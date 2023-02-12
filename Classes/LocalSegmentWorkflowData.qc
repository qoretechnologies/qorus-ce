# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus LocalSegmentWorkflowData class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

# holds cache information per workflowid for locally-managed workflows (qorus-core and qwf processes)
class OMQ::LocalSegmentWorkflowData inherits AbstractSegmentWorkflowData {
    constructor(Workflow wf) : AbstractSegmentWorkflowData(wf) {
    }

    # returns True if the object is managing a running qwf process, False if not
    bool running() {
        return False;
    }

    # replaces static data for the given workflow order
    /** @return the original data
    */
    *hash<auto> replaceStaticData(softstring wfiid, *hash<auto> data) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            return wfe.replaceStaticData(data);
        }

        return SegmentManagerBase::replaceExternalData("staticdata", wfiid, data);
    }

    # replaces dynamic data for the given workflow order
    /** @return the original data
    */
    *hash<auto> replaceDynamicData(softstring wfiid, *hash<auto> data) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            return wfe.replaceDynamicData(data);
        }

        return SegmentManagerBase::replaceExternalData("dynamicdata", wfiid, data);
    }

    # updates dynamic data for the given workflow order
    /** @return the original data and a flag if the data was updated or not
    */
    hash<DataOpInfo> updateDynamicData(softstring wfiid, *hash<auto> new_data) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            return wfe.updateStaticData(new_data);
        }

        bool updated;
        *hash<auto> orig = SegmentManagerBase::updateExternalData("dynamicdata", wfiid, new_data, \updated);
        return <DataOpInfo>{
            "orig": orig,
            "updated": updated ?? False,
        };
    }

    # updates dynamic data for the given workflow order
    /** @return the original data and a flag if the data was updated or not
    */
    hash<DataOpInfo> updateDynamicDataPath(softstring wfiid, string path, auto value) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            return wfe.updateDynamicDataPath(path, value);
        }

        bool updated;
        *hash<auto> orig = SegmentManagerBase::updateExternalDataPath("dynamicdata", wfiid, path, value, \updated);
        return <DataOpInfo>{
            "orig": orig,
            "updated": updated ?? False,
        };
    }

    *hash<auto> replaceStepData(softstring wfiid, softstring stepid, int ind, *hash<auto> newdata, string user) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            return wfe.replaceStepData(stepid, ind, newdata, user);
        }

        return SegmentManagerBase::replaceExternalStepData(wfiid, stepid, ind, newdata, user);
    }

    # replaces sensitive data for the given workflow order, sensitive key, and sensitive data value
    replaceSensitiveData(softstring wfiid, string skey, string svalue, hash<auto> data, *softlist aliases,
        *hash<auto> meta) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            wfe.replaceSensitiveData(skey, svalue, data, aliases, meta);
        } else {
            SegmentManagerBase::replaceExternalSensitiveData(wfiid, skey, svalue, data, aliases, meta);
        }
    }

    # breaks a lock on a user interaction step and adds a note on the workflow order
    /** @return True if the lock was broken, False if not
    */
    bool breakStepLock(softstring wfiid, softstring stepid, softint ind, string note) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            return wfe.breakStepLock(stepid, ind, note);
        } else {
            return SegmentManagerBase::breakStepLockSql(wfiid, stepid, ind, note);
        }
    }

    # skips the given step
    skipStep(softstring wfiid, softstring stepid, softint ind, bool subworkflow) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            wfe.skipStep(stepid, ind, subworkflow);
        }
        else {
            SegmentManagerBase::skipStepSQL(wfiid, stepid, ind, subworkflow);
        }
    }

    # sets the given order to ERROR, deletes it from the cache if it exists, and requeues events if necessary
    hash<auto> setErrorDeleteAndRequeueEvents(hash<auto> cx, softstring wfiid) {
        writeLock();
        on_exit writeUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            # if the following call returns, then we can flush the status and delete the entry
            wfe.setError(cx);
            SM.deleteWorkflowCacheEntry(wfiid);
        }

        hash rv = SegmentManagerBase::setErrorSql(cx, wf.workflowid, wfiid);
        # get all queue and subworkflow entries and detached segments
        if (rv.old_status == OMQ::StatCanceled || rv.old_status == OMQ::StatBlocked) {
            rv += SegmentManagerBase::requeueEventsSql(wfiid, rv.priority, rv.parent_info, cast<WorkflowQueueBase>(WC));
        }

        return rv;
    }

    hash<auto> setOrderKeys(softint wfiid, hash<auto> new_keys, bool truncate, *hash<auto> order_keys) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            return wfe.setOrderKeys(new_keys, truncate);
        }

        return SegmentManagerBase::setOrderKeysSql(wf.workflowid, wfiid, new_keys, truncate, order_keys);
    }

    # locks the given workflow order
    lockOrder(string user, softstring wfiid, string note) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            wfe.lockOrder(note, user);
        }
        else {
            SegmentManagerBase::lockOrderSql(wfiid, note, user);
        }
    }

    # unlocks the given workflow order
    unlockOrder(string user, softstring wfiid, string note) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            wfe.unlockOrder(note, user);
        }
        else {
            SegmentManagerBase::unlockOrderSql(wfiid, note, user);
        }
    }

    # breaks the lock on the given workflow order
    breakOrderLock(softstring wfiid, string note) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            wfe.breakOrderLock(note);
        } else {
            SegmentManagerBase::breakOrderLockSql(wfiid, note);
        }
    }

    # saves a note against a workflow order
    hash<auto> addOrderNote(softint wfiid, hash<auto> info) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            return wfe.orderInstanceNotes.addCommit(wfiid, info);
        }

        return OMQ::OrderInstanceNotes::addSave(wfiid, info);
    }

    # returns all notes for the given workflow order or an empty list if there are none
    list<auto> getNotes(softint wfiid) {
        readLock();
        on_exit readUnlock();

        QDBG_LOG("LocalSegmentWorkflowData::getNotes() %s: in read lock", self.uniqueHash());

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            return wfe.orderInstanceNotes.get();
        }

        return OMQ::OrderInstanceNotes::getNotes(wfiid);
    }

    rescheduleOrder(softint wfiid, *date scheduled) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            wfe.reschedule(scheduled, cast<WorkflowQueueBase>(WC), True);
        }
        else {
            SegmentManagerBase::rescheduleOrderSql(wfiid, scheduled, cast<WorkflowQueueBase>(WC));
        }
    }

    reprioritizeOrder(softint wfiid, int prio) {
        readLock();
        on_exit readUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            wfe.reprioritize(prio, cast<WorkflowQueueBase>(WC), True);
        }
        else {
            SegmentManagerBase::reprioritizeOrderSql(wfiid, prio, cast<WorkflowQueueBase>(WC));
        }
    }

    # requeues workflow events for an unblocked or uncanceled workflow order
    requeueEvents(string oldstatus, string wfiid, int priority, hash<auto> parent_info, *date scheduled) {
        if (inlist(oldstatus, (OMQ::SQLStatReady, OMQ::SQLStatScheduled))) {
            WC.addToWorkflowInstanceQueue(wfiid, priority, parent_info, scheduled);
        } else {
            SegmentManagerBase::requeueEventsSql(wfiid, priority, parent_info, cast<WorkflowQueueBase>(WC));
        }
    }

    # returns a hash of the requested workflow instance or NOTHING
    *hash<auto> getWorkflowInstanceStatus(string wfiid) {
        return SM.getLocalWorkflowInstanceStatus(wfiid);
    }

    # returns a hash of summary inrder info for the requested workflow instance or NOTHING
    *hash<auto> getOrderInfoSummary(string wfiid) {
        return SM.getLocalOrderInfoSummary(wfiid);
    }

    # returns a hierarchy of information about the given workflow order instance if cached, otherwise NOTHING
    *hash<auto> getWFIAllInfo(softstring wfiid, bool compat, bool with_sensitive_data) {
        return SM.getLocalWFIAllInfo(wfiid, compat, with_sensitive_data);
    }

    # returns an info hash of the requested workflow instance or NOTHING
    *hash<auto> getWorkflowInstanceInfo(string wfiid, bool compat) {
        return SM.getLocalWorkflowInstanceInfo(wfiid, compat);
    }

    # updates the subworkflow queue
    updateSubWorkflowQueue(int swfiid, string wfiid, int stepid, int ind, string stat) {
        hash<auto> h = SM.getPriorityWorkflowIDAndParent(wfiid);
        cast<WorkflowQueueBase>(WC).updateSubWorkflowQueue(wfiid, stepid, ind, h.priority, swfiid, h.parent_info, stat);
    }

    # handles blocked or canceled workflow order statuses
    hash<auto> handleWorkflowInstanceStatus(hash<auto> cx, softstring wfiid, string stat, bool setOn,
        *hash<auto> tempdata, *hash<auto> new_keys, string err, hash<auto> wih) {
        writeLock();
        on_exit writeUnlock();

        *WFEntry wfe = SM.getWFEntryUnlocked(self, wfiid);

        if (wfe) {
            if (tempdata) {
                wfe.setTempData(tempdata);
            }
            if (new_keys) {
                wfe.setOrderKeys(new_keys, False);
            }

            #logDebug("handleWorkflowInstanceStatus cache hit for %s (tempdata: %y newkeys: %y)", wfiid, boolean(tempdata), boolean(new_keys));
            if (!setOn) {
                # if there is a race condition and the data has just been marked as blocked by the attach function, then throw
                # an exception here - this should rarely happen
                if (wfe.status == stat)
                    throw err, sprintf("cannot unblock/un-cancel workflow_instanceid %d while an internal block operation is in progress");

                # otherwise it must be unblocked, so we just return the current status
                return ("workflow_status": wfe.status);
            }

            wfe.blockOrCancel(stat);

            if (tld.attachInProgress) {
                tld.attachIsBlocked = True;
            }
            else {
                wfe.flushStatus();
                SM.deleteWorkflowCacheEntry(wfiid);
            }

            # issue #1861: remove events from queues for BLOCKED / CANCELED orders
            cast<WorkflowQueueBase>(WC).removeWorkflowOrder(wfiid, wih.priority);

            return {"workflow_status": stat};
        }

        return SM.handleWorkflowInstanceStatusCached(cx, wf.workflowid, wfiid, stat, setOn, tempdata, new_keys, err, wih);
    }

    # retries a workflow instance
    hash<auto> retryWorkflowOrder(*hash<auto> cx, string wfiid, hash<auto> wh) {
        return SM.retryWorkflowOrderCached(cx, wfiid, wh);
    }

    # caches a workflow order with READY statuses
    cacheReadyOrder(softint wfiid, OrderData order, *hash<auto> parent_info) {
        SM.cacheReadyOrder(wfiid, wf.workflowid, order, parent_info);
    }

    # saves workflow feedback against an order
    leaveFeedbackCached(string wfiid, string key, auto value) {
        SM.leaveFeedbackCached(wf.workflowid, wfiid, key, value);
    }

    *hash<auto> getWFEntryDebugHash(string wfiid) {
        *WFEntry wfe = SM.getWFEntryDebug(wfiid);
        return wfe ? wfe.getDebugHash() : NOTHING;
    }
}
