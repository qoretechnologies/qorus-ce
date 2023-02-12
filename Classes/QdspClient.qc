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

class QdspTransaction inherits AbstractThreadResource {
    public {
        # transaction ID
        string trans_id = UUID::get();
    }

    private {
        # TID of creating thread
        int tid = gettid();

        # client with an active transaction in this thread
        QdspClient dsp;
    }

    constructor(QdspClient dsp) {
        self.dsp := dsp;
        set_thread_resource(self);
    }

    destructor() {
%ifdef QorusDebugInternals
        if (gettid() != tid && dsp && !dsp.stopping()) {
            QDBG_LOG("ERROR: QdspTransaction %y for %y created in TID %d, being deleted in TID %d", trans_id,
                dsp.getConfigString(), tid, gettid());
            QDBG_ASSERT(False);
        }
%endif
        remove_thread_resource(self);
    }

    string getId() {
        return trans_id;
    }

    int getTid() {
        return tid;
    }

    cleanup() {
        if (self)
            dsp.threadTerminated(trans_id);
    }
}

# remote datasource pool client
/** the character encoding reported by this object will always be UTF-8
    although the encoding used by the qdsp process may differ
*/
class QdspClient inherits Qore::SQL::AbstractDatasource, AbstractQorusClient {
    public {}

    private {
        # map from TID -> transaction object
        hash<string, QdspTransaction> tt;

        # default ping timeout
        const PingTimeout = 30s;
    }

    private:internal {
        # connect string info
        string connstr;

        # connection hash
        hash<auto> conn_hash;

        # real name of driver
        string driver_real_name;

        # capabilities
        int caps;

        # connstr mutex
        Mutex m();

        # send context information with new transactions
        bool set_context;

        # stop flag
        bool stop;

        # coordinator mode
        bool coord_mode;

        # coordinator mode transactions; TID -> datasource
        hash<string, Datasource> coord_trans_map;
    }

    #! creates the object
    /** @param process the owning process object
        @param name the name of the qdsp client process
        @param opts optional arguments:
        - \c set_context: send context information with each new transaction

        @note the GET-INFO request is made in the constructor to set up the object
    */
    constructor(AbstractQorusClientProcess process, string name, *hash<auto> opts) : AbstractQorusClient(process, QDP_NAME_QDSP, name) {
        # first get the qdsp configuration including the DB connection string and qdsp mode
        hash<auto> info;
        try {
            info = getInfo();
        } catch (hash<ExceptionInfo> ex) {
            if (process) {
                process.deregisterClient(self, unique_client_id, queue_created);
            }
            rethrow;
        }
        coord_mode = info.coord_mode;
        connstr = info.db_connstr;
        conn_hash = parse_datasource(info.connstr);
        driver_real_name = info.driver_real_name;

        if (opts.set_context && conn_hash.type != "oracle") {
            # see if the DB is oracle, only set context info with oracle
            opts.set_context = False;
        }
        set_context = opts.set_context ?? False;
    }

    destructor() {
        stop = True;

        # release any coordinated transactions
        if (coord_trans_map) {
            foreach Datasource ds in (coord_trans_map.iterator()) {
                try {
                    ds.rollback();
                } catch () {
                    # ignore exceptions
                }
                ds.close();
            }
            if (coord_trans_map.size() == 1) {
                throw "DATASOURCEPOOL-ERROR", sprintf("datasource %y (local coordinated) closed with local "
                    "TID: %d with an allocated connection; the transaction has been rolled back", server_name,
                    coord_trans_map.firstKey());
            } else {
                throw "DATASOURCEPOOL-ERROR", sprintf("datasource %y (local coordinated) closed with local "
                    "TIDs: %y with allocated connections; transactions have been rolled back", server_name,
                    (map $1.toInt(), keys coord_trans_map));
            }
        }

        # release any remote connections
        *hash<string, QdspTransaction> tt = remove self.tt;
        if (tt) {
            foreach QdspTransaction trans in (tt.iterator()) {
                try {
                    rollbackIntern(trans.getId());
                } catch () {
                    # ignore exceptions
                }
                delete trans;
            }
            if (tt.size() > 1) {
                throw "DATASOURCEPOOL-ERROR", sprintf("datasource %y (remote pool) at %y closed with local "
                    "TIDs: %y holding a remote transaction lock; the transactions have been rolled back and the "
                    "connections have been returned to the pool", server_name, process ? getUrls() : "n/a",
                    (map $1.toInt(), keys tt));
            } else {
                throw "DATASOURCEPOOL-ERROR", sprintf("datasource %y (remote pool) at %y closed with local "
                    "TID %d holding a remote transaction lock; the transaction has been rolled back and the "
                    "connection has been returned to the pool", server_name, process ? getUrls() : "n/a",
                    tt.firstKey());
            }
        }
    }

    bool stopping() {
        return stop;
    }

