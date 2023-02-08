# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus SegmentManager class definition
#
# manages workflow, segment, and step statuses & order instance data
# in the context of multiple asychronous segments

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

%include Classes/SegmentEventQueue.qc

public namespace OMQ;

# SegmentManager provides the internal API for managing access to workflows and segments
class OMQ::SegmentManager inherits OMQ::SegmentManagerBase {
    private:internal {
        # workflow counter, to ensure that the object is only destroyed when all cached workflows have been purged
        Counter wCount();

        # workflow counter hash: notification counters for SWD entries; wfid -> Counter
        hash<string, Counter> wch();
    }

    shutdown() {
        # force delete any segment workflow data objects
        map delete SWD.$1, keys SWD;

        SegmentManagerBase::shutdown();

        # wait for all workflows to finish their destructors
        #wCount.waitForZero();
    }

    *hash getWFEntryHash(softstring wfiid) {
        return wdata.getHash(wfiid);
    }

    *hash<auto> getWFEntryDebugHash(softstring wfiid) {
        string wfid = getWorkflowID(wfiid);

        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            return SWD{wfid}.getWFEntryDebugHash(wfiid);
        }
    }

    enableLoggingIfNeeded(softstring wfid) {
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached && SWD{wfid} instanceof RemoteSegmentWorkflowData) {
            cast<RemoteSegmentWorkflowData>(SWD{wfid}).subscribeToLogIfNeeded();
        }
    }

    enableLogging(softstring wfid) {
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached && SWD{wfid} instanceof RemoteSegmentWorkflowData) {
            cast<RemoteSegmentWorkflowData>(SWD{wfid}).subscribeToLog();
        }
    }

    disableLogging(softstring wfid) {
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached && SWD{wfid} instanceof RemoteSegmentWorkflowData) {
            cast<RemoteSegmentWorkflowData>(SWD{wfid}).unsubscribeFromLog();
        }
    }

    private wfLogArgs(softstring wfid, string msg, string logMethod, auto args) {
        string fmsg = vsprintf(msg, args);
        try {
            call_object_method_args(SWD{wfid}, logMethod, fmsg);
        } catch (hash<ExceptionInfo> ex) {
            # log using system logger
            call_object_method_args(Qorus, logMethod, sprintf("wfid %s: %s", wfid, fmsg));
        }
    }

    wfLogFatal(softstring wfid, string msg) {
        wfLogArgs(wfid, msg, "logFatal", argv);
    }

    wfLogError(softstring wfid, string msg) {
        wfLogArgs(wfid, msg, "logError", argv);
    }

    wfLogWarn(softstring wfid, string msg) {
        wfLogArgs(wfid, msg, "logWarn", argv);
    }

    wfLogInfo(softstring wfid, string msg) {
        wfLogArgs(wfid, msg, "logInfo", argv);
    }

    wfLogDebug(softstring wfid, string msg) {
        wfLogArgs(wfid, msg, "logDebug", argv);
    }

    wfLogTrace(softstring wfid, string msg) {
        wfLogArgs(wfid, msg, "logTrace", argv);
    }

    rotateLogFiles() {
        map rotateLogFiles($1), keys SWD;
    }

    private rotateLogFiles(string wfid) {
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            cast<AbstractCoreSegmentWorkflowData>(SWD{wfid}).rotateLogFiles();
        }
    }

    updateLogger(softstring wfid, *hash<LoggerParams> params) {
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            SWD{wfid}.updateLogger(params);
        }
    }

    string getCacheAsString() {
        string str = "Segment Event Cache:";
        str += sprintf(" (wch: %y)", (map {$1.key: $1.value.getCount()}, wch.pairIterator()));

        rwl.readLock();
        on_exit rwl.readUnlock();

        foreach string id in (keys SWD) {
            AbstractSegmentWorkflowData swd = SWD{id};
            str += sprintf("\nworkflow %s:%s (%d)%s", swd.wf.name, swd.wf.version, id, swd.WC.getCacheAsString());
        }

        return str;
    }

    string getCacheSummary() {
        string str = "Segment Event Cache:";

        rwl.readLock();
        on_exit rwl.readUnlock();

        map str += cast<AbstractCoreSegmentWorkflowData>($1).getSummary(), SWD.iterator();
        return str;
    }

    # returns local debugging info without making any remote calls
    hash<auto> getLocalDebugInfo() {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return {
            "wCount": wCount.getCount(),
            "wch": (map {$1.key: $1.value.getCount()}, wch.pairIterator()),
            "SWD": (map {$1.key: {
                    "class": $1.value.className(),
                    "remote": $1.value.wf.remote,
                    "wf": sprintf("%s v%s (%d)", $1.value.wf.name, $1.value.wf.version, $1.value.wf.workflowid),
                    "info": $1.value.getLocalSummary(),
                },
            }, SWD.pairIterator()),
        };
    }

    # returns True if the given wfid has a running qwf process, False if not
    bool running(softstring wfid) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return SWD{wfid} && SWD{wfid}.running();
    }

    updateRetryDelay(softstring wfid, *softint r) {
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            SWD{wfid}.WC.updateRetryDelay(r);
        }
    }

    updateAsyncDelay(softstring wfid, *softint a) {
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            SWD{wfid}.WC.updateAsyncDelay(a);
        }
    }

    list<auto> processWorkflowResults(list<auto> sqlresult, bool bc = False) {
        # fix status values in result
        foreach hash<auto> r in (\sqlresult) {
            if (r.workflowstatus == 'I') {
                r.workflowstatus = wdata.getStatus(r.workflow_instanceid);
                # data structure is accessed unlocked, so it could have disappeared
                # or maybe is in-progress by another instance
                if (!r.workflowstatus) {
                    r.workflowstatus = OMQ::StatInProgress;
                }
            } else {
                r.workflowstatus = OMQ::SQLStatMap.(r.workflowstatus);
            }

            if (exists r.priority) {
                r.priority = int(r.priority);
            }

            r += {
                "custom_status_desc": exists r.custom_status ? Qorus.qmm.lookupWorkflow(r.workflowid, False).custom_statuses{r.custom_status} : NOTHING,
                "business_error": r.business_error ? True : False,
            };

            if (bc) {
                r += {"createdby": "omq", "modifiedby": "omq"};
            }
        }

        return sqlresult;
    }

    # called only for qwf processes
    waitWorkflowProcessStopped(softstring wfid, code action, Counter done) {
        QDBG_ASSERT(!SWD{wfid} || (SWD{wfid} instanceof RemoteSegmentWorkflowData));

        *Counter c;

        {
            rwl.readLock();
            on_exit rwl.readUnlock();

            c = wch{wfid};
            #QDBG_LOG("SegmentManager::waitWorkflowProcessStopped() assigning wch wfid %y c: %y", wfid, c);
        }

        if (!c) {
            action();
            return;
        }

        done.inc();
        # execute closure immediately in the background
        background sub () {
            #QDBG_LOG("SegmentManager::waitWorkflowProcessStopped() waiting for action in the background wfid: %y c: %y done: %y %d", wfid, c.getCount(), done, done.getCount());
            c.waitForZero();
            on_exit done.dec();
            try {
                action();
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::INFO, "exception waiting for action: %s", get_exception_string(ex));
                # do not allow an unhandled exception to happen in a backgrgound thread
            }
            #QDBG_LOG("SegmentManager::waitWorkflowProcessStopped() action done for wfid: %d decrementing %y: %d", wfid, done, done.getCount());
        }();
    }

    resetCache(softstring wfid, Workflow wf) {
        QDBG_ASSERT(ensure_tld());
        # delete index and restore on exit
        auto index = tld.index;
        on_exit {
            QDBG_LOG("SegmentManagerBase::resetCache() index %y -> %y", tld.index, index);
            tld.index = index;
        }
        tld.index = NOTHING;
        QDBG_LOG("SegmentManagerBase::resetCache() index %y -> %y", index, NOTHING);

        # sanity check
        if (wfid != wf.workflowid)
            throw "WORKFLOW-RESET-ERROR", sprintf("workflow %s v%s (%d) cannot be reset because it has changed workflowids; old ID %d", wf.name, wf.version, wf.workflowid, wfid);

        {
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            # wait for temporary blocks and manual blocks to be cleared
            while (True) {
                if (SWD{wfid}) {
                    if (!SWD{wfid}.startReset(rwl))
                        return;
                    break;
                }

                # check for a temporary block
                while (BC{wfid}) {
                    BC{wfid}.cond.wait(rwl);
                }

                if (!SWD{wfid})
                    return;
            }
        }

        on_exit SWD{wfid}.endReset(rwl);

        {
            # grab the read lock so we have an atomic operation on the workflow order data cache entry list
            SWD{wfid}.readLock();
            on_exit SWD{wfid}.readUnlock();

            # get list of all workflow entries affected
            list<auto> l = wdata.getCachedIds(wfid);

            #QDBG_LOG("DEBUG: SegmentManagerBase::resetCache(wfid: %y, wf: %d) got list: %y", wfid, wf.workflowid, l);

            # flush all workflow entries to the DB
            # issue #2111 the order may have been flushed in another thread
            map ((*WFEntry wfe = wdata.get($1)) ? wfe.flushStatus(True) : NOTHING), l;
        }

        SWD{wfid}.reset(wf);
    }

    *hash getOrderKeysSQL(softint wfiid) {
        return sqlif.getOrderKeysTrans(wfiid);
    }

    *hash getWorkflowInstanceStatus(softstring wfiid) {
        string wfid;
        try {
            wfid = getWorkflowID(wfiid);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-WORKFLOW-ORDER-DATA-INSTANCE")
                return;
        }

        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            try {
                return swd.getWorkflowInstanceStatus(wfiid);
            } catch (hash<ExceptionInfo> ex) {
                # issue #2647: ignore CLIENT-DEAD exceptions in case called in a reset when the qwf process dies
                # in this case, take the data from the DB
                if (ex.err == "CLIENT-DEAD" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED") {
                    qlog(LoggerLevel::INFO, "ignoring exception for aborted remote process while retrieving "
                        "information for wfiid %d (wfid %d): %s: %s", wfiid, wfid, ex.err, ex.desc);
                } else {
                    rethrow;
                }
            }
        }

        return getWorkflowInstanceStatusSQL(wfiid);
    }

    # always called in the write lock
    private OMQ::AbstractSegmentWorkflowData getSegmentWorkflowData(Workflow wf, bool qref, bool temp) {
        QDBG_ASSERT(!wch{wf.workflowid});
        on_success {
            QDBG_LOG("SegmentManager::getSegmentWorkflowData() creating wch counter for wfid: %d", wf.workflowid);
            # create the workflow counter hash on success
            wch{wf.workflowid} = new Counter(1);
        }

        return wf.remote
            ? new RemoteSegmentWorkflowData(wf, qref, temp)
            : new SegmentWorkflowData(wf, qref, temp);
    }

    # called only for workflows with remote = True
    QwfClient getWorkflowClient(softstring wfid) {
        QDBG_ASSERT(SWD{wfid});
        QDBG_ASSERT(SWD{wfid} instanceof RemoteSegmentWorkflowData);
        return cast<RemoteSegmentWorkflowData>(SWD{wfid}).getWorkflowClient();
    }

    *hash getOrderInfoSummary(softstring wfiid) {
        string wfid;
        try {
            wfid = getWorkflowID(wfiid);
        }
        catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-WORKFLOW-ORDER-DATA-INSTANCE")
                return;
        }

        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            return swd.getOrderInfoSummary(wfiid);
        }

        return getOrderInfoSummarySql(wfiid);
    }

    # always called in the AbstractSegmentWorkflowData read lock
    *hash getWorkflowInstanceInfo(string wfid, string wfiid, bool compat) {
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            return swd.getWorkflowInstanceInfo(wfiid, compat);
        }

        return getWorkflowInstanceInfoSql(wfiid, compat);
    }

    # if not cached, return NOTHING
    *hash<auto> getWFIAllInfo(softstring wfiid, *date last_modified_date, bool compat = True,
            bool with_sensitive_data = False) {
        string wfid;
        try {
            wfid = getWorkflowID(wfiid);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-WORKFLOW-ORDER-DATA-INSTANCE")
                return;
        }

        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            return swd.getWFIAllInfo(wfiid, compat, with_sensitive_data);
        }
    }

    static private commitCorrectedQueueData(softint queueid, softstring key, softint wfiid, softint stepid, softint ind) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                sqlif.insertOrUpdateCorrectedQueueData(wfiid, stepid, ind, queueid, key);
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

    updateSubWorkflowQueueExtern(softint swfiid, *softstring wfid, softstring wfiid, *softint stepid, *softint ind,
            string stat) {
        ensure_create_tld();
        updateSubWorkflowQueueIntern(swfiid, wfid, wfiid, stepid, ind, stat);
    }

    # called from qwf processes, cannot be private
    private updateSubWorkflowQueueIntern(softint swfiid, *softstring wfid, softstring wfiid, *softint stepid,
            *softint ind, string stat) {
        QDBG_LOG("SegmentManagerBase::updateSubWorkflowQueueIntern(swfiid: %y, wfid: %y, wfiid: %y, stepid: %y, ind: %y, status: %y)", swfiid, wfid, wfiid, stepid, ind, stat);

        if (!wfid)
            wfid = getWorkflowID(wfiid);

        bool cached = block(wfid);
        on_exit unblock(wfid);

        if (!cached)
            return;

        if (!stepid) {
            *hash q = sqlif.getSubWorkflowStepTrans(swfiid);
            stepid = q.stepid;
            ind = q.ind;

            # DEBUG
            #QDBG_LOG("DEBUG: retrieved for subworkflow %d parent workflow %d step %d/%d", swfiid, wfiid, stepid, ind);
            if (!stepid) {
                throw "SUBWORKFLOW-ERROR", sprintf("couldn't retrieve parent workflow step information for "
                    "subworkflow_instanceid: %y (q: %y)", swfiid, q);
            }
        }

        AbstractSegmentWorkflowData swd = SWD{wfid};
        swd.updateSubWorkflowQueue(swfiid, wfiid, stepid, ind, stat);
    }

    # NOTE: to avoid deadlocks between DB locks and Qorus locks, we just get the workflow ID
    # and then check if this workflow is cached, etc
    replaceStaticData(hash<auto> cx, softstring wfiid, *hash<auto> staticdata, bool throw_nochange_exception = True) {
        string wfid = getWorkflowID(wfiid);

        # issue #3446: check workflow order data if applicable
        hash<auto> wf = Qorus.qmm.lookupWorkflow(wfid, False);
        if (wf.staticdata_type_path) {
            staticdata = OrderData::verifyStaticData(wf.name, wf.version, wfid, staticdata, wf.staticdata_type_path);
        }

        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        *hash<auto> orig;

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            orig = swd.replaceStaticData(wfiid, staticdata);
        } else {
            orig = replaceExternalData("staticdata", wfiid, staticdata);
        }

        if (orig != staticdata) {
            Qorus.events.postWorkflowDataUpdated(wfid, wfiid, "staticdata");
            setOrderInstanceNote(cx, wfiid, {"note": sprintf("staticdata changed: %y", orig)});
        } else if (throw_nochange_exception) {
            throw "REPLACE-STATIC-DATA-SKIPPED", "The static data provided is the same as original";
        }
    }

    replaceDynamicData(hash<auto> cx, softstring wfiid, *hash<auto> new_data, bool throw_nochange_exception = True) {
        string wfid = getWorkflowID(wfiid);

        # see if this workflow is cached
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        *hash<auto> orig;

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            orig = swd.replaceDynamicData(wfiid, new_data);
        } else {
            orig = replaceExternalData("dynamicdata", wfiid, new_data);
        }

        if (orig != new_data) {
            Qorus.events.postWorkflowDataUpdated(wfid, wfiid, "dynamic");
            setOrderInstanceNote(cx, wfiid, ("note": sprintf("dynamicdata changed: %y", orig)));
        } else if (throw_nochange_exception) {
            throw "REPLACE-DYNAMIC-DATA-SKIPPED", "Provided dynamicdata are the same as original";
        }
    }

    updateDynamicData(hash<auto> cx, softstring wfiid, *hash<auto> new_data, bool throw_nochange_exception = False) {
        string wfid = getWorkflowID(wfiid);

        # see if this workflow is cached
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        *hash<auto> orig;
        bool updated;

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            hash<DataOpInfo> h = swd.updateDynamicData(wfiid, new_data);
            orig = h.orig;
            updated = h.updated;
        } else {
            orig = updateExternalData("dynamicdata", wfiid, new_data, \updated);
        }

        if (updated) {
            Qorus.events.postWorkflowDataUpdated(wfid, wfiid, "dynamic");
            setOrderInstanceNote(cx, wfiid, {"note": sprintf("dynamicdata changed: %y", orig)});
        } else if (throw_nochange_exception) {
            throw "UPDATE-DYNAMIC-DATA-SKIPPED", "Provided dynamicdata are the same as original";
        }
    }

    updateDynamicDataPath(hash<auto> cx, softstring wfiid, string path, auto value,
            bool throw_nochange_exception = False) {
        string wfid = getWorkflowID(wfiid);

        # see if this workflow is cached
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        *hash<auto> orig;
        bool updated;

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            hash<DataOpInfo> h = swd.updateDynamicDataPath(wfiid, path, value);
            orig = h.orig;
            updated = h.updated;
        } else {
            orig = updateExternalDataPath("dynamicdata", wfiid, path, value, \updated);
        }

        if (updated) {
            Qorus.events.postWorkflowDataUpdated(wfid, wfiid, "dynamic");
            setOrderInstanceNote(cx, wfiid, {"note": sprintf("dynamicdata changed: %y", orig)});
        } else if (throw_nochange_exception) {
            throw "UPDATE-DYNAMIC-DATA-SKIPPED", "Provided dynamicdata are the same as original";
        }
    }

    replaceStepData(hash<auto> cx, softstring wfid, softstring wfiid, softstring stepid, softint ind,
        *hash<auto> newdata, string user) {
        # see if this workflow is cached
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        *hash<auto> orig;

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            orig = swd.replaceStepData(wfiid, stepid, ind, newdata, user);
        } else {
            orig = replaceExternalStepData(wfiid, stepid, ind, newdata, user);
        }

        if (orig != newdata) {
            Qorus.events.postWorkflowStepDataUpdated(wfid, wfiid, stepid, ind);
            setOrderInstanceNote(cx, wfiid, {
                "note": sprintf("stepdata changed for stepid %d[%d]: %y", stepid, ind, orig)
            });
        }
    }

    replaceSensitiveData(hash<auto> cx, softstring wfiid, string skey, string svalue, hash<auto> data,
        *softlist<auto> aliases, *hash<auto> meta) {
        string wfid = getWorkflowID(wfiid);

        # see if this workflow is cached
        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            swd.replaceSensitiveData(wfiid, skey, svalue, data, aliases, meta);
        } else {
            replaceExternalSensitiveData(wfiid, skey, svalue, data, aliases, meta);
        }

        Qorus.events.postWorkflowDataUpdated(wfid, wfiid, "sensitive");
        setOrderInstanceNote(cx, wfiid, ("note": sprintf("sensitive data changed for key %y", skey)));
    }

    int createWorkflowInstanceExtern(softstring wfid, binary order_data, string status = OMQ::StatReady) {
        return createWorkflowInstance(wfid, Serializable::deserialize(order_data), status);
    }

    int createWorkflowInstance(softstring wfid, OrderData order, string status = OMQ::StatReady) {
        int wfiid;

        bool block_flag = status != OMQ::StatBlocked;

        bool cached = block_flag && block(wfid);
        on_exit if (block_flag) unblock(wfid);

        {
            # ensure atomicity of order creation regarding unique keys and manage new workflow order transaction
            WorkflowUniqueKeyHelper wukth(order);

            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    wfiid = createWorkflowInstanceNoCommit(wfid, order, cached, \status);
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
        }

        QDBG_LOG("SegmentManager::createWorkflowInstance() created %d for %s v%s (%d) cached: %y", wfiid,
            order.getName(), order.getVersion(), wfid, cached);

        # emit system event for workflow creation
        Qorus.events.postWorkflowDataSubmitted(tld.cx, order.getName(), order.getVersion(), wfid, wfiid, status,
            order.parent_workflow_instanceid, order.subworkflow);

        # add to workflow cache
        if (cached) {
            # issue #2495: make sure that the loosly-coupled parent_workflow_instanceid is set if any
            if (!order.parent_workflow_instanceid && tld.wfe) {
                order.parent_workflow_instanceid = tld.wfe.workflow_instanceid;
            }

            AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{wfid});
            # issue #2647: ignore CLIENT-DEAD errors, as the order has been saved to the DB anyway
            try {
                swd.cacheReadyOrder(wfiid, order);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "CLIENT-DEAD" || ex.err == "CLIENT-TERMINATED") {
                    qlog(LoggerLevel::INFO, "creating wfiid %d for %s v%s (%d): ignoring exception for aborted "
                        "remote process: %s: %s", wfiid, order.getName(), order.getVersion(), wfid, ex.err, ex.desc);
                } else {
                    rethrow;
                }
            }
        }

        return wfiid;
    }

    string bindSubWorkflowExtern(hash<auto> parent_info, softstring wfid, binary order) {
        # must have TLD in this call
        ensure_create_tld();
        return bindSubWorkflow(parent_info, wfid, OrderData::deserialize(order));
    }

    # called from a subworkflow step
    string bindSubWorkflow(hash<auto> parent_info, softstring wfid, OrderData order) {
        softstring wfiid;

        bool cached = block(wfid);
        on_exit unblock(wfid);

        string status = OMQ::StatReady;
        {
            # ensure atomicity of order creation regarding unique keys and manage new workflow order transaction
            WorkflowUniqueKeyHelper wukth(order);
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    # create subworkflow instance
                    wfiid = createWorkflowInstanceNoCommit(wfid, order, cached, \status);

                    # now we create the subworkflow_instance row
                    createSubWorkflowInstanceRowNoCommit(parent_info.parent_workflow_instanceid,
                        parent_info.parent_stepid, parent_info.parent_ind, wfiid);
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

        UserApi::logArgsInfo("created subworkflow order instance %d", wfiid);

        # emit system event for workflow creation
        Qorus.events.postWorkflowDataSubmitted(tld.cx, order.getName(), order.getVersion(), wfid, wfiid, status,
            order.parent_workflow_instanceid, order.subworkflow);

        # add to workflow cache
        if (cached) {
            AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{wfid});
            swd.cacheReadyOrder(wfiid, order, parent_info);
        }

        return wfiid;
    }

    #! Returns True if the event was already posted before this call, False if not (i.e. posted now)
    bool postEvent(softint eventid, string eventkey) {
        bool wasposted;
        *hash<string, list<hash<auto>>> steps = Qorus.SEM.post(eventid, eventkey, \wasposted);

        foreach hash<auto> i in (steps.pairIterator()) {
            bool cached = blockRead(i.key);
            on_exit unblockRead(i.key);

            if (!cached) {
                QDBG_LOG("skipping posting events for workflowid %d that is not cached (event count: %d)", i.key,
                    i.value.lsize());
                continue;
            }

            AbstractSegmentWorkflowData swd = SWD{i.key};
            if (!swd.WC) {
                QDBG_LOG("skipping posting events for cached workflow %s v%s (%d) with no workflow queue (event "
                    "count: %d)", swd.wf.name, swd.wf.version, i.key, i.value.lsize());
                continue;
            }
            map swd.WC.postSyncEvent($1.stepid, $1.workflow_instanceid, $1.ind, $1.priority,
                $1{"parent_workflow_instanceid", "subworkflow"}), i.value;
            UserApi::logArgsInfo("posted events for cached workflow %s v%s (%d); event count: %d",
                (swd.wf.name, swd.wf.version, i.key, i.value.lsize()));
        }

        return wasposted;
    }

    postSyncEvent(softstring wfid, softstring stepid, softint wfiid, softint ind, softint prio,
            *hash<auto> parent_info) {
        # add to internal queue if possible
        rwl.readLock();
        on_exit rwl.readUnlock();

        # DEBUG
        #QDBG_LOG("DEBUG: SegmentManager::postSyncEvent(wfid: %y, stepid: %y) exists SWD.%y: %y", wfid, stepid,
        #    exists SWD{wfid});

        # NOTE: an exception can only be thrown here if a sync event is posted for
        #       a non-existant step, which can only happen if the workflow has been
        #       illegally redefined using oload -A
        # issue #3490: ensure that workflow queues are in place before calling postSyncEventIntern()
        if (SWD{wfid}.WC) {
            postSyncEventIntern(wfid, stepid, wfiid, ind, prio, parent_info);
        }
    }

    updateQueue(softstring wfid, softstring stepid, softint wfiid, softint ind, softint prio, softbool corrected,
            string queuekey, auto data, *hash<auto> parent_info) {
        # add to internal queue if possible
        # bug 1169: ensure that we update the queues in a consistent way despite possible workflow resets
        bool cached = block(wfid);
        on_exit unblock(wfid);

        # DEBUG
        #QDBG_LOG("DEBUG: SegmentManagerBase::updateQueue(wfid: %y, stepid: %y) exists WC.%y: %y", wfid, stepid,
        #    exists WC{wfid});

        # NOTE: an exception can only be thrown here if a queue message is submitted for
        #       a non-existant step, which can only happen if the workflow has been
        #       illegally redefined using oload -A
        if (cached) {
            AbstractWorkflowQueue wq = SWD{wfid}.WC;
            wq.updateQueue(stepid, wfiid, ind, prio, corrected, queuekey, data, parent_info);
        }
    }

    hash<auto> retryWorkflowInstanceExtern(hash<auto> cx, softstring wfiid) {
        hash<auto> wh = getPriorityWorkflowIDAndParent(wfiid);
        return retryWorkflowInstanceIntern(cx, wfiid, wh);
    }

    hash<auto> retryWorkflowInstance(softstring wfiid) {
        # can be called from internal code without TLD when called from a remote interface
        ensure_create_tld();
        # temporarily erase all thread-local data and restore on exit
        ThreadLocalData td();
        td.tldCopy(tld);
        on_exit tld.tldCopy(td);
        tld.clear();

        hash<auto> wh = getPriorityWorkflowIDAndParent(wfiid);
        return retryWorkflowInstanceIntern(NOTHING, wfiid, wh);
    }

    private hash<auto> retryWorkflowInstanceIntern(*hash<auto> cx, string wfiid, hash<auto> wh) {
        QDBG_ASSERT(ensure_tld());
        QDBG_LOG("SegmentManagerBase::retryWorkfowInstanceIntern wfiid %y wh %y", wfiid, wh);
        # prohibits the workflow from being loaded or unloaded while in progress
        bool cached = block(wh.workflowid);
        on_exit unblock(wh.workflowid);

        # DEBUG
        #QDBG_LOG("SegmentManagerBase::retryWorkflowInstance(wfiid: %d) cached: %y", wfiid, cached);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD.(wh.workflowid);
            return swd.retryWorkflowOrder(cx, wfiid, wh);
        }

        return retryWorkflowInstanceSql(cx, wfiid, wh);
    }

    leaveFeedbackExtern(string wfiid, string key, auto value) {
        ensure_create_tld();
        leaveFeedback(wfiid, key, value);
    }

    leaveFeedback(string wfiid, string key, auto value) {
        string wfid = getWorkflowID(wfiid);
        QDBG_LOG("SegmentManagerBase::leaveFeedback wfiid: %y, key: %y, value: %y", wfiid, key, value);

        # prohibits the workflow from being loaded or unloaded while in progress
        bool cached = block(wfid);
        on_exit unblock(wfid);

        if (cached) {
            AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{wfid});
            swd.leaveFeedbackCached(wfiid, key, value);
            #leaveFeedbackCached(wfid, wfiid, key, value);
            return;
        }

        leaveFeedbackSql(wfid, wfiid, key, value);
    }

    hash blockWorkflowInstanceExtern(hash<auto> c, softstring wfiid, bool block, *hash<auto> tempdata,
            *hash<auto> new_keys) {
        create_tld();
        return blockWorkflowInstance(c, wfiid, block, tempdata, new_keys);
    }

    hash blockWorkflowInstance(hash<auto> c, softstring wfiid, bool block, *hash<auto> tempdata,
            *hash<auto> new_keys) {
        return handleWorkflowInstanceStatus(c, wfiid, OMQ::StatBlocked, block, tempdata, new_keys);
    }

    hash<auto> cancelWorkflowInstanceExtern(hash<auto> c, softstring wfiid, bool cancel, *hash<auto> tempdata) {
        create_tld();
        return cancelWorkflowInstance(c, wfiid, cancel, tempdata);
    }

    hash<auto> cancelWorkflowInstance(hash<auto> c, softstring wfiid, bool cancel, *hash<auto> tempdata) {
        return handleWorkflowInstanceStatus(c, wfiid, OMQ::StatCanceled, cancel, tempdata);
    }

    # SegmentManagerBase::createSynchronousWorkflowCommit()
    # returns on success:
    #    * workflow_instanceid
    string createSynchronousWorkflowRowCommit(hash<auto> cx, softstring wfid, *hash<auto> parent_info,
            OrderData order, string status) {
        string wfiid;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                wfiid = createSynchronousWorkflowRowNoCommit(wfid, order, status).toString();
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

        # emit system event for workflow creation
        Qorus.events.postWorkflowDataSubmitted(cx, order.getName(), order.getVersion(), wfid, wfiid, OMQ::StatInProgress,
            order.parent_workflow_instanceid, order.subworkflow);

        return wfiid;
    }

    # shared method to set StatCanceled and StatBlocked to reduce code duplication
    private hash<auto> handleWorkflowInstanceStatus(*hash<auto> cx, softstring wfiid, string stat, bool setOn,
        *hash<auto> tempdata, *hash<auto> new_keys) {
        QDBG_ASSERT(ensure_tld());
        QDBG_LOG("SegmentManager::handleWorkflowInstanceStatus() wfiid: %y stat: %y set: %y tempdata: %y", wfiid,
            stat, setOn, keys tempdata);
        string err = sprintf("%s-WORKFLOW-ERROR", stat == OMQ::StatCanceled ? "CANCEL" : "BLOCK");
        if (!wfiid) {
            throw err, "no workflow_instanceid given";
        }

        # determine workflowid and parent_workflow_instanceid
        hash<auto> wih = getPriorityWorkflowIDAndParent(wfiid);

        softstring wfid = wih.workflowid;

        # issue #3486: if the order is being executed synchronously, stop it first
        Qorus.control.stopSynchronous(cx, wfiid, (stat == OMQ::StatCanceled ? "cancel" : "block")
            + " order API call");

        # issue #1981: need to ensure tld is saved and restored and wf-specific tld is cleared for this call
        # to cover the case when a synchronous workflow has been executed on the same HTTP connection
        # which could also happen with an HTTP proxy reusing external connections
        TldClearHelper tch("index", "wfe", "wf");

        # DB info result
        hash<auto> q;
        {
            bool cached = block(wfid);
            on_exit unblock(wfid);

            if (cached) {
                QDBG_LOG("SegmentManager::handleWorkflowInstanceStatus() wfiid: %y wfid: %y cached", wfiid, wfid);
                AbstractSegmentWorkflowData swd = SWD{wfid};
                return swd.handleWorkflowInstanceStatus(cx, wfiid, stat, setOn, tempdata, new_keys, err, wih);
            }

            if (new_keys) {
                *hash<auto> wfh = Qorus.qmm.lookupWorkflow(wfid);
                if (!wfh) {
                    throw "INVALID-WORKFLOW", sprintf("workflowid %d has been deleted while processing an order keys "
                        "change request", wfid);
                }

                WFEntry::setOrderKeysStatic(wfid, wfiid, wfh.order_key_map, sqlif.getOrderKeysTrans(wfiid), new_keys,
                    False, (stat == OMQ::StatCanceled ? "cancel" : "block") + " order call");
            }

            #QDBG_LOG("handleWorkflowInstanceStatus raw db write at pos 02 for %s", wfiid);
            q = SegmentManagerBase::commitBlockOrCancelSql(cx, wfid, wfiid, stat, setOn, False);
        }

        return handleWorkflowInstanceStatusPrologue(wfid, wfiid, stat, setOn, q);
    }

    # returns True if a retry is needed, False if not (was async)
    bool skipStepWithoutRetry(hash<auto> cx, softstring wfiid, softstring stepid, softint ind = 0) {
        *hash<auto> stepinfo = Qorus.qmm.lookupStep(stepid);
        if (!exists stepinfo)
            throw "SKIP-STEP-ERROR", sprintf("stepid %d is not a valid step ID", stepid);

        bool swf = (stepinfo.steptype == OMQ::ExecSubWorkflow);

        softint priority;
        string wfid = getWorkflowID(wfiid, \priority);

        bool cached = block(wfid);
        on_exit unblock(wfid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            swd.skipStep(wfiid, stepid, ind, swf);
        } else {
            SegmentManagerBase::skipStepSQL(wfiid, stepid, ind, swf);
        }

        # call submitCorrected() for async steps
        if (stepinfo.steptype == OMQ::ExecAsync) {
            # insert/update queue data in the DB
            string key = sprintf("OMQ-SYS-%d-%d-%d", wfiid, stepid, ind);
            # if there are any errors, an exception will be thrown
            commitCorrectedQueueData(stepinfo.queueid, key, wfiid, stepid, ind);
            # if the WF is cached, then post the corrected async event on the queue
            # issue #3490: ensure that the workflow queue is in place before calling updateQueueUnlocked()
            if (cached && SWD{wfid}.WC) {
                updateQueueUnlocked(wfid, stepid, wfiid, ind, priority, True, key);
            }
            # no retry necessary
            return False;
        }

        # call updateSubWorkflowQueue() for subworkflow steps
        if (swf) {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    # create the updated workflow event msg on the queue
                    createSubWorkflowInstanceRowNoCommit(wfiid, stepid, ind, wfiid, 1);
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

            # if the WF is cached, then post the corrected subworkflow event on the queue
            if (cached) {
                updateSubWorkflowQueue(wfid, wfiid, stepid, ind, priority, wfiid);
            }
            # no retry necessary
            return False;
        }

        # if the WF is cached, then call postSyncEvent() for synchronization event steps
        if (cached && stepinfo.steptype == OMQ::ExecEvent) {
            postSyncEventIntern(wfid, stepid, wfiid, ind, priority);
            return False;
        }

        # otherwise do an immediate retry
        return True;
    }

    skipStep(hash<auto> cx, softstring wfiid, softstring stepid, softint ind = 0) {
        if (skipStepWithoutRetry(cx, wfiid, stepid, ind))
            retryWorkflowInstance(wfiid);
    }

    # from 'X' (CANCELED)
    hash<auto> setWorkflowInstanceError(hash<auto> cx, softstring wfiid) {
        string wfid = getWorkflowID(wfiid);

        # issue #3486: if the order is being executed synchronously, stop it first
        Qorus.control.stopSynchronous(cx, wfiid, "set order ERROR status API call");

        bool cached = block(wfid);
        on_exit unblock(wfid);

        hash rv;
        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            rv = swd.setErrorDeleteAndRequeueEvents(cx, wfiid);
        } else {
            rv = setErrorSql(cx, wfid, wfiid);
        }

        return rv;
    }

     hash<auto> setOrderKeysExtern(*hash<auto> cx, softint wfiid, hash new_keys, bool truncate, *softint wfid,
            *hash<auto> order_keys) {
        if (!wfid)
            wfid = getWorkflowID(wfiid);

        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            return swd.setOrderKeys(wfiid, new_keys, truncate, order_keys);
        }

        return setOrderKeysSql(wfid, wfiid, new_keys, truncate, order_keys);
    }

    lockOrder(hash<auto> wfih, string note) {
        on_success
            Qorus.events.postWorkflowDataLocked(tld.cx, wfih.name, wfih.version, wfih.workflowid,
                wfih.workflow_instanceid, note);

        bool cached = block(wfih.workflowid);
        on_exit unblock(wfih.workflowid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD.(wfih.workflowid);
            swd.lockOrder("system", wfih.workflow_instanceid, note);
        } else {
            lockOrderSql(wfih.workflow_instanceid, note);
        }
    }

    unlockOrder(hash<auto> wfih, string note) {
        on_success
            Qorus.events.postWorkflowDataUnlocked(tld.cx, wfih.name, wfih.version, wfih.workflowid,
                wfih.workflow_instanceid, note);

        bool cached = block(wfih.workflowid);
        on_exit unblock(wfih.workflowid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD.(wfih.workflowid);
            swd.unlockOrder("system", wfih.workflow_instanceid, note);
        } else {
            unlockOrderSql(wfih.workflow_instanceid, note);
        }
    }

    breakOrderLock(hash<auto> wfih, string note) {
        on_success
            Qorus.events.postWorkflowDataUnlocked(tld.cx, wfih.name, wfih.version, wfih.workflowid,
                wfih.workflow_instanceid, note);

        bool cached = block(wfih.workflowid);
        on_exit unblock(wfih.workflowid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD.(wfih.workflowid);
            swd.breakOrderLock(wfih.workflow_instanceid, note);
        } else {
            breakOrderLockSql(wfih.workflow_instanceid, note);
        }
    }

    # returns True if the lock was broken, False if not
    bool breakStepLock(hash<auto> wfih, softstring stepid, softint ind, string user, string note) {
        bool cached = block(wfih.workflowid);
        on_exit unblock(wfih.workflowid);

        note = sprintf("user %y stepid %d[%d]: %s", user, stepid, ind, note);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD.(wfih.workflowid);
            return swd.breakStepLock(wfih.workflow_instanceid, stepid, ind, note);
        } else {
            return breakStepLockSql(wfih.workflow_instanceid, stepid, ind, note);
        }
    }

    setOrderInstanceNote(*hash<auto> cx, softint wfiid, hash<auto> info) {
        string wfid = getWorkflowID(wfiid);

        my (string name, string version);

        {
            bool cached = blockRead(wfid);
            on_exit unblockRead(wfid);

            if (cached) {
                AbstractSegmentWorkflowData swd = SWD{wfid};
                name = swd.wf.name;
                version = swd.wf.version;
                info = swd.addOrderNote(wfiid, info);
            } else {
                info = OMQ::OrderInstanceNotes::addSave(wfiid, info);
                hash wf = Qorus.qmm.lookupWorkflow(wfid);
                name = wf.name;
                version = wf.version;
            }
        }

        Qorus.events.postWorkflowInfoChanged(cx, name, version, wfid, wfiid, info);
    }

    list<auto> getOrderInstanceNotes(softint wfiid, *int count) {
        string wfid = getWorkflowID(wfiid);

        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        list<auto> notes;

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            notes = swd.getNotes(wfiid);
        } else {
            notes = OMQ::OrderInstanceNotes::getNotes(wfiid);
        }

        # if we have no notes (an empty list), return it
        if (!notes)
            return notes;

        return count ? extract notes, -count : notes;
    }

    rescheduleWorkflowExtern(hash<auto> cx, softint wfiid, *date scheduled) {
        string wfid = getWorkflowID(wfiid);

        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            swd.rescheduleOrder(wfiid, scheduled);
        }
        else {
            rescheduleOrderSql(wfiid, scheduled);
        }
    }

    reprioritizeWorkflowExtern(hash<auto> cx, softint wfiid, int prio) {
        string wfid = getWorkflowID(wfiid);

        if (prio < 0)
            prio = 0;
        else if (prio > 999)
            prio = 999;

        bool cached = blockRead(wfid);
        on_exit unblockRead(wfid);

        if (cached) {
            AbstractSegmentWorkflowData swd = SWD{wfid};
            swd.reprioritizeOrder(wfiid, prio);
        }else {
            reprioritizeOrderSql(wfiid, prio);
        }
    }

    # this thread will wake up and process cache expirations as necessary
    private cacheThread() {
        create_tld();
        # DEBUG
        #QDBG_LOG("DEBUG: SM::cacheThread() tid %d starting, TWC: %s", gettid(), TWC.getSummary());

        on_exit cCount.dec();

        while (True) {
            *hash<auto> msg = TWC.getEvent();

            if (!msg)
                break;

            # do not allow the cacheThread() to exit with an exception, log and try to continue
            # otherwise workflow data may be left unflushed
            try {
                bool cached = block(msg.wfid);
                on_exit unblock(msg.wfid);

                if (cached) {
                    AbstractSegmentWorkflowData swd = SWD.(msg.wfid);

                    swd.writeLock();
                    on_exit swd.writeUnlock();

                    *WFEntry wfe = getWFEntryUnlocked(swd, msg.wfiid);

                    if (wfe && !wfe.refs) {
                        #QDBG_LOG("cache entry expired for wfiid %d wfid %d", msg.wfiid, msg.wfid);
                        wfe.flushStatus();
                        wdata.del(msg.wfiid);
                    }
                }
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::FATAL, "exception in SegmentManagerBase::cacheThread(): %s: %s: %s", get_ex_pos(ex),
                    ex.err, ex.desc);
            }
        }
        # DEBUG
        #QDBG_LOG("DEBUG: SM::cacheThread() tid %d exiting", gettid());
    }

    # must be called in the write lock
    private waitForWorkflowIntern(softstring wfid) {
        while (True) {
            while (SWD{wfid} && (AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{wfid})) && swd.RC) {
                Counter c = swd.RC;
                rwl.writeUnlock();
                c.waitForZero();
                rwl.writeLock();
            }

            bool exit = True;

            # check for a temporary block
            while (BC{wfid}.cond) {
                # check restart counter if we have to wait for a block
                exit = False;
                BC{wfid}.cond.wait(rwl);
            }

            if (exit) {
                break;
            }
        }
    }

    # called when a workflow is paused to ensure that the queue data is maintained while workflow exec instances are stopped
    bool referenceWorkflowQueue(softstring wfid) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        waitForWorkflowIntern(wfid);

        if (SWD{wfid}) {
            SWD{wfid}.ref(True, False);
            return True;
        }
        return False;
    }

    registerWorkflow(Workflow wf, bool qref, bool temp) {
        # remove any temporary wf logger on exit, in case it's still present
        on_exit wf.takeTemporaryLogger();

        # id = workflows.workflowid
        softstring id = wf.workflowid;

        {
            bool lck = !rwl.writeLockOwner();
            if (lck)
                rwl.writeLock();
            on_exit if (lck) rwl.writeUnlock();

            waitForWorkflowIntern(id);

            # create cache objects if necessary
            if (!SWD{id}) {
                # increment the workflow count
                wCount.inc();

                on_error
                    wCount.dec();

                SWD{id} = getSegmentWorkflowData(wf, qref, temp);
            } else {
                # increment reference count
                SWD{id}.ref(qref, temp);
            }
        }
    }

    *list<hash<auto>> getRecoveryInfo(string wfid) {
        QDBG_ASSERT(SWD{wfid} instanceof RemoteSegmentWorkflowData);
        return cast<RemoteSegmentWorkflowData>(SWD{wfid}).getRecoveryInfo();
    }

    # cannot be private, also called from the WFEntry class
    callDetachIntern(WorkflowExecutionInstance wi, string status, *softstring eoiid) {
        # bug 612: make sure and delete any "steperror" key in thread-local data when exiting
        QDBG_ASSERT(ensure_tld());
        on_exit { tld.stepError = NOTHING; }
        try {
            # ensure the workflow's source code has been cached and call the detach handler
            wi.wf.callDetach(status, eoiid);
        } catch (hash<ExceptionInfo> ex) {
            # log error
            wi.wf.logInfo("exception in \"detach\" handler %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            Qorus.logInfo(Util::get_exception_string(ex));
            # create an error_instance entry
            wi.stepError(ex.err, ex.desc);
        }
    }

    # called in the write lock
    private *bool derefWorkflowIntern(string id, bool qref, bool temp, *bool from_qwf) {
        QDBG_LOG("SegmentManager::derefWorkflowIntern(id: %s qref: %y temp: %y)", id, qref, temp);
        #QDBG_LOG("stack: %N", get_stack());
        # issue #2436: this call can be made interally with no TLD but must have TLD
        ensure_create_tld();

        AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{id});

        on_exit {
            if (swd.canDelete()) {
                return derefPostProcess(id, from_qwf);
            }
        }

        if (swd.deref(qref, temp)) {
            # purge all cached orders for the given workflow to the DB
            purgeOrders(id);
        }
    }

    # called in the write lock
    private *bool derefPostProcess(string id, *bool from_qwf) {
        QDBG_LOG("SegmentManager::derefPostProcess() processing wch id: %d", id);
        QDBG_ASSERT(wch{id});
        wch{id}.dec();
        QDBG_ASSERT(!wch{id}.getCount());
        # do not delete the counter, but remove it from the hash
        remove wch{id};

        # delete the segment workflow data object
        if (from_qwf) {
            SWD{id}.setDetachedStop();
        }
        delete SWD{id};

        # decrement the workflow count
        wCount.dec();

        return from_qwf;
    }

    private purgeOrdersIntern(string wfid, list fl) {
        if (SWD{wfid}.blockForDelete(rwl)) {
            on_exit SWD{wfid}.blockDeref();

            # run purge with write lock released
            #qlog(LoggerLevel::FATAL, "purging workflow %s v%s (%d) data (orders: %d) UNLOCKED", SWD{id}.wf.name,
            #   SWD{id}.wf.version, id, fl.size());

            rwl.writeUnlock();
            on_exit rwl.writeLock();

            WFEntryCache::flushAndDelete(fl);
        } else {
            WFEntryCache::flushAndDelete(fl);
        }
    }

    derefRestartWorkflow(softstring id) {
        QDBG_LOG("SegmentManager::derefRestartWorkflow() id: %d", id);
        bool lck = !rwl.writeLockOwner();
        if (lck) rwl.writeLock();
        on_exit if (lck) rwl.writeUnlock();

        try {
            cast<AbstractCoreSegmentWorkflowData>(SWD{id}).derefWaitRestart(rwl);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CLIENT-DEAD" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED") {
                qlog(LoggerLevel::INFO, "ignoring qwf process abort in reset: %s: %s: %s", get_ex_pos(ex), ex.err,
                    ex.desc);
            } else {
                rethrow;
            }
        }
        # purge all cached orders for the given workflow to the DB
        purgeOrders(id);

        QDBG_LOG("SegmentManager::derefRestartWorkflow() starting post processing for id: %d", id);
        derefPostProcess(id);
    }

    *bool derefWorkflow(softstring id, bool qref, bool temp, *bool from_qwf) {
        bool lck = !rwl.writeLockOwner();
        if (lck) rwl.writeLock();
        on_exit if (lck) rwl.writeUnlock();

        return derefWorkflowIntern(id, qref, temp, from_qwf);
    }

    # issue #3668: returns True if the AbstractCoreSegmentWorkflowData stop counter was set
    *bool stopWorkflow(softstring id) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (SWD{id}) {
            AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{id});

            # tell WorkflowQueue cache to stop caching workflow data in case it's in progres s
            # and create the restart counter
            swd.startStopWorkflow();
            return True;
        }
    }

    # issue #3668: decrement the stop counter if no workflow exec instances were stopped after calling stopWorkflow()
    # and setting the stop counter
    stopAborted(softstring wfid) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (SWD{wfid} && (AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{wfid})) && swd.RC) {
            QDBG_ASSERT(swd.RC.getCount() == 1);
            swd.signalRestart();
        }
    }

    # prohibits a workflow from being loaded or unloaded until
    # SegmentManagerBase::unblock() is called (thread-safe/recursive)
    # returns True if cached, False if not
    bool block(softstring id) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        # if the workflow is loaded, prevents it from being unloaded
        if (SWD{id}) {
            AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{id});
            if (swd.blockRef(rwl))
                return True;
        }

        # if the workflow is not loaded, this prevents it from being loaded
        ++BC{id}.ref;
        if (!BC{id}.cond)
            BC{id}.cond = new Condition();

        return False;
    }

    # enables a workflow to be loaded or unloaded (thread-safe/recursive)
    unblock(softstring id) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (SWD{id}) {
            SWD{id}.blockDeref();
            derefWorkflowIntern(id, False, False);
            return;
        }

        if (!--BC{id}.ref) {
            BC{id}.cond.broadcast();
            delete BC{id};
        }
    }

    # prohibits a workflow from being loaded or unloaded until
    # SegmentManagerBase::unblockRead() is called
    # returns True if cached, False if not
    # if the workflow is loaded, the read lock is grabbed as well
    bool blockRead(softstring id) {
        AutoWriteLock awl(rwl);

        # if the workflow is loaded, prevents it from being unloaded
        if (SWD{id}) {
            AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{id});
            if (swd.blockRef(rwl)) {
                delete awl;
                swd.readLock();

                return True;
            }
        }

        # if the workflow is not loaded, this prevents it from being loaded
        ++BC{id}.ref;
        if (!BC{id}.cond)
            BC{id}.cond = new Condition();

        return False;
    }

    # enables a workflow to be loaded or unloaded
    # if the workflow is loaded, the read lock is released as well
    unblockRead(softstring id) {
        if (SWD{id}) {
            AbstractCoreSegmentWorkflowData swd = cast<AbstractCoreSegmentWorkflowData>(SWD{id});
            swd.readUnlock();

            rwl.writeLock();
            on_exit rwl.writeUnlock();

            swd.blockDeref();
            derefWorkflowIntern(id, False, False);

            return;
        }

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (!--BC{id}.ref) {
            BC{id}.cond.broadcast();
            delete BC{id};
        }
    }
}
