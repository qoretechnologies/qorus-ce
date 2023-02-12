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

class OMQ::RemoteSoapServiceAuthenticator inherits HttpServer::AbstractAuthenticator {
    public {
        RemoteQorusService svc;
        string bind;
    }

    constructor(RemoteQorusService svc, string bind) {
        #QDBG_LOG("RemoteServiceAuthenticator::constructor() svc: %s %s rid: %y", svc.type, svc.name, rid);
        self.svc = svc;
        self.bind = bind;
    }

    auto methodGate(string m) {
        return svc.doRemoteSoapAuthRequest(bind, m, argv);
    }
}
