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

class AbstractQorusInternProcess inherits AbstractQorusProcess {
    private {
        # child process command-line options
        *list<softstring> cl_opts;

        # restarted flag
        bool restarted;

        #! client object for communication with the process
        AbstractQorusClient client;
    }

    # creates the object
    /**
        @param restarted restarted flag
        @param cl_opts optional command-line arguments for the child process
    */
    constructor(
            AbstractQorusProcessManager parent,
            string node,
            string host,
            string name,
            string client_id,
            bool restarted,
            *softlist<softstring> cl_opts) : AbstractQorusProcess(parent, node, host, name, client_id) {
        self.restarted = restarted;
        self.cl_opts = cl_opts;
    }

    private list<auto> getCommonStartArgs() {
        return (
            CPC_API_LEVEL,
            node,
            Qorus.getActiveMasterNodeName(),
            parent.getActiveMasterUrlsString(),
            parent.getInterfacesString(),
            parent.getNetworkKeyPath(),
            getId(),
            client_id,
            restarted.toInt(),
        );
    }

    #! retrieves the client object
    synchronized AbstractQorusClient getClient() {
        if (client) {
            return client;
        }
        parent.setUrls(id, child_urls);
        return client = getClientImpl();
    }

    #! Terminate the process
    terminate(*hash<auto> args) {
        QDBG_LOG("AbstractQorusInternProcess::terminate() local: %y (node: %y this node: %y) args: %y status: %y child: %y", localProcess(), node, parent.getNodeName(), args, status, child);
        if (!localProcess() || args) {
            if (status == CS_RUNNING) {
                QDBG_LOG("terminating remote process %y", id);
                try {
                    getClient().sendCmdUnreliable(CPC_KILL_PROC, {"kill_self": True} + args, 1s);
                } catch (hash<ExceptionInfo> ex) {
                    # ignore errors
                }
            } else {
                QDBG_LOG("not terminating process %y with status %y", id, status);
            }
            return;
        }
        QDBG_LOG("terminating local process %y", id);
        AbstractQorusProcess::terminate();
    }

    #! Called whan an independent process has aborted
    markDead() {
        setStatus(CS_IDLE, CS_RUNNING, CS_IDLE, CS_STOPPING);
    }

    /**
        @par Description
        Sets the restart flag if not already set
    */
    setRestarting() {
        # NOTE: the following call can throw an exception (ex: INSUFFICIENT-MEMORY)
        AbstractQorusProcess::setRestarting();
        if (!restarted) {
            restarted = True;
        }
    }

    /**
        @par Description
        Gets the process's restarted flag

        @par Return Value
        Returns the process's restarted flag
    */
    bool getRestarted() {
        return restarted;
    }

    /**
        @par Description
        Called when another cluster process was aborted and before any attempt to restart the process has been made

        @par Return Value
        The Queue where the reply will be received
    */
    Queue sendNotifyAbortedProcessInitial(string other_id) {
        AbstractQorusClient client = getClient();
        hash<auto> h = {
            "process": other_id,
        };
        QDBG_LOG("sending initial aborted notification to %y (%y) re %y", child_urls[0], getId(), other_id);
        return client.sendCmdAsync(CPC_PROCESS_ABORT_NOTIFICATION, h);
    }

    /**
        @par Description
        Called when another cluster process was aborted and after the process may have been restarted

        @par Return Value
        The Queue where the reply will be received
    */
    Queue sendNotifyAbortedProcess(string other_id, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        AbstractQorusClient client = getClient();
        hash<auto> h = {
            "process": other_id,
            "info": info,
            "restarted": restarted,
            "abort_timestamp": abort_timestamp,
        };
        QDBG_LOG("sending aborted notification to %y (%y) re %y", child_urls[0], getId(), other_id);
        return client.sendCmdAsync(CPC_PROCESS_ABORTED, h);
    }

