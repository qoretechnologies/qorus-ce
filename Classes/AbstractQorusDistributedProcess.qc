# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

# here we add fallback paths to the QORE_MODULE_DIR search path,
# in case QORE_MODULE_DIR is not set properly for Qorus
%append-module-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib:$OMQ_DIR/user/modules

# here we add fallback paths to the QORE_INCLUDE_DIR search path,
# in case QORE_INCLUDE_DIR is not set properly
%append-include-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib

%include AbstractLogger.qc
%include cpc-api.ql

%requires zmq
%requires yaml
%requires process

const QSE_COMMAND_LINE_ERROR = 8;

class AbstractQorusDistributedProcess inherits AbstractQorusClientProcess, AbstractQorusClusterApi {
    public {
        const Opts = {
            "loglevel": "L,log-level:s",
            "sysdeb": "debug-system",
            "sysprop": "D,define=s@",
            "dir": "d,qorus-dir=s",
            "help": "h,help",
        };

        # the default column offset for printing options used in printOption() and usage()
        const OffsetColumn = 20;
    }

    private {
        # name of the local node
        string node;

        # unique process name
        string name;

        # server-specific name
        string client_id;

        # restarted flag
        bool restarted;

        # bind strings
        list<string> binds;

        # logger
        Logger logger;

        # network encryption key helper
        NetworkKeyHelper nkh;

        # command-line options
        hash opts;

        # timestamp the process was started
        date started = now_us();

        # connection to master
        QorusMasterClient master;

        # list of local interface addresses
        list<string> local_addresses();

        # bind counter so that start authorization is only made after the bind addresses have been generated
        Counter bind_cnt(1);

        # command-line properties ("-D"); see qorus-command-line.ql
        hash runtimeProp = {};

        # debug system flag
        bool debug_system = False;
    }

    constructor(reference<list<string>> p_argv, hash<auto> getopt_opts = Opts, *hash<LoggerParams> loggerParams) {
        # check whether env var with logger params is set up, and update the logger
        if (loggerParams) {
            updateLogger(loggerParams);
        } else if (ENV{ENV_LOGGER_PARAMS}) {
            loggerParams = convert_logger_params(ENV{ENV_LOGGER_PARAMS});
            updateLogger(loggerParams);
        } else {
            createInitialLogger();
        }

        logInfo("starting %s PID %d with args: %y", get_script_name(), getpid(), p_argv);

        *list<string> orig_argv = p_argv;
        try {
            opts = (new GetOpt(getopt_opts)).parse2(\p_argv);
        } catch () {
            usage();
        }
        if (opts.dir)
            ENV.OMQ_DIR = opts.dir;

        if (opts.help)
            usage();

        if (opts.sysdeb)
            debug_system = True;

        foreach string i in (opts.sysprop) {
            list l = split("=", i);
            if (elements l != 2) {
                stderr.printf("runtime properties must have a -Dkey=value format; got: -D%s\n", i);
                exit(QSE_COMMAND_LINE_ERROR);
            }
            runtimeProp{l[0]} = l[1];
        }

        try {
            # issue #2732: check system limits before starting qorus
            QorusSharedApi::checkSystemStart();
        } catch (hash<ExceptionInfo> ex) {
            logFatal("WARNING: %s", ex.desc);
        }

        doInitialConfig(\p_argv);

        logInfo("started process %s PID %d %y with args: %y", get_script_name(), getpid(), client_id, orig_argv);
    }

    string getLocalAddress() {
        QDBG_ASSERT(local_addresses[0]);
        return local_addresses[0];
    }

    #! Post a lot event to the logger directly
    postLogEvent(LoggerEvent event) {
        logger.callAppenders(event);
    }

    #! Returns our bind URLs
    /** should only be called after URLs have been bound
    */
    list<string> getLocalUrls() {
        return binds;
    }

