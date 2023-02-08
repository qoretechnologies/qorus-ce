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

class FakeSocket {
    private:internal {
        string enc;
        *string new_enc;
    }

    constructor(string enc) {
        self.enc = enc;
    }

    setEncoding(string nenc) {
        if (nenc != enc) {
            new_enc = nenc;
        }
    }

    *string getEncoding() {
        return new_enc;
    }
}

class RemoteSocket inherits Socket {
    private {
        string socket_key;
    }

    constructor(string key, *string encoding) {
        socket_key = key;
        if (encoding) {
            Socket::setEncoding(encoding);
        }
    }

    setEncoding(string encoding) {
        Socket::setEncoding(encoding);
        Qorus.callCoreFunction("qorus_api_remote_socket_operation", socket_key, "setEncoding", encoding);
    }

    sendHTTPResponseWithCallback(code scb, softint status_code, string status_desc, string http_version, hash headers, timeout timeout_ms = -1) {
        ClusterQorusService::sendHTTPResponseWithCallback(socket_key, scb, status_code, status_desc, http_version, headers, timeout_ms);
    }

    readHTTPChunkedBodyWithCallback(code rcb, timeout timeout_ms = -1) {
        ClusterQorusService::readHTTPChunkedBodyWithCallback(socket_key, rcb, timeout_ms);
    }
}

hashdecl HandlerConfig {
    string lid;
    hash<auto> conf;
}

class OMQ::ClusterQorusService inherits LocalQorusService {
    public {
        bool stopping = False;
    }

    private:internal {
        # stream handler service hash; access protected with "rm"
        hash<string, hash> shh;

        # HTTP handler hash; access protected with "rm"
        hash<string, AbstractServiceHttpHandler> hh;

        # HTTP handler config list; access protected with "rm"
        /** NOTE: the same handler can be bound multiple times with different configurations
            the configurations must be stored in orde for the calls to be replayed if qorus-core crashes
        */
        list<hash<HandlerConfig>> hcl;

        # UI Extension handler hash; access protected with "rm"
        hash<string, hash> uhh;

        # resource handler hash; access protected with "rm"
        hash<string, hash<string, hash<auto>>> rh;

        # SOAP handler resource hash
        hash<string, hash> srh;

        # SOAP listener resource hash
        hash<string, hash> slrh;

        # FTP handler resource hash
        hash<string, AbstractFtpHandler> frh;

        # persistent data helper objects
        hash<string, AbstractPersistentDataHelper> ph;

        # resource mutex
        Mutex rm();

        # to track REST stream request objects
        hash<string, AbstractRestStreamRequestHandler> arsh;

        # to track REST service stream objects; ssid -> AbstractServiceStream
        hash<string, AbstractServiceStream> arssh;

        # to track rest stream "persistent closed" notification closures / call references
        hash<string, code> pch;

        # persistence factory code
        code pf;

        # to track WebSocket connection objects; lid -> conn_id -> WebSocketConnection
        hash<string, hash<string, WebSocketConnection>> ws_conn_map;

        # WebSocket connection thread termination condition var
        Condition ws_term_cond();

        # WebSocket connection thread termination wait counter
        int ws_term_waiting = 0;

        # flag that the WebSocket connection polling thread is running
        bool ws_running = False;

        # flag to stop the WebSocket connection polling thread
        bool ws_quit = False;

        # WebSocket connection polling condition
        Condition ws_cond();

        # WebSocket connection polling interval
        const WebSocketConnectionPollingInterval = 100ms;

        # startreason text
        string startreason_text;

        # code key -> code for socket send callback operations
        static hash<string, code> send_code_hash;

        # code key -> code for socket recv callback operations
        static hash<string, code> recv_code_hash;
    }

    constructor(string type, string name) : LocalQorusService(type, name) {
    }