    # we need to get the new qdsp mode and connection information and notify the new qdsp process of how many
    # connections we have in progress if the client and server are in coordinated mode
    abortedProcessNotification(string id, *hash<ClusterProcInfo> proc_info, bool restarted, date abort_timestamp) {
        AbstractQorusClient::abortedProcessNotification(id, proc_info, restarted, abort_timestamp);
        if (id != proc_name) {
            return;
        }
        if (restarted) {
            # issue #2918: we cannot make a ZMQ call in the event thread
            background qdspRestarted();
        }
    }

    private qdspRestarted() {
        hash<auto> info = getInfo();
%ifdef QorusDebugInternals
        # a race condition can lead to connstr being missing in this call somehow according to
        # an exception encountered debugging qdsp restarts - if this happens, log the info var
        if (!info.connstr) {
            QDBG_LOG("%y info: %y", server_name, info);
        }
%endif
        QDBG_ASSERT(exists info.connstr);
        if (coord_mode) {
            int num = coord_trans_map.size();
            log(LoggerLevel::INFO, "qdsp process %y terminated unexpectedly with %d transaction%s in progress; current "
                "mode: %y new mode: %y", server_name, num, num == 1 ? "" : "s", coord_mode, info.coord_mode);
            if (info.coord_mode) {
                # FIXME: issue #2692: notify qdsp server of any transactions in progress
            } else {
                coord_mode = False;
            }
        } else {
            int num = tt.size();
            log(LoggerLevel::INFO, "qdsp process %y terminated unexpectedly with %d transaction%s in progress; current "
                "mode: %y new mode: %y", server_name, num, num == 1 ? "" : "s", coord_mode, info.coord_mode);
            if (info.coord_mode) {
                coord_mode = True;
            }
        }
        if (info.db_connstr != connstr) {
            log(LoggerLevel::INFO, "qdsp process %y restarted with a new connection string; old %y -> %y ; updated",
                server_name, connstr, info.connstr);
            connstr = info.db_connstr;
            conn_hash = parse_datasource(info.connstr);
            driver_real_name = info.driver_real_name;
        }
    }

    threadTerminated(string id) {
        rollbackIntern(id);
        # issue #3685 ensure that the transaction object gets deleted in this thread
        delete tt{gettid()};
        throw "DATASOURCEPOOL-LOCK-EXCEPTION", sprintf("TID %d terminated while in a remote transaction with "
            "datasource %y at %y; the transaction has been rolled back", gettid(), server_name, getUrls());
    }

    bool coordMode() {
        return coord_mode;
    }

    *Datasource getCoordDatasource() {
        return coord_trans_map{gettid()};
    }

    bool currentThreadInTransaction() {
        softstring tid = gettid();
        return coord_trans_map{tid} || exists tt{tid};
    }

    bool inTransaction() {
        softstring tid = gettid();
        return coord_trans_map{tid} || exists tt{tid};
    }

    bool ping() {
        hash<auto> h();
        if (!coord_mode) {
            *QdspTransaction t = tt{gettid()};
            h.trans = t ? t.trans_id : QDSP_TempTrans;
        }
        list<string> msgs;
        while (True) {
            try {
                msgs = AbstractQorusClient::sendCmd(CPC_DSP_PING, h, PingTimeout);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "QUEUE-TIMEOUT") {
                    return False;
                }
                rethrow;
            }
            break;
        }

