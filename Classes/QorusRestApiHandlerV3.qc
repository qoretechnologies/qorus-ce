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

/** @page rest_api_page_v3 Qorus REST API v3

    @tableofcontents

    @section rest_api_v3_overview Qorus REST API v3 Overview

    REST API v3 has the following differences from @ref rest_api_page_v2 "REST API v2":
    - a new URI path calling convention can be used. For example:\n
      <tt>PUT foo/bar?action=myAction</tt>\n
      can be used as:\n
      <tt>PUT foo/bar/myAction</tt>
    - the following APIs are new:
      - @ref rest_api_PUT_v3_jobs__id_or_name__setRemote
      - @ref rest_api_PUT_v3_services__id_or_name__setRemote
      - @ref rest_api_PUT_v3_workflows__id_or_name__setRemote
      - @ref rest_api_PUT_v3_workflows__id_or_name__setSla
      - @ref rest_api_v3_system_metadata
      - @ref rest_api_v3_async-queues
      - @ref rest_api_v3_async-queues__queue_
      - @ref rest_api_v3_orders__id__async-queue
      - @ref rest_api_PUT_v3_remote_user__name__disable
      - @ref rest_api_PUT_v3_remote_user__name__enable
    - the @ref rest_api_v3_system returns the following new information:
      - \c cluster_info: a hash keyed by node name with values as hashes as follows:
        - \c node_priv: (int) total private memory user by the cluster per node
        - \c node_priv_str: (string) total private memory user by the cluster per node as a string
        - \c node_ram: (int) total RAM on the node
        - \c node_ram_str: (string) total RAM on the node as a string
        - \c node_ram_in_use: (int) in use RAM on the node
        - \c node_ram_str: (string) in use RAM on the node as a string
        - \c node_cpu_count: (int) the number of CPUs on the node
        - \c node_load_pct: (float) the average load on the machine over the last minute
        - \c mem_history: a list of hashes giving up to 10 historical memory changes on the node with the following keys in each hash:
          - \c timestamp: (date) the timestamp of the change
          - \c age: (float) the age in fractional seconds of the timestamp
          - \c node_priv: (int) total private memory user by the cluster per node
          - \c node_priv_str: (string) total private memory user by the cluster per node as a string
          - \c node_ram_in_use: (int) in use RAM on the node
          - \c node_ram_str: (string) in use RAM on the node as a string
          - \c node_cpu_count: (int) the number of CPUs on the node
          - \c node_load_pct: (float) the average load on the machine over the last minute
        - \c proc_count: (int) the number of processes running on the node
        - \c proc_history: a list of hashes giving up to 10 historical process count changes on the node with the following keys in each hash:
          - \c timestamp: (date) the timestamp of the change
          - \c age: (float) the age in fractional seconds of the timestamp
          - \c count: (int) the number of processes at that time
      - \c processes: a hash keyed by cluster process name where values are @ref rest_process_info_hash "process info hashes"
      - \c order_stats: a list of workflow order processing statistics; list values are @ref OMQ::OrderSummaryOutputInfo "OrderSummaryOutputInfo" hashes with combined statistics for all workflows
    - workflow data has been updated with \c sla_threshold, \c manual_sla_threshold, \c remote, \c process, and \c order_stats keys in @ref rest_workflow_description_hash_v3 affecting the following REST APIs:
      - @ref rest_api_GET_v3_workflows
      - @ref rest_api_GET_v3_workflows__id_or_name_
    - the \c retry_flag key has been deprecated by the \c status key in the following REST APIs (see @ref q40upgrade):
      - @ref rest_api_POST_v3_errors
      - @ref rest_api_POST_v3_errors_global
      - @ref rest_api_POST_v3_errors_workflow__id_or_name_
      - @ref rest_api_POST_v3_errors_global_createOrUpdate
      - @ref rest_api_POST_v3_errors_workflow__id_or_name__createOrUpdate
      - @ref rest_api_POST_v3_workflows__id_or_name__errors_createOrUpdate
      - @ref rest_api_PUT_v3_errors__error_
      - @ref rest_api_PUT_v3_errors_global__error_
      - @ref rest_api_PUT_v3_errors_workflow__id_or_name___error_
    - the following REST APIs now contain a \c status key instead of the \c retry_flag (@ref rest_workflow_error_description_hash):
      - @ref rest_api_GET_v3_errors_search
      - @ref rest_api_GET_v3_errors_global
      - @ref rest_api_GET_v3_errors_global__error_
      - @ref rest_api_GET_v3_errors_workflow
      - @ref rest_api_GET_v3_errors_workflow__id_or_name_
      - @ref rest_api_GET_v3_errors_workflow__id_or_name___error_
      - @ref rest_api_GET_v3_errors__error_
      - @ref rest_api_GET_v3_workflows__id_or_name__errors
    - the following REST APIs ignore the \a forceworkflow flag and always act on the workflow level:
      - @ref rest_api_POST_v3_errors_workflow__id_or_name_
      - @ref rest_api_POST_v3_workflows__id_or_name__errors
      - @ref rest_api_POST_v3_errors_workflow__id_or_name__createOrUpdate
      - @ref rest_api_POST_v3_workflows__id_or_name__errors_createOrUpdate
    - the following REST APIs now contain \c remote and \c process keys in the @ref rest_execution_instance_hash_v3
      hashes and have dropped the \c status, \c errors, \c warnings, and \c iterations keys:
      - @ref rest_api_GET_v3_exec
      - @ref rest_api_GET_v3_exec__id_
      - @ref rest_api_GET_v3_exec__workflowname_
      - @ref rest_api_GET_v3_workflows__id_or_name__instances
      - @ref rest_api_PUT_v3_workflows__id_or_name__start
    - the following REST APIs now contain a \c remote key in service information hashes:
      - @ref rest_api_GET_v3_services
      - @ref rest_api_GET_v3_services__id_or_name_
    - job data has been updated with \c remote and \c process keys in the following REST APIs:
      - @ref rest_api_GET_v3_jobs
      - @ref rest_api_GET_v3_jobs__id_or_name_
    - the following REST API responses now contain a \c retry_count key:
      - @ref rest_api_GET_v3_orders__id_
      - @ref rest_api_GET_v3_workflows__id_or_name__orders
    - the following REST API responses return @ref rest_class_hash_v3 information about the source language:
      - @ref rest_api_GET_v3_classes__id_or_name_
      - @ref rest_api_GET_v3_steps__id_or_name_ (if the step is implemented by a class)
    - the following REST API returns an empty hash if no data is available:
      - @ref rest_api_GET_v3_system_userhttp
    - the follow REST API returns a new \c db_active key in the responses:
      - @ref rest_api_PUT_v3_jobs__id_or_name__setActive
    - the following REST APIs return a new \c result key in the response:
      - @ref rest_api_PUT_v3_remote_datasources__name__ping
      - @ref rest_api_PUT_v3_remote_qorus__name__ping
      - @ref rest_api_PUT_v3_remote_user__name__ping
*/

/** @REST /v3 (/v2)

    This URI path implements v3 of the Qorus REST API
*/
class V3RestClass inherits QorusRestClass {
    private:internal {
        # class hash
        hash<auto> ch;
    }

    constructor() {
        addClass(new WorkflowRestClassV3());
        addClass(new GlobalOrderRestClassV3());
        addClass(new GlobalWorkflowExecRestClassV3());
        addClass(new ServiceRestClassV3());
        addClass(new JobRestClassV3());
        addClass(new SystemRestClassV3());
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
        addClass(new RemoteRestClassV3());
        addClass(new PermsRestClass());
        addClass(new ErrorsRestClassV3());
        addClass(new MappersRestClass());
        addClass(new MapperTypesRestClass());
        addClass(new AsyncQueuesRestClassV3());
        addClass(new ValueMapsRestClass());
        addClass(new ReleasesRestClass());
        addClass(new SyncEventTypesRestClass());
        addClass(new SlasRestClass());
        addClass(new LogoutRestClass());
        addClass(new RemoteDevelopment::RestClass());
    }

    string name() {
        return "v3";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        return ch{arg};
    }

    /** @REST GET

        @par Description
        Returns the top-level members of this version of the REST API
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ch.keys());
    }

    private:internal addClass(QorusRestClass c) {
        ch{c.name()} = c;
    }
}

/** @REST /v3/steps/{id_or_name}/config/{name}

    This REST URI path provides actions and information related to a particular Qorus.
    Prefix can be passed within the config item name or as following: /v3/steps/{id_or_name}/config/{name}?prefix={prefix}.
    @ref step_config_items "step configuration item"
*/
class StepConfigItemRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> sh;
        hash<auto> item;

        string name_with_prefix;
    }

    constructor(hash<auto> sh, hash<auto> item) {
        self.sh = sh;
        self.item = item;

        name_with_prefix = item.prefix + item.name;
    }

    string name() {
        return item.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (item.hasKey(arg)) {
                return new AttributeRestClass(item{arg});
            }
        }
    }

    /** @REST GET
        @par Description
        Returns a hash for the current @ref step_config_items "step configuration item"

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": the default value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        Note: to obtain value the workflows/{id_or_name}/stepinfo/{id_or_name}/config REST API should be used
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, item);
    }

    /** @REST GET action=yaml
        @par Description
        Returns a hash for the current @ref step_config_items "step configuration item" as a YAML-serialized string

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": (YAML-serialized string) the default value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        Note: to obtain value the workflows/{id_or_name}/stepinfo/{id_or_name}/config REST API should be used
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        auto new_item = QorusRestClass::serializeValuesToYaml(item, ("default_value",));
        if (exists new_item.allowed_values) {
            new_item.allowed_values = serializeValuesInListToYaml(new_item.allowed_values);
        }
        return RestHandler::makeResponse(200, new_item);
    }

    /** @REST PUT

        @par Description
        Sets the value for the given @ref step_config_items "step configuration item"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value: the value of the configuration item; must be compatible with the item's declared type

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value: the new value
        - \c info: info about the service configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("value")) {
            return RestHandler::makeResponse(400, "no key \"value\" argument sent in request");
        }

        hash changed = Qorus.qmm.setConfigItemValueOnInterfaceLevel("step", sh.stepid, name_with_prefix,
                                                                    ah.value);
        changed.info = sprintf("%y configuration item value for step %s v%s (%d) has been changed",
                               name_with_prefix, sh.name, sh.version, sh.stepid);
        return RestHandler::makeResponse(200, changed);
    }

    /** @REST PUT action=yaml

        @par Description
        Sets the value for the given @ref step_config_items "step configuration item" using a YAML-serialized string

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value (YAML-serialized string): the value of the configuration item

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value (YAML-serialized string): the new value
        - \c info: info about the service configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<auto> putYaml(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error;
        ah = QorusRestClass::deserializeYamlValues(ah, "value", \error);
        if (exists error) {
            return error;
        }

        hash<auto> result = put(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }

    /** @REST DELETE

        @par Description
        Permanently deletes the current value for the configuration item on this step level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value: deleted value
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        hash result;
        result.value = Qorus.qmm.deleteConfigItemValueOnInterfaceLevel("step", sh.stepid, name_with_prefix,
                                                                       \result.deleted);

        result.info = sprintf("%y configuration item value for step %s v%s (%d) has been deleted",
                              name_with_prefix, sh.name, sh.version, sh.stepid);
        return RestHandler::makeResponse(200, result);
    }

    /** @REST DELETE action=yaml

        @par Description
        Permanently deletes the current value for the configuration item on this step level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value (YAML-serialized string): deleted value
    */
    hash<auto> delYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> result = del(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }
}

/** @REST /v3/steps/{id_or_name}/config

    This REST URI path provides actions and information related to Qorus
    @ref step_config_items "step configuration items"
*/
class step_config_itemsRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> sh;
    }

    constructor(hash<auto> sh) {
        self.sh = sh;
    }

    string name() {
        return "config";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        string name_with_prefix = ah.prefix + arg;
        if (*hash<auto> item = sh.config{name_with_prefix}) {
            # get actual item name
            if (item.prefix && name_with_prefix.equalPartial(item.prefix)) {
                arg = name_with_prefix[item.prefix.length()..];
            }
            return new StepConfigItemRestClassV3(sh, {"name": arg} + item);
        }
    }

    /** @REST GET
        @par Description
        Returns a list of @ref step_config_items "step configuration items" for the step

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": the default value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        Note: to obtain values the workflows/{id_or_name}/stepinfo/{id_or_name}/config REST API should be used
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                                                   sh.config.pairIterator()));
    }

    /** @REST GET action=yaml
        @par Description
        Returns a list of @ref step_config_items "step configuration items" for the step as a YAML-serialized string

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": (YAML-serialized string) the default value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        Note: to obtain value the workflows/{id_or_name}/stepinfo/{id_or_name}/config REST API should be used
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> config_copy = sh.config;

        foreach auto config in (config_copy.pairIterator()) {
            config_copy{config.key} = QorusRestClass::serializeValuesToYaml(config.value, ("default_value",));
            if (exists config.value.allowed_values) {
                config_copy{config.key}.allowed_values = serializeValuesInListToYaml(config.value.allowed_values);
            }
        }
        list<auto> items = map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                               config_copy.pairIterator();
        return RestHandler::makeResponse(200, items);
    }
}

/** @REST /v3/steps/{id_or_name} (/v2/steps/{id_or_name})

    This REST API path provides actions and information about specific @ref steps "workflow steps"
*/
class StepDefinitionRestClassV3 inherits StepDefinitionRestClass {
    constructor(hash<auto> h) : StepDefinitionRestClass(h, 3) {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "config") {
            return new step_config_itemsRestClassV3(sh);
        }
        return StepDefinitionRestClass::subClassImpl(arg, cx, ah);
    }

    /** @REST GET

        @par Description

        Returns a hash of information about the current step.

        @par Return Value
        This API returns a @ref rest_step_hash providing about the current step plus additional keys as follows:
        - \c functions: if the step is a class step with step functions, this element is returned as a
          list of @ref rest_function_hash elements with the following additional key:
          - \c type: a string specifying the role the function fulfils for the step; one of:
            - \c "primary": the primary step function
            - \c "validation": the @ref dep_validationfunc "validation function"
            - \c "array": the @ref dep_arrayfunc "array function"
            - \c "async-end": the @ref dep_asyncbackendfunc "back end function"
        - \c class: if the step is a new-style step implemented by a single class, then this element is returned
          as a @ref rest_class_hash_v3
        - \c desc: the step description
        - \c config: a hash of @ref step_config_items "step configuration item information" keyed by configuration item
          and with hash values with the following keys:
          - \c "name": the name of the configuration item
          - \c "prefix": the prefix of the configuration item
          - \c "type": the type of the configuration item
          - \c "desc": the description of the configuration item
          - \c "default_value": the default value of the configuration item
          - \c "strictly_local": if the configuration item is defined strictly on local level
          - \c "config_group": the group of the configuration item
          - \c "allowed_values": the list of allowed values for the configuration item if defined
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        if (sh.stepfunction_instanceid) {
            sh.functions = ();
            # add function info
            map sh.functions += StepDefinitionRestClass::staticGetFunctionInfo($1.key, sh.($1.value)), StepFunctions.pairIterator(), sh.($1.value);
        } else if (sh.step_classid) {
            sh."class" = ClassRestClass::staticGetClassInfo(sh.step_classid, 3);
        }

        return RestHandler::makeResponse(200, sh);
    }
}

/** @REST /v3/steps (/v2/steps)

    This REST API path provides actions and information about specific @ref steps "workflow steps"
*/
class StepRestClassV3 inherits StepRestClass {
    private QorusRestClass internSubClass(hash<auto> h) {
        return new StepDefinitionRestClassV3(h);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of all steps

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of step names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with step names, versions, and stepids is returned

        @par Return Value
        This API returns a list of @ref rest_step_hash_v3 elements (if neither \c list nor \c short options are passed as above).
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return doGetIntern(cx, ah, 3);
    }
}

/** @REST /v3/async-queues

    This REST URI path provides actions and information about @ref queue_objects "queues for asynchronous workflow steps"
*/
class AsyncQueuesRestClassV3 inherits QorusRestClass {
    string name() {
        return "async-queues";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # get queue by name or by id
        *hash<auto> q = Qorus.qmm.lookupQueue(arg) ?? Qorus.qmm.rLookupQueue(arg);
        if (exists q) {
            return new AsyncQueueRestClassV3(q);
        }
        # it's able to return back to this instance methods if there is no return of any object instance
    }

    /** @REST GET

        @par Description
        Returns informations about the @ref queue_objects "asynchronous queues"

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c queueid: the queue ID
        - \c name: the queue name
        - \c serviceid: optional: a related service id if present
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        list l = list();
        HashIterator it(Qorus.qmm.getQueueMap());

        while (it.next()) {
            hash h = it.getValue();
            h.queueid = h.queueid.toInt();
            if (!h.serviceid) {
                delete h.serviceid;
            }
            push l, h;
        }

        # simulate old behavior - returns NOTHING in case there are no queues. Not an ampty list
        return RestHandler::makeResponse(200, l.size() ? l : NOTHING);
    }
} # class AsyncQueuesRestClassV3

/** @REST /v3/async-queues/{queue}

    This REST URI path provides actions and information about @ref queue_objects "queues for asynchronous workflow steps"
*/
class AsyncQueueRestClassV3 inherits QorusRestClass {
    private  {
        hash<auto> m_cfg;
    }

    constructor(hash<auto> cfg) {
        m_cfg = cfg;
    }

    string name() {
        return m_cfg.name;
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> ret = AsyncQueueManager::getInfoFromQueueKey(m_cfg.queueid, id);
        if (ret) {
            return new AttributeRestClass(ret);
        }
    }

    /** @REST GET

        @par Description
        Returns information about the current @ref queue_objects "asynchronous queue"

        @par Return Value
        This API returns a hash with the following keys:
        - \c queueid: the queue ID
        - \c name: the queue name
        - \c serviceid: optional: a related service id if present
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, m_cfg);
    }

    /** @REST GET action=info

        @par Description
        gets queue information for a queue entry from the queue name and key

        @par Arguments
        - \c key the key to the entry

        @par Return value
        No value if no information is available, or a hash with the following keys:
        - \c workflow_instanceid: the workflow instance ID of the step and queue entry
        - \c stepid: the step ID of the step and queue entry
        - \c ind: the array index of the step and queue entry (0 for non-array steps)
        - \c queuekey: the queue key string
        - \c queue_data_status: the status of the queue entry: @ref OMQ::QS_Waiting, @ref OMQ::QS_Received, @ref OMQ::QS_Used (Oracle only), or @ref OMQ::QS_Error (rarely, in case of unparsable queue data)
        - \c corrected: if 1, then the queue entry has been corrected. meaning that the back-end function will not be executed and the step will automatically get a @ref OMQ::StatComplete status.
        - \c data: the queue data, if any, set only when the queue data status is @ref OMQ::QS_Received

        @par Errors
        - <tt><b>404 Not Found</b></tt>: the given key does not exist
        - <tt><b>409 Conflict</b></tt>: \c UNKNOWN-QUEUE invalid queue name
    */
    hash<auto> getInfo(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.key || ah.key.typeCode() != NT_STRING || ah.key.size() < 1) {
            throw "ASYNC-QUEUE-ERROR", "Argument 'key' must be a non empty string";
        }
        *hash<auto> ret = AsyncQueueManager::getInfoFromQueueKey(m_cfg.queueid, ah.key);
        if (!ret) {
            return RestHandler::makeResponse(404, sprintf("no key %y exists on async queue %y", ah.key, m_cfg.name));
        }
        return RestHandler::makeResponse(200, ret);
    }

    /** @REST GET action=qinfo

        @par Description
        Returns a list of queue entries on a given queue from the queue ID and an optional status filter

        @par Arguments
        - \c status: a single SQL status value; see @ref OMQ::SQL_QS_ALL and @ref OMQ::QS_ALL for valid values (takes both short
          and long status codes); default all statuses except \c "USED" are returned
        - \c user: the username to search for
        - \c user_interaction_locked: 1 or 0 for the @ref step_user_interaction "user interaction" locked status
        - \c limit: the maximum number of entries to return; default 100
        - \c offset: the offset to return; default 0

        @par Return value
        return either no value or a list of hashes having the following keys:
        - \c queuekey: (string) the key name
        - \c queue_data_status: (string) queue entry status:
          - @ref OMQ::QS_Waiting
          - @ref OMQ::QS_Received
          - @ref OMQ::QS_Used
          - @ref OMQ::QS_Error (rarely, in case of unparsable queue data)
        - \c workflow_instanceid: (int) the workflow instance ID of the queue record
        - \c stepid: (int) the step ID of the queue record
        - \c ind: (int) the step index of the queue record
        - \c user_interaction_locked: (bool) \c True if locked, \c False if not
        - \c user_interaction_user: (string) current user with owning the lock on the queue record, if set
        - \c user_interaction_modified: (date) the timestamp the \a user_interaction_user was last updated, if set
        - \c created: (date) created timestamp for the queue entry
        - \c modified: (date) modified timestamp for the queue entry

        @throw GET-QUEUE-INFO-ERROR queueid is invalid
        @throw INVALID-STATUS status is invalid

        @note Queue entries with a \c "USED" status are only returned if the \a status argument is \c "USED"
        (@ref OMQ::QS_Used) or \c "X" (@ref OMQ::SQL_QS_Used)
     */
    hash<auto> getQinfo(hash<auto> cx, *hash<auto> ah) {
        auto ret = AsyncQueueManager::getQueueInfo(m_cfg.queueid, ah);
        return RestHandler::makeResponse(200, ret);
    }

    /** @REST GET action=status

        @par Description
        gives internal queue status (without parameters: for all queues)

        @par Return Value
        Hash with info. The top level key is the queue name, and
        the value is a queue summary hash.

        The queue summary hash has the following structure. Key values
        are strings with the following format:
        \c "<workflow name>/<workflow version>" with queue status subkeys
        and with integer values corresponding to the number of workflows
        that have queue entries with the given statuses.

        @throw UNKNOWN-QUEUE invalid queue name
     */
    hash<auto> getStatus(hash<auto> cx, *hash<auto> ah) {
        auto ret = AsyncQueueManager::status(m_cfg.queueid);
        return RestHandler::makeResponse(200, ret);
    }

    /** @REST POST action=update

        @SCHEMA
        @summary Updates an asynchronous queue entry to allow an asynchronous step to continue processing

        @desc Updates a pending entry in a system queue with status @ref OMQ::QS_Waiting "WAITING" and sets the \
        status to @ref OMQ::QS_Received "RECEIVED".  Data is stored serialized in YAML format so that type \
        information is preserved when passed to the asynchronous step back end function

        @params
        - key (string): value of the key in the given queue
        - data (any): data to post in the queue entry; this data will be passed to the back end function for evaluation

        @return (string): \c "OK"

        @error (400): invalid argument, invalid status in queue entry
        @error (404): unknown queue or queue key
        @ENDSCHEMA

        @par Errors
        @throw UNKNOWN-QUEUE invalid queue name
        @throw INVALID-KEY no entry exists in the given queue with the given key value
        @throw INVALID-STATUS queue entry does not have status @ref OMQ::QS_Waiting
     */
    hash<auto> postUpdate(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.key || ah.key.typeCode() != NT_STRING || ah.key.size() < 1) {
            throw "ASYNC-QUEUE-ARG-ERROR", "Argument 'key' must be a non empty string";
        }
        if (!exists ah.data) {
            throw "ASYNC-QUEUE-ARG-ERROR", "Argument 'data' must be present";
        }
        on_error {
            if ($1.err == "UNKNOWN-QUEUE" || $1.err == "INVALID-KEY") {
                rethrow "REST-NOT-FOUND-ERROR", sprintf("%s: %s", $1.err, $1.desc);
            }
            if ($1.err == "INVALID-STATUS") {
                rethrow "ASYNC-QUEUE-ARG-ERROR", sprintf("%s: %s", $1.err, $1.desc);
            }
        }
        AsyncQueueManager::updateData(m_cfg.queueid, ah.key, ah."data");
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST POST action=cancel

        @par Description
        cancels a queue entry with status @ref OMQ::QS_Waiting setting @ref OMQ::QS_Used.

        @par Arguments
        - \c key the key to the entry in the given queue to cancel

        @throw UNKNOWN-QUEUE invalid queue name
        @throw INVALID-KEY no entry exists in the given queue with the given key value
        @throw INVALID-STATUS queue entry does not have status @ref OMQ::QS_Waiting
    */
    hash<auto> postCancel(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.key || ah.key.typeCode() != NT_STRING || ah.key.size() < 1) {
            throw "ASYNC-QUEUE-ERROR", "Argument 'key' must be a non empty string";
        }
        AsyncQueueManager::cancelData(m_cfg.queueid, ah.key);
        return RestHandler::makeResponse(200);
    }

    /** @REST PUT action=key

        @par Description
        changes the key for a pending entry in a system queue, only when
        the status is @ref OMQ::QS_Waiting (args: queue name, old key, new key)

        @par Arguments
        - \c oldkey the old key name
        - \c newkey the new key name

        @throw UNKNOWN-QUEUE invalid queue name
        @throw UPDATE-KEY-ERROR empty string passed for oldkey or newkey
        @throw QUEUE-KEY-UPDATE-ERROR no queue entry; queue entry does not have status @ref OMQ::QS_Waiting
    */
    hash<auto> putKey(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.oldkey || ah.oldkey.typeCode() != NT_STRING || ah.oldkey.size() < 1) {
            throw "ASYNC-QUEUE-ERROR", "Argument 'oldkey' must be a non empty string";
        }
        if (!exists ah.newkey || ah.newkey.typeCode() != NT_STRING || ah.newkey.size() < 1) {
            throw "ASYNC-QUEUE-ERROR", "Argument 'newkey' must be a non empty string";
        }
        AsyncQueueManager::updateKey(m_cfg.queueid, ah.oldkey, ah.newkey);
        return RestHandler::makeResponse(200);
    }
} # class AsyncQueueRestClassV3

/** @REST /v3/exec/{id} (/v2/exec/{id})

    This URI path provides actions and information regarding a particular workflow execution instance.
*/
    /** @REST GET

        @par Return Value
        This API returns a hash with the keys of @ref rest_execution_instance_hash_v3, plus the following keys:
        - \c groups: list of @ref rbacgroups "interface groups" that the workflow belongs to; each list element is a @ref rest_interface_group_hash (may be empty)
        - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be empty)
        - \c log_url: a complete URL to the websocket source for the workflow log
    */

/** @REST /v3/exec/{workflowname} (/v2/exec/{workflowname})

    This URI path provides actions and information about workflow execution instances for a particular workflow.
*/
    /** @REST GET

        @par Return Value
        This API returns a list of hashes with the keys of @ref rest_execution_instance_hash_v3, plus the following keys:
        - \c groups: list of @ref rbacgroups "interface groups" that the workflow belongs to; each list element is a @ref rest_interface_group_hash (may be empty)
        - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be empty)
        - \c log_url: a complete URL to the websocket source for the workflow log
    */

/** @REST /v3/exec (/v2/exec)

    This URI path provides actions and information regarding workflow execution instances.
*/
class GlobalWorkflowExecRestClassV3 inherits GlobalWorkflowExecRestClass {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # see if we want to work with named workflows
        if (arg =~ /[[:alpha:]]/u) {
            # try to find version
            *string ver;
            if ((int i = arg.find(":")) != -1) {
                ver = extract arg, i + 1;
                splice arg, -1;
            }
            *list l = map $1 + {
                "executionID": $1.executionID.toInt(),
                "log_url": get_log_url(cx, "workflows/%d", $1.workflowid),
            }, api."omq.system.get-workflow-info"(), $1.name == arg && (!ver || ver == $1.version);

            return new WorkflowExecInstanceGroupRestClass(arg, ver, l);
        }

        softint execid = arg;

        # get running workflow info for the given ID
        *hash<auto> eih = api."omq.system.get-workflow-info"(execid);
        if (eih) {
            eih.executionID = execid;
            eih.log_url = get_log_url(cx, "workflows/%d", eih.workflowid);
            return new WorkflowExecInstanceRestClass(eih);
        }
    }

    /** @REST GET

        @par Return Value
        This API returns a list of hashes with the keys of @ref rest_execution_instance_hash_v3, plus the following keys:
        - \c groups: list of @ref rbacgroups "interface groups" that the workflow belongs to; each list element is a @ref rest_interface_group_hash (may be empty)
        - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be empty)
        - \c log_url: a complete URL to the websocket source for the workflow log
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        *list l = api."omq.system.get-workflow-info"();
        l = map $1 + {
            "executionID": $1.executionID.toInt(),
            "log_url": get_log_url(cx, "workflows/%d", $1.workflowid),
        }, l;
        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /v3/services/{id_or_name}/config/{name}

    This REST URI path provides actions and information related to a particular Qorus.
    Prefix can be passed within the config item name or as following: /v3/services/{id_or_name}/config/{name}?prefix={prefix}.
    @ref service_config_items "service configuration item"
*/
class ServiceConfigItemRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> sh;
        hash<auto> item;

        string name_with_prefix;
    }

    constructor(hash<auto> sh, hash<auto> item) {
        self.sh = sh;
        self.item = item;
        name_with_prefix = item.prefix + item.name;
    }

    string name() {
        return item.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (item.hasKey(arg)) {
                return new AttributeRestClass(item{arg});
            }
        }
    }

    /** @REST GET
        @par Description
        Returns a hash for the current @ref service_config_items "service configuration item"

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": the default value of the configuration item
        - \c "value": the value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "level": the level from where the value is obtained (interface level (e.g. "service:1", "service:2") or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, item);
    }

    /** @REST GET action=yaml
        @par Description
        Returns a hash for the current @ref service_config_items "service configuration item" as a serialized YAML string

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": (serialized YAML string) the default value of the configuration item
        - \c "value": (serialized YAML string) the current value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": (serialized YAML string) the list of allowed values for the configuration item if defined
        - \c "level": the level from where the value is obtained (interface level (e.g. "service:1", "service:2") or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        auto new_item = QorusRestClass::serializeValuesToYaml(item, ("default_value", "value"));
        if (exists new_item.allowed_values) {
            new_item.allowed_values = serializeValuesInListToYaml(new_item.allowed_values);
        }
        return RestHandler::makeResponse(200, new_item);
    }

    /** @REST PUT

        @par Description
        Sets the value for the given @ref service_config_items "service configuration item"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value: the value of the configuration item; must be compatible with the item's declared type

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value: the new value
        - \c info: info about the service configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("value")) {
            return RestHandler::makeResponse(400, "no key \"value\" argument sent in request");
        }

        hash changed = Qorus.qmm.setConfigItemValueOnInterfaceLevel("service", sh.serviceid, name_with_prefix,
                                                                    ah.value);
        changed.info = sprintf("%y configuration item value for %s service %s v%s (%d) has been changed",
                               name_with_prefix, sh.type, sh.name, sh.version, sh.serviceid);
        return RestHandler::makeResponse(200, changed);
    }

    /** @REST PUT action=yaml

        @par Description
        Sets the value for the given @ref service_config_items "service configuration item" using a YAML-serialized string

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value: (YAML-serialized string) the value of the configuration item

          @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value (YAML-serialized string): the new value
        - \c info: info about the service configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<auto> putYaml(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error;
        ah = QorusRestClass::deserializeYamlValues(ah, "value", \error);
        if (exists error) {
            return error;
        }

        hash<auto> result = put(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }

    /** @REST DELETE

        @par Description
        Permanently deletes the current value for the configuration item on this service level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value: deleted value
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        hash result;
        result.value = Qorus.qmm.deleteConfigItemValueOnInterfaceLevel("service", sh.serviceid, name_with_prefix,
                                                                       \result.deleted);
        result.info = sprintf("%y configuration item value for %s service %s v%s (%d) has been deleted",
                              name_with_prefix, sh.type, sh.name, sh.version, sh.serviceid);
        return RestHandler::makeResponse(200, result);
    }

    /** @REST DELETE action=yaml

        @par Description
        Permanently deletes the current value for the configuration item on this service level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value (YAML-serialized string): deleted value
    */
    hash<auto> delYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> result = del(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }
}

