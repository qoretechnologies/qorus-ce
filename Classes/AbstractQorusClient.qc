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
%allow-weak-references

# here we add fallback paths to the QORE_INCLUDE_DIR search path,
# in case QORE_INCLUDE_DIR is not set properly
%append-include-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib

%requires zmq

class AbstractQorusClient {
    public {}

    private {
        # ZeroMQ context
        ZContext ctx();

        # the client process object
        /** the client process object provides:
            - logging facilities
            - the process ID
            - the queue URL source for the cluster server process corresponding to this client object
        */
        AbstractQorusClientProcess process;

        # the name or type of cluster server process
        string server_type;

        # the the specific server name (if any)
        *string server_name;

        # cluster server process name: server_type + "-" + server_name
        string proc_name;

        # unique client ID
        string unique_client_id;

        # client queue created flag
        bool queue_created = False;

        # main dealer queue; assigned in process event thread
        ClientDealer dealer;

        # in-progress request set; data queue identifier -> response queue
        /** This hash is only written to in the main ZeroMQ I/O thread
        */
        hash<string, Queue> request_map;

        # I/O thread counter
        Counter io_cnt();

        # aborted flag
        bool aborted = False;

        # request queue name
        string data_queue_url;

        # request queue
        const DataQueueUrlPrefix = "inproc://internal-data-queue-";
    }

    # creates the object and registers the client with the parent process
    /** @param process the client process object
        @param server_type the type of the remote server process
        @param server_name the optional name of the remote server
    */
    constructor(AbstractQorusClientProcess process, string server_type, *string server_name) {
        QorusSharedApi::checkLimits("cannot create ZeroMQ client");
        data_queue_url = DataQueueUrlPrefix + self.uniqueHash();
        self.process = process;
        self.server_type = server_type;
        self.server_name = server_name;
        proc_name = server_type;
        if (server_name.val())
            proc_name += "-" + server_name;
        unique_client_id = sprintf("%s-%s-%s", basename(QORE_ARGV[0] ?? "unknown"), proc_name, self.uniqueHash());
        # make sure the ZeroMQ context has default options set
        setContextOptions(ctx);
        process.registerClient(self);

        # add client queue
        process.createClientQueue(unique_client_id, \setupQueue());
        queue_created = True;
    }

    # deregisters the client with the parent process and destroys the object
    destructor() {
        if (process) {
            process.deregisterClient(self, unique_client_id, queue_created);
        }
    }

    #! Update process ID
    updateId(string new_active_master_id) {
        QDBG_LOG("new proc name: %y (old %y)", new_active_master_id, proc_name);
        proc_name = new_active_master_id;
        if (server_name) {
            server_name = new_active_master_id[(server_type.length() + 1)..];
        }
    }

    # issue: #3346: when deleting clients after the event thread has been shut down, we need to remove the process
    # object before deleting or there will be a deadlock
    removeProcess() {
        remove process;
    }

    string getServerName() {
        return server_name ?? server_type;
    }

    string getRemoteProcessId() {
        return proc_name;
    }

    # handles an aborted process notification
    *Counter abortedProcessNotification(string id, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        if (id == proc_name) {
            QDBG_LOG("AbstractQorusClient::abortedProcessNotification() id: %y info: %y restarted: %y "
                "abort_timestamp: %y", id, info, restarted, abort_timestamp);
            # the only time we can change the ID of a client is when the active master is updated
            QDBG_ASSERT(!info || (id == info.id) || info.new_active_master_id);
            if (!restarted) {
                aborted = True;
                #QDBG_LOG("stack: %N", get_stack());
            } else {
                aborted = False;
            }
            return abortedProcessNotificationIntern(id, restarted, abort_timestamp, info.new_active_master_id);
            # do not stop the I/O thread in case the process is restarted
        }
    }

    bool isAborted() {
        return aborted;
    }

    # returns the server name as the client type
    string getType() {
        return server_type;
    }

    # returns the unique client ID for this client
    string getClientId() {
        return unique_client_id;
    }

