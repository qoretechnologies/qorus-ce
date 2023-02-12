#! -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

/* NOTE: server -> master payloads are DEALER requests with the following format:
    sender, <empty frame>, master-assigned-process-name, cmd, ...

    where "master-assigned-process-name" is the process name as given on the command-line by the master process
*/

#! DEALER CORE -> MASTER (data): "MR-START-DSP": start datasource pool cluster server process
/** Payload:
        string name
        string connstr
        *hash<LoggerParams> logger_params
        *softlist<string> args

    response:
        ROUTER MASTER -> CORE (data): "OK" (CPC_OK)
            Payload:
                hash<ClusterProcInfo> info
                bool already_started
*/
const CPC_MR_START_DSP = "MR-START-DSP";

#! DEALER CORE -> MASTER (data): "MR-START-WF": start workflow cluster server process
/** Payload:
        string name (= workflowid)
        string wfname
        string wfversion
        int sessionid
        *softlist<string> args

    response:
        ROUTER MASTER -> CORE (data): "OK" (CPC_OK)
            Payload:
                hash<ClusterProcInfo> info
                bool already_started
*/
const CPC_MR_START_WF = "MR-START-WF";

#! DEALER CORE -> MASTER (data): "MR-START-SVC": start service cluster server process
/** Payload:
        string name (= serviceid)
        string svctype
        string svcname
        string svcversion
        *softlist<string> args

    response:
        ROUTER MASTER -> CORE (data): "OK" (CPC_OK)
            Payload:
                hash<ClusterProcInfo> info
                bool already_started
*/
const CPC_MR_START_SVC = "MR-START-SVC";

#! DEALER CORE -> MASTER (data): "MR-START-JOB": start job cluster server process
/** Payload:
        string name (= jobid)
        string jobname
        string jobversion
        int sessionid
        *softlist<string> args

    response:
        ROUTER MASTER -> CORE (data): "OK" (CPC_OK)
            Payload:
                hash<ClusterProcInfo> info
                bool already_started
*/
const CPC_MR_START_JOB = "MR-START-JOB";

#! DEALER CORE -> MASTER (data): "MR-STOP-PROC": stop cluster server process
/** Payload:
        string name

    response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_STOP_PROCESS = "MR-STOP-PROC";

#! DEALER CORE -> MASTER (data): "MR-DETACH-PROC": detach cluster server process
/** Payload:
        string name

    response:
        ROUTER MASTER -> CORE (data): "OK" (CPC_OK)
            Payload:
                bool detached
*/
const CPC_MR_DETACH_PROCESS = "MR-DETACH-PROC";

#! DEALER CORE -> MASTER (data): "MR-DETACH-KILL-PROC": detach and kill cluster server process
/** Payload:
        string name

    response:
        ROUTER MASTER -> CORE (data): "OK" (CPC_OK)
            Payload:
                bool detached
*/
const CPC_MR_DETACH_KILL_PROCESS = "MR-DETACH-KILL-PROC";

#! DEALER CORE -> MASTER (data): "MR-IGNORE-PROC-ABORT": ignore process abort and disable process restart
/** Payload:
        string name
        *string reason

    response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)

    issue #2647: to avoid race conditions when stopping and restarting processes
*/
const CPC_MR_IGNORE_PROCESS_ABORT = "MR-IGNORE-PROC-ABORT";

#! DEALER CORE -> MASTER (data): "MR-RUN-INDEPENDENT": allow a process to run independently of qorus-core
/** Payload:
        string name

    response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_RUN_INDEPENDENT = "MR-RUN-INDEPENDENT";

#! DEALER CORE -> MASTER (data): "MR-UPDATE-PROC-INFO": update process information in the DB
/** Payload:
        string name
        hash<auto> info

    response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_UPDATE_PROCESS_INFO = "MR-UPDATE-PROC-INFO";

#! DEALER CORE -> MASTER (STRING): "MR-STARTUP-MSG": report startup message to master
/** response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_STARTUP_MSG = "MR-STARTUP-MSG";

#! DEALER CORE -> MASTER (data): "MR-STARTUP-COMPLETE": report startup status to master
/** Payload:
        bool ok
        int pid
        string status

    response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_STARTUP_COMPLETE = "MR-STARTUP-COMPLETE";

#! DEALER CORE -> MASTER (STRING): "MR-SHUTDOWN-MSG": report shutdown message to master
/** response:
        ROUTER MASTER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_SHUTDOWN_MSG = "MR-SHUTDOWN-MSG";

#! DEALER CORE -> MASTER (data): "MR-SHUTDOWN-COMPLETE": report shutdown status to master
/** Payload:
        bool ok

    response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_SHUTDOWN_COMPLETE = "MR-SHUTDOWN-COMPLETE";

#! DEALER MASTER -> MASTER (NONE): "MR-HANDOVER-COMPLETE": report handover complete
/** response:
        ROUTER MASTER -> MASTER (NONE): "OK" (CPC_OK)
            Payload:
                <id>:
                    list<string> urls
                    string host
                    int pid
                    string type
                    string client_id
                    + other process-specific keys
*/
const CPC_MR_HANDOVER_COMPLETE = "MR-HANDOVER-COMPLETE";

