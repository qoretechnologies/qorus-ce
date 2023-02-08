# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%allow-debugger

public namespace OMQ;

class OMQ::QorusDebugClient inherits AbstractQorusClient {
    constructor(AbstractQorusClientProcess process, string server_type, string server_name): AbstractQorusClient(process, server_type, server_name) {
    }

    sendDebugCommand(softstring cid, string action, auto data) {
        hash h = {
            #"client-id": getClientId(),
            "cid": cid,
            "method": action,
        };
        if (exists data) {
            h.args = data;
        }
        sendCheckResponseUnreliable(CPC_CORE_DEBUG_COMMAND, h, CPC_OK);
    }
}

#! Implements proxy to pass debug messages to cluster process using internal sockets
class OMQ::QorusClusterWebSocketDebugConnection inherits WebSocketHandler::WebSocketConnection {
    public {
        #! websocket context, cx.id is used for sending messages to particular client, custom field may be added as well
        hash cx;

        #! process id
        string pid;
    }
    private {
        QorusWebSocketDebugHandler dhandler;
        QorusDebugClient client;
    }

    #! The constructor is called by the @ref WebSocketHandler::WebSocketHandler "WebSocketHandler" when a new connection is made by a websocket client
    /**
        It is called from @ref WebSocketHandler::WebSocketHandler::getConnectionImpl() "WebSocketHandler::getConnectionImpl()".
    */
    constructor(QorusWebSocketDebugHandler n_handler, hash n_cx, string n_pid): WebSocketConnection(n_handler) {
        dhandler = n_handler;
        cx = n_cx;
        cx.handler = dhandler;
        pid = n_pid;
        dhandler.debugProgram.registerConnection(cx);
    }

    #! The method is called by the @ref WebSocketHandler::WebSocketHandler "WebSocketHandler" when message from the client is received
    /**
    */
    gotMessage(string msg) {
        client.sendDebugCommand(cx.id, "command", parse_yaml(msg));
        # pass data to remote cluster process
        #dhandler.receiveData(cx, msg);
    }

    #! Notifies debug control host that new connection is registered.
    /**
        It may e.g. send welcome message to identify itself
    */
    registered() {
        client = dhandler.acquireClient(pid, cx.id);
        on_error dhandler.releaseClient(pid, cx.id);
        client.sendDebugCommand(cx.id, "subscribe");
    }

    #! Implementation unregisters connection from debug program host
    /**
        The method is called by the @ref WebSocketHandler::WebSocketHandler "WebSocketHandler" when the connection is closed
        immediately after deregisterConnectionImpl. So the stuff may be implemented at both places but here it seems more reasonable
    */
    connectionClosed() {
        try {
            client.sendDebugCommand(cx.id, "unsubscribe");
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "location: %s", get_exception_string(ex));
        }
        dhandler.releaseClient(pid, cx.id);
    }

}

class OMQ::QorusWebSocketDebugHandler inherits WebSocketDebugHandler {
    private {
        # read-write lock
        RWLock crwl();

        # pid connection counters
        hash<string, int> clientCount;

        # pid to QorusDebugClient
        hash<string, QorusDebugClient> clients;

        # pid to websocket connection id (i.e. dedicated to debugger client)
        hash<string, auto> pid_to_cid;
    }

    constructor(WebSocketDebugProgramControl control, *HttpServer::AbstractAuthenticator auth, *hash opts) : WebSocketDebugHandler(control, auth, opts) {
    }

    #! check that the user has DEBUG-CONTROL
    hash handleRequest(hash cx, hash hdr, *data b) {
        return WebSocketDebugHandler::handleRequest(cx, hdr, b);
    }

