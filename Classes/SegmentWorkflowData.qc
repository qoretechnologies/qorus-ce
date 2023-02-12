# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus SegmentWorkflowData class definition

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

# holds cache information per workflowid for locally-managed workflows (non-cluster processes)
class OMQ::SegmentWorkflowData inherits AbstractCoreSegmentWorkflowData, LocalSegmentWorkflowData {
    private {
        # workflow logger
        Logger wfLogger;
    }

    constructor(Workflow wf, bool qref, bool temp) : AbstractCoreSegmentWorkflowData(wf, qref, temp),
            LocalSegmentWorkflowData(wf) {
        *Logger l = wf.takeTemporaryLogger();
        if (l) {
            wfLogger = l;
        } else {
            updateLogger(Qorus.qmm.lookupLogger("workflows", wf.workflowid).params);
        }
    }

    destructor() {
        if (refs > trefs) {
            WC.stop();
            delete WC;
        }
    }

    *hash<auto> getWFEntryDebugHash(string wfiid) {
        return LocalSegmentWorkflowData::getWFEntryDebugHash(wfiid);
    }

    private startProcess() {
        # no process to start
    }

    private stopProcess() {
        # no process to start
    }

    private createWorkflowQueue() {
        WC = new WorkflowQueue(wf);
    }

    updateLoggerImpl(*hash<LoggerParams> params) {
        wfLogger = createLogger(params);
        logDebug("logger for workflow %s v%s (%d) has been updated with params: %y",
            wf.name, wf.version, wf.workflowid, params);
    }

    static staticLogArgs(Workflow wf, Logger wfLogger, int lvl, string msg, auto args) {
        string fmsg = vsprintf(msg, args);
        string ext_msg = sprintf("%s T%d [%s]: ", log_now(), gettid(), LoggerLevel::getLevel(lvl).getStr()) + fmsg
            + "\n";
        # queue message for print in logger thread
        wfLogger.log(lvl, "%s", fmsg, new LoggerEventParameter(\Qorus.eventLog.workflowLogEvent(), wf.workflowid,
            ext_msg));
    }

    private logArgs(int lvl, string msg, auto args) {
        staticLogArgs(wf, wfLogger, lvl, msg, args);
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

    rotateLogFiles() {
        foreach auto appender in (wfLogger.getAppenders()) {
            if (appender instanceof AbstractLoggerAppenderFileRotate) {
                cast<AbstractLoggerAppenderFileRotate>(appender).rotate();
            }
        }
    }
}
