# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus ClusterWorkflowExecutionInstance class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

class OMQ::RemoteWorkflowExecutionInstance inherits AbstractCoreWorkflowExecutionInstance {
    private {
        QwfClient wfc;
    }

    constructor(softstring index, *int sync_wfiid, string mode, Workflow wf, *hash<auto> cx, *string reason, *bool recover)
        : AbstractCoreWorkflowExecutionInstance(index, sync_wfiid, mode, wf) {
        # now we can get the client object and create the workflow execution instance
        # in the qwf process
        wfc = SM.getWorkflowClient(wf.workflowid);
        # create the workflow execution instance object in the qwf process
        hash<auto> h = {
            "subsystem": "control",
            "method": "createWorkflowExecutionInstance",
            "args": (index, sync_wfiid, mode, get_cx(cx), reason, recover),
        };
        try {
            doRemoteCommandUnreliable(h);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CLIENT-TERMINATED" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-DEAD") {
                throw "WORKFLOW-START-ERROR", sprintf("remote workflow %s v%s (%d) could not be started; check the "
                    "workflow log for more information", wf.name, wf.version, wf.workflowid);
            }
            rethrow;
        }
    }

    ActionReason getStopReason() {
        return methodGate("getStopReason");
    }

    *hash<auto> execSynchronous() {
        # issue #2547: this must be called with an unreliable call
        return doUnreliableCommand("execSynchronous");
    }

    hash<auto> execSynchronousOnExistingOrder(hash<auto> cx) {
        QDBG_ASSERT(is_sync);
        # issue #2547: this must be called with an unreliable call
        return doUnreliableCommand("execSynchronousOnExistingOrder", get_cx(cx));
    }

    hash<auto> execSynchronousOrderCreated() {
        QDBG_ASSERT(is_sync);
        return doUnreliableCommand("execSynchronousOrderCreated");
    }

    hash<auto> getAllOptions() {
        return methodGate("getAllOptions");
    }

    auto getOption(string f) {
        return methodGate("getOption", f);
    }

    auto getOption(*softlist<auto> field) {
        return methodGate("getOption", field);
    }

    setOption(hash<auto> h) {
        methodGate("setOption", h);
    }

    setupError(hash<auto> ex) {
        methodGate("setupError", ex);
    }

    int inlineInit() {
        return methodGate("inlineInit");
    }

    setupComplete() {
        # issue #2618: must be allowed to fail
        doUnreliableCommandArgs("setupComplete");
    }

    start() {
        methodGate("start");
    }

    *int setStop(*hash<auto> cx, *string reason) {
        try {
            # issue #2855: must be allowed to fail
            return doUnreliableCommandArgs("setStopExtern", (get_cx(cx), reason));
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-WORKFLOW-EXECUTION-INSTANCE") {
                qlog(LoggerLevel::INFO, "%s v%s (%d): ignoring workflow stop error for restarted qwf process: %s: %s",
                    wf.name, wf.version, wf.workflowid, ex.err, ex.desc);
                return -1;
            }
            if (ex.err == "CLIENT-DEAD" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED") {
                qlog(LoggerLevel::INFO, "%s v%s (%d): ignoring workflow stop error for aborted qwf process: %s: %s",
                    wf.name, wf.version, wf.workflowid, ex.err, ex.desc);
                return -1;
            }
            rethrow;
        }
    }

    setDeferredStop(*hash<auto> cx, *string reason) {
        methodGate("setDeferredStop", get_cx(cx), reason);
    }

    setFatalError(hash<auto> ex) {
        methodGate("setFatalError", ex);
    }

    *string stepError(*softstring err, auto info, auto arg) {
        return methodGate("stepError", err, info, arg);
    }

    stepWarning(*string err, auto info) {
        methodGate("stepWarning", err, info);
    }

    auto methodGate(string method) {
        hash<auto> h = {
            "subsystem": "wfi",
            "index": index,
            "method": method,
            "args": argv,
            "tld": tld{"index", "index_map",},
        };
        return doRemoteCommand(h);
    }

    private auto doRemoteCommand(hash<auto> h) {
        *list<string> msgs = wfc.sendCheckResponse(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    private auto doRemoteCommandUnreliable(hash<auto> h) {
        *list<string> msgs = wfc.sendCheckResponseUnreliable(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    # send a command to the server and allow it to fail if the server dies
    private auto doUnreliableCommand(string method) {
        return doUnreliableCommandArgs(method, argv);
    }

    # send a command to the server and allow it to fail if the server dies
    private auto doUnreliableCommandArgs(string method, *softlist<auto> args) {
        hash<auto> h = {
            "subsystem": "wfi",
            "index": index,
            "method": method,
            "args": args,
            "tld": tld{"index", "index_map",},
        };
        *list<string> msgs = wfc.sendCheckResponseUnreliable(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }
}
