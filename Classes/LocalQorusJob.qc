# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Local Job Class Definition

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

class OMQ::LocalQorusJob inherits CommonInterfaceBase, AbstractQorusJob {
    public {}

    private {
        # interval to check for job quit when another job instance is still running
        const RunCheckInterval = 1s;

        # date/time job was cached
        date cached = now_us();

        # is this job class-based?
        softbool class_based;

        # the class name for class-based jobs
        *string class_name;

        # languageg of the job
        string language;

        # object for class-based jobs; base class depends on language
        object job_object;

        # db description of job
        string description;

        # flag is True if the job should be run if skipped do to system downtime
        softbool run_skipped;

        #! timestamp that the current job instance was started
        *date started;

        # date of last execution
        *date last_executed;

        # job instance id of the last executed one
        *int last_executed_job_instanceid;

        # expiry date
        *date expiry_date;

        # active flag
        softbool active;

        # date of next execution
        date next;

        # custom trigger time
        *date custom_trigger;

        # hash of library info as returned by lookupJob()
        *hash lib;

        # timer object
        CronTimer timer;

        # job program
        JobProgram pgm;

        # lock for blocking and atomic status updates - use with variable \c c
        # and for locking of quit and waiting
        Mutex m();

        #! lock for atomic info updates
        Mutex info_lck();

        # condition object
        Condition c();

        # condition for signal that the job is currently running
        int nrun = 0;
        Condition crun();

        # waiting flag - job is waiting on condition \c c for next scheduled run time
        # use in \c m lock
        bool waiting = False;

        # quit flag - job is requested to stop, use in \c m lock
        bool quit = False;

        # counter to signal that background thread is done
        Counter jc();

        # the TID of the job's background thread
        *int tid;

        # error flag
        bool error = False;

        # job instance id
        int job_instanceid;

        # job options
        hash options = {};

        # flag for recurring timers
        bool recurring = False;

        # hash from mapper names to ids
        *hash<string, int> mh;

        # hash from value map names to ids
        *hash<string, int> vmh;

        # stop warning
        bool stop_warn = False;

        # PerfCache object for the entire job as a whole
        #PerformanceCache pc;

        # last job error
        *string lasterr;
        # last job error description
        *string lasterrdesc;

        # config item hash
        *hash<auto> config;

        #! FSM info for any FSM for the run method
        *hash<auto> run_fsm;

        #! Job user info hash
        *hash<auto> jinfo;
    }

    constructor(int jobid, string name, string version) : AbstractQorusJob(jobid, name, version) {
    }

