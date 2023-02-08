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

# process network id is "qorus-core"
class QorusCoreProcess inherits AbstractQorusInternProcess {
    private {
        string sessionid;
        list<int> running_wfid_list;
        list<string> running_svcid_list;
        list<int> running_jobid_list;
        *list<string> qdsp_recovery_list;

        AbstractQorusClient core;
    }

    # NOTE: changes to the constructor signature require changes to getConstructorArgsImpl()
    constructor(
            AbstractQorusProcessManager parent,
            string node,
            string host,
            bool restarted,
            string sessionid,
            list<int> running_wfid_list = (),
            list<string> running_svcid_list = (),
            list<int> running_jobid_list = (),
            *hash<string, AbstractQorusProcess> qdsp_recovery_map,
            *softlist<softstring> cl_opts) : AbstractQorusInternProcess(parent, node, host, QDP_NAME_QORUS_CORE, "-",
            restarted, cl_opts) {
        self.sessionid = sessionid;
        self.running_wfid_list = running_wfid_list;
        self.running_svcid_list = running_svcid_list;
        self.running_jobid_list = running_jobid_list;
        qdsp_recovery_list = map $1, keys qdsp_recovery_map, $1 != "omq";
    }

    # issue: #3346: when deleting clients after the event thread has been shut down, we need to remove the process
    # object before deleting or there will be a deadlock
    synchronized removeProcess() {
        if (core) {
            core.removeProcess();
        }
    }

    # clear interface lists and set session ID
    clearInterfaceLists(string sessionid) {
        running_wfid_list = new list<int>();
        running_svcid_list = new list<string>();
        running_jobid_list = new list<int>();
        self.sessionid = sessionid;
    }

    addRunningWorkflow(int wfid) {
        running_wfid_list += wfid;
    }

    addRunningService(string svckey) {
        running_svcid_list += svckey;
    }

    addRunningJob(int jobid) {
        running_jobid_list += jobid;
    }

    logEvent(string id, string msg) {
        if (core) {
            try {
                core.sendCmdOneWaySilent(CPC_CORE_LOG_IF, {"method": "logEvent", "args": (id, msg + "\n")});
            } catch (hash<ExceptionInfo> ex) {
                # ignore exceptions; we cannot log here anyway as it might create an infinite loop
            }
        }
    }

