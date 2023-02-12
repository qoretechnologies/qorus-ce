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

/** @page rest_api_page_v5 Qorus REST API v5

    @tableofcontents

    @section rest_api_v5_overview Qorus REST API v5 Overview

    REST API v5 has the following differences from @ref rest_api_page_v4 "REST API v4":
    - added support for @ref finite_state_machines "Finite State Machines": @ref rest_api_latest_fsms
    - added support for @ref data_pipelines "data pipelines": @ref rest_api_latest_pipelines
*/

/** @REST /v5 (/v4)

    This URI path implements v5 of the Qorus REST API
*/
class V5RestClass inherits QorusRestClass {
    constructor() {
        addClass(new WorkflowRestClassV5());
        addClass(new GlobalOrderRestClassV5());
        addClass(new GlobalWorkflowExecRestClassV3());
        addClass(new ServiceRestClassV5());
        addClass(new JobRestClassV5());
        addClass(new SystemRestClassV5());
        addClass(new UsersRestClass());
        addClass(new RolesRestClass());
        addClass(new GroupsRestClassV5());
        addClass(new StepRestClassV3());
        addClass(new FunctionRestClass());
        addClass(new ClassRestClassV5());
        addClass(new ConstantRestClass());
        addClass(new DebugRestClass());
        addClass(new JobResultsRestClass());
        addClass(new LogsRestClass());
        addClass(new RemoteRestClassV5());
        addClass(new PermsRestClass());
        addClass(new ErrorsRestClassV3());
        addClass(new MappersRestClassV4());
        addClass(new MapperTypesRestClass());
        addClass(new AsyncQueuesRestClassV3());
        addClass(new ValueMapsRestClass());
        addClass(new ReleasesRestClass());
        addClass(new SyncEventTypesRestClass());
        addClass(new SlasRestClass());
        addClass(new DataProviderBaseRestClassV5());
        addClass(new FsmsRestClass());
        addClass(new PipelinesRestClass());
        addClass(new LogoutRestClass());
        addClass(new CommandRestClass());
        addClass(new RemoteDevelopment::RestClass());
        addClass(new ObjectOptionsRestClass());
    }

    string name() {
        return "v5";
    }

    /** @REST GET

        @par Description
        Returns the top-level members of this version of the REST API
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, keys class_hash);
    }
}

/** @REST /v5/services/{id_or_name} (/v4/services/{id_or_name})

    This REST URI path provides actions and information related to Qorus services.
*/
class ServiceDefinitionRestClassV5 inherits ServiceDefinitionRestClassV3 {
    constructor(hash<auto> sh) : ServiceDefinitionRestClassV3(sh) {
    }

    /** @REST GET action=options

        @par Description
        Returns options set on the current service.

        @par Return Value
        This API returns @ref nothing if no options are set, otherwise a hash of service options.
    */
    hash<HttpHandlerResponseInfo> getOptions(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, sh."runtime-options");
    }
}

/** @REST /v5/services (/v4/services)

    This REST URI path provides actions and information related to Qorus services;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class ServiceRestClassV5 inherits ServiceRestClassV3 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = ServiceRestClass::staticGetServiceId(arg);
        *hash<auto> svc = ServiceRestClass::staticGetService(cx, id, ah, 5);
        if (!svc) {
            return;
        }

        return new ServiceDefinitionRestClassV5(svc);
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
        return RestHandler::makeResponse(200, ServiceRestClass::staticGetServices(cx, ah, 5, ah));
    }
}

/** @REST /v5/jobs/{id_or_name} (/v4/jobs/{id_or_name})

    This REST API path provides actions and information related to specific jobs;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class JobDefinitionRestClassV5 inherits JobDefinitionRestClassV4 {
    constructor(hash<auto> jh) : JobDefinitionRestClassV4(jh) {
    }

    /** @REST GET action=options

        @par Description
        Returns options set on the current job.

        @par Return Value
        This API returns @ref nothing if no options are set, otherwise a hash of job options.
    */
    hash<HttpHandlerResponseInfo> getOptions(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, jh."runtime-options");
    }
}

/** @REST /v5/jobs (/v4/jobs)

    This REST API path provides actions and information related to Qorus jobs.
*/
class JobRestClassV5 inherits JobRestClassV4 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = JobRestClass::staticGetJobId(arg);
        *hash<auto> job = JobRestClassV2::staticGetJob(cx, ah, id, 5);
        if (!job) {
            return;
        }

        hash<auto> ji = Qorus.jobManager.getActiveInfo();
        JobRestClass::fixJob(\job, ji.(job.name), cx);

        return internGetJobDefinition(job);
    }

    /** @REST GET

        @par Description
        Returns information about Qorus jobs according to the arguments
        returned

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
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        if (*hash<HttpHandlerResponseInfo> err = parseTagOptions(\ah)) {
            return err;
        }

        return RestHandler::makeResponse(200, JobRestClass::staticGetJobs(cx, ah, 5, ah));
    }

    private QorusRestClass internGetJobDefinition(hash<auto> job) {
        return new JobDefinitionRestClassV5(job);
    }
}

/** @REST /v5/fsms/{name}/config/{name}

    This REST URI path provides actions and information related to a particular configuration item for a particular
    Qorus Finite State Machine.

    Prefixes can be passed within the config item name or as following: /v5/fsms/{name}/config/{name}?prefix={prefix}.
*/
class FsmConfigItemRestClass inherits QorusRestClass {
    private {
        hash<auto> fsm;
        hash<auto> item;

        string name_with_prefix;
    }

