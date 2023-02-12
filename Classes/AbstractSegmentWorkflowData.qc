# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus AbstractSegmentWorkflowData class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

hashdecl DataOpInfo {
    *hash<auto> orig;
    bool updated;
}

class OMQ::AbstractSegmentWorkflowData inherits RWLock {
    public {
        # workflow
        Workflow wf;

        # workflow queue interface
        /** issue #2647: cluster workflow queues start automatically, and once stopped are not started again in
            the same process.  When flushing a remote queue, the qw process is stopped and started again.

            For local (qorus-core-hosted) workflows, workflow queues are started and stopped as needed
        */
        AbstractWorkflowQueue WC;
    }

    constructor(Workflow wf) {
        self.wf = wf;
    }

    abstract logArgs(int lvl, string fmt);
    abstract logFatal(string msg);
    abstract logError(string msg);
    abstract logWarn(string msg);
    abstract logInfo(string msg);
    abstract logDebug(string msg);
    abstract logTrace(string msg);

    # returns True if the object is managing a running qwf process, False if not
    abstract bool running();

    # replaces static data for the given workflow order
    /** @return the original data
    */
    abstract *hash<auto> replaceStaticData(softstring wfiid, *hash<auto> new_data);

    # replaces dynamic data for the given workflow order
    /** @return the original data
    */
    abstract *hash<auto> replaceDynamicData(softstring wfiid, *hash<auto> new_data);

    # updates dynamic data for the given workflow order
    /** @return the original data and a flag if the data was updated or not
    */
    abstract hash<DataOpInfo> updateDynamicData(softstring wfiid, *hash<auto> new_data);

    # updates dynamic data for the given workflow order
    /** @return the original data and a flag if the data was updated or not
    */
    abstract hash<DataOpInfo> updateDynamicDataPath(softstring wfiid, string path, auto value);

    # replaces dynamic step data for the given workflow order
    /** @return the original data
    */
    abstract *hash<auto> replaceStepData(softstring wfiid, softstring stepid, int ind, *hash<auto> newdata,
            string user);

    # replaces sensitive data for the given workflow order, sensitive key, and sensitive data value
    abstract replaceSensitiveData(softstring wfiid, string skey, string svalue, hash<auto> data, *softlist aliases,
            *hash<auto> meta);

    # breaks a lock on a user interaction step and adds a note on the workflow order
    /** @return True if the lock was broken, False if not
    */
    abstract bool breakStepLock(softstring wfiid, softstring stepid, softint ind, string note);

    # skips the given step
    abstract skipStep(softstring wfiid, softstring stepid, softint ind, bool subworkflow);

    # sets the given order to ERROR, deletes it from the cache if it exists, and requeues events if necessary
    abstract hash<auto> setErrorDeleteAndRequeueEvents(hash<auto> cx, softstring wfiid);

    # sets order keys with the given order keys
    abstract hash<auto> setOrderKeys(softint wfiid, hash<auto> new_keys, bool truncate, *hash<auto> order_keys);

    # locks the given workflow order
    abstract lockOrder(string user, softstring wfiid, string note);

    # unlocks the given workflow order
    abstract unlockOrder(string user, softstring wfiid, string note);

    # breaks the lock on the given workflow order
    abstract breakOrderLock(softstring wfiid, string note);

    # saves a note against a workflow order
    abstract hash<auto> addOrderNote(softint wfiid, hash<auto> info);

    # returns all notes for the given workflow order or an empty list if there are none
    abstract list<auto> getNotes(softint wfiid);

    # sets or clears the scheduled date on the given order
    abstract rescheduleOrder(softint wfiid, *date scheduled);

    # reprioritizes the given workflow order
    abstract reprioritizeOrder(softint wfiid, int prio);

    # requeues workflow events for an unblocked or uncanceled workflow order
    abstract requeueEvents(string oldstatus, string wfiid, int priority, hash<auto> parent_info, *date scheduled);

    # returns a hash of the requested workflow instance or NOTHING
    abstract *hash<auto> getWorkflowInstanceStatus(string wfiid);

    # returns a hash of summary order info for the requested workflow instance or NOTHING
    abstract *hash<auto> getOrderInfoSummary(string wfiid);

    # returns a hierarchy of information about the given workflow order instance if cached, otherwise NOTHING
    abstract *hash<auto> getWFIAllInfo(softstring wfiid, bool compat, bool with_sensitive_data);

    # returns an info hash of the requested workflow instance or NOTHING
    abstract *hash<auto> getWorkflowInstanceInfo(string wfiid, bool compat);

    # updates the subworkflow queue
    abstract updateSubWorkflowQueue(int swfiid, string wfiid, int stepid, int ind, string stat);

    # handles blocked or canceled workflow order statuses
    abstract hash<auto> handleWorkflowInstanceStatus(hash<auto> cx, softstring wfiid, string stat, bool setOn,
        *hash<auto> tempdata, *hash<auto> new_keys, string err, hash<auto> wih);

    # retries a workflow instance
    abstract hash<auto> retryWorkflowOrder(*hash<auto> cx, string wfiid, hash<auto> wh);

    # caches a workflow order with READY statuses
    abstract cacheReadyOrder(softint wfiid, OrderData order, *hash<auto> parent_info);

    # saves workflow feedback against an order
    abstract leaveFeedbackCached(string wfiid, string key, auto value);
}
