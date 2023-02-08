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

/** @page rest_api_page_v4 Qorus REST API v4

    @tableofcontents

    @section rest_api_v4_overview Qorus REST API v4 Overview

    REST API v4 has the following differences from @ref rest_api_page_v3 "REST API v3":
    - added support for data providers and types:
      - @ref rest_api_v4_dataprovider
      - @ref rest_api_v4_remote_datasources__name__provider
      - @ref rest_api_v4_remote_qorus__name__provider
      - @ref rest_api_v4_remote_user__name__provider
    - added APIs for enabling and disabling data debugging in user and remote connections:
      - @ref rest_api_PUT_v4_remote_qorus__name__enableDebugData
      - @ref rest_api_PUT_v4_remote_qorus__name__disableDebugData
      - @ref rest_api_PUT_v4_remote_user__name__enableDebugData
      - @ref rest_api_PUT_v4_remote_user__name__disableDebugData
    - added an API for asynchronous workflow order execution:
      - @ref rest_api_POST_v4_workflows__id_or_name__execSynchronousAsync
*/

/** @REST /v4 (/v3)

    This URI path implements v4 of the Qorus REST API
*/
class V4RestClass inherits QorusRestClass {
    constructor() {
        addClass(new WorkflowRestClassV4());
        addClass(new GlobalOrderRestClassV4());
        addClass(new GlobalWorkflowExecRestClassV3());
        addClass(new ServiceRestClassV3());
        addClass(new JobRestClassV4());
        addClass(new SystemRestClassV4());
        addClass(new UsersRestClass());
        addClass(new RolesRestClass());
        addClass(new GroupsRestClass());
        addClass(new StepRestClassV3());
        addClass(new FunctionRestClass());
        addClass(new ClassRestClassV3());
        addClass(new ConstantRestClass());
        addClass(new DebugRestClass());
        addClass(new JobResultsRestClass());
        addClass(new LogsRestClass());
        addClass(new RemoteRestClassV4());
        addClass(new PermsRestClass());
        addClass(new ErrorsRestClassV3());
        addClass(new MappersRestClassV4());
        addClass(new MapperTypesRestClass());
        addClass(new AsyncQueuesRestClassV3());
        addClass(new ValueMapsRestClass());
        addClass(new ReleasesRestClass());
        addClass(new SyncEventTypesRestClass());
        addClass(new SlasRestClass());
        addClass(new DataProviderBaseRestClass());
        addClass(new LogoutRestClass());
        addClass(new RemoteDevelopment::RestClass());
    }

    string name() {
        return "v4";
    }

    /** @REST GET

        @par Description
        Returns the top-level members of this version of the REST API
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, keys class_hash);
    }
}

/** @REST /v4/jobs/{id_or_name} (/v3/jobs/{id_or_name})

    This REST API path provides actions and information related to specific jobs;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class JobDefinitionRestClassV4 inherits JobDefinitionRestClassV3 {
    constructor(hash<auto> jh) : JobDefinitionRestClassV3(jh) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (cx.hdr.method == "GET" && name == "persistent-state") {
            return new AttributeRestClass(retrievePersistentState());
        }
        return JobDefinitionRestClassV3::subClassImpl(name, cx, ah);
    }

    /** @REST GET

        @SCHEMA
        @summary Returns a hash of information about the current job

        @desc Returns a hash of information about the current job

        @return (hash JobDetailInfo): a hash of information about the current job
        - name (string): the name of the job
        - jobid (int): the job ID
        - description (*string): the description of the job (if any)
        - version (string): the version of the job
        - author (*string): the author of the job (if any)
        - sessionid (*int): If the job is currently active and running on a Qorus instance, then this attribute will \
          have a value, otherwise it will not be set
        - remote (bool): the remote state of the job; if \c True, the job will run remotely in a \
          @ref qjob "qjob" process; if \c False, it will run in @ref qorus-core "qorus-core"
        - manual_remote (bool): set if the \a manual value has been changed manually, in which \
          case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - open (bool): if the current workflow is open for processing now
        - run_skipped (bool): A boolean value telling the system if the job should be run immediately if the last \
          scheduled run was missed due to system downtime
        - enabled (bool): flag indicating if the job is enabled or not; disabled jobs cannot be activated
        - code (string): the source code for the job
        - class_based (bool): \c True means that the job is an extension of the \c QorusJob class, otherwise it is a \
          function-based job
        - class_name (*string): the name of the job class, if any
        - language (string): the programming language that the job's main code is implemented in
        - month (*string): the month value in a @ref job_schedule "job cron schedule"
        - day (*string): the day value in a @ref job_schedule "job cron schedule"
        - wday (*string): the weekday value in a @ref job_schedule "job cron schedule"
        - hour (*string): the hout value in a @ref job_schedule "job cron schedule"
        - minute (*string): the minute value in a @ref job_schedule "job cron schedule"
        - expiry_date (*date): the expiry date of the job, if any
        - last_executed (*date): the date-time value the job was last executed, if any
        - last_executed_job_instanceid (*int): the last job instance ID, if any
        - manually_updated (bool): flag set if the job schedule has been changed manually, in which case the manual \
          setting takes precendence over any new definitions loaded with @ref oload "oload"
        - created (date): the date/time the job was created
        - modified (date): the date/time the job was modified
        - source (*string): the complete path of the job source file when loaded
        - line (*int): the line offset of the job source code in the file
        - config_items (*list<hash ConfigItemDetailInfo>): list of config items attached directly to the job
          - name (string): the name of the configuration item
          - parent (*hash ConfigItemParentInfo): config item parent information
            - interface-type (string): the type of parent providing the config item
            - interface-name (string): the name of the parent providing the config item
            - interface-version (string): the version of the parent providing the config item
          - prefix (*string): the prefix of the configuration item
          - value (any): the value of the configuration item
          - description (string): the description of the configuration item
          - config_group (string): the group of the configuration item
          - type (string): the data type of the configuration item
          - sensitive (bool): if the value is sensitive or not
          - default_value (any): the default value of the configuration item
          - strictly_local (bool): if the configuration item is defined strictly on local level
          - allowed_values (*list<any>): the list of allowed values for the configuration item if defined
          - is_default_value_templated_string (bool): @ref True if the default value is a templated string that can \
            be later expanded
          - is_value_templated_string (bool): @ref True if the value is a templated string that can be later expanded
        - fsm_triggers (*hash[list<hash FsmTriggerInfo>] FsmTriggerSet): a hash keyed by \
          @ref finite_state_machines "finite state machine" name giving triggers for each flow
          - method (string): the string \c "run"
        - next (*date): the next automatic job execution time time, if any
        - schedule (*string): a string providing all 5 fields of the cron schedule, if any
        - mappers (*list<hash MapperInfo>): list of @ref mappers "mappers" associated with the job
        - vmaps (*list<hash VMapInfo>): a list of @ref value-maps "value maps" associated with the job
        - lib (*hash LibraryInfo): a hash of library information for the job
        - tags (*hash[any] UndefinedHash): any tags for the job
        - schedule (*string): the schedule for the job as a string
        - config (*hash[hash ConfigItemSummaryInfo] ConfigItemSummarySetInfo): a hash of configuration item info \
          keyed by config item name
        - groups (*list<hash GroupInfo>): a list of @ref rbacgroups "interface groups" that the job belongs to
        - offset (*string): the line offset of the job source code in the file
        - host (*string): the hostname of the machine where the job was loaded from
        - user (*string): the OS user who loaded the job
        - base_class_name (*string): the base class name of the job, if any
        - process (*hash ProcessExecInfo): present when \c remote is @ref True "True"
        - COMPLETE (*int): number of job results with status @ref OMQ::JS_Complete "COMPLETE"
        - IN-PROGRESS (*int): number of job results with status @ref OMQ::JS_InProgress "IN-PROGRESS"
        - ERROR (*int): number of job results with status @ref OMQ::JS_Error "ERROR"
        - CRASH (*int): number of job results with status @ref OMQ::JS_Crash "CRASH"
        - connections (*list<hash ConnectionInfo>): a list of connection objects that this job depends on
        - alerts (*list<hash AlertInfo>): a list of alerts raised against the job
        - db_active (bool): a boolean flag indicating the active status in the database
        - active (bool): the active status in the current Qorus instance
        - manual_active (bool): set if the \a active value has been changed manually, in which \
          case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - log_url (*string): the log URL (if any)
        - options (list<hash OptionInfoHash>): a list option information hashes
        - sched_type (string): the schedule type; one of \c "cron" (uses a @ref job_schedule "job cron schedule"), \
          or \c "recurring" ( uses a fixed repeat delay)
        - sched_txt (string): a string describing the schedule (ex: \c "minutes: 0, hours: 0, days: *, months: \
          *, wdays: *")
        - sla (*string): the name of the attached SLA, if any)
        - state (*hash): any job state data
        - persistent-state (*hash): any persistent job state data
        @ENDSCHEMA
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        jh += {
            "state": retrieveState(),
            "persistent-state": retrievePersistentState(),
        };

        return RestHandler::makeResponse(200, jh);
    }

    private *hash<auto> retrievePersistentState() {
        # get service state data, if any
        *string str;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                str = get_sql_table_system("omq", "job_persistent_state_data").selectRow({
                    "columns": "data",
                    "where": {
                        "jobid": jh.jobid,
                    },
                }).data;
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
        if (exists str) {
            return deserialize_qorus_data(str);
        }
    }

    /** @REST PUT action=setPersistentStateData

        @par Description
        Provides an API for externally updating persistent job state data

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c data: a hash of new persistent job state data or @ref nothing which will clear any data

        @par Return Value
        This API returns the new data or @ref nothing if the data is cleared

        @see
        - @ref OMQ::UserApi::Job::JobApi::savePersistentStateData()
    */
    hash<auto> putSetPersistentStateData(hash<auto> cx, *hash<auto> ah) {
        AbstractTable t = get_sql_table_system_trans("omq", "job_persistent_state_data");

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_success omqp.commit();
                on_error omqp.rollback();

                if (!exists ah.data) {
                    t.del({"jobid": jh.jobid});
                } else {
                    if (ah.data.typeCode() != NT_HASH)
                        throw "JOB-STATE-ERROR", sprintf("\"data\" argument is type %y (expecting %y)", ah.data.type(), Type::String);
                    string str = serialize_qorus_data(ah.data);
                    t.upsert({"jobid": jh.jobid, "data": str});
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

        return RestHandler::makeResponse(200, ah.data);
    }
}

/** @REST /v4/jobs (/v3/jobs)

    This REST API path provides actions and information related to Qorus jobs.
*/
class JobRestClassV4 inherits JobRestClassV3 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = JobRestClass::staticGetJobId(arg);
        *hash<auto> job = JobRestClassV2::staticGetJob(cx, ah, id, 4);
        if (!job) {
            return;
        }

