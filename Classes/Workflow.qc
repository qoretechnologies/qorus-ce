# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Workflow class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

# workflow api library
%include lib/qorus-workflow-api.ql

%new-style
%enable-all-warnings
%strict-args
%require-types

public namespace OMQ;

class OMQ::Workflow inherits CommonInterfaceBase, OMQ::WorkflowDef {
    public {
        # workflow program object
        WorkflowProgram pgm;

        # step name -> id map
        hash steprmap;

        # date/time cached
        date cached = now_us();

        # hash of step information
        hash stepinfo;

        # set of step classids: classid -> stepid
        hash<auto> step_classes;

        # set of step classes: lang -> stepid ("wf" for the wf class) -> class name -> True
        hash<auto> class_map = {};

        # handler info; handler name -> function name
        hash<string, string> handler;

        # error function name
        *string errorfunctionname;

        # temporary workflow instance ID
        string tempid;

        # Mutex for temporary workflow instance
        Mutex ml();

        # reset flag
        bool in_reset = False;

        # hash from mapper names to ids
        *hash mh;

        # hash from value map names to ids
        *hash vmh;

        # PerfCache object for performance events
        #PerformanceCache pc;

        # the workflow class name, if defined
        /** issue #3209: this is cleared if the workflow's Program object is deleted
        */
        object workflow_class_obj;

        # workflow class method flags
        /** valid methods:
            - \c attach
            - \c detach
            - \c onetimeinit
            - \c errorhandler
        */
        hash<string, bool> workflow_class_methods;

        # issue #3209 manage program object atomically
        Mutex pgm_lck();

        #! issue #3485: stepid / FSM trigger map: stepid -> trigger -> fsm info
        hash<string, hash<string, hash<auto>>> fsm_map;

%ifdef QorusCore
        # temporary workflow logger before SegmentWorkflowData initialization
        Logger tmp_logger;
%endif

        const StepTriggers = {
            "primary": True,
            "validation": True,
            "array": True,
            "end": True,
        };
    }

    static setThreadInit(Workflow wf) {
        ensure_create_tld();
        wf.setLogContext();
    }

    setLogContext() {
        QDBG_ASSERT(ensure_tld());
        tld += {
            "wf": self,
        };
    }

    private cacheSteps() {
        list<string> need_steps = ();

        foreach string stepid in (keys steps) {
            if (!exists stepinfo{stepid}) {
                need_steps += stepid;
            }
        }

        if (elements need_steps) {
            loadSteps(need_steps);
        }
    }

    constructor(softint wfid) {
        QDBG_ASSERT(ensure_tld());
        *hash<auto> q = Qorus.qmm.lookupWorkflow(wfid) - ("runtime-options", "source", "line");

        # check if workflow exists
        if (!q) {
            throw "NO-SUCH-WORKFLOW", sprintf("workflowid %d is not cached; to refresh the metadata cache, call REST "
                "API: \"qrest put system/metadata/reload/workflows\"", wfid);
        }

        # rename "deprecated" -> "depr"
        q.depr = remove q.deprecated;

        # map fields to workflow hash
        self += q;

%ifdef QorusCore
        setupTemporaryLogger(Qorus.qmm.lookupLogger("workflows", wfid).params);
%endif

        # get performance cache object
        #pc = Qorus.pcm.add("w" + workflowid);

        # set up mapper hash
        mh = map {$1.name: $1.mapperid}, mappers;

        # set up value map hash
        vmh = map {$1.name: $1.id}, vmaps;

        try {
            # make steprmap
            map steprmap.($1.value) = $1.key, stepmap.pairIterator();

            initWorkflowProgram();

            Qorus.logInfo("cached workflow %s/%s (id=%d)", q.name, q.version, wfid);
        } catch (hash<ExceptionInfo> ex) {
            *hash<ExceptionInfo> curr_ex = ex;
            # log full exception here
            while (curr_ex) {
                logError("failed to cache workflow: %s", get_exception_string(curr_ex));
                curr_ex = curr_ex.next;
            }
            throw "WORKFLOw-INIT-ERROR", sprintf("failed to cache workflow %s v%s (%d): %s: %s: %s; see workflow log "
                "for details", q.name, q.version, wfid, get_ex_pos(ex), ex.err, ex.desc), {
                    "already_logged": True,
                };
        }
    }

%ifdef QorusDebugInternals
    copy() {
        throw "WORKFLOW-COPY-ERROR";
    }
%endif

    destructor() {
        # deregister performance cache object
        #if (pc && Qorus.pcm)
        #    Qorus.pcm.del(pc);

%ifdef QorusDebugInternals
        #log(LoggerLevel::DEBUG, "Workflow::destructor() called: %N", get_stack());
        #printf("wf::destr wfid: %y %N\n", workflowid, get_stack());
%endif

        remove pgm;

        ml.lock();
        on_exit ml.unlock();

        if (tempid && Qorus.control)
            Qorus.control.temporaryWorkflowStopped(self);
    }

%ifdef QorusCore
    setupTemporaryLogger(*hash<LoggerParams> params) {
        if (params) {
            hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                "name": name,
                "id": workflowid.toString(),
                "version": version,
            };
            params = substituteLogFilename(params, LoggerController::getLoggerSubs("workflows", subs));
        }

