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

/** @page rest_api_page_v2 Qorus REST API v2

    @tableofcontents

    @section rest_api_v2_overview Qorus REST API v2 Overview

    @subsection rest_api_v2_new REST API v2 New functionality

    The REST API v2 introduces the following new functionality:
    - @ref rest_api_v2_slas for system SLA information

    @subsection rest_api_v2_changes REST API v2 Changes from the v1 API

    REST API v2 has the following differences from @ref rest_api_page_v1 "REST API v1":
    - @ref rest_api_GET_v2_jobs adds the \c "sla" key, if any SLA is associated with the job
    - @ref rest_api_GET_v2_jobs__id_or_name_ adds the \c "sla" key, if any SLA is associated with the job
    - @ref rest_api_DELETE_v2_orders_purgeSensitiveData was added to allow for @ref sensitive_data "sensitive data" to be deleted based on sensitive key types and values
    - @ref rest_api_GET_v2_orders_searchSensitiveData was added to allow for @ref sensitive_data "sensitive data" to be searched based on sensitive key types and values
    - @ref rest_api_GET_v2_orders__id_ adds the following attribute:
      - \c has_sensitive_data: @ref True "True" if the order has sensitive data, @ref False "False" if not; this key is always returned with a valid response
      - \c sensitive_data (only if present on the order and when the request is served over a secure connection and if the user has permission to read sensitive data)
    - @ref rest_api_GET_v2_orders__id__yamlDynamicData was added to allow for order data be be returned as serialized YAML strings
    - @ref rest_api_GET_v2_orders__id__yamlStaticData was added to allow for order data be be returned as serialized YAML strings
    - @ref rest_api_GET_v2_orders__id__yamlSensitiveData was added to allow for order data be be returned as serialized YAML strings
    - @ref rest_api_PUT_v2_orders__id__yamlDynamicData was added to allow for order data be be updated as serialized YAML strings
    - @ref rest_api_PUT_v2_orders__id__yamlStaticData was added to allow for order data be be updated as serialized YAML strings
    - @ref rest_api_PUT_v2_orders__id__yamlSensitiveData was added to allow for order data be be updated as serialized YAML strings
    - @ref rest_api_PUT_v2_orders__id__sensitiveData was added to allow @ref sensitive_data "sensitive data" to be manipulated from the REST API
    - @ref rest_api_GET_v2_services adds the \c "sla" key in service methods, if any SLA is associated with the method
    - @ref rest_api_GET_v2_services__id_or_name_ adds the \c "sla" key in service methods, if any SLA is associated with the method
    - @ref rest_api_GET_v2_system adds the following attribute:
      - \c api_version
    - @ref rest_api_PUT_v2_system_props_replaceAll was added to allow all system properties to be replaced in a single call
    - @ref rest_api_POST_v2_workflows__id_or_name__createOrder adds support for the following arguments:
      - [\c global_unique_key]: (optional hash) a hash giving one or more unique @ref wf_keylist "order keys" for the order (across all workflows regardless of workflowid, name, or version); if this key already exists for any order
          in the system, then the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and the value is the unique key value;
          this value will also be created as an order key
      - [\c sensitive_data]: a hash of sensitive data information for the workflow; this key can only be used when submitting the data over a secure (encrypted) connection; the keys are sensitive data key types, values are hashes keyed by sensitive data values, and the hash values have the following keys:
        - [\c aliases]: (list of strings) zero or more string aliases for the sensitive data
        - \c data: (hash) the sensitive data hash itself
        - [\c meta]: (hash) a hash of metadata for the sensitive data with the following recommended keys (recommended keys are not enforced by the API itself):
          - [\c PURPOSE]: free-form information about the purpose of the sensitive data
          - [\c CATEGORIES]: free-form information about the categories of sensitive data
          - [\c RECIPIENTS]: free-form information about the recipients or recipient catories of sensitive data
          - [\c STORAGE]: free-form information about the storage time or rules for sensitive data
      - [\c workflow_specific_unique_key]: (optional string) a hash giving one or more unique @ref wf_keylist "order keys" for the particular workflowid (which matches a unique name and workflow version); if this key
          already exists for an order with the target workflowid, then the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and
          the value is the unique key value; this value will also be created as an order key
      - [\c workflow_unique_key]: (optional string) a hash giving one or more unique @ref wf_keylist "order keys" for the particular workflow by name only (across all workflows with the same name regardless of version);
          if this key already exists for a workflow order with the same name, then the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a
          valid order key, and the value is the unique key value; this value will also be created as an order key
    - @ref rest_api_POST_v2_workflows__id_or_name__execSynchronous adds support for the following arguments:
      - [\c global_unique_key]: (optional hash) a hash giving one or more unique @ref wf_keylist "order keys" for the order (across all workflows regardless of workflowid, name, or version); if this key already exists for any order
          in the system, then the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and the value is the unique key value;
          this value will also be created as an order key
      - [\c sensitive_data]: a hash of sensitive data information for the workflow; this key can only be used when submitting the data over a secure (encrypted) connection; the keys are sensitive data key types, values are hashes keyed by sensitive data values, and the hash values have the following keys:
        - [\c aliases]: (list of strings) zero or more string aliases for the sensitive data
        - \c data: (hash) the sensitive data hash itself
        - [\c meta]: (hash) a hash of metadata for the sensitive data with the following recommended keys (recommended keys are not enforced by the API itself):
          - [\c PURPOSE]: free-form information about the purpose of the sensitive data
          - [\c CATEGORIES]: free-form information about the categories of sensitive data
          - [\c RECIPIENTS]: free-form information about the recipients or recipient catories of sensitive data
          - [\c STORAGE]: free-form information about the storage time or rules for sensitive data
      - [\c workflow_specific_unique_key]: (optional string) a hash giving one or more unique @ref wf_keylist "order keys" for the particular workflowid (which matches a unique name and workflow version); if this key
          already exists for an order with the target workflowid, then the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and
          the value is the unique key value; this value will also be created as an order key
      - [\c workflow_unique_key]: (optional string) a hash giving one or more unique @ref wf_keylist "order keys" for the particular workflow by name only (across all workflows with the same name regardless of version);
          if this key already exists for a workflow order with the same name, then the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a
          valid order key, and the value is the unique key value; this value will also be created as an order key
*/

/** @REST /v2 (/)

    This URI path implements v2 of the Qorus REST API
*/
class V2RestClass inherits QorusRestClass {
    private:internal {
        # class hash
        hash<auto> ch;
    }

    constructor() {
        addClass(new WorkflowRestClassV2());
        addClass(new GlobalOrderRestClassV2());
        addClass(new GlobalWorkflowExecRestClass());
        addClass(new ServiceRestClassV2());
        addClass(new JobRestClassV2());
        addClass(new SystemRestClassV2());
        addClass(new UsersRestClass());
        addClass(new RolesRestClass());
        addClass(new GroupsRestClass());
        addClass(new StepRestClass());
        addClass(new FunctionRestClass());
        addClass(new ClassRestClass());
        addClass(new ConstantRestClass());
        addClass(new DebugRestClass());
        addClass(new JobResultsRestClass());
        addClass(new LogsRestClass());
        addClass(new RemoteRestClass());
        addClass(new PermsRestClass());
        addClass(new ErrorsRestClass());
        addClass(new MappersRestClass());
        addClass(new MapperTypesRestClass());
        addClass(new AsyncQueuesRestClass());
        addClass(new ValueMapsRestClass());
        addClass(new ReleasesRestClass());
        addClass(new SyncEventTypesRestClass());
        addClass(new SlasRestClass());
        addClass(new LogoutRestClass());
    }

    string name() {
        return "v2";
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

/** @REST /v2/slas/{sla}

    This REST URI path provides actions and information about a particular Qorus SLA
*/
class SlaRestClass inherits QorusRestClass {
    private {
        hash<SlaInfo> h;
    }

    constructor(hash<SlaInfo> h) {
        self.h = h;
    }

    string name() {
        return h.name;
    }

    /** @REST GET

        @par Description
        Returns information about the SLA to the calling user.

        @par Return Value
        A @ref OMQ::SlaInfo hash of the SLA
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, h);
    }

    /** @REST GET?action=events

        @par Description
        Returns a list of SLA events matching the search arguments; the archive schema is also searched if fewer than the maximum number of results is found in the main schema.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c desc: return the results in descending order
        - \c err: the error string of unsucessful SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c errdesc: the error description string of unsucessful SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c limit: max number of rows to return, if not given, then the value of the \a "row-limit" option is used (default: 100)
        - \c mindate: minimum SLA event timestamp (inclusive, meaning \c ">=" comparisons used)
        - \c maxdate: maximum SLA event timestamp (exclusive, meaning \c "<" comparisons used)
        - \c offset: row offset
        - \c producer: the producer string of SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c sort: columns for sorting the results

        @par Return Value
        A list of hashes is returned, one element for each matching SLA event; each element in the returned list is an @ref OMQ::SlaEventInfo hash
    */
    hash<auto> getEvents(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, sysinfo.searchSlaEvents(ah + ("slaid": h.slaid) - "name"));
    }

    /** @REST GET?action=performance

        @par Description
        Returns a list of SLA events matching the search arguments; the archive schema is also searched if fewer than the maximum number of results is found in the main schema.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c err: the error string of unsucessful SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c errdesc: the error description string of unsucessful SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c grouping: (optional) possible values for reporting performance statistics:
          - \c "hourly": hourly grouping
          - \c "daily": daily grouping
          - \c "monthly": monthly grouping
          - \c "yearly": yearly grouping
        - \c maxdate: maximum SLA event timestamp (exclusive, meaning \c "<" comparisons used)
        - \c mindate: minimum SLA event timestamp (inclusive, meaning \c ">=" comparisons used)
        - \c producer: the producer string of SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c success: filter for sucessful calls (1) or errored calls (0)

        @return an empty list if no events are matched, otherwise a list of @ref OMQ::SlaPerformanceInfo hashes
    */
    hash<auto> getPerformance(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, sysinfo.getSlaPerformance(ah + ("slaid": h.slaid) - "name"));
    }

