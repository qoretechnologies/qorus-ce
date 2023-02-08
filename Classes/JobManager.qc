# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus JobManager Class Definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

class OMQ::JobManager {
    private {
        # mutex to access jobs hash
        Mutex jm();

        # hash of Job objects keyed by job name - only active jobs are present in the hash,
        # access is restricted with jm.
        hash<string, AbstractQorusCoreJob> jobs;

        # mutex, condition, and flags for an atomic shutdown of the job manager
        # avoiding race conditions between init and shutdown
        Condition rcond();
        bool initializing;
        int wait_count;
        bool shutdown_flag;

        # job control hash; keyed by jobid
        hash jch;

        # recovery counter
        Counter recovery_cnt();

        # hash of jobs being deleted; name -> delete hash
        hash<string, hash<auto>> delete_hash;

        const ExpiryMsg = "job stopped due to expiry date set on or before next trigger date";
    }

    constructor() {
    }

    # starts all active jobs
    init() {
        {
            jm.lock();
            on_exit jm.unlock();

            if (shutdown_flag) {
                return;
            }
            initializing = True;
        }

        # signal initialization done when exiting if initialization not running in the background
        bool run_init_background;
        on_exit {
            if (!run_init_background) {
                initDone();
            }
        }

        if (!Qorus.options.get("autostart-interfaces")) {
            olog(LoggerLevel::INFO, "not starting jobs since 'autostart-interfaces' is False");
            return;
        }

        *hash<auto> q = Qorus.qmm.getJobMap(False);
        map delete q.$1, keys q, !q.$1.active;

        if (q) {
            background initIntern(q);
            run_init_background = True;
        }
    }

    private:internal initIntern(hash<auto> q) {
        on_exit initDone();
        foreach hash<auto> job in (q.iterator()) {
            if (jobs{job.name} || (job.expiry_date && job.expiry_date <= now_us())) {
                continue;
            }

            startJobCheckDisabled(job, "system startup");
            if (shutdown_flag) {
                break;
            }
        }
    }

    private:internal initDone() {
        jm.lock();
        on_exit jm.unlock();

        initializing = False;
        if (wait_count) {
            rcond.broadcast();
        }
    }

    signalRecovery() {
        recovery_cnt.inc();
    }

    recoverProcesses(hash<string, bool> rjobh) {
        on_exit recovery_cnt.dec();

        foreach string jobid in (keys rjobh) {
            *hash<auto> job = Qorus.qmm.lookupJob(jobid, False);
            if (!job) {
                olog(LoggerLevel::FATAL, "jobid %d with a running qjob process has no metadata; process cannot be recovered "
                    "and will have to be killed manually", jobid);
                continue;
            }

            try {
                # create object but do not initialize qjob process again
                RemoteQorusJob remote_job(job, True, "recover running qjob process after qorus-core restart", True);
                # check if job is a temp job; if so, do not add it; allow it to go out of scope which will stop the
                # process
                if (remote_job.isRunning()) {
                    remote_job.ref();
                    remote_job.setRecovered();
                    jobs{job.name} = remote_job;
                    olog(LoggerLevel::INFO, "recovered running jobid %d %y", job.jobid, job.name);
                }
           } catch (hash<ExceptionInfo> ex) {
                string msg = sprintf("cannot recover jobid %d %y: %s: %s: %s", job.jobid, job.name, get_ex_pos(ex),
                    ex.err, ex.desc);
                olog(LoggerLevel::INFO, msg);
            }
        }
    }