    # called when the qsvc process is relaunched; the qsvc process must drive the initialization
    recover() {
        QDBG_LOG("%s service", "recovering");

        *hash<auto> sq = Qorus.qmm.lookupService(Qorus.interfaceId, False);
        if (!sq) {
            throw "NO-SERVICE", sprintf("serviceid %y does not exist", Qorus.interfaceId);
        }

        ensure_create_tld();
        tld.svc = self;

        string id = Qorus.getNetworkId();

        # inform qorus-core that we are restarting now
        Qorus.callCoreFunction("qorus_api_restarting_service", type, name, id);

        # setup service
        doRemoteSetup(sq, sprintf("qsvc process %y %sstarted", id, "re"));

        # issue #2643: do not call init method twice, as it will be called from qorus-core under certain conditions
        if (hasInit()) {
            try {
                LocalQorusService::callMethodImpl("init");
            } catch (hash<ExceptionInfo> ex) {
                # if the init method fails, then exit the process
                logInfo("service init() method failed: %s", get_exception_string(ex));
                logInfo("aborting service start");
                Qorus.shutdownQsvc();
                return;
            }
        }

        # issue #2975: do not set running state until init has run
        Qorus.setStateRunning();

        if (startServiceConditional()) {
            Qorus.callCoreFunction("qorus_api_ref_service", type, name);
        }

        Qorus.callCoreFunction("qorus_api_service_recovered", type, name);
    }

    doRemoteSetup(hash<auto> sq, string startreason_text) {
%ifdef QorusDebugInternals
        # issue #2558: if a signal file exists, then terminate the process here
        if (is_file(string filename = sprintf("%s/%s-%s-%s-%s-%s-doRemoteSetup", tmp_location(),
            Qorus.options.get("instance-key"), type, name, sq.version, sq.serviceid))) {
            QDBG_LOG("ClusterQorusService::doRemoteSetup() SIGNAL FILE %y found; unlinking", filename);
            unlink(filename);
            QDBG_LOG("ClusterQorusService::doRemoteSetup() TERMINATING");
            exit(1);
        } else {
            QDBG_LOG("ClusterQorusService::doRemoteSetup() NOT FOUND: %s", filename);
        }
%endif

        self.startreason_text = startreason_text;
        *int po = setupIntern(sq);
        LocalQorusService::setupImpl(sq, po);

        # issue #3198: initialize mapper objects after service is created
        Qorus.setupMappers();
    }

    string getStartReasonText() {
        return startreason_text;
    }

    bool getStopping() {
        return stopping;
    }

    qorusCoreRestarted() {
        try {
            logInfo("recovering a qorus-core restart");
            on_exit logInfo("done recovering qorus-core restart");

            rm.lock();
            on_exit rm.unlock();

            # drop all in-progress REST service stream handler objects; connections are no longer valid
            map delete arssh.$1, keys arssh;

            # drop all in-progress WebSocket connections; connections are no longer valid
            map delete ws_conn_map.$1, keys ws_conn_map;

            # reinstate remote streams with qorus-core
            if (shh) {
                logInfo("recovering stream handlers: %y", keys shh);
                map Qorus.callCoreFunction("qorus_api_service_stream_register", type, name, $1.key, $1.value.methods,
                    $1.value.desc), shh.pairIterator();
            }

            # reinstate handlers with qorus-core
            if (hcl) {
                logInfo("recovering HTTP handlers for URLs: %y", (map hh{$1.lid}.url, hcl));
                map Qorus.callCoreFunction("qorus_api_service_bind_http", type, name, $1.lid, $1.conf), hcl;
            }

            if (uhh) {
                logInfo("recovering UI extension handlers: %y", keys uhh);
                map Qorus.callCoreFunction("qorus_api_service_register_ui_extension", type, name, $1.key,
                    $1.value.handler.getRemoteConfig(), $1.value.url_name), uhh.pairIterator();
            }

            # reinstate resource handlers
            if (rh) {
                logInfo("recovering resource handlers: %y", keys rh);
                foreach string rname in (keys rh) {
                    map Qorus.callCoreFunction("qorus_api_service_bind_handler", type, name, $1.key, rname,
                        $1.value.handler.getRemoteConfig()), rh{rname}.pairIterator(), !$1.value.url;
                    map Qorus.callCoreFunction("qorus_api_service_bind_handler", type, name, $1.key, rname,
                        $1.value.handler.getRemoteConfig(), $1.value.url, $1.value.content_type, $1.value.special_headers,
                        $1.value.isregex), rh{rname}.pairIterator(), $1.value.url;
                }
            }

            # reinstate persistence factory
            if (pf) {
                logInfo("recovering persistent connection handler");
                Qorus.callCoreFunction("qorus_api_service_persistence_register", type, name);
            }

            # reinstate SOAP handlers
            if (srh) {
                logInfo("recovering SOAP handlers: %y", keys srh);
                map Qorus.callCoreFunction("qorus_api_service_register_soap_service", type, name, $1.sws, $1.service,
                    $1.uri_path, $1.newapi), srh.iterator();
            }

            # reinstate FTP handlers
            if (frh) {
                logInfo("recovering FTP handlers: %y", keys frh);
                map Qorus.callCoreFunction("qorus_api_service_bind_ftp", type, name, $1.key, $1.value.getRemoteConfig()),
                    frh.pairIterator();
            }

            if (int threads = thread_counter.getCount()) {
                Qorus.callCoreFunction("qorus_api_service_set_thread_count", type, name, threads);
            }

            # set error status and delete any persistent connections currently in progress
            map $1.setError(), ph.iterator();
            remove ph;
        } catch (hash<ExceptionInfo> ex) {
            logFatal("a fatal error has occurred recovering from a qorus-core restart: %s; the process will "
                "terminate in 2 seconds", get_exception_string(ex));
            sleep(2);
            exit(1);
        }
    }