    #! Creates the initial logger if no logger parameters are provided
    private createInitialLogger() {
        logger = createEmptyLogger();
    }

    #! Returns the current logger
    Logger getLogger() {
        return logger;
    }

    #! Processes cmd-line args, sets up the NetworkKeyHelper and sets up the connection to the active master
    private doInitialConfig(reference<list<string>> p_argv) {
        *string api_level = shift p_argv;
        *string node = shift p_argv;
        *string master_node = shift p_argv;
        *string master_urls = shift p_argv;
        *string interfaces = shift p_argv;
        *string network_key_path = shift p_argv;
        *string name = shift p_argv;
        *string client_id = shift p_argv;
        *string restarted = shift p_argv;

        if (!exists api_level || !exists node || !exists master_node || !exists master_urls || !exists interfaces
            || !exists network_key_path || !exists name || !exists client_id || !exists restarted) {
            usage();
        }

        self.node = node;
        self.name = name;
        self.client_id = client_id;
        self.restarted = restarted.toBool();

        if (api_level != CPC_API_LEVEL) {
            logFatal("master server reported API level %y; expecting %y; cannot start", api_level, CPC_API_LEVEL);
            exit(3);
        }

        nkh = new NetworkKeyHelper(network_key_path);

        local_addresses = interfaces.split(",");

        # set master URL
        setUrls(qmaster_get_process_name(master_node), master_urls.split(","));

        # create connection to master
        master = new QorusMasterClient(self, master_node, name);

        # start the server event thread
        startEventThread();
    }

    #! returns the restarted flag
    bool getRestarted() {
        return restarted;
    }

    #! returns the master client object
    QorusMasterClient getMaster() {
        return master;
    }

    #! report to qorus-master that the process could not be started so that it's not restarted, then terminate
    /** should only be called after the process has issued the START command to qorus-master
    */
    private reportStartupErrorAndDie(string reason) {
        if (argv) {
            reason = vsprintf(reason, argv);
        }
        logInfo("notifying qorus-master of startup error: %s", reason);
        master.sendCheckResponse(CPC_MR_IGNORE_PROCESS_ABORT, {"name": name, "reason": reason}, CPC_ACK);
        QDBG_LOG("AbstractQorusDistributedProcess::reportStartupErrorAndDie() notification acknowledged; exiting");
        exit(QSE_STARTUP_ERROR);
    }

    #! registers the given server and gets the URLs for the server process
    hash<auto> registerServer(string proc_name) {
        # set placeholder for process URLs
        setUrls(proc_name);
        on_error unblockClientRequests(proc_name, True);
        # get URLs for process
        *hash<auto> h = qorus_cluster_deserialize(master.checkResponseMsg(CPC_MR_GET_PROCESS_INFO, CPC_OK,
            master.sendCmdSerialized(CPC_MR_GET_PROCESS_INFO, proc_name))[0]);
        if (!h) {
            throw "UNKNOWN-PROCESS-ERROR", sprintf("master returned no info in request for process %y", proc_name);
        }
        if (!h.urls) {
            throw "PROCESS-ERROR", sprintf("master returned process info for process %y with no queue URL info: %y",
                proc_name, h);
        }
        logInfo("registered server %y with urls: %y", proc_name, h.urls);
        # save URLs for qorus-core process
        updateUrlsConditional(proc_name, cast<list<string>>(h.urls));
        return h;
    }

    # returns the name of the local node
    string getNode() {
        return node;
    }

    # returns the unique network ID
    string getNetworkId() {
        return name;
    }

    bool getDebugSystem() {
        return debug_system;
    }

    *hash<auto> getRuntimeProps() {
        return runtimeProp;
    }

    setRuntimeProps(hash h) {
        runtimeProp += h;
    }

    NetworkKeyHelper getNetworkKeyHelper() {
        return nkh;
    }

