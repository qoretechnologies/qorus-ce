# -*- mode: qore; indent-tabs-mode: nil -*-

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

%requires FsUtil

/** @page rest_api_page_v6 Qorus REST API v6

    @tableofcontents

    @section rest_api_v6_overview Qorus REST API v6 Overview

    REST API v6 has the following differences from @ref rest_api_page_v5 "REST API v5":
    - services have a \c processes key
    - the response format of the @ref rest_api_PUT_v6_services_load API has changed
*/

/** @REST /v6 (/v5)

    This URI path implements v6 of the Qorus REST API
*/
class V6RestClass inherits QorusRestClass {
    constructor() {
        addClass(new WorkflowRestClassV6());
        addClass(new GlobalOrderRestClassV6());
        addClass(new GlobalWorkflowExecRestClassV3());
        addClass(new ServiceRestClassV6());
        addClass(new SystemRestClassV6());
        addClass(new JobRestClassV6());
        addClass(new UsersRestClass());
        addClass(new RolesRestClass());
        addClass(new GroupsRestClassV5());
        addClass(new StepRestClassV3());
        addClass(new FunctionRestClass());
        addClass(new ClassRestClassV6());
        addClass(new ConstantRestClass());
        addClass(new DebugRestClass());
        addClass(new JobResultsRestClass());
        addClass(new LogsRestClass());
        addClass(new RemoteRestClassV6());
        addClass(new PermsRestClass());
        addClass(new ErrorsRestClassV3());
        addClass(new MappersRestClassV4());
        addClass(new MapperTypesRestClass());
        addClass(new AsyncQueuesRestClassV3());
        addClass(new ValueMapsRestClass());
        addClass(new ReleasesRestClass());
        addClass(new SyncEventTypesRestClass());
        addClass(new SlasRestClass());
        addClass(new DataProviderBaseRestClassV6());
        addClass(new FsmsRestClass());
        addClass(new PipelinesRestClass());
        addClass(new LogoutRestClass());
        addClass(new CommandRestClass());
        addClass(new RemoteDevelopment::RestClass());
        addClass(new ObjectOptionsRestClass());
        addClass(new ConnectionsRestClassV6());
        addClass(new CreatorRestClass());
    }

    string name() {
        return "v6";
    }

    /** @REST GET

        @par Description
        Returns the top-level members of this version of the REST API
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, keys class_hash);
    }
}

/** @REST /v6/orders/{id} (/v5/orders/{id})

    This REST URI path provides actions and information about specific workflow orders.
*/
class WorkflowOrderInstanceRestClassV6 inherits WorkflowOrderInstanceRestClassV5 {
    constructor(hash<auto> wf, int api_version = 6) : WorkflowOrderInstanceRestClassV5(wf, api_version) {
    }

    /** @REST GET

        @SCHEMA
        @summary Returns information about the current workflow order data instance

        @desc Returns information about the current workflow order data instance

        @return (hash WorkflowOrderInfo): detailed information about the workflow order
        - name (string): the name of the workflow
        - version (string): the version of the workflow
        - author (*string): the author of the workflow
        - patch (*string): the workflow patch string (if any)
        - workflow_instanceid (int): the workflow order instance ID
        - workflowid (int): the ID of the workflow
        - workflowstatus (string): the status of the workflow order (see @ref StatusDescriptions for possible values)
        - status_sessionid (int): the ID of the Qorus application session managing the workflow order data or 0 if \
          none
        - parent_workflow_instanceid (*int): the workflow order instance ID of the parent order for this workflow if \
          any
        - subworkflow (*bool): indicates if the \c parent_workflow_instanceid is the parent workflow order in \
          a subworkflow relationship
        - synchronous (bool): indicates if the order is being executed synchronously
        - archive (*bool): indicates if the order has been archived
        - business_error (bool): indicates if the workflow order has an error status due to a business error
        - workflowstatus_orig (*string): if the order status is @ref OMQ::StatBlocked or @ref OMQ::StatCanceled, \
          this value will reflect the original status of the workflow order (see @ref StatusDescriptions for \
          possible values)
        - custom_status (*string): a custom status for the order
        - scheduled (*date): the scheduled date
        - priority (int): the priority of the workflow order
        - started (date): the date/time the order was created
        - completed (*date): the date/time order processing completed
        - modified (date): the last modified date/time for the order
        - operator_lock (*string): a string giving the username of the user with an operator lock on the order
        - note_count (int): the number of notes stored against the order
        - deprecated (bool): a boolean value indicating if the workflow is deprecated or not; deprecated workflows \
          are hidden by default in the UI
        - autostart (int): the integer @ref wf_autostart "autostart value" for the workflow
        - manual_autostart (bool): a boolean flag set if the \c autostart value has been changed manually, in which \
          case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - max_instances (*int): a value limiting the maximum number of execution instances that can run at once
        - external_order_instanceid (*string): a unique external key for the order
        - staticdata (*hash[any] UndefinedHash): a hash of @ref staticdata "workflow order static data"
        - dynamicdata (*hash[any] UndefinedHash): a hash of @ref dynamicdata "workflow order dynamic data" (if any)
        - sensitive_data (*hash[hash[hash SensitiveDataInfo] SensitiveDataKeyInfo] SensitiveDataSetInfo): \
          any sensitive data information for the workflow; this information is only present when retrieving the data \
          over a secure (encrypted) connection; the keys are sensitive data key types, values are hashes keyed by \
          sensitive data values
        - has_sensitive_data (bool): indicates if the order has sensitive data
        - stepdata (*list<hash StepDataInfo>): a list of step data information
          - name (string): the step name
          - version (string): the step version
          - stepid (int): the step ID
          - steptype (string): the step type
          - arraytype (string): the step array type
          - data (list<hash[any] UndefinedHash>): list of hashes of the @ref stepdata "dynamic step data" per step \
            index
        - keys (*hash[*list<string>] OrderKeySet): a hash of @ref wf_keylist "workflow order keys" and values
        - warning_count (int): the number of warnings raised against the order
        - error_count (int): the number of errors raised against the order
        - retry_count (int): the number of times the order was subject to a @ref OMQ::StatRetry "RETRY" status due \
          to a technical error
        - StepInstances (list<hash StepInstanceInfo>): a list of step hashes giving information about the execution \
          status of @ref steps "workflow steps"
          - workflow_instanceid (int): the workflow instance ID for the step
          - stepid (int): the ID of the step
          - ind (int): the step array index starting with 0
          - stepname (string): the name of the step
          - stepversion (string): the version of the step
          - steptype (string): @ref StepTypes "type" of the step
          - stepstatus (string): the current execution status of the step (see @ref StatusDescriptions for possible \
            values)
          - retries (*int): the number of retries executed on the step
          - skip (bool): a boolean value indicating if the step logic was skipped
          - custom_status (*string): a custom status for the step
          - started (date): the date/time the step was first executed
          - completed (*date): the date/time step processing completed
          - function_instanceid (*int): the function ID of the primary step function
          - subworkflow_instanceid (*int): the workflow order ID of any subworkflow order instance (for bound \
            subworkflow steps only)
          - user_interaction (bool): if the step supports user interaction
          - workflow_event_typeid (*int): the event type ID for workflow event steps
          - eventkey (*string): the event key value for workflow event steps
          - queueid (*int): the asynchronous queue ID for asynchronous steps
          - queuename (*string): the asynchronous queue name for asynchronous steps
          - business_error (bool): a boolean flag indicating if the step has an error status due to a business error
        - ErrorInstances (*list<hash ErrorInstanceInfo>): a list of hashes giving information about errors and \
          warnings raised against the order
          - error_instanceid (int): a unique ID for the error
          - workflow_instanceid (int): the workflow order instance ID
          - stepid (*int): the stepid where the error was raised
          - ind (*int): the step array index starting with 0 where the error was raised
          - severity (string): the severity of the error (see @ref ErrorSeverityCodes for possible values)
          - retry (int): 1 if the error caused a retry
          - error (string): the string error code for the error
          - description (*string): an optional description of the error
          - info (*string): an optional string providing additional information about the error
          - business_error (bool): a boolean flag indicating if the error is a business error
          - created (date): the date/time the error was created
        - HierarchyInfo (hash[hash OrderHierarchyInfo] OrderHierarchySetInfo): a hash of workflow order information; \
          the keys are workflow order instance IDs for all workflow orders linked to each other through parent-child \
          relationships in the hierarchy of the current workflow order
          - name (string): the name of the workflow
          - version (string): the version of the workflow
          - workflow_instanceid (int): the workflow order instance ID
          - workflowid (int): the ID of the workflow
          - workflowstatus (string): the status of the workflow order (see @ref StatusDescriptions for possible values)
          - status_sessionid (int): the ID of the Qorus application session managing the workflow order data or 0 if \
            none
          - parent_workflow_instanceid (*int): the workflow order instance ID of the parent order for this workflow if \
            any
          - subworkflow (*int): if 1, indicates that the \c parent_workflow_instanceid is the parent workflow order in \
            a subworkflow relationship
          - synchronous (int): if 1, indicates that the order is being executed synchronously
          - retries (*int): the number of retries executed on the order
          - note_count (int): the number of notes stored against the order
          - business_error (bool): indicates if the workflow order has an error status due to a business error
          - workflowstatus_orig (*string): if the order status is @ref OMQ::StatBlocked or @ref OMQ::StatCanceled, \
            this value will reflect the original status of the workflow order (see @ref StatusDescriptions for \
            possible values)
          - custom_status (*string): a custom status for the order
          - scheduled (*date): the scheduled date
          - priority (int): the priority of the workflow order
          - started (date): the date/time the order was created
          - completed (*date): the date/time order processing completed
          - modified (date): the last modified date/time for the order
          - operator_lock (*string): a string giving the username of the user with an operator lock on the order
          - patch (*string): the workflow patch string (if any)
          - author (*string): the author of the workflow
          - description (*string): an optional description of the workflow
          - remote (int): the remote status of the workflow
          - manual_remote (int): if the \a remote status has been manually changed
          - workflow_modules (*list<string>): a list of workflow modules
          - open (bool): if the current workflow is open for processing now
          - autostart (int): the autostart value
          - manual_autostart (bool): a boolean flag set if the \c autostart value has been changed manually, in which \
            case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
          - max_instances (*int): a value limiting the maximum number of execution instances that can run at once
          - enabled (bool): if the worklfow is currently enabled for execution
          - sla_threshold (int): the nubmne of seconds that workflow orders should receive a final status
          - has_detach (bool): if the workflow has detach logic
          - code (*string): workflow code, if any
          - language (string): the programming language for the workflow code
          - language_info (*hash[any] UndefinedHash): any language-specific information for the wokflow code
          - class_name (*string): the workflow class's name, if any
          - staticdata_type_path (*string): the type path name for the workflow's static data, if any
          - errorfunction_instanceid (*int): the error function instance ID, if any
          - attach_func_instanceid (*int): the attach function instance ID, if any
          - detach_func_instanceid (*int): the deatch function instance ID, if any
          - onetimeinit_func_instanceid (*int): the one time init function instance ID, if any
          - errhandler_func_instanceid (*int): the error handler function instance ID, if any
          - loggerid (*int): the logger ID, if any
          - deprecated (bool): the deprecated flag
          - created (date): the creation date
          - custom_status_desc (*string): the custom status description, if any
          - hierarchy_level (int): the level in the workflow order hierarchy
          - error_count (int): number of errors
          - warning_count (int): number of warnings
        - AuditEvents (*list<hash[any] UndefinedHash>): a list of @ref rest_audit_info_hash "audit information hashes"
        - LastModified (date): the last modified date/time of the workflow order
        - staticdata_type_path (*string): the type path name for the workflow's static data, if any
        - actions (*list<string>): a list of possible actions on the workflow
        - notes (*list<hash NoteInfo>): a list of notes saved against the order
          - saved (bool): indicates if the note has already been synchronized to the database
          - username (string): the username of the user who created the note or \c "system" in case it was created \
            automatically
          - note (string): the note text
          - created (date): the creation date of the note
          - modified (date): the modified date of the note
        @ENDSCHEMA

        @par Description
        Returns a hash of information about the current workflow order data instance.

        @par Return Value
        This API returns a hash with the following keys:
        - \c name: the name of the workflow
        - \c version: the version of the workflow
        - \c author: the author of the workflow
        - \c workflow_instanceid: the workflow order instance ID
        - \c workflowid: the ID of the workflow
        - \c workflowstatus: the status of the workflow order (see @ref StatusDescriptions for possible values)
        - \c status_sessionid: the ID of the Qorus application session managing the workflow order data or 0 if none
        - \c parent_workflow_instanceid: the workflow order instance ID of the parent order for this workflow or @ref null if none
        - \c subworkflow: if 1, indicates that the \c parent_workflow_instanceid is the parent workflow order in a subworkflow relationship
        - \c synchronous: if 1, indicates that the order is being executed synchronously
        - \c errors: the number of errors raised against the order
        - \c business_error: a boolean flag indicating if the workflow order has an error status due to a business error
        - \c workflowstatus_orig: if the order status is @ref OMQ::StatBlocked or @ref OMQ::StatCanceled, this value will reflect the original status of the workflow order (see @ref StatusDescriptions for possible values)
        - \c custom_status: a custom status for the order
        - \c scheduled: the scheduled date
        - \c priority: the priority of the workflow order
        - \c started: the date/time the order was created
        - \c completed: the date/time order processing completed
        - \c modified: the last modified date/time for the order
        - \c operator_lock: a string giving the username of the user with an operator lock on the order
        - \c note_count: the number of notes stored against the order
        - \c deprecated: a boolean value indicating if the workflow is deprecated or not; deprecated workflows are by default not displayed in the UI
        - \c autostart: the integer @ref wf_autostart "autostart value" for the workflow
        - \c manual_autostart: a boolean flag set if the \c autostart value has been changed manually, in which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - \c max_instances: a value limiting the maximum number of execution instances that can run at once
        - \c external_order_instanceid: a unique external key for the order
        - \c staticdata: a hash of @ref staticdata "workflow order static data"
        - \c dynamicdata: a hash of @ref dynamicdata "workflow order dynamic data" (if any)
        - \c stepdata: a list of step data information with the following keys:
          - \c name: the step name
          - \c version: the step version
          - \c stepid: the step ID
          - \c steptype: the step type
          - \c arraytype: the step array type
          - \c data: list of hashes of the @ref stepdata "dynamic step data" per step index
        - \c keys: a hash of @ref wf_keylist "workflow order keys" and values
        - \c warning_count: the number of warnings raised against the order
        - \c error_count: the number of errors raised against the order
        - \c retry_count: the number of times the order was subject to a @ref OMQ::StatRetry "RETRY" status due to a technical error
        - \c StepInstances: a list of step hashes giving information about the execution status of @ref steps "workflow steps"; each element is a hash with the following keys:
          - \c workflow_instanceid:
          - \c stepid: the ID of the step
          - \c ind: the step array index starting with 0
          - \c stepname: the name of the step
          - \c stepversion: the version of the step
          - \c steptype: @ref StepTypes "type" of the step
          - \c stepstatus: the current execution status of the step (see @ref StatusDescriptions for possible values)
          - \c retries: the number of retries executed on the step
          - \c skip: a boolean value indicating if the step logic was skipped
          - \c custom_status: a custom status for the step
          - \c started: the date/time the step was first executed
          - \c completed: the date/time step processing completed
          - \c function_instanceid: the function ID of the primary step function
          - \c subworkflow_instanceid: the workflow order ID of any subworkflow order instance (for bound subworkflow steps only)
          - \c business_error: a boolean flag indicating if the step has an error status due to a business error
        - \c ErrorInstances: a list of hashes giving information about errors and warnings raised against the order; each element is a hash with the following keys:
          - \c error_instanceid: a unique ID for the error
          - \c workflow_instanceid: the workflow order instance ID
          - \c stepid: the stepid where the error was raised
          - \c ind: the step array index starting with 0 where the error was raised
          - \c severity: the severity of the error (see @ref ErrorSeverityCodes for possible values)
          - \c retry: 1 if the error caused a retry
          - \c error: the string error code for the error
          - \c description: an optional description of the error
          - \c info: an optional string providing additional information about the error
          - \c business_error: a boolean flag indicating if the error is a business error
          - \c created: the date/time the error was created
        - \c HierarchyInfo: a hash of workflow order information; the keys are workflow order instance IDs for all workflow orders linked to each other through parent-child relationships in the hierarchy of the current workflow order; the values are order information hashes similar to the top-level of the return value of this API
        - \c AuditEvents: a list of @ref rest_audit_info_hash "audit information hashes"
        - \c LastModified: the last modified date/time of the workflow order
        - \c actions: a list of possible actions on the workflow
        - \c notes: a list of notes saved against the order; each element is a @ref rest_order_note_hash
    */