/** @REST /v3/services/{id_or_name}/config

    This REST URI path provides actions and information related to Qorus
    @ref service_config_items "service configuration items"
*/
class service_config_itemsRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> sh;
    }

    constructor(hash<auto> sh) {
        self.sh = sh;
    }

    string name() {
        return "config";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        string name_with_prefix = ah.prefix + arg;
        if (*hash<auto> item = sh.config{name_with_prefix}) {
            # get actual item name
            if (item.prefix && name_with_prefix.equalPartial(item.prefix)) {
                arg = name_with_prefix[item.prefix.length()..];
            }
            return new ServiceConfigItemRestClassV3(sh, {"name": arg} + sh.config{name_with_prefix});
        }
    }

    /** @REST GET
        @par Description
        Returns a list of @ref service_config_items "service configuration items" for the service

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": the default value of the configuration item
        - \c "value": the value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "level": the level from where the value is obtained (interface level (e.g. "step:1", "workflow:1")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                                                   sh.config.pairIterator()));
    }

    /** @REST GET action=yaml
        @par Description
        Returns a list of @ref service_config_items "service configuration items" for the service as a YAML-serialized string

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": (YAML-serialized string) the default value of the configuration item
        - \c "value": (YAML-serialized string) the value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        - \c "level": the level from where the value is obtained (interface level (e.g. "step:1", "workflow:1")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> config_copy = sh.config;

        foreach auto config in (config_copy.pairIterator()) {
            config_copy{config.key} = QorusRestClass::serializeValuesToYaml(config.value, ("value", "default_value"));
            if (exists config.value.allowed_values) {
                config_copy{config.key}.allowed_values = serializeValuesInListToYaml(config.value.allowed_values);
            }
        }
        list<auto> items = map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value, config_copy.pairIterator();
        return RestHandler::makeResponse(200, items);
    }
}

/** @REST /v3/services/{id_or_name}/methods

    This REST URI path provides actions and information related to Qorus service methods for a given service.
*/
class ServiceMethodsRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> sh;
    }

    constructor(hash<auto> sh) {
        self.sh = sh;
    }

    string name() {
        return "config";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only look for method if we know it exists
        if (sh.method_name_map{arg}) {
            # find the named method
            foreach hash<auto> mh in (sh.methods) {
                if (mh.name == arg) {
                    mh = {
                        "service_status": sh.status,
                        "serviceid": sh.serviceid,
                        "service_name": sh.name,
                        "service_type": sh.type,
                    } + mh;
                    return new ServiceMethodRestClass(mh);
                }
            }
        }
    }

    /** @REST GET

        @par Description
        Returns information about service methods for the given service

        @par Return Value
        This API returns a list of @ref rest_service_method_hash elements
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, sh.methods);
    }
}

/** @REST /v3/services/{id_or_name} (/v2/services/{id_or_name})

    This REST URI path provides actions and information related to Qorus services.
*/
class ServiceDefinitionRestClassV3 inherits ServiceDefinitionRestClass {
    constructor(hash<auto> sh) : ServiceDefinitionRestClass(sh) {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "logger") {
            return new LoggerRestClass("services", "serviceid", sh.serviceid);
        }
        if (arg == "config") {
            return new service_config_itemsRestClassV3(sh);
        }
        # ensure that methods can be called in all cases
        if (arg == "methods") {
            return new ServiceMethodsRestClassV3(sh);
        }
        if (arg == "authlabels") {
            return new ServiceLabelsRestClass(sh);
        }

        return ServiceDefinitionRestClass::subClassImpl(arg, cx, ah);
    }

    /** @REST PUT action=setRemote

        @par Description
        Sets the remote value for the current service.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c remote: (required) parsed with @ref Qore::parse_boolean(); a boolean value giving the new remote value for the service

        @par Return Value
        This API returns a hash with the following keys:
        - \c updated: @ref True or @ref False
        - \c remote: the new remote value
        - \c info: info about the service update action

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-SETREMOTE-ERROR: missing \c remote argument; cannot update the remote value to @ref True "True" on system services

        @note
        - services that have their remote value changed are temporarily disabled and then reenabled after the change
     */
    hash<auto> putSetRemote(hash<auto> cx, *hash<auto> ah) {
        string info = sprintf("service %s v%s (%d)", sh.name, sh.version, sh.serviceid);

        if (!exists ah.remote) {
            throw "SERVICE-SETREMOTE-ERROR", sprintf("missing \"remote\" argument to update service %s", info);
        }

        rlog(cx, "(%s v%s (%d))", sh.name, sh.version, sh.serviceid);

        ah.remote = parse_boolean(ah.remote);

        if (ah.remote && sh.type == "system") {
            throw "SERVICE-SETREMOTE-ERROR", sprintf("cannot set remote = true on system services (service: %s", info);
        }

        bool updated;
        try {
            updated = Qorus.qmm.updateServiceRemote(sh.serviceid, ah.remote);
            if (updated) {
                info += sprintf(" was updated with remote = %y", ah.remote);
            } else {
                info += sprintf(" was not updated because remote already was %y", ah.remote);
            }
        } catch (hash<ExceptionInfo> ex) {
            info += Qorus.getDebugSystem()
                ? sprintf(", update remote failed: %s", get_exception_string(ex))
                : sprintf(", update remote failed: %s: %s", ex.err, ex.desc);
            updated = False;
        }

        hash<auto> rv = {
            "updated": updated,
            "remote": ah.remote,
            "info": info,
        };

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST GET

        @par Description
        Returns information about the current service

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c lib_source: (optional) parsed with @ref Qore::parse_boolean(); if @ref True "True", then the source code for all library objects is returned
        - \c method_source: (optional) parsed with @ref Qore::parse_boolean(); if @ref True "True", then the source code for all methods is returned in the \c body key in each @ref rest_service_method_hash

        @par Return Value
        This API returns a hash describing the service with the following keys:
        - \c serviceid: the service ID
        - \c type: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        - \c name: the name of the service
        - \c version: the version of the service
        - \c description: the description of the service (if any)
        - \c author: the author of the service (if any)
        - \c parse_options: a list of @ref parse_options "symbolic parse options" for the @ref svcprograms "service program container"
        - \c autostart: a boolean value indicating if the service should be autostarted or not
        - \c manual_autostart: a boolean flag set if the \c autostart value has been changed manually, in which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - \c remote: a boolean value indicating if the service is run as an external process or not
        - \c enabled: a boolean flag indicating if the service is enabled or not; disabled services cannot be loaded
        - \c created: the date/time the service was created
        - \c modified: the date/time the service was last modified
        - \c mappers: a list of @ref mappers "mappers" associated with the service (can be @ref nothing); each mapper element is a @ref rest_mapper_hash
        - \c vmaps: a list of @ref value-maps "value maps" associated with the service (can be @ref nothing); each value map element is a @ref rest_vmap_hash
        - \c latest: a boolean flag indicating if the current contextual service is the latest service of its type and name
        - \c methods: a list of @ref rest_service_method_hash elements
        - \c groups: a list of @ref rbacgroups "interface groups" that the service belongs to; each list element is a @ref rest_interface_group_hash (may be empty)
        - \c resource_files: a list of resource file hashes (if any); each list element is a hash with the following keys:
          - \c name: the name of the resource
          - \c type: the type code for the resource
        - \c status: the status of the service; one of:
          - \c "loaded": loaded but not running
          - \c "running": loaded and running with at least one service thread
          - \c "unloaded": not loaded
        - \c threads: the number of threads running in the service
        - \c resources: a @ref rest_service_resource_hash
        - \c log_url: a complete URL to the websocket source for the service log
        - \c options: a hash of options set on the service
        - \c connections: a list of connection objects that this service depends on; each list element is a @ref rest_conndep_hash (may be empty)
        - \c alerts: a list of alerts raised against the service; each list element is a @ref rest_alert_hash (may be empty)
        - \c state: a hash of saved service state data (if any); see @ref ServiceApi::saveStateData() for more info
        - \c process: a hash of process information, in case the service is running remotely in a @ref qsvc "qsvc" process
    */

    /** @REST POST action=kill

        @par Description
        Kills a remote @ref qsvc "service cluster process"

        @par Return Value
        This API returns a hash with the following keys:
        - status: \c "OK", \c "ERR" if not
        - code: the return code of the \c kill() command: 0 if successful, non-zero if not

        @par Errors
        - <tt><b>404 Not Found</b></tt>: this response is returned if no process is running for the current service
    */
    hash<auto> postKill(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # get current service info to avoid race conditions
        *hash<auto> info = sh.processes[0].id ? Qorus.qmm.lookupProcess(sh.processes[0].id) : NOTHING;
        if (!info) {
            return {
                "code": 404,
                "body": sprintf("no process is currently running for %s service %s v%s (%d)", sh.type, sh.name,
                    sh.version, sh.serviceid),
            };
        }
        return ProcessRestClassV3::staticKillProcess(info, cx, ah);
    }
}

/** @REST /v3/services (/v2/services)

    This REST URI path provides actions and information related to Qorus services;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class ServiceRestClassV3 inherits ServiceRestClassV2, HelpLoggerRestClass, HelpLoggerAppendersRestClass {
    constructor() : HelpLoggerRestClass("services"), HelpLoggerAppendersRestClass("services", "services") {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = ServiceRestClass::staticGetServiceId(arg);
        *hash<auto> svc = ServiceRestClass::staticGetService(cx, id, ah, 3);
        if (!svc) {
            return;
        }

        return new ServiceDefinitionRestClassV3(svc);
    }

    /** @REST GET

        @par Description
        Returns a list of services hashes according to the arguments passed.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c status: one of:
          - \c "running": for only running services (loaded with at least one active thread)
          - \c "loaded": all loaded services (also running services)
          - \c "unloaded": only services not loaded
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of service names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with service names and descriptions is returned

        @par Return Value
        If neither \a list nor \a short are used, then a list of hashes is returned, one element for each service; each hash in the returned list has the following keys:
        - \c type: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        - \c name: the service name
        - \c version: the service version
        - \c patch: the service patch string (if any)
        - \c desc: the service description
        - \c author: the author of the service (if any)
        - \c serviceid: the service ID
        - \c parse_options: a list of @ref parse_options "symbolic parse options" for the @ref svcprograms "service program container" (if any)
        - \c status: the status of the service; one of:
          - \c "loaded": loaded but not running
          - \c "running": loaded and running with at least one service thread
          - \c "unloaded": not loaded
        - \c log: the complete path to the service log file
        - \c threads: the number of active threads in the service
        - \c autostart: boolean value indicating if the service should be autostarted or not
        - \c manual_autostart: a boolean flag set if the \c autostart value has been changed manually, in which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - \c remote: a boolean value indicating if the service is run as an external process or not
        - \c loaded: date/time the service was loaded
        - \c methods: a list of hashes for each service method; each hash element has the following keys:
          - \c name: the name of the method
          - \c desc: a description of the method
          - \c sla: the name of the associated SLA for this call (if any)
        - \c resources: a @ref rest_service_resource_hash (if any)
        - \c resource_files: a list of hashes giving service resource file information (if any); each list element has the following keys:
          - \c type: the type code for the service resource
          - \c name: the name of the service resource
        - \c options: a hash of options set on the service
        - \c groups: a list of @ref rbacgroups "interface groups" that the service belongs to; each list element is a @ref rest_interface_group_hash (may be empty)
        - \c alerts: a list of alerts raised against the service; each list element is a @ref rest_alert_hash (may be empty)
        - \c lib: a @ref rest_library_object_hash
        - \c log_url: a complete URL to the websocket source for the service log
        - \c enabled: a boolean flag indicating if the service is enabled or not; disabled services cannot be loaded
        - \c connections: a list of connection objects that this service depends on; each list element is a @ref rest_conndep_hash (may be empty)
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ServiceRestClass::staticGetServices(cx, ah, 3));
    }

    /** @REST GET action=defaultLogger

        @par Description
        Returns default logger info

        @par Return Value
        This API returns 200 OK and hash with the following keys:
        - \c loggerid: (int) logger id
        - \c params: (hash) logger params
            - \c level: (hash) @ref Logger::LoggerLevel "LoggerLevel"
                - \c "key": logger level string representation
                - \c "value": logger level int representation
            - \c name: (string) logger name
            - \c additivity: (bool) logger additivity
        - \c interface_table_name: (string) interface table name (jobs/workflows/services). If set means default logger
     */
    hash<auto> getDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::getImpl(cx, ah);
    }

    /** @REST POST action=defaultLogger

        @par Description
        Create default Logger

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: required; (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: (string) logger name
        - \c additivity: (bool) logger additivity (default @ref True)
        - \c cloneDefault: (bool) create logger with appenders based on default logger

        @par Return Value
        If success 200 with the logger ID created, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<auto> postDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::postImpl(cx, ah);
    }

    /** @REST DELETE action=defaultLogger

        @par Description
        Delete logger

        @par Return Value
        If success 200 OK, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<auto> delDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::delImpl(cx, ah);
    }

    /** @REST PUT action=defaultLogger

        @par Description
        Set logger params

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: logger name to set
        - \c additivity: logger additivity to set

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<auto> putDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::putImpl(cx, ah);
    }

    /** @REST GET action=defaultLoggerAppenders

        @par Description
        Return all logger appenders

        @par Return Value
        This API returns 200 OK and list with the following hashes:
        - \c appenderId: (int) appenderId
        - \c params: (hash) possible appender parameters, might be missing if not set
            - \c name: (string) appender name
            - \c layoutPattern: (string) appender layout pattern
            - \c rotation: (int) appender layout pattern
            - \c filename: (string) appender filename
    */
    hash<auto> getDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::getImpl();
    }

    /** @REST DELETE action=defaultLoggerAppenders
        @par Description
        Delete logger appender with obtained id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be deleted

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<auto> delDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::delImpl(cx, ah);
    }

    /** @REST POST action=defaultLoggerAppenders

        @par Description
        Create logger appenders

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK and appender id, in case of fail one of the error codes: 400, 409 and \a string of error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<auto> postDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::postImpl(cx, ah);
    }

    /** @REST PUT action=defaultLoggerAppenders
        @par Description
        Update logger appender with the given id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be update
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<auto> putDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::putImpl(cx, ah);
    }
}

/** @REST /v3/orders/{id} (/v2/orders/{id})

    This REST URI path provides actions and information about specific workflow orders.
*/
class WorkflowOrderInstanceRestClassV3 inherits WorkflowOrderInstanceRestClassV2 {
    constructor(hash<auto> wf, int api_version = 3) : WorkflowOrderInstanceRestClassV2(wf, api_version) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (name == "async-queue") {
            return new WorkflowOrderInstanceAsyncQueueRestClassV3(wf.workflow_instanceid);
        }

        return WorkflowOrderInstanceRestClassV2::subClassImpl(name, cx, ah);
    }

    /** @REST GET

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

    /** @REST POST action=lockUserInteractionStep

        @SCHEMA
        @summary Locks the next available queue entry in a user interaction step

        @desc Locks the next available queue entry eligible for @ref step_user_interaction "user interaction" for \
        the named step in the current workflow order and returns the step information or a \c 404 \c Not \c Found \
        error if no such data is available

        @params
        - stepid (*int): the ID of the step to acquire user interaction data from; either this or \a stepname is \
          required
        - stepname (*string): the name of the step to acquire user interaction data from; either this or \a stepid \
          is required

        @return (hash WorkflowLockUseInteractionStepResultInfo): information about the result of the operation
        - workflow_instanceid (int): the workflow order instance ID
        - stepid (int): the step ID of the step
        - ind (int): the step instance index number
        - queuekey (string): the queue key ID
        - queueid (int): the ID of the async queue
        - queuename (string): the name of the async queue
        - data (*hash[any] UndefinedHash): any step data already present

        @error (400): missing or invalid arguments
        @error (404): no data available on the queue to lock

        @since Qorus 4.0.1
        @ENDSCHEMA

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if there is an error with the arguments to the call
        - <tt><b>404 Not Found</b></tt>: this response is returned if no data is available to lock on the queue
    */
    hash<auto> postLockUserInteractionStep(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        string key;
        softstring value;
        if (ah.hasKey("stepid")) {
            if (!ah.stepid.intp()) {
                return RestHandler::makeResponse(400, sprintf("the \"stepid\" argument must be an integer stepid; "
                    "value given: %y", ah.stepid));
            }
            key = "stepid";
            value = ah.stepid;
        } else if (ah.hasKey("stepname")) {
            if (!ah.stepname.strp()) {
                return RestHandler::makeResponse(400, sprintf("the \"stepname\" argument must be a string name; value "
                    "given: %y", ah.stepname));
            }
            key = "stepname";
            value = ah.stepname;
        } else {
            # make a list of steps with user interaction
            *list<auto> sl = map $1{"stepid", "stepname"}, wf.StepInstances, $1.user_interaction;
            return RestHandler::makeResponse(400, sprintf("missing either the \"stepid\" or \"stepname\" argument; "
                "args passed: %y; steps supporting user interaction in this workflow: %y", ah, sl));
        }

        # make a map of steps with user interaction
        *hash<auto> sh = map {$1{key}: $1}, wf.StepInstances, $1.user_interaction;

        *hash<auto> stepinfo = sh{value};
        if (!stepinfo) {
            return RestHandler::makeResponse(404, sprintf("no step supporting user interactions in workflow %s v%s "
                "(%d) found with %s = %y; steps supporting user interaction in this workflow order: %y", wf.name, wf.version,
                wf.workflowid, key, value, (map $1{"stepid", "stepname"}, sh.iterator())));
        }

        *hash<auto> rv = sqlif.returnLockUserInteractionStep(stepinfo.queueid, "%SYS%",
            wf.workflow_instanceid);
        if (!rv) {
            string errmsg = sprintf("no data available for step %s v%s (%d) on queueid %d %y",
                stepinfo.stepname, stepinfo.stepversion, stepinfo.stepid, stepinfo.queueid, stepinfo.queuename);
            if (ah.workflow_instanceid) {
                errmsg += sprintf(" for workflow_instanceid %d", ah.workflow_instanceid);
            }
            return RestHandler::makeResponse(404, errmsg);
        }

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=stepData

        @SCHEMA
        @summary Replaces the @ref stepdata "dynamic step data" for an existing order step

        @desc Replaces the @ref stepdata "dynamic step data" for an existing order step; if the step's queue data \
        is locked by another user, the call will fail with a <tt>409 Conflict</tt> error

        @params
        - stepid (int): required: the step ID of the step
        - ind (int): required: the step instance index value; use 0 for non-array steps
        - newdata (*hash[any] UndefinedHash): required: the new @ref stepdata "dynamic step data" for the current \
          workflow order and step; can also be @ref nothing which will remove all step data from the current step

        @return (string): \c "OK"

        @error (400): invalid arguments
        @error (409): cannot lock order for updating, order has \c COMPLETE status

        @since Qorus 4.0.1
        @ENDSCHEMA

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid arguments passed to the call
        - <tt><b>404 Not Found</b></tt>: the given stepid and ind do not exist in the current workflow order
        - <tt><b>409 Conflict</b></tt>: \c REPLACE-STEP-DATA-ERROR: if the workflow order is owned by another Qorus
          instance, the step data is locked by another user, or the order is COMPLETE
    */
    hash<auto> putStepData(hash<auto> cx, *hash<auto> ah) {
        if (*hash<auto> err = checkStepInd(ah)) {
            return err;
        }

        if (*hash<auto> err = checkNewData(ah)) {
            return err;
        }

        try {
            SM.replaceStepData(cx, wf.workflowid, wf.workflow_instanceid, ah.stepid, ah.ind, ah.newdata,
                "%SYS%");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NO-DATA") {
                return RestHandler::makeResponse(404, ex.desc);
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST GET action=stepData

        @SCHEMA
        @summary Returns @ref stepdata "dynamic step data" for the order and step instance

        @desc Returns @ref stepdata "dynamic step data" for the order and step instance

        @params
        - \c stepid: (int) required: the step ID of the step
        - \c ind: (int) required: the step instance index value; use 0 for non-array steps

        @return (*hash[any] UndefinedHash): the workflow order @ref stepdata "dynamic step data" for the given step \
        instance

        @error (404): the given stepid and ind values do not exist in the workflow order

        @since Qorus 4.0.1
        @ENDSCHEMA

        @par Errors
        - <tt><b>404 Not Found</b></tt>: the given stepid and ind values do not exist in the workflow order
    */
    hash<auto> getStepData(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> err;
        if (err = checkStepInd(ah)) {
            return err;
        }

        *hash<auto> rv = internGetStepData(ah, \err);
        if (err) {
            return err;
        }
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST GET action=yamlStepData

        @par Description
        Returns @ref stepdata "dynamic step data" for the order as a serialized YAML string for potential editing

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c stepid: (int) required: the step ID of the step
        - \c ind: (int) required: the step instance index value; use 0 for non-array steps

        @par Return Value
        This API returns a YAML-serialized string of workflow order @ref stepdata "dynamic step data"; if no
        @ref stepdata "dynamic step data" is in place; then a YAML-serialized string representing no value (i.e.
        \c "null") will be returned.

        @par Errors
        - <tt><b>404 Not Found</b></tt>: the given stepid and ind values do not exist in the workflow order

        @since Qorus 4.0.1
    */
    hash<auto> getYamlStepData(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> err;
        if (err = checkStepInd(ah)) {
            return err;
        }

        *hash<auto> rv = internGetStepData(ah, \err);
        if (err) {
            return err;
        }
        return RestHandler::makeResponse(200, make_yaml(rv, YAML::BlockStyle));
    }

    /** @REST PUT action=yamlStepData

        @par Description
        Replaces the @ref stepdata "dynamic step data" for an existing order using a YAML-serialized string for the
        new dynamic step data

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c stepid: (int) required: the step ID of the step
        - \c ind: (int) required: the step instance index value; use 0 for non-array steps
        - \c newdata: (YAML-serialized string) required: the new @ref stepdata "dynamic step data" for the current
          workflow order and step; can also be deserialized to @ref nothing which will remove all step data from the
          current step

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the \a newdata argument is not a string or cannot be parsed as
          valid YAML
        - <tt><b>404 Not Found</b></tt>: the given stepid and ind values do not exist in the workflow order

        @since Qorus 4.0.1
    */
    hash<auto> putYamlStepData(hash<auto> cx, *hash<auto> ah) {
        if (*hash<auto> err = checkStepInd(ah)) {
            return err;
        }
        if (ah.newdata.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("expecting type \"string\" for the \"newdata\" key; got "
                "type %y instead", ah.newdata.type()));
        }

        try {
            ah.newdata = parse_yaml(ah.newdata);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "YAML-PARSER-ERROR") {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        # verify that the YAML data parsed to NOTHING or a hash
        if (*hash<auto> err = checkNewData(ah)) {
            return err;
        }
        try {
            SM.replaceStepData(cx, wf.workflowid, wf.workflow_instanceid, ah.stepid, ah.ind, ah.newdata,
                "%SYS%");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NO-DATA") {
                return RestHandler::makeResponse(404, ex.desc);
            }
            rethrow;
        }

        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST POST action=releaseUserInteractionStepLock

        @SCHEMA
        @summary Releases a lock owned by the calling user on a step supporting \
        @ref step_user_interaction "user interaction"

        @desc Releases a lock owned by the calling user on a step supporting \
        @ref step_user_interaction "user interaction"

        @params
        - stepid (int): the step ID of the step
        - ind (int): the step instance index value; use 0 for non-array steps

        @return (string): \c "OK"

        @error (400): invalid arguments
        @error (404): the given stepid and ind values do not exist in the workflow order or the step is not an \
        @ref asyncsteps "asynchronous step" with the @ref step_user_interaction "user-interaction" API enabled

        @since Qorus 4.0.1
        @ENDSCHEMA

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid arguments passed to the call
        - <tt><b>404 Not Found</b></tt>: the given stepid does not correspond to an
          @ref asyncsteps "asynchronous step" with the @ref step_user_interaction "user-interaction" API enabled or does
          not exist
    */
    hash<auto> postReleaseUserInteractionStepLock(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> err;
        *hash<auto> stepinfo = checkUserInteractionStep(cx, ah, \err);
        if (err) {
            return err;
        }

        try {
            SM.releaseUserInteractionStepLock(cx, wf.workflowid, wf.workflow_instanceid, ah.stepid, ah.ind,
                "%SYS%");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NO-DATA") {
                return RestHandler::makeResponse(404, ex.desc);
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST POST action=breakUserInteractionStepLock

        @SCHEMA
        @summary Forcibly releases a lock on a step supporting \
        @ref step_user_interaction "user interaction"

        @desc Forcibly releases a lock on a step supporting \
        @ref step_user_interaction "user interaction"

        @params
        - stepid (int): the step ID of the step
        - ind (int): the step instance index value; use 0 for non-array steps
        - note (string): a note to be added to the order on why the lock was broken

        @return (string): \c "OK"

        @error (400): invalid arguments
        @error (404): the given stepid and ind values do not exist in the workflow order or the step is not an \
        @ref asyncsteps "asynchronous step" with the @ref step_user_interaction "user-interaction" API enabled

        @since Qorus 4.0.1
        @ENDSCHEMA
    */
    hash<auto> postBreakUserInteractionStepLock(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> err;
        *hash<auto> stepinfo = checkUserInteractionStep(cx, ah, \err);
        if (err) {
            return err;
        }

        if (ah.note.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("the \"note\" argument is missing or invalid; got type %y; "
                "expecting \"string\"", ah.note.type()));
        }

        try {
            SM.breakStepLock(wf, ah.stepid, ah.ind, "%SYS%", ah.note);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NO-DATA") {
                return RestHandler::makeResponse(404, ex.desc);
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, "OK");
    }

    private *hash<auto> checkUserInteractionStep(hash<auto> cx, *hash<auto> ah, reference<hash<auto>> err) {
        if (err = checkStepInd(ah)) {
            return;
        }

        # make a map of steps with user interaction
        *hash<auto> sh = map {$1.stepid: $1}, wf.StepInstances, $1.user_interaction;
        *hash<auto> stepinfo = sh{ah.stepid};
        if (!stepinfo) {
            err = RestHandler::makeResponse(404, sprintf("no step supporting user interactions in workflow %s v%s "
                "(%d) found with stepid = %y; steps with user interactions in this workflow: %y", wf.name, wf.version,
                wf.workflowid, ah.stepid, (map $1{"stepid", "stepname"}, sh.iterator())));
            return;
        }

        return stepinfo;
    }

    private static *hash<auto> checkStepInd(*hash<auto> ah) {
        if (!ah.stepid.intp()) {
            return RestHandler::makeResponse(400, sprintf("the \"stepid\" argument must be an integer stepid; "
                "value given: %y", ah.stepid));
        }
        if (!ah.ind.intp()) {
            return RestHandler::makeResponse(400, sprintf("the \"ind\" argument must be an integer index value; "
                "value given: %y", ah.ind));
        }
    }

    private static *hash<auto> checkNewData(*hash<auto> ah) {
        switch (ah.newdata.typeCode()) {
            case NT_HASH:
            case NT_NOTHING:
                break;
            default:
                return RestHandler::makeResponse(400, sprintf("the \"newdata\" key is type %y; expecting \"hash\" or "
                    "\"nothing\"", ah.newdata.type()));
        }
    }

    private *hash<auto> internGetStepData(hash<auto> ah, reference<hash> err) {
        # find the step data
        *hash<auto> rv;
        bool found;
        foreach hash<auto> sh in (wf.stepdata) {
            if (sh.stepid == ah.stepid && ah.ind < sh.data.size()) {
                found = True;
                rv = sh.data[ah.ind];
            }
        }

        if (!found) {
            # check if the step instance exists to send a 404 response if appropriate
            foreach hash<auto> sh in (wf.StepInstances) {
                if (sh.stepid == ah.stepid && sh.ind == ah.ind) {
                    found = True;
                    break;
                }
            }

            if (!found) {
                err = RestHandler::makeResponse(404, sprintf("stepid %d[%d] does not exist in workflow order %d for "
                    "workflow %s v%s (%d)", ah.stepid, ah.ind, wf.workflow_instanceid, wf.name, wf.version,
                    wf.workflowid));
                return;
            }
        }

        return rv;
    }
}

/** @REST /v3/orders/{id}/async-queue

    This REST URI path provides actions and information about specific workflow orders' @ref queue_objects
*/
class WorkflowOrderInstanceAsyncQueueRestClassV3 inherits QorusRestClass {
    private {
        int m_wfiid;
    }

    constructor(softint wfiid) {
        m_wfiid = wfiid;
    }

    string name() {
        return "async-queue";
    }

    /** @REST GET

        @par Description
        Gets queue information for a particular workflow and step

        @par Arguments
        - \c stepid the stepid to query. Optional, defaults to 0
        - \c int the array index offset of the step to query (0 for non-array steps). Optional.

        @par Return Value
        A list of hashes or an ampty list is returned.

        The queue info hash has the following keys:
        - \c workflow_instanceid: the workflow instance ID of the step and queue entry
        - \c stepid: the step ID of the step and queue entry
        - \c ind: the array index of the step and queue entry (0 for non-array steps)
        - \c queuekey: the queue key string
        - \c queue_data_status: the status of the queue entry: @ref OMQ::QS_Waiting, @ref OMQ::QS_Received, @ref OMQ::QS_Used (Oracle only), or @ref OMQ::QS_Error (rarely, in case of unparsable queue data)
        - \c corrected: if 1, then the queue entry has been corrected. meaning that the back-end function will not be executed and the step will automatically get a @ref OMQ::StatComplete status.
        - \c data: the queue data, if any, set only when the queue data status is @ref OMQ::QS_Received

        @throw GET-INFO-ERROR invalid workflow_instanceid
     */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        auto ret = AsyncQueueManager::getInfo(m_wfiid, ah.stepid ?? 0, ah.ind ?? NOTHING);
        return RestHandler::makeResponse(200, ret);
    }

    /** @REST POST action=correct

        @par Description
        corrects a queue entry with status @ref OMQ::QS_Waiting,
        sets the status to @ref OMQ::QS_Received and sets the
        \c corrected attribute to \c True

        This will effective cause an asynchronous step to be skipped
        without the back end function being run at all; the step will
        be processed to @ref OMQ::StatComplete as soon as the
        corrected queue entry is delivered to workflow execution
        instance processing this order. See @ref queue_objects

        @par Arguments
        - \c stepid the stepid to update
        - \c ind the array index offset of the step to update (0 for non-array steps)

        @throw QUEUE-CORRECT-DATA-ERROR invalid workflow_instanceid or stepid
        @throw INVALID-WORKFLOW-DATA no queue data for the given step
        @throw INVALID-STATUS queue entry does not have status @ref OMQ::QS_Waiting
        @throw ALREADY-CORRECTED queue entry has already been corrected
     */
    hash<auto> postCorrect(hash<auto> cx, *hash<auto> ah) {
        foreach string key in (("stepid", "ind")) {
            if (!exists ah{key}) {
                throw "ASYNC-QUEUE-ERROR", sprintf("Argument '%s' must be present", key);
            }
        }
        AsyncQueueManager::correctData(m_wfiid, ah.stepid, ah.ind);
        return RestHandler::makeResponse(200);
    }
} # WorkflowOrderInstanceAsyncQueueRestClassV3

/** @REST /v3/orders (/v2/orders)

    This URI path provides information and actions related to workflow order data.
*/
class GlobalOrderRestClassV3 inherits GlobalOrderRestClassV2 {
    private *QorusRestClass internGetOrderInstanceRestClass(hash<auto> h) {
        return new WorkflowOrderInstanceRestClassV3(h);
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        if (id == "all")
            return self;

        # if id is not an int we can expect call of order/<method>
        if (!id.intp()) {
            return NOTHING;
        }

        bool with_sensitive_data = (cx.internal || cx.ssl);
        # workflow access by the given user is checked in the getWFIAllInfo() call
        *hash<auto> h = sysinfo.getWFIAllInfo(id, NOTHING, False, with_sensitive_data);
        if (h) {
            return internGetOrderInstanceRestClass(h);
        }
        throw "WORKFLOW-ORDER-ERROR", sprintf("there is no workflow_instanceid %d", id);
    }
}

/** @REST /v3/workflows (/v2/workflows)

    This URI path allows workflows to be queried and for actions on multiple workflows to be performed;
    this is the URI path parent of workflow-specific actions as well.
*/
class WorkflowRestClassV3 inherits WorkflowRestClassV2, HelpLoggerRestClass, HelpLoggerAppendersRestClass {
    constructor() : HelpLoggerRestClass("workflows"), HelpLoggerAppendersRestClass("workflows", "workflows") {
    }

    private *QorusRestClass internGetWorkflowDefinitionSubclass(hash<auto> wf) {
        return new WorkflowDefinitionRestClassV3(wf);
    }

    private *QorusRestClass internGetWorkflowDefinitionSubclass() {
    }

    private *QorusRestClass internGetOrderInstanceRestClass(hash<auto> h) {
        return new WorkflowOrderInstanceRestClassV3(h);
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg =~ /^order-/) {
            softint wfiid = arg.substr(6);
            # workflow access by the given user is checked in the getWFIAllInfo() call
            *hash<auto> h = sysinfo.getWFIAllInfo(wfiid, NOTHING, False);
            if (h)
                return internGetOrderInstanceRestClass(h);
            throw "WORKFLOW-ORDER-ERROR", sprintf("there is no workflow_instanceid %d", wfiid);
        }

        int id;
        # return a 404 Not Found response if the wf does not exist
        try {
            id = WorkflowRestClass::staticGetWorkflowId(arg, True);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "WORKFLOW-ERROR") {
                qlog(LoggerLevel::INFO, "wf %y: %s", arg, get_exception_string(ex));
                return;
            }
            rethrow;
        }

        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;
        ah.lib_source = ah.lib_source ? parse_boolean(ah.lib_source) : False;
        ah.all_source = ah.all_source ? parse_boolean(ah.all_source) : False;
        return internGetWorkflowDefinitionSubclass(WorkflowRestClass::staticGetWorkflowFromCache(cx, id, ah.date, ah.sqlcache, ah.all_source || ah.lib_source, 3));
    }

    /** @REST GET

        @par Description
        Returns information about workflows

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c deprecated: optional; parsed with @ref Qore::parse_boolean(); if @ref False then no deprecated workflows will be returned; default @ref True
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of workflow names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of workflow names and descriptions is returned
        - \c date: optional; parsed as a date; the minimum date for historical workflow order overview information; if omitted then defaults to the past 24 hours
        - \c sqlcache: optional; parsed with @ref Qore::parse_boolean(); if @ref False then no SQL cache will be used for historical info; default @ref True

        @par Return Value
        If neither \a list nor \a short are used, then a list of hashes is returned, one element for each workflow; each hash in the returned list represents a workflow as a @ref rest_workflow_description_hash_v3
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        ah.deprecated = exists ah.deprecated ? parse_boolean(ah.deprecated) : True;

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.name, WorkflowRestClass::staticGetWorkflowMetadata(ah.deprecated, 3)));

        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200, (map sprintf("%s v%s (%d) remote: %d autostart: %d", $1.name, $1.version, $1.workflowid, $1.remote, $1.autostart), WorkflowRestClass::staticGetWorkflowMetadata(ah.deprecated, 3)));

        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;

        return RestHandler::makeResponse(200, WorkflowRestClass::staticGetWorkflows(ah.date, ah.sqlcache, ah.deprecated, 3));
    }

    /** @REST GET action=defaultLogger

        @par Description
        Returns default logger info

        @par Return Value
        This API returns 200 OK and hash with the following keys:
        - \c loggerid: (int) logger id
        - \c params: (hash) logger params
            - \c level: (hash) @ref Logger::LoggerLevel "LoggerLevel"
                - \c "key": logger level string representation
                - \c "value": logger level int representation
            - \c name: (string) logger name
            - \c additivity: (bool) logger additivity
        - \c interface_table_name: (string) interface table name (jobs/workflows/services). If set means default logger
     */
    hash<auto> getDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::getImpl(cx, ah);
    }

    /** @REST POST action=defaultLogger

        @par Description
        Create default Logger

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: required; (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: (string) logger name
        - \c additivity: (bool) logger additivity (default @ref True)
        - \c cloneDefault: (bool) create logger with appenders based on default logger

        @par Return Value
        If success 200 with the logger ID created, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<auto> postDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::postImpl(cx, ah);
    }

    /** @REST PUT action=defaultLogger

        @par Description
        Set logger params

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: logger name to set
        - \c additivity: logger additivity to set

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<auto> putDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::putImpl(cx, ah);
    }

    /** @REST DELETE action=defaultLogger

        @par Description
        Delete logger

        @par Return Value
        If success 200 OK, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<auto> delDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::delImpl(cx, ah);
    }

    /** @REST GET action=defaultLoggerAppenders

        @par Description
        Return all logger appenders

        @par Return Value
        This API returns 200 OK and list with the following hashes:
        - \c appenderId: (int) appenderId
        - \c params: (hash) possible appender parameters, might be missing if not set
            - \c name: (string) appender name
            - \c layoutPattern: (string) appender layout pattern
            - \c rotation: (int) appender layout pattern
            - \c filename: (string) appender filename
    */
    hash<auto> getDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::getImpl();
    }

    /** @REST DELETE action=defaultLoggerAppenders
        @par Description
        Delete logger appender with obtained id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be deleted

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<auto> delDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::delImpl(cx, ah);
    }

    /** @REST POST action=defaultLoggerAppenders

        @par Description
        Create logger appenders

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK and appender id, in case of fail one of the error codes: 400, 409 and \a string of error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<auto> postDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::postImpl(cx, ah);
    }

    /** @REST PUT action=defaultLoggerAppenders
        @par Description
        Update logger appender with the given id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be update
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<auto> putDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::putImpl(cx, ah);
    }
}

/** @REST /v3/workflows/{id_or_name}/config/{name}

    This REST URI path provides actions and information related to a particular Qorus.
    Prefix can be passed within the config item name or as following: /v3/workflows/{id_or_name}/config/{name}?prefix={prefix}.
    @ref workflowconfigitems "workflow configuration item"
*/
class WorkflowConfigItemRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> wh;
        hash<auto> item;

        string name_with_prefix;
    }

    constructor(hash<auto> wh, hash<auto> item) {
        self.wh = wh;
        self.item = item;

        name_with_prefix = item.prefix + item.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (item.hasKey(arg)) {
                return new AttributeRestClass(item{arg});
            }
        }
    }

    string name() {
        return item.name;
    }

    /** @REST GET
        @par Description
        Returns a hash for the current @ref workflowconfigitems "workflow configuration item"

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "value": the value of the configuration item
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, item);
    }

    /** @REST GET action=yaml
        @par Description
        Returns a hash for the current @ref workflowconfigitems "workflow configuration item" as a serialized YAML string

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "value": (YAML-serialized string) the value of the configuration item
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        auto new_item = QorusRestClass::serializeValuesToYaml(item, ("value",));
        if (exists new_item.allowed_values) {
            new_item.allowed_values = serializeValuesInListToYaml(new_item.allowed_values);
        }
        return RestHandler::makeResponse(200, new_item);
    }

    /** @REST PUT

        @par Description
        Sets the value for the given @ref workflowconfigitems "workflow configuration item"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value: the value of the configuration item; must be compatible with the item's declared type

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value: the new value
        - \c info: info about the workflow configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("value")) {
            return RestHandler::makeResponse(400, "no key \"value\" argument sent in request");
        }

        hash changed = Qorus.qmm.setConfigItemValueOnInterfaceLevel("workflow", wh.workflowid, name_with_prefix,
                                                                    ah.value);
        changed.info = sprintf("%y configuration item value for workflow %s v%s (%d) has been changed",
                               name_with_prefix, wh.name, wh.version, wh.workflowid);
        return RestHandler::makeResponse(200, changed);
    }

    /** @REST PUT action=yaml

        @par Description
        Sets the value for the given @ref workflowconfigitems "workflow configuration item" using a YAML-serialized string

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value: (YAML-serialized string) the value of the configuration item

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value (YAML-serialized string): the new value
        - \c info: info about the workflow configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<auto> putYaml(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error;
        ah = QorusRestClass::deserializeYamlValues(ah, "value", \error);
        if (exists error) {
            return error;
        }

        hash<auto> result = put(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }

    /** @REST DELETE

        @par Description
        Permanently deletes the current value for the configuration item on this workflow level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value: deleted value
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        hash result;
        result.value = Qorus.qmm.deleteConfigItemValueOnInterfaceLevel("workflow", wh.workflowid, name_with_prefix,
                                                                       \result.deleted);
        result.info = sprintf("%y configuration item value for workflow %s v%s (%d) has been deleted",
                              name_with_prefix, wh.name, wh.version, wh.workflowid);
        return RestHandler::makeResponse(200, result);
    }

    /** @REST DELETE action=yaml

        @par Description
        Permanently deletes the current value for the configuration item on this workflow level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value (YAML-serialized string): deleted value
    */
    hash<auto> delYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> result = del(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }
}

