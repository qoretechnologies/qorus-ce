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

/** @page rest_api_page_v7 Qorus REST API v7

    @tableofcontents

    @section rest_api_v7_overview Qorus REST API v7 Overview

    @par Swagger Schema
    A static version can be downloaded here: <a href="qorus-rest-api-v7.yaml">qorus-rest-api-v7.yaml</a>; a dynamic
    version is available from every Qorus instance without authentication at URI paths
    <tt>/schema/qorus-rest-api-v7.yaml</tt> and <tt>/schema/qorus-rest-api-v7.json</tt> (ex: if Qorus is available on
    <tt>https://localhost:8011</tt>, then the dynamic schema can be retrieved from
    <tt>https://localhost:8011/schema/qorus-rest-api-v7.yaml</tt> and
    <tt>https://localhost:8011/schema/qorus-rest-api-v7.json</tt>).

    @par Differences from v6:
    REST API v7 has the following differences from @ref rest_api_page_v6 "REST API v6":
    - data provider manipulation APIs were added
    - APIs permitting external applications to use data provider functionality have been implemented
    - @ref rest_api_POST_latest_system_listeners__id_or_name__reloadCertificate: a new API that allows HTTPS
      listeners to reload their X.509 certificate configuration from source file locations, allowing new
      certificates to take effect immediately without having to restart Qorus or the listener
    - other enhancements were made to data provider APIs
*/

/** @REST /v7 (/v6)

    This URI path implements v6 of the Qorus REST API
*/
class V7RestClass inherits QorusRestClass {
    constructor() {
        addClass(new WorkflowRestClassV6());
        addClass(new GlobalOrderRestClassV6());
        addClass(new GlobalWorkflowExecRestClassV3());
        addClass(new ServiceRestClassV7());
        addClass(new SystemRestClassV7());
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
        addClass(new SlasRestClassV7());
        addClass(new DataProviderBaseRestClassV7());
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
        return "v7";
    }

    /** @REST GET

        @par Description
        Returns the top-level members of this version of the REST API
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, keys class_hash);
    }
}

/** @REST /v7/system/listeners/{id_or_name} (/system/listeners/{id_or_name})

    This REST URI path provides actions and information related to a specific HTTP listener
*/
class ListenerRestClassV7 inherits ListenerRestClass {
    constructor(hash<auto> lh) : ListenerRestClass(lh) {
    }

    /** @REST POST action=reloadCertificate

        @SCHEMA
        @summary Reloads the certificate and private key from the original file locations and uses the new \
        certificate for new connections

        @desc Reloads the certificate and private key from the original file locations and uses the new \
        certificate for new connections

        @return (string): the string "OK"

        @error (401): listener is not an HTTPS listener or no certificate source location information is stored \
        against the listener
        @ENDSCHEMA
    */
    hash<auto> postReloadCertificate(hash<auto> cx, *hash<auto> ah) {
        # reload listener
        try {
            Qorus.httpServer.reloadListenerCertificate(lh.id);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "REFRESH-CERTIFICATE-ERROR") {
                rethrow "LISTENER-ARG-ERROR", sprintf("%s: %s", ex.err, ex.desc);
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, "OK");
    }
}

/** @REST /v7/system/listeners (/system/listeners)

    This REST URI path provides actions and information related to Qorus HTTP listeners
*/
class ListenersRestClassV7 inherits ListenersRestClass {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = Qorus.httpServer.getListeners();
        *hash<auto> lh = h{arg};
        # if the listener number doesn't match, search by name
        if (!lh) {
            foreach hash<auto> lih in (h.iterator()) {
                if (lih.name == arg) {
                    lh = lih;
                    break;
                }
            }
        }

        return lh ? new ListenerRestClassV7(lh) : NOTHING;
    }
}

/** @REST /v7/services/{id_or_name}/resource_files/{name} (/services/{id_or_name}/resource_files/{name})

    This REST URI path provides information about a particular service resource file.
*/
class ServiceResourceFileRestClassV7 inherits ServiceResourceFileRestClass {
    constructor(hash<auto> sh, string rsrc, hash<auto> rh) : ServiceResourceFileRestClass(sh, rsrc, rh) {
    }

    /** @REST GET action=download

        @par Return Value
        Returns the service resource file data requested
    */
    hash<HttpHandlerResponseInfo> getDownload(hash<auto> cx, *hash<auto> ah) {
        string ct = get_mime_type_from_ext(rsrc);
        if (!cx.aih."*/*" && !cx.aih{ct}) {
            return <HttpHandlerResponseInfo>{
                "code": 406,
                "body": sprintf("resource %y has MIME type %y which is not acceptable by the client", rsrc, ct),
            };
        }

        cx.socketobject.sendHTTPResponse(200, HttpServer::HttpCodes."200", cx.hdr.http_version ?? "1.1", {
                "Content-Type": ct,
            },
            rh."data",
        );

        return <HttpHandlerResponseInfo>{
            "reply_sent": True,
        };
    }
}

/** @REST /v7/services/{id_or_name}/resource_files (/services/{id_or_name}/resource_files)

    This REST URI path provides information about service resource files.
*/
class ServiceResourceFilesRestClassV7 inherits ServiceResourceFilesRestClass {
    constructor(hash<auto> sh, *hash<auto> rh) : ServiceResourceFilesRestClass(sh, rh) {
    }

    QorusRestClass doGetResourceFileRestClass(hash<auto> sh, string arg) {
        return new ServiceResourceFileRestClassV7(sh, arg, rh{arg});
    }
}

/** @REST /v7/services/{id_or_name} (/v6/services/{id_or_name})

    This REST URI path provides actions and information related to Qorus services.
*/
class ServiceDefinitionRestClassV7 inherits ServiceDefinitionRestClassV6 {
    constructor(hash<auto> sh) : ServiceDefinitionRestClassV6(sh) {
    }

    private QorusRestClass doGetServiceResourceFilesRestClass() {
        return new ServiceResourceFilesRestClassV7(sh, (map {$1.name: $1 - "name"}, sh.resource_files));
    }
}

/** @REST /v7/services (/v6/services)

    This REST URI path provides actions and information related to Qorus services;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class ServiceRestClassV7 inherits ServiceRestClassV6 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = ServiceRestClass::staticGetServiceId(arg);
        *hash<auto> svc = ServiceRestClass::staticGetService(cx, id, ah, 7);
        if (!svc) {
            return;
        }

        return new ServiceDefinitionRestClassV7(svc);
    }
}

/** @REST /v7/system (/v6/system)

    This REST URI path provides actions and information for system functionality
*/
class SystemRestClassV7 inherits SystemRestClassV6 {
    public {
        const SubClasses = SystemRestClassV6::SubClasses + {
            "listeners": "ListenersRestClassV7",
        };
    }