    /** @REST PUT action=updateDynamicData

        @par Description
        Updates the @ref dynamicdata "dynamic data" for an existing order by merging the data passed in the \a newdata
        argument to the existing dynamic data hash in an atomic operation

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c newdata: (hash) data to be merged with the existing @ref dynamicdata "dynamic data" for the current
          workflow order

        @par Return Value
        This API returns \c "OK" upon successful execution

        @since Qorus 5.1.10
    */
    hash<HttpHandlerResponseInfo> putUpdateDynamicData(hash<auto> cx, *hash<auto> ah) {
        SM.updateDynamicData(cx, wf.workflow_instanceid, ah.newdata);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=yamlUpdateDynamicData

        @par Description
        Updated the @ref dynamicdata "dynamic data" for an existing order using a YAML-serialized string as a hash value
        to be merged with the existing dynamic data in an atomic operation

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c newdata: (YAML-serialized string) the new @ref dynamicdata "dynamic data" to be added to the dynamic data
          for the current workflow order as a YAML-serialized string

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>404 Bad Request</b></tt>: \c DYNAMIC-DATA-ERROR: this error is returned if the \a newdata argument is
          not a string or if the string is not valid YAML

        @since Qorus 5.1.10
    */
    hash<HttpHandlerResponseInfo> putYamlUpdateDynamicData(hash<auto> cx, *hash<auto> ah) {
        if (ah.newdata.typeCode() != NT_STRING)
            throw "DYNAMIC-DATA-ARG-ERROR", sprintf("expecting type \"string\" for the \"newdata\" arg; got type %y "
                "instead", ah.newdata.type());

        try {
            ah.newdata = parse_yaml(ah.newdata);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "YAML-PARSER-ERROR") {
                throw "DYNAMIC-DATA-ARG-ERROR", ex.desc;
            }
            rethrow;
        }
        return putUpdateDynamicData(cx, ah);
    }

    /** @REST PUT action=updateDynamicDataPath

        @par Description
        Updates the @ref dynamicdata "dynamic data" for an existing order by setting the value provided by the \a path
        argument with the value provided by the \a value argument in the existing dynamic data hash in an atomic
        operation

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c path: (string) the path to the data to be updated
        - \c value: (auto) any value to be updated at the location provided by \a path

        @par Return Value
        This API returns \c "OK" upon successful execution

        @since Qorus 5.1.10
    */
    hash<HttpHandlerResponseInfo> putUpdateDynamicDataPath(hash<auto> cx, *hash<auto> ah) {
        if (ah.path.typeCode() != NT_STRING)
            throw "DYNAMIC-DATA-ARG-ERROR", sprintf("expecting type \"string\" for the \"path\" arg; got type %y "
                "instead", ah.newdata.type());

        SM.updateDynamicDataPath(cx, wf.workflow_instanceid, ah.path, ah.value);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=yamlUpdateDynamicDataPath

        @par Description
        Updates the @ref dynamicdata "dynamic data" for an existing order by setting the value provided by the \a path
        argument with the value provided by the \a value argument as a YAML-serialized string in the existing dynamic
        data hash in an atomic operation

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c path: (string) the path to the data to be updated
        - \c value: (string) a YAML-serialized value to be used to update dynamic data at the location provided by
          \a path

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>404 Bad Request</b></tt>: \c DYNAMIC-DATA-ERROR: this error is returned if the \a value argument is
          not a string or if the string is not valid YAML

        @since Qorus 5.1.10
    */
    hash<HttpHandlerResponseInfo> putYamlUpdateDynamicDataPath(hash<auto> cx, *hash<auto> ah) {
        if (ah.path.typeCode() != NT_STRING)
            throw "DYNAMIC-DATA-ARG-ERROR", sprintf("expecting type \"string\" for the \"path\" arg; got type %y "
                "instead", ah.newdata.type());

        auto value;
        try {
            value = parse_yaml(ah.value);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "YAML-PARSER-ERROR") {
                throw "DYNAMIC-DATA-ARG-ERROR", ex.desc;
            }
            rethrow;
        }

        SM.updateDynamicDataPath(cx, wf.workflow_instanceid, ah.path, value);
        return RestHandler::makeResponse(200, "OK");
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV6(name, type);
    }
}

/** @REST /v6/orders (/v5/orders)

    This URI path provides information and actions related to workflow order data.
*/
class GlobalOrderRestClassV6 inherits GlobalOrderRestClassV5 {
    private *QorusRestClass internGetOrderInstanceRestClass(hash<auto> h) {
        return new WorkflowOrderInstanceRestClassV6(h);
    }
}

/** @REST /v6/workflows/{id_or_name} (/v5/workflows/{id_or_name})

    This REST URI path provides actions and information about a particular workflow.
*/
class WorkflowDefinitionRestClassV6 inherits WorkflowDefinitionRestClassV5 {
    constructor(hash<auto> wf) : WorkflowDefinitionRestClassV5(wf) {
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV6(name, type);
    }
}

/** @REST /v6/workflows (/v5/workflows)

    This URI path allows workflows to be queried and for actions on multiple workflows to be performed;
    this is the URI path parent of workflow-specific actions as well.
*/
class WorkflowRestClassV6 inherits WorkflowRestClassV5 {
    private *QorusRestClass internGetOrderInstanceRestClass(hash<auto> h) {
        return new WorkflowOrderInstanceRestClassV6(h);
    }

    private *QorusRestClass internGetWorkflowDefinitionSubclass(hash<auto> wf) {
        return new WorkflowDefinitionRestClassV6(wf);
    }
}

/** @REST /v6/services/{id_or_name} (/v5/services/{id_or_name})

    This REST URI path provides actions and information related to Qorus services.
*/

