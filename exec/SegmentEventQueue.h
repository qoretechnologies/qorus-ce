/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
 SegmentEventQueue.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

#ifndef _QORUS_SEGMENT_EVENT_QUEUE
#define _QORUS_SEGMENT_EVENT_QUEUE

#include <deque>
#include <map>
#include <set>

// parent workflow info
struct ParentInfo {
    int64 wfiid;  // parent workflow_instanceid
    int   stepid; // parent stepid that child is bound to
    int   ind;    // parent step ind that child is bound to
    bool  subworkflow;  // is this a subworkflow child or not? (not == loosely coupled)

    DLLLOCAL ParentInfo(int64 n_wfiid = 0, int n_stepid = 0, int n_ind = 0) : wfiid(n_wfiid), stepid(n_stepid), ind(n_ind), subworkflow(false) {
    }

    DLLLOCAL void toString(QoreString &str) const {
        if (wfiid) {
            str.sprintf(", parent=(subworkflow: %s, wfiid: %lld", subworkflow ? "true" : "false", wfiid);
            if (stepid)
                str.sprintf(", stepid: %d, ind: %d", stepid, ind);
            str.concat(')');
        }
    }

    DLLLOCAL void doHash(QoreHashNode &h) const {
        if (wfiid) {
            QoreHashNode* parent_info = new QoreHashNode(autoTypeInfo);
            parent_info->setKeyValue("subworkflow", subworkflow, 0);
            parent_info->setKeyValue("parent_workflow_instanceid", wfiid, 0);
            if (stepid) {
                parent_info->setKeyValue("parent_stepid", stepid, 0);
                parent_info->setKeyValue("parent_ind", ind, 0);
            }
            h.setKeyValue("parent_info", parent_info, 0);
        }
    }
};

// helper function to concatenate a date to a QoreString from a UTC epoch offset
DLLLOCAL void concat_date(int64 mod, QoreString &str);

// for timed retry events
class RetryQueueEntry {
public:
    // workflow_instanceid
    int64 wfiid;

    // mod is the trigger time for retry events with fixed retry times
    // or it is the modified time for other retry events
    int64 mod;

    // workflow parent info
    ParentInfo parent_info;

    DLLLOCAL RetryQueueEntry(int64 n_wfiid, int64 n_mod, const ParentInfo &n_parent_info) : wfiid(n_wfiid), mod(n_mod), parent_info(n_parent_info) {
        assert(n_wfiid);
    }

    DLLLOCAL QoreHashNode* get_hash() const {
        QoreHashNode* rv = new QoreHashNode(autoTypeInfo);
        rv->setKeyValue("workflow_instanceid", wfiid, 0);
        parent_info.doHash(*rv);
        return rv;
    }

    DLLLOCAL void toString(QoreString &str, bool marked) const {
        str.concat("{mod=");
        concat_date(mod, str);
        str.sprintf(", wfiid: %lld, marked: %d", wfiid, marked);
        parent_info.toString(str);
        str.concat('}');
    }
};

// for backend queues (async, subworkflow, and "workflow synchronization" events)
class BackendQueueEntry {
protected:
    DLLLOCAL QoreHashNode* get_hash_intern() const {
        QoreHashNode* rv = new QoreHashNode(autoTypeInfo);
        parent_info.doHash(*rv);
        rv->setKeyValue("workflow_instanceid", wfiid, 0);
        return rv;
    }

    DLLLOCAL void to_string_intern(QoreString &str) const {
        str.sprintf("{wfiid: %lld, ", wfiid);
    }

public:
    // workflow_instanceid
    int64 wfiid;

    // order priority
    int prio;

    // workflow parent info
    ParentInfo parent_info;

    DLLLOCAL BackendQueueEntry(int64 n_wfiid, int n_prio, const ParentInfo &n_parent_info) : wfiid(n_wfiid), prio(n_prio), parent_info(n_parent_info) {
        assert(n_wfiid);
    }

    DLLLOCAL virtual ~BackendQueueEntry() {
    }