        return qorus_cluster_deserialize(checkResponseMsg(CPC_DSP_PING, CPC_DSP_PONG, msgs)[0]).status;
    }

    reset(hash<auto> conn_hash) {
        try {
            checkResponseMsg(CPC_DSP_RESET, CPC_ACK, sendCmdUnreliable(CPC_DSP_RESET, conn_hash));
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CLIENT-ABORTED") {
                log(LoggerLevel::INFO, "qdsp process %y aborted during reset; ignoring", proc_name);
                return;
            }
            rethrow;
        }
        qdspRestarted();
        log(LoggerLevel::INFO, "updated connection info for qdsp process %y", proc_name);
    }

    persistCoordinated(Datasource ds) {
        coord_trans_map{gettid()} = ds;
    }

    releaseCoordinated() {
        remove coord_trans_map{gettid()};
    }

    bool releaseIfPersistent() {
        return exists (remove coord_trans_map{gettid()});
    }

    auto select(string sql) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.vselect(sql, argv);
        } else {
            return doSqlCommand(CPC_DSP_SELECT_COLUMNS, sql, argv);
        }
    }

    auto vselect(string sql, *softlist<auto> vargs) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.vselect(sql, vargs);
        } else {
            return doSqlCommand(CPC_DSP_SELECT_COLUMNS, sql, vargs);
        }
    }

    auto selectRows(string sql) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.vselectRows(sql, argv);
        } else {
            return doSqlCommand(CPC_DSP_SELECT_ROWS, sql, argv);
        }
    }

    auto vselectRows(string sql, *softlist<auto> vargs) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.vselectRows(sql, vargs);
        } else {
            return doSqlCommand(CPC_DSP_SELECT_ROWS, sql, vargs);
        }
    }

    auto selectRow(string sql) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.vselectRow(sql, argv);
        } else {
            return doSqlCommand(CPC_DSP_SELECT_ROW, sql, argv);
        }
    }

    auto vselectRow(string sql, *softlist<auto> vargs) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.vselectRow(sql, vargs);
        } else {
            return doSqlCommand(CPC_DSP_SELECT_ROW, sql, vargs);
        }
    }

    auto exec(string sql) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.vexec(sql, argv);
        } else {
            return doSqlCommandImplicitTrans(CPC_DSP_EXEC, sql, argv);
        }
    }

    auto vexec(string sql, *softlist<auto> vargs) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.vexec(sql, vargs);
        } else {
            return doSqlCommandImplicitTrans(CPC_DSP_EXEC, sql, vargs);
        }
    }

    auto execRaw(string sql) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.execRaw(sql);
        } else {
            return doSqlCommandImplicitTrans(CPC_DSP_EXEC_RAW, sql);
        }
    }

    auto getOption(string opt) {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.getOption(opt);
        } else {
            return deserialize(sendSqlCommand(CPC_DSP_GET_OPTION, {"opt": opt}, CPC_OK)[0]).val;
        }
    }

    hash<auto> getOptionHash() {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.getOptionHash();
        } else {
            return deserialize(sendSqlCommand(CPC_DSP_GET_OPTION_HASH, NOTHING, CPC_OK)[0]).val;
        }
    }

    *string beginTransaction() {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.beginTransaction();
        } else {
            # return immediately if we are already in a transaction
            reference<*QdspTransaction> t = \tt{gettid()};
            if (t)
                return;
            t = new QdspTransaction(self);

            # start a dedicated transaction thread in the qdsp server with an allocated datasource connection
            # += is used to that hash<auto> will work
            hash<auto> h += {
                # issue #2624: use the unique network ID for the process name so that if a process dies, the entry can be
                # cleared in the qdsp process; the process name must match the name given in the termination message
                "process": process.getNetworkId(),
                "trans": t.trans_id,
            };

            if (set_context)
                h.ctx = getContext();

            try {
                checkResponseMsg(CPC_DSP_BEGIN_TRANS, CPC_ACK, sendCmd(CPC_DSP_BEGIN_TRANS, h));
                return t.trans_id;
            } catch (hash<ExceptionInfo> ex) {
                clearTransaction();
                rethrow;
            }
        }
    }

    rollback() {
        if (coord_mode) {
            # ignore rollback calls if no connection is allocated
            *Datasource allocated_ds = coord_trans_map{gettid()};
            if (allocated_ds) {
                CoordDatasourceHelper ds(self, allocated_ds);
                ds.rollback();
            }
        } else {
            *QdspTransaction t = remove tt{gettid()};
            # return immediately if we are not in a transaction
            if (!t) {
                return;
            }
            # issue #3685 ensure that the transaction object gets deleted in this thread
            on_exit delete t;

            rollbackIntern(t.trans_id);
        }
    }

    commit() {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            ds.commit();
        } else {
            *QdspTransaction t = remove tt{gettid()};
            # return immediately if we are not in a transaction
            if (!t) {
                return;
            }
            # issue #3685 ensure that the transaction object gets deleted in this thread
            on_exit delete t;

            hash<auto> h.trans = t.trans_id;
            checkResponse(CPC_DSP_COMMIT, CPC_ACK, sendCmd(CPC_DSP_COMMIT, h));
        }
    }

    #! returns a context hash to be sent in all new transactions if set_context is True
    *hash<auto> getContext() {
%ifdef QorusHasAnyIxApi
        return UserApi::getUserContextInfo();
%endif
    }

    transDone() {
        # remove transaction unconditionally
        # issue #3685 ensure that the transaction object gets deleted in this thread
        delete tt{gettid()};
    }

    *string getHostName() {
        return parse_datasource(getConfigString()).host;
    }

    *string getDBEncoding() {
        return parse_datasource(getConfigString()).charset;
    }

    *string getDBCharset() {
        return getDBEncoding();
    }

    *int getPort() {
        return parse_datasource(getConfigString()).port;
    }

    *string getOSEncoding() {
        return "UTF-8";
    }

    *string getOSCharset() {
        return getOSEncoding();
    }

    int getCapabilities() {
        if (exists caps) {
            return caps;
        }

        m.lock();
        on_exit m.unlock();
        if (!exists caps) {
            if (coord_mode) {
                CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
                caps = ds.getCapabilities();
            } else {
                caps = checkResponseMsg(CPC_DSP_GET_CAPS, CPC_OK, sendCmd(CPC_DSP_GET_CAPS))[0].toInt();
            }
        }
        return caps;
    }

    string toString() {
        if (coord_mode) {
            return sprintf("coordinated pool: %y", coord_trans_map);
        } else {
            try {
                return checkResponseMsg(CPC_DSP_TO_STRING, CPC_OK, sendCmd(CPC_DSP_TO_STRING))[0];
            } catch (hash<ExceptionInfo> ex) {
                return sprintf("qdsp process error: %s: %s", ex.err, ex.desc);
            }
        }
    }

    hash<auto> getUsageInfo() {
        return deserialize(checkResponseMsg(CPC_DSP_GET_USAGE, CPC_OK, sendCmd(CPC_DSP_GET_USAGE))[0]);
    }

    # TODO
    int getErrorTimeout() {
        return 0;
    }

    updateConfigString(string new_db_connstr, string new_connstr, string new_driver_real_name) {
        m.lock();
        on_exit m.unlock();

        connstr = new_db_connstr;
        conn_hash = parse_datasource(new_connstr);
        driver_real_name = new_driver_real_name;
    }

    string getConfigString() {
        return connstr;
    }

    *string getDBName() {
        return conn_hash.db;
    }

    *string getPassword() {
        return conn_hash.pass;
    }

    string getDriverName() {
        return conn_hash.type;
    }

    string getDriverRealName() {
        return driver_real_name;
    }

    hash<auto> getConfigHash() {
        return conn_hash;
    }

    *string getUserName() {
        return conn_hash.user;
    }

    auto getServerVersion() {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.getServerVersion();
        } else {
            return doSqlCommand(CPC_DSP_GET_SERVER_VER);
        }
    }

    auto getClientVersion() {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.getClientVersion();
        } else {
            return doSqlCommand(CPC_DSP_GET_CLIENT_VER);
        }
    }

    AbstractSQLStatement getSQLStatement() {
        return new QdspStatement(self);
    }

    AbstractQorusClientProcess getProcess() {
        return process;
    }

    string getProcessId() {
        return process.getProcessId();
    }

    hash<auto> getDriverInfo() {
        if (coord_mode) {
            CoordDatasourceHelper ds(self, coord_trans_map{gettid()});
            return ds.getDriverInfo();
        } else {
            return deserialize(checkResponseMsg(CPC_DSP_GET_DRIVER_INFO, CPC_OK, sendCmd(CPC_DSP_GET_DRIVER_INFO))[0]);
        }
    }

    *list<string> sendCmd(string cmd, *hash<auto> h) {
        try {
            #QDBG_LOG("QdspClient::sendCmd() cmd: %y h: %y", cmd, h);
            return sendCmdUnreliable(cmd, h);
        } catch (hash<ExceptionInfo> ex) {
            #QDBG_LOG("QdspClient::sendCmd() %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            if (ex.err == "CLIENT-ABORTED") {
                throw "DATASOURCEPOOL-PROCESS-ERROR", sprintf("remote datasource pool process %y disappeared; restart the SQL operation", proc_name);
            }
            rethrow;
        }
    }

    *list<string> sendSqlCommand(string cmd, *hash<auto> h, string rcmd) {
        try {
            *QdspTransaction t = tt{gettid()};
            h.trans = t ? t.trans_id : QDSP_TempTrans;
            *list<string> msgs = sendCmd(cmd, h);
            msgs = checkResponseMsg(cmd, rcmd, msgs);
            return msgs;
        } catch (hash<ExceptionInfo> ex) {
            if (ex.arg.ex.err) {
                Qorus.checkResetDatasource(server_name, ex.arg.ex);
            }
            rethrow;
        }
    }

    *list<string> sendSqlCommandImplicitTrans(string cmd, *hash<auto> h, string rcmd) {
        *QdspTransaction t = tt{gettid()};
        bool new_trans;
        if (t) {
            h.trans = t.trans_id;
        } else {
            # if we are starting an implicit transaction, then execute a begin transaction operation on the server
            h.trans = beginTransaction();
            new_trans = True;
        }

        try {
            return checkResponseMsg(cmd, rcmd, sendCmd(cmd, h));
        } catch (hash<ExceptionInfo> ex) {
            if (new_trans) {
                forceRollback();
            }
            if (ex.arg.ex.err) {
                Qorus.checkResetDatasource(server_name, ex.arg.ex);
            }
            rethrow;
        }
    }

    auto deserialize(data msg) {
        auto rv = qorus_cluster_deserialize(msg);
        if (rv.sids) {
            foreach hash<auto> sh in (rv.val.pairIterator()) {
                if ((*string sid = sh.value._sid_) && rv.sids{sid}) {
                    rv.val{sh.key} = new QdspRemoteStatement(self, sid);
                }
            }
        }
        return rv;
    }

    private forceRollback() {
        # return immediately if we are not in a transaction
        reference<QdspTransaction> t = \tt{gettid()};
        # remove transaction unconditionally on exit
        on_exit remove t;

        rollbackIntern(t.trans_id);
    }

    private auto doSqlCommandImplicitTrans(string cmd, *string sql, *list<auto> args) {
        hash<auto> h;
        if (exists sql)
            h.sql = sql;
        if (args)
            h.args = args;
        return deserialize(sendSqlCommandImplicitTrans(cmd, h, CPC_OK)[0]).val;
    }

    private auto doSqlCommand(string cmd, *string sql, *list<auto> args) {
        #QDBG_LOG("doSqlCommand() %y: sql: %y args: %y", cmd, sql, args);
        #auto rv = deserialize(doSqlCommandIntern(cmd, sql, args)[0]).val;
        #QDBG_LOG("doSqlCommand() rv: %y", rv);
        #return rv;
        return deserialize(doSqlCommandIntern(cmd, sql, args)[0]).val;
    }

    private *list<string> doSqlCommandIntern(string cmd, *string sql, *list<auto> args, string rcmd = CPC_OK) {
        hash<auto> h;
        if (exists sql)
            h.sql = sql;
        if (args)
            h.args = args;
        return sendSqlCommand(cmd, h, rcmd);
    }

    # send a rollback cmd and wait for the "transaction done" response
    /** @return True if the rollback succeeded, False if not
    */
    private bool rollbackIntern(string trans_id) {
        try {
            hash<auto> h.trans = trans_id;
            return checkResponse(CPC_DSP_ROLLBACK, CPC_ACK, sendCmd(CPC_DSP_ROLLBACK, h));
        } catch (hash<ExceptionInfo> ex) {
            error("%s: %s: failed to roll back transaction", ex.err, ex.desc);
        }
        return False;
    }

    private clearTransaction() {
        delete tt{gettid()};
    }

    private string logUnexpectedResponse(string req_cmd, string expected, *string actual, *list<string> msgs,
        *bool throw_exception) {
        if (actual == CPC_DSP_EXCEPTION) {
            hash<auto> eh = deserialize(msgs[0]);
            # ensure that if the server-side transaction was lost, that it's reflected in the client
            if (!coord_mode && !eh.in_trans && tt{gettid()}) {
                # issue #3685 ensure that the transaction object gets deleted in this thread
                delete tt{gettid()};
            }
            # log the error
            return logException(req_cmd, expected, eh.ex, throw_exception);
        }
        return AbstractQorusClient::logUnexpectedResponse(req_cmd, expected, actual, msgs, throw_exception);
    }
}

