# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args
%enable-all-warnings

# this data structure will ensure that threads blocked on atomic actions are signaled in order
hashdecl ActionStatusInfo {
    # true if an operation is in progress
    bool block = True;

    # TID of the thread holding the lock
    int tid;

    # lock cound for tid so the lock can be held recursively
    int count = 1;

    # hash of threads waiting on the operation; TID -> Condition
    /** because hashes maintain insertion order, this hash will be used to ensure that blocked threads are signaled
        in the order that they arrive
    */
    hash<string, Condition> cond_hash();

%ifdef QorusDebugInternals
    # to trace the original TID
    int orig_tid;

    # to trace where and how the block was acquired
    *list<auto> stack;
%endif
}

class AtomicClassActionHelper {
    public {
        const C_Workflow = "wf";
        const C_Service = "svc";
        const C_Job = "job";
    }

    private {
        # global mutex shared by all actions
        static RWLock rwl;

        # status hash: class -> id -> action status info hash
        static hash<string, hash<string, hash<ActionStatusInfo>>> status_hash();

        # failure hash: class -> id -> True
        hash<string, hash<string, bool>> failure_hash;
    }

    # check failure hash
    bool check(string cls, softstring id) {
        # ensure that the given object was locked
        QDBG_ASSERT(isLocked(cls, id));
        return failure_hash{cls}{id} ?? False;
    }

    # add to failure hash
    add(string cls, softstring id) {
        # ensure that the given object was locked
        QDBG_ASSERT(status_hash{cls}{id});
        # ensure that we only set the failure flag once
        QDBG_ASSERT(!failure_hash{cls}{id});
        failure_hash{cls}{id} = True;
    }

    doBackgroundWorkflowsArgs(softlist<string> ids, code call, *softlist<auto> args) {
        doBackgroundIntern(call, C_Workflow, ids, args);
    }

    doBackgroundWorkflows(softlist<string> ids, code call) {
        doBackgroundIntern(call, C_Workflow, ids, argv);
    }

    doBackgroundServices(softlist<string> ids, code call) {
        doBackgroundIntern(call, C_Service, ids, argv);
    }

    doBackgroundJobs(softlist<string> ids, code call) {
        doBackgroundIntern(call, C_Job, ids, argv);
    }

    doBackgroundWorkflow(string id, code call) {
        doBackgroundIntern(call, C_Workflow, id, argv);
    }

    doBackgroundService(string id, code call) {
        doBackgroundIntern(call, C_Service, id, argv);
    }

    doBackgroundJob(string id, code call) {
        doBackgroundIntern(call, C_Job, id, argv);
    }

    #! handoff lock to another thread
    private:internal doBackgroundIntern(code call, string cls, softlist<string> ids, *list<auto> args) {
        int orig_tid = gettid();
        # issue #3302: do not return until the lock has been handed over in the background thread
        Counter sync(1);
        int new_tid = background doBackgroundIntern(sync, orig_tid, cls, ids, call, args);
        #QDBG_LOG("doBackgroundIntern() PARENT cls: %y ids: %y new_tid: %y STACK: %N", cls, ids, new_tid, get_stack());
        sync.waitForZero();
    }