    DLLLOCAL virtual QoreHashNode* get_hash() = 0;

    DLLLOCAL virtual void toString(QoreString &str) const = 0;
};

// use a set to ensure that ind's can only be inserted once
typedef std::set<int> ind_list_t;

class SubWorkflowQueueEntry : public BackendQueueEntry {
protected:
public:
    // step ind list
    ind_list_t ind_list;

    // workflow status
    char status;

    // subworkflow_instanceid
    int64 swfiid;

    DLLLOCAL SubWorkflowQueueEntry(int64 n_wfiid, int n_ind, int n_prio, const ParentInfo &n_parent_info,
            char n_status, int64 n_swfiid) : BackendQueueEntry(n_wfiid, n_prio, n_parent_info), status(n_status),
            swfiid(n_swfiid) {
        assert(n_wfiid);
        ind_list.insert(n_ind);
    }

    DLLLOCAL virtual QoreHashNode* get_hash() {
        QoreHashNode* rv = BackendQueueEntry::get_hash_intern();

        QoreListNode* l = new QoreListNode(autoTypeInfo);
        for (ind_list_t::iterator i = ind_list.begin(), e = ind_list.end(); i != e; ++i)
            l->push(*i, nullptr);
        rv->setKeyValue("ind", l, 0);
        rv->setKeyValue("status", new QoreStringNode(status), 0);
        rv->setKeyValue("subworkflow_instanceid", swfiid, 0);
        return rv;
    }

    DLLLOCAL virtual void toString(QoreString &str) const {
        BackendQueueEntry::to_string_intern(str);
        str.concat("ind=[");
        for (ind_list_t::iterator i = ind_list.begin(), e = ind_list.end(); i != e; ++i)
            str.sprintf("%d, ", *i);
        str.terminate(str.strlen() - 2);
        str.concat("], ");
        str.sprintf("status: %c, swfiid: %d}", status, swfiid);
        parent_info.toString(str);
    }
};

struct async_entry {
    // queue key
    QoreStringNode* queuekey;

    // queue data
    QoreValue data;

    // step has been corrected?
    bool corrected;

    DLLLOCAL async_entry(QoreStringNode* n_queuekey, QoreValue n_data, bool n_corrected) : queuekey(n_queuekey),
            data(n_data), corrected(n_corrected) {
        assert(queuekey);
    }

    DLLLOCAL void get(QoreListNode &ql, QoreListNode &dl, QoreListNode &cl) {
        // append values to lists
        cl.push(corrected, nullptr);
        assert(queuekey);
        ql.push(queuekey, nullptr);
        queuekey = 0;
        dl.push(data, nullptr);
        data = QoreValue();
    }

    DLLLOCAL void toString(QoreString &str) const {
        str.sprintf("corrected: %d, queuekey: %s", corrected, queuekey->c_str());
        if (data) {
            str.concat(", data: ");
            QoreStringValueHelper tmp(data);
            str.concat(*tmp, nullptr);
        }
    }

    DLLLOCAL void deref() {
        if (queuekey)
            queuekey->deref(nullptr);
        data.discard(nullptr);
    }
};

// use a map to ensure ind's can only be inserted once
typedef std::map<int, async_entry> ind_map_t;

class AsyncQueueEntry : public BackendQueueEntry {
protected:
public:
    // step ind map
    ind_map_t ind_map;

    DLLLOCAL AsyncQueueEntry(int64 n_wfiid, int n_ind, int n_prio, bool n_corrected, const ParentInfo &n_parent_info,
            QoreStringNode* n_queuekey, QoreValue n_data = QoreValue())
            : BackendQueueEntry(n_wfiid, n_prio, n_parent_info) {
        assert(n_wfiid);
        ind_map.insert(std::make_pair(n_ind, async_entry(n_queuekey, n_data, n_corrected)));
    }

    DLLLOCAL virtual ~AsyncQueueEntry() {
        for (ind_map_t::iterator i = ind_map.begin(), e = ind_map.end(); i != e; ++i) {
            i->second.deref();
        }
    }

