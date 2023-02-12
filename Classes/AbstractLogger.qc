# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

#! appender parameters
/** @since Qorus 4.0
*/
public hashdecl AppenderParams {
    #! appender name
    *softstring name;
    #! appender layout pattern
    *string layoutPattern;
    #! appender file name
    *softstring filename;
    #! rotation count
    *int rotationCount;
    #! appender type
    *string appenderType;
    #! encoding
    *string encoding;
    #! archivePattern
    *string archivePattern;
}

#! logger parameters
/** @since Qorus 4.0
*/
public hashdecl LoggerParams {
    #! logger level
    int level;
    #! logger name
    *softstring name;
    #! additivity
    *bool additivity;
    #! appenders; appender ID -> appender params
    *hash<string, hash<AppenderParams>> appenders;
}

#! log filename substitutions
/** @since Qorus 4.0
*/
public hashdecl LogFilenameSubs {
    #! full path
    *string path;
    #! process name
    *string name;
    #! process id
    *string id;
    #! process version
    *string version;
    #! process instance key
    *string instance;
}

# currently no qorus lib - so we define some constants here:
const LL_CRITICAL   = -1;
const LL_IMPORTANT  = 0;
const LL_INFO       = 1;
const LL_DETAIL_1   = 2;
const LL_DETAIL_2   = 3;
const LL_DEBUG_1    = 4;
const LL_DEBUG_2    = 5;
const LL_DEBUG_3    = 6;

const AVAILABLE_LEVELS_STR = {
    "OFF": Logger::LoggerLevel::OFF,
    "FATAL": Logger::LoggerLevel::FATAL,
    "ERROR": Logger::LoggerLevel::ERROR,
    "WARN": Logger::LoggerLevel::WARN,
    "INFO": Logger::LoggerLevel::INFO,
    "DEBUG": Logger::LoggerLevel::DEBUG,
    "TRACE": Logger::LoggerLevel::TRACE,
    "ALL": Logger::LoggerLevel::ALL,
};

#! Default log layout pattern
const DefaultLogLayoutPattern = "%d{YYYY-MM-DD HH:mm:SS.xx} T%t [%p]: %m%n";

const AVAILABLE_LEVELS = map {$1.value: $1.key}, AVAILABLE_LEVELS_STR.pairIterator();
const AVAILABLE_APPENDER_TYPES = ("LoggerAppenderStdOut", "LoggerAppenderFile", "LoggerAppenderFileRotate");
const AVAILABLE_APPENDER_FIELDS = {
    "name": ("LoggerAppenderStdOut", "LoggerAppenderFile", "LoggerAppenderFileRotate"),
    "layoutPattern": ("LoggerAppenderFile", "LoggerAppenderFileRotate"),
    "filename": ("LoggerAppenderFile", "LoggerAppenderFileRotate"),
    "encoding": ("LoggerAppenderFile", "LoggerAppenderFileRotate"),
    "rotationCount": ("LoggerAppenderFileRotate",),
    "archivePattern": ("LoggerAppenderFileRotate",),
};
# issue #3113: default appender params keyed by appender type
const DEFAULT_APPENDER_PARAMS = {
    "LoggerAppenderStdOut": {
        "name": "MyCustomAppender",
        "layoutPattern": DefaultLogLayoutPattern,
        "encoding": "UTF-8",
    },
    "LoggerAppenderFile": {
        "name": "MyCustomAppender",
        "layoutPattern": DefaultLogLayoutPattern,
        # default filenames sent as a hash depending on the context; value is based on system options
        "filename": NOTHING,
        "encoding": "UTF-8",
    },
    # default filename sent as a hash depending on the context; value is based on system options
    "LoggerAppenderFileRotate": {
        "name": "MyCustomAppender",
        "layoutPattern": DefaultLogLayoutPattern,
        # default filenames sent as a hash depending on the context; value is based on system options
        "filename": NOTHING,
        "encoding": "UTF-8",
        # rotationCount is set using the max-log-files option
        "rotationCount": NOTHING,
        "archivePattern": "%p%f.%i",
    },
};
# default logger params
const DEFAULT_LOGGER_PARAMS = {
    "name": "MyCustomLogger",
};
#! system logger types; maps from system logger type to URI path name
const SystemLoggerInfo = {
    "Audit": {
        "uri_path": "audit",
        "log_path": "audit",
        "logger": "AUDIT",
        "description": "Audit logger file",
    },
    "Alert": {
        "uri_path": "alert",
        "log_path": "alert",
        "logger": "ALERT",
        "description": "Alert logger",
    },
    "Monitoring": {
        "uri_path": "mon",
        "log_path": "monitoring",
        "logger": "MONITORING",
        "description": "Monitoring logger",
    },
    "Http": {
        "uri_path": "http",
        "log_path": "http",
        "logger": "HTTP",
        "description": "HTTP logger",
    },
    "Qorus Core": {
        "uri_path": "qorus-core",
        "log_path": "qorus-core",
        "logger": "qorus-core",
        "description": "Qorus core logger",
    },
    "Qorus Master": {
        "uri_path": "qorus-master",
        "log_path": "qorus-master",
        "logger": "qorus-master",
        "description": "Qorus master (process manager) logger",
    },
    "Prometheus": {
        "uri_path": "prometheus",
        "log_path": "prometheus",
        "logger": "prometheus",
        "description": "Prometheus TSDB logger",
    },
    "Grafana": {
        "uri_path": "grafana",
        "log_path": "grafana",
        "logger": "grafana",
        "description": "Grafana logger",
    },
};

