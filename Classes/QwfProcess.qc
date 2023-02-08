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

# process network id is "qwf-name-v<ver>-<wfid>"
class QwfProcess inherits AbstractQorusInterfaceProcess {
    private {
        string wfname;
        string wfversion;
        softint wfid;
        int sessionid;
        *hash<LoggerParams> logger_params;
    }

    # NOTE: changes to the constructor signature require changes to getConstructorArgsImpl()
    constructor(AbstractQorusProcessManager parent, string node, string host, bool restarted, softstring workflowid,
            string wfname, string wfversion, int stack_size, int sessionid, *hash<LoggerParams> logger_params,
            *softlist<softstring> cl_opts) : AbstractQorusInterfaceProcess(parent, node, host, QDP_NAME_QWF,
                qwf_get_process_id(wfname, wfversion, workflowid), restarted, stack_size, cl_opts) {
        wfid = workflowid;
        self.wfname = wfname;
        self.wfversion = wfversion;
        self.sessionid = sessionid;
        self.logger_params = logger_params;
    }

    addToCore(QorusCoreProcess proc) {
        proc.addRunningWorkflow(wfid);
    }

    private Process startImpl() {
        # the first seven args must be api_level, master_urls, interfaces, network_key_path, id, client_id, and restarted
        #hash opts = parent.getOptions();

        list<auto> args = getCommonStartArgs() + (
            wfname,
            wfversion,
            stack_size,
            sessionid.toString(),
        );

        # include defines in child process
        args += map sprintf("-D%s=%s", $1.key, $1.value), parent.getRuntimeProps().pairIterator();

        if (cl_opts) {
            args += cl_opts;
        }

        logInfo("starting %s %y with args: %y", name, id, args);
        return new Process(name, args, {
            "env": ENV + {
                ENV_LOGGER_PARAMS: logger_params ? make_yaml(logger_params) : NOTHING,
            }
        });
    }

    int getWorkflowId() {
        return wfid;
    }

    int getSessionId() {
        return sessionid;
    }

    # gets information about the process
    hash<auto> getInfo() {
        return AbstractQorusInternProcess::getInfo() + getProcessInfo();
    }

    # returns information needed to restart the process if it terminates unexpectedly (or is killed)
    *hash<auto> getProcessInfo() {
        return AbstractQorusInterfaceProcess::getProcessInfo() + {
            "wfname": wfname,
            "wfversion": wfversion,
            "wfid": wfid,
            "sessionid": sessionid,
        };
    }

    #! create the client object
    private AbstractQorusClient getClientImpl() {
        return new AbstractQorusClient(parent, QDP_NAME_QWF, client_id);
    }

    #! returns all constructor arguments after "host"
    private list<auto> getConstructorArgsImpl() {
        return (
            restarted,
            wfid,
            wfname,
            wfversion,
            stack_size,
            sessionid,
            logger_params,
            cl_opts,
        );
    }
}
