# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

public namespace OMQ;

%new-style
%strict-args
%require-types

class OMQ::QorusLogWebSocketHandlerClient inherits OMQ::QorusCoreSubsystemClientBase {
    constructor(AbstractQorusClient core) : QorusCoreSubsystemClientBase(core, "eventLog") {
    }

    workflowLogEvent() {
        methodGateArgs("workflowLogEvent", argv);
    }

    serviceLogEvent() {
        methodGateArgs("serviceLogEvent", argv);
    }

    jobLogEvent() {
        methodGateArgs("jobLogEvent", argv);
    }

    qdspLogEvent() {
        methodGateArgs("qdspLogEvent", argv);
    }

    auto methodGate(string method) {
        return methodGateArgs(method, argv);
    }
}