#! DEALER ANY -> MASTER (STRING): "MR-GET-PROCESS-INFO": get info for process
/** Payload:
        string (process name)

    response:
        ROUTER MASTER -> CORE (data): "OK" (CPC_OK)
            - return value is either the following hash:
                list<string> urls
                string host
                int pid
                string type
                string client_id
                + other process-specific keys
            - or nothing if the given process does not exist
*/
const CPC_MR_GET_PROCESS_INFO = "MR-GET-PROCESS-INFO";

#! DEALER CORE -> MASTER (data): "MR-BCAST-IFS": broadcast to all interfaces; broadcasts are made asynchronously to the request
/** Payload:
        string subsystem
        string method
        *softlist<auto> args

    response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_BCAST_IFS = "MR-BCAST-IFS";

#! DEALER CORE -> MASTER (data): "MR-BCAST-CONFIRM-IFS": broadcast to all interfaces and confirm synchronously when done
/** Payload:
        string subsystem
        string method
        *softlist<auto> args

    response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_BCAST_CONFIRM_IFS = "MR-BCAST-CONFIRM-IFS";

#! DEALER CORE -> MASTER (data): "MR-BCAST-IFS-DIRECT": broadcast to all interfaces; broadcasts are made asynchronously to the request
/** Payload:
        string method
        *softlist<auto> args

    response:
        ROUTER MASTER -> CORE (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_BCAST_IFS_DIRECT = "MR-BCAST-IFS-DIRECT";

#! PUB MASTER -> ALL (data): "MR-PUB-STARTUP-COMPLETE": publish qorus cluster startup complete (rebroadcasted from qorus-core)
/** Payload:
        bool ok
        int pid (if ok == True)
        string status
*/
const CPC_MR_PUB_STARTUP_COMPLETE = "MR-PUB-STARTUP-COMPLETE";

#! PUB MASTER -> ALL (STRING): "MR-PUB-STARTUP-MSG": publish startup message (rebroadcasted from qorus-core)
const CPC_MR_PUB_STARTUP_MSG = "MR-PUB-STARTUP-MSG";

#! PUB MASTER -> ALL (STRING): "MR-PUB-SHUTDOWN-MSG": publish shutdown message (rebroadcasted from qorus-core)
const CPC_MR_PUB_SHUTDOWN_MSG = "MR-PUB-SHUTDOWN-MSG";

#! PUB MASTER -> ALL (data): "MR-PUB-SHUTDOWN-COMPLETE-CORE": publish core shutdown status (rebroadcasted from qorus-core)
/** Payload:
        bool ok
*/
const CPC_MR_PUB_SHUTDOWN_COMPLETE_CORE = "MR-PUB-SHUTDOWN-COMPLETE-CORE";

#! PUB MASTER -> ALL (STRING): "MR-PUB-SHUTDOWN-COMPLETE-MASTER": publish master shutdown status
const CPC_MR_PUB_SHUTDOWN_COMPLETE_MASTER = "MR-PUB-SHUTDOWN-COMPLETE-MASTER";

#! PUB MASTER -> ALL (data): "MR-PUB-PROCESS-STARTED": publish process (re)start info
/** Payload:
        string id
        string node
        string status
        list<string> child_urls
        string host
        int pid
        string type
        string client_id
        # virtual memory size in bytes
        int vsz
        # resident memory size in bytes
        int rss
        # private memory size in bytes
        int priv
        # process start code; 0 = manual start, 1 = manual restart, 2 = automatic restart
        int start_code
*/
const CPC_MR_PUB_PROCESS_STARTED = "MR-PUB-PROCESS-STARTED";

#! PUB MASTER -> ALL (data): "MR-PUB-PROCESS-STOPPED": publish process stop info
/** Payload:
        string id
        string node
        string status
        list<string> child_urls
        string host
        int pid
        string type
        string client_id
*/
const CPC_MR_PUB_PROCESS_STOPPED = "MR-PUB-PROCESS-STOPPED";