class CoordDatasourceHelper {
    private {
        QdspClient dsp;
        Datasource ds;
        bool release;
    }

    constructor(QdspClient dsp, *Datasource ds) {
        self.dsp = dsp;
        if (!ds) {
            string connstr = dsp.getConfigString();
            # request connection authorization and get new connection string, if any
            hash<auto> h = {
                "process": dsp.getProcess().getNetworkId(),
                # use both the unique client ID and the TID to ensure that the same client can be
                # used with unique connections in different
                "trans": dsp.getClientId() + "-" + gettid(),
            };
            hash<auto> new_info = qorus_cluster_deserialize(dsp.checkResponseMsg(CPC_DSP_CONN_GET, CPC_OK,
                dsp.sendCmd(CPC_DSP_CONN_GET, h))[0]);
            # if an exception happens in the constructor, the destructor is not run; we have to release any
            # connection here in case of an exception after this point
            try {
                if (connstr != new_info.db_connstr) {
                    dsp.updateConfigString(new_info.db_connstr, new_info.connstr, new_info.driver_real_name);
                }
                #dsp.log(LoggerLevel::DEBUG, "AUTHORIZED h: %y (%y)", h, conn_hash);
                self.ds = ds = new Datasource(new_info.db_connstr);
                ds.open();
                release = True;
            } catch (hash<ExceptionInfo> ex) {
                releaseIgnoreExceptions(h);
                rethrow;
            }
            #dsp.log(LoggerLevel::DEBUG, "%s (%s): ASSIGNED CONN", dsp.uniqueHash(), self.uniqueHash());
        } else {
            release = False;
            self.ds = ds;
            #dsp.log(LoggerLevel::DEBUG, "%s (%s): CONTINUING CONN", dsp.uniqueHash(), self.uniqueHash());
            #dsp.log(LoggerLevel::DEBUG, "stack: %y", (map sprintf("%s() (%s:%d)", $1.function, $1.file, $1.line), get_thread_call_stack()[2..]));
        }
    }

