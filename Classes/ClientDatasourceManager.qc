# -*- mode: qore; indent-tabs-mode: nil -*-
# @file ClientDatasourceManager.qc provides a cluster client datasource manager

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

class OMQ::ClientDatasourceManager inherits OMQ::AbstractDatasourceManager {
    private {
        RWLock rwl();

        # cached datasource pool client objects
        hash<string, QdspClient> defaults();

        # block hash
        hash<string, bool> bh();

        # waiting hash
        hash<string, int> wh();

        # all waiting
        int waiting_all = 0;

        # table block hash
        hash<string, bool> tbh();

        # table waiting hash
        hash<string, int> twh();

        # block condition variable
        Condition cond();
    }

    constructor() {
        # setup datasource acquisition from SqlUtil with deserialized AbstractTable objects
        SqlUtil::sqlutil_register_ds_deserializer(\deserializeTableDs());
    }

    AbstractDataProvider getDataProvider(string name, *int mapperid) {
        on_success if (mapperid) Qorus.dsmanager_client.doMapperDependency(name, mapperid);
        return AbstractDatasourceManager::getDataProvider(name);
    }

    QdspClient getPoolBlocked(string name, bool register_dependency = True, bool extern = True) {
        ensure_create_tld();
        if (!extern && name == "omq")
            return omqp;

        if (tld.dspNameCache{name})
            return tld.dspNameCache{name};

        QdspClient dsp = getPoolBlockedIntern(name, register_dependency, extern);

        *hash<auto> cxh = UserApi::getUserContextInfo();
        if (cxh && (cxh.type == "job" || cxh.type == "workflow")) {
            string hstr = dsp.uniqueHash();
            tld.dspNameCache{name} = dsp;
            tld.dspHashCache{hstr} = name;
            set_thread_resource(\AbstractDatasourceManager::staticPoolCleanup(), ("name": name, "hash": hstr));
        }

        return dsp;
    }

    /** @param type the type of object
        @param config this is the datasource name
    */
    AbstractDatasource deserializeTableDs(string type, string config) {
        QDBG_ASSERT(type == "DatasourcePool");
        return getPoolBlocked(config, False, False);
    }

    private AbstractTable getCreateTableIntern(string datasource, string type, string name, bool register_dependency, bool extern) {
        # check access to "omq"
        if (name == "omq" && extern) {
            throw "DATASOURCE-ERROR", sprintf("cannot acquire a connection for %y: this is a private/system datasource", name);
        }

        # we have to get the table outside the lock
        blockTable(datasource, name);
        on_exit unblockTable(datasource, name);

        *AbstractTable t = getCacheTableIntern(datasource, type, name);
        if (t) {
            return t;
        }

        # we have to get the table outside the lock
        AbstractTable obj;
        try {
            # get the table from qorus-core
            QDBG_LOG("retrieving table \"%s.%s\" from qorus-core: reg: %y extern: %y", datasource, name, register_dependency, extern);
            binary bin = Qorus.dsmanager_client.getSerializedTable(datasource, type, name, register_dependency, extern);
            obj = Serializable::deserialize(bin);
            QDBG_LOG("got table %y from qorus-core", obj.getSqlName());
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("ex: %s", get_exception_string(ex));
            if (ex.err == "DATASOURCE-ERROR")
                rethrow;
            # rethrow exception and add datasource information
            rethrow ex.err, sprintf("datasource %y (%s): %s", datasource, getDatasourceDescription(datasource), ex.desc);
        }

        if (!exists db_cache{datasource}{type}{name}) {
            db_cache{datasource}{type}{name} = {
                "count": 1,
                "created": now_us(),
                "table": obj,
            };
        }
        return obj;
    }

    private blockTable(string datasource, string name) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        while (True) {
            if (waitBlock(datasource)) {
                continue;
            }

            # check for a table block
            if (!tbh{name}) {
                # exit the block only when both conditions are true at the same time
                break;
            }

            while (tbh{name}) {
                ++twh{name};
                cond.wait(rwl);
                --twh{name};
            }
        }

        if (wh.hasKey(datasource) && !wh{datasource}) {
            delete wh{datasource};
        }

        if (twh.hasKey(name) && !twh{name}) {
            delete twh{name};
        }