    /** @REST PUT?action=setMethod

        @par Description
        Sets the current SLA against the user service method specified with the required arguments; after this call,
        user service calls to the specified method will be tracked with success and failure and call times.

        @par Arguments
        This API takes the following required hash arguments (either as URI arguments or in the message body):
        - \c service (string): the name of the user service
        - \c method (string): the name of the service method

        @par Return Value
        A hash with the following keys is returned:
        - \c service (string): the name of the user service
        - \c method (string): the name of the service method
        - \c slaid (int): the SLA ID set on the given user service method
    */
    hash<auto> putSetMethod(hash<auto> cx, *hash<auto> ah) {
        if (ah.service.typeCode() != NT_STRING)
            throw "SLA-ERROR", sprintf("missing or invalid \"service\" key giving the user service name; got %y (type %s) instead", ah.service, ah.service.type());

        if (ah.method.typeCode() != NT_STRING)
            throw "SLA-ERROR", sprintf("missing or invalid \"method\" key giving the method name; got %y (type %s) instead", ah.method, ah.method.type());

        Qorus.qmm.setMethodSla(ah.service, ah.method, h.slaid);
        return RestHandler::makeResponse(200, ah.("service", "method") + ("slaid": h.slaid));
    }

    /** @REST PUT?action=removeMethod

        @par Description
        Removes the current SLA from the user service method specified with the required arguments (if associated).

        @par Arguments
        This API takes the following required hash arguments (either as URI arguments or in the message body):
        - \c service (string): the name of the user service
        - \c method (string): the name of the service method

        @par Return Value
        A hash with the following keys is returned:
        - \c service (string): the name of the user service
        - \c method (string): the name of the service method
        - \c slaid (int): the current SLA ID
        - \c removed (bool): @ref True "True" if removed, @ref False "False" if not (not associated)
    */
    hash<auto> putRemoveMethod(hash<auto> cx, *hash<auto> ah) {
        if (ah.service.typeCode() != NT_STRING)
            throw "SLA-ERROR", sprintf("missing or invalid \"service\" key giving the user service name; got %y (type %s) instead", ah.service, ah.service.type());

        if (ah.method.typeCode() != NT_STRING)
            throw "SLA-ERROR", sprintf("missing or invalid \"method\" key giving the method name; got %y (type %s) instead", ah.method, ah.method.type());

        bool removed = Qorus.qmm.setMethodSla(ah.service, ah.method);
        return RestHandler::makeResponse(200, ah.("service", "method") + ("slaid": h.slaid, "removed": removed));
    }

    /** @REST PUT?action=setJob

        @par Description
        Sets the current SLA against the job specified with the required arguments; after this call,
        job instance execution will be tracked with success and failure and call times.

        @par Arguments
        This API takes the following required hash argument (either as a URI argument or in the message body):
        - \c job (string): the name of the job

        @par Return Value
        A hash with the following keys is returned:
        - \c job (string): the name of the job
        - \c slaid (int): the SLA ID set on the given job
    */
    hash<auto> putSetJob(hash<auto> cx, *hash<auto> ah) {
        if (ah.job.typeCode() != NT_STRING)
            throw "SLA-ERROR", sprintf("missing or invalid \"job\" key giving the job name; got %y (type %s) instead", ah.job, ah.job.type());

        Qorus.qmm.setJobSla(ah.job, h.slaid);
        return RestHandler::makeResponse(200, ah.("job",) + ("slaid": h.slaid));
    }

    /** @REST PUT?action=removeJob

        @par Description
        Removes the current SLA from the job specified with the required arguments (if associated).

        @par Arguments
        This API takes the following required hash argument (either as a URI argument or in the message body):
        - \c job (string): the name of the job

        @par Return Value
        A hash with the following keys is returned:
        - \c job (string): the name of the job
        - \c slaid (int): the SLA ID set on the given job
        - \c removed (bool): @ref True "True" if removed, @ref False "False" if not (not associated)
    */
    hash<auto> putRemoveJob(hash<auto> cx, *hash<auto> ah) {
        if (ah.job.typeCode() != NT_STRING)
            throw "SLA-ERROR", sprintf("missing or invalid \"job\" key giving the job name; got %y (type %s) instead", ah.job, ah.job.type());

        bool removed = Qorus.qmm.setJobSla(ah.job);
        return RestHandler::makeResponse(200, ah.("job",) + ("slaid": h.slaid, "removed": removed));
    }

    /** @REST DELETE
        @SCHEMA
        @summary Deletes the SLA from the system

        @desc Deletes the SLA from the system

        @return (hash SlaInfo): hash of the SLA created or of the existing SLA if all arguments match an existing \
        SLA exactly
        - slaid (int): the ID of the SLA
        - name (string): the name of the SLA
        - units (string): describes the meaning of SLA event values (allowed values: \c "seconds" and \c "other")
        - description (string): the description of the SLA
        - methods (*list<hash SlaServicveMethodInfo>): list of service methods with the SLA
          - serviceid (int): the service ID
          - type (string): the service type; either \c "system" or \c "user"
          - service_name (string): the service name
          - service_methodid (int): the service methods ID
          - method_name (string): the service method name
        - jobs (*list<hash SlaJobInfo>): list of jobs with the SLA
          - jobid (int): the job ID
          - name (string): the job name
        @ENDSCHEMA
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        Qorus.qmm.deleteSla(h.slaid);
        return RestHandler::makeResponse(200, h);
    }
}

/** @REST /v2/slas

    This REST URI path provides actions and information about Qorus SLAs
*/
class SlasRestClass inherits QorusRestClass {
    string name() {
        return "slas";
    }

    static softint staticGetSlaId(softstring arg, bool check = False, *reference sh) {
        if (arg =~ /[[:alpha:]]/u) {
            *hash<auto> h = Qorus.qmm.rLookupSla(arg);
            if (h) {
                sh = h;
                return sh.slaid;
            }
            if (check)
                throw "SLA-ARG-ERROR", sprintf("can't find any sla %y", arg);
            return 0;
        }

        if (check) {
            *hash<auto> h = Qorus.qmm.lookupSla(arg);
            if (!h)
                throw "SLA-ARG-ERROR", sprintf("there is no SLA with slaid %d", arg);
            sh = h;
        }

        return arg;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<SlaInfo> h = Qorus.qmm.lookupSla(staticGetSlaId(arg, True));
        if (h)
            return new SlaRestClass(h);
    }

    /** @REST GET

        @par Description
        Returns information about SLAs to the calling user.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of workflow names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of workflow names and descriptions is returned

        @par Return Value
        If neither \a list nor \a short are used, then a list of hashes is returned, one element for each SLA; each hash in the returned list represents an SLA as a @ref OMQ::SlaInfo hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = Qorus.qmm.getSlaMap();

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.name, h.iterator()));

        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200, (map sprintf("%s (%d) %s: %s", $1.name, $1.slaid, $1.units, $1.description), h.iterator()));

        return RestHandler::makeResponse(200, (map $1, h.iterator()));
    }

    /** @REST GET?action=events

        @par Description
        Returns a list of SLA events matching the search arguments; the archive schema is also searched if fewer than the maximum number of results is found in the main schema.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c desc: return the results in descending order
        - \c err: the error string of unsucessful SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c errdesc: the error description string of unsucessful SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c name: the name of the SLA; can be a list of names or a string with \c "%" characters for SQL like matching
        - \c limit: max number of rows to return, if not given, then the value of the \a "row-limit" option is used (default: 100)
        - \c mindate: minimum SLA event timestamp (inclusive, meaning \c ">=" comparisons used)
        - \c maxdate: maximum SLA event timestamp (exclusive, meaning \c "<" comparisons used)
        - \c offset: row offset
        - \c producer: the producer string of SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c slaid: the SLA ID, can be a list of IDs
        - \c sort: columns for sorting the results
        - \c success: filter for sucessful calls (1) or errored calls (0)

        @par Return Value
        A list of hashes is returned, one element for each matching SLA event; each element in the returned list is an @ref OMQ::SlaEventInfo hash
    */
    hash<auto> getEvents(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, sysinfo.searchSlaEvents(ah));
    }

