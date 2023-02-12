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

/** Remote development test finite state automation.

    Design info: https://git.qoretechnologies.com/qoretechnologies/wiki/-/wikis/Qorus-Remote-Development

    It's a Qorus private class - not exposed to public API.
*/
class RemoteDevelopment::TestProcessFSA inherits RemoteDevelopment::FileUploadProcessFSA {
    private {
        const ALLOWED_OPTIONS = {
            "continue-on-error": "if one of the tests fails, server will continue on execution of the rest",
        };

        int fileIndex = 0;
        TestRequest testRequest;
        list<hash<auto>> testFiles;

        const CONTINUE = "continue";

        list<hash<Status>> statuses;

        string finalStatus = "";
    }

    #! Constructs TestProcessFSA object with given request
    #  Initialize method must be called to initialize the FSA (ProcessFSA method).
    /** @param request containing qtests to be run
        @throw BAD-REQUEST exception in case request is incorrect
    */
    constructor(TestRequest request, string command) : FileUploadProcessFSA(request, command) {
        testRequest = request;
        OptionHelper::checkOptions(testRequest.options, ALLOWED_OPTIONS);
        checkAndSaveTestFiles();
    }

    private setFinalStatus(string status) {
        AutoLock auto_lock(processMutex);
        finalStatus = status;
    }

    #! Returns status hash of this TestProcessFSA
    /** @return request hash containing all information about this TestProcessFSA
    */
    hash<Status> getStatus() {
        hash<Status> result();
        result += {
            "exit_code": 0,
            "stdout": "",
        };

        bool oneTestFailed = False;
        AutoLock auto_lock(processMutex);
        foreach hash<Status> process_status in (statuses) {
            result{"stdout"} += process_status{"stdout"};
            result{"stderr"} += process_status{"stderr"};

            if (process_status.status == STATUS_FAILED) {
                result.exit_code = 1;
                oneTestFailed = True;
            }
        }

        if (!finalStatus.empty()) {
            if (finalStatus == STATUS_FINISHED) {
                result.status = (!oneTestFailed) ? STATUS_FINISHED : STATUS_FAILED;
            } else {
                result.status = finalStatus;
            }
        } else {
            result.status = STATUS_IN_PROGRESS;
        }

        return result;
    }

    private checkAndSaveTestFiles() {
        testFiles = getTestFiles();
        if (testFiles.empty()) {
            throw "BAD-REQUEST", sprintf("The request (%y) doesn't have any qtest files", testRequest.convertToHash());
        }
    }

    # RemoteDevelopment::ProcessFSA method
    private hash<string, hash<StateInfo>> getTransitions() {
        hash<string, hash<StateInfo>> transitions = FileUploadProcessFSA::getTransitions();
        transitions += {
            DONE_STATE: <StateInfo>{
                FSA::INVARIANT: \done(),
                FSA::IS_FINAL: True,
                FSA::TRANSITIONS: {
                    CONTINUE: CREATE_PROCESS_STATE,
                    CANCEL: CANCELED_STATE
                }
            },
            FAIL_STATE: <StateInfo>{
                FSA::INVARIANT: \fail(),
                FSA::IS_FINAL: True,
            }
        };

        return transitions;
    }

    # RemoteDevelopment::FileUploadProcessFSA method
    private string getDestinationFolder() {
        string omq_dir = ENV.OMQ_DIR;
        if (omq_dir.empty()) {
            log(LoggerLevel::DEBUG, "OMQ_DIR variable is not initialized");
            throw "ENV-ERROR", "OMQ_DIR variable is not initialized";
        }
        return omq_dir + Qore::DirSep + "user" + Qore::DirSep;
    }

    # ProcessFSA method
    private list<string> getProcessArgs() {
        list<string> args;
        args += getDestinationFolder() + testFiles[fileIndex].file_name;
        args += getArgList(testFiles[fileIndex].args);

        log(LoggerLevel::DEBUG, "TestProcessFSA::getProcessArgs: args: %y", args);
        return args;
    }

    # ProcessFSA method
    private hash<auto> getProcessOptions() {
        # command should be in path variable (no need to add different path)
        return {};
    }

    #! converts given args to command-line form as list of strings (has to be overriden in child classes)
    private abstract list<string> getArgList(*hash<auto> args);

    #! Returns test files to execute (must be overriden in child classes)
    /** @return list of hashes
    */
    private abstract list<hash<auto>> getTestFiles();

    #! ProcessFSA method is re-implemented: Done state: one process has been finished
    private done() {
        ProcessFSA::done();

        statuses += ProcessFSA::getStatus();

        ++fileIndex;
        if (fileIndex != testFiles.size()) {
            if (status.status == STATUS_FINISHED || testRequest.options{"continue-on-error"}) {
                execute(CONTINUE);
                return;
            }
        }

        setFinalStatus(STATUS_FINISHED);
    }

    #! ProcessFSA method is re-implemented: canceled state
    private canceled() {
        ProcessFSA::canceled();
        setFinalStatus(STATUS_CANCELED);
    }

    private fail() {
        setFinalStatus(STATUS_FAILED);
    }
}