    destructor() {
        # for the destructor to be run, it means that the constructor did not throw an exception
        # so "ds" must be assigned
        if (release) {
            if (ds.inTransaction()) {
                #dsp.log(LoggerLevel::DEBUG, "%s (%s): PERSIST CONN (LOCAL)", dsp.uniqueHash(), self.uniqueHash());
                dsp.persistCoordinated(ds);
                release = False;
            }
        } else if (!ds.inTransaction()) {
            release = dsp ? dsp.releaseIfPersistent() : False;
        }

        if (release) {
            #dsp.log(LoggerLevel::DEBUG, "%s (%s): RELEASING CONN (REMOTE)", dsp.uniqueHash(), self.uniqueHash());
            releaseIgnoreExceptions();
        }
    }

    hash<auto> getDriverInfo() {
        return get_module_hash(){ds.getDriverName()};
    }

    Datasource getDatasource() {
        return ds;
    }

    persist() {
        if (release) {
            dsp.persistCoordinated(ds);
            release = False;
        }
    }

    auto methodGate(string meth) {
        # simulate a DatasourcePool; if an exception occurs in the first action of a new transaction
        # then no transaction state is saved
        try {
            return call_object_method_args(ds, meth, argv);
        } catch () {
            if (release) {
                ds.rollback();
            }
            rethrow;
        }
    }

