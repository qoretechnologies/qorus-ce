# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus WFEntry class definition
#
# Cached workflow instance implementaion

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

public namespace OMQ;

const OMQ::WF_ATTACH_NEED = 0;
const OMQ::WF_ATTACH_DONE = 1;
const OMQ::WF_ATTACH_BLCK = 2;

# WFEntry caches workflow instance status and data
class OMQ::WFEntry inherits Qore::Serializable {
    private {
        transient Mutex lck();
        transient Mutex mAttach();         # atomic "attach function executed" lock
        transient Mutex mKey();            # order key synchronization lock
        bool needsAttach = True;

        # transition condition variable
        transient Condition tcond();
        # transition flag
        bool tflag = False;

%ifdef QorusDebugInternals
        string transition_who;
        list<auto> transition_stack;
%endif

        # transition wait counter
        int tcount = 0;

        # async segment hash
        hash aseg;

        # is this workflow data being executed synchronously?
        bool sync = False;
        # is the workflow instance row marked as synchronous?
        bool dbsync = False;

        # info about running flows
        hash flows;
    }

    public {
        date cached = now_us();

        # dynamic data structure
        InstanceData ddata();
        # temporary data structure
        InstanceData tdata();
        # sensitive data
        SensitiveInstanceData sensitive_data();
        # step data
        StepData step_data();

        *hash<auto> sdata = {};    # static data
        int refs = 1;
        list errors = ();
        transient Workflow wf;
        softstring workflowid;
        softstring workflow_instanceid;
        string initstatus;
        *hash parent_info;
        *string external_order_instanceid;
        *hash orderKeys;
        *string dbstatus;        # the status in the database
        *string status;          # the currently-cached workflow status
        *string status_orig;     # original status for StatBlocked
        hash business_error;
        list seg;
        hash steps;
        bool need_errors;
        bool need_subworkflow;
        # step summary hash: stepid -> status -> count
        hash<string, hash<string, int>> ssh;
        # stepid -> list of Condition variables per step index
        transient hash<string, list<Condition>> stepsync;
        OrderInstanceNotes orderInstanceNotes;
        *string custom_status;   # custom status in the WORKFLOW_INSTANCE
        *date reschedule;
        int priority;
        date started;            # this should correspond to the field WORKFLOW_INSTANCE.STARTED
        *date completed;

        # issue #2294: track counts for COMPLETE status notifications
        # number of errors with severoty >= MAJOR raised against the order; includes RETRY errors
        int error_count = 0;
        # number of RETRY errors with severoty >= MAJOR
        int retry_count = 0;

        # has a workflow exec instance already claimed this order for initial processing?
        bool claimed = False;

        # feedback from child workflows
        *hash feedback;

        # operator lock
        *string operator_lock;

        # in progress and waiting status order map
        const WaitingOrderMap = {
            OMQ::StatWaiting: 1,
            OMQ::StatEventWaiting: 2,
            OMQ::StatAsyncWaiting: 3,
            OMQ::StatRetry: 4,
            OMQ::StatInProgress: 5,
        };
    }

    constructor(Workflow n_wf, softstring wfiid, OrderData order, string initstatus, *string initstatus_orig,
            *hash<auto> parent_info, *string custom_status, date started = now_us(), *hash<auto> feedback) {
        # the workflow configuration
        wf = n_wf;
        workflowid = n_wf.workflowid;
        workflow_instanceid = wfiid;

        init(order.scheduled, order.priority, initstatus, initstatus_orig, parent_info, order.external_order_instanceid,
            order.orderkeys, custom_status, started, feedback);

        # setup all order data after initialization
        setupOrderData(order);

        orderInstanceNotes = new OrderInstanceNotes();

        #log(LoggerLevel::DEBUG, "DEBUG: WFEntry::constructor() wfiid: %y stack: %N", wfiid, get_stack());
%ifdef QorusDebugInternals
%ifdef QorusCore
        # DBG
        if (SM.SWD{workflowid} instanceof RemoteSegmentWorkflowData) {
            qlog(LoggerLevel::INFO, "DBG: CACHE ERROR: %N\nstack: %N", hash(self) - "wf", get_stack());
        }
%endif
%endif
    }

    nothing resetAvailableSteps(string mode, softint segid) {
        QDBG_LOG("WFEntry::resetAvailableSteps mode %y segid %y: %y", mode, segid, wf.segment[segid].steps);
        lck.lock();
        on_exit lck.unlock();
        # FIXME: lock is not necessary here, since the per-segment threads should not
        # be competing here. --PQ 20-Jun-2016
        flows{mode}.segment[segid].steps = wf.segment[segid].steps;
    }

    list<string> getAvailableSteps(string mode, int segid) {
        # FIXME could use per-mode and per-segment RW lock, since we only need to sync on
        # threads working together on one segment. --PQ 20-Jun-2016
        list<string> avail = ();
        lck.lock();
        on_exit {
            lck.unlock();
            QDBG_LOG("WFEntry::getAvailableSteps mode %y segid %y: %y", mode, segid, avail);
        }

        foreach string s in (keys flows{mode}.segment[segid].steps) {
            if (!elements flows{mode}.segment[segid].steps{s})  {
                #log(LoggerLevel::DEBUG, "adding stepid %d steps: %y", s, flows{mode}.segment[segid].steps);
                # add available step to list
                avail += s;
                # remove step from dependency list
                delete flows{mode}.segment[segid].steps{s};
            }
        }
        return avail;
    }

    nothing markStepComplete(string mode, softint segid, softstring stepid) {
        # FIXME could use per-mode and per-segment RW lock, since we only need to sync on
        # threads working together on one segment. --PQ 20-Jun-2016
        lck.lock();
        on_exit {
            lck.unlock();
            QDBG_LOG("WFEntry::markStepComplete mode %y segid %y stepid %y: %y", mode, segid, stepid, flows{mode}.segment[segid].steps);
        }

        delete flows{mode}.segment[segid].steps{stepid};

        # remove step from all other dependency lists
        map remove_from_list(\flows{mode}.segment[segid].steps{$1}, stepid),
            flows{mode}.segment[segid].steps.keyIterator();
    }

    hash<auto> getHash() {
        hash<auto> rv;
        # issue #2759: get data atomically to avoid race conditions with transitional states of ssh for example
        {
            lck.lock();
            on_exit lck.unlock();
            rv = hash(self) + {
                "status": getOnlineOrderStatusUnlocked(),
                "sync": sync,
            };
        }
        return rv;
    }

    hash<auto> getDebugHash() {
        return self{
            "cached",
            "refs",
            "workflowid",
            "workflow_instanceid",

            "initstatus",
            "parent_info",
            "external_order_instanceid",
            "orderKeys",
            "dbstatus",
            "status",
            "status_orig",
            "business_error",
            "seg",
            "steps",
            "need_errors",
            "need_subworkflow",
            "ssh",
            "custom_status",
            "reschedule",
            "priority",
            "started",
            "completed",
            "error_count",
            "retry_count",
            "claimed",
            "feedback",
            "operator_lock",

            "needsAttach",
            "tflag",
            "tcount",
            "aseg",
            "sync",
            "dbsync",
            "flows",

            "errors",

%ifdef QorusDebugInternals
            "transition_who",
            "transition_stack",
%endif
        };
    }

    hash<auto> getInfo(list<string> l) {
        return self{l};
    }

    #! supports ServiceApi::getCallContext()
    hash<auto> getContextInfo() {
        return self{WorkflowOrderCallContextKeys} + {"wf": wf.getContextInfo()};
    }

    binary serializeWithoutTempData(reference<hash<auto>> tdata_ref) {
        tdata_ref = tdata.get();
        remove tdata;
        return serialize();
    }

    setTemporaryData(hash<auto> td) {
        tdata = new InstanceData();
        tdata.initialize(td);
    }

    #! Returns the current order status
    string getOnlineOrderStatus() {
        lck.lock();
        on_exit lck.unlock();
        return getOnlineOrderStatusUnlocked();
    }

    #! Returns the current order status
    private string getOnlineOrderStatusUnlocked() {
        if (status != OMQ::StatInProgress) {
            return status;
        }

        string stat;

        # derive all segment statuses
        int max = elements wf.segment;
        for (int i = 0; i < max; ++i) {
            *string segstat = getOnlineSegmentStatusUnlocked(i);
            QDBG_LOG("WFEntry::getOnlineOrderStatus() wfiid: %y seg: %d -> %y", workflow_instanceid, i, segstat);
            # change READY status to INCOMPLETE to use for calculating the workflow order data status
            if (!exists segstat) {
                continue;
            }

            if (!stat || (WaitingOrderMap{segstat} > WaitingOrderMap{stat})) {
                stat = segstat;
            }
        }

        QDBG_LOG("WFEntry::getOnlineOrderStatus() wfiid: %y returning %y", workflow_instanceid, stat);
        return stat ?? StatInProgress;
    }

    #! returns the segment status for the fgiven segment for an IN-PROGRESS order
    private *string getOnlineSegmentStatusUnlocked(int segid) {
        *string stat;

        # derive segment status from step statuses
        foreach softstring stepid in (wf.segment[segid].steplist) {
            # get step status
            *string s = foldl WaitingOrderMap.$1 > WaitingOrderMap.$2 ? $1 : $2,
                (map $1.status, steps{stepid}, $1.status);
            # only process statuses in WaitingOrderMap
            if (s && WaitingOrderMap{s} && (!exists stat || WaitingOrderMap{s} > WaitingOrderMap{stat})) {
                stat = s;
            }
            QDBG_LOG("WFEntry::getOnlineOrderStatus() wfiid: %y seg: %d step %y: %y", workflow_instanceid, segid,
                stepid, ssh{stepid});
            QDBG_LOG("WFEntry::getOnlineOrderStatus() wfiid: %y seg: %d step %d -> %y", workflow_instanceid, segid,
                stepid, s);
        }

        # if there are no steps, then return the current segment's status
        if (!stat && WaitingOrderMap{seg[segid].status}) {
            stat = seg[segid].status;
        }

        return stat;
    }

    static string getContextStepIdString() {
        *softstring stepid = tld.stepID;
        if (!stepid) {
            throw "CONTEXT-ERROR", "this API can only be called from a workflow step";
        }
        return stepid;
    }

    static Workflow getContextWorklow() {
        *Workflow wf = tld.wfe.wf ?? tld.wf;
        if (!wf) {
            throw "CONTEXT-ERROR", "this API can only be called from a workflow step";
        }
        return wf;
    }

    static auto getConfigItemValue(string item, *hash<auto> local_context, bool expand_complex_values = True) {
        return WFEntry::getContextWorklow().getConfigItemValue(WFEntry::getContextStepIdString(), item, local_context, expand_complex_values);
    }

    static hash<auto> getConfigItemHash(*hash<auto> local_context) {
        return WFEntry::getContextWorklow().getConfigItemHash(WFEntry::getContextStepIdString(), local_context);
    }
}

OMQ::WFEntry::constructor(Workflow n_wf, softstring wfiid) {
    # the workflow configuration
    wf = n_wf;
    workflowid = n_wf.workflowid;
    workflow_instanceid = wfiid;

    # start with the transition flag set
    tflag = True;

%ifdef QorusDebugInternals
    transition_who = sprintf("TID %d: WFEntry::constructor()", gettid());
    transition_stack = get_stack();
%endif

    orderInstanceNotes = new OrderInstanceNotes(wfiid);

    #log(LoggerLevel::DEBUG, "DEBUG: WFEntry::constructor() wfiid: %y stack: %N", wfiid, get_stack());
    # NOTE: orders for wfs with the remote flag set can be cached in qorus-core if the wf is not running
    # and an order has an un/cancel or un/block action run on it
%ifdef QorusDebugInternals
%ifdef QorusCore
    # DBG
    if (SM.SWD{workflowid} instanceof RemoteSegmentWorkflowData) {
        QDBG_LOG("cache order for remote wf %s v%s (%d) wfiid %d in qorus-core", wf.name, wf.version, workflowid, wfiid);
    }
%endif
%endif
    #log(LoggerLevel::INFO, "DEBUG: WFEntry::constructor() %y", hash(self) - "wf");
}

%ifdef QorusDebugInternals
OMQ::WFEntry::destructor() {
    #log(LoggerLevel::DEBUG, "WFEntry::destructor() wfiid: %y stat: %y refs: %y pi: %y stack: %N", workflow_instanceid, status, refs, parent_info, get_stack());
    if (tflag)
        throw "WFENTRY-ERROR", sprintf("tflag = True: %N", self);
}
%endif

OMQ::WFEntry::setSynchronousFlag() {
    sync = dbsync = True;
}

bool OMQ::WFEntry::getSynchronousFlag() {
    return sync;
}

OMQ::WFEntry::clearSynchronousFlag() {
    sync = False;
}

# always called under the owning SegmentWorkflowData's write lock
WFEntry::finalizeTransition() {
    tflag = False;

%ifdef QorusDebugInternals
    remove transition_who;
    remove transition_stack;
%endif

    if (tcount) {
        tcond.broadcast();
    }
}

# called in either the read or write lock
bool WFEntry::waitTransition(RWLock rwl) {
    if (tflag) {
        ++tcount;
        tcond.wait(rwl);
        # the current object could be deleted here
        if (self)
            --tcount;
        return True;
    }
    return False;
}

# always called in the owning SegmentWorkflowData's write lock
bool OMQ::WFEntry::derefWorkflowDelete(reference stat) {
    if (status == OMQ::StatBlocked || status == OMQ::StatCanceled)
        stat = status;

    QDBG_LOG("WFEntry::derefWorkflowDelete status %y wfiid %d refs %d->%d", status, workflow_instanceid, refs, refs - 1);
    if (!--refs) {
        tflag = True;

%ifdef QorusDebugInternals
        transition_who = sprintf("TID %d: WFEntry::derefWorkflowDelete()", gettid());
        transition_stack = get_stack();
%endif

        return True;
    }
    return False;
}

OMQ::WFEntry::init(*date n_reschedule, softint n_priority, string n_initstatus, *string n_initstatus_orig,
                   *hash n_parent_info, *string n_external_order_instanceid, *hash n_orderkeys,
                   *string n_custom_status, date n_started = now_us(), *hash n_feedback, *string n_operator_lock,
                   *int errors, *int retries) {
    dbstatus = status = initstatus = n_initstatus;
    status_orig                = n_initstatus_orig;
    parent_info                = n_parent_info;
    external_order_instanceid  = n_external_order_instanceid;
    orderKeys                  = n_orderkeys;
    custom_status              = n_custom_status;
    operator_lock              = n_operator_lock;
    priority                   = n_priority;
    reschedule                 = n_reschedule;
    started                    = n_started;
    feedback                   = n_feedback;

    # issue #1434: ensure that no order key is assigned to an empty list
    foreach hash<auto> i in (n_orderkeys.pairIterator()) {
        if (i.value.typeCode() == NT_LIST && !i.value) {
            remove orderKeys{i.key};
        }
    }

    if (errors) {
        error_count = errors;
    }
    if (retries) {
        retry_count = retries;
    }

    QDBG_LOG("WFEntry::init() wfiid %y parent_info: %y order keys: %y", workflow_instanceid, parent_info, orderKeys);
}

