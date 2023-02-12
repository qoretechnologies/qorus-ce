# -*- mode: qore; indent-tabs-mode: nil -*-
# @file DatasourceManager.qc provides the interface to handling datasources

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%push-parse-options
%new-style
%strict-args
%require-types

%requires SqlUtil


#! this class is used to keep and handle datasource connections.
/*
    https://bugs.qoretechnologies.com/projects/qorus/wiki/User_Connections
 */
class OMQ::DatasourceManager inherits OMQ::AbstractDatasourceManager, OMQ::ConnectionsServer {
    public {
        #! known datasource hash keys
        const DSKeys = {
            "type": True,
            "user": True,
            "pass": True,
            "db": True,
            "charset": True,
            "host": True,
            "port": True,
            "options": True,
        };
    }

    private {
        string omq_conn_string;

        # loggerid of the omq datasource
        *softint omq_loggerid = ENV.OMQ_LOGGERID;

        # table contention map: datasource -> type -> name -> Counter
        /** changes only while the write lock is held
        */
        hash<string, hash<string, hash<string, Counter>>> tcmap;
    }

    constructor(ConnectionDependencyManager n_cd, AbstractTable connection_table, AbstractTable connection_tags_table,
            code log_function, QdspClient ds_omq, *hash<string, bool> dsp_recovery, *RWLock rwl)
            : OMQ::ConnectionsServer(n_cd, connection_table, connection_tags_table, log_function, NOTHING, rwl) {
        # setup initial connection for OMQ - used as url for connection_map.omq
        omq_conn_string = ds_omq.getConfigString();

        # setup datasource acquisition from SqlUtil with deserialized AbstractTable objects
        SqlUtil::sqlutil_register_ds_serializer(\serializeTableDs());

        reload();

        foreach string name in (keys dsp_recovery) {
            olog(LoggerLevel::INFO, "starting qdsp process for datasource %y for recovery", name);
            try {
                getPool(name, False, False);
            } catch (hash<ExceptionInfo> ex) {
                olog(LoggerLevel::INFO, "failed to recover qdsp process for datasource %y: %s", name, get_exception_string(ex));
            }
        }
    }

    AbstractDataProvider getDataProvider(string name, *int mapperid) {
        on_success if (mapperid) doMapperDependency(name, mapperid);
        return AbstractDatasourceManager::getDataProvider(name);
    }

    enableLogging(string name) {
        *DatasourceConnection c;

        {
            ReadLockHelper rlh(rwl);

            if (!(c = connection_map{name})) {
                olog(LoggerLevel::FATAL, "Can't enable logging for unknown qdsp %y", name);
                return;
            }
        }

        c.subscribeToLog();
    }

    disableLogging(string name) {
        *DatasourceConnection c;

        {
            ReadLockHelper rlh(rwl);

            if (!(c = connection_map{name})) {
                olog(LoggerLevel::FATAL, "Can't disable logging for unknown qdsp %y", name);
                return;
            }
        }

        c.unsubscribeFromLog();
    }

    *hash<auto> getLoggerInfo(string name) {
        ReadLockHelper rlh(rwl);

        if (*DatasourceConnection c = connection_map{name}) {
            return {"loggerid": c.loggerid};
        }
    }

    # updates all loggers using the default QDSP logger
    updateLogger(*string name, *hash<auto> logger) {
        if (name.val()) {
            *DatasourceConnection c;

            {
                ReadLockHelper rlh(rwl);

                if (!(c = connection_map{name})) {
                    return;
                }
            }

            c.updateLogger(logger);
            return;
        }

        # update all loggers using the default connection
        list<DatasourceConnection> l;

        # remove the loggerid when updating with the "qdsp" default logger
        remove logger.loggerid;

        {
            ReadLockHelper rlh(rwl);

            l = map $1, connection_map.iterator(), !$1.loggerid;
        }

        map $1.updateLogger(logger), l;
    }

    #! checks the error for the given datasource, and resets the datasource in the background if needed
    checkErrorNeedsReset(string dsname, hash<auto> ex) {
        *hash<auto> current_ex = ex;
        while (current_ex) {
            if (ds_error_needs_reset(current_ex)) {
                errorResetDsBackground(dsname, current_ex);
                break;
            }
            current_ex = current_ex.next;
        }
    }

