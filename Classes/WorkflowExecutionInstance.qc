# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus WorkflowExecutionInstance class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

public namespace OMQ;

const OMQ::WSC_NONE  = 0;
const OMQ::WSC_STOP  = 1;
const OMQ::WSC_RESET = 2;

class OMQ::TldHelper {
    private {
        *list<softstring> keyNames;
        *hash<auto> otld;
    }

    constructor() {
        keyNames = argv;
        otld = tld{argv};
    }

    constructor(softlist<softstring> args) {
        keyNames = args;
        otld = tld{args};
    }

    destructor() {
        tld += otld;
        map remove tld.$1, keyNames, !exists otld.$1;
    }

    auto getOldValue(string key) {
        return otld{key};
    }
}

class OMQ::TldClearHelper inherits TldHelper {
    # issue #2647: restore the index_map on exit, but do not clear it
    constructor() : TldHelper(argv + "index_map") {
        tld -= argv;
    }
}

class OMQ::WorkflowExecutionInstance inherits AbstractWorkflowExecutionInstance {
    private {
        # workflow execution instance stop code
        int stop = WSC_NONE;

        Mutex mStatus();
        int scount = 1;
        Counter cSegment();

        # stays for the life of the workflow instance
        InstanceData instancedata();

        # atomic stop variables
        Mutex mStop();

        # started flag
        bool started = False;
        bool exiting = False;
        bool fatal_error = False;

        # stop warning
        bool stop_warn = False;

        # registered with SegmentManager counter
        Counter setup(1);
    }

    public {
        string name;
        string version;
        string status       = OMQ::WISInitializing;

        # start reason for auditing and logging
        ActionReason startreason;

        # stop reason for auditing and logging
        ActionReason stopreason();
    }

    constructor(softstring index, *int sync_wfiid, string mode, Workflow wf, *hash<auto> cx, *string reason)
            : AbstractWorkflowExecutionInstance(index, sync_wfiid, mode, wf) {
        QDBG_ASSERT(ensure_tld());
        name    = wf.name;
        version = wf.version;

        QDBG_LOG("WorkflowExecutionInstance::constructor index = %y name = %y", index, name);

        startreason = new ActionReason(cx, reason);

        if (sync_wfiid) {
            started = True;
        }
    }

    /*
    destructor() {
    }
    */

    ActionReason getStopReason() {
        return stopreason;
    }

    int usleep(date us) {
        return usleep(us.durationMicroseconds());
    }

    int usleep(softint us) {
        if (stop_warn)
            throw "STOP-ERROR", "omqsleep() or omqusleep() called twice after workflow execution instance is in stop state";

        while (!stop && us > 0) {
            Qore::usleep(us > 1000000 ? 1000000 : us);
            us -= 1000000;
        }
        if (stop) {
            stop_warn = True;
            return -1;
        }
        return 0;
    }

    int getStop() {
        return stop;
    }

    private error() {
    }

    private warning() {
    }

    # do nothing in the default implementation
    private waitSignalReset() {
    }

    # do nothing in the default implementation
    private signalReset() {
    }

    # do nothing in the default implementation
    private bool doReset() {
        return False;
    }

    int inlineInit() {
        QDBG_ASSERT(ensure_tld());
        # save primary thread data & restore thread data on exit
        TldHelper tldh("index");
        tld += (
            "index": index,
        );

        int rc = init();
        # also notify that workflow setup failed to avoid race conditions with resets and stops
        if (rc) {
            setup.dec();
        }

        return rc;
    }

    int setupTemp() {
        QDBG_ASSERT(ensure_tld());
        QDBG_LOG("WorkflowExecutionInstance::setupTemp() index %y -> %y", tld.index, index);
        # set local execution instance
        tld.index = index;

        return init(True);
    }

    start() {
        QDBG_ASSERT(ensure_tld());
        QDBG_LOG("WorkflowExecutionInstance::start() index: %y started: %y, setting to True", index, started);
        started = True;

        # save primary thread data
        QDBG_LOG("WorkflowExecutionInstance::start() index %y -> %y", tld.index, index);
        # restore thread data on exit
        TldHelper tldh("index");
        tld += {
            "index": index,
        };

        logInfo("starting %s workflow in %s mode, workflowid %d; %s", wf.remote ? "remote" : "local", mode, wf.workflowid, startreason.getText());

        QDBG_LOG("WorkflowExecutionInstance::start() about to startWorkflow()");
        background startWorkflow();
    }

    # logging in this wf instance's log file
    logInfo(string msg) {
        wf.logInfo(vsprintf(msg, argv));
    }

    # logging in this wf instance's log file
    logFatal(string msg) {
        wf.logFatal(vsprintf(msg, argv));
    }

    # logging in this wf instance's log file
    logDebug(string msg) {
        wf.logDebug(vsprintf(msg, argv));
    }

    hash<auto> getAllOptions() {
        return wf.getAllOptions();
    }

    auto getOption(string f) {
        return wf.getOption(f);
    }

    auto getOption(*softlist<auto> field) {
        return wf.getOption(field);
    }

    setOption(hash<auto> h) {
        wf.setOption(h);
    }

    private int init(bool tmp = False) {
        QDBG_ASSERT(ensure_tld());
        QDBG_LOG("WorkflowExecutionInstance::init() index = %y", index);

        tld.wf = wf;
        tld.mode = mode;

        on_error
            tld -= ("wf", "mode");

        int rv = tmp ? 0 : oneTimeInitialization();

        return rv;
    }

    private int oneTimeInitialization() {
        QDBG_ASSERT(ensure_tld());
        # execute one-time initialization logic for workflow if available
        #printf("onetimeinit: %y\n", wf.hasOneTimeInit());
        if (wf.hasOneTimeInit()) {
            logInfo("executing one time initialization logic");
            tld.inOneTimeInit = True;
            on_exit remove tld.inOneTimeInit;
            try {
                wf.callOneTimeInit();
                if (fatal_error) {
                    return -1;
                }
                if (tld.stepError) {
                    stopreason.set("Qorus", "FATAL-WORKFLOW-ERROR", sprintf("%s: %s", tld.stepError.err, tld.stepError.desc), True);
                    remove tld.stepError;
                    return -1;
                }
            } catch (hash<ExceptionInfo> ex) {
                string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                workflowError("QORE-EXCEPTION", err);
                logInfo("%s v%s (%d): ERROR in onetimeinitialization: %s; the workflow could not be started", name, version, wf.workflowid, err);
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
                setFatalError(ex);
                remove tld.stepError;
                return -1;
            }
        }
        return 0;
    }

    private startWorkflow() {
        create_tld();
        # save primary thread data
        QDBG_LOG("WorkflowExecutionInstance::startWorkflow %y index %y -> %y", name, tld.index, index);
        tld += {
            "wf": wf,
            "index": index,
            "_current_ix": "wf",
        };
%ifdef QorusCore
        # issue #3319: set interface context; at runtime only necessary for qorus-core
        WorkflowContextHelper ixctx();
%endif
        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        # execute workflow
        while (True) {
            try {
                exec();
            } catch (hash<ExceptionInfo> ex) { # handle any uncaught exceptions
                # fix for bug 443: do not roll back transaction in catch block - rollbacks must be handled in tandem with each commit
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
                string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                workflowError("QORE-EXCEPTION", err);
                setFatalError(ex);
                status = OMQ::WISStopping;
                break;
            }

            # wait for all threads to stop
            cSegment.waitForZero();

            # if the workflow is exiting for a reason other than
            # a message on the exit queue, then break
            {
                AutoLock al(mStop);

                if (stop == WSC_NONE) {
                    exiting = True;
                    break;
                }

                # see if workflow configuration was reset
                if (stop == WSC_STOP) {
                    al.unlock();
                    logInfo("workflow exit message received, halting workflow");
                    # signal reset done if necessary
                    waitSignalReset();
                    break;
                }
            }

            QDBG_ASSERT(stop == WSC_RESET);
            if (doReset()) {
                break;
            }
        }

        # in case of an exception, check again that all threads have stopped
        cSegment.waitForZero();

        stopAndCleanup();
    }

    private *ErrorDef getError(string err) {
        return Qorus.getError(wf.workflowid, err);
    }

    private abstract workflowStopped();

    abstract *int auditUserEvent(string user_event, *string info1, *string info2);
}

OMQ::WorkflowExecutionInstance::setupComplete() {
    setup.dec();
}

OMQ::WorkflowExecutionInstance::setupError(hash<auto> ex) {
    stop = WSC_STOP;
    exiting = True;
    setup.dec();

    string err = Qorus.getDebugSystem() ? get_exception_string(ex) : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err,
        ex.desc);
    logInfo("FATAL-WORKFLOW-ERROR: setup error: %s", err);
    stopreason.set("Qorus", "FATAL-WORKFLOW-ERROR", err, True);
}

private OMQ::WorkflowExecutionInstance::stopAndCleanup() {
    logInfo("stopped %s workflow %s v%s (%d) ID %s; %s", wf.remote ? "remote" : "local", name, version, wf.workflowid,
        index, stopreason.getText());

    # start stop actions
    workflowStopped();
}

OMQ::WorkflowExecutionInstance::setFatalError(hash<auto> ex) {
    fatal_error = True;

    string err = Qorus.getDebugSystem() ? get_exception_string(ex) : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err,
        ex.desc);
    stopreason.set("Qorus", "FATAL-WORKFLOW-ERROR", err, True);

    # do not try to stop workflow if it hasn't been started yet
    if (!tld.inOneTimeInit)
        setStop();
}

hash<auto> OMQ::WorkflowExecutionInstance::execSynchronousOnExistingOrder(hash<auto> cx) {
    stopreason.set(cx, "synchronous workflow processing complete");

    # cache workflow
    QDBG_LOG("WorkflowExecutionInstance::execSynchronousOnExistingOrder wfid = %y wfiid = %y", wf.workflowid,
        sync_wfiid);
    return execSynchronous();
}

hash<auto> OMQ::WorkflowExecutionInstance::execSynchronousOrderCreated() {
    return execSynchronous();
}

# this method actually returns a hash, but in an on_success block
*hash<auto> OMQ::WorkflowExecutionInstance::execSynchronous() {
    QDBG_ASSERT(started);
    QDBG_ASSERT(ensure_tld());
    # ensure the order is cached
    SM.cacheReadyWorkflowSynchronous(wf.workflowid.toString(), sync_wfiid);

    WFEntry wfe = SM.getWorkflowEntry(sync_wfiid);
    tld += {
        "wf": wf,
        "sync": sync_wfiid,
        "wfe": wfe,
        "mode": OMQ::WM_Normal,
        "_current_ix": "wf",
    };

    QDBG_LOG("WorkflowExecutionInstance::execSynchronous wfiid = %y", sync_wfiid);
    # log message to system and workflow log files
    {
        string msg = sprintf("executing SYNCHRONOUS workflow order instance %d, workflowid %d, "
            "workflow options: %y; %s", sync_wfiid, wf.workflowid, wf.getOption(), startreason.getText());
        wf.logInfo(msg);
        olog(LoggerLevel::INFO, msg);
    }

    *string stat;

    SM.registerSynchronousWorkflow(wf.workflowid, sync_wfiid);

    {
        # "on_exit", "on_success", "on_error" blocks are executed in reverse order
        *hash dd;
        *hash eh;
        on_success {
            # use += here to maintain "hash<auto>" for "rv"
            hash<auto> rv += (
                "workflow_instanceid": sync_wfiid.toString(),
                "status": stat,
                "dynamicdata": dd,
            );
            if (stat == OMQ::StatError && eh) {
                rv.error = eh.("error", "description", "info");
            }
            return rv;
        }

        on_exit {
            SM.deregisterSynchronousWorkflow(wf.workflowid, sync_wfiid);
            cleanupSynchronous();
            logSynchronousComplete(stat);
        }
        on_success
            setStop();
        on_exit {
            # wait for all threads to stop
            QDBG_LOG("WorkflowExecutionInstance::execSynchronous waiting for counter: count %y waiting %y", cSegment.getCount(), cSegment.getWaiting());
            cSegment.waitForZero();
            dd = wfe.ddata.get();
            # issue 1605: unset the synced flag on the cached data first
            # otherwise the workflow may get deregistered and then an event may
            # be received before the order data is purged from the cache,
            # and errors will occur when the system tries to update synchronous
            # queues that no longer exist
            wfe.clearSynchronousFlag();
            # issue #3966: make sure we get a status here in all cases
            stat = SM.releaseWorkflowInstance(wf.workflowid, sync_wfiid, NOTHING, \eh) ?? wfe.getOnlineOrderStatus();
        }
        try {
            # start detached synchronous normal segments
            for (int i = 0; i < elements wf.segment; ++i) {
                # skip segments that are already complete
                if (wfe.seg[i].status == OMQ::StatComplete)
                    continue;

                # start normal segment if it has not started yet
                if (i && !wfe.seg[i].status) {
                    cSegment.inc();
                    background startNormalSynchronousSegment(i);
                }

                # start recovery segment
                cSegment.inc();
                background startSynchronousRecoverySegment(i);
            }

            # do not start segment 0 normal execution if there is already a status
            # in this case, it must be recovered
            if (wfe.seg[0].status)
                return;

            stat = execInitialSegment(); # execute initial segment(s)

            # stop recovery thread if segment is complete
            if (stat == OMQ::StatComplete)
                SM.terminateRetryConnection(index, wf.workflowid, "0", sync_wfiid);
            else if (inlist(stat, (OMQ::StatError, OMQ::StatBlocked, OMQ::StatScheduled)))
                setStop();
        } catch (hash<ExceptionInfo> ex) {
            setFatalError(ex);
        }
    }
}

