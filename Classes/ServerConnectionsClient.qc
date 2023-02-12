# -*- mode: qore; indent-tabs-mode: nil -*-
# @file ServerConnectionsClient.qc provides an API for remote Qorus connections

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

hashdecl ConnectionConstructorConfig {
    hash cci;
    Program p;
}

class OMQ::ServerConnectionsClient inherits QorusCoreSubsystemClientBase {
    private {
        # lock for atomic operations of the connection hash
        Mutex m();

        # maps from connection name to connection configuration
        hash<string, hash> ch();
    }

    constructor(AbstractQorusClient core, string name) : QorusCoreSubsystemClientBase(core, name) {
    }

    AbstractConnection getConnection(string name) {
        return methodGate("getConnection", name);
    }

    hash<auto> getTags(string name) {
        return methodGate("getTags", name);
    }

    object get(string name, bool connect = True, bool register_dependency = True, *hash<auto> rtopts) {
        # must send TLD here so that dependencies are established
        AbstractConnection c = methodGateArgs("getConnectionRemote", (name, register_dependency), Qorus.getTldContext());
        # add runtime logging closure options if supported by the class and not given in the call
        *hash<auto> rh = c.getRuntimeOptions();
        if (rh.log && !rtopts.log)
            rtopts.log = sub (string fmt) { Qorus.logInfo(fmt, argv); };
        if (rh.errlog && !rtopts.errlog)
            rtopts.errlog = sub (string fmt) { Qorus.logInfo(fmt, argv); };
        if (rh.dbglog && !rtopts.dbglog)
            rtopts.dbglog = sub (string fmt) { Qorus.logDebug(fmt, argv); };

        return c.get(connect, rtopts);
    }

    hash<auto> getInfo(string conn, *hash<auto> opts) {
        return methodGate("getInfo", conn, opts);
    }

    hash<auto> getInfo(*hash<auto> opts) {
        return methodGate("getInfo", opts);
    }

    setRuntimeLogging(reference rtopts, *hash<auto> rh) {
    }

    bool ignoreSocketWarnings(string name) {
        return methodGate("ignoreSocketWarnings", name);
    }

    *list<auto> list(bool monitored_only = False, bool remote_only = False) {
        return methodGate("list", monitored_only, remote_only);
    }
}