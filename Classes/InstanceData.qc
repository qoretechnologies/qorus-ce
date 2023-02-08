# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus InstanceData class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args

public namespace OMQ;

class OMQ::InstanceData inherits Qore::Serializable {
    public {
    }

    private {
        hash info;
        transient RWLock l();
    }

    /*
    constructor() {
    }
    */

    bool empty() {
        return !info.val();
    }

    static bool externalLock(InstanceData idata) {
        if (idata.l.writeLockOwner()) {
            return False;
        }

        # grab write lock in constructor
        idata.l.writeLock();
        return True;
    }

    static externalUnlock(InstanceData idata) {
        if (idata.l.writeLockOwner()) {
            idata.l.writeUnlock();
        }
    }

    reset() {
        delete info;
    }

    initialize(hash new_data) {
        info = new_data;
    }

    replace(hash new_data) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        info = new_data;
    }

    # returns the original data before the update
    hash<auto> replaceAndSave(hash<auto> new_data, softint wfiid) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        hash<auto> orig = info;
        if (orig != new_data) {
            qlog(LoggerLevel::INFO, "replacing dynamic data for workflow_instanceid %d: OLD: %y", wfiid, orig);
            qlog(LoggerLevel::INFO, "replacing dynamic data for workflow_instanceid %d: NEW: %y", wfiid, new_data);

            info = new_data;

            try {
                saveData(wfiid);
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
                rethrow;
            }
        }
        return orig;
    }

    update(hash new_data) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        info += new_data;
    }

    deleteKey(softlist<softstring> list) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        delete info{list};
    }

    auto get(auto field) {
        if (!exists field)
            return info;

        if (field.typeCode() == NT_LIST && elements field == 1)
            field = field[0];

        bool lck = !l.lockOwner();
        if (lck) l.readLock();
        on_exit if (lck) l.readUnlock();

        return info{field};
    }

    updateAndSave(hash new_data, softstring workflow_instanceid) {
        # atomically update the data and save to DB
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        # update data
        info += new_data;

        try {
            saveData(workflow_instanceid);
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            rethrow;
        }
    }

    #! updates data with a path like "account.id" to the given value
    updatePathAndSave(string path, auto val, softstring workflow_instanceid) {
        # atomically update the data and save to DB
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        # update data
        info = UserApi::updateHashDotValue(info, path, val);

        try {
            saveData(workflow_instanceid);
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            rethrow;
        }
    }

    #! returns the old data and provides information if any updates were actually made
    hash<auto> updateAndSave(hash new_data, softstring workflow_instanceid, reference<bool> updated) {
        # atomically update the data and save to DB
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        # update data
        hash<auto> old_data = info;
        info += new_data;

        if (info != old_data) {
            try {
                saveData(workflow_instanceid);
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
                rethrow;
            }
            updated = True;
        }

        return old_data;
    }

    #! updates data with a path like "account.id" to the given value
    /* returns the old data and provides information if any updates were actually made
    */
    hash<auto> updatePathAndSave(string path, auto val, softstring workflow_instanceid, reference<bool> updated) {
        # atomically update the data and save to DB
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        # update data
        hash<auto> old_data = info;
        info = UserApi::updateHashDotValue(info, path, val);

        if (info != old_data) {
            try {
                saveData(workflow_instanceid);
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
                rethrow;
            }
            updated = True;
        }

        return old_data;
    }

    bool deleteAndSave(softlist<auto> keysv, softstring workflow_instanceid) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        *hash<auto> val = remove info{keysv};

        # only save if something was removed
        if (val) {
            try {
                saveData(workflow_instanceid);
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
                rethrow;
            }
            return True;
        }
        return False;
    }

    # must be called within the lock!
    private:internal saveData(softint workflow_instanceid) {
        # save dynamic data to DB
        string str = serialize_qorus_data(info);

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                sqlif.instanceDataSaveData(str, workflow_instanceid);
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
    }
}

class OMQ::SensitiveInstanceData inherits OMQ::InstanceData {
    private:internal {
        # key = alias value, value = ("key": sensitive key name, "value": sensitive key value)
        hash aliases;

        # reverse alias map: key -> value -> alias -> True
        hash rah;

        # metadata map
        hash mh;
    }

    # data is in the following format: keyname -> value -> ("aliases": list of strings, "data": hash)
    initialize(hash<auto> data) {
        foreach hash kh in (data.pairIterator()) {
            foreach hash vh in (kh.value.pairIterator()) {
                # assign sensitive data
                info{kh.key}{vh.key} = vh.value.data;

                # assign aliases
                map aliases{$1} = {
                    "skey": kh.key,
                    "svalue": vh.key,
                }, vh.value.aliases;

                # assign reverse aliases
                map rah{kh.key}{vh.key}.$1 = True, vh.value.aliases;

                # assign metadata
                mh{kh.key}{vh.key} = vh.value.meta;
            }
        }
    }

