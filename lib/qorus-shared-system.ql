# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

our SystemServiceHelper sysinfo;
our SystemApiHelper api;

const OMQ::AlertTypeRemote = "REMOTE";
const OMQ::AlertTypeUser = "USER-CONNECTION";
const OMQ::AlertTypeDatasource = "DATASOURCE";

#! keys for infrastructure shared thread context
const OMQ::QorusSharedContextKeys = (
    "svc_locks",
    "external_locks",
    "method",
    "index",
    "index_map",
    "cx",
);

#! keys for workflow thread context serialization
const OMQ::WorkflowCallContextKeys = ("name", "version", "workflowid", "stepinfo");

#! keys for workflow order thread context serialization
const OMQ::WorkflowOrderCallContextKeys = ("workflow_instanceid", "priority", "started");

const OMQ::LibraryTypeInfo = {
    "classes": {
        "table": "classes",
        "column": "classid",
        "tag": "class",
        "type": OT_CLASS,
    },
    "functions": {
        "table": "function_instance",
        "column": "function_instanceid",
        "tag": "function_instance",
        "type": OT_FUNCTION,
    },
    "constants": {
        "table": "constants",
        "column": "constantid",
        "tag": "constant",
        "type": OT_CONSTANT,
    },
    "pipelines": {
        "table": "pipelines",
        "column": "name",
        "type": OT_PIPELINE,
    },
    "fsm": {
        "table": "fsm",
        "column": "name",
        "type": OT_FSM,
    },
    "mappers": {
        "table": "mappers",
        "column": "mapperid",
        "type": OT_MAPPER,
    },
};

const OMQ::LibMaps = (
    "stepmap", "steprmap",
    "functionmap", "functionrmap",
    "classmap", "classrmap",
    #"constmap", "constrmap",
    "qmap",
    "mmap", "mrmap",
    "pipelines",
    "fsm",
);

sub qsrand(softint int) {
    # does nothing
}

*hash<auto> sub get_cx(*hash<auto> cx) {
    # all possible context keys need to be sent over the network, however no callable type or objects can be sent
    return cx - ("sctx", "uctx") -
        (map $1.key, cx.pairIterator(),
            $1.value.callp() || ($1.value.typeCode() == NT_OBJECT && !($1.value instanceof Serializable)));
    #return cx.("socket", "socket-info", "peer-info", "id", "ssl", "listener-id", "user", "method", "orig_method",
    #   "url", "hdr", "user", "peer-info", "method", "mark", "encoding");
}

*hash<auto> sub qorus_get_source_hash() {
    hash<auto> h;

    if (tld.wf) {
        h.type = "WORKFLOW";
        h.info = tld.wf.("workflowid", "name", "version");
        h.id = h.info.workflowid;
        h.info.desc = sprintf("workflow %s v%s (%d)", h.info.name, h.info.version, h.id);
        return h;
    }

    if (tld.wfe) {
        h.type = "WORKFLOW";
        h.info = tld.wfe.wf.("workflowid", "name", "version");
        h.id = h.info.workflowid;
        h.info.desc = sprintf("workflow %s v%s (%d)", h.info.name, h.info.version, h.id);
        return h;
    }

    if (tld.job) {
        #QDBG_LOG("tld.job: %y", tld.job);
        h.type = "JOB";
%ifdef HasJobClass
        h.info = tld.job instanceof LocalQorusJob ? tld.job.getInfo().("jobid", "name", "version") : tld.job{"jobid", "name", "version"};
%else
        h.info = tld.job{"jobid", "name", "version"};
%endif
        h.id = h.info.jobid;
        h.info.desc = sprintf("job %s v%s (%d)", h.info.name, h.info.version, h.id);
        return h;
    }

    if (tld.svc) {
        h.type = "SERVICE";
        h.info = tld.svc.("serviceid", "type", "name", "version");
        # issue #1912 rename "type" -> "servicetype"
        h.info.servicetype = remove h.info.type;
        h.id = tld.svc.serviceid;
        h.info.desc = sprintf("%s service %s v%s (%d)", h.info.servicetype, h.info.name, h.info.version, h.id);
        return h;
    }
}

