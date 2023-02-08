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

# data queue commands
#! terminate the I/O thread
const DQ_TERMINATE = "TERM";
#! remote process aborted
const DQ_ABORTED = "ABORT";
#! make a request
const DQ_REQ = "REQ";
#! make a one-way request
const DQ_REQOW = "REQOW";
#! receive a reply
const DQ_REP = "REP";
#! cancel an active request
const DQ_CANCEL_REQ = "CANCEL";

#! internal msg hash
hashdecl ZmqMsgInfo {
    #! the queue command; see the ZMQIO_* constants
    string queue_cmd;

    #! the remote msg index
    string index;

    #! the sender
    string sender;

    #! the mboxid
    string mboxid;

    #! the API cmd
    string cmd;

    #! any message or command payload
    auto payload;

    #! a Counter for receive synchronization
    /** this Counter is used by submitClientDataCmdSync() to allow the submitter to continue processing
        once the queue thread has processed the request
    */
    *Counter recv_cnt;

    #! a Counter for processing synchronization
    /** this Counter is used by submitClientDataCmdFullSync() to allow the submitter to continue processing
        once the I/O thread has processed the request
    */
    *Counter proc_cnt;

    #! a flag to supress all logging
    /** set to True if the message is sent to support logging
    */
    *bool silent;

    #! The TID of the thread sending the message
    int sending_tid = gettid();
}

# abstract class for clients of Qorus distributed server processes
class AbstractQorusClientProcess inherits AbstractLogger {
    public {}

    private {
        # process id
        string process_id = AbstractQorusClientProcess::generateProcessId();

        # ZeroMQ context
        ZContext zctx();

        # I/O queue
        Queue io_queue();

        # hash with closures / call refs to set up new clients in the event thread
        hash<string, code> client_setup;

        #! hash for synchronous client requests <unique client ID + "-" + tid> -> Queue
        hash<string, Queue> client_req_map;

        #! hash for processing synchronization with msg submittors
        hash<string, Counter> proc_cnt_map;

        # manual process connection setup timestamps; proc id -> timestamp
        hash<string, date> proc_ts_map;
    }

    private:internal {
        # client map: client ID -> client object
        hash<string, AbstractQorusClient> client_map();

        # cluster process URL map: process -> list<string> (URLs)
        hash<string, list<string>> url_map();

        # cluster process URL retrieval block map: process -> True
        hash<string, bool> url_block_map();

        # cluster process URL retrieval thread waiting counts: process -> int
        hash<string, int> url_waiting_map();

        # poll notification list for primary I/O thread
        list<hash<ZmqPollInfo>> poll_list();

        #! to set up clients after the event threads have been started
        hash<string, code> pending_clients;

        # url and client mutex
        Mutex mutex();

        # URL condition variable
        Condition url_cond();

        # event thread counter
        Counter event_cnt();

        # queue thread counter
        Counter queue_cnt();

        #! event thread TID
        int event_tid;

        # internal data queue URL
        const ProcessDataQueueUrl = "inproc://internal-process-data-queue";

        #! ZeroMQ I/O thread command: SEND
        const ZMQIO_RESPONSE = "RESPONSE";

        #! ZeroMQ I/O thread command: QUIT
        const ZMQIO_QUIT = "QUIT";

        #! ZeroMQ I/O thread command: CREATE
        const ZMQIO_CREATE_QUEUE = "CREATE";

        #! ZeroMQ I/O thread command: SEND
        const ZMQIO_SEND = "SEND";

        #! I/O thread marker
        const QorusIoThreadMarker = "_qorus_io_thread";

        #! admin thread marker
        const QorusAdminThreadMarker = "_qorus_admin_thread";
    }

    constructor() {
        zctx.setOption(ZMQ_BLOCKY, 0);
    }

