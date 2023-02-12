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

class OMQ::Service inherits LocalQorusService, AbstractQorusCoreService {
    private {
        # service logger
        Logger svcLogger;
    }

    constructor(Counter sc, string type, string name, int serviceid, string version, *hash cx, *string reason) :
            AbstractQorusCoreService(sc, type, name, cx, reason), LocalQorusService(type, name) {
        self.serviceid = serviceid;
        self.version = version;
        updateLogger(Qorus.qmm.lookupLogger("services", serviceid).params);
    }

    startThreadTerminated(*string errdesc) {
        services.startThreadTerminated(self, errdesc);
    }

    setLocalStopReason(hash<ExceptionInfo> ex, string reason_fmt) {
        stopreason = new ActionReason(NOTHING, ex, vsprintf(reason_fmt, argv));
    }

    #! called when a config item used by this interface has its value changed externally
    configItemValueChanged(string name, auto value) {
        config_item_change_mutex.lock();
        on_exit config_item_change_mutex.unlock();

        if (!config_item_change_callback) {
            return;
        }

        try {
            ref();
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "SERVICE-STOPPED-ERROR") {
                return;
            }
            rethrow;
        }

        # make callback in the background
        background callConfigItemChangeCallback(name);
    }

    postLogEvent(LoggerEvent event) {
        svcLogger.callAppenders(event);
    }

    #! calls the config item changed callback with the config item name; the code can read the current value
    private callConfigItemChangeCallback(string config_item_name) {
        on_exit deref();

        LocalQorusService::callConfigItemChangeCallback(config_item_name);
    }

    private auto callMethodImpl(string method, auto args, *binary serialized_args, *hash<auto> cx, *bool serialized,
            *QorusProgram ix_pgm) {
        if (serialized_args) {
            QDBG_ASSERT(!exists args);
            args = deserialize(serialized_args);
        }
        ServiceThreadContextHelper stch(self, method);
        auto rv = LocalQorusService::callMethodImpl(method, args);
        return serialized && exists rv ? qorus_cluster_serialize(rv) : rv;
    }

    private stopProcess() {
        # nothing to do
    }

    private notifyStartThreadImpl() {
        ref();
    }

    private notifyEndThreadImpl() {
        deref();
    }

    logArgs(int lvl, string msg, auto args) {
        string fmsg = vsprintf(msg, args);
        string ext_msg = sprintf("%s T%d [%s]: ", log_now(), gettid(), LoggerLevel::getLevel(lvl).getStr()) + fmsg
            + "\n";
        svcLogger.log(lvl, "%s", fmsg, new LoggerEventParameter(\Qorus.eventLog.serviceLogEvent(), serviceid,
            ext_msg));
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
        foreach auto appender in (svcLogger.getAppenders()) {
            if (appender instanceof AbstractLoggerAppenderFileRotate) {
                cast<AbstractLoggerAppenderFileRotate>(appender).rotate();
            }
        }
    }

    updateLoggerImpl(*hash<LoggerParams> params) {
        svcLogger = createLogger(params);
        logDebug("logger for %s service %s v%s (%d) has been updated with params: %y", type, name, version, serviceid,
            params);

        map cast<AbstractDataProvider>($1.observable).setLogger(svcLogger), event_source_map.iterator();
    }

    string getStartReasonText() {
        return AbstractQorusCoreService::getStartReasonText();
    }

    Logger getLogger() {
        return svcLogger;
    }
}
