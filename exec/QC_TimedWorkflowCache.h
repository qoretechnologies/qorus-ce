/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
    QC_TimedWorkflowCache.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#ifndef _QORUS_QC_TIMED_WORKFLOW_CACHE
#define _QORUS_QC_TIMED_WORKFLOW_CACHE

#include <qore/Qore.h>

#include "TimedDataCacheBase.h"

DLLEXPORT extern qore_classid_t CID_TIMEDWORKFLOWCACHE;

DLLLOCAL extern QoreClass* QC_TIMEDWORKFLOWCACHE;
DLLLOCAL QoreClass* initTimedWorkflowCacheClass(QoreNamespace& ns);

#endif