private OMQ::WorkflowExecutionInstance::logSynchronousComplete(*string stat) {
    if (stat) {
        olog(LoggerLevel::INFO, "synchronous workflow %s/%s (id %d) for workflow_instanceid %d completed with "
            "status '%s' (%s); %s", name, version, index, sync_wfiid, OMQ::StatMap{stat}, stat,
            stopreason.getText());
        logInfo("synchronous workflow exiting with status '%s' (%s); %s", OMQ::StatMap{stat}, stat,
            stopreason.getText());
    } else {
        # issue #3966: this should only happen when there is an error
        olog(LoggerLevel::INFO, "synchronous workflow %s/%s (id %d) for workflow_instanceid %d exiting early without "
            "a final status; %s", name, version, index, sync_wfiid, stopreason.getText());
        logInfo("synchronous workflow exiting early without a final status; %s", stopreason.getText());
    }
}

private OMQ::WorkflowExecutionInstance::cleanupSynchronous() {
    QDBG_LOG("WorkflowExecutionInstance::cleanupSynchronous wfiid = %y", sync_wfiid);
    # unset synchronous flag on workflow instance
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            sqlif.workflowInstanceCleanupSynchronous(sync_wfiid);
            QDBG_TEST_CLUSTER_FAILOVER();
        } catch (hash<ExceptionInfo> ex) {
            # restart the transaction if necessary
            if (trans.restartTransaction(ex))
                continue;

            logFatal("exception resetting synchronous flag on workflow: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);

            if (Qorus.getDebugSystem())
                logFatal(get_exception_string(ex));
        }
        trans.reset();
        break;
    }

    # fix for bug 367: make sure the workflow reset only happens when the synchronous workflow is finished processing
    waitSignalReset();
}

private int OMQ::WorkflowExecutionInstance::checkStop() {
    mStop.lock();
    on_exit mStop.unlock();
    if (sync_wfiid && stop == WSC_RESET)
        return WSC_NONE;
    return stop;
}

*int OMQ::WorkflowExecutionInstance::setStop(*hash<auto> cx, *string reason) {
    QDBG_LOG("WorkflowExecutionInstance::setStop() index: %y stop: %y exiting: %y started: %y sync_wfiid: %y "
        "is_sync: %y (reason: %y)", index, stop, exiting, started, sync_wfiid, is_sync, reason);
    # fix for bug 474: wait for registration with the SegmentManager before processing status changes
    setup.waitForZero();

    *int rc;
    mStop.lock();
    on_exit mStop.unlock();

    if (stop != WSC_STOP && !exiting && started) {
        if (sync_wfiid) {
            SM.terminateSynchronousConnections(wf.workflowid, index, sync_wfiid);
        } else if (stop == WSC_NONE) { # if a reset is not in progress then terminate all waiting threads
            SM.terminateConnections(wf.workflowid, index);
        }
        stop = WSC_STOP;
        stopreason.set(cx, reason);
    } else {
        QDBG_LOG("WorkflowExecutionInstance::setStop() index: %y stop: %y (WSC_STOP = 1) exiting: %y started: %y "
            "returning -1", index, stop, exiting, started);
        rc = -1;
    }

    exiting = True;

    return rc;
}

private OMQ::WorkflowExecutionInstance::setRunning() {
    QDBG_LOG("WorkflowExecutionInstance::setRunning index = %y", index);
    mStatus.lock();
    on_exit mStatus.unlock();

    if (status == OMQ::WISStopping)
        return;

    status = OMQ::WISRunning;
    ++scount;
}

private OMQ::WorkflowExecutionInstance::setWaiting() {
    QDBG_LOG("WorkflowExecutionInstance::setWaiting index = %y", index);
    mStatus.lock();
    on_exit mStatus.unlock();

    if (status == OMQ::WISStopping)
        return;
    if (--scount <= 0) {
        status = OMQ::WISWaiting;
        scount = 0;
    }
}

*hash OMQ::WorkflowExecutionInstance::getErrorInfo(string err) {
    *ErrorDef eh = Qorus.getError(wf.workflowid, err);
    return eh ? eh.getCompatHash() : NOTHING;
}

# meant for exception objects
*string OMQ::WorkflowExecutionInstance::stepError(object err) {
    # first cover Java exceptions
    if (err.hasCallableMethod("getClass")) {
        auto v = err.getClass();
        if (v.typeCode() == NT_OBJECT) {
            if (v.hasCallableMethod("getName")) {
                string errstr = v.getName();
                return stepError(errstr, "exception object", err);
            }
        }
    }
    return stepError("EXCEPTION-OBJECT", "unknown exception object", err);
}

*string OMQ::WorkflowExecutionInstance::stepError(*softstring err, auto info, auto arg) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::stepError index: %y err: %y info: %y arg: %y", index, err, info, arg);
    # clear retryDelay value
    remove tld.retryDelay;

    *string severity;
    *string desc;
    *string etxt;
    *string status;
    bool business;

    # issue #2305 if the info arg exists and is not a string, then convert it to a string
    if (exists info && info.typeCode() != NT_STRING) {
        info = sprintf("%y", info);
    }

    *ErrorDef eh;
    if (err) {
        eh = Qorus.getError(wf.workflowid, err);
    }
    if (!eh && arg.typeCode() == NT_HASH && arg.alterr.typeCode() == NT_STRING && arg.alterr.val()) {
        eh = Qorus.getError(wf.workflowid, arg.alterr);
    }

    if (eh) {
        # increment error/warning count if necessary
        if (eh.severity != OMQ::ES_Info) {
            if (eh.severity == OMQ::ES_Warning)
                warning();
            else
                error();
        }

        etxt = eh.description;
        if (info)
            etxt += sprintf(": %y", info);

        severity = eh.severity;
        desc = eh.description;
        status = eh.status;
        business = eh.business_flag;
        if (exists eh.retry_delay_secs)
            WorkflowApi::setRetryDelay(eh.retry_delay_secs);
    } else {
        if (!err)
            err = "UNKNOWN-ERROR";

        # assume ES_Major severity, ERROR status
        error();
        etxt = info;
        severity = OMQ::ES_Major;
        status = OMQ::StatError;
    }

    # save error in WFEntry object
    *int eeid = log_error(err, desc, info, severity, status, business);
    *WFEntry wfe = tld.wfe;
    if (wfe)
        wfe.addError(severity, err, desc, info, status, business, eeid);

    checkSeverity(severity, \status, err, desc);
    logInfo("%s ERROR: %s: %s", severity, err, etxt);
    if (severity == OMQ::ES_Fatal)
        olog(LoggerLevel::FATAL, "%s/%s(%d) FATAL ERROR: %s: %s", name, version, index, err, etxt);

    wf.callErrorHandler(err, eh ? eh.getCompatHash() : NOTHING, info);
    return status;
}

OMQ::WorkflowExecutionInstance::stepException(string err, string desc, auto info) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::stepException index = %y err = %y desc = %y", index, err, desc);
    # clear retryDelay value
    remove tld.retryDelay;

    string severity = OMQ::ES_Fatal;
    string status = OMQ::StatError;

    # assume ES_Major severity, ERROR status
    error();

    *int eeid = log_error(err, desc, info, severity);
    *WFEntry wfe = tld.wfe;
    if (wfe)
        wfe.addError(severity, err, desc, info, status, NOTHING, eeid);

    checkSeverity(severity, \status, err, desc);
    # force status to ERROR
    status = OMQ::StatError;

    logInfo("%s ERROR: %s: %s", severity, err, desc);
    if (severity == OMQ::ES_Fatal) {
        if (exists info)
            olog(LoggerLevel::FATAL, "%s/%s(%d) FATAL ERROR: %s: %s (%s)", name, version, index, err, desc, info);
        else
            olog(LoggerLevel::FATAL, "%s/%s(%d) FATAL ERROR: %s: %s", name, version, index, err, desc);
    }

    *ErrorDef eh = Qorus.getError(wf.workflowid, err);
    wf.callErrorHandler(err, eh ? eh.getCompatHash() : NOTHING, info);
}

# maybe should remove this function
OMQ::WorkflowExecutionInstance::stepWarning(*string err, auto info) {
    QDBG_LOG("WorkflowExecutionInstance::stepWarning index = %y err = %y info = %y", index, err, info);
    warning();

    *ErrorDef eh;
    if (err)
        eh = Qorus.getError(wf.workflowid, err);

    # log error to OMQ DB
    *int eeid = log_error(err, eh ? eh.description : NOTHING, info, OMQ::ES_Warning);
    *WFEntry wfe = tld.wfe;
    if (wfe)
        wfe.addError(OMQ::ES_Warning, err, eh ? eh.description : NOTHING, info, NOTHING, NOTHING, eeid);

    if (eh.description)
        err += ": " + eh.description;

    if (info)
        logInfo("WARNING: %s: %y", err, info);
    else
        logInfo("WARNING: " + err);
}

OMQ::WorkflowExecutionInstance::workflowError(*string err, auto info) {
    logInfo("%s: %s", err, info);
    stepError(err, info);
}

OMQ::WorkflowExecutionInstance::updateInstanceData(hash<auto> h) {
    instancedata.update(h);
}

# can be a string or a list of strings
auto OMQ::WorkflowExecutionInstance::getInstanceData(auto field) {
    return instancedata.get(field);
}

OMQ::WorkflowExecutionInstance::deleteInstanceDataKey(softlist list) {
    instancedata.deleteKey(list);
}

auto OMQ::WorkflowExecutionInstance::getWorkflowInstanceData(string f) {
    if (OMQ::WFITDHash{f})
        return tld{f};

    if (OMQ::WFDHash{f})
        return wf{f};

    if (OMQ::WFEHash{f})
        return tld.wfe{f};

    if (OMQ::WFEParentHash{f})
        return tld.wfe.parent_info{f};

    switch (f) {
        case "instancemode":
            return mode;
        case "sync":
            return sync_wfiid.toBool();
        case "execid":
            return index;
        case "starttime":
            return starttime;
    }
}

hash<auto> OMQ::WorkflowExecutionInstance::getWorkflowInstanceData(*list<auto> key_list) {
    if (!key_list) {
        return tld.(WFITDHash.keys())
            + wf.(WFDHash.keys())
            + tld.wfe.(WFEHash.keys())
            + tld.wfe.parent_info{keys WFEParentHash}
            + {
            "instancemode": mode,
            "sync": sync_wfiid.toBool(),
            "execid": index,
            "starttime": starttime,
        };
    }

    return (map {$1: getWorkflowInstanceData($1)}, key_list) ?? {};
}

