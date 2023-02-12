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

class OMQ::RemoteQorusService inherits OMQ::AbstractQorusCoreService {
    private:internal {
        hash<ClusterProcInfo> qsvcp;

        #! Main service client
        QsvcClient svcc;

        #! Service client lock
        Mutex client_lock;

        #! Active threads
        int threads = 0;

        ServiceResources resources();
        bool hasinit;
        bool hasstart;
        # aborted flag
        bool aborted_flag = False;

        date loaded = now_us();

        # to track remote stream request objects
        hash<string, RemoteRestStreamRequestHandler> rrsh;

        # stop reason
        ActionReason stopreason;

        # log prefix for log messages in qorus-core for the service
        string log_pfx;

        # restart count
        int restart_count = 0;
    }

    constructor(Counter sc, string type, string name, *string uuid, *hash<auto> cx, *string reason)
            : AbstractQorusCoreService(sc, type, name, cx, reason) {
    }

    destructor() {
        *hash<ClusterProcInfo> qsvcp = remove self.qsvcp;
        if (qsvcp) {
            stopProcessIntern(qsvcp);
        }
    }

    bool setupImpl(hash<auto> sq, *int po, *bool qorus_core_recover, *string uuid) {
        config = sq.config;

        # setup log prefix
        log_pfx = sprintf("%s service %s v%s (%d): ", type, name, version, serviceid);

        # setup local method hash
        map methods{$1.name} = {
            "lock"      : $1.locktype,
            "desc"      : $1.description,
            "internal"  : $1.internal,
            "write"     : $1.write,
            "id"        : $1.service_methodid,
        }, Qorus.qmm.lookupService(sq.serviceid).methods.iterator();

        hasinit = exists methods.init;
        hasstart = exists methods.start;
        if (hasstart) {
            ++threads;
        }

        resources.setLog(\logInfo());
        resources.setup(serviceid, sq.resources, sys, po);

        # setup basic info
        if (sq.parse_options) {
            parse_options = sq.parse_options.split(",");
            trim parse_options;
        }

        # if the process is already running, then this will not start it again
        # but rather just set up the process client object
        bool started_now;
        started_now = startProcess();

        bool qsvc_aborted = False;
        if (!qorus_core_recover && !uuid) {
            # issue #2706: when qorus-core is restarted, a service may also be restarted, so initialization from qorus-core
            # should not be done in that case; only execute doRemoteSetup() if "started_now" is True
            if (started_now) {
                try {
                    # setup remote service; must be allowed to fail
                    # issue #3786: allow calls from the remote service -> qorus-core to run in the exclusive lock
                    doUnreliableCommandArgs("doRemoteSetup", (sq, startreason.getText()), {
                        "external_locks": tld.external_locks,
                    });
                } catch (hash<ExceptionInfo> ex) {
                    QDBG_LOG("RemoteQorusService::setupImpl() doRemoteSetup() error: %s: %s", ex.err, ex.desc);
                    if (ex.err != "CLIENT-ABORTED" && ex.err != "CLIENT-TERMINATED" && ex.err != "CLIENT-DEAD") {
                        rethrow;
                    }
                    # ignore the error if the qsvc terminates prematurely on start; it will be restarted by qorus-master
                    # if it cannot be restarted; then qorus-master will send a message to qorus-core, and
                    # the service will be removed
                    # the doRemoteSetup() method call cannot be repeated, as after the qsvc process terminates
                    # prematurely, it will reinitialize itself in any case
                    qsvc_aborted = True;
                }
            }
            subscribeToLogIfNeeded();
        }

        return qsvc_aborted;
    }

    *Program getProgram() {
    }

    refThread() {
        ++threads;
        ref();
    }

    bool derefThread() {
        --threads;
        return deref();
    }

    #! Returns a client for a request
    /**
    */
    QsvcClient getClient() {
        return svcc;
    }

