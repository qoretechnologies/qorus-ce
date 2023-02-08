# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Cluster Control class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

public namespace OMQ;

class OMQ::ClusterControl inherits OMQ::ControlBase {
    private {
        int wfid;

        # the Workflow object
        Workflow wf;
    }

    constructor(int wfid) {
        self.wfid = wfid;
        setWorkflow();
    }

    auto deserialize(data d) {
        return wf.pgm.callFunction("_qorus_deserialize", d);
    }

    # issue #3957: mark synchronous execution instances that they need to inform qorus-core when they terminate
    qorusCoreAborted() {
        try {
            rwl.readLock();
            on_exit rwl.readUnlock();

            map $1.qorusCoreAborted(), execHash.iterator();
        } catch (hash<ExceptionInfo> ex) {
            Qorus.logError("error marking workflows with qorus-core abort status: %s", get_exception_string(ex));
        }
    }

    # call with qctl api QWF-CALL-SUBSYSTEM subsystem=control,method=getDebugInfo
    hash<auto> getDebugInfo() {
        return {
            "wfid": wfid,
            "execHash": keys execHash,
        };
    }

    # called when qorus-core is restarted while qwf processes are running
    *list<hash<auto>> getRecoveryInfo() {
        list<hash<auto>> rv;

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        foreach ClusterWorkflowExecutionInstance wfi in (execHash.iterator()) {
            # issue #3530: in case the workflow was stopping, we need to finalize its removal here and not return it
            # to qorus-core
            int stop = wfi.getStop();
            string id = wfi.getID();
            if (stop != WSC_NONE) {
                Qorus.logInfo("discarding workflow exec instance %d with status %d", id, stop);
                # remove the execution instance immediately
                delete execHash{id};
                continue;
            }
            rv += {
                "index": id,
                "mode": wfi.mode,
                "sync_wfiid": wfi.getSyncOrderId(),
            };
        }

        return rv;
    }

    # called from qorus-core to create a workflow execution instance
    createWorkflowExecutionInstance(softstring index, *int sync_wfiid, string mode, *hash cx, *string reason, *bool recover) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (recover && execHash{index}) {
            Qorus.logInfo("recovering already existing workflow execution instance %y", index);
        } else {
            QDBG_ASSERT(!execHash{index});
            execHash{index} = new ClusterWorkflowExecutionInstance(index, sync_wfiid, mode, wf, cx, reason);
            Qorus.logInfo("created workflow execution instance %y", index);
        }
    }

    waitForStop() {
        list<Counter> l();

        {
            rwl.readLock();
            on_exit rwl.readUnlock();

            l = map cast<ClusterWorkflowExecutionInstance>($1).getStopCounter(), execHash.iterator();
        }

        map $1.waitForZero(), l;
    }

    private setWorkflow() {
        ensure_create_tld();
        wf = new Workflow(wfid);
        # update workflow info
        Qorus.updateMappers((map $1.toInt(), wf.mh.iterator()));
    }

    # method to set up a workflow only for running the detach function
    string getTemporaryWorkflowInstance(softstring wfid, softstring wfiid) {
        QDBG_ASSERT(wf.workflowid == wfid);
        return wf.setTemporaryThreadContext(wfiid);
    }

    # returns a new workflow execution instance object
    private AbstractWorkflowExecutionInstance getTemporaryWorkflowExecutionInstance(string id, string mode, Workflow wf) {
        QDBG_ASSERT(self.wf == wf);
        return new ClusterWorkflowExecutionInstance(id, NOTHING, mode, wf);
    }

    Workflow getWorkflow() {
        QDBG_ASSERT(wf);
        return wf;
    }

    Workflow getNewWorkflow(softstring wfid) {
        QDBG_ASSERT(wf);
        QDBG_ASSERT(wfid == wf.workflowid);
        return wf;
    }

    # called from synchronous workflows when subworkflows are started
    string startSynchronousSubWorkflow(hash<auto> parent_info, softint wfid, OrderData order, *hash<auto> opts) {
        string wfiid = Qorus.control_client.startSynchronousSubWorkflowExtern(parent_info, wfid, order, opts);
        SM.setSubWorkflowInfo(parent_info, wfiid);
        return wfiid;
    }

    # stops all instances of given workflow
    int stopWorkflow(*hash cx, string name, *string version, *reference h, *string reason) {
        return Qorus.control_client.stopWorkflow(cx, name, version, h, reason);
    }

    *Workflow tryGetWorkflow(softstring wfid) {
        QDBG_ASSERT(wfid == self.wfid);
        return wf;
    }

    Workflow getWorkflow(softstring wfid) {
        QDBG_ASSERT(wfid == self.wfid);
        # first try to use read lock
        {
            rwl.readLock();
            on_exit rwl.readUnlock();

            if (wf)
                return wf;
        }

        # copy cached workflow information to workflow instance
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        return getWorkflowIntern(wfid);
    }

    # called with the write lock held
    private Workflow getWorkflowIntern(softstring wfid) {
        QDBG_ASSERT(wfid == self.wfid);
        if (!wf) {
            QDBG_LOG("ClusterControl::getWorkflowIntern() creating %y, stack: %N\n", wfid, get_stack());
            setWorkflow();
        }

        return wf;
    }
}