# returns information for the current step
*hash<auto> OMQ::WorkflowExecutionInstance::getStepInfo() {
    *softint stepid = tld.stepID;
    if (!stepid)
        return;

    string mode = tld.mode;
    int ind     = tld.ind;

    hash<auto> h = wf.stepinfo{stepid} + {
        "index": ind,
        "stepid": stepid,
    };

    if (tld.arraySize)
        h.array_size = tld.arraySize;
    if (tld.arrayElement) {
        h.array_element = tld.arrayElement;
    }

    # add status and retry information to step hash for recoveries
    if (mode == OMQ::WM_Recovery) {
        WFEntry wfe = tld.wfe;
        h.retries = wfe.steps{stepid}[ind].retries;
        h.stepstatus = wfe.steps{stepid}[ind].status;
    } else {
        h.retries = 0;
    }

    # remove all keys without any value
    map delete h.$1, keys h, !exists h.$1 || h.$1 === NULL;
    return h;
}

OMQ::WorkflowExecutionInstance::skipAsyncStep() {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::skipAsyncStep index = %y", index);
    auto queueid = tld.asyncQueueID;
    if (!exists queueid)
        throw "INVALID-FUNCTION-CALL", "skipAsyncStep() (or submitAsyncKey()) can only be called once from the front end logic in an asynchronous step";

    logInfo("marking step for skipping async step");
    tld.skipAsync = True;

    # mark data as queued
    remove tld.asyncQueueID;
}

OMQ::WorkflowExecutionInstance::submitAsyncKey(softstring key) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::submitAsyncKey index = %y key = %y", index, key);
    *softint queueid = tld.asyncQueueID;
    if (!exists queueid)
        throw "INVALID-FUNCTION-CALL", "submitAsyncKey() (or skipAsyncStep()) can only be called once from the front end logic in an asynchronous step";

    if (!strlen(key))
        throw "INVALID-KEY", "submitAsyncKey() called with no argument; the argument must be a unique key for the step on the queue";

    softint wfiid = tld.wfe.workflow_instanceid;
    softint stepid = tld.stepID;
    int ind = tld.ind;

    logInfo("submitting key '%s' on queue '%s'", key, wf.stepinfo{stepid}.queuename);

    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            if (tld.mode == OMQ::WM_Normal)
                sqlif.insertQueueData(wfiid, stepid, ind, wf.stepinfo{stepid}.queueid, key);
            else
                sqlif.insertOrUpdateQueueData(wfiid, stepid, ind, wf.stepinfo{stepid}.queueid, key);
            QDBG_TEST_CLUSTER_FAILOVER();
        } catch (hash<ExceptionInfo> ex) {
            # restart the transaction if necessary
            if (trans.restartTransaction(ex))
                continue;
            logInfo("error updating or inserting queue data mode: %y wfiid: %y stepid: %y:%y queueid: %y key: %y", tld.mode, wfiid, stepid, ind, wf.stepinfo{stepid}.queueid, key);
        }
        trans.reset();
        break;
    }

    # mark data as queued
    remove tld.asyncQueueID;
}

private OMQ::WorkflowExecutionInstance::saveSegmentThreadData(string mode, int segid) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::saveSegmentThreadData index %y -> %y", tld.index, index);
    tld += {
        "index": index,
        "mode": mode,
        "wf": wf,
        "segID": segid,
        "_current_ix": "wf",
    };
}

private OMQ::WorkflowExecutionInstance::startNormalSegment(int segid) {
    create_tld();
    saveSegmentThreadData(OMQ::WM_Normal, segid);

    on_exit cSegment.dec();
    QDBG_LOG("WorkflowExecutionInstance::startNormalSegment() index %y segment: %y", index, wf.segment[segid]);

    try {
        if (elements wf.segment[segid].segdeps) {
            execDetachedSegment(segid);
        } else if (wf.segment[segid].subworkflow) {
            execSubWorkflowEventSegment(segid, True);
        } else if (wf.segment[segid].event) {
            execSubWorkflowEventSegment(segid, False);
        } else {
            execAsyncSegment(segid);
        }
    } catch (hash<ExceptionInfo> ex) {
        string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        logFatal(err);
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        # treat this as a fatal error
        setFatalError(ex);
    }
    QDBG_LOG("WorkflowExecutionInstance::startNormalSegment() index %y segid: %d exiting", index, segid);
}

private OMQ::WorkflowExecutionInstance::startRecoverySegment(int segid) {
    create_tld();
    saveSegmentThreadData(OMQ::WM_Recovery, segid);
    QDBG_LOG("WorkflowExecutionInstance::startRecoverySegment index = %y segid = %y", index, segid);

    logInfo("recovery thread started for segment %d", segid);

    on_exit cSegment.dec();

    try {
        while (!checkStop()) {
            setWaiting();
            *hash<auto> d = SM.waitForRetrySegment(index, wf.workflowid, segid);
            if (!exists d) {
                break;
            }

            on_exit {
                SM.releaseRetrySegmentAndWorkflow(wf.workflowid, segid, d.workflow_instanceid);
                remove tld.wfe;
            }

            #printf("startRecoverySegment() %s got: %N\n", format_date("HH:mm:SS", now()), d);
            setRunning();
            tld.wfe.resetAvailableSteps(OMQ::WM_Recovery, segid);

            setupSegmentRecovery(segid);
            if (!checkAttach(segid))
                execSegment(OMQ::WM_Recovery, segid);

            #printf("startRecoverySegment(segid: %d) wfiid: %d\n", segid, tld.wfe.workflow_instanceid);
            #printf("sRS() segment: %N\n", flows.(OMQ::WM_Recovery).segment[segid]);
        }
    } catch (hash<ExceptionInfo> ex) {
        string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        logFatal(err);
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        setFatalError(ex);
    }

    #printf("startRecoverySegment() segid: %d exiting\n", segid);
    logInfo("recovery thread stopped for segment %d", segid);
}

private OMQ::WorkflowExecutionInstance::startSynchronousRecoverySegment(int segid) {
    create_tld();
    saveSegmentThreadData(OMQ::WM_Recovery, segid);
    QDBG_LOG("WorkflowExecutionInstance::startSynchronousRecoverySegment index: %y segid: %y wfiid: %y", index, segid, sync_wfiid);
    tld.sync = sync_wfiid;

    on_exit cSegment.dec();

    logInfo("recovery thread started for segment %d", segid);

    try {
        while (!checkStop()) {
            setWaiting();
            *hash<auto> d = SM.waitForRetrySegment(index, wf.workflowid, segid);
            if (!exists d)
                break;

            *string stat;
            {
                on_exit {
                    stat = SM.releaseRetrySegmentAndWorkflow(wf.workflowid, segid, d.workflow_instanceid);
                    remove tld.wfe;
                }

                #printf("startRecoverySegment() %s got: %N\n", format_date("HH:mm:SS", now()), d);
                setRunning();
                tld.wfe.resetAvailableSteps(OMQ::WM_Recovery, segid);
                setupSegmentRecovery(segid);
                if (!checkAttach(segid))
                    execSegment(OMQ::WM_Recovery, segid);
            }

            #printf("startRecoverySegment(wfiid: %d, segid: %d)\n", tld.wfe.workflow_instanceid, segid);
            #printf("sRS() segment: %N\n", flows.(OMQ::WM_Recovery).segment[segid]);

            if (inlist(stat, (OMQ::StatComplete, OMQ::StatError))) {
                logInfo("recovery segment %d exiting, status is %y", segid, stat);
                if (stat == OMQ::StatError)
                    setStop();
                break;
            }
        }
    } catch (hash<ExceptionInfo> ex) {
        string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        logFatal(err);
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        setFatalError(ex);
    }

    logInfo("recovery thread stopped for segment %d", segid);
}

private OMQ::WorkflowExecutionInstance::startNormalSynchronousSegment(softint segid) {
    create_tld();
    saveSegmentThreadData(OMQ::WM_Normal, segid);
    QDBG_LOG("WorkflowExecutionInstance::startNormalSynchronousSegment index = %y segid = %y wfiid %y", index, segid, sync_wfiid);
    tld.sync = sync_wfiid;

    on_exit cSegment.dec();

    #printf("startNormalSynchronousSegment() segment: %y\n", wf.segment[segid]);

    try {
        *string stat;
        if (elements wf.segment[segid].segdeps)
            stat = execSynchronousDetachedSegment(segid);
        else if (wf.segment[segid].subworkflow)
            stat = execSynchronousSubWorkflowEventSegment(segid, True);
        else if (wf.segment[segid].event)
            stat = execSynchronousSubWorkflowEventSegment(segid, False);
        else
            stat = execSynchronousAsyncSegment(segid);
        if (inlist(stat, (OMQ::StatComplete, OMQ::StatError)))
            SM.terminateRetryConnection(index, wf.workflowid, segid, sync_wfiid);
    } catch (hash<ExceptionInfo> ex) {
        string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        logFatal(err);
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        setFatalError(ex);
    }
    #printf("startNormalSegment() segid: %d exiting\n", segid);
}

private OMQ::WorkflowExecutionInstance::exec() {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::exec index = %y", index);
    # start detached normal segments for async step support
    for (int i = 1; i < elements wf.segment; i++) {
        cSegment.inc();
        background startNormalSegment(i);
    }

    for (int i = 0; i < elements wf.segment; i++) {
        cSegment.inc();
        background startRecoverySegment(i);
    }

    if (int c = cSegment.getCount())
        logInfo("started %d segment thread%s", c, c == 1 ? "" : "s");

    # if recovery mode, then wait for other threads to exit
    if (mode == OMQ::WM_Recovery) {
        # wait for all threads to stop
        cSegment.waitForZero();
        return;
    }

    # main workflow processing loop
    while (True) {
        if (checkStop())
            break;

        # reset thread information
        tld.mode = OMQ::WM_Normal;
        tld -= ("stepName", "stepID");

        # get input data for workflow
        if (waitForData())
            continue;

        {
            WFEntry wfe = tld.wfe;
            on_exit {
                SM.releaseWorkflowInstance(wf.workflowid, wfe.workflow_instanceid);
                remove tld.wfe;
            }
            # we have a workflow in normal mode, now we execute the initial segments

            execInitialSegment(); # execute initial segment
        }
        # if there's a fatal error, then exit
        if (fatal_error) {
            logFatal("exiting workflow due to fatal error");
            break;
        }
    }
}

# execute the array logic and return the value
private softlist OMQ::WorkflowExecutionInstance::execArrayFunction(string mode, int segid, softint stepid, hash<auto> step, bool recover, *list ainfo) {
    QDBG_LOG("WorkflowExecutionInstance::execArrayFunction index = %y mode = %y segid = %y stepid = %y", index, mode, segid, stepid);
    # DEBUG
    if (tld.stepError) {
        logFatal("ERROR: steperror set before execution of array logic");
        qlog(LoggerLevel::FATAL, "DEBUG: %N", get_stack());
    }

    # now execute the array logic
    softlist<auto> array;
    *string aerr;

    try {
        array = wf.runStepArray(stepid);
        aerr = tld.stepError.status;
    } catch (hash<ExceptionInfo> ex) {
        logInfo("error executing array logic for step %s: %s: %s: %s", step.name, get_ex_pos(ex), ex.err, ex.desc);

        # treat exceptions as errors
        aerr = stepError(ex.err, ex.desc, ex.arg);
    }
    if (exists aerr) {
        # get a default array index for error logging
        int defind = 0;
        if (recover) {
            # find first array step to be recovered
            int end = elements ainfo;
            for (; defind < end; ++defind) {
                if (ainfo[defind].status != OMQ::StatComplete)
                    break;
            }
        }

        # we set the status to ERROR
        aerr = handleStepStatus(mode, segid, stepid, defind, aerr, True);
        throw True, aerr;
    }

    # DEBUG: delete me
    #logDebug("array logic returned: %N", array);

    return array;
}

