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

class OMQ::RemoteRestStreamRequestHandler inherits AbstractRestStreamRequestHandler {
    private {
        RemoteQorusService svc;
        string stream;
        string method;
        softstring id;

        static Sequence seq();

        hash<auto> remote_cx;
    }

    constructor(RemoteQorusService svc, string stream, string method, hash<auto> cx, *hash<auto> ah) : AbstractRestStreamRequestHandler(cx, ah) {
        self.svc = svc;
        self.stream = stream;
        self.method = method;
        remote_cx = get_cx(cx) + {"socketencoding": cx.socketobject.getEncoding()};
        id = seq.next();
        svc.registerRemoteStream(self);
    }

    destructor() {
        if (svc) {
            svc.deregisterRemoteStream(self);
        }
    }

    updateEncoding(string enc) {
        cx.socketobject.setEncoding(enc);
    }

    string getStream() {
        return stream;
    }

    string getMethod() {
        return method;
    }

    string getId() {
        return id;
    }

    hash<auto> getContext() {
        return remote_cx;
    }

    *hash<auto> getRequestArgs() {
        return ah;
    }

    *code getPersistentClosedNotification() {
        if (svc.getRestStreamPersistentClosedNotification(id)) {
            return sub () {
                svc.callPersistentClosedNotification(id);
            };
        }
    }

    bool isPersistent() {
        return svc.remoteRestStreamMethodCall(id, "isPersistent");
    }

    setTimeout(timeout n_timeout_ms) {
        svc.remoteRestStreamMethodCall(id, "setTimeout", n_timeout_ms);
    }

    *int getTimeout() {
        return svc.remoteRestStreamMethodCall(id, "getTimeout");
    }

    streamError(hash<auto> n_ex) {
        svc.remoteRestStreamMethodCall(id, "streamError", n_ex);
    }

    hash<auto> getResponseHeaderMessageImpl() {
        return svc.remoteRestStreamMethodCall(id, "getResponseHeaderMessageImpl");
    }

    recvImpl(hash v) {
        if (v.obj instanceof Socket) {
            # FIXME might need to simulate this to ensure 100% compatibility
            remove v.obj;
            #v.obj = "fakesocket";
        }
        svc.remoteRestStreamMethodCall(id, "recvImpl", v);
    }

    auto sendImpl() {
        return svc.remoteRestStreamMethodCall(id, "sendImpl");
    }

    auto methodGate(string m) {
        return svc.remoteRestStreamMethodCallArgs(id, m, argv);
    }
}