    #! called when a connection is established; the default implementation creates a WebSocketConnection object
    WebSocketHandler::WebSocketConnection getConnectionImpl(hash cx, hash hdr, string cid) {
        olog(LoggerLevel::DEBUG, "olog QorusWebSocketDebugHandler::getConnectionImpl() cid %d: cx: %y", cid, cx);
        # parse url and check if local or cluster is to be connected
        string path = cx.url.path;
        # strip any query args from path
        path =~ s/\?.*$//;
        *list l = path.split("/");
        # handler is assigned to /debug url
        if (l.size() <= 1) {
            return WebSocketDebugHandler::getConnectionImpl(cx, hdr, cid);
        } else {
            string pid = l[1];
            olog(LoggerLevel::DEBUG, "QorusWebSocketDebugHandler::getConnectionImpl(): qmm.pmap: %y", Qorus.qmm.getProcessMap());
            *hash<auto> p = Qorus.qmm.lookupProcess(pid);
            if (!p) {
                throw "QORUS-DEBUG-WS-ERROR", sprintf("no cluster process matches %y, possible values %y", pid, keys Qorus.qmm.getProcessMap());
            }
            return new QorusClusterWebSocketDebugConnection(self, cx, pid);
        }
    }

    public QorusDebugClient acquireClient(string pid, softstring cid) {
        crwl.writeLock();
        on_exit crwl.writeUnlock();

        if (!clientCount{pid}) {
            # parse pid to get server type and server name
            list type_name = regex_extract(pid, "^([^-]+)-(.*)") ?? (pid);
            clients{pid} = new QorusDebugClient(Qorus, type_name[0], type_name[1]);
            clientCount{pid} = 1;
        } else {
            clientCount{pid}++;
        }
        pid_to_cid{pid}{cid} = True;
        return clients{pid};
    }

    public releaseClient(string pid, softstring cid) {
        crwl.writeLock();
        on_exit crwl.writeUnlock();
        if (exists clients{pid}) {
            if (clientCount{pid} == 1) {
                # unsubscribe ZMQ connection
                remove clients{pid};
                remove clientCount{pid};
            } else {
                clientCount{pid}--;
            }
        }
        remove pid_to_cid{pid}{cid};
    }

    /*
        qorus-¨core handlers for messages from debug server. Should be fast as data are just pushed in queue
    */
    public handleSendEvent(string cid, auto data) {
        sendData({"id": cid}, data);
    }

    public handleBroadcastEvent(auto data) {
        broadcastData(data);
    }

    public handleAbortedProcess(string process) {
        olog(LoggerLevel::DEBUG, "QorusWebSocketDebugHandler::handleAbortedProcess(%y)", process);
        crwl.writeLock();
        on_exit crwl.writeUnlock();
        foreach string cid in (keys pid_to_cid{process}) {
            # force stopping threads related to process
            stopOne(cid);
        }
    }
}

class OMQ::QorusWebSocketDebugProgramControl inherits DebugHandler::WebSocketDebugProgramControl, private:internal OMQ::QorusDebugProgramSource {
    constructor(): WebSocketDebugProgramControl(sprintf("%s v%s (build %s) instance %y", OMQ::ProductName, OMQ::version, QorusRevision, Qorus.options.get("instance-key"))) {
        logger = new QorusDebugLogger();
    }

    public setDebug(bool dbg) {
        logger.verbose = dbg ? DebugUtil::DUV_DEBUG : DebugUtil::DUV_INFO;
        foreach AbstractWebSocketDebugHandler h in (handlers) {
            if (h.logger != logger && h.logger) {
                h.logger.verbose = logger.verbose;
            }
        }
    }

    private bool isSupportedSourceCodeForLabel() {
        olog(LoggerLevel::INFO, "QorusWebSocketDebugProgramControl::isSupportedSourceCodeForLabel\n");
        return True;
    }

    private hash<auto> getSourceCodeForLabel(string name) {
        olog(LoggerLevel::INFO, "QorusWebSocketDebugProgramControl::getSourceCodeForLabel(%y)\n", name);
        return getSourceCodeForLabelImpl(name);
    }
}