    constructor(hash<auto> fsm, hash<auto> item) {
        self.fsm = fsm;
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
        Returns a hash for the current Finite State Machine configuration item

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
        - \c "level": the level from where the value is obtained (interface level (e.g. "fsm:name1", "fsm:name2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, item);
    }

    /** @REST GET action=yaml
        @par Description
        Returns a hash for the current Finite State Machine configuration item as a serialized YAML string

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
        - \c "level": the level from where the value is obtained (interface level (e.g. "fsm:name1", "fsm:name2")
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

    /** @REST PUT

        @par Description
        Sets the value for the given Finite State Machine configuration item

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

        hash<auto> changed = Qorus.qmm.setConfigItemValueOnInterfaceLevel("fsm", fsm.name, name_with_prefix, ah.value);
        changed.info = sprintf("%y configuration item value for Finite State Machine %y has been changed",
            name_with_prefix, fsm.name);
        return RestHandler::makeResponse(200, changed);
    }

    /** @REST PUT action=yaml

        @par Description
        Sets the value for the given Finite State Machine configuration item using a YAML-serialized string

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
    hash<auto> putYaml(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> error;
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
        Permanently deletes the current value for the configuration item for the current Finite State Machine

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value: deleted value
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        hash<auto> result;
        auto res = Qorus.qmm.deleteConfigItemValueOnInterfaceLevel("fsm", fsm.name, name_with_prefix, \result.deleted);
        result += {
            "value": res,
            "info": sprintf("%y configuration item value for Finite State Machine %y has been deleted",
                name_with_prefix, fsm.name),
        };
        return RestHandler::makeResponse(200, result);
    }

    /** @REST DELETE action=yaml

        @par Description
        Permanently deletes the current value for the configuration item for this Finite State Machine on the local
        level

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

/** @REST /v5/fsms/{name}/config

    This REST URI path provides actions and information related to Qorus Finite State Machine configuration items
*/
class FsmConfigItemsRestClass inherits QorusRestClass {
    private {
        hash<auto> fsm;
    }

    constructor(hash<auto> fsm) {
        self.fsm = fsm;
    }

    string name() {
        return "config";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        string name_with_prefix = ah.prefix + arg;
        if (*hash<auto> item = fsm.config{name_with_prefix}) {
            # get actual item name
            if (item.prefix && name_with_prefix.equalPartial(item.prefix)) {
                arg = name_with_prefix[item.prefix.length()..];
            }
            return new FsmConfigItemRestClass(fsm, {"name": arg} + item);
        }
    }

    /** @REST GET
        @par Description
        Returns a list of Finite State Machine configuration items for the Finite State Machine

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
        - \c "level": the level from where the value is obtained (interface level (e.g. "fsm:name1", "fsm:name2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                                                   fsm.config.pairIterator()));
    }

    /** @REST GET action=yaml
        @par Description
        Returns a list of configuration items for the Finite State Machine as a YAML-serialized string

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
        - \c "level": the level from where the value is obtained (interface level (e.g. "fsm:name1", "fsm:name2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> config_copy = fsm.config;

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

/** @REST /v5/fsms/{name}

    This REST API path provides actions and information related to a particular Qorus Finite State Machine.
*/
class FsmRestClass inherits QorusRestClass {
    private {
        hash<auto> fsm;
    }

    constructor(hash<auto> fsm) {
        self.fsm = fsm;
    }

    string name() {
        return fsm.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "config") {
            return new FsmConfigItemsRestClass(fsm);
        }

        if (cx.hdr.method == "GET" && fsm.hasKey(arg)) {
            return new AttributeRestClass(fsm{arg});
        }
    }

    /** @REST GET

        @par Description
        Returns the description of the Finite State Machine
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, fsm);
    }
}

/** @REST /v5/fsms

    This REST API path provides actions and information related to Qorus Finite State Machines.
*/
class FsmsRestClass inherits QorusRestClass {
    constructor() {
    }

    string name() {
        return "fsms";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> fsm = staticGetFsm(cx, ah, arg);
        if (!fsm) {
            return;
        }

        return new FsmRestClass(fsm);
    }

    static *list<hash<auto>> staticGetFsms(*hash<auto> cx, *hash<auto> ah) {
        return map $1, Qorus.qmm.getFsmMap(True).iterator();
    }

    private static *hash<auto> staticGetFsm(hash<auto> cx, *hash<auto> ah, string name) {
        return Qorus.qmm.lookupFsm(name, True);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes describing Finite State Machines in Qorus

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of FSM names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of
          FSM information is returned
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *list<hash<auto>> rv = staticGetFsms(cx, ah);

        if (exists ah."list" && parse_boolean(ah."list")) {
            return RestHandler::makeResponse(200, (map $1.name, rv));
        }
        # return summary info
        if (exists ah.short && parse_boolean(ah.short)) {
            return RestHandler::makeResponse(200,
                map sprintf("%s: states: %d triggers: %d options: %d", $1.name, $1.states.size(), $1.triggers.size(),
                    $1.options.size()), rv);
        }

        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v5/pipelines/{name}/config/{name}

    This REST URI path provides actions and information related to a particular configuration item for a particular
    Qorus Data pipeline.

    Prefixes can be passed within the config item name or as following: /v5/pipelines/{name}/config/{name}?prefix={prefix}.
*/
class PipelineConfigItemRestClass inherits QorusRestClass {
    private {
        hash<auto> pipeline;
        hash<auto> item;

        string name_with_prefix;
    }

    constructor(hash<auto> pipeline, hash<auto> item) {
        self.pipeline = pipeline;
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
        Returns a hash for the current Data pipeline configuration item

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
        - \c "level": the level from where the value is obtained (interface level (e.g. "pipeline:name1", "pipeline:name2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, item);
    }

    /** @REST GET action=yaml
        @par Description
        Returns a hash for the current Data pipeline configuration item as a serialized YAML string

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
        - \c "level": the level from where the value is obtained (interface level (e.g. "pipeline:name1", "pipeline:name2")
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

    /** @REST PUT

        @par Description
        Sets the value for the given Data pipeline configuration item

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

        hash<auto> changed = Qorus.qmm.setConfigItemValueOnInterfaceLevel("pipeline", pipeline.name, name_with_prefix, ah.value);
        changed.info = sprintf("%y configuration item value for Data pipeline %y has been changed",
            name_with_prefix, pipeline.name);
        return RestHandler::makeResponse(200, changed);
    }

    /** @REST PUT action=yaml

        @par Description
        Sets the value for the given Data pipeline configuration item using a YAML-serialized string

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
    hash<auto> putYaml(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> error;
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
        Permanently deletes the current value for the configuration item for the current Data pipeline

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
        - \c deleted: True if value has been deleted
        - \c value: deleted value
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        hash<auto> result;
        auto res = Qorus.qmm.deleteConfigItemValueOnInterfaceLevel("pipeline", pipeline.name, name_with_prefix, \result.deleted);
        result += {
            "value": res,
            "info": sprintf("%y configuration item value for Data pipeline %y has been deleted",
                name_with_prefix, pipeline.name),
        };
        return RestHandler::makeResponse(200, result);
    }

    /** @REST DELETE action=yaml

        @par Description
        Permanently deletes the current value for the configuration item for this Data pipeline on the local
        level

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

/** @REST /v5/pipelines/{name}/config

    This REST URI path provides actions and information related to Qorus Data pipeline configuration items
*/
class PipelineConfigItemsRestClass inherits QorusRestClass {
    private {
        hash<auto> pipeline;
    }

    constructor(hash<auto> pipeline) {
        self.pipeline = pipeline;
    }

    string name() {
        return "config";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        string name_with_prefix = ah.prefix + arg;
        if (*hash<auto> item = pipeline.config{name_with_prefix}) {
            # get actual item name
            if (item.prefix && name_with_prefix.equalPartial(item.prefix)) {
                arg = name_with_prefix[item.prefix.length()..];
            }
            return new PipelineConfigItemRestClass(pipeline, {"name": arg} + item);
        }
    }

    /** @REST GET
        @par Description
        Returns a list of Data pipeline configuration items for the Data pipeline

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
        - \c "level": the level from where the value is obtained (interface level (e.g. "pipeline:name1", "pipeline:name2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (map {"name": $1.key.substr(elements $1.value.prefix)} + $1.value,
                                                   pipeline.config.pairIterator()));
    }

    /** @REST GET action=yaml
        @par Description
        Returns a list of configuration items for the Data pipeline as a YAML-serialized string

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
        - \c "level": the level from where the value is obtained (interface level (e.g. "pipeline:name1", "pipeline:name2")
             or "global" or "default")
        - \c "is_templated_string": @ref True if the value is a templated string that can be later expanded
    */
    hash<auto> getYaml(hash<auto> cx, *hash<auto> ah) {
        hash<auto> config_copy = pipeline.config;

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

/** @REST /v5/pipelines/{name}

    This REST API path provides actions and information related to a particular Qorus Data pipeline.
*/
class PipelineRestClass inherits QorusRestClass {
    private {
        hash<auto> pipeline;
    }

    constructor(hash<auto> pipeline) {
        self.pipeline = pipeline;
    }

    string name() {
        return pipeline.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "config") {
            return new PipelineConfigItemsRestClass(pipeline);
        }

        if (cx.hdr.method == "GET" && pipeline.hasKey(arg)) {
            return new AttributeRestClass(pipeline{arg});
        }
    }

    /** @REST GET

        @par Description
        Returns the description of the Data pipeline
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, pipeline);
    }
}

/** @REST /v5/pipelines

    This REST API path provides actions and information related to Qorus Data pipelines.
*/
class PipelinesRestClass inherits QorusRestClass {
    constructor() {
    }

    string name() {
        return "pipelines";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> pipeline = staticGetPipeline(cx, ah, arg);
        if (!pipeline) {
            return;
        }

        return new PipelineRestClass(pipeline);
    }

    private static *list<hash<auto>> staticGetPipelines(hash<auto> cx, *hash<auto> ah) {
        return map $1, Qorus.qmm.getPipelineMap(True).iterator();
    }

    private static *hash<auto> staticGetPipeline(hash<auto> cx, *hash<auto> ah, string name) {
        return Qorus.qmm.lookupPipeline(name, True);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes describing @ref data_pipelines "data pipelines" in Qorus

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of data pipeline names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of
          data pipeline information is returned
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *list<hash<auto>> rv = staticGetPipelines(cx, ah);

        if (exists ah."list" && parse_boolean(ah."list")) {
            return RestHandler::makeResponse(200, (map $1.name, rv));
        }
        # return summary info
        if (exists ah.short && parse_boolean(ah.short)) {
            return RestHandler::makeResponse(200,
                map sprintf("%s: (%d child%s): %s", $1.name, $1.children.size(), $1.children.size() == 1 ? "" : "ren", $1.description), rv);
        }

        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v5/groups

    This URI path provides actions and information related to @ref rbacgroups "interface groups"
*/
class GroupsRestClassV5 inherits GroupsRestClass {
    /** @REST POST

        @par Description
        Creates a new @ref rbacgroups "interface group".  If a new group is created with the enabled flag set to
        @ref False, then workflows, services, and jobs members of the group are stopped immediately if loaded/running.
        Changes are committed to the database before the call returns.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c group: (string) required; the name of the group
        - \c desc: (string) required; the description of the group
        - \c workflows: (list of strings or a single string) optional; a comma-separated string will be split into a
          list; the list of workflow names or IDs to include in the group
        - \c services: (list of strings or a single string) optional; a comma-separated string will be split into a
          list; the list of user service names or IDs to include in the group
        - \c jobs: (list of strings or a single string) optional; a comma-separated string will be split into a list;
          the list of job names or IDs to include in the group
        - \c mappers: (list of strings or a single string) optional; a comma-separated string will be split into a
          list; the list of @ref mappers "mapper" names or IDs to include in the group
        - \c vmaps: (list of strings or a single string) optional; a comma-separated string will be split into a list
          the list of @ref value-maps "value map" names or IDs to include in the group
        - \c fsms: (list of strings) optional; a comma-separated string will be split into a list the list of
          @ref finite_state_machines "Finite State Machine" names to include in the group
        - \c pipelines: (list of strings) optional; a comma-separated string will be split into a list the list of
          @ref data_pipelines "data pipeline" names to include in the group
        - \c enabled: (string) this value will be processed by parse_boolean(); the initial enabled flag for the
          group; if not present defaults to @ref True

        @par Return Value
        This API returns a @ref rest_group_detail_hash for the new group

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-ERROR: invalid or unknown workflow
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-ERROR: invalid or unknown service
        - <tt><b>409 Conflict</b></tt>: \c JOB-ERROR: invalid or unknown job
        - <tt><b>409 Conflict</b></tt>: \c MAPPER-ERROR: invalid or unknown mapper
        - <tt><b>409 Conflict</b></tt>: \c VALUE-MAP-ERROR: invalid or unknown value map
        - <tt><b>409 Conflict</b></tt>: \c FSM-ERROR: invalid or unknown Finite State Machine
        - <tt><b>409 Conflict</b></tt>: \c PIPELINE-ERROR: invalid or unknown data pipeline
        - <tt><b>409 Conflict</b></tt>: \c GROUP-ERROR: missing \c group or \c desc arguments

        @see
        - omq.system.group.create()
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        return internPost(cx, ah, 5);
    }
}

/** @REST /v5/classes (/v4/classes/)

    This REST API path provides actions and information about Qorus class objects
*/
class ClassRestClassV5 inherits ClassRestClassV3 {
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
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        if (*hash<HttpHandlerResponseInfo> err = parseTagOptions(\ah)) {
            return err;
        }

        *hash<auto> h = doGetClassMap();

        Qorus.httpServer.logInfo("CLASSES GET ah: %y (size: %d)", ah, h.size());

        if (ah.tags) {
            h = QorusMapManager::filterHash(h, ah);
        }

        Qorus.httpServer.logInfo("CLASSES GET after filter (size: %d)", h.size());

        *list<auto> rv;
        if (exists ah."list" && parse_boolean(ah."list")) {
            rv = map $1.name, h.iterator();
        } else if (exists ah.short && parse_boolean(ah.short)) {
            rv = map sprintf("%s v%s (%d)", $1.value.name, $1.value.version, $1.key), h.pairIterator();
        } else {
            # repackage into a list of hashes
            rv = map {"classid": $1.key.toInt()} + $1.value, h.pairIterator();
        }

        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v5/system/options (/v4/system/options)

    This REST URI path provides actions and information related to system options; see @ref systemoptions for more information
*/
class SystemOptionsRestClassV5 inherits SystemOptionsRestClass {
    /** @REST PUT action=flush

        @par Description
        Flush current server options to the @ref options "option file" on the server's filesystem

        @par Return Value
        This API returns \c "OK" upon successful execution
    */
    hash<auto> putFlush(hash<auto> cx, *hash<auto> ah) {
        Qorus.options.flushToFile(ah);
        return RestHandler::makeResponse(200, "OK");
    }
}

/** @REST /v5/remote/qorus/{name} (/v4/remote/qorus/{name})

    This REST URI path provides actions and information related to a specific @ref remoteconn "remote connection"
*/
class QorusRemoteConnectionRestClassV5 inherits QorusRemoteConnectionRestClassV4 {
    constructor(hash<auto> rh) : QorusRemoteConnectionRestClassV4(rh) {
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV5(provider);
    }
}

/** @REST /v5/remote/qorus (/v4/remote/qorus)

    This REST URI path provides actions and information related to Qorus @ref remoteconn "remote connections"
*/
class QorusRemoteConnectionsRestClassV5 inherits QorusRemoteConnectionsRestClassV4 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
        *hash<auto> rh = Qorus.remotemonitor.tryGetInfo(name, {"with_passwords": with_passwords});
        if (rh) {
            return new QorusRemoteConnectionRestClassV5(rh);
        }
    }
}

/** @REST /v5/remote/user/{name} (/v4/remote/user/{name})

    This REST URI path provides actions and information related to a specific @ref userconn "user connection"
*/
class UserConnectionRestClassV5 inherits UserConnectionRestClassV4 {
    constructor(hash<auto> rh) : UserConnectionRestClassV4(rh) {
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV5(provider);
    }
}

/** @REST /v5/remote/user (/v4/remote/user)

    This REST URI path provides actions and information related to Qorus @ref userconn "user connections"
*/
class UserConnectionsRestClassV5 inherits UserConnectionsRestClassV4 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
        *hash<auto> rh = Qorus.connections.getInfo(name, {"with_passwords": with_passwords});
        if (rh) {
            return new UserConnectionRestClassV5(rh);
        }
    }
}

/** @REST /v5/remote/datasources/{name} (/v4/remote/datasources/{name})

    This REST URI path provides actions and information related to a specific Qorus system @ref dsconn "datasource"
*/
class DatasourceRestClassV5 inherits DatasourceRestClassV4 {
    constructor(hash<auto> rh) : DatasourceRestClassV4(rh) {
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV5(provider);
    }
}

/** @REST /v5/remote/datasources (/v4/remote/datasources)

    This REST URI path provides actions and information related to Qorus system @ref dsconn "datasources"
*/
class DatasourcesRestClassV5 inherits DatasourcesRestClassV4 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
        *hash<auto> rh = Qorus.dsmanager.tryGetInfo(name, {
            "with_passwords": with_passwords,
            "rtime": parse_boolean(ah.rtime),
        });
        if (rh) {
            return new DatasourceRestClassV5(rh);
        }
    }
}

/** @REST /v5/remote (/v4/remote)

    This REST URI path provides actions and information about remote @ref remoteconn "Qorus", @ref userconn "user" and
    @ref dsconn "datasource" connections
*/
class RemoteRestClassV5 inherits RemoteRestClassV4 {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "qorus": return new QorusRemoteConnectionsRestClassV5();
            case "user": return new UserConnectionsRestClassV5();
            case "datasources": return new DatasourcesRestClassV5();
        }
    }
}

/** @REST /v5/system (/v4/system)

    This REST URI path provides actions and information for system functionality
*/
class SystemRestClassV5 inherits SystemRestClassV4 {
    public {
        const SubClasses = SystemRestClassV4::SubClasses + {
            "options": "SystemOptionsRestClassV5",
        };
    }

    hash<auto> internGetInfo(hash<auto> cx) {
        return SystemRestClassV4::internGetInfo(cx) + {
            # return pipeline option keys
            "pipeline_options": PipelineOptions,
            "stack_size": get_default_thread_stack_size(),
        };
    }

    private hash<string, string> doGetSubClasses() {
        return SubClasses;
    }
}

/** @REST /v5/command

    This URI path provides API support for Qorus remote code deployments
*/
class CommandRestClass inherits QorusRestClass {
    public {
    }

    constructor() {
    }

    string name() {
        return "command";
    }

    /** @REST POST

        @par Description
        Returns the result of the command

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c args: (optional) command-line arguments
        - \c cmd: (required) the command to execute (ex: \c oload)
        - \c dir: (required for \c make-release and \c oload)

        @par oload Arguments
        - \c files: (required) a list of files for the oload command

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing or invalid option
        - <tt><b>500 Internal Server Error</b></tt>: returned if there is an error executing the command
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        if (ah.cmd.typeCode() != NT_STRING) {
            # will be converted to a 400 Bad Request response
            throw "REST-ARG-ERROR", sprintf("missing or invalid 'cmd' arg; got type %y (%y); expecting \"string\"",
                ah.cmd.type(), ah.cmd);
        }

        string dir = "";
        string result = "";
        string user_directory = "";

        string remote_dir = Qorus.getRemoteFileDir() + Qore::DirSep;
        Qorus.httpServer.logArgs(LoggerLevel::INFO, "remote request for %y using dir: %y", (ah.cmd, remote_dir));

        if (ah.cmd == "make-release") {
            dir = doGetString(ah, "dir");
            user_directory = remote_dir + dir;
            ah.args = sprintf("%s -r%s", ah.args, user_directory);
        } else if (ah.cmd == "oload") {
            if (ah.dir) {
                user_directory = remote_dir + ah.dir;
            }
            # make sure that all paths are relative
            ah.files =~ s/"\/+/"/g;
            ah.args = ah.args + " " + ah.opts + " " + ah.files;
        }

        string cmd;
        try {
            cmd = ah.cmd + " " + ah.args;

            if (user_directory)
                cmd = sprintf("cd %s && %s", user_directory, cmd);

            rlog(cx, "executing remote command: %y", cmd);
            result = backquote(cmd + " 2>&1");
            QDBG_LOG("exec cmd %y: %s", cmd, trim(result));
        } catch (hash<auto> ex) {
            Qorus.httpServer.logInfo("%s", get_exception_string(ex));
            return RestHandler::makeResponse(500, sprintf("%s: command %y: %s: %s", get_ex_pos(ex), cmd ?? ah.cmd, ex.err, ex.desc));
        }

        return RestHandler::makeResponse(200, result);
    }
}

/** @REST /v5/options/remote

    This REST URI path provides actions and information about supported options for Qorus connection objects
*/
class RemoteOptionsRestClass inherits QorusRestClass {
    string name() {
        return "remote";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            *hash<ConnectionSchemeInfo> entry = ConnectionSchemeCache::getScheme(arg);
            if (entry) {
                return new AttributeRestClass(doGetOptionInfo(entry));
            }
        }
    }

    /** @REST GET

        @par Description
        Returns a hash of option information for all supported user connection schemes

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of supported connection
          schemes is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of supported connection
          schemes is returned
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        hash<auto> schemes = doGetSchemes();

        if ((exists ah.list && parse_boolean(ah.list)) || (exists ah.short && parse_boolean(ah.short))) {
            return RestHandler::makeResponse(200, keys schemes);
        }

        return RestHandler::makeResponse(200, schemes);
    }

    private hash<auto> doGetOptionInfo(hash<ConnectionSchemeInfo> entry) {
        hash<auto> rv;
        foreach hash<auto> i in (entry.options.pairIterator()) {
            # += in order to stay hash<auto>
            hash<auto> h += i.value;
            if (h.default_value) {
                h."default" = remove h.default_value;
            }
            if (h.allowed_values) {
                h.allowed_values = map ("name": $1.value, "desc": $1.desc), h.allowed_values;
            }
            rv{i.key} = h;
        }
        return rv ?? {};
    }

    private hash<auto> doGetSchemes() {
        # return sorted schemes
        hash<auto> schemes = ConnectionSchemeCache::get();
        return map {$1.key: doGetOptionInfo($1.value)}, schemes{sort(keys schemes)}.pairIterator();
    }

    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return QorusRestClass::doGetPossibleSubClasses(cx, ah) + (map {$1: True}, keys ConnectionSchemeCache::get());
    }
}

/** @REST /v5/options

    This REST URI path provides actions and information about supported options for various Qorus objects
*/
class ObjectOptionsRestClass inherits QorusRestClass {
    public {
        const InterfaceSystemOptions = {
            "stack-size": {
                "type": "byte-size",
                "desc": "The default stack size in bytes for new threads; interface-specific values only take effect "
                    "in remote processes",
            }
        };

        const LanguageAllowedValues = (
            {
                "value": 'qore',
                "icon": 'qore',
            },
            {
                "value": 'python',
                "icon": 'python',
            },
        );

        const FsmBlockOptions = {
            "for": {
                "init_var": {
                    "type": "*string",
                    "desc": "This string indicates a key in the `$var:` hash for local storage where the result of "
                        "`init` evaluation is stored.\n\nBoth `init` and `init_var` must be present, otherwise this "
                        "field is ignored.",
                },
                "language": {
                    "type": "enum",
                    "allowed_values": LanguageAllowedValues,
                    "default": "qore",
                    "desc": "The programming language for the `init`, `condition`, and `update` expressions.",
                },
                "init": {
                    "type": "*string",
                    "desc": "The initialization expression for the `for` loop; if present, this expression is "
                        "evaluated once at the start of the loop, and the result is stored in the location indicated "
                        "by `init_var`.\n\nBoth `init` and `init_var` must be present, otherwise this field is "
                        "ignored.",
                },
                "condition": {
                    "type": "string",
                    "desc": "The condition expression for the `for` loop; the loop stops executing when this "
                        "expression evaluates to `False`.\n\nThis expression is evaluated directly before the loop is "
                        "executed.",
                },
                "update_var": {
                    "type": "*string",
                    "desc": "This string indicates a key in the `$var:` hash for local storage where the result of "
                        "`update` evaluation is stored.\n\nBoth `update` and `update_var` must be present, otherwise "
                        "this field is ignored.",
                },
                "update": {
                    "type": "string",
                    "desc": "The update expression for the `for` loop; if this expression is set, it is evaluted "
                        "after the loop is executed and before the `condition `expression is evaluated for the next "
                        "iteration.\n\nBoth `update` and `update_var` must be present, otherwise this field is "
                        "ignored.",
                },
            },
            "foreach": {
                "loop": {
                    "type": "string",
                    "desc": "This expression is evaluated once at the start of the `foreach` loop, and the value "
                        "returned is used to execute the loop and determine the data submitted to the initial "
                        "state(s) in the block.\n\nIf the expression evaluates to a list, then the loop is executed "
                        "with each element of list in turn as the data for the initial state(s) in the block.\n\n"
                        "If the expression evaluates to a single value, then the `foreach` loop is executed once for "
                        "that value.\n\nIf the expression evaluates to no value, then `foreach` loop execution is "
                        "skipped.",
                },
                "language": {
                    "type": "enum",
                    "allowed_values": LanguageAllowedValues,
                    "default": "qore",
                    "desc": "The programming language for the `loop` expression.",
                },
            },
            "while": {
                "condition": {
                    "type": "string",
                    "desc": "The condition expression for the `while` loop; the loop stops executing when this "
                        "expression evaluates to `False`.\n\nThis expression is evaluated directly before the loop "
                        "is executed.",
                },
                "language": {
                    "type": "enum",
                    "allowed_values": LanguageAllowedValues,
                    "default": "qore",
                    "desc": "The programming language for the `condition` expression.",
                },
            },
        };

        const OptionInfo = {
            "block": FsmBlockOptions,
            "mapper": QorusMapper::UserOptions,
            "pipeline": PipelineOptions,
            "system": InterfaceSystemOptions,
        };
    }

    constructor() {
        addClass(new RemoteOptionsRestClass());
    }

    string name() {
        return "options";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            *hash<auto> rv = OptionInfo{arg};
            if (rv) {
                return new AttributeRestClass(rv);
            }
        }
    }

    /** @REST GET

        @par Description
        Returns a hash of option information for the following objects:
        - \c block: a hash of supported @ref finite_state_machines "finite state machine" block types, each block type
          key is then assigned to a hash of options.
        - \c mapper: a hash of supported mapper options
        - \c pipeline: a hash of supported pipeline options
        - \c remote: a hash of supported remote connection schemes and supported options per scheme
        - \c system: a hash of supported system options that can be overridden in all interfaces
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, OptionInfo);
    }
}

/** @REST /v5/dataprovider/factories/{factory}/provider (/v4/dataprovider/factories/{factory}/provider)

    This URI path provides access to a data provider created from a data provider factory

    @par Arguments
    This URI path element is reachable only if a provider can be created from the factory; to create the provider,
    the following hash argument is removed from the argument list before passing onward for processing:
    - \c provider_options: the options to be passed to the factory creation method to create the provider
*/
class DataProviderRestClassV5 inherits DataProviderRestClass {
    constructor(AbstractDataProvider provider) : DataProviderRestClass(provider) {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProvider child = provider.getChildProvider(arg);
        if (child) {
            return doGetDataProviderRestClass(child);
        }

        return doSubClassArg(arg, cx, ah);
    }

    private *QorusRestClass doSubClassArg(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET or PUT request
        if (cx.hdr.method == "GET" || cx.hdr.method == "PUT") {
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

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV5(provider);
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV5(name, type);
    }
}

/** @REST /v5/dataprovider/factories/{factory} (/v4/dataprovider/factories/{factory})

    This URI path provides access to data factory information
*/
class DataProviderFactoryRestClassV5 inherits DataProviderFactoryRestClass {
    constructor(string name, AbstractDataProviderFactory factory) : DataProviderFactoryRestClass(name, factory) {
    }

    string name() {
        return name;
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV5(provider);
    }
}

/** @REST /v5/dataprovider/factories (/v4/dataprovider/factories)

    This URI path provides access to data factory information
*/
class DataProviderFactoriesRestClassV5 inherits DataProviderFactoriesRestClass {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProviderFactory factory = DataProvider::getFactory(arg);
        if (factory) {
            return new DataProviderFactoryRestClassV5(arg, factory);
        }
    }
}

/** @REST /v5/dataprovider/types/.../{type}/type (/v4/dataprovider/types/.../{type}/type)

    This URI path provides access information for a particular data type
*/
class DataProviderTypeRestClassV5 inherits DataProviderTypeRestClass {
    constructor(string name, *AbstractDataProviderType type) : DataProviderTypeRestClass(name, type) {
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
            hash<auto> info = doGetInfo(ah);
            if (info.hasKey(arg)) {
                return new AttributeRestClass(info{arg});
            }
        }
    }

    /** @REST GET action=compare

        @par Description
        Takes a \c type argument and returns a boolean value:
        - \c True: the type given as an argument is compatible with the current type; i.e. a variable of the current
          type can be assigned to a value corresponding to the type passed as an argument
        - \c False: the type given as an argument is not compatible with the current type; i.e. a variable of the
          current type cannot be assigned to a value corresponding to the type passed as an argument without type
          errors

        @par Arguments
        This API takes the following hash argument (either as URI arguments or in the message body):
        - \c type: required; a string path to the other type (ex: \c "my/other/type")

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing or invalid \c "type" argument
        - <tt><b>404 Not Found</b></tt>: the given type cannot be found
    */
    hash<HttpHandlerResponseInfo> getCompare(hash<auto> cx, *hash<auto> ah) {
        if (ah.type.typeCode() != NT_STRING) {
            # will be converted to a 400 Bad Request response
            throw "REST-ARG-ERROR", sprintf("missing or invalid 'type' arg; got type %y (%y); expecting \"string\"",
                ah.type.type(), ah.type);
        }
        AbstractDataProviderType other_type;
        try {
            other_type = DataProvider::getTypeCache().getTypeEx(ah.type);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "PROVIDER-ERROR") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, type.isAssignableFrom(other_type));
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV5(name, type);
    }
}

/** @REST /v5/dataprovider/types (/v4/dataprovider/types)

    This URI path provides access to data type information
*/
class DataProviderTypesRestClassV5 inherits DataProviderTypesRestClass {
    constructor() {
    }

    constructor(DataProviderTypeEntry entry) : DataProviderTypesRestClass(entry) {
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *DataProviderTypeEntry child = entry.getChild(arg);
        if (child) {
            return new DataProviderTypesRestClassV5(child);
        }

        # check for field
        if (entry.getInfo().has_type && (*AbstractDataField field = entry.getType().getField(arg))) {
            DataProviderTypeEntry new_entry(entry.getPath(), arg);
            new_entry.setType(field.getType());
            return new DataProviderTypesRestClassV5(new_entry);
        }

        if (arg == "type") {
            return doGetDataProviderTypeRestClass(entry.getPath(), entry.getTypeEx());
        }
    }

    /** @REST GET action=listAll

        @par Description
        Returns information about the current data type
    */
    hash<HttpHandlerResponseInfo> getListAll(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, entry.listParentTypes());
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV5(name, type);
    }
}

/** @REST /v5/dataprovider/basetypes (/v4/dataprovider/basetypes)

    This URI path provides access to base data type information
*/
class DataProviderBaseTypesRestClassV5 inherits DataProviderBaseTypesRestClass {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProviderType type = BaseTypes{arg};
        if (type) {
            return doGetDataProviderTypeRestClass(arg, type);
        }
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV5(name, type);
    }
}

/** @REST /v5/dataprovider (/v4/dataprovider)

    This URI path provides access to data provider functionality
*/
class DataProviderBaseRestClassV5 inherits DataProviderBaseRestClass {
    private setup() {
        addClass(new DataProviderFactoriesRestClassV5());
        addClass(new DataProviderTypesRestClassV5());
        addClass(new DataProviderBaseTypesRestClassV5());
        addClass(new DataProviderRestClassV5(create_object("QorusApiDataProvider")));
    }

    /** @REST PUT action=compareTypes

        @SCHEMA
        @summary Compares two types for assignment compatibility

        @desc Compares two types for assignment compatibility; takes a \a base_type and a \a type argument and returns
        a boolean value if a value of type \a type can be assigned a variable of type \a base_type

        @params
        - base_type (hash QorusTypeInfo): hash describing the input or receiving type (type of variable to accept \
          \a type)
          - type (string): one of \c connection, \c datasource, \c factory, \c remote, or \c type
          - name (string): the name of the type, connection, factory, etc
          - path (*string): the path to the final object
          - subtype (*string): the subtype for \a type = \c connection
          - options (*hash): create option for \a type = \c factory
          - hasApiContext (*bool): \c True if the type is a factory with options to be handled in an API
            management context
        - type (hash QorusTypeInfo): a hash describing the output or sending type (type of value to be assigned to \
          \a base_type)

        @return (bool): True if \a type can be assigned to \a base_type, False if not

        @error (400): missing or invalid \c types argument; non-unique \c name in \c types list
        @error (404): the given type, factory, connection, etc cannot be found
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putCompareTypes(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, DataProviderBaseRestClassV5::checkTypeCompatibility(ah));
    }

    #! Returns True if ah.base_type accepts assignment from type ah.type
    static bool checkTypeCompatibility(hash<auto> ah) {
        bool reverse = ah.base_type.is_api_call && ah.type.is_api_call;
        AbstractDataProviderType base_type = DataProviderBaseRestClassV5::doGetType("base_type", ah);
        AbstractDataProviderType type = DataProviderBaseRestClassV5::doGetType("type", ah, reverse);
        # if the base type is an api call state using explicit args,
        # or the base type is anyt data provider action state,
        # then we always return True
        if ((ah.base_type.is_api_call && ah.base_type.use_args)
            || DataProviderActionTypes{ah.base_type.typeAction}) {
            return True;
        }
        QDBG_LOG("DataProviderBaseRestClassV5::checkTypeCompatibility() ah: %y", ah);
        QDBG_LOG("DataProviderBaseRestClassV5::checkTypeCompatibility() base_type: %y (%y) type: %y (%y) reverse: %y",
            base_type.className(), keys base_type.getFields(), type.className(), keys type.getFields(), reverse);
        if (reverse) {
            if (!base_type.isAssignableFrom(type)) {
                return False;
            }
            base_type = DataProviderBaseRestClassV5::doGetType("base_type", ah, True);
            type = DataProviderBaseRestClassV5::doGetType("type", ah);
        }
        if (DataProviderSearchTypes{ah.type.typeAction} && !ah.type.search_options.requires_result) {
            type = type.getOrNothingType();
        }
        QDBG_LOG("DataProviderBaseRestClassV5::checkTypeCompatibility() returning %y",
            base_type.isAssignableFrom(type));
        return base_type.isAssignableFrom(type);
    }

    /** @REST PUT action=compareManyTypes

        @SCHEMA
        @summary Compares multiple types for compatibility and returns the result of each comparison

        @desc Takes a list of hashes in \c types giving \c type and \c base_type information to compare and returns \
        a list of the results of each comparison.

        @params
        - types (hash[hash QorusTypeComparisonInfo] QorusTypeComparisonSetInfo): a hash of hashes keyed by a unique \
          user-defined comparison identifier
          - base_type (hash QorusTypeInfo): hash describing the input or receiving type (type of variable to accept \
            \a type)
          - type (hash QorusTypeInfo): a hash describing the output or sending type (type of value to be assigned to \
            \a base_type)

        @return (hash[bool] QorusBooleanSetInfo): Returns a hash keyed by hash keys in the \c types argument \
        where the values are boolean values of the results of the type comparisons

        @error (400): missing or invalid \c types argument; non-unique \c name in \c types list
        @error (404): the given type, factory, connection, etc cannot be found
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putCompareManyTypes(hash<auto> cx, *hash<auto> ah) {
        if (ah.types.typeCode() != NT_HASH) {
            throw "REST-ARG-ERROR", sprintf("missing or invalid \"types\" arg; got type %y (%y); expecting \"hash\"",
                ah.types.type(), ah.types);
        }

        # the return value
        hash<string, bool> rv;
        foreach hash<auto> i in (ah.types.pairIterator()) {
            try {
                rv{i.key} = DataProviderBaseRestClassV5::checkTypeCompatibility(i.value);
            } catch (hash<ExceptionInfo> ex) {
                throw ex.err, sprintf("%s (checking \"types\" key %y = %y)", ex.desc, i.key, i.value), ex.arg;
            }
        }

        return RestHandler::makeResponse(200, rv);
    }

    static AbstractDataProviderType doGetType(string key, *hash<auto> ah, *bool reverse) {
        try {
            if (ah{key}.typeCode() != NT_HASH) {
                throw "REST-ARG-ERROR", sprintf("missing or invalid %y arg; got type %y (%y); expecting \"hash\"",
                    key, ah{key}.type(), ah{key});
            }
            return _priv_get_type_from_hash(ah{key}, key, reverse);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "PROVIDER-ERROR" || ex.err == "CONNECTION-ERROR" || ex.err == "INVALID-CHILD-PROVIDER") {
                throw "REST-NOT-FOUND-ERROR", sprintf("%s: %s", ex.err, ex.desc);
            }
            if (ex.err == "INVALID-ARGUMENT") {
                throw "REST-ARG-ERROR", sprintf("%y arg: %s", key, ex.desc);
            }
            rethrow;
        }
    }
}

/** @REST /v5/orders/{id} (/v4/orders/{id})

    This REST URI path provides actions and information about specific workflow orders.
*/
class WorkflowOrderInstanceRestClassV5 inherits WorkflowOrderInstanceRestClassV4 {
    constructor(hash<auto> wf, int api_version = 5)
        : WorkflowOrderInstanceRestClassV4(WorkflowOrderInstanceRestClassV4::internAddData(wf), api_version) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (name == "staticdata_type") {
            return doGetDataProviderTypeRestClass(sprintf("staticdata hash for workflow %s v%s (%d)", wf.name,
                    wf.version, wf.workflowid), wf.staticdata_type_path
                ? UserApi::getTypeFromPath(wf.staticdata_type_path)
                : AbstractDataProviderType::get("hash<auto>"));
        }

        return WorkflowOrderInstanceRestClassV4::subClassImpl(name, cx, ah);
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV5(name, type);
    }
}

/** @REST /v5/orders (/v4/orders)

    This URI path provides information and actions related to workflow order data.
*/
class GlobalOrderRestClassV5 inherits GlobalOrderRestClassV4 {
    private *QorusRestClass internGetOrderInstanceRestClass(hash<auto> h) {
        return new WorkflowOrderInstanceRestClassV5(h);
    }
}

/** @REST /v5/workflows/{id_or_name} (/v4/workflows/{id_or_name})

    This REST URI path provides actions and information about a particular workflow.
*/
class WorkflowDefinitionRestClassV5 inherits WorkflowDefinitionRestClassV4 {
    constructor(hash<auto> wf) : WorkflowDefinitionRestClassV4(wf) {
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (name == "staticdata_type") {
            return doGetDataProviderTypeRestClass(sprintf("staticdata hash for workflow %s v%s (%d)", wf.name,
                    wf.version, wf.workflowid), wf.staticdata_type_path
                ? UserApi::getTypeFromPath(wf.staticdata_type_path)
                : AbstractDataProviderType::get("hash<auto>"));
        }

        return WorkflowDefinitionRestClassV4::subClassImpl(name, cx, ah);
    }

    private QorusRestClass doGetDataProviderTypeRestClass(string name, *AbstractDataProviderType type) {
        return new DataProviderTypeRestClassV5(name, type);
    }
}

/** @REST /v5/workflows (/v4/workflows)

    This URI path allows workflows to be queried and for actions on multiple workflows to be performed;
    this is the URI path parent of workflow-specific actions as well.
*/
class WorkflowRestClassV5 inherits WorkflowRestClassV4 {
    private *QorusRestClass internGetOrderInstanceRestClass(hash<auto> h) {
        return new WorkflowOrderInstanceRestClassV5(h);
    }

    private *QorusRestClass internGetWorkflowDefinitionSubclass(hash<auto> wf) {
        return new WorkflowDefinitionRestClassV5(wf);
    }

    /** @REST GET

        @par Description
        Returns information about workflows

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c deprecated: optional; parsed with @ref Qore::parse_boolean(); if @ref False then no deprecated workflows
          will be returned; default @ref True
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of workflow names is
          returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of
          workflow names and descriptions is returned
        - \c date: optional; parsed as a date; the minimum date for historical workflow order overview information;
          if omitted then defaults to the past 24 hours
        - \c sqlcache: optional; parsed with @ref Qore::parse_boolean(); if @ref False then no SQL cache will be used
          for historical info; default @ref True
        - \c tags: optional; a hash of tags to match; only workflows matching at least one of the tags will be
          returned; use <tt>tag=value</tt> format as the value of this option
        - \c tag_case_insensitive: optional; parsed with @ref Qore::parse_boolean(); if @ref True then tag value
          comparisons are made with case-insensitive comparisons
        - \c tag_partial_match: optional; parsed with @ref Qore::parse_boolean(); if @ref True then tag value
          comparisons succeed if the value given as the tag value appears anywhere in the object's tag of the same
          name

        @par Return Value
        If neither \a list nor \a short are used, then a list of hashes is returned, one element for each
        workflow; each hash in the returned list represents a workflow as a @ref rest_workflow_description_hash
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        ah."deprecated" = exists ah."deprecated" ? parse_boolean(ah."deprecated") : True;

        if (*hash<HttpHandlerResponseInfo> err = parseTagOptions(\ah)) {
            return err;
        }

        if (exists ah."list" && parse_boolean(ah."list")) {
            return RestHandler::makeResponse(200,
                (map $1.name, WorkflowRestClass::staticGetWorkflowMetadata(ah."deprecated", 5, ah)));
        }

        if (exists ah.short && parse_boolean(ah.short)) {
            return RestHandler::makeResponse(200,
                (map sprintf("%s v%s (%d) autostart: %d", $1.name, $1.version, $1.workflowid, $1.autostart),
                    WorkflowRestClass::staticGetWorkflowMetadata(ah."deprecated", 5, ah)));
        }

        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;

        return RestHandler::makeResponse(200,
            WorkflowRestClass::staticGetWorkflows(ah."date", ah.sqlcache, ah."deprecated", 5, ah));
    }
}