        hash<auto> ji = Qorus.jobManager.getActiveInfo();
        JobRestClass::fixJob(\job, ji.(job.name), cx);

        return internGetJobDefinition(job);
    }

    private QorusRestClass internGetJobDefinition(hash<auto> job) {
        return new JobDefinitionRestClassV4(job);
    }
}

/** @REST /v4/mappers (/v3/mappers)

    This URI path provides actions and information related to system @ref mappers "mappers"
*/
class MappersRestClassV4 inherits MappersRestClass {
    private MapperRestClass internGetMapperRestClass(int mapperid) {
        hash<auto> mh = Qorus.mappers.getInfo(mapperid, True)
            + {"groups": Qorus.rbac.getMapperGroups(mapperid)};
        *string mctx = Qorus.qmm.lookupMapper(mapperid)."context";
        if (mctx) {
            # add mapper data context to mapper output if possible
            (string type, string name, *string version) = mctx.split(":");
            switch (type) {
                case "workflow": {
                    hash<auto> wfh;
                    if (version) {
                        wfh = Qorus.qmm.rLookupWorkflow(name, version);
                    } else {
                        *hash<auto> h = Qorus.qmm.rLookupWorkflow(name);
                        if (h) {
                            wfh = h{h.lastversion};
                        }
                    }
                    if (wfh.staticdata_type_path) {
                        string typename = sprintf("workflow %s v%s (%d) static data", name, wfh.version, wfh.workflowid);
                        mh.options."context".staticdata =
                            DataProviderTypeRestClass::doGetInfo(UserApi::getTypeFromPath(wfh.staticdata_type_path),
                                typename);
                    }
                    mh.options."context".info =
                        DataProviderTypeRestClass::doGetInfo(UserApi::getQorusType(
                            "qoretechnologies/qorus-api/workflows/context"), "workflow info context");
                    break;
                }
                case "service": {
                    mh.options."context".info =
                        DataProviderTypeRestClass::doGetInfo(UserApi::getQorusType(
                            "qoretechnologies/qorus-api/services/context"), "service info context");
                    break;
                }
                case "job": {
                    mh.options."context".info =
                        DataProviderTypeRestClass::doGetInfo(UserApi::getQorusType(
                            "qoretechnologies/qorus-api/jobs/context"), "job info context");
                    break;
                }
            }
        }
        return new MapperRestClass(mh);
    }
}

class DataProviderTypeRestHelper {
    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClass(name, type);
    }
}

/** @REST /v4/workflows/{id_or_name} (/v3/workflows/{id_or_name})

    This REST URI path provides actions and information about a particular workflow.
*/
class WorkflowDefinitionRestClassV4 inherits WorkflowDefinitionRestClassV3, DataProviderTypeRestHelper {
    constructor(hash<auto> wf) : WorkflowDefinitionRestClassV3(wf) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (name == "staticdata_type") {
            return doGetDataProviderTypeRestClass(sprintf("staticdata hash for workflow %s v%s (%d)", wf.name,
                    wf.version, wf.workflowid), wf.staticdata_type_path
                ? UserApi::getTypeFromPath(wf.staticdata_type_path)
                : AbstractDataProviderType::get("hash<auto>"));
        }

