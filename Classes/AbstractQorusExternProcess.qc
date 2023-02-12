# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

# for filesystem handling
%requires FsUtil

/**
    Base class for 3rd party processes
*/
class AbstractQorusExternProcess inherits AbstractQorusProcess {
    public {
        #! the delay after sending a SIGTERM until the process is killed with -9
        const EXTERN_PROC_STOP_DELAY = 30s;
    }

    private {
        #! logger params
        *hash<LoggerParams> loggerParams;

        #! standard out/err wrapper
        LogPipeWrapper logWrapper;

        #! the path to the log FIFO
        string logPipePath;

        #! polling interface for checking for termination
        const TERM_POLL_INTERVAL = 250ms;
    }

    constructor(AbstractQorusProcessManager parent, string node, string host, string name, *hash<LoggerParams> loggerParams)
        : AbstractQorusProcess(parent, node, host, name, "-") {
        self.loggerParams = loggerParams;
        logPipePath = LogPipeWrapper::getLogPipePath(getName());
    }

    updateLogger(*hash<LoggerParams> params) {
        if (logWrapper) {
            logWrapper.updateLogger(params);
        }
        logInfo("%s has been updated with params: %y", getName(), params);
    }

    private string getStartMsg() {
        return "start";
    }

    # override
    bool stop() {
        stopLogWrapper();
        logInfo("stopping %s", getName());
        setStatus(CS_STOPPING);
        if (localProcess()) {
            killProcess();
        } else {
            parent.stopProcessInPassiveMaster(self);
        }

        setStatus(CS_IDLE);
        logInfo("%s %y: stopped process PID %d", getName(), getId(), getPid());
        return True;
    }

    private stopLogWrapper() {
        if (logWrapper) {
            logInfo("stopping Prometheus output wrapper threads");
            delete logWrapper;
        }
    }

    private Process startExternProcess(list<string> args) {
        logDebug("starting %s with args: %y", getName(), args);

        # start new output wrapper; create FIFO first before starting process
        on_error {
            delete logWrapper;
        }
        createLogWrapper();

        # start process with stdout / stderr redirected to the pipe
        File log();
        log.open2(logPipePath, O_APPEND | O_WRONLY);
        hash<auto> opts = {
            "stdout": log,
            "stderr": log,
        };
        return new Process(getName(), args, opts);
    }

    private killProcess() {
        Qore::kill(getPid(), Qore::SIGTERM);
        # for some reason qproc.wait() is not working reliably with external processes
%ifdef QORUS_WAIT_EXTERAL_QPROC
        if (child) {
            if (qproc.wait(EXTERN_PROC_STOP_DELAY)) {
               return;
            }
        }
%endif
        # wait for process to terminate
        date start = now_us();
        while (True) {
            if (!Process::checkPid(getPid())) {
                return;
            }
            if ((now_us() - start) >= EXTERN_PROC_STOP_DELAY) {
                break;
            }
            usleep(TERM_POLL_INTERVAL);
        }

        logInfo("timed out waiting for %s process to terminate after: %y; killing process", getName(),
            EXTERN_PROC_STOP_DELAY);
        terminate();
    }

    # override
    private checkStart() {
        if (running()) {
            logDebug("%s successfully started", getName());
            setStatusIntern(CS_RUNNING);
        } else {
            logError("failed to start %s", getName());
            setStatusIntern(CS_ERR);
        }
    }

    #! returns the local Qorus URL
    /** @note also duplicated as UserApi::qorusGetLocalUrl()
    */
    static string qorusGetLocalUrl(*string username, *string password) {
        return Qorus.options.getClientUrl();
    }

    #! returrns a URL from an option value
    static string getUrlFromOption(string prot, softstring opt, *string username, *string password) {
        prot += "://";
        if (username && password) {
            prot += sprintf("%s:%s@", username, password);
        }

        if (opt =~ /:/) {
            # convert "0.0.0.0", "::", and "[::]" to "localhost"
            opt =~ s/^(0.0.0.0|::|\[::\]):/localhost:/;
            return sprintf("%s%s", prot, opt);
        }
        if (opt =~ /^\//) {
            return sprintf("%ssocket=%s", prot, encode_url(opt, True));
        }
        return sprintf("%slocalhost:%d", prot, opt);
    }

    #! creates the log wrapper
    private abstract createLogWrapper();
}
