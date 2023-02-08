# -*- mode: qore; indent-tabs-mode: nil -*-

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

%requires SqlUtil

public namespace QorusLogger {

/**
    Help class to manage all loggers.
*/
class LoggerController {
    constructor() {
    }

    private throwBadRequest(list<auto> badParams) {
        throw "BAD-REQUEST", sprintf("Missing or bad params received: %y", badParams);
    }

    hash<AppenderParams> checkAndConvertAppenderParams(hash<auto> ah) {
        hash<AppenderParams> params = <AppenderParams>{
            "name": ah.name,
            "appenderType": ah.appenderType,
        };

        switch (ah.appenderType) {
            case "LoggerAppenderStdOut": {
                break;
            }
            case "LoggerAppenderFile": {
                if (!ah.filename) {
                    throwBadRequest(("filename",));
                }

                # set default params
                params.layoutPattern = ah.layoutPattern ?? LoggerLayoutPattern::DEFAULT_PATTERN;
                # issue #3158: do not allow an invalid encoding to be set, as it can prevent Qorus from starting
                params.encoding = checkEncoding(ah);
                params.filename = ah.filename;
                break;
            }
            case "LoggerAppenderFileRotate": {
                list<string> badParams();
                if (!ah.filename) {
                    push badParams, "filename";
                }
                if (ah.rotationCount) {
                    if (!ah.rotationCount.intp()) {
                        push badParams, "rotationCount";
                    } else {
                        ah.rotationCount = ah.rotationCount.toInt();
                    }
                }

                # set default params
                params.layoutPattern = ah.layoutPattern ?? LoggerLayoutPattern::DEFAULT_PATTERN;
                # issue #3158: do not allow an invalid encoding to be set, as it can prevent Qorus from starting
                params.encoding = checkEncoding(ah);
                params.rotationCount = ah.rotationCount ?? AbstractLoggerAppenderFileRotate::DEFAULT_ROTATION_COUNT;
                params.archivePattern = ah.archivePattern ?? LoggerAppenderFileRotate::DEFAULT_ARCHIVE_PATTERN;

                if (badParams) {
                    throwBadRequest(badParams);
                }

                params.filename = ah.filename;
                break;
            }
            default:
                throw "BAD-REQUEST", sprintf("Unknown logger appender type %y", ah.appenderType);
        }
        return params;
    }

    private string checkEncoding(hash<auto> ah) {
        if (!ah.encoding.val()) {
            return get_default_encoding();
        }

        # issue #3158: do not allow an invalid encoding to be set, as it can prevent Qorus from starting
        try {
            string ignore = convert_encoding(" ", ah.encoding);
            remove ignore;
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "ENCODING-CONVERSION-ERROR") {
                throw "INVALID-APPENDER-ENCODING", sprintf("encoding %y for appender %y is invalid; please try "
                    "again with a valid encoding (ex: \"UTF-8\")", ah.encoding,
                    ah.name ?? "<unnamed appender");
            }
            rethrow;
        }
        return ah.encoding;
    }

    private checkLoggerLevel(int level, reference<hash> h) {
        if (!AVAILABLE_LEVELS{level}) {
            throw "BAD-REQUEST", sprintf("Unknown logger level, received %d, available levels: %y", level, AVAILABLE_LEVELS);
        }
    }

    private checkLoggerLevel(string level, reference<hash> h) {
        h.level = level.upr();
        if (!AVAILABLE_LEVELS_STR{h.level}) {
            throw "BAD-REQUEST", sprintf("Unknown logger level, received %s, available levels: %y", level, AVAILABLE_LEVELS);
        }
    }

    private checkLoggerLevel(auto level, reference<hash> h) {
        throw "BAD-REQUEST", sprintf("Unknown logger level, received %y, available levels: %y", level, AVAILABLE_LEVELS);
    }

    private *int getLoggerId(string type, auto pk) {
        return Qorus.qmm.lookupLogger(type, pk).loggerid;
    }

