# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace OMQ;

hashdecl ServiceEventInfo {
    #! The event source
    DataProvider::Observable observable;
    #! The event handler
    AbstractServiceEventObserver observer;
}

class OMQ::LocalQorusService inherits CommonInterfaceBase, AbstractQorusService {
    public {
        # service stop reason
        ActionReason stopreason();

        # hash from mapper names to ids
        *hash<string, softint> mh;

        # hash from value map names to ids
        *hash<string, softint> vmh;

        #! API manager factory map; factory -> handler class name
        const ApiManagerFactoryMap = {
            "swagger": "QorusSwaggerApiManager",
            "soap": "QorusSoapApiManager",
        };

        #! Event handler factory map; type -> observer class name
        const EventHandlerClassMap = {
            "method": "ServiceEventMethodObserver",
            "fsm": "ServiceEventFsmObserver",
        };
    }

    private {
        #! the service Program container
        ServiceProgram pgm;

        #! config item change mutex
        Mutex config_item_change_mutex();

        #! config item change callback
        *code config_item_change_callback;

        #! Number of running threads
        Counter thread_counter();

        #! issue #3881: event sources
        hash<string, hash<ServiceEventInfo>> event_source_map;
    }

    private:internal {
        RWLock rwlock();

        date loaded = now_us();

        bool hasinit = False;
        bool hasstart = False;
        bool hasstop = False;
        bool event_shutdown = False;
        # is this service class-based?
        bool class_based;
        *string class_name;
        string language;

        # the service object for class-based services
        object service_object;

        # init done flag
        bool initdone = False;

        # stop warning hash: key = TID
        hash<string, bool> stop_warn;

        # service counter
        Counter sc;

        # service resources
        ServiceResources resources();

        #! state data lock
        Mutex state_lck();

        #! issue #3485: method / FSM trigger map: method -> fsm info
        hash<string, hash<auto>> fsm_map;

        #! issue #3485: FSM triggers - event source / observable objects
        hash<string, object> event_object_map;

        #! issue #3834: API manager
        *QorusAbstractApiManager api_manager;

        # PerfCache object for the entire service as a whole
        #PerformanceCache pc;

        # PerfCache objects for methods (service_methodid = PerfCache)
        #hash pcmh;
    }

    constructor(string type, string name) : AbstractQorusService(type, name) {
    }

    destructor() {
        foreach hash<ServiceEventInfo> info in (event_source_map.iterator()) {
            logInfo("stopping event listener %y", info.observer.getEventSourceName());
            delete info.observable;
            logInfo("stopped event listener %y", info.observer.getEventSourceName());
        }

        logInfo("%s %s service successfully deleted from cache", type, name);
        # deregister performance cache objects
        /*
        map Qorus.pcm.del($1), pcmh.iterator();
        if (pc)
            Qorus.pcm.del(pc);
        */

        # issue #3765 delete the service object, not the program
        delete service_object;
    }

    bool setupImpl(hash<auto> sq, *int po, *bool qorus_core_recover, *string uuid) {
        pgm = new ServiceProgram(sys, po, Qorus.options.get(), Qorus.getRuntimeProps());

        class_based = sq.class_based;
        class_name = sq.class_name;
        language = sq.language;
        config = sq.config;

        # set up mapper hash
        mh = map {$1.name: $1.mapperid}, sq.mappers;

        # set up value map hash
        vmh = map {$1.name: $1.id}, sq.vmaps;
        pgm.setProgramName(serviceid, name, version);
        LocalQorusService::setupProgram(pgm, sys);

        # issue #1929: ensure that thread-local data is set in any threads started by foreign modules such as jni
        pgm.setThreadInit(sub () {LocalQorusService::setThreadInit(self);});

        resources.setLog(\logInfo());
        resources.setup(serviceid, sq.resources, sys, po);

        # prepare for service initialization
        ServiceThreadContextHelper stch(self, "init");
        logInfo("loading version %s (serviceid %d); %s", version, sq.serviceid, getStartReasonText());

        # load required service modules
        if (sq.service_modules) {
            map pgm.loadModule(qorus_load_service_module($1)), sq.service_modules.split(",");
        }

        # step 2: setup service methods
        if (!sq.methods) {
            throw "BAD-SERVICE-DEFINITION", sprintf("service '%s/%s' has no methods defined", name, version);
        }

        {
            hash<auto> mappers;
            qorus_load_library(sq.lib, pgm, sub (string msg) {logInfo(vsprintf(msg, argv));}, \mappers);
            # add pipeline and FSM mappers
            mh += map {$1.name: $1.id}, mappers.values();
        }

        # parse in methods after library loaded
        map setupMethod($1), sq.methods.iterator();

        if (class_based) {
            setupCommitClass(sq);
        } else {
            commit();
        }

        if (mh) {
            updateMappers(map $1.toInt(), mh.iterator());
        }

        return False;
    }

