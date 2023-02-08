# -*- mode: qore; indent-tabs-mode: nil -*-
# service cache classes
#
# method calls and service deletions when services
# are in transition states are covered

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace OMQ;

#! holds services
class OMQ::ServiceTypeHolder {
    public {
        hash<string, AbstractQorusCoreService> system;
        hash<string, AbstractQorusCoreService> user;
    }
}

class OMQ::QorusServiceHash {
    public {
        ServiceGate system("system");
        ServiceGate user("user");
    }
}

class OMQ::SvcSignaler {
    private {
        Mutex m();
        Condition c();
        bool detached = False;
    }

    bool wait(timeout to) {
        m.lock();
        on_exit m.unlock();
        if (c.wait(m, to))
            detached = True;
        return !detached;
    }

    bool signal() {
        m.lock();
        on_exit m.unlock();
        c.signal();
        return detached;
    }
}

hashdecl ServiceAccess {
    Condition c();
    # number of waiting threads for the read lock
    int read_waiting = 0;
    # number of waiting threads for the exclusive lock
    int write_waiting = 0;
    # TID of thread with exclusive access
    int exclusive = 0;
    # if the exclusive lock is for service unloading / resetting
    *bool unload;
    # number of threads currently reading the object
    int in_read = 0;
    # TID of thread that can reaquire the exclusive lock
    int exclusive_pending = 0;
    # key for exclusive access
    *string exclusive_key;
%ifdef QorusDebugInternals
    # read lock debugging, TID -> cnt
    hash<string, int> rh;
%endif
}

#! internal listener map record
hashdecl OMQ::ServiceListenerInfo {
    #! reference count
    int refs = 1;
    #! service
    AbstractQorusCoreService svc;
    #! allow other services to bind handlers to the same listener
    bool allow_listener_sharing;
}

class OMQ::ServiceManager inherits Mutex {
    private {
        bool shutting_down = False;
        OMQ::ServiceTypeHolder services();
        date updated = now_us();

        # initialization Counter
        Counter init(1);

        # service counter
        Counter sc();

        # atomic service access hash structure: type(lwr) -> name -> hash<ServiceAccess>
        hash<string, hash<string, hash<ServiceAccess>>> sah;

        # user http service hash
        hash<string, AbstractServiceHttpHandler> user_http_hash;

        # UI extension service map; unique resource name -> resource
        hash<string, QorusUiExtensionResource> ui_extension_resource_map;

        #! UI extension menu map; group -> menu -> resource name -> resource
        hash<string, hash<string, hash<string, QorusUiExtensionResource>>> ui_extension_menu_map;

        # bug 1261: allow only one "reset all services" call at a time
        date rip;

        # service HTTP listener hash; key = listener ID
        hash<auto> slh;

        # recovery counter
        Counter recovery_cnt();

        #! lock for atomic operations on listener map
        RWLock listener_map_lock();

        #! map of listener names to services: listener-name -> serviceid -> service listener info record
        hash<string, hash<string, hash<ServiceListenerInfo>>> listener_map;

        #! Check for service status changes 4 times a second
        const ServiceStatusChangePollInterval = 250ms;

        #! Wait max 30 seconds for the service's status to change
        const ServiceStatusChangeLimit = 30s;
    }

    constructor() {
    }

    rotateLogFiles() {
        foreach string type in (keys services) {
            map rotateLogFile(type, $1), keys services{type};
        }
    }

    private rotateLogFile(string type, string name) {
        grabServiceRead(type, name);
        on_exit releaseServiceRead(type, name);

        if (*OMQ::AbstractQorusCoreService svc = services{type}{name}) {
            svc.rotateLogFiles();
        }
    }

    updateLogger(int serviceid, *hash<LoggerParams> params) {
        if (*hash<auto> sh = Qorus.qmm.lookupService(serviceid, False)) {
            updateLogger(sh.type, sh.name, params);
        }
    }

    updateLogger(string type, string name, *hash<LoggerParams> params) {
        grabServiceRead(type, name);
        on_exit releaseServiceRead(type, name);

        if (*AbstractQorusCoreService svc = services{type}{name}) {
            svc.updateLogger(params);
        }
    }

    copy() {
        throw "COPY-ERROR", "this object cannot be copied";
    }

    signalRecovery() {
        recovery_cnt.inc();
    }

    enableLogging(softstring svcid) {
        *hash<auto> q = Qorus.qmm.lookupService(svcid, False);
        if (!q) {
            olog(LoggerLevel::FATAL, "Can't enable logging for service with id %d; no metadata", svcid);
            return;
        }

        grabServiceRead(q.type, q.name);
        on_exit releaseServiceRead(q.type, q.name);

        *AbstractQorusCoreService svc = services{q.type}{q.name};
        if (!(svc instanceof RemoteQorusService)) {
            return;
        }
        cast<RemoteQorusService>(svc).subscribeToLog();
    }

    disableLogging(softstring svcid) {
        *hash<auto> q = Qorus.qmm.lookupService(svcid, False);
        if (!q) {
            olog(LoggerLevel::FATAL, "Can't disable logging for service with id %d; no metadata", svcid);
            return;
        }

        grabServiceRead(q.type, q.name);
        on_exit releaseServiceRead(q.type, q.name);

        *AbstractQorusCoreService svc = services{q.type}{q.name};
        if (!(svc instanceof RemoteQorusService)) {
            return;
        }
        cast<RemoteQorusService>(svc).unsubscribeFromLog();
    }

    recoverProcesses(hash<string, bool> rsvch) {
        on_exit recovery_cnt.dec();

        foreach string svcid in (keys rsvch) {
            *hash<auto> q = Qorus.qmm.lookupService(svcid, False);
            if (!q) {
                # this can only happen if the metadata for a running service disappears at the same time as a
                # qorus-core process restart
                olog(LoggerLevel::FATAL, "serviceid %d with a running qsvc process has no metadata; process cannot be "
                    "recovered and will have to be killed manually", svcid);
                continue;
            }
            olog(LoggerLevel::INFO, "recovering running qsvc process for %s service %s v%s (%d): %y", q.type, q.name,
                q.version, svcid, SL_STATEFUL);

            grabServiceExclusive(q.type, q.name);
            on_exit releaseServiceExclusive(q.type, q.name);

            try {
                loadInternal(q.type, q.name, False, True, "recover running qsvc process after qorus-core restart", True);
            } catch (hash<ExceptionInfo> ex) {
                string errstr = Qorus.getDebugSystem() ? get_exception_string(ex) : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                olog(LoggerLevel::FATAL, "%s service %s v%s (%d) with a running qsvc process cannot be recovered and will "
                    "be terminated: %s", q.type, q.name, q.version, svcid, errstr);
                string proc_id = qsvc_get_process_name(q.type, q.name, q.version, svcid);
                Qorus.detachKillUnregisteredProcess(proc_id);
            }
        }
    }

    hash<auto> getUserHttpDebugInfo() {
        hash<auto> rv();
        foreach string key in (keys user_http_hash) {
            try {
                rv{key} = user_http_hash{key}.className();
            } catch (hash<ExceptionInfo> ex) {
                rv{key} = sprintf("%s: %s", ex.err, ex.desc);
            }
        }
        return rv;
    }

    string getDebugInfo() {
        hash<auto> service_info;
        foreach string type in (keys services) {
            foreach string name in (keys services{type}) {
                service_info{type}{name} = services{type}{name}.getDebugInfo();
            }
        }

        return sprintf("%N", {
            "service_access_hash": sah,
            "service_info": service_info,
            #"user_http_hash": user_http_hash,
            "user_http_hash": getUserHttpDebugInfo(),
            "listener_map": (map {$1.key: map {$1.key: $1.value.refs}, $1.value.pairIterator()}, listener_map.pairIterator()),
            "sc": sc.getCount(),
            "ui_extension_menu_map": ui_extension_menu_map,
        });
    }

    private checkType(string type) {
        if (type != "system" && type != "user") {
            throw "SERVICE-TYPE-ERROR", sprintf("invalid service type %y; service type may be \"user\" or \"system\"", type);
        }
    }

    # to allow read-only calls to be made while stopping the service
    releaseServiceToReadOnly(string type, string name) {
        QDBG_ASSERT(type == "system" || type == "user");
        int tid = gettid();

        lock();
        on_exit unlock();

        reference<hash<ServiceAccess>> h = \sah{type}{name};
        QDBG_ASSERT(h.exclusive == tid);
        QDBG_ASSERT(!h.in_read);
        QDBG_ASSERT(!h.exclusive_pending);

        # release exclusive lock
        h.exclusive = 0;
        remove tld.external_locks{remove h.exclusive_key};
        # mark as the only thread that can reaquire the exclusive lock
        h.exclusive_pending = tid;

        ++h.in_read;
%ifdef QorusDebugInternals
        ++h.rh{gettid()};
%endif

        # wake up any other threads waiting on the read lock
        if (h.read_waiting) {
            h.c.broadcast();
        }

        QDBG_ASSERT(tld.svc_locks{type}{name}{"EXCL"}{tid});
        remove tld.svc_locks{type}{name}{"EXCL"};
        tld.svc_locks{type}{name}{"RO"}{tid} = True;
    }

    reacquireServiceExclusive(string type, string name) {
        QDBG_ASSERT(type == "system" || type == "user");
        int tid = gettid();

        lock();
        on_exit unlock();

        reference<hash<ServiceAccess>> h = \sah{type}{name};
        QDBG_ASSERT(!h.exclusive);
        QDBG_ASSERT(h.exclusive_pending == tid);

        # release the read lock
%ifdef QorusDebugInternals
        if (!--h.rh{tid}) {
            remove h.rh{tid};
        }
%endif
        --h.in_read;
        while (h.in_read) {
            ++h.write_waiting;
            h.c.wait(self);
            --h.write_waiting;
        }

        QDBG_ASSERT(!h.exclusive);
        QDBG_ASSERT(h.exclusive_pending == tid);
        h.exclusive = tid;
        h.exclusive_pending = 0;
        tld.external_locks{h.exclusive_key = UUID::get()} = True;

        QDBG_ASSERT(tld.svc_locks{type}{name}{"RO"}{tid});
        remove tld.svc_locks{type}{name}{"RO"};
        tld.svc_locks{type}{name}{"EXCL"}{tid} = True;
    }

    private grabServiceExclusive(string type, string name, *bool unload) {
        checkType(type);
        ensure_create_tld();

        int tid = gettid();

        lock();
        on_exit unlock();

        reference<hash<ServiceAccess>> h = \sah{type}{name};
        if (!h) {
            h = new hash<ServiceAccess>();
        }
        while (True) {
            # if a dependent thread already holds a lock, then throw an exception
            if (tld.svc_locks{type}{name}) {
                throw "SERVICE-DEADLOCK-ERROR", sprintf("deadlock detected in TID %d attempting an operation on %s "
                    "service %y (locks held by this call chain: %y)", tid, type, name, tld.svc_locks{type}{name});
            }

            if (h.exclusive || h.exclusive_pending) {
                QDBG_ASSERT(h.exclusive != tid);
                QDBG_ASSERT(h.exclusive_pending != tid);
                ++h.write_waiting;
                QDBG_LOG("grabServiceExclusive(%s, %s) waiting on exclusive lock TID: %d (rh: %y tld.svc_locks: %y)", type, name, h.exclusive, keys h.rh, tld.svc_locks);
                h.c.wait(self);
                --h.write_waiting;
                continue;
            }

            if (h.in_read) {
                ++h.write_waiting;
                QDBG_LOG("grabServiceExclusive(%s, %s) waiting on read lock cnt: %d (rh: %y tld.svc_locks: %y)", type, name, h.in_read, keys h.rh, tld.svc_locks);
                h.c.wait(self);
                --h.write_waiting;
                continue;
            }

            break;
        }

        QDBG_ASSERT(!h.exclusive_pending);
        h.exclusive = gettid();
        tld.external_locks{h.exclusive_key = UUID::get()} = True;
        if (unload) {
            h.unload = unload;
        }

        tld.svc_locks{type}{name}{"EXCL"}{tid} = True;
    }

    #! must be called with the exclusive lock held
    private setUnload(string type, string name) {
        lock();
        on_exit unlock();

        reference<hash<ServiceAccess>> h = \sah{type}{name};
        QDBG_ASSERT(h);
        QDBG_ASSERT(h.exclusive == gettid());
        QDBG_ASSERT(!h.unload);
        QDBG_ASSERT(tld.svc_locks{type}{name}{"EXCL"}{gettid()});
        h.unload = True;
    }

