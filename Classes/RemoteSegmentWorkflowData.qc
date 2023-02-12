# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus RemoteSegmentWorkflowData class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

class OMQ::RemoteSegmentWorkflowData inherits AbstractCoreSegmentWorkflowData {
    private {
        # qwf process object hash
        hash<ClusterProcInfo> qwfc;

        # workflow client object
        QwfClient wfc;

        # save workflow info in case the Workflow object is deleted before we shut down the qwf process
        hash<auto> wfinfo;

        # if the process stop should be done by the qwff process itself
        bool detached_stop;
    }

    constructor(Workflow wf, bool qref, bool temp) : AbstractCoreSegmentWorkflowData(wf, qref, temp) {
        subscribeToLogIfNeeded();
        wfinfo = wf{"name", "version", "workflowid"};
    }

    destructor() {
        #Qorus.logInfo("DBG: RemoteSegmentWorkflowData::destructor(): stopping qwfc: %y", qwfc);
        # stop the process if it exists; stopping the process will also stop and delete the workflow queue
        if (wfc && !wfc.isAborted() && qwfc) {
            stopProcess();
        }
    }

    setDetachedStop() {
        detached_stop = True;
    }

    # called if the process is aborted while resetting
    processedAborted() {
        delete wfc;
        delete qwfc;
    }

    # returns True if the object is managing a running qwf process, False if not
    bool running() {
        return exists qwfc;
    }

