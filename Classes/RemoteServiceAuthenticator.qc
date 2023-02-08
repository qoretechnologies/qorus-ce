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

class OMQ::RemoteServiceAuthenticator inherits HttpServer::AbstractAuthenticator, RemoteHandlerBase {
    constructor(RemoteQorusService svc, string rid) : RemoteHandlerBase(svc, rid) {
        #QDBG_LOG("RemoteServiceAuthenticator::constructor() svc: %s %s rid: %y", svc.type, svc.name, rid);
    }

    auto methodGate(string m) {
        return svc.doRemoteHttpAuthRequest(rid, m, argv);
    }

    # we have to explicitly redirect methods declared in HttpServer::AbstractAuthenticator
    bool requiresAuthentication() {
        return svc.doRemoteHttpAuthRequest(rid, "requiresAuthentication");
    }

    string getRealm() {
        return svc.doRemoteHttpAuthRequest(rid, "getRealm");
    }

    authenticate(string user, string pass = "") {
        svc.doRemoteHttpAuthRequest(rid, "authenticate", (user, pass));
    }

    authenticateByIP(string ip, reference<string> user) {
        svc.doRemoteHttpAuthRequest(rid, "authenticateByIP", (ip, user));
    }

    *hash<HttpResponseInfo> authenticateRequest(HttpListenerInterface listener, hash<auto> hdr, reference<hash> cx) {
        QDBG_LOG("RemoteServiceAuthenticator::authenticateRequest() id: %d method: %y path: %y", cx.id, hdr.method, hdr.path);
        hash<auto> h = svc.authenticateRequestExtern(rid, hdr, get_cx(cx));
        cx += h.cx;
        return h.rv;
    }

    private hash getAuthHeader() {
        return svc.doRemoteHttpAuthRequest(rid, "getAuthHeader");
    }

    private hash<HttpResponseInfo> do401(string msg = "Authentication is required to access this server") {
        return cast<hash<HttpResponseInfo>>(svc.doRemoteHttpAuthRequest(rid, "do401", (msg,)));
    }
}