    /** @REST GET?action=performance

        @par Description
        Returns a list of SLA events matching the search arguments; the archive schema is also searched if fewer than the maximum number of results is found in the main schema.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c err: the error string of unsucessful SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c errdesc: the error description string of unsucessful SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c grouping: (optional) possible values for reporting performance statistics:
          - \c "hourly": hourly grouping
          - \c "daily": daily grouping
          - \c "monthly": monthly grouping
          - \c "yearly": yearly grouping
        - \c name: the name of the SLA; can be a list of names or a string with \c "%" characters for SQL like matching
        - \c maxdate: maximum SLA event timestamp (exclusive, meaning \c "<" comparisons used)
        - \c mindate: minimum SLA event timestamp (inclusive, meaning \c ">=" comparisons used)
        - \c producer: the producer string of SLA events; can be a list of strings or a string with \c "%" characters for SQL like matching
        - \c slaid: the SLA ID, can be a list of IDs
        - \c success: filter for sucessful calls (1) or errored calls (0)

        @return an empty list if no events are matched, otherwise a list of @ref OMQ::SlaPerformanceInfo hashes
    */
    hash<auto> getPerformance(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, sysinfo.getSlaPerformance(ah));
    }

    /** @REST POST

        @SCHEMA
        @summary Creates a system SLA according to the arguments

        @desc Creates a system SLA according to the arguments

        @params
        - name (string): the unique name of the SLA
        - units (*string): describes the meaning of SLA event values (allowed values: \c "seconds" and \c "other"; \
          default: \c "seconds")
        - description (string): the description of the SLA

        @return (hash SlaInfo): hash of the SLA created or of the existing SLA if all arguments match an existing \
        SLA exactly
        - slaid (int): the ID of the SLA
        - name (string): the name of the SLA
        - units (string): describes the meaning of SLA event values (allowed values: \c "seconds" and \c "other")
        - description (string): the description of the SLA
        - methods (*list<hash SlaServicveMethodInfo>): list of service methods with the SLA
          - serviceid (int): the service ID
          - type (string): the service type; either \c "system" or \c "user"
          - service_name (string): the service name
          - service_methodid (int): the service methods ID
          - method_name (string): the service method name
        - jobs (*list<hash SlaJobInfo>): list of jobs with the SLA
          - jobid (int): the job ID
          - name (string): the job name

        @error (400): the given SLA name already exists; invalid or missing argument
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        if (ah.name.typeCode() != NT_STRING)
            throw "SLA-ARG-ERROR", sprintf("missing or invalid \"name\" key; got %y (type %s) instead", ah.name,
                ah.name.type());

        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "name");
        if (exists error) {
            return error;
        }

        if (!ah.hasKey("units"))
            ah.units = "seconds";
        else {
            if (ah.units.typeCode() != NT_STRING)
                throw "SLA-ARG-ERROR", sprintf("missing or invalid \"units\" key; got %y (type %s) instead", ah.units,
                    ah.units.type());
            if (!SlaUnits{ah.units})
                throw "SLA-ARG-ERROR", sprintf("invalid \"units\" value %y; acceptable values: %y", ah.units,
                    keys SlaUnits);
        }
        if (ah.description.typeCode() != NT_STRING)
            throw "SLA-ARG-ERROR", sprintf("missing or invalid \"description\" key; got %y (type %s) instead",
                ah.description, ah.description.type());
        return RestHandler::makeResponse(200, cast<hash<SlaInfo>>((
            "slaid": Qorus.qmm.createSla(ah.name, ah.units, ah.description),
            "name": ah.name,
            "units": ah.units,
            "description": ah.description,
        )));
    }
}

/** @REST /v2/services/{id_or_name} (/services/{id_or_name})

    This REST URI path provides actions and information related to Qorus services;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/

    /** @REST GET

        @par Description
        Returns information about the current service

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c lib_source: (optional) parsed with @ref Qore::parse_boolean(); if @ref True "True", then the source code for all library objects is returned
        - \c method_source: (optional) parsed with @ref Qore::parse_boolean(); if @ref True "True", then the source code for all methods is returned in the \c body key in each @ref rest_service_method_hash_v2

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
        - \c enabled: a boolean flag indicating if the service is enabled or not; disabled services cannot be loaded
        - \c created: the date/time the service was created
        - \c modified: the date/time the service was last modified
        - \c mappers: a list of @ref mappers "mappers" associated with the service (can be @ref nothing); each mapper element is a @ref rest_mapper_hash
        - \c vmaps: a list of @ref value-maps "value maps" associated with the service (can be @ref nothing); each value map element is a @ref rest_vmap_hash
        - \c latest: a boolean flag indicating if the current contextual service is the latest service of its type and name
        - \c methods: a list of @ref rest_service_method_hash_v2 elements
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
        - \c state: a hash of saved service state data (if any); see @ref svc_save_state_data() for more info
    */

/** @REST /v2/services (/services)

    This REST URI path provides actions and information related to Qorus services.
*/
class ServiceRestClassV2 inherits ServiceRestClass {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = ServiceRestClass::staticGetServiceId(arg);
        *hash<auto> svc = ServiceRestClass::staticGetService(cx, id, ah, 2);
        if (!svc)
            return;

        return new ServiceDefinitionRestClass(svc);
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
        - \c manual_autostart:  boolean flag set if the \c autostart value has been changed manually, in which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
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
        return RestHandler::makeResponse(200, ServiceRestClass::staticGetServices(cx, ah, 2));
    }
}

/** @REST /v2/jobs/{id_or_name} (/jobs/{id_or_name})

    This REST API path provides actions and information related to specific jobs;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/

    /** @REST GET

        @par Description
        Returns a hash of job information

        @par Return Value
        Returns a @ref rest_job_description_hash_v2 for the current job, plus the following key:
        - \c state: a hash of job state data (if any)
    */


/** @REST /v2/jobs (/jobs)

    This REST API path provides actions and information related to Qorus jobs.
*/
class JobRestClassV2 inherits JobRestClass {
    static *hash<auto> staticGetJob(hash<auto> cx, *hash<auto> ah, softint id, int apiver = 2) {
        *hash<auto> rv = JobRestClass::staticGetJob(cx, ah, id, apiver);
        if (rv && (*int slaid = Qorus.qmm.getJobSlaHash(){id}) && (*hash<SlaInfo> slah = Qorus.qmm.getSlaMap(){slaid})) {
            rv.sla = slah.name;
        }
        return rv;
    }

    private static list staticGetJobs(hash<auto> cx, *hash<auto> ah, int apiver = 2) {
        list rv = JobRestClass::staticGetJobs(cx, ah, apiver);
        if (rv) {
            hash<string, int> slah = Qorus.qmm.getJobSlaHash();
            *hash<string, hash<SlaInfo>> slam = Qorus.qmm.getSlaMap();
            foreach hash<auto> jh in (\rv) {
                if ((*int slaid = slah{jh.jobid}) && (*hash<SlaInfo> slaih = slam{slaid}))
                    jh.sla = slaih.name;
            }
        }
        return rv;
    }

    private QorusRestClass internGetJobDefinition(hash<auto> job) {
        return new JobDefinitionRestClass(job);
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = JobRestClass::staticGetJobId(arg);
        *hash<auto> job = JobRestClassV2::staticGetJob(cx, ah, id);
        if (!job)
            return;

        hash<auto> ji = Qorus.jobManager.getActiveInfo();
        JobRestClass::fixJob(\job, ji.(job.name), cx);

        return internGetJobDefinition(job);
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
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, JobRestClassV2::staticGetJobs(cx, ah));
    }
}

/** @REST /v2/system (/system)

    This REST URI path provides actions and information for system functionality
*/
class SystemRestClassV2 inherits SystemRestClass {
    public {
        const SubClasses = SystemRestClass::SubClasses + (
            "props": "SystemPropertiesRestClassV2",
        );
    }

    hash<auto> internGetInfo(hash<auto> cx) {
        return SystemRestClass::internGetInfo(cx) + (
            "api_version": "v2",
        );
    }

    /** @REST GET

        @par Description
        Returns a hash of system information

        @par Return Value
        This API returns a hash with the following keys:
        - \c instance-key: (string) the system instance key
        - \c session-id: (int) the application session id
        - \c omq-version: (string) the version of the server
        - \c qore-version: (string) the version of the underlying qore library used
        - \c modules: (hash) a hash of module info as returned by @ref Qore::get_module_hash()
        - \c datamodel-version: (string) the version of the datamodel expected by the server
        - \c omq-schema: (string) \c "user@dbname" string for the system \c "omq" datasource
        - \c omq-driver: (string) driver name for the system \c "omq" datasource
        - \c omq-db-version: (string) database server version for the system \c "omq" datasource
        - \c omquser-schema: (string) \c "user@dbname" string for the \c "omquser" datasource
        - \c omquser-driver: (string) driver name for the \c "omquser" datasource
        - \c omquser-db-version: (string) database server version for the \c "omquser" datasource
        - \c starttime: (date) date and time the server was started
        - \c hostname: (string) hostname where the server is running
        - \c pid: (int) PID of the server process
        - \c threads: (int) count of currently active threads
        - \c schema-properties: (hash) hash of actual schema properties (identical to system property domain \c "omq")
        - \c omq_dir: (string) the application directory or \c "LSB" for Linux Standard Base filesystem integration
        - \c logfile: (string) path to system log file
        - \c http_logfile: (string) path to system HTTP server log file
        - \c monitoring_logfile: (string) path to system monitoring log file
        - \c alert_logfile: (string) path to system alert log file
        - \c cache_size: (int) the current size of the workflow order data cache
        - \c shutting_down: (bool) a flag if the system is shutting down
        - \c build-type: (string) the type of build of the server (\c "Production" or \c "Debug")
        - \c runtime-properties: (hash) a hash of runtime properties
        - \c alert-summary: (hash) a hash with the following keys:
          - \c transient: (int) number of transient alerts
          - \c ongoing: (int) number of ongoing alerts
        - \c debug: (bool) system debugging flag (when @ref True then more information is provided with exceptions)
        - \c health: (string) a string color code for the health of the system with the following values:
          - \c "GREEN": good health
          - \c "YELLOW": warning
          - \c "RED": problems
        - \c system_log_url: (string) a URL to the websocket source for the main system log
        - \c audit_log_url: (string) a URL to the websocket source for the audit log
        - \c http_log_url: (string) a URL to the websocket source for the HTTP server log
        - \c mon_log_url: (string) a URL to the websocket source for the monitoring log
        - \c alert_log_url: (string) a URL to the websocket source for the alert log
        - \c api_version: (string) the REST API version: \c "v2"
    */

