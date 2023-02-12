# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

# DEALER INTERFACE -> QWF (data): "QWF-CALL-SUBSYSTEM": call qwf subsystem
/** Payload:
        string subsystem
        string method
        *softlist<auto> args

    response:
        ROUTER QWF -> INTERFACE (data): "OK" (CPC_OK)
            Payload:
                auto
*/
const CPC_QWF_CALL_SUBSYSTEM = "QWF-CALL-SUBSYSTEM";

#! returns the unique process name for the workflow without the process prefix
string sub qwf_get_process_id(string name, string version, softstring id) {
    return qorus_cluster_get_process_name(name) + "-v" + qorus_cluster_get_process_name(version) + "-" + id;
}

#! returns the unique process name for the qorus workflow proceses
string sub qwf_get_process_name(string name, string version, softstring id) {
    return QDP_NAME_QWF + "-" + qwf_get_process_id(name, version, id);
}