private string OMQ::WorkflowExecutionInstance::skipArrayStepNormal(string mode, int segid, softint stepid, hash<auto> step, int wfiid) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::skipArrayStepNormal index = %y mode = %y segid = %y stepid = %y wfiid = %y", index, mode, segid, stepid, wfiid);
    string stat;
    try {
        logInfo("array logic returned NOTHING, skipping step execution");
        if (step.steptype == OMQ::ExecAsync) {
            logInfo("skipping async step execution");
            stat = OMQ::StatAsyncWaiting;

            tld.skipAsync = True;
        } else if (step.steptype == OMQ::ExecSubWorkflow) {
            logInfo("marking step for skipping subworkflow step");
            tld.skipSubWorkflow = True;
            stat = OMQ::StatWaiting;
        } else if (step.steptype == OMQ::ExecEvent) {
            logInfo("marking step for skipping synchronization event step");
            tld.skipEvent = True;
            stat = OMQ::StatEventWaiting;
        } else {
            # if it's not an asynchronous step
            logInfo("array logic returned NOTHING, creating step as COMPLETE (C)");
            # update step already inserted to COMPLETE
            stat = OMQ::StatComplete;
        }
    } catch (hash<ExceptionInfo> ex) {
        stepException("QORE-EXCEPTION", sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc));
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        stat = OMQ::StatError;
    }

    stat = handleStepStatus(mode, segid, stepid, 0, stat, True);
    return stat;
}

private string OMQ::WorkflowExecutionInstance::skipArrayStepRecover(string mode, softint segid, softstring stepid, hash step, auto wfiid, auto ainfo) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::skipArrayStepRecover index = %y mode = %y segid = %y stepid = %y wfiid = %y", index, mode, segid, stepid, wfiid);
    WFEntry wfe = tld.wfe;

    # otherwise we are recovering, update internal statuses and do not update DB
    # get current step status
    *string stat = wfe.getArrayStepStatus(stepid);

    # the overall status might not exist for the step in case the step was skipped
    # because the array logic returned NOTHING the first time the step was run
    # and then the second time the array logic returned a non-zero length list
    if (!exists stat) {
        logInfo("array logic returned NOTHING, step has no status, setting to COMPLETE (C)");
        return handleStepStatus(mode, segid, stepid, 0, OMQ::StatComplete, True);
    }

    if (stat == OMQ::StatInProgress) {
        # original status can be in-progress in case of a race condition (back-end executing when status acquired)
        logInfo("array logic returned NOTHING, step was IN-PROGRESS (I) when original status acquired, setting to ERROR (E)");
        return OMQ::StatError;
    }

    # if there is only the default array step, then skip the step entirely
    if (elements ainfo != 1) {
        logInfo("array logic returned NOTHING, returning original status '%s'", stat);
        return stat;
    }

    hash<auto> rh = wfe.setStepInProgress(stepid, 0);

    # if the step already has a finalized status, then use it instead
    if (exists rh."final-status") {
        stat = rh."final-status";
        logInfo("array logic returned NOTHING with only 1 default element, but has final status %y from another segment, skipping step execution in this segment", stat);

        return stat;
    }

    *hash<auto> hh;

    QorusRestartableTransaction trans();
    while (True) {
        try {
            switch (step.steptype) {
                case OMQ::ExecAsync: {
                    hh = sqlif.getQueueInfo(wfiid, stepid, 0);
                    break;
                }

                case OMQ::ExecSubWorkflow: {
                    hh = sqlif.workflowInstanceExecuteSubWorkflowStep(wfiid, stepid, 0);
                    break;
                }

                case OMQ::ExecEvent: {
                    hh = sqlif.workflowInstanceGetStepInstanceEvent(wfiid, stepid, 0);
                    break;
                }
            }
            QDBG_TEST_CLUSTER_FAILOVER();
        }
        catch (hash<ExceptionInfo> ex) {
            # restart the transaction if necessary
            if (trans.restartTransaction(ex))
                continue;
            rethrow;
        }
        trans.reset();
        break;
    }

    switch (step.steptype) {
        case OMQ::ExecAsync: {
            # ignore queue data with 'X' status
            if (hh.queue_data_status == 'X')
                delete hh;

            if (hh) {
                logInfo("array logic returned NOTHING when recovering a step with 1 element and existing queue entry %y; returning status 'E' (ERROR)", hh.queuekey);
                stat = OMQ::StatError;
            }
            else {
                logInfo("array logic returned NOTHING with only 1 default element, skipping step execution");
                tld.skipAsync = True;
                stat = OMQ::StatAsyncWaiting;
            }
            break;
        }

        case OMQ::ExecSubWorkflow: {
            if (hh) {
                logInfo("array logic returned NOTHING when recovering a step with 1 element and an existing subworkflow (%d) bound to this step, this represents an error in the workflow's logic; returning status 'W' (WAITING)", hh.subworkflow_instanceid);
            }
            else {
                logInfo("array logic returned NOTHING with only 1 default element; marking step for skipping subworkflow");
                tld.skipSubWorkflow = True;
            }
            stat = OMQ::StatWaiting;
            break;
        }

        case OMQ::ExecEvent: {
            if (hh) {
                logInfo("array logic returned NOTHING when recovering a step with 1 element and an existing synchronization event (event type %y (%d), eventkey %y) bound to this step, this represents an error in the workflow's logic; returning status 'V' (EVENT-WAITING)", Qorus.qmm.lookupEvent(hh.workflow_event_typeid), hh.workflow_event_typeid, hh.eventkey);
            }
            else {
                logInfo("array logic returned NOTHING with only 1 default element; marking step for skipping");
                tld.skipSubWorkflow = True;
            }
            stat = OMQ::StatEventWaiting;
            break;
        }

        default: {
            logInfo("array logic returned NOTHING with only 1 default element; setting step to COMPLETE");
            stat = OMQ::StatComplete;
        }
    }
    stat = handleStepStatus(mode, segid, stepid, 0, stat, True);

    return stat;
}

private string OMQ::WorkflowExecutionInstance::execArrayStep(string mode, int segid, softstring stepid) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::execArrayStep index = %y mode = %y segid = %y stepid = %y", index, mode, segid, stepid);
    softint workflow_instanceid = tld.wfe.workflow_instanceid;

    # copy array step status structure for easier reference
    *list ainfo = tld.wfe.steps{stepid};

    logInfo("starting execution of array step");

    WFEntry wfe = tld.wfe;
    bool recover = exists wfe.steps{stepid};
    #flows{mode}.segment[segid].overallstatus{stepid};

    # DEBUG
    #logDebug("WorkflowExecutionInstance::execArrayStep(mode: %y, segid: %y stepid: %y) recover: %y\n", mode, segid, stepid, recover);
    #printf("WorkflowExecutionInstance::execArrayStep() segid: %y, flowdata: %N\n", segid, flowdata);

    # get step description
    hash step = wf.stepinfo{stepid};

    try {
        # insert step if executing for the first time
        if (!recover) {
            try {
                # this call cannot return any previous or final status
                wfe.setStepInProgress(stepid, 0);
            } catch (hash<ExceptionInfo> ex) {
                logFatal("error setting step status workflow_instanceid: %d stepid: %d ind: 0: %s: %s", workflow_instanceid, stepid, ex.err, ex.desc);
                logFatal("wfe: %N", wfe);
                return OMQ::StatError;
            }
        } else if (mode == OMQ::WM_Normal) {
            # bug 1241: check if step is actually COMPLETE before trying to execute it
            *string stat = wfe.checkFinalStatus(stepid, 0);
            if (stat) {
                # the entire step must be complete if ind 0 is complete
                logInfo("array step final status %y from another segment, skipping step execution in this segment", stat);
                if (stat == OMQ::StatComplete) {
                    tld.wfe.markStepComplete(mode, segid, stepid);
                }

                return stat;
            }
        }

        list<auto> array;
        # get the array data for the step
        # if an error occurs, return the status
        try {
            array = execArrayFunction(mode, segid, stepid, step, recover, ainfo);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err)
                return ex.desc;
            rethrow;
        }

        string stat;
        # if the array logic returned NOTHING or an empty list
        if (array.empty()) {
            # if executing the step for the first time
            if (!recover)
                stat = skipArrayStepNormal(mode, segid, stepid, step, workflow_instanceid);
            else
                stat = skipArrayStepRecover(mode, segid, stepid, step, workflow_instanceid, ainfo);
        } else {
            int alen = array.size();
            logInfo("array logic returned %d element%s", alen, alen == 1 ? "" : "s");

            # save "arraySize" in thread-local data so it can be reported in getStepInfo()
            tld.arraySize = alen;
            on_exit remove tld.arraySize;

            # insert step_instance rows with an IN-PROGRESS status before executing the step functions
            # to avoid race conditions with the segment status
            if (!recover) {
                if (array.size() > 1)
                    wfe.setArrayStepInProgressCommit(stepid, array.size());

                # DEBUG
                #logDebug("starting normal array step execution (%d element(s))", array.size());
                for (int ind = 0; ind < array.size(); ind++)
                    execArrayStepInternal(mode, segid, stepid, ind, array, \stat, ainfo[ind].status);
            } else {
                # add any keys to structure for elements returned by the array logic that do not exist yet
                # NOTE: we do not create the status key here so we know that the step is a new step

                # bug 488: insert array step elements in case a larger list was passed this time when recovering
                wfe.setArrayStepInProgressCommitRecover(stepid, array.size());

                # DEBUG
                #logDebug("starting recovery array step execution (%d element(s)): %y", array.size(), ainfo);

                int last = max(array.size(), ainfo.size());

                # execute only steps that do not have status COMPLETE or ERROR
                for (int ind = 0; ind < last; ++ind) {
                    # DEBUG
                    #logDebug("processing ind: %N (status: %y, exists status: %y)", ind, ainfo[ind].status, exists ainfo[ind].status);
                    if (ainfo[ind].status == OMQ::StatError)
                        stat = OMQ::StatError;
                    else if (ainfo[ind].status != OMQ::StatComplete)
                        execArrayStepInternal(mode, segid, stepid, ind, array, \stat, ainfo[ind].status);
                }
            }
        }

        # if overall step status is COMPLETE, then remove from dependency list
        if (stat == OMQ::StatComplete)
            tld.wfe.markStepComplete(mode, segid, stepid);

        return stat;
    } catch (hash<ExceptionInfo> ex) {
        # log complete exception info
        logInfo(Util::get_exception_string(ex));

        stepError(ex.err, ex.desc, ex.arg);

        # get a default array index for error logging
        int defind = 0;
        if (recover) {
            # find first array step to be recovered
            int end = elements ainfo;
            for (; defind < end; ++defind) {
                if (ainfo[defind].status != OMQ::StatComplete)
                    break;
            }
        }

        # we set the status to ERROR
        return handleStepStatus(mode, segid, stepid, defind, OMQ::StatError, True);
    }
}

