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

#! Hash used when sending process notifications
hashdecl ProcessNotificationInfo {
    #! Response queue
    Queue response_queue;

    #! Process object
    AbstractQorusInternProcess proc;
}

#! Hash used when processes terminate prematurely
hashdecl ProcessTerminationInfo {
    #! Process object
    AbstractQorusProcess proc;

    #! Process restart flag
    bool restart;

    #! Date and time process stopped
    date stop_time = now_us();
}

#! Hash used to get a new node for a process
hashdecl NodeHostInfo {
    #! Node name
    string node;

    #! Host name
    string host;
}

class AbstractQorusProcessManager inherits AbstractQorusClusterApi, AbstractQorusClientProcess {
    public {}

    private {
        # master URLs for each configured interface
        list<string> master_urls;
        Mutex m();

        # network encryption key helper
        NetworkKeyHelper nkh;

        date started = now_us();

        # process hash; name -> process; access wrapped with "m"
        hash<string, AbstractQorusProcess> ph();

        # transition process hash; name -> process; access wrapped with "m"
        hash<string, AbstractQorusProcess> tph();

        # node process map; node name -> process ID -> process
        hash<string, hash<string, AbstractQorusProcess>> node_process_map;

        # ignore abort hash; name -> True; access wrapped with "m"
        /** processes in this hash will not be restarted
            entries are removed when processes are stopped or started normally
        */
        hash<string, bool> ignore_abort_hash;

        #! hash of processes dependent on a key process (qorus-core)
        hash<string, bool> dependent_process_hash;

        # process memory info hash (for change reporting); name -> memory_value -> int
        hash<string, hash> process_memory_info_hash();

        # total private memory for the current node
        int total_private_memory = 0;

        # our local node name
        string node;

        # hash of local interface addresses
        hash<string, bool> local_addresses();

        # total system memory in bytes (note: contants are initialized first in static initialization)
        int machine_ram_total = sysconf(SC_PHYS_PAGES) * AbstractQorusProcessManager::MachinePageSize;

        # issue #2403: system memory in use in bytes
        int machine_ram_in_use = 0;

        # issue #2402: CPU load
        list<float> machine_load_avg = Process::getLoadAvg();

        # issue #2402: CPU load percent over the last 60 seconds; load / CPU count
        float machine_load_pct = 0;

        # number of CPUs
        int machine_cpus = sysconf(SC_NPROCESSORS_ONLN);

        # block process flag
        bool procs_blocked = False;

        #! processes to never kill and always start unconditionally
        hash<string, bool> critical_process_map = DefaultCriticalProcessMap;

        #! independent processes marked aborted; process ID -> info
        hash<string, hash<ProcessTerminationInfo>> independent_aborted_processes;

        # process recovery codes
        const BP_RESTARTED = 0;
        const BP_ALREADY_RESTARTED = 1;
        const BP_RESTART_FAILED = 2;
        const BP_IGNORE_RESTART = 3;

        # process start codes
        const PSC_START = 0;         #!< manual start
        const PSC_RESTART = 1;       #!< manual restart
        const PSC_AUTO_RESTART = 2;  #!< automatic restart

        # process termination notification polling interval
        const DefaultProcessNotificationPollingInterval = 250ms;

        # machine page size in bytes
        const MachinePageSize = sysconf(SC_PAGESIZE);

        #! 5 second timeout to receive an entire message once the first frame has been received
        const NodeMessageTimeout = 5s;

        #! Map of process IDs to always start unconditionally and to never kill
        const DefaultCriticalProcessMap = {
            "qorus-core": True,
            "qdsp-omq": True,
        };
    }

    private:internal {
        Condition stop_cond();
        bool stop_flag = True;

        # monitor thread counter
        Counter monitor_cnt();

        # process transition condition variable
        Condition proc_cond();
        # process transition thread waiting count
        int proc_waiting = 0;

        # routers bound counter
        Counter router_cnt();

        # check processes every second
        const ProcessMonitoringPollingInterval = 1s;

        # check memory footprint every 10s
        /** *NOTE* memory polling is expensive, higher CPU load will result if this value is decreased
        */
        const MemoryInterval = 10;

        # to ensure atomicity of process starts with stops
        hash<auto> process_wait_hash;

%ifdef MEMORY_POLLING
        # refresh process info every 5 seconds
        const ProcessListPollingInterval = 5s;

        # pid -> process info for systems without a proc filesystem
        # and no possibility to query the VM usage of other processes
        # without special priviliges
        hash<string, hash<MemorySummaryInfo>> pih();

        # process list condition variable (wrapped with m)
        Condition plcond();

        # process list monitoring thread run flag
        bool process_list_run = True;

        # process list monitoring thread counter
        Counter plcnt();
%endif
    }

    constructor() {
        initNode();
    }

    destructor() {
        stopCluster();
    }

    NetworkKeyHelper getNetworkKeyHelper() {
        return nkh;
    }

    string getNetworkKeyPath() {
        return nkh.getNetworkKeyPath();
    }

    #! returns the current node name
    string getNodeName() {
        return node;
    }

    #! returns the node name of the active master
    string getActiveMasterNodeName() {
        return node;
    }

    private initNode() {
        initNodeImpl();

        hash<auto> options = getOptions();
        node = QorusMasterCoreQsvcCommon::getNodeInfo(options, \local_addresses);

        # setup encryption
        try {
            nkh = new NetworkKeyHelper(options);

            # check for sensitive data keys; Qorus cannot start if these are not set properly
            NetworkKeyHelper::getKey("sensitive data", options."sensitive-data-key");
            NetworkKeyHelper::getKey("sensitive value", options."sensitive-value-key");
        } catch (hash<ExceptionInfo> ex) {
            stderr.printf("%s: %s\n", ex.err, ex.desc);
            exit(QSE_OPTION_ERROR);
        }
    }