/** @REST /v3/workflows/{id_or_name}/instances (/v2/workflows/{id_or_name}/instances)

    This REST URI path provides actions and information about workflow execution instances for a particular workflow.
*/
class WorkflowInstanceRestClassV3 inherits WorkflowInstanceRestClass {
    constructor(hash<auto> cx, hash<auto> wf) : WorkflowInstanceRestClass(cx, wf, 3) {
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        # get running workflow info for the given ID
        *hash<auto> eih = api."omq.system.get-workflow-info"(id);
        if (eih) {
            eih.executionID = eih.executionID.toInt();
            return new WorkflowExecInstanceRestClass(eih);
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(id))
                return new AttributeRestClass(wf{id});
        }
    }

    /** @REST GET

        @par Return Value
        This API returns a list of hashes with the keys of @ref rest_execution_instance_hash_v3 for the current workflow, plus the following keys:
        - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be empty)
        - \c log_url: a complete URL to the websocket source for the workflow log
    */
}

/** @REST /v3/workflows/{id_or_name}/orders (/v2/workflows/{id_or_name}/orders)

    This REST URI path provides actions and information about workflow orders for the current workflow.
*/
class WorkflowOrderRestClassV3 inherits WorkflowOrderRestClassV2 {
    constructor(hash<auto> wf) : WorkflowOrderRestClassV2(wf) {
    }

    private *QorusRestClass internGetOrderInstanceRestClass(hash<auto> h) {
        return new WorkflowOrderInstanceRestClassV3(h);
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        # workflow access by the given user is checked in the getWFIAllInfo() call
        *hash<auto> h = sysinfo.getWFIAllInfo(id, NOTHING, False, cx.internal || cx.ssl);
        if (h) {
            if (h.InstanceInfo.workflowid != wf.workflowid)
                throw "WORKFLOW-ORDER-ERROR", sprintf("order %d is not an order for workflow %s v%s (%d); it belongs to %s v%s (%d) instead",
                                                      id, wf.name, wf.version, wf.workflowid, h.InstanceInfo.name, h.InstanceInfo.version, h.InstanceInfo.workflowid);
            return internGetOrderInstanceRestClass(h);
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(id))
                return new AttributeRestClass(wf{id});
        }
    }

    /** @REST GET

        @par Description
        Returns a list of hashes for orders for the current workflow matching the search criteria

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c date: an alternate key for \c modified
        - \c desc: return in descending order
        - \c ids: an alternate key for \c workflow_instanceid
        - \c keyname: the name of a search key to be used with the \a keyvalue value(s)
        - \c keyvalue: the value(s) of workflow order search key(s) to use (optionally used in conjunction with \a keyname)
        - \c limit: max number of rows to return, if not given, then the value of the \a "row-limit" option is used (default: 100)
        - \c maxmodified: maximum modified date
        - \c maxstarted: maximum start date
        - \c minstarted: minimum start date
        - \c modified: minimum modified date
        - \c offset: row offset
        - \c sort: columns for sorting the results
        - \c status: status value(s) (see @ref StatusDescriptions for possible values)
        - \c statuses: an alternate key for \c status
        - \c workflow_instanceid: workflow_instanceid values(s)

        @par Return Value
        This API returns @ref nothing if no orders match or a list of hashes with the following keys for all data matched according to the search arguments:
        - \c name: the name of the workflow
        - \c version: the version of the workflow
        - \c workflow_instanceid: the workflow order instance ID
        - \c workflowid: the workflow ID
        - \c workflowstatus: the status of the workflow order instance (see @ref StatusDescriptions for possible values)
        - \c status_sessionid: the application session ID that owns the workflow order instance data or 0 if the data is now owned by any application session
        - \c started: the start date/time of the workflow order instance
        - \c completed: the completed date/time for the workflow order instance
        - \c modified: the last modified date/time of the workflow order instance
        - \c parent_workflow_instanceid: the parent workflow order ID if present
        - \c synchronous: if 1, indicates that the order is being executed synchronously
        - \c business_error: a boolean flag indicating if the workflow order has an error status due to a business error
        - \c operator_lock: a string giving the username of the user with an operator lock on the order
        - \c note_count: the number of notes stored against the order
        - \c warning_count: the number of warnings raised against the order
        - \c error_count: the number of errors raised against the order
        - \c retry_count: the number of times the order was subject to a @ref OMQ::StatRetry "RETRY" status due to a technical error
        - \c custom_status: a custom status for the order
        - \c priority: the priority of the workflow order
        - \c scheduled: the future scheduled date of the workflow order (if any)
        - \c custom_status_desc: a description for the custom status (if any)
        - \c actions: a list of possible actions on the workflow
    */
}

/** @REST /v3/workflows/{id_or_name}/config

    This REST URI path provides actions and information related to Qorus
    @ref workflowconfigitems "workflow configuration item values"
*/
class WorkflowConfigItemsRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> wh;
    }

    constructor(hash<auto> wh) {
        self.wh = wh;
    }

    string name() {
        return "config";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        string name_with_prefix = ah.prefix + arg;
        if (*hash<auto> item = wh.config{name_with_prefix}) {
            # get actual item name
            if (item.prefix && name_with_prefix.equalPartial(item.prefix)) {
                arg = name_with_prefix[item.prefix.length()..];
            }
            return new WorkflowConfigItemRestClassV3(wh, {"name": arg} + wh.config{name_with_prefix});
        }
    }

    /** @REST GET
        @par Description
        Returns a list of @ref workflowconfigitems "workflow configuration item values" for the workflow

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "value": the current value of the configuration item on this level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                                                   wh.config.pairIterator()));
    }

    /** @REST GET action=yaml
        @par Description
        Returns a list of @ref workflowconfigitems "workflow configuration item values" for the workflow

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "value": (YAML-serialized string) the current value of the configuration item on this level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> config_copy = wh.config;

        foreach auto config in (config_copy.pairIterator()) {
            config_copy{config.key} = QorusRestClass::serializeValuesToYaml(config.value, ("value",));
            if (exists config.value.allowed_values) {
                config_copy{config.key}.allowed_values = serializeValuesInListToYaml(config.value.allowed_values);
            }
        }

        list<auto> items = map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                               config_copy.pairIterator();
        return RestHandler::makeResponse(200, items);
    }

    /** @REST POST

        @par Description
        Creates the value for the given @ref step_config_items "step configuration items" on the workflow level

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c name: the name of the configuration item
        - \c value: the value of the configuration item; must be compatible with the item's declared type

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value: the new value
        - \c info: info about the workflow configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("value") || !ah.hasKey("name")) {
            return RestHandler::makeResponse(400, "no key \"value\" or \"name\" argument sent in request");
        }

        hash changed = Qorus.qmm.setConfigItemValueOnInterfaceLevel("workflow", wh.workflowid, ah.name, ah.value, True);
        changed.info = sprintf("%y configuration item value for workflow %s v%s (%d) has been changed",
                               ah.name, wh.name, wh.version, wh.workflowid);
        return RestHandler::makeResponse(200, changed);
    }

    /** @REST POST action=yaml

        @par Description
        Creates the value for the given @ref step_config_items "step configuration items" on the workflow level using a YAML-serialized string

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c name: the name of the configuration item
        - \c value: (YAML-serialized string) the value of the configuration item

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value (YAML-serialized string): the new value
        - \c info: info about the workflow configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<auto> postYaml(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error;
        ah = QorusRestClass::deserializeYamlValues(ah, "value", \error);
        if (exists error) {
            return error;
        }

        hash<auto> result = post(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }
}

/** @REST /v3/workflows/{id_or_name}/stepinfo/{id_or_name}/config/{name} (/v3/steps/{id_or_name}/config/{name})

    This REST URI path provides actions and information related to a particular Qorus.
    Prefix can be passed within the config item name or as following: /v3/workflows/{id_or_name}/stepinfo/{id_or_name}/config/{name}?prefix={prefix}.
    @ref step_config_items "step configuration item" in the context of a particular workflow
*/
class WorkflowStepConfigItemRestClassV3 inherits StepConfigItemRestClassV3 {
    private {
        hash<auto> wf;
    }

    constructor(hash<auto> wf, hash<auto> sh, hash<auto> item) : StepConfigItemRestClassV3(sh, item) {
        self.wf = wf;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (item.hasKey(arg)) {
                return new AttributeRestClass(item{arg});
            }
        }
    }

    /** @REST GET
        @par Description
        Returns a hash for the current @ref step_config_items "step configuration item"

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": the default value of the configuration item
        - \c "value": the value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "level": the level from where the value is obtained (interface level (e.g. "step:1", "workflow:2")
              or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, item);
    }

    /** @REST GET action=yaml
        @par Description
        Returns a hash for the current @ref step_config_items "step configuration item" as a serialized YAML string

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": (serialized YAML string) the default value of the configuration item
        - \c "value": (serialized YAML string) the current value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": (serialized YAML string) the list of allowed values for the configuration item if defined
        - \c "level": the level from where the value is obtained (interface level (e.g. "step:1", "workflow:2")
              or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        auto new_item = QorusRestClass::serializeValuesToYaml(item, ("default_value", "value"));
        if (exists new_item.allowed_values) {
            new_item.allowed_values = serializeValuesInListToYaml(new_item.allowed_values);
        }
        return RestHandler::makeResponse(200, new_item);
    }
}

/** @REST /v3/workflows/{id_or_name}/stepinfo/{id_or_name}/config

    This REST URI path provides actions and information related to Qorus
    @ref step_config_items "step configuration items" in the context of a particular workflow
*/
class Workflowstep_config_itemsRestClassV3 inherits step_config_itemsRestClassV3 {
    private {
        hash<auto> wf;
    }

    constructor(hash<auto> wf, hash<auto> sh) : step_config_itemsRestClassV3(sh) {
        self.wf = wf;
    }

    string name() {
        return "config";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        string name_with_prefix = ah.prefix + arg;
        if (*hash<auto> item = sh.config{name_with_prefix}) {
            # get actual item name
            if (item.prefix && name_with_prefix.equalPartial(item.prefix)) {
                arg = name_with_prefix[item.prefix.length()..];
            }
            return new WorkflowStepConfigItemRestClassV3(wf, sh, {"name": arg} + sh.config{name_with_prefix});
        }
    }

    /** @REST GET
        @par Description
        Returns a list of @ref step_config_items "step configuration items" for the step in the context of the declaring
        workflow

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": the default value of the configuration item
        - \c "value": the value of the configuration item
        - \c "level": the level from where the value is obtained (interface level (e.g. "step:1", "workflow:1")
             or "global" or "default")
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                                                   sh.config.pairIterator()));
    }

    /** @REST GET action=yaml
        @par Description
        Returns a list of @ref step_config_items "step configuration items" for the step as a YAML-serialized string

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": (YAML-serialized string) the default value of the configuration item
        - \c "value": (YAML-serialized string) the value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        - \c "level": the level from where the value is obtained (interface level (e.g. "step:1", "workflow:1")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> config_copy = sh.config;

        foreach auto config in (config_copy.pairIterator()) {
            config_copy{config.key} = QorusRestClass::serializeValuesToYaml(config.value, ("value", "default_value"));
            if (exists config.value.allowed_values) {
                config_copy{config.key}.allowed_values = serializeValuesInListToYaml(config.value.allowed_values);
            }
        }
        list<auto> items = map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                               config_copy.pairIterator();
        return RestHandler::makeResponse(200, items);
    }
}

/** @REST /v3/workflows/{id_or_name}/stepinfo/{id_or_name}

    This REST URI path provides information about a particular step in a workflow.
*/
class WorkflowStepRestClassV3 inherits AttributeRestClass {
    private {
        hash<auto> wf;
    }

    constructor(hash<auto> wf, hash<auto> step) : AttributeRestClass(step) {
        self.wf = wf;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "config") {
            return new Workflowstep_config_itemsRestClassV3(wf, info);
        }
        return AttributeRestClass::subClassImpl(arg, cx, ah);
    }
}

/** @REST /v3/workflows/{id_or_name}/stepinfo

    This REST URI path provides information about steps in a workflow.
*/
class WorkflowStepInfoRestClassV3 inherits AttributeRestClass {
    private {
        hash<auto> wf;
    }

    constructor(hash<auto> wf) : AttributeRestClass(wf.stepinfo) {
        self.wf = wf;
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        # try to find the element requested
        foreach hash<auto> h in (info) {
            if (h.name == name || h.stepid == name) {
                return new WorkflowStepRestClassV3(wf, h);
            }
        }
    }
}

