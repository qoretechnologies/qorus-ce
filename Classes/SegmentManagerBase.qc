# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus SegmentManagerBase class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

const ERROR_LIMIT = 100;

# the following constants are used when calling SegmentManagerBase::checkWorkflowCache()
# or SegmentManagerBase::cacheWorkflowUnlocked()
const OMQ::WC_FOR_CANCEL          = 0;
const OMQ::WC_UPDATE              = 1;
const OMQ::WC_UPDATE_SESSION_ONLY = 2;

# mask for attach flags
const OMQ::WC_ATTACH_MASK         = 0xffff0000;
# flag to do an atomic attach to the order
const OMQ::WC_ATTACH_INITIAL      = 1 << 16;

class OMQ::SegmentManagerBase {
    public {
        # AbstractSegmentWorkflowData cache keyed by workflowid
        hash<string, AbstractSegmentWorkflowData> SWD();
    }

    private {
        # WFEntry cache
        WFEntryCache wdata();

        # hash of block objects keyed by workflowid, hash: int ref, Condition cond
        hash BC;

        # read-write lock
        RWLock rwl();

        # TID of cache thread for delayed workflow instance detaches
        int cacheTid;

        # exit counter for cache thread
        Counter cCount(1);

        # keyed alarm for delayed workflow detaches
        TimedWorkflowCache TWC(Qorus.options, "cache-max", "detach-delay");
    }

    constructor() {
        cacheTid = background cacheThread();
    }

    shutdown() {
        # send termination message to cache thread
        TWC.terminate();
        # wait for cache thread to terminate
        cCount.waitForZero();

        olog(LoggerLevel::INFO, "all workflow data flushed to DB");
    }

    int getWFEntryCacheSize() {
        return wdata.size();
    }

    *WFEntry getWFEntryDebug(softstring wfiid) {
        return wdata.get(wfiid);
    }

    # must be called either in the read lock or in the write lock
    *WFEntry getWFEntryUnlocked(AbstractSegmentWorkflowData swd, softstring wfiid) {
        while (True) {
            *WFEntry wfe = wdata.get(wfiid);
            if (wfe && wfe.waitTransition(swd))
                continue;
            return wfe;
        }
    }

    deleteWorkflowCacheEntry(softstring wfiid) {
        wdata.del(wfiid);
    }

    # NOTE: transaction status handled externally
    # this action is restartable but requires a reset action: WFEntry::resetData()
    private cacheWorkflowIntern(softstring wfid, softstring wfiid, *hash<auto> parent_info, int flags,
            bool get_status, *reference stat_ref, WFEntry wfe, reference old_status, reference q) {
        # get attach code
        int attach_code = flags & WC_ATTACH_MASK;
        # get update status code
        int update_status = flags & ~WC_ATTACH_MASK;

        AbstractSegmentWorkflowData swd = SWD{wfid};

        q = sqlif.cacheWorkflowData(wfiid);
        # save workflow status in stat_ref
        stat_ref = ("status": q.workflowstatus, "status_sessionid": q.status_sessionid);

        if (wfid != q.workflowid)
            throw "ATTACH-ERROR", sprintf("failed to attach to workflow_instanceid %d because it does not have the expected workflowid %d (has %d instead)", wfiid, wfid, q.workflowid);

        q.userkeys = sqlif.getOrderKeys(wfiid);
        #QDBG_LOG("SegmentManagerBase::cacheWorkflowIntern() wfiid: %d keys: %y", wfiid, q.userkeys);

        # set up parent info if not already given
        if (!exists parent_info && q.parent_workflow_instanceid)
            parent_info = q.("parent_workflow_instanceid", "subworkflow");

        # delete all NULL values
        map remove q.$1, keys q, q.$1 === NULL;

        # setup data in WFEntry object
        wfe.init(q.reschedule, q.priority, OMQ::SQLStatMap.(q.workflowstatus),
                OMQ::SQLStatMap.(q.workflowstatus_orig), parent_info,
                q.external_order_instanceid, q.userkeys, q.custom_status,
                q.started, q.feedback, q.operator_lock, q.errors, q.retries);

        # this action requires a reset in case of a transaction restart in case the sensitive data changes
        wfe.setupOrderData(omqp.getOSEncoding(), q.staticdata, q.dynamicdata, q.sensitive_data, q.step_data);
        if (attach_code == WC_ATTACH_INITIAL)
            wfe.claimed = True;

        # DEBUG
        #log(LoggerLevel::DEBUG, "SegmentManagerBase::cacheWorkflowIntern(wfid: %d, wfiid: %d, update_status: %y, get_status: %y)", wfid, wfiid, update_status, get_status);

        # this action requires a reset in case of a transaction restart in case the sensitive data changes
        if (get_status)
            wfe.getWorkflowStatus();

        # set workflow order instance to IN-PROGRESS
        if (update_status) {
            if (q.status_sessionid && q.status_sessionid != Qorus.getSessionId())
                throw "ATTACH-ERROR", sprintf("failed to attach to workflow_instanceid %d because it is owned by foreign session %d", wfiid, q.status_sessionid);

            if (inlist(q.workflowstatus, (OMQ::SQLStatComplete, OMQ::SQLStatCanceled, OMQ::SQLStatBlocked)))
                throw "ATTACH-ERROR", sprintf("cannot cache workflow_instanceid %d because it has status '%s' (%s)", wfiid, q.workflowstatus, OMQ::SQLStatMap.(q.workflowstatus));

            if (update_status == WC_UPDATE) {
                old_status = wfe.setWorkflowInProgressNoCommit();
            } else { # update_status = WC_UPDATE_SESSION_ONLY
                int rows = sqlif.grabWorkflow(wfiid, Qorus.getSessionId());

                if (!rows)
                    throw "ATTACH-ERROR", sprintf("cannot attach to workflow_instanceid %d; status or session error", wfiid);
            }
        }

        # DEBUG
        #log(LoggerLevel::DEBUG, "SegmentManagerBase::cacheWorkflowIntern(wfid: %d, wfiid: %d, get_status: %y)", wfid, wfiid, get_status);
    }

    # returns False for OK, True for error
    # called with the AbstractSegmentWorkflowData write lock held, runs with the lock mostly unlocked, returns with the lock held again
    private bool cacheWorkflowUnlocked(softstring wfid, softstring wfiid, *hash parent_info, int flags,
            bool get_status, *reference stat_ref, *string init_status) {
        # get attach code
        int attach_code = flags & WC_ATTACH_MASK;
        # get update status code
        int update_status = flags & ~WC_ATTACH_MASK;

        AbstractSegmentWorkflowData swd = SWD{wfid};

        # we need to run mostly with the write lock unlocked so first we create a dummy entry with the transition flag set
        # and then release the lock
        WFEntry wfe(swd.wf, wfiid);
        if (init_status)
            wfe.initstatus = wfe.status = init_status;
        wdata.assign(wfe);
        swd.writeUnlock();

        # DEBUG
        #log(LoggerLevel::DEBUG, "DEBUG: SegmentManagerBase::cacheWorkflowUnlocked(wfid: %y, wfiid: %y, parent_info: %y, update_status: %y, get_status: %y)", wfid, wfiid, parent_info, update_status, get_status);

        string old_status;
        hash q;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();
                omqp.beginTransaction();

                # restartable action with reset actions below
                cacheWorkflowIntern(wfid, wfiid, parent_info, flags, get_status, \stat_ref, wfe, \old_status, \q);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    # reset data
                    wfe.resetData();
                    continue;
                }

