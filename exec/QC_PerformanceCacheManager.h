/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
  QC_PerformanceCacheManager.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

#ifndef _QORUS_PERFORMANCECACHEMANAGER_H
#define _QORUS_PERFORMANCECACHEMANAGER_H

#include <qore/Qore.h>

#include "PerformanceCache.h"

DLLEXPORT extern qore_classid_t CID_PERFORMANCECACHEMANAGER;
DLLLOCAL extern QoreClass* QC_PERFORMANCECACHEMANAGER;
DLLLOCAL QoreClass* initPerformanceCacheManagerClass(QoreNamespace& ns);

#endif