    init(hash<auto> jh, bool skip_checks = False, *string reason) {
        QDBG_ASSERT(jh.name == name && jh.version == version);
        self += jh.("jobid", "language", "class_based", "class_name", "config");

        if (class_based && !class_name) {
            class_name = name;
        }

        if (!jh.source) {
            jh -= ("source", "offset");
        }

        # get performance cache object
        #pc = Qorus.pcm.add("j" + jobid);

        # create timer object
        timer = jh.recurring
            ? new CronTimer(seconds(jh.recurring))
            : new CronTimer(jh.minute, jh.hour, jh.day, jh.month, jh.wday);

        if (jh.recurring) {
            recurring = True;
        }

        # get next execution date
        date start = jh.run_skipped && jh.last_executed
            ? (jh.recurring ? jh.last_executed : jh.last_executed + 1m)
            : LocalQorusJob::getStart();
        next = timer.findNext(start);
        if (next < now()) {
            next = LocalQorusJob::getStart(now() - 1m);
        }

        # set active flag
        active = jh.active;

        # do checks if checks have not been disabled
        if (!skip_checks) {
            # do not start job if it should not be active
            if (!jh.active) {
                throw "JOB-ERROR", sprintf("jobid %d (%y) is inactive and therefore cannot be started; call "
                    "omq.system.job.set-active(%y, True) to activate the job and it will be started automatically",
                    jobid, name, name);
            }

            # do not start the job if the expiry date is on or before the next trigger date/time
            if (jh.expiry_date && jh.expiry_date <= next) {
                throw "JOB-EXPIRY-ERROR", sprintf("jobid %d (%y) expires on %y, which is on or before the next "
                    "trigger date %y, therefore the job cannot be started; to start the job, change or remove the "
                    "expiry date by calling omq.system.job.set-expiry(%y)", jobid, name, jh.expiry_date, next, name);
            }
        }

        # set attributes in current object
        self += jh.("description", "run_skipped", "last_executed", "last_executed_job_instanceid", "expiry_date", "lib");

        # set up mapper hash
        mh = map {$1.name: $1.mapperid}, jh.mappers;

        # set up value map hash
        vmh = map {$1.name: $1.id}, jh.vmaps;

        # issue #3485: check FSM triggers for job
        foreach hash<auto> i in (jh.fsm_triggers.pairIterator()) {
            # ignore non-method triggers
            foreach hash<auto> ti in (i.value) {
                if (!ti.method) {
                    continue;
                }
                if (ti.method != "run") {
                    throw "JOB-ERROR", sprintf("jobid %d (%y) lists Finite State Machine %y with a trigger for the "
                        "%y method; only a single \"run\" method trigger is allowed", jobid, name, i.key, ti.method);
                }
                if (run_fsm) {
                    throw "JOB-ERROR", sprintf("jobid %d (%y) has multiple Finite State Machines for the \"run\" "
                        "method trigger; only a single \"run\" method trigger is allowed", jobid, name);
                }
                run_fsm = Qorus.qmm.lookupFsm(i.key);
            }
        }

        # create job start reason object
        ActionReason startreason();
        startreason.set(tld.cx, reason);

        # select/update job info from DB and setup job program in a restartable transaction
        QorusRestartableTransaction trans();
        while (True) {
            # (re-)create Job program
            pgm = new JobProgram(Qorus.options.get(), Qorus.getRuntimeProps());
            pgm.setProgramName(jobid, name, version);
            # issue #1929: ensure that thread-local data is set in any threads started by foreign modules such as jni
            pgm.setThreadInit(sub () {LocalQorusJob::setThreadInit(self);});

            # load required job modules
            if (jh.job_modules) {
                map pgm.loadModule(qorus_load_job_module($1)), jh.job_modules.split(",");
            }

            # load in job classes
            map pgm.importClass($1), JobClassList;

            # load in hashdecls
            map pgm.importHashDecl($1), CommonHashDeclList;

            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # if there is a custom trigger time, use it if possible
                if (jh.custom_trigger && jh.custom_trigger > now() && jh.custom_trigger < next) {
                    custom_trigger = next = jh.custom_trigger;
                }

                pgm.parsePending("namespace OMQ { namespace UserApi {}}", "<job namespace setup>");

                # import all library functions to job program
                foreach auto func in (OMQ::JobAPI) {
                    if (exists func.import) {
                        pgm.importFunction(func.actual, func.import);
                    } else {
                        pgm.importFunction(func);
                    }
                }

                # export system objects to job program
                pgm.importGlobalVariable("omqservice");

                logInfo("loading %sactive jobid %d %s v%s run_skipped: %y; language: %y %s",
                    active ? "" : "in", jobid, name, version, run_skipped, language, startreason.getText());

                try {
                    loadLibrary();
                    if (language == "qore") {
                        string label = sprintf("job: %s v%s (%d)", name, version, jobid);
                        pgm.parsePending(jh."code", label, 0, jh.source, jh.line);
                    }
                    if (class_based) {
                        if (language == "qore") {
                            pgm.cacheQoreClassObject(class_name);
                        } else if (language == "java") {
                            *hash<auto> tags = sqlif.getTags("job", jobid);
                            try {
                                pgm.cacheJavaClass(class_name, jh.language_info, True, tags.classpath);
                            } catch (hash<auto> ex) {
                                logDebug("Java initialization error: %s", get_exception_string(ex));
                                if (ex.arg.typeCode() == NT_OBJECT) {
                                    *object arg = ex.arg;
                                    while (arg) {
                                        logInfo("%s", arg.toString());
                                        arg = arg.getCause();
                                    }
                                }
                                rethrow;
                            }
                        } else if (language == "python") {
                            *hash<auto> tags = sqlif.getTags("job", jobid);
                            pgm.cachePythonClass(class_name, jh."code", jh.language_info, True, tags.module_path);
                        } else {
                            throw "JOB-ERROR", sprintf("job %s:%s (%d) requires support for unsupported language %y",
                                name, version, jobid, language);
                        }
                    }

                    ensure_create_tld();
                    tld.job = self;
                    # issue #3403: set interface context; necessary also in qjob processes during initialization
                    JobContextHelper ixctx();
                    pgm.parseCommit();

                    # verify job code
                    if (!class_based) {
                        # make sure a "run" function is present
                        if (!pgm.existsFunction("run")) {
                            throw "JOB-PROGRAM-ERROR", sprintf("jobid %d %s v%s: job program is missing the "
                                "\"run()\" function", jobid, name, version);
                        }
                    } else {
                        # set job_object variable and check class inheritance
                        if (language == "qore") {
                            Reflection::Class base_class = Class::forName("OMQ::UserApi::Job::QorusJob");
                            job_object = pgm.getCreateObject("qore", class_name);
                            int access = Reflection::Class::getClass(job_object).getInheritanceAccess(base_class);
                            if (access != AC_PUBLIC) {
                                throw "JOB-PROGRAM-ERROR", sprintf("jobid %d %s v%s: job class %y does not inherit %y",
                                    jobid, name, version, class_name, base_class.getPathName());
                            }
                        } else if (language == "java") {
                            job_object = pgm.getCreateObject("java", class_name);
                            Class c = Class::getClass(job_object);
                            QDBG_LOG("got Java object of class %y (%s)", c.getPathName(), class_name);
                        } else if (language == "python") {
                            job_object = pgm.getCreateObject("python", class_name);
                        }
                    }
                } catch (hash<ExceptionInfo> ex) {
                    string err = Qorus.getDebugSystem()
                        ? get_exception_string(ex)
                        : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                    logInfo("cannot load jobid %d %s v%s: %s", jobid, name, version, err);
                    rethrow;
                }

                # update session flag
                omqp.exec("update jobs set sessionid = %v where jobid = %v", Qorus.session.getID(), jobid);

                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }

        if (mh) {
            updateMappers(map $1.toInt(), mh.iterator());
        }

        # raise system event for job start
        hash<auto> jih = getInfo();
        Qorus.events.postJobStart(name, version, jobid, jih - ("name", "version", "jobid", "job_instanceid"));
        # clear any ongoing alert
        ActionReason r(NOTHING, sprintf("job %s v%s (%d) successfully started", name, version, jobid));
        Qorus.alerts.clearOngoingAlert(r, "JOB", jobid, "JOB-INSTANCE-ERROR");
        Qorus.alerts.clearOngoingAlert(r, "JOB", jobid, "STOPPED-JOB");
    }

