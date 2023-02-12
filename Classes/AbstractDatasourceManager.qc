# -*- mode: qore; indent-tabs-mode: nil -*-
# @file AbstractDatasourceManager.qc provides an API for datasource and SQL objects

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

#! this class is used to keep and handle datasources
/** It contains functionality for:
    - SQL cache (UserApi::getSqlTable())
    - obtaining QdspClient instances

    Monitoring logic is implemented in the Connections class
 */
class OMQ::AbstractDatasourceManager {
    private {
        hash<auto> db_cache;

        # issue #2833: must not re-issue datasource pool client objects for crashed qdsp processes
        *hash<string, bool> dspAbortMap;
    }

    AbstractDataProvider getDataProvider(string name) {
        return new DbDataProvider(getPool(name, False));
    }

    QdspClient getPool(string name, bool register_dependency = True, bool extern = True) {
        ensure_create_tld();
        if (!extern && name == "omq")
            return omqp;

        if (tld.dspNameCache{name} && !dspAbortMap{name}) {
            #QDBG_LOG("AbstractDatasourceManager::getPool(%s) returning TLD obj: %y", name, tld.dspNameCache{name}.getConfigHash());
            return tld.dspNameCache{name};
        }

        QdspClient dsp = getPoolImpl(name, register_dependency, extern);

        remove dspAbortMap{name};

        *hash<auto> cxh = UserApi::getUserContextInfo();
        if (cxh && (cxh.type == "job" || cxh.type == "workflow")) {
            setThreadLocalDsp(name, dsp);
        }

        return dsp;
    }

    datasourcePoolProcessAborted(string name, bool restarted, date abort_timestamp) {
        QDBG_LOG("AbstractDatasourceManager::datasourcePoolProcessAborted() handling qdsp %y: restarted: %y abort timestamp: %y", name, restarted, abort_timestamp);
        if (!restarted) {
            dspAbortMap{name} = True;
        }
        datasourcePoolProcessAbortedImpl(name, restarted, abort_timestamp);
    }

    # returns a string description of the datasource without the connection password
    string getDatasourceDescription(string datasource) {
        return getDatasourceDescriptionImpl(datasource);
    }

    *QdspClient getPoolUnlocked(string datasource) {
        return getPoolUnlockedImpl(datasource);
    }

    # returns a string description of the datasource without the connection password
    abstract string getDatasourceDescriptionImpl(string datasource);

    abstract QdspClient getPoolImpl(string name, bool register_dependency = True, bool extern = True);

    abstract *QdspClient getPoolUnlockedImpl(string datasource);

    static staticPoolCleanup(hash h) {
        QDBG_ASSERT(ensure_tld());
        tld.dspNameCache{h.name} = NOTHING;
        tld.dspHashCache{h.hash} = NOTHING;
    }

    string getDatasourceName(QdspClient dsp) {
        return dsp.getServerName();
    }

    private AbstractTable getCacheTable(string datasource, string type, string name, bool register_dependency, bool extern) {
        return getCreateTableIntern(datasource, type, name, register_dependency, extern);
    }

    # only called while holding the write lock and with a block on the datasource, if any
    private invalidateObjectIntern(*string datasource, *string type, *string name) {
        if (!datasource) {
            if (!db_cache) {
                db_cache = {};
            } else {
                # reset the entire cache except for the "omq" datasource
                db_cache = {
                    "omq": db_cache.omq,
                };
            }
        } else {
            if (datasource == "omq")
                throw "SYSTEM-DATASOURCE-ERROR", "cannot reset cached objects for the system datasource; the system must be restarted if the system datasource needs to be reset";
            if (!type) {
                # remove all cached SQL objects for the datasource
                remove db_cache{datasource};
            } else if (!name) {
                # remove all objects in the cache of the given type
                remove db_cache{datasource}{type};
            } else {
                # ensure that objects are cleared using a case-insensitive version of the name
                name = name.lwr();
                # remove the given object from the cache if present
                remove db_cache{datasource}{type}{name};
            }
        }
    }

    AbstractTable getSqlTable(string datasource, string name, bool register_dependency = True) {
        return getSqlTableIntern(datasource, name, register_dependency);
    }

