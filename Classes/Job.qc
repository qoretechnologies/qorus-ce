# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Job Class Definition

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

class OMQ::Job inherits AbstractQorusCoreJob, LocalQorusJob {
    private {
        # job logger
        Logger jobLogger;
    }

    constructor(hash<auto> jh, bool skip_checks = False, *string reason) :
        AbstractQorusCoreJob(jh), LocalQorusJob(jh.jobid, jh.name, jh.version) {

        updateLogger(Qorus.qmm.lookupLogger("jobs", jh.jobid).params);

        init(jh, skip_checks, reason);
        logStartJob(reason);
    }

    *date getExpiryDate() {
        return expiry_date;
    }

    bool isActive() {
        return active;
    }

    # returns True if the job should be stopped because the expiry date is on or before the next trigger date
    bool setExpiry(*date expiry) {
        return setJobExpiry(expiry);
    }

    setStopReason(*string reason) {
        stopreason.set(tld.cx, reason);
    }

    auto getOption(string field) {
        return LocalQorusJob::getOption(field);
    }

    auto getOption(auto field) {
        return LocalQorusJob::getOption(field);
    }

    *int auditUserEvent(string user_event, *string info1, *string info2) {
        return AbstractQorusCoreJob::auditUserEvent(job_instanceid, user_event, info1, info2);
    }

    private hash<auto> getDebugInfoImpl() {
        return {};
    }

    logArgs(int lvl, string msg, auto args) {
        string fmsg = enrichLogMessage(msg, args);
        string ext_msg = sprintf("%s T%d [%s]: ", log_now(), gettid(), LoggerLevel::getLevel(lvl).getStr()) + fmsg + "\n";
        jobLogger.log(lvl, "%s", fmsg, new LoggerEventParameter(\Qorus.eventLog.jobLogEvent(), jobid, ext_msg));
    }

    logFatal(string msg) {
        logArgs(Logger::LoggerLevel::FATAL, msg, argv);
    }

    logError(string msg) {
        logArgs(Logger::LoggerLevel::ERROR, msg, argv);
    }

    logWarn(string msg) {
        logArgs(Logger::LoggerLevel::WARN, msg, argv);
    }

    logInfo(string msg) {
        logArgs(Logger::LoggerLevel::INFO, msg, argv);
    }

    logDebug(string msg) {
        logArgs(Logger::LoggerLevel::DEBUG, msg, argv);
    }

    logTrace(string msg) {
        logArgs(Logger::LoggerLevel::TRACE, msg, argv);
    }

    # rotate the log file
    rotateLogFiles() {
        foreach auto appender in (jobLogger.getAppenders()) {
            if (appender instanceof AbstractLoggerAppenderFileRotate) {
                cast<AbstractLoggerAppenderFileRotate>(appender).rotate();
            }
        }
    }

    updateLoggerImpl(*hash<LoggerParams> params) {
        jobLogger = createLogger(params);
        logDebug("JOB(id=%y) logger has been updated with params=%y", jobid, params);
    }
}