OMQ::WFEntry::setTempData(hash tempdata) {
%ifdef QorusDebugInternals
    if (tdata.get())
        throw "WFENTRY-SETTEMPDATA-ERROR", sprintf("cannot set tempdata for wfiid %d; already set: %y", workflow_instanceid, tdata.get());
%endif
    tdata.initialize(tempdata);
}

*hash<auto> OMQ::WFEntry::getFlushInfo() {
    # DEBUG
    if (status == OMQ::StatInProgress)
        throw "STATUS-ERROR", sprintf("DEBUG: calling WFEntry::getFlushInfo() while IN-PROGRESS: %y\nstack: %N", self, get_stack());

    if (status == OMQ::StatReady) {
        #log(LoggerLevel::FATAL, "DEBUG: WFEntry::destructor(): status: %y self: %y", status, self);
        return;
    }

    if (reschedule < now_us())
        remove reschedule;

    hash<auto> h;

    # issue #3053: order instance notes are always saved when added; then never need to be flushed

    # get segment changes to flush to the DB
    h.segments = ();
    for (int segid = 0; segid < elements seg; ++segid) {
        # bug 486: qorus cannot recover an order with a gap in the segment list
        if (!seg[segid].val())
            continue;

        # Don't leave it in status I. Use Y in the case of BLOCKED wf instance. Only for "blocked in attach()"
        if (status == OMQ::StatBlocked && seg[segid].status == OMQ::StatInProgress && tld.attachInProgress)
            seg[segid].status = OMQ::StatReady;

        if (seg[segid].status != seg[segid].dbstatus) {
            *date retry_delay;
            *hash<auto> rd = seg[segid].rd;

            # DEBUG
            #log(LoggerLevel::DEBUG, "DEBUG: update segment wfiid=%d segid=%d '%s' rd: %y (%y)", workflow_instanceid,
            #    segid, OMQ::StatMap.(seg[segid].status), rd, steps.(rd.stepid)[rd.ind]);
            if (seg[segid].status == OMQ::StatInProgress)
                wf.logFatal("DEBUG: segment released and updated with status IN-PROGRESS, wfiid=%d, segid=%d, "
                    "stat: %y, dbstat: %y, stack: %y", workflow_instanceid, segid, seg[segid].status,
                    seg[segid].dbstatus, get_stack());

            # check if we should commit a fixed retry time
            if (rd) {
                if (inlist(seg[segid].status, (OMQ::StatRetry, OMQ::StatAsyncWaiting))
                    && inlist(steps.(rd.stepid)[rd.ind].status, (OMQ::StatRetry, OMQ::StatAsyncWaiting)))
                    retry_delay = rd.delay;
            }

            h.segments += {
                "segmentid": segid,
                "segmentstatus": OMQ::StatMap.(seg[segid].status),
                "custom_status": seg[segid].custom_status,
                "retry_delay": retry_delay,
            };
        }
    }

    # get step changes to flush to the DB
    h.steps = ();
    foreach string stepid in (keys steps) {
        for (int ind = 0; ind < elements steps{stepid}; ++ind) {
            # Don't leave it in status 'I'; use R in the case of BLOCKED wf instance. Only for "blocked in attach()"
            if (status == OMQ::StatBlocked && steps{stepid}[ind].status == OMQ::StatInProgress && tld.attachInProgress) {
                # issue #2759 update status counts
                QDBG_ASSERT(ssh{stepid}{OMQ::StatInProgress} > 0);
                if (!(--ssh{stepid}{OMQ::StatInProgress})) {
                    remove ssh{stepid}{OMQ::StatInProgress};
                }
                ++ssh{stepid}{OMQ::StatRetry};
                #QDBG_LOG("WFEntry::getFlushInfo() wfiid %d stepid %y [%d] %y: %d -> %d", workflow_instanceid, stepid,
                #    ind, StatInProgress, ssh{stepid}{StatInProgress} + 1, ssh{stepid}{StatInProgress});
                #QDBG_LOG("WFEntry::getFlushInfo() wfiid %d stepid %y [%d] %y: %d -> %d", workflow_instanceid, stepid,
                #    ind, StatRetry, ssh{stepid}{StatRetry} - 1, ssh{stepid}{StatRetry});
                steps{stepid}[ind].status = OMQ::StatRetry;
            }

            if (steps{stepid}[ind].dbstatus != steps{stepid}[ind].status) {
                # DEBUG
                #log(LoggerLevel::DEBUG, "DEBUG: update step wfiid=%d step=%d/%d '%s' retries=%d",
                #    workflow_instanceid, stepid, ind, OMQ::StatMap.(steps{stepid}[ind].status),
                #    steps{stepid}[ind].retries);
                if (steps{stepid}[ind].status == OMQ::StatInProgress)
                    wf.logFatal("DEBUG: step released and updated with status IN-PROGRESS, wfiid=%d step=%d/%d, "
                        "stat: %y, dbstat: %y", workflow_instanceid, stepid, ind, steps{stepid}[ind].status,
                        steps{stepid}[ind].dbstatus);

                h.steps += {
                    "stepid": stepid,
                    "ind": ind,
                    "stepstatus": OMQ::StatMap.(steps{stepid}[ind].status),
                    "retries": business_error{stepid}{ind} ? -1 : steps{stepid}[ind].retries.toInt(),
                    "custom_status": steps{stepid}[ind].custom_status,
                    "skip": steps{stepid}[ind].skip,
                    "completed": steps{stepid}[ind].completed
                };
            }
            # DEBUG
            else if (steps{stepid}[ind].dbstatus == OMQ::StatInProgress)
                wf.logFatal("DEBUG: step released with db status IN-PROGRESS, wfiid=%d step=%d/%d, stat: %y, "
                    "dbstat: %y", workflow_instanceid, stepid, ind, steps{stepid}[ind].status,
                    steps{stepid}[ind].dbstatus);
        }
    }

    if (dbstatus != status || dbsync) {
        if (status == OMQ::StatComplete)
            delete operator_lock;

        h += {
            "workflowstatus": OMQ::StatMap{status},
            "workflowstatus_orig": OMQ::StatMap{status_orig},
            "business_error": elements business_error ? 1 : NOTHING,
            "custom_status": custom_status,
            "reschedule": reschedule,
            "operator_lock": operator_lock,
        };

        if (dbstatus != status && Qorus.audit.checkOption(OMQ::AOC_WORKFLOW_DATA)) {
            h.audit = {
                "workflowid": workflowid.toInt(),
                "oldstatus": OMQ::StatMap{dbstatus},
                "newstatus": OMQ::StatMap{status},
                "who": "Qorus",
                "source": qorus_get_source(),
            };
        }
    }

    if (h)
        h.workflow_instanceid = workflow_instanceid.toInt();

    return h;
}

OMQ::WFEntry::flushDetach() {
    QDBG_ASSERT(ensure_tld());
    if (status == OMQ::StatReady) {
        #log(LoggerLevel::FATAL, "DEBUG: WFEntry::flushDetach(): status: %y self: %N", status, self);
        return;
    }

    flushDetachIntern();
}

private OMQ::WFEntry::flushDetachIntern(bool in_reset = False) {
    # post "workflow data released" event
    Qorus.events.postWorkflowDataReleased(wf.name, wf.version, wf.workflowid, workflow_instanceid, status,
        elements business_error ? True : False);

    # commit external status if handler exists
    #printf("calling commit_status(%s, %s)\n", external_order_instanceid, status);

    # if there is no detach logic, exit immediately
    if (!wf.hasDetach()) {
        return;
    }

    # if there is a WorkflowInstance object, execute the detach function immediately and return
    if (exists tld.index) {
        if (Qorus.control.execHash.(tld.index).wf.workflowid != workflowid) {
            wf.logFatal("workflow detach called on %s but active exec instance is %s", wf.name,
                Qorus.control.execHash.(tld.index).wf.name);
            qlog(LoggerLevel::FATAL, "DEBUG: %N\n", get_stack());
        } else {
            # BUG 288: save correct WFEntry object in thread-local data before calling detach
            *WFEntry wfe = tld.wfe;
            on_exit tld.wfe = wfe;
            tld.wfe = self;

            SM.callDetachIntern(cast<WorkflowExecutionInstance>(Qorus.control.execHash.(tld.index)), status, external_order_instanceid);
            return;
        }
    }

    # use the SegmentManager to setup a temporary workflow and run the detach function
    SM.runDetach(self, in_reset, workflowid, workflow_instanceid, status, external_order_instanceid);
}

OMQ::WFEntry::flushStatus(bool in_reset = False, *hash cx) {
    QDBG_ASSERT(ensure_tld());
    # DEBUG
    #log(LoggerLevel::FATAL, "DEBUG: WFEntry::flushStatus() wfiid: %y status: %y status_orig: %y", workflow_instanceid, status, status_orig);
    #log(LoggerLevel::FATAL, "stack: %y", get_stack());

    # bug 367: do not flush synchronous workflow status during a workflow reset
    if (in_reset && sync)
        return;

    # DEBUG
    if (status == OMQ::StatInProgress)
        throw "STATUS-ERROR", sprintf("DEBUG: calling WFEntry::flushStatus() while IN-PROGRESS: %y", self);

    if (status == OMQ::StatReady) {
        #log(LoggerLevel::FATAL, "DEBUG: WFEntry::destructor(): status: %y self: %y", status, self);
        return;
    }

    if (reschedule < now_us())
        remove reschedule;

    # segment changes list
    list segl;
    # step changes list
    list stepl;

    # to make atomic changes in notes in a restartable transaction
    OrderInstanceNotesHelper oinh(orderInstanceNotes);

    # update the workflow order data instance
    list l;
    QorusRestartableTransaction trans();
    while (True) {
        try {
            # cleanup at block end
            on_error omqp.rollback();
            on_success omqp.commit();

            # NOTE: this transaction is restartable

            # standalone transaction handling
            l = oinh.saveNoCommit(workflow_instanceid);

            # update segments
            for (int segid = 0; segid < elements seg; ++segid) {
                # bug 486: qorus cannot recover an order with a gap in the segment list
                if (!seg[segid].val())
                    continue;

                # Don't leave it in status I. Use Y in the case of BLOCKED wf instance. Only for "blocked in attach()"
                if (status == OMQ::StatBlocked && seg[segid].status == OMQ::StatInProgress && tld.attachInProgress)
                    segl += ("segid": segid, "update": ("status": OMQ::StatReady));

                if (seg[segid].status != seg[segid].dbstatus) {
                    *date retry_delay;
                    *hash rd = seg[segid].rd;

                    # DEBUG
                    #wf.logDebug("DEBUG: update segment wfiid=%d segid=%d '%s' rd: %y (%y)", workflow_instanceid, segid, OMQ::StatMap.(seg[segid].status), rd, steps.(rd.stepid)[rd.ind]);
                    if (seg[segid].status == OMQ::StatInProgress)
                        wf.logFatal("DEBUG: segment released and updated with status IN-PROGRESS, wfiid=%d, segid=%d, stat: %y, dbstat: %y, stack: %y", workflow_instanceid, segid, seg[segid].status, seg[segid].dbstatus, get_stack());

                    # check if we should commit a fixed retry time
                    if (exists rd) {
                        if (inlist(seg[segid].status, (OMQ::StatRetry, OMQ::StatAsyncWaiting))
                            && inlist(steps.(rd.stepid)[rd.ind].status, (OMQ::StatRetry, OMQ::StatAsyncWaiting)))
                            retry_delay = rd.delay;
                    }

                    sqlif.updateSegment(workflow_instanceid, segid, OMQ::StatMap.(seg[segid].status), seg[segid].custom_status, retry_delay);
                    segl += ("segid": segid, "update": ("dbstatus": seg[segid].status));
                }
                # DEBUG
                else if (seg[segid].dbstatus == OMQ::StatInProgress) {
                    wf.logFatal("DEBUG: segment released with db status IN-PROGRESS, wfiid=%d, segid=%d, stat: %y, dbstat: %y, stack: %y", workflow_instanceid, segid, seg[segid].status, seg[segid].dbstatus, get_stack());
                }
            }

            # update steps
            foreach string stepid in (keys steps) {
                for (int ind = 0; ind < elements steps{stepid}; ++ind) {
                    # Don't leave it in status 'I'; use R in the case of BLOCKED wf instance. Only for "blocked in attach()"
                    if (status == OMQ::StatBlocked && steps{stepid}[ind].status == OMQ::StatInProgress && tld.attachInProgress)
                        stepl += ("stepid": stepid, "ind": ind, "update": ("status": OMQ::StatReady));

                    if (steps{stepid}[ind].dbstatus != steps{stepid}[ind].status) {
                        #QDBG_LOG("update step wfiid: %d step: %d/%d '%s' retries: %d (%d)", workflow_instanceid, stepid, ind, OMQ::StatMap.(steps{stepid}[ind].status), steps{stepid}[ind].retries, business_error{stepid}{ind} ? -1 : steps{stepid}[ind].retries);
                        if (steps{stepid}[ind].status == OMQ::StatInProgress)
                            wf.logFatal("DEBUG: step released and updated with status IN-PROGRESS, wfiid=%d "
                                "step=%d/%d, stat: %y, dbstat: %y", workflow_instanceid, stepid, ind,
                                steps{stepid}[ind].status, steps{stepid}[ind].dbstatus);

                        sqlif.updateStep(workflow_instanceid, stepid,
                                        ind, OMQ::StatMap.(steps{stepid}[ind].status),
                                        business_error{stepid}{ind} ? -1 : steps{stepid}[ind].retries,
                                        steps{stepid}[ind].custom_status,
                                        steps{stepid}[ind].skip,
                                        steps{stepid}[ind].completed);
                        stepl += ("stepid": stepid, "ind": ind, "update": ("dbstatus": steps{stepid}[ind].status));
                    }
                    # DEBUG
                    else if (steps{stepid}[ind].dbstatus == OMQ::StatInProgress)
                        wf.logFatal("DEBUG: step released with db status IN-PROGRESS wfiid=%d step=%d/%d stat: %y "
                            "dbstat: %y", workflow_instanceid, stepid, ind, steps{stepid}[ind].status,
                            steps{stepid}[ind].dbstatus);
                }
            }

            if (dbstatus != status || dbsync) {
                # issue #2941: ensure that whenever releasing an order with CANCELED or BLOCKED status that the
                # original status is also set
                if ((status == OMQ::StatCanceled || status == OMQ::StatBlocked) && !status_orig) {
                    status_orig = OMQ::StatError;
                }
                if (!sqlif.updateFinalWorkflowStatus(workflow_instanceid, 0,
                                                    OMQ::StatMap{status}, OMQ::StatMap{status_orig},
                                                    elements business_error ? True : NOTHING,
                                                    custom_status, reschedule, operator_lock)) {
                    wf.logInfo("failed to update workflow %s status to '%s' (%s), status or session error",
                        workflow_instanceid, OMQ::StatMap{status}, status);
                    omqp.rollback();
                    return;
                }
                if (dbstatus != status)
                    Qorus.audit.workflowStatusChangeNoCommit(cx, workflowid, workflow_instanceid,
                        OMQ::StatMap{dbstatus}, OMQ::StatMap{status});
            }

            # issue #2273: to alleviate issues with Oracle 12c in some deployments, only delete sensitive data if
            # there is some
            if (!sensitive_data.empty()
                && ((status == OMQ::StatComplete && Qorus.options.get("purge-sensitive-data-complete"))
                    || (status == OMQ::StatCanceled && Qorus.options.get("purge-sensitive-data-canceled")))) {
                deleteOnlineSensitiveData();
            }
            QDBG_TEST_CLUSTER_FAILOVER();
        } catch (hash<ExceptionInfo> ex) {
            # restart the transaction if necessary
            if (trans.restartTransaction(ex)) {
                # clear lists
                delete segl;
                delete stepl;
                continue;
            }
            wf.logFatal("exception committing workflow status for workflow_instanceid %d: %s: %s:",
                workflow_instanceid, ex.err, ex.desc);
            wf.logFatal("workflow_instanceid %d will be left in an inconsistent state and must be recovered manually",
                workflow_instanceid);
            qlog(LoggerLevel::INFO, get_exception_string(ex));
        }
        trans.reset();
        break;
    }
    oinh.applySaved(l);
    if ((dbstatus != status || dbsync)) {
        if (status == OMQ::StatComplete)
            delete operator_lock;
        wf.logInfo("committed workflow status %d = '%s' (%s)", workflow_instanceid, OMQ::StatMap{status}, status);
    } else
        wf.logInfo("committed segment and step status for workflow_instanceid %d = '%s' (%s)", workflow_instanceid,
            OMQ::StatMap{status}, status);

    # issue #2294: register COMPLETE status disposition
    if (status == OMQ::StatComplete) {
        Qorus.orderStats.post(workflowid, workflow_instanceid,
            !error_count ? CS_Clean : (error_count == retry_count ? CS_RecoveredAuto : CS_RecoveredManual),
            ((completed ?? now_us()) - started).durationMicroseconds().toFloat() / 1000000.0);
    }

    if ((status == OMQ::StatComplete || status == OMQ::StatCanceled) && Qorus.options.get("workflow-perf-events")) {
        Qorus.events.postWorkflowPerformance(tld.cx, wf.name, wf.version, wf.workflowid, workflow_instanceid, status,
            !error_count ? CS_Clean : (error_count == retry_count ? CS_RecoveredAuto : CS_RecoveredManual), started,
            completed ?? now_us());
    }

    #wf.logDebug("DBG: seg: %y segl: %y", seg, segl);
    #wf.logDebug("DBG: steps: %y stepl: %y", steps, stepl);

    # apply changes after committing
    map seg[$1.segid] += $1.update, segl;
    map steps{$1.stepid}[$1.ind] += $1.update, stepl;

    flushDetachIntern(in_reset);
}