    /**
        only called when a stateful service has been restarted

        NOTE: cannot block
    */
    disableResourcesForRestart() {
        rm.lock();
        on_exit rm.unlock();

        foreach hash<auto> i in (rsc.pairIterator()) {
            logInfo("disabling resource %y: %s", i.key, i.value.getType());
            try {
                if (i.value.disable()) {
                    remove rsc{i.key};
                }
            } catch (hash<ExceptionInfo> ex) {
                string desc = sprintf("WARNING! exception disabling resource %y: %s for service %s.%s; could lead to a "
                    "deadlock: %s: %s: %s", i.key, i.value.getType(), type, name, get_ex_pos(ex), ex.err, ex.desc);
                logFatal(desc);
                logFatal(Util::get_exception_string(ex));
                # post error event in the background
                background Qorus.events.postServiceError(tld.cx, ES_Major, type, name, version, serviceid, "STOP-ERROR", desc);
            }
        }
    }

    serviceRecovered() {
        ++restart_count;
        aborted_flag = False;
    }

    setAborted() {
        aborted_flag = True;
    }

    bool isAborted() {
        return aborted_flag;
    }

    int getRestartCount() {
        return restart_count;
    }

    bool aborted(*bool stop) {
        threads = hasstart ? 1 : 0;
        return AbstractQorusCoreService::aborted(stop);
    }

    # called when the qsvc process died and was not restarted
    # returns True if the service is already stopping / has already aborted; False if not
    bool processAborted() {
        if (!qsvcp) {
            Qorus.logInfo("%s service %s v%s (%d) already marked aborted; skipping recovery",
                type, name, version, serviceid);
            return True;
        }
        remove qsvcp;
        return aborted(True);
    }

    init(*bool qorus_core_recover) {
        try {
            AbstractQorusCoreService::init(qorus_core_recover);
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("%s service %s v%s (%d) aborted in init() method; removing process info", type, name, version, serviceid);
            if (ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED" || ex.err == "CLIENT-DEAD") {
                remove qsvcp;
            }
            rethrow;
        }
        # issue #3371: do not set independence on processes already running
        if (!qorus_core_recover) {
            # allow the service to run independently of qorus-core
            Qorus.runIndependent(qsvcp);
        }
    }

    persistenceRegister() {
        persistenceRegister(AbstractPersistentDataHelper sub (hash<auto> cx, *hash<auto> ah) {
            string rid = doCommandArgs("createPersistenceObject", (get_cx(cx), ah));
            return new RemotePersistentDataHelper(rid, cx, ah);
        });
    }