    private getNodeInfo() {
        hash<auto> options = getOptions();

        # see which node applies to this system
        *hash<auto> nh = options.node;
        if (!nh) {
            if (!QorusCommonLib::inContainer()) {
                stderr.printf("WARNING: there is no \"qorus.node\" option in options file %y\n",
                    options."option-file");
                stderr.printf("WARNING: please add a \"qorus.node\" entry manually or by calling "
                    "\"schema-tool -V\"\n");
            }
            node = QorusCommonLib::autoAssignNode(\local_addresses, <AutoAssignNodeOptionInfo>{
                "no_assume_warning": True,
            });
            return;
        }
        # make a reverse map from ip addresses to node names
        hash<auto> nm;
        foreach hash<auto> i in (nh.pairIterator()) {
            map nm{$1} = i.key, i.value;
        }

        # get all active IPv4/IPv6 interfaces on the current host
        list<string> l = cast<list<string>>(map $1.address, get_netif_list(), $1.address
            && ($1.family == AF_INET || $1.family == AF_INET6));

        #printf("DEBUG node: %N\n", nh);
        #printf("DEBUG nm: %N\n", nm);
        #printf("DEBUG l: %y\n", l);
        # create a map from node name to configured interfaces
        hash<string, list<string>> hm();
        map hm{nm{$1}} += ($1,), l, nm{$1};

        # if no node matches, warn and set automatically
        if (!hm) {
            if (!QorusCommonLib::inContainer()) {
                stderr.printf("WARNING: qorus.node option %y in %y does not match local host addresses: %y\n", nh,
                    options."option-file", l);
                stderr.printf("WARNING: please add a \"qorus.node\" entry manually or by calling "
                    "\"schema-tool -V\"\n");
            }
            node = QorusCommonLib::autoAssignNode(\local_addresses, <AutoAssignNodeOptionInfo>{
                "no_assume_warning": True,
            });
            return;
        }

        # if more than one node matches, exit with an error
        if (hm.size() > 1 && !QorusCommonLib::inContainer()) {
            stderr.printf("WARNING: the following qorus.node options in %y match the local host: %y\n",
                options."option-file", keys hm);
            stderr.printf("WARNING: however, only one node may match; please correct the file manually\n");
            stderr.printf("WARNING: using first match: %y\n", hm.firstKey());
        }

        # get matching node name
        node = hm.firstKey();

        #printf("DEBUG node: %y\nnh: %y\nhm: %y\nnm: %y\n", node, nh, hm, nm);

        # if some addresses match and some not, exit with an error
        if (nh{node}.lsize() > hm{node}.lsize()) {
            hash<string, bool> all = map {$1: True}, nh{node};
            hash<string, bool> ah = all - hm{node};
            if (!QorusCommonLib::inContainer()) {
                stderr.printf("WARNING: %y defines qorus.node %y with the following addresses matching the local "
                    "host: %y, but the following expected address%s cannot be matched: %y\n", options."option-file", node,
                    hm{node}, ah.size() == 1 ? "" : "es", keys ah);
            }

            nh{node} = keys all{hm{node}};
            if (!QorusCommonLib::inContainer()) {
                stderr.printf("WARNING: using only: %y as local addresses\n", nh{node});
            }
        }

        # set local addresses
        map local_addresses{$1} = True, nh{node};
    }

    bool startCluster() {
        try {
            # node and local_addresses must be set when the cluster is started
            QDBG_ASSERT(node.val());
            QDBG_ASSERT(!local_addresses.empty());

            stop_flag = False;

            monitor_cnt.inc();
            background monitor();

%ifdef MEMORY_POLLING
            # start process list monitoring thread on MacOS
            plcnt.inc();
            background startProcessListThread();
            QDBG_LOG("started process list thread");
%endif

            router_cnt.inc();
            startMaster();
            # wait for master URL to be set
            router_cnt.waitForZero();
            log(LoggerLevel::INFO, "started cluster master process with queue URLs: %s", getMasterUrlsString());

            if (!startClusterImpl()) {
                stopClusterIntern();
                return False;
            }
            return True;
        } catch (hash<ExceptionInfo> ex) {
            # errors here are otherwise not logged
            logImpl(LoggerLevel::INFO, get_exception_string(ex));
            rethrow;
        }
    }

    # this can only be called once
    stopCluster() {
        if (!stop_flag) {
            stopClusterImpl();
            stopClusterIntern();
            clusterStopped();
        }
    }

    #! starts a process in a remote node
    int startRemoteProcess(AbstractQorusProcess proc) {
        throw "UNIMPLEMENTED";
    }

    blockProcesses() {
        m.lock();
        on_exit m.unlock();

        # wait for all transitional processes to exit the transition state
        while (tph) {
            ++proc_waiting;
            proc_cond.wait(m);
            --proc_waiting;
        }

        procs_blocked = True;
    }

    unblockProcesses() {
        m.lock();
        on_exit m.unlock();

        procs_blocked = False;

        if (proc_waiting)
            proc_cond.broadcast();
    }

    bool addPassiveProcess(AbstractQorusProcess proc, int start_code = PSC_START) {
        string id = proc.getId();
        string proc_node = proc.getNode();
        {
            m.lock();
            on_exit m.unlock();

            waitProcessTransition(id, True);

            tph{id} = proc;
            node_process_map{proc_node}{id} = proc;

            remove ignore_abort_hash{id};
        }

        return startPassiveIntern(proc, start_code);
    }

    int addRestartProcess(AbstractQorusProcess proc) {
        string id = proc.getId();
        string proc_node = proc.getNode();
        {
            m.lock();
            on_exit m.unlock();

            waitProcessTransition(id, True);

            if (ph{id} || tph{id})
                return BP_ALREADY_RESTARTED;

            tph{id} = proc;
            node_process_map{proc_node}{id} = proc;

            remove ignore_abort_hash{id};
            remove dependent_process_hash{id};
        }

        return startIntern(proc, PSC_RESTART) ? BP_RESTARTED : BP_RESTART_FAILED;
    }

    bool addAutoRestartProcess(reference<AbstractQorusProcess> proc) {
        string id = proc.getId();
        string proc_node = proc.getNode();
        {
            m.lock();
            on_exit m.unlock();

            waitProcessTransition(id, True);
            if (*AbstractQorusProcess proc2 = ph{id}) {
                log(LoggerLevel::INFO, "process %y already restarted", id);
                proc = cast<AbstractQorusInternProcess>(proc2);
                return True;
            }

            tph{id} = proc;
            node_process_map{proc_node}{id} = proc;

            remove ignore_abort_hash{id};
        }

        return startIntern(proc, PSC_AUTO_RESTART);
    }

    bool addProcess(AbstractQorusProcess proc, int start_code = PSC_START) {
        string id = proc.getId();
        string proc_node = proc.getNode();
        {
            m.lock();
            on_exit m.unlock();

            QDBG_ASSERT(!ph{id});
            waitProcessTransition(id, True);

            tph{id} = proc;
            node_process_map{proc_node}{id} = proc;

            remove ignore_abort_hash{id};
        }

        return startIntern(proc, start_code);
    }

    bool addDependentProcess(AbstractQorusProcess proc) {
        string id = proc.getId();
        string proc_node = proc.getNode();
        {
            m.lock();
            on_exit m.unlock();

%ifdef QorusDebugInternals
            if (node_process_map{proc_node}{id}) {
                QDBG_LOG("ERROR: existing process replaced: proc_node: %y id: %y", proc_node, id);
            }
%endif
            QDBG_ASSERT(!node_process_map{proc_node}{id});

            waitProcessTransition(id, True);

            tph{id} = proc;
            node_process_map{proc_node}{id} = proc;

            ignore_abort_hash{id} = True;
            dependent_process_hash{id} = True;
        }

        return startIntern(proc, PSC_START);
    }

