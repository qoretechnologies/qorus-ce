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

hashdecl ServiceStreamInfo {
    code factory;
    hash<string, bool> methods;
}

class OMQ::AbstractQorusCoreService inherits AbstractQorusService {
    public {
        # service start audit event id
        *int a_start;

        # flag entry as starting so it can't be deleted during initialization
        int starting = gettid();

        # service start reason
        ActionReason startreason();

        # hash of AbstractServiceResource objects
        hash<string, AbstractServiceResource> rsc;
    }

    private {
        # persistence object factory
        *code pf;

        # stream handler service hash; access protected with "rm"
        hash<string, hash<ServiceStreamInfo>> shh;

        # resource mutex
        Mutex rm();
    }

    private:internal {
        # the service's RWLock for method calls
        RWLock rwlock();

        # resource sequence
        Sequence rs(1);

        # handler sequence
        Sequence hseq(1);

        # init flag
        bool init;

        # init done flag
        bool initdone = False;

        # the TID of the thread that initiated the service unload operation
        int stopping = 0;

        # issue #2398: service stopped flag; after this is set, no calls can be made
        bool stopped = False;

        # call reference counter
        int refs = 0;

        # issue #2734: setup done flag
        bool setup_done = False;

%ifdef QorusDebugInternals
        # hash of reference reasons; TID -> reason info
        hash<string, auto> ref_debug_hash;
%endif
        int waiting = 0;
        Condition statcond();
        Mutex m();

        # service counter
        Counter sc;
    }

    constructor(Counter sc, string type, string name, *hash<auto> cx, *string reason)
            : AbstractQorusService(type, name) {
        startreason.set(cx, reason);
        self.sc = sc;
        sc.inc();
    }

    destructor() {
        on_exit sc.dec();

        {
            m.lock();
            on_exit m.unlock();
            if (waiting) {
                statcond.broadcast();
            }
        }

        if (init) {
            # issue #3373: handle qsvc terminations
            ActionReason stopreason;
            try {
                stopreason = getStopReason();
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "CLIENT-TERMINATED" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-DEAD") {
                    stopreason = new ActionReason(NOTHING, ex, "remote service terminated before external stop "
                        "reason could be retrieved");
                } else {
                    stopreason = new ActionReason(NOTHING, ex, "could not retrieve external stop reason");
                }
            }
            Qorus.audit.serviceStop(a_start, serviceid, NOTHING, NOTHING, stopreason.getReason(), stopreason.getWho(),
                stopreason.getSource());
            Qorus.events.postServiceStop(tld.cx, type, name, version, serviceid);
        }
    }

    Counter getUnloadCounter() {
        return sc;
    }

    init(*bool qorus_core_recover) {
        a_start = Qorus.audit.serviceStart(serviceid, NOTHING, NOTHING, startreason.getReason(), startreason.getWho(),
            startreason.getSource());
        init = True;
        if (hasInit() && !qorus_core_recover) {
            # allow read-only calls to be made while starting the service
            services.releaseServiceToReadOnly(type, name);
            on_exit services.reacquireServiceExclusive(type, name);

            # issue #3373: if the service dies in the init method, then set the stop reason immediately
            try {
                callMethod("init");
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "CLIENT-TERMINATED" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-DEAD") {
                    setLocalStopReason(ex, "remote service terminated in init()");
                } else {
                    setLocalStopReason(ex, "exception in init()");
                }
                rethrow;
            }
        }
        initdone = True;
    }

    # called when the external qsvc process has aborted
    # this method must be in AbstractQorusCoreService, because it accesses private:internal members
    # returns True if the service is already stopping; False if not
    bool aborted(*bool stop) {
        QDBG_LOG("%s service %s v%s (%d) aborted; stopping: %y", type, name, version, serviceid, stopping);
        m.lock();
        on_exit m.unlock();

        refs = 0;
%ifdef QorusDebugInternals
        remove ref_debug_hash;
%endif
        if (waiting) {
            statcond.broadcast();
        }

        if (stop) {
            if (!stopNowIntern()) {
                Qorus.logInfo("aborted %s service %s v%s (%d) is already stopping; delivered internal notification",
                    type, name, version, serviceid);
                return True;
            }
        } else {
            Qorus.logInfo("stopping all resources for aborted %s service %s v%s (%d)", type, name, version,
                serviceid);
            stopAllResources(True);
        }

        return False;
    }

    hash<auto> getDebugInfo() {
        return {
            "refs": refs,
%ifdef QorusDebugInternals
            "ref_debug_hash": ref_debug_hash,
%endif
            "waiting": waiting,
            "stopping": stopping,
        };
    }

