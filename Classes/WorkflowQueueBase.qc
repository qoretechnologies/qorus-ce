# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus WorkflowQueueBase class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

class OMQ::WorkflowQueueThreadPool {
    private {
        ThreadPool tp;
    }

    destructor() {
        if (tp)
            tp.stopWait();
    }

    start() {
        tp = new ThreadPool(Qorus.options.get("db-max-threads"));
    }

    string getInfo() {
        return tp.toString();
    }

    submitJob(BatchInfo job) {
        job.c.inc();
        tp.submit(sub () {job.execute();}, sub () {job.cancel();});
    }
}

# so workflow parameters can be passed to SegmentEventQueue objects as a reference
class WFParams {
    public {
        *softint async;
        *softint retry;
    }
}

# WorkflowQueue status constants

# no data queued
const WQS_IDLE = 0;
# data is being queued by active jobs in the thread pool
const WQS_STARTING = 1;
# data has been queued and queues are running normally
const WQS_STARTED = 2;
# data is being purged to DB
const WQS_STOPPING = 3;

class OMQ::WorkflowQueueBase inherits AbstractWorkflowQueue, private Mutex {
    public {
        # workflow configuration
        Workflow wf;
    }

    # declare private members
    private {
        # hash of segment queues: segmentid -> queue
        hash<string, SegmentEventQueue> SQ;

        # workflow data cache
        WFParams WC();

        # synchronous workflow cache: wfiid -> segmentid -> queue
        *hash<string, hash<string, SegmentEventQueue>> SW;

        # initial status is idle
        int status = WQS_IDLE;

        # status lock
        Mutex sl();

        # status condition
        Condition scond();

        # status change wait count
        int wait_count = 0;

        # stop flag
        bool stop = False;
    }

    constructor(Workflow wf) {
        # save copy of workflow config
        self.wf = wf;

        WC.async = wf.getLocalOption("async_delay");
        WC.retry = wf.getLocalOption("recover_delay");

        #logDebug("WorkflowQueueBase::constructor start %n", now_us());
        #on_exit logDebug("WorkflowQueueBase::constructor end %n", now_us());

        # create segment structures
        for (int segid = 0; segid < elements wf.segment; ++segid) {
            SQ{segid} = new SegmentEventQueue(WC, Qorus.options);

            if (segid) {
                if (!elements wf.segment[segid].segdeps) {
                    softstring fesegid = wf.segment[segid].linksegment;
                    SegmentEventQueue seq = SQ{fesegid};

                    if (wf.segment[segid].subworkflow)
                        seq.add_subworkflow_segment(segid);
                    else if (wf.segment[segid].event)
                        seq.add_event_segment(segid);
                    else
                        seq.add_async_segment(segid);
                }
            }
        }

        # initialize workflow instance queue
        SQ.wfiq = SQ."0";
    }

    start() {
        AutoLock al(sl);

        QDBG_LOG("WorkflowQueueBase::start() wfid: %d status: %y", wf.workflowid, status);

        # return if the queue has already been started
        if (status == WQS_STARTED || status == WQS_STARTING)
            return;

        while (status == WQS_STOPPING) {
            ++wait_count;
            scond.wait(sl);
            --wait_count;
        }

        # set status to "starting"
        status = WQS_STARTING;

        # unlock lock
        delete al;

        # continue the constructor in the background
        background constructorBackground();
    }

    constructorBackground() {
        ReadyBatchInfo readyBatch(self);
        EventBatchInfo eventBatch(self);

        on_exit {
            sl.lock();
            on_exit sl.unlock();
            status = WQS_STARTED;

            # clear stop flag
            stop = False;

            # wake up any threads waiting on the status to change
            if (wait_count)
                scond.broadcast();
        }

        try {
            # execute the rest of the steps in the background
            if (readyBatch.numSteps())
                readyBatch.executeThreads();

            # execute the rest of the steps in the background
            if (eventBatch.numSteps())
                eventBatch.executeThreads();

            readyBatch.wait();
            eventBatch.wait();
        } catch (hash<ExceptionInfo> ex) {
            Qorus.logInfo(get_exception_string(ex));
            string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            logInfo(err);
            logInfo("fatal error initializing workflow, stopping all instances of %s:%s", wf.name, wf.version);
            background Qorus.control.stopWorkflow(NOTHING, wf.name, wf.version, NOTHING, "fatal error initializing workflow: " + err);
        }
    }

    bool checkDelete() {
        return stop;
    }

    Workflow getWorkflow() {
        return wf;
    }

    # sets the "stop" flag and returns immediately
    stop() {
        sl.lock();
        on_exit sl.unlock();
        QDBG_LOG("WorkflowQueueBase::stop() status: %y stop: %y", status, stop);
        # return if the queue is not starting
        if (status != WQS_STARTING) {
            return;
        }

        #dbg("WorkflowQueueBase::stop() called");
        stop = True;
    }

