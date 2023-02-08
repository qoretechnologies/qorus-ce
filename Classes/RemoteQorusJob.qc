# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus qorus-core remote job class definition

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

class OMQ::RemoteQorusJob inherits AbstractQorusCoreJob {
    private:internal {
        # expiry date
        *date expiry_date;

        # active flag
        softbool active;

        hash<ClusterProcInfo> qjobp;

        QjobClient jobc;

        const RecoverRestartReason = "recovered qjob process after an abnormal termination";
    }

    constructor(hash<auto> jh, bool skip_checks = False, *string reason, *bool already_running) :
            AbstractQorusCoreJob(jh) {
        olog(LoggerLevel::INFO, "starting remote job %s v%s (%d)", name, version, jobid);
        active = jh.active;
        expiry_date = jh.expiry_date;

        # if the process is already running, then this will not start it again
        # but rather just set up the process client object
        startProcess();

        if (!already_running) {
            initIntern(jh, skip_checks, reason);
        }
    }

    destructor() {
        if (qjobp) {
            # issue #2564: always delete clients before stopping the process
            delete jobc;
%ifdef QorusDebugInternals
            int stop_tid =
%endif
            background stopProcessBackground(remove qjobp);
            QDBG_LOG("stopping qjob process %s v%s (%d) in TID %d", name, version, jobid, stop_tid);
        }
    }

    startImpl() {
        doCommandArgs("startImpl");
        Qorus.runIndependent(qjobp);
    }

    recover(hash<auto> jh, bool skip_checks) {
        initIntern(jh, skip_checks, RecoverRestartReason);
    }

    private initIntern(hash<auto> jh, bool skip_checks, *string reason) {
        try {
            QDBG_LOG("RemoteQorusJob::initIntern() %s v%s (%d)", name, version, jobid);
            bool initialized = doUnreliableCommandArgs("init", (jh, skip_checks, reason));
            if (initialized) {
                logStartJob(reason);
                subscribeToLogIfNeeded();
            } else {
                olog(LoggerLevel::INFO, "job %s v%s (%d) already initialized", jh.name, jh.version, jh.jobid);
            }
        } catch (hash<ExceptionInfo> ex) {
            stopProcess();
            rethrow;
        }
    }

    /*
    # must be called in the JobManager lock
    recoverResetRefs() {
        # signal any waiters immediately on exit
        if (refs > 0) {
            refs = 0;
            rcond.broadcast();
        }
    }
    */

    *date getExpiryDate() {
        return expiry_date;
    }

    bool isActive() {
        return active;
    }

    # runs the job immediately
    hash<JobResultInfo> runNow() {
        # must be made with an unreliable call
        return doUnreliableCommandArgs("runNow");
    }

    bool isRunning() {
        return doCommandArgs("isRunning");
    }

    bool setExpiry(*date expiry) {
        expiry_date = expiry;
        return doCommandArgs("setExpiry", expiry);
    }

    setOptions(hash<auto> new_opts) {
        doCommandArgs("setOptions", new_opts);
    }

    auto getOption(string field) {
        return doCommandArgs("getOption", field);
    }

    auto getOption(auto field) {
        return doCommandArgs("getOption", field);
    }

    hash<auto> getInfo() {
        return doCommandArgs("getInfo");
    }

    stopNoWait() {
        doCommandArgs("stopNoWait");
    }

