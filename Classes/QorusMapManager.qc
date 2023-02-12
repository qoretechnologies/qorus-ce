# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%push-parse-options
%new-style

hashdecl SlaMapEventInfo {
    int slaid;
    number value;
    string producer;
    softint success;
    *string err;
    *string errdesc;
    *Counter confirm;
}

hashdecl SlaMapEventAdminInfo {
    int waiting = 0;
    int events = 1;
}

const SlaUnits = (
    "seconds": True,
    "other": True,
);

hashdecl EditMapInfo {
    int cid;
    string tab_token;
}

hashdecl ReservationInfo {
    string type;
    string name;
    *string version;
}

#! Web IDE errors
const WEBIDE_ERROR_INVALID_VALUE = "INVALID-VALUE";
const WEBIDE_ERROR_NAME_RESERVED = "NAME-RESERVED";
const WEBIDE_ERROR_NAME_VERSION_RESERVED = "NAME-VERSION-RESERVED";
const WEBIDE_ERROR_NAME_EXISTS = "NAME-EXISTS";
const WEBIDE_ERROR_NAME_VERSION_EXISTS = "NAME-VERSION-EXISTS";
const WEBIDE_ERROR_VERSION_TOO_LOW = "VERSION-TOO-LOW";
const WEBIDE_ERROR_INVALID_TYPE = "INVALID-TYPE";

#! Object types that support code
const CodeObjectMap = {
    "class": True,
    "job": True,
    "step": True,
    "service": True,
};

class OMQ::QorusMapManager inherits OMQ::QorusMapManagerBase {
    public {
        const CommonMetadata = {
            "name": {
                "type": {
                    Type::String: True,
                },
                "required": True,
            },
            "description": {
                "type": {
                    Type::String: True,
                },
                "required": True,
            },
            "tags": {
                "type": {
                    Type::Hash: True,
                },
            },
        };

        const CommonVersionMetadata = CommonMetadata + {
            "version": {
                "type": {
                    Type::String: True,
                },
                "required": True,
            },
        };

        const CodeMetadata = {
            "author": {
                "type": {
                    Type::String: True,
                },
            },
            "base_class_name": {
                "type": {
                    Type::String: True,
                },
                "subtype": "identifier",
            },
            "language": {
                "type": {
                    Type::String: True,
                },
                "required": True,
                "default_value": "qore",
            },
        };

        const InterfaceCodeMetadata = CodeMetadata + {
            "class_name": {
                "type": {
                    Type::String: True,
                },
                "subtype": "identifier",
            },
        };

        const CommonInterfaceMetadata = CommonVersionMetadata + InterfaceCodeMetadata + {
            "classes": {
                "type": {
                    Type::List: True,
                },
            },
            "config_items": {
                "type": {
                    Type::List: True,
                },
            },
            "enabled": {
                "type": {
                    Type::Boolean: True,
                },
                "required": True,
                "default_value": True,
            },
            "fsms": {
                "type": {
                    Type::List: True,
                },
            },
            "groups": {
                "type": {
                    Type::List: True,
                },
            },
            "id": {
                "type": {
                    Type::Int: True,
                },
                # NOTE: required is not set here, as the ID has special handling in any case
            },
            "mappers": {
                "type": {
                    Type::List: True,
                },
            },
            "modules": {
                "type": {
                    Type::List: True,
                },
            },
            "remote": {
                "type": {
                    Type::Boolean: True,
                },
                "required": True,
            },
            "stack-size": {
                "type": {
                    Type::Int: True,
                },
            },
            "vmaps": {
                "type": {
                    Type::List: True,
                },
            },
        };

        const JobMetadata = CommonInterfaceMetadata + {
            "active": {
                "type": {
                    Type::Boolean: True,
                },
                "default_value": True,
            },
            "expiry_date": {
                "type": {
                    Type::Date: True,
                },
            },
            "run_skipped": {
                "type": {
                    Type::Boolean: True,
                },
                "default_value": False,
            },
            "schedule": {
                "type": {
                    Type::Hash: True,
                },
                "required": True,
            },
        };

        const ClassMetadata = CommonVersionMetadata + CodeMetadata + {
            "requires": {
                "type": {
                    Type::List: True,
                },
            },
        };

        const ConnectionMetadata = CommonMetadata + {
            "url": {
                "type": {
                    Type::String: True,
                },
                "required": True,
            },
            "options": {
                "type": {
                    Type::Hash: True,
                },
            },
        };

        #! Map of objects that have unique names (other objects are unique with the name and version)
        const UniqueNameMap = {
            "connection": True,
            "fsm": True,
            "group": True,
            "job": True,
            "pipeline": True,
            "queue": True,     #!< workflow step async queue
            "event": True,     #!< workflow step event type
        };
    }

    private {
        #! RWLock for all objects
        RWLock map_mutex();

        # map of slaids -> serviceid -> method name -> True
        hash<string, hash<string, hash<string, bool>>> sla_mmap();
        # map of serviceid -> method names = SLA ID
        hash<string, hash<string, int>> sla_rmmap();

        # map of slaids -> jobid -> True
        hash<string, hash<string, bool>> sla_jmap();
        # map of jobid -> SLA ID
        hash<string, int> sla_rjmap();

        # map of process ID -> hash<auto>
        hash<string, hash<auto>> pmap;

        # map of plugin name -> True
        hash<string, bool> plugin_map;

        # map of fsm dependencies; type {workflow|service|job} -> id -> fsm name
        hash<string, hash<string, string>> fsm_ix_deps;

        # SLA thread counter
        Counter slac();
        # SLA event queue
        Queue slaq();
        # SLA event bulk insert operation object
        BulkInsertOperation sla_event_insert;

        # SLA event hash keyed by slaid
        hash<string, hash<SlaMapEventAdminInfo>> slaeh();
        # SLA event flush hash
        hash<string, int> slafh();
        # SLA event condition (uses the "map_mutex" RWLock)
        Condition sla_cond();

        # hash of paths provided by modules; these paths cannot be deleted with the API
        hash<string, bool> locked_type_map;

        # for edit locks: type -> id -> {tab_token, cid}
        /** each "type" key hash is accessed under the lock for that type
        */
        hash<string, hash<string, hash<EditMapInfo>>> edit_map;

        # for name reservations for simple objects identified by name only: type -> name -> tab_token
        hash<string, hash<string, string>> reserved_names;

        #! For mapping tab_tokens to name reservations; keys are tab_token values
        hash<string, hash<ReservationInfo>> reservation_map;

        # for name reservations for complex objects identified by name and version
        /** type -> name -> version -> tab_token
        */
        hash<string, hash<string, hash<string, string>>> reserved_names_version;

        # maximum amount of time between DB synchronizations with SLA event information in milliseconds
        const SlaMaxSyncMs = 30s.durationMilliseconds();
        # special SLA ID for flushing all events to disk
        const SLA_Flush = -1;
        # special SLA ID for requeueing SLA events in the SLA event thread
        const SLA_Requeue = -2;

        # config item type map to convert Qore types to config item types
        const ConfigItemTypeMap = {
            Type::Int: "int",
            Type::Number: "float",
            Type::NothingType: NOTHING,
        };
    }

    private:internal {
        # to wait for initialization to be complete before quitting to address a race condition
        # and also to wait for map calls while initializing to address another race condition related to
        # qorus-core restarts
        Mutex init_lck();
        Condition init_cond();
        int init_waiting;
        bool init_done;

        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        Mutex workflow_reload_lock();
        Mutex service_reload_lock();
        Mutex job_reload_lock();
        Mutex constant_reload_lock();
        Mutex class_reload_lock();
        Mutex function_reload_lock();
        Mutex step_reload_lock();
        Mutex queue_reload_lock();
        Mutex sla_reload_lock();
        Mutex event_reload_lock();
        Mutex mapper_reload_lock();
        Mutex vmap_reload_lock();
        Mutex config_reload_lock();
        Mutex pipeline_reload_lock();
        Mutex fsm_reload_lock();

        const ConfigItemStarTypes = {
            "*int": True,
            "*string": True,
            "*bool": True,
            "*float": True,
            "*date": True,
            "*hash": True,
            "*list": True,
            "any": True
        };

        const ConnectionKeys = (
            "name", "desc", "url", "tags", "opts",
        );
    }

    destructor() {
        init_lck.lock();
        on_exit init_lck.unlock();
        if (!init_done) {
            initDoneIntern();
        }
    }

    RWLock getMapLock() {
        return map_mutex;
    }

    private:internal initDone() {
        init_lck.lock();
        on_exit init_lck.unlock();
        initDoneIntern();
    }

    private:internal initDoneIntern() {
        init_done = True;
        if (init_waiting) {
            init_cond.broadcast();
        }
    }

    waitForInit() {
        init_lck.lock();
        on_exit init_lck.unlock();
        while (!init_done) {
            ++init_waiting;
            init_cond.wait(init_lck);
            --init_waiting;
        }
    }

    init() {
        on_exit initDone();

        # initialize type cache
        type_cache = DataProvider::getTypeCache();
        # setup locked types
        locked_type_map = map {$1: True}, type_cache.listTypes();

        olog(LoggerLevel::INFO, "loading configuration metadata from DB");
        date now = now_us();

        reloadTypes(NOTHING, True);
        reloadConfigItemValues();
        reloadConstants();
        reloadClasses();
        reloadFunctions();
        reloadQueues();
        reloadPipelines();
        reloadFsms();
        reloadSteps();
        reloadSlas();
        reloadEvents();
        reloadMappers(NOTHING, True);
        reloadVMaps();
        reloadWorkflows(NOTHING, True);
        reloadServices(NOTHING, True);
        reloadJobs(NOTHING, True);
        reloadLoggers(True);

        olog(LoggerLevel::INFO, "configuration loaded in: %y", now_us() - now);

        # initialize SLA event bulk insert operation object
        {
            hash<auto> opts = {
                "block_size": Qorus.options.get("sla-max-events"),
                "info_log": \slaLog(),
            };
            sla_event_insert = new BulkInsertOperation(Qorus.dsmanager.getOmqTable("sla_events"), opts);
        }
        # start SLA thread
        slac.inc();
        on_error slac.dec();
        background slaThread();
    }

    shutdown() {
        # wait for map initialization to be complete before stopping the SLA thread
        waitForInit();
        slaq.push();
        slac.waitForZero();
    }

    OmqMap getOmqMap() {
        return omqmap;
    }

    # must use locking to support atomic updates
    updateProcess(hash<auto> info) {
        # in case info as a ClusterProcInfo hash, we have to create a new object
        if (info.queue_urls) {
            # rename keys
            info = (info - "queue_urls") + {
                "urls": info.queue_urls,
            };
        }

        map_mutex.writeLock();
        on_exit map_mutex.writeUnlock();

        pmap{info.id} = info;
    }

    # must use locking to support atomic updates
    removeProcess(string id) {
        map_mutex.writeLock();
        on_exit map_mutex.writeUnlock();

        remove pmap{id};
    }

    updateProcessMemory(string id, hash<auto> h) {
        map_mutex.writeLock();
        on_exit map_mutex.writeUnlock();

        if (pmap{id}) {
            pmap{id} += h{"status", "status_string", "priv", "rss", "vsz", "priv_str", "pct",};
        }
    }

    # no locking; only atomic operations are performed on pmap
    hash<string, hash<auto>> getProcessMap() {
        return pmap;
    }

    # no locking; only atomic operations are performed on pmap
    *hash<auto> lookupProcess(string id) {
        return pmap{id};
    }

    # no locking; only atomic operations are performed on pmap
    *hash<auto> getWorkflowProcess(softstring id) {
        *hash<auto> wfh = omqmap.wfmap{id};
        if (!wfh) {
            return;
        }
        return pmap{qwf_get_process_name(wfh.name, wfh.version, id)};
    }

    # no locking; only atomic operations are performed on pmap
    *hash<auto> getServiceProcess(softstring id) {
        *hash<auto> sh = omqmap.servicemap{id};
        if (!sh) {
            return;
        }
        return pmap{qsvc_get_process_name(sh.type, sh.name, sh.version, id)};
    }

    # no locking; only atomic operations are performed on pmap
    *list<hash<auto>> getServiceProcesses(softstring id) {
        *hash<auto> sh = omqmap.servicemap{id};
        if (!sh) {
            return;
        }
        string pfx = qsvc_get_process_name(sh.type, sh.name, sh.version, id, "X");
        pfx =~ s/X$//g;
        return map $1.value, pmap.pairIterator(), !$1.key.comparePartial(pfx);
    }

    # no locking; only atomic operations are performed on pmap
    *hash<auto> getJobProcess(softstring id) {
        *hash<auto> jh = omqmap.jmap{id};
        if (!jh) {
            return;
        }
        return pmap{qjob_get_process_name(jh.name, jh.version, id)};
    }

    private:internal static slaLog(string fmt) {
        qlog(LoggerLevel::INFO, "SLA Events: %s", vsprintf(fmt, argv));
    }

    private:internal slaThread() {
        on_exit slac.dec();

        # millisecond timestamp of first unflushed event
        int dt;
        # queue timeout interval; 0 = no timeout
        int timeout_ms = 0;

        QorusRestartableTransaction trans();
        while (True) {
            *hash<SlaMapEventInfo> h;
            try {
                h = slaq.get(timeout_ms);
                # an empty message on the queue means flush & exit
                if (!h)
                    break;
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err != "QUEUE-TIMEOUT")
                    rethrow;
            }

            if (h && h.slaid != SLA_Requeue) {
                # process flush messages
                if (h.slaid == SLA_Flush) {
                    slaCommit(trans);
                    h.confirm.dec();
                    delete dt;
                    timeout_ms = 0;
                    continue;
                }

                # increment flush hash count
                ++slafh{h.slaid};

                # if this is the first unflushed event, then save the timestamp
                if (!sla_event_insert.size())
                    dt = clock_getmillis();

                # queue event with a restartable transaction in case of a flush
                try {
                    # this is an atomic operation with a single row in case of transaction restarts
                    sla_event_insert.queueData(h);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the commit if necessary
                    if (trans.restartTransaction(ex)) {
                        slaCommit(trans);
                    } else {
                        rethrow;
                    }
                }
            }

            # if we have data in the buffer, then calculate the next timeout
            if (sla_event_insert.size()) {
                timeout_ms = (Qorus.options.get("sla-max-sync-secs") * 1000) - (clock_getmillis() - dt);
                # if we have reached the max sync interval, then flush the buffer to DB & commit
                if (timeout_ms <= 0) {
                    slaCommit(trans);
                    delete dt;
                    timeout_ms = 0;
                }
            } else if (h && h.slaid != SLA_Requeue) {
                # if the buffer has been flushed, then delete the timeout
                # commit the transaction after a flush
                slaCommit(trans);
                delete dt;
                timeout_ms = 0;
            }
        }
        slaCommit(trans);
    }

    # flush and commit SLA event cache; restart transaction if necessary
    private:internal slaCommit(QorusRestartableTransaction trans) {
        while (True) {
            try {
                sla_event_insert.commit();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                qlog(LoggerLevel::ERROR, "SLA thread exiting with an unexpected error: %s: %s", ex.err, ex.desc);
                rethrow;
            }
            trans.reset();
            break;
        }

        # process event counts
        WriteLockHelper wlh(map_mutex);
        foreach hash<auto> h in (slafh.pairIterator()) {
            slaeh{h.key}.events -= h.value;
            QDBG_ASSERT(slaeh{h.key}.events >= 0);
            # if all events have been flushed and we have a waiting thread, then signal it to continue
            if (!slaeh{h.key}.events) {
                if (slaeh{h.key}.waiting) {
                    sla_cond.broadcast();
                } else {
                    delete slaeh{h.key};
                }
            }
            delete slafh{h.key};
        }
    }

    # called by the QorusMapManagerClient in remote processes, returns maps needed
    DataProviderTypeCache getTypeCache() {
        return type_cache;
    }

    hash<auto> getWorkflowMaps() {
        ReadLockHelper rlh(map_mutex);
        return omqmap{"wfmap", "wfrmap", /*"wfids"*/};
    }

    *hash<auto> getWorkflowMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.wfmap;
    }

    *hash<auto> getWorkflowMapUnlocked() {
        return omqmap.wfmap;
    }

    *hash<auto> getLoggerMap() {
        AutoReadLock arl(map_mutex);
        return omqmap.loggerMap;
    }

    *hash<auto> getLoggerAliases() {
        AutoReadLock arl(map_mutex);
        return omqmap.loggerAliases;
    }

    *hash<auto> getLoggerMaps() {
        AutoReadLock arl(map_mutex);
        return omqmap{"loggerMap", "loggerAliases"};
    }

    *hash<auto> getLoggerWfMap() {
        AutoReadLock arl(map_mutex);
        return omqmap.logger_wfmap;
    }

    *hash<auto> getWorkflowRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.wfrmap;
    }

    *list<auto> getWorkflowIds() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.wfids;
    }

    *list<auto> getWorkflowIdsFromName(string name) {
        ReadLockHelper rlh(map_mutex);

        return (map $1.workflowid, (omqmap.wfrmap{name} - ("lvcreated", "lastversion")).iterator());
    }

    *hash<auto> getLoggerSvcMap() {
        AutoReadLock arl(map_mutex);
        return omqmap.logger_svcmap;
    }

    *hash<auto> getServiceMap(bool verbose = True) {
        *hash h;
        {
            ReadLockHelper rlh(map_mutex);
            h = omqmap.servicemap;
        }
        if (h && verbose)
            Qorus.rbac.addServiceGroupInfo(h);
        return h;
    }

    *hash<auto> getServiceRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.servicermap;
    }

    *hash<auto> getServiceAMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.serviceamap;
    }

    *list<auto> getServiceIds() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.svcids;
    }

    *list<auto> getSystemServiceIds() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.systemserviceids;
    }

    *list<auto> getUserServiceIds() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.userserviceids;
    }

    *list<auto> getServiceIdsFromName(string type, string name) {
        type = type.upr();
        ReadLockHelper rlh(map_mutex);

        return (map $1.serviceid, (omqmap.servicermap{type}{name} - ("lvcreated", "lastversion")).iterator());
    }

    *hash<auto> getLoggerJobMap() {
        AutoReadLock arl(map_mutex);
        return omqmap.logger_jobmap;
    }

    *hash<auto> getJobMap(bool verbose = True) {
        *hash h;
        {
            ReadLockHelper rlh(map_mutex);
            h = omqmap.jmap;
            if (h && verbose) {
                map h{$1.key}.edit_lock = edit_map.job{$1.value.jobid}.cid, h.pairIterator(),
                    edit_map.job{$1.value.jobid};
            }
        }
        if (h && verbose)
            Qorus.rbac.addJobGroupInfo(h);
        return h;
    }

    *hash<auto> getJobRMap(bool verbose = True) {
        *hash h;
        {
            ReadLockHelper rlh(map_mutex);
            h = omqmap.jrmap;
            if (h && verbose) {
                map h{$1.key}.edit_lock = edit_map.job{$1.value.jobid}.cid, h.pairIterator(),
                    edit_map.job{$1.value.jobid};
            }
        }
        if (h && verbose)
            Qorus.rbac.addJobGroupInfoByName(h);
        return h;
    }

    *list<string> listTypes() {
        return type_cache.listTypes();
    }

    *list<auto> getJobIds() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.jobids;
    }

    #! Adds a new type to the cache
    /** @return the normalized path
    */
    string addOrReplaceType(string path, AbstractDataProviderType type) {
        path = QorusDataProviderTypeHelper::normalizeTypePath(path);
        type_cache.registerOrReplaceType(path, type);
        Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateTypes", path);
        return path;
    }

    #! Removes a type from the cache
    *AbstractDataProviderType removeType(string path) {
        path = QorusDataProviderTypeHelper::normalizeTypePath(path);
        *AbstractDataProviderType type = type_cache.removeType(path);
        if (type) {
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateTypes", path);
        }
        return type;
    }

    #! Returns True if the type is locked
    bool isTypeLocked(string path) {
        return locked_type_map{QorusDataProviderTypeHelper::normalizeTypePath(path)} ?? False;
    }

    #! Returns all locked types
    list<string> getLockedTypes() {
        return keys locked_type_map;
    }

    *hash<auto> lookupWorkflow(softstring wfid, *softbool verbose) {
        *hash<auto> h;
        {
            ReadLockHelper rlh(map_mutex);
            h = omqmap.wfmap{wfid};
            if (h && verbose) {
                getWorkflowStepInfoUnlocked(\h);
            }
        }
        return h;
    }

    *hash<auto> lookupWorkflowUnlocked(softstring wfid, *softbool verbose) {
        *hash<auto> h = omqmap.wfmap{wfid};
        if (h && verbose) {
            getWorkflowStepInfoUnlocked(\h);
        }
        return h;
    }

    # issue #3621: allow filtering of records based on tags
    static *list<hash<auto>> filterList(*list<hash<auto>> l, hash<auto> filter) {
        if (!filter.tags) {
            return l;
        }
        list<hash<auto>> rv = ();
        foreach hash<auto> rec in (l) {
            foreach hash<auto> i in (rec.tags{keys filter.tags}.pairIterator()) {
                if (filter.tag_case_insensitive) {
                    if (filter.tag_partial_match) {
                        if (i.value.upr().find(filter.tags{i.key}.upr()) >= 0) {
                            rv += rec;
                            break;
                        }
                    } else if (i.value.upr() == filter.tags{i.key}.upr()) {
                        rv += rec;
                        break;
                    }
                } else if (filter.tag_partial_match) {
                    if (i.value.find(filter.tags{i.key}) >= 0) {
                        rv += rec;
                        break;
                    }
                } else if (i.value == filter.tags{i.key}) {
                    rv += rec;
                    break;
                }
            }
        }
        return rv;
    }

    # issue #3621: allow filtering of records based on tags
    static *hash<auto> filterHash(*hash<auto> h, hash<auto> filter) {
        if (!filter.tags) {
            return h;
        }
        hash<auto> rv;
        foreach hash<auto> i in (h.pairIterator()) {
            foreach hash<auto> ri in (i.value.tags{keys filter.tags}.pairIterator()) {
                if (filter.tag_case_insensitive) {
                    if (filter.tag_partial_match) {
                        if (ri.value.upr().find(filter.tags{ri.key}.upr()) >= 0) {
                            rv{i.key} = i.value;
                            break;
                        }
                    } else if (ri.value.upr() == filter.tags{ri.key}.upr()) {
                        rv{i.key} = i.value;
                        break;
                    }
                } else if (filter.tag_partial_match) {
                    if (ri.value.find(filter.tags{ri.key}) >= 0) {
                        rv{i.key} = i.value;
                        break;
                    }
                } else if (ri.value == filter.tags{ri.key}) {
                    rv{i.key} = i.value;
                    break;
                }
            }
        }
        return rv;
    }

    list<hash<auto>> getWorkflowList(*softbool with_deprecated, *hash<auto> filter) {
        # create list with only workflows the user is allowed to access, also filter out deprecated workflows if necessary
        list<hash<auto>> l = ();

        {
            ReadLockHelper rlh(map_mutex);
            foreach hash<auto> wfh in (omqmap.wfmap.iterator()) {
                if ((!with_deprecated && wfh."deprecated"))
                    continue;

                # add process info
                *hash<auto> ph = getWorkflowProcess(wfh.workflowid);
                if (ph) {
                    wfh.process = ph;
                }

                l += wfh;
            }

            foreach hash<auto> wfh in (\l) {
                try {
                    getWorkflowStepInfoUnlocked(\wfh);
                } catch (hash<ExceptionInfo> ex) {
                    qlog(LoggerLevel::INFO, "%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                }
            }
        }

        # issue #3621: allow filtering of records based on tags
        return filter ? filterList(l, filter) : l;
    }

    *hash<auto> rLookupWorkflow(string name) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.wfrmap{name};
    }

    *hash<auto> rLookupWorkflow(string name, string version) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.wfrmap{name}{version};
    }

    list<auto> getProgramList(*softbool with_deprecated) {
        # get local program interfaces being debuggable
        *hash<auto> pgms = map {$1.getScriptName(): True}, ProgramControl::getAllPrograms(),
            ($1.getParseOptions() & PO_NO_DEBUGGING) == 0;
        list<hash<auto>> l = ();
        {
            ReadLockHelper rlh(map_mutex);
            foreach hash<auto> h in (omqmap.wfmap.iterator()) {
                hash<auto> pi = {
                    "type": "workflow",
                    "id": h.workflowid,
                    "name": h.name,
                    "version": h.version,
                    "remote": h.remote,
                    "pgmname": sprintf("%s:%s", h.name, h.version),
                };
                if (pi.remote) {
                    *hash<auto> ph = pmap{qwf_get_process_name(pi.name, pi.version, pi.id)};
                    if (!ph) {
                        continue;
                    }
                    pi.processid = ph.id;
                } else {
                    if (!pgms{pi.pgmname}) {
                        continue;
                    }
                }

                l += pi;
            }

            foreach hash<auto> h in (omqmap.jmap.iterator()) {
                hash<auto> pi = {
                    "type": "job",
                    "id": h.jobid,
                    "name": h.name,
                    "version": h.version,
                    "remote": h.remote,
                    "pgmname": sprintf("%s:%s", h.name, h.version),
                };
                if (pi.remote) {
                    *hash<auto> ph = pmap{qjob_get_process_name(pi.name, pi.version, pi.id)};
                    if (!ph) {
                        continue;
                    }
                    pi.processid = ph.id;
                } else {
                    if (!pgms{pi.pgmname}) {
                        continue;
                    }
                }

                l += pi;
            }

            foreach hash<auto> h in (omqmap.servicemap.iterator()) {
                hash<auto> pi = {
                    "type": "service-"+h.type,
                    "id": h.serviceid,
                    "name": h.name,
                    "version": h.version,
                    "remote": h.remote,
                    "pgmname": sprintf("%s:%s", h.name, h.version),
                };
                if (pi.remote) {
                    *hash<auto> ph = pmap{qsvc_get_process_name(h.type, pi.name, pi.version, pi.id)};
                    if (!ph) {
                        continue;
                    }
                    pi.processid = ph.id;
                } else {
                    if (!pgms{pi.pgmname}) {
                        continue;
                    }
                }

                l += pi;
            }
        }

        return l;
    }

    /** returns a hash with the following keys:
        - \c options: a hash of the options set with the values set
        - \c errs: a list of strings of errors
    */
    hash<auto> updateJobOptions(softint jobid, hash<auto> opts) {
        hash<auto> options;
        list<string> errs;

        WriteLockHelper wlh(map_mutex);
        foreach hash<auto> i in (opts.pairIterator()) {
            options{i.key} = i.value;
            *string err = updateInterfaceOptionIntern("jmap", "job", jobid, i.key, \options{i.key});
            if (err) {
                errs += err;
                continue;
            }
        }

        return {
            "options": options,
            "errs": errs,
        };
    }

    #! Returns the given options with an override for the given interface
    *hash<auto> getOptionsWithContext(string ctx, softstring id) {
        return getOptionsWithContextArgs(ctx, id, argv);
    }

    #! Returns the given options with an override for the given interface
    *hash<auto> getOptionsWithContextArgs(string ctx, softstring id, *list<auto> args) {
        string mapname;

        switch (ctx) {
            case "workflow":
                mapname = "wfmap";
                break;

            case "service":
                mapname = "servicemap";
                break;

            case "job":
                mapname = "jmap";
                break;

            default:
                throw "INVALID-CONTEXT", sprintf("interface context %y unknown", ctx);
        }

        *hash<auto> rv = args
            ? Qorus.options.get(args)
            : Qorus.options.get();
        ReadLockHelper rlh(map_mutex);
        if (!omqmap{mapname}{id}) {
            throw "UNKNOWN-" + ctx.upr(), sprintf("%s ID %y is unknown", ctx, id);
        }
        rv += args
            ? omqmap{mapname}{id}."runtime-options"{args}
            : omqmap{mapname}{id}."runtime-options";
        return rv;
    }

    # returns the value actually set, throws a \c WORKFLOW-OPTION-ERROR exception if there are any errors
    auto updateWorkflowOptionErr(softint wfid, softstring opt, auto val) {
        auto orig_val = val;
        on_success {
            if (orig_val !== val) {
                Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateWorkflowCache");
            }
        }

        *string err = updateInterfaceOption("wfmap", "workflow", wfid, opt, \val);
        if (err) {
            throw "WORKFLOW-OPTION-ERROR", err;
        }
        return val;
    }

    # returns the values actually set, throws a \c WORKFLOW-OPTION-ERROR exception if there are any errors
    *hash<auto> updateWorkflowOptionsErr(softint wfid, hash<auto> opts) {
        bool updated;
        on_success {
            if (updated) {
                Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateWorkflowCache");
            }
        }

        *hash<auto> rv;
        WriteLockHelper wlh(map_mutex);
        foreach hash<auto> i in (opts.pairIterator()) {
            rv{i.key} = i.value;
            *string err = updateInterfaceOptionIntern("wfmap", "workflow", wfid, i.key, \rv{i.key});
            if (err) {
                throw "WORKFLOW-OPTION-ERROR", err;
            }
            if (!updated && rv{i.key} !== i.value) {
                updated = True;
            }
            if (!exists rv{i.key}) {
                remove rv{i.key};
            }
        }
        return rv;
    }

    # returns the value actually set, throws a \c SERVICE-OPTION-ERROR exception if there are any errors
    auto updateServiceOptionErr(softint svcid, softstring opt, auto val) {
        *string err = updateInterfaceOption("servicemap", "service", svcid, opt, \val);
        if (err) {
            throw "SERVICE-OPTION-ERROR", err;
        }
        return val;
    }

    # returns the values actually set, throws a \c SERVICE-OPTION-ERROR exception if there are any errors
    *hash<auto> updateServiceOptionsErr(softint svcid, hash<auto> opts) {
        *hash<auto> rv;
        WriteLockHelper wlh(map_mutex);
        foreach hash<auto> i in (opts.pairIterator()) {
            rv{i.key} = i.value;
            *string err = updateInterfaceOptionIntern("servicemap", "service", svcid, i.key, \rv{i.key});
            if (err) {
                throw "SERVICE-OPTION-ERROR", err;
            }
            if (!exists rv{i.key}) {
                remove rv{i.key};
            }
        }
        return rv;
    }

    # returns the value actually set, throws a \c JOB-OPTION-ERROR exception if there are any errors
    auto updateJobOptionErr(softint jobid, softstring opt, auto val) {
        *string err = updateInterfaceOption("jmap", "job", jobid, opt, \val);
        if (err) {
            throw "JOB-OPTION-ERROR", err;
        }
        return val;
    }

    # returns the values actually set, throws a \c JOB-OPTION-ERROR exception if there are any errors
    *hash<auto> updateJobOptionsErr(softint jobid, hash<auto> opts) {
        *hash<auto> rv;
        WriteLockHelper wlh(map_mutex);
        foreach hash<auto> i in (opts.pairIterator()) {
            rv{i.key} = i.value;
            *string err = updateInterfaceOptionIntern("jmap", "job", jobid, i.key, \rv{i.key});
            if (err) {
                throw "JOB-OPTION-ERROR", err;
            }
            if (!exists rv{i.key}) {
                remove rv{i.key};
            }
        }
        return rv;
    }

    # returns the value actually set, throws a \c JOB-OPTION-ERROR exception if there are any errors
    auto updateJobOptionFromNameErr(string name, softstring opt, auto val) {
        WriteLockHelper wlh(map_mutex);
        *int jobid = omqmap.jrmap{name}.jobid;
        if (!jobid) {
            throw "UNKNOWN-JOB", sprintf("job name %y is unknown", name);
        }
        *string err = updateInterfaceOptionIntern("jmap", "job", jobid, opt, \val);
        if (err) {
            throw "JOB-OPTION-ERROR", err;
        }
        return val;
    }

    # returns the values actually set, throws a \c JOB-OPTION-ERROR exception if there are any errors
    *hash<auto> updateJobOptionsFromNameErr(string name, hash<auto> opts) {
        *hash<auto> rv;
        WriteLockHelper wlh(map_mutex);
        *int jobid = omqmap.jrmap{name}.jobid;
        if (!jobid) {
            throw "UNKNOWN-JOB", sprintf("job name %y is unknown", name);
        }
        foreach hash<auto> i in (opts.pairIterator()) {
            rv{i.key} = i.value;
            *string err = updateInterfaceOptionIntern("jmap", "job", jobid, i.key, \rv{i.key});
            if (err) {
                throw "JOB-OPTION-ERROR", err;
            }
        }
        return rv;
    }

    private *string updateInterfaceOption(string mapname, string type, softint id, softstring opt, reference<auto> val) {
        WriteLockHelper wlh(map_mutex);

        return updateInterfaceOptionIntern(mapname, type, id, opt, \val);
    }

    private *string updateInterfaceOptionIntern(string mapname, string type, softint id, softstring opt, reference<auto> val) {
        QDBG_LOG("QorusMapManager::updateInterfaceOptionIntern() map: %y type: %y id: %y %s = %y", mapname, type, id, opt, val);
        reference ix = \omqmap{mapname}{id};

        if (!ix) {
            throw "UNKNOWN-" + type.upr(), sprintf("%s ID %y is unknown", type, id);
        }

        if (!ix.options{opt} && !OMQ::omq_option_hash{opt}) {
            return sprintf("invalid / unknown option %y", opt);
        }

        if (OMQ::omq_option_hash{opt}) {
            if (!OMQ::omq_option_hash{opt}{type}) {
                return sprintf("invalid system option %y: this option cannot be overridden at the %s level", opt, type);
            }

            val = Qorus.options.processOptionValue(opt, val, OMQ::omq_option_hash, type, True);
        }

        # reference to runtime option hash
        reference roh = \omqmap{mapname}{id}."runtime-options";

        # handle configured and unconfigured options differently
        # see bugs 915, 918, 938, 1148
        if (exists omqmap{mapname}{id}.options{opt}) {
            # option is part of the workflow configuration
            if (roh{opt} !== val) {
                sqlif.updateInterfaceOption(type, id, opt, val);
                QDBG_LOG("QorusMapManager::updateInterfaceOption() UPDATE %s.%s.%s = %y", type, id, opt, val);
            }
        } else {
            # option is an unconfigured option
            if (roh.hasKey(opt)) {
                # runtime value already exists; we must either update or delete
                if (exists val) {
                    if (roh{opt} !== val) {
                        sqlif.updateInterfaceOption(type, id, opt, val);
                        QDBG_LOG("QorusMapManager::updateInterfaceOption() UPDATE %s.%s.%s = %y", type, id, opt, val);
                    }
                } else {
                    sqlif.deleteInterfaceOption(type, id, opt);
                    QDBG_LOG("QorusMapManager::updateInterfaceOption() DELETE %s.%s.%s", type, id, opt);
                }
            } else if (exists val) {
                # bug 1148 - only insert if we are setting a value
                # runtime value does not exist; we must insert
                sqlif.insertInterfaceOption(type, id, opt,
                    (OMQ::omq_option_hash{opt}
                        ? OMQ::omq_option_hash{opt}.desc
                        : "added at runtime without a description"),
                    False, val);
                QDBG_LOG("QorusMapManager::updateInterfaceOption() INSERT %s.%s.%s = %y", type, id, opt, val);
            }
        }

        if (exists val) {
            roh{opt} = val;
            # synchronize twinned map if necessary
            if (mapname == "jmap") {
                omqmap.jrmap{omqmap.jmap{id}.name}."runtime-options"{opt} = val;
            }
        } else {
            # delete
            remove roh{opt};
            # synchronize twinned map if necessary
            if (mapname == "jmap") {
                remove omqmap.jrmap{omqmap.jmap{id}.name}."runtime-options"{opt};
            }
        }
    }

    setWorkflowEnabled(softstring workflowid, bool enabled) {
        # issue #2239: may be called with the write lock held when changing workflow remote status
        bool lck = !map_mutex.writeLockOwner();
        *AutoWriteLock al = lck ? new AutoWriteLock(map_mutex) : NOTHING;

        reference whr = \omqmap.wfmap{workflowid};
        if (!whr) {
            qlog(LoggerLevel::ERROR, "workflowid %d has disappeared", workflowid);
            return;
        }

        whr.enabled = enabled;
        omqmap.wfrmap.(whr.name).(whr.version).enabled = enabled;
    }

    setWorkflowDeprecated(softstring workflowid, bool dep) {
        WriteLockHelper wlh(map_mutex);

        reference whr = \omqmap.wfmap{workflowid};
        if (!whr) {
            qlog(LoggerLevel::ERROR, "workflowid %d has disappeared", workflowid);
            return;
        }
        whr.deprecated = dep;
        omqmap.wfrmap.(whr.name).(whr.version).deprecated = dep;

        if (dep) {
            whr += {
                "autostart": 0,
                "manual_autostart": True,
            };
            omqmap.wfrmap.(whr.name).(whr.version) += {
                "autostart": 0,
                "manual_autostart": True,
            };
        }
    }

    setWorkflowAutostart(softstring workflowid, int autostart) {
        hash<auto> info_hash;
        {
            WriteLockHelper wlh(map_mutex);

            reference whr = \omqmap.wfmap{workflowid};
            if (!whr) {
                qlog(LoggerLevel::ERROR, "workflowid %d has disappeared", workflowid);
                return;
            }
            # do not issue any event if there is no change
            if (autostart == whr.autostart) {
                return;
            }
            whr.autostart = autostart;
            omqmap.wfrmap.(whr.name).(whr.version).autostart = autostart;
            info_hash = whr{"name", "version"};
        }
        # issue #2725 issue WORKFLOW_UPDATED event
        Qorus.events.postWorkflowUpdated(tld.cx, info_hash.name, info_hash.version, workflowid, {"autostart": autostart});
    }

    *list<string> getInvalidWorkflowIdsFromHash(*hash h) {
        ReadLockHelper rlh(map_mutex);

        return select keys h, !omqmap.wfmap.$1;
    }

    *list<string> getInvalidServiceIdsFromHash(*hash h) {
        ReadLockHelper rlh(map_mutex);

        return select keys h, !omqmap.servicemap.$1;
    }

    *list<string> getInvalidJobIdsFromHash(*hash h) {
        ReadLockHelper rlh(map_mutex);

        return select keys h, !omqmap.jmap.$1;
    }

    *hash<auto> lookupServiceMethod(softstring servicemethodid) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.servicemethodmap{servicemethodid};
    }

    *hash<auto> lookupService(softstring serviceid, bool verbose = True) {
        *hash<auto> sh;
        {
            ReadLockHelper rlh(map_mutex);

            sh += omqmap.servicemap{serviceid};
        }
        if (sh && verbose) {
            sh += {
                "groups": Qorus.rbac.getServiceGroups(sh.serviceid),
            };
        }
        return sh;
    }

    *hash<auto> rLookupService(string type, string name) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.servicermap.(type.upr()){name};
    }

    # returns the serviceid corresponding to the service name and version given
    *int rLookupService(string type, string name, string version) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.servicermap.(type.upr()){name}{version};
    }

    *hash<auto> rLookupServiceInfo(string type, string name, string version) {
        ReadLockHelper rlh(map_mutex);
        *int id = omqmap.servicermap.(type.upr()){name}{version};
        if (!id) {
            return;
        }
        return omqmap.servicemap{id};
    }

    *hash<auto> rLookupServiceMethodInfo(string name, string version, string method) {
        ReadLockHelper rlh(map_mutex);
        *int id = omqmap.servicermap.SYSTEM{name}{version} ?? omqmap.servicermap.USER{name}{version};
        if (!id) {
            return;
        }
        # get method ID
        hash<auto> info = omqmap.servicemap{id};
        id = info.method_name_map{method};
        if (!method) {
            return;
        }
        return info.methods{id};
    }

    *hash<auto> lookupServiceInfo(string type, string name, bool verbose = True) {
        *hash<auto> sh;
        {
            ReadLockHelper rlh(map_mutex);

            sh += omqmap.servicermap.(type.upr()){name};
            if (!sh)
                return;
            sh += omqmap.servicemap.(sh.serviceid);
        }
        if (sh && verbose) {
            sh += {
                "groups": Qorus.rbac.getServiceGroups(sh.serviceid),
            };
        }
        return sh;
    }

    setServiceEnabled(softstring serviceid, bool enabled) {
        # may be called with the write lock held when changing service remote status
        bool lck = !map_mutex.writeLockOwner();
        *AutoWriteLock al = lck ? new AutoWriteLock(map_mutex) : NOTHING;

        reference<hash<auto>> shr = \omqmap.servicemap{serviceid};
        if (!shr) {
            qlog(LoggerLevel::ERROR, "serviceid %d has disappeared", serviceid);
            return;
        }

        shr.enabled = enabled;
    }

    updateServiceAutostart(softstring serviceid, bool autostart) {
        hash<auto> info_hash;
        {
            WriteLockHelper wlh(map_mutex);

            reference<hash<auto>> shr = \omqmap.servicemap{serviceid};
            if (!shr) {
                qlog(LoggerLevel::ERROR, "serviceid %d has disappeared", serviceid);
                return;
            }

            # do not issue any event if there is no change
            if (autostart == shr.autostart) {
                return;
            }
            shr += {
                "autostart": autostart,
                "manual_autostart": True,
            };
            info_hash = shr{"type", "name", "version"};
        }

        # issue #2725 issue SERVICE_UPDATED event
        Qorus.events.postServiceUpdated(tld.cx, info_hash.type, info_hash.name, info_hash.version, serviceid,
            {"autostart": autostart});
    }

    int getServiceId(string type, string name, *string version) {
        type = toupper(type);

        ReadLockHelper rlh(map_mutex);

        *hash<auto> svc = omqmap.servicermap{type}{name};
        if (!svc)
            throw "SERVICE-ERROR", sprintf("service type=%n name=%n does not exist", type, name);

        if (!exists version || version.empty())
            return int(svc.(svc.lastversion));

        if (!exists svc{version})
            throw "SERVICE-ERROR", sprintf("service type=%n name=%n version=%n does not exist", type, name, version);

        return int(svc{version});
    }

    private:internal *hash<auto> getLoggerIdForInterface(string type, auto id, *bool direct_only) {
        QDBG_ASSERT(type);
        if (!id.val()) {
            return;
        }

        *hash<auto> ix_info;
        # interface info
        switch (type) {
            case "workflows": ix_info = lookupWorkflow(id); break;
            case "services": ix_info = lookupService(id); break;
            case "jobs": ix_info = lookupJob(id); break;
            # is called before the DatasourceManager exists when Qorus is started
            case "qdsp": {
                if (Qorus.dsmanager) {
                    ix_info = Qorus.dsmanager.getLoggerInfo(id);
                } else {
                    # when initializing, the "omq" datasource logger params must be retrieved from
                    # info seeded from qorus-master
                    QDBG_ASSERT(id == "omq");
                    ix_info = {
                        "loggerid": Qorus.getInitialOmqLoggerId() ?? omqmap.loggerMap.qdsp.loggerid,
                    };
                }
                break;
            }
            default: throw "INVALID-INTERFACE", sprintf("invalid logger interface type %y (ID %y); expected one "
                "of: %y", type, id, keys InterfaceLoggers);
        }
        if (!ix_info) {
            throw "INVALID-INTERFACE", sprintf("%s: invalid ID: %y", type, id);
        }
        return ix_info;
    }

    /** Return logger info from the type and the optional interface ID

        @param type the logger type (e.g. services/workflows/jobs) or system type (audit/http/system etc)
        @param id optional interface ID
        @param direct_only if True then only the given logger is looked up, no fallback to system

        @return found logger
    */
    *hash<auto> lookupLogger(string type, auto id, *bool direct_only) {
        QDBG_ASSERT(type);

        # first map ID to an interface configuration
        *hash<auto> ix_info = getLoggerIdForInterface(type, id, direct_only);

        *hash<auto> logger;
        {
            AutoReadLock arl(map_mutex);
            if (ix_info.loggerid) {
                logger = omqmap.loggerMap{ix_info.loggerid};
                if (logger) {
                    logger.isDefault = False;
                }
            } else {
                logger = omqmap.loggerMap{omqmap.loggerAliases{type}};
                if (logger) {
                    logger.isDefault = InterfaceLoggersWithSystem{type} ?? False;
                }
            }

            if (!logger && SystemLoggers{type} && !direct_only) {
                logger = omqmap.loggerMap{omqmap.loggerAliases.system};
                if (logger) {
                    logger.isDefault = True;
                }
            }
        }

        return logger;
    }

    *hash<auto> lookupJob(softstring jid, bool verbose = True) {
        *hash<auto> jh;
        {
            ReadLockHelper rlh(map_mutex);
            jh = omqmap.jmap{jid};
            if (jh) {
                *int edit_lock = edit_map.job{jid}.cid;
                if (edit_lock) {
                    jh.edit_lock = edit_lock;
                }
            }
        }
        if (jh && verbose)
            jh += {"groups": Qorus.rbac.getJobGroups(jh.jobid)};

        return jh;
    }

    *hash<auto> rLookupJob(string name, bool verbose = True) {
        *hash<auto> jh;
        {
            ReadLockHelper rlh(map_mutex);
            jh = omqmap.jrmap{name};
            if (jh) {
                *int edit_lock = edit_map.job{jh.jobid}.cid;
                if (edit_lock) {
                    jh.edit_lock = edit_lock;
                }
            }
        }
        if (jh && verbose) {
            jh += {"groups": Qorus.rbac.getJobGroups(jh.jobid)};
        }

        return jh;
    }

    hash<auto> lookupJobEx(softstring jid) {
        ReadLockHelper rlh(map_mutex);
        *hash<auto> jh = omqmap.jmap{jid};
        if (!jh)
            throw "JOB-ERROR", sprintf("jobid %d does not exist", jid);
        return jh;
    }

    *hash<auto> rLookupJobEx(string name) {
        ReadLockHelper rlh(map_mutex);
        *hash<auto> jh = omqmap.jrmap{name};
        if (!jh)
            throw "JOB-ERROR", sprintf("job %y does not exist", name);
        return jh;
    }

    softint getJobId(string name) {
        ReadLockHelper rlh(map_mutex);
        *hash job = omqmap.jrmap{name};
        if (!job)
            throw "JOB-ERROR", sprintf("job %y does not exist", name);
        return job.jobid;
    }

    string getJobName(softint jobid) {
        ReadLockHelper rlh(map_mutex);
        *hash job = omqmap.jmap{jobid};
        if (!job)
            throw "JOB-ERROR", sprintf("jobid %d does not exist", jobid);

        return job.name;
    }

    setJobEnabled(softstring jobid, bool enabled) {
        # may be called with the write lock held when changing job remote status
        bool lck = !map_mutex.writeLockOwner();
        *AutoWriteLock al = lck ? new AutoWriteLock(map_mutex) : NOTHING;

        reference jhr = \omqmap.jmap{jobid};
        if (!jhr) {
            qlog(LoggerLevel::ERROR, "jobid %d has disappeared", jobid);
            return;
        }

        jhr.enabled = enabled;
        omqmap.jrmap{jhr.name}.enabled = enabled;
    }

    updateJobExpiry(softstring jobid, *date expiry) {
        bool updated;
        reference jhr;
        {
            WriteLockHelper wlh(map_mutex);

            jhr = \omqmap.jmap{jobid};
            if (!jhr) {
                qlog(LoggerLevel::ERROR, "jobid %d has disappeared", jobid);
                return;
            }

            if (jhr.expiry_date != expiry) {
                jhr.expiry_date = expiry;
                omqmap.jrmap{jhr.name}.expiry_date = expiry;

                updated = True;
            }
        }

        if (updated) {
            # issue #2725 issue JOB_UPDATED event
            Qorus.events.postJobUpdated(tld.cx, jhr.name, jhr.version, jobid, {"expiry_date": expiry});
        }
    }

    # issue 1830: return the updated job description hash
    *hash<auto> updateJobSchedule(softstring jobid, string schedule, string minutes, string hours, string days,
            string months, string dow) {
        hash<auto> uh = {
            "minute": minutes,
            "hour": hours,
            "day": days,
            "month": months,
            "wday": dow,
            "schedule": schedule,
        };

        bool updated;
        reference jhr;
        {
            WriteLockHelper wlh(map_mutex);

            jhr = \omqmap.jmap{jobid};
            if (!jhr) {
                qlog(LoggerLevel::ERROR, "jobid %d has disappeared", jobid);
                return;
            }

            # issue #2725 only issue an event if there is an update
            if (jhr.schedule != uh.schedule) {
                jhr += uh;
                delete jhr.recurring;
                omqmap.jrmap{jhr.name} += uh;
                delete omqmap.jrmap{jhr.name}.recurring;

                updated = True;
            }
        }

        if (updated) {
            # issue #2725 issue JOB_UPDATED event
            uh.sched_txt = remove uh.schedule;
            uh.sched_type = "cron";
            Qorus.events.postJobUpdated(tld.cx, jhr.name, jhr.version, jobid, uh);
        }

        return jhr;
    }

    # issue 1830: return the updated job description hash
    *hash<auto> updateJobRecurring(softstring jobid, int recurring) {
        bool updated;
        reference jhr;
        {
            WriteLockHelper wlh(map_mutex);

            jhr = \omqmap.jmap{jobid};
            if (!jhr) {
                qlog(LoggerLevel::ERROR, "jobid %d has disappeared", jobid);
                return;
            }

            # issue #2725 only issue an event if there is an update
            if (jhr.recurring != recurring) {
                jhr.recurring = recurring;
                jhr -= ("minute", "hour", "day", "month", "wday", "schedule");
                omqmap.jrmap{jhr.name}.recurring = recurring;
                omqmap.jrmap{jhr.name} -= ("minute", "hour", "day", "month", "wday", "schedule");

                updated = True;
            }
        }

        if (updated) {
            # issue #2725 issue JOB_UPDATED event
            hash<auto> update_hash = {
                "sched_type": "recurring",
                "recurring": recurring,
            };
            Qorus.events.postJobUpdated(tld.cx, jhr.name, jhr.version, jobid, update_hash);
        }

        return jhr;
    }

    # issue 1820: update the last_executed date in the internal cache for jobs so that this info (which is used in various places) is up to date
    updateJobTimestamps(softstring jobid, date last_executed, *date next, *int last_executed_jiid) {
        WriteLockHelper wlh(map_mutex);

        reference jhr = \omqmap.jmap{jobid};
        if (!jhr) {
            qlog(LoggerLevel::ERROR, "jobid %d has disappeared", jobid);
            return;
        }

        hash updates = {
            "next": next,
            "last_executed": last_executed,
            "last_executed_job_instanceid": last_executed_jiid,
        };

        jhr += updates;
        omqmap.jrmap{jhr.name} += updates;
    }

    setJobActive(softstring jobid, bool active) {
        hash<auto> info_hash;
        {
            WriteLockHelper wlh(map_mutex);

            reference jhr = \omqmap.jmap{jobid};
            if (!jhr) {
                qlog(LoggerLevel::ERROR, "jobid %d has disappeared", jobid);
                return;
            }

            if (active != jhr.active) {
                # issue #2815: do not allow expired jobs to be set to active
                if (active && jhr.expiry_date && jhr.expiry_date <= now_us()) {
                    throw "JOB-ERROR", sprintf("cannot set expired job %s v%s (%d) to active; job expired on %y",
                        jhr.name, jhr.version, jobid, jhr.expiry_date);
                }

                jhr.active = active;
                jhr.manual_active = True;
                omqmap.jrmap{jhr.name}.active = active;
                omqmap.jrmap{jhr.name}.manual_active = True;
                info_hash = jhr{"name", "version"};
            }
        }

        if (info_hash) {
            # issue #2725 issue JOB_UPDATED event
            Qorus.events.postJobUpdated(tld.cx, info_hash.name, info_hash.version, jobid, {"active": active});
        }
    }

    *hash<auto> getAuthLabels(int serviceid) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.servicemap{serviceid}.authlabels;
    }

    *hash<auto> getAuthLabel(int serviceid, string auth_label_id) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.servicemap{serviceid}.authlabels{auth_label_id};
    }

    hash<auto> getAuthLabelMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.authlabelmap;
    }

    *list workflowList() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.wfids;
    }

    *list serviceList() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.svcids;
    }

    *list jobList() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.jobids;
    }

    # called by the QorusMapManagerClient in remote processes, returns maps needed
    hash<auto> getLibMaps() {
        ReadLockHelper rlh(map_mutex);
        return omqmap{LibMaps};
    }

    *hash<auto> getStepMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.stepmap;
    }

    *hash<auto> getStepRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.steprmap;
    }

    *hash<auto> getFunctionMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.functionmap;
    }

    *hash<auto> getFunctionRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.functionrmap;
    }

    *hash<auto> getConstantMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.constmap;
    }

    *hash<auto> getConstantRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.constrmap;
    }

    *hash<auto> getClassMap(*bool verbose) {
        #QDBG_LOG("QorusMapManager::getClassMap() verbose: %y edit_map: %y stack: %N", verbose, edit_map,
        #    get_stack());
        ReadLockHelper rlh(map_mutex);
        *hash<auto> h = omqmap.classmap;
        if (h && verbose) {
            map h{$1.key}.edit_lock = $1.value.cid, edit_map."class".pairIterator(), h{$1.key};
        }
        return h;
    }

    *hash<auto> getClassRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.classrmap;
    }

    hash<auto> getClassMaps() {
        ReadLockHelper rlh(map_mutex);
        return omqmap{"classmap", "classrmap"};
    }

    # called by the QorusMapManagerClient in remote processes, returns maps needed
    hash<auto> getEventMaps() {
        ReadLockHelper rlh(map_mutex);
        return omqmap{"emap", "ermap"};
    }

    *hash<auto> getEventMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.emap;
    }

    *hash<auto> getEventRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.ermap;
    }

    # called by the QorusMapManagerClient in remote processes, returns maps needed
    hash<auto> getQueueMaps() {
        ReadLockHelper rlh(map_mutex);
        return omqmap{"qmap", /*"qrmap"*/};
    }

    *hash<auto> getQueueMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.qmap;
    }

    *hash<auto> getQueueRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.qrmap;
    }

    *hash<string, hash<SlaInfo>> getSlaMap() {
        *hash<string, hash<SlaInfo>> rv;
        {
            ReadLockHelper rlh(map_mutex);
            rv = omqmap.slamap;
        }
        if (rv)
            addSlaMapInfo(\rv);

        return rv;
    }

    *hash<string, hash<SlaInfo>> getSlaRMap() {
        *hash<string, hash<SlaInfo>> rv;
        {
            ReadLockHelper rlh(map_mutex);
            rv = omqmap.slarmap;
        }
        if (rv)
            addSlaMapInfo(\rv);

        return rv;
    }

    *hash<auto> getSlaMaps() {
        ReadLockHelper rlh(map_mutex);
        return {
            "sla_rjmap": sla_rjmap,
        };
    }

    private addSlaMapInfo(reference<hash<string, hash<SlaInfo>>> rv) {
        {
            ReadLockHelper rlh(map_mutex);
            foreach string key in (keys rv) {
                # see if there are any service methods attached to this SLA
                *hash<string, hash<string, bool>> smmap = sla_mmap{rv{key}.slaid};
                foreach string svcid in (keys smmap) {
                    hash sh = omqmap.servicemap{svcid};
                    foreach string mname in (keys smmap{svcid}) {
                        rv{key}.methods += <SlaServiceMethodInfo>{
                            "serviceid": svcid.toInt(),
                            "type": sh.type,
                            "service_name": sh.name,
                            "service_methodid": sh.method_name_map{mname},
                            "method_name": mname,
                        };
                    }
                }
            }
        }

        {
            ReadLockHelper rlh(map_mutex);
            # add info for any jobs attached to this SLA
            foreach string key in (keys rv) {
                map rv{key}.jobs += <SlaJobInfo>{
                    "jobid": $1.toInt(),
                    "name": omqmap.jmap{$1}.name,
                }, keys sla_jmap{rv{key}.slaid};
            }
        }
    }

    *hash<auto> getMapperMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.mmap;
    }

    *hash<auto> getMapperMapSubset(*list<auto> ids) {
        if (!ids)
            return;
        ReadLockHelper rlh(map_mutex);
        return omqmap.mmap{ids};
    }

    *hash<auto> getMapperRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.mrmap;
    }

    # called by the QorusMapManagerClient in remote processes, returns maps needed
    hash<auto> getVMapMaps() {
        ReadLockHelper rlh(map_mutex);
        return omqmap{"vmmap", "vmrmap"};
    }

    *hash<auto> getVMapMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.vmmap;
    }

    *hash<auto> getVMapRMap() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.vmrmap;
    }

    *hash<auto> lookupVMap(softstring id, *softbool verbose) {
        *hash<auto> h;
        {
            ReadLockHelper rlh(map_mutex);
            h += omqmap.vmmap{id};
        }
        if (h && verbose)
            h += {"groups": Qorus.rbac.getVMapGroups(h.id)};
        return h;
    }

    *hash<auto> rLookupVMap(string name, *softbool verbose) {
        *hash h;
        {
            ReadLockHelper rlh(map_mutex);
            h = omqmap.vmmap{omqmap.vmrmap{name}};
        }
        if (h && verbose)
            h += ("groups": Qorus.rbac.getVMapGroups(h.id));
        return h;
    }

    softint vmapId(string name) {
        ReadLockHelper rlh(map_mutex);

        *softint id = omqmap.vmrmap{name};
        if (!id)
            throw "VALUE-MAP-ERROR", sprintf("value map %y does not exist", name);

        return id;
    }

    *list<auto> getVMapIds() {
        ReadLockHelper rlh(map_mutex);
        return map $1.toInt(), keys omqmap.vmmap;
    }

    *hash<auto> lookupEvent(softstring eid) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.emap{eid};
    }

    *hash<auto> rLookupEvent(string name) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.ermap{name};
    }

    *hash<auto> lookupQueue(softstring qid) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.qmap{qid};
    }

    *hash<auto> rLookupQueue(string name) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.qrmap{name};
    }

    *hash<SlaInfo> lookupSla(softstring slaid) {
        *hash<SlaInfo> rv;
        {
            ReadLockHelper rlh(map_mutex);
            rv = omqmap.slamap{slaid};
        }
        if (rv)
            addSlaInfo(\rv);
        return rv;
    }

    *hash<SlaInfo> rLookupSla(string name) {
        *hash<SlaInfo> rv;
        {
            ReadLockHelper rlh(map_mutex);
            rv = omqmap.slarmap{name};
        }
        if (rv)
            addSlaInfo(\rv);
        return rv;
    }

    private addSlaInfo(reference<hash<SlaInfo>> rv) {
        {
            ReadLockHelper rlh(map_mutex);
            # see if there are any service methods attached to this SLA
            *hash<string, hash<string, bool>> smmap = sla_mmap{rv.slaid};
            foreach string svcid in (keys smmap) {
                hash sh = omqmap.servicemap{svcid};
                foreach string mname in (keys smmap{svcid}) {
                    rv.methods += cast<hash<SlaServiceMethodInfo>>((
                        "serviceid": svcid.toInt(),
                        "type": sh.type,
                        "service_name": sh.name,
                        "service_methodid": sh.method_name_map{mname},
                        "method_name": mname,
                    ));
                }
            }
        }
        {
            ReadLockHelper rlh(map_mutex);
            # add info for any jobs attached to this SLA
            map rv.jobs += cast<hash<SlaJobInfo>>((
                "jobid": $1.toInt(),
                "name": omqmap.jmap{$1}.name,
            )), keys sla_jmap{rv.slaid};
        }
    }

    # returns the SLA ID
    int createSla(string name, string units, string description) {
        WriteLockHelper wlh(map_mutex);
        if (*hash slah = omqmap.slarmap{name}) {
            if (slah.units == units && slah.description == description)
                return slah.slaid;
            throw "SLA-ERROR", sprintf("SLA %y already exists with slaid %d", name, slah.slaid);
        }

        softint slaid;

        # create row in table first
        {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    slaid = sqlif.insertSla(name, units, description);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }
        qlog(LoggerLevel::INFO, "created SLA %d: %y (%s): %s", slaid, name, units, description);
        hash<SlaInfo> h((
            "slaid": slaid,
            "name": name,
            "units": units,
            "description": description,
        ));
        omqmap.slarmap{name} = h;
        omqmap.slamap{slaid} = h;
        return slaid;
    }

    # returns False if the SLA does not exist and the event was not posted
    bool postSlaEventSuccess(int slaid, number val, string producer) {
        ReadLockHelper rlh(map_mutex);
        if (!omqmap.slamap{slaid}) {
            return False;
        }
        # push on queue for later synchronization to the DB
        postSlaEventIntern(slaid, val, producer, True);
        return True;
    }

    # returns False if the SLA does not exist and the event was not posted
    bool postSlaEventSuccess(string sla, number val, string producer) {
        ReadLockHelper rlh(map_mutex);
        *hash h = omqmap.slarmap{sla};
        if (!h) {
            return False;
        }
        # push on queue for later synchronization to the DB
        postSlaEventIntern(h.slaid, val, producer, True);
        return True;
    }

    # returns False if the SLA does not exist and the event was not posted
    bool postSlaEventError(int slaid, number val, string producer, string err, string errdesc) {
        ReadLockHelper rlh(map_mutex);
        if (!omqmap.slamap{slaid}) {
            return False;
        }
        # push on queue for later synchronization to the DB
        postSlaEventIntern(slaid, val, producer, False, err, errdesc);
        return True;
    }

    # returns False if the SLA does not exist and the event was not posted
    bool postSlaEventError(string sla, number val, string producer, string err, string errdesc) {
        ReadLockHelper rlh(map_mutex);
        *hash h = omqmap.slarmap{sla};
        if (!h) {
            return False;
        }
        # push on queue for later synchronization to the DB
        postSlaEventIntern(h.slaid, val, producer, False, err, errdesc);
        return True;
    }

    # flushes all pending events to disk and returns after the data has been committed
    flushSlaEvents() {
        Counter cnt(1);
        slaq.push(new hash<SlaMapEventInfo>(("slaid": SLA_Flush, "confirm": cnt)));
        cnt.waitForZero();
    }

    # requeues pending events
    requeueSlaEvents() {
        slaq.push(new hash<SlaMapEventInfo>(("slaid": SLA_Requeue)));
    }

    private postSlaEventIntern(int slaid, number val, string producer, bool success, *string err, *string errdesc) {
        if (!slaeh{slaid})
            slaeh{slaid} = new hash<SlaMapEventAdminInfo>();
        else
            ++slaeh{slaid}.events;
        # push on queue for later synchronization to the DB
        slaq.push(new hash<SlaMapEventInfo>(("slaid": slaid, "value": val, "producer": producer, "success": success, "err": err, "errdesc": errdesc)));
    }

    deleteSla(int slaid) {
        # flush events before deleting
        flushSlaEvents();

        *hash<SlaInfo> h;
        {
            WriteLockHelper wlh(map_mutex);
            {
                # 1: remove SLA from SLA to method map in the write lock
                # 1.a: remove SLA from forward map
                *hash<string, hash<string, bool>> h0 = remove sla_mmap{slaid};
                # 1.b: remove SLA from reverse map
                foreach hash<auto> sh in (h0.pairIterator())
                    map remove sla_rmmap{sh.key}.$1, keys sh.value;
            }

            {

                # 2: remove SLA from SLA to job map in the write lock
                # 2.a: remove SLA from forward map
                *hash<string, bool> h0 = remove sla_jmap{slaid};
                # 2.b: remove SLA from reverse map
                map remove sla_rjmap.$1, keys h0;
            }

            # 3: update internal cache
            h = omqmap.slamap{slaid};
            if (!h)
                throw "SLA-ERROR", sprintf("cannot delete unknown SLA with slaid %d", slaid);

            # 3.a: delete the SLA entry in the write lock
            remove omqmap.slamap{slaid};
            remove omqmap.slarmap{h.name};

            # 3.b: wait for all affected SLA events to be flushed to the DB
            while (slaeh{slaid}.events) {
                ++slaeh{slaid}.waiting;
                sla_cond.wait(map_mutex);
                --slaeh{slaid}.waiting;
            }
            # 3.c: delete SLA event hash entry
            if (slaeh{slaid}) {
                QDBG_ASSERT(!slaeh{slaid}.events);
                QDBG_ASSERT(!slaeh{slaid}.waiting);
                delete slaeh{slaid};
            }
        }

        # 4: delete the data in the DB
        # count of events deleted
        int ecnt;
        # count of service methods updated
        int smcnt;
        # count of jobs updated
        int jcnt;
        {
            AbstractTable sla = Qorus.dsmanager.getOmqTable("sla");
            AbstractTable service_methods = Qorus.dsmanager.getOmqTable("service_methods");
            AbstractTable jobs = Qorus.dsmanager.getOmqTable("jobs");
            AbstractTable sla_events = Qorus.dsmanager.getOmqTable("sla_events");

            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    # delete all SLA events
                    ecnt = sla_events.del(("slaid": slaid));
                    # delete SLA from service methods
                    smcnt = service_methods.update({"slaid": NOTHING}, {"slaid": slaid});
                    # delete SLA from jobs
                    jcnt = jobs.update({"slaid": NOTHING}, {"slaid": slaid});
                    # delete SLA
                    sla.del({"slaid": slaid});
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }
        qlog(LoggerLevel::INFO, "deleted SLA %d: %y events: %d updated service methods: %d updated jobs: %d", slaid, h.name, ecnt, smcnt, jcnt);
        qlog(LoggerLevel::INFO, "deleted SLA %d: %y (%s): %s", slaid, h.name, h.units, h.description);
    }

    # assumes that the slaid (if any) has been verified before the call
    bool setMethodSla(string name, string method, *int slaid) {
        # 1: verify service name & method and get serviceid and methodid
        int serviceid;
        int methodid;
        {
            ReadLockHelper rlh(map_mutex);
            *hash h = omqmap.servicermap.USER{name};
            if (!h)
                throw "SLA-ERROR", sprintf("user service %y is unknown", name);
            serviceid = h.serviceid;
            h = omqmap.servicemap{serviceid};
            *int mid = h.method_name_map{method};
            if (!mid)
                throw "SLA-ERROR", sprintf("user service %y has no method %y", name, method);
            methodid = mid;
        }

        # 2: update DB
        {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    AbstractTable service_methods = Qorus.dsmanager.getOmqTable("service_methods");
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    service_methods.update(("slaid": slaid), ("service_methodid": methodid));
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        bool rv;

        # 3: update the internal cache
        {
            WriteLockHelper wlh(map_mutex);
            *int old_slaid = remove sla_rmmap{serviceid}{method};
            if (old_slaid) {
                remove sla_mmap{old_slaid}{serviceid}{method};
                rv = True;
            } else
                rv = False;
            if (slaid) {
                sla_mmap{slaid}{serviceid}{method} = True;
                sla_rmmap{serviceid}{method} = slaid;
            }
        }

        return rv;
    }

    # assumes that the slaid (if any) has been verified before the call
    bool setJobSla(string name, *int slaid) {
        on_success {
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateSlaCache");
        }

        # 1: verify job name and get jobid
        int jobid;
        {
            ReadLockHelper rlh(map_mutex);
            *hash h = omqmap.jrmap{name};
            if (!h)
                throw "SLA-ERROR", sprintf("job %y is unknown", name);
            jobid = h.jobid;
        }

        # 2: update DB
        {
            AbstractTable jobs = Qorus.dsmanager.getOmqTable("jobs");
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    jobs.update({"slaid": slaid}, {"jobid": jobid});
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex)) {
                        continue;
                    }
                    rethrow;
                }
                break;
            }
        }

        bool rv;

        # 3: update the internal cache
        {
            WriteLockHelper wlh(map_mutex);
            *int old_slaid = remove sla_rjmap{jobid};
            if (old_slaid) {
                remove sla_jmap{old_slaid}{jobid};
                rv = True;
            }
            else
                rv = False;
            if (slaid) {
                sla_jmap{slaid}{jobid} = True;
                sla_rjmap{jobid} = slaid;
            }
        }

        return rv;
    }

    # unlocked for maximum performance
    *int getSlaForMethod(int serviceid, string method) {
        return sla_rmmap{serviceid}{method};
    }

    # unlocked for maximum performance
    *int getSlaForJob(int jobid) {
        return sla_rjmap{jobid};
    }

    *hash<auto> lookupStep(softstring stepid, *softbool verbose) {
        ReadLockHelper rlh(map_mutex);

        return lookupStepIntern(stepid, verbose);
    }

    *hash<auto> lookupStep(list l, *softbool verbose) {
        ReadLockHelper rlh(map_mutex);

        # issue #2142: do not include a hash entry for stepids that are not present in the cache
        return map {$1: (verbose ? lookupStepIntern($1, True) : omqmap.stepmap{$1})}, l, omqmap.stepmap{$1};
    }

    *hash<auto> rLookupStep(string name) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.steprmap{name};
    }

    *softint rLookupStep(string name, string version) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.steprmap{name}{version};
    }

    softint stepId(string name, *string version) {
        ReadLockHelper rlh(map_mutex);

        *hash h = omqmap.steprmap{name};
        if (!exists h)
            throw "STEP-ERROR", sprintf("step %y does not exist", name);

        if (!exists version || version.empty())
            return h.(h.lastversion);

        if (!h{version})
            throw "STEP-ERROR", sprintf("step %y v%y does not exist", name, version);

        return h{version};
    }

    hash<auto> lookupFunc(softstring funcid) {
        ReadLockHelper rlh(map_mutex);

        *hash rv = omqmap.functionmap{funcid};
        if (!rv)
            throw "OMQMAP-LOOKUPFUNC-ERROR", sprintf("no function information is cached for functionid %d, try "
                "running omqmap.reload() to refresh the cache", funcid);
        return rv;
    }

    *hash<auto> rLookupFunc(string name) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.functionrmap{name};
    }

    *int rLookupFunc(string name, string version) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.functionrmap{name}{version};
    }

    softint functionId(string name, *string version) {
        ReadLockHelper rlh(map_mutex);

        *hash h = omqmap.functionrmap{name};
        if (!h)
            throw "FUNCTION-ERROR", sprintf("function %y does not exist", name);

        if (!exists version || version.empty())
            return h.(h.lastversion);

        if (!h{version})
            throw "FUNCTION-ERROR", sprintf("function %y v%y does not exist", name, version);

        return h{version};
    }

    *hash<auto> lookupConstant(softstring cid) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.constmap{cid};
    }

    *hash<auto> rLookupConstant(string name) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.constrmap{name};
    }

    *int rLookupConstant(string name, string version) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.constrmap{name}{version};
    }

    softint constantId(string name, *string version) {
        ReadLockHelper rlh(map_mutex);

        *hash h = omqmap.constrmap{name};
        if (!h)
            throw "CONSTANT-ERROR", sprintf("constant %y does not exist", name);

        if (!exists version || version.empty())
            return h.(h.lastversion);

        if (!h{version})
            throw "CONSTANT-ERROR", sprintf("constant %y v%y does not exist", name, version);

        return h{version};
    }

    *hash<auto> lookupClass(softstring cid) {
        ReadLockHelper rlh(map_mutex);

        *hash<auto> ch = omqmap.classmap{cid};
        if (ch) {
            *int edit_lock = edit_map."class"{cid}.cid;
            if (edit_lock) {
                ch.edit_lock = edit_lock;
            }
        }
        return ch;
    }

    *hash<auto> rLookupClass(string name) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.classrmap{name};
    }

    *int rLookupClass(string name, string version) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.classrmap{name}{version};
    }

    *hash<auto> rLookupClassInfo(string name, string version) {
        ReadLockHelper rlh(map_mutex);

        *int classid = omqmap.classrmap{name}{version};
        if (!classid) {
            return;
        }
        return omqmap.classmap{classid};
    }

    *softint tryGetClassId(string name, *string version) {
        ReadLockHelper rlh(map_mutex);

        *hash<auto> h = omqmap.classrmap{name};
        if (!h) {
            return;
        }

        if (!exists version || version.empty()) {
            return h{h.lastversion};
        }

        return h{version};
    }

    softint classId(string name, *string version) {
        ReadLockHelper rlh(map_mutex);

        *hash<auto> h = omqmap.classrmap{name};
        if (!h)
            throw "CLASS-ERROR", sprintf("class %y does not exist", name);

        if (!exists version || version.empty())
            return h{h.lastversion};

        if (!h{version})
            throw "CLASS-ERROR", sprintf("class %y v%y does not exist", name, version);

        return h{version};
    }

    *hash<auto> lookupMapper(softstring mid, *softbool verbose) {
        *hash h;
        {
            ReadLockHelper rlh(map_mutex);

            h = omqmap.mmap{mid};
        }
        if (h && verbose)
            h += ("groups": Qorus.rbac.getMapperGroups(h.mapperid));
        return h;
    }

    *hash<auto> rLookupMapper(string name) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.mrmap{name};
    }

    *softint rLookupMapper(string name, string version) {
        ReadLockHelper rlh(map_mutex);

        return omqmap.mrmap{name}{version};
    }

    *hash<auto> getPipelines() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.pipelines;
    }

    *hash<auto> lookupPipeline(string name) {
        ReadLockHelper rlh(map_mutex);
        return omqmap.pipelines{name};
    }

    *hash<auto> lookupPipeline(string name, bool verbose) {
        *hash<auto> rv;
        {
            ReadLockHelper rlh(map_mutex);
            rv = omqmap.pipelines{name};
        }
        if (verbose && rv) {
            fillConfigItemValues("pipeline", name, \rv);
            rv += {
                "groups": Qorus.rbac.getPipelineGroups(name)
            };
        }
        return rv;
    }

    *hash<auto> getPipelineMap(*bool verbose) {
        *hash<auto> rv;
        {
            ReadLockHelper rlh(map_mutex);
            rv = omqmap.pipelines;
        }
        if (verbose && rv) {
            foreach string pipeline in (keys rv) {
                fillConfigItemValues("pipeline", pipeline, \rv{pipeline});
                rv{pipeline} += {
                    "groups": Qorus.rbac.getPipelineGroups(pipeline),
                };
            }
            #map fillConfigItemValues("pipeline", $1, \rv{$1}), keys rv;
        }
        return rv;
    }

    *hash<auto> getFsmMap(*bool verbose) {
        *hash<auto> rv;
        {
            ReadLockHelper rlh(map_mutex);
            rv = omqmap.fsm;
        }
        if (verbose && rv) {
            foreach string fsm in (keys rv) {
                fillConfigItemValues("fsm", fsm, \rv{fsm});
                rv{fsm} += {
                    "groups": Qorus.rbac.getFsmGroups(fsm),
                };
            }
        }
        return rv;
    }

    *hash<auto> lookupFsm(string name, *bool verbose) {
        *hash<auto> rv;
        {
            ReadLockHelper rlh(map_mutex);
            rv = omqmap.fsm{name};
        }
        if (verbose && rv) {
            fillConfigItemValues("fsm", name, \rv);
            rv += {
                "groups": Qorus.rbac.getFsmGroups(name)
            };
        }
        return rv;
    }

    softint mapperId(string name, string version) {
        ReadLockHelper rlh(map_mutex);

        *softint id = omqmap.mrmap{name}{version};
        if (!id)
            throw "MAPPER-ERROR", sprintf("mapper \"%s v%s\" does not exist", name, version);

        return id;
    }

    *list<auto> getMapperIds() {
        ReadLockHelper rlh(map_mutex);
        return map $1.toInt(), keys omqmap.mmap;
    }

    private getWorkflowStepInfo(reference h) {
        ReadLockHelper rlh(map_mutex);
        getWorkflowStepInfoUnlocked(\h);
    }

    private *hash<auto> getMappers(string t, *softlist ids) {
        string table_name = t + "_mappers";
        # key column name
        string k = t + "id";

        hash q;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable mappers = Qorus.dsmanager.getOmqTable(table_name);

                *hash sh;
                if (ids)
                    sh."where"{k} = op_in(ids);

                q = mappers.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            break;
        }
        if (!q.mapperid)
            return;

        ReadLockHelper rlh(map_mutex);

        hash rv;
        foreach hash<auto> mrh in (q.contextIterator()) {
            # skip references to unknown mappers (can only happen if there's a race condition with DB loading with
            # oload)
            *hash mh = omqmap.mmap{mrh.mapperid};
            if (!mh)
                continue;

            softstring id = mrh{k};
            if (!rv{id})
                rv{id} = ();
            rv{id} += ("mapperid": mrh.mapperid) + mh.("name", "version", "patch", "type");
        }
        return rv;
    }

    private *hash<auto> getValueMaps(string t, *softlist ids) {
        string table_name = t + "_vmaps";
        # key column name
        string k = t + "id";

        hash q;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable vmaps = Qorus.dsmanager.getOmqTable(table_name);

                *hash sh;
                if (ids)
                    sh."where"{k} = op_in(ids);

                q = vmaps.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            break;
        }
        if (!q.id)
            return;

        ReadLockHelper rlh(map_mutex);

        hash rv;
        foreach hash vmrh in (q.contextIterator()) {
            # skip references to unknown mappers (can only happen if there's a race condition with DB loading with
            # oload)
            *hash vmh = omqmap.vmmap{vmrh.id};
            if (!vmh)
                continue;

            softstring id = vmrh{k};
            if (!rv{id})
                rv{id} = ();
            hash h = ("id": vmrh.id) + vmh.("name", "throws_exception", "valuetype", "mapsize");
            h.throws_exception = boolean(h.throws_exception);
            rv{id} += h;
        }
        return rv;
    }

    # returns interface ID -> lib type -> list of hashes
    /** @param t the name of the library table
        @param col the column name identifying the interface
        @param ids an optional list of \a col IDs
    */
    private hash<string, hash<string, list<hash<auto>>>> getLibrary(string t, string col, *softlist<auto> ids) {
        *hash<auto> select_hash;
        if (ids) {
            select_hash."where"{col} = op_in(ids);
        }

        return getLibraryFromQuery(t, select_hash, col);
    }

    # returns interface ID -> lib type -> list of hashes
    /** @param t the name of the library table
        @param select_hash the library query hash
        @param col the column name identifying the interface
    */
    private hash<string, hash<string, list<hash<auto>>>> getLibraryFromQuery(string t, *hash<auto> select_hash,
            string col) {
        *hash<auto> result = getLibraryQueryResultIntern(t, select_hash, col);
        return getLibraryIntern(col, result.contextIterator());
    }

    # returns a hash of library query results
    /** @param t the name of the library table
        @param col the column name identifying the interface
        @param ids an optional list of \a col IDs
    */
    private hash<auto> getLibraryQueryResultNoRecovery(string t, string col, *softlist<auto> ids) {
        *hash<auto> select_hash;
        if (ids) {
            select_hash."where"{col} = op_in(ids);
        }
        return getLibraryQueryResultInternNoRecovery(t, select_hash, col);
    }

    # returns a hash of library query results
    /** @param t the name of the library table
        @param select_hash the library query hash
        @param col the column name identifying the interface
    */
    private hash<auto> getLibraryQueryResultIntern(string t, *hash<auto> select_hash, string col) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                return getLibraryQueryResultInternNoRecovery(t, select_hash, col);
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
        }
    }

    # returns a hash of library query results
    /** @param t the name of the library table
        @param select_hash the library query hash
        @param col the column name identifying the interface
    */
    private hash<auto> getLibraryQueryResultInternNoRecovery(string t, *hash<auto> select_hash, string col) {
        AbstractTable table = Qorus.dsmanager.getOmqTable(t);
        QDBG_TEST_CLUSTER_FAILOVER();
        return table.select(select_hash + {"orderby": "load_order"});
    }

    # returns interface ID -> lib type -> list of hashes
    /** @param col the name of the column holding the interface ID
        @param q an iterator returning a hash for the library row
        @param omap to track library objects; xid -> type -> id -> True
        @param newmap the new object map being loaded

        @return hash: interface ID -> lib object type -> list of library hashes => {name, version, id}
    */
    private hash<string, hash<string, list<hash<auto>>>> getLibraryIntern(string col, AbstractIterator q,
            *reference<hash<string, hash<string, hash<string, bool>>>> omap, *hash<auto> newmap) {
        AutoReadLock al;
        if (!map_mutex.lockOwner()) {
            al = new AutoReadLock(map_mutex);
        }

        hash<string, hash<string, list<hash<auto>>>> h = {};
        # get library objects
        foreach hash<auto> row in (q) {
            # get interface ID
            softstring xid = row{col};
            if (!exists h{xid}) {
                h{xid} = {
                    "functions": (),
                    "classes": (),
                    "constants": (),
                    "pipelines": (),
                    "fsm": (),
                };
            }
            if (row.type == OMQ::OT_FUNCTION) {
                *hash<auto> function_info = omqmap.functionrmap{row.name};
                if (function_info) {
                    int id = function_info{function_info.lastversion};
                    # skip object if it has already been added
                    if (omap{xid}{OMQ::OT_FUNCTION}{id}) {
                        continue;
                    }
                    # mark object as already added
                    omap{xid}{OMQ::OT_FUNCTION}{id} = True;

                    h{xid}.functions += {
                        "name"    : row.name,
                        "version" : function_info.lastversion,
                        "id"      : id,
                    };
                } else {
                    # function does not exist
                    olog(LoggerLevel::INFO, "ERROR: function %y does not exist; ignoring", row.name);
                    continue;
                }
            } else if (row.type == OMQ::OT_CLASS) {
                *hash<auto> class_info = omqmap.classrmap{row.name};
                if (class_info) {
                    # issue #3285: classes and all their dependencies to the list
                    code add = sub (softstring classid) {
                        class_info = omqmap.classmap{classid};
                        QDBG_ASSERT(class_info);

                        # skip class if it is already added
                        if (omap{xid}{OMQ::OT_CLASS}{classid}) {
                            return;
                        }

                        # mark class as already added
                        omap{xid}{OMQ::OT_CLASS}{classid} = True;

                        # make copy of class_info before it's updated by the recursive closure call
                        hash<auto> current_class_info = class_info;

                        # issue #3285: add any required classes to list
                        map add($1), class_info.requires;

                        # add class to list
                        h{xid}.classes += {
                            "name"    : current_class_info.name,
                            "version" : current_class_info.version,
                            "id"      : classid.toInt(),
                        };
                    };

                    add(class_info.(class_info.lastversion));
                } else {
                    # class does not exist
                    olog(LoggerLevel::INFO, "ERROR: class %y does not exist; ignoring", row.name);
                    continue;
                }
            } else if (row.type == OMQ::OT_CONSTANT) {
                *hash<auto> constant_info = omqmap.constrmap{row.name};
                if (constant_info) {
                    int id = constant_info{constant_info.lastversion};
                    # skip object if it has already been added
                    if (omap{xid}{OMQ::OT_CONSTANT}{id}) {
                        continue;
                    }
                    # mark object as already added
                    omap{xid}{OMQ::OT_CONSTANT}{id} = True;

                    h{xid}.constants += {
                        "name"    : row.name,
                        "version" : constant_info.lastversion,
                        "id"      : id,
                    };
                } else {
                    # constant does not exist
                    olog(LoggerLevel::INFO, "ERROR: constant %y does not exist; ignoring", row.name);
                    continue;
                }
            } else if (row.type == OMQ::OT_PIPELINE) {
                # skip object if it has already been added
                if (omap{xid}{OMQ::OT_PIPELINE}{row.name}) {
                    continue;
                }
                # mark object as already added
                omap{xid}{OMQ::OT_PIPELINE}{row.name} = True;

                *hash<auto> pipeline_info = omqmap.pipelines{row.name};
                if (pipeline_info) {
                    h{xid}.pipelines += {
                        "name": row.name,
                    };
                } else {
                    # pipeline does not exist
                    olog(LoggerLevel::INFO, "ERROR: pipeline %y does not exist; ignoring", row.name);
                    continue;
                }
            } else if (row.type == OMQ::OT_FSM) {
                # skip object if it has already been added
                if (omap{xid}{OMQ::OT_FSM}{row.name}) {
                    continue;
                }
                # mark object as already added
                omap{xid}{OMQ::OT_FSM}{row.name} = True;

                *hash<auto> fsm_info = newmap{row.name} ?? omqmap.fsm{row.name};
                if (fsm_info) {
                    h{xid}.fsm += {
                        "name": row.name,
                    };
                } else {
                    # fsm does not exist
                    olog(LoggerLevel::INFO, "ERROR: fsm %y does not exist; ignoring", row.name);
                    continue;
                }
            } else if (row.type == OMQ::OT_MAPPER) {
                # only for FSMs and pipelines
                # skip object if it has already been added (check by name, the version is in the name)
                if (omap{xid}{OMQ::OT_MAPPER}{row.name}) {
                    continue;
                }
                # mark object as already added
                omap{xid}{OMQ::OT_MAPPER}{row.name} = True;

                string reg = "(^[^:]+):(.+)$";
                (*string name, *string version) = row.name.regexExtract(reg);
                if (!name || !version) {
                    # mapper is not in the correct format
                    olog(LoggerLevel::INFO, "ERROR: mapper %y is not in format <name>:<version>; ignoring", row.name);
                    continue;
                }

                *hash<auto> mapper_info = omqmap.mrmap{name};
                if (mapper_info) {
                    # issue #3657: reference id with version only
                    *int id = mapper_info{version};
                    if (id) {
                        h{xid}.mappers += {
                            "name": name,
                            "version": version,
                            "id": id,
                        };
                    } else {
                        # mapper does not exist
                        olog(LoggerLevel::INFO, "ERROR: mapper %y v%y does not exist; known versions: %y; ignoring",
                            name, version, keys mapper_info);
                        continue;
                    }
                } else {
                    # fsm does not exist
                    olog(LoggerLevel::INFO, "ERROR: mapper %y in %y does not exist; ignoring", name, row.name);
                    continue;
                }
            }
        }
        return h;
    }

    private hash<auto> getTags(string t, string col, *softlist<auto> ids) {
        hash<string, hash<auto>> h = {};

        hash<auto> q;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable tags = Qorus.dsmanager.getOmqTable(t + "_tags");

                # use += so the "sh" stays "hash<auto>"
                hash<auto> sh += (
                    "columns": ("tag", "value", col),
                );

                if (ids)
                    sh."where"{col} = op_in(ids);

                q = tags.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            break;
        }

        foreach hash<auto> row in (q.contextIterator()) {
            if (row.tag =~ /^_/) {
                splice row.tag, 0, 1;
                h.(row{col}).sys.(row.tag) = row.value;
            } else
                h.(row{col}).(row.tag) = row.value;
        }

        return h;
    }

    hash<auto> reloadTypes(*softlist<string> paths, *bool init) {
        # make sure none of the paths in the arg list are locked
        if (paths) {
            *hash<auto> err = locked_type_map{paths};
            if (err) {
                throw "TYPE-CACHE-ERROR", sprintf("cannot modify locked types %y", keys err);
            }
        }

        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoWriteLock tal(type_cache.getLock());

        # only invalidate remote caches if an existing type was added, removed or changed
        list<string> changed_types;
        on_success if (changed_types) {
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateTypes", changed_types);
        }

        hash<auto> q;

        QorusRestartableTransaction trans();
        while (True) {
            try {
                # restartable transaction
                on_error omqp.rollback();
                on_success omqp.commit();

                AbstractTable types = Qorus.dsmanager.getOmqTable("data_types");

                # use += so the "sh" stays "hash<auto>"
                hash<auto> sh += {
                    "columns": ("path", "typeinfo"),
                };

                if (paths) {
                    sh."where".path = op_in(paths);
                }

                q = types.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            break;
        }

        if (paths) {
            # get a hash of all type paths
            hash<string, bool> path_hash = map {$1: True}, paths;
            *hash<auto> removed_paths = (path_hash - q.path);
            if (removed_paths) {
                list<string> removed_path_list = keys removed_paths;
                # remove given type paths no longer in the DB
                map type_cache.removeType($1), removed_path_list;
                if (!init) {
                    changed_types += removed_path_list;
                }
            }
        }

        # deserialize types and add/replace them in the type cache
        foreach hash<auto> row in (q.contextIterator()) {
            AbstractDataProviderType new_type;
            try {
                if (locked_type_map{row.path}) {
                    # ignore static type errors when qorus-core is restarted in independent mode
                    if (init) {
                        continue;
                    }
                    throw "TYPE-CACHE-ERROR", sprintf("cannot replace static type %y with a new definition",
                        row.path);
                }
                new_type = Serializable::deserialize(row.typeinfo);
                bool updated = type_cache.registerOrReplaceType(row.path, new_type);
                if (!init && updated) {
                    changed_types += row.path;
                }
            } catch (hash<ExceptionInfo> ex) {
                olog(LoggerLevel::INFO, "type %y cannot be loaded and will be ignored: %s: %s", row.path, ex.err,
                    ex.desc);
                continue;
            }
        }

        return {"types": type_cache.size()};
    }

    hash<auto> reloadWorkflows(*softlist<auto> ids, *bool init, *reference<hash<auto>> already_reset) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(workflow_reload_lock);

        on_success
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateWorkflowCache");

        hash<auto> wfmap;
        hash<auto> wfrmap;
        # map of loggerid -> workflowid
        *hash<string, int> logger_wfmap;

        # bug 919: delete workflow options with NULL values
        # bug 938: only delete workflow options with NULL or empty string values if config = False
        QorusRestartableTransaction trans();
        while (True) {
            try {
                # restartable transaction
                on_error omqp.rollback();
                on_success omqp.commit();

                wfmap = {};
                wfrmap = {};
                logger_wfmap = {};

                AbstractTable workflows = Qorus.dsmanager.getOmqTable("workflows");

                # += so "select_hash" remains "hash<auto>"
                hash<auto> select_hash += {
                    "columns": (
                        "workflowid",
                        "name",
                        "version",
                        "patch",
                        "description",
                        "author",
                        "remote",
                        "manual_remote",
                        "workflow_modules",
                        "autostart",
                        "manual_autostart",
                        "sla_threshold",
                        "manual_sla_threshold",
                        "max_instances",
                        "enabled",
                        "language",
                        "language_info",
                        "class_name",
                        "staticdata_type_path",
                        "has_detach",
                        "errorfunction_instanceid",
                        "attach_func_instanceid",
                        "detach_func_instanceid",
                        "onetimeinit_func_instanceid",
                        "errhandler_func_instanceid",
                        "deprecated",
                        "loggerid",
                        "created",
                        "modified",
                        cop_as("st.value", "source"),
                        cop_as("lt.value", "line"),
                    ),
                    "join": join_left(Qorus.dsmanager.getOmqTable("workflow_tags"), "st", NOTHING, ("tag": "_source"))
                        + join_left(Qorus.dsmanager.getOmqTable("workflow_tags"), "lt", NOTHING, ("tag": "_offset")),
                };
                if (ids) {
                    select_hash."where"."workflowid" = op_in((map $1.toInt(), ids));
                }

                *hash<auto> query_hash = workflows.select(select_hash);

                *hash<auto> wih = getWorkflowInfo(query_hash.workflowid, !ids.empty());

                # issue #3285: track library objects; xid -> type -> id -> True
                hash<string, hash<string, hash<string, bool>>> library_ix_map;

                *hash<auto> wmh = query_hash ? getMappers("workflow", ids) : NOTHING;
                *hash<auto> wvmh = query_hash ? getValueMaps("workflow", ids) : NOTHING;

                context (query_hash) {
                    hash<auto> h = %%;
                    # convert NULLs to NOTHING
                    map delete h.$1, keys h, h.$1 === NULL;

                    h.deprecated = boolean(remove h.deprecated);
                    h.manual_autostart = boolean(h.manual_autostart);
                    h.manual_sla_threshold = boolean(h.manual_sla_threshold);
                    h.enabled = boolean(h.enabled);
                    h.remote = boolean(h.remote);
                    h.manual_remote = boolean(h.manual_remote);
                    h.has_detach = h.has_detach.toBool();

                    h.keylist = wih.%workflowid.keyname;
                    h.order_key_map = map {$1: True}, h.keylist;
                    h.line = int(%line);
                    if (h.language_info) {
                        h.language_info = parse_yaml(h.language_info);
                    }

                    # list of starting steps (no dependencies)
                    list<auto> start = ();

                    foreach hash<auto> row in (wih.%workflowid.steps) {
                        # make stepmap
                        h.stepmap.(row.stepid) = row.name;

                        # make it a list so that the list += operator will work
                        if (!exists h.steps.(row.stepid))
                            h.steps.(row.stepid) = ();

                        # if it's not a dummy dependency, then add to dependency list
                        if (row.stepid != row.dependson_stepid)
                            h.steps.(row.stepid) += int(row.dependson_stepid);
                        else
                            start += row.stepid;
                    }

                    # get segment step dependencies for workflow
                    *list<auto> ssq = wih.%workflowid.segments;
                    if (!ssq) {
                        qlog(LoggerLevel::ERROR, "WORKFLOW-VALIDATION-ERROR: workflow %d (%s:%s) has no "
                            "segment_steps entries; cannot cache invalid workflow", %workflowid, %name, %version);
                        continue;
                    }

                    {
                        ReadLockHelper rlh(map_mutex);

                        foreach hash row in (ssq) {
                            # add step to segment step list
                            if (!exists h.segment[row.segmentid].steplist)
                                h.segment[row.segmentid].steplist = ();
                            h.segment[row.segmentid].steplist += row.stepid;

                            if (!exists h.segment[row.segmentid].steps.(row.stepid))
                                h.segment[row.segmentid].steps.(row.stepid) = ();
                            if (row.stepid != row.dependson_stepid)
                                h.segment[row.segmentid].steps.(row.stepid) += row.dependson_stepid;
                            else if (row.segmentid) { # for async segments with one start step (backend)
                                h.segment[row.segmentid].start = row.stepid;
                                *string steptype = omqmap.stepmap{row.stepid}.steptype;
                                if (steptype == OMQ::ExecSubWorkflow)
                                    h.segment[row.segmentid].subworkflow = True;
                                else if (steptype == OMQ::ExecEvent)
                                    h.segment[row.segmentid].event = True;
                            }
                        }
                    }

                    # get inter-segment dependencies for workflow
                    foreach hash<auto> row in (wih.%workflowid.segdeps) {
                        if (!exists h.segment[row.segmentid].segdeps)
                            h.segment[row.segmentid].segdeps = ();
                        h.segment[row.segmentid].segdeps += row.dependson_segmentid;

                        if (!exists h.segment[row.dependson_segmentid].prereqfor)
                            h.segment[row.dependson_segmentid].prereqfor = ();
                        h.segment[row.dependson_segmentid].prereqfor += row.segmentid;
                    }

                    # get async links for workflow
                    foreach hash<auto> row in (wih.%workflowid.segasync) {
                        h.segment[row.segmentid].linksegment = row.frontend_segmentid;
                        h.segment[row.segmentid].linkstepid = row.stepid;

                        # add step to back-end segment lookup
                        h.stepseg.(row.stepid) = row.segmentid;
                    }

                    # get workflow options
                    foreach hash<auto> row in (wih.%workflowid.options) {
                        if (row.config)
                            h.options.(row.name) = row.description;
                        try {
                            h."runtime-options".(row.name) = deserialize_qorus_data(row.value);
                            # bug 919
                            if ((!exists h."runtime-options".(row.name) || h."runtime-options".(row.name) === "")) {
                                delete h."runtime-options".(row.name);
                                # bug 938: do not delete options that are part of the workflow configuration
                                if (!row.config) {
                                    sqlif.deleteInterfaceOptionNoCommit("workflow", %workflowid, row.name);
                                }
                            }
                        } catch (hash<ExceptionInfo> ex) {
                            string err = sprintf("cannot parse workflow %s v%s (%d) option %s: %s: %s (value: %y)",
                                %name, %version, %workflowid, row.name, ex.err, ex.desc, row.value);
                            UserApi::raiseTransientAlert("INVALID-WORKFLOW-DATA", err, h.("name", "version",
                                "workflowid"));
                            qlog(LoggerLevel::ERROR, "INVALID-WORKFLOW-DATA: %s", err);
                        }
                    }

                    # add library
                    hash<auto> lq = getLibraryIntern("workflowid", wih.%workflowid.library.iterator(),
                        \library_ix_map);
                    QDBG_ASSERT(lq.size() <= 1);
                    h.lib = lq.firstValue();
                    #map h.lib = lq.$1, keys lq;

                    map h.custom_statuses.($1.statusid) = $1.description, wih.%workflowid.custstat;

                    # add mappers and value maps
                    h.mappers = wmh.%workflowid;
                    h.vmaps = wvmh.%workflowid;

                    # issue #3406 add step mappers and value maps
                    list<auto> step_ids = map $1.stepid, wih.%workflowid.steps;
                    *hash<auto> step_mappers = getMappers("step", step_ids);
                    *hash<auto> step_vmaps = getValueMaps("step", step_ids);
                    if (step_mappers) {
                        foreach string id in (keys step_mappers) {
                            h.mappers += step_mappers{id};
                        }
                    }
                    if (step_vmaps) {
                        foreach string id in (keys step_vmaps) {
                            h.vmaps += step_vmaps{id};
                        }
                    }

                    wfmap.%workflowid = h;
                    wfrmap.%name.%version = h - "runtime-options";

                    # set "lvcreated" and "lastversion" tags in wfrmap only if loading all workflows
                    if (!ids && (!wfrmap.%name.lastversion || (%created > wfrmap.%name.lvcreated))) {
                        wfrmap.%name += {
                            "lvcreated"   : %created,
                            "lastversion" : %version,
                        };
                    }

                    # add to logger_wfmap
                    if (%loggerid) {
                        logger_wfmap{%loggerid} = %workflowid;
                    }
                }

                # issue #3349: add step library objects in one query
                {
                    select_hash = {
                        "columns": ("*", "w.workflowid"),
                        "join": join_inner(Qorus.dsmanager.getOmqTable("workflow_steps"), "w", {"stepid": "stepid"}),
                    };
                    hash<string, hash<string, list<hash<auto>>>> lib_query = getLibraryFromQuery("step_lib",
                        select_hash, "workflowid");
                    foreach hash<auto> i in (lib_query.pairIterator()) {
                        if (!wfmap{i.key}) {
                            continue;
                        }
                        map wfmap{i.key}.lib{$1.key} += $1.value, i.value.pairIterator();
                    }
                }

                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            break;
        }

        # add tags to workflows
        hash<auto> t = getTags("workflow", "workflowid", ids);
        foreach hash<auto> th in (t.pairIterator()) {
            # issue #3337: only add tags for workflows in the map
            if (!wfmap{th.key}) {
                continue;
            }
            wfmap.(th.key).tags = th.value;
            hash<auto> wfh = wfmap.(th.key);
            wfrmap.(wfh.name).(wfh.version).tags = th.value;
        }

        # get workflow ID list
        softlist wfids = map $1.toInt(), keys wfmap;

        # make atomic update to omqmap and get any remote changes for later execution
        list<hash<auto>> remote_change_list;
        # logger change map: wfid -> bool
        hash<string, bool> wf_logger_change_map;
        {
            WriteLockHelper wlh(map_mutex);

            # check for workflow logger changes
            # NOTE: cannot detect logger changes made in the DB during a qorus-core recovery
            if (omqmap.wfmap) {
                wf_logger_change_map = map {$1.key: True}, omqmap.wfmap.pairIterator(),
                    (!ids || wfmap{$1.key}) && ($1.value.loggerid != wfmap{$1.key}.loggerid);
            }

            hash<auto> wrh = omqmap.wfmap
                ? map {$1.key: $1.value.remote}, omqmap.wfmap.pairIterator(), exists wfmap{$1.key}
                : Qorus.getRunningWorkflowHash();

            foreach hash<auto> wh in (wfmap.pairIterator()) {
                if (exists wrh{wh.key} && wh.value.remote != wrh{wh.key}) {
                    olog(LoggerLevel::INFO, "workflow %s v%s (%d) remote value changed from %y -> %y; queuing remote "
                        "change",
                        wh.value.name, wh.value.version, wh.key, wrh{wh.key}, wh.value.remote, wrh{wh.key});
                    remote_change_list += {
                        "wfid": wh.key,
                        "name": wh.value.name,
                        "version": wh.value.version,
                        "remote": wh.value.remote,
                    };
                    wfmap{wh.key}.remote = wrh{wh.key};

                    # if there is a remote change, then remove the logger change as it will be updated anyway
                    remove wf_logger_change_map{wh.key};
                }
            }

            if (ids) {
                doDeltaIntern(\ids, wfmap, wfrmap, "wfmap", "wfrmap", "wfids", "workflowid", logger_wfmap);
            } else {
                omqmap += {
                    "wfmap": wfmap,
                    "wfrmap": wfrmap,
                    "wfids": wfids,
                    "logger_wfmap": logger_wfmap,
                };
            }
        }

        if (!init) {
            if (ids) {
                Qorus.rbac.rescanWorkflowsDelta(ids);
            } else {
                Qorus.rbac.rescanMetadata(True, False, False);
            }
        }

        Qorus.alerts.rescanMetadata(True, False, False);

        # execute remote changes outside the lock
        if (remote_change_list) {
            if (init) {
                Qorus.saveUpdateWorkflowRemote(remote_change_list);
            } else {
                updateWorkflowRemoteList(remote_change_list);
                already_reset = map {$1.wfid: True}, remote_change_list;
            }
        }

        # enforce logger changes
        map SM.updateLogger($1.toInt(), lookupLogger("workflows", $1.toInt()).params),
            wf_logger_change_map.pairIterator();

        return {"workflows": wfmap.size()};
    }

    updateWorkflowRemoteList(list<auto> l) {
        foreach hash<auto> wh in (l) {
            olog(LoggerLevel::INFO, "updating workflow %s v%s (%d) remote %y -> %y", wh.name, wh.version, wh.wfid,
                !wh.remote, wh.remote);
            try {
                updateWorkflowRemoteIntern(wh.wfid, wh.remote);
            } catch (hash<ExceptionInfo> ex) {
                # in case the workflow disappears; should not happen in normal operations
                olog(LoggerLevel::INFO, "%s: %s", ex.err, ex.desc);
            }
        }
    }

    # returns True if the remote status of the workflow was updated, False if not
    # only called for single workflow updates such as from the REST API
    bool updateWorkflowRemote(softstring wfid, bool remote) {
        waitForInit();
        return updateWorkflowRemoteIntern(wfid, remote);
    }

    # returns True if the remote status of the workflow was updated, False if not
    private bool updateWorkflowRemoteIntern(softstring wfid, bool remote) {
        bool reenable;
        string name;
        string version;

        # if autostart is False, then make sure and restart any workflow execution instances running before the change
        list<string> wml;

        AtomicWorkflowActionHelper atomic_action_helper(wfid);

        on_success if (wml) {
            olog(LoggerLevel::INFO, "workflow %s v%s (%d): restarting %d workflow exec instance%s after \"remote\" "
                "attribute change", name, version, wfid, wml.size(), wml.size() == 1 ? "" : "s");
            map Qorus.control.startWorkflowAtomic(tld.cx, wfid, $1, NOTHING, "restarted after \"remote\" attribute "
                "change"), wml;
        }

        # issue #2425: do not start re-enabling workflows until the disable action has completed
        Counter done_counter();

        on_exit if (reenable) {
            # issue #3302: make sure the atomic lock structure can go out of scope before we wait for the action to
            # complete, or we can get a deadlock
            remove atomic_action_helper;

            # issue #2425: wait for disable action to complete before starting to re-enable
            done_counter.waitForZero();
            done_counter.inc();

            atomic_action_helper = new AtomicWorkflowActionHelper(wfid);
            Qorus.rbac.enableSyntheticGroup("workflow", wfid, atomic_action_helper, done_counter);
            # wait for enable to complete before returning
            done_counter.waitForZero();
        }

        {
            ReadLockHelper rlh(map_mutex);
            reference whr = \omqmap.wfmap{wfid};

            if (!exists whr) {
                throw "WORKFLOW-ERROR", sprintf("workflowid %d does not exist", wfid);
            }

            name = whr.name;
            version = whr.version;

            # if the remote status is already equal to the target remote status, then return
            if (whr.remote == remote) {
                olog(LoggerLevel::INFO, "no update necessary for workflow %s v%s (%d); remote is already %y", name,
                    version, wfid, remote);
                return False;
            }

            if (!whr.autostart) {
                # issue #3242: do not call any control methods subject to locks while holding any map manager locks
                delete rlh;
                wml = Qorus.control.getRunningWorkflowExecutionInstanceModeList(wfid);
            }

            # disable the workflow
            done_counter.inc();
        }
        # release the lock so we can update the group; we have the atomic action lock on the wf anyway
        # so the wf cannot be changed with high level actions
        reenable = Qorus.rbac.disableSyntheticGroup("workflow", wfid, atomic_action_helper, done_counter);

        # update DB
        sqlif.commitUpdateWorkflowRemoteStatus(wfid, remote);

        bool updated;
        {
            WriteLockHelper wlh(map_mutex);
            reference whr = \omqmap.wfmap{wfid};
            # if the workflow has been deleted from the DB
            if (!whr) {
                olog(LoggerLevel::INFO, "workflow %s v%s (%d) metadata disappeared; cannot change remote value",
                    name, version, wfid);
                reenable = False;
                return False;
            }
            if (whr.remote != remote) {
                # mark workflow status changed in internal caches
                whr.remote = omqmap.wfrmap.(whr.name).(whr.version).remote = remote;
                whr.manual_remote = omqmap.wfrmap.(whr.name).(whr.version).manual_remote = True;
                updated = True;
            }
        }

        if (updated) {
            # wait for all workflow execution instances to stop
            # anc update remote value in any cached workflow
            Qorus.control.waitUpdateRemote(wfid, remote);

            olog(LoggerLevel::INFO, "successfully updated workflow %s v%s (%d) remote %y -> %y", name, version, wfid,
                !remote, remote);

            # issue #2725 issue WORKFLOW_UPDATED event
            Qorus.events.postWorkflowUpdated(tld.cx, name, version, wfid, {"remote": remote});
        } else {
            olog(LoggerLevel::INFO, "workflow %s v%s (%d) metadata updated while disabling job", name, version, wfid);
        }

        return updated;
    }

    # returns True if the SLA status of the workflow was updated, False if not
    bool updateWorkflowSla(softstring wfid, int sla) {
        string name;
        string version;
        int old_sla;

        {
            WriteLockHelper wlh(map_mutex);

            reference whr = \omqmap.wfmap{wfid};

            if (!exists whr) {
                throw "WORKFLOW-ERROR", sprintf("workflowid %d does not exist", wfid);
            }

            name = whr.name;
            version = whr.version;

            # if the remote status is already equal to the target remote status, then return
            if (whr.sla_threshold == sla) {
                olog(LoggerLevel::INFO, "no update necessary for workflow %s v%s (%d); SLA is already %y", name,
                    version, wfid, sla);
                return False;
            }

            old_sla = whr.sla_threshold;
            whr.sla_threshold = sla;

            # update DB
            sqlif.commitUpdateWorkflowSlaStatus(wfid, sla);
        }

        Qorus.orderStats.requeue(wfid, sla);

        # issue #2725 issue WORKFLOW_UPDATED event
        Qorus.events.postWorkflowUpdated(tld.cx, name, version, wfid, {"sla_threshold": sla});
        olog(LoggerLevel::INFO, "successfully updated workflow %s v%s (%d) SLA %y -> %y", name, version, wfid, old_sla, sla);

        return True;
    }

    hash<string, hash<string, int>> getServiceMethodSlaHash() {
        ReadLockHelper rlh(map_mutex);
        return sla_rmmap;
    }

    hash<auto> reloadServices(*softlist ids, *bool init, *reference<hash> already_reset) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(service_reload_lock);

        # NOTE: the service metadata cache is now centralized

        hash servicemap;
        hash servicermap;
        hash serviceamap;
        hash<string, hash<string, hash<string, bool>>> sla_mmap();
        hash<string, hash<string, int>> sla_rmmap();

        hash select_hash = {
            "columns": (
                "serviceid",
                cop_as("service_type", "type"),
                "name",
                "version",
                "patch",
                "description",
                "author",
                "parse_options",
                "language",
                "language_info",
                "class_source",
                "class_name",
                "remote",
                "manual_remote",
                "service_modules",
                "autostart",
                "manual_autostart",
                "enabled",
                "loggerid",
                "yaml_fsm_triggers",
                "api_manager",
                "events",
                "created",
                "modified",
            ),
        };
        if (ids) {
            select_hash."where"."serviceid" = op_in((map $1.toInt(), ids));
        }

        hash<auto> config_items;
        hash<auto> query_hash;
        hash<auto> options;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable services = Qorus.dsmanager.getOmqTable("services");
                AbstractTable service_config_items_table = Qorus.dsmanager.getOmqTable("service_config_items");
                AbstractTable service_options = Qorus.dsmanager.getOmqTable("service_options");

                query_hash = services.select(select_hash);
                config_items = service_config_items_table.select(select_hash{"where",});
                context (service_options.select(select_hash{"where",})) {
                    # issue #919
                    if ((%value === NULL || %value === "") && !%config) {
                        sqlif.deleteInterfaceOptionNoCommit("service", %serviceid, %name);
                    }
                    options{%serviceid} = %%;
                }
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        *hash<auto> svcmh = query_hash ? getMappers("service", ids) : NOTHING;
        *hash<auto> svcvmh = query_hash ? getValueMaps("service", ids) : NOTHING;

        context (query_hash) {
            hash<auto> h = %%;

            # convert NULLs to NOTHING
            map delete h.$1, keys h, h.$1 === NULL;

            bool class_based = %class_source.val();

            h.config_items = remove h.yaml_config_items;
            if (h.config_items) {
                h.config_items = deserialize_qorus_data(h.config_items);
            }
            if (h.api_manager) {
                h.api_manager = deserialize_qorus_data(h.api_manager);
            }
            if (h.events) {
                h.events = deserialize_qorus_data(h.events);
            }
            if (h.language_info) {
                h.language_info = parse_yaml(h.language_info);
            }

            *string yaml_fsm_triggers = remove h.yaml_fsm_triggers;

            h.type = %type.lwr();

            # get service options
            foreach hash<auto> row in (options{%serviceid}.contextIterator()) {
                if (row.config) {
                    h.options.(row.name) = row.description;
                }
                try {
                    h."runtime-options".(row.name) = deserialize_qorus_data(row.value);
                    if ((!exists h."runtime-options".(row.name) || h."runtime-options".(row.name) === "")) {
                        delete h."runtime-options".(row.name);
                    }
                } catch (hash<ExceptionInfo> ex) {
                    string err = sprintf("cannot parse %s service %s v%s (%d) option %s: %s: %s (value: %y)",
                        h.type, %name, %version, %serviceid, row.name, ex.err, ex.desc, row.value);
                    UserApi::raiseTransientAlert("INVALID-SERVICE-DATA", err, h{"type", "name", "version", "serviceid"});
                    qlog(LoggerLevel::ERROR, "INVALID-SERVICE-DATA: %s", err);
                }
            }

            servicemap.%serviceid = h + {
                "language": %language,
                "class_based": class_based,
                "class_name": %class_name ?? (class_based ? %name : NOTHING),
                # system services are always internal
                "remote": (%type == "SYSTEM") ? False : %remote.toBool(),
                "manual_remote": %manual_remote.toBool(),
                "autostart": boolean(%autostart),
                "manual_autostart": boolean(%manual_autostart),
                "enabled": boolean(%enabled),
                "mappers": svcmh.%serviceid,
                "vmaps": svcvmh.%serviceid,
                "fsm_triggers": yaml_fsm_triggers ? parse_yaml(yaml_fsm_triggers) : NOTHING,
            };

            servicermap.%type.%name.%version = %serviceid;

            if (!ids && (!servicermap.%type.%name.lastversion || (%created > servicermap.%type.%name.lvcreated))) {
                servicermap.%type.%name += {
                    "lvcreated": %created,
                    "lastversion": %version,
                    "serviceid": %serviceid,
                };
            }
        }

        context (config_items) {
            # ignore config for steps not present in the step query
            if (!servicemap{%serviceid}) {
                continue;
            }
            servicemap{%serviceid}.config{%name} = {
                "type": %type,
                "desc": %description,
                "strictly_local": %strictly_local.toBool(),
                "config_group": %config_group,
                "sensitive": %sensitive.toBool(),
                "prefix": %prefix,
            };

            servicemap{%serviceid}.config{%name} += %default_value.val() ?
                {"default_value": deserialize_qorus_data(%default_value)} : {};

            servicemap{%serviceid}.config{%name} += %allowed_values.val() ?
                {"allowed_values": deserialize_qorus_data(%allowed_values)} : {};
        }
        # tag latest services with "latest" = True
        if (!ids) {
            foreach string t in (keys servicermap) {
                foreach string n in (keys servicermap{t}) {
                    # get version hash
                    hash vh = servicermap{t}{n};
                    servicemap.(vh.serviceid).latest = True;
                    serviceamap{t}{n} = {
                        "serviceid": vh.serviceid,
                        "version": vh.lastversion,
                    };
                }
            }
        }

        # add method info to servicemap
        select_hash.columns = (
            "serviceid",
            "service_methodid",
            "name",
            "description",
            "body",
            "slaid",
            "author",
            "locktype",
            "internal",
            cop_as("writeflag", "write"),
            "created",
            "modified",
        );

        hash smq;
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable service_methods = Qorus.dsmanager.getOmqTable("service_methods");
                smq = service_methods.select(select_hash);
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

        # service method hash; methodid -> service method info
        hash<string, hash<auto>> smh;
        context (smq) {
            # fix for #1208: do not include service methods not selected above in case of DB changes while resetting
            if (!servicemap.%serviceid) {
                continue;
            }
            hash<auto> h = %% - "slaid";
            # convert NULLs to NOTHING
            map delete h.$1, keys h, h.$1 === NULL;

            hash<auto> smih = h + {
                "internal": h.internal.toBool(),
                "write": h.write.toBool(),
            };

            servicemap.%serviceid.methods.%service_methodid = (smih - "serviceid");
            servicemap.%serviceid.method_name_map.%name = %service_methodid;

            smh.%service_methodid = smih;

            # add slaid to service method mapping
            if (%slaid) {
                string svcname = servicemap.%serviceid.name;
                sla_mmap{%slaid}{%serviceid}{%name} = True;
                sla_rmmap{%serviceid}{%name} = %slaid;
            }
        }

        # get svc file resources info
        select_hash.columns = (
            "serviceid",
            "resource_type",
            "name",
        );

        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable service_file_resources = Qorus.dsmanager.getOmqTable("service_file_resources");
                query_hash = service_file_resources.select(select_hash);
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
        context (query_hash) {
            # fix for #1208: do not include service methods not selected above
            if (!servicemap.%serviceid) {
                continue;
            }
            servicemap.%serviceid.resources += list(("name": %name, "type": %resource_type));
        }

        # add tags to services
        hash<auto> t = getTags("service", "serviceid", ids);
        foreach hash<auto> th in (t.pairIterator()) {
            # fix for #1208: do not include service methods not selected above
            if (!servicemap.(th.key)) {
                continue;
            }
            servicemap.(th.key).tags = th.value;
        }

        # add tags to service methods
        t = getTags("service_method", "service_methodid", ids ? smq.service_methodid : NOTHING);
        foreach hash<auto> th in (t.pairIterator()) {
            # fix for #1208: do not include service methods not selected above
            if (!servicemap.(smh.(th.key).serviceid)) {
                continue;
            }
            servicemap.(smh.(th.key).serviceid).methods.(th.key).tags = th.value;
        }

        # add authlabels
        select_hash.columns = (
            "authlabelid",
            "serviceid",
            "value",
        );
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable authlabels = Qorus.dsmanager.getOmqTable("service_auth_labels");

                query_hash = authlabels.select(select_hash);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        hash almap = {}; # authlabels map
        context (query_hash) {
            hash<auto> h = %%;
            if (!servicemap.%serviceid) {
                continue;
            }
            almap.%authlabelid.%serviceid = h + {
                "servicename": servicemap.%serviceid.name,
            };
            remove h.serviceid;
            servicemap.%serviceid.authlabels.%authlabelid = {
                "value" : h.value,
            };
        }

        # add library information to services
        query_hash = getLibrary("service_lib", "serviceid", ids);
        # fix for #1208: do not include service methods not selected above
        map servicemap.$1.lib = query_hash.$1, keys query_hash, servicemap.$1;

        # get service ID list
        softlist<int> svcids = map int($1), keys servicemap;

        # make atomic update to omqmap and get any remote changes for later execution
        list<hash<auto>> remote_change_list;
        {
            WriteLockHelper wlh(map_mutex);

            # serviceid -> remote flag of existing services
            hash<auto> srh;
            if (omqmap.servicemap) {
                srh = map {$1.key: $1.value.remote}, omqmap.servicemap.pairIterator(), exists servicemap{$1.key};
            } else {
                foreach string key in (keys Qorus.getRunningServiceHash()) {
                    srh{key} = True;
                }
            }

            foreach hash<auto> sh in (servicemap.pairIterator()) {
                if (exists srh{sh.key} && sh.value.remote != srh{sh.key}) {
                    olog(LoggerLevel::INFO, "%s service %s v%s (%d) remote value changed from %y -> %y; queuing "
                        "remote change", sh.value.type, sh.value.name, sh.value.version, sh.key, srh{sh.key},
                        sh.value.remote, srh{sh.key});
                    remote_change_list += {
                        "svcid": sh.key,
                        "type": sh.value.type,
                        "name": sh.value.name,
                        "version": sh.value.version,
                        "remote": sh.value.remote,
                    };
                    servicemap{sh.key}.remote = srh{sh.key};
                }
            }

            if (ids) {
                # get hash of types -> names -> True
                hash<string, hash<string, bool>> nh;
                map nh{$1.type.upr()}{$1.name} = True, servicemap{ids}.iterator();
                # add names of any deleted services
                map nh{$1.type.upr()}{$1.name} = True, omqmap.servicemap{ids}.iterator();

                # temporarily copy the reverse map
                *hash<auto> cr = omqmap.servicermap;

                # remove old reverse mappings
                map (remove omqmap.servicermap{$1.type.upr()}{$1.name}{$1.version},
                    remove omqmap.serviceamap{$1.type.upr()}{$1.name}), omqmap.servicemap{ids}.iterator();
                map (remove omqmap.servicermap{$1.type.upr()}{$1.name}{$1.version},
                    remove omqmap.serviceamap{$1.type.upr()}{$1.name}), servicemap{ids}.iterator();

                foreach string type in (keys nh) {
                    map remove omqmap.servicermap{type}{$1}.("lvcreated", "lastversion", "serviceid"), keys nh{type};
                }

                # remove all entries where all versions have been deleted
                foreach string type in (keys omqmap.servicermap) {
                    map (remove omqmap.servicermap{type}.$1, remove omqmap.serviceamap{type}.$1),
                        keys omqmap.servicermap{type}, !omqmap.servicermap{type}.$1;
                }
                # remove all entries where all services of a particular type have been deleted
                map (remove omqmap.servicermap.$1, remove omqmap.serviceamap.$1), keys omqmap.servicermap,
                    !omqmap.servicermap.$1;

                # add possibly removed IDs with the same type/name/version keys to the id list
                ids += map cr{$1.type.upr()}{$1.name}{$1.version}, servicemap{ids}.iterator(),
                    cr{$1.type.upr()}{$1.name}{$1.version} && $1.serviceid != cr{$1.type.upr()}{$1.name}{$1.version};

                # remove old forward mappings
                remove omqmap.servicemap{ids};
                # remove old authlabel mappings
                foreach string authlabelid in (keys omqmap.authlabelmap) {
                    remove omqmap.authlabelmap{authlabelid}{ids};
                }
                # remove old SLA mappings
                foreach softstring sid in (ids) {
                    map remove self.sla_mmap{$1.value}{sid}{$1.key}, self.sla_rmmap{sid}.pairIterator();
                }
                remove self.sla_rmmap{ids};
                # remove possibly duplicated entries
                foreach hash<auto> dh in (servicermap.pairIterator()) {
                    foreach hash<auto> vh in (dh.value.pairIterator()) {
                        map remove omqmap.servicemap{cr{dh.key}{vh.key}{$1.key}}, keys vh.value;
                    }
                }

                # remove old IDs
                hash<string, bool> dh = map {$1: True}, ids;
                omqmap.svcids = select omqmap.svcids, !dh.$1;
                # remove old method mappings
                map remove omqmap.servicemethodmap{$1.methods.keys()}, servicemap.iterator();
                # remove "latest" tag from all affected services
                foreach hash<auto> lh in (nh.pairIterator()) {
                    map (map remove omqmap.servicemap.($1.serviceid).latest,
                        omqmap.servicermap{lh.key}{$1}.iterator()), keys lh.value;
                }

                # only add if there's something to add
                if (svcids) {
                    # add forward mappings
                    omqmap.servicemap += servicemap;

                    # add reverse mappings
                    foreach hash<auto> h1 in (servicermap.pairIterator()) {
                        foreach hash<auto> h2 in (h1.value.pairIterator()) {
                            map omqmap.servicermap{h1.key}{h2.key}{$1.key} = $1.value, h2.value.pairIterator();
                        }
                    }

                    # add IDs
                    omqmap.svcids += svcids;
                    omqmap.servicemethodmap += smh;
                    if (sla_mmap) {
                        # map of slaids -> serviceid -> method name = True
                        map self.sla_mmap{$1.key} += $1.value, sla_mmap.pairIterator();
                        self.sla_rmmap += sla_rmmap;
                    }
                    foreach hash<auto> i in (almap.pairIterator()) {
                        omqmap.authlabelmap{i.key} += i.value;
                    }
                }

                # redo last version for all changed services by type and name
                foreach string type in (keys nh) {
                    foreach string name in (keys nh{type}) {
                        foreach string version in (keys omqmap.servicermap{type}{name}) {
                            hash<auto> svch = omqmap.servicemap{omqmap.servicermap{type}{name}{version}};
                            if (!omqmap.servicermap{type}{name}.lastversion
                                || (svch.created > servicermap{type}{name}.lvcreated)) {
                                omqmap.servicermap{type}{name} += {
                                    "lvcreated": svch.created,
                                    "lastversion": svch.version,
                                    "serviceid": svch.serviceid,
                                };
                                omqmap.serviceamap{type}{name} = {
                                    "serviceid": svch.serviceid,
                                    "version": svch.version,
                                };
                            }
                        }
                    }
                }

                # set "latest" tag in all affected services
                foreach hash<auto> lh in (nh.pairIterator()) {
                    map (map omqmap.servicemap{$1.serviceid}.latest = True, omqmap.serviceamap{lh.key}{$1}), keys lh.value;
                }
            } else {
                omqmap += {
                    "servicemap": servicemap,
                    "servicermap": servicermap,
                    "serviceamap": serviceamap,
                    "svcids": svcids,
                    "servicemethodmap": smh,
                    "authlabelmap": almap,
                };
                self.sla_mmap = sla_mmap;
                self.sla_rmmap = sla_rmmap;
            }

            # rebuild system service ID list
            omqmap.systemserviceids = (map omqmap.servicermap.SYSTEM{$1}{omqmap.serviceamap.SYSTEM{$1}.version}.toInt(),
                keys omqmap.servicermap.SYSTEM) ?? ();
            # rebuild user service ID list
            omqmap.userserviceids = (map omqmap.servicermap.USER{$1}{omqmap.serviceamap.USER{$1}.version}.toInt(),
                keys omqmap.servicermap.USER) ?? ();
        }

        if (!init) {
            if (ids) {
                Qorus.rbac.rescanServicesDelta(ids);
            } else {
                Qorus.rbac.rescanMetadata(False, True, False);
            }
        }

        Qorus.alerts.rescanMetadata(False, True, False);

        # execute remote changes outside the lock
        if (remote_change_list) {
            if (init) {
                Qorus.saveUpdateServiceRemote(remote_change_list);
            } else {
                updateServiceRemoteList(remote_change_list);
                already_reset = map {$1.svcid: True}, remote_change_list;
            }
        }

        return {"services": servicemap.size()};
    }

    updateServiceAuthLabels(int svcid, hash<auto> authlabels) {
        WriteLockHelper wlh(map_mutex);

        reference shr = \omqmap.servicemap{svcid};

        if (!exists shr) {
            throw "SERVICE-ERROR", sprintf("serviceid %d does not exist", svcid);
        }

        # first verify all updates
        foreach string label in (keys authlabels) {
            if (!shr.authlabels{label}) {
                throw "SERVICE-ERROR", sprintf("authentication label %y does not exist in %s service %s v%s (%d); "
                    "known authentication labels for this service: %y",
                    label, shr.type, shr.name, shr.version, svcid, keys shr.authlabels);
            }

            if (!AUTH_LABEL_VALUES{authlabels{label}}) {
                throw "SERVICE-ERROR", sprintf("Authentication label value %y is not valid; expecting one of: %y",
                    authlabels{label}, keys AUTH_LABEL_VALUES);
            }

            # ignore cases when there is no update
            if (shr.authlabels{label}.value == authlabels{label}) {
                remove authlabels{label};
            }
        }

        # update auth labels values in db
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                AbstractTable auth_labels = Qorus.dsmanager.getOmqTable("service_auth_labels");

                map auth_labels.update(
                    # update
                    {"value": authlabels{$1}, "modified": now()},
                    # where
                    {"authlabelid": $1, "serviceid": svcid}),
                    keys authlabels;

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

        # update the values in the cache last
        map shr.authlabels{$1}.value = authlabels{$1}, keys authlabels;
    }

    updateServiceRemoteList(list<auto> l) {
        foreach hash<auto> sh in (l) {
            olog(LoggerLevel::INFO, "updating %s service %s v%s (%d) remote %y -> %y", sh.type, sh.name, sh.version, sh.svcid, !sh.remote, sh.remote);
            try {
                updateServiceRemoteIntern(sh.svcid, sh.remote);
            } catch (hash<ExceptionInfo> ex) {
                # in case the service disappears; should not happen in normal operations
                olog(LoggerLevel::INFO, "%s: %s", ex.err, ex.desc);
            }
        }
    }

    # returns True if the remote status of the service was updated, False if not
    # only called for single service updates such as from the REST API
    bool updateServiceRemote(softstring svcid, bool remote) {
        waitForInit();
        return updateServiceRemoteIntern(svcid, remote);
    }

    # returns True if the remote status of the service was updated, False if not
    private bool updateServiceRemoteIntern(softstring svcid, bool remote) {
        bool reenable;
        string type;
        string name;
        string version;

        # if autostart is False, then make sure and restart any services running before the change
        bool start_service;

        # emsure atomicity of the update
        AtomicServiceActionHelper atomic_action_helper(svcid);

        on_success if (start_service) {
            olog(LoggerLevel::INFO, "%s service %s v%s (%d): restarting after \"remote\" attribute change", type, name, version, svcid);
            services.loadService(type, name, False, "restarting after \"remote\" attribute change");
        }

        # issue #2425: do not start re-enabling services until the disable action has completed
        Counter done_counter();

        on_exit if (reenable) {
            # issue #3302: make sure the atomic lock structure can go out of scope before we wait for the action to
            # complete, or we can get a deadlock
            remove atomic_action_helper;

            # issue #2425: wait for disable action to complete before starting to re-enable
            #QDBG_LOG("QMM updateServiceRemoteIntern() dc: %y (%d)", done_counter.uniqueHash(), done_counter.getCount());
            done_counter.waitForZero();
            done_counter.inc();

            atomic_action_helper = new AtomicServiceActionHelper(svcid);
            Qorus.rbac.enableSyntheticGroup("service", svcid, atomic_action_helper, done_counter);
            # wait for enable to complete before returning
            done_counter.waitForZero();
        }

        {
            ReadLockHelper rlh(map_mutex);
            reference shr = \omqmap.servicemap{svcid};

            if (!exists shr) {
                throw "SERVICE-ERROR", sprintf("serviceid %d does not exist", svcid);
            }

            type = shr.type;
            name = shr.name;
            version = shr.version;

            # if the remote status is already equal to the target remote status, then return
            if (shr.remote == remote) {
                olog(LoggerLevel::INFO, "no update necessary for %s service %s v%s (%d); remote is already %y", type, name, version, svcid, remote);
                return False;
            }

            start_service = shr.autostart;
            if (!start_service) {
                start_service = services.getServiceLoadedIndication(type, name);
            }

            # disable the service
            done_counter.inc();
        }
        # release the lock so we can update the group; we have the atomic action lock on the svc anyway
        # so the svc cannot be changed with high level actions
        reenable = Qorus.rbac.disableSyntheticGroup("service", svcid, atomic_action_helper, done_counter);
        # update DB
        sqlif.commitUpdateServiceRemoteStatus(svcid, remote);

        bool updated;
        {
            WriteLockHelper wlh(map_mutex);
            reference shr = \omqmap.servicemap{svcid};
            # if the service has been deleted from the DB
            if (!shr) {
                olog(LoggerLevel::INFO, "%s service %s v%s (%d) metadata disappeared; cannot change remote value", type, name,
                    version, svcid);
                reenable = False;
                return False;
            }
            if (shr.remote != remote) {
                # mark workflow status changed in internal caches
                shr.remote = remote;
                shr.manual_remote = True;
                updated = True;
            }
        }

        if (updated) {
            olog(LoggerLevel::INFO, "successfully updated %s service %s v%s (%d) remote %y -> %y", type, name, version, svcid,
                !remote, remote);
            # issue #2725 issue SERVICE_UPDATED event
            Qorus.events.postServiceUpdated(tld.cx, type, name, version, svcid, {"remote": remote});
        } else {
            olog(LoggerLevel::INFO, "%s service %s v%s (%d) metadata updated while disabling service", type, name, version, svcid);
        }

        return updated;
    }

    hash<string, int> getJobSlaHash() {
        ReadLockHelper rlh(map_mutex);
        return sla_rjmap;
    }

    #! seed the logger metadata map as provided from qorus-master on startup
    seedLoggers(hash<auto> seed_logger_map) {
        # first convert param types
        hash<auto> loggerMap;
        foreach hash<auto> i in (seed_logger_map.loggerMap.pairIterator()) {
            loggerMap{i.key}.params = new hash<LoggerParams>();
            loggerMap{i.key}.params.appenders = map {$1.key: cast<hash<AppenderParams>>($1.value)},
                i.value.params.appenders.pairIterator();
            # add the rest of the keys
            loggerMap{i.key}.params += (i.value.params - "appenders");
            loggerMap{i.key} += (i.value - "params");
        }

        AutoWriteLock awl(map_mutex);
        omqmap += {
            "loggerMap": loggerMap,
            "loggerAliases": seed_logger_map.loggerAliases,
        };
    }

    #! Returns the path for the given type if it exists or @ref NOTHING if not
    /** @param path the normalized path to the type with a leading \c "/"

        @return the path for the given type if it exists or @ref NOTHING if not
    */
    private *AbstractDataProviderType lookupTypeImpl(string path) {
        return type_cache.getType(path);
    }

    # updates internal workflow maps with new logger info and notifies all affected processes that the logger has been updated
    private:internal updateWorkflowLoggerDb(auto pk, *hash<auto> new_logger) {
        # update in DB
        updateInterfaceLoggerIdDb("workflows", "workflowid", pk, new_logger.loggerid);
        # update in metadata cache and notify processes / objects of changes
        updateWorkflowLogger(pk, new_logger);
    }

    # updates internal workflow maps with new logger info and notifies all affected processes that the logger has been updated
    private:internal updateWorkflowLogger(auto pk, *hash<auto> new_logger) {
        if (pk) {
            {
                WriteLockHelper wlh(map_mutex);
                # workflow disappeared
                if (!omqmap.wfmap{pk}) {
                    return;
                }

                # get workflow hash
                hash<auto> wfh = omqmap.wfmap{pk};

                # remove from loggermap if logger is being removed or changed
                if (wfh.loggerid && new_logger.loggerid != wfh.loggerid) {
                    remove omqmap.logger_wfmap{wfh.loggerid};
                }

                omqmap.wfmap{pk}.loggerid = new_logger.loggerid;
                omqmap.wfrmap.(wfh.name).(wfh.version).loggerid = new_logger.loggerid;

                # add to loggermap if a logger is being added
                if (new_logger.loggerid) {
                    omqmap.logger_wfmap{new_logger.loggerid} = pk.toInt();
                }
            }

            SM.updateLogger(pk, new_logger.params);
        } else {
            # update all workflows using the default logger
            list<softstring> wfids;
            {
                ReadLockHelper rlh(map_mutex);
                wfids = map $1.workflowid, omqmap.wfmap.iterator(), !$1.loggerid;
            }
            map SM.updateLogger($1, new_logger.params), wfids;
        }
    }

    # updates internal service maps with new logger info and notifies all affected processes that the logger has been updated
    private:internal updateServiceLoggerDb(auto pk, *hash<auto> new_logger) {
        # update in DB
        updateInterfaceLoggerIdDb("services", "serviceid", pk, new_logger.loggerid);
        # update in metadata cache and notify processes / objects of changes
        updateServiceLogger(pk, new_logger);
    }

    # updates internal service maps with new logger info and notifies all affected processes that the logger has been updated
    private:internal updateServiceLogger(auto pk, *hash<auto> new_logger) {
        if (pk) {
            {
                WriteLockHelper wlh(map_mutex);
                # service disappeared
                if (!omqmap.servicemap{pk}) {
                    return;
                }

                # remove from loggermap if logger is being removed or changed
                if (omqmap.servicemap{pk}.loggerid && new_logger.loggerid != omqmap.servicemap{pk}.loggerid) {
                    remove omqmap.logger_svcmap{omqmap.servicemap{pk}.loggerid};
                }

                omqmap.servicemap{pk}.loggerid = new_logger.loggerid;

                # add to loggermap if a logger is being added
                if (new_logger.loggerid) {
                    omqmap.logger_svcmap{new_logger.loggerid} = pk.toInt();
                }
            }
            services.updateLogger(pk.toInt(), new_logger.params);
        } else {
            # update all services using the default logger
            list<int> svcids;
            {
                ReadLockHelper rlh(map_mutex);
                svcids = map $1.serviceid, omqmap.servicemap.iterator(), !$1.loggerid;
            }
            map services.updateLogger($1, new_logger.params), svcids;
        }
    }

    # updates internal service maps with new logger info and notifies all affected processes that the logger has been updated
    private:internal updateJobLoggerDb(auto pk, *hash<auto> new_logger) {
        # update in DB
        updateInterfaceLoggerIdDb("jobs", "jobid", pk, new_logger.loggerid);
        # update in metadata cache and notify processes / objects of changes
        updateJobLogger(pk, new_logger);
    }

    # updates internal job maps with new logger info and notifies all affected processes that the logger has been updated
    private:internal updateJobLogger(auto pk, *hash<auto> new_logger) {
        if (pk) {
            string name;
            {
                WriteLockHelper wlh(map_mutex);
                # job disappeared
                if (!omqmap.jmap{pk}) {
                    return;
                }

                # remove from loggermap if logger is being removed or changed
                if (omqmap.jmap{pk}.loggerid && new_logger.loggerid != omqmap.jmap{pk}.loggerid) {
                    remove omqmap.logger_jobmap{omqmap.jmap{pk}.loggerid};
                }

                # get job name
                name = omqmap.jmap{pk}.name;

                # update maps
                omqmap.jmap{pk}.loggerid = new_logger.loggerid;
                omqmap.jrmap{name}.loggerid = new_logger.loggerid;

                # add to loggermap if a logger is being added
                if (new_logger.loggerid) {
                    omqmap.logger_jobmap{new_logger.loggerid} = pk.toInt();
                }
            }
            Qorus.jobManager.updateLogger(name, new_logger.params);
        } else {
            # update all jobs using the default logger
            list<string> jobnames;
            {
                ReadLockHelper rlh(map_mutex);
                jobnames = map $1.name, omqmap.jmap.iterator(), !$1.loggerid;
            }
            map Qorus.jobManager.updateLogger($1, new_logger.params), jobnames;
        }
    }

    # updates system loggers using the default system logger with new logger info
    private:internal updateSystemLoggers(*hash<LoggerParams> params) {
        list<code> update_list;
        {
            map_mutex.readLock();
            on_exit map_mutex.readUnlock();

            if (!omqmap.loggerAliases.AUDIT) {
                update_list += \Qorus.audit.updateLogger();
            }
            if (!omqmap.loggerAliases.ALERT) {
                update_list += \Qorus.alerts.updateLogger();
            }
            if (!omqmap.loggerAliases.HTTP) {
                update_list += \Qorus.httpServer.updateLogger();
            }
            if (!omqmap.loggerAliases.MONITORING) {
                update_list += \OMQ::ConnectionsServer::updateLogger();
            }
            if (!omqmap.loggerAliases."qorus-core") {
                update_list += \Qorus.updateLoggerParams();
            }
            if (!omqmap.loggerAliases.prometheus) {
                update_list += \Qorus.updatePrometheusLogger();
            }
            if (!omqmap.loggerAliases.grafana) {
                update_list += \Qorus.updateGrafanaLogger();
            }
            if (!omqmap.loggerAliases."qorus-master") {
                update_list += \Qorus.updateQorusMasterLogger();
            }
        }

        map call_function($1, params), update_list;
    }

    # updates internal interface maps with new logger info, notifies all affected processes that the logger has been updated
    private:internal updateAndNotifyAffectedLoggers(string type, auto pk, *hash<auto> new_logger) {
        switch (type) {
            case "workflows": {
                updateWorkflowLogger(pk.toInt(), new_logger);
                break;
            }
            case "services": {
                updateServiceLogger(pk.toInt(), new_logger);
                break;
            }
            case "jobs": {
                updateJobLogger(pk.toInt(), new_logger);
                break;
            }
            case "qdsp": {
                Qorus.dsmanager.updateLogger(pk, new_logger);
                break;
            }
            case "AUDIT": {
                Qorus.audit.updateLogger(new_logger.params);
                break;
            }
            case "ALERT": {
                Qorus.alerts.updateLogger(new_logger.params);
                break;
            }
            case "HTTP": {
                Qorus.httpServer.updateLogger(new_logger.params);
                break;
            }
            case "MONITORING": {
                OMQ::ConnectionsServer::updateLogger(new_logger.params);
                break;
            }
            case "qorus-core": {
                Qorus.updateLoggerParams(new_logger.params);
                break;
            }
            case "prometheus": {
                Qorus.updatePrometheusLogger(new_logger.params);
                break;
            }
            case "grafana": {
                Qorus.updateGrafanaLogger(new_logger.params);
                break;
            }
            case "qorus-master": {
                Qorus.updateQorusMasterLogger(new_logger.params);
                break;
            }
            case "system": {
                updateSystemLoggers(new_logger.params);
                break;
            }
            default:
                QDBG_LOG("invalid logger type %y", type);
                QDBG_ASSERT(False);
                break;
        }
    }

    deleteLogger(string type, *string colname, auto pk) {
        # first map ID to an interface configuration
        *hash<auto> ix_info = getLoggerIdForInterface(type, pk, True);
        if (ix_info && !ix_info.loggerid) {
            throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
        }

        QDBG_LOG("QorusMapManager::deleteLogger() type: %y colname: %y pk: %y ix_info: %y aliases: %y", type, colname, pk, ix_info, omqmap.loggerAliases);

        *hash<auto> logger;
        bool is_default;
        {
            AutoWriteLock arl(map_mutex);

            if (ix_info.loggerid) {
                logger = remove omqmap.loggerMap{ix_info.loggerid};
                if (logger) {
                    is_default = False;
                }
            } else {
                QDBG_ASSERT(!pk.val());
                logger = remove omqmap.loggerMap{remove omqmap.loggerAliases{type}};
                if (logger) {
                    is_default = InterfaceLoggersWithSystem{type} ?? False;
                }
            }

            if (!logger) {
                if (pk.val()) {
                    throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
                } else {
                    throw "NO-LOGGER", sprintf("there is no %y logger", type);
                }
            }
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_success omqp.commit();
                on_error omqp.rollback();

                # must delete loggerid from interface table first
                if (colname) {
                    updateInterfaceLoggerIdIntern(type, colname, pk);
                }

                AbstractTable loggersTable = Qorus.dsmanager.getOmqTable("loggers");
                if (!loggersTable.del({"loggerid": logger.loggerid})) {
                    qlog(LoggerLevel::INFO, "WARNING: failed to delete loggerid %d for logger type %y (ID %y)",
                        logger.loggerid, type, pk);
                }
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

        # get the new logger that will be used after this logger is deleted (if any)
        # do not send the loggerid, as we don't want to update the loggerid in any case
        *hash<auto> new_logger = Qorus.qmm.lookupLogger(InterfaceLoggers{type} ? type : "system") - "loggerid";

        QDBG_LOG("QorusMapManager::deleteLogger() type: %y colname: %y pk: %y ix_info: %y aliases: %y new_logger: %y (type: %y)", type, colname, pk, ix_info, omqmap.loggerAliases, new_logger, InterfaceLoggers{type} ? type : "system");

        updateAndNotifyAffectedLoggers(type, pk, new_logger);

        # send a system event about the logger deletion
        hash<auto> info = {
            "loggerid": logger.loggerid,
            "interface": type,
            "current_logger": new_logger,
            "isDefault": is_default,
        };

        if (pk.val()) {
            info.interfaceid = pk;
        }

        qlog(LoggerLevel::INFO, "logger %d for %s deleted", logger.loggerid,
            pk.val() ? sprintf("%s ID %y", type, pk) : type);
        Qorus.events.postLoggerDeleted(info);
    }

    /** Create appender based on received params; updates internal maps and affected processes
        @param type interface table name (e.g. services/jobs/workflows)
        @param params appender params
        @param pk PK value in interface table

        @return created appender id

        @throw INVALID-INTERFACE no such interface
        @throw NO-LOGGER logger does not exist
    */
    int addAppender(string type, auto pk, hash<AppenderParams> params) {
        # first map ID to an interface configuration
        *hash<auto> ix_info = getLoggerIdForInterface(type, pk, True);
        if (ix_info && !ix_info.loggerid) {
            throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
        }

        hash<auto> logger_info;
        softint appender_id;
        bool is_default;
        {
            AutoWriteLock arl(map_mutex);

            reference logger;
            if (ix_info.loggerid) {
                logger = \omqmap.loggerMap{ix_info.loggerid};
                is_default = False;
            } else {
                QDBG_ASSERT(!pk.val());
                logger = \omqmap.loggerMap{omqmap.loggerAliases{type}};
                is_default = InterfaceLoggersWithSystem{type} ?? False;
            }

            if (!logger) {
                if (pk.val()) {
                    throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
                } else {
                    throw "NO-LOGGER", sprintf("there is no logger for logger source %y", type);
                }
            }

            appender_id = logger.params.appenders.firstKey() ?? 0;
            ++appender_id;

            logger.params.appenders{appender_id} = params;
            writeLoggerIntern(logger);

            logger_info = logger;
        }

        updateAndNotifyAffectedLoggers(type, pk, logger_info);

        hash<auto> event = {
            "loggerid": logger_info.loggerid,
            "logger_appenderid": appender_id,
            "interface": type,
            "isDefault": is_default,
            "params": params,
        };

        if (pk) {
            event.interfaceid = pk;
        }

        Qorus.events.postAppenderCreated(event);
        qlog(LoggerLevel::INFO, "appender %d created for logger %d for %s with params: %y", appender_id, logger_info.loggerid,
            pk.val() ? sprintf("%s ID %y", type, pk) : type, params);
        return appender_id;
    }

    /** Creates a new logger; updates internal maps and processes; raises events

        @param type interface table name (e.g. services/jobs/workflows)
        @param colname the PK column name
        @param pk the PK value (ID or name) of the interface take
        @param params interface parameters

        @return the logger ID

        @throw LOGGER-EXISTS logger for the given source already exists
    */
    int createLogger(string type, *string colname, auto pk, hash<LoggerParams> params) {
        # FIXME: implement logger source reverse maps
        # first map ID to an interface configuration
        *hash<auto> ix_info = getLoggerIdForInterface(type, pk, True);
        if (ix_info) {
            if (ix_info.loggerid) {
                throw "LOGGER-EXISTS", sprintf("%y with ID %y has an existing logger", type, pk);
            }
        } else if (!colname && omqmap.loggerAliases{type}) {
            # check for existing system loggers
            throw "LOGGER-EXISTS", sprintf("logger source %y has an existing logger", type);
        }

        QDBG_LOG("QorusMapManager::createLogger() type: %y colname: %y pk: %y params: %y ix_info: %y aliases: %y", type, colname, pk, params, ix_info, omqmap.loggerAliases);

        # save logger ID in DB
        int loggerid;
        bool do_alias = !pk.val() && (SystemLoggersWithSystem{type} || InterfaceLoggers{type});
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_success omqp.commit();
                on_error omqp.rollback();

                AbstractTable loggersTable = Qorus.dsmanager.getOmqTable("loggers");
                loggerid = loggersTable.insert(
                    {
                        "interface_table_name": do_alias ? type : NULL,
                        "params": serialize_qorus_data(params)
                    },
                    {
                        "returning": "loggerid",
                    },
                ).loggerid;

                # must update interface table after creating logger
                if (colname) {
                    updateInterfaceLoggerIdIntern(type, colname, pk, loggerid);
                }
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

        bool is_default;
        hash<auto> logger_info;
        {
            AutoWriteLock arl(map_mutex);

            omqmap.loggerMap{loggerid} = logger_info = {
                "params": params,
                "loggerid": loggerid,
                "interface_table_name": type,
            };

            if (ix_info) {
                is_default = False;
            } else {
                is_default = InterfaceLoggersWithSystem{type} ?? False;
            }

            if (do_alias) {
                omqmap.loggerAliases{type} = loggerid;
            }
        }

        updateAndNotifyAffectedLoggers(type, pk, logger_info);

        # post system events
        Qorus.events.postLoggerCreated({
            "loggerid": loggerid,
            "params": params,
            "interface": type,
            "isDefault": is_default,
            "interfaceid": pk,
        });
        map Qorus.events.postAppenderCreated({
            "loggerid": loggerid,
            "logger_appenderid": $1.key.toInt(),
            "interface": type,
            "isDefault": is_default,
            "params": $1.value,
            "interfaceid": pk,
        }), params.appenders.pairIterator();

        qlog(LoggerLevel::INFO, "Logger with id %d for %s created with params: %y", loggerid,
            pk.val() ? sprintf("%s ID %y", type, pk) : type, params);
        return loggerid;
    }

    /** Updates an existing logger; updates internal maps and processes; raises events

        @param type interface table name (e.g. services/jobs/workflows)
        @param pk the PK value (ID or name) of the interface take
        @param params logger parameters

        @throw NO-LOGGER the logger for the given source does not exist
    */
    updateLogger(string type, auto pk, hash<LoggerParams> params) {
        # first map ID to an interface configuration
        *hash<auto> ix_info = getLoggerIdForInterface(type, pk, True);
        if (ix_info && !ix_info.loggerid) {
            throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
        }

        hash<auto> logger_info;
        softint appender_id;
        bool is_default;
        {
            AutoWriteLock arl(map_mutex);

            reference logger;
            if (ix_info.loggerid) {
                logger = \omqmap.loggerMap{ix_info.loggerid};
                is_default = False;
            } else {
                QDBG_ASSERT(!pk.val());
                logger = \omqmap.loggerMap{omqmap.loggerAliases{type}};
                is_default = InterfaceLoggersWithSystem{type} ?? False;
            }

            if (!logger) {
                if (pk.val()) {
                    throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
                } else {
                    throw "NO-LOGGER", sprintf("there is no logger for logger source %y", type);
                }
            }

            # do nothing if the params are the same
            if (logger.params == params) {
                return;
            }

            logger.params = params;

            writeLoggerIntern(logger);

            logger_info = logger;
        }

        updateAndNotifyAffectedLoggers(type, pk, logger_info);

        hash<auto> event = logger_info + {
            "interface": type,
            "isDefault": is_default,
        } - "interface_table_name";

        if (pk.val()) {
            event.interfaceid = pk;
        }

        Qorus.events.postLoggerUpdated(event);
        qlog(LoggerLevel::INFO, "logger with id %d successfully updated with params: %y", logger_info.loggerid,
            logger_info.params);
    }

    private:internal int updateInterfaceLoggerIdDb(string type, string colname, auto pk, *int loggerid) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_success omqp.commit();
                on_error omqp.rollback();

                return updateInterfaceLoggerIdIntern(type, colname, pk, loggerid);
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

    private:internal int updateInterfaceLoggerIdIntern(string type, string colname, auto pk, *int loggerid) {
        AbstractTable table;
        hash wh;
        wh = {colname: pk};
        if (type == "qdsp") {
            table = Qorus.dsmanager.getOmqTable("connections");
            wh.connection_type = "DATASOURCE";
        } else {
            table = Qorus.dsmanager.getOmqTable(type);
        }
        return table.update({"loggerid": loggerid}, wh);
    }

    deleteAppender(int appender_id, string type, auto pk) {
        # first map ID to an interface configuration
        *hash<auto> ix_info = getLoggerIdForInterface(type, pk, True);
        if (ix_info && !ix_info.loggerid) {
            throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
        }

        reference logger;
        bool is_default;

        AutoWriteLock arl(map_mutex);

        if (ix_info.loggerid) {
            logger = \omqmap.loggerMap{ix_info.loggerid};
            is_default = False;
        } else {
            QDBG_ASSERT(!pk.val());
            logger = \omqmap.loggerMap{omqmap.loggerAliases{type}};
            is_default = InterfaceLoggersWithSystem{type} ?? False;
        }

        if (!remove logger.params.appenders{appender_id}) {
            if (pk.val()) {
                throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
            } else {
                throw "NO-LOGGER", sprintf("there is no logger for logger source %y", type);
            }
        }

        writeLoggerIntern(logger);

        hash<auto> event = {
            "loggerid": logger.loggerid,
            "logger_appenderid": appender_id,
            "interface": type,
            "isDefault": is_default,
        };
        Qorus.events.postAppenderDeleted(event);

        qlog(LoggerLevel::INFO, "appender %d successfully deleted", appender_id);
    }

    /** Update the given appender based on received params
        @param type interface table name (e.g. services/jobs/workflows)
        @param pk PK value in interface table
        @param appender_id the appender ID to update
        @param appender_hash new appender params
    */
    updateAppender(string type, auto pk, softstring appender_id, hash<auto> appender_hash) {
        # first map ID to an interface configuration
        *hash<auto> ix_info = getLoggerIdForInterface(type, pk, True);
        if (ix_info && !ix_info.loggerid) {
            throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
        }

        hash<AppenderParams> params;
        hash<auto> logger_info;
        bool is_default;
        {
            AutoWriteLock arl(map_mutex);

            reference logger;
            if (ix_info.loggerid) {
                logger = \omqmap.loggerMap{ix_info.loggerid};
                is_default = False;
            } else {
                QDBG_ASSERT(!pk.val());
                logger = \omqmap.loggerMap{omqmap.loggerAliases{type}};
                is_default = InterfaceLoggersWithSystem{type} ?? False;
            }

            if (!logger) {
                if (pk.val()) {
                    throw "NO-LOGGER", sprintf("%y with ID %y has no logger", type, pk);
                } else {
                    throw "NO-LOGGER", sprintf("there is no logger for logger source %y", type);
                }
            }

            if (!logger.params.appenders{appender_id}) {
                if (pk.val()) {
                    throw "NO-APPENDER", sprintf("logger source %y with ID %y has no appender with ID %d", type, pk, appender_id);
                } else {
                    throw "NO-APPENDER", sprintf("logger source %y has no appender with ID %d", type, appender_id);
                }
            }

            # add existing params to appender hash
            appender_hash += map {$1.key: $1.value},
                logger.params.appenders{appender_id}.pairIterator(),
                !appender_hash{$1.key}.val();
            params = Qorus.loggerController.checkAndConvertAppenderParams(appender_hash);

            logger.params.appenders{appender_id} = params;
            writeLoggerIntern(logger);

            logger_info = logger;
        }

        updateAndNotifyAffectedLoggers(type, pk, logger_info);

        hash<auto> event = {
            "loggerid": logger_info.loggerid,
            "logger_appenderid": appender_id.toInt(),
            "interface": type,
            "isDefault": is_default,
            "params": params,
        };

        if (pk) {
            event.interfaceid = pk;
        }

        Qorus.events.postAppenderUpdated(event);
        qlog(LoggerLevel::INFO, "appender %d updated for logger %d for %s with params: %y", appender_id, logger_info.loggerid,
            pk.val() ? sprintf("%s ID %y", type, pk) : type, params);
    }

    #! returns True if the logger was updated, False if not
    private:internal softbool writeLoggerIntern(hash<auto> logger) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_success omqp.commit();
                on_error omqp.rollback();

                AbstractTable loggersTable = Qorus.dsmanager.getOmqTable("loggers");
                return loggersTable.update({
                    "params": serialize_qorus_data(logger.params),
                }, {
                    "loggerid": logger.loggerid,
                });
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

    #! read data from db and update loggermap
    hash<auto> reloadLoggers(*bool init) {
        on_success
            Qorus.getMaster().broadcastConfirmToAllInterfaces("qmm", "invalidateLoggerCache");

        # the logger map retrieval code is shared between qorus-master and qorus-core
        # as it's needed to seed the initial logger map from qorus-master -> qorus-core
        *hash<auto> h = Qorus.getLoggerMap(Qorus.dsmanager.getOmqTable("loggers"));

        # get copy of old cache to detect and enforce changes
        hash<auto> old_cache;
        {
            AutoWriteLock awl(map_mutex);
            # get a copy of the old caches
            old_cache = omqmap{"loggerMap", "loggerAliases"};
            # update internal caches
            omqmap += h;
        }

        # only process updates for reloads
        if (!init) {
            # get a list of deleted logger IDs
            *list<string> deleted_loggerids = keys (old_cache.loggerMap - keys h.loggerMap);
            # get deleted default loggers: alias -> non-zero int (not not use;-only keys are useful)
            *hash<string, int> updated_default_loggers = old_cache.loggerAliases{deleted_loggerids};
            # get a list of new logger IDs
            *hash<auto> new_loggerid_map = (h.loggerMap - keys old_cache.loggerMap);
            # get a list of new logger IDs
            *list<string> new_loggerids = keys new_loggerid_map;
            # add new default loggers
            map updated_default_loggers{$1.key} = -1, h.loggerAliases.pairIterator(), new_loggerid_map{$1.value};

            QDBG_LOG("deleted_loggerids: %y new_loggerids: %y updated_default_loggers: %y", deleted_loggerids, new_loggerids, updated_default_loggers);

            # make a list of updated logger IDs
            *list<string> updated_loggerids = ();
            foreach hash<auto> i in (old_cache.loggerMap.pairIterator()) {
                if (h.loggerMap{i.key} != i.value) {
                    updated_loggerids += i.key;
                }
            }
            # hash of updated default loggers
            updated_default_loggers += h.loggerAliases{updated_loggerids};

            if (updated_loggerids || deleted_loggerids) {
                # map of loggerid -> interface ID of interfaces with updated loggers
                *hash<string, auto> updated_loggers;
                # list of IDs for interfaces using an updated or deleted default logger
                list<softstring> default_ids;
                # map of loggerid -> interface ID of interfaces with deleted loggers
                *hash<string, auto> deleted_loggers;

                # process updated and deleted workflow loggers
                {
                    {
                        AutoWriteLock awl(map_mutex);
                        deleted_loggers = remove omqmap.logger_wfmap{deleted_loggerids};
                        updated_loggers = omqmap.logger_wfmap{updated_loggerids};
                        if (updated_default_loggers.workflows) {
                            default_ids = map $1.workflowid, omqmap.wfmap.iterator(), !$1.loggerid;
                        }
                    }

                    # assign the default workflow logger
                    map updateWorkflowLoggerDb($1.toInt(), h.loggerMap{h.loggerAliases.workflows}), deleted_loggers.iterator();
                    # update workflow loggers
                    map SM.updateLogger($1.value.toInt(), h.loggerMap{$1.key}.params), updated_loggers.pairIterator();
                    # update workflows using the updated default workflow logger
                    map SM.updateLogger($1.toInt(), h.loggerMap{h.loggerAliases.workflows}.params), default_ids;
                }

                # process updated and deleted service loggers
                {
                    {
                        AutoWriteLock awl(map_mutex);
                        deleted_loggers = remove omqmap.logger_svcmap{deleted_loggerids};
                        updated_loggers = omqmap.logger_svcmap{updated_loggerids};
                        if (updated_default_loggers.services) {
                            default_ids = map $1.serviceid, omqmap.servicemap.iterator(), !$1.loggerid;
                        } else {
                            remove default_ids;
                        }
                    }

                    # assign the default service logger
                    map updateServiceLoggerDb($1.toInt(), h.loggerMap{h.loggerAliases.services}), deleted_loggers.iterator();
                    # update services loggers
                    map services.updateLogger($1.value.toInt(), h.loggerMap{$1.key}.params), updated_loggers.pairIterator();
                    # update services using the updated default service logger
                    map services.updateLogger($1.toInt(), h.loggerMap{h.loggerAliases.services}.params), default_ids;
                }

                # process updated and deleted job loggers
                {
                    {
                        AutoWriteLock awl(map_mutex);
                        deleted_loggers = remove omqmap.logger_jobmap{deleted_loggerids};
                        # convert jobid -> name
                        deleted_loggers = map {$1.key: omqmap.jmap{$1.value}.name}, deleted_loggers.pairIterator();
                        updated_loggers = omqmap.logger_jobmap{updated_loggerids};
                        # convert jobid -> name
                        updated_loggers = map {$1.key: omqmap.jmap{$1.value}.name}, updated_loggers.pairIterator();
                        if (updated_default_loggers.jobs) {
                            default_ids = map $1.name, omqmap.jmap.iterator(), !$1.loggerid;
                        } else {
                            remove default_ids;
                        }
                    }

                    # assign the default job logger
                    map updateJobLoggerDb($1, h.loggerMap{h.loggerAliases.jobs}), deleted_loggers.iterator();
                    # update job loggers
                    map Qorus.jobManager.updateLogger($1.value, h.loggerMap{$1.key}.params), updated_loggers.pairIterator();
                    # update jobs using the updated default job logger
                    map Qorus.jobManager.updateLogger($1, h.loggerMap{h.loggerAliases.jobs}.params), default_ids;
                }

                # proocess updated and deleted qdsp loggers
                Qorus.dsmanager.processUpdatedAndDeletedLoggers(h.loggerMap{updated_loggerids}, deleted_loggerids,
                    h.loggerMap{h.loggerAliases.qdsp}, updated_default_loggers.qdsp.toBool());

                # process updated default loggers
                foreach string type in (keys updated_default_loggers) {
                    switch (type) {
                        case "qdsp": {
                            Qorus.dsmanager.updateLogger(NOTHING, h.loggerMap{h.loggerAliases.qdsp});
                            break;
                        }
                        case "AUDIT": {
                            Qorus.audit.updateLogger(h.loggerMap{h.loggerAliases.AUDIT}.params);
                            break;
                        }
                        case "ALERT": {
                            Qorus.alerts.updateLogger(h.loggerMap{h.loggerAliases.ALERT}.params);
                            break;
                        }
                        case "HTTP": {
                            Qorus.httpServer.updateLogger(h.loggerMap{h.loggerAliases.HTTP}.params);
                            break;
                        }
                        case "MONITORING": {
                            OMQ::ConnectionsServer::updateLogger(h.loggerMap{h.loggerAliases.MONITORING}.params);
                            break;
                        }
                        case "prometheus": {
                            Qorus.updatePrometheusLogger(h.loggerMap{h.loggerAliases.prometheus}.params);
                            break;
                        }
                        case "grafana": {
                            Qorus.updateGrafanaLogger(h.loggerMap{h.loggerAliases.grafana}.params);
                            break;
                        }
                        case "qorus-core": {
                            Qorus.updateLoggerParams(h.loggerMap{h.loggerAliases."qorus-core"}.params);
                            break;
                        }
                        case "qorus-master": {
                            Qorus.updateQorusMasterLogger(h.loggerMap{h.loggerAliases."qorus-master"}.params);
                            break;
                        }
                        case "system": {
                            updateSystemLoggers();
                            break;
                        }
                    }
                }
            }
        }

        return {"loggers": omqmap.loggerMap.size()};
    }

    #! Validates Qorus object (service, workflow, job, ...) names and identifiers
    /** Allowed characters are a-z A-Z 0-9 - _ (+ UTF-8 letters)

        @param value the value of the field
        @param type the object type
        @param field_name the name of the field

        @throw INVALID-VALUE thrown if \a value is invalid
    */
    static checkIdentifier(string value, string type, string field_name) {
        if (!value.val()) {
            throw WEBIDE_ERROR_INVALID_VALUE, sprintf("%s %s %y is invalid because it is empty", type, field_name,
                value), "empty-value";
        }
        if (value =~ /[^[:alnum:]-_]+/u) {
            throw WEBIDE_ERROR_INVALID_VALUE, sprintf("%s %s %y is invalid; only UTF-8 alphanumeric characters plus "
                "'_' and '-' are allowed in %s values", type, field_name, value, field_name),
                "invalid-characters-in-value";
        }
    }

    static private verifyCreateMetadata(string type, reference<hash<auto>> ix_data, hash<auto> metadata) {
        QorusMapManager::verifyMetadataIntern(type, \ix_data, metadata, True);
    }

    static private verifyUpdateMetadata(string type, reference<hash<auto>> ix_data, hash<auto> metadata) {
        QorusMapManager::verifyMetadataIntern(type, \ix_data, metadata);
    }

    static private verifyMetadataIntern(string type, reference<hash<auto>> ix_data, hash<auto> metadata, *bool create) {
        # process author from a list -> string
        if (ix_data.author.typeCode() == NT_LIST) {
            ix_data.author = ix_data.author.join("; ");
        }

        foreach hash<auto> i in (ix_data.pairIterator()) {
            *hash<auto> field = metadata{i.key};
            if (!field) {
                throw type.upr() + "-" + (create ? "CREATION" : "UPDATE") + "-ERROR",
                    sprintf("unknown %s attribute %y; known attributes: %y", type, i.key, keys metadata);
            }
            if (create && !exists i.value && field.default_value) {
                ix_data{i.key} = field.default_value;
                continue;
            }
            if (!field.type{i.value.type()}) {
                if (!exists i.value && !field.required) {
                    remove ix_data{i.key};
                    continue;
                }
                throw type.upr() + "-" + (create ? "CREATION" : "UPDATE") + "-ERROR",
                    sprintf("%s attribute %y has invalid type %y; expecting: %y", type, i.key, i.value.type(),
                        keys field.type);
            }
            if (*string subtype = field.subtype) {
                try {
                    FieldSubtypeMap{subtype}(i.value);
                } catch (hash<ExceptionInfo> ex) {
                    throw type.upr() + "-" + (create ? "CREATION" : "UPDATE") + "-ERROR",
                        sprintf("invalid value for %y: %s", i.key, ex.desc);
                }
            }
        }
        if (create) {
            # ensure all required fields are present and default values are respected
            foreach hash<auto> i in (metadata.pairIterator()) {
                if (!exists ix_data{i.key}) {
                    if (exists i.value.default_value) {
                        ix_data{i.key} = i.value.default_value;
                        continue;
                    }
                    if (i.value.required) {
                        throw type.upr() + "-" + (create ? "CREATION" : "UPDATE") + "-ERROR",
                            sprintf("required %s attribute %y is missing; cannot create %y", type, i.key, type);
                    }
                }
            }
        } else if (auto val = ix_data{type + "id"}) {
            throw type.upr() + "-UPDATE-ERROR", sprintf("cannot modify the %sid (value given: %y)", type, val);
        }

        # verify that the new name has a valid format
        if (exists ix_data.name) {
            QorusMapManager::checkIdentifier(ix_data.name, type, "name");
        }

        # verify that no tag begins with "_"
        foreach string tag in (keys ix_data.tags) {
            if (tag =~ /^_/) {
                throw type.upr() + "-UPDATE-ERROR", sprintf("tag %y has an invalid name; tags cannot begin with the "
                    "'_' character", tag);
            }
        }
    }

    private writeTagsNoCommit(string type, int id, hash<auto> new_tags) {
        AbstractTable tags = Qorus.dsmanager.getOmqTable(type + "_tags");
        string idname = type + "id";
        map tags.insert({
            idname: id,
            "tag": $1.key,
            "value": $1.value,
        }), new_tags.pairIterator();
    }

    private verifyCreateLib(string type, int id, reference<hash<auto>> ix_data) {
        verifyLibIntern(type, id, \ix_data, True);
    }

    private verifyUpdateLib(string type, int id, reference<hash<auto>> ix_data) {
        verifyLibIntern(type, id, \ix_data);
    }

    private verifyLibIntern(string type, int id, reference<hash<auto>> ix_data, *bool create) {
        map_mutex.readLock();
        on_exit map_mutex.readUnlock();

        list<hash<auto>> ll;
        if (exists ix_data.mappers) {
            foreach string mapper in (ix_data.mappers) {
                (*string name, *string version) = (mapper =~ x/(^[^:]+):(.+)$/);
                if (!name || !version) {
                    throw type.upr() + "-" + (create ? "CREATION" : "UPDATE") + "-ERROR",
                        sprintf("%s %d has invalid mapper entry %y; expecting " "\"<name>:<version>\" format", type, id,
                            mapper);
                }

                *int mapperid = omqmap.mrmap{name}{version};
                if (!mapperid) {
                    throw type.upr() + "-" + (create ? "CREATION" : "UPDATE") + "-ERROR",
                        sprintf("%s %d refers to unknown mapper %s v%s", type, id, name, version);
                }
                hash<auto> mapinfo = omqmap.mmap{mapperid};
                ll += {
                    "mapperid": mapperid,
                } + mapinfo{"name", "version", "type"};
            }
            ix_data.mappers = remove ll;
        }

        if (ix_data.vmaps) {
            foreach string name in (ix_data.vmaps) {
                *int vmapid = omqmap.vmrmap{name};
                if (!vmapid) {
                    throw type.upr() + "-" + (create ? "CREATION" : "UPDATE") + "-ERROR",
                        sprintf("%s %d refers to unknown value map %s", type, id, name);
                }
                hash<auto> mapinfo = omqmap.vmmap{vmapid};
                ll += {
                    "id": vmapid,
                } + mapinfo{"name", "throws_exception", "valuetype", "mapsize"};
            }
            ix_data.vmaps = remove ll;
        }
    }

    private deleteClassFromDb(int id) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                int ndeps = sqlif.omqp.exec("delete from class_dependencies where classid = %v", id);
                int ntags = sqlif.omqp.exec("delete from class_tags where classid = %v", id);
                omqp.exec("delete from classes where classid = %v", id);
                olog(LoggerLevel::DEBUG, "DELETE CLASS %d: deleted from the database (%d dep%s, %d tag%s)", id, ndeps,
                    ndeps == 1 ? "" : "s", ntags, ntags == 1 ? "" : "s");
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

    deleteClass(int id) {
        *hash<auto> cls;
        on_success {
            Qorus.events.postClassDeleted(tld.cx, cls.name, cls.version, id);
            Qorus.audit.classDeleted(tld.cx, id, sprintf("%y", cls{"name", "version"}));
            # NOTE: the class metadata cache is now centralized and not part of the distributed lib map cache
            Qorus.creatorWsHandler.broadcastInterfaceDeleted("class", id, cls.name, cls{"name", "version", "classid"});
        }

        {
            try {
                deleteClassFromDb(id);
            } catch (hash<ExceptionInfo> ex) {
                olog(LoggerLevel::INFO, "error deleting class: %s", get_exception_string(ex));
                throw "CLASS-DELETIION-ERROR", sprintf("classid %d: %s: %s", id, ex.err, ex.desc);
            }

            {
                WriteLockHelper wlh(map_mutex);
                cls = omqmap.classmap{id};
                if (!cls) {
                    throw "CLASS-DELETION-ERROR", sprintf("class ID %d does not exist", id);
                }
                QDBG_LOG("QorusMapManager::deleteClass() id: %y cls: %y", id, cls);

                remove omqmap.classmap{id};
                remove omqmap.classrmap{cls.name}{cls.version};
                if (omqmap.classrmap{cls.name}.lastversion == cls.version) {
                    # get latest version by created date
                    *date vd;
                    *string v;
                    foreach auto i in (omqmap.classrmap{cls.name}.pairIterator()) {
                        if (i.value.typeCode() != NT_INT) {
                            continue;
                        }
                        hash<auto> ch = omqmap.classmap{omqmap.classrmap{cls.name}{i.key}};
                        if (ch.created > vd) {
                            vd = ch.created;
                            v = ch.version;
                        }
                    }
                    if (exists v) {
                        omqmap.classrmap{cls.name} += {
                            "lastversion": v,
                            "lvcreated": vd,
                        };
                    } else {
                        remove omqmap.classrmap{cls.name};
                    }
                }
            }
        }
    }

    private deleteJobFromDb(int id) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                int rows = sqlif.omqp.exec("delete from job_errors where job_instanceid in "
                    "(select job_instanceid from job_instance where jobid = %v)", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_errors row(s) deleted", id, rows);
                }
                # delete audit events
                rows = sqlif.omqp.exec("delete from audit_events where jobid = %v and job_instanceid is not null", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d audit event row(s) deleted", id, rows);
                }
                rows = sqlif.omqp.exec("delete from job_instance where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_instance row(s) deleted", id, rows);
                }
                # issue 2446: delete job instance stats stage
                rows = sqlif.omqp.exec("delete from job_instance_stats_stage where objectid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job instance stats stage row(s) deleted", id, rows);
                }
                # issue 2446: delete job instance stats
                rows = sqlif.omqp.exec("delete from job_instance_stats where objectid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job instance stats row(s) deleted", id, rows);
                }
                rows = omqp.exec("delete from job_options where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_options row(s) deleted", id, rows);
                }
                # delete job library rows
                rows = omqp.exec("delete from job_lib where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_lib row(s) deleted", id, rows);
                }
                # delete mappers
                rows = omqp.exec("delete from job_mappers where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_mappers row(s) deleted", id, rows);
                }
                # delete value maps
                rows = omqp.exec("delete from job_vmaps where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_vmaps row(s) deleted", id, rows);
                }
                # delete group jobs
                rows = omqp.exec("delete from group_jobs where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d group_jobs row(s) deleted", id, rows);
                }
                # delete audit events
                rows = omqp.exec("delete from audit_events where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d audit event row(s) deleted", id, rows);
                }
                rows = omqp.exec("delete from job_state_data where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_state_data row(s) deleted", id, rows);
                }
                rows = omqp.exec("delete from job_persistent_state_data where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_persistent_state_data row(s) deleted", id, rows);
                }
                # delete config items
                rows = omqp.exec("delete from config_item_values where \"level\" = %v", "job:" + id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d config_item_values row(s) deleted", id, rows);
                }
                rows = omqp.exec("delete from job_config_items where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_config_items row(s) deleted", id, rows);
                }
                rows = omqp.exec("delete from job_tags where jobid = %v", id);
                if (rows) {
                    olog(LoggerLevel::DEBUG, "DELETE JOB %d: %d job_tags row(s) deleted", id, rows);
                }

                omqp.exec("delete from jobs where jobid = %v", id);
                olog(LoggerLevel::DEBUG, "DELETE JOB %d: job deleted from the database", id);
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

    deleteJob(int id) {
        *hash<auto> job;
        on_success {
            Qorus.events.postJobDeleted(tld.cx, job.name, job.version, id);
            Qorus.audit.jobDeleted(tld.cx, id, sprintf("%y", job{"name", "version", "active", "remote", "enabled",
                "expiry_date"}));
            # NOTE: the job metadata cache is now centralized
            Qorus.creatorWsHandler.broadcastInterfaceDeleted("job", id, job.name, job{"name", "version", "jobid"});
        }

        {
            AtomicJobActionHelper atomic_action_helper(id);

            try {
                Qorus.rbac.disableSyntheticGroupWait("job", id, atomic_action_helper);
                deleteJobFromDb(id);
            } catch (hash<ExceptionInfo> ex) {
                olog(LoggerLevel::INFO, "error deleting job: %s", get_exception_string(ex));
                throw "JOB-DELETIION-ERROR", sprintf("jobid %d: %s: %s", id, ex.err, ex.desc);
            }

            {
                WriteLockHelper wlh(map_mutex);
                job = omqmap.jmap{id};
                if (!job) {
                    throw "JOB-DELETION-ERROR", sprintf("job ID %d does not exist", id);
                }

                remove omqmap.jmap{id};
                remove omqmap.jrmap{job.name};
            }
        }

        Qorus.rbac.rescanJobsDelta((id,));
        Qorus.alerts.clearAllOngoingAlerts("JOB", id);
    }

    #! Returns edit locks
    *hash<string, hash<string, hash<EditMapInfo>>> getEditLocks() {
        map_mutex.readLock();
        on_exit map_mutex.readUnlock();
        return edit_map;
    }

    #! Returns simple name reservations
    *hash<string, hash<string, string>> getSimpleNameReservations() {
        map_mutex.readLock();
        on_exit map_mutex.readUnlock();
        return reserved_names;
    }

    #! Returns complex name reservations
    *hash<string, hash<string, hash<string, string>>> getComplexNameReservations() {
        map_mutex.readLock();
        on_exit map_mutex.readUnlock();
        return reserved_names_version;
    }

    #! Returns the reservation map
    *hash<string, hash<ReservationInfo>> getReservationMap() {
        map_mutex.readLock();
        on_exit map_mutex.readUnlock();
        return reservation_map;
    }

    #! Returns the tab_token for a simple reservation
    /** the lock must be held
    */
    *string checkReservationLocked(string type, string name) {
        QDBG_ASSERT(map_mutex.lockOwner());
        return reserved_names{type}{name};
    }

    #! Locks an interface for editing
    /** @return the current field data for the interface, if any
    */
    *hash<auto> openInterface(int cid, string tab_token, string type, int id) {
        *string edit_tab_token;
        {
            map_mutex.writeLock();
            on_exit map_mutex.writeUnlock();

            edit_tab_token = edit_map{type}{id}.tab_token;
            if (!edit_tab_token) {
                edit_map{type}{id} = <EditMapInfo>{
                    "tab_token": tab_token,
                    "cid": cid,
                };
                Qorus.creatorWsHandler.broadcastInterfaceOpened(cid, type, id);
                return CreatorBaseRestClass::doGetFieldKeyValueData(type, id);
            }
        }
        if (edit_tab_token != tab_token) {
            QDBG_LOG("QorusMapManager::openInterface() cid: %y tab_token: %y type: %y id: %y edit_tab_token: %y", cid, tab_token, type, id, edit_tab_token);
            throw "OPEN-ERROR", sprintf("tab %y cannot open %s %d; it is already open for editing by another "
                "connection", tab_token, type, id);
        }
        return CreatorBaseRestClass::doGetFieldKeyValueData(type, id);
    }

    #! Unlocks an interface
    closeInterface(string tab_token, string type, int id, *bool ignore_error) {
        QDBG_LOG("closeInterface() tab_token: %y type: %y id: %y ignore_error: %y", tab_token, type, id, ignore_error);

        *list<hash<FieldGroupInfo>> fields;
        *string source_code;
        string name;

        switch (type) {
            case "job": {
                fields = CreatorJobDefinitionRestClass::staticGetFieldsForJob(id, \name);
                # don't select source if there is no interface data
                if (fields) {
                    source_code = CreatorJobDefinitionRestClass::staticGetCodeForJob(id);
                }
                break;
            }

            case "class": {
                fields = CreatorClassDefinitionRestClass::staticGetFieldsForClass(id, \name);
                # don't select source if there is no interface data
                if (fields) {
                    source_code = CreatorClassDefinitionRestClass::staticGetCodeForClass(id);
                }
                break;
            }

            case "connection": {
                fields = CreatorConnectionDefinitionRestClass::staticGetFieldsForConnection(id, \name);
                break;
            }

            default:
                throw "UNIMPLEMENTED", type;
        }

        QDBG_LOG("closeInterface() fields: %y source_code: %y", fields.type(), source_code.type());

        # release any reservation for the tab_token
        releaseReservationForTabTokenIntern(tab_token);

        map_mutex.writeLock();
        on_exit map_mutex.writeUnlock();

        *hash<EditMapInfo> edit_info = edit_map{type}{id};
        QDBG_LOG("closeInterface() edit_tab_token: %y tab_token: %y", edit_info.tab_token, tab_token);
        if (edit_info.tab_token == tab_token) {
            remove edit_map{type}{id};
            # do not send the release event in case of a new object (where there is no name)
            if (name) {
                QDBG_ASSERT(fields);
                Qorus.creatorWsHandler.broadcastInterfaceReleased(edit_info.cid, type, id, name, fields, source_code);
            }
            return;
        } else if (edit_info.tab_token && edit_info.tab_token != tab_token) {
            string err_desc = sprintf("tab %y cannot close %s %d; it is open for editing by another connection",
                    tab_token, type, id);
            if (ignore_error) {
                olog(LoggerLevel::INFO, "error closing interface %y (%d): %s", type, id, err_desc);
            } else {
                throw "CLOSE-ERROR", err_desc;
            }
        }
    }

    #! Checks an interface for editing
    /** the lock must be already acquired before this call
    */
    checkEditLock(string tab_token, string type, int id) {
        *string edit_tab_token = edit_map{type}{id}.tab_token;
        if (!edit_tab_token || edit_tab_token != tab_token) {
            throw "EDIT-ERROR", sprintf("tab %y cannot edit %s %d; it does not own the edit lock for this object",
                tab_token, type, id);
        }
    }

    #! Removes a reservation
    /** @return True if a reservation was released, False if not
    */
    bool releaseReservationForTabToken(string tab_token) {
        *hash<auto> info = reservation_map{tab_token};
        if (!info) {
            return False;
        }

        map_mutex.writeLock();
        on_exit map_mutex.writeUnlock();

        return releaseReservationIntern(tab_token, info.type, info);
    }

    #! Removes a reservation
    /** @return True if a reservation was released, False if not

        Called with the lock held
    */
    private bool releaseReservationForTabTokenIntern(string tab_token) {
        *hash<auto> info = reservation_map{tab_token};
        if (!info) {
            return False;
        }

        return releaseReservationIntern(tab_token, info.type, info);
    }

    #! Removes a reservation
    /** @return True if a reservation was released, False if not

        @throw RELEASE-RESERVATION-ERROR error releasing reservation (only thrown if \a check is True)

        called with the type lock held
    */
    private bool releaseReservationIntern(string tab_token, string type, hash<auto> reservation, *bool check) {
        if (UniqueNameMap{type}) {
            QDBG_LOG("QorusMapManager::releaseReservationIntern() (S) tt: %y type: %y r: %y rs: %y", tab_token, type, reservation, reserved_names);
            QDBG_ASSERT(reservation.name);
            *string reserved_tab_token = reserved_names{type}{reservation.name};
            if (reserved_tab_token) {
                if (reserved_tab_token != tab_token) {
                    if (check) {
                        throw "RELEASE-RESERVATION-ERROR", sprintf("tab %y cannot release the reservation for %s name %y; "
                            "this name is reserved by another connection", tab_token, type, reservation.name);
                    }
                } else {
                    remove reserved_names{type}{reservation.name};
                    if (!reserved_names{type}) {
                        remove reserved_names{type};
                    }
                    QDBG_ASSERT(reservation_map{tab_token}.type == type && reservation_map{tab_token}.name == reservation.name);
                    remove reservation_map{tab_token};
                    return True;
                }
            }
        } else {
            QDBG_LOG("QorusMapManager::releaseReservationIntern() (C) tt: %y type: %y r: %y rs: %y", tab_token, type, reservation, reserved_names_version);
            QDBG_ASSERT(reservation.name);
            QDBG_ASSERT(reservation.version);
            *string reserved_tab_token = reserved_names_version{type}{reservation.name}{reservation.version};
            if (reserved_tab_token) {
                if (reserved_tab_token != tab_token) {
                    if (check) {
                        throw "RELEASE-RESERVATION-ERROR", sprintf("tab %y cannot release the reservation for %s "
                            "name %y v%y; this name and version are reserved by another connection", tab_token, type,
                            reservation.name, reservation.version);
                    }
                } else {
                    remove reserved_names_version{type}{reservation.name}{reservation.version};
                    if (!reserved_names_version{type}{reservation.name}) {
                        remove reserved_names_version{type}{reservation.name};
                    }
                    if (!reserved_names_version{type}) {
                        remove reserved_names_version{type};
                    }
                    QDBG_ASSERT(reservation_map{tab_token}.type == type && reservation_map{tab_token}.name == reservation.name && reservation_map{tab_token}.version == reservation.version);
                    remove reservation_map{tab_token};
                    return True;
                }
            }
        }
        return False;
    }

    #! Releases a name reservation
    /** @return True if the reservation was released, False if not
    */
    bool releaseReservation(string tab_token, string type, hash<auto> reservation, *bool ignore_error) {
        try {
            map_mutex.writeLock();
            on_exit map_mutex.writeUnlock();

            return releaseReservationIntern(tab_token, type, reservation, True);
        } catch (hash<ExceptionInfo> ex) {
            if (ignore_error) {
                olog(LoggerLevel::INFO, "error releasing reservation for tab_token %y type %y reservation: %y: %s", tab_token,
                    type, reservation, get_exception_string(ex));
            } else {
                rethrow;
            }
        }
        return False;
    }

    #! Processes code changes
    /**
        @throw EDIT-ERROR the tab_token does not own the edit lock for the object
        @throw INVALID-TYPE type is unknown
        @throw CODE-ERROR if the type does not support code
    */
    codeUpdated(string tab_token, string type, int id, string source_code) {
        map_mutex.writeLock();
        on_exit map_mutex.writeUnlock();

        checkEditLock(tab_token, type, id);

        if (!CodeObjectMap{type}) {
            throw "CODE-ERROR", sprintf("objects of type %y do not support code", type);
        }
    }

    #! Processes field value changes
    /** @return a reservation hash if a reservation has been made for the interface

        @throw EDIT-ERROR the tab_token does not own the edit lock for the object
        @throw INVALID-TYPE type is unknown
        @throw NAME-RESERVED the name is already reserved by another tab
        @throw ID-ERROR a create operation is trying to create an object for existing ID
        @throw NAME-EXISTS cannot reserve the name because it already exists
    */
    *hash<auto> fieldUpdated(string tab_token, string type, int id, string field, auto value, *hash<auto> attrs) {
        map_mutex.writeLock();
        on_exit map_mutex.writeUnlock();

        checkEditLock(tab_token, type, id);

        if (exists value
            && ((field == "name")
                || (field == "version" && !UniqueNameMap{type}))) {
            return processReservationChange(tab_token, type, id, field, value, attrs);
        }
    }

    #! Reserves a name for a new or updated object
    /** called in the map lock

        @param tab_token the connection sub ID
        @param type the object type
        @param id the object ID
        @param field the field name
        @param value the value of the field
        @param attrs any cached pending attributes for the object

        @return a reservation hash if a reservation has been made for the interface

        @throw EDIT-ERROR the tab_token does not own the edit lock for the object
        @throw INVALID-TYPE type is unknown
        @throw NAME-RESERVED the name is already reserved by another tab
        @throw ID-ERROR a create operation is trying to create an object for existing ID
        @throw NAME-EXISTS cannot reserve the name because it already exists
    */
    private *hash<auto> processReservationChange(string tab_token, string type, int id, string field, string value,
            *hash<auto> attrs) {
        if (field == "name") {
            try {
                QorusMapManager::checkIdentifier(value, type, "name");
            } catch (hash<ExceptionInfo> ex) {
                if (attrs.version || UniqueNameMap{type}) {
                    releaseReservationIntern(tab_token, type, {
                        "name": value,
                        "version": attrs.version,
                    });
                }
                rethrow;
            }
        }

        *hash<auto> rv;
        switch (type) {
            case "connection":
                QDBG_ASSERT(field == "name");
                rv = makeSimpleNameReservation(tab_token, type, id, value,
                    checkConnectionReservationLocked(id, value));
                break;

            case "class":
                rv = makeComplexNameReservation(tab_token, type, id, field, value,
                    checkClassReservationLocked(id, field, value, attrs));
                break;

            case "job":
                QDBG_ASSERT(field == "name");
                rv = makeSimpleNameReservation(tab_token, type, id, value, checkJobReservationLocked(id, value));
                break;

            default:
                throw "INVALID-TYPE", sprintf("unknown type %y", type);
        }

        QDBG_LOG("QorusMapManager::reserveName() name: %y returning rv: %y", value, rv);
        return rv;
    }

    /** called in the map lock
    */
    private *hash<auto> makeSimpleNameReservation(string tab_token, string type, int id, string name, *bool reserve) {
        QDBG_LOG("QorusMapManager::makeSimpleNameReservation() tab_token: %y type: %y id: %y name: %y reserve: %y", tab_token, type, id, name, reserve);
        *string reserved_tab_token = reserved_names{type}{name};
        if (!reserved_tab_token) {
            if (reserve) {
                reserved_names{type}{name} = tab_token;
                reservation_map{tab_token} = <ReservationInfo>{
                    "type": type,
                    "name": name,
                };
            }
        } else {
            if (reserved_tab_token != tab_token) {
                throw WEBIDE_ERROR_NAME_RESERVED, sprintf("tab %y cannot reserve %s ID %d with name %y; this name is "
                    "already reserved", tab_token, type, id, name);
            }
            remove reserve;
        }
        return reserve ? {
            "name": name,
        } : NOTHING;
    }

    /** called in the map lock
    */
    private *hash<auto> makeComplexNameReservation(string tab_token, string type, int id, string field, auto value,
            *hash<auto> reserve) {
        QDBG_LOG("QorusMapManager::makeComplexNameReservation() tab_token: %y type: %y id: %y %y = %y reserve: %y", tab_token, type, id, field, value, reserve);
        # release any reservation unconditionally before starting
        releaseReservationForTabTokenIntern(tab_token);
        if (reserve) {
            *string reserved_tab_token = reserved_names_version{type}{reserve.name}{reserve.version};
            if (!reserved_tab_token) {
                reserved_names_version{type}{reserve.name}{reserve.version} = tab_token;
                reservation_map{tab_token} = <ReservationInfo>{
                    "type": type,
                    "name": reserve.name,
                    "version": reserve.version,
                };
            } else {
                if (reserved_tab_token != tab_token) {
                    throw WEBIDE_ERROR_NAME_VERSION_RESERVED, sprintf("tab %y cannot reserve %s ID %d with name %y "
                        "and version %y; this name and version combination is already reserved for another "
                        "connection", tab_token, type,
                        id, reserve.name, reserve.version);
                }
                remove reserve;
            }
        }
        return reserve;
    }

    #! Checks class reservation requests
    /** @return as hash with \c name and \c version keys if a reservation can be made for the object
    */
    private *hash<auto> checkClassReservationLocked(int id, string field, auto value, *hash<auto> attrs) {
        hash<auto> reserve = {
            "name": field == "name" ? value : (attrs.name ?? omqmap.classmap{id}.name),
            "version": field == "version" ? value : (attrs.version ?? omqmap.classmap{id}.version),
        };
        # no reservation can be made when creating an object with only one attribute
        if (!reserve.name.val() || !reserve.version.val()) {
            return;
        }

        # check for existing match
        if (*int other_id = omqmap.classrmap{reserve.name}{reserve.version}) {
            # ignore if editing the same object with the same values
            if (other_id == id) {
                return;
            }
            throw WEBIDE_ERROR_NAME_VERSION_EXISTS, sprintf("class name and version %y v%y are in use by another "
                "class", reserve.name, reserve.version);
        }

        *hash<auto> obj = omqmap.classmap{id};
        *hash<auto> rmap = omqmap.classrmap{reserve.name} - ("lastversion", "lvcreated");
        # remove current version from comparison map if updating
        if (obj && rmap{obj.version}) {
            QDBG_LOG("QorusMapManager::checkClassReservation() obj: %y rmap: %y", obj, rmap);
            rmap -= obj.version;
        }

        # make sure we are not creating a class with a lower version than an existing class
        foreach string version in (keys rmap) {
            if (compare_version(reserve.version, version) < 0) {
                throw WEBIDE_ERROR_VERSION_TOO_LOW, sprintf("cannot set class %y's version to %y; the class's "
                    "cannot be lower than any existing version; found existing version %y", reserve.name,
                    reserve.version, version);
            }
        }

        return reserve;
    }

    #! Checks job reservation requests
    /** @return True if a reservation can be made for the interface
    */
    private *bool checkJobReservationLocked(int id, string name, *bool create) {
        *hash<auto> job = omqmap.jrmap{name};
        # take no action if we are updating and the name is not actually changing
        if (!create && id == job.jobid) {
            return;
        }
        if (job) {
            throw WEBIDE_ERROR_NAME_EXISTS, sprintf("job name %y already exists", name);
        }
        return True;
    }

    #! Checks connection reservation requests
    /** @return True if a reservation can be made for the connection
    */
    private *bool checkConnectionReservationLocked(int id, string name, *bool create) {
        *AbstractConnection c = getConnectionFromNameLocked(name);
        if (!create && c.internal_info.id == id) {
            return;
        }
        if (c) {
            throw WEBIDE_ERROR_NAME_EXISTS, sprintf("connection name %y already exists", name);
        }
        return True;
    }

    *AbstractConnection getConnectionFromIdLocked(int id, *reference<object> store) {
        *AbstractConnection c = Qorus.dsmanager.getConnectionFromIdLocked(id);
        if (c) {
            store = Qorus.dsmanager;
            return c;
        }
        c = Qorus.remotemonitor.getConnectionFromIdLocked(id);
        if (c) {
            store = Qorus.remotemonitor;
            return c;
        }
        c = Qorus.connections.getConnectionFromIdLocked(id);
        if (c) {
            store = Qorus.connections;
            return c;
        }
    }

    private *AbstractConnection getConnectionFromNameLocked(string name) {
        *AbstractConnection c = Qorus.dsmanager.getConnectionFromNameLocked(name);
        if (c) {
            return c;
        }
        c = Qorus.remotemonitor.getConnectionFromNameLocked(name);
        if (c) {
            return c;
        }
        return Qorus.connections.getConnectionFromNameLocked(name);
    }

    #! Rename system tags and move to the "sys" key
    private static *hash<auto> processTags(*hash<auto> tags) {
        map tags.sys{$1[1..]} = remove tags{$1}, keys tags, $1 =~ /^_/;
        return tags;
    }

    performDbUpdateOperations(hash<auto> db_ops) {
        QDBG_LOG("QorusMapManager::performDbUpdateOperations() %N", db_ops);
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                foreach hash<auto> i in (db_ops.pairIterator()) {
                    AbstractTable table = Qorus.dsmanager.getOmqTable(i.key);

                    foreach hash<auto> j in (i.value.pairIterator()) {
                        switch (j.key) {
                            case "replace":
                                table.del(j.value."where");
                                map table.insert(j.value."where" + $1), j.value."data";
                                olog(LoggerLevel::INFO, "executed %d replacement%s in table %y (%y)",
                                    j.value."data".size(), j.value."data".size() == 1 ? "" : "s", table.getSqlName(),
                                    j.value."where");
                                break;

                            case "update":
                                int rows = table.update(j.value."data", j.value."where");
                                olog(LoggerLevel::INFO, "updated %d column%s and %d row%s in table %y (set %y "
                                    "where %y)",
                                    j.value."data".size(), j.value."data".size() == 1 ? "" : "s", rows,
                                    rows == 1 ? "" : "s", table.getSqlName(), j.value."data", j.value."where");
                                break;

                            default:
                                throw "UNKNOWN-DB-OPERATION", sprintf("key: %y value: %y", j.key, j.value);
                        }
                    }
                }
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

    private *hash<auto> processUpdateTags(reference<*hash<auto>> ix_data, *string source_code, *hash<auto> tags) {
        # process system tags for comparison & update
        *hash<auto> db_tags = remove ix_data.tags;
        if (ix_data.base_class_name) {
            db_tags._base_class_name = ix_data.base_class_name;
        }
        if (db_tags) {
            foreach hash<auto> i in (db_tags.pairIterator()) {
                if (i.key =~ /^_/) {
                    ix_data.tags.sys{i.key[1..]} = i.value;
                } else {
                    ix_data.tags{i.key} = i.value;
                }
            }
        }
        # maintain system "offset" and "source" tags if not updating the source
        if (!source_code && tags) {
            foreach hash<auto> i in (tags.sys{"offset", "source"}.pairIterator()) {
                db_tags{"_" + i.key} = i.value;
                ix_data.tags.sys{i.key} = i.value;
            }
        }
        return db_tags;
    }

    hash<auto> updateJob(int id, *string source_code, *hash<auto> new_job_data, *string tab_token) {
        QDBG_LOG("QorusMapManager::updateJob() id: %y metadata: %y source: %y", id, new_job_data, source_code);

        # check metadata
        if (new_job_data) {
            verifyUpdateMetadata("job", \new_job_data, JobMetadata);

            # verify lib references
            verifyUpdateLib("job", id, \new_job_data);
        }

        # cache info: new job data (all new data)
        hash<auto> job_info;
        # cache info: all old job info
        *hash<auto> old_info;
        # cache info: old job data (only data that changed)
        *hash<auto> old_delta_job_info;
        on_success {
            bool update_cache = !new_job_data.empty();
            if (source_code) {
                new_job_data."code" = source_code;
            }

            Qorus.events.postJobUpdated(tld.cx, job_info.name, job_info.version, id, new_job_data);
            Qorus.audit.jobUpdated(tld.cx, id, sprintf("%y", new_job_data));

            string name;
            list<hash<FieldGroupInfo>> fields = CreatorJobDefinitionRestClass::staticGetFieldsForJob(id, \name);
            if (!source_code.val()) {
                source_code = CreatorJobDefinitionRestClass::staticGetCodeForJob(id);
            }
            Qorus.creatorWsHandler.broadcastInterfaceUpdated("job", id, name, fields, source_code, old_delta_job_info,
                job_info);
        }

        {
            AtomicJobActionHelper atomic_action_helper(id);

            hash<auto> job_row;
            # DB operations: table -> operation -> info
            hash<string, hash<auto>> db_ops;

            string name;
            {
                WriteLockHelper wlh(map_mutex);
                if (!(old_info = omqmap.jmap{id})) {
                    throw "JOB-UPDATE-ERROR", sprintf("job ID %d does not exist", id);
                }

                *hash<auto> db_tags = processUpdateTags(\new_job_data, source_code, omqmap.jmap{id}.tags);

                # remove updates where the value remains the same
                map remove new_job_data{$1.key}, new_job_data.pairIterator(),
                    omqmap.jmap{id}{$1.key} == $1.value;

                name = omqmap.jmap{id}.name;
                if (new_job_data.name) {
                    if (*hash<auto> job = omqmap.jrmap{new_job_data.name}) {
                        throw "JOB-UPDATE-ERROR", sprintf("cannot update the name of job ID %d from %y to %y; "
                            "job %y already exists", id, name, new_job_data.name, new_job_data.name);
                    }

                    *string reserved_tab_token = reserved_names.job{new_job_data.name};
                    if (reserved_tab_token) {
                        if (reserved_tab_token == tab_token) {
                            # release reservation automatically
                            releaseReservationIntern(tab_token, "job", new_job_data{"name",}, False);
                        } else {
                            throw "JOB-UPDATE-ERROR", sprintf("job ID %d cannot be renamed from %y to %y; %y is "
                                "already reserved", id, name, new_job_data.name, new_job_data.name);
                        }
                    }

                    old_delta_job_info.name = name;
                    name = new_job_data.name;
                    omqmap.jrmap{name} = remove omqmap.jrmap{old_delta_job_info.name};
                }

                on_error {
                    if (old_delta_job_info.name) {
                        omqmap.jrmap{old_delta_job_info.name} = remove omqmap.jrmap{name};
                    }
                }

                # direct updates
                *hash<auto> direct_updates = new_job_data{"name", "version", "description", "class_name", "language",
                    "expiry_date"};
                if (direct_updates) {
                    db_ops.jobs.update."data" += direct_updates;
                    old_delta_job_info += old_info{keys direct_updates};

                    if (direct_updates.expiry_date && !omqmap.jmap{id}.h.manually_updated) {
                        old_delta_job_info.manually_updated = False;
                        direct_updates.manually_updated = True;
                        db_ops.jobs.update."data".manually_updated = 1;
                    }
                }
                if (source_code) {
                    # NOTE: the old source code is not compared or returned in old_delta_job_info
                    db_ops.jobs.update."data"."code" = source_code;
                }

                if (new_job_data.tags) {
                    db_ops.job_tags.replace = {
                        "where": {
                            "jobid": id,
                        },
                        "data": (map (
                            "tag": $1.key,
                            "value": $1.value,
                        ), db_tags.pairIterator()),
                    };
                    old_delta_job_info.tags = old_info.tags;
                    direct_updates.tags = new_job_data.tags;
                }

                if (exists new_job_data.mappers) {
                    db_ops.job_mappers.replace = {
                        "where": {
                            "jobid": id,
                        },
                        "data": (map {
                            "mapperid": $1.mapperid,
                        }, new_job_data.mappers),
                    };
                    old_delta_job_info.mappers = old_info.mappers;
                    direct_updates.mappers = new_job_data.mappers;
                }

                # boolean updates
                *hash<auto> boolean_updates = new_job_data{"active", "enabled", "remote", "run_skipped"};
                if (!omqmap.jmap{id}.class_based) {
                    old_delta_job_info.class_based = False;
                    new_job_data.class_based = boolean_updates.class_based = True;
                }
                if (boolean_updates) {
                    db_ops.jobs.update."data" += map {$1.key: ($1.value ? 1 : 0)}, boolean_updates.pairIterator();
                    old_delta_job_info += old_info{keys boolean_updates};
                    direct_updates += boolean_updates;

                    if (boolean_updates.remote && !omqmap.jmap{id}.h.manual_remote) {
                        direct_updates.manual_remote = True;
                        db_ops.jobs.update."data".manual_remote = 1;
                    }

                    if (boolean_updates.active && !omqmap.jmap{id}.h.manual_active) {
                        direct_updates.manual_active = True;
                        db_ops.jobs.update."data".manual_active = 1;
                    }
                }

                if (new_job_data.schedule) {
                    # do not update if the schedule is the same
                    if (omqmap.jmap{id}{keys new_job_data.schedule} == new_job_data.schedule) {
                        remove new_job_data.schedule;
                    } else {
                        db_ops.jobs.update."data" += new_job_data.schedule;
                        old_delta_job_info.schedule = old_info.schedule;
                        direct_updates += new_job_data.schedule;
                        direct_updates.schedule = sprintf("%s %s %s %s %s", new_job_data.schedule.minute,
                            new_job_data.schedule.hour, new_job_data.schedule.day, new_job_data.schedule.month,
                            new_job_data.schedule.wday);

                        if (!omqmap.jmap{id}.h.manually_updated) {
                            direct_updates.manually_updated = True;
                            db_ops.jobs.update."data".manually_updated = 1;
                        }
                    }
                }

                if (db_ops.jobs.update."data") {
                    db_ops.jobs.update."where".jobid = id;
                }
                if (db_ops) {
                    performDbUpdateOperations(db_ops);
                }

                # now update cache
                if (direct_updates) {
                    QDBG_LOG("updating job %s (%d) internal metadata: %y", name, id, direct_updates);
                    omqmap.jmap{id} += direct_updates;
                    omqmap.jrmap{name} += direct_updates;
                }

                job_info = omqmap.jmap{id};
            }

            # reset job if necessary
            if ((*hash<auto> job_updates = (new_job_data - ("run_skipped", "description")))
                || source_code) {
                if (job_updates.size() == 1 && job_updates.hasKey("expiry_date")) {
                    # if only the expiration date has changed
                    Qorus.jobManager.jobExpiryUpdated(job_info.name, new_job_data.expiry_date, job_info);
                } else {
                    # otherwise reload the job with the new info
                    if (exists new_job_data.groups) {
                        Qorus.rbac.resetJobGroups(id, new_job_data.groups);
                    }
                    Qorus.rbac.rescanJobsDelta((id,));
                    Qorus.alerts.rescanMetadata(False, False, True);

                    Qorus.jobManager.deleteJob(old_delta_job_info.name ?? name, True, "job updated with API");
                }

                if (job_info.expiry_date && job_info.expiry_date <= now_us()) {
                    qlog(LoggerLevel::INFO, "job %s has expired, not started after update", job_info.name);
                } else {
                    Qorus.jobManager.startJobBackground(name, "job updated with API");
                }
            }
        }

        return new_job_data;
    }

    int createJob(*softint id, string source_code, hash<auto> new_job_data, *string tab_token) {
        QDBG_LOG("QorusMapManager::createJob() id: %y metadata: %y source: %y", id, new_job_data, source_code);

        # check metadata
        verifyCreateMetadata("job", \new_job_data, JobMetadata);

        # generate job ID if not already provided
        if (!id) {
            id = sqlif.getNextSequenceValue("seq_jobs");
        }

        # verify lib references
        verifyCreateLib("job", id, \new_job_data);

        hash<auto> job_info;
        on_success {
            job_info."code" = source_code;
            Qorus.events.postJobCreated(tld.cx, new_job_data.name, new_job_data.version, id, job_info);
            Qorus.audit.jobCreated(tld.cx, id, sprintf("%y", job_info));
            # NOTE: the job metadata cache is now centralized
            Qorus.creatorWsHandler.broadcastInterfaceCreated("job", id, new_job_data.name,
                new_job_data{"name", "version", "jobid"});
        }

        {
            AtomicJobActionHelper atomic_action_helper(id);

            hash<auto> job_row;
            *hash<auto> db_tags = new_job_data.tags;

            job_row = job_info = {"jobid": id} + new_job_data{"name", "version", "description", "class_name",
                "language"} + new_job_data.schedule + {"code": source_code};

            job_info += new_job_data{"active", "enabled", "remote", "run_skipped", "expiry_date", "mappers", "vmaps"};
            job_row.active = new_job_data.active ? 1 : 0;
            job_row.manual_active = 0;
            job_info.manual_active = False;

            job_row.enabled = new_job_data.enabled ? 1 : 0;
            job_row.remote = new_job_data.remote ? 1 : 0;
            job_row.run_skipped = new_job_data.run_skipped ? 1 : 0;

            job_row.manual_remote = 0;
            job_info.manual_remote = False;

            job_row.manually_updated = 0;
            job_info.manually_updated = False;

            job_row.open = 0;
            job_info.open = False;

            job_row.class_based = 1;
            job_info.class_based = True;

            hash<auto> tsinfo = {"created": now_us(), "modified": now_us()};
            job_row += tsinfo;
            job_info += tsinfo;

            if (new_job_data."stack-size") {
                job_info."runtime-options"."stack-size" = new_job_data."stack-size";
            }

            if (new_job_data.base_class_name) {
                db_tags._base_class_name = new_job_data.base_class_name;
            }
            job_info.tags = processTags(db_tags);

            # get next run timestamp before it will run to get next from job instance manager
            if (new_job_data.active && (!new_job_data.expiry_date || new_job_data.expiry_date > now_us())) {
                CronTimer timer(new_job_data.schedule.minute, new_job_data.schedule.hour, new_job_data.schedule.day,
                    new_job_data.schedule.month, new_job_data.schedule.wday);
                job_info."next" = timer.findNext(LocalQorusJob::getStart());
            }

            {
                WriteLockHelper wlh(map_mutex);
                if (omqmap.jmap{id}) {
                    throw "JOB-CREATION-ERROR", sprintf("job ID %d already exists", id);
                }
                *string reserved_tab_token = reserved_names.job{new_job_data.name};
                if (reserved_tab_token) {
                    if (reserved_tab_token == tab_token) {
                        # release reservation automatically
                        releaseReservationIntern(tab_token, "job", new_job_data{"name",}, False);
                    } else {
                        throw "JOB-CREATION-ERROR", sprintf("job ID %d cannot be created with name %y, as this name is "
                            "already reserved", id, new_job_data.name);
                    }
                }
                if (*hash<auto> job = omqmap.jrmap{new_job_data.name}) {
                    throw "JOB-CREATION-ERROR", sprintf("job name %y already exists", new_job_data.name);
                }

                # insert in cache
                omqmap.jmap{id} = omqmap.jrmap{new_job_data.name} = job_info;
            }

            # remove from metadata map if an error occurs after this point
            on_error {
                WriteLockHelper wlh(map_mutex);
                remove omqmap.jmap{id};
                remove omqmap.jrmap{new_job_data.name};
            }

            # now save new job in the DB
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    AbstractTable jobs = Qorus.dsmanager.getOmqTable("jobs");
                    #AbstractTable job_config_items_table = Qorus.dsmanager.getOmqTable("job_config_items");

                    QDBG_LOG("inserting job row: %y", job_row);
                    jobs.insert(job_row);

                    if (db_tags) {
                        writeTagsNoCommit("job", id, db_tags);
                    }

                    sqlif.insertInterfaceOptionRawNoCommit("job", id, "stack-size",
                        QorusSystemOptionHash."stack-size".desc, True, new_job_data."stack-size");

                    # add mappers
                    if (new_job_data.mappers) {
                        AbstractTable job_mappers = Qorus.dsmanager.getOmqTable("job_mappers");
                        map job_mappers.insert({
                            "jobid": id,
                            "mapperid": $1.mapperid,
                        }), new_job_data.mappers;
                    }

                    # add vmaps
                    if (new_job_data.vmaps) {
                        AbstractTable job_vmaps = Qorus.dsmanager.getOmqTable("job_vmaps");
                        map job_vmaps.insert({
                            "jobid": id,
                            "id": $1.id,
                        }), new_job_data.vmaps;
                    }

                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex)) {
                        continue;
                    }
                    rethrow;
                }
                trans.reset();
                olog(LoggerLevel::INFO, "created job %s v%s (%d)", new_job_data.name, new_job_data.version, id);
                break;
            }

            # delete from DB if an error occurs after this point
            on_error {
                deleteJobFromDb(id);
                olog(LoggerLevel::INFO, "deleted job %s v%s (%d) from the DB due to an error", new_job_data.name,
                    new_job_data.version, id);
            }

            # add jobs to group in cache & DB
            try {
                map Qorus.rbac.addJob($1, new_job_data.name, job_info), new_job_data.groups;
            } catch (hash<ExceptionInfo> ex) {
                olog(LoggerLevel::INFO, "error adding job to group: %s", get_exception_string(ex));
                throw "JOB-CREATION-ERROR", sprintf("%s: %s", ex.err, ex.desc);
            }
        }

        Qorus.rbac.rescanJobsDelta((id,));
        Qorus.alerts.rescanMetadata(False, False, True);

        QDBG_LOG("cached job info: %y", job_info);

        return id;
    }

    hash<auto> reloadJobs(*softlist ids, *bool init, *reference<hash> already_reset) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(job_reload_lock);

        # NOTE: the job metadata cache is now centralized

        hash jmap = {};
        hash jrmap = {};
        # map of slaids -> jobid -> True
        hash<string, hash<string, bool>> sla_jmap();
        # map of jobid -> SLA ID
        hash<string, int> sla_rjmap();
        # map of loggerid -> jobid
        *hash<string, int> logger_jobmap;

        hash<auto> config_items;
        hash<auto> query_hash;
        hash<auto> options;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable jobs = Qorus.dsmanager.getOmqTable("jobs");
                AbstractTable job_config_items_table = Qorus.dsmanager.getOmqTable("job_config_items");
                AbstractTable job_options = Qorus.dsmanager.getOmqTable("job_options");

                # get all columns in "jobs" except code
                list jcl = keys (jobs.describe().getHash());
                jcl += (cop_as("st.value", "source"), cop_as("lt.value", "line"));
                jcl += "loggerid";

                hash select_hash = {
                    "columns": jcl,
                    "join": join_left(Qorus.dsmanager.getOmqTable("job_tags"), "st", NOTHING, ("tag": "_source"))
                    + join_left(Qorus.dsmanager.getOmqTable("job_tags"), "lt", NOTHING, ("tag": "_offset")),
                };

                if (ids) {
                    select_hash."where"."jobid" = op_in((map $1.toInt(), ids));
                }

                query_hash = jobs.select(select_hash);
                config_items = job_config_items_table.select(select_hash{"where",});
                context (job_options.select(select_hash{"where",})) {
                    # issue #919
                    if ((%value === NULL || %value === "") && !%config) {
                        sqlif.deleteInterfaceOptionNoCommit("job", %jobid, %name);
                    }
                    options{%jobid} = %%;
                }

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

        *hash jmh = query_hash.jobid ? getMappers("job", ids) : NOTHING;
        *hash jvmh = query_hash.jobid ? getValueMaps("job", ids) : NOTHING;

        # get library information for jobs
        hash lq = getLibrary("job_lib", "jobid", ids);

        # get tag info for jobs
        hash t = getTags("job", "jobid", ids);

        context (query_hash) {
            hash h = %%;
            # convert NULLs to NOTHING
            map delete h.$1, keys h, h.$1 === NULL;

            h.config_items = remove h.yaml_config_items;
            if (h.config_items) {
                h.config_items = deserialize_qorus_data(h.config_items);
            }

            *string yaml_fsm_triggers = remove h.yaml_fsm_triggers;

            # get job options
            foreach hash<auto> row in (options{%jobid}.contextIterator()) {
                if (row.config) {
                    h.options{row.name} = row.description;
                }
                try {
                    h."runtime-options".(row.name) = deserialize_qorus_data(row.value);
                    # issue #919
                    if ((!exists h."runtime-options".(row.name) || h."runtime-options".(row.name) === "")) {
                        delete h."runtime-options".(row.name);
                    }
                } catch (hash<ExceptionInfo> ex) {
                    string err = sprintf("cannot parse job %s v%s (%d) option %s: %s: %s (value: %y)", %name,
                        %version, %jobid, row.name, ex.err, ex.desc, row.value);
                    UserApi::raiseTransientAlert("INVALID-JOB-DATA", err, h{"name", "version", "jobid"});
                    qlog(LoggerLevel::ERROR, "INVALID-JOB-DATA: %s", err);
                }
            }

            h += {
                "active": boolean(%active),
                "manual_active": boolean(%manual_active),
                "remote": boolean(%remote),
                "manual_remote": boolean(%manual_remote),
                "enabled": boolean(%enabled),
                "manually_updated": boolean(%manually_updated),
                "run_skipped": boolean(%run_skipped),
                "open": boolean(%open),
                "class_based": boolean(%class_based),
                "fsm_triggers": yaml_fsm_triggers ? parse_yaml(yaml_fsm_triggers) : NOTHING,
            };

            # get next run timestamp before it will run to get next from job instance manager
            if (%active && %enabled && (!%expiry_date || %expiry_date > now_us()
                && Qorus.rbac.testStartJob(%jobid))) {
                CronTimer timer = %recurring
                                   ? new CronTimer(seconds(%recurring))
                                   : new CronTimer(%minute, %hour, %day, %month, %wday);
                h."next" = timer.findNext(LocalQorusJob::getStart());
            }
            if (!%recurring) {
                h.schedule = sprintf("%s %s %s %s %s", %minute, %hour, %day, %month, %wday);
            }

            if (%line) {
                h += ("line": int(%line));
            }

            h.mappers = jmh.%jobid;
            h.vmaps = jvmh.%jobid;
            h.lib = lq.%jobid;
            h.tags = t.%jobid;
            if (h.language_info) {
                h.language_info = parse_yaml(h.language_info);
            }

            jmap.%jobid = h;
            jrmap.%name = h;

            # add slaid to job mapping
            if (%slaid) {
                sla_jmap{%slaid}{%jobid} = True;
                sla_rjmap{%jobid} = %slaid;
            }

            # add to logger_jobmap
            if (%loggerid) {
                logger_jobmap{%loggerid} = %jobid;
            }
        }

        context (config_items) {
            # ignore config for steps not present in the query
            if (!jmap{%jobid}) {
                continue;
            }
            hash<auto> item = {
                "type": %type,
                "desc": %description,
                "strictly_local": %strictly_local.toBool(),
                "config_group": %config_group,
                "sensitive": %sensitive.toBool(),
                "prefix": %prefix,
            };

            item += %default_value.val() ? {"default_value": deserialize_qorus_data(%default_value)} : {};
            item += %allowed_values.val() ? {"allowed_values": deserialize_qorus_data(%allowed_values)} : {};

            string job_name = jmap{%jobid}.name;
            jmap{%jobid}.config{%name} = jrmap{job_name}.config{%name} = item;
        }
        # get job ID list
        softlist jobids = map int($1), keys jmap;

        # make atomic update to omqmap and get any remote changes for later execution
        list<hash<auto>> remote_change_list;
        # logger change map: jobid -> bool
        hash<string, bool> job_logger_change_map;
        {
            WriteLockHelper wlh(map_mutex);

            # check for job logger changes
            # NOTE: cannot detect logger changes made in the DB during a qorus-core recovery
            if (omqmap.jmap) {
                job_logger_change_map = map {$1.key: True}, omqmap.jmap.pairIterator(),
                    (!ids || jmap{$1.key}) && ($1.value.loggerid != jmap{$1.key}.loggerid);
            }

            # check for job remote changes
            {
                hash<auto> jrh = omqmap.jmap
                    ? map {$1.key: $1.value.remote}, omqmap.jmap.pairIterator(), exists jmap{$1.key}
                    : Qorus.getRunningJobHash();

                foreach hash<auto> jh in (jmap.pairIterator()) {
                    if (exists jrh{jh.key} && jh.value.remote != jrh{jh.key}) {
                        olog(LoggerLevel::INFO, "job %s v%s (%d) remote value changed from %y -> %y; queuing remote change",
                            jh.value.name, jh.value.version, jh.key, jrh{jh.key}, jh.value.remote, jrh{jh.key});
                        remote_change_list += {
                            "jobid": jh.key,
                            "name": jh.value.name,
                            "version": jh.value.version,
                            "remote": jh.value.remote,
                        };
                        jmap{jh.key}.remote = jrh{jh.key};

                        # if there is a remote change, then remove the logger change as it will be updated anyway
                        remove job_logger_change_map{jh.key};
                    }
                }
            }

            if (ids) {
                # get hash of names
                hash<string, bool> nh = map {$1.name: True}, jmap{ids}.iterator();
                # add any names of deleted jobs
                map nh{$1.name} = True, omqmap.jmap{ids}.iterator();

                # temporarily copy the reverse map
                *hash<auto> cr = omqmap.jrmap;

                # remove old reverse mappings
                map remove omqmap.jrmap{$1.name}, omqmap.jmap{ids}.iterator();
                map remove omqmap.jrmap{$1.name}, jmap{ids}.iterator();

                # add possibly removed IDs with the same name keys to the id list
                ids += map cr{$1.name}.jobid, jmap{ids}.iterator(), cr{$1.name}.jobid
                    && $1.jobid != cr{$1.name}.jobid;

                # remove old forward mappings
                remove omqmap.jmap{ids};
                # remove old SLA mappings
                map remove self.sla_jmap{sla_rjmap{$1}}{$1}, ids;
                remove self.sla_rjmap{ids};

                # remove possibly duplicated entries
                map remove omqmap.jmap{$1.jobid}, jrmap.iterator();

                # remove old IDs
                hash<string, bool> dh = map {$1: True}, ids;
                # remove jobsids about to be readded
                omqmap.jobids = select omqmap.jobids, !dh.$1;
                # remove logger -> job entries about to be readded
                map remove omqmap.logger_jobmap{$1.key}, omqmap.logger_jobmap.pairIterator(), dh{$1.value};

                # only add if there's something to add
                if (jobids) {
                    # add forward mappings
                    omqmap.jmap += jmap;

                    # add reverse mappings
                    omqmap.jrmap += jrmap;

                    # add IDs
                    omqmap.jobids += jobids;
                    if (sla_jmap) {
                        map self.sla_jmap{$1.key} += $1.value, sla_jmap.pairIterator();
                        self.sla_rjmap += sla_rjmap;
                    }

                    # add logger mappings
                    omqmap.logger_jobmap += logger_jobmap;
                }
            } else {
                omqmap += (
                    "jmap": jmap,
                    "jrmap": jrmap,
                    "jobids": jobids,
                    "logger_jobmap": logger_jobmap,
                );
            }

            # issue #2066 add slas to sla job maps
            if (sla_jmap) {
                self.sla_jmap = sla_jmap;
                self.sla_rjmap = sla_rjmap;
            }
        }

        if (!init) {
            if (ids) {
                Qorus.rbac.rescanJobsDelta(ids);
            } else {
                Qorus.rbac.rescanMetadata(False, False, True);
            }
        }
        Qorus.alerts.rescanMetadata(False, False, True);

        # execute remote changes outside the lock
        if (remote_change_list) {
            if (init) {
                Qorus.saveUpdateJobRemote(remote_change_list);
            } else {
                updateJobRemoteList(remote_change_list);
                already_reset = map {$1.jobid: True}, remote_change_list;
            }
        }

        # enforce logger changes
        map Qorus.jobManager.updateLoggerId($1.toInt(), lookupLogger("jobs", $1.toInt()).params),
            job_logger_change_map.pairIterator();

        return {"jobs": jmap.size()};
    }

    clearJobNextTriggerTime(softstring jobid, string name) {
        # FIXME: implement an event to update the UI
        WriteLockHelper wlh(map_mutex);

        if (omqmap.jmap{jobid}.next) {
            remove omqmap.jmap{jobid}.next;
            remove omqmap.jrmap{name}.next;
        }
    }

    updateJobRemoteList(list<auto> l) {
        foreach hash<auto> jh in (l) {
            olog(LoggerLevel::INFO, "updating job %s v%s (%d) remote %y -> %y", jh.name, jh.version, jh.jobid,
                !jh.remote, jh.remote);
            try {
                updateJobRemoteIntern(jh.jobid, jh.remote);
            } catch (hash<ExceptionInfo> ex) {
                # in case the job disappears; should not happen in normal operations
                olog(LoggerLevel::INFO, "%s: %s", ex.err, ex.desc);
            }
        }
    }

    # returns True if the remote status of the job was updated, False if not
    # only called for single job updates such as from the REST API
    bool updateJobRemote(softstring jobid, bool remote) {
        waitForInit();
        return updateJobRemoteIntern(jobid, remote);
    }

    # returns True if the remote status of the job was updated, False if not
    private bool updateJobRemoteIntern(softstring jobid, bool remote) {
        bool reenable;
        string name;
        string version;

        AtomicJobActionHelper atomic_action_helper(jobid);

        # issue #2425: do not start re-enabling jobs until the disable action has completed
        Counter done_counter();

        on_exit if (reenable) {
            # issue #3302: make sure the atomic lock structure can go out of scope before we wait for the action to
            # complete, or we can get a deadlock
            remove atomic_action_helper;

            # issue #2425: wait for disable action to complete before starting to re-enable
            done_counter.waitForZero();
            done_counter.inc();

            atomic_action_helper = new AtomicJobActionHelper(jobid);
            Qorus.rbac.enableSyntheticGroup("job", jobid, atomic_action_helper, done_counter);
            # wait for enable to complete before returning
            done_counter.waitForZero();
        }

        {
            ReadLockHelper rlh(map_mutex);
            reference jhr = \omqmap.jmap{jobid};

            if (!exists jhr) {
                throw "JOB-ERROR", sprintf("jobid %d does not exist", jobid);
            }

            name = jhr.name;
            version = jhr.version;

            # if the remote status is already equal to the target remote status, then return
            if (jhr.remote == remote) {
                olog(LoggerLevel::INFO, "no update necessary for job %s v%s (%d); remote is already %y", name,
                    version, jobid, remote);
                return False;
            }

            # disable the job
            done_counter.inc();
        }
        # release the lock so we can update the group; we have the atomic action lock on the job anyway
        # so the job cannot be changed with high-level actions
        reenable = Qorus.rbac.disableSyntheticGroup("job", jobid, atomic_action_helper, done_counter);
        # update DB
        sqlif.commitUpdateJobRemoteStatus(jobid, remote);
        bool updated;
        {
            WriteLockHelper wlh(map_mutex);
            reference jhr = \omqmap.jmap{jobid};
            # if the job has been deleted from the DB
            if (!jhr) {
                olog(LoggerLevel::INFO, "job %s v%s (%d) metadata disappeared; not continuing change", name, version,
                    jobid);
                reenable = False;
                return False;
            }
            if (jhr.remote != remote) {
                # mark workflow status changed in internal caches
                jhr.remote = remote;
                jhr.manual_remote = True;
                omqmap.jrmap{jhr.name}.remote = remote;
                omqmap.jrmap{jhr.name}.manual_remote = True;
                updated = True;
            }
        }

        if (updated) {
            olog(LoggerLevel::INFO, "successfully updated job %s v%s (%d) remote %y -> %y", name, version, jobid,
                !remote, remote);
            # issue #2725 issue JOB_UPDATED event
            Qorus.events.postJobUpdated(tld.cx, name, version, jobid, {"remote": remote});
        } else {
            olog(LoggerLevel::INFO, "job %s v%s (%d) metadata updated while disabling job", name, version, jobid);
        }

        return updated;
    }

    hash<auto> reloadConstants(*softlist ids) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(constant_reload_lock);

        hash constmap = {};
        hash constrmap = {};

        *hash qh;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable constants = Qorus.dsmanager.getOmqTable("constants");

                hash sh = {
                    "columns": (
                        "name",
                        "version",
                        "constantid",
                        "patch",
                        "description",
                        "author",
                        "created",
                        "modified",
                        cop_as("st.value", "source"),
                        cop_as("lt.value", "line"),
                    ),
                    "join": join_left(Qorus.dsmanager.getOmqTable("constant_tags"), "st", NOTHING, ("tag": "_source"))
                    + join_left(Qorus.dsmanager.getOmqTable("constant_tags"), "lt", NOTHING, ("tag": "_offset")),
                };
                if (ids)
                    sh."where"."constantid" = op_in((map $1.toInt(), ids));

                qh = constants.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        context (qh) {
            hash h = %%;
            h.line = int(h.line);
            # convert NULLs to NOTHING
            map delete h.$1, keys h, h.$1 === NULL;

            constmap.%constantid = h - "constantid";

            constrmap.%name.%version = %constantid.toInt();

            if (!ids && (!constrmap.%name.lastversion || (%created > constrmap.%name.lvcreated))) {
                constrmap.%name += {
                    "lvcreated"   : %created,
                    "lastversion" : %version,
                };
            }
        }

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            if (ids) {
                doDeltaIntern(\ids, constmap, constrmap, "constmap", "constrmap");
            } else {
                omqmap += {
                    "constmap": constmap,
                    "constrmap": constrmap,
                };
            }
        }

        return {"constants": constmap.size()};
    }

    *hash<string, hash<EditMapInfo>> getEditMapForTypeLocked(string type) {
        QDBG_ASSERT(map_mutex.lockOwner());
        return edit_map{type};
    }

    *hash<EditMapInfo> getEditInfoLocked(string type, int id) {
        QDBG_ASSERT(map_mutex.lockOwner());
        return edit_map{type}{id};
    }

    int createConnection(*softint id, hash<auto> new_connection_data, *string tab_token) {
        QDBG_LOG("QorusMapManager::createConnection() id: %y metadata: %y", id, new_connection_data);

        # check metadata
        verifyCreateMetadata("connection", \new_connection_data, ConnectionMetadata);

        hash<auto> conn_info = new_connection_data - ("description", "options", "tags");
        if (new_connection_data.description) {
            conn_info.desc = new_connection_data.description;
        }
        if (new_connection_data.options) {
            conn_info.opts = new_connection_data.options;
        }
        if (new_connection_data.tags) {
            conn_info.attr.tags = new_connection_data.tags;
        }

        # WS and audit messages handled in the connection creation code

        # name reservations are checked in each of the following calls
        if (conn_info.url =~ /^db:\/\//) {
            id = Qorus.dsmanager.registerConnection(conn_info.name, conn_info.desc, conn_info.url, conn_info.attr,
                conn_info.options, id, tab_token).internal_info.id;
            conn_info.connection_type = "DATASOURCE";
        } else if (conn_info.url =~ /^qoruss?:\/\//) {
            id = Qorus.remotemonitor.registerConnection(conn_info.name, conn_info.desc, conn_info.url, conn_info.attr,
                conn_info.options, id, tab_token).internal_info.id;
            conn_info.connection_type = "REMOTE";
        } else {
            id = Qorus.connections.registerConnection(conn_info.name, conn_info.desc, conn_info.url, conn_info.attr,
                conn_info.options, id, tab_token).internal_info.id;
            conn_info.connection_type = "USER";
        }

        return id;
    }

    hash<auto> updateConnection(int id, *hash<auto> new_connection_data, *string tab_token) {
        QDBG_LOG("QorusMapManager::updateConnection() id: %y metadata: %y", id, new_connection_data);

        if (!new_connection_data) {
            return {};
        }

        # check metadata
        verifyUpdateMetadata("connection", \new_connection_data, ConnectionMetadata);

        hash<auto> conn_info = new_connection_data - ("description", "options", "tags");
        if (new_connection_data.description) {
            conn_info.desc = new_connection_data.description;
        }
        if (new_connection_data.options) {
            conn_info.opts = new_connection_data.options;
        }

        # cache info: all old class info
        *hash<auto> old_info;
        # cache info: new data (only data that changed)
        *hash<auto> new_delta_info;
        # cache info: old data (only data that changed)
        *hash<auto> old_delta_info;

        # Audit and WS message in the connection store APIs

        # get existing connection info
        {
            # this grabs the global map write lock an executes queued actions after the lock is released
            AtomicConnectionHelper ach();

            object store;
            *AbstractConnection c = getConnectionFromIdLocked(id, \store);
            if (!c) {
                throw "CONNECTION-UPDATE-ERROR", sprintf("connection ID %y does not exist", id);
            }
            if (c.locked) {
                throw "CONNECTION-UPDATE-ERROR", sprintf("connection ID %y is locked and cannot be updated", id);
            }

            string type = store.getConnectionDbType();

            # check for name conflicts
            if (conn_info.name) {
                if (conn_info.name != c.name
                    && (*AbstractConnection other = getConnectionFromNameLocked(conn_info.name))) {
                    throw "CONNECTION-UPDATE-ERROR", sprintf("cannot update the name of connection ID %d from %y to "
                        "%y; connection %y already exists", id, c.name, conn_info.name,
                        conn_info.name);
                }

                *string reserved_tab_token = reserved_names.connection{conn_info.name};
                if (reserved_tab_token) {
                    if (reserved_tab_token == tab_token) {
                        # release reservation automatically
                        releaseReservationIntern(tab_token, "connection", conn_info{"name",}, False);
                    } else {
                        throw "CONNECTION-UPDATE-ERROR", sprintf("connection ID %d cannot be renamed from %y to %y; "
                            "%y is already reserved", id, c.name, conn_info.name, conn_info.name);
                    }
                }
            }

            # setup new object attributes
            foreach string key in (ConnectionKeys) {
                if (conn_info.hasKey(key)) {
                    if (conn_info{key} != c{key}) {
                        new_delta_info{key} = conn_info{key};
                        old_delta_info{key} = c{key};
                    }
                } else {
                    # fill in attributes that are not changing
                    conn_info{key} = c{key};
                }
            }

            if (!new_delta_info) {
                QDBG_LOG("QorusMapManager::updateConnection() id: %y: no changes requested: %y", id, conn_info);
                return {};
            }

            # see if connection type is changing
            if (new_delta_info.url
                && (object new_store = getConnectionObjectForUrl(new_delta_info.url)) != store) {
                new_delta_info.connection_type = new_store.getConnectionDbType();
                old_delta_info.connection_type = type;
                # get new connection object
                hash<auto> attr;
                if (conn_info.tags) {
                    attr.tags = conn_info.tags;
                }
                AbstractConnection new_connection = new_store.newConnection(conn_info.name, conn_info.desc,
                    conn_info.url, attr, conn_info.opts);
                new_connection.internal_info.id = id;

                QDBG_LOG("changing connection type %y -> %y", old_delta_info, new_delta_info);
                store.removeConnection(id, ach);
                new_store.addUpdateConnection(new_connection, old_delta_info, new_delta_info, ach);
            } else {
                QDBG_LOG("replacing connection %y -> %y", old_delta_info, new_delta_info);
                store.replaceLocked(c, conn_info, old_delta_info, new_delta_info, ach);
            }
        }

        return new_delta_info;
    }

    object getConnectionObjectForUrl(string url) {
        if (url =~ /^db:/) {
            return Qorus.dsmanager;
        }
        if (url =~ /^qoruss?:/) {
            return Qorus.remotemonitor;
        }
        return Qorus.connections;
    }

    deleteConnection(int id) {
        object store;
        string name;
        {
            # this grabs the global map write lock an executes queued actions after the lock is released
            AtomicConnectionHelper ach();

            *AbstractConnection c = getConnectionFromIdLocked(id, \store);
            if (!c) {
                throw "CONNECTION-DELETION-ERROR", sprintf("connection ID %d does not exist", id);
            }
            name = c.name;
        }
        store.del(name);
    }

    hash<auto> updateClass(int id, *string source_code, *hash<auto> new_class_data, *string tab_token) {
        QDBG_LOG("QorusMapManager::updateClass() id: %y metadata: %y source: %y", id, new_class_data, source_code);

        # check metadata
        if (new_class_data) {
            verifyUpdateMetadata("class", \new_class_data, ClassMetadata);

            # verify lib references
            verifyUpdateLib("class", id, \new_class_data);
        }

        hash<auto> class_info;
        # cache info: all old class info
        *hash<auto> old_info;
        # cache info: old class data (only data that changed)
        *hash<auto> old_delta_class_info;
        on_success {
            bool update_cache = !new_class_data.empty();
            if (source_code) {
                new_class_data."code" = source_code;
            }

            Qorus.events.postClassUpdated(tld.cx, class_info.name, class_info.version, id, new_class_data);
            Qorus.audit.classUpdated(tld.cx, id, sprintf("%y", new_class_data));

            # NOTE: the class metadata cache is now centralized and not part of the distributed lib map cache

            string name;
            list<hash<FieldGroupInfo>> fields = CreatorClassDefinitionRestClass::staticGetFieldsForClass(id, \name);
            if (!source_code.val()) {
                source_code = CreatorClassDefinitionRestClass::staticGetCodeForClass(id);
            }
            Qorus.creatorWsHandler.broadcastInterfaceUpdated("class", id, name, fields, source_code,
                old_delta_class_info, class_info);
        }

        {
            hash<auto> class_row;
            # DB operations: table -> operation -> info
            hash<string, hash<auto>> db_ops;

            string name;
            string version;
            {
                WriteLockHelper wlh(map_mutex);
                if (!(old_info = omqmap.classmap{id})) {
                    throw "CLASS-UPDATE-ERROR", sprintf("class ID %d does not exist", id);
                }

                *hash<auto> db_tags = processUpdateTags(\new_class_data, source_code, omqmap.classmap{id}.tags);

                # remove updates where the value remains the same
                map remove new_class_data{$1.key}, new_class_data.pairIterator(),
                    omqmap.classmap{id}{$1.key} == $1.value;

                name = omqmap.classmap{id}.name;
                version = omqmap.classmap{id}.version;
                if (new_class_data.name) {
                    if (*hash<auto> cls = omqmap.classrmap{new_class_data.name}) {
                        throw "CLASS-UPDATE-ERROR", sprintf("cannot update the name of class ID %d from %y to %y; "
                            "class %y already exists", id, name, new_class_data.name, new_class_data.name);
                    }

                    *string reserved_tab_token =
                        reserved_names_version."class"{new_class_data.name}{new_class_data.version};
                    if (reserved_tab_token) {
                        if (reserved_tab_token == tab_token) {
                            # release reservation automatically
                            releaseReservationIntern(tab_token, "class", new_class_data{"name", "version"}, False);
                        } else {
                            throw "CLASS-UPDATE-ERROR", sprintf("class ID %d cannot be renamed from %y to %y; %y is "
                                "already reserved", id, name, new_class_data.name, new_class_data.name);
                        }
                    }

                    old_delta_class_info.name = name;
                    name = new_class_data.name;
                    omqmap.classrmap{name} = remove omqmap.classrmap{old_delta_class_info.name};
                }
                *hash<auto> rmap_save;
                if (new_class_data.version) {
                    if (*int other_id = omqmap.classrmap{name}{new_class_data.version}) {
                        throw "CLASS-UPDATE-ERROR", sprintf("cannot update the version of class ID %d from %y to %y; "
                            "class %y already exists with class ID %d", id, version, new_class_data.version, name,
                            other_id);
                    }

                    old_delta_class_info.version = version;
                    version = new_class_data.version;
                    if (omqmap.classrmap{name}.lastversion == old_delta_class_info.version) {
                        rmap_save = omqmap.classrmap{name};
                        omqmap.classrmap{name}.lastversion = version;
                    }
                    omqmap.classrmap{name}{version} = remove omqmap.classrmap{old_delta_class_info.name}{old_delta_class_info.version};
                }

                on_error {
                    if (old_delta_class_info.version) {
                        if (rmap_save) {
                            omqmap.classrmap{name} = rmap_save;
                        } else {
                            omqmap.classrmap{name}{old_delta_class_info.version} = remove omqmap.classrmap{name}{version};
                        }
                    }
                    if (old_delta_class_info.name) {
                        omqmap.classrmap{old_delta_class_info.name} = remove omqmap.classrmap{name};
                    }
                }

                # direct updates
                *hash<auto> direct_updates = new_class_data{"name", "version", "description", "class_name", "language"};
                if (direct_updates) {
                    old_delta_class_info += old_info{keys direct_updates};
                    db_ops.classes.update."data" += direct_updates;
                }
                if (source_code) {
                     # NOTE: the old source code is not compared or returned in old_delta_class_info
                    db_ops.classes.update."data".body = source_code;
                }

                if (new_class_data.tags) {
                    db_ops.class_tags.replace = {
                        "where": {
                            "classid": id,
                        },
                        "data": (map (
                            "tag": $1.key,
                            "value": $1.value,
                        ), db_tags.pairIterator()),
                    };
                    old_delta_class_info.tags = old_info.tags;
                    direct_updates.tags = new_class_data.tags;
                }

                if (db_ops.classes.update."data") {
                    db_ops.classes.update."where".classid = id;
                }
                if (db_ops) {
                    performDbUpdateOperations(db_ops);
                }

                # now update cache
                if (direct_updates) {
                    QDBG_LOG("updating class %s (%d) internal metadata: %y", name, id, direct_updates);
                    omqmap.classmap{id} += direct_updates;
                }

                class_info = omqmap.classmap{id};
            }

            # reset affected interfaces if necessary
            # FIXME: implement
        }

        return new_class_data;
    }

    int createClass(*softint id, string source_code, hash<auto> new_class_data, *string tab_token) {
        QDBG_LOG("QorusMapManager::createClass() id: %y metadata: %y source: %y", id, new_class_data, source_code);

        # check metadata
        verifyCreateMetadata("class", \new_class_data, ClassMetadata);

        # generate class ID if not already provided
        if (!id) {
            id = sqlif.getNextSequenceValue("seq_classes");
        }

        # verify lib references
        verifyCreateLib("class", id, \new_class_data);

        hash<auto> class_info;
        on_success {
            class_info."code" = source_code;
            Qorus.events.postClassCreated(tld.cx, new_class_data.name, new_class_data.version, id, class_info);
            Qorus.audit.classCreated(tld.cx, id, sprintf("%y", class_info));
            # NOTE: the class metadata cache is now centralized and not part of the distributed lib map cache
            Qorus.creatorWsHandler.broadcastInterfaceCreated("class", id, new_class_data.name,
                new_class_data{"name", "version", "classid"});
        }

        {
            hash<auto> class_row;
            *hash<auto> db_tags = new_class_data.tags;

            class_row = class_info = {"classid": id} + new_class_data{"name", "version", "description", "class_name",
                "language"} + {"body": source_code};

            hash<auto> tsinfo = {"created": now_us(), "modified": now_us()};
            class_row += tsinfo;
            class_info += tsinfo;

            if (new_class_data.base_class_name) {
                db_tags._base_class_name = new_class_data.base_class_name;
            }
            class_info.tags = processTags(db_tags);

            *hash<auto> rmap_save;
            {
                WriteLockHelper wlh(map_mutex);
                if (omqmap.classmap{id}) {
                    throw "CLASS-CREATION-ERROR", sprintf("class ID %d already exists", id);
                }
                *string reserved_tab_token = reserved_names_version."class"{new_class_data.name}{new_class_data.version};
                if (reserved_tab_token) {
                    if (reserved_tab_token == tab_token) {
                        # release reservation automatically
                        releaseReservationIntern(tab_token, "class", new_class_data{"name", "version"}, False);
                    } else {
                        throw "CLASS-CREATION-ERROR", sprintf("class ID %d cannot be created with name %y and "
                            "version %y, as this name and version are already reserved", id, new_class_data.name,
                            new_class_data.version);
                    }
                }
                if (omqmap.classrmap{new_class_data.name}{new_class_data.version}) {
                    throw "CLASS-CREATION-ERROR", sprintf("class name %y v %y already exists", new_class_data.name,
                        new_class_data.version);
                }

                # insert in cache
                omqmap.classmap{id} = class_info;
                rmap_save = omqmap.classrmap{new_class_data.name};
                omqmap.classrmap{new_class_data.name}{new_class_data.version} = id;
                omqmap.classrmap{new_class_data.name} += {
                    "lastversion": new_class_data.version,
                    "lvcreated": now_us(),
                };
            }

            # remove from metadata map if an error occurs after this point
            on_error {
                WriteLockHelper wlh(map_mutex);
                remove omqmap.classmap{id};
                if (!rmap_save) {
                    remove omqmap.classrmap{new_class_data.name};
                } else {
                    omqmap.classrmap{new_class_data.name} = rmap_save;
                }
            }

            # now save new class in the DB
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    AbstractTable classes = Qorus.dsmanager.getOmqTable("classes");

                    QDBG_LOG("inserting class row: %y", class_row);
                    classes.insert(class_row);

                    if (db_tags) {
                        writeTagsNoCommit("class", id, db_tags);
                    }

                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex)) {
                        continue;
                    }
                    rethrow;
                }
                trans.reset();
                olog(LoggerLevel::INFO, "created class %s v%s (%d)", new_class_data.name, new_class_data.version, id);
                break;
            }

            # delete from DB if an error occurs after this point
            on_error {
                deleteClassFromDb(id);
                olog(LoggerLevel::INFO, "deleted class %s v%s (%d) from the DB due to an error", new_class_data.name,
                    new_class_data.version, id);
            }
        }

        QDBG_LOG("cached class info: %y", class_info);

        return id;
    }

    hash<auto> reloadClasses(*softlist<auto> ids) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(class_reload_lock);

        # NOTE: the class metadata cache is now centralized and not part of the distributed lib map cache

        hash classmap = {};
        hash classrmap = {};

        *hash<auto> qh;
        *hash<auto> class_deps_query;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable classes = Qorus.dsmanager.getOmqTable("classes");

                # do not use hash<auto> here
                hash sh = {
                    "columns": (
                        "name",
                        "version",
                        "classid",
                        "patch",
                        "description",
                        "author",
                        "language",
                        "language_info",
                        "body",
                        "created",
                        "modified",
                        "connectors",
                        "processor",
                        "yaml_config_items",
                        cop_as("st.value", "source"),
                        cop_as("lt.value", "line"),
                    ),
                    "join": join_left(Qorus.dsmanager.getOmqTable("class_tags"), "st", NOTHING, ("tag": "_source"))
                        + join_left(Qorus.dsmanager.getOmqTable("class_tags"), "lt", NOTHING, ("tag": "_offset")),
                };
                if (ids) {
                    sh."where"."classid" = op_in((map $1.toInt(), ids));
                }

                qh = classes.select(sh);

                # get class dependencies
                AbstractTable class_dependencies = Qorus.dsmanager.getOmqTable("class_dependencies");
                sh = {
                    "columns": ("classid", "dependson_class"),
                };
                if (ids) {
                    sh."where"."classid" = op_in((map $1.toInt(), ids));
                }

                class_deps_query = class_dependencies.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # issue #3621: get tag info for classes
        hash<auto> tags = getTags("class", "classid", ids);

        context (qh) {
            hash<auto> h = %%;
            h.line = int(h.line);
            h.config_items = remove h.yaml_config_items;
            if (h.config_items) {
                h.config_items = deserialize_qorus_data(h.config_items);
            }
            h.connectors = map {$1.name: $1}, deserialize_qorus_data(h.connectors);
            h.processor = deserialize_qorus_data(h.processor);
            if (h.language_info) {
                h.language_info = parse_yaml(h.language_info);
            }

            # convert NULLs to NOTHING
            map delete h.$1, keys h, h.$1 === NULL;

            h.tags = tags.%classid;

            classmap.%classid = h - "classid";

            classrmap.%name.%version = %classid.toInt();

            if (!ids && (!classrmap.%name.lastversion || (%created > classrmap.%name.lvcreated))) {
                classrmap.%name += {
                    "lvcreated"   : %created,
                    "lastversion" : %version,
                };
            }
        }

        # process dependencies
        context (class_deps_query) {
            # ignore dependencies for classes not in the original query
            # (in case the DB changed between the two queries)
            reference class_hash = \classmap{%classid};
            if (!class_hash) {
                continue;
            }
            # get classid of required class
            softint depid;
            # check in the data we are caching now
            if (classrmap{%dependson_class}) {
                # lastversion is not available when reloading
                *string classversion = classrmap{%dependson_class}.lastversion;
                if (!exists classversion) {
                    # take the last version that does not exist in the global classmap
                    foreach string ver in (keys classrmap{%dependson_class}) {
                        if (!omqmap.classrmap{%dependson_class}{ver}) {
                            classversion = ver;
                        }
                    }
                }
                # if still not matched, then we use the current last version for the class
                if (!exists classversion) {
                    classversion = omqmap.classrmap{%dependson_class}.lastversion;
                }
                depid = classrmap{%dependson_class}{classversion};
            } else if (ids && omqmap.classrmap{%dependson_class}) {
                # only check in the current cache if we are doing a partial reload
                depid = omqmap.classrmap{%dependson_class}{omqmap.classrmap{%dependson_class}.lastversion};
            } else {
                olog(LoggerLevel::INFO, "cached class %s v%s (%d) depends on unknown class %y; ignoring dependency",
                    class_hash.name, class_hash.version, class_hash.classid, %dependson_class);
                continue;
            }
            # add dependency to class entry
            class_hash.requires += (depid,);
        }

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            if (ids) {
                doDeltaIntern(\ids, classmap, classrmap, "classmap", "classrmap");
            } else {
                omqmap += {
                    "classmap": classmap,
                    "classrmap": classrmap,
                };
            }
        }

        return {"classes": classmap.size()};
    }

    hash<auto> reloadFunctions(*softlist ids) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(function_reload_lock);

        on_success
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateLibMapCache");

        hash functionmap = {};
        hash functionrmap = {};

        *hash qh;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable functions = Qorus.dsmanager.getOmqTable("function_instance");

                hash sh = (
                    "columns": (
                        "name",
                        "version",
                        "function_instanceid",
                        "function_type",
                        "patch",
                        "description",
                        "author",
                        "created",
                        "modified",
                        cop_as("st.value", "source"),
                        cop_as("lt.value", "line"),
                    ),
                    "join": join_left(Qorus.dsmanager.getOmqTable("function_instance_tags"), "st", NOTHING, ("tag": "_source"))
                    + join_left(Qorus.dsmanager.getOmqTable("function_instance_tags"), "lt", NOTHING, ("tag": "_offset")),
                );
                if (ids)
                    sh."where"."function_instanceid" = op_in((map $1.toInt(), ids));

                qh = functions.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        context (qh) {
            hash h = %%;
            h.line = int(h.line);
            # convert NULLs to NOTHING
            map delete h.$1, keys h, h.$1 === NULL;

            functionmap.%function_instanceid = h;

            functionrmap.%name.%version = %function_instanceid.toInt();

            if (!ids && (!functionrmap.%name.lastversion || (%created > functionrmap.%name.lvcreated))) {
                functionrmap.%name += {
                    "lvcreated"   : %created,
                    "lastversion" : %version,
                };
            }
        }

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            if (ids) {
                doDeltaIntern(\ids, functionmap, functionrmap, "functionmap", "functionrmap");
            } else {
                omqmap += {
                    "functionmap": functionmap,
                    "functionrmap": functionrmap,
                };
            }
        }

        return {"functions": functionmap.size()};
    }

    hash<auto> reloadSteps(*softlist ids) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(step_reload_lock);

        on_success
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateLibMapCache");

        hash stepmap = {};
        hash steprmap = {};

        *hash<auto> config_items;
        *hash<auto> query_hash;

        # issue #2880 async steps supporting user interaction; stepid -> queueid
        hash<string, softstring> user_interaction;

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable steps_table = Qorus.dsmanager.getOmqTable("steps");
                AbstractTable step_config_items_table = Qorus.dsmanager.getOmqTable("step_config_items");

                *hash select_hash;
                if (ids) {
                    select_hash."where"."stepid" = op_in((map $1.toInt(), ids));
                }
                query_hash = steps_table.select(select_hash);
                config_items = step_config_items_table.select(select_hash);

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

        context (query_hash) {
            hash<auto> h = %%;
            # issue #2880: process step user metadata, if anyway
            h.userdata = deserialize_qorus_data(h.userdata);

            # convert NULLs to NOTHING
            map delete h.$1, keys h, h.$1 === NULL;

            # rename "description" to "desc"
            if (h.description) {
                h.desc = remove h.description;
            }

            *string yaml_fsm_triggers = remove h.yaml_fsm_triggers;
            h.fsm_triggers = yaml_fsm_triggers ? parse_yaml(yaml_fsm_triggers) : NOTHING;

            # issue #2880: async steps may have user interaction support
            h.user_interaction = (h.steptype == OMQ::ExecAsync && h.user_interaction);
            if (h.user_interaction) {
                user_interaction{h.stepid} = h.queueid;
            }
            if (h.language_info) {
                h.language_info = parse_yaml(h.language_info);
            }

            stepmap.%stepid = h;
            delete stepmap.%stepid.stepid;

            steprmap.%name.%version = %stepid;
            # issue #1660: return the description of the primary step function if the step's description is missing
            # issue #2434: do not overwrite the step description if available
            if (!h.desc) {
                stepmap.%stepid.desc = h.stepfunction_instanceid
                    ? omqmap.functionmap{h.stepfunction_instanceid}.description
                    : omqmap.classmap{h.step_classid}.description;
            }

            # set "lvcreated" and "lastversion" tags in wfrmap only if loading all workflows
            if (!ids && (!steprmap.%name.lastversion || (%created > steprmap.%name.lvcreated))) {
                steprmap.%name += {
                    "lvcreated"   : %created,
                    "lastversion" : %version,
                };
            }
        }

        context (config_items) {
            # ignore config for steps not present in the step query
            if (!stepmap{%stepid}) {
                continue;
            }
            stepmap{%stepid}.config{%name} = {
                "type": %type,
                "desc": %description,
                "strictly_local": %strictly_local.toBool(),
                "config_group": %config_group,
                "sensitive": %sensitive.toBool(),
                "prefix": %prefix,
            };
            stepmap{%stepid}.config{%name} += %default_value.val() ?
                {"default_value": deserialize_qorus_data(%default_value)} : {};

            stepmap{%stepid}.config{%name} += %allowed_values.val() ?
                {"allowed_values": deserialize_qorus_data(%allowed_values)} : {};
        }

        # add library information to steps
        query_hash = getLibrary("step_lib", "stepid", ids);
        # fix for #1208: do not include service methods not selected above
        map stepmap.$1.lib = query_hash.$1, keys query_hash, stepmap.$1;

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            if (ids) {
                # get a copy of the current stepmap and qmap for post processing
                *hash<auto> oldstepmap = omqmap.stepmap;
                *hash<auto> oldqmap = omqmap.qmap;

                # process the delta
                doDeltaIntern(\ids, stepmap, steprmap, "stepmap", "steprmap");

                # add backreferences to queues for steps with user interaction and remove backreferences for deleted queues
                foreach softstring stepid in (ids) {
                    if ((*hash<auto> sh = omqmap.stepmap{stepid}) && exists sh.queueid) {
                        # ignore nonexistant queues
                        if (*hash<auto> queue_hash = omqmap.qmap{sh.queueid}) {
                            # issue #3054: add queuename to all async steps
                            omqmap.stepmap{stepid}.queuename = queue_hash.name;
                            if (sh.user_interaction) {
                                omqmap.qmap{sh.queueid}.user_interaction_steps{stepid} = True;
                                omqmap.qrmap{queue_hash.name}.user_interaction_steps{stepid} = True;
                            } else {
                                remove omqmap.qmap{sh.queueid}.user_interaction_steps{stepid};
                                remove omqmap.qrmap{queue_hash.name}.user_interaction_steps{stepid};
                            }
                        }
                    } else if ((*softstring oldqueueid = oldstepmap{stepid}.queueid)
                        && oldstepmap{stepid}.user_interaction && omqmap.qmap{oldqueueid}) {
                        # step no longer supports user interaction; remove queue -> step references
                        remove omqmap.qmap{oldqueueid}.user_interaction_steps{stepid};
                        remove omqmap.qrmap{oldqmap{oldqueueid}.name}.user_interaction_steps{stepid};
                    }
                }
            } else {
                # issue #3054: add queuename to all async steps
                foreach hash<auto> i in (stepmap.pairIterator()) {
                    if (*string queuename = omqmap.qmap{i.value.queueid}.name) {
                        stepmap{i.key}.queuename = queuename;
                    }
                }

                omqmap += {
                    "stepmap": stepmap,
                    "steprmap": steprmap,
                };

                # add backreferences to queues for steps with user interaction, if present
                foreach hash<auto> i in (user_interaction.pairIterator()) {
                    # ignore nonexistant queues
                    if (*hash<auto> queue_hash = omqmap.qmap{i.value}) {
                        omqmap.qmap{i.value}.user_interaction_steps{i.key} = True;
                        omqmap.qrmap{queue_hash.name}.user_interaction_steps{i.key} = True;
                    }
                }
            }
        }

        return {"steps": stepmap.size()};
    }

    hash<auto> reloadQueues(*softlist<softint> ids) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(queue_reload_lock);

        on_success
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateLibMapCache");

        hash qmap = {};
        hash qrmap = {};

        *hash qh;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable queues = Qorus.dsmanager.getOmqTable("queues");

                hash sh = (
                    "columns": (
                        "queueid",
                        "name",
                        "serviceid",
                    ),
                );
                if (ids)
                    sh."where"."queueid" = op_in((map $1.toInt(), ids));

                qh = queues.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        context (qh) {
            qmap.%queueid = %%;
            qrmap.%name = %%;
        }

        # save size for return value
        int qmap_size = qmap.size();

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            # maintain references to steps with user interaction
            map (
                qmap{$1.key}.user_interaction_steps = $1.value.user_interaction_steps,
                qrmap{$1.value.name}.user_interaction_steps = $1.value.user_interaction_steps
            ), omqmap.qmap.pairIterator(), qmap{$1.key};

            if (ids) {
                # get hash of names
                hash nh = map {$1.name: True}, qmap{ids}.iterator();
                # add any names of deleted queues
                map nh{$1.name} = True, omqmap.qmap{ids}.iterator();

                # temporarily copy the reverse map
                *hash cr = omqmap.qrmap;

                # remove old reverse mappings
                map remove omqmap.qrmap{$1.name}, omqmap.qmap{ids}.iterator();
                map remove omqmap.qrmap{$1.name}, qmap{ids}.iterator();

                # add possibly removed IDs with the same name keys to the id list
                ids += map cr{$1.name}.queueid, qmap{ids}.iterator(), cr{$1.name}.queueid && $1.queueid != cr{$1.name}.queueid;

                # remove old forward mappings
                remove omqmap.qmap{ids};

                # remove possibly duplicated entries
                map remove omqmap.qmap{$1.queueid}, qrmap.iterator();

                # only add if there's something to add
                if (qmap) {
                    # add forward mappings
                    omqmap.qmap += qmap;

                    # add reverse mappings
                    omqmap.qrmap += qrmap;
                }
            } else {
                omqmap += {
                    "qmap": qmap,
                    "qrmap": qrmap,
                };
            }
        }

        QDBG_LOG("reloadQueues: qmap: %y", qmap);
        QDBG_LOG("reloadQueues: qrmap: %y", qrmap);

        return {"queues": qmap_size};
    }

    hash<auto> reloadPipelines(*softlist<string> names) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(pipeline_reload_lock);

        on_success Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateLibMapCache");

        hash pipelines = {};

        hash<auto> config_items;
        *hash query;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                AbstractTable pipelines_table = Qorus.dsmanager.getOmqTable("pipelines");
                AbstractTable pipeline_config_items_table = Qorus.dsmanager.getOmqTable("pipeline_config_items");

                hash select_hash = {
                    "columns": (
                        "name",
                        "description",
                        "children",
                        "options",
                    ),
                };
                hash<auto> config_item_select_hash;
                if (names) {
                    config_item_select_hash."where".pipeline = select_hash."where".name = op_in(names);
                }

                query = pipelines_table.select(select_hash);
                config_items = pipeline_config_items_table.select(config_item_select_hash);
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

        hash<string, hash<string, list<hash<auto>>>> libs = getLibrary("pipeline_lib", "pipeline", names);
        QDBG_LOG("reloadPipelines: libs: %y", libs);
        context (query) {
            pipelines.%name = {
                "name": %name,
                "description": %description,
                "children": deserialize_qorus_data(%children),
                "lib": libs.%name,
                "options": deserialize_qorus_data(%options),
            };
        }

        context (config_items) {
            # ignore config for pipelines not present in the query
            if (!pipelines{%pipeline}) {
                continue;
            }
            pipelines{%pipeline}.config{%name} = {
                "type": %type,
                "desc": %description,
                "strictly_local": %strictly_local.toBool(),
                "config_group": %config_group,
                "sensitive": %sensitive.toBool(),
                "prefix": %prefix,
            };

            pipelines{%pipeline}.config{%name} += %default_value.val() ?
                {"default_value": deserialize_qorus_data(%default_value)} : {};

            pipelines{%pipeline}.config{%name} += %allowed_values.val() ?
                {"allowed_values": deserialize_qorus_data(%allowed_values)} : {};
        }

        # save size for return value
        int size = pipelines.size();

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            if (names) {
                # add new pipelines
                omqmap.pipelines += pipelines;

                # remove pipelines that have been deleted, if any
                omqmap.pipelines -= (keys ((map {$1: True}, names) - (keys pipelines)));
            } else {
                omqmap += {
                    "pipelines": pipelines,
                };
            }
        }

        QDBG_LOG("reloadPipelines: pipelines: %y", pipelines);
        return {"pipelines": size};
    }

    hash<auto> reloadFsms(*softlist<string> names) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(fsm_reload_lock);

        on_success Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateLibMapCache");

        hash<auto> fsm = {};

        hash<auto> config_items;
        *hash<auto> query;
        *hash<auto> lib_result;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                AbstractTable fsm_table = Qorus.dsmanager.getOmqTable("fsm");
                AbstractTable fsm_config_items_table = Qorus.dsmanager.getOmqTable("fsm_config_items");

                # += so "select_hash" stays "hash<auto>"
                hash<auto> select_hash += {
                    "columns": (
                        "name",
                        "description",
                        "states",
                        "options",
                        "input_type",
                        "output_type",
                    ),
                };
                hash<auto> config_item_select_hash;
                if (names) {
                    config_item_select_hash."where".fsm = select_hash."where".name = op_in(names);
                }

                query = fsm_table.select(select_hash);
                config_items = fsm_config_items_table.select(config_item_select_hash);
                lib_result = getLibraryQueryResultNoRecovery("fsm_lib", "fsm", names);
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

        context (query) {
            fsm.%name = %% + {
                "states": deserialize_qorus_data(%states),
                "options": deserialize_qorus_data(%options),
                "input_type": deserialize_qorus_data(%input_type),
                "output_type": deserialize_qorus_data(%output_type),
            };
        }

        context (config_items) {
            # ignore config for fsms not present in the query
            if (!fsm{%fsm}) {
                continue;
            }
            fsm{%fsm}.config{%name} = {
                "type": %type,
                "desc": %description,
                "strictly_local": %strictly_local.toBool(),
                "config_group": %config_group,
                "sensitive": %sensitive.toBool(),
                "prefix": %prefix,
            };

            fsm{%fsm}.config{%name} += %default_value.val() ?
                {"default_value": deserialize_qorus_data(%default_value)} : {};

            fsm{%fsm}.config{%name} += %allowed_values.val() ?
                {"allowed_values": deserialize_qorus_data(%allowed_values)} : {};
        }

        # save size for return value
        int size = fsm.size();

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            # clear dependencies in existing map before adding new data
            map omqmap.fsm{$1} -= ("fsm_deps", "fsm_rdeps"), keys omqmap.fsm;

            if (names) {
                # add new fsms
                omqmap.fsm += fsm;

                # remove fsms that have been deleted, if any
                omqmap.fsm -= (keys ((map {$1: True}, names) - (keys fsm)));
            } else {
                omqmap += {
                    "fsm": fsm,
                };
            }

            # add and update libraries
            hash<string, hash<string, list<hash<auto>>>> libs = getLibraryIntern("fsm", lib_result.contextIterator());
            map omqmap.fsm{$1}.lib = libs{$1}, keys fsm;

            # 1) recalculate forward dependencies
            code calc_deps = sub (string name) {
                if (omqmap.fsm{name}.fsm_deps) {
                    return;
                }
                # check libs
                foreach hash<auto> i in (omqmap.fsm{name}.lib.fsm) {
                    calc_deps(i.name);
                    omqmap.fsm{name}.fsm_deps += omqmap.fsm{i.name}.fsm_deps;
                    omqmap.fsm{name}.fsm_deps{i.name} = True;
                }
            };
            map calc_deps($1), keys omqmap.fsm;

            # 2) calculate reverse dependencies based on full forward dependencies
            foreach hash<auto> fsm_info in (omqmap.fsm.iterator()) {
                map omqmap.fsm{$1}.fsm_rdeps{fsm_info.name} = True, keys omqmap.fsm{fsm_info.name}.fsm_deps;
            }
        }

        #QDBG_LOG("reloadFsms: fsm: %y", fsm);
        return {"fsm": size};
    }

    hash<auto> reloadSlas(*softlist ids) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(sla_reload_lock);

        on_success {
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateSlaCache");
        }

        hash<string, hash<SlaInfo>> slamap();
        hash<string, hash<SlaInfo>> slarmap();

        *hash qh;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable slas = Qorus.dsmanager.getOmqTable("sla");

                hash sh = {
                    "columns": (
                        "slaid",
                        "name",
                        "units",
                        "description",
                    ),
                };
                if (ids)
                    sh."where"."slaid" = op_in((map $1.toInt(), ids));

                qh = slas.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        context (qh) {
            slamap.%slaid += %%;
            slarmap.%name += %%;
        }

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            if (ids) {
                # get hash of names
                hash nh = map {$1.name: True}, slamap{ids}.iterator();
                # add any names of deleted slas
                map nh{$1.name} = True, omqmap.slamap{ids}.iterator();

                # temporarily copy the reverse map
                *hash cr = omqmap.slarmap;

                # remove old reverse mappings
                map remove omqmap.slarmap{$1.name}, omqmap.slamap{ids}.iterator();
                map remove omqmap.slarmap{$1.name}, slamap{ids}.iterator();

                # add possibly removed IDs with the same name keys to the id list
                ids += map cr{$1.name}.slaid, slamap{ids}.iterator(), cr{$1.name}.slaid && $1.slaid != cr{$1.name}.slaid;

                # remove old forward mappings
                remove omqmap.slamap{ids};
                # remove possibly duplicated entries
                map remove omqmap.slamap{$1.slaid}, slarmap.iterator();

                # only add if there's something to add
                if (slamap) {
                    # add forward mappings
                    omqmap.slamap += slamap;

                    # add reverse mappings
                    omqmap.slarmap += slarmap;
                }
            } else {
                omqmap += {
                    "slamap": slamap,
                    "slarmap": slarmap,
                };
            }
        }

        return {"slas": slamap.size()};
    }

    hash<auto> reloadEvents(*softlist ids) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(event_reload_lock);

        on_success
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateEventCache");

        hash emap = {};
        hash ermap = {};

        hash qh;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable workflow_event_types = Qorus.dsmanager.getOmqTable("workflow_event_types");

                hash sh = (
                    "columns": (
                        "workflow_event_typeid",
                        "name",
                        "description",
                    ),
                );
                if (ids)
                    sh."where"."workflow_event_typeid" = op_in((map $1.toInt(), ids));

                qh = workflow_event_types.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # we have to rename "description" to "desc" manually, because it's a keyword in Oracle,
        # so we can't currently use cop_as(), otherwise we'll get:
        # ORA-00923: FROM keyword not found where expected
        if (qh.name) {
            qh.desc = remove qh.description;
            context (qh) {
                emap.%workflow_event_typeid = %%;
                ermap.%name = %%;
            }
        }

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            if (ids) {
                # get hash of names
                hash nh = map {$1.name: True}, emap{ids}.iterator();
                # add any names of deleted jobs
                map nh{$1.name} = True, omqmap.emap{ids}.iterator();

                # temporarily copy the reverse map
                *hash cr = omqmap.ermap;

                # remove old reverse mappings
                map remove omqmap.ermap{$1.name}, omqmap.emap{ids}.iterator();
                map remove omqmap.ermap{$1.name}, emap{ids}.iterator();

                # add possibly removed IDs with the same name keys to the id list
                ids += map cr{$1.name}.workflow_event_typeid, emap{ids}.iterator(), cr{$1.name}.workflow_event_typeid && $1.workflow_event_typeid != cr{$1.name}.workflow_event_typeid;

                # remove old forward mappings
                remove omqmap.emap{ids};
                # remove possibly duplicated entries
                map remove omqmap.emap{$1.workflow_event_typeid}, ermap.iterator();

                # only add if there's something to add
                if (emap) {
                    # add forward mappings
                    omqmap.emap += emap;

                    # add reverse mappings
                    omqmap.ermap += ermap;
                }
            }
            else {
                omqmap += {
                    "emap": emap,
                    "ermap": ermap,
                };
            }
        }

        return {"events": emap.size()};
    }

    hash<auto> reloadMappers(*softlist ids, *bool init) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(mapper_reload_lock);

        on_success
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateLibMapCache");

        hash mmap = {};
        hash mrmap = {};

        *hash qh;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable mappers = Qorus.dsmanager.getOmqTable("mappers");

                hash sh = ("orderby": "created");
                if (ids)
                    sh."where"."mapperid" = op_in((map $1.toInt(), ids));

                qh = mappers.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        context (qh) {
            hash<auto> h = %%;
            # convert NULLs to NOTHING
            map delete h.$1, keys h, h.$1 === NULL;

            mmap.%mapperid = h;
            mrmap.%name.%version = %mapperid;
        }

        # add library information to mappers
        qh = getLibrary("mapper_lib", "mapperid", ids);
        map mmap.$1.lib = qh.$1, keys qh;

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            if (ids) {
                # temporarily copy the reverse map
                *hash<auto> cr = omqmap.mrmap;

                # remove old reverse mappings
                map remove omqmap.mrmap{$1.name}{$1.version}, omqmap.mmap{ids}.iterator();
                map remove omqmap.mrmap{$1.name}{$1.version}, mmap{ids}.iterator();

                # remove all entries where all versions have been deleted
                map remove omqmap.mrmap.$1, keys omqmap.mrmap, !omqmap.mrmap.$1;

                # add possibly removed IDs with the same name/version keys to the id list
                ids += map cr{$1.name}{$1.version}, mmap{ids}.iterator(),
                    cr{$1.name}{$1.version} && $1.mapperid != cr{$1.name}{$1.version};
                # remove old forward mappings
                remove omqmap.mmap{ids};
                foreach hash<auto> dh in (mrmap.pairIterator())
                    map remove omqmap.mmap{cr{dh.key}{$1}}, keys dh.value;

                # only add if there's something to add
                if (mmap) {
                    # add forward mappings
                    omqmap.mmap += mmap;

                    # add reverse mappings
                    foreach hash<auto> h1 in (mrmap.pairIterator())
                        map omqmap.mrmap{h1.key}{$1.key} = $1.value, h1.value.pairIterator();
                }
            } else {
                omqmap += {
                    "mmap": mmap,
                    "mrmap": mrmap,
                };
            }
        }

        if (!init) {
            Qorus.mappers.reload(ids);
        }

        return {"mappers": mmap.size()};
    }

    hash<auto> reloadVMaps(*softlist ids) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(vmap_reload_lock);

        on_success
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateVMapCache");

        hash vmmap = {};
        hash vmrmap = {};

        *hash qh;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable value_maps = Qorus.dsmanager.getOmqTable("value_maps");

                hash sh = ("orderby": "created");
                if (ids)
                    sh."where"."id" = op_in((map $1.toInt(), ids));

                qh = value_maps.select(sh);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        context (qh) {
            hash h = %% + ("throws_exception": boolean(%throws_exception));
            # convert NULLs to NOTHING
            map delete h.$1, keys h, h.$1 === NULL;
            vmmap.%id = h;
            vmrmap.%name = %id;
            # value mappings are cached on demand
        }

        {
            map_mutex.writeLock();
            on_exit map_mutex.writeUnlock();

            if (ids) {
                # temporarily copy the reverse map
                *hash cr = omqmap.vmrmap;

                # remove old reverse mappings
                map remove omqmap.vmrmap{$1.name}, omqmap.vmmap{ids}.iterator();
                map remove omqmap.vmrmap{$1.name}, vmmap{ids}.iterator();

                # add possibly removed IDs with the same name keys to the id list
                ids += map cr{$1.name}, vmmap{ids}.iterator(), cr{$1.name} && $1.id != cr{$1.name};

                # remove old forward mappings
                remove omqmap.vmmap{ids};
                # remove possibly duplicated entries
                map remove omqmap.vmmap{cr{$1}}, keys vmrmap;

                # only add if there's something to add
                if (vmmap) {
                    # add forward mappings
                    omqmap.vmmap += vmmap;

                    # add reverse mappings
                    omqmap.vmrmap += vmrmap;
                }

                # clear the cache
                remove m_vmapCache{ids};
            } else {
                omqmap += {
                    "vmmap": vmmap,
                    "vmrmap": vmrmap,
                };
                m_vmapCache = {};
            }
        }

        return {"value maps": vmmap.size()};
    }

    string dumpVMap(string name) {
        *int id;
        {
            map_mutex.readLock();
            on_exit map_mutex.readUnlock();
            id = omqmap.vmrmap{name};
            if (!id)
                throw "VALUE-MAP-ERROR", sprintf("value map name '%s' does not exist", name);
            if (!exists omqmap.vmmap{id})
                throw "VALUE-MAP-ERROR", sprintf("value map id '%d' does not exist", id);
        }

        return dumpVMapIntern(id);
    }

    string dumpVMap(int id) {
        return dumpVMapIntern(id);
    }

    string dumpVMapIntern(softstring id) {
        hash meta;
        *hash data;

        {
            map_mutex.readLock();
            on_exit map_mutex.readUnlock();
            if (!exists omqmap.vmmap{id})
                throw "VALUE-MAP-ERROR", sprintf("value map id '%d' does not exist", id);

            if (omqmap.vmmap{id}.full) {
                meta = omqmap.vmmap{id};
                data = m_vmapCache{id};
            } else {
                # release read lock, grab write lock and grab the entire vmap
                # note that on_* statements are executed in the opposite order in which they appear
                map_mutex.readUnlock();
                on_exit map_mutex.readLock();
                map_mutex.writeLock();
                on_exit map_mutex.writeUnlock();

                if (!exists omqmap.vmmap{id})
                    throw "VALUE-MAP-ERROR", sprintf("value map id '%d' does not exist", id);

                meta = omqmap.vmmap{id};
                if (omqmap.vmmap{id}.full)
                    data = m_vmapCache{id};
                else {
                    # cache entire map if it's below the size threshold
                    data = m_vmapCache{id} = getVMapIntern(id);
                    omqmap.vmmap{id}.full = True;
                }
            }
        }

        string ret = sprintf("## created: %s modified: %s id: %d\n",
                             meta.created.format("YYYY-MM-DD HH:mm:SS.xx"),
                             meta.modified.format("YYYY-MM-DD HH:mm:SS.xx"),
                             meta.id);
        ret += sprintf("# name: %s\n", meta.name);
        if (meta.description) ret += sprintf("# desc: %s\n", meta.description);
        if (meta.author) ret += sprintf("# author: %s\n", meta.author);
        ret += sprintf("# exception: %s\n", meta.throws_exception ? "true" : "false");
        ret += sprintf("# valuetype: %s\n", meta.valuetype);
        if (meta.dateformat) ret += sprintf("# dateformat: %s\n", meta.dateformat);
        ret += sprintf("\n");

        if (meta.valuetype == "raw")
            meta.valuetype = "string";

        hash<auto> opts = {
            "write-headers": False,
            "verify-columns": False,
            "headers": ("0", "1", "2"),
            "fields": {
                "0": "string",
                "1": meta.valuetype == "date"
                    ? {
                        "type": meta.valuetype,
                        "format": meta.dateformat,
                    }
                    : meta.valuetype,
                "2": "*string"
            },
        };
        CsvUtil::CsvStringWriter csv(opts);
        map csv.writeLine(("0": $1.key, "1": $1.value.value, "2": $1.value.enabled ? "true" : "false")), data.pairIterator();
        ret += sprintf("%s\n# END\n", csv.getContent());

        return ret;
    }

    auto getVMapValue(string name, *string key) {
        map_mutex.readLock();
        on_exit map_mutex.readUnlock();

        *int id = omqmap.vmrmap{name};
        if (!id)
            throw "VALUE-MAP-ERROR", sprintf("value map name '%s' does not exist", name);
        if (!exists omqmap.vmmap{id})
            throw "VALUE-MAP-ERROR", sprintf("value map id '%d' does not exist", id);

        return getVMapValueUnlocked(id, key);
    }

    auto getVMapValue(int id, *string key) {
        map_mutex.readLock();
        on_exit map_mutex.readUnlock();

        if (!exists omqmap.vmmap{id})
            throw "VALUE-MAP-ERROR", sprintf("value map id '%d' does not exist", id);

        return getVMapValueUnlocked(id, key);
    }

    # this method always starts with readLock on; returns the entire value map
    private *hash<auto> getVMapValueUnlocked(softstring id) {
        if (omqmap.vmmap{id}.full)
            return m_vmapCache{id};

        # note that on_* statements are executed in the opposite order in which they appear
        map_mutex.readUnlock();
        on_exit map_mutex.readLock();
        map_mutex.writeLock();
        on_exit map_mutex.writeUnlock();

        if (!omqmap.vmmap{id}.full) {
            m_vmapCache{id} = getVMapIntern(id);
            omqmap.vmmap{id}.full = True;
        }

        *hash rv = m_vmapCache{id};
        # remove "miss" entries assigned to NOTHING
        if (m_vmapCache{id}.miss)
            map remove rv.($1.key), rv.pairIterator(), !exists $1.value;
        return rv;
    }

    # this method always starts with readLock on
    private auto getVMapValueUnlocked(softstring id, string key) {
        if (!m_vmapCache{id}.hasKey(key) && !omqmap.vmmap{id}.full) {
            # note that on_* statements are executed in the opposite order in which they appear
            map_mutex.readUnlock();
            on_exit map_mutex.readLock();
            map_mutex.writeLock();
            on_exit map_mutex.writeUnlock();

            return getVMapValueUnlockedIntern(id, key);
        }
        return doVMapValue(id, key);
    }

    string setVMapValue(string name, string key, auto value, *bool enabled) {
        WriteLockHelper wlh(map_mutex);

        *int id = omqmap.vmrmap{name};
        if (!id)
            throw "VALUE-MAP-ERROR", sprintf("value map name '%s' does not exist", name);

        return setVMapValueIntern(id, key, value, enabled);
    }

    string setVMapValue(int id, string key, auto value, *bool enabled) {
        WriteLockHelper wlh(map_mutex);
        return setVMapValueIntern(id, key, value, enabled);
    }

    private string setVMapValueIntern(int id, string key, auto value, *bool enabled) {
        if (!exists omqmap.vmmap{id})
            throw "VALUE-MAP-ERROR", sprintf("value map id '%d' does not exist", id);

        SqlUtil::AbstractTable t = get_sql_table_system_trans("omq", "value_map_values");

        int rc;
        if (!exists value || value == NULL) {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_success omqp.commit();
                    on_error omqp.rollback();

                    rc = t.del(("value_map_id": id, "keyname": key));
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (trans.restartTransaction(ex))
                        continue;
                    rethrow;
                }
                trans.reset();
                break;
            }
            remove m_vmapCache{id}{key};
            return rc ? "DELETED" : "IGNORED";
        }

        # insert/update row
        *hash row = m_vmapCache{id}{key} + {
            "value_map_id": id,
            "keyname": key,
            "value": vmap_value(omqmap.vmmap{id}, \value),
            "created": m_vmapCache{id}{key}.created ?? now_us(),
            "modified": now_us(),
        };

        if (exists enabled)
            row.enabled = enabled.toInt(); # toInt() for pgsql

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_success omqp.commit();
                on_error omqp.rollback();

                # we have to use the UpsertSelectFirst upsert strategy, because an optimized upsert
                # cannot distinguish between inserted and updated rows on some DBs (like Oracle)
                rc = t.upsert(row, AbstractTable::UpsertSelectFirst);

                if (rc == AbstractTable::UR_Inserted)
                    Qorus.dsmanager.getOmqTable("value_maps").update(("mapsize": omqmap.vmmap{id}.mapsize), ("id": id));
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            remove m_vmapCache{id}{key};
            break;
        }

        if (rc == AbstractTable::UR_Inserted)
            omqmap.vmmap{id}.mapsize++;

        m_vmapCache{id}{key} = row;
        m_vmapCache{id}{key}.value = value;

        return rc == AbstractTable::UR_Inserted ? "CREATED" : "UPDATED";
    }

    /**
        for any cache object with a forward and 2-level reverse map (name -> version -> id) with "lvcreated" and "lastversion" keys in the name level
        rkey: set = the reverse map points to a hash and the value is the key, NOTHING = it points to an ID
    */
    private doDeltaIntern(reference ids, *hash<auto> fmap, *hash<auto> rmap, string fmap_name, string rmap_name,
        *string id_name, *string rkey, *hash<string, int> logger_map) {

        # get hash of names
        hash<string, bool> nh = map {$1.name: True}, fmap{ids}.iterator();
        # add any names of deleted objects
        map nh{$1.name} = True, omqmap{fmap_name}{ids}.iterator();

        # get a list of deleted IDs
        #*list<string> deleted_ids = keys (omqmap{fmap_name}{ids} - keys fmap);

        # temporarily copy the reverse map
        *hash<auto> cr = omqmap{rmap_name};

        # remove old reverse mappings
        map remove omqmap{rmap_name}{$1.name}{$1.version}, omqmap{fmap_name}{ids}.iterator();
        map remove omqmap{rmap_name}{$1.name}{$1.version}, fmap{ids}.iterator();
        map remove omqmap{rmap_name}{$1}.("lvcreated", "lastversion"), keys nh;

        # remove all entries where all versions have been deleted
        map remove omqmap{rmap_name}{$1}, keys omqmap{rmap_name}, !omqmap{rmap_name}{$1};

        # add possibly removed IDs with the same name/version keys to the id list
        if (rkey) {
            ids += map cr{$1.value.name}{$1.value.version}{rkey},
                fmap{ids}.pairIterator(),
                cr{$1.value.name}{$1.value.version}{rkey} && $1.key != cr{$1.value.name}{$1.value.version}{rkey};
        } else {
            ids += map cr{$1.value.name}{$1.value.version},
                fmap{ids}.pairIterator(),
                cr{$1.value.name}{$1.value.version} && $1.key != cr{$1.value.name}{$1.value.version};
        }

        # remove old forward mappings
        remove omqmap{fmap_name}{ids};
        # remove possibly duplicated entries
        if (rkey) {
            foreach hash<auto> dh in (rmap.pairIterator())
                map remove omqmap{fmap_name}{cr{dh.key}{$1}{rkey}}, keys dh.value;
        } else {
            foreach hash<auto> dh in (rmap.pairIterator())
                map remove omqmap{fmap_name}{cr{dh.key}{$1}}, keys dh.value;
        }

        string logger_key = "logger_" + fmap_name;

        if (id_name) {
            # remove old IDs
            *hash<string, bool> dh = map {$1: True}, ids;
            # remove IDs about to be readded
            omqmap{id_name} = select omqmap{id_name}, !dh.$1;
            # remove logger -> interface ID entries about to be readded
            map remove omqmap{logger_key}{$1.key}, omqmap{logger_key}.pairIterator(), dh{$1.value};
        }

        # only add if there's something to add
        if (fmap) {
            # add forward mappings
            omqmap{fmap_name} += fmap;

            # add reverse mappings
            foreach hash<auto> h1 in (rmap.pairIterator())
                map omqmap{rmap_name}{h1.key}{$1.key} = $1.value, h1.value.pairIterator();

            if (id_name) {
                omqmap{id_name} += ids;
                if (logger_map) {
                    omqmap{logger_key} += logger_map;
                }
            }
        }

        # redo last version for all changed objects by name
        foreach string name in (keys nh) {
            foreach string version in (keys omqmap{rmap_name}{name}) {
                hash<auto> ih = rkey ? omqmap{rmap_name}{name}{version} : omqmap{fmap_name}{omqmap{rmap_name}{name}{version}};
                if (!omqmap{rmap_name}{name}.lastversion || (ih.created > omqmap{rmap_name}{name}.lvcreated))
                    omqmap{rmap_name}{name} += (
                        "lvcreated"   : ih.created,
                        "lastversion" : ih.version,
                    );
            }
        }
    }

    static private doListResult(reference h, string k, *hash<auto> q) {
        context (q) {
            hash<auto> row = %%;
            if (!h.(row.workflowid){k})
                h.(row.workflowid){k} = ();
            h.(row.workflowid){k} += row{k};
        }
    }

    static private doResult(reference h, string k, *hash q) {
        context (q) {
            hash row = %%;
            softstring wfid = row.workflowid;
            if (!h.hasKey(wfid))
                continue;
            if (!h.(row.workflowid){k})
                h.(row.workflowid){k} = ();
            h.(row.workflowid){k} += row;
        }
    }

    static private *hash<auto> getWorkflowInfo(softlist<auto> wfl, bool filter) {
        *hash<auto> sh;
        if (filter)
            sh."where".workflowid = op_in(wfl);

        QorusRestartableTransaction trans();
        while (True) {
            try {
                hash<auto> wfh;
                map wfh.$1 = NOTHING, wfl;

                {
                    AbstractTable workflow_keys = Qorus.dsmanager.getOmqTable("workflow_keys");

                    QorusMapManager::doListResult(\wfh, "keyname", workflow_keys.select(("columns": ("workflowid", "keyname")) + sh));
                }

                {
                    AbstractTable workflow_steps = Qorus.dsmanager.getOmqTable("workflow_steps");
                    AbstractTable steps = Qorus.dsmanager.getOmqTable("steps");

                    hash<auto> msh = (
                        "columns": ("workflowid", "s.stepid", "dependson_stepid", "s.name", "s.steptype"),
                        "join": join_inner(steps, "s", ("stepid": "stepid")),
                    ) + sh;

                    QorusMapManager::doResult(\wfh, "steps", workflow_steps.select(msh));
                }

                {
                    AbstractTable segment_steps = Qorus.dsmanager.getOmqTable("segment_steps");
                    QorusMapManager::doResult(\wfh, "segments", segment_steps.select(sh));
                }

                {
                    AbstractTable segment_dependencies = Qorus.dsmanager.getOmqTable("segment_dependencies");

                    *hash msh = sh;
                    msh."where" += ("segmentid": op_cne("dependson_segmentid"));

                    QorusMapManager::doResult(\wfh, "segdeps", segment_dependencies.select(msh));
                }

                {
                    AbstractTable segment_async_link = Qorus.dsmanager.getOmqTable("segment_async_link");
                    QorusMapManager::doResult(\wfh, "segasync", segment_async_link.select(sh));
                }

                {
                    AbstractTable workflow_options = Qorus.dsmanager.getOmqTable("workflow_options");
                    QorusMapManager::doResult(\wfh, "options", workflow_options.select(sh));
                }

                {
                    AbstractTable workflow_lib = Qorus.dsmanager.getOmqTable("workflow_lib");
                    QorusMapManager::doResult(\wfh, "library", workflow_lib.select(sh + ("orderby": "load_order")));
                }

                {
                    AbstractTable custom_statuses = Qorus.dsmanager.getOmqTable("custom_statuses");
                    QorusMapManager::doResult(\wfh, "custstat", custom_statuses.select(sh));
                }

                QDBG_TEST_CLUSTER_FAILOVER();
                return wfh;
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
        }
    }

    #! Add a plugin to the plugins map
    /** @param name name of the plugin to be registered

        If the plugin is already registered, no error is thrown.
    */
    registerPlugin(string name) {
        map_mutex.writeLock();
        on_exit {
            map_mutex.writeUnlock();
        }

        QDBG_ASSERT(!plugin_map{name});
        plugin_map{name} = True;
    }

    #! Remove a plugin from the plugins map
    /** @param name name of the plugin to be deregistered

        If the plugin is not registered, no error is thrown.
    */
    deregisterPlugin(string name) {
        map_mutex.writeLock();
        on_exit {
            map_mutex.writeUnlock();
        }

        QDBG_ASSERT(plugin_map{name});
        remove plugin_map{name};
    }

    #! Check if a plugin is registered
    /** @param name name of the plugin to be checked
    */
    bool isPluginRegistered(string name) {
        map_mutex.readLock();
        on_exit {
            map_mutex.readUnlock();
        }

        return plugin_map{name} ?? False;
    }

    #! Return names of registered plugins or an empty list if there are none
    softlist<string> getRegisteredPlugins() {
        map_mutex.readLock();
        on_exit {
            map_mutex.readUnlock();
        }

        return keys plugin_map;
    }

    hash<auto> reloadConfigItemValues(*softlist<string> item_names) {
        # issue #3242: do not use "synchronized" on methods or it serializes all reload calls
        AutoLock cal(config_reload_lock);

        on_success {
            Qorus.getMaster().broadcastToAllInterfaces("qmm", "invalidateConfigValuesCache");
        }

        *hash<auto> query_hash;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable config_item_values_table = Qorus.dsmanager.getOmqTable("config_item_values");

                hash select_hash = {
                    "columns": (
                        "name",
                        "level",
                        "value",
                    ),
                };
                if (item_names) {
                    select_hash."where".name = op_in(item_names);
                }

                query_hash = config_item_values_table.select(select_hash);
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

        hash<auto> config_item_values = {};
        context (query_hash) {
            config_item_values.%name.%level = %value.val() ? deserialize_qorus_data(%value) : NOTHING;
        }

        # make atomic update to omqmap
        {
            WriteLockHelper wlh(map_mutex);

            if (item_names) {
                # add new items
                omqmap.configItemValues += config_item_values;

                # remove items that have been deleted, if any
                omqmap.configItemValues -= (keys ((map {$1: True}, item_names) - (keys config_item_values)));

            } else {
                omqmap.configItemValues = config_item_values;
            }
        }
%ifdef QorusDebugConfigItems
        QDBG_LOG("CONFIG_ITEM_VALUES RELOADED: %y", config_item_values);
%endif
        return {"config_values": config_item_values.size()};
    }

    # returns interface id based on the given interface type, name and version
    auto rLookupInterface(string interface_type, string interface_name, string interface_version) {
         switch (interface_type) {
            case "step":
                return rLookupStep(interface_name, interface_version);
            case "workflow":
                return rLookupWorkflow(interface_name, interface_version).workflowid;
            case "service":
                return rLookupService("system", interface_name, interface_version) ??
                       rLookupService("user", interface_name, interface_version);
            case "job":
                return rLookupJob(interface_name, False).jobid;
            case "fsm":
                if (lookupFsm(interface_name)) {
                    return interface_name;
                }
                throw "UNKNOWN-FINITE-STATE-MACHINE", sprintf("finite state machine %y is unknown", interface_name);
            case "pipeline":
                if (lookupPipeline(interface_name)) {
                    return interface_name;
                }
                throw "UNKNOWN-PIPELINE", sprintf("data pipeline %y is unknown", interface_name);
        }
        throw "UNKNOWN-INTERFACE-TYPE-ERROR", sprintf("unknown interface type %y", interface_type);
    }

    # returns an interface based on the given interface type, name and version
    *hash<auto> rLookupInterface(string interface_type, string interface_name) {
        switch (interface_type) {
            case "step":
                return rLookupStep(interface_name);
            case "workflow":
                return rLookupWorkflow(interface_name);
            case "service":
                return rLookupService("system", interface_name) ?? rLookupService("user", interface_name);
            case "job":
                return rLookupJob(interface_name, False);
            case "fsm":
                return lookupFsm(interface_name);
            case "pipeline":
                return lookupPipeline(interface_name);
        }
        throw "UNKNOWN-INTERFACE-TYPE-ERROR", sprintf("unknown interface type %y", interface_type);
    }

    *hash<auto> lookupInterface(string interface_type, auto interface_id) {
        switch (interface_type) {
            case "step":
                return lookupStep(interface_id, False);
            case "workflow":
                return lookupWorkflow(interface_id, True);
            case "service":
                return lookupService(interface_id);
            case "job":
                return lookupJob(interface_id);
            case "fsm":
                return lookupFsm(interface_id);
            case "pipeline":
                return lookupPipeline(interface_id);
        }
        throw "UNKNOWN-INTERFACE-TYPE-ERROR", sprintf("unknown interface type %y", interface_type);
    }

    private:internal configItemTypeError(string name, string type, auto value) {
        throw "CONFIG-ITEM-ERROR", sprintf("configuration item %y has type %y and cannot be set from type %y "
            "value %y", name, type, value.type(), value);
    }

    # returns the new value or throws a CONFIG-ITEM-ERROR exception if type is incorrect
    private:internal auto getConfigItemNewValue(string name, string type, auto value, bool is_enum) {
        if (!exists value) {
            if (!ConfigItemStarTypes.hasKey(type)) {
                configItemTypeError(name, type, value);
            }
            return NOTHING;
        }

        # don't check the type if the value is a templated string (except for enums)
        # or if the type is any
        if ((!is_enum && UserApi::isSingleTemplatedString(value)) || type == "any") {
            return value;
        }

        switch (type) {
            case "*int":
            case "int": {
                if (!value.intp()) {
                    configItemTypeError(name, type, value);
                }
                softint new_value = value;
                return new_value;
            }
            case "*bool":
            case "bool": {
                if (!value.intp()) {
                    configItemTypeError(name, type, value);
                }
                softbool new_value = value;
                return new_value;
            }
            case "*float":
            case "float": {
                # values that can be converted to an integer can also be converted to a float
                if (!value.intp()) {
                    configItemTypeError(name, type, value);
                }
                softfloat new_value = value;
                return new_value;
            }
            case "*date":
            case "date": {
                # we allow conversion only from a string
                if (value.typeCode() != NT_DATE && value.typeCode() != NT_STRING) {
                    configItemTypeError(name, type, value);
                }
                softdate new_value = value;
                return new_value;
            }
            case "*hash":
            case "hash": {
                if (value.typeCode() != NT_HASH) {
                    configItemTypeError(name, type, value);
                }
                hash new_value = value;
                return new_value;
            }
            case "*list":
            case "list": {
                if (value.typeCode() != NT_LIST) {
                    configItemTypeError(name, type, value);
                }
                list new_value = value;
                return new_value;
            }
        }
        if (!value.strp()) {
            configItemTypeError(name, type, value);
        }
        # otherwise we convert to a string if possible
        softstring new_value = value;

        return new_value;
    }

    private:internal commitToConfigItemValuesTable(string level, string item_name, string transaction_type,
                                                   *string value) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                AbstractTable config_item_values_table = Qorus.dsmanager.getOmqTable("config_item_values");

                on_error config_item_values_table.rollback();
                on_success config_item_values_table.commit();

                switch (transaction_type) {
                    case "update":
                    case "insert":
                        config_item_values_table.upsert({
                            "level": level,
                            "name": item_name,
                            "value": value,
                            "manually_updated": 1,
                        });
                        break;
                    case "delete":
                        config_item_values_table.del({"level": level, "name": item_name});
                        break;

                    default: throw "CONFIG-ITEM-ERROR", sprintf("unknown transaction type %s", transaction_type);
                }
                QDBG_LOG("%s %y configuration item, level: %s", transaction_type, item_name, level);
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

    private:internal checkIfValueIsAllowed(string item_name, hash config_item_info, auto value) {
        if (!config_item_info.hasKey("allowed_values")) {
            return;
        }
        foreach auto allowed_value in (config_item_info{"allowed_values"}) {
            if (allowed_value === value) {
                return;
            }
        }

        throw "CONFIG-ITEM-ERROR", sprintf("cannot set value %y for the configuration item %y the value is not allowed"
            ", allowed values: %y", value, item_name, config_item_info{"allowed_values"});
    }

    private:internal bool updateConfigItemValue(string level, string item_name, auto value) {
        bool is_set = False;
        if (value === getConfigItemValue(level, item_name, \is_set)) {
            return False;
        }

        *string db_value = UserApi::serializeQorusDataWithNothing(value);
        commitToConfigItemValuesTable(level, item_name, "update", db_value);
        {
            WriteLockHelper wlh(map_mutex);
            omqmap.configItemValues{item_name}{level} = value;
        }

        Qorus.getMaster().broadcastToAllInterfaces("qmm", "configItemValueChanged",
                                                   ("update", item_name, level, value));
        return True;
    }

    private:internal auto deleteConfigItemValue(string level, string item_name, *reference<bool> deleted) {
        bool is_set = False;
        auto value = getConfigItemValue(level, item_name, \is_set);
        if (!is_set) {
            deleted = False;
            return NOTHING;
        }
        commitToConfigItemValuesTable(level, item_name, "delete");

        {
            WriteLockHelper wlh(map_mutex);
            remove omqmap.configItemValues{item_name}{level};
        }
%ifdef QorusDebugConfigItems
        QDBG_LOG("QMM::deleteConfigItemValue: value=%y deleted on level: %y", value, level);
%endif
        deleted = True;

        Qorus.getMaster().broadcastToAllInterfaces("qmm", "configItemValueChanged", ("delete", item_name, level));
        return value;
    }

    private:internal bool insertConfigItemValue(string level, string item_name, auto value) {
%ifdef QorusDebugConfigItems
        QDBG_LOG("inserting value: %y for %y configuration item, level: %s", value, item_name, level);
%endif
        bool is_set = False;
        getConfigItemValue(level, item_name, \is_set);
        if (is_set) {
            return False;
        }
        *string db_value = UserApi::serializeQorusDataWithNothing(value);
        commitToConfigItemValuesTable(level, item_name, "insert", db_value);
        {
            WriteLockHelper wlh(map_mutex);
            omqmap.configItemValues{item_name}{level} = value;
        }

        Qorus.getMaster().broadcastToAllInterfaces("qmm", "configItemValueChanged",
                                                   ("insert", item_name, level, value));
        return True;
    }

    # checks if config item exists on given interface level
    # returns config item info
    private:internal hash checkIfConfigItemExists(*hash<auto> interface, string interface_type, auto interface_id,
                                                  string item_name) {
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }
        if (!interface) {
            throw "CONFIG-ITEM-ERROR", sprintf("there is no %y with id %d", interface_type, interface_id);
        }

        if (interface.config{item_name}) {
            return interface.config{item_name};
        }

        if (interface_type != "workflow") {
            throw "CONFIG-ITEM-ERROR", sprintf("%s has no configuration item %y; known configuration items: %y",
                getInterfaceDescription(interface, interface_type, interface_id), item_name, keys interface.config);
        }

        # in case interface is workflow then check if at least one step has the item
        foreach auto step in (interface.stepinfo.iterator()) {
            if (exists step.config{item_name} && !step.config{item_name}.strictly_local) {
                return step.config{item_name};
            }
        }

        # find all known configs having strictly_local set to True to show to user
        hash<string, bool> known_configs;
        foreach hash<auto> step in (interface.stepinfo.iterator()) {
            map known_configs{$1} = True, keys step.config, step.config{$1}.strictly_local == False;
        }

        throw "CONFIG-ITEM-ERROR", sprintf("%s has no configuration item %y; known configuration items: %y",
            getInterfaceDescription(interface, interface_type, interface_id), item_name, keys known_configs);

    }

    # returns config item if exists otherwise CONFIG-ITEM-ERROR exception is thrown
    private:internal *hash<auto> getConfigItem(string item_name, bool strictly_local = False, bool no_exception = False) {
        code get_config_item = *hash sub (*hash interfaces) {
            foreach auto interface in (interfaces.iterator()) {
                if (exists interface.config{item_name} &&
                    interface.config{item_name}.strictly_local == strictly_local) {
                    return interface.config{item_name};
                }
            }
            return;
        };

        *hash<auto> config_item = get_config_item(getJobMap());
        if (exists config_item) {
            return config_item;
        }

        config_item = get_config_item(getServiceMap());
        if (config_item) {
            return config_item;
        }

        config_item = get_config_item(getStepMap());
        if (config_item) {
            return config_item;
        }

        config_item = get_config_item(getFsmMap());
        if (config_item) {
            return config_item;
        }

        config_item = get_config_item(getPipelineMap());
        if (config_item) {
            return config_item;
        }

        if (no_exception) {
            return;
        }
        throw "CONFIG-ITEM-ERROR", sprintf("config item %s with strictly_local=%y is not defined by any interface",
                                           item_name, strictly_local);
    }

    # returns all interfaces that require the given config item
    private:internal hash<auto> getInterfacesForConfigItem(string item_name, bool strictly_local = False,
            bool with_fsms = True) {
        hash<auto> rv = getInterfacesForConfigItem(getJobMap(), "job", item_name, strictly_local) +
            getInterfacesForConfigItem(getServiceMap(), "service", item_name, strictly_local) +
            getInterfacesForConfigItem(getStepMap(), "step", item_name, strictly_local);
        if (with_fsms) {
            rv += getInterfacesForConfigItem(getFsmMap(), "fsm", item_name, strictly_local);
        }
        return rv;
    }

    private:internal hash<auto> getInterfacesForConfigItem(*hash<auto> interfaces, string interface_type, string item_name,
                                                      bool strictly_local) {
        hash<auto> result = {};
        foreach hash<auto> i in (interfaces.pairIterator()) {
            if (i.value.config{item_name} &&
                i.value.config{item_name}.strictly_local == strictly_local) {
                result{interface_type}{i.key} = i.value;
                continue;
            }

            # for FSMs, check pipelines in library as well
            if (interface_type == "fsm" && i.value.lib.pipelines && getPipelinesForConfigItem(item_name, i.value, strictly_local)) {
                result{interface_type}{i.key} = i.value;
                continue;
            }
        }

        return result;
    }

    # returns all steps that require the given config item
    private:internal hash<auto> getStepsForConfigItem(string item_name, *int workflow_id,
            bool strictly_local = False) {
        hash<auto> steps;
        if (exists workflow_id) {
            *list<string> stepids;
            {
                ReadLockHelper rlh(map_mutex);
                stepids = keys omqmap.wfmap{workflow_id}.stepmap;
            }
            if (stepids) {
                ReadLockHelper rlh(map_mutex);
                steps = omqmap.stepmap{stepids};
            }
        } else {
            steps = getStepMap();
        }

        return getInterfacesForConfigItem(steps, "step", item_name, strictly_local);
    }

    # returns all FSMs that require the given config item
    private:internal *hash<auto> getFsmsForConfigItem(string item_name, hash<auto> ix_info,
        bool strictly_local = False) {
        *hash<auto> fsms = getFsmInfoRecursive(ix_info.lib.fsm);
        return getInterfacesForConfigItem(fsms, "fsm", item_name, strictly_local);
    }

    private:internal *hash<auto> getFsmInfoRecursive(*list<auto> fsm_list) {
        hash<auto> fsms;
        foreach hash<auto> fsm_entry in (fsm_list) {
            *hash<auto> fsm_info = lookupFsm(fsm_entry.name);
            if (!fsm_info) {
                olog(LoggerLevel::INFO, "metadata error: Finite State Machine %y does not exist", fsm_entry.name);
                return;
            }
            fsms{fsm_entry.name} = fsm_info;
            fsms += getFsmInfoRecursive(fsm_info.lib.fsm);
        }
        return fsms;
    }

    # returns all pipelines that require the given config item
    private:internal *hash<auto> getPipelinesForConfigItem(string item_name, hash<auto> ix_info,
        bool strictly_local = False) {
        hash<auto> pipelines;
        foreach hash<auto> pipeline_entry in (ix_info.lib.pipelines) {
            *hash<auto> pipeline_info = lookupPipeline(pipeline_entry.name);
            if (!pipeline_info) {
                olog(LoggerLevel::INFO, "metadata error: pipeline %y does not exist", pipeline_entry.name);
                return;
            }
            pipelines{pipeline_entry.name} = pipeline_info;
        }
        return getInterfacesForConfigItem(pipelines, "pipeline", item_name, strictly_local);
    }

    # sends a config item changed event for all interfaces that require the given config item
    # level_filter used to filter only values on relevant levels
    private:internal postConfigItemChangedForAllInterfaces(string item_name, hash config_item_info, hash level_filter,
                                                           bool was_set, *int workflow_id) {
        hash<auto> interfaces = getInterfacesForConfigItem(item_name);
%ifdef QorusDebugConfigItems
        QDBG_LOG("QMM::postConfigItemChangedForAllInterfaces(): interfaces: %y", interfaces);
%endif

        *string level;
        bool is_set;
        foreach hash<auto> elem in (interfaces.pairIterator()) {
            string type = elem.key;
            foreach hash<auto> ix_elem in (elem.value.pairIterator()) {
                softint id = ix_elem.key;
                auto value = findConfigItemValue(type, id, item_name, config_item_info, \level, \is_set,
                                                 workflow_id);
                if (!exists level || level_filter.hasKey(level)) {
%ifdef QorusDebugConfigItems
                    QDBG_LOG("QMM::postConfigItemChangedForAllInterfaces(): interface: %y, type: %y, item: %y, value: %y, level: %s", ix_elem.value, type, item_name, value, level);
%endif
                    configItemChangedOnLowestLevel(ix_elem.value, type, id, item_name, config_item_info,
                                                   value, was_set);
                }
            }
        }
    }

    # sends config item changed event for a specific interface (can also be global)
    private:internal postConfigItemChanged(hash<auto> config_item_info, *hash<auto> interface, string interface_type, auto interface_id,
                                           string item_name, auto value, bool is_set = True, *string level,
                                           *softint workflow_id) {
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }
        hash<auto> event_info = {
            "interfaceType": interface_type,
            "is_set": is_set,
            "is_templated_string": UserApi::isSingleTemplatedString(value),
        };

        if (interface) {
            string key = interface_type;
            if (interface_type != "fsm" && interface_type != "pipeline") {
                key += "id";
            }
            event_info += {
                "interfaceName": interface.name,
                key: interface_id
            } + (interface.version ? {"version": interface.version} : {})
              + (workflow_id ? {"workflowid": workflow_id} : {});
        }

        if (level) {
            event_info.level = level;
        }

        if (config_item_info.type == "any") {
            string type = value.type();
            event_info.currentType = ConfigItemTypeMap.hasKey(type) ? ConfigItemTypeMap{type} : type;
        }

%ifdef QorusDebugConfigItems
        QDBG_LOG("QMM::postConfigItemChanged: interface: %y, type: %y, id: %y, item: %y, value: %y, level: %y, wf_id: %y", interface, interface_type, interface_id, item_name, value, level, workflow_id);
%endif
        Qorus.events.postConfigItemChanged(tld.cx, event_info, item_name, value);

        # alert local interfaces to changes; remote interfaces are already alerted with the QorusMapManagerClient
        switch (interface_type) {
            case "service": {
                # notify local services only
                *hash<auto> svc = lookupService(interface_id, False);
                if (svc && !svc.remote) {
                    services.configItemValueChanged(svc.type, svc.name, item_name, value);
                }
                break;
            }
        }
    }

    # raises or clears ongoing alert for not configured config item of the interface
    private:internal updateUnconfiguredAlert(string item_name, hash<auto> interface, string interface_type,
            auto interface_id, bool clear, *hash<auto> info, *hash<auto> fsm_info,
            *hash<auto> pipeline_info) {
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }
        string error = sprintf("config item %s of ", item_name);
        if (fsm_info) {
            if (pipeline_info) {
                error += getInterfaceDescription(pipeline_info, "pipeline", pipeline_info.name) + " referenced in ";
            }
            error += getInterfaceDescription(fsm_info, "fsm", fsm_info.name) + " referenced in ";
        }

        error += sprintf("%s is not configured", getInterfaceDescription(interface, interface_type, interface_id));

        ActionReason reason(tld.cx, error);

        string alert_name = sprintf("%s-NOT-SET", item_name.upr());

        info = info ?? interface.("name", "version", "servicetype") + {
            "config": interface{"config"}{item_name} + {"name": item_name}
        };

        clear ? Qorus.alerts.clearOngoingAlert(interface_type.upr(), interface_id, alert_name) :
                Qorus.alerts.raiseOngoingAlert(reason, interface_type.upr(), interface_id, alert_name, info);

%ifdef QorusDebugConfigItems
        QDBG_LOG("QMM::updateUnconfiguredAlert: item name: %y, interface: %y, interface_type: %y, interface_id: %y, clear: %y", item_name, interface, interface_type, interface_id, clear);
%endif
    }

    /* Checks if the given interface has all config items configured - if not raise an alert
        @param interface information hash with config key (service, step, job)
        @param interface_type one of the following strings: job, service, step, workflow
        @return True if the interface is properly configured otherwise False
     */
    bool checkIfInterfaceIsConfigured(*hash<auto> interface, string interface_type) {
        if (!exists interface) {
            return True;
        }

%ifdef QorusDebugConfigItems
        QDBG_LOG("QMM::checkInterfaceIfConfigured: check: %y of type %y", interface, interface_type);
%endif

        bool configured = True;
        *string level;
        bool is_set;
        foreach string item_name in (keys interface{"config"}) {
            string interface_id = interface_type + "id";
            findConfigItemValue(interface_type, interface{interface_id}, item_name,
                                interface{"config"}{item_name}, \level, \is_set);
%ifdef QorusDebugConfigItems
            QDBG_LOG("QMM::checkInterfacesIfConfigured: find value of %y for %y, is_set: %y", item_name, interface, is_set);
%endif
            updateUnconfiguredAlert(item_name, interface, interface_type, interface{interface_id}, is_set);

            configured = !is_set ? False : configured;
        }

        return configured;
    }

    private:internal startOrStopInterfaces(*hash<string, bool> idh, string interface_type, bool start,
                                           string object_name) {
        if (!idh) {
            return;
        }

        list<string> ids = keys idh;

        switch (interface_type) {
            case "job":
                # ensure atomicity of potential job starts and stops
                AtomicMultiClassActionHelper atomic_helper(NOTHING, NOTHING, ids);
                start
                    ? atomic_helper.doBackgroundJobs(ids, \Qorus.rbac.startJobs(), tld.cx, "set value for",
                        "unconfigured", object_name, idh, atomic_helper)
                    : atomic_helper.doBackgroundJobs(ids, \Qorus.rbac.stopJobs(), "deleted value for", "configured",
                        object_name, idh, atomic_helper);
                break;

            case "service":
                # ensure atomicity of potential service starts and stops
                AtomicMultiClassActionHelper atomic_helper(NOTHING, ids);
                start
                    ? atomic_helper.doBackgroundServices(ids, \Qorus.rbac.autoStartServices(), tld.cx, "set value for",
                        "unconfigured", object_name, idh, atomic_helper)
                    : atomic_helper.doBackgroundServices(ids, \Qorus.rbac.stopServices(), "deleted value for", "configured",
                        object_name, idh, atomic_helper);
                break;

            case "workflow":
                # ensure atomicity of a potential workflow start or stop
                AtomicMultiClassActionHelper atomic_helper(ids);
                start
                    ? atomic_helper.doBackgroundWorkflows(ids, \Qorus.rbac.autoStartWorkflows(), tld.cx, "set value for",
                        "unconfigured", object_name, idh, atomic_helper)
                    : atomic_helper.doBackgroundWorkflows(ids, \Qorus.rbac.stopWorkflows(), "deleted value for", "configured",
                        object_name, idh, atomic_helper);
                break;

            default:
                break;
        }
    }

    # checks if the given config item is set in all interfaces that are using it - if not raise an alert
    # also tries to start or stop interfaces
    private:internal checkIfInterfacesAreConfiguredFromGlobalChange(string item_name, hash<auto> config_item_info,
                                                                    bool value_is_set) {
        *hash<auto> interfaces = getInterfacesForConfigItem(item_name, config_item_info{"strictly_local"}, False);

        if (!exists interfaces) {
            olog(LoggerLevel::INFO, "WARNING: config item %s is not found", item_name);
            return;
        }

        code check_interfaces = sub (string interface_type, *hash<auto> interfaces_, *softint step_id) {
            *string level;
            bool is_set;

            # get hash of updated interfaces
            hash<string, bool> idh;
            foreach hash<auto> elem in (interfaces_{interface_type}.pairIterator()) {
                findConfigItemValue(step_id ? "step" : interface_type, step_id ?? elem.key, item_name,
                                    config_item_info, \level, \is_set);
                # only process if a change was made
                if (value_is_set == is_set && level == "global") {
                    idh{elem.key} = True;
                    updateUnconfiguredAlert(item_name, elem.value, interface_type, elem.key, is_set);
                } else {
                    # check if the config item is used in any FSMs used by this interface
                    *hash<auto> fsm_info = getFsmsForConfigItem(item_name, elem.value);
                    foreach hash<auto> fsm_elem in (fsm_info.fsm.pairIterator()) {
                        findConfigItemValue("fsm", fsm_elem.key, item_name, config_item_info, \level, \is_set);
                        if (value_is_set == is_set && level == "global") {
                            idh{elem.key} = True;
                            updateUnconfiguredAlert(item_name, elem.value, interface_type, elem.key, is_set, NOTHING, fsm_elem.value);
                        } else {
                            # check pipelines
                            foreach hash<auto> pipe_info in (fsm_elem.value.lib.pipelines) {
                                *hash<auto> pipeline_config = lookupPipeline(pipe_info.name);
                                if (!pipeline_config) {
                                    olog(LoggerLevel::INFO, "metadata error: data pipeline %y for Finite State Machine %y does not exist", pipe_info.name, fsm_elem.key);
                                    continue;
                                }
                                if (!pipeline_config.config{item_name}) {
                                    continue;
                                }
                                findConfigItemValue("pipeline", pipe_info.name, item_name, config_item_info, \level, \is_set);
                                if (value_is_set == is_set && level == "global") {
                                    idh{elem.key} = True;
                                    updateUnconfiguredAlert(item_name, elem.value, interface_type, elem.key, is_set, NOTHING, fsm_elem.value, pipeline_config);
                                }
                            }
                        }
                    }
                }
            }

            startOrStopInterfaces(idh, interface_type, value_is_set, "global config item " + item_name);
        };

        check_interfaces("service", interfaces);
        check_interfaces("job", interfaces);

        foreach hash<auto> elem in (interfaces{"step"}.pairIterator()) {
            check_interfaces("workflow", {"workflow": getWorkflowsFromStep(elem.key)}, elem.key);
        }
    }

    /* Checks if steps of the given workflow have all config items configured - if not raise an alert
        @param workflow with stepinfo hash containing step information including config items

        @return True if the given workflow is properly configured otherwise False
     */
    bool checkIfWorkflowIsConfigured(hash<auto> workflow) {
%ifdef QorusDebugConfigItems
        QDBG_LOG("QMM::checkIfWorkflowIsConfigured(): check workflow: %y", workflow);
%endif
        bool configured = True;

        hash<auto> alert_info = workflow{"name", "version"};

        *string level;
        bool is_set;
        foreach hash<auto> step in (workflow{"stepinfo"}) {
%ifdef QorusDebugConfigItems
            QDBG_LOG("QMM::checkIfWorkflowIsConfigured(): check step: %y", step);
%endif
            foreach string item_name in (keys step{"config"}) {
                findConfigItemValue("step", step{"stepid"}, item_name, step{"config"}{item_name}, \level, \is_set);
                hash<auto> info = alert_info + {
                    "config": step{"config"}{item_name}.("type", "desc", "strictly_local", "default_value", "prefix") + {
                        "name": item_name
                    }
                };
                updateUnconfiguredAlert(item_name, workflow, "workflow", workflow{"workflowid"}, is_set, info);

                if (configured && !is_set) {
                    configured = False;
                    QDBG_LOG("workflow %s v%s (%d): step %s v%s (%d) config item %y is not configured", workflow.name, workflow.version, workflow.workflowid, step.name, step.version, step.stepid, item_name);
                }
            }

            # check all FSMs
            foreach hash<auto> fsm_info in (step.lib.fsm) {
                bool fsm_configured = checkFsmConfiguredForInterface("workflow", workflow, workflow.workflowid, alert_info, fsm_info);
                if (configured && !fsm_configured) {
                    configured = False;
                    QDBG_LOG("workflow %s v%s (%d): step %s v%s (%d) FSM %y is not configured", workflow.name, workflow.version, workflow.workflowid, step.name, step.version, step.stepid, fsm_info.name);
                }
            }
        }

%ifdef QorusDebugConfigItems
        QDBG_LOG("QMM::checkIfWorkflowIsConfigured(): workflow configured: %y", configured);
%endif
        return configured;
    }

    private bool checkFsmConfiguredForInterface(string ix_type, hash<auto> ix_info, auto ix_id, hash<auto> alert_info, hash<auto> fsm_info) {
        *hash<auto> fsm_config = lookupFsm(fsm_info.name);
        if (!fsm_config) {
            olog(LoggerLevel::INFO, "metadata error: Finite State Machine %y does not exist", fsm_info.name);
            return True;
        }
        bool configured = True;
        foreach hash<auto> item in (fsm_config.config.pairIterator()) {
            hash<auto> info = alert_info + {
                "config": item{"type", "desc", "strictly_local", "default_value", "prefix"},
            } + {
                "name": item.key,
            };
            *string level;
            bool is_set;
            findConfigItemValue("fsm", fsm_info.name, item.key, item.value, \level, \is_set);
            updateUnconfiguredAlert(item.key, ix_info, ix_type, ix_id, is_set, info);
            if (configured && !is_set) {
                configured = False;
                QDBG_LOG("FSM %y for %s %s v%s (%d): item %y is not configured", fsm_info.name, ix_type, ix_info.name, ix_info.version, ix_id, item.key);
            } else {
                # check pipelines in FSM lib
                foreach hash<auto> pipe_info in (fsm_config.lib.pipelines) {
                    if (!checkPipelineConfiguredForInterface(ix_type, ix_info, ix_id, alert_info, pipe_info.name)) {
                        configured = False;
                        QDBG_LOG("pipeline %y for FSM %y for %s %s v%s (%d): item %y is not configured", pipe_info.name, fsm_info.name, ix_type, ix_info.name, ix_info.version, ix_id, item.key);
                    }
                }
            }
        }

        # check all FSMs
        foreach hash<auto> sub_fsm_info in (fsm_info.lib.fsm) {
            bool fsm_configured = checkFsmConfiguredForInterface(ix_type, ix_info, ix_id, alert_info, sub_fsm_info);
            if (configured && !fsm_configured) {
                configured = False;
            }
        }

        return configured;
    }

    private bool checkPipelineConfiguredForInterface(string ix_type, hash<auto> ix_info, auto ix_id, hash<auto> alert_info, string pipeline_name) {
        *hash<auto> pipeline_config = lookupPipeline(pipeline_name);
        if (!pipeline_config) {
            olog(LoggerLevel::INFO, "metadata error: data pipeline %y does not exist", pipeline_name);
            return True;
        }
        bool configured = True;
        foreach hash<auto> item in (pipeline_config.config.pairIterator()) {
            hash<auto> info = alert_info + {
                "config": item{"type", "desc", "strictly_local", "default_value", "prefix"},
            } + {
                "name": item.key,
            };
            *string level;
            bool is_set;
            findConfigItemValue("pipeline", pipeline_name, item.key, item.value, \level, \is_set);
            updateUnconfiguredAlert(item.key, ix_info, ix_type, ix_id, is_set, info);
            if (configured && !is_set) {
                configured = False;
                QDBG_LOG("pipeline %y for %s %s v%s (%d): item %y is not configured", pipeline_name, ix_type, ix_info.name, ix_info.version, ix_id, item.key);
            }
        }

        return configured;
    }

    # checks if the given config item is set in all steps of the given workflow
    # also tries to start the given workflow
    private:internal checkIfWorkflowIsConfigured(string item_name, hash<auto> config_item_info, hash<auto> interface,
                                                 softint workflow_id, bool now_set) {
        hash<auto> interfaces = getStepsForConfigItem(item_name, workflow_id, config_item_info{"strictly_local"});

        # was a change made?
        bool change = True;
        foreach hash<auto> elem in (interfaces{"step"}.pairIterator()) {
            *string level;
            bool is_set;
            findConfigItemValue("step", elem.key, item_name, config_item_info, \level, \is_set);
            updateUnconfiguredAlert(item_name, interface, "workflow", workflow_id, is_set);
            # if there is one config item that has a different value than the change we made, then we have no change
            if (change && is_set != now_set) {
                change = False;
            }

            *hash<auto> fsm_info = getFsmsForConfigItem(item_name, elem.value);
            foreach hash<auto> fsm_elem in (fsm_info.fsm.pairIterator()) {
                findConfigItemValue("fsm", fsm_elem.key, item_name, config_item_info, \level, \is_set);
                updateUnconfiguredAlert(item_name, interface, "workflow", workflow_id, is_set, NOTHING, fsm_elem.value);
                # if there is one config item that has a different value than the change we made, then we have no change
                if (change && is_set != now_set) {
                    change = False;
                }

                # check pipelines in FSM lib
                foreach hash<auto> pipe_info in (fsm_elem.value.lib.pipelines) {
                    *hash<auto> pipeline_config = lookupPipeline(pipe_info.name);
                    if (!pipeline_config) {
                        olog(LoggerLevel::INFO, "metadata error: data pipeline %y for Finite State Machine %y does not exist", pipe_info.name, fsm_elem.key);
                        continue;
                    }
                    if (!pipeline_config.config{item_name}) {
                        continue;
                    }

                    findConfigItemValue("pipeline", pipe_info.name, item_name, config_item_info, \level, \is_set);
                    updateUnconfiguredAlert(item_name, interface, "workflow", workflow_id, is_set, NOTHING, fsm_elem.value, pipeline_config);
                    # if there is one config item that has a different value than the change we made, then we have no change
                    if (change && is_set != now_set) {
                        change = False;
                    }
                }
            }
        }

        if (change) {
            string id = workflow_id.toString();
            # ensure atomicity of a potential workflow stop
            AtomicWorkflowActionHelper atomic_action_helper(id);
            if (now_set) {
                atomic_action_helper.doBackgroundWorkflows(id, \Qorus.rbac.autoStartWorkflows(), tld.cx, "set value for",
                    "unconfigured", "config item " + item_name, {workflow_id: True}, atomic_action_helper);
            } else {
                atomic_action_helper.doBackgroundWorkflows(id, \Qorus.rbac.stopWorkflows(), "deleted value for", "configured",
                    "config item " + item_name, {workflow_id: True}, atomic_action_helper);
            }
        }
    }

    # sends config item changed event on global level (cannot be used for other levels) and
    # also sends config item changed event for all interfaces that require it
    # level_filter used to filter only values on relevant levels
    # and checks if interface is configured (in case value has been set or unset)
    private:internal configItemChangedOnGlobalLevel(string item_name, hash<auto> config_item_info, auto value,
                                                    hash level_filter, bool was_set, bool is_set) {
        postConfigItemChanged(config_item_info, NOTHING, "global", NOTHING, item_name, value, is_set);
        postConfigItemChangedForAllInterfaces(item_name, config_item_info, level_filter, was_set);
    }

    # sends config item changed event on workflow level (cannot be used for other levels) and
    # also sends config item changed event for all interfaces that require it
    # level_filter used to filter only values on relevant levels
    # and checks if interface is configured (in case value has been set or unset)
    private:internal configItemChangedOnWorkflowLevel(*hash<auto> interface, auto interface_id,
                                                      string item_name, hash<auto> config_item_info, auto value,
                                                      hash level_filter, bool was_set, bool is_set) {
        postConfigItemChanged(config_item_info, interface, "workflow", interface_id, item_name, value, is_set);
        postConfigItemChangedForAllInterfaces(item_name, config_item_info, level_filter, was_set, interface_id);
    }

    private:internal *hash<auto> getWorkflowsFromStep(softint stepid) {
        *hash workflows;
        {
            ReadLockHelper rlh(map_mutex);
            workflows = map ({$1.workflowid: {"id": $1.workflowid, "name": $1.name, "version": $1.version}}),
                            omqmap.wfmap.iterator(), $1.stepmap{stepid};
        }
        return workflows;
    }

    # sends config item changed event on these levels: step, service, job
    private:internal configItemChangedOnLowestLevel(*hash<auto> interface, string interface_type,
                                                    auto interface_id, string item_name, hash config_item_info,
                                                    auto value, bool was_set) {
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }
%ifdef QorusDebugConfigItems
        QDBG_LOG("QMM::configItemChangedOnLowestLevel: interface: %y type: %y id: %y item: %y cfg_info: %y value: %y was_set: %y", interface, interface_type, interface_id, item_name, config_item_info, value, was_set);
%endif
        QDBG_ASSERT(interface_type == "step" || interface_type == "job" || interface_type == "service" || interface_type == "fsm" || interface_type == "pipeline");

        *string level;

        if (interface_type == "step") {
            *hash<auto> workflows = getWorkflowsFromStep(interface_id);
            if (!workflows) {
                return;
            }
            # hash of workflows with potential changes
            hash<string, bool> idh;
            # send event for each workflow containing the step for which the value has been changed
            foreach auto workflow in (workflows.iterator()) {
                bool is_set;
                auto current_value = findConfigItemValue(interface_type, interface_id, item_name, config_item_info,
                    \level, \is_set, workflow.id);
                postConfigItemChanged(config_item_info, interface, interface_type, interface_id, item_name, current_value, is_set,
                                    level, workflow.id);

                # update not configured alert only in case the value of the config item has been set/unset
                if (was_set != is_set) {
                    updateUnconfiguredAlert(item_name, workflow, "workflow", workflow.id, is_set);
                    idh{workflow.id} = True;
                }
            }
            startOrStopInterfaces(idh, "workflow", !was_set, "config item " + item_name);
        } else {
            bool is_set;
            auto current_value = findConfigItemValue(interface_type, interface_id, item_name, config_item_info,
                                                     \level, \is_set);
            postConfigItemChanged(config_item_info, interface, interface_type, interface_id, item_name, current_value, is_set, level);

            # update not configured alert only in case the value of the config item has been set/unset
            if (was_set != is_set) {
%ifdef QorusDebugConfigItems
                QDBG_LOG("QMM::configItemChangedOnLowestLevel: update not configured alerts for %y (%y), config item: %y", interface_type, interface_id, item_name);
%endif
                if (interface_type == "fsm") {
                    if (!interface) {
                        interface = lookupFsm(interface_id);
                        if (!interface) {
                            olog(LoggerLevel::INFO, "metadata error: Finite State Machine %y does not exist", interface_id);
                            return;
                        }
                    }
                    *list<hash<auto>> ix_list = getInterfacesForFsm(interface);
                    string desc = sprintf("config item %y in dependent Finite State Machine %y", item_name, interface_id);
                    # hash of interfaces with potential changes; type -> ID -> True
                    hash<string, hash<string, bool>> idh;
                    foreach hash<auto> i in (ix_list) {
                        QDBG_LOG("QorusMapManager::configItemChangedOnLowestLevel() FSM %y item %y set: %y ix: %y", interface_id, item_name, is_set, i + {"interface": i.interface{"name", "version"}});
                        updateUnconfiguredAlert(item_name, i.interface, i.interface_type, i.interface_id, is_set, NOTHING, interface);
                        idh{i.interface_type}{i.interface_id} = True;
                    }
                    QDBG_LOG("QorusMapManager::configItemChangedOnLowestLevel() idh: %y", idh);
                    map startOrStopInterfaces($1.value, $1.key, !was_set, "config item " + item_name), idh.pairIterator();
                } else if (interface_type == "pipeline") {
                    if (!interface) {
                        interface = lookupPipeline(interface_id);
                        if (!interface) {
                            olog(LoggerLevel::INFO, "metadata error: data pipeline %y does not exist", interface_id);
                            return;
                        }
                    }
                    *list<hash<auto>> ix_list = getInterfacesForPipeline(interface);
                    string desc = sprintf("config item %y in dependent data pipeline %y", item_name, interface_id);
                    # hash of interfaces with potential changes; type -> ID -> True
                    hash<string, hash<string, bool>> idh;
                    foreach hash<auto> i in (ix_list) {
                        QDBG_LOG("QorusMapManager::configItemChangedOnLowestLevel() pipeline %y item %y set: %y ix: %y", interface_id, item_name, is_set, i + {"interface": i.interface{"name", "version"}});
                        updateUnconfiguredAlert(item_name, i.interface, i.interface_type, i.interface_id, is_set, NOTHING, NOTHING, interface);
                        idh{i.interface_type}{i.interface_id} = True;
                    }
                    QDBG_LOG("QorusMapManager::configItemChangedOnLowestLevel() idh: %y", idh);
                    map startOrStopInterfaces($1.value, $1.key, !was_set, "config item " + item_name), idh.pairIterator();
                } else {
                    updateUnconfiguredAlert(item_name, interface, interface_type, interface_id, is_set);
                    startOrStopInterfaces({interface_id: True}, interface_type, !was_set, "config item " + item_name);
                }
            }
        }
    }

    #! Returns a list if interface hashes for interfaces that depend on the given FSM
    /** @param fsm a hash of information about the FSM

        @return a list of interface hashes with the following keys:
        - \c interface: a hash describing the interface
        - \c interface_type: a string giving the interface type: job, service, or workflow
        - \c interface_id: the interface ID
    */
    *list<hash<auto>> getInterfacesForFsm(hash<auto> fsm) {
        # get FSMs that depend on this FSM
        *hash<string, bool> fsm_deps = {
            fsm.name: True,
        } + fsm.fsm_rdeps;

        return getInterfacesForFsmIntern(fsm_deps);
    }

    #! Returns a list if interface hashes for interfaces that depend on the given FSMs
    /** @param fsm_deps a hash of FSM names with fully-resolved dependencies

        @return a list of interface hashes with the following keys:
        - \c interface: a hash describing the interface
        - \c interface_type: a string giving the interface type: job, service, or workflow
        - \c interface_id: the interface ID
    */
    private:internal *list<hash<auto>> getInterfacesForFsmIntern(hash<string, bool> fsm_deps) {
        # type -> ID -> true
        hash<string, hash<string, hash<auto>>> ix_map;
        # check workflows
        {
            ReadLockHelper rlh(map_mutex);
            foreach hash<auto> ix_info in (omqmap.wfmap.iterator()) {
                map ix_map.workflow{ix_info.workflowid} = ix_info, ix_info.lib.fsm, fsm_deps{$1.name};
            }
        }
        # check services
        {
            ReadLockHelper rlh(map_mutex);
            foreach hash<auto> ix_info in (omqmap.servicemap.iterator()) {
                map ix_map.service{ix_info.serviceid} = ix_info, ix_info.lib.fsm, fsm_deps{$1.name};
            }
        }
        # check jobs
        {
            ReadLockHelper rlh(map_mutex);
            foreach hash<auto> ix_info in (omqmap.jmap.iterator()) {
                map ix_map.job{ix_info.jobid} = ix_info, ix_info.lib.fsm, fsm_deps{$1.name};
            }
        }

        list<hash<auto>> rv;
        foreach hash<auto> i in (ix_map.pairIterator()) {
            map rv += {
                "interface": $1.value,
                "interface_type": i.key,
                "interface_id": $1.key,
            }, i.value.pairIterator();
        }
        return rv;
    }

    #! Returns a list if interface hashes for interfaces that depend on the given data pipeline
    /** @return a list of interface hashes with the following keys:
        - \c interface: a hash describing the interface
        - \c interface_type: a string giving the interface type: job, service, or workflow
        - \c interface_id: the interface ID
    */
    *list<hash<auto>> getInterfacesForPipeline(hash<auto> pipeline) {
        # first get affected FSMs
        hash<string, bool> fsm_deps;

        # check fsms
        {
            ReadLockHelper rlh(map_mutex);
            foreach hash<auto> fsm_info in (omqmap.fsm.iterator()) {
                foreach hash<auto> pipe_info in (fsm_info.lib.pipelines) {
                    if (pipeline.name == pipe_info.name) {
                        fsm_deps{fsm_info.name} = True;
                        fsm_deps += fsm_info.fsm_rdeps;
                    }
                }
            }
        }

        if (!fsm_deps) {
            return;
        }

        return getInterfacesForFsmIntern(fsm_deps);
    }

    /* Updates config item value for a given config item name on interface level
        @param interface_type one of the following strings: job, service, step, workflow
        @param interface_id interface id
        @param item_name name of the config item to be updated
        @param value value to be set for the config item
        @param updated output value determines if config item was updated
        @throws CONFIG-ITEM-ERROR
        @return updated config item value
     */
    auto updateConfigItemValueOnInterfaceLevel(string interface_type, auto interface_id, string item_name,
                                               auto value, *reference<bool> updated) {
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }
        string level = getInterfaceLevel(interface_type, interface_id);
        *hash interface = lookupInterface(interface_type, interface_id);

        hash item = checkIfConfigItemExists(interface, interface_type, interface_id, item_name);
        checkIfValueIsAllowed(item_name, item, value);

        auto new_value = getConfigItemNewValue(item_name, item.type, value, item.hasKey("allowed_values"));
        updated = updateConfigItemValue(level, item_name, new_value);
        if (updated) {
            if (interface_type == "workflow") {
                configItemChangedOnWorkflowLevel(interface, interface_id, item_name, item, value, {level: True}, True, True);
            } else {
                configItemChangedOnLowestLevel(interface, interface_type, interface_id, item_name, item, new_value, True);
            }
        }

        return new_value;
    }

    /* Updates config item value for a given config item name on global level
        @param item_name name of the config item to be updated
        @param value value to be set for the config item
        @param updated output value determines if config item was updated
        @throws CONFIG-ITEM-ERROR
        @return updated config item value
     */
    auto updateConfigItemValueOnGlobalLevel(string item_name, auto value, *reference<bool> updated) {
        hash item = getConfigItem(item_name);
        checkIfValueIsAllowed(item_name, item, value);

        auto new_value = getConfigItemNewValue(item_name, item.type, value, item.hasKey("allowed_values"));
        updated = updateConfigItemValue("global", item_name, new_value);
        if (updated) {
            configItemChangedOnGlobalLevel(item_name, item, new_value, {"global": True}, True, True);
        }
        return new_value;
    }

    /* Deletes config item value for a given config item name on interface level. Checks if interface is configured.
        @param interface_type one of the following strings: job, service, step, workflow
        @param interface_id interface id
        @param item_name name of the config item to be deleted
        @param deleted output value determines if config item value was deleted
        @throws CONFIG-ITEM-ERROR
        @return deleted config item value
     */
    auto deleteConfigItemValueOnInterfaceLevel(string interface_type, auto interface_id, string item_name,
                                               *reference<bool> deleted) {
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }
        string level = getInterfaceLevel(interface_type, interface_id);
        *hash interface = lookupInterface(interface_type, interface_id);

        hash item = checkIfConfigItemExists(interface, interface_type, interface_id, item_name);

        auto value = deleteConfigItemValue(level, item_name, \deleted);

        # unconfigured interface IDs to potentially stop
        if (deleted) {
            if (interface_type == "workflow") {
                configItemChangedOnWorkflowLevel(interface, interface_id, item_name, item, NOTHING,
                                                 {"global": True, "default": True}, True, False);
                checkIfWorkflowIsConfigured(item_name, item, interface, interface_id, False);
            } else {
                configItemChangedOnLowestLevel(interface, interface_type, interface_id, item_name, item, NOTHING,
                                               True);
            }
        }

        return value;
    }

    /* Deletes config item value for a given config item name on global level
        @param item_name name of the config item to be deleted
        @param deleted output value determines if config item value was deleted
        @throws CONFIG-ITEM-ERROR
        @return deleted config item value
     */
    auto deleteConfigItemValueOnGlobalLevel(string item_name, *reference<bool> deleted) {
        hash item = getConfigItem(item_name);

        auto value = deleteConfigItemValue("global", item_name, \deleted);
        if (deleted) {
            configItemChangedOnGlobalLevel(item_name, item, NOTHING, {"default": True}, True, False);
            checkIfInterfacesAreConfiguredFromGlobalChange(item_name, item, False);
        }
        return value;
    }

    /* Inserts new config item value value for a given config item on interface level
        @param interface_type one of the following strings: job, service, step, workflow
        @param interface_id interface id
        @param item_name name of the config item to be inserted
        @param value value to be inserted
        @param inserted output value determines if config item value was deleted
        @throws CONFIG-ITEM-ERROR
        @return deleted config item value
     */
    auto insertConfigItemValueOnInterfaceLevel(string interface_type, auto interface_id, string item_name,
                                               auto value, *reference<bool> inserted) {
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }
        string level = getInterfaceLevel(interface_type, interface_id);
        *hash interface = lookupInterface(interface_type, interface_id);

        hash item = checkIfConfigItemExists(interface, interface_type, interface_id, item_name);
        checkIfValueIsAllowed(item_name, item, value);

        auto new_value = getConfigItemNewValue(item_name, item.type, value, item.hasKey("allowed_values"));
        inserted = insertConfigItemValue(level, item_name, new_value);
        if (inserted) {
            if (interface_type == "workflow") {
                configItemChangedOnWorkflowLevel(interface, interface_id, item_name, item, value, {level: True}, False, True);
                checkIfWorkflowIsConfigured(item_name, item, interface, interface_id, True);
            } else {
%ifdef QorusDebugConfigItems
                QDBG_LOG("QMM::insertConfigItemValueOnInterfaceLevel: interface_type: %y, id: %y, item: %y, value: %y", interface_type, interface_id, item_name, value);
%endif
                configItemChangedOnLowestLevel(interface, interface_type, interface_id, item_name, item, new_value,
                    False);
            }
        }

        return new_value;
    }

    /* Inserts new config item value for a given config item name on global level
        @param item_name name of the config item to be inserted
        @param value value to be inserted
        @param inserted output value determines if config item value was deleted
        @throws CONFIG-ITEM-ERROR if config item is not defined by any interface
        @return deleted config item value
     */
    auto insertConfigItemValueOnGlobalLevel(string item_name, auto value, *reference<bool> inserted) {
        hash item = getConfigItem(item_name);
        checkIfValueIsAllowed(item_name, item, value);

        auto new_value = getConfigItemNewValue(item_name, item.type, value, item.hasKey("allowed_values"));
        inserted = insertConfigItemValue("global", item_name, new_value);
        if (inserted) {
            configItemChangedOnGlobalLevel(item_name, item, new_value, {"global": True}, False, True);
            checkIfInterfacesAreConfiguredFromGlobalChange(item_name, item, True);
        }
        return new_value;
    }

    /* Sets new config item value for a given config item name on interface level
        @param interface_type one of the following strings: job, service, step, workflow
        @param interface_id interface id
        @param item_name name of the config item to be set
        @param value value to be inserted
        @throws CONFIG-ITEM-ERROR if config item is not defined by the given interface
        @return hash containing new config item value and updated/inserted or deleted flag
     */
    hash setConfigItemValueOnInterfaceLevel(string interface_type, auto interface_id, string item_name,
                                            auto new_value, bool restrict_update = False) {
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }
        hash result;

        bool is_set = False;
        auto value = getConfigItemValue(interface_type, interface_id, item_name, \is_set);
        if (is_set) {
            if (restrict_update) {
                throw "CONFIG-ITEM-ERROR",
                    sprintf("value for %s configuration item on the %s:%s level has already been created, use PUT"
                            " method to change the value: %y", item_name, interface_type, interface_id, value);
            }

            bool updated;
            auto updated_value = updateConfigItemValueOnInterfaceLevel(interface_type, interface_id, item_name,
                                                                       new_value, \updated);
            result += {
                "updated": updated,
                "value": updated_value
            };
        } else {
            bool inserted;
            auto inserted_value = insertConfigItemValueOnInterfaceLevel(interface_type, interface_id, item_name,
                                                                        new_value, \inserted);
            result += {
                "inserted": inserted,
                "value": inserted_value
            };
        }
        return result;
    }

     /* Sets new config item value for a given config item name on global level
        @param item_name name of the config item to be set
        @param value value to be set
        @throws CONFIG-ITEM-ERROR if config item is not defined by any interface
        @return hash containing new config item value and updated/inserted or deleted flag
     */
    hash setConfigItemValueOnGlobalLevel(string item_name, auto new_value, bool restrict_update = False) {
        hash result;

        bool is_set = False;
        auto value = getConfigItemValue("global", item_name, \is_set);
        if (is_set) {
            if (restrict_update) {
                throw "CONFIG-ITEM-ERROR", sprintf("value for %s configuration item on the global level has already"
                    " been created, use PUT method to change the value: %y", item_name,value);
            }

            bool updated;
            auto updated_value = updateConfigItemValueOnGlobalLevel(item_name, new_value, \updated);
            result += {
                "updated": updated,
                "value": updated_value
            };
        } else {
            bool inserted;
            auto inserted_value = insertConfigItemValueOnGlobalLevel(item_name, new_value, \inserted);
            result += {
                "inserted": inserted,
                "value": inserted_value
            };
        }
        return result;
    }

    /* Deletes the given config item values.
        @param config_item_values list of the config item values
        @param results: list of hashes, where each hash has the following keys:
            - \c deleted: @ref True if value has been deleted otherwise @ref False
            - \c value: deleted value
    */
    list deleteConfigItemValues(list config_item_values) {
        list result;
        foreach hash config_item_value in (config_item_values) {
            *bool deleted;
            auto value = deleteConfigItemValue(config_item_value{"level"},
                                               config_item_value{"prefix"} + config_item_value{"name"}, deleted);
            result += {"value": value, "deleted": deleted};
        }
        return result;
    }

    /* Imports the given config item values.
        @param config_item_values list of the config item values
        @param results: list of hashes, where each hash has the following keys:
            - \c updated: @ref True or @ref False (in case value was set before)
            - \c inserted: @ref True or @ref False (in case value was not set before)
            - \c value: new value
    */
    list<hash<auto>> importConfigItemValues(list config_item_values) {
        list<hash<auto>> result;
        foreach hash<auto> config_item_value in (config_item_values) {
%ifdef QorusDebugConfigItems
            QDBG_LOG("QMM::importConfigItemValues: %N", config_item_value);
%endif
            hash<auto> sub_result;

            string name_with_prefix = config_item_value{"prefix"} + config_item_value{"name"};
            if (config_item_value{"interface-type"} != "global") {
                auto id = rLookupInterface(config_item_value{"interface-type"}, config_item_value{"interface-name"},
                                               config_item_value{"interface-version"});

                if (!exists id) {
                    olog(LoggerLevel::INFO, "interface cannot be found: %y; config item is ignored",
                         config_item_value);
                    continue;
                }

                sub_result = setConfigItemValueOnInterfaceLevel(config_item_value{"interface-type"}, id,
                                                                name_with_prefix,
                                                                config_item_value{"value"});
%ifdef QorusDebugConfigItems
                QDBG_LOG("QMM::importConfigItemValues: sub_result: %y", sub_result);
%endif
            } else if (config_item_value{"interface-type"} == "global") {
                sub_result = setConfigItemValueOnGlobalLevel(name_with_prefix, config_item_value{"value"});
%ifdef QorusDebugConfigItems
                QDBG_LOG("QMM::importConfigItemValues: sub_result: %y", sub_result);
%endif
            }
            result += config_item_value + sub_result;
        }
        return result;
    }

    /* Returns value for a given config item
        @param interface_type string one of the following strings: job, service, step, workflow, global
        @param interface_id interface id, in case interface type is global must be NOTHING
        @param name config item name
        @param is_set if True value is set (the value maybe NOTHING) otherwise value is not set and the
        return value is NOTHING

        @return config item value or NOTHING in case config item value is not defined for the given level
     */
    auto getConfigItemValue(string interface_type, auto interface_id, string name, reference<bool> is_set) {
        string level = getInterfaceLevel(interface_type, interface_id);
        return getConfigItemValue(level, name, \is_set);
    }

    /* Returns value for a given config item
        @param level interface level or global
        @param name config item name
        @param is_set if True value is set (the value maybe NOTHING) otherwise value is not set and the
        return value is NOTHING

        @return config item value or NOTHING in case config item value is not defined for the given level
     */
    auto getConfigItemValue(string level, string name, reference<bool> is_set) {
        ReadLockHelper rlh(map_mutex);
        is_set = omqmap.configItemValues.hasKey(name) && omqmap.configItemValues{name}.hasKey(level);
        return omqmap.configItemValues{name}{level};
    }

    /* Finds a value for a given config item (start search for a value from given interface level to global level)
        @param interface_type string one of the following strings: job, service, step, workflow, global
        @param interface_id interface id, in case interface type is global must be NOTHING
        @param name config item name
        @param config_item_info config item info
        @param level output parameter describes on which level the value has been found. One of the following strings:
        interface_level (e.g. step:1, workflow:1, service:1), global or default from config_item_info is returned.
        @param is_set if True value is set (the value maybe NOTHING) otherwise value is not set and the
        return value is NOTHING
        @param workflow_id workflow id, must be passed in case interface type is step otherwise must be NOTHING

        @return config item value or NOTHING in case config item value is not defined for the given level

        @throws CONFIG-ITEM-ERROR
     */
    auto findConfigItemValue(string interface_type, auto interface_id, string name, hash<auto> config_item_info,
                             reference<*string> level, reference<bool> is_set, *int workflow_id) {
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }
        while (True) {
            level = getInterfaceLevel(interface_type, interface_id);
            auto value = getConfigItemValue(level, name, \is_set);
            if (is_set) {
%ifdef QorusDebugConfigItems
                QDBG_LOG("QMM::findConfigItemValue: value: %y found on: %y (is_set: True)", value, level);
%endif
                return value;
            } else if (config_item_info.strictly_local) {
                is_set = config_item_info.hasKey("default_value");
                level = is_set ? "default" : NOTHING;
%ifdef QorusDebugConfigItems
                QDBG_LOG("QMM::findConfigItemValue: item %y is strictly local with default: %y (is_set: %y)", config_item_info, config_item_info.default_value, is_set);
%endif
                return config_item_info.default_value;
            }

            switch (interface_type) {
                # next check the workflow level
                case "step":
                    interface_type = "workflow";
                    interface_id = workflow_id;
                    break;

                # next check the global level
                case "workflow":
                case "service":
                case "job":
                case "fsm":
                case "pipeline":
                    interface_type = "global";
                    interface_id = NOTHING;
                    break;

                case "global":
                    is_set = config_item_info.hasKey("default_value");
                    level = is_set ? "default" : NOTHING;
%ifdef QorusDebugConfigItems
                    QDBG_LOG("QMM::findConfigItemValue: item %y is global with default: %y (is_set: %y)", config_item_info, config_item_info.default_value, is_set);
%endif
                    return config_item_info.default_value;

                default:
                    throw "CONFIG-ITEM-ERROR", sprintf("unkown interface type: %y", interface_type);
            }
        }
    }

    /* Fills config item values for given config items
        @param interface_type string one of the following strings: job, service, step, workflow, global
        @param interface_id interface id, in case interface type is global must be NOTHING
        @param inout used as input (config items should be in config key) and output config items with values and
        levels and global_config hash will be added containing global config item values and eventually workflow_config
        @param workflow_id workflow id, fill only in case interface type is step otherwise must be NOTHING
        @throws CONFIG-ITEM-ERROR
     */
    fillConfigItemValues(string interface_type, auto interface_id, reference<hash> inout,
                         *int workflow_id) {
%ifdef QorusDebugConfigItems
        QDBG_LOG("QMM::fillConfigItemValues: config item values: %y", getConfigItemValues());
%endif
        if (interface_type != "fsm" && interface_type != "pipeline" && exists interface_id) {
            interface_id = interface_id.toInt();
        }

        foreach hash<auto> iterator in (inout.config.pairIterator()) {
            *string level;
%ifdef QorusDebugConfigItems
            QDBG_LOG("QMM::fillConfigItemValues: find value for %y configuration item: %y", iterator.key, iterator.value);
%endif
            bool is_set = False;
            auto value = findConfigItemValue(interface_type, interface_id, iterator.key, iterator.value, \level,
                                             \is_set, workflow_id);
            inout.config{iterator.key} += {
                "value": value,
                "level": level,
                "is_set": is_set,
                "is_templated_string": UserApi::isSingleTemplatedString(value),
            };
            on_exit {
                if (iterator.value.type == "any") {
                    # get type
                    string type = inout.config{iterator.key}.value.type();
                    # return type, mapped if a mapping is available
                    inout.config{iterator.key}.currentType = ConfigItemTypeMap.hasKey(type) ? ConfigItemTypeMap{type} : type;
                }
            }
%ifdef QorusDebugConfigItems
            QDBG_LOG("QMM::fillConfigItemValues: value=%y for %y configuration item found on %s level", value, iterator.key, level);
%endif
            if (iterator.value.strictly_local) {
                continue;
            }

            auto global_value = getConfigItemValue("global", iterator.key, \is_set);

            hash<auto> global_config_info = {"value": global_value, "type": iterator.value.type, "is_set": is_set,
                "is_templated_string": UserApi::isSingleTemplatedString(global_value),
            };
            if (iterator.value.hasKey("allowed_values")) {
                global_config_info += {"allowed_values": iterator.value{"allowed_values"}};
            }

            inout.global_config += {iterator.key: global_config_info + {"prefix": iterator.value.prefix}};

            if (exists workflow_id) {
                auto workflow_value = getConfigItemValue("workflow", workflow_id, iterator.key, \is_set);

                hash<auto> wf_config_info = {"value": workflow_value, "type": iterator.value.type, "is_set": is_set,
                    "is_templated_string": UserApi::isSingleTemplatedString(workflow_value),
                };
                if (iterator.value.hasKey("allowed_values")) {
                    wf_config_info += {"allowed_values": iterator.value{"allowed_values"}};
                }

                inout.workflow_config += {iterator.key: wf_config_info + {"prefix": iterator.value.prefix}};
            }
        }
    }

    /* Finds config item value on interface level
        @return hash containing the following keys: name, value and type.
     */
    *hash<auto> findConfigItemValueOnGlobalLevel(string name) {
        *hash<auto> item = getConfigItem(name, False, True);
        if (!exists item) {
            return NOTHING;
        }

        bool is_set = False;
        auto value = getConfigItemValue("global", name, \is_set);
        hash<auto> result = {"value": value, "type": item.type, "is_set": is_set,
            "is_templated_string": UserApi::isSingleTemplatedString(value),
        };
        if (item.hasKey("allowed_values")) {
            result += {"allowed_values": item{"allowed_values"}};
        }
        return result;
    }

    /* Finds all config item values on global level
        @return list where each value is a hash containing name, value and type of the config item
     */
    list<hash<auto>> findAllConfigItemValuesOnGlobalLevel() {
        list<hash<auto>> result = ();
        hash<auto> config_items = getNonStrictlyLocalConfigItems();

        bool is_set = False;
        foreach auto iterator in (config_items.pairIterator()) {
            auto value = getConfigItemValue("global", iterator.key, \is_set);

            string name = iterator.key;
            if (iterator.prefix) {
                QDBG_ASSERT(name.equalPartial(iterator.prefix));
                splice name, 0, iterator.prefix.length();
            }
            hash<auto> global_config = {
                "name": name,
                "prefix": iterator.prefix,
                "value": value,
                "type": iterator.value.type,
                "is_set": is_set,
                "is_templated_string": UserApi::isSingleTemplatedString(value),
            };
            if (iterator.value.hasKey("allowed_values")) {
                global_config += {"allowed_values": iterator.value{"allowed_values"}};
            }

            result += global_config;
        }
        return result;
    }

    # returns all config items with strictly_local == false
    private:internal hash<auto> getNonStrictlyLocalConfigItems() {
        code get_config_items = hash<auto> sub (*hash<auto> interfaces) {
            hash<auto> result = {};
            foreach auto interface in (interfaces.iterator()) {
                foreach auto iterator in (interface.config.pairIterator()) {
                    if (exists iterator.value && iterator.value.strictly_local == False) {
                        result{iterator.key} = iterator.value;
                    }
                }
            }
            return result;
        };

        return get_config_items(getJobMap())
            + get_config_items(getServiceMap())
            + get_config_items(getStepMap())
            + get_config_items(getFsmMap())
            + get_config_items(getPipelineMap());
    }

    /* Returns config item values
        @return hash of config item values
     */
    *hash<auto> getConfigItemValues() {
        ReadLockHelper rlh(map_mutex);
        return omqmap.configItemValues;
    }

    private:internal string getInterfaceLevel(string interface_type, auto interface_id) {
        return interface_type + (exists interface_id ? ":" + interface_id : "");
    }

    private:internal string getInterfaceDescription(hash<auto> interface, string interface_type,
                                                    auto interface_id) {
        if (interface.name == interface_id) {
            return sprintf("%s %y", interface_type, interface.name);
        }
        return sprintf("%s %s%s (%s)", interface_type, interface.name,
                       interface.version ? sprintf(" v%s", interface.version) : "", interface_id);
    }
}