    # purge queues
    flush() {
        {
            sl.lock();
            on_exit sl.unlock();

            # wait for background jobs to complete if they are running
            while (status != WQS_STARTED && status != WQS_IDLE) {
                if (status == WQS_STARTING) {
                    #dbg("WorkflowQueueBase::flush() stop called");
                    stop = True;
                }

                ++wait_count;
                scond.wait(sl);
                --wait_count;
            }

            if (status == WQS_IDLE)
                return;

            status = WQS_STOPPING;
        }

        # this class will perform all the work of purging the queues
        new DestructorBatchInfo(self);

        sl.lock();
        on_exit sl.unlock();
        status = WQS_IDLE;

        if (wait_count)
            scond.broadcast();
    }

    destructor() {
        try {
            flush();
        } catch (hash<ExceptionInfo> ex) {
            logFatal("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            Qorus.logInfo(Util::get_exception_string(ex));
        }
    }

    private string enrichLogMessage(string msg, auto args) {
        return sprintf("%s:%s(%d) CACHE: %s", wf.name, wf.version, wf.workflowid, vsprintf(msg, args));
    }

    logFatal(string msg) {
        wf.logFatal("%s", enrichLogMessage(msg, argv));
    }

    logError(string msg) {
        wf.logError("%s", enrichLogMessage(msg, argv));
    }

    logWarn(string msg) {
        wf.logWarn("%s", enrichLogMessage(msg, argv));
    }

    logInfo(string msg) {
        wf.logInfo("%s", enrichLogMessage(msg, argv));
    }

    logDebug(string msg) {
        wf.logDebug("%s", enrichLogMessage(msg, argv));
    }

    logTrace(string msg) {
        wf.logTrace("%s", enrichLogMessage(msg, argv));
    }

    initWorkflowInstanceQueue(softint min, softint max) {
        #logDebug("WorkflowQueueBase::initWorkflowInstanceQueue start %y", now_us());
        #on_exit logDebug("WorkflowQueueBase::initWorkflowInstanceQueue end %y", now_us());
        # synchronous = 1 not possible

        *hash<auto> res;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                res = sqlif.workflowQueueInitWorkflowInstanceQueue(min, max, Qorus.getSessionId(), wf.workflowid);
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

        list<auto> l = map ($1 + ("parent_info": $1.("parent_workflow_instanceid","subworkflow")) - ("parent_workflow_instanceid", "subworkflow")), res.contextIterator();
        SQ.wfiq.init_primary_queue(l);

        if (l)
            logInfo("queued %d READY workflow instance row%s (min: %d, max: %d)", elements l, elements l == 1 ? "" : "s", min, max);
    }

    # called in WorkflowQueueBase::initSegmentEventCache()
    # splits events in separate lists per segment for adding to the appropriate segment queues
    private static *hash<auto> seghash(list<auto> lst) {
        hash<auto> rh;
        foreach hash<auto> i in (lst) {
            softstring segid = i.segmentid;
            if (!exists rh{segid})
                rh{segid} = ();

            i.parent_info = remove i.("parent_workflow_instanceid", "subworkflow");

            rh{segid} += i;
        }
        return rh;
    }

    initSegmentEventCache(softint min, softint max) {
        #logDebug("WorkflowQueueBase::initSegmentEventCache start %n", now_us());
        #on_exit logDebug("WorkflowQueueBase::initSegmentEventCache end %n", now_us());

        *hash<auto> res;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                res = sqlif.workflowQueueInitCommonSegments(min, max, Qorus.getSessionId(), wf.workflowid);
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
        int segmentCount = elements wf.segment - 1;

        # declare event lists
        list<auto> irqlist = list<auto> arqlist = list<auto> pqlist = ();
        context (res) {
            if (%segmentstatus == "R")
                irqlist += %%;
            else if (%segmentstatus == "A") {
                if (%segmentid == segmentCount) {
                    logFatal("received illegal asynchronous event %y for final segment; discarding event.  This normally is a result of an invalid redefinition of a workflow with existing incompatible data", %%);
                    continue;
                } else
                    arqlist += %%;
            } else if (%segmentstatus == "Y") {
                pqlist += %%;
            }
        }

        # split event lists by segment
        *hash<auto> irh = WorkflowQueueBase::seghash(irqlist);
        *hash<auto> arh = WorkflowQueueBase::seghash(arqlist);
        *hash<auto> pqh = WorkflowQueueBase::seghash(pqlist);

        logInfo("segment retry cache: min: %n max: %n rows: %d retry: %d (segs: %d) async: %d (segs: %d) ready: %d (segs: %d)", min, max, elements res.workflow_instanceid, elements irqlist, elements irh, elements arqlist, elements arh, elements pqlist, elements pqh);

        # add events to appropriate queues
        map SQ.$1.init_retry_queue(irh.$1), keys irh;
        map SQ.$1.init_async_retry_queue(arh.$1), keys arh;
        map SQ.$1.init_primary_queue(pqh.$1), keys pqh;
    }

    # called in WorkflowQueueBase::initSegmentAsyncCache()
    # adds async events to the proper list for later adding to the queue
    private static addEvent(reference eh, softstring fesegid, softstring segid, hash<auto> row) {
        if (!exists eh{fesegid}{segid})
            eh{fesegid}{segid} = ();

        # FIXME: eliminate need for this hash in queue initialization
        row.parent_info = remove row.("parent_workflow_instanceid", "subworkflow");

        eh{fesegid}{segid} += row;
    }

    initSegmentAsyncCache(softint min, softint max) {
        #logDebug("WorkflowQueueBase::initSegmentAsyncCache start %n", now_us());
        #on_exit logDebug("WorkflowQueueBase::initSegmentAsyncCache end %n", now_us());

        hash qres;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                qres = sqlif.workflowQueueInitCommonSubAsync(min, max, Qorus.getSessionId(), wf.workflowid);
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

        #printf("wfid: %d min: %d max: %d sess: %d qres: %N\n", wf.workflowid, min, max, Qorus.getSessionId(), qres);

        # event hash: # front-end segmentid -> back-end segmentid -> event list
        hash<auto> eh;
        # process subworkflow events
        context (qres.subwf) {
            *softint segid = wf.stepseg.%stepid;
            if (!exists segid || !wf.segment[segid].subworkflow) {
                logFatal("received illegal subworkflow event %n from stepid %d which is no longer a subworkflow "
                    "step; discarding event. This normally is a result of an invalid redefinition of a workflow with "
                    "existing incompatible data", %%, %stepid);
                continue;
            }

            WorkflowQueueBase::addEvent(\eh, wf.segment[segid].linksegment, segid, %%);
        }

        # process asynchronous queue events
        context (qres.queue) {
            *softint segid = wf.stepseg.%stepid;
            if (!exists segid || wf.segment[segid].subworkflow || wf.segment[segid].event) {
                logFatal("received illegal async queue event %n from stepid %d which is no longer an asynchronous "
                    "step; discarding event. This normally is a result of an invalid redefinition of a workflow with "
                    "existing incompatible data", %%, %stepid);
                continue;
            }

            WorkflowQueueBase::addEvent(\eh, wf.segment[segid].linksegment, segid, %%);
        }

        # process workflow synchronization events
        context (qres.sync) {
            *softint segid = wf.stepseg.%stepid;
            if (!exists segid || !wf.segment[segid].event) {
                logFatal("received illegal workflow sync event %n from stepid %d which is no longer a workflow "
                    "synchronization step; discarding event. This normally is a result of an invalid redefinition of "
                    "a workflow with existing incompatible data", %%, %stepid);
                continue;
            }

            WorkflowQueueBase::addEvent(\eh, wf.segment[segid].linksegment, segid, %%);
        }

        logInfo("async event cache: min: %n max: %n subworkflow rows: %d async rows: %d segs: %d", min, max,
            elements qres.subwf.workflow_instanceid, elements qres.queue.workflow_instanceid, elements eh);

        #printf("eh: %N\n", eh);
        foreach string fe in (keys eh) {
            foreach string be in (keys eh{fe}) {
                list<auto> l = eh{fe}{be};
                if (l[0].subworkflow_instanceid)
                    SQ{fe}.init_subworkflow_queue(be, l);
                else if (exists l[0].queueid)
                    SQ{fe}.init_async_queue(be, l);
                else
                    SQ{fe}.init_event_queue(be, l);
            }
        }
    }

    registerInitialSegment(softint wfiid) {
        SegmentEventQueue seq = SQ.wfiq;
        seq.grab_segment_inc(wfiid);
    }

    registerInitialSynchronousSegment(softstring wfiid) {
        SegmentEventQueue seq = SW{wfiid}."0";
        seq.grab_segment_inc(wfiid);
    }

    releaseSegment(softstring wfiid, softstring segid) {
        SegmentEventQueue seq = tld.sync ? SW{wfiid}{segid} : SQ{segid};

        # DEBUG
        on_error logFatal("WorkflowQueueBase::releaseSegment(wfiid: %n, segid: %n) sync: %n seq: %N", wfiid, segid,
            tld.sync, seq);

        seq.release_segment(wfiid);
    }

    releaseRetrySegment(softstring wfiid, softstring segid) {
        SegmentEventQueue seq = tld.sync ? SW{wfiid}{segid} : SQ{segid};

        # DEBUG
        on_error logFatal("WorkflowQueueBase::releaseRetrySegment(wfiid: %n, segid: %n) sync: %n seq: %N", wfiid,
            segid, tld.sync, seq);

        seq.release_retry_segment(wfiid);
    }

    removeSegment(softstring wfiid, softstring segid) {
        SegmentEventQueue seq = tld.sync ? SW{wfiid}{segid} : SQ{segid};
        seq.remove_workflow_instance(wfiid);
    }

    private resetConnection(softstring index) {
        map SQ{$1}.cleanup_connection(index), xrange(wf.segment.size());
        /*
        for (int segid = 0; segid < elements wf.segment; segid++)
            SQ{segid}.cleanup_connection(index);
        */
    }

    cleanupConnection(softstring index) {
        resetConnection(index);
    }

    terminateSynchronousConnections(softstring wfiid, softint index) {
        if (SW{wfiid}) {
            map SW{wfiid}{$1}.terminate_connection(index), xrange(wf.segment.size());
            /*
            # terminate waiting threads for this workflow instance
            for (int segid = 0; segid < elements wf.segment; segid++)
                SW{wfiid}{segid}.terminate_connection(index);
            */
        }
    }

    terminateConnections(softint index) {
        map SQ{$1}.terminate_connection(index), xrange(wf.segment.size());
        /*
        for (int segid = 0; segid < elements wf.segment; segid++)
            SQ{segid}.terminate_connection(index);
        */
    }

    terminateSynchronousRetryConnection(softint index, softstring segid, softstring wfiid) {
        SW{wfiid}{segid}.terminate_retry_connection(index);
    }

    *hash<auto> waitForReadyWorkflowInstance(softint index) {
        SegmentEventQueue seq = SQ.wfiq;
        return seq.get_primary_event(index);
    }

    *hash<auto> waitForDetachedSegment(softint index, softstring segid) {
        SegmentEventQueue seq = SQ{segid};
        *hash<auto> rv = seq.get_primary_event(index);
        if (exists rv && !seq.grab_segment_inc(rv.workflow_instanceid))
            return rv;
    }

    *hash<auto> waitForSynchronousDetachedSegment(softint index, softstring segid, softstring wfiid) {
        SegmentEventQueue seq = SW{wfiid}{segid};
        *hash<auto> rv = seq.get_primary_event(index);
        if (exists rv && !seq.grab_segment_inc(rv.workflow_instanceid))
            return rv;
    }

    bool grabSegmentIncrement(softstring wfiid, softstring segid) {
        SegmentEventQueue seq = exists SW{wfiid} ? SW{wfiid}{segid} : SQ{segid};
        return seq.grab_segment_inc(wfiid);
    }

    *hash<auto> getSubWorkflowEvent(softint index, softstring fesegid, softstring besegid) {
        SegmentEventQueue seq;
        SegmentEventQueue beq;
        if (tld.sync) {
            seq = SW.(tld.sync){fesegid};
            beq = SW.(tld.sync){besegid};
        } else {
            seq = SQ{fesegid};
            beq = SQ{besegid};
        }
        return seq.get_subworkflow_event(index, besegid, beq);
    }

    *hash<auto> getAsyncEvent(softint index, softstring fesegid, softstring besegid) {
        SegmentEventQueue seq;
        SegmentEventQueue beq;
        if (tld.sync) {
            seq = SW.(tld.sync){fesegid};
            beq = SW.(tld.sync){besegid};
        } else {
            seq = SQ{fesegid};
            beq = SQ{besegid};
        }
        return seq.get_async_event(index, besegid, beq);
    }

    *hash<auto> getSyncEvent(softint index, softstring fesegid, softstring besegid) {
        SegmentEventQueue seq;
        SegmentEventQueue beq;
        if (tld.sync) {
            seq = SW.(tld.sync){fesegid};
            beq = SW.(tld.sync){besegid};
        } else {
            seq = SQ{fesegid};
            beq = SQ{besegid};
        }
        return seq.get_workflow_event(index, besegid, beq);
    }

    *hash<auto> getRetryEvent(softint index, softstring segid) {
        SegmentEventQueue seq = SQ{segid};
        return seq.get_retry_event(index);
    }

    # called when queuing events for a workflow instance set from 'X' to 'E'
    queueRetrySegment(softstring segid, softstring wfiid, *hash parent_info, date modified = now()) {
        #logDebug("DEBUG: queueRetrySegment(segid: %n, wfiid: %n, parent: %n)\n", segid, wfiid, parent_info);
        #try throw True; catch (hash<ExceptionInfo> ex) { logInfo("location: %s", get_exception_string(ex)); }

        SegmentEventQueue seq = tld.sync ? SW{wfiid}{segid} : SQ{segid};
        seq.queue_retry_event(wfiid, modified, parent_info);
    }

    queueRetrySegmentFixed(softint segid, softint wfiid, *hash parent_info, date trigger) {
        #logDebug("DEBUG: queueRetrySegmentFixed(segid: %n, wfiid: %n, parent: %n, trigger: %n)\n", segid, wfiid, parent_info, trigger);
        #try throw True; catch (hash<ExceptionInfo> ex) { logInfo("location: %s", get_exception_string(ex)); }
        QDBG_ASSERT(trigger.absolute());

        SegmentEventQueue seq = tld.sync ? SW{wfiid}{segid} : SQ{segid};
        seq.queue_retry_event_fixed(wfiid, trigger, parent_info);
    }

    # called when queuing events for a workflow instance set from 'X' to 'E'
    queueAsyncRetrySegment(softstring segid, softstring wfiid, *hash parent_info, date modified = now()) {
        SegmentEventQueue seq = tld.sync ? SW{wfiid}{segid} : SQ{segid};
        seq.queue_async_retry_event(wfiid, modified, parent_info);
    }

    *hash getSynchronousRetryEvent(softint index, softstring segid, softstring wfiid) {
        SegmentEventQueue seq = SW{wfiid}{segid};
        return seq.get_retry_event(index);
    }

    addToWorkflowInstanceQueue(softint wfiid, int priority, *hash parent_info, *date scheduled) {
        SegmentEventQueue seq = SQ.wfiq;
        seq.queue_primary_event(wfiid, priority, parent_info, scheduled);
    }

    # called externally
    queueRetrySegments(softint wfiid, *hash parent_info, list list) {
        #logDebug("queueRetrySegments(wfiid: %n, parent: %n, list: %n)", wfiid, parent_info, list);

        lock();
        on_exit unlock();

        foreach softstring segid in (list) {
            # DEBUG
            #logDebug("queueRetrySegment(segid: %n, wfiid: %n)", e.segmentid, wfiid);

            if (exists SW{wfiid}) {
                queueImmediateRetrySegmentIntern(wfiid, parent_info, SW{wfiid}{segid});
            }
            else {
                queueImmediateRetrySegmentIntern(wfiid, parent_info, SQ{segid});
            }
        }
    }

    private queueImmediateRetrySegmentIntern(softint wfiid, *hash<auto> parent_info, SegmentEventQueue q) {
        q.queue_retry_event_fixed(wfiid, 1970-01-01Z, parent_info);
    }

    registerCompleteSegment(softstring segid, softstring wfiid, int priority, list<auto> seglist) {
        SegmentEventQueue seq = tld.sync ? SW{wfiid}{segid} : SQ{segid};
        seq.remove_workflow_instance(wfiid);

        # add each dependent segment that can be started to internal queue
        foreach softstring dsegid in (seglist) {
            seq = tld.sync ? SW{wfiid}{dsegid} : SQ{dsegid};
            seq.queue_primary_event(wfiid, priority, tld.wfe.parent_info);
        }
    }

    # only to be called when a workflow has gone from status 'X' to 'E'
    queueDetachedSegment(softstring segid, softint wfiid, int priority, *hash<auto> parent_info) {
        SegmentEventQueue seq = SQ{segid};

        seq.queue_primary_event(wfiid, priority, parent_info);
    }

    updateQueue(softstring stepid, softint wfiid, softint ind, softint prio, softbool corrected, string queuekey,
            auto data, *hash<auto> parent_info) {
        # get segment IDs
        softint besegid;
        softstring fesegid;

        try {
            besegid = wf.stepseg{stepid};
            fesegid = wf.segment[besegid].linksegment;
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "RUNTIME-TYPE-ERROR") {
                rethrow;
            }
            Qorus.logInfo("%s", get_exception_string(ex));
            throw "WORKFLOW-DEFINITION-ERROR", sprintf("workflow %s v%s (%d) is expecting an asynchronous step at "
                "stepid %d, but the step either does not exist in the new definition or is no longer asychronous; "
                "the workflow is now incompatible with the existing workflow order data, which can no longer be "
                "processed with the new definition", wf.name, wf.version, wf.workflowid, stepid);
        }

        # DEBUG
        #logDebug("WorkflowQueueBase::updateQueue(stepid: %n, h: %n) besegid: %n, fesegid: %n", stepid, h, besegid, fesegid);

        SegmentEventQueue seq;

        lock();
        on_exit unlock();

        # see if it's a synchronous workflow
        if (exists SW{wfiid})
            seq = SW{wfiid}{fesegid};
        else
            seq = SQ{fesegid};

        seq.queue_async_event(besegid, wfiid, ind, prio, corrected, queuekey, data, parent_info);
    }

