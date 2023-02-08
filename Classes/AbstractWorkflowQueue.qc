# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus AbstractWorkflowQueueBase class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

class OMQ::AbstractWorkflowQueue {
    abstract start();
    abstract stop();
    abstract *string getCacheSummary();
    # called when the retry option changes
    abstract requeueAllRetries();
    abstract postSyncEvent(softstring stepid, softint wfiid, softint ind, softint prio, *hash parent_info);

    abstract updateQueue(softstring stepid, softint wfiid, softint ind, softint prio, softbool corrected, string queuekey, auto data, *hash parent_info);

    abstract updateSubWorkflowQueue(softstring wfiid, softint stepid, softint ind, softint prio, softint swfiid, *hash parent_info, string stat);

    # adds an entry to the workflow instance queue
    abstract addToWorkflowInstanceQueue(softint wfiid, int priority, *hash parent_info, *date scheduled);

    abstract *string getCacheAsString();

    abstract updateRetryDelay(*softint r);

    abstract updateAsyncDelay(*softint a);
}