private OMQ::WorkflowExecutionInstance::execArrayStepInternal(string mode, int segid, softstring stepid, int ind,
        list<auto> array, reference masterstatus, *string ostat) {
    QDBG_ASSERT(ensure_tld());
    string stat;
    tld.ind = ind;
    remove tld.stepError;

    QDBG_LOG("WorkflowExecutionInstance::execArrayStepInternal stepid %d/%d %s ostat: %y", stepid, ind,
        wf.stepinfo{stepid}.steptype, ostat);
    try {
        WFEntry wfe = tld.wfe;
        *hash<auto> rh;
        if (ostat) {
            rh = wfe.setStepInProgress(stepid, ind);
            if (rh."old-status")
                ostat = rh."old-status";
        }

        if (rh."final-status") {
            stat = rh."final-status";
            logInfo("step has final status %y from another segment, skipping step execution in this segment", stat);
        } else {
            ThreadResourceHelper trh();

            auto old_array_element = tld.arrayElement;
            tld.arrayElement = array[ind];
            on_exit tld.arrayElement = old_array_element;

            switch (wf.stepinfo{stepid}.steptype) {
                case OMQ::ExecNormal:
                    stat = executeNormalStep(stepid, ind, ostat, array);
                    break;

                case OMQ::ExecAsync:
                    stat = executeFrontEndAsyncStep(stepid, ind, ostat, array);
                    break;

                case OMQ::ExecSubWorkflow:
                    stat = executeSubWorkflowStep(stepid, ind, ostat, array);
                    break;

                case OMQ::ExecEvent:
                    stat = executeEventStep(stepid, ind, ostat, array);
                    break;
            }
        }
    } catch (hash<ExceptionInfo> ex) {
        logInfo("error generated from exception thrown at %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        # treat exceptions as errors
        stepError(ex.err, ex.desc, ex.arg);
        stat = OMQ::StatError;
    }

    stat = handleStepStatus(mode, segid, stepid, ind, stat, True);
    if (OMQ::StatusOrder{stat} > OMQ::StatusOrder{masterstatus})
        masterstatus = stat;
}

private OMQ::WorkflowExecutionInstance::correctSystemQueueEntry(softint wfiid, softint stepid, int ind, string queuekey) {
    logInfo("correcting queue entry with key %y on queue %y", queuekey, wf.stepinfo{stepid}.queuename);

    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            sqlif.correctQueueData(wfiid, stepid, ind);
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

    SM.updateQueueUnlocked(wf.workflowid, stepid, wfiid, ind, tld.wfe.priority, True, queuekey, NOTHING, tld.wfe.parent_info);
}

private string OMQ::WorkflowExecutionInstance::execStep(string mode, int segid, softstring stepid) {
    QDBG_LOG("WorkflowExecutionInstance::execStep index = %y mode = %y segid = %y stepid = %y", index, mode, segid, stepid);
    string rv;

    try {
        WFEntry wfe = tld.wfe;

        hash<auto> rh = wfe.setStepInProgress(stepid, 0);
        if (exists rh."final-status") {
            rv = rh."final-status";
            logInfo("step has final status %y from another segment, skipping step execution in this segment", rv);
        } else {
            ThreadResourceHelper trh();

            # DEBUG
            QDBG_LOG("WorkflowExecutionInstance::execStep segid: %d stepid: %d rh: %y wfe.steps.%y: %y", segid, stepid, rh, stepid, wfe.steps{stepid});

            *string stat = rh."old-status";

            switch (wf.stepinfo{stepid}.steptype) {
                case OMQ::ExecNormal:
                    rv = executeNormalStep(stepid, 0, stat);
                    break;

                case OMQ::ExecAsync:
                    rv = executeFrontEndAsyncStep(stepid, 0, stat);
                    break;

                case OMQ::ExecSubWorkflow:
                    rv = executeSubWorkflowStep(stepid, 0, stat);
                    break;

                case OMQ::ExecEvent:
                    rv = executeEventStep(stepid, 0, stat);
                    break;

                default:
                    QDBG_ASSERT(False);
            }
        }
    } catch (hash<ExceptionInfo> ex) {
        # log complete exception info
        logInfo(get_exception_string(ex));
        # treat exceptions as errors
        stepError(ex.err, ex.desc, ex.arg);
        rv = OMQ::StatError;
    }

    return handleStepStatus(mode, segid, stepid, 0, rv, False);
}

private OMQ::WorkflowExecutionInstance::execStepThread(WFEntry wfe, string mode, int segid, *softstring stepid, Counter cnt, bool new_thread, *hash<auto> index_map) {
    if (new_thread) {
        create_tld();
    }
%ifdef QorusDebugInternals
    else {
        QDBG_ASSERT(ensure_tld());
    }
%endif

    QDBG_LOG("WorkflowExecutionInstance::execStepThread index %y -> %y", tld.index, index);
    if (new_thread) {
        # set local index
        tld.index = index;
        tld.index_map = index_map;
    }
%ifdef QorusDebugInternals
    else QDBG_ASSERT(tld.index);
%endif

    # decrement thread count atomically, will signal parent thread if last thread exiting
    on_exit cnt.dec();

    string rv;

    #logDebug("DEBUG: WorkflowExecutionInstance::execStepThread(mode: %y, segid: %y, stepid: %y)", mode, segid, stepid);
    while (True) {
        if (!exists stepid) {
            # get list of available steps
            list avail_steps = wfe.getAvailableSteps(mode, segid);
            #logDebug("DEBUG: execStepThread(mode: %y segid: %y stepid: %y): wiid: %y avail_steps: %N", mode, segid, stepid, flows{mode}.segment[segid].workflow_instanceid, avail_steps);
            #logDebug("DEBUG: execStepThread(mode: %y segid: %y stepid: %y): seg: %N", mode, segid, stepid, flows{mode}.segment[segid]);

            # exit loop if no steps are available
            if (!elements avail_steps)
                break;

            stepid = int(shift avail_steps);

            # launch new threads
            foreach softstring s in (avail_steps) {
                cnt.inc();
                on_error cnt.dec();
                background execStepThread(wfe, mode, segid, s, cnt, True, tld.index_map);
            }
        }

        softint wfiid = wfe.workflow_instanceid;

        # set up thread-local data
        tld += (
            "mode": mode,
            "wf": wf,
            "segID": segid,
            "wfe": wfe,
            "stepName": wf.stepinfo{stepid}.name,
            "stepID": stepid,
            "ind": 0,
            "businessError": False,
            "stepError": NOTHING,
            "_current_ix": "wf",
        );

        if (sync_wfiid)
            tld.sync = wfiid;

        on_exit {
            tld -= ("stepID", "stepName", "ind", "stepError", "wfe", "retryDelay", "skipSubWorkflow", "skipEvent", "skipAsync");
            delete stepid;
        }
        remove tld.retryDelay;

        if (wf.stepinfo{stepid}.arraytype != OMQ::ArrayNone)
            rv = execArrayStep(mode, segid, stepid);
        else
            rv = execStep(mode, segid, stepid);

        if (rv != OMQ::StatComplete)
            break;
    }
}

private *string OMQ::WorkflowExecutionInstance::execSynchronousSubWorkflowEventSegment(softint segid, bool swf) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::execSynchronousSubWorkflowEventSegment index = %y segid = %y swf = %y", index, segid, swf);
    softint stepid = wf.segment[segid].start;
    softint linksegid = wf.segment[segid].linksegment;
    *string stat;

    if (swf)
        logInfo("async subworkflow thread started for segment %d", segid);
    else
        logInfo("synchronization event thread started for segment %d", segid);

    while (!checkStop()) {
        setWaiting();
        *hash<auto> d = swf
            ? SM.waitForSubWorkflowEvent(index, wf.workflowid, stepid, segid, linksegid)
            : SM.waitForSyncEvent(index, wf.workflowid, stepid, segid, linksegid);

        if (!exists d)
            break;

        {
            on_exit {
                stat = SM.releaseSegmentAndWorkflow(wf.workflowid, segid, d.workflow_instanceid);
                remove tld.ind;
            }

            setRunning();

            # save thread variables
            #tld.ind = d.ind;

            tld.wfe.resetAvailableSteps(OMQ::WM_Normal, segid);

            execSegment(OMQ::WM_Normal, segid);
        }

        if (stat == OMQ::StatError) {
            setStop();
            break;
        }

        if (stat == OMQ::StatComplete) {
            SM.terminateRetryConnection(index, wf.workflowid, segid, sync_wfiid);
            break;
        }

        break;
    }
    if (swf)
        logInfo("async subworkflow thread stopped for segment %d", segid);
    else
        logInfo("synchronization event thread stopped for segment %d", segid);

    return stat;
}

private *string OMQ::WorkflowExecutionInstance::execSynchronousAsyncSegment(int segid) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::execSynchronousAsyncSegment index = %y segid = %y", index, segid);
    softint stepid = wf.segment[segid].start;
    softint linksegid = wf.segment[segid].linksegment;

    *string stat;

    logInfo("async queue thread started for segment %d", segid);

    while (!checkStop()) {
        bool finished = True;

        setWaiting();
        *hash<auto> d = SM.waitForQueueSegment(index, wf.stepinfo{stepid}.queueid, wf.workflowid, segid, stepid, linksegid);

        if (!d)
            break;

        {
            on_exit {
                stat = SM.releaseSegmentAndWorkflow(wf.workflowid, segid, d.workflow_instanceid);
                tld -= ("ind", "wfe", "virtual");
            }

            setRunning();
            # save thread variables
            tld.wfe.resetAvailableSteps(OMQ::WM_Normal, segid);

            *string status;
            bool ok = False;

            foreach int ind in (d.ind) {
                bool corrected = d.corrected[$#];
                auto data = d.data[$#];

                if (corrected || !exists (status = executeBackEndFunction(segid, stepid, ind, data))) {
                    if (wf.stepinfo{stepid}.arraytype == OMQ::ArrayNone) {
                        ok = True;
                        tld.wfe.markStepComplete(OMQ::WM_Normal, segid, stepid);
                        SM.commitAsyncSegment(wf.workflowid, linksegid, stepid);
                    } else { # for array steps, just create the new segment and set the step to complete if all steps are complete
                        int rc = SM.tryCommitAsyncArraySegment(wf.workflowid, linksegid, stepid, ind);
                        if (rc > 0) {
                            remove tld.virtual;
                            ok = True;
                            tld.wfe.markStepComplete(OMQ::WM_Normal, segid, stepid);
                        } else
                            finished = False;
                    }
                } else { # back end reported an error, so set front end step to error
                    SM.updateFrontEndStepStatus(stepid, ind, status);
                    # stop processing synchronous workflow if an error has occurred
                    if (status == OMQ::StatError)
                        setStop();
                }
            }

            # commit the front-end segment status if new segment not started
            # also releases the front end segment in the segment event queue
            if (!ok)
                SM.releaseAsyncFrontEndSegment(wf.workflowid, linksegid);
            else
                execSegment(OMQ::WM_Normal, segid);
        }

        if (stat == OMQ::StatError) {
            setStop();
            break;
        }

        if (stat == OMQ::StatComplete) {
            SM.terminateRetryConnection(index, wf.workflowid, segid, sync_wfiid);
            break;
        }

        if (finished)
            break;
    }

    logInfo("async queue thread stopped for segment %d", segid);

    return stat;
}

private *string OMQ::WorkflowExecutionInstance::execSynchronousDetachedSegment(softint segid) {
    QDBG_LOG("WorkflowExecutionInstance::execSynchronousDetachedSegment index = %y segid = %y", index, segid);
    *string stat;

    logInfo("detached segment thread started for segment %d", segid);

    setWaiting();
    *hash<auto> d = SM.waitForDetachedSegment(wf.workflowid, segid, index);
    if (d) {
        {
            on_exit {
                stat = SM.releaseSegmentAndWorkflow(wf.workflowid, segid, d.workflow_instanceid);
            }

            setRunning();
            tld.wfe.resetAvailableSteps(OMQ::WM_Normal, segid);
            #printf("execSynchronousDetachedSegment(segid: %d)\n", segid);
            execSegment(OMQ::WM_Normal, segid);
        }

        if (stat == OMQ::StatError)
            setStop();
        if (stat == OMQ::StatComplete)
            SM.terminateRetryConnection(index, wf.workflowid, segid, sync_wfiid);
    }

    logInfo("detached segment thread stopped for segment %d", segid);

    return stat;
}

private OMQ::WorkflowExecutionInstance::execSubWorkflowEventSegment(softint segid, bool swf) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::execSubWorkflowEventSegment index = %y segid = %y swf = %y", index, segid, swf);
    softint stepid = wf.segment[segid].start;
    softint linksegid = wf.segment[segid].linksegment;

    if (swf)
        logInfo("async subworkflow thread started for segment %d", segid);
    else
        logInfo("synchronization event thread started for segment %d", segid);

    while (!checkStop()) {
        setWaiting();
        *hash<auto> d = swf
            ? SM.waitForSubWorkflowEvent(index, wf.workflowid, stepid, segid, linksegid)
            : SM.waitForSyncEvent(index, wf.workflowid, stepid, segid, linksegid);

        #logDebug("DEBUG: eSWFS() got d: %y", d);

        if (!d)
            break;

        on_exit {
            SM.releaseSegmentAndWorkflow(wf.workflowid, segid, d.workflow_instanceid);
            tld -= ("ind", "wfe");
        }

        setRunning();

        tld.wfe.resetAvailableSteps(OMQ::WM_Normal, segid);

        *string status = checkAttach(segid);
        # DEBUG
        #logDebug("DEBUG: execSubWorkflowEventSegment() status: %y", status);
        if (!status) {
            tld.wfe.markStepComplete(OMQ::WM_Normal, segid, stepid);
            execSegment(OMQ::WM_Normal, segid);
        } else { # back end reported an error, so set the segment to error
            tld.wfe.setSegmentError(segid);
        }
    }

    if (swf)
        logInfo("async subworkflow thread stopped for segment %d", segid);
    else
        logInfo("synchronization event thread stopped for segment %d", segid);
}