    postSyncEvent(softstring stepid, softint wfiid, softint ind, softint prio, *hash<auto> parent_info) {
        # get segment IDs
        softint besegid;
        softstring fesegid;

        try {
            besegid = wf.stepseg{stepid};
            fesegid = wf.segment[besegid].linksegment;
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "RUNTIME-TYPE-ERROR") {
                rethrow;
            }
            throw "WORKFLOW-DEFINITION-ERROR", sprintf("workflow %s v%s (%d) is expecting a workflow event step at "
                "stepid %d, but the step either does not exist in the new definition or is no longer asychronous; "
                "the workflow is now incompatible with the existing workflow order data, which can no longer be "
                "processed with the new definition", wf.name, wf.version, wf.workflowid, stepid);
        }

        # DEBUG
        #logDebug("WorkflowQueueBase::updateQueue(stepid: %n, h: %n) besegid: %n, fesegid: %n", stepid, h, besegid, fesegid);

        lock();
        on_exit unlock();

        # see if it's a synchronous workflow
        SegmentEventQueue seq = exists SW{wfiid} ? SW{wfiid}{fesegid} : SQ{fesegid};

        seq.queue_workflow_event(besegid, wfiid, ind, prio, parent_info);
    }

    # update the subworkflow queue only if the entry isn't already there
    # this is necessary if, for example, the attach function fails when a subworkflow segment should be
    # started...
    # 3 workflows here: subworkflow -> workflow -> parent workflow (grandparent workflow)
    # swfiid: subworkflow instance with a status update
    #
    # wfiid: workflow instance being updated
    # stepid: workflow stepid being updated
    # ind: workflow ind being updated
    #
    # parent_info: grandparent workflow instance info
    updateSubWorkflowQueue(softstring wfiid, softint stepid, softint ind, softint prio, softint swfiid,
            *hash<auto> parent_info, string stat) {
        softint besegid;
        softstring fesegid;

        try {
            besegid = wf.stepseg{stepid};
            fesegid = wf.segment[besegid].linksegment;
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "RUNTIME-TYPE-ERROR") {
                rethrow;
            }
            throw "WORKFLOW-DEFINITION-ERROR", sprintf("workflow %s v%s (%d) is expecting a subworkflow step at "
                "stepid %d, but the step either does not exist in the new definition or is no longer asychronous; "
                "the workflow is now incompatible with the existing workflow order data, which can no longer be "
                "processed with the new definition", wf.name, wf.version, wf.workflowid, stepid);
        }

        #logDebug("updateSubWorkflowQueue(xxx) besegid: %n, fesegid: %n", xxx, besegid, fesegid);
        #try throw True; catch (hash<ExceptionInfo> ex) { logInfo(get_exception_string(ex)); }

        lock();
        on_exit unlock();

        QDBG_LOG("WorkflowQueueBase::updateSubWorkflowQueue() wfiid: %d stepid: %d/%d swfiid: %d stat: %y SYNC: %y "
            "(SWF SYNC: %y)", wfiid, stepid, ind, swfiid, stat, exists SW{wfiid}, exists SW{swfiid});

        # check if it's a synchronous workflow
        SegmentEventQueue seq = exists SW{wfiid} ? SW{wfiid}{fesegid} : SQ{fesegid};

        seq.queue_subworkflow_event(besegid, wfiid, ind, prio, OMQ::StatMap{stat}, swfiid, parent_info);
    }

    updateRetryDelay(*softint val) {
        WC.retry = val;
    }

    updateAsyncDelay(*softint val) {
        WC.async = val;
    }

    *string getCacheAsString() {
        string str;

        lock();
        on_exit unlock();

        for (int segid = 0; segid < elements wf.segment; segid++) {
            str += sprintf("\n  segment %d: %s", segid, SQ{segid}.toString());
        }

        foreach string wfiid in (keys SW) {
            str += sprintf("\n  synchronous workflow order data instance %d:", wfiid);
            for (int segid = 0; segid < elements wf.segment; segid++) {
                str += sprintf("\n    segment %d: %s", segid, SW{wfiid}{segid}.toString());
            }
        }

        return str;
    }

    *string getCacheSummary() {
        string str;

        lock();
        on_exit unlock();

        for (int segid = 0; segid < elements wf.segment; segid++) {
            str += sprintf("\n  segment %d: %s", segid, SQ{segid}.getSummary());
        }

        foreach string wfiid in (keys SW) {
            str += sprintf("\n  synchronous workflow order data instance %d:", wfiid);
            for (int segid = 0; segid < elements wf.segment; segid++) {
                str += sprintf("\n    segment %d: %s", segid, SW{wfiid}{segid}.getSummary());
            }
        }

        return str;
    }

    registerSynchronousWorkflow(softstring wfiid) {
        lock();
        on_exit unlock();

        for (int segid = 0; segid < elements wf.segment; segid++) {
            SW{wfiid}{segid} = new SegmentEventQueue(WC, Qorus.options);

            if (segid && !elements wf.segment[segid].segdeps) {
                softstring fesegid = wf.segment[segid].linksegment;

                SegmentEventQueue seq = SW{wfiid}{fesegid};
                if (wf.segment[segid].subworkflow)
                    seq.add_subworkflow_segment(segid);
                else if (wf.segment[segid].event)
                    seq.add_event_segment(segid);
                else
                    seq.add_async_segment(segid);
            }
        }
    }

    deregisterSynchronousWorkflow(softstring wfiid) {
        lock();
        on_exit unlock();

        # move any remaining queue entries to normal queues
        for (int segid = 0; segid < elements wf.segment; segid++) {
            # in case of an initialization error, some segment queues may not exist
            if (exists SW{wfiid}{segid})
                SQ{segid}.merge_all(SW{wfiid}{segid});
        }

        delete SW{wfiid};
    }

    requeueAllRetries() {
        lock();
        on_exit unlock();

        #printf("WorkflowQueueBase::requeueAllRetries() wfid: %d wf.segment: %y()\n", wf.workflowid, wf.segment);

        for (int segid = 0; segid < elements wf.segment; segid++) {
            SegmentEventQueue seq = SQ{segid};
            #printf("WorkflowQueueBase::requeueAllRetries() wfid: %d seg: %d calling requeue_retries()\n", wf.workflowid, segid);
            seq.requeue_retries();
            foreach string wfiid in (keys SW) {
                seq = SW{wfiid}{segid};
                seq.requeue_retries();
            }
        }
    }

    bool rescheduleWorkflow(softint wfiid, auto scheduled) {
        SegmentEventQueue seq = SQ.wfiq;
        return seq.resched_primary_event(wfiid, scheduled);
    }

    bool reprioritizeWorkflow(softint wfiid, int prio) {
        SegmentEventQueue seq = SQ.wfiq;
        return seq.reprioritize_primary_event(wfiid, prio);
    }

    # issue 1861: remove BLOCKED/CANCELED orders from all queues immediately
    removeWorkflowOrder(softint wfiid, softint prio) {
        cast<SegmentEventQueue>(SQ.wfiq).removeWorkflowOrder(wfiid, prio);
    }
}

