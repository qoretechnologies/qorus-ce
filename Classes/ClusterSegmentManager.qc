# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus ClusterSegmentManager class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

class OMQ::ClusterSegmentManager inherits OMQ::SegmentManagerBase {
    public {
        ClusterSegmentWorkflowData local_swd;
    }

    constructor(Workflow wf) {
        local_swd = SWD{wf.workflowid} = new ClusterSegmentWorkflowData(wf);
    }

    shutdown() {
        # purge all cached workflow orders to the DB
        ensure_create_tld();
        purgeOrders(Qorus.interfaceId);

        SegmentManagerBase::shutdown();
    }

    private purgeOrdersIntern(string wfid, list fl) {
        WFEntryCache::flushAndDelete(fl);
    }

    list getOrderInstanceNotes(softint wfiid, *int count) {
        return SMC.getOrderInstanceNotes(wfiid, count);
    }

    OMQ::AbstractSegmentWorkflowData getSegmentWorkflowData(Workflow wf, bool qref, bool temp) {
        return new ClusterSegmentWorkflowData(wf);
    }

    # always called in the AbstractSegmentWorkflowData read lock
    *hash getWorkflowInstanceInfo(string wfid, string wfiid, bool compat) {
        if (!SWD{wfid})
            return SMC.getWorkflowInstanceInfo(wfid, wfiid, compat);

        return getLocalWorkflowInstanceInfo(wfiid, compat);
    }

    int createWorkflowInstance(softstring wfid, OrderData order, string status = OMQ::StatReady) {
        return SMC.createWorkflowInstanceExtern(wfid, order.serialize(), status);
    }

    string bindSubWorkflow(hash parent_info, softstring wfid, OrderData order) {
        return SMC.bindSubWorkflowExtern(parent_info, wfid, order.serialize());
    }

    postSyncEvent(softstring wfid, softstring stepid, softint wfiid, softint ind, softint prio, *hash parent_info) {
        SMC.postSyncEvent(wfid, stepid, wfiid, ind, prio, parent_info);
    }

    updateQueue(softstring wfid, softstring stepid, softint wfiid, softint ind, softint prio, softbool corrected, string queuekey, auto data, *hash parent_info) {
        SMC.updateQueue(wfid, stepid, wfiid, ind, prio, corrected, queuekey, data, parent_info);
    }

    hash retryWorkflowInstance(softstring wfiid) {
        return SMC.retryWorkflowInstance(wfiid);
    }

    leaveFeedback(string wfiid, string key, auto value) {
        SMC.leaveFeedbackExtern(wfiid, key, value);
    }

    # update info in qorus-core
    updateSubWorkflowQueueIntern(softint swfiid, *softstring wfid, softstring wfiid, *softint stepid, *softint ind, string stat) {
        SMC.updateSubWorkflowQueueExtern(swfiid, wfid, wfiid, stepid, ind, stat);
    }

    updateRetryDelay(softstring wfid, *softint r) {
        QDBG_ASSERT(exists SWD{wfid});
        local_swd.WC.updateRetryDelay(r);
    }

    updateAsyncDelay(softstring wfid, *softint a) {
        QDBG_ASSERT(exists SWD{wfid});
        local_swd.WC.updateAsyncDelay(a);
    }

    # cannot be private, also called from the WFEntry class
    callDetachIntern(WorkflowExecutionInstance wi, string status, *softstring eoiid) {
        # bug 612: make sure and delete any "steperror" key in thread-local data when exiting
        QDBG_ASSERT(ensure_tld());
        on_exit { tld.stepError = NOTHING; }
        try {
            wi.wf.callDetach(status, eoiid);
        } catch (hash<ExceptionInfo> ex) {
            # log error
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            # create an error_instance entry
            wi.stepError(ex.err, ex.desc);
        }
    }

    # this thread will wake up and process cache expirations as necessary
    private cacheThread() {
        create_tld();
        # DEBUG
        #log(LoggerLevel::FATAL, "DEBUG: SM::cacheThread() tid %d starting, TWC: %s", gettid(), TWC.getSummary());

        on_exit cCount.dec();

        while (True) {
            *hash msg = TWC.getEvent();

            if (!msg)
                break;

            # do not allow the cacheThread() to exit with an exception, log and try to continue
            # otherwise workflow data may be left unflushed
            try {
                AbstractSegmentWorkflowData swd = SWD.(msg.wfid);

                swd.writeLock();
                on_exit swd.writeUnlock();

                *WFEntry wfe = getWFEntryUnlocked(swd, msg.wfiid);

                if (wfe && !wfe.refs) {
                    #log(LoggerLevel::DEBUG, "cache entry expired for wfiid %d wfid %d", msg.wfiid, msg.wfid);
                    wfe.flushStatus();
                    wdata.del(msg.wfiid);
                }
            }
            catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::FATAL, "exception in ClusterSegmentManager::cacheThread(): %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            }
        }
        # DEBUG
        #log(LoggerLevel::FATAL, "DEBUG: SM::cacheThread() tid %d exiting", gettid());
    }
}