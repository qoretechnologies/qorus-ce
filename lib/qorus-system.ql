# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

%requires HttpServer
%requires Mime
%requires YamlRpcHandler
%requires XmlRpcHandler
%requires JsonRpcHandler
%requires DebugUtil
%requires DebugHandler

# include system object definitions
%include Classes/AsyncQueueManager.qc
%include Classes/Orders.qc
%include Classes/Control.qc
%include Classes/Workflow.qc
%include Classes/WorkflowInstance.qc
%include Classes/InstanceData.qc
%include Classes/Job.qc
%include Classes/ServerSession.qc
%include Classes/ServiceManager.qc
%include Classes/SegmentManager.qc
%include Classes/WFEntry.qc
%include Classes/SoapHandler.qc
%include Classes/WorkflowQueue.qc
%include Classes/WSDL.qc
%include Classes/QorusOptions.qc
%include Classes/RBAC.qc
%include Classes/SQLInterface.qc
%include Classes/QorusEventManager.qc
%include Classes/MultiPartMessage.qc
%include Classes/SyncEventManager.qc
%include Classes/QorusAPI.qc
%include Classes/QorusSystemAPI.qc
%include Classes/ErrorManager.qc
%include Classes/ThreadLocalData.qc
%include Classes/QorusDebugHandler.qc
%include Classes/QorusParametrizedAuthenticator.qc
%include Classes/SchemaSnapshots.qc

# include system library functions
%include lib/qorus-logger.ql
%include lib/qorus.ql

#! global qorus user schema datasource
our Datasource omquser;

our (
    # global application object
    QorusApp Qorus,

    # system datasource pool
    #DatasourcePool omqp,
    QdspClient omqp,

    # SQLInterface object
    ServerSQLInterface sqlif,

    Orders orders,

    ServiceManager services,

    SegmentManager SM,
);

class FavIconHandler inherits public AbstractHttpRequestHandler {
    private {
        binary d;
        string path;
        string ct;
    }

    constructor(string v_path) {
        if (stat(v_path)) {
            d = ReadOnlyFile::readBinaryFile(v_path);
            path = v_path;
            ct = get_mime_type_from_ext(v_path);
        }
    }

    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr, *data body) {
        if (hdr.method == "OPTIONS") {
            return QorusHttpServer::handleOptions(cx);
        }
        hash<HttpResponseInfo> rv = AbstractHttpRequestHandler::handleRequest(listener, s, cx, hdr, body);
        if (!rv.hdr."Access-Control-Allow-Origin") {
            rv.hdr += QorusHttpServer::getCorsResponseHeaders(cx);
        }
        return rv;
    }

    hash<HttpResponseInfo> handleRequest(hash<auto> cx, hash<auto> hdr, *data body) {
        if (d) {
            return <HttpResponseInfo>{
                "code": 200,
                "body": d,
                "hdr": {"Content-Type": ct},
            };
        }
        return <HttpResponseInfo>{
            "code": 404,
            "body": "no icon available",
        };
    }
}

# internal api: call most non-service system APIs as the current (or other) user
auto sub call_system_api_as_user_tld(string call, softlist args, *string user, *hash call_tld) {
    if (call_tld) {
        ensure_create_tld();
        tld += call_tld;
    }

    return call_system_api_as_user(call, args, user, call_tld ? True : False);
}

# internal api: call most non-service system APIs as the current (or other) user
auto sub call_system_api_as_user(string call, softlist args, *string user, bool useTLDContext) {
    # check for invalid shutdown-wait call - this may not be called internally
    if (call == "omq.system.shutdown-wait")
        throw "INVALID-INTERNAL-API-CALL", "the 'shutdown-wait' function may not be called by internal Qorus code";

    string meth;

    # check for submit-data call
    if (call =~ /^omq\.system\.submit-data\./)
        meth = "omq.system.submit-data.[workflow].[version]";
    else if (call =~ /^omq\.system\.service\./)
        meth = "omq.system.service.[servicename].[method]";
    else if (call =~ /^omq\.user\.service\./)
        meth = "omq.user.service.[servicename].[method]";
    else {
        meth = call;
    }
    if (!Qorus.system_api{meth})
        throw "UNKNOWN-API-CALL", sprintf("%n is not a valid network API entry point (%y: %N)", call, meth, keys Qorus.system_api);

    # setup call context
    hash cx = (useTLDContext ? tld.cx : {}) + ("method": call, "user": user, "internal": True);
    unshift args, cx;
    return call_function_args(Qorus.system_api{meth}.code, args);
}

