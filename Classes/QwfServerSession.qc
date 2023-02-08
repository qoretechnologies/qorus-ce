# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus QwfServerSession class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

class OMQ::QwfServerSession inherits OMQ::ServerSessionBase {
    private {
        int wfid;
        int recovery_count;
    }

    constructor(int sessionid, int wfid) : ServerSessionBase() {
        id = sessionid;
        self.wfid = wfid;
    }

    checkRecover(Audit audit, string trigger, bool server = True) {
        # check system properties
        checkSystemProperties();

        softint open = cast<ServerSQLInterface>(sqlif).getWorkflowSessionStatus(wfid);
        if (!open) {
            logInfo("DB %y: the workflow session for workflowid %d sessionid %d does not need recovery", desc, wfid, id);
            return;
        }

        recover(audit, trigger);
    }

    # send a recovery message to qorus-core for a WS event
    private workflowRecoveryComplete(hash<WorkflowRecoveryInfo> res) {
        QDBG_LOG("QwfServerSession::workflowRecoveryComplete() posting workflow recovery complete info for %y %y %y: %y", Qorus.interfaceName, Qorus.interfaceVersion, Qorus.interfaceId, res);
        Qorus.events.postWorkflowRecovered(tld.cx, Qorus.interfaceName, Qorus.interfaceVersion, Qorus.interfaceId);
    }

    # selects minimum and maximum workflow instance ID values for recovery
    private hash initSessionRecovery(string sid) {
        return sqlif.sessionRecoverInit(sid, wfid);
    }

    private hash sessionDbRecoverPart(string sid, hash step, Audit audit, string trigger) {
        return sqlif.sessionRecoverPart(sid, wfid, step.min, step.max, audit, trigger);
    }

    private recover(Audit audit, string trigger) {
        logInfo("DB %y: starting recovery of workflow session for workflowid %d sessionid %d", desc, wfid, id);
        audit.systemRecoveryStart(trigger, sprintf("%d workflowid %d", id, wfid));

        # issue #3249: find all sessions with orders and recover them
        *list<int> sessionids = cast<ServerSQLInterface>(sqlif).getOpenSessionsWithOrders(wfid);
        logInfo("DB %y: sessions with open workflow orders: %y", sessionids);
        string wstr;
        foreach int id in (sessionids) {
            if (wstr) {
                wstr += "; ";
            }
            wstr += recoverWorkflows(id, audit, trigger);

            # log workflow session recovery
            logInfo("DB %y: workflowid %d sessionid %d successfully recovered", desc, wfid, id);
        }

        audit.systemRecoveryComplete(trigger, wstr ?? "no sessions needed recovery");
    }

    private openDbSessionImpl() {
        omqp.exec("update workflows set open = %v where workflowid = %v", 1, wfid);
    }

    private closeDbSessionImpl() {
        omqp.exec("update workflows set open = %v where workflowid = %v", 0, wfid);
    }

    private logOpenSessionImpl() {
        logInfo("DB %y: starting instance", desc);
    }

    private logOpenedSessionImpl() {
        logInfo("DB %y: opened workflowid %d session id: %d", desc, wfid, id);
    }

    private logClosedSessionImpl() {
        logInfo("DB %y: closed workflowid %d session id: %d", desc, wfid, id);
    }

    private logErrorClosingSessionImpl(hash<ExceptionInfo> ex) {
        logInfo("DB %y: unable to close workflowid %d session id %d: %s: %s", desc, wfid, id, ex.err, ex.desc);
    }
}
