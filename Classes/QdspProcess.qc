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

# process network id is "qdsp-<dsname>"
class QdspProcess inherits AbstractQorusInternProcess {
    private {
        string connstr;
        *hash<LoggerParams> logger_params;
    }

    # NOTE: changes to the constructor signature require changes to getConstructorArgsImpl()
    constructor(AbstractQorusProcessManager parent, string node, string host, bool restarted, string dsname, string connstr,
            *hash<LoggerParams> logger_params, *softlist<softstring> cl_opts)
            : AbstractQorusInternProcess(parent, node, host, QDP_NAME_QDSP, dsname, restarted, cl_opts) {
        self.connstr = connstr;
        self.logger_params = logger_params;
    }

    # returns True if the process needs a CPC_PROCESS_ABORT_NOTIFICATION message
    /** qdsp processes need this message
    */
    bool needsSendNotifyAbortedProcessInitial() {
        return True;
    }

    private Process startImpl() {
        hash<auto> opts = parent.getOptions();
        list<auto> args = getCommonStartArgs() + (
            opts."dsp-warning-timeout",
            opts."dsp-error-timeout",
            opts."default-datasource-coordinated",
        );
        if (opts."oracle-datasource-pool" && connstr =~ /^oracle:/) {
            args += "--oracle";
        }
        if (cl_opts) {
            args += cl_opts;
        }

        # FIXME: take into account LSB installations
        return new Process(name, args, {"env": ENV + {
            "CONNSTR": connstr,
            ENV_LOGGER_PARAMS: logger_params ? make_yaml(logger_params) : NOTHING,
        }});
    }

    # sends a message to a qdsp process with no response expected
    sendUpdateLoggerRequest(*hash<LoggerParams> params) {
        logDebug("signal qdsp process to update logger: %y", params);
        AbstractQorusClient client = getClient();
        client.sendCmdOneWay(CPC_UPDATE_LOGGER, params);
    }

    # sends a message to a qdsp process with no response expected
    sendRotateLoggerRequest() {
        logDebug("signal qdsp process to rotate log files");
        AbstractQorusClient client = getClient();
        client.sendCmdOneWay(CPC_ROTATE_LOGGER);
    }

    # gets information about the process
    hash<auto> getInfo() {
        return AbstractQorusInternProcess::getInfo() + (
            "connstr": connstr,
        );
    }

    # returns information needed to restart the process if it terminates unexpectedly (or is killed)
    *hash<auto> getProcessInfo() {
        return {
            "connstr": connstr,
        };
    }

    # updates process info at runtime
    updateProcessInfo(hash<auto> h) {
        connstr = h.connstr;
    }

    #! create the client object
    private AbstractQorusClient getClientImpl() {
        return new AbstractQorusClient(parent, QDP_NAME_QDSP, client_id);
    }

    #! returns all constructor arguments after "host"
    private list<auto> getConstructorArgsImpl() {
        return (
            restarted,
            client_id,
            connstr,
            logger_params,
            cl_opts,
        );
    }
}
