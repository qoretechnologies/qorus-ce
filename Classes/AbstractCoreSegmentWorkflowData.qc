# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus AbstractCoreSegmentWorkflowData class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

# manages contention in the core segment manager
class OMQ::AbstractCoreSegmentWorkflowData inherits AbstractSegmentWorkflowData {
    private {
        # reference count
        int refs = 1;

        # queue reference count
        int qrefs = 0;

        # temporary ref count
        int trefs = 0;

        # reset condition
        Condition rcond();

        # reset waiting
        int rw = 0;

        # reset in progress flag
        bool rip = False;
    }

    private:internal {
        # restart waiting count; for cluster process restart actions
        int restart_waiting = 0;

        # restart cluster process condition variable
        Condition restart_cond();
    }

    public {
        # restart counter
        Counter RC;

%ifdef QorusDebugInternals
        *int rtid;
%endif

        # manual block count
        int bcnt = 0;

        # waiting on manual block flag
        int bw = 0;

        # manual block cleared condition
        Condition bcond();
    }

    constructor(Workflow wf, bool qref, bool temp) : AbstractSegmentWorkflowData(wf) {
        # DEBUG
        QDBG_LOG("AbstractCoreSegmentWorkflowData::constructor(qref: %y, temp: %y) refs: 0 -> %d qrefs: 0 -> %d trefs: %d", qref, temp, refs, qref ? 1 : 0, trefs);

        if (qref) {
            QDBG_ASSERT(!temp);
            ++qrefs;
        } else if (temp) {
            ++trefs;
        }

        if (refs > trefs) {
            startProcess();
            createWorkflowQueue();
        }

        if (qref) {
            WC.start();
        }

        QDBG_LOG("AbstractCoreSegmentWorkflowData::constructor() %s v%s (%d) qref: %y temp: %y qrefs: %d refs: %d", wf.name, wf.version, wf.workflowid, qref, temp, qrefs, refs);
    }

    destructor() {
        # don't delete any possible restart counter; let it go out of scope
        if (RC) {
            RC.dec();
        }
    }

    hash<auto> getLocalSummary() {
        return {
            "num_readers": numReaders(),
            "wtid": lockTID(),
            "refs": refs,
            "qrefs": qrefs,
            "trefs": trefs,
            "rw": rw,
            "rip": rip,
            "bcnt": bcnt,
            "bw": bw,
%ifdef QorusDebugInternals
            "rtid": rtid,
%endif
        };
    }

    string getSummary() {
        string str = sprintf("\nworkflow %s:%s (%d) lock: nr: %d wtid: %d refs: %d qrefs: %d", wf.name, wf.version,
            wf.workflowid, numReaders(), lockTID(), refs, qrefs);
%ifdef QorusDebugInternals
        str += sprintf(" rtid: %y", rtid);
%endif
        str += WC.getCacheSummary();

        return str;
    }

    # tell WorkflowQueue cache to stop caching workflow data in case it's in progress
    # and create the restart counter
    startStopWorkflow() {
        # issue #2467: we can never have two stop operations in progress at the same time
        # as it would lead to a deadlock
        QDBG_ASSERT(!RC);

        WC.stop();

        # create a counter to ensure that once a workflow is stopped, that the cache must be
        # completely deleted before another instance is restarted
%ifdef QorusDebugInternals
        rtid = gettid();
%endif
        RC = new Counter(1);
    }

    # only called in the SegmentManager write lock
    /** called only when the workflow's "pre-state" is a qorus-core internal workflow

        call order:
        1. startReset() - after this all cached workflow order data is flushed to the DB
        2. reset()
        3. endReset()
    */
    bool startReset(RWLock rwl) {
        QDBG_ASSERT(!wf.remote);
        while (True) {
            if (!bcnt && !rip)
                break;

            if (bcnt) {
                ++bw;
                bcond.wait(rwl);
                if (!self) {
                    wf.logFatal("AbstractCoreSegmentWorkflowData::startReset() deleted while waiting");
                    return False;
                }
                --bw;
                continue;
            }

            if (rip && !waitReset(rwl))
                return False;
        }

        rip = True;
        return True;
    }