    private hash<string, string> doGetSubClasses() {
        return SubClasses;
    }
}

/** @REST /v2/system/props (/system/props)

    This REST URI path provides actions and information related to a @ref sysprops "system properties".
*/
class SystemPropertiesRestClassV2 inherits SystemPropertiesRestClass {
    /** @REST PUT action=replaceAll

        @par Description
        Replaces all system property keys in one atomic operation

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c props: (required) must be a hash keyed by domain assigned to key-value property hashes; any \c "omq" domain is ignored

        @par Return Value
        This API returns the system property hash passed as an argument.

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c PROP-ERROR: serialized value exceeds 4000 bytes (column limit) or invalid type assigned to domain key
    */
    hash<auto> putReplaceAll(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        rlog(cx);
        if (!ah.props || ah.props.typeCode() != NT_HASH)
            throw "SYSTEM-PROPERTY-ERROR", "missing \"props\" hash argument to system/props?action=replaceAll";
        return RestHandler::makeResponse(200, Qorus.props.replaceAll(ah.props));
    }
}

/** @REST /v2/workflows/{id_or_name}/orders (/workflows/{id_or_name}/orders)

    This REST URI path provides actions and information about workflow orders for the current workflow.
*/
class WorkflowOrderRestClassV2 inherits WorkflowOrderRestClass {
    constructor(hash<auto> wf) : WorkflowOrderRestClass(wf) {
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = sysinfo.getWFIAllInfo(id, NOTHING, False, cx.internal || cx.ssl);
        if (h) {
            if (h.InstanceInfo.workflowid != wf.workflowid)
                throw "WORKFLOW-ORDER-ERROR", sprintf("order %d is not an order for workflow %s v%s (%d); it belongs to %s v%s (%d) instead",
                                                      id, wf.name, wf.version, wf.workflowid, h.InstanceInfo.name, h.InstanceInfo.version, h.InstanceInfo.workflowid);
            return new WorkflowOrderInstanceRestClassV2(h);
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(id))
                return new AttributeRestClass(wf{id});
        }
    }
}

/** @REST /v2/workflows/{id_or_name} (/workflows/{id_or_name})

    This REST URI path provides actions and information about a particular workflow.
*/
class WorkflowDefinitionRestClassV2 inherits WorkflowDefinitionRestClass {
    constructor(hash<auto> wf) : WorkflowDefinitionRestClass(wf) {
        self.wf = wf;
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "instances": return new WorkflowInstanceRestClass(cx, wf, 2);
            case "orders": return new WorkflowOrderRestClassV2(wf);
            case "errors": return new WorkflowSpecificErrorsRestClass(wf.workflowid);
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(name))
                return new AttributeRestClass(wf{name});
        }
    }

    /** @REST POST action=createOrder

        @SCHEMA
        @summary Creates a workflow order data instance

        @desc Creates a workflow order data instance for the current workflow with the data passed as arguments. \
        To ensure that a given workflow order is only created once for a given unique key value, make sure \
        your workflow defines @ref wf_keylist "order keys", and use one of the following options to guarantee \
        the uniqueness of the order: \
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
        - scheduled (*date): the earliest date and time the order can be processed; if this date is given as a \
          future date/time value and a @ref OMQ::StatReady status is given, then the initial status of the workflow \
          order data instance will be automatically changed to @ref OMQ::StatScheduled instead of @ref OMQ::StatReady
        - sensitive_data (*hash[hash[hash SensitiveDataInfo] SensitiveDataKeyInfo] SensitiveDataSetInfo): \
          a hash of sensitive data information for the \
          workflow; this key can only be used when submitting the data over a secure (encrypted) connection; the \
          keys are sensitive data key types, values are hashes keyed by sensitive data values
          - aliases (*list<string>): zero or more string aliases for the sensitive data
          - data (hash[any] UndefinedHash): the sensitive data hash itself
          - meta (*hash[any] SensitiveMetaInfo): a hash of metadata for the sensitive data
            - PURPOSE (any): free-form information about the purpose of the sensitive data
            - CATEGORIES (any): free-form information about the categories of sensitive data
            - RECIPIENTS (any): free-form information about the recipients or recipient catories of sensitive data
            - STORAGE (any): free-form information about the storage time or rules for sensitive data
        - staticdata (hash[any] UndefinedHash): the static data for the order; either this key or \
          \c external_order_instanceid is required
        - status (*string): the initial order status (default @ref OMQ::StatReady); must be either \
          @ref OMQ::StatReady or @ref OMQ::StatBlocked
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

        @return (hash WorkflowOrderCreateInfo): 201: describes the workflow order created
        - workflow_instanceid (string): the workflow instance ID of the order created

        @error (409): exception processing create order request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SENSITIVE-DATA-ERROR: a workflow order was submitted with sensitive data over a non-encrypted network connection
        - <tt><b>409 Conflict</b></tt>: \c SUBMIT-ORDER-ERROR: invalid \a status value
        - <tt><b>409 Conflict</b></tt>: \c ORDER-DATA-ERROR: missing either \c external_order_instanceid or \c staticdata, unknown workflow; invalid keys or sensitive data format
        - <tt><b>409 Conflict</b></tt>: \c DUPLICATE-ORDER-KEY: the given unique key already exists in the defined scope
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-KEY-ERROR: invalid workflow key given

        @note
        - sensitive data can only be created over a secure connection
        - The \c global_unique_key, \c workflow_specific_unique_key, and \c workflow_unique_key options can be used to
          ensure that given workflow order data is only created once; note that any archiving schema is also searched when checking for
          duplicate keys.  These options may be combined, but it's recommended to use no more than one key for uniqueness.

        @see
        - @ref sensitive_data
        - omq.system.create-order()
     */
    hash<auto> postCreateOrder(hash<auto> cx, *hash<auto> ah) {
        if (ah.status) {
            ah.status = ah.status.upr();
        }

        # check if sensitive data is coming in through an encrypted interface
        if (ah.sensitive_data && !(cx.internal || cx.ssl))
            throw "SENSITIVE-DATA-ERROR", sprintf("a workflow order for workflow %s v%s (%d) was submitted with "
                "sensitive data over a non-encrypted network connection", wf.name, wf.version, wf.workflowid);

        # workflow access is checked in Orders::submitData()
        softstring rv = orders.submitData(cx, wf.name, wf.version, ah.OrderData::DataKeys, ah.status);
        olog(LoggerLevel::INFO, "order %s/%s from %s: created workflow instance %d with status %y", wf.name, wf.version,
            cx."peer-info".address_desc ?? ServiceApi::getCallContextString(cx), rv, ah.status ?? OMQ::StatReady);

        return RestHandler::makeResponse(201, {"workflow_instanceid": rv});
    }

    /** @REST POST action=execSynchronous

        @SCHEMA
        @summary Creates a new order for the current workflow and executes it synchronous mode.

        @desc Creates a new order for the current workflow and executes it synchronous mode.  This API call will \
        return only after the workflow order reaches a @ref OMQ::StatComplete "COMPLETE" or \
        @ref OMQ::StatError "ERROR" state, unless the system or the workflow order data instance are manually \
        stopped while the workflow order data instance is being processed, in which case other statuses can be \
        returned. \
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
        - sensitive_data (*hash[hash[hash SensitiveDataInfo] SensitiveDataKeyInfo] SensitiveDataSetInfo): \
          a hash of sensitive data information for the workflow; this key can only be used when submitting the data \
          over a secure (encrypted) connection; the keys are sensitive data key types, values are hashes keyed by \
          sensitive data values
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

        @return (hash WorkflowOrderExecutionInfo): 201: describes the workflow order created
        - workflow_instanceid (string): the workflow instance ID of the order created
        - status (string): the status of the order after synchronous order processing
        - dynamicdata (*hash[any] UndefinedHash): the dynamic data of the workflow order instance

        @error (409): exception processing create order request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SENSITIVE-DATA-ERROR: a workflow order was submitted with sensitive data
          over a non-encrypted network connection
        - <tt><b>409 Conflict</b></tt>: \c ORDER-DATA-ERROR: missing either \c external_order_instanceid or
          \c staticdata, unknown workflow; invalid keys or sensitive data format
        - <tt><b>409 Conflict</b></tt>: \c DUPLICATE-ORDER-KEY: the given unique key already exists in the defined
          scope
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-KEY-ERROR: invalid workflow key given
    */
    hash<auto> postExecSynchronous(hash<auto> cx, *hash<auto> ah) {
        if (ah.options && ah.options.typeCode() != NT_HASH) {
            throw "PARAMETER-ERROR", sprintf("workflow options must be given in hash format (option=value), type "
                "given: %y", ah.options.type());
        }

        hash<auto> oh = ah.OrderData::DataKeys + ("name": wf.name, "version": wf.version);

        if (oh.priority < 0) {
            oh.priority = 0;
        } else if (oh.priority > 999) {
            oh.priority = 999;
        }

        # check if sensitive data is coming in through an encrypted interface
        if (ah.sensitive_data && !(cx.internal || cx.ssl)) {
            throw "SENSITIVE-DATA-ERROR", sprintf("a workflow order for workflow %s v%s (%d) was submitted with "
                "sensitive data over a non-encrypted network connection", wf.name, wf.version, wf.workflowid);
        }

        OrderData order(oh{(OrderData::DataKeyHash - ("name", "version", "scheduled")).keys()});

        # set workflow name and version in order data
        order.setNameAndVersion(wf.name, wf.version);

        # workflow access is checked in Control::setupWorkflow()
        return RestHandler::makeResponse(201, Qorus.control.execSynchronousWorkflow(cx, wf.workflowid, order,
            ah.options));
    }
}