    #! hands off the lock to another thread
    private:internal doBackgroundIntern(Counter sync, int orig_tid, string cls, softlist<string> ids, code call, *list<auto> args) {
        QDBG_ASSERT(orig_tid != gettid());
        QDBG_LOG("doBackgroundIntern() orig_tid: %y cls: %y id: %y", orig_tid, cls, ids);
        try {
            {
                # issue #3302: signal calling thread to continue
                on_exit sync.dec();

                doLockHandoverIntern(orig_tid, cls, ids);
            }
            call_function_args(call, args);
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, "error in atomic handoff: %s", get_exception_string(ex));
        }
    }

    #! perform lock handover in hew thread
    private abstract doLockHandoverIntern(int orig_tid, string cls, softlist<string> ids);

    # returns true if the current thread owns the lock
    static bool ownsLock(string cls, softstring id) {
        return status_hash{cls}{id}.tid == gettid();
    }

    static string getDebugInfo() {
        return sprintf("AtomicClassActionHelper: %N", status_hash);
    }

    static bool isLocked(string cls, softstring id) {
        return exists status_hash{cls}{id};
    }

    static setLock(RWLock rwl) {
        AtomicClassActionHelper::rwl = rwl;
    }

    # must have the lock already acquired; returns True if the given class and ID were blocked in which case the call also waits for them to become unblocked; returns False if they were not blocked and no waiting was performed
    private static bool checkBlockedIntern(string cls, string id) {
        int tid = gettid();

        # return False if the lock is not acquired or has already been acquired by this thread
        if (!status_hash{cls}{id}.block || status_hash{cls}{id}.tid == tid) {
            return False;
        }

        QDBG_LOG("AtomicClassActionHelper::checkBlockedIntern() waiting for %y.%y (CONTENTION)", cls, id);

        # NOTE: the condition var may exist already from another loop of the same check in the same lock
        *Condition cond;
        if (!(cond = status_hash{cls}{id}.cond_hash{tid})) {
            cond = status_hash{cls}{id}.cond_hash{tid} = new Condition();
        }
        cond.wait(rwl);
        return True;
    }

    # must have the lock already acquired
    private static releaseIntern(string cls, string id) {
        QDBG_ASSERT(rwl.lockOwner());
        QDBG_ASSERT(status_hash{cls}{id}.block);
        QDBG_ASSERT(status_hash{cls}{id}.count);

        if (!--status_hash{cls}{id}.count) {
            # if there are any blocked threads, signal the first thread that blocked
            if (status_hash{cls}{id}.cond_hash) {
                status_hash{cls}{id} += {
                    "tid": 0,
                    "block": False,
%ifdef QorusDebugInternals
                    "stack": NOTHING,
%endif
                };
                # wait up the first thread blocked
                string next_tid = status_hash{cls}{id}.cond_hash.firstKey();
                Condition cond = remove status_hash{cls}{id}.cond_hash{next_tid};
                QDBG_LOG("AtomicClassActionHelper::releaseIntern() releasing %y.%y (CONTENTION); waking TID %d (remaining: %y)", cls, id, next_tid, (map $1.toInt(), keys status_hash{cls}{id}.cond_hash));
                cond.signal();
            } else {
                QDBG_LOG("AtomicClassActionHelper::releaseIntern() releasing %y.%y", cls, id);
                remove status_hash{cls}{id};
                # remove the class if there are no more ID structures
                if (!status_hash{cls}) {
                    remove status_hash{cls};
                }
            }
        }
    }

    private static blockIntern(string cls, string id, int tid = gettid()) {
        if (!status_hash{cls}{id}) {
            status_hash{cls}{id} = <ActionStatusInfo>{"tid": tid};
        } else if (!status_hash{cls}{id}.count) {
            QDBG_ASSERT(!status_hash{cls}{id}.block);
            QDBG_ASSERT(!status_hash{cls}{id}.tid);
            status_hash{cls}{id} += {
                "block": True,
                "tid": tid,
                "count": 1,
            };
        } else {
            QDBG_ASSERT(status_hash{cls}{id}.block);
%ifdef QorusDebugInternals
            if (status_hash{cls}{id}.tid != tid) {
                throw "STATUS-ERROR", sprintf("AtomicClassActionHelper::blockIntern() cls: %y id: %y tid: %d status_hash: %N", cls, id, tid, status_hash);
            }
%endif
            QDBG_ASSERT(status_hash{cls}{id}.tid == tid);
            ++status_hash{cls}{id}.count;
        }

        QDBG_LOG("AtomicClassActionHelper::blockIntern() blocked %y.%y (%y)", cls, id, status_hash{cls}{id});

%ifdef QorusDebugInternals
        if (status_hash{cls}{id}.stack) {
            status_hash{cls}{id}.stack = get_stack();
        }
%endif
    }
}

# this class ensures atomicity for actions of multiple classes (types) and IDs
/** concurrent requests for the same ID will block in the constructor until the
    action has completed (the destructor releases the lock and wakes a single
    waiting thread)

    can be destroyed in the background
*/
class AtomicMultiClassActionHelper inherits AtomicClassActionHelper {
    private:internal {
        # cls -> ID -> True
        *hash<string, hash<string, bool>> atomic_flag_hash;
    }

    constructor(*softlist<softstring> wf_ids, *softlist<softstring> svc_ids, *softlist<softstring> job_ids) {
        hash<string, hash<string, bool>> atomic_flag_hash;
        if (wf_ids) {
            atomic_flag_hash{AtomicClassActionHelper::C_Workflow} = map {$1: True}, wf_ids;
        }
        if (svc_ids) {
            atomic_flag_hash{AtomicClassActionHelper::C_Service} = map {$1: True}, svc_ids;
        }
        if (job_ids) {
            atomic_flag_hash{AtomicClassActionHelper::C_Job} = map {$1: True}, job_ids;
        }
        init(atomic_flag_hash);
    }

    constructor(*hash<string, hash<string, bool>> atomic_flag_hash) {
        init(atomic_flag_hash);
    }

    destructor() {
        bool lck = !rwl.writeLockOwner();
        if (lck) rwl.writeLock();
        on_exit if (lck) rwl.writeUnlock();

        # iterate all classes; i.key = class string, i.value = hash of IDs for the class
        foreach hash<auto> i in (atomic_flag_hash.pairIterator()) {
            # release all IDs in the class
            map releaseIntern(i.key, $1), keys i.value;
        }
    }