    DLLLOCAL virtual QoreHashNode* get_hash() {
        QoreHashNode* rv = BackendQueueEntry::get_hash_intern();

        QoreListNode* il = new QoreListNode(autoTypeInfo);
        QoreListNode* ql = new QoreListNode(autoTypeInfo);
        QoreListNode* dl = new QoreListNode(autoTypeInfo);
        QoreListNode* cl = new QoreListNode(autoTypeInfo);

        for (ind_map_t::iterator i = ind_map.begin(), e = ind_map.end(); i != e; ++i) {
            il->push(i->first, nullptr);
            i->second.get(*ql, *dl, *cl);
        }

        rv->setKeyValue("ind", il, 0);
        rv->setKeyValue("queuekey", ql, 0);
        rv->setKeyValue("data", dl, 0);
        rv->setKeyValue("corrected", cl, 0);

        return rv;
    }

    DLLLOCAL virtual void toString(QoreString &str) const {
        BackendQueueEntry::to_string_intern(str);
        for (ind_map_t::const_iterator i = ind_map.begin(), e = ind_map.end(); i != e; ++i) {
            str.sprintf("(ind: %d, ", i->first);
            i->second.toString(str);
            str.concat("), ");
        }
        str.terminate(str.strlen() - 2);
        parent_info.toString(str);
        str.concat('}');
    }
};

class EventQueueEntry : public BackendQueueEntry {
protected:
public:
    // step ind list
    ind_list_t ind_list;

    DLLLOCAL EventQueueEntry(int64 n_wfiid, int n_ind, int n_prio, const ParentInfo &n_parent_info)
            : BackendQueueEntry(n_wfiid, n_prio, n_parent_info) {
        ind_list.insert(n_ind);
        assert(n_wfiid);
    }

    DLLLOCAL virtual QoreHashNode* get_hash() {
        QoreHashNode* rv = BackendQueueEntry::get_hash_intern();
        QoreListNode* l = new QoreListNode(autoTypeInfo);
        for (ind_list_t::iterator i = ind_list.begin(), e = ind_list.end(); i != e; ++i)
            l->push(*i, nullptr);
        rv->setKeyValue("ind", l, 0);

        return rv;
    }

    DLLLOCAL virtual void toString(QoreString &str) const {
        BackendQueueEntry::to_string_intern(str);
        str.concat("ind=[");
        for (ind_list_t::iterator i = ind_list.begin(), e = ind_list.end(); i != e; ++i)
            str.sprintf("%d, ", *i);
        str.terminate(str.strlen() - 2);
        str.concat(']');
        parent_info.toString(str);
        str.concat('}');
    }
};

// backend queue
typedef std::multimap<int64, BackendQueueEntry *> backend_queue_t;
// map from priorities to queues
typedef std::map<int, backend_queue_t> backend_map_t;

class BackendQueue : public backend_map_t {
protected:
    QoreCondition cond;
    int waiting;

public:
    DLLLOCAL BackendQueue() : waiting(0) {
    }

    DLLLOCAL virtual ~BackendQueue() {
        for (backend_map_t::iterator bi = begin(), be = end(); bi != be; ++bi)
            for (backend_queue_t::iterator i = bi->second.begin(), e = bi->second.end(); i != e; ++i)
                delete i->second;
    }

    DLLLOCAL void wakeup() {
        if (waiting)
        cond.broadcast();
    }

    DLLLOCAL void signal() {
        if (waiting)
        cond.signal();
    }

    DLLLOCAL void wait(QoreThreadLock &mutex) {
        ++waiting;
        cond.wait(mutex);
        --waiting;
    }

    DLLLOCAL virtual void merge(BackendQueue *bq) = 0;
};

// map from wfiid to backend queue iterator to ensure that a workflow is only inserted once
typedef std::map<int64, backend_queue_t::iterator> wfmap_t;

// for workflow events
struct EventQueue : public BackendQueue {
protected:
public:
    // wfiid to backend queue interator map
    wfmap_t wfmap;

