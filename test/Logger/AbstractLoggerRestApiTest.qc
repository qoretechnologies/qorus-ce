#!/usr/bin/env qore
%new-style
%enable-all-warnings
%strict-args
%require-types

%requires QUnit
%requires QorusClientCore
%requires Logger
%requires yaml

%include ../Classes/AbstractLogger.qc
%include ../Classes/LoggerController.qc

sub QDBG_ASSERT(softbool x) {}

int sub convert_old_log_level(int old_lvl) {
    return 1;
}

class SegmentManager {
    updateLogger(*string workflowName) {}
}

class ServiceManager {
    updateLogger(*string serviceName) {}
}

class JobManager {
    updateLogger(*string jobName) {}
}

class App {
    public {
        JobManager jobManager;
        auto qmm;
        auto options;
        auto events;
        auto dsmanager;
        auto alerts;
        auto audit;
        auto httpServer;
    }
    updateQdspLogger() {}
    updateLogger() {}
    updateQorusMasterLogger() {}
}

class WorkflowRestClass {
    static softint staticGetWorkflowId(softstring arg, bool check = False, *reference wh) {
        return 0;
    }
}

class ServiceRestClass {
    static softint staticGetServiceId(softstring arg, bool check = False, *reference sh) {
        return 0;
    }
}

class JobRestClass {
    static softint staticGetJobId(softstring arg, bool check = False, *reference sh) {
        return 0;
    }
}

class OMQ::ConnectionsServer {
    public static updateLogger() {}
}

# A workaround for Qorus4 process split
class QdspClient inherits DatasourcePool {
    constructor(AbstractDatasource ds) : DatasourcePool(ds.getConfigString()) {}
};

our SQLInterface sqlif;
our SegmentManager SM;
our ServiceManager services;
our App Qorus;
our QdspClient omqp;

const CONFIGURABLE_SYSTEM_TYPES = ("audit", "alert", "monitoring", "http", "qorus-core", "qorus-master");

sub qlog(auto level, string msg) {
    printf("%y: %d: %s\n", now(), level, vsprintf(msg, argv));
}

class AbstractLoggerRestApiTest inherits QUnit::Test {
    private {
        hash<string, hash> defParams;
        hash<string, hash> defAppParams;

        const INTERFACES_URLS = (
            "/workflows/",
            "/services/",
            "/jobs/",
            "/remote/datasources/",
        );

        const INTERFACE_URLS = (
            INTERFACES_URLS[0] + "TEST-LOGGER-WORKFLOW/logger",
            INTERFACES_URLS[1] + "test-logger-service/logger",
            INTERFACES_URLS[2] + "test-logger-job/logger",
            INTERFACES_URLS[3] + "omq/logger",
        );

        string SYSTEM_URL = "/system/";

        const SYSTEM_URLS = map "/system/" + $1 + "/logger", CONFIGURABLE_SYSTEM_TYPES;

        const FILE_APPENDERS_URLS = ("?file", "?file_rotate", "?file_ring");

        /*
        # default service logger params
        hash<auto> defSvcParams = {
            "level": {"INFO": Logger::LoggerLevel::INFO},
            "name": "DefaultServiceLogger",
            "additivity": False,
        };

        # default service logger appender params
        hash defSvcAppParams = {
            "name": "DefaultServiceAppender",
            "layoutPattern": "%m%n",
            "rotationCount": 10,
            "appenderType": "LoggerAppenderFileRotate",
            "filename": "$pathOMQ-$instance-SVC-$name.log",
            "encoding" : "UTF-8",
            "archivePattern" : "%p%f.%i",
        };

        # default workflow logger params
        hash<auto> defWfParams = {
            "level": {"INFO": Logger::LoggerLevel::INFO},
            "name": "DefaultWorkflowLogger",
            "additivity": False,
        };

        # default workflow logger appender params
        hash defWfAppParams = {
            "name": "DefaultWorkflowAppender",
            "layoutPattern": "%m%n",
            "rotationCount": 10,
            "appenderType": "LoggerAppenderFileRotate",
            "filename": "$pathOMQ-$instance-WF-$name.log",
            "encoding" : "UTF-8",
            "archivePattern" : "%p%f.%i",
        };

        # default job logger params
        hash<auto> defJobParams = {
            "level": {"INFO": Logger::LoggerLevel::INFO},
            "name": "DefaultJobLogger",
            "additivity": False,
        };

        # default job logger appender params
        hash defJobAppParams = {
            "name": "DefaultJobAppender",
            "layoutPattern": "%m%n",
            "rotationCount": 10,
            "appenderType": "LoggerAppenderFileRotate",
            "filename": "$pathOMQ-$instance-JOB-$name.log",
            "encoding" : "UTF-8",
            "archivePattern" : "%p%f.%i",
        };

        # default system logger params
        hash<auto> defSysParams = {
            "level": {"INFO": Logger::LoggerLevel::INFO},
            "name": "DefaultSystemLogger",
            "additivity": False,
        };

        # default system logger appender params
        hash defSysAppParams = {
            "name": "DefaultSystemAppender",
            "layoutPattern": "%m%n",
            "rotationCount": 10,
            "appenderType": "LoggerAppenderFileRotate",
            "filename": "$pathOMQ-$instance-$name.log",
            "encoding" : "UTF-8",
            "archivePattern" : "%p%f.%i",
        };
        */
    }

    constructor(string name) : Test(name, OMQ::version) {
        QorusClient::init2();
        # !!!!!! before test run, make sure test interfaces are oloaded !!!!!!
        #    wf(TEST-LOGGER-WORKFLOW)
        #    svc(test-logger-service)
        #    job(test-logger-job)

        # ensure interfaces are loaded
        qrest.put("workflows/TEST-LOGGER-WORKFLOW/setAutostart?autostart=1");
        on_exit {
            qrest.put("workflows/TEST-LOGGER-WORKFLOW/setAutostart?autostart=1");
        }
        qrest.put("services/test-logger-service/load");
        on_exit {
            qrest.put("services/test-logger-service/unload");
        }

        map (
            defParams{$1} = getLoggerParams($1),
            defAppParams{$1} = getLoggerAppenderParams($1),
        ), INTERFACE_URLS;

        map (
            defParams{$1} = getDefaultLoggerParams($1),
            defAppParams{$1} = getDefaultLoggerAppenderParams($1),
        ), INTERFACES_URLS;

        defParams{SYSTEM_URL} = getDefaultLoggerParams(SYSTEM_URL);
        defAppParams{SYSTEM_URL} = getDefaultLoggerAppenderParams(SYSTEM_URL);
    }

    hash<auto> getDefaultLoggerParams(string url) {
        return qrest.get(url + "/defaultLogger").params;
    }

    hash<auto> getDefaultLoggerAppenderParams(string url) {
        return qrest.get(url + "/defaultLoggerAppenders")[0].params;
    }

    hash<auto> getRestoreLoggerParams(hash<auto> params) {
        return params + {
            "level": params.level.firstKey(),
        };
    }

    hash<auto> getLoggerParams(string url) {
        on_error printf("url: %y (params)\n", url);
        return qrest.get(url).params;
    }

    hash<auto> getLoggerAppenderParams(string url) {
        on_error printf("url: %y (params)\n", url + "/appenders");
        return qrest.get(url + "/appenders")[0].params;
    }
}
