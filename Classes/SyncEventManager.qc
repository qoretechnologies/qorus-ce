# -*- mode: qore; indent-tabs-mode: nil -*-
#
# Qorus Integration Engine

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

public namespace OMQ;

class OMQ::SyncEventManager inherits private Mutex {
    private {
        # master event cache event_type_id -> event key cache
        hash cache;

        # TID of cache thread for delayed workflow instance detaches
        int cacheTid;

        # exit counter for cache thread
        Counter cCount(1);
    }

    public {
        # cache timeout object
        TimedSyncCache TSC(Qorus.options, "sync-delay");
    }

    constructor() {
        on_error cCount.dec();
        cacheTid = background cacheThread();
    }

    shutdown() {
        # send termination message to cache thread
        TSC.terminate();
        # wait for cache thread to terminate
        cCount.waitForZero();
    }

    syncDelayUpdated() {
        TSC.requeue();
    }

    private cacheThread() {
        on_exit cCount.dec();

        while (True) {
            *hash h = TSC.getEvent();
            if (!h)
                break;

            #printf("timed sync cache event: %y\n", h);

            lock();
            on_exit unlock();
            if (cache{h.eventtype} && cache{h.eventtype}.purge(h.eventkey))
                remove cache{h.eventtype};
        }
    }

    private checkEvent(int event_typeid) {
        lock();
        on_exit unlock();

        if (!exists cache{event_typeid})
            cache{event_typeid} = new SyncEventType(event_typeid);
    }

    bool bindEvent(softint event_typeid, string event, softint wfiid, softint stepid, softint ind) {
        checkEvent(event_typeid);

        bool rc = cache{event_typeid}.bind(event, wfiid, stepid, ind);
        if (rc) {
            string str = Qorus.qmm.lookupEvent(event_typeid).name;
            qlog(LoggerLevel::INFO, "event %s of type %s(%d) has already posted", event, str, event_typeid);
        }
        return rc;
    }

    bindEventUnposted(softint event_typeid, string event, softint wfiid, softint stepid, softint ind) {
        checkEvent(event_typeid);

        cache{event_typeid}.bind(event, wfiid, stepid, ind, True);
    }

    #! returns step instance information for affected events in the given workflows
    /** @return a hash keyed by workflows, values are lists of step row hashes with the following keys:
        - \c workflowid
        - \c parent_workflow_instanceid
        - \c subworkflow
        - \c priority
        - \c workflow_instanceid
        - \c stepid
        - \c ind
    */
    *hash<string, list<hash<auto>>> post(int eventid, string event, *reference<bool> wasposted) {
        {
            lock();
            on_exit unlock();

            if (!exists cache{eventid})
                cache{eventid} = new SyncEventType(eventid);
        }

        return cache{eventid}.post(event, \wasposted);
    }
}

class OMQ::SyncEventType inherits RWLock {
    private {
        int id;
        string name;

        hash cache;
    }

    public {}

    constructor(int n_id) {
        id = n_id;
        name = Qorus.qmm.lookupEvent(id).name;
    }

    # returns True if the last key has been deleted
    bool purge(string event) {
        writeLock();
        on_exit writeUnlock();

        if (cache{event})
            remove cache{event};

        return cache.empty();
    }

    bool bind(string event, softint wfiid, softint stepid, softint ind, bool only_unposted = False) {
        {
            readLock();
            on_exit readUnlock();

            # update TTL in cache
            Qorus.SEM.TSC.set(event, id);

            # if event has already posted, return True
            if (cache{event}) {
                if (only_unposted)
                    throw "ALREADY-POSTED", sprintf("bind_event_unposted() called on already bound event %y (id %d) with key %y", name, id, event);
                return True;
            }

            # event exists but has not yet been posted; create step instance event row and return False
            if (exists cache{event}) {
                QorusRestartableTransaction trans();
                while (True) {
                    try {
                        on_error omqp.rollback();
                        on_success omqp.commit();

                        insertStepInstanceEvent(event, wfiid, stepid, ind);
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

                return False;
            }
        }

        writeLock();
        on_exit writeUnlock();

        # update TTL in cache
        Qorus.SEM.TSC.set(event, id);

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # recheck if event exists
                if (!exists cache{event}) {
                    *bool es = sqlif.getWorkflowEventStatus(id, event);
                    #log(LoggerLevel::DEBUG, "getWorkflowEventStatus(%n, %n) = %n", id, event, es);

                    cache{event} = es;
                    if (es)
                        return True;
                    if (!exists es) {
                        # note: it's possible that this message could be logged multiple times in case of a transaction restart'
                        qlog(LoggerLevel::INFO, "creating workflow event %y of type %s(%d)", event, name, id);
                        sqlif.createWorkflowEvent(id, event, False);
                    }

                    # create step instance event entry
                    insertStepInstanceEvent(event, wfiid, stepid, ind);

                    return False;
                }
                if (cache{event})
                    return True;
                # create step instance event entry
                insertStepInstanceEvent(event, wfiid, stepid, ind);

                QDBG_TEST_CLUSTER_FAILOVER();
                return False;
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
        }
    }

    private insertStepInstanceEvent(string event, softint wfiid, softint stepid, softint ind) {
        qlog(LoggerLevel::INFO, "binding to unposted event %y of type %s(%d)", event, name, id);
        sqlif.insertStepInstanceEvent(wfiid, stepid, ind, id, event);
    }


    #! returns a hash keyed by workflowid, values are step row hashes
    /** @return a hash keyed by workflows, values are lists of step row hashes with the following keys:
        - \c workflowid
        - \c parent_workflow_instanceid
        - \c subworkflow
        - \c priority
        - \c workflow_instanceid
        - \c stepid
        - \c ind
    */
    *hash<string, list<hash<auto>>> post(string event, *reference<bool> wasposted) {
        postIntern(event, \wasposted);
        if (wasposted) {
            return;
        }

        *hash<string, list<hash<auto>>> rv;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                # we can just release the lock because the query is read-only
                on_exit omqp.rollback();

                rv = sqlif.getStepInstanceEventList(id, event);
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
        QDBG_LOG("workflow synchronization event %d:%s workflows: %y", id, event, (map $1.toInt(), keys rv));
        return rv;
    }

    private postIntern(string event, *reference<bool> wasposted) {
        # update TTL in cache
        Qorus.SEM.TSC.set(event, id);

        writeLock();
        on_exit writeUnlock();

        # if the event has already been posted, then return
        if (cache{event}) {
            wasposted = True;
            return;
        }

        on_exit
            cache{event} = True;

        # check if event exists
        bool post;
        if (!exists cache{event}) {
            *bool es;

            QorusRestartableTransaction trans();
            while (True) {
                try {
                    # we can just release the lock because the query is read-only
                    on_exit omqp.rollback();

                    es = sqlif.getWorkflowEventStatus(id, event);
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

            if (es) {
                wasposted = True;
                return;
            }

            if (!exists es) {
                while (True) {
                    try {
                        on_error omqp.rollback();
                        on_success omqp.commit();

                        sqlif.createWorkflowEvent(id, event, True);
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
                qlog(LoggerLevel::INFO, "creating posted workflow event %y of type %s(%d)", event, name, id);
            } else
                post = True;
        } else
            post = True;

        if (post) {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    sqlif.postWorkflowEvent(id, event);
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
            qlog(LoggerLevel::INFO, "posting workflow event %y of type %s(%d)", event, name, id);
        }

        wasposted = False;
    }
}
