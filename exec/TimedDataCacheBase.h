/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
    TimedDataCacheBase.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

/*
    The timed data cache is a cache with the following properties:
    * data entries are workflow order instance IDs or sync event keys
    * the cache has a global (and dynamic) TTL that applies to all data entries
    * the TTL is based on the entry to the cache; entries are placed in the cache in the order they are submitted
    * any particular data entry may be removed from the cache at any time; the cache must support fast deletion
    * all entries for a particular class (workflow ID) may be removed at any time: the cache must support fast deletion of all entries belonging to a particular class ID
*/

#ifndef _QORUS_TIMED_DATA_CACHE_BASE_H
#define _QORUS_TIMED_DATA_CACHE_BASE_H

#include "CacheEntryBase.h"

#include <string>

template <typename T>
class TimedDataCacheBase : public AbstractPrivateData {
public:
    DLLLOCAL TimedDataCacheBase(QoreObject* n_qorus_options, const char* delay, const char* max = nullptr) :
        qorus_options(n_qorus_options), delay_name(delay), max_name(max ? max : "") {
        qorus_options->ref();
    }

    DLLLOCAL void destructor() {
#ifdef DEBUG
        AutoLocker al(m);
        assert(term);
#endif
    }

    DLLLOCAL void terminate() {
        AutoLocker al(m);

        terminateIntern();
    }

    DLLLOCAL void requeue() {
        AutoLocker al(m);
        cond.signal();
    }

    // returns 0 = OK, -1 = not stored
    DLLLOCAL int set(const T& keyvalue, int64 classid) {
        // get detach-delay option value
        int64 max_size = max_name.empty() ? -1 : getOptionBigInt(max_name.c_str());

        AutoLocker al(m);

        // see if keyvalue is already in the lookup cache
        typename classmap_t::iterator i = classmap.find(classid);

        bool signal = false;

        if (i != classmap.end()) {
            typename keyvaluemap_t::iterator j = i->second.find(keyvalue);
            if (j != i->second.end()) {
                typename cache_t::iterator ci = j->second;
                assert((*ci).classid == classid);
                assert((*ci).equal(keyvalue, keyvalue));

                // signal listener if first element deleted
                if (ci == cache.begin())
                signal = true;

                // remove from cache
                cache.erase(ci);

                // insert in cache and get iterator to new entry
                typename cache_t::iterator nci = cache.insert(cache.end(), CacheEntry(keyvalue, classid));

                // update to new entry
                j->second = nci;

                // do not increment size; removing and inserting an element
            }
            else { // insert in instance lookup cache (2nd level)
                // check if insert can be made
                if (max_size >= 0 && size >= max_size) {
                    printf("TDC ERR: max_size: %d size: %d REJECTING\n", (int)max_size, (int)size);
                    return -1;
                }

                // insert in cache and get iterator to new entry
                typename cache_t::iterator nci = cache.insert(cache.end(), CacheEntry(keyvalue, classid));

                i->second[keyvalue] = nci;

                // there are already elements in the cache, so we do not signal

                // increment size; inserting an element in the list
                ++size;
            }
        }
        else {
            // check if insert can be made
            if (max_size >= 0 && size >= max_size) {
                printf("TDC ERR: max_size: %d size: %d REJECTING\n", (int)max_size, (int)size);
                return -1;
            }

            // insert in cache and get iterator to new entry
            typename cache_t::iterator nci = cache.insert(cache.end(), CacheEntry(keyvalue, classid));

            // insert in both levels of lookup cache
            classmap[classid][keyvalue] = nci;

            // signal listeners if the cache is empty
            if (!size)
                signal = true;

            // increment size; inserting an element in the list
            ++size;
        }

        if (signal)
            cond.signal();

        return 0;
    }

    DLLLOCAL void deleteKey(const T& keyvalue, int64 classid) {
        AutoLocker al(m);

        // see if classid is in the first level of the lookup cache
        typename classmap_t::iterator i = classmap.find(classid);
        if (i == classmap.end()) {
            //printd(5, "TimedDataCache::deleteKey() classid %d not found\n", (int)classid);
            return;
        }

        typename keyvaluemap_t::iterator j = i->second.find(keyvalue);
        if (j == i->second.end()) {
            return;
        }

        typename cache_t::iterator ci = j->second;

        // signal listeners if first element is deleted
        if (ci == cache.begin())
            cond.signal();

        // remove entry from cache
        cache.erase(ci);

        // decremement cache size
        --size;

        // delete from instance lookup
        i->second.erase(j);

        // erase map to second level cache if second level is empty
        if (i->second.empty())
            classmap.erase(i);
    }

