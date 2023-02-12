# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

public namespace OMQ;

%new-style
%strict-args
%require-types

class OMQ::QorusCoreSubsystemClientBase {
    public {
    }

    private {
        AbstractQorusClient core;
        string subsystem;
    }

    constructor(AbstractQorusClient core, string subsystem) {
        self.core = core;
        self.subsystem = subsystem;
    }

    auto doCallWithSerializedResponse(string method, *softlist<auto> args, *hash<auto> tld) {
        hash<auto> h = {
            "subsystem": subsystem,
            "method": method,
            "args": args,
            "tld": tld,
            "already_serialized": True,
        };
        *list<string> msgs = core.sendCheckResponse(CPC_CORE_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs ? Qorus.deserialize(msgs[0]) : NOTHING;
    }

    auto methodGate(string method) {
        return methodGateArgs(method, argv);
    }

    auto methodGateArgs(string method, *softlist<auto> args, *hash<auto> tld) {
        hash<auto> h = {
            "subsystem": subsystem,
            "method": method,
            "args": args,
            "tld": tld,
        };
        *list<string> msgs = core.sendCheckResponse(CPC_CORE_CALL_SUBSYSTEM, h, CPC_OK);
        return msgs ? qorus_cluster_deserialize(msgs[0]) : NOTHING;
    }
}
