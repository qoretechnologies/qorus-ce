# -*- mode: qore; indent-tabs-mode: nil -*-
# @file ConnectionsServer.qc provides an API for user connections in Qorus server

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

#! The base connection handling in the Qorus server (qorus-core).
/*  In general it follows OMQ::Connections but it adds locking and additional
    functionality required in the running Qorus server

    https://bugs.qoretechnologies.com/projects/qorus/wiki/User_Connections
*/
class OMQ::ConnectionsServer inherits OMQ::Connections {
    public {
        const POLL_INTERVAL = 60s;
    }

    private {
        # wait mutex & condition
        Mutex m();
        Condition cond();

        # flags
        bool shutdown_flag;
        bool stop_flag;

        # stop condition
        Condition stop_cond();
        # stop waiting
        int stop_waiting;

        # thread counter
        Counter conn_cnt();

        ConnectionDependencyManager connection_dependency_manager;

        # connection mapper map; connection name -> mapperid -> True
        hash<string, hash<string, bool>> cmmap;

        # failure count map; connection -> count
        hash<string, int> conn_fail_count_map;
        # failure count map mutex
        Mutex fmutex();

        # map of connections with dedicated polling threads
        hash<string, bool> dedicated;

        static Logger logger;

        # issue #3732: connections require at least 2 failures before they are marked as down
        const ConnectionPingFailureLimit = 2;
    }

    constructor(ConnectionDependencyManager v_cd, AbstractTable conn, AbstractTable conn_tags, code log_function,
            *list<auto> connection_modules, *RWLock rwl)
            : Connections(conn, conn_tags, log_function, connection_modules, rwl) {
        connection_dependency_manager = v_cd;
    }

    private resetMappers() {
        # reset affected mappers
        foreach string name in (argv) {
            foreach softint mapperid in (keys cmmap{name}) {
                try {
                    hash<auto> mh = Qorus.qmm.lookupMapper(mapperid);
                    Qorus.mappers.reloadMapper(mh);
                    Qorus.logInfo("reset mapper %s v%s (%d) from %y %s reset", mh.name, mh.version, mapperid, name,
                        getAlertType());
                } catch (hash<ExceptionInfo> ex) {
                    # ignore exception
                    QDBG_LOG("ignoring exception resetting mapper from connection %y: %s", name, get_exception_string(ex));
                }
            }
        }
    }

    doMapperDependency(string name, int mapperid) {
        cmmap{name}{mapperid} = True;
    }

    clearAllMapperDependencies() {
        remove cmmap;
    }

    clearMapperDependencies(softstring mapperid) {
        map remove cmmap{$1}{mapperid}, keys cmmap;
    }

    AbstractConnection registerConnection(string name, string desc, string url, hash<auto> attributes = {},
            hash<auto> options = {}, *softint id, *string tab_token) {
        attributes."monitor" = True;
        AbstractConnection c = newConnection(name, desc, url, attributes, options ?? {});

        {
            # get an object that will hold the write lock and release it when the variable goes out of scope
            AutoWriteLock wlh = getWriteLockHelper();
            awaitChange();

            if (connection_map{name}) {
                throw getErrorCode(), sprintf("connection %y is already registered", name);
            }

            # check for reservation
            if (*string reservation = Qorus.qmm.checkReservationLocked("connection", name)) {
                if (reservation && reservation != tab_token) {
                    throw "CONNECTION-CREATION-ERROR", sprintf("connection %y is already reserved", name);
                }
            }

            insertConnection(c, id);
            QDBG_ASSERT(c.internal_info.id);
            if (!id) {
                id = c.internal_info.id;
            }
            id_map{id} = connection_map{name} = c;
        }

        hash<auto> conn_info = c{"name", "url", "desc",} + {
            "opts": c.orig_opts,
            "connectionid": id,
            "conntype": getAlertType(),
        };
        Qorus.audit.connectionCreated(tld.cx, id, sprintf("%y", conn_info));
        Qorus.events.postConnectionCreated(conn_info);
        Qorus.creatorWsHandler.broadcastInterfaceCreated("connection", id, name, conn_info);

        if (c.monitor) {
            # use efficient polling with multiplexed I/O
            if (c.supportsPollingApi()) {
                Qorus.pmonitor.add(c, {"obj": self});
            } else {
                startDedicated(name);
            }
        }

        return c;
    }

