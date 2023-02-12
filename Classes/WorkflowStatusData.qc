# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus WorkflowStatusData class hierarchy

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

public namespace OMQ;

const WSD_START = 0;
const WSD_STOP = 1;
const WSD_RESET = 2;

# empty base class for workflow status change info
class WorkflowStatusData {
%ifdef QorusDebugInternals
    public {
        int tid;
        *list stack;
    }
%endif

    abstract bool waitForStatus(bool w, int wfid, *int wait);
}

class AbstractWorkflowStopResetData inherits WorkflowStatusData {
    abstract bool beginReset();
}

class WorkflowStartData inherits WorkflowStatusData {
    public {
        # counter that signals the end of a start action
        Counter cStart(1);
    }

%ifdef QorusDebugInternals
    constructor() {
        tid = gettid();
        stack = get_stack();
    }
%endif

    bool waitForStatus(bool w, int wfid, *int wait) {
        if (wait & WWC_RetStart)
            return True;
        olog(LoggerLevel::INFO, "waiting for a start action for workflowid %d to complete before continuing", wfid);
        Qorus.control.waitStatusLocked(cStart, w);
        return False;
    }
}

class WorkflowStopData inherits WorkflowStatusData {
    public {
        # counter that signals the end of a workflow execution instance shutdown
        Counter cStop(1);
    }

%ifdef QorusDebugInternals
    constructor() {
        tid = gettid();
        stack = get_stack();
    }
%endif

    bool waitForStatus(bool w, int wfid, *int wait) {
        if (wait & WWC_RetStop)
            return True;
        olog(LoggerLevel::INFO, "waiting for shutdown of all instances of workflowid %d to complete before continuing", wfid);
        Qorus.control.waitStatusLocked(cStop, w);
        return False;
    }

    bool stopped() {
        cStop.dec();
        return True;
    }
}

# this class stops a workflow execution instance as a part of a cluster workflow reset
class WorkflowStopResetData inherits AbstractWorkflowStopResetData, WorkflowStopData {
    public {
        # counter that signals when the reset is done
        Counter cReset();
    }

    bool beginReset() {
        return cReset.getCount() ? True : False;
    }

    inc() {
        QDBG_ASSERT(!cReset.getCount());
        cReset.inc();
%ifdef QorusDebugInternals
        tid = gettid();
        stack = get_stack();
%endif
    }

    bool waitForStatus(bool w, int wfid, *int wait) {
        if (wait & WWC_RetReset) {
            return True;
        }
        olog(LoggerLevel::INFO, "waiting for reset of cluster workflowid %d to complete before continuing", wfid);
        QDBG_LOG("w: %y wfid: %y wait: %y cReset: %y self: %y", w, wfid, wait, cReset.getCount(), self);
        Qorus.control.waitStatusLocked(cReset, w);
        return False;
    }

    bool stopped() {
        cStop.dec();
        return False;
    }
}

class WorkflowResetData inherits AbstractWorkflowStopResetData {
    public {
        Workflow wf;

        # counter that signals the end of a reset
        Counter cEnd(1);
        # counter that signals that a reset can start
        Counter cStartReset(1);

        int count = 0;
        int total = 0;
    }

    constructor(Workflow wf) {
        self.wf = wf;
%ifdef QorusDebugInternals
        tid = gettid();
        stack = get_stack();
%endif
    }

    # returns True if the reset process can begin, False if there is nothing to reset
    bool beginReset() {
        if (total) {
            cStartReset.dec();
            return True;
        }

        # return True if there is a remote workflow process to reset, False if not
        return wf.remote;
    }

    bool waitForStatus(bool w, int wfid, *int wait) {
        if (wait & WWC_RetReset)
            return True;
        olog(LoggerLevel::INFO, "waiting for reset of workflowid %d to complete before continuing", wfid);
        Qorus.control.waitStatusLocked(cEnd, w);
        return False;
    }

    stopping() {
        ++count;
        ++total;
    }
}
