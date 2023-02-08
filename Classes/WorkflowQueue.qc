# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus WorkflowQueue class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

class OMQ::WorkflowQueue inherits WorkflowQueueBase {
    constructor(Workflow wf) : WorkflowQueueBase(wf) {
    }
}
