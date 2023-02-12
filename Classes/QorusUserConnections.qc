# -*- mode: qore; indent-tabs-mode: nil -*-
# @file QorusUserConnectionsc.qc provides an API for user connections

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

/*
    https://bugs.qoretechnologies.com/projects/qorus/wiki/User_Connections
*/
class OMQ::QorusUserConnections inherits OMQ::ConnectionsServer {
    constructor(ConnectionDependencyManager v_cd, AbstractTable connection_table, AbstractTable connection_tags_table,
            code log_function, *RWLock rwl)
            : OMQ::ConnectionsServer(v_cd, connection_table, connection_tags_table, log_function,
                Qorus.options.get("connection-modules"), rwl) {
        known_schemes += (
            "file": new ConnectionScheme("file", "QorusFilesystemConnection"),
            "dir": new ConnectionScheme("dir", "QorusFilesystemConnection"),
        );

        reload();
    }

    AbstractDataProvider getDataProvider(string name, *int mapperid) {
        on_success if (mapperid) doMapperDependency(name, mapperid);
        return getConnection(name).getDataProvider();
    }

    string getAlertType() {
        return AlertTypeUser;
    }

    string getAlertText() {
        return "USER-CONNECTION-UNAVAILABLE";
    }

    string getMonitorType() {
        return "user";
    }

    string getConnectionDbType() {
        return "USER";
    }

    string getErrorCode() {
        return "CONNECTION-ERROR";
    }
}