        return WorkflowDefinitionRestClassV3::subClassImpl(name, cx, ah);
    }

    /** @REST POST action=execSynchronousAsync

        @SCHEMA
        @summary Creates a new order for the current workflow and executes it synchronous mode.

        @desc Creates a new order for the current workflow and executes it synchronous mode in a background thread.  \
        The call returns as soon as the order instance has been created and returns the workflow_instanceid for the \
        new workflow order as well as the new execution ID. \
        \
        To ensure that a given workflow order is only created once for a given unique key value, make sure your \
        workflow defines @ref wf_keylist "order keys", and use one of the following options to guarantee the \
        uniqueness of the order: \
        - \c global_unique_key \
        - \c workflow_specific_unique_key \
        - \c workflow_unique_key

        @params
        - external_order_instanceid (*string): the external order instance ID for the workflow data; either this key \
          or \c staticdata is required
        - dynamicdata (*hash[any] UndefinedHash): the initial dynamic data for the order
        - global_unique_key (*hash[any] UndefinedHash): a hash giving one or more unique \
          @ref wf_keylist "order keys" for the order (across all workflows regardless of workflowid, name, or \
          version); if this key already exists for any order in the system, then the order creation will fail with a \
          \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and the value is the unique key \
          value; this value will also be created as an order key
        - orderkeys (*hash[any] UndefinedHash): a hash of @ref wf_keylist "order keys" for the order
        - parent_workflow_instanceid (*int): a loosely-coupled workflow that will be marked as the parent of this \
          workflow
        - priority (*int): the order priority (default @ref OMQ::DefaultOrderPriority) from 0 - 999; priority 0 is \
          the highest; 999 is the lowest
        - sensitive_data (*hash[hash[hash SensitiveDataInfo] SensitiveDataKeyInfo] SensitiveDataSetInfo): a hash of \
          sensitive data information for the \
          workflow; this key can only be used when submitting the data over a secure (encrypted) connection; the \
          keys are sensitive data key types, values are hashes keyed by sensitive data values
        - staticdata (hash[any] UndefinedHash): the static data for the order; either this key or \
          \c external_order_instanceid is required
        - workflow_specific_unique_key (*hash[any] UndefinedHash): a hash giving one or more unique \
          @ref wf_keylist "order keys" for the particular workflowid (which matches a unique name and workflow \
          version); if this key already exists for an order with the target workflowid, then the order creation will \
          fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and the value is the \
          unique key value; this value will also be created as an order key
        - workflow_unique_key (*hash[any] UndefinedHash): a hash giving one or more unique \
          @ref wf_keylist "order keys" for the particular workflow by name only (across all workflows with the same \
          name regardless of version); if this key already exists for a workflow order with the same name, then the \
          order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and \
          the value is the unique key value; this value will also be created as an order key

        @return (hash WorkflowOrderExecutionAsyncInfo): 201: describes the workflow order created
        - workflow_instanceid (int): the workflow instance ID of the order created
        - execid (int): the synchronous workflow execution instance ID

        @error (409): exception processing create order request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SHUTDOWN-IN-PROGRESS: cannot start new workflows because the system is
          shutting down
    */
    hash<auto> postExecSynchronousAsync(hash<auto> cx, *hash<auto> ah) {
        if (ah.options && ah.options.typeCode() != NT_HASH) {
            throw "PARAMETER-ERROR", sprintf("workflow options must be given in hash format (option=value), type "
                "given: %y", ah.options.type());
        }

        hash<auto> oh = ah.OrderData::DataKeysV1 + ("name": wf.name, "version": wf.version);

        if (oh.priority < 0) {
            oh.priority = 0;
        } else if (oh.priority > 999) {
            oh.priority = 999;
        }

        OrderData order(oh{"staticdata", "dynamicdata", "priority", "orderkeys", "external_order_instanceid",
            "parent_workflow_instanceid"});

        # set workflow name and version in order data
        order.setNameAndVersion(wf.name, wf.version);

        # workflow access is checked in Control::setupWorkflow()
        return RestHandler::makeResponse(201, Qorus.control.execSynchronousWorkflowAsync(cx, wf.workflowid, order,
            ah.options));
    }
}

/** @REST /v4/orders/{id} (/v3/orders/{id})

    This REST URI path provides actions and information about specific workflow orders.
*/
class WorkflowOrderInstanceRestClassV4 inherits WorkflowOrderInstanceRestClassV3, DataProviderTypeRestHelper {
    constructor(hash<auto> wf, int api_version = 4)
            : WorkflowOrderInstanceRestClassV3(WorkflowOrderInstanceRestClassV4::internAddData(wf), api_version) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (name == "staticdata_type") {
            return doGetDataProviderTypeRestClass(sprintf("staticdata hash for workflow %s v%s (%d)", wf.name,
                    wf.version, wf.workflowid), wf.staticdata_type_path
                ? UserApi::getTypeFromPath(wf.staticdata_type_path)
                : AbstractDataProviderType::get("hash<auto>"));
        }

        return WorkflowOrderInstanceRestClassV3::subClassImpl(name, cx, ah);
    }

    static hash<auto> internAddData(hash<auto> h) {
        return h + {
            "staticdata_type_path": Qorus.qmm.lookupWorkflow(h.InstanceInfo.workflowid).staticdata_type_path,
        };
    }
}

/** @REST /v4/orders (/v3/orders)

    This URI path provides information and actions related to workflow order data.
*/
class GlobalOrderRestClassV4 inherits GlobalOrderRestClassV3 {
    private *QorusRestClass internGetOrderInstanceRestClass(hash<auto> h) {
        return new WorkflowOrderInstanceRestClassV4(h);
    }
}

/** @REST /v4/workflows (/v3/workflows)

    This URI path allows workflows to be queried and for actions on multiple workflows to be performed;
    this is the URI path parent of workflow-specific actions as well.
*/
class WorkflowRestClassV4 inherits WorkflowRestClassV3 {
    private *QorusRestClass internGetOrderInstanceRestClass(hash<auto> h) {
        return new WorkflowOrderInstanceRestClassV4(h);
    }

    private *QorusRestClass internGetWorkflowDefinitionSubclass(hash<auto> wf) {
        return new WorkflowDefinitionRestClassV4(wf);
    }
}

class DataProviderRestHelper {
    private QorusRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClass(provider);
    }
}