#! PUB MASTER -> ALL (data): "MR-PUB-PROCESS-START-ERROR": publish process start error info
/** Payload:
        string id
        string node
        string status
        list<string> child_urls
        string host
        int pid
        string type
        string client_id
        string error
*/
const CPC_MR_PUB_PROCESS_START_ERROR = "MR-PUB-PROCESS-START-ERROR";

#! PUB MASTER -> ALL (data): "MR-PUB-PROCESS-MEMORY-CHANGE": publish memory change info for a cluster process
/** Payload:
        string id
        string node
        string status
        list<string> child_urls
        string host
        int pid
        string type
        string client_id
        # virtual memory size in bytes
        int vsz
        # resident memory size in bytes
        int rss
        # private memory size in bytes
        int priv
        # percentage of main memory used
        int pct
*/
const CPC_MR_PUB_PROCESS_MEMORY_CHANGE = "MR-PUB-PROCESS-MEMORY-CHANGE";

#! PUB MASTER -> ALL (data): "MR-PUB-NODE-INFO": publish node info
/** Payload:
        # the node name
        string name

        # the total private memory used by the Qorus instance on the node in bytes
        int node_priv

        # the total private memory used by the Qorus instance on the node as a string
        string node_priv_str

        # total RAM in use on the machine
        int node_ram_in_use

        # total RAOM in use on the machine as a string
        string node_ram_in_use_str

        # the number of CPUs on the node
        int node_cpu_count

        # the average load on the machine over the last minute
        float node_load_pct

        # the number of Qorus processes on the node for this instance
        int processes
*/
const CPC_MR_PUB_NODE_INFO = "MR-PUB-NODE-INFO";

#! PUB MASTER -> ALL (data): "MR-PUB-NODE-REMOVED": publish node removed event
/** Payload:
        # the node name
        string name

    @since Qorus 5.0
*/
const CPC_MR_PUB_NODE_REMOVED = "MR-PUB-NODE-REMOVED";

#! DEALER CORE -> QORUS-MASTER: "MR-UPDATE-LOGGER": cause qorus-master to update logger
const CPC_MR_UPDATE_LOGGER = "MR-UPDATE-LOGGER";

#! DEALER CORE -> QORUS-MASTER: "MR-UPDATE-PROMETHEUS-LOGGER": cause qorus-master to update the prometheus logger
const CPC_MR_UPDATE_PROMETHEUS_LOGGER = "MR-UPDATE-PROMETHEUS-LOGGER";

#! DEALER CORE -> QORUS-MASTER: "MR-UPDATE-GRAFANA-LOGGER": cause qorus-master to update the grafana logger
const CPC_MR_UPDATE_GRAFANA_LOGGER = "MR-UPDATE-GRAFANA-LOGGER";

#! DEALER CORE -> QORUS-MASTER: "MR-ROTATE-LOGGER": cause qorus-master to rotate logger
const CPC_MR_ROTATE_LOGGER = "MR-ROTATE-LOGGER";

#! DEALER CORE -> QORUS-MASTER: "MR-ROTATE-QDSP-LOGGER": cause qorus-master to rotate qdsp logger
const CPC_MR_ROTATE_QDSP_LOGGER = "MR-ROTATE-QDSP-LOGGER";

#! DEALER MASTER -> MASTER (data): "MR-NEW-PASSIVE-MASTER": a new passive master informs the active master that it has started
/**
    Payload:
        hash<ClusterProcInfo> info
        hash<auto> node_memory_info
        hash<string, list<hash<auto>>> mem_history
        hash<string, list<hash<auto>>> proc_history
        *hash<string, bool> running_procs
        date start_timestamp

    response:
        ROUTER SERVER -> MASTER (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_NEW_PASSIVE_MASTER = "MR-NEW-PASSIVE-MASTER";

#! DEALER MASTER (active) -> MASTER (passive): "MR-START-REMOTE-PROC": start a process on a remote Qorus instance
/**
    Payload:
        string class_name
        string args

    response:
        ROUTER MASTER -> MASTER (data): "OK" (CPC_OK)
            int pid

*/
const CPC_MR_START_REMOTE_PROC = "MR-START-REMOTE-PROC";