    hash<auto> getInfo(*hash<auto> cx) {
        return getServiceInfo() + Qorus.callCoreFunction("qorus_api_service_get_local_info", type, name, cx) + getInfoImpl();
    }

    auto callMethodImpl(string method, auto args, *binary serialized_args, *hash<auto> cx) {
%ifdef QorusDebugInternals
        if (method == "init") {
            # issue #2603: if a signal file exists, then terminate the process here
            if (is_file(string filename = sprintf("%s/%s-%s-%s-%s-%s-init", tmp_location(),
                Qorus.options.get("instance-key"), type, name, version, serviceid))) {
                QDBG_LOG("ClusterQorusService::callMethodImpl() SIGNAL FILE %y found; unlinking", filename);
                unlink(filename);
                QDBG_LOG("ClusterQorusService::callMethodImpl() TERMINATING");
                exit(1);
            } else {
                QDBG_LOG("ClusterQorusService::callMethodImpl() NOT FOUND: %s", filename);
            }
        }
%endif
        on_success if (method == "init") {
             Qorus.setStateRunning();
        }

        # do not allow thread sources to stay in place beyond this call
        ThreadResourceHelper thread_resource_helper();

        if (serialized_args) {
            QDBG_ASSERT(!exists args);
            args = deserialize(serialized_args);
        }

        tld.cx = cx;
        return LocalQorusService::callMethodImpl(method, args);
    }

    streamRegister(string stream, softlist<string> methods, code factory, string desc) {
        {
            rm.lock();
            on_exit rm.unlock();

            if (shh{stream}) {
                throw "STREAMHANDLER-ERROR", sprintf("stream handler %y for %s service %y has already been registered", stream, type, name);
            }

            shh{stream} = {
                "methods": (map {$1.upr(): True}, methods),
                "factory": factory,
                "desc": desc,
            };
        }

        try {
            # register the remote stream with qorus-core
            Qorus.callCoreFunction("qorus_api_service_stream_register", type, name, stream, methods, desc);
        } catch (hash<ExceptionInfo> ex) {
            rm.lock();
            on_exit rm.unlock();

            remove shh{stream};
            rethrow;
        }
    }

    hash<auto> getRemoteServiceStream(string lid, hash<auto> cx, hash<auto> hdr, *data body) {
        # do not lock "rm" here to ensure that requests can be handled in parallel
        Socket fakesocket();
        fakesocket.setEncoding(cx.socketencoding);

        AbstractServiceHttpHandler hr = hh{lid} ?? uhh{lid}.handler;
        AbstractServiceStream stream = call_object_method_args(hr, "getServiceStreamRequestExtern", (hr, fakesocket, cx, hdr, body));

        string ssid = stream.uniqueHash();

        # register stream
        {
            rm.lock();
            on_exit rm.unlock();

            if (!arssh{ssid}) {
                arssh{ssid} = stream;
            }
        }

        hash<auto> conf = {
            "ssid": ssid,
        };

        if (fakesocket.getEncoding() != cx.socketencoding) {
            conf.socketencoding = fakesocket.getEncoding();
        }

        return conf;
    }

    auto doRemoteStreamRequest(string ssid, string method, softlist<auto> args) {
         # do not lock "rm" here to ensure that requests can be handled in parallel
        return call_object_method_args(arssh{ssid}, method, args);
    }

    streamDeleted(string ssid) {
        # deregister stream
        rm.lock();
        on_exit rm.unlock();

        delete arssh{ssid};
    }

