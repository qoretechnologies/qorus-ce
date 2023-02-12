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

# process network id is "qjob-name-v<ver>-<jobid>"
class QjobProcess inherits AbstractQorusInterfaceProcess {
    private {
        string jobname;
        string jobversion;
        softint jobid;
        int sessionid;
        *hash<LoggerParams> logger_params;
    }

    # NOTE: changes to the constructor signature require changes to getConstructorArgsImpl()
    constructor(AbstractQorusProcessManager parent, string node, string host, bool restarted, softstring jobid,
            string jobname, string jobversion, int stack_size, int sessionid, *hash<LoggerParams> logger_params,
            *softlist<softstring> cl_opts) :
            AbstractQorusInterfaceProcess(parent, node, host, QDP_NAME_QJOB,
                qjob_get_process_id(jobname, jobversion, jobid), restarted, stack_size, cl_opts) {
        self.jobid = jobid;
        self.jobname = jobname;
        self.jobversion = jobversion;
        self.sessionid = sessionid;
        self.logger_params = logger_params;
    }

    addToCore(QorusCoreProcess proc) {
        proc.addRunningJob(jobid);
    }

    private Process startImpl() {
        # the first seven args must be api_level, master_urls, interfaces, network_key_path, id, client_id, log path, and restarted
        #hash opts = parent.getOptions();

        list<auto> args = getCommonStartArgs() + (
            jobname,
            jobversion,
            stack_size,
            sessionid.toString(),
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
        if (jobname == "bb-test-ftp-job") {
            # XXX DEBUG START: RUN IN DEBUGGER
            string envstr = sprintf("LOGGER_PARAMS='%s'", trim(env.LOGGER_PARAMS));
            logInfo("START %s gdb --args qjob %s", envstr, (foldl $1 + " " + $2, args));

            *softint pid;
            do {
                usleep(500ms);
                pid = `ps ax | grep qjob.*bb-test-ftp-job | grep -v -e grep -e lldb -e gdb -e tail -e less| cut -b1-7`;
            } while (!pid);

            child = False;
            logInfo("got PID %d; sleeping 10s", pid);
            sleep(10s);
            return new Process(pid);
            # XXX DEBUG END: RUN IN DEBUGGER
        }
        */
        return new Process(name, args, {
            "env": env,
        });
    }

    int getJobId() {
        return jobid;
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
            "jobname": jobname,
            "jobversion": jobversion,
            "jobid": jobid,
            "sessionid": sessionid,
        };
    }

    #! create the client object
    private AbstractQorusClient getClientImpl() {
        return new AbstractQorusClient(parent, QDP_NAME_QJOB, client_id);
    }

    #! returns all constructor arguments after "host"
    private list<auto> getConstructorArgsImpl() {
        return (
            restarted,
            jobid,
            jobname,
            jobversion,
            stack_size,
            sessionid,
            logger_params,
            cl_opts,
        );
    }
}