    /** @REST GET

        @par Description
        Returns information about the current service

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c lib_source: (optional) parsed with @ref Qore::parse_boolean(); if @ref True "True", then the source code
          for all library objects is returned
        - \c method_source: (optional) parsed with @ref Qore::parse_boolean(); if @ref True "True", then the source
          code for all methods is returned in the \c body key in each @ref rest_service_method_hash

        @par Return Value
        This API returns a hash describing the service with the following keys:
        - \c alerts: a list of alerts raised against the service; each list element is a @ref rest_alert_hash (may be
          empty)
        - \c author: the author of the service (if any)
        - \c autostart: a boolean value indicating if the service should be autostarted or not
        - \c connections: a list of connection objects that this service depends on; each list element is a
          @ref rest_conndep_hash (may be empty)
        - \c created: the date/time the service was created
        - \c description: the description of the service (if any)
        - \c enabled: a boolean flag indicating if the service is enabled or not; disabled services cannot be loaded
        - \c groups: a list of @ref rbacgroups "interface groups" that the service belongs to; each list element is a
          @ref rest_interface_group_hash (may be empty)
        - \c latest: a boolean flag indicating if the current contextual service is the latest service of its type and
          name
        - \c log_url: a complete URL to the websocket source for the service log
        - \c mappers: a list of @ref mappers "mappers" associated with the service (can be @ref nothing); each mapper
          element is a @ref rest_mapper_hash
        - \c manual_autostart: a boolean flag set if the \c autostart value has been changed manually, in which case
          the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - \c methods: a list of @ref rest_service_method_hash elements
        - \c modified: the date/time the service was last modified
        - \c name: the name of the service
        - \c options: a hash of options set on the service
        - \c parse_options: a list of @ref parse_options "symbolic parse options" for the
          @ref svcprograms "service program container"
        - \c processes: a list of hashes of process information, in case the service is running remotely in one or
          more a @ref qsvc "qsvc" processes
        - \c remote: a boolean value indicating if the service is run as an external process or not
        - \c resource_files: a list of resource file hashes (if any); each list element is a hash with the following
          keys:
          - \c name: the name of the resource
          - \c type: the type code for the resource
        - \c resources: a @ref rest_service_resource_hash
        - \c serviceid: the service ID
        - \c status: the status of the service; one of:
          - \c "loaded": loaded but not running
          - \c "running": loaded and running with at least one service thread
          - \c "unloaded": not loaded
        - \c state: a hash of saved service state data (if any); see @ref svc_save_state_data() for more info
        - \c stateless: always @ref False in the Community Edition
        - \c threads: the number of threads running in the service
        - \c type: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        - \c version: the version of the service
        - \c vmaps: a list of @ref value-maps "value maps" associated with the service (can be @ref nothing); each
          value map element is a @ref rest_vmap_hash
    */

/** @REST /v6/services/{id_or_name} (/v5/services/{id_or_name})

    This REST URI path provides actions and information related to Qorus services.
*/
class ServiceDefinitionRestClassV6 inherits ServiceDefinitionRestClassV5 {
    constructor(hash<auto> sh) : ServiceDefinitionRestClassV5(sh) {
    }
}

/** @REST /v6/services (/v5/services)

    This REST URI path provides actions and information related to Qorus services;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class ServiceRestClassV6 inherits ServiceRestClassV5 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = ServiceRestClass::staticGetServiceId(arg);
        *hash<auto> svc = ServiceRestClass::staticGetService(cx, id, ah, 6);
        if (!svc) {
            return;
        }

        return new ServiceDefinitionRestClassV6(svc);
    }

    /** @REST GET

        @par Description
        Returns a list of service hashes according to the arguments passed.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c status: one of:
          - \c "running": for only running services (loaded with at least one active thread)
          - \c "loaded": all loaded services (also running services)
          - \c "unloaded": only services not loaded
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of service names is
          returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with
          service names and descriptions is returned
        - \c tags: optional; a hash of tags to match; only workflows matching at least one of the tags will be
          returned; use <tt>tag=value</tt> format as the value of this option
        - \c tag_case_insensitive: optional; parsed with @ref Qore::parse_boolean(); if @ref True then tag value
          comparisons are made with case-insensitive comparisons
        - \c tag_partial_match: optional; parsed with @ref Qore::parse_boolean(); if @ref True then tag value
          comparisons succeed if the value given as the tag value appears anywhere in the object's tag of the same
          name

        @par Return Value
        If neither \a list nor \a short are used, then a list of hashes is returned, one element for each
        service; each hash in the returned has the following keys:
        - \c type: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        - \c name: the service name
        - \c version: the service version
        - \c patch: the service patch string (if any)
        - \c desc: the service description
        - \c author: the author of the service (if any)
        - \c serviceid: the service ID
        - \c stateless: always @ref False in the Community Edition
        - \c parse_options: a list of @ref parse_options "symbolic parse options" for the
          @ref svcprograms "service program container" (if any)
        - \c status: the status of the service; one of:
          - \c "loaded": loaded but not running
          - \c "running": loaded and running with at least one service thread
          - \c "unloaded": not loaded
        - \c log: the complete path to the service log file
        - \c threads: the number of active threads in the service
        - \c autostart: boolean value indicating if the service should be autostarted or not
        - \c manual_autostart:  boolean flag set if the \c autostart value has been changed manually, in which case
          the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - \c loaded: date/time the service was loaded
        - \c methods: a list of hashes for each service method; each hash element has the following keys:
          - \c name: the name of the method
          - \c desc: a description of the method
        - \c resources: a @ref rest_service_resource_hash (if any)
        - \c resource_files: a list of hashes giving service resource file information (if any); each list element has
          the following keys:
          - \c type: the type code for the service resource
          - \c name: the name of the service resource
        - \c options: a hash of options set on the service
        - \c groups: a list of @ref rbacgroups "interface groups" that the service belongs to; each list element is a
          @ref rest_interface_group_hash (may be empty)
        - \c alerts: a list of alerts raised against the service; each list element is a @ref rest_alert_hash (may be
          empty)
        - \c lib: a @ref rest_library_object_hash
        - \c log_url: a complete URL to the websocket source for the service log
        - \c enabled: a boolean flag indicating if the service is enabled or not; disabled services cannot be loaded
        - \c connections: a list of connection objects that this service depends on; each list element is a
          @ref rest_conndep_hash (may be empty)
        - \c tags: any tags associated with the service

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        if (*hash<HttpHandlerResponseInfo> err = parseTagOptions(\ah)) {
            return err;
        }
        return RestHandler::makeResponse(200, ServiceRestClass::staticGetServices(cx, ah, 6, ah));
    }

    /** @REST PUT action=load

        @par Description
        Loads and initializes one or more services if not already loaded.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more service names or IDs to start; a comma-separated string will be split into a
          list

        @par Return Value
        This API returns a hash with the following keys:
        - \c err: @ref True if at least one service load command failed, @ref False if all load commands were
          successful
        - \c desc: a description of the result of the operation
        - \c results: a list of hashes giving the result of each load request; each hash has the following keys:
          - \c arg: the service ID or name (argument for the load operation)
          - \c loaded: a boolean giving the result of the operation
          - [\c already_loaded]: (only present if \c loaded is @ref True) @ref True if the service was already loaded
            before this call, @ref False if loaded with this call
          - [\c serviceid]: the service ID
          - [\c type]: the type of the service; one of:
            - \c "system": for system services
            - \c "user": for user services
          - [\c name]: the name of the service
          - [\c version]: the version of the service
          - \c info: information abouit the operation; if the operation failed, a formatted error string will appear
            here; possible failure reasons:
            - \c "SERVICE-ERROR": the given service cannot be loaded (does not exist, error initializing the service)

        @see
        - @ref rest_api_PUT_latest_services_unload
        - @ref rest_api_PUT_latest_services__id_or_name__load
        - @ref rest_api_PUT_latest_services__id_or_name__unload
    */
    hash<HttpHandlerResponseInfo> putLoad(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids) {
            throw "SERVICE-LOAD-ERROR", "missing \"ids\" argument for service IDs to load";
        }

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING) {
            ah.ids = ah.ids.split(",");
        }

        list<hash<auto>> rv = ();

        # permission check hash
        hash<auto> pch;

        # list of failed services
        list<string> failed;

        foreach auto arg in (ah.ids) {
            *hash<auto> sh;
            int id = ServiceRestClass::staticGetServiceId(arg, False, \sh);
            if (!id) {
                failed += sprintf("unknown service %y", arg);
                rv += {
                    "arg": arg,
                    "loaded": False,
                    "info": "unknown service",
                };
                continue;
            }

            try {
                if (!sh) {
                    sh = Qorus.qmm.lookupService(id, True);
                    if (!sh) {
                        failed += sprintf("unknown service %y", arg);
                        rv += {
                            "arg": arg,
                            "loaded": False,
                            "info": sprintf("SERVICE-ERROR: serviceid %d is unknown", id),
                        };
                        continue;
                    }
                }

                if (!pch.(sh.type)) {
                    pch.(sh.type) = True;
                }

                # see if the service is already loaded
                *hash<auto> sih = UserApi::getServiceInfo(sh.type, sh.name);

                if (!sih)
                    api.("omq." + sh.type + ".service." + sh.name + ".init")();
                rv += {
                    "arg": arg,
                    "loaded": True,
                    "already_loaded": boolean(sih),
                    "serviceid": id,
                    "type": sh.type,
                    "name": sh.name,
                    "version": sh.version,
                    "info": sprintf("%s %s v%s (%d) %sloaded", sh.type, sh.name, sh.version, id,
                        sih ? "was already " : ""),
                };
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "AUTHORIZATION-ERROR") {
                    failed += sprintf("no permission to load service %s v%s (%d) (%y)", sh.name, sh.version,
                        sh.serviceid, arg);
                } else {
                    failed += sprintf("%y: %s: %s", arg, ex.err, ex.desc);
                }

                rv += {
                    "arg": arg,
                    "loaded": False,
                    "serviceid": id,
                    "type": sh.type,
                    "name": sh.name,
                    "version": sh.version,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                };
            }
        }

        string desc;
        if (failed) {
            if (failed.size() == 1) {
                desc = sprintf("the following service failed to load: %s", failed[0]);
            } else {
                desc = sprintf("the following services failed to load: %s", (foldl $1 + ", " + $2, failed));
            }
        } else {
            desc = "OK";
        }

        hash<auto> resp = {
            "err": failed ? True : False,
            "desc": desc,
            "results": rv,
        };

        return RestHandler::makeResponse(200, resp);
    }
}

/** @REST /v6/system/templates
*/
class TemplatesRestClassV6 inherits QorusRestClass {
    string name() {
        return "templates";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            # otherwise look for direct attributes of the type
            *hash<auto> h = QorusExpressionTemplateMap{arg};
            if (h) {
                return new AttributeRestClass(h);
            }
        }
    }

    /** @REST GET

        @SCHEMA
        @summary Returns template information

        @desc Returns template information

        @params
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - filter (*int): a bitfield of @ref TemplateContextValues to filter the results: 1: workflow context, \
          2: service context, 4: job context, 8: generic context, 7: interface context, 15: all contexts

        @return (*list<hash TemplateInfo>): a list of template info hashes
        - name (string): the name of the template
        - desc (string): a markdown description of the template
        - doc_url (string): a URL to online documentation for the template
        - valid_context (int): a bitfield of @ref TemplateContextValues giving the valid context for the template
        - access (int): a bitfield of read/write access information for the template; 1 = read, 2 = write
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        int filter = exists ah.filter ? doGetInt(ah, "filter") : QETC_ALL;
        list<hash<auto>> rv = (map $1, QorusExpressionTemplateMap.iterator(),
                $1.access & QETA_READ && $1.valid_context & filter);
        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v6/system (/v5/system)

    This REST URI path provides actions and information for system functionality
*/
class SystemRestClassV6 inherits SystemRestClassV5 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "templates") {
            return new TemplatesRestClassV6();
        }
        return SystemRestClassV5::subClassImpl(arg, cx, ah);
    }

    hash<auto> internGetInfo(hash<auto> cx) {
        return SystemRestClassV5::internGetInfo(cx) + {
            "api_version": "v6",
            "templates": (map $1, QorusExpressionTemplateMap.iterator(),
                $1.access & QETA_READ),
        };
    }

    /** @REST GET

        @SCHEMA
        @summary Returns a hash of system information

        @desc Returns a hash of system information

        @return (hash QorusSystemInfo): Current system information
        - instance-key (string): the system instance key
        - session-id (int): the application session id
        - omq-version (string): the version of the Qorus server
        - omq-build (string): the git hash of the current Qorus build
        - omq-version-code (int): an integer code for the Qorus version as MMmmSS, where MM = the major version, \
          mm = the minor version, SS == the sub version
        - qore-version (string): the version of the underlying qore library used
        - modules (hash[hash QorusModuleInfo] QorusModuleSetInfo): a hash of module info as returned by \
          @ref Qore::get_module_hash(); keys are module names
        - datamodel-version (string): the version of the datamodel expected by the server
        - omq-schema (string): \c "user@dbname" string for the system \c "omq" datasource
        - omq-driver (string): driver name for the system \c "omq" datasource
        - omq-db-version (any): database server version for the system \c "omq" datasource; the data type depends on \
          the driver
        - omquser-schema (string): \c "user@dbname" string for the \c "omquser" datasource
        - omquser-driver (string): driver name for the \c "omquser" datasource
        - omquser-db-version (any): database server version for the \c "omquser" datasource; the data type depends \
          on the driver
        - starttime (date): date and time the qorus-core server was started
        - hostname (string): hostname where the qorus-core server is running
        - pid (int): PID of the server process
        - threads (int): count of currently active threads in qorus-core
        - schema-properties (hash QorusSchemaInfo): information about the system schema
        - omq_dir (string): the full path on the host to the Qorus application directory
        - cache_size (int): The number of entries in the workflow order data cache
        - shutting_down (bool): indicates if the system is shutting down or not
        - build-type (string): the build type (normally \c "Production" for public releases)
        - runtime-properties (*hash[any] UndefinedHash): any runtime properties set on the instance
        - alert-summary (hash SystemAlertInfo): summary of alerts
        - debug (bool): indicates if debugging is enabled for the instance
        - debug-internals (bool): indicates if internal debugging is enabled for the instance
        - health (string): a string indicating the health status of the instance
        - ui-compatibility-version (string): a string indicating the UI compatibility for the instance
        - plugins (*list<string>): any installed plugins
        - edition (string): \c Community for Qorus Integration Engine(R) Community Edition
        - system_log_url (string): a WebSocket URL for system log streaming
        - audit_log_url (string): a WebSocket URL for audit log streaming
        - http_log_url (string): a WebSocket URL for HTTP log streaming
        - mon_log_url (string): a WebSocket URL for connection monitor log streaming
        - alert_log_url (string): a WebSocket URL for alert log streaming
        - api_version (string): the current API version
        - cluster_info (hash[hash QorusClusterInfo] QorusClusterSetInfo): cluster info; keys are node (container) names
        - processes (hash[hash QorusProcessInfo] QorusProcessSetInfo): process info; keys are process IDs
        - workflow_total (int): total number of workflows cached
        - workflow_alerts (int): number of workflows with alerts
        - service_total (int): total number of services cached
        - service_alerts (int): number of services with alerts
        - job_total (int): total number of jobs cached
        - job_alerts (int): number of jobs with alerts
        - remote_total (int): number of remote Qorus connections
        - remote_alerts (int): number of remote Qorus connections with alerts
        - user_total (int): number of user connections
        - user_alerts (int): number of user connections with alerts
        - datasource_total (int): number of datasource connections
        - datasource_alerts (int): number of datasource connections with alerts
        - order_stats (list<hash UndefinedHash>): list of order status information
        - loggerParams (hash[any] UndefinedHash): logger param info
        - auth_label_values (list<string>): list of auth label values
        - grafana_panel_ids (*hash[any] UndefinedHash): hash of grafana panel ID info
        - limits (hash QorusLimitInfo): Qorus system limit information
        - default_mapper_keys (hash[any] UndefinedHash): default mapper key info
        - pipeline_options (hash[any] UndefinedHash): pipeline option info
        - stack_size (int): thread stack size
        - templates (list<hash TemplateInfo>): a list of template info hashes
          - name (string): the name of the template
          - desc (string): a markdown description of the template
          - doc_url (string): a URL to online documentation for the template
          - valid_context (int): a bitfield of @ref TemplateContextValues giving the valid context for the template
          - access (int): a bitfield of read/write access information for the template; 1 = read, 2 = write
        @ENDSCHEMA
    */
}

