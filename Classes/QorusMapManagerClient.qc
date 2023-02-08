# -*- mode: qore; indent-tabs-mode: nil -*-
# @file QorusMapManagerClient.qc provides an API for remote Qorus connections

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args

hashdecl OMQ::ClientMaps {
    # accessed & updated under "loggerMutex"
    bool logger = False;
    # accessed & updated under "wfm"
    bool wf = False;
    # accessed & updated under "libmap_mutex"
    bool libmap = False;
    # accessed & updated under "em"
    bool e = False;
    # accessed & updated under "vsm"
    bool vm = False;
    # accessed & updated under "slam"
    bool sla = False;
    # accessed & updated under "configItemValuesMutex"
    bool configItemValues = False;
}

hashdecl TypeRequestInfo {
    #! Request in progress marker
    bool request = True;

    #! The condition variable to signal waiting threads
    Condition cond;

    #! number of waiting threads on this request
    int waiting;
}

class OMQ::QorusMapManagerClient inherits QorusMapManagerBase, private QorusCoreSubsystemClientBase {
    public {}

    private {
        # Mutex for wfmap data
        Mutex wfm();
        # Mutex for loggermap data
        Mutex loggerMutex();
        # Mutex for steps, functions, constants, classes, queues, mappers, pipelines, and fsms
        /* maps covered by this lock are listed in qorus-shared-system.ql: LibMaps */
        Mutex libmap_mutex();
        # Mutex for events
        Mutex em();
        # Mutex for value maps
        Mutex vsm();
        # Mutex for SLA maps
        Mutex slam();
        # Mutex for global configuration items
        Mutex configItemValuesMutex();

        hash<ClientMaps> cache();

        # map of jobid -> SLA ID
        hash<string, int> sla_rjmap();

        #! Ensures that concurrent requests for the same type block
        /** types are cached on demand; blocks (contention) are made only for a particular type during the request to
            the server

            the type cache RWLock is used for synchronization

            format: path -> TypeRequestInfo
        */
        hash<string, hash<TypeRequestInfo>> type_serialization_map;
    }

    constructor(AbstractQorusClient core) : QorusCoreSubsystemClientBase(core, "qmm") {
        # initialize type cache
        type_cache = DataProvider::getTypeCache();
    }

    /* Finds a value for a given config item (start search for a value from given interface level to global level)
        @param interface_type string one of the following strings: job, service, step, workflow, global
        @param interface_id interface id, in case interface type is global must be NOTHING
        @param name config item name
        @param config_item_info config item info
        @param level output parameter describes on which level the value has been found. One of the following strings:
               interface_level (e.g. step:1, workflow:1, service:1), global or default from config_item_info is returned.
        @param workflow_id workflow id, must be passed in case interface type is step otherwise must be NOTHING
        @return config item value or NOTHING in case config item value is not defined for the given level
        @throws CONFIG-ITEM-ERROR
    */
    auto findConfigItemValue(string interface_type, auto interface_id, string name, hash config_item_info,
                             reference<*string> level, reference<bool> is_set, *int workflow_id) {
        # TODO: after refactoring of the QorusMapManager should be implemented in a new base class at one place
        while (True) {
            auto value = getConfigItemValue(interface_type, interface_id, name, \is_set);
            if (is_set) {
                level = getInterfaceLevel(interface_type, interface_id);
                QDBG_LOG("QMMC::findConfigItemValue: value=%y found on: %y", value, level);
                return value;
            } else if (config_item_info.strictly_local) {
                is_set = config_item_info.hasKey("default_value");
                level = is_set ? "default" : NOTHING;
                QDBG_LOG("QMMC::findConfigItemValue: item %y is strictly local use default: %y", config_item_info, config_item_info.default_value);
                return config_item_info.default_value;
            }
            switch (interface_type) {
                case "step":
                    interface_type = "workflow";
                    interface_id = workflow_id;
                    break;

                case "workflow":
                case "service":
                case "job":
                case "fsm":
                    interface_type = "global";
                    interface_id = NOTHING;
                    break;

                case "global":
                    is_set = config_item_info.hasKey("default_value");
                    level = is_set ? "default" : NOTHING;
                    return config_item_info.default_value;

                default: throw "CONFIG-ITEM-ERROR", sprintf("unkown interface type: %y", interface_type);
            }
        }
    }