    #! checks qorus-core for subscribed logs after recovering
    *hash<string, bool> processRecovered() {
        # create core client object
        processRunning();

        # check log subscriptions
        hash<auto> h = {
            "logs": QorusMaster::MasterLogs,
        };
        try {
            *list<string> msgs = core.sendCheckResponseUnreliable(CPC_CORE_GET_SUBSCRIPTIONS, h, CPC_OK, 10s);
            return msgs[0].val() ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "PROCESS-START-ERROR" && ex.err != "CLIENT-DEAD" && ex.err != "CLIENT-TERMINATED"
                && ex.err != "QUEUE-TIMEOUT") {
                rethrow;
            }
            QDBG_LOG("%s", get_exception_string(ex));
            logError("failed to retrieve log subscriptions from qorus-core: %s: %s", ex.err, ex.desc);
        }
    }

    #! Waits for the process to terminate
    /** @return True if the process terminated, False if not (idependent)
    */
    bool wait() {
        if (Qorus.isIndependent()) {
            logInfo("%y: process is independent", id);
            return False;
        }
        return AbstractQorusInternProcess::wait();
    }

    private sendStopMessage(timeout to = 10s) {
        try {
            QDBG_LOG("%y: sending STOP to %y", id, child_urls);
            AbstractQorusClient client = getClient();
            client.sendCheckResponseUnreliable(CPC_STOP, Qorus.isIndependent() ? {"wait": True} : NOTHING, CPC_ACK,
                to);
        } catch (hash<ExceptionInfo> ex) {
            logInfo("%y: error in stop message: %s: %s; assuming process dead", id, ex.err, ex.desc);
        }
    }

    private stopImpl() {
        if (Qorus.isIndependent()) {
            # send stop msg with no timeout
            sendStopMessage(-1);
        } else {
            AbstractQorusInternProcess::stopImpl();
        }
    }

    # called when the remote process starts; creates the dealer socket to the client
    synchronized processRunning() {
        if (!core) {
            # get the URLs for the qorus-core process and register it as a server
            cast<QorusMaster>(parent).registerServer(QDP_NAME_QORUS_CORE, getClusterProcInfo());
            # create the qorus-core client object
            core = new AbstractQorusClient(parent, QDP_NAME_QORUS_CORE);
        }
    }

    private Process startImpl() {
        # the first seven args must be api_level, master_urls, interfaces, network_key_path, id, client_id, log path, and restarted
        list<auto> args = getCommonStartArgs() + (
            cast<QorusMaster>(parent).getPubUrl(),
            sessionid,
            getIdList(running_wfid_list),
            getIdList(running_svcid_list),
            getIdList(running_jobid_list),
            getIdList(qdsp_recovery_list),
        );
        if (cl_opts) {
            args += cl_opts;
        }

        logInfo("starting %s %y with args: %y", name, id, args);
        hash<auto> env = ENV + {
            "QORUS_LOGPATH": Qorus.options.get("logdir") + DirSep,
            "QORUS_INSTANCE": Qorus.options.get("instance-key"),
        };
        # get all system loggers to seed the metadata map in qorus-core before the OMQ dsp is initialized
        *hash<auto> logger_map = Qorus.getLoggerMap();
        if (logger_map) {
            env{"SYSTEM_" + ENV_LOGGER_PARAMS} = make_yaml(logger_map);
        }
        # get the logger ID for the system omq datasource; if any
        *int omq_loggerid = Qorus.getOmqLoggerId();
        if (omq_loggerid) {
            env.OMQ_LOGGERID = omq_loggerid;
        }
        # make sure the loggermap gets selected again in case qorus-core dies
        Qorus.clearLoggerMap();

        /*
        # XXX DEBUG START: RUN IN DEBUGGER
        string envstr = foldl $1 + " " + $2,
            map sprintf("%s='%s'", $1.key, trim($1.value)),
                env.pairIterator(),
                $1.key == "QORUS_LOGPATH" || $1.key == "QORUS_INSTANCE" || $1.key == "SYSTEM_LOGGER_PARAMS";
        if (PlatformOS == "Darwin") {
            logInfo("START %s lldb -- qorus-core %s", envstr, (foldl $1 + " " + $2, args));
        } else {
            logInfo("START %s gdb --args qorus-core %s", envstr, (foldl $1 + " " + $2, args));
        }

        *softint pid;
        do {
            usleep(500ms);
            # NOTE: the x? in the regex below is to allow this section to be commented out
            pid = `ps ax | grep qorus-core | grep -v -e grep -e lldb -e gdb -e tail -e less|sed -E 's/^ *x?//'| cut -f1 -d\ `;
        } while (!pid);

        child = False;
        logInfo("got PID %d; sleeping 10s", pid);
        sleep(10s);
        return new Process(pid);
        */
        # XXX DEBUG END: RUN IN DEBUGGER

        return new Process(name, args, {"env": env});
    }

    bool processMsgImpl(MyRouter router, string sender, string mboxid, string cmd, ZMsg msg) {
        QDBG_LOG("processing API from qorus-core: %y", cmd);
        switch (cmd) {
            case CPC_STOP: {
                cast<QorusMaster>(parent).stopFromQorusCore(router, sender, mboxid);
                return True;
            }

            case CPC_MR_UPDATE_LOGGER: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                    "name": Qorus.getNetworkId(),
                    "instance": Qorus.options.get("instance-key"),
                    "path": Qorus.options.get("logdir") + DirSep,
                };
                h.params = substituteLogFilename(h.params, subs);
                background cast<QorusMaster>(parent).updateLogger(router.index, sender, mboxid, h.params);
                return True;
            }

            case CPC_MR_UPDATE_PROMETHEUS_LOGGER: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                background cast<QorusMaster>(parent).updatePrometheusLogger(router.index, sender, mboxid, h.params);
                return True;
            }

            case CPC_MR_UPDATE_GRAFANA_LOGGER: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                background cast<QorusMaster>(parent).updateGrafanaLogger(router.index, sender, mboxid, h.params);
                return True;
            }

            case CPC_MR_ROTATE_LOGGER: {
                background cast<QorusMaster>(parent).rotateLogger(router.index, sender, mboxid);
                return True;
            }

            case CPC_MR_ROTATE_QDSP_LOGGER: {
                background cast<QorusMaster>(parent).rotateQdspLogger(router.index, sender, mboxid);
                return True;
            }

            case CPC_MR_START_DSP: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: start qdsp %s: %s%s", sender, mboxid, h.name, h.connstr, h.args ? " args: " + h.args : "");
                background cast<QorusMaster>(parent).startDatasourcePoolProcess(router.index, sender, mboxid, h);
                return True;
            }

            case CPC_MR_START_WF: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: start qwf %s: %y", sender, mboxid, h.name, , h{"wfname", "wfversion", "sessionid"});
                background cast<QorusMaster>(parent).startWorkflowProcess(router.index, sender, mboxid, h);
                return True;
            }

            case CPC_MR_START_SVC: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: start qsvc %s: %y", sender, mboxid, h.name, , h{"svctype", "svcname", "svcversion"});
                background cast<QorusMaster>(parent).startServiceProcess(router.index, sender, mboxid, h);
                return True;
            }

            case CPC_MR_START_JOB: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: start qjob %s: %y", sender, mboxid, h.name, h{"jobname", "jobversion", "sessionid"});
                background cast<QorusMaster>(parent).startJobProcess(router.index, sender, mboxid, h);
                return True;
            }

            case CPC_MR_STOP_PROCESS: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: stop process %s", sender, mboxid, h.name);
                background cast<QorusMaster>(parent).stopProcessExtern(router.index, sender, mboxid, h);
                return True;
            }

            case CPC_MR_DETACH_PROCESS: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: detach process %s", sender, mboxid, h.name);
                background cast<QorusMaster>(parent).detachProcessExtern(router.index, sender, mboxid, h);
                return True;
            }

            case CPC_MR_DETACH_KILL_PROCESS: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: detach and kill process %s", sender, mboxid, h.name);
                background cast<QorusMaster>(parent).detachKillProcessExtern(router.index, sender, mboxid, h);
                return True;
            }

            case CPC_MR_RUN_INDEPENDENT: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: setting process independence for %s", sender, mboxid, h.name);
                background cast<QorusMaster>(parent).setProcessIndependence(router.index, sender, mboxid, h);
                return True;
            }

            case CPC_MR_UPDATE_PROCESS_INFO: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                logInfo("%s TID %d: updating info for process %s", sender, mboxid, h.name);
                background cast<QorusMaster>(parent).updateProcessInfo(router.index, sender, mboxid, h);
                return True;
            }

            case CPC_MR_STARTUP_MSG: {
                string str = msg.popStr();
                cast<QorusMaster>(parent).startupMessageCore(str);
                router.send(sender, mboxid, CPC_ACK);
                return True;
            }

            case CPC_MR_STARTUP_COMPLETE: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                cast<QorusMaster>(parent).startupComplete(h);
                router.send(sender, mboxid, CPC_ACK);
                return True;
            }

            case CPC_MR_SHUTDOWN_MSG: {
                string str = msg.popStr();
                cast<QorusMaster>(parent).shutdownMessageCore(str);
                router.send(sender, mboxid, CPC_ACK);
                return True;
            }

            case CPC_MR_SHUTDOWN_COMPLETE: {
                hash<auto> h = qorus_cluster_deserialize(msg);
                cast<QorusMaster>(parent).shutdownCompleteCore(h);
                router.send(sender, mboxid, CPC_ACK);
                return True;
            }

            case CPC_MR_BCAST_IFS: {
                data msgdata = msg.popStr();
                string except = msg.popStr();
                #QDBG_LOG("bcast: %s", str);
                background cast<QorusMaster>(parent).broadcastToAllInterfaces(msgdata, except);
                router.send(sender, mboxid, CPC_ACK);
                return True;
            }

            case CPC_MR_BCAST_CONFIRM_IFS: {
                data msgdata = msg.popStr();
                string except = msg.popStr();
                #QDBG_LOG("bcast: %s", str);
                background cast<QorusMaster>(parent).broadcastToAllInterfacesConfirm(router.index, sender, mboxid, msgdata, except);
                return True;
            }

            case CPC_MR_BCAST_IFS_DIRECT: {
                data msgdata = msg.popStr();
                string except = msg.popStr();
                #QDBG_LOG("bcast: %s", str);
                background cast<QorusMaster>(parent).broadcastToAllInterfacesDirect(msgdata, except);
                router.send(sender, mboxid, CPC_ACK);
                return True;
            }

            case CPC_CORE_LOG_SUBSCRIBE: {
                hash<auto> log_msg = qorus_cluster_deserialize(msg);
                QDBG_LOG("log subscribe: %y", log_msg);
                Qorus.subscribeToLog(log_msg.log);
                router.send(sender, mboxid, CPC_OK);
                QDBG_LOG("log subscribe DONE");
                return True;
            }

            case CPC_CORE_LOG_UNSUBSCRIBE: {
                hash<auto> log_msg = qorus_cluster_deserialize(msg);
                QDBG_LOG("log unsubscribe: %y", log_msg);
                Qorus.unsubscribeFromLog(log_msg.log);
                router.send(sender, mboxid, CPC_OK);
                QDBG_LOG("log unsubscribe DONE");
                return True;
            }

            case CPC_MR_REGISTER_QORUS_CORE: {
                Qorus.handleQorusCoreRegistration(msg, router.index, sender, mboxid);
                return True;
            }
        }

        return False;
    }

    # returns information needed to restart the process if it terminates unexpectedly (or is killed)
    *hash<auto> getProcessInfo() {
        return {
            "sessionid": sessionid,
            "running_wfid_list": running_wfid_list,
            "running_svcid_list": running_svcid_list,
            "running_jobid_list": running_jobid_list,
        };
    }

    #! qorus-core processes abort notification messages for services
    bool needsSendNotifyAbortedProcessInitial() {
        return True;
    }

    #! qorus-core process restart notification messages for all processes
    bool needsSendNotifyRestartProcess() {
        return True;
    }

    static string getIdList(*list<auto> l) {
        return (foldl $1 + "," + $2, (map $1.toString(), l)) ?? "-";
    }

    #! returns all constructor arguments after "host"
    private list<auto> getConstructorArgsImpl() {
        return (
            restarted,
            sessionid,
            running_wfid_list,
            running_svcid_list,
            running_jobid_list,
            qdsp_recovery_list,
            cl_opts,
        );
    }

    #! create the client object
    private AbstractQorusClient getClientImpl() {
        return new AbstractQorusClient(parent, QDP_NAME_QORUS_CORE);
    }
}
