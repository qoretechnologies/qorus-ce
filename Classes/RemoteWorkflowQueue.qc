# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus RemoteWorkflowQueue class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

class OMQ::RemoteWorkflowQueue inherits AbstractWorkflowQueue {
    private {
        QwfClient wfc;
    }

    constructor(QwfClient wfc) {
        self.wfc = wfc;
    }

    start() {
        # issue #2647: cluster workflow queues start automatically, and once stopped are not started again in
        # the same process
    }

    stop() {
        # issue #2647: the workflow queue will stop when the process is stopped and is not stopped separately
        # for remote processes
    }

    *string getCacheSummary() {
        return doCommandArgs("getCacheSummary");
    }

    requeueAllRetries() {
        doCommandArgs("requeueAllRetries");
    }

    postSyncEvent(softstring stepid, softint wfiid, softint ind, softint prio, *hash parent_info) {
        doCommandArgs("postSyncEvent", (stepid, wfiid, ind, prio, parent_info));
    }

    updateQueue(softstring stepid, softint wfiid, softint ind, softint prio, softbool corrected, string queuekey, auto data, *hash parent_info) {
        doCommandArgs("updateQueue", (stepid, wfiid, ind, prio, corrected, queuekey, data, parent_info));
    }

    updateSubWorkflowQueue(softstring wfiid, softint stepid, softint ind, softint prio, softint swfiid, *hash parent_info, string stat) {
        doCommandArgs("updateSubWorkflowQueue", (wfiid, stepid, ind, prio, swfiid, parent_info, stat));
    }

    # adds an entry to the workflow instance queue
    addToWorkflowInstanceQueue(softint wfiid, int priority, *hash parent_info, *date scheduled) {
        doCommandArgs("addToWorkflowInstanceQueue", (wfiid, priority, parent_info, scheduled));
    }

    updateRetryDelay(*softint r) {
        doCommandArgs("updateRetryDelay", r);
    }

    updateAsyncDelay(*softint a) {
        doCommandArgs("updateAsyncDelay", a);
    }

    *string getCacheAsString() {
        return doCommandArgs("getCacheAsString");
    }

    auto doCommandArgs(string method, *softlist<auto> args) {
        hash<auto> h = {
            "subsystem": "wfq",
            "method": method,
            "args": args,
        };
        *list<string> msgs = wfc.sendCheckResponse(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto doCommand(string method) {
        return doCommandArgs(method, argv);
    }

    auto doCommandUnreliableArgs(string method, *softlist<auto> args) {
        hash<auto> h = {
            "subsystem": "wfq",
            "method": method,
            "args": args,
        };
        *list<string> msgs = wfc.sendCheckResponseUnreliable(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto doCommandUnreliable(string method) {
        return doCommandUnreliableArgs(method, argv);
    }

    auto doTldCommandArgs(string method, *softlist<auto> args) {
        hash<auto> h = {
            "subsystem": "wfq",
            "method": method,
            "args": args,
            "tld": tld{"cx",},
        };
        *list<string> msgs = wfc.sendCheckResponse(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto doTldCommand(string method) {
        return doTldCommandArgs(method, argv);
    }
}