    private:internal releaseIgnoreExceptions(string process = dsp.getProcess().getNetworkId()) {
        return releaseIgnoreExceptions({
            "process": process,
            "trans": dsp.getClientId() + "-" + gettid(),
        });
    }

    private:internal releaseIgnoreExceptions(hash<auto> release_hash) {
        try {
            # release the connection in the server immediately
            dsp.checkResponseMsg(CPC_DSP_CONN_REL, CPC_ACK, dsp.sendCmd(CPC_DSP_CONN_REL, release_hash));
        } catch (hash<ExceptionInfo> ex) {
            # ignore exceptions
        }
        #printf("tid %d: RELEASED %yn", gettid(), release_hash);
    }
}

class QdspStatement inherits AbstractSQLStatement {
    private:internal {
        AbstractSQLStatement stmt;
    }

    constructor(QdspClient dsp) {
        if (dsp.coordMode()) {
            stmt = new QdspCoordStatement(dsp, dsp.getCoordDatasource());
        } else {
            stmt = new QdspRemoteStatement(dsp);
        }
    }

    nothing rollback() {
        stmt.rollback();
    }

    list<auto> fetchRows(softint rows = -1) {
        return stmt.fetchRows(rows);
    }

    *string getSQL() {
        return stmt.getSQL();
    }

    nothing prepare(string sql) {
        softlist<auto> vargs = sql;
        if (argv) {
            vargs += argv;
        }
        call_object_method_args(stmt, "prepare", vargs);
    }

    nothing prepareRaw(string sql) {
        stmt.prepareRaw(sql);
    }

    nothing execArgs(softlist<auto> vargs) {
        stmt.execArgs(vargs);
    }

    bool active() {
        return stmt.active();
    }

    hash<auto> getOutputRows() {
        return stmt.getOutputRows();
    }

    hash<auto> getOutput() {
        return stmt.getOutput();
    }

    bool next() {
        return stmt.next();
    }

    hash<auto> fetchColumns(softint rows = -1) {
        return stmt.fetchColumns(rows);
    }

    nothing bindPlaceholders() {
        stmt.bindPlaceholdersArgs(argv);
    }

    nothing exec() {
        stmt.exec();
    }

    nothing beginTransaction() {
        stmt.beginTransaction();
    }

    nothing define() {
        stmt.define();
    }

    hash<auto> describe() {
        return stmt.describe();
    }

    *hash<auto> fetchRow() {
        return stmt.fetchRow();
    }

    nothing bindValuesArgs(softlist<auto> vargs) {
        stmt.bindValuesArgs(vargs);
    }

    nothing bindValues() {
        stmt.bindValuesArgs(argv);
    }

    nothing commit() {
        stmt.commit();
    }

    *hash<auto> getValue() {
        return stmt.getValue();
    }

    bool valid() {
        return stmt.valid();
    }

    int affectedRows() {
        return stmt.affectedRows();
    }

    bool currentThreadInTransaction() {
        return stmt.currentThreadInTransaction();
    }

    nothing bindArgs(softlist<auto> vargs) {
        stmt.bindArgs(vargs);
    }

    nothing close() {
        stmt.close();
    }

    nothing bind() {
        stmt.bindArgs(argv);
    }

    nothing bindPlaceholdersArgs(softlist<auto> vargs) {
        stmt.bindPlaceholdersArgs(vargs);
    }

    auto memberGate(string key) {
        hash<auto> h = stmt.fetchRow();
        auto rv = h{key};
        if (!exists rv && !h.hasKey(key)) {
            throw "SQLSTATEMENT-COLUMN-ERROR", sprintf("The given column name ('%s') does not exist in the current "
                "row data", key);
        }
        return rv;
    }
}

# remote SQL Statement client for coordinated mode
class QdspCoordStatement inherits AbstractSQLStatement {
    private {
        CoordDatasourceHelper ds;
        SQLStatement stmt;
    }