        tmp_logger = createLogger(params);
        QDBG_LOG("logger for workflow %s v%s (%d) has been updated with params: %y",
            name, version, workflowid, params);
    }

    *Logger takeTemporaryLogger() {
        QDBG_LOG("removing temporary logger for workflow %s v%s (%d)", name, version, workflowid);
        return remove tmp_logger;
    }
%endif

    reset() {
        ml.lock();
        on_exit ml.unlock();

        in_reset = True;

        if (tempid) {
            Qorus.control.temporaryWorkflowStopped(self);
            delete tempid;
        }
    }

    runStepPrimaryArgs(softstring stepid, *softlist<auto> args) {
        # issue #1704: set thread-local variable for Qore object collection
        # in case Java is used (can also be used from Qore code)
        string oid = sprintf("%d-%d-%d", tld.wfe.workflow_instanceid, stepid, tld.ind);
        save_thread_data("_jni_save", oid);
        on_exit remove_thread_data(oid);
        # issue #3524: same for python
        save_thread_data("_python_save", oid);
        on_exit remove_thread_data(oid);

        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        hash<auto> step = stepinfo{stepid};

        # issue #3485: first run any FSM
        if (*hash<auto> fsm_info = fsm_map{stepid}.primary) {
            QorusFsmHandler::executeFsm(fsm_info.name, args);
        } else if (step.sfname) {
            pgm.callFunctionArgs(step.sfname, args);
        } else {
            QDBG_ASSERT(step.step_classid || step{"code"});
            call_object_method_args(pgm.getCreateObject(stepid, step.language, step.classname), "primary", args);
        }
    }

    *string runStepValidationArgs(softstring stepid, *softlist<auto> args) {
        # issue #1704: set thread-local variable for Qore object collection
        # in case Java is used (can also be used from Qore code)
        string oid = sprintf("%d-%d-%d", tld.wfe.workflow_instanceid, stepid, tld.ind);
        save_thread_data("_jni_save", oid);
        on_exit remove_thread_data(oid);
        # issue #3524: same for python
        save_thread_data("_python_save", oid);
        on_exit remove_thread_data(oid);

        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        hash<auto> step = stepinfo{stepid};
        auto rv;
        # issue #3485: first run any FSM
        if (*hash<auto> fsm_info = fsm_map{stepid}.validation) {
            QorusFsmHandler::executeFsm(fsm_info.name, args);
        } else if (step.vfname) {
            rv = pgm.callFunctionArgs(step.vfname, args);
        } else {
            QDBG_ASSERT(step.step_classid || step{"code"});
            rv = call_object_method_args(pgm.getCreateObject(stepid, step.language, step.classname), "validation", args);
        }

        if (exists rv && rv.typeCode() != NT_STRING) {
            throw "VALIDATION-ERROR", sprintf("validation for step %s v%s (%d) retured type %y; expecting a string status code instead", step.name, step.version, step.stepid, rv.type());
        }

        return rv;
    }

    softlist<auto> runStepArray(softstring stepid) {
        # issue #1704: set thread-local variable for Qore object collection
        # in case Java is used (can also be used from Qore code)
        string oid = sprintf("%d-%d-%d", tld.wfe.workflow_instanceid, stepid, tld.ind);
        save_thread_data("_jni_save", oid);
        on_exit remove_thread_data(oid);
        # issue #3524: same for python
        save_thread_data("_python_save", oid);
        on_exit remove_thread_data(oid);

        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        hash<auto> step = stepinfo{stepid};
        softlist<auto> rv;
        # issue #3485: first run any FSM
        if (*hash<auto> fsm_info = fsm_map{stepid}.array) {
            QorusFsmHandler::executeFsm(fsm_info.name);
        } else if (step.afname) {
            rv = pgm.callFunction(step.afname);
        } else {
            QDBG_ASSERT(step.step_classid || step{"code"});
            rv = call_object_method_args(pgm.getCreateObject(stepid, step.language, step.classname), "array");
        }

        return rv;
    }

    runStepAsyncEndArgs(softstring stepid, *softlist<auto> args) {
        # issue #1704: set thread-local variable for Qore object collection
        # in case Java is used (can also be used from Qore code)
        string oid = sprintf("%d-%d-%d", tld.wfe.workflow_instanceid, stepid, tld.ind);
        save_thread_data("_jni_save", oid);
        on_exit remove_thread_data(oid);
        # issue #3524: same for python
        save_thread_data("_python_save", oid);
        on_exit remove_thread_data(oid);

        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        hash<auto> step = stepinfo{stepid};
        # issue #3485: first run any FSM
        if (*hash<auto> fsm_info = fsm_map{stepid}.end) {
            QorusFsmHandler::executeFsm(fsm_info.name, args);
        } else if (step.efname) {
            pgm.callFunctionArgs(step.efname, args);
        } else {
            QDBG_ASSERT(step.step_classid || step{"code"});
            call_object_method_args(pgm.getCreateObject(stepid, step.language, step.classname), "end", args);
        }
    }

    *hash<auto> getDefaultStepData(softstring stepid) {
        QDBG_ASSERT(stepinfo{stepid});
        hash<auto> step = stepinfo{stepid};
        if (!step.step_classid && !step{"code"}) {
            return;
        }
        return call_object_method_args(pgm.getCreateObject(stepid, step.language, step.classname),
                                       "getDefaultStepData");
    }

    bool stepHasValidation(softstring stepid) {
        return fsm_map{stepid}.validation || exists stepinfo{stepid}.vfname || exists stepinfo{stepid}.step_classid ||
            exists stepinfo{stepid}{"code"};
    }

    string setTemporaryThreadContext(softint wfiid, *ThreadLocalData th) {
        QDBG_ASSERT(ensure_tld());
        {
            ml.lock();
            on_exit ml.unlock();

            if (in_reset)
                throw "RESET-ERROR", sprintf("workflow %s v%s (%d) is already being reset", name, version, workflowid);

            if (!tempid)
                tempid = Qorus.control.createTemporaryWorkflowInstance(self);
        }

        QDBG_LOG("Workflow::setTemporaryThreadContext() index %y -> %y", tld.index, tempid);
        tld += {
            "wf": self,
            "index": tempid,
            #"workflow_instanceid": wfiid,
        };
        if (th)
           tld.add(th);
        return tempid;
    }

    string enrichLogMsg(string msg, auto args) {
        string fmsg = vsprintf(msg, args);

        *softint si = tld.stepID;
        if (si) {
            *softint ind = tld.ind;
            if (exists ind) {
                fmsg = sprintf("%s(%d/%d): %s", tld.stepName, si, ind, fmsg);
            } else {
                fmsg = sprintf("%s(%d): %s", tld.stepName, si, fmsg);
            }
        }

        *softint wi = tld.wfe.workflow_instanceid;
        if (wi) {
            fmsg = sprintf("WI %d: %s", wi, fmsg);
        }

        *softstring index = tld.index;
        if (index) {
            fmsg = sprintf("ID %s: %s", index, fmsg);
        }
        return fmsg;
    }

    logArgs(int level, string fmt, auto args) {
%ifdef QorusCore
        string fmsg = enrichLogMsg(fmt, args);
        if (*Logger l = tmp_logger) {
            SegmentWorkflowData::staticLogArgs(self, l, level, "%s", fmsg);
            return;
        }
        code meth;
        # maps from logger levels to SegmentManager log methods
        meth = {
            LoggerLevel::FATAL: \SM.wfLogFatal(),
            LoggerLevel::ERROR: \SM.wfLogError(),
            LoggerLevel::WARN: \SM.wfLogWarn(),
            LoggerLevel::INFO: \SM.wfLogInfo(),
            LoggerLevel::DEBUG: \SM.wfLogDebug(),
            LoggerLevel::TRACE: \SM.wfLogTrace(),
        }{level} ?? \SM.wfLogTrace();
        meth(workflowid, "%s", fmsg);
%else
        # the log message is enriched by the call below
        Qorus.logArgs(level, fmt, args);
%endif
    }

    private logArgs(string msg, code log, auto args) {
%ifdef QorusCore
        string fmsg = enrichLogMsg(msg, args);
        # log to segment workflow data logger through SegmentManager
        log(workflowid, fmsg);
%else
        string fmsg = vsprintf(msg, args);
        # log to process (qwf, qsvc, qjob) logger
        log("%s", fmsg);
%endif
    }

    logFatal(string msg) {
        code log;
%ifdef QorusCore
        if (*Logger l = tmp_logger) {
            SegmentWorkflowData::staticLogArgs(self, l, LoggerLevel::FATAL, "%s", enrichLogMsg(msg, argv));
            return;
        }
        log = \SM.wfLogFatal();
%else
        log = \Qorus.logFatal();
%endif
        logArgs(msg, log, argv);
    }

    logError(string msg) {
        code log;
%ifdef QorusCore
        if (*Logger l = tmp_logger) {
            SegmentWorkflowData::staticLogArgs(self, l, LoggerLevel::ERROR, "%s", enrichLogMsg(msg, argv));
            return;
        }
        log = \SM.wfLogError();
%else
        log = \Qorus.logError();
%endif
        logArgs(msg, log, argv);
    }

    logWarn(string msg) {
        code log;
%ifdef QorusCore
        if (*Logger l = tmp_logger) {
            SegmentWorkflowData::staticLogArgs(self, l, LoggerLevel::WARN, "%s", enrichLogMsg(msg, argv));
            return;
        }
        log = \SM.wfLogWarn();
%else
        log = \Qorus.logWarn();
%endif
        logArgs(msg, log, argv);
    }

    logInfo(string msg) {
        code log;
%ifdef QorusCore
        if (*Logger l = tmp_logger) {
            SegmentWorkflowData::staticLogArgs(self, l, LoggerLevel::INFO, "%s", enrichLogMsg(msg, argv));
            return;
        }
        log = \SM.wfLogInfo();
%else
        log = \Qorus.logInfo();
%endif
        logArgs(msg, log, argv);
    }

    logDebug(string msg) {
        code log;
%ifdef QorusCore
        if (*Logger l = tmp_logger) {
            SegmentWorkflowData::staticLogArgs(self, l, LoggerLevel::DEBUG, "%s", enrichLogMsg(msg, argv));
            return;
        }
        log = \SM.wfLogDebug();
%else
        log = \Qorus.logDebug();
%endif
        logArgs(msg, log, argv);
    }

    logTrace(string msg) {
        code log;
%ifdef QorusCore
        if (*Logger l = tmp_logger) {
            SegmentWorkflowData::staticLogArgs(self, l, LoggerLevel::TRACE, "%s", enrichLogMsg(msg, argv));
            return;
        }
        log = \SM.wfLogTrace();
%else
        log = \Qorus.logTrace();
%endif
        logArgs(msg, log, argv);
    }

    clearRemote() {
        if (remote) {
            remote = False;
        }
        if (!pgm) {
            createWorkflowProgram();
        }
    }

    setRemote() {
        if (!remote) {
            remote = True;

            # delete any cached workflow Program object, as it should not be needed anymore

            # issue #3209: ensure changes to Program object are made atomically
            pgm_lck.lock();
            on_exit pgm_lck.unlock();

            if (pgm) {
                remove pgm;
                remove workflow_class_obj;
            }
        }
    }

    private initWorkflowProgram() {
        # only create the Program container in qorus-core for non-remote workflows
%ifdef QorusCore
        if (!remote) {
            createWorkflowProgram();
        }
%else
        # always create the Program container in qwf processes
        createWorkflowProgram();
%endif
    }

    private Program createWorkflowProgram(*reference<*object> workflow_class_obj_ref) {
        # issue #3209: ensure changes to Program object are made atomically
        pgm_lck.lock();
        on_exit pgm_lck.unlock();

        if (!pgm) {
            pgm = new WorkflowProgram(Qorus.options.get(), Qorus.getRuntimeProps());

            # issue #1929: ensure that thread-local data is set in any threads started by foreign modules such as jni
            pgm.setThreadInit(sub () {Workflow::setThreadInit(self);});

            # load in workflow classes
            map pgm.importClass($1), WorkflowClassList;
            # load in hashdecls
            map pgm.importHashDecl($1), CommonHashDeclList;
            # set the program name for the debugger
            pgm.setProgramName(workflowid, name, version);

            # load required workflow modules
            if (workflow_modules) {
                map pgm.loadModule(qorus_load_workflow_module($1)), workflow_modules.split(",");
            }

            # import all library functions to workflow program
            foreach auto func in (OMQ::WorkflowAPI) {
                if (exists func.import) {
                    pgm.importFunction(func.actual, func.import);
                } else {
                    pgm.importFunction(func);
                }
            }

            # export system objects to workflow program
            pgm.importGlobalVariable("omqservice");

            # load workflow library
            loadLibrary();

            # load workflow functions
            if (attach_func_instanceid) {
                handler.attach = loadFunctionId(attach_func_instanceid);
            }

            if (detach_func_instanceid) {
                handler.detach = loadFunctionId(detach_func_instanceid);
            }

            if (onetimeinit_func_instanceid) {
                handler.onetimeinit = loadFunctionId(onetimeinit_func_instanceid);
            }

            if (errhandler_func_instanceid) {
                handler.error_handler = loadFunctionId(errhandler_func_instanceid);
            }

            if (errorfunction_instanceid) {
                errorfunctionname = loadFunctionId(errorfunction_instanceid);
            }

            # cache steps
            cacheSteps();

            if (class_name) {
                *string code_;
                *string label;
                if (language != "java") {
                    code_ = omqp.selectRow("select code from workflows where workflowid = %v", workflowid){"code"};
                    label = sprintf("workflow: %s v%s (%d)", name, version, workflowid);
                }
                hash<auto> info = {
                    "code": code_,
                    "label": label,
                    "classname": class_name,
                    "language": language,
                    "language_info": language_info,
                };
                hash<auto> wf_tags = sqlif.getTags("workflow", workflowid);
                cacheClass("wf", info, wf_tags);
            }

            tld.wf = self;
            # issue #3403: set interface context; necessary also in qwf processes during initialization
            WorkflowContextHelper ixctx();

            # issue #3432: ensure that transient data is always local to the current execution object
            TransientDataHelper transient_data_helper();

            pgm.parseCommit(class_map);

            if (class_name) {
                #QDBG_LOG("lang_data: %N", pgm.lang_data);
                workflow_class_obj = pgm.getCreateObject("wf", language, class_name);

                # get the workflow base class
                Reflection::Class workflow_base_cls = language == "qore"
                    ? Reflection::Class::forName(pgm, "OMQ::UserApi::Workflow::QorusWorkflow")
                    : Reflection::Class::forName(pgm, "com::qoretechnologies::qorus::workflow::QorusWorkflow");

                # set workflow method flags for reimplemented workflow methods
                Reflection::Class workflow_cls = Class::getClass(workflow_class_obj);
                workflow_class_methods = {
                    "attach": !workflow_cls.findNormalMethod("attachImpl").method.getClass().isEqual(workflow_base_cls),
                    "detach": has_detach,
                    "onetimeinit": !workflow_cls.findNormalMethod("oneTimeInitImpl").method.getClass().isEqual(workflow_base_cls),
                    "errorhandler": !workflow_cls.findNormalMethod("errorHandlerImpl").method.getClass().isEqual(workflow_base_cls),
                };
                QDBG_ASSERT(has_detach == !workflow_cls.findNormalMethod("detachImpl").method.getClass().isEqual(workflow_base_cls));
            }

            if (errorfunction_instanceid && !Qorus.EM.hasWorkflow(workflowid)) {
                # save workflow object in thread-local data for a possible call to getWorkflowMetadata()
                tld._wf = self;
                on_exit { tld._wf = NOTHING; }

                # issue #1704: set thread-local variable for Qore object collection
                # in case Java is used (can also be used from Qore code)
                string oid = sprintf("errorfunc-%d", workflowid);
                save_thread_data("_jni_save", oid);
                on_exit remove_thread_data(oid);
                # issue #3524: same for python
                save_thread_data("_python_save", oid);
                on_exit remove_thread_data(oid);

                *hash errors = pgm.callFunction(errorfunctionname);
                # FIXME: validate structure (hash of hashes) - also in wf validation
                # validate retry-delay type
                foreach string err in (keys errors) {
                    hash eh = errors{err};
                    auto v = eh."retry-delay";
                    if (exists v &&
                        (!inlist(v.typeCode(), (NT_INT, NT_DATE)) || (v.typeCode() == Type::Date && v.absolute()))) {
                        logWarn("WARNING: workflow %s/%s's error function defined error %y with an invalid "
                            "\"retry-delay\" key; \"retry-delay\" must be either an integer (giving seconds until "
                            "the next retry) or a relative date; value given: %y", name, version, err, v);
                        delete eh."retry-delay";
                    }

                    # only update the workflow-specific error if it hasn't already been manually updated
                    if (!Qorus.EM.hasManuallyUpdatedWorkflowError(workflowid, err)) {
                        Qorus.EM.updateError(workflowid, ("error": err) + eh, True);
                    }
                }
            }
        }
        workflow_class_obj_ref = workflow_class_obj;
        return pgm;
    }

    private loadLibrary() {
        hash<auto> mappers;
        qorus_load_library(lib, pgm, sub (string msg) { logInfo(msg); }, \mappers);
        # add pipeline and FSM mappers
        mh += map {$1.name: $1.id}, mappers.values();
    }

    private string loadFunctionIntern(hash<auto> fq, softint id) {
        # issue #2282: ensure functions are only loaded once
        if (pgm.lib_cache_func{id}) {
            return fq.name;
        }
        pgm.lib_cache_func{id} = True;

        *hash<auto> th = sqlif.getTags("function_instance", id).sys;

        string desc = sprintf("%s()/%s(%d) %d bytes", fq.name, fq.version, id, fq.body.size());
        if (th.source) {
            th.source = basename(th.source);
            desc += sprintf(" (source %y:%d)", th.source, th.offset);
        }
        else if (th) {
            th -= ("source", "offset");
        }

        logInfo("caching function %s", desc);
        string label = sprintf("function: %s v%s (%d)", fq.name, fq.version, id);
        pgm.parsePending(fq.body, label, 0, th.source, th.offset);
        return fq.name;
    }

    private string loadClassIntern(hash<auto> cq, softint id, *reference<auto> dep_hash) {
        # ensure classes are only loaded once
        if (pgm.lib_cache_class{id}) {
            return cq.name;
        }
        pgm.lib_cache_class{id} = True;

        # load required objects first
        if (dep_hash{id}) {
            throw "WORKFLOW-CLASS-ERROR", sprintf("class %d has a circular dependency on itself", id);
        }
        *list<softint> requires = Qorus.qmm.lookupClass(id).requires;
        if (requires) {
            dep_hash{id} = True;
            foreach int dep_classid in (requires) {
                *hash<auto> info = Qorus.qmm.lookupClass(dep_classid);
                # set stepid for all class dependencies to the same stepid as this class
                step_classes{dep_classid} = step_classes{id};
                loadClassIntern(info, dep_classid, \dep_hash);
            }
        }

        *hash<auto> tags = sqlif.getTags("class", id);
        string desc = sprintf("%s()/%s(%d) lang %s %d bytes", cq.name, cq.version, id, cq.language, cq.body.size());
        if (tags.sys.source) {
            tags.sys.source = basename(tags.sys.source);
            desc += sprintf(" (source %y:%d)", tags.sys.source, tags.sys.offset);
        } else if (tags.sys) {
            tags.sys -= ("source", "offset");
        }

        logInfo("caching class %s", desc);
        *string label;
        if (cq.language == "qore") {
            label = sprintf("class: %s v%s (%d)", cq.name, cq.version, id);
        }
        hash<auto> info = {
            "code": cq.body,
            "language": cq.language,
            "language_info": cq.language_info,
            "label": label,
            "classname": cq.name
        };
        cacheClass(step_classes{id}, info, tags);
        return cq.name;
    }

    # returns function name
    private string loadFunctionId(softint id) {
        # get function definition
        *hash<auto> fq = sqlif.workflowLoadFunctionID(id);
        if (!fq) {
            throw "FUNCTION-ERROR", sprintf("can't load function_instanceid %d: no such function", id);
        }

        return loadFunctionIntern(fq, id);
    }

    private loadFunctionIds(list<auto> funclist) {
        # create select string for function instance retrieval
        *hash<auto> q = sqlif.workflowLoadFunctionIDs(funclist);

        # parse functions
        context (q) {
            if (!pgm.existsFunction(%name)) {
                loadFunctionIntern(%%, %function_instanceid);
            }
        }
    }

    private loadClassIds(list<int> classlist) {
        # create select string for class instance retrieval
        foreach int id in (classlist) {
            hash<auto> info = Qorus.qmm.lookupClass(id);
            loadClassIntern(info, id);
        }
    }

    # id == wf for the workflow class, id == stepid for step classes
    private:internal cacheClass(softstring id, hash<auto> info, hash<auto> tags) {
        if (info.language == "qore") {
            pgm.parsePending(info{"code"}, info.label ?? info.classname, 0, tags.sys.source, tags.sys.offset);
            class_map.qore{id}{info.classname} = True;
        } else if (info.language == "java") {
            *string main_class_name = pgm.cacheJavaClass(info.classname, info.language_info, True, tags.classpath);
            if (main_class_name) {
                class_map.java{id}{main_class_name} = True;
            }
        } else if (info.language == "python") {
            pgm.cachePythonClass(info.classname, info."code", info.language_info, True, tags.module_path);
        } else {
            throw "WORKFLOW-ERROR", sprintf("workflow %s:%s (%d) requires support for unsupported language %y", name,
                version, workflowid, info.language);
        }
    }

    private:internal loadStepCode(softstring stepid) {
        hash<auto> step_tags = sqlif.getTags("step", stepid);
        cacheClass(stepid, stepinfo{stepid}, step_tags);
    }

    private loadSteps(list<auto> step_list) {
        *hash<auto> q = Qorus.qmm.lookupStep(step_list, True);
        if (elements q != elements step_list) {
            # report stepids not returned from omqmap service
            throw "WORKFLOW-ERROR", sprintf("workflow %s:%s (%d) requires stepid(s): %y that cannot be mapped to "
                "step defintions, please check the workflow definition again and reload the metadata cache if "
                "necessary (ex: qrest put system/metadata/reload/workflows)", name, version, workflowid,
                (map $1, step_list, !q{$1}));
        }

        # delete "stepid" from step hashes
        map delete q.$1.stepid, keys q;

        stepinfo = q;

        #printf("step_list: %y steps: %N\n stepinfo: %N", step_list, steps, stepinfo);

        #logInfo("%d step%s loaded", elements q.stepid, elements q.stepid == 1 ? "" : "s");

        # load all functions not already cached

        hash<string, bool> func_hash;
        foreach softstring stepid in (step_list) {
            if (stepinfo{stepid}.sfname) {
                if (!pgm.existsFunction(stepinfo{stepid}.sfname)) {
                    func_hash{stepinfo{stepid}.stepfunction_instanceid} = True;;
                }

                # check for validation function
                if (stepinfo{stepid}.validationfunction_instanceid && !pgm.existsFunction(stepinfo{stepid}.vfname)) {
                    func_hash{stepinfo{stepid}.validationfunction_instanceid} = True;
                }

                # check for array function
                if (stepinfo{stepid}.arrayfunction_instanceid && !pgm.existsFunction(stepinfo{stepid}.afname)) {
                    func_hash{stepinfo{stepid}.arrayfunction_instanceid} = True;
                }

                # check for end function (asynchronous step)
                if (stepinfo{stepid}.endfunction_instanceid &&
                    !pgm.existsFunction(stepinfo{stepid}.efname)) {
                    func_hash{stepinfo{stepid}.endfunction_instanceid} = True;
                }
            } else if (stepinfo{stepid}.step_classid) {
                step_classes{stepinfo{stepid}.step_classid} = stepid;
                stepinfo{stepid}.language = stepinfo{stepid}.language;
            } else {
                QDBG_ASSERT(stepinfo{stepid}{"code"});
                loadStepCode(stepid);
            }

            # check for queue info
            if (stepinfo{stepid}.queueid) {
                *hash<auto> qi = Qorus.qmm.lookupQueue(stepinfo{stepid}.queueid);
                if (!qi) {
                    throw "INVALID-QUEUE", sprintf("queueid %d does not exist", stepinfo{stepid}.queueid);
                }
                stepinfo{stepid}.queuename = qi.name;
            }

            # check event info
            if (stepinfo{stepid}.workflow_event_typeid) {
                *hash<auto> ei = Qorus.qmm.lookupEvent(stepinfo{stepid}.workflow_event_typeid);
                if (!ei) {
                    throw "INVALID-EVENT-TYPE", sprintf("step %d refers to event type ID %d which does not exist", stepid, stepinfo{stepid}.workflow_event_typeid);
                }
                stepinfo{stepid}.eventtype = ei.name;
            }

            # issue #3485: check FSM triggers for step
            foreach hash<auto> i in (stepinfo{stepid}.fsm_triggers.pairIterator()) {
                hash<auto> fsm_info = Qorus.qmm.lookupFsm(i.key);
                map fsm_map{stepid}{$1.method} = fsm_info, i.value, StepTriggers{$1.method};
            }
        }
        if (func_hash) {
            loadFunctionIds(map $1.toInt(), keys func_hash);
        }
        if (step_classes) {
            loadClassIds(map $1.toInt(), keys step_classes);
        }

        #logInfo("%d function%s cached", elements q.body, elements q.body == 1 ? "" : "s");
    }

    bool hasOneTimeInit() {
        return workflow_class_methods.onetimeinit || handler.onetimeinit;
    }

    bool hasAttach() {
        return workflow_class_methods.attach || handler.attach;
    }

    bool hasDetach() {
        return has_detach;
    }

    bool hasErrorHandler() {
        return workflow_class_methods.errorhandler || handler.error_handler;
    }

    callOneTimeInit() {
        # issue #1704: set thread-local variable for Qore object collection
        # in case Java is used (can also be used from Qore code)
        string oid = sprintf("onetimeinit-%d", tld.wfe.workflow_instanceid);
        save_thread_data("_jni_save", oid);
        on_exit remove_thread_data(oid);
        # issue #3524: same for python
        save_thread_data("_python_save", oid);
        on_exit remove_thread_data(oid);

%ifdef QorusCore
        # issue #3319: set interface context; at runtime only necessary for qorus-core
        WorkflowContextHelper ixctx();
%endif

        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        if (workflow_class_methods.onetimeinit) {
            call_object_method(workflow_class_obj, "oneTimeInit");
        } else if (handler.onetimeinit) {
            pgm.callFunction(handler.onetimeinit);
        }
    }

    callAttach() {
        # issue #1704: set thread-local variable for Qore object collection
        # in case Java is used (can also be used from Qore code)
        string oid = sprintf("attach-%d", tld.wfe.workflow_instanceid);
        save_thread_data("_jni_save", oid);
        on_exit remove_thread_data(oid);
        # issue #3524: same for python
        save_thread_data("_python_save", oid);
        on_exit remove_thread_data(oid);

%ifdef QorusCore
        # issue #3319: set interface context; at runtime only necessary for qorus-core
        WorkflowContextHelper ixctx();
%endif

        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        if (workflow_class_methods.attach) {
            call_object_method(workflow_class_obj, "attach");
        } else if (handler.attach) {
            pgm.callFunction(handler.attach);
        }
    }

    # call the detach logic
    /** this is the only workflow logic that can be called asynchronously to workflow execution;
        it can be called in qorus-core for remote workflows with detach logic that are not currently running

        when the remote flag is changed from local to remote, any cached Program instance is deleted
    */
    callDetach() {
        if (!has_detach) {
            return;
        }
        # issue #3209: ensure changes to Program object are made atomically
        # here we get a reference to the Program object in case the workflow is changed from remote to local while
        # running the detach logic, which can be run in qorus-core
        *object workflow_class_obj;
        Program pgm = createWorkflowProgram(\workflow_class_obj);
        # issue #1704: set thread-local variable for Qore object collection
        # in case Java is used (can also be used from Qore code)
        string oid = sprintf("detach-%d", tld.wfe.workflow_instanceid);
        save_thread_data("_jni_save", oid);
        on_exit remove_thread_data(oid);
        # issue #3524: same for python
        save_thread_data("_python_save", oid);
        on_exit remove_thread_data(oid);

%ifdef QorusCore
        # issue #3319: set interface context; at runtime only necessary for qorus-core
        WorkflowContextHelper ixctx();
%endif

        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        QDBG_LOG("callDetach() wcm: %y handler: %y", workflow_class_methods, handler);

        if (workflow_class_methods.detach) {
            call_object_method_args(workflow_class_obj, "detach", argv);
        } else if (handler.detach) {
            pgm.callFunctionArgs(handler.detach, argv);
        }
    }

    callErrorHandler() {
        # issue #1704: set thread-local variable for Qore object collection
        # in case Java is used (can also be used from Qore code)
        string oid = sprintf("errorhandler-%d", tld.wfe.workflow_instanceid);
        save_thread_data("_jni_save", oid);
        on_exit remove_thread_data(oid);
        # issue #3524: same for python
        save_thread_data("_python_save", oid);
        on_exit remove_thread_data(oid);

%ifdef QorusCore
        # issue #3319: set interface context; at runtime only necessary for qorus-core
        WorkflowContextHelper ixctx();
%endif

        # issue #3432: ensure that transient data is always local to the current execution object
        TransientDataHelper transient_data_helper();

        try {
            if (workflow_class_methods.errorhandler) {
                call_object_method_args(workflow_class_obj, "errorHandler", argv);
            } else if (handler.error_handler) {
                pgm.callFunctionArgs(handler.error_handler, argv);
            }
        } catch (hash<ExceptionInfo> ex) {
            logError("exception in error handler: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
        }
    }

    #! Returns runtime options
    *hash<auto> getRuntimeOptionsImpl() {
        return Qorus.qmm.lookupWorkflow(workflowid)."runtime-options";
    }

    #! Sets options persistently
    setOptionsImpl(hash<auto> h) {
        Workflow::setWorkflowOption(workflowid, h, True);
    }

    setDelayOptions() {
        *hash<auto> h = Qorus.qmm.lookupWorkflow(workflowid)."runtime-options";

        if (exists h.async_delay)
            SM.updateAsyncDelay(workflowid, h.async_delay);
        else if (exists options.recover_delay)
            SM.updateRetryDelay(workflowid, h.recover_delay);
    }

    #! supports ServiceApi::getCallContext()
    hash<auto> getContextInfo() {
        return self{WorkflowCallContextKeys};
    }

    Mapper getMapper(string mapname, *hash<auto> rtopts) {
        if (mh{mapname})
            return Qorus.mappers.get(mh{mapname}, rtopts);

        throw "MAPPER-ERROR", sprintf("mapper %y is not a valid mapper for workflow %s v%s (%d); valid mappers: %y", mapname, name, version, workflowid, mh.keys());
    }

    AbstractIterator getMapperIterator(string mapname, AbstractIterator input, *hash<auto> rtopts) {
        if (mh{mapname})
            return Qorus.mappers.getIterator(mh{mapname}, input, rtopts);

        throw "MAPPER-ERROR", sprintf("mapper %y is not a valid mapper for workflow %s v%s (%d); valid mappers: %y", mapname, name, version, workflowid, mh.keys());
    }

    auto getValueMap(string mapname, string key) {
        if (vmh{mapname})
            return Qorus.qmm.getVMapValue(mapname, key);

        throw "VALUE-MAP-ERROR", sprintf("value map %y is not a valid value map for workflow %s v%s (%d); valid value maps: %y", mapname, name, version, workflowid, vmh.keys());
    }

    list<auto> getValueMaps() {
        return Qorus.qmm.getVMapMap(){vmh.keys()}.values();
    }

    Program getProgram() {
        return pgm;
    }

    auto getConfigItemValue(softstring stepid, string name, *hash<auto> local_context, bool expand_complex_values = True) {
        *hash<auto> config_info = stepinfo{stepid}.config{name};
        if (!config_info) {
            throw "CONFIG-ITEM-ERROR", sprintf("config item %y is unknown; known config items: %y", name,
                keys stepinfo{stepid}.config);
        }

        return getConfigItemValueIntern(stepid, name, config_info, local_context, expand_complex_values);
    }

    private auto getConfigItemValueIntern(softstring stepid, string name, hash<auto> config_info,
            *hash<auto> local_context, bool expand_complex_values = True) {
        *string level;
        bool is_set;
        auto value = Qorus.qmm.findConfigItemValue("step", stepid, name, config_info, \level, \is_set, workflowid);
        if (!config_info.allowed_values) {
            value = UserApi::expandTemplatedValue(value, local_context, expand_complex_values);
        }
        if (is_set) {
            # TODO: check type
            return value;
        }
        throw "CONFIG-ITEM-ERROR", sprintf("config item %y has neither a value nor a default value", name);
    }

    hash<auto> getConfigItemHash(softstring stepid, *hash<auto> local_context) {
        return (map {$1.key: getConfigItemValueIntern(stepid, $1.key, $1.value, local_context)},
            stepinfo{stepid}.config.pairIterator()) ?? {};
    }

    static setWorkflowOption(softint wfid, hash<auto> h, bool cached) {
        list<string> errs = ();

        foreach string k in (keys h) {
            try {
                h{k} = Qorus.qmm.updateWorkflowOptionErr(wfid, k, h{k});
                if (cached) {
                    if (k == "async_delay")
                        SM.updateAsyncDelay(wfid, h{k});
                    else if (k == "recover_delay")
                        SM.updateRetryDelay(wfid, h{k});
                }
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "WORKFLOW-OPTION-ERROR") {
                    errs += ex.desc;
                } else {
                    rethrow;
                }
            }
        }

        if (errs)
            throw "WORKFLOW-OPTION-ERROR", (foldl $1 + "; " + $2, errs);
    }
}

sub wilog(int lvl, string msg) {
    OMQ::Workflow wf = tld.wf;
    wf.logArgs(convert_old_log_level(lvl), msg, argv);
}

sub wilog_args(int lvl, string msg, *softlist<auto> args) {
    OMQ::Workflow wf = tld.wf;
    wf.logArgs(convert_old_log_level(lvl), msg, args);
}