/** @REST /v3/workflows/{id_or_name} (/v2/workflows/{id_or_name})

    This REST URI path provides actions and information about a particular workflow.
*/
class WorkflowDefinitionRestClassV3 inherits WorkflowDefinitionRestClassV2 {
    constructor(hash<auto> wf) : WorkflowDefinitionRestClassV2(wf) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "instances": return new WorkflowInstanceRestClassV3(cx, wf);
            case "orders": return new WorkflowOrderRestClassV3(wf);
            case "errors": return new WorkflowSpecificErrorsRestClassV3(wf.workflowid);
            case "logger": return new LoggerRestClass("workflows", "workflowid", wf.workflowid);
            case "config": return new WorkflowConfigItemsRestClassV3(wf);
            case "stepinfo": return new WorkflowStepInfoRestClassV3(wf);
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(name))
                return new AttributeRestClass(wf{name});
        }
    }

    /** @REST PUT action=start

        @par Description
        Manually starts one or more workflow execution instances for the current workflow.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c count: (optional) the number of execution instances to start; defaults to 1
        - \c mode: (optional) the workflow execution instance mode; defaults to @ref OMQ::WM_Normal (also may be @ref OMQ::WM_Recovery)

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c name: the workflow name
        - \c version: the workflow version
        - \c ids: the execution IDs started
        - \c exec: a list of @ref rest_execution_instance_hash_v3 "execution instance hashes" running for this workflow

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SHUTDOWN-IN-PROGRESS: cannot start new workflows because the system is shutting down

        @deprecated Workflow execution instances should not be manually started; they should be started by the system based on their autostart values and enabled and disabled for operational reasons; use @ref rest_api_PUT_workflows__id_or_name__enable and @ref rest_api_PUT_workflows__id_or_name__disable instead of manually starting and stopping workflow execution instances
    */
    hash<auto> putStart(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);
        softint count = 1;
        string mode = 'NORMAL';

        if (ah.count)
            count = ah.count;

        if (ah.mode)
            mode = ah.mode;

        softlist ids = api."omq.system.start-workflows"(("name": wf.name, "version": wf.version, "options": ah.options, "instances": count, "mode": mode)).ids;
        return RestHandler::makeResponse(200, wf + ("name": wf.name, "version": wf.version, "ids": ids, "exec": WorkflowInstanceRestClass::staticGetExecList(cx, wf.workflowid, wf.name, wf.version, 3)));
    }

    /** @REST PUT action=setRemote

        @SCHEMA
        @summary Sets the 'remote' attribute for the current workflow

        @desc Sets the 'remote' attribute for the current workflow, determining if it will run in a \
        separate remote @ref qwf "qwf" process or locally in @ref qorus-core "qorus-core".  Workflows updated with \
        this API are disabled before the change and reenabled after the change.

        @params
        - remote (bool): the new remote value for the workflow

        @return (hash WorkflowSetRemoteResultInfo): information about the result of the operation
        - updated (bool): a flag indicating if a change was actually made or not
        - remote (bool): the new remote value
        - info (string): a string providing information about the workflow update action

        @error (409): exception processing the request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETREMOTE-ERROR: missing \c remote argument; cannot update the
          remote value on a workflow with the deprecated flag set
     */
    hash<auto> putSetRemote(hash<auto> cx, *hash<auto> ah) {
        string info = sprintf("workflow %s v%s (%d)", wf.name, wf.version, wf.workflowid);

        if (!exists ah.remote) {
            throw "WORKFLOW-SETREMOTE-ERROR", sprintf("missing \"remote\" argument to update workflow %s", info);
        }

        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        if (wf."deprecated") {
            throw "WORKFLOW-SETREMOTE-ERROR", sprintf("cannot update the remote status of workflow %s with the deprecated (hidden) flag set", info);
        }

        ah.remote = parse_boolean(ah.remote);

        bool updated;
        try {
            updated = Qorus.qmm.updateWorkflowRemote(wf.workflowid, ah.remote);
            if (updated) {
                info += sprintf(" was updated with remote = %y", ah.remote);
            } else {
                info += sprintf(" was not updated because remote already was %y", ah.remote);
            }
        } catch (hash<ExceptionInfo> ex) {
            info += Qorus.getDebugSystem()
                ? sprintf(", update remote failed: %s", get_exception_string(ex))
                : sprintf(", update remote failed: %s: %s", ex.err, ex.desc);
            updated = False;
        }

        hash<auto> rv = {
            "updated": updated,
            "remote": ah.remote,
            "info": info,
        };

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=setSla

        @SCHEMA
        @summary Sets the SLA attribute for the current workflow

        @desc Sets the SLA attribute for the current workflow which specifies the maximum targeted time a \
        workflow order should get a final status (being one of @ref OMQ::StatComplete "COMPLETE" or \
        @ref OMQ::StatCanceled "CANCELED")

        @params
        - sla (int): a value giving the new SLA timeout value as an integer in seconds for the workflow

        @return (hash WorkflowSetSlaResultInfo): information about the result of the operation
        - updated (bool): a flag indicating if a change was actually made or not
        - sla (int): the new SLA value as a positive integer in seconds
        - info (string): a string providing information about the workflow update action

        @error (409): exception processing the request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETSLA-ERROR: missing or invalid \c sla argument; cannot update
          the remote value on a workflow with the deprecated flag set
     */
    hash<auto> putSetSla(hash<auto> cx, *hash<auto> ah) {
        string info = sprintf("%s v%s (%d)", wf.name, wf.version, wf.workflowid);

        if (!exists ah.sla) {
            throw "WORKFLOW-SETSLA-ERROR", sprintf("missing \"sla\" argument to update workflow %s", info);
        }
        if (!ah.sla.intp()) {
            throw "WORKFLOW-SETSLA-ERROR", sprintf("\"sla\" argument for workflow %s has type %y which cannot be converted to an integer", info, ah.sla.type());
        }
        softint sla = ah.sla;
        if (sla <= 0) {
            throw "WORKFLOW-SETSLA-ERROR", sprintf("\"sla\" argument for workflow %s has invalid value %y; the SLA value must be a positive integer giving the number of seconds in which a workflow order should get a final status", info, sla);
        }

        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        if (wf."deprecated")
            throw "WORKFLOW-SETSLA-ERROR", sprintf("cannot update the SLA status of workflow %s with the deprecated (hidden) flag set", info);

        bool updated;
        try {
            updated = Qorus.qmm.updateWorkflowSla(wf.workflowid, sla);
            if (updated) {
                info += sprintf(" was updated with SLA = %y", sla);
            } else {
                info += sprintf(" was not updated because SLA already was %y", sla);
            }
        } catch (hash<ExceptionInfo> ex) {
            info += sprintf(", update SLA failed: %s", get_exception_string(ex));
            updated = False;
        }

        hash<auto> rv = {
            "updated": updated,
            "sla": sla,
            "info": info,
        };

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST GET

        @SCHEMA
        @summary Returns information about the current workflow

        @desc Returns information about the current workflow

        @return (hash WorkflowDefinitionInfoV3): information about the current workflow
        - workflowid (int): the workflow ID
        - name (string): the workflow name
        - version (string): the workflow version
        - description (*string): the workflow description
        - author (*string): the workflow author
        - remote (bool): if @ref True "True", the workflow will run as a remote @ref qwf "qwf" process, otherwise it \
          runs internally in the @ref qorus-core "qorus-core" process
        - manual_remote (bool): set if the \a manual value has been changed manually, in which \
          case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - process: present when remote is @ref True "True"; this is a @ref rest_process_exec_info_hash
        - onetimeinit_func_instanceid (*int): the @ref dep_onetimeinit "onetimeinit function" ID for the workflow \
          (if defined)
        - attach_func_instanceid (*int): the @ref dep_attach "attach function" ID for the workflow (if defined)
        - detach_func_instanceid (*int): the @ref dep_detach "detach function" ID for the workflow (if defined)
        - errorfunction_instanceid (*int): the @ref dep_errorfunction "error function" ID for the workflow (if \
          defined)
        - errhandler_func_instanceid (*int): the @ref dep_error_handler "error handler function" ID for the workflow \
          (if defined)
        - has_detach (bool): @ref True "True" if the workflow has @ref detach "detach logic"
        - created (date): the workflow creation date
        - modified (date): the workflow last modified date
        - autostart (int): the @ref wf_autostart "workflow autostart" value
        - manual_autostart (bool): set if the \a autostart value has been changed manually, in which \
          case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - sla_threshold (int): the @ref wf_sla_threshold "workflow SLA threshold" value
        - manual_sla_threshold (bool): a boolean flag set if the sla_threshold value has been changed manually, in \
          which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
        - enabled (bool): a boolean flag indicating if the workflow is enabled or not; disabled workflows cannot be \
          started
        - deprecated (bool): a boolean flag indicating if the workflow is deprecated or not; deprecated workflows \
          are not displayed by default in the UI
        - language (*string): the programming language for the workflow's class (if any)
        - code (*string): the source code for the workflow's class (if any)
        - source (*string): the source for the workflow definition
        - line (*int): the line number offset in \a source for the workflow definition
        - tags (*hash[any] UndefinedHash): any tags for the workflow
        - order_key_map (*hash[bool] Set): set of order keys in hash form
        - keylist (*list<string>): a list of @ref wf_keylist "workflow order keys"
        - stepmap (hash[string] StringMap): a hash where keys are step IDs and values are step names
        - steps (hash[*list<int>] IntListMap): a hash of step dependencies, where keys are step IDs and values are lists of \
          step IDs that must preceed the step ID given as a key
        - segment (list<hash SegmentInfo>): a list of segment description hashes, where each segment hash has the \
          following keys:
          - steplist (list<int>): a list of step IDs in the segment
          - steps (hash[*list<int>] IntListMap): a hash of step dependencies, where keys are step IDs and values are lists of \
            step IDs that must preceed the step ID given as a key
          - start (*int): the starting step ID for segments other than the initial segment
          - subworkflow (*bool): set to @ref True if the segment is a subworkflow segment
          - linksegment (*int): the previous segment
          - linkstepid (*int): the step linking the segment to the previous segment
        - stepseg (*hash[int] IntMap): maps step IDs to segment numbers
        - lib (*hash LibraryInfo): information about any referenced Qorus objects
          - functions (*list<hash LibraryDetailInfo>): a list of function objects (can be empty)
            - name (string): the name of the object
            - version (string): the version of the object
            - id (int): the id of the object
          - classes (*list<hash LibraryDetailInfo>): a list of class objects (can be empty)
          - constants (*list<hash LibraryDetailInfo>): a list of constant objects (can be empty)
          - pipelines (*list<hash NameInfo>): a list of pipeline objects (can be empty)
            - name (string): the name of the object
          - fsm (*list<hash NameInfo>): a list of FSM objects (can be empty)
        - mappers (*list<hash MapperInfo>): a list of @ref mappers "mappers" associated with the workflow
          - mapperid (int): the ID of the mapper
          - name (string): the name of the mapper
          - version (string): the version of the mapper
          - type (string): the @ref mapper-types "type" of the mapper (all types other than \c "Mapper" are deprecated)
        - vmaps (*list<hash VMapInfo>): a list of @ref value-maps "value maps" associated with the workflow
          - id (int): the ID of the value map
          - name (string): the name of the value map
          - throws_exception (bool): indicates how requests for unknown values should be processed
          - valuetype (string): the data type of the value map
          - mapsize (int): the number of elements in the map
        - stepinfo (list<hash WorkflowStepInfo>): a list of hashes giving information about @ref steps "workflow steps"
          - stepid (int): the ID of the step
          - steptype (string): the @ref StepTypes "type" of the step
          - arraytype (string): the @ref StepArrayTypes "array type" of the step
          - name (string): the name of the step
          - version (string): the version of the step
          - author (*string): the author of the step (if any)
          - step_classid (*int): the class ID of the step (if any)
          - classname (*string): the name of the step's class (if any)
          - code (*string): the source code for the step's class (if any)
          - language_info (*hash UndefinedHash): language-specific info
          - desc (*string): the description of the step or the description of the step's logic implementation, if \
            the step itself has no description
          - lib (*hash LibraryInfo): information about any referenced Qorus objects
          - queueid (*int): the asynchronous queue ID for the step (if any)
          - queuename (*string): the asynchronous queue name for the step (if any)
          - config (*hash[hash ConfigItemInfo] ConfigItemSetInfo): a hash of configuration item info keyed by config \
            item name
            - name (string): the name of the configuration item
            - prefix (*string): the prefix of the configuration item
            - type (string): the data type of the configuration item
            - desc (string): the description of the configuration item
            - default_value (any): the default value of the configuration item
            - value (any): the value of the configuration item
            - strictly_local (bool): if the configuration item is defined strictly on local level
            - is_set (bool): @ref True if the value is set otherwise @ref False
            - config_group (string): the group of the configuration item
            - allowed_values (*list<any>): the list of allowed values for the configuration item if defined
            - level (string): the level from where the value is obtained (interface level - e.g. "step:1" - \
               or "global" or "default")
            - is_templated_string (bool): @ref True if the value is a templated string that can be later expanded
          - fsm_triggers (*hash[any] UndefinedHash): any FSM trigges for steps
          - stepfunction_instanceid (*int): the primary step function ID
          - validationfunction_instanceid (*int): the function ID of the \
            @ref dep_validationfunc "validation function" (if any)
          - endfunction_instanceid (*int): the function ID of the @ref dep_asyncbackendfunc "back end function" for \
            @ref asyncsteps "asynchronous steps" (if any)
          - arrayfunction_instanceid (*int): the function ID of the @ref dep_arrayfunc "array function" (if any)
          - queueid (*int): the ID of the @ref queue_objects "async event queue" for \
            @ref asyncsteps "asynchronous steps" (if any)
          - queuename (*string): the name of the @ref queue_objects "async event queue" for \
            @ref asyncsteps "asynchronous steps" (if any)
          - workflow_event_typeid (*int): the ID of the \
            @ref wf_sync_event_objects "workflow synchronization event type" for \
            @ref eventsteps "workflow synchronization event steps" (if any)
          - language (*string): the programming language for the step's class (if any)
          - user_interaction (bool): \c True if the @ref asyncsteps "asynchronous step" supports user interaction \
            APIs, \c False in all other cases
          - userdata (*hash[any] UndefinedHash): any user metadata for the step
          - sfname (*string): the name of the primary step function
          - vfname (*string): the name of the @ref dep_validationfunc "validation function" (if any)
          - afname (*string): the name of the @ref dep_arrayfunc "array function" (if any)
          - efname (*string): the name of the @ref dep_asyncbackendfunc "back end function" (if any)
          - created (date): the creation date of the step in the database
          - modified (date): the last modified date of the step in the database
        - wffuncs (list<hash WorkflowFuncInfo>): a list of workflow-level functions (may be empty)
          - type (string): the type of workflow function; one of \c "onetimeinit" \
            (@ref dep_onetimeinit "workflow execution instance initialization function"), \c "errorfunction" \
            (@ref dep_errorfunction "workflow error function"), \c "attachfunction" \
            (@ref dep_attach "workflow attach function"), \c "detachfunction" \
            (@ref dep_detach "workflow detach function"), \c "errorhandlerfunction" \
            (@ref dep_error_handler "workflow error handler function")
          - name (string): the name of the function
          - version (string): the version of the function
          - function_instanceid (int): the function ID
          - function_type (string): the @ref StepFunctionTypes "type" of the function
          - description (*string): a decsription for the function
          - author (*string): the author of the function
          - created (date): the creation date in the database
          - modified (date): the last modified date in the database
          - source (*string): the name of the source file for the function (complete path)
          - line (*int): the line number offset for the function object definition in the file
        - options (list<hash OptionInfoHash>): a list option information hashes
          - name (string): the name of the option
          - desc (*string): a description for the option
          - value (any): the value of the option
        - config (*hash[hash ConfigItemSummaryInfo] ConfigItemSummarySetInfo): a hash of configuration item info \
          keyed by config item name
          - name (string): the name of the configuration item
          - prefix (*string): the prefix of the configuration item
          - type (string): the data type of the configuration item
          - desc (string): the description of the configuration item
          - default_value (any): the default value of the configuration item
          - value (any): the value of the configuration item
          - strictly_local (bool): if the configuration item is defined strictly on local level
          - is_set (bool): @ref True if the value is set otherwise @ref False
          - config_group (string): the group of the configuration item
          - allowed_values (*list<any>): the list of allowed values for the configuration item if defined
          - level (string): the level from where the value is obtained (interface level (e.g. "job:1", "job:2")
             or "global" or "default")
          - is_templated_string (bool): @ref True if the value is a templated string that can be later expanded
        - global_config (*hash[hash ConfigItemSummaryInfo] ConfigItemSummarySetInfo): a hash of configuration item \
          info keyed by config item name
        - exec (*list<hash ExecInstanceInfoV3>): a list of hashes describing any workflow execution instances running \
          for this workflow
          - mode (string): the workflow execution instance execution mode
          - totalSegments (int): number of segments in the workflow
          - starttime (date): the date/time the execution instance was started
          - logfile (*string): the log file name (full path)
          - sync (bool): a boolean flag if the execution instance is synchronous or not
          - sync_wfiid (*int): the workflow_instanceid currently being processed (if any)
          - executionID (int): the workflow execution instance ID
          - remote (bool): if @ref True "True", the workflow execution instance is running in a remote \
            @ref qwf "qwf" process, otherwise it is running internally in the @ref qorus-core "qorus-core" process
          - process (*hash ProcessExecInfo): present when \c remote is @ref True "True"
            - id (string): the unique process ID in the cluster
            - node (string): the node name where the process is running
            - host (string): the hostname where the process is running
            - pid (int): the PID on the host
            - urls (list<string>): a list of ZeroMQ URLs for the process
            - status (int): the process's status code
            - status_string (string): the process's status as a string
            - priv (int): the amount of private memory of the process in bytes
            - rss (int): the resident size of the process in bytes
            - vsz (int): the virtual size of the process in bytes
            - priv_str (string): a string description of the \c priv value
            - pct (int): the percentage of main memory taken up by the process on the node
          - alerts (list<hash[any] UndefinedHash>): a list of alerts
          - log_url (*string): the log URL (if any)
        - COMPLETE (*int): number of workflow orders with status @ref OMQ::StatComplete "COMPLETE"
        - INCOMPLETE (*int): number of workflow orders with status @ref OMQ::StatIncomplete "INCOMPLETE"
        - WAITING (*int): number of workflow orders with status @ref OMQ::StatWaiting "WAITING"
        - EVENT-WAITING (*int): number of workflow orders with status @ref OMQ::StatEventWaiting "EVENT-WAITING"
        - ASYNC-WAITING (*int): number of workflow orders with status @ref OMQ::StatAsyncWaiting "ASYNC-WAITING"
        - RETRY (*int): number of workflow orders with status @ref OMQ::StatRetry "RETRY"
        - ERROR (*int): number of workflow orders with status @ref OMQ::StatError "ERROR"
        - CANCELED (*int): number of workflow orders with status @ref OMQ::StatCanceled "CANCELED"
        - BLOCKED (*int): number of workflow orders with status @ref OMQ::StatBlocked "BLOCKED"
        - IN-PROGRESS (*int): number of workflow orders with status @ref OMQ::StatInProgress "IN-PROGRESS"
        - SCHEDULED (*int): number of workflow orders with status @ref OMQ::StatScheduled "SCHEDULED"
        - READY (*int): number of workflow orders with status @ref OMQ::StatReady "READY"
        - TOTAL (*int): number of workflow orders in all statuses
        - process (*hash ProcessExecInfo): present when \c remote is @ref True "True"
        - exec_count (int): the number of elements in the exec list
        - order_stats (*list<hash[any] UndefinedHash>): a list of workflow order processing statistics; list values \
          are @ref OMQ::OrderSummaryOutputInfo "OrderSummaryOutputInfo" hashes for the given workflow
        - alerts (*list<hash AlertInfo>): a list of alerts raised against the workflow
          - type (string): the type of object directly causing the alert
          - id (any): the ID of the object directly causing the alert
          - version (*string): the version of the object causing the alert, if any
          - alerttype (string): either \c "ONGOING" or \c "TRANSIENT"
          - when (date): the timestamp when the alert was first raised
          - local (bool): a boolean flag; @ref True if the alert was raised by the local instance
          - alert (string): the name or string code of the alert
          - alertid (int): a unique identifier for the alert (unique within the instance that raised the alert)
          - reason (string): a string giving the reason the alert was raised
          - who (string): a string describing the user or entity that raised the alert
          - source (string): a string describing the source of the alert
          - object (string): a string describing the object causing the alert
          - instance (string): the instance key of the Qorus instance where the alert was raised
          - name (string): the name of the object causing the alert
          - description (*string): the description of the object causing the alert
          - url (*string): the URL of any connection causing the alert
          - connection_type (*string): the connection type for any connection causing the alert
          - auditid (*int): @ref nothing if alert auditing is not enabled, otherwise an integer giving the auditid \
            of the alert event
        - connections (*list<hash ConnectionInfo>): a list of connection objects that this workflow depends on
          - type (string): the type of connection dependency; one of c "DATASOURCE" (@ref dsconn), \c "QORUS" \
            (@ref remoteconn), or \c "USER" (@ref userconn)
          - name (string): the name of the connection
          - up (bool): describes the currently-monitored health of the connection
        - groups (*list<hash GroupInfo>): a list of @ref rbacgroups "interface groups" that the workflow belongs to
          - name (string): the name of the group
          - enabled (bool): the status of the group as a bool
          - size (int): the total number of members of the group
        @ENDSCHEMA
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        {
            SqlUtil::AbstractTable workflows = get_sql_table_system_trans("omq", "workflows");
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();

                    wf{"code"} = workflows.selectRow({"columns": "code", "where": {"workflowid": wf{"workflowid"}}}){"code"};
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
        return RestHandler::makeResponse(200, wf);
    }

    /** @REST POST action=kill

        @SCHEMA
        @summary Kills a remote @ref qwf "workflow cluster process"

        @desc Kills a remote @ref qwf "workflow cluster process"

        @return (hash KillResultInfo): information about the result of the operation
        - status (string): either \c "OK" or \c "ERR"
        - code (int): the return code of the \c kill() command: 0 if successful, non-zero if not

        @error (404): if no remote process is running for the workflow
        @ENDSCHEMA
    */
    hash<auto> postKill(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # get current workflow info to avoid race conditions
        *hash<auto> info = wf.process.id ? Qorus.qmm.lookupProcess(wf.process.id) : NOTHING;
        if (!info) {
            return {
                "code": 404,
                "body": sprintf("no process is currently running for workflow %s v%s (%d)", wf.name, wf.version,
                    wf.workflowid),
            };
        }
        return ProcessRestClassV3::staticKillProcess(info, cx, ah);
    }

    /** @REST POST action=lockUserInteractionStep

        @SCHEMA
        @summary Locks the next available queue entry in a user interaction step

        @desc Locks the next available queue entry eligible for @ref step_user_interaction "user interaction" for \
        the named step and returns the step information or a \c 404 \c Not \c Found error if no such data is available

        @params
        - stepid (*int): the ID of the step to acquire user interaction data from; either this or \a stepname is \
          required
        - stepname (*string): the name of the step to acquire user interaction data from; either this or \
          \a stepid is required

        @return (hash WorkflowLockUseInteractionStepResultInfo): information about the result of the operation

        @error (400): missing or invalid arguments
        @error (404): no data available on the queue to lock
        @ENDSCHEMA

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if there is an error with the arguments to the call
        - <tt><b>404 Not Found</b></tt>: this response is returned if no data is available to lock on the queue
    */
    hash<auto> postLockUserInteractionStep(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        string key;
        softstring value;
        if (ah.hasKey("stepid")) {
            if (!ah.stepid.intp()) {
                return RestHandler::makeResponse(400, sprintf("the \"stepid\" argument must be an integer stepid; "
                    "value given: %y", ah.stepid));
            }
            key = "stepid";
            value = ah.stepid;
        } else if (ah.hasKey("stepname")) {
            if (!ah.stepname.strp()) {
                return RestHandler::makeResponse(400, sprintf("the \"stepname\" argument must be a string name; value "
                    "given: %y", ah.stepname));
            }
            key = "name";
            value = ah.stepname;
        } else {
            # make a list of steps with user interaction
            *list<auto> sl = map $1{"stepid", "name"}, wf.stepinfo, $1.user_interaction;
            return RestHandler::makeResponse(400, sprintf("missing either the \"stepid\" or \"stepname\" argument; "
                "args passed: %y; steps supporting user interaction in this workflow: %y", ah, sl));
        }

        # make a map of steps with user interaction
        *hash<auto> sh = map {$1{key}: $1}, wf.stepinfo, $1.user_interaction;

        *hash<auto> stepinfo = sh{value};
        if (!stepinfo) {
            return RestHandler::makeResponse(400, sprintf("no step supporting user interactions in workflow %s v%s "
                "(%d) found with %s = %y; steps supporting user interaction in this workflow: %y", wf.name, wf.version,
                wf.workflowid, key, value, (map $1{"stepid", "name"}, sh.iterator())));
        }

        *hash<auto> rv = sqlif.returnLockUserInteractionStep(stepinfo.queueid, "%SYS%");
        if (!rv) {
            return RestHandler::makeResponse(404, sprintf("no data available for step %s v%s (%d) on queueid %d %y",
                stepinfo.name, stepinfo.version, stepinfo.stepid, stepinfo.queueid, stepinfo.queuename));
        }

        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v3/remote/qorus/{name} (/v2/remote/qorus/{name})

    This REST URI path provides actions and information related to a specific @ref remoteconn "remote connection"
*/
class QorusRemoteConnectionRestClassV3 inherits QorusRemoteConnectionRestClass {
    constructor(hash<auto> rh) : QorusRemoteConnectionRestClass(rh) {
    }

    /** @REST PUT action=enable

        @par Description
        Enables current @ref remoteconn "remote connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */
    hash<auto> putEnable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.remotemonitor.enable(rh.name);
        hash<auto> rv = {
            "info": sprintf("enabled Qorus remote connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=disable

        @par Description
        Disables current @ref remoteconn "remote connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */
    hash<auto> putDisable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.remotemonitor.disable(rh.name);
        hash<auto> rv = {
            "info": sprintf("disabled Qorus remote connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT

        @par Description
        Modifies the current @ref remoteconn "remote Qorus connection"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c desc: (optional string) a new description for the connection
        - \c url: (optional string) a new URL for the connection
        - \c options: (optional hash) new options for the connection; also accepts \c "opts" as an alias for this
          option

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string describing the connection update

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c REMOTE-CONNECTION-ERROR: invalid or unparsable \c "options" key
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        if (!ah.desc || ah.desc.typeCode() != NT_STRING)
            ah.desc = rh.desc ?? rh.description;
        if (!ah.url || ah.url.typeCode() != NT_STRING)
            ah.url = rh.url;

        # issue #2972: also accept "opts"
        if (!ah.options && ah.hasKey("opts")) {
            ah.options = remove ah.opts;
        }

        # issue #3469: remove all options if an empty "options" key was provided
        if (ah.hasKey("options")) {
            parseOptAsHash("options", \ah);
        } else {
            ah.options = rh.opts;
        }

        # issue #3226: allow tags to be updated and deleted
        if (ah.hasKey("tags")) {
            parseOptAsHash("tags", \ah);
        } else {
            ah.tags = rh.tags;
        }

        hash<auto> attr;
        if (ah.tags) {
            attr.tags = ah.tags;
        }
        Qorus.remotemonitor.replace(rh.name, ah.desc, ah.url, attr, ah.options);

        hash<auto> rv = {
            "info": sprintf("updated remote connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST DELETE

        @par Description
        Permanently deletes the current @ref remoteconn "remote connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.remotemonitor.del(rh.name);
        hash<auto> rv = {
            "info": sprintf("deleted remote connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=ping

        @par Description
        Checks connectivity to the current @ref remoteconn "remote connection"; if the connection
        was up and is monitored to be down, then any dependent interfaces will be disabled.
        If the connection was down and is monitored to be up, then any eligible interfaces
        will be reenabled.

        @par Return Value
        This API returns a hash with the following keys:
        - \c ok: the status of the ping
        - \c name: the name of the connection
        - \c desc: the description of the connection
        - \c url: the URL for the connection
        - \c opts: a hash of options for the connection (if any)
        - \c time: the elapsed time for the ping
        - \c info: \c "OK" if the ping was successful or an error message if not
        - \c result: a string representation of the time in seconds (ex: \c "0.25s")
    */
    hash<HttpHandlerResponseInfo> putPing(hash<auto> cx, *hash<auto> ah) {
        hash<HttpHandlerResponseInfo> rv = QorusRemoteConnectionRestClass::putPing(cx, ah);
        if (rv.body.time) {
            rv.body.result = sprintf("%gs", rv.body.time.durationSecondsFloat());
        }
        return rv;
    }
}

/** @REST /v3/remote/qorus (/v2/remote/qorus)

    This REST URI path provides actions and information related to Qorus @ref remoteconn "remote connections"
*/
class QorusRemoteConnectionsRestClassV3 inherits QorusRemoteConnectionsRestClass {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        try {
            bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
            return new QorusRemoteConnectionRestClassV3({"name": name} +
                Qorus.remotemonitor.getInfo(name, {"with_passwords": with_passwords}));
        } catch (hash<ExceptionInfo> ex) {
        }
    }

    /** @REST POST

        @par Description
        Creates a new remote connection from the arguments supplied

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c name: (required string) the name of the connection
        - \c desc: (required string) the description for the new connection
        - \c url: (required string) the URL for the new connection
        - \c options: (optional hash) a hash of options for the connection; also accepts \c "opts" as an alias
          for this option

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the connection creation

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c REMOTE-CONNECTION-ERROR: missing or invalid \c name, \c desc, \c url, or \c options arguments
        - <tt><b>409 Conflict</b></tt>: \c CONNECTION-ERROR: connection already exists; unknown scheme in URL
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        hash<auto> rv = {
            "id": createConnection(cx, ah),
            "info": sprintf("created new remote connection %y (%s) with URL %y", ah.name, ah.desc, ah.url),
        };
        return RestHandler::makeResponse(200, rv);
    }

    static int createConnection(hash<auto> cx, *hash<auto> ah, *softint id) {
        if (!ah.name || ah.name.typeCode() != NT_STRING)
            throw "REMOTE-CONNECTION-ARG-ERROR", sprintf("missing 'name' argument giving the name for the new connection "
                "(args: %y)", ah);
        if (!ah.desc || ah.desc.typeCode() != NT_STRING)
            throw "REMOTE-CONNECTION-ARG-ERROR", sprintf("missing 'desc' argument giving the description for the new "
                "connection (args: %y)", ah);
        if (!ah.url || ah.url.typeCode() != NT_STRING)
            throw "REMOTE-CONNECTION-ARG-ERROR", sprintf("missing 'url' argument giving the URL for the new connection "
                "(args: %y)", ah);

        rlog(cx);

        # issue #2972: also accept "opts"
        if (!ah.options && ah.hasKey("opts")) {
            ah.options = remove ah.opts;
        }

        QorusRestClass::parseOptAsHash("options", \ah);
        QorusRestClass::parseOptAsHash("tags", \ah);

        hash<auto> attr;
        if (ah.tags) {
            attr.tags = ah.tags;
        }

        return Qorus.remotemonitor.registerConnection(ah.name, ah.desc, ah.url, attr, ah.options ?? {},
            id).internal_info.id;
    }
}

/** @REST /v3/remote/user/{name} (/v2/remote/user/{name})

    This REST URI path provides actions and information related to a specific @ref userconn "user connection"
*/
class UserConnectionRestClassV3 inherits UserConnectionRestClass {
    constructor(hash<auto> rh) : UserConnectionRestClass(rh) {
    }

    /** @REST PUT action=enable

        @par Description
        Enables current @ref userconn "user connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */
    hash<HttpHandlerResponseInfo> putEnable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.connections.enable(rh.name);
        hash<auto> rv = {
            "info": sprintf("enabled user connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=disable

        @par Description
        Disables current @ref userconn "user connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */
    hash<HttpHandlerResponseInfo> putDisable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.connections.disable(rh.name);
        hash<auto> rv = {
            "info": sprintf("disabled user connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=ping

        @par Description
        Checks connectivity to the current @ref userconn "user connection"; if the connection
        was up and is monitored to be down, then any dependent interfaces will be disabled.
        If the connection was down and is monitored to be up, then any eligible interfaces
        will be reenabled.

        @par Return Value
        This API returns a hash with the following keys:
        - \c ok: the status of the ping
        - \c name: the name of the connection
        - \c desc: the description of the connection
        - \c url: the URL for the connection
        - \c opts: a hash of options for the connection (if any)
        - \c time: the elapsed time for the ping
        - \c info: \c "OK" if the ping was successful or an error message if not
        - \c result: a string representation of the time in seconds (ex: \c "0.25s")
    */
    hash<HttpHandlerResponseInfo> putPing(hash<auto> cx, *hash<auto> ah) {
        hash<HttpHandlerResponseInfo> rv = UserConnectionRestClass::putPing(cx, ah);
        if (rv.body.time) {
            rv.body.result = sprintf("%gs", rv.body.time.durationSecondsFloat());
        }
        return rv;
    }
}

/** @REST /v3/remote/user (/v2/remote/user)

    This REST URI path provides actions and information related to Qorus @ref userconn "user connections"
*/
class UserConnectionsRestClassV3 inherits UserConnectionsRestClass {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
        *hash<auto> rh = Qorus.connections.getInfo(name, {"with_passwords": with_passwords});
        if (rh) {
            return new UserConnectionRestClassV3(rh);
        }
    }
}

/** @REST /v3/remote/datasources/{name} (/v2/remote/datasources/{name})

    This REST URI path provides actions and information related to a specific Qorus system @ref dsconn "datasource"
*/
class DatasourceRestClassV3 inherits DatasourceRestClass {
    constructor(hash<auto> rh) : DatasourceRestClass(rh) {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "logger") {
            try {
                # make sure there is no datasource named "logger"
                Qorus.dsmanager.getConfigHash("logger");
            } catch (hash<ExceptionInfo> ex) {
                return new LoggerRestClass("qdsp", "name", rh.name);
            }
        }

        return DatasourceRestClass::subClassImpl(arg, cx, ah);
    }

    /** @REST PUT

        @par Description
        Updates the current @ref dsconn "datasource" in the server's internal cache

        @par Arguments
        This API takes a hash argument (either as URI arguments or in the message body):
        - \c desc: (required string) the description for the new connection
        - \c url: (required string) the connection string for the new connection. See @ref Qore::SQL::parse_datasource()
        - \c options: (optional hash) a hash of options for the connection; also accepts \c "opts" as an alias for this
          option

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the update operation

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c DATASOURCE-ERROR: this exception is thrown if the call tries to modify a locked system datasource or invalid options are passed

        @note
        - in order for any datasource changes to be put into effect, a separate call to
          @ref rest_api_PUT_v3_remote_datasources__name__reset must be made
        - both \c "min" and \c "max" datasource options must be present to be used; if only one is present, it is ignored

        @see
        - @ref rest_api_PUT_v3_remote_datasources__name__reset
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        if (!ah.desc || ah.desc.typeCode() != NT_STRING)
            ah.desc = rh.desc ?? rh.description;
        if (!ah.url || ah.url.typeCode() != NT_STRING)
            ah.url = rh.url;

        # issue #2972: also accept "opts"
        if (!ah.options && ah.hasKey("opts")) {
            ah.options = remove ah.opts;
        }

        # issue #3469: remove all options if an empty "options" key was provided
        if (ah.hasKey("options")) {
            parseOptAsHash("options", \ah);
        } else {
            ah.options = rh.opts;
        }

        # issue #3226: allow tags to be updated and deleted
        if (ah.hasKey("tags")) {
            parseOptAsHash("tags", \ah);
        } else {
            ah.tags = rh.tags;
        }

        if (ah.url !~ /^db:\/\//) {
            ah.url = "db://" + ah.url;
        }

        hash<auto> attr;
        if (ah.tags) {
            attr.tags = ah.tags;
        }
        Qorus.dsmanager.replace(rh.name, ah.desc, ah.url, attr, ah.options ?? {});

        hash<auto> rv.info = sprintf("updated datasource connection %y", name());
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST DELETE

        @par Description
        Deletes the given @ref dsconn "datasource" from the server's internal cache

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c DATASOURCE-ERROR: this exception is thrown if the given datasource does not exist or is a system datasource
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        Qorus.dsmanager.del(rh.name);
        hash<auto> rv = {
            "info": sprintf("deleted datasource connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=enable

        @par Description
        Enables current @ref dsconn "datasource"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the enable operation
    */
    hash<HttpHandlerResponseInfo> putEnable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.dsmanager.enable(rh.name);
        hash<auto> rv = {
            "info": sprintf("enabled datasource connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=disable

        @par Description
        Disables current @ref dsconn "datasource"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the disable operation
    */
    hash<HttpHandlerResponseInfo> putDisable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.dsmanager.disable(rh.name);
        hash<auto> rv = {
            "info": sprintf("disabled datasource connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=ping

        @par Description
        Checks connectivity to the current @ref dsconn "datasource"; if the datasource connection
        was up and is monitored to be down, then any dependent interfaces will be disabled.
        If the connection was down and is monitored to be up, then any eligible interfaces
        will be reenabled.

        @par Return Value
        This API returns a hash with the following keys:
        - \c ok: the status of the ping
        - \c name: the name of the connection
        - \c desc: the description of the connection
        - \c url: the URL for the connection
        - \c opts: a hash of options for the connection (if any)
        - \c time: the elapsed time for the ping
        - \c info: \c "OK" if the ping was successful or an error message if not
        - \c result: a string representation of the time in seconds (ex: \c "0.25s")
    */
    hash<HttpHandlerResponseInfo> putPing(hash<auto> cx, *hash<auto> ah) {
        hash<HttpHandlerResponseInfo> rv = DatasourceRestClass::putPing(cx, ah);
        if (rv.body.time) {
            rv.body.result = sprintf("%gs", rv.body.time.durationSecondsFloat());
        }
        return rv;
    }
}

/** @REST /v3/remote/datasources (/v2/remote/datasources)

    This REST URI path provides actions and information related to Qorus system @ref dsconn "datasources"
*/
class DatasourcesRestClassV3 inherits DatasourcesRestClass, HelpLoggerRestClass, HelpLoggerAppendersRestClass {
    constructor() : HelpLoggerRestClass("qdsp"), HelpLoggerAppendersRestClass("qdsp", "qdsp") {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        try {
            bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
            return new DatasourceRestClassV3(Qorus.dsmanager.getInfo(name, {
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

    /** @REST POST

        @par Description
        Creates a new datasource connection in memory

        @par Arguments
        This API takes a hash argument (either as URI arguments or in the message body):
        - \c name: (required string) the name of the datasource connection
        - \c desc: (required string) the description for the new connection
        - \c url: (required string) the connection string for the new connection. See @ref Qore::SQL::parse_datasource()
        - \c options: (optional hash) a hash of options for the connection; also accepts \c "opts" as an alias
          for this option

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c DATASOURCE-CONNECTION-ERROR: missing or invalid name, desc, url, options arguments - or name and @ref datasource_hash members
        - <tt><b>409 Conflict</b></tt>: \c CONNECTION-ERROR: connection already exists; unknown scheme in URL
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        hash<auto> rv = {
            "id": createConnection(cx, ah),
            "info": sprintf("created new datasource connection %y", ah.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST GET action=defaultLogger

        @par Description
        Returns default logger info

        @par Return Value
        This API returns 200 OK and hash with the following keys:
        - \c loggerid: (int) logger id
        - \c params: (hash) logger params
            - \c level: (hash) @ref Logger::LoggerLevel "LoggerLevel"
                - \c "key": logger level string representation
                - \c "value": logger level int representation
            - \c name: (string) logger name
            - \c additivity: (bool) logger additivity
        - \c interface_table_name: (string) interface table name (jobs/workflows/services/qdsp). If set means default logger
     */
    hash<HttpHandlerResponseInfo> getDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::getImpl(cx, ah);
    }

    /** @REST POST action=defaultLogger

        @par Description
        Create default Logger

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: required; (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: (string) logger name
        - \c additivity: (bool) logger additivity (default @ref True)
        - \c cloneDefault: (bool) create logger with appenders based on default logger

        @par Return Value
        If success 200 with the logger ID created, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<HttpHandlerResponseInfo> postDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::postImpl(cx, ah);
    }

    /** @REST PUT action=defaultLogger

        @par Description
        Set logger params

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: logger name to set
        - \c additivity: logger additivity to set

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<HttpHandlerResponseInfo> putDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::putImpl(cx, ah);
    }

    /** @REST DELETE action=defaultLogger

        @par Description
        Delete logger

        @par Return Value
        If success 200 OK, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<HttpHandlerResponseInfo> delDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::delImpl(cx, ah);
    }

    /** @REST GET action=defaultLoggerAppenders

        @par Description
        Return all logger appenders

        @par Return Value
        This API returns 200 OK and list with the following hashes:
        - \c appenderId: (int) appenderId
        - \c params: (hash) possible appender parameters, might be missing if not set
            - \c name: (string) appender name
            - \c layoutPattern: (string) appender layout pattern
            - \c rotation: (int) appender layout pattern
            - \c filename: (string) appender filename
    */
    hash<HttpHandlerResponseInfo> getDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::getImpl();
    }

    /** @REST DELETE action=defaultLoggerAppenders
        @par Description
        Delete logger appender with obtained id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be deleted

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<HttpHandlerResponseInfo> delDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::delImpl(cx, ah);
    }

    /** @REST POST action=defaultLoggerAppenders

        @par Description
        Create logger appenders

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK and appender id, in case of fail one of the error codes: 400, 409 and \a string of error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<HttpHandlerResponseInfo> postDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::postImpl(cx, ah);
    }

    /** @REST PUT action=defaultLoggerAppenders
        @par Description
        Update logger appender with the given id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be update
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<HttpHandlerResponseInfo> putDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::putImpl(cx, ah);
    }

    #! Creates a new datasource connection
    static int createConnection(hash<auto> cx, *hash<auto> ah, *softint id) {
        if (!ah.hasKey("name") || ah."name".typeCode() != NT_STRING) {
            throw "DATASOURCE-CONNECTION-ERROR", "Argument 'name' must be a non-empty string";
        }
        if (!ah.hasKey("desc") || ah."desc".typeCode() != NT_STRING) {
            throw "DATASOURCE-CONNECTION-ERROR", "Argument 'desc' must be a non-empty string";
        }
        if (!ah.hasKey("url") || ah."url".typeCode() != NT_STRING) {
            throw "DATASOURCE-CONNECTION-ERROR", "Argument 'url' must be a non-empty string";
        }

        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "name");
        if (error) {
            throw "REST-ARG-ERROR", error.body;
        }

        if (ah.url !~ /^db:\/\//) {
            ah.url = "db://" + ah.url;
        }

        # issue #2972 also accept "opts"
        if (!ah.options && ah.hasKey("opts")) {
            ah.options = remove ah.opts;
        }

        QorusRestClass::parseOptAsHash("options", \ah);
        QorusRestClass::parseOptAsHash("tags", \ah);

        hash<auto> attr;
        if (ah.tags) {
            attr.tags = ah.tags;
        }

        return Qorus.dsmanager.registerConnection(ah.name, ah.desc, ah.url, attr, ah.options ?? {},
            id).internal_info.id;
    }
}

/** @REST /v3/remote (/v2/remote)

    This REST URI path provides actions and information about remote @ref remoteconn "Qorus", @ref userconn "user" and
    @ref dsconn "datasource" connections
*/
class RemoteRestClassV3 inherits RemoteRestClass {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "qorus": return new QorusRemoteConnectionsRestClassV3();
            case "user": return new UserConnectionsRestClassV3();
            case "datasources": return new DatasourcesRestClassV3();
        }
    }
}

/** @REST /v3/errors/{error} (/v2/errors/{error})

    This URI path provides actions and information related to a specific @ref globalandworkflowerrors "workflow error"
*/
class ErrorRestClassV3 inherits ErrorRestClass {
    constructor(hash<auto> eh) : ErrorRestClass(eh) {
    }

     /** @REST GET

        @par Description
        Returns a hash of information about the current @ref globalandworkflowerrors "workflow error"

        @par Return Value
        Returns a @ref rest_workflow_error_description_hash_v3
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, eh);
    }

    /** @REST PUT

        @par Description
        Updates the current @ref globalandworkflowerrors "workflow error" with the new definition given as arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (string) the new description of the error
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c status is set to @ref OMQ::StatRetry)
        - \c severity: (string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c status: (string) must be one of the following values:
          - @ref OMQ::StatError (the default if no \c status value is provided)
          - @ref OMQ::StatRetry
          - @ref OMQ::StatCanceled

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "UPDATED-WORKFLOW": the existing workflow-specific error was updated
        - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created (only possible in case of a race condition where the current error was deleted during this request)
        - \c "UNCHANGED-WORKFLOW": the new workflow-specific definition is identical to the old definition
        - \c "UPDATED-GLOBAL": the existing global error was updated
        - \c "CREATED-GLOBAL": a new global error was created (only possible in case of a race condition where the current error was deleted during this request)
        - \c "UNCHANGED-GLOBAL": the new global definition is identical to the old definition

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c ERROR-UPDATE-ERROR: invalid keys or key values provided in the error description hash

        @see
        - omq.system.update-global-error()
        - omq.system.update-workflow-error()
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        if (ah.error) {
            if (ah.error != eh.error)
                throw "UPDATE-ERROR", sprintf("cannot change the error name from %y to %y; first the existing error must be deleted and then the new error must be added", eh.error, ah.error);
        } else {
            ah.error = eh.error;
        }

        return eh.workflowid
            ? RestHandler::makeResponse(200, Qorus.EM.updateError(eh.workflowid, ah))
            : RestHandler::makeResponse(200, Qorus.EM.updateGlobalError(ah));
    }
}

/** @REST /v3/errors/global/{error} (/v2/errors/global/{error})

    This URI path provides actions and information related to a specific @ref globalandworkflowerrors "global workflow error"
*/
    /** @REST PUT

        @par Description
        Updates the current @ref globalandworkflowerrors "global workflow error" with the new definition given as arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (string) the new description of the error
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c status is set to @ref OMQ::StatRetry)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c status: (optional string) must be one of the following values:
          - @ref OMQ::StatError (the default if no \c status value is provided)
          - @ref OMQ::StatRetry
          - @ref OMQ::StatCanceled

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "UPDATED-GLOBAL": the existing global error was updated
        - \c "CREATED-GLOBAL": a new global error was created (only possible in case of a race condition where the current error was deleted during this request)
        - \c "UNCHANGED-GLOBAL": the new global definition is identical to the old definition

        @see
        - @ref rest_api_PUT_v3_errors__error_
        - @ref rest_api_PUT_v3_errors_workflow__id_or_name___error_
        - omq.system.update-global-error()
        - omq.system.update-workflow-error()
    */
    /** @REST PUT action=update

        @par Description
        Updates the current @ref globalandworkflowerrors "global workflow error" with the new definition given as arguments

        @see This API is equivalent to @ref rest_api_PUT_errors_global__error_; see that documentation for details.
    */

/** @REST /v3/errors/workflow/{id_or_name}/{error} (/v3/errors/{error})

    This URI path provides actions and information related to a workflow-specific @ref globalandworkflowerrors "workflow error"
*/
    /** @REST PUT

        @par Description
        Updates the current workflow-specific @ref globalandworkflowerrors "workflow error" with the new definition given as arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (string) the new description of the error
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c status is set to @ref OMQ::StatRetry)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c status: (optional string) must be one of the following values:
          - @ref OMQ::StatError (the default if no \c status value is provided)
          - @ref OMQ::StatRetry
          - @ref OMQ::StatCanceled

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "UPDATED-WORKFLOW": the existing workflow-specific error was updated
        - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created (only possible in case of a race condition where the current error was deleted during this request)
        - \c "UNCHANGED-WORKFLOW": the new workflow-specific definition is identical to the old definition

        @see
        - @ref rest_api_PUT_v3_errors__error_
        - @ref rest_api_PUT_v3_errors_global__error_
        - omq.system.update-global-error()
        - omq.system.update-workflow-error()
    */
    /** @REST PUT action=update

        @par Description
        Updates the current workflow-specific @ref globalandworkflowerrors "workflow error" with the new definition given as arguments

        @see This API is equivalent to @ref rest_api_PUT_v3_errors_workflow__id_or_name___error_; see that documentation for details.
    */

/** @REST /v3/errors/global (/v2/errors/global)

    This REST URI path provides actions and information related to @ref globalandworkflowerrors "global workflow errors"
*/
class GlobalErrorsRestClassV3 inherits GlobalErrorsRestClass {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> eh = Qorus.EM.getGlobalError(name);
        if (eh)
            return new ErrorRestClassV3(eh);
    }

    /** @REST GET

        @par Description
        Returns a list of information of @ref globalandworkflowerrors "global workflow errors"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c errors: optional; a comma-separated string will be split into a list; the @ref globalandworkflowerrors "global workflow errors" to return
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of error names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with error names and brief info is returned

        @par Return Value
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_workflow_error_description_hash_v3 elements for the @ref globalandworkflowerrors "global workflow errors" corresponding to the arguments
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        if (ah.errors.typeCode() == NT_STRING)
            ah.errors = ah.errors.split(",");

        list rl = Qorus.EM.getGlobalErrorsList(ah.errors);

        if (exists ah.list && parse_boolean(ah.list))
            rl = map $1.error, rl;
        else if (exists ah.short && parse_boolean(ah.short))
            rl = map sprintf("%s: (%s) status: %y, business: %y", $1.error, $1.severity, $1.status, $1.business_flag), rl;

        return RestHandler::makeResponse(200, rl);
    }

    /** @REST POST action=createOrUpdate

        @par Description
        Creates or updates a @ref globalandworkflowerrors "global workflow error"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (string) the new description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c status is set to @ref OMQ::StatRetry)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c status: (optional string) must be one of the following values:
          - @ref OMQ::StatError (the default if no \c status value is provided)
          - @ref OMQ::StatRetry
          - @ref OMQ::StatCanceled

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "UPDATED-GLOBAL": the existing global error was updated
        - \c "CREATED-GLOBAL": a new global error was created
        - \c "UNCHANGED-GLOBAL": the new global definition is identical to the old definition
    */
    hash<HttpHandlerResponseInfo> postCreateOrUpdate(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "error", N_WITH_DOT);
        if (exists error) {
            return error;
        }
        return RestHandler::makeResponse(200, Qorus.EM.updateGlobalError(ah));
    }

    /** @REST POST

        @par Description
        Creates a @ref globalandworkflowerrors "global workflow error"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the new description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c status is set to @ref OMQ::StatRetry)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c status: (optional string) must be one of the following values:
          - @ref OMQ::StatError (the default if no \c status value is provided)
          - @ref OMQ::StatRetry
          - @ref OMQ::StatCanceled

        @par Return Value
        This API returns a the following string: \c "CREATED-GLOBAL" indicating that a new @ref globalandworkflowerrors "global workflow error" was created

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c ERROR-EXISTS: this exception is thrown if the global workflow error already exists
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "error", N_WITH_DOT);
        if (exists error) {
            return error;
        }
        return RestHandler::makeResponse(200, Qorus.EM.updateGlobalError(ah, False, True));
    }
}

/** @REST /v3/errors/workflow/{id_or_name} (/v2/errors/workflow/{id_or_name})

    This URI path provides actions and information related to workflow-specific @ref globalandworkflowerrors "workflow errors" for a particular workflow
*/
class WorkflowSpecificErrorsRestClassV3 inherits WorkflowSpecificErrorsRestClass {
    constructor(int wfid) : WorkflowSpecificErrorsRestClass(wfid) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> eh = Qorus.EM.getWorkflowError(wfid, name);
        if (eh)
            return new ErrorRestClassV3(eh);
    }

    /** @REST GET

        @par Description
        Returns a list of information of workflow-specific @ref globalandworkflowerrors "workflow errors" for the current workflow

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c errors: optional; a comma-separated string will be split into a list; the @ref globalandworkflowerrors "workflow-specific workflow errors" for the current workflow to return
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of error names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with error names and brief info is returned

        @par Return Value
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_workflow_error_description_hash_v3 elements for the @ref globalandworkflowerrors "workflow errors" for the current workflow corresponding to the arguments
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        if (ah.errors.typeCode() == NT_STRING)
            ah.errors = ah.errors.split(",");

        list rl = Qorus.EM.getErrorsList(wfid, ah.errors);

        if (exists ah.list && parse_boolean(ah.list))
            rl = map $1.error, rl;
        else if (exists ah.short && parse_boolean(ah.short))
            rl = map sprintf("%s: (%s) status: %y, business: %y, type: %s", $1.error, $1.severity, $1.status, $1.business_flag, $1.type == "workflow" ? sprintf("%s v%s (%d)", $1.workflowname, $1.workflowversion, $1.workflowid) : "global"), rl;

        return RestHandler::makeResponse(200, rl);
    }

    /** @REST POST action=createOrUpdate

        @par Description
        Creates or updates a workflow-specific @ref globalandworkflowerrors "workflow error" for the current workflow

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the new description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c status is set to @ref OMQ::StatRetry)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c status: (optional string) must be one of the following values:
          - @ref OMQ::StatError (the default if no \c status value is provided)
          - @ref OMQ::StatRetry
          - @ref OMQ::StatCanceled

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "UPDATED-WORKFLOW": the existing workflow-specific error was updated
        - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created
        - \c "UNCHANGED-WORKFLOW": the new workflow-specific definition is identical to the old definition

        @note
        - this API always creates or updates a workflow-specific error; to optionally create or update a workflow-
          specific error dependending on the existence of a global error, use the
          @ref rest_api_POST_latest_errors_createOrUpdate API without the \a forceworkflow option
    */
    hash<HttpHandlerResponseInfo> postCreateOrUpdate(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "error", N_WITH_DOT);
        if (exists error) {
            return error;
        }
        return RestHandler::makeResponse(200, Qorus.EM.updateWorkflowError(wfid, ah));
    }

    /** @REST POST

        @par Description
        Creates a workflow-specific @ref globalandworkflowerrors "workflow error" for the current workflow

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the new description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c status is set to @ref OMQ::StatRetry)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c status: (optional string) must be one of the following values:
          - @ref OMQ::StatError (the default if no \c status value is provided)
          - @ref OMQ::StatRetry
          - @ref OMQ::StatCanceled

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created
        - \c "CREATED-GLOBAL": a new global error was created (only possible if \c forceworkflow is omitted or @ref False)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c ERROR-EXISTS: this exception is thrown if the workflow-specific error definition already exists

        @note
        - this API always creates a workflow-specific error; to optionally create or update a workflow-specific error
          dependending on the existence of a global error, use the @ref rest_api_POST_latest_errors API without the
          \a forceworkflow option
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "error", N_WITH_DOT);
        if (exists error) {
            return error;
        }
        return RestHandler::makeResponse(200, Qorus.EM.updateWorkflowError(wfid, ah, False, True));
    }
}

/** @REST /v3/workflows/{id_or_name}/errors (/v3/errors/workflow/{id_or_name})

    This REST URI path provides actions and information about workflow order data instance errors for a particular workflow.
*/

/** @REST /v3/errors/workflow (/v2/errors/workflow)

    This URI path provides actions and information related to workflow-specific @ref globalandworkflowerrors "workflow-specific workflow errors" across all workflows
*/
class WorkflowErrorsRestClassV3 inherits WorkflowErrorsRestClass {
    string name() {
        return "workflow";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int wfid;
        # return a 404 Not Found response if the wf does not exist
        try {
            wfid = WorkflowRestClass::staticGetWorkflowId(arg, True);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "WORKFLOW-ERROR") {
                return;
            }
            rethrow;
        }

        return new WorkflowSpecificErrorsRestClassV3(wfid);
    }

    /** @REST GET

        @par Description
        Returns a list of information of workflow-specific @ref globalandworkflowerrors "workflow errors" for all workflows

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c errors: optional; a comma-separated string will be split into a list; the @ref globalandworkflowerrors "workflow-specific workflow errors" for all workflows to return
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of error names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with error names and brief info is returned

        @par Return Value
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_workflow_error_description_hash_v3 elements for the @ref globalandworkflowerrors "workflow errors" for the current workflow corresponding to the arguments
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        if (ah.errors.typeCode() == NT_STRING)
            ah.errors = ah.errors.split(",");

        list rl = Qorus.EM.getAllWorkflowErrorsList(cx.user, ah.errors);

        if (exists ah.list && parse_boolean(ah.list))
            rl = map $1.error, rl;
        else if (exists ah.short && parse_boolean(ah.short))
            rl = map sprintf("%s: (%s) status: %y, business: %y, type: %s", $1.error, $1.severity, $1.status, $1.business_flag, $1.type == "workflow" ? sprintf("%s v%s (%d)", $1.workflowname, $1.workflowversion, $1.workflowid) : "global"), rl;

        return RestHandler::makeResponse(200, rl);
    }
}

/** @REST /v3/errors (/v2/errors)

    This URI path provides actions and information related to @ref globalandworkflowerrors "workflow errors"
*/
class ErrorsRestClassV3 inherits ErrorsRestClass {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        *softlist el = Qorus.EM.getAllErrorsList(cx.user, name);
        if (!el) {
            if (name == "global")
                return new GlobalErrorsRestClassV3();
            if (name == "workflow")
                return new WorkflowErrorsRestClassV3();
            return;
        }

        if (el.size() == 1)
            return new ErrorRestClassV3(el[0]);

        list l = (map $1.workflowid ? sprintf(".../errors/workflow/%d/%s", $1.workflowid, name) : sprintf(".../errors/global/%s", name), el);
        throw "AMBIGUOUS-ERROR", sprintf("error %y has %d definitions; use one of the following URI fragments to access: %s", name, el.size(), (foldl $1 + ", " + $2, l));
    }

    /** @REST GET

        @par Description
        Returns a list of information of @ref globalandworkflowerrors "workflow errors" corresponding to the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c errors: optional; a comma-separated string will be split into a list; the @ref globalandworkflowerrors "workflow errors"
        - \c filter: optional; if \c "global" then only global errors will be listed; other values for this argument key are ignored; takes precendence over \c wf
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of error names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with error names and brief info is returned
        - \c wf: optional; a workflow ID or name to use to filter the results with; ignored if \c filter = \c "global"

        @par Return Value
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_workflow_error_description_hash_v3 elements corresponding to the arguments
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        list rl = staticGetErrors(cx, ah);

        if (exists ah.list && parse_boolean(ah.list))
            rl = map $1.error, rl;
        else if (exists ah.short && parse_boolean(ah.short))
            rl = map sprintf("%s: (%s) status: %y, business: %y, type: %s", $1.error, $1.severity, $1.status, $1.business_flag, $1.type == "workflow" ? sprintf("%s v%s (%d)", $1.workflowname, $1.workflowversion, $1.workflowid) : "global"), rl;

        return RestHandler::makeResponse(200, rl);
    }

    /** @REST GET action=search

        @par Description
        Returns a list of information of @ref globalandworkflowerrors "workflow errors" corresponding to the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c errors: a comma-separated string will be split into a list; the @ref globalandworkflowerrors "workflow errors" to search for

        @par Return Value
        This API returns a list of @ref rest_workflow_error_description_hash_v3 elements corresponding to the arguments
    */
    hash<HttpHandlerResponseInfo> getSearch(hash<auto> cx, *hash<auto> ah) {
        if (ah.errors.typeCode() == NT_STRING)
            ah.errors = ah.errors.split(",");

        if (!ah.errors)
            return RestHandler::makeResponse(200, ());

        return RestHandler::makeResponse(200, Qorus.EM.searchList(cx.user, ah.errors));
    }

    /** @REST POST action=createOrUpdate

        @par Description
        Creates or updates a @ref globalandworkflowerrors "workflow error"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the new description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c forceworkflow: (optional bool) parsed with @ref Qore::parse_boolean(); if @ref True then the workflow error will be created as a workflow-specific error even if no global error exists; default if not present @ref False; only used if \c workflowid also present
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c status is set to @ref OMQ::StatRetry)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c status: (optional string) must be one of the following values:
          - @ref OMQ::StatError (the default if no \c status value is provided)
          - @ref OMQ::StatRetry
          - @ref OMQ::StatCanceled
        - \c workflowid: (optional string) an optional workflow ID for potentially creating a workflow-specific workflow error definition

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "UPDATED-WORKFLOW": the existing workflow-specific error was updated
        - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created
        - \c "UNCHANGED-WORKFLOW": the new workflow-specific definition is identical to the old definition
        - \c "CREATED-GLOBAL": a new global error was created (only possible if \c forceworkflow is omitted or @ref False)
        - \c "UNCHANGED-GLOBAL": the new global definition is identical to the old definition

        @note
        - the default behavior of this API is to create a global error if no global error with the error name exists; in this case a workflow-specific error can be forced to be created by using the \c workflowid and \c forceworkflow options as described above
    */
    hash<HttpHandlerResponseInfo> postCreateOrUpdate(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "error", N_WITH_DOT);
        if (exists error) {
            return error;
        }

        if (ah.workflowid) {
            softint wfid = remove ah.workflowid;
            if (ah.hasKey("forceworkflow") && parse_boolean(remove ah.forceworkflow))
                return RestHandler::makeResponse(200, Qorus.EM.updateWorkflowError(wfid, ah));

            return RestHandler::makeResponse(200, Qorus.EM.updateError(wfid, ah));
        }

        return RestHandler::makeResponse(200, Qorus.EM.updateGlobalError(ah));
    }

    /** @REST POST

        @par Description
        Creates a @ref globalandworkflowerrors "workflow error"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the new description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c forceworkflow: (optional bool) parsed with @ref Qore::parse_boolean(); if @ref True then the workflow error will be created as a workflow-specific error even if no global error exists; default if not present @ref False; only used if \c workflowid also present
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c status is set to @ref OMQ::StatRetry)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c status: (optional string) must be one of the following values:
          - @ref OMQ::StatError (the default if no \c status value is provided)
          - @ref OMQ::StatRetry
          - @ref OMQ::StatCanceled
        - \c workflowid: (optional string) an optional workflow ID for potentially creating a workflow-specific workflow error definition

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created
        - \c "CREATED-GLOBAL": a new global error was created (only possible if \c forceworkflow is omitted or @ref False)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c ERROR-EXISTS: this exception is thrown if the workflow-specific error definition already exists

        @note
        - the default behavior of this API is to create a global error if no global error with the error name exists; in this case a workflow-specific error can be forced to be created by using the \c workflowid and \c forceworkflow options as described above
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "error", N_WITH_DOT);
        if (exists error) {
            return error;
        }

        if (ah.workflowid) {
            softint wfid = remove ah.workflowid;

            if (ah.hasKey("forceworkflow") && parse_boolean(remove ah.forceworkflow))
                return RestHandler::makeResponse(200, Qorus.EM.updateWorkflowError(wfid, ah, False, True));

            return RestHandler::makeResponse(200, Qorus.EM.updateError(wfid, ah, False, True));
        }

        return RestHandler::makeResponse(200, Qorus.EM.updateGlobalError(ah, False, True));
    }
}

/** @REST /v3/system/userhttp (/system/userhttp)

    This REST URI path provides actions and information about user HTTP services.
*/
class SystemUserHttpRestClassV3 inherits SystemUserHttpRestClass {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            *hash<auto> h = services.getUserHttpServiceInfo(cx);
            if (h.hasKey(name))
                return new AttributeRestClass((map $1 + {"group": name}, h{name}.iterator()));
        }
    }

    /** @REST GET

        @par Description
        Returns a hash keyed by resource type with values as lists of hashes of information about user-defined HTTP services

        @par Return Value
        The hash element in each list has the following keys:
        - \c title: the title of the HTTP service
        - \c url: the full URL to the service
        - \c service: the name of the service
        - \c version: the version of the service
        - \c serviceid: the service ID

        @since Qorus 4.0 returns an empty hash in case no data is available
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        olog(LoggerLevel::INFO, "USERHTTP v3");
        return RestHandler::makeResponse(200, services.getUserHttpServiceInfo(cx) ?? {});
    }
}

/** @REST /v3/jobs/{id_or_name}/config/{name}

    This REST URI path provides actions and information related to a particular Qorus job.
    Prefix can be passed within the config item name or as following: /v3/jobs/{id_or_name}/config/{name}?prefix={prefix}.

    @ref job_config_items "job configuration item"
*/
class JobConfigItemRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> jh;
        hash<auto> item;

        string name_with_prefix;
    }

    constructor(hash<auto> jh, hash<auto> item) {
        self.jh = jh;
        self.item = item;
        name_with_prefix = item.prefix + item.name;
    }

    string name() {
        return item.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (item.hasKey(arg)) {
                return new AttributeRestClass(item{arg});
            }
        }
    }

    /** @REST GET
        @par Description
        Returns a hash for the current @ref job_config_items "job configuration item"

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": the default value of the configuration item
        - \c "value": the value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "level": the level from where the value is obtained (interface level (e.g. "job:1", "job:2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, item);
    }

    /** @REST GET action=yaml
        @par Description
        Returns a hash for the current @ref job_config_items "job configuration item" as a serialized YAML string

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": (YAML-serialized string) the default value of the configuration item
        - \c "value": (YAML-serialized string) the value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        - \c "level": the level from where the value is obtained (interface level (e.g. "job:1", "job:2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<HttpHandlerResponseInfo> getYaml(hash<auto> cx, *hash<auto> ah) {
        auto new_item = QorusRestClass::serializeValuesToYaml(item, ("default_value", "value"));
        if (exists new_item.allowed_values) {
            new_item.allowed_values = serializeValuesInListToYaml(new_item.allowed_values);
        }
        return RestHandler::makeResponse(200, new_item);
    }

    /** @REST PUT

        @par Description
        Sets the value for the given @ref job_config_items "job configuration item"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value: the value of the configuration item; must be compatible with the item's declared type

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value: the new value
        - \c info: info about the service configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("value")) {
            return RestHandler::makeResponse(400, "no key \"value\" argument sent in request");
        }

        hash changed = Qorus.qmm.setConfigItemValueOnInterfaceLevel("job", jh.jobid, name_with_prefix, ah.value);
        changed.info = sprintf("%y configuration item value for job %s v%s (%d) has been changed",
                               name_with_prefix, jh.name, jh.version, jh.jobid);
        return RestHandler::makeResponse(200, changed);
    }

    /** @REST PUT action=yaml

        @par Description
        Sets the value for the given @ref job_config_items "job configuration item" using a YAML-serialized string

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value: (YAML-serialized string) the value of the configuration item; must be compatible with the item's declared type

       @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value (YAML-serialized string): the new value
        - \c info: info about the service configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<HttpHandlerResponseInfo> putYaml(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error;
        ah = QorusRestClass::deserializeYamlValues(ah, "value", \error);
        if (exists error) {
            return error;
        }

        hash<HttpHandlerResponseInfo> result = put(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }

    /** @REST DELETE

        @par Description
        Permanently deletes the current value for the configuration item on this job level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value: deleted value
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        hash<auto> result;
        auto res = Qorus.qmm.deleteConfigItemValueOnInterfaceLevel("job", jh.jobid, name_with_prefix, \result.deleted);
        result += {
            "value": res,
            "info": sprintf("%y configuration item value for job %s v%s (%d) has been deleted",
                        name_with_prefix, jh.name, jh.version, jh.jobid),
        };
        return RestHandler::makeResponse(200, result);
    }

    /** @REST DELETE action=yaml

        @par Description
        Permanently deletes the current value for the configuration item on this job level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value (YAML-serialized string): deleted value
    */
    hash<HttpHandlerResponseInfo> delYaml(hash<auto> cx, *hash<auto> ah) {
        hash<HttpHandlerResponseInfo> result = del(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }
}

/** @REST /v3/jobs/{id_or_name}/config

    This REST URI path provides actions and information related to Qorus
    @ref job_config_items "job configuration items"
*/
class job_config_itemsRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> jh;
    }

    constructor(hash<auto> jh) {
        self.jh = jh;
    }

    string name() {
        return "config";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        string name_with_prefix = ah.prefix + arg;
        if (*hash<auto> item = jh.config{name_with_prefix}) {
            # get actual item name
            if (item.prefix && name_with_prefix.equalPartial(item.prefix)) {
                arg = name_with_prefix[item.prefix.length()..];
            }
            return new JobConfigItemRestClassV3(jh, {"name": arg} + jh.config{name_with_prefix});
        }
    }

    /** @REST GET
        @par Description
        Returns a list of @ref job_config_items "job configuration items" for the job

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": the default value of the configuration item
        - \c "value": the value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "level": the level from where the value is obtained (interface level (e.g. "job:1", "job:2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                                                   jh.config.pairIterator()));
    }

    /** @REST GET action=yaml
        @par Description
        Returns a list of @ref job_config_items "job configuration items" for the job as a YAML-serialized string

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "desc": the description of the configuration item
        - \c "default_value": (YAML-serialized string) the default value of the configuration item
        - \c "value": (YAML-serialized string) the value of the configuration item
        - \c "strictly_local": if the configuration item is defined strictly on local level
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "config_group": the group of the configuration item
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        - \c "level": the level from where the value is obtained (interface level (e.g. "job:1", "job:2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<HttpHandlerResponseInfo> getYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> config_copy = jh.config;

        foreach auto config in (config_copy.pairIterator()) {
            config_copy{config.key} = QorusRestClass::serializeValuesToYaml(config.value, ("value", "default_value"));
            if (exists config.value.allowed_values) {
                config_copy{config.key}.allowed_values = serializeValuesInListToYaml(config.value.allowed_values);
            }
        }
        list<auto> items = map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                               config_copy.pairIterator();
        return RestHandler::makeResponse(200, items);
    }
}

/** @REST /v3/jobs/{id_or_name} (/v2/jobs/{id_or_name})

    This REST API path provides actions and information related to specific jobs;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class JobDefinitionRestClassV3 inherits JobDefinitionRestClass {
    constructor(hash<auto> jh) : JobDefinitionRestClass(jh) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (name == "config") {
            return new job_config_itemsRestClassV3(jh);
        }
        if (name == "logger") {
            return new LoggerRestClass("jobs", "jobid", jh.jobid);
        }
        return JobDefinitionRestClass::subClassImpl(name, cx, ah);
    }

    /** @REST PUT action=setActive

        @SCHEMA
        @summary Updates the active status of a job

        @desc Updates the active status of a job; if any errors occur an exception is thrown. \n
        This API works on all jobs regardless of state; the job does not have to be running or active to be updated. \
        Updating a job to active will start the job immediately unless the expiry date is past or the job is a \
        member of a disabled @ref rbacgroups "group".  Changing a currently-active job to inactive will stop the job \
        immediately.

        @params
        - active (bool): the new active state of the job

        @return (hash JobActiveUpdateInfo): a hash of information about the update operation
        - jobid (int): the job ID
        - name (string): the job name
        - active (bool): the new active state of the job
        - info (string): a descriptive string
        - db_active (bool): the active state in the DB (can differ from \c active if the job cannot be started for \
          example)

        @error (409): \c JOB-ERROR: cannot set expired jobs to active
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c JOB-ERROR: cannot set expired jobs to active
    */
    hash<HttpHandlerResponseInfo> putSetActive(hash<auto> cx, *hash<auto> ah) {
        return handlePutSetActive(cx, ah, 3);
    }

    /** @REST PUT action=setRemote

        @SCHEMA
        @summary Updates the remote status of a job

        @desc Updates the remote status of a job, determining if a job runs in a remote process or not. \
        Jobs that have their remote value changed are temporarily disabled and then reenabled after the change.

        @params
        - remote (bool): the new remote state of the job

        @return (hash JobRemoteUpdateInfo): a hash of information about the update operation
        - updated (bool): if the remote status was updated
        - remote (bool): the new remote state of the job
        - info (string): a descriptive string
        @ENDSCHEMA
     */
    hash<HttpHandlerResponseInfo> putSetRemote(hash<auto> cx, *hash<auto> ah) {
        string info = sprintf("job %s v%s (%d)", jh.name, jh.version, jh.jobid);

        if (!exists ah.remote) {
            throw "JOB-SETREMOTE-ERROR", sprintf("missing \"remote\" argument to update job %s", info);
        }

        rlog(cx, "(%s)", info);

        ah.remote = parse_boolean(ah.remote);

        bool updated;
        try {
            updated = Qorus.qmm.updateJobRemote(jh.jobid, ah.remote);
            if (updated) {
                info += sprintf(" was updated with remote = %y", ah.remote);
            } else {
                info += sprintf(" was not updated because remote already was %y", ah.remote);
            }
        } catch (hash<ExceptionInfo> ex) {
            info += Qorus.getDebugSystem()
                ? sprintf(", update remote failed: %s", get_exception_string(ex))
                : sprintf(", update remote failed: %s: %s", ex.err, ex.desc);
            updated = False;
        }

        hash<auto> rv = {
            "updated": updated,
            "remote": ah.remote,
            "info": info,
        };

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST POST action=kill

        @SCHEMA
        @summary Kills a remote @ref qjob "job cluster process"

        @desc Kills a remote @ref qjob "job cluster process"

        @return (hash KillResultInfo): information about the result of the operation
        - status (string): either \c "OK" or \c "ERR"
        - code (int): the return code of the \c kill() command: 0 if successful, non-zero if not

        @error (404): if no remote process is running for the job
        @ENDSCHEMA

        @par Errors
        - <tt><b>404 Not Found</b></tt>: this response is returned if no process is running for the current job
    */
    hash<HttpHandlerResponseInfo> postKill(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # get current job info to avoid race conditions
        *hash<auto> info = jh.process.id ? Qorus.qmm.lookupProcess(jh.process.id) : NOTHING;
        if (!info) {
            return <HttpHandlerResponseInfo>{
                "code": 404,
                "body": sprintf("no process is currently running for job %s v%s (%d)", jh.name, jh.version, jh.jobid),
            };
        }
        return ProcessRestClassV3::staticKillProcess(info, cx, ah);
    }
}

/** @REST /v3/jobs (/v2/jobs)

    This REST API path provides actions and information related to Qorus jobs.
*/
class JobRestClassV3 inherits JobRestClassV2, HelpLoggerRestClass, HelpLoggerAppendersRestClass {
    constructor() : HelpLoggerRestClass("jobs"), HelpLoggerAppendersRestClass("jobs", "jobs") {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = JobRestClass::staticGetJobId(arg);
        *hash<auto> job = JobRestClassV2::staticGetJob(cx, ah, id, 3);
        if (!job) {
            return;
        }

        hash<auto> ji = Qorus.jobManager.getActiveInfo();
        JobRestClass::fixJob(\job, ji.(job.name), cx);

        return internGetJobDefinition(job);
    }

    private static list<auto> staticGetJobs(hash<auto> cx, *hash<auto> ah) {
        return JobRestClassV2::staticGetJobs(cx, ah, 3);
    }

    private QorusRestClass internGetJobDefinition(hash<auto> job) {
        return new JobDefinitionRestClassV3(job);
    }

    /** @REST GET

        @par Description
        Returns information about Qorus jobs according to the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c defonly: optional (parsed with @ref Qore::parse_boolean()); if @ref True then no job result information will be included in the return value; default @ref False
        - \c date: optional (parsed as a date); the past cutoff date for job result (job instances) for the return value; if not present, then defaults to the last 24 hours
        - \c jobs: one or more job names or IDs to filter the result list; a comma-separated string will be split into a list
        - \c lib_source: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the source code for each library object is returned in the @ref rest_job_description_hash
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of job names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of job names and descriptions is returned
        - \c sqlcache: optional (parsed with @ref Qore::parse_boolean()); if @ref False then no SQL cache will be used for historical info; default @ref True (only used if \c defonly is omitted or @ref False)
        - \c status: options; either \c "active" or \c "inactive" to filter jobs based on their active status

        @par Return Value
        If neither \c list nor \c short are used, then this API returns a list of @ref rest_job_description_hash_v2 elements; if \c defonly is not @ref True, then any jobs with job result data within the given time period (as defined by the \c date option) will be reflected in the following extra keys:
        - \c IN-PROGRESS: the number of job instances currently in progress
        - \c COMPLETE: the number of job instances with a @ref OMQ::StatComplete status during the given time period
        - \c ERROR: the number of job instances with a @ref OMQ::StatError status during the given time period
    */
    # args: "date", "status"
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, JobRestClassV3::staticGetJobs(cx, ah, 3));
    }

    /** @REST GET action=defaultLogger

        @par Description
        Returns default logger info

        @par Return Value
        This API returns 200 OK and hash with the following keys:
        - \c loggerid: (int) logger id
        - \c params: (hash) logger params
            - \c level: (hash) @ref Logger::LoggerLevel "LoggerLevel"
                - \c "key": logger level string representation
                - \c "value": logger level int representation
            - \c name: (string) logger name
            - \c additivity: (bool) logger additivity
        - \c interface_table_name: (string) interface table name (jobs/workflows/services). If set means default logger
     */
    hash<HttpHandlerResponseInfo> getDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::getImpl(cx, ah);
    }

    /** @REST POST action=defaultLogger

        @par Description
        Create default Logger

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: required; (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: (string) logger name
        - \c additivity: (bool) logger additivity (default @ref True)
        - \c cloneDefault: (bool) create logger with appenders based on default logger

        @par Return Value
        If success 200 with the logger ID created, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<HttpHandlerResponseInfo> postDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::postImpl(cx, ah);
    }

    /** @REST PUT action=defaultLogger

        @par Description
        Set logger params

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: logger name to set
        - \c additivity: logger additivity to set

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<HttpHandlerResponseInfo> putDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::putImpl(cx, ah);
    }

    /** @REST DELETE action=defaultLogger

        @par Description
        Delete logger

        @par Return Value
        If success 200 OK, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<HttpHandlerResponseInfo> delDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::delImpl(cx, ah);
    }

    /** @REST GET action=defaultLoggerAppenders

        @par Description
        Return all logger appenders

        @par Return Value
        This API returns 200 OK and list with the following hashes:
        - \c appenderId: (int) appenderId
        - \c params: (hash) possible appender parameters, might be missing if not set
            - \c name: (string) appender name
            - \c layoutPattern: (string) appender layout pattern
            - \c rotation: (int) appender layout pattern
            - \c filename: (string) appender filename
    */
    hash<HttpHandlerResponseInfo> getDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::getImpl();
    }

    /** @REST DELETE action=defaultLoggerAppenders
        @par Description
        Delete logger appender with obtained id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be deleted

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<HttpHandlerResponseInfo> delDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::delImpl(cx, ah);
    }

    /** @REST POST action=defaultLoggerAppenders

        @par Description
        Create logger appenders

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK and appender id, in case of fail one of the error codes: 400, 409 and \a string of error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<HttpHandlerResponseInfo> postDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::postImpl(cx, ah);
    }

    /** @REST PUT action=defaultLoggerAppenders

        @par Description
        Update logger appender with the given id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be update
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<HttpHandlerResponseInfo> putDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::putImpl(cx, ah);
    }
}

/** @REST /v3/system/metadata/reload/{object_type}

    \c object_type can be one of following PUT calls:

    - all: reload all maps
    - functions
    - classes
    - constants
    - queues
    - events
    - mappers
    - vmaps
    - steps
    - workflows
    - services
    - jobs
    - slas
    - config_values
    - pipelines
    - fsm
 */
class ReloadAllRestClassV3 inherits QorusRestClass {
    private {
        string m_name;
    }

    constructor(string name) {
        m_name = name;
    }

    string name() {
        return m_name;
    }

    /** @REST PUT

        @par Description
        Reloads the given metadata cache
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        hash rv;
        softlist keys_to_do = (m_name == "all")
                                ? keys MetadataRestClass::Reload
                                : m_name;

        ListIterator it(keys_to_do);
        while (it.next()) {
            string method = MetadataRestClass::Reload{it.getValue()};
            rv{it.getValue()} = call_object_method(Qorus.qmm, method);
        }

        return RestHandler::makeResponse(200, rv);
    }

} # class ReloadAllRestClassV3

/** @REST /v3/system/metadata/reload

    See also @ref rest_api_PUT_v3_system_metadata_reload
 */
class ReloadRestClassV3 inherits QorusRestClass {
    string name() {
        return "reload";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (MetadataRestClass::Reload.hasKey(arg)
            || arg == "all")
        {
            return new ReloadAllRestClassV3(arg);
        }
    }

    /** @REST PUT

        @par Description
        Reloads the given metadata cache and resets affected interface objects according to the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body); all keys are optional:
        - \c workflows: a list of workflow IDs to reload in the metadata cache and reset
        - \c services: a list of service IDs to reload in the metadata cache and to reset
        - \c jobs: a list of job IDs to reload in the metadata cache and to reset
        - \c mappers: a list of mapper IDs to reload in the metadata cache
        - \c vmaps: a list of value map IDs to reload in the metadata cache
        - \c functions: a list of functions IDs to reload in the metadata cache
        - \c classes: a list of class IDs to reload in the metadata cache
        - \c constants: a list of constant IDs to reload in the metadata cache
        - \c queues: a list of queue IDs to reload in the metadata cache
        - \c events: a list of event IDs to reload in the metadata cache
        - \c steps: a list of step IDs to reload in the metadata cache
        - \c config_values: a list of config item names to reload their values in the metadata cache

        @par Return Value
        This method returns a hash with keys depending on the arguments as follows:
        - \c workflows: the number of workflows updated in the metadata cache
        - \c services: the number of services updated in the metadata cache
        - \c jobs: the number of jobs updated in the metadata cache
        - \c mappers: the number of mappers updated in the metadata cache
        - \c vmaps: the number of value maps updated in the metadata cache
        - \c functions: the number of functions updated in the metadata cache
        - \c classes: the number of classes updated in the metadata cache
        - \c constants: the number of constants updated in the metadata cache
        - \c queues: the number of queues updated in the metadata cache
        - \c events: the number of events updated in the metadata cache
        - \c steps: the number of steps updated in the metadata cache
        - \c config_values: the number of configuration item values updated in the metadata cache
        - \c workflow_reset: a hash of workflow reset info; see the return value of @ref rest_api_PUT_workflows_reset for a description of this hash
        - \c service_reset: a hash of service reset info; see the return value of @ref rest_api_PUT_services_reset for a description of this hash
        - \c job_reset: a hash of job reset info; see the return value of @ref rest_api_PUT_jobs_reset for a description of this hash

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c METADATA-RELOAD-ERROR: unknown metadata keys passed
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        return MetadataRestClass::staticReload(cx, ah);
    }
}

/** @REST /v3/system/metadata/{lookup}

    This REST URI path provides information related
    to the system metadata maps and lookups.

    This set of API calls provides a thread-safe cache for
    internal Qorus data. The underlying functionality
    provided by this service has been moved into the Qorus
    server to avoid race conditions and dependencies
    with the service infrastructure. Qorus internally
    and Qorus system services no longer use this service
    for metadata lookups, but rather use internal
    functionality directly.
*/

/** @REST /v3/system/metadata/systemserviceids

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of all system service ids
*/

/** @REST /v3/system/metadata/userserviceids

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of all user service ids
*/

/** @REST /v3/system/metadata/stepmap
*/
/** @REST GET
    @par Description
    Returns a map of stepids to step info
*/

/** @REST /v3/system/metadata/steprmap
*/
/** @REST GET
    @par Description
    Returns a map of names to step info
*/

/** @REST /v3/system/metadata/functionmap
*/
/** @REST GET
    @par Description
    Returns a map of function instance ids to function info
*/

/** @REST /v3/system/metadata/functionrmap
*/
/** @REST GET
    @par Description
    Returns a map of function names to function instance ids
*/

/** @REST /v3/system/metadata/qmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of queue ids to queue info
*/

/** @REST /v3/system/metadata/qrmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of queue names to queue ids
*/

/** @REST /v3/system/metadata/sla

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of SLA ids to SLA info
*/

/** @REST /v3/system/metadata/slarmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of SLA names to SLA ids
*/

/** @REST /v3/system/metadata/mmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of mapper ids to mapper info
*/

/** @REST /v3/system/metadata/mrmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of mapper names and versions to mapper IDs
*/

/** @REST /v3/system/metadata/wfmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of workflow ids to workflow info
*/

/** @REST /v3/system/metadata/wfrmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of workflow names to workflow ids
*/

/** @REST /v3/system/metadata/wfids

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of all workflow ids
*/

/** @REST /v3/system/metadata/constmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of constant ids to constant info
*/

/** @REST /v3/system/metadata/constrmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of constant names to constant ids
*/

/** @REST /v3/system/metadata/classmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of class ids to constant info
*/

/** @REST /v3/system/metadata/classrmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of class names to class ids
*/

/** @REST /v3/system/metadata/emap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of workflow synchronization event ids to workflow synchronization event info
*/

/** @REST /v3/system/metadata/ermap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of workflow synchronization event type names to workflow synchronization event ids
*/

/** @REST /v3/system/metadata/servicemap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of service ids to service info
*/

/** @REST /v3/system/metadata/servicermap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of service names to service ids
*/

/** @REST /v3/system/metadata/serviceamap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of service types (lower case) -> names -> hash (serviceid, version)
*/

/** @REST /v3/system/metadata/svcids

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of all service ids
*/

/** @REST /v3/system/metadata/jmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of job ids to job info
*/

/** @REST /v3/system/metadata/jrmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of job names to job ids
*/

/** @REST /v3/system/metadata/jobids

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of all job ids
*/

/** @REST /v3/system/metadata/vmmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of value map ids to value map info
*/

/** @REST /v3/system/metadata/vmrmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a map of value map names to value map IDs
*/

/** @REST /v3/system/metadata/lookupstep/{stepid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a hash of info for the given stepid or no value if the step id does not exist

    @par Arguments
    This API takes the following argument:
    - \c verbose: if @ref True then more information is returned

    @par Return Value
    A hash of @ref omqmapstepinfo "step info" for the given stepid or no value if the stepid does not exist
*/

/** @REST /v3/system/metadata/lookupsteps

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a hash keyed by stepid of info for the given stepid(s) or no value if the step ids do not exist

    @par Arguments
    This API takes the following arguments:
    - \c ids: one or more stepids to lookup
    - \c verbose: if @ref True then more information is returned

    @par Return Value
    A hash keyed by stepid with values as @ref omqmapstepinfo "step info hashes" for each valid step; unknown steps are ignored
*/

/** @REST /v3/system/metadata/rlookupstep/{stepname}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a hash giving the result of a reverse lookup of step info from its name

    @par Arguments
    This API takes the following arguments:
    - \c name: the name of the step

    @par Return Value
    @ref nothing if the arguments do not match a cached step or a hash where
    the keys are version strings and the values are the corresponding step IDs
    and the following two special keys:
    - \c lvcreated: the creation date/time of the latest version of the step
    - \c lastversion: the version string of the latest version

    @note the latest version of the step is determined by the creation time of
    the step and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/rlookupstep/{stepname}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the stepid of a particular step from the name and version

    @par Return Value
    Returns the stepid for the given version of a step or @ref nothing if there is no match
*/

/** @REST /v3/system/metadata/stepid/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns the stepid from the step name, throws an exception if no match is found

    @par Return Value
    Returns the stepid for the given step name

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c STEP-ERROR: step cannot be found
*/

/** @REST /v3/system/metadata/stepid/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns the stepid from the step name and version, throws an exception if no match is found

    @par Return Value
    Returns the stepid for the given step name and version

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c STEP-ERROR: step cannot be found
*/

/** @REST /v3/system/metadata/lookupfunc/{funcid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up function info from the function ID

    @par Return Value
    Returns a hash with function metadata

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c OMQMAP-LOOKUPFUNC-ERROR: this error will be thrown if the function ID passed is not a valid function ID
*/

/** @REST /v3/system/metadata/rlookupfunc/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up all versions of a function from the function's name

    @par Return Value
    Returns @ref nothing if the arguments do not match a cached function or a hash where
    the keys are version strings and the values are the corresponding function IDs
    and the following two special keys:
    - \c lvcreated: the creation date/time of the latest version of the function
    - \c lastversion: the version string of the latest version

    @note The latest version of the function is determined by the creation time of
    the function and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/rlookupfunc/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the functionid of a particular function from the name and version

    @par Return Value
    Returns @ref nothing if the arguments do not match or the functionid for the latest
    version of the function

    @note The latest version of the function is determined by the creation time of
    the function and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/functionid/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the function ID from the name

    @par Return Value
    Returns the functionid for the given function name

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c FUNCTION-ERROR: function cannot be found
*/

/** @REST /v3/system/metadata/functionid/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns the functionid from the function name and version, throws an exception if no match is found

    @par Return Value
    Returns the functionid for the given function name and version

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c FUNCTION-ERROR: function cannot be found
*/

/** @REST /v3/system/metadata/lookupqueue/{qid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up queue information from the queueid

    @par Return Value
    @ref nothing if the given ID is not a valid queue ID or a hash of queue information with the following keys:
    - \c name: the name of the queue
    - \c serviceid: the service associated with the queue

    @note Currently the service association is ignored by Qorus and is provided for informational purposes only
*/

/** @REST /v3/system/metadata/rlookupqueue/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up queue information from the queue name

    @par Return Value
    @ref nothing if the given name is not a valid queue name or a hash of queue information with the following keys:
    - \c queueid: the queueid of the queue
    - \c serviceid: the service associated with the queue

    @note Currently the service association is ignored by Qorus and is provided for informational purposes only
*/

/** @REST /v3/system/metadata/lookupsla/{slaid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up SLA information from the slaid

    @par Return Value
    @ref nothing if the given ID is not a valid SLA ID or a hash of SLA information with the following keys:
    - \c name: the name of the SLA
    - \c type: the type of the SLA
    - \c description: the description of the SLA
*/

/** @REST /v3/system/metadata/rlookupsla/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up SLA information from the SLA name

    @par Return Value
    @ref nothing if the given name is not a valid SLA name or a hash of SLA information with the following keys:
    - \c slaid: the ID of the SLA
    - \c type: the type of the SLA
    - \c description: the description of the SLA
*/

/** @REST /v3/system/metadata/lookupworkflow/{wfid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up workflow information from the workflowid

    @par Arguments
    This API takes the following arguments:
    - \c verbose: if @ref True then additional step and function information is included in the return value

    @par Return Value
    @ref nothing if the workflowid does not match any cached workflow, otherwise a
    @ref omqmapworkflowinfo "workflow information hash"
*/

/** @REST /v3/system/metadata/rlookupworkflow/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up all versions of a workflow from the workflow name

    @par Return Value
    @ref nothing if the argument does not match a cached workflow or a hash,
    otherwise the top-level keys of the hash are the cached versions of the
    workflow and the values are @ref omqmapworkflowinfo "workflow information hashes"

    @note Lhe latest version of the workflow is determined by the creation
    time of the workflow and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/rlookupworkflow/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns workflow info from the workflow name and version

    @par Return Value
    @ref nothing if the arguments do not match a cached workflow or a hash,
    otherwise a @ref omqmapworkflowinfo "workflow information hash" is returned
*/

/** @REST /v3/system/metadata/workflowid/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the latest workflow id from the name

    @par Return Value
    The integer workflowid value

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-ERROR: workflow does not exist

    @note The latest version of the workflow is determined by the creation
    time of the workflow and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/workflowid/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the workflow id from the name and version

    @par Return Value
    The integer workflowid value

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-ERROR: workflow does not exist
*/

/** @REST /v3/system/metadata/lookupconstant/{cid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up constant information from the constantid

    @par Return Value
    @ref nothing if the constantid does not match any cached constant, otherwise a hash with the following keys:
    - \c name: the name of the constant
    - \c version: the version of the constant
    - \c patch: the patch string for the constant
    - \c description: the description of the constant
    - \c created: the date/time the constant was created
    - \c modified: the date/time the constant was last modified
*/

/** @REST /v3/system/metadata/rlookupconstant/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up all versions of a constant from the constant's name

    @par Return Value
    @ref nothing if the arguments do not match a cached constant or a hash where
    the keys are version strings and the values are the corresponding constant IDs
    and the following two special keys:
    - \c lvcreated: the creation date/time of the latest version of the constant
    - \c lastversion: the version string of the latest version
    @note the latest version of the constant is determined by the creation time of
    the constant and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/rlookupconstant/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the constantid of a particular constant from the name and version

    @par Return Value
    @ref nothing if the arguments do not match or the constantid for the latest
    version of the constant

    @note The latest version of the constant is determined by the creation time of
    the constant and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/constantid/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the latest constant id(s) from the name

    @par Return Value
    The integer constant ID value

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c CONSTANT-ERROR: constant does not exist

    @note The latest version of the constant is determined by the creation
    time of the constant and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/constantid/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the constant ID from the name and version

    @par Return Value
    The integer constantid value

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c CONSTANT-ERROR: constant does not exist
*/

/** @REST /v3/system/metadata/lookupclass/{cid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up class information from the classid

    @par Return Value
    @ref nothing if the classid does not match any cached class, otherwise a hash with the following keys:
    - \c name: the name of the class
    - \c version: the version of the class
    - \c patch: the patch string for the class
    - \c description: the description of the class
    - \c created: the date/time the class was created
    - \c modified: the date/time the class was last modified
*/

/** @REST /v3/system/metadata/rlookupclass/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up all versions of a class from the class name

    @par Return Value
    @ref nothing if the arguments do not match a cached class or a hash where
    the keys are version strings and the values are the corresponding class IDs
    and the following two special keys:
    - \c lvcreated: the creation date/time of the latest version of the class
    - \c lastversion: the version string of the latest version

    @note The latest version of the class is determined by the creation time of
    the class and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/rlookupclass/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the classid of a particular class from the name and version

    @par Return Value
    @ref nothing if the arguments do not match a known class
*/

/** @REST /v3/system/metadata/classid/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns the classid from the class name and optional version, throws an exception if no match is found

    @par Return Value
    The integer classid value

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c CLASS-ERROR: class does not exist

    @note The latest version of the class is determined by the creation
    time of the class and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/classid/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the class ID from the name and version

    @par Return Value
    The integer classid value

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c CLASS-ERROR: class does not exist
*/

/** @REST /v3/system/metadata/lookupevent/{eid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up event information from the workflow_event_typeid

    @par Return Value
    @ref nothing if the id does not match any cached event, otherwise a hash with the following keys:
    - \c name: the name of the event
    - \c desc: the description of the event
*/

/** @REST /v3/system/metadata/rlookupevent/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the event id(s) from the name, optional version (without version returns all versions)

    @par Return Value
    @ref nothing if the event name does not match any cached event, otherwise a hash with the following keys:
    - \c workflow_event_typeid: the id of the event
    - \c desc: the description of the event
*/

/** @REST /v3/system/metadata/lookupservice/{serviceid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up service information from the serviceid

    @par Return Value
    @ref nothing if the serviceid does not correspond to a cached service, otherwise a hash with the following keys:
    - \c type: either \c "system" or \c "user"
    - \c name: the name of the service
    - \c version: the version of the service
    - \c patch: the patch string for the service
    - \c description: the description of the service
    - \c created: the creation date/time of the service
    - \c modified: the date/time the service was last modified
    - \c autostart: boolean value for autostart status
    - \c manual_autostart: boolean value for the manual_autostart flag
*/

/** @REST /v3/system/metadata/lookupserviceinfo/{type}/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up service information from the type and name

    @par Return Value
    @ref nothing if the service does not correspond to a cached service, otherwise a hash with the following keys:
    - \c type: either \c "system" or \c "user"
    - \c name: the name of the service
    - \c version: the version of the service
    - \c patch: the patch string for the service
    - \c description: the description of the service
    - \c created: the creation date/time of the service
    - \c modified: the date/time the service was last modified
    - \c autostart: boolean value for autostart status
    - \c manual_autostart: boolean value for the manual_autostart flag
*/

/** @REST /v3/system/metadata/rlookupservice/{type}/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up all versions of a service

    @par Return Value
    @ref nothing if the arguments do not match a cached service or a hash where
    the keys are version strings and the values are the corresponding service IDs
    and the following two special keys:
    - \c lvcreated: the creation date/time of the latest version of the service
    - \c lastversion: the version string of the latest version

    @note The latest version of the service is determined by the creation time of
    the service and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/rlookupservice/{type}/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
   @par Description
    Looks up the serviceid from the type, name, and version

    @par Return Value
    @ref nothing if the arguments do not match or the serviceid for the latest
    version of the service
*/

/** @REST /v3/system/metadata/serviceid/{type}/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the last service id(s) from the type, name, optional version

    @par Return Value
    The integer serviceid of the latest version of the given service

    @note The latest version of the service is determined by the creation time of
    the service and not by a logical version string comparison

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c SERVICE-ERROR: service does not exist
*/

/** @REST /v3/system/metadata/serviceid/{type}/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the last service id(s) from the type, name, optional version

    @par Return Value
    The integer serviceid value

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c SERVICE-ERROR: service does not exist
*/

/** @REST /v3/system/metadata/lookupjob/{jid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up job information from the jobid

    @par Return Value
    @ref nothing if the jobid does not match any cached job, otherwise a hash with the following keys:
    - \c jobid: the job id (always same as the argument)
    - \c name: the name of the job
    - \c version: the version of the job
    - \c description: the description of the job
    - \c active: a boolean flag indicating if the job is active or not; active jobs will be running unless they are a member of a disabled group
    - \c created: the date/time the job was created
    - \c modified: the date/time the job was last modified
*/

/** @REST /v3/system/metadata/rlookupjob/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the job information from the name

    @par Return Value
    @ref nothing if the arguments do not match a cached job or a hash of job information
    with the following keys:
    - \c jobid: the job id
    - \c name: the name of the job (always same as the argument)
    - \c version: the version of the job
    - \c description: the description of the job
    - \c active: a boolean flag indicating if the job is active or not; active jobs will be running unless they are a
      member of a disabled group
    - \c created: the date/time the job was created
    - \c modified: the date/time the job was last modified
*/

/** @REST /v3/system/metadata/jobid/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns the job ID from the job name, throws an exception if no match is found

    @par Return Value
    The integer job ID value

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c JOB-ERROR: job does not exist

    @note The latest version of the job is determined by the creation
    time of the job and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/jobid/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the job ID from the name and version

    @par Return Value
    The integer jobid value

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c JOB-ERROR: job does not exist
*/

/** @REST /v3/system/metadata/jobname/{jobid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the job name from the jobid, throws an exception if the ID is not recognized

    @par Return Value
    The name of the job

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c JOB-ERROR: job does not exist
*/

/** @REST /v3/system/metadata/lookupmapper/{mid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up mapper information from the mapperid

    @par Return Value
    @ref nothing if the mapperid does not match any cached mapper, otherwise a hash with the following keys:
    - \c name: the name of the mapper
    - \c version: the version of the mapper
    - \c patch: the patch string for the mapper
    - \c description: the description of the mapper
    - \c author: the author of the mapper
    - \c type: the type or class of the mapper
    - \c fields: the source of the mapper field description hash
    - \c options: the mapper's option hash
    - \c created: the date/time the mapper was created
    - \c modified: the date/time the mapper was last modified
*/

/** @REST /v3/system/metadata/rlookupmapper/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up all versions of a mapper from the mapper name

    @par Return Value
    @ref nothing if the arguments do not match a cached mapper or a hash where the keys are version strings and the
    values are the corresponding mapper IDs
*/

/** @REST /v3/system/metadata/rlookupmapper/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the mapperid of a particular mapper from the name and version

    @par Return Value
    @ref nothing if the arguments do not match or the mapperid for the requested version of the mapper
*/

/** @REST /v3/system/metadata/mapperid/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the latest mapper ID from the name

    @par Return Value
    The mapperid from the mapper name and version

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c MAPPER-ERROR: mapper does not exist

    @note The latest version of the mapper is determined by the creation
    time of the mapper and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/mapperid/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the mapper ID from the name and version

    @par Return Value
    The mapperid from the mapper name and version

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c MAPPER-ERROR: mapper does not exist
*/

/** @REST /v3/system/metadata/lookupvmap/{mid}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up value map information from the value map id

    @par Return Value
    @ref nothing if the value map id does not match any cached value map, otherwise a hash with the following keys:
    - \c name: the name of the value map
    - \c version: the version of the value map
    - \c patch: the patch string for the value map
    - \c description: the description of the value map
    - \c author: the author of the value map
    - \c type: the type or class of the value map
    - \c created: the date/time the value map was created
    - \c modified: the date/time the value map was last modified
*/

/** @REST /v3/system/metadata/rlookupvmap/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up all versions of a value map from the value map name

    @par Return Value
    @ref nothing if the arguments do not match a cached value map or a hash where the keys are version strings and the
    values are the corresponding value map IDs
*/

/** @REST /v3/system/metadata/vmapid/{name}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the latest value map ID from the name

    @par Return Value
    The value map ID from the value map name

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c VALUE-MAP-ERROR: value map does not exist

    @note The latest version of the value map is determined by the creation
    time of the value map and not by a logical version string comparison
*/

/** @REST /v3/system/metadata/vmapid/{name}/{version}

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Looks up the value map ID from the name and version

    @par Return Value
    The value map ID from the value map name and version

    @par Errors
    - <tt><b>409 Conflict</b></tt>: \c VALUE-MAP-ERROR: value map does not exist
*/

/** @REST /v3/system/metadata/workflowlist

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of integers of known workflow ids
*/

/** @REST /v3/system/metadata/servicelist

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of integers of known service ids
*/

/** @REST /v3/system/metadata/joblist

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of integers of known job ids
*/

/** @REST /v3/system/metadata/getworkflowlist

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of cached workflow information enhanced with step and function information from the cache

    @par Arguments
    This API takes the following arguments:
    - \c with_deprecated (bool): include deprecated workflows in return list (default: do not include)

    @note This method is subject to RBAC access filtering
*/

/** @REST /v3/system/metadata/pmap

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Return a list of process hashes
*/

/** @REST /v3/system/metadata/getConfigItemValues

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Return configuration item value information
*/

/** @REST /v3/system/metadata/pgmlist

    REST metadata URI path
*/
/** @REST GET
    @par Description
    Returns a list of debuggable interfaces (type, interface name, version, pgm_name, remote process)
*/

class MetadataLookupsRestClassV3 inherits QorusRestClass {
    private {
        # the original config hash, one of MetadataRestClassV3::SUBCLASSES_LOOKUPS
        hash m_cfg;
        # name of the path token. Eg.:
        # system/metadata/<m_name> - as a API name
        # system/metadata/rlookupmapper/{m_name} - as a mapper name
        # system/metadata/rlookupmapper/my-mapper/{m_name} - as a version
        string m_name;
        # buffer of arguments including parent's args.
        # It's just used in the latest child real get() call
        list m_args;
    }

    # params:
    #   name - a name of the current API's position
    #   cfg - MetadataRestClassV3::SUBCLASSES_LOOKUPS member
    #   parent_args - previous arguments. NOTHING in the 1st level instance
    constructor(string name, hash cfg, *list parent_args) {
        m_name = name;
        m_cfg = cfg;
        m_args = parent_args ?? list();
    }

    string name() {
        return m_name;
    }

    # Create new child in case it's not a latest token in the path
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        push m_args, arg;

        hash new_cfg = m_cfg;
        new_cfg.args_progress++;

        if (m_cfg.args_progress < m_cfg.max_args_count) {
            return new MetadataLookupsRestClassV3(arg, new_cfg, m_args);
        }
    }

    # the final child will return the data at the end
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        if ((m_args.size() == 0 && m_cfg.args_required != 0)
            || m_args.size() < m_cfg.args_required
            ) {
            throw "SYSTEM-METADATA-API-ERROR",
                  sprintf("No required arguments for %s call are given. Required: %d, given: %d",
                          m_cfg.method, m_cfg.args_required, m_args.size());
        }

        return RestHandler::makeResponse(200, call_object_method_args(Qorus.qmm, m_cfg.method, m_args));
    }
} # MetadataLookupsRestClassV3

/** @REST /v3/system/metadata (/v2/system/metadata)

    This REST URI path provides actions and information
    related to the system metadata cache.

    - Metadata getters: @ref rest_api_latest_system_metadata__lookup_
    - Metadata reloaders: @ref rest_api_latest_system_metadata_reload

    @since Qorus 4.0
*/
class MetadataRestClassV3 inherits MetadataRestClass {
    private {
        # key = name of the lookup call/path
        # values:
        #   - method = Qore.qmn method name used in call_object_method()
        #   - max_args_count = maximum arguments allowed for this method
        #   - args_required = count of mandatory arguments
        #   - args_progress - later added to keep "a pointer" to current argument position
        const SUBCLASSES_LOOKUPS = {
            "lookupstep": { "method": "lookupStep", "max_args_count": 2, "args_required": 1},
            "rlookupstep": {"method": "rLookupStep", "max_args_count": 2, "args_required": 1},
            "stepid": {"method": "stepId", "max_args_count": 2, "args_required": 1},
            "lookupfunc": {"method": "lookupFunc", "max_args_count": 1, "args_required": 1},
            "rlookupfunc": {"method": "rLookupFunc", "max_args_count": 2, "args_required": 1},
            "functionid": {"method": "functionId", "max_args_count": 2, "args_required": 1},
            "lookupqueue": {"method": "lookupQueue", "max_args_count": 1, "args_required": 1},
            "rlookupqueue": {"method": "rLookupQueue", "max_args_count": 1, "args_required": 1},
            "lookupsla": {"method": "lookupSla", "max_args_count": 1, "args_required": 1},
            "rlookupsla": {"method": "rLookupSla", "max_args_count": 1, "args_required": 1},
            "lookupworkflow": {"method": "lookupWorkflow", "max_args_count": 2, "args_required": 1},
            "rlookupworkflow": {"method": "rLookupWorkflow", "max_args_count": 2, "args_required": 1},
            "workflowid": {"method": "getWorkflowId", "max_args_count": 2, "args_required": 1},
            "lookupconstant": {"method": "lookupConstant", "max_args_count": 1, "args_required": 1},
            "rlookupconstant": {"method": "rLookupConstant", "max_args_count": 2, "args_required": 1},
            "constantid": {"method": "constantId", "max_args_count": 2, "args_required": 1},
            "lookupclass": {"method": "lookupClass", "max_args_count": 1, "args_required": 1},
            "rlookupclass": {"method": "rLookupClass", "max_args_count": 2, "args_required": 1},
            "classid": {"method": "classId", "max_args_count": 2, "args_required": 1},
            "lookupevent": {"method": "lookupEvent", "max_args_count": 1, "args_required": 1},
            "rlookupevent": {"method": "rLookupEvent", "max_args_count": 1, "args_required": 1},
            "lookupservice": {"method": "lookupService", "max_args_count": 1, "args_required": 1},
            "lookupserviceinfo": {"method": "lookupServiceInfo", "max_args_count": 2, "args_required": 2},
            "rlookupservice": {"method": "rLookupService", "max_args_count": 3, "args_required": 2},
            "serviceid": {"method": "getServiceId", "max_args_count": 3, "args_required": 2},
            "lookupjob": {"method": "lookupJob", "max_args_count": 1, "args_required": 1},
            "rlookupjob": {"method": "rLookupJob", "max_args_count": 1, "args_required": 1},
            "jobid": {"method": "getJobId", "max_args_count": 1, "args_required": 1},
            "jobname": {"method": "getJobName", "max_args_count": 1, "args_required": 1},
            "lookupmapper": {"method": "lookupMapper", "max_args_count": 1, "args_required": 1},
            "rlookupmapper": {"method": "rLookupMapper", "max_args_count": 2, "args_required": 1},
            "mapperid": {"method": "mapperId", "max_args_count": 2, "args_required": 2},
            "lookupvmap": {"method": "lookupVMap", "max_args_count": 1, "args_required": 1},
            "rlookupvmap": {"method": "rLookupVMap", "max_args_count": 1, "args_required": 1},
            "vmapid": {"method": "vmapId", "max_args_count": 1, "args_required": 1},
            "workflowlist": {"method": "getWorkflowIds", "max_args_count": 0, "args_required": 0},
            "servicelist": {"method": "getServiceIds", "max_args_count": 0, "args_required": 0},
            "joblist": {"method": "getJobIds", "max_args_count": 0, "args_required": 0},
            "getworkflowlist": {"method": "getWorkflowList", "max_args_count": 1, "args_required": 0},
            "pmap": {"method": "getProcessMap", "max_args_count": 0, "args_required": 0},
            "getConfigItemValues": {"method": "getConfigItemValues", "max_args_count": 0, "args_required": 0},
            "pgmlist": {"method": "getProgramList", "max_args_count": 0, "args_required": 0},
            "lookupPipeline": {"method": "lookupPipeline", "max_args_count": 1, "args_required": 1},
            "getPipelines": {"method": "getPipelines", "max_args_count": 0, "args_required": 0},
            "lookupFsm": {"method": "lookupFsm", "max_args_count": 1, "args_required": 1},
            "getFsmMap": {"method": "getFsmMap", "max_args_count": 0, "args_required": 0},
        };
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        QDBG_LOG("MetadataRestClassV3::subClass(%y)", arg);
        switch (arg) {
            case "maplist":
                # only return attributes if we have a GET request
                if (cx.hdr.method == "GET") {
                    # just return keys of Caches = list of maps
                    return new AttributeRestClass(Caches.keys());
                }
                break;
            case "lookupsteps": {
                # only return attributes if we have a GET request
                if (cx.hdr.method == "GET") {
                    # lookupsteps require additional parameter(s) so it
                    # cannot be handled by plain AttributeRestClass out of the box.
                    # params are: list of ids and an optional verbose
                    *softlist<softint> ids;
                    if (ah.ids.typeCode() == NT_STRING) {
                        ids = ah.ids.split(",");
                    } else if (ah.ids.lsize()) {
                        ids = ah.ids;
                    }
                    bool verbose = boolean(ah.verbose);
                    if (!ids) {
                        throw "SYSTEM-METADATA-API-ERROR",
                            sprintf("Missing 'ids' argument given; args provided: %y", ah);
                    }
                    return new AttributeRestClass(Qorus.qmm.lookupStep(ids, verbose));
                }
                break;
            }
            case "reload": {
                # reload is a little bit tricky here.
                # REST API v1 uses dedicated class for it with action?reload=...
                # but we have to expand it here, in v3.
                # So the ReloadRestClassV3 handles old-style calls and much more:
                # edicated reload/<foo> subpaths
                return new ReloadRestClassV3();
            }
        }

        *hash sub_method = SUBCLASSES_LOOKUPS{arg};
        if (sub_method) {
            # args_progress is set to 0 to point to the
            # 0 index of the "current argument position"
            # MetadataLookupsRestClassV3 is using sort of
            # recursion to handle the full sub-path(s)
            sub_method.args_progress = 0;
            return new MetadataLookupsRestClassV3(arg, sub_method);
        }

        return MetadataRestClass::subClassImpl(arg, cx, ah);
    }

} # class MetadataRestClassV3

/** @REST /v3/system/config/{name}

    This REST URI path provides actions and information related to a specific Qorus global configuration item.
    Prefix can be passed within the config item name or as following: /v3/system/config/{name}?prefix={prefix}.
*/
class GlobalConfigItemRestClassV3 inherits QorusRestClass {
    private {
        hash<auto> item;

        string name_with_prefix;
    }

    constructor(hash<auto> item) {
        self.item = item;
        name_with_prefix = item.prefix + item.name;
    }

    string name() {
        return item.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (item.hasKey(arg)) {
                return new AttributeRestClass(item{arg});
            }
        }
    }

    /** @REST GET
        @par Description
        Returns a hash for the current configuration item value on the global level

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "value": the value of the configuration item
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, item);
    }

    /** @REST GET action=yaml
        @par Description
        Returns a hash for the current configuration item value as a YAML-serialized string on the global level

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "value": (YAML-serialized string) the value of the configuration item
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<HttpHandlerResponseInfo> getYaml(hash<auto> cx, *hash<auto> ah) {
        auto new_item = QorusRestClass::serializeValuesToYaml(item, ("value",));
        if (exists new_item.allowed_values) {
            new_item.allowed_values = serializeValuesInListToYaml(new_item.allowed_values);
        }
        return RestHandler::makeResponse(200, new_item);
    }

    /** @REST PUT

        @par Description
        Sets the value for the given configuration item on the global level

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value (required): the value of the configuration item; must be compatible with the item's declared type

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value: the new value
        - \c info: info about the service configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
        - <tt><b>409 Conflict</b></tt>: \c CONFIG-ITEM-ERROR: this exception is thrown if an invalid type is given for
          the given configuration item
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("value")) {
            return RestHandler::makeResponse(400, "no key \"value\" argument sent in request");
        }

        hash changed = Qorus.qmm.setConfigItemValueOnGlobalLevel(name_with_prefix, ah.value);
        changed.info = sprintf("%y configuration item value has been changed on the global level", name_with_prefix);
        return RestHandler::makeResponse(200, changed);
    }

    /** @REST PUT action=yaml

        @par Description
        Sets the value for the given global configuration item using a YAML-serialized string

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value (YAML-serialized string): the value of the configuration item

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value (YAML-serialized string): the new value
        - \c info: info about the service configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value key
    */
    hash<HttpHandlerResponseInfo> putYaml(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error;
        ah = QorusRestClass::deserializeYamlValues(ah, "value", \error);
        if (exists error) {
            return error;
        }

        hash<HttpHandlerResponseInfo> result = put(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }

    /** @REST DELETE

        @par Description
        Permanently deletes the current value for the configuration item on the global level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value: deleted value
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        hash result;
        result.value = Qorus.qmm.deleteConfigItemValueOnGlobalLevel(name_with_prefix, \result.deleted);
        result.info = sprintf("%y configuration item value on the global level has been deleted", name_with_prefix);
        return RestHandler::makeResponse(200, result);
    }

    /** @REST DELETE action=yaml

        @par Description
        Permanently deletes the current value for the configuration item on the global level

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value (YAML-serialized string): deleted value
    */
    hash<HttpHandlerResponseInfo> delYaml(hash<auto> cx, *hash<auto> ah) {
        hash<HttpHandlerResponseInfo> result = del(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }
}

/** @REST /v3/system/config

    This REST URI path provides actions and information related to Qorus configuration item values on the global level
*/
class GlobalConfigRestClassV3 inherits QorusRestClass {
    string name() {
        return "config";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        string name_with_prefix = ah.prefix + arg;
        *hash<auto> item = Qorus.qmm.findConfigItemValueOnGlobalLevel(name_with_prefix);
        if (item) {
            # get actual item name
            if (item.prefix && name_with_prefix.equalPartial(item.prefix)) {
                arg = name_with_prefix[item.prefix.length()..];
            }
            return new GlobalConfigItemRestClassV3(item + {"name": arg});
        }
    }

    /** @REST GET
        @par Description
        Returns a list of all configuration item values on the global level

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "value": the value of the configuration item
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "allowed_values": the list of allowed values for the configuration item if defined
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, Qorus.qmm.findAllConfigItemValuesOnGlobalLevel());
    }

    /** @REST GET action=yaml
        @par Description
        Returns a list of all configuration item values on the global level

        @par Return Value
        This API returns a hash with the following keys:
        - \c "name": the name of the configuration item
        - \c "prefix": the prefix of the configuration item
        - \c "type": the type of the configuration item
        - \c "value": (YAML-serialized string) the value of the configuration item
        - \c "is_set": @ref True if the value is set otherwise @ref False
        - \c "allowed_values": the list of allowed values for the configuration item if defined (each element is a YAML-serialized string)
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<HttpHandlerResponseInfo> getYaml(hash<auto> cx, *hash<auto> ah) {
        list<hash<auto>> config_items = Qorus.qmm.findAllConfigItemValuesOnGlobalLevel();

        foreach auto config in (\config_items) {
            config = QorusRestClass::serializeValuesToYaml(config, ("value",));
            if (exists config.allowed_values) {
                config.allowed_values = serializeValuesInListToYaml(config.allowed_values);
            }
        }
        return RestHandler::makeResponse(200, config_items);
    }

    /** @REST POST

        @par Description
        Creates the value for the given configuration items

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c name: the name of the configuration item
        - \c prefix: the prefix of the configuration item (optional)
        - \c value: the value of the configuration item; must be compatible with the item's declared type

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value: the new value
        - \c info: info about the workflow configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value or \c name keys
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("value") || !ah.hasKey("name")) {
            return RestHandler::makeResponse(400, "no key \"value\" or \"name\" argument sent in request");
        }

        string name_with_prefix = ah.prefix + ah.name;
        hash changed = Qorus.qmm.setConfigItemValueOnGlobalLevel(name_with_prefix, ah.value, True);
        changed.info = sprintf("%y configuration item value has been changed on the global level", name_with_prefix);
        return RestHandler::makeResponse(200, changed);
    }

    /** @REST POST action=yaml

        @par Description
        Sets the value for the given configuration items using a YAML-serialized string

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c name: the name of the configuration item
        - \c prefix: the prefix of the configuration item (optional)
        - \c value: (YAML-serialized string) the value of the configuration item

        @par Return Value
        This API returns a hash with the following keys:
        - \c inserted: @ref True or @ref False (returned if the value has been inserted)
        - \c updated: @ref True or @ref False (returned if the value has been updated)
        - \c value (YAML-serialized string): the new value
        - \c info: info about the workflow configuration item change action

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c value or \c name keys
    */
    hash<HttpHandlerResponseInfo> postYaml(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error;
        ah = QorusRestClass::deserializeYamlValues(ah, "value", \error);
        if (exists error) {
            return error;
        }

        hash<HttpHandlerResponseInfo> result = post(cx, ah);
        result.body = QorusRestClass::serializeValuesToYaml(result.body, "value");
        return result;
    }

    /** @REST PUT

        @par Description
        Imports the given config item values.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c config-items: list of hashes describing config item values, each hash has the following keys:
            - \c name: name of the config item
            - \c prefix: prefix of the config item (optional)
            - \c interface-type: interface type (job, service, step, workflow, global)
            - \c interface-name: name of the interface (required if interface type is not global)
            - \c interface-version: version of the interface (required if interface type is not global)
            - \c value: value of the config item

        @par Return Value
        This API returns a hash with the following keys:
        - \c results: list of hashes, where each hash has the following keys:
            - \c updated: @ref True or @ref False (in case value was set before)
            - \c inserted: @ref True or @ref False (in case value was not set before)
            - \c value: new value

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c config-items key
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("config-items")) {
            return RestHandler::make400("no key \"config-items\" argument sent in request");
        }

        return RestHandler::makeResponse(200, Qorus.qmm.importConfigItemValues(ah{"config-items"}));
    }

    /** @REST PUT action=yaml

        @par Description
        Imports the given config item values from YAML-serialized strings.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c config-items: list of hashes describing config item values, each hash has the following keys:
            - \c name: name of the config item
            - \c prefix: prefix of the config item (optional)
            - \c interface-type: interface type (job, service, step, workflow, global)
            - \c interface-name: name of the interface (required if interface type is not global)
            - \c interface-version: version of the interface (required if interface type is not global)
            - \c value: value of the config item (YAML-serialized string)

        @par Return Value
        This API returns a hash with the following keys:
        - \c results: list of hashes, where each hash has the following keys:
            - \c updated: @ref True or @ref False (in case value was set before)
            - \c inserted: @ref True or @ref False (in case value was not set before)
            - \c value: new value

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c config-items key
    */
    hash<HttpHandlerResponseInfo> putYaml(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("config-items")) {
            return RestHandler::make400("no key \"config-items\" argument sent in request");
        }

        list config_items;
        *hash<HttpHandlerResponseInfo> error;
        foreach hash config_item in (ah{"config-items"}) {
            config_item = QorusRestClass::deserializeYamlValues(config_item, "value", \error);
            if (exists error) {
                return error;
            }
            config_items += config_item;
        }

        QDBG_LOG("GlobalConfigRestClassV3::putYaml: config_items: %y\n", config_items);

        list results = Qorus.qmm.importConfigItemValues(config_items);
        foreach auto result in (\results) {
            result = QorusRestClass::serializeValuesToYaml(result, "value");
        }

        return RestHandler::makeResponse(200, results);
    }

    /** @REST DELETE

        @par Description
        Deletes values of the given config items.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c config-items: list of hashes describing config item values, each hash has the following keys:
            - \c name: name of the config item
            - \c prefix: prefix of the config item (optional)
            - \c level: level of the config item value

        @par Return Value
        This API returns a hash with the following keys:
        - \c results: list of hashes, where each hash has the following keys:
            - \c deleted: @ref True in case value has been deleted otherwise @ref False
            - \c value: deleted value

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c config-items key
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("config-items")) {
            return RestHandler::make400("no key \"config-items\" argument sent in request");
        }
        return RestHandler::makeResponse(200, Qorus.qmm.deleteConfigItemValues(ah{"config-items"}));
    }
}

/** @REST /v3/system/processes/{id}

    This REST URI path provides actions and information related to a specific system process
*/
class ProcessRestClassV3 inherits QorusRestClass {
    public {
        hash<auto> process_hash;

        const RemoteProcessKillTimeout = 20s;
    }

    constructor(hash<auto> process_hash) {
        self.process_hash = process_hash;
    }

    string name () {
        return process_hash.id;
    }

    /** @REST POST action=kill

        @par Description
        Kills a cluster process

        @par Return Value
        This API returns a hash with the following keys:
        - status: \c "OK", \c "ERR" if not
        - code: the return code of the \c kill() command: 0 if successful, non-zero if not
    */
    hash<HttpHandlerResponseInfo> postKill(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        return staticKillProcess(process_hash, cx, ah);
    }

    /** @REST GET

        @par Description
        Returns a hash of information about a specific Qorus cluster process

        @par Return Value
        This API returns a @ref rest_process_info_hash "process info hashes" for the current process.
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, process_hash);
    }

    # kills a process; logging must be performed and permissions must be checked before this call
    static hash<HttpHandlerResponseInfo> staticKillProcess(hash<auto> process_hash, hash<auto> cx, *hash<auto> ah) {
        if (process_hash.node != Qorus.getNode()) {
            QDBG_LOG("ProcessRestClassV3::staticKillProcess() process_hash: %y", process_hash);
            # issue #3812: wait for the process to be killed
            Counter cnt(1);
            Qorus.setAbortNotification(process_hash.id, cnt);
            on_error Qorus.removeAbortNotification(process_hash.id, cnt);
            # connections can be reused, but the identity must be unique
            string our_id = sprintf("ProcessRestClassV3::staticKillProcess-%s", gettid());
            ZSocketDealer sock(Qorus.getContext());
            sock.setIdentity(our_id);
            Qorus.getNetworkKeyHelper().setClient(sock);
            sock.connect(process_hash.urls[0]);
            sock.send("1", CPC_KILL_PROC, qorus_cluster_serialize({"kill_self": True}));
            # issue #3812: wait 20s for the process abort notification
            if (cnt.waitForZero(RemoteProcessKillTimeout)) {
                Qorus.removeAbortNotification(process_hash.id, cnt);
                return RestHandler::makeResponse(200, {
                    "status": "ERR",
                    "termination": "message",
                    "code": -1,
                    "pid": process_hash.pid,
                    "error": sprintf("termination message sent to remote process %y, but no abort notification "
                        "received in the timeout window (%y)", process_hash.id, RemoteProcessKillTimeout),
                });
            }

            return RestHandler::makeResponse(200, {
                "status": "OK",
                "termination": "message",
                "code": 0,
                "pid": process_hash.pid,
            });
        }

        int rc = kill(process_hash.pid, SIGKILL);
        return RestHandler::makeResponse(200, {
            "status": rc ? "ERR" : "OK",
            "termination": "signal",
            "code": rc,
            "pid": process_hash.pid,
        } + (rc ? {"error": strerror()} : NOTHING));
    }
}

/** @REST /v3/system/processes

    This REST URI path provides actions and information related to system processes
*/
class ProcessesRestClassV3 inherits QorusRestClass {
    string name() {
        return "processes";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> proc_info = staticGetProcessInfo(){arg};
        return proc_info ? new ProcessRestClassV3(proc_info) : NOTHING;
    }

    /** @REST GET

        @par Description
        Returns a hash of information about currently-running Qorus cluster processes

        @par Return Value
        This API returns a hash keyed by cluster process name where values are
        @ref rest_process_info_hash "process info hashes".
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, staticGetProcessInfo());
    }

    static hash<auto> staticGetProcessInfo() {
        return Qorus.getMaster().getInfo(10s).processes;
    }
}

/** @REST /v3/system/props (/v2/system/props)

    This REST URI path provides actions and information related to a @ref sysprops "system properties".
*/
class SystemPropertiesRestClassV3 inherits SystemPropertiesRestClassV2 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = Qorus.props.get(arg);
        # allow to use real RESTful calls without ?action=
        if (!h.val() &&
            (  arg == "replaceAll"
             || arg == "export"
             || arg == "import"
             || arg == "updateMany"
             || arg == "reload"
             || arg == "set"
            )
        ) {
            return NOTHING;
        }

        return new SystemPropertyDomainRestClass(arg, h);
    }
}

/** @REST /v3/system/authlabels

    This REST URI path provides information about authentication labels
*/
class AuthLabelsRestClassV3 inherits QorusRestClass {
    string name() {
        return "authlabels";
    }

    /** @REST GET

        @par Description
        Returns a hash of authentication labels existing in Qorus

        @par Return Value
        This API returns a hash with the following keys:
        - \c authlabelid: (string) key for the hash value assigned a value of a list of hashes with the following keys:
            - \c authlabelid: (string) unique identifier of the label
            - \c serviceid: (int) the service ID again
            - \c value: (string) the value of the authentication label
            - \c servicename: (string) the name of the service
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        hash<auto> labels = Qorus.qmm.getAuthLabelMap() ?? {};
        hash<auto> rv;
        foreach hash<auto> i in (labels.pairIterator()) {
            rv{i.key} = map $1, i.value.iterator();
        }
        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v3/system (/v2/system)

    This REST URI path provides actions and information for system functionality
*/
class SystemRestClassV3 inherits HelpSystemLoggerRestClass, HelpLoggerAppendersRestClass, SystemRestClassV2 {
    public {
        # hash of default appender params; initialized on demand
        static hash default_appender_params;

        const SubClasses = SystemRestClassV2::SubClasses + {
            "metadata": "MetadataRestClassV3",
            "userhttp": "SystemUserHttpRestClassV3",
            "config": "GlobalConfigRestClassV3",
            "props": "SystemPropertiesRestClassV3",
            "authlabels": "AuthLabelsRestClassV3",
        };

        const SysLogClasses = map {$1.log_path: True}, SystemLoggerInfo.iterator();

        const SysLogInternalName = map {$1.log_path: $1.logger}, SystemLoggerInfo.iterator(), $1.log_path != $1.logger;

        const GrafanaPanelIds = {
            "node_process_count": 4,
            "node_memory": 6,
            "node_cpu_load": 8,
            "number_of_services": 10,
            "number_of_workflows": 12,
            "number_of_jobs": 14,
            "workflow_overall_statuses": 18,
            "sla_stats": 20,
            "workflow_disposition": 22,
            "workflow_instances_statuses": 24
        };
    }

    constructor() : HelpSystemLoggerRestClass("system", "system"), HelpLoggerAppendersRestClass("system", "system") {
        addClass(new ProcessesRestClassV3());
    }

    static hash<auto> staticGetClusterInfo() {
        # get cluster info from master
        QorusMasterClient master = Qorus.getMaster();

        # get master info with timeout
        return master.getInfo(10s){"cluster_info", "processes"};
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *string cls = doGetSubClasses(){arg};
        if (cls) {
            return create_object(cls);
        }
        if (SysLogClasses{arg}) {
            return new AbstractSystemLoggerRestClass(arg, SysLogInternalName{arg});
        }
        if (arg == "loggers") {
            return new SystemLoggersRestClass(arg);
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            *hash<auto> h = internGetInfo(cx);
            if (h.hasKey(arg)) {
                return new AttributeRestClass(h{arg});
            }
        }
    }

    private static synchronized internGetDefaultAppenderParams() {
        if (default_appender_params) {
            return;
        }

        # build map of default appender filename values from system options
        hash fn_map = {
            "workflow": "$path" + Qorus.options.get("wf-logfile-template"),
            "service": "$path" + Qorus.options.get("svc-logfile-template"),
            "job": "$path" + Qorus.options.get("job-logfile-template"),
            "system": "$path" + Qorus.options.get("logfile-template"),
        };

        # get max-log-files option
        int rotationCount = Qorus.options.get("max-log-files");

        default_appender_params = DEFAULT_APPENDER_PARAMS;
        foreach hash<auto> i in (default_appender_params.pairIterator()) {
            if (i.value.hasKey("filename")) {
                default_appender_params{i.key}.filename = fn_map;
            }
            if (i.value.hasKey("rotationCount")) {
                default_appender_params{i.key}.rotationCount = rotationCount;
            }
        }
    }

    hash<auto> internGetInfo(hash<auto> cx) {
        if (!default_appender_params) {
            internGetDefaultAppenderParams();
        }

        hash<string, int> ah = Qorus.alerts.getOngoingAlertSummary();

        return SystemRestClassV2::internGetInfo(cx) + {
            "api_version": "v3",
        } + staticGetClusterInfo() + {
            "workflow_total": Qorus.qmm.getWorkflowIds().lsize(),
            "workflow_alerts": ah.WORKFLOW ?? 0,
            "service_total": Qorus.qmm.getServiceIds().lsize(),
            "service_alerts": ah.SERVICE ?? 0,
            "job_total": Qorus.qmm.getJobIds().lsize(),
            "job_alerts": ah.JOB ?? 0,
            "remote_total": Qorus.remotemonitor.size(),
            "remote_alerts": ah{OMQ::AlertTypeRemote} ?? 0,
            "user_total": Qorus.connections.size(),
            "user_alerts": ah{OMQ::AlertTypeUser} ?? 0,
            "datasource_total": Qorus.dsmanager.size(),
            "datasource_alerts": ah{OMQ::AlertTypeDatasource} ?? 0,
            "order_stats": Qorus.orderStats.getCurrentEvents(),
            "loggerParams": {
                "logger_levels": AVAILABLE_LEVELS_STR,
                "appenders_types": AVAILABLE_APPENDER_TYPES,
                "appenders_fields": AVAILABLE_APPENDER_FIELDS,
                "default_logger_params": DEFAULT_LOGGER_PARAMS,
                "default_appender_params": default_appender_params,
                "configurable_systems": map (
                    "name": $1.key,
                    "logger": $1.value.logger,
                    "uri_path": $1.value.uri_path,
                    "description": $1.value.description,
                ), SystemLoggerInfo.pairIterator(),
            },
            "auth_label_values": (
                "permissive",
                "default",
                "default-basic",
            ),
            "grafana_panel_ids": GrafanaPanelIds,
            "limits": {
                "nofile": QorusSharedApi::getNofile(),
                "nproc": QorusSharedApi::getNproc(),
            },
        };
    }

    /** @REST GET action=defaultLogger

        @par Description
        Returns system default logger info

        @par Return Value
        This API returns 200 OK and hash with the following keys:
        - \c loggerid: (int) logger id
        - \c params: (hash) logger params
            - \c level: (hash) @ref Logger::LoggerLevel "LoggerLevel"
                - \c "key": logger level string representation
                - \c "value": logger level int representation
            - \c name: (string) logger name
            - \c additivity: (bool) logger additivity
        - \c interface_table_name: (string) system (audit, alert, monitoring, http, qorus-core, qorus-master, qdsp) type.
     */
    hash<HttpHandlerResponseInfo> getDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpSystemLoggerRestClass::getImpl(cx, ah);
    }

    /** @REST DELETE action=defaultLogger

        @par Description
        Delete system logger

        @par Return Value
        If success 200 OK, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<HttpHandlerResponseInfo> delDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpSystemLoggerRestClass::delImpl(cx, ah);
    }

    /** @REST POST action=defaultLogger

        @par Description
        Create system Logger

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: required; (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: (string) logger name
        - \c additivity: (bool) logger additivity (default @ref True)
        - \c cloneDefault: (bool) create logger with appenders based on default logger

        @par Return Value
        If success 200 with the logger ID created, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<HttpHandlerResponseInfo> postDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpSystemLoggerRestClass::postImpl(cx, ah);
    }

    /** @REST PUT action=defaultLogger

        @par Description
        Set system logger params

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: logger name to set
        - \c additivity: logger additivity to set

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<HttpHandlerResponseInfo> putDefaultLogger(hash<auto> cx, *hash<auto> ah) {
        return HelpSystemLoggerRestClass::putImpl(cx, ah);
    }

    /** @REST GET action=defaultLoggerAppenders

        @par Description
        Return system logger appenders

        @par Return Value
        This API returns 200 OK and list with the following hashes:
        - \c appenderId: (int) appenderId
        - \c params: (hash) possible appender parameters, might be missing if not set
            - \c name: (string) appender name
            - \c layoutPattern: (string) appender layout pattern
            - \c rotation: (int) appender layout pattern
            - \c filename: (string) appender filename
    */
    hash<HttpHandlerResponseInfo> getDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::getImpl();
    }

    /** @REST POST action=defaultLoggerAppenders

        @par Description
        Create logger appenders

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK and appender id, in case of fail one of the error codes: 400, 409 and \a string of error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<HttpHandlerResponseInfo> postDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::postImpl(cx, ah);
    }

    /** @REST DELETE action=defaultLoggerAppenders
        @par Description
        Delete logger appender with obtained id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be deleted

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<HttpHandlerResponseInfo> delDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::delImpl(cx, ah);
    }

    /** @REST PUT action=defaultLoggerAppenders
        @par Description
        Update logger appender with the given id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be update
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<HttpHandlerResponseInfo> putDefaultLoggerAppenders(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::putImpl(cx, ah);
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
          - filename (string): the path to the module on the host filesystem
          - name (string): the name of the module
          - desc (string): a short description of the module
          - version (string): the version string of the module
          - author (string): the module author's name
          - url (*string): the URL for the module
          - license (*string): the license for the module
          - reexported-modules (*list<string>): list of modules rexported by this module, if any
          - injected (bool): if this module was injected
          - reinjected (bool): if this module was reinjected
          - user (*bool): if this is a user module
          - api_major (*int): the API major version for binary modules
          - api_minor (*int): the API minor version for binary modules
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
          - schema-version (string): the full system schema version
          - schema-compatibility (string): the runtime compatible version
          - schema-load-compatibility (string): the load (oload) compatible version
        - omq_dir (string): the full path on the host to the Qorus application directory
        - cache_size (int): The number of entries in the workflow order data cache
        - shutting_down (bool): indicates if the system is shutting down or not
        - build-type (string): the build type (normally \c "Production" for public releases)
        - runtime-properties (*hash[any] UndefinedHash): any runtime properties set on the instance
        - alert-summary (hash SystemAlertInfo): summary of alerts
          - transient (int): number of current transient alerts
          - ongoing (int): number of ongoing alerts
        - debug (bool): indicates if debugging is enabled for the instance
        - debug-internals (bool): indicates if internal debugging is enabled for the instance
        - health (string): a string indicating the health status of the instance
        - ui-compatibility-version (string): a string indicating the UI compatibility for the instance
        - plugins (*list<string>): any installed plugins
        - system_log_url (string): a WebSocket URL for system log streaming
        - audit_log_url (string): a WebSocket URL for audit log streaming
        - http_log_url (string): a WebSocket URL for HTTP log streaming
        - mon_log_url (string): a WebSocket URL for connection monitor log streaming
        - alert_log_url (string): a WebSocket URL for alert log streaming
        - api_version (string): the current API version
        - cluster_info (hash[hash QorusClusterInfo] QorusClusterSetInfo): cluster info; keys are node (container) names
          - node_priv (int): the memory in use on this node in bytes
          - node_priv_str (string): the memory in use on this node
          - node_ram (int): the total RAM on the host machine in bytes
          - node_ram_str (string): the total RAM on the host machine
          - node_ram_in_use (int): the amount of RAM in use on the host machine in bytes
          - node_ram_in_use_str (string): the amount of RAM in use on the host machine
          - node_cpu_count (int): the number of CPU cores on the host machine
          - node_load_pct (float): the CPU load on the host machine
          - mem_history (list<hash UndefinedHash>): memory history list
          - process_count (int): number of processes running
          - process_history (list<hash UndefinedHash>): process history list
        - processes (hash[hash QorusProcessInfo] QorusProcessSetInfo): process info; keys are process IDs
          - id (string): unique process ID
          - node (string): the node (container) name where the process is running
          - status (int): process status code
          - status_string (string): process status string
          - urls (list<string>): list of ZeroMQ URLs for the process
          - host (string): the hostname of the node (container) where the process is running
          - pid (int): the PID in the host of the process
          - type (string): the process type
          - client_id (string): the client ID for the process
          - started (date): the date and time the process was started
          - vsz (int): current virtual process size in bytes
          - rss (int): current resident process size in bytes
          - priv (int): current private (real memory) size in bytes
          - priv_str (string): current private (real memory) size for the process
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
          - nofile (int): maximum number of open files
          - nproc (int): maximum number of procesess / threads
        - default_mapper_keys (hash[any] UndefinedHash): default mapper key info
        - pipeline_options (hash[any] UndefinedHash): pipeline option info
        - stack_size (int): thread stack size
        @ENDSCHEMA
    */

    private hash<string, string> doGetSubClasses() {
        return SubClasses;
    }
}

/** @REST /v3/services/{id_or_name}/authlabels

    This REST URI path provides actions and information for system functionality
*/
class ServiceLabelsRestClass inherits QorusRestClass {
    private {
        hash sh;
    }

    constructor(hash<auto> sh) {
        self.sh = sh;
    }

    string name() {
        return "authlabels";
    }

    /** @REST GET

        @par Description
        Gets list of authentication labels associated wth the service

        @par Return Value
        Returns hash of labels and their values
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> labels = Qorus.qmm.getAuthLabels(sh.serviceid);
        return RestHandler::makeResponse(200, labels);
    }

    /** @REST PUT

        @par Description

        Updates authentication labels associated wth the service

        @par Input Value
        Hash with label names and their values where keys are authentication labels and values have one of the
        following two values:
        - \c "default": default Qorus authentication is used
        - \c "permissive": all requests are accepted with no authentication necessary

        @par Return Value
        String "OK" representing the authentication labels were updated successfully

        @par Errors
        In case of any error, HTTP status 409 is returned and standard Qorus error hash is retuned in response body
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        Qorus.qmm.updateServiceAuthLabels(sh.serviceid, ah);
        return RestHandler::makeResponse(200, "OK");
    }
}

/** @REST /v3/classes/{id_or_name} (/v2/classes/{id_or_name})

    This REST API path provides actions and information about specific class objects
*/
    /** @REST GET

        @par Description
        Returns a hash of information about the current class object

        @par Return Value
        This API returns a @ref rest_class_hash_v3
    */


/** @REST /v3/classes (/v2/classes/)

    This REST API path provides actions and information about Qorus class objects
*/
class ClassRestClassV3 inherits ClassRestClass {
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
        *hash<auto> h = ClassRestClass::staticGetClassInfo(id, 3);
        return h ? new ClassDefinitionRestClass(h) : NOTHING;
    }
}

public namespace QorusLogger {
# extend logger level with string label
*hash sub extendLoggerLevel(*hash loggerInfo) {
    if (loggerInfo) {
        loggerInfo{"params"}{"level"} = {
            AVAILABLE_LEVELS{loggerInfo{"params"}{"level"}}: loggerInfo{"params"}{"level"},
        };
    }
    return loggerInfo;
}

class HelpSystemLoggerRestClass {
    private:internal {
        string type;
        string internal_name;
    }

    constructor(string type, string internal_name) {
        self.type = type;
        self.internal_name = internal_name;
    }

    string getType() {
        return type;
    }

    string getInternalName() {
        return internal_name;
    }

    private hash<HttpHandlerResponseInfo> getImpl(hash<auto> cx, *hash<auto> ah) {
        # strip types to reformat appenders
        *hash<auto> loggerInfo = auto_cast(Qorus.qmm.lookupLogger(internal_name));
        if (loggerInfo.interface_table_name) {
            loggerInfo.interface_table_name = loggerInfo.interface_table_name.lwr();
        }
        if (loggerInfo.params.appenders) {
            loggerInfo.params.appenders = map (
                "params": $1.value,
                "appenderid": $1.key.toInt(),
                "isDefault": loggerInfo.isDefault,
            ), loggerInfo.params.appenders.pairIterator();
        }
        return RestHandler::makeResponse(200, extendLoggerLevel(loggerInfo));
    }

    private hash<HttpHandlerResponseInfo> postImpl(hash<auto> cx, *hash<auto> ah) {
        try {
            # clone default logger with assigned to it appenders and assign it to the interface
            if (ah.hasKey("cloneDefault") && parse_boolean(ah{"cloneDefault"}) == True) {
                int loggerId = Qorus.loggerController.cloneDefault(internal_name);
                return RestHandler::makeResponse(200, loggerId);
            }

            if (!ah.hasKey("level")) {
                return RestHandler::make400("error creating logger: 'level' key is not set");
            }

            if (ah.hasKey("additivity")) {
                ah{"additivity"} = parse_boolean(ah{"additivity"});
            } else {
                ah{"additivity"} = True;
            }

            hash<auto> params = {
                "level": ah{"level"},
                "name": ah{"name"},
                "additivity": ah{"additivity"}
            };

            int loggerId = Qorus.loggerController.createLogger(params, internal_name);
            return RestHandler::makeResponse(200, loggerId);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "PARSE-TYPE-ERROR" || ex.err == "LOGGER-EXISTS" || ex.err == "BAD-REQUEST") {
                return RestHandler::make400("%s: %s", ex.err, ex.desc);
            }
            # exceptions are always returned as 409 Conflict errors
            rethrow;
        }
    }

    private hash<HttpHandlerResponseInfo> delImpl(hash<auto> cx, *hash<auto> ah) {
        try {
            Qorus.qmm.deleteLogger(internal_name);
            return RestHandler::makeResponse(200, "OK");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NO-LOGGER") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            if (ex.err == "PARSE-TYPE-ERROR") {
                return RestHandler::make400("%s: %s", ex.err, ex.desc);
            }
            rethrow;
        }
    }

    private hash<HttpHandlerResponseInfo> putImpl(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("level") && !ah.hasKey("name") && !ah.hasKey("additivity")) {
            return RestHandler::make400("error setting logger params: nothing to setup.");
        }
        if (ah.hasKey("additivity") && ah{"additivity"}.typeCode() != NT_BOOLEAN) {
            return RestHandler::make400("error setting logger additivity: 'additivity' key is not set to boolean; got type %y instead", ah{"additivity"}.type());
        }

        try {
            Qorus.loggerController.updateLogger(internal_name, NOTHING, ah);
            return RestHandler::makeResponse(200, "OK");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NO-LOGGER" || ex.err == "INVALID-INTERFACE") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            if (ex.err == "LOGGER-ERROR" || ex.err == "BAD-REQUEST") {
                return RestHandler::make400("%s: %s", ex.err, ex.desc);
            }
            rethrow;
        }
    }
}

class HelpLoggerRestClass {
    private:internal {
        #! interface type
        string type;
        #! interface table PK column name
        *string colname;
        #! interface table PK value
        auto pk;
    }

    constructor(string type) {
        self.type = type;
    }

    constructor(string type, string colname, auto pk) {
        self.type = type;
        self.colname = colname;
        self.pk = pk;
    }

    private string getType() {
        return type;
    }

    private *string getColname() {
        return colname;
    }

    private auto getPk() {
        return pk;
    }

    private hash<HttpHandlerResponseInfo> getImpl(hash<auto> cx, *hash<auto> ah) {
        # strip types to reformat appenders
        *hash loggerInfo = Qorus.qmm.lookupLogger(type, pk);
        if (loggerInfo.interface_table_name) {
            loggerInfo.interface_table_name = loggerInfo.interface_table_name.lwr();
        }
        if (loggerInfo.params.appenders) {
            loggerInfo.params.appenders = loggerInfo.params.appenders.values();
        }
        return RestHandler::makeResponse(200, extendLoggerLevel(loggerInfo));
    }

    private hash<HttpHandlerResponseInfo> postImpl(hash<auto> cx, *hash<auto> ah) {
        try {
            # clone default logger with assigned to it appenders and assign it to the interface
            if (ah.hasKey("cloneDefault") && parse_boolean(ah{"cloneDefault"}) == True) {
                int loggerId = Qorus.loggerController.cloneDefault(type, colname, pk);
                return RestHandler::makeResponse(200, loggerId);
            }

            if (!ah.hasKey("level")) {
                return RestHandler::make400("error creating logger: 'level' key is not set");
            }

            if (ah.hasKey("additivity")) {
                ah{"additivity"} = parse_boolean(ah{"additivity"});
            } else {
                ah{"additivity"} = True;
            }

            hash<auto> params = ah{"level", "name", "additivity"};

            int loggerId = Qorus.loggerController.createLogger(params, type, colname, pk);
            return RestHandler::makeResponse(200, loggerId);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "PARSE-TYPE-ERROR" || ex.err == "LOGGER-EXISTS" || ex.err == "BAD-REQUEST") {
                return RestHandler::make400("%s: %s", ex.err, ex.desc);
            }
            # exceptions are always returned as 409 Conflict errors
            rethrow;
        }
    }

    private hash<HttpHandlerResponseInfo> putImpl(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("level") && !ah.hasKey("name") && !ah.hasKey("additivity")) {
            return RestHandler::make400("error setting logger params: nothing to setup.");
        }
        if (ah.hasKey("additivity") && ah{"additivity"}.typeCode() != NT_BOOLEAN) {
            return RestHandler::make400("error setting logger additivity: 'additivity' key is not set to boolean; got type %y instead", ah{"additivity"}.type());
        }

        try {
            Qorus.loggerController.updateLogger(type, pk, ah);
            return RestHandler::makeResponse(200, "OK");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NO-LOGGER" || ex.err == "INVALID-INTERFACE") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            if (ex.err == "LOGGER-ERROR" || ex.err == "BAD-REQUEST") {
                return RestHandler::make400("%s: %s", ex.err, ex.desc);
            }
            rethrow;
        }
    }

    private hash<HttpHandlerResponseInfo> delImpl(hash<auto> cx, *hash<auto> ah) {
        try {
            Qorus.qmm.deleteLogger(type, colname, pk);
            return RestHandler::makeResponse(200, "OK");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NO-LOGGER") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            if (ex.err == "PARSE-TYPE-ERROR") {
                return RestHandler::make400("%s: %s", ex.err, ex.desc);
            }
            rethrow;
        }
    }
}

class HelpLoggerAppendersRestClass {
    private:internal {
        #! interface type
        string type;
        #! internal type name
        string internal_name;
        #! interface table PK value
        auto pk;
    }

    constructor(string type, string internal_name) {
        self.type = type;
        self.internal_name = internal_name;
    }

    constructor(string type, string internal_name, auto pk) {
        self.type = type;
        self.internal_name = internal_name;
        self.pk = pk;
    }

    private string getType() {
        return type;
    }

    private auto getPk() {
        return pk;
    }

    private hash<HttpHandlerResponseInfo> getImpl() {
        return RestHandler::makeResponse(200, Qorus.loggerController.getAppenders(internal_name, pk));
    }

    private hash<HttpHandlerResponseInfo> postImpl(hash<auto> cx, *hash<auto> ah) {
        if (!ah{"appenderType"}) {
            return RestHandler::make400("error creating appender: 'appenderType' key is missing");
        }

        try {
            int appenderId = Qorus.loggerController.addAppender(internal_name, pk, ah);
            return RestHandler::makeResponse(200, appenderId);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-INTERFACE" || ex.err == "NO-LOGGER") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            if (ex.err == "PARSE-TYPE-ERROR" || ex.err == "BAD-REQUEST") {
                return RestHandler::make400("%s: %s", ex.err, ex.desc);
            }
            # exceptions are always returned as 409 Conflict errors
            rethrow;
        }
    }

    private hash<HttpHandlerResponseInfo> delImpl(hash<auto> cx, *hash<auto> ah) {
        if (ah{"id"}.typeCode() != NT_INT) {
            return RestHandler::make400("error deleting appender: 'id' key is not set to int; got type %y instead", ah{"id"}.type());
        }

        try {
            Qorus.qmm.deleteAppender(ah{"id"}, internal_name, pk);
            return RestHandler::makeResponse(200, "OK");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-INTERFACE" || ex.err == "NO-LOGGER") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            if (ex.err == "PARSE-TYPE-ERROR" || ex.err == "NO-APPENDER") {
                return RestHandler::make400("%s: %s", ex.err, ex.desc);
            }
            rethrow;
        }
    }

    private hash<HttpHandlerResponseInfo> putImpl(hash<auto> cx, *hash<auto> ah) {
        if (ah.id.typeCode() != NT_INT) {
            return RestHandler::make400("error updating appender: 'id' key is not set to int; got type %y instead", ah.id.type());
        }

        try {
            Qorus.qmm.updateAppender(internal_name, pk, ah.id, ah - "id");
            return RestHandler::makeResponse(200, "OK");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "INVALID-INTERFACE" || ex.err == "NO-LOGGER" || ex.err == "NO-APPENDER") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            if (ex.err == "PARSE-TYPE-ERROR" || ex.err == "BAD-REQUEST") {
                return RestHandler::make400("%s: %s", ex.err, ex.desc);
            }
            rethrow;
        }
    }
}

