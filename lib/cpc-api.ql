# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

hashdecl ClusterProcInfo {
    #! cluster process ID
    string id;
    #! ZeroMQ queue URL(s) for the process; ref @nothing for external processes
    *list<string> queue_urls;
    #! node name for process
    string node;
    #! hostname for process
    string host;
    #! PID of process on host
    int pid;
    #! in case the active master ID has changed, it is given here (ex: active master handover)
    *string new_active_master_id;
}

/** Message Description Format

    All messages (requests and responses) consist of an initial string frame that is
    generally a command string.  With responses in some cases if the expected response
    command is not received, then the initial frame is treated as an error message
    (ex: the response to CPC_START)

    Messages are described as follows:
    <queue operation> <source> -> <target> (payload): <command>

    Queue operations:
    * DEALER: ZeroMQ request queue request format; frames: sender, mboxid, cmd, ...
    * ROUTER: ZeroMQ response queue response format; frames: sender, mboxid, rcmd, ...

    Where:
    * sender = the sending socket's unique identity
    * mboxid = the sending socket's internal mailbox ID (= TID of the sending thread)
    * cmd = the request API command code - payload format depends on the request
    * rcmd = the response API commannd code - depends on the request

    NOTE: REQ and REP framing is not used as all network I/O should be fully asynchronous
          REQ and REP framing may be used with internal inproc:// queues however

    Nodes:
    * MASTER: a cluster master process, spawns cluster server processes on a node
    * SERVER: a cluster server process, children of a cluster master process

    Payload:
    * NONE: no payload
    * data: Qore serialized payload
    * STRING: plain UTF-8 string

    ex:
    DEALER SERVER -> MASTER (data): "START"

    Describes a request queue request from a server process to the master process with a Qore serialized payload
    and the command is "START".
*/

# the major API level, differences here indicate a break in compatibility
/** 0.1: 4.0 API
    0.2: 4.1 API
    0.3: 4.1.2+ API with working encryption
    1.0: 5.1+ API with stateless services (not supported in the Community Edition)
    1.1: 5.1.4+ API with "MR-BCAST-IFS-DIRECT" and "BCAST_DIRECT"
    1.2: 6.0+ API with "CORE-CALL-STATIC-METHOD"
*/
const CPC_API_LEVEL = "1.2";
# implementation level of the major API; differences here do not indicate a break in compatibility
const CPC_API_SUB = "0";

# commands
# DEALER SERVER -> MASTER (data): "START": server reports queue URL to master
/** Payload:
    - int pid
    - list<string> urls: the server process's queue URLs
    - string api_level: the server process's API level (CPC_API_LEVEL)
    - string api_sub: the server process's API sub level (CPC_API_SUB)

    response:
        ROUTER MASTER -> SERVER (STRING): "OK" | error message
            if not "OK" then the server process will not start and the string sent
            is the error message displayed by the server process
*/
const CPC_START = "START";

# DEALER MASTER -> SERVER (NONE): "STOP": master tells the server to shut down
/** response:
        ROUTER SERVER -> MASTER (NONE): "ACK" (CPC_ACK)
*/
const CPC_STOP = "STOP";

# ROUTER ANY -> ANY (NONE): "ACK": the remote acknowledges a command
const CPC_ACK = "ACK";

# DEALER ANY -> ANY (NONE): "PING": keep-alive message
/** response:
        ROUTER ANY -> ANY (NONE): "PONG"
*/
const CPC_PING = "PING";

# ROUTER ANY -> ANY (NONE): "PONG": keep-alive response
const CPC_PONG = "PONG";

# ROUTER ANY -> ANY (NONE): "UNKNOWN-CMD": unknown command received
const CPC_UNKNOWN_CMD = "UNKNOWN-CMD";

# ROUTER ANY -> ANY (data): "EXCEPTION": an exception occurred
/** Payload:
        hash<ExceptionInfo> ex
*/
const CPC_EXCEPTION = "EXCEPTION";

# DEALER MASTER -> SERVER (data): "PROCESS-ABORT-NOTIFICATION": the master informs server processes immediately that another cluster server process terminated prematurely
/** This notification is sent immediately when a process is aborted before any attempt to restart the process has been made

    Payload:
        string process

    response:
        ROUTER SERVER -> MASTER (NONE): "ACK" (CPC_ACK)
*/
const CPC_PROCESS_ABORT_NOTIFICATION = "PROCESS-ABORT-NOTIFICATION";

# DEALER MASTER -> SERVER (data): "PROCESS-ABORTED": the master informs server processes that another cluster server process terminated prematurely with a restart status
/** This message is sent after the process has been restarted or not; see @ref CPC_PROCESS_ABORT_NOTIFICATION

    Payload:
        string process
        *hash<ClusterProcInfo> info
        bool restarted

    response:
        ROUTER SERVER -> MASTER (NONE): "ACK" (CPC_ACK)
*/
const CPC_PROCESS_ABORTED = "PROCESS-ABORTED";