# transaction handling handled by the caller
OMQ::WFEntry::deleteOnlineSensitiveData() {
    AbstractTable sensitive_order_data_keys = get_sql_table_system("omq", "sensitive_order_data_keys");
    AbstractTable sensitive_order_data = get_sql_table_system("omq", "sensitive_order_data");

    hash dcond = (
        "workflow_instanceid": workflow_instanceid.toInt(),
    );
    int rows = sensitive_order_data_keys.del(dcond);
    if (rows)
        wf.logInfo("%y: rows deleted for workflow_instanceid %d: %d", sensitive_order_data_keys.getName(), workflow_instanceid, rows);
    rows = sensitive_order_data.del(dcond);
    if (rows)
        wf.logInfo("%y: rows deleted for workflow_instanceid %d: %d", sensitive_order_data.getName(), workflow_instanceid, rows);
}

# eeid may be NOTHING if the error was not saved in the DB due to an exception
OMQ::WFEntry::addError(string sev, softstring error, *string desc, *string info, *string status, softbool business = False, *int eeid) {
    # the action is locked in order to avoid a race condition with WFEntry::getDBErrors()
    lck.lock();
    on_exit lck.unlock();

    errors += {
        "error_instanceid" : eeid,
        "retry"            : status == OMQ::StatRetry ? 1 : 0,
        # issue #2903 stepid must always be an int
        "stepid"           : tld.stepID.toInt(),
        "ind"              : tld.ind,
        "severity"         : sev,
        "error"            : error,
        "description"      : desc,
        "info"             : info,
        "business_error"   : business,
        "created"          : now_us(),
    };

    if (sev == ES_Major || sev == ES_Fatal) {
        ++error_count;
        if (status == OMQ::StatRetry) {
            ++retry_count;
        }
    }
}

# returns False = OK, True = error
bool OMQ::WFEntry::claimInitial() {
    lck.lock();
    on_exit lck.unlock();

    if (!claimed) {
        claimed = True;
        return False;
    }

    wf.logInfo("cannot attach to workflow_instanceid %d for initial processing as it's already being processed by another workflow execution instance", workflow_instanceid);
    return True;
}

string OMQ::WFEntry::setWorkflowInProgress() {
    string old_status;
    {
        lck.lock();
        on_exit lck.unlock();

        if (dbstatus !== OMQ::StatInProgress) {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    old_status = setWorkflowInProgressNoCommit();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex))
                        continue;
                    rethrow;
                }
                trans.reset();
                break;
            }
            dbstatus = OMQ::StatInProgress;
        } else {
            old_status = status;
        }

        status = OMQ::StatInProgress;
    }

    # raise system event
    if (old_status != OMQ::StatInProgress) {
        Qorus.events.postWorkflowStatusChanged(NOTHING, wf.name, wf.version, workflowid, workflow_instanceid,
            {"old": old_status, "new": OMQ::StatInProgress});
    }

    return old_status;
}

# unlocked because this method is called only with exclusive access to the WFEntry object
string OMQ::WFEntry::setWorkflowInProgressNoCommit() {
    if (dbstatus === OMQ::StatInProgress)
        return status;

    bool rc = sqlif.setWorkflowInstanceInProgress(workflow_instanceid, Qorus.getSessionId());

    # DEBUG
    if (!rc) {
        string err = sprintf("failed to attach to workflow_instanceid %d (status or session error)", workflow_instanceid);
        wf.logInfo(err);
        #wf.logDebug("DEBUG: rc: %y, sql=%s", rc, sql);
        #wf.logDebug("DEBUG: stack: %y", get_stack());
        throw "WORKFLOW-UPDATE-ERROR", err;
    }

    Qorus.audit.workflowStatusChangeNoCommit(NOTHING, workflowid, workflow_instanceid, OMQ::StatMap{dbstatus}, OMQ::SQLStatInProgress);

    return status;
}

# unlocked because this method is called only with exclusive access to the WFEntry object
OMQ::WFEntry::postSetWorkflowInProgress(string old_status) {
    status = OMQ::StatInProgress;
    dbstatus = OMQ::StatInProgress;

    # issue #2937: issue a system event if the internal status changes
    if (old_status != OMQ::StatInProgress) {
        Qorus.events.postWorkflowStatusChanged(NOTHING, wf.name, wf.version, workflowid, workflow_instanceid,
            {"old": old_status, "new": OMQ::StatInProgress});
    }
}

*hash<auto> OMQ::WFEntry::replaceStaticData(*hash<auto> new_data) {
    # locking needed here to ensure atomicity
    lck.lock();
    on_exit lck.unlock();

    # do not update anything if are data the same
    if (new_data == sdata) {
        return;
    }

    *hash<auto> orig = sdata;

    wf.logInfo("replacing staticdata for workflow_instanceid %d: OLD: %y", workflow_instanceid, orig);
    wf.logInfo("replacing staticdata for workflow_instanceid %d: NEW: %y", workflow_instanceid, new_data);

    string str = serialize_qorus_data(new_data);

    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            sqlif.wfEntryReplaceStaticData(str, workflow_instanceid);
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
    sdata = new_data;

    return orig;
}

*hash<auto> OMQ::WFEntry::replaceDynamicData(*hash new_data) {
    # atomic calls are made below; no locking needed here
    return ddata.replaceAndSave(new_data, workflow_instanceid);
}

hash<DataOpInfo> OMQ::WFEntry::updateDynamicData(*hash new_data) {
    # atomic calls are made below; no locking needed here
    bool updated;
    hash<auto> old_data = ddata.updateAndSave(new_data, workflow_instanceid, \updated);
    return <DataOpInfo>{
        "orig": old_data,
        "updated": updated ?? False,
    };
}

hash<DataOpInfo> OMQ::WFEntry::updateDynamicDataPath(string path, auto value) {
    # atomic calls are made below; no locking needed here
    bool updated;
    hash<auto> old_data = ddata.updatePathAndSave(path, value, workflow_instanceid, \updated);
    return <DataOpInfo>{
        "orig": old_data,
        "updated": updated ?? False,
    };
}

OMQ::WFEntry::replaceSensitiveData(string skey, string svalue, hash data, *softlist aliases, *hash meta) {
    # atomic calls are made below; no locking needed here
    wf.logInfo("replacing sensitive data for workflow_instanceid %d key %y", workflow_instanceid, skey);
    sensitive_data.replaceAndSave(skey, svalue, data, aliases, meta, workflow_instanceid);
}

*hash<auto> OMQ::WFEntry::replaceStepData(softstring stepid, int ind, *hash<auto> stepdata, *string user) {
    # atomic calls are made below; no locking needed here
    # verify that the step exists
    checkStep(stepid, ind);

    return step_data.replaceAndSave(stepid, ind, stepdata, workflow_instanceid, user);
}

# breaks a lock on a user interaction step and adds a note on the workflow order
/** @return True if the lock was broken, False if not
*/
bool OMQ::WFEntry::breakStepLock(softstring stepid, softint ind, string note) {
    lck.lock();
    on_exit lck.unlock();

    # to make atomic changes in notes in a restartable transaction
    OrderInstanceNotesHelper oinh(orderInstanceNotes);

    # add note
    oinh.add({"note": note});

    list<auto> l;

    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            # update step lock in DB
            if (!sqlif.clearQueueDataLock(workflow_instanceid, stepid, ind)) {
                return False;
            }

            # save all notes and commit transaction immediately
            l = oinh.saveNoCommit(workflow_instanceid);
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
    oinh.applySaved(l);
    return True;
}

private static OMQ::WFEntry::checkOrderKeyValue(string key, auto val) {
    if (!val.strp()) {
        throw "SET-ORDER-KEYS-ERROR", sprintf("value for key %y cannot be converted to a string: type: %y value: %y", key, val.type(), val);
    }
}

hash OMQ::WFEntry::appendOrderKeys(hash new_order_keys, bool truncate) {
    if (!new_order_keys)
        throw "APPEND-ORDER-KEYS-ERROR", sprintf("empty hash passed to wf_append_order_keys()");

    # grab lock here for the duration of the method and only release it when the method is exited
    mKey.lock();
    on_exit mKey.unlock();

    # prepend existing keys to the hash before calling setOrderKeysStatic()
    foreach hash pair_iterator_hash in (new_order_keys.pairIterator()) {
        *softlist<auto> keylist = orderKeys{pair_iterator_hash.key};
        # issue #2299: ensure that duplicates are removed even when there are no existing keys
        # to ensure consistent behavior in all cases; this also serves to convert all values to strings
        *hash<string, bool> key_set = map {$1: True}, keylist;
        map key_set.$1 = True, pair_iterator_hash.value;
        new_order_keys{pair_iterator_hash.key} = key_set.keys();
    }

    return orderKeys = WFEntry::setOrderKeysStatic(workflowid, workflow_instanceid, wf.order_key_map, orderKeys,
        new_order_keys, truncate, "WorkflowApi::appendOrderKeys()");
}

hash OMQ::WFEntry::setOrderKeys(hash key_hash, bool truncate) {
    # grab lock here for the duration of the method and only release it when the method is exited
    mKey.lock();
    on_exit mKey.unlock();

    return orderKeys = WFEntry::setOrderKeysStatic(workflowid, workflow_instanceid, wf.order_key_map, orderKeys,
        key_hash, truncate, "WorkflowApi::setOrderKeys()");
}