    /* Returns value for a given config item
        @param interface_type string one of the following strings: job, service, step, workflow, global
        @param interface_id interface id, in case interface type is global must be NOTHING
        @param name config item name
        @return config item value or NOTHING in case config item value is not defined for the given level
     */
    auto getConfigItemValue(string interface_type, auto interface_id, string name, reference<bool> is_set) {
        # TODO: after refactoring of the QorusMapManager should be implemented in a new base class at one place
        string level = getInterfaceLevel(interface_type, interface_id);
        return getConfigItemValue(level, name, \is_set);
    }

    /* Returns value for a given config item
        @param level interface level or global
        @param name config item name
        @return config item value or NOTHING in case config item value is not defined for the given level
     */
    auto getConfigItemValue(string level, string name, reference<bool> is_set) {
        # TODO: after refactoring of the QorusMapManager should be implemented in a new base class at one place
        auto value;
        {
            AutoLock al(configItemValuesMutex);
            value = omqmap.configItemValues{name}{level};
        }

        is_set = omqmap.configItemValues.hasKey(name) && omqmap.configItemValues{name}.hasKey(level);

        if (!is_set) {
            AutoLock al(configItemValuesMutex);
            checkConfigCacheIntern();
            # get it again after the cache may have been updated
            value = omqmap.configItemValues{name}{level};
            is_set = omqmap.configItemValues.hasKey(name) && omqmap.configItemValues{name}.hasKey(level);
        }
        return value;
    }

    private:internal string getInterfaceLevel(string interface_type, auto interface_id) {
        # TODO: after refactoring of the QorusMapManager should be implemented in a new base class at one place
        return interface_type + (exists interface_id ? ":" + interface_id : "");
    }

    # called from QorusMapManager when config item value has been changed
    configItemValueChanged(string change_type, string name, string level, auto value) {
        on_exit {
            Qorus.configItemValueChanged(change_type, name, level, value);
        }

        if (!cache.configItemValues) {
            return;
        }

        AutoLock al(configItemValuesMutex);
        switch (change_type) {
            case "insert":
            case "update":
                omqmap.configItemValues{name}{level} = value;
                break;
            case "delete":
                remove omqmap.configItemValues{name}{level};
                break;

            default: throw "CONFIG-ITEM-ERROR", sprintf("unkown type of change: %y", change_type);
        }
    }

    /** Return logger found by logger info

        @param interfacetn interface table name (e.g. services/workflows/jobs)
        @param id interface ID

        @return found logger
    */
    *hash<auto> lookupLogger(string type, auto id) {
        QDBG_ASSERT(type);

        # first map ID to an interface configuration
        *hash<auto> ix_info;
        {
            # interface info
            switch (type) {
                case "workflows": ix_info = lookupWorkflow(id); break;
                case "services": ix_info = lookupService(id); break;
                case "jobs": ix_info = lookupJob(id); break;
                default: throw "INVALID-INTERFACE", sprintf("invalid interface %y (ID %d); expected one of "
                    "\"workflows\", \"services\", or \"jobs\"", type, id);
                # qdsp lookups only supported in qorus-core
            }
            if (!ix_info) {
                throw "INVALID-INTERFACE", sprintf("%s: invalid ID %d", type, id);
            }
        }

        *hash<auto> logger;
        {
            # NOTE: no system loggers are looked up here
            logger = ix_info.loggerid
                ? omqmap.loggerMap{ix_info.loggerid}
                : omqmap.loggerMap{omqmap.loggerAliases{type}};

            if (!logger) {
                AutoLock al(loggerMutex);
                checkLoggerCacheIntern();

                # get it again, as the cache may have been updated here or in another thread
                logger = ix_info.loggerid
                    ? omqmap.loggerMap{ix_info.loggerid}
                    : omqmap.loggerMap{omqmap.loggerAliases{type}};
            }
        }

        if (logger) {
            logger.isDefault = !ix_info.loggerid;
        }

        return logger;
    }

