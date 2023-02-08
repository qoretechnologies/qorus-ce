# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Control class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

public namespace OMQ;

const OMQ::WWC_RetReset = (1 << 0); # return immediately if reset in progress
const OMQ::WWC_RetStop  = (1 << 1); # return immediately if stop in progress
const OMQ::WWC_RetStart = (1 << 2); # return immediately if start in progress

# feature 1081: manage the workflow queue reference for paused workflows
# this class ensures that non-synchronous workflow starts and workflow pauses are executed atomically (never at the
# same time, one action will wait for the other)
# it also ensures that no workflow is starting when the system is shut down, to eliminate a race condition with
# workflow starts and system shutdown
class OMQ::ClearHelper {
    private {
        Mutex m();
        # start pause helpers
        hash<string, StartClearHelper> sp;

        # global action count
        int ac = 0;
        # global action condition
        Condition acond();
        # global action waiting
        int action_waiting = 0;

        # global start count
        int sc = 0;
        # global start condition
        Condition scond();
        # global start waiting
        int start_waiting = 0;

        # reference counts
        hash<string, string> wrh;
    }

    # no public members
    public {}

    hash<auto> getDebugInfo() {
        return {
            "m": m.lockTID(),
            "sp": (map {$1.key: $1.value.getDebugInfo()}, sp.pairIterator()),
            "ac": ac,
            "action_waiting": action_waiting,
            "sc": sc,
            "start_waiting": start_waiting,
            "wrh": wrh,
        };
    }

    # discard all references on shutdown
    clearAll() {
        list<string> l = ();

        {
            m.lock();
            on_exit m.unlock();

            foreach string wfid in (keys wrh) {
                olog(LoggerLevel::INFO, "Control: purging cache for wfid %d", wfid);
                if (clearIntern(wfid)) {
                    l += wfid;
                }
            }
        }

        map SM.derefWorkflow($1, True, False), l;
    }

    # discard all references when autostart = 0
    clear(softstring wfid) {
        bool b;

        # ensure that pause and workflow start actions happen atomically to avoid a race condition in managing the
        # workflow queue reference
        {
            m.lock();
            on_exit m.unlock();

            if (!sp{wfid}) {
                sp{wfid} = new StartClearHelper();
            }

            sp{wfid}.startClear(m);

            b = clearIntern(wfid);
        }

        on_exit {
            m.lock();
            on_exit m.unlock();
            if (sp{wfid}.endClear(m)) {
                remove sp{wfid};
            }
        }

        if (!b) {
            return;
        }

        SM.derefWorkflow(wfid, True, False);
    }

    # temporarily dereference any saved reference for workflows with autostart > 0
    # and then re-reference them so that the remote qwf processes can be restarted
    resetRemote(softstring wfid) {
        *string msg;

        # ensure that pause and workflow start actions happen atomically to avoid a race condition in managing the
        # workflow queue reference
        {
            m.lock();
            on_exit m.unlock();

            if (!sp{wfid}) {
                sp{wfid} = new StartClearHelper();
            }

            sp{wfid}.startClear(m);

            msg = remove wrh{wfid};
        }

        on_exit {
            m.lock();
            on_exit m.unlock();
            if (sp{wfid}.endClear(m)) {
                remove sp{wfid};
            }
        }

        if (!msg) {
            return;
        }

        # dereference segment workflow data
        SM.derefRestartWorkflow(wfid);
        # reference segment workflow data
        started(wfid, msg);
    }

    private bool clearIntern(string wfid) {
        if (wrh{wfid}) {
            remove wrh{wfid};
            return True;
        }
        return False;
    }

    *bool hasRef(softstring wfid) {
        return exists wrh{wfid} ? True : False;
    }

    started(softstring wfid, string strdesc) {
        {
            m.lock();
            on_exit m.unlock();

            if (exists wrh{wfid})
                return;

            # optimistically mark the reference; clear actions cannot start until after the start action is confirmed
            # anyway
            wrh{wfid} = strdesc;
        }

        if (!SM.referenceWorkflowQueue(wfid)) {
            m.lock();
            on_exit m.unlock();

            remove wrh{wfid};
        }
    }

    startClearAll() {
        m.lock();
        on_exit m.unlock();

        # wait until there are no workflows starting
        while (sc) {
            ++start_waiting;
            scond.wait(m);
            --start_waiting;
        }

        # increment action count
        ++ac;
    }

    endClearAll() {
        if (!--ac && action_waiting) {
            acond.broadcast();
        }
    }

    startStart(softstring wfid, bool sync) {
        m.lock();
        on_exit m.unlock();

        # wait until there are no global actions in progress
        while (ac) {
            ++action_waiting;
            acond.wait(m);
            --action_waiting;
        }

        # increment global start count
        ++sc;

        if (!sync) {
            # create wf action helper if necessary
            if (!sp{wfid}) {
                sp{wfid} = new StartClearHelper();
            }

            # start workflow start action
            sp{wfid}.startStart(m);
        }
    }

    endStart(softstring wfid, bool sync) {
        m.lock();
        on_exit m.unlock();

        # finalize wf start action
        if (!sync && sp{wfid}.endStart(m)) {
            remove sp{wfid};
        }

        # dec global start count
        if (!--sc && start_waiting) {
            scond.broadcast();
        }
    }
}

# feature 1081: manage the workflow queue reference for paused workflows
# this class ensures that non-synchronous workflow starts and workflow pauses are executed atomically (never at the
# same time, one action will wait for the other)
class OMQ::StartClearHelper {
    public {
        # action count
        int ac = 0;
        # action condition
        Condition acond();
        # action waiting
        int action_waiting = 0;

        # start count
        int sc = 0;
        # start condition
        Condition scond();
        # start waiting
        int start_waiting = 0;
    }

    hash<auto> getDebugInfo() {
        return {
            "ac": ac,
            "action_waiting": action_waiting,
            "sc": sc,
            "start_waiting": start_waiting,
        };
    }

    startClear(Mutex m) {
        # wait until there are no workflows starting
        while (sc) {
            ++start_waiting;
            scond.wait(m);
            --start_waiting;
        }

        # increment action count
        ++ac;
    }

    bool endClear(Mutex m) {
        if (!--ac) {
            if (action_waiting)
                acond.broadcast();
            else # can delete helper object - no waiting threads
                return True;
        }
        return False;
    }

    startStart(Mutex m) {
        # wait until there are no workflows actions in progress
        while (ac) {
            ++action_waiting;
            acond.wait(m);
            --action_waiting;
        }

        # increment start count
        ++sc;
    }

    bool endStart(Mutex m) {
        if (!--sc) {
            if (start_waiting)
                scond.broadcast();
            else # can delete helper object - no waiting threads
                return True;
        }
        return False;
    }
}

class OMQ::Control inherits OMQ::ControlBase {
    public {
        # per-workflow stop timestamps to deal with abort notifications for aborts that happened before the workflow
        # was stopped anyway
        # wfid -> timestamp
        hash<string, date> wf_stop_map;
    }

    private {
        # workflow cache; keyed by workflowid
        hash<string, Workflow> wfc();

        # running workflow count
        Counter cInstances();

        # workflow exec ID sequence (start with 1 to make sure 0 is invalid)
        Sequence idSeq(1);

        # workflow execution instance tracking hash, keyed by workflowid, keyed by execution ID
        hash<string, hash<string, Counter>> eh();

        # reset hash; keyed by workflowid; values are WorkflowStatusData objects
        hash<string, WorkflowStatusData> rh();

        # workflow exec instance counter hash; wfid -> index -> True
        hash<string, hash<string, bool>> ch();

        # map of synchronously-executing workflow_instanceids -> exec ID
        hash<string, string> sync_map;

        # feature 1081: saved workflow references for paused workflows
        ClearHelper wah();

        # recovery counter
        Counter recovery_cnt();
    }

    constructor() {
    }

    signalRecovery() {
        recovery_cnt.inc();
    }

    hash<auto> getDebugInfo() {
        return {
            "cInstances": cInstances.getCount(),
            "wah": wah.getDebugInfo(),
            "recovery_cnt": recovery_cnt.getCount(),
            "rh": (map {$1.key: sprintf("%N", $1.value)}, rh.pairIterator()),
            "eh": (map {$1.key: (map {$1.key: $1.value.getCount()}, $1.value.pairIterator())}, eh.pairIterator()),
            "ch": ch,
            "execHash": (
                map {
                    $1.key: {
                        "class": $1.value.className(),
                        "workflow": sprintf("%s v%s (%d)", $1.value.wf.name, $1.value.wf.version,
                            $1.value.wf.workflowid),
                        "remote": $1.value.wf.remote,
                        "mode": $1.value.mode,
                        "sync": $1.value.isSync(),
                        "starttime": $1.value.starttime,
                        "temp": $1.value.isTemp(),
                    }
                }, execHash.pairIterator()
            ),
        };
    }

