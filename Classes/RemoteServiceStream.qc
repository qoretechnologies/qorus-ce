# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace OMQ;

class OMQ::RemoteServiceStream inherits AbstractServiceStream {
    private {
        # service object
        RemoteQorusService svc;

        # stream ID
        string ssid;
    }

    constructor(RemoteQorusService svc, hash<auto> conf) : AbstractServiceStream(conf.cx, conf.ah) {
        self.svc = svc;
        ssid = conf.ssid;
    }

    destructor() {
        svc.streamDeleted(ssid);
    }

    hash getResponseHeaderMessageImpl() {
        return svc.doRemoteStreamRequest(ssid, "getResponseHeaderMessageImpl", argv);
    }

    recvImpl(hash v) {
        svc.doRemoteStreamRequest(ssid, "recvImpl", argv);
    }

    auto sendImpl() {
        return svc.doRemoteStreamRequest(ssid, "sendImpl");
    }

    auto methodGate(string m) {
        return svc.doRemoteStreamRequest(ssid, m, argv);
    }
}
