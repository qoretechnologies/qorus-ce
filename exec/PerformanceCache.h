/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
 PerformanceCache.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

#ifndef _QORUS_PERFORMANCE_CACHE_H
#define _QORUS_PERFORMANCE_CACHE_H

#include <qore/Qore.h>

#include <stdint.h>

#include <deque>
#include <map>

struct DataPointHistory {
   // average
   double avg;
   // throughput
   double tp;

   DLLLOCAL DataPointHistory(double a, double t) : avg(a), tp(t) {
   }
};

typedef std::deque<DataPointHistory> dphl_t;

struct DataPoint {
   int64 v; // value
   int64 t; // time point (epoch offset)

   DLLLOCAL DataPoint() : v(0), t(0) {
   }

   DLLLOCAL DataPoint(int64 n_v) : v(n_v), t(q_epoch()) {
   }

   DLLLOCAL DataPoint(const DataPoint& p) : v(p.v), t(p.t) {
   }

   DLLLOCAL bool isSet() const {
      return t > 0;
   }

   DLLLOCAL DataPoint& operator=(const DataPoint& p) {
      v = p.v;
      t = p.t;
      return *this;
   }
};

class DataPointList {
protected:
    // list type
    typedef std::deque<DataPoint> dpl_t;
    dpl_t list;

    // running total of values of data point list
    double sum;

public:
    DLLLOCAL DataPointList() : sum(0.0) {
    }

    DLLLOCAL void push(const DataPoint& p) {
        list.push_back(p);
        sum += (double)p.v;
    }

    DLLLOCAL void pop(int64 t) {
        while (!list.empty()) {
            dpl_t::iterator i = list.begin();
            if (i->t > t)
                break;
            sum -= (double)i->v;
            if (sum < 0)
                sum = 0.0;
            list.erase(i);
        }
    }

    // get the list's start timestamp or -1 if the list is empty
    DLLLOCAL int64 getStart() const {
        return list.empty() ? -1 : list.begin()->t;
    }

    // get the list's average value
    DLLLOCAL double getAverage(double& tp) const {
        if (list.empty()) {
            tp = 0.0;
            return 0.0;
        }

        double rv = sum / (double)list.size();
        tp = 3600000000.0 / rv;
        return rv;
    }
};

// forward reference to the PerformanceCache class
class PerformanceCache;

typedef safe_dslist<Queue*> qlist_t;

class PerformanceCacheManager : public AbstractPrivateData {
protected:
    typedef std::map<const char*, PerformanceCache*, ltstr> pcmap_t;

    // map of caches
    pcmap_t pcmap;

    // mutex
    QoreThreadLock m;
    // event condition var
    QoreCondition cevent;
    // shutdown condition var
    QoreCondition cstop;

    bool running; // thread running flag
    bool stop;    // stop flag

    DLLLOCAL virtual ~PerformanceCacheManager() {
        assert(pcmap.empty());
    }

public:
    typedef pcmap_t::iterator iterator;

    DLLLOCAL PerformanceCacheManager() : running(false), stop(false) {
    }

    // background thread function
    DLLLOCAL void run();

    DLLLOCAL PerformanceCache* add(const QoreStringNode* name);

    DLLLOCAL void del(PerformanceCache* pc, ExceptionSink* xsink);

    // starts the performance cache background thread
    DLLLOCAL int start(ExceptionSink* xsink);

    // stops the performance cache background thread
    // and deletes all the caches
    DLLLOCAL void shutdown(ExceptionSink* xsink);
};

// 120 seconds of performance history per cache
#define PERFCACHE_HIST_SIZE 120

class PerformanceCache : public AbstractPrivateData {
protected:
    // performance for the last second
    DataPointList l_onesec;

    // performance history per second; first entry is the earliest second
    dphl_t l_hist;

    // manager ref count
    QoreReferenceCounter mrc;

    // mutex
    QoreThreadLock m;

    // listener queues
    qlist_t qlist;

    // index in containing map
    PerformanceCacheManager::iterator pi;

    // name of the cache
    QoreStringNode* name;

    int64 start;  // the start epoch offset

    double sum,   // sum total of all sample values
        count;     // total number of samples

    bool running;