    *string createRemoteStream(string id, string stream, hash<auto> cx, *hash<auto> ah) {
        rm.lock();
        on_exit rm.unlock();

        if (!shh{stream}) {
            throw "STREAMHANDLER-ERROR", sprintf("stream handler %y for %s service %y has not been registered", stream, type, name);
        }

        cx.socketobject = new FakeSocket(cx.socketencoding);
        #QDBG_LOG("ClusterQorusService::createRemoteStream() cx: %y", cx);

        arsh{id} = shh{stream}.factory(cx, ah);
        QDBG_LOG("created stream %y (all streams: %y)", id, keys arsh);

        return cx.socketobject.getEncoding();
    }

    deleteRemoteStream(string id) {
        rm.lock();
        on_exit rm.unlock();

        # delete "persistent closed" notification closure for rest stream handler, if any
        delete pch{id};
        # delete rest stream request handler
        delete arsh{id};
    }

    callPersistentClosedNotification(string id) {
        # do not lock "rm" here to ensure that requests can be handled in parallel
        pch{id}();
    }

    bool getRestStreamPersistentClosedNotification(string id) {
        rm.lock();
        on_exit rm.unlock();

        if (!pch{id}) {
            *code c = arsh{id}.getPersistentClosedNotification();
            if (c) {
                pch{id} = c;
            }
        }

        return pch{id} ? True : False;
    }

    auto remoteRestStreamMethodCallArgs(string id, string method, *softlist<auto> args) {
        rm.lock();
        on_exit rm.unlock();

        return call_object_method_args(arsh{id}, method, args);
    }

    uiExtensionRegister(QorusExtensionHandler handler, *string url_name) {
        string lid = handler.getUniqueHash();

        {
            rm.lock();
            on_exit rm.unlock();

            if (uhh{lid}) {
                throw "UI-EXTENSION-ERROR", sprintf("handler %y has already been registered", lid);
            }

            uhh{lid} = {
                "handler": handler,
                "url_name": url_name,
            };
        }

        try {
            # bind the handler with qorus-core
            Qorus.callCoreFunction("qorus_api_service_register_ui_extension", type, name, lid, handler.getRemoteConfig(), url_name);
        } catch (hash<ExceptionInfo> ex) {
            rm.lock();
            on_exit rm.unlock();

            remove uhh{lid};
            rethrow;
        }
    }

    list<string> bindHttp(OMQ::AbstractServiceHttpHandler handler, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        string lid = handler.getUniqueHash();

        {
            rm.lock();
            on_exit rm.unlock();

            if (!hh{lid}) {
                hh{lid} = handler;
            }
        }

        try {
            # get handler configuration
            hash<auto> conf = handler.getRemoteConfig();
            # bind the handler with qorus-core
            list<auto> rv = Qorus.callCoreFunction("qorus_api_service_bind_http", type, name, lid, conf, opts);

            # save handler configuration at the time of binding; the same handler can be bound multiple
            # times with different configurations
            rm.lock();
            on_exit rm.unlock();
            hcl += hash<HandlerConfig>{
                "lid": lid,
                "conf": conf,
            };

            return rv;
        } catch (hash<ExceptionInfo> ex) {
            rm.lock();
            on_exit rm.unlock();

            remove hh{lid};
            rethrow;
        }
    }

    registerWsConnection(string lid, string conn_id, hash<auto> cx, hash<auto> hdr, string cid) {
        WebSocketConnection conn = call_object_method(hh{lid}, "doNewConnection", cx, hdr, cid);

        rm.lock();
        on_exit rm.unlock();

        if (!ws_conn_map) {
            startWebSocketMonitorThreadIntern();
        }

        ws_conn_map{lid}{conn_id} = conn;
        QDBG_LOG("ClusterQorusService::registerWsConnection() lid: %y conn_id: %y (%s)", lid, conn_id, conn.className());
    }

    deregisterWsConnection(string lid, string conn_id) {
        bool stop;
        {
            rm.lock();
            on_exit rm.unlock();

            *WebSocketConnection conn = remove ws_conn_map{lid}{conn_id};
            if (conn) {
                if (!ws_conn_map{lid}) {
                    remove ws_conn_map{lid};
                }
            }

            if (!ws_conn_map) {
                stop = True;
            }
        }
        if (stop) {
            stopWebSocketMonitorThread(True);
        }
        QDBG_LOG("ClusterQorusService::deregisterWsConnection() lid: %y conn_id: %y", lid, conn_id);
    }

