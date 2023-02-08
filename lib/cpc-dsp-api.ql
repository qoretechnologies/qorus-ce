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

# commands
# DEALER ANY -> SERVER (data): "DSP-COMMIT": commit the transaction
/** Payload:
        string trans

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_COMMIT = "DSP-COMMIT";

# DEALER ANY -> SERVER (data): "DSP-ROLLBACK": rollback the transaction
/** Payload:
        string trans

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_ROLLBACK = "DSP-ROLLBACK";

# DEALER ANY -> SERVER (data): "DSP-BEGIN-TRANS": allocate a datasource connection and service thread to the caller
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_BEGIN_TRANS = "DSP-BEGIN-TRANS";

# DEALER ANY -> SERVER (data): "DSP-SELECT-COLUMNS": execute a select statement and return hashes of lists
/** Payload:
        string trans
        string sql
        *list<auto> args

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_SELECT_COLUMNS = "DSP-SELECT-COLUMNS";

# DEALER ANY -> SERVER (data): "DSP-SELECT-ROWS": execute a select statement and return lists of hashes
/** Payload:
        string trans
        string sql
        *list<auto> args

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_SELECT_ROWS = "DSP-SELECT-ROWS";

# DEALER ANY -> SERVER (data): "DSP-SELECT-ROW": execute a select statement and a hash of a single row
/** Payload:
        string trans
        string sql
        *list<auto> args

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_SELECT_ROW = "DSP-SELECT-ROW";

# DEALER ANY -> SERVER (data): "DSP-EXEC": execute an SQL statement and return the result
/** Payload:
        string trans
        string sql
        *list<auto> args

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_EXEC = "DSP-EXEC";

# DEALER ANY -> SERVER (data): "DSP-EXEC-RAW": execute an SQL statement with no args and return the result
/** Payload:
        string trans
        string sql

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_EXEC_RAW = "DSP-EXEC-RAW";

# DEALER ANY -> SERVER (data): "DSP-GET-SERVER-VER": get the DB server version
/** responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_GET_SERVER_VER = "DSP-GET-SERVER-VER";

# DEALER ANY -> SERVER (data): "DSP-GET-CLIENT-VER": get the DB client version
/** responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_GET_CLIENT_VER = "DSP-GET-CLIENT-VER";

# ROUTER SERVER -> ANY (data): "DSP-EXCEPTION": an execption occurred in the qdsp server processing the request
/** Payload:
        hash<ExceptionInfo> ex
        bool in_trans
*/
const CPC_DSP_EXCEPTION = "DSP-EXCEPTION";

# DEALER ANY -> SERVER (NONE): "DSP-GET-CAPS": get pool capabilities
/**
    response:
        ROUTER SERVER -> ANY (STRING): "OK" (CPC_OK)
            Payload:
                string
*/
const CPC_DSP_GET_CAPS = "DSP-GET-CAPS";

# DEALER ANY -> SERVER (NONE): "DSP-GET-USAGE": get usage info
/**
    response:
        ROUTER SERVER -> ANY (STRING): "OK" (CPC_OK)
            Payload:
                hash
*/
const CPC_DSP_GET_USAGE = "DSP-GET-USAGE";

# DEALER ANY -> SERVER (NONE): "DSP-TO-STRING": return a description string of the status of the pool
/** response:
        ROUTER MASTER -> SERVER (STRING): "OK"
*/
const CPC_DSP_TO_STRING = "DSP-TO-STRING";

# DEALER ANY -> SERVER (data): "DSP-GET-DRIVER-INFO": get the DB driver/module info hash
/** responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                hash val
*/
const CPC_DSP_GET_DRIVER_INFO = "DSP-GET-DRIVER-INFO";

# DEALER ANY -> SERVER (data): "DSP-GET-OPTION": get the given option value
/** Payload:
        string opt

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
*/
const CPC_DSP_GET_OPTION = "DSP-GET-OPTION";

# DEALER ANY -> SERVER (data): "DSP-GET-OPTION-HASH": get the option hash
/** responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                hash val
*/
const CPC_DSP_GET_OPTION_HASH = "DSP-GET-OPTION-HASH";

# DEALER ANY -> SERVER (data): "DSP-STMT-DEL": delete SQL statement
/** Payload:
        string process
        string sid

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_DELETE = "DSP-STMT-DEL";

# DEALER ANY -> SERVER (data): "DSP-STMT-PREPARE": prepare SQL statement
/** Payload:
        string process
        string trans
        string sid
        string sql
        *list args

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_PREPARE = "DSP-STMT-PREPARE";

# DEALER ANY -> SERVER (data): "DSP-STMT-PREPARE-RAW": prepare raw SQL statement
/** Payload:
        string process
        string trans
        string sid
        string sql

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_PREPARE_RAW = "DSP-STMT-PREPARE-RAW";

# DEALER ANY -> SERVER (data): "DSP-STMT-FETCH-ROWS": fetch rows
/** Payload:
        string process
        string trans
        int rows

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_FETCH_ROWS = "DSP-STMT-FETCH-ROWS";

# DEALER ANY -> SERVER (data): "DSP-STMT-FETCH-COLUMNS": fetch columns
/** Payload:
        string process
        string trans
        int rows

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_FETCH_COLUMNS = "DSP-STMT-FETCH-COLUMNS";

# DEALER ANY -> SERVER (data): "DSP-STMT-FETCH-ROW": fetch a single row
/** Payload:
        string process
        string trans

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_FETCH_ROW = "DSP-STMT-FETCH-ROW";

# DEALER ANY -> SERVER (data): "DSP-STMT-GET-SQL": get SQL
/** Payload:
        string process
        string trans

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_GET_SQL = "DSP-STMT-GET-SQL";

# DEALER ANY -> SERVER (data): "DSP-STMT-EXEC": exec statement
/** Payload:
        string process
        string trans
        *list args

    responses:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_EXEC = "DSP-STMT-EXEC";

# DEALER ANY -> SERVER (data): "DSP-STMT-ACTIVE": is stmt active?
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)# -*- mode: qore; indent-tabs-mode: nil -*-

%new-style
%strict-args
%require-types
%enable-all-warnings
            Payload:
                auto val
*/
const CPC_DSP_STMT_ACTIVE = "DSP-STMT-ACTIVE";