    deletePersistenceObject(string rid) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        doUnreliableCommandArgs("deletePersistenceObject", rid);
    }

    auto doRemotePersistenceRequest(string rid, string method, *list<auto> args) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doRemotePersistenceRequest", (rid, method, args));
    }

    auto doRemoteHttpRequest(string rid, string method, softlist<auto> args) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doRemoteHttpRequest", (rid, method, args));
    }

    auto doRemoteHttpAuthRequest(string rid, string method, softlist<auto> args) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doRemoteHttpAuthRequest", (rid, method, args));
    }

    auto doRemoteSoapAuthRequest(string bind, string method, softlist<auto> args) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doRemoteSoapAuthRequest", (bind, method, args));
    }

    auto doRemoteFtpRequest(string rid, string method, softlist<auto> args) {
        # issue #2349: allow transient FTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doRemoteFtpRequest", (rid, method, args));
    }

    auto doRemoteFtpAuthRequest(string rid, string method, softlist<auto> args) {
        # issue #2349: allow transient FTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doRemoteFtpAuthRequest", (rid, method, args));
    }

    hash<auto> getRemoteServiceStream(string rid, hash<auto> cx, hash<auto> hdr, *data body) {
        return doUnreliableCommandArgs("getRemoteServiceStream", (rid, cx, hdr, body));
    }

    auto doRemoteStreamRequest(string ssid, string method, softlist<auto> args) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doRemoteStreamRequest", (ssid, method, args));
    }

    auto doRemoteRestValidatorRequest(string rid, string method, softlist<auto> args) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doRemoteRestValidatorRequest", (rid, method, args));
    }

    hash<HttpResponseInfo> handleRequestExtern(string rid, string socket_key, hash<auto> cx, hash<auto> hdr, *data b) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        # issue #3253: set thread context on call
        hash<auto> my_tld = tld{"stepID", "ind", "index",} + {
            "wf": tld.wf.typeCode() == NT_OBJECT ? tld.wf.getContextInfo() : tld.wf,
            "wfe": tld.wfe.typeCode() == NT_OBJECT ? tld.wfe.getContextInfo() : tld.wfe,
            "job": tld.job.typeCode() == NT_OBJECT ? tld.wf.getInfo() : tld.job,
        };
        hash<auto> h = doUnreliableCommandArgs("handleRequestExtern", (rid, socket_key, cx, hdr, b), my_tld);
        return cast<hash<HttpResponseInfo>>(h.rv);
    }

    hash<auto> authenticateRequestExtern(string rid, hash<auto> hdr, hash<auto> cx) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("authenticateRequestExtern", (rid, hdr, cx));
    }

    auto doHttpSendCallback(string code_key) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doHttpSendCallback", code_key);
    }

    *string doHttpRecvCallback(string code_key, hash<auto> h) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("doHttpRecvCallback", (code_key, h));
    }

    streamDeleted(string ssid) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        doUnreliableCommandArgs("streamDeleted", ssid);
    }

    remoteStreamRegister(string stream, softlist<string> methods, string desc) {
        streamRegister(stream, methods, getRemoteStreamFactory(stream), desc);
    }

    callPersistentClosedNotification(string id) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        doUnreliableCommandArgs("callPersistentClosedNotification", id);
    }

    bool getRestStreamPersistentClosedNotification(string id) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("getRestStreamPersistentClosedNotification", id);
    }

    auto remoteRestStreamMethodCall(string id, string method) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("remoteRestStreamMethodCallArgs", (id, method, argv), {"cx": get_cx(tld.cx)});
    }

    auto remoteRestStreamMethodCallArgs(string id, string method, *softlist<auto> args) {
        # issue #2349: allow transient HTTP requests to fail; they cannot be recovered in any case as
        # they depend on the state lost when the qsvc process dies
        return doUnreliableCommandArgs("remoteRestStreamMethodCallArgs", (id, method, args), {"cx": get_cx(tld.cx)});
    }

    postLogEvent(LoggerEvent event) {
        # do not use reliazble messaging with log events as it would be confusing in the target log
        doUnreliableCommandArgs("postLogEvent", event);
    }

    registerRemoteStream(RemoteRestStreamRequestHandler stream) {
        # create remote stream object
        *string enc = doCommandArgs("createRemoteStream", (stream.getId(), stream.getStream(), stream.getContext(), stream.getRequestArgs()));
        if (enc) {
            stream.updateEncoding(enc);
        }

        rm.lock();
        on_exit rm.unlock();

        rrsh{stream.getId()} = stream;
    }

    deregisterRemoteStream(RemoteRestStreamRequestHandler stream) {
        # create remote stream object
        doCommandArgs("deleteRemoteStream", stream.getId());
    }

    # if log streaming is requested, subscribe to it
    subscribeToLogIfNeeded() {
        if (Qorus.eventLog.isServiceLogRequested(serviceid)) {
            subscribeToLog();
        }
    }

    # subscribes to the service's log if not subscribed yet
    subscribeToLog() {
        QsvcClient svcc = getClient();
        svcc.sendCheckResponse(CPC_CORE_LOG_SUBSCRIBE, NOTHING, CPC_OK);
    }

    # unsubscribes from the service's log if subscribed
    unsubscribeFromLog() {
        QsvcClient svcc = getClient();
        svcc.sendCheckResponse(CPC_CORE_LOG_UNSUBSCRIBE, NOTHING, CPC_OK);
    }

    registerWsConnection(string rid, string conn_id, hash<auto> cx, hash<auto> hdr, string cid) {
        doUnreliableCommandArgs("registerWsConnection", (rid, conn_id, get_cx(cx), hdr, cid));
    }

    deregisterWsConnection(string rid, string conn_id) {
        doUnreliableCommandArgs("deregisterWsConnection", (rid, conn_id));
    }

    auto callWsConnectionMethodArgs(string rid, string conn_id, string method, *softlist<auto> args) {
        return doUnreliableCommandArgs("callWsConnectionMethodArgs", (rid, conn_id, method, args));
    }

    private code getRemoteStreamFactory(string stream) {
        # create local stream object bound to remote
        return AbstractRestStreamRequestHandler sub (hash<auto> cx, *hash<auto> ah) {
            return new RemoteRestStreamRequestHandler(self, stream, cx.hdr.method, cx, ah);
        };
    }

    bool hasInit() {
        return hasinit;
    }

    bool hasStart() {
        return hasstart;
    }

    hash<auto> getInfoImpl(*hash<auto> cx) {
        QDBG_LOG("RemoteQorusService::getInfoImpl() %s %s v%s (%d): cx: %y", type, name, version, serviceid, (map {$1.key: $1.value.fullType()}, cx.pairIterator()));
        # only return processes for registered clients
        *list<hash<auto>> processes;
        *hash<auto> proc = Qorus.qmm.getServiceProcess(serviceid);
        if (proc) {
            processes = (proc,);
        }
        return {
            "parse_options": parse_options,
            "status": threads ? OMQ::SSRunning : OMQ::SSLoaded,
            "threads": threads,
            "loaded": loaded,
            "options": Qorus.qmm.lookupService(serviceid, False).options,
            "resource_files": resources.getResourceHashList(),
            "processes": processes,
        };
    }

    hash<auto> getResource(string n, hash<auto> ctx, int code = 200, *hash<auto> hdr) {
        return resources.getResource(n, ctx, code, hdr);
    }

    *hash<auto> tryGetResource(string n, hash<auto> ctx, int code = 200, *hash<auto> hdr) {
        return resources.tryGetResource(n, ctx, code, hdr);
    }

    data getResourceData(string n, *hash<auto> ctx) {
        return resources.getResourceData(n, ctx);
    }

    WebService getResourceWsdl(string n, *hash<auto> ctx) {
        return resources.getResourceWsdl(n, ctx);
    }

    *data tryGetResourceData(string n, *hash<auto> ctx) {
        return resources.tryGetResourceData(n, ctx);
    }

    *hash<auto> getResourceHash() {
        return resources.getResourceHash();
    }

    list<string> getResourceList() {
        return resources.getResourceList();
    }

    list<hash<auto>> getResourceHashList() {
        return resources.getResourceHashList();
    }

    bool hasResource(string n) {
        return resources.hasResource(n);
    }

    checkDefaultResource(string name) {
        resources.checkDefaultResource(name);
    }

    hash<auto> renderTemplate(string n, *hash<auto> ctx) {
        return resources.renderTemplate(n, ctx);
    }

    *hash<auto> tryRenderTemplate(string n, hash<auto> cx) {
        return resources.tryRenderTemplate(n, cx);
    }

    *hash<auto> getTemplateHash() {
        return resources.getTemplateHash();
    }

    list<auto> getTemplateList() {
        return resources.getTemplateList();
    }

    bool hasTemplate(string n) {
        return resources.hasTemplate(n);
    }

    #! if no stop reason is already set; then a stop reason is set due to the process having aborted
    synchronized setAbortedStopReason() {
        if (!stopreason) {
            string desc = "service process aborted for remote";
            desc += sprintf(" %s service %s v%s (%d); unloading service", type, name, version, serviceid);
            stopreason = new ActionReason(NOTHING, desc);
        }
    }

    synchronized ActionReason getStopReason() {
        if (!stopreason) {
            try {
                stopreason = doUnreliableCommandArgs("getStopReason");
            } catch (hash<ExceptionInfo> ex) {
                # ignore errors for terminated processes; in this case the abort message will clear all references
                if (ex.err == "CLIENT-DEAD" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED") {
                    string err = sprintf("%s service %s v%s (%d) terminated unexpectedly while stopping: %s: %s",
                        type, name, version, serviceid, ex.err, ex.desc);
                    Qorus.logInfo("%s", err);
                    stopreason = new ActionReason(tld.cx, err);
                } else {
                    rethrow;
                }
            }
        }
        return stopreason;
    }

    stopIntern() {
        if (!qsvcp) {
            return;
        }
        # issue #2677: do not restart a service that dies or is killed while being stopped
        Qorus.ignoreProcessAbort(qsvcp);

        try {
            doUnreliableCommandArgs("stopIntern");
        } catch (hash<ExceptionInfo> ex) {
            # ignore errors for terminated processes; in this case the abort message will clear all references
            if (ex.err == "CLIENT-DEAD" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-TERMINATED") {
                Qorus.logInfo("%s service %s v%s (%d) terminated unexpectedly while stopping: %s: %s", type, name,
                    version, serviceid, ex.err, ex.desc);
            } else {
                rethrow;
            }
        }
    }

    bool getStopping() {
        return doUnreliableCommandArgs("getStopping");
    }

    setStopReason(string desc) {
        doUnreliableCommandArgs("setStopReason", desc);
    }

    setStopReason(*hash<auto> cx, *string reason, bool override_reason = False) {
        list<auto> args = (get_cx(cx), reason, override_reason);
        doUnreliableCommandArgs("setStopReason", args);
    }

    setLocalStopReason(hash<ExceptionInfo> ex, string reason_fmt) {
        stopreason = new ActionReason(NOTHING, ex, vsprintf(reason_fmt, argv));
    }

    bool startServiceConditional(*bool qorus_core_recover) {
        if (qorus_core_recover) {
            # do not start the service thread again
            return hasstart;
        }

        return doCommandArgs("startServiceConditional");
    }

    setOptions(hash<auto> h) {
        doCommandArgs("setOptions", h);
    }

    hash<auto> getAllOptions() {
        return doCommandArgs("getAllOptions");
    }

    auto getOption(string field) {
        return doCommandArgs("getOption", field);
    }

    auto getOption(auto field) {
        return doCommandArgs("getOption", field);
    }

    setThreadCount(int threads) {
        self.threads = threads;
    }

    private auto callMethodImpl(string method, auto args, *binary serialized_args, *hash<auto> cx, *bool serialized, *QorusProgram ix_pgm) {
        # issue #2318: allow the method call to fail if the service dies; do not repeat the call without raising an error
        hash<auto> h = {
            "subsystem": "svc",
            "method": "callMethodImpl",
            "args": (method, args, serialized_args),
            "tld": get_tld_context() + (cx ? {"cx": get_cx(cx)} : NOTHING),
        };
        QsvcClient svcc = getClient();
        *list<string> msgs;
        while (True) {
            msgs = svcc.sendCheckResponseUnreliable(CPC_QSVC_CALL_SUBSYSTEM, h, CPC_OK);
            break;
        }
        # issue #3537: always ensure that response messages are deserialized in the context of the calling Program,
        # if any
        return serialized
            ? msgs[0]
            : (msgs[0].val()
                ? (ix_pgm ? ix_pgm.callFunction("_qorus_deserialize", msgs[0]) : Serializable::deserialize(msgs[0]))
                : NOTHING);
    }

    private auto doCommand(string method) {
        return doCommandArgs(method, argv);
    }

    private auto doCommandArgs(string method, *softlist<auto> args, *hash<auto> my_tld) {
        hash<auto> h = {
            "subsystem": "svc",
            "method": method,
            "args": args,
            "tld": my_tld,
        };
        QsvcClient svcc = getClient();
        *list<string> msgs;
        msgs = svcc.sendCheckResponse(CPC_QSVC_CALL_SUBSYSTEM, h, CPC_OK);

        # issue #3537: always ensure that response messages are deserialized in the context of the calling Program,
        # if any
        return msgs[0].val() ? _priv_deserialize_with_interface_pgm(msgs[0]) : NOTHING;
    }

    # send a command to the server and allow it to fail if the server dies
    private auto doUnreliableCommand(string method) {
        return doUnreliableCommandArgs(method, argv);
    }

    # send a command to the server and allow it to fail if the server dies
    private auto doUnreliableCommandArgs(string method, *softlist<auto> args, *hash<auto> my_tld) {
        hash<auto> h = {
            "subsystem": "svc",
            "method": method,
            "args": args,
            "tld": my_tld,
        };
        QsvcClient svcc = getClient();
        *list<string> msgs = svcc.sendCheckResponseUnreliable(CPC_QSVC_CALL_SUBSYSTEM, h, CPC_OK);
        # issue #3537: always ensure that response messages are deserialized in the context of the calling Program,
        # if any
        return msgs[0].val() ? _priv_deserialize_with_interface_pgm(msgs[0]) : NOTHING;
    }

    private stopProcess() {
        # the process may have already been aborted
        *hash<ClusterProcInfo> qsvcp = remove self.qsvcp;
        if (!qsvcp) {
            QDBG_LOG("qsvc process %s %s v%s (%d) already stopped", type, name, version, serviceid);
            return;
        }
        getStopReason();
        stopProcessIntern(qsvcp);
    }

    # returns True if the process was started now, False if the process was already running
    private:internal bool startProcess() {
        # start qsvc process
        QDBG_LOG("starting qsvc process %s %s v%s (%d)", type, name, version, serviceid);
        # start cluster process
        hash<auto> start_info = Qorus.startServiceProcess(self);
        qsvcp = start_info.info;
        svcc = new QsvcClient(Qorus, type, name, version, serviceid, SL_STATEFUL);
        QDBG_LOG("started qsvc process %s %s v%s (%d)", type, name, version, serviceid);
        return !start_info.already_started;
    }

    private:internal stopProcessIntern(*hash<ClusterProcInfo> qsvcp) {
        if (!qsvcp) {
            QDBG_LOG("qsvc process %s %s v%s (%d) already stopped", type, name, version, serviceid);
            return;
        }
        QDBG_LOG("stopping qsvc process %s %s v%s (%d)", type, name, version, serviceid);
        QDBG_ASSERT(qsvcp);
        # issue #2564: always delete clients before stopping the process
        delete svcc;
        # must stop service synchronously or there can be a race condition with service terminations
        # and restarts if performed in the background
        Qorus.stopProcess(qsvcp);
        QDBG_LOG("stopped");
    }

    logFatal(string msg) {
        Qorus.logFatal(vsprintf(log_pfx + msg, argv));
    }

    logError(string msg) {
        Qorus.logError(vsprintf(log_pfx + msg, argv));
    }

    logWarn(string msg) {
        Qorus.logWarn(vsprintf(log_pfx + msg, argv));
    }

    logInfo(string msg) {
        Qorus.logInfo(vsprintf(log_pfx + msg, argv));
    }

    logDebug(string msg) {
        Qorus.logDebug(vsprintf(log_pfx + msg, argv));
    }

    logTrace(string msg) {
        Qorus.logTrace(vsprintf(log_pfx + msg, argv));
    }

    # send request to remote process to update logger
    updateLoggerImpl(*hash<LoggerParams> params) {
        hash<auto> h = {
            "method": "updateLogger",
            "args": params,
        };
        svcc ? svcc.sendCheckResponse(CPC_INTERFACE_CALL_METHOD, h, CPC_OK) : NOTHING;
    }

    # send request to remote process to rotate log files
    rotateLogFiles() {
        hash<auto> h = {
            "method": "rotateLogFiles",
        };
        svcc ? svcc.sendCheckResponse(CPC_INTERFACE_CALL_METHOD, h, CPC_OK) : NOTHING;
    }
}