    #! resets the given datasource in the background due to the given error
    /** the error is one whjere ds_error_needs_reset() returns True
    */
    errorResetDsBackground(string dsname, hash<auto> ex) {
        string why = sprintf("datasource %y error requires a connection reset: %s: %s", dsname, ex.err, ex.desc);
        background resetDsEvent(dsname, why);
    }

    #! called when logger metadata has been updated and loggers have been updated and deleted
    processUpdatedAndDeletedLoggers(*hash<auto> updated_loggers, *list<string> deleted_loggerids,
        *hash<auto> default_qdsp_logger, bool updated_default_qdsp_logger) {
        # list of updated datasources; hashes are conn, logger
        list<hash<auto>> connection_list();

        # make a hash of deleted loggerids for quick checking; loggerid -> True
        *hash<string, bool> deleted_loggerid_map = map {$1: True}, deleted_loggerids;

        # remove the loggerid from the default connection
        default_qdsp_logger -= "loggerid";

        {
            rwl.readLock();
            on_exit rwl.readUnlock();

            foreach DatasourceConnection c in (connection_map.iterator()) {
                if (!c.loggerid) {
                    # add only if the default qdsp logger has been updated
                    if (updated_default_qdsp_logger) {
                        connection_list += {
                            "conn": c,
                            "logger": default_qdsp_logger,
                        };
                    }
                } else if (*hash<auto> logger = updated_loggers{c.loggerid}) {
                    connection_list += {
                        "conn": c,
                        "logger": logger,
                    };
                } else if (deleted_loggerid_map{c.loggerid}) {
                    # add even if there is no default qdsp logger
                    connection_list += {
                        "conn": c,
                        "logger": default_qdsp_logger,
                    };
                }
            }
        }

        QDBG_LOG("processUpdatedAndDeletedLoggers() updated_loggers: %y deleted_loggerids: %y "
            "default_qdsp_logger: %y updated_default_qdsp_logger: %y connection_list: %y", updated_loggers,
            deleted_loggerids, default_qdsp_logger, updated_default_qdsp_logger, (map $1.conn{"name", "loggerid"} +
            {"logger": $1.logger}, connection_list));

        foreach hash<auto> updated_conn in (connection_list) {
            log(LoggerLevel::INFO, "updating connection %y with %s; params: %y", updated_conn.conn.name,
                updated_conn.logger.loggerid
                    ? sprintf("loggerid %d", updated_conn.logger.loggerid)
                    : "the default qdsp logger",
                updated_conn.logger.params);
            updated_conn.conn.updateLogger(updated_conn.logger);
        }
    }

    # must be called with the write lock held
    startAcquireTable(string datasource, string type, string table) {
        QDBG_ASSERT(rwl.writeLockOwner());
        while (*Counter c = tcmap{datasource}{type}{table}) {
            rwl.writeUnlock();
            c.waitForZero();
            rwl.writeLock();
        }

        tcmap{datasource}{type}{table} = new Counter(1);
        rwl.writeUnlock();
    }

    endAcquireTable(string datasource, string type, string table) {
        QDBG_ASSERT(rwl.writeLockOwner());
        QDBG_ASSERT(tcmap{datasource}{type}{table});
        (remove tcmap{datasource}{type}{table}).dec();
        if (!tcmap{datasource}{type}) {
            remove tcmap{datasource}{type};
            if (!tcmap{datasource}) {
                remove tcmap{datasource};
            }
        }
    }

    private AutoWriteLock getWriteLockHelper() {
        AutoWriteLock awl(rwl);

        # wait until the tree is empty of Counter objects
        bool found = True;
        while (found) {
            found = False;

            foreach hash<auto> i0 in (tcmap.pairIterator()) {
                foreach hash<auto> i1 in (i0.value.pairIterator()) {
                    foreach hash<auto> i2 in (i1.value.pairIterator()) {
                        found = True;
                        delete awl;
                        i2.value.waitForZero();
                        awl = new AutoWriteLock(rwl);
                    }
                    if (found) {
                        break;
                    }
                }
                if (found) {
                    break;
                }
            }
        }

        QDBG_ASSERT(awl);
        return awl;
    }

