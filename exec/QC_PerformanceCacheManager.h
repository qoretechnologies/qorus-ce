/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
  QC_PerformanceCacheManager.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#ifndef _QORUS_PERFORMANCECACHEMANAGER_H
#define _QORUS_PERFORMANCECACHEMANAGER_H

#include <qore/Qore.h>

#include "PerformanceCache.h"

DLLEXPORT extern qore_classid_t CID_PERFORMANCECACHEMANAGER;
DLLLOCAL extern QoreClass* QC_PERFORMANCECACHEMANAGER;
DLLLOCAL QoreClass* initPerformanceCacheManagerClass(QoreNamespace& ns);

#endif