    # called when a qwf process terminated prematurely
    recoverAbortedWorkflow(string wfid, bool restarted, date abort_timestamp) {
        QDBG_LOG("Control::recoverAbortedWorklow() wfid: %d restarted: %y abort timestamp: %y last stop: %y", wfid,
            restarted, abort_timestamp, wf_stop_map{wfid});
        # wait for qorus-core recovery to complete if applicable
        recovery_cnt.waitForZero();

        ensure_create_tld();
        # issue #2547: ensure that handling qwf process aborted events is subject to serialization
        AtomicWorkflowActionHelper atomic_action_helper(wfid);

        if (wf_stop_map{wfid} > abort_timestamp) {
            qlog(LoggerLevel::INFO, "ignoring abort message for workflowid %d that happened before last stop; abort "
                "timestamp: %y last stop: %y", abort_timestamp, wf_stop_map{wfid});
            return;
        }

        if (restarted) {
            # issue #3531: if a qwf process is restarted when qorus is shutting down, then throw an appropriate
            # exception
            if (Qorus.shutting_down) {
                throw "SYSTEM-SHUTDOWN-ERROR", sprintf("ignoring restart of qwf process for workflowid %d, as the "
                    "system is shutting down", wfid);
            }

            # register with segment manager to get segment workflow data and therefore the remote connection object
            # ensure that the workflow process stays in scope while restarting the execution instances
            SM.registerWorkflow(getWorkflow(wfid), False, False);
            # notify workflow of any active log subscriptions
            SM.enableLoggingIfNeeded(wfid);
        }
        on_exit if (restarted) {
            SM.derefWorkflow(wfid, False, False);
        }

        # mark all affected workflow execution instances as stopped
        {
            /** issue #2415: first we have to remove the workflow execution instance from the exec hash
                before calling workflowStoppedIntern() due to changes necessary to avoid a race condition
                with running processes, so we do it here for recovery as well, even though in this cause
                there was already a process aborted event
            */
            *list<AbstractCoreWorkflowExecutionInstance> workflow_exec_instances;
            # list of workflow execution instance IDs to recover
            *list<string> idl;
            # execution Counter objects removed from eh
            *hash<string, *Counter> execution_counter_hash;
            hash<auto> wf;
            {
                rwl.writeLock();
                on_exit rwl.writeUnlock();

                # issue #3491: do not remove execution instances started after the crash
                idl = keys eh{wfid}, execHash{$1}.starttime < abort_timestamp;
                if (idl) {
                    wf = hash(execHash{idl[0]}.wf);
                    # issue #2415: remove workflow execution instances
                    workflow_exec_instances = (remove execHash{idl}).values();
                    QDBG_LOG("Control::recoverAbortedWorklow() removed exec IDs: %y", idl);
                    execution_counter_hash = remove eh{wfid};
                }
            }
            if (idl) {
                ActionReason stopreason(NOTHING, "qwf process terminated prematurely" + !restarted ? " and could not "
                    "be restarted" : "");
                foreach string id in (idl) {
                    *Counter execution_counter = remove execution_counter_hash{id};
                    AbstractCoreWorkflowExecutionInstance workflow_exec_instance = workflow_exec_instances[$#];
                    # NOTE: the workflow execution instance must be deleted only after the SegmentManager has been
                    # dereferenced
                    on_exit {
                        rwl.writeLock();
                        on_exit rwl.writeUnlock();

                        workflowStoppedIntern(id, wfid, workflow_exec_instance, execution_counter, wf, stopreason,
                            True);
                    }

                    # we have to have TLD when we dereference the WF
                    ensure_create_tld();
                    # deregister the instance with the segment manager, deref queue count if not synchronous
                    QDBG_LOG("Control::recoverAbortedWorklow() deleting exec ID %y", workflow_exec_instance.getID());
                    SM.derefWorkflow(wfid, !workflow_exec_instance.isSync(), False);
                    QDBG_LOG("Control::recoverAbortedWorklow() deleted");
                }
            }
        }

        if (restarted) {
            *hash wf = Qorus.qmm.lookupWorkflow(wfid);
            if (wf.autostart > 0 && !wf."deprecated") {
                autoStartWorkflow(NOTHING, wf, NOTHING, "restarting workflow after the qwf process terminated "
                    "prematurely");
            }
        }
    }

    # this method is called when qorus-core is restarted with already-running processes
    # to recover the running workflow execution instances
    recoverProcesses(hash<string, bool> rwfh) {
        # save the maximum index for the recovered workflow execution instances
        int maxindex;
        on_exit {
            if (maxindex) {
                # make sure the sequence does not overlap with the recovered indices
                while (idSeq.next() < maxindex) {
                }
            }
            recovery_cnt.dec();
        }

        foreach string wfid in (keys rwfh) {
            # ensure atomicity of workflow recoveries
            AtomicWorkflowActionHelper atomic_action_helper(wfid);

            rwl.writeLock();
            on_exit rwl.writeUnlock();

            Workflow wf = getWorkflowIntern(wfid);
            # make sure workflow has remote=true; it might have changed at the same time that qorus-core failed
            if (!wf.remote) {
                wf.remote = True;
            }
            # register with segment manager to get segment workflow data and therefore the remote connection object
            SM.registerWorkflow(wf, False, False);
            on_exit
                SM.derefWorkflow(wfid, False, False);

            try {
                # get information from workflow process
                *list<auto> rl = SM.getRecoveryInfo(wfid);
                QDBG_LOG("Control::recoverProcesses() wfid: %y got: %y", wfid, rl);

                # register execution instances
                foreach hash<auto> h in (rl) {
                    QDBG_ASSERT(!execHash{h.index});
                    QDBG_ASSERT(!eh{wfid}{h.index});
                    QDBG_ASSERT(!ch{wfid}{h.index});

                    maxindex = max(maxindex, h.index.toInt());

                    # ensure that workflow starts are coordinated with system shutdown
                    wah.startStart(wfid, exists h.sync_wfiid);
                    on_exit {
                        wah.endStart(wfid, exists h.sync_wfiid);
                        QDBG_LOG("Control::recoverProcesses() finished wfid %y index %y", wfid, h.index);
                    }

                    RemoteWorkflowExecutionInstance rwf;
                    try {
                        # reference in segment manager for segment workflow data
                        SM.registerWorkflow(wf, !exists h.sync_wfiid, False);
                        on_error
                            SM.derefWorkflow(wfid, !exists h.sync_wfiid, False);

                        # create workflow execution instance
                        rwf = new RemoteWorkflowExecutionInstance(h.index, h.sync_wfiid, h.mode, wf, NOTHING,
                            "workflow process recovery", True);
                    } catch (hash<ExceptionInfo> ex) {
                        olog(LoggerLevel::INFO, "error recovering workflow %s v%s (%d) exec instance %d: %s: %s",
                            wf.name, wf.version, wfid, h.index, ex.err, ex.desc);
                        continue;
                    }

                    # save the wf exec instance
                    execHash{h.index} = rwf;

                    # mark ID in execution hash; set stop counter for notifications
                    eh{wfid}{h.index} = new Counter(1);

                    # increment exec instance counter
                    ch{wfid}{h.index} = True;

                    # increment workflow count
                    cInstances.inc();

                    try {
                        # ensure that the workflow exits any intermediary state and is started
                        rwf.recoverAndStartWorkflow();
                    } catch (hash<ExceptionInfo> ex) {
                        QDBG_LOG("qwf recovery error: %s", get_exception_string(ex));
                        ActionReason sr = rwf.getStopReason();
                        workflowStopped(h.index);
                        olog(LoggerLevel::INFO, "error recovering workflow %s v%s (%d) exec instance %d: %s", wf.name,
                            wf.version, wfid, h.index, sr.getText());
                        continue;
                    }
                }
            } catch (hash<ExceptionInfo> ex) {
                olog(LoggerLevel::INFO, "critical error recovering workflows: %s", get_exception_string(ex));
                rethrow;
            }
        }
    }

    shutdown(*hash<auto> cx) {
        olog(LoggerLevel::FATAL, "shutdown command received, stopping %d workflow%s",
             (int c = cInstances.getCount()), c == 1 ? "" : "s");

        wah.startClearAll();
        on_exit wah.endClearAll();

        stopAllWorkflows(cx, NOTHING, "system shutdown");

        # purge workflow cache references for stopped workflows with autostart = 1
        wah.clearAll();

        olog(LoggerLevel::FATAL, "all workflows stopped");

        # delete workflows immediately to ensure that log files are closed and temporary workflow instances are
        # deregistered, etc
        *hash<auto> wfc;
        {
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            wfc = remove self.wfc;
        }

        map delete wfc.$1, keys wfc;
    }

    # wait for any reset/stop actions for the given workflow to complete
    # then update any cached workflow's remote status
    waitUpdateRemote(softstring wfid, bool remote) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        # wait for a reset/stop to complete
        waitForStatus(wfid);

        if (!wfc{wfid}) {
            return;
        }

        wfc{wfid}.remote = remote;
    }

    resetRemote(softstring wfid) {
        wah.resetRemote(wfid);
    }