    auto callWsConnectionMethodArgs(string lid, string conn_id, string method, *list<auto> args) {
        *WebSocketConnection conn;

        {
            rm.lock();
            on_exit rm.unlock();

            conn = ws_conn_map{lid}{conn_id};
        }
        if (!conn) {
            throw "INVALID-WEBSOCKET-CONNECTION", sprintf("connection %y.%y is not known", lid, conn_id);
        }

        return call_object_method_args(conn, method, args);
    }

    auto doRemoteFtpRequest(string lid, string method, softlist<auto> args) {
        # do not lock "rm" here to ensure that requests can be handled in parallel
        return call_object_method_args(frh{lid}, method, args);
    }

    auto doRemoteFtpAuthRequest(string lid, string method, softlist<auto> args) {
        # do not lock "rm" here to ensure that requests can be handled in parallel
        return call_object_method_args(frh{lid}.auth, method, args);
    }

    auto doRemoteHttpRequest(string lid, string method, softlist<auto> args) {
        QDBG_LOG("doRemoteHttpRequest() lid: %y type: %y", lid, hh{lid} ? "normal handler" : (uhh{lid} ? "extension handler" : "unknown"));
        # do not lock "rm" here to ensure that requests can be handled in parallel
        return call_object_method_args(hh{lid} ?? uhh{lid}.handler, method, args);
    }

    auto doRemoteHttpAuthRequest(string lid, string method, softlist<auto> args) {
        # do not lock "rm" here to ensure that requests can be handled in parallel
        return call_object_method_args(hh{lid}.auth ?? uhh{lid}.handler.auth, method, args);
    }

    auto doRemoteRestValidatorRequest(string lid, string method, softlist<auto> args) {
        # do not lock "rm" here to ensure that requests can be handled in parallel
        return call_object_method_args(cast<AbstractServiceRestHandler>(hh{lid} ?? uhh{lid}).getValidator(), method,
            args);
    }

    hash<auto> handleRequestExtern(string lid, string socket_key, hash<auto> cx, hash<auto> hdr, *data b) {
        DummyListenerInterface listener();
        RemoteSocket remotesocket(socket_key, cx.socketencoding);
        list<auto> args = (listener, remotesocket, cx, hdr, b);
        # setup call thread context
        tld.cx = cx;
        # do not lock "rm" here to ensure that requests can be handled in parallel
        return {
            # issue #3216: must strip complex types before returning
            "rv": cast<hash>(call_object_method_args(hh{lid} ?? uhh{lid}, "handleRequest", args)),
        };
    }

    hash<auto> authenticateRequestExtern(string lid, hash<auto> hdr, hash<auto> cx) {
        DummyListenerInterface listener();
        *hash<auto> rv = call_object_method_args(hh{lid}.auth ?? uhh{lid}.handler.auth, "authenticateRequest",
            (listener, hdr, \cx));
        return {
            "cx": cx,
            "rv": rv,
        };
    }

    bindHandler(string name, AbstractServiceHttpHandler handler) {
        string lid = handler.getUniqueHash();

        # set to True if the handler is being registered now
        bool new_registration;

        {
            rm.lock();
            on_exit rm.unlock();

            rh{name}{lid} = {
                "handler": handler,
            };

            if (!hh{lid}) {
                new_registration = True;
                hh{lid} = handler;
            }
        }

        try {
            # bind the handler with qorus-core
            Qorus.callCoreFunction("qorus_api_service_bind_handler", type, self.name, lid, name,
                handler.getRemoteConfig());
        } catch (hash<ExceptionInfo> ex) {
            rm.lock();
            on_exit rm.unlock();
            if (new_registration) {
                remove hh{lid};
            }
            remove rh{name}{lid};
            rethrow;
        }
    }

    bindHandler(string name, AbstractHttpRequestHandler handler, string url, *softlist<auto> content_type,
            *softlist<auto> special_headers, bool isregex = True) {
        string lid = getUniqueHashForHandler(handler);

        # set to True if the handler is being registered now
        bool new_registration;

        {
            rm.lock();
            on_exit rm.unlock();

            rh{name}{lid} = {
                "handler": handler,
                "url": url,
                "content_type": content_type,
                "special_headers": special_headers,
                "isregex": isregex,
            };

            if (!hh{lid}) {
                new_registration = True;
                hh{lid} = handler;
            }
        }

        try {
            # bind the handler with qorus-core
            Qorus.callCoreFunction("qorus_api_service_bind_handler", type, self.name, lid, name,
                cast<AbstractServiceHttpHandler>(handler).getRemoteConfig(), url, content_type, special_headers,
                isregex);
        }
        catch (hash<ExceptionInfo> ex) {
            rm.lock();
            on_exit rm.unlock();
            if (new_registration) {
                remove hh{lid};
            }
            remove rh{name}{lid};
            rethrow;
        }
    }