/** @REST /v6/classes/{id_or_name} (/v5/classes/{id_or_name})

    This REST API path provides actions and information about specific class objects
*/
class ClassDefinitionRestClassV6 inherits ClassDefinitionRestClass {
    constructor(hash<auto> h) : ClassDefinitionRestClass(h) {
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current class object

        @par Return Value
        This API returns a hash with the following keys:
        - \c name: the name of the class object
        - \c version: the version of the class object
        - \c classid: the class object ID
        - \c description: the description of the class
        - \c author: the author of the class
        - \c body: the source code for the class object
        - \c created: the date/time the class was created
        - \c modified: the date/time the class was modified
        - \c createdby: (deprecated) always \c "omq"
        - \c modifiedby: (deprecated) always \c "omq"
        - \c tags: any user-defined tags on the class object
        - \c source: the source file that the class object was created from
        - \c offset: the offset in the source file for the source of the class object
        - \c host: the hostname of the machine where the class object was loaded from
        - \c user: the OS user who loaded the class object
        - \c [edit_lock]: the connection ID of the WebSocket connection holding the edit lock
    */

    /** @REST DELETE

        @par Description
        Deletes the class

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        return CreatorClassDefinitionRestClass::staticDeleteClass(h, cx, ah);
    }
}

/** @REST /v6/classes (/v5/classes/)

    This REST API path provides actions and information about Qorus class objects
*/
class ClassRestClassV6 inherits ClassRestClassV5 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id;
        if (arg !~ /^[[:digit:]]+$/u) {
            *int clsid = Qorus.qmm.tryGetClassId(arg);
            if (!clsid) {
                return;
            }
            id = clsid;
        } else {
            id = arg.toInt();
        }
        *hash<auto> h = ClassRestClass::staticGetClassInfo(id, 6);
        return h ? new ClassDefinitionRestClassV6(h) : NOTHING;
    }

    *hash<auto> doGetClassMap() {
        return Qorus.qmm.getClassMap(True);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of all classes

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of class names is
          returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with
          class names, versions, and IDs is returned
        - \c tags: optional; a hash of tags to match; only workflows matching at least one of the tags will be
          returned; use <tt>tag=value</tt> format as the value of this option
        - \c tag_case_insensitive: optional; parsed with @ref Qore::parse_boolean(); if @ref True then tag value
          comparisons are made with case-insensitive comparisons
        - \c tag_partial_match: optional; parsed with @ref Qore::parse_boolean(); if @ref True then tag value
          comparisons succeed if the value given as the tag value appears anywhere in the object's tag of the same
          name

        @par Return Value
        This API returns a list of hashes with the following keys (if neither \c list nor \c short options are passed
        as above):
        - \c classid: the class ID
        - \c name: the name of the class
        - \c version: the version of the class
        - \c description: the description of the class object
        - \c author: the author of the class object
        - \c created: the date/time the class object was created
        - \c modified: the date/time the class object was modified
        - \c source: the source file that the class object was created from
        - \c line: the offset in the source file for the source of the class object
        - \c edit_lock: the connection ID of the connection holding the edit lock, if any
    */
}

/** @REST /v6/dataprovider/factories/{factory}/provider/.../request-fields

    This URI path provides access information for a particular data request data type
*/
class DataProviderTypeFieldsRestClass inherits DataProviderTypeRestClassV5 {
    constructor(string name, AbstractDataProviderType type) : DataProviderTypeRestClassV5(name, type) {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # return fields directly
        *AbstractDataField field = type.getField(arg);
        if (field) {
            return doGetDataProviderTypeRestClass(arg, field.getType());
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

    hash<auto> doGetInfo(*hash<auto> ah) {
        return DataProviderTypeFieldsRestClass::doGetInfo(type, name, ah);
    }

    static hash<auto> doGetInfo(AbstractDataProviderType type, string name, *hash<auto> ah) {
        bool soft = parse_boolean(ah.soft);
        hash<auto> info = soft ? type.getSoftType().getInfo() : type.getInfo();
        *list<hash<auto>> fields = map $1, info.fields.iterator();
        return {
            "typename": name,
            "fields": fields,
        };
    }

    static hash<auto> doGetInfo(AbstractDataField field, *hash<auto> ah) {
        bool soft = parse_boolean(ah.soft);
        if (soft) {
            field = field.getSoftType();
        }
        if (DataProviderRestClass::checkOption(ah, "context", "ui")) {
            *hash<auto> fields = DataProviderTypeFieldsRestClass::doGetFieldInfo(field.getType().getFields(), ah);
            return {
                "type": field.getName(),
                "desc": field.getDescription(),
                "required": field.isMandatory(),
            } + fields
                ? {
                    "fields": fields,
                }
                : NOTHING;
        } else {
            return {
                "typename": field.getName(),
                "fields": DataProviderTypeFieldsRestClass::doGetFieldInfo(field.getType().getFields(), ah),
            };
        }
    }

    static *hash<auto> doGetFieldInfo(*hash<string, AbstractDataField> fields, *hash<auto> ah) {
        if (DataProviderRestClass::checkOption(ah, "context", "ui")) {
            hash<auto> rv;
            foreach AbstractDataField field in (fields.iterator()) {
                hash<auto> info = field.getInfo();
                string name = field.getName();
                rv{name} = DataProviderTypeRestClassV6::doGetInfo(field.getType(), name, ah) + {
                    "desc": info.desc,
                };
                if (exists info.default_value) {
                    rv{name}.default_value = info.default_value;
                }
                if (info.fields) {
                    rv{name}.fields = DataProviderTypeFieldsRestClass::doGetFieldInfo(info.fields, ah);
                }
            }
            return rv;
        }
        return map {$1.getName(): $1.getInfo()}, fields.iterator();
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV6(name, type);
    }
}

/** @REST /v6/dataprovider/factories/{factory}/provider (/v5/dataprovider/factories/{factory}/provider)

    This URI path provides access to a data provider created from a data provider factory

    @par Arguments
    This URI path element is reachable only if a provider can be created from the factory; to create the provider,
    the following hash argument is removed from the argument list before passing onward for processing:
    - \c provider_options: the options to be passed to the factory creation method to create the provider
*/
class DataProviderRestClassV6 inherits DataProviderRestClassV5 {
    constructor(AbstractDataProvider provider) : DataProviderRestClassV5(provider) {
    }

    /** @REST PUT action=apiEndpoints

        @SCHEMA
        @summary Returns a list of request/response endpoint information for the data provider

        @desc Returns a list of request/response endpoint information for the data provider

        @params
        - Q context (*list<string>): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type; also \c ui: to return a format for the UI
        - soft (*bool): soft types are returned
        - provider_options (*hash[any] UndefinedHash): a hash of constructor options for a data provider when \
          following the URI path through a data provider factory that takes constructor options

        @return (list<hash EndpointInfo>): a list of API endpoints supported by the data provider
        - endpoint: (string) the relative data provider path to the endpoint
        - request_type: (hash) a type hash for the request
        - response_type: (hash) a type hash for the response
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putApiEndpoints(hash<auto> cx, *hash<auto> ah) {
        list<hash<auto>> rv = ();
        # scan data provider for request-response endpoints
        scanProviderForApiEndpoints(\rv, "/", provider, ah);
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=Description

        @SCHEMA
        @summary Returns data provider information

        @desc Returns data provider information

        @params
        - Q context (*list<string>): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type; also \c ui: to return a format for the UI
        - provider_options (*hash[any] UndefinedHash): any options to be passed to a factory creation method when \
          accessing this URI endpoint through a factory

        @return (hash DataProviderInfo): information about the current data provider

        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putDescription(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, doGetInfo(ah));
    }

    /** @REST PUT action=childDetails

        @SCHEMA
        @summary Returns data provider information with details in the \c children key

        @desc Returns data provider information

        @params
        - Q context (*list<string>): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type; also \c ui: to return a format for the UI

        @return (hash DataProviderChildDetailInfo): information about the current data provider
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putChildDetails(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, doGetDetails(ah));
    }

    /** @REST GET action=childDetails

        @SCHEMA
        @summary Returns data provider information with details in the \c children key

        @desc Returns data provider information

        @params
        - Q context (*list<string>): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type; also \c ui: to return a format for the UI

        @return (hash DataProviderChildDetailInfo): information about the current data provider
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
        - search_logic_capabilities (int): a bitfield of supported search logic capabilities
        - mapper_keys (*hash[any] UndefinedHash): a hash of mapper key information
        - desc (string): the description of the data provider
        - type (string): the type (class name) of the data provider
        - constructor_options (*hash[any] UndefinedHash): any constructor options supported by the data provider
        - create_options (*hash[any] UndefinedHash): any record creation options supported by the data provider
        - upsert_options (*hash[any] UndefinedHash): any record upsert options supported by the data provider
        - search_options (*hash[any] UndefinedHash): any record search options supported by the data provider
        - child_create_options (*hash[any] UndefinedHash): any child creation options supported by the data provider
        - children (*list<hash DataProviderSummaryInfo>): a list of any data provider children
          - name (string): the name of the data provider
          - desc (string): the description of the data provider
          - type (string): the type (class name) of the data provider
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
          - supports_search_expressions (bool): if the data provider supports advanced search expressions
          - supports_observable (bool): if the data provider supports the observer pattern / event API
          - supports_messages (string): if the data provider supports output messages; values are: \c NONE (messages \
            not supported), \c SYNC (messages supported 1:1 with observed events), \c ASYNC (messages supported, no \
            connection to observed events)
          - children_can_support_apis (bool): if the data provider can provide children that support APIs
          - children_can_support_records (bool): if the data provider can provide children that support records
          - children_can_support_observers (bool): if the data provider can provide children that support event observation
          - children_can_support_messages (bool): if the data provider can provide children that support messages
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> getChildDetails(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, doGetDetails(ah));
    }

    static scanProviderForApiEndpoints(reference<list<hash<auto>>> rv, string path, AbstractDataProvider provider,
            *hash<auto> ah) {
        if (provider.supportsRequest()) {
            rv += {
                "endpoint": path,
                "request_type": DataProviderTypeRestClassV6::doGetInfo(provider.getRequestType(), "request", ah),
                "response_type": DataProviderTypeRestClassV6::doGetInfo(provider.getRequestType(), "response", ah),
            };
        }

        # scan children
        map DataProviderRestClassV6::scanProviderForApiEndpoints(\rv, path == "/" ? path + $1 : path + "/" + $1,
            provider.getChildProviderEx($1), ah), provider.getChildProviderNames();
    }

    # Returns information about the data provider
    hash<auto> doGetInfo(*hash<auto> ah, int apiver = 6) {
        return DataProviderRestClass::doGetInfo(provider, ah, apiver);
    }

    # Returns information about the data provider
    hash<auto> doGetDetails(*hash<auto> ah, int apiver = 6) {
        return DataProviderRestClass::doGetInfo(provider, ah, apiver, True);
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV6(provider);
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV6(name, type);
    }

    private *QorusRestClass doSubClassArg(string arg, hash<auto> cx, *hash<auto> ah) {
        QDBG_LOG("DataProviderRestClassV6::doSubClassArg() m: %y arg: %y", cx.hdr.method, arg);
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (arg == "request-fields") {
                return new DataProviderTypeFieldsRestClass("request", provider.getRequestType());
            }
            if (arg == "response-fields") {
                return new DataProviderTypeFieldsRestClass("response", provider.getRequestType());
            }
        }
        return DataProviderRestClassV5::doSubClassArg(arg, cx, ah);
    }
}

/** @REST /v6/dataprovider/factories/{factory} (/v5/dataprovider/factories/{factory})

    This URI path provides access to data factory information
*/
class DataProviderFactoryRestClassV6 inherits DataProviderFactoryRestClassV5 {
    constructor(string name, AbstractDataProviderFactory factory) : DataProviderFactoryRestClassV5(name, factory) {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "provider") {
            processProviderArgs(\ah);
            process_factory_args(\ah);
            return doGetDataProviderRestClass(DataProvider::getFactoryObjectWithTemplate(name, ah.template_options,
                ah.provider_options));
        }

        if (arg == "provider_by_example") {
            processExampleArgs(\ah);
            processProviderArgs(\ah);

            return doGetDataProviderRestClass(factory.getProviderFromExample(ah.example, ah.provider_options));
        }

        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            hash<auto> info = doGetInfo(ah);
            if (info.hasKey(arg)) {
                return new AttributeRestClass(info{arg});
            }
        }
    }

    /** @REST GET action=providerExampleOutput

        @par Description
        Returns example records from the example input and factory constructor options

        @par Arguments
        This API takes the following hash arguments:
        - \c encoded_example: base-64-encoded string example input
        - \c provider_yaml_options: a string in the following format giving factory provider constructor options:
          \a key = base-64-encoded yaml value
    */
    hash<HttpHandlerResponseInfo> getProviderExampleOutput(hash<auto> cx, *hash<auto> ah) {
        processExampleArgs(\ah);
        processProviderArgs(\ah);

        QDBG_LOG("getProviderExampleOutput() opts: %y example: %y", ah.provider_options, ah.example);
        return RestHandler::makeResponse(200, factory.getExampleProviderRecordOutput(ah.example, ah.provider_options));
    }

    static private processExampleArgs(reference<*hash<auto>> ah) {
        if (ah.encoded_example) {
            ah.example = parse_base64_string_to_string(ah.encoded_example);
        }
        int type = ah.example.typeCode();
        if (type != NT_STRING && type != NT_BINARY) {
            throw "FACTORY-EXAMPLE-ARG-ERROR", sprintf("missing or invalid \"example\" argument; got type %y; "
                "expecting \"string\" or \"binary\"", ah.example.type());
        }
    }

    private processProviderArgs(reference<*hash<auto>> ah) {
        if (ah.provider_options.typeCode() == NT_STRING) {
            ah.provider_options = parse_to_qore_value(ah.provider_options);
        }
        if (ah.provider_options.typeCode() != NT_HASH) {
            remove ah.provider_options;
        }
        if (!ah.provider_options && (*string opts = (ah.provider_yaml_options =~ x/^{(.+)}$/[0]))) {
            QDBG_LOG("yaml opts: %y (%y)", ah.provider_yaml_options, opts);

            foreach string opt in (opts.split(",")) {
                (string key, string value) = (opt =~ x/^([^=]+)=(.+)$/);
                ah.provider_options{key} = parse_yaml(parse_base64_string_to_string(value));
            }

            QDBG_LOG("yaml opts parsed: %y", ah.provider_options);
            if (ah.provider_options.typeCode() != NT_HASH) {
                remove ah.provider_options;
            }
        }
        if (ah.provider_options) {
            ah.provider_options = ah.provider_options{keys factory.getInfo().provider_info.constructor_options ?? ()};
        }
    }

    private hash<auto> doGetInfo(*hash<auto> ah, int apiver = 6) {
        return DataProviderFactoryRestClass::doGetInfo(name, factory, ah, apiver);
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV6(provider);
    }
}

/** @REST /v6/dataprovider/factories (/v5/dataprovider/factories)

    This URI path provides access to data factory information
*/
class DataProviderFactoriesRestClassV6 inherits DataProviderFactoriesRestClassV5 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProviderFactory factory = DataProvider::getFactory(arg);
        if (factory) {
            return new DataProviderFactoryRestClassV6(arg, factory);
        }
    }

