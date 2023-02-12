# -*- mode: qore; indent-tabs-mode: nil -*-
# @file QorusMapManagerBase.qc provides an API for Qorus metadata

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args

class OMQ::QorusMapManagerBase {
    private {
        # this will hold the map data used by omqmap
        OmqMap omqmap();

        # value map value cache
        hash m_vmapCache;

        # type cache
        DataProviderTypeCache type_cache;
    }

    int getWorkflowId(string name, *string version) {
        *hash wf = rLookupWorkflow(name);
        if (!wf)
            throw "WORKFLOW-ERROR", sprintf("workflow %n does not exist", name);

        if (!exists version || version.empty())
            return int(wf.(wf.lastversion).workflowid);

        if (!wf{version})
            throw "WORKFLOW-ERROR", sprintf("workflow %n/%n does not exist", name, version);

        return int(wf{version}.workflowid);
    }

    #! Returns the path for the given type if it exists or @ref NOTHING if not
    /** @param path the path for the type which will be normalized

        @return the path for the given type if it exists or @ref NOTHING if not
    */
    *AbstractDataProviderType lookupType(string path) {
        # normalize the type path and add the leading slash if necessary
        return lookupTypeImpl(QorusDataProviderTypeHelper::normalizeTypePath(path));
    }

    #! Returns the path for the given type if it exists or an exception is thrown if not
    /** @param path the path for the type which will be normalized

        @return the path for the given type if it exists or an exception is thrown if not

        @throw PROVIDER-ERROR the given data provider type path is unknown
    */
    AbstractDataProviderType lookupTypeEx(string path) {
        *AbstractDataProviderType type = lookupType(path);
        if (!type) {
            throw "PROVIDER-ERROR", sprintf("type path %y is unknown", path);
        }
        return type;
    }

    #! Returns information about the latest version of the given class
    /** @throw CLASS-ERROR if the class doesn't exist
    */
    hash<auto> rLookupLatestClass(string name) {
        return omqmap.classmap{classId(name)};
    }

    auto getPipelineConfigItemValue(string pipeline_name, string name, *hash<auto> local_context,
            bool expand_complex_values = True) {
        *hash<auto> pipeline = lookupPipeline(pipeline_name);
        if (!pipeline) {
            throw "PIPELINE-ERROR", sprintf("data pipeline %y does not exist", pipeline_name);
        }
        *hash<auto> config_info = pipeline.config{name};
        if (!config_info) {
            throw "CONFIG-ITEM-ERROR", sprintf("data pipeline %y does not have any config item %y; known config "
                "items: %y", pipeline_name, name, keys pipeline.config);
        }

        return getPipelineConfigItemValueIntern(pipeline_name, name, config_info, local_context, expand_complex_values);
    }

    hash<auto> getPipelineConfigItemHash(string pipeline_name, *hash<auto> local_context) {
        *hash<auto> pipeline = lookupPipeline(pipeline_name);
        if (!pipeline) {
            throw "PIPELINE-ERROR", sprintf("data pipeline %y does not exist", pipeline_name);
        }

        return (map {$1.key: getPipelineConfigItemValueIntern(pipeline_name, $1.key, $1.value, local_context)},
            pipeline.config.pairIterator()) ?? {};
    }

    private auto getPipelineConfigItemValueIntern(string pipeline_name, string name, hash<auto> config_info,
            *hash<auto> local_context, bool expand_complex_values = True) {
        bool is_set;
        *string level;
        auto value = findConfigItemValue("pipeline", pipeline_name, name, config_info, \level, \is_set);
        if (!config_info.allowed_values) {
            value = UserApi::expandTemplatedValue(value, local_context, expand_complex_values);
        }
        if (is_set) {
            return value;
        }
        throw "CONFIG-ITEM-ERROR", sprintf("config item %y has neither a value nor a default value", name);
    }

    private getWorkflowStepInfoUnlocked(reference<hash<auto>> h) {
        # add step info to step hash
        # issue #3599: ensure NOTHING is not added to the stepinfo list
        h.stepinfo = (select (map lookupStepIntern($1, True), keys h.steps), $1) ?? ();
        h.wffuncs = ();
        addFuncInfoIntern("onetimeinit", \h.wffuncs, h.onetimeinit_func_instanceid);
        addFuncInfoIntern("errorfunction", \h.wffuncs, h.errorfunction_instanceid);
        addFuncInfoIntern("attachfunction", \h.wffuncs, h.attach_func_instanceid);
        addFuncInfoIntern("detachfunction", \h.wffuncs, h.detach_func_instanceid);
        addFuncInfoIntern("errorhandlerfunction", \h.wffuncs, h.errhandler_func_instanceid);
    }