    # returns a hash of info about the server process
    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    hash<auto> getInfo(timeout to = -1) {
        try {
            return qorus_cluster_deserialize(checkResponseMsg(CPC_GET_INFO, CPC_OK, sendApiCmd(CPC_GET_INFO, NOTHING, to))[0]);
        } catch (hash<ExceptionInfo> ex) {
            throw ex.err, sprintf("client %y: %s", proc_name, ex.desc), ex.arg;
        }
    }

    # returns "PONG"
    string ping() {
        return sendCmd(CPC_PING)[0];
    }

    list<string> getUrls() {
        return process.getUrls(proc_name);
    }

    ZContext getContext() {
        return ctx;
    }

    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> sendCheckResponseUnreliable(string cmd, *hash<auto> h, string rcmd, timeout to = -1) {
        return checkResponseMsg(cmd, rcmd, sendCmdUnreliable(cmd, h, to));
    }

    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> sendCheckResponse(string cmd, *hash<auto> h, string rcmd, timeout to = -1) {
        return checkResponseMsg(cmd, rcmd, sendCmd(cmd, h, to));
    }

    #! send a cluster API message to the server process
    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> sendApiCmd(string cmd, *hash<auto> h, timeout to = -1) {
        #QDBG_LOG("sendApiCmd() to %y: cmd: %y: \"%s...\"", proc_name, cmd, replace(make_yaml(Serializable::serializeToData(h)._data._members)[0..120], "\n", ""));
        #on_exit QDBG_LOG("DONE");
        return sendApiCmdSerialized(cmd, exists h ? qorus_cluster_serialize(h) : NOTHING, to);
    }

    #! send a message to the server process; message may be modified by subclasses
    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> sendCmd(string cmd, *hash<auto> h, timeout to = -1) {
        #QDBG_LOG("sendCmd() to %y: cmd: %y: \"%s...\"", proc_name, cmd, replace(make_yaml(Serializable::serializeToData(h)._data._members)[0..40], "\n", ""));
        #on_exit QDBG_LOG("DONE");
        return sendCmdSerialized(cmd, exists h ? qorus_cluster_serialize(h) : NOTHING, to);
    }

    #! send a message to the server process
    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> sendCmdUnreliable(string cmd, *hash<auto> h, timeout to = -1) {
        #QDBG_LOG("sendCmdUnreliable() to %y: cmd: %y: \"%s...\"", proc_name, cmd, replace(make_yaml(Serializable::serializeToData(h)._data._members)[0..40], "\n", ""));
        #on_exit QDBG_LOG("DONE");
        return sendCmdSerializedUnreliable(cmd, exists h ? qorus_cluster_serialize(h) : NOTHING, to);
    }

    #! queues a message to be sent and returns the internal response Queue
    /** call checkAsyncResponseMsg() with the Queue returned from this method, or call cancelAsyncCmd() to cancel the
        async operation; one of these must be called to complete the async operations, or errors will result
    */
    Queue sendCmdAsync(string cmd, *hash<auto> h) {
        *data msgdata = exists h ? qorus_cluster_serialize(h) : NOTHING;
        Queue response_queue();
        #log(LoggerLevel::DEBUG, "AbstractQorusClient::sendCmdAsync() sending %s: %y", cmd, str);
        sendCmdIntern(response_queue, cmd, msgdata);
        return response_queue;
    }

    #! Cancels an in-progress async operation
    cancelAsyncCmd(string request_index = process.getRequestId(unique_client_id)) {
        # only cancel if the request is still in progress
        if (request_map{request_index}) {
            log(LoggerLevel::INFO, "canceling response queue for client %y request %y", unique_client_id,
                request_index);
            process.cancelRequest(unique_client_id, request_index);
        }
    }

    #! checks a response from the response queue and returns the list of frames after the expected response msg
    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> checkAsyncResponseMsg(Queue response_queue, string cmd, string rcmd, timeout to = -1) {
        return checkResponseMsg(cmd, rcmd, processDataQueueMsg(getResponseFromQueue(response_queue, to)));
    }

