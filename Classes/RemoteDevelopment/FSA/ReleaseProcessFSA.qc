# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

%requires process
%requires FsUtil

public namespace RemoteDevelopment;

/** Remote development release finite state automation.

    Design info: https://bugs.qoretechnologies.com/projects/qorus/wiki/Qorus_remote_development

    private class; not exposed in the public API
*/

class RemoteDevelopment::ReleaseProcessFSA inherits RemoteDevelopment::FileUploadProcessFSA {
    private:internal {
        Process unarchiveProcess;

        string omqDir;

        TmpDir tmpDir;
    }
    private {
        const ALLOWED_OPTIONS = {
            "allow-redef": "Allows dangerous workflow redefinitions (for dev only)",
            "force": "Force schema verification/downgrade with user schemas",
            "validate": "Validate all functions recursively",
            "reload": "Reload interfaces in the server",
            "verbosity-level": "Sets verbosity level (greater value = more info)",
            "to-user": "Deploy tar releases directly to $OMQ_DIR/user",
        };
        const OPTIONS_TO_OLOAD_ARGS = {
            "allow-redef": "A",
            "force": "f",
            "validate": "l",
            "reload": "R",
            "verbosity-level": "v",
        };

        const UNARCHIVE_STATE = "unarchive";
        const UNARCHIVING_STATE = "unarchiving";

        ReleaseRequest releaseRequest;
    }

    #! Constructs ReleaseProcessFSA object with given request
    #  Initialize method must be called to initialize the FSA (ProcessFSA method).
    /** @param request containing files to deployed, id of the request, user name and options
        @throw BAD-REQUEST exception in case request is incorrect
    */
    constructor(ReleaseRequest request) : FileUploadProcessFSA(request) {
        releaseRequest = request;
        OptionHelper::checkOptions(releaseRequest.options, ALLOWED_OPTIONS);

        tmpDir = new TmpDir("qorus_release_");

        omqDir = ENV.OMQ_DIR;
        if (omqDir.empty()) {
            log(LoggerLevel::DEBUG, "OMQ_DIR variable is not initialized");
            throw "ENV-ERROR", "OMQ_DIR variable is not initialized";
        }
        omqDir += Qore::DirSep + "user";
    }

    # ProcessFSA method
    private hash<string, hash<StateInfo>> getTransitions() {
        hash<string, hash<StateInfo>> transitions = FileUploadProcessFSA::getTransitions();
        # only unarchive to $OMQ_DIR/user if the option is set, otherwise deploy immediately with oload
        if (releaseRequest.options."to-user") {
            transitions += {
                UNARCHIVE_STATE: <StateInfo>{
                    FSA::INVARIANT: \unarchive(),
                    FSA::TRANSITIONS: {
                        START: UNARCHIVING_STATE,
                        CANCEL: CANCELED_STATE
                    }
                },
                UNARCHIVING_STATE: <StateInfo>{
                    FSA::INVARIANT: \unarchiving(),
                    FSA::TRANSITIONS: {
                        DONE: CREATE_PROCESS_STATE,
                        CANCEL: CANCELED_STATE,
                        FAIL: FAIL_STATE
                    }
                }
            };

            transitions{UPLOADING_STATE}{FSA::TRANSITIONS}{DONE} = UNARCHIVE_STATE;
        }
        return transitions;
    }
    ###

    # RemoteDevelopment::FileUploadProcessFSA method
    private string getDestinationFolder() {
        return tmpDir.path;
    }
    ###

    # ProcessFSA method
    private list<string> getProcessArgs() {
        list<string> args;

        args += OptionHelper::convertOptionsToOloadArguments(releaseRequest.options, OPTIONS_TO_OLOAD_ARGS);
        log(LoggerLevel::INFO, "release options: %y", releaseRequest.options);
        # only unarchive to $OMQ_DIR/user if the option is set, otherwise deploy immediately with oload
        if (releaseRequest.options."to-user") {
            *string ext = (releaseRequest.files[0].file_name =~ x/(\.(?:tar|tar\.bz2|tar\.gz|tar\.Z|tbz2|tgz|tZ))$/)[0];
            if (!ext) {
                throw "REST-ARG-ERROR", sprintf("cannot determine release extension from %y",
                    releaseRequest.files[0].file_name);
            }
            args += omqDir + Qore::DirSep + basename_ext(releaseRequest.files[0].file_name, ext) + ".qrf";
        } else {
            args += getDestinationFolder() + Qore::DirSep + releaseRequest.files[0].file_name;
        }

        return args;
    }
    ###

    #! Unarchive to $OMQ_DIR/user: only performed if the "to-user" option is set
    private unarchive() {
        {
            AutoLock auto_lock(processMutex);

            list<string> args = ("-xvf",);
            # It's assumed that there is only one file to be released
            args += getDestinationFolder() + Qore::DirSep + releaseRequest.files[0].file_name;

            args += "-C";
            args += omqDir;

            log(LoggerLevel::INFO, "Arguments to pass to the unarchive process: %y", args);
            unarchiveProcess = new Process("tar", args);
        }
        execute(START);
    }

    #! Unarchiving to $OMQ_DIR/user state: only valid if the "to-user" option is set
    private unarchiving() {
        {
            AutoLock auto_lock(processMutex);
            status += {
                "status": STATUS_IN_PROGRESS,
                "stdout": "Unarchiving is in progress",
            };
        }

        log(LoggerLevel::DEBUG, "Waiting for unarchive process object to be finished");
        unarchiveProcess.wait();

        int exit_code;
        {
            AutoLock auto_lock(processMutex);
            exit_code = unarchiveProcess.exitCode();

            status += <Status>{
                "status": exit_code > 0 ? STATUS_FAILED : STATUS_IN_PROGRESS,
                "stdout": unarchiveProcess.readStdout(DefaultOutputSize) ?? "",
                "stderr": unarchiveProcess.readStderr(DefaultOutputSize) ?? "",
                "exit_code": exit_code
            };
        }

        if (exit_code > 0) {
            execute(FAIL);
        } else {
            execute(DONE);
        }
    }

    private canceled() {
        {
            AutoLock auto_lock(processMutex);
            if (unarchiveProcess) {
                unarchiveProcess.terminate();
            }
            delete unarchiveProcess;
        }

        ProcessFSA::canceled();
    }
    ###
}