    private init(*hash<string, hash<string, bool>> atomic_flag_hash) {
        self.atomic_flag_hash = atomic_flag_hash;

        bool lck = !rwl.writeLockOwner();
        if (lck) rwl.writeLock();
        on_exit if (lck) rwl.writeUnlock();

        # wait until all conditions are satisfied at the same time
        while (True) {
            bool blocked;
            foreach string cls in (keys atomic_flag_hash) {
                foreach string id in (keys atomic_flag_hash{cls}) {
                    if (blocked = checkBlockedIntern(cls, id)) {
                        break;
                    }
                }
            }
            if (blocked) {
                continue;
            }
            break;
        }

        # mark all classes and IDs as blocked
        # iterate all classes; i.key = class string, i.value = hash of IDs for the class
        int tid = gettid();
        foreach hash<auto> i in (atomic_flag_hash.pairIterator()) {
            # mark all IDs as blocked
            map blockIntern(i.key, $1, tid), keys i.value;
        }
    }

    #! perform lock handover in the new thread
    private doLockHandoverIntern(int orig_tid, string cls, softlist<string> ids) {
        int tid = gettid();
%ifdef QorusDebugInternal
        on_exit QDBG_LOG("handover done (orig tid %d)", orig_tid);
        QDBG_ASSERT(tid != orig_tid);
%endif

        QDBG_ASSERT(ids);

        foreach string id in (ids) {
            if (atomic_flag_hash{cls}{id}) {
                QDBG_ASSERT(status_hash{cls}{id}.tid == orig_tid);
                status_hash{cls}{id}.tid = tid;
            }
        }
%ifdef DISABLED
        if (!ids) {
%ifdef QorusDebugInternal
            map QDBG_ASSERT(status_hash{cls}{$1}.tid == orig_tid), keys atomic_flag_hash{cls};
%endif
            map status_hash{cls}{$1}.tid = tid, keys atomic_flag_hash{cls};
        }
%endif
    }
}

# this class ensures atomicity for actions of a specific class (type) and ID
/** concurrent requests for the same ID will block in the constructor until the
    action has completed (the destructor releases the lock and wakes a single
    waiting thread)
*/
class AtomicSingleClassActionHelper inherits AtomicClassActionHelper {
    private:internal {
        string cls;
        string id;
    }

    constructor(string cls, softstring id) {
        self.cls = cls;
        self.id = id;

        bool lck = !rwl.writeLockOwner();
        if (lck) rwl.writeLock();
        on_exit if (lck) rwl.writeUnlock();

        while (AtomicClassActionHelper::checkBlockedIntern(cls, id)) {}

        blockIntern(cls, id);
    }

    destructor() {
        bool lck = !rwl.writeLockOwner();
        if (lck) rwl.writeLock();
        on_exit if (lck) rwl.writeUnlock();

        AtomicClassActionHelper::releaseIntern(cls, id);
    }

    #! perform lock handover in new thread
    private doLockHandoverIntern(int orig_tid, string cls, softlist<string> ids) {
        #QDBG_LOG("doLockHandoverIntern() orig_tid: %d cls: %y id: %y self.cls: %y self.id: %y", orig_tid, cls, id, self.cls, self.id);
        #if (!status_hash{cls}{id})
%ifdef QorusDebugInternals
        on_exit QDBG_LOG("handover done (orig tid %d)", orig_tid);
        QDBG_ASSERT(cls == self.cls);
        QDBG_ASSERT(!ids || ((ids.size() == 1) && ids[0] == id));
        QDBG_ASSERT(gettid() != orig_tid);
        QDBG_ASSERT(status_hash{cls}{id}.tid == orig_tid);
        # NOTE: locks may be handed over more than once
        status_hash{cls}{id}.orig_tid = status_hash{cls}{id}.tid;
%endif
        status_hash{cls}{id}.tid = gettid();
    }
}

# this class ensure atomicity for workflow actions
class AtomicWorkflowActionHelper inherits AtomicSingleClassActionHelper {
    constructor(softstring id) : AtomicSingleClassActionHelper(C_Workflow, id) {
    }
}

# this class ensure atomicity for service actions
class AtomicServiceActionHelper inherits AtomicSingleClassActionHelper {
    constructor(softstring id) : AtomicSingleClassActionHelper(C_Service, id) {
    }
}

# this class ensure atomicity for job actions
class AtomicJobActionHelper inherits AtomicSingleClassActionHelper {
    constructor(softstring id) : AtomicSingleClassActionHelper(C_Job, id) {
    }
}