#! system logger types; maps from system logger type to URI path name
const SystemLoggers = map {$1.logger: True}, SystemLoggerInfo.iterator();
#! system loggers including the catch-all "system"; maps from system logger type to URI path name
const SystemLoggersWithSystem = SystemLoggers + {
    "system": True,
};
#! interface logger types
const InterfaceLoggers = {
    "workflows": True,
    "services": True,
    "jobs": True,
    "qdsp": True,
};
#! interface logger types including "system"
const InterfaceLoggersWithSystem = InterfaceLoggers + {
    "system": True,
};

const ENV_LOGGER_PARAMS = "LOGGER_PARAMS";  # uses by processes to receive logger params

class AbstractLogger {
    error(string fmt) {
        logArgs(LoggerLevel::ERROR, fmt, argv);
    }

    log(int lvl, string fmt) {
        logImpl(lvl, vsprintf(fmt, argv));
    }

    logArgs(int lvl, string fmt, *list<auto> args) {
        logImpl(lvl, vsprintf(fmt, args));
    }

# only for qorus-master and qorus-core
%ifdef NeedQorusLoggerCache
    /** we restrict this to only selecting system mappers when seeding the logger map from qorus-master to qorus-core
        because there is a limit of 32K chars to the size of environment variables
    */
    hash<auto> getLoggerMap(AbstractTable loggers, *bool only_system, *int omq_loggerid) {
        hash<auto> loggerMap = {};
        hash<auto> logger_info;
        hash<string, int> aliases;
        QorusRestartableTransaction trans(loggers.getDriverName());
        while (True) {
            try {
                on_error loggers.rollback();

                hash select_hash = {
                    "columns": ("loggerid", "params", "interface_table_name")
                };
                if (only_system) {
                    select_hash."where" = {
                        "interface_table_name": op_ne(NULL),
                    };
                    # include the logger for the omq datasource if available
                    if (omq_loggerid) {
                        select_hash."where" = wop_or(select_hash."where", {
                            "loggerid": omq_loggerid,
                        });
                    }
                }
                logger_info = loggers.select(select_hash);
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (*string msg = trans.restartTransaction(ex)) {
                    log(LL_INFO, msg);
                    continue;
                }
                rethrow;
            }
            break;
        }

        context (logger_info) {
            hash<auto> row = %%;
            # convert NULLs to NOTHING
            map delete row.$1, keys row, row.$1 === NULL;

            hash<auto> params;
            if (%params) {
                hash<auto> tmp_params = parse_yaml(%params);
                if (tmp_params.appenders) {
                    params.appenders = map {$1.key: cast<hash<AppenderParams>>($1.value)},
                        tmp_params.appenders.pairIterator();
                }
                params += tmp_params - "appenders";
                loggerMap{%loggerid}.params = cast<hash<LoggerParams>>(params);
            }

            loggerMap{%loggerid} += row - "params";

            if (%interface_table_name) {
                aliases{%interface_table_name} = %loggerid;
            }
        }

        return {
            "loggerMap": loggerMap,
            "loggerAliases": aliases,
        };
    }
%endif