    updateProcessInfo(string id, hash<auto> info) {
        m.lock();
        on_exit m.unlock();

        *AbstractQorusProcess proc = ph{id} ?? tph{id};
        if (!proc) {
            throw "NO-PROCESS", sprintf("%y: process is not a known process; known processes: %y", id,
                (keys ph + keys tph));
        }
        proc.updateProcessInfo(info);
    }

    private bool startPassiveIntern(AbstractQorusProcess proc, int start_code) {
        # only add process to hash if it can be started
        if (proc.startPassive()) {
            processStartedIntern(proc, start_code);
            return True;
        }
        removeTransitionProcess(proc.getId());
        processStartFailed(proc);
        return False;
    }

    private bool startIntern(AbstractQorusProcess proc, int start_code) {
        # only add process to hash if it can be started
        if (proc.start()) {
            processStartedIntern(proc, start_code);
            return True;
        }
        removeTransitionProcess(proc.getId());
        processStartFailed(proc);
        return False;
    }

    private processStartedIntern(AbstractQorusProcess proc, int start_code) {
        string id = proc.getId();
        {
            m.lock();
            on_exit m.unlock();

            if (ph{id}) QDBG_LOG("ERROR: AbstractQorusProcessManager::startIntern() id: %y exists: %y", id, keys ph);
            QDBG_ASSERT(!ph{id});
            if (!tph{id}) {
                # process already killed and removed
                return;
            }
            QDBG_ASSERT(tph{id});

            # signal any threads waiting on this process to leave the transition state
            if (process_wait_hash{id}.cond) {
                process_wait_hash{id}.cond.broadcast();
            }
            # signal threads waiting on the transition hash to be empty
            if (proc_waiting && tph.empty())
                proc_cond.broadcast();
            # move the process from the transition hash to the process hash
            ph{id} = remove tph{id};

            processStartedInternImpl(proc, start_code);

            # save memory footprint for process
            hash<MemorySummaryInfo> pi = proc.getProcessMemoryInfo();
            #QDBG_LOG("total_private_memory: %d -> %d (%s: old: %d new: %d diff: %d) START", total_private_memory, total_private_memory + (pi.priv - process_memory_info_hash{id}.priv), id, process_memory_info_hash{id}.priv, pi.priv, pi.priv - process_memory_info_hash{id}.priv);
            total_private_memory += pi.priv - process_memory_info_hash{id}.priv;
            process_memory_info_hash{id} = pi + {"pct": (pi.priv * 100.0 / float(machine_ram_total)).toInt()};
        }
        log(LoggerLevel::INFO, "started process %s %y on %s PID %d (%s)", proc.getName(), id, proc.getNode(),
            proc.getPid(), proc.getNetworkDescription());

        processStartedImpl(proc, start_code);
        #log(LoggerLevel::DEBUG, "ph: %y", keys ph);
    }

    # called when a process fails to start
    string processStartFailed(AbstractQorusProcess proc) {
        string err = sprintf("failed to start process %s %y", proc.getName(), proc.getId());
        log(LoggerLevel::INFO, err);
        return err;
    }

    # nust be called in the "m" lock; waits for a process to be removed from the transition hash
    private waitProcessTransition(string id, bool add) {
        while (True) {
            if (tph{id}) {
                if (!process_wait_hash{id}.cond)
                    process_wait_hash{id}.cond = new Condition();
                ++process_wait_hash{id}.count;
                process_wait_hash{id}.cond.wait(m);
                --process_wait_hash{id}.count;
                continue;
            }

            if (add && procs_blocked) {
                ++proc_waiting;
                proc_cond.wait(m);
                --proc_waiting;
                continue;
            }

            break;
        }
        # remove the wait structure if there are no more waiting threads
        if (!process_wait_hash{id}.count)
            delete process_wait_hash{id};
    }

    # removes the process from the running process hash if it exists, in which case it is moved to the temporary process hash
    private *AbstractQorusProcess tryRemoveProcess(string id) {
        *AbstractQorusProcess rv;
        {
            m.lock();
            on_exit m.unlock();

            waitProcessTransition(id, False);

            rv = remove ph{id};
            if (rv) {
                QDBG_ASSERT(!tph{id});
                tph{id} = rv;
                remove ignore_abort_hash{id};
                remove dependent_process_hash{id};
            }
        }
        if (rv) {
            log(LoggerLevel::DEBUG, "removing %y", id);
        } else {
            log(LoggerLevel::DEBUG, "cannot remove unknown process %y; known processes: %y; transitions: %y", id,
                keys ph, keys tph);
        }
        return rv;
    }

    # removes the process from the transition process hash
    private removeTransitionProcess(string id, *bool aborted_externally) {
        AbstractQorusProcess proc;
        {
            m.lock();
            on_exit m.unlock();

            if (!tph{id}) {
                return;
            }

            proc = removeTransitionProcessIntern(id, aborted_externally);
        }
        processRemovedImpl(proc);

        QDBG_LOG("AbstractQorusProcessManager::removeTransitionProcess() removed %y", id);
    }

    # must be called while the "m" lock is held
    private AbstractQorusProcess removeTransitionProcessIntern(string id, *bool aborted_externally) {
        QDBG_ASSERT(tph{id});

        # signal any threads waiting on this process to leave the transition state
        if (process_wait_hash{id}.cond) {
            process_wait_hash{id}.cond.broadcast();
        }

        AbstractQorusProcess proc;
        processRemovedIntern(proc = remove tph{id}, aborted_externally);
        remove ignore_abort_hash{id};
        remove dependent_process_hash{id};

        if (proc_waiting && tph.empty()) {
            proc_cond.broadcast();
        }
        return proc;
    }

    softlist getProcessIds() {
        m.lock();
        on_exit m.unlock();

        return keys ph + keys tph;
    }

    # detaches a cluster server process
    *AbstractQorusProcess detachProcess(string id) {
        *AbstractQorusProcess proc = tryRemoveProcess(id);
        if (proc) {
            proc.detach();
            removeTransitionProcess(id);
        }
        return proc;
    }

    # detaches and kills a cluster server process
    bool detachKillProcess(string id) {
        *AbstractQorusProcess proc = tryRemoveProcess(id);
        if (proc) {
            proc.terminate();
            removeTransitionProcess(id);
            return True;
        }
        return False;
    }

    # stops a cluster server process
    bool stopProcess(AbstractQorusProcess proc) {
        string id = proc.getId();
        bool rv;
        if (tryRemoveProcess(id)) {
            rv = proc.stop();
            removeTransitionProcess(id);
        } else {
            rv = proc.stop();
        }
        return rv;
    }

    # stops a cluster server process
    bool stopProcess(string id) {
        *AbstractQorusProcess proc = tryRemoveProcess(id);
        if (proc) {
            bool res = proc.stop();
            removeTransitionProcess(id);
            return res;
        }
        return False;
    }