    del(string name) {
        AbstractConnection c = Connections::del(name);

        hash<auto> conn_info = c{"name", "url"};
        int id = c.internal_info.id;
        Qorus.audit.connectionDeleted(tld.cx, id, sprintf("%y", {"id": id} + conn_info));
        Qorus.events.postConnectionDeleted(getAlertType(), name);
        Qorus.creatorWsHandler.broadcastInterfaceDeleted("connection", id, name, conn_info);
    }

    AbstractConnection replaceLocked(AbstractConnection old_conn, hash<auto> conn_info, hash<auto> old_delta_info,
            hash<auto> new_delta_info, AtomicConnectionHelper ach) {
        QDBG_ASSERT(!old_conn.locked);

        hash<auto> attr;
        if (conn_info.tags) {
            attr.tags = conn_info.tags;
        }
        AbstractConnection c = newConnection(conn_info.name, conn_info.desc, conn_info.url, attr, conn_info.opts);
        QDBG_LOG("DEBUG: %y == name: %y (%s) url: %y (tags: %y opts: %y)", conn_info, c.name, c.desc, c.url, c.getTags(), c.opts);

        int id = c.internal_info.id = old_conn.internal_info.id;

        if (conn_info.name != old_conn.name) {
            remove connection_map{old_conn.name};
        }

        replaceIntern(conn_info.name, c, old_conn);
        updateConnectionIntern(id, c, old_delta_info, new_delta_info);

        if (old_conn.url != c.url || old_conn.opts != c.opts) {
            ach.addPostAction(sub () {
                if (old_conn.name == c.name) {
                    resetMappers(c.name);
                } else {
                    resetMappers(old_conn.name, c.name);
                }
            });
        }

        return c;
    }

    # called only when moving a connection from one monitor type to another (ex: datasource -> user connection)
    addUpdateConnection(AbstractConnection c, hash<auto> old_delta_info, hash<auto> new_delta_info,
            AtomicConnectionHelper ach) {
        QDBG_ASSERT(Qorus.connection_rwl.lockOwner());
        QDBG_ASSERT(c.internal_info.id);
        int id = c.internal_info.id;
        QDBG_ASSERT(!id_map{id});
        QDBG_ASSERT(!connection_map{c.name});

        updateConnectionIntern(id, c, old_delta_info, new_delta_info);

        QDBG_ASSERT(!connection_map{c.name});
        id_map{id} = connection_map{c.name} = c;

        if (c.monitor) {
            ach.addPostAction(sub () {
                if (c.supportsPollingApi()) {
                    Qorus.pmonitor.addOrUpdate(c, {"obj": self});
                } else {
                    startDedicated(c.name);
                }
            });
        }

        log(c.name, "updated connection (%s) registered with url: %y opts: %y", c.desc, c.url, c.getRealOptions());
    }

