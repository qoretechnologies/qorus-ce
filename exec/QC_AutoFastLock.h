/*
 QC_AutoFastLock.h

 Qorus Integration Engine
*/

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#ifndef _QORE_QC_AUTOFASTLOCK_H

#define _QORE_QC_AUTOFASTLOCK_H

#include <qore/Qore.h>

#include "QC_FastLock.h"

DLLEXPORT extern qore_classid_t CID_AUTOFASTLOCK;

DLLLOCAL class QoreClass *initAutoFastLockClass();

class QoreAutoFastLock : public AbstractPrivateData {
      class FastLock *m;
      bool locked;

   public:
      DLLLOCAL QoreAutoFastLock(class FastLock *mt) : m(mt), locked(true) {
	 m->lock();
      }

      using AbstractPrivateData::deref;
      DLLLOCAL virtual void deref(class ExceptionSink *xsink) {
	 if (ROdereference()) {
	    m->deref(xsink);
	    delete this;
	 }
      }

      DLLLOCAL virtual void destructor(class ExceptionSink *xsink) {
	 if (locked)
	    m->unlock();
      }

      DLLLOCAL void lock() {
	 m->lock();
	 locked = true;
      }
      DLLLOCAL void unlock() {
	 locked = false;
	 m->unlock();
      }
      DLLLOCAL int trylock() {
	 int rc = m->trylock();
	 if (!rc)
	    locked = true;
	 return rc;
      }
};

#endif