    # replaces static data for the given workflow order
    /** @return the original data
    */
    *hash<auto> replaceStaticData(softstring wfiid, *hash<auto> order_data) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("replaceStaticData", wfiid, order_data);
    }

    # replaces dynamic data for the given workflow order
    /** @return the original data
    */
    *hash<auto> replaceDynamicData(softstring wfiid, *hash<auto> order_data) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("replaceDynamicData", wfiid, order_data);
    }

    # updates dynamic data for the given workflow order
    /** @return the original data and a flag if the data was updated or not
    */
    hash<DataOpInfo> updateDynamicData(softstring wfiid, *hash<auto> order_data) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("updateDynamicData", wfiid, order_data);
    }

    # updates dynamic data for the given workflow order
    /** @return the original data and a flag if the data was updated or not
    */
    hash<DataOpInfo> updateDynamicDataPath(softstring wfiid, string path, auto value) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("updateDynamicDataPath", wfiid, path, value);
    }

    # replaces dynamic step data for the given workflow order
    /** @return the original data
    */
    *hash<auto> replaceStepData(softstring wfiid, softstring stepid, int ind, *hash<auto> newdata, string user) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("replaceStepData", wfiid, stepid, ind, newdata, user);
    }

    # replaces sensitive data for the given workflow order, sensitive key, and sensitive data value
    replaceSensitiveData(softstring wfiid, string skey, string svalue, hash<auto> sensitive_data, *softlist aliases,
            *hash<auto> meta) {
        QDBG_ASSERT(refs > trefs);
        doCommand("replaceSensitiveData", wfiid, skey, svalue, sensitive_data, aliases, meta);
    }

    # breaks a lock on a user interaction step and adds a note on the workflow order
    /** @return True if the lock was broken, False if not
    */
    bool breakStepLock(softstring wfiid, softstring stepid, softint ind, string note) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("breakStepLock", wfiid, stepid, ind, note);
    }

    # skips the given step
    skipStep(softstring wfiid, softstring stepid, softint ind, bool subworkflow) {
        QDBG_ASSERT(refs > trefs);
        doCommand("skipStep", wfiid, stepid, ind, subworkflow);
    }

    # sets the given order to ERROR, deletes it from the cache if it exists, and requeues events if necessary
    hash<auto> setErrorDeleteAndRequeueEvents(hash<auto> cx, softstring wfiid) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("setErrorDeleteAndRequeueEvents", get_cx(cx), wfiid);
    }

    hash<auto> setOrderKeys(softint wfiid, hash<auto> new_keys, bool truncate, *hash<auto> order_keys) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("setOrderKeys", wfiid, new_keys, truncate, order_keys);
    }

    # locks the given workflow order
    lockOrder(string user, softstring wfiid, string note) {
        QDBG_ASSERT(refs > trefs);
        doCommand("lockOrder", user, wfiid, note);
    }

    # unlocks the given workflow order
    unlockOrder(string user, softstring wfiid, string note) {
        QDBG_ASSERT(refs > trefs);
        doCommand("unlockOrder", user, wfiid, note);
    }

    # breaks the lock on the given workflow order
    breakOrderLock(softstring wfiid, string note) {
        QDBG_ASSERT(refs > trefs);
        doCommand("breakOrderLock", wfiid, note);
    }

    hash<auto> addOrderNote(softint wfiid, hash<auto> info) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("addOrderNote", wfiid, info);
    }

    list<auto> getNotes(softint wfiid) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("getNotes", wfiid);
    }

    rescheduleOrder(softint wfiid, *date scheduled) {
        QDBG_ASSERT(refs > trefs);
        doCommand("rescheduleOrder", wfiid, scheduled);
    }

    reprioritizeOrder(softint wfiid, int prio) {
        QDBG_ASSERT(refs > trefs);
        doCommand("reprioritizeOrder", wfiid, prio);
    }

    # requeues workflow events for an unblocked or uncanceled workflow order
    requeueEvents(string oldstatus, string wfiid, int priority, hash<auto> parent_info, *date scheduled) {
        QDBG_ASSERT(refs > trefs);
        doCommand("requeueEvents", oldstatus, wfiid, priority, parent_info, scheduled);
    }

    # if log streaming is requested, subscribe to it
    subscribeToLogIfNeeded() {
        if (Qorus.eventLog.isWorkflowLogRequested(wf.workflowid)) {
            subscribeToLog();
        }
    }

    # subscribes to the workflow's log if not subscribed yet
    subscribeToLog() {
        wfc.sendCheckResponse(CPC_CORE_LOG_SUBSCRIBE, NOTHING, CPC_OK);
    }

    # unsubscribes from the workflow's log if subscribed
    unsubscribeFromLog() {
        wfc.sendCheckResponse(CPC_CORE_LOG_UNSUBSCRIBE, NOTHING, CPC_OK);
    }

    # returns a hash of the requested workflow instance or NOTHING
    *hash<auto> getWorkflowInstanceStatus(string wfiid) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("getWorkflowInstanceStatus", wfiid);
    }

    # returns a hash of summary inrder info for the requested workflow instance or NOTHING
    *hash<auto> getOrderInfoSummary(string wfiid) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("getOrderInfoSummary", wfiid);
    }

    # returns a hierarchy of information about the given workflow order instance if cached, otherwise NOTHING
    *hash<auto> getWFIAllInfo(softstring wfiid, bool compat, bool with_sensitive_data) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("getWFIAllInfo", wfiid, compat, with_sensitive_data);
    }

    # returns an info hash of the requested workflow instance or NOTHING
    *hash<auto> getWorkflowInstanceInfo(string wfiid, bool compat) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("getWorkflowInstanceInfo", wfiid, compat);
    }

    # handles blocked or canceled workflow order statuses
    hash<auto> handleWorkflowInstanceStatus(hash<auto> cx, softstring wfiid, string stat, bool setOn, *hash<auto> tempdata,
        *hash<auto> new_keys, string err, hash<auto> wih) {
        QDBG_ASSERT(refs > trefs);
        hash<auto> h = doCommand("handleWorkflowInstanceStatusExtern", get_cx(cx), wfiid, stat, setOn, tempdata, new_keys, err, wih);
        if (h.tld) {
            tld += h.tld;
        }
        return h.val;
    }

    # updates the subworkflow queue
    updateSubWorkflowQueue(int swfiid, string wfiid, int stepid, int ind, string stat) {
        QDBG_ASSERT(refs > trefs);
        doCommand("updateSubWorkflowQueue", swfiid, wfiid, stepid, ind, stat);
    }

    # retries a workflow instance
    hash<auto> retryWorkflowOrder(*hash<auto> cx, string wfiid, hash<auto> wh) {
        QDBG_ASSERT(refs > trefs);
        return doCommand("retryWorkflowOrder", get_cx(cx), wfiid, wh);
    }

    # caches a workflow order with READY statuses
    cacheReadyOrder(softint wfiid, OrderData order, *hash<auto> parent_info) {
        QDBG_ASSERT(refs > trefs);
        doCommand("cacheReadyOrder", wfiid, order, parent_info);
    }

    # saves workflow feedback against an order
    leaveFeedbackCached(string wfiid, string key, auto value) {
        QDBG_ASSERT(refs > trefs);
        doCommand("leaveFeedbackCached", wfiid, key, value);
    }

    *list<hash<auto>> getRecoveryInfo() {
        QDBG_LOG("RemoteSegmentWorkflowData::getRecoveryInfo() getting recovery info for %s v%s (%d)", wf.name, wf.version, wf.workflowid);
        hash<auto> h = {
            "subsystem": "control",
            "method": "getRecoveryInfo",
        };
        return doRemoteCommand(h);
    }

    QwfClient getWorkflowClient() {
        return wfc;
    }

    *hash<auto> getWFEntryDebugHash(string wfiid) {
        return doUnreliableCommand("getWFEntryDebugHash", wfiid);
    }

    startProcess() {
        QDBG_LOG("starting qwf process %s v%s (%d)", wf.name, wf.version, wf.workflowid);
        QDBG_ASSERT(!qwfc);
        # start cluster process
        qwfc = Qorus.startWorkflowProcess(wf).info;
        wfc = new QwfClient(Qorus, wf.name, wf.version, wf.workflowid);
        QDBG_LOG("started");
    }

    private stopProcess() {
        # issue 2855: the Workflow object could be destroyed at this point, we need to use our local copies of the
        # data
        bool reset = Qorus.control.isWorkflowInReset(wfinfo.workflowid);
        QDBG_LOG("stopping qwf process %s v%s (%d) reset: %y detached: %y", wfinfo.name, wfinfo.version, wfinfo.workflowid, reset, detached_stop);
        QDBG_ASSERT(qwfc);
        if (!detached_stop) {
            stopProcessIntern(wfinfo, remove qwfc, remove wfc, reset);
        } else {
            bool process_dead = stopAndDeleteWorkflowQueueUnreliable(wfc, wfinfo);
            delete wfc;
            # set the process stop timestamp
            Qorus.control.wf_stop_map{wfinfo.workflowid} = now_us();
            if (!process_dead) {
                Qorus.detachProcess(qwfc);
            }
        }
    }

    static private stopProcessIntern(hash<auto> wfinfo, hash<ClusterProcInfo> qwfc, QwfClient wfc, bool reset) {
        bool process_dead;
        if (reset) {
            # issue #2647: tell the master process to disable restarting the workflow until it's been restarted
            Qorus.ignoreProcessAbort(qwfc);
            process_dead = RemoteSegmentWorkflowData::stopAndDeleteWorkflowQueueUnreliable(wfc, wfinfo);
        } else {
            try {
                RemoteSegmentWorkflowData::doCommand(wfc, "stopAndDeleteWorkflowQueue");
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "CLIENT-DEAD" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED") {
                    Qorus.logInfo("workflow %s v%s (%d) terminated unexpectedly while stopping: %s: %s", wfinfo.name,
                        wfinfo.version, wfinfo.workflowid, ex.err, ex.desc);
                    process_dead = True;
                }
            }
        }
        # set the process stop timestamp
        Qorus.control.wf_stop_map{wfinfo.workflowid} = now_us();
        # issue #2564: always delete clients before stopping the process
        delete wfc;
        if (!process_dead) {
            # must stop workflow synchronously or there can be a race condition with workflow terminations
            # and restarts if performed in the background
            Qorus.stopProcess(qwfc);
        }
    }

    # returns True if the process is dead
    static private bool stopAndDeleteWorkflowQueueUnreliable(QwfClient wfc, hash<auto> wfinfo) {
        try {
            RemoteSegmentWorkflowData::doUnreliableCommand(wfc, "stopAndDeleteWorkflowQueue");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CLIENT-DEAD" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED") {
                Qorus.logInfo("workflow %s v%s (%d) terminated unexpectedly while stopping: %s: %s", wfinfo.name,
                     wfinfo.version, wfinfo.workflowid, ex.err, ex.desc);
                return True;
            } else {
                rethrow;
            }
        }
        return False;
    }

    private createWorkflowQueue() {
        RemoteWorkflowQueue rwfq(wfc);
        WC = rwfq;
    }

    private auto doCommand(string method) {
        hash<auto> h = {
            "subsystem": "swd",
            "method": method,
            "args": argv,
        };
        return doRemoteCommand(h);
    }

    private auto doRemoteCommand(hash<auto> h) {
        *list<string> msgs = wfc.sendCheckResponse(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    private auto doUnreliableCommand(string method) {
        hash<auto> h = {
            "subsystem": "swd",
            "method": method,
            "args": argv,
        };

        *list<string> msgs = wfc.sendCheckResponseUnreliable(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    logArgs(int lvl, string fmt) {
        Qorus.logArgs(lvl, "OMQ: " + fmt, argv);
    }

    logFatal(string fmt) {
        Qorus.logArgs(LoggerLevel::FATAL, "OMQ: " + fmt, argv);
    }

    logError(string fmt) {
        Qorus.logArgs(LoggerLevel::ERROR, "OMQ: " + fmt, argv);
    }

    logWarn(string fmt) {
        Qorus.logArgs(LoggerLevel::WARN, "OMQ: " + fmt, argv);
    }

    logInfo(string fmt) {
        Qorus.logArgs(LoggerLevel::INFO, "OMQ: " + fmt, argv);
    }

    logDebug(string fmt) {
        Qorus.logArgs(LoggerLevel::DEBUG, "OMQ: " + fmt, argv);
    }

    logTrace(string fmt) {
        Qorus.logArgs(LoggerLevel::TRACE, "OMQ: " + fmt, argv);
    }

    # send request to remote process to update logger
    updateLoggerImpl(*hash<LoggerParams> params) {
        hash<auto> h = {
            "method": "updateLogger",
            "args": params,
        };
        wfc.sendCheckResponse(CPC_INTERFACE_CALL_METHOD, h, CPC_OK);
    }

    # send request to remote process to rotate log files
    rotateLogFiles() {
        hash<auto> h = {
            "method": "rotateLogFiles",
            "args": NOTHING,
        };
        wfc.sendCheckResponse(CPC_INTERFACE_CALL_METHOD, h, CPC_OK);
    }

    static private auto doCommand(QwfClient wfc, string method) {
        hash<auto> h = {
            "subsystem": "swd",
            "method": method,
            "args": argv,
        };
        return RemoteSegmentWorkflowData::doRemoteCommand(wfc, h);
    }

    static private auto doRemoteCommand(QwfClient wfc, hash<auto> h) {
        *list<string> msgs = wfc.sendCheckResponse(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    static private auto doUnreliableCommand(QwfClient wfc, string method) {
        hash<auto> h = {
            "subsystem": "swd",
            "method": method,
            "args": argv,
        };

        *list<string> msgs = wfc.sendCheckResponseUnreliable(CPC_QWF_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }
}