    #! gets messages from a response queue and cancels the response if a timeout occurs
    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> getResponseFromQueue(Queue response_queue, timeout to) {
        try {
            *list<string> rv;
            while (exists (*string msg = response_queue.get(to == -1 ? 0 : to))) {
                push rv, msg;
            }
            return rv;
        } catch (hash<ExceptionInfo> ex) {
            string request_id = process.getRequestId(unique_client_id);
            if (ex.err == "QUEUE-TIMEOUT") {
                log(LoggerLevel::INFO, "timeout for request %y: canceling response queue", request_id);
            } else {
                log(LoggerLevel::INFO, "error handling response for request %y: canceling response queue", request_id);
            }
            cancelAsyncCmd(request_id);
            rethrow;
        }
    }

    checkAborted() {
        if (aborted) {
            throw "CLIENT-DEAD", sprintf("connection to remote client %y terminated because the process "
                "aborted and was not restarted", unique_client_id);
        }
    }

    sendCmdOneWaySilent(string cmd, *hash<auto> h) {
        checkAborted();
        process.submitClientDataCmdSilent(unique_client_id, DQ_REQOW, cmd,
            exists h ? qorus_cluster_serialize(h) : NOTHING);
    }

    sendCmdOneWay(string cmd, *hash<auto> h) {
        #QDBG_LOG("sendCmdOneWay() to %y: cmd: %y: \"%s...\"", proc_name, cmd, replace(make_yaml(Serializable::serializeToData(h)._data._members)[0..40], "\n", ""));
        #on_exit QDBG_LOG("DONE");
        checkAborted();
        process.submitClientDataCmd(unique_client_id, DQ_REQOW, cmd, exists h ? qorus_cluster_serialize(h) : NOTHING);
    }

    sendCmdOneWaySerialized(string cmd, *data msgdata) {
        checkAborted();
        process.submitClientDataCmd(unique_client_id, DQ_REQOW, cmd, msgdata);
    }

    sendCmdOneWaySerializedIgnoreAborted(string cmd, *data msgdata) {
        if (aborted) {
            return;
        }
        process.submitClientDataCmd(unique_client_id, DQ_REQOW, cmd, msgdata);
    }