    # the process has already been removed from the process hash
    processAborted(string id, hash<ProcessTerminationInfo> info) {
        log(LoggerLevel::INFO, "process %s %y on %s PID %d terminated prematurely; %srestarting", info.proc.getName(),
            id, info.proc.getNode(), info.proc.getPid(), info.restart ? "" : "not ");
        # after this call the Process object is not available
        info.proc.processAborted();

        # issue #2651: send abort notification before trying to restart process
        *hash<string, hash<ProcessNotificationInfo>> proc_map = notifyAbortedProcessAllInitial(id, NOTHING,
            info.stop_time);

        # call processAbortedRestartImpl() before restarting the process
        hash<auto> ctx;
        bool new_restart = processAbortedRestartImpl(id, info.proc, info.restart, \ctx);
        if (new_restart != info.restart) {
            log(LoggerLevel::INFO, "restart status for process %y changed to %y", id, new_restart);
            info.restart = new_restart;
        }

        # FIXME: handle the situation when the cluster server process keeps aborting repeatedly
        # i.e.: add a progressive delay to respawns

        # restart process before notifying other cluster server processes
        if (info.restart) {
            try {
                info.proc.setRestarting();
            } catch (hash<ExceptionInfo> ex) {
                log(LoggerLevel::INFO, "failed to restart process %y: %s: %s", id, ex.err, ex.desc);
                info.restart = False;
            }
        }
        if (info.restart && !addAutoRestartProcess(\info.proc)) {
            log(LoggerLevel::INFO, "failed to add restarted process %y; not restarting", id);
            info.restart = False;
        }

        *hash<ClusterProcInfo> proc_info = info.restart ? info.proc.getClusterProcInfo() : NOTHING;

        # notify all processes of the aborted process
        notifyAbortedProcessAll(proc_map, id, proc_info, info.restart, info.stop_time);

        # call processAbortedImpl() after potentially restarting the process
        processAbortedImpl(id, info.proc, info.restart, ctx);
    }

    #! returns the node for starting a process
    hash<NodeHostInfo> getNodeForNewProcess(string id) {
        return <NodeHostInfo>{
            "node": node,
            "host": gethostname(),
        };
    }

    #! reimplement in child classes to support passive nodes
    stopProcessInPassiveMaster(AbstractQorusProcess proc) {
        throw "UNSUPPORTED";
    }

    # issue #2651: send abort notification before trying to restart process
    hash<string, hash<ProcessNotificationInfo>> notifyAbortedProcessAllInitial(string id, *hash<string, bool> ex,
            date abort_timestamp) {
        # map from process ID to notification info
        hash<string, hash<ProcessNotificationInfo>> msg_info();

        QDBG_LOG("AbstractQorusProcessManager::notifyAbortedProcessAllInitial() id: %y ex: %y", id, ex);
        {
            m.lock();
            on_exit m.unlock();

            # do not wait for responses here, as the process being notified also may die during the notification
            map sendNotifyAbortedProcessInitial($1, id, \msg_info),
                ph.iterator(),
                $1.needsSendNotifyAbortedProcessInitial() && $1.getId() != id && (!ex || !ex{$1.getId()})
                    && $1 instanceof AbstractQorusInternProcess
                    && $1.checkStartTimeBefore(abort_timestamp);
            map sendNotifyAbortedProcessInitial($1, id, \msg_info),
                tph.iterator(),
                $1.needsSendNotifyAbortedProcessInitial() && $1.getId() != id && (!ex || !ex{$1.getId()})
                    && $1.getUrls() && $1 instanceof AbstractQorusInternProcess;
        }

        if (msg_info) {
            waitForResponses(CPC_PROCESS_ABORT_NOTIFICATION, \msg_info);
        }

        QDBG_LOG("AbstractQorusProcessManager::notifyAbortedProcessAllInitial() done");
        return msg_info;
    }

    # notify all processes of the aborted process
    /** the processing here is complex to ensure that
        - all processes are notified deterministically of a crashed process
        - any other process that terminates prematurely during this notification does not block the monitor thread

        To do this, we send the notification messages and then poll for ACKs, removing any polling entries for
        processes that crash during the notification polling action

        @param proc_map the map of processes the original notification was sent to; if not given then the second
        notification is sent to all processes
        @param id the ID of the aborted process
        @param urls the new URLs of the process (if it's been restarted)
        @param restart the restart flag
        @param ex a hash of process IDs to exclude from notifications
        @param notify_passive_masters also notify passive masters
    */
    notifyAbortedProcessAll(*hash<string, hash<ProcessNotificationInfo>> proc_map, string id,
            *hash<ClusterProcInfo> info, bool restart, date abort_timestamp, *hash<string, bool> ex,
            *bool notify_passive_masters) {
        # unconditionally notify local clients of updated process info
        if (restart) {
            setUrls(info, abort_timestamp);
        }
        abortedProcessNotification(id, info, restart, abort_timestamp);

        # map from process ID to notification info
        hash<string, hash<ProcessNotificationInfo>> msg_info;

        int notify_count;
        {
            m.lock();
            on_exit m.unlock();

            # do not wait for responses here, as the process being notified also may die during the notification
            notify_count += (map sendNotifyAbortedProcess($1, id, info, restart, abort_timestamp, \msg_info),
                ph.iterator(),
                (!exists proc_map || proc_map{$1.getId()} || $1.needsSendNotifyRestartProcess())
                    && $1.getId() != id && (!ex || !ex{$1.getId()}) && $1 instanceof AbstractQorusInternProcess
                    && $1.checkStartTimeBefore(abort_timestamp)
                    && (notify_passive_masters || !($1 instanceof QorusPassiveMasterProcess))).size();
            notify_count += (map sendNotifyAbortedProcess($1, id, info, restart, abort_timestamp, \msg_info),
                tph.iterator(),
                (!exists proc_map || proc_map{$1.getId()} || $1.needsSendNotifyRestartProcess())
                    && $1.getId() != id && (!ex || !ex{$1.getId()}) && $1 instanceof AbstractQorusInternProcess
                    && $1.checkStartTimeBefore(abort_timestamp)
                    && (notify_passive_masters || !($1 instanceof QorusPassiveMasterProcess)) && $1.getUrls()).size();

            log(LoggerLevel::INFO, "processes notified of %srestarted process %y: %d", restart ? "" : "not ", id,
                notify_count);
        }

        if (msg_info) {
            waitForResponses(CPC_PROCESS_ABORTED, \msg_info);
        }
    }

