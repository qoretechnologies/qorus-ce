/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

class OMQ::Props {
    public {
        # length of the value column
        const COLUMN_LEN = 4000;
    }

    private {
        # hash holding domain, key, and property values
        hash props;

        # RWLock for access
        RWLock rwl();
    }

    # NOTE: transaction handling performed externally
    private string doUpdate(string domain, string key, any value, *reference<hash<string, bool>> ph,
            reference<list<hash<auto>>> ul) {
        if (!domain.val())
            throw "PARAMATER-ERROR", "'domain' is a required parameter";

        if (!key.val())
            throw "PARAMATER-ERROR", "'key' is a required parameter";

        if (domain == "omq")
            throw "UPDATE-ERROR", "parameters in the 'omq' domain cannot be updated";

        bool keyexists = exists props{domain}{key};

        string action;
        # if it's an insert
        if (exists value) {
            if (!ph.set) {
                ph.set = True;
            }

            string strval = getSerializedPropertyValue(domain, key, value);
            if (keyexists) {
                omqp.exec("update system_properties set value = %v where domain = %v and keyname = %v", strval, domain, key);
                action = "UPDATE";
            } else {
                omqp.exec("insert into system_properties (domain, keyname, value) values (%v, %v, %v)", domain, key, strval);
                action = "INSERT";
            }

            ul += {"cmd": "SET", "domain": domain, "key": key, "value": value};
        } else if (keyexists) {
            if (!ph.del) {
                ph.del = True;
            }

            omqp.exec("delete from system_properties where domain = %v and keyname = %v", domain, key);

            ul += {"cmd": "DEL", "domain": domain, "key": key};
            action = "DELETE";
        } else {
            action = "IGNORED";
        }

        return action;
    }

    private string getSerializedPropertyValue(string domain, string key, auto value) {
        string strval = serialize_qorus_data(value);
        if (length(strval) > COLUMN_LEN) {
            throw "PROP-ERROR", sprintf("%y.%y serialized value of length %d (%y) exceeds %d character limit for "
                "column", domain, key, length(strval), strval, COLUMN_LEN);
        }
        return strval;
    }

    private applyUpdates(list ul) {
        foreach hash h in (ul) {
            switch (h.cmd) {
                case "SET": {
                    props{h.domain}{h.key} = h.value;
                    break;
                }
                case "DEL": {
                    delete props{h.domain}{h.key};
                    # if the last key in a domain is deleted, then delete the domain
                    if (!props{h.domain})
                        delete props{h.domain};
                    break;
                }
            }
        }
    }

    int reload() {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        delete props;

        *hash q;

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                q = omqp.select("select * from system_properties");
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

        context (q) {
            try {
                # issue #2854: system properties in the "omq" domain must always be read as strings
                props.%domain.%keyname = %domain == "omq" ? %value : parse_yaml(%value);
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::INFO, "system property %y.%y cannot be parsed; value: %y, error %s: %s", %domain,
                    %keyname, %value, ex.err, ex.desc);
            }
        }

