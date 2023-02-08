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

class AbstractQorusProcess {
    public {
        #! the maximum number of bytes to read from output streams
        const DefaultOutputSize = 32 * 1024;
    }

    private {
        #! parent object
        AbstractQorusProcessManager parent;

        #! node name; the unique node name where the process is running
        string node;

        #! host name where the process is running
        string host;

        #! the PID on the host
        int pid = -1;

        #! process name; this is the string used to launch the process
        string name;

        #! the cluster-server-specific name for the process
        string client_id;

        #! unique process network ID (not the PID): name + "-" + client_id
        string id;

        #! child process's queue URL
        *list<string> child_urls;

        #! qproc process object
        Process qproc;

        #! can we manage the process directly?
        bool child = True;

        #! child status mutex
        Mutex m();

        #! child status condition
        Condition cond();

        #! child status
        int status = CS_IDLE;

        #! threads waiting on status changes
        int stat_waiting = 0;

        #! start error text saved here
        string start_err;

        #! Process start time
        date started;

        #! memory summary info for remote processes
        hash<MemorySummaryInfo> remote_memory_info();

        #! process poll interval
        const ProcessPollInterval = 500ms;

        #! default process start timeout
        const StartTimeout = 20s;
    }

    # creates the object
    /** @param parent the process manager object
        @param node the unique node name where the process is running
        @param host the host name where the process is running
        @param name the name of the server process
        @param client_id the server-specific name
    */
    constructor(AbstractQorusProcessManager parent, string node, string host, string name, string client_id) {
        self.parent = parent;
        self.node = node;
        self.host = host;
        self.name = name;
        self.client_id = client_id;
        id = name;
        if (client_id != "-")
            id += "-" + client_id;
    }

    #! returns all constructor args after "host"
    list<auto> getConstructorArgs() {
        return getConstructorArgsImpl();
    }

    #! Waits for the process to terminate
    /** @return True if the process terminated, False if not (independent)
    */
    bool wait() {
        QDBG_LOG("AbstractQorusProcess::wait() node: %y (%y) name: %y pid: %y child: %y", node, parent.getNodeName(), id, pid, child);

        if (parent.getNodeName() != node) {
            # in case of remote processes, they are stopped in the call to the passive master on that node
            return True;
        }

        if (child) {
            try {
                qproc.wait();
            } catch (hash<ExceptionInfo> ex) {
                logWarn("error waiting for process: %s: %s; assuming terminated", ex.err, ex.desc);
            }
            return True;
        }

        Process::waitForTermination(pid);
        return True;
    }

    string getClientId() {
        return client_id;
    }

    #! Called when the process terminates unexpectedly; returns True if the process should be restarted
    bool restartProcess() {
        return True;
    }

    private logFatal(string msg) {
        parent.logArgs(Logger::LoggerLevel::FATAL, msg, argv);
    }

    private logError(string msg) {
        parent.logArgs(Logger::LoggerLevel::ERROR, msg, argv);
    }

    private logWarn(string msg) {
        parent.logArgs(Logger::LoggerLevel::WARN, msg, argv);
    }

    private logInfo(string msg) {
        parent.logArgs(Logger::LoggerLevel::INFO, msg, argv);
    }

    private logDebug(string msg) {
        parent.logArgs(Logger::LoggerLevel::DEBUG, msg, argv);
    }

    private logTrace(string msg) {
        parent.logArgs(Logger::LoggerLevel::TRACE, msg, argv);
    }

    # changes the process's status
    private setStatus(int stat) {
        m.lock();
        on_exit m.unlock();

        setStatusUnlockedArgs(stat, argv);
    }

    private setStatusUnlockedArgs(int stat, *softlist<auto> args) {
        if (args) {
            bool found;
            foreach int cstat in (args) {
                if (status == cstat) {
                    found = True;
                    break;
                }
            }
            if (!found) {
                string err = sprintf("cannot set status %y when current status is %y; expecting: %y",
                    CS_StatusMap{stat}, CS_StatusMap{status}, (foldl $1 + ", " + $2, map CS_StatusMap.$1, args));
                logFatal(err);
                throw "PROCESS-STATUS-ERROR", err;
            }
        }

        setStatusIntern(stat);
    }