    private releaseServiceExclusive(string type, string name) {
        QDBG_ASSERT(type.lwr() == type);

        lock();
        on_exit unlock();

        reference<hash<ServiceAccess>> h = \sah{type}{name};
        QDBG_ASSERT(h.exclusive == gettid());
        QDBG_ASSERT(!h.exclusive_pending);
        QDBG_ASSERT(tld.svc_locks{type}{name}{"EXCL"}{gettid()});

        h.exclusive = 0;
        remove tld.external_locks{remove h.exclusive_key};
        if (h.unload) {
            remove h.unload;
        }
        if (h.write_waiting || h.read_waiting) {
            h.c.broadcast();
        }

        remove tld.svc_locks{type}{name}{"EXCL"};
    }

    private grabServiceRead(string type, string name, *bool fail_unload) {
        checkType(type);
        ensure_create_tld();

        int tid = gettid();

        lock();
        on_exit unlock();

        reference<hash<ServiceAccess>> h = \sah{type}{name};
        if (!h) {
            h = new hash<ServiceAccess>();
        }

        while (True) {
            if (h.exclusive) {
                QDBG_ASSERT(h.exclusive_key);
                # if a dependent thread already holds a lock, then throw an exception
                if (tld.svc_locks{type}{name}{"EXCL"}) {
                    throw "SERVICE-DEADLOCK-ERROR", sprintf("deadlock detected in TID %d attempting an operation on "
                        "%s service %y (locks held by this call chain: %y)", tid, type, name,
                        tld.svc_locks{type}{name});
                }

                if (fail_unload && h.unload) {
                    throw "SERVICE-ERROR", sprintf("%s service %s cannot be accessed as it is being unloaded by "
                        "TID %d", type, name, h.exclusive);
                }

                # issue #3786: if the reader is holding a borrowed exclusive lock, then allow access and exit
                # without taking any action
                if (tld.external_locks{h.exclusive_key}) {
                    QDBG_LOG("%s service %y: allowing read lock under exclusive lock (%y)", type, name, h.exclusive_key);
                    # if the calling thread holds the exclusive key, then provide it exclusive access
                    return;
                }

                ++h.read_waiting;
                h.c.wait(self);
                --h.read_waiting;
                continue;
            }

            break;
        }

        ++h.in_read;
%ifdef QorusDebugInternals
        ++h.rh{tid};
%endif

        tld.svc_locks{type}{name}{"RO"}{tid} = True;
    }

    private releaseServiceRead(string type, string name) {
        int tid = gettid();
        QDBG_ASSERT(type.lwr() == type);
        lock();
        on_exit unlock();

        # issue #3786: if the reader is holding a borrowed exclusive lock, then exit without taking any action
        if (tld.external_locks{sah{type}{name}.exclusive_key}) {
            QDBG_ASSERT(!tld.svc_locks{type}{name}{"RO"}{tid});
            return;
        }
        # otherwise the called must be holding the read lock
        QDBG_ASSERT(tld.svc_locks{type}{name}{"RO"}{tid});

        reference<hash<ServiceAccess>> service_access = \sah{type}{name};
        QDBG_ASSERT(!exists tld.svc_locks{type}{name}{"EXCL"} || service_access.exclusive_pending);

        releaseServiceReadIntern(type, name, \service_access, tid);
    }

    private releaseServiceReadIntern(string type, string name, reference<hash<ServiceAccess>> service_access, int tid) {
        # release the read lock
%ifdef QorusDebugInternals
        if (!--service_access.rh{tid}) {
            remove service_access.rh{tid};
        }
%endif

        remove tld.svc_locks{type}{name}{"RO"}{tid};

        if (!--service_access.in_read) {
            # cover the case when we hold the read lock and the write lock
            if (service_access.write_waiting) {
                service_access.c.broadcast();
            }

            QDBG_ASSERT(!tld.svc_locks{type}{name}{"RO"});
        }

        if (!tld.svc_locks{type}{name}{"RO"}) {
            remove tld.svc_locks{type}{name};
        }
    }

    # returns True if the exclusive lock was grabbed = service needs to be loaded; False = read lock grabbed
    /** this method also allows a read lock to be grabbed while the same thread holds a write lock
        in this case the read lock must be released by calling releaseServiceToLoad() before releasing the write lock
    */
    private bool grabServiceToLoad(string type, string name) {
        checkType(type);
        ensure_create_tld();
        int tid = gettid();
        lock();
        on_exit unlock();

        reference<hash<ServiceAccess>> h = \sah{type}{name};
        if (!h) {
            h = new hash<ServiceAccess>();
        }

        while (True) {
            # because we could grab either lock, we need to set both "read_waiting" and "write_waiting"
            # if the service does not exist, then we need to grab the write lock, so we wait for any read lock to come free
            if (h.exclusive || (!services{type}{name} && (h.in_read || h.exclusive_pending))) {
                QDBG_ASSERT(h.exclusive != tid);

                # if a dependent thread already holds a lock, then throw an exception
                if (tld.svc_locks{type}{name}{"EXCL"}) {
                    throw "SERVICE-DEADLOCK-ERROR", sprintf("deadlock detected in TID %d attempting an operation on "
                        "%s service %y (locks held by this call chain: %y)", tid, type, name,
                        tld.svc_locks{type}{name});
                }

                ++h.read_waiting;
                ++h.write_waiting;
                h.c.wait(self);
                --h.write_waiting;
                --h.read_waiting;
                continue;
            }

            break;
        }

        if (!services{type}{name}) {
            QDBG_ASSERT(!h.exclusive);
            QDBG_ASSERT(!h.exclusive_pending);
            QDBG_ASSERT(!h.in_read);
            h.exclusive = gettid();
            tld.external_locks{h.exclusive_key = UUID::get()} = True;

            tld.svc_locks{type}{name}{"EXCL"}{tid} = True;

            return True;
        }

        ++h.in_read;
%ifdef QorusDebugInternals
        ++h.rh{tid};
%endif

        QDBG_ASSERT(!h.exclusive);
        QDBG_ASSERT(!h.exclusive_key);
        tld.svc_locks{type}{name}{"RO"}{tid} = True;

        return False;
    }

    # transitions from an exclusive lock on the service to a read lock on the service
    private releaseServiceExclusiveToRead(string type, string name) {
        QDBG_ASSERT(type.lwr() == type);
        int tid = gettid();
        lock();
        on_exit unlock();

        reference<hash<ServiceAccess>> h = \sah{type}{name};
        QDBG_ASSERT(h.exclusive == tid);
        QDBG_ASSERT(!h.exclusive_pending);
        QDBG_ASSERT(!h.in_read);
        # release the exclusive lock
        h.exclusive = 0;
        remove tld.external_locks{remove h.exclusive_key};

        # grab the read lock
        ++h.in_read;
%ifdef QorusDebugInternals
        ++h.rh{tid};
%endif
        # wake up any threads waiting on the read lock
        if (h.read_waiting) {
            h.c.broadcast();
        }

        remove tld.svc_locks{type}{name}{"EXCL"};
        tld.svc_locks{type}{name}{"RO"}{tid} = True;
    }

    private releaseServiceToLoad(string type, string name) {
        QDBG_ASSERT(type.lwr() == type);
        int tid = gettid();
        lock();
        on_exit unlock();

        reference<hash<ServiceAccess>> h = \sah{type}{name};
        QDBG_ASSERT(!h.exclusive || !h.in_read || h.exclusive == tid);
        # cover the case when we hold the read lock and the write lock
        if (h.exclusive && !h.in_read) {
            QDBG_ASSERT(h.exclusive == tid);
            QDBG_ASSERT(tld.svc_locks{type}{name}{"EXCL"}{tid});
            h.exclusive = 0;
            remove tld.external_locks{remove h.exclusive_key};
            if (h.write_waiting || h.read_waiting) {
                h.c.broadcast();
            }
            remove tld.svc_locks{type}{name}{"EXCL"};
            return;
        }

        QDBG_ASSERT(tld.svc_locks{type}{name}{"RO"}{tid});

        # release the read lock
        remove tld.svc_locks{type}{name}{"RO"}{tid};

%ifdef QorusDebugInternals
        if (!--h.rh{tid}) {
            remove h.rh{tid};
        }
%endif
        if (!--h.in_read) {
            QDBG_ASSERT(!h.exclusive || h.exclusive == tid);
            # we may also hold the write lock, so only broadcast if not
            if (!h.exclusive && h.write_waiting) {
                h.c.broadcast();
            }
            QDBG_ASSERT(!tld.svc_locks{type}{name}{"RO"});
        }

        if (!tld.svc_locks{type}{name}{"RO"}) {
            remove tld.svc_locks{type}{name};
        }
    }

    # must be called holding the read lock for the service; returns after the
    # service has been unloaded and still holding the read lock
    private waitServiceUnload(OMQ::AbstractQorusCoreService svc) {
        string type = svc.type;
        string name = svc.name;
        int tid = gettid();
        QDBG_ASSERT(type.lwr() == type);
        QDBG_ASSERT(tld.svc_locks{type}{name}{"RO"}{tid});
        Counter svc_unloaded;
        {
            lock();
            on_exit unlock();

            reference<hash<ServiceAccess>> service_access = \sah{type}{name};
            QDBG_ASSERT(!exists tld.svc_locks{type}{name}{"EXCL"} || service_access.exclusive_pending);

            svc_unloaded = svc.getUnloadCounter();

            releaseServiceReadIntern(type, name, \service_access, tid);
        }

        svc_unloaded.waitForZero();
        grabServiceRead(type, name);
    }

    stopListenerName(*hash<auto> cx, string name) {
        stopListenerId(cx, Qorus.httpServer.getListenerInfoName(name).id);
    }