/** @REST /v2/workflows (/workflows)

    This URI path allows workflows to be queried and for actions on multiple workflows to be performed;
    this is the URI path parent of workflow-specific actions as well.
*/
class WorkflowRestClassV2 inherits WorkflowRestClass {
    private *QorusRestClass internGetWorkflowDefinitionSubclass(*hash<auto> wf) {
        if (wf) {
            return new WorkflowDefinitionRestClassV2(wf);
        }
    }
}

/** @REST /v2/orders/{id} (/orders/{id})

    This REST URI path provides actions and information about specific workflow orders.
*/
class WorkflowOrderInstanceRestClassV2 inherits WorkflowOrderInstanceRestClass {
    constructor(hash<auto> wf, int apiver = 2) : WorkflowOrderInstanceRestClass(wf, apiver) {
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
        - \c sensitive_data: a hash of @ref sensitive_data "sensitive data" (if present on the order and the request comes in over an encrypted connection and the user has permission to read sensitive data) keyed by sensitive data key; each value is a hash keyed by sensitive data values; each value here is a hash with the following keys:
          - \c aliases: zero or more sensitive data aliases for the current sensitive data key and value
          - \c data: the sensitive data hash itself
          - \c meta: any sensitive metadata; the following keys are recommended here (but not enforced by the API):
            - \c PURPOSE: free-form information about the purpose of the sensitive data
            - \c CATEGORIES: free-form information about the categories of sensitive data
            - \c RECIPIENTS: free-form information about the recipients or recipient catories of sensitive data
            - \c STORAGE: free-form information about the storage time or rules for sensitive data
        - \c has_sensitive_data: @ref True "True" if the order has sensitive data, @ref False "False" if not; this key is always returned with a valid response
        - \c keys: a hash of @ref wf_keylist "workflow order keys" and values
        - \c warning_count: the number of warnings raised against the order
        - \c error_count: the number of errors raised against the order
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

        @note
        - sensitive data is only returned if the request is made through a secure (i.e. HTTPS) listener, otherwise if
          the order contains sensitive data, then the sensitive data is not returned, however
          the \c has_sensitive_data key is returned as @ref True "True"
        - as with other REST APIs backed by info service methods, this method searches the system schema and any archiving schema transparently
    */

    /** @REST PUT action=sensitiveData

        @SCHEMA
        @summary Replaces the @ref sensitive_data "sensitive data" for the current order

        @desc Replaces the @ref sensitive_data "sensitive data" for the current order given the sensitive data key and
        value; if the order is located in an archiving schema, then it is updated there as well

        @params
        - skey (string): the sensitive data key type
        - svalue (string): the sensitive data key value
        - aliases (*list<string>): zero or more string aliases for the sensitive data
        - data (*hash[any] UndefinedHash): the sensitive data hash itself; if omitted then sensitive data is removed \
          for the given \a skey and \a svalue values
        - meta (*hash[any] SensitiveMetaInfo): a hash of metadata for the sensitive data
          - PURPOSE (any): free-form information about the purpose of the sensitive data
          - CATEGORIES (any): free-form information about the categories of sensitive data
          - RECIPIENTS (any): free-form information about the recipients or recipient catories of sensitive data
          - STORAGE (any): free-form information about the storage time or rules for sensitive data

        @return (string): \c "OK"

        @error (400): invalid arguments or request made over a non-encrypted connection
        @ENDSCHEMA

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: \c SENSITIVE-DATA-ERROR: invalid arguments; cannot update sensitive data
          over a non-encrypted network connection
    */
    hash<auto> putSensitiveData(hash<auto> cx, *hash<auto> ah) {
        # check if sensitive data is coming in through an encrypted interface
        if (!(cx.internal || cx.ssl)) {
            throw "SENSITIVE-DATA-ARG-ERROR", sprintf("cannot update sensitive data for workflow_instanceid %d over "
                "a non-encrypted network connection", wf.workflow_instanceid);
        }

        *string skey = ah.skey;
        if (!skey.val()) {
            throw "SENSITIVE-DATA-ARG-ERROR", sprintf("missing argument \"skey\" in the call to update sensitive "
                "data for workflow_instanceid %d", wf.workflow_instanceid);
        }

        *softstring svalue = ah.svalue;
        if (!svalue.val()) {
            throw "SENSITIVE-DATA-ARG-ERROR", sprintf("missing argument \"svalue\" in the call to update sensitive "
                "data for workflow_instanceid %d for key type %y", wf.workflow_instanceid, skey);
        }

        auto data = ah.data;
        if (exists data && data.typeCode() != NT_HASH) {
            throw "SENSITIVE-DATA-ARG-ERROR", sprintf("argument \"data\" has type %y; expecting \"hash\"",
                data.type());
        }

        auto aliases = ah.aliases;
        switch (aliases.typeCode()) {
            case NT_STRING:
                if (aliases =~ /,/) {
                    aliases = aliases.split(",");
                }
                break;
            case NT_LIST:
            case NT_NOTHING:
                break;
            default:
                if (aliases.strp()) {
                    aliases = aliases.toString();
                } else {
                    throw "SENSITIVE-DATA-ERROR", sprintf("argument \"aliases\" has type %y; expecting \"list\" or "
                        "\"string\"", aliases.type());
                }
        }

        auto meta = ah.meta;
        if (exists meta && meta.typeCode() != NT_HASH) {
            throw "SENSITIVE-DATA-ARG-ERROR", sprintf("argument \"meta\" has type %y; expecting \"hash\"",
                meta.type());
        }

        SM.replaceSensitiveData(cx, wf.workflow_instanceid, skey, svalue, data, aliases, meta);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST GET action=yamlDynamicData
        @par Description
        Returns @ref dynamicdata "dynamic data" for the order as a serialized YAML string for potential editing

        @par Return Value
        This API returns a YAML-serialized string of workflow order @ref dynamicdata "dynamic data"; if no @ref dynamicdata "dynamic data" is in place; then YAML-serialized string will be deserialized to a hash or to no value (i.e. in %Qore @ref nothing) if there is no @ref dynamicdata "dynamic data" for the workflow order

        @note
        - this method operates on the system schema and any archiving schema transparently

        @since Qorus 3.1.1.p1
    */
    hash<auto> getYamlDynamicData(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, make_yaml(wf.dynamicdata, YAML::BlockStyle));
    }

    /** @REST PUT action=yamlDynamicData

        @par Description
        Replaces the @ref dynamicdata "dynamic data" for an existing order using a YAML-serialized string for the new dynamic data

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c newdata: (YAML-serialized string) the new @ref dynamicdata "dynamic data" for the current workflow order as a YAML-serialized string; can also be deserialized to @ref nothing which will remove all dynamic data from the order

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c DYNAMIC-DATA-ERROR: this error is returned if the \a newdata argument is not a string
        - <tt><b>409 Conflict</b></tt>: \c YAML-PARSER-ERROR: this error is returned if the YAML string cannot be deserialized

        @since Qorus 3.1.1.p1
    */
    hash<auto> putYamlDynamicData(hash<auto> cx, *hash<auto> ah) {
        if (ah.newdata.typeCode() != NT_STRING)
            throw "DYNAMIC-DATA-ERROR", sprintf("expecting type \"string\" for the \"newdata\" key; got type %y instead", ah.newdata.type());

        ah.newdata = parse_yaml(ah.newdata);
        return putDynamicData(cx, ah);
    }

    /** @REST GET action=yamlStaticData
        @par Description
        Returns @ref staticdata "static data" for the order as a serialized YAML string for potential editing

        @par Return Value
        This API returns a YAML-serialized string of workflow order @ref staticdata "static data"; if no @ref staticdata "static data" is in place; then YAML-serialized string will be deserialized to a hash or to no value (i.e. in %Qore @ref nothing) if there is no @ref staticdata "static data" for the workflow order

        @note
        - this method operates on the system schema and any archiving schema transparently

        @since Qorus 3.1.1.p1
    */
    hash<auto> getYamlStaticData(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, make_yaml(wf.staticdata, YAML::BlockStyle));
    }

