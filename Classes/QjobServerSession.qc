# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus QjobServerSession class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

class OMQ::QjobServerSession inherits OMQ::ServerSessionBase {
    private {
        int jobid;
        int recovery_count;
    }

    constructor(int sessionid, int jobid) : ServerSessionBase() {
        id = sessionid;
        self.jobid = jobid;
    }

    checkRecover(Audit audit, string trigger, bool server = True) {
        # check system properties
        checkSystemProperties();

        softint open = cast<ServerSQLInterface>(sqlif).getJobSessionStatus(jobid);
        if (!open) {
            logInfo("DB %y: the job session for jobid %d sessionid %d does not need recovery", desc, jobid, id);
            return;
        }

        recover(audit, trigger);
    }

    # send a recovery message to qorus-core for a WS event
    private jobRecoveryComplete(hash<JobRecoveryInfo> res) {
        # QDBG_ code must be all on one line
        QDBG_LOG("QwfServerSession::jobRecoveryComplete() posting job recovery complete info for %y %y %y: %y", Qorus.interfaceName, Qorus.interfaceVersion, jobid, res);
        Qorus.events.postJobRecovered(tld.cx, Qorus.interfaceName, Qorus.interfaceVersion, jobid);
    }

    hash<JobRecoveryInfo> getJobsToRecover(softint sid, Audit audit, string trigger) {
        return sqlif.recoverJobs(sid, audit, trigger, jobid);
    }

    private recover(Audit audit, string trigger) {
        logInfo("DB %y: starting recovery of job session for jobid %d sessionid %d", desc, jobid, id);
        audit.systemRecoveryStart(trigger, sprintf("%d jobid %d", id, jobid));

        # issue #3249: find all sessions with open job instances and recover them
        *list<int> sessionids = cast<ServerSQLInterface>(sqlif).getOpenSessionsWithJobs(jobid);
        logInfo("DB %y: sessions with open job instances: %y", sessionids);
        string jstr;
        foreach int id in (sessionids) {
            if (jstr) {
                jstr += "; ";
            }
            jstr += recoverJobs(id, audit, trigger);

            # log job session recovery
            logInfo("DB %y: jobid %d sessionid %d successfully recovered", desc, jobid, id);
        }

        audit.systemRecoveryComplete(trigger, jstr ?? "no sessions needed recovery");
    }

    private openDbSessionImpl() {
        omqp.exec("update jobs set open = %v where jobid = %v", 1, jobid);
    }

    private closeDbSessionImpl() {
        omqp.exec("update jobs set open = %v where jobid = %v", 0, jobid);
    }

    private logOpenSessionImpl() {
        logInfo("DB %y: starting instance", desc);
    }

    private logOpenedSessionImpl() {
        logInfo("DB %y: opened jobid %d session id: %d", desc, jobid, id);
    }

    private logClosedSessionImpl() {
        logInfo("DB %y: closed jobid %d session id: %d", desc, jobid, id);
    }

    private logErrorClosingSessionImpl(hash<ExceptionInfo> ex) {
        logInfo("DB %y: unable to close jobid %d session id %d: %s: %s", desc, jobid, id, ex.err, ex.desc);
    }
}
