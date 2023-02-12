/* -*- indent-tabs-mode: nil -*- */
/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

#include "PerformanceCache.h"

// defines the cycle time for cache updates: default 1 second (1000 ms)
#define QORUS_PC_HZ 1000

void PerformanceCacheManager::run() {
   while (!stop) {
      AutoLocker al(m);
      cevent.wait(m, QORUS_PC_HZ);
      if (stop)
	 break;

      int64 now = q_epoch();
      //printd(5, "PerformanceCacheManager::run() now: "QLLD" empty: %d\n", now, (int)pcmap.size());
      for (pcmap_t::iterator i = pcmap.begin(), e = pcmap.end(); i != e; ++i)
	 i->second->pop(now);
   }

   AutoLocker al(m);
   running = false;
   cstop.signal();
}

namespace {
   extern "C" void* pcache_man_run(void* arg) {
      PerformanceCacheManager* pcm = (PerformanceCacheManager*)arg;
      pcm->run();
      pthread_exit(0);
      return 0;
   }
}

int PerformanceCacheManager::start(ExceptionSink* xsink) {
   assert(!stop);
   assert(!running);

   pthread_t ptid;

   running = true;

   int rc = pthread_create(&ptid, 0, pcache_man_run, this);
   if (rc) {
      running = false;
      xsink->raiseErrnoException("PERFORMANCECACHEMANAGER-THREAD-ERROR", rc, "could not create performance cache manager timer thread: pthread_create() failed");
      return -1;
   }

   return 0;
}

void PerformanceCacheManager::shutdown(ExceptionSink* xsink) {
   stop = true;

   AutoLocker al(m);

   for (pcmap_t::iterator i = pcmap.begin(), e = pcmap.end(); i != e; ++i) {
      i->second->stop(xsink);
      i->second->deref();
   }

   pcmap.clear();

   cevent.signal();
   while (running)
      cstop.wait(m);
}

PerformanceCache* PerformanceCacheManager::add(const QoreStringNode* name) {
   PerformanceCache* pc = 0;
   AutoLocker al(m);

   iterator i = pcmap.lower_bound(name->getBuffer());
   if (i == pcmap.end() || strcmp(name->getBuffer(), i->second->getName())) {
      // the following PerformanceCache reference is for the object
      pc = new PerformanceCache(name);
      pc->setIndex(pcmap.insert(i, pcmap_t::value_type(pc->getName(), pc)));

      // the following performance cache reference is for the cache manager
      pc->ref();
   }
   else {
      pc = i->second;
      // the following PerformanceCache reference is for the object
      pc->ref();
      // add count
      pc->mref();
   }


   return pc;
}

void PerformanceCacheManager::del(PerformanceCache* pc, ExceptionSink* xsink) {
   {
      AutoLocker al(m);

      // if the add count is zero, then stop and remove from the cache
      if (pc->mderef()) {
	 pc->stop(xsink);
	 pcmap.erase(pc->getIndex());
	 pc->deref(xsink);
      }
   }
}
