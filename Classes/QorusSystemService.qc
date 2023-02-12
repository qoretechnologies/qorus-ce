# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusSystemService.qc base class definition for class-based Qorus system services

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

#! The base class for Qorus system services
/**
*/
public class OMQ::UserApi::Service::QorusSystemService inherits QorusService {
    static verifySensitiveDataRequestRo() {
%ifdef QorusServer
        #log(LoggerLevel::DEBUG, "verifySensitiveDataRequestRo() context: %N", ServiceApi::getCallContext());

        # throw an exception if there is an attempt to return sensitive data over an unencrypted external connection
        if ((*hash<auto> cx = ServiceApi::getCallContext().cx) && !(cx.ssl || cx.internal)) {
            throw "SENSITIVE-DATA-ERROR", "cannot retrieve sensitive data over an insecure connection";
        }
%endif
    }

    static verifySensitiveDataRequestDel() {
%ifdef QorusServer
        #log(LoggerLevel::DEBUG, "verifySensitiveDataRequestDel() context: %N", ServiceApi::getCallContext());

        # throw an exception if there is an attempt to return sensitive data over an unencrypted external connection
        if ((*hash<auto> cx = ServiceApi::getCallContext().cx) && !(cx.ssl || cx.internal)) {
            throw "SENSITIVE-DATA-ERROR", "cannot delete sensitive data over an insecure connection";
        }
%endif
    }

    # get cached table object if present, otherwise it creates one from scratch.
    static SqlUtil::AbstractTable getSqlTableSystem(string datasource, string table_name) {
%ifdef QorusServer
        return Qorus.dsmanager.getSqlTableSystem(datasource, table_name);
%endif
    }

    # get cached table object if present, otherwise it creates one from scratch.
    static SqlUtil::AbstractTable getSqlTableSystem(AbstractDatasource datasource, string table_name) {
%ifdef QorusServer
        return Qorus.dsmanager.getSqlTableSystem(datasource, table_name);
%endif
    }

    static SqlUtil::AbstractTable getSqlTableSystemTrans(string ds, string table) {
%ifdef QorusServer
        return QorusSystemService::getSqlTableSystemTrans(Qorus.dsmanager.getPool(ds, False, False), table);
%endif
    }

    static SqlUtil::AbstractTable getSqlTableSystemTrans(AbstractDatasource dsp, string table) {
%ifdef QorusServer
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error dsp.rollback();

                return get_sql_table_system(dsp, table);
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
        }
%endif
    }

    static list<hash<auto>> processAuditEvents(*hash<auto> q) {
%ifdef QorusServer
        return process_audit_events();
%endif
    }

    # FIXME: remove this method
    static string compatDeprecatedMakeSelectListSingle(auto list) {
%ifdef QorusServer
        if (!exists list || list.typeCode() == NT_LIST && !elements list)
            return "null";

        return foldl $1 + "," + $2, (map QorusSystemService::compatDeprecatedSqlValue("oracle", $1).toString(), list);
%endif
    }

    # FIXME: remove this method
    static string compatDeprecatedMakeSelectList(auto driver, auto list) {
%ifdef QorusServer
        if (!exists list || (list.typeCode() == NT_LIST && !elements list)) {
            return "null";
        }

        if (driver.typeCode() == NT_OBJECT) {
            driver = driver.getDriverName();
        }

        return foldl $1 + $2, (map sprintf("%s,", QorusSystemService::compatDeprecatedSqlValue(driver, $1)), list);
%endif
    }

    # FIXME: remove this method
    static string compatDeprecatedDbDate(string driver, date date) {
%ifdef QorusServer
        return driver == "oracle"
            ? QorusSystemService::compatDeprecatedOracleDate(date)
            : date.format("'YYYY-MM-DD HH:mm:SS.ms'");
%endif
    }

%ifdef QorusServer
    # FIXME: remove this method
    static private:internal string compatDeprecatedFixQuotes(string str) {
        int p;

        while ((int i = index(str, "'", p)) != -1) {
            splice str, i, 0, "'";
            p = i + 2;
        }
        return str;
    }

    # FIXME: remove this method
    static private:internal auto compatDeprecatedSqlValue(string driver, auto v) {
        switch (v.typeCode()) {
            case NT_STRING:
                return sprintf("'%s'", QorusSystemService::compatDeprecatedFixQuotes(v));
            case NT_DATE:
                return QorusSystemService::compatDeprecatedDbDate(driver, v);
            case NT_BOOLEAN:
                return int(v);
        }
        if (!exists v || v === NULL)
            return "NULL";

        return v;
    }

    # FIXME: remove this method
    static private:internal string compatDeprecatedOracleDate(date d) {
        return "to_date('" + d.format("YYYYMMDDHHmmSS") + "', 'YYYYMMDDHH24MISS')";
    }
%endif
}