    destructor() {
        logInfo("%s job with id %d successfully deleted", name, jobid);

        # issue #3765 delete the job object, not the program
        delete job_object;
    }

    static setThreadInit(LocalQorusJob job) {
        ensure_create_tld();
        tld.job = job;
    }

    # return the current time rounded to the next minute
    static date getStart(date start = now()) {
        date rv = start;
        int secs = rv.seconds();
        if (secs) {
            rv += seconds(60 - secs);
        }
        return rv;
    }

    int getId() {
        return jobid;
    }

    *int getJobIntanceId() {
        return job_instanceid;
    }

    *hash<auto> getStateData() {
        info_lck.lock();
        on_exit info_lck.unlock();

        return getStateDataIntern();
    }

    private *hash<auto> getStateDataIntern() {
        *string str;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                str = get_sql_table_system("omq", "job_state_data").selectRow({
                    "columns": "data",
                    "where": {"jobid": jobid},
                }).data;
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }

        if (!exists str) {
            return;
        }

        return deserialize_qorus_data(str);
    }

    saveStateData(hash<auto> data) {
        info_lck.lock();
        on_exit info_lck.unlock();

        saveStateDataIntern(data);
    }

    private saveStateDataIntern(hash<auto> data) {
        *string str = data ? serialize_qorus_data(data) : NOTHING;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                psave({"jobid": jobid, "data": str});
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    saveStateDataPath(string path, auto value) {
        info_lck.lock();
        on_exit info_lck.unlock();

        *hash<auto> state = getStateDataIntern();
        state = UserApi::updateHashDotValue(state, path, value);
        saveStateDataIntern(state);
    }

    *hash<auto> getPersistentStateData() {
        info_lck.lock();
        on_exit info_lck.unlock();

        return getPersistentStateDataIntern();
    }

    *hash<auto> getPersistentStateDataIntern() {
        *string str;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                str = get_sql_table_system("omq", "job_persistent_state_data").selectRow({
                    "columns": "data",
                    "where": {"jobid": jobid},
                }).data;
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }

        if (!exists str) {
            return;
        }

        return deserialize_qorus_data(str);
    }

    savePersistentStateData(hash<auto> data) {
        info_lck.lock();
        on_exit info_lck.unlock();

        savePersistentStateDataIntern(data);
    }

    savePersistentStateDataIntern(hash<auto> data) {
        *string str = data ? serialize_qorus_data(data) : NOTHING;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                ppsave({"jobid": jobid, "data": str});
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    savePersistentStateDataPath(string path, auto value) {
        info_lck.lock();
        on_exit info_lck.unlock();

        *hash<auto> info = getPersistentStateDataIntern();
        info = UserApi::updateHashDotValue(info, path, value);
        savePersistentStateDataIntern(info);
    }

    static hash<auto> getInactiveInfo(softint id) {
        # use += so the hash stays "hash<auto>"
        *hash<auto> h += omqservice.system.info.getJobMetadata(id);
        if (!exists h) {
            throw "JOB-ERROR", sprintf("jobid %d is unknown", id);
        }

        string name = h.firstKey();
        h = h{name};

        # create timer object
        CronTimer timer = h.recurring ? new CronTimer(seconds(h.recurring)) : new CronTimer(h.minute, h.hour, h.day,
            h.month, h.wday);
        return h{
            "name", "jobid", "version", "description", "run_skipped", "last_executed",
            "last_executed_job_instanceid", "expiry_date", "job_instanceid",
        } + {
            "trigger": timer.toString(),
            "active": False,
            "groups": Qorus.rbac.getJobGroups(h.jobid),
            "alerts": Qorus.alerts.getAlerts("JOB", h.jobid),
        };
    }

    hash<auto> getInfo() {
        m.lock();
        on_exit m.unlock();

        return self{
            "name", "jobid", "version", "description", "started", "run_skipped", "last_executed",
            "last_executed_job_instanceid", "expiry_date", "next", "job_instanceid", "custom_trigger",
        } + {
%ifdef QorusCore
            "remote": False,
%else
            "remote": True,
%endif
            "trigger": timer.toString(),
            "options": options,
            "active": True,
            "groups": Qorus.rbac.getJobGroups(jobid),
            "alerts": Qorus.alerts.getAlerts("JOB", jobid),
        };
    }

    saveInfo(auto info) {
        sqlif.updateJobInstanceInfo(job_instanceid, info);
    }

    saveInfoPath(string path, auto value) {
        info_lck.lock();
        on_exit info_lck.unlock();

        auto info = sqlif.getJobInstanceInfo(job_instanceid);
        if (exists info && info.typeCode() != NT_HASH) {
            info = {};
        }
        info = UserApi::updateHashDotValue(info, path, value);
        QDBG_LOG("LocalQorusJob::saveInfoPath() path: %y value: %y info: %y", path, value, info);
        sqlif.updateJobInstanceInfo(job_instanceid, info);
        jinfo = info;
    }

    *hash<auto> getJobInfo() {
        return jinfo;
    }

    # starts the job's background thread
    startImpl() {
        if (tid) {
            logInfo("already started; ignoring superfluous start call");
            return;
        }
        tid = background loop();
    }

    bool isRunning() {
        return tid.toBool();
    }

    stopNoWait() {
        m.lock();
        on_exit m.unlock();
        quit = True;
        if (waiting) {
            c.signal();
        }
    }

    stop() {
        stopNoWait();
        jc.waitForZero();
    }

    raiseError(string err, softstring desc = "", auto info, softstring severity = OMQ::ES_Major,
        softbool business = False) {
        int jeid;
        bool errflag;

        if (ErrorSeverityOrder{severity} > ErrorSeverityOrder{OMQ::ES_Warning}) {
            errflag = True;
        }
        if (errflag && !error) {
            error = True;
        }
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                jeid = sqlif.insertJobError(job_instanceid, severity, err, desc, info, business);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                olog(LoggerLevel::FATAL, "Exception thrown while trying to write error for job_instanceid %d to OMQ "
                    "job_errors table: %s: %s", job_instanceid, ex.err, ex.desc);
                # fix for bug 484: if a job error instance cannot be written to the job_errors table due to a
                # character encoding problem, then the job instance remains in status IN-PROGRESS
                # log user params separately in case of encoding problems
                olog(LoggerLevel::FATAL, "job_instanceid: %y job_errorid: %y", job_instanceid, jeid);
                try { olog(LoggerLevel::FATAL, "severity: %y", severity); } catch () {}
                try { olog(LoggerLevel::FATAL, "error: %y", err); } catch () {}
                try { olog(LoggerLevel::FATAL, "description: %y", substr(desc, 0, 240)); } catch () {}
                try { olog(LoggerLevel::FATAL, "info: %y", info); } catch () {}
                qlog(LoggerLevel::INFO, "%s", get_exception_string(ex));
            }
            trans.reset();
            break;
        }
        Qorus.events.postJobError(severity, name, version, jobid, job_instanceid,
            {
                "err": err,
                "desc": desc,
                "info": info,
                "business_error": business,
                "errorid": jeid,
            });
        logInfo("%s%s: %s%s%s", severity, business ? " (B)" : "", err, desc ? ": " + desc : "",
            exists info ? sprintf(", info: %y", info) : "");
        # save last job error info
        lasterr = err;
        lasterrdesc = desc;
    }