    auto doRemoteSoapAuthRequest(string bind, string method, softlist<auto> args) {
        # do not lock "rm" here to ensure that requests can be handled in parallel
        return call_object_method_args(slrh{bind}.auth, method, args);
    }

    list<string> registerSoapListener(hash<auto> sh, softstring bind, int family = AF_UNSPEC,
            *HttpServer::AbstractAuthenticator auth, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        # remove listener params
        *hash<auto> lh = remove sh{ListenerParams};
        return registerSoapListenersIntern(sh, bind, lh, family, auth, "svc_register_soap_listener", opts);
    }

    list<string> registerSoapListeners(list<auto> sl, softstring bind, *hash<auto> lh, int family = AF_UNSPEC,
            *HttpServer::AbstractAuthenticator auth, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        return registerSoapListenersIntern(sl, bind, lh, family, auth, "svc_register_soap_listeners", opts);
    }

    postLogEvent(LoggerEvent event) {
        Qorus.postLogEvent(event);
    }

    Logger getLogger() {
        return Qorus.getLogger();
    }

    private list<string> registerSoapListenersIntern(softlist<auto> sl, softstring bind, *hash<auto> lh,
            int family = AF_UNSPEC, *HttpServer::AbstractAuthenticator auth, string call,
            hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        # convert any WebService objects to their serialized forms before sending to qorus-core
        foreach auto h in (\sl) {
            if (h.wsdl instanceof WebService) {
                h.wsdl = h.wsdl.serialize();
            }
        }

        {
            rm.lock();
            on_exit rm.unlock();

            if (slrh{bind}) {
                throw "REGISTER-SOAP-LISTENER-ERROR", sprintf("%s service %y has already registered a SOAP handler "
                    "with bind address %y", type, name, bind);
            }

            slrh{bind} = {
                "sl": sl,
                "bind": bind,
                "lh": lh,
                "family": family,
                "auth": auth,
            };
        }

        # get remote auth label
        string rauth = !exists auth ? "none" : (auth instanceof DefaultQorusRBACAuthenticator ? "def" : "remote");

        try {
            return Qorus.callCoreFunction("qorus_api_service_register_soap_listeners", type, name, sl, bind, lh,
                family, rauth, call, opts);
        } catch (hash<ExceptionInfo> ex) {
            rm.lock();
            on_exit rm.unlock();

            remove slrh{bind};
            rethrow;
        }
    }

    registerSoapService(WebService ws, *softlist<string> service, *string uri_path, bool newapi) {
        binary sws = ws.serialize();

        #QDBG_LOG("sws: %y (%y) sws.opts: %y (%y)", sws, sws.fullType(), sws.opts, sws.opts.fullType());

        string key = sprintf("%s-%s-%s-%s", ws.uniqueHash(), service ?? "*", uri_path ?? "*", newapi ? "1" : "0");

        {
            rm.lock();
            on_exit rm.unlock();

            if (srh{key}) {
                throw "REGISTER-SOAP-HANDLER-ERROR", sprintf("WebService %y for %s service %y has already been "
                    "registered", key, type, name);
            }

            srh{key} = {
                "wsdl": sws,
                "service": service,
                "uri_path": uri_path,
                "newapi": newapi,
            };
        }

        try {
            logInfo("registering SOAP service %y with options: %y", ws.getName(), sws - "wsdl");
            Qorus.callCoreFunction("qorus_api_service_register_soap_service", type, name, sws, service, uri_path,
                newapi);
        } catch (hash<ExceptionInfo> ex) {
            rm.lock();
            on_exit rm.unlock();

            remove srh{key};
            rethrow;
        }
    }

    bindFtp(AbstractFtpHandler handler) {
        string lid = handler.getUniqueHash();

        {
            rm.lock();
            on_exit rm.unlock();

            if (frh{lid}) {
                throw "BIND-FTP-ERROR", sprintf("FTP handler %y has already been registered", lid);
            }

            frh{lid} = handler;
        }

        try {
            # bind the handler with qorus-core
            Qorus.callCoreFunction("qorus_api_service_bind_ftp", type, name, lid, handler.getRemoteConfig());
        } catch (hash<ExceptionInfo> ex) {
            rm.lock();
            on_exit rm.unlock();

            remove frh{lid};
            rethrow;
        }
    }