    private abstract logImpl(int lvl, string msg);
}

# variant that handles an empty arg and returns no value
sub convert_logger_params() {
}

hash<LoggerParams> sub convert_logger_params(hash<auto> h) {
    hash<LoggerParams> rv();
    if (h.appenders) {
        rv.appenders = map {$1.key: cast<hash<AppenderParams>>($1.value)}, (remove h.appenders).pairIterator();
    }
    rv += h;
    return rv;
}

hash<LoggerParams> sub convert_logger_params(string paramsStr) {
    *hash<auto> params = parse_yaml(paramsStr);
    if (!params) {
        throw "LOGGER-PARAMS-PARSE-ERROR", sprintf("can not parse received logger params %s", paramsStr);
    }
    hash<string, hash<AppenderParams>> appenders = map {$1.key: cast<hash<AppenderParams>>($1.value)},
        params.appenders.pairIterator();
    delete params.appenders;
    hash<LoggerParams> loggerParams = cast<hash<LoggerParams>>(params);
    loggerParams.appenders = appenders;
    return loggerParams;
}

*hash<LoggerParams> sub substituteLogFilename(*hash<LoggerParams> params, hash<LogFilenameSubs> subs) {
    if (!params.appenders) {
        return params;
    }

    foreach string id in (keys params.appenders) {
        reference app = \params.appenders{id};
        if (app.appenderType == "LoggerAppenderFileRotate" ||
            app.appenderType == "LoggerAppenderFile") {
            *string filename = app.filename;
            if (filename) {
                map filename = replace(filename, "$" + $1.key, $1.value), subs.pairIterator();
                app.filename = filename;
            }
        }
    }

    return params;
}

LoggerAppender sub createAppender(hash<AppenderParams> appenderParams) {
    LoggerAppender appender;
    switch (appenderParams.appenderType) {
        case "LoggerAppenderFileRotate": {
            appender = new LoggerAppenderFileRotate(
                appenderParams.name,
                new LoggerLayoutPattern(appenderParams.layoutPattern),
                appenderParams.filename,
                appenderParams.rotationCount,
                appenderParams.archivePattern,
                appenderParams.encoding);
            break;
        }
        case "LoggerAppenderFile": {
            appender = new LoggerAppenderFile(
                appenderParams.name,
                new LoggerLayoutPattern(appenderParams.layoutPattern),
                appenderParams.filename,
                appenderParams.encoding);
            break;
        }
        case "LoggerAppenderStdOut": {
            appender = new LoggerAppenderStdOut(
                appenderParams.name,
                new LoggerLayoutPattern(appenderParams.layoutPattern));
            break;
        }
        default: {
            printf("unknown logger appender type %s", appenderParams.appenderType);
            appender = new LoggerAppenderStdOut(
                appenderParams.name,
                new LoggerLayoutPattern(appenderParams.layoutPattern));
        }
    }
    return appender;
}

Logger sub createLogger(*hash<LoggerParams> loggerParams) {
%ifdef QorusServer
    if (!loggerParams) {
        # stdout params
        return createEmptyLogger();
    }

    # respect given lvl
    int loggerLevel = loggerParams{"level"};
    Logger logger = new Logger(loggerParams{"name"});
    logger.setLevel(loggerLevel);
    if (loggerParams{"additivity"}) {
        logger.setAdditivity(loggerParams{"additivity"});
    }

    foreach hash<AppenderParams> appender_params in (loggerParams.appenders.iterator()) {
        LoggerAppender appender = createAppender(appender_params);
        appender.open();
        logger.addAppender(appender);
    }

    return logger;
%endif
}

Logger sub createEmptyLogger() {
    Logger logger("EmptyLogger");
    logger.setLevel(Logger::LoggerLevel::INFO);
    return logger;
}