    destructor() {
        stopEventThread();

        # issue #3479: must destroy polled sockets before destroying context
        if (poll_list) {
            map delete poll_list[$#], xrange(poll_list.size());
        }
    }

    ZContext getContext() {
        return zctx;
    }

    private startEventThread() {
        event_cnt.inc();
        event_tid = background startBackgroundIntern();
        # issue #2987: dedicated thread for sending ZeroMQ messages to the event thread
        queue_cnt.inc();
        background startQueueThread();
    }

    # stops the event and I/O threads if they are running
    private stopEventThread() {
        if (event_cnt.getCount()) {
            # delete all clients before stopping the I/O thread
            deleteAllClients();
            io_queue.push(<ZmqMsgInfo>{
                "queue_cmd": ZMQIO_QUIT,
            });

            # wait for threads to exit
            event_cnt.waitForZero();
            queue_cnt.waitForZero();
        }
    }

    #! registers a cluster process URL
    /** @return True if URLs were actually updated
    */
    *bool setUrls(string id, list<string> urls = new list<string>()) {
        #QDBG_LOG("AbstractQorusClientProcess::setUrls() %s: %y", id, urls);
        mutex.lock();
        on_exit mutex.unlock();

        if (url_map{id} != urls) {
            # URLs may be set for this ID in case a client has been reset and now will be recreated
            url_map{id} = urls;

            # update process connection timestamp
            if (urls) {
                proc_ts_map{id} = now_us();
                return True;
            } else {
                # block URL requests until the URL is set
                url_block_map{id} = True;
            }
        }
    }

    /** @return True if URLs were actually updated

        @note this method returns when the changes have been applied, unless called from the primary I/O thread, in
        which case it returns immediately
    */
    *bool setUrls(hash<ClusterProcInfo> info, date abort_timestamp) {
        QDBG_LOG("AbstractQorusClientProcess::setUrls() info: %y abort_timestamp: %y", info, abort_timestamp);
        *bool rv;
        QDBG_ASSERT(info.queue_urls);
        *list<Counter> cl;
        {
            mutex.lock();
            on_exit mutex.unlock();

            if (url_map{info.id} != info.queue_urls && abort_timestamp > proc_ts_map{info.id}) {
                # URLs may be set for this ID in case a client has been reset and now will be recreated
                url_map{info.id} = info.queue_urls;
                # issue #3664: update clients atomically in the lock
                cl = updateClientsInternUnlocked(info.id, info, True, abort_timestamp);

                # update process connection timestamp
                proc_ts_map{info.id} = now_us();
                rv = True;

                # release any block
                if (url_block_map{info.id}) {
                    unblockClientRequestsIntern(info.id);
                }
            }
        }
        # only wait if not in the primary I/O thread
        if (!get_thread_data(QorusIoThreadMarker)) {
            map $1.waitForZero(), cl;
        }
        return rv;
    }

    /** @return True if URLs were actually updated

        @note this method returns when the changes have been applied, unless called from the primary I/O thread, in
        which case it returns immediately
    */
    *bool updateUrls(string old_id, hash<ClusterProcInfo> info, date abort_timestamp, *bool add_unknown) {
        *bool rv;
        *list<Counter> cl;
        {
            mutex.lock();
            on_exit mutex.unlock();

            # ignore updates for processes we are not tracking
            # make sure to update an empty URL list
            if (exists url_map{old_id} || add_unknown) {
                # only update URLs if:
                # 1) a URL is present in the message
                # 2) the URL is different than the cached URL
                # 3) the abort happened after the last update for the given process
                bool update_urls = info.queue_urls
                    && ((add_unknown && !url_map{old_id})
                        || (url_map{old_id} != info.queue_urls
                            && proc_ts_map{old_id} < abort_timestamp));

                if (update_urls) {
                    url_map{old_id} = info.queue_urls;
                    # update process connection timestamp
                    proc_ts_map{old_id} = now_us();

                    if (old_id != info.id) {
                        # the only time we can change the ID of a client is when the active master is updated
                        QDBG_ASSERT(info.new_active_master_id);
                        url_map{info.id} = remove url_map{old_id};
                        proc_ts_map{info.id} = remove proc_ts_map{old_id};

                        # release any block
                        if (url_block_map{old_id}) {
                            unblockClientRequestsIntern(old_id);
                        }
                    }

                    # release any block
                    if (url_block_map{info.id}) {
                        unblockClientRequestsIntern(info.id);
                    }

                    # issue #3664: update clients atomically in the lock
                    cl = updateClientsInternUnlocked(old_id, info, True, abort_timestamp);
                    rv = True;
%ifdef QorusDebugInternals
                } else {
                    QDBG_LOG("AbstractQorusClientProcess::updateUrls(%y, %y, %y) ignoring update (cached ts: %y)", old_id, info, abort_timestamp, proc_ts_map{old_id});
%endif
                }
%ifdef QorusDebugInternals
            } else {
                QDBG_LOG("AbstractQorusClientProcess::updateUrls(%y, %y, %y) ignoring update; unknown ID", old_id, info, abort_timestamp);
%endif
            }
        }
        # only wait if not in the primary I/O thread
        if (!get_thread_data(QorusIoThreadMarker)) {
            map $1.waitForZero(), cl;
        }
        return rv;
    }

    # updates a cluster process's URL list if it is already registered
    /** @return True if URLs were actually updated
    */
    *bool updateUrls(string id, *list<string> urls, *string new_id) {
        #QDBG_LOG("AbstractQorusClientProcess::updateUrls() %s: %y", id, urls);
        *bool rv;
        mutex.lock();
        on_exit mutex.unlock();

        # ignore updates for processes we are not tracking
        # make sure to update an empty URL list
        if (exists url_map{id}) {
            if (urls && url_map{id} != urls) {
                url_map{id} = urls;
                # update process connection timestamp
                proc_ts_map{id} = now_us();
                rv = True;

                # release any block
                if (url_block_map{id}) {
                    unblockClientRequestsIntern(id);
                }
            }

            if (new_id) {
                url_map{new_id} = remove url_map{id};
            }
        }
        return rv;
    }

    # updates a cluster process's URL list if it hasn't already been updated
    /** @return True if URLs were actually updated

        @note this method returns when the changes have been applied, unless called from the primary I/O thread, in
        which case it returns immediately
    */
    *bool updateUrlsConditional(hash<ClusterProcInfo> info) {
        #QDBG_LOG("AbstractQorusClientProcess::updateUrlsConditional() %s: %y", id, urls);
        *bool rv;
        QDBG_ASSERT(info.queue_urls);
        *list<Counter> cl;
        {
            mutex.lock();
            on_exit mutex.unlock();

            # ignore updates for processes with already updated URLs
            if (!url_map{info.id} && url_map{info.id} != info.queue_urls) {
                url_map{info.id} = info.queue_urls;

                # update process connection timestamp
                proc_ts_map{info.id} = now_us();

                # issue #3664: update clients atomically in the lock
                cl = updateClientsInternUnlocked(info.id, info, True, now_us());
                rv = True;

                # release any block
                if (url_block_map{info.id}) {
                    unblockClientRequestsIntern(info.id);
                }
            }
        }
        # only wait if not in the primary I/O thread
        if (!get_thread_data(QorusIoThreadMarker)) {
            map $1.waitForZero(), cl;
        }
        return rv;
    }

    # updates a cluster process's URL list if it hasn't already been updated
    /** @return True if URLs were actually updated
    */
    *bool updateUrlsConditional(string id, list<string> urls) {
        #QDBG_LOG("AbstractQorusClientProcess::updateUrlsConditional() %s: %y", id, urls);
        mutex.lock();
        on_exit mutex.unlock();

        # ignore updates for processes with already updated URLs
        if (!url_map{id} && url_map{id} != urls) {
            url_map{id} = urls;

            # release any block
            if (url_block_map{id}) {
                unblockClientRequestsIntern(id);
            }

            return True;
        }
    }

    # removes URLs for the given process (for example when the process is stopped)
    /** @return True if URLs were actually updated

        @note this method returns when the changes have been applied, unless called from the primary I/O thread, in
        which case it returns immediately
    */
    *bool removeUrls(string id, date abort_timestamp) {
        #QDBG_LOG("AbstractQorusClientProcess::removeUrls() %s", id);
        *bool rv;
        *list<Counter> cl;
        {
            mutex.lock();
            on_exit mutex.unlock();

            if (url_map{id} && proc_ts_map{id} < abort_timestamp) {
                remove url_map{id};
                # issue #3664: update clients atomically in the lock
                cl = updateClientsInternUnlocked(id, NOTHING, False, abort_timestamp);
                remove proc_ts_map{id};
                rv = True;
                QDBG_LOG("AbstractQorusClientProcess::removeUrls() removed URLs for %y (%y)", id, abort_timestamp);
            }
        }
        # only wait if not in the primary I/O thread
        if (!get_thread_data(QorusIoThreadMarker)) {
            map $1.waitForZero(), cl;
        }
        return rv;
    }

    # invalidates the URL for the given process (for example when the process is stopped but is a critical process)
    /** @return True if URLs were actually invalidated

        @note this method returns when the changes have been applied, unless called from the primary I/O thread, in
        which case it returns immediately
    */
    *bool invalidateUrls(string id, date abort_timestamp) {
        #QDBG_LOG("AbstractQorusClientProcess::removeUrls() %s", id);
        *bool rv;
        *list<Counter> cl;
        {
            mutex.lock();
            on_exit mutex.unlock();

            if (url_map{id} && proc_ts_map{id} < abort_timestamp) {
                url_map{id} = ();
                # issue #3664: update clients atomically in the lock
                cl = updateClientsInternUnlocked(id, NOTHING, False, abort_timestamp);
                remove proc_ts_map{id};
                rv = True;
                QDBG_LOG("AbstractQorusClientProcess::invalidateUrls() invalidated URLs for %y (%y)", id, abort_timestamp);
            }
        }
        # only wait if not in the primary I/O thread
        if (!get_thread_data(QorusIoThreadMarker)) {
            map $1.waitForZero(), cl;
        }
        return rv;
    }

    # gets an updated URL
    list<string> getUrls(string id) {
        mutex.lock();
        on_exit mutex.unlock();

        # wait for client type to become unblocked
        while (url_block_map{id}) {
            ++url_waiting_map{id};
            url_cond.wait(mutex);
            --url_waiting_map{id};
        }

        auto rv = url_map{id};
        if (!rv) {
            throw "URL-ERROR", sprintf("no local URL available for cluster process %y; locally known processes: %y",
                id, keys url_map);
        }

        return cast<list<string>>(rv);
    }

    # registers a client
    registerClient(AbstractQorusClient c) {
        mutex.lock();
        on_exit mutex.unlock();

        if (client_map{c.getClientId()})
            throw "CLIENT-ERROR", sprintf("client %y already registered with this process; registered clients: %y",
                c.getClientId(), keys client_map);

        # take a weak reference to the client object to ensure that it
        # goes out of scope naturally; the destructor deregisters the client
        # with this object in any case
        client_map{c.getClientId()} := c;
    }

    # deregister a client
    deregisterClient(AbstractQorusClient client, string id, *bool remove_queue) {
        if (remove_queue) {
            # remove the client's queue
            # issue #3229 handle synchronously if in I/O thread
            if (get_thread_data(QorusIoThreadMarker)) {
                # if a race conditions occurs, the destructor for the client object can be run in the I/O thread as
                # the object goes out of scope after a msg call, in this case we need to deregister the object
                # directly, as this call is made from the client's destructor in any case
                QDBG_LOG("processing inline removal of client %y", id);
                client.terminateAllConnections();
                client.removeDealer(\poll_list);
            } else {
                QDBG_LOG("processing removal of client %y", id);
                submitClientDataCmdSyncFull(id, DQ_TERMINATE);
            }
        }

        # issue #2647: may be called while already holding the lock
        bool lck = !mutex.lockOwner();
        if (lck) {
            mutex.lock();
        }
        on_exit if (lck) {
            mutex.unlock();
        }

        remove client_map{id};
    }

    #! Returns True if the current thread is the main process I/O thread
    bool isIoThread() {
        return get_thread_data(QorusIoThreadMarker) ?? False;
    }

    # blocks URL retrieval for the given process
    blockClientRequests(string proc_name) {
        mutex.lock();
        on_exit mutex.unlock();

        if (url_block_map{proc_name})
            throw "BLOCK-ERROR", sprintf("process %y is already blocked (%y)", proc_name, url_block_map);

        url_block_map{proc_name} = True;
    }

    # unblocks URL retrieval for the given process
    unblockClientRequests(string proc_name, *bool no_error) {
        mutex.lock();
        on_exit mutex.unlock();

        if (!url_block_map{proc_name}) {
            if (no_error) {
                return;
            }
            throw "UNBLOCK-ERROR", sprintf("client type %y is not blocked (%y)", proc_name, url_block_map);
        }

        unblockClientRequestsIntern(proc_name);
        # remove any temporary URL placeholder
        if (no_error && url_map{proc_name} == ()) {
            remove url_map{proc_name};
        }
    }

    private unblockClientRequestsIntern(string proc_name) {
        QDBG_ASSERT(mutex.trylock());

        delete url_block_map{proc_name};
        if (url_waiting_map{proc_name}) {
            url_cond.broadcast();
        }
    }

    # handles an aborted process notification
    abortedProcessNotification(string id, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        log(LoggerLevel::INFO, "cluster process aborted notification: %y restarted: %y abort timestamp: %y", id,
            restarted, abort_timestamp);
    }

    # handles detaching a process
    private detachProcessIntern(string id, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        *list<Counter> cl;
        {
            mutex.lock();
            on_exit mutex.unlock();

            cl = updateClientsInternUnlocked(id, info, restarted, abort_timestamp);
        }
        # only wait if not in the primary I/O thread
        if (!get_thread_data(QorusIoThreadMarker)) {
            map $1.waitForZero(), cl;
        }
    }

    private *list<Counter> updateClientsInternUnlocked(string id, *hash<ClusterProcInfo> info, bool restarted,
            date abort_timestamp) {
        *list<Counter> cl;
        # notify all clients that the process was aborted
        # issue #2647: clients can be deleted at any time
        foreach hash<auto> i in (client_map.pairIterator()) {
            try {
                *Counter c = i.value.abortedProcessNotification(id, info, restarted, abort_timestamp);
                if (c) {
                    cl += c;
                }
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "OBJECT-ALREADY-DELETED") {
                    remove client_map{i.key};
                    QDBG_LOG("removed deleted client %y", i.key);
                } else {
                    rethrow;
                }
            }
        }
        return cl;
    }

