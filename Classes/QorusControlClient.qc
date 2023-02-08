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

class QorusControlClient inherits QorusCoreSubsystemClientBase {
    constructor(AbstractQorusClient core) : QorusCoreSubsystemClientBase(core, "control") {
    }

    auto methodGate(string method) {
        return methodGateArgs(method, argv, Qorus.getTldContext());
    }
}