    hash<auto> internGetInfo(hash<auto> cx) {
        TimeZone tz = TimeZone::get();
        return SystemRestClassV6::internGetInfo(cx) + {
            "tz_region": tz.region(),
            "tz_utc_offset": tz.UTCOffset(),
            "api_version": "v7",
        };
    }

    private hash<string, string> doGetSubClasses() {
        return SubClasses;
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
        - edition (string): \c Enterprise for Qorus Integration Engine(R) Enterprise Edition
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
        - tz_region (string): the time zone region the server is running in
        - tz_utc_offset (int): the UTC offset in seconds east of UTC; negative numbers indicate west of UTC
        - templates (list<hash TemplateInfo>): a list of template info hashes
          - name (string): the name of the template
          - desc (string): a markdown description of the template
          - doc_url (string): a URL to online documentation for the template
          - valid_context (int): a bitfield of @ref TemplateContextValues giving the valid context for the template
          - access (int): a bitfield of read/write access information for the template; 1 = read, 2 = write
        @ENDSCHEMA
    */
}

/** @REST /v7/dataprovider/factories/{factory}/provider (/v6/dataprovider/factories/{factory}/provider)

    This URI path provides access to a data provider created from a data provider factory

    @par Arguments
    This URI path element is reachable only if a provider can be created from the factory; to create the provider,
    the following hash argument is removed from the argument list before passing onward for processing:
    - \c provider_options: the options to be passed to the factory creation method to create the provider
*/
class DataProviderRestClassV7 inherits DataProviderRestClassV6 {
    public {
        const FieldKeys = (
            "type",
            "desc",
            "default_value",
            "opts",
        );
    }

    constructor(AbstractDataProvider provider) : DataProviderRestClassV6(provider) {
    }

    /** @REST PUT action=search

        @SCHEMA
        @summary Searches for records matching the search parameters

        @desc Searches for records matching the search parameters

        @params
        - provider_options (*hash[any] UndefinedHash): any options to be passed to a factory creation method when \
          accessing this URI endpoint through a factory
        - where_cond (*hash[any] UndefinedHash): the where CreatorJobDefinitionRestClass
        - search_options (*hash[any] UndefinedHash): any search options

        @return (*list<hash[any] UndefinedHash): list of record hashes matching the search parameters given by \
        \c where_cond

        @error (400): the data provider does not support searching
        @error (403): AUTHORIZATION-ERROR: this exception is thrown when @ref RBAC is enabled, and the user does not \
        have sufficient privileges for the operation

        @perms DATA-PROVIDER-CONTROL, DATA_PROVIDER_READ
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putSearch(hash<auto> cx, *hash<auto> ah) {
        *bool requires_result;
        if (exists ah.search_options.requires_result) {
            requires_result = parse_boolean(remove ah.search_options.requires_result);
        }
        on_error if ($1.err == "INVALID-OPERATION") {
            rethrow "REST-ARG-ERROR", sprintf("%s: %s", $1.err, $1.desc);
        }
        AbstractDataProviderRecordIterator i = provider.searchRecords(ah.where_cond, ah.search_options);
        *list<auto> rv = map $1, i;
        if (requires_result && !rv) {
            throw "NO-DATA-ERROR", sprintf("data provider %y: search criteria %y returned no records, and "
                "\"requires_result\" is set", provider.getName(), ah.where_cond);
        }
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=searchSingleRecord

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c where_cond: search parameters
        - \c search_options: search options

        @par Return Value
        Returns a single record matching the search parameters given by \a where_cond or no value

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: data provider does not support searching or search matches multiple records
    */
    hash<HttpHandlerResponseInfo> putSearchSingleRecord(hash<auto> cx, *hash<auto> ah) {
        *bool requires_result;
        if (exists ah.search_options.requires_result) {
            requires_result = parse_boolean(remove ah.search_options.requires_result);
        }
        on_error if ($1.err == "INVALID-OPERATION" || $1.err == "MULTIPLE-RECORDS-ERROR") {
            rethrow "REST-ARG-ERROR", sprintf("%s: %s", $1.err, $1.desc);
        }
        *hash<auto> rv = provider.searchSingleRecord(ah.where_cond, ah.search_options);
        if (requires_result && !rv) {
            throw "NO-DATA-ERROR", sprintf("data provider %y: search criteria %y returned no records, and "
                "\"requires_result\" is set", provider.getName(), ah.where_cond);
        }
        return RestHandler::makeResponse(200, rv);
    }

   /** @REST PUT action=searchStream

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
    AbstractRestStreamRequestHandler streamPutSearchStream(hash<auto> cx, *hash<auto> ah) {
        return new DataProviderSearchStream(provider, cx, ah);
    }

    /** @REST POST action=providerCreate

        @SCHEMA
        @summary Creates a child data provider

        @desc This API creates a child data provider, if the data provider supports child creation

        @params
        - name (string): the name of the new child provider
        - fields (hash[hash QorusNewFieldInfo] QorusNewFieldSetInfo): the set of fields making up the new record \
          where keys are field names and values describe each field
          - type (string): the type of the field
          - desc (string): field description
          - default_value (any): the default value of the field if not present; the value must be compatible with \
            the field's type
          - opts (*hash): any options for the given type

        @return (string): the string "OK"

        @error (400): returned if the request has no name or fields keys or if the data provider does not support \
        the current operation
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postProviderCreate(hash<auto> cx, *hash<auto> ah) {
        if (ah.name.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("\"name\" argument missing or invalid (expecting type "
                "\"string\"; got %y", ah.name.type()));
        }
        if (ah.fields.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, sprintf("\"fields\" argument missing or invalid (expecting type "
                "\"hash\"; got %y", ah.fields.type()));
        }
        if (exists ah.options && !exists ah.opts) {
            ah.opts = remove ah.options;
        }
        if (exists ah.opts && ah.opts.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, sprintf("\"opts\" argument must be hash if present; got type %y "
                "instead", ah.opts.type()));
        }
        hash<string, AbstractDataField> fields = map {$1.key: doGetField($1.key, $1.value)}, ah.fields.pairIterator();
        on_error {
            if ($1.err == "INVALID-OPERATION") {
                rethrow "DATAPROVIDER-ARG-ERROR";
            }
        }
        provider.createChildProvider(ah.name, fields, ah.options);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST DELETE action=child

        @par Description
        Permanently deletes the given child data provider

        @par Return Value
        This API returns a hash with the following key:
        - \c name: (required string) the name of the child provider to delete

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c name key or if the data provider does not
          support the current operation
    */
    hash<HttpHandlerResponseInfo> delChild(hash<auto> cx, *hash<auto> ah) {
        if (ah.name.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("\"name\" argument missing or invalid (expecting type "
                "\"string\"; got %y", ah.name.type()));
        }
        on_error {
            if ($1.err == "INVALID-OPERATION") {
                rethrow "DATAPROVIDER-ARG-ERROR";
            }
        }
        provider.deleteChildProvider(ah.name);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST POST action=fieldAdd

