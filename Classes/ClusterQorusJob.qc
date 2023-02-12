# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Cluster Job Class Definition

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

class OMQ::ClusterQorusJob inherits LocalQorusJob {
    private:internal {
        bool initialized = False;
        bool stop_called = False;
    }

    constructor(int jobid, string name, string version) : LocalQorusJob(jobid, name, version) {
    }

    # returns True if initialized, False if not
    synchronized bool init(hash<auto> jh, bool skip_checks, *string reason) {
        # issue #2714: in case of a race condition with job recoveries; we need to ensure that init() is
        # only called once
        if (initialized) {
            logInfo("already initialized; ignoring superfluous initialization call");
            return False;
        }
        QDBG_LOG("initializing job; reason: %y", reason);
        initialized = True;
        on_success Qorus.setStateRunning();
        try {
            LocalQorusJob::init(jh, skip_checks, reason);
        } catch (hash<ExceptionInfo> ex) {
            string err = !Qorus.getDebugSystem()
                ? sprintf("Unable to initialize job: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc)
                : sprintf("Unable to initialize job: %s", get_exception_string(ex));
            logInfo(err);
            rethrow;
        }

        # issue #3198: initialize mapper objects after service is created
        Qorus.setupMappers();

        return True;
    }

    # make sure stop is called only once
    synchronized stop() {
        if (!initialized || stop_called) {
            return;
        }
        stop_called = True;
        LocalQorusJob::stop();
    }

    auto deserialize(data d) {
        return pgm.callFunction("_qorus_deserialize", d);
    }

    *int auditUserEvent(string user_event, *string info1, *string info2) {
        return Qorus.jobManager.auditUserEventExtern(name, job_instanceid, user_event, info1, info2);
    }

    # returns True if the job should be stopped because the expiry date is on or before the next trigger date
    bool setExpiry(*date expiry) {
        return setJobExpiry(expiry);
    }

    logFatal(string msg) {
        Qorus.logArgs(LoggerLevel::FATAL, msg, argv);
    }

    logError(string msg) {
        Qorus.logArgs(LoggerLevel::ERROR, msg, argv);
    }

    logWarn(string msg) {
        Qorus.logArgs(LoggerLevel::WARN, msg, argv);
    }

    logInfo(string msg) {
        Qorus.logArgs(LoggerLevel::INFO, msg, argv);
    }

    logDebug(string msg) {
        Qorus.logArgs(LoggerLevel::DEBUG, msg, argv);
    }

    logTrace(string msg) {
        Qorus.logArgs(LoggerLevel::TRACE, msg, argv);
    }

    logArgs(int lvl, string msg) {
        Qorus.logArgs(lvl, msg, argv);
    }

    setStopReason(*string reason) {
        Qorus.jobManager.setStopReasonExtern(name, reason);
    }

    private updateMappers(*list<auto> mapper_ids) {
        Qorus.updateMappers(mapper_ids);
    }
}