private OMQ::WorkflowExecutionInstance::execAsyncSegment(int segid) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::execAsyncSegment index = %y segid = %y", index, segid);
    softint stepid = wf.segment[segid].start;
    softint linksegid = wf.segment[segid].linksegment;

    logInfo("async queue thread started for segment %d", segid);

    while (!checkStop()) {
        setWaiting();
        *hash<auto> d = SM.waitForQueueSegment(index, wf.stepinfo{stepid}.queueid, wf.workflowid, segid, stepid, linksegid);

        if (!exists d)
            break;

        on_exit {
            SM.releaseSegmentAndWorkflow(wf.workflowid, segid, d.workflow_instanceid);
            tld -= ("ind", "wfe", "virtual");
        }

        setRunning();
        # save thread variables
        tld.wfe.resetAvailableSteps(OMQ::WM_Normal, segid);

        *string status = checkAttach(segid);
        # DEBUG
        #logDebug("attach status: %y", status);
        if (status) {
            if (inlist(status, (OMQ::StatBlocked, OMQ::StatScheduled)))
                status = OMQ::StatError;
            SM.commitFrontEndStepStatusReleaseSegment(wf.workflowid, linksegid, stepid, d.ind, status);

            continue;
        }

        bool ok = False;

        #logDebug("WorkflowExecutionInstance::execAsyncSegment() wfiid: %d segid: %d stepid: %d d: %y", tld.wfe.workflow_instanceid, segid, stepid, d);

        foreach int ind in (d.ind) {
            bool corrected = d.corrected[$#];
            auto data = d.data[$#];

            # DEBUG
            #logDebug("WorkflowExecutionInstance::execAsyncSegment() wfiid: %d segid: %d stepid: %d ind: %d corrected: %y", tld.wfe.workflow_instanceid, segid, stepid, ind, corrected);

            if ((corrected || !exists (status = executeBackEndFunction(segid, stepid, ind, data)))) {
                if (wf.stepinfo{stepid}.arraytype == OMQ::ArrayNone) {

                    #logDebug("WorkflowExecutionInstance::execAsyncSegment() wfiid: %d segid: %d stepid: %d ind: %d non-array step COMPLETE", tld.wfe.workflow_instanceid, segid, stepid, ind);

                    ok = True;
                    tld.wfe.markStepComplete(OMQ::WM_Normal, segid, stepid);
                    SM.commitAsyncSegment(wf.workflowid, linksegid, stepid);
                } else { # for array steps, just create the new segment and set the step to complete if all steps are complete
                    int rc = SM.tryCommitAsyncArraySegment(wf.workflowid, linksegid, stepid, ind);
                    if (rc > 0) {
                        #logDebug("WorkflowExecutionInstance::execAsyncSegment() wfiid: %d segid: %d stepid: %d ind: %d array step COMPLETE", tld.wfe.workflow_instanceid, segid, stepid, ind);

                        remove tld.virtual;
                        ok = True;
                        tld.wfe.markStepComplete(OMQ::WM_Normal, segid, stepid);
                    }
                    #else
                    #logDebug("WorkflowExecutionInstance::execAsyncSegment() wfiid: %d segid: %d stepid: %d ind: %d array step not yet COMPLETE", tld.wfe.workflow_instanceid, segid, stepid, ind);
                }
            } else { # back end reported an error, so set front end step to error
                #logDebug("WorkflowExecutionInstance::execAsyncSegment() wfiid: %d segid: %d stepid: %d ind: %d setting status to %y", tld.wfe.workflow_instanceid, segid, stepid, ind, status);
                SM.updateFrontEndStepStatus(stepid, ind, status);
            }
        }

        # commit the front-end segment status if new segment not started
        # also releases the front end segment in the segment event queue
        if (!ok)
            SM.releaseAsyncFrontEndSegment(wf.workflowid, linksegid);

        if (ok)
            execSegment(OMQ::WM_Normal, segid);
    }
    logInfo("async queue thread stopped for segment %d", segid);
}

private OMQ::WorkflowExecutionInstance::execDetachedSegment(int segid) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::execDetachedSegment index = %y segid = %y", index, segid);
    logInfo("detached segment thread started for segment %d", segid);

    while (!checkStop()) {
        setWaiting();
        *hash<auto> d = SM.waitForDetachedSegment(wf.workflowid, segid, index);

        if (!exists d)
            break;

        on_exit {
            SM.releaseSegmentAndWorkflow(wf.workflowid, segid, d.workflow_instanceid);
            remove tld.wfe;
        }

        setRunning();
        tld.wfe.resetAvailableSteps(OMQ::WM_Normal, segid);
        #printf("execDetachedSegment(segid: %d)\n", segid);
        if (!checkAttach(segid))
            execSegment(OMQ::WM_Normal, segid);
    }

    logInfo("detached segment thread stopped for segment %d", segid);
}

private OMQ::WorkflowExecutionInstance::execSegment(string mode, int segid) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::execSegment index = %y mode = %y segid = %y", index, mode, segid);
    tld.segID = segid;

    #logDebug("DEBUG: execSegment(mode: %y, segid: %y)", mode, segid);
    # Counter to ensure that all step-specific threads are done before we leave execSegment().
    Counter cnt();
    cnt.inc();

    # DEBUG
    #printf("execSegment() start flowdata.segment[%d].cThreads.getCount(): %d\n", segid, flowdata.segment[segid].cThreads.getCount());

    on_exit # wait for threads to terminate
        cnt.waitForZero();

    execStepThread(tld.wfe, mode, segid, NOTHING, cnt, False);
}

# called only in normal mode
private *string OMQ::WorkflowExecutionInstance::execInitialSegment() {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::execInitialSegment index = %y", index);
    setRunning();
    tld.mode = OMQ::WM_Normal;
    tld.segID = 0;

    softint wfiid = tld.wfe.workflow_instanceid;

    *string stat = checkAttach(0);
    if (stat) {
        # take no action if the status is BLOCKED
        # create segment 0 with status ERROR and mark workflow order data with ERROR if an error occurs
        if (!inlist(stat, (OMQ::StatBlocked, OMQ::StatReady, OMQ::StatScheduled)))
            SM.markReadyWorkflowAsError(wfiid, sprintf("attach logic failed with status = %y", stat));
        return stat;
    }

    SM.setupInitialSegment(wf.workflowid, wfiid, sync_wfiid);

    {
        on_exit {
            stat = SM.releaseSegment(wf.workflowid, 0, wfiid);
        }

        tld.wfe.resetAvailableSteps(OMQ::WM_Normal, 0);
        execSegment(OMQ::WM_Normal, 0);
    }
    setWaiting();

    return stat;
}

private *string OMQ::WorkflowExecutionInstance::checkAttach(int segid) {
    if (!wf.hasAttach()) {
        # confirm that no attach was necessary and that we are starting processing
        SM.confirmNoAttach();
        return;
    }

    int rcode = SM.needsAttach();
    # already blocked
    if (rcode == OMQ::WF_ATTACH_BLCK)
        return OMQ::StatBlocked;
    # already attached
    if (rcode == OMQ::WF_ATTACH_DONE)
        return;
    # "assertion" for DEBUG only - but the needsAttach doesn't return anything else here
    #if (rcode != OMQ::WF_ATTACH_NEED)
    #    throw "FATAL-ERROR", sprintf("Unhandled status of needsAttach() = %s", rcode);

    # now the real attach checking continues
    try {
        string status = execAttach(segid);

        #logDebug("DEBUG: execAttach() returned %y", status);

        # execAttach() returns StatComplete for succesfully finished
        # attach calls. checkAttach() returns NOTHING for this case.
        # If there is a real error, SM.confirmAttachError() is called.
        # If there was a BLOCKED request call by an user it marks
        # it as "not success" but no error is raised upstream. Its only BLOCKED.
        if (inlist(status, (OMQ::StatBlocked, OMQ::StatReady, OMQ::StatScheduled))) {
            SM.confirmAttachStop();
            # bug 366: stop synchronous workflow
            if (sync_wfiid)
                setStop(NOTHING, "attach error");
            return status;
        }
        if (status != OMQ::StatComplete) {
            SM.confirmAttachError();
            # bug 366: stop synchronous workflow
            if (sync_wfiid)
                setStop(NOTHING, "attach error");
            return status;
        }
    } catch (hash<ExceptionInfo> ex) {
        SM.confirmAttachError();
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        rethrow;
    }
    SM.confirmAttach();
    #logDebug("DEBUG: checkAttach() returning NOTHING");
}

private OMQ::WorkflowExecutionInstance::setupSegmentRecovery(int segid) {
    QDBG_LOG("WorkflowExecutionInstance::setupSegmentRecovery index = %y segid = %y", index, segid);
    #logDebug("DEBUG: BEFORE setupSegmentRecovery(segid: %d) wfiid: %d seg: %N\n", segid, tld.wfe.workflow_instanceid, flows.(OMQ::WM_Recovery).segment[segid]);

    WFEntry wfe = tld.wfe;

    foreach softstring id in (wf.segment[segid].steplist) {
        if (!exists wfe.steps{id})
            continue;

        bool array = (wf.steps{id}.arraytype != OMQ::ArrayNone);

        # derive overall step status for array steps
        string status;
        if (!array)
            status = wfe.steps{id}[0].status;
        else {
            status = wfe.getArrayStepStatus(id);
        }

        if (status == OMQ::StatComplete) {
            # remove step dependency list
            tld.wfe.markStepComplete(OMQ::WM_Recovery, segid, id);
        }
    }

    #logDebug("DEBUG: AFTER setupSegmentRecovery(segid: %d) wfiid: %d seg: %N\n", segid, tld.wfe.workflow_instanceid, flows.(OMQ::WM_Recovery).segment[segid]);
}

private *int OMQ::WorkflowExecutionInstance::waitForData() {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::waitForData index = %y", index);
    tld.segID = 0;

    setWaiting();

    # try to get waiting workflows with READY status
    if (!SM.waitForReadyWorkflow(wf.workflowid, index))
        return -1;

    setRunning();
}

private *string OMQ::WorkflowExecutionInstance::runStepValidation(softstring stepid) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::runStepValidation() index = %y", index);
    *string stat = wf.runStepValidationArgs(stepid, exists argv[0] ? argv : NOTHING);

    if ((*string err = tld.stepError.status)) {
        remove tld.stepError;
        stat = err;
    }
    return stat;
}

