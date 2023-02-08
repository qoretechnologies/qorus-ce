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

/** Process finite state automation. This class wraps process object.

    Design info: https://git.qoretechnologies.com/qoretechnologies/wiki/-/wikis/Qorus-Remote-Development

    It's a Qorus private class - not exposed to public API.
*/

public namespace RemoteDevelopment;

class ProcessFSA inherits FSA {
    private:internal {
        Process process;
        string processCommand;
    }

    private {
        Mutex processMutex();

        const IDLE_STATE = "idle";
        const CANCELED_STATE = "canceled";
        const CREATE_PROCESS_STATE = "createProcess";
        const WAITING_STATE = "waiting";
        const DONE_STATE = "done";

        const DONE = "done";
        const FAIL = "fail";

        # the maximum number of bytes to read from output streams
        const DefaultOutputSize = 32 * 1024;

        hash<Status> status();
    }
    public {
        const START = "start";
        const CANCEL = "cancel";
    }

    #! Constructs ProcessFSA object with given process command. Initialize method must be called to initialize the FSA
    /** @param process_command the name of the process to be wrapped
        */
    constructor(string process_command) : FSA() {
        processCommand = process_command;
    }

    #! Initializes ProcessFSA object
    synchronized initialize() {
        FSA::initialize(getTransitions(), IDLE_STATE);
    }

    #! Aborted state: no process, error setting update
    aborted(hash<ExceptionInfo> ex) {
        log(LoggerLevel::ERROR, "Aborting process: %s", get_exception_string(ex));

        AutoLock auto_lock(processMutex);
        if (process) {
            process.terminate();
        }

        status += <Status>{
            "status": STATUS_FAILED,
            "stdout": "",
            "stderr": sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc),
            "exit_code": -1,
        };
    }

    #! Reimplement this method in a child class if changes to transitions hash are needed
    private hash<string, hash<StateInfo>> getTransitions() {
        return {
            IDLE_STATE: <StateInfo>{
                FSA::INVARIANT: NOTHING,
                FSA::TRANSITIONS: {
                    START: CREATE_PROCESS_STATE,
                    CANCEL: CANCELED_STATE
                }
            },
            CREATE_PROCESS_STATE: <StateInfo>{
                FSA::INVARIANT: \createProcess(),
                FSA::TRANSITIONS: {
                    START: WAITING_STATE,
                    CANCEL: CANCELED_STATE
                }
            },
            WAITING_STATE: <StateInfo>{
                FSA::INVARIANT: \waiting(),
                FSA::TRANSITIONS: {
                    DONE: DONE_STATE,
                    CANCEL: CANCELED_STATE
                }
            },
            DONE_STATE: <StateInfo>{
                FSA::INVARIANT: \done(),
                FSA::IS_FINAL: True,
            },
            CANCELED_STATE: <StateInfo>{
                FSA::INVARIANT: \canceled(),
                FSA::IS_FINAL: True,
            }
        };
    }

    #! Reimplement this method in child classes to add args to the process
    private list<string> getProcessArgs() {
        return new list<string>();
    }

    #! Reimplement this method in child classes to add options to the process
    private hash<auto> getProcessOptions() {
        return {
            # the variable path accepts only list of paths
            "path": (ENV.OMQ_DIR + "/bin",)
        };
    }

    #! Returns status hash of this ProcessFSA
    /** @return request hash containing all information about this ProcessFSA
    */
    hash<Status> getStatus() {
        AutoLock al(processMutex);
        return status;
    }

    #! CreateProcess state: Process object is created
    private createProcess() {
        log(LoggerLevel::DEBUG, "ProcessFSA::createProcess (%y)", self.className());
        {
            AutoLock auto_lock(processMutex);
            list<string> args = getProcessArgs();
            log(LoggerLevel::INFO, "Arguments to pass to the %y process: %y", processCommand, args);

            hash<auto> options = getProcessOptions();
            log(LoggerLevel::INFO, "Options to pass to the %y process: %y", processCommand, options);

            process = new Process(processCommand, args, options);
        }
        execute(START);
    }

    #! Waiting state: wait method of the process object is called
    private waiting() {
        {
            AutoLock auto_lock(processMutex);
            status += {
                "status": STATUS_IN_PROGRESS,
                "stdout": processCommand + " is in progress",
            };
        }

        log(LoggerLevel::DEBUG, "Waiting for process object to be finished");
        try {
            process.wait();
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "Error waiting for process: %s: %s", ex.err, ex.desc);
        }
        execute(DONE);
    }

    #! Done state: process has been finished
    private done() {
        int exit_code = 1;

        AutoLock auto_lock(processMutex);
        exit_code = process.exitCode();

        status += <Status>{
            "status": exit_code ? STATUS_FAILED : STATUS_FINISHED,
            "stdout": process.readStdout(DefaultOutputSize) ?? "",
            "stderr": process.readStderr(DefaultOutputSize) ?? "",
            "exit_code": exit_code,
        };
        delete process;
    }

    #! Canceled state: canceled by user
    private canceled() {
        AutoLock auto_lock(processMutex);
        if (process) {
            process.terminate();
        }

        status += {
            "status": STATUS_CANCELED,
            "stdout": "canceled by user",
        };
        delete process;
    }

    #! log method;
    private log(int log_level, string format) {
        qlog_args(log_level, format, argv);
    }
}