    # the verbose arg is ignored in the client
    *hash<auto> lookupJob(softstring id, bool verbose = False) {
        QDBG_ASSERT(!verbose);
        return methodGateArgs("lookupJob", (id, verbose));
    }

    *hash<auto> rLookupJob(string name, bool verbose = True) {
        QDBG_ASSERT(!verbose);
        return methodGateArgs("rLookupJob", (name, verbose));
    }

    *hash<auto> lookupWorkflow(softstring wfid, *softbool verbose) {
        *hash<auto> h = omqmap.wfmap{wfid};
        if (!h) {
            AutoLock al(wfm);
            checkWorkflowCacheIntern();
            # cache may have been updated either above or in another thread
            h = omqmap.wfmap{wfid};
        }

        if (h && verbose)
            getWorkflowStepInfo(\h);
        return h;
    }

    *hash<auto> rLookupWorkflow(string name) {
        *hash<auto> h = omqmap.wfrmap{name};
        if (!h) {
            AutoLock al(wfm);
            checkWorkflowCacheIntern();
            # get it again after the cache may have been updated either above or in another thread
            h = omqmap.wfrmap{name};
        }
        return h;
    }

    *hash<auto> rLookupWorkflow(string name, string version) {
        *hash<auto> h = omqmap.wfrmap{name}{version};
        if (!h) {
            AutoLock al(wfm);
            checkWorkflowCacheIntern();
            # get it again after the cache may have been updated either above or in another thread
            h = omqmap.wfrmap{name}{version};
        }
        return h;
    }

    # returns the value actually set, throws a \c WORKFLOW-OPTION-ERROR exception if there are any errors
    auto updateWorkflowOptionErr(softint wfid, softstring opt, auto val) {
        AutoLock al(wfm);

        checkWorkflowCacheIntern();
        # update option in qorus-core & in DB
        val = methodGateArgs("updateWorkflowOptionErr", (wfid, opt, val));

        # reference to runtime option hash
        reference roh = \omqmap.wfmap{wfid}."runtime-options";

        if (exists val)
            roh{opt} = val;
        else # delete
            remove roh{opt};

        return val;
    }

    # returns the value actually set, throws a \c SERVICE-OPTION-ERROR exception if there are any errors
    *hash<auto> updateServiceOptionsErr(softint svcid, hash<auto> opts) {
        # update option in qorus-core & in DB
        return methodGateArgs("updateServiceOptionsErr", (svcid, opts));
    }

    # returns the value actually set, throws a \c JOB-OPTION-ERROR exception if there are any errors
    auto updateJobOptionsErr(softint jobid, hash<auto> opts) {
        # update option in qorus-core & in DB
        return methodGateArgs("updateJobOptionsErr", (jobid, opts));
    }

    *hash<auto> lookupStep(softstring stepid, *softbool verbose) {
        AutoLock al(libmap_mutex);
        checkLibMapCacheIntern();
        return lookupStepIntern(stepid, verbose);
    }

    *hash<auto> lookupStep(list<auto> l, *softbool verbose) {
        AutoLock al(libmap_mutex);
        checkLibMapCacheIntern();
        # issue #2142: do not include a hash entry for stepids that are not present in the cache
        return map {$1: (verbose ? lookupStepIntern($1, True) : omqmap.stepmap{$1})}, l, omqmap.stepmap{$1};
    }

