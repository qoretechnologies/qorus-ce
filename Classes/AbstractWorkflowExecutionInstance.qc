# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus AbstractWorkflowExecutionInstance class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

class OMQ::AbstractWorkflowExecutionInstance {
    public {
        Workflow wf;
        string mode;
        date starttime = now_us();
    }

    private {
        # workflow execution instance ID
        string index;
        # is this a synchronous workflow execution instance
        bool is_sync;
        *int sync_wfiid;
    }

    constructor(softstring index, *int sync_wfiid, string mode, Workflow wf) {
        QDBG_LOG("AbstractWorkflowExecutionInstance::constructor() wf %s (%d) index: %y starttime: %y", wf.name,
            wf.workflowid, index, starttime);
        self.index = index;
        self.sync_wfiid = sync_wfiid;
        self.mode = mode;
        self.wf = wf;
        is_sync = sync_wfiid.toBool();
    }

    string getID() {
        return index;
    }

    # returns True if this is a temporary workflow execution instance
    bool isTemp() {
        return (index =~ /^temp-/);
    }

    bool isSync() {
        return is_sync;
    }

    *int getSyncOrderId() {
        return sync_wfiid;
    }

    abstract ActionReason getStopReason();

    abstract *hash<auto> execSynchronous();

    abstract hash<auto> execSynchronousOnExistingOrder(hash<auto> cx);

    abstract hash<auto> execSynchronousOrderCreated();

    abstract hash<auto> getAllOptions();

    abstract auto getOption(string f);

    abstract auto getOption(*softlist field);

    abstract setOption(hash<auto> h);

    abstract setupError(hash<auto> ex);

    abstract int inlineInit();

    abstract setupComplete();

    abstract start();

    abstract *int setStop(*hash<auto> cx, *string reason);

    abstract setFatalError(hash<auto> ex);

    abstract *string stepError(*softstring err, auto info, auto arg);

    abstract stepWarning(*string err, auto info);

    static string generateUniqueKey() {
       return sprintf("OMQ-SYS-%d-%d-%d", tld.wfe.workflow_instanceid, tld.stepID, tld.ind);
    }
}