    private setupCommitClass(hash<auto> sq) {
        if (language == "qore") {
            string label = sprintf("%s service: %s v%s (%d)", type, name, version, serviceid);
            pgm.parsePending(sq.class_source, label, 0, sq.tags.sys.source, sq.tags.sys.offset);
            pgm.cacheQoreClassObject(class_name);
        } else if (language == "java") {
            try {
                pgm.cacheJavaClass(class_name, sq.language_info, True, sq.tags.classpath);
            } catch (hash<auto> ex) {
                logDebug("Java initialization error: %s", get_exception_string(ex));
                if (ex.arg.typeCode() == NT_OBJECT) {
                    *object arg = ex.arg;
                    while (arg) {
                        logInfo("%s", arg.toString());
                        arg = arg.getCause();
                    }
                }
                rethrow;
            }
        } else if (language == "python") {
            pgm.cachePythonClass(class_name, sq.class_source, sq.language_info, True, sq.tags.module_path);
        } else {
            throw "SERVICE-ERROR", sprintf("%s service %s:%s (%d) requires support for unsupported language %y",
                type, name, version, serviceid, language);
        }
        commit();

        # verify service methods
        if (language == "qore") {
            Reflection::Class base_class = sys
                ? Class::forName("OMQ::UserApi::Service::QorusSystemService")
                : Class::forName("OMQ::UserApi::Service::QorusService");
            service_object = pgm.getCreateObject("qore", class_name);
            int access = Reflection::Class::getClass(service_object).getInheritanceAccess(base_class);
            if (access != AC_PUBLIC) {
                throw "SERVICE-PROGRAM-ERROR", sprintf("%s service %s v%s (%d): service class %y does not inherit %y",
                    type, name, version, serviceid, class_name, base_class.getPathName());
            }
        } else if (language == "java") {
            service_object = pgm.getCreateObject("java", class_name);
        } else if (language == "python") {
            service_object = pgm.getCreateObject("python", class_name);
        }

        # issue #3485: check FSM triggers for service
        foreach hash<auto> i in (sq.fsm_triggers.pairIterator()) {
            hash<auto> fsm_info = Qorus.qmm.lookupFsm(i.key);
            foreach hash<auto> trigger in (i.value) {
                if (trigger.method) {
                    if (methods{trigger.method}) {
                        fsm_map{trigger.method} = fsm_info;
                    } else {
                        throw "SERVICE-ERROR", sprintf("%s service %s v%s (%d) specifies unknown method %y to "
                            "trigger Finite State Machine %y; known methods: %y",
                            type, name, version, serviceid, trigger.method, i.key, keys methods);
                    }
                } else if (trigger."class" && trigger.connector) {
                    hash<auto> cls_info = Qorus.qmm.rLookupLatestClass(trigger."class");
                    *hash<auto> connector = cls_info.connectors{trigger.connector};
                    if (!connector) {
                        throw "SERVICE-ERROR", sprintf("%s service %s v%s (%d) specifies class %y to trigger "
                            "Finite State Machine %y with unknown connector %y",
                            type, name, version, serviceid, trigger."class", i.key, trigger.connector);
                    }
                    if (connector.type != "event") {
                        throw "SERVICE-ERROR", sprintf("%s service %s v%s (%d) specifies class %y to trigger "
                            "Finite State Machine %y with connector %y, but the connector type is %y; expecting "
                            "\"event\"",
                            type, name, version, serviceid, trigger."class", i.key, trigger.connector,
                            connector.type);
                    }
                    *object event_source = event_object_map{trigger."class"};
                    if (!event_source) {
                        event_source = pgm.getCreateObject(cls_info.language, trigger."class");
                        event_object_map{trigger."class"} = event_source;
                    }
                    string event_id = sprintf("%s::%s", trigger."class", connector.method);
                    QDBG_LOG("LocalQorusService::setupCommitClass() registering event trigger %y for FSM %y", event_id, i.key);
                    QorusFsmHandler::registerFsmAsObserver(i.key, event_source, event_id);
                }
            }
        }

        Reflection::Class cls = Class::getClass(service_object);

        foreach string method in (keys methods) {
            string class_method = method;
            if (method == "copy") {
                class_method = "_copy";
            }
            try {
                hash<MethodAccessInfo> method_info = cls.findMethod(class_method);
                bool has_public;
                if (method_info.access == AC_PUBLIC) {
                    foreach AbstractMethodVariant v in (method_info.method.getVariants()) {
                        if (v.getModifiers() & AC_PUBLIC) {
                            has_public = True;
                            break;
                        }
                    }
                }
                if (!has_public) {
                    if (method == class_method) {
                        throw "SERVICE-PROGRAM-ERROR", sprintf("%s service %s v%s (%d): service class %y does not "
                            "implement a public method variant for declared service method \"%s()\"",
                            type, name, version, serviceid, class_name, method);
                    } else {
                        throw "SERVICE-PROGRAM-ERROR", sprintf("%s service %s v%s (%d): service class %y does not "
                            "implement a public method variant for declared service method \"%s()\" with name "
                            " \"%s()\"", type, name, version, serviceid, class_name, method, class_method);
                    }
                }
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "UNKNOWN-METHOD") {
                    if (method == class_method) {
                        throw "SERVICE-PROGRAM-ERROR", sprintf("%s service %s v%s (%d): service class %y does not "
                            "implement a method for declared service method \"%s()\"",
                            type, name, version, serviceid, class_name, method);
                    } else {
                        throw "SERVICE-PROGRAM-ERROR", sprintf("%s service %s v%s (%d): service class %y does not "
                            "implement a method for declared service method \"%s()\" with name \"%s()\"",
                            type, name, version, serviceid, class_name, method, class_method);
                    }
                }
            }
        }

