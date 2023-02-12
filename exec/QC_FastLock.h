/* -*- mode: c++; indent-tabs-mode: nil -*- */
/*
 QC_FastLock.h
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

/*
 fast, unsafe lock, does not participate in deadlock detection
*/

#ifndef _QORUS_FASTLOCK

#define _QORUS_FASTLOCK

DLLEXPORT extern qore_classid_t CID_FASTLOCK;

DLLLOCAL class QoreClass *initFastLockClass();

class FastLock : public AbstractPrivateData, public QoreThreadLock {
public:
   DLLLOCAL FastLock() {
   }
   DLLLOCAL ~FastLock() {
   }
};

#endif