    recoverAbortedJob(int jobid, bool restarted, date abort_timestamp) {
        *hash<auto> jh = Qorus.qmm.lookupJob(jobid, False);
        if (!jh) {
            if (restarted) {
                olog(LoggerLevel::FATAL, "jobid %d with a restarted qjob process has no metadata; process cannot be recovered "
                    "and will have to be killed manually", jobid);
            }
            return;
        }

        QDBG_LOG("JobManager::recoverAbortedJob() %s v%s (%d) restarted: %y abort timestamp: %y", jh.name, jh.version, jh.jobid, restarted, abort_timestamp);
        if (restarted) {
            # if we are in a job stop, then we take no action, as the process will be stopped in any case
            *OMQ::AbstractQorusCoreJob j = getReferencedJob(jh.name);
            if (j) {
                on_exit derefJob(j);
                RemoteQorusJob job = cast<RemoteQorusJob>(j);
                try {
                    job.recover(jh, j.isTemp());
                } catch (hash<ExceptionInfo> ex) {
                    olog(LoggerLevel::INFO, "error in %s v%s (%d) recovery: %s", jh.name, jh.version, jh.jobid,
                        get_exception_string(ex));
                    restarted = False;
                    # do not rethrow, as this is a background thread and therefore the exception will be unhandled
                }
            } else {
                olog(LoggerLevel::INFO, "job %s v%s (%d) has already stopped; nothing to recover", jh.name, jh.version, jh.jobid);
            }
        }

        if (!restarted) {
            *RemoteQorusJob job;
            {
                jm.lock();
                on_exit jm.unlock();

                *AbstractQorusJob failed_job = remove jobs{jh.name};
                if (!failed_job) {
                    olog(LoggerLevel::INFO, "job %s v%s (%d) was not restarted and has already stopped; nothing to recover", jh.name, jh.version, jh.jobid);
                    return;
                }
                job = cast<RemoteQorusJob>(failed_job);

                # must call AbstractQorusCoreJob::aborted() in the mutex
                job.aborted();
            }

            # raise an alert for running jobs that could not be restarted
            # should not happen in normal operations
            if (!job.isTemp()) {
                ActionReason r(tld.cx, "the qjob process terminated unexpectedly and could not be restarted", True);
                Qorus.alerts.raiseOngoingAlert(r, "JOB", jh.jobid, "STOPPED-JOB", jh{"name", "version"});
            }
        }
    }

    hash<auto> getDebugInfo() {
        jm.lock();
        on_exit jm.unlock();

        return self{"initializing", "wait_count", "shutdown_flag"} + {
            "jobs": (map {
                $1.getName(): $1.getDebugInfo(),
            }, jobs.iterator()),
        };
    }

    setStopReasonExtern(string name, *string reason) {
        jm.lock();
        on_exit jm.unlock();

        # in case qorus-core has just restarted while a qjob tries to report its stop reason, first wait for
        # initialization to complete
        if (Qorus.getRestarted() && !jobs{name}) {
            waitInit();
        }

        if (jobs{name}) {
            cast<RemoteQorusJob>(jobs{name}).setStopReason(reason);
        } else {
            olog(LoggerLevel::INFO, "ERROR: not loaded job %y reported stop reason %y; ignoring", name, reason);
        }
    }

    *int auditUserEventExtern(string name, int job_instanceid, string user_event, *string info1, *string info2) {
        jm.lock();
        on_exit jm.unlock();

        # in case qorus-core has just restarted while a qjob tries to report its stop reason, first wait for
        # initialization to complete
        if (Qorus.getRestarted() && !jobs{name}) {
            waitInit();
        }

        if (jobs{name}) {
            jobs{name}.auditUserEvent(job_instanceid, user_event, info1, info2);
        } else {
            olog(LoggerLevel::INFO, "ERROR: not loaded job %y with job_instanceid %d tried to issue audit event %y (info1: %y "
                "info2: %y); ignoring", name, job_instanceid, user_event, info1, info2);
        }
    }