    DLLLOCAL virtual ~PerformanceCache() {
        name->deref();
        assert(qlist.empty());
    }

public:
    typedef qlist_t::iterator iterator;
    typedef qlist_t::node_t node_t;

    DLLLOCAL PerformanceCache(const QoreStringNode* n) : name(n->stringRefSelf()), start(q_epoch()), sum(0.0), count(0.0), running(true) {
    }

    DLLLOCAL void setIndex(PerformanceCacheManager::iterator n_pi) {
        pi = n_pi;
    }

    DLLLOCAL PerformanceCacheManager::iterator getIndex() const {
        return pi;
    }

    // Queue must be already referenced for assignment
    DLLLOCAL iterator addListenerQueue(Queue* q) {
        //printd(5, "PerformanceCache::addListenerQueue() this: %p '%s': q: %p\n", this, name->getBuffer(), q);

        AutoLocker al(m);
        qlist.push_back(q);

        // add history values
        if (!l_hist.empty()) {
            QoreListNode* hl = new QoreListNode(autoTypeInfo);
            for (dphl_t::const_iterator i = l_hist.begin(), e = l_hist.end(); i != e; ++i) {
                QoreHashNode* h = new QoreHashNode(autoTypeInfo);
                h->setKeyValue("avg_1s", i->avg, 0);
                h->setKeyValue("tp_1s", i->tp, 0);
                hl->push(h, nullptr);
            }
            QoreHashNode* hist = new QoreHashNode(autoTypeInfo);
            hist->setKeyValue("name", name->stringRefSelf(), 0);
            hist->setKeyValue("hist", hl, 0);
            // push history on queue
            q->pushAndTakeRef(hist);
        }

        return qlist.last();
    }

    DLLLOCAL void removeListenerQueue(iterator qi, ExceptionSink* xsink) {
        //printd(5, "PerformanceCache::removeListenerQueue() this: %p '%s'\n", this, name->getBuffer());

        AutoLocker al(m);
        (*qi)->deref(xsink);
        qlist.erase(qi);
    }

    DLLLOCAL void stop(ExceptionSink* xsink) {
        AutoLocker al(m);
        if (!qlist.empty()) {
            for (qlist_t::iterator i = qlist.begin(), e = qlist.end(); i != e; ++i)
                (*i)->deref(xsink);
            qlist.clear();
        }
        running = false;
    }

    DLLLOCAL void post(int64 v) {
        //printd(5, "PerformanceCache::post() this: %p '%s': v: "QLLD"\n", this, name->getBuffer(), v);

        DataPoint p(v);

        AutoLocker al(m);
        if (!running)
            return;

        l_onesec.push(p);

        // adjust global cache values
        sum += v;
        count += 1.0;
    }

    DLLLOCAL void pop(int64 now) {
        // calculate times
        int64 co_onesec = now - 1;

        AutoLocker al(m);
        //printd(5, "PerformanceCache::pop() this: %p '%s': now: "QLLD" qsize: %d\n", this, name->getBuffer(), now, (int)qlist.size());

        // push event on all listener queues if any
        if (!qlist.empty()) {
            QoreHashNode* h = new QoreHashNode(autoTypeInfo);
            h->setKeyValue("name", name->stringRefSelf(), 0);
            double tp;
            double avg = l_onesec.getAverage(tp);
            h->setKeyValue("avg_1s", avg, 0);
            h->setKeyValue("tp_1s", tp, 0);

            //h->setKeyValue("avg_all", new QoreFloatNode(sum / (count ? count : 1)), 0);
            for (qlist_t::iterator i = qlist.begin(), e = qlist.end(); i != e; ++i) {
                if (i != qlist.begin())
                    h->ref();
                (*i)->pushAndTakeRef(h);
            }

            // add history entry
            l_hist.push_back(DataPointHistory(avg, tp));
            if (l_hist.size() > PERFCACHE_HIST_SIZE)
                l_hist.pop_front();
        }

        l_onesec.pop(co_onesec);
    }

    DLLLOCAL const char* getName() const {
        return name->getBuffer();
    }

    DLLLOCAL void mref() const {
        mrc.ROreference();
    }

    DLLLOCAL bool mderef() const {
        return mrc.ROdereference();
    }
};

#endif
