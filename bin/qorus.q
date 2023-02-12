#!/usr/bin/env qore
# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%requires qore >= 1.0

%new-style
%require-our
%strict-args
%require-types

%enable-all-warnings
%exec-class QorusMaster

%requires yaml
%requires zmq
%requires Util
%requires process
%requires SqlUtil

%include QorusProcessManager.qc
%include AbstractQorusClient.qc
%include qorus.ql
%include qorus-version.ql
%include cpc-api.ql
%include cpc-dsp-api.ql
%include cpc-core-api.ql
%include cpc-master-api.ql

our QorusMaster Qorus;

#! qorus-master application class
class QorusMaster inherits AbstractQorusProcessManager, QorusMasterCoreQsvcCommon {
    public {
        #! system options
        QorusOptionsBase options();

        #! cluster processes table
        AbstractTable cluster_processes;

        #! logs handled by this process
        const MasterLogs = (
            "qorus-master",
            "prometheus",
            "grafana",
        );

        #! map of external processes; name -> True
        const ExternalProcesses = {
            QDP_NAME_PROMETHEUS: True,
            QDP_NAME_GRAFANA: True,
        };
    }

    private {
        #! the network ID for this master process
        string master_network_id;

        #! command-line properties ("-D"); see qorus-command-line.ql
        hash runtimeProp = {};

        #! application command-line option hash
        const QorusOpts = {
            "help"            : "h,help",
            "dir"             : "d,qorus-dir=s",
            "independent"     : "I,independent",
            "list"            : "l,option-list",
            "loglevel"        : "L,log-level:s",
            "version"         : "V,version",
            "sysprop"         : "D,define=s@",
            "build"           : "B,show-build",
            "sysdeb"          : "debug-system",
            "daemon"          : "daemon=s",
            "startup"         : "startup=s",
            "logsub"          : "log-subscribe=s@",
        };

        #! the qorus-master logger
        Logger logger;

        const Banners = (
            sprintf("%s v%s (build %s)", OMQ::ProductName, OMQ::version, QorusRevision),
            "Copyright (C) 2003 - 2023 Qore Technologies, s.r.o.",
        );

        #! command-line options
        hash opts;

        #! there can be only one qorus-core process
        QorusCoreProcess qorus_core;

        #! there can be only one prometheus process
        PrometheusProcess prometheus;

        #! there can be only one grafana process
        GrafanaProcess grafana;

        #! container for qdsp processes
        hash<string, AbstractQorusProcess> qdsp_map();

        #! workflow process hash
        hash<string, AbstractQorusProcess> wph();

        #! passive master process hash; proc ID -> proc
        hash<string, QorusPassiveMasterProcess> passive_master_id_map();

        #! passive master process hash; node -> proc
        hash<string, QorusPassiveMasterProcess> passive_master_node_map();

        #! issue #3506: map of qdsp processes that need recovery; dsp name -> process ID
        hash<string, AbstractQorusProcess> qdsp_recovery_map;

        #! shutdown flag
        bool shutdown_flag;

        #! shutdown Qorus flag; once set, no more Qorus processes can be started
        bool shutdown_qorus_flag;

        #! started flag: set when the first qorus-core process reports that it has started
        bool started_flag = False;

        #! handover event Queue
        Queue handover_queue();

        #! startup Queue
        Queue startup_queue();

        #! has master row
        bool has_master_row = False;

        #! recover from old master
        bool recover = False;

        #! startup PUB msg sent?
        bool startup_msg_sent = False;

        #! queue for PUB data
        Queue pubq();
        #! pub socket URL
        string pub_url;
        #! Counter for pub_url
        Counter pub_url_cnt(1);
        #! Counter for pub thread
        Counter pub_thread_cnt();

        #! Counter for the heartbeat thread
        Counter heartbeat_thread_cnt();
        #! mutex and condition variable for the heartbeat thread
        Mutex heartbeat_mutex();
        Condition heartbeat_cond();

        #! Counter for node monitor thread
        Counter node_thread_cnt();
        #! Condition for node monitor thread
        Condition node_thread_cond();
        #! Mutex for node monitor thread
        Mutex node_thread_lck();
        #! node thread flag
        bool stop_node_thread;

        #! running flag for the cluster info thread
        bool cluster_info_running = False;

        #! mutex and condition variable for the cluster info thread
        Mutex cluster_info_mutex();
        Condition cluster_info_cond();

        #! stop flag for the cluster info thread
        bool cluster_info_stop;

        #! Counter for the cluster info thread
        Counter cluster_info_cnt();

        #! list of workflow IDs still running when qorus-core is not running
        /** to ensure that they are registered as remote / cluster processes in qorus-core when it's recovered
        */
        list<int> running_wfid_list();

        #! list of service IDs still running when qorus-core is not running
        /** to ensure that they are registered as remote / cluster processes in qorus-core when it's recovered

            each entry is:
            - serviceid: stateful services
        */
        list<string> running_svcid_list();

        #! list of job IDs still running when qorus-core is not running
        /** to ensure that they are registered as remote / cluster processes in qorus-core when it's recovered
        */
        list<int> running_jobid_list();

        #! qorus-core start status for "startup" mode for PUB socket
        string start_status = QSS_NORMAL;

        #! current application sessionid ("-" = new session)
        string sessionid = "-";

        #! node memory history; node -> node memory info list
        hash<string, list<hash<auto>>> mem_history;

        #! process memory history; node -> node process history list
        hash<string, list<hash<auto>>> proc_history;

        #! common commnad-line process options
        list<string> cl_opts();

        #! qorus master process start time
        date starttime = now_us();

        #! init logger map
        *hash<auto> init_logger_map;

        #! omq qdsp loggerid
        *int omq_loggerid;

        #! mutex for atomic operations on log_subscribed
        Mutex subscription_mutex();

        #! is qorus-core interested in our logs? valid keys: qorus-master
        hash<string, bool> log_subscribed;

        #! running in active mode
        bool active;

        #! the network process ID of the active master, if running in passive mode
        string active_master_network_id;

        #! set when active = False for the connection to the active master
        QorusMasterClient active_master;

        #! Set to the node the active master is running on
        string active_master_node;

        #! hash of remote master node info keyed per node name
        hash<string, hash<auto>> remote_node_memory_info;

        #! restarted qorus-core flag after an active master failover
        bool failover_restart_qorus_core;

        #! interfaces to notify after qorus-core has been restarted
        list<string> failover_restart_qorus_core_list;

        #! the timestamp for the qorus-core termination event
        date failover_restart_qorus_core_abort_timestamp;

        #! independent mode: termination flag
        bool terminate;

        #! Startup counter
        Counter startup_done(1);

        #! default recovery timeout
        const DefaultRecoverTimeout = 15s;

        #! default startup timeout; must be long for large Qorus instances
        const StartupTimeout = 300s;

        #! cluster info update interval
        const ClusterInfoUpdateInterval = 2s;

        #! number of history entries for memory and process counts (60 * 5s = 5 minutes)
        const HistoryDepth = 60;

        #! YAML info for an active instance
        const ActiveYaml = make_yaml({"active": True});

        #! YAML info for an inactive instance
        const PassiveYaml = make_yaml({"active": False});

        #! poll remote nodes every 10 seconds
        const NodePollingInterval = 10s;

        #! 20 second timeout for remote node memory info
        const NodeMemoryTimeout = 10s;

        #! 1 GB node memory threshold
        /** if estimated process memory and the node's free memory are greater than this amount, then treat as equal
        */
        const NodeMemoryThreshold = 1024 * 1024 * 1024;

        #! Heartbeat interval
        const HeartbeatInterval = 5s;

        #! Heartbeat cutoff for failed master nodes
        const MasterCutoffInterval = 15s;

        #! issue #3573: date test key
        const DATE_TEST_KEY = "__DATE_TEST__";

        #! issue #3573: maximum date/time difference between the server and the DB
        const DB_THRESHOLD = 5s;
    }

    constructor() {
        # initialize logger with stdout appender, before establishing datasource connection
        logger = createEmptyLogger();

        # note info must already be set
        QDBG_ASSERT(node);

        # set process network ID
        master_network_id = qmaster_get_process_name(node);

        # open system datasource
        openSystemDatasource();

        # show Qorus version
        map logStartup($1), Banners;

        # process command line after options have been initialized
        opts = processCommandLine();

        if (exists opts.loglevel) {
            softint ll = opts{"loglevel"};
            updateSystemLogLevel(ll != 0 ? ll : parse_yaml(opts{"loglevel"}));

            # set common command-line process options
            cl_opts += sprintf("-L=%y", opts.loglevel);
        }

        getLoggerMap();

        # update logger with params from db
        if (int loggerid = init_logger_map.loggerAliases{master_network_id}
            ?? init_logger_map.loggerAliases."qorus-master"
            ?? init_logger_map.loggerAliases.system) {
            updateLogger(makeLoggerParams(init_logger_map.loggerMap{loggerid}.params, master_network_id));
        }

        # add runtime properties to command line
        map cl_opts += sprintf("-D%s=%s", $1.key, $1.value), runtimeProp.pairIterator();
        # add debugging option to command line if applicable
%ifdef QorusDebugInternals
        opts.sysdeb = True;
%endif
        if (opts.sysdeb) {
            cl_opts += "--debug-system";
        }

        if (opts.logsub) {
            log_subscribed = map {$1: True}, opts.logsub;
        }

        # start cluster manager
        if (!startCluster()) {
            stderr.printf("failed to start cluster servers\n");
            exit(QSE_DATASOURCE);
        }

        # install shutdown signal handlers
        setSignalHandlers();

        # initialize memory footprint for this master process
        initMemoryFootprint();

        # check master status
        try {
            checkMaster();
        } catch (hash<ExceptionInfo> ex) {
            stopCluster();
            rethrow;
        }
        startup_done.dec();

        {
            string str = omqds.getConfigString();
            # remove password if any
            str =~ s/\/[^@%{}]+//;
            # remove options
            str =~ s/{.*}//;
            logStartup("starting %s %y; system schema: %s",
                active ? "Qorus cluster" : "passive master for node \"" + node + "\" for Qorus cluster",
                options.get("instance-key"),
                str);
            log(LoggerLevel::INFO, "event publisher URL %s", getPubUrl());
        }

        # issue#3517: check date/time alignment
        checkDbDate();

        if (opts.daemon && active) {
            executeMasterHandover();
            publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, {
                "ok": True,
                "pid": qorus_core ? qorus_core.getPid() : -1,
                "status": start_status
            });
            startHeartbeatThread();
            if (active) {
                startNodeThread();
            }
        } else {
            bool ok = True;
            if (active) {
                startInitialProcesses();

                bool daemon_mode = options.get("daemon-mode");
                if (daemon_mode && opts.independent) {
                    logStartup("ignoring daemon-mode with independent start");
                    daemon_mode = False;
                }

                # run in background if required
                if (daemon_mode) {
                    # if this call returns, an error has occurred
                    startMasterHandover();
                    stopCluster();
                    start_status = QSS_ERROR;
                    ok = False;
                } else {
                    # only start the heartbeat thread if a master handover is not made
                    startHeartbeatThread();
                    startNodeThread();
                    logStartup("system started; daemon-mode disabled; staying in foreground");
                }
            } else {
                # start heartbeat thread in passive master
                startHeartbeatThread();
            }

            if (!startup_msg_sent) {
                hash<auto> sh = (
                    "ok": ok,
                    "status": start_status,
                );

                if (ok && active) {
                    sh.pid = qorus_core ? qorus_core.getPid() : -1;
                }
                publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, sh);
                startup_msg_sent = True;
            }

