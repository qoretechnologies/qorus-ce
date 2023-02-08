# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%allow-debugger

public namespace OMQ;

#! Implements getting source code from omq database
class OMQ::QorusDebugProgramSource {
    private:internal hash getValueFromTable(string table, string column, hash<auto> wh) {
        hash<auto> res.origin = "omq database";
        SqlUtil::AbstractTable tbl = get_sql_table_system_trans('omq', table);
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                res.content = tbl.selectRow({'columns': column, 'where': wh}){column};
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }
        return res;
    }

    private:internal hash<auto> getConstantSource(string name, string ver) {
        return getValueFromTable('constants', 'body', {'name': name, 'version': ver});
    }

    private:internal hash<auto> getFunctionSource(string name, string ver) {
        return getValueFromTable('function_instance', 'body', {'name': name, 'version': ver});
    }

    private:internal hash<auto> getClassSource(string name, string ver) {
        *hash<auto> info = Qorus.qmm.rLookupClassInfo(name, ver);
        if (!info) {
            throw "INVALID-CLASS", sprintf("no class with name %y and version %y exists", name, ver);
        }
        return {
            "origin": "Qorus metadata cache",
            "content": info.body,
        };
    }

    private:internal hash<auto> getJobSource(string name, string ver) {
        *hash<auto> info = Qorus.qmm.rLookupJob(name);
        if (!info) {
            throw "INVALID-JOB", sprintf("no job with name %y and version %y exists", name, ver);
        }
        if (ver != info.version) {
            throw "INVALID-JOB", sprintf("job %y v%y cannot be retrieved; only version %y is available", name, ver,
                info.version);
        }
        return {
            "origin": "Qorus metadata cache",
            "content": info."code",
        };
    }

    private:internal hash<auto> getServiceSource(string type, string name, string ver) {
        *hash<auto> info = Qorus.qmm.rLookupServiceInfo(type, name, ver);
        if (!info) {
            throw "INVALID-SERVICE", sprintf("no %s service with name %y and version %y exists", type, name, ver);
        }
        return {
            "origin": "Qorus metadata cache",
            "content": info.class_source,
        };
    }

    private:internal hash<auto> getServiceMethodSource(string svcname, string svcver, string method) {
        *hash<auto> info = Qorus.qmm.rLookupServiceMethodInfo(svcname, svcver, method);
        if (!info) {
            throw "INVALID-SERVICE", sprintf("no service method %y found for service %y version %y", method, svcname,
                svcver);
        }
        return {
            "origin": "Qorus metadata cache",
            "content": info.body,
        };
    }

    private hash<auto> getSourceCodeForLabelImpl(string name) {
        # strip obsolete
        name =~ s/^<run-time-loaded: (.*)>$/$1/;
        switch (name) {
            case /^[A-Z]+ /:
                #<run-time-loaded: CLASS test-debug_class:1.0>
                *list l = (name =~ x/([A-Z]+) ([^:]+):(.+)$/);
                switch (l[0]) {
                    case 'CLASS':
                        return getClassSource(l[1], l[2]);
                    case 'FUNCTION':
                        return getFunctionSource(l[1], l[2]);
                    case 'CONSTANT':
                        return getConstantSource(l[1], l[2]);
                }
                break;
            case /^[a-z]+: /:
                #<run-time-loaded: job: test-debug_job v1.0 (5)>
                *list l = (name =~ x/([^:]+): ([^ ]+) v(.+) \([0-9]+\)$/);
                switch (l[0]) {
                    case 'function':
                        return getFunctionSource(l[1], l[2]);
                    case 'class':
                        return getClassSource(l[1], l[2]);
                    case 'constant':
                        return getConstantSource(l[1], l[2]);
                    case 'job':
                        return getJobSource(l[1], l[2]);
                }
                break;
            case /^[a-z]+ service: /:
                #system service: info v4.0 (5)
                *list l = (name =~ x/([a-z]+) ([^:]+): ([^ ]+) v(.+) \([0-9]+\)$/);
                return getServiceSource(l[0], l[2], l[3]);
            case /^service method: /:
                #<run-time-loaded: service method: test-debug_service v1.0 (11) about (250)>
                *list l = (name =~ x/([^:]+): ([^ ]+) v(.+) \([0-9]+\) ([^ ]+) \([0-9]+\)$/);
                return getServiceMethodSource(l[1], l[2], l[3]);
        }
        throw "DEBUG-HANDLER-ERROR", sprintf("Cannot get source for label: %y", name);
    }
}