auto sub qorus_get_system_option(string opt) {
    return Qorus.options.get(opt);
}

hash<auto> sub qorus_get_system_options() {
    return Qorus.options.get();
}

string sub process_system_template(string template) {
    template = regex_subst(template, "\\$instance", Qorus.options.get("instance-key"));
    template = regex_subst(template, "\\$pid", string(getpid()));
    template = regex_subst(template, "\\$host", gethostname());
    return template;
}

sub alert_exception(string type, string alert, hash<auto> ex, int id = -1, string name = "Qorus") {
    ActionReason r(tld.cx, ex);
    Qorus.alerts.raiseTransientAlert(r, type, id, alert, ("name": name));
}

*list sub get_stack() {
    if (!HAVE_RUNTIME_THREAD_STACK_TRACE)
        return;
    *list stack = get_thread_call_stack();
    if (!stack)
        return;
    splice stack, 0, 2;
    return map $1.type != "new-thread" ? sprintf("%s %s()", get_ex_pos($1), $1.function) : "new-thread", stack;
}

string sub get_url_from_option(string prot, softstring opt, *string username, *string password) {
    # remove any options from "opt"
    opt =~ s/{.*}//;

    prot += "://";
    if (username && password) {
        prot += sprintf("%s:%s@", username, password);
    }

    if (opt =~ /:/) {
        # convert "0.0.0.0", "::", and "[::]" to "localhost"
        opt =~ s/^(0.0.0.0|::|\[::\]):/localhost:/;
        return sprintf("%s%s", prot, opt);
    }
    if (opt =~ /^\//)
        return sprintf("%ssocket=%s", prot, encode_url(opt, True));
    return sprintf("%slocalhost:%d", prot, opt);
}

sub qorus_add_mapper(string namever, *reference<hash<auto>> mappers) {
    (*string name, *string version) = (namever =~ x/^([^:]+):(.+)$/);
    if (name && version) {
        *softint mid = Qorus.qmm.rLookupMapper(name, version);
        if (mid) {
            mappers{namever} = {
                "name": name,
                "version": version,
                "id": mid,
            };
        }
    }
}

sub qorus_scan_fsm_mappers(hash<auto> fsm, *reference<hash<auto>> mappers) {
    map qorus_add_mapper($1.action.value, \mappers), fsm.states.values(),
        $1.action.type == "mapper" && exists $1.action.value;
}

sub qorus_scan_pipeline_mappers(list<auto> children, *reference<hash<auto>> mappers) {
    foreach hash<auto> child in (children) {
        if (child.type == "mapper") {
            qorus_add_mapper(child.name, \mappers);
        }
        if (child.children) {
            qorus_scan_pipeline_mappers(child.children, \mappers);
        }
    }
}

sub qorus_load_library_object(hash<auto> type_info, hash<auto> o, QorusProgram pgm, *code log,
        *reference<hash<auto>> mappers) {
    #QDBG_LOG("qorus_load_library_object() %s %s %s: B select", type_info.table, type_info.type, exists o.id ? sprintf("%d", o.id) : o.name);
    *hash<auto> oq = omqp.selectRow("select * from %s where %s = %v", type_info.table, type_info.column,
                                    o.id ?? o.name);
    if (!oq) {
        throw "LIBRARY-ERROR",
            sprintf("%s not found in table %s", exists o.id ? sprintf("%s %d", type_info.column, o.id) : o.name,
                    type_info.table);
    }
    #QDBG_LOG("qorus_load_library_object() %s %s %s: A select", type_info.table, type_info.type, exists o.id ? sprintf("%d", o.id) : o.name);

    if (type_info.type == OT_MAPPER) {
        mappers{o.name} = o;
        return;
    }

    if (type_info.type == OT_PIPELINE) {
        if (pgm.lib_cache_pipe{o.name}) {
            return;
        }
        pgm.lib_cache_pipe{o.name} = True;

        *hash<auto> pipeline = Qorus.qmm.lookupPipeline(o.name);
        if (pipeline) {
            #QDBG_LOG("qorus_load_library_object(): pipeline_libs: %y", pipeline_libs);
            foreach string lib_name in (keys pipeline.lib) {
                map qorus_load_library_object(LibraryTypeInfo{lib_name}, $1, pgm, log, \mappers),
                    pipeline.lib{lib_name};
            }
            qorus_scan_pipeline_mappers(pipeline.children, \mappers);
        }
        return;
    }

    if (type_info.type == OT_FSM) {
        if (pgm.lib_cache_fsm{o.name}) {
            return;
        }
        pgm.lib_cache_fsm{o.name} = True;

        *hash<auto> fsm = Qorus.qmm.lookupFsm(o.name);
        if (fsm) {
            *hash<string, list<hash<auto>>> fsm_libs = fsm.lib;
            #QDBG_LOG("qorus_load_library_object(): fsm_libs: %y", fsm_libs);
            foreach string lib_name in (keys fsm_libs) {
                map qorus_load_library_object(LibraryTypeInfo{lib_name}, $1, pgm, log, \mappers), fsm_libs{lib_name};
            }
            qorus_scan_fsm_mappers(fsm, \mappers);
        }
        return;
    }

    # issue #2282: ensure functions are only loaded once
    if (type_info.type == OT_FUNCTION) {
        if (pgm.lib_cache_func{o.id}) {
            return;
        }
        pgm.lib_cache_func{o.id} = True;
    }

    # issue #3285: ensure classes are only loaded once; required classes are already listed as library objects
    if (type_info.type == OT_CLASS) {
        if (pgm.lib_cache_class{o.id}) {
            return;
        }
        pgm.lib_cache_class{o.id} = True;

        foreach int classid in (Qorus.qmm.lookupClass(o.id).requires) {
            hash<auto> obj_hash = {
                "id": classid,
                "version": Qorus.qmm.lookupClass(classid).version,
            };

            qorus_load_library_object(type_info, obj_hash, pgm, log, \mappers);
        }
    }

    # get tags
    *hash<auto> tags = sqlif.getTags(type_info.tag, o.id);
    *hash<auto> th = tags.sys;

    if (th.source) {
        th.source = basename(th.source);
    } else if (th) {
        th -= ("source", "offset");
    }

    if (log) {
        string msg = sprintf("loading library %s %s:%s(%d) lang %s %d bytes", type_info.type, oq.name, o.version, o.id,
                             oq.language ?? "qore", oq.body.size());
        if (th.source) {
            msg += sprintf(" (source %y:%d)", th.source, th.offset);
        }
        log(msg);
    }

    if (type_info.type != OT_CLASS || oq.language == "qore") {
        string label = sprintf("%s: %s v%s (%d)", type_info.type.lwr(), oq.name, o.version, o.id);
        pgm.parsePending(oq.body, sprintf("%s %s:%s", type_info.type, oq.name, o.version), 0, th.source, th.offset);
    } else if (oq.language == "java") {
        QDBG_ASSERT(oq.language_info);
        pgm.cacheJavaClass(oq.name, oq.language_info, NOTHING, tags.classpath);
    } else if (oq.language == "python") {
        pgm.cachePythonClass(oq.name, oq.body, oq.language_info, NOTHING, tags.module_path);
    } else {
        throw "UNSUPPORTED-LANGUAGE", sprintf("language %y is not supported; expecting qore, java, or python",
            oq.language);
    }
}

# exception handling is outside of this function
sub qorus_load_library(*hash<auto> libh, QorusProgram pgm, *code log, *reference<hash<auto>> mappers) {
    #printf("qorus_load_library()\nq=%N\npgm=%N\nlogf=%N\nlogargs=%N\n", q, pgm, logf, logargs);

    map qorus_load_library_object(LibraryTypeInfo.functions, $1, pgm, log), libh.functions;
    map qorus_load_library_object(LibraryTypeInfo.classes, $1, pgm, log), libh.classes;
    map qorus_load_library_object(LibraryTypeInfo.constants, $1, pgm, log), libh.constants;
    map qorus_load_library_object(LibraryTypeInfo.pipelines, $1, pgm, log, \mappers), libh.pipelines;
    map qorus_load_library_object(LibraryTypeInfo.fsm, $1, pgm, log, \mappers), libh.fsm;
}

string sub log_now() {
    return now_us().format("YYYY-MM-DD HH:mm:SS.xx");
}

# helper class to making sure that no thread resources are left allocated after the scope of this object
class OMQ::ThreadResourceHelper {
    constructor() {
        mark_thread_resources();
    }
    destructor() {
        throw_thread_resource_exceptions_to_mark();
    }
}

#! Helper class to set the current thread FSM and state context
class OMQ::FsmStateContextHelper {
    public {
        *hash<auto> fsm_ctx;
    }

    constructor(FsmInfo fsm, string state, int exec_id) {
        fsm_ctx = tld.fsm_ctx;
        tld.fsm_ctx = {
            "fsm": fsm,
            "state": state,
            "exec_id": exec_id,
        };
        #QDBG_LOG("FsmStateContextHelper::constructor() setting: %y %y -> %y %y (%y %y)", fsm_ctx.fsm ? fsm_ctx.fsm.getName() : "n/a", fsm_ctx.state, fsm.getName(), state, tld.fsm_ctx.fsm.getName(), tld.fsm_ctx.state);
    }

    destructor() {
        #QDBG_LOG("FsmStateContextHelper::destructor() restoring: %y %y -> %y %y", tld.fsm_ctx.fsm.getName(), tld.fsm_ctx.state, fsm_ctx.fsm ? fsm_ctx.fsm.getName() : "n/a", fsm_ctx.state);
        tld.fsm_ctx = fsm_ctx;
    }
}

string sub qorus_get_source() {
    string source;

    if (tld) {
        if (tld.isOrderContext()) {
            source = sprintf("wf %s v%s (%d)", tld.wfe.wf.name, tld.wfe.wf.version, tld.wfe.wf.workflowid);
            if (tld.wfe.workflow_instanceid) {
                source += sprintf(" wfiid %d", tld.wfe.workflow_instanceid);
                if (tld.stepID) {
                    source += sprintf(" step %d/%d", tld.stepID, tld.ind);
                }
            }
            source += sprintf(" exec ID %s", tld.index);
        } else if (tld.isWorkflowContext()) {
            source = sprintf("wf %s v%s (%d)", tld.wf.name, tld.wf.version, tld.wf.workflowid);
        } else if (tld.isJobContext()) {
            hash<auto> jh = tld.job.typeCode() == NT_OBJECT ? tld.job.getInfo() : tld.job;
            source = sprintf("job %s v%s (%d) jiid %d", jh.name, jh.version, jh.jobid, jh.job_instanceid);
        } else if (tld.isServiceContext()) {
            source = sprintf("%s service %s v%s (%d)", tld.svc.type, tld.svc.name, tld.svc.version, tld.svc.serviceid);
            if (tld.method) {
                source += sprintf(" method: %s", tld.method);
            }
        }
    }
    if (!source) {
        source = "system";
    }

    return source;
}

# for invalid mappers
class OMQ::InvalidMapperType inherits OMQ::AbstractMapperType {
    private {
        string name;
    }

    constructor(string n_name) {
        name = n_name;
    }

    bool isValid() {
        return False;
    }

    string getName() {
        return name;
    }

    hash<auto> getMapperOptions() {
        return {};
    }

    *list<string> getRequiredRecordOptions() {
    }

    Mapper::Mapper get(hash<auto> mapv, *hash<auto> opts) {
        throw "INVALID-MAPPER", sprintf("the mapper refers to invalid mapper type %y and was marked as invalid when loaded", name);
    }

    bool requiresInput() {
        return False;
    }

    bool requiresOutput() {
        return False;
    }
}

class SystemApiHelper {
    auto methodGate(string m) {
        return call_system_api_as_user(m, argv, DefaultSystemUser, True);
    }

    code memberGate(string m) {
        return auto sub () { return call_system_api_as_user(m, argv, DefaultSystemUser, True); };
    }

    auto callArgs(string m, *softlist<auto> args) {
        return call_system_api_as_user(m, args, DefaultSystemUser, True);
    }
}

class SystemServiceHelper {
    private {
        string name;
    }

    constructor(string v_name) {
        name = v_name;
    }

    auto methodGate(string m) {
        return omqservice.system{name}.externalMethodGateArgs(m, argv);
    }
}

/*  The queue/socket monitor. A static only (not a real singleton) class
    which provides support for main Qorus proces (qorus-core) and user connections.
    By running a dedicated threads for network monitoring
 */
class OMQ::MonitorSingleton {
    public {
        # socket perf and warning queue
        static Queue sock_queue();
        # datasource perf and warning queue
        static Queue ds_queue();
        # socket event queue
        static Queue event_queue();
        # thread counter
        static Counter cnt();
    }

    private static socketPerfMon() {
        on_exit cnt.dec();

        while (True) {
            *hash<auto> h = sock_queue.get();
            if (!h)
                break;

            # issue #2268: check if warnings are enabled on this object
            if (h.arg.mon == AlertTypeUser) {
                if (Qorus.connections.ignoreSocketWarnings(h.arg.name)) {
                    continue;
                }
            } else if (h.arg.mon == AlertTypeRemote) {
                if (Qorus.remotemonitor.ignoreSocketWarnings(h.arg.name)) {
                    continue;
                }
            }

            if (!h.name) {
                h.name = h.arg.name;
            }

            string str;
            switch (h.type) {
                case "SOCKET-OPERATION-WARNING": {
                    str = sprintf("excessive I/O time in %s operation: %y exceeded threshold: %y", h.operation, microseconds(h.us), microseconds(h.timeout));
                    break;
                }
                case "SOCKET-THROUGHPUT-WARNING": {
                    str = sprintf("slow I/O in %s operation: %s/s below warning threshold of %s/s in a transfer of %d byte%s", h.dir, get_byte_size(h.bytes_sec), get_byte_size(h.threshold), h.bytes, h.bytes == 1 ? "" : "s");
                    break;
                }
                default: {
                    str = "unknown socket performance warning";
                    break;
                }
            }

            ActionReason r(tld.cx, str, True);
            Qorus.alerts.raiseTransientAlert(r, h.arg.mon, h.arg.name, h.type, h - ("type", "arg"));
        }
    }

    private static dsPerfMon() {
        on_exit cnt.dec();

        while (True) {
            *hash<auto> h = ds_queue.get();
            if (!h)
                break;

            string desc = sprintf("%s@%s: %s", remove h.user, remove h.db, remove h.desc);
            ActionReason r(tld.cx, desc, True);
            #printf("DS WARNING: %N\n", h);
            Qorus.alerts.raiseTransientAlert(r, h.arg.mon, h.arg.name, remove h.warning, h - ("arg") + ("name": h.arg.name));
        }
    }

    private static sockEventMon() {
        on_exit cnt.dec();

        while (True) {
            *hash<auto> h = event_queue.get();
            if (!h) {
                break;
            }

            h.arg.logInfo("SOCKET DATA %s %y (id %x): %s: %y", h.arg.mon, h.arg.conn, h.id, EVENT_MAP{h.event}, h - ("arg", "event", "source", "id"));
        }
    }

    static start() {
        try {
            cnt.inc();
            background MonitorSingleton::socketPerfMon();
        } catch () {
            cnt.dec();
            rethrow;
        }
        try {
            cnt.inc();
            background MonitorSingleton::dsPerfMon();
        } catch () {
            cnt.dec();
            rethrow;
        }
        try {
            cnt.inc();
            background MonitorSingleton::sockEventMon();
        } catch () {
            cnt.dec();
            rethrow;
        }
    }

    static stop() {
        sock_queue.push();
        ds_queue.push();
        event_queue.push();
        cnt.waitForZero();
    }

    static setSocketMonitor(object obj, hash<auto> arg) {
        if (obj.hasCallableNormalMethod("setWarningQueue")) {
            int wt = Qorus.options.get("socket-warning-timeout");
            int mt = Qorus.options.get("socket-min-throughput");
            if (wt >= 0 || mt >= 0) {
                obj.setWarningQueue(wt, mt, sock_queue, arg, Qorus.options.get("socket-min-throughput-ms"));
            }
        }
    }

    static setEventMonitor(object obj, string type, string conn) {
        if (obj.hasCallableNormalMethod("setEventQueue")) {
            *code logInfo = MonitorSingleton::getLogInfo();
            if (logInfo) {
                obj.setEventQueue(event_queue, {
                    "mon": type.upr(),
                    "conn": conn,
                    "logInfo": logInfo,
                }, True);
            }
        }
    }

    #! returns a closure for logging info messsages to the current interface
    static private *code getLogInfo() {
%ifdef QorusCore
        if (tld && (*object ix = tld.getInterface())) {
            return \ix.logInfo();
        }
%else
        return \Qorus.logInfo();
%endif
    }
}

sub set_socket_monitor(object obj, hash<auto> arg) {
    MonitorSingleton::setSocketMonitor(obj, arg);
}

class JavaFsRemoteReceive inherits AbstractFsRemoteReceive {
    private {
        object java_obj;
    }

    constructor(string remote, string path, string streamType = TYPE_FILE, *hash<auto> options)
        : AbstractFsRemoteReceive(remote, path, streamType, options) {
    }

    constructor(string remote, string conn, string path, string streamType = TYPE_FILE, *hash<auto> options)
        : AbstractFsRemoteReceive(remote, conn, path, streamType, options) {
    }

    constructor(QorusSystemRestHelper remote, string path, string streamType = TYPE_FILE, *hash<auto> options)
        : AbstractFsRemoteReceive(remote, path, streamType, options) {
    }

    constructor(QorusSystemRestHelper remote, string conn, string path, string streamType = TYPE_FILE, *hash<auto> options)
        : AbstractFsRemoteReceive(remote, conn, path, streamType, options) {
    }

    setJavaObject(object obj) {
        java_obj = obj;
    }

    recvDataImpl(auto row) {
        java_obj.recvDataImpl(row);
    }
}

class OMQ::QorusFilesystemConnection inherits FilesystemConnection {
    deprecated
    constructor(string name, string desc, string url, bool monitor, *hash<auto> opts, hash<auto> urlh)
        : FilesystemConnection(name, desc, url, {"monitor": monitor}, opts ?? {}) {
    }

    constructor(string name, string desc, string url, hash<auto> attributes = {}, hash<auto> options = {})
        : FilesystemConnection(name, desc, url, attributes, options) {
    }

    private Dir getImpl(bool connect = True, *hash<auto> rtopts) {
        Dir dir = FilesystemConnection::getImpl(connect);
        if (connect) {
            hash<FilesystemInfo> fh = dir.statvfs();
            number bpct;
            number bused;
            number btot;
            if (fh.blocks) {
                number bsize = 4096; #number(fh.bsize);
                btot = number(fh.blocks) * bsize;
                bused = number(fh.blocks - fh.bavail) * bsize;
                bpct = bused / btot * 100n;
            }
            number ipct;
            number iused;
            if (fh.files) {
                number tot = number(fh.files);
                iused = number(fh.files - fh.favail);
                ipct = iused / tot * 100n;
            }
            if (exists bpct) {
                string msg;
                if (exists ipct)
                    msg = sprintf("filesystem at %y is %.2f%% full (%s/%s), %.2f%% full (%d/%d inodes)", url, bpct, get_byte_size(bused), get_byte_size(btot), ipct, iused, fh.files);
                else
                    msg = sprintf("filesystem at %y is %.2f%% full (%s/%s)", url, bpct, get_byte_size(bused), get_byte_size(btot));
                self.log(name, msg);
                if (bpct > Qorus.options.get("alert-fs-full")) {
                    ActionReason reason(NOTHING, msg + sprintf("; filesystem alert threshold: %d%% exceeded", Qorus.options.get("alert-fs-full")), True);
                    Qorus.alerts.raiseOngoingAlert(reason, AlertTypeUser, name, "FILESYSTEM-FULL", ("name": name, "url": url));
                } else {
                    ActionReason reason(NOTHING, sprintf("filesystem alert threshold: %d%% no longer exceeded", Qorus.options.get("alert-fs-full")), True);
                    Qorus.alerts.clearOngoingAlert(reason, AlertTypeUser, name, "FILESYSTEM-FULL");
                }
            } else if (exists ipct)
                self.log(name, "filesystem at %y is %.2f%% full (%s/%s inodes)", url, ipct, iused, fh.files);
        }
        return dir;
    }

    private log(string name, string msg) {
        if (Qorus && Qorus.connections) {
%ifdef QorusCore
            Qorus.connections.log(name, vsprintf(msg, argv));
%else
            Qorus.logInfo("Connections: user %y: %s", name, vsprintf(msg, argv));
%endif
        }
    }

    deprecated
    static AbstractConnection make(string name, string desc, string url, bool monitor, *hash opts, hash urlh) {
        return new QorusFilesystemConnection(name, desc, url, {"monitor": monitor}, opts ?? {});
    }
}

list<hash<auto>> sub process_audit_events(*hash<auto> q) {
    list<hash<auto>> l = ();

    context (q) {
        hash<auto> h = %%;
        # remove all NULL values
        map delete h.$1, keys h, h.$1 === NULL;
        h.event = OMQ::AuditEventMap.(h.audit_event_code);
        l += h;
    }

    return l;
}

Mapper::Mapper sub get_specific_mapper(string namever, *hash<auto> rtopts) {
    (*string name, *string ver) = (namever =~ x/^([^:]+):(.+)$/);
    if (!name || !ver) {
        throw "MAPPER-ERROR", sprintf("mapper identifier %y is not in format <name>:<version>", namever);
    }
    *softint mid = Qorus.qmm.rLookupMapper(name, ver);
    if (!mid) {
        throw "MAPPER-ERROR", sprintf("mapper %y v%y is unknown", name, ver);
    }
    return Qorus.mappers.get(mid, rtopts);
}

#! checks if the given module is loaded and returns the feature name
string sub qorus_check_module(string mod, reference<bool> loaded) {
    # get feature name
    string feature_name = (mod =~ /\.qm$/)
        ? basename_ext(mod, ".qm")
        : mod;
    loaded = exists get_module_hash(){feature_name};
    return feature_name;
}

const IX_PGM_MOD_FAKE_WF  = (1 << 0);
const IX_PGM_MOD_FAKE_SVC = (1 << 1);
const IX_PGM_MOD_FAKE_JOB = (1 << 2);

#! loads the given module and returns the module name to cover the case when the argument is an absolute path
/** requires injection; cannot be in the client module
*/
string sub qorus_load_interface_module(int fake_api_mask, string mod, list<string> class_list) {
    bool loaded;
    string feature_name = qorus_check_module(mod, \loaded);
    if (!loaded) {
        InterfaceModuleProgram pgm();

%ifdef QorusCore
        # load in all APIs equally
        map pgm.importClass($1), CommonClassList;
        map pgm.importClass($1), WorkflowOnlyClassList;
        map pgm.importClass($1), ServiceOnlyClassList;
        map pgm.importClass($1), JobOnlyClassList;
%else
        # load in fake APIs
        if (fake_api_mask & IX_PGM_MOD_FAKE_WF) {
            qorus_load_fake_api_module(pgm, "QorusFakeApiWorkflow");
        }
        if (fake_api_mask & IX_PGM_MOD_FAKE_SVC) {
            qorus_load_fake_api_module(pgm, "QorusFakeApiService");
        }
        if (fake_api_mask & IX_PGM_MOD_FAKE_JOB) {
            qorus_load_fake_api_module(pgm, "QorusFakeApiJob");
        }

        # load in interface API classes
        map pgm.importClass($1), class_list;
%endif

        # load in hashdecls
        map pgm.importHashDecl($1), CommonHashDeclList;
        # import omqservice object to program
        pgm.importGlobalVariable("omqservice");
        # load the module into the Program container
        pgm.loadApplyToUserModule(mod);
    }

    return feature_name;
}

#! loads a fake interface API module into the current program
sub qorus_load_fake_api_module(Program p, string name) {
    qorus_load_fake_api_module(name);
    p.loadModule(name);
}

#! loads fake interface API modules
sub qorus_load_fake_api_module(string name) {
    if (get_module_hash(){name}) {
        return;
    }
    Program pgm(PO_NO_USER_API | PO_NO_THREAD_CONTROL | PO_NO_PROCESS_CONTROL);
    pgm.define("QORUS_FAKE_API_MODULE", True);
    pgm.loadApplyToUserModule(name);
}

hash<string, bool> sub qorus_get_module_hash_from_option(string opt) {
    code get_feature = string sub (string arg) {
        return arg =~ /\.qm$/
            ? basename_ext(arg, ".qm")
            : arg;
    };
    return (map {get_feature($1): True}, Qorus.options.get(opt)) ?? {};
}

bool sub qorus_ex_client_dead(hash<ExceptionInfo> ex) {
    return ex.err == "CLIENT-TERMINATED" || ex.err == "CLIENT-ABORTED" || ex.err == "CLIENT-DEAD";
}

#! Oracle error codes getting an automatic datasource reset
/** reset the datasource connection if one of the following errors has been encountered:
    - ORA-01041: internal error. hostdef extension doesn't exist
    - ORA-0406[158]: invalid package state errors
    - ORA-06508: invalid package state error
    - ORA-2540[1-9]: cluster failover errors
*/
const OracleResetErrors = {
    "ORA-01041": True,
    "ORA-04061": True,
    "ORA-04065": True,
    "ORA-04058": True,
    "ORA-06508": True,
    "ORA-25401": True,
    "ORA-25402": True,
    "ORA-25403": True,
    "ORA-25404": True,
    "ORA-25405": True,
    "ORA-25406": True,
    "ORA-25407": True,
    "ORA-25408": True,
    "ORA-25409": True,
};

#! returns True if the exception is for a datasource error that requires a connection reset
bool sub ds_error_needs_reset(hash<auto> ex) {
    # currently only Oracle connections get a reset depending on the error
    if (ex.arg.alterr =~ /^ORA-/) {
        return OracleResetErrors{ex.arg.alterr} ?? False;
    }
    return False;
}

sub process_factory_args(reference<hash<auto>> ah) {
    foreach hash<auto> i in (ah.provider_options.pairIterator()) {
        if (check_template_arg_value(i.value)) {
            ah.template_options{i.key} = remove ah.provider_options{i.key};
        }
    }
}

bool sub check_template_arg_value(auto v) {
    switch (v.typeCode()) {
        case NT_STRING:
            return v =~ /([^\\]|^)\$[a-z][-a-z]+:({.*}|[a-zA-Z0-9_\.]|'.*')/;

        case NT_HASH: {
            foreach auto v0 in (v.iterator()) {
                if (check_template_arg_value(v0)) {
                    return True;
                }
            }
            return False;
        }

        case NT_LIST: {
            foreach auto e in (v) {
                if (check_template_arg_value(e)) {
                    return True;
                }
            }
            return False;
        }
    }

    return False;
}

%ifdef QorusDebugInternals
sub qdbg_assert(bool b) {
    if (!b)
        throw "ASSERT-ERROR", sprintf("stack: %N", get_stack());
}
sub qdbg_test_cluster_failover() {
    #if (!(rand() % 5))
    #    throw "TEST-CLUSTER-FAILOVER", "DB cluster failover simulation error";
}
sub qdbg_wait_to_continue() {
    /*
    if (is_file("/tmp/continue_all"))
        return;
    while (True) {
        if (!is_file("/tmp/continue")) {
            log(LoggerLevel::INFO, "waiting for file");
            sleep(1);
        } else
            break;
    }
    unlink("/tmp/continue");
    */
}

# lines with QDBG_* must be on one line
sub QDBG_LOG(string fmt) { if (Qorus) Qorus.logArgs(LoggerLevel::INFO, fmt, argv); else call_function_args(\qlog_args(), (LoggerLevel::INFO, fmt, argv)); }
sub QDBG_LOG(code func, string fmt) { call_function_args(func, (LoggerLevel::INFO, fmt, argv)); }
sub QDBG_ASSERT(auto v) { qdbg_assert(v.toBool()); }
sub QDBG_TEST_CLUSTER_FAILOVER() { qdbg_test_cluster_failover(); }
sub QDBG_WAIT_TO_CONTINUE() { qdbg_wait_to_continue(); }
%endif
