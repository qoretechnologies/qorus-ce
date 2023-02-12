# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus ClusterWorkflowQueue class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

/** NOTE: the workflow queue is started automatically in remote qwf processes,
    and once stopped are not started again in the same process
*/
class OMQ::ClusterWorkflowQueue inherits WorkflowQueueBase {
    constructor(Workflow wf) : WorkflowQueueBase(wf) {
        QDBG_LOG("ClusterWorkflowQueue::constructor() starting");
        # issue #2647: start the remote workflow queue automatically in qwf processes
        start();
    }
}