    Workflow getNewWorkflow(softstring wfid) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return getWorkflowIntern(wfid);
    }

    # method to set up a workflow only for running the detach function
    string getTemporaryWorkflowInstance(softstring wfid, softstring wfiid) {
        Workflow wf;

        {
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            # wait for reset; do not wait for a stop
            waitForStatus(wfid, WWC_RetStop);

            wf = getWorkflowIntern(wfid);
        }

        return wf.setTemporaryThreadContext(wfiid);
    }

    bool isWorkflowInReset(softstring wfid) {
        # no locking here; either it's already locked or the results are not valid anyway after the call
        # also locking here can cause a deadlock
        return rh{wfid} instanceof AbstractWorkflowStopResetData;
    }

    string startSynchronousSubWorkflowExtern(hash<auto> parent_info, softint wfid, OrderData order,
            *hash<auto> opts) {
        return startSynchronousSubWorkflowIntern(parent_info, wfid, order, opts);
    }

    # called from synchronous workflows when subworkflows are started
    string startSynchronousSubWorkflowIntern(hash<auto> parent_info, softint wfid, OrderData order,
            *hash<auto> opts) {
        QDBG_ASSERT(ensure_tld());

        *string parent_index = tld.index;
        # fix for bug 821: workflow log messages are written to the incorrect workflow log file after executing a
        # synchronous subworkflow
        ThreadLocalData tld_save();
        tld_save.tldCopy(tld);
        on_exit tld.tldCopy(tld_save);

        # create the order first and then setup the workflow
        string wfiid = SM.createSynchronousWorkflowCommit(wfid, parent_info, order, OMQ::StatReady, True);

        # do not save the ID in thread data here, only in the child thread
        string id = setupWorkflow({"user": "%SYS%"}, wfid, wfiid, OMQ::WM_Normal, opts, True,
            "executing synchronous subworkflow");

        on_error
            workflowStopped(id);

        background execSynchronousWorkflowBackground(id, wfiid, parent_index);

        return wfiid;
    }

    string startSynchronousSubWorkflow(hash<auto> parent_info, softint wfid, OrderData order, *hash opts) {
        string wfiid = startSynchronousSubWorkflowIntern(parent_info, wfid, order, opts);
        SM.setSubWorkflowInfo(parent_info, wfiid);
        return wfiid;
    }

    clusterResetComplete(softstring oldid) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();
        WorkflowStopResetData rd = rh{oldid};

        rd.cReset.dec();
        delete rh{oldid};
    }

    resetComplete(softstring oldid, *Workflow wf) {
        int count;
        int tot;
        Counter cEnd;
        {
            rwl.writeLock();
            on_exit rwl.writeUnlock();
            # DBG
            if (!rh{oldid}) {
                wf.logFatal("resetComplete() oldid: %y wf: %s v%s (%d) rh: %y", oldid, wf.name, wf.version,
                    wf.workflowid, (foldl $1 + ", " + $2, (map sprintf("%s: %s", $1.key, $1.value.className()),
                    rh.pairIterator())));
            }

            WorkflowResetData rd = rh{oldid};

            # take a copy of a reference to the confirmation counter
            cEnd = rd.cEnd;
            # save total number of execution instances
            tot = rd.total;
            count = --rd.count;
            if (!count) {
                delete rh{oldid};
            }
        }
        # release the lock now, we have already ensured that the cache reset and cEnd.dec() call
        # will be done in one thread only

        if (!count) {
            if (wf) {
                try {
                    SM.resetCache(oldid, wf); # hopefully we won't access rh{oldid} anymore
                } catch (hash<ExceptionInfo> ex) {
                    wf.logFatal("exception resetting workflow cache: %s", Util::get_exception_string(ex));
                    wf.logFatal("workflow processing cannot continue until the problem is resolved");
                }
            }

            cEnd.dec();
            olog(LoggerLevel::INFO, "cache reset complete for workflowid %d (%d execution instance%s reset)", oldid,
                tot, tot == 1 ? "" : "s");
        } else {
            cEnd.waitForZero();
        }

        QDBG_LOG("Control::resetComplete() reset complete for wfid %d", oldid);
    }

    waitStatusLocked(Counter c, bool write) {
        if (write) {
            rwl.writeUnlock();
            c.waitForZero();
            rwl.writeLock();
        } else {
            rwl.readUnlock();
            c.waitForZero();
            rwl.readLock();
        }
    }

    *int auditUserEventExtern(string id, *hash<auto> cx, softint wfiid, softint stepid, softint ind,
            string user_event, *string info1, *string info2) {
        AbstractCoreWorkflowExecutionInstance cwfi = cast<AbstractCoreWorkflowExecutionInstance>(execHash{id});
        return Qorus.audit.userWorkflowEvent(cx, cwfi.a_start, cwfi.wf.workflowid, wfiid, stepid, ind, user_event,
            info1, info2);
    }

    # NOTE: stopreason is read-only for remote workflow execution instances
    # returns True if from_qwf is True and the last workflow has been stopped and the qwf process should terminate
    *bool workflowStopped(string id, *ActionReason stopreason, *bool from_qwf) {
        hash<auto> wf = hash(execHash{id}.wf);
        *softstring sync_wfiid = execHash{id}.getSyncOrderId();

        softstring wfid = wf.workflowid;

        if (!stopreason) {
            try {
                stopreason = execHash{id}.getStopReason();
            } catch (hash<ExceptionInfo> ex) {
                olog(LoggerLevel::INFO, "error retrieving stop reason from workflow execution instance: %s: %s",
                    ex.err, ex.desc);
                stopreason = new ActionReason(NOTHING, "unknown");
            }
        }

        QDBG_LOG("Control::workflowStopped() index: %y %s v%s (%d)", id, wf.name, wf.version, wfid);

%ifdef QorusDebugInternals
        # issue #3539: if a signal file exists, then terminate the process here
        if (is_file(string filename = sprintf("%s/%s-%s-%s-%s-workflowStopped-1", tmp_location(),
            Qorus.options.get("instance-key"), wf.name, wf.version, wf.workflowid))) {
            QDBG_LOG("Control::workflowStopped() SIGNAL FILE %y found; unlinking", filename);
            unlink(filename);
            QDBG_LOG("Control::workflowStopped() TERMINATING");
            exit(1);
        } else {
            QDBG_LOG("Control::workflowStopped() NOT FOUND: %s", filename);
        }
%endif

        /** issue #2415: first we have to remove the workflow execution instance from the exec hash
            and then stop the qwf process (if remote = True), otherwise if we do it in the reverse order, if
            a REST request comes in that requires info from workflows that triggers a remote call, we could
            get a race condition where the process is stopped and then a call is made which will deadlock
        */
        AbstractCoreWorkflowExecutionInstance workflow_exec_instance;
        # the execution counter will be NOTHING for temporary workflow execution instances
        *Counter execution_counter;
        {
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            if (sync_wfiid) {
                remove sync_map{sync_wfiid};
            }

            # remove the workflow exec instance from the exec hash
            workflow_exec_instance = remove execHash{id};
            execution_counter = remove eh{wfid}{id};
            if (!eh{wfid}) {
                remove eh{wfid};
            }
        }

        on_exit {
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            workflowStoppedIntern(id, wfid, workflow_exec_instance, execution_counter, wf, stopreason);
        }

        # do not audit or issue events for temporary workflow exec instances
        if (execution_counter) {
            QDBG_ASSERT(id !~ /^temp-/);

            # we have to have TLD when we dereference the WF
            ensure_create_tld();
            workflow_exec_instance.stopEvents(stopreason);
            # deregister the instance with the segment manager, deref queue count if not synchronous
            return SM.derefWorkflow(wfid, !workflow_exec_instance.isSync(), False, from_qwf);
        }
    }

    # the execution counter will be NOTHING for temporary workflow execution instances
    private workflowStoppedIntern(string id, string wfid,
            AbstractCoreWorkflowExecutionInstance workflow_exec_instance, *Counter execution_counter,
            hash<auto> wf, ActionReason stopreason, *bool recover) {
        string name = wf.name;
        string ver = wf.version;

        # if not a temporary wf exec instance
        if (execution_counter) {
            # decrement exec instance counter
            remove ch{wfid}{id};
            if (!ch{wfid}) {
                delete ch{wfid};
            }

            # decrement/signal stop Counter
            # (do not delete the Counter as someone may be waiting on it)
            execution_counter.dec();

            if (!eh{wfid}) {
                # signal that all workflows of the given type have stopped
                if (rh{wfid} instanceof WorkflowStopData) {
                    QDBG_LOG("Control::workflowStopped() wfid %d", wfid);
                    # for a normal stop, clears the atomic lock on the workflow
                    # for a reset, the atomic lock is left in place
                    if (cast<WorkflowStopData>(rh{wfid}).stopped()) {
                        delete rh{wfid};
                    }
                }
            }
        }

        # delete the workflow instance
        delete workflow_exec_instance;

        # decrement count
        cInstances.dec();

        # if the last instance is being stopped and autostart > 0, then raise ongoing alert
        if (!ch{wf.workflowid} && Qorus.qmm.lookupWorkflow(wfid).autostart && !Qorus.shutting_down) {
            Qorus.alerts.raiseOngoingAlert(stopreason, "WORKFLOW", wf.workflowid, "WORKFLOW-NOT-RUNNING",
                {"name": wf.name, "version": wf.version});
        }
    }

    # return the number of running workflow execution instances for the given workflow ID
    list<string> getRunningWorkflowExecutionInstanceModeList(softstring wfid) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return map execHash{$1}.mode, keys eh{wfid} ?? ();
    }

    list<hash<auto>> getWorkflowInfoList(*string name, *string ver) {
        list<hash<auto>> rv = ();

        rwl.readLock();
        on_exit rwl.readUnlock();

        foreach string id in (keys execHash) {
            if (id =~ /^temp-/) {
                continue;
            }
            AbstractCoreWorkflowExecutionInstance wi = execHash{id};
            if (name) {
                if (name != wi.wf.name) {
                    continue;
                }
                if (ver && wi.wf.version != ver) {
                    continue;
                }
            }
            # get execution instance info
            # issue #2424: process info always returned by getInfo() if available
            rv += wi.getInfo();
        }

        return rv;
    }

    hash<auto> getWorkflowInfo(softstring id) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        # issue #2424: process info always returned by getInfo() if available
        return execHash{id} ? execHash{id}.getInfo() : {};
    }

    # wait for a reset/stop to complete; automatically detects if the read or write lock held
    /** @param wfid the workflow ID to wait for
        @param wait an optional code for the type of action

        @return True if the required condition is already in progress, False if not
    */
    private bool waitForStatus(softint wfid, *int wait) {
        bool w = rwl.writeLockOwner();
        while (True) {
            *WorkflowStatusData wd = rh{wfid};
            if (!wd)
                break;

            if (wd.waitForStatus(w, wfid, wait))
                return True;
        }
        return False;
    }

    /**
        @throw SHUTDOWN-IN-PROGRESS workflows cannot be started while the system is shutting down
        @throw WORKFLOW-START-ERROR workflows cannot be started (too many instances)
        @throw WORKFLOW-INIT-ERROR workflows cannot be initialized (see the message body for reason)
    */
    private string setupWorkflow(*hash<auto> cx, softstring wfid, *softint sync_wfiid, string mode, *hash<auto> opts,
            bool sync_swf = False, *string reason, *bool sm_registered) {
        # wait for workflow process recovery if applicable
        recovery_cnt.waitForZero();

        AtomicWorkflowActionHelper atomic_action_helper(wfid);
        return setupWorkflowAtomic(cx, wfid, sync_wfiid, mode, opts, sync_swf, reason, sm_registered);
    }

    /**
        @throw SHUTDOWN-IN-PROGRESS workflows cannot be started while the system is shutting down
        @throw WORKFLOW-START-ERROR workflows cannot be started (too many instances)
        @throw WORKFLOW-INIT-ERROR workflows cannot be initialized (see the message body for reason)
    */
    private string setupWorkflowAtomic(*hash<auto> cx, softstring wfid, *softint sync_wfiid, string mode,
            *hash<auto> opts, bool sync_swf = False, *string reason, *bool sm_registered) {
        Workflow wf;
        try {
            # do not allow workflows to start if the system is shutting down
            if (Qorus.shutting_down) {
                throw "SHUTDOWN-IN-PROGRESS", "cannot start new workflows because the system is shutting down";
            }

            # issue #2732: do not allow workflows to start if system limits have been exceeded
            QorusSharedApi::checkLimits("cannot start workflow");

            # check if workflow can really start
            Qorus.rbac.canStartWorkflow(wfid);

            bool sync = sync_wfiid.toBool();
            # ensure that workflow starts are coordinated with system shutdown
            wah.startStart(wfid, sync);
            on_exit {
                wah.endStart(wfid, sync);
                QDBG_LOG("ControlBase::setupWorkflowAtomic() finished wfid %y", wfid);
            }

            # get unique execution ID for this workflow
            softstring id = idSeq.next();
            AbstractCoreWorkflowExecutionInstance workflow_exec_instance;
            try {
                AutoWriteLock al(rwl);

                wf = getWorkflowIntern(wfid);

                # check for max_instances
                if (wf.max_instances) {
                    if (ch{wf.workflowid}.size() == wf.max_instances)
                        throw "WORKFLOW-START-ERROR", sprintf("cannot start workflow %s v%s (%d) since there %s "
                            "already %d instance%s running (max_instances = %d)",
                            wf.name, wf.version, wfid, wf.max_instances == 1 ? "is" : "are",
                            wf.max_instances, wf.max_instances == 1 ? "" : "s", wf.max_instances);
                }

                if (!wf.remote) {
                    # ensure that we have all info cached for local workflows in case the workflow has
                    # changed from remote to local
                    wf.clearRemote();
                } else {
                    # issue #3161: ensure that Workflow Program containers are deleted in case the
                    # workflow has changed from local to remote
                    wf.setRemote();
                }

                {
                    # register with segment manager for segment workflow
                    # starts qwf processes if the workflow supports remote execution
                    if (!sm_registered) {
                        QDBG_LOG("ControlBase::setupWorkflowAtomic() wfid: %d register (sync: %y)", wfid, sync);
                        SM.registerWorkflow(wf, !sync, False);
                    }
                    on_error {
                        if (!sm_registered) {
                            QDBG_LOG("ControlBase::setupWorkflowAtomic() wfid: %d deregister (sync: %y)", wfid, sync);
                            SM.derefWorkflow(wf.workflowid, !sync, False);
                        }
                    }

                    # create workflow execution instance
                    execHash{id} = workflow_exec_instance = wf.remote
                        ? new RemoteWorkflowExecutionInstance(id, sync_wfiid, mode, wf, cx, reason)
                        : new CoreWorkflowExecutionInstance(id, sync_wfiid, mode, wf, cx, reason);
                }
                # issue #2295: handle the situation when the qwf process if it is killed before it can be initialized
                int inline_init_error;
                try {
                    # mark ID in execution hash; set stop counter for notifications
                    eh{wfid}{id} = new Counter(1);

                    if (sync_wfiid) {
                        sync_map{sync_wfiid} = id;
                    }

                    # increment exec instance counter
                    ch{wf.workflowid}{id} = True;

                    # unlock lock
                    delete al;

                    # issue #3593: if the workflow is remote, then do not deregister if there's an exception; it will be
                    # handled when the process crashes
                    if (!sm_registered && wf.remote) {
                        sm_registered = True;
                    }

                    # increment workflow count
                    cInstances.inc();

                    # set options
                    if (opts) {
                        execHash{id}.setOption(opts);
                    }
                    inline_init_error = workflow_exec_instance.inlineInit();
                    if (!inline_init_error) {
                        # fix for bug 474:
                        # * notify that the workflow is registered in case of a race with resetting the workflow where
                        #   the SegmentWorkflowData object doesn't exist when SegmentManager::terminateConnections() is
                        #   called
                        workflow_exec_instance.setupComplete();
                    }
                } catch (hash<ExceptionInfo> ex) {
                    ActionReason stopreason(tld.cx, ex);
                    if (wf.remote
                        && (ex.err == "INVALID-WORKFLOW-EXECUTION-INSTANCE"
                            || ex.err == "CLIENT-ABORTED")) {
                        # issue #2295: the qwf process has been killed and is being recovered
                        # the execution instance will be removed in the recovery logic and normal autostart
                        # logic will be applied

                        # feature 1081: maintain saved workflow queue reference for workflow with autostart set
                        if (!sync && wf.autostart) {
                            wah.started(wfid, sprintf("%s v%s (%d)", wf.name, wf.version, wfid));
                        }

                        # mark workflow exec instance setup failed to avoid race conditions with resets and stops
                        workflowStopped(id, stopreason);
                        throw "WORKFLOW-REMOTE-START-ERROR",
                            sprintf("workflow %s v%s (%d) could not be started as the qwf process aborted "
                                "prematurely", wf.name, wf.version, wfid);
                    }

                    # also notify that workflow setup failed to avoid race conditions with resets and stops
                    workflow_exec_instance.setupError(ex);
                    workflowStopped(id, stopreason);
                    rethrow;
                }

                QDBG_LOG("Control::setupWorkflowAtomic() workflow %y %y registered", wf.name, wf.version);

                # initialize workflow inline in start; errors cause an exception to be thrown
                if (inline_init_error) {
                    # get the stop reason before calling ControlBase::workflowStopped() because the
                    # WorkflowExecutionInstance object is deleted there
                    # NOTE: stopreason is read-only for remote workflow execution instances
                    ActionReason sr = workflow_exec_instance.getStopReason();
                    workflowStopped(id);
                    throw "WORKFLOW-INIT-ERROR", sprintf("workflow %s v%s (%d) could not be initialized: %s", wf.name,
                        wf.version, wfid, sr.getText());
                }
                QDBG_LOG("Control::setupWorkflowAtomic() inlineInit done for id %y", id);
            } catch (hash<ExceptionInfo> ex) {
                hash info = {"workflowid": wfid};
                if (wf) {
                    info = {"name": wf.name, "version": wf.version, "mode": mode} + info;
                }
                Qorus.events.postSystemError(ES_Major, "WORKFLOW-INIT-ERROR", sprintf("%s: %s", ex.err, ex.desc),
                    info);
                rethrow;
            }

            # feature 1081: maintain saved workflow queue reference for workflow with autostart set
            if (!sync && wf.autostart) {
                wah.started(wfid, sprintf("%s v%s (%d)", wf.name, wf.version, wfid));
            }

            # raise start events
            QDBG_LOG("ControlBase::setupWorkflowAtomic() raising events id %y opts %y", id, opts);
            workflow_exec_instance.startEvents(cx, opts);
            return id;
        } catch (hash<ExceptionInfo> ex) {
            # issue #3593: must clear session status for workflow
            if (sync_wfiid) {
                {
                    # issue #3593: release sync workflow
                    on_error rethrow;
                    {
                        on_error omqp.rollback();
                        on_success omqp.commit();

                        omqp.exec("update workflow_instance set status_sessionid = 0, synchronous = 0 where "
                            "workflow_instanceid = %v", sync_wfiid);
                        QDBG_LOG("cleared session ID for sync wfiid %d", sync_wfiid);
                    }
                }
                if (!exists ex.arg || ex.arg.typeCode() == NT_HASH) {
                    # ensure that ex.arg has type "hash<auto>"
                    ex.arg = {} + ex.arg;
                    if (wf) {
                        ex.arg += {
                            "name": wf.name,
                            "version": wf.version,
                            "workflowid": wfid,
                        };
                    }
                    ex.arg.workflow_instanceid = sync_wfiid;
                }
                # throw a new exception with the workflow_instanceid
                if (wf) {
                    throw ex.err, sprintf("%s: synchronous workflow order for %s v%s (%s) workflow_instanceid %d: %s",
                        get_ex_pos(ex), wf.name, wf.version, wfid, sync_wfiid, ex.desc), ex.arg;
                } else {
                    throw ex.err, sprintf("%s: synchronous workflow order workflow_instanceid %d: %s",
                        get_ex_pos(ex), sync_wfiid, ex.desc), ex.arg;
                }
            }
            rethrow;
        }
    }

    # called from startSynchronousSubWorkflow()
    private execSynchronousWorkflowBackground(string id, string wfiid, *string parent_index) {
        create_tld();
        QDBG_LOG("ControlBase::execSynchronousWorkflowBackground index %y -> %y", tld.index, id);
        tld.index = id;
        # issue #2647: set parent index if any
        if (parent_index) {
            tld.index_map{parent_index}{id} = True;
        }

        try {
            execHash{id}.execSynchronous();
        } catch (hash<ExceptionInfo> ex) {
            Workflow wf = execHash{id}.wf;
            hash<auto> info = {
                "name": wf.name,
                "version": wf.version,
                "workflowid": wf.workflowid,
            };

            Qorus.events.postSystemError(ES_Major, "SYNC-WORKFLOW-EXEC-ERROR", sprintf("%s: %s", ex.err, ex.desc),
                info);

            wf.logFatal("exception in synchronous workflow: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        }

        workflowStopped(id);
    }

    private AbstractWorkflowExecutionInstance getTemporaryWorkflowExecutionInstance(string id, string mode,
            Workflow wf) {
        return new CoreWorkflowExecutionInstance(id, NOTHING, mode, wf);
    }

    private checkStopExecInstance(string id) {
        checkExecInstance("STOP", id);
    }

    private checkExecInstance(string err, string id) {
        if (!tld.index) {
            return;
        }

        if (tld.index == id) {
            throw err + "-ERROR", sprintf("cannot %s execution instance %d from within the same execution instance",
                err.lwr(), tld.index);
        }

        # check if id is a parent of tld.index
        if (checkChild(id, tld.index)) {
            throw err + "-ERROR", sprintf("cannot %s execution instance %d from within the same execution instance "
                "hierarchy; execution instance %d is a child of %d", err.lwr(), id, tld.index, id);
        }
    }

    # always called outside the lock
    private checkStopWorkflow(softstring wfid) {
        map checkExecInstance("STOP", $1), keys eh{wfid};
    }

    # always called in the write lock
    private checkResetWorkflow(softstring wfid) {
        map checkExecInstance("RESET", $1), keys eh{wfid};
    }

    private static bool checkChild(string parent, string child) {
        if (!tld.index_map{parent}) {
            return False;
        }

        if (tld.index_map{parent}{child}) {
            return True;
        }

        # check all other children for indirect inheritance
        foreach string other_child in (keys tld.index_map{parent}) {
            if (Control::checkChild(other_child, child)) {
                return True;
            }
        }

        return False;
    }
}

OMQ::Control::autoStart() {
    # wait for workflow process recovery if applicable
    recovery_cnt.waitForZero();

    try {
        # get list of all workflows and autostart those with the autostart flag set
        foreach hash<auto> wf in (Qorus.qmm.getWorkflowMap().iterator()) {
            if (wf.autostart <= 0 || wf.deprecated) {
                continue;
            }

            autoStartWorkflow(NOTHING, wf, NOTHING, "autostarting workflow at system startup");
        }
    } catch (hash<ExceptionInfo> ex) {
        # NOTE: Control::autoStart must not throw, being executed in a background thread.
        if (ex.err != "SHUTDOWN-IN-PROGRESS") {
            olog(LoggerLevel::FATAL, "cannot autostart workflows: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        }
    }
}

# called when a wf's autostart value changes; also stops excess wf execution instances
int OMQ::Control::autoStartWorkflow(*hash<auto> cx, hash<auto> wf, *reference h,
        string reason = "autostarting workflow", *reference errstr, *bool in_reset) {
    if (wf.autostart < 0 || (wf.deprecated && wf.autostart > 0)) {
        errstr = sprintf("%s v%s (%d): cannot autostart workflow with autostart: %y, deprecated: %y", wf.name,
            wf.version, wf.workflowid, wf.autostart, wf.deprecated);
        olog(LoggerLevel::INFO, errstr);
        return 0;
    }
    softstring wfid = wf.workflowid;

    # issue #2647: update autostart value in any cached wf immediately; value has already been updated in the
    # map manager
    {
        rwl.readLock();
        on_exit rwl.readUnlock();
        if (wfc{wfid}) {
            wfc{wfid}.autostart = wf.autostart;
        }
    }

    # wait for workflow process recovery if applicable
    recovery_cnt.waitForZero();

    # issue #2799: do not allow autostart status changes while the system is shutting down
    if (Qorus.shutting_down) {
        errstr = sprintf("%s v%s (%d): cannot autostart workflow while the system is shutting down", wf.name,
            wf.version, wf.workflowid);
        olog(LoggerLevel::INFO, errstr);
        return 0;
    }

    # start workflow execution instances exclusively if we are not in a reset
    # if we are in a reset, then the lock is already held by another thread
    AtomicWorkflowActionHelper atomic_action_helper;
    if (!in_reset) {
        atomic_action_helper = new AtomicWorkflowActionHelper(wfid);
    }

    # feature 1081: discard any and all saved queue references if the workflow's autostart is set to 0
    if (!wf.autostart) {
        wah.clear(wfid);
    }

    ThreadLocalData tld_save();
    if (tld) {
       # bug 826: make sure and save and restore thread-local data after this call completes
       tld_save.tldCopy(tld);
    } else {
        # bug 1807: when comming from ConnectionDependencyManager::autoStartWorkflow(),
        # namely connectionUpIntern(), we bypass Control::autoStart
        # and hence need to create ThreadLocalData here.
        create_tld();
    }

    # restart thread-local data on exit
    on_exit {
%ifdef QorusDebugInternals
        if (tld.index || tld_save.index) {
            QDBG_LOG("Control::autoStartWorkflow index %y -> %y", tld.index, tld_save.index);
        }
%endif
        tld = tld_save;
    }

    string wfstr = sprintf("%s v%s (%d)", wf.name, wf.version, wf.workflowid);
    h{wfstr} = 0;

    # FIXME we should use rwl readLock() for the 'ch' hash. --PQ 15-Aug-2016
    # https://bugs.qoretechnologies.com/issues/1553

    bool suppress_detailed_error;

    # error list
    bool stopping = False;
    list<auto> el = ();
    # issue #2625 make sure to raise an ongoing alert if a workflow has a positive autostart value and is disabled
    bool disabled;
    if (ch{wfid}.size() > wf.autostart) {
        stopping = True;
        # trying to stop all instances over wf.autostart, not exitting on 1st exception
        int i = ch{wfid}.size();
        while (i > wf.autostart) {
            try {
                *string id = ch{wfid}.lastKey();
                if (id) {
                    olog(LoggerLevel::INFO, "%s v%s (%d): %s", wf.name, wf.version, wf.workflowid, reason);

                    stopWorkflowInstanceAtomic(cx, id, NOTHING, reason, True);
                    --h{wfstr};

                    olog(LoggerLevel::INFO, "%s v%s (%d): stopped exec ID %d due to autostart change", wf.name,
                        wf.version, wf.workflowid, id);
                }
            } catch (hash<ExceptionInfo> ex) {
                el += ex;
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            }
            --i;
        }
    } else if (ch{wfid}.size() < wf.autostart) {
        # FIXME still somebody can probably start an instance manually during
        # autostartWorkflow, i.e. max_instances should always be checked in
        # setupWorkflow... But how we set autostart then? (to max_instances,
        # but still starting less instances, probably)
        # For example: someone calls omq.system.start-workflow and REST putIncAutostart
        # at the same time. --PQ 15-Aug-2016
        # (REST api is also able to start WF manually, and RBAC::autoStartWorkflows
        # also calls startWorkflow -> comes from enforceGroupChanges(), updateGroup()
        # and others).

        # trying to start enough instances - if it is not possible, we still have to report the proper number of
        # errors
        int i = ch{wfid}.size();
        while (i < wf.autostart) {
            try {
                olog(LoggerLevel::INFO, "%s v%s (%d): autostarting workflow, instance %d/%d", wf.name, wf.version,
                    wf.workflowid, i, wf.autostart);
                QDBG_LOG("Control::autoStartWorkflow starting wfid %y", wfid);

                softint id = startWorkflowAtomic(cx, wfid, OMQ::WM_Normal, NOTHING, reason);

                ++h{wfstr};

                olog(LoggerLevel::INFO, "%s v%s (%d): autostarted instance %d/%d with exec ID %d", wf.name,
                    wf.version, wf.workflowid, i, wf.autostart, id);
                # note: the reason why a WF cannot be autostarted is also reaching
                # wf_max_instance
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SHUTDOWN-IN-PROGRESS") {
                    rethrow;
                }
                olog(LoggerLevel::INFO, "%s v%s (%d): failed to autostart workflow: %s: %s", wf.name, wf.version,
                    wf.workflowid, ex.err, ex.desc);
                if (ex.err == "GROUP-DISABLED") {
                    # don't include disabled workflows in transient alerts
                    # we could return immediately from here, but it can still happen
                    # that somebody disables the group during starting the WFs
                    disabled = True;
                    suppress_detailed_error = True;
                } else if (ex.err != "WORKFLOW-INIT-ERROR" || !ex.arg.already_logged) {
                    suppress_detailed_error = True;
                }
                el += ex;
            }
            ++i;
        }
    }

    if (el) {
        ActionReason r();
        r.set(cx);

        hash<auto> ih = wf.("name", "version");

        # raise transient alerts if at least one workflow was started
        if (el.size() < wf.autostart && !disabled) {
            foreach hash<auto> ex in (el) {
                string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                r.setReason(err);
                Qorus.alerts.raiseTransientAlert(r, "WORKFLOW", wf.workflowid, "WORKFLOW-START-FAILED", ih);
            }
        } else {
            if (!stopping) {
                # raise ongoing alert for workflow
                string err = sprintf("%s: %s: %s:", get_ex_pos(el[0]), el[0].err, el[0].desc);
                r.setReason(err);
                Qorus.alerts.raiseOngoingAlert(r, "WORKFLOW", wf.workflowid, "WORKFLOW-NOT-RUNNING", ih);
            }
        }
        hash<auto> erh = el.first(); # should report first issue, not last
        if (!suppress_detailed_error && Qorus.getDebugSystem()) {
            errstr = get_exception_string(erh);
        } else {
            errstr = sprintf("%s: %s: %s", get_ex_pos(erh), erh.err, erh.desc);
        }
    } else {
        if (!wf.autostart) { # clear WORKFLOW-NOT-RUNNING alert if everything stopped ok
            Qorus.alerts.clearOngoingAlert("WORKFLOW", wf.workflowid, "WORKFLOW-NOT-RUNNING");
        }
    }

    return h{wfstr};
}

*hash OMQ::Control::getWorkflowRuntimeOptions(softstring id) {
    rwl.readLock();
    on_exit rwl.readUnlock();

    return wfc{id} ? wfc{id}.getAllOptions() : NOTHING;
}

# returns execution id on success, exception if error
string OMQ::Control::startWorkflowSetAtomic(*hash<auto> cx, softstring wfid, string mode, *hash<auto> opts,
        *string reason) {
    # wait for workflow process recovery if applicable
    recovery_cnt.waitForZero();

    AtomicWorkflowActionHelper atomic_action_helper(wfid);
    return startWorkflowAtomic(cx, wfid, mode, opts, reason);
}

string OMQ::Control::startWorkflowAtomic(*hash<auto> cx, softstring wfid, string mode, *hash<auto> opts,
        *string reason) {
    # issue #2467: ensure that this call is wrapped in an atomic action call
    QDBG_ASSERT(AtomicClassActionHelper::isLocked(AtomicClassActionHelper::C_Workflow, wfid)
        || isWorkflowInReset(wfid));
    # this can be called without TLD in case of a workflow reset with autostart > 0
    ensure_create_tld();
    QDBG_LOG("Control::startWorkflow entered wfid %y", wfid);
    string id = setupWorkflowAtomic(cx, wfid, NOTHING, mode, opts, False, reason);
    QDBG_LOG("Control::startWorkflow index %y -> %y", tld.index, id);
    TldHelper tldh("index");
    tld.index = id;

    # start workflow
    # log message to qorus-core log file
    Workflow wf = execHash{id}.wf;
    olog(LoggerLevel::INFO, "starting %s workflow %s v%s (%d) ID %s in %s mode%s", wf.remote ? "remote" : "local",
        wf.name, wf.version, wfid, id, mode, reason ? "; " + reason : NOTHING);
    execHash{id}.start();

    # clear any ongoing alert
    ActionReason r(cx, sprintf("workflow %s v%s (%d) ID %s successfully started", wf.name, wf.version, wfid, id));
    # FIXME should not clear the alert here, e.g. if we autostart multiple workflows,
    # some of them can succeed and some of them can fail. --PQ 13-Sep-2016
    Qorus.alerts.clearAllOngoingAlerts(r, "WORKFLOW", wfid);
    return id;
}

hash<auto> OMQ::Control::execSynchronousWorkflowOnExistingOrder(hash<auto> cx, softstring wfiid, *hash<auto> opts) {
    QDBG_ASSERT(ensure_tld());
    # get workflow name and version from workflow ID
    *hash<auto> q = sqlif.controlExecSynchronousWorkflowOnExistingOrder(wfiid);
    if (!exists q)
        throw "WORKFLOW-ERROR", sprintf("cannot initialize synchronous workflow instance; workflow instance ID %d "
            "does not exist in the database", wfiid);

    # issue #1981: clear authentication info and other tld for workflow execution
    TldClearHelper tch("index", "wf", "wfe", "stepID", "ind", "sync");

    string id = setupWorkflow(cx, q.workflowid, wfiid, OMQ::WM_Normal, opts, True,
        "executing synchronous workflow on existing order");
    QDBG_LOG("Control::execSynchronousWorkflowOnExistingOrder index %y -> %y", tld.index, id);
    tld.index = id;

    # issue #2647: add to the index map
    if (*string parent = tch.getOldValue("index")) {
        tld.index_map{parent}{id} = True;
    }

    on_exit
        workflowStopped(id);

    return execHash{id}.execSynchronousOnExistingOrder(cx);
}

# returns execution id on success, exception if error
hash<auto> OMQ::Control::execSynchronousWorkflow(hash<auto> cx, softstring wfid, OrderData order, *hash<auto> opts) {
    QDBG_ASSERT(ensure_tld());

    string wfiid = SM.createSynchronousWorkflowRowCommit(cx, wfid, NOTHING, order, OMQ::StatReady);
    QDBG_LOG("Control::execSynchronousWorkflow() created wfiid %d", wfiid);

    # issue #1981: clear authentication info and other tld for workflow execution
    TldClearHelper tch("index", "wf", "wfe", "stepID", "ind", "sync");

    string id = setupWorkflow(cx, wfid, wfiid, OMQ::WM_Normal, opts, True, "executing synchronous workflow");
    QDBG_LOG("Control::execSynchronousWorkflow index %y -> %y", tld.index, id);
    tld.index = id;

    # issue #2647: add to the index map
    if (*string parent = tch.getOldValue("index")) {
        tld.index_map{parent}{id} = True;
    }

    on_exit
        workflowStopped(id);

    return execHash{id}.execSynchronousOrderCreated();
}

# returns the workflow_instanceid and execution id on success, exception if error
hash<auto> OMQ::Control::execSynchronousWorkflowAsync(hash<auto> cx, softstring wfid, OrderData order,
        *hash<auto> opts) {
    QDBG_ASSERT(ensure_tld());
    *string parent_index = tld.index;
    # issue #1981: clear authentication info and other tld for workflow execution
    TldClearHelper tch("index", "wf", "wfe", "stepID", "ind", "sync");

    # create the workflow order cache entry and saves the parent info, if any
    string wfiid = SM.createSynchronousWorkflowRowCommit(cx, wfid, NOTHING, order, OMQ::StatReady);

    string id = setupWorkflow(cx, wfid, wfiid, OMQ::WM_Normal, opts, True, "executing synchronous workflow");
    on_error {
        workflowStopped(id);
    }

    # execute workflow order synchronously in the background
    background execSynchronousWorkflowBackground(id, wfiid, parent_index);

    return {
        "workflow_instanceid": wfiid.toInt(),
        "execid": id.toInt(),
    };
}

int OMQ::Control::stopAllWorkflows(*hash<auto> cx, *reference h, *string reason) {
    int stopped = 0;

    # issue #2647: check if there is a dependency error with stopping the workflow
    if (tld.index || tld.index_map) {
        throw "STOP-ERROR", "cannot stop all workflows from within a workflow execution instance";
    }

    # lock and stop one workflow at a time
    foreach string wfid in (keys eh) {
        # issue #2467: ensure that this call is wrapped in an atomic action call
        AtomicWorkflowActionHelper atomic_action_helper(wfid);

        # "stop" hash; hash of Counters to wait for to complete workflow stops
        hash<string, Counter> sh;
        {
            # bug 1130: stop workflows with the write lock held since the stop / reset data structure is created in
            #           this lock
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            # if the workflow has disappeared in the meantime, then skip it
            if (!eh{wfid}) {
                continue;
            }

            stopped += stopWorkflowIntern(cx, wfid, \sh, \h, reason, wah.hasRef(wfid));
        }
        if (sh{wfid}) {
            sh{wfid}.waitForZero();
        }
    }

    return stopped;
}

# returns the number of execution instances or 0 if the workflow is already stopping
int OMQ::Control::getExecInstanceCount(softint id) {
    rwl.readLock();
    on_exit rwl.readUnlock();

    return !ch{id} || rh{id} instanceof WorkflowStopData ? 0 : ch{id}.size();
}

# returns the number of execution instances; unlocked, does not take into account any pending workflow stops
# unlocked to avoid locking the Control read lock while holding another lock such as the
# ConnectionDependencyManager write lock to avoid deadlocks
int OMQ::Control::getExecInstanceCountIndication(softint id) {
    return ch{id}.size();
}

# returns: False: OK, True: error
bool OMQ::Control::stopSynchronous(hash<auto> cx, softstring wfiid, *string reason, *reference<auto> h) {
    # first get workflow ID and exec ID
    softstring wfid;
    string id;
    {
        rwl.readLock();
        on_exit rwl.readUnlock();

        *string exec_id = sync_map{wfiid};
        if (!exec_id) {
            QDBG_LOG("wfiid %d is not being executed synchronously (reason %y)", wfiid, reason);
            return True;
        }

        id = exec_id;
        wfid = execHash{id}.wf.workflowid;
    }
    olog(LoggerLevel::INFO, "wfiid %d is being executed synchronously; stopping exec instance %s (reason %y)", wfiid,
        id, reason);
    AtomicWorkflowActionHelper atomic_action_helper(wfid);
    stopWorkflowInstanceAtomic(cx, id, \h, reason);
    olog(LoggerLevel::INFO, "synchronous exec instance %s for wfiid %d stopped", id, wfiid);
    return False;
}

# returns: False: OK, True: error
bool OMQ::Control::stopWorkflowInstance(hash<auto> cx, softstring id, *reference<auto> h, *string reason,
        *bool autostart) {
    # issue #2467: ensure that this call is wrapped in an atomic action call
    # first get workflow ID
    softstring wfid;
    {
        rwl.readLock();
        on_exit rwl.readUnlock();

        if (!execHash{id}) {
            return True;
        }

        wfid = execHash{id}.wf.workflowid;
    }
    AtomicWorkflowActionHelper atomic_action_helper(wfid);
    stopWorkflowInstanceAtomic(cx, id, \h, reason, autostart);
    return False;
}

private bool OMQ::Control::stopWorkflowInstanceAtomic(hash<auto> cx, softstring id, *reference<auto> h,
        *string reason, *bool autostart) {
    checkStopExecInstance(id);

    Counter c;
    {
        rwl.readLock();
        on_exit rwl.readUnlock();

        if (!execHash{id}) {
            return True;
        }

        Workflow wf = execHash{id}.wf;

        string wfstr = sprintf("%s v%s (%d)", wf.name, wf.version, wf.workflowid);
        h{wfstr} = id;

        # if the instance is synchronous or if we are autostarting
        # (meaning that we already have a lock), then just stop it
        if (!autostart && !execHash{id}.isSync()) {
            # if reset in progress, wait until complete; return immediately if already stopping
            if (waitForStatus(wf.workflowid, WWC_RetStop))
                throw "STOP-ERROR", "workflow is already stopping";

            # make sure wf exec instance is still there
            if (!execHash{id})
                return True;
        }

        if (execHash{id}.setStop(cx, reason)) {
            throw "STOP-ERROR", "workflow is already stopping";
        }

        # get stop counter
        c = eh{wf.workflowid}{id};
    }
    c.waitForZero();

    return False;
}

# always called in the (rwl) write lock
int OMQ::Control::stopWorkflowIntern(*hash<auto> cx, string wfid, reference<hash<string, Counter>> sh, *reference h,
        *string reason, *bool pause) {
    QDBG_ASSERT(rwl.writeLockOwner());
    QDBG_LOG("Control::stopWorkflowIntern stopping wfid: %y tld.index: %y pause: %y", wfid, tld.index,
        pause.toBool());
    int stopped = 0;

    # NOTE: tld.index may be NOTHING here!
    if (tld.index && eh{wfid}.(tld.index)) {
        throw "STOP-ERROR", sprintf("cannot stop execution instance %d from within the same execution instance",
            tld.index);
    }

    # wait for any resets or stops to complete before continuing
    waitForStatus(wfid);

    # skip if there are no active workflow execution instances of this type anymore
    # the status could have changed during waitForStatus()
    if (!eh{wfid}) {
        return 0;
    }

    QDBG_LOG("stopping wfid %d: exec: %y running execHash: %y", wfid, keys eh{wfid}, keys execHash);
    Workflow wf = execHash{eh{wfid}.firstKey()}.wf;
    olog(LoggerLevel::INFO, "workflow %s v%s (%d): stopping %d exec instance%s%s", wf.name, wf.version, wfid,
        eh{wfid}.size(), eh{wfid}.size() == 1 ? "" : "s", reason ? "; " + reason : NOTHING);

    try {
        # tell SegmentManager to stop caching workflow data
        # feature 1081: allow temporarily disabled workflows to be put on pause
        *bool stop_counter_set;
        if (!pause) {
            # issue #3668: decrement stop counter if set here and then there are no instances to stop
            stop_counter_set = SM.stopWorkflow(wfid);
        }

        # set the stop flag for this workflow name & ver
        WorkflowStopData sd();
        rh{wfid} = sd;

        list<string> l = ();
        foreach string id in (keys eh{wfid}) {
            if (!execHash{id}.setStop(cx, reason)) {
                l += id;
                ++stopped;
                if (!sh{wfid}) {
                    sh{wfid} = sd.cStop;
                }
            }
        }

        # issue #3668: remove stop data structure if no wf exec instances were stopped
        if (!stopped) {
            remove rh{wfid};
            if (stop_counter_set) {
                SM.stopAborted(wfid);
            }
        }

        *hash<auto> wfh = Qorus.qmm.lookupWorkflow(wfid, False);
        # the above call might not return a value in case the workflow has been deleted while running
        # this could happen in a development or test instance but should not happen in a production instance
        if (wfh) {
            string wfstr = sprintf("%s v%s (%d)", wfh.name, wfh.ver, wfid);
            h{wfstr} = l;
        }

        QDBG_LOG("Control::stopWorkflowIntern finished wfid = %y tld.index = %y stopped = %y", wfid, tld.index,
            stopped);
        return stopped;
    } catch (hash<ExceptionInfo> ex) {
        olog(LoggerLevel::INFO, "error stopping workflow %s v%s (%d): %s", wf.name, wf.version, wfid,
            get_exception_string(ex));
        rethrow;
    }
}

# stops all instances of given workflow; this call must be made wrapped in an atomic action call
int OMQ::Control::stopWorkflowId(*hash<auto> cx, softstring wfid, *reference h, *string reason, *bool dep) {
    # issue #2467: ensure that this call is wrapped in an atomic action call
    QDBG_ASSERT(AtomicClassActionHelper::isLocked(AtomicClassActionHelper::C_Workflow, wfid));

    # issue #2647: check if there is a dependency error with stopping the workflow
    checkStopWorkflow(wfid);

    # feature 1081: discard any and all saved queue references if the workflow is set to deprecated
    # or disabled (this method is called when the workflow's deprecated flag is set to True and
    # when the workflow is a member of a disabled group)
    if (dep) {
        wah.clear(wfid);
    }

    int stopped = 0;

    # "stop" hash; hash of Counters to wait for to complete workflow stops
    hash<string, Counter> sh;
    {
        # bug 1130: stop workflows with the write lock held since the stop / reset data structure is created in this
        #           lock
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (eh{wfid}) {
            # issue #2467 do not call SegmentManager::stopWorkflow() on workflows with autostart > 1
            # in this case, the stop action will not complete
            stopped += stopWorkflowIntern(cx, wfid, \sh, \h, reason, wah.hasRef(wfid));
        }
    }

    # wait for all wfs to acknowledge stopping
    map $1.waitForZero(), sh.iterator();

    return stopped;
}

# feature 1081: stops all instances of the given workflow without unloading the queues
OMQ::Control::pauseWorkflow(string name, string version, softstring wfid, string reason) {
    # "stop" hash; hash of Counters to wait for to complete workflow stops
    hash<string, Counter> sh;

    {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (!eh{wfid} || rh{wfid})
            return;

        stopWorkflowIntern(NOTHING, wfid, \sh, NOTHING, reason, True);
    }

    # wait for all wfs to acknowledge stopping
    map $1.waitForZero(), sh.iterator();
}

# stops all instances of given workflow
int OMQ::Control::stopWorkflow(*hash<auto> cx, string name, *string version, *reference h, *string reason) {
    int stopped = 0;

    # get list of wfs to stop
    softlist<auto> l = exists version
        ? Qorus.qmm.rLookupWorkflow(name, version).workflowid
        : (map $1.workflowid, (Qorus.qmm.rLookupWorkflow(name) - ("lvcreated", "lastversion")).iterator());
    QDBG_LOG("STOP WORKFLOW name: %y version: %y l: %y", name, version, l);

    # issue #2647: check if there is a dependency error with stopping the workflow(s)
    map checkStopWorkflow($1), l;

    # issue #2467: ensure that this call is wrapped in an atomic action call
    AtomicMultiClassActionHelper atomic_action_helper(l);

    # "stop" hash; hash of Counters to wait for to complete workflow stops
    hash<string, Counter> sh;
    {
        # bug 1130: stop workflows with the write lock held since the stop / reset data structure is created in this
        #           lock
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        foreach softstring wfid in (l) {
            if (!eh{wfid}) {
                continue;
            }

            stopped += stopWorkflowIntern(cx, wfid, \sh, \h, reason, wah.hasRef(wfid));
        }
    }

    # wait for all wfs to acknowledge stopping
    map $1.waitForZero(), sh.iterator();

    QDBG_LOG("STOP WORKFLOW stopped: %y", stopped);
    return stopped;
}

softlist OMQ::Control::getWorkflowCache() {
    rwl.readLock();
    on_exit rwl.readUnlock();

    return map ("name": $1.name, "version": $1.version, "workflowid": $1.workflowid, "cached": $1.cached),
        wfc.iterator();
}

*Workflow OMQ::Control::tryGetWorkflow(softstring wfid) {
    return wfc{wfid};
}

Workflow OMQ::Control::getWorkflow(softstring wfid) {
    # first try to use read lock
    {
        rwl.readLock();
        on_exit rwl.readUnlock();

        if (wfc{wfid})
            return wfc{wfid};
    }

    # copy cached workflow information to workflow instance
    rwl.writeLock();
    on_exit rwl.writeUnlock();

    return getWorkflowIntern(wfid);
}

# called with the write lock held
private Workflow OMQ::Control::getWorkflowIntern(softstring wfid) {
    if (!wfc{wfid}) {
        #QDBG_LOG("Control::getWorkflowIntern() creating %y, stack: %N", wfid, get_stack());
        wfc{wfid} = new Workflow(wfid);
    }

    return wfc{wfid};
}

private OMQ::Control::doCompleteResetTryAutoStart(*hash<auto> cx, softlist<softint> wfids,
        *ClusterWorkflowRestartState cwrs) {
    if (cwrs) {
        cwrs.doBackground(\completeResetTryAutoStart(), cx, wfids, cwrs);
    } else {
        background completeResetTryAutoStart(cx, wfids);
    }
}

private OMQ::Control::completeResetTryAutoStart(*hash<auto> cx, softlist<softint> wfids,
        *ClusterWorkflowRestartState cwrs) {
    # complete reset for any cluster workflow processes
    if (cwrs) {
        cwrs.restartWorkflows(cx);
    }

    ensure_create_tld();
    foreach softint wfid in (wfids) {
        *hash<auto> wf = Qorus.qmm.lookupWorkflow(wfid);
        #log(LoggerLevel::DEBUG, "Control::completeResetTryAutoStart() checking wfid %d as: %y d: %y ch: %d", wfid,
        #    wf.autostart, wf.deprecated, ch{wf.workflowid}.size());
        if (!wf || wf.autostart < 1 || wf."deprecated" || ch{wf.workflowid}.size() == wf.autostart)
            continue;

        autoStartWorkflow(cx, wf, NOTHING, "autostarting workflows after reset", NOTHING, True);
    }
}

# always called in the write lock
# also the atomic action lock is held for the workflow being reset
private int OMQ::Control::resetWorkflowIntern(ClusterWorkflowRestartState cwrs, *hash<auto> cx, softint wfid,
        *string why) {
    if (waitForStatus(wfid, WWC_RetReset)) {
        wfc{wfid}.logInfo("skipping reset for workflowid %d because another reset is still in progress", wfid);
        return 0;
    }

    if (!why) {
        why = (new ActionReason(cx)).getText();
    }

    # do not delete the Workflow object directly!
    Workflow owf = remove wfc{wfid};
    owf.reset();

    # post reset event
    Qorus.events.postWorkflowCacheReset(cx, owf.name, owf.version, wfid);

    QDBG_LOG("Control::resetWorkflowIntern() starting reset for wfid %d why: %y", wfid, why);

    AbstractWorkflowStopResetData rd = owf.remote
        ? new WorkflowStopResetData()
        : new WorkflowResetData(owf);
    rh{wfid} = rd;

    # add the qwf process to be stopped if it exists
    bool do_remote;
    if (owf.remote && SM.running(wfid)) {
        do_remote = True;
        cwrs.add(wfid, cast<WorkflowStopResetData>(rd));
    }

    # find all running non-temporary workflows and reset them
    foreach string id in (keys execHash) {
        if (id =~ /^temp-/) {
            continue;
        }

        AbstractWorkflowExecutionInstance wi = execHash{id};
        if (wi.wf.name != owf.name || wi.wf.version != owf.version) {
            continue;
        }

        if (wi instanceof RemoteWorkflowExecutionInstance) {
            # if the workflow's not synchronous then stop it
            if (!wi.isSync()) {
                # add to cluster restart list if remote and if not synchronous
                if (do_remote) {
                    cwrs.add(wfid, wi.mode);
                }

                # stop the remote workflow execution instance
                cast<RemoteWorkflowExecutionInstance>(wi).setStop(cx, why);
            } else {
                # stop the remote workflow execution instance after synchronous workflow execution
                cast<RemoteWorkflowExecutionInstance>(wi).setDeferredStop(cx, why);
            }
        } else {
            # start the reset process for local workflow execution instances
            cast<CoreWorkflowExecutionInstance>(wi).setReset(cast<WorkflowResetData>(rd), why);
        }
    }

    # DEBUG
    #log(LoggerLevel::DEBUG, "DEBUG: Control::resetWorkflowIntern(%s, %s) %d instance(s) starting reset", name,
    #    version, rd.total);

    # signal workflows that they may begin the reset process
    if (!rd.beginReset()) {
        QDBG_LOG("Control::resetWorkflowIntern() deleting wfid %d: %y", wfid, rh{wfid}.className());
        delete rh{wfid};
    }

    return 1;
}

*list<auto> OMQ::Control::deleteAllWorkflowCacheEntries(hash<auto> cx) {
    list<auto> l;
    # reset autostart list
    list<int> rasl();
    # remote cluster process restart list
    ClusterWorkflowRestartState cwrs();

    on_exit if (rasl || !cwrs.empty()) {
        doCompleteResetTryAutoStart(cx, rasl, cwrs);
    }

    # issue #2647: first get all workflows to be reset so we can grab the atomic lock for all them at once
    rasl = (map $1.workflowid, wfc.iterator()) ?? ();

    if (rasl) {
        # issue #2647: check if there is a dependency error with resetting the workflow(s)
        map checkResetWorkflow($1), rasl;

        # issue #3405: grabs the atomic action lock; must be performed *before* the Control write lock is acquired,
        # otherwise a deadlock can happen if the locks are grabbed in the reverse order
        cwrs.lock(rasl);

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        on_exit if (rasl) {
            # reset user connection status & dependencies
            Qorus.connections.resetStatus("WORKFLOW", rasl);
        }

        # start reset process
        foreach Workflow wf in (wfc.iterator()) {
            int wfid = wf.workflowid;
            # workflow reset status hash
            hash<auto> wrsh = wf.("name", "version", "workflowid") + {
                "count": resetWorkflowIntern(cwrs, cx, wfid),
            };
            l += wrsh;
        }
    }

    return l;
}

int OMQ::Control::deleteWorkflowCacheEntries(*hash<auto> cx, string name) {
    # get list of wfids to reset
    *hash<auto> wfh = Qorus.qmm.rLookupWorkflow(name) - ("lvcreated", "lastversion");
    if (!wfh) {
        return 0;
    }

    int count = 0;
    # reset autostart list
    list<string> rasl = ();
    # remote cluster process restart list
    ClusterWorkflowRestartState cwrs();

    on_exit if (rasl || !cwrs.empty()) {
        doCompleteResetTryAutoStart(cx, rasl, cwrs);
    }

    {
        # list of workflowids (as strings) of connections to be reset
        # also the list of workflows present that will be reset
        list<string> conl = ();

        # issue #2647: first get all workflows to be reset so we can grab the atomic lock for all them at once
        # start reset process
        foreach hash<auto> wh in (wfh.iterator()) {
            softstring wfid = wh.workflowid;
            # if not running and the autostart flag is set, then try to autostart it
            if (!wfc{wfid}) {
                if (wh.autostart > 0 && !wh.deprecated) {
                    rasl += wfid;
                }
                continue;
            }
            # add to reset autostart list
            rasl += wfid;
            # add to connection reset list
            conl += wfid;
        }

        if (conl) {
            # issue #2647: check if there is a dependency error with resetting the workflow(s)
            map checkResetWorkflow($1), conl;

            rwl.writeLock();
            on_exit rwl.writeUnlock();

            on_exit {
                # reset user connection status & dependencies
                Qorus.connections.resetStatus("WORKFLOW", conl);
            }

            # issue #2647: now lock actions for all workflows about to be reset
            cwrs.lock(conl);

            # start reset process
            map count += resetWorkflowIntern(cwrs, cx, $1), conl;
        }
    }

    return count;
}

OMQ::Control::deleteWorkflowCacheEntry(*hash<auto> cx, softstring wfid, *string why) {
    # remote cluster process restart list
    ClusterWorkflowRestartState cwrs();
    on_exit doCompleteResetTryAutoStart(cx, wfid, cwrs);

    # issue #2647: check if there is a dependency error with resetting the workflow(s)
    checkResetWorkflow(wfid);

    # issue #2647: first lock the workflow to be reset
    # issue #2940: must lock workflows that are being reset that were not previously cached
    #              so that any start action will be made atomically
    # issue #3405: this acquires the atomic action lock, which must be acquired *before* the Control write lock is
    #              acquired or a deadlock can result
    cwrs.lock(wfid);

    rwl.writeLock();
    on_exit rwl.writeUnlock();

    if (wfc{wfid}) {
        on_exit {
            # reset user connection status & dependencies
            Qorus.connections.resetStatus("WORKFLOW", wfid);
        }

        resetWorkflowIntern(cwrs, cx, wfid, why);
    }
}

# returns True on error
*bool OMQ::Control::setWorkflowInstanceOption(hash<auto> cx, softstring id, hash hash) {
    rwl.readLock();
    on_exit rwl.readUnlock();

    if (!execHash{id})
        return True;

    execHash{id}.setOption(hash);
}

auto OMQ::Control::getWorkflowInstanceOption(hash<auto> cx, softstring id, *softlist list) {
    rwl.readLock();
    on_exit rwl.readUnlock();

    if (!execHash{id})
        throw "INVALID-WORKFLOW-EXECUTION-ID", sprintf("there is no workflow with execution ID %y", id);

    return exists list ? execHash{id}.getOption(list) : execHash{id}.getAllOptions();
}

hash OMQ::Control::getAllWorkflowInstanceOptions(hash<auto> cx, softstring id) {
    rwl.readLock();
    on_exit rwl.readUnlock();

    if (!execHash{id})
        throw "INVALID-WORKFLOW-EXECUTION-ID", sprintf("there is no workflow with execution ID %y", id);

    return execHash{id}.getAllOptions();
}

# returns True on error
*bool OMQ::Control::setWorkflowOption(hash<auto> cx, softstring wfid, hash hash) {
    rwl.readLock();
    on_exit rwl.readUnlock();

    Workflow::setWorkflowOption(wfid, hash, exists wfc{wfid});
}

