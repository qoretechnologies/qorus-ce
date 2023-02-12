# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus AbstractCoreWorkflowExecutionInstance class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

class OMQ::AbstractCoreWorkflowExecutionInstance inherits AbstractWorkflowExecutionInstance {
    private {
        # start event flag
        bool start_event = False;
    }

    public {
        # start workflow audit event ID
        *int a_start;
    }

    constructor(softstring index, *int sync_wfiid, string mode, Workflow wf) : AbstractWorkflowExecutionInstance(index, sync_wfiid, mode, wf) {
    }

    startEvents(*hash cx, *hash opts) {
        QDBG_LOG("RemoteWorkflowExecutionInstance::startEvents index %y", index);
        start_event = True;
        Qorus.events.postWorkflowStart(cx, wf.name, wf.version, wf.workflowid, index, mode, is_sync, opts, wf.autostart);
        a_start = Qorus.audit.startWorkflow(cx, wf.workflowid, mode, index, opts);
        # update starttime to effective startup time
        starttime = now_us();
    }

    stopEvents(ActionReason stopreason) {
        softint wfid = wf.workflowid;

        # create audit record
        if (a_start) {
            Qorus.audit.stopWorkflow(a_start, wfid, index, stopreason.getReason(), stopreason.getWho(), stopreason.getSource());
        }

        # post stop event
        if (start_event) {
            # in case a wf is stopped after it's been deleted and no more autostart info is available in the cache, we send autostart = 0
            Qorus.events.postWorkflowStop(stopreason.getContext(), wf.name, wf.version, wfid, index, mode, is_sync, Qorus.qmm.lookupWorkflow(wfid).autostart ?? 0);
        }
    }

    hash<auto> getInfo() {
        # removed: status, iterations, errors, warnings
        return {
            "name": wf.name,
            "version": wf.version,
            "mode": mode,
            "totalSegments": wf.segment.size(),
            "starttime": starttime,
            "sync": is_sync,
            "sync_wfiid": sync_wfiid,
            "executionID": index,
            "workflowid": wf.workflowid,
            "remote": wf.remote,
            "process": wf.remote ? Qorus.qmm.getWorkflowProcess(wf.workflowid) : NOTHING,
            "groups": Qorus.rbac.getWorkflowGroups(wf.workflowid),
            "alerts": Qorus.alerts.getAlerts("WORKFLOW", wf.workflowid),
        };
    }
}