    private *hash<auto> lookupStepIntern(softstring stepid, *softbool verbose) {
        *hash<auto> h += omqmap.stepmap{stepid};
        if (!h) {
            return;
        }
        h = {"stepid": stepid.toInt()} + h;
        if (verbose) {
            if (h.stepfunction_instanceid) {
                h.sfname = omqmap.functionmap.(h.stepfunction_instanceid).name;
                if (!h.sfname) {
                    throw "INVALID-STEP",
                        sprintf("cannot lookup step %s v%s (%d) because its primary step function is not cached; try resetting the function cache with 'ocmd omq.system.service.omqmap.reload functions' and try again",
                            h.name, h.version, stepid);
                }
                if (h.validationfunction_instanceid) {
                    h.vfname = omqmap.functionmap.(h.validationfunction_instanceid).name;
                }
                if (h.endfunction_instanceid) {
                    h.efname = omqmap.functionmap.(h.endfunction_instanceid).name;
                }
                if (h.arrayfunction_instanceid) {
                    h.afname = omqmap.functionmap.(h.arrayfunction_instanceid).name;
                }
            } else if (h.step_classid) {
                h.classname = omqmap.classmap{h.step_classid}.name;
                h.language = omqmap.classmap{h.step_classid}.language;
                if (!h.classname) {
                    throw "INVALID-STEP",
                        sprintf("cannot lookup step %s v%s (%d) because its step class code is not cached; try resetting the class cache with 'ocmd omq.system.service.omqmap.reload classes' and try again",
                            h.name, h.version, stepid);
                }
            }
        }
        return h;
    }

    private addFuncInfoIntern(string name, reference<list<auto>> l, *softstring id) {
        if (!id)
            return;
        *hash<auto> h = omqmap.functionmap{id};
        if (!h)
            return;
        l += ("type": name) + h;
    }

    # always called in either the read or write lock; reads in the entire value map
    private *hash<auto> getVMapIntern(softint id) {
        *list<auto> rows;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                AbstractTable value_map_values = Qorus.dsmanager.getOmqTable("value_map_values");
                rows = value_map_values.selectRows(("where": ("value_map_id": id)));
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

        # ensure that only deserialized data is stored in the cache
        return map {$1.keyname: ("value": deserialize_qorus_data($1.value), "enabled": boolean($1.enabled))}, rows;
    }

    private auto getVMapValueUnlockedIntern(string id, string key) {
        # we have to check the cache again
        if (!m_vmapCache{id}.hasKey(key) && !omqmap.vmmap{id}.full) {
            # cache entire map if it's below the size threshold
            if (omqmap.vmmap{id}.mapsize <= Qorus.options.get("vmaps-size-threshold")) {
                m_vmapCache{id} = getVMapIntern(id);
                omqmap.vmmap{id}.full = True;
            } else {
                # cache a single value if possible
                *hash row;
                QorusRestartableTransaction trans();
                while (True) {
                    try {
                        on_error omqp.rollback();

                        SqlUtil::AbstractTable t = Qorus.dsmanager.getOmqTable("value_map_values");
                        row = t.selectRow(("columns": ("value", "enabled"), "where": ("value_map_id": id.toInt(), "keyname": key)));
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

                # if the value is not in the map, then cache the missed value
                if (!row) {
                    m_vmapCache{id}{key} = NOTHING;
                    ++m_vmapCache{id}.miss;
                } else {
                    # if we have cached all values, then mark the value map as complete
                    if (++omqmap.vmmap{id}.cached == omqmap.vmmap{id}.mapsize)
                        omqmap.vmmap{id}.full = True;
                    m_vmapCache{id}{key} = row;
                    m_vmapCache{id}{key}.value = deserialize_qorus_data(row.value);
                }
            }
        }
        # make sure to return the value in the same lock
        return doVMapValue(id, key);
    }

    # must be called locked after the value map has been loaded
    private auto doVMapValue(softstring id, string key) {
        if (exists m_vmapCache{id}{key}.value
            && m_vmapCache{id}{key}.enabled) {
            return m_vmapCache{id}{key}.value;
        } else if ((!exists m_vmapCache{id}{key}.value || !m_vmapCache{id}{key}.enabled)
                    && omqmap.vmmap{id}.throws_exception) {
            throw "VALUE-MAP-ERROR", sprintf("value map '%s' does not contain a value for key '%s'",
                omqmap.vmmap{id}.name, key);
        }
    }

    abstract *hash<auto> rLookupWorkflow(string name);

    #! Returns the path for the given type if it exists or @ref NOTHING if not
    /** @param path the normalized path to the type with a leading \c "/"

        @return the path for the given type if it exists or @ref NOTHING if not
    */
    private abstract *AbstractDataProviderType lookupTypeImpl(string path);

    #! Returns the latest class ID for the given class
    /** @throw CLASS-ERROR if the class doesn't exist
    */
    abstract softint classId(string name, *string version);

    #! finds and returns the value of a config item
    abstract auto findConfigItemValue(string interface_type, auto interface_id, string name, hash config_item_info,
        reference<*string> level, reference<bool> is_set, *int workflow_id);

    #! looks up pipeline info from the name
    abstract *hash<auto> lookupPipeline(string name);
}