    private updateConnectionIntern(int id, AbstractConnection c, hash<auto> old_delta_info,
            hash<auto> new_delta_info) {
        hash<auto> where_hash = {
            "connectionid": id,
        };

        QorusRestartableTransaction trans(connection_table.getDriverName());
        while (True) {
            try {
                on_success connection_table.commit();
                on_error connection_table.rollback();

                hash<auto> db_info = new_delta_info;
                if (remove db_info.tags) {
                    connection_tags_table.del(where_hash);
                    insertTagsIntern(c, where_hash);
                }
                if (db_info) {
                    connection_table.update(db_info, where_hash);
                }
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            break;
        }

        if (new_delta_info) {
            QDBG_ASSERT(old_delta_info);
            sendUpdateMessages(c, old_delta_info, new_delta_info);
        }
    }

    AbstractConnection replace(string name, string desc, string url, hash<auto> attributes = {},
            hash<auto> options = {}) {
        bool was_monitored = connection_map{name}.monitor ?? True;
        bool did_support_polling = connection_map{name}.supportsPollingApi();
        bool do_reset;
        AbstractConnection new_connection = replace(name, desc, url, attributes, options, \do_reset);
        doReplaceIntern(new_connection, was_monitored, did_support_polling, do_reset);
        return new_connection;
    }

    private doReplaceIntern(AbstractConnection c, bool was_monitored, bool did_support_polling,
            *bool do_reset) {
        string name = c.name;
        if (!was_monitored) {
            if (connection_map{name}.monitor) {
                if (c.supportsPollingApi()) {
                    # use efficient polling with multiplexed I/O
                    Qorus.pmonitor.addOrUpdate(c, {"obj": self});
                } else {
                    # add dedicated polling thread
                    startDedicated(name);
                }
            }
        } else {
            if (connection_map{name}.monitor) {
                # use efficient polling with multiplexed I/O
                if (c.supportsPollingApi()) {
                    # update the definition in the multiplexed I/O poller
                    Qorus.pmonitor.addOrUpdate(c, {"obj": self});
                } else {
                    if (did_support_polling) {
                        # remove from multiplexed I/O poller
                        Qorus.pmonitor.removeConnection(name);

                        # add dedicated polling thread
                        startDedicated(name);
                    }
                    # nothing to do if using a dedicated polling thread before and after
                }
            }
        }

        if (do_reset) {
            resetMappers(name);
        }
    }

    private startDedicated(string name) {
        AutoLock al(m);

%ifdef QorusDebugInternals
        if (dedicated{name}) {
            printf("ERROR %y: %y\n", name, dedicated);
        }
        QDBG_LOG("starting dedicated monitoring thread for connection %y", name);
%endif

        dedicated{name} = True;

        conn_cnt.inc();
        on_error {
            conn_cnt.dec();
            remove dedicated{name};
        }
%ifdef QorusDebugInternals
        int dtid = background monitor(name);
        QDBG_LOG("ConnectionsServer::startMonitoringIntern() %y: started dedicated I/O thread %d", name, dtid);
%else
        background monitor(name);
%endif
    }

    AbstractConnection replace(string name, string desc, string url, hash<auto> attributes = {},
            hash<auto> options = {}, reference<bool> do_reset) {
        AbstractConnection c = newConnection(name, desc, url, attributes, options, True);
        QDBG_LOG("DEBUG: name: %y (%s) url: %y attr: %y (tags: %y)", name, desc, url, attributes, c.getTags());

        hash<auto> old_updated_info;
        hash<auto> new_updated_info;
        # do not delete the old connection in the write lock; it can cause a deadlock updating qdsp process info
        # declaring it here allows it to go out of scope outside the lock
        AbstractConnection old_conn;
        {
            # get an object that will hold the write lock and release it when the variable goes out of scope
            AutoWriteLock wlh = getWriteLockHelper();
            awaitChange();

            old_conn = checkReplaceIntern(name);
            QDBG_LOG("DEBUG: old conn name: %y (%s) url: %y (tags: %y)", name, old_conn.desc, old_conn.url, old_conn.tags);
            c.internal_info.id = old_conn.internal_info.id;
            replaceIntern(name, c, old_conn);

            if (old_conn.url != url || old_conn.opts != options) {
                do_reset = True;
            }

            if (old_conn.name != name) {
                old_updated_info.name = old_conn.name;
                new_updated_info.name = name;
            }
            if (old_conn.desc != desc) {
                old_updated_info.description = old_conn.desc;
                new_updated_info.description = desc;
            }
            if (old_conn.url != url) {
                old_updated_info.url = old_conn.url;
                new_updated_info.url = url;
            }
            if (old_conn.tags != attributes.tags) {
                old_updated_info.tags = old_conn.tags;
                new_updated_info.tags = attributes.tags;
            }
            if (old_conn.opts != options) {
                old_updated_info.options = old_conn.opts;
                new_updated_info.options = options;
            }
        }

        if (new_updated_info) {
            QDBG_ASSERT(old_updated_info);
            sendUpdateMessages(c, old_updated_info, new_updated_info);
        }

        connectionReplaced(name, old_conn, c);

        return c;
    }

    private connectionReplaced(string name, *AbstractConnection old_conn, *AbstractConnection new_conn) {
        # this method left empty intentionally
    }

    private sendUpdateMessages(AbstractConnection c, hash<auto> old_updated_info, hash<auto> new_updated_info) {
        int id = c.internal_info.id;
        Qorus.audit.connectionUpdated(tld.cx, id, sprintf("%y", new_updated_info));
        Qorus.events.postConnectionUpdated(id, getAlertType(), c.name, new_updated_info);
        string name;
        list<hash<FieldGroupInfo>> fields = CreatorConnectionDefinitionRestClass::staticGetFieldsForConnection(id, \name);
        Qorus.creatorWsHandler.broadcastInterfaceUpdated("connection", id, name, fields, NOTHING,
            old_updated_info, new_updated_info);
    }

    # alert type. One of Alert* constants: OMQ::AlertTypeRemote, OMQ::AlertTypeUser, OMQ::AlertTypeDatasource
    abstract string getAlertType();

    # text for alert/exceptions
    abstract string getAlertText();

    # description text for connection_dependency_manager
    abstract string getMonitorType();

    static initLogger() {
        ConnectionsServer::logger = createLogger(Qorus.loggerController.getLoggerParamsSubs("MONITORING"));
    }

    static updateLogger(*hash<LoggerParams> params) {
        params = substituteLogFilename(params, LoggerController::getLoggerSubs("MONITORING"));
        ConnectionsServer::logger = createLogger(params);
        OMQ::ConnectionsServer::logArgs(Logger::LoggerLevel::DEBUG, "MONITORING logger has been updated with "
            "params: %y", params);
    }

    bool ignoreSocketWarnings(string name) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        if (!connection_map{name}) {
            return True;
        }
        return connection_map{name}.opts.ignore_socket_warnings ?? False;
    }