    # returns the unique process ID for this process
    string getProcessId() {
        return process_id;
    }

    # deletes all known clients
    deleteAllClients() {
        on_exit QDBG_LOG("deleteAllClients() done");
        foreach AbstractQorusClient c in (client_map.iterator()) {
            AbstractQorusClient client = c;
%ifdef QorusDebugInternals
            try {
                QDBG_LOG("deleteAllClients() deleting client %y", client.getClientId());
            } catch (hash<ExceptionInfo> ex) {
                # issue #3211: ignore OBJECT-ALREADY-DELETED errors
                if (ex.err != "OBJECT-ALREADY-DELETED") {
                    rethrow;
                }
            }
%endif
            delete client;
        }
        remove client_map;
    }

    #! sets up a dealer queue for a new client in the event thread
    createClientQueue(string unique_client_id, code setupQueue) {
        QDBG_LOG("creating client queue for client: %y", unique_client_id);
        client_setup{unique_client_id} = setupQueue;
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_CREATE_QUEUE,
            "payload": unique_client_id,
        });
    }

%ifdef QorusDebugInternals
    static string logRequestArgs(*list<auto> args) {
        return "["
            + (foldl $1 + "," + $2, (map sprintf("%y", $1.typeCode() == NT_BINARY && !$1.find("QS") ? Serializable::deserialize($1) : $1), args))
            + "]";
    }