            try {
                # issue #2732: check system limits before starting qorus
                QorusSharedApi::checkSystemStart();
            } catch (hash<ExceptionInfo> ex) {
                log(LoggerLevel::FATAL, "WARNING: %s", ex.desc);
            }
        }
        QDBG_LOG("%s master initialization complete", active ? "active" : "passive");
    }

    string getSystemDbDriverName() {
        return omqds.getDriverName();
    }

    #! Returns True if the "independent" flag is set
    bool isIndependent() {
        return opts.independent ?? False;
    }

    #! Starts the heartbeat thread
    private startHeartbeatThread() {
        heartbeat_thread_cnt.inc();
        background heartbeatThread();
    }

    #! starts the node thread
    private startNodeThread() {
        QDBG_ASSERT(active);
        node_thread_cnt.inc();
        try {
            background nodeThread();
        } catch (hash<ExceptionInfo> ex) {
            node_thread_cnt.dec();
            stderr.printf("could not start node monitor thread: %s\n", get_exception_string(ex));
            exit(QSE_STARTUP_ERROR);
        }
    }

    #! starts initial Qorus cluster processes
    private startInitialProcesses() {
        try {
            if (options.get("unsupported-enable-tsdb")) {
                int prometheus_port;
                if (prometheus) {
                    prometheus_port = prometheus.getPort();
                } else if (!startPrometheusProcess(\prometheus_port)) {
                    logStartup("Failed to start %s", QDP_NAME_PROMETHEUS);
                    exit(QSE_DATASOURCE);
                }

                if (!grafana && !startGrafanaProcess(prometheus_port)) {
                    logStartup("Failed to start %s", QDP_NAME_GRAFANA);
                    exit(QSE_DATASOURCE);
                }
            }

            # start qorus-core process
            if (!qorus_core && !opts.independent) {
                # issue #2801: return any errors starting qorus-core
                if (!startQorusCoreProcess()) {
                    startupMessageMaster("failed to start qorus-core process");
                    publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, {"ok": False, "status": QSS_ERROR});
                    stopCluster();
                    thread_exit;
                }

                QDBG_LOG("qorus-core started; timestamp: %y notifying: %y",
                    failover_restart_qorus_core_abort_timestamp, failover_restart_qorus_core_list);
                if (failover_restart_qorus_core_list) {
                    notifyInterfacesAboutQorusCore();
                }

                waitForQorusCore();
            }
        } catch (hash<ExceptionInfo> ex) {
            stderr.printf("system process startup error: %s\n", get_exception_string(ex));
            exit(QSE_DATASOURCE);
        }
    }

    #! notify interfaces that qorus-core has restarted and has a new URL
    private notifyInterfacesAboutQorusCore() {
        QDBG_ASSERT(!opts.independent);
        # map from process ID to notification info
        hash<string, hash<ProcessNotificationInfo>> msg_info();
        {
            m.lock();
            on_exit m.unlock();

            # do not wait for responses here, as the process being notified also may die during the notification
            map sendNotifyAbortedProcessInitial($1, QDP_NAME_QORUS_CORE, \msg_info),
                ph{failover_restart_qorus_core_list}.iterator(),
                $1.needsSendNotifyAbortedProcessInitial();
        }
        if (msg_info) {
            waitForResponses(CPC_PROCESS_ABORT_NOTIFICATION, \msg_info);
        }
        # map from process ID to notification info
        hash<string, hash<ProcessNotificationInfo>> msg_info2();
        {
            m.lock();
            on_exit m.unlock();

            # do not wait for responses here, as the process being notified also may die during the notification
            map sendNotifyAbortedProcess($1, QDP_NAME_QORUS_CORE, qorus_core.getClusterProcInfo(), True,
                failover_restart_qorus_core_abort_timestamp, \msg_info2),
                ph{failover_restart_qorus_core_list}.iterator(),
                (!exists msg_info || msg_info{$1.getId()} || !$1.needsSendNotifyAbortedProcessInitial());
        }
        if (msg_info2) {
            waitForResponses(CPC_PROCESS_ABORT_NOTIFICATION, \msg_info2);
        }
    }

    #! the remote node polling thread
    private nodeThread() {
        log(LoggerLevel::INFO, "starting node monitor thread");
        on_exit {
            log(LoggerLevel::INFO, "stopped node monitor thread");
            node_thread_cnt.dec();
        }

        while (!stop_node_thread) {
            *hash<string, AbstractQorusInternProcess> node_map;
            # get a snapshot of the node map in the lock
            {
                m.lock();
                on_exit m.unlock();

                node_map = cast<*hash<string, AbstractQorusInternProcess>>(passive_master_node_map);
                if (opts.independent && qorus_core) {
                    node_map{qorus_core.getNode()} = qorus_core;
                }
            }

            if (node_map) {
                try {
                    getRemoteMemoryInfo(node_map);
                } catch (hash<ExceptionInfo> ex) {
                    log(LoggerLevel::ERROR, "error getting remote memory info: %s", get_exception_string(ex));
                }
            }

            {
                node_thread_lck.lock();
                on_exit node_thread_lck.unlock();

                QorusSharedApi::waitCondition(node_thread_cond, node_thread_lck, NodePollingInterval,
                    \stop_node_thread);
            }
        }
    }

    private killAllLocalProcesses() {
        QDBG_LOG("killAllLocalProcesses() node: %y", node);
        m.lock();
        on_exit m.unlock();

        map (remove ph{$1.key}).terminate(), ph.pairIterator(), $1.value.getNode() == node;
    }

    private setSignalHandlers() {
        set_signal_handler(SIGTERM, \signalHandler());
        set_signal_handler(SIGINT,  \signalHandler());
        set_signal_handler(SIGHUP,  \signalHandler());
        set_signal_handler(SIGUSR2, \debugSignalHandler());
        QDBG_LOG("signal handlers installed");
    }

    private removeSignalHandlers() {
        remove_signal_handler(SIGTERM);
        remove_signal_handler(SIGINT);
        remove_signal_handler(SIGHUP);
        remove_signal_handler(SIGUSR2);
        QDBG_LOG("signal handlers removed");
    }

    private debugSignalHandler(int sig) {
        hash<auto> stacks;
        foreach hash<auto> i in (get_all_thread_call_stacks().pairIterator()) {
            stacks{i.key} = map $1.type != "new-thread"
                ? sprintf("%s %s()", get_ex_pos($1), $1.function)
                : "new-thread", i.value;
        }
        log(LoggerLevel::INFO, "%s: %N", SignalToName{sig}, stacks);
    }

    private signalHandler(softstring sig) {
        QDBG_LOG("signalHandler() %d -> %y", sig, SignalToName{sig});
        removeSignalHandlers();
        if (canShutdown()) {
            if (opts.independent) {
                if (active) {
                    if (shutdownHandoverActiveToPassive()) {
                        log(LoggerLevel::INFO, "%s signal received, handed over to new active master",
                            SignalToName{sig});
                        exit(0);
                    }
                } else {
                    QDBG_LOG("informing active master that the passive master is shutting down");

                    blockProcesses();
                    on_exit unblockProcesses();

                    killAllLocalProcesses();

                    try {
                        active_master.sendCheckResponse(CPC_MR_DO_PASSIVE_SHUTDOWN, NOTHING, CPC_ACK);
                    } catch (hash<ExceptionInfo> ex) {
                        log(LoggerLevel::ERROR, "error communicating with active master: %s",
                            get_exception_string(ex));
                    }
                }
            }

            try {
                log(LoggerLevel::INFO, "%s signal received, starting cluster shutdown", SignalToName{sig});
            } catch (hash<ExceptionInfo> ex) {
                # ignore log exceptions
                # ex: FILE-WRITE-ERROR: failed writing 95 bytes to File: Stale file handle, arg: 116
                if (ex.err != "FILE-WRITE-ERROR") {
                    rethrow;
                }
            }
            background stopCluster();
        }
    }

    #! Initializes the memory footprint for the current process
    private initMemoryFootprint() {
        hash<MemorySummaryInfo> pi = getMachineAndProcessMemory();
%ifdef DARWIN
        # on Darwin we have to use vm_stat :(
        machine_ram_in_use = (sysconf(SC_PHYS_PAGES) - (`vm_stat` =~ x/Pages free:\s+([0-9]+)/m)[0].toInt()) * MachinePageSize;
%endif
        int pct = (pi.priv * 100.0 / float(machine_ram_total)).toInt();
        checkProcessMemoryIntern(master_network_id, pi, pct, getProcessInfoHash(pi));
    }

    #! gets memory information from processes on remote nodes
    private getRemoteMemoryInfo(hash<string, AbstractQorusInternProcess> node_map) {
        hash<string, Queue> response_map = cast<hash<string, Queue>>(map {
            $1.key: $1.value.getClient().sendCmdAsync(CPC_MR_GET_MEMORY_INFO)
        }, node_map.pairIterator());
        on_exit {
            # cancel all async calls
            map node_map{$1}.getClient().cancelAsyncCmd(), keys response_map;
        }

        date start = now_us();

        # FIXME: implement a polling API for multiple queues
        while (response_map && !stop_node_thread) {
            foreach hash<auto> i in (response_map.pairIterator()) {
                if (!i.value.empty()) {
                    AbstractQorusInternProcess proc = node_map{i.key};
                    processMemoryResponse(proc, i.value);
                    remove response_map{i.key};
                }
            }

            date now = now_us();
            if (response_map && (now - start) > NodeMemoryTimeout) {
                # cancel all async calls
                map node_map{$1}.getClient().cancelAsyncCmd(), keys response_map;
                # handle timeouts for all remaining nodes
                nodeTimeout(keys (remove response_map), node_map);
                break;
            }
            {
                node_thread_lck.lock();
                on_exit node_thread_lck.unlock();

                QorusSharedApi::waitCondition(node_thread_cond, node_thread_lck, 250ms);
            }
        }
    }

    #! handle node memory request response messages
    processMemoryResponse(AbstractQorusInternProcess proc, Queue response_queue) {
        string node_id = proc.getNode();
        AbstractQorusClient client = proc.getClient();
        try {
            list<string> msgs = client.checkAsyncResponseMsg(response_queue, CPC_MR_GET_MEMORY_INFO, CPC_OK, NodeMessageTimeout);
            QDBG_LOG("REMOTE MEM MSGS: %y", msgs);
            hash<auto> info = qorus_cluster_deserialize(msgs[0]);

            # do not process qsvc responses running on otherwise registered nodes as a remote node
            bool do_node = !(proc instanceof QsvcProcess) || (!passive_master_node_map{node_id} && node != node_id);
            QDBG_LOG("got remote memory info: %y (do_node: %y): %y", node_id, do_node, info);

            # update processes with remote memory info
            m.lock();
            on_exit m.unlock();

            map ph{$1.key}.setRemoteMemoryInfo($1.value), info.process_info.pairIterator(), ph{$1.key};

            if (do_node) {
                remote_node_memory_info{node_id} = info.node_memory_info;
                if (info.mem_history) {
                    mem_history{node_id} = info.mem_history;
                }
                if (info.proc_history) {
                    proc_history{node_id} = info.proc_history;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CLIENT-DEAD" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED") {
                # these errors are normal when a node dies and is detected while the call is in progress
                log(LoggerLevel::ERROR, "node %y: error retrieving node memory response: %s: %s", node_id, ex.err, ex.desc);
            } else {
                log(LoggerLevel::ERROR, "node %y: error retrieving node memory response: %s", node_id, get_exception_string(ex));
            }
        }
    }

    #! Called in the process lock when a node is removed
    private removeNodeIntern(string node_id) {
        AbstractQorusProcessManager::removeNodeIntern(node_id);
        remove remote_node_memory_info{node_id};
        remove mem_history{node_id};
        remove proc_history{node_id};
    }

    #! handle node memory request timeouts
    private nodeTimeout(softlist<string> node_ids, hash<string, AbstractQorusInternProcess> node_map) {
        log(LoggerLevel::INFO, "the following nodes / procs are not responding: %y", node_ids);

        # issue #3870: handle the failure of multiple nodes correctly
        # first check all master heartbeats
        *list<string> process_ids = map $1.getId(), (map node_map{$1}, node_ids),
            $1 instanceof QorusPassiveMasterProcess;
        if (process_ids) {
            date cutoff = now_us() - MasterCutoffInterval;
            *list<hash<auto>> rows = selectRowsFromTable(cluster_processes, {
                "where": {
                    "process_network_id": op_in(process_ids),
                    "heartbeat": op_ge(cutoff),
                },
            });
            if (rows) {
                QDBG_LOG("passive masters with valid heartbeats: %y", (
                    map $1{"process_network_id", "node", "heartbeat"}, rows
                ));
                foreach hash<auto> row in (rows) {
                    log(LoggerLevel::INFO, "passive master %y on node %y has a valid heartbeat (%y); abandoning recovery",
                        row.process_network_id, row.node, row.heartbeat);
                    node_ids = map $1, node_ids, $1 != row.node;
                    continue;
                }
            }
        }

        # issue #3870: process and remove all failed qsvc proesses
        foreach string node_id in (node_ids) {
            if (node_map{node_id} instanceof QorusCoreProcess) {
                QDBG_ASSERT(opts.independent);
                log(LoggerLevel::INFO, "qorus-core process has died and must be restarted independently");
                # tell monitor thread to send notification that process no longer exists
                markIndependentProcessAborted(QDP_NAME_QORUS_CORE);
                node_ids = map $1, node_ids, $1 != node_id;
            }
        }

        # only master processes are left
        recoverPassiveNodes(node_ids);
    }

    private recoverPassiveNodes(list<string> nodes) {
        hash<string, bool> node_map = map {$1: True}, nodes;

        hash<string, QorusPassiveMasterProcess> master_procs;
        {
            m.lock();
            on_exit m.unlock();

            QDBG_ASSERT(passive_master_node_map{nodes}.size() == nodes.size());
            master_procs = remove passive_master_node_map{nodes};
        }

        # now we send messages to all the processes on the node to terminate
        map killAllProcessesOnNode($1.value, $1.key), master_procs.pairIterator();

        hash<string, hash<ProcessTerminationInfo>> aborted_hash;

        {
            m.lock();
            on_exit m.unlock();

            map removeAbortedProcess($1.getId(), \aborted_hash), ph.iterator(), (node_map{$1.getNode()});

            map remove passive_master_id_map{$1.getId()}, master_procs.iterator();

            # remove remote node
            map remove remote_node_memory_info{$1}, keys master_procs;
            map remove node_process_map{$1}, keys master_procs;
        }

        if (aborted_hash) {
            log(LoggerLevel::INFO, "the following processes have died on nodes %y: %y", nodes, keys aborted_hash);
            # handle aborted processes
            handleAbortedProcesses(aborted_hash);
        }

        map publishEvent(CPC_MR_PUB_NODE_REMOVED, {"name": $1}), keys master_procs;
    }

    private recoverPassiveNode(string node, bool kill_all_processes = True) {
        QDBG_LOG("recoverPassiveNode() node: %y (this node: %y) kill_all: %y", node, self.node, kill_all_processes);
        # first we remove the node from the node list
        QorusPassiveMasterProcess master_proc;
        {
            m.lock();
            on_exit m.unlock();

            QDBG_ASSERT(passive_master_node_map{node});
            master_proc = remove passive_master_node_map{node};
        }

        # now we send messages to all the processes on the node to terminate
        if (kill_all_processes) {
            killAllProcessesOnNode(master_proc, node);
        }

        hash<string, hash<ProcessTerminationInfo>> aborted_hash;

        {
            m.lock();
            on_exit m.unlock();

            map removeAbortedProcess($1.getId(), \aborted_hash), ph.iterator(), ($1.getNode() == node);

            remove passive_master_id_map{master_proc.getId()};

            # remove remote node
            remove remote_node_memory_info{node};
            remove node_process_map{node};
        }

        if (aborted_hash) {
            log(LoggerLevel::INFO, "the following processes have died on node %y: %y", node, keys aborted_hash);
            # handle aborted processes
            handleAbortedProcesses(aborted_hash);
        }

        publishEvent(CPC_MR_PUB_NODE_REMOVED, {"name": node});
    }

    #! Send messages to all processes on a node to terminate
    private killAllProcessesOnNode(QorusPassiveMasterProcess master_proc, string node) {
        # in case the process is still running and can receive messages, we tell the passive master to terminate
        QDBG_ASSERT(master_proc.getPid() > 0);
        master_proc.terminate();

        # now we get a list of non-internal processes on the node
        list<AbstractQorusProcess> non_internal_list;
        foreach AbstractQorusProcess proc in (node_process_map{node}.iterator()) {
            if (!(proc instanceof AbstractQorusInternProcess)) {
                non_internal_list += proc;
            }
        }

        *list<int> pids = map $1.getPid(), non_internal_list, $1.getPid() > 0;
        pids += master_proc.getPid();

        # tell all processes on the node to kill the passive master and any non-internal processes and then to kill
        # themselves
        foreach AbstractQorusProcess proc in (node_process_map{node}.iterator()) {
            if (!(proc instanceof AbstractQorusInternProcess)) {
                continue;
            }
            if (proc != master_proc) {
                AbstractQorusInternProcess intern_proc = cast<AbstractQorusInternProcess>(proc);
                intern_proc.terminate({"pids": pids});
            }
        }
    }

    #! Handles an orderly shutdown of a passive master node
    handlePassiveShutdown(int index, string sender, string mboxid, string passive_node) {
        try {
            log(LoggerLevel::INFO, "passive node %y is terminating; recovering processes", passive_node);
            sendAnyResponse(index, sender, mboxid, CPC_ACK);
            recoverPassiveNode(passive_node, False);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error handling passive shutdown on node %y: %s", passive_node,
                get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    #! stop the node monitor thread
    private stopNodeThread() {
        stop_node_thread = True;
        {
            node_thread_lck.lock();
            on_exit node_thread_lck.unlock();
            node_thread_cond.signal();
        }
        node_thread_cnt.waitForZero();
    }

    # waits for qorus-core to start successfully; if not then an error message is published, and the process exits
    private waitForQorusCore() {
        QDBG_ASSERT(!opts.independent);
        # wait for qorus-core process to start or be recovered
        try {
            bool ok = startup_queue.get(StartupTimeout);
            if (!ok) {
                startupMessageMaster("timeout starting qorus-core");
                publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, {"ok": False, "status": QSS_ERROR});
                if (canShutdown()) {
                    stopCluster();
                }
                thread_exit;
            }
        } catch (hash<ExceptionInfo> ex) {
            *QorusCoreProcess proc = ph{QDP_NAME_QORUS_CORE};
            *string str;
            if (proc) {
                str = proc.readStdout();
                if (str) {
                    str = "; stdout: " + str;
                }
                *string estr = proc.readStderr();
                if (estr) {
                    str += "; stderr: " + estr;
                }
            }
            startupMessageMaster("qorus-core failed to start: %s: %s%s", ex.err, ex.desc, str);
            publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, {"ok": False, "status": QSS_ERROR});
            stopCluster();
            thread_exit;
        }
    }

    bool getDebugSystem() {
        return opts.sysdeb ?? False;
    }

    # returns the unique network ID
    string getNetworkId() {
        return master_network_id;
    }

    #! returns the node name of the active master
    string getActiveMasterNodeName() {
        return !active ? active_master.getServerName() : node;
    }

    private hash<auto> getRuntimePropsImpl() {
        return runtimeProp;
    }

    # executed before the constructor in this class
    private initNodeImpl() {
        # set global application variable
        Qorus = self;

        # process the options file, set defaults, and check for sane option values
        options.init(opts.daemon.toBool());

        # set runtime properties
        runtimeProp += options.get("defines");
    }

    private *hash<auto> getCurrentMasterRowForUpdateIntern() {
        QDBG_ASSERT(cluster_processes.getDatasource().currentThreadInTransaction());
        # check if there is a master process in the process table already
        hash<auto> sh = {
            "where": {
                "process_network_id": master_network_id,
            },
            "forupdate": True,
        };
        return cluster_processes.selectRow(sh);
    }

    #! Ensure that the DB and server have their time zones in sync
    private:internal checkDbDate() {
        string systemdb = options.get("systemdb");
        # issue #3517: do not allow Qorus to start if the database time zone locale is incorrect
        try {
            AbstractTable sysprops = getTable("system_properties");
            Datasource ds = sysprops.getDatasource();
            # must use now() for Oracle as we will only get back a date/time value with second precision from Oracle
            date now = Qore::now();
            softdate dbnow;
            switch (ds.getDriverName()) {
                case "oracle":
                    dbnow = ds.selectRow("select %v as now from dual", now).now;
                    break;
                default:
                    dbnow = ds.selectRow("select %v as now", now).now;
                    break;
            }
            if (dbnow != now) {
                throw "SYSTEM-DATASOURCE-ERROR", sprintf("cannot start Qorus; database and Qorus machine have "
                    "different time zone configurations; local time: %y is returned as %y from the DB; local region: "
                    "%y", now, dbnow, TimeZone::get().region());
            }
            QDBG_LOG("DB delta: 1: %y == %y", dbnow, now);

            hash<auto> row = {
                "domain": "omq",
                "keyname": DATE_TEST_KEY
            };
            int rc = sysprops.del(row);
            if (rc) {
                sysprops.commit();
            }
            on_exit sysprops.rollback();
            # must use now() for Oracle as we will only get back a date/time value with second precision from Oracle
            now = Qore::now();
            sysprops.insert(row + {"value": get_random_string(), "modified": now});
            hash<auto> dbrow = sysprops.selectRow({"where": row});
            if (dbrow.modified != now) {
                throw "SYSTEM-DATASOURCE-ERROR", sprintf("cannot start Qorus; database and Qorus machine have "
                    "different time zone configurations; local time: %y is returned as %y from the DB; local region: "
                    "%y", now, dbrow.modified, TimeZone::get().region());
            }
            QDBG_LOG("DB delta: 2: %y == %y", dbrow.modified, now);
            date delta = dbrow.created - now;
            if (delta > DB_THRESHOLD) {
                throw "SYSTEM-DATASOURCE-ERROR", sprintf("cannot start Qorus; time difference between insert in the "
                    "DB schema %y and the system time is %y (threshold: %y)", systemdb, delta, DB_THRESHOLD);
            }
            QDBG_LOG("DB delta: %y OK", delta);
        } catch (hash<ExceptionInfo> ex) {
            startupMessageMaster("cannot start Qorus; system datasource %y: %s", systemdb, get_exception_string(ex));
            publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, {"ok": False, "status": QSS_ERROR});
            stopCluster();
            thread_exit;
        }
    }

    checkMaster() {
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            has_master_row = False;
            try {
                cluster_processes.getDatasource().beginTransaction();

                on_error cluster_processes.rollback();
                on_success cluster_processes.commit();

                # check if there is a master process in the process table already
                *hash<auto> row = getCurrentMasterRowForUpdateIntern();
                QDBG_LOG("current master: %y", row);
                if (row) {
                    # see if master is still active
                    *hash<auto> info = checkProcessAlive(row, False);
                    if (info) {
                        if (opts.daemon) {
                            bool found;
                            foreach string url in (row.queue_urls.split(",")) {
                                if (url == opts.daemon) {
                                    found = True;
                                    break;
                                }
                            }

                            # exit if we have a valid but unexpected master entry
                            if (!found) {
                                startupMessageMaster("unexpected qorus master process on node %s:%d (%s) is alive; "
                                    "exiting", row.node, row.pid, row.queue_urls);
                                publishEventUnconditional(CPC_MR_PUB_STARTUP_COMPLETE, {
                                    "ok": True,
                                    "pid": info.processes."qorus-core".pid,
                                    "status": QSS_ALREADY_RUNNING,
                                });
                                stopCluster();
                                thread_exit;
                            }
                            log(LoggerLevel::INFO, "successfully contacted old master: %y", info + {
                                "processes": keys info.processes,
                                "modules": keys info.modules,
                            });
                            # ok; we have a valid and expected master; leave the row in place and set the active flag
                            active = True;
                        } else {
                            # exit if we have an active master already
                            startupMessageMaster("qorus master process %s:%d (%s) is alive; exiting", row.node,
                                row.pid, row.queue_urls);
                            publishEventUnconditional(CPC_MR_PUB_STARTUP_COMPLETE, {
                                "ok": True,
                                "pid": info.processes."qorus-core".pid,
                                "status": QSS_ALREADY_RUNNING,
                            });
                            stopCluster();
                            thread_exit;
                        }
                    } else {
                        if (opts.daemon) {
                            delete opts.daemon;
                        }

                        if (row.active_master) {
                            active = True;
                        }
                        startupMessageMaster("%s qorus master process %s:%d (%s) has died; starting recovery",
                            active ? "active" : "passive", row.node, row.pid, row.queue_urls);

                        # if we have running passive masters, then we need to force an active failover and restart as
                        # a passive master
                        if (active) {
                            if (handoverActiveToPassive()) {
                                checkActiveMaster();
                            }
                        }

                        recover = True;
                    }
                } else {
                    if (opts.daemon) {
                        startupMessageMaster("no qorus master in place; exiting");
                        publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, {"ok": False, "status": QSS_ERROR});
                        stopCluster();
                        thread_exit;
                    }
                }

                # active flag must be set here
                if (!exists active) {
                    # check if there is already a qorus-master process running in active mode
                    # this sets the active flag
                    checkActiveMaster();
                }

                # if there are other processes, then we must recover
                if (!opts.daemon && !recover && cluster_processes.selectRow({
                    "where": {
                        "process_network_id": op_ne(master_network_id),
                    },
                    "limit": 1,
                })) {
                    recover = True;
                }

                # try to insert master row
                if (!row) {
                    # insert row
                    row = {
                        "process_network_id": master_network_id,
                        "host": gethostname(),
                        "node": node,
                        "pid": getpid(),
                        "process_type": QDP_NAME_QORUS_MASTER,
                        "client_id": node,
                        "interfaces": getInterfacesString(),
                        "queue_urls": getMasterUrlsString(),
                        "info": active ? ActiveYaml : PassiveYaml,
                        "active_master": active ? 1 : NULL,
                    };
                    # if the insert fails due to a PK error, an exception will be thrown
                    cluster_processes.insert(row);
                    QDBG_LOG("inserted master row: %y", row);
                } else {
                    # update existing row
                    hash<auto> uh = {
                        "host": gethostname(),
                        "node": node,
                        "pid": getpid(),
                        "interfaces": getInterfacesString(),
                        "queue_urls": getMasterUrlsString(),
                        "info": active ? ActiveYaml : PassiveYaml,
                        "created": now_us(),
                        "active_master": active ? 1 : NULL,
                    };
                    hash<auto> wh = {
                        "process_network_id": master_network_id,
                        "host": row.host,
                        "pid": row.pid,
                        "created": row.created,
                    };
                    int rows = cluster_processes.update(uh, wh);
                    if (!rows) {
                        throw "STARTUP-ERROR", "failed to update master row; master has been recovered already";
                    }
                    QDBG_LOG("updated master row with urls %y", master_urls);
                }

                has_master_row = True;
            } catch (hash<ExceptionInfo> ex) {
                string driver = cluster_processes.getDriverName();
                if (*string msg = restart_transaction(driver, ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }

                if (duplicate_key(driver, ex)) {
                    startupMessageMaster("cannot start master %y: conflict with existing master with the same "
                        "configuration (duplicate key error in clsuter_processes); exiting", master_network_id);
                } else {
                    startupMessageMaster("cannot start master %y: %s; exiting", master_network_id,
                        get_exception_string(ex));
                }
                publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, {"ok": False, "status": QSS_ERROR});
                stopCluster();
                thread_exit;
            }
            trans.reset();
            break;
        }

        try {
            if (active) {
                if (recover) {
                    recoverActiveMaster(node, master_network_id);
                }
            } else {
                if (recover) {
                    recoverPassiveMaster();
                }
                registerWithActive();
            }
        } catch (hash<ExceptionInfo> ex) {
            startupMessageMaster("cannot start master %y: %s; exiting", master_network_id, get_exception_string(ex));
            publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, {"ok": False, "status": QSS_ERROR});
            stopCluster();
            thread_exit;
        }
    }

    #! Handover the active role to a passive master if a signal is raised
    private bool shutdownHandoverActiveToPassive() {
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                cluster_processes.getDatasource().beginTransaction();

                on_error cluster_processes.rollback();
                on_success cluster_processes.commit();

                *hash<auto> row = getCurrentMasterRowForUpdateIntern();
                if (!row) {
                    log(LoggerLevel::INFO, "master row for %y disappeared during handover", master_network_id);
                    return False;
                }

                bool rv = handoverActiveToPassive(True);
                if (rv) {
                    # NOTE: do not block processes here, as it can lead to a deadlock
                    killAllLocalProcesses();

                    QDBG_LOG("shutdown / handover: deleting cluster_processes row");

                    cluster_processes.del({"process_network_id": master_network_id});
                    QDBG_LOG("deleted cluster_processes row for %y", master_network_id);
                }
                return rv;
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                log(LoggerLevel::ERROR, "%s", get_exception_string(ex));
                log(LoggerLevel::ERROR, "trying again in 15 seconds...");
                sleep(15);
                continue;
            }
            break;
        }
        return False;
    }

    #! Force a failover of the active role to the first passive master
    /** @return True if the failover was successful, False if no passive masters are available

        @note this is called in a transaction recovery while loop for the cluster_processes table
    */
    private bool handoverActiveToPassive(*bool kill_processes) {
        # try to force a failover of the chosen passive master
        while (True) {
            *string id = getNewActiveMasterIdIntern();
            if (!id) {
                log(LoggerLevel::INFO, "no passive masters; continuing %s", kill_processes
                    ? "active master and Qorus cluster shutdown"
                    : "with active master recovery");
                return False;
            }
            # get the queue info for the passive master
            *hash<auto> row = cluster_processes.selectRow({
                "where": {
                    "process_network_id": id,
                },
            });
            if (!row) {
                log(LoggerLevel::INFO, "row disappeared for passive master %y; ignoring", id);
                continue;
            }

            log(LoggerLevel::INFO, "triggering an active takeover for master %y", id);

            QorusPassiveMasterProcess master_proc(self, <ClusterProcInfo>{
                "node": row.node,
                "host": row.host,
                "pid": row.pid,
                "queue_urls": row.queue_urls.split(","),
            }, row.created);
            QorusMasterClient client = master_proc.getClient();
            Queue msg_queue = client.sendCmdAsync(CPC_MR_DO_ACTIVE_TAKEOVER, {
                "old_master_node": node,
                "old_master_id": master_network_id,
                "old_master_recovered": True,
                "processes_killed": kill_processes,
            });
            on_exit {
                # cancel async call
                client.cancelAsyncCmd();
            }

            # we must release the transaction lock here, so the other process can update the process table
            cluster_processes.commit();

            # wait for an answer
            bool ok;
            while (True) {
                try {
                    msg_queue.get(NodeMemoryTimeout);
                    ok = True;
                    break;
                } catch (hash<ExceptionInfo> ex) {
                    if (ex.err == "QUEUE-TIMEOUT") {
                        # get active master row to check heartbeat
                        row = cluster_processes.selectRow({
                            "where": {
                                "process_network_id": id,
                            },
                        });
                        if (!row) {
                            log(LoggerLevel::WARN, "row disappeared for passive master %y; ignoring", id);
                            break;
                        }
                        if (!row.queue_urls) {
                            log(LoggerLevel::WARN, "passive master %y has no ZeroMQ URL; ignoring", id);
                            break;
                        }
                        string url = row.queue_urls.split(".")[0];
                        if (url != client.getUrls()[0]) {
                            log(LoggerLevel::INFO, "passive master %y has a new ZeroMQ URL: %y; updating and retrying", id, url);
                            hash<ClusterProcInfo> info = <ClusterProcInfo>{
                                "id": id,
                                "queue_urls": (url,),
                                "node": row.node,
                                "host": row.host,
                                "pid": row.pid,
                            };
                            updateUrls(id, info, row.modified);
                            abortedProcessNotification(id, info, True, row.modified);
                            continue;
                        }

                        date cutoff = now_us() - MasterCutoffInterval;
                        if (row.heartbeat > cutoff) {
                            log(LoggerLevel::WARN, "passive master %y on node %y did not respond to the takeover message in the "
                                "timeout period (%y) but has a valid heartbeat (%y); retrying",
                                id, row.node, NodeMemoryTimeout, row.heartbeat);
                            continue;
                        }

                        killPassiveNodeStartup(master_proc, row);
                        break;
                    } else {
                        rethrow;
                    }
                }
            }
            if (!ok) {
                continue;
            }

            # wait for passive node to become the master node
            date now = now_us();
            log(LoggerLevel::INFO, "waiting for %y to take over the active master role (timeout %y)", id, NodeMemoryTimeout);

            while (True) {
                *hash<auto> active_master_row = cluster_processes.selectRow({
                    "where": {
                        "process_network_id": id,
                        "active_master": 1,
                    },
                });
                if (active_master_row) {
                    log(LoggerLevel::INFO, "passive master %y has claimed the active role", id);
                    return True;
                }
                if ((now_us() - now) > NodeMemoryTimeout) {
                    log(LoggerLevel::INFO, "passive master %y did not take over the active role in the timeout period (%y); "
                        "retrying", id, NodeMemoryTimeout);
                    break;
                }
                sleep(1s);
            }

            # reacquire transaction lock on our row
            cluster_processes.getDatasource().beginTransaction();

            # check if there is a master process in the process table already
            row = getCurrentMasterRowForUpdateIntern();
            if (!row) {
                throw "RECOVERY-ERROR", sprintf("master row for %y disappeared during recovery", master_network_id);
            }

            continue;
        }
    }

    #! Kills all processes on a passive node and removes the processes from the DB during startup
    private killPassiveNodeStartup(QorusPassiveMasterProcess master_proc, hash<auto> master_row) {
        log(LoggerLevel::INFO, "passive master %y on node %y did not responsd to the takeover message in the "
            "timeout period (%y) and has a invalid heartbeat (%y); recovering node",
            master_row.process_network_id, master_row.node, NodeMemoryTimeout, master_row.heartbeat);

        # in case the process is still running and can receive messages, we tell the passive master to terminate
        QDBG_ASSERT(master_proc.getPid() > 0);
        master_proc.terminate();

        # now we get a list of non-internal processes on the node
        *hash<auto> q = selectFromTable(cluster_processes, {
            "where": {
                "node": master_row.node,
                "process_network_id": op_ne(master_row.process_network_id),
            }
        });

        # first get a list of non-internal processes on the node
        *list<int> pids = map $1.pid, q.contextIterator(), !$1.queue_urls && $1.pid;
        # process internal processes with network queues and a PID
        context (q) where (%queue_urls && %pid) {
            log(LoggerLevel::INFO, "processing process %y on failed node %y (%s:%d)", %process_network_id, %node,
                %host, %pid);
            AbstractQorusProcess proc = getRecoverProcess(%%);
            QDBG_ASSERT(proc instanceof AbstractQorusInternProcess);
            cast<AbstractQorusInternProcess>(proc).terminate({"pids": pids});
            deleteProcessRowCommit(%process_network_id);
        }
        # process other processes
        context (q) where (!%queue_urls || !%pid) {
            log(LoggerLevel::INFO, "processing process %y on failed node %y (%s:%d)", %process_network_id, %node,
                %host, %pid);
            deleteProcessRowCommit(%process_network_id);
        }

        log(LoggerLevel::INFO, "cleaned up %d failed process%s on node %y (host %y)", q.pid.size(),
            q.pid.size() == 1 ? "" : "es", master_row.node, master_row.host);
    }

    #! Handles a KILL-PROC message
    private *hash<auto> handleKillProcMessage(hash<auto> h) {
        QDBG_LOG("handleKillProcMessage() %y", h);
        if (h.kill_self) {
            # kill all processes on the current node immediately
            *hash<string, AbstractQorusProcess> ph;
            {
                m.lock();
                on_exit m.unlock();

                ph = cast<*hash<string, AbstractQorusProcess>>(
                    map {$1.key: $1.value}, self.ph.pairIterator(), $1.value.getNode() == node
                );
            }
            map $1.terminate(), ph.iterator();
        }

        return AbstractQorusClusterApi::handleKillProcMessage(h);
    }

    #! passive master notifies the active master that it's running
    private registerWithActive() {
        try {
            *hash<string, bool> running_procs;
            {
                m.lock();
                on_exit m.unlock();

                running_procs = map {$1.key: True}, ph.pairIterator(), $1.value.getNode() == node;
            }

            # we must have our memory footprint initialized by now
            hash<auto> node_memory_info = getNodeMemoryInfo();
            QDBG_LOG("QorusMaster::registerWithActive() NMI: %y", node_memory_info);
            QDBG_ASSERT(node_memory_info.node_ram_in_use);
            QDBG_ASSERT(active_master);
            hash<auto> msg = {
                "info": getClusterProcessInfo(),
                "node_memory_info": node_memory_info,
                "mem_history": mem_history{node},
                "proc_history": proc_history{node},
                "running_procs": running_procs,
                "start_timestamp": now_us(),
            };
            QDBG_LOG("registering passive master with active: %y", msg);
            active_master.sendCheckResponse(CPC_MR_NEW_PASSIVE_MASTER, msg, CPC_ACK);
            QDBG_LOG("active master confirmed registration");
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "failed to registed with active master: %s", get_exception_string(ex));
        }
    }

    #! returns node memory info for inter-master memory reporting
    private hash<auto> getNodeMemoryInfo() {
        return node_memory_info + {
            "machine_ram_total": machine_ram_total,
            "machine_load_pct": machine_load_pct,
        };
    }

    #! check for an active master when starting a new qorus-master process on a node
    /** if there is a qorus-master process in active mode, then this process must start in passive mode

        @return the ID of the old active master process, if any

        @note this is called in a while loop in a restartable transaction
    */
    *string checkActiveMaster() {
        # check if there is an active master process in the process table already
        hash<auto> sh = {
            "where": {
                "process_type": QDP_NAME_QORUS_MASTER,
                "active_master": 1,
            },
        };
        *hash<auto> row = cluster_processes.selectRow(sh);
        if (row) {
            if (checkProcessAlive(row, False)) {
                log(LoggerLevel::INFO, "active master found on node %y with ID %y; starting in passive mode", row.node, row.process_network_id);
                active_master_network_id = row.process_network_id;
                active = False;
                # setup connection to active master
                setUrls(row.process_network_id, row.queue_urls.split(","));
                active_master = new QorusMasterClient(self, row.node, master_network_id);
                active_master_node = row.node;
                log(LoggerLevel::INFO, "created connection to active master");
            } else {
                log(LoggerLevel::INFO, "no active master; removing row for unavailable active master %y; starting in active "
                    "mode", row.process_network_id);
                cluster_processes.del({"process_network_id": row.process_network_id});
                active = True;
                return row.process_network_id;
            }
        } else {
            log(LoggerLevel::INFO, "no active master; starting in active mode");
            active = True;
        }
    }

    #! selects zero or more rows in hash or lists format from the given table and restarts the select if it fails with a cluster failover error
    /** does not commit the transaction

        useful as the first select in a transaction or a standalone select
    */
    *hash<auto> selectFromTable(AbstractTable table, hash<auto> select_hash) {
        QDBG_ASSERT(!table.getDatasource().currentThreadInTransaction());
        QorusRestartableTransaction trans(table.getDriverName());
        while (True) {
            try {
                on_error table.rollback();

                return table.select(select_hash);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
        }
    }

    #! check if the given process is running
    bool checkProcessRunning(string id, string node, *bool old_active_recovered, *bool processes_killed, reference<*hash<auto>> process_info) {
        try {
            *hash<auto> row = selectRowFromTable(cluster_processes, {
                "where": {
                    "process_network_id": id,
                },
            });
            if (!row || (processes_killed && row.node == node) || !(process_info = checkProcessAlive(row))) {
                return False;
            }
            # kill process if it's running on a node being recovered that's not the current node
            if (!opts.independent && !old_active_recovered && row.node == node && node != self.node) {
                log(LoggerLevel::INFO, "terminating running process %y on node %y pid %d as the node has failed", id,
                    node, row.pid);
                AbstractQorusProcess proc = getRecoverProcess(row);
                proc.setDetached(row.pid, row.queue_urls.split(","), row.created);
                proc.terminate();
                if (id == QDP_NAME_QORUS_CORE) {
                    failover_restart_qorus_core_abort_timestamp = now_us();
                    failover_restart_qorus_core = True;
                }
                remove process_info;
                # we have a lock on the row, so this operation must succeed
                deleteProcessRowCommit(row);
                # do not add to fail list, as then processes will be notified that it will not be restarted
                return False;
            }
            QDBG_LOG("checkProcessRunning() id: %y row.node: %y node: %y self.node: %y ALIVE OK", id, row.node, node,
                self.node);
            log(LoggerLevel::INFO, "process %y is running on node %y", id, row.node);
            return True;
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "%s", get_exception_string(ex));
            rethrow;
        }
    }

    #! Removes a process from the process hash during active master recovery
    private:internal forceRemoveProcess(string id) {
        m.lock();
        on_exit m.unlock();

        *AbstractQorusProcess proc = remove ph{id};
        if (proc) {
            proc.detach();
            remove node_process_map{proc.getNode()}{id};
            remove ignore_abort_hash{id};
            remove dependent_process_hash{id};
        }
    }

    #! recover a failed master process on a node
    /* restart any processes in the list that are not running and notify existing processes of restarted processes
    */
    private recoverPassiveMaster() {
        hash<auto> sh = {
            "where": {
                "process_network_id": op_ne(master_network_id),
                "node": node,
            },
            "forupdate": True,
        };

        hash<auto> q;
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                cluster_processes.getDatasource().beginTransaction();
                on_error cluster_processes.rollback();

                q = cluster_processes.select(sh);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }

        hash<string, hash<ProcessTerminationInfo>> aborted_hash;

        on_error cluster_processes.rollback();
        on_success cluster_processes.commit();

        context (q) {
            if (!%pid) {
                log(LoggerLevel::INFO, "ignoring not started process %y on passive master", %process_network_id);
                # the active master will delete the row
                continue;
            }

            log(LoggerLevel::INFO, "recovering process %y on passive master", %process_network_id);

            AbstractQorusProcess proc = getRecoverProcess(%%);

            try {
                *hash<auto> ih = checkProcessAlive(%%);
                if (ih) {
                    proc.setDetached(%%);
                    addRecoveredProcess(proc, True);
                } else if (active_master) {
                    # issue #3959: add to aborted hash to notify active master
                    aborted_hash{%process_network_id} = <ProcessTerminationInfo>{
                        "proc": proc,
                        "restart": proc.restartProcess(),
                    };
                }
            } catch (hash<ExceptionInfo> ex) {
                log(LoggerLevel::WARN, "ignoring process %y: %s", %process_network_id, get_exception_string(ex));
            }
        }

        if (aborted_hash) {
            log(LoggerLevel::INFO, "the following processes have died on node %y: %y", node, keys aborted_hash);
            # issue #3959: notify active master of aborted processes
            handleAbortedProcessesIntern(aborted_hash);
        }

        log(LoggerLevel::INFO, "passive master %y on node %y: recovered %d process%s", master_network_id, node,
            q.firstValue().lsize(), q.firstValue().lsize() == 1 ? "" : "es");
    }

    #! recover a failed master process on a node
    /** restart any processes in the list that are not running and notify existing processes of restarted processes
    */
    private bool recoverActiveMaster(string old_master_node, string old_master_id, *bool old_active_recovered,
            *bool processes_killed) {
        # list of restarted processes
        softlist<AbstractQorusProcess> rl = ();
        # list of failed processes
        softlist<AbstractQorusProcess> fl = ();

        list<string> id_list = (master_network_id,);
        if (old_active_recovered) {
            id_list += old_master_id;
        }

        # see if there is a qorus-core process still running
        # because if not, then we want to discard interface process rows, as they will be recovered later
        bool qorus_core_running;
        code psort = int sub (hash<auto> l, hash<auto> r) {
            # sort qorus-core first if running
            if (qorus_core_running) {
                if (l.process_type == QDP_NAME_QORUS_CORE) {
                    return r.process_type == QDP_NAME_QORUS_CORE ? l.client_id <=> r.client_id : -1;
                }
                if (r.process_type == QDP_NAME_QORUS_CORE) {
                    return 1;
                }
            }

            # recover datasource pool processes second
            if (l.process_type == QDP_NAME_QDSP) {
                return r.process_type == QDP_NAME_QDSP ? l.client_id <=> r.client_id : -1;
            }
            if (r.process_type == QDP_NAME_QDSP) {
                return 1;
            }

            # recover qorus-core last (if not running)
            if (l.process_type == QDP_NAME_QORUS_CORE) {
                return r.process_type == QDP_NAME_QORUS_CORE ? l.client_id <=> r.client_id : 1;
            }
            if (r.process_type == QDP_NAME_QORUS_CORE) {
                return -1;
            }

            return l.client_id <=> r.client_id;
        };

        # all existing cluster process rows on the node
        *list<auto> cpl;

        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        {
            hash<auto> sh = {
                "where": {
                    "process_network_id": op_not(op_in(id_list)),
                },
                "forupdate": True,
            };

            while (True) {
                try {
                    # mark transaction in progress
                    cluster_processes.getDatasource().beginTransaction();
                    on_error cluster_processes.rollback();

                    # get all existing cluster process rows
                    cpl = cluster_processes.selectRows(sh);
                } catch (hash<ExceptionInfo> ex) {
                    if (*string msg = trans.restartTransaction(ex)) {
                        log(LoggerLevel::WARN, "%s", msg);
                        continue;
                    }
                    rethrow;
                }
                trans.reset();
                break;
            }
        }

        on_error cluster_processes.rollback();
        on_success cluster_processes.commit();

        # get process information for all processes keyed by process ID
        *hash<string, hash<auto>> process_info_map = getProcessInfoMap(cpl, old_master_node, processes_killed);
        QDBG_LOG("processes_running: %y", keys process_info_map);

        qorus_core_running = process_info_map{QDP_NAME_QORUS_CORE} ? True : False;
        logInfo("active master failover: qorus-core is %s running", qorus_core_running ? "still" : "not");

        # list of process rows to be discarded (processes not running, will be recovered by qorus-core)
        list<string> discard_list();

        # list of workflow IDs to have their sessions cleared (qwf processes not running, sessions
        # to be recovered in global session recovery in qorus-core)
        list<int> discard_wfid_list();

        # list of job IDs to have their sessions cleared (qjob processes not running, sessions
        # to be recovered in global session recovery in qorus-core)
        list<int> discard_jobid_list();

        # ensure that discarded rows are processed on exit if not already processed
        # (such as below right before qorus-core is recovered)
        on_exit if (discard_list || discard_wfid_list || discard_jobid_list)
            discardProcesses(discard_list, discard_wfid_list, discard_jobid_list);

        # sort the process rows as per above
        cpl = sort(cpl, psort);

        QDBG_LOG("cpl: %y", cpl);

        #QDBG_LOG("ph: %y", keys ph);
        #QDBG_LOG("tph: %y", keys tph);

        # timestamp for handling aborted processes
        date abort_timestamp = now_us();

        # first get a count of nodes and processes; node -> process count
        hash<string, int> node_proc_count_map;
        map ++node_proc_count_map{$1.node}, cpl;

        foreach hash<auto> row in (cpl) {
            log(LoggerLevel::DEBUG, "starting recovery of %y", row);
            try {
                AbstractQorusProcess proc;
                # if the process is cached locally, then remove it for further processing
                if (row.node == self.node) {
                    m.lock();
                    on_exit m.unlock();

                    if (ph{row.process_network_id}) {
                        proc = ph{row.process_network_id};
                        QDBG_LOG("got already cached process %y", row.process_network_id);
                    }
                }
                # issue #3395: temporary entries with no PID should be deleted immediately
                if (!row.pid) {
                    # if we were starting on the
                    # we have a lock on the row, so this operation must succeed
                    deleteProcessRow(row);
                    if (proc) {
                        forceRemoveProcess(row.process_network_id);
                    }

                    continue;
                }

                bool proc_recovered;
                if (!proc) {
                    proc = getRecoverProcess(row);
                    proc_recovered = True;
                    QDBG_LOG("created recovery process %y", row.process_network_id);
                } else if (row.queue_urls && row.queue_urls != "-") {
                    # set URLs as the process object in passive masters does not have this information
                    proc.setUrls(row.queue_urls.split(","));
                }
                *hash<auto> ih = process_info_map{row.process_network_id};

                bool terminate;
                if (ih) {
                    if (row.dependent && !qorus_core_running) {
                        log(LoggerLevel::INFO, "terminating dependent process %s PID %d as qorus-core is not running",
                            proc.getId(), proc.getPid());
                        terminate = True;
                    } else if (!old_active_recovered && row.node == old_master_node && old_master_node != self.node) {
                        log(LoggerLevel::INFO, "terminating process %s PID %d as the master process died on node %y",
                            proc.getId(), proc.getPid(), old_master_node);
                        terminate = True;
                    }
                }
                QDBG_LOG("PROC ID %y ih: %y terminate: %y", proc.getId(), keys ih, terminate);

                if (ih && terminate) {
                    if (proc_recovered) {
                        proc.setDetached(row.pid, row.queue_urls.split(","), row.created);
                    } else {
                        forceRemoveProcess(row.process_network_id);
                    }
                    proc.terminate();

                    # issue #3747: always try to restart critical processes
                    if (critical_process_map{row.process_network_id}) {
                        remove ih;
                        terminate = False;
                        log(LoggerLevel::INFO, "restarting critical process %y", row.process_network_id);
                    } else {
                        if (proc_recovered) {
                            proc_recovered = False;
                        }
                        # we have a lock on the row, so this operation must succeed
                        deleteProcessRow(row);
                        fl += proc;
                    }
                }

                if (!ih) {
                    # terminate non-responsive processes
                    if (!proc_recovered && proc.getPid() > 0) {
                        proc.terminate();
                    }
                    forceRemoveProcess(row.process_network_id);

                    if (!qorus_core_running) {
                        if (row.process_type == QDP_NAME_QWF) {
                            # delete failed workflow processes if there is no qorus-core process;
                            # such processes will be restarted by qorus-core and their sessions
                            # will be recovered with global session recovery
                            QwfProcess p = cast<QwfProcess>(proc);
                            discard_list += p.getId();
                            discard_wfid_list += p.getWorkflowId();
                            continue;
                        }

                        if (row.process_type == QDP_NAME_QSVC) {
                            # delete failed service processes if there is no qorus-core process;
                            # such processes will be restarted by qorus-core
                            QsvcProcess p = cast<QsvcProcess>(proc);
                            discard_list += p.getId();
                            continue;
                        }

                        if (row.process_type == QDP_NAME_QJOB) {
                            # delete failed qjob processes if there is no qorus-core process;
                            # such processes will be restarted by qorus-core
                            QjobProcess p = cast<QjobProcess>(proc);
                            discard_list += p.getId();
                            discard_jobid_list += p.getJobId();
                            continue;
                        }

                        if (row.process_type == QDP_NAME_QDSP) {
                            string id = proc.getId();
                            discard_list += id;
                            # mark qdsp processes for recovery by qorus-core and restart messages when restarted
                            qdsp_recovery_map{row.client_id} = proc;
                            continue;
                        }
                    }

                    if (row.process_type == QDP_NAME_QORUS_MASTER) {
                        # delete failed passive master processes
                        discard_list += proc.getId();
                        continue;
                    }

                    # discard rows before recovering qorus-core
                    if (row.process_type == QDP_NAME_QORUS_CORE
                        && (discard_list || discard_wfid_list || discard_jobid_list)) {
                        discardProcesses(discard_list, discard_wfid_list, discard_jobid_list);
                        remove discard_list;
                        remove discard_wfid_list;
                        remove discard_jobid_list;
                    }

                    # recover the failed process
                    int prc;
                    if (row.process_type == QDP_NAME_QORUS_CORE && opts.independent) {
                        prc = BP_IGNORE_RESTART;
                    } else {
                        string proc_id = proc.getId();

                        # ensure that cluster program starts and stops happen atomically
                        AtomicProcessHelper aph(proc_id);
                        try {
                            # assign new node for process
                            proc.setRestarting();
                            # restart process
                            prc = addRestartProcess(proc);
                            if (prc == BP_RESTARTED) {
                                # update URLs, if applicable
                                if (proc.getUrls()) {
                                    updateUrls(proc_id, proc.getClusterProcInfo(), now_us());
                                }
                            }
                        } catch (hash<ExceptionInfo> ex) {
                            if (ex.err =~ /INSUFFICIENT-/) {
                                log(LoggerLevel::ERROR, "%s: %s", ex.err, ex.desc);
                            } else {
                                log(LoggerLevel::ERROR, "%s", get_exception_string(ex));
                            }
                            prc = BP_RESTART_FAILED;
                        }
                    }

                    switch (prc) {
                        case BP_RESTARTED:
                            rl += proc;
                            log(LoggerLevel::INFO, "successfully restarted %s %y on %s PID %d at %y",
                                row.process_type, proc.getId(), proc.getNode(), proc.getPid(), proc.getUrls());
                            row = proc.getClusterProcessesRow();
                            QDBG_ASSERT(row.process_network_id == proc.getId());
                            while (True) {
                                try {
                                    on_error cluster_processes.rollback();
                                    on_success cluster_processes.commit();

                                    cluster_processes.update(row + ("created": now_us()) - "process_network_id",
                                        {"process_network_id": proc.getId()});
                                } catch (hash<ExceptionInfo> ex) {
                                    if (*string msg = trans.restartTransaction(ex)) {
                                        log(LoggerLevel::WARN, "%s", msg);
                                        continue;
                                    }
                                    rethrow;
                                }
                                break;
                            }
                            switch (row.process_type) {
                                # qorus-core is recovered last
                                case QDP_NAME_QORUS_CORE:
                                    start_status = QSS_RECOVERED;
                                    waitForQorusCore();
                                    break;
                                case QDP_NAME_QWF:
                                    QwfProcess p = cast<QwfProcess>(proc);
                                    if (sessionid == "-" && !qorus_core_running) {
                                        sessionid = p.getSessionId().toString();
                                        log(LoggerLevel::INFO, "marking sessionid %d to be continued when restarting "
                                            "qorus-core", sessionid);
                                    }
                                    break;
                            }
                            break;

                        case BP_ALREADY_RESTARTED:
                            log(LoggerLevel::INFO, "process %s %y at %y was already restarted", row.process_type,
                                proc.getId(), proc.getUrls());
                            if (row.process_type == QDP_NAME_QORUS_CORE)
                                start_status = QSS_ALREADY_RUNNING;
                            break;

                        case BP_RESTART_FAILED:
                            logStartup("failed to restart %s %y", row.process_type, row.process_network_id, );
                            fl += proc;
                            # cannot restart process
                            # we have a lock on the row, so this operation must succeed
                            deleteProcessRow(row);
                            if (row.process_type == QDP_NAME_QORUS_CORE) {
                                start_status = QSS_ERROR;
                            }
                            break;

                        case BP_IGNORE_RESTART:
                            logStartup("ignoring restart for %s %y", row.process_type, row.process_network_id);
                            fl += proc;
                            # cannot restart process
                            # we have a lock on the row, so this operation must succeed
                            deleteProcessRow(row);
                            if (row.process_type == QDP_NAME_QORUS_CORE) {
                                start_status = QSS_ERROR;
                            }
                            break;
                    }
                } else {
                    # process is alive
                    #log(LoggerLevel::DEBUG, "ih: %y", ih);
                    #log(LoggerLevel::DEBUG, "row: %y", row);
                    if (proc_recovered) {
                        proc.trySetDetached(row);
                    }
                    if (row.dependent) {
                        string id = proc.getId();
                        dependent_process_hash{id} = True;
                        ignore_abort_hash{id} = True;
                    }

                    switch (row.process_type) {
                        case QDP_NAME_QORUS_CORE:
                            start_status = QSS_ALREADY_RUNNING;
                            break;
                        case QDP_NAME_QWF:
                            QwfProcess p = cast<QwfProcess>(proc);
                            if (!qorus_core_running) {
                                if (sessionid == "-") {
                                    sessionid = p.getSessionId().toString();
                                    log(LoggerLevel::INFO, "marking sessionid %d to be continued when restarting "
                                        "qorus-core", sessionid);
                                }
                                running_wfid_list += p.getWorkflowId();
                            }
                            break;
                        case QDP_NAME_QSVC:
                            QsvcProcess p = cast<QsvcProcess>(proc);
                            if (!qorus_core_running) {
                                running_svcid_list += p.getServiceRecoveryKey();
                            }
                            break;
                        case QDP_NAME_QJOB:
                            QjobProcess p = cast<QjobProcess>(proc);
                            if (!qorus_core_running) {
                                if (sessionid == "-") {
                                    sessionid = p.getSessionId().toString();
                                    log(LoggerLevel::INFO, "marking sessionid %d to be continued when restarting "
                                        "qorus-core", sessionid);
                                }
                                running_jobid_list += p.getJobId();
                            }
                            break;
                    }

                    if (proc_recovered) {
                        addRecoveredProcess(proc, node_proc_count_map{row.node} > 1);
                    }
                }
            } catch (hash<ExceptionInfo> ex) {
                log(LoggerLevel::ERROR, "%s", get_exception_string(ex));
            }
        }

        if (cpl && !start_status)
            start_status = QSS_RECOVERED;

        hash<string, bool> exclude_hash = map {$1.getId(): True}, fl;
        # do not notify processes that have failed, this process, or processes that have just restarted
        notifyMasterRestart(old_master_id, exclude_hash + (map {$1.getId(): True}, rl));

        # issue #3506: notify processes about QDSP processes that could not be recovered
        {
            m.lock();
            on_exit m.unlock();

            if (qdsp_recovery_map) {
                QDBG_LOG("adding unrecovered qdsp processes to failed list: %y", map $1.getId(),
                    qdsp_recovery_map.values());
                fl += (remove qdsp_recovery_map).values();
            }
        }

        # notify cluster of restarted and failed processes
        map notifyAbortedProcessAllInitial($1.getId(), exclude_hash, abort_timestamp), rl + fl;
        map notifyAbortedProcessAll(NOTHING, $1.getId(), $1.getClusterProcInfo(), True, abort_timestamp, exclude_hash), rl;
        map notifyAbortedProcessAll(NOTHING, $1.getId(), NOTHING, False, abort_timestamp, exclude_hash), fl;

        if (failover_restart_qorus_core) {
            QDBG_ASSERT(!opts.independent);
            failover_restart_qorus_core_list = map $1.getId(), ph.iterator(),
                $1 instanceof AbstractQorusInterfaceProcess && !exclude_hash{$1.getId()};
        }

        logStartup("node %y active master recovery complete", old_master_node);
        return qorus_core_running;
    }

    #! Returns a hash of running process information keyed by process ID
    /** checks all processes in parallel
    */
    *hash<string, hash<auto>> getProcessInfoMap(*list<auto> cpl, string old_master_node, *bool processes_killed) {
        hash<string, hash<auto>> rv;

        list<hash<ZmqPollInfo>> poll_list;

        foreach hash<auto> row in (cpl) {
            if ((processes_killed && row.node == old_master_node) || !row.pid) {
                continue;
            }

            string type = row.process_type;
            string id = row.process_network_id;

            if (ExternalProcesses{type}) {
                *hash<auto> info = checkExternalProcessAlive(type, id, row.node, row.pid);
                if (info) {
                    rv{id} = info;
                }
                continue;
            }

            # is this process local
            bool is_local;
            if (row.node == node) {
                if (!Process::checkPid(row.pid)) {
                    logStartup("* %s %y (%s:%s: %y) no longer exists; clearing", type, id, row.node, row.pid,
                        row.queue_urls.split(",")[0]);
                    continue;
                }
                is_local = True;
            }

            # issue #3770: do not try to connect to processes that are starting
            if (row.queue_urls == "-") {
                logStartup("* %s %y (%s:%s: %y) is starting; clearing", type, id, row.node, row.pid,
                    row.queue_urls.split(",")[0]);
                continue;
            }

            string our_id = sprintf("master-%s-%s-%d-%d", node, row.process_network_id, getpid(), gettid());
            QorusRecoveryZSocketDealer sock(getContext(), nkh, our_id, row);

            logStartup("* recovering %s %y (%s:%d: %y)", row.process_type, row.process_network_id, row.node,
                row.pid, sock.endpoint());

            # send "GET-INFO" message to remote process
            sock.send("1", CPC_GET_INFO);

            # add socket to poll list
            poll_list += <ZmqPollInfo>{
                "socket": sock,
                "events": ZMQ_POLLIN,
            };
        }

        # wait for async responses
        date delta = DefaultRecoverTimeout;
        date start = now_us();
        date last_report = start;

        while (poll_list) {
            if (delta < 0s) {
                # no time left in timeout period
                break;
            }
            # the poll() call will return an empty list if no data is available
            list<hash<ZmqPollInfo>> current_list = ZSocket::poll(poll_list, delta);
            if (!current_list) {
                # no more info in the polling period
                break;
            }

            # process messages received
            foreach hash<ZmqPollInfo> poll_hash in (current_list) {
                QorusRecoveryZSocketDealer sock = cast<QorusRecoveryZSocketDealer>(poll_hash.socket);
                string id = sock.getRow().process_network_id;
                ZMsg msg = sock.recvMsg();
                # remove mboxid
                msg.popStr();
                *string cmd = msg.popStr();
                if (cmd != CPC_OK) {
                    logStartup("* %y: ignoring invalid response to GET-INFO msg (%y)", id, cmd);
                } else {
                    rv{id} = qorus_cluster_deserialize(msg);
                }
            }

            # remove all polled sockets from poll list
            foreach hash<ZmqPollInfo> poll_hash_current in (current_list) {
                foreach hash<ZmqPollInfo> poll_hash_orig in (poll_list) {
                    if (poll_hash_current.socket == poll_hash_orig.socket) {
                        splice poll_list, $#, 1;
                        break;
                    }
                }
            }

            date now = now_us();
            delta = DefaultRecoverTimeout - (now - start);
            if (poll_list && ((now - last_report) > 2s)) {
                logStartup("* still waiting for %d process%s to respond", poll_list.size(),
                    poll_list.size() == 1 ? "" : "es");
                last_report = now;
            }
        }

        # log processes assumed dead
        foreach hash<ZmqPollInfo> poll_hash in (poll_list) {
            QorusRecoveryZSocketDealer sock = cast<QorusRecoveryZSocketDealer>(poll_hash.socket);
            hash<auto> row = sock.getRow();
            logStartup("* %s %y (%s:%s: %y) no response; assuming dead; clearing", row.process_type,
                row.process_network_id, row.node, row.pid, sock.endpoint());
        }

        return rv;
    }

    #! adds a recovered process to the process hash
    private addRecoveredProcess(AbstractQorusProcess proc, bool shared_node) {
        # add to process hash
        {
            m.lock();
            on_exit m.unlock();

            string id = proc.getId();
            string proc_node = proc.getNode();
            QDBG_ASSERT(!ph{id});
            ph{id} = node_process_map{proc_node}{id} = proc;
            switch (proc.getName()) {
                case QDP_NAME_QORUS_CORE:
                    QDBG_ASSERT(!qorus_core);
                    qorus_core = cast<QorusCoreProcess>(proc);
                    break;
                case QDP_NAME_PROMETHEUS:
                    prometheus = cast<PrometheusProcess>(proc);
                    break;
                case QDP_NAME_GRAFANA:
                    grafana = cast<GrafanaProcess>(proc);
                    break;
                case QDP_NAME_QWF:
                    wph{id} = proc;
                    break;
                case QDP_NAME_QDSP:
                    qdsp_map{id} = proc;
                    break;
                case QDP_NAME_QORUS_MASTER:
                    QorusPassiveMasterProcess pm = cast<QorusPassiveMasterProcess>(proc);
                    passive_master_node_map{pm.getNode()} = passive_master_id_map{id} = pm;
                    break;
            }
            log(LoggerLevel::INFO, "successfully recovered process %y (node %y pid %d)", proc.getId(), proc.getNode(),
                proc.getPid());
        }
        # WARNING: do not make any ZMQ calls while holding the "m" lock; it will cause a deadlock
        if (active && proc.getName() == QDP_NAME_QORUS_CORE) {
            log_subscribed += qorus_core.processRecovered();
        }
    }

    private hash<ClusterProcInfo> getClusterProcessInfo() {
        return <ClusterProcInfo>{
            "id": master_network_id,
            "queue_urls": master_urls,
            "node": node,
            "host": gethostname(),
            "pid": getpid(),
        };
    }

    private notifyMasterRestart(string old_master_id, *hash<string, bool> exclude) {
        QDBG_LOG("notifyMasterRestart() old: %y new: %y", old_master_id, master_network_id);
        hash<ClusterProcInfo> info = getClusterProcessInfo();
        # unconditionally send the abort message with the new_active_master_id key
        info.new_active_master_id = info.id;
        # inform children of new master process
        date abort_timestamp = now_us();
        *hash<string, hash<ProcessNotificationInfo>> proc_map = notifyAbortedProcessAllInitial(old_master_id, exclude,
            abort_timestamp);
        notifyAbortedProcessAll(proc_map, old_master_id, info, True, abort_timestamp, exclude, True);
        QDBG_LOG("notifyMasterRestart() done");
    }

    int deleteProcessRowCommit(string id) {
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                on_error cluster_processes.rollback();
                on_success cluster_processes.commit();

                return deleteProcessRow(id);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    int deleteProcessRow(string id) {
        int rows = cluster_processes.del({"process_network_id": id});
        QDBG_LOG("delete process row for %y (%y)", id, rows);
        return rows;
    }

    int deleteProcessRowCommit(hash<auto> row) {
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                on_error cluster_processes.rollback();
                on_success cluster_processes.commit();

                return deleteProcessRow(row);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    int deleteProcessRow(hash<auto> row) {
        int rows = cluster_processes.del({
            "process_network_id": row.process_network_id,
            "host": row.host,
            "node": row.node,
            "pid": row.pid,
        });
        QDBG_LOG("delete process row for %y on node %y (%y)", row.process_network_id, row.node, rows);
        return rows;
    }

    discardProcesses(list<string> discard_list, list<int> discard_wfid_list, list<int> discard_jobid_list) {
        AbstractTable workflows = getTable("workflows");
        AbstractTable jobs = getTable("jobs");

        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                on_error cluster_processes.rollback();
                on_success cluster_processes.commit();

                if (discard_list) {
                    cluster_processes.del({"process_network_id": op_in(discard_list)});
                    log(LoggerLevel::INFO, "discarded %d cluster_processes row%s to be recovered by qorus-core",
                        discard_list.size(), discard_list.size() == 1 ? "" : "s");
                }

                if (discard_wfid_list) {
                    workflows.update({"open": 0}, {"workflowid": op_in(discard_wfid_list), "open": 1});
                    log(LoggerLevel::INFO, "updated %d row%s for workflow sessions to be recovered by qorus-core",
                        discard_wfid_list.size(), discard_wfid_list.size() == 1 ? "" : "s");
                }

                if (discard_jobid_list) {
                    jobs.update({"open": 0}, {"jobid": op_in(discard_jobid_list), "open": 1});
                    log(LoggerLevel::INFO, "updated %d row%s for job sessions to be recovered by qorus-core",
                        discard_jobid_list.size(), discard_jobid_list.size() == 1 ? "" : "s");
                }
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    private AbstractQorusProcess getRecoverProcess(hash<auto> row) {
        AbstractQorusProcess proc;
        switch (row.process_type) {
            case QDP_NAME_QORUS_CORE: {
                list<string> cl_opts = options.getCommandLineOptions();
                cl_opts += self.cl_opts;
                proc = new QorusCoreProcess(self, row.node, row.host, True, sessionid, running_wfid_list,
                    running_svcid_list, running_jobid_list, qdsp_recovery_map, cl_opts);
                break;
            }
            case QDP_NAME_QDSP:
                proc = new QdspProcess(self, row.node, row.host, True, row.client_id, parse_yaml(row.info).connstr,
                    getLoggerParams("qdsp", row.client_id, row.client_id), cl_opts);
                break;
            case QDP_NAME_QWF: {
                hash<auto> wfh = parse_yaml(row.info);
                proc = new QwfProcess(self, row.node, row.host, True, wfh.wfid.toString(), wfh.wfname, wfh.wfversion,
                    wfh.stack_size ?? 0,  wfh.sessionid, getLoggerParams("workflows", wfh.wfid, wfh.wfname),
                    cl_opts);
                break;
            }
            case QDP_NAME_QSVC: {
                hash<auto> svch = parse_yaml(row.info);
                proc = new QsvcProcess(self, row.node, row.host, True, svch.svcid.toString(), svch.svctype,
                    svch.svcname, svch.svcversion, svch.stack_size ?? 0,
                    getLoggerParams("services", svch.svcid, svch.svcname), cl_opts);
                break;
            }
            case QDP_NAME_QJOB: {
                hash<auto> jobh = parse_yaml(row.info);
                proc = new QjobProcess(self, row.node, row.host, True, jobh.jobid.toString(), jobh.jobname,
                    jobh.jobversion, jobh.stack_size ?? 0, jobh.sessionid,
                    getLoggerParams("jobs", jobh.jobid, jobh.jobname), cl_opts);
                break;
            }
            case QDP_NAME_QORUS_MASTER: {
                hash<ClusterProcInfo> info = <ClusterProcInfo>{
                    "id": qmaster_get_process_name(row.node),
                    "queue_urls": row.queue_urls.split(","),
                    "node": row.node,
                    "host": row.host,
                    "pid": row.pid,
                };
                proc = new QorusPassiveMasterProcess(self, info, row.created);
                break;
            }
            case QDP_NAME_PROMETHEUS: {
                hash<auto> proc_info = parse_yaml(row.info);
                proc = new PrometheusProcess(self, row.node, row.host, proc_info.port, getLoggerParams("prometheus"));
                break;
            }
            case QDP_NAME_GRAFANA: {
                hash<auto> proc_info = parse_yaml(row.info);
                proc = new GrafanaProcess(self, row.node, row.host, proc_info.prometheus_port, proc_info.socket_path,
                    getLoggerParams("grafana"));
                break;
            }
            default:
                throw "PROCESS-ERROR", sprintf("unrecognized process %y: %y", row.process_type,
                    row.process_network_id);
        }
        return proc;
    }

    #! Sends a one-time message to a remote program without creating a client
    private:internal ZMsg sendAdHocRemoteCheckResponse(string queue_url, string cmd, string str, string expected) {
        # connections can be reused, but the identity must be unique
        string our_id = sprintf("master-%d-%d", getpid(), gettid());
        # create the client socket
        ZSocketDealer sock(zctx);
        # set socket identity
        sock.setIdentity(our_id);
        # setup encryption before connecting
        nkh.setClient(sock);
        # connecto to remote program
        sock.connect(queue_url);
        log(LoggerLevel::DEBUG, "sending %s: %y from %y", cmd, str, our_id);
        # allow requests to time out
        sock.send("1", "self", cmd, str);
        ZMsg msg = sock.recvMsg();
        # ignore msgid
        msg.popStr();
        # get response cmd
        *string rcmd = msg.popStr();
        if (rcmd != expected)
            throw "INVALID-RESPONSE", sprintf("sending %y; expected %y; got %y", cmd, expected, rcmd);
        # return message
        return msg;
    }

    executeMasterHandover() {
        # notify original master that we are up and running
        hash<auto> h;
        try {
            # FIXME: modify to work with multiple URLs
            ZMsg msg = sendAdHocRemoteCheckResponse(opts.daemon, CPC_MR_HANDOVER_COMPLETE, master_urls[0], CPC_OK);
            h = qorus_cluster_deserialize(msg);
            log(LoggerLevel::DEBUG, "got response from old master: %y", h);
        } catch (hash<ExceptionInfo> ex) {
            # log exception and continue processing, assume old master is dead
            log(LoggerLevel::WARN, "%s: %s: %s: ignoring error", get_ex_pos(ex), ex.err, ex.desc);
        }

        # create process entries
        {
            m.lock();
            on_exit m.unlock();

            foreach hash<auto> nph in (h.pairIterator()) {
                QDBG_LOG("creating process %y node %y host %y PID %y URLs %y", nph.key, nph.value.node,
                    nph.value.host, nph.value.pid, nph.value.urls);
                AbstractQorusProcess proc;
                switch (nph.value.type) {
                    case QDP_NAME_QORUS_CORE:
                        proc = new QorusCoreProcess(self, nph.value.node, nph.value.host, nph.value.restarted, sessionid,
                            cast<list<int>>(nph.value.running_wfid_list ?? ()),
                            cast<list<string>>(nph.value.running_svcid_list ?? ()),
                            cast<list<int>>(nph.value.running_jobid_list ?? ()));
                        QDBG_ASSERT(!qorus_core);
                        qorus_core = cast<QorusCoreProcess>(proc);
                        break;
                    case QDP_NAME_PROMETHEUS: {
                        proc = new PrometheusProcess(self, nph.value.node, nph.value.host, nph.value.port,
                            getLoggerParams("prometheus"));
                        prometheus = cast<PrometheusProcess>(proc);
                        break;
                    }
                    case QDP_NAME_GRAFANA: {
                        proc = new GrafanaProcess(self, nph.value.node, nph.value.host, nph.value.prometheus_port,
                            nph.value.socket_path, getLoggerParams("grafana"));
                        grafana = cast<GrafanaProcess>(proc);
                        break;
                    }
                    case QDP_NAME_QDSP:
                        proc = new QdspProcess(self, nph.value.node, nph.value.host, nph.value.restarted,
                            nph.value.client_id, nph.value.connstr, getLoggerParams("qdsp", nph.value.client_id,
                            nph.value.client_id));
                        qdsp_map{proc.getId()} = proc;
                        break;
                    case QDP_NAME_QWF:
                        proc = new QwfProcess(self, nph.value.node, nph.value.host, nph.value.restarted,
                            nph.value.wfid.toString(), nph.value.wfname, nph.value.wfversion,
                            nph.value.stack_size ?? 0, nph.value.sessionid.toInt(),
                            getLoggerParams("workflows", nph.value.wfid, nph.value.wfname));
                        wph{nph.key} = proc;
                        break;
                    case QDP_NAME_QSVC:
                        proc = new QsvcProcess(self, nph.value.node, nph.value.host, nph.value.restarted,
                            nph.value.svcid.toString(), nph.value.svctype, nph.value.svcname, nph.value.svcversion,
                            nph.value.stack_size ?? 0,
                            getLoggerParams("services", nph.value.svcid, nph.value.svcname));
                        break;
                    case QDP_NAME_QJOB:
                        proc = new QjobProcess(self, nph.value.node, nph.value.host, nph.value.restarted,
                            nph.value.jobid.toString(), nph.value.jobname, nph.value.jobversion,
                            nph.value.stack_size ?? 0, nph.value.sessionid.toInt(),
                            getLoggerParams("jobs", nph.value.jobid, nph.value.jobname));
                        break;
                    default:
                        throw "PROCESS-ERROR", sprintf("unrecognized process %y: %y", nph.key, nph.value);
                }
                #log(LoggerLevel::DEBUG, "nph: %y", nph);
                proc.setDetached(nph.value.pid, cast<*list<string>>(nph.value.urls), nph.value.started);
                if (nph.value.type == QDP_NAME_QORUS_CORE) {
                    try {
                        log_subscribed += qorus_core.processRecovered();
                    } catch (hash<ExceptionInfo> ex) {
                        log(LoggerLevel::WARN, "ignoring error retrieving log subscriptions from qorus-core: %s: %s",
                            ex.err, ex.desc);
                    }
                }
                log(LoggerLevel::DEBUG, "set detached %y: pid: %d url: %s (%s)", proc.getId(), proc.getPid(),
                    proc.getNetworkDescription(), proc.uniqueHash());
                ph{nph.key} = node_process_map{nph.value.node}{nph.key} = proc;
            }
        }

        {
            hash<ClusterProcInfo> info = <ClusterProcInfo>{
                "id": master_network_id,
                "queue_urls": master_urls,
                "node": node,
                "host": gethostname(),
                "pid": getpid(),
            };
            # inform children of new master process
            hash<string, hash<ProcessNotificationInfo>> proc_map = notifyAbortedProcessAllInitial(master_network_id,
                NOTHING, starttime);
            notifyAbortedProcessAll(proc_map, master_network_id, info, True, starttime);
        }

        log(LoggerLevel::INFO, "handover complete; managing processes: %y", keys ph);
        started_flag = True;
    }

    string getPubUrl() {
        if (pub_url) {
            return pub_url;
        }
        pub_url_cnt.waitForZero();
        return pub_url;
    }

    openSystemDatasource() {
        # get info for the omq datasource
        code dblog = opts.daemon
            ? sub (int ll, string fmt) {}
            : \log();

        *string systemdb = options.get("systemdb");
        if (!exists systemdb) {
            stderr.printf("ERROR: no definition provided for system datasource 'systemdb' in the option file, "
                "aborting\n");
            exit(QSE_DATASOURCE);
        }

        # FIXME: fix ClusterProcessHelper
        try {
            omqds = new Datasource(systemdb);
            cluster_processes = getTable("cluster_processes");
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::FATAL, "cannot start Qorus; system datasource %y unavailable: %s: %s", systemdb, ex.err,
                ex.desc);
            exit(QSE_DATASOURCE);
        }
    }

    bool isStarted() {
        return started_flag;
    }

    private bool canShutdownQorus() {
        m.lock();
        on_exit m.unlock();

        if (shutdown_qorus_flag) {
            return False;
        }

        shutdown_qorus_flag = True;
        return True;
    }

    private bool canShutdown() {
        m.lock();
        on_exit m.unlock();

        if (shutdown_flag) {
            return False;
        }

        shutdown_flag = True;
        return True;
    }

    bool startShutdownCluster() {
        if (!canShutdown()) {
            return False;
        }
        background stopCluster();
        return True;
    }

    startupMessageCore(string msg) {
        msg = "qorus-core: " + msg;
        logStartup(msg);
        publishEvent(CPC_MR_PUB_STARTUP_MSG, msg);
    }

    startupMessageMaster(string msg) {
        msg = vsprintf("qorus-master: " + msg, argv);
        logStartup(msg);
        publishEvent(CPC_MR_PUB_STARTUP_MSG, msg);
    }

    startupComplete(hash<auto> h) {
        log(LoggerLevel::INFO, "qorus-core: startup complete: %s status: %s", h.ok ? "OK" : "ERROR", h.status);
        if (!started_flag) {
            started_flag = True;
            if (!h.ok) {
                if (opts.independent) {
                    logStartup("qorus-core reported startup errors; waiting for new qorus-core");
                    return;
                }
                # NOTE: do not remove the process or start the cluster shutdown here, this is handled elsewhere if
                # qorus-core does not start, triggered by a thread waiting on the startup_queue
            } else {
                if (start_status == QSS_RECOVERED && h.status == QSS_NORMAL) {
                    h.status = QSS_RECOVERED;
                }
            }
            startup_queue.push(h.ok);
        }

        publishEvent(CPC_MR_PUB_STARTUP_COMPLETE, h);
        startup_msg_sent = True;

        if (h.ok) {
            startClusterInfoThread();
        }
    }

    private startClusterInfoThread() {
        QDBG_LOG("QorusMaster::startClusterInfoThread() cnt: %d", cluster_info_cnt.getCount());
        # start cluster info update thread
        # issue #3540: ensure the cluster info thread can only start once
        if (!cluster_info_cnt.getCount()) {
            cluster_info_cnt.inc();
            on_error {
                cluster_info_cnt.dec();
            }
            background clusterInfoThread();
        }
    }

    shutdownMessageCore(string msg) {
        msg = "qorus-core: " + msg;
        log(LoggerLevel::INFO, "%s", msg);
        publishEvent(CPC_MR_PUB_SHUTDOWN_MSG, msg);
    }

    shutdownMessageMaster(string msg) {
        msg = "qorus-master: " + msg;
        log(LoggerLevel::INFO, "%s", msg);
        publishEvent(CPC_MR_PUB_SHUTDOWN_MSG, msg);
    }

    shutdownCompleteCore(hash<auto> h) {
        log(LoggerLevel::INFO, "qorus-core: shutdown complete");
        publishEvent(CPC_MR_PUB_SHUTDOWN_COMPLETE_CORE, h);
    }

    shutdownCompleteMaster() {
        string msg = "qorus-master: shutdown complete";
        log(LoggerLevel::INFO, "%s", msg);
        publishEvent(CPC_MR_PUB_SHUTDOWN_COMPLETE_MASTER, msg);
    }

    private clusterInfoThread() {
        on_exit {
            cluster_info_cnt.dec();
            QDBG_LOG("exiting cluster info thread");
        }

        hash<auto> h = {
            "name": node,
            "node_priv": 0,
            "node_priv_str": "",
            "node_ram_in_use": 0,
            "node_ram_in_use_str": "",
            "node_cpu_count": 0,
            "node_load_pct": 0.0,
            "processes": 1,
        };

        mem_history{node} = ();
        proc_history{node} = ();

        while (!cluster_info_stop) {
            {
                cluster_info_mutex.lock();
                on_exit cluster_info_mutex.unlock();

                QorusSharedApi::waitCondition(cluster_info_cond, cluster_info_mutex, ClusterInfoUpdateInterval,
                    \cluster_info_stop);
                if (cluster_info_stop) {
                    break;
                }
            }

            # issue #2376: only process info if information is present
            if (node_memory_info.node_priv) {
                # get current timestamp
                date ts = now_us();

                # issue #2402: get current CPU load
                float load_pct = Process::getLoadAvg()[0] / machine_cpus * 100.0;

                # update cluster info; add 1 for the current master process (i.e. this process)
                int proc_count = node_process_map{node}.size() + 1;
                hash<auto> npi = node_memory_info;
                h += npi + {
                    "node_load_pct": load_pct,
                    "processes": proc_count
                };
                publishEvent(CPC_MR_PUB_NODE_INFO, h);

                # add info to history
                unshift mem_history{node}, npi + {"timestamp": ts};
                unshift proc_history{node}, {"count": proc_count, "timestamp": ts};

                # trim off excess history entries
                if (mem_history{node}.size() > HistoryDepth) {
                    splice mem_history{node}, HistoryDepth;
                }
                if (proc_history{node}.size() > HistoryDepth) {
                    splice proc_history{node}, HistoryDepth;
                }
            }
            # publish node info for passive masters
            map publishRemoteNodeInfo($1.key, $1.value), remote_node_memory_info.pairIterator();
        }
    }

    #! published node info for the given node
    private publishRemoteNodeInfo(string node, hash<auto> node_info) {
        QDBG_LOG("QorusMaster::publishRemoteNodeInfo() %y: %y", node, node_info);
        # add one for the passive master process
        int proc_count = node_process_map{node}.size() + (passive_master_node_map{node} ? 1 : 0);
        hash<auto> info = {
            "name": node,
            "node_priv": node_info.node_priv,
            "node_priv_str": node_info.node_priv_str,
            "node_ram_in_use": node_info.node_ram_in_use,
            "node_ram_in_use_str": node_info.node_ram_in_use_str,
            "node_cpu_count": node_info.node_cpu_count,
            "node_load_pct": node_info.node_load_pct,
            "processes": proc_count,
        };
        publishEvent(CPC_MR_PUB_NODE_INFO, info);
    }

    # called when a process's memory footprint changes
    processMemoryUpdated(string id, hash<auto> h) {
        node_memory_info = h{
            "node_priv",
            "node_priv_str",
            "node_ram_in_use",
            "node_ram_in_use_str",
            "node_cpu_count",
            "node_load_pct",
        };
        #QDBG_LOG("QorusMaster::processMemoryUpdated() id: %y h: %y NMI: %y", id, h, node_memory_info);
        publishEvent(CPC_MR_PUB_PROCESS_MEMORY_CHANGE, {"id": id} + h);
    }

    # called when a process fails to start
    string processStartFailed(AbstractQorusProcess proc) {
        string err = AbstractQorusProcessManager::processStartFailed(proc);
        if (!started_flag) {
            stderr.printf("%s\n", err);
        }
        publishEvent(CPC_MR_PUB_PROCESS_START_ERROR, proc.getInfo() + {"error": err});

        doFailedNotifications(proc);

        return err;
    }

    #! notify processes about failed restarts
    private doFailedNotifications(AbstractQorusProcess proc) {
        # issue #3506: do process notification for failed processes
        QDBG_LOG("doFailedNotifications(%y) QRM: %y", proc.getId(), qdsp_recovery_map);

        bool notify;
        string client_id = proc.getClientId();
        {
            m.lock();
            on_exit m.unlock();

            notify = exists (remove qdsp_recovery_map{client_id});
        }

        if (notify) {
            date abort_timestamp = now_us();
            string id = proc.getId();
            *hash<string, hash<ProcessNotificationInfo>> proc_map = notifyAbortedProcessAllInitial(id, NOTHING,
                abort_timestamp);
            notifyAbortedProcessAll(proc_map, id, NOTHING, False, abort_timestamp);
        }
    }

    # returns True if the process already exists; sends a confirmation message to the sender
    private bool checkProcess(int index, string sender, string mboxid, string id) {
        m.lock();
        on_exit m.unlock();

        #log(LoggerLevel::DEBUG, "QorusMaster::checkProcess() sender: %y id: %y ph: %y", sender, id, keys ph);

        if (ph{id}) {
            AbstractQorusProcess proc = ph{id};
            hash<ClusterProcInfo> rh = proc.getClusterProcInfo();
            # send confirmation to caller
            sendResponse(index, sender, mboxid, CPC_OK, {
                "info": rh,
                "already_started": True,
                "started": proc.getStartTime() ?? now_us(),
            });
            return True;
        }

        # if we are handing over, then ignore the request with no response
        if (procs_blocked) {
            return True;
        }

        return False;
    }

    #! returns the max process size for the given process
    private int getEstimatedProcessSize(string id) {
        # estimate for now: qorus-core = 1GB, all others: 125MB
        return (id == QDP_NAME_QORUS_CORE)
            ? 1024 * 1024 * 1024
            : 125 * 1024 * 1024;
    }

    #! returns the node for starting the process or throws an exception if it would exceed memory limits on the node
    /** @throw INSUFFICIENT-MEMORY not enough free memory on node to start process
    */
    private hash<NodeHostInfo> verifyProcessStart(string id, hash<NodeHostInfo> node_info, int proc_size, int max,
            int total_ram) {
        if (critical_process_map{id}) {
            return node_info;
        }
        float overcommit_pct = options.get("allow-node-overcommit-percent");
        int overcommit = (total_ram * overcommit_pct / 100.0).toInt();
        if (max < -overcommit) {
            throw "INSUFFICIENT-MEMORY", sprintf("cannot start process %y on any node due to insufficient memory "
                "(best node: %y with %s RAM would be overcommitted by %s; qorus.allow-node-overcommit-percent: "
                "%d%% = %s)", id, node_info, get_byte_size(total_ram), get_byte_size(-max), overcommit_pct,
                get_byte_size(overcommit));
        }
        #QDBG_LOG("memory verification %y: RAM %s target: %d (%s) overcommit limit: %d %% (%s)", id,
        #    get_byte_size(total_ram), -max, get_byte_size(-max), overcommit_pct, get_byte_size(overcommit));
        return node_info;
    }

    #! returns the node for starting a process
    hash<NodeHostInfo> getNodeForNewProcess(string id) {
        # get estimated process memory footprint size
        int proc_size = getEstimatedProcessSize(id);

        *list<string> node_list;
        {
            m.lock();
            on_exit m.unlock();

            node_list = (node,) + keys passive_master_node_map;
            if (node_list.size() < 2) {
                return verifyProcessStart(id, <NodeHostInfo>{"node": node, "host": gethostname()}, proc_size,
                    (machine_ram_total - machine_ram_in_use) - proc_size, machine_ram_total);
            }
        }

        # find node with best fit

        # get a hash of nodes to free mem after launching the process
        hash<string, int> node_mem_map;
        # map of nodes where the estimated free memory after launching the process is >= NodeMemoryThreshold
        hash<string, int> best_node_mem_map;
        # map of node names -> total RAM
        hash<string, int> node_ram_map;

        m.lock();
        on_exit m.unlock();

        foreach string node in (node_list) {
            int free_mem;
            int total_ram;
            if (node == self.node) {
                free_mem = machine_ram_total - machine_ram_in_use;
                total_ram = machine_ram_total;
            } else {
                free_mem = (remote_node_memory_info{node}.machine_ram_total
                    - remote_node_memory_info{node}.node_ram_in_use) ?? 0;
                total_ram = remote_node_memory_info{node}.machine_ram_total ?? 0;
            }
            int mem = free_mem - proc_size;
            QDBG_LOG("QorusMaster::getNodeForNewProcess() %y: node: %y est mem: %y (free_mem: %y proc_size: %y)", id,
                node, mem, free_mem, proc_size);
            node_mem_map{node} = mem;
            node_ram_map{node} = total_ram;
            if (mem >= NodeMemoryThreshold) {
                best_node_mem_map{node} = mem;
            }
        }
        if (best_node_mem_map) {
            QDBG_LOG("QorusMaster::getNodeForNewProcess() choosing from best nodes: %y", best_node_mem_map);
            node_list = keys best_node_mem_map;

            #return node_list[rand() % node_list.size()];
            string node = node_list[rand() % node_list.size()];
            QDBG_LOG("QorusMaster::getNodeForNewProcess() node: %y (this node: %y) nl: %y", node, self.node, node_list);
            return getNodeHostInfo(node);
        }

        # take the node with the most free memory first
        QDBG_LOG("QorusMaster::getNodeForNewProcess() choosing from nodes according to free highest memory value: %y",
            node_mem_map);
        string max_node;
        int max = MININT;
        foreach hash<auto> i in (node_mem_map.pairIterator()) {
            if (i.value > max) {
                max_node = i.key;
                max = i.value;
            }
        }
        QDBG_ASSERT(max_node);
        QDBG_LOG("QorusMaster::getNodeForNewProcess() node: %y free mem: %y", max_node, max);

        return verifyProcessStart(id, getNodeHostInfo(max_node), proc_size, max, node_ram_map{max_node});
    }

    #! Returns node and host info for the given node
    hash<NodeHostInfo> getNodeHostInfo(string node) {
        if (node == self.node) {
            return <NodeHostInfo>{
                "node": node,
                "host": gethostname()
            };
        }
        return <NodeHostInfo>{
            "node": node,
            "host": passive_master_node_map{node}.getHostName(),
        };
    }

    # returns True if the process was started, False if not
    private bool startProcess(int index, string sender, string mboxid, string client_id, AbstractQorusProcess proc,
            ClusterProcessHelper clph) {
        if (!clph.start()) {
            # process already exists
            hash<auto> row = clph.getRow();
            proc.setDetached(row);
        }

        return registerProcessIntern(index, sender, mboxid, client_id, proc, clph);
    }

    # returns True if the process was started, False if not
    private bool registerProcessIntern(int index, string sender, string mboxid, string client_id,
            AbstractQorusProcess proc, ClusterProcessHelper clph) {
        if (clph.isDependent() ? addDependentProcess(proc) : addProcess(proc)) {
            date start_time = now_us();
            hash<ClusterProcInfo> rh = proc.getClusterProcInfo();
            clph.updateProcess(proc);
            log(LoggerLevel::INFO, "%s %s %y: %y", clph.start() ? "started" : "recovered", client_id, rh.id,
                rh.queue_urls ?? proc.getNetworkDescription());
            # send confirmation to caller
            sendResponse(index, sender, mboxid, CPC_OK, {
                "info": rh,
                "already_started": False,
                "started": start_time,
            });
            return True;
        }

        # we have failed to start the process
        clph.del();
        # return an exception message
        try {
            throw "PROCESS-START-ERROR", sprintf("process %y, see log for more info", proc.getId());
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error starting process %y: %s", proc.getId(), get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
        return False;
    }

    # starts a datasource pool cluster process
    startDatasourcePoolProcess(int index, string sender, string mboxid, hash<auto> h) {
        try {
            string name = qdsp_get_process_name(h.name);

            # build command line options
            list<string> cl_opts = self.cl_opts;
            if (h.args) {
                cl_opts += h.args;
            }

            # ensure that cluster program starts and stops happen atomically
            AtomicProcessHelper aph(name);

            # check if we have such a process already
            if (checkProcess(index, sender, mboxid, name))
                return;

            hash<NodeHostInfo> node_info = getNodeForNewProcess(name);
            ClusterProcessHelper clph(self, node_info.node, QDP_NAME_QDSP, h.name, name);

            while (True) {
                try {
                    # NOTE: the first qdsp process (for "omq") will not have any logger params
                    # as the dsp is needed to retrieve the metadata, so we retrieve it here
                    QdspProcess proc(self, node_info.node, node_info.host, False, h.name, h.connstr,
                        convert_logger_params(h.logger_params)
                            ?? getLoggerParams("qdsp", h.name, h.name),
                        cl_opts);
                    startProcess(index, sender, mboxid, h.name, proc, clph);
                    break;
                } catch (hash<ExceptionInfo> ex) {
                    if (node_info.node != self.node) {
                        log(LoggerLevel::ERROR, "failed to start process %y in remote node %y: %s; retrying", name,
                            node_info.node, get_exception_string(ex));
                        hash<NodeHostInfo> new_node_info = getNodeForNewProcess(name);
                        if (new_node_info != node_info) {
                            clph.updateNode(new_node_info);
                            node_info = new_node_info;
                        }
                        continue;
                    }
                    rethrow;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error starting datasource pool process (%y): %s", h, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    # starts a workflow cluster process
    startWorkflowProcess(int index, string sender, string mboxid, hash<auto> h) {
        try {
            string name = qwf_get_process_name(h.wfname, h.wfversion, h.name);

            # build command line options
            list<string> cl_opts = self.cl_opts;
            if (h.args) {
                cl_opts += h.args;
            }

            # ensure that cluster program starts and stops happen atomically
            AtomicProcessHelper aph(name);

            # check if we have such a process already
            if (checkProcess(index, sender, mboxid, name))
                return;

            hash<NodeHostInfo> node_info = getNodeForNewProcess(name);
            ClusterProcessHelper clph(self, node_info.node, QDP_NAME_QWF, h.name, name);

            while (True) {
                try {
                    QwfProcess proc(self, node, gethostname(), False, h.name, h.wfname, h.wfversion, h.stack_size,
                        h.sessionid, convert_logger_params(h.logger_params), cl_opts);

                    if (startProcess(index, sender, mboxid, h.name, proc, clph) && sessionid == "-") {
                        saveSession(h);
                    }

                    break;
                } catch (hash<ExceptionInfo> ex) {
                    if (node_info.node != self.node) {
                        log(LoggerLevel::ERROR, "failed to start process %y in remote node %y: %s; retrying", name,
                            node_info.node, get_exception_string(ex));
                        hash<NodeHostInfo> new_node_info = getNodeForNewProcess(name);
                        if (new_node_info != node_info) {
                            clph.updateNode(new_node_info);
                            node_info = new_node_info;
                        }
                        continue;
                    }
                    rethrow;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error starting workflow process (%y): %s", h, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    processAborted(string id, hash<ProcessTerminationInfo> info) {
        QDBG_LOG("QorusMaster::processAborted() active: %y id: %y restart: %y", active, id, info.restart);
        if (active) {
            # we cannot restart passive master processes
            if (info.restart) {
                if (info.proc instanceof QorusPassiveMasterProcess) {
                    info.restart = False;
                } else if (info.proc instanceof QorusCoreProcess && opts.independent) {
                    info.restart = False;
                }
            }
            AbstractQorusProcessManager::processAborted(id, info);
        } else {
            log(LoggerLevel::INFO, "cluster process %y on %s PID %d terminated prematurely; notifying active master",
                id, info.proc.getNode(), info.proc.getPid(), info.restart ? "" : "not ");
            # after this call the Process object is not available
            info.proc.processAborted();
        }
    }

    string getActiveMasterUrlsString() {
        if (!active) {
            # return the URL string for the active master
            return active_master.getUrls().join(",");
        } else {
            return master_urls.join(",");
        }
    }

    private saveSession(hash<auto> h) {
        sessionid = h.sessionid.toString();
        log(LoggerLevel::INFO, "marking sessionid %d to be continued when restarting qorus-core", sessionid);
    }

    #! starts a process in a remote node
    int startRemoteProcess(AbstractQorusProcess proc) {
        QorusPassiveMasterProcess pm = passive_master_node_map{proc.getNode()};
        hash<auto> args = {
            "class_name": proc.className(),
            "args": proc.getConstructorArgs(),
        };
        return qorus_cluster_deserialize(pm.getClient().sendCheckResponseUnreliable(CPC_MR_START_REMOTE_PROC, args,
            CPC_OK)[0]).pid;
    }

    #! called in the passive from the active to start a remote process
    startRemoteProcessFromActive(int index, string sender, string mboxid, hash<auto> req) {
        QDBG_ASSERT(!active);
        try {
            QDBG_LOG("start process in passive: sender: %y mboxid: %y req: %y", sender, mboxid, req);
            list<auto> args = (self, node, gethostname());
            if (req.args) {
                args += req.args;
            }
            AbstractQorusProcess proc = create_object_args(req.class_name, args);
            addPassiveProcess(proc);
            sendAnyResponse(index, sender, mboxid, CPC_OK, {"pid": proc.getPid()});
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error starting process in passive master: %s", get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    #! called in the passive from the active to stop a remote process
    stopRemoteProcessFromActive(int index, string sender, string mboxid, hash<auto> req) {
        QDBG_ASSERT(!active);
        try {
            QDBG_LOG("stop process in passive: sender: %y mboxid: %y req: %y", sender, mboxid, req);
            # check if we should stop ourselves
            if (req.id == master_network_id) {
                sendAnyResponse(index, sender, mboxid, CPC_ACK);
                if (!opts.independent) {
                    stopServer();
                }
                return;
            }
            # setup URLs for process
            if (req.urls) {
                m.lock();
                on_exit m.unlock();

                *AbstractQorusProcess proc = ph{req.id};
                if (!proc) {
                    throw "PROCESS-STOP-ERROR", sprintf("cannot stop unknown process %y; known processes: %y, %y",
                        req.id, keys ph, keys tph);
                }
                proc.setUrls(req.urls);
            }
            bool result = stopProcess(req.id);
            log(LoggerLevel::INFO, "active master requested to stop process %y: %s", req.id,
                result ? "stopped" : "failed");
            sendAnyResponse(index, sender, mboxid, CPC_ACK);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error stopping process in passive master: %s", get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    # starts a service cluster process
    startServiceProcess(int index, string sender, string mboxid, hash<auto> h) {
        try {
            string name = qsvc_get_process_name(h.svctype, h.svcname, h.svcversion, h.name);

            # build command line options
            list<string> cl_opts = self.cl_opts;
            if (h.args) {
                cl_opts += h.args;
            }

            # ensure that cluster program starts and stops happen atomically
            AtomicProcessHelper aph(name);

            # check if we have such a process already
            if (checkProcess(index, sender, mboxid, name))
                return;

            hash<NodeHostInfo> node_info = getNodeForNewProcess(name);
            ClusterProcessHelper clph(self, node_info.node, QDP_NAME_QSVC, h.name, name, True);

            while (True) {
                try {
                    QsvcProcess proc(self, node, gethostname(), False, h.name, h.svctype, h.svcname, h.svcversion,
                        h.stack_size, convert_logger_params(h.logger_params), cl_opts);
                    startProcess(index, sender, mboxid, h.name, proc, clph);
                    break;
                } catch (hash<ExceptionInfo> ex) {
                    if (node_info.node != self.node) {
                        log(LoggerLevel::ERROR, "failed to start process %y in remote node %y: %s; retrying", name,
                            node_info.node, get_exception_string(ex));
                        hash<NodeHostInfo> new_node_info = getNodeForNewProcess(name);
                        if (new_node_info != node_info) {
                            clph.updateNode(new_node_info);
                            node_info = new_node_info;
                        }
                        continue;
                    }
                    rethrow;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error starting service process (%y): %s", h, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    # starts a job cluster process
    startJobProcess(int index, string sender, string mboxid, hash<auto> h) {
        try {
            string name = qjob_get_process_name(h.jobname, h.jobversion, h.name);

            # build command line options
            list<string> cl_opts = self.cl_opts;
            if (h.args) {
                cl_opts += h.args;
            }

            # ensure that cluster program starts and stops happen atomically
            AtomicProcessHelper aph(name);

            # check if we have such a process already
            if (checkProcess(index, sender, mboxid, name)) {
                return;
            }

            hash<NodeHostInfo> node_info = getNodeForNewProcess(name);
            ClusterProcessHelper clph(self, node_info.node, QDP_NAME_QJOB, h.name, name, True);

            while (True) {
                try {
                    QjobProcess proc(self, node, gethostname(), False, h.name, h.jobname, h.jobversion, h.stack_size,
                        h.sessionid, convert_logger_params(h.logger_params), cl_opts);
                    startProcess(index, sender, mboxid, h.name, proc, clph);
                    break;
                } catch (hash<ExceptionInfo> ex) {
                    if (node_info.node != self.node) {
                        log(LoggerLevel::ERROR, "failed to start process %y in remote node %y: %s; retrying", name,
                            node_info.node, get_exception_string(ex));
                        hash<NodeHostInfo> new_node_info = getNodeForNewProcess(name);
                        if (new_node_info != node_info) {
                            clph.updateNode(new_node_info);
                            node_info = new_node_info;
                        }
                        continue;
                    }
                    rethrow;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error starting job process (%y): %s", h, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    #! starts grafana (3rd-party process)
    bool startGrafanaProcess(int prometheus_port) {
        # FIXME: grafana can only be started on the same node as qorus-core until it's updated to use TCP sockets
        #hash<NodeHostInfo> node_info = getNodeForNewProcess(QDP_NAME_GRAFANA);
        ClusterProcessHelper clph(self, node, QDP_NAME_GRAFANA, "-", QDP_NAME_GRAFANA);

        while (True) {
            try {
                GrafanaProcess proc(self, node, gethostname(), prometheus_port, NOTHING, getLoggerParams("grafana"));
                if (!clph.start()) {
                    # process already exists
                    hash<auto> row = clph.getRow();
                    proc.setDetached(clph.getRow());
                }

                if (addProcess(proc)) {
                    clph.updateProcess(proc);
                    logStartup(" + %s: [%y] started", QDP_NAME_GRAFANA, proc.getNetworkDescription());
                    return True;
                }
                break;
            } catch (hash<ExceptionInfo> ex) {
                if (node != self.node) {
                    log(LoggerLevel::ERROR, "failed to start process %y in remote node %y: %s; retrying",
                        QDP_NAME_GRAFANA, node, get_exception_string(ex));
                    #hash<NodeHashInfo> new_node_info = getNodeForNewProcess(QDP_NAME_GRAFANA);
                    #if (new_node_info != node_info) {
                    #    clph.updateNode(new_node_info);
                    #    node_info = new_node_info;
                    #}
                    continue;
                }
                rethrow;
            }
        }

        # we have failed to update the process
        clph.del();
        return False;
    }

    #! starts prometheus (3rd-party process)
    bool startPrometheusProcess(reference<int> started_port) {
        hash<NodeHostInfo> node_info = getNodeForNewProcess(QDP_NAME_PROMETHEUS);
        ClusterProcessHelper clph(self, node_info.node, QDP_NAME_PROMETHEUS, "-", QDP_NAME_PROMETHEUS);

        while (True) {
            try {
                PrometheusProcess proc(self, node_info.node, node_info.host, NOTHING, getLoggerParams("prometheus"));
                if (!clph.start()) {
                    # process already exists
                    hash<auto> row = clph.getRow();
                    proc.setDetached(clph.getRow());
                }

                if (addProcess(proc)) {
                    clph.updateProcess(proc);
                    logStartup(" + %s: [%y] started", QDP_NAME_PROMETHEUS, proc.getNetworkDescription());
                    started_port = proc.getPort();
                    return True;
                }
                break;
            } catch (hash<ExceptionInfo> ex) {
                if (node_info.node != self.node) {
                    log(LoggerLevel::ERROR, "failed to start process %y in remote node %y: %s; retrying",
                        QDP_NAME_PROMETHEUS, node_info.node, get_exception_string(ex));
                    hash<NodeHostInfo> new_node_info = getNodeForNewProcess(QDP_NAME_PROMETHEUS);
                    if (new_node_info != node_info) {
                        clph.updateNode(new_node_info);
                        node_info = new_node_info;
                    }
                    continue;
                }
                rethrow;
            }
        }

        # we have failed to update the process
        clph.del();
        return False;
    }

    # starts a qorus-core cluster process
    bool startQorusCoreProcess() {
        QDBG_ASSERT(!opts.independent);
        # build command line options starting with Qorus system options given on the command line
        list<string> cl_opts = options.getCommandLineOptions();
        cl_opts += self.cl_opts;

        # ensure that cluster program starts and stops happen atomically
        AtomicProcessHelper aph(QDP_NAME_QORUS_CORE);

        # FIXME: qorus-core can only be started on the same node as grafana until grafana is updated to use TCP sockets
        hash<NodeHostInfo> node_info;
        if (options.get("unsupported-enable-tsdb")) {
            node_info = getNodeHostInfo(node);
        } else {
            node_info = getNodeForNewProcess(QDP_NAME_QORUS_CORE);
        }

        ClusterProcessHelper clph(self, node_info.node, QDP_NAME_QORUS_CORE, "-", QDP_NAME_QORUS_CORE);

        while (True) {
            try {
                QorusCoreProcess proc(self, node_info.node, node_info.host, False, sessionid, running_wfid_list,
                    running_svcid_list, running_jobid_list, qdsp_recovery_map, cl_opts);

                if (!clph.start()) {
                    # process already exists
                    proc.setDetached(clph.getRow());
                }

                if (addProcess(proc)) {
                    clph.updateProcess(proc);
                    logStartup(" + qorus-core: %y %s", proc.getUrls(), clph.start() ? "started" : "recovered");
                    return True;
                }
                break;
            } catch (hash<ExceptionInfo> ex) {
                if (node_info.node != self.node) {
                    log(LoggerLevel::ERROR, "failed to start process %y in remote node %y: %s; retrying",
                        QDP_NAME_QORUS_CORE, node_info.node, get_exception_string(ex));
                    hash<NodeHostInfo> new_node_info = getNodeForNewProcess(QDP_NAME_QORUS_CORE);
                    if (new_node_info != node_info) {
                        clph.updateNode(new_node_info);
                        node_info = new_node_info;
                    }
                    continue;
                }
                rethrow;
            }
        }

        # we have failed to update the process
        clph.del();
        return False;
    }

    #! called when the prometheus process is restarted, but cannot be restarted on the same port
    prometheusPortChange(int port) {
        m.lock();
        on_exit m.unlock();

        if (grafana) {
            # appropriate logging is made in the GrafanaProcess call
            grafana.prometheusPortChange(port);
        } else {
            log(LoggerLevel::INFO, "prometheus port updated to %d: grafana process not running", port);
        }
    }

    detachProcessExtern(int index, string sender, string mboxid, hash<auto> h) {
        try {
            *AbstractQorusProcess proc;
            {
                # ensure that cluster program starts and stops happen atomically
                AtomicProcessHelper aph(h.name);

                # detach process and send confirmation to caller
                proc = detachProcess(h.name);
                sendResponse(index, sender, mboxid, CPC_OK, {"detached": (proc ? True : False)});
            }
            # issue #3663: we have to make sure and wait() on processes, so they don't become zombies
            if (proc) {
                QDBG_LOG("waiting for detached process %y to terminate", proc.getId());
                proc.wait();
                QDBG_LOG("detached process %y terminated", proc.getId());
            }
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error detaching process (%y): %s", h, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    detachKillProcessExtern(int index, string sender, string mboxid, hash<auto> h) {
        try {
            # ensure that cluster program starts and stops happen atomically
            AtomicProcessHelper aph(h.name);

            # detach process and send confirmation to caller
            bool detached = detachKillProcess(h.name);
            sendResponse(index, sender, mboxid, CPC_OK, {"detached": detached});
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error detaching and killing process (%y): %s", h, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    stopProcessExtern(int index, string sender, string mboxid, hash<auto> h) {
        try {
            # ensure that cluster program starts and stops happen atomically
            AtomicProcessHelper aph(h.name);

            # stop process and send confirmation to caller
            if (stopProcess(h.name)) {
                sendResponse(index, sender, mboxid, CPC_ACK);
                return;
            }
            throw "NO-PROCESS", sprintf("%y: process is not a known process; known processes: %y", h.name,
                getProcessIds());
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error stopping process (%y): %s", h, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    stopProcessInPassiveMaster(AbstractQorusProcess proc) {
        try {
            *QorusPassiveMasterProcess pm = passive_master_node_map{proc.getNode()};
            if (!pm) {
                # in case of a race condition where the process has already been deleted, log it and ignore
                log(LoggerLevel::WARN, "process %y has already been removed from node %y; assuming dead",
                    proc.getId(), proc.getNode());
                return;
            }
            hash<auto> args = {
                "id": proc.getId(),
                "urls": proc.getUrls(),
            };
            pm.getClient().sendCheckResponseUnreliable(CPC_MR_STOP_REMOTE_PROC, args, CPC_ACK);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "exception stopping process %y on node %y; assuming process dead: %s", proc.getId(),
                proc.getNode(), get_exception_string(ex));
        }
    }

    ignoreProcessAbort(int index, string sender, string mboxid, hash<auto> h) {
        {
            # ensure that cluster program starts and stops happen atomically
            AtomicProcessHelper aph(h.name);

            ignoreProcessAbortIntern(h);
        }
        sendResponse(index, sender, mboxid, CPC_ACK);
    }

    setProcessIndependence(int index, string sender, string mboxid, hash<auto> h) {
        try {
            # ensure that cluster program starts and stops happen atomically
            AtomicProcessHelper aph(h.name);

            bool gone;
            {
                m.lock();
                on_exit m.unlock();
                # if the process disappeared, then no update can be done
                if (!ph{h.name} && !tph{h.name}) {
                    gone = True;
                } else {
                    # issue #3371: in case of a qorus-core recovery, this might be called on a process already
                    # runmning independently
                    if (dependent_process_hash{h.name}) {
                        QDBG_ASSERT(ignore_abort_hash{h.name});
                        remove ignore_abort_hash{h.name};
                        remove dependent_process_hash{h.name};
%ifdef QorusDebugInternals
                    } else {
                        QDBG_ASSERT(!ignore_abort_hash{h.name});
%endif
                    }
                }
            }

            if (!gone) {
                # update dependent flag in DB
                QorusRestartableTransaction trans(cluster_processes.getDriverName());
                while (True) {
                    try {
                        on_error cluster_processes.rollback();
                        on_success cluster_processes.commit();
                        # if the insert fails due to a PK error, an exception will be thrown
                        cluster_processes.update({"dependent": 0}, {"process_network_id": h.name});
                    } catch (hash<ExceptionInfo> ex) {
                        if (*string msg = trans.restartTransaction(ex)) {
                            log(LoggerLevel::WARN, "%s", msg);
                            continue;
                        }
                        rethrow;
                    }
                    break;
                }
            }

            sendResponse(index, sender, mboxid, CPC_ACK);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error setting process independence (%y): %s", h, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    updateProcessInfo(int index, string sender, string mboxid, hash<auto> h) {
        # ensure that cluster program starts and stops and info updates happen atomically
        AtomicProcessHelper aph(h.name);

        try {
            updateProcessInfo(h.name, h.info);
            # now update in the DB
            QorusRestartableTransaction trans(cluster_processes.getDriverName());
            while (True) {
                try {
                    on_error cluster_processes.rollback();
                    on_success cluster_processes.commit();

                    # if the insert fails due to a PK error, an exception will be thrown
                    cluster_processes.update({"info": make_yaml(h.info)}, {"process_network_id": h.name});
                } catch (hash<ExceptionInfo> ex) {
                    if (*string msg = trans.restartTransaction(ex)) {
                        log(LoggerLevel::WARN, "%s", msg);
                        continue;
                    }
                    rethrow;
                }
                break;
            }
            log(LoggerLevel::INFO, "updated process info for process %y", h.name);
            sendResponse(index, sender, mboxid, CPC_ACK);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "failed to update process info (%y): %s", h, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    # called with the main Mutex held
    private checkProcessMemoryIntern(int mpmp, reference<hash<string, hash<ProcessTerminationInfo>>> aborted_hash) {
        # check process size
        foreach AbstractQorusProcess p in (ph.iterator()) {
            hash<MemorySummaryInfo> pi = p.getProcessMemoryInfo();
            int pct = (pi.priv * 100.0 / float(machine_ram_total)).toInt();
            #log(LoggerLevel::INFO, "process %s: %s (private memory) %d%% RAM", p.getName(), get_byte_size(pi.vsz),
            #    pct);
            # get process ID
            string id = p.getId();
            if (pct > mpmp) {
                if (critical_process_map{id}) {
                    log(LoggerLevel::WARN, "WARNING: critical process %s %y PID %d: %s -> %d%% RAM exceeds limit of "
                        "%d%%", p.getName(), id, p.getPid(), get_byte_size(pi.priv), pct, mpmp);
                } else if (shutdown_flag) {
                    log(LoggerLevel::WARN, "WARNING: process %s %y PID %d: %s -> %d%% RAM exceeds limit of %d%%; not "
                        "terminating due to pending shutdown", p.getName(), id, p.getPid(), get_byte_size(pi.priv),
                        pct, mpmp);
                } else {
                    log(LoggerLevel::ERROR, "process %s %y PID %d: %s -> %d%% RAM exceeds limit of %d%%; restarting "
                        "process", p.getName(), id, p.getPid(), get_byte_size(pi.priv), pct, mpmp);
                    restart(p);
                    aborted_hash{id} = <ProcessTerminationInfo>{
                        "proc": remove ph{id},
                        "restart": !(remove ignore_abort_hash{id}),
                    };
                    remove dependent_process_hash{id};
                    processRemovedIntern(aborted_hash{id}.proc);
                }
            } else if (pi.priv && process_memory_info_hash{id}.priv != pi.priv) {
                checkProcessMemoryIntern(id, pi, pct, p.getInfo());
            }
        }

        # check the current master process
        hash<MemorySummaryInfo> pi = Process::getMemorySummaryInfo();
        QDBG_LOG("QorusMaster::checkProcessMemoryIntern() pi: %y PMI{%y}: %y", pi, master_network_id,
            process_memory_info_hash{master_network_id});
        if (pi.priv && process_memory_info_hash{master_network_id}.priv != pi.priv) {
            int pct = (pi.priv * 100.0 / float(machine_ram_total)).toInt();
            checkProcessMemoryIntern(master_network_id, pi, pct, getProcessInfoHash(pi));
        }
    }

    #! returns a process info hash for the current process
    private hash<auto> getProcessInfoHash(hash<MemorySummaryInfo> mh = Process::getMemorySummaryInfo()) {
        return {
            "id": master_network_id,
            "node": node,
            "status": CS_RUNNING,
            "status_string": CS_StatusMap{CS_RUNNING},
            "urls": master_urls,
            "host": gethostname(),
            "pid": getpid(),
            "type": QDP_NAME_QORUS_MASTER,
            "client_id": node,
            "started": starttime,
        } + mh + {"priv_str": mh ? get_byte_size(mh.priv) : "n/a"};
    }

    private checkProcessMemoryIntern(string id, hash<MemorySummaryInfo> pi, int pct, hash<auto> info) {
        QDBG_ASSERT(pi.priv && process_memory_info_hash{id}.priv != pi.priv);
        # only send a memory changed event when the private memory amount changes
        #QDBG_LOG("total_private_memory: %d -> %d (%s: old: %d new: %d diff: %d) MON", total_private_memory,
        #    total_private_memory + (pi.priv - process_memory_info_hash{id}.priv), id,
        #    process_memory_info_hash{id}.priv, pi.priv, pi.priv - process_memory_info_hash{id}.priv);
        QDBG_LOG("AbstractQorusProcessManager::checkProcessMemoryIntern() machine_ram_in_use: %y", machine_ram_in_use);
        total_private_memory += pi.priv - process_memory_info_hash{id}.priv;
        process_memory_info_hash{id} = pi + {"pct": pct};
        processMemoryUpdated(id, info + process_memory_info_hash{id} + {
            "node_priv": total_private_memory,
            "node_priv_str": get_byte_size(total_private_memory),
            "node_ram": machine_ram_total,
            "node_ram_str": get_byte_size(machine_ram_total),
            "node_ram_in_use": machine_ram_in_use,
            "node_ram_in_use_str": get_byte_size(machine_ram_in_use),
            "node_cpu_count": machine_cpus,
            "node_load_pct": machine_load_pct,
        });
    }

    # called in the process lock when a process is started and added to the process map; reimplement in subclasses to add to process-specific type maps
    private processStartedInternImpl(AbstractQorusProcess proc, int start_code) {
        if (active) {
            if (proc instanceof QorusCoreProcess) {
                QDBG_ASSERT(!qorus_core);
                qorus_core = cast<QorusCoreProcess>(proc);
            } else if (proc instanceof PrometheusProcess) {
                QDBG_ASSERT(!prometheus);
                prometheus = cast<PrometheusProcess>(proc);
            } else if (proc instanceof GrafanaProcess) {
                QDBG_ASSERT(!grafana);
                grafana = cast<GrafanaProcess>(proc);
            } else if (proc instanceof QwfProcess) {
%ifdef QorusDebugInternals
                # DBG
                if (wph{proc.getId()}) {
                    QDBG_LOG("ERROR: proc id %y already present: wph: %y pid %y?", proc.getId(), keys wph, proc.getPid());
                }
                QDBG_ASSERT(!wph{proc.getId()});
%endif
                wph{proc.getId()} = proc;
            } else if (proc instanceof QdspProcess) {
                QDBG_ASSERT(!qdsp_map{proc.getId()});
                qdsp_map{proc.getId()} = proc;
            }
        }
    }

    # called outside the process lock when a process is started and added to the process map
    private processStartedImpl(AbstractQorusProcess proc, int start_code) {
        # publish process start event after row written to DB (if applicable)
        on_exit
            publishEvent(CPC_MR_PUB_PROCESS_STARTED, proc.getInfo() + {"start_code": start_code});

        # issue #3506: do process notification for restarted processes
        doRestartNotifications(proc);

        if (start_code != PSC_AUTO_RESTART)
            return;

        hash<auto> row = proc.getClusterProcessesRow();

        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                on_error cluster_processes.rollback();
                on_success cluster_processes.commit();

                # if the insert fails due to a PK error, an exception will be thrown
                cluster_processes.insert(row);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    #! do restart notifications for processes that die in recovery
    private doRestartNotifications(AbstractQorusProcess proc) {
        QDBG_LOG("doRestartNotifications(%y) QRM: %y", proc.getId(), qdsp_recovery_map);
        bool notify;
        string client_id = proc.getClientId();
        {
            m.lock();
            on_exit m.unlock();

            notify = exists (remove qdsp_recovery_map{client_id});
        }

        if (notify) {
            QDBG_LOG("doRestartNotifications(%y) QRN: notifying restart", proc.getId());

            date abort_timestamp = now_us();
            string id = proc.getId();
            *hash<string, hash<ProcessNotificationInfo>> proc_map = notifyAbortedProcessAllInitial(id, NOTHING, abort_timestamp);
            notifyAbortedProcessAll(proc_map, id, proc.getClusterProcInfo(), True, abort_timestamp);
        }
    }

    # called in the process lock when a process is removed from the process list; reimplement in subclasses to remove from process type lists
    private processRemovedInternImpl(*AbstractQorusProcess proc, *bool aborted_externally) {
        if (proc instanceof QorusCoreProcess) {
            if (qorus_core) {
                remove qorus_core;
            }
        } else if (proc instanceof PrometheusProcess) {
            if (prometheus) {
                remove prometheus;
            }
        } else if (proc instanceof GrafanaProcess) {
            if (grafana) {
                remove grafana;
            }
        } else if (proc instanceof QwfProcess) {
            if (wph{string id = proc.getId()}) {
                remove wph{id};
            }
        } else if (proc instanceof QdspProcess) {
            if (qdsp_map{string id = proc.getId()}) {
                remove qdsp_map{id};
            }
        } else if (proc instanceof QorusPassiveMasterProcess) {
            if (passive_master_id_map{string id = proc.getId()}) {
                remove passive_master_id_map{id};
            }
        }
    }

    # called outside the process lock when a process is removed from the process list
    private handleAbortedProcesses(hash<string, hash<ProcessTerminationInfo>> aborted_hash) {
        if (active) {
            AbstractQorusProcessManager::handleAbortedProcesses(aborted_hash);
        } else {
            # unconditionally notify local clients the process has died
            map detachProcessIntern($1, NOTHING, False, now_us()), keys aborted_hash;
            # notify active master of aborted process
            handleAbortedProcessesIntern(aborted_hash);
        }
    }

    # called outside the process lock when a process is removed from the process list
    private handleAbortedProcessesIntern(hash<string, hash<ProcessTerminationInfo>> aborted_hash) {
%ifdef QorusDebugInternals
        list<hash<ClusterProcInfo>> l = map $1.proc.getClusterProcInfo(), aborted_hash.iterator();
        active_master.sendCmdOneWay(CPC_MR_REMOTE_PROCESS_ABORTED, {
            "info_list": l,
        });
%else
        active_master.sendCmdOneWay(CPC_MR_REMOTE_PROCESS_ABORTED, {
            "info_list": map $1.proc.getClusterProcInfo(), aborted_hash.iterator(),
        });
%endif
    }

    # called outside the process lock when a process is removed from the process list
    private processRemovedImpl(AbstractQorusProcess proc) {
        if (!active) {
            return;
        }

        #QDBG_LOG("processRemovedImpl() %y: %N", proc.getId(), get_stack());

        # publish process stop event after DB updated
        on_exit
            publishEvent(CPC_MR_PUB_PROCESS_STOPPED, proc.getInfo());

        # remove process from DB
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                on_error cluster_processes.rollback();
                on_success cluster_processes.commit();

                # in case of a race condition, make sure we only delete our row
                hash<auto> dh = {
                    "process_network_id": proc.getId(),
                    "node": proc.getNode(),
                    "pid": proc.getPid(),
                };

                #QDBG_LOG("processRemovedImpl() dh: %y", dh);
                if (dh.pid == -1) {
                    dh -= "pid";
                }

                int rows = cluster_processes.del(dh);
                QDBG_LOG("deleted process ID row %y: %d", proc.getId(), rows);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    private startMasterHandover() {
        # block process changes before starting new master
        blockProcesses();
        on_exit {
            unblockProcesses();
        }

        log(LoggerLevel::INFO, "launching new master process");
        list<auto> args;
        if (QORE_ARGV.size() > 1)
            args += QORE_ARGV[1..];
        args += "--daemon=" + master_urls[0];

        # ensure that the path to the process is valid
        QORE_ARGV[0] = ENV.OMQ_DIR + DirSep + "bin" + DirSep + "qorus";
        if (!is_executable(QORE_ARGV[0])) {
            string err = sprintf("FATAL ERROR: cannot determine path to qorus binary; %y not valid", QORE_ARGV[0]);
            printf(err + "\n");
            log(LoggerLevel::FATAL, err);
            return;
        }

        map args += "--log-subscribe=" + $1, keys log_subscribed;

        log(LoggerLevel::INFO, "launching %y %y", "qorus", args);
        Process proc;
        try {
            proc = new Process("qorus", args, ENV - "PATH");
        } catch (hash<ExceptionInfo> ex) {
            string err = sprintf("FATAL ERROR: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            printf(err + "\n");
            log(LoggerLevel::FATAL, err);
            return;
        }

        log(LoggerLevel::INFO, "launched new master PID %d for handover", proc.id());
        string new_url;

        date now = now_us();
        while (True) {
            try {
                new_url = handover_queue.get(500ms);
                break;
            } catch (hash<ExceptionInfo> ex) {
                #log(LoggerLevel::DEBUG, "ex: %s", get_exception_string(ex));
                if (ex.err == "QUEUE-TIMEOUT") {
                    # check status of child process
                    if (!proc.running()) {
                        string str = sprintf("failed to launch qorus master for handover; not running; rc: %d", proc.exitCode());

                        # try to log stderr / stdout if any
                        *string estr = proc.readStdout(AbstractQorusInternProcess::DefaultOutputSize);
                        if (estr) {
                            str += sprintf("; stdout: %s", trim(estr));
                        }
                        estr = proc.readStderr(AbstractQorusInternProcess::DefaultOutputSize);
                        if (estr) {
                            str += sprintf("; stderr: %s", trim(estr));
                        }
                        log(LoggerLevel::ERROR, str);
                        proc.terminate();
                        return;
                    }

                    if ((now_us() - now) > 20s) {
                        string err = sprintf("FATAL ERROR: master handover timed out; aborting");
                        printf(err + "\n");
                        log(LoggerLevel::FATAL, err);
                        proc.terminate();
                        return;
                    }

                    continue;
                }

                string err = sprintf("FATAL ERROR: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                printf(err + "\n");
                log(LoggerLevel::FATAL, err);
                return;
            }
        }
        log(LoggerLevel::INFO, "got new master URL %y", new_url);
        # ensure that errors are logged to enable debugging
        try {
            # stop master and I/O threads to ensure that no more messages are processed
            stopEventThread();
            # detach new master
            proc.detach();
            # detach all child processes; now owned by new master
            detachAll();
            has_master_row = False;
            log(LoggerLevel::DEBUG, "stopping cluster");
            try {
                stopCluster();
            } catch (hash<ExceptionInfo> ex) {
                log(LoggerLevel::ERROR, "%s", get_exception_string(ex));
            }
            log(LoggerLevel::DEBUG, "exiting process");
            logStartup("Qorus cluster services started; running qorus master PID %d in the background", proc.id());
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "SHUTDOWN EXCEPTION: %s", get_exception_string(ex));
        }
        exit(0);
    }

    private:internal detachAll() {
        # no locking needed; processes are blocked/frozen
        map $1.detach(), ph.iterator();
        # issue #3346: remove process object before removing clients
        if (qorus_core) {
            qorus_core.removeProcess();
            remove qorus_core;
        }
        remove prometheus;
        remove grafana;
        delete ph;
        delete wph;
        delete qdsp_map;
        delete passive_master_id_map;
        delete passive_master_node_map;
    }

    hash<auto> getInfo() {
        # master process info hash; start with an entry about the "qorus-master" process (i.e. this process)
        hash<MemorySummaryInfo> mh = Process::getMemorySummaryInfo();
        hash<auto> mph = {
            master_network_id: getProcessInfoHash(mh),
        };
        # node memory hash; initialize with private memory for this master process
        hash<auto> nmh{node}.node_priv = mh.priv;
        m.lock();
        on_exit m.unlock();

        foreach hash<auto> h in (ph.pairIterator()) {
            hash<auto> ih = h.value.getInfo();
            mph{h.key} = ih;
            nmh{ih.node}.node_priv += ih.priv;
        }

        # get memory history in reverse order
        date now = now_us();
        foreach hash<auto> i in (nmh.pairIterator()) {
            *hash<auto> machine_info;
            if (i.key == node) {
                machine_info = {
                    "node_priv": i.value.node_priv,
                    "machine_ram_total": machine_ram_total,
                    "node_ram_in_use": machine_ram_in_use,
                    "machine_cpus": machine_cpus,
                    "machine_load_pct": machine_load_pct,
                    "node_cpu_count": node_memory_info.node_cpu_count,
                };
            } else {
                machine_info = remote_node_memory_info{i.key};
            }

            int proc_count = node_process_map{i.key}.size();
            # add one for the current process on the current node
            if (i.key == node) {
                ++proc_count;
            }

            nmh{i.key} = i.value + {
                "node_priv": machine_info.node_priv,
                "node_priv_str": get_byte_size(machine_info.node_priv ?? 0),
                "node_ram": machine_info.machine_ram_total,
                "node_ram_str": get_byte_size(machine_info.machine_ram_total ?? 0),
                "node_ram_in_use": machine_info.node_ram_in_use ?? 0,
                "node_ram_in_use_str": get_byte_size(machine_info.node_ram_in_use ?? 0),
                "node_cpu_count": machine_info.node_cpu_count,
                "node_load_pct": machine_info.machine_load_pct,
                "mem_history": (map $1, new ListReverseIterator(mem_history{i.key} ?? ())),
                "process_count": proc_count,
                "process_history": (map $1, new ListReverseIterator(proc_history{i.key} ?? ())),
            };
        }

        return {
            "name": master_network_id,
            "id": node,
            "urls": master_urls,
            "pub_url": getPubUrl(),
            "started": started,
            "threads": num_threads(),
            "loglevel": logger.getLevel().getValue(),
            "cluster_info": nmh,
            "processes": mph,
            "modules": get_module_hash(),
            "props": runtimeProp,
        } + mh + {"priv_str": mh ? get_byte_size(mh.priv) : "n/a"};
    }

    stopServer() {
        QDBG_ASSERT(!opts.independent);
        startShutdownCluster();
    }

    private static usage() {
        stderr.printf("usage: qorus [option=value]
 -B,--show-build        show build information
 -D,--define=ARG        sets a runtime property
 -d,--qorus-dir=ARG     sets the application directory (overrides OMQ_DIR)
 -h,--help              this help text
 -I,--independent       wait for qorus-master to be started and register independently
 -l,--option-list       shows a list of valid options and exit
 -L,--log-level=ARG     set log level for system loggers
 -V,--version           show version information and exit
    --debug-system      turns on system debugging
    --daemon=ARG        signifies a handover; ARG=old master URL
    --startup=ARG       send startup messages to the given REP socket
"
# -P,--pid-file=ARG      create a file with the current PID for the current
#                        instance in the given directory; the file name will be
#                        qorus-<instance-name>; the file will be deleted when
#                        the server exits
        );
        thread_exit;
    }

    private hash<auto> processCommandLine() {
        GetOpt g(QorusOpts);
        hash<auto> o;

        try {
            o = g.parse2(\ARGV);
            # handle -D values
            foreach string i in (o.sysprop) {
                list l = split("=", i);
                if (elements l != 2)
                    throw "PARSE-SYSPROP-ERROR", sprintf("runtime properties must have a -Dkey=value format. Got: -D%s", i);
                runtimeProp{l[0]} = l[1];
                #printf("runtime property %s=%s\n", l[0], l[1]);
            }
        } catch (hash<ExceptionInfo> ex) {
            stderr.printf("%s\n", ex.desc);
            exit(QSE_COMMAND_LINE_ERROR);
        }

        if (o.help)
            usage();

        if (o.list) {
            foreach hash<auto> h in (omq_option_hash.pairIterator()) {
                printf("%s:\n", h.key);
                foreach string a in ("desc", "expects", "default", "startup-only") {
                    auto v = h.value{a};
                    if (!exists v)
                        continue;
                    printf("  %s: %s\n", a, v.typeCode() == NT_STRING ? v : sprintf("%y", v));
                }
            }
            exit(1);
        }

        if (o.version) {
            # banners have already been printed; just exit here
%ifdef QorusDebugInternals
            thread_exit;
%else
            exit(QSE_VERSION_ONLY);
%endif
        }

        if (o.build) {
            printf("%s@%s on %s\n", QorusBuildUser, QorusBuildHost, QorusBuildTime.format("YYYY-MM-DD HH:mm:SS"));
%ifdef QorusDebugInternals
            thread_exit;
%else
            exit(QSE_VERSION_ONLY);
%endif
        }

        if (o.dir) {
            ENV.OMQ_DIR = o.dir;
            cl_opts += sprintf("--qorus-dir=%s", o.dir);
        }

        int errors = (foldl $1 + $2, (map setSystemOption($1), ARGV)) ?? 0;

        if (errors) {
            stderr.printf("; please correct the error%s above and try again (-h or --help for usage)\n", errors == 1 ? "" : "s");
            exit(QSE_OPTION_ERROR);
        }

        return o;
    }

    private updateSystemLogLevel(int logLevel) {
        if (!AVAILABLE_LEVELS{logLevel}) {
            printf("WARNING: Unknown logger level, received %d, available levels: %y", logLevel, AVAILABLE_LEVELS);
        }

        #TODO update all logger levels
        *hash<auto> loggerInfo = getLoggerInfo("qorus-master");
        if (!loggerInfo) {
            return;
        }

        loggerInfo{"params"}{"level"} = logLevel;

        AbstractTable loggersTable = getTable("loggers");
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                on_success cluster_processes.commit();
                on_error cluster_processes.rollback();

                int rowsUpdated = loggersTable.update({"params": make_yaml(loggerInfo{"params"})}, {"loggerid": loggerInfo{"loggerid"}});
                if (rowsUpdated == 1) {
                    printf("System logger level successfully updated with value %d\n", logLevel);
                }
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    printf(msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    private updateSystemLogLevel(string logLevel) {
        if (!AVAILABLE_LEVELS_STR{logLevel}) {
            printf("WARNING: Unknown logger level, received %s, available levels: %y", logLevel, AVAILABLE_LEVELS_STR);
        }

        updateSystemLogLevel(AVAILABLE_LEVELS_STR{logLevel});
    }

    *hash<LoggerParams> makeLoggerParams(*hash<auto> input_params, string type, *string name) {
        return QorusMasterCoreQsvcCommon::makeLoggerParams(options.get(), input_params, type, name);
    }

    updateLogger(int index, string sender, string mboxid, *hash<LoggerParams> params) {
        try {
            updateLogger(params);
            sendResponse(index, sender, mboxid, CPC_OK);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error updating logger (%y): %s", params, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    updatePrometheusLogger(int index, string sender, string mboxid, *hash<LoggerParams> params) {
        try {
            {
                m.lock();
                on_exit m.unlock();

                if (prometheus) {
                    prometheus.updateLogger(params);
                }
            }
            sendResponse(index, sender, mboxid, CPC_OK);
        } catch (hash<ExceptionInfo> ex) {
            error("exception updating prometheus logger (%y): %s", params, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    updateGrafanaLogger(int index, string sender, string mboxid, *hash<LoggerParams> params) {
        try {
            {
                m.lock();
                on_exit m.unlock();

                if (grafana) {
                    grafana.updateLogger(params);
                }
            }
            sendResponse(index, sender, mboxid, CPC_OK);
        } catch (hash<ExceptionInfo> ex) {
            error("exception updating grafana logger (%y): %s", params, get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    rotateLogger(int index, string sender, string mboxid) {
        try {
            rotateLogFiles();
            sendResponse(index, sender, mboxid, CPC_OK);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error rotating loggers: %s", get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    rotateQdspLogger(int index, string sender, string mboxid) {
        try {
            map cast<QdspProcess>($1).sendRotateLoggerRequest(), qdsp_map.iterator();
            sendResponse(index, sender, mboxid, CPC_OK);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error rotating qdsp loggers: %s", get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    updateLogger(*hash<LoggerParams> params) {
        logger = createLogger(params);
        log(LoggerLevel::DEBUG, "master logger has been updated with params: %y", params);

        if (opts.daemon || opts.startup) {
            # redirect stderr & stdout if running in the background
            redirectStdEO();
        }
    }

    rotateLogFiles() {
        foreach auto appender in (logger.getAppenders()) {
            if (appender instanceof AbstractLoggerAppenderFileRotate) {
                cast<AbstractLoggerAppenderFileRotate>(appender).rotate();
            }
        }
    }

    private redirectStdEO() {
        # redirect stdout & stderr to the logger appenders
        foreach auto appender in (logger.getAppenders()) {
            if (appender instanceof LoggerAppenderFile) {
                File file = appender.getFile();
                stderr.redirect(file);
                stdout.redirect(file);
                break;
            }
        }
    }

    int setSystemOption(string v) {
        string opt;
        auto val;

        if ((int i = v.find("=")) != -1) {
            opt = substr(v, 0, i);
            val = substr(v, i + 1);
        } else {
            opt = v;
            val = True;
        }

        *hash<auto> oh = omq_option_hash{opt};

        if (!oh) {
            stderr.printf("ERROR: unknown Qorus system option %y", opt);
            return 1;
        }

        try {
            list<auto> errs = options.set({opt: val});
            if (!elements errs)
                return 0;

            map stderr.print($1 + "\n"), errs;
        } catch (hash<ExceptionInfo> ex) {
            stderr.printf("%s: %s\n", ex.err, ex.desc);
        }
        return 1;
    }

    logStartup(string fmt) {
        string msg = vsprintf(fmt, argv);
        if (!opts.daemon && !opts.startup) {
            stdout.print(msg + "\n");
        }

        log(LoggerLevel::INFO, "%s", msg);
    }

    broadcastToAllInterfaces(data msgdata, string except) {
        try {
            m.lock();
            on_exit m.unlock();

            map $1.broadcastSubsystemOneWay(msgdata), ph.iterator(),
                $1 instanceof AbstractQorusInterfaceProcess && $1.getId() != except;
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "failed to broadcast message to all interfaces: %s", get_exception_string(ex));
        }
    }

    broadcastToAllInterfacesConfirm(int index, string sender, string mboxid, data msgdata, string except) {
        try {
            {
                m.lock();
                on_exit m.unlock();

                map $1.broadcastSubsystemOneWay(msgdata), ph.iterator(),
                    $1 instanceof AbstractQorusInterfaceProcess && $1.getId() != except;
            }
            # send confirmation to caller
            sendResponse(index, sender, mboxid, CPC_ACK);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "failed to broadcast message with confirmation to all interfaces: %s",
                get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    broadcastToAllInterfacesDirect(data msgdata, string except) {
        try {
            m.lock();
            on_exit m.unlock();

            map $1.broadcastSubsystemOneWayDirect(msgdata), ph.iterator(),
                $1 instanceof AbstractQorusInterfaceProcess && $1.getId() != except;
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "failed to broadcast message to all interfaces: %s", get_exception_string(ex));
        }
    }

    broadcastToAllPassiveMasters(data msgdata, string except) {
        m.lock();
        on_exit m.unlock();

        map $1.broadcastSubsystemOneWay(msgdata), passive_master_id_map.iterator(), $1.getId() != except;
    }

    stopFromQorusCore(MyRouter router, string sender, string mboxid) {
        if (opts.independent) {
            if (canShutdownQorus()) {
                logInfo("%s: STOP received from qorus-core", sender);
                background stopQorusApplication();
            } else {
                logInfo("%s: STOP received from qorus-core: Qorus application shutdown already in progress", sender);
            }
        } else {
            if (startShutdownCluster()) {
                logInfo("%s: STOP received: stopping cluster", sender);
            } else {
                logInfo("%s: STOP received: cluster shutdown in progress", sender);
            }
        }
        router.send(sender, mboxid, CPC_ACK);
    }

    # start cluster processes
    private bool startClusterImpl() {
        pub_thread_cnt.inc();
        background pubThread();

        if (!active) {
            startClusterInfoThread();
        }
        return True;
    }

    #! Processes a STOP message inline
    private doInlineStop(ZSocketRouter sock, string sender, string mboxid) {
        if (opts.independent) {
            sendStopErrorReply(sock, sender, mboxid);
            return;
        } else {
            # cannot stop the server from the I/O thread
            background stopServer();
        }
        sock.send(sender, mboxid, CPC_ACK);
    }

    #! kills a set of processes
    private killProcsIntern(hash<string, AbstractQorusProcess> proc_map) {
        # list of process IDs to remove from the cluster_processes table
        list<string> ids;

        # map of passive nodes with unresponsive masters
        hash<string, bool> node_down_map;

        if (active) {
            shutdownMessageMaster("shutdown: WARNING: failed to stop qorus-core process cleanly");
        }
        string msg = sprintf("shutdown: killing %d process%s", proc_map.size(), proc_map.size() == 1 ? "" : "es");
        shutdownMessageMaster(msg);

        foreach AbstractQorusProcess proc in (proc_map.iterator()) {
            string proc_node = proc.getNode();
            string id = proc.getId();
            if (proc_node == node || node_down_map{proc_node} || !passive_master_node_map{proc_node}) {
                log(LoggerLevel::INFO, "shutdown: terminating proc %y (node %y)", id, proc_node);
                proc.terminate();
                continue;
            }

            QDBG_ASSERT(passive_master_node_map{proc_node});
            # tell passive master to terminate process
            try {
                log(LoggerLevel::INFO, "shutdown: terminating proc %y (node %y) through passive master", id, proc_node);
                passive_master_node_map{proc_node}.getClient().sendCheckResponseUnreliable(CPC_MR_DETACH_KILL_PROCESS,
                    {"name": id}, CPC_OK);
            } catch (hash<ExceptionInfo> ex) {
                log(LoggerLevel::INFO, "shutdown: failed to kill remote process %y; assuming master on node %y died: %s: %s", id,
                    proc_node, ex.err, ex.desc);
                node_down_map{proc_node} = True;
                proc.terminate();
            }
        }

        ids += keys proc_map;

        # remove processes from the cluster_processes table
        if (ids) {
            QorusRestartableTransaction trans(cluster_processes.getDriverName());
            while (True) {
                try {
                    on_error cluster_processes.rollback();
                    on_success cluster_processes.commit();

                    int rows = cluster_processes.del({"process_network_id": op_in(ids)});
                    msg = sprintf("shutdown: cluster_process rows removed for terminated processes: %d", rows);
                    shutdownMessageMaster(msg);
                } catch (hash<ExceptionInfo> ex) {
                    if (*string restart_msg = trans.restartTransaction(ex)) {
                        log(LoggerLevel::ERROR, "%s", restart_msg);
                        continue;
                    }
                }
                break;
            }

            if (active) {
                msg = "WARNING: forced shutdown: the application session will need recovery when the cluster is next restarted";
                shutdownMessageMaster(msg);
            }
        }
    }

    #! Sends an error reply to a STOP message in independent mode
    private sendStopErrorReply(ZSocketRouter sock, string sender, string mboxid) {
        try {
            throw "QORUS-MODE-ERROR", "cannot stop Qorus with API commands when running in independent "
                "(externally-managed) mode; external cluster tools must be used to stop Qorus instead";
        } catch (hash<ExceptionInfo> ex) {
            sock.send(sender, mboxid, CPC_EXCEPTION, qorus_cluster_serialize({"ex": ex}));
            log(LoggerLevel::ERROR, "stop message received from %y ignored in independent mode", sender);
        }
    }

    #! stop qorus-core and all Qorus processes
    private synchronized stopQorusApplication() {
        # first stop qorus-core process
        if (qorus_core) {
            log(LoggerLevel::INFO, "stopping qorus-core");
            # ensure that cluster program starts and stops happen atomically
            AtomicProcessHelper aph(qorus_core.getId());

            # if an error occurs stopping qorus-core, then we have to restart the cluster to shut it down
            if (!stopProcess(qorus_core)) {
                string msg = "failed to stop qorus-core process cleanly; the cluster must be restarted and recovered "
                    "in order to be shut down";
                shutdownMessageMaster(msg);
                throw "SHUTDOWN-ERROR", msg;
            }
        }

        if (!opts.independent) {
            # stop all passive masters
            map stopProcess($1), passive_master_id_map.iterator();
        }

        # stop prometheus and grafana
        if (grafana) {
            shutdownStopExternalProcess(grafana);
        }

        if (prometheus) {
            shutdownStopExternalProcess(prometheus);
        }

        # issue #2302: if an error occurs stopping qorus-core, or if qorus-core was not running and other processes
        #              are, then we have to kill all remaining non-master processes in the cluster
        hash<string, AbstractQorusProcess> proc_map;

        blockProcesses();
        on_exit unblockProcesses();

        {
            m.lock();
            on_exit m.unlock();

            if (ph) {
                # get a list of all processes that are not master processes
                foreach hash<auto> i in (ph.pairIterator()) {
                    if (i.value instanceof QorusPassiveMasterProcess) {
                        continue;
                    }
                    proc_map{i.key} = remove ph{i.key};
                    ignore_abort_hash{i.key} = True;
                }
            }
        }

        if (proc_map) {
            killProcsIntern(proc_map);
        }

        shutdownMessageMaster("qorus has been shut down");

        # remove Qorus shutdown flag
        {
            m.lock();
            on_exit m.unlock();

            shutdown_qorus_flag = False;
        }
    }

    #! Stop heartbeat thread
    private stopHeartbeatThread() {
        {
            heartbeat_mutex.lock();
            on_exit heartbeat_mutex.unlock();
            if (!shutdown_flag) {
                shutdown_flag = True;
            }
            heartbeat_cond.signal();
        }

        if (heartbeat_thread_cnt.getCount()) {
            log(LoggerLevel::INFO, "waiting for heartbeat thread to stop");
        }
        heartbeat_thread_cnt.waitForZero();
    }

    # stop cluster processes; called before the cluster has stopped
    private stopClusterImpl() {
        if (!opts.independent && !opts.daemon && options.get("daemon-mode") && active) {
            log(LoggerLevel::INFO, "exiting parent process for cluster handover");
        } else {
            log(LoggerLevel::INFO, "stopping cluster services");
        }

        if (canShutdownQorus()) {
            stopQorusApplication();
        }

        stopHeartbeatThread();

        # stop all passive masters
        map stopProcess($1), passive_master_id_map.iterator();

        shutdownCompleteMaster();

        if (cluster_info_cnt.getCount()) {
            cluster_info_mutex.lock();
            on_exit cluster_info_mutex.unlock();

            cluster_info_stop = True;
            cluster_info_cond.signal();
        }
        cluster_info_cnt.waitForZero();
    }

    private shutdownStopExternalProcess(AbstractQorusProcess proc) {
        string name = proc.getName();
        string id = proc.getId();
        shutdownMessageMaster(sprintf("stopping %s process", name));
        if (!stopProcess(proc)) {
            string msg = sprintf("failed to stop %s process cleanly", name);
            shutdownMessageMaster(msg);
            proc.terminate();
            stopProcess(proc);
        }
        deleteProcessRowCommit(id);
    }

    publishEvent(string cmd) {
        if (active) {
            pubq.push((cmd,) + (argv ? argv : ()));
        }
    }

    publishEventUnconditional(string cmd) {
        pubq.push((cmd,) + (argv ? argv : ()));
    }

    subscribeToLog(string log) {
        QDBG_LOG("subscribeToLog(%y): %y", log, log_subscribed);
        subscription_mutex.lock();
        on_exit subscription_mutex.unlock();

        if (!log_subscribed{log}) {
            log_subscribed{log} = True;
        }
    }

    unsubscribeFromLog(string log) {
        QDBG_LOG("unsubscribeFromLog(%y): %y", log, log_subscribed);
        subscription_mutex.lock();
        on_exit subscription_mutex.unlock();

        if (log_subscribed{log}) {
            log_subscribed{log} = False;
        }
    }

    logExtern(string name, Logger logger, int lvl, string msg) {
        # runs unlocked for speed
        try {
            if (log_subscribed{name} && qorus_core) {
                QDBG_LOG("logExtern() YES name: %y sub: %y core: %y", name, log_subscribed{name}, exists qorus_core);
                logger.log(lvl, "%s", msg, new LoggerEventParameter(\qorus_core.logEvent(), name,
                    sprintf("%s T%d [%s]: ", now_us().format("YYYY-MM-DD HH:mm:SS.xx"), gettid(),
                    LoggerLevel::getLevel(lvl).getStr()) + msg + "\n"));
            } else {
                QDBG_LOG("logExtern() NO name: %y sub: %y core: %y", name, log_subscribed{name}, exists qorus_core);
                logger.log(lvl, "%s", msg);
            }
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("log exception: %s", get_exception_string(ex));
            logger.log(lvl, "%s", msg);
        }
    }

    string getLocalAddress() {
        return local_addresses ? local_addresses.firstKey() : "localhost";
    }

    private pubThread() {
        on_exit {
            pub_thread_cnt.dec();
            log(LoggerLevel::DEBUG, "stopped publisher thread");
        }

        ZSocketPub sock(zctx, "@tcp://*:*");
        pub_url = qorus_cluster_get_bind(getLocalAddress(), sock.endpoint());
        if (opts.startup) {
            try {
                # report the PUB URL to the parent process
                ZSocketReq psock(zctx);
                psock.setIdentity("qorus");
                nkh.setClient(psock);
                psock.setTimeout(5s);
                psock.connect(opts.startup);
                psock.send(pub_url);
                log(LoggerLevel::DEBUG, "sent pub URL %y to %y", pub_url, opts.startup);
                # wait for confirmation before proceeding
                psock.recvMsg();
            } catch (hash<ExceptionInfo> ex) {
                log(LoggerLevel::ERROR, "error handling publisher confirmation: %s: %s: proceeding anyway",
                    ex.err, ex.desc);
            }
        }
        pub_url_cnt.dec();
        while (True) {
            auto v = pubq.get();
            if (!exists v) {
                break;
            }
            try {
                QDBG_LOG("publishing event: %y", v);
            } catch (hash<ExceptionInfo> ex) {
                # ignore log exceptions; ex: FILE-WRITE-ERROR: failed writing 95 bytes to File: Stale file handle, arg: 116
                if (ex.err != "FILE-WRITE-ERROR") {
                    rethrow;
                }
            }
            v = map $1.typeCode() == NT_STRING ? $1 : qorus_cluster_serialize($1), v;
            call_function_args(\sock.send(), v);
        }
    }

    #! Update the heartbeat in the cluster_processes row
    private heartbeatThread() {
        on_exit {
            heartbeat_thread_cnt.dec();
            log(LoggerLevel::DEBUG, "stopped heartbeat thread");
        }
        log(LoggerLevel::DEBUG, "started heartbeat thread");

        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (!shutdown_flag) {
            while (True) {
                try {
                    on_error cluster_processes.rollback();
                    on_success cluster_processes.commit();

                    date now = now_us();
                    # update heartbeat for our row only
                    int rowcount = cluster_processes.update({
                        "heartbeat": now,
                    }, {
                        "process_network_id": master_network_id,
                        "node": node,
                        "pid": getpid(),
                    });
                    QDBG_LOG("heartbeat update: %y (updated: %d)", now, rowcount);
                    if (!rowcount) {
                        # our row has been deleted; terminate immediately
                        log(LoggerLevel::INFO, "no cluster_processes row exists for this master process; terminating all child "
                            "processes immediately");
                        terminateNode();
                    }
                } catch (hash<ExceptionInfo> ex) {
                    if (*string msg = trans.restartTransaction(ex)) {
                        log(LoggerLevel::WARN, "%s", msg);
                        continue;
                    }
                    log(LoggerLevel::ERROR, "%s", get_exception_string(ex));
                    continue;
                }
                trans.reset();
                break;
            }

            if (!active) {
                heartbeatCheckActiveMaster();
            }

            # wait for next poll interval
            {
                heartbeat_mutex.lock();
                on_exit heartbeat_mutex.unlock();

                QorusSharedApi::waitCondition(heartbeat_cond, heartbeat_mutex, HeartbeatInterval, \shutdown_flag);
            }
        }
    }

    #! Terminate node immediately
    terminateNode() {
        # we will terminate here; the process lock will not be unlocked
        m.lock();

        foreach AbstractQorusProcess proc in (node_process_map{node}.iterator()) {
            log(LoggerLevel::INFO, "terminating process %y", proc.getId());
            proc.terminate();
        }

        int num = node_process_map{node}.size();
        log(LoggerLevel::INFO, "%d process%s terminated; terminating this master node %y", num, num == 1 ? "" : "es",
            master_network_id);
        exit(1);
    }

    #! Check active master heartbeat and elect a new active master if it failed
    private heartbeatCheckActiveMaster() {
        QDBG_ASSERT(active_master);
        try {
            active_master.getInfo(NodeMemoryTimeout);
            log(LoggerLevel::INFO, "active master OK");
            return;
        } catch (hash<ExceptionInfo> ex) {
            # NOTE: "active_master" can disappear while calling in case of an active -> passive failover to this node
            log(LoggerLevel::ERROR, "error contacting active master %y: %s: %s", active_master_network_id, ex.err,
                ex.desc);
        }

        *hash<auto> row = selectRowFromTable(cluster_processes, {
            "where": {
                "active_master": 1,
            },
        });

        # check if node matches
        if (row.node != active_master_node) {
            log(LoggerLevel::INFO, "active master has changed from %y to %y", active_master_node, row.node);
            return;
        }

        date cutoff = now_us() - MasterCutoffInterval;
        if (row.heartbeat > cutoff) {
            log(LoggerLevel::INFO, "active master %y heartbeat %y > %y: OK", row.process_network_id, row.heartbeat, cutoff);
            return;
        }
        if (!row) {
            log(LoggerLevel::INFO, "NO-ACTIVE-MASTER: there is no active master process for this cluster");
            return;
        } else if (!row.heartbeat) {
            log(LoggerLevel::INFO, "ACTIVE-MASTER-ERROR: active master %y has no heartbeat", row.process_network_id);
        } else {
            log(LoggerLevel::INFO, "ACTIVE-MASTER-HEARTBEAT-ERROR: active master %y on node %y (host %y pid %s) has expired "
                "heartbeat %y", row.process_network_id, row.node, row.host, row.pid, row.heartbeat);
        }

        electNewActiveMaster(row.node, row.process_network_id);
    }

    #! Elect a new active master process
    private electNewActiveMaster(string old_master_node, string old_master_id) {
        # ensure that only one thread executes the active master takeover at a time
        ActiveMasterHelper amh();
        if (*int tid = amh.start()) {
            log(LoggerLevel::INFO, "active master takeover in progress in TID %d, waiting for process to complete", tid);
            amh.waitComplete();
            log(LoggerLevel::INFO, "active master takeover process complete; new status: %s", active ? "active" : "passive");
            return;
        }

        log(LoggerLevel::INFO, "electing new active master");
        *string id;
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                id = getNewActiveMasterIdIntern();
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                log(LoggerLevel::ERROR, "error electing new active master: %s", get_exception_string(ex));
                return;
            }
            break;
        }
        if (!id) {
            log(LoggerLevel::INFO, "no eligible passive masters");
            return;
        }
        if (id != master_network_id) {
            log(LoggerLevel::INFO, "election indicated %y will be the new active master; waiting for confirmation",
                id);
            return;
        }

        log(LoggerLevel::INFO, "election indicated that this node (%y) will be the new active master; recovering "
            "node %y", master_network_id, old_master_node);

        becomeActiveMaster(old_master_node, old_master_id);
    }

    #! Called from the active master when the active master restarts
    private doActiveTakeover(int index, string sender, string mboxid, string old_master_node, string old_master_id,
            *bool old_active_recovered, *bool processes_killed) {
        try {
            # ensure that only one thread executes the active master takeover at a time
            ActiveMasterHelper amh();
            if (*int tid = amh.start()) {
                log(LoggerLevel::INFO, "active master takeover in progress in TID %d, waiting for process to "
                    "complete", tid);
                amh.waitComplete();
                log(LoggerLevel::INFO, "active master takeover process complete; new status: %s",
                    active ? "active" : "passive");
                sendAnyResponse(index, sender, mboxid, CPC_ACK);
                return;
            }

            log(LoggerLevel::INFO, "active master %y indicated that this node (%y) will be the new active master; "
                "recovering node %y", old_master_id, master_network_id, old_master_node);

            becomeActiveMasterUpdateDb(old_master_node, old_master_id);
            sendAnyResponse(index, sender, mboxid, CPC_ACK);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::ERROR, "error handling active master failover: %s", get_exception_string(ex));
            sendExceptionResponse(index, sender, mboxid, ex);
        }
        becomeActiveMasterFinalize(old_master_node, old_master_id, old_active_recovered, processes_killed);
    }

    #! Returns the new active master ID by choosing the oldest passive master; implements a restartable transaction
    private *string getNewActiveMasterId() {
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                on_error cluster_processes.rollback();

                return getNewActiveMasterIdIntern();
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                log(LoggerLevel::ERROR, "error determining new active master: %s", get_exception_string(ex));
                return;
            }
            break;
        }
    }

    #! Returns the new active master ID by choosing the oldest passive master
    private *string getNewActiveMasterIdIntern() {
        list<string> ids = cluster_processes.select({
            "columns": (
                "process_network_id",
                "created",
                cop_as(cop_over(cop_min("created"), "process_type"), "min_created"),
            ),
            "where": {
                "process_type": QDP_NAME_QORUS_MASTER,
                "active_master": NULL,
                "heartbeat": op_gt(now_us() - MasterCutoffInterval),
            },
            "superquery": {
                "columns": ("process_network_id",),
                "where": {
                    "min_created": op_ceq("created"),
                },
            },
        }).process_network_id;
        # in the unlikely case of more than one row with the same "created" timestamp, we pick the row with the minimum proc ID
        return (ids.lsize() > 1)
            ? sort(ids)[0]
            : ids[0];
    }

    #! Converts this passive master to the active master
    private becomeActiveMaster(string old_master_node, string old_master_id, *bool old_active_recovered, *bool processes_killed) {
        becomeActiveMasterUpdateDb(old_master_node, old_master_id);
        becomeActiveMasterFinalize(old_master_node, old_master_id, old_active_recovered, processes_killed);
    }

    #! Updates the DB to become the new active master
    private becomeActiveMasterUpdateDb(string old_master_node, string old_master_id) {
        startup_done.inc();
        on_error startup_done.dec();

        active = True;

        # update master row
        QorusRestartableTransaction trans(cluster_processes.getDriverName());
        while (True) {
            try {
                on_error cluster_processes.rollback();
                on_success cluster_processes.commit();

                int rows = cluster_processes.update({
                    "info": PassiveYaml,
                    "active_master": NULL,
                }, {
                    "process_network_id": old_master_id,
                    "active_master": 1,
                });
                if (!rows) {
                    log(LoggerLevel::INFO, "could not update old active master row for %y; abandoning election");
                    return;
                }

                rows = cluster_processes.update({
                    "info": ActiveYaml,
                    "active_master": 1,
                }, {
                    "process_network_id": master_network_id,
                });
                QDBG_LOG("update row for %y to active master status: %d", master_network_id, rows);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    #! Finalizes the active master failover process
    /** This method cannot fail; if there is an error, the error is logged and the process terminates immediately
    */
    private becomeActiveMasterFinalize(string old_master_node, string old_master_id, *bool old_active_recovered,
            *bool processes_killed) {
        on_exit startup_done.dec();

        # delete the active master client
        delete active_master;

        try {
            recoverActiveMaster(old_master_node, old_master_id, old_active_recovered, processes_killed);
            startNodeThread();
            startInitialProcesses();
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::FATAL, "error finalizing active master transition: %s", get_exception_string(ex));
            log(LoggerLevel::FATAL, "terminating due to fatal error");
            exit(1);
        }
    }

    #! Called when shutting down the cluster and all processes have been stopped
    private processesStopped() {
        if (has_master_row) {
            QorusRestartableTransaction trans(cluster_processes.getDriverName());
            while (True) {
                try {
                    on_error cluster_processes.rollback();
                    on_success cluster_processes.commit();

                    # delete our row only
                    int rows =
                    cluster_processes.del({"process_network_id": master_network_id, "node": node, "pid": getpid()});
                    QDBG_LOG("removed master row for %y: %d", master_network_id, rows);
                } catch (hash<ExceptionInfo> ex) {
                    if (*string msg = trans.restartTransaction(ex)) {
                        log(LoggerLevel::WARN, "%s", msg);
                        continue;
                    }
                    rethrow;
                }
                break;
            }
        }
%ifdef QorusDebugInternals
        else
            log(LoggerLevel::DEBUG, "no master row to remove");
%endif
    }

    # called when the cluster has been stopped
    private clusterStopped() {
        stopNodeThread();

        # stop pub thread
        pubq.push();

        # wait for pub thread to terminate
        pub_thread_cnt.waitForZero();

        # wait for heartbeat thread to terminate
        heartbeat_thread_cnt.waitForZero();
    }

    # called before trying to restart process
    hash<string, hash<ProcessNotificationInfo>> notifyAbortedProcessAllInitial(string id, *hash<string, bool> ex, date abort_timestamp) {
        if (id == "qorus-core") {
            subscription_mutex.lock();
            on_exit subscription_mutex.unlock();

            remove log_subscribed;
        }
        return AbstractQorusProcessManager::notifyAbortedProcessAllInitial(id, ex, abort_timestamp);
    }

    #! registers the given server and gets the URLs for the server process
    registerServer(string proc_name, *hash<ClusterProcInfo> info) {
        # set placeholder for process URLs
        setUrls(proc_name);
        on_error unblockClientRequests(proc_name, True);
        if (!info) {
            # get URLs for process
            info = getClusterProcInfoFromName(proc_name);
            if (!info) {
                throw "UNKNOWN-PROCESS-ERROR", sprintf("no info for process %y", proc_name);
            }
        }
        # can only register internal processes
        QDBG_ASSERT(info);
        log(LoggerLevel::INFO, "registered server %y with info: %y", proc_name, info);
        # save URLs for process
        updateUrlsConditional(info);
    }

    logArgs(int lvl, string msg, auto args) {
        string fmsg = vsprintf(msg, args);
        logger.log(lvl, "%s", fmsg);

        if (lvl == Logger::LoggerLevel::FATAL) {
            stdout.print(fmsg + "\n");
        }
    }

    handleQorusCoreRegistration(ZMsg msg, int index, string sender, string mboxid) {
        hash<auto> info = qorus_cluster_deserialize(msg.popBin());
        if (!active) {
            throw "MASTER-API-ERROR", sprintf("cannot register qorus-core with a passive master; "
                "info: %y", info.info);
        }
        if (!opts.independent) {
            throw "MASTER-API-ERROR", sprintf("cannot register qorus-core with an active master in "
                "dependent mode; info: %y", info.info);
        }

        background handleQorusCoreRegistrationIntern(index, sender, mboxid, info);
    }

    # called in the active master when a remote process is aborted
    handleRemoteProcessAbort(list<hash<ClusterProcInfo>> info_list) {
        if (!active) {
            log(LoggerLevel::INFO, "MASTER-API-ERROR: ignoring %y message in a passive master; info_list: %y",
                CPC_MR_REMOTE_PROCESS_ABORTED, info_list);
            return;
        }

        # process ID -> proc, restart
        hash<string, hash<ProcessTerminationInfo>> aborted_hash;

        {
            m.lock();
            on_exit m.unlock();

            waitBlockedProcessesIntern();

            foreach hash<ClusterProcInfo> info in (info_list) {
                try {
                    AbstractQorusProcess proc = remove ph{info.id};
                    log(LoggerLevel::INFO, "processing remote process %y abort event on node %y (%s pid %d)", info.id,
                        info.node, info.host, info.pid);

                    aborted_hash{info.id} = <ProcessTerminationInfo>{
                        "proc": proc,
                        "restart": !(remove ignore_abort_hash{info.id}),
                    };

                    remove dependent_process_hash{info.id};
                    # allow custom processing per removed process within the lock
                    processRemovedIntern(proc);
                } catch (hash<ExceptionInfo> ex) {
                    log(LoggerLevel::ERROR, "error processing remote abort event for %y on node %y (%s pid %d): %s", info.id,
                        info.node, info.host, info.pid, get_exception_string(ex));
                }
            }
        }

        if (aborted_hash) {
            log(LoggerLevel::INFO, "the following processes aborted in remote node %y (%s): %y", info_list[0].node,
                info_list[0].host, keys aborted_hash);
            # handle aborted processes
            handleAbortedProcesses(aborted_hash);
        }
    }

    private bool processAbortedRestartImpl(string id, AbstractQorusProcess proc, bool restart,
            reference<hash<auto>> ctx) {
        if (proc instanceof QorusCoreProcess) {
            if (restart && shutdown_flag) {
                log(LoggerLevel::INFO, "not restarting qorus-core; system is shutting down");
                restart = False;
            }

            QorusCoreProcess coreproc = cast<QorusCoreProcess>(proc);
            coreproc.clearInterfaceLists(sessionid);

            # transition processes removed
            list<AbstractQorusProcess> trans_list;
            # process ID -> proc, restart
            hash<string, hash<ProcessTerminationInfo>> aborted_hash;

            {
                # update running interface lists
                m.lock();
                on_exit m.unlock();

                # kill all transitioning processes
                if (tph) {
                    foreach hash<auto> i in (tph.pairIterator()) {
                        # kill the process
                        i.value.terminate();
                        # remove from the transition list
                        removeTransitionProcessIntern(i.key, True);
                        # add to transition list to call processRemovedImpl() outside the lock
                        trans_list += i.value;
                    }
                    log(LoggerLevel::INFO, "transition process terminated: %y", keys tph);
                }

                # remove all dependent processes in the primary process hash
                if (dependent_process_hash) {
                    list<string> dep_proc_ids = keys dependent_process_hash;
                    foreach AbstractQorusProcess dep_proc in (map $1, (remove ph{dep_proc_ids}).iterator(), $1) {
                        string dep_proc_id = dep_proc.getId();
                        dep_proc.terminate();
                        log(LoggerLevel::INFO, "terminated dependent process: %y", dep_proc_id);
                        removeAbortedProcess(dep_proc_id, \aborted_hash, True);
                    }
                    QDBG_ASSERT(!ignore_abort_hash{dep_proc_ids});
                    QDBG_ASSERT(!dependent_process_hash);
                }

                # add remaining interface processes to qorus-core
                map cast<AbstractQorusInterfaceProcess>($1).addToCore(coreproc), ph.iterator(),
                    $1 instanceof AbstractQorusInterfaceProcess;
            }

            # cleanup transition processes removed above
            map processRemovedImpl($1), trans_list;

            # cleanup processes killed above
            if (aborted_hash) {
                log(LoggerLevel::INFO, "the following processes have been terminated: %y", keys aborted_hash);
                # handle aborted processes
                handleAbortedProcesses(aborted_hash);
            }
        }
        if (restart) {
            # grab atomic restart lock
            ctx.aph = new AtomicProcessHelper(id);
        }
        return restart;
    }

    private processAbortNotificationImpl(string process) {
        # this method intentionally left blank
    }

    # called from QorusProcessManager for process aborts (server-side)
    private processAbortedImpl(string id, AbstractQorusProcess proc, bool restart, *hash<auto> ctx) {
        if (ctx.aph) {
            # free atomic restart lock
            delete ctx.aph;
        }
    }

    # called when clients abort (client-side)
    private processAbortedImpl(string id, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        QDBG_LOG("processAbortedImpl() id: %y info: %y restarted: %y abort_timestamp: %y", id, info, restarted,
            abort_timestamp);
        # passive masters in a multi-master cluster need to update for active master handovers
        if (restarted && !active &&
            (info.new_active_master_id || (id == active_master_network_id && info.queue_urls))) {
            QDBG_LOG("updating connection info for active master: %y", info);
            QDBG_ASSERT(active_master);
            if (info.new_active_master_id) {
                # unconditionally assume the name of the old active master that this process knows of
                id = active_master.getRemoteProcessId();
                log(LoggerLevel::INFO, "active master updated from %y -> %y", id, info.new_active_master_id);
            }
            updateUrls(id, info, abort_timestamp);
            if (info.new_active_master_id) {
                active_master_network_id = info.new_active_master_id;
            }
            log(LoggerLevel::INFO, "new active master: id: %y URLs: %y", info.new_active_master_id, info.queue_urls);
            abortedProcessNotification(id, info, restarted, abort_timestamp);
        }
    }

    # return all Qorus options
    private hash<auto> getOptionsImpl() {
        return options.get();
    }

    # return the value of a single Qorus option
    private auto getOptionImpl(string opt) {
        return options.get(opt);
    }

    # CHECKING
    private logImpl(int lvl, string msg) {
        # runs unlocked for speed
        try {
            if (logger) {
                if (log_subscribed."qorus-master" && qorus_core) {
                    logger.log(lvl, "%s", msg, new LoggerEventParameter(\qorus_core.logEvent(), "qorus-master",
                        sprintf("%s T%d [%s]: ", now_us().format("YYYY-MM-DD HH:mm:SS.xx"), gettid(),
                        LoggerLevel::getLevel(lvl).getStr()) + msg + "\n"));
                } else {
                    logger.log(lvl, "%s", msg);
                }
            } else {
                print(msg + "\n");
            }
        } catch (hash<ExceptionInfo> ex) {
            stderr.printf("error in log msg: %s: %s\n", get_ex_pos(ex), ex.err, ex.desc);
            if (!logger || lvl < LoggerLevel::FATAL) {
                stdout.print(msg + "\n");
            }
        }

        if (logger && lvl >= LoggerLevel::FATAL) {
            stdout.print(msg + "\n");
        }
    }

    private logCommonInfo(string fmt) {
        list<auto> args;
        args += LoggerLevel::INFO;
        args += vsprintf(fmt, argv);
        call_function_args(\logImpl(), args);
    }

    private logCommonDebug(string fmt) {
        list<auto> args;
        args += LoggerLevel::DEBUG;
        args += vsprintf(fmt, argv);
        call_function_args(\logImpl(), args);
    }

    private logCommonFatal(string fmt) {
        list<auto> args;
        args += LoggerLevel::FATAL;
        args += vsprintf(fmt, argv);
        call_function_args(\logImpl(), args);
    }

    # called when a message is received from a new master process
    private processSelfMsgImpl(ZSocketRouter router, int index, string sender, string mboxid, string cmd, ZMsg msg) {
        if (cmd == CPC_MR_HANDOVER_COMPLETE) {
            string new_url = msg.popStr();
            # make a hash of processes
            hash<auto> h;
            {
                m.lock();
                on_exit m.unlock();

                h = map {$1.key: $1.value.getInfo()}, ph.pairIterator();
            }
            router.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(h));
            handover_queue.push(new_url);
            return;
        }
        try {
            throw "API-ERROR", sprintf("unexpected cmd %y", cmd);
        } catch (hash<ExceptionInfo> ex) {
            error("exception handling cmd: %y from sender: %y: %s: %s: %s", cmd, sender, get_ex_pos(ex), ex.err, ex.desc);
            router.send(sender, mboxid, CPC_EXCEPTION, serializeExceptionResponse(ex));
        }
    }

    # called when a message is received from the active master
    private handleMessageFromActive(ZSocketRouter router, ZMsg msg, string sender, string mboxid, string key, string cmd) {
        QDBG_ASSERT(!active);
        switch (cmd) {
            case CPC_MR_START_REMOTE_PROC: {
                # cannot start processes from the I/O thread
                hash<auto> req = Serializable::deserialize(msg.popBin());
                background startRemoteProcessFromActive(cast<MyRouter>(router).index, sender, mboxid, req);
                return;
            }

            case CPC_MR_STOP_REMOTE_PROC: {
                # cannot stop processes from the I/O thread
                hash<auto> req = Serializable::deserialize(msg.popBin());
                background stopRemoteProcessFromActive(cast<MyRouter>(router).index, sender, mboxid, req);
                return;
            }

            case CPC_MR_GET_MEMORY_INFO: {
                # get memory info for local processes
                hash<auto> process_info;
                {
                    m.lock();
                    on_exit m.unlock();

                    process_info = map {$1.key: $1.value.getProcessMemoryInfo()}, ph.pairIterator();
                }
                # add information for this process
                process_info{master_network_id} = Process::getMemorySummaryInfo();
                # return memory information to caller
                hash<auto> h = {
                    "process_info": process_info,
                    "node_memory_info": getNodeMemoryInfo(),
                    "mem_history": mem_history{node},
                    "proc_history": proc_history{node},
                };
                router.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(h));
                return;
            }

            case CPC_STOP:
                router.send(sender, mboxid, CPC_ACK);
                if (!opts.independent) {
                    # cannot stop the server from the I/O thread
                    background stopServer();
                }
                return;

            case CPC_MR_DO_ACTIVE_TAKEOVER: {
                hash<auto> info = qorus_cluster_deserialize(msg.popBin());
                if (shutdown_qorus_flag) {
                    throw "HANDOVER-ERROR", sprintf("passive master %y cannot assume master status, as it's shutting "
                        "down", master_network_id);
                }
                background doActiveTakeover(cast<MyRouter>(router).index, sender, mboxid, info.old_master_node,
                    info.old_master_id, info.old_master_recovered, info.processes_killed);
                return;
            }

            case CPC_MR_DETACH_KILL_PROCESS: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: detach and kill process %s", sender, mboxid, h.name);
                background detachKillProcessExtern(cast<MyRouter>(router).index, sender, mboxid, h);
                return;
            }

            case CPC_PROCESS_ABORTED: {
                handleProcessAbortedMessage(router, msg, sender, mboxid);
                return;
            }

            default:
                throw "UNSUPPORTED-COMMAND", sprintf("unsupported command %y sent from active master", cmd);
        }
    }

    # called when a message from an unknown sender arrives
    private handleUnknownSender(ZSocketRouter router, ZMsg msg, string sender, string mboxid, string key, data cmd) {
        try {
            if (!active && key == active_master_network_id) {
                handleMessageFromActive(router, msg, sender, mboxid, key, cmd.toString());
                return;
            }
            switch (cmd.toString()) {
                # message from new passive master to active
                case CPC_MR_NEW_PASSIVE_MASTER: {
                    handlePassiveMasterRegistration(msg, cast<MyRouter>(router).index, sender, mboxid);
                    return;
                }

                # message from the new qorus-core process
                case CPC_MR_REGISTER_QORUS_CORE: {
                    handleQorusCoreRegistration(msg, cast<MyRouter>(router).index, sender, mboxid);
                    return;
                }

                # message from new active master immediately after an active -> passive handover
                case CPC_PROCESS_ABORTED: {
                    handleProcessAbortedMessage(router, msg, sender, mboxid);
                    return;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            error("exception handling cmd: %y from sender: %y: %s: %s: %s", cmd, sender, get_ex_pos(ex), ex.err, ex.desc);
            router.send(sender, mboxid, CPC_EXCEPTION, serializeExceptionResponse(ex));
        }
        AbstractQorusProcessManager::handleUnknownSender(router, msg, sender, mboxid, key, cmd);
    }

    handlePassiveMasterRegistration(ZMsg msg, int index, string sender, string mboxid) {
        hash<auto> info = qorus_cluster_deserialize(msg.popBin());
        if (!active) {
            throw "MASTER-API-ERROR", sprintf("cannot register a passive master with a passive master; "
                "info: %y", info.info);
        }
        QDBG_LOG("passive master registration info: %y", info);
        background handlePassiveMasterRegistrationIntern(index, sender, mboxid, info);
    }

    private handlePassiveMasterRegistrationIntern(int index, string sender, string mboxid, hash<auto> info) {
        hash<string, hash<ProcessTerminationInfo>> aborted_hash;
        bool restarted;

        if (startup_done.getCount()) {
            log(LoggerLevel::INFO, "waiting for startup before registering passive master %y", info.info.id);
            startup_done.waitForZero();
            log(LoggerLevel::INFO, "startup done; continuing registration of passive master");
        }

        try {
            {
                m.lock();
                on_exit m.unlock();

                if (passive_master_node_map{info.info.node}) {
                    restarted = True;
                    QDBG_ASSERT(passive_master_id_map{info.info.id});
                    log(LoggerLevel::INFO, "passive master %y restarted on node %y (%s PID %d) with URLs: %y", info.info.id,
                        info.info.node, info.info.host, info.info.pid, info.info.queue_urls);
                    QDBG_ASSERT(info.info.fullType() == "hash<ClusterProcInfo>");
                    passive_master_node_map{info.info.node}.updateRunningDetached(info.info, info.start_timestamp);

                    # handle any terminated processes
                    map removeAbortedProcess($1.getId(), \aborted_hash), ph.iterator(),
                        (!($1 instanceof QorusPassiveMasterProcess)
                            && $1.getNode() == info.info.node
                            && !info.running_procs{$1.getId()});
                    QDBG_LOG("processes on node %y: %y", info.info.node, (map $1.getId(), ph.iterator(),
                        $1.getNode() == info.info.node));
                    QDBG_LOG("processes aborted on node %y: %y", info.info.node, keys aborted_hash);
                } else {
                    log(LoggerLevel::INFO, "registering new passive master %y on node %y (%s PID %d) with URLs: %y",
                        info.info.id, info.info.node, info.info.host, info.info.pid, info.info.queue_urls);
                    # we need to register a new passive master
                    QorusPassiveMasterProcess proc(self, info.info, info.start_timestamp);

                    passive_master_node_map{info.info.node} = passive_master_id_map{info.info.id} =
                        ph{info.info.id} = node_process_map{info.info.node}{info.info.id} = proc;
                    mem_history{info.info.node} = info.mem_history;
                    proc_history{info.info.node} = info.proc_history;
                }
                remote_node_memory_info{info.info.node} = info.node_memory_info;
            }
            sendResponse(index, sender, mboxid, CPC_ACK);
            # publish node info for new passive master
            publishRemoteNodeInfo(info.info.node, info.node_memory_info);
        } catch (hash<ExceptionInfo> ex) {
            error("exception handling passive master registration; sender: %y: %s: %s: %s", sender,
                get_ex_pos(ex), ex.err, ex.desc);
            sendExceptionResponse(index, sender, mboxid, ex);
        }

        if (restarted) {
            # no need to notify external processes, but any in-progress requests to the passive master must be
            # interrupted and updated
            detachProcessIntern(info.info.id, info.info, True, info.start_timestamp);
        }

        if (aborted_hash) {
            log(LoggerLevel::INFO, "the following processes have died on node %y: %y", info.info.node, keys aborted_hash);
            # handle aborted processes
            handleAbortedProcesses(aborted_hash);
        }
    }

    private handleQorusCoreRegistrationIntern(int index, string sender, string mboxid, hash<auto> info) {
        try {
            if (startup_done.getCount()) {
                throw "TRY-AGAIN", sprintf("active master %y is starting up; try again in 10 seconds",
                    master_network_id);
            }
            startup_done.waitForZero();

            QDBG_LOG("registering new qorus-core process: %y", info);
            date start = now_us();

            hash<string, bool> rwfh();
            # services: serviceid -> bool
            hash<string, bool> rsvch();
            hash<string, bool> rjobh();
            {
                m.lock();
                on_exit m.unlock();

                # get a list of running interfaces for ZMQ response (not needed for process)
                foreach AbstractQorusProcess proc in (ph.iterator()) {
                    if (proc instanceof QwfProcess) {
                        rwfh{cast<QwfProcess>(proc).getWorkflowId()} = True;
                    } else if (proc instanceof QsvcProcess) {
                        rsvch{cast<QsvcProcess>(proc).getServiceRecoveryKey()} = True;
                    } else if (proc instanceof QjobProcess) {
                        rjobh{cast<QjobProcess>(proc).getJobId()} = True;
                    }
                }

                if (qorus_core) {
                    log(LoggerLevel::INFO, "qorus-core restarted on node %y (%s PID %d) with URLs: %y", info.node,
                        info.host, info.pid, info.child_urls);
                    # issue #3742: do node housekeeping
                    if (info.node != (string old_node = qorus_core.getNode())) {
                        node_process_map{info.node}{QDP_NAME_QORUS_CORE} =
                            remove node_process_map{old_node}{QDP_NAME_QORUS_CORE};
                        if (!node_process_map{old_node}) {
                            remove node_process_map{old_node};
                        }
                    }
                    hash<ClusterProcInfo> cpinfo = <ClusterProcInfo>{
                        "id": QDP_NAME_QORUS_CORE,
                        "queue_urls": info.child_urls,
                        "node": info.node,
                        "host": info.host,
                        "pid": info.pid,
                    };
                    qorus_core.updateRunningDetached(cpinfo);
                } else {
                    log(LoggerLevel::INFO, "registering new qorus-core process on node %y (%s PID %d) with URLs: %y",
                        info.node, info.host, info.pid, info.child_urls);
                    qorus_core = new QorusCoreProcess(self, info.node, info.host, info.restarted, "-");
                    ph{QDP_NAME_QORUS_CORE} = node_process_map{info.node}{QDP_NAME_QORUS_CORE} = qorus_core;
                    qorus_core.setDetached(info{"pid", "node", "host"} + {
                        "queue_urls": info.child_urls.join(","),
                        "created": now_us(),
                    });
                }
            }

            {
                ClusterProcessHelper cph(self, node, QDP_NAME_QORUS_CORE, "-", QDP_NAME_QORUS_CORE);
                cph.updateProcess(qorus_core);
            }

            hash<auto> mr_info = {
                "info": getClusterProcessInfo(),
                "rwfh": rwfh,
                "rsvch": rsvch,
                "rjobh": rjobh,
                "pub_url": getPubUrl(),
            };

            hash<ClusterProcInfo> proc_info = <ClusterProcInfo>{
                "id": QDP_NAME_QORUS_CORE,
                "queue_urls": info.child_urls,
                "node": info.node,
                "host": info.host,
                "pid": info.pid,
            };
            # inform children of new qorus-core process
            hash<string, hash<ProcessNotificationInfo>> proc_map = notifyAbortedProcessAllInitial(QDP_NAME_QORUS_CORE,
                NOTHING, start);
            notifyAbortedProcessAll(proc_map, QDP_NAME_QORUS_CORE, proc_info, True, start);

            sendResponse(index, sender, mboxid, CPC_OK, mr_info);
        } catch (hash<ExceptionInfo> ex) {
            error("exception handling qorus-core registration; sender: %y: %s: %s: %s", sender,
                get_ex_pos(ex), ex.err, ex.desc);
            sendExceptionResponse(index, sender, mboxid, ex);
        }
    }

    checkResetDatasource(string server_name, hash<auto> ex) {
        # take no action in the master process
    }

    #! checks if the given external process is alive and returns a hash with a \c process_network_id key if so
    private *hash<auto> checkExternalProcessAlive(string type, string id, string node, int pid) {
         if (node != self.node || !pid || !Process::checkPid(pid)) {
            logStartup("* %s %y (%s:%s) no longer exists; clearing", type, id, node, pid ?? "n/a");
            return;
        }
        return selectRowFromTable(cluster_processes, {"where": {"process_network_id": id}});
    }

    # returns the process's GET-INFO response or NOTHING if it can't be reached
    *hash<auto> checkProcessAlive(hash<auto> row, bool do_log = True) {
        string type = row.process_type;
        string id = row.process_network_id;
        string node = row.node;
        *int pid = row.pid;

        if (!pid) {
            return;
        }

        if (ExternalProcesses{type}) {
            return checkExternalProcessAlive(type, id, node, pid);
        }

        # get queue URL
        # FIXME: work with multiple URLs
        QDBG_ASSERT(row.queue_urls);
        if (row.queue_urls == "-") {
            return;
        }
        string queue_url = row.queue_urls.split(",")[0];

        # is this process local
        bool is_local;
        if (node == self.node) {
            if (!pid || !Process::checkPid(pid)) {
                if (do_log)
                    logStartup("* %s %y (%s:%s: %y) no longer exists; clearing", type, id, node, pid ?? "n/a",
                        queue_url);
                return;
            }
            is_local = True;
        }

        # FIXME: check and kill process if API not responding; ensure that the pid
        # corresponds to the desired process
        # FIXME: implement support for process management on different machines

        if (do_log) {
            string str = sprintf("* recovering %s %y (%s:%d: %y)", type, id, node, pid, queue_url);
            log(LoggerLevel::INFO, str);
            if (!opts.startup) {
                stdout.print(str + ": ");
                stdout.sync();
            }
        }
        string our_id = sprintf("master-%s-%d-%d", self.node, getpid(), gettid());
        ZSocketDealer sock(getContext());
        sock.setIdentity(our_id);
        nkh.setClient(sock);
        # set timeout
        sock.setTimeout(DefaultRecoverTimeout);
        sock.connect(queue_url);
        ZMsg msg;
        try {
            sock.send("1", CPC_GET_INFO);
            msg = sock.recvMsg();
            if (do_log) {
                log(LoggerLevel::INFO, "* successfully contacted %s %y (%s:%d: %y)", type, id, node, pid, queue_url);
                if (!opts.startup) {
                    stdout.printf("OK\n");
                    stdout.sync();
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            if (do_log) {
                log(LoggerLevel::ERROR, "* failed to contact %s %y (%s:%d: %y): %s: %s", type, id, node, pid, queue_url, ex.err, ex.desc);
                if (!opts.startup) {
                    stdout.printf("FAILED: %s: %s\n", ex.err, ex.desc);
                    stdout.sync();
                }
            }

            if (is_local && Process::checkPid(pid)) {
                Process::terminate(pid);
            }
            return;
        }

        # parse response message; any errors here are unrecoverable errors
        # ignore mboxid
        msg.popStr();
        string cmd = msg.popStr();
        if (cmd != CPC_OK)
            throw "API-ERROR", sprintf("expecting %y; got %y", CPC_OK, cmd);
        return qorus_cluster_deserialize(msg);
    }

    *hash<auto> getLoggerMap() {
        if (init_logger_map) {
            return init_logger_map;
        }
        omq_loggerid = getLoggerId("qdsp", "omq");
        return init_logger_map = AbstractLogger::getLoggerMap(getTable("loggers"), True, omq_loggerid);
    }

    *int getOmqLoggerId() {
        return omq_loggerid;
    }

    clearLoggerMap() {
        remove init_logger_map;
        remove omq_loggerid;
    }
}

class ClusterProcessHelper {
    public {}

    private {
        QorusMaster master;
        string id;
        *hash<auto> row;
        bool start_flag = True;
        hash<auto> info;
        bool dependent;
    }

    constructor(QorusMaster master, string node, string type, string client_id, string id, bool dependent = False) {
        self.master = master;
        self.id = id;
        self.dependent = dependent;

        int err_cnt = 0;

        QDBG_LOG("ClusterProcessHelper::constructor() type: %y node: %y client_id: %y id: %y (dep: %y)", type, node,
            client_id, id, dependent);

        # there is no way to select an existing row for update or insert a row based on the PK in a
        # single atomic operation (without locking the table), so we do it in a while loop and repeat if a
        # race condition is found
        QorusRestartableTransaction trans(master.cluster_processes.getDriverName());
        while (True) {
            try {
                # do not leave the transaction lock held or process restarts cannot take place
                on_error master.cluster_processes.rollback();
                on_success master.cluster_processes.commit();

                master.cluster_processes.getDatasource().beginTransaction();
                row = master.cluster_processes.selectRow({"where": {"process_network_id": id}, "forupdate": True});

                if (row) {
                    # verify if process exists
                    if (row.queue_urls != "-") {
                        *hash<auto> ih = master.checkProcessAlive(row, False);
                        if (!ih) {
                            on_error master.cluster_processes.rollback();

                            # reuse process entry; we have a lock on the row, so this update must succeed
                            hash<auto> uh = {
                                "queue_urls": "-",
                                "node": node,
                                "host": gethostname(),
                                "pid": getpid(),
                                "interfaces": master.getInterfacesString(),
                                "dependent": dependent.toInt(),
                                "created": now_us(),
                            };
                            master.cluster_processes.update(uh, {"process_network_id": id});
                            QDBG_LOG("ClusterProcessHelper::constructor() updated id: %y", id);
                        } else {
                            start_flag = False;
                            info = ih;
                        }
                    }
                } else {
                    hash<auto> new_row = {
                        "process_network_id": id,
                        "process_type": type,
                        "client_id": client_id,
                        "host": gethostname(),
                        "node": node,
                        "interfaces": master.getInterfacesString(),
                        "dependent": dependent.toInt(),
                        "queue_urls": "-",
                    };
                    # if the insert fails due to a PK error, an exception will be thrown
                    master.cluster_processes.insert(new_row);
                    QDBG_LOG("ClusterProcessHelper::constructor() inserted row: %y", new_row);
                    row = new_row;
                }
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    master.log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }

                master.log(LoggerLevel::ERROR, "failed to upsert %s %y: %s: %s", type, id, ex.err, ex.desc);
                # do not try more than 3 times
                if (++err_cnt > 3) {
                    rethrow;
                }
                master.log(LoggerLevel::WARN, "retrying");
                continue;
            }
            break;
        }
    }

    bool start() {
        return start_flag;
    }

    bool isDependent() {
        return dependent;
    }

    *hash<auto> getInfo() {
        return info;
    }

    *hash<auto> getRow() {
        return row;
    }

    #! Updates the node value for a process entry
    updateNode(hash<NodeHostInfo> node_info) {
        QorusRestartableTransaction trans(master.cluster_processes.getDriverName());
        while (True) {
            try {
                int rows =
                    master.cluster_processes.update(
                        {"host": node_info.host, "node": node_info.node},
                        {"process_network_id": id}
                    );
                QDBG_LOG("updated node: %y host: %y for %y rows: %d", node_info.node, node_info.host, id, rows);
                row.node = node_info.node;
                row.host = node_info.host;
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    master.log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    # commits the transaction
    del() {
        QorusRestartableTransaction trans(master.cluster_processes.getDriverName());
        while (True) {
            try {
                on_error master.cluster_processes.rollback();
                on_success master.cluster_processes.commit();

                int rows =
                    master.cluster_processes.del({"process_network_id": id});
                QDBG_LOG("delete id: %y rows: %d", id, rows);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    master.log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    # commits the transaction
    updateProcess(AbstractQorusProcess proc) {
        if (!start_flag)
            return;

        hash<auto> uh = proc.getClusterProcessesRow() + ("created": now_us());

        QorusRestartableTransaction trans(master.cluster_processes.getDriverName());
        while (True) {
            try {
                on_error master.cluster_processes.rollback();
                on_success master.cluster_processes.commit();

                int rows =
                    master.cluster_processes.update(uh, {"process_network_id": proc.getId()});
                QDBG_LOG("updateProcess uh: %y rows: %d", uh, rows);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    master.log(LoggerLevel::WARN, "%s", msg);
                    continue;
                }
                rethrow;
            }
            break;
        }
    }
}

# this data structure will ensure that blocked threads are signaled in order
hashdecl ProcStatusInfo {
    # > 0 if an operation is in progress
    int block = 1;
    # hash of threads waiting on the operation; TID -> Condition
    /** because hashes maintain insertion order, this hash will be used to ensure that blocked threads are signaled
        in the order that they arrive
    */
    hash<string, Condition> cond_hash();
}

# this class ensures that cluster programs start and stop atomically
class AtomicProcessHelper {
    public {}

    private {
        static Mutex mutex();
        # status hash: process id -> tid -> Condition
        static hash<string, hash<ProcStatusInfo>> status_hash();
    }

    private:internal {
        string id;
    }

    constructor(string id) {
        self.id = id;

        softstring tid = gettid();

        mutex.lock();
        on_exit mutex.unlock();

        while (status_hash{id}.block && !status_hash{id}.cond_hash{tid}) {
            QDBG_LOG("AtomicProcessHelper::constructor() waiting for %y (CONTENTION); queued TIDs: %y", id,
                (map $1.toInt(), keys status_hash{id}.cond_hash));
            # create condition variable
            QDBG_ASSERT(!status_hash{id}.cond_hash{tid});
            (status_hash{id}.cond_hash{tid} = new Condition()).wait(mutex);
        }

        if (!status_hash{id}) {
            status_hash{id} = <ProcStatusInfo>{};
        } else {
            ++status_hash{id}.block;
        }

        QDBG_LOG("AtomicProcessHelper::constructor() acquired %y", id);
        #QDBG_LOG("stack: %N", get_stack());
    }

    destructor() {
        mutex.lock();
        on_exit mutex.unlock();

        # if we are not the last call to release the lock, then exit
        if (--status_hash{id}.block) {
            QDBG_LOG("AtomicProcessHelper::destructor() %y block: %d -> %d", id, status_hash{id}.block + 1,
                status_hash{id}.block);
            return;
        }

        # if there are any blocked threads, signal the first thread that blocked
        if (status_hash{id}.cond_hash) {
            string next_tid = status_hash{id}.cond_hash.firstKey();
            Condition cond = remove status_hash{id}.cond_hash{next_tid};
            QDBG_LOG("AtomicProcessHelper::destructor() releasing %y (CONTENTION); waking TID %d (remaining: %y)", id,
                next_tid, (map $1.toInt(), keys status_hash{id}.cond_hash));
            cond.signal();
        } else {
            QDBG_LOG("AtomicProcessHelper::destructor() releasing %y", id);
            remove status_hash{id};
        }
    }
}

#! Ensures that only one thread at a time runs the active master takeover procedure
class ActiveMasterHelper {
    private {
        static Mutex lck();
        static Condition cond();
        static int threads_waiting;
        static int tid;
    }

    #! If the current threads is the takeover thread, the lock is released and any waiting threads are awakened
    destructor() {
        if (tid == gettid()) {
            lck.lock();
            on_exit lck.unlock();

            remove tid;
            if (threads_waiting) {
                cond.broadcast();
            }
        }
    }

    #! Returns the TID if the active takeover is already in progress in another thread
    /** otherwise returns NOTHING and marks this thread as the takeover thread by setting "tid" to this TID
    */
    *int start() {
        lck.lock();
        on_exit lck.unlock();

        if (tid) {
            return tid;
        }

        tid = gettid();
    }

    #! Waits for the takeover process to be complete
    /** Cannot be called by the thread performing the takeover
    */
    waitComplete() {
        QDBG_ASSERT(tid != gettid());

        lck.lock();
        on_exit lck.unlock();

        while (tid) {
            ++threads_waiting;
            cond.wait(lck);
            --threads_waiting;
        }
    }
}

class QorusRecoveryZSocketDealer inherits ZSocketDealer {
    private {
        hash<auto> row;
    }

    constructor(ZContext zctx, NetworkKeyHelper nkh, string identity, hash<auto> row) : ZSocketDealer(zctx) {
        self.row = row;
        string queue_url = row.queue_urls.split(",")[0];
        nkh.setClient(self);
        # set identity
        setIdentity(identity);
        # connect to socket
        connect(queue_url);
    }

    hash<auto> getRow() {
        return row;
    }
}

%ifdef QorusDebugInternals
sub qdbg_assert(bool b) {
    if (!b)
        throw "ASSERT-ERROR", sprintf("stack: %N", get_stack());
}
*list sub get_stack() {
    if (!HAVE_RUNTIME_THREAD_STACK_TRACE)
        return;
    *list stack = get_thread_call_stack();
    if (!stack)
        return;
    splice stack, 0, 2;
    return map $1.type != "new-thread" ? sprintf("%s %s()", get_ex_pos($1), $1.function) : "new-thread", stack;
}
# lines with QDBG_* must be on one line
sub QDBG_LOG(string fmt) { if (Qorus) Qorus.log(LoggerLevel::INFO, "%s", vsprintf(fmt, argv)); else vprintf(fmt + "\n", argv); }
sub QDBG_LOG(code func, string fmt) { call_function_args(func, (LoggerLevel::INFO, fmt, argv)); }
sub QDBG_ASSERT(auto v) { qdbg_assert(v.toBool()); }
%endif