    #! send a serialized cluster API message to the server process
    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> sendApiCmdSerialized(string cmd, *data d, timeout to = -1) {
        while (True) {
            try {
                #QDBG_LOG("sending cmd to %y: %y: %d bytes", proc_name, cmd, d.size());
                #on_exit QDBG_LOG("DONE");
                return processDataQueueMsg(sendApiCmdSerializedIntern(cmd, d, to));
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "CLIENT-ABORTED") {
                    log(LoggerLevel::INFO, "connection to %s interrupted; retrying", proc_name);
                    continue;
                }
                rethrow;
            }
        }
    }

    #! send a serialized message to the server process; message may be modified by subclasses
    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> sendCmdSerialized(string cmd, *data d, timeout to = -1) {
        while (True) {
            try {
                #QDBG_LOG("sending cmd %y: %y", cmd, str);
                #on_exit QDBG_LOG("DONE");
                return processDataQueueMsg(sendCmdSerializedIntern(cmd, d, to));
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "CLIENT-ABORTED") {
                    log(LoggerLevel::INFO, "connection to %s interrupted; retrying", proc_name);
                    continue;
                }
                rethrow;
            }
        }
    }

    #! send a serialized message to the server process
    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> sendCmdSerializedUnreliable(string cmd, *data d, timeout to = -1) {
        #QDBG_LOG("sending cmd %y: %y", cmd, str);
        #on_exit QDBG_LOG("DONE");
        return processDataQueueMsg(sendCmdSerializedIntern(cmd, d, to));
    }

    *list<string> processDataQueueMsg(*list<string> msgs) {
        #QDBG_LOG("processDataQueueMsg() msgs: %y", msgs);
        string rcmd = shift msgs;
        switch (rcmd) {
            case DQ_REP:
                break;
            case DQ_ABORTED: {
                throw "CLIENT-ABORTED", sprintf("connection to remote client %y interrupted because the process "
                    "aborted", unique_client_id), {"restarted": msgs[0].toBool()};
            }
            case DQ_TERMINATE:
                throw "CLIENT-TERMINATED", sprintf("request to client %y aborted because the client object was "
                    "deleted", self.val() ? unique_client_id : "<unknown: object already deleted>");
%ifdef QorusDebugInternals
            default:
                QDBG_LOG("ERROR: unknown data queue return code %y", rcmd);
                throw "DATAQUEUE-ERROR", sprintf("unknown data queue return code %y", rcmd);
%endif
        }
        return msgs;
    }

    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    *list<string> sendApiCmdSerializedIntern(string cmd, *data d, timeout to = -1) {
        Queue response_queue();
        sendApiCmdIntern(response_queue, cmd, d);
        return getResponseFromQueue(response_queue, to);
    }

    /** @throw QUEUE-TIMEOUT thrown if the timeout period expires before an answer
    */
    private *list<string> sendCmdSerializedIntern(string cmd, *data d, timeout to = -1) {
        Queue response_queue();
        #log(LoggerLevel::DEBUG, "AbstractQorusClient::sendCmdSerializedIntern() sending %s: %y", cmd, str);
        sendCmdIntern(response_queue, cmd, d);
        return getResponseFromQueue(response_queue, to);
    }

    #! sends a serialized command to the server
    sendApiCmdIntern(Queue response_queue, string cmd, *data d) {
        if (aborted) {
            throw "CLIENT-DEAD", sprintf("connection to remote client %y terminated because the process "
                "aborted and was not restarted", unique_client_id);
        }
        #QDBG_LOG("AbstractQorusClient::sendApiCmdIntern() %y: sending  %s: %y", proc_name, cmd, str);

        process.submitClientRequest(unique_client_id, response_queue, cmd, d);
    }

    #! sends a serialized command to the server; may be modified by subclasses
    private sendCmdIntern(Queue response_queue, string cmd, *data d) {
        sendApiCmdIntern(response_queue, cmd, d);
    }

    #! check a response from the server process
    *list<string> checkResponseMsg(string req_cmd, string expected, *list<string> msgs) {
        *string cmd = shift msgs;
        if (cmd != expected) {
            string err = logUnexpectedResponse(req_cmd, expected, cmd, msgs, True);
            throw "INVALID-SERVER-RESPONSE", err;
        }
        return msgs;
    }

    #! checks a response without throwing an exception
    bool checkResponse(string req_cmd, string expected, *list<string> msgs) {
        *string cmd = shift msgs;
        if (cmd != expected) {
            logUnexpectedResponse(req_cmd, expected, cmd, msgs);
            return False;
        }
        return True;
    }

    string error() {
        return call_function_args(\process.error(), argv);
    }

    log() {
        call_function_args(\process.log(), argv);
    }

    #! terminates all connections
    /** can only be called from the process's main I/O thread
    */
    terminateAllConnections() {
        QDBG_ASSERT(!process || process.isIoThread());
        # send termination message for all outstanding requests
        map ($1.push(DQ_TERMINATE), $1.push()), request_map.iterator();
        # remove all response queues
        remove request_map;
    }

    #! remove this client's dealer from the poll list
    /** can only be called from the process's main I/O thread
    */
    removeDealer(reference<list<hash<ZmqPollInfo>>> poll_list) {
        QDBG_ASSERT(!process || process.isIoThread());
        if (!dealer) {
            return;
        }
        int lsize = poll_list.size();
        foreach hash<ZmqPollInfo> h in (poll_list) {
            if (h.socket == dealer) {
                splice poll_list, $#, 1;
                break;
            }
        }
        if (lsize == poll_list.size()) {
            log(LoggerLevel::INFO, "%s: dealer %y already removed from poll list", proc_name, dealer);
        }
    }

    private:internal hash<ZmqPollInfo> setupQueue(reference<hash<string, hash<string, code>>> client_handler_map) {
        QDBG_ASSERT(!dealer);

        # get dealer socket; the default timeout is OK because we use polling
        dealer = getNewDealer();

        # add to poll list
        hash<ZmqPollInfo> rv = <ZmqPollInfo>{
            "socket": dealer,
            "events": ZMQ_POLLIN,
        };

        client_handler_map{unique_client_id} = {
            "data": \processDataMsg(),
            "dealer": \processDealerMsg(),
        };

        return rv;
    }

    # called only int the main ZeroMQ I/O thread
    private:internal terminateConnectionIntern(reference<list<hash<ZmqPollInfo>>> poll_list) {
        QDBG_LOG("%s: stop queue command received; removing queue for client %y; request_map: %y", proc_name, unique_client_id, request_map);
        terminateAllConnections();

        # remove dealer from poll list
        removeDealer(\poll_list);
    }

    #! process messages from the process to the outside world; called only in the main ZeroMQ I/O thread
    private:internal processDataMsg(ZMsg msg, ZSocketRouter data_queue, reference<list<hash<ZmqPollInfo>>> poll_list) {
        # get return mailbox ID (only used with DQ_REQ, DQ_REQOW, and DQ_CANCEL_REQ, ignored with all other commands)
        string id = msg.popStr();
        # get command
        string cmd = msg.popStr();
        #QDBG_LOG("LOOP id: %y cmd: %y", id, cmd);

        switch (cmd) {
            case DQ_TERMINATE: {
                terminateConnectionIntern(\poll_list);

                break;
            }

            case DQ_ABORTED: {
                string proc_id = msg.popStr();
                string restarted = msg.popStr();
                *string new_active_master_id = msg.popStr();
                QDBG_LOG("connection %y aborted%s; restarted %y; sending abort message to outstanding requests: %y", proc_id, new_active_master_id ? sprintf(" (new ID %y)", new_active_master_id) : "", restarted.toBool(), request_map);
                # send aborted message for all outstanding requests
                map ($1.push(DQ_ABORTED), $1.push(restarted), $1.push()), request_map.iterator();
                # clear all outstanding request queues
                remove request_map;

                # remove dealer from poll list
                removeDealer(\poll_list);

                QDBG_LOG("%s: deleting dealer", proc_name);
                # delete the dealer socket first to ensure that the context deletion does not block
                delete dealer;
                QDBG_LOG("%s: deleted dealer", proc_name);
                # reset the context
                ZContext old_ctx = self.ctx;
                ZContext new_ctx();
                AbstractQorusClient::setContextOptions(new_ctx);
                self.ctx = new_ctx;
                QDBG_LOG("%s: deleting old context", proc_name);
                # delete the old context
                delete old_ctx;
                QDBG_LOG("%s: deleted old context", proc_name);
                if (restarted) {
                    if (new_active_master_id) {
                        updateId(new_active_master_id);
                    }
                    # replace dealer socket with new object and new queue URL
                    dealer = self.getNewDealer();

                    poll_list += <ZmqPollInfo>{
                        "socket": dealer,
                        "events": ZMQ_POLLIN,
                    };
                }

                break;
            }

            case DQ_REQOW: {
                QDBG_ASSERT(!request_map{id});
                sendRemoteMsg(dealer, id, msg);
                break;
            }

            case DQ_REQ: {
%ifdef QorusDebugInternals
                # this should never happen, if it does we log info in debug mode
                if (request_map{id}) {
                    QDBG_LOG("ERROR: %s: reuse of ID %y: %y", proc_name, id, request_map);
                    while (*string str = msg.popStr()) {
                        QDBG_LOG("str: %y", str);
                    }
                    QDBG_ASSERT(False);
                }
                if (!dealer) {
                    QDBG_LOG("ERROR: %s: no dealer; id: %y", proc_name, id);
                    while (*string str = msg.popStr()) {
                        QDBG_LOG("str: %y", str);
                    }
                    QDBG_ASSERT(False);
                }
%endif
                # get index for response queue
                string queue_ix = msg.popStr();
                # get queue for response
                Queue response_queue = process.getResponseQueue(queue_ix);
                # there can't be a request already in progress
                QDBG_ASSERT(!request_map{id});
                QDBG_ASSERT(dealer);
                sendRemoteMsg(dealer, id, msg);
                # mark request as in progress
                request_map{id} = response_queue;
                break;
            }

            case DQ_CANCEL_REQ: {
                # reponse queue may no longer be in place if the response was received in the meantime
                QDBG_LOG("cancel request: %y: %y", id, request_map{id});
                remove request_map{id};
                break;
            }


%ifdef QorusDebugInternals
            default: {
                QDBG_LOG("%s: id %y: unknown data queue command received: %y", proc_name, id, cmd);
                QDBG_ASSERT(False);
                break;
            }
%endif
        }
    }

    #! process messages from the outside world to the local process; called only in the main ZeroMQ I/O thread
    private:internal processDealerMsg(ZSocketRouter data_queue) {
        ZMsg msg = dealer.recvMsg();
        # get original mailbox ID
        string id = msg.popStr();

%ifdef QorusDebugMessages
        QDBG_LOG("%s: got response MSG for id: %y request_map: %y size: %d", proc_name, id, keys request_map, msg.contentSize());
%endif
        # ensure that the request exists
        if (!request_map{id}) {
            if (id != "x") {
                log(LoggerLevel::INFO, "%s: response message received with unknown / canceled ID %y; ignoring", proc_name, id);
%ifdef QorusDebugInternals
                int cnt = 0;
                while (exists (*string msgarg = msg.popStr())) {
                    try {
                        auto x = Serializable::deserialize(msgarg);
                        if (x.err && x.desc) {
                            QDBG_LOG("arg %d: %s", cnt++, get_exception_string(x));
                        } else {
                            QDBG_LOG("arg %d: %y", cnt++, x);
                        }
                        continue;
                    } catch () {
                    }
                    QDBG_LOG("arg %d: %s", cnt++, msgarg);
                }
%endif
            }
            return;
        }
        Queue response_queue = remove request_map{id};

        response_queue.push(DQ_REP);

        # must parse message in current thread
        while (exists (*string msgarg = msg.popStr())) {
%ifdef QorusDebugMessages
            try {
                QDBG_LOG("msgarg: %y", !binary(msgarg).find("QS") ? Serializable::deserialize(msgarg) : msgarg);
            } catch (hash<ExceptionInfo> ex) {
                QDBG_LOG("msgarg: cannot deserialize: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            }
%endif
            response_queue.push(msgarg);
        }

        response_queue.push();
    }

    private static setContextOptions(ZContext ctx) {
        ctx.setOption(ZMQ_BLOCKY, 0);
    }

    # handles an aborted process notification by sending a DQ_ABORTED message to the I/O thread
    /** this results in all currently in-progress queue operations being interrupted
        with a CLIENT-ABORTED exception
    */
    private *Counter abortedProcessNotificationIntern(string id, bool restarted, date abort_timestamp,
            *string new_active_master_id) {
        #QDBG_CLOG("client %y: sending DQ_ABORTED for %y", proc_name, id);
        if (!process) {
            return;
        }
        if (!restarted) {
            QDBG_ASSERT(aborted);
            return process.submitClientDataCmdAsync(unique_client_id, DQ_TERMINATE);
        } else {
            return process.submitClientDataCmdAsync(unique_client_id, DQ_ABORTED, id, "1", new_active_master_id);
        }
    }

    private string logUnexpectedResponse(string req_cmd, string expected, *string actual, *list<string> msgs,
        *bool throw_exception) {
        if (actual == CPC_EXCEPTION) {
            try {
                hash<auto> h = qorus_cluster_deserialize(msgs[0]);
                return logException(req_cmd, expected, h.ex, throw_exception);
            } catch (hash<ExceptionInfo> ex) {
                QDBG_LOG("AstractQorusClient::logUnexpectedResponse() %s: request: %y expected: %y got: %y err: %s",
                    proc_name, req_cmd, expected, actual, get_exception_string(ex));
                rethrow;
            }
        }
        string msg = sprintf("%s: request %y: got unexpected reponse %y from server while expecting %y",
                     proc_name, req_cmd, actual, expected);
        error(msg);
        return "ERROR: " + msg;
    }

    private string logException(string req_cmd, string expected, hash<auto> ex, *bool throw_exception) {
        string err = sprintf("ERROR: %s: request %y: expected %y response; server returned exception: %s",
                             proc_name, req_cmd, expected, get_exception_string(ex));
        QDBG_LOG("%s: exception in %y: %s", proc_name, unique_client_id, get_exception_string(ex));
        if (throw_exception) {
            # issue #2653: throw an exception with remote exception information
            # create new exception arg
            hash<auto> new_arg;
            if (ex.arg.typeCode() == NT_HASH) {
                # duplicate any non-chained-exception arg keys in the current exception
                new_arg += (ex.arg - "ex");
            }
            new_arg += {
                "ex": ex,
                "server": proc_name,
            };
            throw ex.err, ex.desc, new_arg;
        }
        return err;
    }

    private:internal ClientDealer getNewDealer() {
        string url = process.getUrls(proc_name)[0];
        QDBG_LOG("%s: creating new dealer with URL: %y", proc_name, url);
        try {
            # FIXME: work with multiple URLs
            ClientDealer dealer(ctx, unique_client_id + "-client-" + getpid() + "-" + gettid(), url, unique_client_id,
                process.getNetworkKeyHelper());
            QDBG_ASSERT(dealer.getOption(ZMQ_LINGER) === 0);
            QDBG_LOG("%s: got new dealer with target URL: %y", proc_name, process.getUrls(proc_name)[0]);
            return dealer;
        } catch (hash<ExceptionInfo> ex) {
            # issue #3606: if this call fails (ex: descriptor exhaustion), then the client must be marked as invalid
            process.submitClientDataCmdSync(unique_client_id, DQ_TERMINATE);
            log(LoggerLevel::INFO, "FATAL ERROR: cannot create client with URL %y: %s: %s", url, ex.err, ex.desc);
            rethrow;
        }
    }

    private:internal static sendRemoteMsg(ClientDealer dealer, string id, ZMsg msg) {
        # issue #3756: check for full outbound queues
        /* if we call send() without checking if the queue is full, then we get a 2 minute timeout,
            which will block the critical I/O thread
        */
        hash<ZmqPollInfo> info = <ZmqPollInfo>{
             "socket": dealer,
            "events": ZMQ_POLLOUT,
        };
        list<hash<ZmqPollInfo>> poll_list = ZSocket::poll((info,), 0);
        #QDBG_LOG("AbstractQorusClient::sendRemoteMsg() %y: %y", id, poll_list);
        if (!poll_list) {
            # issue #3756: we can never block in the I/O thread, if this happens, then the application cluster is
            # unstable; we need to terminate the process immediately - normally there is no active master
            int queue_len = dealer.getOption(ZMQ_SNDHWM);
            Qorus.log(LoggerLevel::FATAL, "FATAL ERROR: the outbound ZeroMQ message queue is full for %y; this normally "
                "only happens when the process has died and there is no active master process for the cluster; in "
                "any case this is fatal error, and this process will exit in 5 seconds");
            sleep(5);
            exit(1);
            #throw "ZEROMQ-QUEUE-ERROR", sprintf("The ZeroMQ outbound queue (size: %d) is full for client %y with "
            #    "message ID %y", queue_len, dealer.unique_client_id, id);
        }

        # reframe message by pushing ID on msg in reverse order
        msg.push(id);
        #QDBG_LOG("sendRemoteMsg() sending MSG for id: %y size: %d", id, msg.contentSize());
        # then send the message
        dealer.send(msg);
    }

    private:internal terminateIoThread() {
        io_cnt.waitForZero();
    }
}

class ClientDealer inherits ZSocketDealer {
    public {
        string unique_client_id;
    }

    constructor(ZContext ctx, string identity, string endpoint, string unique_client_id, NetworkKeyHelper nkh)
        : ZSocketDealer(ctx) {
        QDBG_ASSERT(!getOption(ZMQ_LINGER));
        # set client ID
        self.unique_client_id = unique_client_id;
        # issue #3453: setup encryption before connecting
        nkh.setClient(self);
        # set identity
        setIdentity(identity);
        # connect to remote router
        connect(endpoint);
        # set send timeout to 30s
        setSendTimeout(30s);
    }
}