    AbstractTable getSqlTable(QdspClient dsp, string name, bool register_dependency = True) {
        try {
            return getSqlTableIntern(getDatasourceName(dsp), name, register_dependency);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-DATASOURCE") {
                # if the datasource is cached, then create a temporary object
                # based on the cached pool object and return it without caching it
                if (tld.dspHashCache{dsp.uniqueHash()}) {
                    Table table(dsp, name);
                    return table.getTable();
                }
            }
            rethrow;
        }
    }

    # can only be called internally or by system services
    AbstractTable getOmqTable(string name) {
        return getSqlTableIntern("omq", name, False, False);
    }

    # can only be called internally or by system services
    AbstractTable getSqlTableSystem(string datasource, string name, bool register_dependency = True) {
        return getSqlTableIntern(datasource, name, False, False);
    }

    AbstractTable getSqlTableSystem(QdspClient dsp, string name, bool register_dependency = True) {
        return self.getSqlTableIntern(getDatasourceName(dsp), name, False, False);
    }

    # clears the table cache with the given arguments from an external notification
    clearTableCacheExtern(*string datasource, *string name) {
        clearTableCacheIntern(datasource, name);
    }

    # clears the table cache with the given arguments from an internal request and notifies all other
    # cluster servers that the object has been cleared
    clearTableCache(*string datasource, *string name) {
        # first clear the internal cache entry
        clearTableCacheIntern(datasource, name);
        # notify all other cluster server to clear the table cache with the given arguments
        Qorus.getMaster().broadcastToAllInterfaces("dsmanager", "clearTableCacheExtern", (datasource, name));
    }

    clearTableCache(*QdspClient dsp, *string name) {
        return self.clearTableCache((dsp ? getDatasourceName(dsp) : NOTHING), name);
    }

    private setThreadLocalDsp(string name, AbstractDatasource dsp) {
        if (name != "omq") {
            ensure_create_tld();
            string hstr = dsp.uniqueHash();
            tld.dspNameCache{name} = dsp;
            tld.dspHashCache{hstr} = name;
            set_thread_resource(\AbstractDatasourceManager::staticPoolCleanup(), ("name": name, "hash": hstr));
            #log(LoggerLevel::DEBUG, "DEBUG: setThreadLocalDsp() %y setting TLD+resource for pool: %s", name, dsp.uniqueHash());
        }
    }

    private *AbstractTable getCacheTableIntern(string datasource, string type, string name) {
        if (db_cache{datasource}{type}{name}) {
            bool useCache = True;
            if (exists tld.dspNameCache{datasource}) {
                # be careful, resets could cause a dsp change in the cache!
                useCache = tld.dspNameCache{datasource} == db_cache{datasource}{type}{name}.table.getDatasource();

                #QDBG_LOG("AbstractDatasourceManager::getCacheTableIntern() datasource: %y type: %y name: %y "
                #    useCache: %y tld{%y}: %y table ds: %y", datasource, type, name, useCache, datasource,
                #    tld.dspNameCache{datasource}.uniqueHash(),
                #    db_cache{datasource}{type}{name}.table.getDatasource().uniqueHash());
            }
            if (useCache) {
                # issue #3313: must set TLD for table here if not set
                if (!tld.dspNameCache{datasource}) {
                    setThreadLocalDsp(datasource, db_cache{datasource}{type}{name}.table.getDatasource());
                }
                ++db_cache{datasource}{type}{name}.count;
                return db_cache{datasource}{type}{name}.table;
            }
        }
%ifdef QorusDebugInternals
        else {
            #QDBG_LOG("AbstractDatasourceManager::getCacheTableIntern() datasource: %y type: %y name: %y NOT CACHED", datasource, type, name);
        }
%endif
    }

    private AbstractTable getSqlTableIntern(string datasource, string name, bool register_dependency = True, bool extern = True) {
        # ensure that objects stored/looked-up in a case-insensitive manner
        return getCacheTable(datasource, "tables", name.lwr(), register_dependency, extern);
    }

    private abstract clearTableCacheIntern(*string datasource, *string name);

    private abstract AbstractTable getCreateTableIntern(string datasource, string type, string name, bool register_dependency, bool extern);

    private abstract datasourcePoolProcessAbortedImpl(string name, bool restarted, date abort_timestamp);
}

# get cached table object if present, otherwise it creates one from scratch.
SqlUtil::AbstractTable sub get_sql_table_system(string datasource, string table_name) {
    return Qorus.dsmanager.getSqlTableSystem(datasource, table_name);
}

# get cached table object if present, otherwise it creates one from scratch.
SqlUtil::AbstractTable sub get_sql_table_system(AbstractDatasource datasource, string table_name) {
    return Qorus.dsmanager.getSqlTableSystem(datasource, table_name);
}

SqlUtil::AbstractTable sub get_sql_table_system_trans(string ds, string table) {
    return get_sql_table_system_trans(Qorus.dsmanager.getPool(ds, False, False), table);
}

SqlUtil::AbstractTable sub get_sql_table_system_trans(AbstractDatasource dsp, string table) {
    QorusRestartableTransaction trans();
    while (True) {
        try {
            on_error dsp.rollback();

            return get_sql_table_system(dsp, table);
        } catch (hash<ExceptionInfo> ex) {
            # restart the transaction if necessary
            if (trans.restartTransaction(ex))
                continue;
            rethrow;
        }
    }
}