    private waitForResponses(string cmd, reference<hash<string, hash<ProcessNotificationInfo>>> msg_info) {
        # poll for ACKs here outside the lock; if a process terminates, remove the socket from the polling list
%ifdef QorusDebugInternals
        date start = now_us();
%endif
        while (msg_info) {
            try {
                # FIXME: implement a polling API for multiple queues
                foreach hash<auto> i in (msg_info.pairIterator()) {
                    AbstractQorusInternProcess proc = i.value.proc;
                    if (!i.value.response_queue.empty()) {
                        processNotificationResponse(cmd, i.key, proc.getClient(), i.value.response_queue);
                        remove msg_info{i.key};
                        continue;
                    }

                    # check for terminated local processes
                    if (!proc.running()) {
                        log(LoggerLevel::INFO, "process %y died in process aborted notification", proc.getId());
                        # issue #3518: cancel async message
                        proc.getClient().cancelAsyncCmd();
                        remove msg_info{i.key};
                    }
%ifdef QorusDebugInternals
                    else {
                        if ((now_us() - start) > 2s) {
                            # issue #2918: a process that does not die and does not respond to the terminated message will
                            # cause the master process to block
                            QDBG_LOG("process %y still has not responded", proc.getId());
                        }
                    }
%endif
                }

                # FIXME: do not use sleep here
                if (msg_info) {
                    usleep(DefaultProcessNotificationPollingInterval);
                }
            } catch (hash<ExceptionInfo> ex) {
                log(LoggerLevel::INFO, "error receiving process aborted notification acknowledgement: %s: %s", ex.err, ex.desc);
            }
        }
    }

    private processNotificationResponse(string cmd, string id, AbstractQorusClient client, Queue response_queue) {
        try {
            client.checkAsyncResponseMsg(response_queue, cmd, CPC_ACK, NodeMessageTimeout);
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::INFO, "process %y: error retrieving response to %y msg: %s", id, cmd, get_exception_string(ex));
        }
    }

    private static sendNotifyAbortedProcessInitial(AbstractQorusInternProcess proc, string id,
            reference<hash<string, hash<ProcessNotificationInfo>>> msg_info) {
        msg_info{proc.getId()} = <ProcessNotificationInfo>{
            "response_queue": proc.sendNotifyAbortedProcessInitial(id),
            "proc": proc,
        };
    }

    private static bool sendNotifyAbortedProcess(AbstractQorusInternProcess proc, string id,
            *hash<ClusterProcInfo> info, bool restart, date abort_timestamp,
            reference<hash<string, hash<ProcessNotificationInfo>>> msg_info) {
        msg_info{proc.getId()} = <ProcessNotificationInfo>{
            "response_queue": proc.sendNotifyAbortedProcess(id, info, restart, abort_timestamp),
            "proc": proc,
        };
        return True;
    }

    hash<auto> getOptions() {
        return getOptionsImpl();
    }

    string getLogDir() {
        return getOptionImpl("logdir");
    }

    string getMasterUrlsString() {
        return master_urls.join(",");
    }

    string getActiveMasterUrlsString() {
        return master_urls.join(",");
    }

    string getInterfacesString() {
        return (keys local_addresses).join(",");
    }

    private list<object<ZSocketRouter>> createRouters(reference<list<hash<ZmqPollInfo>>> poll_list) {
        # list of ZSocketRouter objects for all interfaces
        list<ZSocketRouter> rl();

        # bind all interfaces on a wildcard address
        foreach string addr in (keys local_addresses) {
            # create master API socket; default timeout OK because we use polling
            MyRouter router(zctx, "master-" + addr, "tcp://" + addr + ":*", $#, nkh);
            rl += router;
            master_urls += addr == "*" ? qorus_cluster_get_bind(local_addresses.firstKey(), router.endpoint()) : router.endpoint();

            poll_list += new hash<ZmqPollInfo>((
                "socket": router,
                "events": ZMQ_POLLIN,
            ));
        }

        router_cnt.dec();

        return rl;
    }

    private startMaster() {
        QDBG_ASSERT(!local_addresses.empty());
        startEventThread();
    }

    handleRouterMsg(ZSocketRouter zsocket_router) {
        MyRouter router = cast<MyRouter>(zsocket_router);
        ZMsg msg = router.recvMsg();
        string sender;
        string mboxid;
        string key;
        try {
            # pop the sender's identity from the msg
            sender = msg.popStr();
            # pop the sender's mailbox ID from the msg
            mboxid = msg.popStr();
            # get source process (or common API command)
            key = msg.popStr();
        } catch (hash<ExceptionInfo> ex) {
            error("exception handling msg from sender: %y TID %y: %s: %s: %s", sender, mboxid, get_ex_pos(ex), ex.err, ex.desc);
            router.send(sender, mboxid, CPC_EXCEPTION, qorus_cluster_serialize({"ex": ex}));
            return;
        }
        QDBG_LOG("got msg from sender: %y %y key/cmd: %y", sender, mboxid, key);
        # process common cluster API messages
        if (processMsg(router, sender, mboxid, key, msg)) {
            return;
        }

        # get command / arg
        data cmd;
        try {
            cmd = msg.popBin();
        } catch (hash<ExceptionInfo> ex) {
            error("exception handling msg from sender: %y TID %y key: %y: %s: %s: %s", sender, mboxid, key, get_ex_pos(ex), ex.err, ex.desc);
            router.send(sender, mboxid, CPC_EXCEPTION, qorus_cluster_serialize({"ex": ex}));
            return;
        }

        if (key == "self") {
            cmd = cmd.toString();
            log(LoggerLevel::TRACE, "got msg from sender: %y %y (%y) cmd: %y (ph: %y tph: %y)", sender, mboxid, key, cmd, keys ph, keys tph);
            processSelfMsg(router, router.index, sender, mboxid, cmd, msg);
            return;
        }

        # match message to a registered process
        *AbstractQorusProcess proc;
        {
            m.lock();
            on_exit m.unlock();

            proc = tph{key} ?? ph{key};
        }
        cmd = cmd.toString();
        if (proc && (cmd != CPC_MR_REGISTER_QSVC)) {
            log(LoggerLevel::TRACE, "got msg from sender: %y %y (%y) cmd: %y proc: %y (ph: %y tph: %y)", sender,
                mboxid, key, cmd, proc.getId(), keys ph, keys tph);
            if (processMasterMsg(proc, router, router.index, sender, mboxid, cmd, msg)) {
                return;
            }
            if (!proc.processMsg(router, sender, mboxid, cmd, msg)) {
                try {
                    throw "MESSAGE-IGNORED", sprintf("proc %y ignored msg %y from sender %y mboxid %y", proc.getId(),
                        cmd, sender, mboxid);
                } catch (hash<ExceptionInfo> ex) {
                    error("%s: %s", ex.err, ex.desc);
                    router.send(sender, mboxid, CPC_EXCEPTION, qorus_cluster_serialize({"ex": ex}));
                }
            }
        } else {
            handleUnknownSender(router, msg, sender, mboxid, key, cmd);
        }
    }

    # called when a message from an unknown sender arrives
    private handleUnknownSender(ZSocketRouter router, ZMsg msg, string sender, string mboxid, string key, data cmd) {
        auto cmd_arg;
        try {
            # try to decode cmd
            cmd_arg = qorus_cluster_deserialize(cmd);
        } catch () {
            cmd_arg = cmd;
        }
        handleMsgFromUnknownSender(router, msg, sender, mboxid, key, cmd_arg);
    }

    # called when a message from an unknown sender arrives
    private handleMsgFromUnknownSender(ZSocketRouter router, ZMsg msg, string sender, string mboxid, string key, auto cmd_arg) {
        log(LoggerLevel::TRACE, "got msg from sender: %y %y (%y) cmd: %y (ph: %y tph: %y)", sender, mboxid, key, cmd_arg,
            keys ph, keys tph);
        list<string> tl = ();
        while (True) {
            *string str = msg.popStr();
            if (!str.val())
                break;
            tl += str;
        }
        string errmsg = sprintf("ignoring message from unknown sender %y key: %y cmd: %y (%y); known senders: %y + "
            "%y", sender, key, cmd_arg, tl, keys tph, keys ph);
        log(LoggerLevel::INFO, errmsg);
        try {
            throw "PROCESS-ERROR", errmsg;
        } catch (hash<ExceptionInfo> ex) {
            # send exception to sender
            router.send(sender, mboxid, CPC_EXCEPTION, qorus_cluster_serialize({"ex": ex}));
        }
    }

    # called when a message is received from a new master process
    private processSelfMsg(ZSocketRouter router, int index, string sender, string mboxid, string cmd, ZMsg msg) {
        processSelfMsgImpl(router, index, sender, mboxid, cmd, msg);
    }

    private ignoreProcessAbort(int index, string sender, string mboxid, hash<auto> h) {
        ignoreProcessAbortIntern(h);
        sendResponse(index, sender, mboxid, CPC_ACK);
    }

    private ignoreProcessAbortIntern(hash<auto> h) {
        m.lock();
        on_exit m.unlock();
        ignore_abort_hash{h.name} = True;
    }

    private bool processMasterMsg(AbstractQorusProcess proc, ZSocketRouter router, int index, string sender,
            string mboxid, string cmd, ZMsg msg) {
        # process master API messages
        switch (cmd) {
            case CPC_MR_GET_PROCESS_INFO: {
                string pname = msg.popStr();
                return getClusterProcessInfo(router, index, sender, mboxid, pname);
            }

            case CPC_MR_IGNORE_PROCESS_ABORT: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: setting flag to ignore process %s abort%s", sender, mboxid, h.name,
                    h.reason ? sprintf(" reason: %s", h.reason) : NOTHING);
                background ignoreProcessAbort(index, sender, mboxid, h);
                return True;
            }
        }
        return False;
    }

    private bool getClusterProcessInfo(ZSocketRouter router, int index, string sender, string mboxid, string pname) {
        *hash<auto> h = getClusterProcessInfoIntern(pname);
        router.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(h));
        return True;
    }

    private *hash<auto> getClusterProcessInfoIntern(string pname) {
        *AbstractQorusProcess oproc;
        {
            m.lock();
            on_exit m.unlock();

            oproc = tph{pname} ?? ph{pname};
        }
        if (oproc)
            return oproc.getInfo();
    }

    private *hash<auto> getClusterProcInfoFromName(string pname) {
        m.lock();
        on_exit m.unlock();

        if (*AbstractQorusProcess oproc = tph{pname} ?? ph{pname}) {
            return oproc.getClusterProcInfo();
        }
    }

    #! Called when shutting down the cluster and all processes have been stopped
    private processesStopped() {
        # this method intentionally left empty
    }

    private:internal stopClusterIntern() {
        blockProcesses();
        on_exit unblockProcesses();

        hash<string, AbstractQorusProcess> sph();
        {
            m.lock();
            on_exit m.unlock();

            # first stop all processes and remove them from the process hash
            if (ph) {
                sph = ph;
                tph += sph;
                delete ph;
            }
        }

        log(LoggerLevel::DEBUG, "stopping processes: %y", keys tph);

        # stop processes outside the lock
        map $1.stop(), sph.iterator();

        # remove from transition hash, call removal notification method, stop the process monitoring thread
        {
            m.lock();
            on_exit m.unlock();

            tph -= keys sph;
            map processRemovedIntern($1), sph.iterator();

            # now stop the process monitoring thread
            QDBG_ASSERT(!stop_flag);
            QDBG_ASSERT(!ph);
            stop_flag = True;
            stop_cond.signal();

            # unblock processes to shut down if necessary
            if (procs_blocked) {
                procs_blocked = False;

                if (proc_waiting) {
                    proc_cond.broadcast();
                }
            }
        }

        map processRemovedImpl($1), sph.iterator();

        processesStopped();

        # wait for process monitoring thread to terminate
        monitor_cnt.waitForZero();

        # now stop the master event and I/O threads
        stopEventThread();

%ifdef MEMORY_POLLING
        # stop process list monitoring thread
        {
            m.lock();
            on_exit m.unlock();
            QDBG_LOG("stopping the process list thread");
            process_list_run = False;
            plcond.signal();
        }
        plcnt.waitForZero();
%endif
    }