hash<auto> sub qorus_get_system_info() {
    hash<auto> ah = Qorus.alerts.getHealth();
    TimeZone tz = TimeZone::get();
    return {
        "instance-key"            : Qorus.session.getKey(),
        "session-id"              : Qorus.session.getID(),
        "omq-version"             : OMQ::version,
        "omq-build"               : QorusRevision,
        "omq-version-code"        : OMQ::version_code,
        "qore-version"            : Qore::VersionString,
        "modules"                 : get_module_hash(),
        "datamodel-version"       : OMQ::datamodel,
        "omq-schema"              : Qorus.omq_info.user + "@" + Qorus.omq_info.db,
        "omq-driver"              : Qorus.omq_info.driver,
        "omq-db-version"          : Qorus.omq_info.server_version,
        "omquser-schema"          : Qorus.omquser_info.user + "@" + Qorus.omquser_info.db,
        "omquser-driver"          : Qorus.omquser_info.driver,
        "omquser-db-version"      : Qorus.omquser_info.server_version,
        "starttime"               : Qorus.start_time, #format_date("YYYY-MM-DD HH:mm:SS", start_time),
        "hostname"                : gethostname(),
        "pid"                     : getpid(),
        "threads"                 : num_threads(),
        "schema-properties"       : Qorus.sysprops,
        "omq_dir"                 : ENV.OMQ_DIR,
        "cache_size"              : SM.getWFEntryCacheSize(),
        "shutting_down"           : (exists Qorus.shutting_down && Qorus.shutting_down) ? True : False,
%ifdef QoreDebug
        "build-type"              : "Debug",
%else
        "build-type"              : "Production",
%endif
        "runtime-properties"      : Qorus.getRuntimeProps(),
        "alert-summary"           : ah - "health",
        "debug"                   : Qorus.getDebugSystem(),
        "debug-internals"         : Qorus.getDebugSystemInternals(),
        "health"                  : ah.health,
        "ui-compatibility-version": OMQ::ui_compatibility_version,
        "plugins"                 : Qorus.qmm.getRegisteredPlugins(),
        "edition"                 : "Community",
        "tz_region"               : tz.region(),
        "tz_utc_offset"           : tz.UTCOffset(),
    };
}

# internal helper class for consistent auditing and logging from system HTTP handlers
class OMQ::QorusHttpRequestHandler {
    static *string getLogMessage(hash<auto> cx, hash<auto> api, reference<auto> params) {
        # save call context in thread-local data
        ensure_create_tld();
        tld.cx = cx;

        string args;
        *string msg = AbstractHttpRequestHandler::getLogMessage(cx, api, \params, \args);
        if (msg)
            Qorus.audit.apiCall(cx, args);
        return msg;
    }
}

# internal helper class for saving and restoring the thread-local context when calling system APIs
class QorusApiContextHelper {
    public {
        ThreadLocalData tld_save();
    }

    constructor() {
        QDBG_ASSERT(ensure_tld());
        tld_save.tldCopy(tld);
    }

    destructor() {
        QDBG_ASSERT(ensure_tld());
        tld.clear();
        tld.tldCopy(tld_save);
    }
}

string sub get_safe_url(hash<auto> h) {
    return sprintf("%s://%s:%d", h.protocol ? h.protocol : "http", h.host, h.port ? h.port : 80);
}

string sub get_safe_url(string url) {
    return get_safe_url(parse_url(url));
}

*hash<auto> sub get_tld_context() {
    hash<auto> rv = tld{"svc_locks",};
    if (tld.wfe) {
        rv.wf += tld.wfe.("workflow_instanceid", "priority", "started");
        rv.wf += tld.wfe.wf.("name", "version", "workflowid");
        rv.wf.stepid = tld.stepID;
        rv.wf.ind = tld.ind;
        if (tld.index)
            rv.wf.options = Qorus.control.execHash{tld.index}.getAllOptions();
    }
    else if (tld.wf) {
        rv.wf += tld.wf{"name", "version", "workflowid"};
    }
    if (tld.svc) {
        rv.svc = tld.svc{"type", "name", "version", "serviceid"};
    }
    if (tld.job) {
        if (tld.job instanceof Job) {
            rv.job = tld.job.getInfo();
        }
        else {
            rv.job = tld.job;
        }
    }
    if (tld.cx) {
        rv.cx = get_cx(tld.cx);
    }
    return rv;
}

sub raise_rbac_alert(string alert, string reason, *hash info) {
    CodeActionReason ar(reason);
    *string provider = remove info.provider;
    if (!provider)
        provider = "unknown";
    Qorus.alerts.raiseTransientAlert(ar, "RBAC", provider, alert, info);
}