    /** @REST PUT action=yamlStaticData

        @par Description
        Replaces the @ref staticdata "static data" for an existing order using a YAML-serialized string for the new static data

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c newdata: (YAML-serialized string) the new @ref staticdata "static data" for the current workflow order as a YAML-serialized string; must be deserialized to a non-empty hash

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c STATIC-DATA-ERROR: this error is returned if the \a newdata argument is not a string
        - <tt><b>409 Conflict</b></tt>: \c YAML-PARSER-ERROR: this error is returned if the YAML string cannot be deserialized

        @since Qorus 3.1.1.p1
    */
    hash<auto> putYamlStaticData(hash<auto> cx, *hash<auto> ah) {
        if (ah.newdata.typeCode() != NT_STRING)
            throw "STATIC-DATA-ERROR", sprintf("expecting type \"string\" for the \"newdata\" key; got type %y instead", ah.newdata.type());

        ah.newdata = parse_yaml(ah.newdata);
        return putStaticData(cx, ah);
    }

    /** @REST GET action=yamlSensitiveData

        @par Description
        Returns the @ref sensitive_data "sensitive data" for an existing order given the sensitive data key and value; the sensitive data itself is returned as a YAML-serialized string

        @par Arguments
        This API takes the following required hash arguments (either as URI arguments or in the message body):
        - \c skey: (string) the sensitive data key type
        - \c svalue: (string) the sensitive data key value

        @par Return Value
        This API returns either @ref nothing (if the order doesn't have the request sensitive data key and value)
        or a hash with the following keys:
        - [\c aliases]: (list of strings) zero or more string aliases for the sensitive data
        - \c data: (YAML-serialized string) the sensitive data hash itself serialized as a YAML string for potential editing
        - [\c meta]: (hash) a hash of metadata for the sensitive data with the following recommended keys (recommended keys are not enforced by the API itself):
          - [\c PURPOSE]: free-form information about the purpose of the sensitive data
          - [\c CATEGORIES]: free-form information about the categories of sensitive data
          - [\c RECIPIENTS]: free-form information about the recipients or recipient catories of sensitive data
          - [\c STORAGE]: free-form information about the storage time or rules for sensitive data

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SENSITIVE-DATA-ERROR: invalid arguments; cannot retrieve sensitive data over a non-encrypted network connection

        @note
        - this method operates on the system schema and any archiving schema transparently

        @since Qorus 3.1.1.p1
    */
    hash<auto> getYamlSensitiveData(hash<auto> cx, *hash<auto> ah) {
        # check if a request for sensitive data is coming in through an encrypted interface
        if (!(cx.internal || cx.ssl))
            throw "SENSITIVE-DATA-ERROR", sprintf("cannot retrieve sensitive data for workflow_instanceid %d over a non-encrypted network connection", wf.workflow_instanceid);

        *string skey = ah.skey;
        if (!skey.val())
            throw "SENSITIVE-DATA-ERROR", sprintf("missing argument \"skey\" in the call to retrieve sensitive data for workflow_instanceid %d", wf.workflow_instanceid);

        *softstring svalue = ah.svalue;
        if (!svalue.val())
            throw "SENSITIVE-DATA-ERROR", sprintf("missing argument \"svalue\" in the call to retrieve sensitive data for workflow_instanceid %d for key type %y", wf.workflow_instanceid, skey);

        *hash<auto> rv = wf.sensitive_data{skey}{svalue};
        if (rv)
            rv.data = make_yaml(rv.data, YAML::BlockStyle);

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=yamlSensitiveData

        @par Description
        Replaces the @ref sensitive_data "sensitive data" for an existing order given the sensitive data key and value;
        the actual sensitive data must be given as a YAML-serialized string

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c skey: (string) the sensitive data key type
        - \c svalue: (string) the sensitive data key value
        - \c data: (YAML-serialized string) the new @ref sensitive_data "sensitive data" for the current workflow order; can also be @ref nothing which will remove all sensitive data from the order for the given sensitive data key and value
        - \c aliases: (string or list of strings; optional) zero or more aliases for the sensitive data corresponding to the given sensitive data key and value
        - \c meta: (hash; optional) a hash of metadata for the sensitive data with the following recommended keys (recommended keys are not enforced by the API itself):
          - [\c PURPOSE]: free-form information about the purpose of the sensitive data
          - [\c CATEGORIES]: free-form information about the categories of sensitive data
          - [\c RECIPIENTS]: free-form information about the recipients or recipient catories of sensitive data
          - [\c STORAGE]: free-form information about the storage time or rules for sensitive data

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SENSITIVE-DATA-ERROR: invalid arguments; cannot update sensitive data over a non-encrypted network connection
        - <tt><b>409 Conflict</b></tt>: \c YAML-PARSER-ERROR: this error is returned if the YAML string cannot be deserialized

        @note
        - this method operates on the system schema and any archiving schema transparently

        @since Qorus 3.1.1.p1
    */
    hash<auto> putYamlSensitiveData(hash<auto> cx, *hash<auto> ah) {
        if (ah.data.typeCode() != NT_STRING)
            throw "SENSITIVE-DATA-ERROR", sprintf("expecting type \"string\" for the \"data\" key; got type %y instead", ah.data.type());

        ah.data = parse_yaml(ah.data);
        return putSensitiveData(cx, ah);
    }
}

/** @REST /v2/orders (/orders)

    This URI path provides information and actions related to workflow order data.
*/
class GlobalOrderRestClassV2 inherits GlobalOrderRestClass {
    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        if (id == "all")
            return self;
        bool with_sensitive_data = (cx.internal || cx.ssl);
        *hash<auto> h = sysinfo.getWFIAllInfo(id, NOTHING, False, with_sensitive_data);
        if (h) {
            return new WorkflowOrderInstanceRestClassV2(h);
        }
        throw "WORKFLOW-ORDER-ERROR", sprintf("there is no workflow_instanceid %d", id);
    }

    /** @REST GET action=searchSensitiveData

        @par Description
        Searches for @ref sensitive_data "sensitive data" according to the arguments given

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c skey: (required) the sensitive data key type
        - \c svalue: (required) the sensitive data key value
        - \c desc: (optional) return in descending order
        - \c maxmodified: (optional) maximum modified date of the workflow order
        - \c maxstarted: (optional) maximum start date of the workflow order
        - \c minstarted: (optional) minimum start date of the workflow order
        - \c modified: (optional) minimum modified date of the workflow order
        - \c limit: (optional) max number of rows to return, if not given, then the value of the \a "row-limit" option is used (default: 100)
        - \c offset: (optional) row offset
        - \c sort: (optional) columns for sorting the results
        - \c status: (optional) workflow order status value(s)
        - \c workflow_instanceid: (optional) workflow_instanceid values(s)
        - \c workflowid: (optional) workflowid values(s)
        - \c workflowname: (optional) all versions of the given workflow name

        @par Return Value
        A list of hashes for matched workflow orders that correspond to the arguments; each hash element has keys as follows:
        - \c name: the name of the workflow
        - \c version: the version of the workflow
        - \c workflow_instanceid: the workflow order instance ID
        - \c workflowid: the workflow ID
        - \c workflowstatus: the status of the workflow order instance
        - \c status_sessionid: the application session ID that owns the workflow order instance data or 0 if the data is now owned by any application session
        - \c started: the start date/time of the workflow order instance
        - \c completed: the completed date/time for the workflow order instance
        - \c modified: the last modified date/time of the workflow order instance
        - \c parent_workflow_instanceid: the parent workflow_instanceid if the workflow is a child workflow order
        - \c synchronous: the synchronous flag for the workflow order instance
        - \c business_error: the business error flag for the workflow order instance
        - \c archive: the archive flag for the workflow order instance (presented only if it goes from archive datasource)
        - \c operator_lock: the username of the user owning the lock on the workflow order instance data
        - \c note_count: the number of notes attached to the workflow order instance
        - \c warning_count: the warning count of the workflow order instance
        - \c error_count: the error count of the workflow order instance
        - \c custom_status: any custom status for the workflow order instance
        - \c priority: the priority of the workflow order instance
        - \c scheduled: the scheduled date for the workflow order instance
        - \c archive: if retrieved from the archive datasource
        - \c skey: the sensitive data key type
        - \c svalue: the sensitive data value
        - \c sensitive_data: the sensitive data hash for the given key and value

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SENSITIVE-DATA-ERROR: the request to search for sensitive data arrived over a non-encrypted network connection
        - <tt><b>409 Conflict</b></tt>: \c INVALID-WORKFLOW: the name given in the \c workflowname parameter does not correspond to a known workflow

        @note
        - sensitive data can only be queried over a secure connection
        - this method searches the system schema and any archiving schema, treating both as a single unified schema transparently
        - this method is not implemented in the @link ##info system.info service @endlink to avoid inadvertent logging of sensitive data

        @see
        - @ref sensitive_data
    */
    hash<auto> getSearchSensitiveData(hash<auto> cx, *hash<auto> ah) {
        *softstring skey = remove ah.skey;
        if (!skey.val())
            throw "SENSITIVE-DATA-ERROR", "missing argument \"skey\" in the call to query sensitive data";

        *softstring svalue = remove ah.svalue;
        if (!svalue.val())
            throw "SENSITIVE-DATA-ERROR", sprintf("missing argument \"svalue\" in the call to query sensitive data for key type %y", skey);

        # ensure that sensitive data is only returned over a secure connection and by an authorized user
        QorusSystemService::verifySensitiveDataRequestRo();

        if (ah.sort =~ /,/)
            ah.sort = ah.sort.split(",");

        if (ah.status =~ /,/)
            ah.status = ah.status.split(",");

        if (ah.workflowid =~ /,/)
            ah.workflowid = ah.workflowid.split(",");

        if (ah.workflowname =~ /,/)
            ah.workflowname = ah.workflowname.split(",");

        if (ah.workflow_instanceid =~ /,/)
            ah.workflow_instanceid = ah.workflow_instanceid.split(",");

        # permissions and connection details are checked in the info service method
        return RestHandler::makeResponse(200, GlobalOrderRestClassV2::searchSensitiveData(skey, svalue, ah));
    }

