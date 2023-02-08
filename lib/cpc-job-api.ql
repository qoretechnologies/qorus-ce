# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

# DEALER INTERFACE -> QJOB (data): "QJOB-CALL-SUBSYSTEM": call qjob subsystem
/** Payload:
        string subsystem
        string method
        *softlist<auto> args

    response:
        ROUTER QJOB -> INTERFACE (data): "OK" (CPC_OK)
            Payload:
                auto
*/
const CPC_QJOB_CALL_SUBSYSTEM = "QJOB-CALL-SUBSYSTEM";

#! returns the unique process name for the job without the process prefix
string sub qjob_get_process_id(string name, string version, softstring id) {
    return qorus_cluster_get_process_name(name) + "-v" + qorus_cluster_get_process_name(version) + "-" + id;
}

#! returns the unique process name for the qorus job proceses
string sub qjob_get_process_name(string name, string version, softstring id) {
    return QDP_NAME_QJOB + "-" + qjob_get_process_id(name, version, id);
}