    /** @REST GET

        @par Description
        Returns data factory information

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c context: if \c "api" then only factories suitable for API management are returned
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of data provider factory
          names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of
          data provider factory information is returned
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *list<string> factory_list = sort(DataProvider::listFactories());
        bool for_api_management = DataProviderRestClass::checkOption(ah, "context", "api");
        bool for_api_call = DataProviderRestClass::checkOption(ah, "context", "apicall");
        if (exists ah."list" && parse_boolean(ah."list")) {
            if (for_api_management) {
                *list<hash<auto>> rv = doGetFactoryInfo(factory_list, ah);
                return RestHandler::makeResponse(200, (map $1.name, rv, $1.api_management));
            }
            if (for_api_call) {
                *list<hash<auto>> rv = doGetFactoryInfo(factory_list, ah);
                return RestHandler::makeResponse(200, (map $1.name, rv, $1.children_can_support_apis));
            }
            return RestHandler::makeResponse(200, factory_list);
        }
        *list<hash<auto>> rv = doGetFactoryInfo(factory_list, ah);
        if (for_api_management) {
            rv = map $1, rv, $1.api_management;
        }
        if (for_api_call) {
            rv = map $1, rv, $1.children_can_support_apis;
        }
        # return summary info
        if (exists ah.short && parse_boolean(ah.short)) {
            return RestHandler::makeResponse(200,
                map sprintf("%s: %s (%s)", $1.name, $1.provider_info.type, doGetCapString($1)), rv);
        }
        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v6/connections/{name}/provider (/v6/dataprovider/factories/{factory}/provider)

    This URI path provides access to a data provider created from a Qorus connection
*/

/** @REST /v6/dataprovider/types/.../{type}/type (/v5/dataprovider/types/.../{type}/type)

    This URI path provides access information for a particular data type
*/
class DataProviderTypeRestClassV6 inherits DataProviderTypeRestClassV5 {
    constructor(string name, *AbstractDataProviderType type) : DataProviderTypeRestClassV5(name, type) {
        QDBG_LOG("DataProviderTypeRestClassV6::constructor() %y type: %y", name, type ? type.getName() : "n/a");
    }

    /** @REST GET

        @par Description
        Returns data type information

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c soft: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the type is returned with
          soft types to be used as the target for a mapper
        - \c context: optional; if the value is \c "ui", then the return format will be in a format suitable for the
          UI
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, doGetInfo(ah));
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV6(name, type);
    }

    hash<auto> doGetInfo(*hash<auto> ah) {
        return DataProviderTypeRestClassV6::doGetInfo(type, name, ah);
    }

    static hash<auto> doGetInfo(AbstractDataProviderType type, string name, *hash<auto> ah) {
        if (DataProviderRestClass::checkOption(ah, "context", "ui")) {
            return DataProviderTypeRestClassV6::doGetUiContextInfo(type, name, ah);
        }
        bool soft = parse_boolean(ah.soft);
        return {
            "typename": name,
        } + (soft ? type.getSoftType().getInfo() : type.getInfo()) + {
            "or_nothing_type": type.isOrNothingType(),
            "locked": Qorus.qmm.isTypeLocked(name),
        };
    }

    static hash<auto> doGetUiContextInfo(AbstractDataProviderType type, string name, *hash<auto> ah) {
        bool soft = parse_boolean(ah.soft);
        if (soft) {
            type = type.getSoftType();
        }
        hash<auto> info = type.getInfo();
        hash<auto> rv += {
            "type": info.name,
        };
        # reformat info for the UI
        *hash<string, AbstractDataField> fields = type.getFields();
        if (fields) {
            rv.type = "hash";
            rv.arg_schema = DataProviderTypeRestClassV6::doGetFieldInfo(fields);
        } else if (info.name =~ /^\*?hash$/) {
            rv.type += "<auto>";
        }
        return rv;
    }

    static hash<auto> doGetFieldInfo(hash<string, AbstractDataField> fields) {
        hash<auto> rv;
        foreach AbstractDataField f in (fields.iterator()) {
            AbstractDataProviderType t = f.getType();
            hash<auto> field_info = {
                "type": t.getBaseTypeName(),
                "desc": f.getDescription(),
                "required": f.isMandatory(),
            };
            auto defval = f.getDefaultValue();
            if (exists defval) {
                field_info.default_value = defval;
            }
            if (*list<auto> allowed_values = f.getAllowedValues()) {
                field_info.allowed_values = map ("name": $1), allowed_values;
            }
            *hash<string, AbstractDataField> ffields = t.getFields();
            if (ffields) {
                field_info.type = "hash";
                field_info.arg_schema = DataProviderTypeRestClassV6::doGetFieldInfo(ffields);
            }
            rv{f.getName()} = field_info;
        }
        return rv;
    }
}

/** @REST /v6/dataprovider/types (/v5/dataprovider/types)

    This URI path provides access to data type information
*/
class DataProviderTypesRestClassV6 inherits DataProviderTypesRestClassV5 {
    constructor(*DataProviderTypeEntry entry) : DataProviderTypesRestClassV5(entry) {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *DataProviderTypeEntry child = entry.getChild(arg);
        if (child) {
            return new DataProviderTypesRestClassV6(child);
        }

        # check for field
        if (entry.getInfo().has_type && (*AbstractDataField field = entry.getType().getField(arg))) {
            DataProviderTypeEntry new_entry(entry.getPath(), arg);
            new_entry.setType(field.getType());
            return new DataProviderTypesRestClassV6(new_entry);
        }

        if (arg == "type") {
            return doGetDataProviderTypeRestClass(entry.getPath(), entry.getTypeEx());
        }
    }

    /** @REST GET action=childDetails

        @par Description
        Returns information for the current data type entry with details for children
    */
    hash<HttpHandlerResponseInfo> getChildDetails(hash<auto> cx, *hash<auto> ah) {
        hash<DataProviderTypeEntryInfo> info = entry.getInfo();
        hash<auto> rv = info + {
            "children": (map entry.getChildEx($1).getInfo() - "children", info.children),
        };
        return RestHandler::makeResponse(200, rv);
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV6(name, type);
    }
}

/** @REST /v6/dataprovider/basetypes (/v5/dataprovider/basetypes)

    This URI path provides access to base data type information
*/
class DataProviderBaseTypesRestClassV6 inherits DataProviderBaseTypesRestClassV5 {
    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV6(name, type);
    }
}

/** @REST /v6/dataprovider/browse/factory/{provider}

    This URI path provides the root URI for browsing a data provider create from a data provider factory
*/
class DataProviderBrowseDataProvider inherits QorusRestClass {
    private {
        #! The parsed "context" argument keyed by value
        *hash<string, bool> ctxt;

        #! The data provider
        AbstractDataProvider prov;

        #! The data provider info
        hash<auto> info;
    }

    constructor(*hash<string, bool> ctxt, AbstractDataProvider prov, hash<auto> info) {
        self.ctxt = ctxt;
        self.prov = prov;
        self.info = info;
    }

    string name() {
        return info.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProvider child = prov.getChildProvider(arg);
        if (!child && (!ctxt || (ctxt.type))) {
            if ((*list<string> l = arg.split(":")) && (l.size() > 1) && (l[0] == "type")) {
                if (l.size() == 2) {
                    if (l[1] == "record") {
                        DataProviderTypeEntry entry();
                        *hash<string, AbstractDataField> rec = prov.getRecordType();
                        AbstractDataProviderType type;
                        if (rec) {
                            HashDataType ht();
                            map ht.addField($1), rec.iterator();
                            type = ht;
                        } else {
                            type = AbstractDataProviderTypeMap."any";
                        }
                        entry.setType(type);
                        return new DataProviderBrowseTypes(entry);
                    } else if (l[1] == "request") {
                        DataProviderTypeEntry entry();
                        entry.setType(prov.getRequestType());
                        return new DataProviderBrowseTypes(entry);
                    } else if (l[1] == "response") {
                        DataProviderTypeEntry entry();
                        entry.setType(prov.getResponseType());
                        return new DataProviderBrowseTypes(entry);
                    }
                } else if (l.size() == 3) {
                    if (l[1] == "event") {
                        if (*hash<DataProviderMessageInfo> minfo = info.events{l[2]}) {
                            DataProviderTypeEntry entry();
                            entry.setType(minfo.type);
                            return new DataProviderBrowseTypes(entry);
                        }
                    } else if (l[1] == "message") {
                        if (*hash<DataProviderMessageInfo> minfo = info.messages{l[2]}) {
                            DataProviderTypeEntry entry();
                            entry.setType(minfo.type);
                            return new DataProviderBrowseTypes(entry);
                        }
                    }
                }
            }

            return;
        }
        hash<auto> pinfo = child.getInfoAsData();
        if (!ctxt || ctxt.type
            || (ctxt.api && (pinfo.supports_request || pinfo.children_can_support_apis))
            || (ctxt.record && (pinfo.has_record || pinfo.children_can_support_records))
            || (ctxt.event && (pinfo.supports_observable || pinfo.children_can_support_observers))
            || (ctxt.message && (pinfo.supports_messages || pinfo.children_can_support_messages))) {
            return new DataProviderBrowseDataProvider(ctxt, child, pinfo);
        }
    }

    /** @REST GET

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        - type (string): one of the following: \c nav: a navigation node, \c data-provider: a data provider, \
          \c type: a data type
        - children (list<hash DataProviderChildBrowseInfo>): a list of children of the current node
          - name (string): the name of the child node
          - desc (string): the description of the child
          - type (string): the type of the child node; one of the following: \c nav: a navigation node, \
            \c data-provider: a data provider, \c type: a data type, \c factory: a data provider factory, which may \
            require sending \c provider_options according to the \c constructor_options key in this hash to create \
            the data provider
          - constructor_options (*hash[any] UndefinedHash): any constructor options supported by the data provider; \
            only present when \c type is \c "factory"
        - matches_context (*bool): if \c True then the node is a match for the search context
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *hash<string, hash<auto>> children = doGetAvailableChildren(ah);
        hash<auto> rv = {
            "type": "data-provider",
            "children": (map (
                "name": $1.key,
                "desc": $1.value.desc,
                "type": $1.value.type,
            ), children.pairIterator()),
        };
        if (!ctxt
            || (ctxt.api && info.supports_request)
            || (ctxt.record && info.has_record)
            || (ctxt.event && info.supports_observable)
            || (ctxt.message && info.supports_messages)) {
            rv.matches_context = True;
        }
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type
        - provider_options (*hash[any] UndefinedHash): a hash of constructor options for a data provider when \
          following the URI path through a data provider factory that takes constructor options

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST GET action=info

        @SCHEMA
        @summary Returns information about the current DataProvider

        @desc Returns information about the current DataProvider

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type
        @return (hash DataProviderChildDetailInfo): information about the current data provider
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> getInfo(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, DataProviderRestClass::doGetInfo(prov, ah, 6, True));
    }

    /** @REST PUT action=info

        @SCHEMA
        @summary Returns information about the current DataProvider

        @desc Returns information about the current DataProvider

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type
        - provider_options (*hash[any] UndefinedHash): a hash of constructor options for a data provider when \
          following the URI path through a data provider factory that takes constructor options

        @return (hash DataProviderChildDetailInfo): information about the current data provider
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putInfo(hash<auto> cx, *hash<auto> ah) {
        return getInfo(cx, ah);
    }

    #! returns a set of possible subclasses for a particular request
    /** @param cx the HTTP call context hash
        @param ah the holds URI and / or message body arguments for the REST call; if a request has both URI
        query arguments and message body arguments, then this value will be a combination of URI query arguments
        and deserialized message body arguments with URI query arguments taking precedence over the message body
        arguments

        @return a set of possible subclasses for the request
    */
    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return map {$1: True}, keys doGetAvailableChildren(ah);
    }

