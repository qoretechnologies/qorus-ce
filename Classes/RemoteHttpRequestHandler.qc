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

class OMQ::RemoteHttpRequestHandler inherits AbstractServiceHttpHandler, RemoteHandlerBase {
    public {
        bool has_handle_request;
        bool has_handle_request_impl;
    }

    constructor(RemoteQorusService svc, string rid, hash<auto> conf)
            : AbstractServiceHttpHandler(conf.url, conf.content_type, conf.special_headers,
                RemoteHttpRequestHandler::getAuth(svc, rid, conf), conf.isregex),
            RemoteHandlerBase(svc, rid) {
        # add listeners, if any
        foreach hash<auto> lh in (conf.listeners) {
            if (lh.cert) {
                addListener(lh.bind, lh.cert, lh.key, lh.opt);
            } else {
                addListener(lh.bind, lh.cert_path, lh.key_path, lh.key_password, lh.opt);
            }
        }

        has_handle_request = conf.has_handle_request;
        has_handle_request_impl = conf.has_handle_request_impl;

        self += conf - ("auth", "authlabel", "has_handle_request", "has_handle_request_impl", "url", "content_type",
            "special_headers", "type");
    }

    destructor() {
    }

    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr,
            *data b) {
        string socket_key = rid + "-" + gettid();
        RemoteServiceRestHandler::socket_hash{socket_key} = s;
        on_exit remove RemoteServiceRestHandler::socket_hash{socket_key};

        return svc.handleRequestExtern(rid, socket_key, get_cx(cx) + {"socketencoding": s.getEncoding()}, hdr, b);
    }

    auto methodGate(string m) {
        return svc.doRemoteHttpRequest(rid, m, argv);
    }

    static AbstractServiceHttpHandler get(RemoteQorusService svc, string rid, hash<auto> conf) {
        switch (conf.type) {
            case "WS": return new RemoteServiceWebSocketHandler(svc, rid, conf);
            case "REST": return new RemoteServiceRestHandler(svc, rid, conf);
            case "SOAP": return new RemoteServiceSoapHandler(svc, rid, conf);
            default: return new RemoteHttpRequestHandler(svc, rid, conf);
        }
    }

    static *AbstractAuthenticator getAuth(RemoteQorusService svc, string rid, hash<auto> conf) {
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
