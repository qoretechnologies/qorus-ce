# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace OMQ;

class OMQ::RemoteFtpServiceAuthenticator inherits HttpServer::AbstractAuthenticator, RemoteHandlerBase {
    constructor(RemoteQorusService svc, string rid) : RemoteHandlerBase(svc, rid) {
        #QDBG_LOG("RemoteServiceAuthenticator::constructor() svc: %s %s rid: %y", svc.type, svc.name, rid);
    }

    auto methodGate(string m) {
        return svc.doRemoteFtpAuthRequest(rid, m, argv);
    }
}