/** @REST /v3/system/loggers

    Returns all system loggers
*/
class SystemLoggersRestClass inherits QorusRestClass {
    string name() {
        return "loggers";
    }

    /** @REST GET

        @par Description
        Returns all system loggers

        @par Return Value
        This API returns 200 OK and list with hashes with the following keys:
        - \c loggerid: (int) logger id
        - \c params: (hash) logger params
            - \c level: (hash) @ref Logger::LoggerLevel "LoggerLevel"
                - \c "key": logger level string representation
                - \c "value": logger level int representation
            - \c name: (string) logger name
            - \c additivity: (bool) logger additivity
        - \c interface_table_name: (string) interface table name (jobs/workflows/services). If set means default logger
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, Qorus.loggerController.getSystemLoggers());
    }
}

class AbstractSystemLoggerRestClass inherits QorusRestClass {
    private:internal {
        string type;
        string internal_name;
    }

    string name() {
        return type;
    }

    constructor(string type, *string internal_name) {
        self.type = type;
        self.internal_name = internal_name ?? type;
    }

    *QorusRestClass subClassImpl(string logger, hash<auto> cx, *hash<auto> ah) {
        if (logger == "logger") {
            return new SystemLoggerRestClass(type, internal_name);
        }
    }
}

/** @REST /v3/system/{type}/logger

    This URI path provides ability to customize Qorus system logger configurations
*/
class SystemLoggerRestClass inherits HelpSystemLoggerRestClass, QorusRestClass {
    string name() {
        return "logger";
    }