    private resetDsEvent(string name, string why) {
        try {
            logInfo("resetting faulty Datasource connection %y", name);
            reset(name);
            # now reset all dependent connections
            resetDependentWorkflowsAndServices(name, why);
        } catch (hash<ExceptionInfo> ex) {
            logInfo("error resetting faulty Datasource connection %y: %s: %s", name, ex.err, ex.desc);
        }
    }

    hash<auto> serializeTableDs(AbstractDatasource ds) {
        QDBG_ASSERT(cast<QdspClient>(ds));
        return {
            "ds_type": "DatasourcePool",
            "ds": cast<QdspClient>(ds).getServerName(),
        };
    }

    # called from interface programs to get a serialized AbstractTable object
    binary getSerializedTable(string datasource, string type, string name, bool register_dependency, bool extern) {
        AbstractTable t = getCacheTable(datasource, type, name, register_dependency, extern);
        return t.serialize();
    }

    private AbstractTable getCreateTableIntern(string datasource, string type, string name, bool register_dependency,
            bool extern) {
        {
            ReadLockHelper rlh(rwl);

            if (*AbstractTable rv = getCacheTableIntern(datasource, type, name)) {
                #QDBG_LOG("getCreateTableIntern() (getCacheTableIntern() 1) ds: %y type: %y name: %y rd: %y ext: %y "
                #    "rv: %y", datasource, type, name, register_dependency, extern, rv.uniqueHash());
                return rv;
            }
        }

        # issue #2057: get the pool outside the lock in case we need it below
        QdspClient dsp = getPool(datasource, register_dependency, extern);

        # issue #3313: do not use stale pool objects to create objects that will be stored in the cache
        bool can_store_pool;
        if (!tld.dspNameCache{datasource} || (dsp == tld.dspNameCache{datasource})) {
            *DatasourceConnection c = cast<*DatasourceConnection>(tryGetConnection(datasource));
            if (c && c.getPool() == dsp) {
                can_store_pool = True;
%ifdef QorusDebugInternals
            } else {
                QDBG_LOG("getCreateTableIntern() not storing: ds: %y type: %y name: %y c: %y pool: %y dsp: %y",
                    datasource, type, name, c, c ? c.getPool().uniqueHash() : "n/a", dsp.uniqueHash());
%endif
            }
        } else {
            can_store_pool = True;
        }

        WriteLockTableHelper wlh(rwl, datasource, type, name);

        {
            if (*AbstractTable rv = getCacheTableIntern(datasource, type, name)) {
                #QDBG_LOG("getCreateTableIntern() (getCacheTableIntern() 2) ds: %y type: %y name: %y rd: %y ext: %y "
                #    "rv: %y", datasource, type, name, register_dependency, extern, rv.uniqueHash());
                return rv;
            }
        }

        AbstractTable obj;
        try {
            # NOTE: if dsp has changed in the cache, the call of getPool will use
            # our local (tld) datasource pool and the table will be created from it.
            Table table(dsp, name);
            obj = table.getTable();
            # issue #2978: ensure that the table is cached immediately before using
            # to avoid race conditions with table DML and datasource pool connections
            obj.cache();
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == getErrorCode())
                rethrow;
            # rethrow exception and add datasource information
            throw ex.err, sprintf("datasource %y (%s): %s", datasource, getDatasourceDescription(datasource), ex.desc);
        }

        wlh.relock();

