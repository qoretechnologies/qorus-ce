#!/usr/bin/env qore
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

class ClientProcessBase {
    public {
        # ZeroMQ context
        ZContext zctx;

        # system options
        QorusOptionsBase options();

        # command line options
        hash<auto> opts;

        # connection to the system schema
        Datasource omqds;

        # cluster processes table object
        AbstractTable cluster_processes;

        # hash of local interface addresses
        hash<string, bool> local_addresses;

        #! name of the local node
        string node;

        #! local host name
        string host = gethostname();

        #! process type
        string process_type;

        #! prohibit assume warning flag
        static *bool prohibit_assume_warning;

        # default zmq msg timeout
        const DefaultTimeout = 5s;

        # waiting threads by process type for thread filtering
        const WaitingThreads = {
            "qorus-core": (
                {"function": "Condition::wait", "file": "ConnectionsServer.qc"},
                {"function": "Condition::wait", "file": "QorusEventManager.qc"},
                {"function": "Condition::wait", "file": "AlertManager.qc"},
                {"function": "Condition::wait", "file": "LocalQorusJob.qc"},
                {"function": "Condition::wait", "file": "QorusSharedApi.qc"},
                {"function": "TimedSyncCache::getEvent", "file": "SyncEventManager.qc"},
                {"function": "HttpListener::accept",},
                {"function": "Queue::get", "file": "qorus-shared-system.ql"},
                {"function": "TimedWorkflowCache::getEvent", "file": "SegmentManager.qc"},
                {"function": "SegmentEventQueue::get_primary_event", "file": "WorkflowQueueBase.qc"},
                {"function": "SegmentEventQueue::get_async_event", "file": "WorkflowQueueBase.qc"},
                {"function": "SegmentEventQueue::get_retry_event", "file": "WorkflowQueueBase.qc"},
                {"function": "SegmentEventQueue::get_subworkflow_event", "file": "WorkflowQueueBase.qc"},
                {"function": "SegmentEventQueue::get_workflow_event", "file": "WorkflowQueueBase.qc"},
                {"function": "Socket::isDataAvailable", "file": "HttpServer.qm", "file_regex": True},
                {"function": "Socket::accept", "file": "HttpServer.qm", "file_regex": True},
                {"function": "Queue::get", "file": "WebSocketHandler.qm", "file_regex": True},
                {"function": "get_all_thread_call_stacks", "file": "qorus-svc-core-system.ql"},
                {"function": "get_all_thread_call_stacks", "file": "AbstractQorusClusterApi.qc"},
                {"function": "Queue::get", "file": "QorusMapManager.qc"},
                {"function": "ZSocket::poll", "file": "AbstractQorusDistributedProcess.qc"},
                {"function": "Condition::wait", "file": "QorusProcessManager.qc"},
                {"function": "ZSocket::poll", "file": "qorus-core.q"},
                {"function": "ZSocket::poll", "file": "AbstractQorusClient.qc"},
                {"function": "Queue::get", "file": "qorus-core.q"},
                {"function": "Condition::wait", "file": "WorkflowOrderStats.qc"},
                {"function": "JobSchemaSnapshotManager::runImplementation", "file": "SchemaSnapshots.qc"},
                {"function": "WfSchemaSnapshotManager::runImplementation", "file": "SchemaSnapshots.qc"},
                {"function": "sleep", "file": "SchemaSnapshots.qc"},
                {"function": "ZSocket::send", "file": "AbstractQorusClientProcess.qc"},
                {"function": "Queue::get", "file": "AbstractQorusClientProcess.qc"},
                {"function": "ZSocket::poll", "file": "AbstractQorusClientProcess.qc"},
                {"function": "Condition::wait", "file": "SchemaSnapshots.qc"},
                {"function": "QorusRemoteWebSocketConnection::getIo", "file": "QorusRemoteWebSocketHandler.qc", "all": True},
                {"function": "Socket::accept", "file": "FtpServer.qc"},
                {"function": "Counter::waitForZero", "file": "qorus-core.q"},
                {"function": "Condition::wait", "file": "QorusAuthTokenStore.qc"},
                {"function": "Socket::poll", "regex": "PollingConnectionMonitor.qc$", "file_regex": True},
            ),
            "qorus-master": (
                {"function": "get_all_thread_call_stacks", "file": "AbstractQorusClusterApi.qc"},
                {"function": "Condition::wait", "file": "QorusProcessManager.qc"},
                {"function": "Condition::wait", "file": "QorusSharedApi.qc"},
                {"function": "Queue::get", "file": "qorus.q"},
                {"function": "ZSocket::poll", "file": "AbstractQorusClient.qc"},
                {"function": "Condition::wait", "file": "qorus.q"},
                {"function": "AbstractQorusProcessManager::pollProcessList", "file": "qorus.q"},
                {"function": "ZSocket::send", "file": "AbstractQorusClientProcess.qc"},
                {"function": "Queue::get", "file": "AbstractQorusClientProcess.qc"},
                {"function": "StreamReader::readLine", "file": "PrometheusProcess.qc"},
                {"function": "StreamReader::readLine", "file": "GrafanaProcess.qc"},
            ),
            "qdsp": (
                {"function": "get_all_thread_call_stacks", "file": "AbstractQorusClusterApi.qc"},
                {"function": "Queue::get", "file": "qdsp"},
                {"function": "ZSocket::poll", "file": "AbstractQorusClient.qc"},
                {"function": "ZSocket::send", "file": "AbstractQorusClientProcess.qc"},
                {"function": "Queue::get", "file": "AbstractQorusClientProcess.qc"},
            ),
            "qwf": (
                {"function": "get_all_thread_call_stacks", "file": "AbstractQorusClusterApi.qc"},
                {"function": "TimedWorkflowCache::getEvent", "file": "ClusterSegmentManager.qc"},
                {"function": "SegmentEventQueue::get_primary_event", "file": "WorkflowQueueBase.qc"},
                {"function": "SegmentEventQueue::get_async_event", "file": "WorkflowQueueBase.qc"},
                {"function": "SegmentEventQueue::get_retry_event", "file": "WorkflowQueueBase.qc"},
                {"function": "SegmentEventQueue::get_subworkflow_event", "file": "WorkflowQueueBase.qc"},
                {"function": "SegmentEventQueue::get_workflow_event", "file": "WorkflowQueueBase.qc"},
                {"function": "ZSocket::poll", "file": "AbstractQorusClient.qc"},
                {"function": "Queue::get", "file": "QorusInterfaceProcess.qc"},
                {"function": "ZSocket::send", "file": "AbstractQorusClientProcess.qc"},
                {"function": "Queue::get", "file": "AbstractQorusClientProcess.qc"},
            ),
            "qsvc": (
                {"function": "get_all_thread_call_stacks", "file": "AbstractQorusClusterApi.qc"},
                {"function": "ZSocket::poll", "file": "AbstractQorusClient.qc"},
                {"function": "Queue::get", "file": "QorusInterfaceProcess.qc"},
                {"function": "ZSocket::send", "file": "AbstractQorusClientProcess.qc"},
                {"function": "Queue::get", "file": "AbstractQorusClientProcess.qc"},
                {"function": "Condition::wait", "file": "QorusSharedApi.qc"},
            ),
            "qjob": (
                {"function": "Condition::wait", "file": "LocalQorusJob.qc"},
                {"function": "get_all_thread_call_stacks", "file": "AbstractQorusClusterApi.qc"},
                {"function": "ZSocket::poll", "file": "AbstractQorusClient.qc"},
                {"function": "ZSocket::send", "file": "AbstractQorusClientProcess.qc"},
                {"function": "Queue::get", "file": "AbstractQorusClientProcess.qc"},
            ),
        };

        const StackKeys = ("function", "file");
    }

