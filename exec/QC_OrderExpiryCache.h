/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
    QC_OrderExpiryCache.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

/*
    The order expiry cache is a cache with the following properties:
    * data entries are workflow order instance IDs with their created time
    * the cache has workflow-specific TTLs that apply to all data entries of its class (= workflowid)
    * the TTL is based on the entry to the cache; entries are placed in each cache in the order they are submitted
    * any particular data entry may be removed from the cache at any time; the cache must support fast deletion
    * all entries for a particular class (workflow ID) may be requeued at any time: the cache must support
      fast requeuing of all entries belonging to a particular class ID
*/

#ifndef _QORUS_ORDER_EXPIRY_CACHE_H
#define _QORUS_ORDER_EXPIRY_CACHE_H

// default SLA threshold is 30 minutes
#define DEFAULT_SLA_THRESHOLD 1800

#include <deque>
#include <map>

#include <inttypes.h>

class OrderExpiryCache : public AbstractPrivateData {
public:
    DLLLOCAL void queueOrder(int64 wfid, int64 wfiid, int64 created) {
        AutoLocker al(lck);

        queueOrderUnlocked(wfid, wfiid, created);
    }

    // wf_slas is a hash keyed by wfid -> (int) sla threshold in seconds
    // returns as *hash<string, int> of wfid -> count
    DLLLOCAL QoreHashNode* getEvents(const QoreHashNode* wf_slas, int64 delay) {
        int64 now = q_epoch();

        ReferenceHolder<QoreHashNode> rv(nullptr);

        AutoLocker al(lck);

        // iterate through all workflow maps
        for (cache_t::iterator i = cache.begin(), e = cache.end(); i != e;) {
            int64 wfid = i->first;

            // get expiry in seconds
            int64 seconds;
            if (wf_slas) {
                QoreStringMaker wf_str(QLLD, wfid);
                seconds = wf_slas->getKeyValue(wf_str.c_str()).getAsBigInt();
                //printd(5, "getEvents() wfid: %d ('%s' wf_sla size: %d) seconds: %d\n", static_cast<int>(wfid), wf_str.c_str(), static_cast<int>(wf_slas->size()), static_cast<int>(seconds));
                if (!seconds) {
                    seconds = DEFAULT_SLA_THRESHOLD;
                }
            }
            else {
                seconds = DEFAULT_SLA_THRESHOLD;
                //printd(5, "getEvents() wfid: %d wf_slas empty\n", static_cast<int>(wfid));
            }
            // add a buffer to address race conditions
            seconds += delay;

            size_t offset = 0;
            while (true) {
                /*
                printd(5, "getEvents() wfid: %d seconds: %d offset: %d now: %d size: %d entry: %d (%d)\n",
                    static_cast<int>(wfid), static_cast<int>(seconds), static_cast<int>(offset),
                    static_cast<int>(now), static_cast<int>(i->second.size()), offset != i->second.size() ? i->second[offset].second : 0,
                    offset != i->second.size() ? now - i->second[offset].second : 0);
                */
                if (offset == i->second.size()
                    || ((now - i->second[offset].second) < seconds)) {
                    break;
                }

                ++offset;
            }
            if (offset) {
                // first write result to hash
                if (!rv) {
                    rv = new QoreHashNode(bigIntTypeInfo);
                }

                QoreStringMaker wfid_str(QLLD, wfid);
                rv->setKeyValue(wfid_str.c_str(), offset, nullptr);

                // remove entries from list
                i->second.erase(i->second.begin(), i->second.begin() + offset);
                // remove workflow from map if there are no more entries
                if (i->second.empty()) {
                    cache_t::iterator j = i;
                    ++i;
                    cache.erase(j);
                    continue;
                }
            }
            ++i;
        }

        return rv.release();
    }

    // returns 0 = deleted, -1 = not found
    int removeOrder(int64 wfid, int64 wfiid) {
        AutoLocker al(lck);

        cache_t::iterator i = cache.find(wfid);
        if (i == cache.end()) {
            return 0;
        }

        // we do a linear search here
        for (order_vec_t::iterator oi = i->second.begin(), oe = i->second.end(); oi != oe; ++oi) {
            if (oi->first == wfiid) {
                i->second.erase(oi);
                return 0;
            }
        }

        return -1;
    }

    DLLLOCAL QoreStringNode* getSummary() const {
        QoreStringNode* str = new QoreStringNode("[");

        AutoLocker al(lck);

        for (auto& i : cache) {
            str->sprintf("wfid %d: size: %d, ", static_cast<int>(i.first), static_cast<int>(i.second.size()));
        }

        if (str->size() > 1) {
            str->terminate(str->size() - 2);
        }

        str->concat(']');

        return str;
    }

    DLLLOCAL QoreStringNode* getDetails() const {
        QoreStringNode* str = new QoreStringNode("[");

        AutoLocker al(lck);

        for (auto& i : cache) {
            str->sprintf("wfid %d: size: %d: [", static_cast<int>(i.first), static_cast<int>(i.second.size()));
            for (auto& wi : i.second) {
                str->sprintf("wfid: " QLLD " created: " QLLD ", ", wi.first, wi.second);
            }
            if (i.second.size()) {
                str->terminate(str->size() - 2);
            }
            str->concat("], ");
        }

        if (str->size() > 1) {
            str->terminate(str->size() - 2);
        }

        str->concat(']');

        return str;
    }

protected:
    DLLLOCAL void queueOrderUnlocked(int64 wfid, int64 wfiid, int64 created) {
        //printd(5, "queueOrderUnlocked() wfid: %d wfiid: %d created: %d\n", static_cast<int>(wfid), static_cast<int>(wfiid), static_cast<int>(created));
        cache_t::iterator i = cache.find(wfid);
        if (i == cache.end()) {
            i = cache.insert(cache_t::value_type(wfid, order_vec_t())).first;
        }

        // orders should be placed roughly in order - check for not more than 30 seconds before than the last entry
        assert(i->second.empty() || (i->second.back().second < created) || ((i->second.back().second - created) < 30));
        i->second.push_back(order_vec_t::value_type(wfiid, created));
    }

    // list of orders for a particular workflow tagged with creation time; values are <wfiid, creation time>
    /** reasons for a deque:
        * very fast iteration
        * very efficient memory usage
        * constant time insertions at the end
        * constant time removals from the beginning
    */
    typedef std::deque<std::pair<int64, int64>> order_vec_t;
    // each wf order cache is keyed by its wfid
    typedef std::map<int64, order_vec_t> cache_t;
    cache_t cache;

    // mutex for cache access
    mutable QoreThreadLock lck;
};

DLLLOCAL extern qore_classid_t CID_TIMEDWORKFLOWCACHE;
DLLLOCAL QoreClass* initOrderExpiryCacheClass(QoreNamespace& ns);

#endif