    DLLLOCAL virtual ~EventQueue() {
    }

    DLLLOCAL void add_event(int64 mod, int64 wfiid, int ind, int prio, const ParentInfo &pi);

    DLLLOCAL virtual void merge(BackendQueue *bq);
};

struct AsyncQueue : public BackendQueue {
public:
    // wfiid to backend queue interator map
    wfmap_t wfmap;

    DLLLOCAL virtual ~AsyncQueue() {
    }

    DLLLOCAL void add_async_event(int64 mod, int64 wfiid, int ind, int prio, bool corrected, const ParentInfo &pi, QoreStringNode* n_queuekey, QoreValue n_data = QoreValue());

    DLLLOCAL virtual void merge(BackendQueue *bq);
};

// map from 'ind's to backend queue iterator
//typedef std::map<int, backend_queue_t::iterator> indmap_t;
// map from workflow instance IDs to indmaps
//typedef std::map<int64, indmap_t> wmap_t;

struct SubWorkflowQueue : public BackendQueue {
public:
    // map for ERROR events
    wfmap_t c_wfmap;
    // map for COMPLETE events
    wfmap_t e_wfmap;

    DLLLOCAL virtual ~SubWorkflowQueue() {
    }

    DLLLOCAL void add_subworkflow_event(int64 mod, int64 wfiid, int ind, int prio, const ParentInfo &pi, char status, int64 swfiid);

    DLLLOCAL virtual void merge(BackendQueue *bq);
};

struct PrimaryEvent {
    int64 wfiid;             // workflow_instanceid
    int prio;                // order priority
    ParentInfo parent_info;  // parent info

    DLLLOCAL PrimaryEvent(int64 n_wfiid, int n_prio, const ParentInfo &pi) : wfiid(n_wfiid), prio(n_prio), parent_info(pi) {
        assert(n_wfiid);
    }

    DLLLOCAL QoreHashNode* get_hash() const {
        QoreHashNode* rv = new QoreHashNode(autoTypeInfo);
        rv->setKeyValue("workflow_instanceid", wfiid, 0);
        //rv->setKeyValue("priority", prio, 0);
        parent_info.doHash(*rv);
        return rv;
    }
};

// primary event queue
typedef std::deque<PrimaryEvent> primary_queue_t;
// primary priority to event queue map
typedef std::map<int, primary_queue_t> primary_map_t;

// retry and async retry queues, mapped/sorted by trigger time
typedef std::multimap<int64, RetryQueueEntry *> retry_map_t;
// backend queue map, mapped by segment ID
typedef std::map<int, BackendQueue *> backend_queue_map_t;
// workflow lookup map to primary queue
typedef std::map<int64, primary_queue_t::iterator> pmap_t;

// primary scheduled queue, key = trigger time
typedef std::multimap<int64, PrimaryEvent> scheduled_queue_t;
// workflow lookup map to primary scheduled queue
typedef std::map<int64, scheduled_queue_t::iterator> psmap_t;

class PrimaryQueue {
public:
    DLLLOCAL PrimaryQueue() {
    }

    DLLLOCAL ~PrimaryQueue() {
    }

    DLLLOCAL size_t size() const {
        return pq.size();
    }

    DLLLOCAL bool empty() const {
        return pq.empty();
    }

    DLLLOCAL size_t scheduledSize() const {
        return psq.size();
    }

    DLLLOCAL bool scheduledEmpty() const {
        return psq.empty();
    }

    DLLLOCAL void del() {
        pq.clear();
        psq.clear();
        pmap.clear();
        psmap.clear();
    }

    DLLLOCAL void add(int64 wfiid, int priority, const ParentInfo &pi, const DateTimeNode* scheduled = 0, int64 now = q_epoch(), bool signal = true) {
        PrimaryEvent event(wfiid, priority, pi);
        int64 trigger = 0;

        // add a scheduled event to the scheduled queue
        if (scheduled && (trigger = scheduled->getEpochSecondsUTC()) > now) {
            if (addToScheduled(trigger, event) && signal && waiting)
                cond.broadcast();
        }
        else {
            // insert in primary queue
            addToPrimary(event);
            // signal if there are waiting threads
            if (signal && waiting)
                cond.signal();
        }
    }