# ROUTER ANY -> ANY (data): "OK": successful response to a request
/** Payload:
        auto val
*/
const CPC_OK = "OK";

# DEALER ANY -> SERVER (NONE): "GET-INFO": report process info
/** response:
        ROUTER ANY -> SERVER (data): "OK" (CPC_OK)
            Payload:
                string name: the unique network name / id of the process (ex: "qdsp-staging")
                string id: the client ID of the process (ex: "staging")
                string url: the queue URL of the process
                date started: the date/time the process was started
                int threads: the number of Qore threads currently active
                int verbose: the log level
                hash modules: the return value of get_module_hash()
                int vsz: the virtual image size of the process in bytes
                int rss: the resident size of the process in bytes
                int priv: the private memory size of the process in bytes
                + other process-specific keys
*/
const CPC_GET_INFO = "GET-INFO";

# DEALER ANY -> SERVER (NONE): "GET-THREADS": report thread stacks
/** response:
        ROUTER MASTER -> SERVER (data): "OK" (CPC_OK)
            Payload:
                see get_all_thread_call_stacks()
*/
const CPC_GET_THREADS = "GET-THREADS";

# DEALER MASTER -> SERVER (data): "BCAST-SUBSYSTEM": send one-way notification to a remote subsystem as a part of a broadcast msg
/** Payload:
        string subsystem
        string method
        *softlist<auto> args

    response: n/a
*/
const CPC_BCAST_SUBSYSTEM = "BCAST-SUBSYSTEM";

# DEALER MASTER -> SERVER (data): "BCAST-DIRECT": send one-way notification to a remote subsystem as a part of a broadcast msg
/** Payload:
        string method
        *softlist<auto> args

    response: n/a
*/
const CPC_BCAST_DIRECT = "BCAST-DIRECT";

# DEALER MASTER -> SERVER (data): "UPDATE_LOGGER": send one-way notification to a qdsp process to update logger
const CPC_UPDATE_LOGGER = "UPDATE_LOGGER";

# DEALER MASTER -> SERVER (data): "ROTATE_LOGGER": send one-way notification to a qdsp process to rotate log files
const CPC_ROTATE_LOGGER = "ROTATE_LOGGER";

# DEALER ANY -> ANY (data): "KILL-PROC": kill a process on the local node
/** Payload:
        *list<int> pids  # other PIDs to kill
        *int signal
        bool kill_self

    response:
        ROUTER ANY -> ANY (data): "OK" (CPC_OK)
            int rc
            int errno
*/
const CPC_KILL_PROC = "KILL-PROC";

#! the distributed type for prometheus processes
const QDP_NAME_PROMETHEUS = "prometheus";

#! the distributed type for grafana processes
const QDP_NAME_GRAFANA = "grafana-server";

# returns a string that can used as a bind address, substituting the local host name for "0.0.0.0" or "::"
string sub qorus_cluster_get_bind(string local_ip, string bind) {
    if (bind !~ /(0.0.0.0|\[::\])/) {
        return bind;
    }
    # issue #2600: make sure the hostname can be resolved before using it to substitute wildcard binds
    try {
        # substitute hostname for wildcard bind
        return regex_subst(bind, "(0.0.0.0|\\[::\\])", local_ip);
    } catch (hash<ExceptionInfo> ex) {
        if (ex.err != "QOREADDRINFO-GETINFO-ERROR") {
            rethrow;
        }
    }
    # hostname cannot be resolved; return 127.0.0.1
    if (bind =~ /0.0.0.0/) {
        return regex_subst(bind, "0.0.0.0", "127.0.0.1");
    }
    return regex_subst(bind, "\\[::\\]", "\\[::1\\]");
}

# returns a process name with special characters replaced with "_"
string sub qorus_cluster_get_process_name(string name) {
    name =~ s/[^\w-.]/_/ug;
    return name;
}

#! serialization function
data sub qorus_cluster_serialize(auto v) {
    return Serializable::serialize(v);
}

#! deserialization function
auto sub qorus_cluster_deserialize(data d) {
    return Serializable::deserialize(d);
}

#! deserialization function
auto sub qorus_cluster_deserialize(ZMsg msg) {
    return Serializable::deserialize(msg.popBin());
}

#! the distributed server name for qorus master proceses
const QDP_NAME_QORUS_MASTER = "qorus-master";
#! the distributed server name for qorus core processes
const QDP_NAME_QORUS_CORE = "qorus-core";
#! the distributed server name for qorus workflow proceses
const QDP_NAME_QWF = "qwf";
#! the distributed server name for qorus service proceses
const QDP_NAME_QSVC = "qsvc";
#! the distributed server name for qorus job proceses
const QDP_NAME_QJOB = "qjob";
#! the distributed server name for datasource pool processes
const QDP_NAME_QDSP = "qdsp";
