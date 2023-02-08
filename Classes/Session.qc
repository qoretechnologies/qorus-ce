# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Session class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

public namespace OMQ;

%new-style

class OMQ::Session {
    private {
        Counter sessionCounter();
        Queue sessionSteps();
        list<hash<WorkflowRecoveryInfo>> sessionStepsResult = ();
        bool is_open = False;
        string key;
        int id;
        # internal SQLInterface object so this class can be used by the Qorus client library as well
        SQLInterface sqlif;
        int db_max_threads;
        int stepsize;

        # datasource description string
        string desc;
    }

    logFatal(string msg) {
        vprintf(msg + "\n", argv);
    }

    logError(string msg) {
        vprintf(msg + "\n", argv);
    }

    logWarn(string msg) {
        vprintf(msg + "\n", argv);
    }

    logInfo(string msg) {
        vprintf(msg + "\n", argv);
    }

    logDebug(string msg) {
        vprintf(msg + "\n", argv);
    }

    logTrace(string msg) {
        vprintf(msg + "\n", argv);
    }

    # if wfid is passed, then id must be passed as well, meaning that the given workflow session will be recovered
    constructor(SQLInterface sqlif, string key, int db_max_threads, int stepsize) {
        self.sqlif = sqlif;
        self.key = key;
        self.db_max_threads = db_max_threads;
        self.stepsize = stepsize;

        desc = get_ds_desc(sqlif.omqp.getConfigHash(), DD_SHORT);
    }

    private hash checkSystemPropertiesIntern() {
        hash sysprops;

        context (sqlif.sessionCheckSystemProperties())
            sysprops.%keyname = %value;

        # for old versions
        if (exists sysprops."omq-schema-compatibility") {
            if (sysprops."omq-schema-compatibility" != OMQ::compat_datamodel)
                throw "SESSION-ERROR", sprintf("(ID01) incompatible compat datamodel %y, expecting %y",
                                            sysprops."omq-schema-compatibility", OMQ::compat_datamodel);
        } else if (exists sysprops."schema-compatibility") {
            if (sysprops."schema-compatibility" != OMQ::compat_datamodel) {
                if (compare_version(sysprops."schema-compatibility", OMQ::compat_datamodel) < 0)
                    throw "SESSION-ERROR",
                    sprintf("(ID02) compat datamodel %y is too old for this version of Qorus, expecting %y; please run 'schema-tool -V' to upgrade the schema to the latest version and try again",
                            sysprops."schema-compatibility", OMQ::compat_datamodel);
                else
                    throw "SESSION-ERROR",
                    sprintf("(ID03) compat datamodel %y requires a later version of Qorus, expecting compat datamodel %y",
                            sysprops."schema-compatibility", OMQ::compat_datamodel);
            }
            if (compare_version(sysprops."schema-version", OMQ::datamodel) < 0)
                throw "SESSION-ERROR",
                sprintf("(ID04) data model %y is too old for this version of qorus, expecting %y; please run 'schema-tool -V' to upgrade the schema to the latest version and try again", sysprops."schema-version", OMQ::datamodel);
        } else
            throw "SESSION-ERROR", "no 'schema-compatibility' key set in the system_properties table in domain 'omq'";

        return sysprops;
    }

    private checkSystemProperties() {
        checkSystemPropertiesIntern();
    }

    static throwServerAliveException(hash info, string msg) {
        string err;
        if (exists info.result)
            err = sprintf("instance %y (%y pid %d sessionid %d) is already", info.result."instance-key", info.result.hostname, info.result.pid, info.result."session-id");
        else
            err = sprintf("a qorus-core process is");
        err += sprintf(" alive and responding on %s; cannot %s", info.url, msg);
        throw "SERVER-ALIVE", err, True;
    }