    DLLLOCAL void wakeup() {
        if (waiting)
        cond.broadcast();
    }

    DLLLOCAL void wait(int64 now, QoreThreadLock &mutex) {
        assert(mutex.trylock());
        assert(pq.empty());

        ++waiting;

        // if there is a scheduled event, then wait for its trigger time
        if (!psq.empty()) {
            assert((psq.begin()->first - now) > 0);
            cond.wait(mutex, (psq.begin()->first - now) * 1000);
        }
        else
            cond.wait(mutex);

        --waiting;
    }

    // returns true if a primary event is ready, false if not
    DLLLOCAL bool checkEvent(int64 now) {
        // first move all activated entries in the scheduled queue to the primary queue
        activate(now);

        return !pq.empty();
    }

    DLLLOCAL QoreHashNode* getEvent() {
        assert(!pq.empty());

        // get the queue for the lowest priority
        primary_map_t::iterator pi = pq.begin();
        primary_queue_t &q = pi->second;

        // get the first event from the queue
        PrimaryEvent &event = q[0];

        QoreHashNode* rv = event.get_hash();

        // remove from lookup queue
        pmap.erase(event.wfiid);

        // remove from queue
        q.pop_front();

        // delete queue for that priority if no more entries are present
        if (q.empty())
            pq.erase(pi);

        return rv;
    }

    DLLLOCAL void summary(QoreStringNode& str) const {
        str.sprintf("waiting: %d", waiting);
        for (primary_map_t::const_iterator pi = pq.begin(), e = pq.end(); pi != e; ++pi) {
            str.sprintf(", prio %d -> len: %d", pi->first, pi->second.size());
        }
    }

    DLLLOCAL void toString(QoreString &str) const {
        str.sprintf("primary len: (waiting: %d) %d: [", waiting, pq.size());
        if (!pq.empty()) {
            for (primary_map_t::const_iterator pi = pq.begin(), e = pq.end(); pi != e; ++pi) {
                str.sprintf("prio %d -> len: %d: [", pi->first, pi->second.size());
                for (primary_queue_t::const_iterator i = pi->second.begin(), e = pi->second.end(); i != e; ++i) {
                str.sprintf("wfiid: %lld", (*i).wfiid);
                (*i).parent_info.toString(str);
                str.concat(", ");
                }
                str.concat("], ");
            }
            str.terminate(str.strlen() - 2);
        }

        str.sprintf("], scheduled len: %d: [", psq.size());
        if (!psq.empty()) {
            for (scheduled_queue_t::const_iterator i = psq.begin(), e = psq.end(); i != e; ++i) {
                str.concat("sched: ");
                concat_date(i->first, str);
                str.sprintf(", wfiid: %lld prio: %d", i->second.wfiid, i->second.prio);
                i->second.parent_info.toString(str);
                str.concat(", ");
            }
            str.terminate(str.strlen() - 2);
        }
    }

    // returns true if the workflow data was found and rescheduled, false if not
    DLLLOCAL bool resched(int64 wfiid, const DateTimeNode* scheduled) {
        bool rc = reschedIntern(wfiid, scheduled);
        // if we have waiting threads, then wake them up to check the changes in the queues
        if (rc)
            wakeup();
        return rc;
    }

    // returns true if the workflow data was found and reprioritized, false if not
    DLLLOCAL bool reprioritize(int64 wfiid, int prio) {
        // check if in scheduled queue
        psmap_t::iterator smi = psmap.find(wfiid);
        if (smi != psmap.end()) {
            smi->second->second.prio = prio;
            return true;
        }

        // check if in primary queue
        pmap_t::iterator pmi = pmap.find(wfiid);
        if (pmi == pmap.end())
            return false;

        ParentInfo pi = (*pmi->second).parent_info;
        removeIntern(pmi);

        // add to appropriate queue
        add(wfiid, prio, pi);
        return true;
    }