        # issue #3313: do not use stale pool objects to create objects that will be stored in the cache
        if (can_store_pool && !exists db_cache{datasource}{type}{name} && !dspAbortMap{datasource}) {
            db_cache{datasource}{type}{name} = {
                "count": 1,
                "created": now_us(),
                "table": obj,
            };
            QDBG_LOG("getCreateTableIntern() ds: %y type: %y name: %y CACHING", datasource, type, name);
        }
%ifdef QorusDebugInternals
        else {
            QDBG_LOG("getCreateTableIntern() ds: %y type: %y name: %y not caching csp: %y cached: %y abort: %y",
                datasource, type, name, can_store_pool, exists db_cache{datasource}{type}{name},
                dspAbortMap{datasource} ? True : False);
        }
%endif
        #QDBG_LOG("getCreateTableIntern() (created) ds: %y type: %y name: %y rd: %y ext: %y rv: %y", datasource, type,
        #    name, register_dependency, extern, obj.uniqueHash());
        return obj;
    }

    *QdspClient getPoolUnlockedImpl(string datasource) {
        return cast<DatasourceConnection>(connection_map{datasource}).pool;
    }

    string getAlertType() {
        return AlertTypeDatasource;
    }

    string getAlertText() {
        return "DATASOURCE-UNAVAILABLE";
    }

    string getMonitorType() {
        return "Datasource";
    }

    string getConnectionDbType() {
        return "DATASOURCE";
    }

    string getErrorCode() {
        return "DATASOURCE-ERROR";
    }

    *hash<string, hash<auto>> reload(*hash<auto> cx) {
        *hash<string, hash<auto>> updated = ConnectionsServer::reload(cx);
        Qorus.getMaster().broadcastToAllInterfaces("dsmanager", "reload");
        map connectionReplaced($1.key, $1.value.old_conn, $1.value.new_conn), updated.pairIterator();
    }

    private *hash<string, hash<auto>> reloadIntern() {
        invalidateObjectIntern();
        *hash<string, hash<auto>> rv = ConnectionsServer::reloadIntern();
        if (rv.omq) {
            remove rv.omq;
        }
        return rv;
    }

    private hash<auto> reloadConnection(AbstractSQLStatement stmt, hash<auto> row, *hash<auto> tags) {
        if (stmt.name != "omq" || !omq_conn_string) {
            return ConnectionsServer::reloadConnection(stmt, row);
        }

        hash<auto> attributes = {
            "locked": True,
            "monitor": boolean(row.monitor),
            "enabled": boolean(row.enabled),
            "tags": tags.omq,
        };

        DatasourceConnection c("omq", "Qorus system database", "db://" + omq_conn_string, attributes,
            {"loggerid": omq_loggerid});
        c.internal_info.id = 0;
        c.pool = omqp;

        id_map{"0"} = connection_map."omq" = c;
        return {
            "old_conn": connection_map.omq,
            "new_conn": c,
        };
    }

    private datasourcePoolProcessAbortedImpl(string name, bool restarted, date abort_timestamp) {
        {
            ReadLockHelper rlh(rwl);

            if (*DatasourceConnection c = connection_map{name}) {
                c.processAborted(restarted);
            }
        }
        if (!restarted) {
            ping(name);
        }
    }

    DatasourceConnection getConnection(string name) {
        ReadLockHelper rlh(rwl);

        AbstractConnection c = getConnectionIntern(name);
        if (c instanceof InvalidConnection) {
            throw getErrorCode(), sprintf("cannot retrieve invalid connection %y", name);
        }
        return c;
    }

    DatasourceConnection getConnection(string name, bool check_locked) {
        DatasourceConnection c = self.getConnection(name);
        if (check_locked && c.locked)
            throw getErrorCode(), sprintf("cannot acquire a connection for %y: this is a private/system datasource",
                name);
        return c;
    }

    Datasource getShared(string name, bool register_dependency = True) {
        DatasourceConnection c;
        *bool oldok;
        *hash<auto> src = qorus_get_source_hash();

        Datasource ds;
        try {
            c = self.getConnection(name, True);
            oldok = c.last_check ? c.up : NOTHING;
            ds = c.getShared();
        } catch (hash<ExceptionInfo> ex) {
            # add dependency and then rethrow
            if (c) {
                string err = sprintf("%s connection monitor: shared connection could not be acquired to %y (%s) "
                    "url: %y", getMonitorType(), c.name, c.desc, c.safe_url);
                connection_dependency_manager.manageDependency(self, c, src, register_dependency, False, oldok, err,
                    ex);
            } else {
                string err = sprintf("%s connection monitor: shared connection could not be acquired to unknown "
                    "datasource %y", getMonitorType(), name);
                connection_dependency_manager.manageDependency(self, name, src, register_dependency, err, ex);
            }
            rethrow;
        }
        connection_dependency_manager.manageDependency(self, c, src, register_dependency, True, oldok);

        return ds;
    }

    hash<auto> getConfigHash(string name) {
        # issue #3239: do not grab the lock again if it's already held
        ReadLockHelper rlh(rwl);

        # issue #2057: we do not need to create a datasource pool object to get the description
        # (which might fail anyway), instead the description is available in the "urlh" member
        # of the DatasourceConnection
        if (!connection_map.hasKey(name)) {
            throw "DATASOURCE-NOT-KNOWN";
        }
        return connection_map{name}.urlh;
    }

    hash<auto> getExternalConnectionInfo(string name, bool register_dependency, *hash<auto> src) {
        DatasourceConnection c;

        try {
            c = getConnection(name); # TODO/FIXME refs 2353 - enabled/disabled check is done here. Should it be here?
        } catch (hash<ExceptionInfo> ex) {
            string err = sprintf("%s connection monitor: datasource pool could not be acquired to unknown datasource %y", getMonitorType(), name);
            connection_dependency_manager.manageDependency(self, name, src, register_dependency, err, ex);
            rethrow;
        }

        if (c.locked) {
            throw getErrorCode(), sprintf("cannot acquire a connection for %y: this is a private/system datasource", name);
        }
        *bool oldok = c.last_check ? c.up : NOTHING;

        # get a pool in any case (even if a dedicated connection will be acquired) to test if the DB connection works
        QdspClient dsp;
        try {
            dsp = c.getPool();
        } catch (hash<ExceptionInfo> ex) {
            string err = sprintf("%s connection monitor: datasource pool for external process could not be acquired to %y (%s) url: %y", getMonitorType(), c.name, c.desc, c.safe_url);
            connection_dependency_manager.manageDependency(self, c, src, register_dependency, False, oldok, err, ex);
            # convert "PROCESS-START-ERROR" to "DATASOURCE-ERROR"
            if (ex.err == "PROCESS-START-ERROR")
                throw getErrorCode(), sprintf("datasource pool cluster process %y for datasource %y could not be started: %s: %s", qdsp_get_process_name(name), name, ex.err, ex.desc), ex.arg;
            rethrow;
        }

        # process dependency
        connection_dependency_manager.manageDependency(self, c, src, register_dependency, True, oldok);

        # return configuration info
        return c.getConfigInfo();
    }

    private QdspClient getPoolImpl(string name, bool register_dependency = True, bool extern = True) {
        DatasourceConnection c;
        *bool oldok;
        *hash<auto> src = qorus_get_source_hash();

        QdspClient dsp;
        try {
            c = getConnection(name, extern);
            oldok = c.last_check ? c.up : NOTHING;
            dsp = c.getPool();
            #QDBG_LOG("DatasourceManager::getPoolImpl(%s) obj: %y", name, dsp.getConfigHash());
        } catch (hash<ExceptionInfo> ex) {
            # add dependency and then rethrow
            if (c) {
                string err = sprintf("%s connection monitor: datasource pool could not be acquired to %y (%s) url: %y", getMonitorType(), c.name, c.desc, c.safe_url);
                connection_dependency_manager.manageDependency(self, c, src, register_dependency, False, oldok, err, ex);
            } else {
                string err = sprintf("%s connection monitor: datasource pool could not be acquired to unknown datasource %y", getMonitorType(), name);
                connection_dependency_manager.manageDependency(self, name, src, register_dependency, err, ex);
            }
            rethrow;
        }

        connection_dependency_manager.manageDependency(self, c, src, register_dependency, True, oldok);
        return dsp;
    }

    Datasource getDedicated(string name, bool register_dependency = True) {
        DatasourceConnection c;
        *bool oldok;
        *hash<auto> src = qorus_get_source_hash();

        Datasource ds;
        try {
            c = getConnection(name, True);
            oldok = c.last_check ? c.up : NOTHING;
            ds = c.getDedicated();
        } catch (hash<ExceptionInfo> ex) {
            # add dependency and then rethrow
            if (c) {
                string err = sprintf("%s connection monitor: dedicated connection could not be acquired to %y (%s) url: %y", getMonitorType(), c.name, c.desc, c.safe_url);
                connection_dependency_manager.manageDependency(self, c, src, register_dependency, False, oldok, err, ex);
            } else {
                string err = sprintf("%s connection monitor: dedicated connection could not be acquired to unknown datasource %y", getMonitorType(), name);
                connection_dependency_manager.manageDependency(self, name, src, register_dependency, err, ex);
            }
            rethrow;
        }
        connection_dependency_manager.manageDependency(self, c, src, register_dependency, True, oldok);

        return ds;
    }

    private string getConnectionStringFromHash(hash connection_hash) {
        # remove unknown keys
        foreach string key in (keys connection_hash) {
            if (!DSKeys{key}) {
                logInfo("ignoring unknown datasource key %y in %y", key, connection_hash);
                delete connection_hash{key};
            }
        }
        string connstr = "db://" + get_ds_desc(connection_hash);
        return connstr;
    }

    # another variant for ConnectionsServer::registerConnection() used for datasource_hash arguments
    AbstractConnection registerConnection(string name, hash<auto> connection_hash) {
        string url = getConnectionStringFromHash(connection_hash);
        string desc = sprintf("%s:%s@%s",
                         connection_hash.type, connection_hash.user, connection_hash.db);
        return ConnectionsServer::registerConnection(name, desc, url, {}, {});
    }

    # another variant for ConnectionsServer::replace() used for datasource_hash arguments
    DatasourceConnection replace(string name, hash<auto> connection_hash) {
        string url = getConnectionStringFromHash(connection_hash);

        AbstractConnection old_conn;
        {
            ReadLockHelper rlh(rwl);

            old_conn = checkReplaceIntern(name);
        }

        bool was_monitored = old_conn.monitor ?? True;
        bool did_support_polling = old_conn.supportsPollingApi();
        bool do_reset;

        AbstractConnection new_connection = replace(name, old_conn.desc, url, {}, old_conn.opts, \do_reset);
        doReplaceIntern(new_connection, was_monitored, did_support_polling, do_reset);
        return new_connection;
    }

    connectionReplaced(string name, *AbstractConnection old_conn, *AbstractConnection new_conn) {
        if (old_conn && new_conn) {
            string old_url = old_conn.url;
            # move pool config to new object
            new_conn += cast<DatasourceConnection>(old_conn).takeResetConfig();
            delete old_conn;

            # do reset with new connection
            if (new_conn.url != old_url) {
                resetConnection(new_conn, name);
                Qorus.getMaster().broadcastToAllInterfaces("dsmanager", "reset", name);
            }
            return;
        }
        Qorus.getMaster().broadcastToAllInterfaces("dsmanager", "reset", name);
    }

    private resetConnection(DatasourceConnection c, string name) {
        c.reset();

        {
            WriteLockHelper wlh(rwl);

            invalidateObjectIntern(name);
        }

        resetMappers(name);
    }

    private hash<auto> getSelectHash() {
        # must be "hash"
        hash sh = {
            "where": {
                "connection_type": getConnectionDbType(),
            },
        };
        if (connection_map.omq) {
            sh."where".name =  op_ne("omq");
        }
        return sh;
    }

    # overrides ConnectionsServer::getInfo() because of 'rtime'
    # Do not call anything from Connections because of locking!
    hash<auto> getInfo(string name, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        ReadLockHelper rlh(rwl);

        *AbstractConnection c = connection_map{name};
        if (!c) {
            throw "DATASOURCE-ERROR", sprintf("datasource %y is unknown; known datasources: %y", name,
                keys connection_map);
        }
        return getInfoIntern(c, opts);
    }

    *hash<auto> tryGetInfo(string name, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        ReadLockHelper rlh(rwl);

        *AbstractConnection c = connection_map{name};
        if (c) {
            return getInfoIntern(c, opts);
        }
    }

    *hash<auto> tryGetInfoFromId(int id, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        ReadLockHelper rlh(rwl);

        *AbstractConnection c = id_map{id};
        if (c) {
            return getInfoIntern(c, opts);
        }
        QDBG_LOG("DatasourceManager::tryGetInfoFromId() id: %y not found: %y", id, map $1.toInt(), keys id_map);
    }

    # overrides ServersConnections::getInfo() because of 'rtime'
    # Do not call anything from Connections because of locking!
    hash<auto> getInfo(*hash<auto> opts) {
        ReadLockHelper rlh(rwl);

        # we always have the "omq" datasource
        return map {$1.name: getInfoIntern($1, opts)}, connection_map.iterator();
    }

    hash<string, int> getDbSizeB(bool with_passwords) {
        ReadLockHelper rlh(rwl);

        # we always have the "omq" datasource; only check active connections with a created pool
        hash<string, int> rv = {};
        foreach AbstractConnection conn in (connection_map.iterator()) {
            DatasourceConnection dsc = cast<DatasourceConnection>(conn);
            if (!dsc.pool) {
                continue;
            }
            try {
                rv{dsc.name} = new SqlUtil::Database(dsc.pool).getPhysicalSize();
            } catch (hash<ExceptionInfo> ex) {
                QDBG_LOG("error getting database size for db connection %y: %s: %s", dsc.name, ex.err,
                    ex.desc ?? "<no exception description>");
            }
        }
        return rv;
    }

    # this one overrides ConnectionsServer::list() completely.
    # reason: rtime and different meaning of with_passwords vs monitred_only
    # No need for locking here - rwl is used in self.getInfo()
    list<hash<auto>> list(*hash<auto> opts) {
        return self.getInfo(opts).values();
    }

    # rest API call
    reset(string name) {
        {
            # invalidate all cached SQL objects for this datasource
            resetConnection(getConnection(name, True), name);
        }

        Qorus.getMaster().broadcastToAllInterfaces("dsmanager", "reset", name);
        ping(name);
    }

    string getDescription(string name) {
        DatasourceConnection c = getConnection(name);
        return c.desc;
    }

    # returns a string description of the datasource without the connection password
    string getDatasourceDescriptionImpl(string datasource) {
        hash h;
        try {
            # this could throw an exception in case the datasource is no longer defined
            h = getConfigHash(datasource);
        } catch (hash<ExceptionInfo> ex) {
            return sprintf("<unknown datasource %y>", datasource);
        }
        string str = sprintf("%s:%s@%s", h.type, h.user, h.db);
        if (h.host)
            str += "%" + h.host;
        if (h.port)
            str += ":" + h.port;
        return str;
    }

    hash<auto> getCacheInfo() {
        ReadLockHelper rlh(rwl);
        return getCacheInfoImpl(False);
    }

    hash<auto> getCacheInfoSystem() {
        ReadLockHelper rlh(rwl);
        return getCacheInfoImpl(True);
    }

    list<string> getDatasourceList() {
        ReadLockHelper rlh(rwl);
        return keys connection_map;
    }

    private clearTableCacheIntern(*string datasource, *string name) {
        WriteLockHelper wlh(rwl);

        invalidateObjectIntern(datasource, "tables", name);
    }

    private hash<auto> getCacheInfoImpl(bool show_system) {
        hash<auto> rv = {};

        foreach string dsn in (keys db_cache) {
            if (!show_system && dsn == "omq") {
                continue;
            }

            foreach string type in (keys db_cache{dsn}) {
                map rv{dsn}{type}{$1} = db_cache{dsn}{type}{$1}{"count", "created"}, keys db_cache{dsn}{type};
            }
        }

        return rv;
    }
}

class WriteLockGateHelper {
    constructor(RWLock rwl, *string datasource, *string type, *string table) {
    }
}

class WriteLockTableHelper {
    private {
        RWLock rwl;
        string datasource;
        string type;
        string table;
        bool unlock;
    }

    constructor(RWLock rwl, string datasource, string type, string table) {
        if (!rwl.writeLockOwner()) {
            rwl.writeLock();
            unlock = True;
        }
        self.rwl = rwl;
        Qorus.dsmanager.startAcquireTable(datasource, type, table);
        self.datasource = datasource;
        self.type = type;
        self.table = table;
    }

    destructor() {
        if (!rwl.writeLockOwner()) {
            rwl.writeLock();
        }
        Qorus.dsmanager.endAcquireTable(datasource, type, table);
        if (unlock) {
            rwl.writeUnlock();
        }
    }

    relock() {
        QDBG_ASSERT(!rwl.writeLockOwner());
        rwl.writeLock();
    }
}