    list<ZSocketRouter> createRouters(reference<list<hash<ZmqPollInfo>>> poll_list) {
        on_exit bind_cnt.dec();

        # list of ZSocketRouter objects for all interfaces
        list<ZSocketRouter> rl();

        # bind all interfaces on a wildcard address
        foreach string addr in (local_addresses) {
            # create master API socket; default timeout OK because we use polling
            MyRouter router(zctx, name, "tcp://" + addr + ":*", $#, nkh);

            rl += router;
            # we always have real addresses in local_addresses
            QDBG_ASSERT(addr != "*");
            binds += router.endpoint();

            # add to poll notification list
            poll_list += new hash<ZmqPollInfo>({
                "socket": router,
                "events": ZMQ_POLLIN,
            });
        }

        logInfo("starting ZeroMQ primary I/O thread with queue URLs: %y", binds);
        return rl;
    }

    doAuthStart() {
        # wait for bind addresses to be created
        bind_cnt.waitForZero();

        # send URLs to master and get start authorization
        hash<auto> h = {
            "pid": getpid(),
            "urls": binds,
            "api_level": CPC_API_LEVEL,
            "api_sub": CPC_API_SUB,
        };

        logDebug("sending %y to %y", h, master.getUrls());
        try {
            *list<string> msgs = master.sendCmd(CPC_START, h);
            string str = shift msgs;
            if (str != CPC_OK) {
                error("server did not authorize start: %y", str);
                while (exists (*string mstr = shift msgs)) {
                    error("str: %y", mstr);
                }
                exit(1);
            }
            QDBG_LOG("qorus-master authorized start: %y", str);
        } catch (hash<ExceptionInfo> ex) {
            logInfo("%s", get_exception_string(ex));
            rethrow;
        }
    }

    handleRouterMsg(ZSocketRouter zsocket_router) {
        MyRouter router = cast<MyRouter>(zsocket_router);
        ZMsg msg;
        try {
            msg = router.recvMsg();
        } catch (hash<ExceptionInfo> ex) {
            error("error receiving command: %s: %s", ex.err, ex.desc);
            return;
        }

        string sender;
        string mboxid;
        string cmd;
        try {
            # get sender's ID
            sender = msg.popStr();
            # get the sender's mailbox ID
            mboxid = msg.popStr();
            # get command
            cmd = msg.popStr();
            QDBG_LOG("received msg from: %y TID %d cmd: %y size: %d", sender, mboxid, cmd, msg.contentSize() + mboxid.size() + cmd.size());
        } catch (hash<ExceptionInfo> ex) {
            error("error reading message (sender: %y TID %y cmd: %y): %s", sender,
                mboxid, cmd, get_exception_string(ex));
            return;
        }

        try {
            # process common commands
            if (processMsg(router, sender, mboxid, cmd, msg)) {
                #QDBG_LOG("cmd %y from sender %y mboxid %y handled; continuing", cmd, sender, mboxid);
                return;
            }

            processCmd(router, router.index, sender, mboxid, cmd, msg);
        } catch (hash<ExceptionInfo> ex) {
            error("exception handling cmd: %y from sender: %y TID %d: %s", cmd, sender,
                mboxid, get_exception_string(ex));
            router.send(sender, mboxid, CPC_EXCEPTION, qorus_cluster_serialize({"ex": ex}));
            return;
        }
    }

    logCmd(int ll, string fmt) {
        log(ll, vsprintf(fmt, argv));
    }

    errorCmd(string fmt) {
        error(vsprintf(fmt, argv));
    }

    static pingDs(AbstractDatasource ds) {
        *string driver = ds.getDriverName();
        if (driver == "odbc" && (*string conn = ds.getOption("conn")) && (conn =~ /driver=firebird/i)) {
            ds.select("select 1 from rdb$database");
        } else if (driver == "oracle") {
            ds.select("select 1 from dual");
        } else {
            ds.select("select 1");
        }
    }

    # returns information about the process
    hash<auto> getInfo() {
        hash<auto> mh = Process::getMemorySummaryInfo();
        return {
            "name": name,
            "id": client_id,
            "urls": binds,
            "started": started,
            "threads": num_threads(),
            "loglevel": logger.getLevel().getValue(),
            "modules": get_module_hash(),
            "props": getRuntimeProps(),
        } + mh + {"priv_str": mh ? get_byte_size(mh.priv) : "n/a"};
    }

    private processCmd(ZSocketRouter sock, int index, string sender, string mboxid, string cmd, ZMsg msg) {
        if (!processCmdImpl(sock, index, sender, mboxid, cmd, msg)) {
            sock.send(sender, mboxid, CPC_UNKNOWN_CMD);
            error("unknown command: %y from sender: %y", cmd, sender);
        }
    }

    private usage() {
        int offset = usageImpl() ?? OffsetColumn;
        printOption("-h,--help", "this help text", offset);
        printOption("--debug-system", "turns on system debugging", offset);
        printOption("-D,--define=ARG", "sets a runtime property", offset);
        printOption("-d,--qorus-dir=ARG", "sets the application directory (overrides OMQ_DIR)", offset);
        printOption("-L,--loglevel=ARG", "sets log level for system loggers", offset);
        exit(0);
    }

    private printOption(string left, string right, int offset = OffsetColumn) {
        stderr.printf(" %s", left);
        int blanks = offset - left.size();
        if (blanks > 0)
            stderr.print(strmul(" ", blanks));
        stderr.printf("%s\n", right);
    }

    # called when the cluster server process should stop
    private stopServer() {
        logInfo("server issued STOP");
        stopEventThread();
    }

    # takes an old log level arg
    private logImpl(int lvl, string msg) {
        logger.log(lvl, "%s", msg);
    }

    private redirectStdEO() {
        # redirect stdout & stderr to the logger appender
        foreach auto appender in (logger.getAppenders()) {
            if (appender instanceof LoggerAppenderFile) {
                File file = appender.getFile();
                stderr.redirect(file);
                stdout.redirect(file);
                break;
            }
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

    rotateLogFiles() {
        bool redirected;
        foreach auto appender in (logger.getAppenders()) {
            if (appender instanceof AbstractLoggerAppenderFileRotate) {
                cast<AbstractLoggerAppenderFileRotate>(appender).rotate();
                # issue #3826: make sure to update stdout/stderr redirections when rotating log files
                if (!redirected) {
                    File file = appender.getFile();
                    stderr.redirect(file);
                    stdout.redirect(file);
                    redirected = True;
                }
            }
        }
    }

    updateLogger(*hash<LoggerParams> params) {
        if (logger) {
            logInfo("logger will be updated with params: %y", params);
        }
        logger = params ? createLogger(params) : createEmptyLogger();
        logInfo("logger has been updated with params: %y", params);

        redirectStdEO();

        updateLoggerImpl(logger);
    }

    #! Called after updating the logger
    updateLoggerImpl(Logger logger) {
        # this method is empty by design
    }

    abstract private bool processCmdImpl(ZSocketRouter sock, int index, string sender, string mboxid, string cmd, ZMsg msg);

    # returns the offset in characters between options and descriptions
    abstract private *int usageImpl();

    abstract private logArgs(int lvl, string msg, auto args);
}

class MyRouter inherits ZSocketRouter {
    public {
        int index;
    }

    constructor(ZContext ctx, string identity, string url, int index, NetworkKeyHelper nkh) : ZSocketRouter(ctx) {
        self.index = index;
        # issue #3453: set encryption keys
        nkh.setServer(self);
        # set identity
        setIdentity(identity);
        # bind listener
        bind(url);
        # clients can reuse identities but must ensure uniqueness
        setOption(ZMQ_ROUTER_HANDOVER, 1);
        # do not try to return values to dead clients
        setOption(ZMQ_LINGER, 0);
    }
}