        @par Description
        This API adds a field to the provider, if the data provider supports adding fields

        @par Arguments
        This API takes the following hash argument (either as URI arguments or in the message body):
        - \c name: (required string) the name of the new child provider
        - \c field: (required hash) a hash with the following keys:
          - \c type: (string) the type of the field
          - \c desc: (string) field description
          - \c default_value: (value of field's type) the default value of the field if not present
          - \c opts: (hash) any options for the given type
        - \c opts: (optional hash) any field creation options supported by the data provider

        @par Return Value
        The string \c "OK"

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c name or \c fields keys or if the data
          provider does not support the current operation
    */
    hash<HttpHandlerResponseInfo> postFieldAdd(hash<auto> cx, *hash<auto> ah) {
        if (ah.name.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("\"name\" argument missing or invalid (expecting type "
                "\"string\"; got %y", ah.name.type()));
        }
        if (ah.field.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, sprintf("\"field\" argument missing or invalid (expecting type "
                "\"hash\"; got %y", ah.field.type()));
        }
        if (exists ah.options && !exists ah.opts) {
            ah.opts = remove ah.options;
        }
        if (exists ah.opts && ah.opts.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, sprintf("\"opts\" argument must be hash if present; got type %y "
                "instead", ah.opts.type()));
        }
        AbstractDataField field = doGetField(ah.name, ah.field);
        on_error {
            if ($1.err == "INVALID-OPERATION") {
                rethrow "DATAPROVIDER-ARG-ERROR";
            }
        }
        provider.addField(field, ah.opts);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=field

        @par Description
        This API updated a field in the provider, if the data provider supports updating fields

        @par Arguments
        This API takes the following hash argument (either as URI arguments or in the message body):
        - \c name: (required string) the current name of the field
        - \c new_name: (optional string) the new name of the field
        - \c field: (optional hash) a hash with the following keys:
          - \c type: (string) the type of the field
          - \c desc: (string) field description
          - \c default_value: (value of field's type) the default value of the field if not present
          - \c opts: (hash) any options for the given type
        - \c opts: (optional hash) any field update options supported by the data provider

        @par Return Value
        The string \c "OK"

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c old_name key or if the data provider does
          not support the current operation
    */
    hash<HttpHandlerResponseInfo> putField(hash<auto> cx, *hash<auto> ah) {
        if (ah.name.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("\"name\" argument missing or invalid (expecting type "
                "\"string\"; got %y", ah.name.type()));
        }
        if (exists ah.new_name && ah.new_name.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("\"new_name\" argument must be hash if present; got type "
                "%y instead", ah.new_name.type()));
        }
        if (exists ah.field && ah.field.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, sprintf("\"field\" argument must be hash if present; got type %y "
                "instead", ah.field.type()));
        }
        if (exists ah.options && !exists ah.opts) {
            ah.opts = remove ah.options;
        }
        if (exists ah.opts && ah.opts.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, sprintf("\"opts\" argument must be hash if present; got type %y "
                "instead", ah.opts.type()));
        }
        AbstractDataField field;
        if (ah.field) {
            field = doGetField(ah.new_name ?? ah.name, ah.field);
        } else {
            *hash<string, AbstractDataField> fields = provider.getRecordType();
            if (!fields{ah.name}) {
                throw "FIELD-ARG-ERROR", sprintf("provider %y has no field %y to update", provider.getName(), ah.name);
            }
            field = fields{ah.name};
        }
        on_error {
            if ($1.err == "INVALID-OPERATION") {
                rethrow "DATAPROVIDER-ARG-ERROR";
            }
        }
        provider.updateField(ah.name, field, ah.opts);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST DELETE action=field

        @par Description
        Permanently deletes the given field from the data provider

        @par Return Value
        This API returns a hash with the following key:
        - \c name: (required string) the name of the field to delete

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has no \c name key or if the data provider does not
          support the current operation
    */
    hash<HttpHandlerResponseInfo> delField(hash<auto> cx, *hash<auto> ah) {
        if (ah.name.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("\"name\" argument missing or invalid (expecting type "
                "\"string\"; got %y", ah.name.type()));
        }
        on_error {
            if ($1.err == "INVALID-OPERATION") {
                rethrow "DATAPROVIDER-ARG-ERROR";
            }
        }
        provider.deleteField(ah.name);
        return RestHandler::makeResponse(200, "OK");
    }

    static AbstractDataField doGetField(string name, auto f) {
        if (f.typeCode() != NT_HASH) {
            throw "FIELD-ARG-ERROR", sprintf("field %y value must be type \"hash\"; got type %y instead", name, f.type());
        }
        if (exists f.options && !exists f.opts) {
            f.opts = remove f.options;
        }
        if (*hash<auto> err = (f - FieldKeys)) {
            throw "FIELD-ARG-ERROR", sprintf("field %y has unknown keys: %y; known keys: %y", name, keys err, FieldKeys);
        }
        return new QoreDataField(name, f.desc, AbstractDataProviderType::get(f.type ?? "string", f.opts),
            f.default_value);
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV7(provider);
    }
}

/** @REST /v7/dataprovider/factories/{factory} (/v6/dataprovider/factories/{factory})

    This URI path provides access to data factory information
*/
class DataProviderFactoryRestClassV7 inherits DataProviderFactoryRestClassV6 {
    constructor(string name, AbstractDataProviderFactory factory) : DataProviderFactoryRestClassV6(name, factory) {
    }

    private DataProviderRestClass doGetDataProviderRestClass(AbstractDataProvider provider) {
        return new DataProviderRestClassV7(provider);
    }
}

/** @REST /v7/dataprovider/factories (/v6/dataprovider/factories)

    This URI path provides access to data factory information
*/
class DataProviderFactoriesRestClassV7 inherits DataProviderFactoriesRestClassV6 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProviderFactory factory = DataProvider::getFactory(arg);
        if (factory) {
            return new DataProviderFactoryRestClassV7(arg, factory);
        }
    }

    private *list<hash<auto>> doGetFactoryInfo(*list<string> factory_list, *hash<auto> ah) {
        return map DataProviderFactoryRestClassV7::doGetInfo($1, DataProvider::getFactory($1), ah), factory_list;
    }
}

/** @REST /v7/dataprovider/dataproviders/.../{name}

    This URI path provides access to functionality related to listing available data providers
*/
class DataProviderListRestClassV7 inherits DataProviderRestClassV7 {
    private {
        string path;
    }

    constructor(string path, AbstractDataProvider provider) : DataProviderRestClassV7(provider) {
        self.path = path
            ? path + "/" + provider.getName()
            : provider.getName();
    }