        bh{datasource} = True;
        tbh{name} = True;

        #QDBG_LOG("ClientDatasourceManager::blockTable() datasource: %y table: %y stack: %N", datasource, name, get_stack());
    }

    private unblockTable(string datasource, string name) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (wh{datasource} || waiting_all || twh{name}) {
            cond.broadcast();
        }

        delete bh{datasource};
        delete tbh{name};
    }

    private waitBlock() {
        while (bh) {
            ++waiting_all;
            cond.wait(rwl);
            --waiting_all;
        }
    }

    private bool waitBlock(string name) {
        if (!bh{name}) {
            return False;
        }

        while (bh{name}) {
            ++wh{name};
            cond.wait(rwl);
            --wh{name};
        }

        if (wh.hasKey(name) && !wh{name}) {
            delete wh{name};
        }

        return True;
    }

    private releaseBlock(string name) {
        delete bh{name};
        if (wh{name} || waiting_all)
            cond.broadcast();
    }

    private datasourcePoolProcessAbortedImpl(string name, bool restarted, date abort_timestamp) {
        # remove the given datasource pool
        if (!restarted) {
            reset(name);
        }
    }

    private QdspClient getPoolImpl(string name, bool register_dependency = True, bool extern = True) {
        # set a block on the given datasource
        {
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            waitBlock(name);

            if (defaults{name}) {
                QDBG_LOG("ClientDatasourceManager::getPoolImpl() returning existing client for %y", name);
                return defaults{name};
            }

            bh{name} = True;
        }

        on_exit {
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            releaseBlock(name);
        }

        if (name != "omq" || extern || register_dependency) {
            getConnectionInfo(name, register_dependency);
        }

        #QDBG_LOG("ClientDatasourceManager::getPoolImpl() retrieving %y; cached datasources: %y", name, keys defaults);

        Qorus.registerServer(qdsp_get_process_name(name));
        QdspClient dsp(Qorus, name);

        QDBG_LOG("ClientDatasourceManager::getPoolImpl() created a new client for %y", name);

        # while a datasource block is place, we can read and write to "defaults"
        # for that particular datasource without additional locking
        # insert in caches
        defaults{name} = dsp;

        return dsp;
    }

    private QdspClient getPoolBlockedIntern(string name, bool register_dependency = True, bool extern = True) {
        # while a datasource block is place, we can read and write to "defaults"
        # for that particular datasource without additional locking
        if (defaults{name})
            return defaults{name};

        if (name != "omq" || extern || register_dependency) {
            getConnectionInfo(name, register_dependency);
        }

        Qorus.registerServer(qdsp_get_process_name(name));
        QdspClient dsp(Qorus, name);

        # insert in caches
        defaults{name} = dsp;

        return dsp;
    }

    Datasource getShared(string name, bool register_dependency = True) {
        throw "DEPRECATED-ERROR", sprintf("shared datasources with autocommit enabled are deprecated and should not be used; use a dedicated datasource or (better) a datasource pool instead");
    }

    Datasource getDedicated(string name, bool register_dependency = True) {
        return new Datasource(getPoolImpl(name, register_dependency).getConfigHash());
    }

    private hash<auto> getConnectionInfo(string name, bool register_dependency = True) {
        return Qorus.dsmanager_client.getExternalConnectionInfo(name, register_dependency, qorus_get_source_hash());
    }

    # returns a string description of the datasource without the connection password
    string getDatasourceDescriptionImpl(string datasource) {
        return Qorus.dsmanager_client.getDatasourceDescriptionImpl(datasource);
    }

    hash<auto> getCacheInfo() {
        return Qorus.dsmanager_client.getCacheInfo();
    }

    *QdspClient getPoolUnlockedImpl(string datasource) {
        return defaults{datasource};
    }

    hash<auto> getInfo(string name, *hash<auto> opts) {
        return Qorus.dsmanager_client.getInfo(name, opts);
    }

    reload() {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        waitBlock();

        defaults = new hash<string, QdspClient>();
    }

    reset(string name) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        waitBlock(name);

        remove defaults{name};
    }

    private clearTableCacheIntern(*string datasource, *string name) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (exists datasource) {
            waitBlock(datasource);
        }

        invalidateObjectIntern(datasource, "tables", name);
    }
}
