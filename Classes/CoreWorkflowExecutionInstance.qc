# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus CorerWorkflowExecutionInstance class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

class OMQ::CoreWorkflowExecutionInstance inherits AbstractCoreWorkflowExecutionInstance, WorkflowExecutionInstance {
    private {
        # reset ID
        softint resetid = 0;

        Counter startResetCounter;
    }

    constructor(softstring index, *int sync_wfiid, string mode, Workflow wf, *hash cx, *string reason)
        : AbstractCoreWorkflowExecutionInstance(index, sync_wfiid, mode, wf),
            WorkflowExecutionInstance(index, sync_wfiid, mode, wf, cx, reason) {
    }

    *int auditUserEvent(string user_event, *string info1, *string info2) {
        return Qorus.audit.userWorkflowEvent(tld.cx, a_start, wf.workflowid, tld.wfe.workflow_instanceid, tld.stepID, tld.ind, user_event, info1, info2);
    }

    private workflowStopped() {
        # cleanup connection
        SM.cleanupConnection(wf.workflowid, index);

        # tell control object that workflow has stopped
        Qorus.control.workflowStopped(index, stopreason);
    }

    private waitSignalReset() {
        if (resetid) {
            # wait for all workflow instances to be signaled
            startResetCounter.waitForZero();
            signalReset();
        }
    }

    private signalReset() {
        Qorus.control.resetComplete(resetid, wf);
    }

    private clearReset() {
        mStop.lock();
        on_exit mStop.unlock();

        # do not propagate exceptions raised when resetting workflow execution instance data (fix for bug 512)
        # reset instance data (fix for bug 329)
        try {
            instancedata.reset();
        } catch (hash<ExceptionInfo> ex) {
            logInfo("exception resetting workflow execution instance data: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        }

        stop_warn = False;
        resetid = 0;
        # do not delete the startResetCounter object
        remove startResetCounter;
        if (stop == WSC_RESET)
            stop = WSC_NONE;
    }

    private bool doReset() {
        # otherwise we are resetting the workflow; refresh workflow information
        # wait for all workflow instances to be signaled
        startResetCounter.waitForZero();

        try {
            {
                # wait for all workflows to reach the sync point so the WorkflowQueue can be reset
                on_exit
                    Qorus.control.resetComplete(resetid, wf);
                wf = Qorus.control.getNewWorkflow(resetid);
            }

            if (clearReset())
                return True;

            # fix for bug 405: reset workflow recovery delay options after wf reset
            wf.setDelayOptions();

            # fix for bug 474: wait for registration with the SegmentManager before processing status changes
            setup.waitForZero();

            logInfo("workflow configuration refreshed with version cached on %y, reset complete", wf.cached);
        } catch (hash<ExceptionInfo> ex) {
            Qorus.logInfo(Util::get_exception_string(ex));
            string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            workflowError("QORE-EXCEPTION", err);
            setFatalError(ex);
            status = OMQ::WISStopping;
            return True;
        }

        return init() ? True : False;
    }

    bool setReset(WorkflowResetData r, *string why) {
        QDBG_LOG("WorkflowExecutionInstance::setReset index = %y why = %y", index, why);
        # fix for bug 474: wait for registration with the SegmentManager before processing status changes
        setup.waitForZero();

        mStop.lock();
        on_exit mStop.unlock();

        if (stop == WSC_NONE && !exiting) {
            r.stopping();
            startResetCounter = r.cStartReset;
            stop = WSC_RESET;
            resetid = wf.workflowid;

            # fix for bug 367: make sure the workflow reset only happens when the synchronous workflow is finished processing
            if (!sync_wfiid) {
                logInfo("workflow configuration for %s v%s (%d) from %y is being reloaded, starting workflow execution instance reset%s", wf.name, wf.version, wf.workflowid, wf.cached, why ? sprintf(": %s", why) : "");
                # only terminate queues if non-synchronous
                SM.terminateConnections(wf.workflowid, index);
            } else {
                # do not terminate queues for sync workflows; just log
                logInfo("workflow configuration for %s v%s (%d) from %y is being reloaded, the reload will be delayed until this synchronous workflow has finished processing its order data", wf.name, wf.version, wf.workflowid, wf.cached, why ? sprintf(": %s", why) : "");
            }
            return False;
        }

        logInfo("workflow configuration for %s v%s (%d) from %y is being ignored; stop: %y exiting: %y", wf.name, wf.version, wf.workflowid, wf.cached, stop, exiting);
        return True;
    }

    setFatalError(hash<auto> ex) {
        WorkflowExecutionInstance::setFatalError(ex);
    }

    private stopAndCleanup() {
        Qorus.logInfo("stopped %s workflow %s v%s (%d) ID %s; %s", wf.remote ? "remote" : "local", name, version, wf.workflowid, index, stopreason.getText());
        WorkflowExecutionInstance::stopAndCleanup();
    }
}