    string name() {
        return path;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *AbstractDataProvider child = provider.getChildProvider(arg);
        if (child) {
            return new DataProviderListRestClassV7(path, child);
        }

        return doSubClassArg(arg, cx, ah);
    }

    /** @REST GET

        @par Description
        Returns a list of available data providers
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (map path + "/" + $1, provider.getChildProviderNames()));
    }

    /** @REST GET action=info

        @par Description
        Returns data provider information
    */
    hash<HttpHandlerResponseInfo> getInfo(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, doGetInfo(ah));
    }
}

/** @REST /v7/dataprovider/dataproviders/datasource

    This URI path provides access to functionality related to listing available data providers
*/
class DataProviderListTypeRestClassV7 inherits QorusRestClass {
    private {
        string type;

        const ValidArgs = {
            "connection": True,
            "datasource": True,
            "qorus": True,
        };
    }

    constructor(string type) {
        self.type = type;
    }

    string name() {
        return type;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        try {
            string path = type + "/" + arg;
            return new DataProviderListRestClassV7(path, UserApi::getDataProvider(path));
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "DATA-PROVIDER-ERROR") {
                rethrow;
            }
        }
    }

    /** @REST GET

        @par Description
        Returns a list of available data providers
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        list<string> paths = ();

        ReadLockHelper rlh(Qorus.connection_rwl);

        *hash<string, hash<EditMapInfo>> edit_map = Qorus.qmm.getEditMapForTypeLocked("connection");

        switch (type) {
            case "datasource": {
                # get datasource connections
                DataProvidersRestClassV7::processProvider("datasource", \paths, Qorus.dsmanager, edit_map);
                break;
            }

            case "connection": {
                # get user connections
                DataProvidersRestClassV7::processProvider("connection", \paths, Qorus.connections, edit_map);
                break;
            }

            case "qorus": {
                # get server connections
                DataProvidersRestClassV7::processProvider("qorus", \paths, Qorus.remotemonitor, edit_map);
                break;
            }
        }

        return RestHandler::makeResponse(200, paths);
    }
}

/** @REST /v7/dataprovider/dataproviders/connection (/v7/dataprovider/dataproviders/datasource)

    This URI path provides access to functionality related to listing available data providers
*/

/** @REST /v7/dataprovider/dataproviders/qorus (/v7/dataprovider/dataproviders/datasource)

    This URI path provides access to functionality related to listing available data providers
*/

/** @REST /v7/dataprovider/dataproviders

    This URI path provides access to functionality related to listing available data providers
*/
class DataProvidersRestClassV7 inherits QorusRestClass {
    public {
        const DefaultQorusDataProviders = (
            "qorus-api",
        );
    }

    string name() {
        return "dataproviders";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        switch (arg) {
            case "qorus-api":
                return new DataProviderListRestClassV7("", create_object("QorusApiDataProvider"));
            case "datasource":
            case "qorus":
            case "connection":
                return new DataProviderListTypeRestClassV7(arg);
        }
    }

    /** @REST GET

        @par Description
        Returns a list of available data providers
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        # FIXME: replace with an implementation based on a data provider registry API
        list<string> paths = doGetInitialDataProviderPathList(cx);
        return RestHandler::makeResponse(200, paths);
    }

    list<string> doGetDefaultQorusDataProviders() {
        return DefaultQorusDataProviders;
    }

    list<string> doGetInitialDataProviderPathList(hash<auto> cx) {
        list<string> paths = doGetDefaultQorusDataProviders();

        ReadLockHelper rlh(Qorus.connection_rwl);

        *hash<string, hash<EditMapInfo>> edit_map = Qorus.qmm.getEditMapForTypeLocked("connection");

        # get datasource connections
        processProvider("datasource", \paths, Qorus.dsmanager, edit_map);
        # get user connections
        processProvider("connection", \paths, Qorus.connections, edit_map);
        # get server connections
        processProvider("qorus", \paths, Qorus.remotemonitor, edit_map);

        return paths;
    }

    static processProvider(string type, reference<list<string>> paths, object obj,
                                   *hash<string, hash<EditMapInfo>> edit_map) {
        map paths += sprintf("%s/%s", type, $1.name), obj.getListLocked(edit_map), $1.has_provider;
    }
}

/** @REST /v7/slas/{sla}

    This REST URI path provides actions and information about a particular Qorus SLA
*/
class SlaRestClassV7 inherits SlaRestClass {
    constructor(hash<SlaInfo> h) : SlaRestClass(h) {
    }

    /** @REST POST action=success

        @SCHEMA
        @summary Posts a success event for the SLA

        @desc Posts a success event for the SLA

        @params
        - value (number): the event value

        @return (bool): @ref True if the event was posted
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postSuccess(hash<auto> cx, *hash<auto> ah) {
        number value = doGetNumber(ah, "value");
        bool rv = Qorus.qmm.postSlaEventSuccess(h.name, value, CodeActionReason::getSource() ?? "system");
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST POST action=error

        @SCHEMA
        @summary Posts an error event for the SLA

        @desc Posts an error event for the SLA

        @params
        - value (number): the event value
        - err (string): the error code
        - desc (string): the error description

        @return (bool): @ref True if the event was posted
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postError(hash<auto> cx, *hash<auto> ah) {
        number value = doGetNumber(ah, "value");
        string err = doGetString(ah, "err");
        string desc = doGetString(ah, "desc");
        bool rv = Qorus.qmm.postSlaEventError(h.name, value, CodeActionReason::getSource() ?? "system", err, desc);
        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /v7/slas

    This REST URI path provides actions and information about Qorus SLAs
*/
class SlasRestClassV7 inherits SlasRestClass {
    public {
        const FakeSlaInfo = <SlaInfo>{
            "slaid": -1,
            "name": "fake-sla",
            "units": "seconds",
            "description": "fake SLA",
        };
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int slaid = staticGetSlaId(arg);
        if (!slaid) {
            # allow post methods on non-existant SLAs to run
            if (cx.hdr.method == "POST") {
                return new SlaRestClassV7(FakeSlaInfo);
            }
            return;
        }
        *hash<SlaInfo> h = Qorus.qmm.lookupSla(slaid);
        if (h) {
            return new SlaRestClassV7(h);
        }
    }
}

/** @REST /v7/dataprovider (/v6/dataprovider)

    This URI path provides access to data provider functionality
*/
class DataProviderBaseRestClassV7 inherits DataProviderBaseRestClassV6 {
    private setup() {
        addClass(new DataProviderFactoriesRestClassV7());
        addClass(new DataProviderTypesRestClassV6());
        addClass(new DataProviderBaseTypesRestClassV5());
        addClass(new DataProviderRestClassV7(create_object("QorusApiDataProvider")));
        addClass(new DataProvidersRestClassV7());
        addClass(new DataProviderBrowseRoot());
    }