/** @REST /v4/remote/qorus/{name} (/v3/remote/qorus/{name})

    This REST URI path provides actions and information related to a specific @ref remoteconn "remote connection"
*/
class QorusRemoteConnectionRestClassV4 inherits QorusRemoteConnectionRestClassV3, DataProviderRestHelper {
    constructor(hash<auto> rh) : QorusRemoteConnectionRestClassV3(rh) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "provider": {
                return doGetDataProviderRestClass(Qorus.remotemonitor.getConnection(rh.name).getDataProvider());
            }
        }
        return QorusRemoteConnectionRestClassV3::subClassImpl(name, cx, ah);
    }

    /** @REST PUT action=enableDebugData

        @par Description
        Enables data debugging for the current @ref remoteconn "remote connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */
    hash<auto> putEnableDebugData(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.remotemonitor.enableDebugData(rh.name);
        hash<auto> rv = {
            "info": sprintf("enabled data debugging for Qorus connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=disableDebugData

        @par Description
        Disables current @ref remoteconn "remote connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */
    hash<auto> putDisableDebugData(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.remotemonitor.disableDebugData(rh.name);
        hash<auto> rv = {
            "info": sprintf("disabled data debugging for Qorus connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v4/remote/qorus (/v3/remote/qorus)

    This REST URI path provides actions and information related to Qorus @ref remoteconn "remote connections"
*/
class QorusRemoteConnectionsRestClassV4 inherits QorusRemoteConnectionsRestClassV3 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        try {
            bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
            return new QorusRemoteConnectionRestClassV4({"name": name} +
                Qorus.remotemonitor.getInfo(name, {"with_passwords": with_passwords}));
        } catch (hash<ExceptionInfo> ex) {
            # CONNECTION-ERROR is thrown if the connection is unknown
            if (ex.err == "CONNECTION-ERROR") {
                return;
            }
            rethrow;
        }
    }
}

/** @REST /v4/system (/v3/system)

    This REST URI path provides actions and information for system functionality
*/
class SystemRestClassV4 inherits SystemRestClassV3 {
    hash<auto> internGetInfo(hash<auto> cx) {
        return SystemRestClassV3::internGetInfo(cx) + {
            # return default mapper keys + global Qorus mapper keys
            "default_mapper_keys": MapperKeyInfo + QorusMapperKeys,
        };
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *QorusRestClass rv = SystemRestClassV3::subClassImpl(arg, cx, ah);
        if (rv) {
            return rv;
        }
        if (arg == "ix_context") {
            return new AttributeRestClass(internGetInterfacesWithDataContext());
        }
    }

    /** @REST GET action=interfacesWithDataContext

        @par Description
        Returns a list of interfaces with a defined data context

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c iface_kind: the type of interface (\c workflow, \c service, or \c job)
        - \c name: the name of the interface
        - \c version: the version of the interface
        - \c id: the ID of the interface
        - \c label: a string in the format: \c name:version
    */
    hash<HttpHandlerResponseInfo> getInterfacesWithDataContext(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, internGetInterfacesWithDataContext());
    }

    # return interfaces with a data context
    *list<hash<auto>> internGetInterfacesWithDataContext() {
        list<hash<auto>> rv;
        map rv += {
            "iface_kind": "workflow",
            "name": $1.name,
            "version": $1.version,
            "id": $1.workflowid,
            "label": sprintf("%s:%s", $1.name, $1.version),
        }, Qorus.qmm.getWorkflowMap().iterator(), $1.staticdata_type_path;
        return rv;
    }
}

/** @REST /v4/remote/user/{name} (/v3/remote/user/{name})

    This REST URI path provides actions and information related to a specific @ref userconn "user connection"
*/
class UserConnectionRestClassV4 inherits UserConnectionRestClassV3, DataProviderRestHelper {
    constructor(hash<auto> rh) : UserConnectionRestClassV3(rh) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "provider": {
                return doGetDataProviderRestClass(Qorus.connections.getConnection(rh.name).getDataProvider());
            }
        }
        return UserConnectionRestClassV3::subClassImpl(name, cx, ah);
    }

    /** @REST PUT action=enableDebugData

        @par Description
        Enables data debugging for the current @ref userconn "user connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */
    hash<auto> putEnableDebugData(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.connections.enableDebugData(rh.name);
        hash<auto> rv = {
            "info": sprintf("enabled data debugging for user connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=disableDebugData

        @par Description
        Disables data debugging for the current @ref userconn "user connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */
    hash<auto> putDisableDebugData(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.connections.disableDebugData(rh.name);
        hash<auto> rv = {
            "info": sprintf("disabled data debugging for user connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v4/remote/user (/v3/remote/user)

    This REST URI path provides actions and information related to Qorus @ref userconn "user connections"
*/
class UserConnectionsRestClassV4 inherits UserConnectionsRestClassV3 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
        *hash<auto> rh = Qorus.connections.getInfo(name, {"with_passwords": with_passwords});
        if (rh) {
            return new UserConnectionRestClassV4(rh);
        }
    }
}

/** @REST /v4/remote/datasources/{name} (/v3/remote/datasources/{name})

    This REST URI path provides actions and information related to a specific Qorus system @ref dsconn "datasource"
*/
class DatasourceRestClassV4 inherits DatasourceRestClassV3, DataProviderRestHelper {
    constructor(hash<auto> rh) : DatasourceRestClassV3(rh) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "provider": {
                # do not return a data provider from the "omq" datasource
                if (name == "omq") {
                    throw "DATASOURCE-ERROR", sprintf("cannot acquire a connection for %y: this is a private/system "
                        "datasource", name);
                }
                return doGetDataProviderRestClass(Qorus.dsmanager.getConnection(rh.name).getDataProvider());
            }
        }
        return DatasourceRestClassV3::subClassImpl(name, cx, ah);
    }
}

/** @REST /v4/remote/datasources (/v3/remote/datasources)

    This REST URI path provides actions and information related to Qorus system @ref dsconn "datasources"
*/
class DatasourcesRestClassV4 inherits DatasourcesRestClassV3 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        try {
            bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
            return new DatasourceRestClassV4(Qorus.dsmanager.getInfo(name, {
                "with_passwords": with_passwords,
                "rtime": parse_boolean(ah.rtime),
            }));
        } catch (hash<ExceptionInfo> ex) {
%ifdef QorusDebugInternals
            if (name != "reload") {
                QDBG_LOG("%s", get_exception_string(ex));
            }
%endif
        }
    }
}

/** @REST /v4/remote (/v3/remote)

    This REST URI path provides actions and information about remote @ref remoteconn "Qorus", @ref userconn "user" and
    @ref dsconn "datasource" connections
*/
class RemoteRestClassV4 inherits RemoteRestClassV3 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "qorus": return new QorusRemoteConnectionsRestClassV4();
            case "user": return new UserConnectionsRestClassV4();
            case "datasources": return new DatasourcesRestClassV4();
        }
    }
}

class DataProviderSearchStream inherits AbstractDataStreamRequestHandler {
    private {
        const Defaults = {
            "block_size": 1000,
        };

        AbstractDataProviderRecordIterator i;
        hash<auto> conf;
        bool done;
    }

    constructor(AbstractDataProvider provider, hash<auto> cx, *hash<auto> ah) : AbstractDataStreamRequestHandler(cx, ah) {
        i = provider.searchRecords(ah.where_cond, ah.search_options - "requires_result");
        conf = Defaults + ah;
    }

    recvDataImpl(auto data) {
        # this method intentionally left blank
    }

    private auto sendDataImpl() {
        if (done) {
            return;
        }
        list<hash<auto>> rv;
        while (rv.size() < conf.block_size) {
            if (!i.next()) {
                done = True;
                break;
            }
            rv += i.getValue();
        }
        return rv;
    }
}

class DataProviderStreamBase inherits AbstractDataStreamRequestHandler {
    private {
        AbstractDataProvider provider;
        bool err_flag;
    }

    constructor(AbstractDataProvider provider, hash<auto> cx, *hash<auto> ah)
            : AbstractDataStreamRequestHandler(cx, ah - "provider_options") {
        self.provider = provider;
    }

    log(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, sprintf("data provider %y: ", provider.getName()) + fmt, argv);
    }
}

class DataProviderBulkStream inherits DataProviderStreamBase {
    private {
        AbstractDataProviderBulkOperation op;
        date start = now_us();
        int rowcount = 0;
        bool reply_sent;
    }

    constructor(AbstractDataProvider provider, AbstractDataProviderBulkOperation op, hash<auto> cx, *hash<auto> ah)
            : DataProviderStreamBase(provider, cx, ah) {
        self.op = op;
    }

    destructor() {
    }

    recvDataImpl(auto record_data) {
        try {
            record_data -= "provider_options";
            rowcount += (record_data.typeCode() == NT_HASH
                ? record_data.firstValue().lsize()
                : record_data.lsize());
            op.queueData(record_data);
            log("QUEUED: %y", record_data);
        } catch (hash<ExceptionInfo> ex) {
            err_flag = True;
            rethrow;
        }
    }

    private recvDataDoneImpl(*string err) {
        if (err) {
            op.discard();
            op.rollback();
            log("stream complete; rolled back transaction due to errors");
        } else {
            op.flush();
            op.commit();
            log("stream complete: committed %d row%s", rowcount, rowcount == 1 ? "" : "s");
        }
    }

    private auto sendDataImpl() {
        if (!err && !reply_sent) {
            reply_sent = True;
            return {
                "records_received": rowcount,
                "elapsed_time": sprintf("%gs", (now_us() - start).durationSecondsFloat()),
            };
        }
    }
}

class DataProviderInsertStream inherits DataProviderBulkStream {
    constructor(AbstractDataProvider provider, hash<auto> cx, *hash<auto> ah)
        : DataProviderBulkStream(provider, provider.getBulkInserter(), cx, ah) {
    }
}

