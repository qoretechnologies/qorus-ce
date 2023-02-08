/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
    QC_TimedSyncCache.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

#ifndef _QORUS_QC_TIMED_SYNC_CACHE
#define _QORUS_QC_TIMED_SYNC_CACHE

#include <qore/Qore.h>

#include "TimedDataCacheBase.h"

class TimedSyncCache : public TimedDataCacheBase<std::string> {
public:
    DLLLOCAL TimedSyncCache(QoreObject* n_qorus_options, const char* delay) : TimedDataCacheBase<std::string>(n_qorus_options, delay) {
    }

    DLLLOCAL void terminate() {
        AutoLocker al(m);

        cache.clear();
        classmap.clear();
        size = 0;

        terminateIntern();
    }
};

DLLEXPORT extern qore_classid_t CID_TIMEDSYNCCACHE;

DLLLOCAL extern QoreClass* QC_TIMEDSYNCCACHE;
DLLLOCAL QoreClass* initTimedSyncCacheClass(QoreNamespace& ns);

#endif
