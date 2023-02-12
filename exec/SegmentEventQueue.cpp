/* -*- indent-tabs-mode: nil -*- */
/*
 SegmentEventQueue.cpp
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#include <qore/Qore.h>
#include "SegmentEventQueue.h"

#include <memory>

void concat_date(int64 mod, QoreString &str) {
   DateTime d;
   d.setDate(currentTZ(), mod, 0);
   d.format(str, "YYYY-MM-DD HH:mm:SS");
}

SegmentEventQueue::SegmentEventQueue(QoreObject* n_workflow_params, QoreObject* n_qorus_options)
        : term(false),
            retry_waiting(0), workflow_params(n_workflow_params),
            qorus_options(n_qorus_options) {
    workflow_params->ref();
    qorus_options->ref();
}

SegmentEventQueue::~SegmentEventQueue() {
   // delete all backend queues
   for (backend_queue_map_t::iterator i = backend_queue_map.begin(), e = backend_queue_map.end(); i != e; ++i)
      delete i->second;
}

void SegmentEventQueue::deref(ExceptionSink *xsink) {
    if (ROdereference()) {
        workflow_params->deref(xsink);
        qorus_options->deref(xsink);
        delete this;
    }
}

// must be called in the lock
void SegmentEventQueue::broadcast() {
    assert(mutex.trylock());

    // signal primary queue
    primary_queue.wakeup();

    if (retry_waiting)
        retry_cond.broadcast();

    // signal all backend queues
    for (backend_queue_map_t::iterator i = backend_queue_map.begin(), e = backend_queue_map.end(); i != e; ++i)
        i->second->wakeup();
}

void SegmentEventQueue::destructor() {
    AutoLocker al(&mutex);
    term = true;

    broadcast();
}

void SegmentEventQueue::terminate_connection(int id) {
    AutoLocker al(&mutex);
    conn_set.insert(id);
    broadcast();
}

void SegmentEventQueue::terminate_retry_connection(int id) {
    AutoLocker al(&mutex);
    retry_conn_set.insert(id);
    if (retry_waiting)
        retry_cond.broadcast();
}

void SegmentEventQueue::add_subworkflow_segment(int segid) {
    // no locking needed during single-threaded initialization
    //AutoLocker al(&mutex);

    assert(!term);
    assert(backend_queue_map.find(segid) == backend_queue_map.end());

    backend_queue_map[segid] = new SubWorkflowQueue;
}

void SegmentEventQueue::add_async_segment(int segid) {
    // no locking needed during single-threaded initialization
    //AutoLocker al(&mutex);

    assert(!term);
    assert(backend_queue_map.find(segid) == backend_queue_map.end());

    backend_queue_map[segid] = new AsyncQueue;
}

void SegmentEventQueue::add_event_segment(int segid) {
    // no locking needed during single-threaded initialization
    //AutoLocker al(&mutex);

    assert(!term);
    assert(backend_queue_map.find(segid) == backend_queue_map.end());

    backend_queue_map[segid] = new EventQueue;
}

static void get_parent_info(const QoreHashNode* h, ParentInfo& pi) {
    bool found;
    int64 val = h->getKeyAsBigInt("parent_workflow_instanceid", found);
    if (!val)
        return;

    pi.wfiid = val;

    bool swf = h->getKeyAsBool("subworkflow", found);
    // issue 1772: subworkflow can be missing; when NULL it is deleted from the internal responses in SQLInterface sometimes
    pi.subworkflow = swf;

    val = h->getKeyAsBigInt("parent_stepid", found);
    if (!val)
        return;

    pi.stepid = (int)val;

    val = h->getKeyAsBigInt("parent_ind", found);
    if (val)
        pi.ind = (int)val;
}

void SegmentEventQueue::get_event_info(const QoreHashNode* h, int64& wfiid, ParentInfo& pi) {
    bool found;
    wfiid = h->getKeyAsBigInt("workflow_instanceid", found);
    assert(wfiid);

    // get parent info
    QoreValue n = h->getKeyValue("parent_info");
    assert(!n || n.getType() == NT_HASH);
    if (n)
        get_parent_info(n.get<const QoreHashNode>(), pi);
}

void SegmentEventQueue::init_primary_queue(const QoreListNode* l) {
    // get current time (epoch offset in seconds)
    int64 now = q_epoch();

    AutoLocker al(&mutex);

    ConstListIterator li(l);
    while (li.next()) {
        QoreValue n = li.getValue();
        assert(n.getType() == NT_HASH);
        const QoreHashNode* h = n.get<const QoreHashNode>();

        int64 wfiid;
        ParentInfo pi;
        get_event_info(h, wfiid, pi);

        // get scheduled date/time
        n = h->getKeyValue("scheduled");

        const DateTimeNode* d = (n && !n.isNull()) ? n.get<const DateTimeNode>() : nullptr;

        n = h->getKeyValue("priority");
        assert(n);
        int priority = n.getAsBigInt();

        // only queue for later execution if the scheduled date has not yet arrived
        primary_queue.add(wfiid, priority, pi, d, now, false);
    }

    // notify waiting threads if any
    primary_queue.wakeup();
}

void SegmentEventQueue::init_retry_queue(const QoreListNode* l) {
    init_retry_intern(*l, retry_queue);
}

void SegmentEventQueue::init_async_retry_queue(const QoreListNode* l) {
    init_retry_intern(*l, async_retry_queue);
}

void SegmentEventQueue::init_retry_intern(const QoreListNode& l, RetryQueue& rq) {
    if (l.empty())
        return;

    AutoLocker al(&mutex);

    ConstListIterator li(l);
    while (li.next()) {
        QoreValue n = li.getValue();
        assert(n.getType() == NT_HASH);
        const QoreHashNode* h = n.get<const QoreHashNode>();

        int64 wfiid;
        ParentInfo pi;
        get_event_info(h, wfiid, pi);

        // if there is a fixed "trigger" time, then add to the fixed retry queue
        QoreValue t = h->getKeyValue("retry_trigger");
        if (t.getType() == NT_DATE) {
            fixed_retry_queue.add(wfiid, t.get<const DateTimeNode>()->getEpochSecondsUTC(), pi);
        }
        else {
            t = h->getKeyValue("modified");
            assert(t.getType() == NT_DATE);
            int64 mod = t.get<const DateTimeNode>()->getEpochSecondsUTC();
            rq.add(wfiid, mod, pi);
        }
    }
    printd(5, "SegmentEventQueue::init_retry_intern() this=%p, size=%lu (%sretry)\n", this, retry_queue.size(),
        &rq == &retry_queue ? "" : "async ");

    // notify waiting threads that there is data available
    requeue_retries_intern();
}

void SegmentEventQueue::get_backend_event_info(const QoreHashNode* h, int64& wfiid, ParentInfo& pi, int& ind,
        int& prio, int64& mod) {
    get_event_info(h, wfiid, pi);

    bool found;
    ind = h->getKeyAsBigInt("ind", found);
    assert(found);

    prio = h->getKeyAsBigInt("priority", found);
    assert(found);

    // get modified date
    QoreValue t = h->getKeyValue("modified");
    assert(t.getType() == NT_DATE);
    const DateTimeNode* modified = t.get<const DateTimeNode>();
    mod = modified->getEpochSecondsUTC();
}

void SegmentEventQueue::init_event_queue(int segid, const QoreListNode* l) {
    AutoLocker al(&mutex);

    backend_queue_map_t::iterator i = backend_queue_map.find(segid);
    assert(i != backend_queue_map.end());

    assert(dynamic_cast<EventQueue*>(i->second));
    EventQueue* q = reinterpret_cast<EventQueue*>(i->second);

    ConstListIterator li(l);
    while (li.next()) {
        QoreValue n = li.getValue();
        assert(n.getType() == NT_HASH);
        const QoreHashNode* h = n.get<const QoreHashNode>();

        int64 wfiid;
        ParentInfo pi;
        int ind, prio;
        int64 mod;
        get_backend_event_info(h, wfiid, pi, ind, prio, mod);

        q->add_event(mod, wfiid, ind, prio, pi);
    }

    // notify waiting threads that there is data available
    q->wakeup();
}

void SegmentEventQueue::init_async_queue(int segid, const QoreListNode* l) {
    AutoLocker al(&mutex);

    backend_queue_map_t::iterator i = backend_queue_map.find(segid);
    assert(i != backend_queue_map.end());

    assert(dynamic_cast<AsyncQueue*>(i->second));
    AsyncQueue* q = reinterpret_cast<AsyncQueue*>(i->second);

    //printd(5, "SegmentEventQueue::init_async_queue() this=%p l=%p (len=%d)\n", this, l, l->size());

    ConstListIterator li(l);
    while (li.next()) {
        QoreValue n = li.getValue();
        assert(n.getType() == NT_HASH);
        const QoreHashNode* h = n.get<const QoreHashNode>();

        int64 wfiid;
        ParentInfo pi;
        int ind, prio;
        int64 mod;
        get_backend_event_info(h, wfiid, pi, ind, prio, mod);

        bool found;
        bool corrected = h->getKeyAsBigInt("corrected", found);
        assert(found);

        // get queue key
        n = h->getKeyValue("queuekey");
        assert(n.getType() == NT_STRING);

        const QoreStringNode* queuekey = n.get<const QoreStringNode>();
        assert(queuekey->strlen());

        q->add_async_event(mod, wfiid, ind, prio, corrected, pi, queuekey->stringRefSelf());
    }

    // notify waiting threads that there is data available
    q->wakeup();
}

void SegmentEventQueue::init_subworkflow_queue(int segid, const QoreListNode* l) {
    AutoLocker al(&mutex);

    backend_queue_map_t::iterator i = backend_queue_map.find(segid);
    assert(i != backend_queue_map.end());

    assert(dynamic_cast<SubWorkflowQueue*>(i->second));
    SubWorkflowQueue* q = reinterpret_cast<SubWorkflowQueue*>(i->second);

    ConstListIterator li(l);
    while (li.next()) {
        QoreValue n = li.getValue();
        assert(n.getType() == NT_HASH);
        const QoreHashNode* h = n.get<const QoreHashNode>();

        int64 wfiid;
        ParentInfo pi;
        int ind, prio;
        int64 mod;
        get_backend_event_info(h, wfiid, pi, ind, prio, mod);

        bool found;
        int64 swfiid = h->getKeyAsBigInt("subworkflow_instanceid", found);
        assert(swfiid);

        char status;

        bool corrected = h->getKeyAsBigInt("corrected", found);
        assert(found);
        if (corrected)
            status = 'C';
        else {
            n = h->getKeyValue("status");
            assert(n.getType() == NT_STRING);

            const QoreStringNode* stat = n.get<const QoreStringNode>();
            assert(stat->strlen() == 1);

            status = stat->getBuffer()[0];
        }

        q->add_subworkflow_event(mod, wfiid, ind, prio, pi, status, swfiid);
    }

    // notify waiting threads that there is data available
    q->wakeup();
}

// lock must be already held
void SegmentEventQueue::backend_broadcast() {
    assert(mutex.trylock());

    // signal all backend queues if there is data in the queue
    for (backend_queue_map_t::iterator i = backend_queue_map.begin(), e = backend_queue_map.end(); i != e; ++i)
        if (!i->second->empty())
            i->second->wakeup();
}

// lock must be already held
void SegmentEventQueue::requeue_retries_intern() {
    //printd(5, "SegmentEventQueue::requeue_retries_intern() this: %p retry_queue: %d async_queue: %d "
    //     retry_waiting: %d\n", retry_queue.size(), async_retry_queue.size(), retry_waiting);
    assert(mutex.trylock());

    retry_queue.marker_set.clear();
    async_retry_queue.marker_set.clear();
    fixed_retry_queue.marker_set.clear();
    if (retry_waiting)
        retry_cond.broadcast();
}

void SegmentEventQueue::requeue_retries() {
    AutoLocker al(&mutex);
    requeue_retries_intern();
}

void SegmentEventQueue::cleanup_connection(int id) {
    AutoLocker al(&mutex);
    conn_set.erase(id);
}

// called in the lock
void RetryQueue::remove_workflow_instance(int64 wfiid) {
    rwmap_t::iterator i = rwmap.find(wfiid);
    if (i == rwmap.end())
        return;

    delete i->second->second;
    erase(i->second);

    rwmap.erase(i);
}

int RetryQueue::toString(QoreString &str) {
    str.sprintf("marker len=%d len=%d: [", marker_set.size(), size());
    if (!empty()) {
        for (RetryQueue::iterator i = begin(), e = end(); i != e; ++i) {
            (*i).second->toString(str, marker_set.find((*i).second) != marker_set.end());
            str.concat(", ");
        }
        str.terminate(str.strlen() - 2);
    }
    return 0;
}

void SegmentEventQueue::remove_workflow_instance(int64 wfiid) {
    AutoLocker al(&mutex);
    retry_queue.remove_workflow_instance(wfiid);
    async_retry_queue.remove_workflow_instance(wfiid);
    fixed_retry_queue.remove_workflow_instance(wfiid);
    requeue_retries_intern();
}

void SubWorkflowQueue::add_subworkflow_event(int64 mod, int64 wfiid, int ind, int prio, const ParentInfo& pi,
        char status, int64 swfiid) {
    // can only submit status COMPLETE or ERROR
    assert(status == 'E' || status == 'C');

    wfmap_t &wfmap = status == 'C' ? c_wfmap : e_wfmap;

    wfmap_t::iterator i = wfmap.find(wfiid);
    if (i != wfmap.end()) {
        SubWorkflowQueueEntry *e = reinterpret_cast<SubWorkflowQueueEntry*>(i->second->second);
        assert(dynamic_cast<SubWorkflowQueueEntry*>(e));

        // try to insert in ind list
        e->ind_list.insert(ind);

        // do not need to signal as an existing entry was updated
        return;
    }

    backend_queue_t &q = (*this)[prio];
    backend_queue_t::iterator bi = q.insert(backend_queue_t::value_type(mod, new SubWorkflowQueueEntry(wfiid,
        ind, prio, pi, status, swfiid)));

    wfmap[wfiid] = bi;

    // signal waiting threads because a new entry was added
    signal();
}

// adds a new event; existing events for this step are deleted
void AsyncQueue::add_async_event(int64 mod, int64 wfiid, int ind, int prio, bool corrected, const ParentInfo& pi,
        QoreStringNode* n_queuekey, QoreValue n_data) {
    assert(n_queuekey);

    wfmap_t::iterator i = wfmap.find(wfiid);
    if (i != wfmap.end()) {
        AsyncQueueEntry *e = reinterpret_cast<AsyncQueueEntry*>(i->second->second);
        assert(dynamic_cast<AsyncQueueEntry*>(e));

        // see if ind is already present
        if (e->ind_map.find(ind) != e->ind_map.end()) {
            //printd(5, "AsyncQueue::add_async_event() this=%p discarding duplicate message for wfiid=%lld ind=%d "
            //    "queuekey=%s, corrected=%d\n", this, wfiid, ind, n_queuekey->getBuffer(), (int)corrected);
            // discard data
            n_queuekey->deref();
            n_data.discard(0);
            return;
        }

        // insert new event
        e->ind_map.insert(std::make_pair(ind, async_entry(n_queuekey, n_data, corrected)));

        // do not need to signal as an existing entry was updated
        return;
    }

    backend_queue_t &q = (*this)[prio];
    backend_queue_t::iterator bi = q.insert(backend_queue_t::value_type(mod, new AsyncQueueEntry(wfiid, ind, prio,
        corrected, pi, n_queuekey, n_data)));

    wfmap[wfiid] = bi;

    //printd(5, "AsyncQueue::add_async_event() this=%p queued wfiid=%lld ind=%d prio=%d qlen=%d waiting=%d\n", this,
    //    wfiid, ind, prio, q.size(), waiting);

    // signal waiting threads because a new entry was added
    signal();
}

void EventQueue::add_event(int64 mod, int64 wfiid, int ind, int prio, const ParentInfo& pi) {
    wfmap_t::iterator i = wfmap.find(wfiid);
    if (i != wfmap.end()) {
        EventQueueEntry *e = reinterpret_cast<EventQueueEntry*>(i->second->second);
        assert(dynamic_cast<EventQueueEntry*>(e));

        // try to insert in ind list
        e->ind_list.insert(ind);

        // do not need to signal as an existing entry was updated
        return;
    }

    // insert new entry
    backend_queue_t &q = (*this)[prio];
    backend_queue_t::iterator bi = q.insert(backend_queue_t::value_type(mod,
        new EventQueueEntry(wfiid, ind, prio, pi)));

    wfmap[wfiid] = bi;

    // signal waiting threads because a new entry was added
    signal();
}

void SegmentEventQueue::queue_subworkflow_event(int segid, int64 wfiid, int ind, int prio, char status, int64 swfiid,
        const QoreHashNode* parent_info) {
    ParentInfo pi;
    if (parent_info)
        get_parent_info(parent_info, pi);

    AutoLocker al(&mutex);

    backend_queue_map_t::iterator i = backend_queue_map.find(segid);
    assert(i != backend_queue_map.end());
    assert(dynamic_cast<SubWorkflowQueue*>(i->second));

    // get current epoch offset
    int64 mod = time(0);
    reinterpret_cast<SubWorkflowQueue*>(i->second)->add_subworkflow_event(mod, wfiid, ind, prio, pi, status, swfiid);
}

void SegmentEventQueue::queue_async_event(int segid, int64 wfiid, int ind, int prio, bool corrected,
        const QoreStringNode* queuekey, QoreValue data, const QoreHashNode* parent_info) {
    ParentInfo pi;
    if (parent_info)
        get_parent_info(parent_info, pi);

    AutoLocker al(&mutex);

    backend_queue_map_t::iterator i = backend_queue_map.find(segid);
    assert(i != backend_queue_map.end());
    assert(dynamic_cast<AsyncQueue*>(i->second));

    // get current epoch offset
    int64 mod = time(0);
    reinterpret_cast<AsyncQueue*>(i->second)->add_async_event(mod, wfiid, ind, prio, corrected, pi,
        queuekey->stringRefSelf(), data.refSelf());
}

void SegmentEventQueue::queue_workflow_event(int segid, int64 wfiid, int ind, int prio, const QoreHashNode* parent_info) {
    ParentInfo pi;
    if (parent_info)
        get_parent_info(parent_info, pi);

    AutoLocker al(&mutex);

    backend_queue_map_t::iterator i = backend_queue_map.find(segid);
    assert(i != backend_queue_map.end());
    assert(dynamic_cast<EventQueue*>(i->second));

    // get current epoch offset
    int64 mod = time(0);
    reinterpret_cast<EventQueue*>(i->second)->add_event(mod, wfiid, ind, prio, pi);
}

void SegmentEventQueue::queue_primary_event(int64 wfiid, int prio, const QoreHashNode* parent_info,
        const DateTimeNode* scheduled) {
    ParentInfo pi;
    if (parent_info)
        get_parent_info(parent_info, pi);

    AutoLocker al(&mutex);
    primary_queue.add(wfiid, prio, pi, scheduled);
}

// requeue retries is called by the caller
int RetryQueue::add(int64 wfiid, int64 mod, const ParentInfo& pi) {
    rwmap_t::iterator i = rwmap.find(wfiid);
    if (i != rwmap.end()) {
        if (mod < i->second->second->mod) {
            //printd(5, "RetryQueue::add() requeueing retry event for wfiid=%d mod=%lld (new mod %lld)\n", wfiid,
            //    i->second->second->mod, mod);

            RetryQueueEntry *e = i->second->second;
            e->mod = mod;
            erase(i->second);

            retry_map_t::iterator ri = insert(retry_map_t::value_type(mod, e));
            i->second = ri;
            return 0;
        } else {
            //printd(5, "RetryQueue::add() discarding duplicate retry event for wfiid=%d mod=%lld (new mod %lld)\n",
            //    wfiid, i->second->second->mod, mod);
            return -1;
        }
    }

    RetryQueueEntry *e = new RetryQueueEntry(wfiid, mod, pi);
    retry_map_t::iterator ri = insert(retry_map_t::value_type(e->mod, e));
    rwmap[wfiid] = ri;
    return 0;
}

void SegmentEventQueue::queue_retry_event(int64 wfiid, const DateTimeNode& d, const QoreHashNode* parent_info) {
    ParentInfo pi;
    if (parent_info)
        get_parent_info(parent_info, pi);

    AutoLocker al(&mutex);
    if (!retry_queue.add(wfiid, d.getEpochSecondsUTC(), pi))
        requeue_retries_intern();
}

void SegmentEventQueue::queue_retry_event_fixed(int64 wfiid, const DateTimeNode& d, const QoreHashNode* parent_info) {
    ParentInfo pi;
    if (parent_info)
        get_parent_info(parent_info, pi);

    AutoLocker al(&mutex);
    if (!fixed_retry_queue.add(wfiid, d.getEpochSecondsUTC(), pi))
        requeue_retries_intern();
}

void SegmentEventQueue::queue_async_retry_event(int64 wfiid, const DateTimeNode& d, const QoreHashNode* parent_info) {
    ParentInfo pi;
    if (parent_info)
        get_parent_info(parent_info, pi);

    AutoLocker al(&mutex);
    if (!async_retry_queue.add(wfiid, d.getEpochSecondsUTC(), pi))
        requeue_retries_intern();
}

void RetryQueue::merge(RetryQueue& rq) {
    for (retry_map_t::iterator i = rq.begin(), e = rq.end(); i != e; ++i)
        insert(retry_map_t::value_type(i->first, i->second));
    rq.clear();
}

// "wakeup" is called by this function's caller
void AsyncQueue::merge(BackendQueue* bq) {
    for (backend_map_t::iterator mi = bq->begin(), me = bq->end(); mi != me; ++mi) {
        backend_queue_t &q = mi->second;
        assert(!q.empty());
        backend_queue_t &myq = (*this)[mi->first];
        for (backend_queue_t::iterator i = q.begin(), e = q.end(); i != e; ++i) {
            backend_queue_t::iterator bi = myq.insert(backend_queue_t::value_type(i->first, i->second));
            wfmap[i->second->wfiid] = bi;
        }
        //q.clear();
    }
    bq->clear();

    AsyncQueue* eq = reinterpret_cast<AsyncQueue*>(bq);
    eq->wfmap.clear();
}

// "wakeup" is called by this function's caller
void EventQueue::merge(BackendQueue* bq) {
    for (backend_map_t::iterator mi = bq->begin(), me = bq->end(); mi != me; ++mi) {
        backend_queue_t &q = mi->second;
        assert(!q.empty());
        backend_queue_t &myq = (*this)[mi->first];
        for (backend_queue_t::iterator i = q.begin(), e = q.end(); i != e; ++i) {
            backend_queue_t::iterator bi = myq.insert(backend_queue_t::value_type(i->first, i->second));
            wfmap[i->second->wfiid] = bi;
        }
        //q.clear();
    }
    bq->clear();

    EventQueue* eq = reinterpret_cast<EventQueue*>(bq);
    eq->wfmap.clear();
}

// "wakeup" is called by this function's caller
void SubWorkflowQueue::merge(BackendQueue* bq) {
    for (backend_map_t::iterator mi = bq->begin(), me = bq->end(); mi != me; ++mi) {
        backend_queue_t &q = mi->second;
        assert(!q.empty());
        backend_queue_t &myq = (*this)[mi->first];
        for (backend_queue_t::iterator i = q.begin(), e = q.end(); i != e; ++i) {
            backend_queue_t::iterator bi = myq.insert(backend_queue_t::value_type(i->first, i->second));
            SubWorkflowQueueEntry *qe = reinterpret_cast<SubWorkflowQueueEntry*>(i->second);
            if (qe->status == 'C')
                c_wfmap[qe->wfiid] = bi;
            else
                e_wfmap[qe->wfiid] = bi;
        }
    }
    bq->clear();

    SubWorkflowQueue* sq = reinterpret_cast<SubWorkflowQueue*>(bq);
    sq->c_wfmap.clear();
    sq->e_wfmap.clear();
}

void SegmentEventQueue::merge_all(SegmentEventQueue* seq) {
    AutoLocker al(&mutex);

    // merge retry queues
    retry_queue.merge(seq->retry_queue);
    async_retry_queue.merge(seq->async_retry_queue);
    fixed_retry_queue.merge(seq->fixed_retry_queue);
    requeue_retries_intern();

    // merge backend queues
    for (backend_queue_map_t::iterator i = backend_queue_map.begin(), e = backend_queue_map.end(); i != e; ++i) {
        int id = i->first;
        backend_queue_map_t::iterator bi = seq->backend_queue_map.find(id);
        assert(bi != seq->backend_queue_map.end());

        BackendQueue* bq = i->second, *n_bq = bi->second;

        if (!n_bq->empty()) {
            // this will only broadcast if there are threads waiting, meaning that the queue was empty before
            bq->wakeup();
            bq->merge(n_bq);
        }
    }
}

bool SegmentEventQueue::grab_segment_inc(int64 wfiid) {
    assert(wfiid);
    AutoLocker al(&mutex);
    workflow_seg_map_t::iterator i = workflow_seg_map.find(wfiid);
    if (i != workflow_seg_map.end()) {
        // bug 667: return true if a retry is in progress for this segment already
        if (i->second < 0)
            return true;
        ++i->second;
    } else {
        workflow_seg_map.insert(std::make_pair(wfiid, 1));
    }
    return false;
}

QoreHashNode* SegmentEventQueue::get_primary_event(int conn_id) {
    AutoLocker al(&mutex);

    while (true) {
        if (term || (conn_set.find(conn_id) != conn_set.end()))
            break;

        // get current time (UTC epoch offset)
        int64 now = q_epoch();

        // get primary event if available
        if (primary_queue.checkEvent(now))
            return primary_queue.getEvent();

        // wait for event
        primary_queue.wait(now, mutex);
    }
    return 0;
}

bool SegmentEventQueue::resched_primary_event(int64 wfiid, const DateTimeNode* scheduled) {
    AutoLocker al(mutex);
    return primary_queue.resched(wfiid, scheduled);
}

bool SegmentEventQueue::reprioritize(int64 wfiid, int prio) {
    AutoLocker al(mutex);

    bool b = primary_queue.reprioritize(wfiid, prio);
    // if it's in the initial primary queue, then it can't be in any other queue
    if (!b) {
        // check in backend queues
        for (backend_queue_map_t::iterator i = backend_queue_map.begin(), e = backend_queue_map.end(); i != e; ++i) {
            BackendQueue& beq = *(i->second);

            // search each priority queue; we assume that there will not be an excessive number
            // of priorities for each workflow and that priorities will not change often enough
            // to justify a workflow instance ID -> queue map as well
            for (backend_map_t::iterator bi = beq.begin(), be = beq.end(); bi != be; ++bi){
                if (bi->first == prio)
                    continue;

                backend_queue_t &q = bi->second;

                // get all entries for this workflow_instanceid and move to the new priority queue
                std::pair<backend_queue_t::iterator, backend_queue_t::iterator> range = q.equal_range(wfiid);
                for (backend_queue_t::iterator ri = range.first; ri != range.second;) {
                    if (!b)
                        b = true;

                    backend_queue_t::iterator ti = ri;
                    ++ri;

                    beq[prio].insert(backend_queue_t::value_type(wfiid, ti->second));
                    q.erase(ti);
                }
            }
        }
    }

    return b;
}

void SegmentEventQueue::removeWorkflowOrder(int64 wfiid, int64 prio) {
    AutoLocker al(mutex);

    // if it's in the initial primary queue, then it can't be in any other queue
    if (primary_queue.removeWorkflowOrder(wfiid))
        return;

    // check in backend queues
    for (backend_queue_map_t::iterator i = backend_queue_map.begin(), e = backend_queue_map.end(); i != e; ++i) {
        BackendQueue& beq = *(i->second);

        backend_map_t::iterator bi = beq.find(prio);
        if (bi != beq.end()) {
            backend_queue_t &q = bi->second;
            q.erase(wfiid);
        }
    }
}

BackendQueueEntry *SegmentEventQueue::get_backend_event_unlocked(int conn_id, int segid, SegmentEventQueue& beq,
        BackendQueue& be) {
    assert(mutex.trylock());

    while (true) {
        if (term || (conn_set.find(conn_id) != conn_set.end()))
            break;

        for (backend_map_t::iterator mi = be.begin(), me = be.end(); mi != me; ++mi) {
            backend_queue_t &q = mi->second;
            for (backend_queue_t::iterator i = q.begin(), e = q.end(); i != e; ++i) {
                BackendQueueEntry *qe = i->second;

                // see if workflow instance entry exists
                workflow_seg_map_t::iterator fsi = workflow_seg_map.find(qe->wfiid);
                //printd(5, "SegmentEventQueue::get_backend_event(conn_id=%d, segid=%d) this=%p qe=%p wfiid=%lld "
                //    "ref=%d\n", conn_id, segid, this, qe, qe->wfiid,
                //    fsi != workflow_seg_map.end() ? fsi->second : 0);

                if (fsi != workflow_seg_map.end()) {
                    // if a retry is in progress, then continue
                    if (fsi->second < 0)
                        continue;

                    // otherwise increment the in-use count
                    ++fsi->second;
                } else {
                    assert(qe->wfiid);
                    workflow_seg_map.insert(std::make_pair(qe->wfiid, 1));
                }

                // get hash and erase element from queue
                q.erase(i);

                //printd(5, "SegmentEventQueue::get_backend_event(conn_id=%d, segid=%d) this=%p qe=%p wfiid=%lld "
                //    prio=%d qsize=%d -> %d\n", conn_id, segid, this, qe, qe->wfiid, qe->prio, q.size() + 1,
                //    q.size());

                // remove entire queue for priority if queue empty
                if (q.empty())
                    be.erase(mi);

                return qe;
            }
        }
        // no data available, wait
        be.wait(mutex);
    }
    return 0;
}

QoreHashNode* SegmentEventQueue::get_subworkflow_event(int conn_id, int segid, SegmentEventQueue& beq) {
    AutoLocker al(mutex);

    backend_queue_map_t::iterator bqi = backend_queue_map.find(segid);
    assert(bqi != backend_queue_map.end());

    assert(dynamic_cast<SubWorkflowQueue*>(bqi->second));

    SubWorkflowQueueEntry *qe = reinterpret_cast<SubWorkflowQueueEntry*>(get_backend_event_unlocked(conn_id, segid, beq, *(bqi->second)));

    if (!qe)
        return 0;

    SubWorkflowQueue* be = reinterpret_cast<SubWorkflowQueue*>(bqi->second);

    wfmap_t &wfmap = qe->status == 'C' ? be->c_wfmap : be->e_wfmap;

    // remove from lookup map
    wfmap_t::iterator wi = wfmap.find(qe->wfiid);
    assert(wi != wfmap.end());
    wfmap.erase(wi);

    QoreHashNode* rv = qe->get_hash();
    delete qe;
    return rv;
}

QoreHashNode* SegmentEventQueue::get_async_event(int conn_id, int segid, SegmentEventQueue& beq) {
    AutoLocker al(mutex);

    backend_queue_map_t::iterator bqi = backend_queue_map.find(segid);
    assert(bqi != backend_queue_map.end());

    assert(dynamic_cast<AsyncQueue*>(bqi->second));

    BackendQueueEntry *qe = get_backend_event_unlocked(conn_id, segid, beq, *(bqi->second));

    //printd(5, "SegmentEventQueue::get_async_event() this=%p returning=%p (wfiid=%lld)\n", this, qe, qe ? qe->wfiid : 0ll);

    if (!qe) {
        return nullptr;
    }

    // remove workflow from wfmap
    reinterpret_cast<AsyncQueue*>(bqi->second)->wfmap.erase(qe->wfiid);

    QoreHashNode* rv = qe->get_hash();
    delete qe;
    return rv;
}

QoreHashNode* SegmentEventQueue::get_workflow_event(int conn_id, int segid, SegmentEventQueue& beq) {
    AutoLocker al(&mutex);

    backend_queue_map_t::iterator bqi = backend_queue_map.find(segid);
    assert(bqi != backend_queue_map.end());

    assert(dynamic_cast<EventQueue*>(bqi->second));

    BackendQueueEntry *qe = get_backend_event_unlocked(conn_id, segid, beq, *(bqi->second));
    if (!qe) {
        return nullptr;
    }

    // remove workflow from wfmap
    reinterpret_cast<EventQueue*>(bqi->second)->wfmap.erase(qe->wfiid);

    QoreHashNode* rv = qe->get_hash();
    delete qe;
    return rv;
}

#define RV_DBG 5

void SegmentEventQueue::get_retry_values(int64& retry, int64& async_retry, int conn_id) const {
    assert(mutex.trylock());
    assert(retry == -1 && async_retry == -1);

    QoreString conn_str;
    conn_str.sprintf("%d", conn_id);

    bool found;
    int64 val;

    if (retry != -1 && async_retry != -1) {
        return;
    }

    // check execution instance options
    {
        // get workflow params
        ValueHolder wfip(workflow_params->getReferencedMemberNoMethod(conn_str.getBuffer(), 0), 0);

        QoreHashNode* h = wfip->getType() == NT_HASH ? wfip->get<QoreHashNode>() : nullptr;
        if (h) {
            // get retry delay to use; get "retry" value
            if (retry == -1) {
                val = h->getKeyAsBigInt("retry", found);
                if (val > 0) {
                    retry = val;
                    printd(RV_DBG, "get_retry_values() got retry=%lld from execution instance workflow params\n",
                        retry);
                }
            }

            if (async_retry == -1) {
                val = h->getKeyAsBigInt("async", found);
                if (val > 0) {
                    async_retry = val;
                    printd(RV_DBG, "get_retry_values() got async_retry=%lld from execution instance workflow "
                        "params\n", async_retry);
                }
            }

            if (retry != -1 && async_retry != -1)
                return;
        }
    }

    // check per-workflow-type params if still not set
    if (retry == -1) {
        val = workflow_params->getMemberAsBigInt("retry", found, 0);
        if (val > 0) {
            retry = val;
            printd(RV_DBG, "get_retry() got retry=%lld from global workflow params\n", retry);
        }
    }

    if (async_retry == -1) {
        val = workflow_params->getMemberAsBigInt("async", found, 0);
        if (val > 0) {
            async_retry = val;
            printd(RV_DBG, "get_retry_values() got async_retry=%lld from global workflow params\n", async_retry);
        }
    }

    if (retry == -1) {
        // get value of global option
        retry = getOptionBigInt("recover_delay");
        printd(RV_DBG, "get_retry_values() got retry=%lld from global options\n", retry);
    }

    if (async_retry == -1) {
        async_retry = getOptionBigInt("async_delay");
        printd(RV_DBG, "get_retry_values() got async_retry=%lld from global options\n", async_retry);
    }
}

int64 SegmentEventQueue::getOptionBigInt(const char* opt) const {
    ValueHolder h(qorus_options->getReferencedMemberNoMethod("opts", nullptr), nullptr);
    if (h) {
        bool found;
        return h->get<QoreHashNode>()->getKeyAsBigInt(opt, found);
    }
    return 0;
}

QoreHashNode* SegmentEventQueue::get_event(retry_map_t::iterator i, RetryQueue& queue, int64& wfiid) {
    assert(mutex.trylock());
    // remove lookup entry
    rwmap_t::iterator ri = queue.rwmap.find(i->second->wfiid);
    assert(ri != queue.rwmap.end());
    queue.rwmap.erase(ri);

    // delete entry when exiting this block
    std::unique_ptr<RetryQueueEntry> re(i->second);
    // erase queue element
    queue.erase(i);

    wfiid = re->wfiid;
    return re->get_hash();
}

void SegmentEventQueue::mark_wait_retry(retry_map_t::iterator i, RetryQueue& queue, int64 diff) {
    assert(mutex.trylock());
    RetryQueueEntry *mark = i->second;
    // otherwise set marker on entry
    queue.marker_set.insert(mark);
    // and sleep until trigger or requeue time
    ++retry_waiting;
    retry_cond.wait(&mutex, diff * 1000);
    --retry_waiting;
    // delete marker if still there
    marker_set_t::iterator mi = queue.marker_set.find(mark);
    if (mi != queue.marker_set.end())
        queue.marker_set.erase(mi);
}

QoreHashNode* SegmentEventQueue::get_retry_event(int conn_id, ExceptionSink* xsink) {
    AutoLocker al(&mutex);

    printd(5, "SegmentEventQueue::get_retry_event() this=%p fsize=%lu rsize=%lu asize=%lu wp=%p qo=%p\n", this,
        fixed_retry_queue.size(), retry_queue.size(), async_retry_queue.size(), workflow_params, qorus_options);

/*
    {
        QoreNodeAsStringHelper str(workflow_params, FMT_NONE, xsink);
        printd(0, "workflow_params=%s\n", str->getBuffer());
    }

    {
        QoreNodeAsStringHelper str(qorus_options, FMT_NONE, xsink);
        printd(0, "qorus_options=%s\n", str->getBuffer());
    }
*/

    QoreHashNode* rv = 0;
    int64 wfiid;
    while (true) {
        if (term || (conn_set.find(conn_id) != conn_set.end()))
            break;

        int_set_t::iterator rci = retry_conn_set.find(conn_id);
        if (rci != retry_conn_set.end()) {
            retry_conn_set.erase(rci);
            break;
        }

        // get earliest trigger time
        int64 trig = -1;

        // first check fixed queue
        retry_map_t::iterator fi = fixed_retry_queue.begin();
        retry_map_t::iterator fie = fixed_retry_queue.end();

        // get first fixed retry entry
        for (; fi != fie; ++fi) {
            RetryQueueEntry *re = fi->second;
            // see if workflow instance entry exists
            workflow_seg_map_t::iterator fsi = workflow_seg_map.find(re->wfiid);

            // skip this entry if the segment is in progress
            if (fsi != workflow_seg_map.end() && fsi->second)
                continue;

            // skip this entry if another thread is already sleeping on it
            if (fixed_retry_queue.marker_set.find(fi->second) != fixed_retry_queue.marker_set.end())
                continue;

            wfiid = re->wfiid;
            trig = re->mod;
            break;
        }

        int64 retry = -1, async_retry = -1;
        get_retry_values(retry, async_retry, conn_id);

#ifdef DEBUG
        wfiid = 0;
#endif

        // loop through retry queue
        retry_map_t::iterator ri = retry_queue.begin();
        retry_map_t::iterator rie = retry_queue.end();
        for (; ri != rie; ++ri) {
            RetryQueueEntry *re = ri->second;
            // see if workflow instance entry exists
            workflow_seg_map_t::iterator fsi = workflow_seg_map.find(re->wfiid);

            // skip this entry if the segment is in progress
            if (fsi != workflow_seg_map.end() && fsi->second)
                continue;

            // skip this entry if another thread is already sleeping on it
            if (retry_queue.marker_set.find(ri->second) != retry_queue.marker_set.end())
                continue;

            // found a valid entry
            int64 retry_trig = re->mod + retry;

            // if the entry's trigger time is after the fixed event already found
            // then mark this queue as not relevant
            if (trig != -1 && retry_trig > trig)
                ri = rie;
            else {
                // otherwise tag with this queue
                wfiid = re->wfiid;
                //fi = fie;
                trig = retry_trig;
            }
            break;
        }

        // see if there's an async entry with an earlier trigger time
        retry_map_t::iterator ari = async_retry_queue.begin();
        retry_map_t::iterator arie = async_retry_queue.end();
        for (; ari != arie; ++ari) {
            RetryQueueEntry *re = ari->second;
            // see if workflow instance entry exists
            workflow_seg_map_t::iterator fsi = workflow_seg_map.find(re->wfiid);

            // skip this entry if the segment is in progress
            if (fsi != workflow_seg_map.end() && fsi->second)
                continue;

            // skip this entry if another thread is already sleeping on it
            if (async_retry_queue.marker_set.find(ari->second) != async_retry_queue.marker_set.end())
                continue;

            int64 async_trig = re->mod + async_retry;
            if (trig != -1 && async_trig > trig)
                ari = arie;
            else {
                wfiid = re->wfiid;
                //fi = fie;
                //ri = rie;
                trig = async_trig;
            }
            break;
        }

        printd(5, "SegmentEventQueue::get_retry_event() this=%p, cid=%d, wfiid=%lld, fq=%lu, rq=%lu, arq=%lu (fi=%d, "
            "ri=%d, ari=%d, fq.ms=%lu, rq.ms=%lu, arq.ms=%lu), trig=%lld\n", this, conn_id,
            wfiid,
            fixed_retry_queue.size(), retry_queue.size(), async_retry_queue.size(),
            fi != fie, ri != rie, ari != arie,
            fixed_retry_queue.marker_set.size(),
            retry_queue.marker_set.size(),
            async_retry_queue.marker_set.size(),
            trig);

        if (trig == -1) { //  if there are no elements to grab, then wait until data is updated
            ++retry_waiting;
            retry_cond.wait(&mutex);
            --retry_waiting;
            continue;
        }

        // get current GMT to compare to epoch seconds
        int64 diff;
        if (trig) {
            diff = trig - q_epoch();
            printd(5, "SegmentEventQueue::get_retry_event() this=%p, cid=%d, wfiid=%lld, ri=%d, ari=%d, trig=%lld, "
                "now=%lld, diff=%lld\n", this, conn_id, wfiid,
                ri != retry_queue.end(), ari != async_retry_queue.end(), trig, trig - diff, diff);
        } else {
            diff = 0;
            // immediate retry, trig = 0
            printd(5, "SegmentEventQueue::get_retry_event() this=%p, cid=%d, wfiid=%lld, ri=%d, ari=%d, trig=0, "
                "immediate retry\n", this, conn_id,
                wfiid, ri != retry_queue.end(), ari != async_retry_queue.end());
        }

        // first check if we have an async retry
        if (ari != arie) {
            if (diff <= 0) {
                rv = get_event(ari, async_retry_queue, wfiid);
                break;
            }

            mark_wait_retry(ari, async_retry_queue, diff);
            continue;
        }

        // then check if we have a normal retry
        if (ri != rie) {
            // if data is available now
            if (diff <= 0) {
                rv = get_event(ri, retry_queue, wfiid);
                break;
            }

            mark_wait_retry(ri, retry_queue, diff);
            continue;
        }

        // otherwise we have a fixed retry
        assert(fi != fie);

        // if data is available now
        if (diff <= 0) {
            rv = get_event(fi, fixed_retry_queue, wfiid);
            break;
        }

        mark_wait_retry(fi, fixed_retry_queue, diff);
    }

    // mark retry in progress
    if (rv) {
        // see if workflow instance entry exists
        workflow_seg_map_t::iterator fsi = workflow_seg_map.find(wfiid);
        //printd(5, "SegmentEventQueue::get_retry_event() this=%p wfiid=%lld (in seg map=%s)\n", this, wfiid, fsi != workflow_seg_map.end() ? "true" : "false");
        if (fsi != workflow_seg_map.end()) {
            assert(!fsi->second);
            fsi->second = -1;
        } else { // insert into workflow segment map
            assert(wfiid);
            workflow_seg_map.insert(std::make_pair(wfiid, -1));
        }
    }

    //printd(5, "SegmentEventQueue::get_retry_event() this=%p returning wfiid=%lld rv=%p\n", this, wfiid, rv);
    return rv;
}