class DataProviderUpsertStream inherits DataProviderBulkStream {
    constructor(AbstractDataProvider provider, hash<auto> cx, *hash<auto> ah)
        : DataProviderBulkStream(provider, provider.getBulkUpserter(), cx, ah) {
    }
}

/** @REST /v4/dataprovider/factories/{factory}/provider/record

    This URI path provides record information for a data provider

    @par Arguments
    This URI path element is reachable only if a provider can be created from the factory; to create the provider,
    the following hash argument is removed from the argument list before passing onward for processing:
    - \c provider_options: the options to be passed to the factory creation method to create the provider
*/
class DataProviderRecordRestClass inherits QorusRestClass {
    public {
        *hash<string, AbstractDataField> rec;
    }

    constructor(*hash<string, AbstractDataField> rec) {
        self.rec = rec;
    }

    string name() {
        return "record";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            hash<auto> info = getIntern(ah);
            if (info.hasKey(arg)) {
                return new AttributeRestClass(info{arg});
            }
        }
    }

    private *hash<auto> getIntern(*hash<auto> ah) {
        bool soft = parse_boolean(ah.soft);
        return map {
            $1.key: soft ? $1.value.getSoftType().getInfo() : $1.value.getInfo(),
        }, rec.pairIterator();
    }

    /** @REST GET

        @par Description
        Returns data record information

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c soft: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the type is returned with
          soft types to be used as the target for a mapper
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, getIntern(ah));
    }
}

/** @REST /v4/dataprovider/factories/{factory}/provider

    This URI path provides access to a data provider created from a data provider factory

    @par Arguments
    This URI path element is reachable only if a provider can be created from the factory; to create the provider,
    the following hash argument is removed from the argument list before passing onward for processing:
    - \c provider_options: the options to be passed to the factory creation method to create the provider
*/
class DataProviderRestClass inherits QorusRestClass, DataProviderRestHelper, DataProviderTypeRestHelper {
    public {
        #! Generic option for requiring at least one record in search APIs
        /** This option is added to the search_options on all data providers that support reading from the Qorus API
        */
        const GenericRequiresResultOption = {
            "type": ("bool",),
            "required": True,
            "desc": "If True, then an operation that returns no result or affects no records results in an error",
            "default_value": False,
        };
    }

    private {
        AbstractDataProvider provider;
    }

    constructor(AbstractDataProvider provider) {
        self.provider = provider;
    }

    string name() {
        return provider.getName();
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProvider child = provider.getChildProvider(arg);
        if (child) {
            return doGetDataProviderRestClass(child);
        }

        return doSubClassArg(arg, cx, ah);
    }