# execute workflow synchronization event step
private string OMQ::WorkflowExecutionInstance::executeEventStep(softstring stepid, int ind, *string ostat,
        *list<auto> array) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::executeEventStep index = %y stepid = %y ind = %y", index, stepid, ind);
    softint wfiid = tld.wfe.workflow_instanceid;

    # get step description
    hash<auto> step = wf.stepinfo{stepid};

    #logDebug("DEBUG: WorkflowExecutionInstance::executeEventStep() stepid: %y, step: %y", stepid, step);

    # get event type name
    string event = Qorus.qmm.lookupEvent(step.workflow_event_typeid).name;

    # get WFEntry object from thread-local data
    WFEntry wfe = tld.wfe;

    try {
        if (exists array)
            logInfo("starting execution of synchronization event array substep [%d] (event type: %y (%d))", ind,
                event, step.workflow_event_typeid);
        else
            logInfo("starting execution of synchronization event step (event type: %y (%d))", event,
                step.workflow_event_typeid);
        #printf("WorkflowExecutionInstance::executeEventStep(stepid: %y)\n", stepid);

        # if we are recovering
        if (exists ostat) {
            # see if an event has already been bound to this step
            *hash eq;
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();

                    eq = sqlif.workflowInstanceGetStepInstanceEvent(wfiid, stepid, ind);
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

            if (exists eq) {
                # check if the step should be skipped
                if (wfe.steps{stepid}[ind].skip) {
                    logInfo("event synchronization step flagged to be skipped");
                    tld.skipEvent = True;
                } else
                    logInfo("already bound to eventkey %y; updating step status to 'V' (EVENT-WAITING); not "
                        "re-executing step", eq.eventkey);
                return OMQ::StatEventWaiting;
            }
            logInfo("eventkey has not yet been created and bound to step; re-executing step");
        }

        # to enable event binding
        #tld.event_name = event;
        tld.eventTypeID = step.workflow_event_typeid;

        # remove thread keys for event steps at the end of the block
        on_exit
            tld -= ("eventTypeID", "eventKey");

        # execute step logic
        try {
            wf.runStepPrimaryArgs(stepid, array[ind]);
        } catch (hash<ExceptionInfo> ex) {
            # log complete exception info
            logInfo(Util::get_exception_string(ex));

            # treat exceptions as errors
            stepError(ex.err, ex.desc, ex.arg);
        }

        # if no error was raised and no key was submitted and the step was not skipped, then raise an error
        if (!tld.stepError && !tld.eventKey && !tld.skipEvent) {
            stepError("NO-EVENT-BOUND", sprintf("event step '%s' did not call either bind_event() or skip_event(); one of these functions must be called in the primary step logic for event steps", wf.stepinfo{stepid}.name));
        }
    } catch (hash<ExceptionInfo> ex) {
        stepException("QORE-EXCEPTION", sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc));
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
    }

    # derive status
    *string stat = tld.stepError.status;
    if (!stat)
        stat = OMQ::StatEventWaiting;

    return stat;
}

private string OMQ::WorkflowExecutionInstance::executeSubWorkflowStep(softstring stepid, int ind, *string ostat, *list<auto> array) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::executeSubWorkflowStep index = %y stepid = %y ind = %y", index, stepid, ind);
    softint workflow_instanceid = tld.wfe.workflow_instanceid;

    *string stat;
    try {
        if (exists array)
            logInfo("starting execution of subworkflow array substep [%d]", ind);
        else
            logInfo("starting execution of subworkflow step");
        #printf("WorkflowExecutionInstance::executeSubWorkflowStep(stepid: %y)\n", stepid);

        if (exists ostat) {
            # first get subworkflow_instanceid
            *hash<auto> swfq;
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();

                    swfq = sqlif.workflowInstanceExecuteSubWorkflowStep(workflow_instanceid, stepid, ind);
                    QDBG_TEST_CLUSTER_FAILOVER();
                }
                catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex))
                        continue;
                    rethrow;
                }
                trans.reset();
                break;
            }

            if (swfq) {
                # if corrected is set, the set the status to WAITING
                if (swfq.corrected) {
                    logInfo("subworkflow corrected=1, setting status to 'W' (WAITING)");
                    # have to try to update the subworkflow queue in case the entry was deleted if, for example,
                    # the attach logic failed in the subworkflow segment in the parent workflow
                    SM.updateSubWorkflowQueue(wf.workflowid, workflow_instanceid, stepid, ind, tld.wfe.priority, swfq.subworkflow_instanceid, tld.wfe.parent_info, OMQ::StatComplete);
                    return OMQ::StatWaiting;
                }

                # if the status is RETRY, then we try to set the child workflow to RETRY as well
                if (ostat == OMQ::StatRetry) {
                    # now we try to update the subworkflow's status to RETRY
                    try {
                        SM.retryWorkflowInstance(swfq.subworkflow_instanceid);
                    }
                    catch (hash<ExceptionInfo> ex) {
                        #printf("ex: %N\n", ex);
                        if (ex.arg.err == "STATUS-ERROR") {
                            if (ex.arg.status == OMQ::StatComplete) {
                                logInfo("subworkflow order instance %d is already 'C' (COMPLETE)", swfq.subworkflow_instanceid);
                                # have to try to update the subworkflow queue in case the entry was deleted if, for example,
                                # the attach logic failed in the subworkflow segment in the parent workflow
                                SM.updateSubWorkflowQueue(wf.workflowid, workflow_instanceid, stepid, ind, tld.wfe.priority, swfq.subworkflow_instanceid, tld.wfe.parent_info, OMQ::StatComplete);
                                return OMQ::StatWaiting;
                            }
                            else if (inlist(ex.arg.status, (OMQ::StatInProgress, OMQ::StatReady, OMQ::StatScheduled, OMQ::StatRetry))) {
                                logInfo("subworkflow order instance %d is '%s' (%s)", swfq.subworkflow_instanceid, OMQ::StatMap.(ex.arg.status), ex.arg.status);
                                return OMQ::StatWaiting;
                            }
                            logInfo("subworkflow order instance %d cannot be set to 'R' (RETRY) from status '%s'",
                                    swfq.subworkflow_instanceid, ex.arg.status);
                            return OMQ::StatError;
                        }
                        else if (ex.arg.err == "SEGMENT-ERROR") {
                            logInfo("subworkflow order instance %d cannot be set to 'R' (RETRY) because it has no segments that can be retried (workflow order status: '%s')", swfq.subworkflow_instanceid, ex.arg.status);
                            return OMQ::StatError;
                        }

                        # if the status isn't already RETRY
                        if (ex.arg.status != OMQ::StatRetry) {
                            logInfo("could not set subworkflow order instance %d to 'R' (RETRY), unexpected exception: %s: %s: %s", swfq.subworkflow_instanceid, get_ex_pos(ex), ex.err, ex.desc);
                            return OMQ::StatError;
                        }
                    }

                    logInfo("set subworkflow order instance %d to 'R' (RETRY)", swfq.subworkflow_instanceid);
                    return OMQ::StatWaiting;
                }

                logInfo("already bound to subworkflow order instance %d, step status is '%s' (%s), not re-executing step",
                    swfq.subworkflow_instanceid, OMQ::StatMap{ostat}, ostat);
                return ostat;
            }
            logInfo("subworkflow has not yet been created and bound to step, re-executing step");
        }

        if (!exists stat) {
            # to enable subworkflow binding
            tld.subWorkflow = True;

            # execute step logic
            try {
                wf.runStepPrimaryArgs(stepid, array[ind]);
            } catch (hash<ExceptionInfo> ex) {
                # log complete exception info
                logInfo(Util::get_exception_string(ex));

                # treat exceptions as errors
                stepError(ex.err, ex.desc, ex.arg);
            }

            *softint swfiid = tld.subWorkflowInstanceID;

            # if no error was raised and no key was submitted, then raise an error
            if (!tld.stepError && !swfiid) {
                stepError("NO-SUBWORKFLOW-STARTED", wf.stepinfo{stepid}.name);
            }
        }
    } catch (hash<ExceptionInfo> ex) {
        stepException("QORE-EXCEPTION", sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc));
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
    }
    tld -= ("subWorkflow", "subWorkflowInstanceID");

    # derive status
    if (!stat && !(stat = tld.stepError.status))
        stat = OMQ::StatWaiting;

    return stat;
}

private string OMQ::WorkflowExecutionInstance::executeFrontEndAsyncStep(softstring stepid, int ind, *string ostat, *list<auto> array) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::executeFrontEndAsyncStep index = %y stepid = %y ind = %y", index, stepid, ind);
    softint workflow_instanceid = tld.wfe.workflow_instanceid;

    *string stat;
    *bool has_key;
    bool do_step;
    try {
        if (exists array)
            logInfo("starting execution of async front end array substep [%d]", ind);
        else
            logInfo("starting execution of async front end");
        #printf("WorkflowExecutionInstance::executeFrontEndAsyncStep(stepid: %y)\n", stepid);

        do_step = True;
        *hash<auto> keyq;

        # if we are recovering
        if (exists ostat) {
            # DEBUG
            #logDebug("executeFrontEndAsyncStep() recovering wfiid: %d, stepid: %d", workflow_instanceid, stepid);

            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();

                    keyq = sqlif.getQueueInfo(workflow_instanceid, stepid, ind);
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

            #logDebug("WorkflowExecutionInstance::executeFrontEndAsyncStep(stepid: %y, ind: %y, ostat: %y, array: %y) keyq: %y", stepid, ind, ostat, array, keyq);
            # ignore queue data with 'X' status
            if (keyq.queue_data_status == 'X')
                delete keyq;

            # if we should skip the step; check directly in workflow entry cache
            if (tld.wfe.steps{stepid}[ind].skip) {
                if (!exists keyq) {
                    tld.skipAsync = True;
                    logInfo("step has been flagged to be skipped, skipping step execution");
                } else {
                    correctSystemQueueEntry(workflow_instanceid, stepid, ind, keyq.queuekey);
                    logInfo("step has been flagged to be skipped, skipping step execution (correcting queue entry %y)", keyq.queuekey);
                }

                return OMQ::StatAsyncWaiting;
            }

            # if the key exists, then skip recovery
            if (keyq.queue_data_status == SQL_QS_Received) {
                logInfo("data with key %y already queued with status RECEIVED (R), requeueing message and skipping recovery", keyq.queuekey);
                if (keyq.data === NULL)
                    delete keyq.data;
                # this message will be discarded if already in the queue
                SM.updateQueueUnlocked(wf.workflowid, stepid, workflow_instanceid, ind, tld.wfe.priority, keyq.corrected, keyq.queuekey, keyq.data, tld.wfe.parent_info);

                return OMQ::StatAsyncWaiting;
            }

            # if we have a validation logic
            if (wf.stepHasValidation(stepid)) {
                # DEBUG
                #logDebug("executeFrontEndAsyncStep() got key: %y, wfiid: %d, stepid: %d", keyq.queuekey, workflow_instanceid, stepid);

                if (exists array)
                    stat = runStepValidation(stepid, keyq.queuekey, array[ind]);
                else
                    stat = runStepValidation(stepid, keyq.queuekey);

                # DEBUG
                #logDebug("executeFrontEndAsyncStep() validation returned: %y, wfiid: %d, stepid: %d", stat, workflow_instanceid, stepid);

                if (exists stat) {
                    # DEBUG
                    #logDebug("executeFrontEndAsyncStep() exists stat: %y, wfiid: %d, stepid: %d", stat, workflow_instanceid, stepid);

                    do_step = False;
                    if (!inlist(stat, (OMQ::StatComplete, OMQ::StatError, OMQ::StatRetry, OMQ::StatAsyncWaiting))) {
                        stepError("INVALID-ASYNC-VALIDATION-STATUS", stat);
                        delete stat;
                    } else {
                        # DEBUG
                        #logDebug("executeFrontEndAsyncStep() inlist stat: %y, wfiid: %d, stepid: %d", stat, workflow_instanceid, stepid);

                        if (stat == OMQ::StatAsyncWaiting && !exists keyq) {
                            logInfo("validation indicated status is 'A' (ASYNC-WAITING), but there is no queue_data, marked step as 'E' (ERROR)");
                            return OMQ::StatError;
                        }

                        if (stat == OMQ::StatComplete) {
                            if (!exists keyq) {
                                logInfo("validation indicated status is 'C' (COMPLETE), skipping step execution");
                                tld.skipAsync = True;
                            } else {
                                logInfo("validation indicated status is 'C' (COMPLETE), skipping step execution (correcting queue entry %y)", keyq.queuekey);
                                correctSystemQueueEntry(workflow_instanceid, stepid, ind, keyq.queuekey);
                            }
                            # DEBUG
                            #logDebug("executeFrontEndAsyncStep() COMPLETE=stat: %y, wfiid: %d, stepid: %d", stat, workflow_instanceid, stepid);

                            return OMQ::StatAsyncWaiting;
                        }

                        if (stat == OMQ::StatRetry) {
                            if (exists tld.retryDelay) {
                                logInfo("validation indicated 'R' (RETRY); retrying step at %y", tld.retryDelay);
                                do_step = False;
                            } else {
                                do_step = True;
                                delete stat;
                                logInfo("validation indicated 'R' (RETRY); retrying step immediately");
                            }
                        } else
                            logInfo("validation indicated status is '%s' (%s), skipping step execution", OMQ::StatMap{stat}, stat);
                    }
                } else if (!exists keyq.queuekey)
                    logInfo("validation logic indicates step should be re-run");
                # DEBUG
                #logDebug("executeFrontEndAsyncStep() no key: %y, stat: %y, wfiid: %d, stepid: %d", keyq.queuekey, stat, workflow_instanceid, stepid);
            }
        }

        if (do_step) {
            if (exists keyq.queuekey) {
                hash<auto> ddh = sqlif.discardQueueDataCheck(wf.stepinfo{stepid}.queueid, keyq.queuekey);
                if (ddh.rowcount)
                    logInfo("step will be re-run, discarded queue entry with key '%s'", keyq.queuekey);
                else {
                    logInfo("failed to discard queue entry with key %y (%y) skipping step execution", keyq.queuekey, ddh);
                    do_step = False;
                }
            }

            if (do_step) {
                # for data submission
                tld.asyncQueueID = wf.stepinfo{stepid}.queueid;
                on_exit remove tld.asyncQueueID;

                # execute front end async logic
                wf.runStepPrimaryArgs(stepid, array[ind]);

                # if no error was raised and no key was submitted, then raise an error
                has_key = !exists tld.asyncQueueID;
            }
        }
    } catch (hash<ExceptionInfo> ex) {
        # log complete exception info
        logInfo(Util::get_exception_string(ex));

        # treat exceptions as errors
        stepError(ex.err, ex.desc, ex.arg);
    }

    if (do_step && !tld.stepError && !has_key) {
        stepError("ASYNC-NO-KEY-SUBMITTED", wf.stepinfo{stepid}.name);
    }

    # derive status
    if (!stat && !(stat = tld.stepError.status))
        stat = OMQ::StatAsyncWaiting;

    return stat;
}

