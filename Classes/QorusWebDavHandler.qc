# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args
%enable-all-warnings

#! Wraps the Qorus RBAC object while allowing OPTIONS requests to be handled without authentication
class OMQ::QorusWebDavAuthenticator inherits AbstractAuthenticator {
    bool requiresAuthentication() {
        return False;
    }

    string getRealm() {
        return Qorus.rbac.getRealm();
    }

    authenticate(string user, string pass = "") {
    }

    authenticateByIP(string ip, reference<string> user) {
    }

    *hash<HttpResponseInfo> authenticateRequest(HttpListenerInterface listener, hash<auto> hdr,
            reference<hash<auto>> cx) {
    }
}

class OMQ::QorusWebDavHandler inherits WebDavHandler::FsWebDavHandler {
    constructor(*string root_path) : FsWebDavHandler(QorusWebDavHandler::checkPath(ENV.OMQ_DIR + "/user"),
            new QorusWebDavAuthenticator(),
            root_path) {
    }

    static string checkPath(string path) {
        if (!is_dir(path)) {
            mkdir_ex(path, NOTHING, True);
        }
        return path;
    }

    private hash<HttpResponseInfo> handleOptionsImpl(Socket s, hash<auto> cx, hash<auto> hdr, *data body) {
        hash<HttpResponseInfo> rv = FsWebDavHandler::handleOptionsImpl(s, cx, hdr, body);
        rv.hdr += QorusHttpServer::getCorsResponseHeaders(cx);
        return rv;
    }

    private *hash<HttpResponseInfo> checkAuth(string method, hash<auto> cx, hash<auto> hdr, *data body) {
    }
}
