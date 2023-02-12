# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Control class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

public namespace OMQ;

class OMQ::ControlBase {
    public {
        hash<string, AbstractWorkflowExecutionInstance> execHash();
    }

    private {
        # read-write lock for the workflow cache and for workflow execution instances
        RWLock rwl();
    }

    string setTemporaryThreadContext(softstring wfid, softint wfiid, ThreadLocalData th) {
        Workflow wf = getWorkflow(wfid);
        return wf.setTemporaryThreadContext(wfiid, th);
    }

    temporaryWorkflowStopped(Workflow wf) {
        bool lck = !rwl.writeLockOwner();
        if (lck) rwl.writeLock();
        on_exit if (lck) rwl.writeUnlock();

        # delete the workflow instance
        delete execHash.(wf.tempid);
    }

    # method to set up a temporary workflow instance belonging to the Workflow object
    string createTemporaryWorkflowInstance(Workflow wf) {
        string id;
        bool lck = !rwl.writeLockOwner();
        {
            if (lck)
                rwl.writeLock();
            on_exit if (lck)
                rwl.writeUnlock();

            id = "temp-wf-" + wf.workflowid;

            if (execHash{id}) {
                # called during a wf reset
                if (execHash{id}.wf != wf)
                    execHash{id}.wf = wf;
            } else {
                # do not wait for status changes (reset or stop)
                execHash{id} = getTemporaryWorkflowExecutionInstance(id, WM_Normal, wf);
            }
        }

        on_error {
            olog(LoggerLevel::FATAL, "deleting temp %y (err): keys: %y: %y", id, execHash.keys(), execHash{id});
            if (lck)
                rwl.writeLock();
            on_exit if (lck)
                rwl.writeUnlock();
            delete execHash{id};
        }

        # initialize workflow instance
        execHash{id}.setupTemp();

        return id;
    }

    # returns a new Temporary workflow execution instance object
    abstract private AbstractWorkflowExecutionInstance getTemporaryWorkflowExecutionInstance(string id, string mode, Workflow wf);

    abstract Workflow getNewWorkflow(softstring wfid);

    abstract private Workflow getWorkflowIntern(softstring wfid);

    abstract Workflow getWorkflow(softstring wfid);
}
