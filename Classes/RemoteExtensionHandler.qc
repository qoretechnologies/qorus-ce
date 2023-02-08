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

class OMQ::RemoteExtensionHandler inherits QorusExtensionHandler, RemoteHandlerBase {
    public {
        bool has_handle_request;
        bool has_handle_request_impl;
    }

    constructor(RemoteQorusService svc, string rid, hash<auto> conf)
            : QorusExtensionHandler(conf.group, conf.menuname, conf.desc),
            RemoteHandlerBase(svc, rid) {
        has_handle_request = conf.has_handle_request;
        has_handle_request_impl = conf.has_handle_request_impl;

        self += conf - (
            "auth", "has_handle_request", "has_handle_request_impl",
            "url", "content_type", "special_headers", "group", "menuname", "desc",
            "authlabel",
        );
    }

    destructor() {
    }

    hash<auto> handleRequest(hash<auto> cx, hash<auto> hdr, *data body) {
        if (has_handle_request) {
            return svc.doRemoteHttpRequest(rid, "handleRequest", (get_cx(cx), hdr, body));
        }
        return AbstractServiceHttpHandler::handleRequest(cx, hdr, body);
    }

    *hash<auto> handleRequestImpl(reference cx, hash<auto> hdr, *data body) {
        if (has_handle_request_impl) {
            hash<auto> rv = svc.doRemoteHttpRequest(rid, "handleRequestExternImpl", (get_cx(cx), hdr, body));
            cx = rv.cx;
            return rv.rv;
        }
        return AbstractServiceHttpHandler::handleRequestImpl(\cx, hdr, body);
    }

    auto methodGate(string m) {
        return svc.doRemoteHttpRequest(rid, m, argv);
    }

    static RemoteExtensionHandler get(RemoteQorusService svc, string rid, hash<auto> conf) {
        return new RemoteExtensionHandler(svc, rid, conf);
    }

    static private *AbstractAuthenticator getAuth(RemoteQorusService svc, string rid, hash<auto> conf) {
        QDBG_ASSERT(tld.svc.serviceid == svc.serviceid);
        switch (conf.auth) {
            case "param": return new QorusParametrizedAuthenticator(conf.authlabel);
            case "def": return new DefaultQorusRBACAuthenticator();
            case "remote": return new RemoteServiceAuthenticator(svc, rid);
            case "none": break;
            default: throw "UNSUPPORTED-AUTHENTICATION", sprintf("unrecognized authentication for service; conf: %y",
                conf);
        }
    }
}