    private setStatusUnconditional(int stat) {
        m.lock();
        on_exit m.unlock();

        setStatusIntern(stat);
    }

    #! returns a descriptive string of the network interface(s) for this process
    string getNetworkDescription() {
        if (!child_urls) {
            # URLs are not immediately available when a process is started on a passive node
            return "n/a";
        }
        return sprintf("%y", child_urls);
    }

    #! returns the process's queue URLs separated by a comma or @ref nothing for external processes
    *string getUrlsString() {
        return child_urls ? child_urls.join(",") : NOTHING;
    }

    #! Gets a list of URLs for the child process or @ref nothing for external processes
    /** @return a list of URLs for the child process
    */
    *list<string> getUrls() {
        return child_urls;
    }

    #! Gets process's name
    /** @return the name of the process
    */
    string getName() {
        return name;
    }

    #! Gets process's host name
    /** @return the process's host name
    */
    string getHostName() {
        return host;
    }

    #! Gets process's PID
    /** @return the process's PID
    */
    int getPid() {
        return pid;
    }

    #! Gets process's status
    /** @return the process's status
    */
    int getStatus() {
        return status;
    }

    #! Gets process's id (name + "-" + client_id)
    /** @return the process's unique network ID (not the PID)
    */
    string getId() {
        return id;
    }

    #! Gets the node name where the process is running
    /** @return the node name where the process is running
    */
    string getNode() {
        return node;
    }

    #! Returns \c True if the process needs a CPC_PROCESS_ABORT_NOTIFICATION message
    /** @return \c True if the process needs a CPC_PROCESS_ABORT_NOTIFICATION message
    */
    bool needsSendNotifyAbortedProcessInitial() {
        return False;
    }

    #! Returns \c True if the process needs a CPC_PROCESS_ABORTED message
    /** @return \c True if the process needs a CPC_PROCESS_ABORTED message
    */
    bool needsSendNotifyRestartProcess() {
        return !needsSendNotifyAbortedProcessInitial();
    }

    #! Returns any start error message
    *string getStartError() {
        return start_err;
    }

    #! Detaches the current process if attached
    detach() {
        QDBG_ASSERT(started);
        if (qproc) {
            logInfo("%s (%s:%d) detached", id, host, pid);
            qproc.detach();
        }
    }

    #! Sets memory summary info from remote processes
    setRemoteMemoryInfo(hash<MemorySummaryInfo> info) {
        QDBG_LOG("AbstractQorusProcess::setRemoteMemoryInfo() %y = %y", id, info);
        remote_memory_info = info;
    }

    #! Gets information about the running process
    /** @return a hash of memory summary info about the running process
    */
    hash<MemorySummaryInfo> getProcessMemoryInfo() {
        if (!localProcess()) {
            return remote_memory_info;
        }
        if (!running()) {
            return new hash<MemorySummaryInfo>();
        }
%ifdef MEMORY_POLLING
        return parent.getProcessMemoryInfo(pid);
%else
%ifdef QORUS_STANDALONE_TEST
        if (Platform.OS == "Darwin") {
            return new hash<MemorySummaryInfo>();
        }
%endif
        return qproc.getMemorySummaryInfo();
%endif
    }

    #! Updates process info at runtime
    updateProcessInfo(hash<auto> h) {
        throw "UNSUPPORTED";
    }

    #! Returns True if the process is running locally
    bool localProcess() {
        return node == parent.getNodeName();
    }

    #! Starts the process on a node with a passive master
    /** @return \c True if the process started normally, \c False if an error occurred
    */
    bool startPassive() {
        QDBG_ASSERT(child);
        QDBG_ASSERT(localProcess());
        if (startLocal()) {
            setStatus(CS_RUNNING, CS_IDLE);
            return True;
        }
        return False;
    }