    private *QorusRestClass doSubClassArg(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (arg == "record") {
                return doGetDataProviderRecordRestClass(provider.getRecordType());
            }
            if (arg == "request") {
                return doGetDataProviderTypeRestClass("request", provider.getRequestType());
            }
            if (arg == "response") {
                return doGetDataProviderTypeRestClass("response", provider.getResponseType());
            }
            hash<auto> info = doGetInfo(ah);
            if (info.hasKey(arg)) {
                return new AttributeRestClass(info{arg});
            }
        }
    }

    /** @REST GET

        @SCHEMA
        @summary Returns data provider information

        @desc Returns data provider information

        @return (hash DataProviderInfo): information about the current data provider
        - name (string): the name of the data provider
        - supports_read (bool): if the data provider supports record read/search actions
        - supports_create (bool): if the data provider support record creation
        - supports_update (bool): if the data provider supports record updates
        - supports_upsert (bool): if the data provider supports record upserts / merges
        - supports_delete (bool): if the data provider supports record deletions
        - supports_native_search (bool): if the data provider supports a native record search API
        - supports_bulk_read (bool): if the data provider supports bulk record read / search actions
        - supports_bulk_create (bool): if the data provider supports bulk record creation
        - supports_bulk_upsert (bool): if the data provider supports bulk record upsert / merges
        - supports_request (bool): if the data provider supports the request/reply integration pattern (API calls)
        - supports_children (bool): if the data provider supports children
        - transaction_management (bool): if the data provider supports transaction mgmt
        - has_record (bool): if the data provider supports records
        - record_requires_search_options (bool): if the data provider requires search options when searching
        - supports_child_create (bool): if the data provider supports creating child data providers
        - supports_child_delete (bool): if the data provider supports deleting child data providers
        - supports_add_field (bool): if the data provider supports the add field API
        - supports_update_field (bool): if the data provider supports the update field API
        - supports_delete_field (bool): if the data provider supports the delete field API
        - supports_schema (bool): if the data provider supports a schema
        - supports_search_expressions (bool): if the data provider supports generic search expressions
        - supports_observable (bool): if the data provider supports the observer pattern / event API
        - supports_messages (string): if the data provider supports output messages; values are: \c NONE (messages \
          not supported), \c SYNC (messages supported 1:1 with observed events), \c ASYNC (messages supported, no \
          connection to observed events)
        - children_can_support_apis (bool): if the data provider can provide children that support APIs
        - children_can_support_records (bool): if the data provider can provide children that support records
        - children_can_support_observers (bool): if the data provider can provide children that support event observation
        - children_can_support_messages (bool): if the data provider can provide children that support messages
        - events (*hash[any] UndefinedHash): any events supported by the data provider
        - messages (*hash[any] UndefinedHash): any messages supported by the data provider
        - search_logic_capabilities (int): a bitfield of supported search logic capabilities
        - mapper_keys (*hash[any] UndefinedHash): a hash of mapper key information
        - desc (string): the description of the data provider
        - type (string): the type (class name) of the data provider
        - constructor_options (*hash[any] UndefinedHash): any constructor options supported by the data provider
        - create_options (*hash[any] UndefinedHash): any record creation options supported by the data provider
        - upsert_options (*hash[any] UndefinedHash): any record upsert options supported by the data provider
        - search_options (*hash[any] UndefinedHash): any record search options supported by the data provider
        - child_create_options (*hash[any] UndefinedHash): any child creation options supported by the data provider
        - children (*list<string>): a list of any data provider children

        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, doGetInfo(ah));
    }

    /** @REST POST action=create

        @par Arguments
        This API takes the following hash argument (either as URI arguments or in the message body):
        - \c record: (required) the set of fields making up the new record
        - \c create_options: any create options supported by the data provider

        @par Return Value
        The string \c "OK"

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c record key
    */
    hash<HttpHandlerResponseInfo> postCreate(hash<auto> cx, *hash<auto> ah) {
        if (ah.record.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, "no key \"record\" argument sent in request");
        }
        provider.createRecord(ah.record, ah.create_options);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST POST action=request

        @par Arguments
        - \c request_options: request options

        @par Return Value
        Returns the result of the operation
    */
    hash<HttpHandlerResponseInfo> postRequest(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, provider.doRequest(ah.request_options));
    }

    /** @REST PUT action=upsert

        @par Arguments
        This API takes the following hash argument (either as URI arguments or in the message body):
        - \c record: (required) the set of fields making up the new record
        - \c upsert_options: any upsert options supported by the data provider

        @par Return Value
        The result string of the upsert operation; see @ref db_provider_upsert_results for possible values

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c record key
    */
    hash<HttpHandlerResponseInfo> putUpsert(hash<auto> cx, *hash<auto> ah) {
        if (ah.record.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, "no key \"record\" argument sent in request");
        }
        return RestHandler::makeResponse(200, provider.upsertRecord(ah.record, ah.upsert_options));
    }

    /** @REST GET action=search

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c where_cond: search parameters
        - \c search_options: search options

        @par Return Value
        Returns a list of hashes of records matching the search parameters given by \a where_cond
    */
    hash<HttpHandlerResponseInfo> getSearch(hash<auto> cx, *hash<auto> ah) {
        *bool requires_result;
        if (exists ah.search_options.requires_result) {
            requires_result = parse_boolean(remove ah.search_options.requires_result);
        }
        AbstractDataProviderRecordIterator i = provider.searchRecords(ah.where_cond, ah.search_options);
        *list<auto> rv = map $1, i;
        if (requires_result && !rv) {
            throw "NO-DATA-ERROR", sprintf("data provider %y: search criteria %y returned no records, and "
                "\"requires_result\" is set", provider.getName(), ah.where_cond);
        }
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=update

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c set: (required) set of fields matching \a where_conf to update
        - \c where_cond: (required) search parameters
        - \c search_options: search options

        @par Return Value
        Returns the number of rows updated

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c set or \c where_cond keys
    */
    hash<HttpHandlerResponseInfo> putUpdate(hash<auto> cx, *hash<auto> ah) {
        if (ah.set.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, "no key \"set\" argument sent in request");
        }
        if (ah.where_cond.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, "no key \"where_cond\" argument sent in request");
        }
        return RestHandler::makeResponse(200, provider.updateRecords(ah.set, ah.where_cond, ah.search_options -
            "requires_result"));
    }

    /** @REST DELETE

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c where_cond: search parameters for records to be deleted
        - \c search_options: search options

        @par Return Value
        Returns the number of records deleted

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c where_cond key
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        if (ah.where_cond.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, "no key \"where_cond\" argument sent in request");
        }
        return RestHandler::makeResponse(200, provider.deleteRecords(ah.where_cond, ah.search_options -
            "requires_result"));
    }

   /** @REST POST action=stream

        @par Description
        Opens a stream for bulk inserting or upserting records in the data provider

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c stream: (required) the name of the stream to open; must be either:
          - \c insert: for an insert stream
          - \c upsert: for an upsert stream
        - \c upsert_options: any upsert options supported by the data provider (upsert stream only)

        @par Return Value
        This API returns a stream supporting bulk record insertion for the data provider
    */
    AbstractRestStreamRequestHandler streamPostStream(hash<auto> cx, *hash<auto> ah) {
        switch (ah.stream) {
            case "insert":
                return new DataProviderInsertStream(provider, cx, ah);
            case "upsert":
                return new DataProviderUpsertStream(provider, cx, ah);
        }
        throw "STREAM-ERROR", sprintf("invalid stream %y in parameters; expecting one of \"insert\" "
            "or \"upsert\"", ah.stream);
    }

   /** @REST GET action=stream

        @par Description
        Returns a search stream for results corresponding to the argument(s)

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body); all keys are
        optional:
        - \c where_cond: search parameters
        - \c block_size: number of rows in each block (default = 1000)

        @par Return Value
        This API returns a stream consisting of a list of hashes of records matching the search parameters given by
        \a where_cond
    */
    AbstractRestStreamRequestHandler streamGetStream(hash<auto> cx, *hash<auto> ah) {
        return new DataProviderSearchStream(provider, cx, ah);
    }

    # Returns information about the data provider
    hash<auto> doGetInfo(*hash<auto> ah, *int apiver) {
        return DataProviderRestClass::doGetInfo(provider, ah, apiver);
    }

    QorusRestClass doGetDataProviderRecordRestClass(*hash<string, AbstractDataField> rec) {
        return new DataProviderRecordRestClass(rec);
    }

    # Returns information about the data provider
    static hash<auto> doGetInfo(AbstractDataProvider provider, *hash<auto> ah, *int apiver, *bool child_details) {
        # we have to add Qorus mapper keys to the response here
        hash<auto> rv = provider.getInfoAsData(apiver >= 6);
        rv.mapper_keys = QorusMapperKeys + rv.mapper_keys;
        # add the "requires_result" option to the data provider's search options if it supports reading
        if (rv.supports_read && !rv.search_options.requires_result) {
            rv.search_options.requires_result = GenericRequiresResultOption;
        }
        if (child_details && rv.children) {
            rv.children = provider.getChildProviderSummaryInfo();
        }
        return DataProviderRestClass::processOptions(rv, ah);
    }

    #! Processes options for the calling context
    static hash<auto> processOptions(*hash<auto> rv, *hash<auto> ah) {
        QDBG_LOG("processOptions ah: %y", ah);
        # only return options that make sense for the UI
        if (DataProviderRestClass::checkOption(ah, "context", "ui")) {
            bool api_management = DataProviderRestClass::checkOption(ah, "context", "api");
            foreach hash<auto> i in (rv.pairIterator()) {
                if (i.key !~ /_options$/ || i.value.typeCode() != NT_HASH) {
                    continue;
                }
                QDBG_LOG("processOptions ah: %y", ah);
                foreach hash<auto> j in (i.value.pairIterator()) {
                    # remove unsupported types
                    rv{i.key}{j.key}.type = map $1, j.value.type, $1 !~ /^object/;
                    # remove options with no supported types
                    if (!rv{i.key}{j.key}.type) {
                        remove rv{i.key}{j.key};
                        continue;
                    } else if (exists rv{i.key}{j.key}.type_info) {
                        rv{i.key}{j.key}.type_info = map $1, j.value.type_info, $1.name !~ /^object/
                            && (!api_management || !$1.tags.client_only);
                        if (!rv{i.key}{j.key}.type_info) {
                            remove rv{i.key}{j.key};
                            continue;
                        }
                        foreach hash<auto> type_info in (remove rv{i.key}{j.key}.type_info) {
                            if (type_info.tags.from_file && type_info.name == "string") {
                                rv{i.key}{j.key}.type[$#] = "file-as-string";
                            }
                        }
                    }
                    if (rv{i.key}{j.key}.allowed_values) {
                        if (rv{i.key}{j.key}.allowed_values[0].value) {
                            rv{i.key}{j.key}.allowed_values = map ("name": $1.value, "desc": $1.desc),
                                rv{i.key}{j.key}.allowed_values;
                        } else {
                            rv{i.key}{j.key}.allowed_values = map ("name": $1), rv{i.key}{j.key}.allowed_values;
                        }
                    }
                    QDBG_LOG("processOptions (%y) j: %y", i.key, j);
                }
            }
            if (*hash<auto> exp = remove rv.expressions) {
                bool selected;
                foreach hash<auto> i in (exp.pairIterator()) {
                    # skip expressions that are not valid for searching
                    # and those that cannot take a field reference as the first arg
                    if (!(i.value.role & ER_Search) || i.value.args[0].type_code == "value") {
                        continue;
                    }
                    hash<auto> h = i.value{"name", "desc",};
                    if (i.key == "!" || i.key =~ /^not$/i) {
                        h.supports_nesting = True;
                    } else {
                        h.supports_nesting = False;
                        # skip operators that cannot be nested and take only one arg
                        if (i.value.args.size() == 1) {
                            continue;
                        }
                    }
                    if (!h.supports_nesting && i.value.args[1].type != "any" && i.value.args[1].type != "auto") {
                        h.type = (i.value.args[1].type,);
                    }
                    # set "selected" on "=" operator
                    if (!selected && (i.key == '=' || i.key == "eq")) {
                        h.selected = True;
                        selected = True;
                    }
                    rv.search_operators{i.key} = h;
                }
            }
        }
        return rv;
    }

    static bool checkOption(*hash<auto> ah, string optval, string value) {
        auto opt = ah{optval};
        switch (opt.typeCode()) {
            case NT_STRING: {
                int i = opt.find(",");
                if (i == -1) {
                    return opt == value;
                }
                return inlist(value, opt.split(","));
            }
            case NT_LIST: return inlist(value, opt);
        }
        return False;
    }

    static *hash<string, bool> parseOption(*hash<auto> ah, string optval) {
        auto opt = ah{optval};
        switch (opt.typeCode()) {
            case NT_STRING: {
                int i = opt.find(",");
                if (i == -1) {
                    return {opt: True};
                }
                return map {$1: True}, opt.split(",");
            }
            case NT_LIST: return map {$1: True}, opt;
        }
    }
}

