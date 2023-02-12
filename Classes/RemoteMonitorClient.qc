# -*- mode: qore; indent-tabs-mode: nil -*-
# @file RemoteMonitorClient.qc provides an API for remote Qorus connections

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

class OMQ::RemoteMonitorClient inherits ServerConnectionsClient {
    constructor(AbstractQorusClient core) : ServerConnectionsClient(core, "remotemonitor") {
    }

    AbstractDataProvider getDataProvider(string name, *int mapperid) {
        QorusClientServer::init();
        on_success if (mapperid) methodGateArgs("doMapperDependency", (name, mapperid));
        return create_object("QorusRemoteConnectionDataProvider", name);
    }

    QorusSystemAPIHelper get(string name, bool connect = True, bool register_dependency = True) {
        return cast<QorusSystemAPIHelper>(ServerConnectionsClient::get(name, connect, register_dependency));
    }
}

class OMQ::RemoteRestConnectionClient inherits ServerConnectionsClient {
    constructor(AbstractQorusClient core) : ServerConnectionsClient(core, "remotemonitor") {
    }

    QorusSystemRestHelper get(string name, bool connect = True, bool register_dependency = True) {
        AbstractConnection c = methodGateArgs("getConnectionRemote", (name, register_dependency), Qorus.getTldContext());
        hash<auto> h += c.getInfo(True);
        h += remove h.opts;
        h = h{"url" + RestConnection::OptionList};

        QorusSystemRestHelper obj(h);
        if (c.debug_data) {
            MonitorSingleton::setEventMonitor(obj, AlertTypeRemote, c.name);
        }
        if (connect) {
            obj.connect();
        }
        MonitorSingleton::setSocketMonitor(obj, {"mon": AlertTypeRemote, "name": name});
        return obj;
    }
}
