/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
  QC_PerformanceCache.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#ifndef _QORUS_PERFORMANCECACHE_H
#define _QORUS_PERFORMANCECACHE_H

#include <qore/Qore.h>

#include "PerformanceCache.h"

DLLEXPORT extern qore_classid_t CID_PERFORMANCECACHE;
DLLLOCAL extern QoreClass* QC_PERFORMANCECACHE;
DLLLOCAL QoreClass* initPerformanceCacheClass(QoreNamespace& ns);

#endif