#! DEALER MASTER (active) -> MASTER (passive): "MR-STOP-REMOTE-PROC": stop a process on a remote Qorus instance
/**
    Payload:
        string id
        list<string> urls

    response:
        ROUTER MASTER -> MASTER (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_STOP_REMOTE_PROC = "MR-STOP-REMOTE-PROC";

#! DEALER MASTER (passive) -> MASTER (active): "MR-REMOTE-PROC-ABORTED": passive master notifies active master that a process has aborted
/**
    Payload:
        list<hash<ClusterProcInfo>> info_list

    response: none: one-way msg
*/
const CPC_MR_REMOTE_PROCESS_ABORTED = "MR-REMOTE-PROC-ABORTED";

#! DEALER MASTER (active) -> MASTER (passive): "MR-GET-MEMORY-INFO": retrieves memory information for remote nodes
/**
    Payload: none

    response:
        ROUTER MASTER -> MASTER (data): "OK" (CPC_OK)
            hash<auto> process_info
            hash<auto> node_info
            hash<string, list<hash<auto>>> mem_history
            hash<string, list<hash<auto>>> proc_history
*/
const CPC_MR_GET_MEMORY_INFO = "MR-GET-MEMORY-INFO";

#! DEALER MASTER (old active) -> MASTER (passive): "MR-DO-ACTIVE-TAKEOVER": immediately become the active master
/**
    Payload:
        string old_master_node
        string old_master_id
        *bool old_active_recovered
        *bool processes_killed

    response:
        ROUTER MASTER -> MASTER (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_DO_ACTIVE_TAKEOVER = "MR-DO-ACTIVE-TAKEOVER";

#! DEALER qorus-core -> MASTER (active): "MR-REGISTER-QORUS-CORE": register independent qorus-core process
/**
    Payload:
        string id
        string node
        list<string> child_urls
        string host
        int pid
        bool restarted
        int vsz         # virtual memory size in bytes
        int rss         # resident memory size in bytes
        int priv        # private memory size in bytes

    response:
        ROUTER MASTER -> MASTER (NONE): "OK" (CPC_OK)
            hash<ClusterProcInfo> info
            hash<string, bool> rwfh
            hash<string, bool> rsvch
            hash<string, bool> rjobh
            string pub_url
            *int sessionid
*/
const CPC_MR_REGISTER_QORUS_CORE = "MR-REGISTER-QORUS-CORE";

#! DEALER MASTER (passive) -> MASTER (active): "MR-DO-PASSIVE-SHUTDOWN": tell the active master that a passive master is shutting down
/**
    Payload: none

    response:
        ROUTER MASTER -> MASTER (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_DO_PASSIVE_SHUTDOWN = "MR-DO-PASSIVE-SHUTDOWN";

#! DEALER qorus-core -> MASTER (active): "MR-REGISTER-QSVC": register independent qsvc process
/**
    Payload:
        string servicetype
        string servicename
        string serviceversion
        int serviceid
        string uuid
        int stack_size
        string id
        string node
        list<string> child_urls
        string host
        int pid
        bool restarted
        int vsz         # virtual memory size in bytes
        int rss         # resident memory size in bytes
        int priv        # private memory size in bytes

    response:
        ROUTER MASTER -> MASTER (NONE): "OK" (CPC_OK)
            hash<ClusterProcInfo> info
*/
const CPC_MR_REGISTER_QSVC = "MR-REGISTER-QSVC";

#! DEALER QSVC (passive) -> MASTER (active): "MR-DO-QSVC-SHUTDOWN": tell the active master that a qsvc process is shutting down
/**
    Payload: none

    response:
        ROUTER QSVC -> MASTER (NONE): "ACK" (CPC_ACK)
*/
const CPC_MR_DO_QSVC_SHUTDOWN = "MR-DO-QSVC-SHUTDOWN";

#! returns the unique process name for the master process on the given node
string sub qmaster_get_process_name(string node) {
    return QDP_NAME_QORUS_MASTER + "-" + node;
}

#! process state constants
const CS_IDLE = 0;
const CS_STARTING = 1;
const CS_RUNNING = 2;
const CS_STOPPING = 3;
const CS_ERR = 4;

#! state codes to strings
const CS_StatusMap = (
    CS_IDLE: "IDLE",
    CS_STARTING: "STARTING",
    CS_RUNNING: "RUNNING",
    CS_STOPPING: "STOPPING",
    CS_ERR: "ERR",
);

#! Qorus startup status strings
const QSS_NORMAL = "NORMAL";
const QSS_RECOVERED = "RECOVERED";
const QSS_ERROR = "ERROR";
const QSS_ALREADY_RUNNING = "ALREADY-RUNNING";