    string createPersistenceObject(hash<auto> cx, *hash ah) {
        code c;
        {
            rm.lock();
            on_exit rm.unlock();

            if (!pf) {
                throw "SERVICE-PERSISTENCE-ERROR", sprintf("%s service %y has not registered a persistence handler",
                    type, name);
            }

            c = pf;
        }

        # acquire the persistence object
        AbstractPersistentDataHelper pdh = c(cx - "sctx", ah);
        pdh.setService(self);

        string lid = pdh.uniqueHash();

        # store the persistence object
        ph{lid} = pdh;

        # return the persistence object ID
        return lid;
    }

    deletePersistenceObject(string lid) {
        remove ph{lid};
    }

    auto doRemotePersistenceRequest(string lid, string method, *list<auto> args) {
        return call_object_method(ph{lid}, method, args);
    }

    persistenceRegister(code factory) {
        {
            rm.lock();
            on_exit rm.unlock();

            if (pf) {
                throw "SERVICE-PERSISTENCE-ERROR", sprintf("%s service %y has already registered a persistence "
                    "handler", type, name);
            }

            pf = factory;
        }

        try {
            Qorus.callCoreFunction("qorus_api_service_persistence_register", type, name);
        } catch (hash<ExceptionInfo> ex) {
            rm.lock();
            on_exit rm.unlock();
            remove pf;
            rethrow;
        }
    }

    persistenceThreadTerminate() {
        Qorus.callCoreFunction("qorus_api_service_persistence_thread_terminated", type, name);
    }

    startThreadTerminated(*string errdesc) {
        try {
            Qorus.callCoreFunction("qorus_api_service_start_thread_terminated", type, name, errdesc);
        } catch (hash<ExceptionInfo> ex) {
            if (qorus_ex_client_dead(ex)) {
                Qorus.logInfo("ignoring error in notification to qorus-core: %s: %s", ex.err, ex.desc);
            } else {
                rethrow;
            }
        }
    }

    logFatal(string msg) {
        Qorus.logArgs(LoggerLevel::FATAL, msg, argv);
    }

    logError(string msg) {
        Qorus.logArgs(LoggerLevel::ERROR, msg, argv);
    }

    logWarn(string msg) {
        Qorus.logArgs(LoggerLevel::WARN, msg, argv);
    }

    logInfo(string msg) {
        Qorus.logArgs(LoggerLevel::INFO, msg, argv);
    }

    logDebug(string msg) {
        Qorus.logArgs(LoggerLevel::DEBUG, msg, argv);
    }

    logTrace(string msg) {
        Qorus.logArgs(LoggerLevel::TRACE, msg, argv);
    }

    logArgs(int lvl, string msg) {
        Qorus.logArgs(lvl, msg, argv);
    }

    stopIntern() {
%ifdef QorusDebugInternals
        # issue #2318: if a signal file exists, then terminate the process here
        if (is_file(string filename = sprintf("%s/%s-%s-%s-%s-%s-stopIntern", tmp_location(),
            Qorus.options.get("instance-key"), type, name, version, serviceid))) {
            QDBG_LOG("ClusterQorusService::stopIntern() SIGNAL FILE %y found; unlinking", filename);
            unlink(filename);
            QDBG_LOG("ClusterQorusService::stopIntern() TERMINATING");
            exit(1);
        }
%endif

        stopWebSocketMonitorThread();

        stopping = True;
        LocalQorusService::stopIntern();
    }

    updateLogger(Logger logger) {
        map cast<AbstractDataProvider>($1.observable).setLogger(logger), event_source_map.iterator();
    }

    private updateMappers(*list<auto> mapper_ids) {
        Qorus.updateMappers(mapper_ids);
    }

    private notifyStartThreadImpl() {
        Qorus.callCoreFunction("qorus_api_service_notify_start_thread", type, name);
    }

    private notifyEndThreadImpl() {
        Qorus.callCoreFunction("qorus_api_service_notify_end_thread", type, name);
    }