    # called without the global segment manager write lock
    /** called only when the workflow's "pre-state" is a qorus-core internal workflow

        call order:
        1. startReset() - after this all cached workflow order data is flushed to the DB
        2. reset()
        3. endReset()
    */
    endReset(RWLock rwl) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (rw)
            rcond.broadcast();
        rip = False;
    }

    # wait until reset is complete
    # called in the global segment manager write lock
    bool waitReset(RWLock rwl) {
        while (rip) {
            ++rw;
            rcond.wait(rwl);
            if (!self) {
                wf.logFatal("AbstractCoreSegmentWorkflowData::derefWaitRestart() deleted while waiting");
                return False;
            }
            --rw;
        }
        return True;
    }

    # waits for qrefs = 1 && refs = 1 and dereferences both; returns when the object
    # can be deleted and the remote workflow can be restarted
    # only called for remote qwf processes
    derefWaitRestart(RWLock rwl) {
        QDBG_ASSERT(wf.remote);
        QDBG_LOG("AbstractCoreSegmentWorkflowData::derefWaitRestart() qrefs: %d refs: %d trefs: %d", qrefs, refs, trefs);

        while (True) {
            # wait for any blocks to be cleared
            if (bcnt) {
                ++bw;
                bcond.wait(rwl);
                --bw;
                continue;
            }

            # ensure that qrefs = 1 and refs = (trefs + 1) - i.e. that we have the last reference + queue reference
            if (qrefs != 1 || refs != (trefs + 1)) {
                ++restart_waiting;
                restart_cond.wait(rwl);
                --restart_waiting;
                continue;
            }

            break;
        }

        QDBG_LOG("AbstractCoreSegmentWorkflowData::derefWaitRestart() OK to restart: qrefs: %d -> %d refs: %d -> %d trefs: %d", qrefs, qrefs - 1, refs, refs - 1, trefs);
        --qrefs;
        --refs;

        signalRestart();
        stop();
    }

    # returns True if workflow data can be purged, False if not
    *bool deref(bool qref, bool temp) {
        QDBG_LOG("AbstractCoreSegmentWorkflowData::deref(qref: %y temp: %y) refs: %d -> %d qrefs %d -> %d trefs: %d -> %d", qref, temp, refs, refs - 1, qrefs, qref ? qrefs - 1 : qrefs, trefs, temp ? trefs - 1 : trefs);
        bool canpurge;
        if (qref) {
%ifdef QorusDebugInternals
            if (!qrefs)
                throw "QREFERENCE-ERROR", sprintf("AbstractCoreSegmentWorkflowData wf %s v%s (%d) refs: %d qrefs: %d", wf.name, wf.version, wf.workflowid, refs, qrefs);
%endif
            QDBG_ASSERT(qrefs > 0);
            if (!--qrefs) {
                WC.stop();

                canpurge = True;
            }
        }
        if (temp) {
            QDBG_LOG("AbstractCoreSegmentWorkflowData::deref(qref: %y temp: %y) trefs %d -> %d", qref, temp, trefs, trefs - 1);
            --trefs;
        }
        QDBG_ASSERT(refs > 0);
%ifdef QorusDebugInternals
        if (!refs) {
            throw "REFERENCE-ERROR", sprintf("AbstractCoreSegmentWorkflowData wf %s v%s (%d) refs: %d qrefs: %d", wf.name, wf.version, wf.workflowid, refs, qrefs);
        }
%endif

        # bug 1123: always purge the data cache if the last workflow reference reaches zero
        if (!--refs && !canpurge) {
            canpurge = True;
        }

        if (canpurge) {
            signalRestart();
        } else if (restart_waiting && qrefs == 1 && refs == (trefs + 1)) {
            restart_cond.signal();
        }

        if (refs && (trefs == refs)) {
            # stop the workflow queue
            WC.stop();
        }

        QDBG_LOG("AbstractCoreSegmentWorkflowData::deref(qref: %y temp: %y) workflow %s:%s (%d) refs: %y qrefs: %y trefs: %y returning %y", qref, temp, wf.name, wf.version, wf.workflowid, refs, qrefs, trefs, canpurge);
        return canpurge;
    }

    # only called in the SegmentManager write lock
    signalRestart() {
        # don't delete any possible restart counter; let it go out of scope
        if (RC) {
            RC.dec();
            remove RC;
%ifdef QorusDebugInternals
            remove rtid;
%endif
        }
    }

    # only called in the SegmentManager write lock
    private stop() {
        try {
            # stop the workflow queue (local workflows only; remote workflow queues stop when the process is stopped)
            WC.stop();
            # delete the workflow queue (also waits until all threads have stopped)
            delete WC;
            # stop the qwf process (if any)
            stopProcess();
        } catch (hash<ExceptionInfo> ex) {
            # ignore a qwf crash when resetting a workflow
            if (ex.err == "CLIENT-ABORTED" && Qorus.control.isWorkflowInReset(wf.workflowid)) {
                Qorus.logInfo("ignoring qwf process abort in reset: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            } else {
                rethrow;
            }
        }
    }

    # only called in the SegmentManager write lock
    bool blockRef(RWLock rwl) {
        if (waitReset(rwl)) {
            ++refs;
            ++bcnt;
            return True;
        }
        return False;
    }

    bool blockForDelete(RWLock rwl) {
        if (waitReset(rwl)) {
            ++bcnt;
            return True;
        }
        return False;
    }

    # only called in the SegmentManager write lock
    blockDeref() {
        if (!--bcnt && bw) {
            bcond.broadcast();
        }
    }

    # only called in the SegmentManager write lock
    int ref(bool qref, bool temp) {
        QDBG_LOG("AbstractCoreSegmentWorkflowData::ref(qref: %y temp: %y) refs: %d -> %d qrefs: %d -> %d", qref, temp, refs, refs + 1, qrefs, qref ? qrefs + 1 : qrefs);

        bool no_queue = (refs == trefs);
        if (temp) {
            #QDBG_LOG("AbstractCoreSegmentWorkflowData::ref(qref: %y temp: %y) trefs: %d -> %d", qref, temp, trefs, trefs + 1);
            ++trefs;
        }
        int rc = ++refs;
        if (no_queue && refs > trefs) {
            startProcess();
            createWorkflowQueue();
        }
        if (qref) {
            # DEBUG
            #QDBG_LOG("AbstractCoreSegmentWorkflowData::ref(qref: %y temp: %y) qrefs: %d -> %d", qref, temp, qrefs, qrefs + 1);
            if (++qrefs == 1) {
                QDBG_ASSERT(WC);
                WC.start();
            }
        }

        QDBG_LOG("AbstractCoreSegmentWorkflowData::ref(qref: %y temp: %y) workflow %s:%s (%d) refs: %y qrefs: %y trefs: %y returning %y", qref, temp, wf.name, wf.version, wf.workflowid, refs, qrefs, trefs, rc);
        return rc;
    }

    /** called only when the workflow's "pre-state" is a qorus-core internal workflow

        call order:
        1. startReset() - after this all cached workflow order data is flushed to the DB
        2. reset()
        3. endReset()
    */
    reset(Workflow wf) {
        QDBG_ASSERT(!self.wf.remote);
        if (refs > trefs) {
            stop();
        }
        self.wf = wf;
        if (refs > trefs) {
            startProcess();
            createWorkflowQueue();
        }
        if (qrefs) {
            QDBG_ASSERT(WC);
            WC.start();
        }
    }

    bool canDelete() {
        return !refs && !bcnt;
    }

    updateLogger(*hash<LoggerParams> params) {
        if (params) {
            hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                "name": wf.name,
                "id": wf.workflowid.toString(),
                "version": wf.version,
            };
            params = substituteLogFilename(params, LoggerController::getLoggerSubs("workflows", subs));
        }
        updateLoggerImpl(params);
    }

    abstract *hash<auto> getWFEntryDebugHash(string wfiid);

    private abstract startProcess();

    private abstract stopProcess();

    private abstract createWorkflowQueue();

    abstract rotateLogFiles();

    abstract updateLoggerImpl(*hash<LoggerParams> params);
}