class OMQ::BatchInfo {
    private {
        list steps = ();
        WorkflowQueueBase wfq;
        Workflow wf;

        # current step for info reporting
        *hash current;
    }

    public {
        Counter c();
        string mode;
    }

    constructor(WorkflowQueueBase q) {
        wfq = q;
        wf = q.getWorkflow();
    }

    # initiates all processing in background threads
    executeThreads() {
        Qorus.wqtp.submitJob(self);
    }

    string getInfo() {
        string str = sprintf("%s/%s(%d): %s: ", wf.name, wf.version, wf.workflowid, mode);
        *hash c = current;
        if (!c)
            str += "done";
        else
            str += sprintf("min: %d max: %d", c.min, c.max);
        return str;
    }

    # returns the number of steps
    private int initData(hash init, bool first_small = False) {
        # gives max blocksize rows for each block

        # convert all values to integer
        map (init.$1 = int(init.$1)), keys init;

        # failsafe settings for an empty database
        if (init.minimum == 0 && init.maximum == 0) {
            wfq.logInfo("no rows to process for %s events", getType());
            return 0;
        }

        # regular run
        int min = init.minimum;

        int blocks = init.count / Qorus.options.get("sql-default-blocksize");
        # ensure there is at least 1 block
        blocks = blocks ?* 1;
        int stepsize = (init.maximum - min) / blocks;
        int initstepsize = Qorus.options.get("sql-init-blocksize");

        while (min <= init.maximum) {
            int max = min + stepsize;
            if (first_small && (max - min) > initstepsize) {
                max = min + initstepsize;
                first_small = False;
            }
            if (max > init.maximum)
                max = init.maximum;
            hash step = ( "min"    : min,
                    "max"    : max,
                    "count"  : max - min );

            min = max + 1;
            steps += step;
        }

        wfq.logInfo("initializing steps for %s events: min: %N, max: %N, size: %N, cnt: %N",
                getType(), init.minimum, init.maximum, stepsize, elements steps);

        return elements steps;
    }