    checkRecover(Audit audit, string trigger, bool server = True) {
        # check system properties
        checkSystemProperties();

        # check for still open sessions
        *list<auto> l = sqlif.sessionOpen1();
        if (!l) {
            logInfo("DB %y: %sno sessions need recovery", desc, server ? "(auto-recover) " : "");
            return;
        }

        logInfo("DB %y: the following sessions are active: %y", desc, (map $1.sessionid, l));

        # only check each URL once
        hash<string, bool> urlh;

        foreach hash<auto> q in (l) {
            # if there is an active session with this key
            hash<auto> info;
            if (!urlh{q.xmlrpc_server}) {
                urlh{q.xmlrpc_server} = True;

                int rc = Session::checkLastInstance(q.hostname, q.xmlrpc_server, \info);
                if (rc) {
                    Session::throwServerAliveException(info, "recover a running instance");
                }

                logInfo("DB %y: could not contact old instance on %y (%s), starting recovery", desc, info.url, info.ex.err);
            }

            recover(audit, trigger, q.sessionid);
        }
    }

    # selects minimum and maximum workflow instance ID values for recovery
    private hash initSessionRecovery(string sid) {
        return sqlif.sessionRecoverInit(sid);
    }

    # workflow recovery works in smaller chunks of data instead one fullscan
    # to avoid rollback segment too small errors etc.
    # 1) it queries workflow_instances for "statistics" about
    #    PK and how many steps will be used.
    # 2) if there are only few data the fullscan is perfomed.
    # 3) create a helper queues (sessionSteps) with workflow_instances PK intervals
    #    and one list (sessionStepsResult) for batch results (various counts)
    # 4) then call processing of these intervals in separate thread pools
    #    (up to options' db-max-threads).
    # 5) Then finalize it
    private string recoverWorkflows(softstring sid, Audit audit, string trigger) {
        hash init = initSessionRecovery(sid);
        if (!init.minimum && !init.maximum) {
            string rv = "Session workflow recovery params: no workflow orders need recovery";
            logInfo(rv);
            return rv;
        }

        # convert all values to integer
        map (init.$1 = int(init.$1)), keys init;

        int min = init.minimum;

        while (min <= init.maximum) {
            int max = min + stepsize;
            if (max > init.maximum)
                max = init.maximum;
            hash step = {
                "min"    : min,
                "max"    : max,
                "count"  : max - min,
            };

            min = max + 1;
            sessionSteps.push(step);
        }

        # mark it as a last step for threads as an exit flag
        sessionSteps.push("END");

        logInfo("Session workflow recovery params: min: %y, max: %y, size: %y", init.minimum, init.maximum, stepsize);

        for (int i = 0; i < Qore::min(db_max_threads, sessionSteps.size() - 1); ++i) {
            sessionCounter.inc();
            background sessionRecoverPart(sid, audit, trigger);
        }

        sessionCounter.waitForZero();
        if (sessionSteps.get() != "END") # note the END marker
            throw "SESSION-RECOVER", sprintf("Not all recovery steps have been processed. Still in queue: %d", sessionSteps.size());

        hash<WorkflowRecoveryInfo> res();
        foreach hash<WorkflowRecoveryInfo> i in (sessionStepsResult) {
            res.count += i.count;
            res.sgcount += i.sgcount;
            res.wcount += i.wcount;
        }

        # workflow audit info string
        string wstr;

        # log what was done
        if (res.wcount) {
            workflowRecoveryComplete(res);
            wstr = sprintf("recovered %d workflow order%s (%d segment%s, %d step%s)",
                            res.wcount, res.wcount == 1 ? "" : "s",
                            res.sgcount, res.sgcount == 1 ? "" : "s",
                            res.count,  res.count == 1 ? "" : "s");
        }
        else {
            wstr = "no workflow orders needed recovery";
        }

        logInfo("DB %y: %s", desc, wstr);
        return wstr;
    }

    # this method is empty in the base class
    private workflowRecoveryComplete(hash<WorkflowRecoveryInfo> res) {
    }