    *hash<auto> lookupEvent(softstring eid) {
        *hash<auto> e = omqmap.emap{eid};
        if (!e) {
            AutoLock al(em);
            checkEventCacheIntern();
            e = omqmap.emap{eid};
        }
        return e;
    }

    *hash<auto> rLookupEvent(string name) {
        *hash<auto> e = omqmap.ermap{name};
        if (!e) {
            AutoLock al(em);
            checkEventCacheIntern();
            e = omqmap.ermap{name};
        }
        return e;
    }

    *hash<auto> lookupQueue(softstring qid) {
        *hash<auto> q = omqmap.qmap{qid};
        if (!q) {
            AutoLock al(libmap_mutex);
            checkLibMapCacheIntern();
            q = omqmap.qmap{qid};
        }
        return q;
    }

    *hash<auto> lookupClass(softstring cid) {
        return methodGateArgs("lookupClass", cid);
    }

    *hash<auto> rLookupClassInfo(string name, string version) {
        return methodGateArgs("rLookupClassInfo", (name, version));
    }

    softint classId(string name, *string version) {
        return methodGateArgs("classId", (name, version));
    }

    *hash<auto> lookupMapper(softstring mid, *softbool verbose) {
        *hash<auto> h += omqmap.mmap{mid};
        if (!h) {
            AutoLock al(libmap_mutex);
            checkLibMapCacheIntern();
            h = omqmap.mmap{mid};
        }

        if (h && verbose)
            h += {"groups": Qorus.rbac.getMapperGroups(mid)};
        return h;
    }

    *softint rLookupMapper(string name, string version) {
        *softint rv = omqmap.mrmap{name}{version};
        if (!rv) {
            AutoLock al(libmap_mutex);
            checkLibMapCacheIntern();

            rv = omqmap.mrmap{name}{version};
        }
        return rv;    }