    resetData() {
        # reset data in case of a restartable TRANSACTION
        delete info;
        delete aliases;
        delete rah;
        delete mh;
    }

    # returned with API requests
    *hash getApiData() {
        if (!info)
            return;

        hash rv;
        foreach string skey in (keys info) {
            rv{skey} = map {$1.key: {
                "data": $1.value,
                "aliases": rah{skey}{$1.key}.keys(),
                "meta": mh{skey}{$1.key},
            }}, info{skey}.pairIterator();
        }

        return rv;
    }

    bool empty() {
        return info.empty();
    }

    replaceAndSaveMulti(hash<string, hash<string, hash<SensitiveDataInfo>>> sinfo, softint wfiid) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        # process aliases: skey -> svalue -> alias action hash
        hash<string, hash<string, hash<string, list>>> ac;
        # for actual saving to the DB: skey -> svalue -> sdh
        hash<string, hash<string, hash>> sdh;

        foreach hash sh in (sinfo.pairIterator()) {
            string skey = sh.key;
            foreach hash vh in (sh.value.pairIterator()) {
                string svalue = vh.key;

                # handle aliases
                ac{skey}{svalue} = {
                    "del": (),
                    "add": (),
                };
                replaceDataIntern(skey, svalue, vh.value.data, vh.value.aliases, vh.value.meta, \ac{skey}{svalue});

                if (ac{skey}{svalue}.add || ac{skey}{svalue}.del)
                    updateAliases(skey, svalue, ac{skey}{svalue});

                # prepare data for saving to the DB; serialize and encrypt data
                hash eh = encrypt_order_data(wfiid, skey, svalue, vh.value.data, vh.value.meta);
                sdh{skey}{svalue} = {
                    "workflow_instanceid": wfiid,
                    "skey": skey,
                } + eh{"svalue", "data", "iv", "mac", "meta", "miv", "mmac"};
            }
        }

        AbstractTable sensitive_order_data = get_sql_table_system(omqp, "sensitive_order_data");
        AbstractTable sensitive_order_data_keys = get_sql_table_system(omqp, "sensitive_order_data_keys");

        # now commit the changes to the DB in a single restartable transaction
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                foreach hash<auto> sh in (sinfo.pairIterator()) {
                    string skey = sh.key;
                    foreach hash<auto> vh in (sh.value.pairIterator()) {
                        string svalue = vh.key;

                        hash<auto> tsdh = sdh{skey}{svalue};
                        # save sensitive data to DB
                        sensitive_order_data.upsert(tsdh);

                        *hash aac = ac{skey}{svalue};
                        if (aac.add || aac.del) {
                            if (aac.add)
                                map sensitive_order_data_keys.insert({
                                    "workflow_instanceid": wfiid,
                                    "skey": skey,
                                    "svalue": tsdh.svalue,
                                    "alias": $1,
                                }), aac.add;
                            if (aac.del)
                                map sensitive_order_data_keys.del({
                                    "workflow_instanceid": wfiid,
                                    "alias": $1,
                                }), aac.del;
                        }
                    }
                }

                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    replaceAndSave(string skey, string svalue, hash<auto> data, *softlist<softstring> aliases, *hash<auto> meta,
            softint wfiid) {
        checkKeys(skey, svalue, aliases);

        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        replaceAndSaveIntern(skey, svalue, data, aliases, meta, wfiid);
    }

    replaceAndSaveAlias(string alias, hash<auto> data, *hash<auto> meta, softint wfiid) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        *hash<auto> h = aliases{alias};
        if (!h)
            throw "INVALID-ALIAS", sprintf("alias %y for sensitive data is unknown; known aliases: %y", alias,
                keys aliases);

