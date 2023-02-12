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

%include cpc-core-api.ql

public namespace OMQ;

class OMQ::QorusDistributedDebugProgramControl inherits public DebugProgramControl::DebugProgramControl {
    private {
        AbstractQorusDistributedProcessWithDebugProgramControl qdp;
    }

    constructor(string server_name, AbstractQorusDistributedProcessWithDebugProgramControl n_qdp) : DebugProgramControl::DebugProgramControl(server_name) {
        qdp = n_qdp;
        logger = new QorusDebugLogger();
    }

    public setDebug(bool dbg) {
        logger.verbose = dbg ? DebugUtil::DUV_DEBUG : DebugUtil::DUV_INFO;
    }

    public sendDataImpl(hash cx, auto data) {
        qdp.sendData(cx, data);
    }

    #! sends data to all connections
    public broadcastDataImpl(auto data) {
        qdp.broadcastData(data);
    }
}

/*
    Class implements debug server for distributed program debugging via ZMQ socket from qorus-qore.
    Qorus-qore is intended as proxy to messages comming from HTTP debug handler. So qorus-qore is
    debug client for this class. Mutually only one client is supported (i.e. one HTTP handler as well.

    In theory we might implement e.g. a ZMQ command line debug client to connect cluster process directly.
    In this case we need support more clients and send responses properly.
 */
class OMQ::AbstractQorusDistributedProcessWithDebugProgramControl inherits public AbstractQorusDistributedProcess {
    private {
        QorusDistributedDebugProgramControl debugProgram;   # BUG: does not find DebugProgramControl::* methods
        #DebugProgramControl debugProgram;
    }

    public {
        # connection to qorus-core
        AbstractQorusClient core;
    }

    constructor(reference<list<string>> p_argv, hash getopt_opts = Opts): AbstractQorusDistributedProcess(\p_argv, getopt_opts) {
    }

    private QorusDistributedDebugProgramControl createDebugProgramControl() {
        return new QorusDistributedDebugProgramControl(name, self);
    }

    private waitForQorusCore() {
        debugProgram = createDebugProgramControl();
        debugProgram.setDebug(getDebugSystem());

        while (True) {
            try {
                initQorusCore();
                return;
            } catch (hash<ExceptionInfo> ex) {
                #QDBG_LOG("failed to initialize qorus-core client: %s", get_exception_string(ex));
                if (ex.err == "PROCESS-ERROR") {
                    logInfo("qorus-core is starting; waiting for a URL to be available...");
                    sleep(5);
                    continue;
                } else if (ex.err == "UNKNOWN-PROCESS-ERROR") {
                    break;
                } else {
                    rethrow;
                }
            }
        }

        # here we need to wait until the qorus-core process exists
        logInfo("qorus-core process is not running yet; waiting for it to start...");
        waitForClient(QDP_NAME_QORUS_CORE);
    }

    private initQorusCore() {
        # get the URLs for the qorus-core process and register it as a server
        registerServer(QDP_NAME_QORUS_CORE);
        # create the qorus-core client object
        createCoreClient();
    }

    private createCoreClient() {
        proc_lck.lock();
        on_exit proc_lck.unlock();

        if (!core) {
            core = new AbstractQorusClient(self, QDP_NAME_QORUS_CORE);
            notifyClientIntern(QDP_NAME_QORUS_CORE);
        }
    }

    private:internal doDebugCommand(int index, string sender, string mboxid, string cmd, hash cx, hash<auto> h) {
        *hash sd;
        try {
            sd = debugProgram.processCommand(cx, h.args);
            if (exists sd)
                sendData(cx, sd);
        } catch (hash<ExceptionInfo> ex) {
            #log(DUV_DEBUG, "exception: %y", ex);
            sd.type = 'error';
            sd.result.err = ex.err;
            sd.result.desc = ex.desc;
            sd.result.ex = ex;
            sendData(cx, sd);
        }
        sendResponse(index, sender, mboxid, CPC_OK);
    }

    private bool processCmdImpl(ZSocketRouter sock, int index, string sender, string mboxid, string cmd, ZMsg msg) {
        # TODO? test if message is originated from qore-core ?
        switch (cmd) {
            case CPC_CORE_DEBUG_COMMAND:
                hash<auto> h = qorus_cluster_deserialize(msg);
                hash cx = {
                    "id": h.cid,
                };
                switch (h.method) {
                    case "subscribe":
                        debugProgram.registerConnection(cx);
                        debugProgram.connectionRegistered(cx);
                        sendResponse(index, sender, mboxid, CPC_OK);
                        return True;

                    case "unsubscribe":
                        debugProgram.unregisterConnection(cx);
                        sendResponse(index, sender, mboxid, CPC_OK);
                        return True;

                    case "command":
                        # we need filter commands which get data from database (source code) not to block receiving thread for omq-dsp
                        # only commands being resolved in calling thread are exception, i.e. program/*/label/source which has label field
                        if (exists h.args.label) {
                            background doDebugCommand(index, sender, mboxid, cmd, cx, h);
                        } else {
                            doDebugCommand(index, sender, mboxid, cmd, cx, h);
                        }
                        return True;
                }
        }
        return False;
    }

    public sendData(hash cx, auto data) {
        core.sendCmdOneWay(CPC_CORE_DEBUG_EVENT, {"method": "send", "cid": cx.id, "args": data});
    }

    #! sends data to all connections
    public broadcastData(auto data) {
        core.sendCmdOneWay(CPC_CORE_DEBUG_EVENT, {"method": "broadcast", "args": data});
    }

    private processAbortedImpl(string process, *hash<ClusterProcInfo> info, bool restarted, date abort_timestamp) {
        # may be called after a restart; "debugProgram" may not exist
        if (process == QDP_NAME_QORUS_CORE && debugProgram) {
            debugProgram.unregisterAllConnections();
        }

        if (restarted) {
            if (!core && process == QDP_NAME_QORUS_CORE) {
                createCoreClient();
            }
        }
    }

    auto deserialize(data d) {
        return Serializable::deserialize(d);
    }
}