    constructor(string type, *string internal_name) : HelpSystemLoggerRestClass(type, internal_name ?? type) {
    }

    *QorusRestClass subClassImpl(string appender, hash<auto> cx, *hash<auto> ah) {
        if (appender == "appenders") {
            return new SystemAppendersRestClass(getType(), getInternalName());
        }
    }

    /** @REST GET

        @par Description
        Returns system logger info

        @par Return Value
        This API returns 200 OK and hash with the following keys:
        - \c loggerid: (int) logger id
        - \c params: (hash) logger params
            - \c level: (hash) @ref Logger::LoggerLevel "LoggerLevel"
                - \c "key": logger level string representation
                - \c "value": logger level int representation
            - \c name: (string) logger name
            - \c additivity: (bool) logger additivity
            - \c appenders: (list of hashes) list of appender hashes
        - \c interface_table_name: (string) system (audit, alert, monitoring, http, qorus-core, qorus-master, qdsp) type. If set means default logger
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return HelpSystemLoggerRestClass::getImpl(cx, ah);
    }

    /** @REST PUT

        @par Description
        Set system logger params

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: logger name to set
        - \c additivity: logger additivity to set

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        return HelpSystemLoggerRestClass::putImpl(cx, ah);
    }

    /** @REST DELETE

        @par Description
        Delete system logger

        @par Return Value
        If success 200 OK, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        return HelpSystemLoggerRestClass::delImpl(cx, ah);
    }

    /** @REST POST

        @par Description
        Create Logger

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: required; (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: (string) logger name
        - \c additivity: (bool) logger additivity (default @ref True)
        - \c cloneDefault: (bool) create logger with appenders based on default logger

        @par Return Value
        If success 200 with the logger ID created, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        return HelpSystemLoggerRestClass::postImpl(cx, ah);
    }
}

/** @REST /v3/system/audit/logger (/v3/system/{type}/logger)

    This URI path provides ability to customize the Qorus audit logger
*/

/** @REST /v3/system/http/logger (/v3/system/{type}/logger)

    This URI path provides ability to customize the Qorus http logger
*/

/** @REST /v3/system/alert/logger (/v3/system/{type}/logger)

    This URI path provides ability to customize the Qorus alert logger
*/

/** @REST /v3/system/monitoring/logger (/v3/system/{type}/logger)

    This URI path provides ability to customize the Qorus monitoring logger
*/

/** @REST /v3/system/qorus-master/logger (/v3/system/{type}/logger)

    This URI path provides ability to customize the @ref qorus process logger
*/

/** @REST /v3/system/qorus-core/logger (/v3/system/{type}/logger)

    This URI path provides ability to customize the @ref qorus-core process logger
*/

/** @REST /v3/system/logger/appenders

    This URI path provides ability to customize Qorus system logger appenders
*/
class SystemAppendersRestClass inherits HelpLoggerAppendersRestClass, QorusRestClass {
    string name() {
        return "appenders";
    }