    *hash<string, hash<auto>> doGetAvailableChildren(*hash<auto> ah) {
        *hash<string, hash<auto>> rv = cast<*hash<string, hash<auto>>>(
            map {
                $1.name: {
                    "desc": $1.desc,
                    "type": "data-provider",
                },
            },
            prov.getChildProviderSummaryInfo(),
                (!ctxt || ctxt.type
                    || (ctxt.api && ($1.supports_request || $1.children_can_support_apis))
                    || (ctxt.record && ($1.has_record || $1.children_can_support_records))
                    || (ctxt.event && ($1.supports_observable || $1.children_can_support_observers))
                    || (ctxt.message && ($1.supports_messages || $1.children_can_support_messages)))
        );
        if (!ctxt || ctxt.type) {
            if (info.has_record) {
                rv."type:record" = {
                    "desc": "the record type for the data provider",
                    "type": "type",
                };
            }
            if (info.supports_request) {
                rv += {
                    "type:request": {
                        "desc": "the API request type for the data provider",
                        "type": "type",
                    },
                    "type:response": {
                        "desc": "the API response type for the data provider",
                        "type": "type",
                    },
                };
            }
            if (info.supports_observable && info.events) {
                rv += cast<*hash<string, hash<auto>>>(
                    map {
                        "type:event:" + $1: {
                            "desc": sprintf("observable event %y type for the data provider", $1),
                            "type": "type",
                        },
                    }, keys info.events
                );
            }
            if (info.supports_message && info.messages) {
                rv += cast<*hash<string, hash<auto>>>(
                    map {
                        "type:message:" + $1: {
                            "desc": sprintf("message %y type for the data provider", $1),
                            "type": "type",
                        },
                    }, keys info.messages
                );
            }
        }

        return rv;
    }
}

/** @REST /v6/dataprovider/browse/factory/{provider}/info (/v6/dataprovider/factories/{factory}/provider)
*/

    /** @REST GET

        @SCHEMA
        @summary Returns data provider information

        @desc Returns data provider information

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderChildDetailInfo): information about the current data provider
        @ENDSCHEMA
    */

    /** @REST PUT action=apiEndpoints

        @SCHEMA
        @summary Returns a list of request/response endpoint information for the data provider

        @desc Returns a list of request/response endpoint information for the data provider

        @params
        - soft (*bool): soft types are returned
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type
        - provider_options (*hash[any] UndefinedHash): a hash of constructor options for a data provider when \
          following the URI path through a data provider factory that takes constructor options

        @return (list<hash EndpointInfo>): a list of API endpoints supported by the data provider
        - endpoint: (string) the relative data provider path to the endpoint
        - request_type: (hash) a type hash for the request
        - response_type: (hash) a type hash for the response
        @ENDSCHEMA
    */

    /** @REST PUT action=Description

        @SCHEMA
        @summary Returns data provider information

        @desc Returns data provider information

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type
        - provider_options (*hash[any] UndefinedHash): any options to be passed to a factory creation method when \
          accessing this URI endpoint through a factory

        @return (hash DataProviderInfo): information about the current data provider

        @ENDSCHEMA
    */

    /** @REST GET action=childDetails

        @SCHEMA
        @summary Returns data provider information with details in the \c children key

        @desc Returns data provider information

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderChildDetailInfo): information about the current data provider
        @ENDSCHEMA
    */

    /** @REST PUT action=childDetails

        @SCHEMA
        @summary Returns data provider information with details in the \c children key

        @desc Returns data provider information

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type
        - provider_options (*hash[any] UndefinedHash): a hash of constructor options for a data provider when \
          following the URI path through a data provider factory that takes constructor options

        @return (hash DataProviderChildDetailInfo): information about the current data provider
        @ENDSCHEMA
    */


/** @REST /v6/dataprovider/browse/factory

    This URI path provides the root URI for browsing data provider factories
*/
class DataProviderBrowseFactories inherits QorusRestClass {
    private {
        #! The parsed "context" argument keyed by value
        *hash<string, bool> ctxt;
    }

    constructor(*hash<string, bool> ctxt) {
        self.ctxt = ctxt;
    }

    string name() {
        return "factory";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProviderFactory factory = DataProvider::getFactoryEx(arg);
        if (!factory) {
            return;
        }
        hash<auto> info = factory.getInfo();
        if (!ctxt || ctxt.type
            || (ctxt.api && info.children_can_support_apis)
            || (ctxt.record && info.children_can_support_records)
            || (ctxt.event && info.children_can_support_observers)
            || (ctxt.message && info.children_can_support_messages)) {
            AbstractDataProvider prov = factory.create(ah.provider_options);
            hash<auto> pinfo = prov.getInfoAsData();
            if (!ctxt || ctxt.type
                || (ctxt.api && (pinfo.supports_request || pinfo.children_can_support_apis))
                || (ctxt.record && (pinfo.has_record || pinfo.children_can_support_records))
                || (ctxt.event && (pinfo.supports_observable || pinfo.children_can_support_observers))
                || (ctxt.message && (pinfo.supports_messages || pinfo.children_can_support_messages))) {
                return new DataProviderBrowseDataProvider(ctxt, prov, pinfo);
            }
        }
    }

    /** @REST GET

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *hash<string, hash<auto>> children = doGetAvailableChildren(ah);
        hash<auto> rv = {
            "type": "nav",
            "children": (map (
                "name": $1.key,
                "desc": $1.value.desc,
                "constructor_options": $1.value.constructor_options,
                "type": "factory",
            ), children.pairIterator()),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST GET action=info

        @SCHEMA
        @summary Returns information about the current navigation node

        @desc Returns information about the current navigation node

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> getInfo(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, {"name": name()});
    }

    /** @REST PUT action=info

        @SCHEMA
        @summary Returns information about the current navigation node

        @desc Returns information about the current navigation node

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putInfo(hash<auto> cx, *hash<auto> ah) {
        return getInfo(cx, ah);
    }

    #! returns a set of possible subclasses for a particular request
    /** @param cx the HTTP call context hash
        @param ah the holds URI and / or message body arguments for the REST call; if a request has both URI
        query arguments and message body arguments, then this value will be a combination of URI query arguments
        and deserialized message body arguments with URI query arguments taking precedence over the message body
        arguments

        @return a set of possible subclasses for the request
    */
    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return map {$1: True}, keys doGetAvailableChildren(ah);
    }

    *hash<string, hash<auto>> doGetAvailableChildren(*hash<auto> ah) {
        return map {$1.name: {
            "desc": $1.desc,
            "constructor_options": $1.provider_info.constructor_options,
        }}, (map DataProvider::getFactoryEx($1).getInfoAsData(), DataProvider::listFactories()),
            (!ctxt || ctxt.type
                || (ctxt.api && $1.children_can_support_apis)
                || (ctxt.record && $1.children_can_support_records)
                || (ctxt.event && $1.children_can_support_observers)
                || (ctxt.message && $1.children_can_support_messages));
    }
}

class AbstractDataProviderBrowseConnections inherits QorusRestClass {
    private {
        #! The parsed "context" argument keyed by value
        *hash<string, bool> ctxt;
    }

    constructor(*hash<string, bool> ctxt) {
        self.ctxt = ctxt;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractConnection conn = doGetConnectionObject().tryGetConnection(arg);
        if (!conn) {
            return;
        }
        hash<ConnectionInfo> info = conn.getInfo();
        if (!ctxt || ctxt.type
            || (ctxt.api && info.children_can_support_apis)
            || (ctxt.record && info.children_can_support_records)
            || (ctxt.event && info.children_can_support_observers)
            || (ctxt.message && info.children_can_support_messages)) {
            AbstractDataProvider prov = conn.getDataProvider();
            hash<auto> pinfo = prov.getInfoAsData();
            if (!ctxt || ctxt.type
                || (ctxt.api && (pinfo.supports_request || pinfo.children_can_support_apis))
                || (ctxt.record && (pinfo.has_record || pinfo.children_can_support_records))
                || (ctxt.event && (pinfo.supports_observable || pinfo.children_can_support_observers))
                || (ctxt.message && (pinfo.supports_messages || pinfo.children_can_support_messages))) {
                return new DataProviderBrowseDataProvider(ctxt, prov, pinfo);
            }
        }
    }

    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *hash<string, string> children = doGetAvailableChildren(ah);
        hash<auto> rv = {
            "type": "nav",
            "children": (map (
                "name": $1.key,
                "desc": $1.value,
                "type": "data-provider",
            ), children.pairIterator()),
        };
        return RestHandler::makeResponse(200, rv);
    }

    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    hash<HttpHandlerResponseInfo> getInfo(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, {"name": name()});
    }

    hash<HttpHandlerResponseInfo> putInfo(hash<auto> cx, *hash<auto> ah) {
        return getInfo(cx, ah);
    }

    #! returns a set of possible subclasses for a particular request
    /** @param cx the HTTP call context hash
        @param ah the holds URI and / or message body arguments for the REST call; if a request has both URI
        query arguments and message body arguments, then this value will be a combination of URI query arguments
        and deserialized message body arguments with URI query arguments taking precedence over the message body
        arguments

        @return a set of possible subclasses for the request
    */
    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return map {$1: True}, keys doGetAvailableChildren(ah);
    }

    *hash<string, string> doGetAvailableChildren(*hash<auto> ah) {
        return cast<*hash<string, string>>(map {$1.name: $1.desc}, doGetConnectionObject().list(),
            ($1.has_provider && (!ctxt || ctxt.type
                || (ctxt.api && $1.children_can_support_apis)
                || (ctxt.record && $1.children_can_support_records)
                || (ctxt.event && $1.children_can_support_observers)
                || (ctxt.message && $1.children_can_support_messages))));
    }

    abstract ConnectionsServer doGetConnectionObject();
}

/** @REST /v6/dataprovider/browse/connection/{connection} (/v6/dataprovider/browse/factory/{provider})

    This URI path provides the root URI for browsing a data provider created from a user connection
*/

/** @REST /v6/dataprovider/browse/connection

    This URI path provides the root URI for browsing data providers from user connections
*/
class DataProviderBrowseConnections inherits AbstractDataProviderBrowseConnections {
    constructor(*hash<string, bool> ctxt) : AbstractDataProviderBrowseConnections(ctxt) {
    }

    string name() {
        return "connection";
    }

    ConnectionsServer doGetConnectionObject() {
        return Qorus.connections;
    }

    /** @REST GET

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */

    /** @REST PUT

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */

    /** @REST GET action=info

        @SCHEMA
        @summary Returns information about the current navigation node

        @desc Returns information about the current navigation node

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */

    /** @REST PUT action=info

        @SCHEMA
        @summary Returns information about the current navigation node

        @desc Returns information about the current navigation node

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */
}

/** @REST /v6/dataprovider/browse/datasource/{datasource} (/v6/dataprovider/browse/factory/{provider})

    This URI path provides the root URI for browsing a data provider created from datasources
*/

/** @REST /v6/dataprovider/browse/datasource

    This URI path provides the root URI for browsing data providers from datasources
*/
class DataProviderBrowseDatasources inherits AbstractDataProviderBrowseConnections {
    constructor(*hash<string, bool> ctxt) : AbstractDataProviderBrowseConnections(ctxt) {
    }

    string name() {
        return "datasource";
    }

    ConnectionsServer doGetConnectionObject() {
        return Qorus.dsmanager;
    }

    /** @REST GET

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */

    /** @REST PUT

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */

    /** @REST GET action=info

        @SCHEMA
        @summary Returns information about the current navigation node

        @desc Returns information about the current navigation node

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */

    /** @REST PUT action=info

        @SCHEMA
        @summary Returns information about the current navigation node

        @desc Returns information about the current navigation node

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */
}

/** @REST /v6/dataprovider/browse/remote/{remote} (/v6/dataprovider/browse/factory/{provider})

    This URI path provides the root URI for browsing a data provider created from a remote Qorus connection
*/

/** @REST /v6/dataprovider/browse/remote

    This URI path provides the root URI for browsing data providers from remote Qorus connections
*/
class DataProviderBrowseRemotes inherits AbstractDataProviderBrowseConnections {
    constructor(*hash<string, bool> ctxt) : AbstractDataProviderBrowseConnections(ctxt) {
    }

    string name() {
        return "remote";
    }

    ConnectionsServer doGetConnectionObject() {
        return Qorus.remotemonitor;
    }

    /** @REST GET

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */

    /** @REST PUT

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */

    /** @REST GET action=info

        @SCHEMA
        @summary Returns information about the current navigation node

        @desc Returns information about the current navigation node

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */

    /** @REST PUT action=info

        @SCHEMA
        @summary Returns information about the current navigation node

        @desc Returns information about the current navigation node

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */
}

