# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

public namespace OMQ;

%ifdef QorusServer
%new-style
%endif

#! provides info about the stream
class OMQ::StreamInfo {
    public {
        #! start time
        date start;
        #! end time
        date end;
        #! total elapsed time
        date delta;
        #! row count / bytes
        int count;
        #! data per second
        float dps;
        #! total row count / bytes
        int total_count;
    }

    #! sets the start time
    setStart() {
        start = now_us();
    }

    #! sets the end time and calculates total elapsed time
    setEnd() {
        end = now_us();
        delta = end - start;
        # calculate data/s
        float dt = delta.durationSecondsFloat();
        dps = dt ? count / dt : 0;
    }

    reset() {
        start = now_us();
        delete end;
        delete delta;
        delete count;
        delete dps;
    }
}

#! stream configuration class
/** default values:
    - \c m_timeout: \c 5m
    - \c m_loglevel: @ref Logger::LoggerLevel::INFO "LoggerLevel::INFO"
*/
public class OMQ::StreamConfig {
    #! no public members
    public {}

    private {
        #! the remote sqlutil service stream
        string m_stream;
        #! real remote rest helper
        QorusSystemRestHelper m_remote;

        #! timeout for rest connections
        timeout m_timeout = 5m;
        #! flag to suppress sending the timeout option to the remote
        bool m_no_remote_timeout = False;
        #! default log level; default @ref Logger::LoggerLevel::INFO "LoggerLevel::INFO"
        int m_logLevel = LoggerLevel::INFO;
        #! block size
        softint m_block;
    }

    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server
    /**
        @param stream a string giving the name of the stream that will be used
        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
    */
    constructor(string stream, string remote, *hash<auto> options) {
        m_stream = stream;
        setOptions(options);

        logger("named remote stream: %s", remote);
        m_remote = UserApi::getRemoteRestConnection(remote);
        # issue #1915: set HTTP timeout on remote connection object
        if (m_timeout)
            m_remote.setTimeout(m_timeout);
        m_remote.setPersistent();
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection
    /**
        @param stream a string giving the name of the stream that will be used
        @param remote a @ref OMQ::QorusSystemRestHelper object
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
    */
    constructor(string stream, QorusSystemRestHelper remote, *hash<auto> options) {
        m_stream = stream;
        setOptions(options);

        logger("remote stream using url: %s", remote.getURL());
        m_remote = remote;
        # issue #1915: set HTTP timeout on remote connection object
        if (m_timeout)
            m_remote.setTimeout(m_timeout);
        # ensure remote is connected before calling HTTPClient::setPersistent()
        if (!m_remote.isConnected())
            m_remote.connect();
        m_remote.setPersistent();
    }

    #! logs the stream configuration when created
    logStreamConfig(string what) {
        # do not show user/pass in log files
        string url = regex_subst(m_remote.getURL(), "\:\/\/.*\@", "://");
        logStreamConfigImpl(what, url);
    }

    #! logs the stream configuration when created
    logStreamConfigImpl(string what, string url) {
        logger("%s %y stream url: %y", what, m_stream, url);
    }

    #! sets configuration values from an optional option hash
    private setOptions(*hash<auto> options) {
        m_timeout = options.timeout ?* 5m;
%ifdef QorusServer
        if (options.logLevel) {
            m_logLevel = convert_old_log_level(options.loglevel);
        }
%endif
        m_block = options.block > 0 ? options.block : getDefaultBlockSize();
        m_no_remote_timeout = boolean(options."no_remote_timeout") ?? False;
    }

    #! returns the stream name
    string stream() {
        return m_stream;
    }

    #! returns a description of the stream for error reporting
    string streamDesc() {
        return sprintf("%y stream", m_stream);
    }

    #! returns the remote connection object (see @ref OMQ::QorusSystemRestHelper)
    QorusSystemRestHelper remote() {
        return m_remote;
    }

    #! returns the timeout value in milliseconds
    timeout timeout() {
        return m_timeout;
    }

    #! returns the block size
    int block() {
        return m_block;
    }

    #! returns @ref True if no \c "timeout" option should be sent to the remote
    bool suppressRemoteTimeout() {
        return m_no_remote_timeout;
    }

    logger(string message) {
        loggerImpl(m_logLevel, vsprintf(message, argv));
    }

    debug(string message) {
        loggerImpl(LoggerLevel::DEBUG, vsprintf(message, argv));
    }

    #! updates the configuration for a new stream
    update(string stream, *hash<auto> options) {
        m_stream = stream;
        if (options) {
            if (options.timeout)
                m_timeout = options.timeout;
            if (options.loglevel)
                m_logLevel = options.loglevel;
            if (options.block > 0)
                m_block = options.block;
            if (options.hasKey("no_remote_timeout"))
                m_no_remote_timeout = boolean(options."no_remote_timeout");
        }
    }

    private loggerImpl(int level, string message) {
        message = "Streams: " + message;
%ifdef QorusServer
        UserApi::logWithLevelArgs(level, message, argv);
%else
        if (level < m_logLevel)
            vprintf(message+"\n", argv);
%endif
    }

    #! returns the default block size for this object (1000)
    private int getDefaultBlockSize() {
        return 1000;
    }
} # class StreamConfig

#! base configuration for DB streams
public class OMQ::DbStreamConfigBase {
    private {
        # the @ref dsconn "datasource" connection name in the remote server
        string m_datasource;
        # the remote table name (if not a raw stream)
        *string m_tableName;
    }

    #! creates the object and assigns config info
    /** @param datasource the @ref dsconn "datasource" connection name in the remote server
        @param tablename the remote table name
     */
    constructor(string datasource, *string tablename) {
        m_datasource = datasource;
        m_tableName = tablename;
    }

    #! returns the the @ref dsconn "datasource" connection name in the remote server
    string datasource() {
        return m_datasource;
    }

    #! returns the table name
    *string tableName() {
        return m_tableName;
    }

    #! updates the configuration for a new stream
    update(string tablename) {
        m_tableName = tablename;
    }
}

#! common base class for streams using a background thread for socket I/O
public class OMQ::AbstractParallelStream inherits Qore::Thread::AbstractThreadResource {
    private {
        #! Queue for the socket I/O thread
        Qore::Thread::Queue dataq;

        #! confirmation counter for the socket I/O thread
        Qore::Thread::Counter cnt();

        #! exception info for send thread to communicate errors to the primary data thread
        *hash<auto> thread_ex;

        #! stream information
        OMQ::StreamInfo m_info();

        #! stream object identifier
        string objid;

        #! stream terminated error
        const StreamTerminatedError = "STREAM-TERMINATED";

        #! thread-local data key
        const ThreadKey = "_STREAM_";
    }

    public {
        #! A constant for rollback() methods to perform real disconnect
        const DO_DISCONNECT = True;
        #! A constant for rollback() methods to keep the network connection alive
        const DONT_DISCONNECT = False;
    }

    #! wait for any I/O in progress to complete
    destructor() {
        if (cnt.getCount()) {
            StreamConfig m_config = config();
            m_config.logger("waiting for background socket I/O to complete before continuing");
            waitIoComplete();
        } else
            markIoComplete();
    }

    #! performs static thread resource cleanup on I/O thread resources
    static staticCleanup() {
        *hash<auto> std = remove_thread_data(ThreadKey).ThreadKey;
        if (std)
            throw "STREAM-ERROR", sprintf("the following stream objects: %y were destroyed in their background I/O thread; make sure and terminate I/O threads properly before allowing your stream objects go out of scope", (map sprintf("class: %y stream: %y", $1.cls, $1.stream), std.iterator()));
    }

    #! checks if there is a stream operation running in the background, if so, a user-friendly exception is thrown
    static checkStream(QorusSystemRestHelper helper, string op) {
        *hash<auto> h = get_thread_data(ThreadKey){helper.uniqueHash()};
        if (!h)
            return;

        throw "STREAM-ERROR", sprintf("cannot call %s when class %y is handling stream %y on the same connection; note that this error can also be thrown with API errors in streaming classes (ex: failure to read all data with DbReceiveStream before terminating the object)", op, h.cls, h.stream);
    }

    #! called by child classes when the thread resource is still allocated and the thread exits or one of Qore::throw_thread_resource_exceptions() or Qore::throw_thread_resource_exceptions_to_mark() is called
    nothing cleanupBase() {
        # remove any thread-local data for the current object
        if (self)
            save_thread_data((ThreadKey: (get_thread_data(ThreadKey) - objid)));
    }

    #! waits for the I/O thread to complete and returns
    private waitIoComplete() {
        cnt.waitForZero();
        markIoComplete();
    }

    #! Returns True if a remote transaction is in progress
    /** @return True if a remote transaction is in progress

        @since Qorus 4.1
    */
    bool inTransaction() {
        QorusSystemRestHelper remote = config().remote();
        return remote.conn_opts.trans_id == remote.getConnectionId();
    }

    #! marks the current connection as in progress; must be already checked beforehand that it's not in progress
    private markIoInProgress() {
        # get object ID
        string n_objid = config().remote().uniqueHash();
        # throw a STREAM-ERROR exception if the connection object is already active with another stream connection
        *hash<auto> std = get_thread_data(ThreadKey);
        bool set_static;
        if (!std)
            set_static = True;
        else if (std{n_objid})
            throw "STREAM-ERROR", sprintf("cannot start %y stream when class %y is handling stream %y on the same connection; note that this error can also be thrown with API errors in streaming classes (ex: failure to read all data with DbReceiveStream before terminating the object)", config().stream(), std{n_objid}.cls, std{n_objid}.stream);

        # save object ID
        objid = n_objid;

        StreamConfig m_config = config();
        m_config.debug("starting %y stream with objid %y", m_config.stream(), objid);
        # save the info in thread-local data
        std{objid} = {
            "cls": self.className(),
            "stream": m_config.stream(),
        };
        save_thread_data((ThreadKey: std));
        set_thread_resource(self);
        # static cleanup is used in case the object is deleted in the background thread
        if (set_static)
            set_thread_resource(\AbstractParallelStream::staticCleanup());
    }

    #! performs thread cleanup on the background I/O thread if any is registered and running
    private markIoComplete() {
        if (!objid)
            return;
        # remove the info from thread-local data
        *hash<auto> std = get_thread_data(ThreadKey);
        if (std) {
            remove std{objid};
            save_thread_data((ThreadKey: std));
            remove_thread_resource(self);
        }
        delete objid;
    }

    #! returns performance information about the stream
    OMQ::StreamInfo getInfo() {
        return m_info;
    }

    #! checks for an error in the background send thread; if there is one, then rethrows the exception in the main application / data thread
    private checkError(string cmd) {
        if (thread_ex) {
            StreamConfig m_config = config();
            # make sure the exception only gets thrown once
            hash<auto> tex = remove thread_ex;
            throw tex.err, sprintf("cannot execute %s::%s(); %y stream aborted in I/O thread: %s", self.className(), cmd, m_config.stream(), tex.desc);
        }
    }

    #! opens the remote transaction by calling startStreamImpl() and starts the background I/O socket thread
    /** @throw STREAM-ERROR if the same remote connection object is already active with a remote stream, this exception is thrown
     */
    private startStream() {
        markIoInProgress();
        startStreamImpl();
        cnt.inc();
        try {
%ifndef QORUS_FAKE_API_MODULE
%ifdef QorusServer
            background socketThread(tld);
%else
            background socketThread();
%endif
%endif
        } catch (hash<ExceptionInfo> ex) {
            cnt.dec();
            rethrow;
        }
    }

    #! sets up thread-local data if possible and calls socketThreadImpl() that implements the background socket I/O for the object
    private socketThread(*ThreadLocalData my_tld) {
        StreamConfig m_config = config();
        on_exit {
            cnt.dec();
            m_config.logger("%s: terminated I/O thread", m_config.streamDesc());
        }
        try {
%ifdef QorusServer
            tld = my_tld; # here can be '=', no need for copy(), probably
%endif
            m_config.logger("%s: started I/O thread", m_config.streamDesc());

            m_info.setStart();
            socketThreadImpl();
        } catch (hash<ExceptionInfo> ex) {
            m_config.logger("%s: error in %s: %s: %s", get_ex_pos(ex), m_config.streamDesc(), ex.err, ex.desc);
            thread_ex = ex;
            # disconnect immediately in case of stream errors
            m_config.remote().disconnect();
            # mark I/O as aborted
            abortIo("error in I/O thread: %s: %s", ex.err, ex.desc);
        }
    }

    #! signals the end of queue operations
    private abortIo(string reason) {
        string err = sprintf("I/O terminated by TID %d: %s", gettid(), vsprintf(reason, argv));
        # purge remaining queued data and set the error status
        dataq.setError(StreamTerminatedError, err);
    }

    #! signals the end of queue operations and waits until the socket thread terminates
    /** @param reason the reason for aborting the I/O thread

        @return @ref True if there was I/O still in progress, @ref False if not
     */
    private bool abortIoWait(string reason) {
        bool rv = cnt.getCount() > 0;
        if (!rv) {
            # ensure that the current thread has removed the thread-local data for the socket I/O thread
            markIoComplete();
            return False;
        }
        abortIo(vsprintf(reason, argv));
        waitIoComplete();
        return rv;
    }

    #! starts or continues a remote transaction
    private beginTransaction(OMQ::DbStreamConfig m_config) {
        QorusSystemRestHelper remote = m_config.remote();
        # only start a transaction if not already in a transaction in the same HTTP session (as identified by the socket descriptor number)
        if (remote.conn_opts.trans_id != remote.getConnectionId()) {
            hash<auto> info;
            # we need to use the timeout both locally and remotely
            string uripath = sprintf("services/sqlutil?action=stream;stream=beginTransaction;datasource=%s", m_config.datasource());
            if (!m_config.suppressRemoteTimeout())
                uripath += sprintf(";timeout=%d", m_config.timeout());

            # here we use the Continue-Persistent header value to try to re-use any current transaction context
            remote.post(uripath, NOTHING, {"Qorus-Connection": "Continue-Persistent"}, \info);
            int id = remote.getConnectionId();
            # save connection ID
            if (id >= 0)
                remote.conn_opts.trans_id = id;
            m_config.debug("info: %y", info);
        } else {
            m_config.debug("already in transaction (trans_id: %d)", remote.conn_opts.trans_id);
        }
    }