    execute() {
        on_exit c.dec();
        executeImpl();
    }

    cancel() {
        c.dec();
    }

    # abstract methods
    abstract executeImpl();
    abstract string getType();

    int numSteps() {
        return elements steps;
    }

    private int getThreads() {
        softint nthreads = Qorus.options.get("db-max-threads");
        if (elements steps < nthreads)
            nthreads = elements steps;
        return nthreads;
    }
}

class ConstructorBatchInfo inherits BatchInfo {
    constructor(WorkflowQueueBase wfq) : BatchInfo(wfq) {
    }

    executeImpl() {
        #on_exit wfq.logDebug("ConstructorBatchInfo::executeImpl() %s %d steps EXITING", getType(), elements steps);
        try {
            while (!wfq.checkDelete()) {
                #wfq.logDebug("ConstructorBatchInfo::executeImpl() %s %d steps", getType(), elements steps);
                current = shift steps;
                #wfq.logDebug("ConstructorBatchInfo::executeImpl() %s %d steps; got %n", getType(), elements steps, current);
                if (!exists current)
                    return;
                executeStep(current);
            }
        } catch (hash<ExceptionInfo> ex) {
            Qorus.logInfo(Util::get_exception_string(ex));
            string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            wfq.logInfo(err);
            wfq.logInfo("fatal error initializing workflow, stopping all instances of %s:%s", wf.name, wf.version);
            background Qorus.control.stopWorkflow(NOTHING, wf.name, wf.version, NOTHING, "fatal error initializing workflow: " + err);
        }
    }