    # overrides Connections::getInfo() because of deps manager.
    # Do not call anything from Connections because of locking!
    *hash<auto> getInfo(*hash<auto> opts) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return map {
            $1.key: getInfoIntern($1.value, opts)
        }, connection_map.pairIterator();
    }

    # overrides Connections::getInfo() because of deps manager.
    # Do not call anything from Connections because of locking!
    *hash<auto> getInfo(string name, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        rwl.readLock();
        on_exit rwl.readUnlock();

        *AbstractConnection c = connection_map{name};
        if (c) {
            return getInfoIntern(c, opts);
        }
    }

    *hash<auto> getInfoFromId(int id, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        rwl.readLock();
        on_exit rwl.readUnlock();

        *AbstractConnection c = id_map{id};
        if (c) {
            return getInfoIntern(c, opts);
        }
    }

    # called with the lock held
    private hash<auto> getInfoWithEditInfoIntern(AbstractConnection c, *hash<auto> opts,
            *hash<EditMapInfo> edit_info) {
        hash<auto> rv = connection_dependency_manager.getDependencies({
            "conntype": getAlertType(),
        } + c.getExtendedInfo(opts), getAlertType()) + {
            "connectionid": c.internal_info.id,
            "alerts": Qorus.alerts.getAlerts(getAlertType(), c.name),
        };
        if (edit_info) {
            rv.edit_lock = edit_info.cid;
        }
        return rv;
    }

    # called with the lock held
    private hash<auto> getInfoIntern(AbstractConnection c, *hash<auto> opts) {
        QDBG_ASSERT(rwl.lockOwner());

        return getInfoWithEditInfoIntern(c, opts, Qorus.qmm.getEditInfoLocked("connection", c.internal_info.id));
    }

    # takes the old log level
    log(int ll, string fmt) {
        ConnectionsServer::logger.log(convert_old_log_level(ll), "%s", sprintf(getConnectionDbType().lwr() + ": " +
            fmt, argv));
    }

    logSystem(string name, string fmt) {
        fmt = sprintf("%s %y: ", getConnectionDbType().lwr(), name) + fmt;
        Qorus.logArgs(Logger::LoggerLevel::INFO, fmt, argv);
    }

    log(string name, string fmt) {
        fmt = sprintf("%s %y: ", getConnectionDbType().lwr(), name) + fmt;
        OMQ::ConnectionsServer::logArgs(Logger::LoggerLevel::INFO, fmt, argv);
    }

    # takes a new log level
    static logArgs(int lvl, string msg, auto args) {
        string fmsg = vsprintf(msg, args);
        ConnectionsServer::logger.log(lvl, "%s", fmsg, new LoggerEventParameter(\Qorus.eventLog.logEvent(), "mon",
            sprintf("%s T%d [%s]: ", log_now(), gettid(), LoggerLevel::getLevel(lvl).getStr()) + fmsg + "\n"));
    }

    logDebug(string msg) {
        OMQ::ConnectionsServer::logArgs(Logger::LoggerLevel::DEBUG, msg, argv);
    }

    logInfo(string msg) {
        OMQ::ConnectionsServer::logArgs(Logger::LoggerLevel::INFO, msg, argv);
    }

    static rotateLogFiles() {
        foreach auto appender in (ConnectionsServer::logger.getAppenders()) {
            if (appender instanceof AbstractLoggerAppenderFileRotate) {
                cast<AbstractLoggerAppenderFileRotate>(appender).rotate();
            }
        }
    }

    hash<auto> dbgInfo() {
        return connection_dependency_manager.dbgInfo();
    }

    list<hash<auto>> getListLocked(*hash<string, *hash<EditMapInfo>> edit_map, *hash<auto> opts) {
        QDBG_ASSERT(rwl.lockOwner());

        # rename "desc" to "description"
        return map $1 - "desc" + {
            "description": $1.desc,
        }, (map getInfoWithEditInfoIntern($1, opts, edit_map{$1.internal_info.id}),
            connection_map.iterator());
    }

    # this one overrides Connections::list() completely. reason: alerts.
    # No need for locking here - rwl is used in self.getInfo()
    list<auto> list(bool monitored_only = False, bool remote_only = False) {
        list ret = ();
        HashIterator it(self.getInfo({"with_passwords": monitored_only}));
        while (it.next()) {
            auto c = it.getValue();
            if (monitored_only && !c.monitor)
                continue;
            if (remote_only && c.loopback)
                continue;
            push ret, c;
        }
        return ret;
    }

    shutdown() {
        # get an object that will hold the write lock and release it when the variable goes out of scope
        AutoWriteLock wlh = getWriteLockHelper();
        awaitChange();

        shutdown_flag = True;
        stopIntern();

        logInfo("stopping monitoring: %y", connection_map.keys());
    }

    bool isConnectionUp(string name) {
        return boolean(connection_map{name}.up);
    }

    resetStatus(string type, list idl) {
        connection_dependency_manager.resetStatus(type, idl);
    }

    resetStatus(string type, softstring id) {
        connection_dependency_manager.resetStatus(type, id);
    }

    AbstractConnection removeConnection(int id, AtomicConnectionHelper ach) {
        AbstractConnection c = Connections::removeConnection(id, ach);
        if (cmmap{c.name}) {
            ach.addPostAction(sub () { resetMappers(c.name); } );
        }
    }

    # this one overrides Connections::ping completely
    hash<PingInfo> ping(string name) {
        *AbstractConnection c;

        # previous status
        bool up;

        {
            rwl.readLock();
            on_exit rwl.readUnlock();

            c = connection_map{name};
            if (!c)
                throw getErrorCode(), sprintf("connection %y does not exist; known connections: %y", name,
                    keys connection_map);

            up = c.up;
        }

        *bool oldok = c.last_check ? c.up : NOTHING;

        date now = now_us();
        hash<PingInfo> ping_info = c.ping();
        date delta = now_us() - now;

        if (!ping_info.ok) {
            handleFailedPing(c, delta, ping_info.ex, tld.cx);
        } else {
            handleSuccessfulPing(c, delta, ping_info, oldok);
        }

        return ping_info;
    }

    # returns True if we waited for a stop/reload
    private bool awaitChange(*bool no_shutdown_error) {
        QDBG_ASSERT(rwl.writeLockOwner());

        if (shutdown_flag && !no_shutdown_error) {
            throw "SHUTDOWN-ERROR", "no connection changes can be made while the system is shutting down";
        }

        bool rv = False;

        # wait for stop flag to be cleared
        while (stop_flag) {
            ++stop_waiting;
            stop_cond.wait(rwl);
            --stop_waiting;
            if (!rv) {
                rv = True;
            }
        }

        return rv;
    }

    private stopIntern() {
        QDBG_ASSERT(shutdown_flag || stop_flag);

        # stop polling connections associated with this object
        map Qorus.pmonitor.removeConnection($1), keys connection_map;

        # signal dedicated polling threads to stop
        {
            rwl.writeUnlock();
            on_exit rwl.writeLock();

            {
                m.lock();
                on_exit m.unlock();
                cond.broadcast();
            }

            # wait for dedicated polling threads to stop
            conn_cnt.waitForZero();
        }

        QDBG_ASSERT(!dedicated);
    }

    waitStop() {
        conn_cnt.waitForZero();
    }

    # no rwl handling here! It's done in Connections
    AbstractConnection getConnection(string name, *reference<auto> rtopts) {
        AbstractConnection c = Connections::getConnection(name);

        # add runtime logging closure options if supported by the class and not given in the call
        *hash<auto> rh = c.getRuntimeOptions();
        if (rh.log && !rtopts.log)
            rtopts.log = sub (string fmt) { logInfo(fmt, argv); };
        if (rh.errlog && !rtopts.errlog)
            rtopts.errlog = sub (string fmt) { logInfo(fmt, argv); };
        if (rh.dbglog && !rtopts.dbglog)
            rtopts.dbglog = sub (string fmt) { logDebug(fmt, argv); };

        return c;
    }

    #! returns a connection and processes the dependency
    AbstractConnection getConnectionRemote(string name, bool register_dependency) {
        AbstractConnection c;
        try {
            c = Connections::getConnection(name);
        } catch (hash<ExceptionInfo> ex) {
            if (register_dependency) {
                string err = sprintf("%s connection monitor: connection could not be acquired to unknown connection %y", getMonitorType(), name);
                connection_dependency_manager.registerDependency(self, name, err, ex);
            }
            QDBG_LOG("invalid remote connection %y %y: %s: %s", getMonitorType(), name, ex.err, ex.desc);
            rethrow;
        }
        if (register_dependency) {
            connection_dependency_manager.registerDependency(self, c);
        }
        QDBG_LOG("got remote connection %y %y: %s", getMonitorType(), name, c.className());
        return c;
    }

    object get(string name, bool connect = True, bool register_dependency = True, *hash<auto> rtopts) {
        return connection_dependency_manager.get(self, name, connect, register_dependency, rtopts);
    }

    hash<auto> getTags(string name) {
        return Connections::getConnection(name).getTags();
    }

    # called in the write lock
    private connectionUp(string name, string fmt) {
        ActionReason reason(tld.cx, vsprintf(fmt, argv), True);
        connection_dependency_manager.connectionUp(self, reason, name);
    }

    # this one overrides Connections::reload(), so it's safe to use rwl here again
    *hash<string, hash<auto>> reload(*hash<auto> cx) {
        #QDBG_LOG("ConnectionsServer::reload() threads: %N", get_stack());

        *hash<string, hash<auto>> rv;
        *hash<auto> nch;
        {
            # get an object that will hold the write lock and release it when the variable goes out of scope
            AutoWriteLock wlh = getWriteLockHelper();

            awaitChange();

            {
                stop_flag = True;
                on_exit stop_flag = False;

                stopIntern();

                QDBG_ASSERT(!dedicated);
            }

            # save a copy of currently-monitored remote instances
            nch = connection_map;
            rv = reloadIntern();
            startMonitoringIntern();
            # clear any ongoing events for remote connections no longer defined
        }

        {
            if (nch) {
                foreach string on in (keys nch) {
                    if (!nch{on}.up) {
                        ActionReason reason(cx, sprintf("%s connection %y no longer defined after reload", getMonitorType(), on), True);
                        connection_dependency_manager.connectionUp(self, reason, on, True);
                    }
                }

                connection_dependency_manager.clearConnectionDependencies(getAlertType(), nch.keys());
            }

            # handle disabled connections - enforce them down
            foreach string conn_name in (keys connection_map) {
                if (!connection_map{conn_name}.enabled) {
                    disabledEvent(conn_name);
                }
            }
        }

        Qorus.events.postConnectionReloaded(getMonitorType().upr(), self.list());
        log("<reload>", "started monitoring: %y", keys connection_map);
        return rv;
    }

    resetDependentWorkflowsAndServices(string name, string why) {
        connection_dependency_manager.resetDependentWorkflowsAndServices(self, name, why);
    }

    clearConnectionFailureCount(string name) {
        fmutex.lock();
        on_exit fmutex.unlock();

        remove conn_fail_count_map{name};
    }

    handleSuccessfulPing(AbstractConnection c, date dt, hash<PingInfo> ping_info, *bool oldok) {
        ActionReason reason(NOTHING, sprintf("ping to %s connection %y (%s) url: %y successful",
            getConnectionDbType(), c.name, c.desc, c.safe_url), True);
        log(c.name, "ping %y: OK (%y)", c.safe_url, dt);
        Qorus.alerts.clearOngoingAlert(reason, getAlertType(), c.name, getAlertText());
        connection_dependency_manager.checkStatusChange(self, c, oldok, True, ping_info.info);
        clearConnectionFailureCount(c.name);
    }

    handleFailedPing(AbstractConnection c, date dt, hash<ExceptionInfo> ex, *hash<auto> cx) {
        string err = sprintf("%s connection monitor: ping failed to %y (%s) url: %y (%y): %s: %s", getConnectionDbType(),
            c.name, c.desc, c.safe_url, dt, ex.err, ex.desc);
        log(c.name, "ping %y: %s: %s: %s (%y)", c.safe_url, get_ex_pos(ex), ex.err, ex.desc, dt);
        ActionReason reason(cx, ex, err);
        int count = incrementConnectionFailureCount(c.name);
        if (count == ConnectionPingFailureLimit) {
            connection_dependency_manager.connectionDown(self, reason, c.name,
                ConnectionDependencyManager::CONNECTION_RAISE_ALERT);
        }
    }

    int incrementConnectionFailureCount(string name) {
        fmutex.lock();
        on_exit fmutex.unlock();

        return ++conn_fail_count_map{name};
    }

    private deleteConnection(AbstractConnection c) {
        if (c.monitor) {
            if (c.supportsPollingApi()) {
                Qorus.pmonitor.removeConnection(c.getName());
            }
        }
        Connections::deleteConnection(c);
    }

    private connectionLoadedImpl(string name) {
        ActionReason reason(tld.cx, "connection was loaded correctly", True);
        Qorus.alerts.clearOngoingAlert(reason, getAlertType(), name, getConnectionDbType() + "-CONNECTION-UNUSABLE");
    }

    private connectionDeletedImpl(string name) {
        ActionReason reason(tld.cx, "connection was deleted", True);
        Qorus.alerts.clearAllOngoingAlerts(reason, getAlertType(), name);
    }

    private connectionErrorImpl(hash<auto> ex, string name, hash<auto> h) {
        string err = sprintf("%s: %s", ex.err, ex.desc);
        ActionReason r(NOTHING, err, True);
        # raise an "unusable" alert
        Qorus.alerts.raiseOngoingAlert(r, getAlertType(), name, getConnectionDbType() + "-CONNECTION-UNUSABLE", h);
        ##printf("DEBUG: %N\n", get_stack());
    }

    private startMonitoringIntern() {
        foreach AbstractConnection c in (connection_map.iterator()) {
            # use efficient polling with multiplexed I/O
            if (c.supportsPollingApi()) {
                Qorus.pmonitor.add(c, {"obj": self});
                QDBG_LOG("ConnectionsServer::startMonitoringIntern() %y: added to polling monitor", c.getName());
                continue;
            }

            # use inefficient polling with a dedicated polling thread per connection
            startDedicated(c.name);
        }
    }

    private monitor(string name) {
        on_exit {
            {
                m.lock();
                on_exit m.unlock();

                remove dedicated{name};
            }

            conn_cnt.dec();
        }

        bool first_run = True;

        while (True) {
            if (shutdown_flag) {
                log(name, "stopping monitoring due to system shutdown");
                break;
            }
            if (stop_flag) {
                log(name, "stopping monitoring due to reset");
                break;
            }

            {
                m.lock();
                on_exit m.unlock();

                # sleep for polling interval (interruptible with the Condition)
                if (!first_run && !stop_flag && !shutdown_flag) {
                    cond.wait(m, ConnectionsServer::POLL_INTERVAL);
                } else {
                    first_run = False;
                }
            }

            {
                *AbstractConnection c;
                {
                    rwl.readLock();
                    on_exit rwl.readUnlock();
                    c = connection_map{name};
                }
                if (!c) {
                    log(name, "connection no longer exists; exiting monitor thread");
                    return;
                }
                if (!c.monitor) {
                    log(name, "connection no longer should be monitored; exiting monitor thread");
                    return;
                }
                if (!c.enabled) {
                    log(name, "connection is disabled");
                    continue;
                }
                if (c.supportsPollingApi()) {
                    log(name, "connection now supports the polling API; exiting monitor thread");
                    return;
                }

                monitorPing(c);
            }
        }
    }

    private monitorPing(AbstractConnection c) {
        *bool oldok = c.last_check ? c.up : NOTHING;

        # delta time for ping
        date dt;
        date now = now_us();
        c.last_check = now;

        try {
            hash<PingInfo> ping_info = c.ping(True);
            handleSuccessfulPing(c, now_us() - now, ping_info, oldok);
        } catch (hash<ExceptionInfo> ex) {
            handleFailedPing(c, now_us() - now, ex);
        }
    }

    # issue #2110: recover in case of a temporary db connection error
    private insertDbConnectionIntern(AbstractConnection c) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                Connections::insertDbConnectionIntern(c);
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    # issue #2110: recover in case of a temporary db connection error
    private updateDbConnectionIntern(AbstractConnection c, bool set_updated) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                Connections::updateDbConnectionIntern(c, set_updated);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    # issue #2110: recover in case of a temporary db connection error
    private deleteDbConnectionIntern(AbstractConnection c) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                Connections::deleteDbConnectionIntern(c);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    # enable a connection. Called from REST API's UserConnectionRestClass
    # The DB handling is done in Connections::enable()
    enable(string name) {
        if (enableIntern(name, True)) {
            Qorus.events.postConnectionEnabledChange(getMonitorType().upr(), name, getAttributes(name).enabled);
            connection_dependency_manager.connectionUp(self, name, "connection has been reenabled");
            # instantly ensure availability of the connection
            monitorPing(connection_map{name});
        }
    }

    # disable a connection. Called from REST API's UserConnectionRestClass
    # The DB handling is done in Connections::disable()
    disable(string name) {
        if (enableIntern(name, False)) {
            disabledEvent(name);
        }
    }

    #! updates the DB entry for the connection to enable data debugging for the given connection
    enableDebugData(string name) {
        if (enableDebugDataIntern(name, True)) {
            Qorus.events.postConnectionDebugDataChange(getMonitorType().upr(), name, True);
        }
    }

    #! updates the DB entry for the connection to disable data debugging for the given connection
    disableDebugData(string name) {
        if (enableDebugDataIntern(name, False)) {
            Qorus.events.postConnectionDebugDataChange(getMonitorType().upr(), name, False);
        }
    }

    # set the connection down without updating DB. It's used internally
    # in the initial setup and in the disable() calls
    private disabledEvent(string name) {
        ActionReason ar(NOTHING, getMonitorType() + " connection has been disabled", True);
        Qorus.events.postConnectionEnabledChange(getMonitorType().upr(), name, getAttributes(name).enabled);
        connection_dependency_manager.connectionDown(self, ar, name,
            ConnectionDependencyManager::CONNECTION_NO_ALERT);
    }
}