    #! Starts the process
    /** @return \c True if the process started normally, \c False if an error occurred
    */
    bool start() {
        if (!child) {
            # verify status
            setStatus(CS_RUNNING, CS_RUNNING, CS_IDLE);
            logInfo("%s %y detached child running on node %s PID: %d URLs: %y", name, id, node,
                pid, getNetworkDescription());
            return True;
        }
        setStatus(CS_STARTING, CS_IDLE);
        if (localProcess()) {
            if (!startLocal()) {
                return False;
            }
        } else {
            if (!startRemote()) {
                return False;
            }
        }

        logInfo("%s %y started process on node %y PID %d; waiting for %s", name, id, node, pid,
            getStartMsg());
        # start verification thread
        background checkStart();
        waitForNotStatus(CS_STARTING);
        # can go from STARTING -> STARTED | ERR
        if (status == CS_RUNNING) {
            started = now_us();
            # detach processes by default
            detach();
            logInfo("%s %y started with URLs: %s", name, id, getNetworkDescription());
            return True;
        }
        return False;
    }

    #! Returns True if the start time is after the timestamp passed
    bool checkStartTimeBefore(date timestamp) {
%ifdef QorusDebugInternals
        bool rv = started && started < timestamp;
        if (!rv) {
            QDBG_LOG("AbstractQorusProcess::checkStartTimeBefore() %y started: %y > %y", id, started, timestamp);
        }
        return rv;
%else
        return started && started < timestamp;
%endif
    }

    #! Returns the start time of the process; must be running
    *date getStartTime() {
        QDBG_ASSERT(status == CS_RUNNING);
        return started;
    }

    #! Starts a local process
    private bool startLocal() {
        try {
            qproc = startImpl();
            pid = qproc.id();
            return True;
        } catch (hash<ExceptionInfo> ex) {
            string errstr = Qorus.getDebugSystem()
                ? get_exception_string(ex)
                : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            logError(sprintf("failed to start local process %s %y: %s", name, id, errstr));
            start_err = errstr;
            return False;
        }
    }

    #! Starts a process on a remote node
    private bool startRemote() {
        try {
            child = False;
            pid = parent.startRemoteProcess(self);
            return True;
        } catch (hash<ExceptionInfo> ex) {
            string errstr = Qorus.getDebugSystem()
                ? get_exception_string(ex)
                : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            logError(sprintf("failed to start remote process %s %y on node %y: %s", name, id, node, errstr));
            start_err = errstr;
            return False;
        }
    }

    private string getStartMsg() {
        return "child URL";
    }

    #! Updates info for a running process
    /** Currently called only for qorus-core in independent mode
    */
    updateRunningDetached(hash<ClusterProcInfo> info, date start_timestamp = now_us()) {
        QDBG_ASSERT(!child);
        QDBG_ASSERT(!localProcess());
        setStatusUnconditional(CS_RUNNING);
        child_urls = info.queue_urls;
        pid = info.pid;
        host = info.host;
        node = info.node;
        started = start_timestamp;
        parent.setUrls(info, started);
    }

    #! Creates the process object based on the PID and sets the child flag to False
    /** if the status is already CS_RUNNING, returns False, otherwise sets the detached status and returns True
    */
    bool trySetDetached(hash<auto> row) {
        {
            m.lock();
            on_exit m.unlock();

            if (status == CS_RUNNING) {
                return False;
            }
            setDetachedUnlocked(row);
        }
        child_urls = row.queue_urls && row.queue_urls != "-" ? row.queue_urls.split(",") : NOTHING;
        parent.setUrls(id, child_urls);
        return True;
    }

    #! Creates the process object based on the PID and sets the child flag to False
    setDetached(hash<auto> row, *int new_status) {
        {
            m.lock();
            on_exit m.unlock();

            setDetachedUnlocked(row, new_status);
        }
        child_urls = row.queue_urls && row.queue_urls != "-" ? row.queue_urls.split(",") : NOTHING;
        parent.setUrls(id, child_urls);
    }

