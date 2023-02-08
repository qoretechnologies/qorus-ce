# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus abstract qorus core job class definition

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

class OMQ::AbstractQorusCoreJob inherits AbstractQorusJob {
    private {
        # audit event ID for job start
        *int a_eid;

        # stop reason
        ActionReason stopreason();

        # is this a temporary job?
        bool temp = True;

        Condition rcond();
    }

    private:internal {
        # call reference counter
        int refs = 0;

        # number of threads waiting on condition variable
        int ref_waiting;

        # number of threads waiting for the job to possibly start
        # called after running an inactive job in case the job is set to active while running
        int start_waiting;

%ifdef QorusDebugInternals
        # hash of reference reasons; TID -> reason info
        hash<string, auto> ref_debug_hash;
%endif
    }

    constructor(hash<auto> jh) : AbstractQorusJob(jh.jobid, jh.name, jh.version) {
    }

    # must be called with the JobManager lock held
    start() {
        QDBG_ASSERT(temp);
        startImpl();
        temp = False;
        if (start_waiting) {
            rcond.broadcast();
        }
    }

    destructor() {
        rcond.broadcast();

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                omqp.exec("update jobs set sessionid = %v where jobid = %v", 0, jobid);
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

        logInfo("jobid %d %y stopped; %s", jobid, name, stopreason.getText());
        olog(LoggerLevel::INFO, "jobid %d %y stopped; %s", jobid, name, stopreason.getText());

        # deregister performance cache object
        /*
        if (pc && Qorus.pcm)
            Qorus.pcm.del(pc);
        */

        # raise auditing event for job stop
        Qorus.audit.stopJob(a_eid, jobid, NOTHING, stopreason.getReason(), stopreason.getWho(),
            stopreason.getSource());
        # raise system event for job stop
        Qorus.events.postJobStop(name, version, jobid);
        # if stopping an active, non-expired job and the system is not shutting down, then raise an ongoing alert
        if (isActive() && !Qorus.shutting_down) {
            *date expiry_date = getExpiryDate();
            if (!expiry_date || expiry_date >= now_us()) {
                Qorus.alerts.raiseOngoingAlert(stopreason, "JOB", jobid, "STOPPED-JOB",
                    {"name": name, "version": version});
            } else { # raise a transient alert that the job has expired
                Qorus.alerts.raiseTransientAlert(stopreason, "JOB", jobid, "JOB-EXPIRED",
                    {"name": name, "version": version});
            }
        }
    }

    logStartJob(*string reason) {
        # create job start reason object
        ActionReason startreason();
        startreason.set(tld.cx, reason);

        logInfo("starting jobid %d %s v%s; %s", jobid, name, version, startreason.getText());

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # raise system event for job stop
                a_eid = Qorus.audit.startJobNoCommit(jobid, sprintf("%y", getInfo()), startreason.getReason(),
                    startreason.getWho(), startreason.getSource());
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

    *int getAuditStartEventID() {
        return a_eid;
    }

    *int auditUserEvent(int job_instanceid, string user_event, *string info1, *string info2) {
        return Qorus.audit.userJobEvent(tld.cx, a_eid, jobid, job_instanceid, user_event, info1, info2);
    }

    # must be called in the JobManager lock
    bool deref() {
        # in case of a qjob process early termination, "refs" can be zero while calls are in progress
        # we have to make sure it never goes negative, which could lead to a deadlock
        if (refs > 0) {
%ifdef QorusDebugInternals
            softstring tid = gettid();
            pop ref_debug_hash{tid};
            if (!ref_debug_hash{tid}) {
                remove ref_debug_hash{tid};
            }
%endif
            if (!(--refs)) {
                if (ref_waiting) {
                    rcond.broadcast();
                }
                return True;
            }
            return False;
        }
        return True;
    }

    # must be called in the JobManager lock
    ref() {
        ++refs;

%ifdef QorusDebugInternals
        softstring tid = gettid();
        ref_debug_hash{tid} += ({"stack": get_stack()},);
%endif
    }

    # clears the temp flag
    setRecovered() {
        QDBG_ASSERT(temp);
        temp = False;
    }

    # called when the external qjob process has aborted
    # must be called in the JobManager lock
    aborted() {
        refs = 0;
%ifdef QorusDebugInternals
        remove ref_debug_hash;
%endif
        rcond.broadcast();
    }

    # must be called with the JobManager lock; returns True if there are no more references
    # returns False if the wait was interrupted because the job was started
    bool waitForRefs(Mutex m, *bool abort_started) {
        while (refs && (!abort_started || temp)) {
            logInfo("waiting for calls in progress: %d", refs);
            if (abort_started) {
                ++start_waiting;
            }
            ++ref_waiting;
            rcond.wait(m);
            --ref_waiting;
            if (abort_started) {
                --start_waiting;
            }
        }

        return !refs;
    }

    bool isTemp() {
        return temp;
    }

    setStopReason(hash<auto> ex, *string err) {
        stopreason.set(tld.cx, ex, err);
    }

    hash<auto> getDebugInfo() {
        return {"class": self.className()} + self{
            "temp",
            "ref_waiting",
            "refs",
%ifdef QorusDebugInternals
            "ref_debug_hash",
%endif
        } + getDebugInfoImpl();
    }

    updateLogger(*hash<LoggerParams> params) {
        if (params) {
            hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                "name": name,
                "id": jobid.toString(),
                "version": version,
            };
            params = substituteLogFilename(params, LoggerController::getLoggerSubs("jobs", subs));
        }
        updateLoggerImpl(params);
    }

    # starts the job's main thread in the process
    abstract startImpl();

    # runs the job immediately
    abstract hash<JobResultInfo> runNow();

    abstract setOptions(hash<auto> new_opts);

    abstract auto getOption(string field);

    abstract auto getOption(auto field);

    abstract hash<auto> getInfo();

    abstract stopNoWait();

    abstract bool setExpiry(*date expiry);

    abstract stop();

    abstract *date getExpiryDate();

    abstract bool isActive();

    abstract private hash<auto> getDebugInfoImpl();

    abstract updateLoggerImpl(*hash<LoggerParams> params);

    abstract rotateLogFiles();

    abstract *Program getProgram();
}