sub iprintf(string fmt) {
    vprintf(fmt, argv);
    flush();
}

bool sub qkill(int pid, int sig = SIGHUP) {
%ifdef Windows
    any ret = system(sprintf("taskkill %s /PID %d",
                             (sig == SIGKILL ? "/F" : ""),
                             getpid()));
    {
        if (ret == 128)
        {
            # FIXME: 128 is ERROR_WAIT_NO_CHILDREN, but dunno whether this is what we want?
            iprintf("already terminated\n");
            return True;
        }
        iprintf("error %y while sending the signal\n", ret);
        iprintf("%s: aborting system restart\n", strerror());
        # we assume the process is owned by a different user
        exit(QSE_COMMAND_LINE_ERROR);
    }
%else
    if (kill(pid, sig)) {
        if (errno() == ESRCH) {
            iprintf("already terminated\n");
            return True;
        }

        iprintf("%s: aborting system restart\n", strerror());
        # we assume the process is owned by a different user
        exit(QSE_COMMAND_LINE_ERROR);
    }
%endif
    iprintf("signal sent\n");
    return False;
}

bool sub wait_for_termination(int pid, int t0 = 60, string mp = "SYSTEM RESTART") {
    date now = now_us();
    date end = now + seconds(t0);

    # check if PID is alive
    bool timeout = check_pid(pid);

    if (!timeout) {
        iprintf("%s: pid %d has terminated\n", mp, pid);
        return timeout;
    }

    int ds = 0;
    iprintf("%s: waiting %ds for pid %d to terminate: ", mp, t0, pid);
    while (True) {
        date t1 = now_us();
        if (t1 > end) {
            iprintf("\n%s: timeout of %ds exceeded\n", mp, t0);
            break;
        }
        ++ds;
        date dt = (now + seconds(ds)) - t1;
        if (dt < 0)
            continue;
        usleep(dt);
        if (!check_pid(pid)) {
            timeout = False;
            iprintf("\n%s: pid %d terminated\n", mp, pid);
            break;
        }

        iprintf("%d ", t0 - ds + 1);
    }

    return timeout;
}

bool sub check_pid(int pid) {
    # currently we do it the "dumb" way
%ifdef Windows
    string ps = sprintf("tasklist /NH /FI \"PID eq %d\"", pid);
    string str = backquote(ps);
    return str.regex('^[^ ]+[ ]+' + pid.toString() + '[ ]');
%else
    # currently Linux, Darwin, and Solaris all support this syntax
    string ps = sprintf("ps -p%d", pid);
    string str = backquote(ps);
    return str.regex(pid.toString());
%endif
}

# get information about cached object
/** @return hash the whole sql cache; see @ref get_sql_cache_info for output hash format
    It's available in system services to show cache including OMQ db objects
    @see @ref sql-cache

    @since Qorus 3.1.0
**/
hash sub get_sql_cache_info_system() {
    return Qorus.dsmanager.getCacheInfoSystem();
}

# returns a system URL related to the request used to access Qorus
string sub qorus_get_url(hash<auto> cx, string url) {
    # remove options from url
    url =~ s/{.*}//g;

    # get the broken-down representation of the URL
    hash<auto> uh = parse_url(url);
    #printf("uh: %y\n", uh);

    # if we have only "host", then treat it as a path (host is ignored)
    if (!uh.port && !uh.protocol && !uh.username && !uh.password && uh.host) {
        uh.path = uh.host;
    }

    # NOTE: cx.hdr.host is not set on internal calls
    if (!cx.hdr.host) {
        cx.hdr.host = uh.host ?? Qorus.getLocalAddress();
    } else if (cx.hdr.host =~ /^(0.0.0.0|::|\[::\])/) {
        # convert "0.0.0.0", "::", and "[::]" to "localhost"
        cx.hdr.host =~ s/^(0.0.0.0|::|\[::\])/localhost/;
    } else if (cx.hdr.host =~ /^[[:xdigit:]:]+$/) {
        # enclose IPv6 addresses in "[]"
        cx.hdr.host = "[" + cx.hdr.host + "]";
    } else if (cx.hdr.host =~ /\//) {
        # otherwise if the host is a path, then we have a UNIX socket
        cx.hdr.host =~ s/ /%20/g;
        cx.hdr.host =~ s/\//%2f/g;
        cx.hdr.host = "socket=" + cx.hdr.host;
    }

    # remove the port from the host
    if (cx.hdr.host =~ /:[0-9]+/) {
        int port = (cx.hdr.host =~ x/:([0-9]+)/)[0].toInt();
        cx.hdr.host =~ s/:[0-9]+//;
        if (!cx.hdr.port) {
            cx.hdr.port = port;
        }
    }

    # default protocol is "http"
    if (!uh.protocol) {
        uh.protocol = "http";
    }

    # issue #2187: ensure the scheme is formatted correctly
    if (cx.ssl && uh.protocol == "https") {
        uh.protocol = "http";
    }

    # create the URL string without the port and path
    url = sprintf("%s%s://%s", uh.protocol, cx.ssl ? "s" : "", cx.hdr.host);

    # add port if necessary
    if (cx.hdr.port
        && !(cx.hdr.port == 80 && uh.protocol == "http" && !cx.ssl)
        && !(cx.hdr.port == 443 && uh.protocol == "http" && cx.ssl)) {
        url += sprintf(":%d", cx.hdr.port);
    }

    # add path
    if (uh.path) {
        if (uh.path !~ /^\//) {
            url += "/";
        }
        url += uh.path;
    }

    return url;
}