    #! Creates the process object for local proecsses based on the PID and sets the child flag to False
    setDetached(int pid, *list<string> urls, date started) {
        child_urls = urls;
        child = False;
        self.pid = pid;
        self.started = started;
        qproc = new Process(pid);
        setStatus(CS_RUNNING, CS_IDLE);
        parent.setUrls(id, urls);
    }

    #! Sets the URLs as reported from the active master or as found in the DB when recovering
    setUrls(*list<string> urls) {
        child_urls = urls;
        parent.setUrls(id, urls);
    }

    #! Checks if process is running
    /** @return \c True if the process is running
    */
    bool running() {
        #QDBG_LOG("AbstractQorusProcess::running() %y local: %y status: %y qproc: %y (running: %y) child: %y node: %y (pid: %d %y)", id, localProcess(), status, exists qproc, exists qproc ? qproc.running() : "n/a", child, node, pid, localProcess() ? Process::checkPid(pid) : "n/a");
        if (!localProcess()) {
            return status == CS_RUNNING || status == CS_STARTING;
        }

        if (!qproc) {
            return False;
        }

        if (child) {
            return qproc.running();
        }

        return Process::checkPid(pid);
    }

    #! Gets information about the cluster process
    /** @return a hash with cluster process info
    */
    hash<ClusterProcInfo> getClusterProcInfo() {
        return <ClusterProcInfo>{
            "id": id,
            "queue_urls": getUrls(),
            "host": host,
            "node": node,
            "pid": pid,
        };
    }

    #! Gets information about the cluster process table row
    /** @return a hash with cluster process table row
    */
    hash<auto> getClusterProcessesRow() {
        *hash<auto> ih = getProcessInfo();
        return {
            "process_network_id": id,
            "host": host,
            "node": node,
            "pid": pid,
            "process_type": name,
            "client_id": getClientId(),
            "interfaces": parent.getInterfacesString(),
            "queue_urls": getUrlsString(),
            "info": ih ? make_yaml(ih) : NOTHING,
        };
    }

    #! Gets information needed to restart the process if it terminates unexpectedly (or is killed)
    /** @return a hash with information needed to restart the process if it terminates unexpectedly (or is killed)
    */
    *hash<auto> getProcessInfo() {
    }

    #! Called when a process is restarted
    setRestarting() {
        processAborted();
        hash<NodeHostInfo> node_info = parent.getNodeForNewProcess(id);
        node = node_info.node;
        host = node_info.host;
        pid = -1;
        remove child_urls;
    }

    #! Terminate the process
    terminate() {
        if (child) {
            qproc.terminate();
            return;
        }

        try {
            Process::terminate(pid);
        } catch (hash<ExceptionInfo> ex) {
            logError("failed to kill process %y; assuming process dead: %s: %s", id, ex.err, ex.desc);
        }
    }

    #! Called when process terminates unexpectedly
    processAborted() {
        # set status to IDLE
        setStatus(CS_IDLE, CS_RUNNING, CS_STARTING, CS_IDLE);

        if (child) {
            if (qproc) {
                # try to log stderr / stdout if any
                *string str = qproc.readStdout(DefaultOutputSize);
                if (str) {
                    logInfo("%s %y aborted stdout: %s", name, id, trim(str));
                }
                str = qproc.readStderr(DefaultOutputSize);
                if (str) {
                    logInfo("%s %y aborted stderr: %s", name, id, trim(str));
                }
                # clear process object
                delete qproc;
            }
        } else {
            # reset child flag
            child = True;
        }
        # clear URLs
        delete child_urls;
        parent.removeUrls(id, now_us());
    }

    # logs an error message
    string error() {
        return call_function_args(\parent.error(), argv);
    }

    # logs a message
    log() {
        call_function_args(\parent.log(), argv);
    }