    constructor(string type) {
        process_type = type;
    }

    bool getDebugSystem() {
        return opts.sysdeb ?? False;
    }

    getLocalAddressesExit(*bool no_assume_warning) {
        getLocalAddresses(True, no_assume_warning);
    }

    string getLocalAddress() {
        getLocalAddresses();
        return local_addresses.firstKey();
    }

    getLocalAddresses(*bool exit_on_err,
            *bool no_assume_warning = ClientProcessBase::prohibit_assume_warning ?? False) {
        if (exists local_addresses) {
            return;
        }

        *hash<auto> node_option = options.get("node");
        if (!node_option) {
            if (exit_on_err && !QorusCommonLib::inContainer() && !no_assume_warning) {
                stderr.printf("WARNING: missing qorus.node option in %y\n",
                    ENV.OMQ_DIR + QorusOptionsBase::EtcOptions);
            }
            node = QorusCommonLib::autoAssignNode(\local_addresses, <AutoAssignNodeOptionInfo>{
                "no_exit_on_error": !exit_on_err,
                "no_assume_warning": no_assume_warning,
            });
            return;
        }

        # make a reverse map from ip addresses to node names
        hash<auto> node_ip_map;
        foreach hash<auto> h in (node_option.pairIterator()) {
            map node_ip_map{$1} = h.key, h.value;
        }

        # get all active IPv4/IPv6 interfaces on the current host
        list<string> l = cast<list<string>>(map $1.address, get_netif_list(),
            $1.address && ($1.family == AF_INET || $1.family == AF_INET6));

        # create a map from node name to configured interfaces
        hash<string, list<string>> node_name_map();
        map node_name_map{node_ip_map{$1}} += ($1,), l, node_ip_map{$1};

        # if no node matches, return
        if (!node_name_map) {
            if (exit_on_err) {
                stderr.printf("WARNING: qorus.node option %y in %y does not match any local addresses\n",
                    node_option, ENV.OMQ_DIR + QorusOptionsBase::EtcOptions);
            }
            node = QorusCommonLib::autoAssignNode(\local_addresses, <AutoAssignNodeOptionInfo>{
                "no_exit_on_error": !exit_on_err,
                "no_assume_warning": no_assume_warning,
            });
            return;
        }

        # if more than one node matches, return
        if (node_name_map.size() > 1) {
            if (exit_on_err) {
                stderr.printf("WARNING: qorus.node option in %y matches multiple nodes: %y\n", ENV.OMQ_DIR
                    + QorusOptionsBase::EtcOptions, node_option{keys node_name_map});
            }
        }

        # get matching node name
        node = node_name_map.firstKey();

        # if some addresses match and some not, return
        if (node_option{node}.lsize() > node_name_map{node}.lsize()) {
            if (exit_on_err) {
                stderr.printf("WARNING: qorus.node option %y in %y for node %y does not match all given addresses\n",
                    node_option, ENV.OMQ_DIR + QorusOptionsBase::EtcOptions, node);
            }

            # get hash of unmatched addresses
            hash<string, bool> all = map {$1: True}, node_option{node};
            node_option{node} = keys all{node_name_map{node}};
            if (exit_on_err) {
                stderr.printf("WARNING: using only: %y as local addresses\n", node_option{node});
            }
        }

        # set local addresses
        map local_addresses{$1} = True, node_option{node};
    }