    #! commits a remote transaction
    private commit(OMQ::DbStreamConfig m_config) {
        QorusSystemRestHelper remote = m_config.remote();
        # we need to use the timeout both locally and remotely
        string uripath = "services/sqlutil?action=stream;stream=commit";
        if (!m_config.suppressRemoteTimeout())
            uripath += sprintf(";timeout=%d", m_config.timeout());
        remote.post(uripath, m_config.timeout());
        delete remote.conn_opts.trans_id;
    }

    #! rolls back a remote transaction
    private rollback(OMQ::DbStreamConfig m_config) {
        QorusSystemRestHelper remote = m_config.remote();
        # we need to use the timeout both locally and remotely
        string uripath = "services/sqlutil?action=stream;stream=rollback";
        if (!m_config.suppressRemoteTimeout())
            uripath += sprintf(";timeout=%d", m_config.timeout());
        remote.post(uripath, m_config.timeout());
        delete remote.conn_opts.trans_id;
    }

    #! this method implements the background thread that handles the actual @ref datastreamprotocol "DataStream" socket sends
    abstract private socketThreadImpl();

    #! opens the remote transaction before starting the background I/O socket thread
    abstract private startStreamImpl();

    #! returns the configuration object
    abstract OMQ::StreamConfig config();

    #! starts a transaction in a remote @ref dsconn "datasource"
    /** @par Example:
        @code{.py}
AbstractParallelStream::beginTransaction(remote, dsname);
        @endcode

        @param remote a @ref OMQ::QorusSystemRestHelper object
        @param datasource the name of the @ref dsconn "datasource" in the remote server
        @param timeout_ms an optional timeout value in milliseconds for HTTP communication
        @param info an optional reference to an lvalue that will be used as an output variable giving a hash of request headers and other information about the HTTP request

        The \c "Qorus-Connection: Continue-Persistent" header is sent with the call so that a new transaction is started or any transaction in progress is continued
    */
    static beginTransaction(QorusSystemRestHelper remote, string datasource, *timeout timeout_ms, *reference info) {
        # ensure remote is connected
        remote.connect();
        # set persistent (disable automatic reconnects)
        remote.setPersistent();
        # start remote transaction
        string uripath = sprintf("services/sqlutil?action=stream;stream=beginTransaction;datasource=%s", datasource);
        # we need to use the timeout both locally and remotely
        if (timeout_ms)
            uripath += sprintf(";timeout=%d", timeout_ms);
        remote.post(uripath, NOTHING, ("Qorus-Connection": "Continue-Persistent"), \info);
    }
}

#! this class handles stream classes that use an I/O thread to send data
/** such classes have the following characteristics:
    - they can abort the I/O at any time without corrupting the socket data; therefore when aborting the I/O thread, they don't need to disconnect
    - the destructor waits until the I/O thread completes and do not disconnect
*/
class OMQ::AbstractParallelWriteStream inherits OMQ::AbstractParallelStream {
    #! waits for any I/O to complete and then returns
    destructor() {
        if (!thread_ex && cnt.getCount())
            flush();
        else
            abortIoWait("%s object destroyed", self.className());
    }

    #! called when the thread resource is still allocated and the thread exits or one of Qore::throw_thread_resource_exceptions() or Qore::throw_thread_resource_exceptions_to_mark() is called
    nothing cleanup() {
        if (self) {
            cleanupBase();
            abortIoWait("%s I/O thread resource left active on exit; ensure that %s::flush() or %s::disconnect() is called before terminating; the I/O thread now will be aborted with an error", self.className(), self.className(), self.className());
        }
    }

    #! Disconnects the connection
    disconnect() {
        # mark queue data as errored and terminate I/O thread if it's still in progress
        abortIoWait("%s::disconnect() called", self.className());
        # disconnect connection
        config().remote().disconnect();
    }

    #! flushes all remote I/O, signals the I/O thread to terminate and waits for confirmation, then checks for background I/O errors, in which case an exception is thrown in this thread
    /** use this method when a remote operation should be continued in the same HTTP connection, for example
     */
    flush() {
        terminateIoWait("flush");
    }

    #! flushes all remote I/O, signals the I/O thread the terminate and waits for confirmation, then checks for background I/O errors, in which case an exception is thrown in this thread
    /** called by terminateIoWait()

        @return @ref True if the I/O thread was terminated due to this call, @ref False if it was already terminated
     */
    private bool terminateIoWaitIntern(string action) {
        # ensure all data has been sent
        softbool rv = submitImpl();
        if (rv) {
            # signal the background thread to stop sending data
            stopIoThreadImpl();
            # wait for send thread to complete
            waitIoComplete();
        }
        # check for background send errors
        checkError(action);
        # get total elapsed time and calculate performance
        m_info.setEnd();
        return rv;
    }

    #! flushes all remote I/O, signals the I/O thread the terminate and waits for confirmation, then checks for background I/O errors, in which case an exception is thrown in this thread
    abstract private terminateIoWait(string action);

    #! signal the I/O thread to top sending data
    abstract private stopIoThreadImpl();

    #! puts data on the queue for sending in the background I/O thread
    /** @return @ref True if the I/O thread is running, @ref False if not
    */
    abstract private bool submitImpl();
}

#! this class handles stream classes that use an I/O thread to receive data
/** such classes have the following characteristics:
    - when aborting the I/O thread, the connection must be closed
    - the destructor will abort any background I/O in progress, if the I/O thread is aborted, then it will disconnect the connection and throw a user-friendly exception explaining what went wrong and how to avoid it in the future
    - whenever the main thread detects that all data has been received or a stream error has occured, the connection must be marked as available again (is call waitIoComplete())
*/
class OMQ::AbstractParallelReceiveStream inherits OMQ::AbstractParallelStream {
    #! disconnects and aborts the I/O thread if it's still running
    destructor() {
        abortInternMethod("destructor");
    }

    #! called when the thread resource is still allocated and the thread exits or one of Qore::throw_thread_resource_exceptions() or Qore::throw_thread_resource_exceptions_to_mark() is called
    nothing cleanup() {
        cleanupBase();
        abortIntern("cleanup", "%s I/O thread resource left active on exit; ensure that all data has been received or %s::disconnect() is called before terminating; the I/O thread now will be aborted with an error", self.className(), self.className());
    }

    #! if the I/O thread is running, then abort it, disconnect the connection, and throw a user-friendly exception what happened and how to avoid such situations in the future
    private abortInternMethod(string meth) {
        abortIntern(meth, "%s::%s() called", self.className(), meth);
    }

    #! if the I/O thread is running, then abort it, disconnect the connection, and throw a user-friendly exception what happened and how to avoid such situations in the future
    private abortIntern(string meth, string fmt) {
        # mark queue data as errored and terminate I/O thread if it's still in progress
        string desc = vsprintf(fmt, argv);
        bool aborted = abortIoWait(desc);
        if (aborted) {
            # disconnect connection
            config().remote().disconnect();
            throwAbortedExceptionImpl(meth);
        }
    }

    #! throw a user-friendly exception about why the I/O thread was aborted and the connection forcibly closed and how to avoid such situations in the future
    abstract private throwAbortedExceptionImpl(string meth);
}

#! configuration class for DB streams
public class OMQ::DbStreamConfig inherits StreamConfig, DbStreamConfigBase {
    #! creates the object and assigns config info
    constructor(string stream, string remote, string datasource, *string tablename, *hash<auto> options) : StreamConfig(stream, remote, options), DbStreamConfigBase(datasource, tablename) {
    }

    #! creates the object and assigns config info
    constructor(string stream, QorusSystemRestHelper remote, string datasource, *string tablename, *hash<auto> options) : StreamConfig(stream, remote, options), DbStreamConfigBase(datasource, tablename) {
    }

    #! returns a description of the stream for error reporting
    string streamDesc() {
        return sprintf("%y stream %s:%y", m_stream, m_datasource, m_tableName ?? "raw SQL");
    }

    #! logs the stream configuration when created
    logStreamConfigImpl(string what, string url) {
        logger("%s %y stream url: %y datasource: %y table: %y", what, m_stream, url, m_datasource, m_tableName);
    }
}

#! config class for DB streams using queued / blocked I/O
public class OMQ::QueuedBlockConfigBase {
    private {
        #! data queue block size; the number of blocks to queue for sending before the main data thread will block; default: \c 2
        *softint m_queue_block_size = 2;

        #! queue timeout; maximum amount of time a message can wait for the queue to become free; default: \c 5m
        timeout m_queue_timeout = 5m;

        #! minimum queue block size
        const MinQueueBlockSize = 2;
    }

    #! creates the object and assigns config info
    constructor(*hash<auto> options)  {
        if (options.hasKey("queue_block_size")) {
            if (options.queue_block_size != -1 && (options.queue_block_size < MinQueueBlockSize))
                throw "QUEUE-BLOCK-SIZE-ERROR", sprintf("queue_block_size: %d is less then the minimum: %d (note: -1 is valid meaning no limit)", options.queue_block_size, MinQueueBlockSize);
            m_queue_block_size = options.queue_block_size;
        }
        if (options.hasKey("queue_timeout"))
            m_queue_timeout = options.queue_timeout;
        else if (options.hasKey("timeout"))
            m_queue_timeout = options.timeout;
    }

    #! returns the queue block size
    *int queueBlockSize() {
        return m_queue_block_size;
    }

    #! returns the queue timeout in milliseconds
    int queueTimeout() {
        return m_queue_timeout;
    }

    #! updates options
    update(*hash<auto> options) {
        if (options.queue_block_size) {
            if (options.queue_block_size != -1 && (options.queue_block_size < MinQueueBlockSize))
                throw "QUEUE-BLOCK-SIZE-ERROR", sprintf("queue_block_size: %d is less then the minimum: %d (note: -1 is valid meaning no limit)", options.queue_block_size, MinQueueBlockSize);
            m_queue_block_size = options.queue_block_size;
        }
        if (options.queue_timeout)
            m_queue_timeout = options.queue_timeout;
    }
}

#! config class for DbRemoteSend
public class OMQ::DbQueuedBlockStreamConfig inherits DbStreamConfig, QueuedBlockConfigBase {
    private {
        # "omit_update" stream option for the "upsert" stream
        *softlist<auto> omit_update;

        # "upsert_strategy" stream option for the "upsert" stream
        *softint upsert_strategy;
    }

    #! creates the object and assigns config info
    constructor(string stream, string remote, string datasource, *string tablename, *hash<auto> options) : DbStreamConfig(stream, remote, datasource, tablename, options), QueuedBlockConfigBase(options) {
        if (options.omit_update)
            omit_update = options.omit_update;
        if (options.upsert_strategy)
            upsert_strategy = options.upsert_strategy;
    }

    #! creates the object and assigns config info
    constructor(string stream, QorusSystemRestHelper remote, string datasource, *string tablename, *hash<auto> options) : DbStreamConfig(stream, remote, datasource, tablename, options), QueuedBlockConfigBase(options) {
        if (options.omit_update)
            omit_update = options.omit_update;
        if (options.upsert_strategy)
            upsert_strategy = options.upsert_strategy;
    }

    #! updates the configuration for a new stream
    update(string stream, string tablename, *hash<auto> options) {
        StreamConfig::update(stream, options);
        DbStreamConfigBase::update(tablename);
        QueuedBlockConfigBase::update(options);
        if (options.omit_update)
            omit_update = options.omit_update;
        if (options.upsert_strategy)
            upsert_strategy = options.upsert_strategy;
    }

    #! returns any "omit_update" remote upsert stream option
    *list<auto> omitUpdate() {
        return omit_update;
    }

    #! returns any "upsert_strategy" remote upsert stream option
    *int upsertStrategy() {
        return upsert_strategy;
    }
}

#! Database stream for outbound/writing data to the remote instance
/** @par Transaction Management
    The DbRemoteSend object automatically starts or continues a remote transaction by including the
    \c "Qorus-Connection: Continue-Persistent" header when opening the stream.  Remote transactions
    must be explicitly committed (by calling DbRemoteSend::commit() for example) or aborted (by calling
    DbRemoteSend::disconnect() for example).\n\n
    Multiple write operations with the same @ref remoteconn "remote connection" and the same
    @ref dsconn "datasource" can be made in the same remote transaction by calling the DbRemoteSend::openStream()
    method for each new action as in the following example:
    @code{.py}
DbRemoteSend out(qrest, "omquser", "insert", "table1");
# in case of error, disconnect which will cause a rollback on the remote end
# due to the fact that the DataStream protocol relies on HTTP chunked transfer
# encoding, the socket could be in the middle of a chunked transfer when an
# error occurs, therefore it's better to simply disconnect than to try to
# execute a manual rollback when errors occur
on_error out.disconnect();
on_success out.commit();

out.append(Data1.iterator());
out.openStream("insert", "table2");
out.append(Data2.iterator());
    @endcode \n
    Additionally, the DbRemoteSend::flush() method can be used to flush background I/O to the server
    before continuing.\n\n
    This class will start a remote transaction if none is already in place; otherwise any existing
    remote transaction is continued.\n\n
    To explicitly start a transaction before stream operations, see
    @ref OMQ::AbstractParallelStream::beginTransaction() "AbstractParallelStream::beginTransaction()"
    @see
    - @ref sqlutil_transmgt
    - @ref stream-api-transmgt

    @par Data Format
    This class serializes data in column format, meaning a hash (with keys giving column names) of lists (giving the
    row values for each column).  This is the most efficient data serialization technique from the point of view of
    the packet size and therefore of network performance.  Additionally, this format is the native format to use with
    bulk DML on the remote end.\n\n
    For this reason, it's best to use the DbRemoteSend::append(hash) method with data already in this format for
    maximum efficiency (for example as selected by @ref Qore::SQL::SQLStatement::fetchColumns() or
    @ref SqlUtil::AbstractTable::select()).

    @par Update Stream Data Format
    When using the \c "update" stream, the DbRemoteSend::append() methods take a hash with \c "set" and \c "cond"
    keys, where each of these keys must be assigned a list<auto> of hashes giving the corresponding arguments to the
    @ref SqlUtil::AbstractTable::update() method.

    @par Threaded I/O Implementation
    This class creates a background thread that handles the socket I/O so that socket I/O
    can be executed in parallel to the main data acquisition thread (the thread that creates
    the object).\n
    \n
    There is a @ref Qore::Thread::Queue "Queue" object that passes aggregated row data to the send thread;
    the default @ref Qore::Thread::Queue "Queue" size is 2 (representing a number of blocks), which allows
    2 blocks of data to be queued before the internal private method DbRemoteSend::submitImpl() (called
    implicitly by DbRemoteSend::append()) will block.\n
    \n
    If the @ref Qore::Thread::Queue "Queue" size is 2 and the block size is 1000 then at most 2000 rows
    will be queued for sending before the main thread will block in the internal private method
    DbRemoteSend::submitImpl().\n
    \n
    This allows the main data acquisition thread to stay loosely in sync with the I/O thread so
    that memory usage is optimized and furthermore serves to avoid stalling the I/O thread due to
    lack of data.\n
    \n
    After sending all data, one of the following methods should be called:
    - DbRemoteSend::commit(): waits for background I/O to be sent and commits the remote transaction
    - DbRemoteSend::rollback(): aborts the background I/O as soon as possible and rolls the remote transaction back
    - DbRemoteSend::flush(): waits for background I/O to be sent and then returns after the I/O thread has exited; use
      this method when a remote transaction will be continued

    @note
    - This class assumes that data submitted with the append() methods is stable; that is, it has the same format and
      same hash keys, additionally, if there are any SqlUtil operator hashes, that they are identical in every row
    - This class is not thread-safe; it's designed to be used from a single thread; calling this class's methods from
      multiple threads simultaneously will result in unpredictable behavior
 */
public class OMQ::DbRemoteSend inherits OMQ::AbstractParallelWriteStream, DataStreamClient::DataStreamSendMessage {
    private {
        #! data to be sent in column format
        hash<auto> m_data;

        #! stream configuration
        DbQueuedBlockStreamConfig m_config;

        #! non-operator column list<auto> when processing column-formatted data (hash of lists)
        list<auto> cols = ();
    }