/** @REST /v6/dataprovider/browse/type

    This URI path provides the root URI for browsing data types
*/
class DataProviderBrowseTypes inherits QorusRestClass {
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
            return new DataProviderBrowseTypes(child);
        }
    }

    /** @REST GET

        @SCHEMA
        @summary Returns information on available paths to child types, if any

        @desc Returns information on available paths to child types, if any

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *hash<string, hash<auto>> children = doGetAvailableChildren(ah);
        hash<auto> rv = {
            "type": entry.hasType() ? "type" : "nav",
            "children": (map (
                "name": $1.key,
                "desc": $1.value.desc,
                "type": $1.value.type,
            ), children.pairIterator()),
            "matches_context": True,
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST GET action=info

        @SCHEMA
        @summary Returns information about the current DataProvider

        @desc Returns information about the current DataProvider

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash[any] UndefinedHash): a hash with basic info about the current data provider type, if the node \
        has a type, otherwise with basic information about the nav node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> getInfo(hash<auto> cx, *hash<auto> ah) {
        hash<auto> info;
        if (entry.hasType()) {
            info = DataProviderTypeRestClassV6::doGetInfo(entry.getType(), name, ah);
        } else {
            info = {"name": self.name()};
        }
        return RestHandler::makeResponse(200, info);
    }

    /** @REST PUT action=info

        @SCHEMA
        @summary Returns information about the current DataProvider

        @desc Returns information about the current DataProvider

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash[any] UndefinedHash): a hash with basic info about the current data provider type, if the node \
        has a type, otherwise with basic information about the nav node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putInfo(hash<auto> cx, *hash<auto> ah) {
        return getInfo(cx, ah);
    }

    #! returns a set of possible subclasses for a particular request
    /** @param cx the HTTP call context hash
        @param ah the holds URI and / or message body arguments for the REST call; if a request has both URI
        query arguments and message body arguments, then this value will be a combination of URI query arguments
        and deserialized message body arguments with URI query arguments taking precedence over the message body
        arguments

        @return a set of possible subclasses for the request
    */
    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return map {$1: True}, keys doGetAvailableChildren(ah);
    }

    *hash<string, hash<auto>> doGetAvailableChildren(*hash<auto> ah) {
        hash<DataProviderTypeEntryInfo> info = entry.getInfo();
        return cast<*hash<string, hash<auto>>>(map {$1.name: {
            "desc": $1.desc,
            #"path": $1.path,
            "type": ($1.has_type ? "type" : "nav"),
        }}, (map entry.getChildEx($1).getInfo(), entry.getChildNames()));
    }
}

/** @REST /v6/dataprovider/browse

    This URI path provides the root URI for browsing for types and data providers
*/
class DataProviderBrowseRoot inherits QorusRestClass {
    public {
        const RootContexts = {
            "factory": "Factories that create DataProviders and associated data types",
            "connection": "User connections that support DataProviders and associated data types",
            "datasource": "DataProviders for locally-connected databases and tables and associated types",
            "remote": "Remote Qorus connections for DataProviders associated with the remote Qorus instance and associated types",
            "type": "Data types known to Qorus",
        };

        const Contexts = {
            "api": ("factory", "connection", "remote"),
            "event": ("factory", "connection", "remote"),
            "message": ("factory", "connection", "remote"),
            "record": ("factory", "connection", "datasource", "remote"),
            "type": keys RootContexts,
        };
    }

    string name() {
        return "browse";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<string, bool> ctxt;
        *hash<string, string> children = doGetAvailableChildren(cx, ah, \ctxt);

        if (arg == "factory" && children.factory) {
            return new DataProviderBrowseFactories(ctxt);
        }
        if (arg == "connection" && children.connection) {
            return new DataProviderBrowseConnections(ctxt);
        }
        if (arg == "datasource" && children.datasource) {
            return new DataProviderBrowseDatasources(ctxt);
        }
        if (arg == "remote" && children.remote) {
            return new DataProviderBrowseRemotes(ctxt);
        }
        if (arg == "type" && children.type) {
            return new DataProviderBrowseTypes();
        }
    }

    /** @REST GET

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *hash<string, string> children = doGetAvailableChildren(cx, ah);
        hash<auto> rv = {
            "type": "nav",
            "children": (map (
                "name": $1.key,
                "desc": $1.value,
                "type": "nav",
            ), children.pairIterator()),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT

        @SCHEMA
        @summary Returns information on available paths to types or data providers according to the requesting context

        @desc Returns information on available paths to types or data providers according to the requesting context

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNodeInfo): a hash providing information about the current node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST GET action=info

        @SCHEMA
        @summary Returns information about the current DataProvider

        @desc Returns information about the current DataProvider

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> getInfo(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, {"name": name()});
    }

    /** @REST PUT action=info

        @SCHEMA
        @summary Returns information about the current DataProvider

        @desc Returns information about the current DataProvider

        @params
        - Q context (*string): one of the following: \c api: when browsing for a request-response data provider, \
          \c record: when browsing for a record-based data provider, \c event: when browsing for a data provider \
          that can function as an observable event source, \c message: when browsing for a data provider that \
          supports sending messages, \c type: when browsing for a type

        @return (hash DataProviderBrowseNavInfo): a hash with basic info about the current data provider nav node
        - name (string): the name of the node
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putInfo(hash<auto> cx, *hash<auto> ah) {
        return getInfo(cx, ah);
    }

    #! returns a set of possible subclasses for a particular request
    /** @param cx the HTTP call context hash
        @param ah the holds URI and / or message body arguments for the REST call; if a request has both URI
        query arguments and message body arguments, then this value will be a combination of URI query arguments
        and deserialized message body arguments with URI query arguments taking precedence over the message body
        arguments

        @return a set of possible subclasses for the request
    */
    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return map {$1: True}, keys doGetAvailableChildren(cx, ah);
    }

    static *hash<string, string> doGetAvailableChildren(hash<auto> cx, *hash<auto> ah, *reference<*hash<string, bool>> ctxt) {
        ctxt = DataProviderRestClass::parseOption(ah, "context");
        *hash<string, string> rv;
        if (!ctxt || ctxt.type) {
            rv = RootContexts;
        } else {
            rv = foldl $1 + $2, (map RootContexts{Contexts{$1}}, keys ctxt);
        }
        return rv;
    }
}

/** @REST /v6/dataprovider (/v5/dataprovider)

    This URI path provides access to data provider functionality
*/
class DataProviderBaseRestClassV6 inherits DataProviderBaseRestClassV5 {
    private setup() {
        addClass(new DataProviderFactoriesRestClassV6());
        addClass(new DataProviderTypesRestClassV6());
        addClass(new DataProviderBaseTypesRestClassV6());
        addClass(new DataProviderRestClassV6(create_object("QorusApiDataProvider")));
        addClass(new DataProviderBrowseRoot());
    }
}

/** @REST /v6/remote/qorus/{name} (/v5/remote/qorus/{name})

    This REST URI path provides actions and information related to a specific @ref remoteconn "remote connection"
*/
class QorusRemoteConnectionRestClassV6 inherits QorusRemoteConnectionRestClassV5 {
    constructor(hash<auto> rh) : QorusRemoteConnectionRestClassV5(rh) {
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV6(provider);
    }
}

/** @REST /v6/remote/qorus (/v5/remote/qorus)

    This REST URI path provides actions and information related to Qorus @ref remoteconn "remote connections"
*/
class QorusRemoteConnectionsRestClassV6 inherits QorusRemoteConnectionsRestClassV5 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
        *hash<auto> rh = Qorus.remotemonitor.tryGetInfo(name, {"with_passwords": with_passwords});
        if (rh) {
            return new QorusRemoteConnectionRestClassV6(rh);
        }
    }
}

/** @REST /v6/remote/user/{name} (/v5/remote/user/{name})

    This REST URI path provides actions and information related to a specific @ref userconn "user connection"
*/
class UserConnectionRestClassV6 inherits UserConnectionRestClassV5 {
    constructor(hash<auto> rh) : UserConnectionRestClassV5(rh) {
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV6(provider);
    }
}

/** @REST /v6/remote/user (/v5/remote/user)

    This REST URI path provides actions and information related to Qorus @ref userconn "user connections"
*/
class UserConnectionsRestClassV6 inherits UserConnectionsRestClassV5 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
        *hash<auto> rh = Qorus.connections.getInfo(name, {"with_passwords": with_passwords});
        if (rh) {
            return new UserConnectionRestClassV6(rh);
        }
    }
}

/** @REST /v6/remote/datasources/{name} (/v5/remote/datasources/{name})

    This REST URI path provides actions and information related to a specific Qorus system @ref dsconn "datasource"
*/
class DatasourceRestClassV6 inherits DatasourceRestClassV5 {
    constructor(hash<auto> rh) : DatasourceRestClassV5(rh) {
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV6(provider);
    }
}

/** @REST /v6/remote/datasources (/v5/remote/datasources)

    This REST URI path provides actions and information related to Qorus system @ref dsconn "datasources"
*/
class DatasourcesRestClassV6 inherits DatasourcesRestClassV5 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
        *hash<auto> rh = Qorus.dsmanager.tryGetInfo(name, {
            "with_passwords": with_passwords,
            "rtime": parse_boolean(ah.rtime),
        });
        if (rh) {
            return new DatasourceRestClassV6(rh);
        }
    }
}

/** @REST /v6/remote (/v5/remote)

    This REST URI path provides actions and information about remote @ref remoteconn "Qorus", @ref userconn "user" and
    @ref dsconn "datasource" connections
*/
class RemoteRestClassV6 inherits RemoteRestClassV5 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "qorus": return new QorusRemoteConnectionsRestClassV6();
            case "user": return new UserConnectionsRestClassV6();
            case "datasources": return new DatasourcesRestClassV6();
        }
    }
}

