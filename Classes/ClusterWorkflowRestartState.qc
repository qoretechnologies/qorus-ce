# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus ClusterWorkflowRestartState class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args

class OMQ::ClusterWorkflowRestartState {
    public {}

    private {
        # list of cluster workflow IDs to reset
        list<int> rcsl;

%ifdef QorusDebugInternals
        # keep workflows to reset in a hash
        hash<string, bool> dbg_reset_wfid_hash;
%endif

        # maps workflows IDs to lists of execution instance modes
        hash<string, list<string>> mhl;

        # ensure atomic locking of reset actions from stop to restart
        AtomicMultiClassActionHelper atomic_action;

        #! workflow IDs locked
        list<string> wfid_list;
    }

    doBackground(code call) {
        if (atomic_action && wfid_list) {
            atomic_action.doBackgroundWorkflowsArgs(wfid_list, call, argv);
        } else {
            background call_function_args(call, argv);
        }
    }

    # this static method returns a closure to be executed when the qwf process has been stopped
    /** this will restart workflow instances and signal that the WorkflowStopResetData reset process is complete

        issue #2647: this must be a static method so the object does not get captured in the closure,
        so the object can go out of scope while the closure is still valid
    */
    static code getAction(*hash<auto> cx, Counter c, softstring wfid, *list<string> ml) {
        return sub () {
            QDBG_LOG("ClusterWorkflowRestartState::restartWorkflows() action start: cnt: %y %d ml: %y", c, c.getCount(), ml);
            # first signal cluster reset complete for the given workflow
            Qorus.control.clusterResetComplete(wfid);
            QDBG_LOG("ClusterWorkflowRestartState::restartWorkflows() action complete: cnt: %y %d ml: %y", c, c.getCount(), ml);
        };
    }

    lock(softlist<softstring> wfid_list) {
        # issue #1514 (https://bugs.qoretechnologies.com/issues/1514)
        # do not allow a workflow reset whle the system is shutting down
        if (Qorus.shutting_down) {
            throw "SHUTDOWN-IN-PROGRESS", "cannot reset workflows because the system is shutting down";
        }

        atomic_action = new AtomicMultiClassActionHelper(wfid_list);
        self.wfid_list = wfid_list;
    }

    restartWorkflows(*hash<auto> cx) {
        # the reset is complete, so the segment workflow data objects should go out of scope,
        # which will cause the qwf processes to stop
        # wait for qwf processes to stop
        Counter c();

        map SM.waitWorkflowProcessStopped($1, getAction(cx, c, $1, mhl{$1}), c), rcsl;

        # temporarily release any workflow references for workflows with autostart > 0
        ensure_create_tld();
        map Qorus.control.resetRemote($1), rcsl;

        QDBG_LOG("ClusterWorkflowRestartState::restartWorkflows() waiting for: cnt: %y %d mhl: %y", c, c.getCount(), mhl);
        # wait until all actions have been executed
        c.waitForZero();

        # then restart workflow instances; do not use Control::startWorkflowSetAtomic() here, as we are already
        # holding the atomic lock for this workflow
        foreach int wfid in (rcsl) {
            map Qorus.control.startWorkflowAtomic(cx, wfid, $1), mhl{wfid};
        }
    }

    bool empty() {
        return rcsl.empty();
    }

    add(int wfid, WorkflowStopResetData rd) {
%ifdef QorusDebugInternals
        QDBG_ASSERT(!dbg_reset_wfid_hash{wfid});
        dbg_reset_wfid_hash{wfid} = True;
%endif

        rcsl += wfid;
        rd.inc();
    }

    add(softstring wfid, string mode) {
        QDBG_ASSERT(dbg_reset_wfid_hash{wfid});
        QDBG_ASSERT(rcsl);
        mhl{wfid} += mode;
    }
}