%ifdef QorusDebugInternals
    private:internal addReferenceReason(string reason, hash<auto> info) {
        softstring tid = gettid();
        ref_debug_hash{tid} += ({"reason": reason} + info,);
    }

    private:internal removeReferenceReason(softstring tid = gettid()) {
        # cannot assert that this thread holds the reference; remote services won't have the right thread context
        #QDBG_ASSERT(ref_debug_hash{tid}.size());
        pop ref_debug_hash{tid};
        if (!ref_debug_hash{tid}) {
            remove ref_debug_hash{tid};
        }
    }
%endif

    # issue #2734: get setup done flag: do not call getInfo() before set has been done
    bool getSetupDone() {
        return setup_done;
    }

    # issue #2734: set setup done flag: do not call getInfo() before set has been done
    setSetupDone() {
        QDBG_ASSERT(!setup_done);
        setup_done = True;
    }

    # returns true if the service is stopping, false if not
    bool getStopping() {
        return stopping.toBool();
    }

    # the read lock for the service is held during this call
    auto callMethod(string method, auto args, *binary serialized_args, bool ext = False, *hash<auto> cx,
            *bool serialized) {
        #printf("ENTER: %s.%s.%s = %y\n", type, name, method, methods{method});fflush();
        if (!methods{method}) {
            throw "SERVICE-NO-METHOD", sprintf("%s service %s/%s has not registered method %y (available "
                "methods: %y)", type, name, version, method, (foldl $1 + ", " + $2, keys methods));
        }

        if (ext) {
            # if calling an internal-only method exterally, throw exception
            if (methods{method}.internal) {
                throw "INTERNAL-METHOD-ERROR", sprintf("%s method %s.%s() cannot be accessed from external "
                    "interfaces", type, name, method);
            }
        }

        # reference for atomic method call
        {
            # issue #2398: all reference operations must be atomic due to the use of the condition variable
            m.lock();
            on_exit m.unlock();

            if (stopped) {
                # issue #2398: the call will be retried if called when the service is being stopped
                # the exception "arg" value is to mark the system as a system exception
                throw "SERVICE-STOPPED-ERROR", sprintf("service has been stopped by TID %d; please repeat your call "
                    "after the service is reloaded", stopping), self;
            }

            ++refs;
        }
%ifdef QorusDebugInternals
        addReferenceReason("method call", {"method": method, "args": args, "ext": ext, "cx": cx});
%endif
        on_exit # dereference and delete service if necessary when the block exists
            deref();

        #logDebug("type: %y name: %y method: %y args: %y method-intern: %y", type, name, method, args,
        #   methods{method});

        {
            # lock service if necessary
            object al;
            if (methods{method}.lock == OMQ::SLRead) {
                if (!rwlock.lockOwner()) {
                    al = new AutoReadLock(rwlock);
                }
            } else if (methods{method}.lock == OMQ::SLWrite) {
                if (!rwlock.writeLockOwner()) {
                    al = new AutoWriteLock(rwlock);
                }
            }

            # issue #3537: get current interface context for msg deserialization
            *QorusProgram ix_pgm = _priv_try_get_interface_pgm();

            # to save exception info if necessary
            ServiceThreadContextHelper stch(self, method);

            date start = now_us();
            # make sure we use the same end timestamp for all events
            date end;
            int us;
            try {
                on_success {
                    if (Qorus.options.get("service-perf-events")) {
                        Qorus.events.postServiceMethodPerformance(tld.cx, type, name, version, serviceid, method,
                            start, end, False);
                    }
                    # post SLA event if necessary
                    *softint slaid = Qorus.qmm.getSlaForMethod(serviceid, method);
                    if (slaid) {
                        Qorus.qmm.postSlaEventSuccess(slaid, us.toNumber() / 1000000n,
                            CodeActionReason::getSource() ?? "system");
                    }
                }
                on_error {
                    if (Qorus.options.get("service-perf-events")) {
                        Qorus.events.postServiceMethodPerformance(tld.cx, type, name, version, serviceid, method,
                            start, end, True);
                    }
                }
                /* post service performance events
                    this block is executed unconditionally first, so end is initialized before
                    the above blocks are executed
                */
                on_exit {
                    end = now_us();
                    us = get_duration_microseconds(end - start);
                    /*
                    pcmh{methods{method}.id}.post(us);
                    pc.post(us);
                    Qorus.pcsvc.post(us);
                    */
                }

                return callMethodImpl(method, args, serialized_args, cx, serialized, ix_pgm);
            } catch (hash<ExceptionInfo> ex) {
                # post SLA event if necessary
                *softint slaid = Qorus.qmm.getSlaForMethod(serviceid, method);
                if (slaid) {
                    Qorus.qmm.postSlaEventError(slaid, us.toNumber() / 1000000n,
                        CodeActionReason::getSource() ?? "system", ex.err, ex.desc);
                }

                logRethrowException(ex, sprintf("%s()", method), stch);
            }
        }
    }

    hash<auto> getLocalInfo(*hash<auto> cx) {
        hash<auto> rv = {
            "groups": Qorus.rbac.getServiceGroups(serviceid),
            "alerts": Qorus.alerts.getAlerts("SERVICE", serviceid),
        };

        # add resource info
        *hash<string, hash<auto>> rsrc;
        {
            rm.lock();
            on_exit rm.unlock();

            rsrc = map {$1.key: {
                "type": $1.value.getType(),
                "desc": $1.value.getDesc(),
                "info": $1.value.getInfo(cx),
            }}, rsc.pairIterator(), !$1.value.isDisabled();
        }

        return rv + {
            "waiting_threads": waiting,
            "resources": rsrc,
            "active_calls": rv.active_calls + refs,
        };
    }

    hash<auto> getInfo(*hash<auto> cx) {
        return getServiceInfo() + getLocalInfo(cx) + getInfoImpl(cx);
    }

    int getResourceId() {
        return rs.next();
    }

    bool addResource(AbstractServiceResource asr) {
        rm.lock();
        on_exit rm.unlock();

        return addResourceIntern(asr);
    }

    private bool addResourceIntern(AbstractServiceResource asr) {
        string rname = asr.getName();

        if (rsc{rname}) {
            asr.stop();
            throw "SERVICE-ERROR", sprintf("duplicate resource %y added to service %s.%s", rname, type, name);
        }

        rsc{rname} = asr;
        return True;
    }

    removeResource(string rname) {
        AbstractServiceResource asr;

        {
            rm.lock();
            on_exit rm.unlock();

            # DEBUG
            if (!rsc{rname})
                throw "SERVICE-REMOVE-RESOURCE-ERROR", sprintf("service %s.%s does not have resource %y; valid "
                    "resources: %y", type, name, rname, rsc.keys());

            asr = remove rsc{rname};
        }
        stopResource(rname, asr);
    }

    resourceRemovedNotification(string name) {
        if (self) {
            AbstractServiceResource rsc;
            {
                AutoLock al(rm);
                # ignore if already removed
                if (!rsc{name}) {
                    return;
                }
                rsc = remove rsc{name};
            }
            logInfo("resource %y: %s stopped externally", name, rsc.getType());
        }
    }

    persistenceRegister(code factory) {
        rm.lock();
        on_exit rm.unlock();

        if (pf) {
            throw "SERVICE-PERSISTENCE-ERROR", sprintf("%s service %y has already registered a persistence handler",
                type, name);
        }

        pf = factory;
    }

    persistenceThreadTerminate() {
        *HttpListenerInterface l = remove_thread_data("svc_listener").svc_listener;
        if (!l) {
            throw "SERVICE-PERSISTENCE-ERROR", "the current thread is not in a persistent connection";
        }
        AbstractPersistentDataHelper data = l.removeUserThreadContext("persistent_data");
        delete data;
    }

    bool checkServiceResource(string rname) {
        return exists rsc{rname};
    }