/** @REST /v6/connections/{name}

    This REST URI path provides actions and information related to a specific connection, which may be:
    - a @ref userconn "user connection"
    - a @ref dsconn "datasource"
    - a @ref remoteconn "remote Qorus connection"
*/

    /** @REST PUT action=enableDebugData

        @SCHEMA
        @summary Enables data debugging for a user connection

        @desc Enables data debugging for a @ref userconn "user connection" (and only for user connections)

        @return (hash ConnectionUpdateResultInfo): information about the result of the operation
        - info (string): a string providing information about the connection update action
        @ENDSCHEMA
    */

    /** @REST PUT action=disableDebugData

        @SCHEMA
        @summary Disables data debugging for a user connection

        @desc Disables data debugging for a @ref userconn "user connection" (and only for user connections)

        @return (hash ConnectionUpdateResultInfo): information about the result of the operation
        - info (string): a string providing information about the connection update action
        @ENDSCHEMA
    */

    /** @REST PUT action=enable

        @SCHEMA
        @summary Enables the current connection if it is disabled

        @desc Enables the current @ref userconn "user connection", @ref dsconn "datasource", or \
        @ref remoteconn "remote Qorus connection" if it is disabled; if the connection is already enabled, the \
        action is reported as successful anyway

        @return (hash ConnectionUpdateResultInfo): information about the result of the operation
        - info (string): a string providing information about the connection update action
        @ENDSCHEMA
    */

    /** @REST PUT action=disable

        @SCHEMA
        @summary Disables the current connection if it is enabled

        @desc Disables the current @ref userconn "user connection", @ref dsconn "datasource", or \
        @ref remoteconn "remote Qorus connection" if it is enabled; if the connection is already disabled, the \
        action is reported as successful anyway

        @return (hash ConnectionUpdateResultInfo): information about the result of the operation
        - info (string): a string providing information about the connection update action
        @ENDSCHEMA

        @par Description
        Disables current @ref userconn "user connection", @ref dsconn "datasource", or
        @ref remoteconn "remote Qorus connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */

    /** @REST PUT action=ping

        @SCHEMA
        @summary Pings the current connection

        @desc Checks connectivity to the current @ref userconn "user connection", @ref dsconn "datasource", or \
        @ref remoteconn "remote Qorus connection"; if the connection was up and is monitored to be down, then any \
        dependent interfaces will be disabled.  If the connection was down and is monitored to be up, then any \
        eligible interfaces will be reenabled.

        @return (hash PingResultInfo): the result of the ping operation
        - ok (bool): the status of the ping
        - name (string): the name of the connection
        - desc (string): the description of the connection
        - url (string): the URL for the connection
        - opts (hash UndefinedHash): a hash of options for the connection (if any)
        - time (date): the elapsed time for the ping
        - info (string): \c "OK" if the ping was successful or an error message if not
        - result (string): a string representation of the time in seconds (ex: \c "0.25s")
        @ENDSCHEMA
    */

    /** @REST GET

        @SCHEMA
        @summary Returns information about the current connection

        @desc Returns a hash information for the current @ref userconn "user connection", @ref dsconn "datasource", \
        or @ref remoteconn "remote Qorus connection"

        @params
        - with_password (*bool): include the password in the \c "url" and \c "url_hash" keys

        @return (hash ConnectionInfo): information about the connection
        - connectionid (int): the unique connection ID
        - name (string): the name of the connection
        - conntype (string): either \c "DATASOURCE", \c "REMOTE", or \c "USER-CONNECTION"
        - description (string): a description of the connection
        - url (string): the URL to the remote host
        - monitor (bool): a boolean indicating if the connection is monitored or not
        - last_check (*date): the date/time value the connection was last checked (loopback \
          @ref remoteconn "remote connections" are not checked)
        - updated (*date): the date/time the connection was last updated
        - status (string): \ "OK", \c "not checked", or an error message
        - up (bool): a boolean indicating if the connection was monitored to be up or not
        - loopback (*bool): (only for @ref remoteconn "remote connections") indicates if the connection is a \
          loopback connection
        - type (string): the connection type (\c "datasource", \c "rest", \c "soap", etc)
        - url_hash (hash UndefinedHash): a hash of broken-down URL components
        - enabled (bool): indicates if the connecton is enabled or not
        - locked (*bool): indicates if the connection can be edited or not (only the system schema connection is \
          locked and cannot be edited)
        - debug_data (*bool): if data debugging is enabled for the connection
        - tags (*hash[any] UndefinedHash): any tags for the connection
        - has_provider (bool): if the connection supports a data provider
        - children_can_support_apis (bool): if the data provider or any children support APIs
        - children_can_support_records (bool): if the data provider or any children support records
        - children_can_support_observers (bool): if the data provider or any children support event observation
        - children_can_support_messages (bool): if the data provider or any children support messages
        - opts (*hash UndefinedHash): a hash of options for the connection
        - coord-mode (*bool): if coordinated mode is enabled (datasources only)
        - safe_url (*string): a URL string without any password information
        - shared-pool (*string): summary information about the DatasourcePool object backing a datasource connection
        - warning-timeout (*int): datasource warning timeout in milliseconds
        - error-timeout (*int): datasources error timeout in milliseconds
        - pool-wait-max (*int): (datasources only) the maximum wait time for a pool connection to become available \
          in milliseconds
        - pool-reqs (*int): (datasources only) the number of connection requests on the pool
        - pool-hits (*int): (datasources only) the number of connection requests that could be served immediately \
          without blocking
        - pool-miss (*int): (datasources only) the number of connection requests that could be served only after \
          blocking
        - pool-hit-pct (*float): the percentage of hits to misses
        - deps (*list<hash ConnectionDependencyInfo>): a list of dependent interfaces
          - type (string): the interface type; one of \c "WORKFLOW", \c "SERVICE", or \c "JOB"
          - workflowid (*int): the workflow ID (only present for workflows)
          - serviceid (*int): the service ID (only present for services)
          - jobid (*int): the job ID (only present for jobs)
          - servicetype (*string): the service type (only present for services); one of \c "user" or \c "system"
          - name (string): the interface name
          - version (string): the interface version
          - desc (string): a description of the interface (ex: \c "job it-94-ar_payments-piteco-out v1.0 (23)")
        - alerts (*list<hash AlertInfo>): a list of alerts raised against the connection
        - health (*string): (remote Qorus connections only) a string giving the health color code of the instance
        - instance-key (*string): (remote Qorus connections only) the Qorus instance key of the remote instance
        - omq-version (*string): (remote Qorus connections only) the Qorus version
        - alert-summary (*hash SystemAlertInfo): summary of alert info
        - error (*string): (remote Qorus connections only) any error summary string for the remote instance
        @ENDSCHEMA

        @par Description
        Returns a hash information for the current @ref userconn "user connection", @ref dsconn "datasource", or
        @ref remoteconn "remote Qorus connection"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c with_password: (optional bool) include the password in the \c "url" and \c "url_hash" keys

        @par Return Value
        This API returns a @ref rest_user_remote_connection_hash
    */

    /** @REST PUT

        @SCHEMA
        @summary Modifies the current connection

        @desc Modifies the current @ref userconn "user connection", @ref dsconn "datasource", or \
        @ref remoteconn "remote Qorus connection"

        @params
        - desc (*string): a new description for the connection
        - url (*string): a new URL for the connection
        - options (*hash UndefinedHash): new options for the connection
        - tags (*hash UndefinedHash): new tags for the connection

        @return (hash ConnectionUpdateResultInfo): information about the result of the operation
        - info (string): a string providing information about the connection update action

        @error (403): access or authorization error
        @error (409): error executing the change
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c USER-CONNECTION-ERROR: invalid or unparsable \c "options" key

        @note
        - \c opts is accepted as an alias for \c options
    */

    /** @REST DELETE

        @SCHEMA
        @summary Deletes the current connection

        @desc Permanently deletes the current @ref userconn "user connection", @ref dsconn "datasource", or \
        @ref remoteconn "remote Qorus connection"

        @return (hash ConnectionUpdateResultInfo): information about the result of the operation
        - info (string): a string providing information about the connection update action
        @ENDSCHEMA
    */

/** @REST /v6/connections

    This REST URI path provides actions and information about remote @ref remoteconn "Qorus", @ref userconn "user" and
    @ref dsconn "datasource" connections
*/
class ConnectionsRestClassV6 inherits QorusRestClass {
    string name() {
        return "connections";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        int id;
        if (name =~ /^[0-9]+$/) {
            id = name.toInt();
        }
        if (cx.hdr.method != "GET") {
            ah.with_passwords = True;
        }
        *hash<auto> h = exists id
            ? Qorus.dsmanager.tryGetInfoFromId(id, ah)
            : Qorus.dsmanager.tryGetInfo(name, ah);
        if (h) {
            h.description = remove h.desc;
            return new DatasourceRestClassV6(h);
        }
        if (h = exists id
            ? Qorus.connections.getInfoFromId(id, ah)
            : Qorus.connections.getInfo(name, ah)) {
            h.description = remove h.desc;
            return new UserConnectionRestClassV6(h);
        }
        if (h = exists id
            ? Qorus.remotemonitor.tryGetInfoFromId(id, ah)
            : Qorus.remotemonitor.tryGetInfo(name, ah)) {
            h.description = remove h.desc;
            return new QorusRemoteConnectionRestClassV6({"name": name} + h);
        }
    }

    /** @REST GET

        @par Description
        Returns a list of all remote connections (@ref remoteconn "remote connections" under \c "qorus",
        @ref userconn "user connections" under \c "user", and
        @ref dsconn "datasource connections" under \c "datasources")

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of connection names is
          returned
        - \c monitored: optional; (@ref remoteconn "remote" and @ref userconn "user" connections only) parsed with
          @ref Qore::parse_boolean(); if @ref True then only monitored connections are returned
        - \c remote: optional; (@ref remoteconn "remote connections") parsed with @ref Qore::parse_boolean(); if
          @ref True then no loopback connections are returned; default if not present: @ref False
        - \c rtime: optional; (@ref dsconn "datasource connections" only) parsed with @ref Qore::parse_boolean(); if
          @ref True then the following attributes are returned as relative date/time values:
          - \c "warning-timeout"
          - \c "error-timeout"
          - \c "pool-wait-max"
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with
          connection names and brief info is returned
        - \c with_passwords: (@ref dsconn "datasource connections" only) parsed with @ref Qore::parse_boolean(); if
          @ref True then the \c pass key is returned in the @ref rest_datasource_connection_hash return value

        @par Return Value
        Returns a list of hashes; the \c "conntype" value determines the hash format as follows:
        - \c "DATASOURCE": a @ref rest_datasource_connection_hash
        - \c "REMOTE" or \c "USER-CONNECTION": a @ref rest_user_remote_connection_hash
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        if (exists (auto wp = (ah.with_passwords ?? ah.with_password))) {
            ah.with_passwords = parse_boolean(wp);
        }

        list<hash<auto>> l = ();

        ReadLockHelper rlh(Qorus.connection_rwl);

        *hash<string, hash<EditMapInfo>> edit_map = Qorus.qmm.getEditMapForTypeLocked("connection");

        # get datasource connections
        l += Qorus.dsmanager.getListLocked(edit_map, ah);
        # get user connections
        l += Qorus.connections.getListLocked(edit_map, ah);
        # get server connections
        l += Qorus.remotemonitor.getListLocked(edit_map, ah);

        if (exists ah."list" && parse_boolean(ah."list")) {
            return RestHandler::makeResponse(200, (map $1.name, l));
        }
        if (exists ah.short && parse_boolean(ah.short)) {
            return RestHandler::makeResponse(200, (map sprintf("%s: %s (%s)", $1.name, $1.description,
                $1.up ? "OK" : "DOWN"), l));
        }

        return RestHandler::makeResponse(200, l);
    }

    /** @REST POST

        @par Description
        Creates a new connection from the arguments supplied

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c name: (required string) the name of the user connection
        - \c desc: (required string) the description for the new user connection
        - \c url: (required string) the URL for the new user connection
        - \c options: (optional hash) a hash of options for the user connection (also \c "opts" is accepted as an
          alias for \c "options")

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the connection creation

        @par Errors
        - <tt><b>403 Forbidden</b></tt>: \c AUTHORIZATION-ERROR: this exception is thrown when @ref RBAC is enabled
          and the user does not have sufficient privileges for the operation
        - <tt><b>409 Conflict</b></tt>: \c CONNECTION-ERROR: connection already exists; unknown scheme in URL
        - <tt><b>409 Conflict</b></tt>: \c DATASOURCE-CONNECTION-ERROR: missing or invalid name, desc, url, options
          arguments - or name and @ref datasource_hash members
        - <tt><b>409 Conflict</b></tt>: \c REMOTE-CONNECTION-ERROR: missing or invalid \c name, \c desc, \c url, or
          \c options arguments
        - <tt><b>409 Conflict</b></tt>: \c USER-CONNECTION-ERROR: missing or invalid \c name, \c desc, \c url, or
          \c options arguments

        @see
        - @ref userconntypes "User Connection Types" for information about supported user connection types
        - @ref connection-modules
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        if (ah.url =~ /^db:\/\//) {
            DatasourcesRestClassV6 rest();
            return rest.post(cx, ah);
        }
        if (ah.url =~ /^qoruss?:\/\//) {
            QorusRemoteConnectionsRestClassV6 rest();
            return rest.post(cx, ah);
        }
        UserConnectionsRestClassV6 rest();
        return rest.post(cx, ah);
    }
}

/** @REST /v6/jobs/{id_or_name} (/v5/jobs/{id_or_name})

    This REST API path provides actions and information related to specific jobs;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class JobDefinitionRestClassV6 inherits JobDefinitionRestClassV5 {
    constructor(hash<auto> jh) : JobDefinitionRestClassV5(jh) {
    }

    /** @REST PUT

        @par Description
        Updates a job

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c code: (string) the source code for the job
        - \c metadata: (hash) the metadata of the job to update

        @par Return Value
        This API returns a hash with the following keys:
        - \c id: (int) the job ID updated

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        CreatorJobDefinitionRestClass restclass(jh);
        return restclass.put(cx, ah);
    }

    /** @REST DELETE

        @par Description
        Deletes the job

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        return CreatorJobDefinitionRestClass::staticDeleteJob(jh, cx, ah);
    }
}

/** @REST /v6/jobs (/v5/jobs)

    This REST API path provides actions and information related to Qorus jobs.
*/
class JobRestClassV6 inherits JobRestClassV5 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = JobRestClass::staticGetJobId(arg);
        *hash<auto> job = JobRestClassV2::staticGetJob(cx, ah, id, 6);
        if (!job) {
            return;
        }

        hash<auto> ji = Qorus.jobManager.getActiveInfo();
        JobRestClass::fixJob(\job, ji{job.name}, cx);

        return internGetJobDefinition(job);
    }

    /** @REST GET

        @par Description
        Returns information about Qorus jobs according to the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c defonly: optional (parsed with @ref Qore::parse_boolean()); if @ref True then no job result information
          will be included in the return value; default @ref False
        - \c date: optional (parsed as a date); the past cutoff date for job result (job instances) for the return
          value; if not present, then defaults to the last 24 hours
        - \c jobs: one or more job names or IDs to filter the result list; a comma-separated string will be split into
          a list
        - \c lib_source: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the source code for each
          library object is returned in the @ref rest_job_description_hash
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of job names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of job
          names and descriptions is returned
        - \c sqlcache: optional (parsed with @ref Qore::parse_boolean()); if @ref False then no SQL cache will be
          used for historical info; default @ref True (only used if \c defonly is omitted or @ref False)
        - \c status: optional; either \c "active" or \c "inactive" to filter jobs based on their active status
        - \c tags: optional; a hash of tags to match; only workflows matching at least one of the tags will be
          returned; use <tt>tag=value</tt> format as the value of this option
        - \c tag_case_insensitive: optional; parsed with @ref Qore::parse_boolean(); if @ref True then tag value
          comparisons are made with case-insensitive comparisons
        - \c tag_partial_match: optional; parsed with @ref Qore::parse_boolean(); if @ref True then tag value
          comparisons succeed if the value given as the tag value appears anywhere in the object's tag of the same
          name

        @par Return Value
        If neither \c list nor \c short are used, then this API returns a list of @ref rest_job_description_hash
        elements; if \c defonly is not @ref True, then any jobs with job result data within the given time period (as
        defined by the \c date option) will be reflected in the following extra keys:
        - \c IN-PROGRESS: the number of job instances currently in progress
        - \c COMPLETE: the number of job instances with a @ref OMQ::StatComplete status during the given time period
        - \c ERROR: the number of job instances with a @ref OMQ::StatError status during the given time period
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        if (*hash<HttpHandlerResponseInfo> err = parseTagOptions(\ah)) {
            return err;
        }

        return RestHandler::makeResponse(200, JobRestClass::staticGetJobs(cx, ah, 6, ah));
    }

    private QorusRestClass internGetJobDefinition(hash<auto> job) {
        return new JobDefinitionRestClassV6(job);
    }
}