    # gets information about the process
    hash<auto> getInfo() {
        hash<auto> mh = getProcessMemoryInfo();
        int st = getStatus();
        return {
            "id": id,
            "node": node,
            "status": st,
            "status_string": CS_StatusMap{st},
            "urls": getUrls(),
            "host": host,
            "pid": pid,
            "type": name,
            "client_id": getClientId(),
            "started": started,
        } + mh + {"priv_str": mh ? get_byte_size(mh.priv) : "n/a"};
    }

    #! Read stdout from the managed Process
    /** @param bytes bytes to read (default: 32 * 1024)

        @return a string with process stdout
    */
    *string readStdout(int bytes = DefaultOutputSize) {
        if (child) {
            return "child: " + qproc.readStdout(bytes);
        }
    }

    #! Read stderr from the managed Process
    /** @param bytes bytes to read (default: 32 * 1024)

        @return a string with process stderr
    */
    *string readStderr(int bytes = DefaultOutputSize) {
        if (child) {
            return "child: " + qproc.readStderr(bytes);
        }
    }

    #! Checks if process has started. Called in the master's event thread
    private checkStart() {
        m.lock();
        on_exit m.unlock();

        date total = 0s;

        string err_str;
        while (status == CS_STARTING) {
            ++stat_waiting;
            int rc = cond.wait(m, ProcessPollInterval);
            --stat_waiting;
            if (!rc)
                break;
            if (rc == ETIMEDOUT) {
                total += ProcessPollInterval;
                #QDBG_LOG("process %y total: %y pid: %d running: %y really running: %y", id, total, pid, qproc.running(), Process::checkPid(pid));
                if (total >= StartTimeout) {
                    err_str = sprintf("process %y did not report its queue URL within the timeout: %y (running: %y)",
                        id, StartTimeout, qproc ? qproc.running() : False);
                    start_err = err_str;
                    if (qproc) {
                        # terminate the process if possible
                        qproc.terminate();
                    }
                    setStatusIntern(CS_ERR);
                    break;
                }
                QDBG_LOG("AbstractQorusProcess::checkStart() %y local: %y locally running: %y", id, localProcess(), qproc ? qproc.running() : False);
                if (localProcess() && !qproc.running()) {
                    err_str = sprintf("not running; rc: %d (running: %y)", qproc.exitCode(), Process::checkPid(pid));

                    # try to log stderr / stdout if any
                    *string str = qproc.readStdout(DefaultOutputSize);
                    if (str) {
                        err_str += sprintf(", stdout: %s", trim(str));
                    }
                    str = qproc.readStderr(DefaultOutputSize);
                    if (str) {
                        err_str += sprintf(", stderr: %s", trim(str));
                    }
                    start_err = err_str;

                    setStatusIntern(CS_ERR);
                    break;
                }
            }
        }

        if (err_str) {
            logError("%s %y failed to start: %s", name, id, err_str);
        }
    }

    #! Creates the process object based on the PID and sets the child flag to False
    /** called with the lock held
    */
    private setDetachedUnlocked(hash<auto> row, int new_status = CS_RUNNING) {
        child = False;
        pid = row.pid;
        host = row.host;
        node = row.node;
        started = row.created;
        if (localProcess()) {
            qproc = new Process(pid);
        }
        setStatusUnlockedArgs(new_status, CS_IDLE);
    }

    private setStatusIntern(int stat) {
        QDBG_LOG("AbstractQorusProcess::setStatusIntern() %s: %y -> %y", id, status, stat);
        status = stat;
        if (stat_waiting)
            cond.broadcast();
    }

    private waitForNotStatus(int stat) {
        m.lock();
        on_exit m.unlock();

        waitForNotStatusIntern(stat);
    }

    private waitForNotStatusIntern(int stat) {
        while (status == stat) {
            ++stat_waiting;
             cond.wait(m);
            --stat_waiting;
        }
    }

    #! Stops the process
    /** @return \c True if the process stopped normally, \c False if an error occurred
    */
    abstract bool stop();

    #! returns all constructor arguments after "host"
    private abstract list<auto> getConstructorArgsImpl();

    #! Starts the child process
    /** @return the Process object for the created program
    */
    private abstract Process startImpl();
}
