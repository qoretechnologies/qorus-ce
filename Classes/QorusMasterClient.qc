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

# here we add fallback paths to the QORE_MODULE_DIR search path,
# in case QORE_MODULE_DIR is not set properly for Qorus
%append-module-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib:$OMQ_DIR/user/modules

# here we add fallback paths to the QORE_INCLUDE_DIR search path,
# in case QORE_INCLUDE_DIR is not set properly
%append-include-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib

# connection to the master process
class QorusMasterClient inherits AbstractQorusClient {
    private {
        #! the process name as assigned by the master
        string master_index_name;
    }

    # creates the object and registers the client with the parent process
    /** @param process the client process object
        @param node the name of the node where the master is running
        @param name the name of the current process for the master index for messaging
    */
    constructor(AbstractQorusClientProcess process, string node, string name)
            : AbstractQorusClient(process, QDP_NAME_QORUS_MASTER, node) {
        master_index_name = name;
    }

    #! Returns the node the master is running on
    string getNode() {
        return server_name;
    }

    #! Returns process info for the given process ID or NOTHING if the process does not exist in the master
    *hash<auto> getProcessInfo(string id) {
        return qorus_cluster_deserialize(
            checkResponseMsg(CPC_MR_GET_PROCESS_INFO, CPC_OK, sendCmdSerialized(CPC_MR_GET_PROCESS_INFO, proc_name))[0]
        );
    }

    #! tells the master process to send a one-way "broadcast" message to all interfaces; broadcast is executed asynchronously
    /** Calls a direct method in the interface
    */
    broadcastToAllInterfacesDirect(string method) {
        hash<auto> h = {
            "method": method,
            "args": argv,
        };
        broadcastToAllInterfacesIntern(CPC_MR_BCAST_IFS_DIRECT, h);
    }

    #! tells the master process to send a one-way "broadcast" message to all interfaces; broadcast is executed asynchronously
    /** Calls a method in a subsystem
    */
    broadcastToAllInterfaces(string subsystem, string method, *softlist<auto> args) {
        hash<auto> h = {
            "subsystem": subsystem,
            "method": method,
            "args": args,
        };
        broadcastToAllInterfacesIntern(CPC_MR_BCAST_IFS, h);
    }

    #! tells the master process to send a one-way "broadcast" message to all interfaces and waits for the confirmation
    broadcastConfirmToAllInterfaces(string subsystem, string method, *softlist<auto> args) {
        hash<auto> h = {
            "subsystem": subsystem,
            "method": method,
            "args": args,
        };
        broadcastToAllInterfacesIntern(CPC_MR_BCAST_CONFIRM_IFS, h);
    }

    sendCmdOneWay(string cmd, *hash<auto> h) {
        #QDBG_LOG("sendCmdOneWay() to %y: cmd: %y: \"%s...\"", proc_name, cmd, replace(make_yaml(Serializable::serializeToData(h)._data._members)[0..40], "\n", ""));
        #on_exit QDBG_LOG("DONE");
        checkAborted();
        process.submitClientDataCmd(unique_client_id, DQ_REQOW, master_index_name, cmd,
            exists h ? qorus_cluster_serialize(h) : NOTHING);
    }

    #! tells the master process to send a one-way "broadcast" message to all interfaces
    private broadcastToAllInterfacesIntern(string cmd, hash<auto> h) {
        while (True) {
            try {
                Queue response_queue();
                process.submitClientRequest(unique_client_id, response_queue, master_index_name, cmd,
                    qorus_cluster_serialize(h), process.getNetworkId());
                *list<string> msgs;
                while (exists (*string msg = response_queue.get())) {
                    push msgs, msg;
                }
                msgs = processDataQueueMsg(msgs);
                checkResponseMsg(cmd, CPC_ACK, msgs);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "CLIENT-ABORTED") {
                    log(LoggerLevel::INFO, "connection to %y interrupted in broadcast (%y); retrying", proc_name,
                        h{"subsystem", "method"});
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    #! sends a serialized command to the server
    private sendCmdIntern(Queue response_queue, string cmd, *data d) {
        #log(LoggerLevel::DEBUG, "QorusMasterClient::sendCmdIntern() sending ix: %y cmd: %y str: %y", master_index_name, cmd, str);
        if (aborted) {
            throw "CLIENT-DEAD", sprintf("connection to remote client %y terminated because the process "
                "aborted and was not restarted", unique_client_id);
        }

        process.submitClientRequest(unique_client_id, response_queue, master_index_name, cmd, d);
    }
}
