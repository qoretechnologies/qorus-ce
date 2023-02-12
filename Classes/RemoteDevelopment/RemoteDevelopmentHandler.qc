# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace RemoteDevelopment;

/** RemoteDevelopment::Handler has all information about all remote development requests (deployment, delete, release).
    It stores history in processes hash while Qorus is running.
    The hash has the following structure:
        {
            id: reference_to_processFSA_object,
        }
    Requests older then 1 day (REQUEST_LIFE_TIME) will be removed by clearCache method.
    The method is run every 1h (CLEAR_CACHE_FREQUENCY).
    Now the class creates ThreadPool object with one thread to process requests.

    Also within every request findRecentlyDeployedFiles method is called to check
    if the same files were previously deployed within 1 hour. If so, the warning is returned.

    Design info: https://git.qoretechnologies.com/qoretechnologies/wiki/-/wikis/Qorus-Remote-Development
*/
class RemoteDevelopment::Handler {
    public {
        const REQUEST_LIFE_TIME = 1D;
        const CLEAR_CACHE_FREQUENCY = 1h;
        const REQUEST_TIMEOUT = 3s;
        const FIND_FILES_DEPLOYED_IN = 1h;
    }

    private {
        Sequence idSequence();

        RWLock rwLock();
        hash<string, ProcessFSA> processes;
        ThreadPool threadPool(1, 0, 1);

        date cacheClearedDate;
    }

    constructor() {
        cacheClearedDate = now();
    }

    shutdown() {
        AutoReadLock auto_read_lock(rwLock);
        foreach string id in (keys processes) {
            processes{id}.execute(ProcessFSA::CANCEL);
        }
        threadPool.stopWait();
    }

    hash<auto> getDebugInfo() {
        return {
            "processes": (map {$1.key: $1.value.getStatus()}, processes.pairIterator()),
            "thread_pool": threadPool.toString(),
        };
    }

    private findRecentlyDeployedFile(auto file, *string ignored, reference<auto> result) {
        date current_date = now();

        AutoReadLock auto_read_lock(rwLock);

        # iterate in reverse order to find the latest request that contains the same files
        HashKeyReverseIterator it(processes);
        while (it.next()) {
            ProcessFSA process = it.getKeyValue();
            if (!(process instanceof DeployProcessFSA)) {
                continue;
            }

            if ((current_date - process.getStatus().created) > FIND_FILES_DEPLOYED_IN) {
                # stop iteration if created date is later then 1 hour
                return;
            }

            auto request = cast<DeployProcessFSA>(process).getRequest();
            foreach auto old_file in (request.files) {
                if (old_file.file_name == file.file_name &&
                    old_file.file_content != file.file_content) {

                    result += {file.file_name: DefaultSystemUser};
                    # we have found the latest file, do not check older requests
                    return;
                }
            }
        }
    }

    private hash<auto> findRecentlyDeployedFiles(list<auto> files, *string ignored) {
        hash<auto> result = {};

        {
            AutoReadLock auto_read_lock(rwLock);
            if (processes.empty()) {
                return result;
            }
        }

        # find the same files previously deployed for all files to deploy
        foreach auto file in (files) {
            findRecentlyDeployedFile(file, DefaultSystemUser, \result);
        }

        return result;
    }

    private clearCache() {
        if (now() - cacheClearedDate < CLEAR_CACHE_FREQUENCY) {
            return;
        }

        qlog(LoggerLevel::INFO, "Clearing cache");
        date current_date = now();

        AutoWriteLock auto_write_lock(rwLock);
        foreach string id in (keys processes) {
            ProcessFSA process = processes{id};
            if (process.isInFinalState() &&
                current_date - process.getStatus().created > REQUEST_LIFE_TIME) {

                delete processes{id};
                qlog(LoggerLevel::DEBUG, "clearing request id: %y", id);
            }
        }
        cacheClearedDate = now();
    }

    private start(ProcessFSA processFSA) {
        qlog(LoggerLevel::DEBUG, "Starting");
        clearCache();
        try {
            processFSA.execute(ProcessFSA::START);
        } catch (hash<ExceptionInfo> ex) {
            processFSA.aborted(ex);
        }
    }

