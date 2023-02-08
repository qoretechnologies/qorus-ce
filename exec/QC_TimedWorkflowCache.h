/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
    QC_TimedWorkflowCache.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

#ifndef _QORUS_QC_TIMED_WORKFLOW_CACHE
#define _QORUS_QC_TIMED_WORKFLOW_CACHE

#include <qore/Qore.h>

#include "TimedDataCacheBase.h"

DLLEXPORT extern qore_classid_t CID_TIMEDWORKFLOWCACHE;

DLLLOCAL extern QoreClass* QC_TIMEDWORKFLOWCACHE;
DLLLOCAL QoreClass* initTimedWorkflowCacheClass(QoreNamespace& ns);

#endif