        replaceAndSaveIntern(h.skey, h.svalue, data, NOTHING, meta, wfiid);
    }

    private:internal replaceDataIntern(string skey, string svalue, hash<auto> data, *softlist<softstring> aliases,
            *hash<auto> meta, reference<hash> ac) {
        info{skey}{svalue} = data;

        if (meta)
            mh{skey}{svalue} = meta;
        else
            meta = mh{skey}{svalue};

        # process aliases
        *hash nah = map {$1: True}, aliases;
        # delete existing aliases
        foreach string alias in (keys rah{skey}{svalue}) {
            if (nah{alias}) {
                delete nah{alias};
                continue;
            }
            ac.del += alias;
        }
        ac.add += nah.keys();
    }

    private:internal replaceAndSaveIntern(string skey, string svalue, hash<auto> data, *softlist<softstring> aliases,
            *hash<auto> meta, softint wfiid) {
        # process aliases
        hash<auto> ac = {
            "del": (),
            "add": (),
        };

        replaceDataIntern(skey, svalue, data, aliases, meta, \ac);

        try {
            saveData(wfiid, skey, svalue, ac, meta);
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            rethrow;
        }
    }

    updateAndSave(string skey, string svalue, hash<auto> data, *softlist<softstring> aliases, *hash<auto> meta,
            softint wfiid) {
        checkKeys(skey, svalue, aliases);
        # atomically update the data and save to DB
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        updateAndSaveIntern(skey, svalue, data, aliases, meta, wfiid);
    }

    updateAndSaveAlias(string alias, hash<auto> data, *hash<auto> meta, softint wfiid) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        *hash<auto> h = aliases{alias};
        if (!h)
            throw "INVALID-ALIAS", sprintf("alias %y for sensitive data is unknown; known aliases: %y", alias,
                keys aliases);

        updateAndSaveIntern(h.skey, h.svalue, data, NOTHING, meta, wfiid);
    }

    updatePathAndSave(string skey, string svalue, list<hash<DotInfo>> path, auto value, softint wfiid) {
        checkKeys(skey, svalue, aliases);
        # atomically update the data and save to DB
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        updatePathAndSaveIntern(skey, svalue, path, value, wfiid);
    }

    updatePathAndSaveAlias(string alias, list<hash<DotInfo>> path, auto value, softint wfiid) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        *hash<auto> h = aliases{alias};
        if (!h)
            throw "INVALID-ALIAS", sprintf("alias %y for sensitive data is unknown; known aliases: %y", alias,
                keys aliases);

        updatePathAndSaveIntern(h.skey, h.svalue, path, value, wfiid);
    }

    private:internal updateAndSaveIntern(string skey, string svalue, hash<auto> data, *softlist<softstring> aliases,
            *hash<auto> meta, softint wfiid) {
        # update data
        info{skey}{svalue} += data;

        if (meta)
            mh{skey}{svalue} = meta;
        else
            meta = mh{skey}{svalue};

        # process aliases: add new aliases
        hash<auto> ac.add = map $1, aliases, !rah{skey}{svalue}{$1};

        try {
            saveData(wfiid, skey, svalue, ac, meta);
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            rethrow;
        }
    }

    private:internal updatePathAndSaveIntern(string skey, string svalue, list<hash<DotInfo>> path, auto value,
            softint wfiid) {
        # update data
        info{skey}{svalue} = _priv_update_hash_dot_value(info{skey}{svalue}, path, value);

        try {
            saveData(wfiid, skey, svalue, NOTHING, mh{skey}{svalue});
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            rethrow;
        }
    }

    bool deleteAndSave(string skey, string svalue, softint wfiid) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        # ignore deletion requests for non-existent data
        if (!info{skey}{svalue}) {
            return False;
        }

        try {
            deleteData(wfiid, skey, svalue);
            return True;
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            rethrow;
        }
    }

    bool deleteAndSave(string skey, string svalue, softlist<softstring> keysv, softint wfiid) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        # ignore deletion requests for non-existent data
        if (!info{skey}{svalue}{keysv})
            return False;

        delete info{skey}{svalue}{keysv};

        try {
            if (info{skey}{svalue})
                saveData(wfiid, skey, svalue);
            else
                deleteData(wfiid, skey, svalue);
            return True;
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            rethrow;
        }
    }

    # 2017-12-11 DN: without this method, calls to base class get() with no args fail sometimes
    # it looks like there is an inconsistency in Qore
    auto get() {
        return info;
    }

    auto get(string skey, string svalue, auto field) {
        if (!elements field)
            return info{skey}{svalue};

        if (field.typeCode() == NT_LIST && elements field == 1)
            field = field[0];

        bool lck = !l.lockOwner();
        if (lck) l.readLock();
        on_exit if (lck) l.readUnlock();

        return info{skey}{svalue}{field};
    }

    hash<auto> getAlias(string alias, auto field) {
        bool lck = !l.lockOwner();
        if (lck) l.readLock();
        on_exit if (lck) l.readUnlock();

        *hash<auto> h = aliases{alias};
        if (!h)
            throw "INVALID-ALIAS", sprintf("alias %y for sensitive data is unknown; known aliases: %y", alias,
                keys aliases);

        return {
            "skey": h.skey,
            "svalue": h.svalue,
            "value": get(h.skey, h.svalue, field),
        };
    }

    hash<auto> getMetadata(string skey, string svalue) {
        bool lck = !l.lockOwner();
        if (lck) l.readLock();
        on_exit if (lck) l.readUnlock();

        return mh{skey}{svalue} ?? {};
    }

    hash<auto> getMetadataAlias(string alias) {
        bool lck = !l.lockOwner();
        if (lck) l.readLock();
        on_exit if (lck) l.readUnlock();

        *hash<auto> h = aliases{alias};
        if (!h)
            throw "INVALID-ALIAS", sprintf("alias %y for sensitive data is unknown; known aliases: %y", alias,
                keys aliases);

        return {
            "skey": h.skey,
            "svalue": h.svalue,
            "value": mh{h.skey}{h.svalue},
        };
    }

    hash<auto> getAliases() {
        bool lck = !l.lockOwner();
        if (lck) l.readLock();
        on_exit if (lck) l.readUnlock();

        return aliases ?? {};
    }

    hash<auto> getKeyValues() {
        bool lck = !l.lockOwner();
        if (lck) l.readLock();
        on_exit if (lck) l.readUnlock();

        return map {$1.key: $1.value.keys()}, info.pairIterator();
    }

    # must be already in the write lock
    private:internal deleteData(softint wfiid, string skey, string svalue) {
        # get aliases before deleting data
        *list<string> al = keys rah{skey}{svalue};

        # remove sensitive data
        map (remove aliases.$1), al;
        remove rah{skey}{svalue};
        remove info{skey}{svalue};
        remove mh{skey}{svalue};
        if (!info{skey}) {
            remove info{skey};
            remove rah{skey};
            remove mh{skey};
        }

        # encrypt and encode sensitive value
        svalue = Qorus.encodeEncryptSensitiveValue(svalue);

        # delete sensitive data from the DB
        hash<auto> sdh = {
            "workflow_instanceid": wfiid,
            "skey": skey,
            "svalue": svalue,
        };

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # delete aliases first for referential integrity
                if (al) {
                    hash<auto> asdh = {
                        "workflow_instanceid": wfiid,
                        "alias": op_in(al),
                    };

                    get_sql_table_system(omqp, "sensitive_order_data_keys").del(asdh);
                }

                get_sql_table_system(omqp, "sensitive_order_data").del(sdh);
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
    }

    # must be called within the lock!
    private:internal saveData(softint wfiid, string skey, string svalue, *hash<auto> ac, *hash<auto> meta) {
        # serialize and encrypt data
        hash<auto> eh = encrypt_order_data(wfiid, skey, svalue, info{skey}{svalue}, meta);

        hash<auto> sdh = {
            "workflow_instanceid": wfiid,
            "skey": skey,
        } + eh{"svalue", "data", "iv", "mac", "meta", "miv", "mmac"};

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # save sensitive data to DB
                get_sql_table_system(omqp, "sensitive_order_data").upsert(sdh);

                if (ac.add || ac.del) {
                    AbstractTable t = get_sql_table_system(omqp, "sensitive_order_data_keys");
                    if (ac.add)
                        map t.insert(("workflow_instanceid": wfiid, "skey": skey, "svalue": eh.svalue, "alias": $1)), ac.add;
                    if (ac.del)
                        map t.del(("workflow_instanceid": wfiid, "alias": $1)), ac.del;
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

        if (ac.add || ac.del)
            updateAliases(skey, svalue, ac);
    }

    private:internal updateAliases(string skey, string svalue, hash<auto> ac) {
        if (ac.add) {
            map rah{skey}{svalue}.$1 = True, ac.add;
            map aliases{$1} = {"skey": skey, "svalue": svalue}, ac.add;
        }
        if (ac.del) {
            map remove rah{skey}{svalue}.$1, ac.del;
            if (!rah{skey}{svalue}) {
                remove rah{skey}{svalue};
                if (!rah{skey})
                    remove rah{skey};
            }
            map remove aliases.$1, ac.del;
        }
    }

    # note: keys are not sensitive data themselves and therefore can be logged, but values are
    static checkKeys(string skey, string svalue, *softlist<auto> aliases) {
        if (skey.empty())
            throw "SENSITIVE-DATA-ERROR", "sensitive data key is empty";
        if (skey.size() > SQLSensitiveKeyLen)
            throw "SENSITIVE-DATA-ERROR", sprintf("sensitive value key %y has length %d which exceeds the maximum "
                "length %d", skey, skey.size(), SQLSensitiveKeyLen);
        if (svalue.empty())
            throw "SENSITIVE-DATA-ERROR", sprintf("sensitive data value for key %y is empty", skey);
        if (svalue.size() > SQLSensitiveValueLen)
            throw "SENSITIVE-DATA-ERROR", sprintf("sensitive value key %y value has length %d which exceeds the "
                "maximum length %d", skey, svalue.size(), SQLSensitiveValueLen);
        foreach auto v in (aliases) {
            if (v.typeCode() != NT_STRING)
                throw "SENSITIVE-DATA-ERROR", sprintf("sensitive alias given is not type \"string\"; got type %y in "
                    "position %d instead", v.type(), $#);
            if (v.empty())
                throw "SENSITIVE-DATA-ERROR", sprintf("sensitive alias value for key %y is empty", skey);
            # alias values can be logged
            if (v.size() > SQLSensitiveValueLen)
                throw "SENSITIVE-DATA-ERROR", sprintf("sensitive alias value (%y) has length %d which exceeds the "
                    "maximum length %d", v, v.size(), SQLSensitiveValueLen);
        }
    }
}

class OMQ::StepData inherits private OMQ::InstanceData {
    # data is in the following format: stepid[ind] -> data hash
    initialize(hash<auto> stepdata) {
        info = stepdata;
    }

    replace(softstring stepid, int ind, hash<auto> data) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        info{stepid}[ind] = data;
    }

    # returns the original data before the update
    *hash<auto> replaceAndSave(softstring stepid, int ind, hash stepdata, softint wfiid, *string user) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        *hash<auto> orig = info{stepid}[ind];
        if (orig != stepdata) {
            qlog(LoggerLevel::INFO, "replacing step data for workflow_instanceid %d stepid %d[%d]: OLD: %y", wfiid,
                stepid, ind, orig);
            qlog(LoggerLevel::INFO, "replacing step data for workflow_instanceid %d stepid %d[%d]: NEW: %y", wfiid,
                stepid, ind, stepdata);

            info{stepid}[ind] = stepdata;

            try {
                saveData(wfiid, stepid, ind, user);
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
                rethrow;
            }
        }
        return orig;
    }

    update(softstring stepid, int ind, hash<auto> stepdata) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        info{stepid}[ind] += stepdata;
    }

    deleteKey(softstring stepid, int ind, softlist<softstring> keylist) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        delete info{stepid}[ind]{keylist};
    }

    auto get() {
        return info;
    }

    auto get(softstring stepid, int ind, auto field) {
        if (!exists field) {
            return info{stepid}[ind];
        }

        if (field.typeCode() == NT_LIST && elements field == 1) {
            field = field[0];
        }

        bool lck = !l.lockOwner();
        if (lck) l.readLock();
        on_exit if (lck) l.readUnlock();

        return info{stepid}[ind]{field};
    }

    updateAndSave(softstring stepid, int ind, hash<auto> new_data, softstring workflow_instanceid) {
        # atomically update the data and save to DB
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        # update data
        info{stepid}[ind] += new_data;

        try {
            saveData(workflow_instanceid, stepid, ind);
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            rethrow;
        }
    }

    updatePathAndSave(softstring stepid, int ind, string path, auto val, softstring workflow_instanceid) {
        # atomically update the data and save to DB
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        # update data
        info{stepid}[ind] = UserApi::updateHashDotValue(info{stepid}[ind], path, val);
        try {
            saveData(workflow_instanceid, stepid, ind);
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
            rethrow;
        }
    }

    deleteAndSave(softstring stepid, int ind, softlist<softstring> keylist, softstring workflow_instanceid) {
        bool lck = !l.writeLockOwner();
        if (lck) l.writeLock();
        on_exit if (lck) l.writeUnlock();

        auto val = info{stepid}[ind]{keylist};

        # only save if something was removed
        if (exists val) {
            try {
                saveData(workflow_instanceid, stepid, ind);
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::INFO, Util::get_exception_string(ex));
                rethrow;
            }
        }
    }

    static bool externalLock(StepData idata) {
        return InstanceData::externalLock(idata);
    }

    static externalUnlock(StepData idata) {
        return InstanceData::externalUnlock(idata);
    }

    # must be called within the lock!
    private:internal saveData(softint workflow_instanceid, softint stepid, int ind, *string user) {
        # save dynamic data to DB
        string str = serialize_qorus_data(info{stepid}[ind]);

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                sqlif.stepInstanceDataSaveData(str, workflow_instanceid, stepid, ind, user);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }
    }
}