    constructor(string type, *string internal_name) : HelpLoggerAppendersRestClass(type, internal_name ?? type) {
    }

    /** @REST GET

        @par Description
        Return system logger appenders

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: (string) id of appender to get

        @par Return Value
        This API returns 200 OK and list with the following hashes:
        - \c appenderId: (int) appenderId
        - \c params: (hash) possible appender parameters, might be missing if not set
            - \c name: (string) appender name
            - \c layoutPattern: (string) appender layout pattern
            - \c rotation: (int) appender layout pattern
            - \c filename: (string) appender filename
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::getImpl();
    }

    /** @REST DELETE
        @par Description
        Delete logger appender with obtained id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be deleted

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::delImpl(cx, ah);
    }

    /** @REST POST

        @par Description
        Create logger appenders

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK and appender id, in case of fail one of the error codes: 400, 409 and \a string of error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::postImpl(cx, ah);
    }

    /** @REST PUT
        @par Description
        Update logger appender with the given id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be update
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppender
File, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::putImpl(cx, ah);
    }
}

/** @REST /v3/{interface}/{id_or_name}/logger

    This URI path provides ability to customize Qorus interface logger configurations
*/
class LoggerRestClass inherits HelpLoggerRestClass, QorusRestClass {
    constructor(string type) : HelpLoggerRestClass(type) {
    }

