# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

our QdspClient omqp;
our QorusCoreSubsystemClientBase orders;
our ServerSQLInterface sqlif;
our QorusCoreSubsystemClientBase SMC;

class QorusInterfaceProcess inherits public AbstractQorusDistributedProcessWithDebugProgramControl,
        QorusCommonInterface {
    public {
         # interface name
        string interfaceName;

        # interface version
        string interfaceVersion;

        # interface type
        string interfaceType;

        # interface id
        int interfaceId;

        # AuditRemote interface
        AuditRemote audit;

        # client datasource manager
        ClientDatasourceManager dsmanager();

        # mapper containers
        QorusMappers mappers();

        # system options
        QorusClusterOptions options();

        # core system options client
        QorusCoreSubsystemClientBase options_client;

        # Qorus Map Manager client
        QorusMapManagerClient qmm;

        # workflow event manager client
        QorusCoreSubsystemClientBase events;

        # RBAC client
        QorusCoreSubsystemClientBase rbac;

        # log message client object
        QorusLogWebSocketHandlerClient eventLog;

        # alert client
        QorusCoreSubsystemClientBase alerts;

        # system properties client
        QorusCoreSubsystemClientBase props;

        # global workflow control client
        QorusControlClient control_client;

        # datasource manager client
        QorusCoreSubsystemClientBase dsmanager_client;

        # job manager client
        QorusCoreSubsystemClientBase jobManager;

        # user connection manager client
        QorusUserConnectionsClient connections;

        # qorus <-> qorus remote connection manager client
        RemoteMonitorClient remotemonitor;

        # qorus <-> qorus remote REST connection manager client
        RemoteRestConnectionClient restconnections;

        # list of mapper IDs belonging to this interface
        *list<int> mapper_ids;

        # shutdown flag
        bool shutting_down = False;

        # is core interested in our logs?
        bool log_subscribed = False;

        #! network ID for the qdsp-omq process
        string qdsp_omq_id = qdsp_get_process_name("omq");

        #! custom process thread stack size
        softint stack_size;

        # debug internal flag
        const DebugInternals =
%ifdef QorusDebugInternals
            True
%else
            False
%endif
            ;
    }

    private {
        # startup counter
        Counter startup_cnt(1);
    }

    private:internal {
        # interface internal state
        string state = IS_STARTING;

        # interface states
        const IS_STARTING = "STARTING";
        const IS_RUNNING = "RUNNING";
        const IS_STOPPING = "STOPPING";
    }

    constructor(reference<list<string>> p_argv, hash<auto> getopt_opts = Opts) :
            AbstractQorusDistributedProcessWithDebugProgramControl(\p_argv, getopt_opts) {
%ifdef HAVE_SIGNAL_HANDLING
        # install shutdown signal handlers
        set_signal_handler(SIGTERM, \signalHandler());
        set_signal_handler(SIGINT,  \signalHandler());
        set_signal_handler(SIGHUP,  \signalHandler());
        set_signal_handler(SIGUSR2, \signalHandler());
%endif
    }

    string getSystemDbDriverName() {
        return omqp.getDriverName();
    }

    #! Processes cmd-line args, sets up the NetworkKeyHelper and sets up the connection to the active master
    private doInitialConfig(reference<list<string>> p_argv) {
        AbstractQorusDistributedProcessWithDebugProgramControl::doInitialConfig(\p_argv);

        *string interfaceName = shift p_argv;
        *string interfaceVersion = shift p_argv;
        *string stackSize = shift p_argv;

        if (!exists interfaceName || !exists interfaceVersion || !exists stackSize) {
            usage();
        }

        self.interfaceName = interfaceName;
        self.interfaceVersion = interfaceVersion;
        interfaceId = getInterfaceId();
        stack_size = stackSize;

        # we have to set the stack size as early as possible; before any threads are started
        if (stack_size) {
            setStackSize(stack_size);
        }
    }

    int getInterfaceId() {
        return (client_id =~ x/-([0-9]+)$/)[0].toInt();
    }

    #! Returns the custom stack size for the process; if any
    *int getStackSize(hash<auto> qorus_options) {
        return stack_size ?* qorus_options."stack-size";
    }

    setStateRunning() {
        QDBG_ASSERT(state == IS_STARTING);
        startup_cnt.dec();

        state = IS_RUNNING;
    }

    setStateStopping() {
        QDBG_ASSERT(state == IS_STARTING || state == IS_RUNNING);
        state = IS_STOPPING;
    }

    bool isRunning() {
        return state == IS_RUNNING;
    }

    string getState() {
        return state;
    }

    waitForStartup() {
        startup_cnt.waitForZero();
    }

    bool getDebugSystemInternals() {
        return DebugInternals;
    }

    synchronized bool canShutdown() {
        if (shutting_down) {
            return False;
        }
        return shutting_down = True;
    }

    shutdown() {
        if (canShutdown()) {
            setStateStopping();
            background shutdownIntern();
        }
    }

    # called when the cluster server process should stop
    # do not terminate the event thread immediately; we terminate manually later in the shutdown process
    private stopServer() {
        logInfo("server issued STOP");
        shutdown();
    }

    private initInterface() {
        try {
            waitForQorusCore();

            # init the options client first
            options_client = new QorusCoreSubsystemClientBase(core, "options");

            # process the options file, set defaults, and check for sane option values
            options.init();

            setQorusLogDir();

            # init qorus-core subsystem clients
            qmm = new QorusMapManagerClient(core);
            SMC = new QorusCoreSubsystemClientBase(core, "SM");
            events = new QorusCoreSubsystemClientBase(core, "events");
            rbac = new QorusCoreSubsystemClientBase(core, "rbac");
            eventLog = new QorusLogWebSocketHandlerClient(core);
            alerts = new QorusCoreSubsystemClientBase(core, "alerts");
            props = new QorusCoreSubsystemClientBase(core, "props");
            control_client = new QorusControlClient(core);
            orders = new QorusCoreSubsystemClientBase(core, "orders");
            dsmanager_client = new QorusCoreSubsystemClientBase(core, "dsmanager");
            jobManager = new QorusCoreSubsystemClientBase(core, "jobManager");
            connections = new QorusUserConnectionsClient(core);
            remotemonitor = new RemoteMonitorClient(core);
            restconnections = new RemoteRestConnectionClient(core);

            # init other helper objects
            omqservice = new OMQ::QorusSystemServiceHelper();
            sysinfo = new SystemServiceHelper("info");
            api = new SystemApiHelper();

            waitForQdspOmq();

            # init SQL interface
            switch (omqp.getDriverRealName()) {
                case "oracle":
                    sqlif = new OracleServerSQLInterface(omqp);
                    break;

                case "pgsql":
                case /^postgres/i:
                    sqlif = new PostgreServerSQLInterface(omqp);
                    break;

                case "mysql":
                    sqlif = new MySQLServerSQLInterface(omqp);
                    break;

                default:
                    throw "DATASOURCE-ERROR", sprintf("driver %y is not supported for the Qorus system schema",
                        omqp.getDriverRealName());
            }

            # create system audit object
            audit = new AuditRemote(sqlif, options.get("audit"), core);

            # set debug flag
            if (!debug_system && options.get("debug-system")) {
                debug_system = True;
            }

            QorusClientServer::init();

            # initialize data providers
            postInit(options.get(PostInitOptions), logger);
        } catch (hash<ExceptionInfo> ex) {
            logError("initInterface(): %s", get_exception_string(ex));
            exit(QSE_OPTION_ERROR);
        }
    }

    private waitForQdspOmq() {
        try {
            # get the URLs for the qdsp-omq distributed datasource pool process and register it as a server
            registerServer(qdsp_omq_id);
            # get the system schema connection client object
            createQdspOmqClient();
            return;
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "UNKNOWN-PROCESS-ERROR") {
                rethrow;
            }
            QDBG_LOG("failed to initialize qdsp omq client: %s", get_exception_string(ex));
        }

        # here we need to wait until the qdsp-omq process exists
        logInfo("qdsp-omq process is not running yet; waiting for it to start...");
        waitForClient(qdsp_omq_id);
    }

    private createQdspOmqClientBackground() {
        background sub () {
            try {
                # do not create datasource inline; will cause a deadlock
                createQdspOmqClient();
            } catch (hash<ExceptionInfo> ex) {
                logError("%s", get_exception_string(ex));
            }
        }();
    }

    private createQdspOmqClient() {
        proc_lck.lock();
        on_exit proc_lck.unlock();

        if (!omqp) {
            # the following call will fail with an exception if the qdsp-omq process is not running
            omqp = new QdspClient(self, "omq", {"set_context": options.get("oracle-datasource-pool")});
            notifyClientIntern(qdsp_omq_id);
        }
    }

    #! This method is called when qorus-core starts the system pool process
    systemPoolStarted(hash<ClusterProcInfo> info, date started, bool already_started) {
        if (core) {
            # make sure the qdsp-omq process is registered properly
            updateUrls(info.id, info, started, True);
            createQdspOmqClientBackground();
        }
    }

    checkResetDatasource(string server_name, hash<auto> ex) {
        if (ds_error_needs_reset(ex)) {
            dsmanager_client.errorResetDsBackground(server_name, ex);
        }
    }

    updateMappers(*list<auto> mapper_ids) {
        self.mapper_ids = mapper_ids;
    }

    # only return mappers used by this workflow
    *hash<auto> getMapperMap() {
        return qmm.getMapperMapSubset(mapper_ids);
    }

    auto callCoreStaticMethodTld(softlist<string> tld_keys, string cname, string mname) {
        hash<auto> h = {
            "cname": cname,
            "mname": mname,
            "args": argv,
            "tld": tld{tld_keys},
        };
        *list<string> msgs = core.sendCheckResponse(CPC_CORE_CALL_STATIC_METHOD, h, CPC_OK);
        return msgs ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto callCoreStaticMethodTld(hash<auto> call_tld, string cname, string mname) {
        hash<auto> h = {
            "cname": cname,
            "mname": mname,
            "args": argv,
            "tld": call_tld,
        };
        *list<string> msgs = core.sendCheckResponse(CPC_CORE_CALL_STATIC_METHOD, h, CPC_OK);
        return msgs ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto callCoreStaticMethod(string cname, string mname) {
        hash<auto> h = {
            "cname": cname,
            "mname": mname,
            "args": argv,
            "tld": getTldContext(),
        };
        QDBG_LOG("%s::callCoreStaticMethod() h: %y", self.className(), h);
        *list<string> msgs = core.sendCheckResponse(CPC_CORE_CALL_STATIC_METHOD, h, CPC_OK);
        return msgs ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto callCoreStaticMethodUnreliable(string cname, string mname) {
        hash<auto> h = {
            "cname": cname,
            "mname": mname,
            "args": argv,
            "tld": getTldContext(),
        };
        QDBG_LOG("%s::callCoreStaticMethodUnreliable() h: %y", self.className(), h);
        *list<string> msgs = core.sendCheckResponseUnreliable(CPC_CORE_CALL_STATIC_METHOD, h, CPC_OK);
        return msgs ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto callCoreFunctionTld(softlist<string> tld_keys, string name) {
        hash<auto> h = {
            "name": name,
            "args": argv,
            "tld": tld{tld_keys},
        };
        *list<string> msgs = core.sendCheckResponse(CPC_CORE_CALL_FUNCTION, h, CPC_OK);
        return msgs ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto callCoreFunctionTld(hash<auto> call_tld, string name) {
        hash<auto> h = {
            "name": name,
            "args": argv,
            "tld": call_tld,
        };
        *list<string> msgs = core.sendCheckResponse(CPC_CORE_CALL_FUNCTION, h, CPC_OK);
        return msgs ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto callCoreFunction(string name) {
        hash<auto> h = {
            "name": name,
            "args": argv,
            "tld": getTldContext(),
        };
        QDBG_LOG("%s::callCoreFunction() h: %y", self.className(), h);
        *list<string> msgs = core.sendCheckResponse(CPC_CORE_CALL_FUNCTION, h, CPC_OK);
        return msgs ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    auto callCoreFunctionUnreliable(string name) {
        hash<auto> h = {
            "name": name,
            "args": argv,
            "tld": getTldContext(),
        };
        QDBG_LOG("%s::callCoreFunctionUnreliable() h: %y", self.className(), h);
        *list<string> msgs = core.sendCheckResponseUnreliable(CPC_CORE_CALL_FUNCTION, h, CPC_OK);
        return msgs ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }

    logArgs(int lvl, string msg, auto args) {
        string fmsg = enrichLogMsg(msg, args);
        if (core) {
            logger.log(lvl, "%s", fmsg, new LoggerEventParameter(\Qorus.logEvent(), interfaceId,
                sprintf("%s T%d [%s]: ", log_now(), gettid(), LoggerLevel::getLevel(lvl).getStr()) + fmsg + "\n"));
        } else {
            logger.log(lvl, "%s", fmsg);
        }
    }

    logError(string msg) {
        logArgs(Logger::LoggerLevel::ERROR, msg, argv);
    }

    logWarn(string msg) {
        logArgs(Logger::LoggerLevel::WARN, msg, argv);
    }

    logInfo(string msg) {
        logArgs(Logger::LoggerLevel::INFO, msg, argv);
    }

    logDebug(string msg) {
        logArgs(Logger::LoggerLevel::DEBUG, msg, argv);
    }

    logTrace(string msg) {
        logArgs(Logger::LoggerLevel::TRACE, msg, argv);
    }

    private processAbortNotificationImpl(string process) {
        # this method intentionally left blank
    }

    private processAbortedImpl(string process, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        # first handle URLs
        bool created_omqp;
        *bool updated;
        if (restarted) {
            if (info.new_active_master_id) {
                process = master.getRemoteProcessId();
                logInfo("active master updated from %y -> %y", process, info.new_active_master_id);
            }
            # NOTE: external processes have no queue URLs
            QDBG_ASSERT(!info.new_active_master_id || info.queue_urls);
            if (info.queue_urls) {
                updated = updateUrls(process, info, abort_timestamp, process == QDP_NAME_QORUS_CORE);
                QDBG_LOG("QorusInterfaceProcess::processAbortedImpl() updated: %y", updated);
                if (!omqp && process == qdsp_omq_id && core && updated) {
                    createQdspOmqClientBackground();
                    created_omqp = True;
                }
%ifdef QorusDebugInternals
            } else {
                QDBG_LOG("QorusInterfaceProcess::processAbortedImpl() no queue_urls: %y", info);
%endif
            }
        } else {
            # invalidate URLs for the process
            updated = invalidateUrls(process, abort_timestamp);
        }

        if (!updated) {
            logInfo("ignoring irrelevant abort message for process %y info: %y restarted: %y abort_timestamp: %y",
                process, info, restarted, abort_timestamp);
        }

        AbstractQorusDistributedProcessWithDebugProgramControl::processAbortedImpl(process, info, restarted, abort_timestamp);
        abortedProcessNotification(process, info, restarted, abort_timestamp);

        # recover processes
        switch (process) {
            # disable log streaming if the qorus-core process has aborted
            case QDP_NAME_QORUS_CORE: {
                log_subscribed = False;
                break;
            }

            # handle qdsp process aborts
            case =~ /^qdsp-/: {
                if (!created_omqp) {
                    string name = (process =~ x/^qdsp-(.*)$/)[0];
                    QDBG_LOG("processAbortedImpl() handling qdsp %y; restarted: %y abort timestamp: %y", name, restarted, abort_timestamp);
                    background dsmanager.datasourcePoolProcessAborted(name, restarted, abort_timestamp);
                }
                break;
            }
        }
    }

    # we cannot block the I/O thread; calls here must be guaranteed to be very fast or must
    # be made asynchronously in a background thread
    private bool processCmdImpl(ZSocketRouter sock, int index, string sender, string mboxid, string cmd, ZMsg msg) {
        #QDBG_LOG("processCmdImpl(): cmd: %y sender: %y", cmd, sender);
        if (AbstractQorusDistributedProcessWithDebugProgramControl::processCmdImpl(sock, index, sender, mboxid, cmd, msg)) {
            return True;
        }
        switch (cmd) {
            case CPC_BCAST_SUBSYSTEM: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                QDBG_LOG("subsystem broadcast: sender: %y TID: %d index: %y h: %y", sender, mboxid, index, h);
                switch (h.subsystem) {
                    case "options":
                        call_object_method_args(options, h.method, h.args);
                        return True;

                    case "qmm":
                        if (qmm) {
                            background callMapManagerBackground(index, sender, mboxid, h);
                        }
                        return True;

                    case "dsmanager":
                        background callDatasourceManagerBackground(index, sender, mboxid, h);
                        return True;

                    default:
                        throw "UNKNOWN-SUBSYSTEM-ERROR", sprintf("interface subsystem %y is unknown", h.subsystem);
                }
            }
            case CPC_BCAST_DIRECT: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                QDBG_LOG("direct call broadcast: sender: %y TID: %d index: %y h: %y", sender, mboxid, index, h);
                call_object_method_args(self, h.method, h.args);
                return True;
            }
            case CPC_INTERFACE_CALL_METHOD: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                QDBG_LOG("calling interface method %y with args %y", h.method, h.args);
                background callInterfaceMethod(index, sender, mboxid, h);
                return True;
            }
            case CPC_CORE_LOG_SUBSCRIBE: {
                QDBG_LOG("log subscribe: %y -> %y", log_subscribed, True);
                log_subscribed = True;
                sendResponse(index, sender, mboxid, CPC_OK);
                return True;
            }
            case CPC_CORE_LOG_UNSUBSCRIBE: {
                QDBG_LOG("log unsubscribe: %y -> %y", log_subscribed, False);
                log_subscribed = False;
                sendResponse(index, sender, mboxid, CPC_OK);
                return True;
            }
        }
        return False;
    }

    private callMapManagerBackground(int index, string sender, string mboxid, hash<auto> h) {
        try {
            call_object_method_args(qmm, h.method, h.args);
            sendResponse(index, sender, mboxid, CPC_OK);
        } catch (hash<ExceptionInfo> ex) {
            logInfo("map manager call exception for: %y: sender: %y TID %d index: %y: %s", h, sender, mboxid,
                index, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    private callDatasourceManagerBackground(int index, string sender, string mboxid, hash<auto> h) {
        try {
            call_object_method_args(dsmanager, h.method, h.args);
            sendResponse(index, sender, mboxid, CPC_OK);
        } catch (hash<ExceptionInfo> ex) {
            logInfo("datasource manager call exception for: %y: sender: %y TID %d index: %y: %s", h, sender, mboxid,
                index, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    private callInterfaceMethod(int index, string sender, string mboxid, hash<auto> h) {
        try {
            call_object_method_args(self, h.method, h.args);
            sendResponse(index, sender, mboxid, CPC_OK);
        } catch (hash<ExceptionInfo> ex) {
            logInfo("interface method call exception for: %y: sender: %y TID %d index: %y: %s", h, sender, mboxid,
                index, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    private setQorusLogDir() {
        *string logdir = options.get("logdir");
        *string logdir_orig = logdir;
        if (!logdir) {
            logdir = ENV.OMQ_LOG_DIR ?? (ENV.OMQ_DIR == "LSB" ? "/var/qorus/log" : ENV.OMQ_DIR + DirSep + "log");
        }

        if (!stat(logdir)) {
            stderr.printf("ERROR: can't stat log directory %y: %s\n", logdir, strerror());
            stderr.printf("aborting Qorus startup; please set the 'Qorus.logfiledir' option in the Qorus options file and restart Qorus\n");
            exit(QSE_LOG_ERROR);
        }

        if (logdir && substr(logdir, -1) != DirSep) {
            logdir += DirSep;
        }

        if (logdir != logdir_orig) {
            options.set({"logdir": logdir});
        }
    }

    private QorusDistributedDebugProgramControl createDebugProgramControl() {
        return new QorusDistributedDebugProgramControlSource(name, self);
    }

    private removeSignalHandlers() {
%ifdef HAVE_SIGNAL_HANDLING
        remove_signal_handler(SIGTERM);
        remove_signal_handler(SIGINT);
        remove_signal_handler(SIGHUP);
        remove_signal_handler(SIGUSR2);
%endif
    }

    private signalHandler(softstring sig) {
        removeSignalHandlers();
        logFatal("signal %y received; removed signal handlers; subsequent signals will cause the program to exit "
            "immediately", SignalToName{sig});
    }

    #! to enrich the log message
    private string enrichLogMsg(string msg, auto args) {
        return vsprintf(msg, args);
    }

    abstract *hash<auto> getTldContext();

    abstract shutdownIntern();

    #! Returns the interface object for the program
    abstract CommonInterfaceBase getInterface();

    #! Returns the interface object for the program if available
    abstract *CommonInterfaceBase tryGetInterface();
}

class OMQ::QorusDistributedDebugProgramControlSource inherits public OMQ::QorusDistributedDebugProgramControl, private:internal OMQ::QorusDebugProgramSource {

    constructor(string server_name, AbstractQorusDistributedProcessWithDebugProgramControl n_qdp) : OMQ::QorusDistributedDebugProgramControl(server_name, n_qdp) {
    }

    private bool isSupportedSourceCodeForLabel() {
        return True;
    }

    private hash<auto> getSourceCodeForLabel(string name) {
        return getSourceCodeForLabelImpl(name);
    }
}

sub olog(softint lvl, string fmt) {
    qlog_args(lvl, fmt, argv);
}

sub qlog(softint lvl, string fmt) {
    qlog_args(lvl, fmt, argv);
}

sub qlog_args(softint lvl, string fmt, *softlist<auto> args) {
    if (Qorus) {
        Qorus.logArgs(lvl, fmt, args);
    } else {
        printf("%s T%d: %s\n", log_now(), gettid(), vsprintf(fmt, args));
    }
}