%ifdef QorusDebugInternals
    *list<string> getServiceResourceNames() {
        return keys rsc;
    }
%endif

    private AbstractPersistentDataHelper getPersistenceObject(hash<auto> cx, *hash<auto> ah) {
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
        # return the persistence object
        return pdh;
    }

    streamRegister(string stream, softlist<string> methods, code factory, string desc) {
        # ensure HTTP methods names are all upper case
        methods = map $1.upr(), methods;

        rm.lock();
        on_exit rm.unlock();

        if (shh{stream}) {
            throw "STREAMHANDLER-ERROR", sprintf("stream handler %y for %s service %y has already been registered",
                stream, type, name);
        }

        shh{stream} = <ServiceStreamInfo>{
            "methods": (map {$1: True}, methods),
            "factory": factory,
        };
        addResourceIntern(new QorusStreamHandlerResource(stream, methods, desc));
    }

    AbstractRestStreamRequestHandler getStreamHandler(string name, hash<auto> cx, *hash<auto> ah) {
        ensure_create_tld();
        code c;
        {
            rm.lock();
            on_exit rm.unlock();

            if (!shh{name}) {
                throw "STREAMHANDLER-ERROR", sprintf("no stream handler %y for %s service %y has been registered; "
                    "known stream handlers: %y", name, type, self.name, keys shh);
            }

            if (!shh{name}.methods{cx.hdr.method}) {
                return new ErrorStreamHandler(cx, ah, 405, "HTTP method %y is not valid for %s service %y stream %y; "
                    "use %y instead", cx.hdr.method, type, self.name, name, keys shh{name}.methods);
            }
            c = shh{name}.factory;
        }

        tld += {
            "svc": self,
            "_current_ix": "svc",
        };
        # do not remove the TLD on exit; this method is called in a new connection thread in any case

        # setup a persistent connection if requested
        if ((cx.hdr."qorus-connection" =~ /^persistent$/i)
            || ((cx.hdr."qorus-connection" =~ /^continue-persistent$/i) && !get_thread_data("svc_listener"))) {
            hash<string, AbstractPersistentDataHelper> h.persistent_data = getPersistenceObject(cx, ah);
            # listener is an object of class HttpListenerInterface
            cx.sctx.listener.addUserThreadContext(h);
            # save the listener in the current thread data
            save_thread_data({"svc_listener": cx.sctx.listener});
            cx.uctx = h;
        }

        # return the stream request handler
        try {
            return c(cx - "sctx", ah);
        } catch (hash<ExceptionInfo> ex) {
            logRethrowException(ex, sprintf("{stream %y}", name));
        }
    }

    int getNextHandlerId() {
        return hseq.next();
    }

    private bindUserHttpHandler(AbstractServiceHttpHandler handler) {
        HttpUserServiceResource usr(handler);
        if (addResource(usr)) {
            logInfo("registered %s HTTP user service handler with heading: %y title: %y and user "
                "URL: %y", handler.listeners ? "dedicated" : "global", handler.utype, handler.utitle,
                handler.uurl);
        }
    }

    softlist<string> bindHttp(AbstractServiceHttpHandler handler,
            hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        # ensure that any resources added are stopped and removed if there's an exception
        ServiceResourceHelper rsh(self);
        on_error {
            rsh.rollback();
        }

        softlist<string> rv;
        # process dedicated listener(s)
        if (handler.listeners) {
            rv = bindHttpListeners(handler, opts);
            if (handler.utype && handler.utitle && handler.uurl) {
                # do not add the user service handler resource name to the return value
                bindUserHttpHandler(handler);
            }
        } else {
            # process a global HTTP handler
            int id = getNextHandlerId();

            # handler names must be unique
            string hname = sprintf("svc-%s-%d", name, id);
            Qorus.httpServer.setDynamicHandler(hname, handler.url, handler.content_type, handler,
                handler.special_headers, handler.isregex);
            # issue 3787: make sure to remove handler if an error occurs
            on_error Qorus.httpServer.removeDynamicHandler(hname, True);

            # add HTTP handler as service resource
            HttpGlobalHandlerServiceResource hsr(getResourceId(), hname, sprintf("handling URL: %y", handler.url),
                handler.url, handler.content_type, handler.special_headers);
            if (addResource(hsr)) {
                logInfo("registered global HTTP service handler for URL: %y, Content-Type: %y, Headers: %y",
                    handler.url, handler.content_type, handler.special_headers);
            }
            # issue 3787: make sure to remove resource if an error occurs
            on_error removeResource(hsr.getName());
            rv = hsr.getName();

            if (handler.utype && handler.utitle && handler.uurl) {
                # do not add the user service handler resource name to the return value
                bindUserHttpHandler(handler);
            }
        }
        return rv;
    }

    list<string> bindHttpListeners(AbstractServiceHttpHandler handler,
            hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        softlist<auto> l = handler.listeners;
        # do NOT use <auto> here see: bug #3020
        foreach hash h in (\l) {
            h += {
                "url": handler.url,
                "content": handler.content_type,
                "headers": handler.special_headers,
            };
        }

        # list of HTTP listeners
        list<auto> ll = services.bindHttpListenersIntern(self, handler, l, opts);

        # list of resource names as return value
        list<string> rv = ();

        # add HTTP listeners as resources to service
        foreach hash<auto> h in (ll) {
            bool newListener = False;
            {
                rm.lock();
                on_exit rm.unlock();

                if (!rsc.hasKey(h.name)) {
                    HttpListenerServiceResource hsr(
                        serviceid,
                        h.name,
                        h.name + "-" + (h.handler_name ?? "default"),
                        getResourceId(),
                        h.id,
                        h.desc,
                        handler.content_type,
                        handler.special_headers,
                        cast<list<AbstractHttpRequestHandler>>((handler,))
                    );
                    addResourceIntern(hsr);
                    newListener = True;
                }
            }
            if (newListener) {
                services.registerListener(h.id, self, h.name);
            }
            rv += h.name;
        }

        logInfo("bound %d HTTP listener%s to service", ll.size(), ll.size() == 1 ? "" : "s");

        return rv;
    }

    bindHandler(string name, AbstractHttpRequestHandler handler, string url, *softlist<auto> content_type,
            *softlist<auto> special_headers, bool isregex = True) {
        rm.lock();
        on_exit rm.unlock();

        if (!rsc{name}) {
            throw "BIND-HANDLER-ERROR", sprintf("cannot bind a new HTTP handler to unknown service resource %y; "
                "known resources: %y", name, keys rsc);
        }

        if (!(rsc{name} instanceof HttpListenerServiceResource)) {
            throw "BIND-HANDLER-ERROR", sprintf("cannot bind a new HTTP handler to service resource %y of type %y "
                "(expecting \"HttpListener\")", name, rsc{name}.getType());
        }

        HttpListenerServiceResource sr = rsc{name};

        # handler names must be unique
        string hname = sprintf("svc-%s-%s-%s-%s", name, url ?* "/", handler.className(), isregex ? "R" : "N");
        if (content_type) {
            hname += "-" + (foldl $1 + "|" + $2, content_type);
        }
        if (special_headers) {
            hname += "-" + (foldl $1 + "|" + $2, special_headers);
        }
        Qorus.httpServer.addHandlerToListenerID(sr.id, hname, <HttpHandlerConfigInfo>{
            "path": url,
            "content_types": content_type,
            "handler": handler,
            "headers": special_headers,
            "isregex": isregex,
        });
        sr.addHandlers(cast<list<AbstractHttpRequestHandler>>((handler,)));

        logInfo("added HTTP service handler %y to resource %y for URL: %y (regex: %y), Content-Type: %y, Headers: %y",
            hname, name, url, isregex, content_type, special_headers);
    }

    bindHandler(string name, AbstractServiceHttpHandler handler) {
        rm.lock();
        on_exit rm.unlock();

        if (!rsc{name}) {
            throw "BIND-HANDLER-ERROR", sprintf("cannot bind a new HTTP handler to unknown service resource %y; "
                "known resources: %y", name, keys rsc);
        }

        if (!(rsc{name} instanceof HttpListenerServiceResource)) {
            throw "BIND-HANDLER-ERROR", sprintf("cannot bind a new HTTP handler to service resource %y of type %y "
                "(expecting \"HttpListener\")", name, rsc{name}.getType());
        }

        HttpListenerServiceResource sr = rsc{name};

        # handler names must be unique
        string hname = sprintf("svc-%s-%s-%s-%s", name, handler.url ?* "/", handler.className(),
            handler.isregex ? "R" : "N");
        if (handler.content_type) {
            hname += "-" + (foldl $1 + "|" + $2, handler.content_type);
        }
        if (handler.special_headers) {
            hname += "-" + (foldl $1 + "|" + $2, handler.special_headers);
        }
        Qorus.httpServer.addHandlerToListenerID(sr.id, hname, <HttpHandlerConfigInfo>{
            "path": handler.url,
            "content_types": handler.content_type,
            "handler": handler,
            "headers": handler.special_headers,
            "isregex": handler.isregex,
        });
        sr.addHandlers(cast<list<AbstractServiceHttpHandler>>((handler,)));

        logInfo("added HTTP service handler %y to resource %y for URL: %y (regex: %y), Content-Type: %y, Headers: %y",
            hname, name, handler.url, handler.isregex, handler.content_type, handler.special_headers);
    }

    startService(*bool qorus_core_recover) {
        {
            # issue #2398: all reference operations must be serialized due to the use of the condition variable
            m.lock();
            on_exit m.unlock();

            if (stopped) {
                throw "SERVICE-STOPPED-ERROR", "cannot start service that's already been stopped";
            }

            ++refs;
%ifdef QorusDebugInternals
            addReferenceReason("start service call", {"tid": gettid(), "recover": qorus_core_recover});
%endif
        }

        if (!startServiceConditional(qorus_core_recover)) {
            # did not start service, must dereference
            deref();
        }
    }

    bool isInTransition() {
        return starting || stopping;
    }

    bool deref() {
        m.lock();
        on_exit m.unlock();

%ifdef QorusDebugInternals
        # issue #2398: dereference with the same TID
        int tid = get_thread_data("orig_service_thread_tid") ?? gettid();
        removeReferenceReason(tid);
%endif

        # issue #2526: in case of a qsvc process early termination, "refs" can be zero while calls are in progress
        # we have to make sure it never goes negative, which could lead to a deadlock
        if (!refs) {
            return True;
        }
        if (!(--refs)) {
            if (waiting) {
                statcond.broadcast();
            }

            return True;
        }
        return False;
    }

    ref() {
        m.lock();
        on_exit m.unlock();

        if (stopped) {
            throw "SERVICE-STOPPED-ERROR", "cannot start service that's already been stopped";
        }

%ifdef QorusDebugInternals
        addReferenceReason("ref() call", {"tid": gettid(), "stack": get_stack()});
%endif
        ++refs;
    }

    startupDone() {
        m.lock();
        on_exit m.unlock();
        # unset service initialization flag
        starting = 0;
        if (waiting) {
            statcond.broadcast();
        }
    }

    stop(bool idle = False) {
        on_exit {
            m.lock();
            on_exit m.unlock();

            while (refs) {
                logInfo("waiting for calls in progress: %d", refs);
                ++waiting;
                statcond.wait(m);
                --waiting;
            }

            stopped = True;
        }

        Qorus.logInfo(formatSvcLogMessage(type, name, "stopping running %s service, refs: %d", type, refs));

        logInfo("stopping service");

        # issue #2398: serialize setting "stopping" to ensure that stop code is only run once
        if (stopNow()) {
            stopIntern();

            # stop resources
            stopAllResources();
        }

        if (idle) {
            if (refs) {
                Qorus.logInfo(formatSvcLogMessage(type, name, "waiting for %d method call%s in progress to "
                    "terminate", refs, refs == 1 ? "" : "s"));
                # allow read-only calls to be made while stopping the service
                services.releaseServiceToReadOnly(type, name);
                on_exit services.reacquireServiceExclusive(type, name);

                m.lock();
                on_exit m.unlock();

                while (refs) {
                    ++waiting;
                    statcond.wait(m);
                    --waiting;
                }

            }
            Qorus.logInfo(formatSvcLogMessage(type, name, "stopped; %s", getStopReason().getText()));
        }
    }

    ActionReason getStartReason() {
        return startreason;
    }

    string getStartReasonText() {
        return startreason.getText();
    }

    # returns True if the service is a remote service and terminates during the setup, meaning that
    # the init method should not be run again
    bool setup(hash<auto> sq, *bool qorus_core_recover, *string uuid) {
        *int po = setupIntern(sq);
        return setupImpl(sq, po, qorus_core_recover, uuid);
    }

    private logRethrowException(hash<ExceptionInfo> ex, string context_str, *ServiceThreadContextHelper stch) {
        *string desc = !Qorus.getDebugSystem()
            ? ex.desc
            : Util::get_exception_string(ex);

        string cxstr;
        *hash ccx = ServiceApi::getCallContext();
        if (ccx.wf) {
            cxstr = sprintf(" (called from: workflow %s v%s (%d)", ccx.wf.name, ccx.wf.version, ccx.wf.workflowid);
            if (ccx.wf.workflow_instanceid) {
                cxstr += sprintf(" workflow_instanceid %d", ccx.wf.workflow_instanceid);
                if (ccx.wf.stepid) {
                    *hash sh = Qorus.qmm.lookupStep(ccx.wf.stepid);
                    if (sh) {
                        cxstr += sprintf(" step %s v%s", sh.name, sh.version);
                    }
                    cxstr += sprintf(" (%d/%d)", ccx.wf.stepid, ccx.wf.ind);
                }
            }
        } else if (ccx.job) {
            cxstr = sprintf(" (called from: job %s v%s (%d) job_instanceid %d", ccx.job.name, ccx.job.version,
                ccx.job.jobid, ccx.job.job_instanceid);
        } else if (stch.svc) {
            cxstr = sprintf(" (called by: %s service %s.%s", stch.svc.type, stch.svc.name, stch.method);
        }

        if (ccx.cx) {
            cxstr += cxstr ? " " : " (";
            cxstr += sprintf("called externally from %s", ccx.cx."peer-info".address_desc);
            if (ccx.cx.user) {
                cxstr += sprintf(" user %y", ccx.cx.user);
            }
        }
        if (cxstr) {
            cxstr += ")";
        }

        logInfo("exception calling %s.%s.%s%s: %s: %s: %s%s", type, name, context_str, cxstr, get_ex_pos(ex), ex.err,
            desc, ex.arg.val() ? sprintf(" (%y)", ex.arg) : "");
        #logDebug("stack: %N", get_thread_call_stack());
        throw ex.err, sprintf("%s (while calling %s.%s.%s): %s", get_ex_pos(ex), type, name, context_str, desc), ex.arg;
    }

    stopAllResources(*bool aborted) {
        QDBG_LOG("AbstractQorusCoreService::stopAllResources() %y", (map {$1.key: $1.value.className()}, rsc.pairIterator()));

        # stop resources
        while (True) {
            string tag;
            AbstractServiceResource vrsc;
            {
                rm.lock();
                on_exit rm.unlock();
                if (!rsc) {
                    break;
                }
                tag = rsc.firstKey();
                vrsc = remove rsc{tag};
            }
            stopResource(tag, vrsc, aborted);
        }
    }

    private stopResource(string tag, AbstractServiceResource vrsc, *bool aborted) {
        logInfo("stopping resource %y: %s", tag, vrsc.getType());
        try {
            vrsc.stop(aborted);
        } catch (hash<ExceptionInfo> ex) {
            string desc = sprintf("WARNING! exception stopping resource %y: %s for service %s.%s; could lead to a "
                "deadlock: %s: %s: %s", tag, vrsc.getType(), type, name, get_ex_pos(ex), ex.err, ex.desc);
            logFatal(desc);
            logFatal(Util::get_exception_string(ex));

            Qorus.events.postServiceError(tld.cx, ES_Major, type, name, version, serviceid, "STOP-ERROR", desc);
        }
    }

    private delIntern(Mutex lck) {
        ensure_create_tld();

        # issue #3787: ensure that all resources are removed
        stopAllResources(True);

        lck.lock();
        on_exit lck.unlock();

        delete self;
    }

    logExtern() {
        logInfo("%s", vsprintf(shift argv, argv));
    }

    logErrorExtern() {
        logError("%s", vsprintf(shift argv, argv));
    }

    updateLogger(*hash<LoggerParams> params) {
        if (params) {
            hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                "name": name,
                "id": serviceid.toString(),
                "version": version,
            };
            params = substituteLogFilename(params, LoggerController::getLoggerSubs("services", subs));
        }
        updateLoggerImpl(params);
    }

    # returns True if we are the first thread to stop the service
    /** if this method returns True, then we can call the stop method (if the service has not aborted)
        and stop all resources - these actions can only be performed once when the service is shut down
    */
    private:internal bool stopNow() {
        m.lock();
        on_exit m.unlock();

        return stopNowIntern();
    }

    private:internal bool stopNowIntern() {
        if (!stopping) {
            stopping = gettid();
            QDBG_LOG("stopping %s service %s v%s (%d)", type, name, version, serviceid);
            return True;
        }
        return False;
    }

    abstract bool setupImpl(hash<auto> sq, *int po, *bool qorus_core_recover, *string uuid);
    abstract hash<auto> getInfoImpl(*hash<auto> cx);
    abstract bool startServiceConditional(*bool qorus_core_recover);
    abstract private auto callMethodImpl(string method, auto args, *binary serialized_args, *hash<auto> cx,
        *bool serialized, *QorusProgram ix_pgm);
    abstract hash<auto> getResource(string n, hash<auto> ctx, int code = 200, *hash<auto> hdr);
    abstract *hash tryGetResource(string n, hash<auto> ctx, int code = 200, *hash<auto> hdr);
    abstract data getResourceData(string n, *hash<auto> ctx);
    abstract WebService getResourceWsdl(string n, *hash<auto> ctx);
    abstract *data tryGetResourceData(string n, *hash<auto> ctx);
    abstract *hash<auto> getResourceHash();
    abstract list<string> getResourceList();
    abstract list<hash<auto>> getResourceHashList();
    abstract bool hasResource(string n);
    abstract checkDefaultResource(string name);
    abstract hash<auto> renderTemplate(string n, *hash<auto> ctx);
    abstract *hash<auto> tryRenderTemplate(string n, hash<auto> cx);
    abstract *hash<auto> getTemplateHash();
    abstract list<auto> getTemplateList();
    abstract bool hasTemplate(string n);
    abstract bool hasInit();
    abstract setStopReason(string desc);
    abstract setStopReason(*hash<auto> cx, *string reason, bool override_reason = False);
    abstract setLocalStopReason(hash<ExceptionInfo> ex, string reason_fmt);
    abstract private stopProcess();
    abstract updateLoggerImpl(*hash<LoggerParams> params);
    abstract rotateLogFiles();
    abstract postLogEvent(LoggerEvent event);
    abstract *Program getProgram();

    static del(AbstractQorusCoreService svc, Mutex lck) {
        svc.stopProcess();
        # fix for bug 545: a system deadlock can happen if a service returns objects and then the service is reset
        # while an object returned by the service attempts to make service calls
        # the deletion of the Program is run in a background thread in case it is blocked on locks that the current
        # thread is holding
        background sub () {
            try {
                *Program pgm = svc.getProgram();
                on_exit delete pgm;
                svc.delIntern(lck);
            } catch (hash<ExceptionInfo> ex) {
                # ignore OBJECT-ALREADY-DELETED exception; log all others
                if (ex.err != "OBJECT-ALREADY-DELETED") {
                    Qorus.logInfo("FATAL ERROR: unexpected exception deleting service: %s", get_exception_string(ex));
                }
            };
        }();
    }
}