    // removes the order from the queue
    DLLLOCAL bool removeWorkflowOrder(int64 wfiid) {
        // check if in scheduled queue
        psmap_t::iterator smi = psmap.find(wfiid);
        if (smi != psmap.end()) {
            psmap.erase(smi);
            return true;
        }

        // check if in primary queue
        pmap_t::iterator pmi = pmap.find(wfiid);
        if (pmi == pmap.end())
            return false;

        removeIntern(pmi);
        return true;
    }

private:
    // condition variable for threads waiting on events in this queue
    QoreCondition cond;

    // flag for waiting thread
    int waiting = 0;

    // primary event queue
    primary_map_t pq;

    // workflow lookup map to primary queue
    pmap_t pmap;

    // queue of workflows with scheduled activation times
    scheduled_queue_t psq;

    // workflow lookup map to primary scheduled queue
    psmap_t psmap;

    // move all activated entries in the scheduled queue to the primary queue
    DLLLOCAL void activate(int64 now) {
        while (true) {
            scheduled_queue_t::iterator i = psq.begin();
            if (i == psq.end() || i->first > now)
                break;

            // erase from scheduled queue lookup map
            psmap.erase(i->second.wfiid);

            // insert in primary queue
            addToPrimary(i->second);

            // erase from scheduled queue
            psq.erase(i);
        }
    }

    // returns true if it's the first entry in the list and all primary queues are empty, false if not
    DLLLOCAL bool addToScheduled(int64 trigger, const PrimaryEvent &event) {
        // the workflow can already be in the scheduled queue lookup map if there
        // is a race condition with order data submissions and workflow starting

        // bug 617: a race condition with workflow queue initialization and order creation can cause a runtime server crash
        // here we search in a way that if the search fails, we have an insert hint
        psmap_t::iterator pi = psmap.lower_bound(event.wfiid);
        if (pi == psmap.end() || pi->first != event.wfiid) {
            scheduled_queue_t::iterator i = psq.insert(scheduled_queue_t::value_type(trigger, event));
            // make sure the workflow is not already in the primary queue lookup map
            assert(pmap.find(event.wfiid) == pmap.end());
            // add to lookup map for scheduled queue
            psmap.insert(pi, psmap_t::value_type(event.wfiid, i));

            return pq.empty() && i == psq.begin();
        }

        // nothing was changed, return false
        return false;
    }

    // adds an element to the primary queue
    DLLLOCAL void addToPrimary(const PrimaryEvent &event) {
        // the workflow can already be in the primary queue lookup map if there
        // is a race condition with order data submissions and workflow starting

        // bug 617: a race condition with workflow queue initialization and order creation can cause a runtime server crash
        // here we search in a way that if the search fails, we have an insert hint
        pmap_t::iterator i = pmap.lower_bound(event.wfiid);
        if (i == pmap.end() || i->first != event.wfiid) {
            // get queue from priority
            primary_queue_t &q = pq[event.prio];
            // insert in queue
            primary_queue_t::iterator pi = q.insert(q.end(), event);
            // ensure workflow is not already in the scheduled lookup map
            assert(psmap.find(event.wfiid) == psmap.end());
            // insert in primary queue lookup map
            pmap.insert(i, pmap_t::value_type(event.wfiid, pi));
        }
    }

