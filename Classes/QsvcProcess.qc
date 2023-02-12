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

# process network id is "qsvc-type-name-v<ver>-<svcid>"
class QsvcProcess inherits AbstractQorusInterfaceProcess {
    private {
        string svctype;
        string svcname;
        string svcversion;
        softint svcid;
        *hash<LoggerParams> logger_params;
    }

    # NOTE: changes to the constructor signature require changes to getConstructorArgsImpl()
    constructor(AbstractQorusProcessManager parent, string node, string host, bool restarted, softstring serviceid,
            string svctype, string svcname, string svcversion, int stack_size,
            *hash<LoggerParams> logger_params, *softlist<softstring> cl_opts)
            : AbstractQorusInterfaceProcess(parent, node, host, QDP_NAME_QSVC,
                qsvc_get_process_id(svctype, svcname, svcversion, serviceid), restarted, stack_size,
                cl_opts) {
        svcid = serviceid;
        self.svctype = svctype;
        self.svcname = svcname;
        self.svcversion = svcversion;
        self.logger_params = logger_params;
    }

    addToCore(QorusCoreProcess proc) {
        proc.addRunningService(getServiceRecoveryKey());
    }

%ifdef QorusDebugInternals_X
    Queue sendNotifyAbortedProcess(string other_id, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        QDBG_LOG("QsvcProcess::sendNotifyAbortedProcess() other_id: %y stack: %N", other_id, get_stack());
        return AbstractQorusInterfaceProcess::sendNotifyAbortedProcess(other_id, info, restarted, abort_timestamp);
    }
%endif

    private Process startImpl() {
        # the first seven args must be api_level, master_urls, interfaces, network_key_path, id, client_id, log path, and restarted
        #hash opts = parent.getOptions();

        list<auto> args = getCommonStartArgs() + (
            svcname,
            svcversion,
            stack_size,
            svctype,
        );

        # include defines in child process
        args += map sprintf("-D%s=%s", $1.key, $1.value), parent.getRuntimeProps().pairIterator();

        if (cl_opts) {
            args += cl_opts;
        }

        logInfo("starting %s %y with args: %y", name, id, args);
        hash<auto> env = ENV + {
            ENV_LOGGER_PARAMS: logger_params ? make_yaml(logger_params) : NOTHING,
        };
        /*
        if (svcname == "xxx") {
            # XXX DEBUG START: RUN IN DEBUGGER
            string envstr = sprintf("LOGGER_PARAMS='%s'", trim(env.LOGGER_PARAMS));
            logInfo("START %s gdb --args qsvc %s", envstr, (foldl $1 + " " + $2, args));

            *softint pid;
            do {
                usleep(500ms);
                pid = `ps ax | grep qsvc.*ondewo-bpi-test | grep -v -e grep -e gdb -e tail -e less| cut -b1-7`;
            } while (!pid);

            child = False;
            logInfo("got PID %d; sleeping 10s", pid);
            sleep(10s);
            return new Process(pid);
            # XXX DEBUG END: RUN IN DEBUGGER
        } else {
        */
        return new Process(name, args, {"env": env});
        #}
    }

    #! Called when the process terminates unexpectedly; returns True if the process should be restarted
    bool restartProcess() {
        return True;
    }

    int getServiceId() {
        return svcid;
    }

    softstring getServiceRecoveryKey() {
        return svcid;
    }

    # gets information about the process
    hash<auto> getInfo() {
        return AbstractQorusInternProcess::getInfo() + getProcessInfo();
    }

    # returns information needed to restart the process if it terminates unexpectedly (or is killed)
    *hash<auto> getProcessInfo() {
        return AbstractQorusInterfaceProcess::getProcessInfo() + {
            "svctype": svctype,
            "svcname": svcname,
            "svcversion": svcversion,
            "svcid": svcid,
        };
    }

    #! create the client object
    private AbstractQorusClient getClientImpl() {
        return new AbstractQorusClient(parent, QDP_NAME_QSVC, client_id);
    }

    #! returns all constructor arguments after "host"
    private list<auto> getConstructorArgsImpl() {
        return (
            restarted,
            svcid,
            svctype,
            svcname,
            svcversion,
            stack_size,
            logger_params,
            cl_opts,
        );
    }
}