    DLLLOCAL QoreListNode* purgeClass(int64 classid) {
        QoreListNode* l = new QoreListNode(autoTypeInfo);

        AutoLocker al(m);
        // see if classid is in the first level of the lookup cache
        typename classmap_t::iterator i = classmap.find(classid);
        if (i == classmap.end())
            return l;

        // flag to signal waiting thread if first element is deleted
        bool signal = false;

        for (typename keyvaluemap_t::iterator j = i->second.begin(), e = i->second.end(); j != e; ++j) {
            l->push(CacheEntry::getValue(j->first), nullptr);

            // signal waiting thread if first element is deleted
            if (!signal && j->second == cache.begin())
                signal = true;

            // erase element from cache
            cache.erase(j->second);

            // decrement cache size
            --size;
        }

        // erase map to second level cache
        classmap.erase(i);

        return l;
    }

    DLLLOCAL QoreHashNode* getEvent() {
        AutoLocker al(m);

        while (true) {
            if (term) {
                break;
            }

            // if the cache is empty, then wait for an event
            if (cache.empty()) {
                cond.wait(m);
                continue;
            }

            // check the first cache entry
            CacheEntry& ce = *(cache.begin());

            // get detach-delay option value
            int64 detach_delay = getOptionBigInt(delay_name.c_str());

            time_t now = time(0);

            int64 diff = ce.time + detach_delay - now;
            if (diff > 0) {
                cond.wait(m, diff * 1000);
                continue;
            }

            // got an event, remove from queue
            typename classmap_t::iterator i = classmap.find(ce.classid);
            assert(i != classmap.end());

            // get pointer to second-level cache
            typename keyvaluemap_t::iterator j = i->second.find(ce.keyvalue);
            assert(j != i->second.end());

            // erase from second level cache
            i->second.erase(j);

            // if second level cache is empty, then erase the classid from top-level hash
            if (i->second.empty())
                classmap.erase(i);

            // get return value
            QoreHashNode* rv = ce.getHash();

            // erase from cache
            cache.erase(cache.begin());

            // decrement size
            --size;

            // return hash
            return rv;
        }

        return nullptr;
    }

    DLLLOCAL QoreStringNode* toString() {
        QoreStringNode* str = new QoreStringNode;

        str->sprintf("size: %d", size);

        for (typename classmap_t::iterator i = classmap.begin(), e = classmap.end(); i != e; ++i) {
            str->sprintf("\nclassid: %lld size: %d [", i->first, i->second.size());

            for (typename keyvaluemap_t::iterator j = i->second.begin(), je = i->second.end(); j != je; ++j) {
                if (j != i->second.begin()) {
                    str->concat(", ");
                }
                DateTime d;
                d.setDate(currentTZ(), (*(j->second)).time, 0);
                str->concat("{time=");
                d.format(*str, "YYYY-MM-DD HH:mm:SS");
                str->concat(", ");
                (*(j->second)).addKeyValue(*str);
                str->concat('}');
            }

            str->concat(']');
        }

        return str;
    }

    DLLLOCAL QoreStringNode* getSummary() {
        QoreStringNode* str = new QoreStringNode;

        str->sprintf("size: %d", size);
        for (typename classmap_t::iterator i = classmap.begin(), e = classmap.end(); i != e; ++i) {
            str->sprintf(", %s: %d size: %d", CacheEntry::getClassName(), i->first, i->second.size());
        }

        return str;
    }

    using AbstractPrivateData::deref;
    DLLLOCAL virtual void deref(ExceptionSink* xsink) {
        if (QoreReferenceCounter::ROdereference()) {
            qorus_options->deref(xsink);
            delete this;
        }
    }

protected:
    DLLLOCAL int64 getOptionBigInt(const char* opt) const {
        ValueHolder h(qorus_options->getReferencedMemberNoMethod("opts", nullptr), nullptr);
        if (h) {
            bool found;
            return h->get<QoreHashNode>()->getKeyAsBigInt(opt, found);
        }
        return 0;
    }

    DLLLOCAL void terminateIntern() {
#ifdef DEBUG
        if (size) {
            QoreStringNode* str = toString();
            printd(0, "ERROR: TimedDataCache(): %s\n", str->getBuffer());
            str->deref();
        }
#endif
        assert(!size);

        term = true;
        cond.signal();
    }

    typedef CacheEntryBase<T> CacheEntry;
    typedef std::list<CacheEntry> cache_t;
    cache_t cache;

    // map from key values to cache entries
    typedef std::map<T, typename cache_t::iterator> keyvaluemap_t;
    // map from class IDs to keyvalue maps
    typedef std::map<int, keyvaluemap_t> classmap_t;

    // master class to keyvalue to cache entry map
    classmap_t classmap;

    // Condition variable
    QoreCondition cond;

    // mutex
    QoreThreadLock m;

    // termination flag
    bool term = false;

    // current cache size
    int size = 0;

    // Qorus system options object
    QoreObject* qorus_options;

    // option names
    std::string delay_name, max_name;
};

#endif