static hash<auto> OMQ::WFEntry::setOrderKeysStatic(softint workflowid, softint workflow_instanceid,
        *hash<string, bool> order_key_map, *hash<auto> current_keys, hash<auto> new_keys, bool truncate,
        string call_name, *bool ignore_empty_keys) {
    if (!new_keys)
        throw "SET-ORDER-KEYS-ERROR", sprintf("empty hash passed to %s", call_name);

    list sqlupdate = list sqlinsert = list sqldelete = ();

    # DEBUG take snapshot
    *hash old_keys = current_keys;

    # check for updates
    foreach string k in (keys new_keys) {
        if (!order_key_map{k})
            throw "INVALID-WORKFLOW-KEY", sprintf("%y is not a valid key for this workflow (valid keys: %y)", k,
                keys order_key_map);

        auto val = new_keys{k};

        # check for duplicate values
        # issue #2299 also check for duplicate values with existing keys
        # key set is a hash of bools to simulate a set
        *hash<string, bool> key_set;

        # remove empty keys, if any
        if (ignore_empty_keys) {
            if (val.typeCode() == NT_LIST) {
                val = map $1, val, $1.val();
                # ignore an empty list
                if (!val) {
                    continue;
                }
            } else {
                if (!val.val()) {
                    continue;
                }
            }
        }

        foreach auto key_value in (\val) {
            if (key_set{key_value}) {
                throw "DUPLICATE-KEY-VALUE", sprintf("order key %y has duplicate value %y in the key list", k, key_value);
            } else if (!key_value.val()) {
                throw "SET-ORDER-KEYS-ERROR", sprintf("order key %y has an empty value in the key list", k);
            }
            key_set{key_value} = True;
        }

        if (val.typeCode() == NT_LIST) {
            if (elements val == 1) {
                val = val[0];
            }
        }

        # DEBUG
        #wf.logDebug("setOrderKeys() %s: %y (current: %y)", k, val, current_keys);

        # ignore empty order keys by default
        if (!val.val()) {
            continue;
        }

        # empty list is refused before; any single value that cannot be converted to a
        # non-empty string is refused too. (e.g. zero integer is now accepted)
        if (val.typeCode() != NT_LIST) {
            WFEntry::checkOrderKeyValue(k, val);
        } # else a list of values, which is accepted here - the elements will be checked later

        if (exists current_keys{k}) {
            # find differences in lists
            if (val.typeCode() == NT_LIST) {
                # NOTE: we know the list 'val' is non-empty here!
                if (current_keys{k}.typeCode() != NT_LIST) {
                    WFEntry::checkOrderKeyValue(k, val[0]);
                    sqlupdate += ("key": k, "value": val[0], "oldval": current_keys{k});
                    for (int i = 1; i < elements val; ++i) {
                        WFEntry::checkOrderKeyValue(k, val[i]);
                        sqlinsert += ("key": k, "value": val[i]);
                    }
                } else {
                    # remove common entries from both lists
                    hash vh = map {$1: True}, val;
                    hash oh = map {$1: True}, current_keys{k};

                    vh -= current_keys{k};
                    oh -= val;

                    # delete entries not in new list
                    foreach string v in (keys oh)
                        sqldelete += ("key": k, "value": v);
                    # add new entries
                    foreach string v in (keys vh) {
                        # ignore empty order keys by default
                        if (!v.val())
                            continue;
                        else {
                            WFEntry::checkOrderKeyValue(k, v);
                        }
                        sqlinsert += ("key": k, "value": v);
                    }
                }
            } else {
                if (current_keys{k}.typeCode() != NT_LIST) {
                    if (current_keys{k} != val) {
                        WFEntry::checkOrderKeyValue(k, val);
                        sqlupdate += ("key": k, "value": val, "oldval": current_keys{k});
                    }
                } else {
                    WFEntry::checkOrderKeyValue(k, val);
                    sqlupdate += ("key": k, "value": val, "oldval": current_keys{k}[0]);
                    for (int i = 1; i < elements current_keys{k}; ++i)
                        sqldelete += ("key": k, "value": current_keys{k}[i]);
                }
            }
        } else {
            foreach auto v in (val) {
                WFEntry::checkOrderKeyValue(k, v);
                sqlinsert += ("key": k, "value": v);
            }
        }
        current_keys{k} = val;
    }

    # if no updates are to be made, then return the current keys or an empty hash (possible if the order has no keys and sends a hash with keys but not values or empty lists as values)
    if (!sqldelete && !sqlupdate && !sqlinsert)
        return current_keys ?? {};

    #wf.logDebug("new_keys: %y\nold: %y\ncurrent: %y\ndel: %y\nupd: %y\nins: %y", new_keys, old_keys, current_keys, sqldelete, sqlupdate, sqlinsert);

    QorusRestartableTransaction trans();
    while (True) {
        try {
            # commit on success, rollback on exception
            on_error omqp.rollback();
            on_success omqp.commit();

            # if we need to do deletes
            map sqlif.deleteOrderKey(workflow_instanceid, $1.key, $1.value), sqldelete;
            # if we need to do an update
            map sqlif.updateOrderKey(workflow_instanceid, $1.key, $1.value, $1.oldval, truncate), sqlupdate;
            # if we need to do an insert
            map sqlif.insertOrderKey(workflowid, workflow_instanceid, $1.key, $1.value, truncate), sqlinsert;
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

    # issue #3141: raise an event when order keys are updated
    Qorus.events.postWorkflowDataUpdated(workflowid, workflow_instanceid, "keys");

    return current_keys;
}

auto OMQ::WFEntry::getOrderKeys(*softlist<auto> fl, *reference<bool> missing_input) {
    int ls = fl.lsize();
    if (!ls)
        return orderKeys;

    if (ls == 1) {
        # ensure that a single key is always returned as a single string and not as a list
        # otherwise it can be returned inconsistently depending on how the order keys have been assigned or cached
        auto rv = orderKeys.(fl[0]);
        if (rv.lsize() == 1 && rv.typeCode() == NT_LIST) {
            return rv[0];
        }
        if (!rv && !wf.order_key_map{fl[0]}) {
            missing_input = True;
        }
        return rv;
    }

    return map {$1: orderKeys{$1}}, fl;
}

*string OMQ::WFEntry::releaseWorkflowInstance(reference<int> erri) {
    QDBG_LOG("WFEntry::releaseWorkflowInstance wfid %y wfiid %y", workflowid, workflow_instanceid);
    # grab lock here for the duration of the method and only release it when the method is exited
    lck.lock();
    on_exit lck.unlock();

%ifdef QorusDebugInternals
    # DEBUG
    if (refs < 0 || refs > 5) {
        wf.logDebug("ERROR: WFEntry::releaseWorkflowInstance() refs: %y, self: %y", refs, self);
        qlog(LoggerLevel::FATAL, "DEBUG: %N\n", get_stack());
    }
%endif

    string stat;
    try {
        stat = getFinalWorkflowStatusUnlocked(\erri);

        if (stat == OMQ::StatComplete)
            completed = now_us();

        if (stat != status) {
            Qorus.events.postWorkflowStatusChanged(NOTHING, wf.name, wf.version, workflowid, workflow_instanceid,
                {"old": status, "new": stat});
            status = stat;
        }

        claimed = False;
    } catch (hash<ExceptionInfo> ex) {
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        # rethrow exception
        rethrow;
    }

    return stat;
}

# if the init function must be run, then the lock is held and
# this method returns True.  After the init function is run,
# WFEntry::confirmAttach(), WFEntry::confirmAttachStop(), or
# WFEntry::confirmAttachError() must be run.
# If it's already in BLOCKED state, the attach function is
# blocked too.
int OMQ::WFEntry::needsAttach() {
    mAttach.lock();
    if (status == OMQ::StatBlocked) {
       mAttach.unlock();
       return OMQ::WF_ATTACH_BLCK;
    }
    if (needsAttach)
        return OMQ::WF_ATTACH_NEED;

    mAttach.unlock();
    return OMQ::WF_ATTACH_DONE;
}

private OMQ::WFEntry::setInProgress() {
    # do not set DB workflow data to IN-PROGRESS if status is READY; it will be
    # set to IN-PROGRESS in the same transaction when the initial segment is
    # created in WFEntry::setupInitialSegment()
    if (inlist(status, (OMQ::StatReady, OMQ::StatScheduled))) {
        # issue #2937: issue an event when the internal status changes
        Qorus.events.postWorkflowStatusChanged(NOTHING, wf.name, wf.version, workflowid, workflow_instanceid,
            {"old": status, "new": OMQ::StatInProgress});
        status = OMQ::StatInProgress;
        return;
    }

    setWorkflowInProgress();
}

# unlocks the init lock
OMQ::WFEntry::confirmAttach() {
    needsAttach = False;
    mAttach.unlock();

    # set workflow data in progress if necessary
    setInProgress();
}

# unlocks the init lock
OMQ::WFEntry::confirmAttachStop() {
    needsAttach = False;
    mAttach.unlock();
}

# confirms that no attach was necessary
OMQ::WFEntry::confirmNoAttach() {
    needsAttach = False;

    # set workflow data in progress if necessary
    setInProgress();
}

# unlocks the init lock
OMQ::WFEntry::confirmAttachError() {
    needsAttach = True;
    mAttach.unlock();
}

OMQ::WFEntry::setAttachError(softint segid) {
    lck.lock();
    on_exit lck.unlock();

    # bug 685:
    # errors in attach functions with workflow orders with RETRY or ASYNC-WAITING statuses can lead to an infinite loop
    # set all steps with RETRY or ASYNC-WAITING status to ERROR
    foreach string stepid in (keys steps) {
        foreach hash<auto> sh in (steps{stepid}) {
            if (sh.status == OMQ::StatRetry || sh.status == OMQ::StatAsyncWaiting)
                updateStepStatusUnlocked(stepid, $#, OMQ::StatError);
        }
    }

    # set segment to ERROR
    seg[segid].status = OMQ::StatError;
}

OMQ::WFEntry::newAsyncSegment(softint segid) {
    lck.lock();
    on_exit lck.unlock();

    if (exists seg[segid]) {
        # DEBUG
        #log(LoggerLevel::DEBUG, "DEBUG: WFEntry::newAsyncSegmentNoCommit(segid: %y) segment already exists with status '%s' (%s)", segid, OMQ::StatMap.(seg[segid].status), seg[segid].status);

        seg[segid].status = OMQ::StatInProgress;
        seg[segid].attach = True;

        return;
    }

    newSegmentCommitUnlocked(segid);
}

private OMQ::WFEntry::newSegmentNoCommitUnlocked(softint segid) {
    # insert segment only in the case if it doesn't exist. See waitForReadyWorkflow()
    # cacheWorkflowUnlocked() call with get_status set to True
    if (!exists seg[segid])
        sqlif.insertSegment(workflowid, workflow_instanceid, segid);
    else if (seg[segid].status != OMQ::StatInProgress)
        sqlif.updateSegment(workflow_instanceid, segid, OMQ::SQLStatInProgress, seg[segid].custom_status);
}

private OMQ::WFEntry::postNewSegmentUnlocked(softint segid) {
    # marks segment as in-progress in internal cache
    seg[segid].attach = True;
    seg[segid].status = seg[segid].dbstatus = OMQ::StatInProgress;
}

private OMQ::WFEntry::newSegmentCommitUnlocked(softint segid) {
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            newSegmentNoCommitUnlocked(segid);
            QDBG_TEST_CLUSTER_FAILOVER();
        } catch (hash<ExceptionInfo> ex) {
            # restart the transaction if necessary
            if (trans.restartTransaction(ex))
                continue;
            wf.logFatal("error %s new segment: workflowid: %d, workflow_instanceid: %d, segmentid: %d",
                exists seg[segid] ? "updating" : "inserting",
                workflowid, workflow_instanceid, segid);
            wf.logFatal(get_exception_string(ex));
            #wf.logFatal("DEBUG: stack: %y", get_stack());

            # rethrow exception
            rethrow;
        }
        trans.reset();
        break;
    }
    postNewSegmentUnlocked(segid);
}

# creates a new initial segment row with status ERROR
OMQ::WFEntry::markReadyWorkflowAsError(string reason) {
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            sqlif.markReadyWorkflowAsError(workflowid, workflow_instanceid);
            Qorus.audit.workflowStatusChangeNoCommit(NOTHING, workflowid, workflow_instanceid, OMQ::SQLStatReady, OMQ::SQLStatError, reason);
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

    # raise system event
    # issue #2937: issue events if the internal status changes; do not use the DB status for any status change
    # comparisons for events
    if (status != OMQ::StatError) {
        Qorus.events.postWorkflowStatusChanged(NOTHING, wf.name, wf.version, workflowid, workflow_instanceid,
            {"old": status, "new": OMQ::StatError});
    }

    seg[0].status = seg[0].dbstatus = OMQ::StatError;
    # set workflow order instance data status to ERROR
    dbstatus = status = OMQ::StatError;
}

# creates a new initial segment row
OMQ::WFEntry::setupInitialSegment() {
    # all operations are unlocked because we have exclusive access to the WFEntry object
    string old_status;
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            # restartable with the reset logic below
            old_status = setWorkflowInProgressNoCommit();
            newSegmentNoCommitUnlocked(0);
            QDBG_TEST_CLUSTER_FAILOVER();
        } catch (hash<ExceptionInfo> ex) {
            # restart the transaction if necessary
            if (trans.restartTransaction(ex)) {
                if (old_status)
                    dbstatus = old_status;
                continue;
            }
            rethrow;
        }
        trans.reset();
        break;
    }
    postSetWorkflowInProgress(old_status);
    postNewSegmentUnlocked(0);

    # DEBUG
    #log(LoggerLevel::DEBUG, "nif() WI %d fr 0->1", workflow_instanceid);
    #log(LoggerLevel::DEBUG, "WFEntry::setupInitialSegment() wfiid %d workflow %d->%d", workflow_instanceid, refs, refs + 1);
    #log(LoggerLevel::DEBUG, "nif() self: %y", True);#self);

    # reference workflow instance
    ++refs;
}

# sets segment status to in-progress
OMQ::WFEntry::grabSegment(softint segid) {
    #log(LoggerLevel::DEBUG, "WFEntry::grabSegment(segid: %d) wfiid %d workflow %d->%d", segid, workflow_instanceid, refs, refs + 1);

    ++refs;

    lck.lock();
    on_exit lck.unlock();

    if (seg[segid].dbstatus != OMQ::StatInProgress) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                sqlif.updateSegment(workflow_instanceid, segid, OMQ::SQLStatInProgress, seg[segid].custom_status);
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
    }

    # clear any retry trigger
    delete seg[segid].rd;

    seg[segid].attach = True;
    seg[segid].status = seg[segid].dbstatus = OMQ::StatInProgress;
}

# resets data in case of a transaction restart when acquiring order data
OMQ::WFEntry::resetData() {
    sensitive_data.resetData();
    delete steps;
    delete ssh;
    delete seg;
    need_errors = False;
    need_subworkflow = False;
}

# read in the workflow order data instance's step status from the database if not already there
OMQ::WFEntry::getWorkflowStatusConditional() {
    lck.lock();
    on_exit lck.unlock();

    if (ssh)
        return;

    getWorkflowStatusIntern();
}

# read in the workflow order data instance's step status from the database
OMQ::WFEntry::getWorkflowStatus() {
    lck.lock();
    on_exit lck.unlock();

    getWorkflowStatusIntern();
}

# read in the workflow order data instance's step status from the database
# NOTE: transaction status handled externally
OMQ::WFEntry::getWorkflowStatusIntern() {
    #log(LoggerLevel::DEBUG, "DEBUG WFEntry::getWorkflowStatus() wfiid=%d", workflow_instanceid);

%ifdef QorusDebugInternals
    # DEBUG
    if (steps) {
        wf.logFatal("DEBUG: workflow status already cached: %N", steps);
        wf.logFatal("DEBUG: stack: %y", get_stack());
    }
%endif

    # get step status
    *hash<auto> q = sqlif.cacheSteps(workflow_instanceid);

    int retry;
    bool has_swf;

    context (q) {
        string stat = OMQ::SQLStatMap.%stepstatus;
        string dbstat = stat;

        if (%stepstatus == OMQ::SQLStatInProgress) {
            wf.logInfo("step %d/%d for workflow_instanceid %d has status 'I' (IN-PROGRESS), treating as 'E' (ERROR)", %stepid, %ind, workflow_instanceid);
            # set the status to ERROR so we can process the step
            stat = OMQ::StatError;
        }

        int retries = %retries > 0 ? int(%retries) : 0;

        bool business;
        if (%retries < 0 && inlist(stat, (OMQ::StatError, OMQ::StatRetry))) {
            # set workflow-level flag for business error
            business_error.%stepid.%ind = True;
            business = True;
        }

        steps.%stepid[%ind] = {
            "dbstatus"      : dbstat,
            "status"        : stat,
            "retries"       : string(retries),
            "business_error": business,
            "skip"          : boolean(%skip),
            "started"       : %started,
            "completed"     : %completed.val() ? %completed : NOTHING,
            "event"         : %eventkey,
            "custom_status" : (%custom_status == NULL ? NOTHING : %custom_status)
        };

        # update step summary status hash
        ++ssh{%stepid}{stat};
        #QDBG_LOG("WFEntry::getWorkflowStatusIntern() wfiid %d stepid %y [%d] %y: %d -> %d", workflow_instanceid, %stepid, %ind, stat, ssh{%stepid}{stat} - 1, ssh{%stepid}{stat});

        if (wf.stepinfo.%stepid.steptype == OMQ::ExecSubWorkflow)
            has_swf = True;

        if (stat == OMQ::StatRetry)
            retry++;
    }

    # see if step statuses need to be processed after a recovery where the step statuses were not flushed to disk
    if (retry > 1) {
        # get list of steps with statuses
        foreach string stepid in (keys ssh) {
            # each dependent step is actually COMPLETE
            foreach softstring id in (wf.steps{stepid}) {
                if (exists ssh{id} && ssh{id}{OMQ::StatComplete} != elements steps{id}) {
                    wf.logInfo("marking step %d as 'C' (COMPLETE)", id);
                    for (int i = 0; i < elements steps{id}; ++i) {
                        string old_status = steps{id}[i].status;
                        # issue #2759: remove the old status
                        QDBG_ASSERT(ssh{id}{old_status} > 0);
                        if (!(--ssh{id}{old_status})) {
                            remove ssh{id}{old_status};
                        }
                        ++ssh{id}{OMQ::StatComplete};
                        #QDBG_LOG("WFEntry::getWorkflowStatusIntern() wfiid %d stepid %y [%d] %y: %d -> %d", workflow_instanceid, stepid, i, old_status, ssh{stepid}{old_status} + 1, ssh{stepid}{old_status});
                        #QDBG_LOG("WFEntry::getWorkflowStatusIntern() wfiid %d stepid %y [%d] %y: %d -> %d", workflow_instanceid, stepid, i, StatRetry, ssh{stepid}{StatComplete} - 1, ssh{stepid}{StatComplete});
                        steps{id}[i].status = OMQ::StatComplete;
                        steps{id}[i].completed = now_us();
                        # bug 1257: in case of schema corruption, the started attribute may not exist
                        if (steps{id}[i].started)
                            Qorus.events.postWorkflowStepPerformance(tld.cx, wf.name, wf.version, workflowid, workflow_instanceid, wf.stepmap{id}, id, i, steps{id}[i].started, steps{id}[i].completed);
                        else
                            steps{id}[i].started = steps{id}[i].completed;
                    }
                }
            }
        }
    }

    # get segment status
    q = sqlif.cacheSegments(workflow_instanceid);
    context (q) {
        # set internal and DB status to actual DB status
        seg[%segmentid].status = seg[%segmentid].dbstatus = OMQ::SQLStatMap.%segmentstatus;
        if (%segmentstatus == 'I') {
            # set the status to ERROR so we can process the segment
            seg[%segmentid].status = OMQ::StatError;
            wf.logInfo("segment %d for workflow_instanceid %d has status 'I' (IN-PROGRESS), treating as 'E' (ERROR)", %segmentid, workflow_instanceid);
        }
        seg[%segmentid].custom_status = (%custom_status == NULL ? NOTHING : %custom_status);
    }

    # tag this entry that errors may be present in the DB that have not been retrieved into memory yet
    need_errors = True;

    # tag this entry that subworkflow steps have been executed and the data has not been retrieved
    need_subworkflow = True;

    # DEBUG
%ifdef QorusDebugInternals
    #wf.logDebug("DEBUG WFEntry::getWorkflowStatus() wfiid=%d status: %y seg: %y steps: %y", workflow_instanceid, status, seg, steps);
%endif
}

