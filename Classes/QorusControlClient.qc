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

class QorusControlClient inherits QorusCoreSubsystemClientBase {
    constructor(AbstractQorusClient core) : QorusCoreSubsystemClientBase(core, "control") {
    }

    auto methodGate(string method) {
        return methodGateArgs(method, argv, Qorus.getTldContext());
    }
}