    // returns true if the workflow data was found and rescheduled, false if not
    DLLLOCAL bool reschedIntern(int64 wfiid, const DateTimeNode* scheduled) {
        // check if in scheduled queue
        psmap_t::iterator smi = psmap.find(wfiid);
        if (smi != psmap.end()) {
            scheduled_queue_t::iterator qi = smi->second;

            // get event info
            int prio = qi->second.prio;
            ParentInfo pi = qi->second.parent_info;

            // remove from scheduled queue map
            psmap.erase(smi);
            // remove from scheduled queue
            psq.erase(qi);

            // add to appropriate queue
            add(wfiid, prio, pi, scheduled);
            return true;
        }

        // check if in primary queue
        pmap_t::iterator pmi = pmap.find(wfiid);
        if (pmi != pmap.end()) {
            primary_queue_t::iterator qi = pmi->second;

            // get event info
            int prio = (*qi).prio;
            ParentInfo pi = (*qi).parent_info;

            // remove from primary queue map
            pmap.erase(pmi);
            // remove from primary queue
            primary_queue_t &q = pq[prio];
            q.erase(qi);

            // delete queue for that priority if no more entries are present
            if (q.empty())
                pq.erase(prio);

            // add to appropriate queue
            add(wfiid, prio, pi, scheduled);
            return true;
        }

        return false;
    }

    // remove event info from internal queues
    DLLLOCAL void removeIntern(pmap_t::iterator pmi) {
        primary_queue_t::iterator qi = pmi->second;

        // get event info
        int old_prio = (*qi).prio;

        // remove from primary queue
        pmap.erase(pmi);

        primary_queue_t &q = pq[old_prio];
        q.erase(qi);

        // delete queue for that priority if no more entries are present
        if (q.empty())
            pq.erase(old_prio);
    }
};

typedef std::set<RetryQueueEntry *> marker_set_t;

// retry workflow lookup map
typedef std::map<int64, retry_map_t::iterator> rwmap_t;

class RetryQueue : public retry_map_t {
public:
    // "marker" set to mark entries being "slept on"
    marker_set_t marker_set;

    // lookup map for quick deletion of all entries that belong to a particular workflow instance
    rwmap_t rwmap;

    DLLLOCAL ~RetryQueue() {
        del();
    }
    DLLLOCAL void del() {
        for (retry_map_t::iterator i = begin(), e = end(); i != e; ++i)
        delete i->second;
        clear();
    }

    // 0 = OK, -1 = not queued
    DLLLOCAL int add(int64 wfiid, int64 mod, const ParentInfo &pi);

    DLLLOCAL void remove_workflow_instance(int64 wfiid);
    DLLLOCAL void merge(RetryQueue &rq);
    DLLLOCAL int toString(QoreString &str);
};

// workflow instance reference map
typedef std::map<int64, int> workflow_seg_map_t;

class SegmentEventQueue : public AbstractPrivateData {
public:
    DLLLOCAL SegmentEventQueue(QoreObject* n_workflow_params, QoreObject* n_qorus_options);
    DLLLOCAL virtual ~SegmentEventQueue();

    using AbstractPrivateData::deref;
    DLLLOCAL virtual void deref(ExceptionSink *xsink);

    DLLLOCAL void destructor();
    DLLLOCAL void terminate_connection(int id);
    DLLLOCAL void terminate_retry_connection(int id);

    DLLLOCAL void add_subworkflow_segment(int segid);
    DLLLOCAL void add_async_segment(int segid);
    DLLLOCAL void add_event_segment(int segid);

    DLLLOCAL void init_primary_queue(const QoreListNode* l);
    DLLLOCAL void init_retry_queue(const QoreListNode* l);
    DLLLOCAL void init_async_retry_queue(const QoreListNode* l);

    DLLLOCAL void init_subworkflow_queue(int segid, const QoreListNode* l);
    DLLLOCAL void init_async_queue(int segid, const QoreListNode* l);
    DLLLOCAL void init_event_queue(int segid, const QoreListNode* l);

    DLLLOCAL void requeue_retries();
    DLLLOCAL void cleanup_connection(int id);
    DLLLOCAL void remove_workflow_instance(int64 wfiid);

    DLLLOCAL void queue_async_event(int segid, int64 wfiid, int ind, int prio, bool corrected,
            const QoreStringNode* queuekey, const QoreValue data, const QoreHashNode* parent_info);
    DLLLOCAL void queue_workflow_event(int segid, int64 wfiid, int ind, int prio, const QoreHashNode* parent_info);
    DLLLOCAL void queue_subworkflow_event(int segid, int64 wfiid, int ind, int prio, char status, int64 swfiid,
            const QoreHashNode* parent_info);

