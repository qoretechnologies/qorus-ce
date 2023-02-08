# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

#! @file qorus-common-master-core-client.ql defines functions used in the client library

# this file is automatically included by the Qorus client library and should not be included directly by Qorus client programs

%new-style
%require-types
%push-parse-options

namespace Priv {
*string sub restart_transaction_intern_oracle(hash<auto> ex) {
    # restart transaction if one of the following errors has been encountered:
    # ORA-01041: internal error. hostdef extension doesn't exist
    # ORA-2540[1-9]: cluster failover errors
    # ORA-03113: end-of-file on communication channel
    # ORA-03114: not connected to ORACLE
    # ORA-00060: deadlock detected while waiting for resource
    *string err = (ex.desc =~ x/ORA-(01041|2540[1-9]|0311[34]|00060)/)[0];
    if (!err) {
        return;
    }
    return sprintf("cluster failover detected: %s: ORA-%s: %s: %s", get_ex_pos(ex), err, ex.err, ex.desc);
}

# see: https://www.postgresql.org/docs/9.0/static/errcodes-appendix.html
const PGSQL_RESTART_TRANSACTION_CODES = {
    "08000": True, # connection_exception
    "08003": True, # connection_does_not_exist
    "08006": True, # connection_failure
    "08001": True, # sqlclient_unable_to_establish_sqlconnection
    "08004": True, # sqlserver_rejected_establishment_of_sqlconnection
    "08007": True, # transaction_resolution_unknown
    "08P01": True, # protocol_violation
};

*string sub restart_transaction_intern_pgsql(hash<auto> ex) {
    # DBI:PGSQL:CONNECTION-ERROR: the connection was lost
    # DBI:PGSQL:ERROR contains arg.alterr error; codes listed in PGSQL_RESTART_TRANSACTION_CODES are used to
    # indicate a transaction restart
    if (ex.err == "DBI:PGSQL:CONNECTION-ERROR"
        || (ex.err == "DBI:PGSQL:ERROR" && PGSQL_RESTART_TRANSACTION_CODES{ex.arg.alterr})
    ) {
        return sprintf("cluster failover detected: %s: %s: %s", ex.arg.alterr ?? "<errcode n/a>", ex.err, ex.desc);
    }
}

*string sub restart_transaction_intern_mysql(hash<auto> ex) {
}

*string sub restart_transaction_intern(string driver, hash<auto> ex) {
    switch (driver) {
        case "oracle": return restart_transaction_intern_oracle(ex);
        case "pgsql": return restart_transaction_intern_pgsql(ex);
        case "mysql": return restart_transaction_intern_mysql(ex);
        default: throw "UNSUPPORTED-DRIVER", sprintf("%y is not a supported driver", driver);
    }
}

bool sub duplicate_key_intern_oracle(hash<auto> ex) {
    return ex.desc =~ /ORA-00001/;
}

bool sub duplicate_key_intern_pgsql(hash<auto> ex) {
    return ex.arg.alterr == 23505;
}

bool sub duplicate_key_intern_mysql(hash<auto> ex) {
    return ex.desc =~ /Duplicate entry/i;
}

bool sub duplicate_key_intern(string driver, hash<auto> ex) {
    switch (driver) {
        case "oracle": return duplicate_key_intern_oracle(ex);
        case "pgsql": return duplicate_key_intern_pgsql(ex);
        case "mysql": return duplicate_key_intern_mysql(ex);
        default: throw "UNSUPPORTED-DRIVER", sprintf("%y is not a supported driver", driver);
    }
}
}

public namespace OMQ {
public namespace UserApi {
#! returns a string error message if any exception in the chain passed was caused by a recoverable DB error, otherwise returns @ref nothing "NOTHING"
/** @param driver the database driver name, which must be a driver supported by the Qorus system schema, currently one of \c "oracle", \c "pgsql", or \c "mysql", otherwise an \c UNSUPPORTED-DRIVER exception is thrown
    @param ex the exception hash

    @return a string error message if any exception in the chain passed was caused by a recoverable DB error, otherwise returns @ref nothing "NOTHING"

    @throw UNSUPPORTED-DRIVER only \c "oracle", \c "pgsql", and \c "mysql" are currently supported

    @since Qorus 3.1.1.p1
*/
public *string sub restart_transaction(string driver, hash<auto> ex) {
    while (True) {
        if (ex.err == "DATASOURCEPOOL-PROCESS-ERROR") {
            return "Qorus qdsp cluster server failover event; restart transaction";
        } else if (ex.err == "DATASOURCEPOOL-TIMEOUT") {
            return "Qorus qdsp cluster pool access timeout; restart transaction";
        }
        *string msg = restart_transaction_intern(driver, ex);
        if (msg)
            return msg;
        if (!ex.next)
            break;
        ex = ex.next;
    }
}

#! Returns True if the error was caused by a duplicate key error
/** @since Qorus 5.1
*/
public bool sub duplicate_key(string driver, hash<auto> ex) {
    while (True) {
        if (duplicate_key_intern(driver, ex)) {
            return True;
        }
        if (!ex.next)
            break;
        ex = ex.next;
    }
    return False;
}
}
}