    private executeStep(hash step) {
        wfq.logInfo("%s block: min: %d max: %d blocks remaining: %d", getType(), step.min, step.max, elements steps);
        #on_exit wfq.logDebug("ConstructorBatchInfo::executeStep() %s step: %n done (%d remaining)", getType(), step, elements steps);

        QorusRestartableTransaction trans();
        while (True) {
            try {
                # grab workflows
                on_error omqp.rollback();
                on_success omqp.commit();

                int rows = doSQL(step);
                if (rows)
                    wfq.logInfo("updated %d %s workflow instance row%s", rows, getType(), rows == 1 ? "" : "s");
                else {
                    wfq.logInfo("no rows in range %d - %d for %s events", step.min, step.max, getType());
                    return;
                }
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                Qorus.logInfo(Util::get_exception_string(ex));
                wfq.logInfo("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                rethrow;
            }
            trans.reset();
            break;
        }

        doQueue(step);
    }

    # abstract methods

    # transaction recoverability handled by the caller
    abstract int doSQL(hash step);
    abstract doQueue(hash step);
    abstract string getType();

    doInlineStep() {
        # perform initial step inline to ensure there are no catastrophic errors
        hash step = shift steps;
        #wfq.logDebug("running inline (mode: %s): %N %N", mode, step.min, step.max);
        executeStep(step);
    }

    wait() {
        c.waitForZero();
    }
}

class OMQ::ReadyBatchInfo inherits ConstructorBatchInfo {
    constructor(WorkflowQueueBase wfq) : ConstructorBatchInfo(wfq) {
        mode = "Y";
        hash init;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                init = sqlif.workflowReadyQueueInit(wf.workflowid);
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

        initData(init, True);
    }