/** @REST /v4/remote/datasources/{name}/provider (/v4/dataprovider/factories/{factory}/provider)

    This URI path provides access to a data provider created from a @ref dsconn "datasource"
*/

/** @REST /v4/remote/qorus/{name}/provider (/v4/dataprovider/factories/{factory}/provider)

    This URI path provides access to a data provider created from a @ref remoteconn "remote Qorus connection"
*/

/** @REST /v4/remote/user/{name}/provider (/v4/dataprovider/factories/{factory}/provider)

    This URI path provides access to a data provider created from a @ref userconn "user connection"
*/

/** @REST /v4/dataprovider/factories/{factory}

    This URI path provides access to data factory information
*/
class DataProviderFactoryRestClass inherits QorusRestClass, DataProviderRestHelper {
    private {
        string name;
        AbstractDataProviderFactory factory;
    }

    constructor(string name, AbstractDataProviderFactory factory) {
        self.name = name;
        self.factory = factory;
    }

    string name() {
        return name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "provider") {
            if (ah.provider_options.typeCode() == NT_STRING) {
                ah.provider_options = parse_to_qore_value(ah.provider_options);
            }
            if (ah.provider_options.typeCode() != NT_HASH) {
                remove ah.provider_options;
            }
            return doGetDataProviderRestClass(DataProvider::getFactoryObject(name, ah.provider_options));
        }

        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            hash<auto> info = doGetInfo(ah);
            if (info.hasKey(arg)) {
                return new AttributeRestClass(info{arg});
            }
        }
    }

    /** @REST GET

        @par Description
        Returns data factory information
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, doGetInfo(ah));
    }

    private hash<auto> doGetInfo(*hash<auto> ah, *int apiver) {
        return DataProviderFactoryRestClass::doGetInfo(name, factory, ah, apiver);
    }

    static hash<auto> doGetInfo(string name, AbstractDataProviderFactory factory, *hash<auto> ah, *int apiver) {
        # we have to add Qorus mapper keys to the response here
        hash<auto> rv = factory.getInfoAsData(apiver >= 6);
        rv.mapper_keys = QorusMapperKeys + rv.mapper_keys;
        if (rv.provider_info && ah) {
            if ((apiver >= 6) && DataProviderRestClass::checkOption(ah, "context", "api")) {
                rv.provider_info.constructor_options += QorusAbstractApiManager::getOptionsForApiManagement(name,
                    ah.api_profile);
            }
            rv.provider_info = DataProviderRestClass::processOptions(rv.provider_info, ah);
        }
        return DataProviderRestClass::processOptions(rv, ah);
    }
}

/** @REST /v4/dataprovider/factories

    This URI path provides access to data factory information
*/
class DataProviderFactoriesRestClass inherits QorusRestClass {
    private {
        const CapMap = {
            "supports_create": "create",
            "supports_read": "read",
            "supports_update": "update",
            "supports_delete": "delete",
            "supports_upsert": "upsert",
            "supports_native_search": "search",
            "supports_bulk_create": "bulk_create",
            "supports_bulk_upsert": "bulk_upsert",
            "supports_children": "children",
            "transaction_management": "trans",
        };
    }

    string name() {
        return "factories";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProviderFactory factory = DataProvider::getFactory(arg);
        if (factory) {
            return new DataProviderFactoryRestClass(arg, factory);
        }
    }

    /** @REST GET

        @par Description
        Returns data factory information

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of data provider factory
          names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of
          data provider factory information is returned
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *list<string> factory_list = sort(DataProvider::listFactories());
        if (exists ah."list" && parse_boolean(ah."list")) {
            return RestHandler::makeResponse(200, factory_list);
        }
        *list<hash<auto>> rv = doGetFactoryInfo(factory_list, ah);
        # return summary info
        if (exists ah.short && parse_boolean(ah.short)) {
            return RestHandler::makeResponse(200,
                map sprintf("%s: %s (%s)", $1.name, $1.provider_info.type, doGetCapString($1)), rv);
        }
        return RestHandler::makeResponse(200, rv);
    }

    private *list<hash<auto>> doGetFactoryInfo(*list<string> factory_list, *hash<auto> ah) {
        return map DataProviderFactoryRestClass::doGetInfo($1, DataProvider::getFactory($1), ah), factory_list;
    }

    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return (map {$1: True}, DataProvider::listFactories()) + QorusRestClass::doGetPossibleSubClasses(cx, ah);
    }

    static private *string doGetCapString(hash<auto> factory_info) {
        *string rv = foldl $1 + ", " + $2, (map $1.value, CapMap.pairIterator(), factory_info.provider_info{$1.key});
        if (factory_info.api_management) {
            if (rv) {
                rv = "api_management, " + rv;
            } else {
                rv = "api_management";
            }
        }
        return rv;
    }
}

/** @REST /v4/dataprovider/types/.../{type}/type

    This URI path provides access information for a particular data type
*/
class DataProviderTypeRestClass inherits QorusRestClass {
    private {
        string name;
        AbstractDataProviderType type;
    }

    constructor(string name) {
        self.name = name;
        type = AbstractDataProviderType::get(NothingType);
    }

    constructor(string name, AbstractDataProviderType type) {
        self.name = name;
        self.type = type;
    }

    string name() {
        return name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # return fields directly
        *AbstractDataField field = type.getField(arg);
        if (field) {
            return new DataProviderTypeRestClass(arg, field.getType());
        }

        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            # otherwise look for direct attributes of the type
            hash<auto> info = doGetInfo();
            if (info.hasKey(arg)) {
                return new AttributeRestClass(info{arg});
            }
        }
    }

    /** @REST GET

        @par Description
        Returns data type information

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c soft: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the type is returned with
          soft types to be used as the target for a mapper
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, doGetInfo(ah));
    }

    hash<auto> doGetInfo(*hash<auto> ah) {
        return DataProviderTypeRestClass::doGetInfo(type, name, ah);
    }

    static hash<auto> doGetInfo(AbstractDataProviderType type, string name, *hash<auto> ah) {
        bool soft = parse_boolean(ah.soft);
        return {
            "typename": name,
        } + (soft ? type.getSoftType().getInfo() : type.getInfo()) + {
            "or_nothing_type": type.isOrNothingType(),
            "locked": Qorus.qmm.isTypeLocked(name),
        };
    }
}

/** @REST /v4/workflows/{id_or_name}/staticdata_type (/v4/dataprovider/types/.../{type}/type)

    This REST URI path provides information about workflow static data types
*/

/** @REST /v4/orders/{id}/staticdata_type (/v4/dataprovider/types/.../{type}/type)

    This REST URI path provides information about workflow static data types
*/

/** @REST /v4/dataprovider/types

    This URI path provides access to data type information
*/
class DataProviderTypesRestClass inherits QorusRestClass, DataProviderTypeRestHelper {
    private {
        DataProviderTypeEntry entry;
        string name;
    }

    constructor() {
        entry = DataProvider::getTypeRoot();
        name = "types";
    }