    stop() {
        # ignore process aborts if the remote stop() call fails
        try {
            doUnreliableCommandArgs("stop");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "CLIENT-ABORTED") {
                rethrow;
            }
            olog(LoggerLevel::INFO, "job %s v%s (%d) process aborted during stop() call", name, version, jobid);
        }
    }

    aborted() {
        # NOTE: called in the job manager lock; remove the job process hash here, so that when the object is
        # destroyed, qorus-core will not try to stop a process that does not exist
        remove qjobp;
        AbstractQorusCoreJob::aborted();
    }

    setStopReason(*string reason) {
        stopreason.set(tld.cx, reason);
    }

    # if log streaming is requested, subscribe to it
    subscribeToLogIfNeeded() {
        if (Qorus.eventLog.isJobLogRequested(jobid)) {
            subscribeToLog();
        }
    }

    # subscribes to the job's log if not subscribed yet
    subscribeToLog() {
        jobc.sendCheckResponse(CPC_CORE_LOG_SUBSCRIBE, NOTHING, CPC_OK);
    }

    # unsubscribes from the job's log if subscribed
    unsubscribeFromLog() {
        jobc.sendCheckResponse(CPC_CORE_LOG_UNSUBSCRIBE, NOTHING, CPC_OK);
    }

    *Program getProgram() {
    }

    private hash<auto> getDebugInfoImpl() {
        return {};
    }

    private auto doCommand(string method) {
        return doCommandArgs(method, argv);
    }

    private auto doCommandArgs(string method, *softlist<auto> args, *hash<auto> my_tld) {
        hash<auto> h = {
            "subsystem": "job",
            "method": method,
            "args": args,
            "tld": my_tld,
        };
        *list<string> msgs = jobc.sendCheckResponse(CPC_QJOB_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    # send a command to the server and allow it to fail if the server dies
    private auto doUnreliableCommand(string method) {
        return doUnreliableCommandArgs(method, argv);
    }

    # send a command to the server and allow it to fail if the server dies
    private auto doUnreliableCommandArgs(string method, *softlist<auto> args, *hash<auto> my_tld) {
        hash<auto> h = {
            "subsystem": "job",
            "method": method,
            "args": args,
            "tld": my_tld,
        };
        *list<string> msgs = jobc.sendCheckResponseUnreliable(CPC_QJOB_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    private stopProcess() {
        QDBG_LOG("stopping qjob process %s v%s (%d)", name, version, jobid);
        QDBG_ASSERT(qjobp);
        # issue #2564: always delete clients before stopping the process
        delete jobc;
        # stop the qjob process
        Qorus.stopProcess(qjobp);
        delete qjobp;
        QDBG_LOG("stopped");
    }

    private:internal startProcess() {
        # start qjob process
        QDBG_LOG("starting qjob process %s v%s (%d)", name, version, jobid);
        # start cluster process
        qjobp = Qorus.startJobProcess(self).info;
        jobc = new QjobClient(Qorus, name, version, jobid);
        QDBG_LOG("started qjob process %s v%s (%d)", name, version, jobid);
    }

    private:internal static stopProcessBackground(hash<ClusterProcInfo> qjobp) {
        QDBG_ASSERT(qjobp);
        # must stop job synchronously or there can be a race condition with job terminations
        # and restarts if performed in the background
        Qorus.stopProcess(qjobp);
        QDBG_LOG("stopped");
    }

    logFatal(string msg) {
        Qorus.logFatal(vsprintf("OMQ: " + msg, argv));
    }

    logError(string msg) {
        Qorus.logError(vsprintf("OMQ: " + msg, argv));
    }

    logWarn(string msg) {
        Qorus.logWarn(vsprintf("OMQ: " + msg, argv));
    }

    logInfo(string msg) {
        Qorus.logInfo(vsprintf("OMQ: " + msg, argv));
    }

    logDebug(string msg) {
        Qorus.logDebug(vsprintf("OMQ: " + msg, argv));
    }

    logTrace(string msg) {
        Qorus.logTrace(vsprintf("OMQ: " + msg, argv));
    }

    # send request to remote process to update logger
    updateLoggerImpl(*hash<LoggerParams> params) {
        hash<auto> h = {
            "method": "updateLogger",
            "args": params,
        };
        jobc.sendCheckResponse(CPC_INTERFACE_CALL_METHOD, h, CPC_OK);
    }

    # send request to remote process to rotate log files
    rotateLogFiles() {
        hash<auto> h = {
            "method": "rotateLogFiles",
        };
        jobc.sendCheckResponse(CPC_INTERFACE_CALL_METHOD, h, CPC_OK);
    }
}
