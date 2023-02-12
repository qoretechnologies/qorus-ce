# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus ClusterWorkflowExecutionInstance class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

class OMQ::ClusterWorkflowExecutionInstance inherits WorkflowExecutionInstance {
    private:internal {
        bool deferred_stop;
        # one-time init flag; in case of a recovery after a premature qorus-core termination
        bool init_done = False;
        # Counter for waiting for workflow execution instance to stop
        Counter stop_cnt();

        # if qorus-core aborted while this execution instance started
        bool qorus_core_aborted;
    }

    constructor(softstring index, *int sync_wfiid, string mode, Workflow wf, *hash cx, *string reason)
        : WorkflowExecutionInstance(index, sync_wfiid, mode, wf, cx, reason) {
    }

    destructor() {
        # stop the qwf process if we need to reset
        if (deferred_stop) {
            Qorus.shutdown();
        }
    }

    int usleep(date us) {
        return usleep(us.durationMicroseconds());
    }

    int usleep(softint us) {
        if (stop_warn) {
            throw "STOP-ERROR", "omqsleep() or omqusleep() called twice after workflow execution instance is in stop "
                "state";
        }

        while (!stop && !deferred_stop && us > 0) {
            Qore::usleep(us > 1000000 ? 1000000 : us);
            us -= 1000000;
        }
        if (stop || deferred_stop) {
            stop_warn = True;
            return -1;
        }
        return 0;
    }

    *int auditUserEvent(string user_event, *string info1, *string info2) {
        return Qorus.control_client.auditUserEventExtern(index, tld.cx, tld.wfe.workflow_instanceid, tld.stepID, tld.ind, user_event, info1, info2);
    }

    setDeferredStop(*hash<auto> cx, *string reason) {
        QDBG_ASSERT(sync_wfiid);
        deferred_stop = True;
        stopreason.set(cx, reason);
    }

    # synchronized to ensure that initialization is only performed once; can be called more than once
    # in case of a qorus-core crash when qorus-core recovers a qwf process
    synchronized int inlineInit() {
%ifdef QorusDebugInternals
        # issue #2295: if a signal file exists, then terminate the process here
        {
            string filename = sprintf("%s/%s-%s-%s-%s-inlineInit", tmp_location(),
                Qorus.options.get("instance-key"), wf.name, wf.version, wf.workflowid);
            if (is_file(filename)) {
                QDBG_LOG("WorkflowExecutionInstance::inlineInit() SIGNAL FILE %y found; unlinking", filename);
                unlink(filename);
                QDBG_LOG("WorkflowExecutionInstance::inlineInit() TERMINATING");
                exit(1);
            }
        }
%endif

        QDBG_LOG("WorkflowExecutionInstance::inlineInit() tld.index %y -> %y (done: %y)", tld.index, index, init_done);
        if (init_done) {
            return 0;
        }
        init_done = True;

        return WorkflowExecutionInstance::inlineInit();
    }

%ifdef QorusDebugInternals
    setupComplete() {
        # issue #2618: if a signal file exists, then terminate the process here
        {
            string filename = sprintf("%s/%s-%s-%s-%s-setupComplete", tmp_location(),
                Qorus.options.get("instance-key"), wf.name, wf.version, wf.workflowid);
            if (is_file(filename)) {
                QDBG_LOG("WorkflowExecutionInstance::setupComplete() SIGNAL FILE %y found; unlinking", filename);
                unlink(filename);
                QDBG_LOG("WorkflowExecutionInstance::setupComplete() TERMINATING");
                exit(1);
            }
        }
        WorkflowExecutionInstance::setupComplete();
    }
%endif

%ifdef QorusDebugInternals
    setOption(hash<auto> h) {
        # issue #2812: if a signal file exists, then terminate the process here
        {
            string filename = sprintf("%s/%s-%s-%s-%s-setOption", tmp_location(),
                Qorus.options.get("instance-key"), wf.name, wf.version, wf.workflowid);
            if (is_file(filename)) {
                QDBG_LOG("WorkflowExecutionInstance::setOption() SIGNAL FILE %y found; unlinking", filename);
                unlink(filename);
                QDBG_LOG("WorkflowExecutionInstance::setOption() TERMINATING");
                exit(1);
            }
        }
        WorkflowExecutionInstance::setOption(h);
    }
%endif

    synchronized bool start() {
        QDBG_LOG("calling ClusterWorkflowExecutionInstance::start() index: %y started: %y", index, started);
        if (started) {
            return False;
        }

        WorkflowExecutionInstance::start();
        return True;
    }

    recoverAndStartWorkflow() {
        QDBG_LOG("ClusterWorkflowExecutionInstance::recoverAndStartWorkflow() index: %y setup: %d err: %y "
            "started: %y", index, setup.getCount(), fatal_error, started);
        if (setup.getCount()) {
            if (!fatal_error) {
                logInfo("recovering from a qorus-core termination during workflow setup");

                # ensure that the workflow exec instance has been initialized
                inlineInit();
            }

            if (fatal_error) {
                logInfo("workflow cannot be recovered due to a fatal error: %s", stopreason.getText());
                stop = WSC_STOP;
                exiting = True;
                setup.dec();
                throw "WORKFLOW-RECOVERY-ERROR", sprintf("workflow %s v%s (%d) could not be recovered: %s", wf.name,
                    wf.version, wf.workflowid, stopreason.getText());
            }

            setupComplete();
        }

        if (start()) {
            logInfo("started workflow execution instance %d after recovery", index);
        } else {
            logInfo("workflow execution instance %d is already running", index);
        }
    }

    qorusCoreAborted() {
        if (!qorus_core_aborted) {
            qorus_core_aborted = True;
        }
    }

    private logSynchronousComplete(*string stat) {
        WorkflowExecutionInstance::logSynchronousComplete(stat);
        # issue #3957: if qorus-core has been restarted, then we need to notify qorus-core that the instance has
        # stopped
        if (qorus_core_aborted) {
            notifyWorkflowStoppedIntern();
        }
    }

    hash<auto> execSynchronousOrderCreated() {
        Qorus.exec_cnt.inc();
        on_exit Qorus.exec_cnt.dec();

        # issue #2647: index and index_map must already be set in thread local data
        QDBG_ASSERT(tld.index == index);

        return execSynchronous();
    }

    # called when stop called from qorus-core
    setStopExtern(*hash<auto> cx, *string reason) {
        signalStop();

        setStop(cx, reason);
    }

    Counter getStopCounter() {
        return stop_cnt;
    }

    private startWorkflow() {
        stop_cnt.inc();
        on_exit signalStop();

        WorkflowExecutionInstance::startWorkflow();
    }

    synchronized signalStop() {
        if (stop_cnt.getCount()) {
            stop_cnt.dec();
        }
    }

    private workflowStopped() {
        # cleanup connection
        SM.cleanupConnection(wf.workflowid, index);

        notifyWorkflowStoppedIntern();
    }

    private notifyWorkflowStoppedIntern() {
        try {
            # if this call throws a CLIENT-TERMINATED error, then the qorus-core process has already
            # removed this workflow, and we should terminate
            if (Qorus.control_client.workflowStopped(index, stopreason, True)) {
                logInfo("qorus-core indicated the workflow process should be terminated");
                Qorus.shutdown();
            }
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CLIENT-TERMINATED") {
                logInfo("%s: qorus-core has already stopped this workflow", ex.err);
                return;
            }
            rethrow;
        }
    }
}