    DLLLOCAL void queue_primary_event(int64 wfiid, int priority, const QoreHashNode* parent_info,
            const DateTimeNode* scheduled);
    DLLLOCAL bool resched_primary_event(int64 wfiid, const DateTimeNode* scheduled);
    DLLLOCAL bool reprioritize(int64 wfiid, int prio);

    DLLLOCAL void removeWorkflowOrder(int64 wfiid, int64 prio);

    DLLLOCAL void queue_retry_event(int64 wfiid, const DateTimeNode &d, const QoreHashNode* parent_info);
    DLLLOCAL void queue_retry_event_fixed(int64 wfiid, const DateTimeNode &d, const QoreHashNode* parent_info);
    DLLLOCAL void queue_async_retry_event(int64 wfiid, const DateTimeNode &d, const QoreHashNode* parent_info);

    DLLLOCAL void merge_all(SegmentEventQueue *seq);
    DLLLOCAL bool grab_segment_inc(int64 wfiid);

    DLLLOCAL QoreHashNode* get_primary_event(int conn_id);
    DLLLOCAL QoreHashNode* get_subworkflow_event(int conn_id, int segid, SegmentEventQueue &beq);
    DLLLOCAL QoreHashNode* get_async_event(int conn_id, int segid, SegmentEventQueue &beq);
    DLLLOCAL QoreHashNode* get_workflow_event(int conn_id, int segid, SegmentEventQueue &beq);

    DLLLOCAL QoreHashNode* get_retry_event(int conn_id, ExceptionSink *xsink);
    DLLLOCAL void release_segment(int64 wfiid);
    DLLLOCAL void release_retry_segment(int64 wfiid);

    DLLLOCAL QoreStringNode* toString();
    DLLLOCAL QoreStringNode* getSummary();

private:
    mutable QoreThreadLock mutex;
    bool term;				        // terminate flag

    PrimaryQueue primary_queue;

    QoreCondition retry_cond;			// retry and async retry cond
    RetryQueue retry_queue, async_retry_queue;   // retry and async retry queues
    RetryQueue fixed_retry_queue;                // retry and async retries with fixed trigger times
    int retry_waiting;

    backend_queue_map_t backend_queue_map;	// map of segment IDs to backend queues
    int_set_t conn_set, retry_conn_set;          // connection ID termination sets

    workflow_seg_map_t workflow_seg_map;		// flow and segment instance markers
    QoreObject* workflow_params,                 // per-workflow type overrides (retry and async delays)
        *qorus_options;                           // pointer to system option object

    // broadcasts on all condition variables with waiting threads
    DLLLOCAL void broadcast();
    DLLLOCAL void backend_broadcast();
    DLLLOCAL void requeue_retries_intern();

    DLLLOCAL int64 getOptionBigInt(const char* opt) const;

    // returns -1 for error, 0 for OK
    //DLLLOCAL int check_active_and_grab(int64 wfiid, int ind);

    DLLLOCAL void get_retry_values(int64 &retry, int64 &async_retry, int conn_id) const;
    DLLLOCAL QoreHashNode* get_event(retry_map_t::iterator i, RetryQueue &queue, int64 &wfiid);
    DLLLOCAL void mark_wait_retry(retry_map_t::iterator i, RetryQueue &queue, int64 diff);

    DLLLOCAL void init_retry_intern(const QoreListNode &l, RetryQueue &rq);
    DLLLOCAL BackendQueueEntry *get_backend_event_unlocked(int conn_id, int segid, SegmentEventQueue &beq,
            BackendQueue &be);

    DLLLOCAL static void get_event_info(const QoreHashNode* h, int64 &wfiid, ParentInfo &pi);
    DLLLOCAL static void get_backend_event_info(const QoreHashNode* h, int64 &wfiid, ParentInfo &pi, int &ind,
            int &prio, int64 &mod);
};

#endif
