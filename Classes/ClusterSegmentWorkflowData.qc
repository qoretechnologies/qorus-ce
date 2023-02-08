# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus ClusterSegmentWorkflowData class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

# holds cache information per workflowid for locally-managed workflows in a cluster process
class OMQ::ClusterSegmentWorkflowData inherits LocalSegmentWorkflowData {
    constructor(Workflow wf) : LocalSegmentWorkflowData(wf) {
        # create the local workflow queue
        WC = new ClusterWorkflowQueue(wf);
    }

    # handles blocked or canceled workflow order statuses from an external call
    hash<auto> handleWorkflowInstanceStatusExtern(hash<auto> cx, softstring wfiid, string stat, bool setOn,
        *hash<auto> tempdata, *hash<auto> new_keys, string err, hash<auto> wih) {
        hash<auto> rv = handleWorkflowInstanceStatus(cx, wfiid, stat, setOn, tempdata, new_keys, err, wih);
        return {
            "val": rv,
            "tld": tld.("attachIsBlocked",),
        };
    }

    synchronized stopAndDeleteWorkflowQueue() {
%ifdef QorusDebugInternals
        # issue #2647: if a signal file exists, then terminate the process here
        {
            string filename = sprintf("%s/%s-%s-%s-%s-stopAndDeleteWorkflowQueue", tmp_location(),
                Qorus.options.get("instance-key"), wf.name, wf.version, wf.workflowid);
            if (is_file(filename)) {
                QDBG_LOG("ClusterSegmentWorkflowData::stopAndDeleteWorkflowQueue() SIGNAL FILE %y found; unlinking", filename);
                unlink(filename);
                QDBG_LOG("ClusterSegmentWorkflowData::stopAndDeleteWorkflowQueue() TERMINATING");
                exit(1);
            }
        }
%endif
        QDBG_LOG("stopAndDeleteWorkflowQueue() WC: %y", exists WC);
        if (WC) {
            WC.stop();
            delete WC;
        }
    }

    logArgs(int lvl, string fmt) {
        Qorus.logArgs(lvl, fmt, argv);
    }

    logFatal(string fmt) {
        Qorus.logArgs(LoggerLevel::FATAL, fmt, argv);
    }

    logError(string fmt) {
        Qorus.logArgs(LoggerLevel::ERROR, fmt, argv);
    }

    logWarn(string fmt) {
        Qorus.logArgs(LoggerLevel::WARN, fmt, argv);
    }

    logInfo(string fmt) {
        Qorus.logArgs(LoggerLevel::INFO, fmt, argv);
    }

    logDebug(string fmt) {
        Qorus.logArgs(LoggerLevel::DEBUG, fmt, argv);
    }

    logTrace(string fmt) {
        Qorus.logArgs(LoggerLevel::TRACE, fmt, argv);
    }
}