private *string OMQ::WorkflowExecutionInstance::executeBackEndFunction(int segid, softstring stepid, int ind, auto data) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::executeBackEndFunction index = %y segid = %y stepid = %y ind = %y", index, segid, stepid, ind);
    *string rc;

    tld.stepName = wf.stepinfo{stepid}.name;
    tld.stepID = stepid;
    #tld.noerror = True;

    if (wf.stepinfo{stepid}.arraytype != OMQ::ArrayNone)
        rc = executeBackEndArrayFunction(segid, stepid, ind, data);
    else
        rc = executeBackEndNormalFunction(segid, stepid, data);

    tld -= ("stepName", "stepID", "stepError", "attachInProgress", "ind");

    if (rc == OMQ::StatComplete)
        delete rc;

    return rc;
}

private string OMQ::WorkflowExecutionInstance::executeBackEndArrayFunction(int segid, softstring stepid, int ind, auto data) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::executeBackEndArrayFunction index = %y segid = %y stepid = %y ind = %y", index, segid, stepid, ind);
    #softint workflow_instanceid = tld.wfe.workflow_instanceid;
    tld.ind = ind;

    *string rc;
    try {
        logInfo("starting execution of async back end logic for step %s for array substep index [%d]", wf.stepinfo{stepid}.name, ind);

        # now execute the array logic
        *softlist<auto> array;
        try {
            array = wf.runStepArray(stepid);
            if (tld.stepError) {
                logInfo("array logic for step %y raised an error", wf.stepinfo{stepid}.name);
                return OMQ::StatError;
            }
        } catch (hash<ExceptionInfo> ex) {
            # log complete exception info
            logInfo(Util::get_exception_string(ex));

            return OMQ::StatError;
        }

        auto old_array_element = tld.arrayElement;
        tld.arrayElement = array[ind];
        on_exit tld.arrayElement = old_array_element;

        # execute back end logic
        wf.runStepAsyncEndArgs(stepid, data, array[ind]);

        # set step with in segment with front-end logic top error
        rc = tld.stepError.status;
    } catch (hash<ExceptionInfo> ex) {
        # log complete exception info
        logInfo(Util::get_exception_string(ex));

        # treat exceptions as errors
        rc = stepError(ex.err, ex.desc, ex.arg);
    }
    if (!exists rc)
        rc = OMQ::StatComplete;
    logInfo("step completed with status '%s' (%s) (backend async array)", OMQ::StatMap{rc}, rc);
    return rc;
}

private string OMQ::WorkflowExecutionInstance::executeBackEndNormalFunction(int segid, softstring stepid, auto data) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::executeBackEndNormalFunction index = %y segid = %y stepid = %y", index, segid, stepid);
    #softint wfiid = tld.wfe.workflow_instanceid;
    tld.ind = 0;

    *string rc;
    try {
        logInfo("starting execution of async back end logic for step %s", wf.stepinfo{stepid}.name);
        # execute back end logic
        wf.runStepAsyncEndArgs(stepid, data);

        # set step with in segment with front-end logic top error
        rc = tld.stepError.status;
    } catch (hash<ExceptionInfo> ex) {
        # log complete exception info
        logInfo(Util::get_exception_string(ex));

        # treat exceptions as errors
        rc = stepError(ex.err, ex.desc, ex.arg);
    }
    if (!exists rc)
        rc = OMQ::StatComplete;

    logInfo("step completed with status '%s' (%s) (backend async)", OMQ::StatMap{rc}, rc);
    return rc;
}

private string OMQ::WorkflowExecutionInstance::execAttach(int segid) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WorkflowExecutionInstance::execAttach index = %y segid = %y", index, segid);
    # set Workflow in thread context
    tld.wf = wf;
    # flag for "we are in WF attach logic call"
    tld.attachInProgress = True;

    # attachIsBlocked is a flag with "user requested a BLOCKED status in attach"
    on_exit
        tld -= ("attachInProgress", "attachIsBlocked", "attachReschedule");

    try {
        logInfo("executing attach handler");

        # execute step logic
        wf.callAttach();
    } catch (hash<ExceptionInfo> ex) {
        # log complete exception info
        logInfo(Util::get_exception_string(ex));

        # treat exceptions as errors
        stepError(ex.err, ex.desc, ex.arg);
    }
    string status;
    if (tld.stepError) {
        status = OMQ::StatError;
        logInfo("attach handler raised an error");

        # register an error with the segment manager so that the segment gets an error status when released
        tld.wfe.setAttachError(segid);

        remove tld.stepError;
    } else {
        if (tld.attachIsBlocked) {
            logInfo("attach handler set BLOCKED status; skipping workflow execution");
            status = OMQ::StatBlocked;
        } else if (tld.attachReschedule) {
            logInfo("attach handler rescheduled order for %y; skipping workflow execution", tld.wfe.reschedule);
            status = OMQ::StatScheduled;
        } else {
            logInfo("attach handler completed successfully");
            status = OMQ::StatComplete;
        }
    }

    return status;
}

private string OMQ::WorkflowExecutionInstance::executeNormalStep(softstring stepid, int ind, *string ostat, *list<auto> array) {
    QDBG_LOG("WorkflowExecutionInstance::executeNormalStep index = %y stepid = %y ind = %y", index, stepid, ind);
    # if initstep, then save in thread_data, so that errors can be logged properly

    *string stat;
    try {
        if (exists array)
            logInfo("starting execution of array substep index [%d]", ind);
        else
            logInfo("starting execution");

        #printf("WorkflowExecutionInstance::executeNormalStep(stepid: %y, ind: %y)\n", stepid, ind);
        #printf("WorkflowExecutionInstance::executeNormalStep() flowdata: %N\n", flowdata);

        # DEBUG
        #if (SM.WFED.(tld.wfe.workflow_instanceid)) logInfo("DEBUG: WorkflowExecutionInstance::executeNormalStep(stepid: %d, ind: %d, ostat: %y) wfe.steps.%y: %y", stepid, ind, ostat, stepid, tld.wfe.steps{stepid});

        # if we are recovering
        if (exists ostat) {
            WFEntry wfe = tld.wfe;
            # if step is flagged to be skipped; check directly in workflow entry cache
            if (wfe.steps{stepid}[ind].skip) {
                logInfo("step has been flagged to be skipped - skipping step execution");
                return OMQ::StatComplete;
            } else if (wf.stepHasValidation(stepid)) {
                stat = runStepValidation(stepid, array[ind]);
                if (!stat)
                    logInfo("validation indicated that the step should be rerun");
                else if (stat == OMQ::StatRetry) {
                    logInfo("validation indicated that the step should be retried");
                    delete stat;
                } else if (!inlist(stat, (OMQ::StatComplete, OMQ::StatError))) {
                    stepError("INVALID-VALIDATION-STATUS", stat);
                    logInfo("setting step status to ERROR");
                    return OMQ::StatError;
                } else {
                    logInfo("validation indicated status '%s', skipping step execution", stat);
                    return stat;
                }
            }
        }

        # execute step logic
        wf.runStepPrimaryArgs(stepid, array[ind]);
    } catch (hash<ExceptionInfo> ex) {
        # log complete exception info
        logInfo(Util::get_exception_string(ex));

        # treat exceptions as errors
        stepError(ex.err, ex.desc, ex.arg);
    }

    # return step status
    return tld.stepError ? tld.stepError.status : OMQ::StatComplete;
}

private string OMQ::WorkflowExecutionInstance::handleStepStatus(string mode, softint segid, softstring stepid,
        int ind = 0, string status, bool arrayStep) {
    QDBG_LOG("WorkflowExecutionInstance::handleStepStatus index = %y mode = %y segid = %y stepid = %y ind = %y "
        "status = %y", index, mode, segid, stepid, ind, status);

    if (!arrayStep &&
        status != OMQ::StatError &&
        status != OMQ::StatCanceled &&
        status != OMQ::StatRetry) {
        tld.wfe.markStepComplete(mode, segid, stepid);
    }

    try {
        if (status == OMQ::StatCanceled) {
            status = OMQ::StatError; # a STEP cannot go to Canceled, only the entire WF
        }

        WFEntry wfe = tld.wfe;
        status = wfe.commitStepStatus(segid, stepid, ind, status, wf.getOption("max-retries"),
            wf.getOption("max-async-retries"));
        if (status == OMQ::StatError && sync_wfiid)
            setStop();
    } catch (hash<ExceptionInfo> ex) {
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
    }

    return status;
}

private OMQ::WorkflowExecutionInstance::checkSeverity(string newv, reference status, *string err, *string desc) {
    QDBG_ASSERT(ensure_tld());
    if (OMQ::ErrorSeverityOrder{newv} > OMQ::ErrorSeverityOrder.OMQ::ES_Minor) {
        # flag fatal error
        if ((OMQ::ErrorSeverityOrder{newv} >= OMQ::ErrorSeverityOrder.OMQ::ES_Fatal)
                || tld.inOneTimeInit) {
            # DEBUG
            #printf("FATAL ERROR %y\n", newv);
            fatal_error = True;
            if (!tld.inOneTimeInit)
                setStop(NOTHING, sprintf("fatal error %y", newv));
        }
        # if step status is already ERROR, then do not update further
        if (tld.stepError.status == OMQ::StatError)
            return;

        # update step error status in thread data
        tld.stepError = (
                "status": status,
                "err": err,
                "desc": desc,
                );
    }
    else
        delete status;
}

int sub workflow_sleep(softint s) {
    return cast<WorkflowExecutionInstance>(Qorus.control.execHash{tld.index}).usleep(s * 1000000);
}

int sub workflow_usleep(softint s) {
    return cast<WorkflowExecutionInstance>(Qorus.control.execHash{tld.index}).usleep(s);
}

int sub workflow_usleep(date s) {
    return cast<WorkflowExecutionInstance>(Qorus.control.execHash{tld.index}).usleep(get_duration_microseconds(s));
}