private static OMQ::WFEntry::logRetriesExceededError(string type, int max) {
    string desc = sprintf("this step has exceeded the %s value of %d", type, max);
    log_error("RETRIES-EXCEEDED-ERROR", desc, NOTHING, OMQ::ES_Major);
}

OMQ::WFEntry::setArrayStepInProgressCommit(softstring stepid, int elementsv) {
    lck.lock();
    on_exit lck.unlock();

    # if there's an error, set array index 0 to ERROR for step to avoid a deadlock
    # use a separate on_error statement just in case the rollback throws an exception
    on_error updateStepStatusUnlocked(stepid, 0, OMQ::StatError);

    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            sqlif.insertArrayStep(workflow_instanceid, stepid, elementsv);
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

    date now = now_us();
    # step ind 0 already inserted
    int new_steps = elementsv - 1;
    if (new_steps) {
        map steps{stepid}[$1] = {
            "status": OMQ::StatInProgress,
            "dbstatus": OMQ::StatInProgress,
            "started": now,
        }, xrange(1, new_steps + 1);
        ssh{stepid}{OMQ::StatInProgress} += new_steps;
        #QDBG_LOG("WFEntry::setArrayStepInProgressCommit() wfiid %d stepid %y %y: %d -> %d", workflow_instanceid, stepid, StatInProgress, ssh{stepid}{StatInProgress} - new_steps, ssh{stepid}{StatInProgress});
    }

    # DEBUG
    #log(LoggerLevel::DEBUG, "WFEntry::setArrayStepInProgressCommit(stepid: %y, elementsv: %y) steps: %y ssh: %y", stepid, elementsv, steps, ssh);
}

OMQ::WFEntry::setArrayStepInProgressCommitRecover(softstring stepid, int elementsv) {
    lck.lock();
    on_exit lck.unlock();

    int first = steps{stepid}.size();

    # fix for bug 497: make sure elementsv > first before incrementing the array step "IN-PROGRESS" status count
    # or the reference count can be negative - in fact all the logic of this function can be skipped in this case
    int new_steps = elementsv - first;
    if (new_steps <= 0) {
        return;
    }

    # if there's an error, set the first array index to ERROR for the step to avoid a deadlock
    # use a separate on_error statement just in case the rollback throws an exception
    on_error updateStepStatusUnlocked(stepid, first, OMQ::StatError);

    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            sqlif.insertArrayStepRecover(workflow_instanceid, stepid, elementsv, first);
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

    date now = now_us();

    # issue #3418: only add data for new steps
    QDBG_ASSERT(elementsv - first);
    map steps{stepid}[$1] = {
        "status": OMQ::StatInProgress,
        "dbstatus": OMQ::StatInProgress,
        "started": now,
    }, xrange(first, elementsv);
    ssh{stepid}{OMQ::StatInProgress} += new_steps;
    #QDBG_LOG("WFEntry::setArrayStepInProgressCommitRecover() wfiid %d stepid %y %y: %d -> %d", workflow_instanceid, stepid, StatInProgress, ssh{stepid}{StatInProgress} - new_steps, ssh{stepid}{StatInProgress});

    # DEBUG
    #log(LoggerLevel::DEBUG, "WFEntry::setArrayStepInProgressCommitRecover(stepid: %y, elementsv: %y) steps: %y ssh: %y", stepid, elementsv, steps, ssh);
}

*string OMQ::WFEntry::getStepStatus(string stepname) {
    *softstring stepid = wf.steprmap{stepname};
    if (!exists stepid)
        throw "STEP-ERROR", sprintf("cannot map step name %y to a step id", stepname);

    return foldl OMQ::SpecialStatusOrder.$1 > OMQ::SpecialStatusOrder.$2 ? $1 : $2, (select keys ssh{stepid}, ssh{stepid}.$1);
}

# will wait until the step is not IN-PROGRESS
private OMQ::WFEntry::waitForStepUnlocked(softstring stepid, softint ind) {
    # if the step is already in progress, then wait until it's done executing in the other segment before continuing
    while (steps{stepid}[ind].status == OMQ::StatInProgress) {
        if (!exists stepsync{stepid}[ind]) {
            stepsync{stepid}[ind] = new Condition();
        }
        QDBG_LOG("DEBUG: waiting for step %d/%d (%y)", stepid, ind, steps{stepid}[ind]);
        #QDBG_LOG("DEBUG: stack: %y", get_stack());
        #QDBG_LOG("DEBUG: self: %y", self);
        stepsync{stepid}[ind].wait(lck);
    }
}

# in_progress: is the step already in progress by this segment?
string OMQ::WFEntry::updateAsyncStepStatusUnlocked(softstring stepid, int ind, string stat, *bool in_progress) {
    # if the step is already in progress, then wait until it's done executing in the other segment before continuing
    if (!in_progress)
        waitForStepUnlocked(stepid, ind);

    string ostat = steps{stepid}[ind].status;
    if (updateStepStatusUnlocked(stepid, ind, stat))
        return steps{stepid}[ind].status;

    return stat;
}

