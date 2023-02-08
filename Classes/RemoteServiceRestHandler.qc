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

class OMQ::RemoteServiceRestHandler inherits public AbstractServiceRestHandler, RemoteHandlerBase {
    private {
        bool has_handle_request;
        bool has_handle_request_impl;
    }

    public {
        # for stream callbbacks with remote socket operations: <rid>-<tid> -> Socket
        static hash<string, Socket> socket_hash;
    }

    constructor(RemoteQorusService svc, string rid, hash<auto> conf)
            : AbstractServiceRestHandler(
                conf.url,
                conf.isregex,
                RemoteHttpRequestHandler::getAuth(svc, rid, conf),
                RemoteServiceRestHandler::getValidator(svc, rid, conf)
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
            "special_headers", "rest", "validator", "type",
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

    static *AbstractRestSchemaValidator getValidator(RemoteQorusService svc, string rid, hash<auto> conf) {
        switch (conf.validator) {
            case "null": return new NullRestSchemaValidator();
            case "remote": return new RemoteRestSchemaValidator(svc, rid);
            default: throw "UNSUPPORTED-VALIDATOR", sprintf("unrecognized validator for service; conf: %y", conf);
        }
    }

    static auto doSocketOperation(string socket_key, string method, *softlist args) {
        return call_object_method_args(socket_hash{socket_key}, method, args);
    }
}