    /** @REST PUT action=type

        @SCHEMA
        @summary Returns type information for the given data provider information

        @desc Returns type information for the given data provider information

        @params
        - soft (*bool): if a "soft" type should be returned
        - type (hash QorusTypeInfo): hash describing the input or receiving type (type of variable to accept \
          \a type)
          - type (string): one of \c connection, \c datasource, \c factory, \c remote, or \c type
          - name (string): the name of the type, connection, factory, etc
          - path (*string): the path to the final object
          - subtype (*string): the subtype for \a type = \c connection
          - options (*hash): create option for \a type = \c factory
          - hasApiContext (*bool): \c True if the type is a factory with options to be handled in an API
            management context

        @return (hash DataProviderTypeInfo): data provider type information
        - name (string): the type name
        - desc (string): the description of the type
        - supported_options (*hash[any] UndefinedHash): transformation options supported by the type
        - options (*hash[any] UndefinedHash): transformation option values
        - base_type (string): the Qore base type name
        - mandatory (bool): can be null / missing?
        - types_accepted (list<string>): list of types accepted on input
        - types_returned (list<string>): list of types returned
        - fields (*hash[any] UndefinedHash): fields supported by the type
        - can_manage_fields (bool): @ref True if fields can be added dynamically to the type
        - tags (*hash[any] UndefinedHash): any tags set on the type
        - or_nothing_type (bool): if @ref True, the type will accept @ref NOTHING
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putType(hash<auto> cx, *hash<auto> ah) {
        bool soft = parse_boolean(ah.soft);
        AbstractDataProviderType type = DataProviderBaseRestClassV5::doGetType("type", ah);
        return RestHandler::makeResponse(200, (soft ? type.getSoftType().getInfo() : type.getInfo()) + {
            "or_nothing_type": type.isOrNothingType(),
        });
    }

    /** @REST POST action=callApi

        @SCHEMA
        @summary Makes an API call and returns the response

        @desc Makes an API call with a request-response data provider and returns the response

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[any] UndefinedHash): factory constructor options; invalid options are silently ignored
        - args (any): any arguments to the API call; if present this will be resolved as a template with a \
          call to UserApi::expandTemplatedValue() with \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve arguments
        - request_options (*hash[any] UndefinedHash): any request options

        @return (any): the return value of the API call

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postCallApi(hash<auto> cx, *hash<auto> ah) {
        return doPostCallApiIntern(cx, ah);
    }

    /** @REST POST action=callApiFromUi

        @SCHEMA
        @summary Makes an API call and returns the response

        @desc Makes an API call with a request-response data provider and returns the response; certain arguments \
        are expected in a format used by UI clients

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[hash TypeValueInfo] UndefinedUiHash): factory constructor options; invalid options are \
          silently ignored
          - type (string): the expected type of the argument
          - value (any): the value of the argument, for values that cannot be serialized as JSON, this will be a \
            string in YAML format
        - args (any): any arguments to the API call; if this argument is a hash, then each hash key must be assigned \
          a hash value with \c type and \c value keys, additionally, if present this will be \
          resolved as a template with a call to UserApi::expandTemplatedValue() with \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve arguments
        - request_options (*hash[hash TypeValueInfo] UndefinedUiHash): any request options

        @return (any): the return value of the API call

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postCallApiFromUi(hash<auto> cx, *hash<auto> ah) {
        return doPostCallApiIntern(cx, ah, True);
    }

    /** @REST POST action=searchRecords

        @SCHEMA
        @summary Performs a search in a data provider and returns the result record set

        @desc Performs a search in a record-based data provider and returns the result as a list of zero or more \
        hashes representing the records matched

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[any] UndefinedHash): factory constructor options; invalid options are silently ignored
        - where (*hash[any] UndefinedHash): the search criteria for the search where keys are field names and values \
          are either values to be matched or a hash describing a comparison operator for the column with \c op and \
          \c value keys; if present this will be resolved as a template with a call to \
          UserApi::expandTemplatedValue() with \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument
        - search_options (*hash[any] UndefinedHash): any search options

        @return (*list<hash[any] UndefinedHash>): the records matching the search criteria

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postSearchRecords(hash<auto> cx, *hash<auto> ah) {
        return doPostSearchRecordsIntern(cx, ah);
    }

    /** @REST POST action=searchRecordsFromUi

        @SCHEMA
        @summary Performs a search in a data provider and returns the result record set

        @desc Performs a search in a record-based data provider and returns the result as a list of zero or more \
        hashes representing the records matched; certain arguments are expected in a format used by UI clients

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[hash TypeValueInfo] UndefinedUiHash): factory constructor options; invalid options are \
          silently ignored
        - where (*hash[any] UndefinedHash): the search criteria for the search where keys are field names and values \
          are either values to be matched or a hash describing a comparison operator for the column with \c op and \
          \c value keys; if present this will be resolved as a template with a call to \
          UserApi::expandTemplatedValue() with \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument
        - search_options (*hash[hash TypeValueInfo] UndefinedUiHash): any search options

        @return (*list<hash[any] UndefinedHash>): the records matching the search criteria

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postSearchRecordsFromUi(hash<auto> cx, *hash<auto> ah) {
        return doPostSearchRecordsIntern(cx, ah, True);
    }

    /** @REST POST action=searchSingleRecord

        @SCHEMA
        @summary Performs a search in a data provider and returns the result record or no value

        @desc Performs a search in a record-based data provider and returns the result record, if there is a match, \
        or no value if not

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[any] UndefinedHash): factory constructor options; invalid options are silently ignored
        - where (hash[any] UndefinedHash): the search criteria for the search where keys are field names and values \
          are either values to be matched or a hash describing a comparison operator for the column; if present this \
          will be resolved as a template with a call to UserApi::expandTemplatedValue() with \a context as the local \
          context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument
        - search_options (*hash[any] UndefinedHash): any search options

        @return (*hash[any] UndefinedHash): the record matching the search criteria or no value if there is no match

        @error (400): missing or invalid required arguments or if multiple records match the search criteria
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postSearchSingleRecord(hash<auto> cx, *hash<auto> ah) {
        return doPostSearchSingleRecordIntern(cx, ah);
    }

    /** @REST POST action=searchSingleRecordFromUi

        @SCHEMA
        @summary Performs a search in a data provider and returns the result record or no value

        @desc Performs a search in a record-based data provider and returns the result record, if there is a match, \
        or no value if not; certain arguments are expected in a format used by UI clients

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[hash TypeValueInfo] UndefinedUiHash): factory constructor options; invalid options are \
          silently ignored
        - where (hash[hash TypeValueInfo] UndefinedUiHash): the search criteria for the search where keys are field \
          names and values are either values to be matched or a hash describing a comparison operator for the column; \
          if present this will be resolved as a template with a call to UserApi::expandTemplatedValue() with \
          \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument
        - search_options (*hash[hash TypeValueInfo] UndefinedUiHash): any search options

        @return (*hash[any] UndefinedHash): the record matching the search criteria or no value if there is no match

        @error (400): missing or invalid required arguments or if multiple records match the search criteria
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postSearchSingleRecordFromUi(hash<auto> cx, *hash<auto> ah) {
        return doPostSearchSingleRecordIntern(cx, ah, True);
    }

    /** @REST POST action=updateRecords

        @SCHEMA
        @summary Performs an update action in a data provider and returns the number of records updated

        @desc Performs an update action in a data provider and returns the number of records updated

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[any] UndefinedHash): factory constructor options; invalid options are silently ignored
        - set (hash[any] UndefinedHash): keys are field names and values are field values to be updated; values will \
          be resolved as a template with a call to UserApi::expandTemplatedValue() with \a context as the local \
          context
        - where (*hash[any] UndefinedHash): the search criteria for the search where keys are field names and values \
          are either values to be matched or a hash describing a comparison operator for the column with \c op and \
          \c value keys; if present this will be resolved as a template with a call to \
          UserApi::expandTemplatedValue() with \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument
        - search_options (*hash[any] UndefinedHash): any search options

        @return (hash AffectedRecordInfo): a hash describing the number of records affected by the operation
        - affected_records (int): the number of records affected by the operation

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postUpdateRecords(hash<auto> cx, *hash<auto> ah) {
        return doPostUpdateRecordsIntern(cx, ah);
    }

    /** @REST POST action=updateRecordsFromUi

        @SCHEMA
        @summary Performs an update action in a data provider and returns the number of records updated

        @desc Performs an update action in a data provider and returns the number of records updated

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[hash TypeValueInfo] UndefinedUiHash): factory constructor options; invalid options are \
          silently ignored
        - set (hash[hash TypeValueInfo] UndefinedUiHash): keys are field names and values are field values to be \
          updated; values will be resolved as a template with a call to UserApi::expandTemplatedValue() with \
          \a context as the local context
        - where (hash[hash TypeValueInfo] UndefinedUiHash): the search criteria for the search where keys are field \
          names and values are either values to be matched or a hash describing a comparison operator for the column; \
          if present this will be resolved as a template with a call to UserApi::expandTemplatedValue() with \
          \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument
        - search_options (*hash[hash TypeValueInfo] UndefinedUiHash): any search options

        @return (hash AffectedRecordInfo): a hash describing the number of records affected by the operation
        - affected_records (int): the number of records affected by the operation

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postUpdateRecordsFromUi(hash<auto> cx, *hash<auto> ah) {
        return doPostUpdateRecordsIntern(cx, ah, True);
    }

    /** @REST POST action=deleteRecords

        @SCHEMA
        @summary Deletes records from a data provider and returns the number of deleted records

        @desc Deletes records from a data provider and returns the number of deleted records

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[any] UndefinedHash): factory constructor options; invalid options are silently ignored
        - where (*hash[any] UndefinedHash): the search criteria for the search where keys are field names and values \
          are either values to be matched or a hash describing a comparison operator for the column with \c op and \
          \c value keys; if present this will be resolved as a template with a call to \
          UserApi::expandTemplatedValue() with \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument
        - search_options (*hash[any] UndefinedHash): any search options

        @return (hash AffectedRecordInfo): a hash describing the number of records affected by the operation
        - affected_records (int): the number of records affected by the operation

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postDeleteRecords(hash<auto> cx, *hash<auto> ah) {
        return doPostDeleteRecordsIntern(cx, ah);
    }

    /** @REST POST action=deleteRecordsFromUi

        @SCHEMA
        @summary Deletes records from a data provider and returns the number of deleted records

        @desc Deletes records from a data provider and returns the number of deleted records

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[hash TypeValueInfo] UndefinedUiHash): factory constructor options; invalid options are \
          silently ignored
        - where (*hash[any] UndefinedHash): the search criteria for the search where keys are field names and values \
          are either values to be matched or a hash describing a comparison operator for the column with \c op and \
          \c value keys; if present this will be resolved as a template with a call to \
          UserApi::expandTemplatedValue() with \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument
        - search_options (*hash[hash TypeValueInfo] UndefinedUiHash): any search options

        @return (hash AffectedRecordInfo): a hash describing the number of records affected by the operation
        - affected_records (int): the number of records affected by the operation

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postDeleteRecordsFromUi(hash<auto> cx, *hash<auto> ah) {
        return doPostDeleteRecordsIntern(cx, ah, True);
    }

    /** @REST POST action=createRecords

        @SCHEMA
        @summary Creates new records in a data provider and returns the number of created records

        @desc Creates new records in a data provider and returns the number of created records

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[any] UndefinedHash): factory constructor options; invalid options are silently ignored
        - records (list<hash[any] UndefinedHash>): the list of new records; each hash in the list represents a new \
          record and must have keys that correspond to valid field names, values are subjected to template \
          resolution by calls to UserApi::expandTemplatedValue() with \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument

        @return (list<hash[any] UndefinedHash>): the record set inserted

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postCreateRecords(hash<auto> cx, *hash<auto> ah) {
        return doPostCreateRecordsIntern(cx, ah);
    }

    /** @REST POST action=createRecordsFromUi

        @SCHEMA
        @summary Creates new records in a data provider and returns the number of created records

        @desc Creates new records in a data provider and returns the number of created records

        @params
        - type (string): the type of path: \c factory, \c connection, \c datasource, or \c remote
        - name (string): the initial segment of the data provider path
        - path (*string): the path to the data provider
        - options (*hash[hash TypeValueInfo] UndefinedUiHash): factory constructor options; invalid options are \
          silently ignored
        - records (list<hash[hash TypeValueInfo] UndefinedUiHash>): the list of new records; each hash in the list \
          represents a new record and must have keys that correspond to valid field names, values are subjected to \
          template resolution by calls to UserApi::expandTemplatedValue() with \a context as the local context
        - context (*hash[any] UndefinedHash): any context data to be used to resolve the \a where argument

        @return (list<hash[any] UndefinedHash>): the record set inserted

        @error (400): missing or invalid required arguments
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> postCreateRecordsFromUi(hash<auto> cx, *hash<auto> ah) {
        return doPostCreateRecordsIntern(cx, ah, True);
    }

    hash<HttpHandlerResponseInfo> doPostCallApiIntern(hash<auto> cx, *hash<auto> ah, *bool ui) {
        # check and prepare / expand arguments
        string type = doGetString(ah, "type");
        string name = doGetString(ah, "name");
        *string path = doGetString(ah, "path", True);
        *hash<auto> ctxt = doGetHash(ah, "context", True);
        *hash<auto> opts = _priv_parse_ui_hash(doGetHash(ah, "options", True), ui, ctxt);
        *hash<auto> request_options = _priv_parse_ui_hash(doGetHash(ah, "request_options", True), ui, ctxt);
        if (exists ah.args) {
            if (ah.args.typeCode() == NT_HASH) {
                ah.args = _priv_parse_ui_hash(ah.args, ui, ctxt);
            } else {
                ah.args = UserApi::expandTemplatedValue(ah.args, ctxt);
            }
        }

        on_error if ($1.err == "DATA-PROVIDER-ERROR") {
            rethrow "DATA-PROVIDER-ARG-ERROR";
        }
        AbstractDataProvider prov = UserApi::getDataProvider(type, name, path, opts);
        if (!prov.supportsRequest()) {
            throw "API-CALL-ARG-ERROR", sprintf("data provider %y (identified by %s/%s%s) does not support the "
                "request-response integration pattern", prov.getName(), type, name, path);
        }

        QDBG_LOG("DataProviderBaseRestClassV7::doPostCallApiIntern() provider: %y args: %y", prov.getName(), ah.args);
        return RestHandler::makeResponse(200, prov.doRequest(ah.args, request_options));
    }

    hash<HttpHandlerResponseInfo> doPostSearchRecordsIntern(hash<auto> cx, *hash<auto> ah, *bool ui) {
        string type = doGetString(ah, "type");
        string name = doGetString(ah, "name");
        *string path = doGetString(ah, "path", True);
        *hash<auto> ctxt = doGetHash(ah, "context", True);
        *hash<auto> opts = _priv_parse_ui_hash(doGetHash(ah, "options", True), ui, ctxt);
        *hash<auto> search_options = _priv_parse_ui_hash(doGetHash(ah, "search_options", True), ui, ctxt);
        *bool requires_result;
        if (exists search_options.requires_result) {
            requires_result = parse_boolean(remove search_options.requires_result);
        }
        *hash<auto> where_hash = doGetWhereHash(ah, ctxt, ui);

        on_error if ($1.err == "DATA-PROVIDER-ERROR") {
            rethrow "DATA-PROVIDER-ARG-ERROR";
        }
        AbstractDataProvider prov = UserApi::getDataProvider(type, name, path, opts, ctxt);
        if (!prov.supportsRead()) {
            throw "API-CALL-ARG-ERROR", sprintf("data provider %y (identified by %s/%s%s) does not support "
                "search operations", prov.getName(), type, name, path);
        }

        QDBG_LOG("DataProviderBaseRestClassV7::doPostSearchRecordsIntern() provider: %y where: %y search opts: %y",
            prov.getName(), where_hash, search_options);

        *list<auto> rv = (map $1, prov.searchRecords(where_hash, search_options));
        if (!rv && requires_result) {
            throw "NO-DATA-ERROR", sprintf("data provider %y: search criteria %y returned no records, and "
                "\"requires_result\" is set", prov.getName(), where_hash);
        }
        return RestHandler::makeResponse(200, rv);
    }

    hash<HttpHandlerResponseInfo> doPostSearchSingleRecordIntern(hash<auto> cx, *hash<auto> ah, *bool ui) {
        string type = doGetString(ah, "type");
        string name = doGetString(ah, "name");
        *string path = doGetString(ah, "path", True);
        *hash<auto> ctxt = doGetHash(ah, "context", True);
        *hash<auto> opts = _priv_parse_ui_hash(doGetHash(ah, "options", True), ui, ctxt);
        *hash<auto> search_options = _priv_parse_ui_hash(doGetHash(ah, "search_options", True), ui, ctxt);
        *bool requires_result;
        if (exists search_options.requires_result) {
            requires_result = parse_boolean(remove search_options.requires_result);
        }
        *hash<auto> where_hash = doGetWhereHash(ah, ctxt, ui);

        on_error if ($1.err == "DATA-PROVIDER-ERROR" || $1.err == "MULTIPLE-RECORDS-ERROR") {
            rethrow "DATA-PROVIDER-ARG-ERROR";
        }
        AbstractDataProvider prov = UserApi::getDataProvider(type, name, path, opts, ctxt);
        if (!prov.supportsRead()) {
            throw "API-CALL-ARG-ERROR", sprintf("data provider %y (identified by %s/%s%s) does not support "
                "search operations", prov.getName(), type, name, path);
        }

        QDBG_LOG("DataProviderBaseRestClassV7::doPostSearchSingleRecordIntern() provider: %y where: %y search opts: "
            "%y", prov.getName(), where_hash, search_options);
        *hash<auto> rv = prov.searchSingleRecord(where_hash, search_options);
        if (!rv && requires_result) {
            throw "NO-DATA-ERROR", sprintf("data provider %y: search criteria %y returned no records, and "
                "\"requires_result\" is set", prov.getName(), where_hash);
        }
        return RestHandler::makeResponse(200, rv);
    }

    hash<HttpHandlerResponseInfo> doPostUpdateRecordsIntern(hash<auto> cx, *hash<auto> ah, *bool ui) {
        string type = doGetString(ah, "type");
        string name = doGetString(ah, "name");
        *string path = doGetString(ah, "path", True);
        *hash<auto> ctxt = doGetHash(ah, "context", True);
        *hash<auto> opts = _priv_parse_ui_hash(doGetHash(ah, "options", True), ui, ctxt);
        *hash<auto> search_options = _priv_parse_ui_hash(doGetHash(ah, "search_options", True), ui, ctxt);
        *bool requires_result;
        if (exists search_options.requires_result) {
            requires_result = parse_boolean(remove search_options.requires_result);
        }
        hash<auto> set_hash = doGetSetHash(ah, ctxt, ui);
        *hash<auto> where_hash = doGetWhereHash(ah, ctxt, ui);

        on_error if ($1.err == "DATA-PROVIDER-ERROR") {
            rethrow "DATA-PROVIDER-ARG-ERROR";
        }
        AbstractDataProvider prov = UserApi::getDataProvider(type, name, path, opts, ctxt);
        if (!prov.supportsUpdate()) {
            throw "API-CALL-ARG-ERROR", sprintf("data provider %y (identified by %s/%s%s) does not support "
                "update operations", prov.getName(), type, name, path);
        }

        QDBG_LOG("DataProviderBaseRestClassV7::doPostUpdateRecordsIntern() provider: %y set: %y where: %y "
            "search opts: %y", prov.getName(), set_hash, where_hash, search_options);

        int affected_records = prov.updateRecords(set_hash, where_hash, search_options);
        if (!affected_records && requires_result) {
            throw "NO-DATA-ERROR", sprintf("data provider %y: update: %y where: %y updated no records, and "
                "\"requires_result\" is set", prov.getName(), set_hash, where_hash);
        }
        return RestHandler::makeResponse(200, {"affected_records": affected_records});
    }

    hash<HttpHandlerResponseInfo> doPostDeleteRecordsIntern(hash<auto> cx, *hash<auto> ah, *bool ui) {
        string type = doGetString(ah, "type");
        string name = doGetString(ah, "name");
        *string path = doGetString(ah, "path", True);
        *hash<auto> ctxt = doGetHash(ah, "context", True);
        *hash<auto> opts = _priv_parse_ui_hash(doGetHash(ah, "options", True), ui, ctxt);
        *hash<auto> search_options = _priv_parse_ui_hash(doGetHash(ah, "search_options", True), ui, ctxt);
        *bool requires_result;
        if (exists search_options.requires_result) {
            requires_result = parse_boolean(remove search_options.requires_result);
        }
        *hash<auto> where_hash = doGetWhereHash(ah, ctxt, ui);

        on_error if ($1.err == "DATA-PROVIDER-ERROR") {
            rethrow "DATA-PROVIDER-ARG-ERROR";
        }
        AbstractDataProvider prov = UserApi::getDataProvider(type, name, path, opts, ctxt);
        if (!prov.supportsDelete()) {
            throw "API-CALL-ARG-ERROR", sprintf("data provider %y (identified by %s/%s%s) does not support "
                "delete operations", prov.getName(), type, name, path);
        }

        QDBG_LOG("DataProviderBaseRestClassV7::doPostDeleteRecordsIntern() provider: %y where: %y "
            "search opts: %y", prov.getName(), where_hash, search_options);

        int affected_records = prov.deleteRecords(where_hash, search_options);
        if (!affected_records && requires_result) {
            throw "NO-DATA-ERROR", sprintf("data provider %y: delete where: %y deleted no records, and "
                "\"requires_result\" is set", prov.getName(), where_hash);
        }
        return RestHandler::makeResponse(200, {"affected_records": affected_records});
    }

    hash<HttpHandlerResponseInfo> doPostCreateRecordsIntern(hash<auto> cx, *hash<auto> ah, *bool ui) {
        string type = doGetString(ah, "type");
        string name = doGetString(ah, "name");
        *string path = doGetString(ah, "path", True);
        *hash<auto> ctxt = doGetHash(ah, "context", True);
        *hash<auto> opts = _priv_parse_ui_hash(doGetHash(ah, "options", True), ui, ctxt);
        list<hash<auto>> records = doGetRecords(ah, ctxt, ui);
        on_error if ($1.err == "DATA-PROVIDER-ERROR") {
            rethrow "DATA-PROVIDER-ARG-ERROR";
        }
        AbstractDataProvider prov = UserApi::getDataProvider(type, name, path, opts, ctxt);
        if (!prov.supportsCreate()) {
            throw "API-CALL-ARG-ERROR", sprintf("data provider %y (identified by %s/%s%s) does not support "
                "create operations", prov.getName(), type, name, path);
        }

        QDBG_LOG("DataProviderBaseRestClassV7::doPostCreateRecordsIntern() provider: %y create %d record%s",
            prov.getName(), records.size(), records.size() == 1 ? "" : "s");

        list<hash<auto>> rv = map prov.createRecord($1), records;
        return RestHandler::makeResponse(200, rv);
    }

    *hash<auto> doGetWhereHash(*hash<auto> ah, *hash<auto> ctxt, *bool ui) {
        *hash<auto> where_hash = doGetHash(ah, "where", True);
        if (!where_hash) {
            return;
        }
        where_hash = UserApi::expandTemplatedValue(where_hash, ctxt);
        if (ui) {
            foreach hash<auto> i in (where_hash.pairIterator()) {
                auto arg = i.value.type != "string" && i.value.value.typeCode() == NT_STRING
                    ? parse_yaml(i.value.value),
                    : i.value.value;
                if (i.value.op.typeCode() == NT_LIST) {
                    switch (i.value.op.lsize()) {
                        case 1:
                            where_hash{i.key} = {
                                "op": i.value.op[0],
                                "arg": arg,
                            };
                            break;

                        case 2:
                            where_hash{i.key} = {
                                "op": i.value.op[0],
                                "arg": {
                                    "op": i.value.op[1],
                                    "arg": arg,
                                },
                            };
                            break;

                        default:
                            throw "WHERE-ARG-ERROR", sprintf("only a single operator nesting level is allowed; "
                                "got %d levels (%y)", i.value.op.lsize(), i.value.op);
                    }
                } else if (i.value.op) {
                    where_hash{i.key} = {
                        "op": i.value.op,
                        "arg": arg,
                    };
                }
            }
        }
        return where_hash;
    }

    hash<auto> doGetSetHash(*hash<auto> ah, *hash<auto> ctxt, *bool ui) {
        *hash<auto> set_hash = doGetHash(ah, "set", True);
        if (!set_hash) {
            throw "SET-ARG-ERROR", "missing set arg in update API call";
        }
        QDBG_LOG("set_hash before: %y", set_hash);
        set_hash = UserApi::expandTemplatedValue(set_hash, ctxt);
        QDBG_LOG("set_hash after: %y", set_hash);
        if (ui) {
            foreach hash<auto> i in (set_hash.pairIterator()) {
                set_hash{i.key} = i.value.type != "string" && i.value.value.typeCode() == NT_STRING
                    ? parse_yaml(i.value.value)
                    : i.value.value;
            }
            QDBG_LOG("set_hash after UI processing: %y", set_hash);
        }
        return set_hash;
    }

    list<hash<auto>> doGetRecords(*hash<auto> ah, *hash<auto> ctxt, *bool ui) {
        *list<auto> records = doGetListOfHashes(ah, "records", True);
        if (!records) {
            throw "RECORDS-ARG-ERROR", "missing records arg in update API call";
        }
        list<hash<auto>> rv;
        foreach auto record in (UserApi::expandTemplatedValue(records, ctxt)) {
            if (record.typeCode() != NT_HASH) {
                throw "RECORDS-ARG-ERROR", sprintf("entry %d/%d in the records list is type %y; expecting \"hash\"",
                    $#, records.lsize(), record.fullType());
            }
            if (ui) {
                foreach hash<auto> i in (record.pairIterator()) {
                    record{i.key} = i.value.type != "string" && i.value.value.typeCode() == NT_STRING
                        ? parse_yaml(i.value.value),
                        : i.value.value;
                }
            }
            rv += record;
        }
        return rv;
    }
}

/** @REST /latest (/v7)

    This URI path always provides access to the latest REST API; in this case it is identical to @ref rest_api_v7

    To ensure that a specific REST API version is used; use the URI path prefix with a specific API version in it
    instead.
*/
class LatestRestClass inherits V7RestClass {
    string name() {
        return "latest";
    }
}