    #! constructor taking a @ref OMQ::DbRemoteBase object for the remote server
    /**
        @param remote a DbRemoteBase object
        @param stream the @ref system_sqlutil "system.sqlutil service stream" to be used
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "omit_update": a list<auto> of columns to omit when updating for asymmetrical upserts; only valid with
          the \c "upsert" stream; if this option is given with other streams, it will be ignored
        - \c "queue_block_size": the number of blocks to queue for sending before the main data thread will block
          (default: \c 2)
        - \c "queue_timeout": the number of milliseconds to wait for queue data before throwing a \c QUEUE-TIMEOUT
          exception
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "upsert_strategy": an @ref sql_upsert_strategies "upsert strategy code"; only valid with the \c "upsert"
          stream; if this option is given with other streams, it will be ignored

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote
        connection object
    */
    constructor(DbRemoteBase remote, string stream, string table_name, *hash<auto> options) {
        m_config = new DbQueuedBlockStreamConfig(stream, remote.config().remote(), remote.datasourceName(),
            table_name, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server
    /**
        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param datasource a string with name of the remote @ref dsconn "datasource" to use
        @param stream the @ref system_sqlutil "system.sqlutil service stream" stream to be used
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "omit_update": a list<auto> of columns to omit when updating for asymmetrical upserts; only valid with
          the \c "upsert" stream; if this option is given with other streams, it will be ignored
        - \c "queue_block_size": the number of blocks to queue for sending before the main data thread will block
          (default: 2)
        - \c "queue_timeout": the number of milliseconds to wait for queue data before throwing a \c QUEUE-TIMEOUT
          exception
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "upsert_strategy": an @ref sql_upsert_strategies "upsert strategy code"; only valid with the \c "upsert"
          stream; if this option is given with other streams, it will be ignored

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote
        connection object
    */
    constructor(string remote, string datasource, string stream, string table_name, *hash<auto> options) {
        m_config = new DbQueuedBlockStreamConfig(stream, remote, datasource, table_name, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection
    /**
        @param remote an @ref OMQ::QorusSystemRestHelper object
        @param datasource a string with name of the remote @ref dsconn "datasource" to use
        @param stream the @ref system_sqlutil "system.sqlutil service stream" stream to be used
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size giving the number of rows per block
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "omit_update": a list<auto> of columns to omit when updating for asymmetrical upserts; only valid with
          the \c "upsert" stream; if this option is given with other streams, it will be ignored
        - \c "queue_block_size": the number of blocks to queue for sending before the main data thread will block
          (default: 2)
        - \c "queue_timeout": the number of milliseconds to wait for queue data before throwing a \c QUEUE-TIMEOUT
          exception
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "upsert_strategy": an @ref sql_upsert_strategies "upsert strategy code"; only valid with the \c "upsert"
          stream; if this option is given with other streams, it will be ignored

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote
         dconnection object
    */
    constructor(QorusSystemRestHelper remote, string datasource, string stream,
                string table_name, *hash<auto> options) {
        m_config = new DbQueuedBlockStreamConfig(stream, remote, datasource, table_name, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! opens the remote transaction and starts the background send thread
    private startStreamImpl() {
        beginTransaction(m_config);
    }

    #! this method implements the background thread that handles the actual @ref datastreamprotocol "DataStream" socket sends
    private socketThreadImpl() {
        # we need to use the timeout both locally and remotely
        string uripath = sprintf("services/sqlutil?action=stream;stream=%s;datasource=%s;table=%s",
                                 m_config.stream(), m_config.datasource(), m_config.tableName());
        # process upsert options
        if (m_config.stream() == "upsert") {
            *list<auto> l = m_config.omitUpdate();
            if (l)
                uripath += sprintf(";omit_update=%s", (foldl $1 + "," + $2, l));
            *int us = m_config.upsertStrategy();
            if (us)
                uripath += sprintf(";upsert_strategy=%d", us);
        }
        if (!m_config.suppressRemoteTimeout())
            uripath += sprintf(";timeout=%d", m_config.timeout());
        m_config.debug("uri path: %y", uripath);
        hash<auto> response = m_config.remote().sendDataStream(self, "POST", uripath, m_config.timeout(), NOTHING, ("Qorus-Connection": "Continue-Persistent"));
        m_config.debug("response: %y", response);
    }

    #! flushes the current stream and reopens a new stream with the same remote connection and in the same @ref dsconn "datasource"s
    /** @par Example:
        @code{.py}
out.openStream("update", "table2");
        @endcode

        @param stream the @ref system_sqlutil "system.sqlutil service stream" to be used
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size giving the number of rows per block
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "queue_block_size": the number of blocks to queue for sending before the main data thread will block (default: 2)
        - \c "queue_timeout": the number of milliseconds to wait for queue data before throwing a \c QUEUE-TIMEOUT exception
     */
    openStream(string stream, string table_name, *hash<auto> options) {
        terminateIoWait("openStream");
        # clear any possible data queue error
        dataq.clearError();
        m_config.update(stream, table_name, options);
        m_config.logStreamConfig("updating");
        startStream();
    }

    #! signals the I/O thread to stop sending
    private stopIoThreadImpl() {
        # push NOTHING to stop sending
        try {
            dataq.push(NOTHING, m_config.queueTimeout());
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == StreamTerminatedError)
                return;
            rethrow;
        }
    }

    #! flushes all remote I/O, terminates the I/O thread, and checks for background I/O errors, in which case an exception is thrown
    private terminateIoWait(string action) {
        #m_config.debug("DEBUG: terminateIoWait: %y", action);
        if (terminateIoWaitIntern(action)) {
            m_config.logger("%s %s:%y: sent %d row%s in %y: %.2f rows / second",
                            m_config.stream(), m_config.datasource(), m_config.tableName(),
                            m_info.count, m_info.count == 1 ? "" : "s", m_info.delta, m_info.dps);
        }
        m_info.reset();
        # reset column hash
        delete m_data;
        # reset column list
        cols = ();
    }

    #! Commit the remote transaction. It also sends any pending data in the data queue before the commit.
    commit() {
        terminateIoWait("commit");
        # execute the commit operation in the remote server
        AbstractParallelStream::commit(m_config);
        m_config.logger("%s: committed transaction", m_config.stream());
    }

    #! Rollback remote transaction
    /** @note it's normally better to disconnect the connection if an error occurs rather than call
        rollback() when streaming because if a chunked transfer is interrupted, then HTTP calls will
        fail anyway, and the remote end will rollback the transaction in any case unless an explicit
        commit is executed

        @param action an optional bool value to keep connection open or close the connection. Connection closing is the default

        @see DO_DISCONNECT
        @see DONT_DISCONNECT
        @see disconnect()
    */
    rollback(bool action = DO_DISCONNECT) {
        if (action == DO_DISCONNECT) {
             disconnect();
        } else {
            # mark queue data as errored and terminate I/O thread if it's still in progress
            abortIoWait("%s::rollback() called", self.className());
            AbstractParallelStream::rollback(m_config);
            m_config.logger("%s: rolled back transaction", m_config.stream());
        }
    }

    #! Append data to the ready queue: list
    /**
        @param data a list<auto> with row data to be added. It should follow the expected target format (list<auto> of hashes, each list<auto> element represents a row and each has the row data).

        Data are sent whenever their count reaches the \c block size.

        The DB transaction is left open.

        @note This class assumes that data submitted with the append() methods is stable; that is, it has the same format and same hash keys, additionally, if there are any SqlUtil operator hashes, that they are identical in every row
    */
    append(list<auto> data) {
        checkError("append");
        # return if an empty list<auto> was passed
        if (!data)
            return;
        if (data[0].typeCode() != NT_HASH)
            throw "DBREMOTESEND-APPEND-ERROR", sprintf("expected a list<auto> (rows) of hashes (column data); got type %y for the first list<auto> element instead", data[0].typeCode());
        if (!m_data)
            setupData(data[0]);
        foreach hash<auto> row in (data)
            map m_data.$1 += row.$1, cols;
        if (m_data{cols[0]}.size() >= m_config.block())
            submitImpl();
    }

    #! Append data to the ready queue: hash
    /**
        @param new_data a hash with data to be added; can be a single row or multiple rows in column format

        Data are sent whenever the row count reaches the \c block size.

        The DB transaction is left open.

        @note
        - This class assumes that data submitted with the append() methods is stable; that is, it has the same format
          and same hash keys, additionally, if there are any SqlUtil operator hashes, that they are identical in every
          row
        - When submitting bulk data (hashes of lists), any constant data must be submitted in trailing keys; the first
          key value will determine if the data is handled as bulk (hash of lists) or not, furthermore it is an error
          to pass a key with a constant value and then in another call as a list of values or vice versa
    */
    append(hash<auto> new_data) {
        checkError("append");
        if (!m_data)
            setupData(new_data);
        # ensure that no submit is made if the hash has no values
        bool bulk;
        {
            auto val = new_data.firstValue();
            if (val.typeCode() == NT_LIST) {
                val = val[0];
                bulk = True;
            }
            if (!exists val)
                return;
        }
        if (bulk) {
            # add column data
            map m_data.$1 += new_data.$1, cols, new_data.$1.typeCode() == NT_LIST;
            # add constant data
            map m_data.$1 = new_data.$1, cols, new_data.$1.typeCode() != NT_LIST && !m_data.$1;
        } else {
            map m_data.$1 += new_data.$1, cols;
        }

        if (m_data{cols[0]}.size() >= m_config.block())
            submitImpl();
    }

    #! Append data to the ready queue from a @ref Mapper::AbstractMapperIterator "AbstractMapperIterator" object
    /**
        @param it a @ref Mapper::AbstractMapperIterator "AbstractMapperIterator" object with data to be added. Data provided by the iterator should follow the expected format (ie hashes of lists for column_format, otherwise simple hashes of row data for non-column_format).

        This method processes the whole iterator in one call.

        The DB transaction is left open.

        @note SqlUtil operator functions are assumed to be identical for all rows and are only sent once; the input data is assumed to be uniform in this regard also across append(hash) calls
    */
    append(Mapper::AbstractMapperIterator it) {
        int block = m_config.block();
        while (True) {
            list<auto> data = it.mapBulk(block);
            if (!data)
                break;
            if (!m_data)
                setupData(data[0]);
            foreach hash<auto> row in (data) {
                map m_data.$1 += row.$1, cols;
            }
            checkError("append");
            submitImpl();
            if (data.size() < block)
                break;
        }
        submitImpl();
    }

    #! Append data to the ready queue from a @ref Qore::AbstractIterator "AbstractIterator" object
    /**
        @param it a @ref Qore::AbstractIterator "AbstractIterator" object with data to be added. Data provided by the iterator should follow the expected format (ie hashes of lists for column_format, otherwise simple hashes of row data for non-column_format).

        This method processes the whole iterator in one call.

        The DB transaction is left open.

        @note SqlUtil operator functions are assumed to be identical for all rows and are only sent once; the input data is assumed to be uniform in this regard also across append(hash) calls
    */
    append(Qore::AbstractIterator it) {
        while (it.next()) {
            hash<auto> data = it.getValue();
            if (!m_data)
                setupData(data);
            map m_data.$1 += data.$1, cols;
            if (m_data{cols[0]}.size() >= m_config.block()) {
                checkError("append");
                submitImpl();
            }
        }
        submitImpl();
    }

    #! scans the first row for SqlUtil operator hashes and makes a list<auto> of "normal" columns assigned to \a cols
    private nothing setupData(hash<auto> row) {
        if (m_config.stream() == "update")
            cols = row.keys();
        else {
            foreach hash<auto> dh in (row.pairIterator()) {
                auto val = dh.value;
                if (val.typeCode() == NT_LIST) {
                    if (val[0].typeCode() == NT_HASH)
                        m_data{dh.key} = val[0];
                    else
                        cols += dh.key;
                } else if (val.typeCode() == NT_HASH)
                    m_data{dh.key} = val;
                else
                    cols += dh.key;
            }
        }
        map m_data.$1 = (), cols;
    }

    #! Append data to the ready queue from a @ref Qore::AbstractIterator "AbstractIterator" object and commit the transaction
    /**
        @param it a @ref Qore::AbstractIterator "AbstractIterator" object with data to be added. Data provided by the iterator should follow the expected format (ie hashes of lists for column_format, otherwise simple hashes of row data for non-column_format).

        This method processes the whole iterator in one call.

        The DB transaction is committed immediately after all data are sent to the server.
    */
    appendCommit(Qore::AbstractIterator it) {
        append(it);
        commit();
    }

    #! submits any pending data on the send queue if the I/O thread is running
    /** @return @ref True if the I/O thread is running, @ref False if not

        @throw IO-ERROR the I/O thread is not running so no data can be submitted
     */
    private bool submitImpl() {
        softbool rv = cnt.getCount();
        if (m_data{cols[0]}) {
            if (!rv)
                throw "IO-ERROR", sprintf("%s: the I/O thread is not running so the data cannot be sent", m_config.stream());
            *hash<auto> data = m_data;
            dataq.push(data, m_config.queueTimeout());
            map m_data.$1 = (), cols;
        }
        return rv;
    }

    #! reimplemented from DataStreamSendMessage
    /** @return the data to send

        @throw STREAM-TERMINATED if the stream was terminated in the main thread, this exception will be thrown here to terminate the I/O thread
     */
    private auto sendDataImpl() {
        *hash<auto> rv = dataq.get(m_config.queueTimeout());
        if (!exists rv)
            return;

        int rowcnt = rv{cols[0]}.lsize();
        m_info.count += rowcnt;
        m_info.total_count += rowcnt;

        m_config.debug("sending rows: %d; total sent: %d", rowcnt, m_info.count);

        return rv;
    }

    #! returns the configuration object
    OMQ::StreamConfig config() {
        return m_config;
    }
}

#! config class for DB select streams
public class OMQ::DbSelectStreamConfig inherits DbStreamConfig, QueuedBlockConfigBase {
    private {
        # select hash options
        *hash<auto> m_sh;

        #! flag to start a remote transaction
        bool m_transaction = False;

        #! raw select SQL for non-table-based selects
        *string sql;

        #! bind args for non-table-based selects
        *list<auto> args;
    }

    #! private constructor
    private constructor(*hash<auto> options, string stream, string remote, string datasource, string sql,
            *list<auto> args) : DbStreamConfig(stream, remote, datasource, NOTHING, options),
                QueuedBlockConfigBase(options) {
        self.sql = sql;
        self.args = args;
        setDbSelectOptions(options - "select");
    }

    #! private constructor
    private constructor(*hash<auto> options, string stream, QorusSystemRestHelper remote, string datasource,
            string sql, *list<auto> args) : DbStreamConfig(stream, remote, datasource, NOTHING, options),
                QueuedBlockConfigBase(options) {
        self.sql = sql;
        self.args = args;
        setDbSelectOptions(options - "select");
    }

    #! creates the object and assigns config info
    constructor(string stream, string remote, string datasource, string tablename, *hash<auto> options)
            : DbStreamConfig(stream, remote, datasource, tablename, options), QueuedBlockConfigBase(options) {
        setDbSelectOptions(options);
    }

    #! creates the object and assigns config info
    constructor(string stream, QorusSystemRestHelper remote, string datasource, string tablename, *hash<auto> options)
            : DbStreamConfig(stream, remote, datasource, tablename, options), QueuedBlockConfigBase(options) {
        setDbSelectOptions(options);
    }

    #! returns any raw SQL set
    *string getRawSql() {
        return sql;
    }

    #! returns any raw SQL bind args set
    *list<auto> getRawSqlArgs() {
        return args;
    }

    #! sets config options
    private setDbSelectOptions(*hash<auto> options) {
        if (options."select")
            m_sh = options."select";
        if (options.hasKey("transaction") && parse_boolean(options.transaction))
            m_transaction = True;
    }

    #! returns any select hash<auto> options
    *hash<auto> selectOptions() {
        return m_sh;
    }

    #! returns the transaction flag
    bool transaction() {
        return m_transaction;
    }

    #! updates the configuration for a new stream
    update(string stream, string tablename, *hash<auto> options) {
        StreamConfig::update(stream, options);
        DbStreamConfigBase::update(tablename);
        QueuedBlockConfigBase::update(options);
        setDbSelectOptions(options);
    }

    #! logs the stream configuration when created
    logStreamConfigImpl(string what, string url) {
        logger("%s %y stream url: %y datasource: %y raw SQL: %y args: %y", what, m_stream, url, m_datasource, sql,
            args);
    }
}

#! config class for raw DB select streams
public class OMQ::DbRawSelectStreamConfig inherits DbSelectStreamConfig {
    #! creates the object and assigns config info
    constructor(string remote, string datasource, string sql, *list<auto> args, *hash<auto> options)
            : DbSelectStreamConfig(options, "select_raw", remote, datasource, sql, args) {
    }

    #! creates the object and assigns config info
    constructor(QorusSystemRestHelper remote, string datasource, string sql, *list<auto> args, *hash<auto> options)
            : DbSelectStreamConfig(options, "select_raw", remote, datasource, sql, args) {
    }
}

#! A class for inbound/reading data from the remote instance, I/O is handled in a background thread and is made available in the getData() and getAllData() methods
/** @par Transaction Management
    The DbRemoteReceive object automatically starts or continues a remote transaction by including the
    \c "Qorus-Connection: Continue-Persistent" header when opening the stream if the \c "transaction"
    constructor() option is set to @ref True.  Remote transactions must be explicitly committed (by
    calling DbRemoteReceive::commit() for example) or aborted (by calling DbRemoteReceive::disconnect()
    for example); otherwise the remote transaction status is left unchanged by the DbRemoteReceive object.\n\n
    To explicitly start a transaction before stream operations, see
    @ref OMQ::AbstractParallelStream::beginTransaction() "AbstractParallelStream::beginTransaction()"
    @see
    - @ref sqlutil_transmgt
    - @ref stream-api-transmgt

    @par Data Format
    This class serializes data in column format, meaning a hash (with keys giving column names) of lists
    (giving the row values for each column).  This is the most efficient data serialization technique from
    the point of view of the packet size and therefore of network performance.  Additionally, this format
    is the native format to use with bulk DML on the local end.\n\n
    Data in row format (lists of hashes) can be received by using the @ref DbRemoteReceive::getDataRows()
    and @ref DbRemoteReceive::getAllDataRows() methods.

    @par Threaded I/O Implementation
    This class creates a background thread that handles the socket I/O so that socket I/O
    can be executed in parallel to the main data handling thread (the thread that creates
    the object).\n\n
    There is a @ref Qore::Thread::Queue "Queue" object that receives row data from the socket I/O thread;
    the default @ref Qore::Thread::Queue "Queue" size is 2 (representing a number of blocks), which allows
    two blocks of data to be queued before the DbRemoteReceive::getData() method will block.\n\n
    If the @ref Qore::Thread::Queue "Queue" size is 2 and the block size is 1000 then at most 2000 rows
    will be queued for receiving before the I/O thread will block in the internal
    DbRemoteReceive::recvDataImpl() method.\n\n
    This allows the main data handling thread to stay loosely in sync with the I/O thread so
    that memory usage is optimized and furthermore serves to avoid stalling the main data handling
    thread due to lack of data.

    @par DbRemoteReceive Usage
    The stream is set up in the constructor, which also starts the background socket I/O thread, which posts data on
    an internal queue.  The data received is then made available in the getData(), getAllData(), getDataRows(), or
    getAllDataRows() methods.

    @par Example:
    @code{.py}
DbRemoteReceive recv(qrest, "omquser", table_name, {"block": 2000});
while (*hash<auto> h = recv.getData()) {
    processData(h);
}
    @endcode

    @note a remote transaction is only started in this object's constructor if the \c transaction option is set,
    otherwise the remote transaction status is left unchanged
 */
public class OMQ::DbRemoteReceive inherits OMQ::AbstractParallelReceiveStream, DataStreamClient::DataStreamRecvMessage {
    private {
        #! stream configuration
        DbSelectStreamConfig m_config;

        #! flag indicating that all data has been taken from the Queue
        bool complete;
    }

    #! Private constructor
    private constructor(*hash<auto> options, DbRemoteBase remote, string sql, *list<auto> args) {
        m_config = new DbRawSelectStreamConfig(remote.config().remote(), remote.datasourceName(), sql, args, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! Private constructor
    private constructor(*hash<auto> options, string remote, string datasource, string sql, *list<auto> args) {
        m_config = new DbRawSelectStreamConfig(remote, datasource, sql, args, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! Private constructor
    private constructor(*hash<auto> options, QorusSystemRestHelper remote, string datasource, string sql, *list<auto> args) {
        m_config = new DbRawSelectStreamConfig(remote, datasource, sql, args, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking an @ref OMQ::DbRemoteBase object for the remote connection
    /**
        @par Example:
        @code{.py}
DbRemoteReceive recv(db, "select", table_name);
while (*hash<auto> h = recv.getData()) {
    processData(h);
}
        @endcode

        @param remote an @ref OMQ::DbRemoteBase object
        @param stream the @ref system_sqlutil "system.sqlutil service stream" to be used
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size; the number of rows to retrieve from the remote database and send in each block
        - \c "block_queue_size": the number of blocks to queue for receiving before the I/O thread will block (default: 2); the total number of rows that can be queued = <i>block_queue_size * block</i>
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "select": @ref select_option_hash "select options" for the source select statement
        - \c "transaction": start a remote transaction; if this option is not given, the remote transaction status is left unchanged

        @note
        - a remote transaction is only started in this object's constructor if the \c transaction option is set,
          otherwise the remote transaction status is left unchanged
        - the \c forupdate @ref select_option_hash "select_option" must be manually included in the \c "select" option
          hash to initiate a \c "select for update"; this is not automatically set by setting the \c "transaction"
          option
       - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
     */
    constructor(DbRemoteBase remote, string stream, string table_name, *hash<auto> options) {
        m_config = new DbSelectStreamConfig(stream, remote.config().remote(), remote.datasourceName(), table_name, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking an @ref OMQ::DbRemoteBase object for the remote connection and assuming the \c "select" stream
    /**
        @par Example:
        @code{.py}
DbRemoteReceive recv(db, table_name);
while (*hash<auto> h = recv.getData()) {
    processData(h);
}
        @endcode

        @param remote an @ref OMQ::DbRemoteBase object
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size; the number of rows to retrieve from the remote database and send in each block
        - \c "block_queue_size": the number of blocks to queue for receiving before the I/O thread will block
          (default: 2); the total number of rows that can be queued = <i>block_queue_size * block</i>
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "select": @ref select_option_hash "select options" for the source select statement
        - \c "transaction": start a remote transaction; if this option is not given, the remote transaction status is
          left unchanged

        @note
        - this constructor always uses the @ref system_sqlutil "system.sqlutil service stream": \c "select"
        - a remote transaction is only started in this object's constructor if the \c transaction option is set,
          otherwise the remote transaction status is left unchanged
        - the \c forupdate @ref select_option_hash "select_option" must be manually included in the \c "select" option
          hash to initiate a \c "select for update"; this is not automatically set by setting the \c "transaction"
          option
        - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection
          object
     */
    constructor(DbRemoteBase remote, string table_name, *hash<auto> options) {
        m_config = new DbSelectStreamConfig("select", remote.config().remote(), remote.datasourceName(), table_name, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server
    /**
        @par Example:
        @code{.py}
DbRemoteReceive recv(remote_name, datasource_name, "select", table_name);
while (*hash<auto> h = recv.getData())
    processData(h);
        @endcode

        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param datasource a string with name of the remote @ref dsconn "datasource" to use
        @param stream the @ref system_sqlutil "system.sqlutil service stream" to be used
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size; the number of rows to retrieve from the remote database and send in each block
        - \c "block_queue_size": the number of blocks to queue for receiving before the I/O thread will block (default: 2); the total number of rows that can be queued = <i>block_queue_size * block</i>
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "select": @ref select_option_hash "select options" for the source select statement
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "transaction": start a remote transaction; if this option is not given, the remote transaction status is left unchanged

        @note
        - a remote transaction is only started in this object's constructor if the \c transaction option is set,
          otherwise the remote transaction status is left unchanged
        - the \c forupdate @ref select_option_hash "select_option" must be manually included in the \c "select" option
          hash to initiate a \c "select for update"; this is not automatically set by setting the \c "transaction"
          option
        - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection
          object
     */
    constructor(string remote, string datasource, string stream, string table_name, *hash<auto> options) {
        m_config = new DbSelectStreamConfig(stream, remote, datasource, table_name, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server and assuming the \c "select" stream
    /**
        @par Example:
        @code{.py}
DbRemoteReceive recv(remote_name, datasource_name, table_name);
while (*hash<auto> h = recv.getData()) {
    processData(h);
}
        @endcode

        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param datasource a string with name of the remote @ref dsconn "datasource" to use
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size; the number of rows to retrieve from the remote database and send in each block
        - \c "block_queue_size": the number of blocks to queue for receiving before the I/O thread will block
          (default: 2); the total number of rows that can be queued = <i>block_queue_size * block</i>
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "select": @ref select_option_hash "select options" for the source select statement
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "transaction": start a remote transaction; if this option is not given, the remote transaction status is
          left unchanged

        @note
        - this constructor always uses the @ref system_sqlutil "system.sqlutil service stream": \c "select"
        - a remote transaction is only started in this object's constructor if the \c transaction option is set,
          otherwise the remote transaction status is left unchanged
        - the \c forupdate @ref select_option_hash "select_option" must be manually included in the \c "select" option
          hash to initiate a \c "select for update"; this is not automatically set by setting the \c "transaction"
          option
        - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection
          object
     */
    constructor(string remote, string datasource, string table_name, *hash<auto> options) {
        m_config = new DbSelectStreamConfig("select", remote, datasource, table_name, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection
    /**
        @par Example:
        @code{.py}
DbRemoteReceive recv(qrest, datasource_name, "select", table_name);
while (*hash<auto> h = recv.getData())
    processData(h);
        @endcode

        @param remote an @ref OMQ::QorusSystemRestHelper object
        @param datasource a string with name of the remote @ref dsconn "datasource" to use
        @param stream the @ref system_sqlutil "system.sqlutil service stream" to be used
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size; the number of rows to retrieve from the remote database and send in each block
        - \c "block_queue_size": the number of blocks to queue for receiving before the I/O thread will block (default: 2); the total number of rows that can be queued = <i>block_queue_size * block</i>
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "select": @ref select_option_hash "select options" for the source select statement
        - \c "transaction": start a remote transaction; if this option is not given, the remote transaction status is left unchanged

        @note
        - a remote transaction is only started in this object's constructor if the \c transaction option is set,
          otherwise the remote transaction status is left unchanged
        - the \c forupdate @ref select_option_hash "select_option" must be manually included in the \c "select" option
          hash to initiate a \c "select for update"; this is not automatically set by setting the \c "transaction"
          option
        - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection
          object
     */
    constructor(QorusSystemRestHelper remote, string datasource, string stream, string table_name, *hash<auto> options) {
        m_config = new DbSelectStreamConfig(stream, remote, datasource, table_name, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection and assuming the \c "select" stream
    /**
        @par Example:
        @code{.py}
DbRemoteReceive recv(qrest, datasource_name, table_name);
while (*hash<auto> h = recv.getData()) {
    processData(h);
}
        @endcode

        @param remote an @ref OMQ::QorusSystemRestHelper object
        @param datasource a string with name of the remote @ref dsconn "datasource" to use
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size; the number of rows to retrieve from the remote database and send in each block
        - \c "block_queue_size": the number of blocks to queue for receiving before the I/O thread will block
          (default: 2); the total number of rows that can be queued = <i>block_queue_size * block</i>
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "select": @ref select_option_hash "select options" for the source select statement
        - \c "transaction": start a remote transaction; if this option is not given, the remote transaction status is
          left unchanged

        @note
        - this constructor always uses the @ref system_sqlutil "system.sqlutil service stream": \c "select"
        - a remote transaction is only started in this object's constructor if the \c transaction option is set,
          otherwise the remote transaction status is left unchanged
        - the \c forupdate @ref select_option_hash "select_option" must be manually included in the \c "select" option
          hash to initiate a \c "select for update"; this is not automatically set by setting the \c "transaction"
          option
        - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection
          object
     */
    constructor(QorusSystemRestHelper remote, string datasource, string table_name, *hash<auto> options) {
        m_config = new DbSelectStreamConfig("select", remote, datasource, table_name, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! flushes the current stream and reopens a new stream with the same @ref remoteconn "remote connection" and in the same @ref dsconn "datasource"
    /** @par Example:
        @code{.py}
out.openStream("update", "table2");
        @endcode

        @param stream the @ref system_sqlutil "system.sqlutil service stream" to be used
        @param table_name a string with remote table name located in the remote @ref dsconn "datasource"
        @param options optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "block": data block size
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "queue_block_size": the number of blocks to queue for sending before the main data thread will block (default: 2)
        - \c "queue_timeout": the number of milliseconds to wait for queue data before throwing a \c QUEUE-TIMEOUT exception

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
     */
    openStream(string stream, string table_name, *hash<auto> options) {
        abortInternMethod("openStream");
        # clear any possible data queue error
        dataq.clearError();
        m_config.update(stream, table_name, options);
        m_config.logStreamConfig("updating");
        startStream();
    }

    private throwAbortedExceptionImpl(string meth) {
        throw sprintf("STREAM-%s-ERROR", meth.upr()), sprintf("%s::%s() called while I/O still in progress; the remote connection has been disconnected; make sure and retrieve all data or call %s::rollback, or %s::disconnect() before %s", self.className(), meth, self.className(), self.className(), self.className(), "meth" == "destructor" ? "destroying this object": "calling this method");
    }

    #! opens the remote transaction if necessary
    private startStreamImpl() {
        if (m_config.transaction())
            beginTransaction(m_config);
    }

    #! receive reimplementation
    private socketThreadImpl() {
        # we need to use the timeout both locally and remotely
        string uripath;
        *string table_name = m_config.tableName();
        hash<auto> args;
        string http_method;
        if (table_name) {
            uripath = sprintf("services/sqlutil?action=stream;stream=%s;datasource=%s;table=%s;block=%d;column_format=true",
                m_config.stream(), m_config.datasource(), m_config.tableName(), m_config.block());
            # we set the HTTP method to GET here for backwards compatibility
            http_method = "GET";
        } else {
            uripath = sprintf("services/sqlutil?action=stream;stream=select_raw;datasource=%s;block=%d;column_format=true",
                m_config.datasource(), m_config.block());
            args += {
                "sql": m_config.getRawSql(),
            };
            *list<auto> sql_args = m_config.getRawSqlArgs();
            if (sql_args) {
                args.args = sql_args;
            }
            http_method = "PUT";
        }
        if (!m_config.suppressRemoteTimeout())
            uripath += sprintf(";timeout=%d", m_config.timeout());
        m_config.debug("uri path: %y select options: %y", uripath, m_config.selectOptions());
        m_config.remote().recvDataStream(self, http_method, uripath, args + m_config.selectOptions(),
            m_config.timeout());
    }

    # FIXME: should throw an exception if called before all data is received
    #! Commit remote transaction
    /**
        @note exceptions thrown in the socket I/O thread will be rethrown when this method is called so that errors can be handled in the main data thread
    */
    commit() {
        # wait for socket thread to complete
        waitIoComplete();
        # check for background I/O errors
        checkError("commit");
        AbstractParallelStream::commit(m_config);
    }

    #! Rollback remote transaction
    /** @note
        - it's normally better to disconnect the connection if an error occurs rather than call
        rollback() when streaming because if a chunked transfer is interrupted, then HTTP calls will
        fail anyway, and the remote end will rollback the transaction in any case unless an explicit
        commit is executed

        @param action an optional bool value to keep connection open or close the connection. Connection closing is the default

        @see DO_DISCONNECT
        @see DONT_DISCONNECT
        @see disconnect()
    */
    rollback(bool action = DO_DISCONNECT) {
        if (action == DO_DISCONNECT) {
            disconnect();
        } else {
            # wait for socket thread to complete
            waitIoComplete();
            AbstractParallelStream::rollback(m_config);
        }
    }

    #! Disconnects the connection
    disconnect() {
        # mark queue data as errored and terminate I/O thread if it's still in progress
        abortIoWait("%s::disconnect() called", self.className());
        # disconnect connection
        m_config.remote().disconnect();
    }

    #! An abstract method to handle incoming data
    /** @param rdata data arrive in hash format: keys = columns, values = lists of row values
    */
    private nothing recvDataImpl(auto rdata) {
        if (rdata.typeCode() != NT_HASH) {
            throw "STREAM-ERROR", sprintf("unexpected data received on stream; expected \"hash\"; got %y: %y",
                rdata.type(), rdata);
        }
        int rowcnt = rdata.firstValue().lsize();
        m_info.count += rowcnt;
        m_info.total_count += rowcnt;
        dataq.push(rdata, m_config.queueTimeout());
    }

    #! called when all data has been received or the background I/O operation terminates due to an error
    private nothing recvDataDoneImpl(*string err) {
        # get total elapsed time and calculate performance
        m_info.setEnd();

        # log receive performance
        m_config.logger("%s %s:%y: received %d row%s in %y: %.2f rows / second",
                        m_config.stream(), m_config.datasource(), m_config.tableName() ?? "raw SQL",
                        m_info.count, m_info.count == 1 ? "" : "s", m_info.delta, m_info.dps);

        # mark the data as complete
        dataq.push(NOTHING, m_config.queueTimeout());
    }

    #! returns queued data as soon as it is available, if the timeout is omitted or equal or less than 0, no timeout is used and the call will block until data is available on the queue; once this method return @ref nothing it signifies that the end of stream data condition has been reached; do not call this method again after it returns @ref nothing
    /**
        @par Examples:
        @code{.py}
DbRemoteReceive recv(qrest, "omquser", "select", table_name, ("block": 2000));
while (*hash<auto> h = recv.getData())
    processData(h);
        @endcode

        @param timeout_ms an override for the the timeout for waiting on the queue; integers are interpreted as milliseconds; relative date/time values are interpreted literally with a maximum resolution of milliseconds; if the timeout limit is exceeded before data is available, a \c QUEUE-TIMEOUT error is thrown.  If no value is given here, the default queue timeout value configured for the object is used (see the \c "queue_timeout" option in the @ref constructor())

        @return a hash of lists: keys = columns, values = lists of row values or @ref nothing if all data has been received (do not call this method again after it returns @ref nothing)

        @throw DB-REMOTE-RECEIVE-ERROR this exception is thrown if this method is called after it returns @ref nothing signifying end of stream
        @throw QUEUE-TIMEOUT this exception is thrown if a timeout occurs on the @ref Qore::Thread::Queue "Queue"
        @throw STREAM-TERMINATED if the I/O thread was terminated prematurely, this exception will be thrown

        @note exceptions thrown in the socket I/O thread will be rethrown when this method is called so that errors can be handled in the main data thread
    */
    *hash<auto> getData(*timeout timeout_ms) {
        checkComplete("getData");
        *hash<auto> d;
        try {
            d = dataq.get(timeout_ms ?? m_config.queueTimeout());
        } catch (hash<ExceptionInfo> ex) {
            # wait for the I/O thread to complete and mark the connection as available for use again
            if (ex.err == StreamTerminatedError)
                waitIoComplete();

            rethrow;
        }
        if (!d) {
            complete = True;
            # wait for the I/O thread to complete and mark the connection as available for use again
            waitIoComplete();
        }

        # check for background I/O errors
        checkError("getData");

        #m_config.debug("DbRemoteReceive::getData() returning %y", d);
        return d;
    }

    #! returns all data recevied by the object in a single call, if the timeout is omitted or equal or less than 0, no timeout is used and the call will block until data is available on the queue
    /**
        @par Examples:
        @code{.py}
DbRemoteReceive recv(qrest, "omquser", "select", table_name, ("block": 2000));
*hash<auto> h = recv.getAllData();
        @endcode

        @param timeout_ms an override for the the timeout for waiting on the queue; integers are interpreted as milliseconds; relative date/time values are interpreted literally with a maximum resolution of milliseconds; if the timeout limit is exceeded before data is available, a \c QUEUE-TIMEOUT error is thrown.  If no value is given here, the default queue timeout value configured for the object is used (see the \c "queue_timeout" option in the @ref constructor())

        @return a hash is returned where keys = columns, values = lists of row values, or @ref nothing if no data was returned

        @throw DB-REMOTE-RECEIVE-ERROR this exception is thrown if this method is called after it returns @ref nothing signifying end of stream
        @throw QUEUE-TIMEOUT no data was posted to the queue in the timeout period
        @throw STREAM-TERMINATED if the I/O thread was terminated prematurely, this exception will be thrown

        @note
        - exceptions thrown in the socket I/O thread will be rethrown when this method is called so that errors can be handled in the main data thread
        - any exception thrown in this method (I/O error or timeout error) will cause all data to be lost; when this method returns (either normally or due to an exception), the data complete flag is set and no more data can be retrieved from the object
    */
    *hash<auto> getAllData(*timeout timeout_ms) {
        checkComplete("getAllData");
        on_exit complete = True;

        if (!exists timeout_ms)
            timeout_ms = m_config.queueTimeout();

        *hash<auto> rv;
        while (*hash<auto> d = getData(timeout_ms)) {
            # check for background I/O errors
            checkError("getData");

            if (!rv) {
                rv = d;
                continue;
            }

            map rv.$1 += d.$1, d.keyIterator();
        }
        # wait for the I/O thread to complete and mark the connection as available for use again
        waitIoComplete();

        return rv;
    }

    #! returns queued data as a list<auto> of rows as soon as it is available, if the timeout is omitted or equal or less than 0, no timeout is used and the call will block until data is available on the queue; once this method return @ref nothing it signifies that the end of stream data condition has been reached; do not call this method again after it returns @ref nothing
    /**
        @par Examples:
        @code{.py}
DbRemoteReceive recv(qrest, "omquser", "select", table_name, ("block": 2000));
while (*list<auto> l = recv.getDataRows())
    map processDataRow($1), l;
        @endcode

        @param timeout_ms an override for the the timeout for waiting on the queue; integers are interpreted as milliseconds; relative date/time values are interpreted literally with a maximum resolution of milliseconds; if the timeout limit is exceeded before data is available, a \c QUEUE-TIMEOUT error is thrown.  If no value is given here, the default queue timeout value configured for the object is used (see the \c "queue_timeout" option in the @ref constructor())

        @return a list<auto> of row data or @ref nothing if all data has been received (do not call this method again after it returns @ref nothing)

        @throw DB-REMOTE-RECEIVE-ERROR this exception is thrown if this method is called after it returns @ref nothing signifying end of stream
        @throw QUEUE-TIMEOUT this exception is thrown if a timeout occurs on the @ref Qore::Thread::Queue "Queue"
        @throw STREAM-TERMINATED if the I/O thread was terminated prematurely, this exception will be thrown

        @note
        - exceptions thrown in the socket I/O thread will be rethrown when this method is called so that errors can be handled in the main data thread
        - the native column format is converted to row format for the return value of this method
    */
    *list<auto> getDataRows(*timeout timeout_ms) {
        *hash<auto> rv = getData(timeout_ms ?? m_config.queueTimeout());
        if (!rv)
            return;
        return map $1, rv.contextIterator();
    }

    #! returns all data recevied by the object in a single call as a list<auto> of rows, if the timeout is omitted or equal or less than 0, no timeout is used and the call will block until data is available on the queue
    /**
        @par Examples:
        @code{.py}
DbRemoteReceive recv(qrest, "omquser", "select", table_name, ("block": 2000));
*list<auto> l = recv.getAllDataRows();
        @endcode

        @param timeout_ms an override for the the timeout for waiting on the queue; integers are interpreted as milliseconds; relative date/time values are interpreted literally with a maximum resolution of milliseconds; if the timeout limit is exceeded before data is available, a \c QUEUE-TIMEOUT error is thrown.  If no value is given here, the default queue timeout value configured for the object is used (see the \c "queue_timeout" option in the @ref constructor())

        @return a list<auto> of rows or @ref nothing if no data was returned

        @throw DB-REMOTE-RECEIVE-ERROR this exception is thrown if this method is called after it returns @ref nothing signifying end of stream
        @throw QUEUE-TIMEOUT no data was posted to the queue in the timeout period
        @throw STREAM-TERMINATED if the I/O thread was terminated prematurely, this exception will be thrown

        @note
        - exceptions thrown in the socket I/O thread will be rethrown when this method is called so that errors can be handled in the main data thread
        - any exception thrown in this method (I/O error or timeout error) will cause all data to be lost; when this method returns (either normally or due to an exception), the data complete flag is set and no more data can be retrieved from the object
        - the native column format is converted to row format for the return value of this method
    */
    *list<auto> getAllDataRows(*timeout timeout_ms) {
        *hash<auto> rv = getAllData(timeout_ms);
        if (!rv)
            return;
        return map $1, rv.contextIterator();
    }

    #! checks if data is requested after the transfer is complete
    private checkComplete(string meth) {
        if (complete)
            throw "DB-REMOTE-RECEIVE-ERROR", sprintf("%s::%s() called after end of stream; this method has already returned NOTHING signifying end of stream and therefore cannot be called again", self.className(), meth);
    }

    #! returns the configuration object
    OMQ::StreamConfig config() {
        return m_config;
    }
}

#! A class for inbound/reading data from the remote instance from a raw SQL query, I/O is handled in a background thread and is made available in the getData() and getAllData() methods
/** @see @ref OMQ::DbRemoteReceive for information about usage

    @par Example:
    @code{.py}
DbRemoteRawReceive recv(qrest, "omquser", sql, args, ("block": 2000));
while (*hash<auto> h = recv.getData()) {
    processData(h);
}
    @endcode

    @note a remote transaction is only started in this object's constructor if the \c transaction option is set, otherwise the remote transaction status is left unchanged
 */
public class OMQ::DbRemoteRawReceive inherits OMQ::DbRemoteReceive {
    #! constructor taking an @ref OMQ::DbRemoteBase object for the remote connection
    /**
        @par Example:
        @code{.py}
DbRemoteRawReceive recv(db, sql);
while (*hash<auto> h = recv.getData()) {
    processData(h);
}
        @endcode

        @param remote an @ref OMQ::DbRemoteBase object
        @param sql the SQL for the select statement in the remote DB
        @param args optional bind arguments for the SQL statement
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size; the number of rows to retrieve from the remote database and send in each block
        - \c "block_queue_size": the number of blocks to queue for receiving before the I/O thread will block
          (default: 2); the total number of rows that can be queued = <i>block_queue_size * block</i>
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "transaction": start a remote transaction; if this option is not given, the remote transaction status is
          left unchanged

        @note
        - this class always uses the @ref system_sqlutil "system.sqlutil service stream": \c "select_raw"
        - a remote transaction is only started in this object's constructor if the \c transaction option is set,
          otherwise the remote transaction status is left unchanged
        - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection
          object
     */
    constructor(DbRemoteBase remote, string sql, *softlist<auto> args, *hash<auto> options) : DbRemoteReceive(options, remote, sql, args) {
    }

    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server
    /**
        @par Example:
        @code{.py}
DbRemoteRawReceive recv(remote_name, datasource_name, sql);
while (*hash<auto> h = recv.getData()) {
    processData(h);
}
        @endcode

        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param datasource a string with name of the remote @ref dsconn "datasource" to use
        @param sql the SQL for the select statement in the remote DB
        @param args optional bind arguments for the SQL statement
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size; the number of rows to retrieve from the remote database and send in each block
        - \c "block_queue_size": the number of blocks to queue for receiving before the I/O thread will block
          (default: 2); the total number of rows that can be queued = <i>block_queue_size * block</i>
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "transaction": start a remote transaction; if this option is not given, the remote transaction status is
          left unchanged

        @note
        - this class always uses the @ref system_sqlutil "system.sqlutil service stream": \c "select_raw"
        - a remote transaction is only started in this object's constructor if the \c transaction option is set,
          otherwise the remote transaction status is left unchanged
        - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection
          object
     */
    constructor(string remote, string datasource, string sql, *softlist<auto> args, *hash<auto> options) : DbRemoteReceive(options, remote, datasource, sql, args) {
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection and assuming the \c "select" stream
    /**
        @par Example:
        @code{.py}
DbRemoteReceive recv(qrest, datasource_name, table_name);
while (*hash<auto> h = recv.getData()) {
    processData(h);
}
        @endcode

        @param remote an @ref OMQ::QorusSystemRestHelper object
        @param datasource a string with name of the remote @ref dsconn "datasource" to use
        @param sql the SQL for the select statement in the remote DB
        @param args optional bind arguments for the SQL statement
        @param options optional @ref stream-api-options as follows:
        - \c "block": data block size; the number of rows to retrieve from the remote database and send in each block
        - \c "block_queue_size": the number of blocks to queue for receiving before the I/O thread will block
          (default: 2); the total number of rows that can be queued = <i>block_queue_size * block</i>
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote
        - \c "transaction": start a remote transaction; if this option is not given, the remote transaction status is
          left unchanged

        @note
        - this class always uses the @ref system_sqlutil "system.sqlutil service stream": \c "select_raw"
        - a remote transaction is only started in this object's constructor if the \c transaction option is set,
          otherwise the remote transaction status is left unchanged
        - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection
          object
     */
    constructor(QorusSystemRestHelper remote, string datasource, string sql, *softlist<auto> args, *hash<auto> options) : DbRemoteReceive(options, remote, datasource, sql, args) {
    }
}

#! A high level API for remote @ref system_sqlutil "system.sqlutil service" calls
/** DbRemoteBase provides a high level API for the @ref system_sqlutil "system.sqlutil service" in remote
    Qorus instances. Use it for single updates, deletes, inserts, and/or schema
    management.

    DbRemoteBase wraps all available @ref system_sqlutil "system.sqlutil service" methods with the
    following changes in service methods API:
    - the \c datasource argument is passed to OMQ::DbRemote::constructor() and it's not used in
      method calls

    @warning Use @ref OMQ::DbRemoteSend and @ref OMQ::DbRemoteReceive for inserting and fetching
             large amount of data. These classes are optimized for high volume data.
             Any use of e.g. DbRemote::select() will store all resulting data in the memory
             and it will be transferred in a single call.

    @see DbRemote for a child class that automatically wraps all actions in a remote transaction

    @since Qorus 4.1
*/
public class OMQ::DbRemoteBase {
    private {
        StreamConfig m_config;
        string m_ds;
    }

    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server
    /**
        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param dsname a string with name of the remote @ref dsconn "datasource" to use
        @param opts optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
    */
    constructor(string remote, string dsname, *hash<auto> opts) {
        m_config = new StreamConfig("db-remote", remote, opts);
        m_ds = dsname;
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection
    /**
        @param remote an @ref OMQ::QorusSystemRestHelper object
        @param dsname a string with name of the remote @ref dsconn "datasource" to use
        @param opts optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
     */
    constructor(QorusSystemRestHelper remote, string dsname, *hash<auto> opts) {
        m_config = new StreamConfig("db-remote", remote, opts);
        m_ds = dsname;
    }

    #! Just check if the transaction finished correctly
    destructor() {
        if (m_config.remote().conn_opts.trans_id)
            throw "DB-REMOTE-ERROR", "Deleting object while transaction in progress. commit or rollback is missing";
    }

    #! starts or continues a remote transaction
    /** This method is called from the constructor() automatically
     */
    beginTransaction() {
        QorusSystemRestHelper remote = m_config.remote();
        AbstractParallelStream::checkStream(remote, "DbRemote::beginTransaction()");
        # only start a transaction if not already in a transaction in the same HTTP session (as identified by the socket descriptor number)
        if (remote.conn_opts.trans_id != remote.getConnectionId()) {
            hash<auto> info;
            # we need to use the timeout both locally and remotely
            string uripath = sprintf("services/sqlutil?action=stream;stream=beginTransaction;datasource=%s", m_ds);
            if (!m_config.suppressRemoteTimeout())
                uripath += sprintf(";timeout=%d", m_config.timeout());
            # here we use the Continue-Persistent header value to try to re-use any current transaction context
            remote.post(uripath, NOTHING, ("Qorus-Connection": "Continue-Persistent"), \info);
            int id = remote.getConnectionId();
            # save connection ID
            if (id >= 0)
                remote.conn_opts.trans_id = id;
            m_config.debug("info: %y", info);
        } else
            m_config.debug("already in transaction (trans_id: %d)", remote.conn_opts.trans_id);
    }

    #! returns the remote @ref dsconn "datasource" name specified in constructor
    string datasourceName() {
        return m_ds;
    }

    #! returns the configuration object
    OMQ::StreamConfig config() {
        return m_config;
    }

    #! Returns True if a remote transaction is in progress
    /** @return True if a remote transaction is in progress
    */
    bool inTransaction() {
        QorusSystemRestHelper remote = m_config.remote();
        return remote.conn_opts.trans_id == remote.getConnectionId();
    }

    #! commits a remote transaction
    commit() {
        QorusSystemRestHelper remote = m_config.remote();
        AbstractParallelStream::checkStream(remote, "DbRemote::commit()");
        # we need to use the timeout both locally and remotely
        string uripath = "services/sqlutil?action=stream;stream=commit";
        if (!m_config.suppressRemoteTimeout())
            uripath += sprintf(";timeout=%d", m_config.timeout());
        remote.post(uripath, m_config.timeout());
        delete remote.conn_opts.trans_id;
    }

    #! Rollback remote transaction
    /** @note it's normally better to disconnect the connection if an error occurs rather than call
        rollback() when streaming because if a chunked transfer is interrupted, then HTTP calls will
        fail anyway, and the remote end will rollback the transaction in any case unless an explicit
        commit is executed

        @param action an optional bool value to keep connection open or close the connection. Connection closing is the default

        @see DO_DISCONNECT
        @see DONT_DISCONNECT
        @see disconnect()
    */
    rollback(bool action = AbstractParallelStream::DO_DISCONNECT) {
        QorusSystemRestHelper remote = m_config.remote();
        if (action == AbstractParallelStream::DO_DISCONNECT) {
            # disconnect connection
            remote.disconnect();
            delete remote.conn_opts.trans_id;
            return;
        }
        AbstractParallelStream::checkStream(remote, "DbRemote::rollback()");
        # we need to use the timeout both locally and remotely
        string uripath = "services/sqlutil?action=stream;stream=rollback";
        if (!m_config.suppressRemoteTimeout())
            uripath += sprintf(";timeout=%d", m_config.timeout());
        remote.post(uripath, m_config.timeout());
        delete remote.conn_opts.trans_id;
    }

    #! Disconnects the connection
    disconnect() {
        QorusSystemRestHelper remote = m_config.remote();
        AbstractParallelStream::checkStream(remote, "DbRemote::disconnect()");
        # disconnect connection
        remote.disconnect();
    }

    #! Redirects the method to the remote service and prepends the datasource name to the arguments in the remote call
    auto methodGateArgs(string method, *list<auto> args) {
        if (method !~ /[[:alpha:]_]+/u) {
            throw "DB-REMOTE-ERROR", sprintf("Disallowed method name: %s", method);
        }
        string cmd = sprintf("services/sqlutil/%s?action=call", method);
        # add the datasource as the first element of the argument list
        unshift args, m_ds;
        QorusSystemRestHelper remote = m_config.remote();
        AbstractParallelStream::checkStream(remote, "DbRemote::" + method + "()");
        auto ret = remote.put(cmd, {"args": args});
        return ret;
    }

    #! Redirects the method to the remote service and prepends the datasource name to the arguments in the remote call
    auto methodGate(string method) {
        return methodGateArgs(method, argv);
    }
} # class DbRemoteBase

#! A high level API for remote @ref system_sqlutil "system.sqlutil service" calls
/** DbRemote is identical to DbRemoteBase except that it automatically wraps all actions in a transaction by calling
    beginTransaction() in the constructor.

    DbRemote provides a high level API for the @ref system_sqlutil "system.sqlutil service" in remote
    Qorus instances. Use it for single updates, deletes, inserts, and/or schema
    management.

    DbRemote wraps all available @ref system_sqlutil "system.sqlutil service" methods with the
    following changes in service methods API:
    - the \c datasource argument is passed to OMQ::DbRemote::constructor() and it's not used in
      method calls
    - the transaction is started when the DbRemote object is constructed and must be committed
      or rolled back explicitly.

    @warning Use @ref OMQ::DbRemoteSend and @ref OMQ::DbRemoteReceive for inserting and fetching
             large amount of data. These classes are optimized for high volume data.
             Any use of e.g. DbRemote::select() will store all resulting data in the memory
             and it will be transferred in a single call.

    @section DbRemote_api_calls DbRemote API calls

    This class does not have any of its own methods; all method calls are redirected to @ref system_sqlutil "system.sqlutil" transparently.

    In case of e.g. \c system.sqlutil.update with prototype:
@code{.py}
    int sqlutil.update(string ds, string table, hash<auto> set, *hash<auto> cond)
@endcode
    The DbRemote::update() version of an update call looks like this:
@code{.py}
    int DbRemote::update(string table, hash<auto> set, *hash<auto> cond) {}
@endcode

    @par Example of usage

    @code{.py}
%new-style
%requires QorusClientCore

QorusClient::init2();

DbRemote db("msepl-it", "omquser");
on_success db.commit();
on_error db.rollback();

auto r = db.select("H3G_IT_SHIPPED_ITEMS");
printf("%N\n", r);

r = db.list_tables();
printf("%N\n", r);

r = db.insert("op_in_test", ("id" : 11));
printf("%N\n", r);
    @endcode
*/
public class OMQ::DbRemote inherits DbRemoteBase {
    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server
    /**
        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param dsname a string with name of the remote @ref dsconn "datasource" to use
        @param opts optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        Automatically starts a remote transaction by calling beginTransaction().

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote
        connection object
    */
    constructor(string remote, string dsname, *hash<auto> opts) : DbRemoteBase(remote, dsname, opts) {
        beginTransaction();
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection
    /**
        @param remote an @ref OMQ::QorusSystemRestHelper object
        @param dsname a string with name of the remote @ref dsconn "datasource" to use
        @param opts optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O
          and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        Automatically starts a remote transaction by calling beginTransaction().

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote
        connection object
     */
    constructor(QorusSystemRestHelper remote, string dsname, *hash<auto> opts) : DbRemoteBase(remote, dsname, opts) {
        beginTransaction();
    }

    #! Redirects the method to the remote service and prepends the datasource name to the arguments in the remote call
    auto methodGate(string method) {
        return DbRemoteBase::methodGateArgs(method, argv);
    }
}

#! filesystem send stream base config class
/** This class creates a background thread that handles the socket I/O so that socket I/O
    can be executed in parallel to the main data acquisition thread (the thread that creates
    the object).

    There is a @ref Qore::Thread::Queue "Queue" object that passes aggregated row data to the send thread;
    the default @ref Qore::Thread::Queue "Queue" size is 2 (representing a number of blocks), which allows
    2 blocks of data to be queued before the internal private method FsRemoteSend::submitImpl() (called
    implicitly by FsRemoteSend::append()) will block.

    If the @ref Qore::Thread::Queue "Queue" size is 2 and the block size is 4096 then at most 8192 bytes
    will be queued for sending before the main thread will block in the internal private method
    FsRemoteSend::submitImpl().

    This allows the main data acquisition thread to stay loosely in sync with the I/O thread so
    that memory usage is optimized and furthermore serves to avoid stalling the I/O thread due to
    lack of data.
 */
public class OMQ::FsSendStreamConfig inherits StreamConfig, QueuedBlockConfigBase {
    private {
        #! target path
        string m_path;
        #! target file creation mode (unix privs.); default: 0644
        softint m_mode = 0644;
        #! target file encoding
        string m_encoding = get_default_encoding();

        #! minimum block size in bytes
        const MinBlockSize = 4096;
    }

    #! creates the configuration object from the arguments
    constructor(string remote, string path, *hash<auto> options) : StreamConfig("put-file", remote, options), QueuedBlockConfigBase(options) {
        setFsSendOptions(path, options);
    }

    #! creates the configuration object from the arguments
    constructor(QorusSystemRestHelper remote, string path, *hash<auto> options) : StreamConfig("put-file", remote, options), QueuedBlockConfigBase(options) {
        setFsSendOptions(path, options);
    }

    #! sets configuration options
    private setFsSendOptions(string path, *hash<auto> options) {
        m_path = path;
        if (exists options.mode)
            m_mode = options.mode;
        if (options.encoding)
            m_encoding = options.encoding;
        if (m_block < MinBlockSize)
            m_block = MinBlockSize;
    }

    #! returns the path
    string path() {
        return m_path;
    }

    #! returns the file mode
    int mode() {
        return m_mode;
    }

    #! returns the file's character encoding
    string encoding() {
        return m_encoding;
    }

    #! returns the default block size for this object (16384)
    private int getDefaultBlockSize() {
        return 16384;
    }

    #! logs the stream configuration when created
    logStreamConfigImpl(string what, string url) {
        logger("%s %y stream url: %y remote path: %y block: %d", what, m_stream, url, m_path, m_block);
    }

    #! updates the stored path
    updatePath(string path) {
        m_path = path;
    }
}

#! Filesystem stream for outbound/writing data to the remote instance
/**
    @par FsRemoteSend Background Socket I/O
    This class creates a background thread that handles the socket I/O so that socket I/O
    can be executed in parallel to the main data acquisition thread (the thread that creates
    the object).\n\n
    There is a @ref Qore::Thread::Queue "Queue" object that passes aggregated row data to the send thread;
    the default @ref Qore::Thread::Queue "Queue" size is 2 (representing a number of blocks), which allows
    2 blocks of data to be queued before the internal private FsRemoteSend::submitImpl() (called
    implicitly by DbRemoteSend::append()) will block.\n\n
    If the @ref Qore::Thread::Queue "Queue" size is 2 and the block size is 16384 then at most 32768 bytes
    will be queued for sending before the main thread will block in the internal private method
    FsRemoteSend::submitImpl().\n\n
    This allows the main data acquisition thread to stay loosely in sync with the I/O thread so
    that memory usage is optimized and furthermore serves to avoid stalling the I/O thread due to
    lack of data.

    @ref OMQ::FsRemote class can be used for synchronous calls of the remote system.fs service

    @par FsRemoteSend Usage
    Call FsRemoteSend::append() to queue data for sending, then call FsRemoteSend::commit()
    to ensure that all data have been sent to the remote server before continuing.\n\n
    In case of an error in the sending thread, FsRemoteSend::cancel() should be called to cancel
    the socket I/O send operation and shut down the socket thread.  Note that in this case the file is not
    automatically deleted; to delete the file, call omq.system.service.fs.del() manually.

    @par FsRemoteSend Example
    @code{.py}
FsRemoteSend fs(qrest, remote_fs_connection, relative_path, opts);
on_success fs.commit();
on_error fs.cancel();

map fs.append($1), dataIterator;
    @endcode

    @note This class is not thread-safe; it's designed to be used from a single thread; calling this class's methods from multiple threads simultaneously will result in unpredictable behavior
*/
public class OMQ::FsRemoteSend inherits OMQ::AbstractParallelWriteStream, DataStreamSendMessage {
    private {
        #! optional name of the user connection. It can be @ref nothing if the non-connection methods should be called
        *string m_connection;

        #! waiting data buffer
        data m_data;

        #! stream configuration
        FsSendStreamConfig m_config;
    }

    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server
    /** @par Example:
        @code{.py}
FsRemoteSend fs(remote_name, target_path, opts);
on_success fs.commit();
on_error fs.cancel();

map fs.append($1), dataIterator;
        @endcode

        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param path a string with full or relative path of the target file (inluding file name)
        @param options optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "block": data block size (default 16384, minimum 4096); the number of bytes sent in each @ref datastreamprotocol "DataStream" protocol chunk
        - \c "queue_block_size": the number of blocks to queue for sending before the main data thread will block (default: 2)
        - \c "queue_timeout": the number of milliseconds to wait for queue data before throwing a \c QUEUE-TIMEOUT exception
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        @note
        - to calculate the total data queued for the socket I/O thread, multiply \a block by \a queue_block_size (default 16384 * 2 = 32768 bytes)
        - the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
     */
    constructor(string remote, string path, *hash<auto> options) {
        m_config = new FsSendStreamConfig(remote, path, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server
    /** @par Example:
        @code{.py}
FsRemoteSend fs(remote_name, target_connection, relative_path, opts);
on_success fs.commit();
on_error fs.cancel();

map fs.append($1), dataIterator;
        @endcode

        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param conn an user connection
        @param path a string with relative path of the target file (inluding file name) under \c conn
        @param options optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "block": data block size (minimum 4096); the number of bytes sent in each @ref datastreamprotocol "DataStream" protocol chunk
        - \c "queue_block_size": the number of blocks to queue for sending before the main data thread will block (default: 2)
        - \c "queue_timeout": the number of milliseconds to wait for queue data before throwing a \c QUEUE-TIMEOUT exception
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
     */
    constructor(string remote, string conn, string path, *hash<auto> options) {
        m_connection = conn;
        m_config = new FsSendStreamConfig(remote, path, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection
    /** @par Example:
        @code{.py}
FsRemoteSend fs(qrest, target_path, opts);
on_success fs.commit();
on_error fs.cancel();

map fs.append($1), dataIterator;
        @endcode

        @param remote an @ref OMQ::QorusSystemRestHelper object
        @param path a string with full or relative path of the target file (inluding file name)
        @param options optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "block": data block size (minimum 4096); the number of bytes sent in each @ref datastreamprotocol "DataStream" protocol chunk
        - \c "queue_block_size": the number of blocks to queue for sending before the main data thread will block (default: 2)
        - \c "queue_timeout": the number of milliseconds to wait for queue data before throwing a \c QUEUE-TIMEOUT exception
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
     */
    constructor(QorusSystemRestHelper remote, string path, *hash<auto> options) {
        m_config = new FsSendStreamConfig(remote, path, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection
    /** @par Example:
        @code{.py}
FsRemoteSend fs(qrest, remote_connection, relative_path, opts);
on_success fs.commit();
on_error fs.cancel();

map fs.append($1), dataIterator;
        @endcode

        @param remote an @ref OMQ::QorusSystemRestHelper object
        @param conn an user connection
        @param path a string with relative path of the target file (inluding file name) under \c conn
        @param options optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "block": data block size (minimum 4096); the number of bytes sent in each @ref datastreamprotocol "DataStream" protocol chunk
        - \c "queue_block_size": the number of blocks to queue for sending before the main data thread will block (default: 2)
        - \c "queue_timeout": the number of milliseconds to wait for queue data before throwing a \c QUEUE-TIMEOUT exception
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
     */
    constructor(QorusSystemRestHelper remote, string conn, string path, *hash<auto> options) {
        m_connection = conn;
        m_config = new FsSendStreamConfig(remote, path, options);
        m_config.logStreamConfig("starting");
        dataq = new Queue(m_config.queueBlockSize());
        startStream();
    }

    #! signal the I/O thread to stop sending data
    private stopIoThreadImpl() {
        # push NOTHING to stop sending
        try {
            dataq.push(NOTHING, m_config.queueTimeout());
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == StreamTerminatedError)
                return;
            rethrow;
        }
    }

    #! flushes all remote I/O, terminates the I/O thread, and checks for background I/O errors, in which case an exception is thrown
    private terminateIoWait(string action) {
        terminateIoWaitIntern(action);
        m_config.logger("%s %y: sent %d byte%s in %y: %.2f bytes / second",
                        m_config.stream(), m_config.path(),
                        m_info.count, m_info.count == 1 ? "" : "s", m_info.delta, m_info.dps);
        m_info.reset();
    }

    #! no implementation in this class
    private startStreamImpl() {
    }

    #! opens the remote socket stream in the socket I/O thread and starts streaming the data
    private socketThreadImpl() {
        string conn = m_connection ? sprintf(";userconn=%s", m_connection) : "";
        string uripath = sprintf("services/fs?action=stream;stream=put-file;path=%s;encoding=%s;mode=%s%s",
                                 m_config.path(), m_config.encoding(), m_config.mode(), conn);
        m_config.debug("uri path: %y", uripath);
        hash<auto> response = m_config.remote().sendDataStream(self, "POST", uripath, m_config.timeout());
        m_config.debug("response: %y", response);
    }

    #! this method flushes all buffered I/O to the remote server and returns when all data have been sent to the server and the socket I/O thread has terminated
    /** @par Example:
        @code{.py}
FsRemoteSend fs(qrest, target_path, opts);
on_success fs.commit();
on_error fs.cancel();

map fs.append($1), dataIterator;
        @endcode

        Log messages are created with performance information (bytes send, time of transfer, bytes / second, etc).

        @note
        - either this method, flush() or cancel() should be called to ensure that all data has been sent
        - exceptions thrown in the socket I/O thread will be rethrown when this method is called so that errors can be handled in the main data thread
        - equivalent to flush()

        @see flush()
    */
    commit() {
        terminateIoWait("commit");
    }

    #! this method purges any queued I/O and stops the socket thread and returns when the socket I/O thread has terminated
    /** @par Example:
        @code{.py}
FsRemoteSend fs(qrest, target_path, opts);
on_success fs.commit();
on_error fs.cancel();

map fs.append($1), dataIterator;
        @endcode

        @note either this method or commit() should be called to ensure that all data has been sent
    */
    cancel() {
        abortIoWait("%s::cancel() called", self.className());
    }

    #! Append data to the ready queue: data
    /** @par Example:
        @code{.py}
FsRemoteSend fs(qrest, target_path, opts);
on_success fs.commit();
on_error fs.cancel();

map fs.append($1), dataIterator;
        @endcode

        @param data data to be sent

        Data are queued for sending when the buffered byte count reaches the \c block size.

        @note
        - make sure to call either commit() (to flush all data to the server) or cancel() (to cancel the I/O operation) before continuing (see the example above)
        - exceptions thrown in the socket I/O thread will be rethrown when this method is called so that errors can be handled in the main data thread
      */
    append(data data) {
        checkError("append");
        m_data += data;
        if (m_data.size() >= m_config.block())
            submitImpl();
    }

    #! Append data to the ready queue using a @ref Qore::FileLineIterator "FileLineIterator" object for input
    /** @par Example:
        @code{.py}
FsRemoteSend fs(qrest, target_path, opts);
on_success fs.commit();
on_error fs.cancel();

fs.append(i);
        @endcode

        @param it a @ref Qore::FileLineIterator "FileLineIterator" object with data to be sent to the remote server

        This method processes the whole iterator in one call.

        @note
        - make sure to call either commit() (to flush all data to the server) or cancel() (to cancel the I/O operation) before continuing (see the example above)
        - exceptions thrown in the socket I/O thread will be rethrown when this method is called so that errors can be handled in the main data thread
      */
    append(Qore::FileLineIterator it) {
        while (it.next()) {
            m_data += it.getValue();
            if (m_data.size() >= m_config.block()) {
                checkError("append");
                submitImpl();
            }
        }

        submitImpl();
    }

    #! queues buffered data to be sent in the socket I/O thread
    /** @return @ref True if the I/O thread is running, @ref False if not

        @throw IO-ERROR the I/O thread is not running so no data can be submitted
     */
    private bool submitImpl() {
        softbool rv = cnt.getCount();
        *data data = remove m_data;
        if (exists data) {
            if (!rv)
                throw "IO-ERROR", sprintf("%s: the I/O thread is not running so the data cannot be sent", m_config.stream());
            dataq.push(data, m_config.queueTimeout());
        }
        return rv;
    }

    #! executes an implicit commit() and renames/moves the file given in \c path in the constructor()
    /** @par Example:
        @code{.py}
FsRemoteSend fs(qrest, target_path, opts);
{
    on_success fs.commit();
    on_error fs.cancel();

    map fs.append($1), dataIterator;
}
fs.rename(target);
        @endcode

        @param target a new path with filename. Relative to user connection if the user connection constructor is used.
        @param man rename the file manually by copying the file's data and then deleting the source file, this is sometimes necessary on some OSes when renaming files across filesystem boundaries

        @warning The original file after the rename does not exist anymore
                 if \c man is set to @ref True. Any additional append()
                 call will result in an exception.

        @note do not call this method before all data have been sent (ie call only after calling commit() first as in the example above)
     */
    nothing rename(string target, softbool man = False) {
        # ensure the send is done before the rename
        commit();
        on_success m_config.updatePath(target);
        # TODO/FIXME: timeout?
        if (m_connection) {
            m_config.remote().put("services/fs/rename_conn?action=call",
                                         ( "args" : ( m_connection, m_config.path(), m_connection, target, man))
                                        );
        }
        else
            m_config.remote().put("services/fs/rename?action=call", ( "args" : ( m_config.path(), target, man)));
    }

    #! executes an implicit commit() and deletes the file given in \c path in the constructor()
    /** @par Example:
        @code{.py}
FsRemoteSend fs(qrest, target_path, opts);
{
    on_success fs.commit();
    on_error fs.cancel();

    map fs.append($1), dataIterator;
}
fs.del(target);
        @endcode

        @note do not call this method before all data have been sent (ie call only after calling commit() first as in the example above)
     */
    nothing del() {
        # ensure the send is done before the rename
        commit();
        # TODO/FIXME: timeout?
        if (m_connection) {
            m_config.remote().put("services/fs/del_conn?action=call", ("args": (m_connection, m_config.path())));
        }
        else
            m_config.remote().put("services/fs/del?action=call", ("args": (m_config.path())));
    }

    #! reimplemented from DataStreamClient::DataStreamSendMessage
    /** @return the data to send

        @throw STREAM-TERMINATED if the stream was terminated in the main thread, this exception will be thrown here to terminate the I/O thread
     */
    private auto sendDataImpl() {
        auto rv = dataq.get(m_config.queueTimeout());
        if (!exists rv)
            return;

        int count = rv.size();
        m_info.count += count;
        m_info.total_count += count;

        m_config.debug("sending bytes: %d; total sent: %d", count, m_info.count);

        return rv;
    }

    #! returns the configuration object
    OMQ::StreamConfig config() {
        return m_config;
    }

} # class FsRemoteSend


#! filesystem receive stream base config class
public class OMQ::FsReceiveStreamConfig inherits StreamConfig, QueuedBlockConfigBase {
    private {
        #! target path
        string m_path;
        #! target file encoding
        string m_encoding = get_default_encoding();

        #! minimum block size in bytes
        const MinBlockSize = 4096;

        #! One of supported stream types. See AbstractFsRemoteReceive public constants
        string m_streamType;

        #! Potential options for csv when is the m_streamType = AbstractFsRemoteReceive::TYPE_CSV;
        hash<auto> m_csvUtilOpts;

        #! Potential xml element for csv when is the m_streamType = AbstractFsRemoteReceive::TYPE_XML;
        string m_xmlElement;
    }

    #! creates the configuration object from the arguments
    constructor(string remote, string path, string streamType = AbstractFsRemoteReceive::TYPE_FILE, *hash<auto> options)
        : StreamConfig(streamType, remote, options), QueuedBlockConfigBase(options)
    {
        setOptions(path, streamType, options);
    }

    #! creates the configuration object from the arguments
    constructor(QorusSystemRestHelper remote, string path, string streamType = AbstractFsRemoteReceive::TYPE_FILE, *hash<auto> options)
        : StreamConfig(streamType, remote, options), QueuedBlockConfigBase(options)
    {
        setOptions(path, streamType, options);
    }

    #! sets configuration options
    private setOptions(string path, string streamType, *hash<auto> options) {
        m_streamType = streamType;
        if (!inlist(m_streamType, (AbstractFsRemoteReceive::TYPE_FILE,
                                   AbstractFsRemoteReceive::TYPE_XML,
                                   AbstractFsRemoteReceive::TYPE_CSV)))
        {
            throw "FS-REMOTE-RECEIVE-CONFIG-ERROR", sprintf("Unsuported stream type: %s", streamType);
        }

        m_path = path;
        if (options.encoding)
            m_encoding = options.encoding;
        if (m_block < MinBlockSize)
            m_block = MinBlockSize;

        if (exists options.csvutil)
            m_csvUtilOpts = options.csvutil;

        if (m_streamType == AbstractFsRemoteReceive::TYPE_XML) {
            if (!exists options.element)
                throw "FS-REMOTE-RECEIVE-CONFIG-ERROR", "get-xml-data stream type requires xml element option";
            else if (options.element.typeCode() != NT_STRING)
                throw "FS-REMOTE-RECEIVE-CONFIG-ERROR", sprintf("options.element for get-xml-data must be string, got: %s", options.element.typeName());
            m_xmlElement = options.element;
        }
    }

    string streamType() {
        return m_streamType;
    }

    #! returns the path
    string path() {
        return m_path;
    }

    #! returns the file's character encoding
    string encoding() {
        return m_encoding;
    }

    #! returns the default block size for this object (16384)
    private int getDefaultBlockSize() {
        return 16384;
    }

    *hash<auto> csvUtilOpts() {
        return m_csvUtilOpts;
    }

    *string xmlElement() {
        return m_xmlElement;
    }

    #! logs the stream configuration when created
    logStreamConfigImpl(string what, string url) {
        logger("%s %y stream url: %y remote path: %y block: %d", what, m_stream, url, m_path, m_block);
    }

    #! updates the stored path
    updatePath(string path) {
        m_path = path;
    }
}

#! A class for inbound/reading data from the remote instance's filesystem
/**
    An abstract class to receive a file from remote Qorus instance.

    The user has to reimplement the the recvDataImpl() method to handle incoming data.

    Data are received in @ref AbstractFsRemoteReceive_formats

    @note This class does not create a background thread.

    @anchor AbstractFsRemoteReceive_formats
    @par AbstractFsRemoteReceive File Fomats
    - AbstractFsRemoteReceive::TYPE_FILE - a plain text/binary file
    - AbstractFsRemoteReceive::TYPE_CSV - CsvUtil data structures
    - AbstractFsRemoteReceive::TYPE_XML - parsed XML hashes
    .
    @see AbstractFsRemoteReceive::recvDataImpl

    @anchor AbstractFsRemoteReceive_options
    @par AbstractFsRemoteReceive Options
    - \c "encoding": a filename encoding
    - \c "csvutil": a parse option hash for CsvUtil classed
    - \c "element": an element name used for XML parsing
    - any of relevant @ref stream-api-options
 */
public class OMQ::AbstractFsRemoteReceive inherits DataStreamClient::DataStreamRecvMessage {
    private {
        #! optional name of the user connection. It can be @ref nothing if the non-connection methods should be called
        *string m_connection;

        #! flag indicating that all data has been taken from the Queue
        bool complete;

        #! stream configuration
        FsReceiveStreamConfig m_config;
    }

    public {
        #! Raw file transfer
        const TYPE_FILE = "get-file";
        #! Receive CSV data
        const TYPE_CSV = "get-csv-data";
        #! Receive XML data
        const TYPE_XML = "get-xml-data";
    }

    #! Creates the object and starts receiving file data immediately
    /** @param remote a string with a @ref remoteconn "remote Qorus connection" name as defined in @ref remoteconn
        @param path a source (remote) file path
        @param streamType a string with @ref AbstractFsRemoteReceive_formats
        @param options optional @ref stream-api-options with additional @ref AbstractFsRemoteReceive_options
     */
    constructor(string remote, string path, string streamType = TYPE_FILE, *hash<auto> options) {
        m_config = new FsReceiveStreamConfig(remote, path, streamType, options);
        m_config.logStreamConfig("starting");
    }

    #! Creates the object and starts receiving file data immediately
    /** @param remote a string with a @ref remoteconn "remote Qorus connection" name as defined in @ref remoteconn
        @param conn a remote filesystem based user connection name
        @param path a source (remote) file path, relative to the \c conn root
        @param streamType a string with @ref AbstractFsRemoteReceive_formats
        @param options optional @ref stream-api-options with additional @ref AbstractFsRemoteReceive_options
     */
    constructor(string remote, string conn, string path, string streamType = TYPE_FILE, *hash<auto> options) {
        m_connection = conn;
        m_config = new FsReceiveStreamConfig(remote, path, streamType, options);
        m_config.logStreamConfig("starting");
    }

    #! Creates the object and starts receiving file data immediately
    /** @param remote a QorusSystemRestHelper object
        @param path a source (remote) file path
        @param streamType a string with @ref AbstractFsRemoteReceive_formats
        @param options optional @ref stream-api-options with additional @ref AbstractFsRemoteReceive_options
     */
    constructor(QorusSystemRestHelper remote, string path, string streamType = TYPE_FILE, *hash<auto> options) {
        m_config = new FsReceiveStreamConfig(remote, path, streamType, options);
        m_config.logStreamConfig("starting");
    }

    #! Creates the object and starts receiving file data immediately
    /** @param remote a string with a @ref remoteconn "remote Qorus connection" name as defined in @ref remoteconn
        @param conn a remote filesystem based user connection name
        @param path a source (remote) file path, relative to the \c conn root
        @param streamType a string with @ref AbstractFsRemoteReceive_formats
        @param options optional @ref stream-api-options with additional @ref AbstractFsRemoteReceive_options
     */
    constructor(QorusSystemRestHelper remote, string conn, string path, string streamType = TYPE_FILE, *hash<auto> options) {
        m_connection = conn;
        m_config = new FsReceiveStreamConfig(remote, path, streamType, options);
        m_config.logStreamConfig("starting");
    }

    #! receive reimplementation
    receive() {
        on_error m_config.remote().disconnect();
        string conn = m_connection ? sprintf(";userconn=%s", m_connection) : "";

        hash<auto> opts;
        if (m_config.streamType() == TYPE_CSV)
            opts = ( "csvutil" : m_config.csvUtilOpts() );
        else if (m_config.streamType() == TYPE_XML)
            opts = ( "element" : m_config.xmlElement() );

        m_config.remote().recvDataStream(self,
                                         "GET",
                                         sprintf("services/fs?action=stream;stream=%s;path=%s;encoding=%s;block=%s;%s",
                                                 m_config.streamType(), m_config.path(), m_config.encoding(), m_config.block(), conn),
                                         opts,
                                         m_config.timeout(),
                                         NOTHING);

    }

    #! An abstract method to handle incoming data/
    /**
        Data are comming in a form regarding the stream type:
            - TYPE_FILE: string or binary
            - TYPE_CSV: list<auto> of hashes. See CsvUtil module for reference
            - TYPE_XML: list<auto> of hashes. XML serialized hashes.
      */
    abstract nothing recvDataImpl(auto row);

    #! returns the configuration object
    OMQ::StreamConfig config() {
        return m_config;
    }

    #! rename/move currently operated file given in \c path in constructor
    /**
        @param target a new path with filename. Relative to user connection if the user connection constructor is used.
        @param man rename the file manually by copying the file's data and then deleting the source file, this is sometimes necessary on some OSes when renaming files across filesystem boundaries

        @warning The original file after the rename does not exist anymore
                 if \c man is set to @ref True. Any additional append()
                 call will result in an exception.

        @note do not call this method before all data have been received
     */
    nothing rename(string target, softbool man = False) {
        on_success
            m_config.updatePath(target);
        if (m_connection) {
            m_config.remote().put("services/fs/rename_conn?action=call",
                                  ( "args" : ( m_connection, m_config.path(), m_connection, target, man)));
        }
        else
            m_config.remote().put("services/fs/rename?action=call", ( "args" : ( m_config.path(), target, man)));
    }

    #! delete currently operated file given in \c path in constructor or any other file name
    /**
        @param target an optional new path with filename. Relative to user connection if the user connection constructor is used.
               If it's empty (\c NOTHING) the path specified in constructor is used.
               Otherwise any file name given to this method will be deleted.
     */
    nothing del(*string target) {
        target = target ?? m_config.path();
        # TODO/FIXME: timeout?
        if (m_connection) {
            m_config.remote().put("services/fs/del_conn?action=call",
                                         ( "args" : ( m_connection, target,))
                                        );
        }
        else
            m_config.remote().put("services/fs/del?action=call", ( "args" : (target,)));
    }

    #! delete currently operated file given in \c path in constructor or any other file name
    /**
        @param target an optional new path with filename. Relative to user connection if the user connection constructor is used.
               If it's empty (\c NOTHING) the path specified in constructor is used.
               Otherwise any file name given to this method will be deleted.
     */
    nothing delete(*string target) {
        del(target);
    }
} # class AbstractFsRemoteReceive

#! A high level API for a remote @ref system_fs "system.fs service"
/** FsRemote provides a high level API for the @ref system_fs "system.fs service" in remote
    Qorus instances. Use it for single filesystem operations.

    @warning Use @ref OMQ::FsRemoteSend and @ref OMQ::AbstractFsRemoteReceive for sending and retrieving
             large files. These classes are optimized for high volume data.
             Any use of e.g. FsRemote::write_file() will store all data in the memory
             and the data will be transferred in a single call.

    @section FsRemote_api_calls FsRemote API calls

    This class does not have any of its own methods; all method calls are redirected to the @ref system_fs "system.fs service" transparently.

    @par Example of usage

    @code{.py}
%new-style
%requires QorusClientCore

QorusClient::init2();

FsRemote fs("msepl-it");

list<auto> ls = fs.ls("/tmp"); # list files in /tmp directory
printf("%N\n", ls);
    @endcode
 */
public class OMQ::FsRemote {
    private {
        StreamConfig m_config;
    }

    #! constructor taking a string giving the name of the @ref remoteconn "remote connection" for the remote server
    /**
        @param remote a string giving the name of the @ref remoteconn "remote connection" for the remote server
        @param opts optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
    */
    constructor(string remote, *hash<auto> opts) {
        m_config = new StreamConfig("fs-remote", remote, opts);
    }

    #! constructor taking an @ref OMQ::QorusSystemRestHelper object for the remote connection
    /**
        @param remote an @ref OMQ::QorusSystemRestHelper object
        @param opts optional @ref stream-api-options as follows:
        - \c "timeout": an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O and queue operations; default value: \c 5m
        - \c "loglevel": a default log level option for logging; see @ref LogLevels for valid value
        - \c "no_remote_timeout": if @ref True the \c "timeout" option will not be sent to the remote

        @note the explicit or default timeout value here overrides any socket I/O timeout set for the remote connection object
     */
    constructor(QorusSystemRestHelper remote, *hash<auto> opts) {
        m_config = new StreamConfig("fs-remote", remote, opts);
    }

    #! returns the configuration object
    OMQ::StreamConfig config() {
        return m_config;
    }

    #! Disconnects the connection
    disconnect() {
        QorusSystemRestHelper remote = m_config.remote();
        AbstractParallelStream::checkStream(remote, "FsRemote::disconnect()");
        # disconnect connection
        remote.disconnect();
    }

    auto methodGate(string method) {
        if (method !~ /[a-zA-Z_]+/)
            throw "FS-REMOTE-ERROR", sprintf("Not allowed method name: %s", method);
        string cmd = sprintf("services/fs/%s?action=call", method);
        QorusSystemRestHelper remote = m_config.remote();
        AbstractParallelStream::checkStream(remote, "FsRemote::" + method + "()");
        auto ret = remote.put(cmd, ("args" : argv));
        return ret;
    }
} # class FsRemote