%ifdef MEMORY_POLLING
    private:internal startProcessListThread() {
        QDBG_LOG("in process list thread");
        on_exit {
            plcnt.dec();
            QDBG_LOG("stopped process list thread");
        }

        while (process_list_run) {
            # get set of PIDs to monitor
            hash<string, bool> mph;
            {
                m.lock();
                on_exit m.unlock();

                map mph{$1.getPid()} = True, ph.iterator(), $1.getNode() == node;
                map mph{$1.getPid()} = True, tph.iterator(), $1.getNode() == node;
            }

            # remove nonexistent process
            remove mph."-1";

            if (mph) {
                pollProcessList(mph);
            } else {
                # interruptable sleep
                m.lock();
                on_exit m.unlock();

                QorusSharedApi::waitCondition(plcond, m, ProcessListPollingInterval);
            }
        }
    }

    hash<MemorySummaryInfo> getProcessMemoryInfo(softstring pid) {
        return pih{pid} ?? new hash<MemorySummaryInfo>();
    }
%endif

%ifdef LINUX
    private:internal pollProcessList(hash<string, bool> mph) {
        # PID -> process info
        hash<string, hash<MemorySummaryInfo>> tmp_pih();

        # measure how long this loop takes to calculate the sleep delay below
        date start = now_us();
        foreach string pid in (keys mph) {
            try {
                tmp_pih{pid} = Process::getMemorySummaryInfo(pid.toInt());
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err != "PROCESS-GETMEMORYINFO-ERROR") {
                    log(LoggerLevel::INFO, "failed to get process ino for PID %d: %s: %s", pid, ex.err, ex.err);
                }
            }
            # exit immediately if we are shutting down
            if (!process_list_run) {
                return;
            }
        }

        # get the duration in ms
        int delta_ms = (now_us() - start).durationMilliseconds();

        # update process info
        pih = tmp_pih;

        # calculate process info polling interval based on the time it took to read the process data
        # sleep at least 10 seconds, or three times the time it took to calculate the PSS sizes for all processes,
        # whichever is greater
        int process_list_polling_interval_ms = max(delta_ms * 3, 10000);

        # interruptable sleep
        {
            m.lock();
            on_exit m.unlock();

            QorusSharedApi::waitCondition(plcond, m, process_list_polling_interval_ms);
        }
    }
