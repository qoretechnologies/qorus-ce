/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
    CacheEntryBase.h
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
    * all entries for a particular class (workflow ID) may be removed at any time: the cache must support
      fast deletion of all entries belonging to a particular class ID
*/

#ifndef _QORUS_CACHE_ENTRY_BASE_H
#define _QORUS_CACHE_ENTRY_BASE_H

#include <chrono>

template <typename T>
class CacheEntryBase {
public:
    // epoch time (zulu) entry submitted to the cache
    std::time_t time = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());

    // key value
    T keyvalue;

    // class ID
    int64 classid;

    DLLLOCAL CacheEntryBase(const T& n_keyvalue, int64 n_classid) : keyvalue(n_keyvalue), classid(n_classid) {
    }

    DLLLOCAL QoreHashNode* getHash() const {
        QoreHashNode* h = new QoreHashNode(autoTypeInfo);

        h->setKeyValue(getClassName(), classid, 0);
        h->setKeyValue(getKeyName(), getValue(keyvalue), 0);

        return h;
    }

    DLLLOCAL static bool equal(const T& v1, const T& v2) {
        return v1 == v2;
    }

    // implemented with template specialization
    DLLLOCAL void addKeyValue(QoreString& str) const;

    // implemented with template specialization
    DLLLOCAL static const char* getClassName();

    // implemented with template specialization
    DLLLOCAL static const char* getKeyName();

    // implemented with template specialization
    DLLLOCAL static QoreValue getValue(const T& v);
};

// template specializations
template <>
DLLLOCAL inline const char* CacheEntryBase<std::string>::getClassName() {
   return "eventtype";
}

template <>
DLLLOCAL inline const char* CacheEntryBase<std::string>::getKeyName() {
   return "eventkey";
}

template<>
DLLLOCAL inline QoreValue CacheEntryBase<std::string>::getValue(const std::string& str) {
   return new QoreStringNode(str);
}

template<>
DLLLOCAL inline void CacheEntryBase<std::string>::addKeyValue(QoreString& str) const {
   str.sprintf("%s: %s", getKeyName(), keyvalue.c_str());
}

template <>
DLLLOCAL inline const char* CacheEntryBase<int64>::getClassName() {
   return "wfid";
}

template <>
DLLLOCAL inline const char* CacheEntryBase<int64>::getKeyName() {
   return "wfiid";
}

template<>
DLLLOCAL inline QoreValue CacheEntryBase<int64>::getValue(const int64& v) {
   return v;
}

template<>
DLLLOCAL inline void CacheEntryBase<int64>::addKeyValue(QoreString& str) const {
   str.sprintf("%s: " QLLD, getKeyName(), keyvalue);
}

#endif