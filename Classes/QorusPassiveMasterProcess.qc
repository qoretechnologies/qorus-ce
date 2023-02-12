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

# process network id is "qorus-master-<node>"
class QorusPassiveMasterProcess inherits AbstractQorusInternProcess {
    constructor(AbstractQorusProcessManager parent, hash<ClusterProcInfo> info, date start_timestamp) :
        AbstractQorusInternProcess(parent, info.node, info.host, QDP_NAME_QORUS_MASTER, info.node, False) {
        child_urls = info.queue_urls;
        pid = info.pid;
        child = False;
        # issue #3868: if this is not set, then the recovery messagee after an active master handoff is not sent
        started = start_timestamp;
        status = CS_RUNNING;
    }

    private Process startImpl() {
        throw "UNSUPPORTED", "qorus-master processes must be started externally";
    }

    #! create the client object
    private AbstractQorusClient getClientImpl() {
        return new QorusMasterClient(parent, node, parent.getNetworkId());
    }

    #! processes message from the remote process
    bool processMsgImpl(MyRouter router, string sender, string mboxid, string cmd, ZMsg msg) {
        switch (cmd.toString()) {
            # this msg is a one-way msg - no response provided
            case CPC_MR_REMOTE_PROCESS_ABORTED: {
                list<hash<ClusterProcInfo>> info_list = qorus_cluster_deserialize(msg.popBin()).info_list;
                logInfo("remote processes aborted: %y", (map $1.id, info_list));
                background Qorus.handleRemoteProcessAbort(info_list);
                return True;
            }

            case CPC_MR_DO_PASSIVE_SHUTDOWN: {
                background Qorus.handlePassiveShutdown(router.index, sender, mboxid, node);
                return True;
            }

            case CPC_MR_NEW_PASSIVE_MASTER: {
                Qorus.handlePassiveMasterRegistration(msg, router.index, sender, mboxid);
                return True;
            }
        }

        return False;
    }

    #! returns all constructor arguments after "host"
    private list<auto> getConstructorArgsImpl() {
        throw "UNSUPPORTED", "passive master processes must be started directly on the node";
    }
}