%endif

%ifdef DARWIN
    private:internal static int getBytes(string str) {
        str =~ s/\+$//;
        switch (str[-1]) {
            case "B": return str.toInt();
            case "K": return str.toInt() * 1024;
            case "M": return str.toInt() * 1024 * 1024;
            case "G": return str.toInt() * 1024 * 1024 * 1024;
            case "T": return str.toInt() * 1024 * 1024 * 1024 * 1024;
            case "E": return str.toInt() * 1024 * 1024 * 1024 * 1024 * 1024;
            default: throw "GETBYTES-ERROR", sprintf("unknown value: %y", str);
        }
    }

    private:internal pollProcessList(hash<string, bool> mph) {
        # PID -> process info
        hash<string, hash<MemorySummaryInfo>> tmp_pih();

        if (mph) {
            # we cannot get vm memory maps with root privileges or signed binaries on Darwin
            # that are allowed to call task_for_pid(), so we use top (suid bin) and parse its
            # output - low tech, but works on Darwin
            string cmd = "top -l 1 -r -stats pid,vsize,vprvt,rprvt";
            bool in_proc;
            DataLineIterator i(backquote(cmd));
            while (i.next()) {
                string line = i.getValue();
                if (!in_proc) {
                    if (line =~ /^PID/) {
                        in_proc = True;
                    }
                    continue;
                }
                # collapse multiple spaces to a single space
                line =~ s/ +/ /g;
                list<string> ll = line.split(" ");
                # ll offsets: 0=PID, 1=VSZ, 2=PRIV, 3=RSS
                if (!mph{ll[0]}) {
                    continue;
                }

                tmp_pih{ll[0]} = <MemorySummaryInfo>{
                    "vsz": getBytes(ll[1]),
                    "rss": getBytes(ll[3]),
                    "priv": getBytes(ll[2]),
                };
                #if (pih != tmp_pih) QDBG_LOG("new pih: %N", tmp_pih);
            }
        }

        # on Darwin we have to use vm_stat :(
        machine_ram_in_use = (sysconf(SC_PHYS_PAGES) - (`vm_stat` =~ x/Pages free:\s+([0-9]+)/m)[0].toInt()) * MachinePageSize;

        # update process info
        pih = tmp_pih;

        # interruptable sleep
        {
            m.lock();
            on_exit m.unlock();

            QorusSharedApi::waitCondition(plcond, m, ProcessListPollingInterval);
        }
    }