    string getType() {
        return "READY";
    }

    # transaction recoverability handled by the caller
    int doSQL(hash step) {
        return sqlif.workflowReadyQueueConstructor(step.min, step.max, Qorus.getSessionId(), wf.workflowid);
    }

    # transaction recoverability handled in the method below
    doQueue(hash step) {
        wfq.initWorkflowInstanceQueue(step.min, step.max);
    }
}

class OMQ::EventBatchInfo inherits ConstructorBatchInfo {
    constructor(WorkflowQueueBase wfq) : ConstructorBatchInfo(wfq) {
        mode = "ALL";
        hash init;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                init = sqlif.workflowEventQueueInit(wf.workflowid);
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

        initData(init, True);
    }

    string getType() {
        return "RETRY, WAITING, ASYNC-WAITING, and EVENT-WAITING";
    }

    # transaction recoverability handled by the caller
    int doSQL(hash step) {
        return sqlif.workflowEventQueueConstructor(step.min, step.max, Qorus.getSessionId(), wf.workflowid);
    }

    # transaction recoverability handled in each method below
    doQueue(hash step) {
        # queue retry, ready, and async-waiting events
        wfq.initSegmentEventCache(step.min, step.max);

        # queue asynchronous subworkflow, async queue, and workflow sycnhronization events
        wfq.initSegmentAsyncCache(step.min, step.max);
    }
}

class OMQ::DestructorBatchInfo inherits BatchInfo {
    constructor(WorkflowQueueBase wfq) : BatchInfo(wfq) {
        mode = "DESTRUCTOR";
        hash init;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                init = sqlif.workflowDestructorQueueInit(wf.workflowid, Qorus.getSessionId());
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

        initData(init);

        if (!elements steps)
            return;

        # execute all processing in background threads
        executeThreads();

        # wait until threads complete
        c.waitForZero();
    }

    executeImpl() {
        while (True) {
            current = shift steps;
            if (!exists current)
                break;

            hash step = current;
            #wfq.logDebug("DestructorBatchInfo::execute() min: %n max: %n", step.min, step.max);
            #on_exit wfq.logDebug("DestructorBatchInfo::execute() min: %n max: %n", step.min, step.max);

            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error sqlif.rollback();
                    on_success sqlif.commit();

                    int rows = sqlif.workflowQueueDestructor(step.min, step.max, Qorus.getSessionId(), wf.workflowid);
                    wfq.logInfo("released %d workflow instance%s", rows, rows == 1 ? "" : "s");
                    QDBG_TEST_CLUSTER_FAILOVER();
                }
                catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex))
                        continue;
                    wfq.logInfo("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                    Qorus.logInfo(get_exception_string(ex));
                }
                trans.reset();
                break;
            }
        }
    }

    string getType() {
        return "session release";
    }
}