    # returns False if the process has crashed
    bool checkProcess(hash<auto> row) {
        if (row.pid <= 0) {
            return False;
        }
        # get local addresses to check for aborted processes
        getLocalAddresses(NOTHING, True);

        # is this process on the local node?
        bool local = (node == row.node);

        return (local && !checkPid(row.pid, row.process_type)) ? False : True;
    }

    string showThreadStacks(hash<auto> row, hash<auto> cs, *bool all_threads) {
        string rv;
        string desc = row.process_type == row.process_network_id
            ? row.process_type
            : sprintf("%s %y", row.process_type, row.process_network_id);
        rv += sprintf("%scall stacks for %d thread%s for %s %s:%d (%s):\n",
            all_threads ? "" : "filtered ", cs.size(), cs.size() == 1 ? "" : "s", desc, row.host, row.pid,
            row.queue_urls.split(",")[0]);
        int output = 0;
        # get waiting threads
        *list<auto> wt = WaitingThreads{row.process_type};
        foreach hash<auto> h in (cs.pairIterator()) {
            softint tid = h.key;
            list<auto> stack = h.value;

            if (!all_threads && wt && filterStackEntry(wt, stack)) {
                continue;
            }
            ++output;

            rv += sprintf("TID %d\n", tid);
            int i;
            foreach hash<auto> th in (stack) {
                if (th.type != "new-thread") {
                    rv += sprintf(" %d: %s() called at %s (%s function)\n", ++i, th.function, get_ex_pos(th), th.type);
                } else {
                    rv += sprintf(" %d: *** thread started by background operator ***\n", ++i);
                }
            }
        }

        desc = all_threads ? "do not use -v for a filtered thread list" : "use -v to see an unfiltered thread list";
        if (!output) {
            rv += sprintf("*** all %d threads are idle; %s\n", cs.size(), desc);
        } else {
            rv += sprintf("*** displayed %d/%d threads; %s\n", output, cs.size(), desc);
        }

        return rv;
    }