%endif

    private waitBlockedProcessesIntern() {
        while (procs_blocked) {
            ++proc_waiting;
            proc_cond.wait(m);
            --proc_waiting;
        }
    }

    private *AbstractQorusInternProcess markIndependentProcessAborted(string id) {
        *AbstractQorusInternProcess proc = cast<*AbstractQorusInternProcess>(tryRemoveProcess(id));
        if (!proc) {
            QDBG_LOG("AbstractQorusProcessManager::markIndependentProcessAborted() process %y not removed; ignoring",
                id);
            return;
        }
        proc.markDead();
        # the process is added to the independent_aborted_processes map in processRemovedInternImpl()
        removeTransitionProcess(id, True);

        # mark process aborted internally
        invalidateUrls(id, now_us());
    }

    private:internal monitor() {
        on_exit {
            log(LoggerLevel::INFO, "process monitor thread exiting");
            monitor_cnt.dec();
        }

        try {
            # get max process memory percent option
            int mpmp = getOptions()."max-process-memory-percent";

            log(LoggerLevel::INFO, "monitoring processes on node %y with total physical system memory: %s; max process memory: "
                "%02d%%", node, get_byte_size(machine_ram_total), mpmp);

            int mem_count = 0;

            while (True) {
                # aborted process hash: name -> {AbstractQorusProcess proc, bool restart}
                hash<string, hash<ProcessTerminationInfo>> aborted_hash;

                hash<MemorySummaryInfo> pi;
                # only perform memory operations in iterations when memory is polled
                if (++mem_count == MemoryInterval) {
                    mem_count = 0;
                    pi = getMachineAndProcessMemory();
                }

                {
                    m.lock();
                    on_exit m.unlock();

                    waitBlockedProcessesIntern();

                    # only perform memory operations in iterations when memory is polled
                    if (pi) {
                        # add this process's private memory to the node's total
                        #QDBG_LOG("total_private_memory: %d -> %d (%s: old: %d new: %d diff: %d) MON", total_private_memory, total_private_memory + (pi.priv - process_memory_info_hash{QDP_NAME_QORUS_MASTER}.priv), QDP_NAME_QORUS_MASTER, process_memory_info_hash{QDP_NAME_QORUS_MASTER}.priv, pi.priv, pi.priv - process_memory_info_hash{QDP_NAME_QORUS_MASTER}.priv);
                        total_private_memory += pi.priv - process_memory_info_hash{QDP_NAME_QORUS_MASTER}.priv;
                        process_memory_info_hash{QDP_NAME_QORUS_MASTER} =
                            pi + {"pct": (pi.priv * 100.0 / float(machine_ram_total)).toInt()};
                    }

                    # sleep for polling period
                    QorusSharedApi::waitCondition(stop_cond, m, ProcessMonitoringPollingInterval);

                    # remove non-running processes from the process hash and set the restart flag
                    map removeAbortedProcess($1.key, \aborted_hash), ph.pairIterator(),
                        $1.value.getNode() == node && !$1.value.running();

                    # add independent processes marked aborted
                    aborted_hash += remove independent_aborted_processes;

                    # only perform memory operations in iterations when memory is polled
                    if (pi) {
                        checkProcessMemoryIntern(mpmp, \aborted_hash);
                    }
                }

                if (aborted_hash) {
                    log(LoggerLevel::INFO, "the following processes died: %y", keys aborted_hash);
                    # handle aborted processes
                    handleAbortedProcesses(aborted_hash);
                }

                if (stop_flag) {
                    break;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::INFO, "error in monitor thread: %s", get_exception_string(ex));
        }
    }

    private hash<MemorySummaryInfo> getMachineAndProcessMemory() {
        # total system memory in bytes (in case it changes while running; hotplugging RAM
        # is possible on some VMs at least)
        int current_mem = sysconf(SC_PHYS_PAGES) * MachinePageSize;
        if (current_mem != machine_ram_total) {
            log(LoggerLevel::INFO, "total physical system memory changed from %s to %s",
                get_byte_size(machine_ram_total), get_byte_size(current_mem));
            machine_ram_total = current_mem;
        }

        # check for changed CPU count
        int current_cpus = sysconf(SC_NPROCESSORS_ONLN);
        if (current_cpus != machine_cpus) {
            log(LoggerLevel::INFO, "total CPUs changed from %s to %s", machine_cpus, current_cpus);
            machine_cpus = current_cpus;
        }

%ifndef DARWIN
        # issue #2403: get RAM in use; API not supported on Darwin
        # on Darwin we have to use top and vm_stat :(
        machine_ram_in_use = current_mem - (sysconf(SC_AVPHYS_PAGES) * MachinePageSize);
%endif
        # issue #2402: get load average
        machine_load_avg = Process::getLoadAvg();
        machine_load_pct = machine_load_avg[0] / machine_cpus * 100.0;
        return Process::getMemorySummaryInfo();
    }

    private removeAbortedProcess(string id, reference<hash<string, hash<ProcessTerminationInfo>>> aborted_hash, *bool do_not_restart) {
        AbstractQorusProcess proc = remove ph{id};
        QDBG_ASSERT(id == proc.getId());
        bool restart = !(remove ignore_abort_hash{id});
        if (restart && do_not_restart) {
            restart = False;
        }
        if (restart) {
            restart = proc.restartProcess();
        }
        aborted_hash{id} = <ProcessTerminationInfo>{
            "proc": proc,
            "restart": restart,
        };
        remove dependent_process_hash{id};

        # allow custom processing per removed process within the lock
        processRemovedIntern(proc);
    }

    private handleAbortedProcesses(hash<string, hash<ProcessTerminationInfo>> aborted_hash) {
        # allow custom processing per removed process outside the lock
        map processRemovedImpl($1.proc), aborted_hash.iterator();

        try {
            # process aborted processes
            map processAborted($1.key, $1.value), aborted_hash.pairIterator();
        } catch (hash<ExceptionInfo> ex) {
            log(LoggerLevel::INFO, "%s", get_exception_string(ex));
        }
    }

    restart(AbstractQorusProcess p) {
        p.terminate();
    }

    # called when a process's memory footprint changes
    processMemoryUpdated(string id, hash<auto> h) {
    }

    # called with the main Mutex held
    private checkProcessMemoryIntern(int mpmp, reference<hash<string, hash<ProcessTerminationInfo>>> aborted_hash) {
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

    # called when the cluster has been stopped
    private clusterStopped() {
    }

    logCmd(int ll, string fmt) {
        logImpl(ll, vsprintf(fmt, argv));
    }

    errorCmd(string fmt) {
        error("%s", vsprintf(fmt, argv));
    }

    stopServer() {
        log(LoggerLevel::INFO, "received STOP; ignoring");
    }

    hash<auto> getRuntimeProps() {
        return getRuntimePropsImpl();
    }

    #! log with varargs
    abstract logArgs(int lvl, string msg, auto args);

    # called in the process lock when a process is removed from the process map; reimplement in subclasses to remove from process-specific type maps
    private processRemovedIntern(AbstractQorusProcess proc, *bool aborted_externally) {
        string id = proc.getId();
        # adjust total private memory sum for the node
        #QDBG_LOG("total_private_memory: %d -> %d (%s: old: %d diff: %d) STOP", total_private_memory, total_private_memory - process_memory_info_hash{id}.priv, id, process_memory_info_hash{id}.priv, -process_memory_info_hash{id}.priv);
        total_private_memory -= process_memory_info_hash{id}.priv;
        # remove memory footprint info
        remove process_memory_info_hash{id};
        QDBG_ASSERT(node_process_map{proc.getNode()});
        # remove from node map
        remove node_process_map{proc.getNode()}{id};
        if (!node_process_map{proc.getNode()}) {
            removeNodeIntern(proc.getNode());
        }
        # call implementation-specific removal method
        processRemovedInternImpl(proc, aborted_externally);
    }

    #! Called in the process lock when a node is removed
    private removeNodeIntern(string node_id) {
        log(LoggerLevel::INFO, "node %y is down; removing", node_id);
        remove node_process_map{node_id};
    }

    # called in the process lock when a process is started and added to the process map; reimplement in subclasses to add to process-specific type maps
    private processStartedInternImpl(AbstractQorusProcess proc, int start_code) {
    }

    # called outside the process lock when a process is started and added to the process map
    private processStartedImpl(AbstractQorusProcess proc, int start_code) {
    }

    # called from the network API when a process has aborted
    private processAbortedImpl(string process, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        # ignore message
    }

    # called in the process lock when a process is removed from the process map; reimplement in subclasses to remove from process-specific type maps
    private processRemovedInternImpl(AbstractQorusProcess proc, *bool aborted_externally) {
    }

    # called outside the process lock when a process is removed from the process map
    private processRemovedImpl(AbstractQorusProcess proc) {
    }

    # to get any runtimeProperties, if any
    private abstract hash<auto> getRuntimePropsImpl();

    # called in the constructor before getNodeInfo(); getOption() must be callable after this call
    private abstract initNodeImpl();
    private abstract bool startClusterImpl();
    private abstract stopClusterImpl();
    # called before the cluster server process is potentially restarted
    private abstract bool processAbortedRestartImpl(string id, AbstractQorusProcess proc, bool restart,
        reference<hash> ctx);
    # called after the cluster server process has been potentially restarted
    private abstract processAbortedImpl(string id, AbstractQorusProcess proc, bool restart, *hash<auto> ctx);
    # return all Qorus options
    private abstract hash<auto> getOptionsImpl();
    # return the value of a single Qorus option
    private abstract auto getOptionImpl(string opt);
    # called when a message is received from a new master process
    private abstract processSelfMsgImpl(ZSocketRouter router, int index, string sender, string mboxid, string cmd, ZMsg msg);

    #! get process info
    private abstract hash<auto> getInfo();
}

class MyRouter inherits ZSocketRouter {
    public {
        int index;
    }

    constructor(ZContext ctx, string identity, string url, int index, NetworkKeyHelper nkh) : ZSocketRouter(ctx) {
        # set index
        self.index = index;
        # set socket identity
        setIdentity(identity);
        # issue #3453: setup encryption before binding
        nkh.setServer(self);
        # clients can reuse identities but must ensure uniqueness
        setOption(ZMQ_ROUTER_HANDOVER, 1);
        # bind listeners
        bind(url);
    }
}
