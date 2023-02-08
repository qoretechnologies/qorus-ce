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

%requires FsUtil

/**
    Wrapper class for 3rd-party prometheus process
*/
class PrometheusProcess inherits AbstractQorusExternProcess {
    private {
        #! port on which Prometheus is listening (is set in startImpl() method)
        int port = 0;

        #! path to auto-generated config, relative to $OMQ_DIR
        const ConfigFile = "etc/prometheus/prometheus.yaml";

        #! path to template config, relative to $OMQ_DIR
        const ConfigFileTemplate = "etc/prometheus/prometheus-template.yaml";

        #! path to data dir, relative to $OMQ_DIR
        const DataDir = "srv/prometheus/data";
    }

    constructor(AbstractQorusProcessManager parent, string node, string host, *int port, *hash<LoggerParams> loggerParams)
        : AbstractQorusExternProcess(parent, node, host, QDP_NAME_PROMETHEUS, loggerParams) {
        if (port) {
            self.port = port;
        }
    }

    int getPort() {
        return port;
    }

    #! returns a descriptive string of the network interface(s) for this process
    string getNetworkDescription() {
        return sprintf("http://localhost:%d", port);
    }

    hash<auto> getInfo() {
        return AbstractQorusProcess::getInfo() + {
            "log_pipe": logPipePath,
        } + getProcessInfo();
    }

    # returns information needed to restart the process if it terminates unexpectedly (or is killed)
    *hash<auto> getProcessInfo() {
        return {
            "port": port,
        };
    }

    processAborted() {
        AbstractQorusProcess::processAborted();
        stopLogWrapper();
    }

    #! Creates the process object based on the PID and sets the child flag to False
    setDetached(int pid, *list<string> urls, date started) {
        AbstractQorusProcess::setDetached(pid, NOTHING, started);
        # start the log wrapper if necessary
        createLogWrapper();
    }

    # override
    private Process startImpl() {
        createConfigFile();

        # prepare new free port for Prometheus if launching the first time
        int orig_port = port;
        {
            Socket sock();
            port = bindSocket(sock, port);
        }

        on_success {
            # update grafana if the port could not be reused
            if (orig_port && orig_port != port) {
                cast<QorusMaster>(parent).prometheusPortChange(port);
            }
        }

        list<string> args = (
            "--config.file=" + getConfigFilePath(),
            "--storage.tsdb.path=" + getDataDirPath(),
            "--web.listen-address=:" + port,
        );

        QDBG_LOG("starting %s on port: %y with args: %y", getName(), port, args);

        return startExternProcess(args);
    }

    #! creates the log wrapper object
    synchronized private createLogWrapper() {
        if (!logWrapper) {
            logWrapper = new PrometheusLogPipeWrapper(createLogger(loggerParams), logPipePath);
        }
    }

    #! binds the socket on the given port and returns the port bound (in case the input port is 0)
    private int bindSocket(Socket socket, int port) {
        if (socket.bind(port, True)) {
            if (!port) {
                throw "SOCKET-BIND-ERROR", sprintf("Bind to auto generated port (0) for Prometheus failed: %s", strerror());
            }
            # we cannot reuse the same port; we need to update the port and update grafana as well
            return bindSocket(socket, 0);
        }
        return socket.getPort();
    }

    private string getConfigTemplatePath() {
        return join_paths(ENV.OMQ_DIR, ConfigFileTemplate);
    }

    private string getConfigFilePath() {
        return join_paths(ENV.OMQ_DIR, ConfigFile);
    }

    private string getDataDirPath() {
        return join_paths(ENV.OMQ_DIR, DataDir);
    }

    private createConfigFile() {
        # extract scheme and base url with port from local url
        # TODO @OS@ we should use qorus socket instead of port
        *list<*string> endpoint = regex_extract(qorusGetLocalUrl(), "^(https?):\/\/([^/]+)");
        hash<string, string> replacements = {
            "qorus_scheme": endpoint[0],
            "qorus_endpoint": endpoint[1],
        };

        ConfFileFromTemplate::replaceAndFlush(
            parent,
            getConfigTemplatePath(),
            replacements,
            getConfigFilePath()
        );
    }

    #! returns all constructor arguments after "host"
    private list<auto> getConstructorArgsImpl() {
        return (
            port,
            loggerParams,
        );
    }
}

class PrometheusLogPipeWrapper inherits LogPipeWrapper {
    private {
        #! prometheus log level map
        const LogMap = {
            "debug": LoggerLevel::DEBUG,
            "info": LoggerLevel::INFO,
            "warn": LoggerLevel::WARN,
            "error": LoggerLevel::ERROR,
        };
    }

    constructor(Logger logger, string logPipePath)
        : LogPipeWrapper(logger, logPipePath, QDP_NAME_PROMETHEUS) {
    }

    #! this method will read in a log line from the stream and issue it to the logger
    /** translates prometheus levels to logger levels
    */
    readLineAndLog(StreamReader log_reader) {
        *string log_str = log_reader.readLine();
        if (log_str) {
            # get level
            *string lvl = (log_str =~ x/^level=([a-z]+)/)[0];
            int log_lvl = LogMap{lvl} ?? LoggerLevel::INFO;
            if (lvl.val()) {
                # remove level from string
                splice log_str, 0, 7 + lvl.length();
            }
            Qorus.logExtern("prometheus", logger, log_lvl, log_str);
        }
    }
}