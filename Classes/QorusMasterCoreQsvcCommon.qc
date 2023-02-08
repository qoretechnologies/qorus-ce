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

class QorusMasterCoreQsvcCommon {
    private {
        #! internal table cache
        hash<string, AbstractTable> table_cache;

        #! table cache mutex
        Mutex table_mutex();

        #! system datasource for process tracking
        Datasource omqds;

        #! current node info
        hash<auto> node_memory_info = {
            "node_priv": 0,
            "node_priv_str": get_byte_size(0),
            "node_ram_in_use": 0,
            "node_ram_in_use_str": get_byte_size(0),
            "node_cpu_count": 0,
            "node_load_pct": 0.0,
        };
    }

    constructor() {
        # issue #3522: do not allow Qorus to start as root
        if (!getuid() && hstat(ENV.OMQ_DIR).uid && !ENV.QORUS_ALLOW_ROOT) {
            logCommonFatal("cannot start Qorus as the root user; please start Qorus as the application user");
            exit(QSE_STARTUP_ERROR);
        }
    }

    AbstractTable getTable(string name) {
        *AbstractTable rv = table_cache{name};

        if (!rv) {
            table_mutex.lock();
            on_exit table_mutex.unlock();

            QorusRestartableTransaction trans(omqds.getDriverName());
            while (True) {
                try {
                    on_error omqds.rollback();

                    rv = table_cache{name} = (new Table(omqds, name)).getTable();
                } catch (hash<ExceptionInfo> ex) {
                    if (*string msg = trans.restartTransaction(ex)) {
                        logCommonInfo("%s", msg);
                        continue;
                    }
                    rethrow;
                }
                break;
            }
        }

        return rv;
    }