%endif

    #! submits a command for processing for the given client in the event thread; no logging allowed
    submitClientDataCmdSilent(string unique_client_id, string cmd) {
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_SEND,
            "cmd": cmd,
            "payload": {
                "unique_client_id": unique_client_id,
                "args": argv,
            },
            "silent": True,
        });
    }

    #! submits a command for processing for the given client in the event thread
    submitClientDataCmd(string unique_client_id, string cmd) {
        # we cannot log here or it will cause an infinite loop when log msgs are reported over the network for example
        #QDBG_LOG("client data cmd: %y: %y args: %y", unique_client_id, cmd, logRequestArgs(argv));
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_SEND,
            "cmd": cmd,
            "payload": {
                "unique_client_id": unique_client_id,
                "args": argv,
            }
        });
    }

    #! submits a command for processing for the given client in the event thread
    /** does not return until the command has been processed in the ZeroMQ I/O thread
    */
    submitClientDataCmdSync(string unique_client_id, string cmd) {
        QDBG_LOG("client sync data cmd: %y: %y args: %y", unique_client_id, cmd, logRequestArgs(argv));
        Counter cnt(1);
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_SEND,
            "cmd": cmd,
            "payload": {
                "unique_client_id": unique_client_id,
                "args": argv,
            },
            "recv_cnt": cnt,
        });
        cnt.waitForZero();
    }

    #! submits a command for processing for the given client in the event thread
    /** returns a Counter that will trigger when the command has been processed in the ZeroMQ I/O thread
    */
    Counter submitClientDataCmdAsync(string unique_client_id, string cmd) {
        QDBG_LOG("client sync data cmd: %y: %y args: %y", unique_client_id, cmd, logRequestArgs(argv));
        Counter cnt(1);
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_SEND,
            "cmd": cmd,
            "payload": {
                "unique_client_id": unique_client_id,
                "args": argv,
            },
            "recv_cnt": cnt,
        });
        return cnt;
    }

    #! submits a command for processing for the given client in the event thread; does not return until the command has been processed in the ZeroMQ event thread
    submitClientDataCmdSyncFull(string unique_client_id, string cmd) {
        QDBG_LOG("client sync data cmd: %y: %y args: %y", unique_client_id, cmd, logRequestArgs(argv));
        Counter cnt(1);
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_SEND,
            "cmd": cmd,
            "payload": {
                "unique_client_id": unique_client_id,
                "args": argv,
            },
            "proc_cnt": cnt,
        });
        cnt.waitForZero();
    }

    #! submits a command for processing for the given client in the event thread
    /** this is the request-reply method; the response will be put in the response_queue arg
    */
    submitClientRequest(string unique_client_id, Queue response_queue) {
%ifdef QorusDebugMessages
        QDBG_LOG("client request: %y: argv: %y", unique_client_id, logRequestArgs(argv));
%endif
        string request_index = getRequestId(unique_client_id);
%ifdef QorusDebugInternals
        if (client_req_map{request_index}) {
            QDBG_LOG("ERROR: request index %y has response queue %y in place already (new queue: %y)", request_index, client_req_map{request_index}.uniqueHash(), response_queue.uniqueHash());
        }
%endif
        QDBG_ASSERT(!client_req_map{request_index});
        client_req_map{request_index} = response_queue;
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_SEND,
            "index": request_index,
            "cmd": DQ_REQ,
            "payload": {
                "unique_client_id": unique_client_id,
                # we need to ensure that the response queue index is the first argument
                "args": (request_index,) + (argv ?? ()),
            },
        });
    }

    #! Cancels an in-progress request
    /** Only returns when the main I/O thread has canceled the request
    */
    cancelRequest(string unique_client_id, string request_index) {
        Counter cnt(1);
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_SEND,
            "index": request_index,
            "cmd": DQ_CANCEL_REQ,
            "payload": {
                "unique_client_id": unique_client_id,
            },
            "proc_cnt": cnt,
        });
        cnt.waitForZero();
    }

    #! returns a unique request ID
    string getRequestId(string unique_client_id) {
        return unique_client_id + "-" + gettid().toString();
    }

    # get queue for response
    Queue getResponseQueue(string queue_ix) {
%ifdef QorusDebugInternals
        if (!client_req_map{queue_ix}) {
            QDBG_LOG("ERROR: getResponseQueue(%y) client_req_map: %y", queue_ix, client_req_map);
        }
%endif
        return remove client_req_map{queue_ix};
    }

    private startQueueThread() {
        on_exit {
            log(LoggerLevel::INFO, "terminating ZeroMQ queue thread");
            queue_cnt.dec();
        }

        log(LoggerLevel::INFO, "started ZeroMQ queue thread");

        # the default timeout is OK
        ZSocketDealer sock(zctx, gettid().toString(), ">" + ProcessDataQueueUrl);

        bool quit;
        while (!quit) {
            hash<ZmqMsgInfo> msg;
            try {
                msg = io_queue.get();
%ifdef QorusDebugMessages
                if (!msg.silent) QDBG_LOG("data queue msg: %y", msg);
%endif
                on_exit if (msg.recv_cnt) {
                    msg.recv_cnt.dec();
                }

                switch (msg.queue_cmd) {
                    case ZMQIO_RESPONSE:
                        sock.send(msg.queue_cmd, msg.index, msg.sender, msg.mboxid, msg.cmd, msg.payload);
                        break;

                    case ZMQIO_QUIT:
                        sock.send(msg.queue_cmd);
                        quit = True;
                        break;

                    case ZMQIO_CREATE_QUEUE: {
                        sock.send(msg.queue_cmd, msg.payload);
                        break;
                    }

                    case ZMQIO_SEND: {
                        string proc_cnt_index;
                        if (msg.proc_cnt) {
                            proc_cnt_index = msg.sending_tid.toString();
                            proc_cnt_map{proc_cnt_index} = msg.proc_cnt;
                        } else {
                            proc_cnt_index = "x";
                        }
                        list<auto> call_args = (msg.queue_cmd, proc_cnt_index, msg.payload.unique_client_id,
                            msg.index ?? "x", msg.cmd) + (msg.payload.args ?? ());
                        call_function_args(\sock.send(), call_args);
                        break;
                    }

                    default:
                        throw "UNKNOWN-QUEUE-CMD", sprintf("msg: %y", msg);
                }

                # issue #2987: to work around a memory leak with inproc sockets, we perform a read operation on them
                # and ignore the response; the read operation is only used to ensure that file descriptors are
                # released
                # see https://github.com/zeromq/libzmq/issues/792

                # issue #3716: do not allow this call to time out, but log the event thread's call stack
                while (True) {
                    try {
                        sock.recvMsg();
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "ZSOCKET-TIMEOUT-ERROR") {
                            log(LoggerLevel::WARN, "timeout in ZeroMQ queue thread: msg: %y: %s", msg,
                                get_exception_string(ex));
                            *list<hash<CallStackInfo>> stack = get_all_thread_call_stacks(){event_tid};
                            *list<string> stack_str = map
                                $1.type != "new-thread"
                                    ? sprintf("%s %s()", get_ex_pos($1), $1.function)
                                    : "new-thread",
                                stack;
                            log(LoggerLevel::WARN, "event thread: %N", stack_str);
                            log(LoggerLevel::WARN, "this timeout could be a result of an active master outage or "
                                "system thrashing; continuing waiting for response from event thread");
                            continue;
                        }
                        rethrow;
                    }
                    break;
                }
            } catch (hash<ExceptionInfo> ex) {
                if (!msg.silent) {
                    log(LoggerLevel::ERROR, "unexpected exception in ZeroMQ queue thread: msg: %y: %s", msg,
                        get_exception_string(ex));
                }
            }
        }
    }

    private startBackgroundIntern() {
        log(LoggerLevel::INFO, "started ZeroMQ primary I/O thread");

        on_exit {
            log(LoggerLevel::INFO, "terminating ZeroMQ primary I/O thread");
            event_cnt.dec();
        }

        # issue #3229 mark I/O thread
        save_thread_data(QorusIoThreadMarker, True);

        # map of closures / call refs for client msg processing;
        # unique client ID -> {data|dealer} -> code (handler)
        hash<string, hash<string, code>> client_handler_map;

        # list of ZSocketRouter objects for all interfaces
        list<ZSocketRouter> router_list = createRouters(\poll_list);

        # the default timeout is OK because we use polling
        ZSocketRouter dq(zctx, "internal-data-queue", "@" + ProcessDataQueueUrl);
        dq.setOption(ZMQ_ROUTER_HANDOVER, 1);

        # add sockets to poll notification list
        poll_list += (
            new hash<ZmqPollInfo>({
                "socket": dq,
                "events": ZMQ_POLLIN,
            }),
        );

        bool run = True;
        while (run) {
            try {
                # poll for data
                list<hash<ZmqPollInfo>> lr = ZSocket::poll(poll_list, -1);

                foreach hash<ZmqPollInfo> pi in (lr) {
                    try {
                        #QDBG_LOG("pi.socket: %y dq: %y", pi.socket.className(), pi.socket == dq);
                        if (pi.socket == dq) {
                            ZMsg msg = dq.recvMsg();
                            # issue #2987: to work around a memory leak with inproc sockets, we perform a read
                            # operation on the sending (client) side and ignore the response; the read operation
                            # is only used to ensure that file descriptors are released, so we need to send a
                            # response here; the message is sent after the command has been processed in this thread
                            # see https://github.com/zeromq/libzmq/issues/792
                            # get the identity of the sender
                            string id = msg.popStr();
                            on_exit {
                                dq.send(id, "x");
                            }
                            # get queue cmd
                            string cmd_code = msg.popStr();
                            #QDBG_LOG("CMD_CODE: %y", cmd_code);
                            switch (cmd_code) {
                                case ZMQIO_QUIT: {
                                    log(LoggerLevel::INFO, "command received on queue: %y", cmd_code);
                                    run = False;
                                    break;
                                }

                                case ZMQIO_CREATE_QUEUE: {
                                    # create a client router queue
                                    string unique_client_id = msg.popStr();
                                    code client_setup = remove self.client_setup{unique_client_id};
                                    QDBG_LOG("queue cmd: %y: id: %y setup: %y", cmd_code, unique_client_id, client_setup);
                                    poll_list += client_setup(\client_handler_map);
                                    break;
                                }

                                case ZMQIO_SEND: {
                                    # get process Counter index, if any
                                    string proc_cnt_index = msg.popStr();
                                    # signal submitted to continue if necessary
                                    on_exit {
                                        if (proc_cnt_index != "x") {
                                            (remove proc_cnt_map{proc_cnt_index}).dec();
                                        }
                                    }
                                    # process an incoming message on the client data queue
                                    string unique_client_id = msg.popStr();
                                    #QDBG_LOG("queue cmd: %y: id: %y", cmd_code, unique_client_id);
                                    *code client_process_data_msg = client_handler_map{unique_client_id}."data";
                                    if (!client_process_data_msg) {
                                        # this error can happen if file/socket descriptors are exhausted
                                        log(LoggerLevel::INFO, "cannot process message for unknown client %y; known clients: %y",
                                            unique_client_id, keys client_handler_map);
                                        continue;
                                    }

                                    client_process_data_msg(msg, dq, \poll_list);
                                    break;
                                }

                                case ZMQIO_RESPONSE: {
                                    # get router index for response
                                    softint index = msg.popStr();
                                    string sender = msg.popStr();
                                    string mboxid = msg.popStr();
                                    string cmd = msg.popStr();
                                    ZSocketRouter router = router_list[index];
%ifdef QorusDebugMessages
                                    QDBG_LOG("sending response to sender: %y %y cmd: %y", sender, mboxid, cmd);
%endif
                                    try {
                                        router.send(sender, mboxid, cmd, msg.popBin());
                                    } catch (hash<ExceptionInfo> ex) {
                                        error("exception sending response cmd: %y to sender: %y %y: %s", cmd,
                                            sender, mboxid, get_exception_string(ex));
                                        continue;
                                    }
                                    break;
                                }

                                default:
                                    QDBG_LOG("invalid cmd submitted to queue: %y", cmd_code);
                                    QDBG_ASSERT(False);
                                    break;
                            }
                        } else if (pi.socket instanceof ClientDealer) {
                            string unique_client_id = cast<ClientDealer>(pi.socket).unique_client_id;
                            client_handler_map{unique_client_id}.dealer(dq);
                            break;
                        } else {
                            QDBG_ASSERT(pi.socket instanceof ZSocketRouter);
                            handleRouterMsg(pi.socket);
                        }
                    } catch (hash<ExceptionInfo> ex) {
                        string errstr = Qorus.getDebugSystem()
                            ? get_exception_string(ex)
                            : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                        error("%s", errstr);
                    }
                }
            } catch (hash<ExceptionInfo> ex) {
                string errstr = Qorus.getDebugSystem()
                    ? get_exception_string(ex)
                    : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                error("%s", errstr);
            }
        }
        log(LoggerLevel::INFO, "shutdown command received");
    }

    # can be overridden by subclasses to use informaetion in "h" in the response
    private hash getSerializationException(hash<auto> h, hash<ExceptionInfo> ex) {
        return {"ex": ex};
    }

    private hash getSerializationException(hash<ExceptionInfo> ex) {
        return {"ex": ex};
    }

    # queues the message to be sent to the remote target
    /** @param index socket index for the response
        @param sender sender's ID
        @param cmd the Qorus cluster API command
        @param val the optional payload for the response
    */
    private sendAnyResponse(softstring index, string sender, string mboxid, string cmd, auto val, *bool already_serialized) {
        *data payload = already_serialized
            ? val
            : (exists val
                ? serializeAnyResponse(\cmd, val)
                : NOTHING);
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_RESPONSE,
            "index": index,
            "sender": sender,
            "mboxid": mboxid,
            "cmd": cmd,
            "payload": payload,
        });
    }

    # queues the message to be sent to the remote target
    /** @param index socket index for the response
        @param sender sender's ID
        @param cmd the Qorus cluster API command
        @param h the optional payload for the response
        @param sctx an optional send context hash in case of exception handling; only used in subclasses
    */
    private sendResponse(softstring index, string sender, string mboxid, string cmd, *hash<auto> h, *hash<auto> sctx) {
        *data payload = h ? serializeResponse(\cmd, h, sctx) : NOTHING;
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_RESPONSE,
            "index": index,
            "sender": sender,
            "mboxid": mboxid,
            "cmd": cmd,
            "payload": payload,
        });
    }

    # queues the message to be sent to the remote target
    /** @param index socket index for the response
        @param sender sender's ID
        @param ex the exception to send
        @param sctx an optional send context hash in case of exception handling; only used in subclasses
    */
    private sendExceptionResponse(softstring index, string sender, string mboxid, hash<auto> ex, *hash<auto> sctx) {
        *data payload = serializeExceptionResponse(ex, sctx);
        io_queue.push(<ZmqMsgInfo>{
            "queue_cmd": ZMQIO_RESPONSE,
            "index": index,
            "sender": sender,
            "mboxid": mboxid,
            "cmd": CPC_EXCEPTION,
            "payload": payload,
        });
    }

    private data serializeAnyResponse(reference<string> cmd, auto val) {
        data d;
        try {
            d = qorus_cluster_serialize(val);
        } catch (hash<ExceptionInfo> ex) {
            # data here can be very large - only usable when debugging
            #QDBG_LOG("%s: %s: %y", ex.err, ex.desc, val);
            cmd = CPC_EXCEPTION;
            d = qorus_cluster_serialize(getSerializationException(ex));
        }
        return d;
    }

    # AbstractQorusClientProcess
    static private checkException(reference<auto> ex) {
        if (ex.typeCode() != NT_HASH) {
            return;
        }
        if (ex.arg.typeCode() == NT_OBJECT && !(ex.arg instanceof Serializable)) {
            try {
                ex.arg = sprintf("class %y", ex.arg.className());
                if (ex.arg.hasCallableMethod("getMessage")) {
                    ex.arg += ": " + ex.arg.getMessage();
                }
            } catch (hash<ExceptionInfo> ex) {
                # ignore exceptions
            }
        } else {
            if (ex.arg.ex.arg) {
                AbstractQorusClientProcess::checkException(\ex.arg.ex.arg);
            }
        }
        if (ex.next.arg) {
            AbstractQorusClientProcess::checkException(\ex.next.arg);
        }
    }

    private data serializeExceptionResponse(hash<auto> ex, *hash<auto> sctx) {
        if (ex.arg) {
            checkException(\ex);
        }
        data d;
        try {
            d = qorus_cluster_serialize({"ex": ex});
        } catch (hash<ExceptionInfo> ex1) {
            d = qorus_cluster_serialize(getSerializationException({"ex": ex}, ex1));
        }
        return d;
    }

    private data serializeResponse(reference<string> cmd, hash<auto> h, *hash<auto> sctx) {
        data d;
        try {
            d = qorus_cluster_serialize(h);
        } catch (hash<ExceptionInfo> ex) {
            cmd = CPC_EXCEPTION;
            d = qorus_cluster_serialize(getSerializationException(h, ex));
        }
        return d;
    }

    # create the local router queues
    abstract list<ZSocketRouter> createRouters(reference<list<hash<ZmqPollInfo>>> poll_list);

    # handle messages from local routers
    abstract handleRouterMsg(ZSocketRouter router);

    # returns the unique network ID
    abstract string getNetworkId();

    # returns the NetworkKeyHelper object
    abstract NetworkKeyHelper getNetworkKeyHelper();

    # returns a unique ID for the process
    static string generateProcessId() {
        return sprintf("%s-%s-%d", gethostname(), get_script_name(), getpid());
    }
}