                wfe.wf.logInfo("ERROR setting up workflow order instance %d: %s: %s: %s", wfiid, get_ex_pos(ex),
                    ex.err, ex.desc);
                wfe.wf.logInfo("%s", get_exception_string(ex));
                swd.writeLock();
                wfe.finalizeTransition();
                wdata.del(wfiid);
                return True;
            }
            trans.reset();
            break;
        }

        # raise system events
        if (old_status)
            wfe.postSetWorkflowInProgress(old_status);
        Qorus.events.postWorkflowDataCached(wfe.wf.name, wfe.wf.version, wfe.wf.workflowid, wfiid,
            OMQ::SQLStatMap.(q.workflowstatus), q.business_error, q.external_order_instanceid, q.userkeys);

        swd.writeLock();
        wfe.finalizeTransition();
        return False;
    }

    # returns False for OK, True for error
    private bool checkWorkflowCache(softstring wfid, softstring wfiid, *hash<auto> parent_info, int flags,
            bool get_status, *reference stat_ref, *string init_status) {
        # get attach code
        int attach_code = flags & WC_ATTACH_MASK;
        # get update status code
        int update_status = flags & ~WC_ATTACH_MASK;

        QDBG_LOG("SegmentManagerBase::checkWorkflowCache() wfid: %y, wfiid: %y, parent_info: %y, update_status: %y, get_status: %y", wfid, wfiid, parent_info, update_status, get_status);
        #QDBG_LOG("SegmentManagerBase::checkWorkflowCache() wdata{%d}: %y", wfiid, wdata.get(wfiid));

        QDBG_ASSERT(SWD{wfid});
        bool lck = !SWD{wfid}.writeLockOwner();
        if (lck) SWD{wfid}.writeLock();
        on_exit if (lck) SWD{wfid}.writeUnlock();

        *WFEntry wfe = getWFEntryUnlocked(SWD{wfid}, wfiid);

        # if the workflow order data instance has not already been cached, then cache it
        if (!wfe)
            return cacheWorkflowUnlocked(wfid, wfiid, parent_info, flags, get_status, \stat_ref, init_status);

        # save workflow status in stat_ref
        stat_ref.status = wfe.status;

        # DEBUG
        QDBG_LOG("SegmentManagerBase::checkWorkflowCache() wfiid %d is already cached, internal status '%s' (%s)", wfiid, OMQ::StatMap.(wdata{wfiid}.status), wdata{wfiid}.status);

        # return True if status is Blocked - i.e. block in progress from attach
        if (wfe.status == OMQ::StatBlocked) {
            wfe.wf.logInfo("cannot attach to workflow_instanceid %d because it has status 'B' (BLOCKED)", wfiid);
            return True;
        }

        # bug 1277: if the step status is needed and not present, then fetch it from the database
        if (get_status)
            wfe.getWorkflowStatusConditional();

        # perform atomic attach if requested
        if (attach_code == WC_ATTACH_INITIAL && wfe.claimInitial())
            return True;

        # update workflow order data instance to IN-PROGRESS
        if (update_status == WC_UPDATE) {
            try {
                wfe.setWorkflowInProgress();
            } catch (hash<ExceptionInfo> ex) {
                wfe.wf.logInfo("cannot attach to workflow_instanceid %d: %s: %s: %s", wfiid, get_ex_pos(ex), ex.err, ex.desc);
                return True;
            }
        }

        # if attach was successful
        # delete any pending detaches
        if (!wfe.refs)
            TWC.deleteKey(wfiid, wfid);

        # reference workflow entry
        wfe.referenceWorkflow();

        QDBG_LOG("SegmentManagerBase::checkWorkflowCache() WI %d workflow %d->%d", wfiid, wdata{wfiid}.refs, wdata{wfiid}.refs + 1);

        return False;
    }

    # creates the initial segment, registers it with the workflow queue, and sets up segment with the WFEntry object
    setupInitialSegment(softstring wfid, softstring wfiid, *softstring sync_wfiid) {
        WFEntry wfe = wdata{wfiid};
        wfe.setupInitialSegment();

        WorkflowQueueBase wq = SWD{wfid}.WC;

        if (sync_wfiid)
            wq.registerInitialSynchronousSegment(sync_wfiid);
        else
            wq.registerInitialSegment(wfiid);
    }

    *string releaseWorkflowInstance(softstring wfid, softstring wfiid, bool do_ready_queue = True,
            *reference<*hash<auto>> eh) {
        QDBG_ASSERT(ensure_tld());
        QDBG_LOG("SegmentManagerBase::releaseWorkflowInstance wfid %y wfiid %y", wfid, wfiid);
        WFEntry wfe = wdata{wfiid};

        # save and restore tld.wfe
        *WFEntry wfe_orig = tld.wfe;
        tld.wfe = wfe;
        on_exit tld.wfe = wfe_orig;

        AbstractSegmentWorkflowData swd = SWD{wfid};
        QDBG_ASSERT(!swd.readLockOwner());

        bool del;
        *string stat;
        {
            bool lck = !swd.writeLockOwner();
            QDBG_LOG("%y: lock owner: %y (derefWorkflowDelete)", swd.uniqueHash(), !lck);
            if (lck) swd.writeLock();
            on_exit if (lck) swd.writeUnlock();

            # mark object for deletion if reference count is 0
            # update "in_del" only in the write lock
            del = wfe.derefWorkflowDelete(\stat);
        }

        QDBG_LOG("SegmentManagerBase::releaseWorkflowInstance() wfiid %d wfid: %d workflow del: %y stat: %y", wfiid, wfid, del, stat);

        if (!del) {
            if (stat) {
                wfe.wf.logInfo("cached workflow instance released with internal status %y (%s)", OMQ::StatMap{stat},
                    stat);
            }

            return stat;
        }

        *int cancel_err_index; # has a value when the order has been canceled with an error
        if (!stat) {
            stat = wfe.releaseWorkflowInstance(\cancel_err_index);
        }
        if (stat) {
            wfe.wf.logInfo("workflow instance released with internal status %y (%s)", OMQ::StatMap{stat}, stat);
        }

        QDBG_LOG("SegmentManagerBase::releaseWorkflowInstance wfiid %d wfid: %d workflow refs: 0 (%y) del: %y stat: %y pi: %y", wfiid, wfid, wfe.refs, del, stat, wfe.parent_info);

        bool err = (stat == OMQ::StatError);

        # set a flag if the workflow is COMPLETE or ERROR
        bool ce = (stat == OMQ::StatComplete || err);

        # set a flag if the data should not be cached
        bool clearCache = ce || (stat == OMQ::StatBlocked || stat == OMQ::StatCanceled);

        # save parent info in case WFEntry object is deleted
        *hash<auto> pi = wfe.parent_info;

        # requeue workflow data if status is READY (has been rescheduled by the attach function)
        if (do_ready_queue && (stat == OMQ::StatReady || stat == OMQ::StatScheduled)) {
            WorkflowQueueBase wq = swd.WC;
            wq.addToWorkflowInstanceQueue(wfiid, wfe.priority, pi, wfe.reschedule);
        } else if (stat == OMQ::StatComplete) {
            wfe.wf.logInfo("total elapsed time for workflow processing: %y", (now_us() - wfe.started));
        }

        if (exists cancel_err_index) {
            # get the error that has caused the cancellation
            eh = wfe.errors[cancel_err_index];
        } else {
            # get last error info if available
            if (err)
                eh = wfe.errors.last();
        }

%ifdef QorusDebugInternals
        if (eh) {
            QDBG_LOG("SegmentManagerBase::releaseWorkflowInstance wfiid %d wfid: %d error %y", wfiid, wfid, eh);
        }
%endif

        # if workflow is COMPLETE or ERROR, or the cache is full, then purge the data
        if (clearCache || TWC.set(wfiid, wfid)) {
            QDBG_LOG("purging wfid %d wfiid %d status %y from the cache", wfid, wfiid, stat);

            # remove from cache if already there
            TWC.deleteKey(wfiid, wfid);

            wfe.flushStatus();
            {
                bool lck = !swd.writeLockOwner();
                QDBG_LOG("%y: lock owner: %y (finalizeTransition)", swd.uniqueHash(), !lck);
                if (lck) swd.writeLock();
                on_exit if (lck) swd.writeUnlock();
                wfe.finalizeTransition();
                QDBG_LOG("SegmentManagerBase::releaseWorkflowInstance() wfiid %d wfid: %d nr: %d wtid: %d deleting wdata", wfiid, wfid, swd.numReaders(), swd.lockTID());
                wdata.del(wfiid);
                QDBG_LOG("SegmentManagerBase::releaseWorkflowInstance() DONE");
            }
        } else {
            #log(LoggerLevel::DEBUG, "storing wfid %d wfiid %d status %y in the cache", wfid, wfiid, stat);

            bool lck = !swd.writeLockOwner();
            if (lck) swd.writeLock();
            on_exit if (lck) swd.writeUnlock();
            wfe.finalizeTransition();
            wdata.store(wfiid);
        }

        QDBG_LOG("SegmentManagerBase::releaseWorkflowInstance wfid: %y, wfiid: %y stat: %y", wfid, wfiid, stat);
        # update subworkflow queue if workflow is a subworkflow and status was COMPLETE or ERROR
        if (pi.subworkflow && ce) {
            updateSubWorkflowQueueIntern(wfiid, pi.parent_workflowid, pi.parent_workflow_instanceid,
                                        pi.parent_stepid, pi.parent_ind, stat);
        }

        return stat;
    }

    *string releaseSegment(softstring wfid, softint segid, softstring wfiid) {
        WFEntry wfe = wdata{wfiid};
        try {
            return wfe.commitReleaseSegment(segid, SWD{wfid}.WC);
        } catch (hash<ExceptionInfo> ex) {
            wfe.wf.logInfo("error releasing segment %d for wfiid: %d (%s sync %y): %s", segid, wfiid, wfe.wf.name, wfe.getSynchronousFlag(), get_exception_string(ex));
            rethrow;
        }
    }

    *string releaseSegmentAndWorkflow(softstring wfid, softint segid, softstring wfiid) {
        QDBG_LOG("SegmentManagerBase::releaseSegmentAndWorkflow wfid %y segid %y wfiid %y", wfid, segid, wfiid);
        WFEntry wfe = wdata{wfiid};
        *string stat = wfe.commitReleaseSegment(segid, SWD{wfid}.WC, False);
        releaseWorkflowInstance(wfid, wfiid);
        return stat;
    }

    *string releaseRetrySegmentAndWorkflow(softstring wfid, softint segid, softstring wfiid) {
        QDBG_LOG("SegmentManagerBase::releaseRetrySegmentAndWorkflow wfid %y segid %y wfiid %y", wfid, segid, wfiid);
        WFEntry wfe = wdata{wfiid};
        *string stat = wfe.commitReleaseSegment(segid, SWD{wfid}.WC, True);
        releaseWorkflowInstance(wfid, wfiid);
        return stat;
    }

    # update the subworkflow queue only if the entry isn't already there
    updateSubWorkflowQueue(softstring wfid, softstring wfiid, softint stepid, int ind, softint prio, softint swfiid, *hash<auto> parent_info, *string stat = OMQ::StatComplete) {
        WorkflowQueueBase wq = SWD{wfid}.WC;
        wq.updateSubWorkflowQueue(wfiid, stepid, ind, prio, swfiid, parent_info, stat);
    }

    # SegmentManager::waitForReadyWorkflow()
    # return NOTHING for no data, or True if data is available
    bool waitForReadyWorkflow(softstring wfid, softint index) {
        QDBG_ASSERT(ensure_tld());
        *WorkflowQueueBase wq = SWD{wfid}.WC;

        # issue 1832: if there is no WorkflowQueue, then we need to exit immediately
        if (!wq)
            return False;

        while (True) {
            *hash qs = wq.waitForReadyWorkflowInstance(index);
            if (!qs)
                return False;

            tld.subWorkflow = qs.subworkflow;

            # cache workflow, WC_UPDATE_SESSION_ONLY=update session, get_status=False
            # only update session, status remains 'Y' until the attach function is called
            # because we may go directly from 'Y' -> 'B'
            if (checkWorkflowCache(wfid, qs.workflow_instanceid, qs.parent_info, WC_UPDATE_SESSION_ONLY | WC_ATTACH_INITIAL, False, NOTHING, OMQ::StatReady)) {
                # error has already been logged by cacheWorkflowUnlocked()
                continue;
            }
            WFEntry wfe = wdata.(qs.workflow_instanceid);

%ifdef QorusDebugInternals
            # DEBUG
            if (exists wfe.status && wfe.status != OMQ::StatReady && wfe.status != OMQ::StatScheduled)
                throw "READY-STATUS-ERROR", sprintf("wfe: %y", wfe);
%endif

            tld.wfe = wfe;

            wfe.wf.logInfo("dequeued READY workflow, starting execution");
            break;
        }
        return True;
    }

    # SegmentManager::waitForDetachedSegment()
    # called in normal mode. the segment cannot already exist
    # returns:
    #  NOTHING
    # or
    #  hash:
    #   workflow_instanceid
    #   parent_info
    *hash<auto> waitForDetachedSegment(softstring wfid, softstring segid, softint index) {
        QDBG_ASSERT(ensure_tld());
        *hash<auto> qs;

        *WorkflowQueueBase wq = SWD{wfid}.WC;

        # issue 1832: if there is no WorkflowQueue, then we need to exit immediately
        if (!wq)
            return;

        while (True) {
            if (*softstring wfiid = tld.sync)
                qs = wq.waitForSynchronousDetachedSegment(index, segid, wfiid);
            else
                qs = wq.waitForDetachedSegment(index, segid);

            # DEBUG
            #log(LoggerLevel::FATAL, "wFDS(%y, %y, %y) qs: %y", workflowid, segid, index, qs);

            if (!qs)
                return;

            setThreadVars(qs);

            wq.wf.logInfo("continuing with segment %d", segid);

            # check workflow cache, WC_UPDATE=update status and session, True=acquire step status
            if (!checkWorkflowCache(wfid, qs.workflow_instanceid, qs.parent_info, WC_UPDATE, True))
                break;
        }

        WFEntry wfe = wdata.(qs.workflow_instanceid);
        # set segment to in-progress
        wfe.grabSegment(segid);
        tld.wfe = wfe;

        return qs;
    }

    # SegmentManager::waitForRetrySegment()
    # is executed for recoveries (RECOVERY mode)
    # returns NOTHING or
    # hash:
    #   workflow_instanceid
    #   parent_info
    *hash<auto> waitForRetrySegment(softint index, softstring wfid, softstring segid) {
        QDBG_ASSERT(ensure_tld());
        *hash<auto> qs;

        *WorkflowQueueBase wq = SWD{wfid}.WC;

        # issue 1832: if there is no WorkflowQueue, then we need to exit immediately
        if (!wq) {
            return;
        }

        while (True) {
            if (*softstring wfiid = tld.sync) {
                qs = wq.getSynchronousRetryEvent(index, segid, wfiid);
            } else {
                qs = wq.getRetryEvent(index, segid);
            }
            if (!qs) {
                return;
            }

            # DEBUG
            #log(LoggerLevel::DEBUG, "SegmentManager::waitForRetrySegment() qs: %y", qs);

            setThreadVars(qs);
            wq.wf.logInfo("found segment %d for retry", segid);

            # check workflow cache, WC_UPDATE=update status and session, True=acquire step status
            if (!checkWorkflowCache(wfid, qs.workflow_instanceid, qs.parent_info, WC_UPDATE, True)) {
                break;
            }

            # otherwise release segment
        }

        WFEntry wfe = wdata.(qs.workflow_instanceid);
        wfe.grabSegment(segid);
        tld.wfe = wfe;

        return qs;
    }

    # workflow queue must be verified in place before calling
    updateQueueUnlocked(softstring wfid, softstring stepid, softint wfiid, softint ind, softint prio, softbool corrected, string queuekey, auto data, *hash<auto> parent_info) {
        QDBG_ASSERT(SWD{wfid}.WC);
        WorkflowQueueBase wq = SWD{wfid}.WC;
        wq.updateQueue(stepid, wfiid, ind, prio, corrected, queuekey, data, parent_info);
    }

    # workflow queue must be verified in place before calling
    postSyncEventIntern(softstring wfid, softstring stepid, softint wfiid, softint ind, softint prio, *hash<auto> parent_info) {
        QDBG_ASSERT(SWD{wfid}.WC);
        WorkflowQueueBase wq = SWD{wfid}.WC;
        wq.postSyncEvent(stepid, wfiid, ind, prio, parent_info);
    }

    # called only during workflow execution, workflow queue must be in place
    updateSubWorkflowQueueStep(softstring wfid, softstring wfiid, softint stepid, int ind, softint prio, softint swfiid, *hash<auto> parent_info, string stat) {
        # DEBUG
        #log(LoggerLevel::DEBUG, "DEBUG: SegmentManagerBase::updateSubWorkflowQueueStep(wfid: %y, wfiid: %y, stepid: %y, ind: %y, swfiid: %y, pwfiid: %y, stat: %y, corrected: %y", wfid, wfiid, stepid, ind, swfiid, pwfiid, stat, corrected);

        QDBG_ASSERT(SWD{wfid}.WC);
        WorkflowQueueBase wq = SWD{wfid}.WC;
        wq.updateSubWorkflowQueue(wfiid, stepid, ind, prio, swfiid, parent_info, stat);
    }

    runDetach(WFEntry wfe, bool in_reset, softstring wfid, softstring wfiid, string status, *softstring eoiid) {
        QDBG_ASSERT(ensure_tld());
        # clear thread-local data and restore on exit
        ThreadLocalData td();
        td.tldCopy(tld);
        on_exit tld.tldCopy(td);
        tld.clear();

        ThreadLocalData temp_tld();
        temp_tld.wfe = wfe;
        string index = Qorus.control.setTemporaryThreadContext(wfid, wfiid, temp_tld);
        #AbstractSegmentWorkflowData swd = SWD{wfid};
        #string index = swd.wf.setTemporaryThreadContext(wfiid, ("wfe": wfe));
        callDetachIntern(Qorus.control.execHash{index}, status, eoiid);
    }

    # sets order keys: only called from wf code
    setOrderKeys(hash<auto> h, bool truncate) {
        WFEntry wfe = tld.wfe;
        cast<WFEntry>(wfe).setOrderKeys(h, truncate);
        Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "keys");
    }

    # appends order keys: only called from wf code
    appendOrderKeys(hash<auto> h, bool truncate) {
        WFEntry wfe = tld.wfe;
        cast<WFEntry>(wfe).appendOrderKeys(h, truncate);
        Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "keys");
    }

    # called while the wf is running
    auto getTempData(auto field) {
        WFEntry wfe = tld.wfe;
        return wfe.tdata.get(field);
    }

    # called while the wf is running
    updateTempData(hash<auto> hsh) {
        WFEntry wfe = tld.wfe;
        wfe.tdata.update(hsh);
    }

    # called while the wf is running
    deleteTempDataKey(softlist<auto> lst) {
        WFEntry wfe = tld.wfe;
        wfe.tdata.deleteKey(lst);
    }

    #! called while the wf is running
    updateTempDataPath(string path, auto value) {
        WFEntry wfe = tld.wfe;
        wfe.tdata.updatePathAndSave(path, value, wfe.workflow_instanceid);
    }

    # called while the wf is running
    auto getDynamicData(auto field) {
        WFEntry wfe = tld.wfe;
        return wfe.ddata.get(field);
    }

    # called while the wf is running
    updateDynamicData(hash<auto> new_data) {
        WFEntry wfe = tld.wfe;
        wfe.ddata.updateAndSave(new_data, wfe.workflow_instanceid);
        Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "dynamic");
    }

    # called while the wf is running
    deleteDynamicDataKey(softlist<auto> lst) {
        WFEntry wfe = tld.wfe;
        if (wfe.ddata.deleteAndSave(lst, wfe.workflow_instanceid)) {
            Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "dynamic");
        }
    }

    #! called while the wf is running
    updateDynamicDataPath(string path, auto value) {
        WFEntry wfe = tld.wfe;
        wfe.ddata.updatePathAndSave(path, value, wfe.workflow_instanceid);
        Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "dynamic");
    }

    # called while the wf is running
    auto getStaticData(*softlist<auto> field) {
        WFEntry wfe = tld.wfe;
        if (!field.val())
            return wfe.sdata;

        if (field.size() == 1)
            return wfe.sdata.(field[0]);

        return wfe.sdata{field};
    }

    # called while the wf is running
    auto getSensitiveData(string skey, string svalue, auto field) {
        WFEntry wfe = tld.wfe;
        return wfe.sensitive_data.get(skey, svalue, field);
    }

    # called while the wf is running
    *hash getSensitiveAlias(string alias, auto field) {
        return cast<WFEntry>(tld.wfe).sensitive_data.getAlias(alias, field);
    }

    # called while the wf is running
    hash getSensitiveMetadata(string skey, string svalue) {
        return cast<WFEntry>(tld.wfe).sensitive_data.getMetadata(skey, svalue);
    }

    # called while the wf is running
    hash getSensitiveMetadataAlias(string alias) {
        return cast<WFEntry>(tld.wfe).sensitive_data.getMetadataAlias(alias);
    }

    # called while the wf is running
    hash getSensitiveAliases() {
        return cast<WFEntry>(tld.wfe).sensitive_data.getAliases();
    }

    # called while the wf is running
    updateSensitiveData(string skey, string svalue, hash hash, *softlist aliases, *hash meta) {
        WFEntry wfe = tld.wfe;
        wfe.sensitive_data.updateAndSave(skey, svalue, hash, aliases, meta, wfe.workflow_instanceid);
        Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "sensitive");
    }

    # called while the wf is running
    updateSensitiveDataAlias(string alias, hash hash, *hash meta) {
        WFEntry wfe = tld.wfe;
        wfe.sensitive_data.updateAndSaveAlias(alias, hash, meta, wfe.workflow_instanceid);
        Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "sensitive");
    }

    # called while the wf is running
    bool deleteSensitiveData(string skey, string svalue) {
        WFEntry wfe = tld.wfe;
        if (wfe.sensitive_data.deleteAndSave(skey, svalue, wfe.workflow_instanceid)) {
            Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "sensitive");
            return True;
        }
        return False;
    }

    # called while the wf is running
    bool deleteSensitiveDataKey(string skey, string svalue, softlist list) {
        WFEntry wfe = tld.wfe;
        if (wfe.sensitive_data.deleteAndSave(skey, svalue, list, wfe.workflow_instanceid)) {
            Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "sensitive");
            return True;
        }
        return False;
    }

    # called while the wf is running
    updateSensitiveDataPath(string skey, string svalue, list<hash<DotInfo>> path, auto value) {
        WFEntry wfe = tld.wfe;
        wfe.sensitive_data.updatePathAndSave(skey, svalue, path, value, wfe.workflow_instanceid);
        Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "sensitive");
    }

    # called while the wf is running
    updateSensitiveDataAliasPath(string alias, list<hash<DotInfo>> path, auto value) {
        WFEntry wfe = tld.wfe;
        wfe.sensitive_data.updatePathAndSaveAlias(alias, path, value, wfe.workflow_instanceid);
        Qorus.events.postWorkflowDataUpdated(wfe.workflowid, wfe.workflow_instanceid, "sensitive");
    }

    # called while the wf is running
    hash getSensitiveDataKeyValues() {
        return cast<WFEntry>(tld.wfe).sensitive_data.getKeyValues();
    }

    *hash tryGetStaticData() {
        *softstring wfiid = tld.wfe.workflow_instanceid;
        if (!wfiid)
            return;
        *hash wh = wdata.getHash(wfiid);
        return wh ? wh.sdata : NOTHING;
    }

    *hash tryGetDynamicData() {
        *softstring wfiid = tld.wfe.workflow_instanceid;
        if (!wfiid)
            return;
        *hash wh = wdata.getHash(wfiid);
        return wh ? wh.ddata : NOTHING;
    }

    *hash tryGetTempData() {
        *softstring wfiid = tld.wfe.workflow_instanceid;
        if (!wfiid)
            return;
        *hash wh = wdata.getHash(wfiid);
        return wh ? wh.tdata.get() : NOTHING;
    }

    static hash<auto> getStepContext() {
        hash<auto> ctx = {
            "stepid": tld.stepID,
            "ind": tld.ind,
        };
        if (!ctx.stepid || !exists ctx.ind) {
            throw "STEP-DATA-ERROR", "cannot access step data when not executing a step";
        }
        return ctx;
    }

    # called while the wf is running
    auto getStepData(auto field) {
        hash<auto> step_ctx = getStepContext();
        WFEntry wfe = tld.wfe;
        return wfe.step_data.get(step_ctx.stepid, step_ctx.ind, field);
    }

    # called while the wf is running
    updateStepData(hash<auto> new_data) {
        hash<auto> step_ctx = getStepContext();
        WFEntry wfe = tld.wfe;
        wfe.step_data.updateAndSave(step_ctx.stepid, step_ctx.ind, new_data, wfe.workflow_instanceid);
        Qorus.events.postWorkflowStepDataUpdated(wfe.workflowid, wfe.workflow_instanceid, step_ctx.stepid, step_ctx.ind);
    }

    # called while the wf is running
    deleteStepDataKey(softlist<auto> keylist) {
        hash<auto> step_ctx = getStepContext();
        WFEntry wfe = tld.wfe;
        if (wfe.step_data.deleteAndSave(step_ctx.stepid, step_ctx.ind, keylist, wfe.workflow_instanceid)) {
            Qorus.events.postWorkflowStepDataUpdated(wfe.workflowid, wfe.workflow_instanceid, step_ctx.stepid, step_ctx.ind);
        }
    }

    #! called while the wf is running
    updateStepDataPath(string path, auto value) {
        hash<auto> step_ctx = getStepContext();
        WFEntry wfe = tld.wfe;
        wfe.step_data.updatePathAndSave(step_ctx.stepid, step_ctx.ind, path, value, wfe.workflow_instanceid);
        Qorus.events.postWorkflowStepDataUpdated(wfe.workflowid, wfe.workflow_instanceid, step_ctx.stepid, step_ctx.ind);
    }

    *hash<auto> tryGetStepData(softstring stepid, int ind) {
        *softstring wfiid = tld.wfe.workflow_instanceid;
        if (!wfiid) {
            return;
        }
        return wdata.getHash(wfiid).step_data{stepid}[ind];
    }

    # gets order keys: only called from wf code
    auto getOrderKeys(*softlist<auto> fl, *reference<bool> missing_input) {
        WFEntry wfe = tld.wfe;
        return wfe.getOrderKeys(fl, \missing_input);
    }

    # only called from wf code
    int needsAttach() {
        WFEntry wfe = tld.wfe;
        return wfe.needsAttach();
    }

    # only called from wf code
    confirmAttachError() {
        WFEntry wfe = tld.wfe;
        wfe.confirmAttachError();
    }

    # only called from wf code
    confirmAttachStop() {
        WFEntry wfe = tld.wfe;
        wfe.confirmAttachStop();
    }

    # only called from wf code
    confirmAttach() {
        WFEntry wfe = tld.wfe;
        wfe.confirmAttach();
    }

    # only called from wf code
    confirmNoAttach() {
        WFEntry wfe = tld.wfe;
        wfe.confirmNoAttach();
    }

    # only called from wf code when an attach error happens
    markReadyWorkflowAsError(softstring wfiid, string reason) {
        WFEntry wfe = wdata{wfiid};
        wfe.markReadyWorkflowAsError(reason);
    }

    detachDelayUpdated() {
        TWC.requeue();
    }

    string getDataCacheAsString() {
        return TWC.toString();
    }

    string getDataCacheSummary() {
        return TWC.getSummary();
    }

    hash<auto> getPriorityWorkflowIDAndParent(softstring wfiid) {
        *hash h = wdata.getParentWorkflowPriority(wfiid);
        if (h)
            return h;

        *hash<auto> q = sqlif.getPriorityWorkflowIDAndParentTrans(wfiid);
        if (!q.workflowid)
            throw "INVALID-WORKFLOW-ORDER-DATA-INSTANCE", sprintf("workflow_instanceid %d does not exist", wfiid);

        q.parent_info = remove q.("parent_workflow_instanceid", "subworkflow");
        return q;
    }

    softstring getWorkflowID(softstring wfiid, *reference priority) {
        # first check cache to see if workflow instance data is cached
        *hash wd = wdata.getParentWorkflowPriority(wfiid);
        if (wd) {
            priority = wd.priority;
            return wd.workflowid;
        }

        *hash h = sqlif.getWorkflowIDAndPriorityTrans(wfiid);
        if (!h.workflowid)
            throw "INVALID-WORKFLOW-ORDER-DATA-INSTANCE", sprintf("workflow_instanceid %d does not exist", wfiid);
        priority = h.priority;
        return h.workflowid;
    }

    string dumpCaches() {
        return foldl $1 + ", " + $2, (map sprintf("%y: %y", $1.key, $1.value.typeCode() == NT_OBJECT ? sprintf("%s object", $1.value.className()) : $1.value), self.pairIterator());
        #return sprintf("%N\n", self);
    }

    cleanupConnection(softstring wfid, softstring index) {
        AbstractSegmentWorkflowData swd = SWD{wfid};
        cast<WorkflowQueueBase>(swd.WC).cleanupConnection(index);
    }

    # for asynchronous array steps, set the array step's status to COMPLETE in the DB, then,
    # if all array steps are COMPLETE, create the backend segment
    # for synchronous workflows, returns:
    #   -1 if all steps have completed, one or more with ERROR or RETRY status
    #    0 if not all steps have a status
    #    1 if all steps are COMPLETE
    int tryCommitAsyncArraySegment(softstring workflowid, softint fesegid, int stepid, int ind) {
        QDBG_ASSERT(ensure_tld());
        softstring wfiid = tld.wfe.workflow_instanceid;
        softint segid = tld.segID;

        WorkflowQueueBase wq = SWD{workflowid}.WC;

        int rc = wdata{wfiid}.updateFrontEndStepStatusTryCreateSegment(segid, fesegid, stepid, ind, wq);
        if (rc > 0) {
            # release front-end segment in segment event queue
            wq.releaseSegment(wfiid, fesegid);
        }
        # if new segment not started, then mark segment as virtual
        else
            tld.virtual = True;

        return rc;
    }

    # creates the backend segment and sets the async step's status to complete
    string commitAsyncSegment(softstring workflowid, softint linksegid, softint linkstepid) {
        softstring wfiid = tld.wfe.workflow_instanceid;
        softint segid = tld.segID;
        string rv;

        WorkflowQueueBase wq = SWD{workflowid}.WC;

        try {
            WFEntry wfe = wdata{wfiid};
            wfe.newAsyncSegment(segid);
            rv = wfe.updateFrontEndStepStatusReleaseSegment(linksegid, linkstepid, 0, OMQ::StatComplete, wq, True);
            wq.releaseSegment(wfiid, linksegid);
        } catch (hash<ExceptionInfo> ex) {
            wq.wf.logInfo("%s", Util::get_exception_string(ex));
            rethrow;
        }
        return rv;
    }

    /*  wfid: the workflow ID of the order
        segid: the front-end segment ID to release
        stepid: the front-end stepid to release
        ind:the step index
        stat: the status of the step
    */
    commitFrontEndStepStatusReleaseSegment(softstring wfid, softint segid, softstring stepid, softlist ind, string stat) {
        QDBG_ASSERT(ensure_tld());
        softstring wfiid = tld.wfe.workflow_instanceid;

        WorkflowQueueBase wq = SWD{wfid}.WC;

        # DEBUG
        #wq.wf.logDebug("commitFrontEndStepStatusReleaseSegment() wfid: %y segid: %y stepid: %y ind: %y stat: %y "
        #    "wfiid: %y", wfid, segid, stepid, ind, stat);

        # update step status and source (front-end) segment
        cast<WFEntry>(wdata{wfiid}).updateFrontEndStepStatusReleaseSegment(segid, stepid, ind, stat, wq, True);

        # release front-end segment in segment event queue
        wq.releaseSegment(wfiid, segid);

        # mark back end segment as virtual
        tld.virtual = True;
    }

    updateFrontEndStepStatus(softstring stepid, softint ind, string stat) {
        QDBG_ASSERT(ensure_tld());
        tld.wfe.updateFrontEndStepStatus(stepid, ind, stat, True);

        # mark back end segment as virtual
        tld.virtual = True;
    }

    # release front end segment when processing async back-end messages
    releaseAsyncFrontEndSegment(softstring wfid, softint segid) {
        softstring wfiid = tld.wfe.workflow_instanceid;

        WorkflowQueueBase wq = SWD{wfid}.WC;

        # update front-end segment status
        wdata{wfiid}.releaseAsyncFrontEndSegment(segid, wq);
        # release front-end segment in segment event queue
        wq.releaseSegment(wfiid, segid);
    }

    # called while the wf is running
    updateStepStatus(softstring stepid, softint ind, string stat) {
        WFEntry wfe = tld.wfe;
        wfe.updateStepStatus(stepid, ind, stat);
    }

    terminateConnections(softstring wfid, softint index) {
        *WorkflowQueueBase wq = SWD{wfid}.WC;
        if (wq)
            wq.terminateConnections(index);
    }

    terminateSynchronousConnections(softstring wfid, softint index, softstring sync) {
        *WorkflowQueueBase wq = SWD{wfid}.WC;
        if (wq)
            wq.terminateSynchronousConnections(sync, index);
    }

    cacheReadyWorkflowSynchronous(string wfid, softstring wfiid, *string expected_status = OMQ::StatReady) {
        QDBG_ASSERT(ensure_tld());
        QDBG_LOG("SegmentManagerBase::cacheReadyWorkflowSynchronous wfid %y wfiid %y", wfid, wfiid);
        hash<auto> info;
        # cache workflow, WC_UPDATE=update status and session, get_status=True
        if (checkWorkflowCache(wfid, wfiid, NOTHING, WC_UPDATE | WC_ATTACH_INITIAL, True, \info))
            throw "WORKFLOW-ERROR", sprintf("error caching workflow_instanceid %d", wfiid), info;

        on_error
            releaseWorkflowInstance(wfid, wfiid);

        WFEntry wfe = wdata{wfiid};

        # if the workflow is ERROR, WAITING, or ASYNC-WAITING, then do an immediate retry
        if (expected_status == OMQ::StatReady) {
            if (wfe.initstatus != OMQ::StatReady && wfe.initstatus != OMQ::StatScheduled) {
                throw "WORKFLOW-ERROR", sprintf("error caching workflow_instanceid %d; expecting status 'Y' (READY) "
                    "or 'S' (SCHEDULED); got '%s' (%s) instead", wfiid, OMQ::StatMap{wfe.initstatus}, wfe.initstatus);
            }
        } else if (wfe.initstatus != expected_status) {
            throw "WORKFLOW-ERROR", sprintf("error caching workflow_instanceid %d; expecting status '%s' (%s); "
                "got '%s' (%s) instead", wfiid, StatMap{expected_status}, expected_status,
                    OMQ::StatMap{wfe.initstatus}, wfe.initstatus);
        }

        tld.wfe = wfe;
        wfe.setSynchronousFlag();

        wfe.wf.logInfo("attached to workflow, starting execution");
    }

    private purgeOrders(softstring wfid) {
        # delete all queued delayed detaches for this workflowid
        list l = TWC.purgeClass(wfid);

        QDBG_LOG("TWC purging wfid %d l: %y", wfid, l);

        if (l) {
            # temporarily erase all thread-local data and restore on exit
            ThreadLocalData td();
            td.tldCopy(tld);
            on_exit tld.tldCopy(td);
            tld.clear();

            list fl;

            {
                SWD{wfid}.writeLock();
                on_exit SWD{wfid}.writeUnlock();

                # need to optimize this operation
                fl = wdata.getFlushAndDelete(l);
            }

            QDBG_LOG("TWC purging wfid %d fl size: %d", wfid, fl.size());

            if (fl) {
                purgeOrdersIntern(wfid, fl);
            }
        }
    }

    # NOTE: synchronous workflows will never be passed to this function
    private recursiveSubWorkflowErrorUpdate(*hash w, softint swfiid) {
        do {
            # note: this will grab and release the lock for each iteration of the loop
            rwl.readLock();
            on_exit rwl.readUnlock();

            # see if workflowid is queued
            if (SWD.(w.workflowid)) {
                WorkflowQueueBase wq = SWD.(w.workflowid).WC;
                wq.updateSubWorkflowQueue(w.workflow_instanceid, w.stepid, w.ind, w.priority, swfiid, w.parent_info, OMQ::StatError);
                return;
            }

            swfiid = w.workflow_instanceid;
            # try to update with SQL
            w = commitStepAndWorkflowErrorStatus(w, sprintf("subworkflow: %d bound to stepid %d/%d is ERROR", w.subworkflow_instanceid, w.stepid, w.ind));
        } while (w);
    }

    # SegmentManager::waitForSubWorkflowEvent()
    # waits for a subworkflow message
    # grab the workflow order instance and segment
    # returns a hash:
    #   workflow_instanceid
    #   list: ind
    #   parent_info
    # always called in normal mode
    *hash waitForSubWorkflowEvent(softint index, softstring wfid, softint stepid, softstring segid, softstring fesegid) {
        QDBG_ASSERT(ensure_tld());
        # DEBUG
        QDBG_LOG("SegmentManager::waitForSubWorkflowEvent index %y wfid %y stepid %y segid %y fesegid %y", index, wfid, stepid, segid, fesegid);

        AbstractSegmentWorkflowData swd = SWD{wfid};
        *WorkflowQueueBase wq = swd.WC;

        # issue 1832: if there is no WorkflowQueue, then we need to exit immediately
        if (!wq)
            return;

        *softint sync_wfiid = tld.sync;
        *hash qs;
        while (True) {
            while (True) {
                # unset virtual flag
                on_exit { tld.virtual = NOTHING; }

                qs = wq.getSubWorkflowEvent(index, fesegid, segid);
                if (!qs) {
                    QDBG_LOG("SegmentManager::waitForSubWorkflowEvent index %y wfid %y stepid %y segid %y fesegid %y NO EVENT", index, wfid, stepid, segid, fesegid);
                    return;
                }

                qs.status = OMQ::SQLStatMap.(qs.status);

                QDBG_LOG("SegmentManager::waitForSubWorkflowEvent qs: %y", qs);

                # BUG 627: do not set "ind" (list) in thread-local data
                # FIXME - but setThreadVars sets only "ind", right? --PQ 16-Jun-2016
                setThreadVars(qs - "ind");

                if (elements qs.ind == 1)
                    swd.wf.logInfo("subworkflow instanceid %d bound to step: %d/%d is '%s' (%s), updating front-end segment %d", qs.subworkflow_instanceid, stepid, qs.ind[0], OMQ::StatMap.(qs.status), qs.status, fesegid);
                else
                    swd.wf.logInfo("subworkflow instances bound to step: %d/%y are '%s' (%s), updating front-end segment %d", stepid, qs.ind, OMQ::StatMap.(qs.status), qs.status, fesegid);

                if (qs.status != OMQ::StatError)
                    break;

                AutoReadLock al(swd);

                #log(LoggerLevel::DEBUG, "DEBUG: updating workflow %y from errored subworkflow %y (cached: %y, fesegid: %y, stepid: %y, ind: %y, stat: %y)", qs.workflow_instanceid, qs.subworkflow_instanceid, exists wdata.(qs.workflow_instanceid), fesegid, stepid, qs.ind, qs.status);

                *WFEntry wfe = getWFEntryUnlocked(swd, qs.workflow_instanceid);

                # if status is ERROR, then just update step status and release segment
                if (wfe) {
                    # reference workflow, but don't create segment_instance row
                    wfe.referenceWorkflow();

                    # release the read lock
                    delete al;

                    on_exit # release workflow on exit
                        releaseWorkflowInstance(wfid, qs.workflow_instanceid);

                    # signal synchronous workflow to exit due to ERROR status
                    if (sync_wfiid)
                        Qorus.control.execHash{tld.index}.setStop();

                    # update and release the front-end segment
                    wfe.updateFrontEndStepStatusReleaseSegment(fesegid, stepid, qs.ind, OMQ::StatError, wq);
                    # mark segment as virtual
                    tld.virtual = True;

                    # release the front-end segment
                    wq.releaseSegment(qs.workflow_instanceid, fesegid);
                } else {
                    #log(LoggerLevel::DEBUG, "DEBUG: updating workflow %y from errored subworkflow %y (not cached: %y, fesegid: %y, stepid: %y, ind: %y, stat: %y)", qs.workflow_instanceid, qs.subworkflow_instanceid, exists wdata.(qs.workflow_instanceid), fesegid, stepid, qs.ind, qs.status);

                    *hash nqs;

                    qs.segid      = fesegid;
                    qs.stepid     = stepid;

                    # recursively update status with SQL
                    nqs = commitStepAndWorkflowErrorStatus(("workflowid": wfid) + qs, sprintf("subworkflow: %y bound to stepid %d/%y %s ERROR", qs.subworkflow_instanceid, stepid, qs.ind, elements qs.ind == 1 ? "is" : "are"));

                    # release segment in workflow queue, workflow is not cached and cannot be cached while the lock is held
                    wq.releaseSegment(qs.workflow_instanceid, fesegid);

                    # release the read lock
                    delete al;

                    if (exists nqs)
                        recursiveSubWorkflowErrorUpdate(nqs, qs.workflow_instanceid);
                }
            }

            # log data
            #log(LoggerLevel::INFO, "trying to connect to segment %d", segid);

            # check workflow cache, WC_UPDATE=update status and session, True=acquire step status
            if (checkWorkflowCache(wfid, qs.workflow_instanceid, qs.parent_info, WC_UPDATE, True)) {
                wq.releaseSegment(qs.workflow_instanceid, fesegid);

                continue;
            }

            WFEntry wfe = wdata.(qs.workflow_instanceid);

            # check if segment can really start - WFentry::startAsyncSegment() returns -1 = error, 0 = OK
            # WFEntry::startAsyncSegment() will release the front-end segment in the segment event queue and reference the back-end segment
            if (wfe.startAsyncSegment(segid, stepid, qs.ind, fesegid, wq)) {
                releaseWorkflowInstance(wfid, qs.workflow_instanceid);
                continue;
            }

            tld.wfe = wfe;

            return qs;
        }
    }

    # SegmentManager::waitForSyncEvent()
    # grab the workflow order instance and segment
    # returns a hash:
    #   workflow_instanceid
    #   list: ind
    #   parent_info
    # always called in normal mode
    *hash<auto> waitForSyncEvent(softint index, softstring wfid, softstring stepid, softint segid, softint fesegid) {
        QDBG_ASSERT(ensure_tld());
        QDBG_LOG("SegmentManager::waitForSyncEvent index: %y, wfid: %y, stepid: %y", index, wfid, stepid);

        AbstractSegmentWorkflowData swd = SWD{wfid};
        *WorkflowQueueBase wq = swd.WC;

        # issue 1832: if there is no WorkflowQueue, then we need to exit immediately
        if (!wq)
            return;

        #*softint sync_wfiid = tld.sync;
        *hash<auto> qs;
        while (True) {
            while (True) {
                qs = wq.getSyncEvent(index, fesegid, segid);
                if (!qs)
                    return;

                # BUG 627: do not set "ind" (list) in thread-local data
                setThreadVars(qs - "ind");
                if (qs.corrected)
                    swd.wf.logInfo("synchronization event step: %d/%y was skipped, updating segment %d", stepid, qs.ind, fesegid);
                else
                    swd.wf.logInfo("synchronization event for step: %d/%y has been posted, updating segment %d", stepid, qs.ind, fesegid);

                break;
            }

            # log data
            #log(LoggerLevel::DEBUG, "DEBUG: segment %d: got %y", segid, qs);
            #log(LoggerLevel::INFO, "trying to connect to segment %d", segid);

            # check workflow cache, WC_UPDATE=update status and session, True=acquire step status
            if (checkWorkflowCache(wfid, qs.workflow_instanceid, qs.parent_info, WC_UPDATE, True)) {
                wq.releaseSegment(qs.workflow_instanceid, fesegid);

                continue;
            }

            #log(LoggerLevel::DEBUG, "DEBUG: got wf");

            WFEntry wfe = wdata.(qs.workflow_instanceid);

            # check if segment can really start - WFentry::startAsyncSegment() returns -1 = error, 0 = OK
            # WFEntry::startAsyncSegment() will release the front-end segment in the segment event queue and reference the back-end segment
            if (wfe.startAsyncSegment(segid, stepid, qs.ind, fesegid, wq)) {
                #log(LoggerLevel::DEBUG, "DEBUG: start async segment FAILED");
                releaseWorkflowInstance(wfid, qs.workflow_instanceid);
                continue;
            }

            #log(LoggerLevel::DEBUG, "DEBUG: start async segment OK");

            tld.wfe = wfe;

            return qs;
        }
    }

    # note that corrected will be set to True if the backend segment was already created, so the step is already COMPLETE
    # returns hash:
    #  workflow_instanceid
    #  parent_info (only if submitted internally)
    #  list:ind
    #  list:data (only if !corrected)
    #  list:corrected
    #  list:queuekey
    *hash<auto> waitForQueueSegment(softint index, softint queueid, softstring wfid, softstring segid, softint stepid, softstring fesegid) {
        QDBG_ASSERT(ensure_tld());
        QDBG_LOG("SegmentManager::waifForQueueSegment index: %y, wfid: %y, segid: %y, stepid: %y", index, wfid, segid, stepid);
        *hash qs;

        AbstractSegmentWorkflowData swd = SWD{wfid};
        *WorkflowQueueBase wq = swd.WC;

        # issue 1832: if there is no WorkflowQueue, then we need to exit immediately
        if (!wq)
            return;

        #*softint sync_wfiid = tld.sync;
        while (True) {
            # unset virtual flag
            on_exit { tld.virtual = NOTHING; }

            qs = wq.getAsyncEvent(index, fesegid, segid);
            if (!qs)
                return;

            #log(LoggerLevel::DEBUG, "DEBUG: SegmentManager::waitForQueueSegment() qs: %y", qs);

            list err = ();

            foreach auto data in (qs.data) {
                int ind = qs.ind[$#];
                string queuekey = qs.queuekey[$#];
                bool corrected = qs.corrected[$#];

                # data will not exist if queued from the DB, in this case, it's only read in and processed here
                if (!corrected && !exists data) {
                    # get the rest of the data (reget "corrected" in case the entry was corrected since it's been queued)
                    hash q = sqlif.getQueueAndWorkflowInfoTrans(queueid, queuekey);

                    # if the queue data has already been processed, then ignore it
                    if (q.queue_data_status == 'X') {
                        #swd.wf.logInfo("queue entry already processed; queueid: %d; ignoring", queueid);
                        continue;
                    }

                    # set up parent_info structure, but do not overwrite if already present
                    if (!exists qs.parent_info)
                        qs.parent_info = q.("parent_workflow_instanceid", "subworkflow");

                    corrected = qs.corrected[$#] = boolean(q.corrected);

                    try {
                        if (q.queue_data_status != 'R')
                            throw "QUEUE-STATUS-ERROR", sprintf("expecting status 'R', got '%s'; status changed since submitted to the queue", q.queue_data_status);
                        data = qs.data[$#] = deserialize_qorus_data(q.data);
                    } catch (hash<ExceptionInfo> ex) {
                        swd.wf.logFatal("invalid queue entry, queueid: %d, marking as ERROR (%s: %s): queue row: %y", queueid, ex.err, ex.desc, q);
                        # set entry status to error
                        QorusRestartableTransaction trans();
                        while (True) {
                            try {
                                on_error omqp.rollback();
                                on_success omqp.commit();

                                sqlif.setQueueDataError(queueid, queuekey);
                                QDBG_TEST_CLUSTER_FAILOVER();
                            } catch (hash<ExceptionInfo> ex1) {
                                # restart the transaction if necessary
                                if (trans.restartTransaction(ex1))
                                    continue;

                                olog(LoggerLevel::FATAL, "error setting 'ERROR' status on queue entry: %s: %s", ex1.err, ex1.desc);
                            }
                            trans.reset();
                            break;
                        }

                        # add current element to error list
                        err += $#;
                    }
                } else if (!exists qs.parent_info) {
                    # get parent_workflow_instanceid
                    hash q = sqlif.getParentAndStatusFromQueueTrans(queueid, queuekey);

                    #qs.status_sessionid = q.status_sessionid;
                    qs.parent_info = q.("parent_workflow_instanceid", "subworkflow");
                }
            }

            # if there is an error list, remove errored elements from data
            if (err && SegmentManagerBase::removeAsyncErrors(\qs, err)) {
                wq.releaseSegment(qs.workflow_instanceid, fesegid);
                return;
            }

            # DEBUG
            #log(LoggerLevel::DEBUG, "qs: %y", qs);

            # BUG 627: do not set "ind" (list) in thread-local data
            setThreadVars(qs - "ind");
            # log data
            swd.wf.logInfo("setting up async backend for key: %y, seg: %d, step: %d/%y (corrected: %y)", qs.queuekey, segid, stepid, qs.ind, qs.corrected);

            bool ok = False;
            on_exit {
                if (!ok)
                    tld.ind = NOTHING;
            }

            # first see if we can attach to the workflow
            # check workflow cache, WC_UPDATE=update status and session, True=acquire step status
            if (checkWorkflowCache(wfid, qs.workflow_instanceid, qs.parent_info, WC_UPDATE, True)) {
                swd.wf.logInfo("discarding queue data: cannot attach to workflow");
                QorusRestartableTransaction trans();
                while (True) {
                    try {
                        on_error omqp.rollback();
                        on_success omqp.commit();

                        sqlif.discardQueueDataUnconditional(queueid, qs.queuekey);
                        QDBG_TEST_CLUSTER_FAILOVER();
                    } catch (hash<ExceptionInfo> ex) {
                        # restart the transaction if necessary
                        if (trans.restartTransaction(ex))
                            continue;
                        rethrow;
                    }
                    trans.reset();
                    break;
                }

                # release segment in workflow queue
                wq.releaseSegment(qs.workflow_instanceid, fesegid);
                continue;
            }

            on_exit {
                if (!ok) {
                    wq.releaseSegment(qs.workflow_instanceid, fesegid);
                    releaseWorkflowInstance(wfid, qs.workflow_instanceid);
                }
            }

            WFEntry wfe = wdata.(qs.workflow_instanceid);

            list os = ();

            try {
                if (wfe.startAsyncStepBackEnd(\qs, stepid, queueid, \os)) {
                    swd.wf.logInfo("discarding queue data, duplicate message received");

                    QorusRestartableTransaction trans();
                    while (True) {
                        try {
                            on_error omqp.rollback();
                            on_success omqp.commit();

                            sqlif.discardQueueDataUnconditional(queueid, qs.queuekey);
                            QDBG_TEST_CLUSTER_FAILOVER();
                        } catch (hash<ExceptionInfo> ex) {
                            # restart the transaction if necessary
                            if (trans.restartTransaction(ex))
                                continue;
                            rethrow;
                        }
                        trans.reset();
                        break;
                    }
                    continue;
                }
            } catch (hash<ExceptionInfo> ex) {
                swd.wf.logFatal("unexpected exception: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                swd.wf.logFatal("this workflow will be left in an invalid status due to this error");
                continue;
            }

            tld.wfe = wfe;

            if (exists wfe.seg[segid]) {
                for (int i = 0; i < elements qs.corrected; ++i)
                    qs.corrected[i] = True;
            }

            # reference backend segment in segment event queue
            if (wq.grabSegmentIncrement(qs.workflow_instanceid, segid)) {
                # bug 667: if there is a race condition and a retry is in progress, then discard the queue entry
                wfe.wf.logFatal("unexpected async event for key: %y, seg: %d, step: %d/%y (corrected: %y) during recovery; discarding message", qs.queuekey, segid, stepid, qs.ind, qs.corrected);

                wfe.releaseAsyncBackendSteps(qs, stepid, os);
                continue;
            }

            ok = True;

            # reference workflow, but don't create segment_instance row
            ++wfe.refs;
            break;
        }

        return qs;
    }

    # no locking needed here as this is only called from the WorkflowInstance object executing a synchronous workflow
    WFEntry getWorkflowEntry(softstring wfiid) {
        return wdata{wfiid};
    }

    string createSynchronousWorkflowCommit(softstring wfid, *hash<auto> parent_info, OrderData order, string status = OMQ::StatInProgress, *bool swf) {
        string wfiid;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                wfiid = createSynchronousWorkflowRowNoCommit(wfid, order, status).toString();
                if (swf) {
                    # now we create the subworkflow_instance row
                    QDBG_ASSERT(parent_info);
                    createSubWorkflowInstanceRowNoCommit(parent_info.parent_workflow_instanceid, parent_info.parent_stepid, parent_info.parent_ind, wfiid);
                }
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        return wfiid;
    }

    # SegmentManagerBase::createCacheSynchronousWorkflowCommit()
    # returns on success:
    #    * workflow_instanceid
    string createCacheSynchronousWorkflowCommit(hash<auto> cx, softstring wfid, *hash<auto> parent_info, OrderData order, string status = OMQ::StatInProgress, *bool swf) {
        QDBG_ASSERT(SWD{wfid});
        AbstractSegmentWorkflowData swd = SWD{wfid};

        # issue #2495: if parent_info is not set and order has a parent, then use it
        if (!parent_info && order.parent_workflow_instanceid) {
            parent_info = {
                "parent_workflow_instanceid": order.parent_workflow_instanceid,
                "subworkflow": False,
            };
        }

        swd.writeLock();
        on_exit swd.writeUnlock();

        string wfiid = createSynchronousWorkflowCommit(wfid, parent_info, order, status, swf);

        # emit system event for workflow creation
        Qorus.events.postWorkflowDataSubmitted(cx, order.getName(), order.getVersion(), wfid, wfiid, status,
            order.parent_workflow_instanceid, order.subworkflow);

        on_error {
            # here it's not possible for the WFEntry to be in a transition state, but we will use
            # the standard solution anyway
            *WFEntry wfe = getWFEntryUnlocked(swd, wfiid);
            if (wfe) {
                wfe.flushStatus();
                wdata.del(wfiid);
            }
        }

        # issue 1605: the synchronous workflow order is registered and deregistered with the
        # WorkflowQueue class by the WorkflowInstance class - not here

        WFEntry wfe = new WFEntry(swd.wf, wfiid, order, status, NOTHING, parent_info);
        wdata.assign(wfe);
        wfe.setSynchronousFlag();

        # DEBUG
        #log(LoggerLevel::DEBUG, "createSynchronousWorkflow() WI %d workflow %d->%d", wfiid, wdata{wfiid}.refs, wdata{wfiid}.refs + 1);
        return wfiid;
    }

    # returns True if the order was saved in the cache, False if not (cache full)
    private bool saveOrderInCacheIntern(WFEntry wfe) {
%ifdef QorusDebugInternals
        if (wfe.refs)
            throw "WFENTRY-CACHE-ERROR", sprintf("order %d sent to cache with refs: %d", wfe.workflow_instanceid, wfe.refs);
%endif

        wdata.assign(wfe);

        # try to add cache TTL
        if (!TWC.set(wfe.workflow_instanceid, wfe.workflowid)) {
            # compress the data
            wdata.store(wfe.workflow_instanceid);
            return True;
        }

        # if cache is full, then delete
        wdata.del(wfe.workflow_instanceid);
        return False;
    }

    # assumes that wfid is cached (SWD{wfid} exists) and that block() has been called
    cacheReadyOrder(softstring wfiid, softstring wfid, OrderData order, *hash<auto> parent_info) {
        #log(LoggerLevel::DEBUG, "cacheReadyOrder() wfiid: %y wfid: %y data: %y parent_info: %y", wfiid, wfid, data, parent_info);
        AbstractSegmentWorkflowData swd = SWD{wfid};

        string stat = order.scheduled > now() ? OMQ::StatScheduled : OMQ::StatReady;

        # issue #2495: set the parent_workflow_instanceid explicitly if necessary
        if (order.parent_workflow_instanceid && !parent_info.parent_workflow_instanceid) {
            parent_info = {
                "parent_workflow_instanceid": order.parent_workflow_instanceid,
                "subworkflow": False,
            };
        }

        # create cache entry
        WFEntry wfe(swd.wf, wfiid, order, stat, stat, parent_info);
        # refs should be 0 in cache
        --wfe.refs;

        {
            swd.writeLock();
            on_exit swd.writeUnlock();

            saveOrderInCacheIntern(wfe);
        }

        swd.WC.addToWorkflowInstanceQueue(wfiid, order.priority, parent_info, order.scheduled);
    }

    setSubWorkflowInfo(hash<auto> parent_info, string wfiid) {
        # update subworkflow info in parent entry
        wdata.(parent_info.parent_workflow_instanceid).setSubWorkflowInfo(parent_info.parent_stepid, parent_info.parent_ind, wfiid);
    }

    hash<auto> retryWorkflowOrderCached(*hash<auto> cx, string wfiid, hash<auto> wh) {
        AbstractSegmentWorkflowData swd = SWD.(wh.workflowid);

        # check workflow cache, WC_UPDATE_SESSION_ONLY, acquire step status=True
        hash<auto> info;
        if (checkWorkflowCache(wh.workflowid, wfiid, wh.parent_info, WC_UPDATE_SESSION_ONLY, True, \info)) {
            if (!inlist(info.status, (OMQ::SQLStatError, OMQ::SQLStatAsyncWaiting, OMQ::SQLStatRetry)))
                throw "STATUS-ERROR",
                sprintf("01: can't update status '%s' (%s)", info.status, OMQ::SQLStatMap.(info.status)),
                ("err" : "STATUS-ERROR", "status" : OMQ::SQLStatMap.(info.status));

            if (info.status_sessionid && info.status_sessionid != Qorus.getSessionId()) {
                throw "SESSION-ERROR", sprintf("cannot retry workflow_instanceid %d because it is owned by foreign session ID %d", wfiid, info.status_sessionid);
            } else {
                throw "RETRY-ERROR", sprintf("failed to retrieve data for workflow_instanceid %d", wfiid);
            }
        }

        # release workflow order instance on exit
        on_exit releaseWorkflowInstance(wh.workflowid, wfiid, False);

        # setup temporary thread-local data
        tld.clear();

        int nseg = wdata{wfiid}.retryWorkflowInstance(cx, swd.WC);

        return {
            "steps_updated"   : 0,
            "segments_updated": nseg,
            "workflow_updated": True,
            "workflow_status" : OMQ::StatRetry,
            "cached"          : True,
        };
    }

    leaveFeedbackCached(softstring wfid, string wfiid, string key, auto value) {
        # when called from a qwf process, we need to create the TLD
        ensure_create_tld();
        QDBG_LOG("SegmentManagerBase::leaveFeedbackCached wfid %y wfiid %y key %y value %y", wfid, wfiid, key, value);
        # check workflow cache, WC_UPDATE_SESSION_ONLY, acquire step status: False
        hash info;
        if (checkWorkflowCache(wfid, wfiid, NOTHING, WC_UPDATE_SESSION_ONLY, False, \info)) {
            if (inlist(info.status, (OMQ::SQLStatCanceled, OMQ::SQLStatComplete)))
                throw "STATUS-ERROR",
                sprintf("can't update feedback for parent workflow order with status '%s' (%s)", info.status, OMQ::SQLStatMap.(info.status)),
                ("err" : "STATUS-ERROR", "status" : OMQ::SQLStatMap.(info.status));

            if (info.status_sessionid && info.status_sessionid != Qorus.getSessionId())
                throw "SESSION-ERROR", sprintf("cannot update feedback for parent workflow_instanceid %d because it is owned by foreign session ID %d", wfiid, info.status_sessionid);
            else
                throw "FEEDBACK-ERROR", sprintf("failed to retrieve data for workflow_instanceid %d", wfiid);
        }

        # bug 1326: set thread-local data for workflow order being updated
        WFEntry wfe = wdata{wfiid};
        ThreadLocalData tld_save();
        tld_save.tldCopy(tld);

        QDBG_LOG("SegmentManagerBase::leaveFeedbackCached tld_save before switch context WF name: %y", tld_save.wfe.wf.name);

        tld.clear();
        tld.wf = wfe.wf;
        tld.wfe = wfe;

        QDBG_LOG("SegmentManagerBase::leaveFeedbackCached return from checkWorkflowCache = False, after context switch: tld.wfe=%y tld_save.wfe=%y", tld.wfe.wf.name, tld_save.wfe.wf.name);

        on_exit {
            QDBG_LOG("SegmentManagerBase::leaveFeedbackCached restoring tld: %y -> %y", tld.wfe.wf.name, tld_save.wfe.wf.name);
            tld.tldCopy(tld_save);
        }

        # release workflow order instance on exit
        on_exit {
            releaseWorkflowInstance(wfid, wfiid, False);
        }

        # update feedback info in DB and in cache
        wdata{wfiid}.leaveFeedback(key, value);
    }

    # can only be called from internal workflow code while in an attach function
    setBlocked() {
        QDBG_ASSERT(ensure_tld());
        if (!tld.attachInProgress)
            throw "BLOCK-WORKFLOW-ERROR", "setBlocked() can only be called from an attach function";

        wdata.(tld.wfe.workflow_instanceid).blockOrCancel(OMQ::StatBlocked);
        tld.attachIsBlocked = True;
    }

    # only called from workflow code
    rescheduleOrder(date scheduled) {
        QDBG_ASSERT(ensure_tld());
        if (!tld.attachInProgress)
            throw "RESCHEDULE-ERROR", "reschedule_order() can only be called from an attach function";

        if (scheduled < now_us()) {
            tld.wfe.wf.logInfo("ignoring reschedule_order() call for %y", scheduled);
            return;
        }

        # save reschedule time
        softstring wfiid = tld.wfe.workflow_instanceid;
        string wfid = wdata{wfiid}.workflowid;
        wdata{wfiid}.reschedule(scheduled, SWD{wfid}.WC);

        # set thread-local flag for reschedule
        tld.attachReschedule = True;
    }

    # only called from workflow code
    reprioritizeOrder(int prio) {
        softstring wfiid = tld.wfe.workflow_instanceid;
        string wfid = wdata{wfiid}.workflowid;
        wdata{wfiid}.reprioritize(prio, SWD{wfid}.WC);
    }

    # called from a synchronization event step
    static bindEvent(string event) {
        QDBG_ASSERT(ensure_tld());
        SegmentManagerBase::checkBindEvent(event);

        bool posted = Qorus.SEM.bindEvent(tld.eventTypeID, event, tld.wfe.workflow_instanceid, tld.stepID, tld.ind);

        SegmentManagerBase::updateBoundEvent(event);

        if (!posted)
            return;

        tld.skipEvent = True;
    }

    # called from a synchronization event step
    static bindEventUnposted(string event) {
        SegmentManagerBase::checkBindEvent(event);

        Qorus.SEM.bindEventUnposted(tld.eventTypeID, event, tld.wfe.workflow_instanceid, tld.stepID, tld.ind);

        SegmentManagerBase::updateBoundEvent(event);
    }

    static leaveFeedbackSql(string wfid, string wfiid, string key, auto value) {
        string yaml = serialize_qorus_data(value);

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();
                omqp.beginTransaction();

                # lock with "select for update"
                hash wq = sqlif.smWorkflowInstanceLock(wfiid);

                # check session
                if (wq.status_sessionid && wq.status_sessionid != Qorus.getSessionId())
                    throw "SESSION-ERROR", sprintf("cannot retry workflow_instanceid %d because it is owned by foreign session ID %d", wfiid, wq.status_sessionid);

                string status = OMQ::SQLStatMap.(wq.workflowstatus);

                if (inlist(status, (OMQ::SQLStatCanceled, OMQ::SQLStatComplete)))
                    throw "STATUS-ERROR",
                        sprintf("can't update feedback for parent workflow order with status '%s' (%s)", status, OMQ::SQLStatMap{status}),
                        ("err" : "STATUS-ERROR", "status" : OMQ::SQLStatMap{status});

                sqlif.upsertFeedback(wfiid, key, yaml);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    static hash retryWorkflowInstanceSql(*hash cx, string wfiid, hash wh) {
        hash wq;
        int segcount;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();
                omqp.beginTransaction();

                # lock with "select for update"
                wq = sqlif.smWorkflowInstanceLock(wfiid);

                # check session
                if (wq.status_sessionid && wq.status_sessionid != Qorus.getSessionId()) {
                    throw "SESSION-ERROR", sprintf("cannot retry workflow_instanceid %d because it is owned by foreign session ID %d", wfiid, wq.status_sessionid);
                }

                string status = OMQ::SQLStatMap.(wq.workflowstatus);

                if (!inlist(status, (OMQ::StatError, OMQ::StatAsyncWaiting))) {
                    throw "STATUS-ERROR",
                        sprintf("02: can't update status '%s' (%s)", wq.workflowstatus, status),
                        {"err": "STATUS-ERROR", "status": status};
                }

                # update segment status
                segcount = sqlif.smRetryWorkflowInstanceUpdate(wfiid);
                # audit workflow status change
                Qorus.audit.workflowStatusChangeNoCommit(cx, wq.workflowid, wfiid, wq.workflowstatus, OMQ::SQLStatRetry);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # raise system event; old status must have been ERROR or ASYNC-WAITING
        QDBG_ASSERT(wq.workflowstatus != OMQ::SQLStatRetry);
        wq += Qorus.qmm.lookupWorkflow(wq.workflowid, False);
        Qorus.events.postWorkflowStatusChanged(cx, wq.name, wq.version, wq.workflowid, wfiid, {"old": SQLStatMap.(wq.workflowstatus), "new": OMQ::StatRetry});

        return {
            "steps_updated"    : 0,
            "segments_updated" : segcount,
            "workflow_updated" : True,
            "workflow_status"  : OMQ::StatRetry,
            "cached"           : False,
        };
    }

    static hash<auto> setErrorSql(hash<auto> cx, softstring wfid, string wfiid) {
        hash<auto> res;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                # start transaction management
                on_error omqp.rollback();
                on_success omqp.commit();
                omqp.beginTransaction();

                res = sqlif.smSetErrorIntern(wfiid, Qorus.getSessionId(), tld.cx.user);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # raise audit & system events if the status has changed
        if (res.workflowstatus != OMQ::SQLStatError) {
            Qorus.audit.workflowStatusChange(cx, wfid, wfiid, res.workflowstatus, OMQ::SQLStatError);
            hash<auto> workflow_hash += Qorus.qmm.lookupWorkflow(wfid, False);
            Qorus.events.postWorkflowStatusChanged(get_cx(cx), workflow_hash.name, workflow_hash.version, wfid, wfiid,
                {"old": SQLStatMap.(res.workflowstatus), "new": OMQ::StatError});
        }

        return {
            "steps_updated"    : int(res.stepcount),
            "segments_updated" : int(res.segcount),
            "workflow_status"  : OMQ::StatError,
            "old_status"       : OMQ::SQLStatMap.(res.workflowstatus),
            "priority"         : int(res.priority),
            "parent_info"      : {
                "parent_workflow_instanceid": exists res.parent_workflow_instanceid
                    ? int(res.parent_workflow_instanceid)
                    : NOTHING,
                "subworkflow": exists res.subworkflow ? int(res.subworkflow) : NOTHING,
            },
        };
    }

    registerSynchronousWorkflow(softstring wfid, softstring wfiid) {
        #QDBG_LOG("SegmentManagerBase::registerSynchronousWorkflow() wfid: %y wfiid: %y (%y) VAL: %y", wfid, wfiid,
        #    (map {$1.key: $1.value.type()}, SWD.pairIterator()), SWD{wfid}.WC);
        cast<WorkflowQueueBase>(SWD{wfid}.WC).registerSynchronousWorkflow(wfiid);
    }

    deregisterSynchronousWorkflow(softstring wfid, softstring wfiid) {
        cast<WorkflowQueueBase>(SWD{wfid}.WC).deregisterSynchronousWorkflow(wfiid);
    }

    terminateRetryConnection(softint index, softstring wfid, softstring segid, softstring sync) {
        cast<WorkflowQueueBase>(SWD{wfid}.WC).terminateSynchronousRetryConnection(index, segid, sync);
    }

    requeueAllRetries() {
        bool lck = !rwl.lockOwner();
        if (lck)
            rwl.readLock();
        on_exit if (lck)
            rwl.readUnlock();

        map SWD{$1}.WC.requeueAllRetries(), keys SWD;
    }

    # always called in the AbstractSegmentWorkflowData read lock
    *hash<auto> getLocalWorkflowInstanceInfo(softstring wfiid, bool compat = True) {
        *hash<auto> wd = wdata.getHash(wfiid);
        if (wd)
            return getWorkflowInstanceInfoIntern(wd, compat);

        return getWorkflowInstanceInfoSql(wfiid, compat);
    }

    *hash<auto> getWorkflowInstanceInfo(softstring wfiid, bool compat = True) {
        string wfid;
        try {
            wfid = getWorkflowID(wfiid);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-WORKFLOW-ORDER-DATA-INSTANCE")
                return;
        }

        return getWorkflowInstanceInfo(wfid, wfiid, compat);
    }

    private hash<auto> getParentInfo(softstring wfiid, *reference<int> priority) {
        *hash<auto> wd = wdata.getParentWorkflowPriority(wfiid);
        if (wd) {
            priority = wd.priority;
            return exists wd.parent_info ? wd.parent_info.("parent_workflow_instanceid", "subworkflow") : {};
        }

        hash<auto> q;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                q = sqlif.smGetParentInfo(wfiid);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        priority = int(q.priority);
        return q.("parent_workflow_instanceid", "subworkflow");
    }

    # NOTE: any changes here have to be reflected in system.info.getTreeWithWorkflowInstance()
    private hash<auto> getTreeWithWorkflowInstanceIntern(softint wfiid, hash<auto> wd, bool compat) {
        *softint pwfiid = wd.parent_info.parent_workflow_instanceid;
        if (pwfiid) {
            *softint tid;
            do {
                tid = getParentInfo(pwfiid).parent_workflow_instanceid;
                if (tid)
                    pwfiid = tid;
            } while (tid);
        } else
            pwfiid = wfiid;

        # add root entry to tree
        hash<auto> wiTree{pwfiid} = getWorkflowInstanceInfo(pwfiid, compat);

        # now build the rest of the tree
        softlist toFetch = pwfiid;
        while (toFetch) {
            # get children
            *hash<auto> rs;
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();

                    rs = sqlif.smGetTreeWithWorkflowInstanceIntern(toFetch);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex))
                        continue;
                    rethrow;
                }
                trans.reset();
                break;
            }

            # fill the values
            context (rs) {
                wiTree.%workflow_instanceid = %%;

                wiTree.%workflow_instanceid += {
                    "workflowstatus"     : OMQ::SQLStatMap.%workflowstatus,
                    "custom_status_desc" : Qorus.qmm.lookupWorkflow(%workflowid).custom_statuses{%custom_status},
                    "business_error"     : boolean(%business_error),
                } + (compat ? ("createdby": "omq", "modifiedby": "omq") : NOTHING);
            }
            # next party to fetch
            toFetch = rs.workflow_instanceid;
        }

        return sortHierarchy(wiTree);
    }

    *hash<auto> sortHierarchy(hash<auto> wiTree) {
        # hash keyed by parent -> children
        hash<auto> ch;
        # root order
        string rwfiid;
        foreach hash<auto> h in (wiTree.pairIterator()) {
            if (h.value.parent_workflow_instanceid) {
                ch{h.value.parent_workflow_instanceid}{h.key} = True;
            } else {
                QDBG_ASSERT(!exists rwfiid);
                rwfiid = h.key;
            }
        }

%ifdef QorusDebugInternals
        if (!exists rwfiid)
            QDBG_LOG("ERROR wiTree: %N", wiTree);
%endif
        QDBG_ASSERT(exists rwfiid);

        hash<auto> nh;
        code add = sub (string wfiid, int level) {
            nh{wfiid} = wiTree{wfiid} + ("hierarchy_level": level);
            map add($1, level + 1), keys ch{wfiid};
        };

        add(rwfiid, 0);

        return nh;
    }

    # only called from a workflow executiom instance
    setOrderInstanceNoteIntern(softint wfiid, hash<auto> info) {
        WFEntry wfe = wdata{wfiid};
        wfe.orderInstanceNotes.addCommit(wfiid, info);
        Qorus.events.postWorkflowInfoChanged(NOTHING, wfe.wf.name, wfe.wf.version, wfe.wf.workflowid, wfiid, info);
    }

    # does not need locking because it can only be called from workflow code
    setCustomStatus(softstring wfiid, softstring stepid, string stat) {
        wdata{wfiid}.setCustomStatus(stepid, stat);
    }

    # always called in the AbstractSegmentWorkflowData read lock
    *hash<auto> getLocalOrderInfoSummary(softstring wfiid) {
        # see if data is cached - get atomic copy of WFEntry object members, if it exists
        *hash wd = wdata.getHash(wfiid);
        if (!wd)
            return getOrderInfoSummarySql(wfiid);

        return {
            "name"                      : wd.wf.name,
            "version"                   : wd.wf.version,
            "author"                    : wd.wf.author,
            "workflow_instanceid"       : wfiid.toInt(),
            "external_order_instanceid" : wd.external_order_instanceid,
            "staticdata"                : wd.sdata,
            "dynamicdata"               : wd.ddata.get(),
            "created"                   : wd.cached,    # not real data
            "modified"                  : now(),        # not real data
            "createdby"                 : "omq",        # backwards-compatibility
            "modifiedby"                : "omq",        # backwards-compatibility
            "keys"                      : elements wd.orderKeys ? wd.orderKeys : NOTHING,
            # following key contains redundant info except status
            "workflows"                 : list({
                "name": wd.wf.name,
                "version": wd.wf.version,
                "workflow_instanceid": wfiid,
                "workflowstatus": wd.status,
            }),
        };
    }

    # returns a hierarchy of information about the given workflow order instance if cached, otherwise NOTHING
    *hash<auto> getLocalWFIAllInfo(softstring wfiid, bool compat, bool with_sensitive_data) {
        # see if data is cached - get atomic copy of WFEntry object members, if it exists
        *hash<auto> wd = wdata.getHash(wfiid);
        QDBG_LOG("SegmentManagerBase::getLocalWFIAllInfo() wfiid: %y wd: %y", wfiid, wd);
        # do not use an empty or not-yet-populated workflow cache entry
        if (!wd) {
            return;
        }

        # get subworkflow info if necessary
        if (wd.need_subworkflow) {
            softstring wfid = wd.wf.workflowid;
            *bool ok;

            {
                QDBG_ASSERT(SWD{wfid});
                SWD{wfid}.readLock();
                on_exit SWD{wfid}.readUnlock();

                *WFEntry wfe = getWFEntryUnlocked(SWD{wfid}, wfiid);

                if (wfe) {
                    wd.steps = wfe.getDBSubWorkflowInfo();
                    ok = True;
                }
            }

            if (!ok) {
                # if we could not refresh the cache entry, then retrieve directly from DB
                *hash<auto> q = SegmentManagerBase::getAllSubWorkflowInfo(wfiid);
                map wd.steps.($1.stepid)[$1.ind].subworkflow = $1.subworkflow_instanceid, q.contextIterator();
            }
        }

        list<hash<auto>> StepInstances = ();
        foreach string stepid in (keys wd.steps) {
            for (int i = 0; i < elements wd.steps{stepid}; ++i) {
                hash sh = {
                    # issue #2903: stepid must always be an integer
                    "stepid": stepid.toInt(),
                    "ind": compat ? string(i) : i,
                    "stepname": wd.wf.stepinfo{stepid}.name,
                    "stepversion": wd.wf.stepinfo{stepid}.version,
                    "steptype": wd.wf.stepinfo{stepid}.steptype,
                } + wd.steps{stepid}[i] + (wd.wf.stepinfo{stepid}.user_interaction ? {
                    "user_interaction": True,
                } : NOTHING) + wd.wf.stepinfo{stepid}{"queueid", "queuename"};

                # rename "status" -> "stepstatus"
                sh.stepstatus = remove sh.status;
                # rename "event" -> "eventkey"
                sh.eventkey = remove sh.event;

                # DEBUG
                delete sh.segment;

                # ensure "completed", "retries", and "skip" keys are present
                sh += {
                    "completed": sh.completed,
                    "retries": compat ? string(int(sh.retries)) : int(sh.retries),
                    "skip": compat ? string(int(sh.skip)) : boolean(sh.skip),
                    "business_error": boolean(wd.business_error{stepid}{i}),
                };
                if (sh.eventkey) {
                    sh.workflow_event_typeid = wd.wf.stepinfo{stepid}.workflow_event_typeid;
                }

                delete sh.dbstatus;
                sh.subworkflow_instanceid = exists sh.subworkflow ? string(sh.subworkflow) : NOTHING;
                delete sh.subworkflow;
                if (compat)
                    sh.flow_instanceid = wfiid;

                StepInstances += sh;
            }
        }

        # issue #2880: get step data
        *list<auto> stepdata = map (
            "name": wd.wf.stepinfo{$1.key}.name,
            "version": wd.wf.stepinfo{$1.key}.version,
            "stepid": $1.key.toInt(),
            "type": wd.wf.stepinfo{$1.key}.steptype,
            "data": $1.value,
        ), wd.step_data.get().pairIterator();

        hash OrderInfo = {
            "workflow_instanceid"       : wfiid.toInt(),   # redundant
            "external_order_instanceid" : wd.external_order_instanceid,
            "staticdata"                : wd.sdata,
            "dynamicdata"               : wd.ddata.get(),
            "stepdata"                  : stepdata,
            "created"                   : wd.cached,    # not real data
            "modified"                  : now(),        # not real data
            "keys"                      : wd.orderKeys,
        };

        if (with_sensitive_data) {
            OrderInfo.sensitive_data = wd.sensitive_data.getApiData();
        }

        OrderInfo.has_sensitive_data = !wd.sensitive_data.empty();

        if (compat) {
            OrderInfo += {
                "createdby": "omq",
                "modifiedby": "omq",
            };
        }

        *list ErrorInstances;
        #printf("BEFORE wfiid: %d, need_errors: %y errors: %y\n", wfiid, wd.need_errors, wd.errors);
        if (wd.need_errors) {
            softstring wfid = wd.wf.workflowid;
            *bool ok;

            {
                QDBG_ASSERT(SWD{wfid});
                # we have to grab the segment workflow data read lock when calling getLocalWFIAllInfEntryUnlocked()
                SWD{wfid}.readLock();
                on_exit SWD{wfid}.readUnlock();

                *WFEntry wfe = getWFEntryUnlocked(SWD{wfid}, wfiid);

                if (wfe) {
                    ErrorInstances = wfe.getDBErrors();
                    ok = True;
                }
            }

            if (!ok && elements wd.errors < ERROR_LIMIT) {
                ErrorInstances = SegmentManagerBase::getDBErrors(wfiid);
            }
        } else {
            ErrorInstances = wd.errors;
        }

        #printf("AFTER1 wfiid: %d, need_errors: %y ei: %y\n", wfiid, wd.need_errors, ErrorInstances);

        ErrorInstances = map $1 + {
            "workflow_instanceid": wfiid.toInt(),
         } + (compat ? {"createdby" : "omq"} : NOTHING), ErrorInstances;

        #printf("AFTER2 wfiid: %d, need_errors: %y errors: %y\n", wfiid, wd.need_errors, wd.errors);

        # set up order instance info
        return {
            #"wd": (map {$1.key: ($1.value.typeCode() == NT_OBJECT ? sprintf("%y", $1.value) : $1.value)}, wd.pairIterator()),
            "InstanceInfo"   : SegmentManagerBase::getWorkflowInstanceInfoIntern(wd, compat)
                + {"note_count": wd.orderInstanceNotes.size()},
            "OrderInfo"      : OrderInfo,
            "StepInstances"  : StepInstances,
            "ErrorInstances" : ErrorInstances,
            "HierarchyInfo"  : getTreeWithWorkflowInstanceIntern(wfiid, wd, compat),
            "AuditEvents"    : SegmentManagerBase::getWorkflowAuditEventsSQL(wfiid),
            "LastModified"   : now_us(),
        };
    }

    *hash getLocalWorkflowInstanceStatus(string wfiid) {
        # see if data is cached - get atomic slice of WFEntry object, if it exists
        *hash<auto> wd = wdata.getHash(wfiid);
        QDBG_LOG("SegmentManagerBase::getLocalWorkflowInstanceStatus() wfiid: %y local: %y (%y)", wfiid, exists wd,
            wd.status);
        # issue: 3137: do not use an empty or not-yet-populated workflow cache entry
        if (!wd) {
            return getWorkflowInstanceStatusSQL(wfiid);
        }

        hash wq = {
            "name"                       : wd.wf.name,
            "version"                    : wd.wf.version,
            "author"                     : wd.wd.author,
            "workflow_instanceid"        : wfiid.toInt(),
            "workflowstatus"             : wd.status,
            "workflowid"                 : wd.wf.workflowid,
            "status_sessionid"           : Qorus.getSessionId(),
            "parent_workflow_instanceid" : wd.parent_info.parent_workflow_instanceid,
            "subworkflow"                : boolean(wd.parent_info.subworkflow),
            "started"                    : wd.started,
            "completed"                  : NOTHING,
            "custom_status"              : wd.custom_status,
            "custom_status_desc"         : wd.wf.custom_statuses{wd.custom_status},
            "scheduled"                  : wd.reschedule,
            "priority"                   : wd.priority,
            "operator_lock"              : wd.operator_lock,
            "note_count"                 : wd.orderInstanceNotes.size(),
            "segment_instance"           : (),
        };

        for (int i = 0; i < elements wd.seg; ++i) {
            # bug 486: qorus cannot recover an order with a gap in the segment list
            if (!wd.seg[i].val())
                continue;
            wq.segment_instance += {
                "segmentid"     : i,
                "segmentstatus" : wd.seg[i].status,
                "created"       : wd.cached,   # not real data
                "modified"      : wd.cached,   # not real data
                "steps"         : wd.wf.segment[i].steplist
            };
        }

        foreach string stepid in (keys wd.steps) {
            # issue #2759: sometimes the step has no status yet in ssh if it hasn't been executed - ignore
            if (!wd.ssh{stepid}) {
                continue;
            }
%ifdef QorusDebugInternals
            *string status = foldl OMQ::SpecialStatusOrder.$1 > OMQ::SpecialStatusOrder.$2 ? $1 : $2, (select keys wd.ssh{stepid}, wd.ssh{stepid}.$1);
            if (!status) {
                # cannot call QDBG_ASSERT() here, as any info logged will not be visible in gitlab CI
                throw "INTERNAL-ERROR", sprintf("workflow_instanceid %d stepid %y has no status; wd.ssh{%y}: %y",
                    wfiid, stepid, stepid, wd.ssh{stepid});
            }
%else
            string status = foldl OMQ::SpecialStatusOrder.$1 > OMQ::SpecialStatusOrder.$2 ? $1 : $2, (select keys wd.ssh{stepid}, wd.ssh{stepid}.$1);
%endif
            # step metadata hash
            *hash<auto> smh = wd.wf.stepinfo{stepid};
            # issue #3360: when workflows are redefined with existing data, this can happen
            if (!smh) {
                Qorus.logError("workflow_instanceid %d stepid %d is not configured in the current workflow and "
                    "cannot be reported; known stepids: %y", wfiid, stepid, (map $1.toInt(), keys wd.wf.stepinfo));
                continue;
            }
            # step execution info hash
            hash sih = wd.steps{stepid}[0];
            hash sh = {
                "name"               : smh.name,
                "version"            : smh.version,
                "author"             : smh.author,
                "steptype"           : smh.steptype,
                "arraytype"          : smh.arraytype,
                "stepid"             : stepid,     # redundant
                "stepstatus"         : status,
                "started"            : sih.started,
                "completed"          : sih.completed,
                "custom_status"      : sih.custom_status,
                "custom_status_desc" : wd.wf.custom_statuses{sih.custom_status}
            };

            if (smh.steptype == OMQ::ExecEvent) {
                #printf("2:si:(%d): %y\n", stepid, wd.wf.stepinfo{stepid});
                softstring typeid = wd.wf.stepinfo{stepid}.workflow_event_typeid;
                sh.event = Qorus.qmm.lookupEvent(typeid) + ("typeid": typeid);
            }
            if (smh.arraytype == OMQ::ArrayNone) {
                if (smh.steptype == OMQ::ExecSubWorkflow)
                    sh += SegmentManagerBase::getSubWorkflowStatus(wfiid, stepid, 0);
                else if (smh.steptype == OMQ::ExecEvent)
                    sh.event.key = sih.event;
            } else {
                sh.substeps = ();
                # loop through step ind execution info hashes
                foreach hash siih in (wd.steps{stepid}) {
                    hash ss = {
                        "stepid"             : stepid,  # redundant
                        "ind"                : $#,
                        "stepstatus"         : siih.status,
                        "started"            : siih.started,
                        "completed"          : siih.completed,
                        "eventkey"           : siih.event,
                        "custom_status"      : siih.custom_status,
                        "custom_status_desc" : wd.wf.custom_statuses{siih.custom_status}
                    };

                    if (smh.steptype == OMQ::ExecSubWorkflow)
                        ss += SegmentManagerBase::getSubWorkflowStatus(wfiid, stepid, $#);

                    sh.substeps += ss;
                }
            }
            wq.step_instance{stepid} = sh;
        }

        if (wd.need_errors) {
            softstring wfid = wd.wf.workflowid;
            *bool ok;

            {
                QDBG_ASSERT(SWD{wfid});
                # we have to grab the segment workflow data read lock when calling getWFEntryUnlocked()
                SWD{wfid}.readLock();
                on_exit SWD{wfid}.readUnlock();

                *WFEntry wfe = getWFEntryUnlocked(SWD{wfid}, wfiid);

                if (wfe) {
                    wq.errors = wfe.getDBErrors();
                    ok = True;
                }
            }
            if (!ok && elements wd.errors < ERROR_LIMIT)
                wq.errors = SegmentManagerBase::getDBErrors(wfiid);
        }

        # get error information - add redundant information to error map
        wq.errors = map $1 + ("workflow_instanceid": wfiid.toInt()) - "error_instanceid", wd.errors;

        # add workflow order instance audit events
        wq.audit = SegmentManagerBase::getWorkflowAuditEventsSQL(wfiid);

        # add notes
        wq.notes = wd.orderInstanceNotes.get();

        return wq;
    }

    # always called in the AbstractSegmentWorkflowData write lock
    private resetBlockOrCancel(softstring wfiid, hash statHash, string stat) {
        #log(LoggerLevel::FATAL, "resetBlocked for %s", wfiid);
        string wfid = getWorkflowID(wfiid);
        int priority;
        hash parent_info = getParentInfo(wfiid, \priority);

        AbstractSegmentWorkflowData swd = SWD{wfid};
        swd.requeueEvents(statHash.workflowstatus_orig, wfiid, priority, parent_info, statHash.scheduled);
    }

    # always called in the AbstractSegmentWorkflowData write lock
    hash handleWorkflowInstanceStatusCached(hash cx, softstring wfid, softstring wfiid, string stat, bool setOn, *hash tempdata, *hash new_keys, string err, hash wih) {
        QDBG_LOG("SegmentManagerBase::handleWorkflowInstanceStatusCached() wfiid: %s set: %y err: %y tempdata: %y newkeys: %y wih: %y", wfiid, setOn, err, keys tempdata, keys new_keys, wih);

        if (new_keys) {
            *hash<auto> wfh = Qorus.qmm.lookupWorkflow(wfid);
            if (!wfh) {
                throw "INVALID-WORKFLOW", sprintf("workflowid %d has been deleted while processing an order keys change request", wfid);
            }

            WFEntry::setOrderKeysStatic(wfid, wfiid, wfh.order_key_map, sqlif.getOrderKeysTrans(wfiid), new_keys,
                False, (stat == OMQ::StatCanceled ? "cancel" : "block") + " order call");
        }

        #log(LoggerLevel::DEBUG, "handleWorkflowInstanceStatus raw db write at pos 01 for %s", wfiid);
        # here run while workflow write lock is held
        hash q = SegmentManagerBase::commitBlockOrCancelSql(cx, wfid, wfiid, stat, setOn, True);
        QDBG_LOG("SegmentManagerBase::handleWorkflowInstanceStatusCached() q: %y", q);
        if (!setOn) {
            # if we have tempdata to insert, then we cache the workflow order now
            if (tempdata) {
                *bool td;
                #log(LoggerLevel::DEBUG, "handleWorkflowInstanceStatus wfiid: %d wfid: %d q: %y (tempdata: %y newkeys: %y)", wfiid, wfid, q, boolean(tempdata), boolean(new_keys));
                if (q.workflowstatus_orig != OMQ::StatError) {
                    *hash parent_info;
                    if (q.parent_workflow_instanceid)
                        parent_info = q.("parent_workflow_instanceid", "subworkflow");

                    # retrieve the workflow order data to put in the cache
                    if (!cacheWorkflowUnlocked(wfid, wfiid, parent_info, WC_UPDATE_SESSION_ONLY, True)) {
                        WFEntry wfe = wdata{wfiid};
                        # refs must be 0 in cache
                        --wfe.refs;
                        wfe.setTempData(tempdata);
                        # returns False if the order cannot be cached
                        td = saveOrderInCacheIntern(wfe);
                        QDBG_LOG("SegmentManagerBase::handleWorkflowInstanceStatusCached() updated tempdata for wfiid %d td: %y", wfiid, td);
                    }
                    else {
                        QDBG_LOG("SegmentManagerBase::handleWorkflowInstanceStatusCached() failed to cache wfiid %d", wfiid);
                    }
                }
                q.tempdata = td ? True : False;
            }
            resetBlockOrCancel(wfiid, q, stat);
        } else {
            # issue #1861: remove events from queues for BLOCKED / CANCELED orders
            cast<WorkflowQueueBase>(SWD{wfid}.WC).removeWorkflowOrder(wfiid, wih.priority);
        }

        return handleWorkflowInstanceStatusPrologue(wfid, wfiid, stat, setOn, q);
    }

    hash<auto> handleWorkflowInstanceStatusPrologue(string wfid, string wfiid, string stat, bool setOn, hash q) {
        string retStatus = setOn ? stat : OMQ::SQLStatMap{q.workflowstatus_orig};
        # log status change
        string msg = sprintf("API: set workflow order instance %d to '%s'", wfiid, retStatus);
        try {
            SWD{wfid}.wf.logInfo(msg);
        } catch (hash<ExceptionInfo> ex) {
            # log to system logger
            Qorus.logInfo("WF: " + msg);
        }

        # only run detach function if setting (as opposed to removing) a blocked or canceled status
        if (setOn) {
            hash<auto> wfi = Qorus.qmm.lookupWorkflow(wfid, False);

            if (wfi.has_detach) {
                ThreadLocalData td();
                td.tldCopy(tld);
                on_exit tld.tldCopy(td);
                tld.clear();

                string id = Qorus.control.getTemporaryWorkflowInstance(wfid, wfiid);

%ifdef QorusCore
                # get SegmentWorkflowData for any workflow to run the detach function
                # only in qorus-core, in qwf it's always available

                # register the order instance with the segment manager, do not request workflow event data
                registerWorkflow(Qorus.control.execHash{id}.wf, False, True);

                # deregister the workflow on exit
                on_exit
                    derefWorkflow(wfid, False, True);
%else
                QDBG_ASSERT(SM.SWD{wfid});
%endif

                # now workflow is cached in segment manager, we can cache the workflow order instance data
                # check workflow cache, WC_FOR_CANCEL=do not update status or session, False=do not acquire step status
                checkWorkflowCache(wfid, wfiid, q.("parent_workflow_instanceid", "subworkflow"), WC_FOR_CANCEL, False);

                # BUG 288: save correct WFEntry object in thread-local data before calling detach
                tld.wfe = wdata{wfiid};

                # delete release the workflow instance
                on_exit {
                    # this will also delete the cached WFEntry object
                    releaseWorkflowInstance(wfid, wfiid);
                    #log(LoggerLevel::FATAL, "DEBUG: handleWorkflowInstanceStatus() wdata.%y: %y", wfiid, wdata{wfiid});
                }

                # call the handler
                callDetachIntern(Qorus.control.execHash{id}, stat, wdata{wfiid}.external_order_instanceid);
            } # if has detach
        }

        return {"workflow_status": retStatus};
    }

    setWFEntryDebug(softstring wfiid, bool flag) {
        throw "ERROR", "not implemented in this release";
        #if (!flag) delete WFED{wfiid};
        #else WFED{wfiid} = True;
    }

%ifdef QorusCore
    abstract registerWorkflow(Workflow wf, bool qref, bool temp);
    abstract derefWorkflow(softstring id, bool qref, bool temp, *bool from_qwf);
%endif

    # cannot be private, also called from the WFEntry class
    abstract callDetachIntern(WorkflowExecutionInstance wi, string status, *softstring eoiid);

    abstract purgeOrdersIntern(string wfid, list fl);

    abstract cacheThread();

    abstract list getOrderInstanceNotes(softint wfiid, *int count);

    # always called in the write lock
    abstract private OMQ::AbstractSegmentWorkflowData getSegmentWorkflowData(Workflow wf, bool qref, bool temp);

    abstract private updateSubWorkflowQueueIntern(softint swfiid, *softstring wfid, softstring wfiid, *softint stepid, *softint ind, string stat);

    abstract *hash getWorkflowInstanceInfo(string wfid, string wfiid, bool compat);

    static *hash getWorkflowInstanceInfoSql(string wfiid, bool compat) {
        # FIXME: missing custom statuses, parent_info
        *hash q;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                q = sqlif.smGetWorkflowInstanceInfoSQLIntern(wfiid);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        if (!q) {
            return;
        }

        q.wf = q.("name", "version", "author", "workflowid", );
        q.workflowstatus = OMQ::SQLStatMap.(q.workflowstatus);
        q.subworkflow = boolean(q.subworkflow);
        q.wf.depr = boolean(q.deprecated);
        return q + (compat ? ("createdby" : "omq", "modifiedby" : "omq") : NOTHING);
    }

    static *hash getWorkflowInstanceStatusSQL(softint wfiid) {
        *hash res;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                res = sqlif.smGetWorkflowInstanceStatusSQL(wfiid);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        QDBG_LOG("SegmentManagerBase::getWorkflowInstanceStatusSQL() wfiid: %y status: %y", wfiid, res.wq.workflowstatus);
        if (!exists res) {
            return;
        }

        #log(LoggerLevel::DEBUG, "getWorkflowInstanceStatusSQL(%y) res: %N", wfiid, res);
        hash wq = res.wq;

        wq.workflowstatus = OMQ::SQLStatMap.(wq.workflowstatus);

        hash<auto> wfi = Qorus.qmm.lookupWorkflow(wq.workflowid, False);

        wq.custom_status_desc = wfi.custom_statuses{wq.custom_status};

        wq.business_error = boolean(wq.business_error);
        wq.priority = int(wq.priority);

        wq.segment_instance = ();

        *hash seg = res.seg;

        context (seg) {
            hash sh = %%;

            sh.segmentstatus = OMQ::SQLStatMap.%segmentstatus;
            sh.custom_status_desc = wfi.custom_statuses{%custom_status};

            # get step status per segment as well
            sh.steps = ();
            *hash ssq;
            while (True) {
                try {
                    on_error omqp.rollback();

                    ssq = sqlif.smGetWorkflowInstanceStatusSQLContextSeg(wq.workflowid, %segmentid);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex))
                        continue;
                    rethrow;
                }
                trans.reset();
                break;
            }
            context (ssq) {
                sh.steps += %stepid;
            }
            wq.segment_instance += sh;
        }

        # get step information
        *hash sq;
        while (True) {
            try {
                on_error omqp.rollback();

                sq = sqlif.smGetWorkflowInstanceStatusSQLContextStep(wfiid);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        #QDBG_LOG("SegmentManagerBase::getWorkflowInstanceStatusSQL(%y) sq: %N", wfiid, sq);

        hash ai;
        context (sq) {
            softint retries = %retries < 0 ? 0 : %retries;
            bool business_error = %retries < 0 ? True : False;

            if (%arraytype != "NONE") {
                ai.%stepid = %arraytype;

                if (!exists wq.step_instance.%stepid) {
                    wq.step_instance.%stepid = %%;

                    # delete keys meant for the substeps
                    # FIXME: delete stepid: redundant
                    wq.step_instance.%stepid -= ("stepstatus", "started", "completed", "ind", "eventkey");
                }
                wq.step_instance.%stepid.substeps[%ind] = %% + {
                    "retries": string(retries),
                    "business_error": business_error,
                };

                # delete keys valid for all steps
                wq.step_instance.%stepid.substeps[%ind] -= ("name", "version", "steptype", "arraytype", "workflow_event_typeid");

                # map status char to verbose status
                string stat = OMQ::SQLStatMap.(%stepstatus);
                wq.step_instance.%stepid.substeps[%ind].stepstatus = stat;

                if (%steptype == OMQ::ExecSubWorkflow)
                    wq.step_instance.%stepid.substeps[%ind] += SegmentManagerBase::getSubWorkflowStatus(wfiid, %stepid, %ind);

                if (!exists wq.step_instance.%stepid.stepstatus || OMQ::SpecialStatusOrder{stat} > OMQ::SpecialStatusOrder.(wq.step_instance.%stepid.stepstatus))
                    wq.step_instance.%stepid.stepstatus = stat;

                if (%completed != NULL && %completed > wq.step_instance.%stepid.completed)
                    wq.step_instance.%stepid.completed = %completed;
            } else {
                wq.step_instance.%stepid = %% + {
                    "retries": string(retries),
                    "business_error": business_error,
                };

                # FIXME: delete stepid: redundant
                # map status char to verbose status
                wq.step_instance.%stepid.stepstatus = OMQ::SQLStatMap.(%stepstatus);

                if (%steptype == OMQ::ExecEvent)
                    wq.step_instance.%stepid.event.key = remove wq.step_instance.%stepid.eventkey;

                if (%steptype == OMQ::ExecSubWorkflow)
                    wq.step_instance.%stepid += SegmentManagerBase::getSubWorkflowStatus(wfiid, %stepid, %ind);
            }

            if (%steptype == OMQ::ExecEvent && !exists wq.step_instance.%stepid.event.name) {
                #printf("1:wq:(%d): %y\n", %stepid, %workflow_event_typeid);
                wq.step_instance.%stepid.event += Qorus.qmm.lookupEvent(%workflow_event_typeid) + ("typeid": %workflow_event_typeid);
                delete wq.step_instance.%stepid.workflow_event_typeid;
            }

            wq.step_instance.%stepid.custom_status_desc = wfi.custom_statuses{%custom_status};
        }

        # now calculate summary information for array steps
        foreach string id in (keys ai) {
            wq.step_instance{id}.started = wq.step_instance{id}.substeps[0].started;
            if (wq.step_instance{id}.stepstatus != OMQ::StatComplete)
                delete wq.step_instance{id}.completed;
        }

        # get error information
        # FIXME: workflow_instanceid is redundant
        wq.errors = map $1 + {"workflow_instanceid": wfiid}, SegmentManagerBase::getDBErrors(wfiid);

        # add workflow order instance audit events
        wq.audit = SegmentManagerBase::getWorkflowAuditEventsSQL(wfiid);

        # add notes
        wq.notes = OMQ::OrderInstanceNotes::getNotes(wfiid);

        return wq;
    }

    static *hash getOrderInfoFromQueryResults(*hash q, bool compat) {
        if (!exists q)
            return;

        if (compat)
            q += ("createdby":"omq","modifiedby":"omq");

        # parse dynamic data
        if (strlen(q.dynamicdata))
            q.dynamicdata = deserialize_qorus_data(q.dynamicdata);

        # parse static data
        if (strlen(q.staticdata))
            q.staticdata = deserialize_qorus_data(q.staticdata);

        *hash wq;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                # setup user keys
                q."keys" = sqlif.getOrderKeys(q.workflow_instanceid);

                # get workflow and workflow status info
                wq = sqlif.smGetOrderInfoFromQueryResults(q.workflow_instanceid);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        q.workflows = ();
        context (wq) {
            hash h = %%;
            h.workflowstatus = OMQ::SQLStatMap.(h.workflowstatus);
            q.workflows += h;
        }

        return q;
    }

    static *hash getOrderInfoSummarySql(softint wfiid) {
        # workflow_instanceid is unique in order instances
        list l = SegmentManagerBase::getOrderInfoSql("workflow_instanceid", wfiid);
        if (elements l > 1)
            throw "GET-ORDER-INFO-SUMMARY-ERROR", sprintf("Unexpected value returned from DB; elements expected: 1, got: %d", elements l);
        return l[0];
    }

    static list getOrderInfoSql(string key, auto value) {
        *list l;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                l = sqlif.smGetOrderInfoSQL(key, value);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        return map SegmentManagerBase::getOrderInfoFromQueryResults($1, True), l;
    }

    static hash<auto> commitBlockOrCancelSql(hash<auto> cx, string wfid, string wfiid, string stat, bool setOn,
            bool assignSession = True) {
        hash ih;
        hash h;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                h = sqlif.smCommitBlockOrCancel(wfiid, Qorus.getSessionId(), stat, setOn, assignSession,
                    tld.attachInProgress);

                string os = h.workflowstatus;
                string ns = setOn ? OMQ::StatMap{stat} : h.workflowstatus_orig;
                ih = ("old": SQLStatMap{os}, "new": SQLStatMap{ns});
                Qorus.audit.workflowStatusChangeNoCommit(cx, wfid, wfiid, os, ns);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                qlog(LoggerLevel::INFO, "%s%s failed; rolled back transaction", setOn ? "" : "un",
                    stat == OMQ::StatCanceled ? "cancel" : "block");
                # ensure exception is logged
                qlog(LoggerLevel::INFO, "ERROR: %s", get_exception_string(ex));
                rethrow;
            }
            trans.reset();
            break;
        }

        if (h.parent_workflow_instanceid)
            h.subworkflow = boolean(h.subworkflow);

        # raise system event
        hash<auto> wh = Qorus.qmm.lookupWorkflow(wfid, False);

        if (setOn && stat == OMQ::StatCanceled) {
            ih += {
                "start": h.started,
                "end": now_us(),
            };
        }

        QDBG_ASSERT(ih.old != ih."new");
        Qorus.events.postWorkflowStatusChanged(get_cx(cx), wh.name, wh.version, wfid, wfiid, ih);

        return h;
    }

    static hash requeueEventsSql(softint wfiid, softint priority, hash parent_info, WorkflowQueueBase wq) {
        hash rv = {};

        hash q;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                q = sqlif.smQueueEventsIntern(wfiid);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        #log(LoggerLevel::FATAL, sprintf("q: %y", q));
        # queue detached segments
        context (q.segmentids) {
            wq.queueDetachedSegment(%segmentid, wfiid, priority, parent_info);
        }
        if (q.segmentids.segmentid) {
            rv += ("queued_detached_segments" : elements q.segmentids.segmentid);
        }

        # queue subworkflow events
        context (q.subworkflows) {
            string stat = %corrected ? SQLStatComplete : OMQ::SQLStatMap.%status;
            wq.updateSubWorkflowQueue(wfiid, %stepid, %ind, priority, %subworkflow_instanceid, parent_info, stat);
        }
        if (q.subworkflows.stepid) {
            rv += ("queued_subworkflows" : elements q.subworkflows.stepid);
        }

        # queue received async messages
        context (q.asyncs) {
            # data will be retrieved and parsed when the queue entry is passed to the backend segment
            wq.updateQueue(%stepid, wfiid, %ind, priority, boolean(%corrected), %queuekey, NOTHING, parent_info);
        }
        if (q.asyncs.queuekey) {
            rv += ("queued_async_messages" : elements q.asyncs.queuekey);
        }

        # queue posted workflow synchronization events
        context (q.syncs) {
            # data will be retrieved and parsed when the queue entry is passed to the backend segment
            wq.postSyncEvent(%stepid, wfiid, %ind, priority, parent_info);
        }
        if (q.syncs.stepid) {
            rv += ("queued_sync_events" : elements q.syncs.stepid);
        }

        # queue retries
        int rc = 0;
        int ac = 0;
        int fc = 0;
        context (q.retries) {
            if (%retry_trigger != NULL) {
                wq.queueRetrySegmentFixed(%segmentid, wfiid, parent_info, %retry_trigger);
                ++fc;
            }
            else if (%segmentstatus == OMQ::SQLStatAsyncWaiting) {
                wq.queueAsyncRetrySegment(%segmentid, wfiid, parent_info, %modified);
                ++ac;
            }
            else {
                wq.queueRetrySegment(%segmentid, wfiid, parent_info, %modified);
                ++rc;
            }
        }
        if (ac) {
            rv.queued_async_retries = ac;
        }
        if (rc) {
            rv.queued_retries = rc;
        }
        if (fc) {
            rv.queued_fixed_retries = rc;
        }

        return rv;
    }

    static rescheduleOrderSql(softint wfiid, *date scheduled, *WorkflowQueueBase wq) {
        bool block_or_cancel;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # first try and update the DB; if this fails an exception is thrown
                # issue #1851: make sure that rescheduled BLOCKED or CANCELED orders are not rescheduled in the workflow queue as it can lead to a race condition
                block_or_cancel = sqlif.rescheduleWorkflow(wfiid, scheduled, Qorus.getSessionId(), tld.cx.user);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        if (wq && !block_or_cancel) {
            wq.rescheduleWorkflow(wfiid, scheduled);
        }
    }

    static reprioritizeOrderSql(softint wfiid, int prio, *WorkflowQueueBase wq) {
        bool do_reprioritize;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # try and update the DB; if this fails an exception is thrown
                do_reprioritize = sqlif.reprioritizeWorkflow(wfiid, prio, Qorus.getSessionId(), tld.cx.user);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        if (do_reprioritize && wq) {
            wq.reprioritizeWorkflow(wfiid, prio);
        }
    }

    # workflow instance cannot be in progress with another omq instance
    static *hash<auto> replaceExternalData(string f, softint wfiid, *hash<auto> data) {
        *hash<auto> od;
        string str = serialize_qorus_data(data);
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();
                omqp.beginTransaction();

                *hash<auto> q = sqlif.smReplaceExternalData(f, wfiid);
                if (q.status_sessionid && q.status_sessionid != Qorus.getSessionId())
                    throw "REPLACE-DATA-ERROR", sprintf("cannot replace %s for workflow instance %d because it's "
                        "owned by foreign session %d", f, wfiid, q.status_sessionid);

                # try to log previous value, ignore parsing errors
                try {
                    od = deserialize_qorus_data(q{f});
                    qlog(LoggerLevel::INFO, "wfiid %d: replacing %s: OLD: %y", wfiid, f, od);
                } catch (hash<ExceptionInfo> ex) {
                    qlog(LoggerLevel::INFO, "%s parsing old %s, clob data: %s", ex.err, f, q{f});
                }
                qlog(LoggerLevel::INFO, "wfiid %d: replacing %s: NEW: %y", wfiid, f, data);

                sqlif.smReplaceExternalDataUpdate(f, str, wfiid);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        return od;
    }

    # workflow instance cannot be in progress with another omq instance
    static *hash<auto> updateExternalData(string f, softint wfiid, *hash<auto> new_data, *reference<bool> updated) {
        QDBG_ASSERT(!updated);
        *hash<auto> od;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();
                omqp.beginTransaction();

                *hash<auto> q = sqlif.smReplaceExternalData(f, wfiid);
                if (q.status_sessionid && q.status_sessionid != Qorus.getSessionId())
                    throw "UPDATE-DATA-ERROR", sprintf("cannot replace %s for workflow instance %d because it's "
                        "owned by foreign session %d", f, wfiid, q.status_sessionid);

                # get current value
                od = deserialize_qorus_data(q{f});
                *hash<auto> new_order_data = od + new_data;
                if (od != new_order_data) {
                    qlog(LoggerLevel::INFO, "wfiid %d: replacing %s: OLD: %y", wfiid, f, od);
                    qlog(LoggerLevel::INFO, "wfiid %d: replacing %s: NEW: %y", wfiid, f, new_order_data);
                    string str = serialize_qorus_data(new_order_data);
                    sqlif.smReplaceExternalDataUpdate(f, str, wfiid);
                    updated = True;
                } else {
                    qlog(LoggerLevel::INFO, "wfiid %d: no changes in %s; ignoring update", wfiid, f);
                }

                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        return od;
    }

    # workflow instance cannot be in progress with another omq instance
    static *hash<auto> updateExternalDataPath(string f, softint wfiid, string path, auto value,
            *reference<bool> updated) {
        QDBG_ASSERT(!updated);
        *hash<auto> od;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();
                omqp.beginTransaction();

                *hash<auto> q = sqlif.smReplaceExternalData(f, wfiid);
                if (q.status_sessionid && q.status_sessionid != Qorus.getSessionId())
                    throw "UPDATE-DATA-ERROR", sprintf("cannot replace %s for workflow instance %d because it's "
                        "owned by foreign session %d", f, wfiid, q.status_sessionid);

                # get current value
                od = deserialize_qorus_data(q{f});

                *hash<auto> new_data = UserApi::updateHashDotValue(od, path, value);
                if (od != new_data) {
                    qlog(LoggerLevel::INFO, "wfiid %d: replacing %s: OLD: %y", wfiid, f, od);
                    qlog(LoggerLevel::INFO, "wfiid %d: replacing %s: NEW: %y", wfiid, f, new_data);
                    string str = serialize_qorus_data(new_data);
                    sqlif.smReplaceExternalDataUpdate(f, str, wfiid);
                    updated = True;
                } else {
                    qlog(LoggerLevel::INFO, "wfiid %d: no changes in %s; ignoring update", wfiid, f);
                }

                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        return od;
    }

    releaseUserInteractionStepLock(hash<auto> cx, softint wfid, softint wfiid, softint stepid, softint ind,
        string user) {
        hash<auto> wh = {
            "workflow_instanceid": wfiid,
            "stepid": stepid,
            "ind": ind,
        };
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                AbstractTable queue_data = Qorus.dsmanager.getOmqTable("queue_data");
                *hash<auto> rh = queue_data.selectRow({
                    "columns": "user_interaction_user",
                    "where": wh,
                });
                if (!rh) {
                    throw "NO-DATA", sprintf("no queue_data row corresponding to %y can be found", wh);
                }

                # if the row is not locked, then return normally
                if (!rh.user_interaction_user.val()) {
                    return;
                }

                # if the user does not match, then throw an exception
                if (rh.user_interaction_user != user) {
                    throw "USER-ERROR", sprintf("step %y is locked by user %y and cannot be released by user %y", wh,
                        rh.user_interaction_user, user);
                }

                queue_data.update({
                    "user_interaction_user": NOTHING,
                    "user_interaction_locked": 0,
                }, wh);
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    # returns True if the lock was broken, False if not
    static bool breakStepLockSql(softint wfiid, softint stepid, softint ind, string note) {
        bool rv;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                if (rv = sqlif.clearQueueDataLock(wfiid, stepid, ind)) {
                    OrderInstanceNotes::addSaveNoCommit(wfiid, note);
                }
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }
        return rv;
    }

    # workflow instance cannot be in progress with another omq instance
    static *hash<auto> replaceExternalStepData(softint wfiid, softint stepid, int ind, *hash<auto> newdata,
        string user) {
        *hash<auto> od;
        *string str = newdata ? serialize_qorus_data(newdata) : NOTHING;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();
                omqp.beginTransaction();

                *hash<auto> q = sqlif.smReplaceExternalStepData(wfiid, stepid, ind);
                if (q.status_sessionid && q.status_sessionid != Qorus.getSessionId()) {
                    throw "REPLACE-STEP-DATA-ERROR", sprintf("cannot replace step data for workflow instance %d "
                        "stepid %d[%d] because it's owned by foreign session %d", wfiid, stepid, ind,
                        q.status_sessionid);
                }

                # check user match if present for step data locks
                if (user != "%SYS%" && q.user_interaction_user.val() && user != q.user_interaction_user) {
                    throw "REPLACE-STEP-DATA-ERROR", sprintf("user %y cannot replace step data for workflow instance "
                        "%d stepid %d[%d] because user %y already owns the lock", user, wfiid, stepid, ind,
                        q.user_interaction_user);
                }

                # try to log previous value, ignore parsing errors
                if (q.data) {
                    try {
                        od = deserialize_qorus_data(q.data);
                        qlog(LoggerLevel::INFO, "replacing step data for wfiid %d stepid %d[%d]: OLD: %y", wfiid, stepid, ind,
                            od);
                    } catch (hash<ExceptionInfo> ex) {
                        qlog(LoggerLevel::INFO, "%s parsing old step data for wfiid %d stepid %d[%d], clob data: %s", ex.err,
                            wfiid, stepid, ind, q.data);
                    }
                    qlog(LoggerLevel::INFO, "replacing step data: NEW: %y", newdata);
                } else {
                    qlog(LoggerLevel::INFO, "inserting step data for wfiid %d stepid %d[%d]: NEW: %y", wfiid, stepid, ind,
                        newdata);
                }

                sqlif.smReplaceExternalStepDataUpdate(str, wfiid, stepid, ind);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }
        return od;
    }

    static replaceExternalSensitiveData(softstring wfiid, string skey, string svalue, hash data, *softlist aliases, *hash meta) {
        *hash wdh;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();
                omqp.beginTransaction();

                # get existing sensitive data if any
                wdh = sqlif.cacheWorkflowData(wfiid);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        # should not happen
        if (!wdh)
            throw "ORDER-ERROR", sprintf("cannot replace sensitive data for non-existent order %d", wfiid);

        SensitiveInstanceData sd();
        if (wdh.sensitive_data)
            WFEntry::initializeSensitiveData(wfiid, sd, wdh.sensitive_data);
        sd.replaceAndSave(skey, svalue, data, aliases, meta, wfiid);
    }

    # do not do any SQL logging here; there may be no WorkflowInstance object
    static private int createSynchronousWorkflowRowNoCommit(softint wfid, OrderData order, string status = OMQ::StatInProgress) {
        int wfiid = sqlif.createWorkflowInstance(wfid, Qorus.getSessionId(), order.parent_workflow_instanceid,
            order.subworkflow, order.staticdata, order.dynamicdata, order.sensitive_data,
            order.external_order_instanceid, order.priority, NOTHING, True, status);

        # audit workflow creation
        Qorus.audit.workflowOrderCreatedNoCommit(tld.cx, wfid, wfiid, order.priority, status,
            order.external_order_instanceid, order.scheduled, order.parent_workflow_instanceid, order.subworkflow,
            True);

        if (order.orderkeys) {
            SegmentManagerBase::createOrderKeysNoCommit(wfid, wfiid, order.orderkeys);
        }

        return wfiid;
    }

    static private setThreadVars(*hash q) {
        QDBG_ASSERT(ensure_tld());
        tld.ind = q.ind;
    }

    # only called when not cached
    static private *hash commitStepAndWorkflowErrorStatus(hash qs, string reason) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                if (sqlif.setWorkflowInstanceError(qs.workflow_instanceid, qs.segid, qs.stepid, qs.ind, Qorus.getSessionId())) {
                    omqp.rollback();
                    qlog(LoggerLevel::INFO, "cannot update workflow_instance %d status to 'E' (ERROR); it is being "
                        "processed in another Qorus application instance or has status 'C' (COMPLETE), "
                        "'B' (BLOCKED), or 'X' (CANCELED)", qs.workflow_instanceid);
                    return;
                }

                Qorus.audit.workflowStatusChangeNoCommit(NOTHING, qs.workflowid, qs.workflow_instanceid, qs.workflowstatus, OMQ::SQLStatError, reason);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # raise system event if a change was made to the workflow order's status
        if (qs.status != OMQ::StatError) {
            hash<auto> workflow_hash += Qorus.qmm.lookupWorkflow(qs.workflowid, False);
            Qorus.events.postWorkflowStatusChanged(NOTHING, workflow_hash.name, workflow_hash.version, qs.workflowid, qs.workflow_instanceid, ("old": qs.status, "new": OMQ::StatError));
        }

        *hash q = sqlif.getSubworkflowParentAndGrandparentInfoTrans(qs.workflow_instanceid);
        if (!q)
            return;

        # get front end segment ID for step
        hash<auto> wfi = Qorus.qmm.lookupWorkflow(q.workflowid, False);
        int segid;
        for (segid = 0; segid < elements wfi.segment; ++segid) {
            if (exists wfi.segment[segid].steps.(q.stepid))
                break;
        }

        q.segid = segid;
        q.parent_info = remove q.("parent_workflow_instanceid", "subworkflow");

        # DEBUG
        #log(LoggerLevel::INFO, "DEBUG: qs: %y", qs);
        #log(LoggerLevel::INFO, "DEBUG: sq: %y", sq);
        #log(LoggerLevel::INFO, "DEBUG: q: %y", q);

        return q;
    }

    # must be called in the cache/workflowid lock
    # issue #2368 return status saved to DB
    static private int createWorkflowInstanceNoCommit(softstring wfid, OrderData order, bool owned, reference<string> status) {
        if (status == OMQ::StatReady && order.scheduled > now()) {
            status = OMQ::StatScheduled;
        } else if (status == OMQ::StatScheduled && order.scheduled <= now()) {
            status = OMQ::StatReady;
        }

        int wfiid = sqlif.createWorkflowInstance(wfid,
                                                owned ? Qorus.getSessionId() : 0,
                                                order.parent_workflow_instanceid,
                                                order.subworkflow,
                                                order.staticdata,
                                                order.dynamicdata,
                                                order.sensitive_data,
                                                order.external_order_instanceid,
                                                order.priority,
                                                order.scheduled,
                                                False,
                                                status);

        if (order.orderkeys) {
            SegmentManagerBase::createOrderKeysNoCommit(wfid, wfiid, order.orderkeys);
        }

        # audit workflow creation
        Qorus.audit.workflowOrderCreatedNoCommit(tld.cx, wfid, wfiid, order.priority, status,
            order.external_order_instanceid, order.scheduled, order.parent_workflow_instanceid, order.subworkflow,
            False);

        return wfiid;
    }

    static createOrderKeysNoCommit(softint wfid, softint wfiid, hash<auto> k) {
        hash<auto> wf = Qorus.qmm.lookupWorkflow(wfid, False);

        # issue #2067: ensure that order keys are unique
        BulkInsertOperation ins(Qorus.dsmanager.getOmqTable("order_instance_keys"));
        on_error ins.discard();
        on_success ins.flush();

        hash<auto> kh;
        foreach string key in (keys k) {
            if (!wf.order_key_map{key})
                throw "WORKFLOW-KEY-ERROR", sprintf("key %y is not valid for workflowid %d (%s:%s), valid keys: %y", key, wfid, wf.name, wf.version, wf.keylist);

            foreach softstring kv in (k{key}) {
                if (kh{key}{kv})
                    throw "DUPLICATE-ORDER-KEY-ERROR", sprintf("duplicate order key found for workflow %s v%s (%d) key %y; value %y", wf.name, wf.version, wfid, key, kv);
                kh{key}{kv} = True;

                ins.queueData(("workflowid": wfid, "workflow_instanceid": wfiid, "keyname": key, "value": kv));
            }
        }
    }

    private static checkBindEvent(string event) {
        if (!exists tld.eventTypeID)
            throw "WORKFLOW-EVENT-ERROR", "bind_event() can only be called in a workflow event step";

        if (exists tld.eventKey)
            throw "WORKFLOW-EVENT-ERROR", sprintf("bind_event(%y) called, but event %y is already bound to this step",
                event, tld.eventKey);

        if (tld.skipEvent)
            throw "WORKFLOW-EVENT-ERROR", "bind_event() called after skip_event()";
    }

    private static updateBoundEvent(string event) {
        QDBG_ASSERT(ensure_tld());
        # write event info directly into step structure
        tld.wfe.steps.(tld.stepID)[tld.ind].event = event;

        # set thread flag that event has been stored in the DB
        tld.eventKey = event;
    }

    static skipStepSQL(softint wfiid, softint stepid, softint ind, bool swf) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                sqlif.smSkipStepSQL(wfiid, stepid, ind, Qorus.getSessionId(), swf, tld.cx.user);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    static lockOrderSql(softstring wfiid, string note, *string user) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                sqlif.lockOrderNoCommit(wfiid, user ?? tld.cx.user, Qorus.getSessionId());
                OrderInstanceNotes::addSaveNoCommit(wfiid, note);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    static unlockOrderSql(softstring wfiid, string note, *string user) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                sqlif.unlockOrderNoCommit(wfiid, user ?? tld.cx.user, Qorus.getSessionId());
                OrderInstanceNotes::addSaveNoCommit(wfiid, note);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    static breakOrderLockSql(softstring wfiid, string note) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                if (sqlif.breakOrderLockNoCommit(wfiid, Qorus.getSessionId())) {
                    OrderInstanceNotes::addSaveNoCommit(wfiid, note);
                }
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    static private hash<auto> getSubWorkflowStatus(softint wfiid, softint stepid, int ind) {
        *hash<auto> swq;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                swq = sqlif.smGetSubWorkflowStatus(wfiid, stepid, ind);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        return {
            "subworkflow_instanceid": swq.workflow_instanceid,
            "subworkflowstatus": OMQ::SQLStatMap.(swq.workflowstatus),
        };
    }

    static list<auto> getWorkflowAuditEventsSQL(softint wfiid) {
        *hash<auto> q;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                q = omqp.select("select audit_eventid, related_audit_eventid, audit_event_code, audit_user_event, reason, who, source, info1, info2, created from audit_events where workflow_instanceid = %v order by created", wfiid);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        return process_audit_events(q);
    }

    static hash<auto> setOrderKeysSql(int wfid, int wfiid, hash new_keys, bool truncate, *hash order_keys) {
        *hash<auto> wfh = Qorus.qmm.lookupWorkflow(wfid);
        if (!wfh)
            throw "INVALID-WORKFLOW", sprintf("workflowid %d has been deleted while processing an order keys change request", wfid);

        if (!exists order_keys)
            order_keys = sqlif.getOrderKeysTrans(wfiid);
        return WFEntry::setOrderKeysStatic(wfid, wfiid, wfh.order_key_map, order_keys, new_keys, truncate,
            "the update order keys call");
    }

    static hash<auto> getWorkflowInstanceInfoIntern(hash wd, bool compat = True) {
        int wcount = (foldl $1 + 1, (map 1, wd.errors, OMQ::ErrorSeverityOrder.($1.severity) <= 1)) ?? 0;

        return {
            "name"                       : wd.wf.name,
            "version"                    : wd.wf.version,
            "author"                     : wd.wf.author,
            "workflow_instanceid"        : wd.workflow_instanceid,
            "workflowid"                 : wd.wf.workflowid,
            "workflowstatus"             : wd.status,
            "status_sessionid"           : Qorus.getSessionId(),
            "parent_workflow_instanceid" : wd.parent_info.parent_workflow_instanceid,
            "subworkflow"                : boolean(wd.parent_info.subworkflow),
            "synchronous"                : compat ? (wd.sync ? "1" : "0") : boolean(wd.sync),
            "warnings"                   : wcount ? (compat ? string(wcount) : wcount) : NOTHING,
            "errors"                     : wd.errors ? (compat ? string(elements wd.errors - wcount) : (elements wd.errors - wcount)) : NOTHING,
            "archive"                    : NOTHING,
            "business_error"             : wd.business_error ? True : False,
            "started"                    : wd.started,
            "completed"                  : NOTHING,
            "modified"                   : now(),   # note: not real data
            "scheduled"                  : wd.reschedule,
            "custom_status"              : wd.custom_status,
            "custom_status_desc"         : wd.wf.custom_statuses{wd.custom_status},
            "priority"                   : wd.priority,
            "deprecated": wd.wf.depr,
         } + (compat ? {"createdby": "omq", "modifiedby": "omq"} : NOTHING);
    }

    # must be called in the workflowid lock unless corrected = True
    # wfiid, stepid, ind = parent info
    static createSubWorkflowInstanceRowNoCommit(softint wfiid, softint stepid, softint ind, softint subworkflow_instanceid, *softint corrected) {
        sqlif.insertSubWorkflowInstance(wfiid, stepid, ind, subworkflow_instanceid, corrected);
    }

    static *list<auto> getDBErrors(softint wfiid, *softint minerr) {
        *list<auto>l;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                l = sqlif.smGetDBErrors(wfiid, minerr, ERROR_LIMIT);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        return map $1 + ("business_error":boolean($1.business_error)), l;
    }

    static *hash<auto> getAllSubWorkflowInfo(softint wfiid) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                return sqlif.smGetAllSubWorkflowInfo(wfiid);
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
        }
    }

    # returns True for error, False for OK
    static bool removeAsyncErrors(reference<hash<auto>> qs, list<auto> err) {
        # if there is an error list, remove errored elements from data
        list<auto> ind = ();
        list<auto> data = ();
        list<auto> corrected = ();
        list<auto> queuekey = ();

        foreach auto qdata in (qs.data) {
            if ($# == err[0]) {
                shift err;
                continue;
            }

            ind += qs.ind[$#];
            data += qdata;
            corrected += qs.corrected[$#];
            queuekey += qs.queuekey[$#];
        }

        # if there are no elements left, then release segment in workflow queue
        if (!ind)
            return True;

        # otherwise replace lists
        qs = {
            # bug 1171: also include workflow_instanceid
            "workflow_instanceid": qs.workflow_instanceid,
            "ind": ind,
            "data": data,
            "corrected": corrected,
            "queuekey": queuekey,
        };

        return False;
    }
}