hash OMQ::WFEntry::setStepInProgress(softstring stepid, int ind) {
    lck.lock();
    on_exit lck.unlock();

    # if the step is already in progress, then wait until it's done executing in the other segment before continuing
    waitForStepUnlocked(stepid, ind);

    *string stat = steps{stepid}[ind].status;
    if (updateStepStatusUnlocked(stepid, ind, OMQ::StatInProgress)) {
        #log(LoggerLevel::DEBUG, "DEBUG: ERROR: wfiid %y segment %y tried to update step %y.%y to IN-PROGRESS but already has final status %N",
        #    workflow_instanceid, tld.segID, stepid, ind, steps{stepid}[ind].status);
        #log(LoggerLevel::DEBUG, "DEBUG: stack: %y", get_stack());
        return {"final-status": steps{stepid}[ind].status};
    }

    # issue #2880: first get any step data for a new step outside the SQL insertion loop
    *hash<auto> step_data;
    if (!stat) {
        step_data = wf.getDefaultStepData(stepid);
        if (step_data) {
            self.step_data.update(stepid, ind, step_data);
        }
    }

    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            if (exists stat) {
                sqlif.updateStepStatus(workflow_instanceid, stepid, ind, OMQ::SQLStatInProgress);
            } else {
                sqlif.insertStep(workflow_instanceid, stepid, ind, step_data);
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

    steps{stepid}[ind].dbstatus = OMQ::StatInProgress;

    #log(LoggerLevel::DEBUG, "DEBUG: SQL: setStepInProgress() %d/%d: updated status to IN-PROGRESS (old: %y, step: %y)", stepid, ind, stat, steps{stepid}[ind]);

    return ("old-status": stat);
}

*string OMQ::WFEntry::getArrayStepStatus(string id) {
    lck.lock();
    on_exit lck.unlock();

    string status;
    int end = elements steps{id};
    for (int ind = 0; ind < end; ++ind) {
        if (!exists status ||
                OMQ::ArrayStatusOrder.(steps{id}[ind].status) >
                OMQ::ArrayStatusOrder{status})
        {
            status = steps{id}[ind].status;
        }
    }
    return status;
}

*string OMQ::WFEntry::checkFinalStatus(softstring stepid, int ind) {
    lck.lock();
    on_exit lck.unlock();

    # if the step is already in progress, then wait until it's done executing in the other segment before continuing
    waitForStepUnlocked(stepid, ind);

    if (inlist(steps{stepid}[ind].status, (OMQ::StatComplete, OMQ::StatCanceled)))
        return steps{stepid}[ind].status;
}

string OMQ::WFEntry::commitStepStatus(softint segid, softstring stepid, int ind, string n_status, softint max_retries,
        softint max_async_retries) {
    bool skip_step = False;
    # will be used if an async queue entry is created
    string async_key;
    QDBG_LOG("WFEntry::commitStepStatus tld.mode %y segid %y stepid %y ind %y n_status %y tld: skipSubWorkflow %y "
        "skipAsync %y skipEvent %y steps: %y", tld.mode, segid, stepid, ind, n_status, tld.skipSubWorkflow,
        tld.skipAsync, tld.skipEvent, steps{stepid}[ind]);

    {
        lck.lock();
        on_exit lck.unlock();

        if (inlist(n_status, (OMQ::StatRetry, OMQ::StatAsyncWaiting))) {
            ++steps{stepid}[ind].retries;
        } else {
            delete steps{stepid}[ind].retries;
        }

        # first, see if we have exhausted all retries
        if (tld.mode == OMQ::WM_Recovery) {
            if (n_status == OMQ::StatRetry) {
                if (exists max_retries && steps{stepid}[ind].retries >= (int mr = int(max_retries))) {
                    wf.logInfo("retry count has reached maximum (%d), changing status from '%s' to 'ERROR'", mr,
                        n_status);
                    n_status = OMQ::StatError;
                    delete steps{stepid}[ind].retries;
                    WFEntry::logRetriesExceededError("max-retries", mr);
                }
            } else if (n_status == OMQ::StatAsyncWaiting && !tld.skipAsync) {
                if (exists max_async_retries && steps{stepid}[ind].retries >= (int mr = int(max_async_retries))) {
                    wf.logInfo("async retry count has reached maximum (%d), changing status from '%s' to 'ERROR'", mr,
                        n_status);
                    n_status = OMQ::StatError;
                    delete steps{stepid}[ind].retries;
                    WFEntry::logRetriesExceededError("max-async-retries", mr);
                }
            }
        }

        if (tld.skipSubWorkflow || tld.skipAsync || tld.skipEvent) {
            /*
                if this is an array step with > 1 step element, and this step is not the
                last step element to go to COMPLETE, then the step may go directly to
                COMPLETE without having to post a queue entry for the backend segment;
                only the last step element will create a queue entry
            */
            int n = steps{stepid}.size() - 1;
            if (n && (ssh{stepid}{OMQ::StatComplete} < n)) {
                n_status = OMQ::StatComplete;
                tld.skipSubWorkflow = NOTHING;
                tld.skipAsync = NOTHING;
                tld.skipEvent = NOTHING;
            }
            #QDBG_LOG("WFEntry::commitStepStatus check for completeness: steps{%y} = %y ssh{%y}{COMPLETE} = %y -> %y",
            #    stepid, steps{stepid}, stepid, ssh{stepid}{OMQ::StatComplete}, n_status);
        }

        # unset businessError flag if step status is not ERROR or RETRY
        if (tld.businessError && !inlist(n_status, (OMQ::StatError, OMQ::StatRetry)))
            tld.businessError = NOTHING;

        # save status before update (current status in case of error in WFEntry::updateStepStatusUnlocked())
        QDBG_LOG("WFEntry::commitStepStatus steps: %y", steps);
        string ostat = steps{stepid}[ind].status;

        wf.logInfo("step completed with status '%s' (%s)", OMQ::StatMap{n_status}, n_status);
        QDBG_LOG("WFEntry::commitStepStatus() wfiid %y stepid %y [%d] setting status %y", workflow_instanceid, stepid,
            ind, n_status);

        if (updateStepStatusUnlocked(stepid, ind, n_status)) {
            if (tld.skipAsync) {
                wf.logInfo("cannot skip async step; status has changed to %y", ostat);
            } else if (tld.skipSubWorkflow) {
                wf.logInfo("cannot create entry to skip subworkflow step as step status has changed to %y", ostat);
            } else if (tld.skipEvent) {
                wf.logInfo("cannot create entry for posted synchronization event step as step status has changed "
                    "to %y", ostat);
            }

            return steps{stepid}[ind].status;
        }

        # set segment retry delay
        if (exists tld.retryDelay && inlist(n_status, (OMQ::StatAsyncWaiting, OMQ::StatRetry))) {
            # should already be an absolute date for comparison and inserting in the DB
            QDBG_ASSERT(tld.retryDelay.typeCode() == NT_DATE && tld.retryDelay.absolute());

            if (!exists seg[segid].rd || (seg[segid].rd.delay > tld.retryDelay)) {
                seg[segid].rd = {
                    "delay" : tld.retryDelay,
                    "stepid": stepid,
                    "ind"   : ind,
                };
            }
        }

        if (tld.skipEvent)
            skip_step = True;

        #log(LoggerLevel::DEBUG, "DEBUG: retry_delay: %y, stat: %y, seg %d: %y", tld.retryDelay, n_status, segid, seg[segid]);

        # do we need to write to the DB?  ensure all updates are made in a single transaction
        if (tld.skipSubWorkflow || tld.skipAsync) {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    # restartable actions
                    if (tld.skipSubWorkflow) {
                        OMQ::SegmentManagerBase::createSubWorkflowInstanceRowNoCommit(workflow_instanceid, stepid, ind, workflow_instanceid, 1);
                        wf.logInfo("created corrected subworkflow order instance row for step");
                    }

                    if (tld.skipAsync) {
                        async_key = createCorrectedSystemQueueEntryNoCommit(stepid, ind);
                        wf.logInfo("created corrected queue entry %y for step", async_key);
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
        }

        # DEBUG
        #log(LoggerLevel::DEBUG, "DEBUG: commitStepStatus(segid: %y, step=%d/%d, status: %y, max-retries: %y, max-async-retries: %y) step: %y all: %y", segid, stepid, ind, n_status, max_retries, max_async_retries, steps{stepid}[ind], steps{stepid});
        #log(LoggerLevel::DEBUG, "DEBUG: self: %y", self);
    }

    # update internal subworkflow queue if necessary
    if (tld.skipSubWorkflow)
        SM.updateSubWorkflowQueueStep(wf.workflowid, workflow_instanceid, stepid, ind, priority, workflow_instanceid, parent_info, OMQ::StatComplete);
    else if (tld.skipEvent) # FIXME: remove "corrected" from event queue
        SM.postSyncEventIntern(wf.workflowid, stepid, workflow_instanceid, ind, priority, parent_info);
    else if (tld.skipAsync)
        SM.updateQueueUnlocked(wf.workflowid, stepid, workflow_instanceid, ind, priority, True, async_key, NOTHING, parent_info);

    return n_status;
}

# returns True if an error occurred, NOTHING if OK
private *bool OMQ::WFEntry::updateStepStatusUnlocked(softstring stepid, softint ind, string stat) {
    # DEBUG
    #log(LoggerLevel::DEBUG, "DEBUG: updateStepStatusUnlocked() BEFORE wfiid: %y stepid: %y ind: %y stat=%s "
    #    "(currently %y)", workflow_instanceid, stepid, ind, stat, steps{stepid}[ind].status);

    if (tld.businessError && stat != OMQ::StatError) {
        tld.businessError = NOTHING;
    }

%ifdef QorusDebugInternals
    # DEBUG
    if (stat == OMQ::StatInProgress && steps{stepid}[ind].status == OMQ::StatInProgress) {
        wf.logFatal("DEBUG: ERROR: wfiid %y (seg %y) tried to set step %y.%y to IN-PROGRESS while already "
            "IN-PROGRESS by segment %y",
            workflow_instanceid, tld.segID, stepid, ind, steps{stepid}[ind].segment);
        wf.logFatal("DEBUG: stack: %y", get_stack());
        return True;
    }
%endif

    if (inlist(steps{stepid}[ind].status, (OMQ::StatComplete, OMQ::StatCanceled, stat))) {
        QDBG_LOG("WFEntry::updateStepStatusUnlocked() wfiid %d stepid %d [%d] no update to %y performed; current "
            "status: %y", workflow_instanceid, stepid, ind, stat, steps{stepid}[ind].status);
        return True;
    }

    if (stat != OMQ::StatInProgress) {
%ifdef QorusDebugInternals
        # DEBUG
        delete steps{stepid}[ind].segment;
%endif

        # signal any waiting threads that the step is free
        if (exists stepsync{stepid}[ind]) {
            stepsync{stepid}[ind].broadcast();
        }

        if (stat == OMQ::StatComplete) {
            steps{stepid}[ind].completed = now_us();
            # bug 1257: in case of schema corruption, the started attribute may not exist
            if (steps{stepid}[ind].started) {
                Qorus.events.postWorkflowStepPerformance(NOTHING, wf.name, wf.version, workflowid,
                    workflow_instanceid, wf.stepmap{stepid}, stepid, ind, steps{stepid}[ind].started,
                    steps{stepid}[ind].completed);
            } else {
                steps{stepid}[ind].started = steps{stepid}[ind].completed;
            }
        }
    }
%ifdef QorusDebugInternals
    else {
        # DEBUG
        steps{stepid}[ind].segment = tld.segID;
    }
%endif

    # update step statistics
    if (exists (*string old_status = steps{stepid}[ind].status)) {
        # issue #2759: remove the status when the count reaches zero
        QDBG_ASSERT(ssh{stepid}{old_status} > 0);
        if (!--ssh{stepid}{old_status}) {
            remove ssh{stepid}{old_status};
        }
        QDBG_LOG("WFEntry::updateStepStatusUnlocked() wfiid %d stepid %y [%d] %y: %d -> %d", workflow_instanceid,
           stepid, $1, old_status, ssh{stepid}{old_status} + 1, ssh{stepid}{old_status});
    } else {
        steps{stepid}[ind].started = now_us();
    }

    ++ssh{stepid}{stat};
    QDBG_LOG("WFEntry::updateStepStatusUnlocked() wfiid %d stepid %y [%d] %y: %d -> %d", workflow_instanceid, stepid,
       $1, stat, ssh{stepid}{stat} - 1, ssh{stepid}{stat});

    steps{stepid}[ind] += (
        "status"        : stat,
        "business_error": tld.businessError,
%ifdef QorusDebugInternals
        "tid": gettid(),
%endif
    );

    if (tld.businessError) {
        business_error{stepid}{ind} = True;
    } else {
        delete business_error{stepid}{ind};
        if (!elements business_error{stepid}) {
            delete business_error{stepid};
        }
    }

    #log(LoggerLevel::DEBUG, "DEBUG: updateStepStatusUnlocked() updated step %d/%d to %y", stepid, ind, steps{stepid}[ind]);
    #log(LoggerLevel::DEBUG, "stack: %y", get_stack());
}

private string OMQ::WFEntry::createCorrectedSystemQueueEntryNoCommit(softint stepid, int ind) {
    string key = sprintf("OMQ-SYS-%d-%d-%d", workflow_instanceid, stepid, ind);
    wf.logInfo("creating queue entry with key %y on queue %y to skip step", key, wf.stepinfo{stepid}.queuename);

    if (tld.mode == OMQ::WM_Normal) {
        sqlif.insertCorrectedQueueData(workflow_instanceid, stepid, ind, wf.stepinfo{stepid}.queueid, key);
    } else {
        sqlif.insertOrUpdateCorrectedQueueData(workflow_instanceid, stepid, ind, wf.stepinfo{stepid}.queueid, key);
    }

    return key;
}

OMQ::WFEntry::updateStepStatus(softstring stepid, softint ind, string stat) {
    # grab lock here for the duration of the method and only release it when the method is exited
    lck.lock();
    on_exit lck.unlock();

    updateStepStatusUnlocked(stepid, ind, stat);
}

# called when the backend segment cannot be acquired for normal backend execution due to a race condition with a recovery action
OMQ::WFEntry::releaseAsyncBackendSteps(hash qs, softstring stepid, list<auto> stats) {
    lck.lock();
    on_exit lck.unlock();

    foreach softint ind in (qs.ind) {
        updateStepStatusUnlocked(stepid, ind, stats[$#]);
        if (steps{stepid}[ind].dbstatus != stats[$#]) {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    sqlif.updateStepStatus(qs.workflow_instanceid, stepid, ind, StatMap.(stats[$#]));
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
            steps{stepid}[ind].dbstatus = stats[$#];
            # DEBUG
            #log(LoggerLevel::DEBUG, "WFEntry::releaseBackendSteps() set stepid=%d/%d to %y", stepid, ind, stats[$#]);
        }
    }
}

int OMQ::WFEntry::startAsyncStepBackEnd(reference qs, softstring stepid, softint queueid, reference os) {
    # list of errored ind's
    list err = ();

    lck.lock();
    on_exit lck.unlock();

    foreach softint ind in (qs.ind) {
        # see if we can start working on the step and set the status to IN-PROGRESS
        # if the step is already in progress, then wait until it's done executing
        waitForStepUnlocked(stepid, ind);

        os[$#] = steps{stepid}[ind].status;

        if (updateStepStatusUnlocked(stepid, ind, OMQ::StatInProgress)) {
            err += $#;
            continue;
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                if (steps{stepid}[ind].dbstatus != OMQ::StatInProgress)
                    sqlif.updateStepStatus(qs.workflow_instanceid, stepid, ind, OMQ::SQLStatInProgress);

                # delete queue_data row
                sqlif.discardQueueDataUnconditional(queueid, qs.queuekey[$#]);
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

        if (steps{stepid}[ind].dbstatus != OMQ::StatInProgress)
            steps{stepid}[ind].dbstatus = OMQ::StatInProgress;
    }

    # if there is an error list, remove errored elements from data; return -1 if no elements are left
    if (elements err && SegmentManagerBase::removeAsyncErrors(\qs, err))
        return -1;

    return 0;
}

private OMQ::WFEntry::doRelease(softstring segid, WorkflowQueueBase wco, *bool retry) {
    QDBG_LOG("WFEntry::doRelease segid: %d wfiid %d workflow %d->%d", segid, workflow_instanceid, refs, refs - 1);

    # decrement workflow reference count
    --refs;

    if (retry)
        wco.releaseRetrySegment(workflow_instanceid, segid);
    else
        wco.releaseSegment(workflow_instanceid, segid);
}

# must be called with the lock held
private *string OMQ::WFEntry::getSegmentStatusNoWaitUnlocked(int segid) {
    *string stat;

    # bug 476: do not mark segments COMPLETE before all their steps have executed
    # incomplete flag
    bool incomplete = False;

    # derive segment status from step statuses
    foreach softstring stepid in (wf.segment[segid].steplist) {
        # bug 476: if a step has not executed yet then set the incomplete flag
        if (!exists ssh{stepid}) {
            incomplete = True;
            continue;
        }

        # get step status
        string s = foldl OMQ::SpecialStatusOrder.$1 > OMQ::SpecialStatusOrder.$2 ? $1 : $2, (select keys ssh{stepid}, ssh{stepid}.$1);
        if (s == OMQ::StatInProgress)
            return OMQ::StatInProgress;

        if (!exists stat || OMQ::SpecialStatusOrder{s} > OMQ::SpecialStatusOrder{stat})
            stat = s;
    }

    # bug 476: if the status is COMPLETE and the incomplete flag has been set, then change to INCOMPLETE
    if (incomplete && stat == OMQ::StatComplete)
        stat = OMQ::StatIncomplete;

    # DEBUG
    #log(LoggerLevel::DEBUG, "WFEntry::getSegmentStatusNoWaitUnlocked(segid: %y) stat: %y seg: %y ssh: %y", segid, stat, wf.segment[segid].steplist, ssh);

    return stat;
}

# must be called with the lock held
private *string OMQ::WFEntry::getSegmentStatusUnlocked(softint segid) {
    *string stat;
    bool restart;

    do {
        # flag to restart the process if a step is in-progress
        restart = False;

        # derive segment status from step statuses
        foreach softstring stepid in (wf.segment[segid].steplist) {
            # make sure no steps are in progress
            if (ssh{stepid}."IN-PROGRESS") {
                # find step in progress
                int end = elements steps{stepid};
                for (int ind = 0; ind < end; ++ind) {
                    # if step is in-progress, wait for step to complete
                    if (steps{stepid}[ind].status == OMQ::StatInProgress) {
                        waitForStepUnlocked(stepid, ind);
                        delete stat;
                        break;
                    }

                    # DEBUG
                    if (ind == (end - 1)) {
                        wf.logFatal("DEBUG: WFEntry::getSegmentStatusUnlocked() did not find any steps in progress for stepid %y\nssh.%y: %y\nsteps.%y: %y", stepid, stepid, ssh{stepid}, stepid, steps{stepid});
                        wf.logFatal("DEBUG: stack: %y", get_stack());
                        # fix for bug 497: do not let Qorus get into an infinite loop in this case
                        throw "INTERNAL-STEP-STATUS-ERROR", sprintf("no steps with IN-PROGRESS status: wfiid %y segment %d stepid %d %y", workflow_instanceid, segid, stepid, ssh{stepid});
                    }
                }
                restart = True;
                break;
            }

            # get step status
            *string s = foldl OMQ::StatusOrder.$1 > OMQ::StatusOrder.$2 ? $1 : $2, (select keys ssh{stepid}, ssh{stepid}.$1);

            if (!exists stat || OMQ::StatusOrder{s} > OMQ::StatusOrder{stat}) {
                stat = s;
                if (stat == OMQ::StatError)
                    break;
            }
        }
    } while (restart);

    # if there are no steps, then return the current segment's status
    *string rv = stat ?? seg[segid].status;

    # issue #3687: do not release the segment with COMPLETE status if not all steps have executed
    if (rv == OMQ::StatComplete && (wf.segment[segid].steps.size() != steps{keys wf.segment[segid].steps}.size())) {
        wf.logInfo("WARNING: segment %d has only %d/%d steps executed; setting status ERROR", segid,
            steps{keys wf.segment[segid].steps}.size(), wf.segment[segid].steps.size());
        rv = OMQ::StatError;
    }
    return rv;
}

# called inside the WFEntry lock
list OMQ::WFEntry::registerCompleteSegmentNoCommit(softint segid) {
    list sl = ();   # list of segments that can now be started

    # see if we can start dependent segments
    foreach softint dsegid in (wf.segment[segid].prereqfor) {
        if (exists seg[dsegid]) {
            #log(LoggerLevel::DEBUG, "DEBUG: cannot start segment %d; segment has already been started", dsegid);
            continue;
        }

        bool ok = True;

        foreach softint sid in (wf.segment[dsegid].segdeps) {
            if (seg[sid].status != OMQ::StatComplete) {
                ok = False;
                break;
            }
        }

        if (ok) {
            sl += dsegid;

            sqlif.insertSegment(wf.workflowid, workflow_instanceid, dsegid);
        }
    }

    return sl;
}

# writes segment status to DB
*string OMQ::WFEntry::commitReleaseSegment(softint segid, WorkflowQueueBase wco, *bool retry) {
    QDBG_ASSERT(ensure_tld());
    QDBG_LOG("WFEntry::commitReleaseSegment segid %y", segid);
    *string stat;
    # save and restore tld.wfe
    *WFEntry wfe_orig = tld.wfe;
    tld.wfe = self;
    on_exit tld.wfe = wfe_orig;

    #*bool sync = tld.sync;

    # DEBUG
    #log(LoggerLevel::DEBUG, "WFEntry::commitReleaseSegment(segid: %y) wfiid: %d virtual: %y", segid, workflow_instanceid, tld.virtual);

    # make sure segment attaches and releases are atomic
    lck.lock();

    # cleanup on block exit
    on_exit {
        delete seg[segid].attach;
        lck.unlock();
        doRelease(segid, wco, retry);
    }

    if (!tld.virtual) {
        stat = getSegmentStatusUnlocked(segid);
        if (!exists stat)
            stat = OMQ::StatError;

        # DEBUG
        #log(LoggerLevel::DEBUG, "DEBUG WFEntry::commitReleaseSegment() !virtual wfiid: %y stat: %y seg[%y]: %y", workflow_instanceid, stat, segid, seg[segid]);

        *date retry_delay;
        *hash rd = seg[segid].rd;
        # check if we should commit a fixed retry time
        if (exists rd) {
            if (inlist(stat, (OMQ::StatRetry, OMQ::StatAsyncWaiting))
                && inlist(steps.(rd.stepid)[rd.ind].status, (OMQ::StatRetry, OMQ::StatAsyncWaiting)))
                retry_delay = rd.delay;
        }

        #log(LoggerLevel::DEBUG, "DEBUG wfiid: %y segid=%d stat: %y steps: %y stepinfo: %y retry_delay: %y", workflow_instanceid, segid, stat, wf.segment[segid].steplist, steps, retry_delay);

        wf.logInfo("segment %d completed with status '%s' (%s)%s", segid, OMQ::StatMap{stat}, stat,
            exists retry_delay ? sprintf(" retry %y", retry_delay) : "");

        seg[segid].status = stat;

        list sl;
        if (!exists retry_delay && (stat == OMQ::StatComplete)) {
            QDBG_LOG("WFEntry::commitReleaseSegment() wfid %d segid %d steps: %y expecting: %y == %y", workflowid, segid, keys wf.segment[segid].steps, wf.segment[segid].steps.size(), steps{keys wf.segment[segid].steps}.size());
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    # restartable action, updates performed with "sl" below
                    sl = registerCompleteSegmentNoCommit(segid);
                    #QDBG_TEST_CLUSTER_FAILOVER();
                    QDBG_WAIT_TO_CONTINUE();
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

        #log(LoggerLevel::DEBUG, "DEBUG: stat: %y sync: %y index: %y segid: %y", stat, sync, tld.index, segid);

        if (exists retry_delay) {
            wco.queueRetrySegmentFixed(segid, workflow_instanceid, parent_info, retry_delay);
        } else if (stat == OMQ::StatComplete) {
            # apply segment changes
            map seg[$1] = (
                "dbstatus": OMQ::StatInProgress,
                "attach": True,
                "status": OMQ::StatReady,
            ), sl;

            wco.registerCompleteSegment(segid, workflow_instanceid, priority, sl);

            # stop synchronous recovery thread
            if (sync)
                wco.terminateSynchronousRetryConnection(tld.index, segid, workflow_instanceid);
        } else if (stat == OMQ::StatRetry) {
            wco.queueRetrySegment(segid, workflow_instanceid, parent_info);
        } else if (stat == OMQ::StatAsyncWaiting) {
            wco.queueAsyncRetrySegment(segid, workflow_instanceid, parent_info);
        } else if (stat == OMQ::StatError) {
            wco.removeSegment(workflow_instanceid, segid);
            # stop synchronous workflow
            if (sync)
                Qorus.control.execHash.(tld.index).setStop();
        }
    } else {
        tld.virtual = NOTHING;
        #wf.logDebug("DEBUG WFEntry::commitReleaseSegment() virtual wfiid: %y", workflow_instanceid);
    }

    return stat;
}

# cseg: number of segments in this workflow
private string OMQ::WFEntry::getFinalWorkflowStatusUnlocked(reference<int> erri) {
    if (status == OMQ::StatBlocked)
       return status;

    if (exists reschedule && reschedule < now_us())
        remove reschedule;

    # release the workflow with a READY status if no segment entries exist
    if (!elements seg) {
        # DEBUG xxx
        #if (!tld.index) {
        #    log(LoggerLevel::FATAL, "DEBUG: releasing wfiid %d with status READY: self: %y", workflow_instanceid, hash(self) - "wf");
        #    log(LoggerLevel::FATAL, "DEBUG: stack: %y", get_stack());
        #}
        if ((!initstatus || initstatus == OMQ::StatReady) && reschedule)
            return OMQ::StatScheduled;
        return initstatus ?? OMQ::StatReady;
    }

    string stat = OMQ::StatComplete;

    # derive all segment statuses
    int max = elements wf.segment;
    for (int i = 0; i < max; ++i) {
        *string segstat = getSegmentStatusUnlocked(i);
        # change READY status to INCOMPLETE to use for calculating the workflow order data status
        if (!exists segstat || segstat == OMQ::StatReady)
            segstat = OMQ::StatIncomplete;

        if (OMQ::StatusOrder{segstat} > OMQ::StatusOrder{stat})
            stat = segstat;

        #log(LoggerLevel::DEBUG, "DEBUG: getFinalWorkflowStatusUnlocked() segment %d status %y (overall %y)", i, segstat, stat);
        if (stat == OMQ::StatError)
            break;
    }

    stat = checkWfCanceled(stat, \erri);
    #log(LoggerLevel::DEBUG, "DEBUG: getFinalWorkflowStatusUnlocked() wfiid=%d stat: %y (seg: %y)", workflow_instanceid, stat, seg);
    return stat;
}

private string OMQ::WFEntry::checkWfCanceled(string stat, reference<int> erri) {
    if (stat == OMQ::StatError && wf) {
        int i = 0;
        foreach hash<auto> h in (errors) {
            string err = h.error;
            *ErrorDef eh = Qorus.getError(wf.workflowid, err);
            if (exists eh && eh.status == OMQ::StatCanceled) {
                erri = i;
                stat = OMQ::StatCanceled;

                # if the original status is READY and there are segments, then we need to use ERROR
                if ((status_orig == OMQ::StatReady || status_orig == OMQ::StatScheduled)
                    && seg)
                    status_orig = OMQ::StatError;
                break;
            }
            ++i;
        }
    }
    return stat;
}

OMQ::WFEntry::referenceWorkflow() {
    #log(LoggerLevel::DEBUG, "DEBUG WFEntry::referenceWorkflow() wfiid %d workflow %d->%d", workflow_instanceid, refs, refs + 1);
    ++refs;
    #log(LoggerLevel::DEBUG, "DEBUG WFEntry::referenceWorkflow() self: %y", True); #self);
}

# WFEntry::setupOrderData()
OMQ::WFEntry::setupOrderData(string encoding, *string sstr, *string dstr, *hash<auto> sddb, *hash<auto> step_data) {
    if (exists sstr) {
        # DEPRECATED: remove support for XML-RPC encoding
        # add XML preamble for XML-RPC encoding if necessary
        if (sstr =~ /^</) {
            sstr = sprintf("<?xml version=\"1.0\" encoding=\"%s\"?>%s", encoding, sstr);
        }
        # issue #3446: if the serialized data is hacked in the DB, then the order data could be set here that does not
        # conform to the defined static data type
        sdata = deserialize_qorus_data(sstr);
    }
    if (dstr.val()) {
        # DEPRECATED: remove support for XML-RPC encoding
        # add XML preamble for XML-RPC encoding if necessary
        if (dstr =~ /^</) {
            dstr = sprintf("<?xml version=\"1.0\" encoding=\"%s\"?>%s", encoding, dstr);
        }
        auto dd = deserialize_qorus_data(dstr);
        if (dd) {
            ddata.initialize(dd);
        }
    }

    if (sddb) {
        WFEntry::initializeSensitiveData(workflow_instanceid, sensitive_data, sddb);
    }

    if (step_data) {
        self.step_data.initialize(step_data);
    }
    #log(LoggerLevel::DEBUG, "WFEntry::setupOrderData(string) wfiid: %y sddb: %N\n", workflow_instanceid, sddb);
}

static OMQ::WFEntry::initializeSensitiveData(softint wfiid, SensitiveInstanceData sensitive_data, hash<auto> sddb) {
    hash<auto> sdh;

    # we need to decrypt sensitive data keys and data
    foreach hash<auto> kh in (sddb.pairIterator()) {
        foreach hash<auto> vh in (kh.value.pairIterator()) {
            string svalue = Qorus.decodeDecryptSensitiveValue(vh.key);
            # create the additional authenticated data (AAD) string for decryption with the MAC
            string aad = sprintf("%d-%s-%s", wfiid, kh.key, svalue);
            hash<auto> data = Qorus.deserializeDecryptSensitiveData(vh.value.data, vh.value.iv, vh.value.mac, aad);

            hash<auto> sdkh = (
                "data": data,
                "aliases": vh.value.aliases,
            );

            if (vh.value.meta)
                sdkh.meta = Qorus.deserializeDecryptSensitiveData(vh.value.meta, vh.value.miv, vh.value.mmac, aad);

            sdh{kh.key}{svalue} = sdkh;
        }
    }
    sensitive_data.initialize(sdh);
    #log(LoggerLevel::DEBUG, "WFEntry::initializeSensitiveData() wfiid: %y (aliases: %y) sdh: %N\n", wfiid, sensitive_data.getAliases(), sdh);
}

OMQ::WFEntry::setupOrderData(OrderData order) {
    if (order.staticdata) {
        sdata = order.staticdata;
    }

    if (order.dynamicdata) {
        ddata.initialize(order.dynamicdata);
    }

    if (order.tempdata) {
        tdata.initialize(order.tempdata);
    }

    if (order.sensitive_data) {
        sensitive_data.initialize(order.sensitive_data);
    }
    #log(LoggerLevel::DEBUG, "WFEntry::setupOrderData(hash) wfiid: %y sd: %N\n", workflow_instanceid, sd);
}

OMQ::WFEntry::releaseAsyncFrontEndSegment(softint segid, WorkflowQueueBase wco) {
    lck.lock();
    on_exit lck.unlock();

    releaseAsyncFrontEndSegmentUnlocked(segid, wco);
}

private string OMQ::WFEntry::releaseAsyncFrontEndSegmentUnlocked(softint segid, WorkflowQueueBase wco) {
    QDBG_ASSERT(ensure_tld());
    # save and restore tld.wfe
    *WFEntry wfe_orig = tld.wfe;
    tld.wfe = self;
    on_exit tld.wfe = wfe_orig;

    string stat = getSegmentStatusNoWaitUnlocked(segid);

    # DEBUG
    #log(LoggerLevel::DEBUG, "WFEntry::releaseAsyncFrontEndSegmentUnlocked() segid: %d stat: %y seg: %y virtual: %y", segid, stat, seg, tld.virtual);

    if (stat != OMQ::StatInProgress && seg[segid].status != stat) {
        seg[segid].status = stat;
        wf.logInfo("updated segment %d status to '%s' (%s)", segid, OMQ::StatMap{stat}, stat);

        switch (stat) {
            case OMQ::StatComplete: {
                wco.removeSegment(workflow_instanceid, segid);
                # stop synchronous recovery thread
                if (sync)
                    wco.terminateSynchronousRetryConnection(tld.index, segid, workflow_instanceid);
                break;
            }
            case OMQ::StatError: {
                wco.removeSegment(workflow_instanceid, segid);
                # stop synchronous workflow
                if (sync)
                    Qorus.control.execHash.(tld.index).setStop();
                break;
            }
            case OMQ::StatRetry: {
                wco.queueRetrySegment(segid, workflow_instanceid, parent_info);
                break;
            }
            case OMQ::StatAsyncWaiting: {
                wco.queueAsyncRetrySegment(segid, workflow_instanceid, parent_info);
                break;
            }
        }
    }

    return stat;
}

# in_progress: is this step already in progress by this segment?
string OMQ::WFEntry::updateFrontEndStepStatusReleaseSegment(softint segid, softstring stepid, softlist ind_list, string stat, WorkflowQueueBase wco, *bool in_progress) {
    # DEBUG
    #log(LoggerLevel::DEBUG, "WFEntry::updateFrontEndStepStatusReleaseSegment() segid: %y stepid: %y ind_list: %y stat: %y in_progress: %y", segid, stepid, ind_list, stat, in_progress);

    # need to lock here to make sure actions are atomic
    lck.lock();
    on_exit lck.unlock();

    try {
        map updateAsyncStepStatusUnlocked(stepid, $1.toInt(), stat, in_progress), ind_list;
        return releaseAsyncFrontEndSegmentUnlocked(segid, wco);
    }
    catch (hash<ExceptionInfo> ex) {
        wf.logInfo("error releasing async front-end segment %d for wfiid: %d (%s sync %y): %s", segid, workflow_instanceid, wf.name, sync, Util::get_exception_string(ex));
        rethrow;
    }
}

# in_progress: is this step already in progress by this segment?
OMQ::WFEntry::updateFrontEndStepStatus(softstring stepid, int ind, string stat, *bool in_progress) {
    # need to lock here to make sure actions are atomic
    lck.lock();
    on_exit lck.unlock();

    try {
        updateAsyncStepStatusUnlocked(stepid, ind, stat, in_progress);
    }
    catch (hash<ExceptionInfo> ex) {
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        rethrow;
    }
}

# returns:
#   -1 if all steps have completed, one or more with ERROR or RETRY status
#    0 if not all steps have a status
#    1 if all steps are COMPLETE
# NOTE: transaction management is performed externally to this call
private int OMQ::WFEntry::tryCreateSegmentUnlocked(softint segid, softstring stepid, softint linksegid) {
    QDBG_ASSERT(ensure_tld());
    # save and restore tld.wfe
    *WFEntry wfe_orig = tld.wfe;
    tld.wfe = self;
    on_exit tld.wfe = wfe_orig;

    int rv = 0;

    try {
        # check if step (all indexes) are complete
        # get step status
        string s = foldl OMQ::SpecialStatusOrder.$1 > OMQ::SpecialStatusOrder.$2 ? $1 : $2, (select keys ssh{stepid}, ssh{stepid}.$1);

        if (s == OMQ::StatComplete) {
            wf.logInfo("array step %d in async segment %d is 'C' (COMPLETE), starting segment %d", stepid, linksegid, segid);

            # DEBUG
            #log(LoggerLevel::DEBUG, "DEBUG: creating back-end segment %d (seg: %y, all: %y)", segid, seg[segid], seg);

            rv = 1;

            # insert segment_instance row
            newSegmentCommitUnlocked(segid);
        } else if (s == OMQ::StatError) {
            wf.logInfo("array step %d in async segment %d is 'E' (ERROR), cannot start segment %d", stepid, linksegid, segid);
            rv = -1;
        } else
            wf.logInfo("array step %d in async segment %d is not yet complete, has status '%s' (%s), cannot start segment %d", stepid, linksegid, OMQ::StatMap{s}, s, segid);

    }
    catch (hash<ExceptionInfo> ex) {
        qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
        # rethrow exception
        rethrow;
    }

    return rv;
}

#  returns:
#   -1 if all steps have completed, one or more with ERROR or RETRY status
#    0 if not all steps have a status
#    1 if all steps are COMPLETE
int OMQ::WFEntry::updateFrontEndStepStatusTryCreateSegment(softint segid, softint fesegid, softint stepid, softint ind, WorkflowQueueBase wco) {
    QDBG_ASSERT(ensure_tld());
    # save and restore tld.wfe
    *WFEntry wfe_orig = tld.wfe;
    tld.wfe = self;
    on_exit tld.wfe = wfe_orig;

    int rv;

    lck.lock();
    on_exit lck.unlock();

    updateAsyncStepStatusUnlocked(stepid, ind, OMQ::StatComplete, True);
    releaseAsyncFrontEndSegmentUnlocked(fesegid, wco);
    return tryCreateSegmentUnlocked(segid, stepid, fesegid);
}

# returns 0 if the new segment can be started, -1 if not
# if the new segment can be started; it means that the step's status was updated to COMPLETE
# and the new segment was created as 'I' (IN-PROGRESS) in the database
# for array steps, it means that the entire step is complete as well
int OMQ::WFEntry::startAsyncSegment(softint segid, softstring stepid, any ind_list, softint fesegid, WorkflowQueueBase wco) {
    QDBG_ASSERT(ensure_tld());
    # save and restore tld.wfe
    *WFEntry wfe_orig = tld.wfe;
    tld.wfe = self;
    on_exit tld.wfe = wfe_orig;

    lck.lock();
    on_exit lck.unlock();

    foreach softint ind in (ind_list) {
        # a retry of the back-end segment could cause the step to be in-progress - which will fail
        waitForStepUnlocked(stepid, ind);

        # if step is already COMPLETE, then do not update step status and do not try to start segment if already started
        if (steps{stepid}[ind].status == OMQ::StatComplete) {
            wf.logInfo("step %d/%d is already 'C' (COMPLETE), discarding message", stepid, ind);
            continue;
        }

        # updates step
        updateAsyncStepStatusUnlocked(stepid, ind, OMQ::StatComplete);
    }

    # updates front-end segment status
    releaseAsyncFrontEndSegmentUnlocked(fesegid, wco);

    # releases the front end segment in the segment event queue
    wco.releaseSegment(workflow_instanceid, fesegid);

    if (ssh{stepid}{OMQ::StatComplete} != elements steps{stepid}) {
        wf.logInfo("cannot start segment %d because step %d is not yet 'C' (COMPLETE)", segid, stepid);
        return -1;
    }

    if (aseg{segid}) {
        wf.logInfo("segment %d has already been started in another thread", segid);
        return -1;
    }

    # reference back-end segment in segment event queue
    if (wco.grabSegmentIncrement(workflow_instanceid, segid)) {
        wf.logInfo("cannot start segment %d due to a retry in progress", segid);
        return -1;
    }

    aseg{segid} = True;

    wf.logInfo("starting segment %d", segid);

    # step is complete, now check segment
    # insert new segment or update existing segment to in-progress
    newSegmentCommitUnlocked(segid);

    #log(LoggerLevel::DEBUG, "DEBUG WFEntry::startAsyncSegment() wfiid %d workflow %d->%d", workflow_instanceid, refs, refs + 1);
    # references workflow, but doesn't create segment_instance row
    ++refs;

    return 0;
}

OMQ::WFEntry::setSegmentError(softint segid) {
    lck.lock();
    on_exit lck.unlock();

    if (!inlist(seg[segid].status, (OMQ::StatComplete, OMQ::StatCanceled, OMQ::StatBlocked))) {
        seg[segid].status = OMQ::StatError;
    }
}

OMQ::WFEntry::setSubWorkflowInfo(softstring stepid, int ind, softint swfiid) {
    # the lock to avoid race conditions with retrieving subworkflow info from the DB
    lck.lock();
    on_exit lck.unlock();
    steps{stepid}[ind].subworkflow = swfiid;
}

OMQ::WFEntry::skipStep(softstring stepid, softint ind, bool swf) {
    lck.lock();
    on_exit lck.unlock();

    # make sure step can be updated
    if (!exists steps{stepid}[ind])
        throw "SKIP-STEP-ERROR", sprintf("stepid %d/%d has not been executed with workflow_instanceid %d", stepid, ind, workflow_instanceid);

    if (!inlist(steps{stepid}[ind].status, (OMQ::StatRetry, OMQ::StatError, OMQ::StatAsyncWaiting, OMQ::StatEventWaiting)))
        throw "SKIP-STEP-ERROR", sprintf("cannot skip step %d/%d with workflow_instanceid %d with status '%s' (%s)", stepid, ind, workflow_instanceid, OMQ::StatMap.(steps{stepid}[ind].status), steps{stepid}[ind].status);

    # make sure no subworkflow step has been bound
    if (swf) {
        *hash swfq = sqlif.workflowInstanceExecuteSubWorkflowStep(workflow_instanceid, stepid, ind);
        if (swfq.val())
            throw "SKIP-STEP-ERROR", sprintf("cannot skip subworkflow step %d/%d with workflow_instanceid %d with bound subworkflow instanceid %d (corrected: %d)", stepid, ind, workflow_instanceid, swfq.subworkflow_instanceid, swfq.currected);
    }

    # FIXME: there is a race condition here; if the order is currently being processed, then
    # we could mark it to be skipped here, with follow-up actions in the calling function, and
    # then the step could be executed anyway in WorkflowInstance

    # flag step execution to be skipped
    steps{stepid}[ind].skip = True;
}

int OMQ::WFEntry::retryWorkflowInstance(*hash cx, WorkflowQueueBase wco) {
    lck.lock();
    on_exit lck.unlock();

    string real_status = self.status;
    if (real_status == OMQ::StatInProgress) {
        real_status = getOnlineOrderStatusUnlocked();
    }

    # make sure workflow has a status that can be updated to RETRY
    if (!inlist(real_status, (OMQ::StatError, OMQ::StatAsyncWaiting, OMQ::StatRetry))) {
        throw "STATUS-ERROR",
            sprintf("can't trigger a retry for workflow order instance ID %d with status '%s' (%s)",
                workflow_instanceid, OMQ::StatMap{real_status}, real_status),
                (
                    "err": "STATUS-ERROR",
                    "status" : real_status,
                );
    }

    # find segments not IN-PROGRESS and update their statuses to RETRY and queue the retries
    list l = ();
    foreach *hash sh in (\seg) {
        # bug 486: qorus cannot recover an order with a gap in the segment list
        if (!sh)
            continue;

        if (sh.status == OMQ::StatRetry) {
            l += $#;
            continue;
        }

        if (!inlist(sh.status, (OMQ::StatError, OMQ::StatAsyncWaiting)))
            continue;

        l += $#;

        sh.status = OMQ::StatRetry;

        # udpate step statuses to RETRY
        foreach softstring stepid in (wf.segment[$#].steplist) {
            int end = elements steps{stepid};
            for (int ind = 0; ind < end; ++ind) {
                if (inlist(steps{stepid}[ind].status, (OMQ::StatError, OMQ::StatAsyncWaiting))) {
                    updateStepStatusUnlocked(stepid, ind, OMQ::StatRetry);
                }
            }
        }
    }

    #printf("DEBUG: self: %N\n", self);

    if (!l) {
        throw "STATUS-ERROR", sprintf("workflow_instanceid %d has no segments with status 'E' (ERROR), 'A' "
            "(ASYNC-WAITING), or 'R' (RETRY) (workflow status is '%s' (%s))", workflow_instanceid,
            OMQ::StatMap{real_status}, real_status),
            ("err": "SEGMENT-ERROR", "status": real_status);
    }

    # update workflow order to IN-PROGRESS
    string stat = OMQ::StatInProgress;

    if (dbstatus != stat) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                sqlif.updateWorkflowStatus(workflow_instanceid, OMQ::StatMap{stat});
                Qorus.audit.workflowStatusChangeNoCommit(cx, workflowid, workflow_instanceid, OMQ::StatMap{dbstatus},
                    OMQ::StatMap{stat});
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

    # raise system event
    # issue #2937: raise system event if internal status has changed
    if (status != stat) {
        Qorus.events.postWorkflowStatusChanged(cx, wf.name, wf.version, workflowid, workflow_instanceid,
            {"old": status, "new": stat});
    }

    # update internal status
    dbstatus = status = stat;

    wco.queueRetrySegments(workflow_instanceid, parent_info, l);

    return elements l;
}

# can only be called from the attach function (if extern is not True)
OMQ::WFEntry::reschedule(*date sched, WorkflowQueueBase wq, *bool extern) {
    lck.lock();
    on_exit lck.unlock();

    if (sched <= now_us()) {
        # ignore calls to reschedule with a date/time in the past
        delete sched;
    }

    # reschedule can only be called when the workflow has never been processed
    if (elements ssh && exists sched) {
        if (extern)
            throw "RESCHEDULE-ERROR", sprintf("workflow_instance %d cannot be rescheduled to %y because the workflow has already been processed", workflow_instanceid, sched);
        else
            throw "RESCHEDULE-ERROR", sprintf("reschedule_order(%y) called, but the workflow has already been processed; reschedule_order() can only be called in the attach function for orders that have never been processed", sched);
    }

    # if the initial segment exists (because of an earlier error), then set the status to READY
    if (exists seg[0].status)
        seg[0].status = OMQ::StatReady;

    # update in DB
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            sqlif.rescheduleWorkflowUnconditional(workflow_instanceid, sched);
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

    reschedule = sched;

    status = exists sched ? OMQ::StatScheduled : OMQ::StatReady;
    wq.rescheduleWorkflow(workflow_instanceid, sched);
    #log(LoggerLevel::DEBUG, "WFEntry::reschedule() reschedule: %y status: %y", reschedule, status);
}

OMQ::WFEntry::reprioritize(int prio, WorkflowQueueBase wq, *bool extern) {
    lck.lock();
    on_exit lck.unlock();

    # update in DB
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            sqlif.reprioritizeWorkflowUnconditional(workflow_instanceid, prio);
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

    priority = prio;

    wq.reprioritizeWorkflow(workflow_instanceid, prio);
    #log(LoggerLevel::DEBUG, "WFEntry::reschedule() reschedule: %y status: %y", reschedule, status);
}

OMQ::WFEntry::blockOrCancel(string stat) {
    lck.lock();
    on_exit lck.unlock();

    # check status
    if (!inlist(stat, (OMQ::StatCanceled, OMQ::StatBlocked))) {
        string err = sprintf("%s-WORKFLOW-ERROR", stat == OMQ::StatCanceled ? "CANCEL" : "BLOCK");
        throw err, sprintf("cannot update workflow_instanceid %d with status %y", workflow_instanceid, stat);
    }

    if (refs && !tld.attachInProgress) {
        string err = sprintf("%s-WORKFLOW-ERROR", stat == OMQ::StatCanceled ? "CANCEL" : "BLOCK");
        throw err, sprintf("cannot %s workflow_instanceid %d as it is currently being processed", stat == OMQ::StatCanceled ? "cancel" : "block", workflow_instanceid);
    }

    # if it's already been blocked then we just return
    # this can happen if the attach function calls setBlocked() twice, for example
    if (status == stat) {
        return;
    }
    # issue workflow status changed event
    Qorus.events.postWorkflowStatusChanged(NOTHING, wf.name, wf.version, workflowid, workflow_instanceid,
        {"old": status, "new": stat});

    status_orig = tld.attachInProgress ? initstatus : status;
    status = stat;
}

OMQ::WFEntry::setError(hash cx) {
    {
        lck.lock();
        on_exit lck.unlock();

        if (refs)
            throw "WORKFLOW-ERROR", sprintf("cannot set workflow_instanceid %d to 'E' (ERROR) as it is currently being processed", workflow_instanceid);
    }
    flushStatus(False, cx);
}

list OMQ::WFEntry::getDBErrors() {
    lck.lock();
    on_exit lck.unlock();

    if (!need_errors)
        return errors;

    if (elements errors < ERROR_LIMIT) {
        # a race condition could occur that causes the first elements in the list to be not
        # in the same order as the acquisition of the error instance ID from the sequence
        # so we use the min() function with a closure to get the minimum value
        *hash meh = elements errors ? min(errors, int sub (hash l, hash r) {return l.error_instanceid <=> r.error_instanceid;}) : NOTHING;

        #printf("before DB errors: meh: %y, %N\n", meh, errors);
        errors = SegmentManagerBase::getDBErrors(workflow_instanceid, meh.error_instanceid) + errors;
        #printf("got DB errors: %N\n", errors);
    }

    delete need_errors;
    return errors;
}

*hash OMQ::WFEntry::getDBSubWorkflowInfo() {
    lck.lock();
    on_exit lck.unlock();

    if (!need_subworkflow)
        return steps;

    *hash q = SegmentManagerBase::getAllSubWorkflowInfo(workflow_instanceid);
    context (q)
        steps.%stepid[%ind].subworkflow = %subworkflow_instanceid;

    delete need_subworkflow;
    return steps;
}

OMQ::WFEntry::setCustomStatus(string stepid, string stat) {
    lck.lock();
    on_exit lck.unlock();
    setCustomStatusUnlocked(stepid, stat);
}

private OMQ::WFEntry::setCustomStatusUnlocked(string stepid, string stat) {
    # to step
    int ind = tld.ind;
    steps{stepid}[ind].custom_status = stat;
#     log(LoggerLevel::FATAL, "WFEntry::setCustomStatus stepid: %y status: %N", stepid, status);

    # to segments
    for (int segid = 0; segid < elements wf.segment; segid++) {
        # don't update the segment custom status if the segment does not exist
        if (inlist(stepid, wf.segment[segid].steplist) && seg[segid].val()) {
            seg[segid].custom_status = stat;
#             log(LoggerLevel::FATAL, "WFEntry::setCustomStatus segid: %y status: %N", segid, stat);
            break;
        } # if
    } # foreach segment

    # to wfi
    # if is it in the "set the real value" state

    # to wfi
    # check the other steps if it is in the "clear the value" state
    if (!exists stat) {
        foreach string key in (keys steps) {
           for (ind = 0; ind < elements steps{key}; ++ind) {
               if (exists steps{key}[ind].custom_status) {
                   custom_status = steps{key}[ind].custom_status;
#                    log(LoggerLevel::FATAL, "WFEntry::setCustomStatus by OTHER STEPS wfiid: %y status: %N", workflow_instanceid, steps{key}[ind].custom_status);
                   return;
               } #if
           } # for ind
        } # foreach ix
    } # if exists
    # no additonal logic here, just set the value or NOTHING. We don't care now.
    custom_status = stat;
#     log(LoggerLevel::FATAL, "WFEntry::setCustomStatus wfiid: %y status: %N", workflow_instanceid, status);
}

OMQ::WFEntry::leaveFeedback(string key, auto value) {
    # convert to a YAML string
    string yaml = serialize_qorus_data(value);

    lck.lock();
    on_exit lck.unlock();

    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            sqlif.upsertFeedback(workflow_instanceid, key, yaml);
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

    feedback{key} = value;
}

auto OMQ::WFEntry::getFeedback(string key) {
    lck.lock();
    on_exit lck.unlock();

    return feedback{key};
}

*hash<auto> OMQ::WFEntry::getFeedback() {
    lck.lock();
    on_exit lck.unlock();

    return feedback;
}

private OMQ::WFEntry::checkStep(softstring stepid, int ind) {
    if (!steps{stepid}[ind]) {
        throw "STEP-ERROR", sprintf("stepid %d[%d] does not exist in workflow instance ID %d", stepid, ind,
            workflow_instanceid);
    }
}

OMQ::WFEntry::lockOrder(string note, *string user) {
    lck.lock();
    on_exit lck.unlock();

    tld.cx.user = user ?? tld.cx.user ?? "%SYS%";

    # to make atomic changes in notes in a restartable transaction
    OrderInstanceNotesHelper oinh(orderInstanceNotes);

    # add note
    oinh.add(("note": note));

    list l;
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            # update operator lock in DB
            sqlif.updateOperatorLockNoCommit(workflow_instanceid, user);

            # save all notes and commit transaction immediately
            l = oinh.saveNoCommit(workflow_instanceid);
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
    oinh.applySaved(l);

    operator_lock = user;
}

OMQ::WFEntry::unlockOrder(string note, *string user) {
    lck.lock();
    on_exit lck.unlock();

    if (!operator_lock)
        return;

    tld.cx.user = user ?? tld.cx.user ?? "%SYS%";

    # to make atomic changes in notes in a restartable transaction
    OrderInstanceNotesHelper oinh(orderInstanceNotes);

    # add note
    oinh.add(("note": note));

    list l;
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            # update operator lock in DB
            sqlif.updateOperatorLockNoCommit(workflow_instanceid);

            # save all notes and commit transaction immediately
            l = oinh.saveNoCommit(workflow_instanceid);
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
    oinh.applySaved(l);

    delete operator_lock;
}

OMQ::WFEntry::breakOrderLock(string note) {
    lck.lock();
    on_exit lck.unlock();

    if (!operator_lock)
        return;

    # to make atomic changes in notes in a restartable transaction
    OrderInstanceNotesHelper oinh(orderInstanceNotes);

    # add note
    oinh.add(("note": note));

    list l;
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            # update operator lock in DB
            sqlif.updateOperatorLockNoCommit(workflow_instanceid);

            # save all notes and commit transaction immediately
            l = oinh.saveNoCommit(workflow_instanceid);
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
    oinh.applySaved(l);

    delete operator_lock;
}