# internal service API implementation
hash<auto> sub qorus_api_svc_get_service_info(*hash<auto> cx) {
    return services.getCurrentServiceInfo(cx);
}

*hash<auto> sub qorus_api_svc_get_service_info_as_current_user(softint id, *hash<auto> cx) {
    # get the type and name of the service
    *hash<auto> sh = Qorus.qmm.lookupService(id, False);
    if (!sh) {
        return;
    }

    *hash<auto> h = services.getServiceInfo(sh.type, sh.name, cx);
    if (!h) {
        return;
    }

    return h;
}

*hash<auto> sub qorus_api_svc_get_service_info_as_current_user(string type, string name, *hash<auto> cx) {
    *hash<auto> h = services.getServiceInfo(type.lwr(), name, cx);
    if (!h) {
        return;
    }

    return h;
}

list<hash<auto>> sub qorus_api_svc_get_running_workflow_list_as_current_user(string name, *string ver) {
    list<hash<auto>> l = Qorus.control.getWorkflowInfoList(name, ver);
    return l;
}

list<auto> sub qorus_api_svc_start_listeners(softstring bind, *string cert_path, *string key_path,
        *string key_password, *string name, int family = AF_UNSPEC) {

    hash<HttpListenerOptionInfo> info();
    if (exists name) {
        info.name = name;
    }
    if (exists family) {
        info.family = family;
    }
    if (exists cert_path) {
        info += http_get_ssl_objects(cert_path, key_path, key_password);
    }
    return Qorus.httpServer.addListeners(bind, info);
}

sub qorus_api_svc_slog(*list args) {
    slog_args(args);
}

*hash<auto> sub qorus_api_svc_try_get_wf_static_data() {
    return SM.tryGetStaticData();
}

*hash<auto> sub qorus_api_svc_try_get_wf_dynamic_data() {
    return SM.tryGetDynamicData();
}

*hash<auto> sub qorus_api_svc_try_get_wf_temp_data() {
    return SM.tryGetTempData();
}

list<string> sub qorus_api_svc_bind_http(OMQ::AbstractServiceHttpHandler handler,
        hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
    return services.bindHttp(handler, opts);
}

sub qorus_api_svc_bind_handler(string name, OMQ::AbstractServiceHttpHandler handler) {
    services.bindHandler(name, handler);
}

sub qorus_api_svc_bind_handler(string name, HttpServer::AbstractHttpRequestHandler handler, string url,
        *softlist<auto> content_type, *softlist<auto> special_headers, bool isregex = True) {
    services.bindHandler(name, handler, url, content_type, special_headers, isregex);
}

sub qorus_api_svc_register_soap_service(WebService ws, *softlist<string> service, *string uri_path, bool newapi) {
    services.registerSoapService(ws, service, uri_path, newapi);
}

sub qorus_api_restarting_service(string type, string name, string process_id) {
    services.restartingService(type, name, process_id);
}

sub qorus_api_service_notify_start_thread(string type, string name) {
    services.getRemoteService(type, name).refThread();
}

sub qorus_api_service_notify_end_thread(string type, string name) {
    services.getRemoteService(type, name).derefThread();
}

sub qorus_api_service_set_thread_count(string type, string name, int threads) {
    services.getRemoteService(type, name).setThreadCount(threads);
}

sub qorus_api_service_bind_ftp(string type, string name, string rid, hash<auto> conf) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    services.bindFtp(new RemoteFtpHandler(svc, rid, conf));
}

list<string> sub qorus_api_service_register_soap_listeners(string type, string name, softlist<auto> sl,
        softstring bind, *hash<auto> lh, int family, string rauth, string call,
        hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
    return services.registerSoapListenersRemote(type, name, sl, bind, lh, family, rauth, call, opts);
}