    private checkLoggerParams(reference<hash> params) {
        checkLoggerLevel(params.level, \params);
        # convert string lvl to int
        if (params.level.typeCode() == NT_STRING) {
            params.level = AVAILABLE_LEVELS_STR{params.level};
        }

        # set default params
        if (!params.hasKey("additivity")) {
            params.additivity = True;
        } else {
            params.additivity = parse_boolean(params.additivity);
        }

        if (params.appenders) {
            params.appenders = map {($# + 1).toString(): checkAndConvertAppenderParams($1)}, params.appenders;
        }
    }

    /** Return all system loggers

        @return list of available system loggers
    */
    *list<hash<auto>> getSystemLoggers() {
        list<hash<auto>> loggers;
        foreach string type in (keys SystemLoggersWithSystem) {
            # strip types to reformat the return type
            *hash<auto> logger = auto_cast(Qorus.qmm.lookupLogger(type, NOTHING, True));
            if (logger) {
                # extend logger level with string label
                logger.params.level = {
                    AVAILABLE_LEVELS{logger.params.level}: logger.params.level,
                };
                if (logger.params.appenders) {
                    logger.params.appenders = map (
                        "params": $1.value,
                        "appenderid": $1.key.toInt(),
                        "isDefault": logger.isDefault,
                    ), logger.params.appenders.pairIterator();
                }
                logger.interface_table_name = logger.interface_table_name.lwr();
                logger.type = logger.interface_table_name;
                loggers += logger;
            }
        }
        return loggers;
    }

    /** Return logger params together with params of appenders assigned to

        @param type logger type (e.g. services/jobs/workflows/qdsp or system type - AUDIT, ALERT, HTTP, etc)
        @param pk the PK for the interface table

        @return logger parameters with assigned to it appenders parameters
    */
    *hash<LoggerParams> getLoggerParams(string type, auto pk) {
        *hash<LoggerParams> loggerParams = Qorus.qmm.lookupLogger(type, pk).params;
        if (!loggerParams) {
            # rare case, there should always be at least a default logger
            if (pk) {
                qlog(LoggerLevel::DEBUG, "No logger params for %y (interface) with ID %y found", type, pk);
            } else {
                qlog(LoggerLevel::DEBUG, "No logger params for %y found", type);
            }
            return;
        }

        return loggerParams;
    }

    /** Return logger params together with params of appenders assigned to

        @param type logger type (e.g. services/jobs/workflows/qdsp or system type)
        @param interfaceId interface id

        @return logger parameters with assigned to it appenders parameters with substituted template log filename
    */
    *hash<LoggerParams> getLoggerParamsSubs(string type, *hash<LogFilenameSubs> subs, auto pk) {
        return substituteLogFilename(getLoggerParams(type, pk), getLoggerSubs(type, subs));
    }

    #! returns a filename substitution hash corresponding to the arguments
    static hash<LogFilenameSubs> getLoggerSubs(string type, *hash<LogFilenameSubs> subs) {
        if (!subs) {
            subs = <LogFilenameSubs>{
                "name": type,
            };
        }
        subs += {
            "path": Qorus.options.get("logdir"),
            "instance": Qorus.options.get("instance-key"),
        };
        return subs;
    }

    /** Update existing logger

        @param interfaceTableName interface table name (e.g. services/jobs/workflows)
        @param params logger params to update
        @param pk the PK value for the interface

        @throw INVALID-INTERFACE no such interface exists
        @throw BAD-REQUEST if the logger params are invalid
        @throw NO-LOGGER no such logger
    */
    updateLogger(string type, auto pk, hash<auto> params) {
        *hash<auto> loggerInfo = Qorus.qmm.lookupLogger(type, pk);
        if (!loggerInfo) {
            if (pk) {
                throw "NO-LOGGER", sprintf("No logger params for %s ID %y found, or it uses the default system "
                    "params", type, pk);
            }
            throw "NO-LOGGER", sprintf("No logger params for %s found, or it uses the default system params", type);
        }

        *hash<LoggerParams> currentParams = cast<hash<LoggerParams>>(loggerInfo.params);
        *hash<LoggerParams> newParams = currentParams;
        if (params.hasKey("level")) {
            checkLoggerLevel(params.level, \params);

            # convert string lvl to int
            if (params.level.typeCode() == NT_STRING) {
                params.level = AVAILABLE_LEVELS_STR{params.level};
            }
            newParams.level = params.level;
        }

        if (params.hasKey("name")) {
            newParams.name = params.name;
        }

        if (params.hasKey("additivity")) {
            newParams.additivity = params.additivity;
        }

        if (params.appenders) {
            newParams.appenders = map {($# + 1).toString(): checkAndConvertAppenderParams($1)}, params.appenders;
        }

        Qorus.qmm.updateLogger(type, pk, newParams);
    }

    /** Clone default interface logger with assigned to it appenders and assigned to the interface

        @param type system or interface type (e.g. workflows, jobs, services, AUDIT, ALERT, HTTP ...)
        @param colname the PK column name
        @param pk the PK value (ID or name) of the interface take

        @return created logger ID

        @throw LOGGER-EXISTS if the logger already exists
    */
    int cloneDefault(string type, *string colname, auto pk) {
        QDBG_ASSERT(type != "system");
        *hash<LoggerParams> params = getLoggerParams(type);

        if (!params) {
            # no default logger found
            if (colname) {
                qlog(LoggerLevel::DEBUG, "No logger params for %s interface with %s %y found", type, colname, pk);
            } else {
                qlog(LoggerLevel::DEBUG, "No default system logger params found");
            }
            return -1;
        }

        # rename logger
        params.name = "CloneOf" + params.name;

        # rename appenders
        params.appenders = map {
            $1.key: cast<hash<AppenderParams>>($1.value + {"name": "CloneOf" + $1.value.name}),
        }, params.appenders.pairIterator();
        return Qorus.qmm.createLogger(type, colname, pk, params);
    }

    /** Create logger based on the received params

        @param type interface table name (e.g. services/jobs/workflows)
        @param colname the PK's column name
        @param pk PK value in interface table
        @param params interface params

        @return the logger ID created

        @throw BAD-REQUEST if received logger level can not be converted to @ref Logger::LoggerLevel "LoggerLevel"
        @throw LOGGER-EXISTS if the logger already exists
    */
    int createLogger(hash<auto> params, string type, *string colname, auto pk) {
        checkLoggerParams(\params);
        return Qorus.qmm.createLogger(type, colname, pk, convert_logger_params(params));
    }

    /** Return assigned to logger appenders

        @param type logger type (e.g. services/jobs/workflows or HTTP/AUDIT/etc)
        @param pk PK value in interface table

        @return appenders
    */
    *list<hash<auto>> getAppenders(string type, auto pk) {
        *hash<auto> logger = Qorus.qmm.lookupLogger(type, pk);
        if (!logger) {
            return;
        }
        return map (
            "params": $1.value,
            "appenderid": $1.key.toInt(),
            "isDefault": logger.isDefault,
        ), logger.params.appenders.pairIterator();
    }

    /** Create appender based on received params
        @param type interface table name (e.g. services/jobs/workflows)
        @param params appender params
        @param pk PK value in interface table

        @return created appender id

        @throw NO-LOGGER the given logger does not exist
    */
    int addAppender(string type, auto pk, hash<auto> ah) {
        return Qorus.qmm.addAppender(type, pk, checkAndConvertAppenderParams(ah));
    }
}

} # namespace QorusLogger