    static bool checkFilter(hash<auto> ref, hash<auto> entry) {
        foreach string k in (StackKeys) {
            *bool re = ref{k + "_regex"};
            if (ref{k}
                && ((re && !regex(entry{k}, ref{k}))
                    || (!re && ref{k} != entry{k}))) {
                #printf("no match - do not filter entry: %y ref: %y\n", entry, ref);
                return False;
            }
        }
        return True;
    }

    static bool filterStackEntry(list<auto> wt, list<auto> stack) {
        # filter out waiting threads
        foreach softlist<auto> tl in (wt) {
            bool filter = True;
            foreach hash<auto> ref in (tl) {
                if (!ClientProcessBase::checkFilter(ref, stack[$#])) {
                    filter = False;
                    break;
                }
            }
            if (filter) {
                return True;
            }
        }
        return False;
    }

    ZSocketDealer sendCmdSerializedIntern(ZSocketDealer sock, string cmd, *data msgdata, *timeout timeout) {
        if (timeout) {
            sock.setTimeout(timeout);
        }
        sock.send("1", cmd, msgdata);
        return sock;
    }

    # check a response from the master process
    ZMsg checkResponseMsg(string req_cmd, string expected, ZMsg msg) {
        *string cmd = msg.popStr();
        if (exists expected && cmd != expected) {
            if (cmd == CPC_EXCEPTION) {
                hash<auto> ex = qorus_cluster_deserialize(msg).ex;
                throw "CLUSTER-SERVER-ERROR", sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc), ex;
            }
            throw "INVALID-SERVER-RESPONSE", sprintf("request %y: got unexpected reponse %y from server while expecting %y", req_cmd, cmd, expected);
        }
        return msg;
    }

    static bool checkPid(int pid, string process_type) {
        switch (Platform.OS) {
            case "Linux":
            case "SunOS":
            case "FreeBSD":
                # issue #2619: do not show "unreachable" if the process name does not match
                string name = ClientProcessBase::getProcessNameFromType(process_type);
                # do not read the "exe" link, as when the executable is deleted, the link is no longer valid
                # instead read the cmdline to get the original process name
                if (is_dir("/proc/" + pid)) {
                    try {
                        # read the first line of the command line to get the process name
                        InputStreamLineIterator i(new FileInputStream("/proc/" + pid + "/cmdline"));
                        if (!i.next()) {
                            return False;
                        }
                        # if the program has the expected name, then return True
                        return basename(i.getValue()) == name;
                    } catch () {
                        # ignore any exceptions and return False
                    }
                }
                return False;
            case "Darwin":
                return !kill(pid, 0);
            default:
                throw "NOT-IMPLEMENTED", "error";
        }
    }

    static string getProcessNameFromType(string process_type) {
        return process_type == "qorus-master" ? "qorus" : process_type;
    }
}

%ifdef QorusDebugInternals
sub qdbg_assert(bool b) {
    if (!b)
        throw "ASSERT-ERROR", sprintf("stack: %N", get_stack());
}
*list<auto> sub get_stack() {
    if (!HAVE_RUNTIME_THREAD_STACK_TRACE)
        return;
    *list<auto> stack = get_thread_call_stack();
    if (!stack)
        return;
    splice stack, 0, 2;
    return map $1.type != "new-thread" ? sprintf("%s %s()", get_ex_pos($1), $1.function) : "new-thread", stack;
}
# lines with QDBG_* must be on one line
sub QDBG_LOG(code func, string fmt) { call_function_args(func, (LoggerLevel::INFO, fmt, argv)); }
sub QDBG_LOG(string fmt) { vprintf(fmt + "\n", argv); }
sub QDBG_ASSERT(auto v) { qdbg_assert(v.toBool()); }
%endif