sub qorus_api_service_register_soap_service(string type, string name, binary sws, *softlist<string> service,
        *string uri_path, bool newapi) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    ensure_create_tld();
    tld.svc = svc;
    WebService ws = Serializable::deserialize(sws);
    if (ws.has_try_import) {
        ws.try_import = \svc.getResourceData();
    }
    services.registerSoapService(ws, service, uri_path, newapi);
}

hash<auto> sub qorus_api_service_get_local_info(string type, string name, *hash<auto> cx) {
    return services.getRemoteService(type, name).getLocalInfo(cx);
}

sub qorus_api_service_register_ui_extension(string type, string name, string rid, hash<auto> remote_config,
        *string url_name) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    ensure_create_tld();
    tld.svc = svc;
    return services.uiExtensionRegister(RemoteExtensionHandler::get(svc, rid, remote_config), url_name);
}

list<auto> sub qorus_api_service_bind_http(string type, string name, string rid, hash<auto> remote_config,
        hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    ensure_create_tld();
    tld.svc = svc;
    return svc.bindHttp(RemoteHttpRequestHandler::get(svc, rid, remote_config), opts);
}

sub qorus_api_service_bind_handler(string type, string name, string rid, string rname, hash<auto> remote_config) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    ensure_create_tld();
    tld.svc = svc;
    svc.bindHandler(rname, new RemoteHttpRequestHandler(svc, rid, remote_config));
}

sub qorus_api_service_bind_handler(string type, string name, string rid, string rname, hash<auto> remote_config,
        string url, *softlist<auto> content_type, *softlist<auto> special_headers, bool isregex = True) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    ensure_create_tld();
    tld.svc = svc;
    svc.bindHandler(rname, new RemoteHttpRequestHandler(svc, rid, remote_config), url, content_type, special_headers,
        isregex);
}

sub qorus_api_service_persistence_thread_terminated(string type, string name) {
    services.getRemoteService(type, name).persistenceThreadTerminate();
}

sub qorus_api_service_start_thread_terminated(string type, string name, *string errdesc) {
    services.startThreadTerminated(services.getRemoteService(type, name), errdesc);
}

sub qorus_api_service_persistence_register(string type, string name) {
    services.getRemoteService(type, name).persistenceRegister();
}

auto sub qorus_api_remote_websocket_method(string type, string name, string rid, string conn_id, string method) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    return RemoteServiceWebSocketHandler::callLocalConnMethodArgs(rid, conn_id, method, argv);
}

auto sub qorus_api_remote_socket_send_http_response_with_callback(string type, string name, string key,
        softint status_code, string status_desc, string http_version, hash headers, timeout timeout_ms) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    code my_scb = auto sub () {
        return svc.doHttpSendCallback(key);
    };
    return RemoteServiceRestHandler::doSocketOperation(key, "sendHTTPResponseWithCallback", (my_scb, status_code,
        status_desc, http_version, headers, timeout_ms));
}

sub qorus_api_remote_socket_recv_http_chunked_body_with_callback(string type, string name, string key,
        timeout timeout_ms) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    code my_rcb = sub (hash<auto> h) {
        *Socket s = remove h.obj;
        if (s) {
            h.socketencoding = s.getEncoding();
        }
        *string enc = svc.doHttpRecvCallback(key, h);
        if (enc) {
            s.setEncoding(enc);
        }
    };
    RemoteServiceRestHandler::doSocketOperation(key, "readHTTPChunkedBodyWithCallback", (my_rcb, timeout_ms));
}

auto sub qorus_api_remote_socket_operation(string key, string m) {
    return RemoteServiceRestHandler::doSocketOperation(key, m, argv);
}

sub qorus_api_ref_service(AbstractQorusService svc) {
    cast<AbstractQorusCoreService>(svc).ref();
}

sub qorus_api_ref_service(string type, string name) {
    services.getRemoteServiceRef(type, name);
}

sub qorus_api_deref_service(AbstractQorusService svc) {
    services.derefService(cast<AbstractQorusCoreService>(svc));
}

sub qorus_api_deref_service(string type, string name) {
    services.derefService(services.getRemoteService(type, name));
}

sub qorus_api_service_recovered(string type, string name) {
    services.getRemoteService(type, name).serviceRecovered();
}

sub qorus_api_service_stream_register(string type, string name, string stream, softlist<string> methods,
        string desc) {
    RemoteQorusService svc = services.getRemoteServiceRef(type, name);
    on_exit svc.deref();
    svc.remoteStreamRegister(stream, methods, desc);
}

int sub qorus_api_get_session_id() {
    return Qorus.getSessionId();
}