    # must be called with the "rm" lock held
    private startWebSocketMonitorThreadIntern() {
        # if we are shutting down the thread, wait for it to shut down before starting it again
        while (ws_quit) {
            ++ws_term_waiting;
            ws_term_cond.wait(rm);
            --ws_term_waiting;
        }
        if (!ws_running) {
            ws_running = True;
            on_error ws_running = False;
            background webSocketMonitorThread();
        }
    }

    private stopWebSocketMonitorThread(*bool check_again) {
        rm.lock();
        on_exit rm.unlock();

        if (ws_running) {
            if (check_again && ws_conn_map) {
                return;
            }
            ws_quit = True;
            ws_cond.signal();
        }

        while (ws_running) {
            ++ws_term_waiting;
            ws_term_cond.wait(rm);
            --ws_term_waiting;
        }
    }

    private webSocketMonitorThread() {
        logInfo("started WebSocket connection monitor thread");
        on_exit {
            logInfo("stopped WebSocket connection monitor thread");
            QDBG_LOG("webSocketMonitorThread() exiting ws_running: %y ws_quit: %y", ws_running, ws_quit);
            ws_running = False;
            ws_quit = False;
            if (ws_term_waiting) {
                rm.lock();
                on_exit rm.unlock();
                ws_term_cond.broadcast();
            }
        }

        while (!ws_quit) {
            try {
                # get data to send to remote clients
                list<hash<auto>> req;

                {
                    rm.lock();
                    on_exit rm.unlock();

                    foreach hash<auto> i in (ws_conn_map.pairIterator()) {
                        foreach hash<auto> ci in (i.value.pairIterator()) {
                            *binary msg = ci.value.pollDataImmediate();
                            if (msg) {
                                req += {
                                    "lid": i.key,
                                    "conn_id": ci.key,
                                    "msg": msg,
                                };
                            }
                        }
                    }
                }

                # send messages
                foreach hash<auto> r in (req) {
                    try {
                        Qorus.callCoreFunctionUnreliable("qorus_api_remote_websocket_method", Qorus.svctype,
                            Qorus.interfaceName, r.lid, r.conn_id, "sendEncoded", r.msg);
                    } catch (hash<ExceptionInfo> ex) {
                        logInfo("failed sending outgoing WebSocket message on %y.%y: %s: %s", r.lid, r.conn_id,
                            ex.err, ex.desc);
                    }
                }
                #QDBG_LOG("ClusterQorusService::webSocketMonitorThread() ws_quit: %y sleeping...", ws_quit);

                # interruptible wait
                QorusSharedApi::waitConditionLock(ws_cond, rm, WebSocketConnectionPollingInterval, \ws_quit);
            } catch (hash<ExceptionInfo> ex) {
                logError("%s", get_exception_string(ex));
            }
        }
    }

    static sendHTTPResponseWithCallback(string socket_key, code scb, softint status_code, string status_desc,
            string http_version, hash<auto> headers, timeout timeout_ms) {
        send_code_hash{socket_key} = scb;
        on_exit remove send_code_hash{socket_key};

        Qorus.callCoreFunction("qorus_api_remote_socket_send_http_response_with_callback", Qorus.svctype,
            Qorus.interfaceName, socket_key, status_code, status_desc, http_version, headers, timeout_ms);
    }

    static readHTTPChunkedBodyWithCallback(string socket_key, code rcb, timeout timeout_ms = -1) {
        recv_code_hash{socket_key} = rcb;
        on_exit remove recv_code_hash{socket_key};

        Qorus.callCoreFunction("qorus_api_remote_socket_recv_http_chunked_body_with_callback", Qorus.svctype,
            Qorus.interfaceName, socket_key, timeout_ms);
    }

    static auto doHttpSendCallback(string code_key) {
        return send_code_hash{code_key}();
    }

    static *string doHttpRecvCallback(string code_key, hash<auto> h) {
        if (h.socketencoding) {
            h.obj = new FakeSocket(remove h.socketencoding);
        }
        recv_code_hash{code_key}(h);
        return h.obj ? h.obj.getEncoding() : NOTHING;
    }

    static string getUniqueHashForHandler(AbstractHttpRequestHandler handler) {
        string base = sprintf("%s;%s;%s;%s;%s;%s",
            handler.className(), handler.auth ? handler.auth.className() : "*", handler.decompress.toString(),
                handler.decompress_to_string.toString(), handler.stream.toString(), handler.timeout_ms);
        QDBG_LOG("ClusterQorusService::getUniqueHashForHandler() %y -> %y", base, base.toSHA512());
        return base.toSHA512();
    }
}
