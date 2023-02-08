# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

public namespace OMQ {
    public class AuditLocal inherits Audit {
        private {
            Logger logger;
        }

        constructor(SQLInterface n_sqlif, *softlist n_options) : Audit(n_sqlif, n_options) {
            logger = createLogger(Qorus.loggerController.getLoggerParamsSubs("AUDIT"));
        }

        updateLogger(*hash<LoggerParams> params) {
            params = substituteLogFilename(params, LoggerController::getLoggerSubs("AUDIT"));
            logger = createLogger(params);
            logDebug("AUDIT logger has been updated with params: %y", params);
        }

        private logArgs(int lvl, string msg, auto args) {
            string fmsg = vsprintf(msg, args);
            logger.log(lvl, "%s", fmsg, new LoggerEventParameter(\Qorus.eventLog.logEvent(), "audit",
                sprintf("%s T%d [%s]: ", log_now(), gettid(), LoggerLevel::getLevel(lvl).getStr()) + fmsg + "\n"));
        }

        logFatal(string msg) {
            logArgs(Logger::LoggerLevel::FATAL, msg, argv);
        }

        logInfo(string msg) {
            logArgs(Logger::LoggerLevel::INFO, msg, argv);
        }

        logDebug(string msg) {
            logArgs(Logger::LoggerLevel::DEBUG, msg, argv);
        }

        rotateLogFiles() {
            foreach auto appender in (logger.getAppenders()) {
                if (appender instanceof AbstractLoggerAppenderFileRotate) {
                    cast<AbstractLoggerAppenderFileRotate>(appender).rotate();
                }
            }
        }
    }
}