    private string startJobCheckDisabled(hash<auto> job, *string reason, *bool already_running) {
        if (!already_running) {
            try {
                # check if job is a member of a disabled group
                Qorus.rbac.canStartJob(job.jobid);
            } catch (hash<ExceptionInfo> ex) {
                # issue alert for job start error
                string err = sprintf("failed to load job: %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                ActionReason r(tld.cx, err, True);
                Qorus.alerts.raiseOngoingAlert(r, "JOB", job.jobid, "STOPPED-JOB", job.("name", "version"));

                # a full exception backtrace here is never relevant, as it only contains internal Qorus calls
                string errtxt = sprintf("%s: %s", ex.err, ex.desc);
                olog(LoggerLevel::INFO, "cannot start jobid %d %y: %s", job.jobid, job.name, errtxt);
                # clear next job run date/time
                Qorus.qmm.clearJobNextTriggerTime(job.jobid, job.name);
                return err;
            }
        }

        jm.lock();
        on_exit jm.unlock();

        string msg;
        try {
            loadAndStartJob(job, reason, already_running);
            msg = sprintf("job %s %s", job.name, already_running ? "recovered" : "started");
        } catch (hash<ExceptionInfo> ex) {
            string errtxt = Qorus.getDebugSystem()
                ? get_exception_string(ex)
                : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
            msg = sprintf("cannot %s jobid %d %y: %s", already_running ? "recover" : "start", job.jobid,
                job.name, errtxt);
            olog(LoggerLevel::INFO, msg);
        }
        return msg;
    }

    private list<AbstractQorusCoreJob> getReferencedJobs(*list<string> names) {
        list<AbstractQorusCoreJob> ret = ();
        *hash nhash = exists names ? map {$1: True}, names : NOTHING;
        jm.lock();
        on_exit jm.unlock();
        foreach hash<auto> h in (jobs.pairIterator()) {
            if (!delete_hash{h.key} && (!exists nhash || nhash{h.key})) {
                OMQ::AbstractQorusCoreJob j = h.value;
                j.ref();
                push ret, j;
            }
        }
        return ret;
    }

    private *OMQ::AbstractQorusCoreJob getReferencedJob(string name) {
        jm.lock();
        on_exit jm.unlock();

        if (jobs{name} && !delete_hash{name}) {
            jobs{name}.ref();
            return jobs{name};
        }
    }

    private derefJobs(softlist<AbstractQorusCoreJob> jlist) {
        jm.lock();
        on_exit jm.unlock();

        map $1.deref(), jlist;
    }

    private derefJob(AbstractQorusCoreJob job) {
        jm.lock();
        on_exit jm.unlock();

        job.deref();
    }

    # after running a job, dereference it and remove it if it hasn't been started in the meantime
    private derefTryRemoveJob(AbstractQorusCoreJob job) {
        jm.lock();
        on_exit jm.unlock();

        job.deref();
        # only remove the job if the job was not started
        if (job.waitForRefs(jm, True)) {
            remove jobs{job.getName()};
        } else {
            olog(LoggerLevel::INFO, "job %s v%s (%d) activated during ad-hoc run; not unloading", job.getName(), job.getVersion(),
                job.getId());
        }
    }

    shutdown() {
        {
            jm.lock();
            on_exit jm.unlock();

            shutdown_flag = True;
            waitInit();
        }

        list<string> names();
        {
            list<AbstractQorusCoreJob> ljobs = getReferencedJobs();
            on_exit derefJobs(ljobs);

            # first flag all jobs to stop in case some are long-running
            map $1.stopNoWait(), ljobs;

            # then log when each job actually stops
            foreach OMQ::AbstractQorusCoreJob j in (ljobs) {
                olog(LoggerLevel::INFO, "stopping jobid %d %y", j.getId(), j.getName());
                names += j.getName();
            }
        }
        map deleteJob($1, True, "system shutdown"), names;
    }

    setOptions(string name, hash<auto> h) {
        Qorus.qmm.updateJobOptionsFromNameErr(name, h);
    }

    setOptionsID(softint jobid, hash<auto> h) {
        Qorus.qmm.updateJobOptionsErr(jobid, h);
    }

    auto getOptions(string name, auto args) {
        int jobid = Qorus.qmm.rLookupJobEx(name).jobid;
        return Qorus.qmm.getOptionsWithContextArgs("job", jobid, args);
    }

    # return job option(s); do not throw an exception if the job doesn't exist
    auto getOptionsIdNoEx(softint jobid, auto args) {
        try {
            return Qorus.qmm.getOptionsWithContextArgs("job", jobid, args);
        } catch (hash<ExceptionInfo> ex) {
        }
    }

    auto getOptionsId(softint jobid, auto args) {
        return Qorus.qmm.getOptionsWithContextArgs("job", jobid, args);
    }

    hash<auto> getInfoID(softint jobid) {
        *string name = Qorus.qmm.lookupJob(jobid).name;
        if (!exists name) {
            throw "JOB-ERROR", sprintf("no jobid %d found in the system", jobid);
        }

        *OMQ::AbstractQorusCoreJob j = getReferencedJob(name);
        on_exit if (j) derefJob(j);

        return exists j ? j.getInfo() : Job::getInactiveInfo(jobid);
    }

    # this API is only called without an argument from the network
    # if the calling user has no RBAC group restrictions (ie is a member of the DEFAULT group)
    hash<auto> getInfo(*string name) {
        # if an argument was passed, then return information for the given job
        if (name) {
            *OMQ::AbstractQorusCoreJob j = getReferencedJob(name);
            on_exit if (j) derefJob(j);

            return exists j ? j.getInfo() : Job::getInactiveInfo(Qorus.qmm.getJobId(name));
        } else {
            hash<auto> h = {};
            list fullList = Qorus.qmm.jobList();

            list<AbstractQorusCoreJob> jlist = getReferencedJobs();
            on_exit derefJobs(jlist);

            hash activeJIDHash = map { $1.getId() : True }, jlist;
            list inactiveJIDList = select fullList, !exists activeJIDHash{$1};
            foreach OMQ::Job j in (jlist) {
                h{j.getName()} = j.getInfo();
            }
            foreach softstring jid in (inactiveJIDList) {
                *string jname = Qorus.qmm.lookupJobEx(jid).name;
                h{jname} = Job::getInactiveInfo(jid);
            }
            return h;
        }
    }

    # issue #1921 check if job is active with an unlocked call
    bool getJobActiveIndication(string name) {
        return jobs{name} ? True : False;
    }

    bool jobActive(softstring id) {
        *string name = Qorus.qmm.lookupJob(id).name;
        if (!exists name) {
            throw "JOB-ERROR", sprintf("no jobid %d found in the system", id);
        }

        *OMQ::AbstractQorusCoreJob j = getReferencedJob(name);
        on_exit if (j) derefJob(j);

        return exists j;
    }

    hash<auto> getActiveInfo(*string user) {
        hash<auto> h = {};

        list<AbstractQorusCoreJob> jlist = getReferencedJobs();
        on_exit derefJobs(jlist);

        foreach OMQ::AbstractQorusCoreJob j in (jlist) {
            hash<auto> jih = Qorus.qmm.rLookupJobEx(j.getName());
            h{jih.name} = jih;
        }

        return h;
    }

    hash<auto> getAnyInfo(list<auto> ids) {
        hash<auto> h = {};

        foreach softstring id in (ids) {
            *string name = Qorus.qmm.lookupJobEx(id).name;
            if (exists name) {
                *OMQ::AbstractQorusCoreJob j = getReferencedJob(name);
                on_exit derefJobs(j);
                if (exists j) {
                    h{name} = j.getInfo();
                }
            }
        }

        return h;
    }

    hash<auto> runJobIDNow(softint id) {
        hash<auto> jih = Qorus.qmm.lookupJobEx(id);
        runJobNow(jih.name, jih);
    }

    hash<auto> runJobNow(string name, *hash<auto> jih) {
        *OMQ::AbstractQorusCoreJob j = getReferencedJob(name);

        # issue #2797: clear and restore TLD to ensure that user api calls work properly
        ThreadLocalData tld_save();
        tld_save.tldCopy(tld);
        on_exit tld.tldCopy(tld_save);
        tld.clear();

        if (j) {
            on_exit derefJob(j);
            return j.runNow();
        } else {
            if (!jih) {
                jih = Qorus.qmm.rLookupJobEx(name);
            }
            # make sure job is enabled
            Qorus.rbac.canStartJob(jih.jobid);

            # issue #3699 ensure serialization of requests for inactive remote jobs
            AtomicJobActionHelper jah;
            if (jih.remote && jih.inactive) {
                jah = new AtomicJobActionHelper(jih.jobid);
            }

            AbstractQorusCoreJob job;

            {
                # insert job in job hash
                jm.lock();
                on_exit jm.unlock();

                if (!jobs{name}) {
                    # load job temporarily and skip checks
                    # NOTE: Job objects are created with refs = 0
                    job = jih.remote
                        ? new RemoteQorusJob(jih, True)
                        : new Job(jih, True);
                    jobs{name} = job;
                } else {
                    job = jobs{name};
                }
                jobs{name}.ref();
            }
            on_exit derefTryRemoveJob(job);

            return job.runNow();
        }
    }

    string resetJob(string name) {
        QDBG_LOG("JobManager::resetJob() %y", name);
        deleteJob(name, True, "reset job");
        hash<auto> jih = Qorus.qmm.rLookupJobEx(name);
        if (jih.expiry_date && jih.expiry_date <= now_us()) {
            return sprintf("job %s has expired, not started", jih.name);
        }

        return startJobCheckDisabled(jih, "reset job");
    }

    string resetJobID(softint id) {
        hash<auto> jih = Qorus.qmm.lookupJobEx(id);
        return resetJob(jih.name);
    }

    string reset(*list<auto> ids) {
        *list<auto> names = exists ids
            ? map Qorus.qmm.lookupJobEx($1.toString()).name, ids
            : map $1.name, Qorus.qmm.getJobMap(False).iterator();

        # get job names to reset
        list<string> jnames = ();
        if (names) {
            list<AbstractQorusCoreJob> jlist = getReferencedJobs(names);
            on_exit derefJobs(jlist);
            jnames = map $1.getName(), jlist;
        }

        int before = jnames.size();
        map resetJob($1), jnames;

        int after;
        {
            jm.lock();
            on_exit jm.unlock();

            after = jobs.size();
        }
        return sprintf("%d job%s stopped, %d job%s started after reset",
                       before, before == 1 ? "" : "s", after, after == 1 ? "" : "s");
    }

    #! called from the MapManager when the jib's expiry date has changed
    jobExpiryUpdated(string name, *date expiry, hash<auto> jih) {
        setJobExpiry(name, expiry, True, jih);
    }

    string setJobExpiry(string name, *date expiry, *bool metadata_updated, *hash<auto> jih) {
        if (!jih) {
            jih = Qorus.qmm.rLookupJobEx(name);
        }

        string msg = sprintf("jobid %d %y, expiry date: %y, ", jih.jobid, jih.name, expiry);

        # issue #3814 ensure serialization of requests to avoid race conditions
        AtomicJobActionHelper jah(jih.jobid);

        # must operate in the lock to ensure consistent update of all resources
        jm.lock();
        on_exit jm.unlock();

        sqlif.commitJobExpiry(jih.jobid, expiry);
        # update omqmap
        if (!metadata_updated) {
            Qorus.qmm.updateJobExpiry(jih.jobid, expiry);
        }

        if (exists jobs{name}) {
            # stop running job if the expiry date is before the next trigger date
            if (jobs{name}.setExpiry(expiry)) {
                jobs{name}.setStopReason(ExpiryMsg);
                deleteJobLocked(jih.jobid, name, True);
                msg += ExpiryMsg;
            } else {
                msg += "updated expiry date for running job";
            }
        } else {
            # inactive job
            # try to start job if expiry date cleared or set to a future date
            if (!expiry || expiry > now()) {
                try {
                    Qorus.rbac.canStartJob(jih.jobid);
                    loadAndStartJob(jih + {"expiry_date": expiry}, "job expiry date removed");
                    msg += "started";
                } catch (hash<ExceptionInfo> ex) {
                    msg += sprintf("cannot be started: %s: %s", ex.err, ex.desc);
                }
            } else {
                # clear STOPPED-JOB alert
                Qorus.alerts.clearOngoingAlert("JOB", jih.jobid, "STOPPED-JOB");
                msg += "updated stopped job";
            }
        }
        return msg;
    }

    string setJobExpiryID(softint id, *date expiry) {
        hash<auto> jih = Qorus.qmm.lookupJobEx(id);

        return setJobExpiry(jih.name. expiry);
    }

    # issue #2500: return the real active status as an output variable
    string setJobStatus(string name, bool active, *reference<bool> now_active) {
        hash<auto> jih = Qorus.qmm.rLookupJobEx(name);

        string msg = sprintf("jobid %d %y ", jih.jobid, jih.name);

        # issue #3814 ensure serialization of requests to avoid race conditions
        AtomicJobActionHelper jah(jih.jobid);

        # must operate in the lock to ensure consistent update of all resources
        jm.lock();
        on_exit jm.unlock();

        sqlif.commitJobActiveStatus(jih.jobid, active);
        # update omqmap
        Qorus.qmm.setJobActive(jih.jobid, active);

        if (exists jobs{name}) {
            if (active) {
                msg += sprintf("is already active and running");
                now_active = True;
            } else {
                jobs{name}.setStopReason("set to inactive");
                deleteJobLocked(jih.jobid, name, True);
                msg += sprintf("stopped and set to inactive");
                now_active = False;
            }
        } else {
            if (active) {
                # start job if possible
                try {
                    Qorus.rbac.canStartJob(jih.jobid);
                    loadAndStartJob(jih + ("active": True), "job reactivated");
                    msg += "set to active and started";
                    now_active = True;
                } catch (hash<ExceptionInfo> ex) {
                    msg += sprintf("set to active but cannot be started: %s: %s", ex.err, ex.desc);
                    now_active = False;
                }
            } else {
                # clear STOPPED-JOB alert
                Qorus.alerts.clearOngoingAlert("JOB", jih.jobid, "STOPPED-JOB");
                msg += "is not started and has been updated to inactive";
                now_active = False;
            }
        }
        return msg;
    }

    string setJobStatusID(softint id, bool active) {
        hash<auto> jih = Qorus.qmm.lookupJobEx(id);

        setJobStatus(jih.name, active);
    }

    string setJobScheduleID(softint id, *string schedule, *int duration) {
        hash<auto> jih = Qorus.qmm.lookupJobEx(id);

        return setJobSchedule(jih.name, schedule, duration);
    }

    string setJobSchedule(string name, *string schedule, *int duration) {
        hash<auto> jih = Qorus.qmm.rLookupJobEx(name);

        # issue #3814 ensure serialization of requests to avoid race conditions
        AtomicJobActionHelper jah(jih.jobid);

        # must operate in the lock to ensure consistent update of all resources
        jm.lock();
        on_exit jm.unlock();

        # issue 1830: must update the job description when updating the map so it takes effect in the job
        string msg = JobManager::updateJobSchedule(jih.jobid, schedule, duration, \jih);

        if (exists jobs{name}) {
            jobs{name}.setStopReason("set schedule");
            deleteJobLocked(jih.jobid, name, True);
            Qorus.rbac.canStartJob(jih.jobid);
            loadAndStartJob(jih, "set schedule");

            msg += ": updated running job";
        } else {
            msg += ": updated stopped job";
        }
        return msg;
    }

    private static string updateJobSchedule(int jobid, *string schedule, *int duration, reference jih) {
        if (schedule && duration) {
            throw "JOB-SCHEDULE-ERROR", sprintf("both schedule (%y) and duration (%y) parameters given", schedule, duration);
        }
        if (!schedule && !duration) {
            throw "JOB-SCHEDULE-ERROR", "neither schedule nor duration parameters given";
        }

        if (schedule) {
            # verify valid schedule before updating
            trim schedule;
            schedule =~ s/ +/ /g;
            list cl = split(" ", schedule);
            if (elements cl != 5) {
                throw "CRON-ERROR", sprintf("cron schedule %y does not have 5 fields in the format <minutes> <hours> <days> <months> <days-of-week>", schedule);
            }

            # this will throw a CRON-ERROR if the input cannot be parsed
            CronTrigger ct(cl[0], cl[1], cl[2], cl[3], cl[4]);

            sqlif.commitJobSchedule(jobid, cl[0], cl[1], cl[2], cl[3], cl[4]);
            # issue 1830: update the job description hash when updating the map so it takes effect in the job
            *hash<auto> h = Qorus.qmm.updateJobSchedule(jobid, schedule, cl[0], cl[1], cl[2], cl[3], cl[4]);
            if (!h) {
                throw "JOB-SCHEDULE-ERROR", sprintf("job %s v%s (%d) cannot be updated; it has been deleted during the update", jih.name, jih.version, jih.jobid);
            }
            jih = h;
            return sprintf("cron schedule %s", ct.toString());
        }

        if (!duration) {
            throw "CRON-ERROR", "duration of 0 seconds is not legal";
        }

        sqlif.commitJobRecurring(jobid, duration);
        # issue 1830: update the job description hash when updating the map so it takes effect in the job
        *hash h = Qorus.qmm.updateJobRecurring(jobid, duration);
        if (!h) {
            throw "JOB-SCHEDULE-ERROR", sprintf("job %s v%s (%d) cannot be updated; it has been deleted during the update", jih.name, jih.version, jih.jobid);
        }
        jih = h;
        return sprintf("duration %y", seconds(duration));
    }

    # called from the RBAC class
    startJob(string name, *string reason) {
        hash<auto> jih = Qorus.qmm.rLookupJobEx(name);

        jm.lock();
        on_exit jm.unlock();

        if (exists jobs{name}) {
            if (jih.jobid != jobs{name}.getId()) {
                throw "JOB-LOAD-ERROR", sprintf("jobid %d (%y) is already running, but job looked up as id %d; "
                    "call: \"qrest put system/metadata/reload?jobs=%d\" to align the system with the database as "
                    "necessary and try again", jobs{name}.getId(), name, jih.jobid);
            }
            # job already started
            return;
        }

        loadAndStartJob(jih, reason);
    }

    # called from QorusMapManager
    startJobBackground(string name, *string reason) {
        background sub (string name, *ThreadLocalData other_tld) {
            create_tld();
            tld.tldCopy(other_tld);
            try {
                startJob(name, "job updated with API");
            } catch (hash<ExceptionInfo> ex) {
                string errtxt = Qorus.getDebugSystem()
                    ? get_exception_string(ex)
                    : sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                olog(LoggerLevel::INFO, "cannot start job %y: %s", name, errtxt);
            }
        }(name, tld);
    }

    # stop an active job (for example, from RBAC when its group is disabled or due to a faulty user connection)
    stopJobID(softint jobid, *string reason) {
        string name = Qorus.qmm.lookupJobEx(jobid).name;

        deleteJob(name, True, reason);
    }

    enableLogging(softstring jobid) {
        *hash<auto> q = Qorus.qmm.lookupJob(jobid, False);
        if (!q) {
            olog(LoggerLevel::FATAL, "Can't enable logging for job with id %d; no metadata", jobid);
            return;
        }

        *OMQ::AbstractQorusCoreJob job = getReferencedJob(q.name);
        on_exit if (job) derefJob(job);

        if (!(job instanceof RemoteQorusJob)) {
            return;
        }
        cast<RemoteQorusJob>(job).subscribeToLog();
    }

    disableLogging(softstring jobid) {
        *hash<auto> q = Qorus.qmm.lookupJob(jobid, False);
        if (!q) {
            olog(LoggerLevel::FATAL, "Can't disable logging for job with id %d; no metadata", jobid);
            return;
        }

        *OMQ::AbstractQorusCoreJob job = getReferencedJob(q.name);
        on_exit if (job) derefJob(job);

        if (!(job instanceof RemoteQorusJob)) {
            return;
        }
        cast<RemoteQorusJob>(job).unsubscribeFromLog();
    }

    deleteJob(string name, bool withStop, *string reason) {
        jm.lock();
        on_exit jm.unlock();

        if (jobs{name}) {
            deleteJobLocked(jobs{name}.getId(), name, withStop, reason);
        }
    }

    private deleteJob(string name, bool withStop, hash<auto> ex) {
        jm.lock();
        on_exit jm.unlock();

        if (jobs{name}) {
            deleteJobLocked(jobs{name}.getId(), name, withStop, NOTHING, ex);
        }
    }

    private nothing deleteJobLocked(softstring jobid, string name, bool withStop, *string reason, *hash<auto> ex) {
        QDBG_LOG("JobManager::deleteJobLocked() %y called with stop: %y", name, withStop);
        # if we are already deleting this job then wait for the other delete to complete and then return
        if (delete_hash{name}) {
            QDBG_LOG("JobManager::deleteJobLocked() %y waiting for another delete already in progress", name);
            ++delete_hash{name}.waiting;
            delete_hash{name}.cond.wait(jm);
            # if we are the last thread waiting on this condition, remove the hash entry
            if (!--delete_hash{name}.waiting) {
                remove delete_hash{name};
            }
            QDBG_LOG("JobManager::deleteJobLocked() %y done", name);
            return;
        }

        if (withStop || reason || ex) {
            # issue #2634: do not make any external calls while the job manager lock is held
            delete_hash{name} = {
                "cond": new Condition(),
                "waiting": 0,
            };
            jm.unlock();
            # grab the lock on exit and notify/clean up the delete hash entry for the job
            on_exit {
                jm.lock();
                if (delete_hash{name}.waiting) {
                    # if we have waiting threads, let the last waiting thread remove the hash
                    delete_hash{name}.cond.broadcast();
                } else {
                    # otherwise remove it now
                    remove delete_hash{name};
                }
            }

            if (ex) {
                jobs{name}.setStopReason(ex);
            } else if (reason) {
                jobs{name}.setStopReason(reason);
            }
            if (withStop) {
                jobs{name}.stop();
                # do not delete temp jobs
                if (jobs{name}.isTemp()) {
                    return;
                }
            }
        }
        # deref the reference we created after construction
        jobs{name}.deref();
        # wait for all other in-progress actions
        jobs{name}.waitForRefs(jm);
        *Program pgm = jobs{name}.getProgram();
        delete jobs{name};
        delete pgm;
        # clear next job run date/time
        Qorus.qmm.clearJobNextTriggerTime(jobid, name);
        QDBG_LOG("JobManager::deleteJobLocked() %y removed job", name);
    }

    # called with the the lock held
    private loadAndStartJob(hash<auto> jih, *string reason, *bool already_running) {
        if (Qorus.shutting_down) {
            throw "SHUTDOWN-IN-PROGRESS", "terminating job startup due to system shutdown";
        }

        # issue #2732: do not allow jobs to start if system limits have been exceeded
        QorusSharedApi::checkLimits("cannot start job");

        if (jobs{jih.name} || !jih.active || (jih.expiry_date && jih.expiry_date <= now())) {
            return;
        }

        AbstractQorusCoreJob job;
        try {
            job = jih.remote
                ? new RemoteQorusJob(jih, True, reason, already_running)
                : new Job(jih, True);
        } catch (hash<ExceptionInfo> ex) {
            # ignore job expiry errors for the sake of alerting since it's not an error
            # when the job expires
            if (ex.err != "JOB-EXPIRY-ERROR") {
                # issue alert for job start error
                string err = sprintf("failed to load job: %s: %s: %s",
                                     get_ex_pos(ex), ex.err, ex.desc);
                ActionReason r(tld.cx, err, True);
                Qorus.alerts.raiseOngoingAlert(r, "JOB", jih.jobid, "STOPPED-JOB",
                                               jih.("name", "version"));
            }
            # clear next job run date/time
            Qorus.qmm.clearJobNextTriggerTime(jih.jobid, jih.name);
            rethrow;
        }

        # add job to internal data structures
        {
            job.ref();
            jobs.(jih.name) = job;
        }

        QDBG_LOG("JobManager::loadAndStartJob() %y created %s object; starting job", jih.name, job.className());
        # start the job
        try {
            job.start();
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("JobManager::loadAndStartJob() %y exception starting job: %s", jih.name, get_exception_string(ex));
            job.setStopReason(ex);
            deleteJobLocked(jih.jobid, jih.name, False);
            # clear next job run date/time
            Qorus.qmm.clearJobNextTriggerTime(jih.jobid, jih.name);
            rethrow;
        }
        QDBG_LOG("JobManager::loadAndStartJob() %y started", jih.name);
    }

    #! wait for initialization to complete; must be called with the lock held
    private waitInit() {
        while (initializing) {
            ++wait_count;
            rcond.wait(jm);
            --wait_count;
        }
    }

    rotateLogFiles() {
        list<AbstractQorusCoreJob> ljobs = getReferencedJobs();
        on_exit derefJobs(ljobs);

        map $1.rotateLogFiles(), ljobs;
    }

    # updates a single logger
    updateLoggerId(int jobid, *hash<LoggerParams> params) {
        # do not make any cluster network calls with the job lock held
        *string name = Qorus.qmm.lookupJob(jobid).name;
        if (!exists name) {
            return;
        }
        updateLogger(name, params);
    }

    updateLogger(string name, *hash<LoggerParams> params) {
        *OMQ::AbstractQorusCoreJob job = getReferencedJob(name);
        if (!job) {
            return;
        }
        on_exit {
            derefJob(job);
        }
        job.updateLogger(params);
    }
}
