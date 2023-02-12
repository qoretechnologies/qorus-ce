# -*- mode: qore; indent-tabs-mode: nil -*-
# @file QorusUserConnectionsClient.qc provides an API for remote Qorus connections

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

class OMQ::QorusUserConnectionsClient inherits ServerConnectionsClient {
    constructor(AbstractQorusClient core) : ServerConnectionsClient(core, "connections") {
    }

    AbstractDataProvider getDataProvider(string name, *int mapperid) {
        on_success if (mapperid) methodGateArgs("doMapperDependency", (name, mapperid));
        return getConnection(name).getDataProvider();
    }

    setRuntimeLogging(reference rtopts, *hash rh) {
        # add runtime logging closure options if supported by the class and not given in the call
        if (rh.log && !rtopts.log)
            rtopts.log = sub (string fmt) { Qorus.logArgs(LoggerLevel::INFO, fmt, argv); };
        if (rh.errlog && !rtopts.errlog)
            rtopts.errlog = sub (string fmt) { Qorus.logArgs(LoggerLevel::ERROR, fmt, argv); };
        if (rh.dbglog && !rtopts.dbglog)
            rtopts.dbglog = sub (string fmt) { Qorus.logArgs(LoggerLevel::DEBUG, fmt, argv); };
    }
}