        return q.domain.size();
    }

    updatePath(string path, auto value) {
        # update data
        list<hash<DotInfo>> dot_list = UserApi::_priv_get_dot_string_list(path);
        if (dot_list[0].key == "omq") {
            throw "UPDATE-ERROR", "parameters in the 'omq' domain cannot be updated";
        }

        if (dot_list.size() == 1) {
            if (value.typeCode() != NT_HASH) {
                throw "UPDATE-ERROR", sprintf("cannot update an entire property domain (%y) to type %y; must be "
                    "\"hash\"", dot_list[0].key, value.type());
            }
        }

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        hash<auto> new_props = _priv_update_hash_dot_value(props, dot_list, value);

        QorusRestartableTransaction trans();
        while (True) {
            try {
                AbstractTable system_properties = Qorus.dsmanager.getOmqTable("system_properties");

                on_error omqp.rollback();
                on_success omqp.commit();

                string domain = dot_list[0].key;

                if (dot_list.size() == 1) {
                    # find deleted keys
                    if (*hash<auto> domain_diff = (props{domain} - (keys value))) {
                        system_properties.del({
                            "domain": domain,
                            "keyname": op_in(keys domain_diff),
                        });
                        QDBG_LOG("Props::updatePath() deleted keys: %s.%y", domain, keys domain_diff);
                    }

                    map system_properties.upsert({
                        "domain": domain,
                        "keyname": $1.key,
                        "value": getSerializedPropertyValue(domain, $1.key, $1.value),
                    }), value.pairIterator();
                    QDBG_LOG("Props::updatePath() upserted: %s.%y", domain, value);
                } else {
                    QDBG_ASSERT(dot_list.size() > 1);
                    string key = dot_list[1].key;

                    system_properties.upsert({
                        "domain": domain,
                        "keyname": key,
                        "value": getSerializedPropertyValue(domain, key, new_props{domain}{key}),
                    });
                    QDBG_LOG("Props::updatePath() upserted: %s.%s = %y", domain, key, new_props{domain}{key});
                }
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

        props = new_props;
    }

    hash<auto> get() {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return props;
    }

    *hash<auto> get(string domain) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return props{domain};
    }

    auto get(string domain, softstring key) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return props{domain}{key};
    }

    # issue #2152: replace all properties in a single atomic call
    hash<auto> replaceAll(hash ph) {
        BulkInsertOperation insert(get_sql_table_system(omqp, "system_properties"));

        # key count
        int kcnt;

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        QorusRestartableTransaction trans();
        while (True) {
            kcnt = 0;
            try {
                on_error {
                    insert.discard();
                    omqp.rollback();
                }
                on_success {
                    insert.flush();
                    omqp.commit();
                }

                # delete all existing rows, if any
                omqp.exec("delete from system_properties where domain != %v", "omq");

                # insert new rows
                foreach hash<auto> h in (ph.pairIterator()) {
                    # ignore the system "omq" domain
                    if (h.key == "omq")
                        continue;

                    if (h.value.typeCode() != NT_HASH)
                        throw "PROP-ERROR", sprintf("value assigned to domain %y is type %y; expecting \"hash\"", h.key, h.value.type());

                    foreach hash dh in (h.value.pairIterator()) {
                        string strval = serialize_qorus_data(dh.value);
                        if (length(strval) > COLUMN_LEN)
                            throw "PROP-ERROR", sprintf("%y.%y serialized value of length %d (%y) exceeds %d character limit for column", h.key, dh.key, length(strval), strval, COLUMN_LEN);

                        insert.queueData(("domain": h.key, "keyname": dh.key, "value": strval));
                        ++kcnt;
                    }
                }

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

        # replace properties, keeping the "omq" domain
        props = ("omq": props.omq) + ph;
        qlog(LoggerLevel::INFO, "replaced system properties with %d domain%s, %d keys", ph.size(), ph.size() == 1 ? "" : "s", kcnt, kcnt == 1 ? "" : "s");
        return props;
    }

    string update(string domain, softstring key, auto value) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        list ul = ();
        string rv;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                rv = doUpdate(domain, key, value, NOTHING, \ul);
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
        applyUpdates(ul);
        return rv;
    }

    hash<auto> updateMany(hash new_data) {
        if (new_data.omq)
            throw "UPDATE-ERROR", "parameters in the 'omq' domain cannot be updated";

        hash actions;
        hash ph;
        list ul = ();

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        QorusRestartableTransaction trans();
        while (True) {
            actions = {};
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                foreach hash h in (new_data.pairIterator())
                    map +actions{doUpdate(h.key, $1.key, $1.value, \ph, \ul)}, h.value.pairIterator();
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
        applyUpdates(ul);

        return actions;
    }

    string export(*softlist<softstring> domains, softbool yaml = True) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        hash exp;
        if (domains) {
            foreach string dom in (domains) {
                if (dom == "omq")
                    throw "EXPORT-ERROR", "Domain 'omq' cannot be exported";
                if (!props{dom})
                    throw "EXPORT-ERROR", sprintf("Domain '%s' does not exist", dom);
                exp.qorus_properties{dom} = props{dom};
            }
        } else {
            exp.qorus_properties = props;
            remove exp.qorus_properties.omq;
        }

        # format omq related additional infos into the root element
        hash attrs;
        attrs.instance = Qorus.options.get("instance-key");
        foreach string attr in (keys props.omq)
            attrs{attr} = props.omq{attr};
        exp.qorus_properties."^attributes^" = attrs;

        return yaml ? serialize_qorus_data(exp) : make_xml(fixMakeXml(exp), XGF_ADD_FORMATTING);
    }

    nothing import(string data, *softlist<softstring> domains) {
        hash inv = data =~ /^</ ? fixParseXml(parse_xml(data)) : parse_yaml(data);
        if (!inv.qorus_properties)
            throw "IMPORT-ERROR", "input data error; import expects 'qorus_properties' as the root element";

        # we don't care about informational attrs, ignore "omq" domain
        inv.qorus_properties -= ("^attributes^", "omq");

        # remove unwanted domains by taking a slice of the hash
        if (domains)
            inv.qorus_properties = inv.qorus_properties{domains};

        updateMany(inv.qorus_properties);
    }

    # issue 1975 handle system properties with invalid xml key names
    static hash<auto> fixMakeXml(hash exp) {
        # artificial name counter
        int c = 0;
        foreach hash h in (exp.pairIterator()) {
            # first process values
            switch (h.value.typeCode()) {
                case NT_HASH:
                    exp{h.key} = Props::fixMakeXml(h.value);
                    break;
                case NT_LIST:
                    exp{h.key} = Props::fixMakeXml(h.value);
                    break;
            }
            # ignore special key names relevant for XML serialization
            if (h.key =~ /^\^/)
                continue;

            /** check if key name is a valid XML element name
                - Element names must start with a letter or underscore
                - Element names cannot start with the letters xml (case-insensitive)
                - Element names can only contain letters, digits, hyphens, underscores, and periods
            */
            if (h.key !~ /^[a-z_]/i || h.key =~ /^xml/i || h.key !~ /^[-a-z0-9_\.]+$/) {
                string nk = sprintf("____QORUS_FAKE_KEY_%d", c++);
                exp{nk} = (
                    "key": h.key,
                    "value": remove exp{h.key},
                );
            }
        }
        return exp;
    }

    static list<auto> fixMakeXml(list exp) {
        list<auto> l = ();
        foreach auto v in (exp) {
            switch (v.typeCode()) {
                case NT_HASH:
                    l += Props::fixMakeXml(v);
                    break;
                case NT_LIST:
                    l += Props::fixMakeXml(v);
                    break;
                default:
                    l += v;
            }
        }
        return l;
    }

    static hash<auto> fixParseXml(hash exp) {
        foreach hash<auto> h in (exp.pairIterator()) {
            # first process keys
            if (h.key =~ /^____QORUS_FAKE_KEY_[0-9]+$/) {
                exp{h.value.key} = h.value.value;
                remove exp{h.key};
                h = h.value;
            }

            switch (h.value.typeCode()) {
                case NT_HASH:
                    exp{h.key} = Props::fixParseXml(h.value);
                    break;
                case NT_LIST:
                    exp{h.key} = Props::fixParseXml(h.value);
                    break;
            }
        }
        return exp;
    }

    static list<auto> fixParseXml(list exp) {
        list l = ();
        foreach auto v in (exp) {
            switch (v.typeCode()) {
                case NT_HASH:
                    l += Props::fixParseXml(v);
                    break;
                case NT_LIST:
                    l += Props::fixParseXml(v);
                    break;
                default:
                    l += v;
            }
        }
        return l;
    }
}