class QorusPollingConnectionMonitor inherits PollingConnectionMonitor {
    logArgs(int lvl, string msg, auto args) {
        ConnectionsServer::logArgs(lvl, msg, args);
    }

    private handlePingSuccess(string name, date delta, *bool oldok) {
        QDBG_ASSERT(m.trylock());
        PollingConnectionMonitor::handlePingSuccess(name, delta);
        hash<PingInfo> ping_info(hash(cache{name}.conn){"name", "desc", "opts"});
        ping_info += {
            "ok": True,
            "time": delta,
            "info": "OK",
        };
        background cast<ConnectionsServer>(cache{name}.other.obj).handleSuccessfulPing(cache{name}.conn, delta,
            ping_info, oldok);
    }

    private handlePingFailed(string name, date delta, hash<ExceptionInfo> ex) {
        QDBG_ASSERT(m.trylock());
        PollingConnectionMonitor::handlePingFailed(name, delta, ex);
        background cast<ConnectionsServer>(cache{name}.other.obj).handleFailedPing(cache{name}.conn, delta, ex);
    }

    private handlePingTimeoutIntern(string name, date delta) {
        QDBG_ASSERT(m.trylock());
        PollingConnectionMonitor::handlePingTimeoutIntern(name, delta);
        try {
            throw "PING-TIMEOUT-ERROR", sprintf("ping on connection %y timed out after: %y", name, delta);
        } catch (hash<ExceptionInfo> ex) {
            background cast<ConnectionsServer>(cache{name}.other.obj).handleFailedPing(cache{name}.conn, delta, ex);
        }
    }
}