    stopListenerId(*hash<auto> cx, softstring lid) {
        # issue #3789: do not allow a listener to be stopped from the same listener
        if (lid == cx."listener-id") {
            throw "LISTENER-ARG-ERROR", sprintf("cannot stop listener %d from a request on the same listener", lid);
        }

        # if the listener is a service listener, then stop it by removing the service resource
        *hash<auto> h;
        {
            lock();
            on_exit unlock();

            h = remove slh{lid};
        }

        if (h) {
            try {
                # XXX log
                h.service.removeResource(h.resource);
            } catch (hash<ExceptionInfo> ex) {
                # if the resource does not exist, then try to stop the listener
                if (ex.err == "SERVICE-REMOVE-RESOURCE-ERROR") {
                    Qorus.httpServer.stopListenerID(lid);
                } else {
                    rethrow;
                }
            }
        }

        try {
            Qorus.httpServer.stopListenerID(lid);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-LISTENER-ERROR") {
                # ignore if listener does not exist anymore
            } else {
                rethrow;
            }
        }
    }

    #! called when a config item value changes for a local service
    configItemValueChanged(string type, string name, string item_name, auto value) {
        type = type.lwr();

        grabServiceRead(type, name);
        on_exit releaseServiceRead(type, name);

        # if the service is not loaded or is remote, then ignore
        if (!services{type}{name} || services{type}{name}.remote) {
            return;
        }

        cast<Service>(services{type}{name}).configItemValueChanged(item_name, value);
    }

    registerListener(softstring lid, OMQ::AbstractQorusCoreService svc, string rname) {
        lock();
        on_exit unlock();

        slh{lid} = {
            "service": svc,
            "resource": rname,
        };
    }

    deregisterListener(softstring lid, string listener_name, softstring serviceid) {
        {
            lock();
            on_exit unlock();

            remove slh{lid};
        }
        removeServiceFromListenerMap(listener_name, serviceid);
    }

    #! Returns True if the new qsvc process must be stopped
    /** only called for stateful services
    */
    bool handleRestartedService(string process_id, string type, string name, int svcid, date abort_timestamp) {
        # in case qorus-core was restarted, the service may not exist, in which case we tell the service to terminate
        if (!services{type}{name}) {
            # tell qorus-master to stop the process
            qlog(LoggerLevel::INFO, "unloaded remote %s service %s (%s) has restarted; stopping process", type, name,
                process_id);
            background Qorus.stopProcess(process_id);
            return True;
        }

        return False;
    }

    markRemoteServiceAborted(string type, string name) {
        *RemoteQorusService svc = tryGetRemoteService(type, name);
        if (!svc) {
            QDBG_LOG("ignoring abort for remote %s service: %y", type, name);
            return;
        }
        QDBG_LOG("marking remote %s service aborted: %y", type, name);
        svc.setAborted();
    }

    #! only called when the remote services are not restarted
    /**
    */
    recoverAbortedService(string type, string name, int svcid, string state_label, date abort_timestamp) {
        hash<auto> service_info_hash;
        bool autostart;
        {
            # service recovery is driven by the remote service, so we only take action here if the remote service was not
            # restarted.  when a remote service recovers itself, it will call restartingService()
            # if qorus-core is restarted and the same time as a service crashes, then it will not exist in "services"

            grabServiceRead(type, name);
            on_exit releaseServiceRead(type, name);

            if (!services{type}{name}) {
                qlog(LoggerLevel::INFO, "ignoring service abort message for unloaded %s service %s (%d)", type, name, svcid);
                return;
            }
            RemoteQorusService svc = getRemoteService(type, name);

            # if AbstractQorusCoreService::processAborted() returns True, it means that the service is already stopping
            # in another thread, if it returns False, then we have to call AbstractQorusCoreService::stopAllResources()
            if (svc.processAborted()) {
                return;
            }
            QDBG_LOG("processing %s %s service %s v%s (%d)", "aborted", type, name, svc.version, svcid);

            svc.setAbortedStopReason();

            # in case autostart is set, save service information for the alert
            if (svc.autostart) {
                autostart = True;
                service_info_hash = {
                    "servicetype": type,
                    "name": name,
                    "version": svc.version,
                    "stateless": False,
                };
            }
        }

        {
            grabServiceExclusive(type, name, True);
            on_exit releaseServiceExclusive(type, name);

            if (services{type}{name}) {
                RemoteQorusService svc = getRemoteService(type, name);

                svc.stopAllResources();

                remove services{type}{name};

                AbstractQorusCoreService::del(svc, self);
            }
        }

        # if autostart is set, raise an ongoing alert
        if (autostart) {
            ActionReason stopreason(NOTHING, "the qsvc process terminated unexpectedly and could not be restarted");
            Qorus.alerts.raiseOngoingAlert(stopreason, "SERVICE", svcid, "SERVICE-NOT-LOADED", service_info_hash);
        }

        qlog(LoggerLevel::INFO, "%s %s service successfully deleted from cache", type, name);

        updated = now_us();
    }

    # called from the remote service when it restarts
    restartingService(string type, string name, string process_id) {
        # in case qorus-core was restarted, the service may not exist, in which case we tell the service to terminate
        if (!services{type}{name}) {
            # tell qorus-master to stop the process
            qlog(LoggerLevel::INFO, "got restart call for unloaded remote %s service %s (%s); stopping process", type, name, process_id);
            Qorus.stopProcess(process_id);
            return;
        }

        RemoteQorusService svc = getRemoteService(type, name);
        svc.aborted();
        qlog(LoggerLevel::INFO, "successfully processed restart call for remote %s service %s (%s)", type, name, process_id);
    }

    addUiExtension(string name, QorusUiExtensionResource ext) {
        lock();
        on_exit unlock();

        if (ui_extension_resource_map{name}) {
            throw "UI-EXTENSION-ERROR", sprintf("UI extension %y for %s service %y has already been registered", name,
                ext.getServiceType(), ext.getServiceName());
        }
        string group = ext.getGroup();
        string menu = ext.getMenuName();
        if ((*QorusUiExtensionResource other = ui_extension_menu_map{group}{menu}.firstValue())
            && (other.getServiceType() != ext.getServiceType() || other.getServiceName() != ext.getServiceName())) {
            throw "UI-EXTENSION-ERROR", sprintf("UI extension with group %y and menu entry %y has already been "
                "registered by %s service %y", group, menu, other.getServiceType(), other.getServiceName());
        }

        ui_extension_resource_map{name} = ui_extension_menu_map{group}{menu}{name} = ext;
    }

    removeUiExtension(string name) {
        lock();
        on_exit unlock();

        *QorusUiExtensionResource ext = remove ui_extension_resource_map{name};
        if (ext) {
            string group = ext.getGroup();
            string menu = ext.getMenuName();
            remove ui_extension_menu_map{group}{menu}{name};
            # issue #3677 must remove parent entries when empty
            if (!ui_extension_menu_map{group}{menu}) {
                remove ui_extension_menu_map{group}{menu};
                if (!ui_extension_menu_map{group}) {
                    remove ui_extension_menu_map{group};
                }
            }
        }
    }

    *hash<auto> getUiExtensions(hash<auto> cx) {
        lock();
        on_exit unlock();

        hash<string, hash<auto>> rv;
        foreach hash<auto> gi in (ui_extension_menu_map.pairIterator()) {
            foreach hash<auto> mi in (gi.value.pairIterator()) {
                # return a random extension handler for each menu entry in case there is more than one
                QorusUiExtensionResource ext;
                if ((int size = mi.value.size()) > 1) {
                    # get a random handler
                    ext = mi.value.values()[rand() % size];
                } else {
                    ext = mi.value.firstValue();
                }
                rv{ext.getName()} = ext.getUiExtensionInfo(cx);
            }
        }
        return rv;
    }

    *hash<auto> getUiExtensionInfo(string name, hash<auto> cx) {
        lock();
        on_exit unlock();

        *QorusUiExtensionResource ext = ui_extension_resource_map{name};
        return ext ? ext.getUiExtensionInfo(cx) : NOTHING;
    }

    hash<auto> handleUiExtensionRequest(string ename, hash<auto> cx, hash<auto> hdr, *data body) {
        QorusUiExtensionResource ext;

        {
            lock();
            on_exit unlock();

            if (!ui_extension_resource_map{ename})
                throw "UI-EXTENSION-ERROR", sprintf("no UI extension named %y exists; known extensions: %y", ename,
                    keys ui_extension_resource_map);

            ext = ui_extension_resource_map{ename};
        }

        string svc_type = ext.getServiceType();
        string svc_name = ext.getServiceName();

        ServiceThreadContextHelper stch(services{svc_type}{svc_name}, sprintf("<%s::handleRequest>", ext.getName()));

        return ext.getHandler().handleRequest(cx, hdr, body);
    }

    checkUserServiceAccess(hash<auto> cx, string type, string name) {
        if (cx.user && type == "user") {
            # get service id outside the lock
            *int sid = services{type}{name}.serviceid;
            if (!sid)
                sid = Qorus.qmm.getServiceId(type, name);
        }
    }

    AbstractRestStreamRequestHandler getStreamHandler(string type, string name, string stream, hash<auto> cx, *hash<auto> ah) {
        AbstractQorusCoreService svc;
        {
            # user service access has already been checked by REST infrastructure
            bool load = grabServiceToLoad(type, name);
            on_exit releaseServiceToLoad(type, name);

            # if we are in persistent transaction, we can use the service in the handler,
            # cannot we?
            auto listener = get_thread_data("svc_listener");
            if (listener) {
                auto uctx = listener.removeUserThreadContext("persistent_data");
                on_exit {
                    if (uctx) {
                        listener.addUserThreadContext({"persistent_data": uctx});
                    }
                }
                if (uctx) {
                    svc = uctx.getService();
                }
            }

            if (load) {
                QDBG_ASSERT(!svc || svc.type != type || svc.name != name);
                svc = getServiceIntern(type, name);
                releaseServiceExclusiveToRead(type, name);
            } else if (svc) {
                svc.logDebug("using service %y.%y from persistent connection", type, name);
            } else {
                svc = services{type}{name};
            }

            svc.ref();
        }

        # dereference and delete service if necessary when the block exists
        on_exit
            derefService(svc);

        # issue #3307: set TLD for service so logs will appear in the service log file
        on_success
            tld.svc = svc;

        return svc.getStreamHandler(stream, cx, ah);
    }

    derefService(OMQ::AbstractQorusCoreService svc) {
        # dereference and delete service if necessary when the block exists
        # this is very fast, no need to block / unblock service
        svc.deref();
    }

    # the URL identifies the user http service and must be unique
    bool setUserHttpServiceInfo(string url, AbstractServiceHttpHandler handler) {
        lock();
        on_exit unlock();

        if (user_http_hash{url}) {
            tld.svc.logInfo("cannot register url %y as a user handler; already registered to service %y",
                url, user_http_hash{url}.getServiceInfo().name);
            return False;
        }

        user_http_hash{url} = handler;
        return True;
    }

    # must use the same URL as used in the setUserHttpServiceInfo() call
    removeUserHttpServiceInfo(string url) {
        lock();
        on_exit unlock();

        QDBG_ASSERT(user_http_hash{url});
        remove user_http_hash{url};
    }

    *hash<auto> getUserHttpServiceInfo(hash<auto> cx) {
        lock();
        on_exit unlock();

        hash<auto> h;
        foreach AbstractServiceHttpHandler handler in (user_http_hash.iterator()) {
            reference hi = \h.(handler.utype);
            if (!hi)
                hi = ();
            hash<auto> sh = handler.getServiceInfo();
            hi += {
                "title": handler.utitle,
                "url": qorus_get_url(cx, handler.uurl),
                "service": sh.name,
                "version": sh.version,
                "serviceid": sh.serviceid,
            };
        }

        return h;
    }

    date getUpdated() { return updated; }
    bool shuttingDown() { return shutting_down; }

    bool reloadService(*hash<auto> c, string type, string name, bool load = False, *string why) {
        # get service id outside the lock
        *int sid = services{type}{name}.serviceid;
        if (!sid)
            sid = Qorus.qmm.getServiceId(type, name);

        # reset user connection status & dependencies
        Qorus.connections.resetStatus("SERVICE", sid);

        grabServiceExclusive(type, name);
        on_exit releaseServiceExclusive(type, name);

        if (!services{type}{name}) {
            # check if service should be running
            if (load || Qorus.qmm.lookupService(sid, False).autostart) {
                loadInternal(type, name, False, True, "reload service" + (why ? ": " + why : ""));
            }
            return False;
        }

        reloadServiceIntern(type, name, why);
        return True;
    }

    unloadService(string type, string name, *string version, *bool for_disable, *string reason) {
        grabServiceExclusive(type, name, True);
        on_exit releaseServiceExclusive(type, name);

        while (True) {
            try {
                unloadServiceUnlocked(type, name, version, for_disable, False, reason);
            } catch (hash<ExceptionInfo> ex) {
                # CLIENT-ABORTED is only thrown when a process aborts and is restarted automatically
                # if other errors related to terminating or aborted qsvc processes are thrown, then we wait until the
                # service has been unloaded normally
                if (ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED" || ex.err == "CLIENT-DEAD"
                    || ex.err == "SERVICE-SHUTDOWN-ERROR") {
                    waitForRemoteServiceReset(type, name);
                    continue;
                } else {
                    rethrow;
                }
            }
            break;
        }
    }

    # called with the exclusive lock held for the service
    private waitForRemoteServiceReset(string type, string name) {
        releaseServiceExclusive(type, name);
        on_exit grabServiceExclusive(type, name, True);

        # allow for the call to succeed even if the qsvc process crashes while unloading
        date now = now_us();

        while (True) {
            grabServiceRead(type, name);
            on_exit releaseServiceRead(type, name);

            *AbstractQorusCoreService svc = services{type}{name};
            if (!svc || !(svc instanceof RemoteQorusService)) {
                return;
            }
            RemoteQorusService rsvc = cast<RemoteQorusService>(svc);
            if (!rsvc.isAborted()) {
                return;
            }

            date delta = now_us() - now;
            if (delta > ServiceStatusChangeLimit) {
                throw "SERVICE-UNLOAD-ERROR", sprintf("%s service %s v%s (%d) aborted and the status did not "
                    "change in the time limit (%y)", type, name, svc.version, svc.serviceid, delta);
            }

            QDBG_LOG("ServiceManager::waitForRemoteServiceReset() qsvc process for %s service %s v%s (%d) aborted; "
                "waiting for status to change", type, name, svc.version, svc.serviceid);
            usleep(ServiceStatusChangePollInterval);
        }
    }

    list<hash<string, string>> reloadServices(*hash<auto> c, string type, *string why) {
        return reloadServicesIntern(c, type, why);
    }

    list<hash<string, string>> reloadAll(*hash<auto> c) {
        {
            lock();
            on_exit unlock();

            if (rip)
                throw "RELOAD-IN-PROGRESS", sprintf("reload all services call in progress since %y", rip);

            rip = now_us();
        }

        on_exit {
            lock();
            on_exit unlock();

            delete rip;
        }

        list<hash<string, string>> l = ();
        map l += reloadServicesIntern(c, $1), ("system", "user");
        return l;
    }

    setServiceOptions(*hash<auto> c, string type, string name, hash<auto> h) {
        *hash<auto> svc = Qorus.qmm.rLookupService(type, name);
        if (!svc) {
            throw "UNKNOWN-SERVICE", sprintf("cannot find any %s service %y", type, name);
        }

        type = type.lwr();

        Qorus.qmm.updateServiceOptionsErr(svc.serviceid, h);
    }

    auto getServiceOptions(*hash<auto> c, string type, string name, *softlist<auto> args) {
        *hash<auto> svc = Qorus.qmm.rLookupService(type, name);
        if (!svc) {
            throw "UNKNOWN-SERVICE", sprintf("cannot find any %s service %y", type, name);
        }

        type = type.lwr();

        return Qorus.qmm.getOptionsWithContextArgs("service", svc.serviceid, args);
    }

    *AbstractQorusCoreService getService(string type, string name) {
        return services{type}{name};
    }

    RemoteQorusService getRemoteService(string type, string name) {
        return cast<RemoteQorusService>(services{type}{name});
    }

    *RemoteQorusService tryGetRemoteService(string type, string name) {
        return cast<*RemoteQorusService>(services{type}{name});
    }

    RemoteQorusService getRemoteServiceRef(string type, string name) {
        grabServiceRead(type, name, True);
        on_exit releaseServiceRead(type, name);

        # issue #3531: in case qorus-core is shutting down when the service is restarted
        if (!services{type}{name}) {
            throw "SYSTEM-SHUTDOWN-ERROR", sprintf("%s service %s cannot be recovered because the system is shutting down",
                type, name);
        }

        RemoteQorusService svc = cast<RemoteQorusService>(services{type}{name});
        svc.ref();
        return svc;
    }

    data getServiceFileResourceData(string type, string name, string rsrc) {
        type = type.lwr();

        {
            grabServiceRead(type, name);
            on_exit releaseServiceRead(type, name);

            if (services{type}{name})
                return services{type}{name}.getResourceData(rsrc);
        }

        *hash<auto> sh = Qorus.qmm.rLookupService(type, name);
        if (!sh)
            throw "SERVICE-RESOURCE-ERROR", sprintf("cannot retrieve file resource %y from unknown %s service %y", rsrc, type, name);

        *hash<auto> rq = AbstractQorusService::getServiceResource(sh.serviceid, rsrc);
        if (!rq)
            throw "SERVICE-RESOURCE-ERROR", sprintf("%s service %y has no file resource %y", type, name, rsrc);

        return rq.resource_type != "B" ? rq.body.toString() : rq.body;
    }

    # issue 1921: API to tell if the service is loaded
    bool getServiceLoadedIndication(string type, string name) {
        return services{type}{name} ? True : False;
    }

    #! despite the "Extern" in the name, this is actually for internal service method calls (unless "ext" is True)
    auto callMethodExtern(string type, string name, string method, *softlist<auto> args, *hash<auto> my_tld, *bool ext) {
        ensure_create_tld();
        if (my_tld) {
            tld.add(my_tld);
        }

        return callMethodInternal(type, name, method, args, NOTHING, ext);
    }

    #! despite the "Extern" in the name, this is actually for internal service method calls
    /** This method is for calls from external processes; in case the actual service call is made from an external
        qsvc process, it is not deserialized here, but rather the response is returned in its native form so that it
        can be deserialized by the called directly
    */
    auto callMethodExternSerialized(string type, string name, string method, *binary serialized_args, *hash<auto> my_tld, *bool ext) {
        ensure_create_tld();
        if (my_tld) {
            tld.add(my_tld);
        }

        return callMethodInternal(type, name, method, NOTHING, serialized_args, ext, NOTHING, True);
    }

    startThreadTerminated(AbstractQorusCoreService svc, *string errdesc) {
        string type = svc.type;
        string name = svc.name;

        svc.deref();

        if (!errdesc || shuttingDown()) {
            return;
        }

        grabServiceExclusive(type, name, True);
        on_exit releaseServiceExclusive(type, name);

        # raise an error and delete the service if the start method stopped prematurely
        svc.logInfo("%s", errdesc);
        Qorus.events.postServiceError(tld.cx, ES_Major, svc.type, svc.name, svc.version, svc.serviceid, "START-ERROR", errdesc);
        unloadServiceIntern(svc);
    }

    # no locking needed; called in current service
    bindHandler(string name, AbstractServiceHttpHandler handler) {
        OMQ::AbstractQorusCoreService svc = services.(tld.svc.type).(tld.svc.name);
        svc.bindHandler(name, handler);
    }

    # no locking needed; called in current service
    bindHandler(string name, AbstractHttpRequestHandler handler, string url, *softlist<auto> content_type,
            *softlist<auto> special_headers, bool isregex = True) {
        OMQ::AbstractQorusCoreService svc = services.(tld.svc.type).(tld.svc.name);
        svc.bindHandler(name, handler, url, content_type, special_headers, isregex);
    }

    # no locking needed; called in current service
    softlist<string> bindHttp(AbstractServiceHttpHandler handler, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{},) {
        OMQ::AbstractQorusCoreService svc = services.(tld.svc.type).(tld.svc.name);
        return svc.bindHttp(handler, opts);
    }

    list<hash<auto>> bindHttpListenersIntern(OMQ::AbstractQorusCoreService svc, softlist<auto> listeners,
            hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        list<auto> createdListeners = ();
        list<auto> reusedListeners = ();

        # find already existing listeners
        hash<auto> currentListeners = Qorus.httpServer.getListeners();

        # try to start all listeners
        foreach hash<auto> listener_params in (listeners) {
            try {
                if (listener_params.bind.typeCode() != NT_STRING) {
                    throw "BIND-HTTP-ERROR", sprintf("listener parameter hash has type %y assigned to 'bind' key, "
                        "expecting string", listener_params.bind.type());
                }

                # find listeners with same bind value
                list<auto> sameBindListeners();
                foreach hash<auto> ch in (currentListeners.pairIterator()) {
                    # issue #3255: do not use equality comparisons with type conversions (==)
                    # because in this case 0 == NOTHING for example
                    # issue #3669: treat wildcard listeners as unique
                    if (listener_params.bind =~ /:0$/ || listener_params.bind == "0") {
                        continue;
                    }
                    if (listener_params.bind === ch.value.bind) {
                        push sameBindListeners, ch.value;
                    } else if (listener_params.bind =~ /^[0-9]{1,5}$/ &&
                                    (listener_params.bind.toInt() === ch.value.port ||
                                    (":::" + listener_params.bind) === ch.value.bind)) {
                        push sameBindListeners, ch.value;
                    }
                }

                # check that existing listeners with same bind value can be shared
                if (sameBindListeners) {
                    foreach hash<auto> h in (sameBindListeners) {
                        # check that it's allowed to share this listener
                        {
                            listener_map_lock.readLock();
                            on_exit listener_map_lock.readUnlock();

                            hash<string, hash<ServiceListenerInfo>> svc_hash = listener_map{h.name};
                            if (!svc_hash{svc.serviceid}) {
                                if (opts.allow_listener_sharing == False) {
                                    throw "LISTENER-SHARING-ERROR",
                                        sprintf("service %s trying to bind handler to listener %s and does not allow "
                                                "sharing of the listener; all services have to allow sharing "
                                                "to be able to share a listener",
                                                svc.name, h.name);
                                }

                                # we have to check that the service(s) using the listener allow sharing
                                foreach hash<ServiceListenerInfo> x in (svc_hash.iterator()) {
                                    if (x.allow_listener_sharing == False) {
                                        throw "LISTENER-SHARING-ERROR",
                                            sprintf("service %s using listener %s does not allow sharing of the listener",
                                                    x.svc.name, h.name);
                                    }
                                }
                            }
                        }

                        # issue #3219: add to listener map
                        addServiceToListenerMap(h.name, svc, opts);

                        reusedListeners += {
                            "name": h.name,
                            "id": h.id,
                            "desc": sprintf("listening on %s (dedicated)", h.desc),
                        };

                        svc.logInfo("using existing listener %y with bind address %y for service ",
                            h.name, h.bind, svc.name);
                    }

                    continue;
                }

                # create new listeners
                list<auto> ll = addServiceListeners(svc.serviceid, listener_params.bind, listener_params, svc);
                if (!ll) {
                    throw "HTTP-ERROR", sprintf("no listeners could be started on bind address %s",
                        listener_params.bind);
                }

                foreach hash<auto> h in (ll) {
                    svc.logInfo("HTTP%s listener %s %y id %d started on %s", h.ssl ? "S" : "", h.name,
                        listener_params.bind, h.id, h.address_desc + ":" + h.port);
                    createdListeners += {
                        "name": h.name,
                        "id": h.id,
                        "desc": sprintf("listening on %s (dedicated)", h.desc),
                    };
                    # issue #3219: add to listener map
                    addServiceToListenerMap(h.name, svc, opts);
                }
            } catch (hash<ExceptionInfo> ex) {
                svc.logInfo("error starting HTTP listener with bind address %y "
                    "or reusing an existing one: %s: %s", listener_params.bind, ex.err, ex.desc);

                # stop all started listeners if an error has occured
                foreach hash<auto> h in (createdListeners) {
                    # issue #3219: remove from listener map
                    removeServiceFromListenerMap(h.name, svc.serviceid);

                    try {
                        Qorus.httpServer.stopListenerID(h.id);
                    } catch (hash<ExceptionInfo> ex1) {
                        svc.logInfo("error stopping HTTP%s listener id %d: %s: %s", h.ssl ? "S" : "", h.id,
                            ex1.err, ex1.desc);
                    }
                }

                # remove from listener map for the reused listeners
                foreach hash<auto> h in (reusedListeners) {
                    # issue #3219: remove from listener map
                    removeServiceFromListenerMap(h.name, svc.serviceid);
                }

                throw "SERVICE-HTTP-ERROR", sprintf("error starting listener: %y: %s: %s", listener_params.bind,
                    ex.err, ex.desc);
            }
        }

        return createdListeners + reusedListeners;
    }

    #! log HTTP listener messages to the appropriate service
    /** @param listener_name the name of the listener
        @param msg the already-formatted message
        @param svc the original service that set up the listener; may have been deleted; it is included here for
        messages that arrive before the listener map is set up, since the listener name is only available after
        the add listener call returns, but log messages are output immediately by the HTTP server
    */
    logHttpListenerExtern(string listener_name, string msg, *AbstractQorusCoreService svc) {
        listener_map_lock.readLock();
        on_exit listener_map_lock.readUnlock();

        *AbstractQorusCoreService log_svc = listener_map{listener_name}.firstValue().svc ?? svc;
        if (log_svc) {
            try {
                log_svc.logExtern(msg);
            } catch (hash<ExceptionInfo> ex) {
                Qorus.httpServer.logArgs(LoggerLevel::ERROR, "could not log to service: %s: %s: %s", (get_ex_pos(ex), ex.err, ex.desc));
                Qorus.httpServer.logArgs(LoggerLevel::INFO, "%s", msg);
            }
        } else {
            # in case we have no valid service, log to the HTTP server's log
            Qorus.httpServer.logArgs(LoggerLevel::INFO, "%s", msg);
        }
    }

    logHttpListenerErrorExtern(string listener_name, string msg, *AbstractQorusCoreService svc) {
        listener_map_lock.readLock();
        on_exit listener_map_lock.readUnlock();

        *AbstractQorusCoreService log_svc = listener_map{listener_name}.firstValue().svc ?? svc;
        if (log_svc) {
            try {
                log_svc.logErrorExtern(msg);
            } catch (hash<ExceptionInfo> ex) {
                Qorus.httpServer.logArgs(LoggerLevel::ERROR, "could not log to service: %s: %s: %s", (get_ex_pos(ex),
                    ex.err, ex.desc));
                Qorus.httpServer.logArgs(LoggerLevel::ERROR, "%s", msg);
            }
        } else {
            Qorus.httpServer.logArgs(LoggerLevel::ERROR, "%s", msg);
        }
    }

    private list<auto> addServiceListeners(int serviceid, string bind, hash<auto> listener_params, AbstractQorusCoreService svc) {
        Logger service_listener_logger(svc.name, LoggerLevel::getLevelInfo());
        service_listener_logger.addAppender(new QorusServiceAppender(svc));

        hash<HttpListenerOptionInfo> info = cast<hash<HttpListenerOptionInfo>>(listener_params.opt ?? {});
        info = http_get_listener_options_from_bind(bind, listener_params, info);
        info += {
            "name": sprintf("svc-%s", svc.name),
            "logger": service_listener_logger,
            "stopc": \svc.resourceRemovedNotification(),
        };

        return Qorus.httpServer.addListeners(bind, info);
    }

    private addServiceToListenerMap(string listener_name, AbstractQorusCoreService svc,
            hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        #QDBG_LOG("ServiceManager::addServiceToListenerMap() %y -> %y (%y)", listener_name, svc.serviceid, (map {$1.key: map {$1.key: $1.value.refs}, $1.value.pairIterator()}, listener_map.pairIterator()));
        listener_map_lock.writeLock();
        on_exit listener_map_lock.writeUnlock();

        if (listener_map{listener_name}{svc.serviceid}) {
            ++listener_map{listener_name}{svc.serviceid}.refs;
        } else {
            listener_map{listener_name}{svc.serviceid} = <ServiceListenerInfo>{
                "svc": svc,
                "allow_listener_sharing": opts.allow_listener_sharing
            };
        }
    }

    removeServiceFromListenerMap(string listener_name, softstring serviceid) {
        QDBG_LOG("ServiceManager::removeServiceFromListenerMap() %y -> %y (%y)", listener_name, serviceid, (map {$1.key: map {$1.key: $1.value.refs}, $1.value.pairIterator()}, listener_map.pairIterator()));

        listener_map_lock.writeLock();
        on_exit listener_map_lock.writeUnlock();

        # remove service from map
        QDBG_ASSERT(listener_map{listener_name}{serviceid}.refs);
        if (!--listener_map{listener_name}{serviceid}.refs) {
            remove listener_map{listener_name}{serviceid};
            if (!listener_map{listener_name}) {
                remove listener_map{listener_name};
            }
        }
    }

    list<auto> bindHttpListenersIntern(OMQ::AbstractQorusCoreService svc, AbstractServiceHttpHandler handler,
            softlist<auto> listeners, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        list<auto> createdListeners = ();
        list<auto> assignedListeners = ();

        # find already existing listeners
        hash<auto> currentListeners = Qorus.httpServer.getListeners();

        foreach hash<auto> listener_params in (listeners) {
            try {
                if (listener_params.bind.typeCode() != NT_STRING) {
                    throw "BIND-HTTP-ERROR", sprintf("listener parameter hash has type %y assigned to 'bind' key, "
                        "expecting string", type(listener_params.bind));
                }

                # find listeners with same bind value
                list<auto> sameBindListeners();
                foreach hash<auto> ch in (currentListeners.pairIterator()) {
                    # issue #3255: do not use equality comparisons with type conversions (==)
                    # because in this case 0 == NOTHING for example
                    # issue #3669: treat wildcard listeners as unique
                    if (listener_params.bind =~ /:0$/ || listener_params.bind == "0") {
                        continue;
                    }
                    if (listener_params.bind === ch.value.bind) {
                        push sameBindListeners, ch.value;
                    } else if (listener_params.bind =~ /^[0-9]{1,5}$/ &&
                                    (listener_params.bind.toInt() === ch.value.port ||
                                    (":::" + listener_params.bind) === ch.value.bind)) {
                        push sameBindListeners, ch.value;
                    }
                }

                # assign handler to already existing listeners with same bind value
                if (sameBindListeners) {
                    foreach hash<auto> h in (sameBindListeners) {
                        # check that it's allowed to share this listener
                        {
                            listener_map_lock.readLock();
                            on_exit listener_map_lock.readUnlock();

                            hash<string, hash<ServiceListenerInfo>> svc_hash = listener_map{h.name};
                            if (!svc_hash{svc.serviceid}) {
                                if (opts.allow_listener_sharing == False) {
                                    throw "LISTENER-SHARING-ERROR",
                                        sprintf("service %s trying to bind handler to listener %s does not allow "
                                                "sharing of the listener; all the services have to allow sharing "
                                                "to be able to share a listener",
                                                svc.name, h.name);
                                }

                                # we have to check that the service(s) using the listener allow sharing
                                foreach hash<ServiceListenerInfo> x in (svc_hash.iterator()) {
                                    if (x.allow_listener_sharing == False) {
                                        throw "LISTENER-SHARING-ERROR",
                                            sprintf("service %s using listener %s does not allow sharing of the listener",
                                                    x.svc.name, h.name);
                                    }
                                }
                            }
                        }

                        # issue #3219: add to listener map
                        addServiceToListenerMap(h.name, svc, opts);

                        int handler_id = svc.getNextHandlerId();

                        # handler names must be unique
                        string handler_name = sprintf("svc-%s-%d", svc.name, handler_id);

                        *softlist<softstring> content_types = listener_params.content_type;
                        *softlist<softstring> headers = listener_params.special_headers;
                        hash<HttpHandlerConfigInfo> info({
                            "path": handler.url,
                            "isregex": handler.isregex,
                            "content_types": content_types,
                            "handler": handler,
                            "headers": headers,
                        });

                        # assign handler to listener
                        Qorus.httpServer.addHandlerToListenerID(h.id, handler_name, info);
                        assignedListeners += {
                            "name": h.name,
                            "id": h.id,
                            "desc": sprintf("listening on %s (dedicated)", h.desc),
                            "handler_name": handler_name,
                        };

                        svc.logInfo("bound service handler %y to existing listener %y with bind address %y",
                            handler_name, h.name, h.bind);
                    }

                    continue;
                }

                # create new listeners
                list<auto> ll = addServiceListeners(svc.serviceid, listener_params.bind, listener_params, svc);
                if (!ll) {
                    throw "HTTP-ERROR", sprintf("no listeners could be started on bind address %s",
                        listener_params.bind);
                }

                # assign handler to the newly created listeners
                foreach hash<auto> h in (ll) {
                    svc.logInfo("HTTP%s listener %s %y id %d started on %s", h.ssl ? "S" : "", h.name,
                        listener_params.bind, h.id, h.address_desc + ":" + h.port);

                    # issue #3219: add to listener map
                    addServiceToListenerMap(h.name, svc, opts);

                    int handler_id = svc.getNextHandlerId();

                    # handler names must be unique
                    string handler_name = sprintf("svc-%s-%d", svc.name, handler_id);

                    *softlist<softstring> content_types = listener_params.content_type;
                    *softlist<softstring> headers = listener_params.special_headers;
                    hash<HttpHandlerConfigInfo> info({
                        "path": handler.url,
                        "isregex": handler.isregex,
                        "content_types": content_types,
                        "handler": handler,
                        "headers": headers,
                    });

                    # assign handler to listener
                    Qorus.httpServer.addHandlerToListenerID(h.id, handler_name, info);
                    createdListeners += {
                        "name": h.name,
                        "id": h.id,
                        "desc": sprintf("listening on %s (dedicated)", h.desc),
                        "handler_name": handler_name,
                    };

                    svc.logInfo("added handler %s to HTTP%s listener %s %y id %d", handler_name,
                        h.ssl ? "S" : "", h.name, listener_params.bind, h.id);
                    svc.logInfo("bound service handler %y to new listener %y with bind address %y", handler_name,
                        h.name, h.bind);
                }
            } catch (hash<ExceptionInfo> ex) {
                svc.logInfo("error starting HTTP listener with bind address %y or adding handler to an "
                    "existing listener: %s: %s", listener_params.bind, ex.err, ex.desc);

                # stop newly created listeners if an error has occured
                foreach hash<auto> h in (createdListeners) {
                    # issue #3219: remove from listener map
                    removeServiceFromListenerMap(h.name, svc.serviceid);

                    try {
                        Qorus.httpServer.stopListenerID(h.id);
                    } catch (hash<ExceptionInfo> ex1) {
                        svc.logInfo("error stopping HTTP%s listener id %d: %s: %s", h.ssl ? "S" : "", h.id,
                            ex1.err, ex1.desc);
                    }
                }
                throw "SERVICE-HTTP-ERROR", sprintf("error starting listener (or adding handler to an existing "
                    "listener): %y: %s: %s: %s", listener_params.bind, get_ex_pos(ex), ex.err, ex.desc);
            }
        }

        return createdListeners + assignedListeners;
    }

    auto callMethod(string type, string name, string method, auto args, bool ext = False, *hash<auto> cx) {
        return callMethodInternal(type, name, method, args, NOTHING, ext, cx);
    }

    private auto callMethodInternal(string type, string name, string method, auto args, *binary serialized_args, bool ext = False, *hash<auto> cx, *bool serialized) {
        if (method == "stop") {
            throw "SERVICE-METHOD-ERROR", sprintf("error calling '%s.stop()'': the 'stop()'' method can only be called by the system; unload the service to stop it", name);
        }

        while (True) {
            bool load = grabServiceToLoad(type, name);
            on_exit releaseServiceToLoad(type, name);

            OMQ::AbstractQorusCoreService svc;
            if (load) {
                # we have exclusive access to the service
                svc = getServiceIntern(type, name);
                releaseServiceExclusiveToRead(type, name);
            } else {
                svc = services{type}{name};
            }

            # return if init method called (loadInternal will call the init method)
            # NOTE: this check must come after the service is loaded above
            if (method == "init") {
                return;
            }

            # return if start method called (loadInternal will start any start method)
            if (method == "start" && exists svc.methods.start) {
                return;
            }

            try {
                return svc.callMethod(method, args, serialized_args, ext, cx, serialized);
            } catch (hash<ExceptionInfo> ex) {
                # issue #2398: retry the call if the call failed because the service was being stopped
                # the "arg" key is to ensure that the exception came from the system
                if (ex.err == "SERVICE-STOPPED-ERROR" && ex.arg == svc) {
                    # wait for service to reset, as it's already been stopped
                    Qorus.logInfo(formatSvcLogMessage(type, name, "repeating call to method %s() due to service unload operation", method));
                    waitServiceUnload(svc);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    # no locking needed; called in current service
    hash<auto> getCurrentServiceInfo(*hash<auto> cx) {
        OMQ::AbstractQorusCoreService svc = services.(tld.svc.type).(tld.svc.name);
        return svc.getInfo(cx) + {"method": tld.method};
    }

    # no locking needed; called in current service
    bindFtp(AbstractFtpHandler handler) {
        if (!handler.listeners) {
            throw "SERVICE-FTP-ERROR", sprintf("no listeners set in FTP handler object; call "
                "AbstractFtpHandler::addListener() to add listeners before calling ServiceApi::bindFtp()");
        }

        # list of FTP listeners
        list<auto> ll = ();

        OMQ::AbstractQorusCoreService svc = services.(tld.svc.type).(tld.svc.name);

        # try to start all listeners
        foreach softstring l in (handler.listeners) {
            try {
                ThreadLocalData tcx();
                tcx.svc = tld.svc;
                tcx._current_ix = "svc";
                list<auto> new_ll = Qorus.ftpServer.addListeners(handler, tcx, l, \svc.logExtern(), \svc.logErrorExtern());
                if (!elements new_ll) {
                    throw "SERVICE-FTP-ERROR", sprintf("no listeners could be started on bind address %s", l);
                }
                foreach hash<auto> h in (new_ll) {
                    svc.logInfo("FTP listener %y id %d started on %s", l, h.id, h.address_desc);
                    ll += {
                        "id": h.id,
                        "desc": sprintf("listening on %s", h.desc),
                    };
                }
            } catch (hash<ExceptionInfo> ex) {
                svc.logInfo("error starting FTP listener with bind address %y: %s: %s", l, ex.err, ex.desc);

                # stop all listeners if an error has occured
                foreach hash<auto> h in (ll) {
                    try {
                        Qorus.ftpServer.stopListenerId(h.id);
                    } catch (hash<ExceptionInfo> ex1) {
                        svc.logInfo("error stopping FTP listener id %d: %s: %s", h.id, get_ex_pos(ex1), ex1.err, ex1.desc);
                    }
                }
                throw "SERVICE-FTP-ERROR", sprintf("error starting listener: %y: %s: %s: %s", l, get_ex_pos(ex), ex.err, ex.desc);
            }
        }

        # add FTP listeners as resources to service
        foreach hash<auto> h in (ll) {
            FtpServiceResource fsr(svc.getResourceId(), h.id, h.desc);
            svc.addResource(fsr);
        }

        svc.logInfo("started %d FTP listener%s for service", ll.size(), ll.size() == 1 ? "" : "s");
    }

    # returns a list of services cached
    list<hash<auto>> getCache(*hash<auto> cx, *string ptype) {
        if (ptype) {
            ptype = ptype.lwr();
        }

        list<hash<auto>> l = ();

        lock();
        on_exit unlock();

        foreach string type in (exists ptype ? ptype : keys services) {
            foreach string name in (keys services{type}) {
                AbstractQorusCoreService svc = services{type}{name};
                # issue #2734: do not get info if the service has not been initialized yet
                if (!svc.getSetupDone()) {
                    continue;
                }
                l += svc.getInfo(cx);
            }
        }

        return l;
    }

    # returns a hash of services cached keyed by serviceid
    *hash<string, hash<auto>> getCacheHash(*hash<auto> cx) {
        lock();
        on_exit unlock();

        hash<string, hash<auto>> h;

        foreach string type in (keys services) {
            foreach string name in (keys services{type}) {
                AbstractQorusCoreService svc = services{type}{name};
                # issue #2734: do not get info if the service has not been initialized yet
                if (!svc.getSetupDone()) {
                    continue;
                }
                hash<auto> sh = svc.getInfo(cx);
                h.(sh.serviceid) = sh;
            }
        }

        return h;
    }

    *hash<auto> getServiceInfo(string type, string name, *hash<auto> cx) {
        grabServiceRead(type, name);
        on_exit releaseServiceRead(type, name);

        # issue #2734: do not get info if the service has not been initialized yet
        *AbstractQorusCoreService svc = services{type}{name};
        if (exists svc && svc.getSetupDone()) {
            return svc.getInfo(cx);
        }
    }

    bool getAutostartStatus(string type, string name) {
        *hash<auto> info = Qorus.qmm.lookupServiceInfo(type, name);
        if (!info) {
            throw "UNKNOWN-SERVICE", sprintf("no %s service %y can be found", type, name);
        }
        return info.autostart;
    }

    setAutostartStatus(string type, string name, auto status) {
        status = parse_boolean(status);
        *hash<auto> info = Qorus.qmm.lookupServiceInfo(type, name);
        if (!info) {
            throw "UNKNOWN-SERVICE", sprintf("no %s service %y can be found", type, name);
        }

        # update status if necessary
        if (status != info.autostart) {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    sqlif.serviceManagerSetAutostartStatus(status, info.serviceid);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex)) {
                        continue;
                    }
                    rethrow;
                }
                trans.reset();
                break;
            }
        }

        # update internally if possible
        type = type.lwr();

        lock();
        if (services{type}{name}) {
            services{type}{name} += {
                "autostart": status,
                "manual_autostart": True,
            };
        }
        unlock();

        # synchronize change in omqmap
        Qorus.qmm.updateServiceAutostart(info.serviceid, status);

        # load service if not already loaded
        if (status) {
            omqservice{type}{name}.init();
        } else { # otherwise clear SERVICE-NOT-LOADED alert
            Qorus.alerts.clearOngoingAlert("SERVICE", info.serviceid, "SERVICE-NOT-LOADED");
        }
    }

    uiExtensionRegister(QorusExtensionHandler handler, *string url_name) {
        OMQ::AbstractQorusCoreService svc = tld.svc;
        QorusUiExtensionResource er(svc.type, svc.name, url_name ?? svc.getResourceId(), handler);
        svc.addResource(er);
    }

    # always called exclusive access to the service
    private reloadServiceIntern(string type, string name, *string why) {
        *OMQ::AbstractQorusCoreService svc = services{type}{name};

        *hash<auto> opts = svc ? svc.getAllOptions() : NOTHING;

        if (!svc || !svc.getStopping()) {
            unloadServiceUnlocked(type, name, NOTHING, False, True, "unloading service for reset"
                + (why ? ": " + why : ""));
        }

        loadInternal(type, name, False, True, "reload service" + (why ? ": " + why : ""));
        if (opts) {
            services{type}{name}.setOptions(opts);
        }
    }

    private list<hash<string, string>> reloadServicesIntern(*hash<auto> c, string type, *string why) {
        list<hash<string, string>> l = ();

        *list<string> sl;

        {
            lock();
            unlock();

            sl = keys services{type};
        }

        foreach string name in (sl) {
            grabServiceExclusive(type, name, True);
            on_exit releaseServiceExclusive(type ,name);

            # fix for bug 429: reloadServiceIntern() calls loadInternal() which unlocks the lock
            # if an exception in an init() method occurs, the service may have already
            # deregistered itself, so we have to check if the service is still loaded here
            # before processing it
            if (!services{type}{name}) {
                Qorus.logInfo(formatSvcLogMessage(type, name, "service already unloaded, cannot reset"));
                continue;
            }

            l += {
                "type": type,
                "name": name,
            };
            try {
                reloadServiceIntern(type, name, why);
            } catch (hash<ExceptionInfo> ex) {
                Qorus.logInfo(formatSvcLogMessage(type, name, "error resetting service: %s: %s", ex.err, ex.desc));
            }
            if (shutting_down)
                break;
        }

        return l;
    }

    # called with exclusive access to the service
    private OMQ::AbstractQorusCoreService getServiceIntern(string type, string name) {
        # if system shutting down, then throw exception
        if (shutting_down) {
            throw "SERVICE-ACCESS-ERROR", "system is shutting down";
        }

        # no need to wait for services in transition states, because we already have exclusive access

        # if service is not loaded, load it
        return services{type}{name} ?? loadInternal(type, name);
    }

    # called with exclusive access to the service
    private unloadServiceUnlocked(string type, string name, *string version, *bool for_disable, *bool for_reset,
            *string reason) {
        if (tld.svc && (services{type}{name} == tld.svc) && (!version || version == tld.svc.version)) {
            throw "SERVICE-UNLOAD-ERROR", sprintf("service %s.%s cannot delete itself", type, name);
        }

        # we have exclusive access, so the service should not be starting or stopping
        QDBG_ASSERT(!services{type}{name}.starting && (!services{type}{name} || !services{type}{name}.getStopping()));

        if (shutting_down) {
            throw "SERVICE-UNLOAD-ERROR", "can't delete service, system is shutting down";
        }

        if (!services{type}{name}) {
            throw "SERVICE-NOT-LOADED", sprintf("no %s service with name '%s' is loaded", type, name);
        }

        OMQ::AbstractQorusCoreService svc = services{type}{name};

        if (version && version != svc.version) {
            throw "SERVICE-NOT-LOADED", sprintf("%s/%s is not loaded (however %s/%s is loaded)", name, version, name,
                svc.version);
        }

        svc.setStopReason(tld.cx, reason);
        unloadServiceIntern(svc, for_reset);
    }

    # called with exclusive access to the service
    private unloadServiceIntern(OMQ::AbstractQorusCoreService svc, *bool for_reset) {
        string type = svc.type;
        string name = svc.name;

        ServiceThreadContextHelper stch(svc, "stop");

        ActionReason stopreason = svc.getStopReason();

        # see if service is running
        svc.stop(True);

        remove services{type}{name};

        softint sid = svc.serviceid;
        bool as = svc.autostart;

        hash<auto> service_info_hash;
        if (!for_reset && as) {
            service_info_hash = {
                "servicetype": type,
                "name": name,
                "version": svc.version,
            };
        }

        # remove thread local service context if deleting it
        if (tld.svc == svc) {
            remove tld.svc;
        }

        AbstractQorusCoreService::del(svc, self);

        # if not resetting and autostart is set, then raise an ongoing alert
        if (!for_reset && as) {
            Qorus.alerts.raiseOngoingAlert(stopreason, "SERVICE", sid, "SERVICE-NOT-LOADED", service_info_hash);
        }

        qlog(LoggerLevel::INFO, "%s %s service successfully deleted from cache", type, name);

        updated = now_us();
    }

    autoStartAsync() {
        init.inc();
        background autoStartIntern();
    }

    private autoStartIntern() {
        on_exit init.dec();

        try {
            # get hash of services already running
            hash<string, bool> rsvch = Qorus.getRunningServiceHash();

            context (sqlif.serviceManagerAutoStart()) {
                if (shutting_down || Qorus.shutting_down) {
                    olog(LoggerLevel::INFO, "terminating service autostart due to system shutdown");
                    break;
                }

                string type = tolower(%service_type);
                if (rsvch{%serviceid}) {
                    Qorus.logInfo("SVC: %s.%s: skipping autostart for recovered service", type, %name);
                    continue;
                }
                # skip services that are already loaded; locking is done in the loadService() call; here if the
                # service exists, then it was already loaded, whatever state it may be in
                if (services{type}{%name}) {
                    continue;
                }
                Qorus.logInfo("SVC: %s.%s: autostarting service", type, %name);
                try {
                    autoStartServiceTimeout(type, %name, %version, %serviceid);
                } catch (hash<ExceptionInfo> ex) {
                    string desc = sprintf("error autostarting %s service %s: ", type, %name);
                    desc += (Qorus.getDebugSystem() && (ex.err != "GROUP-DISABLED"
                        && (ex.err != "SERVICE-INIT-ERROR" || !ex.err.already_logged)))
                        ? Util::get_exception_string(ex)
                        : sprintf("%s: %s", ex.err, ex.desc);

                    Qorus.logInfo(formatSvcLogMessage(type, %name, desc));
                    # issue #2625: raise an onoing alert for services with the autostart flag set that cannot be started
                    ActionReason stopreason(NOTHING, desc);
                    hash<auto> sh = {
                        "servicetype": type,
                        "name": %name,
                        "version": %version,
                    };
                    Qorus.alerts.raiseOngoingAlert(stopreason, "SERVICE", %serviceid, "SERVICE-NOT-LOADED", sh);
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, "service autostart error: %s", get_exception_string(ex));
        }
    }

    initDone() {
        init.dec();
    }

    private autoStartServiceTimeout(string type, string name, string version, int serviceid) {
        SvcSignaler ss();
        int tid = background autoStartServiceBackground(ss, type, name, version, serviceid);
        if (!ss.wait(10s))
            Qorus.logInfo(formatSvcLogMessage(type, name, "service is taking more than 10 seconds to start; "
                "continuing in the background in TID %d", tid));
    }

    private autoStartServiceBackground(SvcSignaler ss, string type, string name, string version, int serviceid) {
        create_tld();
        on_exit { if (ss.signal()) Qorus.logInfo(formatSvcLogMessage(type, name, "background loading complete"));}

        try {
            loadService(type, name, False, "autostarting service at system startup");
        } catch (hash<ExceptionInfo> ex) {
            string desc = sprintf("error autostarting %s service %s: ", type, name);
            desc += (Qorus.getDebugSystem() && (ex.err != "GROUP-DISABLED"
                && (ex.err != "SERVICE-INIT-ERROR" || !ex.arg.already_logged)))
                ? Util::get_exception_string(ex)
                : sprintf("%s: %s", ex.err, ex.desc);

            Qorus.logInfo(formatSvcLogMessage(type, name, desc));
            # issue #2625: raise an onoing alert for services with the autostart flag set that cannot be started
            ActionReason stopreason(NOTHING, desc);
            hash<auto> sh = {
                "servicetype": type.lwr(),
                "name": name,
                "version": version,
            };
            Qorus.alerts.raiseOngoingAlert(stopreason, "SERVICE", serviceid, "SERVICE-NOT-LOADED", sh);
        }
    }

    waitInit() {
        init.waitForZero();
    }

    waitShutdown() {
        sc.waitForZero();
    }

    # stops all running services
    shutdown(*hash<auto> cx) {
        # no more services can be added after this statement
        shutting_down = True;
        # make sure and not start service shutdown until init has exited
        init.waitForZero();

        # stop all services
        foreach string type in ("user", "system") {
            while (True) {
                *string name = services{type}.firstKey();
                if (!exists name) {
                    break;
                }

                grabServiceExclusive(type, name, True);
                on_exit releaseServiceExclusive(type, name);

                # in case a service exits while the shutdown is in progress
                #printf("keys services.%y: %y\n", type, keys services{type});
                # DEBUG
                #on_error printf("ERROR services.%y: type: %y %y\n", type, services{type}.type(), services{type});

                if (!services{type}{name}) {
                    continue;
                }

                OMQ::AbstractQorusCoreService svc = services{type}{name};

                ServiceThreadContextHelper stch(svc, "stop");

                try {
                    Qorus.logInfo(formatSvcLogMessage(type, name, "unloading service"));

                    svc.setStopReason(cx, "system shutdown");
                    svc.stop(True);

                    # bug 566: the service could have been deleted and removed from the service hash by Service::stop() if it was still being initialized
                    if (!services{type}{name}) {
                        Qorus.logInfo(formatSvcLogMessage(type, name, "service already unloaded"));
                        continue;
                    }

                    remove services{type}{name};

                    # save parameters to log "stopped" message in service log file after service is deleted
                    AbstractQorusCoreService::del(svc, self);
                } catch (hash<ExceptionInfo> ex) {
                    Qorus.logInfo(formatSvcLogMessage(type, name, "exception stopping %s.%s service: %s: %s", type, name, ex.err, ex.desc));
                    if (Qorus.getDebugSystem()) {
                        Qorus.logInfo(formatSvcLogMessage(type, name, Util::get_exception_string(ex)));
                    }
                }
            }
        }
        sc.waitForZero();
        olog(LoggerLevel::INFO, "ServiceManager: all services stopped");
    }

    # must be called with exclusive access to the current service
    private OMQ::AbstractQorusCoreService loadInternal(string type, string name, *bool for_enable, *bool for_reset, *string reason,
            *bool qorus_core_recover, *string uuid) {
        type = type.lwr();

        # we have exclusive access to the service, therefore it cannot be starting or stopping
        QDBG_ASSERT(!services{type}{name}.starting);
        QDBG_ASSERT(!services{type}{name} || !services{type}{name}.getStopping());

        # if the service is loaded, return it
        if (services{type}{name}) {
            return services{type}{name};
        }

        if (shutting_down) {
            throw "SERVICE-ERROR", "can't start service, system is shutting down";
        }

        # create the service
        OMQ::AbstractQorusCoreService svc;

        # step 1: try to find the latest version of the service
        *hash<auto> sq = Qorus.qmm.lookupServiceInfo(type, name, False);
        if (!sq) {
            throw "NO-SERVICE", sprintf("%s service '%s' does not exist", type, name);
        }

        string version = sq.version;

        string dname = name + "/" + version;

        # issue #2732: do not allow user services to start if system limits have been exceeded
        if (type == "user" && !qorus_core_recover) {
            # always allow system services to be loaded
            QorusSharedApi::checkLimits(sprintf("cannot load service %s v%s (%d)", name, version, sq.serviceid));
        }

        # issue #3520: loaded services missing descriptions in REST API
        # rename "description" -> "desc"
        sq.desc = remove sq.description;

        try {
            # check if service can really be started
            Qorus.rbac.canStartService(sq.serviceid);

            bool init_executed;
            {
                # check minimum required versions for system services
                if (type == "system") {
                    *string min_ver = OMQ::MinSystemServiceVersion{name};
                    if (!min_ver) {
                        Qorus.logInfo(formatSvcLogMessage(type, dname, "WARNING: loading unknown system service %s",
                            dname));
                    } else {
                        if (compare_version(min_ver, version) > 0) {
                            throw "SYSTEM-SERVICE-ERROR", sprintf("system service %s version %s cannot be loaded, "
                                "minimum version required is %s, please reload system services using oload and try "
                                "again",
                                name, version, min_ver);
                        }
                    }
                }

                # create service and put in service tree immediately
                svc = sq.remote
                    ? new RemoteQorusService(sc, type, name, uuid, tld.cx, reason)
                    : new Service(sc, type, name, sq.serviceid, sq.version, tld.cx, reason);

                # issue #2734: put service in the hash in the lock
                {
                    lock();
                    on_exit unlock();

                    services{type}{name} = svc;
                }

                on_error {
                    {
                        lock();
                        on_exit unlock();

                        remove services{type}{name};
                    }
                    AbstractQorusCoreService::del(svc, self);
                }

                # log service startup message in system log
                Qorus.logInfo(formatSvcLogMessage(type, name, "loading version %s (serviceid %d); %s", version,
                    sq.serviceid, svc.startreason.getText()));

                # setup the service and open the log file
                # issue #2543: if the service terminates in setup, the error is ignored in qorus-core while when
                # the qsvc process is recovered, it will run its initialization locally, therefore in this case
                # we need to make sure not to run the init() method again from qorus-core
                init_executed = svc.setup(sq, qorus_core_recover, uuid);

                # issue #2734: mark setup done in the lock
                {
                    lock();
                    on_exit unlock();

                    svc.setSetupDone();
                }

                if (shutting_down) {
                    throw "SERVICE-ERROR", "can't start service, system is shutting down";
                }
            }

            # step 3: create service instance object
            omqservice{type}{name} = new ServiceMethodGate(type, name);

            updated = now_us();

            if (!init_executed) {
                try {
                    svc.init(qorus_core_recover);
                } catch (hash<ExceptionInfo> ex) {
                    if (ex.err != "CLIENT-TERMINATED") {
                        try {
                            svc.stop();
                        } catch (hash<ExceptionInfo> dex) {
                            svc.logInfo("%s: %s: %s", get_ex_pos(dex), dex.err, dex.desc);
                        }
                    }
                    {
                        lock();
                        on_exit unlock();

                        # issue #3544: remove the server after it is stopped
                        remove services{type}{name};
                    }

                    # log error locally and throw summary message for logging in qorus-core
                    bool already_logged;
                    if (ex.err != "CLIENT-TERMINATED" && ex.err != "GROUP-DISABLED") {
                        # try to log in the service's log
                        try {
                            svc.logError("%s", get_exception_string(ex));
                        } catch (hash<ExceptionInfo> ex1) {
                            Qorus.logError("%s service %s v%s (%d) initialization error details: %s", type, name,
                                version, sq.serviceid, get_exception_string(ex));
                            already_logged = True;
                        }
                    }

                    # this call deletes the service in the background
                    AbstractQorusCoreService::del(svc, self);
                    # remove the reference in this thread immediately to avoid race conditions below
                    remove svc;

                    # if the remote process died in initialization, throw a PROCESS-START-ERROR
                    if (ex.err == "CLIENT-TERMINATED") {
                        throw "PROCESS-START-ERROR", ex.desc, ex.arg;
                    }

                    if (ex.err == "GROUP-DISABLED") {
                        rethrow;
                    }

                    throw "SERVICE-INIT-ERROR", sprintf("failed to initialize service %s v%s (%d): %s: %s: %s%s",
                        name, version, sq.serviceid, get_ex_pos(ex), ex.err, ex.desc,
                        already_logged ? "" : "; see service log for details"), {
                            "already_logged": True,
                        };
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            string desc = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            Qorus.events.postServiceError(tld.cx, ES_Major, type, name, version, sq.serviceid, "SERVICE-LOAD-ERROR",
                sprintf("error loading service: %s", desc));

            # log error locally and throw summary message for logging in qorus-core
            *bool already_logged = ex.arg.already_logged;
            if (!already_logged && ex.err != "GROUP-DISABLED" && ex.err != "PROCESS-START-ERROR") {
                bool logged_in_service;
                if (svc) {
                    try {
                        svc.logError("%s", get_exception_string(ex));
                        logged_in_service = True;
                    } catch (hash<ExceptionInfo> ex1) {
                        if (ex1.err != "OBJECT-ALREADY-DELETED") {
                            Qorus.logError("%s service %s v%s (%d) error logging setup error: %s", type, name,
                                version, sq.serviceid, get_exception_string(ex));
                        }
                    }
                }
                if (!logged_in_service) {
                    Qorus.logError("%s service %s v%s (%d) init/setup error details: %s", type, name,
                        version, sq.serviceid, get_exception_string(ex));
                    already_logged = True;
                }
            }

            olog(LoggerLevel::INFO, "error loading service: %s", desc);
            # try to log in the service log file, if the log object still exists
            if (!already_logged && svc) {
                try {
                    svc.logInfo("error loading service: %s", desc);
                } catch (hash<ExceptionInfo> ex) {
                    # ignore any exceptions here; the logging attempt is on a best-effort basis
                }
            }

            # raise an ongoing alert if the service can't start and the autostart flag is set
            if (sq.autostart) {
                ActionReason stopreason;
                # the service object may have been deleted above
                if (sq.remote || !svc) {
                    # do not send a message to the remote service here
                    stopreason = new ActionReason();
                    stopreason.setReason(desc);
                } else {
                    svc.setStopReason(desc);
                    stopreason = svc.getStopReason();
                }

                hash<auto> service_info_hash = {
                    "servicetype": sq.type,
                    "name": sq.name,
                    "version": sq.version,
                };

                Qorus.alerts.raiseOngoingAlert(stopreason, "SERVICE", sq.serviceid, "SERVICE-NOT-LOADED",
                    service_info_hash);
            }

            if (ex.err == "CLIENT-TERMINATED") {
                throw "PROCESS-START-ERROR", ex.desc, ex.arg;
            }

            if (ex.err != "GROUP-DISABLED" && (ex.err != "SERVICE-INIT-ERROR" || !ex.arg.already_logged)) {
                throw "SERVICE-INIT-ERROR", sprintf("failed to init/setup service %s v%s (%d): %s: %s: %s%s",
                    name, version, sq.serviceid, get_ex_pos(ex), ex.err, ex.desc,
                    already_logged ? "" : "; see service log for details"), {
                        "already_logged": True,
                    };
            }

            rethrow;
        }

        if (shutting_down) {
            {
                lock();
                on_exit unlock();

                remove services{type}{name};
            }
            AbstractQorusCoreService::del(svc, self);

            throw "SERVICE-ERROR", "can't start service, system is shutting down";
        }

        # start the service if it has a "start()" method
        if (True) {
            try {
                svc.startService(qorus_core_recover);
            } catch (hash<ExceptionInfo> ex) {
                {
                    lock();
                    on_exit unlock();

                    remove services{type}{name};
                }
                AbstractQorusCoreService::del(svc, self);
                if (ex.err == "CLIENT-DEAD") {
                    throw "PROCESS-START-ERROR", ex.desc, ex.arg;
                }
                rethrow;
            }
        }

        Qorus.events.postServiceStart(tld.cx, type, name, version, sq.serviceid);

        # flag service started as complete
        svc.startupDone();

        # clear any SERVICE-NOT-LOADED ongoing alert related to this service
        ActionReason r(tld.cx, sprintf("%s service %s v%s (%d) successfully loaded and initialized", type, name,
            version, svc.serviceid));
        Qorus.alerts.clearOngoingAlert(r, "SERVICE", svc.serviceid, "SERVICE-NOT-LOADED");

        #printf("DEBUG ServiceManager::loadInternal() %s.%s returning %s\n", type, name, dbg_node_info(svc));

        return svc;
    }

    # called from ServiceGate to auto-load services
    loadService(string type, string name, *bool for_enable, *string reason) {
        # wait for recovery
        recovery_cnt.waitForZero();

        bool load = grabServiceToLoad(type, name);
        on_exit releaseServiceToLoad(type, name);

        if (shutting_down) {
            throw "SERVICE-ERROR", "can't start service, system is shutting down";
        }

        if (load) {
            loadInternal(type, name, for_enable, False, reason);
        }
    }

    # this method can only be called from a service method call
    # so no locking is needed
    int startServiceThreadArgs(auto func, auto args) {
        string name = tld.svc.name;
        string type = tld.svc.type;

        return services{type}{name}.startThread(self, func, args);
    }

    list<string> registerSoapListenersRemote(string type, string name, softlist<auto> sl, softstring bind,
            *hash<auto> lh, int family, string rauth, string call,
            hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        RemoteQorusService svc = getRemoteService(type, name);
        ensure_create_tld();
        tld.svc = svc;

        *HttpServer::AbstractAuthenticator auth;

        switch (rauth) {
            case "def":
            case "remote":
            case "none": break;
            default: throw "UNSUPPORTED-AUTHENTICATION", sprintf("unrecognized authentication for SOAP listener; "
                "auth: %y", rauth);
        }

        # deserialize any WebService objects
        foreach auto h in (\sl) {
            # issue #2574 deserialize "wsdl" if it is serialized
            if (h.wsdl._data) {
                h.wsdl = Serializable::deserialize(h.wsdl);
                if (h.wsdl.has_try_import) {
                    h.wsdl.try_import = \svc.getResourceData();
                }
            }
        }

        return registerSoapListenersIntern(sl, bind, lh, family, auth, call, opts);
    }

    private list<string> registerSoapListenersIntern(softlist<auto> sl, softstring bind, *hash<auto> lh,
            int family = AF_UNSPEC, *HttpServer::AbstractAuthenticator auth, string call,
            hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        OMQ::AbstractQorusCoreService svc = tld.svc;

        # ensure that any resources added are stopped and removed if there's an exception
        ServiceResourceHelper rsh(svc);
        on_error
            rsh.rollback();

        # list of SOAP services added to listener
        list<hash<auto>> sll = ();

        foreach auto arg in (sl) {
            if (arg.typeCode() != NT_HASH) {
                throw "REGISTER-SOAP-LISTENER-ERROR", sprintf("expecting a hash argument to %s(); got type %y "
                    "instead (value: %y)", call, arg.type(), arg);
            }
            hash<auto> sh = arg;

            auto wsdl;

            # import options
            hash<auto> ioh;

            # get web service definition
            if (sh.wsdl_resource) {
                wsdl = svc.getResourceData(sh.wsdl_resource);
                ioh.try_import = \svc.getResourceData();
                sh -= "wsdl_resource";
            } else if (sh.wsdl_file) {
                string def_path;
                wsdl = WSDLLib::getWSDL(sh.wsdl_file, NOTHING, NOTHING, \def_path);
                ioh.def_path = def_path;
                sh -= "wsdl_file";
            } else if (sh.wsdl) {
                if (sh.wsdl.typeCode() == NT_STRING && sh.wsdl !~ /^<\?xml/) {
                    string def_path;
                    wsdl = WSDLLib::getWSDL(sh.wsdl, NOTHING, NOTHING, \def_path);
                    ioh.def_path = def_path;
                } else {
                    wsdl = sh.wsdl;
                    ioh.try_import = \svc.getResourceData();
                }
                sh -= "wsdl";
            } else {
                throw "REGISTER-SOAP-LISTENER-ERROR", sprintf("none of required 'wsdl', 'wsdl_file', or "
                    "'wsdl_resource' keys present in the hash argument to %s(); args provided: %y", call, sh);
            }

            WebService w = wsdl instanceof WebService ? wsdl : new WebService(wsdl, sh - "service" + ioh);

            #if (Qorus.getDebugSystem()) olog(LoggerLevel::DEBUG, "registerSoapListener() w: %y", w);

            string service = sh.service ?? w.listServices()[0].name;

            #if (Qorus.getDebugSystem()) olog(LoggerLevel::DEBUG, "registerSoapListener() service: %y", service);

            # create SoapHandler for service
            SoapHandler handler(auth ? auth : Qorus.qorusAuth);

            # register SOAP methods in service
            if (registerSoapServiceIntern(svc, handler, w, service, NOTHING, True)) {
                sll += {
                    "service": service,
                    "handler": handler,
                };
            }
        }

        # start dedicated listener against the service
        lh += {"bind": bind,};

        # do env substitution on cert_path and key_path if present
        if (lh.cert_path) {
            lh.cert_path = OMQ::substitute_env_vars(lh.cert_path);
        }
        if (lh.key_path) {
            lh.key_path = OMQ::substitute_env_vars(lh.key_path);
        }

        # list of resource names as return value
        list<string> rv = ();

        # list of handlers registered to the service
        list<AbstractHttpRequestHandler> handlers();
        map handlers += cast<AbstractHttpRequestHandler>($1.handler), sll;

        # list of HTTP listeners
        # NOTE: duplicate bind operations checked above
        list<auto> llist = bindHttpListenersIntern(svc, lh, opts);

        # add HTTP listeners as resources to service
        foreach hash<auto> lrh in (llist) {
            HttpSoapListenerServiceResource hsr(svc.serviceid, lrh.name, svc.getResourceId(), lrh.id, lrh.desc,
                (map $1.service, sll));
            registerListener(lrh.id, svc, lrh.name);
            svc.addResource(hsr);
            rv += hsr.getName();

            # add SOAP handlers to listener
            int hid = svc.getNextHandlerId();
            # handler names must be unique
            string hname = sprintf("svc-%s-%d", svc.name, hid);
            map Qorus.httpServer.addHandlerToListenerID(lrh.id, hname, <HttpHandlerConfigInfo>{
                "path": $1.service,
                "isregex": False,
                "handler": $1.handler,
            }), sll;
            hsr.addHandlers(handlers);
        }

        if (llist) {
            svc.logInfo("started or reused %d HTTP listener%s for services: %y", llist.size(),
                llist.size() == 1 ? "" : "s", (map $1.service, sll));
        }

        return rv;
    }

    list<string> registerSoapListener(hash<auto> sh, softstring bind, int family = AF_UNSPEC,
            *HttpServer::AbstractAuthenticator auth, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        # remove listener params
        *hash<auto> lh = remove sh{ListenerParams};
        return registerSoapListenersIntern(sh, bind, lh, family, auth, "svc_register_soap_listener", opts);
    }

    list<string> registerSoapListeners(list<auto> sl, softstring bind, *hash<auto> lh, int family = AF_UNSPEC,
            *HttpServer::AbstractAuthenticator auth, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        return registerSoapListenersIntern(sl, bind, lh, family, auth, "svc_register_soap_listeners", opts);
    }

    private bool registerSoapServiceIntern(OMQ::AbstractQorusCoreService svc, SoapHandler handler, WebService ws,
            *softlist<string> service, *string uri_path, bool newapi = False) {
        string st = svc.type;
        string sn = svc.name;

        QDBG_LOG("ServiceManager::registerSoapServiceIntern() %s resource: %y (%y)", svc.name, SoapServiceResource::getResourceName(sn, ws), svc.getServiceResourceNames());

        *SoapServiceResource sr;

        # ensure that any resources added are stopped and removed if there's an exception
        ServiceResourceHelper rsh(svc);
        on_error
            rsh.rollback();

        if (!service) {
            service = ws.listServices()[0].name;
        }

        foreach string name in (service) {
            string path = name;

            svc.logInfo("setting up mapping to SOAP service %y", name);

            hash<auto> svch = ws.getService(name);
            # if there is more than one port, use the first port
            if (!svch.port) {
                throw "WEBSERVICE-ERROR", sprintf("service %y has no ports", name);
            }

            # get the first defined port for the service
            string portname = svch.port.firstValue().binding.getPort();

            # issue #2274 get real URI path for service if necessary & possible
            if (!exists uri_path) {
                # if we have a simple path with no directory separators and no scheme, then the value will be in the "host" field
                # after parse_url()
                hash<auto> h = parse_url(svch.port.firstValue().address);
                uri_path = h.path ?? h.host ?? h.sn;
            }
            # issue #2274 get unique ID for the SOAP service
            string unique_id = sprintf("%s-%s", name, svc.serviceid);

            # find all operations supported by this service
            foreach string opname in (keys ws.portType{portname}.operations) {
                *hash<auto> mh = services{st}{sn}.methods{opname};
                if (!mh) {
                    svc.logError("cannot export %s.%s.%s() as a SOAP method because the method does not exist", st, sn, opname);
                    continue;
                }

                if (mh.internal) {
                    svc.logError("cannot export SOAP operation %s.%s (port %y) as %s.%s.%s(), because the method is internal",
                        name, opname, portname, st, sn, opname);
                    continue;
                }

                WSOperation op = ws.portType{portname}.operations{opname};
                hash<auto> cmark = {
                    "type": st,
                    "name": sn,
                    "method": opname,
                    "newapi": newapi,
                };
                handler.addMethod(ws, op, \soap_service_gate(), NOTHING, 1, cmark, path, \soap_error_gate(), uri_path, NOTHING, unique_id);
                if (handler == Qorus.soapHandler && !sr) {
                    sr = new SoapServiceResource(sn, ws, path, unique_id);
                    svc.addResource(sr);
                }
                svc.logInfo("exported SOAP method: %s.%s.%s()", st, sn, opname);
            }
        }

        return True;
    }

    # the service cannot be deleted while this call is in progress, so no locking is necessary
    registerSoapService(WebService ws, *softlist<string> service, *string uri_path, bool newapi = True) {
        registerSoapServiceIntern(tld.svc, Qorus.soapHandler, ws, service, uri_path, newapi);
    }
}

#! This class passes raw logging events for processing in the service logger
class QorusServiceAppender inherits LoggerAppenderNull {
    private {
        AbstractQorusCoreService svc;
    }

    constructor(AbstractQorusCoreService svc) : LoggerAppenderNull(svc.name) {
        self.svc = svc;
        open();
    }

    bool post(LoggerEvent event) {
        svc.postLogEvent(event);
        return True;
    }
}

*int sub service_audit_user_event_remote(string type, string name, string user_event, *string info1, *string info2) {
    OMQ::AbstractQorusCoreService svc = services.getService(type, name);
    return Qorus.audit.userServiceEvent(tld.cx, svc.a_start, svc.serviceid, user_event, info1, info2);
}

*int sub service_audit_user_event(string user_event, *string info1, *string info2) {
    OMQ::AbstractQorusCoreService svc = tld.svc;
    return Qorus.audit.userServiceEvent(tld.cx, svc.a_start, svc.serviceid, user_event, info1, info2);
}

# lvl, msg
sub oslog(int lvl, string type, string svc, string msg) {
    qlog(lvl, sprintf("SVC: %s.%s: %s", type, svc, vsprintf(msg, argv)));
}

string sub formatSvcLogMessage(string type, string svc, string msg) {
    return sprintf("SVC: %s.%s: %s", type, svc, vsprintf(msg, argv));
}

sub service_log(int lvl, string fmt) {
    slog_args((lvl, fmt) + argv);
}

sub service_log_args(int lvl, string fmt, *softlist<auto> args) {
    slog_args((lvl, fmt) + args);
}

sub slog_args(softlist args) {
    # fix for bug 496: code objects exported from services and called in other contexts will not have thread-local
    # data with the service context
    if (!tld.svc) {
        # fix arguments if necessary (from old code)
        int lvl = args[0].typeCode() == NT_INT ? shift args : LoggerLevel::INFO;
        if (args[0].typeCode() != NT_STRING)
            args[0] = string(args[0]);
        string msg = shift args;
        if (tld.job) {
            cast<OMQ::Job>(tld.job).logArgs(convert_old_log_level(lvl), msg, args);
            return;
        }
        Qorus.logArgs(convert_old_log_level(lvl), msg, args);
    } else {
        #printf("slog() sname: %y, argv: %y\n", tld.sname, argv);
        tld.svc.logArgs(convert_old_log_level(shift args), shift args, args);
    }
}

auto sub soap_service_gate() {
    ensure_create_tld();
    hash<auto> cx = argv[0];
    # for SOAP services registered with "registerSoapHandler()"
    if (cx.cmark.newapi) {
        # remove context from method argument
        shift argv;
    }

    # save soap context in this thread data for calls to getSoapCallContext()
    ThreadLocalData mt();
    mt.tldCopy(tld);
    tld.cx = cx;
    on_exit tld.tldCopy(mt);

    AbstractQorusCoreService svc = services.getService(cx.cmark.type, cx.cmark.name);

    try {
        auto rv = omqservice.(cx.cmark.type).(cx.cmark.name).externalMethodGateArgs(cx.cmark.method, argv);
        #svc.logDebug("SOAP service call: %s(%y) rv: %y", cx.cmark.method, argv, rv);
        return rv;
    } catch (hash<ExceptionInfo> ex) {
        string desc = !Qorus.getDebugSystem() ? ex.desc : get_exception_string(ex);
        svc.logInfo("exception in SOAP service call: %s: %s: %s", get_ex_pos(ex), ex.err, desc);
        rethrow;
    }
}

sub soap_error_gate(hash<auto> cx, hash<auto> ex) {
    AbstractQorusCoreService svc = services.getService(cx.cmark.type, cx.cmark.name);
    string desc = !Qorus.getDebugSystem() ? ex.desc : Util::get_exception_string(ex);
    svc.logInfo("exception in SOAP service call: %s: %s: %s", get_ex_pos(ex), ex.err, desc);
}

*string sub get_current_user() {
}

# API call serving loaded service to set service options
sub qorus_api_service_set_option(hash<auto> h) {
    Qorus.qmm.updateServiceOptionsErr(tld.svc.serviceid, h);
}

# FIXME: document
auto sub qorus_api_service_get_option() {
    return qorus_api_service_get_option_args(argv);
}

auto sub qorus_api_service_get_option_args(*softlist<auto> args) {
    *hash<auto> h = Qorus.qmm.getOptionsWithContextArgs("service", tld.svc.serviceid, args);
    return args.size() == 1
        ? h.firstValue()
        : h;
}