    constructor(string type, string colname, auto pk) : HelpLoggerRestClass(type, colname, pk) {
    }

    string name() {
        return "logger";
    }

    *QorusRestClass subClassImpl(string appender, hash<auto> cx, *hash<auto> ah) {
        if (appender == "appenders") {
            qlog(LoggerLevel::DEBUG, "Check authorization for user: %y", cx.user);
            return new AppendersRestClass(getType(), getPk());
        }
    }

    /** @REST GET

        @par Description
        Returns logger info

        @par Return Value
        This API returns 200 OK and hash with the following keys:
        - \c loggerid: (int) logger id
        - \c params: (hash) logger params
            - \c level: (hash) @ref Logger::LoggerLevel "LoggerLevel"
                - \c "key": logger level string representation
                - \c "value": logger level int representation
            - \c name: (string) logger name
            - \c additivity: (bool) logger additivity
        - \c interface_table_name: (string) interface table name (jobs/workflows/services). If set means default logger
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::getImpl(cx, ah);
    }

    /** @REST PUT

        @par Description
        Set logger params

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: logger name to set
        - \c additivity: logger additivity to set

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::putImpl(cx, ah);
    }

    /** @REST DELETE

        @par Description
        Delete logger

        @par Return Value
        If success 200 OK, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::delImpl(cx, ah);
    }

    /** @REST POST

        @par Description
        Create Logger

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c level: required; (int|string) @ref Logger::LoggerLevel "LoggerLevel"
        - \c name: (string) logger name
        - \c additivity: (bool) logger additivity (default @ref True)
        - \c cloneDefault: (bool) create logger with appenders based on default logger

        @par Return Value
        If success 200 with the logger ID created, in case of failure 400 and \a string with error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerRestClass::postImpl(cx, ah);
    }
}

/** @REST /v3/{interface}/{id_or_name}/logger/appenders

    This URI path provides ability to customize Qorus inerface logger appenders
*/
class AppendersRestClass inherits HelpLoggerAppendersRestClass, QorusRestClass {
    string name() {
        return "appenders";
    }

    constructor(string type) : HelpLoggerAppendersRestClass(type, type) {
    }

    constructor(string type, auto pk) : HelpLoggerAppendersRestClass(type, type, pk) {
    }

    /** @REST GET

        @par Description
        Return all logger appenders

        @par Return Value
        This API returns 200 OK and list with the following hashes:
        - \c appenderId: (int) appenderId
        - \c params: (hash) possible appender parameters, might be missing if not set
            - \c name: (string) appender name
            - \c layoutPattern: (string) appender layout pattern
            - \c rotation: (int) appender layout pattern
            - \c filename: (string) appender filename
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::getImpl();
    }

    /** @REST DELETE
        @par Description
        Delete logger appender with obtained id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be deleted

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::delImpl(cx, ah);
    }

    /** @REST POST

        @par Description
        Create logger appenders

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values) (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK and appender id, in case of fail one of the error codes: 400, 409 and \a string of error description

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call
        - <tt><b>409 Conflict</b></tt>: conflict with the current state
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::postImpl(cx, ah);
    }

    /** @REST PUT
        @par Description
        Update logger appender with the given id

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; (int); id of the appender to be update
        - \c name: (string) the name of the appender
        - \c layoutPattern: (string) the layout for the appender
        - \c filename: (string) the output filename
        - \c encoding: (string) the file's output encoding
        - \c appenderType: required; (string) appender type, case sensitive (see @ref Logger::Logger "Logger" for possible values)
          (ex. LoggerAppenderFileRotate, LoggerAppenderFile, LoggerAppenderStdOut ...)
        - \c rotationCount: (int) the number of files in rotation chain, if count is <=0 then no ratation is performed. Only for rotation appenders
        - \c archivePattern: (string) pattern to evaluate archive filename

        @par Return Value
        If success 200 OK, in case of fail 400 and \a string with error description
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        return HelpLoggerAppendersRestClass::putImpl(cx, ah);
    }
}
} # namespace QorusLogger