    /** @REST DELETE action=purgeSensitiveData

        @par Description
        Deletes @ref sensitive_data "sensitive data" according to the arguments given

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c skey: (optional) the sensitive data key type; if passed, then \c svalue must be included
        - \c svalue: (optional) the sensitive data key value; if passed then \c skey must be included
        - \c force: (optional) allows sensitive data to be deleted for workflow orders with statuses other than @ref OMQ::StatComplete or @ref OMQ::StatCanceled
        - \c maxmodified: (optional) maximum modified date of the workflow order
        - \c maxstarted: (optional) maximum start date of the workflow order
        - \c minstarted: (optional) minimum start date of the workflow order
        - \c modified: (optional) minimum modified date of the workflow order
        - \c status: (optional) workflow order status value(s)
        - \c workflow_instanceid: (optional) workflow_instanceid values(s)
        - \c workflowid: (optional) workflowid values(s)
        - \c workflowname: (optional) all versions of the given workflow name

        @par Return Value
        A list of hashes for matched workflow orders that correspond to the arguments; each hash element has keys as follows:
        - \c name: the name of the workflow
        - \c version: the version of the workflow
        - \c workflow_instanceid: the workflow order instance ID
        - \c workflowid: the workflow ID
        - \c workflowstatus: the status of the workflow order instance
        - \c status_sessionid: the application session ID that owns the workflow order instance data or 0 if the data is now owned by any application session
        - \c started: the start date/time of the workflow order instance
        - \c completed: the completed date/time for the workflow order instance
        - \c modified: the last modified date/time of the workflow order instance
        - \c parent_workflow_instanceid: the parent workflow_instanceid if the workflow is a child workflow order
        - \c synchronous: the synchronous flag for the workflow order instance
        - \c business_error: the business error flag for the workflow order instance
        - \c archive: the archive flag for the workflow order instance (presented only if it goes from archive datasource)
        - \c operator_lock: the username of the user owning the lock on the workflow order instance data
        - \c note_count: the number of notes attached to the workflow order instance
        - \c warning_count: the warning count of the workflow order instance
        - \c error_count: the error count of the workflow order instance
        - \c custom_status: any custom status for the workflow order instance
        - \c priority: the priority of the workflow order instance
        - \c scheduled: the scheduled date for the workflow order instance
        - \c archive: if retrieved from the archive datasource
        - \c skey: the sensitive data key type
        - \c svalue: the sensitive data value; if the \c svalue key is given in the request, then it's returned decoded, otherwise the encoded version is returned'
        - \c sensitive_data: the sensitive data hash for the given key and value

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SENSITIVE-DATA-ERROR: the request to search for sensitive data arrived over a non-encrypted network connection or \c skey included without \c svalue or \c svalue included without \c skey
        - <tt><b>409 Conflict</b></tt>: \c INVALID-WORKFLOW: the name given in the \c workflowname parameter does not correspond to a known workflow
        - <tt><b>409 Conflict</b></tt>: \c ORDER-STATUS-ERROR: a status other than @ref OMQ::StatComplete or @ref OMQ::StatCanceled was passed and the \c force option was not given and the \c workflow_instanceid option was used

        @note
        - sensitive data can only be queried over a secure connection
        - the \c ORDER-STATUS-ERROR is only thrown if the \c force option is not @ref True "True" and the \c workflow_instanceid option is used, otherwise ineligible orders are ignored
        - this method operates on the system schema and any archiving schema, treating both as a single unified schema transparently
        - this method is not implemented in the @link ##info system.info service @endlink to avoid inadvertent logging of sensitive data

        @see
        - @ref sensitive_data
    */
    hash<auto> delPurgeSensitiveData(hash<auto> cx, *hash<auto> ah) {
        *softstring skey = remove ah.skey;
        *softstring svalue = remove ah.svalue;

        if (!skey.val() && svalue.val())
            throw "SENSITIVE-DATA-ERROR", "missing argument \"skey\" but with \"svalue\" in the call to query sensitive data; if \"svalue\" is included in the call, then \"skey\" must also be included in the call";
        if (!svalue.val() && skey.val())
            throw "SENSITIVE-DATA-ERROR", sprintf("missing argument \"svalue\" in the call to query sensitive data for sensitive key type %y", skey);

        # ensure that sensitive data is only returned over a secure connection and by an authorized user
        QorusSystemService::verifySensitiveDataRequestDel();

        if (ah.hasKey("force") && ah.force.typeCode() != NT_BOOLEAN)
            ah.force = parse_boolean(ah.force);

        if (ah.status) {
            if (ah.status =~ /,/)
                ah.status = ah.status.split(",");

            # ensure that only orders with COMPLETE and CANCELED are searched if the force flag is not set
            if (!ah.force) {
                foreach string status in (ah.status) {
                    if (status != OMQ::StatComplete && status != OMQ::StatCanceled)
                        throw "ORDER-STATUS-ERROR", sprintf("cannot delete workflow sensitive data with statuses %y unless the \"force\" flag is also set", ah.status);
                }
            }
        }
        else if (!ah.force && !ah.workflow_instanceid)
            ah.status = (OMQ::StatComplete, OMQ::StatCanceled);

        if (ah.workflowid =~ /,/)
            ah.workflowid = ah.workflowid.split(",");

        if (ah.workflowid)
            ah.workflowid = map $1.toInt(), ah.workflowid;

        if (ah.workflowname =~ /,/)
            ah.workflowname = ah.workflowname.split(",");

        if (ah.workflow_instanceid =~ /,/)
            ah.workflow_instanceid = ah.workflow_instanceid.split(",");

        if (ah.workflow_instanceid)
            ah.workflow_instanceid = map $1.toInt(), ah.workflow_instanceid;

        # encode sensitive data value for query if present
        *string svalue_encoded;
        if (svalue.val())
            svalue_encoded = Qorus.encodeEncryptSensitiveValue(svalue);

        *list ret = deleteSensitiveDataIntern("omq", "primary", skey, svalue, svalue_encoded, ah);

        if (*string dsarch = Qorus.props.get("arch").datasource)
            ret += deleteSensitiveDataIntern(dsarch, "archive", skey, svalue, svalue_encoded, ah);

        return RestHandler::makeResponse(200, ret);
    }

    private static *list deleteSensitiveDataIntern(string dsname, string desc, *string skey, *string svalue, *string svalue_encoded, hash h) {
        *list ret = GlobalOrderRestClassV2::searchSensitiveDataIntern(dsname, skey, svalue, svalue_encoded, h);

        if (ret) {
            if (h.workflow_instanceid && !h.force) {
                foreach hash<auto> wh in (ret) {
                    # include only the encrypted value in the exception message
                    if (wh.workflowstatus != OMQ::StatComplete && wh.workflowstatus != OMQ::StatCanceled) {
                        if (skey.val())
                            throw "ORDER-STATUS-ERROR", sprintf("cannot purge sensitive data with skey: %y encrypted svalue: %y for workflow_instanceid: %d with status: %y", skey, svalue_encoded, wh.workflow_instanceid, wh.workflowstatus);
                        else
                            throw "ORDER-STATUS-ERROR", sprintf("cannot purge sensitive data for workflow_instanceid: %d with status: %y", wh.workflow_instanceid, wh.workflowstatus);
                    }
                }
            }

            QdspClient dsp = dsname == "omq" ? omqp : UserApi::getDatasourcePool(dsname);
            # delete data from the primary schema
            AbstractTable sensitive_order_data_keys = get_sql_table_system(dsp, "sensitive_order_data_keys");
            AbstractTable sensitive_order_data = get_sql_table_system(dsp, "sensitive_order_data");

            on_error
                dsp.rollback();
            on_success
                dsp.commit();

            # create deletion condition hash
            hash dcond = (
                "workflow_instanceid": op_in(map $1.workflow_instanceid, ret),
            );

            if (skey.val()) {
                dcond += {
                    "skey": skey,
                    "svalue": svalue_encoded,
                };
            }

            int rows = sensitive_order_data_keys.del(dcond);
            # log only the encrypted value
            if (skey.val())
                qlog(LoggerLevel::INFO, "%y: rows deleted in the %s schema with skey: %y and encrypted svalue: %y: %d", sensitive_order_data_keys.getName(), dsname, skey, svalue_encoded, rows);
            else
                qlog(LoggerLevel::INFO, "%y: rows deleted in the %s schema: %d", sensitive_order_data_keys.getName(), dsname, rows);
            rows = sensitive_order_data.del(dcond);
            # log only the encrypted value
            if (skey.val())
                qlog(LoggerLevel::INFO, "%y: rows deleted in the %s schema with skey: %y and encrypted svalue: %y: %d", sensitive_order_data.getName(), dsname, skey, svalue_encoded, rows);
            else
                qlog(LoggerLevel::INFO, "%y: rows deleted in the %s schema: %d", sensitive_order_data.getName(), dsname, rows);
        }

        return ret;
    }