void SegmentEventQueue::release_segment(int64 wfiid) {
    AutoLocker al(&mutex);

    // see if workflow instance entry exists
    workflow_seg_map_t::iterator i = workflow_seg_map.find(wfiid);
    assert(i != workflow_seg_map.end());

    // if this is the last reference, delete the structure for this workflow instance
    if (!--i->second) {
        workflow_seg_map.erase(i);
        if (retry_waiting)
            retry_cond.signal();
    }
}

void SegmentEventQueue::release_retry_segment(int64 wfiid) {
    AutoLocker al(&mutex);

    // see if workflow instance entry exists
    workflow_seg_map_t::iterator i = workflow_seg_map.find(wfiid);
    //printd(5, "SegmentEventQueue::release_retry_segment(wfiid=%lld) this=%p in seg map = %s, refs = %d\n", wfiid,
    //    this, i != workflow_seg_map.end() ? "true" : "false", i != workflow_seg_map.end() ? i->second : 999999999);
    assert(i != workflow_seg_map.end());
    assert(i->second == -1);

    workflow_seg_map.erase(i);

    backend_broadcast();
}

QoreStringNode* SegmentEventQueue::toString() {
    QoreStringNodeHolder str(new QoreStringNode);

    AutoLocker al(&mutex);

    str->sprintf("SegmentEventQueue %p: ", this);
    primary_queue.toString(**str);

    str->concat("], fixed retry ");
    fixed_retry_queue.toString(**str);

    str->concat("], retry ");
    retry_queue.toString(**str);

    str->concat("], async retry ");
    async_retry_queue.toString(**str);

    str->sprintf("], backend (len: %d): [", backend_queue_map.size());
    if (!backend_queue_map.empty()) {
        for (backend_queue_map_t::iterator i = backend_queue_map.begin(), e = backend_queue_map.end(); i != e; ++i) {
            str->sprintf("segid: %d len: %d: [", (*i).first, (*i).second->size());

            if (!(*i).second->empty()) {
                for (backend_map_t::iterator mi = (*i).second->begin(), me = (*i).second->end(); mi != me; ++mi) {
                    backend_queue_t &q = mi->second;
                    str->sprintf("prio %d len: %d: [", mi->first, q.size());

                    for (backend_queue_t::iterator si = q.begin(), se = q.end(); si != se; ++si) {
                        si->second->toString(**str);
                        str->concat("], ");
                    }
                    str->terminate(str->strlen() - 2);
                    str->concat("], ");
                }
                str->terminate(str->strlen() - 2);
            }
            str->concat("], ");
        }
        str->terminate(str->strlen() - 2);
    }

    str->sprintf("], workflow segment map (len: %d): [", workflow_seg_map.size());
    if (!workflow_seg_map.empty()) {
        for (workflow_seg_map_t::iterator i = workflow_seg_map.begin(), e = workflow_seg_map.end(); i != e; ++i)
            str->sprintf("%lld -> (refs: %d), ", (*i).first, (*i).second);

        str->terminate(str->strlen() - 2);
    }
    str->concat(']');

    return str.release();
}

QoreStringNode* SegmentEventQueue::getSummary() {
    QoreStringNode* str = new QoreStringNode;

    AutoLocker al(&mutex);

    str->sprintf("SegmentEventQueue %p: primary: (", this);
    primary_queue.summary(*str);
    str->sprintf("), scheduled len: %d, fixed retry len: %d (mlen: %d), retry len: %d (mlen: %d), "
        "async retry len: %d (mlen: %d), backend len: %d: [",
        primary_queue.scheduledSize(), fixed_retry_queue.size(), fixed_retry_queue.marker_set.size(),
        retry_queue.size(), retry_queue.marker_set.size(), async_retry_queue.size(),
        async_retry_queue.marker_set.size(), backend_queue_map.size());

    if (!backend_queue_map.empty()) {
        for (backend_queue_map_t::iterator i = backend_queue_map.begin(), e = backend_queue_map.end(); i != e; ++i)
            str->sprintf("segid: %d -> len: %d, ", (*i).first, (*i).second->size());
        str->terminate(str->strlen() - 2);
    }

    str->sprintf("], workflow segment map len: %d", workflow_seg_map.size());

    return str;
}