    #! Creates a new development request
    /** @param request containing needed information to create the process
        @return CreationStatus hash with request id and eventually list of warnings
        @throw BAD-REQUEST in case request is incorrect
        */
    hash<CreationStatus> createRequest(Request request) {
        int id = idSequence.next();
        request.id = id;

        ProcessFSA processFSA;
        if (request instanceof DeployRequest) {
            qlog(LoggerLevel::DEBUG, "Creating instance of DeployProcessFSA with id %d", id);
            processFSA = new DeployProcessFSA(request);
        } else if (request instanceof DeleteRequest) {
            qlog(LoggerLevel::DEBUG, "Creating instance of DeleteProcessFSA with id %d", id);
            processFSA = new DeleteProcessFSA(request);
        } else if (request instanceof ReleaseRequest) {
            qlog(LoggerLevel::DEBUG, "Creating instance of ReleaseProcessFSA with id %d", id);
            processFSA = new ReleaseProcessFSA(request);
        } else if (request instanceof TestRequest) {
            qlog(LoggerLevel::DEBUG, "Creating instance of TestProcessFSA with id %d", id);

            TestRequest testRequest = cast<TestRequest>(request);
            if (testRequest.numQoreTests() || testRequest.numQoreScripts()) {
                processFSA = new QoreTestProcessFSA(request);
                qlog(LoggerLevel::DEBUG, "QoreTestProcessFSA with id %d created", id);
            } else if (testRequest.numJavaTests()) {
                processFSA = new JavaTestProcessFSA(request);
                qlog(LoggerLevel::DEBUG, "JavaTestProcessFSA with id %d created", id);
            } else if (testRequest.numPythonTests() || testRequest.numPythonScripts()) {
                processFSA = new PythonTestProcessFSA(request);
                qlog(LoggerLevel::DEBUG, "PythonTestProcessFSA with id %d created", id);
            } else if (testRequest.numSchemas()) {
                processFSA = new QoreSchemaProcessFSA(request);
                qlog(LoggerLevel::DEBUG, "QoreSchemaProcessFSA with id %d created", id);
            }
%ifdef QorusDebugInternals
            else {
                throw "ERROR", sprintf("no FSA match for request: %y", request);
            }
%endif
        }

        processFSA.initialize();

        {
            AutoWriteLock auto_write_lock(rwLock);
            processes += {id: processFSA};
            qlog(LoggerLevel::DEBUG, "Added process, id: %y", id);
        }

        qlog(LoggerLevel::DEBUG, "Submiting request with id %y to the ThreadPool", id);
        threadPool.submit(sub () { start(processFSA); });
        qlog(LoggerLevel::DEBUG, "Request with id %y submitted", id);

        hash<CreationStatus> result = <CreationStatus>{"id": id};

        if (request instanceof DeployRequest) {
            DeployRequest deployRequest = cast<DeployRequest>(request);
            hash<auto> recentlyDeployedFiles = findRecentlyDeployedFiles(deployRequest.files, DefaultSystemUser);
            if (!recentlyDeployedFiles.empty()) {
                result += {"warning": map sprintf("File %s was recently deployed", $1.key),
                    recentlyDeployedFiles.pairIterator()};
            }
        }

        return result;
    }

    #! Returns the status of request with given id
    /** @param id id of the request
        @return Status hash with all information about the request
        @throw NOT-FOUND in case request with given id is not found
        */
    hash<auto> getRequestStatus(string id) {
        *ProcessFSA processFSA;
        {
            AutoReadLock auto_read_lock(rwLock);
            processFSA = processes{id};
        }

        if (!processFSA) {
            throw "NOT-FOUND", sprintf("Request id %s cannot be found", id);
        }

        qlog(LoggerLevel::DEBUG, "Found id: %y", id);
        return processFSA.getStatus();
    }

    #! Cancels the request with given id
    /** @param id id of the request
        @param ignored ignored
        @return True if the request was successfully canceled, False if not
        @throw NOT-FOUND in case request with given id is not found
        @throw FORBIDDEN in case user has no permission to cancel the request
        */
    bool cancelRequest(string id, *string ignored) {
        *ProcessFSA processFSA;
        {
            AutoReadLock auto_read_lock(rwLock);
            processFSA = processes{id};
        }

        if (!processFSA) {
            throw "NOT-FOUND", sprintf("Request id %s cannot be found", id);
        }

        qlog(LoggerLevel::DEBUG, "Cancel request id: %y", id);

        return processFSA.execute(ProcessFSA::CANCEL);
    }
}