    /**
        @par Description
        Processes a message from the cluster server process to the master process

        @par Return Value
        \a True if success
    */
    bool processMsg(MyRouter router, string sender, string mboxid, string cmd, ZMsg msg) {
        switch (cmd) {
            case CPC_START: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                QDBG_LOG("ix: %y sender: %y mboxid: %y START: %y (status: %y)", router.index, sender, mboxid, h, status);
                # check API level
                if (h.api_level != CPC_API_LEVEL) {
                    string err = sprintf("cluster process %s %y sent %y message with API level %y; expecting %y", getName(), id, CPC_START, h.api_level, CPC_API_LEVEL);
                    logError(err);
                    # do not change status and send an error in the format for a REQ socket
                    router.send(sender, mboxid, err);
                } else {
                    # get child process URL
                    child_urls = h.urls;

                    # make sure we can start
                    {
                        m.lock();
                        on_exit m.unlock();

                        if (status == CS_STARTING) {
                            # send OK in the format for a REQ socket
                            router.send(sender, mboxid, CPC_OK);
                            setStatusIntern(CS_RUNNING);
                        } else {
                            logInfo("cluster process %s %y: cannot authorize start because the process has status %y", getName(), id, status);
                            # do not change status and send an error in the format for a REQ socket
                            router.send(sender, mboxid, "ERR");
                        }
                    }

                    QDBG_ASSERT(pid == -1 || pid == h.pid);
                    if (pid == -1) {
                        pid = h.pid;
                    }

                    processRunning();
                }

                return True;
            }
        }

        return processMsgImpl(router, sender, mboxid, cmd, msg);
    }

    #! Returns True if the process was stopped normally, False if not
    bool stop() {
        # set status from STARTED -> STOPPING
        setStatus(CS_STOPPING, CS_RUNNING, CS_IDLE);
        logInfo("%s %y: stopping %s process on node %s PID %d (%y)", getName(), getId(),
            localProcess() ? "local" : "remote", getNode(), getPid(), getUrls());

        # send a "STOP" command to the child
        stopImpl();

        #logDebug("%s %y: sent %y to %y (%y)", getName(), getId(), CPC_STOP, child_urls, child);
        # wait for process to terminate
        bool rv;
        try {
            if (wait()) {
                logInfo("%s %y: stopped process on node %s PID %d", getName(), id, getNode(), getPid());
            } else {
                logInfo("%s %y: cannot stop independent process on node %s PID %d", getName(), id, getNode(), getPid());
            }
            rv = True;
        } catch (hash<ExceptionInfo> ex) {
            # issue #3642: if the process terminates before the STOP message can be sent, then treat as a normal stop
            # happens only on Alpine Linux
            if (ex.err == "PROCESS-WAIT-ERROR") {
                logInfo("%s %y: stopped process on node %s PID %d (terminated)", getName(), id, getNode(), getPid());
                rv = True;
            } else {
                logError("stopping %s %y on node %s PID %d: %s: %s", getName(), id, getNode(), getPid(), ex.err, ex.desc);
                rv = False;
            }
        }
        # set status to IDLE
        setStatus(CS_IDLE);
        return rv;
    }

    private string getSenderId(string pfx) {
        return sprintf("mr-%s-%s-%d-%d-%d", pfx, parent.getNodeName(), getpid(), gettid(), getId());
    }

    private stopImpl() {
        QDBG_LOG("STOPPING: %y", id);
        if (!localProcess()) {
            parent.stopProcessInPassiveMaster(self);
        } else {
            sendStopMessage();
        }
    }

    private sendStopMessage(timeout to = 10s) {
        try {
            QDBG_LOG("%y: sending STOP to %y", id, child_urls);
            AbstractQorusClient client = getClient();
            client.sendCheckResponseUnreliable(CPC_STOP, NOTHING, CPC_ACK, to);
        } catch (hash<ExceptionInfo> ex) {
            logInfo("%y: error in stop message: %s: %s; assuming process dead", id, ex.err, ex.desc);
        }
    }

    # override
    hash<auto> getInfo() {
        return {
            "restarted": getRestarted()
        } + AbstractQorusProcess::getInfo();
    }

    # called when the remote process starts
    private processRunning() {
        # this method intentionally left empty in the base class
    }

    # called in the master's event thread
    private bool processMsgImpl(MyRouter router, string sender, string mboxid, string cmd, ZMsg msg) {
        return False;
    }

    #! create the client object
    private abstract AbstractQorusClient getClientImpl();
}