/*
    auto getOption(string field) {
        auto val = options{field};
        if (exists val) {
            return val;
        }
        return Qorus.options.get(field);
    }

    auto getOption(auto field) {
        m.lock();
        on_exit m.unlock();

        if (!elements field) {
            return options;
        }

        if (field.typeCode() == NT_LIST && elements field == 1) {
            return getOption(field[0]);
        }

        hash<auto> h;
        list<string> stillneed = ();

        foreach softstring f in (field) {
            if (exists options{f}) {
                h{f} = options{f};
            } else {
                stillneed += f;
            }
        }
        # get Qorus options
        map h{$1} = Qorus.options.get($1), stillneed;

        #printf("OMQ::Job::getOption(): getting %y: %y\n", field, h);
        return h;
    }

    setOptions(hash<auto> new_opts) {
        hash<auto> rv = Qorus.qmm.updateJobOptions(jobid, new_opts);

        if (rv.options) {
            options += rv.options;
        }

        if (rv.errs) {
            throw "JOB-OPTION-ERROR", sprintf("%y", rv.errs);
        }
    }
    */

    int usleep(date us) {
        return usleep(us.durationMicroseconds());
    }

    int usleep(softint us) {
        if (stop_warn) {
            throw "STOP-ERROR", "omqsleep() or omqusleep() called twice after job is in stop state";
        }

        do {
            {
                m.lock();
                on_exit m.unlock();
                if (quit) {
                    stop_warn = True;
                    break;
                }
            }
            if (us > 0) {
                Qore::usleep(us > 1000000 ? 1000000 : us);
                us -= 1000000;
            }
        } while (us > 0);

        return stop_warn ? -1 : 0;
    }

    # returns True if the job should be stopped because the expiry date is on or before the next trigger date
    bool setJobExpiry(*date date) {
        expiry_date = date;
        if (!exists expiry_date || expiry_date > next) {
            return False;
        }

        logInfo("expiry date %y set on or before next trigger date/time %y", date, next);
        return True;
    }

    Mapper getMapper(string mapname, *hash<auto> rtopts) {
        if (mh{mapname}) {
            return Qorus.mappers.get(mh{mapname}, rtopts);
        }

        throw "MAPPER-ERROR", sprintf("mapper %y is not a valid mapper for job %s v%s (%d); valid mappers: %y",
            mapname, name, version, jobid, mh.keys());
    }

    AbstractIterator getMapperIterator(string mapname, Qore::AbstractIterator input, *hash<auto> rtopts) {
        if (mh{mapname}) {
            return Qorus.mappers.getIterator(mh{mapname}, input, rtopts);
        }

        throw "MAPPER-ERROR", sprintf("mapper %y is not a valid mapper for job %s v%s (%d); valid mappers: %y",
            mapname, name, version, jobid, mh.keys());
    }

    auto getValueMap(string mapname, string key) {
        if (vmh{mapname}) {
            return Qorus.qmm.getVMapValue(mapname, key);
        }

        throw "VALUE-MAP-ERROR", sprintf("value map %y is not a valid value map for job %s v%s (%d); valid value "
            "maps: %y", mapname, name, version, jobid, vmh.keys());
    }

    list getValueMaps() {
        return Qorus.qmm.getVMapMap(){vmh.keys()}.values();
    }

    hash<JobResultInfo> runNow() {
        QDBG_ASSERT(ensure_tld());
        tld.job = self;
        return run();
    }

    bool setTrigger(date ts) {
        if (ts.relative()) {
            ts = now() + ts;
        }
        if (ts < now()) {
            logInfo("job_set_trigger() timestamp %y is in the past", ts);
            return False;
        }
        if (ts > next) {
            logInfo("job_set_trigger() timestamp %y is after the next trigger time %y", ts, next);
            return False;
        }
        logInfo("job_set_trigger() next trigger time set to %y (was %y)", ts, next);
        custom_trigger = next = ts;
        sqlif.commitJobCustomTrigger(jobid, ts);

        return True;
    }

    auto getConfigItemValue(string name, *hash<auto> local_context, bool expand_complex_values = True) {
        *hash<auto> config_info = config{name};
        if (!config_info) {
            throw "CONFIG-ITEM-ERROR", sprintf("config item %y is unknown; known config items: %y", name, keys config);
        }

        return getConfigItemValueIntern(name, config_info, local_context, expand_complex_values);
    }

    private auto getConfigItemValueIntern(string name, hash<auto> config_info, *hash<auto> local_context, bool expand_complex_values = True) {
        *string level;
        bool is_set;
        auto value = Qorus.qmm.findConfigItemValue("job", jobid, name, config_info, \level, \is_set);
        if (!config_info.allowed_values) {
            value = UserApi::expandTemplatedValue(value, local_context, expand_complex_values);
        }
        if (is_set) {
            # TODO: check type
            return value;
        }
        throw "CONFIG-ITEM-ERROR", sprintf("config item %y has neither a value nor a default value", name);
    }

    hash<auto> getConfigItemHash(*hash<auto> local_context) {
        return (map {$1.key: getConfigItemValueIntern($1.key, $1.value, local_context)}, config.pairIterator()) ?? {};
    }

    Program getProgram() {
        return pgm;
    }

    string enrichLogMessage(string msg, auto args) {
        *string jiid = job_instanceid ? sprintf("JI %d: ", job_instanceid) : NOTHING;
        return sprintf("%s%s", jiid, vsprintf(msg, args));
    }

    private updateMappers(*list<auto> mapper_ids) {
        # method body intentionally left blank in this class; overridden in ClusterQorusJob
    }

    private loop() {
        create_tld();
        jc.inc();
        on_exit
            jc.dec();

        # set thread context
        tld.job = self;

        logInfo("started job: schedule: %s last_executed: %y next: %y", timer.toString(), last_executed, next);
        olog(LoggerLevel::INFO, "jobid %d %y started", jobid, name);

        while (True) {
            {
                m.lock();
                on_exit m.unlock();
                if (quit)
                    break;
            }

            if (expiry_date >= next) {
                string msg = sprintf("this job (%y) expires on %y, which is on or after the next trigger date/time: "
                    "%y; the job will stop immediately; to start this job, change or remove the expiry date by "
                    "calling omq.system.job.set-expiry() or use the equivalent REST API", name, expiry_date, next);
                logInfo(msg);
                setStopReason(msg);

                break;
            }

            date diff = next - now();
            # if the difference is negative, then run now
            if (diff > 0s) {
                # wait wait for signal
                m.lock();
                on_exit m.unlock();
                if (quit)
                    break;

                waiting = True;
                c.wait(m, diff);
                waiting = False;
                if (quit)
                    break;
            }

            # FIXME: if a request to stop comes between here and run() then the job
            # will run anyway. Can we somehow avoid it?
            logInfo("trigger time %y has arrived, executing job", next);

            # update next trigger time before running job so it can be retrieved with job_get_info()
            next = timer.findNext(recurring ? now() : now() + 1m);
            if (custom_trigger) {
                date ts = remove custom_trigger;
                if (ts > now() && ts < next)
                    next = ts;
            }

            try {
                run();
            } catch () {
                # ignore exception; already logged
            }
        }

        logInfo("stopping job now");
    }

    /** @return a hash with the following keys:
        - \c job_instanceid
        - \c status
     */
    private hash<JobResultInfo> run() {
        # cannot run if requested to quit
        {
            m.lock();
            on_exit m.unlock();

            bool waited;
            while (nrun) {
                *int jiid = job_instanceid;
                if (jiid)
                    Qorus.logInfo("waiting for job instance ID %d to complete", jiid);
                else
                    Qorus.logInfo("waiting for running job instance to complete");
                if (quit)
                    break;
                crun.wait(m, RunCheckInterval);
                waited = True;
            }
            if (quit) {
                Qorus.logInfo("cannot run job; the job is stopping");
                throw "JOB-ERROR", sprintf("jobid %d is stopping and cannot be run", jobid);
            }
            if (waited)
                Qorus.logInfo("other job instance finished");
            ++nrun;
            QDBG_ASSERT(nrun == 1);
        }

        on_exit {
            m.lock();
            if (!--nrun)
                crun.broadcast();
            QDBG_ASSERT(!nrun);
            m.unlock();
        }

        # NOTE: running outside the lock, but with nrun set on

        # job instance start audit event ID
        *int a_eid;

        started = now_us();
        on_exit remove started;
        try {
            # first create job_instance row with status 'I'
            job_instanceid = sqlif.insertJobInstance(jobid, Qorus.session.getID());
        } catch (hash<ExceptionInfo> ex) {
            string str = !Qorus.getDebugSystem()
                ? sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc)
                : get_exception_string(ex);
            logInfo("%s", str);
            rethrow;
        }

        try {
            # audit job instance start
            a_eid = Qorus.audit.startJobInstance(tld.cx, jobid, job_instanceid);
            # raise system event for job instance start
            Qorus.events.postJobInstanceStart(name, version, jobid, job_instanceid);

            # ensure no resources are left open after the job's code is run
            ThreadResourceHelper trh();

%ifdef QorusCore
            # issue #3319: set interface context; at runtime only necessary for qorus-core
            JobContextHelper ixctx();
%endif

            # issue #3432: ensure that transient data is always local to the current execution object
            TransientDataHelper transient_data_helper();

            # run job
            # issue #3485: first run any FSM
            if (run_fsm) {
                QorusFsmHandler::executeFsm(run_fsm.name);
            } else if (class_based) {
                call_object_method(job_object, "run");
            } else {
                pgm.callFunction("run");
            }
        } catch (hash<ExceptionInfo> ex) {
            string str = !Qorus.getDebugSystem()
                ? sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc)
                : get_exception_string(ex);
            logInfo("%s", str);
            raiseError(ex.err.toString(), "A Qore exception occurred", ex.desc);
        }

        date end = now_us();
        string status = !error ? JS_Complete : JS_Error;
        date dt = end - started;
        logInfo("job completed with status '%s' (%s), elapsed time: %y, next trigger: %y", OMQ::JSMap{status},
            status, dt, next);

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # delete any state data if the status is COMPLETE
                if (!error)
                    get_sql_table_system("omq", "job_state_data").del(("jobid": jobid));
                sqlif.updateFinalJobInstanceStatus(jobid, job_instanceid, OMQ::JSMap{status}, started);
                # post SLA events

                *softint slaid = Qorus.qmm.getSlaForJob(jobid);
                if (slaid) {
                    int us = dt.durationMicroseconds();
                    if (!error) {
                        Qorus.qmm.postSlaEventSuccess(slaid, us.toNumber() / 1000000n,
                            CodeActionReason::getSource() ?? "system");
                    } else {
                        Qorus.qmm.postSlaEventError(slaid, us.toNumber() / 1000000n,
                            CodeActionReason::getSource() ?? "system", lasterr, lasterrdesc);
                    }
                }

                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                logFatal("failed to update job status to '%s' (%s): %s: %s", OMQ::JSMap{status}, status,
                    ex.err, ex.desc);
            }
            trans.reset();
            break;
        }

        last_executed = started;
        last_executed_job_instanceid = job_instanceid;
        # issues #1820 #1825: ensure the last_executed attribute is updated in the cache
        Qorus.qmm.updateJobTimestamps(jobid, last_executed, next, job_instanceid);

        hash<JobResultInfo> rv({
            "job_instanceid": job_instanceid,
            "status": status,
        });

        # post job performance events
        /*
        {
            string jid = "j" + jobid;
            int us = get_duration_microseconds(end - started);
            pc.post(us);
            Qorus.pcjob.post(us);
        }
        */

        # audit job instance stop
        Qorus.audit.stopJobInstance(tld.cx, a_eid, jobid, job_instanceid, OMQ::JSMap{status});
        # raise system event for job stop
        Qorus.events.postJobInstanceStop(name, version, jobid, job_instanceid, status, started, end, next);

        # clear any ongoing alert if the job executed successfully
        if (rv.status == OMQ::StatComplete) {
            Qorus.alerts.clearOngoingAlert("JOB", jobid, "JOB-INSTANCE-ERROR");
            Qorus.alerts.clearOngoingAlert("JOB", jobid, "STOPPED-JOB");
        } else if (active && !Qorus.shutting_down && (!expiry_date || expiry_date >= now_us())) {
            # raise an ongoing alert if the job instance failed and the job is currently scheduled
            # and Qorus is not shutting down
            CodeActionReason reason(sprintf("job %y job_instanceid %d completed with status %y", name,
                rv.job_instanceid, rv.status));
            Qorus.alerts.raiseOngoingAlert(reason, "JOB", jobid, "JOB-INSTANCE-ERROR", self.("name", "version"));
        }

        delete job_instanceid;
        delete error;

        return rv;
    }

    private loadLibrary() {
        hash<auto> mappers;
        qorus_load_library(lib, pgm, sub (string msg) { logInfo(msg); }, \mappers);
        # add pipeline and FSM mappers
        mh += map {$1.name: $1.id}, mappers.values();
    }

    #! Returns runtime options
    *hash<auto> getRuntimeOptionsImpl() {
        return Qorus.qmm.lookupJob(jobid, False)."runtime-options";
    }

    #! Sets options persistently
    setOptionsImpl(hash<auto> h) {
        Qorus.qmm.updateJobOptionsErr(jobid, h);
    }

    abstract *int auditUserEvent(string user_event, *string info1, *string info2);
}
