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

#! hash of client info
hashdecl ClientProcInfo {
    #! condition var
    Condition cond();

    #! waiting thread count
    int waiting = 0;

    #! created flag
    bool created = False;
}

class AbstractQorusClusterApi {
    private {
        #! mutex for atomic waits until processes have been restarted
        Mutex proc_lck();

        #! hash of counter/flags for threads waiting on the processes
        hash<string, hash<ClientProcInfo>> proc_info;
    }

    bool processMsg(ZSocketRouter sock, string sender, string mboxid, string cmd, ZMsg msg) {
        # process common commands
        switch (cmd) {
            case CPC_STOP: {
                *binary msg_data = msg.popBin();
                hash<auto> msg_hash;
                if (msg_data) {
                    msg_hash = qorus_cluster_deserialize(msg_data);
                }
                doInlineStop(sock, sender, mboxid, msg_hash);
                return True;
            }

            case CPC_PING:
                # send keep alive response
                sock.send(sender, mboxid, CPC_PONG);
                return True;

            # issue #2651: process initial process abort notifications
            case CPC_PROCESS_ABORT_NOTIFICATION: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logCmd(LoggerLevel::INFO, "cluster process %y terminated prematurely", h.process);
                # remove any state for aborted process
                processAbortNotificationImpl(h.process);
                # acknowledge request
                sock.send(sender, mboxid, CPC_ACK);
                return True;
            }

            case CPC_PROCESS_ABORTED: {
                handleProcessAbortedMessage(sock, msg, sender, mboxid);
                return True;
            }

            case CPC_GET_INFO:
                sock.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(getInfo()));
                return True;

            case CPC_GET_THREADS:
                sock.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(get_all_thread_call_stacks()));
                return True;

            # kill a process on the local node
            case CPC_KILL_PROC: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logCmd(LoggerLevel::INFO, "kill proc: %y", h);
                *hash<auto> rv = handleKillProcMessage(h);
                sock.send(sender, mboxid, CPC_OK, qorus_cluster_serialize(rv));
                if (h.kill_self) {
                    logCmd(LoggerLevel::INFO, "killing current process");
                    exit(-1);
                }
                return True;
            }
        }
        return False;
    }

    #! handles a PROCESS-ABORTED message
    private handleProcessAbortedMessage(ZSocketRouter sock, ZMsg msg, string sender, string mboxid) {
        hash<auto> h = qorus_cluster_deserialize(msg);
        logCmd(LoggerLevel::INFO, "cluster process %y terminated prematurely; info: %y restarted: %y abort "
                "timestamp: %y", h.process, h.info, h.restarted, h.abort_timestamp);
        # remove any state for aborted process in the background as locks are acquired
        background processAbortedImpl(h.process, h.info, h.restarted, h.abort_timestamp);
        # acknowledge request
        sock.send(sender, mboxid, CPC_ACK);
    }

    #! Handles a KILL-PROC message
    private *hash<auto> handleKillProcMessage(hash<auto> h) {
        hash<auto> rv;
        foreach int pid in (h.pids) {
            int rc = kill(pid, h.signal ?? SIGKILL);
            rv{pid} = {
                "rc": rc,
                "errno": errno(),
            };
            logCmd(LoggerLevel::INFO, "kill PID %d rc: %d (result: %s)", pid, rc, strerror());
        }
        return rv;
    }

    #! Processes a STOP message inline
    private doInlineStop(ZSocketRouter sock, string sender, string mboxid, *hash<auto> msg_hash) {
        sock.send(sender, mboxid, CPC_ACK);
        # cannot stop the server from the I/O thread
        background stopServer();
    }

    #! notifies waiting threads that a client is available; proc_lck must be held
    private notifyClientIntern(string id) {
        QDBG_ASSERT(proc_lck.lockOwner());

        # create process info hash if needed
        if (!proc_info{id}) {
            proc_info{id} = <ClientProcInfo>{};
        }

        if (!proc_info{id}.created) {
            # notify any waiting threads that the process client is ready
            if (proc_info{id}.waiting) {
                proc_info{id}.cond.broadcast();
            }
            # mark the process client created
            proc_info{id}.created = True;
        }
    }

    #! waits for a client to become available
    private waitForClient(string id) {
        proc_lck.lock();
        on_exit proc_lck.unlock();

        # create process info hash if needed
        if (!proc_info{id}) {
            proc_info{id} = <ClientProcInfo>{};
        }

        # wait for the client to be created
        while (!proc_info{id}.created) {
            ++proc_info{id}.waiting;
            proc_info{id}.cond.wait(proc_lck);
            --proc_info{id}.waiting;
        }
    }

    abstract logCmd(int ll, string fmt);
    abstract errorCmd(string fmt);
    abstract stopServer();
    #! returns information about the process
    abstract hash getInfo();

    #! issue #2651: called from the network API when a cluster process has aborted before any attempt to restart it has been made
    abstract private processAbortNotificationImpl(string process);

    #! called from the network API when a cluster process has aborted and possibly has been restarted
    abstract private processAbortedImpl(string process, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp);
}