    constructor(QdspClient dsp, *Datasource ds) {
        self.ds = new CoordDatasourceHelper(dsp, ds);
        stmt = new SQLStatement(self.ds.getDatasource());
        self.ds.persist();
    }

    auto memberGate(string key) {
        hash<auto> h = fetchRow();
        auto rv = h{key};
        if (!exists rv && !h.hasKey(key)) {
            throw "SQLSTATEMENT-COLUMN-ERROR", sprintf("The given column name ('%s') does not exist in the current "
                "row data", key);
        }
        return rv;
    }

    nothing rollback() {
        stmt.rollback();
    }

    nothing commit() {
        stmt.commit();
    }

    nothing prepare(string sql) {
        softlist<auto> vargs = sql;
        if (argv) {
            vargs += argv;
        }
        call_object_method_args(stmt, "prepare", vargs);
    }

    nothing prepareRaw(string sql) {
        stmt.prepareRaw(sql);
    }

    list<auto> fetchRows(softint rows = -1) {
        return stmt.fetchRows(rows);
    }

    hash<auto> fetchColumns(softint rows = -1) {
        return stmt.fetchColumns(rows);
    }

    *hash<auto> fetchRow() {
        return stmt.fetchRow();
    }

    *string getSQL() {
        return stmt.getSQL();
    }

    nothing execArgs(softlist<auto> vargs) {
        stmt.execArgs(vargs);
    }

    nothing exec() {
        stmt.execArgs(argv);
    }

    bool active() {
        return stmt.active();
    }

    bool next() {
        return stmt.next();
    }

    bool valid() {
        return stmt.valid();
    }

    bool currentThreadInTransaction() {
        return stmt.currentThreadInTransaction();
    }

    hash<auto> getOutputRows() {
        return stmt.getOutputRows();
    }

    hash<auto> getOutput() {
        return stmt.getOutput();
    }

    nothing bindPlaceholders() {
        stmt.bindPlaceholdersArgs(argv);
    }

    nothing bindPlaceholdersArgs(softlist<auto> vargs) {
        stmt.bindPlaceholdersArgs(vargs);
    }

    nothing bindValues() {
        stmt.bindValuesArgs(argv);
    }

    nothing bindValuesArgs(softlist<auto> vargs) {
        stmt.bindValuesArgs(vargs);
    }

    nothing bind() {
        stmt.bindArgs(argv);
    }

    nothing bindArgs(softlist<auto> vargs) {
        stmt.bindArgs(vargs);
    }

    nothing beginTransaction() {
        stmt.beginTransaction();
    }

    nothing define() {
        stmt.define();
    }

    hash<auto> describe() {
        return stmt.describe();
    }

    *hash<auto> getValue() {
        return stmt.getValue();
    }

    int affectedRows() {
        return stmt.affectedRows();
    }

    nothing close() {
        stmt.close();
    }
}

# remote SQL Statement client
class QdspRemoteStatement inherits AbstractSQLStatement {
    private {
        QdspClient dsp;
        # process
        AbstractQorusClientProcess process;
        # unique process ID
        string process_id;
        # unique statement ID
        string sid;
        # SQL statement
        string sql;
    }

    constructor(QdspClient dsp, *string sid) {
        self.dsp = dsp;
        process = dsp.getProcess();
        # we need to use the network ID so that if the process dies, transactions and statements can be cleared
        process_id = process.getNetworkId();
        self.sid = sid ?? UUID::get();
    }

    destructor() {
        try {
            sendSqlCommand(CPC_DSP_STMT_DELETE, NOTHING, CPC_ACK);
        } catch (hash<ExceptionInfo> ex) {
            # only log the error if the datasource pool client has not been deleted and the process object still exists
            if (dsp && process)
                process.error("%s: %s: failed to delete statement", ex.err, ex.desc);
        }
    }

    string getSid() {
        return sid;
    }

    auto memberGate(string key) {
        hash<auto> h = fetchRow();
        auto rv = h{key};
        if (!exists rv && !h.hasKey(key))
            throw "SQLSTATEMENT-COLUMN-ERROR", sprintf("The given column name ('%s') does not exist in the current row data", key);
        return rv;
    }

    nothing rollback() {
        sendSqlCommand(CPC_DSP_STMT_ROLLBACK, NOTHING, CPC_ACK);
        dsp.transDone();
    }

    nothing commit() {
        sendSqlCommand(CPC_DSP_STMT_COMMIT, NOTHING, CPC_ACK);
        dsp.transDone();
    }

    nothing prepare(string sql) {
        self.sql = sql;
        sendSqlCommand(CPC_DSP_STMT_PREPARE, {"sql": sql, "args": argv}, CPC_ACK);
    }

    nothing prepareRaw(string sql) {
        self.sql = sql;
        sendSqlCommand(CPC_DSP_STMT_PREPARE_RAW, {"sql": sql}, CPC_ACK);
    }

