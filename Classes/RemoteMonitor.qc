# -*- mode: qore; indent-tabs-mode: nil -*-
# @file RemoteMonitor.qc provides an API for remote Qorus connections

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

class OMQ::RemoteMonitor inherits OMQ::ConnectionsServer {
    constructor(ConnectionDependencyManager v_cd, AbstractTable connection_table, AbstractTable connection_tags_table,
            code log_function, *RWLock rwl)
        : OMQ::ConnectionsServer(v_cd, connection_table, connection_tags_table, log_function, NOTHING, rwl) {
    }

    string getAlertType() {
        return AlertTypeRemote;
    }

    string getAlertText() {
        return "REMOTE-UNAVAILABLE";
    }

    string getMonitorType() {
        return "remote";
    }

    string getConnectionDbType() {
        return "REMOTE";
    }

    string getErrorCode() {
        return "REMOTE-ERROR";
    }

    AbstractDataProvider getDataProvider(string name, *int mapperid) {
        on_success if (mapperid) doMapperDependency(name, mapperid);
        return create_object("QorusRemoteConnectionDataProvider", name);
    }

    *list<hash<auto>> getRemoteHealthList() {
        rwl.readLock();
        on_exit rwl.readUnlock();

        if (!connection_map) {
            return;
        }

        list<hash<auto>> ret;
        HashIterator it(connection_map);
        while (it.next()) {
            AbstractConnection connection = it.getValue();
            # issue #2790: do not return loopback connections as remote connections
            if (connection.loopback) {
                continue;
            }
            # valid remote connection
            if (connection instanceof QorusHttpConnection) {
                # cannot use the push operator here due to a type error with complex types
                ret += {"name": connection.name} + cast<QorusHttpConnection>(connection).getHealthInfo();
            } else {
                # invalid conn. AbstractConnection does not have getHealthInfo()
                # cannot use the push operator here due to a type error with complex types
                ret += {"name": connection.name, "health": "UNKNOWN", "instance_key": "unknown"};
            }
        }

        return ret;
    }

    QorusSystemRestHelper getRest(string name, bool connect = True, bool register_dependency = True) {
        *hash<auto> src = qorus_get_source_hash();

        AbstractConnection c;
        *bool oldok;

        QorusSystemRestHelper obj;
        try {
            c = getConnection(name);
            oldok = c.last_check ? c.up : NOTHING;

            hash<auto> h = c.getExtendedInfo({"with_passwords": True});
            h += remove h.opts;
            h = h{"url" + RestConnection::OptionList};

            obj = new QorusSystemRestHelper(h);
            if (c.debug_data) {
                MonitorSingleton::setEventMonitor(obj, getAlertType(), c.name);
            }
            if (connect) {
                obj.connect();
            }
            MonitorSingleton::setSocketMonitor(obj, {"mon": getAlertType(), "name": name});
        } catch (hash<ExceptionInfo> ex) {
            # add dependency and then rethrow
            if (c) {
                string err = sprintf("%s connection monitor: REST connection could not be acquired to %y (%s) "
                    "url: %y", getMonitorType(), c.name, c.desc, c.safe_url);
                connection_dependency_manager.manageDependency(self, c, src, register_dependency, False, oldok, err,
                    ex);
            } else {
                string err = sprintf("%s connection monitor: REST connection could not be acquired to unknown remote "
                    "connection %y", getMonitorType(), name);
                connection_dependency_manager.manageDependency(self, name, src, register_dependency, err, ex);
            }
            rethrow;
        }

        connection_dependency_manager.manageDependency(self, c, src, register_dependency,
            connect ? connect : NOTHING, oldok);

        return obj;
    }

    list<auto> getRemoteList() {
        rwl.readLock();
        on_exit rwl.readUnlock();

        *list<auto> l = map $1, keys connection_map, !connection_map.$1.loopback;
        return l ? l : ();
    }

    hash<auto> getInfo(string conn, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        # do not try to call getHealthInfo() on InvalidConnection objects
        *AbstractConnection connection = connection_map{conn};
        if (!connection) {
            throw "CONNECTION-ERROR", sprintf("unknown remote connection %y; known connections: %y", conn,
                keys connection_map);
        }
        return ConnectionsServer::getInfo(conn, opts) + {
                "connectionid": connection.internal_info.id,
            } + (
                connection instanceof QorusHttpConnection
                    ? cast<QorusHttpConnection>(connection).getHealthInfo()
                    : NOTHING
            );
    }

    *hash<auto> tryGetInfo(string conn, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        # do not try to call getHealthInfo() on InvalidConnection objects
        *AbstractConnection connection = connection_map{conn};
        if (connection) {
            return ConnectionsServer::getInfo(conn, opts) + {
                    "connectionid": connection.internal_info.id,
                } + (
                    connection instanceof QorusHttpConnection
                        ? cast<QorusHttpConnection>(connection).getHealthInfo()
                        : NOTHING
                );
        }
    }

    *hash<auto> tryGetInfoFromId(int id, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        # do not try to call getHealthInfo() on InvalidConnection objects
        *AbstractConnection connection = id_map{id};
        if (connection) {
            return ConnectionsServer::getInfo(connection.name, opts) + {
                    "connectionid": connection.internal_info.id,
                } + (
                    connection instanceof QorusHttpConnection
                        ? cast<QorusHttpConnection>(connection).getHealthInfo()
                        : NOTHING
                );
        }
    }

    private AbstractConnection newConnection(string name, string desc, string url, hash<auto> attributes = {},
            hash<auto> options = {}) {
        return new QorusHttpConnection(name, desc, url, attributes, options);
    }
}
