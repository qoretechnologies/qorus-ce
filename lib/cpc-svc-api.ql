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

# DEALER INTERFACE -> QSVC (data): "QSVC-CALL-SUBSYSTEM": call qsvc subsystem
/** Payload:
        string subsystem
        string method
        *softlist<auto> args

    response:
        ROUTER QSVC -> INTERFACE (data): "OK" (CPC_OK)
            Payload:
                auto
*/
const CPC_QSVC_CALL_SUBSYSTEM = "QSVC-CALL-SUBSYSTEM";

#! Label for stateful services
const SL_STATEFUL = "stateful";

#! returns the unique process name for the service without the process prefix
string sub qsvc_get_process_id(string type, string name, string version, softstring id, string state_label = SL_STATEFUL) {
    return qorus_cluster_get_process_name(type) + "-" + qorus_cluster_get_process_name(name) + "-v" +
        qorus_cluster_get_process_name(version) + "-" + id + "-" + state_label;
}

#! returns the unique process name for the qorus service proceses
string sub qsvc_get_process_name(string type, string name, string version, softstring id,
        string state_label = SL_STATEFUL) {
    return QDP_NAME_QSVC + "-" + qsvc_get_process_id(type, name, version, id, state_label);
}