# DEALER ANY -> SERVER (data): "DSP-STMT-NEXT": advance iterator
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
*/
const CPC_DSP_STMT_NEXT = "DSP-STMT-NEXT";

# DEALER ANY -> SERVER (data): "DSP-STMT-VALID": is iterator valid
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
*/
const CPC_DSP_STMT_VALID = "DSP-STMT-VALID";

# DEALER ANY -> SERVER (data): "DSP-STMT-GET-OUTPUT-ROWS": get output rows
/** Payload:
        string process
        string trans

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_GET_OUTPUT_ROWS = "DSP-STMT-GET-OUTPUT-ROWS";

# DEALER ANY -> SERVER (data): "DSP-STMT-GET-OUTPUT": get output
/** Payload:
        string process
        string trans

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_GET_OUTPUT = "DSP-STMT-GET-OUTPUT";

# DEALER ANY -> SERVER (data): "DSP-STMT-BIND": bind values and placeholders
/** Payload:
        string process
        string trans
        *list args

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_BIND = "DSP-STMT-BIND";

# DEALER ANY -> SERVER (data): "DSP-STMT-BIND-VALUES": bind values
/** Payload:
        string process
        string trans
        *list args

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_BIND_VALUES = "DSP-STMT-BIND-VALUES";

# DEALER ANY -> SERVER (data): "DSP-STMT-BIND-PLACEHOLDERS": bind placeholders
/** Payload:
        string process
        string trans
        *list args

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_BIND_PLACEHOLDERS = "DSP-STMT-BIND-PLACEHOLDERS";

# DEALER ANY -> SERVER (data): "DSP-STMT-DEFINE": define statement buffers
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_DEFINE = "DSP-STMT-DEFINE";

# DEALER ANY -> SERVER (data): "DSP-STMT-DESCRIBE": describe select columns
/** Payload:
        string process
        string trans

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_DESCRIBE = "DSP-STMT-DESCRIBE";

# DEALER ANY -> SERVER (data): "DSP-STMT-GET-VALUE": retrieve output values
/** Payload:
        string process
        string trans

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_GET_VALUE = "DSP-STMT-GET-VALUE";

# DEALER ANY -> SERVER (data): "DSP-STMT-AFFECTED-ROWS": get affected rows
/** Payload:
        string process
        string trans

    responses:
        ROUTER SERVER -> ANY (data): "OK" (CPC_OK)
            Payload:
                auto val
        ROUTER SERVER -> ANY (data): "DSP-EXCEPTION" (CPC_DSP_EXCEPTION)
*/
const CPC_DSP_STMT_AFFECTED_ROWS = "DSP-STMT-AFFECTED-ROWS";

# DEALER ANY -> SERVER (data): "DSP-STMT-CLOSE": close statement
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_CLOSE = "DSP-STMT-CLOSE";

# DEALER ANY -> SERVER (data): "DSP-STMT-COMMIT": commit transaction and close statement
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_COMMIT = "DSP-STMT-COMMIT";

# DEALER ANY -> SERVER (data): "DSP-STMT-ROLLBACK": rollback transaction and close statement
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_STMT_ROLLBACK = "DSP-STMT-ROLLBACK";

# DEALER ANY -> SERVER (NONE): "DSP-PING": keep-alive message; also verifies if the DB connection is up
/** response:
        ROUTER ANY -> ANY (NONE): "DSP-PONG" (CPC_DSP_PONG)
*/
const CPC_DSP_PING = "DSP-PING";

# ROUTER SERVER -> ANY (data): "DSP-PONG": ping response
/** Payload:
        bool status
*/
const CPC_DSP_PONG = "DSP-PONG";

# DEALER ANY -> SERVER (data): "DSP-CONN-GET": coordinated mode: get connection
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (NONE): "OK" (CPC_OK)
            Payload:
                string connstr
                string db_connstr
*/
const CPC_DSP_CONN_GET = "DSP-CONN-GET";

# DEALER ANY -> SERVER (data): "DSP-CONN-REL": coordinated mode: release connection
/** Payload:
        string process
        string trans

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_CONN_REL = "DSP-CONN-REL";

# DEALER ANY -> SERVER (data): "DSP-RESET": reset the qdsp process with new connection info; recreate the pool
/** Payload:
        string connstr

    response:
        ROUTER SERVER -> ANY (NONE): "ACK" (CPC_ACK)
*/
const CPC_DSP_RESET = "DSP-RESET";

# INTERNAL (NONE): "DSP-ABORTED-PROC": put on the transaction queue when a process with active statements aborts
/** Payload:
        none

    response: none
*/
const CPC_DSP_ABORTED_PROCESS = "DSP-ABORTED-PROC";

# client/server data declarations
const QDSP_TempTrans = "%TEMP%";

#! returns the unique process name for the datasource pool
string sub qdsp_get_process_name(string dsname) {
    return QDP_NAME_QDSP + "-" + dsname;
}