    # search for workflow order instances with the sensitive data given in the command-line
    /** this is not implemented in the info service to avoid logging sensitive data values
    */
    private static *list searchSensitiveDataIntern(string dsname, *string skey, *string svalue, *string svalue_encoded, *hash<auto> h) {
        AbstractTable sensitive_order_data = get_sql_table_system(dsname, "sensitive_order_data");
        AbstractTable workflows = get_sql_table_system(dsname, "workflows");
        AbstractTable workflow_instance = get_sql_table_system(dsname, "workflow_instance");

        if (h.desc)
            h.desc = parse_boolean(h.desc);

        if (h.sort) {
            # process sort keys
            bool hwf;
            foreach string k in (\h.sort) {
                k = k.lwr();
                if (!sensitive_order_data.describe().hasKey(k) && !workflows.describe().hasKey(k) && !workflow_instance.describe().hasKey(k))
                    throw "ORDER-SORT-ERROR", sprintf("sort key %y is not valid; valid keys: %y", k, (sensitive_order_data.describe().getHash() + workflows.describe().getHash() + workflow_instance.describe().getHash()).keys());
                if (k == "workflow_instanceid")
                    hwf = True;
            }

            # the sort key must also have a unique column to ensure consistent sort order
            if (!hwf) {
                if (h.sort.typeCode() != NT_LIST)
                    h.sort = list(h.sort);
                h.sort += "workflow_instanceid";
            }
        }
        else if (h.desc)
            h.sort = "workflow_instanceid";

        hash<auto> jh = join_inner(workflow_instance, "wi") + join_inner("wi", workflows, "w");

        hash wcond;
        if (skey.val()) {
            wcond = {
                "skey": skey,
                "svalue": svalue_encoded,
            };
        }

        if (h.workflow_instanceid) {
            if (h.workflow_instanceid.lsize() > 1)
                wcond.workflow_instanceid = op_in(map $1.toInt(), h.workflow_instanceid);
            else
                wcond.workflow_instanceid = h.workflow_instanceid.toInt();
        }

        if (h.status) {
            # convert to SQL status codes
            wcond."wi.workflowstatus" = op_in(map OMQ::StatMap.($1.upr()), h.status);
        }

        if (exists h.modified)
            wcond."wi.modified" = op_ge(date(h.modified));

        if (exists h.maxmodified)
            wcond."1:wi.modified" = op_lt(date(h.maxmodified));

        if (exists h.minstarted)
            wcond."wi.started" = op_ge(date(h.minstarted));
        if (exists h.maxstarted)
            wcond."1:wi.started" = op_lt(date(h.maxstarted));

        foreach string wfn in (h.workflowname) {
            *hash<auto> wh = Qorus.qmm.rLookupWorkflow(wfn);
            if (!wh)
                throw "INVALID-WORKFLOW", sprintf("workflow %y is unknown", h.workflowname);
            softlist l = h.workflowid;
            h.workflowid = l;
            map h.workflowid += $1.workflowid, wh.iterator(), $1.workflowid;
        }

        if (h.workflowid) {
            if (h.workflowid.lsize() > 1)
                wcond.workflowid = op_in(map $1.toInt(), h.workflowid);
            else if (h.workflowid.typeCode() == NT_LIST)
                wcond."w.workflowid" = h.workflowid[0].toInt();
            else
                wcond."w.workflowid" = h.workflowid.toInt();
        }

        hash<auto> sh = (
            "comment": "RESTv2 searchSensitiveData",
            "columns": ("workflow_instanceid", "skey", "svalue", "w.name", "w.version", "w.workflowid", "wi.workflowstatus", "wi.status_sessionid",
                "wi.started", "wi.completed", "wi.modified", "wi.parent_workflow_instanceid", "wi.synchronous", "wi.business_error", "wi.operator_lock",
                "wi.note_count", cop_as("wi.warnings", "warning_count"), cop_as("wi.errors", "error_count"), "wi.custom_status", "wi.priority",
                "wi.scheduled"),
            "join": jh,
            "where": wcond,
            "limit": h.limit,
            "offset": h.offset,
            "orderby": h.sort,
            "desc": h.desc,
        );

        *list sqlresult;
        if (svalue.val())
            sqlresult = map $1 + ("svalue": svalue), sensitive_order_data.selectRows(sh, SqlDataOpt);
        else
            sqlresult = map $1, sensitive_order_data.selectRows(sh, SqlDataOpt);

        if (sqlresult)
            sqlresult = SM.processWorkflowResults(sqlresult);

        return sqlresult;
    }

    static private *list searchSensitiveData(string skey, softstring svalue, *hash<auto> h) {
        # ensure that sensitive data is only returned over a secure connection and by an authorized user
        QorusSystemService::verifySensitiveDataRequestRo();

        # encode sensitive data value for query
        string svalue_encoded = Qorus.encodeEncryptSensitiveValue(svalue);

        # log only the encrypted value
        qlog(LoggerLevel::DEBUG, "searchSensitiveData(): skey: %y encrypted svalue: %y h: %y", skey, svalue_encoded, h);

        # enforce a maximum of 100 rows returned
        if (!h.limit)
            h.limit = 100;

        *list ret = GlobalOrderRestClassV2::searchSensitiveDataIntern("omq", skey, svalue, svalue_encoded, h);
        int lsize = ret.lsize();
        if (lsize < h.limit && (*string dsarch = Qorus.props.get("arch").datasource))
            ret += map $1 + ("archive": True), GlobalOrderRestClassV2::searchSensitiveDataIntern(dsarch, skey, svalue, svalue_encoded, h + ("limit": h.limit - lsize));
        return ret;
    }
}

/** @REST /v2/exec (/exec)

    This URI path provides actions and information regarding workflow execution instances.
*/

/** @REST /v2/users (/users)

    This REST URI path provides actions and information related to Qorus @ref rbacusers "users"
*/

/** @REST /v2/roles (/roles)

    This REST URI path provides actions and information related to Qorus @ref rbacroles "roles"
*/

/** @REST /v2/groups (/groups)

    This URI path provides actions and information related to @ref rbacgroups "interface groups"
*/

/** @REST /v2/steps (/steps)

    This REST API path provides actions and information about specific @ref steps "workflow steps"
*/

/** @REST /v2/functions (/functions)

    This REST API path provides actions and information about Qorus functions
*/

/** @REST /v2/classes (/classes)

    This REST API path provides actions and information about Qorus class objects
*/

/** @REST /v2/constants (/constants)

    This REST API path provides actions and information about Qorus constant objects
*/

/** @REST /v2/debug (/debug)

    This REST URI path provides actions and information related to Qorus system debugging
*/

/** @REST /v2/jobresults (/jobresults)

    This REST API path provides actions and information about job results (job instances).
*/

/** @REST /v2/logs (/logs)

    This REST URI path provides actions and information related to Qorus system logs and websocket log sources
*/

/** @REST /v2/remote (/remote)

    This REST URI path provides actions and information about remote @ref remoteconn "Qorus", @ref userconn "user" and @ref dsconn "datasource" connections
*/

/** @REST /v2/perms (/perms)

    This REST URI path provides actions and information related to @ref RBAC "RBAC" @ref rbacpermissions "permissions"
*/

/** @REST /v2/errors (/errors)

    This URI path provides actions and information related to @ref globalandworkflowerrors "workflow errors"
*/

/** @REST /v2/mappers (/mappers)

    This URI path provides actions and information related to system @ref mappers "mappers"
*/

/** @REST /v2/mappertypes (/mappertypes)

    This REST URI path provides actions and information related to all @ref mapper-types "mapper types"

    @see @ref mapper-modules
*/

/** @REST /v2/async-queues (/async-queues)

    This REST URI path provides actions and information about @ref queue_objects "queues for asynchronous workflow steps"
*/

/** @REST /v2/valuemaps (/valuemaps)

    This URI path provides actions and information related to Qorus @ref value-maps "value maps"
*/

/** @REST /v2/releases (/releases)

    This REST URI path provides actions and information about Qorus releases
*/

/** @REST /v2/sync-events (/sync-events)

    This REST URI path provides actions and information about @ref wf_sync_event_objects "workflow synchronization events"
*/

/** @REST /v2/logout (/logout)

    This REST API path provides the logout action
*/