        # notify observable objects that all observers have been added, if applicable
        map $1.observersReady(), event_object_map.iterator(), $1.hasCallableMethod("observersReady");

        # setup API manager if applicable
        if (sq.api_manager) {
            *string api_class = ApiManagerFactoryMap{sq.api_manager.factory};
            if (!api_class) {
                throw "SERVICE-ERROR", sprintf("%s service %s v%s (%d) requires unknown API management factory %y "
                    "(supported factories: %y)", type, name, version, serviceid, sq.api_manager.factory,
                    keys ApiManagerFactoryMap);
            }
            QDBG_LOG("LocalQorusService::setupCommitClass() api_manager: %y api_class: %y", sq.api_manager, api_class);
            api_manager = create_object(api_class, self, sq.api_manager);
            QDBG_LOG("LocalQorusService::setupCommitClass() api_manager: %y", api_manager.className());
        }

        # setup event sources if applicable
        foreach hash<auto> event in (sq.events) {
            on_error rethrow $1.err, sprintf("failed to initialize event sources: %s", $1.desc);
            hash<auto> ctxt = UserApi::getUserContextInfo();
            *hash<auto> opts = _priv_parse_ui_hash(event.options, True, ctxt);
            AbstractDataProvider prov = UserApi::getDataProvider(event.type, event.name, event.path, opts, ctxt);
            prov.checkObservable();
            prov.setLogger(getLogger());
            string event_source_name = sprintf("%s:%s", event.type, event.name);
            if (event.path) {
                if (event.path !~ /^\//) {
                    event_source_name += "/";
                }
                event_source_name += event.path;
            }
            *string event_handler_class = EventHandlerClassMap{event.handler.type};
            if (!event_handler_class) {
                throw "EVENT-HANDLER-ERROR", sprintf("unknown event handler type %y; known types: %y",
                    event.handler.type, keys EventHandlerClassMap);
            }

            AbstractServiceEventObserver observer = create_object(event_handler_class, self, event_source_name,
                event.handler);
            DataProvider::Observable observable = cast<DataProvider::Observable>(prov);
            event_source_map{prov.uniqueHash()} = <ServiceEventInfo>{
                "observable": observable,
                "observer": observer,
            };
            observable.registerObserver(observer);
            if (observable instanceof DataProvider::DelayedObservable) {
                cast<DataProvider::DelayedObservable>(observable).observersReady();
            }
            logInfo("started event listener %s (%y) with %s handler %y", event_source_name, opts,
                event.handler.type, event.handler.value);
        }
    }

    #! Makes an internal service method call
    auto callLocalMethod(string method) {
        # to save exception info if necessary
        ServiceThreadContextHelper stch(self, method);

        # lock service if necessary
        object al;
        if (methods{method}.lock == OMQ::SLRead) {
            if (!rwlock.lockOwner()) {
                al = new AutoReadLock(rwlock);
            }
        } else if (methods{method}.lock == OMQ::SLWrite) {
            if (!rwlock.writeLockOwner()) {
                al = new AutoWriteLock(rwlock);
            }
        }

        return callMethodImpl(method, argv);
    }

    #! issue #3218: deserialize in the Program object to allow local types to be supported
    auto deserialize(data d) {
        return pgm.callFunction("_qorus_deserialize", d);
    }

    #! issue #3267: set the config item change callback
    setConfigItemChangeCallback(*code callback) {
        config_item_change_mutex.lock();
        on_exit config_item_change_mutex.unlock();

        config_item_change_callback = callback;
    }

    #! called when a config item used by this interface has its value changed externally
    configItemValueChanged(string name, auto value) {
        config_item_change_mutex.lock();
        on_exit config_item_change_mutex.unlock();

        if (!config_item_change_callback) {
            return;
        }

        # make callback in the background
        background callConfigItemChangeCallback(name);
    }

    checkEventShutdown(hash<auto> h) {
        if (h.shutdown) {
            if (event_shutdown) {
                throw "SHUTDOWN-ERROR", sprintf("event API called a second time after the shutdown key returned");
            }
            event_shutdown = True;
        }
    }

    auto getOption(string field) {
        return CommonInterfaceBase::getOption(field);
    }

    *hash<auto> getOption() {
        return CommonInterfaceBase::getOption();
    }

    auto getOption(softstring f) {
        return CommonInterfaceBase::getOption(f);
    }

    auto getOption(list<auto> field) {
        return CommonInterfaceBase::getOption(field);
    }

    Mapper getMapper(string mapname, *hash<auto> rtopts) {
        if (mh{mapname}) {
            return Qorus.mappers.get(mh{mapname}, rtopts);
        }

        throw "MAPPER-ERROR", sprintf("mapper %y is not a valid mapper for %s service %s v%s (%d); valid mappers: %y", mapname, type, name, version, serviceid, mh.keys());
    }

    AbstractIterator getMapperIterator(string mapname, Qore::AbstractIterator input, *hash<auto> rtopts) {
        if (mh{mapname})
            return Qorus.mappers.getIterator(mh{mapname}, input, rtopts);

        throw "MAPPER-ERROR", sprintf("mapper %y is not a valid mapper for %s service %s v%s (%d); valid mappers: %y", mapname, type, name, version, serviceid, mh.keys());
    }

    auto getValueMap(string mapname, string key) {
        if (vmh{mapname}) {
            return Qorus.qmm.getVMapValue(mapname, key);
        }

        throw "VALUE-MAP-ERROR", sprintf("value map %y is not a valid value map for %s service %s v%s (%d); valid value maps: %y", mapname, type, name, version, serviceid, vmh.keys());
    }

    list<auto> getValueMaps() {
        return Qorus.qmm.getVMapMap(){vmh.keys()}.values();
    }

    setStopReason(string desc) {
        stopreason.setReason(desc);
    }

    setStopReason(*hash<auto> cx, *string reason, bool override_reason = False) {
        stopreason.set(cx, reason, override_reason);
    }

    ActionReason getStopReason() {
        return stopreason;
    }

    int usleep(date us) {
        return usleep(us.durationMicroseconds());
    }

    int usleep(softint us) {
        softstring tid = gettid();
        if (stop_warn{tid}) {
            throw "STOP-ERROR", sprintf("omqsleep() or omqusleep() called twice in TID %d after service is in stop state", tid);
        }

        while (!getStopping() && us > 0) {
            Qore::usleep(us > 1000000 ? 1000000 : us);
            us -= 1000000;
        }
        if (getStopping()) {
            stop_warn{tid} = True;
            return -1;
        }
        return 0;
    }

    *hash<auto> getStateData() {
        state_lck.lock();
        on_exit state_lck.unlock();

        return getStateDataIntern();
    }

    private *hash<auto> getStateDataIntern() {
        *string str = get_sql_table_system_trans("omq", "service_state_data").selectRow(("columns": "data", "where": ("serviceid": serviceid))).data;
        if (!exists str)
            return;

        return deserialize_qorus_data(str);
    }

    saveStateData(*hash<auto> data) {
        state_lck.lock();
        on_exit state_lck.unlock();

        saveStateDataIntern(data);
    }

    saveStateDataIntern(*hash<auto> data) {
        *string str = data ? serialize_qorus_data(data) : NOTHING;

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                if (str)
                    psave({"serviceid": serviceid, "data": str});
                else
                    get_sql_table_system("omq", "service_state_data").del({"serviceid": serviceid});
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
    }

    saveStateDataPath(string path, auto value) {
        state_lck.lock();
        on_exit state_lck.unlock();

        *hash<auto> state = getStateDataIntern();
        state = UserApi::updateHashDotValue(state, path, value);
        #QDBG_LOG("LocalQorusService::saveStateDataPath() path: %y value: %y serviceid %d state data: %N", path, value, serviceid, state);
        saveStateDataIntern(state);
    }

    bool startServiceConditional(*bool qorus_core_recover) {
        QDBG_ASSERT(!qorus_core_recover);
        on_success {
            # must set "initdone" to True if the service has been started, as the service may not have an "init"
            # method and otherwise may not get set, and it must be set if the service has been initialized
            if (!initdone) {
                initdone = True;
            }
        }
        if (hasstart) {
            # increment thread count
            thread_counter.inc();
            on_error thread_counter.dec();
            # Qorus.logDebug(formatSvcLogMessage(type, name, "starting %s service", type));
            int tid = gettid();
            background startServiceIntern(tid);
            return True;
        }
        return False;
    }

    bool hasInit() {
        return hasinit;
    }

    bool hasStart() {
        return hasstart;
    }

    bool hasStop() {
        return hasstop;
    }

    hash<auto> getBasicInfo() {
        int threads = thread_counter.getCount();
        return {
            "parse_options": parse_options,
            "status": threads ? OMQ::SSRunning : OMQ::SSLoaded,
            "threads": threads,
            "loaded": loaded,
            "options": Qorus.qmm.lookupService(serviceid, False).options,
        };
    }

    hash<auto> getInfoImpl(*hash<auto> cx) {
        return getBasicInfo() + {
            "resource_files": resources.getResourceHashList(),
        };
    }

    int startThread(Mutex m, auto func, auto args) {
        # only allow threads to be started if a stop method is available
        if (!exists methods.stop) {
            throw "START-SERVICE-THREAD-ERROR", "cannot start a background thread as the service has no 'stop' method";
        }

        if (thread_counter.getCount() == Qorus.options.get("max-service-threads")) {
            throw "START-SERVICE-THREAD-ERROR", sprintf("cannot start another thread in %s service %s (v%s) because "
                "the max-service-thread limit (%d) has already been reached; wait for some threads to terimnate, or "
                "change this option and restart Qorus if necessary", type, name, version,
                Qorus.options.get("max-service-threads"));
        }

        # increment reference count for background thread
        notifyStartThreadImpl();

        # increment thread count
        thread_counter.inc();
        on_error thread_counter.dec();
        return background startThreadIntern(m, func, args);
    }

    hash<auto> getResource(string n, hash<auto> ctx, int code = 200, *hash<auto> hdr) {
        return resources.getResource(n, ctx, code, hdr);
    }

    *hash<auto> tryGetResource(string n, hash<auto> ctx, int code = 200, *hash<auto> hdr) {
        return resources.tryGetResource(n, ctx, code, hdr);
    }

    data getResourceData(string n, *hash<auto> ctx) {
        return resources.getResourceData(n, ctx);
    }

    WebService getResourceWsdl(string n, *hash<auto> ctx) {
        return resources.getResourceWsdl(n, ctx);
    }

    *data tryGetResourceData(string n, *hash<auto> ctx) {
        return resources.tryGetResourceData(n, ctx);
    }

    *hash<auto> getResourceHash() {
        return resources.getResourceHash();
    }

    list<string> getResourceList() {
        return resources.getResourceList();
    }

    list<hash<auto>> getResourceHashList() {
        return resources.getResourceHashList();
    }

    bool hasResource(string n) {
        return resources.hasResource(n);
    }

    checkDefaultResource(string name) {
        resources.checkDefaultResource(name);
    }

    hash<auto> renderTemplate(string n, *hash<auto> ctx) {
        return resources.renderTemplate(n, ctx);
    }

    *hash<auto> tryRenderTemplate(string n, hash<auto> cx) {
        return resources.tryRenderTemplate(n, cx);
    }

    *hash<auto> getTemplateHash() {
        return resources.getTemplateHash();
    }

    list<string> getTemplateList() {
        return resources.getTemplateList();
    }

    bool hasTemplate(string n) {
        return resources.hasTemplate(n);
    }

    auto callMethodImpl(string method, auto args) {
        if (!initdone && method == "init") {
            initdone = True;
        }
        *string m = tld.method;
        on_exit tld.method = m;
        tld.method = method;

%ifdef QorusCore
        # issue #3319: set interface context; at runtime only necessary for qorus-core
        ServiceContextHelper ixctx();
%endif

        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        # issue #3485: execute FSM if necessary
        if (*hash<auto> fsm_info = fsm_map{method}) {
            QDBG_LOG("method %s.%s() executing FSM %y with args: %y", name, method, fsm_info.name, args);
            return QorusFsmHandler::executeFsm(fsm_info.name, args);
        } else {
            if (method == "copy") {
                method = "_copy";
            }

            if (class_based) {
                return call_object_method_args(service_object, method, args);
            } else {
                return pgm.callFunctionArgs(method, args);
            }
        }
    }

    #! calls the config item changed callback with the config item name; the code can read the current value
    private callConfigItemChangeCallback(string config_item_name) {
        config_item_change_mutex.lock();
        on_exit config_item_change_mutex.unlock();

        if (!config_item_change_callback) {
            return;
        }

        create_tld();
        tld += {
            "svc": self,
        };

%ifdef QorusCore
        # issue #3319: set interface context; at runtime only necessary for qorus-core
        ServiceContextHelper ixctx();
%endif

        try {
            # NOTE: we need to call the callback in the Program context, or we will get a NullPointerException
            # when running the callback
            pgm.callFunction("_qorus_call_code", config_item_change_callback, config_item_name);
        } catch (hash<ExceptionInfo> ex) {
            # log any exception
            logInfo("exception in config item change callback: %s", Util::get_exception_string(ex));
        }
    }

    # starts a background thread for a service
    private startThreadIntern(Mutex m, auto func, auto args) {
        create_tld();
        tld.svc = self;
        tld.method = func.typeCode() == NT_STRING
            ? sprintf("background thread function: %y", func)
            : (tld.method
                ? sprintf("background thread started from method: %y", tld.method)
                : "background thread started from API call");

%ifdef QorusCore
        # issue #3319: set interface context; at runtime only necessary for qorus-core
        ServiceContextHelper ixctx();
%endif

        QDBG_LOG("started service thread: %y", func);

        try {
            if (func.callp()) {
                call_function_args(func, args);
            } else {
                pgm.callFunctionArgs(func, args);
            }
        } catch (hash<ExceptionInfo> ex) {
            # log any exception
            string desc = !Qorus.getDebugSystem() ? ex.desc : Util::get_exception_string(ex);
            logInfo("exception in %s: %s: %s", get_ex_pos(ex), ex.err, desc);
        }

        QDBG_LOG("service thread stopped: %y", func);

        m.lock();
        on_exit m.unlock();

        notifyEndThreadImpl();
        # decrement thread count
        thread_counter.dec();
    }

    # executes background service method "start()"
    private start() {
        QDBG_ASSERT(ensure_tld());
        tld.svc = self;
        tld.method = "start";

%ifdef QorusCore
        # issue #3319: set interface context; at runtime only necessary for qorus-core
        ServiceContextHelper ixctx();
%endif

        logInfo("service start() method running");
        try {
            # do not allow thread sources to stay in place beyond this call
            ThreadResourceHelper thread_resource_helper();

            if (class_based) {
                call_object_method_args(service_object, "start");
            } else {
                pgm.callFunctionArgs("start");
            }
        } catch (hash<ExceptionInfo> ex) {
            # log any exception
            string desc = !Qorus.getDebugSystem() ? ex.desc : Util::get_exception_string(ex);
            logInfo("exception in %s: %s: %s", get_ex_pos(ex), ex.err, desc);
        }

        logInfo("background service stopped, unloading service");
    }

    private commit() {
        # make sure service is consistent
        if (hasstart && !hasstop) {
            throw "INCONSISTENT-SERVICE", "start() method defined but not stop() method, deleting service";
        }

        if (!sys) {
            # import service API functions into service program
            foreach auto func in (OMQ::ServiceAPI) {
                if (exists func.import) {
                    if (func.check && pgm.existsFunction(func.import)) {
                        continue;
                    }
                    pgm.importFunction(func.actual, func.import);
                } else {
                    pgm.importFunction(func);
                }
            }
        }

        tld.svc = self;

        # issue #3319: set interface context; necessary also in qsvc processes during initialization
        ServiceContextHelper ixctx();

        pgm.parseCommit();
    }

    private startServiceIntern(int orig_tid) {
        create_tld();
        start();

%ifdef QorusDebugInternals
        # issue #2398 save TID of thread creating the reference
        save_thread_data("orig_service_thread_tid", orig_tid);
%endif

        # decrement thread count
        thread_counter.dec();

        if (!getStopping()) {
            string desc = "start() thread terminated prematurely, unloading service";
            stopreason.set("Qorus", "SERVICE-START-ERROR", desc);
            startThreadTerminated(desc);
        } else {
            startThreadTerminated();
        }
    }

    # called with the ServiceManager QSLock held
    # cannot be private as it is called from AbstractQorusCoreService::stop(), which is not directly related
    # to LocalQorusService in the hierarchy and therefore cannot access private members of LocalQorusService
    stopIntern() {
        if (!thread_counter.getCount()) {
            return;
        }

        logInfo("stopping service");

        QDBG_LOG("LocalQorusService::stopIntern() hasstop: %y initdone: %y", hasstop, initdone);

        # call "stop" method if it exists
        if (hasstop && initdone) {
            try {
                ServiceThreadContextHelper stch(self, "stop");

%ifdef QorusCore
                # issue #3319: set interface context; at runtime only necessary for qorus-core
                ServiceContextHelper ixctx();
%endif

                if (class_based) {
                    call_object_method_args(service_object, "stop");
                } else {
                    pgm.callFunctionArgs("stop");
                }

                thread_counter.waitForZero();
            } catch (hash<ExceptionInfo> ex) {
                string exdesc = !Qorus.getDebugSystem() ? ex.desc : get_exception_string(ex);
                string desc = sprintf("WARNING! exception in %s.%s.stop() could lead to a deadlock: %s: %s: %s", type, name, get_ex_pos(ex), ex.err, exdesc);
                logFatal(desc);
                logFatal(Util::get_exception_string(ex));

                Qorus.events.postServiceError(tld.cx, ES_Major, type, name, version, serviceid, "STOP-ERROR", desc);
            }
        }
    }

    Program getProgram() {
        return pgm;
    }

    private setupMethod(hash<auto> m) {
        logInfo("registering method %s() (%s)", m.name, m.locktype);
        methods{m.name} = {
            "lock"      : m.locktype,
            "desc"      : m.description,
            "internal"  : m.internal,
            "write"     : m.write,
            "id"        : m.service_methodid,
        };

        if (!m.tags.sys.source) {
            m.tags.sys -= ("source", "offset");
        }

        if (!class_based) {
            if (!m.body) {
                throw "CACHE-ERROR", sprintf("service method: %s v%s (%d) %s (%d) has no body in the metadata cache; "
                    "reset the service metadata cache and try again", name, version, serviceid, m.name,
                    m.service_methodid);
            }

            pgm.parsePending(m.body, sprintf("service method: %s v%s (%d) %s (%d)", name, version, serviceid, m.name,
                m.service_methodid), NOTHING, m.tags.sys.source, m.tags.sys.offset);
        }

        # get performance cache object
        #pcmh{m.service_methodid} = Qorus.pcm.add("m" + m.service_methodid);

        # set booleans
        if (m.name == "init") {
            hasinit = True;
        } else if (m.name == "start") {
            hasstart = True;
        } else if (m.name == "stop") {
            hasstop = True;
        }
    }

    private updateMappers(*list<auto> mapper_ids) {
        # method body intentionally left blank in this class; overridden in ClusterQorusService
    }

    #! Returns runtime options
    *hash<auto> getRuntimeOptionsImpl() {
        return Qorus.qmm.lookupService(serviceid, False)."runtime-options";
    }

    #! Sets options persistently
    setOptionsImpl(hash<auto> h) {
        Qorus.qmm.updateServiceOptionsErr(serviceid, h);
    }

    abstract private notifyStartThreadImpl();
    abstract private notifyEndThreadImpl();
    abstract startThreadTerminated(*string errdesc);
    abstract streamRegister(string stream, softlist<string> methods, code factory, string desc);
    abstract persistenceRegister(code factory);
    abstract persistenceThreadTerminate();
    abstract Logger getLogger();

    static setThreadInit(LocalQorusService svc) {
        ensure_create_tld();
        tld.svc = svc;
        #QDBG_LOG("LocalQorusService::setThreadInit()");
    }

    static setupProgram(Program p, bool sys, bool classes = True) {
        # load in service classes
        if (classes) {
            map p.importClass($1), ServiceClassList;
            # load in hashdecls
            map p.importHashDecl($1), CommonHashDeclList;
        }

        # export system service functions to service program if applicable
        if (sys) {
            # load in system service api functions
            #map p.importFunction($1), SystemServiceAPI;

            # load in system service classes
            if (classes) {
                map p.importClass($1), SystemServiceClassList;
            }

            # export system objects to service program (read-only)
            # import system datasource pool
            p.importGlobalVariable("omqp", True);
            # service manager
            p.importGlobalVariable("services", True);
            # segment manager
            p.importGlobalVariable("SM", True);
            # Qorus object
            p.importGlobalVariable("Qorus", True);
            # SQLInterface object
            p.importGlobalVariable("sqlif", True);
            # SystemApiHelper object
            p.importGlobalVariable("api", True);
        } else {
            # FIXME: deprecate this; only import with a compatibility option
            p.importGlobalVariable("omquser", True);
        }

        p.importGlobalVariable("omqservice", True);

        # this is available to call without CALL_SYSTEM_SERVICE permissions
        p.importGlobalVariable("sysinfo", True);
    }
}