    *hash lookupInterface(string interface_type, auto interface_id) {
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
        }
        throw "UNKNOWN-INTERFACE-TYPE-ERROR", sprintf("unknown interface type %y", interface_type);
    }

    *hash<auto> getMapperMapSubset(*list<auto> ids) {
        if (!ids)
            return;

        *hash<auto> h = omqmap.mmap{ids};
        if (!h) {
            AutoLock al(libmap_mutex);
            checkLibMapCacheIntern();
            h = omqmap.mmap{ids};
        }

        return h;
    }

    auto getVMapValue(string name, *string key) {
        AutoLock al(vsm);
        checkVMapCacheIntern();

        *int id = omqmap.vmrmap{name};
        if (!id)
            throw "VALUE-MAP-ERROR", sprintf("value map name '%s' does not exist", name);
        if (!exists omqmap.vmmap{id})
            throw "VALUE-MAP-ERROR", sprintf("value map id '%d' does not exist", id);

        return getVMapValueUnlocked(id, key);
    }

    *hash<auto> getVMapMap() {
        *hash<auto> h = omqmap.vmmap;
        if (!h) {
            AutoLock al(vsm);
            checkVMapCacheIntern();
            h = omqmap.vmmap;
        }
        return h;
    }

    *hash<auto> lookupService(softstring serviceid, bool verbose = True) {
        return methodGateArgs("lookupService", (serviceid, verbose));
    }

    *hash<auto> rLookupServiceInfo(string type, string name, string version) {
        return methodGateArgs("rLookupServiceInfo", (type, name, version));
    }

    *hash<auto> rLookupServiceMethodInfo(string name, string version, string method) {
        return methodGateArgs("rLookupServiceInfo", (name, version, method));
    }

    *hash<auto> lookupPipeline(string name) {
        *hash<auto> pipeline = omqmap.pipelines{name};
        if (!pipeline) {
            AutoLock al(libmap_mutex);
            checkLibMapCacheIntern();
            pipeline = omqmap.pipelines{name};
        }

        return pipeline;
    }

    *hash<auto> lookupFsm(string name) {
        *hash<auto> fsm = omqmap.fsm{name};
        if (!fsm) {
            AutoLock al(libmap_mutex);
            checkLibMapCacheIntern();
            fsm = omqmap.fsm{name};
        }

        return fsm;
    }

    *hash<auto> getAuthLabel(int serviceid, string authlabelid) {
        return methodGateArgs("getAuthLabel", (serviceid, authlabelid));
    }

    *int getSlaForJob(int jobid) {
        *int rv = sla_rjmap{jobid};
        if (!rv) {
            AutoLock al(slam);
            checkSlaCacheIntern();
            rv = sla_rjmap{jobid};
        }
        return rv;
    }

    # returns False if the SLA does not exist and the event was not posted
    bool postSlaEventSuccess(int slaid, number val, string producer) {
        return methodGateArgs("postSlaEventSuccess", (slaid, val, producer));
    }

    # returns False if the SLA does not exist and the event was not posted
    bool postSlaEventSuccess(string sla, number val, string producer) {
        return methodGateArgs("postSlaEventSuccess", (sla, val, producer));
    }

    # returns False if the SLA does not exist and the event was not posted
    bool postSlaEventError(int slaid, number val, string producer, string err, string errdesc) {
        return methodGateArgs("postSlaEventError", (slaid, val, producer, err, errdesc));
    }

    # returns False if the SLA does not exist and the event was not posted
    bool postSlaEventError(string sla, number val, string producer, string err, string errdesc) {
        return methodGateArgs("postSlaEventError", (sla, val, producer, err, errdesc));
    }

    /** update the last_executed date in the internal cache for jobs so that this info (which is used in various places)
        is up to date
    */
    updateJobTimestamps(softstring jobid, date last_executed, *date next, *int last_executed_jiid) {
        methodGateArgs("updateJobTimestamps", (jobid, last_executed, next, last_executed_jiid));
    }

    /** returns a hash with the following keys:
        - \c options: a hash of the options set with the values set
        - \c errs: a list of strings of errors
    */
    hash<auto> updateJobOptions(softint jobid, hash<auto> opts) {
        return methodGateArgs("updateJobOptions", (jobid, opts));
    }

    # mapped directly from the server
    # flushes all pending events to disk and returns after the data has been committed
    flushSlaEvents() {
        methodGateArgs("flushSlaEvents");
    }

    invalidateConfigValuesCache() {
        AutoLock al(configItemValuesMutex);
        invalidateConfigValuesCacheIntern();
    }

    invalidateWorkflowCache() {
        AutoLock al(wfm);
        invalidateWorkflowCacheIntern();
    }

    invalidateLoggerCache() {
        AutoLock al(loggerMutex);
        invalidateLoggerCacheIntern();
    }

    invalidateLibMapCache() {
        AutoLock al(libmap_mutex);
        remove omqmap{LibMaps};
        cache.libmap = False;
    }

    invalidateSlaCache() {
        AutoLock al(slam);
        remove sla_rjmap;
        cache.sla = False;
    }

    invalidateEventCache() {
        AutoLock al(em);
        remove omqmap{"emap", "ermap"};
        cache.e = False;
    }

    invalidateVMapCache() {
        AutoLock al(vsm);
        remove omqmap{"vmmap", "vmrmap"};
        cache.vm = False;
    }

    invalidateTypes() {
        AutoWriteLock al(type_cache.getLock());
        map type_cache.removeType($1), argv;
    }

    #! Returns the path for the given type if it exists or @ref NOTHING if not
    /** @param path the normalized path to the type without any leading \c "/"

        @return the path for the given type if it exists or @ref NOTHING if not
    */
    private *AbstractDataProviderType lookupTypeImpl(string path) {
        RWLock lock = type_cache.getLock();
        AutoWriteLock al(lock);

        while (type_serialization_map{path}.request) {
            if (!type_serialization_map{path}.cond) {
                type_serialization_map{path}.cond = new Condition();
            }
            ++type_serialization_map{path}.waiting;
            type_serialization_map{path}.cond.wait(lock);
            --type_serialization_map{path}.waiting;
        }
        on_exit {
            if (!type_serialization_map{path}.waiting) {
                remove type_serialization_map{path};
            }
        }

        *AbstractDataProviderType type = type_cache.getType(path);
        if (!type) {
            type = getCacheRemoteType(path, lock);
            if (type) {
                # save type in cache and return it
                type_cache.registerType(path, type);
                return type;
            }
        }
    }

    #! Makes a request to qorus-core for the given type and caches it if it exists
    /** called in the type cache write lock
    */
    private *AbstractDataProviderType getCacheRemoteType(string path, RWLock lock) {
        # mark request in progress
        if (!type_serialization_map{path}) {
            type_serialization_map{path} = <TypeRequestInfo>{};
        } else {
            QDBG_ASSERT(!type_serialization_map{path}.request);
            type_serialization_map{path}.request = True;
        }
        lock.writeUnlock();
        # on exit, mark the request as no longer in progress and wait up any waiting threads
        on_exit {
            lock.writeLock();
            type_serialization_map{path}.request = False;
            if (type_serialization_map{path}.waiting) {
                type_serialization_map{path}.cond.broadcast();
            } else {
                remove type_serialization_map{path};
            }
        }

        return methodGateArgs("lookupType", path);
    }

    # this method always starts with readLock on
    private auto getVMapValueUnlocked(softstring id, string key) {
        if (!m_vmapCache{id}.hasKey(key) && !omqmap.vmmap{id}.full) {
            return getVMapValueUnlockedIntern(id, key);
        }
        return doVMapValue(id, key);
    }

    private invalidateConfigValuesCacheIntern() {
        remove omqmap.configItemValues;
        cache.configItemValues = False;
    }

    private invalidateLoggerCacheIntern() {
        remove omqmap{"loggerMap", "loggerAliases"};
        cache.logger = False;
    }

    private invalidateWorkflowCacheIntern() {
        remove omqmap{"wfmap", "wfrmap", "wfids"};
        cache.wf = False;
    }

    private getWorkflowStepInfo(reference h) {
        AutoLock al(libmap_mutex);
        checkLibMapCacheIntern();
        getWorkflowStepInfoUnlocked(\h);
    }

    # must be called in the configItemValuesMutex lock
    private checkConfigCacheIntern() {
        if (!cache.configItemValues) {
            omqmap.configItemValues = methodGateArgs("getConfigItemValues");
            cache.configItemValues = True;
        }
    }

    # must be called in the loggerMutex lock
    private checkLoggerCacheIntern() {
        if (!cache.logger) {
            omqmap += methodGateArgs("getLoggerMaps");
            cache.logger = True;
        }
    }

    # must be called in the wfm lock
    private checkWorkflowCacheIntern() {
        if (!cache.wf) {
            omqmap += methodGateArgs("getWorkflowMaps");
            cache.wf = True;
        }
    }

    # must be called in the libmap_mutex lock
    private checkLibMapCacheIntern() {
        if (!cache.libmap) {
            omqmap += methodGateArgs("getLibMaps");
            cache.libmap = True;
        }
    }

    # must be called in the em lock
    private checkEventCacheIntern() {
        if (!cache.e) {
            omqmap += methodGateArgs("getEventMaps");
            cache.e = True;
        }
    }

    # must be called in the qm lock
    private checkVMapCacheIntern() {
        if (!cache.vm) {
            omqmap += methodGateArgs("getVMapMaps");
            cache.vm = True;
        }
    }

    # must be called in the slam lock
    private checkSlaCacheIntern() {
        if (!cache.sla) {
            self += methodGateArgs("getSlaMaps");
            cache.sla = True;
        }
    }
}
