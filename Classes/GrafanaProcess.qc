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

/**
    Wrapper class for grafana-server process.
*/
class GrafanaProcess inherits AbstractQorusExternProcess {
    private {
        #! the path used for the local UNIX domain socket for this grafana instance
        string socket_path;

        #! the local URL used to access grafana
        string local_url;

        #! prometheus port
        int prometheus_port;

        #! grafana home directory, relative from $OMQ_DIR
        const HomeDir = "srv/grafana";

        #! dir path relative to Qorus log dir (empty to use just the Qorus log dir)
        const LogDir = "grafana";

        #! path to auto-generated config file, relative to $OMQ_DIR
        const ConfigFile = "etc/grafana/grafana.ini";

        #! path to config file template, relative to $OMQ_DIR
        const ConfigFileTemplate = "etc/grafana/grafana-template.ini";

        const PrometheusDatasourceFile = "conf/provisioning/datasources/qorus-prometheus.yaml"; # relative to HomeDir
        const PrometheusDatasourceFileTemplate = "etc/grafana/grafana-prometheus-datasource-template.yaml"; # relative to $OMQ_DIR

        const DashboardFile = "conf/provisioning/dashboards/grafana-dashboard.yaml"; # relative to HomeDir
        const DashboardFileTemplate = "etc/grafana/grafana-dashboard-template.yaml"; # relative to $OMQ_DIR

        const DashboardJsonFile = "etc/grafana/grafana-dashboard.json"; # relative to $OMQ_DIR
    }

