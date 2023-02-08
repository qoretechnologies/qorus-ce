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

# DEALER QDSP -> CORE (data): "CORE-DSP-TIMEOUT-WARNING": datasource pool timeout warning
/** Payload:
        string desc
        int time
        int to
        string dsn

    response:
        no response: one-way command
*/
const CPC_CORE_DSP_TIMEOUT_WARNING = "CORE-DSP-TIMEOUT-WARNING";

# DEALER QDSP -> CORE (data): "CORE-DSP-EVENT": datasource pool event notification
/** Payload:
        string user
        string db
        int eventtype
        auto arg;
        + other event-specific keys

    response:
        no response: one-way command
*/
const CPC_CORE_DSP_EVENT = "CORE-DSP-EVENT";

# DEALER INTERFACE -> CORE (data): "CORE-CALL-SUBSYSTEM": call core subsystem
/** Payload:
        string subsystem
        string method
        *softlist<auto> args

    response:
        ROUTER CORE -> INTERFACE (data): "OK" (CPC_OK)
            Payload:
                auto
*/
const CPC_CORE_CALL_SUBSYSTEM = "CORE-CALL-SUBSYSTEM";

# DEALER INTERFACE -> CORE (STRING): "CORE-LOG-AUDIT": log audit event
/** Payload:
        literal string to log

    response:
        ROUTER CORE -> INTERFACE (data): "OK" (CPC_OK)
*/
const CPC_CORE_LOG_AUDIT = "CORE-LOG-AUDIT";

# DEALER INTERFACE -> CORE (data): "CORE-LOG-IF": log interface event
/** Payload:
        string method
        softlist<auto> args

    response:
        no response: one-way command
*/
const CPC_CORE_LOG_IF = "CORE-LOG-IF";

# DEALER CORE -> ANY (*YAML): "CORE-LOG-SUBSCRIBE": subscribe to the remote program's log
/** Payload (optional):
        string log literal name of log to subscribe to

    response:
        ROUTER CORE -> ANY (data): "OK" (CPC_OK)
*/
const CPC_CORE_LOG_SUBSCRIBE = "CORE-LOG-SUBSCRIBE";

# DEALER CORE -> ANY (*YAML): "CORE-LOG-UNSUBSCRIBE": unsubscribe from the remote program's log
/** Payload (optional):
        string log literal name of log to unsubscribe from

    response:
        ROUTER CORE -> ANY (data): "OK" (CPC_OK)
*/
const CPC_CORE_LOG_UNSUBSCRIBE = "CORE-LOG-UNSUBSCRIBE";

# DEALER MASTER -> CORE (data): "CORE-GET-SUBSCRIPTIONS": get subscription status for the given logs
/** Payload:
        list<string>: logs

    response:
        ROUTER CORE -> ANY (data): "OK" (CPC_OK)
        hash<string, bool> of logs with active subscriptions
*/
const CPC_CORE_GET_SUBSCRIPTIONS = "CORE-GET-SUBSCRIPTIONS";

# DEALER CORE -> INTERFACE (data): "INTERFACE_CALL_METHOD": call interface method
/** Payload:
        string method
        auto args

    response:
        ROUTER CORE -> INTERFACE (data): "OK" (CPC_OK)
*/
const CPC_INTERFACE_CALL_METHOD = "INTERFACE_CALL_METHOD";

# DEALER INTERFACE -> CORE (data): "CORE-CALL-FUNCTION": call core function
/** Payload:
        string name
        *softlist<auto> args

    response:
        ROUTER CORE -> INTERFACE (data): "OK" (CPC_OK)
            Payload:
                auto
*/
const CPC_CORE_CALL_FUNCTION = "CORE-CALL-FUNCTION";

# DEALER INTERFACE -> CORE (data): "CORE-CALL-STATIC-METHOD": call core static method
/** Payload:
        string cname
        string mname
        *softlist<auto> args

    response:
        ROUTER CORE -> INTERFACE (data): "OK" (CPC_OK)
            Payload:
                auto
*/
const CPC_CORE_CALL_STATIC_METHOD = "CORE-CALL-STATIC-METHOD";

# DEALER ANY -> CORE (data): "CORE-GET-DEBUG-INFO": get debug info
/** Payload: none

    response:
        ROUTER CORE -> INTERFACE (data): "OK" (CPC_OK)
            Payload:
                auto
*/
const CPC_CORE_GET_DEBUG_INFO = "CORE-GET-DEBUG-INFO";

# DEALER ANY -> CORE (data): "CORE-GET-SYSTEM-TOKEN": get system authentication token
/** Payload: none

    response:
        ROUTER CORE -> INTERFACE (data): "OK" (CPC_OK)
            Payload:
                string: token
*/
const CPC_CORE_GET_SYSTEM_TOKEN = "CORE-GET-SYSTEM-TOKEN";

#! returns the unique process name for the qorus core process
string sub qorus_core_get_process_name(int id) {
    return QDP_NAME_QORUS_CORE + "-" + id;
}

# DEALER CORE -> DISTRIBUTED PROCESS (i.e.INTERFACE/QDSP) (hash): "CORE-DEBUG-COMMAND": debug message
const CPC_CORE_DEBUG_COMMAND = "CORE-DEBUG-COMMAND";

# DISTRIBUTED PROCESS -> DEALER CORE (data): "CORE-DEBUG-EVENT": debug response or notification event
/** Payload:
        string method (send/broadcast)
        softlist<auto> args

    response:
        no response: one-way command
*/
const CPC_CORE_DEBUG_EVENT = "CORE-DEBUG-EVENT";
