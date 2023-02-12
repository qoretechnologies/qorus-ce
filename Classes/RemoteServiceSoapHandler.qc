# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args
%enable-all-warnings

class OMQ::RemoteServiceSoapHandler inherits public AbstractServiceSoapHandler, RemoteHandlerBase {
    private {
        bool has_handle_request;
        bool has_handle_request_impl;
    }

    public {
        # for stream callbbacks with remote socket operations: <rid>-<tid> -> Socket
        static hash<string, Socket> socket_hash;
    }

    constructor(RemoteQorusService svc, string rid, hash<auto> conf)
            : AbstractServiceSoapHandler(
                conf.url,
                RemoteHttpRequestHandler::getAuth(svc, rid, conf),
            ),
            RemoteHandlerBase(svc, rid) {
        # add listeners, if any
        foreach hash<auto> lh in (conf.listeners) {
            if (lh.cert) {
                addListener(lh.bind, lh.cert, lh.key);
            } else {
                addListener(lh.bind, lh.cert_path, lh.key_path);
            }
        }

        has_handle_request = conf.has_handle_request;
        has_handle_request_impl = conf.has_handle_request_impl;

        self += conf - (
            "auth", "authlabel", "has_handle_request", "has_handle_request_impl", "url", "content_type",
            "special_headers", "type",
        );
    }

    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr,
            *data b) {
        string socket_key = rid + "-" + gettid();
        socket_hash{socket_key} = s;
        on_exit remove socket_hash{socket_key};

%ifdef QorusDebugInternals
        try {
            hash<HttpResponseInfo> rv = svc.handleRequestExtern(rid, socket_key, get_cx(cx)
                + {"socketencoding": s.getEncoding()}, hdr, b);
            QDBG_LOG("rv: %y", rv);
            return rv;
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("%s", get_exception_string(ex));
            rethrow;
        }
%else
        return svc.handleRequestExtern(rid, socket_key, get_cx(cx) + {"socketencoding": s.getEncoding()}, hdr, b);
%endif
    }

    auto methodGate(string m) {
        return svc.doRemoteHttpRequest(rid, m, argv);
    }

    static auto doSocketOperation(string socket_key, string method, *softlist args) {
        return call_object_method_args(socket_hash{socket_key}, method, args);
    }
}
