#!/usr/bin/qore
# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%requires qore >= 1.0

%new-style
%require-our
%strict-args
%require-types

%enable-all-warnings
%exec-class QorusApp

%include lib/qorus-system.ql

public namespace OMQ {
    const Banner = sprintf("%s v%s (build %s), Copyright (C) 2003 - 2023 Qore Technologies, s.r.o.", OMQ::ProductName,
        OMQ::version, QorusRevision);

    # global performance cache identifiers
    const GPC_AllWorkflows = "allwfs";
    const GPC_AllServices = "allsvcs";
    const GPC_AllJobs = "alljobs";

    # valid global performance cache values
    const GlobalPerformanceCacheHash = (
        GPC_AllWorkflows: True,
        GPC_AllServices: True,
        GPC_AllJobs: True,
    );
}

class OMQ::QorusApp inherits CryptoKeyHelper, AbstractQorusDistributedProcess, QorusCommonInterface,
        QorusIndependentProcess {
    public {
        QorusEventManager events;

        AlertManager alerts;

        QorusOptions options();
        JobManager jobManager();

        ConnectionDependencyManager connDeps();

        QorusPollingConnectionMonitor pmonitor;

        DatasourceManager dsmanager;
        RemoteMonitor remotemonitor;
        QorusUserConnections connections;

        QorusMappers mappers();

        ServerErrorManager EM;

        # web socket log event handler
        QorusLogWebSocketHandler eventLog;

        # web socket debug event handler
        QorusWebSocketDebugHandler debugHandler;

        # web socket performance event handler
        #QorusPerfCacheWebSocketHandler perfEvents;

        # WebDAV handler
        AbstractWebDavHandler webDavHandler;

        # web socket event handler
        WebAppSocketHandler webSocketHandler();

        # UI extension handler
        QorusSystemUiExtensionHandler uiext();

        # workflow and service group manager
        RBAC rbac();
        OMQ::PermissiveAuthenticator qorusAuth();

        # workflow order processing statistics
        WorkflowOrderStats orderStats();

        # system API hash
        hash system_api = OMQ::QorusSystemApi::get();

        # system start time
        date start_time = now_us();

        CoreServerSession session;
        # decremented when the system is shut down
        Counter start_counter(1);
        hash<auto> omq_info;
        hash<auto> omquser_info;

        # system schema properties (set by CoreServerSession)
        hash<auto> sysprops;

        bool shutting_down = False;
        bool http_debug = False;

        # workflow execution instance cache
        Control control();

        # workflow synchronization event manager
        SyncEventManager SEM;

        # WorkflowQueue thread pool
        WorkflowQueueThreadPool wqtp();

        # HTTP server's SOAP request handler
        SoapHandler soapHandler;

        # HTTP server's websocket debug handler
        QorusWebSocketDebugProgramControl debugProgramControl;

        # log closures
        code infoLogging = sub(string msg) { logInfo("OMQ: " + vsprintf(msg, argv)); };
        code errorLogging = sub(string msg) { logError("OMQ: " + vsprintf(msg, argv)); };

        # system YAML-RPC handler object
        YamlRpcHandler yamlRpcHandler;

        # system XML-RPC handler object
        XmlRpcHandler xmlRpcHandler;

        # system JSON-RPC handler object
        JsonRpcHandler jsonRpcHandler;

        # system HttpServer object
        QorusHttpServer httpServer;

        # system creator API WS handler
        QorusCreatorWebSocketHandler creatorWsHandler;

        # system FtpServer object
        FtpServer ftpServer;

        # system REST handler
        WebAppHandler restHandler;

        # remote development handler
        RemoteDevelopment::Handler remoteDevelopmentHandler;

        # logger controller - responsible class for logger configuration updates
        QorusLogger::LoggerController loggerController;

        # this will hold the map data used by omqmap
        QorusMapManager qmm();

        # for system properties
        Props props();

        # class for writing audit messages
        AuditLocal audit;

        # Global Performance Cache Manager
        #PerformanceCacheManager pcm();

        # performance cache lookups
        #PerformanceCache pcwf;
        #PerformanceCache pcsvc;
        #PerformanceCache pcjob;

        # hash of workflow processes running before qorus-core start; wfid -> True
        hash<string, bool> rwfh;

        # hash of service processes running before qorus-core start; svcid -> True
        hash<string, bool> rsvch;

        # hash of job processes running before qorus-core start; jobid -> True
        hash<string, bool> rjobh;

        # hash of dsp processes to recover
        hash<string, bool> rdsph;

        # qdsp server process info
        hash<ClusterProcInfo> qdsp_omq;

        # old session to reuse in case of still running interface processes
        *int recovery_sessionid;

        # issue #2732: nofile alert raised
        bool nofile_alert = False;

        # issue #2732: nproc alert raised
        bool nproc_alert = False;

        #! Counter is non-zero when Qorus is running
        Counter qorus_running_cnt();

        # issue #3812: allow process abort events to be waited on
        Mutex abort_lck();
        # process ID -> Counter hash -> Counter
        hash<string, hash<string, Counter>> abort_map;

        #! Counter for the heartbeat thread
        Counter heartbeat_thread_cnt();
        #! mutex and condition variable for the heartbeat thread
        Mutex heartbeat_mutex();
        Condition heartbeat_cond();

        const RbacServerApi = {
            "raise_transient_alert": \raise_rbac_alert(),
        };

        #! Heartbeat interval
        const HeartbeatInterval = 5s;

        const DefaultRestartTimeout = 120;

        # application command-line option hash
        const Opts = AbstractQorusDistributedProcess::Opts + {
            "independent": "I,independent",
        };

        # subscriber thread polling interval
        const DefaultSubscriberPollingInterval = 250ms;

        # issue #2732: "nofile" alert limit
        const NofileAlertLimit = (QorusSharedApi::getNofile() * 0.8).toInt();

        # issue #2732: "nproc" alert limit
        const NprocAlertLimit = (QorusSharedApi::getNproc() * 0.8).toInt();

        # offset column for cmd-line options
        const OffsetColumn = 29;

        #! WebDAV root path
        const QorusWebDavRootPath = "webdav";
    }

    private {
        WfSchemaSnapshotManager wfSnapshot;
        JobSchemaSnapshotManager jobSnapshot;
    }

    private:internal {
        # startup counter, decremented when the server has fully started
        Counter startup_cnt(1);

        # list of workflows whose "remote" status has changed
        list<hash<auto>> wfrl;

        # list of services whose "remote" status has changed
        list<hash<auto>> svcrl;

        # list of jobs whose "remote" status has changed
        list<hash<auto>> jobrl;

        # issue #2706: need to track interfaces and ignore process abort messages for processes we didn't start
        # in case qorus-core is restarted at the same time as other processes
        Mutex ix_lock();
        Condition ix_cond();
        int ix_waiting = 0;
        # hash of processes we started; process ID -> True
        hash<string, bool> ix_map;
        # hash of process start timestampts; ignore abort msgs earlier than a start entry
        hash<string, date> ix_timestamp_map;

        # qorus master process pub URL
        string master_pub_url;
        # qorus master process pub thread counter
        Counter master_pub_cnt();
        # qorus master process pub thread run flag
        bool sub_run = True;

        #! UNIX domain socket path
        string unix_socket_path;

        # logger map as seeded from qorus-master
        static hash<auto> seed_logger_map;

        #! master registration busy retry interval
        const MasterBusyRetryInterval = 10s;

        #! timeout for master restarts in independent mode
        const MasterRestartTimeout = 10s;

        # remote file location
        string remote_file_dir;
    }

    constructor() : AbstractQorusDistributedProcess(\ARGV, Opts, QorusApp::getQorusCoreLoggerParams()) {
        # register Qorus schemes
        ConnectionSchemeCache::registerScheme("qorus", QorusHttpConnection::ConnectionScheme);
        ConnectionSchemeCache::registerScheme("qoruss", QorusHttpConnection::ConnectionScheme);
        ConnectionSchemeCache::registerScheme("db", DatasourceConnection::ConnectionScheme);

        startQorusInitial();

        if (opts.independent) {
            do {
                QDBG_LOG("waiting for shutdown...");
                # wait for Qorus to shut down
                qorus_running_cnt.waitForZero();
                deleteMembers();
                if (!terminate) {
                    QDBG_LOG("shutdown complete, waiting for active master...");
                    # wait for a new active master
                    waitForActiveMaster();
                }
                # startup Qorus again
                if (!terminate) {
                    shutting_down = False;
                    initMembers();
                    startup_cnt.inc();
                    startQorusInitial();
                }
            } while (!terminate);

            # we need to exit explicitly in case there are Java threads that will not exit by themselves
            # stop cluster server process event thread
            stopEventThread();

            exit(0);
        }
    }

    clearAllMapperDependencies() {
        dsmanager.clearAllMapperDependencies();
        remotemonitor.clearAllMapperDependencies();
        connections.clearAllMapperDependencies();
    }

    clearMapperDependencies(softstring mapperid) {
        dsmanager.clearMapperDependencies(mapperid);
        remotemonitor.clearMapperDependencies(mapperid);
        connections.clearMapperDependencies(mapperid);
    }

    private stopEventThread() {
        AbstractQorusClientProcess::stopEventThread();
    }

    private initMembers() {
        options = new QorusOptions();
        jobManager = new JobManager();
        connDeps = new ConnectionDependencyManager();
        mappers = new QorusMappers();
        webSocketHandler = new WebAppSocketHandler();
        uiext = new QorusSystemUiExtensionHandler();
        rbac = new RBAC();
        webDavHandler = new QorusWebDavHandler(QorusWebDavRootPath);
        orderStats = new WorkflowOrderStats();
        start_time = now_us();
        QDBG_ASSERT(!start_counter.getCount());
        start_counter.inc();
        control = new Control();
        wqtp = new WorkflowQueueThreadPool();
        qmm = new QorusMapManager();
        # make sure connection stores use the metadata map lock
        connection_rwl = Qorus.qmm.getMapLock();
        props = new Props();
    }

    private deleteMembers() {
        delete props;
        delete qmm;
        delete wqtp;
        delete control;
        QDBG_ASSERT(!start_counter.getCount());
        delete orderStats;
        delete rbac;
        delete uiext;
        delete webSocketHandler;
        delete webDavHandler;
        delete mappers;
        delete connDeps;
        delete jobManager;
        delete options;
    }

    private startQorusInitial() {
        qorus_running_cnt.inc();

        try {
            {
                on_error {
                    qorus_running_cnt.dec();
                }

                startSubThread();

%ifdef HAVE_UNIX_USERMGT
                # check environment variables
                if (!strlen(ENV.USER)) {
                    ENV.USER = getusername();
                    if (!ENV.USER)
                        ENV.USER = sprintf("uid-%d", getuid());
                }
%else
                ENV.USER = getusername();
%endif

                # load data providers
                QorusClientServer::init();

                # signal recovery if applicable
                if (rwfh) {
                    control.signalRecovery();
                }

                # signal recovery if applicable
                if (rjobh) {
                    jobManager.signalRecovery();
                }

                # authorize start
                doAuthStart();

                # make sure connection stores use the metadata map lock
                connection_rwl = Qorus.qmm.getMapLock();

                # seed the logger metadata map from the environment if possible
                if (seed_logger_map) {
                    qmm.seedLoggers(seed_logger_map);
                }

                # create global objects
                omqservice = new OMQ::QorusSystemServiceHelper();

                # set system directories and paths
                QorusApp::setSystemPaths();

                # process command line
                processCommandLine();

                # process the options file, set defaults, and check for sane option values
                if (options.needsInit()) {
                    options.init(True);
                }

                # set and create remote file directory
                remote_file_dir = join_paths(tmp_location(), options.get("instance-key"));
                Dir dir("utf-8");
                dir.chdir(remote_file_dir);
                if (dir.exists()) {
                    FsUtil::remove_tree(remote_file_dir);
                }
                dir.create(0700);

                setQorusLogDir();

                loggerController = new LoggerController();

                # setup the sensitive data encryption key
                setupEncryption();

                # set http_debug flag if QoreDebug option is set
                if (runtimeProp.QoreDebug)
                    http_debug = True;

                eventLog = new QorusLogWebSocketHandler();

                alerts = new AlertManager();

                pmonitor = new QorusPollingConnectionMonitor();

                ConnectionsServer::initLogger();

                # initialize data providers
                postInit(options.get(PostInitOptions), logger);

                # set transient alert buffer size
                alerts.setTransientMax(options.get("transient-alert-max"));

                # create event manager
                try {
                    events = new QorusEventManager(options.get("max-events"));
                } catch (hash<ExceptionInfo> ex) {
                    logError("startup error: %s", get_exception_string(ex));
                    string desc = !debug_system ? sprintf("%s: %s", ex.err, ex.desc) : get_exception_string(ex);
                    sendStartupMsg("%s", desc);
                    sendStartupMsg("Please correct the above error and try again - the system was NOT started");
                    sendStartupComplete(False);
                    stopEventThread();
                    exit(QSE_EVENT_ERROR);
                }

                # exit if OMQ db schemas cannot be opened
                try {
                    if (!exists options.get("systemdb")) {
                        throw "DATASOURCE-ERROR", "ERROR: no definition provided for system datasource ('systemdb') in options file, aborting";
                    }
                    openSystemDatasources();
                } catch (hash<ExceptionInfo> ex) {
                    logError("startup error: %s", get_exception_string(ex));
                    sendStartupMsg("cannot open system datasources: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                    sendStartupComplete(False);
                    stopEventThread();
                    exit(QSE_DATASOURCE);
                }

                try {
                    # create system audit object
                    audit = new AuditLocal(sqlif, options.get("audit"));
                } catch (hash<ExceptionInfo> ex) {
                    logError("startup error: %s", get_exception_string(ex));
                    string desc = !debug_system ? sprintf("%s: %s", ex.err, ex.desc) : get_exception_string(ex);
                    sendStartupMsg("%s", desc);
                    sendStartupMsg("Please correct the above error and try again - the system was NOT started");
                    sendStartupComplete(False);
                    stopEventThread();
                    exit(QSE_EVENT_ERROR);
                }

                # initialize Datasource manager object (for table cache) before recovery so that
                # persistent table objects can be used in session recovery
                try {
                    dsmanager = new DatasourceManager(connDeps, new SqlUtil::Table(omqp, "connections").getTable(),
                        new SqlUtil::Table(omqp, "connection_tags").getTable(), infoLogging, omqp, NOTHING, connection_rwl);
                } catch (hash<ExceptionInfo> ex) {
                    logError("startup error: %s", get_exception_string(ex));
                    sendStartupMsg("Unable to initialize datasource cache: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                    sendStartupComplete(False);
                    stopEventThread();

                    exit(QSE_STARTUP_ERROR);
                }

                # get "omquser" datasource info if it exists to set system info
                try {
                    omquser_info = getDsInfo(dsmanager.getDedicated("omquser"));
                } catch (hash<ExceptionInfo> ex) {
                    # ignore exceptions
                }

                # setup session and recover last session if necessary
                try {
%ifdef Unix
                    # add UNIX domain server in /tmp
                    if (is_writable("/tmp")) {
                        hash<auto> socket_info;
                        unix_socket_path = sprintf("/tmp/qorus-sock-%s", options.get("instance-key"));
                        if (is_socket(unix_socket_path) && Session::checkLastInstance("", unix_socket_path, \socket_info))
                            Session::throwServerAliveException(socket_info, "start a new instance");
                        # in Qorus 4.0, the "http-server" option may not be set, so we need to ensure
                        # that we generate a list with no extra empty entries, and that "us" is the
                        # last entry in the list
                        softlist hsl = options.get("http-server");
                        hsl += unix_socket_path;
                        options.set({"http-server": hsl});
                    }
%endif
                    # issue #2304: if we are recovering a session, then ensure that all orders for workflows previously
                    # running in a separate process with open = 1 where remote is now = 0 are recovered immediately
                    int rows = sqlif.sessionRecoverUpdatedWorkflows(rwfh);
                    if (rows) {
                        logInfo("non-remote workflow sessions forced closed for recovery: %d", rows);
                    }

                    session = new CoreServerSession(recovery_sessionid);
                    session.open(audit);
                    QDBG_ASSERT(!recovery_sessionid || recovery_sessionid == session.getID());
                } catch (hash<ExceptionInfo> ex) {
                    logError("startup error: %s", get_exception_string(ex));
                    string err;
                    # if another session of this instance is running and alive, then print status and exit without an error
                    if (ex.arg) {
                        err = sprintf("%s: %s", ex.err, ex.desc);
                    } else {
                        err = !debug_system
                            ? sprintf("Unable to open session: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc)
                            : get_exception_string(ex);
                    }
                    sendStartupMsg("%s", err);
                    sendStartupComplete(False);
                    stopEventThread();
                    exit(ex.arg ? 0 : QSE_SESSION_ERROR);
                }

                audit.systemStartup();

                # load the metadata cache
                try {
                    # initialize metadata cache and start the SLA thread
                    qmm.init();
                } catch (hash<ExceptionInfo> ex) {
                    logError("startup error: %s", get_exception_string(ex));
                    sendStartupMsg("Unable to initialize metadata cache: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                    sendStartupMsg("%s", Util::get_exception_string(ex));
                    sendStartupComplete(False);
                    stopEventThread();
                    exit(QSE_STARTUP_ERROR);
                }

                try {
                    # initialize error manager
                    EM = new ServerErrorManager(sqlif, sub(string msg) { logInfo("OMQ: " + vsprintf(msg, argv)); });

                    events.postSystemStartup();

                    rbac.init();
                } catch (hash<ExceptionInfo> ex) {
                    logError("startup error: %s", get_exception_string(ex));
                    string desc = !debug_system ? sprintf("%s: %s", ex.err, ex.desc) : get_exception_string(ex);
                    sendStartupMsg("%s", desc);
                    sendStartupMsg("Please correct the above error and try again - the system was NOT started");
                    sendStartupComplete(False);
                    stopEventThread();
                    exit(QSE_RBAC_ERROR);
                }

                # display instance info
                sendStartupMsg("starting instance %s on %s@%s (%s) with session ID %d", options.get("instance-key"),
                    omqp.getUserName(), omqp.getDBName(), omqp.getDriverName(), session.getID());
                sendStartupMsg("system starting at %s", now_us().format("YYYY-MM-DD HH:mm:SS.xx"));
                sendStartupMsg("auditing: %s", audit.getDescription());

                # display HTTP server info
                showListeners("HTTP", "http-server");
                showListeners("HTTPS", "http-secure-server");

                # initialize authenticators for authentication label values
                QorusParametrizedAuthenticator::initializeAuthenticators();
            }

            # start the server
            startQorus();
        } catch (hash<ExceptionInfo> ex) {
            logError("%s", get_exception_string(ex));
            rethrow;
        }
    }

    private doAuthStart() {
        if (opts.independent) {
            return;
        }
        return AbstractQorusDistributedProcess::doAuthStart();
    }

    *hash<LoggerParams> makeLoggerParams(*hash<auto> input_params, string type, *string name) {
        return QorusMasterCoreQsvcCommon::makeLoggerParams(options.get(), input_params, type, name);
    }

    #! Returns the initial loggerid for the omq datasource
    *softint getInitialOmqLoggerId() {
        if (opts.independent) {
            return getLoggerId(QDP_NAME_QDSP, "omq");
        } else {
            return ENV.OMQ_LOGGERID;
        }
    }

    #! Creates the initial logger if no logger parameters are provided
    private createInitialLogger() {
        # set global application variable
        Qorus = self;

        if (map $1, ARGV, $1 == "-I" || $1 == "--independent") {
            # initialize options
            initIndependentOptions();
            openIndependentQorusDatasource(options.get("systemdb"));
            *hash<LoggerParams> params = QorusMasterCoreQsvcCommon::getLoggerParams(QDP_NAME_QORUS_CORE);
            if (params) {
                logger = createLogger(params);
                return;
            }
        }
        AbstractQorusDistributedProcess::createInitialLogger();
    }

    #! Initializes system options and sets node address
    private initIndependentOptions() {
        options.beginInit();
        hash<auto> qorus_options = options.get();
        hash<string, bool> local_addresses;
        node = QorusMasterCoreQsvcCommon::getNodeInfo(qorus_options, \local_addresses);

        # in case qorus-core is started manually on the same machine as other node processes, we add a prefix here
        # as is also done in qorus-master to make the name unique
        if (opts.independent && node != QDP_NAME_QORUS_CORE) {
            node = QDP_NAME_QORUS_CORE + "-" + node;
        }

        self.local_addresses = keys local_addresses;
        options.finalizeInit();
    }

    #! Processes cmd-line args, sets up the NetworkKeyHelper and sets up the connection to the active master
    private doInitialConfig(reference<list<string>> p_argv) {
        try {
            # set global application variable
            Qorus = self;

            if (!opts.independent) {
                AbstractQorusDistributedProcess::doInitialConfig(\p_argv);

                *string url = shift p_argv;
                *string sessionid = shift p_argv;
                *string rwfl = shift p_argv;
                *string rsvcl = shift p_argv;
                *string rjobl = shift p_argv;
                *string rdspl = shift p_argv;
                if (!exists url || !exists sessionid || !exists rwfl || !exists rsvcl || !exists rjobl
                    || !exists rdspl)
                    usage();

                rwfh = getProcessHash(rwfl);
                rsvch = getProcessHash(rsvcl);
                rjobh = getProcessHash(rjobl);

                master_pub_url = url;
                if (sessionid != "-") {
                    recovery_sessionid = sessionid.toInt();
                }

                if (rdspl != "-") {
                    rdsph = getProcessHash(rdspl);
                }

                return;
            }

            # options are initialized in createInitialLogger(), which is called first
            hash<auto> qorus_options = options.get();
            QDBG_ASSERT(local_addresses);

            # setup encryption
            try {
                nkh = new NetworkKeyHelper(qorus_options);

                # check for sensitive data keys; Qorus cannot start if these are not set properly
                NetworkKeyHelper::getKey("sensitive data", qorus_options."sensitive-data-key");
                NetworkKeyHelper::getKey("sensitive value", qorus_options."sensitive-value-key");
            } catch (hash<ExceptionInfo> ex) {
                stderr.printf("%s: %s\n", ex.err, ex.desc);
                exit(QSE_OPTION_ERROR);
            }

            name = QDP_NAME_QORUS_CORE;
            client_id = "-";

            # open omqds Datasource
            openIndependentQorusDatasource(options.get("systemdb"));

            # start the server event thread
            startEventThread();

            # check if any interface processes are already running
            # NOTE: QorusMasterCoreQsvcCommon::getTable() uses a direct Datasource and not the qdsp process
            AbstractTable cluster_processes = getTable("cluster_processes");
            if (cluster_processes.selectRow({
                "where": {
                    "process_type": op_in(QDP_NAME_QWF, QDP_NAME_QSVC, QDP_NAME_QJOB),
                },
                "limit": 1,
            })) {
                restarted = True;
            } else {
                restarted = False;
            }

            # start memory / load monitor thread
            monitor_cnt.inc();
            background monitor();

            waitForActiveMaster();
        } catch (hash<ExceptionInfo> ex) {
            logError("startup error: %s", get_exception_string(ex));
            stderr.printf("%s: %s\n", ex.err, ex.desc);
            exit(QSE_STARTUP_ERROR);
        }
    }

    private waitForActiveMaster() {
        # NOTE: QorusMasterCoreQsvcCommon::getTable() uses a direct Datasource and not the qdsp process
        AbstractTable cluster_processes = getTable("cluster_processes");

        string ds_desc = get_ds_desc(omqds.getConfigHash(), DD_SHORT);

        # where active_master = 1
        hash<DataProviderExpression> cond_orig = <DataProviderExpression>{
             "exp": DP_SEARCH_OP_EQ,
             "args": (
                <DataProviderFieldReference>{"field": "active_master"},
                1,
             ),
        };

        hash<DataProviderExpression> cond = cond_orig;

        date master_timeout;
        # make sure we get a new active master
        if (master_proc_info) {
            # where active_master = 1 and (pid != <pid> or host != <host>)
            cond = <DataProviderExpression>{
                "exp": DP_OP_AND,
                "args": (
                    cond,
                    <DataProviderExpression>{
                        "exp": DP_OP_OR,
                        "args": (
                            <DataProviderExpression>{
                                "exp": DP_SEARCH_OP_NE,
                                "args": (
                                    <DataProviderFieldReference>{"field": "pid"},
                                    master_proc_info.pid,
                                ),
                            },
                            <DataProviderExpression>{
                                "exp": DP_SEARCH_OP_NE,
                                "args": (
                                    <DataProviderFieldReference>{"field": "host"},
                                    master_proc_info.host,
                                ),
                            },
                        ),
                    },
                ),
            };

            master_timeout = now_us() + MasterRestartTimeout;
        }

        # wait for an active master process to run
        *hash<auto> master_row;
        date start;
        QorusRestartableTransaction trans();
        while (True) {
            if (terminate) {
                logInfo("process has received a termination signal; exiting");
                exit(1);
            }
            try {
                if (master_timeout && now_us() > master_timeout) {
                    delete master_timeout;
                    cond = cond_orig;
                    QDBG_LOG("active master restart timeout expired; any active master including the last is "
                        "eligible");
                }
                QDBG_LOG("master query: %y", cond);
                master_row = cluster_processes.selectRow({"where": cond});
                QDBG_LOG("result: %y", master_row);
                if (!master_row) {
                    if (start && ((now_us() - start) > 1m)) {
                        remove start;
                    }
                    if (!start) {
                        logInfo("waiting for an active master process to start in %y", ds_desc);
                        start = now_us();
                    }
                    sleep(MasterPollingInterval);
                    continue;
                }
            } catch (hash<ExceptionInfo> ex) {
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }

            string master_id = qmaster_get_process_name(master_row.node);
            list<string> master_urls = master_row.queue_urls.split(",");
            setUrls(master_id, master_urls);

            # create connection to master
            master = new QorusMasterClient(self, master_row.node, name);

            logInfo("found active master %y with URLs %y", master_id, master_urls);

            # wait for binds on primary ZeroMQ interfaces to be done in the background
            bind_cnt.waitForZero();
            QDBG_LOG("bind done");

            # register qorus-core with master
            try {
                hash<MemorySummaryInfo> mem_info = Process::getMemorySummaryInfo();
                hash<auto> info = {
                    "id": QDP_NAME_QORUS_CORE,
                    "node": node,
                    "child_urls": binds,
                    "host": gethostname(),
                    "pid": getpid(),
                    "restarted": restarted,
                    "vsz": mem_info.vsz,
                    "rss": mem_info.rss,
                    "priv": mem_info.priv,
                    "node_info": getNodeMemoryInfo(),
                    "mem_history": mem_history,
                    "proc_history": (map ("count": 1, "timestamp": $1.timestamp), mem_history),
                };
                QDBG_LOG("registering with master (timeout: %y): %y", MasterRegistrationTimeout, info);
                hash<auto> mr_info = qorus_cluster_deserialize(master.sendCheckResponse(
                    CPC_MR_REGISTER_QORUS_CORE, info, CPC_OK, MasterRegistrationTimeout)[0]);
                QDBG_LOG("qorus-master registration response: %y", mr_info);

                master_proc_info = mr_info.info;

                rwfh = mr_info.rwfh;
                rsvch = mr_info.rsvch;
                rjobh = mr_info.rjobh;

                master_pub_url = mr_info.pub_url;
                if (mr_info.sessionid) {
                    recovery_sessionid = mr_info.sessionid;
                }

                startHeartbeatThread();
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "TRY-AGAIN") {
                    logInfo("active master is busy; retrying: %s: %s", ex.err, ex.desc);
                } else {
                    logError("failed to register with the active master: retrying: %s", get_exception_string(ex));
                }
                sleep(MasterBusyRetryInterval);
                continue;
            }
            break;
        }
    }

    #! Starts the heartbeat thread
    private startHeartbeatThread() {
        heartbeat_thread_cnt.inc();
        background heartbeatThread();
    }

    #! Stop heartbeat thread
    private stopHeartbeatThread() {
        {
            heartbeat_mutex.lock();
            on_exit heartbeat_mutex.unlock();
            heartbeat_cond.signal();
        }

        if (heartbeat_thread_cnt.getCount()) {
            log(LoggerLevel::INFO, "waiting for heartbeat thread to stop");
        }
        heartbeat_thread_cnt.waitForZero();
    }

    #! Update the heartbeat in the cluster_processes row
    private heartbeatThread() {
        on_exit {
            heartbeat_thread_cnt.dec();
            log(LoggerLevel::DEBUG, "stopped heartbeat thread");
        }
        log(LoggerLevel::DEBUG, "started heartbeat thread");

        while (!shutting_down) {
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    # NOTE: QorusMasterCoreQsvcCommon::getTable() uses a direct Datasource and not the qdsp process
                    AbstractTable cluster_processes = getTable("cluster_processes");

                    on_error cluster_processes.rollback();
                    on_success cluster_processes.commit();

                    date now = now_us();
                    # update heartbeat for our row only
                    int rowcount = cluster_processes.update({
                        "heartbeat": now,
                    }, {
                        "process_network_id": QDP_NAME_QORUS_CORE,
                        "node": node,
                        "pid": getpid(),
                    });
                    QDBG_LOG("heartbeat update: %y (updated: %d)", now, rowcount);
                    if (!rowcount) {
%ifdef QorusDebugInternals
                        *hash<auto> row = cluster_processes.selectRow({
                            "where": {
                                "process_network_id": QDP_NAME_QORUS_CORE,
                            },
                        });
                        QDBG_LOG("row: %y node: %y pid: %y", row{"node", "pid"}, node, getpid());
%endif

                        # our row has been deleted; terminate immediately
                        log(LoggerLevel::INFO, "no cluster_processes row exists for the qorus-core process; "
                            "terminating immediately");
                        sleep(1);
                        exit(1);
                    }
                } catch (hash<ExceptionInfo> ex) {
                    if (trans.restartTransaction(ex)) {
                        continue;
                    }
                    log(LoggerLevel::ERROR, "%s", get_exception_string(ex));
                }
                break;
            }

            # wait for next poll interval
            {
                heartbeat_mutex.lock();
                on_exit heartbeat_mutex.unlock();

                QorusSharedApi::waitCondition(heartbeat_cond, heartbeat_mutex, HeartbeatInterval, \shutting_down);
            }
        }
    }

    checkResetDatasource(string server_name, hash<auto> ex) {
        if (ds_error_needs_reset(ex)) {
            dsmanager.errorResetDsBackground(server_name, ex);
        }
    }

    updateLoggerParams(*hash<LoggerParams> params) {
        AbstractQorusDistributedProcess::updateLogger(substituteLogFilename(params,
            LoggerController::getLoggerSubs("qorus-core")));
    }

    *hash<auto> getMapperMap() {
        return qmm.getMapperMap();
    }

    private startSubThread() {
        # start the master SUB thread subscriber
        master_pub_cnt.inc();
        background masterSubThread();
    }

    private stopSubThread() {
        # stop master SUB thread subscriber thread
        sub_run = False;
        master_pub_cnt.waitForZero();
    }

    int getSessionId() {
        return session.getID();
    }

    # acquires the master publisher URL if possible and then returns
    # also returns if the subscriber thread should be shut down
    private waitForMasterPublisherUrl() {
        while (sub_run) {
            try {
                # we have to use low-level APIs to send the request and get the response
                # as we need to poll for "sub_run == False" in case the qorus process dies
                # and the qorus-core process should exit
                # connections can be reused, but the identity must be unique
                Queue response_queue();
                master.sendApiCmdIntern(response_queue, CPC_GET_INFO);

                # poll for reply
                while (sub_run) {
                    # poll for data; check for sub thread stop condition on every poll cycle
                    string cmd;
                    try {
                        cmd = response_queue.get(DefaultSubscriberPollingInterval);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "QUEUE-TIMEOUT") {
                            continue;
                        }
                        rethrow;
                    }

                    list<string> msgs = (cmd,);
                    while (exists (*string msg = response_queue.get())) {
                        msgs += msg;
                    }
                    msgs = master.checkResponseMsg(CPC_GET_INFO, CPC_OK, master.processDataQueueMsg(msgs));
                    hash<auto> h = qorus_cluster_deserialize(msgs[0]);
                    master_pub_url = h.pub_url;
                    logInfo("got new master PUB URL %y", master_pub_url);
                    return;
                }
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "CLIENT-ABORTED") {
                    logError("connection to master interrupted; retrying");
                    continue;
                }
                if (!master) {
                    logFatal("fatal error: master no longer exists; exiting");
                    exit(QSS_ERROR);
                }
                logFatal("fatal error: unexpected exception retrieving master PUB URL: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                sub_run = False;
                break;
            }
        }
    }

    private checkAlertLimits() {
        # check nofile if there is a limit in place
        if (NofileAlertLimit > 0) {
            softint current_nofile = QorusSharedApi::getCurrentNoFile();
            #QDBG_LOG("checkAlertLimits() nofile: %d / %d nproc: %d / %d", current_nofile, NofileAlertLimit, num_threads(), NprocAlertLimit);
            if (current_nofile > NofileAlertLimit) {
                if (!nofile_alert) {
                    # raise an ongoing alert for this process
                    ActionReason r(NOTHING, sprintf("number of descriptors (%d) has exceeded the buffer limit (%d) "
                        "calculated as 80%% of the \"nofile\" system limit (%d)",
                        current_nofile, NofileAlertLimit, QorusSharedApi::getNofile()));
                    hash<auto> info = {
                        "current-nofile": current_nofile,
                        "system-nofile": QorusSharedApi::getNofile(),
                    };
                    alerts.raiseOngoingAlert(r, "PROCESS", name, "DESCRIPTOR-LIMIT", info);
                    nofile_alert = True;
                }
            } else if (nofile_alert) {
                alerts.clearOngoingAlert("PROCESS", name, "DESCRIPTOR-LIMIT");
                nofile_alert = False;
            }
        }

        # check nproc (number of threads: num_threads()) if there is a limit in place
        if (NprocAlertLimit > 0) {
            if ((int threads = num_threads()) > NprocAlertLimit) {
                if (!nproc_alert) {
                    # raise an ongoing alert for this process
                    ActionReason r(NOTHING, sprintf("number of threads (%d) has exceeded the buffer limit (%d) "
                        "calculated as 80%% of the \"nproc\" system limit (%d)",
                        threads, NprocAlertLimit, QorusSharedApi::getNproc()));
                    hash<auto> info = {
                        "current-nproc": threads,
                        "system-nproc": QorusSharedApi::getNproc(),
                    };
                    alerts.raiseOngoingAlert(r, "PROCESS", name, "THREAD-LIMIT", info);
                    nproc_alert = True;
                }
            } else if (nofile_alert) {
                alerts.clearOngoingAlert("PROCESS", name, "THREAD-LIMIT");
                nproc_alert = False;
            }
        }
    }

    private masterSubThread() {
        on_exit {
            logInfo("terminating master SUB thread");
            master_pub_cnt.dec();
        }

        # create a subscriber thread subscribed to all messages
        ZSocketSub master_sub = getMasterSubscriber();

        logInfo("master SUB thread listening to PUB events on %y", master_pub_url);

        # set up polling for response
        list<hash<ZmqPollInfo>> nl(new hash<ZmqPollInfo>({
            "socket": master_sub,
            "events": ZMQ_POLLIN,
        }));

        int cycle = 0;
        while (sub_run) {
            try {
                on_exit {
                    # issue #2732: check limits and raise/clear alerts if necessary
                    ++cycle;
                    if (cycle == 4) {
                        checkAlertLimits();
                        cycle = 0;
                    }
                }

                # poll for data; check for sub thread stop condition on every poll cycle
                list<auto> l = ZSocket::poll(nl, DefaultSubscriberPollingInterval);
                if (!l) {
                    continue;
                }

                ZMsg msg = master_sub.recvMsg();
                string cmd = msg.popStr();

                QDBG_LOG("got SUB cmd: %y", cmd);

                if (!events) {
                    continue;
                }

                switch (cmd) {
                    case CPC_MR_PUB_PROCESS_STARTED: {
                        hash<auto> process_info = qorus_cluster_deserialize(msg);
                        events.postProcessStarted(process_info);
                        qmm.updateProcess(process_info);
                        break;
                    }
                    case CPC_MR_PUB_PROCESS_STOPPED: {
                        hash<auto> process_info = qorus_cluster_deserialize(msg);
                        events.postProcessStopped(process_info);
                        if (alerts) {
                            alerts.processStopped(process_info);
                        }
                        # issue #3569: do not remove qsvc processes here; they are removed in processAbortedImpl()
                        if (process_info.id !~ /^qsvc-/) {
                            qmm.removeProcess(process_info.id);
                        }
                        break;
                    }
                    case CPC_MR_PUB_PROCESS_START_ERROR: {
                        hash<auto> process_info = qorus_cluster_deserialize(msg);
                        events.postProcessStartError(process_info);
                        if (alerts) {
                            alerts.processStopped(process_info);
                        }
                        break;
                    }
                    case CPC_MR_PUB_PROCESS_MEMORY_CHANGE: {
                        hash<auto> process_info = qorus_cluster_deserialize(msg);
                        events.postProcessMemoryChanged(process_info);
                        if (alerts) {
                            alerts.checkProcessMemory(process_info);
                        }
                        qmm.updateProcessMemory(process_info.id, process_info);
                        break;
                    }
                    case CPC_MR_PUB_NODE_INFO: {
                        hash<auto> process_info = qorus_cluster_deserialize(msg);
                        events.postProcessNodeInfo(process_info);
                        break;
                    }
                    case CPC_MR_PUB_NODE_REMOVED: {
                        hash<auto> process_info = qorus_cluster_deserialize(msg);
                        events.postProcessNodeRemoved(process_info);
                        break;
                    }
                    # ignore all other messages
                }
            } catch (hash<ExceptionInfo> ex) {
                # if the master has died or a master handover has taken place, get the new master PUB URL
                if (ex.err == "ZSOCKET-CONTEXT-ERROR") {
                    delete master_sub;
                    waitForMasterPublisherUrl();
                    try {
                        master_sub = getMasterSubscriber();
                        nl[0] = new hash<ZmqPollInfo>((
                            "socket": master_sub,
                            "events": ZMQ_POLLIN,
                        ));
                        continue;
                    } catch (hash<ExceptionInfo> ex1) {
                        ex = ex1;
                    }
                }
                # otherwise treat as a fatal error to the subscriber thread and terminate the thread
                logFatal("fatal error in master subscriber thread: %s", get_exception_string(ex));
                break;
            }
        }
    }

    private ZSocketSub getMasterSubscriber() {
        ZSocketSub sock(master.getContext(), ">" + master_pub_url, "MR-PUB-PROCESS");
        sock.subscribe("MR-PUB-NODE");
        return sock;
    }

    waitForStartup() {
        startup_cnt.waitForZero();
    }

    sendStartupMsg(string msg) {
        master.checkResponseMsg(CPC_MR_STARTUP_MSG, CPC_ACK, master.sendCmdSerialized(CPC_MR_STARTUP_MSG, vsprintf(msg, argv)));
    }

    sendStartupComplete(bool ok) {
        master.sendCheckResponse(CPC_MR_STARTUP_COMPLETE, {"ok": ok, "pid": getpid(), "status": QSS_NORMAL}, CPC_ACK);
        if (ok) {
            startup_cnt.dec();
        }
    }

    sendShutdownMsg(string msg) {
        try {
            master.checkResponseMsg(CPC_MR_SHUTDOWN_MSG, CPC_ACK, master.sendCmdSerialized(CPC_MR_SHUTDOWN_MSG, vsprintf(msg, argv)));
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("error sending shutdown msg: %s: %s: %s", ex.err, ex.desc, msg);
        }
    }

    sendShutdownComplete() {
        try {
            master.sendCheckResponse(CPC_MR_SHUTDOWN_COMPLETE, {}, CPC_ACK);
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("error sending shutdown complete msg: %s: %s", ex.err, ex.desc);
        }
    }

    # starts a datasource pool process
    hash<auto> startDatasourcePoolProcess(string dsname, hash<auto> dh, *bool sys = False) {
        string connstr = get_ds_desc(dh, DD_WITH_PASSWORD);
        #QDBG_LOG("startDatasourcePoolProcess() %y: dh: %y connstr: %y", dsname, dh, connstr);
        # tell master to start process
        # set URLs with an empty URL list
        string dsp_id = qdsp_get_process_name(dsname);
        *hash<LoggerParams> logger_params = loggerController.getLoggerParamsSubs("qdsp", <LogFilenameSubs>{
            "name": dsname,
            "instance": options.get("instance-key"),
            "path": options.get("logdir") + DirSep
        }, dsname);
        try {
            setUrls(dsp_id);
            on_error unblockClientRequests(dsp_id, True);
            *list<string> msgs = master.sendCheckResponse(CPC_MR_START_DSP, {
                "name": dsname,
                "connstr": connstr,
                "logger_params": logger_params,
            }, CPC_OK);
            hash<auto> start_info = qorus_cluster_deserialize(msgs[0]);
            QDBG_ASSERT(start_info.info.id == dsp_id);
            # update process in map
            qmm.updateProcess(start_info.info);
            # update URLs only if not already updated
            updateUrlsConditional(start_info.info);
            # clear any ongoing alert
            alerts.clearProcessStartError(dsp_id);
            # issue #3712: when starting the system "omq" datasource pool, send out a notification to all processes
            # that the system pool has been started
            master.broadcastToAllInterfacesDirect("systemPoolStarted", start_info.info, start_info.started,
                start_info.already_started);
            return start_info;
        } catch (hash<ExceptionInfo> ex) {
            # raise an ongoing alert
            if (dsname != "omq") {
                alerts.raiseProcessStartError(dsp_id, ex);
            }
            rethrow;
        }
    }

    # starts a workflow process
    hash<auto> startWorkflowProcess(Workflow wf) {
        string wf_id = qwf_get_process_name(wf.name, wf.version, wf.workflowid);
        hash<auto> ch = {
            "name": wf.workflowid.toString(),
            "wfname": wf.name,
            "wfversion": wf.version,
            "sessionid": getSessionId(),
            "logger_params": loggerController.getLoggerParamsSubs("workflows", <LogFilenameSubs>{
                "name": wf.name,
                "id": wf.workflowid.toString(),
                "version": wf.version,
            }, wf.workflowid),
            "stack_size": Qorus.qmm.lookupWorkflow(wf.workflowid)."runtime-options"."stack-size" ?? 0,
        };
        try {
            # register the process if it's not already registered
            updateUrlsConditional(wf_id, new list<string>());
            *list<string> msgs = master.sendCheckResponse(CPC_MR_START_WF, ch, CPC_OK);
            hash<auto> start_info = qorus_cluster_deserialize(msgs[0]);
            QDBG_ASSERT(start_info.info.id == wf_id);
            # update process in map
            qmm.updateProcess(start_info.info);
            # update URLs only if not already updated
            updateUrlsConditional(start_info.info);
            # mark interface as started
            markInterfaceStarted(start_info.info, start_info.already_started, start_info.started);
            # clear any ongoing alert
            alerts.clearProcessStartError(wf_id);
            return start_info;
        } catch (hash<ExceptionInfo> ex) {
            # raise an ongoing alert
            alerts.raiseProcessStartError(wf_id, ex);
            rethrow;
        }
    }

    # starts a service process
    hash<auto> startServiceProcess(AbstractQorusService svc) {
        hash<auto> ch = {
            "name": svc.serviceid.toString(),
            "svctype": svc.type,
            "svcname": svc.name,
            "svcversion": svc.version,
            "logger_params": loggerController.getLoggerParamsSubs("services", <LogFilenameSubs>{
                "name": svc.name,
                "id": svc.serviceid.toString(),
                "version": svc.version,
            }, svc.serviceid),
            "stack_size": Qorus.qmm.lookupService(svc.serviceid)."runtime-options"."stack-size" ?? 0,
        };
        string svc_id = qsvc_get_process_name(svc.type, svc.name, svc.version, svc.serviceid);
        try {
            # register the process if it's not already registered
            updateUrlsConditional(svc_id, new list<string>());
            *list<string> msgs = master.sendCheckResponse(CPC_MR_START_SVC, ch, CPC_OK);
            hash<auto> start_info = qorus_cluster_deserialize(msgs[0]);
            QDBG_ASSERT(start_info.info.id == svc_id);
            # update process in map
            qmm.updateProcess(start_info.info);
            # update URLs only if not already updated
            updateUrlsConditional(start_info.info);
            # mark interface as started
            markInterfaceStarted(start_info.info, start_info.already_started, start_info.started);
            # clear any ongoing alert
            alerts.clearProcessStartError(svc_id);
            return start_info;
        } catch (hash<ExceptionInfo> ex) {
            # raise an ongoing alert
            alerts.raiseProcessStartError(svc_id, ex);
            rethrow;
        }
    }

    # starts a job process
    hash<auto> startJobProcess(AbstractQorusJob job) {
        int jobid = job.getId();
        hash<auto> ch = {
            "name": jobid.toString(),
            "jobname": job.getName(),
            "jobversion": job.getVersion(),
            "sessionid": getSessionId(),
            "logger_params": loggerController.getLoggerParamsSubs("jobs", <LogFilenameSubs>{
                "name": job.getName(),
                "id": jobid.toString(),
                "version": job.getVersion(),
            }, jobid),
            "stack_size": Qorus.qmm.lookupJob(jobid)."runtime-options"."stack-size" ?? 0,
        };
        string job_id = qjob_get_process_name(job.getName(), job.getVersion(), jobid);
        try {
            # register the process if it's not already registered
            updateUrlsConditional(job_id, new list<string>());
            *list<string> msgs = master.sendCheckResponse(CPC_MR_START_JOB, ch, CPC_OK);
            hash<auto> start_info = qorus_cluster_deserialize(msgs[0]);
            QDBG_ASSERT(start_info.info.id == job_id);
            # update process in map
            qmm.updateProcess(start_info.info);
            # update URLs only if not already updated
            updateUrlsConditional(start_info.info);
            # mark interface as started
            markInterfaceStarted(start_info.info, start_info.already_started, start_info.started);
            # clear any ongoing alert
            alerts.clearProcessStartError(job_id);
            return start_info;
        } catch (hash<ExceptionInfo> ex) {
            # raise an ongoing alert
            alerts.raiseProcessStartError(job_id, ex);
            rethrow;
        }
    }

    detachProcess(hash<ClusterProcInfo> h) {
        detachProcess(h.id);
    }

    detachProcess(string process_id) {
        QDBG_LOG("detaching process: %y", process_id);
        # tell master to stop process
        date stop_timestamp = now_us();
        # remove URLs for process
        removeUrls(process_id, stop_timestamp);
        master.sendCheckResponse(CPC_MR_DETACH_PROCESS, {"name": process_id}, CPC_OK);

        # remove process from map
        qmm.removeProcess(process_id);

        # decrement interface counter for interfaces
        if (process_id !~ /^qdsp/) {
            markInterfaceStopped(process_id, stop_timestamp);
        }
    }

    # called when reocvery for a running interface fails after a qorus-core restart
    detachKillUnregisteredProcess(string process_id) {
        QDBG_LOG("detaching and killing unregistered process: %y", process_id);
        master.sendCheckResponse(CPC_MR_DETACH_KILL_PROCESS, {"name": process_id}, CPC_OK);
    }

    stopProcess(hash<ClusterProcInfo> h) {
        stopProcess(h.id);
    }

    /** issue #2564: always delete AbstractQorusClient objects before stopping the process
        otherwise if the process terminates before it can be stopped, the client I/O thread will get into an infinite
        loop
    */
    stopProcess(string process_id) {
        QDBG_LOG("stopping process: %y", process_id);
        # tell master to stop process
        date stop_timestamp = now_us();
        # remove URLs for process
        removeUrls(process_id, stop_timestamp);
        # only decrement the interface count if the process was really stopped
        # otherwise an abort message has already done the same
        bool stopped = False;
        try {
            master.sendCheckResponse(CPC_MR_STOP_PROCESS, {"name": process_id}, CPC_ACK);
            stopped = True;
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NO-PROCESS") {
                # ignore the case when the process does not exist
                logInfo("ignoring process %y stop error as it does not exist: %s: %s", ex.err, ex.desc);
            } else {
                rethrow;
            }
        }

        # remove process from map
        qmm.removeProcess(process_id);
        # decrement interface counter for interfaces
        if (stopped && process_id !~ /^qdsp/) {
            markInterfaceStopped(process_id, stop_timestamp);
        }
    }

    private:internal markInterfaceStarted(hash<ClusterProcInfo> proc_info, *bool already_started, date started) {
        # marking interface as started
        ix_lock.lock();
        on_exit ix_lock.unlock();

        if (ix_map{proc_info.id}) {
            QDBG_LOG("interface already started: %y: %d", proc_info.id, ix_map.size());
            QDBG_ASSERT(already_started);
        } else {
            QDBG_LOG("marking interface started: %y: %d -> %d", proc_info.id, ix_map.size(), ix_map.size() + 1);
            ix_map{proc_info.id} = True;
        }
        ix_timestamp_map{proc_info.id} = started;
    }

    private:internal markInterfaceStopped(string id, date stop_timestamp, *bool abort) {
        # marking interface as stopped
        ix_lock.lock();
        on_exit ix_lock.unlock();

        if (abort && !ix_map{id}) {
            logInfo("ignoring abort message for %y; not tracked", id);
            return;
        }

        if (stop_timestamp < ix_timestamp_map{id}) {
            QDBG_LOG("ignoring outdated stop msg for %y with timestamp %y; last start: %y", id, stop_timestamp,
                ix_timestamp_map{id});
            return;
        }

        QDBG_LOG("marking interface stopped: %y: %d -> %d", id, ix_map.size(), ix_map.size() - 1);
        QDBG_ASSERT(ix_map{id});
        remove ix_map{id};
        if (!ix_map && ix_waiting) {
            ix_cond.broadcast();
        }
    }

    private:internal waitForInterfaces() {
        ix_lock.lock();
        on_exit ix_lock.unlock();

        while (ix_map) {
            ++ix_waiting;
            ix_cond.wait(ix_lock);
            --ix_waiting;
        }
    }

    /** issue #2647: ignore process abort and disable process restart to avoid race conditions when stopping and restarting
        processes
    */
    ignoreProcessAbort(hash<ClusterProcInfo> proc_info) {
        QDBG_LOG("informing qorus-master to ignore aborts for: %y", proc_info);
        master.sendCheckResponse(CPC_MR_IGNORE_PROCESS_ABORT, {"name": proc_info.id}, CPC_ACK);
    }

    /** issue #2707: implement support for datasource resets
    */
    updateProcessInfo(hash<ClusterProcInfo> proc_info, hash<auto> conn_hash) {
        QDBG_LOG("updating qorus-master with new process config info: %y: %y", proc_info, conn_hash);
        master.sendCheckResponse(CPC_MR_UPDATE_PROCESS_INFO, {"name": proc_info.id, "info": conn_hash}, CPC_ACK);
    }

    runIndependent(hash<ClusterProcInfo> proc_info) {
        QDBG_LOG("informing qorus-master set set run independence for: %y", proc_info);
        master.sendCheckResponse(CPC_MR_RUN_INDEPENDENT, {"name": proc_info.id}, CPC_ACK);
    }

    # required for CryptoKeyHelper
    *string getKeyOption(string opt) {
        return options.get(opt);
    }

    # returns a hash of workflowids for workflows running before qorus-core was started
    hash<string, bool> getRunningWorkflowHash() {
        return rwfh;
    }

    # returns a hash of svcids for services running before qorus-core was started
    hash<string, bool> getRunningServiceHash() {
        return rsvch;
    }

    # returns a hash of jobids for jobs running before qorus-core was started
    hash<string, bool> getRunningJobHash() {
        return rjobh;
    }

    *ErrorDef getError(softstring wfid, string err) {
        return EM.getError(wfid, err);
    }

    saveUpdateWorkflowRemote(list<hash<auto>> wfrl) {
        self.wfrl = wfrl;
    }

    saveUpdateServiceRemote(list<hash<auto>> svcrl) {
        self.svcrl = svcrl;
    }

    saveUpdateJobRemote(list<hash<auto>> jobrl) {
        self.jobrl = jobrl;
    }

    #! calls a method on the RestHandler; waits for initialization if recovering from a qorus-core crash
    auto callRestHandlerMethod(string m) {
        if (!restHandler) {
            startup_cnt.waitForZero();
        }
        return call_object_method_args(restHandler, m, argv);
    }

    hash<auto> getDebugInfo() {
        return {
            "ix_map": ix_map,
        };
    }

    bool getDebugSystemInternals() {
        return options.get("debug-qorus-internals");
    }

    int shutdown() {
        # send a message to the master process to shut down
        master.sendCheckResponse(CPC_STOP, NOTHING, CPC_ACK);
        return 0;
    }

    synchronized private int checkStartShutdown() {
        #QDBG_LOG("calling checkStartShutdown(): %y", shutting_down);
        if (shutting_down) {
            QDBG_LOG("shutdown flag already set");
            return -1;
        }
        QDBG_LOG("set shutdown flag");
        shutting_down = True;
        return 0;
    }

    # may be sent with context information if called from system API
    synchronized int shutdownQorusCore() {
        if (checkStartShutdown()) {
            return -1;
        }
        if (events) {
            events.postSystemShutdown(tld.cx);
        }
        background shutdownIntern(tld.cx);
        return 0;
    }

    static *hash<LoggerParams> getQorusCoreLoggerParams() {
        if (*string logger_str = ENV{"SYSTEM_" + ENV_LOGGER_PARAMS}) {
            seed_logger_map = parse_yaml(logger_str);

            # create logger params for qorus-core
            *hash<auto> info = seed_logger_map.loggerMap{seed_logger_map.loggerAliases."qorus-core"
                ?? seed_logger_map.loggerAliases.system};
            if (info) {
                hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                    "name": "qorus-core",
                    "path": ENV.QORUS_LOGPATH,
                    "instance": ENV.QORUS_INSTANCE,
                };

                # do not call LoggerController::getLoggerSubs() here; use the env vars
                return substituteLogFilename(convert_logger_params(info.params), subs);
            }
        }
    }

    #! Processes a STOP message inline
    private doInlineStop(ZSocketRouter sock, string sender, string mboxid, *hash<auto> msg_hash) {
        logInfo("STOP received from sender %y", sender);

        int rc = shutdownQorusCore();

        if (opts.independent && ((!rc || !stop_info) && msg_hash.wait)) {
            # do not respond until all processes have been shut down
            stop_info = {
                "index": cast<MyRouter>(sock).index,
                "sender": sender,
                "mboxid": mboxid,
            };

            logInfo("shutdown of independent qorus-core process started; sender %y will be notified when complete",
                sender);
            return;
        }

        sock.send(sender, mboxid, CPC_ACK);

        if (rc) {
            logInfo("shutdown already in progress; ignoring message");
        }
    }

    # called when the cluster server process should stop
    # do not terminate the event thread immediately; we terminate manually later in the shutdown process
    private stopServer() {
        shutdownQorusCore();
    }

    # return all Qorus options
    private hash getOptionsImpl() {
        return options.get();
    }

    # return the value of a single Qorus option
    private auto getOptionImpl(string opt) {
        return options.get(opt);
    }

    # must be very short calls or called in the background
    private bool processCmdImpl(ZSocketRouter sock, int index, string sender, string mboxid, string cmd, ZMsg msg) {
        QDBG_LOG("processCmdImpl cmd: %y", cmd);
        try {
            switch (cmd) {
                case CPC_CORE_DSP_TIMEOUT_WARNING: {
                    hash<auto> h = qorus_cluster_deserialize(msg);
                    DatasourceConnection::poolWarning(h.desc, h.time, h.to, h.dsn);
                    # one-way message; no reply is required so we return True without sending a reply
                    return True;
                }

                case CPC_CORE_DSP_EVENT:
                    MonitorSingleton::ds_queue.push(qorus_cluster_deserialize(msg));
                    # one-way message; no reply is required so we return True without sending a reply
                    return True;

                case CPC_CORE_LOG_IF: {
                    hash<auto> h = qorus_cluster_deserialize(msg);
                    QDBG_LOG("if log: sender: %y TID %d index: %y: %y", sender, mboxid, index, h);
                    call_object_method_args(eventLog, h.method, h.args);
                    # one-way message; no reply is required so we return True without sending a reply
                    return True;
                }

                case CPC_CORE_DEBUG_EVENT:
                    hash<auto> h = qorus_cluster_deserialize(msg);
                    QDBG_LOG("debug event: sender: %y TID %d index: %y: %y", sender, mboxid, index, h);
                    switch (h.method) {
                        case "send":
                            debugHandler.handleSendEvent(h.cid, h.args);
                            break;
                        case "broadcast":
                            debugHandler.handleBroadcastEvent(h.args);
                            break;
                    }
                    # one-way message; no reply is required so we return True without sending a reply
                    return True;

                case CPC_CORE_CALL_SUBSYSTEM: {
                    hash<auto> h = qorus_cluster_deserialize(msg);
%ifdef QorusDebugMessages
                    QDBG_LOG("subsystem call: sender: %y TID %d index: %y: %y", sender, mboxid, index, h);
%endif
                    object obj;
                    switch (h.subsystem) {
                        case "options":
                            obj = options;
                            break;
                        case "alerts":
                            # issue #3238: alert commands must be processed in a background thread if auditing is enabled
                            if (!Qorus.audit || Qorus.audit.checkOption(AOC_ALERT_EVENTS)) {
                                background callSubsystem(index, sender, mboxid, h);
                                return True;
                            }
                            obj = alerts;
                            break;
                        case "eventLog":
                            # issue #2584: if the "eventLog" object has not yet been created, then process it in a
                            # background thread
                            if (!eventLog) {
                                background callSubsystem(index, sender, mboxid, h);
                                return True;
                            }
                            obj = eventLog;
                            break;
                        case "events":
                            # issue #2584: if the "events" object has not yet been created, or if a potential blocking
                            # call is being made, then process it in a background thread
                            if (!events || h.method =~ /^get/) {
                                background callSubsystem(index, sender, mboxid, h);
                                return True;
                            }
                            obj = events;
                            break;
                        case "orderStats":
                            obj = orderStats;
                            break;
                        default:
                            background callSubsystem(index, sender, mboxid, h);
                            return True;
                    }

                    if (h.tld) {
                        create_tld();
                        tld.add(h.tld);
                    }
                    on_exit if (h.tld) {
                        delete tld;
                    }

                    # otherwise call it immediately inline
                    auto rv = call_object_method_args(obj, h.method, h.args);
%ifdef QorusDebugMessages
                    QDBG_LOG("subsystem response: sender: %y TID %d index: %y: method: %s.%s(): %y", sender, mboxid,
                        index, h.subsystem, h.method, rv);
%else
                    QDBG_LOG("subsystem response: sender: %y TID %d index: %y: method: %s.%s(): type: %y (size: %d)",
                        sender, mboxid, index, h.subsystem, h.method, rv.type(), rv.size());
%endif
                    sock.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(rv));
                    return True;
                }

                case CPC_CORE_CALL_FUNCTION: {
                    *binary msgbin = msg.popBin();
                    background callFunction(index, sender, mboxid, msgbin);
                    return True;
                }

                case CPC_CORE_CALL_STATIC_METHOD: {
                    *binary msgbin = msg.popBin();
                    background callStaticMethod(index, sender, mboxid, msgbin);
                    return True;
                }

                case CPC_CORE_LOG_AUDIT: {
                    audit.logInfo(msg.popStr());
                    sock.send(sender, mboxid, CPC_OK);
                    return True;
                }

                case CPC_CORE_GET_DEBUG_INFO: {
                    hash<auto> h = getDebugInfo();
                    QDBG_LOG("debug info request: %y", h);
                    sock.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(h));
                    return True;
                }

                case CPC_CORE_GET_SUBSCRIPTIONS: {
                    hash<auto> h = qorus_cluster_deserialize(msg);

                    # issue #2584: if the "eventLog" object has not yet been created, then process it in a background thread
                    if (!eventLog) {
                        background (sub (int index, string sender, string mboxid, *list<string> logs) {
                            try {
                                startup_cnt.waitForZero();
                                QDBG_ASSERT(eventLog);
                                sendAnyResponse(index, sender, mboxid, CPC_OK, eventLog.getSubscriptions(logs));
                            } catch (hash<ExceptionInfo> ex) {
                                logInfo("eventlog exception: sender: %y TID %d index: %y: %s", sender, mboxid, index,
                                    get_exception_string(ex));
                                sendExceptionResponse(index, sender, mboxid, ex);
                            }
                        })(index, sender, mboxid, h.logs);
                    } else {
                        # otherwise process the call inline
                        sock.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(eventLog.getSubscriptions(h.logs)));
                    }
                    return True;
                }

                # only called for independent processes
                case CPC_MR_GET_MEMORY_INFO: {
                    QDBG_ASSERT(opts.independent);
                    # get memory info for the local process
                    hash<auto> process_info = {
                        QDP_NAME_QORUS_CORE: Process::getMemorySummaryInfo(),
                    };
                    # return memory information to caller
                    hash<auto> h = {
                        "process_info": process_info,
                        "node_memory_info": getNodeMemoryInfo(),
                        "mem_history": mem_history,
                        "proc_history": (map ("count": 1, "timestamp": $1.timestamp), mem_history),
                    };
                    sock.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(h));
                    return True;
                }

                case CPC_CORE_GET_SYSTEM_TOKEN: {
                    hash<auto> h = qorus_cluster_deserialize(msg);
                    sock.send(sender, mboxid, CPC_OK, "");
                    return True;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            logError("process call exception: sender: %y TID %d index: %y: %s", sender, mboxid, index,
                get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
            return True;
        }

        return False;
    }

    private callSubsystem(int index, string sender, string mboxid, hash<auto> h) {
        try {
%ifdef QorusDebugMessages
            QDBG_LOG("subsystem call: sender: %y TID %d index: %y: %y", sender, mboxid, index, h);
%endif
            if (h.tld) {
                create_tld();
                tld.add(h.tld);
            }
            auto rv;
            # if qorus-core is restarted while interface processes are running, then
            # we may need to wait until qorus-core has been fully initialized before
            # responding to subsystem requests
            switch (h.subsystem) {
                case "qmm":
                    if (restarted) {
                        Qorus.qmm.waitForInit();
                    }
                    rv = call_object_method_args(qmm, h.method, h.args);
                    break;

                case "SM":
                    if (!SM) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(SM, h.method, h.args);
                    break;

                case "services":
                    if (restarted) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(services, h.method, h.args);
                    break;

                case "events":
                    if (!events) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(events, h.method, h.args);
                    break;

                case "SEM":
                    if (!SEM) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(SEM, h.method, h.args);
                    break;

                case "rbac":
                    rv = call_object_method_args(rbac, h.method, h.args);
                    break;

                case "eventLog":
                    if (!eventLog) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(eventLog, h.method, h.args);
                    break;

                case "EM":
                    if (!EM) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(EM, h.method, h.args);
                    break;

                case "props":
                    rv = call_object_method_args(props, h.method, h.args);
                    break;

                case "control":
                    rv = call_object_method_args(control, h.method, h.args);
                    break;

                case "orders":
                    rv = call_object_method_args(orders, h.method, h.args);
                    break;

                case "dsmanager":
                    if (!dsmanager) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(dsmanager, h.method, h.args);
                    break;

                case "jobManager":
                    rv = call_object_method_args(jobManager, h.method, h.args);
                    break;

                case "connections":
                    if (!connections) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(connections, h.method, h.args);
                    break;

                case "remotemonitor":
                    if (!remotemonitor) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(remotemonitor, h.method, h.args);
                    break;

                case "alerts":
                    if (!alerts) {
                        startup_cnt.waitForZero();
                    }
                    rv = call_object_method_args(alerts, h.method, h.args);
                    break;

                default:
                    throw "UNKNOWN-SUBSYSTEM-ERROR", sprintf("qorus-core subsystem %y is unknown", h.subsystem);
            }
%ifdef QorusDebugMessages
            QDBG_LOG("subsystem response: sender: %y TID %d index: %y: method: %s.%s(): %y", sender, mboxid, index,
                h.subsystem, h.method, rv);
%else
            QDBG_LOG("subsystem response: sender: %y TID %d index: %y: method: %s.%s(): type: %y (size: %d)", sender,
                mboxid, index, h.subsystem, h.method, rv.type(), rv.size());
%endif

            sendAnyResponse(index, sender, mboxid, CPC_OK, rv, h.already_serialized);
        } catch (hash<ExceptionInfo> ex) {
            logError("subsystem exception: sender: %y TID %d index: %y: %s", sender, mboxid, index,
                get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    private callFunction(int index, string sender, string mboxid, data d) {
        try {
            hash<auto> h = qorus_cluster_deserialize(d);
            QDBG_LOG("function call: sender: %y TID %d index: %y: %y", sender, mboxid, index, h);
            if (h.tld) {
                create_tld();
                if (h.tld.svc) {
                    if (!services) {
                        startup_cnt.waitForZero();
                    }
                }
                tld.add(h.tld);
            }
            auto rv = call_function_args(h.name, h.args);
            QDBG_LOG("function response: sender: %y TID %d index: %y: name: %y: %y", sender, mboxid, index, h.name, rv);
            sendAnyResponse(index, sender, mboxid, CPC_OK, rv);
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("DBG: function call: sender: %y TID %d index: %y: d: (%d) %y", sender, mboxid, index, d.size(), d.toString());
            logError("function exception: sender: %y TID %d index: %y: name: %y: %y", sender, mboxid, index, name,
                get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    private callStaticMethod(int index, string sender, string mboxid, data d) {
        try {
            hash<auto> h = qorus_cluster_deserialize(d);
            QDBG_LOG("function call: sender: %y TID %d index: %y: %y", sender, mboxid, index, h);
            if (h.tld) {
                create_tld();
                if (h.tld.svc) {
                    if (!services) {
                        startup_cnt.waitForZero();
                    }
                }
                tld.add(h.tld);
            }
            auto rv = call_static_method_args(h.cname, h.mname, h.args);
            QDBG_LOG("function response: sender: %y TID %d index: %y: name: %y: %y", sender, mboxid, index, h.name, rv);
            sendAnyResponse(index, sender, mboxid, CPC_OK, rv);
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("DBG: function call: sender: %y TID %d index: %y: d: (%d) %y", sender, mboxid, index, d.size(), d.toString());
            logError("function exception: sender: %y TID %d index: %y: name: %y: %y", sender, mboxid, index, name,
                get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    private processAbortNotificationImpl(string process) {
        # mark remote service as aborted
        if (process =~ /^qsvc-/ && services) {
            hash<auto> svcinfo = getServiceInfo(process);
            services.markRemoteServiceAborted(svcinfo.type, svcinfo.name);
        }

        # signal process aborted
        if (abort_map{process}) {
            abort_lck.lock();
            on_exit abort_lck.unlock();

            map $1.dec(), abort_map{process}.values();
            remove abort_map{process};
        }
    }

    #! Decrements the Counter when the given process aborts
    setAbortNotification(string process, Counter cnt) {
        abort_lck.lock();
        on_exit abort_lck.unlock();

        abort_map{process}{cnt.uniqueHash()} = cnt;
    }

    #! Returns True if the Counter is removed for the process
    bool removeAbortNotification(string process, Counter cnt) {
        abort_lck.lock();
        on_exit abort_lck.unlock();

        return exists remove abort_map{process}{cnt.uniqueHash()};
    }

    static hash<auto> getServiceInfo(string process) {
        hash<auto> svcinfo;
        (svcinfo.type, svcinfo.name, svcinfo.svcid, svcinfo.state_label) =
            (process =~ x/^qsvc-([^-]+)-(.+)-v.*-([0-9]+)-(stateful|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/);
        QDBG_LOG("getServiceInfo() %y: %y", process, svcinfo);
        svcinfo.svcid = svcinfo.svcid.toInt();
        return svcinfo;
    }

    # called from the network API when a process has aborted
    private processAbortedImpl(string process, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        QDBG_LOG("DBG: processAbortedImpl() process: %y info: %y restarted: %y abort timestamp: %y", process, info,
            restarted, abort_timestamp);
        if (restarted) {
            QDBG_ASSERT(info);
            if (info.new_active_master_id) {
                # unconditionally assume the name of the old active master that this process knows of
                process = master.getRemoteProcessId();
                logInfo("active master updated from %y -> %y", process, info.new_active_master_id);
            }
            # NOTE: external processes have no queue URLs
            QDBG_ASSERT(!info.new_active_master_id || info.queue_urls);
            if (info.queue_urls) {
                updateUrls(process, info, abort_timestamp);
            }

            # first update process in map
            qmm.updateProcess(info);
            abortedProcessNotification(process, info, restarted, abort_timestamp);

            # if qorus-core has restarted at the same time as a service that is not cached, then tell it to quit
            hash<auto> svcinfo;
            if (process =~ /^qsvc-/ && services) {
                # if qorus-core has been restarted then "services" may not exist
                svcinfo = getServiceInfo(process);
                if (services.handleRestartedService(process, svcinfo.type, svcinfo.name, svcinfo.svcid,
                    abort_timestamp)) {
                    return;
                }
            }

            # recover processes
            switch (process) {
                case =~ /^qwf-/: {
                    string wfid = (process =~ x/-([0-9]+)$/)[0];
                    background Qorus.control.recoverAbortedWorkflow(wfid, restarted, abort_timestamp);
                    break;
                }

                case =~ /^qsvc-/: {
                    if (!services) {
                        if (!svcinfo) {
                            svcinfo = getServiceInfo(process);
                        }
                        logInfo("ignoring service abort message for unloaded %s service %s (%d)", svcinfo.type,
                            svcinfo.name, svcinfo.svcid);
                    }
                    break;
                }

                case =~ /^qjob-/: {
                    softint jobid = (process =~ x/-([0-9]+)$/)[0];
                    if (jobManager) {
                        background jobManager.recoverAbortedJob(jobid, restarted, abort_timestamp);
                    }
                    break;
                }

                case =~ /^qdsp-/: {
                    string name = (process =~ x/^qdsp-(.*)$/)[0];
                    if (dsmanager) {
                        background dsmanager.datasourcePoolProcessAborted(name, restarted, abort_timestamp);
                    }
                    break;
                }

                case =~ /^qorus-master-/: {
                    QDBG_LOG("new: %y old: %y", info.new_active_master_id ?? "n/a", master_proc_info.id);
                    if (process == master_proc_info.id) {
                        QDBG_LOG("updating master_proc_info: %y", info);
                        try {
                            master_proc_info = info;
                        } catch (hash<ExceptionInfo> ex) {
                            QDBG_LOG("%s", get_exception_string(ex));
                        }
                    }
                    break;
                }

                # NOTE: no need to reestablish log subscriptions with qorus-master
                # qorus-master recovers subscriptions itself
            }
        } else {
            QDBG_ASSERT(!info);
            # decrement interface count if necessary
            if (process !~ /^qdsp/) {
                markInterfaceStopped(process, abort_timestamp, True);
            }

            # issue #3643: disable service handlers immediately
            hash<auto> svcinfo;
            bool do_svc_recovery;
            if (process =~ /^qsvc-/ && services) {
                # if qorus-core has been restarted then "services" may not exist
                svcinfo = getServiceInfo(process);
                do_svc_recovery = True;
            }

            # remove URLs for process
            removeUrls(process, abort_timestamp);
            # notify clients that the process failed and that it has not been restarted
            abortedProcessNotification(process, NOTHING, False, abort_timestamp);
            # remove process from map
            qmm.removeProcess(process);

            # recover processes
            switch (process) {
                case =~ /^qwf-/: {
                    # issue #3745: in the qwf process died for anything other than a reset and could not be started
                    string wfid = (process =~ x/^qwf-.+-v.*-([0-9]+)$/)[0];
                    QDBG_ASSERT(wfid);
                    background control.recoverAbortedWorkflow(wfid, False, abort_timestamp);
                    break;
                }

                case =~ /^qsvc-/: {
                    if (do_svc_recovery) {
                        if (!svcinfo) {
                            svcinfo = getServiceInfo(process);
                        }
                        background services.recoverAbortedService(svcinfo.type, svcinfo.name, svcinfo.svcid,
                            svcinfo.state_label, abort_timestamp);
                    }
                    break;
                }

                case =~ /^qjob-/: {
                    softint jobid = (process =~ x/-([0-9]+)$/)[0];
                    background jobManager.recoverAbortedJob(jobid, restarted, abort_timestamp);
                    break;
                }

                case =~ /^qdsp-/: {
                    string name = (process =~ x/^qdsp-(.*)$/)[0];
                    QDBG_LOG("processAbortedImpl() handling qdsp %y; not restarted", name);
                    background dsmanager.datasourcePoolProcessAborted(name, restarted, abort_timestamp);
                    break;
                }
            }
        }
        # issue #2706: debugHandler may not exist when an abort message arrives when qorus-core is restarted
        if (debugHandler) {
            debugHandler.handleAbortedProcess(process);
        }
    }

    private *int usageImpl() {
        stderr.printf("usage: %s [options] <api> <node> <master-node> <master-urls> <interfaces> <network-key-path> "
            "<process-type> <unique-proc-name> <logpath> <restarted> <master-pub-url> <session_id> <running_wfs> "
            "<running_svcs> <running_jobs> <qdsp_recovery_list>\n", get_script_name());
        stderr.printf("this program is not meant to be started by hand\n");
        printOption("-I,--independent", "wait for qorus-master to be started and register independently",
            OffsetColumn);
        return OffsetColumn;
    }

    private processCommandLine() {
        int errors = (foldl $1 + $2, (map setSystemOption($1), ARGV)) ?? 0;

        if (errors) {
            stderr.printf("please correct the error%s above and try again (-h or --help for usage)\n", errors == 1 ? "" : "s");
            exit(QSE_OPTION_ERROR);
        }
    }

    private:internal setupEncryption() {
        try {
            CryptoKeyHelper::setupEncryption();
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "QORUS-ENCRYPTION-ERROR") {
                stderr.print(ex.desc + "\n");
                exit(QSE_STARTUP_ERROR);
            }
        }
    }

    private:internal static hash<string, bool> getProcessHash(string str) {
        return str == "-" ? {} : map {$1: True}, str.split(",");
    }

    *hash getJobStatusCache() {
        return jobSnapshot ? jobSnapshot.getStatusCache() : NOTHING;
    }

    *hash getWfStatusCache() {
        return wfSnapshot ? wfSnapshot.getStatusCache() : NOTHING;
    }

    *hash getJobInterfaceStatusCache() {
        return jobSnapshot ? jobSnapshot.getInterfaceStatusCache() : NOTHING;
    }

    *hash getWfInterfaceStatusCache() {
        return wfSnapshot ? wfSnapshot.getInterfaceStatusCache() : NOTHING;
    }

    *string getUnixSocketPath() {
        return unix_socket_path;
    }
    *string getRemoteFileDir() {
        return remote_file_dir;
    }

    /*
    private:internal eventLogQueueThread() {
        on_exit {
            logInfo("OMQ: event log queue thread exiting");
            event_log_cnt.dec();
        }

        while (*hash h = event_log_queue.get()) {
            call_object_method_args(eventLog, h.method, h.args);
        }
    }
    */

    # start the server
    startQorus() {
        orderStats.start();
        on_error orderStats.shutdown();

        # lock startup-only options
        options.lockOptions(select keys OMQ::omq_option_hash, OMQ::omq_option_hash.$1."startup-only");

        # output initial info to log files
        logInfo("OMQ: " + Banner);

        # install shutdown signal handlers
        set_signal_handler(SIGTERM, \signal_handler());
        set_signal_handler(SIGINT,  \signal_handler());
        set_signal_handler(SIGHUP,  \signal_handler());
        set_signal_handler(SIGUSR2, \signal_handler());
        QDBG_LOG("signal handlers set");

        # initialize global performance caches
        #pcwf = pcm.add(GPC_AllWorkflows);
        #pcsvc = pcm.add(GPC_AllServices);
        #pcjob = pcm.add(GPC_AllJobs);

        # init services infrastructure and load system services
        try {
            # initialize system properties
            props.reload();

            # initialize error manager
            EM.init();

            # api editor
            code editor = hash<auto> sub (string txt, hash h) {
                # rename "code" -> "function"
                h += {
                    "function": remove h.code,
                    "text": txt,
                };
                if (!exists h.name) {
                    string n = txt;
                    n =~ s/\./\./g;

                    if (exists h.alias) {
                        splice n, 0, 0, "(";
                        foreach string alias in (h.alias) {
                            alias =~ s/\./\./g;
                            n += "|" + alias;
                        }
                        n += ")";
                    }

                    h.name = "^" + n + "\$";
                }

                return h;
            };
            # create api list
            list<auto> qorus_api = map editor($1.key, $1.value), system_api.pairIterator();

            # initialize WebDAV handler
            webDavHandler = new QorusWebDavHandler(QorusWebDavRootPath);

            # initialize xmlrpc and soap handlers before services are loaded
            xmlRpcHandler = new XmlRpcHandler(qorusAuth, qorus_api, \QorusHttpRequestHandler::getLogMessage(),
                debug_system, "omq.system.", sub (string msg) {olog_args(LoggerLevel::INFO, msg, argv);});
            jsonRpcHandler = new JsonRpcHandler(qorusAuth, qorus_api, \QorusHttpRequestHandler::getLogMessage(),
                debug_system, "omq.system.", sub (string msg) {olog_args(LoggerLevel::INFO, msg, argv);});
            yamlRpcHandler = new YamlRpcHandler(qorusAuth, qorus_api, \QorusHttpRequestHandler::getLogMessage(),
                debug_system, "omq.system.", sub (string msg) {olog_args(LoggerLevel::INFO, msg, argv);});
            soapHandler = new SoapHandler(qorusAuth, \QorusHttpRequestHandler::getLogMessage(), debug_system);
            FavIconHandler fiHandler((ENV.OMQ_DIR == "LSB" ? "/var/opt/qorus" : ENV.OMQ_DIR + "/etc") + "/images/Q.ico");
            debugProgramControl = new QorusWebSocketDebugProgramControl();
            # In case of debugging Qorus itself when !PO_NO_DEBUGGING we should find a point to debugProgramControl.addProgram(qpgm) to attach it
            debugHandler = new QorusWebSocketDebugHandler(debugProgramControl, qorusAuth);
            debugHandler.logger = debugProgramControl.logger;

            # init order cache
            orders = new Orders();

            # init helper objects
            sysinfo = new SystemServiceHelper("info");
            api = new SystemApiHelper();

            logDebug("OMQ: STARTUP: initializing service cache");
            # create service manager
            services = new ServiceManager();
            {
                on_exit {
                    services.initDone();
                }

                if (rsvch) {
                    services.signalRecovery();
                }

                # create dedicated interface groups
                rbac.createDedicatedGroups();

                logDebug("OMQ: STARTUP: initializing workflow synchronization event cache");
                # init workflow synchronization event manager
                SEM = new SyncEventManager();

                logDebug("OMQ: STARTUP: initializing workflow segment manager");
                # init segment manager
                SM = new SegmentManager();

                logDebug("OMQ: STARTUP: initializing workflow queue thread pool");
                # initialize WorkflowQueue thread pool
                wqtp.start();

                # create idle FTP server object
                ftpServer = new FtpServer(infoLogging, errorLogging);

                # initialize user connections object
                logDebug("OMQ: STARTUP: initializing QorusUserConnections");
                connections = new QorusUserConnections(connDeps, dsmanager.getOmqTable("connections"),
                    dsmanager.getOmqTable("connection_tags"), infoLogging, connection_rwl);

                logDebug("OMQ: STARTUP: initializing alerts.init");
                # initialize alert manager
                alerts.init();

                logDebug("OMQ: STARTUP: starting HTTP server");
                # create primary REST handler first
                restHandler = new WebAppHandler(rbac, "api");
                # create HTTP Server and setup default handlers
                # http server name formatted according to RFC 2616 section 3.8 http://tools.ietf.org/html/rfc2616#section-3.8)
                # make sure it is created after qmm.init()
                httpServer = new QorusHttpServer(debug_system);
                httpServer.setMaskCode(\WebAppHandler::maskMessage());

                # add WebDAV method support to HTTP server
                map httpServer.addHttpMethod($1), webDavHandler.getHttpMethods();

                # add remote development handler
                remoteDevelopmentHandler = new RemoteDevelopment::Handler();

                # add system REST API handler
                httpServer.setHandler("rest", "api", NOTHING, restHandler, NOTHING, False);

                OMQ::PermissiveAuthenticator permAuth();
                PublicWebAppHandler publicWebAppHandlerV1(permAuth, "api/public");
                httpServer.setHandler("public-rest-v1", "api/public", NOTHING, publicWebAppHandlerV1, NOTHING, False);

                # add public handlers to named APIs
                map httpServer.setHandler("public-rest-v" + $1, "api/v" + $1 + "/public", NOTHING,
                        new PublicWebAppHandler(permAuth, "api/v" + $1 + "/public"), NOTHING, False),
                    xrange(2, RestApiVersion + 1);

                # "latest" public handler
                PublicWebAppHandler publicWebAppHandlerLatest(permAuth, "api/latest/public");
                httpServer.setHandler("public-rest-latest", "api/latest/public", NOTHING, publicWebAppHandlerLatest, NOTHING, False);

                # "latest" metrics handler
                MetricsHandler metricsHandlerLatest(permAuth, "api");
                httpServer.setHandler("metrics", "api/metrics", NOTHING, metricsHandlerLatest, NOTHING, False);

                # add system WebSocket event handler
                # issue #3555: do not match requests based on the Sec-WebSocket-Key header
                httpServer.setHandler("websocket-events", "apievents", NOTHING, webSocketHandler, NOTHING, False);
                # start websocket event listener
                background webSocketHandler.eventListener();

                # add system WebDAV handler
                httpServer.setHandler("webdav", QorusWebDavRootPath, NOTHING, webDavHandler, NOTHING, False);

                # add Qorus log WebSocket event handler
                httpServer.setHandler("websocket-log-events", "log", NOTHING, eventLog, NOTHING, False);

                # add Qorus perforance cache event handler
                #perfEvents = new QorusPerfCacheWebSocketHandler();
                #httpServer.setHandler("websocket-perfcache", "perfcache", NOTHING, perfEvents, NOTHING, False);

                httpServer.setHandler("xmlrpc", "RPC2", MimeTypeXmlRpc, xmlRpcHandler, NOTHING, False);
                httpServer.setHandler("jsonrpc", "JSON", MimeTypeJsonRpc, jsonRpcHandler, NOTHING, False);
                httpServer.setHandler("yamlrpc", "YAML", MimeTypeYamlRpc, yamlRpcHandler, NOTHING, False);
                httpServer.setHandler("soap", "SOAP", MimeTypeSoapXml, soapHandler, "soapaction", False);
                httpServer.setHandler("favicon", "favicon.ico", NOTHING, fiHandler, NOTHING, False);
                httpServer.setHandler("debug", "debug", debugHandler.getContentType(), debugHandler, NOTHING, False);
                httpServer.setHandler("grafana", "grafana", NOTHING, new GrafanaReverseProxy(permAuth), NOTHING, False);
                debugProgramControl.setDebug(debug_system);

                # add extension handler for UI extensions
                httpServer.setHandler(UiExtensionRoot, UiExtensionRoot, NOTHING, uiext, NOTHING, False);

                string guiBasePath = ENV.OMQ_DIR == "LSB" ? "/var/opt/qorus" : ENV.OMQ_DIR;
                UiFileHandler reactHandler(join_paths(guiBasePath, "webapp"));
                httpServer.setHandler("react", "react", NOTHING, reactHandler, NOTHING, False);

                SchemaFileHandler schemaHandler(join_paths(guiBasePath, "schema"));
                httpServer.setHandler("schema", "schema", NOTHING, schemaHandler, NOTHING, False);

                # add uploading file handler
                httpServer.setHandler("raw-remote-file", "raw/remote-file", NOTHING,
                    new QorusRawRemoteFileRequestHandler(), NOTHING, False);

                # add remote command handler
                httpServer.setHandler("remote-command", "remote-command", NOTHING, new QorusRemoteWebSocketHandler(),
                    NOTHING, False);

                # create the creator WS handler unconditionally as it's needed at runtime in any case
                creatorWsHandler = new QorusCreatorWebSocketHandler();

                # add creator WS API handler
                UiFileHandler ideHandler(join_paths(guiBasePath, "webide"), "/ide");
                httpServer.setHandler("ide", "ide", NOTHING, ideHandler, NOTHING, False);
                httpServer.setHandler("creator", "creator", NOTHING, creatorWsHandler, NOTHING, False);

                httpServer.setDefaultHandler("react", reactHandler);

                # set the debug flag on the HttpServer immediately if necessary
                if (debug_system) {
                    httpServer.setDebug(True);
                }

                # init services
                AbstractQorusService::staticInit();

                # issue #2790: create the remote monitor here but do not initialize until the HTTP server is running
                # so that loopback connections can be monitored
                remotemonitor = new RemoteMonitor(connDeps, dsmanager.getOmqTable("connections"),
                    dsmanager.getOmqTable("connection_tags"), infoLogging, connection_rwl);

                # startup the HTTP server
                httpServer.startup();

                # issue #2640: send startup message as soon as the HTTP listeners have started
                if (!rjobh && !rsvch && !rwfh) {
                    sendStartupComplete(True);
                }
                logDebug("OMQ: Qorus HTTP listeners started; initial system startup complete");

                # initialize Qorus connections object
                # note: this one *has* to go after HTTP server is set up
                # because of examination of loopback connections
                logDebug("OMQ: STARTUP: initializing RemoteMonitor");
                remotemonitor.reload();

                logDebug("OMQ: initializing mappers");
                # initialize mapper objects after connection managers have been initialized
                mappers.init(infoLogging, options.get("mapper-modules"));

                # start connection performance monitoring thread
                MonitorSingleton::start();

                # initialize and start jobs
                AbstractQorusJob::staticInit();

                # recover any already-running qjob processes
                if (rjobh) {
                    jobManager.recoverProcesses(rjobh);
                }

                # start snapshot managers
                logInfo("OMQ: STARTUP: workflow snapshot manager");
                wfSnapshot = new WfSchemaSnapshotManager();
                wfSnapshot.start();
                logInfo("OMQ: STARTUP: job snapshot manager");
                jobSnapshot = new JobSchemaSnapshotManager();
                jobSnapshot.start();

                QDBG_LOG("rsvch: %y", rsvch);
                # recover any already-running qsvc processes
                if (rsvch) {
                    services.recoverProcesses(rsvch);
                }

                QDBG_LOG("rwfh: %y", rwfh);
                # recover any already-running qwf processes
                if (rwfh) {
                    control.recoverProcesses(rwfh);
                }

                if (rsvch || rjobh || rwfh) {
                    sendStartupComplete(True);
                }

                QDBG_LOG("initializing jobs");
                # initialize the job manager and autostart jobs in the background
                jobManager.init();

                if (options.get("autostart-interfaces")) {
                    QDBG_LOG("autostarting services");
                    # autostart services in the background
                    services.autoStartAsync();
                } else {
                    logInfo("OMQ: not autostarting services since 'autostart-interfaces' is False");
                }

                QDBG_LOG("autostarting workflow");
                # autostart workflows in the background
                if (options.get("autostart-interfaces")) {
                    QDBG_LOG("autostarting workflow");
                    background control.autoStart();
                } else {
                    logInfo("OMQ: not autostarting workflows since 'autostart-interfaces' is False");
                }

                logDebug("OMQ: startup complete");
            }

            # must be executed after "services.initDone()"
            if (svcrl) {
                qmm.updateServiceRemoteList(remove svcrl);
            }
            if (jobrl) {
                qmm.updateJobRemoteList(remove jobrl);
            }
            if (wfrl) {
                qmm.updateWorkflowRemoteList(remove wfrl);
            }
        } catch (hash<ExceptionInfo> ex) {
            string errstr = Util::get_exception_string(ex);
            logError("%s", errstr);
            # cleanup after exceptions
            if (ex.err.typeCode() != NT_BOOLEAN && ex.err != "BIND-ERROR" && ex.err != "SERVICE-ERROR") {
                sendStartupMsg("%s", errstr);
            }
            sendStartupComplete(False);
            # here we need to decrement the startup count manually, because we need to do a shutdown
            startup_cnt.dec();
            shutdown();
        }
    }

    private shutdownIntern(*hash cx) {
        # do not start the shutdown until the startup has completed
        QDBG_LOG("shutdownIntern() startup_cnt: %d", startup_cnt.getCount());
        startup_cnt.waitForZero();

        create_tld();
        # save call context (if present) in thread-local data
        tld.cx = cx;

        # stop snapshot managers
        if (exists wfSnapshot) {
            sendShutdownMsg("stopping workflow snapshot manager...");
            wfSnapshot.stop();
        }
        if (exists jobSnapshot) {
            sendShutdownMsg("stopping job snapshot manager...");
            jobSnapshot.stop();
        }
        if (sqlif) {
            # snapshots to be finished
            sqlif.lockSnapshot("workflow_instance");
            sqlif.unlockSnapshot("workflow_instance");
            sqlif.lockSnapshot("job_instance");
            sqlif.unlockSnapshot("job_instance");
        }
        sendShutdownMsg("stopped snapshot managers");

        sendShutdownMsg("stopping all workflows");

        control.shutdown(cx);

        sendShutdownMsg("stopped all workflows");

        # stop order statistics thread
        orderStats.shutdown();

        # stop all active jobs
        if (jobManager)
            jobManager.shutdown();

        sendShutdownMsg("stopped all jobs");

        sendShutdownMsg("stopping all services");

        # stop all running services
        if (services) {
            services.shutdown(cx);
        }

        # signal user connection monitoring to stop
        if (connections) {
            connections.shutdown();
        }
        sendShutdownMsg("stopped user connections");

        # stop performance monitoring thread
        MonitorSingleton::stop();

        sendShutdownMsg("stopped performance monitoring");

        # signal remote monitoring to stop
        if (remotemonitor)
            remotemonitor.shutdown();
        sendShutdownMsg("stopped remote connections");

        # signal datasource monitoring to stop
        if (dsmanager)
            dsmanager.shutdown();
        sendShutdownMsg("stopped db connections");

        # stop and clear the polling connection monitor
        pmonitor.stopClear();

        # stop HTTP server
        if (httpServer) {
            logInfo("OMQ: stopping HTTP server");
            httpServer.stopNoWait();
        }

        # resume any blocked debug threads
        if (debugProgramControl)
            debugProgramControl.shutdown();

        # stop FTP server
        if (ftpServer) {
            logInfo("OMQ: stopping FTP server");
            ftpServer.stopNoWait();
        }

        # shutdown the segment manager
        if (SM)
            SM.shutdown();

        sendShutdownMsg("stopped segment manager");

        # shutdown the workflow synchronization event manager
        if (SEM)
            SEM.shutdown();

        sendShutdownMsg("stopped workflow synchronization event manager");

        # wait for all services to stop
        if (services)
            services.waitShutdown();

        sendShutdownMsg("stopped all services");

        # stop any mapper reloads and avoid race conditions
        mappers.shutdown();

        # make sure all interface processes have stopped
        waitForInterfaces();

        # shutdown metadata cache
        qmm.shutdown();

        # stop and delete the performance cache manager
        #pcm.shutdown();
        #delete pcm;

        sendShutdownMsg("stopped performance cache manager");

        # stop WorkflowQueue thread pool
        delete wqtp;

        sendShutdownMsg("stopped workflow queue thread pool");

        # stop the alert manager
        alerts.shutdown();

        sendShutdownMsg("stopped alert manager");

        # close session
        if (session)
            session.close();

        sendShutdownMsg("closed application session");

        # make sure user connection monitoring has stopped
        if (connections) {
            connections.waitStop();
            logInfo("OMQ: stopped user connection monitoring");
            sendShutdownMsg("stopped user connection monitoring");
        }

        if (remotemonitor) {
            # make sure Qorus remote monitoring has stopped
            remotemonitor.waitStop();
            logInfo("OMQ: stopped remote Qorus connection monitoring");
            sendShutdownMsg("stopped remote Qorus connection monitoring");
        }

        if (dsmanager) {
            # make sure datasource monitoring has stopped
            dsmanager.waitStop();
            logInfo("OMQ: stopped datasource connection monitoring");
            sendShutdownMsg("stopped datasource connection monitoring");
        }

        # decrement start counter
        start_counter.dec();

        if (audit)
            audit.systemShutdown(cx);

        if (ftpServer) {
            ftpServer.waitStop();
            logInfo("OMQ: stopped FTP server");
            sendShutdownMsg("stopped FTP server");
        }

        if (httpServer) {
            httpServer.waitStop();
            logInfo("OMQ: stopped HTTP server");
            delete httpServer;
            sendShutdownMsg("stopped HTTP server");
        }

        # stop the qorus datasource pool process
        if (qdsp_omq) {
            stopProcess(qdsp_omq);
        }

        # stop heartbeat thread in independent mode
        if (opts.independent) {
            stopHeartbeatThread();
        }

        # delete connection managers
        delete connections;
        delete remotemonitor;
        delete dsmanager;
        delete pmonitor;

        #logInfo("OMQ: waiting for all threads to finish...");
        #OMQ::wait_for_all_threads(\olog_args());

        if (session)
            printf("Qorus instance %y sessionid %d PID %d stopped\n", options.get("instance-key"), session.getID(), getpid());

        if (remoteDevelopmentHandler) {
            remoteDevelopmentHandler.shutdown();
        }

        stopSubThread();

        sendShutdownMsg("stopped all server threads");

        logInfo("OMQ: system shutdown complete");
        sendShutdownComplete();

        if (opts.independent) {
            if (stop_info) {
                logInfo("%y: acknowledging STOP", stop_info.sender);
                sendAnyResponse(stop_info.index, stop_info.sender, stop_info.mboxid, CPC_ACK);
                remove stop_info;
                QDBG_LOG("acknowledgement sent");
            } else {
                logInfo("no shutdown sender for STOP acknowledgement");
            }
        } else {
            # stop cluster server process event thread
            stopEventThread();

            # we need to exit explicitly in case there are Java threads that will not exit by themselves
            exit(0);
        }

        QDBG_LOG("qorus_running_cnt: %y", qorus_running_cnt.getCount());
        qorus_running_cnt.dec();
    }

    bool restart(softint timeout = QorusApp::DefaultRestartTimeout) {
        Process restart("qctl", ("restart", "--close"), {"close-fds": True});
        restart.detach();
        return shutting_down;
    }

    hash<auto> refreshSnapshots() {
        if (exists wfSnapshot) {
            wfSnapshot.stop();
        }
        if (exists jobSnapshot) {
            jobSnapshot.stop();
        }
        auto ret = sqlif.refreshSnapshots();
        wfSnapshot.start();
        wfSnapshot.start();
        return ret;
    }

    string getSystemDbDriverName() {
        return omqp ? omqp.getDriverName() : omqds.getDriverName();
    }

    static private checkDir(string dir, bool need_write = False) {
        if (!strlen(ENV{dir}))
            return;

        if (!is_dir(ENV{dir})) {
            stderr.printf("ERROR: directory %s=%n does not exist, aborting\n",
                dir, ENV{dir});
            exit(1);
        }

        if (!need_write)
            return;

        if (!is_writable(ENV.OMQ_DIR)) {
            stderr.printf("ERROR: directory %s=%n is not writable, aborting\n",
                dir, ENV{dir});
            exit(1);
        }
    }

    static private setSystemPaths() {
        # if OMQ_DIR is not set or does not exist
        if (ENV.OMQ_DIR != "LSB")
            QorusApp::checkDir("OMQ_DIR");
        QorusApp::checkDir("OMQ_LOG_DIR", True);

        if (!ENV.OMQ_DIR) {
            # see if application is installed in system directories or in
            # an application directory
            string pn = QORE_ARGV[0];

            # find the program in the path if necessary
            if (pn !~ /\//) {
                # find program in path
                foreach string dir in (split(":", ENV.PATH)) {
                    string nf = dir + "/" + pn;
%ifdef HAVE_IS_EXECUTABLE
                    if (is_executable(nf)) {
                        pn = nf;
                        break;
                    }
%else
                    if (is_readable(nf)) {
                        pn = nf;
                        break;
                    }
%endif
                }
            }

            pn = normalize_dir(dirname(pn));

            if (pn == "/usr/bin") {
                ENV.OMQ_DIR="LSB";
                #stderr.printf("WARNING: assuming LSB directory structure\n");
            }
            else if (pn =~ /\/bin$/) {
                ENV.OMQ_DIR = substr(pn, 0, -4);
                #stderr.printf("WARNING: assuming OMQ_DIR=%n\n", ENV.OMQ_DIR);
            }
        }

        # if log dir is not set or does not exist
        if (!ENV.OMQ_LOG_DIR && ENV.OMQ_DIR == "LSB") {
            ENV.OMQ_LOG_DIR = "/var/log/qorus";
        }
    }

    static saveContext(hash cx) {
        if (!tld) {
            # FIXME how it can happen that tld is NOTHING? --PQ 27-Jun-2016
            QDBG_LOG("QorusApp::saveContext creating tld");
            OMQ::ThreadLocalData ntld();
            tld = ntld;
        }
        tld.cx = cx;
    }

    private showListeners(string prot, string opt) {
        string msg;
        foreach softstring ifv in (select options.get(opt), exists $1)
            msg += QorusApp::getInterface(ifv);

        if (!msg)
            return;

        # remove trailing ", "
        splice msg, -2;

        sendStartupMsg("starting %s listener on: %s", prot, msg);
    }

    static private string getInterface(string a) {
        if (a == int(a))
            return sprintf("<all interfaces>:%d, ", a);
        a =~ s/{.*//;
        if (a == int(a))
            return sprintf("<all interfaces>:%d, ", a);
        return sprintf("%s, ", trim(a));
    }

    private openSystemDatasources() {
        # This object is local only. It will disappear at the end of this method
        # the real OMQ DatasourceConnection is created in the DatasourceManager
        DatasourceConnection connection("omq", "Qorus system schema", options.get("systemdb"));

        # start datasource pool process
        qdsp_omq = startDatasourcePoolProcess("omq", connection.urlh + {"options": connection.opts}, True).info;
        omqp = new QdspClient(self, "omq", {"set_context": options.get("oracle-datasource-pool")});
        omq_info = getDsInfo(omqp);

        # check system schema driver version
        {
            hash<auto> di = omqp.getDriverInfo();
            if (compare_version(OMQ::MinSystemDBDriverVersion{di.name}, di.version) > 0)
                throw "INCOMPATIBLE-SYSTEM-DRIVER", sprintf("Qorus requires %s driver version %s or greater for the "
                    "system schema; the current module supplies version %s; please install a compatible version of "
                    "the %s driver and try again", di.name, OMQ::MinSystemDBDriverVersion{di.name}, di.version,
                    di.name);
        }

        # init SQL Interface
        # PV 20091201 - moved from omq_init to allow use interfaces for sessions too
        switch (omq_info.driver_realname) {
            case "oracle":
                sqlif = new OracleServerSQLInterface(omqp); break;

            case "pgsql":
            case /^postgres/i:
                sqlif = new PostgreServerSQLInterface(omqp); break;

            case "mysql":
                sqlif = new MySQLServerSQLInterface(omqp); break;

            default:
                throw "DATASOURCE-ERROR", sprintf("driver %y is not supported for the Qorus system schema",
                    omq_info.driver);
        }
    }

    private hash<auto> getDsInfo(AbstractDatasource ds) {
        return {
            "driver"          : ds.getDriverName(),
            "driver_realname" : ds.getDriverRealName(),
            "server_version"  : ds.getServerVersion(),
            "user"            : ds.getUserName(),
            "pass"            : ds.getPassword(),
            "db"              : ds.getDBName(),
            "encoding"        : ds.getDBEncoding(),
            "host"            : ds.getHostName(),
            "port"            : ds.getPort(),
        };
    }

    private remove_signal_handlers() {
        remove_signal_handler(SIGTERM);
        remove_signal_handler(SIGINT);
        remove_signal_handler(SIGHUP);
        remove_signal_handler(SIGUSR2);
        QDBG_LOG("signal handlers removed");
    }

    private signal_handler(softstring sig) {
        try {
            remove_signal_handlers();
            if (opts.independent) {
                {
                    monitor_lck.lock();
                    on_exit monitor_lck.unlock();

                    if (terminate) {
                        logFatal("OMQ: %s received, process already stopping", SignalToName{sig});
                        return;
                    }
                    terminate = True;
                }
                background stopIndependent();
                logFatal("OMQ: %s received, stopping independent qorus-core", SignalToName{sig});
            }

            if (!shutting_down) {
                try {
                    logFatal("OMQ: %s received, starting system shutdown", SignalToName{sig});
                } catch (hash<ExceptionInfo> ex) {
                    # ignore log exceptions; ex: FILE-WRITE-ERROR: failed writing 95 bytes to File: Stale file handle, arg: 116
                    if (ex.err != "FILE-WRITE-ERROR") {
                        rethrow;
                    }
                }
                QDBG_LOG("signal_handler() calling shutdown()");
                if (!shutdownQorusCore()) {
                    # send a message to the master process to shut down
                    master.sendCheckResponse(CPC_STOP, NOTHING, CPC_ACK);
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            logFatal("error in signal handler: %s", get_exception_string(ex));
        }
    }

    setDebug(bool dbg) {
        debug_system = dbg;
        if (yamlRpcHandler)
            yamlRpcHandler.setDebug(dbg);
        if (xmlRpcHandler)
            xmlRpcHandler.setDebug(dbg);
        if (jsonRpcHandler)
            jsonRpcHandler.setDebug(dbg);
        if (soapHandler)
            soapHandler.setDebug(dbg);
        if (httpServer)
            httpServer.setDebug(dbg);
        if (debugProgramControl)
            debugProgramControl.setDebug(dbg);
    }

    private int setSystemOption(string v) {
        int i;
        hash hash;
        string f;

        if ((i = index(v, "=")) == -1) {
            hash{v} = 1;
            f = v;
        } else {
            f = substr(v, 0, i);
            hash{f} = substr(v, i + 1);
        }

        try {
            list errs = options.set(hash);
            if (!elements errs)
                return 0;

            map stderr.print($1 + "\n"), errs;
        } catch (hash<ExceptionInfo> ex) {
            stderr.printf("%s: %s\n", ex.err, ex.desc);
        }
        return 1;
    }

    *list<string> getStack() {
        if (!HAVE_RUNTIME_THREAD_STACK_TRACE)
            return;
        *list<auto> stack = get_all_thread_call_stacks(){gettid()};
        if (!exists stack)
            return;
        splice stack, 0, 2;
        return map $1.type != "new-thread" ? sprintf("%s %s()", get_ex_pos($1), $1.function) : "new-thread", stack;
    }

    private setQorusLogDir() {
        *string logdir = options.get("logdir");
        if (!logdir) {
            logdir = ENV.OMQ_LOG_DIR ?? (ENV.OMQ_DIR == "LSB" ? "/var/qorus/log" : join_paths(ENV.OMQ_DIR, "log"));
            options.set(("logdir" : logdir));
        }

        if (!stat(logdir)) {
            stderr.printf("ERROR: can't stat log directory %y: %s\n", logdir, strerror());
            stderr.printf("aborting Qorus startup; please set the 'Qorus.logfiledir' option in the Qorus options file and restart Qorus\n");
            exit(QSE_LOG_ERROR);
        }
    }

    # subscribes to a log in qorus-master
    subscribeToLog(string oid) {
        master.sendCheckResponse(CPC_CORE_LOG_SUBSCRIBE, {"log": oid}, CPC_OK);
    }

    # unsubscribes from a log in qorus-master
    unsubscribeFromLog(string oid) {
        master.sendCheckResponse(CPC_CORE_LOG_UNSUBSCRIBE, {"log": oid}, CPC_OK);
    }

    updateQorusMasterLogger(*hash<LoggerParams> params) {
        # do not substitute params here; let the filename be generated by each master separately
        master.sendCheckResponse(CPC_MR_UPDATE_LOGGER, {"params": params}, CPC_OK);
    }

    updatePrometheusLogger(*hash<LoggerParams> params) {
        params = substituteLogFilename(params, LoggerController::getLoggerSubs("prometheus"));
        master.sendCheckResponse(CPC_MR_UPDATE_PROMETHEUS_LOGGER, {"params": params}, CPC_OK);
    }

    updateGrafanaLogger(*hash<LoggerParams> params) {
        params = substituteLogFilename(params, LoggerController::getLoggerSubs("grafana"));
        master.sendCheckResponse(CPC_MR_UPDATE_GRAFANA_LOGGER, {"params": params}, CPC_OK);
    }

    private *hash<LoggerParams> getLoggerParams() {
        return loggerController.getLoggerParamsSubs("qorus-core");
    }

    rotateLogFiles(*hash cx) {
        AbstractQorusDistributedProcess::rotateLogFiles();

        alerts.rotateLogFiles();
        httpServer.rotateLogFiles();
        audit.rotateLogFiles();

        # rotate monitoring logger (e.g. dsmanager, remotemonitor, connections)
        ConnectionsServer::rotateLogFiles();

        SM.rotateLogFiles();
        services.rotateLogFiles();
        jobManager.rotateLogFiles();

        master.sendCheckResponse(CPC_MR_ROTATE_LOGGER, NOTHING, CPC_OK);
        master.sendCheckResponse(CPC_MR_ROTATE_QDSP_LOGGER, NOTHING, CPC_OK);
    }

    logArgs(int lvl, string msg, auto args) {
        string fmsg = vsprintf(msg, args);
        # on start up, while AbstractQorusDistributedProcess only initialize logger
        # eventLog has not been initialized yet
        if (eventLog) {
            logger.log(lvl, "%s", fmsg, new LoggerEventParameter(\Qorus.eventLog.logEvent(), "qorus-core",
                sprintf("%s T%d [%s]: ", log_now(), gettid(), LoggerLevel::getLevel(lvl).getStr()) + fmsg + "\n"));
        } else {
            logger.log(lvl, "%s", fmsg);
        }

        if (lvl == Logger::LoggerLevel::FATAL) {
            stdout.print(fmsg + "\n");
        }
    }

    logFatal(string msg) {
        logArgs(Logger::LoggerLevel::FATAL, msg, argv);
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

    private logCommonFatal(string fmt) {
        logArgs(LoggerLevel::FATAL, fmt, argv);
    }

    private logCommonInfo(string fmt) {
        logArgs(LoggerLevel::INFO, fmt, argv);
    }

    private logCommonDebug(string fmt) {
        logArgs(LoggerLevel::DEBUG, fmt, argv);
    }

    private rescanMetadataIntern(*bool wf, *bool svc, *bool job) {
        alerts.rescanMetadata(wf, svc, job);
        rbac.rescanMetadata(wf, svc, job);
    }

    rescanMetadata(*bool wf, *bool svc, *bool job) {
        if (rbac.initialized())
            background rescanMetadataIntern(wf, svc, job);
    }
}

class QorusFileHandlerBase inherits FileHandler {
    private {
        int https_port;
    }

    constructor(string file_root, string url_root = "/", string default_target = "index.html")
            : FileHandler(file_root, url_root, {
                "default_target": default_target,
                "auth": new PermissiveAuthenticator(),
                "error_level": 2,
            }) {
        if (!Qorus.options.get("disable-https-redirect")) {
            foreach string ifv in (Qorus.options.get("http-secure-server")) {
                ifv =~ s/{.*}//;
                if (ifv == ifv.toInt()) {
                    https_port = ifv.toInt();
                    break;
                }
            }
        }
    }

    hash<HttpResponseInfo> handleRequest(HttpServer::HttpListenerInterface listener, Qore::Socket s, hash<auto> cx,
            hash<auto> hdr, *data body) {
        # redirect to HTTPS if applicable
        # issue #3854: do not redirect requests from UNIX domain dockets (i.e. without any port)
        if (!cx.ssl && https_port && cx."socket-info".port) {
            string host = hdr.host;
            host =~ s/:.*$//;
            hdr.host = sprintf("%s:%d", host, https_port);
            return redirect(cx + {"ssl": True}, hdr, hdr.path ?? "");
        }
        if (hdr.method == "OPTIONS") {
            return QorusHttpServer::handleOptions(cx);
        }
        hash<HttpResponseInfo>  rv = handleRequestIntern(listener, s, cx, hdr, body);
        if (!rv.hdr."Access-Control-Allow-Origin") {
            rv.hdr += QorusHttpServer::getCorsResponseHeaders(cx);
        }
        return rv;
    }

    private hash<HttpResponseInfo> handleRequestIntern(HttpServer::HttpListenerInterface listener, Qore::Socket s,
            hash<auto> cx, hash<auto> hdr, *data body) {
        return FileHandler::handleRequest(listener, s, cx, hdr, body);
    }

    logInfo(string fmt) {
        Qorus.logArgs(LoggerLevel::INFO, "OMQ: " + fmt, argv);
    }

    logError(string fmt) {
        Qorus.logArgs(LoggerLevel::ERROR, "OMQ: " + fmt, argv);
    }

    logDebug(string fmt) {
        Qorus.logArgs(LoggerLevel::DEBUG, "OMQ: " + fmt, argv);
    }

    # do not render any directories
    renderDirectory(hash<auto> cx, string path) {}
}

class UiFileHandler inherits QorusFileHandlerBase {
    constructor(string file_root, string url_root = "/", string default_target = "index.html")
            : QorusFileHandlerBase(file_root, url_root, default_target) {
    }

    #! tries to serve the request from the filesystem
    private *hash<HttpResponseInfo> tryServeRequest(HttpServer::HttpListenerInterface listener, Qore::Socket s, hash<auto> cx,
            hash<auto> hdr, *data body) {
        # try to serve .gz files for the UI first if possible
        if (cx."header-info"."accept-encoding".gzip) {
            hash<auto> new_cx = cx + {
                "resource_path": cx.resource_path + ".gz",
                "auto-gzip": True,
            };
            *hash<HttpResponseInfo> rv = FileHandler::tryServeRequest(listener, s, new_cx, hdr, body);
            if (rv) {
                logInfo("serving %y in place of %y (%y)", new_cx.resource_path, cx.resource_path, rv.hdr);
                return rv;
            }
        }
        return FileHandler::tryServeRequest(listener, s, cx, hdr, body);
    }

    private *hash<auto> getResponseHeadersForFile(string path, hash<auto> cx, hash<auto> request_hdr) {
        hash<string, string> response_hdr;
        # make client cache JS and CSS files
        if (path =~ /\.(js|css)(.gz)?$/) {
            response_hdr."Cache-Control" = "private, max-age=86400"; # 86400 = 1 day
        }

        if (cx."auto-gzip" && path =~ /.gz$/) {
            response_hdr += {
                "Content-Encoding": "gzip",
                "Content-Type": get_mime_type_from_ext(path.substr(0, -3)),
            };
        } else {
            response_hdr."Content-Type" = get_mime_type_from_ext(path);
        }

        return response_hdr;
    }
}

class SchemaFileHandler inherits QorusFileHandlerBase {
    private {
        Mutex m();
        hash<string, hash<auto>> schemas;

        string body;

        const Head = "<head>
  <title>Qorus REST Schema Index</title>
  <style>
    * {
      font-family: 'Verdana'
    }
  </style>
</head>\n";
    }

    constructor(string file_root) : QorusFileHandlerBase(file_root) {
        body = Head + sprintf("<body>\n  <b>Qorus Integration Engine&reg; v%s REST Schemas</b>\n  <ul>\n",
            OMQ::version);
        Dir d();
        d.chdir(file_root);
        foreach hash<auto> info in (d.listFiles(True)) {
            if (info.name !~ /\.(json|yaml)$/) {
                continue;
            }
            try {
                (string bn, string ext) = (info.name =~ x/(.*)\.([a-z0-9]+)$/i);
                string file_data = File::readTextFile(join_paths(d.path(), info.name));
                string altname;
                if (ext == "json") {
                    altname = bn + ".yaml";
                    schemas{altname} = schemas{info.name} = parse_json(file_data);
                } else {
                    altname = bn + ".json";
                    schemas{altname} = schemas{info.name} = parse_yaml(file_data);
                }
                body += sprintf("    <li><a href=\"/schema/%s\">%s</a></li>\n", info.name, info.name);
                body += sprintf("    <li><a href=\"/schema/%s\">%s</a></li>\n", altname, altname);
            } catch (hash<ExceptionInfo> ex) {
                logError("%s: invalid schema: %s: %s", info.name, ex.err, ex.desc);
                continue;
            }
        }
        body += "  </ul>\n</body>";
    }

    #! tries to serve the request
    private *hash<HttpResponseInfo> tryServeRequest(HttpServer::HttpListenerInterface listener, Qore::Socket s,
            hash<auto> cx, hash<auto> hdr, *data request_body) {
        if ((*string name = (cx.resource_path =~ x/^schema\/(.+)$/)[0]) && (*hash<auto> schema = schemas{name})) {
            # prepare schema data for response
            schema.host = cx.hdr.host;
            schema.schemes = cx.ssl ? ("https",) : ("http",);
            string body;
            string ct;
            if (name =~ /\.json$/) {
                 body = make_json(schema, JGF_ADD_FORMATTING);
                 ct = MimeTypeJson + ";charset=UTF-8";
            } else {
                 body = make_yaml(schema, BlockStyle);
                 ct = MimeTypeYaml + ";charset=UTF-8";
            }
            return <HttpResponseInfo>{
                "code": 200,
                "body": body,
                "hdr": {
                    "Content-Type": ct,
                    "Content-Disposition": sprintf("attachment;filename=%y", name),
                },
            };
        }
        logInfo("SCHEMA path: %y", cx.resource_path);
        if (cx.resource_path == "index.html") {
            return <HttpResponseInfo>{
                "code": 200,
                "body": body,
                "hdr": {"Content-Type": MimeTypeHtml},
            };
        }
        return QorusFileHandlerBase::tryServeRequest(listener, s, cx, hdr, request_body);
    }
}