    list<auto> fetchRows(softint rows = -1) {
        *list<string> msgs = sendSqlCommandImplicitTrans(CPC_DSP_STMT_FETCH_ROWS, {"rows": rows}, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    hash<auto> fetchColumns(softint rows = -1) {
        *list<string> msgs = sendSqlCommandImplicitTrans(CPC_DSP_STMT_FETCH_COLUMNS, {"rows": rows}, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    *hash<auto> fetchRow() {
        *list<string> msgs = sendSqlCommandImplicitTrans(CPC_DSP_STMT_FETCH_ROW, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    *string getSQL() {
        *list<string> msgs = sendSqlCommand(CPC_DSP_STMT_GET_SQL, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    nothing execArgs(softlist<auto> vargs) {
        sendSqlCommandImplicitTrans(CPC_DSP_STMT_EXEC, {"args": vargs}, CPC_ACK);
    }

    nothing exec() {
        sendSqlCommandImplicitTrans(CPC_DSP_STMT_EXEC, {"args": argv}, CPC_ACK);
    }

    bool active() {
        *list<string> msgs = sendSqlCommand(CPC_DSP_STMT_ACTIVE, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    bool next() {
        *list<string> msgs = sendSqlCommandImplicitTrans(CPC_DSP_STMT_NEXT, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    bool valid() {
        *list<string> msgs = sendSqlCommand(CPC_DSP_STMT_VALID, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    bool currentThreadInTransaction() {
        return dsp.currentThreadInTransaction();
    }

    hash<auto> getOutputRows() {
        *list<string> msgs = sendSqlCommandImplicitTrans(CPC_DSP_STMT_GET_OUTPUT_ROWS, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    hash<auto> getOutput() {
        *list<string> msgs = sendSqlCommandImplicitTrans(CPC_DSP_STMT_GET_OUTPUT, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    nothing bindPlaceholders() {
        sendSqlCommandImplicitTrans(CPC_DSP_STMT_BIND_PLACEHOLDERS, ("args": argv), CPC_ACK);
    }

    nothing bindPlaceholdersArgs(softlist<auto> vargs) {
        sendSqlCommandImplicitTrans(CPC_DSP_STMT_BIND_PLACEHOLDERS, ("args": vargs), CPC_ACK);
    }

    nothing bindValues() {
        sendSqlCommandImplicitTrans(CPC_DSP_STMT_BIND_VALUES, ("args": argv), CPC_ACK);
    }

    nothing bindValuesArgs(softlist<auto> vargs) {
        sendSqlCommandImplicitTrans(CPC_DSP_STMT_BIND_VALUES, ("args": vargs), CPC_ACK);
    }

    nothing bind() {
        sendSqlCommandImplicitTrans(CPC_DSP_STMT_BIND, ("args": argv), CPC_ACK);
    }

    nothing bindArgs(softlist<auto> vargs) {
        sendSqlCommandImplicitTrans(CPC_DSP_STMT_BIND, ("args": vargs), CPC_ACK);
    }

    nothing beginTransaction() {
        dsp.beginTransaction();
    }

    nothing define() {
        sendSqlCommandImplicitTrans(CPC_DSP_STMT_DEFINE, NOTHING, CPC_ACK);
    }

    hash<auto> describe() {
        *list<string> msgs = sendSqlCommandImplicitTrans(CPC_DSP_STMT_DESCRIBE, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    *hash<auto> getValue() {
        *list<string> msgs = sendSqlCommandImplicitTrans(CPC_DSP_STMT_GET_VALUE, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    int affectedRows() {
        *list<string> msgs = sendSqlCommandImplicitTrans(CPC_DSP_STMT_AFFECTED_ROWS, NOTHING, CPC_OK);
        return dsp.deserialize(msgs[0]).val;
    }

    nothing close() {
        sendSqlCommand(CPC_DSP_STMT_CLOSE, NOTHING, CPC_ACK);
    }

    private *list<string> sendSqlCommand(string cmd, *hash<auto> h, string rcmd) {
        # in case the qdsp server has been restarted, the statement SQL can be lost on the server side
        while (True) {
            try {
                return dsp.sendSqlCommand(cmd, {"process": process_id, "sid": sid} + h, rcmd);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SQLSTATEMENT-ERROR" && ex.desc =~ /no SQL/) {
                    prepare(sql);
                    continue;
                }
                rethrow;
            }
        }
    }

    private *list<string> sendSqlCommandImplicitTrans(string cmd, *hash<auto> h, string rcmd) {
        # in case the qdsp server has been restarted, the statement SQL can be lost on the server side
        while (True) {
            try {
                return dsp.sendSqlCommandImplicitTrans(cmd, ("process": process_id, "sid": sid) + h, rcmd);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SQLSTATEMENT-ERROR" && ex.desc =~ /no SQL/) {
                    prepare(sql);
                    continue;
                }
                rethrow;
            }
        }
    }
}