    constructor(AbstractQorusProcessManager parent, string node, string host, int prometheus_port, *string socket_path,
        *hash<LoggerParams> loggerParams)
        : AbstractQorusExternProcess(parent, node, host, QDP_NAME_GRAFANA, loggerParams) {
        self.prometheus_port = prometheus_port;

        # setup socket path; save in the temporary directory
        if (socket_path) {
            self.socket_path = socket_path;
        } else {
            string socket_file = sprintf("qorus-%s-grafana.sock", Qorus.options.get("instance-key"));
            # substitute invalid characters
            socket_file =~ s/[\/#:]/_/g;
            self.socket_path = join_paths(tmp_location(), socket_file);
        }

        local_url = qorusGetLocalUrl()
            + "/grafana"
            ;
    }

    #! returns all constructor arguments after "host"
    private list<auto> getConstructorArgsImpl() {
        # FIXME
        throw "UNSUPPORTED", "grafana must start on the same node as qorus-core or use a regular socket";
        /*
        return (
            prometheus_port,
            socket_path,
            loggerParams,
        );
        */
    }

    processAborted() {
        AbstractQorusProcess::processAborted();
        stopLogWrapper();
    }

    #! called when the prometheus process is restarted, but cannot be restarted on the same port
    prometheusPortChange(int port) {
        AutoLock al(m);

        waitForNotStatusIntern(CS_STARTING);

        prometheus_port = port;

        # if the process is running, then restart it
        if (status == CS_RUNNING) {
            # grafana must be restarted when the prometheus port changes; there is currently no way to reload the grafana
            # configuration at runtime, despite several requests for this feature (2019-07-14)
            logInfo("prometheus port updated to %d: restarting grafana process with the new configuration", port);
            # stop grafana
            setStatusIntern(CS_STOPPING);
            killProcess();
            setStatusIntern(CS_IDLE);
            logInfo("%s %y: stopped process PID %d", getName(), getId(), getPid());
            # update datasource config file with new prometheus port
            setupDatasource();
            # release lock
            delete al;
            # restart grafana
            start();
        } else {
            logInfo("prometheus port updated to %d: grafana process not running", port);
        }
    }

    #! returns a descriptive string of the network interface(s) for this process
    string getNetworkDescription() {
        return sprintf("socket://%s", socket_path);
    }

    hash<auto> getInfo() {
        return AbstractQorusProcess::getInfo() + {
            "log_pipe": logPipePath,
        } + getProcessInfo();
    }

   # returns information needed to restart the process if it terminates unexpectedly (or is killed)
    *hash<auto> getProcessInfo() {
        return {
            "prometheus_port": prometheus_port,
            "socket_path": socket_path,
        };
    }

    #! Creates the process object based on the PID and sets the child flag to False
    setDetached(int pid, *list<string> urls, date started) {
        AbstractQorusProcess::setDetached(pid, NOTHING, started);
        # start the log wrapper if necessary
        createLogWrapper();
    }

    # override
    private Process startImpl() {
        setupConfigFile();
        setupDatasource();
        setupDashboard();

        list<string> args = (
            "-config=" + getConfigFilePath(),
            "-homepath=" + getHomeDirPath(),
        );

        # must delete the socket path before starting in case it was left in place
        unlink(socket_path);

        return startExternProcess(args);
    }

    synchronized private createLogWrapper() {
        if (!logWrapper) {
            logWrapper = new GrafanaLogPipeWrapper(createLogger(loggerParams), logPipePath);
        }
    }

    private string getHomeDirPath() {
        return join_paths(ENV.OMQ_DIR, HomeDir);
    }

    private string getLogDirPath() {
        return join_paths(Qorus.options.get("logdir"), LogDir);
    }

    private string getConfigFilePath() {
        return join_paths(ENV.OMQ_DIR, ConfigFile);
    }

    private string getConfigTemplatePath() {
        return join_paths(ENV.OMQ_DIR, ConfigFileTemplate);
    }

    private string getPrometheusDatasourcePath() {
        return join_paths(getHomeDirPath(), PrometheusDatasourceFile);
    }

    private string getPrometheusDatasourceTemplatePath() {
        return join_paths(ENV.OMQ_DIR, PrometheusDatasourceFileTemplate);
    }

    private string getDashboardPath() {
        return join_paths(getHomeDirPath(), DashboardFile);
    }

    private string getDashboardTemplatePath() {
        return join_paths(ENV.OMQ_DIR, DashboardFileTemplate);
    }

    private string getDashboardJsonPath() {
        return join_paths(ENV.OMQ_DIR, DashboardJsonFile);
    }

    private setupConfigFile() {
        hash<string, string> replacements = {
            "qorus_instance_name": Qorus.options.get("instance-key"),
            "qorus_log_directory": getLogDirPath(),
            "grafana_socket_path": socket_path,
            "grafana_local_url": local_url,
        };

        ConfFileFromTemplate::replaceAndFlush(
            parent,
            getConfigTemplatePath(),
            replacements,
            getConfigFilePath()
        );
    }

    private setupDatasource() {
        hash<string, string> replacements = {
            # TODO @OS@ prometheus url is enough this way?
            "prometheus_url": sprintf("http://localhost:%s", prometheus_port),
        };

        ConfFileFromTemplate::replaceAndFlush(
            parent,
            getPrometheusDatasourceTemplatePath(),
            replacements,
            getPrometheusDatasourcePath()
        );
    }

    private setupDashboard() {
        hash<string, string> replacements = {
            "dashboard_url": getDashboardJsonPath(),
        };

        ConfFileFromTemplate::replaceAndFlush(
            parent,
            getDashboardTemplatePath(),
            replacements,
            getDashboardPath()
        );
    }
}

class GrafanaLogPipeWrapper inherits LogPipeWrapper {
    private {
        #! grafana log level map
        const LogMap = {
            "debug": LoggerLevel::DEBUG,
            "info": LoggerLevel::INFO,
            "warn": LoggerLevel::WARN,
            "error": LoggerLevel::ERROR,
            "critical": LoggerLevel::FATAL,
        };
    }

    constructor(Logger logger, string logPipePath)
        : LogPipeWrapper(logger, logPipePath, QDP_NAME_GRAFANA) {
    }

    #! this method will read in a log line from the stream and issue it to the logger
    /** translates grafana levels to logger levels
    */
    readLineAndLog(StreamReader log_reader) {
        *string logStr = log_reader.readLine();
        if (logStr) {
            try {
                hash<auto> msg = parse_json(logStr);
                int log_lvl = LogMap{msg.lvl} ?? LoggerLevel::INFO;
                string msg_str = foldl $1 + ", " + $2, (map sprintf("%s=%y", $1.key, $1.value), msg.pairIterator());
                Qorus.logExtern("grafana", logger, log_lvl, msg_str);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "JSON-PARSE-ERROR") {
                    Qorus.logExtern("grafana", logger, LoggerLevel::INFO, sprintf("ERROR: %s", logStr));
                } else {
                    Qorus.logExtern("grafana", logger, LoggerLevel::ERROR, get_exception_string(ex));
                }
                rethrow;
            }
        }
    }
}