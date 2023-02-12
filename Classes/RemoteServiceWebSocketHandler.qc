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

class OMQ::RemoteServiceWebSocketHandler inherits public AbstractServiceWebSocketHandler, RemoteHandlerBase {
    public {
        # for WS connections: rid -> conn_id -> RemoteWebSocketConnection
        static hash<string, hash<string, RemoteWebSocketConnection>> conn_hash;
    }

    constructor(RemoteQorusService svc, string rid, hash<auto> conf)
            : AbstractServiceWebSocketHandler(conf.url, RemoteHttpRequestHandler::getAuth(svc, rid, conf)),
            RemoteHandlerBase(svc, rid)  {
        # add listeners, if any
        foreach hash<auto> lh in (conf.listeners) {
            if (lh.cert) {
                addListener(lh.bind, lh.cert, lh.key);
            } else {
                addListener(lh.bind, lh.cert_path, lh.key_path);
            }
        }

        self += conf - ("auth", "authlabel", "has_handle_request", "has_handle_request_impl", "url", "content_type",
                "special_headers", "type");
        QDBG_LOG("RemoteServiceWebSocketHandler::constructor() conf: %y", conf);
    }

    #! called when a connection is established; the default implementation creates a WebSocketConnection object
    WebSocketConnection getConnectionImpl(hash<auto> cx, hash<auto> hdr, string cid) {
        QDBG_LOG("RemoteServiceWebSocketHandler::getConnectionImpl() cx: %y hdr: %y cid: %y", cx, hdr, cid);
        RemoteWebSocketConnection conn(self, rid, cx, hdr, cid);
        QDBG_LOG("RemoteServiceWebSocketHandler::getConnectionImpl() registered RID: %y conn_id: %y", conn.getRid(), conn.getConnId());
        return conn_hash{conn.getRid()}{conn.getConnId()} = conn;
    }

    #! called when the connection terminates
    deregisterConnectionImpl(WebSocketConnection wsc) {
        RemoteWebSocketConnection conn = cast<RemoteWebSocketConnection>(wsc);
        remove conn_hash{conn.getRid()}{conn.getConnId()};
    }

    registerRemoteConnection(string rid, string conn_id, hash<auto> cx, hash<auto> hdr, string cid) {
        QDBG_LOG("RemoteServiceWebSocketHandler::registerRemoteConnection() rid: %y conn_id: %y", rid, conn_id);
        svc.registerWsConnection(rid, conn_id, cx, hdr, cid);
    }

    deregisterRemoteConnection(string rid, string conn_id) {
        QDBG_LOG("RemoteServiceWebSocketHandler::deregisterRemoteConnection() rid: %y conn_id: %y", rid, conn_id);
        svc.deregisterWsConnection(rid, conn_id);
    }

    auto callRemoteConnMethod(string rid, string conn_id, string method) {
        QDBG_LOG("RemoteServiceWebSocketHandler::callRemoteConnMethod() rid: %y conn_id: %y meth: %y args: %y", rid, conn_id, method, argv);
        return svc.callWsConnectionMethodArgs(rid, conn_id, method, argv);
    }

    static auto callLocalConnMethodArgs(string rid, string conn_id, string method, *softlist<auto> args) {
        QDBG_LOG("RemoteServiceWebSocketHandler::callLocalConnMethodArgs() rid: %y conn_id: %y meth: %y args: %y", rid, conn_id, method, args);
        *RemoteWebSocketConnection conn = conn_hash{rid}{conn_id};
        if (!conn) {
            throw "INVALID-WEBSOCKET-CONNECTION", sprintf("connection %y.%y no longer exists", rid, conn_id);
        }
        return call_object_method_args(conn, method, args);
    }
}

class OMQ::RemoteWebSocketConnection inherits public WebSocketConnection {
    private {
        string rid;
        softstring conn_id = gettid();
    }

    constructor(RemoteServiceWebSocketHandler handler, string rid, hash<auto> cx, hash<auto> hdr, string cid)
            : WebSocketConnection(handler) {
        self.rid = rid;
        handler.registerRemoteConnection(rid, conn_id, cx, hdr, cid);
    }

    destructor() {
        try {
            cast<RemoteServiceWebSocketHandler>(handler).deregisterRemoteConnection(rid, conn_id);
        } catch (hash<ExceptionInfo> ex) {
            cast<RemoteServiceWebSocketHandler>(handler).logInfo("error deregistering WebSocket connection: %s: %s", ex.err, ex.desc);
        }
    }

    string getRid() {
        return rid;
    }

    string getConnId() {
        return conn_id;
    }

    #! this method is called by the @ref WebSocketHandler::WebSocketHandler "WebSocketHandler" when messages from the client are received
    gotMessage(string msg) {
        cast<RemoteServiceWebSocketHandler>(handler).callRemoteConnMethod(rid, conn_id, "gotMessage", msg);
    }

    #! this method is called by the @ref WebSocketHandler::WebSocketHandler "WebSocketHandler" when messages from the client are received
    gotMessage(binary msg) {
        cast<RemoteServiceWebSocketHandler>(handler).callRemoteConnMethod(rid, conn_id, "gotMessage", msg);
    }

    #! this method is called by the @ref WebSocketHandler::WebSocketHandler "WebSocketHandler" when the connection is closed
    connectionClosed() {
        cast<RemoteServiceWebSocketHandler>(handler).callRemoteConnMethod(rid, conn_id, "connectionClosed");
    }

    #! called when the connection has been registered in handler and accept sending messages
    /** for e.g. to send initial welcome message
    */
    registered() {
        cast<RemoteServiceWebSocketHandler>(handler).callRemoteConnMethod(rid, conn_id, "registered");
    }
}