    hash<JobRecoveryInfo> getJobsToRecover(softint sid, Audit audit, string trigger) {
        return sqlif.recoverJobs(sid, audit, trigger);
    }

    private string recoverJobs(softstring sid, Audit audit, string trigger) {
        # job audit info string
        string jstr;

        # now recover jobs
        hash<JobRecoveryInfo> res = sqlif.recoverJobs(sid, audit, trigger);
        if (res.jcount || res.jrcount) {
            jobRecoveryComplete(res);
            softint tot = res.jcount + res.jrcount;
            jstr = sprintf("%d job instance%s marked with status %y, cleared sessionid for %d job record%s",
                        res.jcount, res.jcount == 1 ? "" : "s", OMQ::JS_Crash,
                        tot, tot == 1 ? "" : "s");
        } else {
            jstr = "no jobs needed recovery";
        }

        logInfo("DB %y: %s", desc, jstr);
        return jstr;
    }

    # this method is empty in the base class
    private jobRecoveryComplete(hash<JobRecoveryInfo> res) {
    }

    private recover(Audit audit, string trigger, softstring sid) {
        logFatal("DB %y: starting recovery of sessionid %d", desc, sid);
        # create audit entry
        audit.systemRecoveryStart(trigger, sid);

        string wstr = recoverWorkflows(sid, audit, trigger);

        # recover jobs
        string jstr = recoverJobs(sid, audit, trigger);

        # marks the session in the sessions table as recovered
        sqlif.sessionRecoverFinalize(sid);

        # log session recovery
        logInfo("DB %y: sessionid %d successfully recovered", desc, sid);

        audit.systemRecoveryComplete(trigger, wstr + "; " + jstr);
    }

    private hash<WorkflowRecoveryInfo> sessionDbRecoverPart(string sid, hash step, Audit audit, string trigger) {
        return sqlif.sessionRecoverPart(sid, NOTHING, step.min, step.max, audit, trigger);
    }

    private sessionRecoverPart(softstring sid, Audit audit, string trigger) {
        logDebug("starting recovery thread %d", gettid());
        hash<WorkflowRecoveryInfo> retval();

        on_exit {
            sessionCounter.dec();
            push sessionStepsResult, retval;
            logDebug("end of recovery thread %d", gettid());
        }

        while (True) {
            try {
                auto step = sessionSteps.get();
                if (step == "END") {
                    sessionSteps.push("END");
                    return;
                }
                if (step == "ERROR") {
                    sessionSteps.push("ERROR");
                    return;
                }
                logDebug("recovery part: min: %y max: %y", step.min, step.max);
                hash res = sessionDbRecoverPart(sid, step, audit, trigger);
                logDebug("res: %y", res);
                retval.count += res.count;
                retval.sgcount += res.sgcount;
                retval.wcount += res.wcount;
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "QUEUE-TIMEOUT") {
                    return;
                }
                sessionSteps.push("ERROR");
                string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                logInfo("recovery error: %s", err);
                # do not throw an exception here; it cannot be handled
            }
        } # end of while loop
    }

    int getID() {
        return id;
    }

    string getKey() {
        return key;
    }

    # returns -1 for error (already running), information in info
    static int checkLastInstance(string host, string server, reference<hash<auto>> info) {
        try {
            # remove any options from server string
            server =~ s/{.*}//;
            info.url = http_get_url_from_bind(server, host);

            info.url =~ s/{.*//;

            JsonRpcClient jc({"url": info.url, "timeout": 15s, "connect_timeout": 15s});
            info += jc.call("omq.system.get-status");
        } catch (hash<ExceptionInfo> ex) {
            # return -1 for "system up" on auth errors
            if (ex.arg.status_code == 401) {
                return -1;
            }

            #printf("EX: %N\n", ex);
            #printf("%s: %s\n", info.url, get_exception_string(ex));
            info.ex = ex;
            return 0;
        }

        return -1;
    }
}