    #! selects a row from the given table and restarts the select if it fails with a cluster failover error
    /** does not commit the transaction

        useful as the first select in a transaction or a standalone select
    */
    *hash<auto> selectRowFromTable(AbstractTable table, hash<auto> select_hash) {
        QorusRestartableTransaction trans(table.getDriverName());
        while (True) {
            try {
                on_error table.rollback();

                return table.selectRow(select_hash);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    logCommonInfo("%s", msg);
                    continue;
                }
                rethrow;
            }
        }
    }

    #! selects a row from the given table and restarts the select if it fails with a cluster failover error
    /** does not commit the transaction

        useful as the first select in a transaction or a standalone select
    */
    *list<hash<auto>> selectRowsFromTable(AbstractTable table, hash<auto> select_hash) {
        QDBG_ASSERT(!table.getDatasource().currentThreadInTransaction());
        QorusRestartableTransaction trans(table.getDriverName());
        while (True) {
            try {
                on_error table.rollback();

                return table.selectRows(select_hash);
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    logCommonInfo("%s", msg);
                    continue;
                }
                rethrow;
            }
        }
    }

    *hash<LoggerParams> getLoggerParams(string type, auto id, *string name) {
        *hash<auto> loggerInfo = getLoggerInfo(type, id);
        if (!loggerInfo) {
            # rare case, there should always be default system logger
            if (id.val()) {
                logCommonDebug("No logger params for logger type %y ID %y found", type, id);
            } else {
                logCommonDebug("No logger params for logger type %y found", type);
            }
            return;
        }
        return makeLoggerParams(loggerInfo.params, type, name);
    }

    *hash<LoggerParams> makeLoggerParams(hash<auto> options, *hash<auto> input_params, string type, *string name) {
        if (!input_params) {
            return;
        }
        hash<LogFilenameSubs> subs = <LogFilenameSubs>{
            "name": name ?? type,
            "instance": options."instance-key",
            "path": options."logdir" + DirSep
        };
        hash<LoggerParams> params({
            "appenders": (map {$1.key: cast<hash<AppenderParams>>($1.value)},
                (remove input_params.appenders).pairIterator()),
        });
        params += input_params;
        return substituteLogFilename(params, subs);
    }

    private *int getLoggerId(string type, auto id) {
        # get logger ID if possible
        AbstractTable ix_table;
        hash<auto> wh;
        switch (type) {
            case "qdsp": {
                ix_table = getTable("connections");
                wh = {
                    "name": id,
                    "connection_type": "DATASOURCE",
                };
                break;
            }

            case "workflows":
            case "services":
            case "jobs": {
                ix_table = getTable(type);
                wh = {
                    type.substr(0, -1) + "id": id,
                };
                break;
            }

            default:
                if (!id.val() && SystemLoggers{type}) {
                    ix_table = getTable("loggers");
                    wh = {
                        "interface_table_name": type,
                    };
                    break;
                }
                return;
        }

        if (!ix_table.getDatasource().currentThreadInTransaction()) {
            return selectRowFromTable(ix_table, {
                "columns": "loggerid",
                "where": wh,
            }).loggerid;
        }

        return ix_table.selectRow({
            "columns": "loggerid",
            "where": wh,
        }).loggerid;
    }

    /** @param type the type; can be either an interface type like "workflows", "services", "jobs", or "qdsp"
        or a system logger type like "qorus-master", "http", "audit", etc
    */
    private *hash<auto> getLoggerInfo(string type, auto id) {
        hash<auto> wh;
        if (id.val()) {
            *softint loggerid = getLoggerId(type, id);
            if (loggerid) {
                wh = {
                    "loggerid": loggerid,
                };
            }
        }

        if (!wh) {
            wh = {
                "interface_table_name": type,
            };
        }

        AbstractTable loggerTable = getTable("loggers");
        QorusRestartableTransaction trans(loggerTable.getDriverName());
        while (True) {
            try {
                on_error loggerTable.rollback();

                *hash<auto> logger = loggerTable.selectRow({
                    "columns": ("loggerid", "params"),
                    "where": wh,
                });

                if (!logger) {
                    logger = loggerTable.selectRow({
                        "columns": ("loggerid", "params"),
                        "where": {
                            "interface_table_name": "system",
                        },
                    });
                }

                if (!logger) {
                    return;
                }

                logger.params = parse_yaml(logger.params);
                return logger;
            } catch (hash<ExceptionInfo> ex) {
                if (*string msg = trans.restartTransaction(ex)) {
                    logCommonInfo("%s", msg);
                    continue;
                }
                rethrow;
            }
        }
    }

    static string getNodeInfo(hash<auto> options, reference<hash<string, bool>> local_addresses) {
        # see which node applies to this system
        *hash<auto> nh = options.node;
        if (!nh) {
            if (!QorusCommonLib::inContainer()) {
                stderr.printf("WARNING: there is no \"qorus.node\" option in options file %y\n", options."option-file");
                stderr.printf("WARNING: please add a \"qorus.node\" entry manually or by calling \"schema-tool -V\"\n");
            }
            return QorusCommonLib::autoAssignNode(\local_addresses);
        }
        # make a reverse map from ip addresses to node names
        hash<auto> nm;
        foreach hash<auto> i in (nh.pairIterator()) {
            map nm{$1} = i.key, i.value;
        }

        # get all active IPv4/IPv6 interfaces on the current host
        list<string> l = cast<list<string>>(map $1.address, get_netif_list(),
            $1.address && ($1.family == AF_INET || $1.family == AF_INET6));

        #printf("DEBUG node: %N\n", nh);
        #printf("DEBUG nm: %N\n", nm);
        #printf("DEBUG l: %y\n", l);
        # create a map from node name to configured interfaces
        hash<string, list<string>> hm();
        map hm{nm{$1}} += ($1,), l, nm{$1};

        # if no node matches, exit with an error
        if (!hm) {
            if (!QorusCommonLib::inContainer()) {
                stderr.printf("WARNING: qorus.node option %y in %y does not match local host addresses: %y\n", nh,
                    options."option-file", l);
                stderr.printf("WARNING: please add a \"qorus.node\" entry manually or by calling \"schema-tool -V\"\n");
            }
            return QorusCommonLib::autoAssignNode(\local_addresses);
        }

        # if more than one node matches, exit with an error
        if (hm.size() > 1 && !QorusCommonLib::inContainer()) {
            stderr.printf("WARNING: the following qorus.node options in %y match the local host: %y\n",
                options."option-file", keys hm);
            stderr.printf("WARNING: however, only one node may match; please correct the file manually\n");
            stderr.printf("WARNING: using first match: %y\n", hm.firstKey());
        }

        # get matching node name
        string node = hm.firstKey();

        #printf("DEBUG node: %y\nnh: %y\nhm: %y\nnm: %y\n", node, nh, hm, nm);

        # if some addresses match and some not, exit with an error
        if (nh{node}.lsize() > hm{node}.lsize()) {
            # get hash of unmatched addresses
            hash<string, bool> all = map {$1: True}, nh{node};
            hash<string, bool> ah = all - hm{node};
            if (!QorusCommonLib::inContainer()) {
                stderr.printf("WARNING: %y defines qorus.node %y with the following addresses matching the local "
                    "host: %y, but the following expected address%s cannot be matched: %y\n", options."option-file",
                    node, hm{node}, ah.size() == 1 ? "" : "es", keys ah);
            }

            nh{node} = keys all{hm{node}};
            if (!QorusCommonLib::inContainer()) {
                stderr.printf("WARNING: using only: %y as local addresses\n", nh{node});
            }
        }

        # set local addresses
        map local_addresses{$1} = True, nh{node};

        return node;
    }

    abstract logCommonInfo(string fmt);
    abstract logCommonDebug(string fmt);
    abstract logCommonFatal(string fmt);
}
