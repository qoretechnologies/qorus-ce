# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace OMQ;

class OMQ::AbstractQorusService {
    public {
        string name;
        *string desc;
        # lower case "system" or "user"
        string type;
        string version;
        *string patch;
        *string author;

        int serviceid;
        bool autostart;
        bool manual_autostart;

        bool remote;

        # list of parse option strings
        *list<string> parse_options;

        # service method hash
        hash<string, hash> methods;

        # config item hash
        *hash<auto> config;
    }

    private {
        bool sys;

        # service state upsert closure
        static code psave;
    }

    constructor(string type, string name) {
        self.type = type;
        self.name = name;
        sys = (type == "system");
    }

    hash<auto> getServiceInfo() {
        list<auto> ml = map ("name": $1, "desc": methods{$1}.desc), keys methods;

        return {
            "type": type,
            "name": name,
            "version": version,
            "patch": patch,
            "desc": desc,
            "author": author,
            "serviceid": serviceid,
            "autostart": autostart,
            "remote": remote,
            "manual_autostart": manual_autostart,
            "methods": ml,
        };
    }

    auto getConfigItemValue(string name, *hash<auto> local_context, bool expand_complex_values = True) {
        *hash<auto> config_info = config{name};
        if (!config_info) {
            throw "CONFIG-ITEM-ERROR", sprintf("config item %y is unknown; known config items: %y", name, keys config);
        }

        return getConfigItemValueIntern(name, config_info, local_context, expand_complex_values);
    }

    private auto getConfigItemValueIntern(string name, hash<auto> config_info, *hash<auto> local_context, bool expand_complex_values = True) {
        *string level;
        bool is_set;
        auto value = Qorus.qmm.findConfigItemValue("service", serviceid, name, config_info, \level, \is_set);
        if (!config_info.allowed_values) {
            value = UserApi::expandTemplatedValue(value, local_context, expand_complex_values);
        }
        if (is_set) {
            # TODO: check type
            return value;
        }
        throw "CONFIG-ITEM-ERROR", sprintf("config item %y has neither a value nor a default value", name);
    }

    hash<auto> getConfigItemHash(*hash<auto> local_context) {
        return (map {$1.key: getConfigItemValueIntern($1.key, $1.value, local_context)}, config.pairIterator()) ?? {};
    }

    private *int setupIntern(hash<auto> sq) {
        self += sq.("version", "serviceid", "autostart", "manual_autostart", "patch", "author", "desc");
        remote = sq.remote.toBool();

        if (sq.parse_options) {
            parse_options = sq.parse_options.split(",");
            trim parse_options;
        }

        # get performance cache object
        #pc = Qorus.pcm.add("s" + serviceid);

        *int po;
        if (parse_options) {
            foreach string opt in (parse_options) {
                *int c = ParseOptionStringMap{opt};
                if (!c) {
                    throw "SERVICE-ERROR", sprintf("cannot process unknown parse option %y", opt);
                }
                if (!(c & ServiceParseOptionMask)) {
                    throw "SERVICE-ERROR", sprintf("service references illegal parse option %y; valid parse options: %y", opt, (map ParseOptionCodeMap.$1, ServiceParseOptionList));
                }
                po |= c;
            }
        }
        return po;
    }

    abstract logFatal(string msg);
    abstract logError(string msg);
    abstract logWarn(string msg);
    abstract logInfo(string msg);
    abstract logDebug(string msg);
    abstract logTrace(string msg);
    abstract string getStartReasonText();
    abstract ActionReason getStopReason();
    abstract stopIntern();
    abstract bool getStopping();
    abstract setOptions(hash<auto> h);
    abstract hash getAllOptions();
    abstract auto getOption(string field);
    abstract auto getOption(auto field);

    static *hash<auto> getServiceResource(softint serviceid, string rname) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                QDBG_TEST_CLUSTER_FAILOVER();
                return omqp.selectRow("select resource_type, body from service_file_resources where serviceid = %v "
                    "and name = %v", serviceid, rname);
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
        }
    }

    static staticInit() {
        # transaction handling / recovery handled by the caller
        psave = get_sql_table_system("omq", "service_state_data").getUpsertClosure(
            {"serviceid": 1, "data": "string"}, AbstractTable::UpsertAuto);
    }
}