    constructor(DataProviderTypeEntry entry) {
        self.entry = entry;
        name = entry.getName();
    }

    string name() {
        return name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *DataProviderTypeEntry child = entry.getChild(arg);
        if (child) {
            return new DataProviderTypesRestClass(child);
        }

        # check for field
        if (entry.getInfo().has_type && (*AbstractDataField field = entry.getType().getField(arg))) {
            DataProviderTypeEntry new_entry(entry.getPath(), arg);
            new_entry.setType(field.getType());
            return new DataProviderTypesRestClass(new_entry);
        }

        if (arg == "type") {
            return doGetDataProviderTypeRestClass(entry.getPath(), entry.getTypeEx());
        }
    }

    /** @REST GET

        @par Description
        Returns information for the current data type entry
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, entry.getInfo());
    }

    /** @REST GET action=type

        @par Description
        Returns information about the current data type

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c soft: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the type is returned with
          soft types to be used as the target for a mapper

        @par Errors
        - <tt><b>404 Not Found</b></tt>: returned if the current entry has no type
    */
    hash<HttpHandlerResponseInfo> getType(hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProviderType type = entry.getType();
        if (!type) {
            return RestHandler::makeResponse(404, sprintf("entry %y has no type but has children: %y",
                type.getPath(), type.getChildNames()));
        }

        return RestHandler::makeResponse(200, DataProviderTypeRestClass::doGetInfo(type, entry.getPath(), ah));
    }

    /** @REST POST

        @par Description
        Creates a new data type

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c path: (*string) the relative path from the current entry to the new type (ex: \c "my-types/project-x/my-type")
        - \c type: (hash) a hash with the following keys:
          - \c name: (string) the type name
          - \c options: (*hash) a hash of type options
          - \c fields: (*hash) a hash of fields where names are field names and values are hashes with the following
            keys:
            - \c type: (hash) as above
            - \c desc: (*string) a description for the field
            - \c default: (*string) a default value for the field serialization as YAML

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>403 Forbidden</b></tt>: TYPE-LOCK-ERROR: a static/base type already exists with the given path
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        if (ah.path.typeCode() != NT_STRING) {
            ah.path = entry.getPath();
        } else {
            if (ah.path[0] == "/") {
                ah.path = ah.path[1..];
            }
            ah.path = entry.getPath() + "/" + ah.path;
        }

        AbstractDataProviderType type;
        try {
            type = QorusDataProviderTypeHelper::getType(ah.type);
        } catch (hash<ExceptionInfo> ex) {
            return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
        }

        try {
            ah.path = Qorus.qmm.addOrReplaceType(ah.path, type);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "TYPE-LOCK-ERROR") {
                return RestHandler::makeResponse(403, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }

        return RestHandler::makeResponse(200, DataProviderTypeRestClass::doGetInfo(type, ah.path));
    }

    /** @REST DELETE

        @par Description
        Deletes the data type

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the entry has no type to delete
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        if (!entry.getInfo().has_type) {
            return RestHandler::makeResponse(400, sprintf("type tree entry %y has no type to delete", entry.getPath()));
        }
        try {
            Qorus.qmm.removeType(entry.getPath());
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "TYPE-LOCK-ERROR") {
                return RestHandler::makeResponse(403, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, sprintf("deleted type %y", entry.getPath()));
    }

    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return (map {$1: True}, entry.getChildNames()) + QorusRestClass::doGetPossibleSubClasses(cx, ah);
    }
}

/** @REST /v4/dataprovider/basetypes

    This URI path provides access to base data type information
*/
class DataProviderBaseTypesRestClass inherits QorusRestClass, DataProviderTypeRestHelper {
    public {
        #! "no null" option for non-soft types
        const TypeOptionQoreNoNull = {"qore.no_null": True};

        #! hash of base types available to mappers
        const BaseTypes = {
            "any": AbstractDataProviderType::get(AbstractDataProviderType::anyType),
            "int": AbstractDataProviderType::get(IntType, TypeOptionQoreNoNull),
            "float": AbstractDataProviderType::get(FloatType, TypeOptionQoreNoNull),
            "bool": AbstractDataProviderType::get(BoolType, TypeOptionQoreNoNull),
            "number": AbstractDataProviderType::get(NumberType, TypeOptionQoreNoNull),
            "date": AbstractDataProviderType::get(DateType, TypeOptionQoreNoNull),
            "string": AbstractDataProviderType::get(StringType, TypeOptionQoreNoNull),
            "binary": AbstractDataProviderType::get(BinaryType, TypeOptionQoreNoNull),
            "list": AbstractDataProviderType::get(AutoListType, TypeOptionQoreNoNull),
            "hash": AbstractDataProviderType::get(AutoHashType, TypeOptionQoreNoNull),

            "*int": AbstractDataProviderType::get(IntOrNothingType),
            "*float": AbstractDataProviderType::get(FloatOrNothingType),
            "*bool": AbstractDataProviderType::get(BoolOrNothingType),
            "*number": AbstractDataProviderType::get(NumberOrNothingType),
            "*date": AbstractDataProviderType::get(DateOrNothingType),
            "*string": AbstractDataProviderType::get(StringOrNothingType),
            "*binary": AbstractDataProviderType::get(BinaryOrNothingType),
            "*list": AbstractDataProviderType::get(AutoListOrNothingType),
            "*hash": AbstractDataProviderType::get(AutoHashOrNothingType),
        };

        #! for the get possible types method return value
        const PossibleBaseTypes = map {$1: True}, keys BaseTypes;
    }

    string name() {
        return "basetypes";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProviderType type = BaseTypes{arg};
        if (type) {
            return doGetDataProviderTypeRestClass(arg, type);
        }
    }

    /** @REST GET

        @par Description
        Returns a list of base data types

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of type names is
          returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of
          type information is returned
        - \c soft: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the type is returned with
          soft types to be used as the target for a mapper
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *list<string> type_list = sort(keys BaseTypes);
        if (exists ah."list" && parse_boolean(ah."list")) {
            return RestHandler::makeResponse(200, type_list);
        }

        bool soft = parse_boolean(ah.soft);

        # get list of types and simplified type info
        list<hash<auto>> rv;
        foreach string type in (type_list) {
            AbstractDataProviderType data_type = BaseTypes{type};
            if (soft) {
                data_type = data_type.getSoftType();
            }
            hash<DataTypeInfo> info = data_type.getInfo();
            rv += {
                "typename": type,
            } + info + {
                "fields": map {$1.key: $1.value{"desc", "default_value", "type"},
                }, info.fields.pairIterator(),
            };
        }

        # return summary info
        if (exists ah.short && parse_boolean(ah.short)) {
            return RestHandler::makeResponse(200,
                map sprintf("%s: %s fields: %d", $1.typename, $1.name, $1.fields.size()), rv);
        }

        # return all info
        return RestHandler::makeResponse(200, rv);
    }


    #! returns a set of possible subclasses for a particular request
    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return PossibleBaseTypes;
    }
}

/** @REST /v4/dataprovider/basetypes/{type} (/v4/dataprovider/types/.../{type})

    This URI path provides access to base data type information for a specific type
*/

/** @REST /v4/dataprovider

    This URI path provides access to data provider functionality
*/
class DataProviderBaseRestClass inherits QorusRestClass {
    constructor() {
        setup();
    }

    private setup() {
        addClass(new DataProviderFactoriesRestClass());
        addClass(new DataProviderTypesRestClass());
        addClass(new DataProviderBaseTypesRestClass());
        addClass(new DataProviderRestClass(create_object("QorusApiDataProvider")));
    }

    string name() {
        return "dataprovider";
    }
}
