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

/** @page qorusapi Network System API

    @tableofcontents

    @section apiintro Introduction to the Qorus System APIs

    Qorus implements two network-available system APIs:
    - @subpage rest_api_page_latest "REST API": the latest version of the Qorus REST API
      - @ref restapi "REST API overview" (newer, all new API development happens here)
      - @subpage rest_api_page_v7 (version-specific, latest version as of this release;
        <a href="qorus-rest-api-v7.yaml">Swagger schema</a>)
      - @subpage rest_api_page_v6
      - @subpage rest_api_page_v5
      - @subpage rest_api_page_v4
      - @subpage rest_api_page_v3
      - @subpage rest_api_page_v2
      - @subpage rest_api_page_v1 (the original, base REST API)
      - @subpage rest_api_page_public (no authentication required;
        <a href="qorus-rest-api-public.yaml">Swagger schema</a>)
      - @subpage rest_api_data_structures
    - @subpage rpcapi (older, no new development)

    @section restapi Qorus REST API

    The Qorus <a href="http://en.wikipedia.org/wiki/Representational_state_transfer">REST</a> API has been
    implemented to use REST design principles for interfacing with Qorus Integration Engine.

    The Qorus REST API follows the following REST design principles:
    - \c GET requests never make changes (do not alter state)
    - \c PUT requests can change server state and are also <a href="http://en.wikipedia.org/wiki/Idempotence">idempotent</a>
    - \c POST requests create new objects or configuration
    - \c DELETE requests delete existing objects or configuration
    - arguments are accepted in the URI or in the message body, however for all but simple requests it's recommended to send arguments in the message body

    Qorus's REST API is designed to facilitate data exchanges between clients and the server.  Serialized data
    is supported with the following \c Content-Types (clients indicate support by including these in the
    \c Accept header):
    - \c text/x-yaml or \c application/x-yaml: @ref yamlintro "YAML"
    - \c application/json: @ref jsonintro "JSON"
    - \c text/xml: @ref xmlintro "XML-RPC" (for HTTP payload body encoding)
    - \c text/html: HTML (for responses only)

    The REST API is accessible from the Qorus HTTP server anchored at the path \c "/api"; the latest version of the REST API is
    accessible at \c "/api/latest"; see the following section for more information.

    There are two methods of calling the API. Both methods are identical. Examples:
    - <tt>PUT foo/bar?action=myAction</tt>
    - <tt>PUT foo/bar/myAction</tt>

    @note
    - If no \c Accept header is present, then it is assumed that the client accepts all
      media types; see <a href="http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html">http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html</a>
    - The @ref qrest "qrest" program provides the command-line interface to the Qorus REST API; note that
      @ref qrest "qrest" automatically adds the \c "/api/latest" URI path prefix to requests to Qorus.
    - All future Qorus API development will be made with the <a href="http://en.wikipedia.org/wiki/Representational_state_transfer">REST</a> API.

    @subsection http_rest_handler REST Client Time Zone Header

    The following header can be given by clients to specify the client's
    <a href="https://en.wikipedia.org/wiki/List_of_tz_database_time_zones">time zone region</a>:
    - \c Qorus-Client-Time-Zone

    For example:
    @verbatim
Qorus-Client-Time-Zone: America/New_York
    @endverbatim

    This allows the REST server to handle date/time values in the client's time zone.

    @section restapiversioning Qorus REST API Versioning

    The REST API is versioned in order to provide maximum backwards-compatibility to external applications and allow for maximum flexibility
    for future expansion.

    Each REST API version besides the base version (version 1) is accessible with a URI prefix with its version name as follows:
    - @ref rest_api_page_v4 "/api/v7": introduced in %Qorus 6
    - @ref rest_api_page_v4 "/api/v6": introduced in %Qorus 5.1
    - @ref rest_api_page_v4 "/api/v5": introduced in %Qorus 5
    - @ref rest_api_page_v4 "/api/v4": introduced in %Qorus 4.1
    - @ref rest_api_page_v3 "/api/v3": introduced in %Qorus 4.0
    - @ref rest_api_page_v2 "/api/v2": introduced in %Qorus 3.1.1
    - @ref rest_api_page_v1 "/api": (the original, base REST API)

    The following URI prefix can be used to ensure that the latest version of the REST API is used at all times:
    - @ref rest_api_page_latest "/api/latest": this currently points to @ref rest_api_page_v5 "/api/v5"
*/

/** @RESTEND

    @section rest_library_object_hash REST Library Object Hash

    Library object hashes have the following keys:
    - \c functions: a list of function objects (can be empty)
    - \c classes: a list of class objects (can be empty)
    - \c constants: a list of constant objects (can be empty)

    Library object hash values in the lists assigned to the keys listed above have the following keys:
    - \c name: the name of the object
    - \c version: the version of the object
    - \c id: the id of the object (corresponding to a \c function_instanceid, \c classid, or \c constantid)

    @par Example
    @verbatim
lib : hash: (3 members)
  functions : <EMPTY LIST>
  classes : <EMPTY LIST>
  constants : list: (1 element)
    [0]=hash: (3 members)
      name : "Errors"
      version : "1.0"
      id : 12
    @endverbatim

    @section rest_mapper_hash REST Mapper Hash

    @ref mappers "Mapper" hashes have the following keys:
    - \c mapperid: the ID of the mapper
    - \c name: the name of the mapper
    - \c version: the version of the mapper
    - \c type: the @ref mapper-types "type" of the mapper

    @par Example
    @verbatim
mappers : list: (1 element)
  [0]=hash: (4 members)
    mapperid : 119
    name : "it-32-inv_stock_adj-brep_trans-rrc-dhl-in"
    version : "1.0"
    type : "EbsSingleTableInboundMapper"
    @endverbatim

    @section rest_vmap_hash REST Value Map Hash

    @ref value-maps "Value map" hashes have the following keys:
    - \c id: the ID of the value map
    - \c name: the name of the value map
    - \c throws_exception: a boolean value indicating how requests for unknown values should be processed
    - \c valuetype: the data type of the value map
    - \c mapsize: the number of elements in the map

    @par Example
    @verbatim
vmaps : list: (1 element)
  [0]=hash: (5 members)
    id : 3
    name : "it-34-inv_direct_transfer-inventory-tat-smart"
    throws_exception : False
    valuetype : "string"
    mapsize : 2
    @endverbatim

    @section rest_option_hash REST Option Hash

    Options hashes have the following keys:
    - \c name: the name of the option
    - \c desc: a description for the option
    - \c value: the value of the option

    @par Example
    @verbatim
    options : list: (1 element)
      [0]=hash: (3 members)
        name : "verbose"
        desc : "sets verbose level"
        value : 11
    @endverbatim

    @section rest_alert_hash REST Alert Hash

    Alert hashes have the following keys:
    - \c type: the type of object directly affected by the alert
    - \c id: the ID of the object directly affected by the alert
    - \c alerttype: either \c "ONGOING" or \c "TRANSIENT"
    - \c when: the timestamp when the alert was first raised
    - \c local: a boolean flag; @ref True if the alert was raised by the local instance
    - \c alert: the name or string code of the alert
    - \c alertid: a unique identifier for the alert (unique within the instance that raised the alert)
    - \c reason: a string giving the reason the alert was raised
    - \c who: a string describing the user or entity that raised the alert
    - \c source: a string describing the source of the alert
    - \c object: a string describing the object the alert directly affects
    - \c instance: the instance key of the Qorus instance where the alert was raised
    - \c name: the name of the object directly affected by the alert
    - \c auditid: @ref nothing if alert auditing is not enabled, otherwise an integer giving the auditid of the alert event

    @par Example
    @verbatim
alerts : list: (1 element)
  [0]=hash: (14 members)
    type : "GROUP"
    id : 728
    alerttype : "ONGOING"
    when : 2016-05-22 13:57:03.196796 Sun +02:00 (CEST)
    local : True
    alert : "INTERFACE-GROUP-DISABLED"
    alertid : 3
    reason : "\"enabled\" flag for interface group \"SALESFORCE-EXAMPLE-1\" set to false in the DB at system startup"
    who : "Qorus"
    source : "system"
    object : "GROUP SALESFORCE-EXAMPLE-1 (728)"
    instance : "quark-1"
    name : "SALESFORCE-EXAMPLE-1"
    auditid : 4797709
    @endverbatim

    @section rest_conndep_hash REST Connection Dependency Hash

    @ref connmon "Connection" dependency hashes have the following keys:
    - \c type: the type of connection dependency:
      - \c "DATASOURCE": @ref dsconn
      - \c "QORUS": @ref remoteconn
      - \c "USER": @ref userconn
    - \c name: the name of the connection
    - \c up: a boolean flag describing the currently-monitored health of the connection

    @par Example
    @verbatim
connections : list: (1 element)
  [0]=hash: (3 members)
    type : "DATASOURCE"
    name : "staging-ora"
    up : True
    @endverbatim

    @section rest_interface_group_hash REST Interface Group Hash

    @ref rbacgroups "Interface group" hashes have the following keys:
    - \c name: the name of the group
    - \c enabled: the status of the group as a bool
    - \c size: the total number of members of the group

    @par Example
    @verbatim
groups : list: (2 elements)
  [0]=hash: (3 members)
    name : "IT"
    enabled : True
    size : 432
  [1]=hash: (3 members)
    name : "IT-84-EXPORT_ITEM_CROSS_REFERENCE-OUT"
    enabled : True
    size : 1
    @endverbatim

    @section rest_execution_instance_hash REST Execution Instance Hash

    Execution instance hashes have the following keys:
    - \c mode: the workflow execution instance execution mode
    - \c status: always \c "n/a"; removed in Qorus 4.0/REST API v3
    - \c iterations: always \c 0; removed in Qorus 4.0/REST API v3
    - \c totalSegments: number of segments in the workflow
    - \c starttime: the date/time the execution instance was started
    - \c logfile: the log file name (full path)
    - \c sync: a boolean flag if the execution instance is synchronous or not
    - \c executionID: the workflow execution instance ID
    - \c errors: always \c 0; removed in Qorus 4.0/REST API v3
    - \c warnings: always \c 0; removed in Qorus 4.0/REST API v3

    @par Example
    @verbatim
    name : "IT-32-INV_STOCK_ADJ-ROAMERS-SG-IN"
    version : "1.0"
    mode : "NORMAL"
    status : "n/a"
    iterations : 0
    totalSegments : 1
    starttime : 2016-05-22 13:58:45.335128 Sun +02:00 (CEST)
    logfile : "/Users/david/src/Qorus/test/log/OMQ-quark-1-IT-32-INV_STOCK_ADJ-ROAMERS-SG-IN.log"
    options : <EMPTY HASH>
    sync : False
    executionID : 209
    workflowid : 607
    errors : 0
    warnings : 0
    @endverbatim

    @section rest_execution_instance_hash_v3 REST Execution Instance Hash v3

    Execution instance hashes in the REST v3 API are the same as in the v1 and v2 APIs except that the V3 hash adds the \c "remote" and \c "process" keys; these hashes have the following keys:
    - \c mode: the workflow execution instance execution mode
    - \c status: the current status
    - \c totalSegments: number of segments in the workflow
    - \c starttime: the date/time the execution instance was started
    - \c logfile: the log file name (full path)
    - \c sync: a boolean flag if the execution instance is synchronous or not
    - \c executionID: the workflow execution instance ID
    - \c remote: if @ref True "True", the workflow execution instance is running in a remote @ref qwf "qwf" process, otherwise it is running internally in the @ref qorus-core "qorus-core" process
    - \c process: present when \c remote is @ref True "True"; this is a @ref rest_process_exec_info_hash

    @par Example
    @verbatim
    name : "IT-32-INV_STOCK_ADJ-ROAMERS-SG-IN"
    version : "1.0"
    mode : "NORMAL"
    totalSegments : 1
    starttime : 2016-05-22 13:58:45.335128 Sun +02:00 (CEST)
    logfile : "/Users/david/src/Qorus/test/log/OMQ-quark-1-IT-32-INV_STOCK_ADJ-ROAMERS-SG-IN.log"
    options : <EMPTY HASH>
    sync : False
    executionID : 209
    workflowid : 607
    @endverbatim

    @section rest_audit_info_hash REST Audit Info Hash

    Audit info hashes have the following keys:
    - \c audit_event_code: the audit event code (see @ref AuditEventCodes for possible values)
    - \c reason: the reason for the event (ex: if due to an API call, then the API name, ex \c "REST PUT api/jobs/myjob?action=run", if due to normal system processing, then the string \c "internal call")
    - \c who: always \c "Qorus"
    - \c source: the source of the call that led to the event (ex: \c "source: ipv6[::1]:50653 listener: ipv6[::]:8001") or \c "system" if due to normal system processing
    - \c info1: first informational string for the event
    - \c info2: second informational string for the event
    - \c created: the date/time the event was created
    - \c event: the event string corresponding to the \c audit_event_code

    @par Example
    @verbatim
    audit_event_code : 6
    reason : "internal call"
    who : "Qorus"
    source : "system"
    info1 : "I"
    info2 : "C"
    created : 2014-06-18 12:49:58.329436 Wed +02:00 (CEST)
    event : "WORKFLOW-STATUS-CHANGE"
    @endverbatim

    @section rest_order_note_hash REST Order Note Hash

    Order note hashes have the following keys:
    - \c saved: a boolean indicating if the note has already been flushed to the DB or not
    - \c username: the user who created the note
    - \c note: the note itself
    - \c created: the date/time the note was created
    - \c modified: the date/time the note was modified

    @section rest_workflow_description_hash REST Workflow Description Hash

    Workflow description hashes have the following keys:
    - \c workflowid: the workflow ID
    - \c name: the workflow name
    - \c version: the workflow version
    - \c description: the workflow description
    - \c author: the workflow author
    - \c created: the workflow creation date
    - \c modified: the workflow last modified date
    - \c autostart: the @ref wf_autostart "workflow autostart" value
    - \c manual_autostart: a boolean flag set if the \c autostart value has been changed manually, in which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
    - \c enabled: a boolean flag indicating if the workflow is enabled or not; disabled workflows cannot be started
    - \c deprecated: a boolean flag indicating if the workflow is deprecated or not; deprecated workflows are not displayed by default in the UI
    - \c keylist: a list of @ref wf_keylist "workflow order keys"
    - \c stepmap: a hash where keys are step IDs and values are step names
    - \c steps: a hash of step dependencies, where keys are step IDs and values are lists of step IDs that must preceed the step ID given as a key
    - \c segment: a list of segment description hashes, where each segment hash has the following keys:
      - \c steplist: a list of step IDs in the segment
      - \c steps: a hash of step dependencies, where keys are step IDs and values are lists of step IDs that must preceed the step ID given as a key
      - [\c start]: the starting step ID for segments other than the initial segment
      - [\c subworkflow]: set to @ref True if the segment is a subworkflow segment
      - [\c linksegment]: the previous segment
      - [\c linkstepid]: the step linking the segment to the previous segment
    - \c lib: a @ref rest_library_object_hash
    - \c mappers: a list of @ref mappers "mappers" associated with the workflow (can be @ref nothing); each mapper element is a @ref rest_mapper_hash
    - \c vmaps: a list of @ref value-maps "value maps" associated with the workflow (can be @ref nothing); each value map element is a @ref rest_vmap_hash
    - \c stepinfo: a list of hashes giving information about @ref steps "workflow steps"; each hash is a @ref rest_step_hash with the following additional keys:
      - \c sfname: the name of the primary step function
      - \c name: the name of the function
      - \c version: the version of the function
      - \c function_instanceid: the function ID
      - \c function_type: the @ref StepFunctionTypes "type" of the function
      - \c description: a decsription for the function
      - \c author: the author of the function
      - \c created: the creation date in the database
      - \c modified: the last modified date in the database
      - \c source: the name of the source file for the function (complete path)
      - \c line: the line number offset for the function object definition in the file
    - \c options: a list of @ref rest_option_hash "option hashes"
    - \c exec: a list of @ref rest_execution_instance_hash "execution instance hashes" describing any workflow execution instances running for this workflow
    - \c exec_count: the number of elements in the \c exec list
    - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be empty)
    - \c connections: a list of connection objects that this workflow depends on; each list element is a @ref rest_conndep_hash (may be empty)
    - \c groups: a list of @ref rbacgroups "interface groups" that the workflow belongs to; each list element is a @ref rest_interface_group_hash (may be empty)

    @section rest_workflow_description_hash_v3 REST Workflow Description Hash v3

    Workflow description hashes in the REST v3 API are the same as in the v1 and v2 APIs except that the V3 hash adds the \c "sla_threshold", \c "manual_sla_threshold", \c "remote", \c "process", and \c "order_stats" keys; these hashes have the following keys:
    - \c workflowid: the workflow ID
    - \c name: the workflow name
    - \c version: the workflow version
    - \c description: the workflow description
    - \c author: the workflow author
    - \c remote: if @ref True "True", the workflow will run as a remote @ref qwf "qwf" process, otherwise it runs internally in the @ref qorus-core "qorus-core" process
    - \c process: present when \c remote is @ref True "True"; this is a @ref rest_process_exec_info_hash
    - \c created: the workflow creation date
    - \c modified: the workflow last modified date
    - \c autostart: the @ref wf_autostart "workflow autostart" value
    - \c manual_autostart: a boolean flag set if the \c autostart value has been changed manually, in which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
    - \c sla_threshold: the @ref wf_sla_threshold "workflow SLA threshold" value
    - \c manual_sla_threshold: a boolean flag set if the \c sla_threshold value has been changed manually, in which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
    - \c enabled: a boolean flag indicating if the workflow is enabled or not; disabled workflows cannot be started
    - \c deprecated: a boolean flag indicating if the workflow is deprecated or not; deprecated workflows are not displayed by default in the UI
    - \c keylist: a list of @ref wf_keylist "workflow order keys"
    - \c stepmap: a hash where keys are step IDs and values are step names
    - \c steps: a hash of step dependencies, where keys are step IDs and values are lists of step IDs that must preceed the step ID given as a key
    - \c segment: a list of segment description hashes, where each segment hash has the following keys:
      - \c steplist: a list of step IDs in the segment
      - \c steps: a hash of step dependencies, where keys are step IDs and values are lists of step IDs that must preceed the step ID given as a key
      - [\c start]: the starting step ID for segments other than the initial segment
      - [\c subworkflow]: set to @ref True if the segment is a subworkflow segment
      - [\c linksegment]: the previous segment
      - [\c linkstepid]: the step linking the segment to the previous segment
    - \c lib: a @ref rest_library_object_hash
    - \c mappers: a list of @ref mappers "mappers" associated with the workflow (can be @ref nothing); each mapper element is a @ref rest_mapper_hash
    - \c vmaps: a list of @ref value-maps "value maps" associated with the workflow (can be @ref nothing); each value map element is a @ref rest_vmap_hash
    - \c stepinfo: a list of hashes giving information about @ref steps "workflow steps"; each hash is a @ref rest_step_hash with the following additional keys:
      - \c sfname: the name of the primary step function
      - \c name: the name of the function
      - \c version: the version of the function
      - \c function_instanceid: the function ID
      - \c function_type: the @ref StepFunctionTypes "type" of the function
      - \c description: a decsription for the function
      - \c author: the author of the function
      - \c created: the creation date in the database
      - \c modified: the last modified date in the database
      - \c source: the name of the source file for the function (complete path)
      - \c line: the line number offset for the function object definition in the file
    - \c options: a list of @ref rest_option_hash "option hashes"
    - \c exec: a list of @ref rest_execution_instance_hash_v3 "execution instance hashes" describing any workflow execution instances running for this workflow
    - \c exec_count: the number of elements in the \c exec list
    - \c order_stats: a list of workflow order processing statistics; list values are @ref OMQ::OrderSummaryOutputInfo "OrderSummaryOutputInfo" hashes for the given workflow
    - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be empty)
    - \c connections: a list of connection objects that this workflow depends on; each list element is a @ref rest_conndep_hash (may be empty)
    - \c groups: a list of @ref rbacgroups "interface groups" that the workflow belongs to; each list element is a @ref rest_interface_group_hash (may be empty)

    @section rest_service_method_hash REST Service Method Hash

    Order note hashes have the following keys:
    - \c service_methodid: the service method ID
    - \c name: the name of the method
    - \c description: the description of the method (if any)
    - \c author: the author of the method (if any)
    - \c locktype: the type of locking performed with method calls; see @ref MethodLockAttributes for possible values
    - \c internal: a boolean flag indicating if the method is restricted to internal calls only (if @ref True then the method cannot be called externally)
    - \c write: a boolean flag indicating if the method is a "write" method
    - \c created: the date/time the method was created
    - \c modified: the date/time the method was modified
    - \c tags: any user-defined tags on the method
    - \c source: the service source file that the method was created from
    - \c offset: the offset in the service file for the source of the method
    - \c host: the hostname of the machine where the method was loaded from
    - \c user: the OS user who loaded the service

    @par Example
    @verbatim
hash: (14 members)
  service_methodid : 301033
  name : "init"
  description : "service init method"
  author : "Qore Technologies, sro"
  locktype : "none"
  internal : False
  write : False
  created : 2016-05-20 18:32:57.177490 Fri +02:00 (CEST)
  modified : 2016-05-20 18:32:57.177490 Fri +02:00 (CEST)
  tags : <EMPTY HASH>
  source : "/Users/david/src/Qorus/git/qorus/system/prop-v3.1.qsd"
  offset : "45"
  host : "quasar.prague"
  user : "david"
    @endverbatim

    @section rest_service_method_hash_v2 REST Service Method Hash v2

    Service method hashes in the REST v2 API are the same as in the V1 API except that the V2 hash adds the \c "sla" key; these hashes have the following keys:
    - \c service_methodid: the service method ID
    - \c name: the name of the method
    - \c description: the description of the method (if any)
    - \c author: the author of the method (if any)
    - \c locktype: the type of locking performed with method calls; see @ref MethodLockAttributes for possible values
    - \c internal: a boolean flag indicating if the method is restricted to internal calls only (if @ref True then the method cannot be called externally)
    - \c write: a boolean flag indicating if the method is a "write" method
    - \c created: the date/time the method was created
    - \c modified: the date/time the method was modified
    - \c tags: any user-defined tags on the method
    - \c source: the service source file that the method was created from
    - \c offset: the offset in the service file for the source of the method
    - \c host: the hostname of the machine where the method was loaded from
    - \c user: the OS user who loaded the service
    - \c sla: the SLA associated with the service method (if any)

    @par Example
    @verbatim
hash: (14 members)
  service_methodid : 301033
  name : "init"
  description : "service init method"
  author : "Qore Technologies, sro"
  locktype : "none"
  internal : False
  write : False
  created : 2016-05-20 18:32:57.177490 Fri +02:00 (CEST)
  modified : 2016-05-20 18:32:57.177490 Fri +02:00 (CEST)
  tags : <EMPTY HASH>
  source : "/Users/david/src/Qorus/git/qorus/system/prop-v3.1.qsd"
  offset : "45"
  host : "quasar.prague"
  user : "david"
    @endverbatim

    @section rest_service_resource_hash REST Service Resource Hash

    Service resource hashes are keyed by the resource name; each value is a hash with the following keys:
    - \c type: the type of service resource
    - \c desc: a description of the resource
    - \c info: a hash of information about the resource; the format and content of this hash depends on the resource type

    @par Example
    @verbatim
resources : hash: (2 members)
  ui-extension-user-sql-data-view-1-1 : hash: (3 members)
    type : "UiExtension"
    desc : "Allows database and table browsing"
    info : hash: (4 members)
      url : "http://localhost:8001/UIExtension/user-sql-data-view-1"
      group : "SQL"
      menuname : "SQL Data View"
      desc : "Allows database and table browsing"
  http-global-2 : hash: (3 members)
    type : "HttpGlobalHandler"
    desc : "handling URL: \"db\""
    info : hash: (2 members)
      content : <NOTHING>
      headers : <NOTHING>
    @endverbatim

    @section rest_step_hash REST Step Hash

    Step hashes have the following keys:
    - \c stepid: the ID of the step
    - \c typedesc: a string describing the step type (ex: "NORMAL ARRAY")
    - \c steptype: the @ref StepTypes "type" of the step
    - \c arraytype: the @ref StepArrayTypes "array type" of the step
    - \c name: the name of the step
    - \c version: the version of the step
    - \c author: the author of the step (if any)
    - \c desc: the description of the step or the description of the step's primary step function if the step itself
      has no description
    - [\c queueid]: the ID of the @ref queue_objects "async event queue" for @ref asyncsteps "asynchronous steps" (if any)
    - [\c queuename]: the name of the @ref queue_objects "async event queue" for @ref asyncsteps "asynchronous steps" (if any)
    - [\c workflow_event_typeid]: the ID of the @ref wf_sync_event_objects "workflow synchronization event type" for
      @ref eventsteps "workflow synchronization event steps" (if any)
    - \c user_interaction: \c True if the @ref asyncsteps "asynchronous step" supports user interaction APIs, \c False
      in all other cases
    - \c created: the creation date of the step in the database
    - \c modified: the last modified date of the step in the database

    @par Example
    @verbatim
hash: (11 members)
  stepid : 509
  typedesc : "NORMAL"
  steptype : "NORMAL"
  arraytype : "NONE"
  name : "it_100_delivery_confirmation_update_oracle"
  version : "1.0"
  author : "Qore Technologies, s.r.o."
  stepfunction_instanceid : 508
  validationfunction_instanceid : 122
  created : 2016-02-05 13:38:26.000000 Fri +01:00 (CET)
  modified : 2016-02-05 14:00:51.000000 Fri +01:00 (CET)
    @endverbatim

    @section rest_step_hash_v3 REST Step Hash V3

    Step hashes in the V3 REST API have the following keys:
    - \c stepid: the ID of the step
    - \c typedesc: a string describing the step type (ex: "NORMAL ARRAY")
    - \c steptype: the @ref StepTypes "type" of the step
    - \c arraytype: the @ref StepArrayTypes "array type" of the step
    - \c name: the name of the step
    - \c version: the version of the step
    - \c author: the author of the step (if any)
    - \c desc: the description of the step or the description of the step's primary step function if the step itself has no description
    - \c config: a hash of config items keyed by config item name with values as hashes with the following keys:
      - \c type: the type of the config item
      - \c desc: the description of the config item
      - \c default_value: the default value of the config item
    - [\c queueid]: the ID of the @ref queue_objects "async event queue" for @ref asyncsteps "asynchronous steps" (if any)
    - [\c queuename]: the name of the @ref queue_objects "async event queue" for @ref asyncsteps "asynchronous steps" (if any)
    - [\c workflow_event_typeid]: the ID of the @ref wf_sync_event_objects "workflow synchronization event type" for @ref eventsteps "workflow synchronization event steps" (if any)
    - \c created: the creation date of the step in the database
    - \c modified: the last modified date of the step in the database

    @par Example
    @verbatim
hash: (11 members)
  stepid : 509
  typedesc : "NORMAL"
  steptype : "NORMAL"
  arraytype : "NONE"
  name : "it_100_delivery_confirmation_update_oracle"
  version : "1.0"
  author : "Qore Technologies, s.r.o."
  stepfunction_instanceid : 508
  validationfunction_instanceid : 122
  created : 2016-02-05 13:38:26.000000 Fri +01:00 (CET)
  modified : 2016-02-05 14:00:51.000000 Fri +01:00 (CET)
    @endverbatim

    @section rest_function_hash REST Function Hash

    Function hashes have the following keys:
    - \c name: the name of the function
    - \c version: the version of the function
    - \c function_instanceid: the function ID
    - \c function_type: the type of function object; see @ref StepFunctionTypes for possible values
    - \c description: the description of the function
    - \c author: the author of the function
    - \c body: the source code for the function
    - \c created: the date/time the function was created
    - \c modified: the date/time the function was modified
    - \c createdby: (deprecated) always \c "omq"
    - \c modifiedby: (deprecated) always \c "omq"
    - \c tags: any user-defined tags on the function object
    - \c source: the source file that the function object was created from
    - \c offset: the offset in the source file for the source of the function object
    - \c host: the hostname of the machine where the function was loaded from
    - \c user: the OS user who loaded the function source

    @par Example
    @verbatim
hash: (16 members)
  name : "it_00_dhl_dispatcher_create_wf"
  version : "1.0"
  function_instanceid : 183
  function_type : "STEP"
  description : "binds the subworkflow"
  author : "Josephine Programmer"
  body : "
%new-style
%require-types
%enable-all-warnings

sub it_00_dhl_dispatcher_create_wf(string workflow) {
    hash<auto> sd = wf_get_static_data();

    hash<auto> ord = (
        \"staticdata\": sd,
        \"orderkeys\": wf_get_order_keys(),
    );

    log(LoggerLevel::INFO, \"binding subworkflow %s\", workflow);
    wf_bind_subworkflow((\"name\" : workflow), ord);
}
"
  created : 2015-12-10 10:35:04.000000 Thu +01:00 (CET)
  modified : 2016-02-08 14:51:03.000000 Mon +01:00 (CET)
  createdby : "omq"
  modifiedby : "omq"
  tags : <EMPTY HASH>
  source : "/export/home/dnichols/src/drei/sepl-it/src/00-DHL/isepl/it-00-dhl_dispatcher_create_wf-v1.0.qfd"
  offset : "123"
  host : "manatee.prague.qoretechnologies.com"
  user : "dnichols"
    @endverbatim

    @section rest_job_result_hash REST Job Result Hash

    Job result (job instance) hashes have the following keys:
    - \c name: the name of the job
    - \c version: the version of the job
    - \c job_instanceid: the job_instanceid (unique ID for the job result)
    - \c jobid: the job ID
    - \c jobstatus: the status of executing the job; see @ref JobStatusDescriptions for possible values
    - \c info: a hash of information set by the job code during execution
    - \c sessionid: the @ref appsessionmodel "application session ID" that is currently processing the job instance (0 for no session)
    - \c started: the date/time the job instance was started
    - \c completed: the date/time the job instance completed
    - \c modified: the date/time the job was last modified

    @section rest_job_description_hash REST Job Description Hash

    Job description hashes have the following keys:
    - \c name: the name of the job
    - \c jobid: the job ID
    - \c description: the description of the job (if any)
    - \c version: the version of the job
    - \c author: the author of the job (if any)
    - \c sessionid: If the job is currently active and running on a Qorus instance, then this attribute will have a
     value, otherwise it will not be set
    - \c run_skipped: A boolean value telling the system if the job should be run immediately if the last scheduled run was missed due to system downtime
    - \c enabled: a boolean flag indicating if the job is enabled or not; disabled jobs cannot be activated
    - \c month: the month value in a @ref job_schedule "job cron schedule"
    - \c day: the day value in a @ref job_schedule "job cron schedule"
    - \c wday: the weekday value in a @ref job_schedule "job cron schedule"
    - \c hour: the hout value in a @ref job_schedule "job cron schedule"
    - \c minute: the minute value in a @ref job_schedule "job cron schedule"
    - \c manually_updated: a boolean flag set if the job schedule has been changed manually, in which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
    - \c created: the date/time the job was created
    - \c modified: the date/time the job was modified
    - \c source: the complete path of the job source file when loaded
    - \c line: the line offset of the job source code in the file
    - \c mappers: list of @ref mappers "mappers" associated with the job (can be @ref nothing); each mapper element is a @ref rest_mapper_hash
    - \c vmaps:  list of @ref value-maps "value maps" associated with the job (can be @ref nothing); each value map element is a @ref rest_vmap_hash
    - \c lib: a @ref rest_library_object_hash
    - \c tags: any user-defined tags on the job
    - \c db_active: a boolean flag indicating the active status in the database
    - \c active: the active status in the current Qorus instance
    - \c options: a hash of options set on the job (if any)
    - \c offset: the line offset of the job source code in the file
    - \c host: the hostname of the machine where the job was loaded from
    - \c user: the OS user who loaded the job
    - \c sched_type: the schedule type; one of:
      - \c "cron": uses a @ref job_schedule "job cron schedule"
      - \c "recurring": uses a fixed erpeat delay
    - \c sched_txt: a string describing the schedule (ex: \c "minutes: 0, hours: 0, days: *, months: *, wdays: *")
    - \c connections: a list of connection objects that this job depends on; each list element is a @ref rest_conndep_hash (may be empty)
    - \c alerts: a list of alerts raised against the job; each list element is a @ref rest_alert_hash (may be empty)

    @section rest_job_description_hash_v2 REST Job Description Hash v2

    Job description hashes in the REST v2 API are the same as in the V1 API except that the V2 hash adds the \c "sla" key; these hashes have the following keys:
    - \c name: the name of the job
    - \c jobid: the job ID
    - \c description: the description of the job (if any)
    - \c version: the version of the job
    - \c author: the author of the job (if any)
    - \c sessionid: If the job is currently active and running on a Qorus instance, then this attribute will have a
      value, otherwise it will not be set
    - \c run_skipped: A boolean value telling the system if the job should be run immediately if the last scheduled run was missed due to system downtime
    - \c enabled: a boolean flag indicating if the job is enabled or not; disabled jobs cannot be activated
    - \c month: the month value in a @ref job_schedule "job cron schedule"
    - \c day: the day value in a @ref job_schedule "job cron schedule"
    - \c wday: the weekday value in a @ref job_schedule "job cron schedule"
    - \c hour: the hout value in a @ref job_schedule "job cron schedule"
    - \c minute: the minute value in a @ref job_schedule "job cron schedule"
    - \c manually_updated: a boolean flag set if the job schedule has been changed manually, in which case the manual setting takes precendence over any new definitions loaded with @ref oload "oload"
    - \c created: the date/time the job was created
    - \c modified: the date/time the job was modified
    - \c source: the complete path of the job source file when loaded
    - \c line: the line offset of the job source code in the file
    - \c mappers: list of @ref mappers "mappers" associated with the job (can be @ref nothing); each mapper element is a @ref rest_mapper_hash
    - \c vmaps:  list of @ref value-maps "value maps" associated with the job (can be @ref nothing); each value map element is a @ref rest_vmap_hash
    - \c lib: a @ref rest_library_object_hash
    - \c tags: any user-defined tags on the job
    - \c db_active: a boolean flag indicating the active status in the database
    - \c active: the active status in the current Qorus instance
    - \c options: a hash of options set on the job (if any)
    - \c offset: the line offset of the job source code in the file
    - \c host: the hostname of the machine where the job was loaded from
    - \c user: the OS user who loaded the job
    - \c sched_type: the schedule type; one of:
      - \c "cron": uses a @ref job_schedule "job cron schedule"
      - \c "recurring": uses a fixed erpeat delay
    - \c sched_txt: a string describing the schedule (ex: \c "minutes: 0, hours: 0, days: *, months: *, wdays: *")
    - \c connections: a list of connection objects that this job depends on; each list element is a @ref rest_conndep_hash (may be empty)
    - \c alerts: a list of alerts raised against the job; each list element is a @ref rest_alert_hash (may be empty)
    - \c sla: the name of the attached SLA (if any, if no SLA is associated, this key is not returned)

    @section rest_system_option_hash REST System Option Hash

    System option hashes have the following keys:
    - \c name: the name of the option; see @ref systemoptions for a list of possible options
    - \c value: the value of the option
    - \c expects: the value type of the option
    - \c desc: the description of the option
    - \c default: the default value of the option
    - \c startup-only: @ref True if the option can only be set during system startup
    - \c status: \c "locked" if \c startup-only is @ref True, \c "unlocked" if not
    - \c workflow: @ref True if the option can be overridden at the workflow level, @ref False if not
    - \c service: @ref True if the option can be overridden at the service level, @ref False if not
    - \c job: @ref True if the option can be overridden at the job level, @ref False if not
    - [\c interval]: the range of valid values for the option (inclusive)

    @par Example
    @verbatim
hash: (11 members)
  name : "verbose"
  value : 11
  expects : "integer"
  desc : "sets verbose level"
  default : 2
  startup-only : <NOTHING>
  status : "unlocked"
  workflow : True
  service : True
  job : True
  interval : list: (2 elements)
    [0]=1
    [1]=6
    @endverbatim

    @section rest_system_ui_extension_hash REST System UI Extension Hash

    REST system UI extension hashes have the following keys:
    - \c name: The name of the extension
    - \c group: a user-defined extension group name
    - \c type: the type of service serving the extension
    - \c service: the name of the service serving the extension
    - \c menuname: the menu string to use for the extension
    - \c desc: a short descriptive string for the extension
    - \c url: the full URL to the extension
    - \c url_name: a label for the URL of the extension

    @section rest_permission_hash REST Permission Hash

    Rest permissions hashes have the following keys:
    - \c permission_type: the type of permission; one of:
      - \c "SYSTEM": for system permissions
      - \c "USER": for user permissions
    - \c desc: a description for the permission
    - \c name: the name of the permission (permission code; ex: \c "RELOAD-DATASOURCE")

    @section rest_listener_hash REST Listener Hash

    Listener hashes have the following keys:
    - \c name: the unique name of the listener
    - \c hostname: the bind hostname
    - \c hostname_desc: a description for the hostname
    - \c address: the bind address
    - \c address_desc: a description for the address
    - [\c port]: the port number (not present in UNIX sockets)
    - \c family: the @ref network_address_family_constants "network address family code" for the socket
    - \c familystr: a descriptive string for the \c family code
    - \c ssl: @ref True if the listener is a TLS/SSL listener
    - \c desc: a descriptive string for the listener
    - \c proto: the protocol; either \c "http" or \c "https"
    - \c id: the listener ID
    - \c bind: the bind string

    @section rest_group_detail_hash REST Interface Group Detail Hash

    @ref rbacgroups "Interface group" hashes have the following keys:
    - \c name: the name of the group
    - \c description: group description
    - \c id: the ID for the group; synthetic groups have negative IDs
    - \c enabled: a boolean flag indicating if the group is enabled or not
    - \c size: the number of workflow, service, job, mapper, and value map members of the group
    - \c is_default : False
    - \c services: a list of hashes of services belonging to the group (can be @ref nothing); each element has the following keys:
      - \c type: the type of the service; one of:
        - \c "system": for system services
        - \c "user": for user services
      - \c serviceid: the service ID
      - \c name: the name of the service
      - \c version: the version of the service
      - \c autostart: a boolean value indicating if the service should be autostarted or not
    - \c workflows: a list of hashes of workflows belonging to the group (can be @ref nothing); each element has the following keys:
      - \c workflowid: the workflow ID
      - \c name: the name of the workflow
      - \c version: the version of the workflow
    - \c jobs: a list of hashes of jobs belonging to the group (can be @ref nothing); each element has the following keys:
      - \c jobid: the job ID
      - \c name: the name of the job
      - \c version: the version of the job
    - \c mappers: a list of @ref mappers "mappers" belonging to the group (can be @ref nothing); each mapper element is a @ref rest_mapper_hash
    - \c vmaps: a list of @ref value-maps "value maps" belonging to the group (can be @ref nothing); each value map element is a @ref rest_vmap_hash
    - \c synthetic: @ref True if the group is a synthetic group (in which case the \c id will be negative)

    @section rest_user_hash REST User Hash

    user hashes have the following keys:
    - \c provider: the name of the @ref RBAC "RBAC" provider (see also @ref rbac-external)
    - \c username: the unique username of the user
    - \c name: the descriptive name of the user
    - \c has_default: always @ref True in the Community Edition

    @par Example
    @verbatim
hash: (13 members)
  provider : "db"
  username : "admin"
  name : "Administrator"
  has_default : True
    @endverbatim

    @section rest_debug_callstack_hash REST Debug Callstack Hash

    Callstack hashes have the following keys:
    - \c function: the function or method name in the stack
    - \c line: the starting line number
    - \c endline: the ending line number
    - \c file: the source label or file name
    - \c source: the full source path (if known)
    - \c offset: the offset of the source object within \c source (if known)
    - \c typecode: see @ref call_type_constants for possible values
    - \c type: a string corresponding to \c typecode

    @section rest_connection_dependency_hash REST Connection Dependency Hash

    Connection dependency hashes have the following keys:
    - \c type: the interface type; one of \c "WORKFLOW", \c "SERVICE", or \c "JOB"
    - [\c workflowid]: the workflow ID
    - [\c serviceid]: the service ID
    - [\c jobid]: the job ID
    - [\c servicetype]: the service type (only present for services); one of \c "user" or \c "system"
    - \c name: the interface name
    - \c version: the interface version
    - \c desc: a description of the interface (ex: \c "job it-94-ar_payments-piteco-out v1.0 (23)")

    @section rest_user_remote_connection_hash REST User and Remote Connection Hash

    @ref userconn "User connection" and @ref remoteconn "remote connection" hashes have the following keys:
    - \c name: the name of the connection
    - \c conntype: either \c "REMOTE" or \c "USER-CONNETION"
    - \c desc: a description of the connection
    - \c url: the URL to the remote host
    - \c monitor: a boolean indicating if the connection is monitored or not
    - \c last_check: the date/time value the connection was last checked (loopback @ref remoteconn "remote connections" are not checked)
    - \c updated: the date/time the connection was last updated
    - \c status: one of the following:
      - \c "OK": the connection is OK
      - \c "not checked": not yet checked
      - any other string is an error message that occurred in the last check
    - \c up: a boolean indicating if the connection was monitored to be up or not
    - [\c loopback]: (only for @ref remoteconn "remote connections") a boolean indicating if the connection is a loopback connection
    - \c type: the connection type
    - \c url_hash: a hash of broken-down URL components as returned by @ref Qore::parse_url()
    - \c opts: a hash of options for the connection
    - \c deps: a list of @ref rest_connection_dependency_hash elements for dependent interfaces
    - \c alerts: a list of alerts raised against the connection; each list element is a @ref rest_alert_hash (may be empty)
    - [\c remote]: (only for @ref remoteconn "remote connections" when \c loopback = @ref False) a hash with the keys
      \c instance-key, \c health, \c alert-summary and \c omq-version

    @section rest_datasource_connection_hash REST Datasource Connection Hash

    @ref dsconn "datasource connection" hashes have the following keys:
    - \c name: the name of the @ref dsconn "datasource"
    - \c conntype: \c "DATASOURCE"
    - \c desc: a technical description of the connection without the password (ex: \c "freetds:test@mssql")
    - \c monitor: a boolean indicating if the connection is monitored or not
    - \c last_check: the date/time value the connection was last checked (loopback @ref remoteconn "remote connections" are not checked)
    - \c updated: the date/time the connection was last updated
    - \c status: one of the following:
      - \c "OK": the connection is OK
      - \c "not checked": not yet checked
      - any other string is an error message that occurred in the last check
    - \c up: a boolean indicating if the connection was monitored to be up or not
    - \c type: the database driver for the connection
    - \c user: the database username for the connection
    - \c db: the database name for the connection
    - \c shared-pool: a string describing the shared @ref Qore::SQL::DatasourcePool "DatasourcePool" status
    - \c warning-timeout: the period in milliseconds after which a warning is raised as a transient alert if a connection cannot be allocated from the @ref Qore::SQL::DatasourcePool "DatasourcePool" status
    - \c error-timeout: the period in milliseconds after which an exception is thrown if a connection cannot be allocated from the @ref Qore::SQL::DatasourcePool "DatasourcePool" status
    - \c pool-wait-max: maximum connection wait time in milliseconds for connections on the pool (0 means no contention)
    - \c pool-reqs: the number of requests for connections from the pool (= \c pool-hits + \c pool-miss)
    - \c pool-hits: the number of connection requests that were immediately satisified with no waiting (= \c pool-reqs - \c pool-miss)
    - \c pool-miss: the number of connection requests that blocked due to contention in the pool (= \c pool-reqs - \c pool-hits)
    - \c pool-hit-pct: the percentage of connection requests that were satisified immediately over all requests (100 means no contention)
    - \c alerts: a list of alerts raised against the connection; each list element is a @ref rest_alert_hash (may be empty)
    - \c deps: a list of @ref rest_connection_dependency_hash elements for dependent interfaces

    @section rest_workflow_error_description_hash_v1 REST Workflow Error Description Hash (REST API v1 and v2)

    @ref globalandworkflowerrors "Workflow error" hashes have the following keys (REST API v1 and v2):
    - \c error: the error code (ex: \c "SOCKET-SSL-ERROR")
    - \c description: a description for the error
    - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
    - \c retry_flag: a boolean value indicating if the error should cause the workflow order to get a retry or not
    - \c business_flag: a boolean flag indicating of the error is a business error
    - \c retry_delay_secs: if \c retry_flag is @ref True, the number of seconds that the order should wait before retrying
    - \c manually_updated: a boolean flag set if the error has been changed manually (if @ref True then subsequent loads with @ref oload will not overwrite the configuration in the DB)
    - \c type: either \c "global" or \c "workflow" giving the error definition scope
    - [\c workflowname]: (only if \c type = \c "workflow") the name of the workflow where the workflow-specific error is defined
    - [\c workflowversion]: (only if \c type = \c "workflow") the version of the workflow where the workflow-specific error is defined
    - [\c workflowid]: (only if \c type = \c "workflow") the ID of the workflow where the workflow-specific error is defined

    @see rest_workflow_error_description_hash_v3

    @section rest_workflow_error_description_hash_v3 REST Workflow Error Description Hash

    @ref globalandworkflowerrors "Workflow error" hashes have the following keys (REST API v3+):
    - \c business_flag: a boolean flag indicating of the error is a business error
    - \c description: a description for the error
    - \c error: the error code (ex: \c "SOCKET-SSL-ERROR")
    - \c manually_updated: a boolean flag set if the error has been changed manually (if @ref True then subsequent loads with @ref oload will not overwrite the configuration in the DB)
    - \c retry_delay_secs: if \c status is @ref OMQ::StatRetry "RETRY", the number of seconds that the order should wait before retrying
    - \c retry_flag: a boolean value indicating if the error should cause the workflow order to get a retry or not
    - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
    - \c status: the status the order enters when this error appears (@ref OMQ::StatError "ERROR", @ref OMQ::StatRetry "RETRY", @ref OMQ::StatCanceled "CANCELED")
    - \c type: either \c "global" or \c "workflow" giving the error definition scope
    - [\c workflowid]: (only if \c type = \c "workflow") the ID of the workflow where the workflow-specific error is defined
    - [\c workflowname]: (only if \c type = \c "workflow") the name of the workflow where the workflow-specific error is defined
    - [\c workflowversion]: (only if \c type = \c "workflow") the version of the workflow where the workflow-specific error is defined

    @section rest_class_hash_v3 REST Class Hash

    @ref class_objects "Class" description hashes have the following keys (REST API v3+):
    - \c name: the name of the class object
    - \c version: the version of the class object
    - \c classid: the class object ID
    - \c description: the description of the class
    - \c author: the author of the class
    - \c body: the source code for the class object
    - \c language: the language of the class; either \c "qore" or \c "java"
    - \c created: the date/time the class was created
    - \c modified: the date/time the class was modified
    - \c createdby: (deprecated) always \c "omq"
    - \c modifiedby: (deprecated) always \c "omq"
    - \c tags: any user-defined tags on the class object
    - \c source: the source file that the class object was created from
    - \c offset: the offset in the source file for the source of the class object
    - \c host: the hostname of the machine where the class object was loaded from
    - \c user: the OS user who loaded the class object

    @section rest_mapper_description_hash REST Mapper Description Hash

    @ref mappers "Mapper" description hashes have the following keys:
    - \c mapperid: the mapper ID
    - \c name: the name of the mapper
    - \c version: the version of the mapper
    - \c patch: the patch string of the mapper (if any)
    - \c desc: the description for the mapper
    - \c parse_options: a list of @ref parse_options "symbolic parse options" for the mapper program container (if any parse options are defined)
    - \c created: the date/time the mapper was created
    - \c modified: the date/time the mapper was modified
    - \c type: the @ref mapper-devel-types "type" of the mapper
    - \c opts: a hash of @ref mapper-options "mapper options"; \c "input" and \c "output" define the input and output records, respectively
    - \c valid: @ref True if the mapper is valid, @ref False if not
    - \c groups: a list of @ref rbacgroups "interface groups" that the mapper belongs to; each list element is a @ref rest_interface_group_hash (may be empty)

    @section rest_mapper_type_description_hash REST Mapper Type Description Hash

    @ref mapper-types "Mapper type" description hashes have the following keys:
    - \c name: the mapper type name
    - \c options: a hash of valid options for the mapper type; keys are option names, values are option descriptions
    - \c runtime_options: a hash of valid runtime options for the mapper type; keys are option names, values are option descriptions
    - \c required_options: a list of required options; if any of the options in this list are not provided when creating a mapper of this type, the creation will fail
    - \c required_record_options: a list of mapper options that must be given to create the input or output records for the mapper for mappers that can create either input and/or output descriptions automatically
    - \c requires_input : True
    - \c requires_output : False
    - \c type: either \c "system" (a mapper type @ref mapper-types "provided by Qorus") \c "user" (supplied with a @ref mapper-modules "mapper module")
    - [\c module]: a hash of module info as returned by @ref Qore::get_module_hash() (only present if \c type = \c "user")

    @section rest_vmap_description_hash REST Value Map Description Hash

    @ref value-maps "Value map" description hashes have the following keys:
    - \c id: the value map ID
    - \c name: the name of the value map
    - \c author: the author of the value map (if any)
    - \c throws_exception: a boolean value indicating if a map lookup failure should throw an exception or not
    - \c valuetype: the data type of the value map
    - \c mapsize: the number of entries in the value map
    - \c created: the date/time the value map was created
    - \c modified: the date/time the value map was modified
    - \c groups: a list of @ref rbacgroups "interface groups" that the value map belongs to; each list element is a @ref rest_interface_group_hash (may be empty)

    @section rest_workflow_sync_event_hash REST Workflow Synchronization Event Hash

    Workflow synchronization event hashes have the following keys:
    - \c id: the workflow synchronization event type id
    - \c eventname: the workflow synchronization event type name
    - \c eventkey: synchronization event type key
    - \c posted: a boolean posted status
    - \c created: the date/time the event was created
    - \c modified: the date/time the event was modified (posted)

    @par Example
    @verbatim
hash: (6 members)
  id : 2
  eventname : "regression-test"
  eventkey : "c4e0b32b-fec9-40a1-8f95-c8362a2d0abb"
  posted : True
  created : 2016-02-11 17:08:09.000000 Thu +01:00 (CET)
  modified : 2016-02-11 17:08:09.000000 Thu +01:00 (CET)
    @endverbatim

    @section rest_workflow_sync_event_type_hash REST Workflow Synchronization Event Type Hash

    Workflow synchronization event type hashes have the following keys:
    - \c id: the workflow synchronization event type ID
    - \c name: the workflow synchronization event type name
    - \c desc: the description for the workflow synchronization event type

    @section rest_process_exec_info_hash REST Process Execution Info Hash

    Process info hashes have the following keys:
    - \c id (string): the unique process ID in the cluster
    - \c node (string): the node name where the process is running
    - \c host (string): the hostname where the process is running
    - \c pid (int): the PID on the host
    - \c urls (list<string>): a list of ZeroMQ URLs for the process
    - \c status (string): the process's status as a string
    - \c priv (int): the amount of private memory of the process in bytes
    - \c rss (int): the resident size of the process in bytes
    - \c vsz (int): the virtual size of the process in bytes
    - \c priv_str (string): a string description of the \c priv value
    - \c pct (int): the percentage of main memory taken up by the process on the node

    @section rest_process_info_hash REST Process Information Hash

    The cluster process information hash is keyed by cluster process ID; values have the following keys:
    - \c id (string): the unique process ID in the cluster
    - \c node (string): the node name where the process is running
    - \c host: (string) the hostname of the node running the process
    - \c pid: (int) the PID of the process on the host
    - \c urls (list<string>): a list of ZeroMQ URLs for the process
    - \c status: (int) the process status code; 0 = IDLE, 1 = STARTING, 2 = RUNNING, 3 = STOPPING, 4 = ERROR
    - \c status_string (string) the string description corresponding to \a status
    - \c type: (string) the type of cluster process
    - \c client_id: (string) the type-specific ID for the process
    - \c priv: (int) the amount of private memory (heap + stack + non-shared, non-memory-mapped virtual memory segments) for the process in bytes
    - \c rss: (int) the resident size of the process in bytes
    - \c vsz: (int) the virtual memory size of the process in bytes

    Other keys are present depending on the process type.

    @section omqmapworkflowinfo REST Metadata Workflow Info Hash
    The workflow info hash has the following keys:
    - \c name: the name of the workflow
    - \c version: the version of the workflow
    - \c patch: the patch string for the workflow
    - \c description: the description of the workflow
    - \c workflowid: the workflowid
    - \c created: the date/time the workflow was created
    - \c modified: the date/time the workflow was last modified
    - \c keylist: a list of valid @ref wf_keylist "order keys" for the workflow
    - \c stepmap: a hash where the keys are stepids and the values are step names
    - \c steps: a hash of step dependencies where the keys are stepids and the values are lists of steps are the direct dependent steps (that must be COMPLETE before the step given as the key can be executed)
    - \c segment: a list of segment information, where each element in the list is a @ref omqmapsegmentinfo "segment info hash"
    - \c stepseg: a hash of asynchronous/subworkflow/event stepids and their associated back-end segments
    - \c options: optional: a hash of workflow options where the keys are the option names and values are the descriptions
    - \c lib: optional: a hash of library objects where the top-level keys are one of the following strings: \c "FUNCTION", \c "CLASS", \c "CONSTANT" and the values are lists of object names

    @section omqmapstepinfo REST Metadata Step Info Hash
    The step info hash has the following keys:
    - \c name: step name
    - \c version: step version
    - \c patch: step patchlevel
    - \c description: step description
    - \c steptype: step type
    - [\c stepfunction_instanceid]: the function_instanceid for the primary step function (not present for
      @ref step_source "class-based steps")
    - [\c validationfunction_instanceid]: the function_instanceid for the validation function (if present)
    - [\c endfunction_instanceid]: the function_instanceid for the asynchronous end function (if present)
    - [\c arrayfunction_instanceid]: the function_instanceid for the array function (if present)
    - [\c arraytype]: the type of array step for array steps (only for array steps)
    - [\c step_sourceid]: the ID of the class for the step class, if the step is a class-based step
    - [\c queueid]: the @ref queue_objects "async event queue ID" for @ref asyncsteps "asynchronous steps" (not present if
      not an asynchronous step)
    - [\c queuename]: the name of the @ref queue_objects "async event queue" for @ref asyncsteps "asynchronous steps" (not
      present if not an asynchronous step)
    - [\c workflow_event_typeid]: the workflow_event_typeid for workflow event steps (only for workflow event steps)
    - \c created: the created date/time of the step

    @section omqmapsegmentinfo REST Metadata Segment Info Hash
    - \c steplist: list of stepids in the segment
    - \c steps: a step dependency hash as above
    - \c prereqfor: optional: list of segmentid that depend on this segment
    - \c start: optional: the first stepid in the segment
    - \c linksegment: optional: the segmentid that directly precedes this segment as linked from an asynchronous/subworkflow/event step
    - \c linkstepid: optional: the stepid of the asynchronous/subworkflow/event step that link this segment to the previous segment
*/

string sub get_log_url(hash<auto> cx, string url) {
    return sprintf("%s://%s/log/%s", cx.ssl ? "wss" : "ws", cx.hdr.host, vsprintf(url, argv));
}

sub rlog(hash<auto> cx, *string fmt) {
    string rstr = sprintf("REST: %s %s", cx.hdr.method, cx.url.path);
    if (cx.orig_method && rstr !~ /\?/)
        rstr += sprintf("?action=%s", cx.orig_method);
    if (cx.user)
        rstr += sprintf(" user: %y", cx.user);
    if (cx."peer-info")
        rstr += sprintf(" source: %y", cx."peer-info".address_desc);
    if (fmt) {
        rstr = vsprintf(rstr + " " + fmt, argv);
    }
    Qorus.httpServer.logInfo(rstr);
}

*hash<auto> sub get_library_source(*hash<auto> lh) {
    if (!lh) {
        return {
            "functions": (),
            "classes": (),
            "constants": (),
        };
    }
    if (lh.functions) {
        foreach hash<auto> fh in (\lh.functions)
            fh += FunctionRestClass::moveTags(sysinfo.getFunctionInstance(fh.id).firstValue().firstValue() - "function_instanceid");
    } else {
        lh.functions = ();
    }
    if (lh.classes) {
        foreach hash<auto> fh in (\lh.classes) {
            # issue #3647: take all class info from the metadata cache
            *hash<auto> info = Qorus.qmm.lookupClass(fh.id);
            if (info) {
                info.classid = fh.id;
                fh += FunctionRestClass::moveTags(info);
            }
        }
    } else {
        lh.classes = ();
    }
    if (lh.constants) {
        foreach hash<auto> fh in (\lh.constants) {
            fh += FunctionRestClass::moveTags(sysinfo.getConstant(fh.id).firstValue().firstValue() - "constantid");
        }
    } else {
        lh.constants = ();
    }

    return lh;
}

class QorusOptionsHandlerBase inherits AbstractRestClass {
    #! to handle OPTIONS requests
    hash<HttpResponseInfo> options(hash<auto> cx, *hash<auto> ah) {
        # check if CORS is enabled
        *hash<auto> hdr = QorusHttpServer::getCorsResponseHeaders(cx);
        if (hdr) {
            # return a CORS response
            return AbstractHttpRequestHandler::makeResponse(200, NOTHING, hdr);
        }

        # see if alternate methods would work
        list<string> hl = map $1.key, RestHandler::Methods.pairIterator(),
            $1.key != "OPTIONS" && self.hasCallableMethod($1.value + cx.rest_method);
        # if we have alternate methods, return an appropriate 405 Method Not Allowed error
        if (hl) {
            string desc = sprintf("HTTP method %s is unimplemented in REST class %y (%s)", cx.hdr.method, name(),
                self.className());
            if (cx.orig_method)
                desc += sprintf(" REST method %y", cx.orig_method);
            string ml = foldl $1 + "," + $2, hl;
            desc += sprintf(", available methods: %s", ml);
            return AbstractHttpRequestHandler::makeResponse({"Allow": ml}, 405, desc);
        }

        # otherwise return a 501 Not Implemented response
        return AbstractHttpRequestHandler::make501("REST class %y (%s) does not "
            "implement method %y", name(), self.className(), "options");
    }
}

class QorusRestClass inherits AbstractRestClass, QorusOptionsHandlerBase {
    private {
        const SqlDataOpt = {
            "sqlarg_callback": \QorusRestClass::logSqlData(),
        };
    }

    # SQL data operation logger
    static nothing logSqlData(string sql, *list args) {
        olog(LoggerLevel::DEBUG, "SQL: %s, args: %y", sql, args);
    }

    #! this method is called to dispatch requests on the given object
    private hash<auto> dispatch(RestHandler rh, string mn, *hash<auto> ah, hash<auto> cx) {
        ensure_create_tld();
        # must overwrite thread-local data on each request in case sockets are reused
        tld.cx = cx;
        return AbstractRestClass::dispatch(rh, mn, ah, cx);
    }

    static *hash<HttpHandlerResponseInfo> validateObjectName(*hash<auto> ah, string name, *int rules) {
        if (!ah{name}.val()) {
            return RestHandler::make400("missing required %y parameter; args provided: %y", name, keys ah);
        }
        if (!OMQ::is_valid_object_name(ah{name}, rules)) {
            string rulestr;
            if (!rules) {
                rulestr = "[A-Za-z0-9-_]+";
            } else if (rules & N_EMAIL_ADDRESS) {
                rulestr = "[A-Za-z0-9-_\\.@]+";
            } else {
                rulestr = "[A-Za-z0-9-_\\.]+";
            }
            return RestHandler::make400("invalid characters in name %y; allowed name format: %s", ah{name}, rulestr);
        }
    }

    # deserializes the YAML string values of the given keys from the given hash
    private hash<auto> deserializeYamlValues(hash<auto> ah, softlist<string> keys_,
            reference<*hash<HttpHandlerResponseInfo>> error, bool required_keys = True) {
        foreach string key in (keys_) {
            if (!ah.hasKey(key)) {
                if (required_keys) {
                    error = RestHandler::makeResponse(400, sprintf("no key \"%s\" argument sent in request", key));
                    return ah;
                } else {
                    continue;
                }
            }

            try {
                ah{key} = parse_yaml(ah{key});
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "YAML-PARSER-ERROR") {
                    error = RestHandler::make400("%s: %s", ex.err, ex.desc);
                    return ah;
                }
                rethrow;
            }
        }
        return ah;
    }

    private auto serializeValueToYaml(auto value) {
        auto result = make_yaml(value, (value.typeCode() == NT_HASH || value.typeCode() == NT_LIST) ?
                                        YAML::BlockStyle : YAML::None);
        return trim(result, ".\n\r");
    }

    # serializes each value in the given list to a YAML string
    private list<auto> serializeValuesInListToYaml(*list<auto> l) {
        return map serializeValueToYaml($1), l;
    }

    # serializes the values of the given keys from the given hash to a YAML string
    private hash<auto> serializeValuesToYaml(hash<auto> ah, softlist<string> keys_) {
        map ah{$1} = serializeValueToYaml(ah{$1}), keys_, ah.hasKey($1);
        return ah;
    }

    #! tries to parse the given option as a hash
    static parseOptAsHash(string opt, reference<hash<auto>> ah) {
        # try to parse value as a hash
        if (exists ah{opt}) {
            int ot = ah{opt}.typeCode();
            if (ot == NT_STRING) {
                string ostr = ah{opt};
                ah{opt} = parse_to_qore_value(ah{opt});
                if (ah{opt} && ah{opt}.typeCode() != NT_HASH) {
                    throw "USER-CONNECTION-ERROR", sprintf("%y argument for user connection %y could not be parsed "
                        "to a hash of %s (value given: %y; parsed to %y)", opt, ah.name, opt, ostr, ah{opt});
                }
            } else if (ot != NT_HASH) {
                throw "USER-CONNECTION-ERROR", sprintf("%y argument for user connection %y was not a hash or string "
                    "(value given: %y)", opt, ah.name, ah.tags);
            }
        }
    }

    #! Tries to parse the given option as a hash; returns a 400 error if the option is present and invalid
    static *hash<HttpHandlerResponseInfo> parseOptionAsHash(string opt, reference<*hash<auto>> ah) {
        # try to parse value as a hash
        if (exists ah{opt}) {
            int ot = ah{opt}.typeCode();
            if (ot == NT_STRING) {
                string ostr = ah{opt};
                ah{opt} = parse_to_qore_value(ah{opt});
                if (ah{opt} && ah{opt}.typeCode() != NT_HASH) {
                    return RestHandler::makeResponse(400, sprintf("REST API argument %y could not be parsed "
                        "to a hash (string value given: %y; parsed to %y)", opt, ostr, ah{opt}));
                }
            } else if (ot != NT_HASH) {
                return RestHandler::makeResponse(400, sprintf("REST API argument %y was not a hash or string "
                    "(value given: %y)", opt, ah{opt}));
            }
        }
    }

    #! Tries to parse the tag search options; returns a 400 error if any errors are encountered
    static *hash<HttpHandlerResponseInfo> parseTagOptions(reference<*hash<auto>> ah) {
        if (*hash<HttpHandlerResponseInfo> err = QorusRestClass::parseOptionAsHash("tags", \ah)) {
            return err;
        }

        ah.tag_case_insensitive = parse_boolean(ah.tag_case_insensitive);
        ah.tag_partial_match = parse_boolean(ah.tag_partial_match);
    }

    private static *int doGetInt(*hash<auto> ah, string key, *bool optional) {
        switch (ah{key}.typeCode()) {
            case NT_NOTHING:
                if (optional) {
                    return;
                }
                break;

            case NT_STRING:
                if (ah{key}.intp()) {
                    return ah{key}.toInt();
                }
                break;

            case NT_INT:
                return ah{key};
        }

        # will be converted to a 400 Bad Request response
        throw "REST-ARG-ERROR", sprintf("missing required int argument %y (got type %y)", key, ah{key}.type());
    }

    private static *softnumber doGetNumber(*hash<auto> ah, string key, *bool optional) {
        switch (ah{key}.typeCode()) {
            case NT_NOTHING:
                if (optional) {
                    return;
                }
                break;

            case NT_STRING:
                if (ah{key}.intp()) {
                    return ah{key};
                }
                break;

            case NT_INT:
            case NT_FLOAT:
            case NT_NUMBER:
                return ah{key};
        }

        # will be converted to a 400 Bad Request response
        throw "REST-ARG-ERROR", sprintf("missing required number argument %y (got type %y)", key, ah{key}.type());
    }

    private static *string doGetString(*hash<auto> ah, string key, *bool optional) {
        switch (ah{key}.typeCode()) {
            case NT_NOTHING:
                if (optional) {
                    return;
                }
                break;

            case NT_STRING:
                return ah{key};
        }

        # will be converted to a 400 Bad Request response
        throw "REST-ARG-ERROR", sprintf("missing required string argument %y (got type %y)", key, ah{key}.type());
    }

    private static *list<softstring> doGetStringList(*hash<auto> ah, string key, *bool optional) {
        switch (ah{key}.typeCode()) {
            case NT_STRING:
                # make sure and respect quoted strings to allow for processing file names with spaces
                return ah{key}.split(" ", "\"", True);

            case NT_NOTHING:
                if (optional) {
                    return;
                }
                break;

            case NT_LIST:
                return ah{key};
        }

        throw "REST-ARG-ERROR", sprintf("missing or invalid required argument %y (got type %y; expecting "
            "\"string\" or \"list\")", key, ah{key}.type());
    }

    private static *list<auto> doGetListOfHashes(*hash<auto> ah, string key, *bool optional) {
        switch (ah{key}.typeCode()) {
            case NT_HASH:
                return (ah{key},);

            case NT_NOTHING:
                if (optional) {
                    return;
                }
                break;

            case NT_LIST:
                return ah{key};
        }

        throw "REST-ARG-ERROR", sprintf("missing or invalid required argument %y (got type %y; expecting "
            "\"list\")", key, ah{key}.type());
    }

    private static *hash<auto> doGetHash(*hash<auto> ah, string key, *bool optional) {
        switch (ah{key}.typeCode()) {
            case NT_STRING: {
                try {
                    auto v = parse_to_qore_value(ah{key});
                    if (v.typeCode() == NT_HASH) {
                        return v;
                    }
                } catch (hash<ExceptionInfo> ex) {
                }
                throw "REST-ARG-ERROR", sprintf("missing or invalid required argument %y (got type %y; expecting "
                    "\"hash\" or \"string\" that can be parsed to a hash)", key, ah{key}.type());
            }

            case NT_NOTHING:
                if (optional) {
                    return;
                }
                break;

            case NT_HASH:
                return ah{key};
        }

        throw "REST-ARG-ERROR", sprintf("missing or invalid required argument %y (got type %y; expecting "
            "\"string\" or \"list\")", key, ah{key}.type());
    }
}

/** @REST /exec/{id}

    This URI path provides actions and information regarding a particular workflow execution instance.
*/
class WorkflowExecInstanceRestClass inherits QorusRestClass {
    private {
        hash<auto> wf;
    }

    constructor(hash<auto> v_wf) {
        wf = v_wf;
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(id))
                return new AttributeRestClass(wf{id});
        }
    }

    softstring name() {
        return wf.executionID;
    }

    /** @REST PUT action=stop

        @par Description
        Manually stops the workflow execution instance.

        @par Return Value
        This API returns \c "OK" if successful.

        @deprecated Workflow execution instances should not be manually stopped; they should be disabled instead; use @ref rest_api_PUT_workflows__id_or_name__enable and @ref rest_api_PUT_workflows__id_or_name__disable instead of starting and stopping workflow execution instances
    */
    hash<auto> putStop(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);
        try {
            api."omq.system.stop-workflow-instance"(wf.executionID);
        } catch (hash<ExceptionInfo> ex) {
        }
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=setOptions

        @par Description
        Sets workflow options; workflow options are now actually global for the given workflow; this API will set global options against the workflow and not just on the current execution instance level.  If the workflow has an option list and any of the options are not valid for that workflow, an exception will be thrown, however, even if an exception is thrown due to an option error, all other options will still be set.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c options: a hash of options to set against the workflow; if the value of this key is a string, then it is first parsed with @ref Util::parse_to_qore_value(), which should then return a hash

        @par Return Value
        This API returns a string confirming that the options have been set.

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing \c "options" argument or \c "options" is not a hash (or string parsed to a hash with @ref Util::parse_to_qore_value())
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-OPTION-ERROR: invalid option for workflow or option cannot be overridden at the workflow level

        @note
        - workflow options are persistent (persistent workflow options were implemented in Qorus 3.0.0)

        @deprecated use @ref rest_api_PUT_workflows__id_or_name__setOptions instead
    */
    hash<auto> putSetOptions(hash<auto> cx, *hash<auto> ah) {
        if (ah.options.typeCode() == NT_STRING)
            ah.options = parse_to_qore_value(ah.options);
        if (!ah.options)
            return RestHandler::make400("error setting options on id %d: missing 'options' hash in message body", wf.executionID);
        if (ah.options.typeCode() != NT_HASH)
            return RestHandler::make400("error setting options on id %d: 'options' argument is not a hash (got type %y instead)", wf.executionID, ah.options.type());

        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        # set options
        return RestHandler::makeResponse(200, api."omq.system.set-workflow-option"(wf.executionID, ah.options));
    }

    /** @REST GET

        @par Return Value
        This API returns a hash with the keys of @ref rest_execution_instance_hash, plus the following keys:
        - \c groups: list of @ref rbacgroups "interface groups" that the workflow belongs to; each list element is a @ref rest_interface_group_hash (may be empty)
        - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be empty)
        - \c log_url: a complete URL to the websocket source for the workflow log
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        return RestHandler::makeResponse(200, wf);
    }
}

/** @REST /exec/{workflowname}

    This URI path provides actions and information about workflow execution instances for a particular workflow.
*/
class WorkflowExecInstanceGroupRestClass inherits QorusRestClass {
    private {
        string name;
        *string ver;
        *list l;
    }

    constructor(string v_name, *string v_ver, *list v_l) {
        name = v_name;
        ver = v_ver;
        l = v_l;
    }

    string name() {
        return "workflow-execution-instance-group";
    }

    /** @REST PUT action=stop

        @par Description
        Manually stops the workflow execution instances.

        @par Return Value
        This API returns a hash with the following key if there are execution instances:
        - \c stopped: the value is a descriptive string for the workflow
        .
        otherwise it returns a string \c "no instances to stop".

        @deprecated Workflow execution instances should not be manually stopped; they should be disabled instead; use @ref rest_api_PUT_workflows__id_or_name__enable and @ref rest_api_PUT_workflows__id_or_name__disable instead of starting and stopping workflow execution instances
    */
    hash<auto> putStop(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s)", getDesc());
        if (l) {
            # workflow access is checked in Control::stopWorkflow()
            hash<auto> sh;
            Qorus.control.stopWorkflow(cx, name, ver, \sh);
            return RestHandler::makeResponse(200, ("stopped": sh.firstValue()));
        }
        return RestHandler::makeResponse(200, "no instances to stop");
    }

    /** @REST GET action=desc

        @par Return Value
        Returns a string describing the workflow.
    */
    string getDesc() {
        return sprintf("%s%s", name, ver ? sprintf(" %s", ver) : "");
    }

    /** @REST PUT action=setOptions

        @par Description
        Sets workflow options; workflow options are now actually global for the given workflow; this API will set global options against the workflow and not on the execution instances.  If the workflow has an option list and any of the options are not valid for that workflow, an exception will be thrown, however, even if an exception is thrown due to an option error, all other options will still be set.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c options: a hash of options to set against the workflow; if the value of this key is a string, then it is first parsed with @ref Util::parse_to_qore_value(), which should then return a hash

        @par Return Value
        This API returns a hash keyed by execution instance ID of option set.

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing \c "options" argument or \c "options" is not a hash (or string parsed to a hash with @ref Util::parse_to_qore_value())
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-OPTION-ERROR: invalid option for workflow or option cannot be overridden at the workflow level

        @note
        - workflow options are persistent (persistent workflow options were implemented in Qorus 3.0.0)

        @deprecated use @ref rest_api_PUT_workflows__id_or_name__setOptions instead
    */
    hash<auto> putSetOptions(hash<auto> cx, *hash<auto> ah) {
        if (ah.options.typeCode() == NT_STRING)
            ah.options = parse_to_qore_value(ah.options);
        if (!ah.options)
            return RestHandler::make400("error setting options on %s: missing 'options' hash in message body", getDesc());
        if (ah.options.typeCode() != NT_HASH)
            return RestHandler::make400("error setting options on %s: 'options' key is not set to a hash; got type %y instead", getDesc(), ah.options.type());

        rlog(cx, "(%s)", getDesc());

        if (!l)
            return RestHandler::makeResponse(200, "no instances to modify");

        # set options
        hash<auto> h;

        foreach hash<auto> eh in (l) {
            int eid = eh.executionID;

            # workflow access is checked in Control::setWorkflowInstanceOption()
            h{eid} = Qorus.control.setWorkflowInstanceOption(cx, eid, ah.options)
                ? "workflow execution instance stopped"
                : "OK";
        }

        return RestHandler::makeResponse(200, h);
    }

    /** @REST GET

        @par Return Value
        This API returns a list of hashes with the keys of @ref rest_execution_instance_hash, plus the following keys:
        - \c groups: list of @ref rbacgroups "interface groups" that the workflow belongs to; each list element is a @ref rest_interface_group_hash (may be empty)
        - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be empty)
        - \c log_url: a complete URL to the websocket source for the workflow log
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /workflows/{id_or_name}/instances

    This REST URI path provides actions and information about workflow execution instances for a particular workflow.
*/
class WorkflowInstanceRestClass inherits QorusRestClass {
    private {
        hash<auto> wf;
    }

    constructor(hash<auto> cx, hash<auto> v_wf, int apiver = 1) {
        wf = v_wf + ("exec": WorkflowInstanceRestClass::staticGetExecList(cx, v_wf.workflowid, v_wf.name, v_wf.version, apiver));
    }

    static hash<auto> staticGetCompatExecHash() {
        return {
            "status": "n/a",
            "iterations": 0,
            "errors": 0,
            "warnings": 0,
        };
    }

    static list<auto> staticGetExecList(hash<auto> cx, int wfid, string name, string ver, int apiver) {
        list<auto> l = Qorus.control.getWorkflowInfoList(name, ver);
        foreach hash<auto> eih in (\l) {
            # convert executionID to an integer
            eih.executionID = eih.executionID.toInt();
            # add log url
            eih.log_url = get_log_url(cx, "workflows/%d", wfid);
            # remove keys for apiver < 3
            if (apiver < 3) {
                eih -= ("remote", "process");
                eih += WorkflowInstanceRestClass::staticGetCompatExecHash();
            }
            # add to hash without redundant keys
            eih -= ("name", "version", "workflowid", "groups");
        }
        return l;
    }

    string name() {
        return "instances";
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        # get running workflow info for the given ID
        *hash<auto> eih = api."omq.system.get-workflow-info"(id);
        if (eih) {
            eih.executionID = eih.executionID.toInt();
            # remove keys new keys; add compat keys for v1 & v2 APIs
            return new WorkflowExecInstanceRestClass(eih - ("remote", "process") +
                WorkflowInstanceRestClass::staticGetCompatExecHash());
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(id))
                return new AttributeRestClass(wf{id});
        }
    }

    /** @REST GET

        @par Return Value
        This API returns a list of hashes with the keys of @ref rest_execution_instance_hash for the current workflow,
        plus the following keys:
        - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be
          empty)
        - \c log_url: a complete URL to the websocket source for the workflow log
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        return RestHandler::makeResponse(200, wf.exec);
    }
}

/** @REST /orders/{id}

    This REST URI path provides actions and information about specific workflow orders.
*/
class WorkflowOrderInstanceRestClass inherits QorusRestClass {
    private {
        hash<auto> wf;
    }

    constructor(hash<auto> wf, int apiver = 1) {
        # DBG
        if (!wf.InstanceInfo.workflowstatus || !wf.InstanceInfo.workflow_instanceid) {
            olog(LoggerLevel::INFO, "ERROR: %N\nstack: %N", wf, get_stack());
        }

        hash<auto> h = remove wf.InstanceInfo;

        wf.OrderInfo -= ("created", "modified");
        h += remove wf.OrderInfo;
        # rename fields
        h.warning_count = int(remove h.warnings);
        h.error_count = int(remove h.errors);
        if (apiver < 3) {
            remove h{"retries", "stepdata"};
        } else {
            h.retry_count = int(remove h.retries);
        }

        # rewrite hierarchy info
        map wf.HierarchyInfo.$1 = wf.HierarchyInfo.$1 - ("createdby", "modifiedby", "errors", "warnings")
            + ("error_count": int(wf.HierarchyInfo.$1.errors), "warning_count": int(wf.HierarchyInfo.$1.warnings)),
            keys wf.HierarchyInfo;
        # edit step info
        map delete wf.StepInstances[$1].flow_instanceid, wf.StepInstances.rangeIterator();

        # issue #2808: StepInstances must exist
        if (!wf.StepInstances) {
            wf.StepInstances = ();
        }

        self.wf = h + wf + ("actions": WorkflowOrderInstanceRestClass::staticGetActions(h.workflowstatus));
        self.wf.notes = sysinfo.getOrderInstanceNotes(h.workflow_instanceid);
        self.wf.note_count = self.wf.notes.size();
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(name))
                return new AttributeRestClass(wf{name});
        }
    }

    softstring name() {
        return wf.workflow_instanceid;
    }

    /** @REST POST action=execSynchronous

        @par Description
        Executes a workflow in synchronous mode against the current order, which must have status @ref OMQ::StatReady
        or @ref OMQ::StatScheduled; it is not possible to process workflow data with other statuses synchronously.\n
        The call will normally return only after the workflow reaches a @ref OMQ::StatComplete or @ref OMQ::StatError
        state, unless the system or the workflow order data instance are manually stopped while the workflow order
        data instance is being processed, in which case other statuses can be returned.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c options: (hash) an optional hash of option names and values; if any options are not valid for the workflow,
          then an exception is raised and the synchronous workflow execution instance is not started

        @par Return Value
        This API returns a hash with the following keys:
        - \c workflow_instanceid: the workflow instance ID of the order
        - \c status: the status of the workflow
        - \c dynamicdata: the dynamic data of the workflow order instance

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SHUTDOWN-IN-PROGRESS: cannot start new workflows because the system is
          shutting down

        @see
        - omq.system.exec-synchronous-workflow()
        - omq.system.exec-synchronous-existing()
    */
    hash<auto> postExecSynchronous(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(201, api."omq.system.exec-synchronous-existing"(ah + {
            "workflow_instanceid": wf.workflow_instanceid,
            "options": ah.options,
        }));
    }

    /** @REST PUT action=cancel

        @SCHEMA
        @summary Cancels the current workflow order data instance

        @desc Blocks the current workflow order data instance by changing its status to \
        @ref OMQ::StatCanceled "CANCELED".  An exception will be thrown if the status is \
        @ref OMQ::StatInProgress "IN-PROGRESS".  No further processing can \
        be done on workflow order data instances with a @ref OMQ::StatCanceled "CANCELED" status (unless the \
        workflow order instance is recovered back from @ref OMQ::StatCanceled "CANCELED" to its original status or \
        the status is first updated to @ref OMQ::StatError "ERROR" and then to @ref OMQ::StatRetry "RETRY"). Note \
        that @ref OMQ::StatCanceled "CANCELED" and @ref OMQ::StatBlocked "BLOCKED" statuses have the same effect, \
        however @ref OMQ::StatCanceled "CANCELED" is meant to be a permanent or final status, while \
        @ref OMQ::StatBlocked "BLOCKED" is meant to be temporary.

        @return (hash WorkflowOrderStatusInfo): provides status information about the order processed
        - workflow_status (string): the status of the order after updating

        @error (409): exception processing request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c CANCEL-WORKFLOW-ERROR: invalid status, foreign session id, missing original
          status, cancel operation already in progress

        @see
        - @ref rest_api_PUT_orders__id__uncancel
        - omq.system.cancel-workflow-instance()
        - omq.system.cancel-workflow-instances()
    */
    hash<auto> putCancel(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # workflow access is checked in SegmentManager::cancelWorkflowInstance()
        return RestHandler::makeResponse(200, SM.cancelWorkflowInstance(cx, wf.workflow_instanceid, True));
    }

    /** @REST PUT action=uncancel

        @SCHEMA
        @summary Resets the status of a canceled workflow order data instance to its original status

        @desc Resets the status of a canceled workflow order data instance to its original status before canceling.

        @return (hash WorkflowOrderStatusInfo): provides status information about the order processed

        @error (409): exception processing request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c CANCEL-WORKFLOW-ERROR: invalid status, foreign session id, missing original
          status, uncancel operation already in progress

        @see
        - @ref rest_api_PUT_orders__id__cancel
        - omq.system.cancel-workflow-instance()
        - omq.system.cancel-workflow-instances()
    */
    hash<auto> putUncancel(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # workflow access is checked in SegmentManager::cancelWorkflowInstance()
        return RestHandler::makeResponse(200, SM.cancelWorkflowInstance(cx, wf.workflow_instanceid, False));
    }

    /** @REST PUT action=block

        @SCHEMA
        @summary Blocks the current workflow order data instance

        @desc Blocks the current workflow order data instance by changing its status to \
        @ref OMQ::StatBlocked "BLOCKED".  An exception will be thrown if the status is \
        @ref OMQ::StatInProgress "IN-PROGRESS".  No further processing can \
        be done on workflow order data instances with a @ref OMQ::StatCanceled "CANCELED" status (unless the \
        workflow order instance is recovered back from @ref OMQ::StatCanceled "CANCELED" to its original status or \
        the status is first updated to @ref OMQ::StatError "ERROR" and then to @ref OMQ::StatRetry "RETRY"). Note \
        that @ref OMQ::StatCanceled "CANCELED" and @ref OMQ::StatBlocked "BLOCKED" statuses have the same effect, \
        however @ref OMQ::StatCanceled "CANCELED" is meant to be a permanent or final status, while \
        @ref OMQ::StatBlocked "BLOCKED" is meant to be temporary.

        @return (hash WorkflowOrderStatusInfo): provides status information about the order processed

        @error (409): exception processing request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c BLOCK-WORKFLOW-ERROR: invalid status, foreign session id, missing original
          status, block operation already in progress

        @see
        - @ref rest_api_PUT_orders__id__unblock
        - @ref rest_api_PUT_orders_unblock
        - omq.system.block-workflow-instance()
        - omq.system.block-workflow-instances()
    */
    hash<auto> putBlock(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        # workflow access is checked in SegmentManager::blockWorkflowInstance()
        return RestHandler::makeResponse(200, SM.blockWorkflowInstance(cx, string(wf.workflow_instanceid), True));
    }

    /** @REST PUT action=unblock

        @SCHEMA
        @summary Resets the status of a blocked workflow order data instance to its original status

        @desc Resets the status of a blocked workflow order data instance to its original status before blocking.

        @return (hash WorkflowOrderStatusInfo): provides status information about the order processed

        @error (409): exception processing request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c BLOCK-WORKFLOW-ERROR: invalid status, foreign session id, missing original
          status, block operation already in progress

        @see
        - @ref rest_api_PUT_orders__id__block
        - @ref rest_api_PUT_orders_block
        - omq.system.block-workflow-instance()
        - omq.system.block-workflow-instances()
    */
    hash<auto> putUnblock(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # workflow access is checked in SegmentManager::blockWorkflowInstance()
        return RestHandler::makeResponse(200, SM.blockWorkflowInstance(cx, string(wf.workflow_instanceid), False));
    }

    /** @REST PUT action=retry

        @par Description
        Retries the current workflow order instance; in order to make a retry; the workflow order status must be
        @ref OMQ::StatError, @ref OMQ::StatAsyncWaiting, or OMQ::StatRetry.

        @par Return Value
        This API returns a hash with the following keys:
        - \c steps_updated: (deprecated) always 0 in this version of Qorus
        - \c segments_updated: the number of segments updated
        - \c workflow_updated: always @ref True in this version of Qorus
        - \c workflow_status: always @ref OMQ::StatRetry in this version of Qorus
        - \c cached: @ref True if the workflow data is currently cached

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c STATUS-ERROR: workflow data does not have either @ref OMQ::StatError,
          @ref OMQ::StatAsyncWaiting, or OMQ::StatRetry status
        - <tt><b>409 Conflict</b></tt>: \c SESSION-ERROR: cannot change status for workflow data managed by another
          Qorus instance (foreign session ID)
        - <tt><b>409 Conflict</b></tt>: \c RETRY-ERROR: invalid workflow instance ID

        @see omq.system.retry-workflow-instances()
    */
    hash<auto> putRetry(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        # workflow access is checked in SegmentManager::retryWorkflowInstanceExtern()
        return RestHandler::makeResponse(200, SM.retryWorkflowInstanceExtern(cx, wf.workflow_instanceid));
    }

    /** @REST PUT action=reschedule

        @par Description
        Sets or removes the scheduled date for the current workflow order data instance.  Setting the scheduled date for a workflow order means that the
        workflow order data will not be processed before the scheduled date and time.  The workflow order data must normally have status
        @ref OMQ::StatReady or @ref OMQ::StatScheduled to be rescheduled, however also workflows with @ref OMQ::StatCanceled and
        @ref OMQ::StatBlocked statuses can be rescheduled if their original status is @ref OMQ::StatReady or @ref OMQ::StatScheduled.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c date: (optional) parsed as a date; this is the new scheduled date to set; if not present, then any scheduled date will be removed

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SESSION-ERROR: cannot reschedule workflow data owned by a foreign session
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-STATUS-ERROR: only workflows with status @ref OMQ::StatReady or @ref OMQ::StatScheduled or blocked or canceled workflows with original status @ref OMQ::StatReady or @ref OMQ::StatScheduled can be rescheduled
        - <tt><b>409 Conflict</b></tt>: \c RESCHEDULE-ERROR: reschedule failed because workflow order data started processing while the request was being processed

        @see
        - omq.system.reschedule-order()
        - omq.system.reschedule-orders()
    */
    hash<auto> putReschedule(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        if (ah.date)
            ah.date = date(ah.date);
        return RestHandler::makeResponse(200, api."omq.system.reschedule-order"(wf.workflow_instanceid, ah.date));
    }

    /** @REST PUT action=setPriority

        @par Description
        Changes the priority for an existing workflow order data instance.  The workflow order data must not have status @ref OMQ::StatComplete.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c priority: the new order priority from 0 - 999; priority 0 is the highest; 999 is the lowest

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SESSION-ERROR: cannot reschedule workflow data owned by a foreign session
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-STATUS-ERROR workflows with status @ref OMQ::StatComplete cannot have their priority changed

        @see
        - omq.system.reprioritize-order()
        - omq.system.reprioritize-orders()
    */
    hash<auto> putSetPriority(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.priority)
            throw "ORDER-PRIORITY-ERROR", sprintf("missing \"priority\" argument to set new priority for workflow_instanceid %d", wf.workflow_instanceid);
        ah.priority = ah.priority.toInt();

        rlog(cx);
        # workflow access is checked in SegmentManager::reprioritizeWorkflowExtern()
        SM.reprioritizeWorkflowExtern(cx, wf.workflow_instanceid, ah.priority);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=setError

        @par Description
        Changes the status of a workflow order data instance to @ref OMQ::StatError, as long as the starting status is
        @ref OMQ::StatRetry, @ref OMQ::StatCanceled, @ref OMQ::StatBlocked, or @ref OMQ::StatAsyncWaiting.  If the
        status is any other status, an exception will be thrown.\n\n
        To set a workflow order data instance with a @ref OMQ::StatWaiting status to @ref OMQ::StatError, set the
        child workflows to @ref OMQ::StatError first and the status of the parent workflow order will be updated
        automatically.\n\n
        When setting a workflow order from @ref OMQ::StatCanceled to @ref OMQ::StatError, outstanding events will be
        queued and the associated queued event keys will be present in the return value.

        @par Return Value
        This API returns a hash with the following keys:
        - \c steps_updated: number of steps updated
        - \c segments_updated: number of segments updated
        - \c workflow_status: always @ref OMQ::StatError
        - \c old_status: the old workflow data status
        - \c queued_detached_segments: number of detached segment events queued
        - \c queued_subworkflows: number of subworkflow events queued
        - \c queued_async_messages: number of async events queued
        - \c queued_sync_events: number of workflow synchronization events queued
        - \c queued_async_retries: number of async events queued
        - \c queued_retries: number of retry events queued
        - \c queued_fixed_retries: number of retry events with a fixed retry time queued

        @see
        - omq.system.set-workflow-instance-error()
        - omq.system.set-workflow-instance-errors()
    */
    hash<auto> putSetError(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # workflow access is checked in SegmentManager::setWorkflowInstanceError()
        return RestHandler::makeResponse(200, SM.setWorkflowInstanceError(cx, wf.workflow_instanceid));
    }

    /** @REST PUT action=lock

        @par Description
        Locks the current workflow order so that it can only be updated by the current user.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c note: (required) a string note that gives the reason for setting the operator lock

        @par Return Value
        This API returns \c "OK" upon successful execution

        @see
        - @ref rest_api_PUT_orders__id__unlock
        - @ref rest_api_PUT_orders__id__breakLock
    */
    hash<auto> putLock(hash<auto> cx, *hash<auto> ah) {
        if (!ah.note || ah.note.typeCode() != NT_STRING)
            throw "ORDER-ERROR", sprintf("missing string \"note\" argument in workflow lock request for workflow_instanceid %d", wf.workflow_instanceid);

        SM.lockOrder(wf, "ORDER LOCK: " + ah.note);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=unlock

        @par Description
        Unlocks the current workflow order so that it can be updated by any authorized user.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c note: (optional) a string note that gives the reason for removing the operator lock; if not passed, a default note will be added

        @par Return Value
        This API returns \c "OK" upon successful execution

        @note
        - only the user that set the lock on the order can unlock the order

        @see
        - @ref rest_api_PUT_orders__id__lock
        - @ref rest_api_PUT_orders__id__breakLock
    */
    hash<auto> putUnlock(hash<auto> cx, *hash<auto> ah) {
        if (!ah.note || ah.note.typeCode() != NT_STRING)
            ah.note = "<unlocked order without note>";

        SM.unlockOrder(wf, "ORDER UNLOCK: " + ah.note);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=breakLock

        @par Description
        Breaks the current workflow order lock so that it can be updated by any authorized user.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c note: (required) a string note that gives the reason for breaking the operator lock

        @par Return Value
        This API returns \c "OK" upon successful execution

        @see
        - @ref rest_api_PUT_orders__id__lock
        - @ref rest_api_PUT_orders__id__unlock
    */
    hash<auto> putBreakLock(hash<auto> cx, *hash<auto> ah) {
        if (!ah.note || ah.note.typeCode() != NT_STRING)
            throw "ORDER-ERROR", sprintf("missing string \"note\" argument in workflow break lock request for workflow_instanceid %d", wf.workflow_instanceid);

        SM.breakOrderLock(wf, "BREAK ORDER LOCK: " + ah.note);
        return RestHandler::makeResponse(200, "OK");
    }

    /*
        Parse the string and return list of numbers.
        Examples of strings: "1", "2-5", "3,5, 7-9"
    */
    static list<int> parseRange(*string text) {
        if (!text) {
            return (0,);
        }
        list<int> numbers = ();
        list<string> parts = select (map trim($1), text.split(',')), $1.val();
        foreach string str in (parts) {
            list<string> bounds = str.split("-");
            if (bounds.size() == 2) {
                numbers += range(int(bounds[0]), int(bounds[1]) + 1);
            } else {
                numbers += int(str);
            }
        }
        return numbers;
    }

    static softlist<int> parseRange(int num) {
        return num;
    }

    /** @REST PUT action=skipStep

        @par Description
        Skips execution of a step in the current workflow order.  Sometimes execution for a given step must be skipped, but the rest of the workflow logic should be executed.  This API call allows Qorus to continue executing a workflow order data instance after skipping the given step.  Only steps with @ref OMQ::StatError, @ref OMQ::StatRetry, @ref OMQ::StatEventWaiting, or @ref OMQ::StatAsyncWaiting can be skipped.  Subworkflow steps with any status cannot be skipped; the child workflow must be corrected instead.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c stepid: (required) the step ID to skip
        - \c ind: (optional) one or more step array index values to skip (ranges accepted; ex: \c "1,3,5-7"); if not present defaults to 0
        - \c noretry: (optional) parsed with @ref Qore::parse_boolean(); if @ref True then no retry will be executed

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SKIP-STEP-ERROR: step is a subworkflow step; step has not been executed in the given workflow order instance; the given workflow instance ID does not exist
        - <tt><b>409 Conflict</b></tt>: \c STEP-STATUS-ERROR: step status does not allow it to be skipped (ex: IN-PROGRESS, COMPLETE)
        - <tt><b>409 Conflict</b></tt>: \c SESSION-ERROR: workflow order instance belongs to another Qorus session

        @note
        - this method will also queue internal events for asynchronous steps, and will trigger a retry of the workflow for all other steps to ensure that the workflow is immediately reprocessed unless the \c noretry argument is passed as @ref True.
    */
    hash<auto> putSkipStep(hash<auto> cx, *hash<auto> ah) {
        if (!ah.stepid)
            throw "SKIP-STEP-ERROR", sprintf("cannot skip step with no \"stepid\" argument");

        if (ah.noretry)
            ah.noretry = parse_boolean(ah.noretry);

        ListIterator li(WorkflowOrderInstanceRestClass::parseRange(ah.ind));

        while (li.next()) {
            softint ind = li.getValue();
            # workflow access is checked in SegmentManager::skipStepWithoutRetry()
            SM.skipStepWithoutRetry(cx, wf.workflow_instanceid, ah.stepid, ind);
        }
        if (!ah.noretry)
            SM.retryWorkflowInstanceExtern(cx, wf.workflow_instanceid);

        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST GET action=listErrors

        @par Description
        Returns information about workflow order errors for the given workflow order instance

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c orderby: one or more field names for sorting the output
        - \c error: the error text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c description: the description text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c info: the info text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given
        - \c stepid: limit the search to one or more stepids
        - \c severity: limit the search to one or more severity values
        - \c name: limit the search to one or more step names
        - \c version: limit the search to one or more step versions
        - \c retry: limit the search to errors with or without the retry flag
        - \c business_error: limit the search to errors with or without the business_error flag
        - \c error_instanceid: mit the search to one or more error_instanceids
        - \c mindate: give the lower date range for the error search
        - \c maxdate: give the upper date range for the error search
        - \c limit: the maximum number of errors to return
        - \c offset: the starting error to return (use when paging for example)

        @par Return Value
        This API returns a list of hashes with the following keys for all data matched according to the search arguments:
        - \c name: the name of the workflow
        - \c version: the version of the workflow
        - \c workflow_instanceid: the workflow instance ID
        - \c workflowid: the workflow ID
        - \c stepid: the step ID where the error occurred
        - \c stepname: the name of the step where the error occurred
        - \c stepversion: the version of the step where the error occurred
        - \c ind: the array step index number where the error occurred
        - \c workflowstatus: current status of the workflow (see @ref StatusDescriptions for possible values)
        - \c started: the date and time when the workflow order started processing
        - \c completed: the date and time when the workflow order was completed
        - \c parent_workflow_instanceid: any parent workflow instance ID
        - \c custom_status: the custom status of the workflow order, if any
        - \c priority: the priority of the workflow order
        - \c scheduled: any scheduled date for the workflow order
        - \c error_instanceid: the error instance ID
        - \c error: the error code string
        - \c description: a description for the error (if any)
        - \c info: additional information about the error (if any)
        - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
        - \c created: the date and time the error was raised
        - \c retry: the retry count of the error
        - \c business_error: a boolean flag indicating of the error is a business error
        - \c custom_status_desc: a descriptive string for the custom status (if any)
    */
    hash<auto> getListErrors(hash<auto> cx, *hash<auto> ah) {
        # issue 1879 handle list arguments
        if (ah.error =~ /,/)
            ah.error = ah.error.split(",");
        if (ah.stepid =~ /,/)
            ah.stepid = ah.stepid.split(",");
        if (ah.name =~ /,/)
            ah.name = ah.name.split(",");
        if (ah.error_instanceid =~ /,/)
            ah.error_instanceid = ah.error_instanceid.split(",");
        if (ah.workflowid =~ /,/)
            ah.workflowid = ah.workflowid.split(",");
        if (ah.workflowstatus =~ /,/)
            ah.workflowstatus = ah.workflowstatus.split(",");

        *list l = sysinfo.searchWorkflowErrors(ah + ("workflow_instanceid": wf.workflow_instanceid));
        return RestHandler::makeResponse(200, l);
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
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        # add notes list to instance hash
        return RestHandler::makeResponse(200, wf);
    }

    static softlist staticGetActions(string stat) {
        switch (stat) {
            case OMQ::StatInProgress:
            case OMQ::StatIncomplete:
            case OMQ::StatComplete:
                return;

            case OMQ::StatError:
            case OMQ::StatAsyncWaiting:
            case OMQ::StatEventWaiting:
            case OMQ::StatRetry:
            case OMQ::StatWaiting:
                return ("block", "cancel", "retry");

            case OMQ::StatCanceled:
                # issue #2948: CANCELED orders can be updated to BLOCKED
                return ("unCancel", "block");

            case OMQ::StatReady:
                return ("block", "cancel", "reschedule");

            case OMQ::StatScheduled:
                return ("block", "cancel", "reschedule");

            case OMQ::StatBlocked:
                # issue #2948: BLOCKED orders can be updated to CANCELED
                return ("unBlock", "cancel");
        }
    }

    /** @REST GET action=notes

        @par Description
        Returns a list of notes saved against the order; each element is a @ref rest_order_note_hash.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c limit: the maximum number of notes to return; if omitted then all notes are returned

        @par Return Value
        This API returns a list of hashes of notes saved against the order; each element is a @ref rest_order_note_hash.
     */
    hash<auto> getNotes(hash<auto> cx, *hash<auto> ah) {
        softlist l = wf.notes;
        if (ah.limit)
            splice l, ah.limit.toInt();

        return RestHandler::makeResponse(200, l);
    }

    /* params: ah
        - note: string, a note body

        use POST action=notes instead, not idempotent
     */
    hash<auto> putNotes(hash<auto> cx, *hash<auto> ah) {
        return postNotes(cx, ah);
    }

    /** @REST POST action=notes

        @SCHEMA
        @summary Creates an order note on the current workflow order

        @desc Creates an order note on the current workflow order

        @params
        - note (string): the note to create on the order

        @return (string): OK
        @ENDSCHEMA
     */
    hash<auto> postNotes(hash<auto> cx, *hash<auto> ah) {
        SM.setOrderInstanceNote(cx, wf.workflow_instanceid, ("note": ah.note));
        # TODO: return value = newly added note hash
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=staticData

        @SCHEMA
        @summary Replaces the @ref staticdata "static data" for the current order

        @desc Replaces the @ref staticdata "static data" for the current order

        @params
        - newdata (hash): the new @ref staticdata "static data" for the current workflow order; must be a non-empty
          hash

        @return (string): OK

        @error (400): invalid or missing argument
        @ENDSCHEMA

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: \c ORDER-STATIC-DATA-ARG-ERROR: the new static data hash cannot be empty
    */
    hash<auto> putStaticData(hash<auto> cx, *hash<auto> ah) {
        if (ah.newdata.typeCode() != NT_HASH || !ah.newdata) {
            throw "ORDER-STATIC-DATA-ARG-ERROR", sprintf("expecting \"newdata\" argument giving the new static data "
                "for workflow order %d which must be a non-empty hash; got type %y instead (value: %y)",
                wf.workflow_instanceid, ah.newdata.type(), ah.newdata);
        }
        SM.replaceStaticData(cx, wf.workflow_instanceid, ah.newdata);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=dynamicData

        @SCHEMA
        @summary Replaces the @ref dynamicdata "dynamic data" for the current order

        @desc Replaces the @ref dynamicdata "dynamic data" for the current order

        @params
        - newdata (*hash): the new @ref dynamicdata "dynamic data" for the current workflow order

        @return (string): OK

        @error (400): invalid or missing argument
        @ENDSCHEMA

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: \c ORDER-STATIC-DATA-ARG-ERROR: invalid \c newdata argument
    */
    hash<auto> putDynamicData(hash<auto> cx, *hash<auto> ah) {
        if (exists ah.newdata && ah.newdata.typeCode() != NT_HASH) {
            throw "ORDER-STATIC-DATA-ARG-ERROR", sprintf("expecting \"newdata\" argument giving the new static data "
                "for workflow order %d which must be a non-empty hash; got type %y instead (value: %y)",
                wf.workflow_instanceid, ah.newdata.type(), ah.newdata);
        }
        SM.replaceDynamicData(cx, wf.workflow_instanceid, ah.newdata);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=updateKeys

        @SCHEMA
        @summary Replace all @ref wf_keylist "order keys" for the current workflow order

        @desc Replace all @ref wf_keylist "order keys" for the current workflow order

        @params
        - orderkeys (hash[list<string>] OrderKeySet): the @ref wf_keylist "order keys" to replace for the current \
          workflow order
        - truncate (*bool): truncate any key values automatically to the length of the column (4000 characters)

        @return (hash[list<string>] OrderKeySet): all order keys for the order after updating

        @error (400): invalid \a orderkeys argument
        @ENDSCHEMA

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: \c ORDER-KEYS-ARG-ERROR: the \c orderkeys argument was missing or not a
          hash, an order key was given that is not valid for the workflow,duplicate key value
    */
    hash<auto> putUpdateKeys(hash<auto> cx, *hash<auto> ah) {
        if (ah.orderkeys.typeCode() != NT_HASH) {
            throw "ORDER-KEYS-ARG-ERROR", sprintf("expecting \"orderkeys\" argument giving the order keys to set for "
                "order %d; must be a non-empty hash; got type %y instead (value: %y)", wf.workflow_instanceid,
                ah.orderkeys.type(), ah.orderkeys);
        }
        on_error if ($1.err == "ORDER-KEYS-ERROR" || $1.err == "INVALID-WORKFLOW-KEY") {
            rethrow "ORDER-KEYS-ARG-ERROR", sprintf("%s: %s", $1.err, $1.desc);
        }
        return RestHandler::makeResponse(200, SM.setOrderKeysExtern(cx, wf.workflow_instanceid, ah."orderkeys",
            parse_boolean(ah.truncate), wf.workflowid, wf."keys" ?? {}));
    }
}

/** @REST /workflows/{id_or_name}/orders/{id} (/orders/{id})

    This REST URI path provides actions and information about a particular workflow order of a given workflow type
*/

/** @REST /workflows/{id_or_name}/orders

    This REST URI path provides actions and information about workflow orders for the current workflow.
*/
class WorkflowOrderRestClass inherits QorusRestClass {
    private {
        hash<auto> wf;
    }

    constructor(hash<auto> v_wf) {
        #log(LoggerLevel::DEBUG, "WorkflowOrderRestClass::constructor() wf: %y", v_wf);
        wf = v_wf;
    }

    string name() {
        return wf.name;
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = sysinfo.getWFIAllInfo(id, NOTHING, False);
        if (h) {
            if (h.InstanceInfo.workflowid != wf.workflowid) {
                throw "WORKFLOW-ORDER-ERROR", sprintf("order %d is not an order for workflow %s v%s (%d); it belongs "
                    "to %s v%s (%d) instead", id, wf.name, wf.version, wf.workflowid, h.InstanceInfo.name,
                    h.InstanceInfo.version, h.InstanceInfo.workflowid);
            }
            return new WorkflowOrderInstanceRestClass(h);
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(id))
                return new AttributeRestClass(wf{id});
        }
    }

    /** @REST GET action=processingSummary

        @par Description
        Returns information about workflow processing for the current workflow.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c mindate: (required) minimum date
        - \c maxdate: maximum date
        - \c seconds: if @ref True "True" then the performance values will be returned as arbitrary-precision numeric values representing seconds, otherwise they will be returned as @ref relative_dates "relative date/time values"
        - \c global: if @ref True "True" then all workflows will be combined into an overall processing report, if @ref False "False" then each workflow gets a separate line in the output
        - grouping: (optional) possible values for reporting performance statistics:
          - \c "hourly": hourly grouping
          - \c "daily": daily grouping
          - \c "monthly": monthly grouping
          - \c "yearly": yearly grouping

        @par Return Value
        This API returns a list of hashes with the following keys for all data matched according to the search arguments:
        - \c workflowid: the workflow ID
        - \c name: the workflow name
        - \c version: the workflow version
        - \c count: the number of workflow orders in the period
        - \c minstarted: the minimum workflow order start date
        - \c maxcompleted: the maximum workflow order completion date (if any)
        - \c minduration: the minimum total elapsed order processing time for workflow orders in the period (starting from workflow order creation)
        - \c avgduration: the average total elapsed order processing time for workflow orders in the period (starting from workflow order creation)
        - \c maxduration: the maximum total elapsed order processing time for workflow orders in the period (starting from workflow order creation)
        - \c minprocessing: the minimum order processing time for workflow orders in the period (starting from when then order was first processed)
        - \c avgprocessing: the average order processing time for workflow orders in the period (starting from when then order was first processed)
        - \c maxprocessing: the maximum order processing time for workflow orders in the period (starting from when then order was first processed)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c ARGUMENT-ERROR: missing \c mindate
    */
    hash<auto> getProcessingSummary(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, GlobalOrderRestClass::processingSummary(cx, ah + ("wfids": wf.workflowid)));
    }

    /** @REST GET action=overview

        @par Description
        Returns aggregate order status information for the current workflow.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c date: optional (parsed as a date); the past cutoff date for the search; only orders with a \c modified date equal or after this date will be considered; if not present, then defaults to the last 24 hours
        - \c sqlcache: optional (parsed with @ref Qore::parse_boolean()); if @ref False then no SQL cache will be used for historical info; default @ref True

        @par Return Value
        This API returns a hash keyed by order status (see @ref StatusDescriptions for possible values) where the values are order counts for the time period in question.  One additional hash key is also provided as follows:
        - \c TOTAL: the total number of orders matched
    */
    hash<auto> getOverview(hash<auto> cx, *hash<auto> ah) {
        ah.date = ah.date ? date(ah.date) : now() - 1D;
        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;
        *hash<auto> h = sysinfo.getWorkflowOverview(ah.date, wf.workflowid, ah.sqlcache);
        h = h ? h.firstValue().firstValue() - "workflowid" : {};

        return RestHandler::makeResponse(200, h);
    }

    /** @REST GET action=listErrors

        @par Description
        Returns information about workflow order errors corresponding to the search arguments for the current workflow

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c orderby: one or more field names for sorting the output
        - \c error: the error text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c description: the description text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c info: the info text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given
        - \c stepid: limit the search to one or more stepids
        - \c severity: limit the search to one or more severity values
        - \c name: limit the search to one or more step names
        - \c version: limit the search to one or more step versions
        - \c retry: limit the search to errors with or without the retry flag
        - \c business_error: limit the search to errors with or without the business_error flag
        - \c workflow_instanceid:  limit the search to one or more workflow_instanceids
        - \c error_instanceid: mit the search to one or more error_instanceids
        - \c mindate: give the lower date range for the error search
        - \c maxdate: give the upper date range for the error search
        - \c workflowid: limit the search to one or more workflowids
        - \c workflowstatus: limit the search to workflow instances with the given status value(s) (see @ref StatusDescriptions for possible values)
        - \c limit: the maximum number of errors to return
        - \c offset: the starting error to return (use when paging for example)

        @par Return Value
        This API returns a list of hashes with the following keys for all data matched according to the search arguments:
        - \c name: the name of the workflow
        - \c version: the version of the workflow
        - \c workflow_instanceid: the workflow instance ID
        - \c workflowid: the workflow ID
        - \c stepid: the step ID where the error occurred
        - \c stepname: the name of the step where the error occurred
        - \c stepversion: the version of the step where the error occurred
        - \c ind: the array step index number where the error occurred
        - \c workflowstatus: current status of the workflow order (see @ref StatusDescriptions for possible values)
        - \c started: the date and time when the workflow order started processing
        - \c completed: the date and time when the workflow order was completed
        - \c parent_workflow_instanceid: any parent workflow instance ID
        - \c custom_status: the custom status of the workflow order, if any
        - \c priority: the priority of the workflow order
        - \c scheduled: any scheduled date for the workflow order
        - \c error_instanceid: the error instance ID
        - \c error: the error code string
        - \c description: a description for the error (if any)
        - \c info: additional information about the error (if any)
        - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
        - \c created: the date and time the error was raised
        - \c retry: the retry count of the error
        - \c business_error: a boolean flag indicating of the error is a business error
        - \c custom_status_desc: a descriptive string for the custom status (if any)
    */
    hash<auto> getListErrors(hash<auto> cx, *hash<auto> ah) {
        # issue 1879 handle list arguments
        if (ah.error =~ /,/)
            ah.error = ah.error.split(",");
        if (ah.stepid =~ /,/)
            ah.stepid = ah.stepid.split(",");
        if (ah.name =~ /,/)
            ah.name = ah.name.split(",");
        if (ah.error_instanceid =~ /,/)
            ah.error_instanceid = ah.error_instanceid.split(",");
        if (ah.workflow_instanceid =~ /,/)
            ah.workflow_instanceid = ah.workflow_instanceid.split(",");
        if (ah.workflowstatus =~ /,/)
            ah.workflowstatus = ah.workflowstatus.split(",");

        *list l = sysinfo.searchWorkflowErrors(ah + ("workflowid": wf.workflowid));
        return RestHandler::makeResponse(200, l);
    }

    list workflowInstances(*hash<auto> ah) {
        list l = sysinfo.searchWorkflowInstances(ah + ("workflowid": wf.workflowid));
        foreach hash<auto> h in (\l) {
            h.actions = WorkflowOrderInstanceRestClass::staticGetActions(h.workflowstatus);
        }
        return l;
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
        - \c custom_status: a custom status for the order
        - \c priority: the priority of the workflow order
        - \c scheduled: the future scheduled date of the workflow order (if any)
        - \c custom_status_desc: a description for the custom status (if any)
        - \c actions: a list of possible actions on the workflow
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        # rename args
        if (ah.date && !ah.modified)
            ah.modified = remove ah.date;
        if (ah.ids && !ah.workflow_instanceid)
            ah.workflow_instanceid = remove ah.ids;
        if (ah.statuses && !ah.status)
            ah.status = remove ah.statuses;

        #log(LoggerLevel::DEBUG, "orders get: ah: %y", ah);
        return RestHandler::makeResponse(200, workflowInstances(ah));
    }
}

/** @REST /workflows/{id_or_name}

    This REST URI path provides actions and information about a particular workflow.
*/
class WorkflowDefinitionRestClass inherits QorusRestClass {
    private {
        hash<auto> wf;
    }

    constructor(hash<auto> v_wf) {
        wf = v_wf;
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        #olog(LoggerLevel::DEBUG, "WorkflowDefinitionRestClass::subClassImpl() name: %y", name);
        switch (name) {
            case "instances": return new WorkflowInstanceRestClass(cx, wf);
            case "orders": return new WorkflowOrderRestClass(wf);
            case "errors": return new WorkflowSpecificErrorsRestClass(wf.workflowid);
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (wf.hasKey(name))
                return new AttributeRestClass(wf{name});
        }
    }

    string name() {
        return wf.name + ":" + wf.version;
    }

    /** @REST GET action=listErrors

        @par Description
        Returns information about workflow order errors corresponding to the search arguments for the current workflow

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c orderby: one or more field names for sorting the output
        - \c error: the error text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c description: the description text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c info: the info text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given
        - \c stepid: limit the search to one or more stepids
        - \c severity: limit the search to one or more severity values
        - \c name: limit the search to one or more step names
        - \c version: limit the search to one or more step versions
        - \c retry: limit the search to errors with or without the retry flag
        - \c business_error: limit the search to errors with or without the business_error flag
        - \c workflow_instanceid:  limit the search to one or more workflow_instanceids
        - \c error_instanceid: mit the search to one or more error_instanceids
        - \c mindate: give the lower date range for the error search
        - \c maxdate: give the upper date range for the error search
        - \c workflowstatus: limit the search to workflow instances with the given status value(s)
        - \c limit: the maximum number of errors to return
        - \c offset: the starting error to return (use when paging for example)

        @par Return Value
        This API returns a list of hashes with the following keys for all data matched according to the search arguments:
        - \c name: the name of the workflow
        - \c version: the version of the workflow
        - \c workflow_instanceid: the workflow instance ID
        - \c workflowid: the workflow ID
        - \c stepid: the step ID where the error occurred
        - \c stepname: the name of the step where the error occurred
        - \c stepversion: the version of the step where the error occurred
        - \c ind: the array step index number where the error occurred
        - \c workflowstatus: current status of the workflow (see @ref StatusDescriptions for possible values)
        - \c started: the date and time when the workflow order started processing
        - \c completed: the date and time when the workflow order was completed
        - \c parent_workflow_instanceid: any parent workflow instance ID
        - \c custom_status: the custom status of the workflow order, if any
        - \c priority: the priority of the workflow order
        - \c scheduled: any scheduled date for the workflow order
        - \c error_instanceid: the error instance ID
        - \c error: the error code string
        - \c description: a description for the error (if any)
        - \c info: additional information about the error (if any)
        - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
        - \c created: the date and time the error was raised
        - \c retry: the retry count of the error
        - \c business_error: a boolean flag indicating of the error is a business error
        - \c custom_status_desc: a descriptive string for the custom status (if any)
    */
    hash<auto> getListErrors(hash<auto> cx, *hash<auto> ah) {
        # issue 1879 handle list arguments
        if (ah.error =~ /,/)
            ah.error = ah.error.split(",");
        if (ah.stepid =~ /,/)
            ah.stepid = ah.stepid.split(",");
        if (ah.name =~ /,/)
            ah.name = ah.name.split(",");
        if (ah.error_instanceid =~ /,/)
            ah.error_instanceid = ah.error_instanceid.split(",");
        if (ah.workflow_instanceid =~ /,/)
            ah.workflow_instanceid = ah.workflow_instanceid.split(",");
        if (ah.workflowstatus =~ /,/)
            ah.workflowstatus = ah.workflowstatus.split(",");

        *list l = sysinfo.searchWorkflowErrors(ah + ("workflowid": wf.workflowid));
        return RestHandler::makeResponse(200, l);
    }

    /** @REST POST action=createOrder

        @par Description
        Creates a workflow order data instance for the current workflow with the data passed as arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - [\c staticdata]: the static data for the order; either this key or \c external_order_instanceid is required
        - [\c external_order_instanceid]: the external order instance ID for the workflow data; either this key or \c staticdata is required
        - [\c dynamicdata]: the initial dynamic data for the order
        - [\c orderkeys]: a hash of order keys for the order
        - [\c scheduled]: the earliest date and time the order can be processed; if this date is given as a future date/time value and a @ref OMQ::StatReady status is given, then the initial status of the workflow order data instance will be automatically changed to @ref OMQ::StatScheduled instead of @ref OMQ::StatReady
        - [\c priority]: the order priority (default @ref OMQ::DefaultOrderPriority) from 0 - 999; priority 0 is the highest; 999 is the lowest
        - [\c status]: the initial order status (default @ref OMQ::StatReady); must be either @ref OMQ::StatReady or @ref OMQ::StatBlocked
        - [\c parent_workflow_instanceid]: a loosely-coupled workflow that will be marked as the parent of this workflow

        @par Return Value
        a hash with the following key:
        - \c workflow_instanceid the workflow instance ID of the workflow order instance ID created

        @see omq.system.create-order()
     */
    hash<auto> postCreateOrder(hash<auto> cx, *hash<auto> ah) {
        if (ah.status) {
            ah.status = ah.status.upr();
        }

        # workflow access is checked in Orders::submitData()
        softstring rv = orders.submitData(cx, wf.name, wf.version, ah.OrderData::DataKeysV1, ah.status);
        olog(LoggerLevel::INFO, "order %s/%s from %s: created workflow instance %d with status %y", wf.name, wf.version,
            cx."peer-info".address_desc ?? ServiceApi::getCallContextString(cx), rv, ah.status ?? OMQ::StatReady);

        return RestHandler::makeResponse(201, {"workflow_instanceid": rv});
    }

    /** @REST POST action=execSynchronous

        @par Description
        Creates a new order for the current workflow and executes it synchronous mode.  The call will normally return only after the workflow order reaches a @ref OMQ::StatComplete or @ref OMQ::StatError state, unless the system or the workflow order data instance are manually stopped while the workflow order data instance is being processed, in which case other statuses can be returned.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - [\c staticdata]: the static data for the order; either this key or \c external_order_instanceid is required
        - [\c external_order_instanceid]: the external order instance ID for the workflow data; either this key or \c staticdata is required
        - [\c dynamicdata]: the initial dynamic data for the order
        - [\c orderkeys]: a hash of order keys for the order
        - [\c priority]: the order priority (default @ref OMQ::DefaultOrderPriority) from 0 - 999; priority 0 is the highest; 999 is the lowest
        - [\c parent_workflow_instanceid]: a loosely-coupled workflow that will be marked as the parent of this workflow
        - [\c options]: (hash) an optional hash of option names and values; if any options are not valid for the workflow, then an exception is raised and the synchronous workflow execution instance is not started

        @par Return Value
        This API returns a hash with the following keys:
        - \c workflow_instanceid: the workflow instance ID of the order
        - \c status: the status of the workflow
        - \c dynamicdata: the dynamic data of the workflow order instance

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SHUTDOWN-IN-PROGRESS: cannot start new workflows because the system is shutting down

        @see
        - omq.system.exec-synchronous-workflow()
        - omq.system.exec-synchronous-existing()
    */
    hash<auto> postExecSynchronous(hash<auto> cx, *hash<auto> ah) {
        if (ah.options && ah.options.typeCode() != NT_HASH) {
            throw "PARAMETER-ERROR", sprintf("workflow options must be given in hash format (option=value), type given: %y", ah.options.type());
        }

        hash<auto> oh = ah.OrderData::DataKeysV1 + ("name": wf.name, "version": wf.version);

        if (oh.priority < 0) {
            oh.priority = 0;
        } else if (oh.priority > 999) {
            oh.priority = 999;
        }

        OrderData order(oh.("staticdata", "dynamicdata", "priority", "orderkeys",
                            "external_order_instanceid", "parent_workflow_instanceid"));

        # set workflow name and version in order data
        order.setNameAndVersion(wf.name, wf.version);

        # workflow access is checked in Control::setupWorkflow()
        return RestHandler::makeResponse(201, Qorus.control.execSynchronousWorkflow(cx, wf.workflowid, order, ah.options));
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
        - \c exec: a list of @ref rest_execution_instance_hash "execution instance hashes" running for this workflow

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
        return RestHandler::makeResponse(200, wf + ("name": wf.name, "version": wf.version, "ids": ids, "exec": WorkflowInstanceRestClass::staticGetExecList(cx, wf.workflowid, wf.name, wf.version, 1)));
    }

    /** @REST PUT action=stop

        @par Description
        Manually stops all execution instances for the current workflow.

        @par Return Value
        This API returns \c "OK" upon successful execution

        @deprecated Workflow execution instances should not be manually stopped; they should be disabled instead; use @ref rest_api_PUT_workflows_enable and @ref rest_api_PUT_workflows_disable instead of starting and stopping workflow execution instances
    */
    hash<auto> putStop(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);
        try {
            api."omq.system.stop-workflow"(wf.name, wf.version);
        } catch (hash<ExceptionInfo> ex) {
        }
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=enable

        @SCHEMA
        @summary Enables the current workflow if it is disabled

        @desc Enables the current workflow if it is disabled; if the workflow is already enabled, the action is \
        reported as successful anyway

        @return (hash WorkflowUpdateResultInfo): information about the result of the operation
        - workflowid (int): the workflow ID
        - name (string): the workflow name
        - version (string): the workflow version
        - info (string): a string providing information about the workflow update action

        @error (409): exception processing the request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SHUTDOWN-IN-PROGRESS: disabled workflows cannot be enabled while the system
          is shutting down
     */
    hash<auto> putEnable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        Qorus.rbac.enableSyntheticGroup("workflow", wf.workflowid);
        hash<auto> h = wf.("name", "version", "workflowid") + (
            "info": sprintf("enabled workflow %s v%s (%d)", wf.name, wf.version, wf.workflowid),
        );
        return RestHandler::makeResponse(200, h);
    }

    /** @REST PUT action=disable

        @SCHEMA
        @summary Disables the current workflow if it is enabled

        @desc Disables the current workflow if it is enabled; if the workflow is already disabled, the action is \
        reported as successful anyway

        @return (hash WorkflowUpdateResultInfo): information about the result of the operation
        - workflowid (int): the workflow ID
        - name (string): the workflow name
        - version (string): the workflow version
        - info (string): a string providing information about the workflow update action
        @ENDSCHEMA
     */
    hash<auto> putDisable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        # issue #3358: do not return until the interface has been disabled
        Qorus.rbac.disableSyntheticGroupWait("workflow", wf.workflowid);
        hash<auto> h = wf.("name", "version", "workflowid") + {
            "info": sprintf("disabled workflow %s v%s (%d)", wf.name, wf.version, wf.workflowid),
        };
        return RestHandler::makeResponse(200, h);
    }

    /** @REST PUT action=setDeprecated

        @par Description
        Sets or removes the deprecated flag on the current workflow.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c deprecated: (required) a value (processed with @ref Qore::parse_boolean()) indicating whether or not the workflow should have its deprecated flag set (@ref True) or removed (@ref False)

        @par Return Value
        This API returns a hash with the following keys:
        - \c updated: @ref True or @ref False
        - \c stopped: a hash keyed by workflow description where the values are the lists of all execution instance IDs stopped for that workflow
        - \c info: info about the workflow update action

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETDEPRECATED-ERROR: missing \c deprecated argument
        - <tt><b>409 Conflict</b></tt>: \c SHUTDOWN-IN-PROGRESS: disabled workflows cannot be enabled while the system is shutting down

        @note
        - workflows set to deprecated are immediately stopped; workflows no longer deprecated are immediately started if their autostart value is greater than zero
     */
    hash<auto> putSetDeprecated(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.deprecated)
            throw "WORKFLOW-SETDEPRECATED-ERROR", "missing \"deprecated\" argument to update workflow";

        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        ah.deprecated = parse_boolean(ah.deprecated);

        bool updated;
        string info = sprintf("%s v%s (%d) ", wf.name, wf.version, wf.workflowid);
        hash<auto> sh;
        if (wf.deprecated != ah.deprecated) {
            sqlif.updateWorkflowDeprecated(wf.workflowid, ah.deprecated);
            Qorus.qmm.setWorkflowDeprecated(wf.workflowid, ah.deprecated);
            if (ah.deprecated) {
                # issue #2467: ensure that workflow start and stop operations are serialized
                AtomicWorkflowActionHelper atomic_helper(wf.workflowid);

                # stop any running workflow execution instances set as deprecated
                Qorus.control.stopWorkflowId(cx, wf.workflowid, \sh, NOTHING, True);

                # clear any alerts related to deprecated workflows
                Qorus.alerts.clearAllOngoingAlerts("WORKFLOW", wf.workflowid);
            }

            updated = True;
            info += sprintf("was updated with deprecated = %y", ah.deprecated);
        } else {
            updated = False;
            info += sprintf("was not updated because deprecated already was %y", ah.deprecated);
        }

        hash<auto> rv = (
            "updated": updated,
            "info": info,
            "stopped": sh,
            );

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=setAutostart

        @SCHEMA
        @summary Sets the autostart attribute for the current workflow

        @desc Sets the autostart attribute for the current workflow which specifies the targeted numbe of workflow \
        execution instances to be running for the workflow at one time.  If the new autostart value is higher than \
        current one, and the workflow is eligible to be started, then new workflow execution instances will be \
        started automatically, while reducing a workflow's autostart value will result in workflow execution \
        instances being stopped immediately.

        @params
        - autostart (int): the new autostart value for the workflow

        @return (hash WorkflowSetAutostartResultInfo): information about the result of the operation
        - updated (bool): a flag indicating if a change was actually made or not
        - autostart (int): the new autostart value
        - info (string): a string providing information about the workflow update action
        - started (int): if positive, then it is the number of execution instances started; if negative, it is the \
          number of execution instances stopped

        @error (409): exception processing the request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETAUTOSTART-ERROR: missing \c autostart argument; \c autostart
          value is negative; cannot set a positive autostart value on a workflow with the deprecated flag set
     */
    hash<auto> putSetAutostart(hash<auto> cx, *hash<auto> ah) {
        string info = sprintf("%s v%s (%d)", wf.name, wf.version, wf.workflowid);

        if (!exists ah.autostart)
            throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("missing \"autostart\" argument to update workflow %s", info);

        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        ah.autostart = int(ah.autostart);

        if (ah.autostart < 0)
            throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("invalid \"autostart\" argument %y to update workflow %s", ah.autostart, info);

        if (wf.deprecated && ah.autostart)
            throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("cannot set autostart status on workflow %s with the deprecated (hidden) flag set", info);

        bool updated;
        int count = 0;
        string errstr;
        if (wf.autostart != ah.autostart) {
            sqlif.updateWorkflowAutostart(wf.workflowid, ah.autostart);
            Qorus.qmm.setWorkflowAutostart(wf.workflowid, ah.autostart);

            updated = True;
            info += sprintf(" was updated with autostart = %y", ah.autostart);
            # adjusting running workflow exec instances
            hash<auto> h;
            count = Qorus.control.autoStartWorkflow(cx,
                        wf + ("autostart": ah.autostart),
                        \h,
                        "autostarting workflow",
                        \errstr);
        } else {
            updated = False;
            info += sprintf(" was not updated because autostart already was %y", ah.autostart);
        }

        hash<auto> rv = {
            "updated": updated,
            "autostart": ah.autostart,
            "info": errstr ? sprintf("%s, finished with errors: %s", info, errstr) : info,
            "started": count,
        };

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=incAutostart

        @SCHEMA
        @summary Increments the autostart value for the current workflow

        @desc Increments the autostart value for the current workflow; if the workflow is eligible to be started, an \
        additional workflow execution instance is started immediately

        @return (hash WorkflowSetAutostartResultInfo): information about the result of the operation
        - updated (bool): a flag indicating if a change was actually made or not
        - autostart (int): the new autostart value
        - info (string): a string providing information about the workflow update action
        - started (int): if positive, then it is the number of execution instances started

        @error (409): exception processing the request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETAUTOSTART-ERROR: cannot set a positive autostart value on a
          workflow with the deprecated flag set
     */
    hash<auto> putIncAutostart(hash<auto> cx, *hash<auto> ah) {
        string info = sprintf("%s v%s (%d)", wf.name, wf.version, wf.workflowid);

        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        if (wf.deprecated)
            throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("cannot set autostart status on workflow %s with the deprecated (hidden) flag set", info);

        bool updated;
        int count = 0;
        ++wf.autostart;
        # FIXME if any of updateWorkflowAutostart, setWorkflowAutostart or
        # autoStartWorkflow fails, the rest of the info
        # (sqlif, qmm, real running instances) will be out of sync and NOBODY KNOWS!
        # --PQ 15-Aug-2016
        sqlif.updateWorkflowAutostart(wf.workflowid, wf.autostart);
        Qorus.qmm.setWorkflowAutostart(wf.workflowid, wf.autostart);

        updated = True;
        info += sprintf(" was updated with autostart = %y", wf.autostart);
        # adjusting running workflow exec instances
        hash<auto> h;
        string errstr;
        count = Qorus.control.autoStartWorkflow(cx,
                    wf + ("autostart": wf.autostart),
                    \h,
                    "autostarting workflow",
                    \errstr);

        hash<auto> rv = (
            "updated": updated,
            "autostart": wf.autostart,
            "info": errstr ? sprintf("%s, finished with errors: %s", info, errstr) : info,
            "started": count,
            );

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=decAutostart

        @SCHEMA
        @summary Decrements the autostart value for the current workflow

        @desc Decrements the autostart value for the current workflow; if the workflow is running, a running \
        workflow execution instance is stopped immediately

        @return (hash WorkflowSetAutostartResultInfo): information about the result of the operation
        - updated (bool): a flag indicating if a change was actually made or not
        - autostart (int): the new autostart value
        - info (string): a string providing information about the workflow update action
        - started (int): if negative, then it is the number of execution instances stopped

        @error (409): exception processing the request
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETAUTOSTART-ERROR: autostart value cannot be negative; cannot
          change the autostart value on a workflow with the deprecated flag set
     */
      hash<auto> putDecAutostart(hash<auto> cx, *hash<auto> ah) {
        string info = sprintf("%s v%s (%d)", wf.name, wf.version, wf.workflowid);

        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        if (wf.deprecated)
            throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("cannot decrement autostart status on workflow %s with the deprecated (hidden) flag set", info);
        if (!wf.autostart)
            throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("cannot decrement autostart status on workflow %s because it is already at zero", info);

        bool updated;
        int count = 0;
        --wf.autostart;
        sqlif.updateWorkflowAutostart(wf.workflowid, wf.autostart);
        Qorus.qmm.setWorkflowAutostart(wf.workflowid, wf.autostart);

        updated = True;
        info += sprintf(" was updated with autostart = %y", wf.autostart);
        # adjusting running workflow exec instances
        hash<auto> h;
        string errstr;
        count = Qorus.control.autoStartWorkflow(cx,
                    wf + ("autostart": wf.autostart),
                    \h,
                    "autostarting workflow",
                    \errstr);

        hash<auto> rv = {
            "updated": updated,
            "autostart": wf.autostart,
            "info": errstr ? sprintf("%s, finished with errors: %s", info, errstr) : info,
            "stopped": -count,
        };

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=reset

        @SCHEMA
        @summary Resets and reloads the current workflow

        @desc Resets and reloads the current workflow by reloading the configuration for the current workflow in the \
        metadata cache; if there are any running execution instances, then the reset will cause the workflow \
        configuration to be reset on their next iteration.

        @return (string): the value \c "OK"
        @ENDSCHEMA
     */
    hash<auto> putReset(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        # workflow access is checked in Control::deleteWorkflowCacheEntry()
        Qorus.control.deleteWorkflowCacheEntry(cx, Qorus.qmm.getWorkflowId(wf.name, wf.version));
        return RestHandler::makeResponse(200, sprintf("workflow %s/%s has been deleted from the cache", wf.name,
            wf.version));
    }

    /** @REST PUT action=setOptions

        @par Description
        Sets workflow options for the current workflow.  If the workflow has an option list and any of the options are not valid for that workflow, an exception will be thrown, however, even if an exception is thrown due to an option error, all other options will still be set.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c options: a hash of options to set against the workflow; if the value of this key is a string, then it is first parsed with @ref Util::parse_to_qore_value(), which should then return a hash

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing \c "options" argument or \c "options" is not a hash (or string parsed to a hash with @ref Util::parse_to_qore_value())
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-OPTION-ERROR: invalid option for workflow or option cannot be overridden at the workflow level

        @note
        - workflow options are persistent (persistent workflow options were implemented in Qorus 3.0.0)
    */
    hash<auto> putSetOptions(hash<auto> cx, *hash<auto> ah) {
        if (ah.options.typeCode() == NT_STRING) {
            ah.options = parse_to_qore_value(ah.options);
        }
        if (!ah.options) {
            return RestHandler::make400("error setting options on workflow %s v%s (%d): missing 'options' hash in "
                "message body", wf.name, wf.version, wf.workflowid);
        }
        if (ah.options.typeCode() != NT_HASH) {
            return RestHandler::make400("error setting options on workflow %s v%s (%d): 'options' argument is not a "
                "hash; got type %y instead", wf.name, wf.version, wf.workflowid, ah.options.type());
        }

        rlog(cx, "(%s v%s (%d))", wf.name, wf.version, wf.workflowid);

        # workflow access is checked in Control::setWorkflowOption()
        Qorus.control.setWorkflowOption(cx, wf.workflowid, ah.options);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST GET action=options

        @par Description
        Returns options set on the current workflow.

        @par Return Value
        This API returns @ref nothing if no options are set, otherwise a hash of workflow options.
    */
    hash<auto> getOptions(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, wf."runtime-options");
    }

    /** @REST GET

        @par Description
        Returns a @ref rest_workflow_description_hash for the current workflow

        @par Return Value
        This API returns a @ref rest_workflow_description_hash for the current workflow
     */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        return RestHandler::makeResponse(200, wf - ("remote", "process"));
    }
}

/** @REST /workflows

    This URI path allows workflows to be queried and for actions on multiple workflows to be performed;
    this is the URI path parent of workflow-specific actions as well.
*/
class WorkflowRestClass inherits QorusRestClass {
    string name() {
        return "workflows";
    }

    private static *hash<auto> staticGetWorkflowFromCache(hash<auto> cx, softint id, *softdate date, bool sqlcache,
        bool all_source, int apiver) {
        try {
            hash<auto> h = Qorus.qmm.lookupWorkflow(id, True);
            # get order data summary
            *hash<auto> oview = sysinfo.getWorkflowOverview(date, id, sqlcache);
            h += oview.firstValue().firstValue() - "workflowid";
            if (apiver >= 3) {
                h.process = Qorus.qmm.getWorkflowProcess(id);
                h.order_stats = Qorus.orderStats.getCurrentEvents(id);
                foreach hash<auto> sh in (\h.stepinfo) {
                    Qorus.qmm.fillConfigItemValues("step", sh.stepid, \sh, h.workflowid);
                    h.config += remove sh.workflow_config;
                    h.global_config += remove sh.global_config;
                }
            } else {
                h -= ("sla_threshold", "manual_sla_threshold");
            }
            *list<auto> el = WorkflowInstanceRestClass::staticGetExecList(cx, id, h.name, h.version, apiver);
            h += {
                "exec": el,
                "exec_count": el.size(),
                "connections": Qorus.connDeps.getConnections("WORKFLOW", id),
                "groups": Qorus.rbac.getWorkflowGroups(id),
                "alerts": Qorus.alerts.getAlerts("WORKFLOW", id),
                "enabled": Qorus.rbac.getSyntheticGroupStatus("workflow", id),
            };

            if (all_source) {
                h.lib = get_library_source(h.lib);

                # for required classes - to be added to lib.classes directly;
                hash<string, bool> class_hash;

                # for classes we already have; classid -> True
                hash<string, bool> cached_class_hash;

                if (apiver >= 3) {
                    foreach hash class_info in (\h.lib.classes) {
                        if (class_info.requires) {
                            map class_hash{$1} = True, class_info.requires;
                        }
                        cached_class_hash{class_info.classid} = True;
                    }

                    # remove classes we already have
                    if (class_hash) {
                        class_hash -= (keys cached_class_hash);
                    }
                }

                foreach hash<auto> sh in (\h.stepinfo) {
                    if (sh.stepfunction_instanceid) {
                        sh.functions = ();
                        # add function info
                        map sh.functions += StepDefinitionRestClass::staticGetFunctionInfo($1.key, sh.($1.value)),
                            StepDefinitionRestClass::StepFunctions.pairIterator(), sh.($1.value);
                    } else if (apiver >= 3) {
                        if (sh.step_sourceid) {
                            sh."class" = ClassRestClass::staticGetClassInfo(sh.step_sourceid, apiver);
                            if (sh."class".requires) {
                                # add all required classes that we don't already have
                                map class_hash{$1} = True, sh."class".requires, !cached_class_hash{$1};
                            }
                        }
                    }
                }

                if (apiver >= 3) {
                    *hash<string, bool> new_class_hash = class_hash;
                    # get other required classes & class info for the response
                    while (new_class_hash) {
                        *hash<string, bool> even_newer_class_hash;

                        # see if the required classes have any required classes themselves
                        foreach string classid in (keys new_class_hash) {
                            *hash<auto> class_info = Qorus.qmm.lookupClass(classid);
                            foreach softstring new_classid in (class_info.requires) {
                                if (!cached_class_hash{new_classid} && !class_hash{new_classid}) {
                                    even_newer_class_hash{new_classid} = True;
                                }
                            }
                        }
                        if (!even_newer_class_hash) {
                            break;
                        }
                        # retrieve the new classes
                        class_hash += even_newer_class_hash;
                        new_class_hash = even_newer_class_hash;
                    }

                    if (class_hash) {
                        if (!h.lib.classes) {
                            h.lib.classes = ();
                        }
                        foreach string classid in (keys class_hash) {
                            *hash<auto> class_info = Qorus.qmm.lookupClass(classid);
                            if (class_info) {
                                class_info.classid = classid;
                                h.lib.classes += FunctionRestClass::moveTags(class_info);
                            }
                        }
                    }
                }

                foreach hash<auto> fh in (\h.wffuncs) {
                    fh += FunctionRestClass::moveTags(sysinfo.getFunctionInstance(fh.function_instanceid).firstValue().firstValue() - "function_instanceid");
                }
            }

            # reformat options in a single list of hashes with configured and runtime values
            hash<auto> opts;
            map opts.($1.key).desc = $1.value, h.options.pairIterator();
            map opts.($1.key).value = $1.value, (remove h."runtime-options").pairIterator();
            h.options = map ("name": $1) + opts.$1, keys opts;

            return h;
        } catch (hash<ExceptionInfo> ex) {
            # ignore exceptions (unknown workflow)
            Qorus.httpServer.logDebug("%s", get_exception_string(ex));
        }
    }

    static softint staticGetWorkflowId(softstring arg, bool check = False, *reference wh) {
        if (arg =~ /[[:alpha:]]/u) {
            # try to find version
            *string ver;
            if ((int i = arg.find(":")) != -1) {
                ver = extract arg, i + 1;
                splice arg, -1;
            }
            if (ver) {
                *hash<auto> h = Qorus.qmm.rLookupWorkflow(arg, ver);
                if (h) {
                    wh = h;
                    return h.workflowid;
                }
                if (check)
                    throw "WORKFLOW-ERROR", sprintf("can't find any workflow %y v%s", arg, ver);
                return 0;
            } else {
                *hash<auto> h = Qorus.qmm.rLookupWorkflow(arg);
                if (h) {
                    wh = h{h.lastversion};
                    return wh.workflowid;
                }
                if (check)
                    throw "WORKFLOW-ERROR", sprintf("can't find any workflow %y", arg);
                return 0;
            }
        }

        if (check) {
            *hash<auto> h = Qorus.qmm.lookupWorkflow(arg, False);
            if (!h)
                throw "WORKFLOW-ERROR", sprintf("there is no workflow with workflowid %d", arg);
            wh = h;
        }

        return arg;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg =~ /^order-/) {
            softint wfiid = arg.substr(6);
            *hash<auto> h = sysinfo.getWFIAllInfo(wfiid, NOTHING, False);
            if (h)
                return new WorkflowOrderInstanceRestClass(h);
            # allow a 404 Not Found error to be returned in this case
            return;
        }

        int id;
        try {
            id = WorkflowRestClass::staticGetWorkflowId(arg, True);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "WORKFLOW-ERROR") {
                # allow a 404 Not Found error to be returned
                return;
            }
            rethrow;
        }

        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;
        ah.lib_source = ah.lib_source ? parse_boolean(ah.lib_source) : False;
        ah.all_source = ah.all_source ? parse_boolean(ah.all_source) : False;
        return internGetWorkflowDefinitionSubclass(WorkflowRestClass::staticGetWorkflowFromCache(cx, id, ah.date, ah.sqlcache, ah.all_source || ah.lib_source, 1));
    }

    private *QorusRestClass internGetWorkflowDefinitionSubclass(*hash<auto> wf) {
        if (wf)
            return new WorkflowDefinitionRestClass(wf);
    }

    /** @REST GET action=listErrors

        @par Description
        Returns information about workflow order errors corresponding to the search arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c orderby: one or more field names for sorting the output
        - \c error: the error text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c description: the description text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c info: the info text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given
        - \c stepid: limit the search to one or more stepids
        - \c severity: limit the search to one or more severity values
        - \c name: limit the search to one or more step names
        - \c version: limit the search to one or more step versions
        - \c retry: limit the search to errors with or without the retry flag
        - \c business_error: limit the search to errors with or without the business_error flag
        - \c workflow_instanceid:  limit the search to one or more workflow_instanceids
        - \c error_instanceid: mit the search to one or more error_instanceids
        - \c mindate: give the lower date range for the error search
        - \c maxdate: give the upper date range for the error search
        - \c workflowid: limit the search to one or more workflowids
        - \c workflowstatus: limit the search to workflow instances with the given status value(s)
        - \c limit: the maximum number of errors to return
        - \c offset: the starting error to return (use when paging for example)

        @par Return Value
        This API returns a list of hashes with the following keys for all data matched according to the search arguments:
        - \c name: the name of the workflow
        - \c version: the version of the workflow
        - \c workflow_instanceid: the workflow instance ID
        - \c workflowid: the workflow ID
        - \c stepid: the step ID where the error occurred
        - \c stepname: the name of the step where the error occurred
        - \c stepversion: the version of the step where the error occurred
        - \c ind: the array step index number where the error occurred
        - \c workflowstatus: current status of the workflow (see @ref StatusDescriptions for possible values)
        - \c started: the date and time when the workflow order started processing
        - \c completed: the date and time when the workflow order was completed
        - \c parent_workflow_instanceid: any parent workflow instance ID
        - \c custom_status: the custom status of the workflow order, if any
        - \c priority: the priority of the workflow order
        - \c scheduled: any scheduled date for the workflow order
        - \c error_instanceid: the error instance ID
        - \c error: the error code string
        - \c description: a description for the error (if any)
        - \c info: additional information about the error (if any)
        - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
        - \c created: the date and time the error was raised
        - \c retry: the retry count of the error
        - \c business_error: a boolean flag indicating of the error is a business error
        - \c custom_status_desc: a descriptive string for the custom status (if any)
    */
    hash<auto> getListErrors(hash<auto> cx, *hash<auto> ah) {
        # issue 1879 handle list arguments
        if (ah.error =~ /,/)
            ah.error = ah.error.split(",");
        if (ah.stepid =~ /,/)
            ah.stepid = ah.stepid.split(",");
        if (ah.name =~ /,/)
            ah.name = ah.name.split(",");
        if (ah.error_instanceid =~ /,/)
            ah.error_instanceid = ah.error_instanceid.split(",");
        if (ah.workflow_instanceid =~ /,/)
            ah.workflow_instanceid = ah.workflow_instanceid.split(",");
        if (ah.workflowid =~ /,/)
            ah.workflowid = ah.workflowid.split(",");
        if (ah.workflowstatus =~ /,/)
            ah.workflowstatus = ah.workflowstatus.split(",");

        *list l = sysinfo.searchWorkflowErrors(ah);
        return RestHandler::makeResponse(200, l);
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
        If neither \a list nor \a short are used, then a list of hashes is returned, one element for each workflow; each hash in the returned list is a @ref rest_workflow_description_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        ah.deprecated = exists ah.deprecated ? parse_boolean(ah.deprecated) : True;

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.name, WorkflowRestClass::staticGetWorkflowMetadata(ah.deprecated, 1)));

        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200, (map sprintf("%s v%s (%d) autostart: %d", $1.name, $1.version, $1.workflowid, $1.autostart), WorkflowRestClass::staticGetWorkflowMetadata(ah.deprecated, 1)));

        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;

        return RestHandler::makeResponse(200, WorkflowRestClass::staticGetWorkflows(ah.date, ah.sqlcache, ah.deprecated, 1));
    }

    /** @REST GET action=processingSummary

        @par Description
        Returns information about workflow processing.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c mindate: (required) minimum date
        - \c maxdate: maximum date
        - \c wfids: optional workflow IDs
        - \c seconds: if @ref True "True" then the performance values will be returned as arbitrary-precision numeric values representing seconds, otherwise they will be returned as @ref relative_dates "relative date/time values"
        - \c global: if @ref True "True" then all workflows will be combined into an overall processing report, if @ref False "False" then each workflow gets a separate line in the output
        - grouping: (optional) possible values for reporting performance statistics:
          - \c "hourly": hourly grouping
          - \c "daily": daily grouping
          - \c "monthly": monthly grouping
          - \c "yearly": yearly grouping

        @par Return Value
        This API returns a list of hashes with the following keys for all data matched according to the search arguments:
        - \c workflowid: the workflow ID
        - \c name: the workflow name
        - \c version: the workflow version
        - \c count: the number of workflow orders in the period
        - \c minstarted: the minimum workflow order start date
        - \c maxcompleted: the maximum workflow order completion date (if any)
        - \c minduration: the minimum total elapsed order processing time for workflow orders in the period (starting from workflow order creation)
        - \c avgduration: the average total elapsed order processing time for workflow orders in the period (starting from workflow order creation)
        - \c maxduration: the maximum total elapsed order processing time for workflow orders in the period (starting from workflow order creation)
        - \c minprocessing: the minimum order processing time for workflow orders in the period (starting from when then order was first processed)
        - \c avgprocessing: the average order processing time for workflow orders in the period (starting from when then order was first processed)
        - \c maxprocessing: the maximum order processing time for workflow orders in the period (starting from when then order was first processed)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c ARGUMENT-ERROR: missing \c mindate
    */
    hash<auto> getProcessingSummary(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, GlobalOrderRestClass::processingSummary(cx, ah));
    }

    hash<auto> staticGetOrderSummary(hash<auto>  cx, *hash<auto> ah) {
        ah.date = ah.date ? date(ah.date) : now() - 1D;
        ah.deprecated = exists ah.deprecated ? parse_boolean(ah.deprecated) : True;
        return WorkflowRestClass::staticGetOrderSummary(ah.date, ah.deprecated);
    }

    /** @REST PUT action=start

        @par Description
        Manually starts one or more workflow execution instances.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow names or IDs to start; a comma-separated string will be split into a list

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c arg: the workflow ID or name
        - \c started: @ref True or @ref False
        - [\c exec_id]: the workflow execution ID (when \c started = @ref True)
        - [\c workflowid]: the workflow ID
        - [\c name]: the workflow name
        - [\c version]: the workflow version
        - \c info: info about the workflow start or a reason why the request failed

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-START-ERROR: missing \c ids argument
        - <tt><b>409 Conflict</b></tt>: \c SHUTDOWN-IN-PROGRESS: workflows cannot be started while the system is shutting down

        @deprecated Workflow execution instances should not be manually started; they should be started by the system based on their autostart values and enabled and disabled for operational reasons; use @ref rest_api_PUT_workflows_enable and @ref rest_api_PUT_workflows_disable instead of starting and stopping workflow execution instances
     */
    hash<auto> putStart(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "WORKFLOW-START-ERROR", "missing \"ids\" argument for workflow IDs to start";

        rlog(cx);

        list<hash> rv();

        if (ah.ids.typeCode() == NT_STRING) {
            ah.ids = ah.ids.split(",");
        }

        foreach auto arg in (ah.ids) {
            *hash<auto> wh;
            int id = WorkflowRestClass::staticGetWorkflowId(arg, False, \wh);
            if (!id) {
                rv += {
                    "arg": arg,
                    "started": False,
                    "info": "unknown workflow",
                };
                continue;
            }
            try {
                if (!wh) {
                    wh = Qorus.qmm.lookupWorkflow(id, False);
                    if (!wh) {
                        rv += {
                            "arg": arg,
                            "started": False,
                            "info": sprintf("WORKFLOW-ERROR: workflowid %d is unknown", id),
                        };
                        continue;
                    }
                }
                int eid = int(Qorus.control.startWorkflowSetAtomic(cx, id, OMQ::WM_Normal));
                rv += {
                    "arg": arg,
                    "started": True,
                    "exec_id": eid,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": sprintf("started %s v%s (%d) with execution ID %d", wh.name, wh.version, id, eid),
                };
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SHUTDOWN-IN-PROGRESS") {
                    rethrow;
                } else {
                    rv += {
                        "arg": arg,
                        "started": False,
                        "workflowid": id,
                        "name": wh.name,
                        "version": wh.version,
                        "info": sprintf("%s: %s", ex.err, ex.desc),
                    };
                }
            }
        }
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=stop

        @par Description
        Manually stops one or more workflow execution instances.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow names or IDs to stop; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash with the following keys:
        - \c count: number of workflow execution instances stopped
        - \c workflows: a hash keyed by workflow description where the values are the lists of all execution instance IDs stopped for that workflow
        - \c details: a list of hashes providing details of the individual workflow stop actions with the following keys
          - \c arg: the workflow ID or name
          - \c stopped: @ref True or @ref False
          - [\c count]: the number of execution instances stopped
          - [\c workflowid]: the workflow ID
          - [\c name]: the workflow name
          - [\c version]: the workflow version
          - \c info: info about the workflow stop action or a reason why the request failed

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-STOP-ERROR: missing \c ids argument

        @deprecated Workflow execution instances should not be manually stopped; they should be disabled instead; use @ref rest_api_PUT_workflows_enable and @ref rest_api_PUT_workflows_disable instead of starting and stopping workflow execution instances
     */
    hash<auto> putStop(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "WORKFLOW-STOP-ERROR", "missing \"ids\" argument for workflow IDs to stop";

        rlog(cx);

        list<hash<auto>> rv();

        if (ah.ids.typeCode() == NT_STRING) {
            ah.ids = ah.ids.split(",");
        }

        int tcount = 0;
        hash<auto> h;
        foreach auto arg in (ah.ids) {
            *hash<auto> wh;
            int id = WorkflowRestClass::staticGetWorkflowId(arg, False, \wh);
            if (!id) {
                rv += {
                    "arg": arg,
                    "stopped": False,
                    "info": "unknown workflow",
                };
                continue;
            }
            try {
                if (!wh) {
                    wh = Qorus.qmm.lookupWorkflow(id, False);
                    if (!wh) {
                        rv += {
                            "arg": arg,
                            "stopped": False,
                            "info": sprintf("WORKFLOW-ERROR: workflowid %d is unknown", id),
                        };
                        continue;
                    }
                }
                # issue #2467: ensure that workflow start and stop operations are serialized
                AtomicWorkflowActionHelper atomic_helper(id);

                int count = Qorus.control.stopWorkflowId(cx, id, \h);
                tcount += count;
                rv += {
                    "arg": arg,
                    "count": count,
                    "stopped": boolean(count),
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": sprintf("stopped %d instance%s of %s v%s (%d)", count, count == 1 ? "" : "s", wh.name, wh.version, id),
                };
            } catch (hash<ExceptionInfo> ex) {
                rv += {
                    "arg": arg,
                    "stopped": False,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                };
            }
        }

        hash<auto> rvh = {
            "count": tcount,
            "workflows": h,
            "details": rv,
        };
        return RestHandler::makeResponse(200, rvh);
    }

    /** @REST PUT action=enable

        @par Description
        Enables one or more disabled workflows.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow names or IDs to enable; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash with the following keys:
        - \c arg: the workflow ID or name
        - \c enabled: @ref True or @ref False
        - [\c workflowid]: the workflow ID
        - [\c name]: the workflow name
        - [\c version]: the workflow version
        - \c info: info about the workflow enable action or a reason why the request failed

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-ENABLE-ERROR: missing \c ids argument
        - <tt><b>409 Conflict</b></tt>: \c SHUTDOWN-IN-PROGRESS: disabled workflows cannot be enabled while the system is shutting down
     */
    hash<auto> putEnable(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "WORKFLOW-ENABLE-ERROR", "missing \"ids\" argument for workflow IDs to enable";

        rlog(cx);

        list rv = ();

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        foreach any arg in (ah.ids) {
            *hash<auto> wh;
            int id;
            try {
                id = WorkflowRestClass::staticGetWorkflowId(arg, True, \wh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "enabled": False, "info": "unknown workflow");
                continue;
            }
            try {
                Qorus.rbac.enableSyntheticGroup("workflow", id);
                rv += (
                    "arg": arg,
                    "enabled": True,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": sprintf("enabled %s v%s (%d)", wh.name, wh.version, id),
                    );
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SHUTDOWN-IN-PROGRESS") {
                    rethrow;
                } else {
                    rv += (
                        "arg": arg,
                        "enabled": False,
                        "workflowid": id,
                        "name": wh.name,
                        "version": wh.version,
                        "info": sprintf("%s: %s", ex.err, ex.desc),
                        );
                }
            }
        }
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=disable

        @par Description
        Disables one or more enabled workflows.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow names or IDs to disable; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash with the following keys:
        - \c count: number of workflow execution instances disabled
        - \c details: a list of hashes providing details of the individual workflow disable actions with the following keys
          - \c arg: the workflow ID or name
          - \c stopped: @ref True or @ref False
          - [\c count]: the number of execution instances stopped
          - [\c workflowid]: the workflow ID
          - [\c name]: the workflow name
          - [\c version]: the workflow version
          - \c info: info about the workflow disable action or a reason why the request failed

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-DISABLE-ERROR: missing \c ids argument
     */
    hash<auto> putDisable(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "WORKFLOW-DISABLE-ERROR", "missing \"ids\" argument for workflow IDs to disable";

        rlog(cx);

        list rv = ();

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        int tcount = 0;
        foreach any arg in (ah.ids) {
            *hash<auto> wh;
            int id;
            try {
                id = WorkflowRestClass::staticGetWorkflowId(arg, True, \wh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "disabled": False, "info": "unknown workflow");
                continue;
            }
            try {
                # issue #3358: do not return until the interface has been disabled
                Qorus.rbac.disableSyntheticGroupWait("workflow", id);
                ++tcount;
                rv += {
                    "arg": arg,
                    "disabled": True,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": sprintf("disabled workflow %s v%s (%d)", wh.name, wh.version, id),
                };
            } catch (hash<ExceptionInfo> ex) {
                rv += {
                    "arg": arg,
                    "disabled": False,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                };
            }
        }

        hash<auto> rvh = (
            "count": tcount,
            "details": rv,
            );
        return RestHandler::makeResponse(200, rvh);
    }

    /** @REST PUT action=resetAll

        @par Description
        Resets all cached and running workflow execution instances

        @par Return Value
        This API returns a list of hashes of affected workflows with the following keys:
        - \c name: the name of the workflow that was reset
        - \c version: the version of the workflow that was reset
        - \c workflowid: the workflow ID of the workflow that was reset
        - \c count: the number of workflow execution instances affected
     */
    hash<auto> putResetAll(hash<auto> cx, *hash<auto> ah) {
        # workflow access is checked in Control::deleteAllWorkflowCacheEntries()
        return RestHandler::makeResponse(200, Qorus.control.deleteAllWorkflowCacheEntries(cx));
    }

    # permissions must be checked externally before calling
    static hash<auto> resetWorkflows(hash<auto> cx, softlist<auto> ids) {
        list<hash<auto>> rv = ();

        int tcount = 0;
        foreach auto arg in (ids) {
            *hash<auto> wh;
            int id = WorkflowRestClass::staticGetWorkflowId(arg, False, \wh);
            if (!id) {
                rv += {
                    "arg": arg,
                    "reset": False,
                    "info": "unknown workflow",
                };
                continue;
            }
            try {
                if (!wh) {
                    wh = Qorus.qmm.lookupWorkflow(id, False);
                    if (!wh) {
                        rv += {
                            "arg": arg,
                            "reset": False,
                            "info": sprintf("WORKFLOW-ERROR: workflowid %d is unknown", id),
                        };
                        continue;
                    }
                }
                # workflow access is checked in Control::deleteWorkflowCacheEntry()
                Qorus.control.deleteWorkflowCacheEntry(cx, id);
                ++tcount;
                rv += {
                    "arg": arg,
                    "reset": True,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": sprintf("purged %s v%s (%d) from the cache", wh.name, wh.version, id),
                };
            } catch (hash<ExceptionInfo> ex) {
                rv += {
                    "arg": arg,
                    "reset": False,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                };
            }
        }

        return {
            "count": tcount,
            "details": rv,
        };
    }

    /** @REST PUT action=reset

        @par Description
        Resets one or more workflows.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow names or IDs to reset; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash with the following keys:
        - \c count: number of workflow execution instances disabled
        - \c details: a list of hashes providing details of the individual workflow reset actions with the following keys
          - \c arg: the workflow ID or name
          - \c reset: @ref True or @ref False
          - [\c workflowid]: the workflow ID
          - [\c name]: the workflow name
          - [\c version]: the workflow version
          - \c info: info about the workflow reset action or a reason why the request failed

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-RESET-ERROR: missing \c ids argument
     */
    hash<auto> putReset(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "WORKFLOW-RESET-ERROR", "missing \"ids\" argument for workflow IDs to reset";

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        return RestHandler::makeResponse(200, resetWorkflows(cx, ah.ids));
    }

    /** @REST PUT action=setDeprecated

        @par Description
        Sets or removes the deprecated flag on one or more workflows.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow names or IDs to modify; a comma-separated string will be split into a list
        - \c deprecated: (required) a value (processed with @ref Qore::parse_boolean()) indicating whether or not the workflows should have their deprecated flag set (@ref True) or removed (@ref False)

        @par Return Value
        This API returns a hash with the following keys:
        - \c arg: the workflow ID or name
        - \c updated: @ref True or @ref False
        - [\c workflowid]: the workflow ID
        - [\c name]: the workflow name
        - [\c version]: the workflow version
        - [\c stopped]: a hash keyed by workflow description where the values are the lists of all execution instance IDs stopped for that workflow
        - \c info: info about the workflow update action or a reason why the request failed

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETDEPRECATED-ERROR: missing \c ids or \c deprecated argument
        - <tt><b>409 Conflict</b></tt>: \c SHUTDOWN-IN-PROGRESS: disabled workflows cannot be enabled while the system is shutting down
     */
    hash<auto> putSetDeprecated(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "WORKFLOW-SETDEPRECATED-ERROR", "missing \"ids\" argument for workflow IDs to update";

        if (!exists ah.deprecated)
            throw "WORKFLOW-SETDEPRECATED-ERROR", "missing \"deprecated\" argument for workflow IDs to update";

        rlog(cx);

        ah.deprecated = parse_boolean(ah.deprecated);

        list rv = ();

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        foreach any arg in (ah.ids) {
            *hash<auto> wh;
            int id;
            try {
                id = WorkflowRestClass::staticGetWorkflowId(arg, True, \wh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "updated": False, "info": "unknown workflow");
                continue;
            }
            try {
                bool updated;
                string info = sprintf("%s v%s (%d)", wh.name, wh.version, wh.workflowid);
                hash<auto> sh;
                if (wh.deprecated != ah.deprecated) {
                    sqlif.updateWorkflowDeprecated(wh.workflowid, ah.deprecated);
                    Qorus.qmm.setWorkflowDeprecated(wh.workflowid, ah.deprecated);

                    if (ah.deprecated) {
                        # issue #2467: ensure that workflow start and stop operations are serialized
                        AtomicWorkflowActionHelper atomic_helper(wh.workflowid);

                        # stop any running workflow execution instances set as deprecated
                        Qorus.control.stopWorkflowId(cx, wh.workflowid, \sh, NOTHING, True);

                        # clear any alerts on deprecated workflows
                        Qorus.alerts.clearAllOngoingAlerts("WORKFLOW", wh.workflowid);
                    }

                    updated = True;
                    info += sprintf(" was updated with deprecated = %y", ah.deprecated);
                } else {
                    updated = False;
                    info += sprintf(" was not updated because deprecated already was %y", ah.deprecated);
                }

                rv += {
                    "arg": arg,
                    "updated": updated,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": info,
                    "stopped": sh,
                };
            } catch (hash<ExceptionInfo> ex) {
                rv += {
                    "arg": arg,
                    "updated": False,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                };
            }
        }
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=setAutostart

        @par Description
        Sets the autostart value on one or more workflows.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow names or IDs to modify; a comma-separated string will be split into a list
        - \c autostart: (required) an integer value giving the new autostart value for the workflow(s)

        @par Return Value
        This API returns a hash with the following keys:
        - \c arg: the workflow ID or name
        - \c updated: @ref True or @ref False
        - [\c workflowid]: the workflow ID
        - [\c name]: the workflow name
        - [\c version]: the workflow version
        - \c info: info about the workflow update action or a reason why the request failed
        - [\c started]: the number of execution instances started

        @note the autostart cannot be set over @ref wf_max_instances; in case @ref wf_max_instances is reached the autostart value is set to @ref wf_max_instances and this number is returned in \c started

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETAUTOSTART-ERROR: missing \c ids or \c autostart argument; \c autostart value is negative; cannot set a positive autostart value on a workflow with the deprecated flag set
     */
    hash<auto> putSetAutostart(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "WORKFLOW-SETAUTOSTART-ERROR", "missing \"ids\" argument for workflow IDs to update";

        if (!exists ah.autostart)
            throw "WORKFLOW-SETAUTOSTART-ERROR", "missing \"autostart\" argument for workflow IDs to update";

        rlog(cx);

        ah.autostart = int(ah.autostart);

        if (ah.autostart < 0)
            throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("invalid \"autostart\" argument %y for workflow IDs to update", ah.autostart);

        list rv = ();

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        foreach any arg in (ah.ids) {
            *hash<auto> wh;
            int id;
            try {
                id = WorkflowRestClass::staticGetWorkflowId(arg, True, \wh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "updated": False, "info": "unknown workflow");
                continue;
            }
            try {
                string info = sprintf("%s v%s (%d)", wh.name, wh.version, wh.workflowid);

                if (wh.deprecated && ah.autostart)
                    throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("cannot set autostart status on workflow %s with the deprecated (hidden) flag set", info);

                bool updated;
                int count = 0;
                string errstr;
                if (wh.autostart != ah.autostart) {
                    sqlif.updateWorkflowAutostart(wh.workflowid, ah.autostart);
                    Qorus.qmm.setWorkflowAutostart(wh.workflowid, ah.autostart);

                    updated = True;
                    info += sprintf(" was updated with autostart = %y", ah.autostart);
                    # start workflows with autostart flag set
                    hash<auto> h;
                    count = Qorus.control.autoStartWorkflow(cx,
                            wh + ("autostart": ah.autostart),
                            \h,
                            "autostarting workflow",
                            \errstr);
                } else {
                    updated = False;
                    info += sprintf(" was not updated because autostart already was %y", ah.autostart);
                }

                rv += {
                    "arg": arg,
                    "updated": updated,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": errstr ? sprintf("%s, finished with errors: %s", info, errstr) : info,
                    "started": count,
                };
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SHUTDOWN-IN-PROGRESS") {
                    rethrow;
                } else {
                    rv += {
                        "arg": arg,
                        "updated": False,
                        "workflowid": id,
                        "name": wh.name,
                        "version": wh.version,
                        "info": sprintf("%s: %s", ex.err, ex.desc),
                    };
                }
            }
        }

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=incAutostart

        @par Description
        Increments the autostart value on one or more workflows.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow names or IDs to modify; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash with the following keys:
        - \c arg: the workflow ID or name
        - \c updated: @ref True or @ref False
        - \c autostart: the new autostart value for the workflow
        - [\c workflowid]: the workflow ID
        - [\c name]: the workflow name
        - [\c version]: the workflow version
        - \c info: info about the workflow update action or a reason why the request failed
        - [\c started]: the number of execution instances started

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETAUTOSTART-ERROR: missing \c ids argument; cannot set a positive autostart value on a workflow with the deprecated flag set
     */
    hash<auto> putIncAutostart(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "WORKFLOW-SETAUTOSTART-ERROR", "missing \"ids\" argument for workflow IDs to update";

        rlog(cx);

        list rv = ();

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        foreach any arg in (ah.ids) {
            *hash<auto> wh;
            int id;
            try {
                id = WorkflowRestClass::staticGetWorkflowId(arg, True, \wh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "updated": False, "info": "unknown workflow");
                continue;
            }
            try {
                string info = sprintf("%s v%s (%d)", wh.name, wh.version, wh.workflowid);

                if (wh.deprecated)
                    throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("cannot increment autostart status on workflow %s with the deprecated (hidden) flag set", info);

                bool updated;
                int count = 0;
                # FIXME I believe we should not allow for increasing autostart over
                # max_instances here, but then it would require better sync between
                # sqlif, qmm and Control. If wh.autostart crosses over max_instances then
                # sqlif and qmm get updated, but actually only max_instances will be
                # running. --PQ 15-Aug-2016
                ++wh.autostart;
                sqlif.updateWorkflowAutostart(wh.workflowid, wh.autostart);
                Qorus.qmm.setWorkflowAutostart(wh.workflowid, wh.autostart);

                updated = True;
                info += sprintf(" was updated with autostart = %y", wh.autostart);
                string errstr;
                hash<auto> h;
                count = Qorus.control.autoStartWorkflow(cx,
                        wh + ("autostart": ah.autostart),
                        \h,
                        "autostarting workflow",
                        \errstr);

                rv += {
                    "arg": arg,
                    "updated": updated,
                    "autostart": wh.autostart,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": errstr ? sprintf("%s, finished with errors: %s", info, errstr) : info,
                    "started": count,
                };
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SHUTDOWN-IN-PROGRESS") {
                    rethrow;
                } else {
                    rv += {
                        "arg": arg,
                        "updated": False,
                        "workflowid": id,
                        "name": wh.name,
                        "version": wh.version,
                        "info": sprintf("%s: %s", ex.err, ex.desc),
                    };
                }
            }
        }

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=decAutostart

        @par Description
        Decrements the autostart value on one or more workflows.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow names or IDs to modify; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash with the following keys:
        - \c arg: the workflow ID or name
        - \c updated: @ref True or @ref False
        - \c autostart: the new autostart value for the workflow
        - [\c workflowid]: the workflow ID
        - [\c name]: the workflow name
        - [\c version]: the workflow version
        - \c info: info about the workflow update action or a reason why the request failed
        - [\c stopped]: the number of execution instances stopped

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-SETAUTOSTART-ERROR: missing \c ids argument; autostart value cannot be negative
     */
    hash<auto> putDecAutostart(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "WORKFLOW-SETAUTOSTART-ERROR", "missing \"ids\" argument for workflow IDs to update";

        rlog(cx);

        list rv = ();

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        foreach any arg in (ah.ids) {
            *hash<auto> wh;
            int id;
            try {
                id = WorkflowRestClass::staticGetWorkflowId(arg, True, \wh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "updated": False, "info": "unknown workflow");
                continue;
            }
            try {
                string info = sprintf("%s v%s (%d)", wh.name, wh.version, wh.workflowid);

                if (wh.deprecated)
                    throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("cannot decrement autostart status on workflow %s with the deprecated (hidden) flag set", info);

                if (!wh.autostart)
                    throw "WORKFLOW-SETAUTOSTART-ERROR", sprintf("cannot decrement autostart status on workflow %s because it is already at zero", info);

                bool updated;
                int count = 0;
                --wh.autostart;
                sqlif.updateWorkflowAutostart(wh.workflowid, wh.autostart);
                Qorus.qmm.setWorkflowAutostart(wh.workflowid, wh.autostart);

                updated = True;
                info += sprintf(" was updated with autostart = %y", wh.autostart);
                string errstr;
                hash<auto> h;
                count = Qorus.control.autoStartWorkflow(cx,
                        wh + ("autostart": ah.autostart),
                        \h,
                        "autostarting workflow",
                        \errstr);

                rv += {
                    "arg": arg,
                    "updated": updated,
                    "autostart": wh.autostart,
                    "workflowid": id,
                    "name": wh.name,
                    "version": wh.version,
                    "info": errstr ? sprintf("%s, finished with errors: %s", info, errstr) : info,
                    "stopped": -count,
                };
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SHUTDOWN-IN-PROGRESS") {
                    rethrow;
                } else {
                    rv += {
                        "arg": arg,
                        "updated": False,
                        "workflowid": id,
                        "name": wh.name,
                        "version": wh.version,
                        "info": sprintf("%s: %s", ex.err, ex.desc),
                    };
                }
            }
        }

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=stopAll

        @par Description
        Stops all workflow execution instances.

        @par Return Value
        This API returns a hash with the following keys:
        - \c count: number of workflow execution instances stopped
        - \c workflows: a hash keyed by workflow description where the values are the lists of all execution instance IDs stopped for that workflow
        - \c msg: a descriptive message about the workflows stopped

        @deprecated Workflow execution instances should not be manually stopped; they should be disabled instead; use @ref rest_api_PUT_workflows_enable and @ref rest_api_PUT_workflows_disable instead of starting and stopping workflow execution instances
     */
    hash<auto> putStopAll(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        # workflow access is checked in Control::stopAllWorkflows()
        hash<auto> sh;
        int count = Qorus.control.stopAllWorkflows(cx, \sh);
        hash<auto> h = {
            "count": count,
            "workflows": sh,
            "msg": sprintf("%d workflow execution instance%s %s been stopped", count,
                           count != 1 ? "s" : "",
                           count != 1 ? "have" : "has"),
        };
        return RestHandler::makeResponse(200, h);
    }

    static list<hash<auto>> staticGetWorkflowMetadata(bool with_deprecated, int apiver, *hash<auto> filter) {
        list<hash<auto>> l = Qorus.qmm.getWorkflowList(with_deprecated, filter);
        if (apiver < 3) {
            # remove keys from responses if API ver < 3
            l = map $1 - ("remote", "process", "sla_threshold", "manual_sla_threshold"), l;
        }
        return l;
    }

    static hash<auto> staticGetOrderSummary(softdate date, bool with_deprecated) {
        *list l = sysinfo.getWorkflowSummaryOverview(date, NOTHING, with_deprecated);
        hash<auto> h;
        map h.(SQLStatMap.($1.workflowstatus)) = $1.total, l;
        return RestHandler::makeResponse(200, h);
    }

    # desc: get workflows (optional parameters: date), returns: workflows decorated with instance status overview and running instances
    static *list<hash<auto>> staticGetWorkflows(*softdate date, bool sqlcache, bool with_deprecated = True, int apiver, *hash<auto> filter) {
        list<hash<auto>> rvlist = WorkflowRestClass::staticGetWorkflowMetadata(with_deprecated, apiver);

        # get order data summary
        *hash<auto> oview = sysinfo.getWorkflowOverview(date, NOTHING, sqlcache, with_deprecated);
        # reformat overview hash
        hash<auto> wfh;
        foreach hash<auto> wh in (oview.iterator()) {
            map wfh.($1.workflowid) = ($1 - "workflowid"), wh.iterator();
        }

        # get running workflow info
        *list<hash<auto>> exec = Qorus.control.getWorkflowInfoList();
                # reformat exec hash
        hash<auto> eh;
        foreach hash<auto> eih in (exec) {
            # convert executionID to an integer
            eih.executionID = eih.executionID.toInt();
            reference<auto> e = \eh.(eih.workflowid);
            if (!e) {
                e = ();
            }
            # issue #2424: add compat keys to old API responses
            if (apiver < 3) {
                eih += WorkflowInstanceRestClass::staticGetCompatExecHash();
            }
            # add to hash without redundant keys
            e += eih - ("name", "version", "workflowid", "remote", "process", "groups", "alerts", "options");
        }

        #log(LoggerLevel::DEBUG, "staticGetWorkflows: date: %y oview: %y wfh: %y", date, oview, wfh);

        # add workflows to list
        foreach hash<auto> wh in (\rvlist) {
            wh += wfh.(wh.workflowid);

            # reformat options in a single list of hashes with configured and runtime values
            hash<auto> opts;
            map opts.($1.key).desc = $1.value, wh.options.pairIterator();
            map opts.($1.key).value = $1.value, (remove wh."runtime-options").pairIterator();
            wh.options = map ("name": $1) + opts.$1, keys opts;

            wh.exec = eh.(wh.workflowid);
            wh.exec_count = wh.exec.size();

            # add workflow stats
            if (apiver >= 3) {
                wh.order_stats = Qorus.orderStats.getCurrentEvents(wh.workflowid);
                foreach hash<auto> sh in (\wh.stepinfo) {
                    Qorus.qmm.fillConfigItemValues("step", sh.stepid, \sh, wh.workflowid);
                    wh.config += remove sh.workflow_config;
                    wh.global_config += remove sh.global_config;
                }
            }
        }

        # issue #3621: allow interfaces to be filtered by tag
        if (filter) {
            rvlist = QorusMapManager::filterList(rvlist, filter);
        }
        return Qorus.rbac.addWorkflowGroupsAndAlerts(Qorus.connDeps.getConnections("WORKFLOW", Qorus.alerts.getAlerts("WORKFLOW", rvlist, "workflowid"), "workflowid"));
    }

    /** @REST GET action=list

        @par Description
        Returns information about workflows

        @see This API is equivalent to @ref rest_api_GET_workflows; see that documentation for details.
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }
}

/** @REST /steps/{id_or_name}

    This REST API path provides actions and information about specific @ref steps "workflow steps"
*/
class StepDefinitionRestClass inherits QorusRestClass {
    private {
        hash<auto> sh;
    }

    public {
        const StepFunctions = {
            "primary": "stepfunction_instanceid",
            "validation": "validationfunction_instanceid",
            "array": "arrayfunction_instanceid",
            "async-end": "endfunction_instanceid",
        };
    }

    string name() {
        return "step";
    }

    constructor(hash<auto> h, *int apiver) {
        sh = h;
        if (apiver < 3) {
            remove h.config;
        }
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (sh.hasKey(arg))
                return new AttributeRestClass(sh{arg});
        }
    }

    static hash<auto> staticGetFunctionInfo(string type, softint id) {
        return {
            "type": type,
        } + FunctionRestClass::staticGetFunctionInfo(id);
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current step.

        @par Return Value
        This API returns a @ref rest_step_hash providing about the current step plus additional keys as follows:
        - \c desc: the step description (as derived from the description of the primary step function)
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        sh.functions = ();
        # add function info
        map sh.functions += StepDefinitionRestClass::staticGetFunctionInfo($1.key, sh.($1.value)), StepFunctions.pairIterator(), sh.($1.value);

        if (!sh.desc) {
            sh.desc = sh.functions[0].description;
        }

        return RestHandler::makeResponse(200, sh);
    }
}

/** @REST /steps

    This REST API path provides actions and information about specific @ref steps "workflow steps"
*/
class StepRestClass inherits QorusRestClass {
    string name() {
        return "steps";
    }

    private QorusRestClass internSubClass(hash<auto> h) {
        return new StepDefinitionRestClass(h - "config");
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        softint id = (arg =~ /[[:alpha:]]/u) ? Qorus.qmm.stepId(arg) : arg;
        *hash<auto> h = Qorus.qmm.lookupStep(id);
        if (!h) {
            return;
        }

        h += {
            "stepid": id,
            "typedesc": h.steptype + (h.arraytype == "NONE" ? "" : " ARRAY"),
        };
        return internSubClass(h);
    }

    hash<auto> doGetIntern(hash<auto> cx, *hash<auto> ah, *int apiver) {
        *hash<auto> h = Qorus.qmm.getStepMap();

        if (exists ah.list && parse_boolean(ah.list)) {
            return RestHandler::makeResponse(200, (map $1.name, h.iterator()));
        }

        if (exists ah.short && parse_boolean(ah.short)) {
            return RestHandler::makeResponse(200,
                (map sprintf("%s v%s (%d)", $1.value.name, $1.value.version, $1.key), h.pairIterator()));
        }

        # repackage into list
        list<hash<auto>> l = ();
        foreach hash<auto> i in (h.pairIterator()) {
            if (apiver < 3) {
                remove i.value.config;
            }
            l += {
                "stepid": i.key.toInt(),
                "typedesc": i.value.steptype + (i.value.arraytype == "NONE" ? "" : " ARRAY"),
            } + i.value;
        }

        return RestHandler::makeResponse(200, l);
    }

    /** @REST GET action=list

        @par Description
        Identical to @ref rest_api_GET_steps

        @see @ref rest_api_GET_steps
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of all steps

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of step names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with step names, versions, and stepids is returned

        @par Return Value
        This API returns a list of @ref rest_step_hash elements (if neither \c list nor \c short options are passed as above).
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return doGetIntern(cx, ah);
    }
}

/** @REST /functions/{id_or_name}

    This REST API path provides actions and information about specific functions
*/
class FunctionDefinitionRestClass inherits QorusRestClass {
    private {
        hash<auto> h;
    }

    string name() {
        return "function";
    }

    constructor(hash<auto> v_h) {
        h = v_h;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (h.hasKey(arg))
                return new AttributeRestClass(h{arg});
        }
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current function

        @par Return Value
        This API returns a @ref rest_function_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        return RestHandler::makeResponse(200, h);
    }
}

/** @REST /functions

    This REST API path provides actions and information about Qorus functions
*/
class FunctionRestClass inherits QorusRestClass {
    string name() {
        return "functions";
    }

    # move "sys" tags to top-level of hash
    static hash<auto> moveTags(hash<auto> h) {
        if (h.tags.sys)
            h += remove h.tags.sys;
        return h;
    }

    static *hash<auto> staticGetFunctionInfo(softint id) {
        *hash<auto> h = sysinfo.getFunctionInstance(id);
        if (!h)
            return;

        h.name = h.firstKey();
        h.version = h.(h.name).firstKey();
        h += remove h.(h.name).(h.version);
        remove h.(h.name);
        return FunctionRestClass::moveTags(h);
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        softint id = (arg =~ /[[:alpha:]]/u) ? Qorus.qmm.functionId(arg) : arg;
        *hash<auto> h = FunctionRestClass::staticGetFunctionInfo(id);
        if (!h)
            return;

        return new FunctionDefinitionRestClass(h);
    }

    /** @REST GET action=list

        @par Description
        Identical to @ref rest_api_GET_functions

        @see @ref rest_api_GET_functions
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of all functions

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of function names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with function names, versions, and IDs is returned

        @par Return Value
        This API returns a list of hashes with the following keys (if neither \c list nor \c short options are passed as above):
        - \c name: the name of the function
        - \c version: the version of the function
        - \c function_instanceid: the function ID
        - \c function_type: the type of function object; see @ref StepFunctionTypes for possible values
        - \c description: the description of the function
        - \c author: the author of the function
        - \c created: the date/time the function was created
        - \c modified: the date/time the function was modified
        - \c source: the source file that the function object was created from
        - \c line: the offset in the source file for the source of the function object
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = Qorus.qmm.getFunctionMap();

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.name, h.iterator()));

        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200, (map sprintf("%s v%s (%d)", $1.value.name, $1.value.version, $1.key), h.pairIterator()));

        # repackage into list
        list l = ();
        foreach string id in (keys h) {
            l += (
                "function_instanceid": id.toInt(),
                ) + h{id};
        }

        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /classes/{id_or_name}

    This REST API path provides actions and information about specific class objects
*/
class ClassDefinitionRestClass inherits QorusRestClass {
    private {
        hash<auto> h;
    }

    string name() {
        return h.name;
    }

    constructor(hash<auto> h) {
        self.h = h;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (h.hasKey(arg))
                return new AttributeRestClass(h{arg});
        }
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
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        return RestHandler::makeResponse(200, h);
    }
}

/** @REST /classes

    This REST API path provides actions and information about Qorus class objects
*/
class ClassRestClass inherits QorusRestClass {
    string name() {
        return "classes";
    }

    static *hash<auto> staticGetClassInfo(softint id, *int apiver) {
        # issue #3647: get all data from the metadata cache
        *hash<auto> h = Qorus.qmm.lookupClass(id);
        if (!h) {
            return;
        }
        h.classid = id;
        if (apiver < 3) {
            remove h{"language", "language_info"};
        }
        return FunctionRestClass::moveTags(h);
    }

    static *hash<auto> staticGetClassMap(*int apiver) {
        return Qorus.qmm.getClassMap(apiver >= 6);
    }

    *hash<auto> doGetClassMap() {
        return Qorus.qmm.getClassMap();
    }

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
        *hash<auto> h = ClassRestClass::staticGetClassInfo(id);
        return h ? new ClassDefinitionRestClass(h) : NOTHING;
    }

    /** @REST GET action=list

        @par Description
        Identical to @ref rest_api_GET_classes

        @see @ref rest_api_GET_classes
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of all classes

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of class names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with class names, versions, and IDs is returned

        @par Return Value
        This API returns a list of hashes with the following keys (if neither \c list nor \c short options are passed as above):
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
        *hash<auto> h = doGetClassMap();

        list<auto> rv;
        if (exists ah.list && parse_boolean(ah.list)) {
            rv = map $1.name, h.iterator();
        } else if (exists ah.short && parse_boolean(ah.short)) {
            rv = map sprintf("%s v%s (%d)", $1.value.name, $1.value.version, $1.key), h.pairIterator();
        } else {
            # repackage into list
            rv = map {"classid": $1.key.toInt()} + $1.value, h.pairIterator();
        }

        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /constants/{id_or_name}

    This REST API path provides actions and information about specific constant objects
*/
class ConstantDefinitionRestClass inherits QorusRestClass {
    private {
        hash<auto> h;
    }

    string name() {
        return "constant";
    }

    constructor(hash<auto> v_h) {
        h = v_h;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (h.hasKey(arg))
                return new AttributeRestClass(h{arg});
        }
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current constant object

        @par Return Value
        This API returns a hash with the following keys:
        - \c name: the name of the constant object
        - \c version: the version of the constant object
        - \c constantid: the constant object ID
        - \c description: the description of the constant object
        - \c author: the author of the constant object
        - \c body: the source code for the class object
        - \c created: the date/time the constant object was created
        - \c modified: the date/time the constant object was modified
        - \c createdby: (deprecated) always \c "omq"
        - \c modifiedby: (deprecated) always \c "omq"
        - \c tags: any user-defined tags on the constant object
        - \c source: the source file that the constant object was created from
        - \c offset: the offset in the source file for the source of constant object
        - \c host: the hostname of the machine where the constant object was loaded from
        - \c user: the OS user who loaded the constant object
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        return RestHandler::makeResponse(200, h);
    }
}

/** @REST /logout

    This REST API path provides the logout action
*/
class LogoutRestClass inherits QorusRestClass {
    string name() {
        return "logout";
    }

    /** @REST POST

        @par Description
        This API performs is a noop in the Community Edition

        @par Arguments
        None

        @par Return Value
        None

        @note This operation is a noop in the Community Edition
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, hash());
    }
}

/** @REST /constants

    This REST API path provides actions and information about Qorus constant objects
*/
class ConstantRestClass inherits QorusRestClass {
    string name() {
        return "constants";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        softint id = (arg =~ /[[:alpha:]]/u) ? Qorus.qmm.constantId(arg) : arg;
        *hash<auto> h = sysinfo.getConstant(id);
        if (!h)
            return;

        h.name = h.firstKey();
        h.version = h.(h.name).firstKey();
        h += remove h.(h.name).(h.version);
        remove h.(h.name);
        return new ConstantDefinitionRestClass(FunctionRestClass::moveTags(h));
    }

    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of all constant objects

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of constant names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with constant names, versions, and IDs is returned

        @par Return Value
        This API returns a list of hashes with the following keys (if neither \c list nor \c short options are passed as above):
        - \c constantid: the constant ID
        - \c name: the name of the constant
        - \c version: the version of the constant
        - \c description: the description of the constant object
        - \c author: the author of the constant object
        - \c created: the date/time the constant object was created
        - \c modified: the date/time the constant object was modified
        - \c source: the source file that the constant object was created from
        - \c line: the offset in the source file for source of the constant object
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = Qorus.qmm.getConstantMap();

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.name, h.iterator()));

        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200, (map sprintf("%s v%s (%d)", $1.value.name, $1.value.version, $1.key), h.pairIterator()));

        # repackage into list
        list l = ();
        foreach string id in (keys h) {
            l += (
                "constantid": id.toInt(),
                ) + h{id};
        }

        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /orders

    This URI path provides information and actions related to workflow order data.
*/
class GlobalOrderRestClass inherits QorusRestClass {
    string name() {
        return "orders";
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        if (id == "all")
            return self;
        *hash<auto> h = sysinfo.getWFIAllInfo(id, NOTHING, False);
        if (h)
            return new WorkflowOrderInstanceRestClass(h);
        throw "WORKFLOW-ORDER-ERROR", sprintf("there is no workflow_instanceid %d", id);
    }

    *list workflowInstances(*hash<auto> ah) {
        return map $1 + ("actions": WorkflowOrderInstanceRestClass::staticGetActions($1.workflowstatus)) - ("has_sensitive_data"), sysinfo.searchWorkflowInstances(ah);
    }

    /** @REST PUT action=retry

        @par Description
        Retries the given workflow order instances.  In order to make a retry; the workflow order status for each order must be @ref OMQ::StatError, @ref OMQ::StatAsyncWaiting, or OMQ::StatRetry.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow instance IDs to retry; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash where the top level key is the workflow_instanceid, and the value is either an exception string (indicating that the operation failed) or a hash with the following keys:
        - \c steps_updated: (deprecated) always 0 in this version of Qorus
        - \c segments_updated: the number of segments updated
        - \c workflow_updated: always @ref True in this version of Qorus
        - \c workflow_status: always @ref OMQ::StatRetry in this version of Qorus
        - \c cached: @ref True if the workflow data is currently cached
        .
        Failure reasons include:
        - \c "STATUS-ERROR": workflow data does not have @ref OMQ::StatError, @ref OMQ::StatAsyncWaiting, or OMQ::StatRetry status
        - \c "SESSION-ERROR": cannot change status for workflow data managed by another Qorus instance (foreign session ID)
        - \c "RETRY-ERROR": invalid workflow instance ID
     */
    hash<auto> putRetry(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        # rename old param for backwards compatibility
        if (!ah.ids && ah.workflow_instanceid)
            ah.ids = remove ah.workflow_instanceid;

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        return RestHandler::makeResponse(200, api."omq.system.retry-workflow-instances"(ah.ids));
    }

    /** @REST PUT action=block

        @par Description
        Blocks a list of workflow order data instances.  The operation will fail on workflow orders with status @ref OMQ::StatInProgress.  No further processing can be done on workflow order data instances with a @ref OMQ::StatBlocked status (unless the workflow instance is recovered back from @ref OMQ::StatBlocked or the status is first updated to @ref OMQ::StatError and then to @ref OMQ::StatRetry).

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more workflow instance IDs to block; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash where the top-level key is the workflow_instanceid, and each value is either an exception string (indicating that the operation for that workflow_instanceid failed) or a hash with the following key:
        - \c workflow_status: the status of the workflow order
        .
        Failure reasons include:
        - \c "BLOCK-WORKFLOW-ERROR": invalid status, foreign session id, missing original status, unblock operation already in progress

        @see
        - @ref rest_api_PUT_orders_unblock
        - @ref rest_api_PUT_orders__id__unblock
        - omq.system.block-workflow-instance()
        - omq.system.block-workflow-instances()
    */
    hash<auto> putBlock(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        hash<auto> h;
        map h.$1 = True, ah.ids;

        return RestHandler::makeResponse(200, api."omq.system.block-workflow-instances"(h));
    }

    /** @REST PUT action=unblock

        @par Description
        Resets the statuses of one or more blocked workflow order data instances to their original statuses before blocking.

        @par Return Value
        This API returns a hash where the top-level key is the workflow_instanceid, and each value is either an exception string (indicating that the operation for that workflow_instanceid failed) or a hash with the following key:
        - \c workflow_status: the status of the workflow order
        .
        Failure reasons include:
        - \c "BLOCK-WORKFLOW-ERROR": invalid status, foreign session id, missing original status, block operation already in progress

        @see
        - @ref rest_api_PUT_orders_block
        - @ref rest_api_PUT_orders__id__block
        - omq.system.block-workflow-instance()
        - omq.system.block-workflow-instances()
    */
    hash<auto> putUnblock(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        hash<auto> h;
        map h.$1 = False, ah.ids;

        return RestHandler::makeResponse(200, api."omq.system.block-workflow-instances"(h));
    }

    /** @REST PUT action=cancel

        @par Description
        Cancels one or more workflow order data instances by changing the status for the workflow order data
        instances to @ref OMQ::StatCanceled.  The operation will fail if the workflow order status is
        @ref OMQ::StatInProgress.  No further processing can be done on workflow order data instances with a
        @ref OMQ::StatCanceled status (unless the workflow instance is recovered back from @ref OMQ::StatCanceled or
        the status is first updated to @ref OMQ::StatError and then to @ref OMQ::StatRetry).

        @par Return Value
        This API returns a hash where the top-level key is the workflow_instanceid, and each value is either an
        exception string (indicating that the operation for that workflow_instanceid failed) or a hash with the
        following key:
        - \c workflow_status: the status of the workflow order

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c CANCEL-WORKFLOW-ERROR: invalid status, foreign session id, missing original
          status, uncancel operation already in progress

        @see
        - @ref rest_api_PUT_orders_uncancel
        - @ref rest_api_PUT_orders__id__uncancel
        - omq.system.cancel-workflow-instance()
        - omq.system.cancel-workflow-instances()
    */
    hash<auto> putCancel(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # process arguments
        if (ah.ids.typeCode() == NT_STRING) {
            ah.ids = ah.ids.split(",");
        }
        *hash<auto> h = map {$1: True}, ah.ids;

        hash<auto> rv = {};
        # workflow access is checked in SegmentManager::cancelWorkflowInstance()
        foreach hash<auto> i in (h.pairIterator()) {
            try {
                rv{i.key} = SM.cancelWorkflowInstance(cx, i.key, True);
            } catch (hash<ExceptionInfo> ex) {
                rv{i.key} = sprintf("%s: %s", ex.err, ex.desc);
            }
        }

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=uncancel

        @par Description
        Resets one or more canceled workflow order data instance statuses to their original statuses before canceling.

        @par Return Value
        This API returns a hash where the top-level key is the workflow_instanceid, and each value is either an exception string (indicating that the operation for that workflow_instanceid failed) or a hash with the following key:
        - \c workflow_status: the status of the workflow order
        .
        Failure reasons include:
        - \c "CANCEL-WORKFLOW-ERROR": invalid status, foreign session id, missing original status, cancel operation already in progress

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: all uncancel operations failed

        @see
        - @ref rest_api_PUT_orders_cancel
        - @ref rest_api_PUT_orders__id__cancel
        - omq.system.cancel-workflow-instance()
        - omq.system.cancel-workflow-instances()
    */
    hash<auto> putUncancel(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # process arguments
        if (ah.ids.typeCode() == NT_STRING) {
            ah.ids = ah.ids.split(",");
        }
        *hash<auto> h = map {$1: True}, ah.ids;

        hash<auto> rv = {};

        # workflow access is checked in SegmentManager::cancelWorkflowInstance()
        int errs;
        foreach softstring wfiid in (ah.ids) {
            try {
                rv{wfiid} = SM.cancelWorkflowInstance(cx, wfiid, False);
            } catch (hash<ExceptionInfo> ex) {
                ++errs;
                h{wfiid} = sprintf("%s: %s", ex.err, ex.desc);
            }
        }

        # if all commands failed, then return a 400 Bad Request error
        if (errs && errs == rv.size()) {
            return RestHandler::makeResponse(400, rv);
        } else {
            return RestHandler::makeResponse(200, rv);
        }
    }

    /** @REST GET action=listErrors

        @par Description
        Returns information about workflow order errors corresponding to the search arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c orderby: one or more field names for sorting the output
        - \c error: the error text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c description: the description text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given)
        - \c info: the info text to search (can also include '%' characters for use with the LIKE operator; in this case only 1 value can be given
        - \c stepid: limit the search to one or more stepids
        - \c severity: limit the search to one or more severity values
        - \c name: limit the search to one or more step names
        - \c version: limit the search to one or more step versions
        - \c retry: limit the search to errors with or without the retry flag
        - \c business_error: limit the search to errors with or without the business_error flag
        - \c workflow_instanceid:  limit the search to one or more workflow_instanceids
        - \c error_instanceid: limit the search to one or more error_instanceids
        - \c mindate: give the lower date range for the error search
        - \c maxdate: give the upper date range for the error search
        - \c workflowid: limit the search to one or more workflowids
        - \c workflowstatus: limit the search to workflow instances with the given status value(s)
        - \c limit: the maximum number of errors to return
        - \c offset: the starting error to return (use when paging for example)

        @par Return Value
        This API returns a list of hashes with the following keys for all data matched according to the search arguments:
        - \c name: the name of the workflow
        - \c version: the version of the workflow
        - \c workflow_instanceid: the workflow instance ID
        - \c workflowid: the workflow ID
        - \c stepid: the step ID where the error occurred
        - \c stepname: the name of the step where the error occurred
        - \c stepversion: the version of the step where the error occurred
        - \c ind: the array step index number where the error occurred
        - \c workflowstatus: current status of the workflow (see @ref StatusDescriptions for possible values)
        - \c started: the date and time when the workflow order started processing
        - \c completed: the date and time when the workflow order was completed
        - \c parent_workflow_instanceid: any parent workflow instance ID
        - \c custom_status: the custom status of the workflow order, if any
        - \c priority: the priority of the workflow order
        - \c scheduled: any scheduled date for the workflow order
        - \c error_instanceid: the error instance ID
        - \c error: the error code string
        - \c description: a description for the error (if any)
        - \c info: additional information about the error (if any)
        - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
        - \c created: the date and time the error was raised
        - \c retry: the retry count of the error
        - \c business_error: a boolean flag indicating of the error is a business error
        - \c custom_status_desc: a descriptive string for the custom status (if any)
    */
    hash<auto> getListErrors(hash<auto> cx, *hash<auto> ah) {
        # issue 1879 handle list arguments
        if (ah.error =~ /,/)
            ah.error = ah.error.split(",");
        if (ah.stepid =~ /,/)
            ah.stepid = ah.stepid.split(",");
        if (ah.name =~ /,/)
            ah.name = ah.name.split(",");
        if (ah.error_instanceid =~ /,/)
            ah.error_instanceid = ah.error_instanceid.split(",");
        if (ah.workflow_instanceid =~ /,/)
            ah.workflow_instanceid = ah.workflow_instanceid.split(",");
        if (ah.workflowid =~ /,/)
            ah.workflowid = ah.workflowid.split(",");
        if (ah.workflowstatus =~ /,/)
            ah.workflowstatus = ah.workflowstatus.split(",");

        *list l = sysinfo.searchWorkflowErrors(ah);
        return RestHandler::makeResponse(200, l);
    }

    static list processingSummary(hash<auto> cx, *hash<auto> ah) {
        return sysinfo.getWorkflowProcessingSummary(ah);
    }

    /** @REST GET action=processingSummary

        @par Description
        Returns information about workflow processing.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c mindate: (required) minimum date
        - \c maxdate: maximum date
        - \c wfids: optional workflow IDs
        - \c seconds: if @ref True "True" then the performance values will be returned as arbitrary-precision numeric values representing seconds, otherwise they will be returned as @ref relative_dates "relative date/time values"
        - \c global: if @ref True "True" then all workflows will be combined into an overall processing report, if @ref False "False" then each workflow gets a separate line in the output
        - grouping: (optional) possible values for reporting performance statistics:
          - \c "hourly": hourly grouping
          - \c "daily": daily grouping
          - \c "monthly": monthly grouping
          - \c "yearly": yearly grouping

        @par Return Value
        This API returns a list of hashes with the following keys for all data matched according to the search arguments:
        - \c workflowid: the workflow ID
        - \c name: the workflow name
        - \c version: the workflow version
        - \c count: the number of workflow orders in the period
        - \c minstarted: the minimum workflow order start date
        - \c maxcompleted: the maximum workflow order completion date (if any)
        - \c minduration: the minimum total elapsed order processing time for workflow orders in the period (starting from workflow order creation)
        - \c avgduration: the average total elapsed order processing time for workflow orders in the period (starting from workflow order creation)
        - \c maxduration: the maximum total elapsed order processing time for workflow orders in the period (starting from workflow order creation)
        - \c minprocessing: the minimum order processing time for workflow orders in the period (starting from when then order was first processed)
        - \c avgprocessing: the average order processing time for workflow orders in the period (starting from when then order was first processed)
        - \c maxprocessing: the maximum order processing time for workflow orders in the period (starting from when then order was first processed)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c ARGUMENT-ERROR: missing \c mindate
    */
    hash<auto> getProcessingSummary(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, GlobalOrderRestClass::processingSummary(cx, ah));
    }

    hash<auto> staticGetOrderSummary(hash<auto>  cx, *hash<auto> ah) {
        ah.date = ah.date ? date(ah.date) : now() - 1D;
        ah.deprecated = exists ah.deprecated ? parse_boolean(ah.deprecated) : True;
        return WorkflowRestClass::staticGetOrderSummary(ah.date, ah.deprecated);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes for orders for the current workflow matching the search criteria

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c date: an alternate key for \c modified
        - \c desc: return in descending order
        - \c ids: an alternate key for \c workflow_instanceid
        - \c key: an alternate key for \c keyname
        - \c keyname: the name of a search key to be used with the \a keyvalue value(s)
        - \c keyvalue: the value(s) of workflow order search key(s) to use (optionally used in conjunction with \a keyname)
        - \c limit: max number of rows to return, if not given, then the value of the \a "row-limit" option is used (default: 100)
        - \c maxmodified: maximum modified date
        - \c maxstarted: maximum start date
        - \c minstarted: minimum start date
        - \c modified: minimum modified date; if this key is not sent with the request, and no \c keyvaue, \c keyname or \c workflow_instanceid keys are sent, then a value one week before the time of the request is assumed
        - \c offset: row offset
        - \c sort: columns for sorting the results
        - \c status: status value(s) (see @ref StatusDescriptions for possible values)
        - \c statuses: an alternate key for \c status
        - \c wfid: an alternate key for \c workflowid
        - \c workflowid: one or more workflow IDs
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
        - \c custom_status: a custom status for the order
        - \c priority: the priority of the workflow order
        - \c scheduled: the future scheduled date for the workflow order (if any)
        - \c custom_status_desc: a description for the custom status (if any)
        - \c actions: a list of possible actions on the workflow
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        # rename args
        if (ah.date && !ah.modified)
            ah.modified = remove ah.date;
        if (ah.wfids && !ah.workflowid)
            ah.workflowid = remove ah.wfids;
        if (ah.ids && !ah.workflow_instanceid)
            ah.workflow_instanceid = remove ah.ids;
        if (ah.statuses && !ah.status)
            ah.status = remove ah.statuses;
        if (ah.key && !ah.keyname)
            ah.keyname = remove ah.key;

        # issue #2161: an empty "date" or "modified" key must be respected
        if (!ah.hasKey("modified") && !ah.hasKey("date") && !ah.keyvalue && !ah.keyname && !ah.workflow_instanceid)
            ah.modified = now() - 7D;

        #log(LoggerLevel::DEBUG, "orders get: ah: %y", ah);
        return RestHandler::makeResponse(200, workflowInstances(ah));
    }
}

/** @REST /exec

    This URI path provides actions and information regarding workflow execution instances.
*/
class GlobalWorkflowExecRestClass inherits QorusRestClass {
    private {
        hash<auto> wf;
    }

    string name() {
        return "exec";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # see if we want to work with named workflows
        if (arg =~ /[[:alpha:]]/u) {
            # try to find version
            *string ver;
            if ((int i = arg.find(":")) != -1) {
                ver = extract arg, i + 1;
                splice arg, -1;
            }
            # iterate execution instances for the given workflow, add compat keys to each hash
            *list l = map $1 + {
                "executionID": $1.executionID.toInt(),
                "log_url": get_log_url(cx, "workflows/%d", $1.workflowid),
            } - ("remote", "process") + WorkflowInstanceRestClass::staticGetCompatExecHash(),
                # map iterator expression
                api."omq.system.get-workflow-info"(),
                # map filter expression
                $1.name == arg && (!ver || ver == $1.version);

            return new WorkflowExecInstanceGroupRestClass(arg, ver, l);
        }

        softint execid = arg;

        # get running workflow info for the given ID
        *hash<auto> eih = api."omq.system.get-workflow-info"(execid);
        if (eih) {
            eih.executionID = execid;
            eih.log_url = get_log_url(cx, "workflows/%d", eih.workflowid);
            # remove old keys, add compat keys for v1 & v2 API
            return new WorkflowExecInstanceRestClass(eih - ("remote", "process")
                + WorkflowInstanceRestClass::staticGetCompatExecHash());
        }
    }

    /** @REST GET

        @par Return Value
        This API returns a list of hashes with the keys of @ref rest_execution_instance_hash, plus the following keys:
        - \c groups: list of @ref rbacgroups "interface groups" that the workflow belongs to; each list element is a @ref rest_interface_group_hash (may be empty)
        - \c alerts: a list of alerts raised against the workflow; each list element is a @ref rest_alert_hash (may be empty)
        - \c log_url: a complete URL to the websocket source for the workflow log
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        *list l = api."omq.system.get-workflow-info"();
        l = map $1 + {
            "executionID": $1.executionID.toInt(),
            "log_url": get_log_url(cx, "workflows/%d", $1.workflowid),
         } - ("remote", "process") + WorkflowInstanceRestClass::staticGetCompatExecHash(), l;
        return RestHandler::makeResponse(200, l);
    }

    /** @REST PUT action=stopAll

        @par Description
        Stops all workflow execution instances.

        @par Return Value
        This API returns a hash with the following keys:
        - \c count: number of workflow execution instances stopped
        - \c workflows: a hash keyed by workflow description where the values are the lists of all execution instance IDs stopped for that workflow
        - \c msg: a descriptive message about the workflows stopped

        @deprecated Workflow execution instances should not be manually stopped; they should be disabled instead; use @ref rest_api_PUT_workflows_enable and @ref rest_api_PUT_workflows_disable instead of starting and stopping workflow execution instances
     */
    hash<auto> putStopAll(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        # workflow access is checked in Control::stopAllWorkflows()
        hash<auto> sh;
        int count = Qorus.control.stopAllWorkflows(cx, \sh);
        hash<auto> h = (
            "count": count,
            "workflows": sh,
            "msg": sprintf("%d workflow execution instance%s %s been stopped", count,
                           count != 1 ? "s" : "",
                           count != 1 ? "have" : "has"),
            );
        return RestHandler::makeResponse(200, h);
    }

    /** @REST PUT action=stopMany

        @par Description
        Manually stops one or more workflow execution instances.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c args: (required) one or more workflow names or IDs to stop

        @par Return Value
        This API returns a hash with the following keys:
        - \c count: number of workflow execution instances stopped
        - \c workflows: a hash keyed by workflow description where the values are the lists of all execution instance IDs stopped for that workflow
        - \c msg: a descriptive message describing the workflow execution instances that were stopped

        @deprecated Workflow execution instances should not be manually stopped; they should be disabled instead; use @ref rest_api_PUT_workflows_enable and @ref rest_api_PUT_workflows_disable instead of starting and stopping workflow execution instances
    */
    hash<auto> putStopMany(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        # count of instances stopped
        int count;
        # hash of workflows stopped
        hash<auto> sh;

        foreach softstring arg in (ah.args) {
            if (arg == int(arg)) {
                # workflow access is checked in Control::stopWorkflowInstance()
                if (!Qorus.control.stopWorkflowInstance(cx, arg.toInt(), \sh))
                    count++;
            }
            else {
                *string ver;
                if ((int i = arg.find(":")) != -1) {
                    ver = extract arg, i + 1;
                    splice arg, -1;
                }
                count += Qorus.control.stopWorkflow(cx, arg, ver, \sh);
            }
        }

        hash<auto> h = (
            "count": count,
            "workflows": sh,
            "msg": sprintf("%d workflow execution instance%s %s been stopped", count,
                           count != 1 ? "s" : "",
                           count != 1 ? "have" : "has"),
            );
        return RestHandler::makeResponse(200, h);
    }

    /** @REST GET action=list

        @par Description
        Returns information about workflow execution instances.

        @see This API is equivalent to @ref rest_api_GET_exec; see that documentation for details.
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }
}

/** @REST /services/{id_or_name}/{method}

    This REST path provides actions and information about service methods
*/
class ServiceMethodRestClass inherits QorusRestClass {
    private {
        hash<auto> mh;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (mh.hasKey(arg))
                return new AttributeRestClass(mh{arg});
        }
    }

    string name() {
        return mh.name;
    }

    constructor(hash<auto> v_mh) {
        mh = v_mh;
    }

    /** @REST PUT action=call

        @par Description
        Calls the current service method with any argument given and returns the result; the service is loaded and started if necessary.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - [\c parse_args]: any string here will be parsed with @ref Util::parse_to_qore_value() and used as the method arguments; \c parse_args takes precedence over \c args
        - [\c args]: any arguments passed here will be used directly as the method arguments

        @par Return Value
        This API returns result of calling the current service method

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-ERROR: invalid method call; missing method name
    */
    hash<auto> putCall(hash<auto> cx, *hash<auto> ah) {
        auto args = exists ah.parse_args ? parse_to_qore_value(ah.parse_args) : ah.args;
        return RestHandler::makeResponse(200, services.callMethod(mh.service_type, mh.service_name, mh.name, args, True, cx));
    }

    /** @REST GET

        @par Return Value
        This API returns a @ref rest_service_method_hash describing the service method with the addition of the following keys describing the service:
        - \c service_status: the status of the service; one of:
          - \c "loaded": loaded but not running
          - \c "running": loaded and running with at least one service thread
          - \c "unloaded": not loaded
        - \c serviceid: the ID of the service
        - \c service_name: the name of the service
        - \c service_type: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, mh);
    }
}

/** @REST /services/{id_or_name}/resource_files/{name}

    This REST URI path provides information about a particular service resource file.
*/
class ServiceResourceFileRestClass inherits QorusRestClass {
    private {
        string rsrc;
        hash<auto> rh;
    }

    constructor(hash<auto> sh, string rsrc, hash<auto> rh) {
        self.rsrc = rsrc;
        self.rh = rh + {
            "data": services.getServiceFileResourceData(sh.type, sh.name, rsrc),
        };
    }

    string name() {
        return rsrc;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (rh.hasKey(arg))
                return new AttributeRestClass(rh{arg});
        }
    }

    /** @REST GET

        @par Return Value
        Returns a hash of service resource file information with the following keys:
        - type: the type code for the service resource
        - data: the data of the service resource
     */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, rh);
    }
}

/** @REST /services/{id_or_name}/resource_files

    This REST URI path provides information about service resource files.
*/
class ServiceResourceFilesRestClass inherits QorusRestClass {
    private {
        hash<auto> sh;
        *hash<auto> rh;
    }

    constructor(hash<auto> n_sh, *hash<auto> n_rh) {
        sh = n_sh;
        rh = n_rh;
    }

    string name() {
        return "resource_files";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        arg =~ s/\|/\//g;
        if (rh.hasKey(arg)) {
            return doGetResourceFileRestClass(sh, arg);
        }
    }

    /** @REST GET

        @par Return Value
        Returns a hash of service resource information; the keys are the resource name, the values hashes with the following keys:
        - type: the type code for the service resource
     */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, rh);
    }

    QorusRestClass doGetResourceFileRestClass(hash<auto> sh, string arg) {
        return new ServiceResourceFileRestClass(sh, arg, rh{arg});
    }
}

/** @REST /services/{id_or_name}

    This REST URI path provides actions and information related to Qorus services;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class ServiceDefinitionRestClass inherits QorusRestClass {
    private {
        hash<auto> sh;
    }

    hash<auto> getValues() {
        return sh{"name", "version", "description"};
    }

    constructor(hash<auto> v_sh) {
        sh = v_sh;

        if (sh.parse_options)
            sh.parse_options = sh.parse_options.split(",");
    }

    string name() {
        return sh.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        hash<auto> smh;
        if (arg =~ /[[:alpha:]]/u) {
            # only look for method if we know it exists
            if (sh.method_name_map{arg}) {
                # find the named method
                foreach hash<auto> mh in (sh.methods) {
                    if (mh.name == arg) {
                        smh = mh;
                        break;
                    }
                }
            }
            if (!smh) {
                if (arg == "resource_files") {
                    return doGetServiceResourceFilesRestClass();
                }

                # only return attributes if we have a GET request
                if (cx.hdr.method == "GET") {
                    if (sh.hasKey(arg))
                        return new AttributeRestClass(sh{arg});

                    if (arg == "state")
                        return new AttributeRestClass(retrieveState());
                }
                return;
            }
        } else {
            foreach hash<auto> mh in (sh.methods) {
                if (mh.service_methodid == arg) {
                    smh = mh;
                    break;
                }
            }

            if (!smh)
                return;
        }

        hash<auto> mh = {
            "service_status": sh.status,
            "serviceid": sh.serviceid,
            "service_name": sh.name,
            "service_type": sh.type,
        } + smh;

        return new ServiceMethodRestClass(mh);
    }

    private QorusRestClass doGetServiceResourceFilesRestClass() {
        return new ServiceResourceFilesRestClass(sh, (map {$1.name: $1 - "name"}, sh.resource_files));
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
        - \c state: a hash of saved service state data (if any); see
          @ref OMQ::UserApi::Service::ServiceApi::saveStateData() "ServiceApi::saveStateData()" for more info
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        sh.state = retrieveState();
        return RestHandler::makeResponse(200, sh);
    }

    private *hash<auto> retrieveState() {
        # get service state data, if any
        *string str;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                str = get_sql_table_system("omq", "service_state_data").selectRow({
                    "columns": "data",
                    "where": {"serviceid": sh.serviceid},
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

    /** @REST PUT action=setStateData

        @par Description
        Provides an API for externally updating service state data

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c data: a hash of new service state data or @ref nothing which will clear any data

        @par Return Value
        This API returns the new data or @ref nothing if the data is cleared

        @see
        - svc_get_state_data()
        - svc_save_state_data()
    */
    hash<auto> putSetStateData(hash<auto> cx, *hash<auto> ah) {
        AbstractTable t = get_sql_table_system_trans("omq", "service_state_data");

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_success omqp.commit();
                on_error omqp.rollback();

                if (!exists ah.data)
                    t.del(("serviceid": sh.serviceid));
                else {
                    if (ah.data.typeCode() != NT_HASH)
                        throw "SERVICE-STATE-ERROR", sprintf("\"data\" argument is type %y (expecting %y)", ah.data.type(), Type::String);
                    string str = serialize_qorus_data(ah.data);
                    t.upsert(("serviceid": sh.serviceid, "data": str));
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

    /** @REST PUT action=reset

        @par Description
        Unloads the current service (if loaded) and reloads it from the database.

        @par Return Value
        This API returns @ref True if the service was already loaded before this call, @ref False if not
    */
    hash<auto> putReset(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s %s v%s (%d))", sh.type, sh.name, sh.version, sh.serviceid);
        return RestHandler::makeResponse(200, api.("omq." + sh.type + ".reset-service")(sh.name));
    }

    /** @REST PUT action=setOptions

        @par Description
        Sets options for the current service.  If the service has an option list and any of the options are not valid
        for that service, an exception will be thrown, however, even if an exception is thrown due to an option error,
        all other options will still be set.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c options: a hash of options to set against the service; if the value of this key is a string, then it is
          first parsed with @ref Util::parse_to_qore_value(), which should then return a hash

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing \c "options" argument or \c "options" is not a hash (or string
          parsed to a hash with @ref Util::parse_to_qore_value())

        @note
        - service options are persistent (persistent service options were implemented in Qorus 5.0)
    */
    hash<auto> putSetOptions(hash<auto> cx, *hash<auto> ah) {
        if (ah.options.typeCode() == NT_STRING) {
            ah.options = parse_to_qore_value(ah.options);
        }
        if (!ah.options) {
            return RestHandler::make400("error setting options on %s service %s v%s (%d): missing 'options' hash in "
                "message body", sh.type, sh.name, sh.version, sh.serviceid);
        }
        if (ah.options.typeCode() != NT_HASH) {
            return RestHandler::make400("error setting options on %s service %s v%s (%d): 'options' argument is not "
                "a hash; got type %y instead", sh.type, sh.name, sh.version, sh.serviceid, ah.options.type());
        }

        rlog(cx, "(%s %s v%s (%d))", sh.type, sh.name, sh.version, sh.serviceid);

        list<string> errs = ();
        foreach hash<auto> i in (ah.options.pairIterator()) {
            try {
                Qorus.qmm.updateServiceOptionErr(sh.serviceid, i.key, i.value);
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SERVICE-OPTION-ERROR") {
                    errs += ex.desc;
                } else {
                    rethrow;
                }
            }
        }
        if (errs) {
            throw "SERVICE-OPTION-ERROR", (foldl $1 + "; " + $2, errs);
        }

        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=setAutostart

        @par Description
        Sets the autostart status of the current service

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c autostart: (required) the autostart status for the service (parsed with parse_boolean())

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing \c "autostart" hash argument
    */
    hash<auto> putSetAutostart(hash<auto> cx, *hash<auto> ah) {
        # permissions checked in RPC call
        if (!exists ah.autostart)
            return RestHandler::make400("error setting autostart for %s service %s v%s serviceid %d: missing 'autostart' hash in message body", sh.type, sh.name, sh.version, sh.serviceid);
        rlog(cx, "(%s %s v%s (%d))", sh.type, sh.name, sh.version, sh.serviceid);
        return RestHandler::makeResponse(200, api.("omq." + sh.type + ".set-service-autostart")(sh.name, parse_boolean(ah.autostart)));
    }

    /** @REST PUT action=load

        @par Description
        Loads and initializes the current service if it is not already loaded.

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-ERROR: the given service cannot be loaded (error initializing the service)

        @note
        - identical to @ref rest_api_PUT_services__id_or_name__start and @ref rest_api_PUT_services__id_or_name__init
    */
    hash<auto> putLoad(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s %s v%s (%d))", sh.type, sh.name, sh.version, sh.serviceid);
        api.("omq." + sh.type + ".service." + sh.name + ".init")();
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=start

        @par Description
        Loads and initializes the current service if it is not already loaded.

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-ERROR: the given service cannot be loaded (error initializing the service)

        @note
        - identical to @ref rest_api_PUT_services__id_or_name__load and @ref rest_api_PUT_services__id_or_name__init
    */
    hash<auto> putStart(hash<auto> cx, *hash<auto> ah) {
        return putLoad(cx, ah);
    }

    /** @REST PUT action=init

        @par Description
        Loads and initializes the current service if it is not already loaded.

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-ERROR: the given service cannot be loaded (error initializing the service)

        @note
        - identical to @ref rest_api_PUT_services__id_or_name__load and @ref rest_api_PUT_services__id_or_name__start
    */
    hash<auto> putInit(hash<auto> cx, *hash<auto> ah) {
        return putLoad(cx, ah);
    }

    /** @REST PUT action=stop

        Unloads the current service from the system.  If the service is running, it is first stopped.  Additionally, any outstanding method calls must return before the service can be unloaded.

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-NOT-LOADED: this exception is thrown when the service is not loaded

        @note
        - identical to @ref rest_api_PUT_services__id_or_name__unload
    */
    hash<auto> putStop(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s %s v%s (%d))", sh.type, sh.name, sh.version, sh.serviceid);

        # check if the service is loaded before trying to unload it
        if (sh.status != "unloaded")
            return RestHandler::makeResponse(200, api.("omq." + sh.type + ".delete-service")(sh.name));
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=unload

        Unloads the current service from the system.  If the service is running, it is first stopped.  Additionally, any outstanding method calls must return before the service can be unloaded.

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-NOT-LOADED: this exception is thrown when the service is not loaded

        @note
        - identical to @ref rest_api_PUT_services__id_or_name__stop
    */
    hash<auto> putUnload(hash<auto> cx, *hash<auto> ah) {
        return putStop(cx, ah);
    }

    /** @REST PUT action=enable

        @par Description
        Enables the current service if it is disabled.

        @par Return Value
        This API returns a hash with the following keys:
        - \c type: the service type one of:
          - \c "system": for system services
          - \c "user": for user services
        - \c name: the service name
        - \c version: the service version
        - \c serviceid: the service ID
        - \c info: info about the service enable action

        @note
        - if the service is already enabled, the action is reported as successful anyway
     */
    hash<auto> putEnable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s %s v%s (%d))", sh.type, sh.name, sh.version, sh.serviceid);

        Qorus.rbac.enableSyntheticGroup("service", sh.serviceid);
        hash<auto> h = sh.("type", "name", "version", "serviceid") + {
            "info": sprintf("enabled %s service %s v%s (%d)", sh.type, sh.name, sh.version, sh.serviceid),
        };
        return RestHandler::makeResponse(200, h);
    }

    /** @REST PUT action=disable

        @par Description
        Disables the current service.

        @par Return Value
        This API returns a hash with the following keys:
        - \c type: the service type one of:
          - \c "system": for system services
          - \c "user": for user services
        - \c name: the service name
        - \c version: the service version
        - \c serviceid: the service ID
        - \c info: info about the service disable action

        @note
        - if the service is already disabled, the action is reported as successful anyway
     */
    hash<auto> putDisable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s %s v%s (%d))", sh.type, sh.name, sh.version, sh.serviceid);

        # issue #3358: do not return until the interface has been disabled
        Qorus.rbac.disableSyntheticGroupWait("service", sh.serviceid);
        hash<auto> h = sh.("type", "name", "version", "serviceid") + {
            "info": sprintf("disabled %s service %s v%s (%d)", sh.type, sh.name, sh.version, sh.serviceid),
        };
        return RestHandler::makeResponse(200, h);
    }

    /** @REST PUT

        @par Description
        Performs a single update of the service and returns the value for that update.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c autostart: changes the autostart value (see @ref rest_api_PUT_services__id_or_name__setAutostart)
        - \c reset: reloads the service (see @ref rest_api_PUT_services__id_or_name__reset)
        - \c status: performs the actions listed below depending on the value of the \c status argument as follows:
          - \c "loaded": performs a load (see @ref rest_api_PUT_services__id_or_name__load)
          - \c "stopped": unloads the service (see @ref rest_api_PUT_services__id_or_name__unload)
        - \c enabled: performs the actions listed below depending on the value of the \c enabled argument as follows:
          - @ref True "True": enables the service (see @ref rest_api_PUT_services__id_or_name__enable)
          - @ref False "False": disables the service (see @ref rest_api_PUT_services__id_or_name__disable)
        .
        Note that if multiple arguments are passed, only the first recognized argument is processed in the order listed above.

        @par Return Value
        This API returns return values depending on the arguments; see the links above for more information

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: invalid or missing arguments to REST call

        @note permissions are required depending on the arugments used; see links in the argument section for more information
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        if (exists ah.autostart)
            return putSetAutostart(cx, ah);

        if (ah.reset)
            return putReset(cx, ah);

        if (ah.status){
            if (ah.status == "loaded") {
                return putLoad(cx, ah);
            } else if (ah.status == "stopped")
                return putStop(cx, ah);
        }

        if (exists ah.enabled)
            return parse_boolean(ah.enabled) ? putEnable(cx, ah) : putDisable(cx, ah);

        return RestHandler::make400("invalid arguments in REST call on %s service %s v%s serviceid %d: unknown arguments: %y", sh.type, sh.name, sh.version, sh.serviceid, cx.body);
    }

    private AbstractRestStreamRequestHandler doStream(hash<auto> cx, *hash<auto> ah) {
        if (!ah.stream || ah.stream.typeCode() != NT_STRING)
            throw "STREAM-ERROR", "missing \"stream\" argument for the stream to return";
        return services.getStreamHandler(sh.type, sh.name, remove ah.stream, cx, ah);
    }

    /** @REST GET action=stream

        @par Description
        Opens a \c GET stream for the named stream if the service implements that stream.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c stream: (required) the name of the stream to open

        @par Return Value
        See documentation for the stream implemented by the service.
    */
    AbstractRestStreamRequestHandler streamGetStream(hash<auto> cx, *hash<auto> ah) {
        return doStream(cx, ah);
    }

    /** @REST PUT action=stream

        @par Description
        Opens a \c PUT stream for the named stream if the service implements that stream.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c stream: (required) the name of the stream to open

        @par Return Value
        See documentation for the stream implemented by the service.
    */
    AbstractRestStreamRequestHandler streamPutStream(hash<auto> cx, *hash<auto> ah) {
        return doStream(cx, ah);
    }

    /** @REST POST action=stream

        @par Description
        Opens a \c POST stream for the named stream if the service implements that stream.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c stream: (required) the name of the stream to open

        @par Return Value
        See documentation for the stream implemented by the service.
    */
    AbstractRestStreamRequestHandler streamPostStream(hash<auto> cx, *hash<auto> ah) {
        return doStream(cx, ah);
    }

    /** @REST DELETE action=stream

        @par Description
        Opens a \c DELETE stream for the named stream if the service implements that stream.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c stream: (required) the name of the stream to open

        @par Return Value
        See documentation for the stream implemented by the service.
    */
    AbstractRestStreamRequestHandler streamDeleteStream(hash<auto> cx, *hash<auto> ah) {
        return doStream(cx, ah);
    }
}

/** @REST /services

    This REST URI path provides actions and information related to Qorus services.
*/
class ServiceRestClass inherits QorusRestClass {
    string name() {
        return "services";
    }

    static softlist listAllServices() {
        return api."omq.system.list-all-services"();
    }

    private static *auto staticGetServices(hash<auto> cx, *hash<auto> ah, int apiver, *hash<auto> filter) {
        *hash<auto> smh = Qorus.qmm.getServiceMap();
        *hash<auto> lsh = services.getCacheHash(cx);

        bool fr = (ah.status == "running");

        list<hash<auto>> rv = ();

        # add loaded & visible services to list
        foreach hash<auto> sh in (lsh.iterator()) {
            # filter by status if necessary
            if (fr && sh.status != "running") {
                continue;
            }

            # convert service options to a list
            softlist options = map (
                "name": $1.key,
                "desc": omq_option_hash{$1.key}.desc,
                "value": $1.value,
            ), (remove sh."runtime-options").pairIterator();
            sh.options = options;

            # add library and ws log URL
            rv += sh + {
                "lib": smh.(sh.serviceid).lib,
                "log_url": get_log_url(cx, "services/%d", sh.serviceid),
            };
        }

        # add unloaded services to list
        foreach hash<auto> sh in (smh.iterator()) {
            # skip services that are not the latest version
            if (!sh.latest) {
                continue;
            }
            # skip services that are already loaded
            if (lsh.(sh.serviceid)) {
                continue;
            }

            if (ah.status && ah.status != "unloaded") {
                continue;
            }

            hash<auto> mh = {
                "type": sh.type,
                "name": sh.name,
                "version": sh.version,
                "desc": sh.description,
                "serviceid": sh.serviceid,
                "status": "unloaded",
                "autostart": sh.autostart,
                "remote": sh.remote,
                "methods": (map ("name": $1.name, "desc": $1.description), sh.methods.iterator()),
                "groups": sh.groups,
                "resource_files": sh.resources,
                "alerts": Qorus.alerts.getAlerts("SERVICE", sh.serviceid),
                "enabled": Qorus.rbac.getSyntheticGroupStatus("service", sh.serviceid),
                "lib": sh.lib,
            };

            if (apiver >= 5) {
                mh.tags = sh.tags;
            }

            rv += mh;
        }

        if (filter) {
            rv = QorusMapManager::filterList(rv, filter);
        }

        if (exists ah."list" && parse_boolean(ah."list")) {
            return (map $1.name, rv);
        }

        if (exists ah.short && parse_boolean(ah.short)) {
            return (map sprintf("%s %s v%s (%d): %s", $1.type.upr(), $1.name, $1.version, $1.serviceid, $1.status), rv);
        }

        if (apiver < 3) {
            # remote "remote" attribute from services
            rv = map $1 - "remote", rv;
        } else {
            foreach hash<auto> sh in (\rv) {
                sh.config = smh{sh.serviceid}.config;
                Qorus.qmm.fillConfigItemValues("service", sh.serviceid, \sh);
            }
        }

        Qorus.httpServer.logInfo(sprintf("ServiceRestClass::staticGetServices() apiver: %y filter: %y", apiver, filter));

        if (apiver > 1) {
            # add SLA information to service methods
            if (rv && (*hash<string, hash<string, int>> smsh = Qorus.qmm.getServiceMethodSlaHash())) {
                *hash<string, hash<SlaInfo>> slam = Qorus.qmm.getSlaMap();
                foreach hash<auto> sh in (\rv) {
                    if (*hash<string, int> mh = smsh{sh.serviceid}) {
                        foreach hash<auto> mmh in (\sh.methods) {
                            if ((*int slaid = mh{mmh.name}) && (*string sla_name = slam{slaid}.name)) {
                                mmh.sla = sla_name;
                            }
                        }
                    }
                }
            }
        }

        return Qorus.alerts.getAlerts("SERVICE",
            Qorus.connDeps.getConnections("SERVICE", Qorus.rbac.addServiceStatus(rv), "serviceid"), "serviceid");
    }

    static *hash<auto> staticGetRuntimeServiceInfo(hash<auto> cx, softint id, *int apiver) {
        *hash<auto> h = qorus_api_svc_get_service_info_as_current_user(id, cx);
        if (!h) {
            return {
                "status": "unloaded",
            };
        }
        if (apiver > 3) {
            h = h{"status", "threads", "resources", "processes"};
            if (apiver < 6) {
                h.process = remove h.processes[0];
            }
        } else {
            h = h{"status", "threads", "resources"};
        }

        return h{"status", "threads", "resources", "processes"} + {
            "log_url": get_log_url(cx, "services/%d", id),
        };
    }

    static *hash<auto> staticGetService(hash<auto> cx, softint id, *hash<auto> ah, int apiver) {
        *hash<auto> sh = Qorus.qmm.lookupService(id, True);
        if (!sh) {
            return;
        }

        if (exists ah.lib_source && parse_boolean(ah.lib_source)) {
            sh.lib = get_library_source(sh.lib);
        }

        if (apiver < 3 || !sh.class_based) {
            remove sh.class_source;
        }

        if (!ah.method_source || !parse_boolean(ah.method_source)) {
            map remove sh.methods{$1}.body, keys sh.methods;
        }

        # remove language and class_based from API < 3
        if (apiver < 3) {
            sh -= ("language", "class_based", "config");
        }

        # reformat methods as a list and fix methods tags
        sh.methods = map FunctionRestClass::moveTags(sh.methods.$1), keys sh.methods;

        # rename resources to resource_files
        sh.resource_files = remove sh.resources;

        if (exists ah.with_resources && parse_boolean(ah.with_resources)) {
            list<hash<auto>> l = ();

            *list<auto> ql;
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    on_error omqp.rollback();

                    ql = omqp.selectRows("select name, resource_type as type, body from service_file_resources where "
                        "serviceid = %v", sh.serviceid);
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

            foreach hash<auto> rh in (ql) {
                if (rh.resource_type != "B") {
                    rh.body = rh.body.toString();
                }
                l += rh;
            }

            sh.resource_files = l;
        }

        if (apiver > 1) {
            if (sh && (*hash<string, int> mh = Qorus.qmm.getServiceMethodSlaHash(){id})) {
                *hash<string, hash<SlaInfo>> slam = Qorus.qmm.getSlaMap();
                foreach hash<auto> mmh in (\sh.methods) {
                    if ((*int slaid = mh{mmh.name}) && (*string sla_name = slam{slaid}.name)) {
                        mmh.sla = sla_name;
                    }
                }
            }
        }
        if (apiver >= 3) {
            Qorus.qmm.fillConfigItemValues("service", sh.serviceid, \sh);
        } else {
            sh -= ("config",);
        }

        sh.apiver = apiver;

        *hash<auto> rt_opts = remove sh."runtime-options";
        {
            # reformat options in a single list of hashes with configured and runtime values
            hash<auto> sys_opts;
            map sys_opts.($1.key).desc = $1.value, sh.options.pairIterator();
            map sys_opts.($1.key).value = $1.value, rt_opts.pairIterator();
            sh.options = map ("name": $1) + sys_opts.$1, keys sys_opts;
            if (!sh.options) {
                sh.options = ();
            }
        }

        return sh + ServiceRestClass::staticGetRuntimeServiceInfo(cx, id, apiver) + {
            "connections": Qorus.connDeps.getConnections("SERVICE", id),
            "alerts": Qorus.alerts.getAlerts("SERVICE", id),
            "enabled": Qorus.rbac.getSyntheticGroupStatus("service", id),
        };
    }

    static softint staticGetServiceId(softstring arg, bool check = False, *reference sh) {
        if (arg =~ /[[:alpha:]]/u) {
            # try to find version
            *string ver;
            if ((int i = arg.find(":")) != -1) {
                ver = extract arg, i + 1;
                splice arg, -1;
            }
            if (ver) {
                if (int serviceid = Qorus.qmm.rLookupService("system", arg, ver)
                    ?? Qorus.qmm.rLookupService("user", arg, ver)
                    ?? 0) {
                    return serviceid;
                }
            } else {
                *hash<auto> h = Qorus.qmm.rLookupService("system", arg);
                if (!h)
                    h = Qorus.qmm.rLookupService("user", arg);
                if (h) {
                    sh = Qorus.qmm.lookupService(h.serviceid, True);
                    return h.serviceid;
                }
            }

            if (check)
                throw "SERVICE-ERROR", sprintf("can't find any service %y", ver.val() ? sprintf("%s:%s", arg, ver) : arg);

            return 0;
        }

        if (check) {
            *hash<auto> h = Qorus.qmm.lookupService(arg, True);
            if (!h)
                throw "SERVICE-ERROR", sprintf("there is no service with serviceid %d", arg);
            sh = h;
        }

        return arg;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = ServiceRestClass::staticGetServiceId(arg);
        *hash<auto> svc = ServiceRestClass::staticGetService(cx, id, ah, 1);
        if (!svc)
            return;

        return new ServiceDefinitionRestClass(svc);
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
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ServiceRestClass::staticGetServices(cx, ah, 1));
    }

    /** @REST PUT action=load

        @par Description
        Loads and initializes one or more services if not already loaded.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more service names or IDs to start; a comma-separated string will be split into a list

        @par Return Value
        This API returns a list of hashes giving the result of each load request; each hash has the following keys:
        - \c arg: the service ID or name (argument for the load operation)
        - \c loaded: a boolean giving the result of the operation
        - [\c already_loaded]: (only present if \c loaded is @ref True) @ref True if the service was already loaded before this call, @ref False if loaded with this call
        - [\c serviceid]: the service ID
        - [\c type]: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        - [\c name]: the name of the service
        - [\c version]: the version of the service
        - \c info: information abouit the operation; if the operation failed, a formatted error string will appear here; possible failure reasons:
          - \c "SERVICE-ERROR": the given service cannot be loaded (does not exist, error initializing the service)

        @see
        - @ref rest_api_PUT_services_unload
        - @ref rest_api_PUT_services__id_or_name__load
        - @ref rest_api_PUT_services__id_or_name__unload
    */
    hash<auto> putLoad(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "SERVICE-LOAD-ERROR", "missing \"ids\" argument for service IDs to load";

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        list rv = ();

        # permission check hash
        hash<auto> pch;

        foreach auto arg in (ah.ids) {
            *hash<auto> sh;
            int id = ServiceRestClass::staticGetServiceId(arg, False, \sh);
            if (!id) {
                rv += ("arg": arg, "loaded": False, "info": "unknown service");
                continue;
            }

            try {
                if (!sh) {
                    sh = Qorus.qmm.lookupService(id, True);
                    if (!sh) {
                        rv += ("arg": arg, "loaded": False, "info": sprintf("SERVICE-ERROR: serviceid %d is unknown", id));
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
                    "info": sprintf("%s %s v%s (%d) %sloaded", sh.type, sh.name, sh.version, id, sih ? "was already " : ""),
                };
            } catch (hash<ExceptionInfo> ex) {
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

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=resetAll

        @par Description
        Unloads all services currently loaded in memory and reloads them from the database

        @par Return Value
        This API returns a list of hashes listing all services reset; each hash has the following keys:
        - \c type: the type of service reset; one of:
          - \c "system": for system services
          - \c "user": for user services
        - \c name: name of the service

        @see
        - @ref rest_api_PUT_services_reset
        - @ref rest_api_PUT_services_resetSystem
        - @ref rest_api_PUT_services_resetUser
        - @ref rest_api_PUT_services__id_or_name__reset
        - omq.system.reset-all-services()
        - omq.system.reset-services()
        - omq.system.reset-service()
        - omq.user.reset-services()
        - omq.user.reset-service()
    */
    hash<auto> putResetAll(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # service access is checked in the ServiceManager call
        list l = services.reloadAll(cx);
        return RestHandler::makeResponse(200, l);
    }

    /** @REST PUT action=resetSystem

        @par Description
        Unloads all system services currently loaded in memory and reloads them from the database.

        @par Return Value
        This API returns a list of hashes listing all services reset; each hash has the following keys:
        - \c type: the type of service reset; always "system" for this call
        - \c name: name of the service

        @see
        - @ref rest_api_PUT_services_reset
        - @ref rest_api_PUT_services_resetAll
        - @ref rest_api_PUT_services_resetUser
        - @ref rest_api_PUT_services__id_or_name__reset
        - omq.system.reset-all-services()
        - omq.system.reset-services()
        - omq.system.reset-service()
        - omq.user.reset-services()
        - omq.user.reset-service()
    */
    hash<auto> putResetSystem(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        list l = services.reloadServices(cx, "system");
        return RestHandler::makeResponse(200, l);
    }

    /** @REST PUT action=resetUser

        @par Description
        Unloads all user services currently loaded in memory and reloads them from the database

        @par Return Value
        This API returns a list of hashes listing all services reset; each hash has the following keys:
        - \c type: the type of service reset; always "user" for this call
        - \c name: name of the service

        @see
        - @ref rest_api_PUT_services_reset
        - @ref rest_api_PUT_services_resetAll
        - @ref rest_api_PUT_services_resetSystem
        - @ref rest_api_PUT_services__id_or_name__reset
        - omq.system.reset-all-services()
        - omq.system.reset-services()
        - omq.system.reset-service()
        - omq.user.reset-services()
        - omq.user.reset-service()
    */
    hash<auto> putResetUser(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # service access is checked in the ServiceManager call
        list l = services.reloadServices(cx, "user");
        return RestHandler::makeResponse(200, l);
    }

    static list resetServices(hash<auto> cx, softlist ids, *bool load) {
        list rv = ();

        foreach any arg in (ids) {
            *hash<auto> sh;
            int id = ServiceRestClass::staticGetServiceId(arg, False, \sh);
            if (!id) {
                rv += ("arg": arg, "reset": False, "info": "unknown service");
                continue;
            }

            if (!sh) {
                sh = Qorus.qmm.lookupService(id, True);
                if (!sh) {
                    rv += ("arg": arg, "reset": False, "info": sprintf("SERVICE-ERROR: serviceid %d is unknown", id));
                    continue;
                }
            }

            # see if the service is loaded
            *hash<auto> sih = UserApi::getServiceInfo(sh.type, sh.name);

            hash<auto> ih = {
                "arg": arg,
                "loaded": boolean(sih),
                "serviceid": id,
                "type": sh.type,
                "name": sh.name,
                "version": sh.version,
            };

            try {
                if (!sih && !load && !sh.autostart) {
                    ih += {
                        "reset": False,
                        "info": sprintf("%s %s v%s (%d) is not loaded", sh.type, sh.name, sh.version, id),
                    };
                } else {
                    services.reloadService(cx, sh.type, sh.name, load);
                    ih += {
                        "reset": True,
                        "info": sprintf("%s %s v%s (%d) was reset", sh.type, sh.name, sh.version, id),
                    };
                }
            } catch (hash<ExceptionInfo> ex) {
                string msg = sprintf("%s: %s", ex.err, ex.desc);
                qlog(LoggerLevel::INFO, "error resetting %s service %s v%s (%d): %s", sh.type, sh.name, sh.version, id,
                    Qorus.getDebugSystem() ? get_exception_string(ex) : msg);
                ih += {
                    "reset": False,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                };
            }
            rv += ih;
        }

        return rv;
    }

    /** @REST PUT action=reset

        @par Description
        Resets one or more services and reloads them from the database.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more service names or IDs to reload; a comma-separated string will be split into a list
        - \c load: (optional) will be evaluated with @ref Qore::parse_boolean(); if @ref True then services not already loaded will be loaded with this call; default @@ref False, meaning that services not already loaded will not be loaded by this call

        @par Return Value
        This API returns a list of hashes giving the result of each reset request; each hash has the following keys:
        - \c arg: the service ID or name (argument for the load operation)
        - [\c loaded]: @ref True if the service was already loaded before this call, @ref False if loaded with this call
        - [\c reset]: @ref True if the service was (re)loaded
        - [\c serviceid]: the service ID
        - [\c type]: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        - [\c name]: the name of the service
        - [\c version]: the version of the service
        - \c info: information abouit the operation; if the operation failed, a formatted error string will appear here; possible failure reasons:
          - \c "SERVICE-ERROR": the given service cannot be loaded (does not exist, error initializing the service)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-RESET-ERROR: missing \c ids argument

        @see
        - @ref rest_api_PUT_services_resetAll
        - @ref rest_api_PUT_services_resetSystem
        - @ref rest_api_PUT_services_resetUser
        - @ref rest_api_PUT_services__id_or_name__reset
        - omq.system.reset-all-services()
        - omq.system.reset-services()
        - omq.system.reset-service()
        - omq.user.reset-services()
        - omq.user.reset-service()
    */
    hash<auto> putReset(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "SERVICE-RESET-ERROR", "missing \"ids\" argument for service IDs to reset";

        rlog(cx);

        ah.load = exists ah.load ? parse_boolean(ah.load) : False;

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        return RestHandler::makeResponse(200, resetServices(cx, ah.ids, ah.load));
    }

    /** @REST PUT action=unload

        @par Description
        Unloads one or more services from the system.  If the service is running, then it is first stopped.  Additionally, for each service to be unloaded, any outstanding method calls must return before the service can be unloaded.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more service names or IDs to unload; a comma-separated string will be split into a list

        @par Return Value
        This API returns a list of hashes giving the result of each unload request; each hash has the following keys:
        - \c arg: the service ID or name (argument for the unload operation)
        - [\c loaded]: @ref True if the service was already loaded, @ref False if not
        - [\c unloaded]: @ref True if the service was unloaded, @ref False if not
        - [\c serviceid]: the service ID
        - [\c type]: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        - [\c name]: the name of the service
        - [\c version]: the version of the service
        - \c info: information abouit the operation; if the operation failed, a formatted error string will appear here; possible failure reasons:
          - \c "SERVICE-ERROR": the given service cannot be loaded (does not exist, error initializing the service)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-UNLOAD-ERROR: missing \c ids argument

        @see
        - @ref rest_api_PUT_services_load
        - @ref rest_api_PUT_services__id_or_name__load
        - @ref rest_api_PUT_services__id_or_name__unload
    */
    hash<auto> putUnload(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "SERVICE-UNLOAD-ERROR", "missing \"ids\" argument for service IDs to unload";

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        list rv = ();

        foreach auto arg in (ah.ids) {
            *hash<auto> sh;
            int id = ServiceRestClass::staticGetServiceId(arg, False, \sh);
            if (!id) {
                rv += ("arg": arg, "unloaded": False, "info": "unknown service");
                continue;
            }

            if (!sh) {
                sh = Qorus.qmm.lookupService(id, True);
                if (!sh) {
                    rv += ("arg": arg, "unloaded": False, "info": sprintf("SERVICE-ERROR: serviceid %d is unknown", id));
                    continue;
                }
            }

            # see if the service is loaded
            *hash<auto> sih = UserApi::getServiceInfo(sh.type, sh.name);

            hash<auto> ih = {
                "arg": arg,
                "loaded": boolean(sih),
                "serviceid": id,
                "type": sh.type,
                "name": sh.name,
                "version": sh.version,
            };

            try {
                if (!sih) {
                    ih += {
                        "unloaded": False,
                        "info": sprintf("%s %s v%s (%d) is not loaded", sh.type, sh.name, sh.version, id),
                    };
                } else {
                    services.unloadService(sh.type, sh.name, sh.version);
                    ih += {
                        "stopped": True,
                        "info": sprintf("%s %s v%s (%d) was stopped/unloaded", sh.type, sh.name, sh.version, id),
                    };
                }
            } catch (hash<ExceptionInfo> ex) {
                ih += {
                    "unloaded": False,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                };
            }
            rv += ih;
        }

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=enable

        @par Description
        Enables one or more disabled services.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more service names or IDs to enable; a comma-separated string will be split into a list

        @par Return Value
        This API returns a list of hashes; each hash has the following keys:
        - \c arg: the service ID or name
        - \c enabled: @ref True or @ref False
        - [\c serviceid]: the service ID
        - [\c type]: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        - [\c name]: the service name
        - [\c version]: the service version
        - \c info: info about the service enable action or a reason why the request failed; possible failure reasons:
          - \c "SERVICE-ERROR": unknown service

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-ENABLE-ERROR: missing \c ids argument

        @see
        - @ref rest_api_PUT_services_disable
        - @ref rest_api_PUT_services__id_or_name__enable
        - @ref rest_api_PUT_services__id_or_name__disable
     */
    hash<auto> putEnable(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "SERVICE-ENABLE-ERROR", "missing \"ids\" argument for service IDs to enable";

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        list rv = ();

        # permission check hash
        hash<auto> pch;

        foreach any arg in (ah.ids) {
            *hash<auto> sh;
            int id;
            try {
                id = ServiceRestClass::staticGetServiceId(arg, True, \sh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "enabled": False, "info": "SERVICE:ERROR: unknown service");
                continue;
            }

            try {
                Qorus.rbac.enableSyntheticGroup("service", id);
                rv += (
                    "arg": arg,
                    "enabled": True,
                    "serviceid": id,
                    "type": sh.type,
                    "name": sh.name,
                    "version": sh.version,
                    "info": sprintf("%s %s v%s (%d) enabled", sh.type, sh.name, sh.version, id),
                    );
            } catch (hash<ExceptionInfo> ex) {
                rv += (
                    "arg": arg,
                    "enabled": False,
                    "serviceid": id,
                    "type": sh.type,
                    "name": sh.name,
                    "version": sh.version,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                    );
            }
        }

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=disable

        @par Description
        Disables one or more services.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more service names or IDs to disable; a comma-separated string will be split into a list

        @par Return Value
        This API returns a list of hashes; each hash has the following keys:
        - \c arg: the service ID or name
        - \c disabled: @ref True or @ref False
        - [\c serviceid]: the service ID
        - [\c type]: the type of the service; one of:
          - \c "system": for system services
          - \c "user": for user services
        - [\c name]: the service name
        - [\c version]: the service version
        - \c info: info about the service enable action or a reason why the request failed; possible failure reasons:
          - \c "SERVICE-ERROR": unknown service

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-DISABLE-ERROR: missing \c ids argument

        @see
        - @ref rest_api_PUT_services_enable
        - @ref rest_api_PUT_services__id_or_name__enable
        - @ref rest_api_PUT_services__id_or_name__disable
     */
    hash<auto> putDisable(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "SERVICE-DISABLE-ERROR", "missing \"ids\" argument for service IDs to disable";

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        list rv = ();

        # permission check hash
        hash<auto> pch;

        foreach any arg in (ah.ids) {
            *hash<auto> sh;
            int id;
            try {
                id = ServiceRestClass::staticGetServiceId(arg, True, \sh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "disabled": False, "info": "SERVICE-ERROR: unknown service");
                continue;
            }

            try {
                # issue #3358: do not return until the interface has been disabled
                Qorus.rbac.disableSyntheticGroupWait("service", id);
                rv += {
                    "arg": arg,
                    "disabled": True,
                    "serviceid": id,
                    "type": sh.type,
                    "name": sh.name,
                    "version": sh.version,
                    "info": sprintf("%s %s v%s (%d) enabled", sh.type, sh.name, sh.version, id),
                };
            } catch (hash<ExceptionInfo> ex) {
                rv += {
                    "arg": arg,
                    "disabled": False,
                    "serviceid": id,
                    "type": sh.type,
                    "name": sh.name,
                    "version": sh.version,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                };
            }
        }

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST GET action=list

        @par Description
        Returns a list of services hashes according to the arguments passed.

        @see This API is equivalent to @ref rest_api_GET_services__id_or_name_; see that documentation for details.
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }
}

/** @REST /jobresults/{id}

    This REST API path provides actions and information about specific job results (job instances).
*/
class JobResultRestClass inherits QorusRestClass {
    private {
        hash<auto> jh;
    }

    constructor(hash<auto> v_jh) {
        jh = v_jh;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (jh.hasKey(arg))
                return new AttributeRestClass(jh{arg});
        }
    }

    softstring name() {
        return jh.jobid;
    }

    /** @REST GET

        @par Description
        Returns a hash of job result (job instance) information

        @par Return Value
        This API returns a @ref rest_job_result_hash with the following additional keys:
        - \c errors: a list of hashes of errors and warnings raised by the job; each list element has the following keys:
          - \c job_errorid: the unique ID for the error instance
          - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
          - \c error: the error code string
          - \c description: description for the error (if any)
          - \c info: additional information about the error (if any)
          - \c business_error: a boolean flag indicating of the error is a business error
          - \c created: the date and time the error was raised
        - \c audit: a list of one or more @ref rest_audit_info_hash elements (can be empty)
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        return RestHandler::makeResponse(200, jh);
    }
}

/** @REST /jobresults

    This REST API path provides actions and information about job results (job instances).
*/
class JobResultsRestClass inherits QorusRestClass {
    string name() {
        return "jobresults";
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = sysinfo.getJobStatus(id);
        if (h)
            return new JobResultRestClass(h);
    }

    /** @REST GET action=overview

        @par Description
        Returns aggregate job result information corresponding to the arguments.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c date: optional (parsed as a date); the past cutoff date for the search; only orders with a \c modified date equal or after this date will be considered; if not present, then defaults to the last 24 hours
        - \c sqlcache: optional (parsed with @ref Qore::parse_boolean()); if @ref False then no SQL cache will be used for historical info; default @ref True
        - \c combined: if @ref True then all results are combined into one global hash for all queried jobs
        - \c jobs: one or more job names or IDs to filter the result list; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash keyed by job name; values are hashes keyed by job status value (see @ref JobStatusDescriptions for possible values) and the values are integer job result (job instance) counts having the given status (unless \c combined is set, described above)

        @par Example Return Value
        @verbatim
myjob_1 : hash: (2 members)
  ERROR : 1
  COMPLETE : 3
myjob_2 : hash: (2 members)
  IN-PROGRESS : 1
  COMPLETE : 8
        @endverbatim
    */
    hash<auto> getOverview(hash<auto> cx, *hash<auto> ah){
        ah.date = ah.date ? date(ah.date) : now() - 1D;
        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;

        *hash<auto> h = sysinfo.getJobOverview(ah.date, NOTHING, ah.sqlcache);

        #log(LoggerLevel::DEBUG, "JobResultsRestClass::getOverview() h: %N", h);

        if (ah.combined)
            ah.combined = parse_boolean(ah.combined);

        # filter by specific jobs if necessary
        hash<auto> jfh;
        if (ah.jobs) {
            if (ah.jobs.typeCode() == NT_STRING)
                ah.jobs = ah.jobs.split(",");
            map jfh.(JobRestClass::staticGetJobId($1)) = True, ah.jobs;
        }

        if (ah.combined) {
            *hash<auto> jh;
            foreach hash<auto> jrh in (h.iterator()) {
                jrh -= ("jobid", "version");
                map jh.$1 += jrh.$1, keys jrh;
            }
            h = jh;
        }
        else
            map h.$1 -= ("jobid", "version"), keys h;

        #log(LoggerLevel::DEBUG, "JobResultsRestClass::getOverview() h (%s): %N", h.type(), h);
        return RestHandler::makeResponse(200, h);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of job result (job instance) information corresponding to the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c date: optional (parsed as a date); the past cutoff date for the search; only orders with a \c modified date equal or after this date will be considered; if not present, then defaults to the last 24 hours
        - \c desc: optional (parsed with @ref Qore::parse_boolean(); determines the sort order; if @ref False then results are sorted in ascending order, if @ref True (the default), results are sorted in descending order (newest first)
        - \c full: optional (parsed with @ref Qore::parse_boolean(); if @ref True then additional keys are included in each result record; see below for details
        - \c ids: optional; one or more job IDs to filter the result list; a comma-separated string will be split into a list
        - \c limit: optional; limits the number of results returned
        - \c offset: optional; the starting result to return (use when paging for example)
        - \c sort: optional; a list of columns to sort the output by
        - \c statuses: optional; job result (job instance) status value(s); a comma-separated string will be split into a list (see @ref JobStatusDescriptions for possible values)

        @par Return Value
        This API returns a list of @ref rest_job_result_hash elements corresponding to the arguments; if the \c full option is set, then the following additional keys are included in each hash:
        - \c errors: a list of hashes of errors and warnings raised by the job; each list element has the following keys:
          - \c job_errorid: the unique ID for the error instance
          - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
          - \c error: the error code string
          - \c description: description for the error (if any)
          - \c info: additional information about the error (if any)
          - \c business_error: a boolean flag indicating of the error is a business error
          - \c created: the date and time the error was raised
        - \c audit: a list of one or more @ref rest_audit_info_hash elements (can be empty)
    */
    # takes options date=<date>,statuses=<list of statuses>,limit=<max results to return>,offset=<starting row>,sort=<sort key>,desc=<boo>,full=<bool>
    # defaults:
    # - desc: True
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        ah.date = ah.date ? date(ah.date) : now() - 1D;
        # make into a list
        if (ah.statuses && ah.statuses.typeCode() == NT_STRING) {
            ah.statuses = ah.statuses.upr();
            ah.statuses = ah.statuses.split(",");
        }
        if (ah.sort && ah.sort.typeCode() == NT_STRING)
            ah.sort = ah.sort.split(",");
        if (exists ah.desc)
            ah.desc = parse_boolean(ah.desc);
        else
            ah.desc = True;
        if (ah.full)
            ah.full = parse_boolean(ah.full);
        if (ah.ids && ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        return RestHandler::makeResponse(200, sysinfo.getJobInstances(ah.ids, ah.statuses, ah.date, ah.limit, ah.offset, ah.sort, NOTHING, ah.desc, ah.full));
    }
}

/** @REST /jobs/{id_or_name}/results

    This REST API path provides actions and information related to the results of specific jobs.
*/
class JobSpecificResultsRestClass inherits QorusRestClass {
    private {
        hash<auto> jh;
    }

    constructor(hash<auto> v_jh) {
        jh = v_jh;
    }

    string name() {
        return jh.name;
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = sysinfo.getJobStatus(id);
        if (h)
            return new JobResultRestClass(h);
    }

    /** @REST GET action=overview

        @par Description
        Returns aggregate job result information for the current job corresponding to the arguments.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c date: optional (parsed as a date); the past cutoff date for the search; only orders with a \c modified date equal or after this date will be considered; if not present, then defaults to the last 24 hours
        - \c sqlcache: optional (parsed with @ref Qore::parse_boolean()); if @ref False then no SQL cache will be used for historical info; default @ref True
        - \c combined: if @ref True then all results are combined into one global hash for all queried jobs

        @par Return Value
        This API returns a hash keyed by job name; values are hashes keyed by job status value (see @ref JobStatusDescriptions for possible values) and the values are integer job result (job instance) counts having the given status (unless \c combined is set, described above)

        @par Example Return Value
        @verbatim
myjob_1 : hash: (2 members)
  ERROR : 1
  COMPLETE : 3
myjob_2 : hash: (2 members)
  IN-PROGRESS : 1
  COMPLETE : 8
        @endverbatim
    */
    hash<auto> getOverview(hash<auto> cx, *hash<auto> ah){
        ah.date = ah.date ? date(ah.date) : now() - 1D;
        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;

        *hash<auto> h = sysinfo.getJobOverview(ah.date, jh.jobid, ah.sqlcache);

        #log(LoggerLevel::DEBUG, "JobResultsRestClass::getOverview() h: %N", h);

        if (ah.combined)
            ah.combined = parse_boolean(ah.combined);

        h = h ? h.firstValue() - ("jobid", "version") : {};

        #log(LoggerLevel::DEBUG, "JobResultsRestClass::getOverview() h (%s): %N", h.type(), h);
        return RestHandler::makeResponse(200, h);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of job result (job instance) information for the current job corresponding to the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c date: optional (parsed as a date); the past cutoff date for the search; only orders with a \c modified date equal or after this date will be considered; if not present, then defaults to the last 24 hours
        - \c desc: optional (parsed with @ref Qore::parse_boolean(); determines the sort order; if @ref False then results are sorted in ascending order, if @ref True (the default), results are sorted in descending order (newest first)
        - \c full: optional (parsed with @ref Qore::parse_boolean(); if @ref True then additional keys are included in each result record; see below for details
        - \c ids: optional; one or more job instance IDs to filter the result list; a comma-separated string will be split into a list
        - \c limit: optional; limits the number of results returned
        - \c offset: optional; the starting result to return (use when paging for example)
        - \c sort: optional; a list of columns to sort the output by
        - \c statuses: optional; job result (job instance) status value(s); a comma-separated string will be split into a list (see @ref JobStatusDescriptions for possible values)

        @par Return Value
        This API returns a list of @ref rest_job_result_hash elements corresponding to the arguments; if the \c full option is set, then the following additional keys are included in each hash:
        - \c errors: a list of hashes of errors and warnings raised by the job; each list element has the following keys:
          - \c job_errorid: the unique ID for the error instance
          - \c severity: an error severity code (see @ref ErrorSeverityCodes for possible values)
          - \c error: the error code string
          - \c description: description for the error (if any)
          - \c info: additional information about the error (if any)
          - \c business_error: a boolean flag indicating of the error is a business error
          - \c created: the date and time the error was raised
        - \c audit: a list of one or more @ref rest_audit_info_hash elements (can be empty)
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah){
        ah.date = ah.date ? date(ah.date) : now() - 1D;
        # make into a list
        if (ah.statuses && ah.statuses.typeCode() == NT_STRING) {
            ah.statuses = ah.statuses.upr();
            ah.statuses = ah.statuses.split(",");
        }
        if (ah.sort && ah.sort.typeCode() == NT_STRING)
            ah.sort = ah.sort.split(",");
        if (exists ah.desc)
            ah.desc = parse_boolean(ah.desc);
        else
            ah.desc = True;
        if (ah.full)
            ah.full = parse_boolean(ah.full);
        if (ah.ids && ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        return RestHandler::makeResponse(200, sysinfo.getJobInstances(jh.jobid, ah.statuses, ah.date, ah.limit,
            ah.offset, ah.sort, ah.ids, ah.desc, ah.full));
    }
}

class AttributeRestClass inherits QorusRestClass {
    private {
        any info;
        string key = "name";
    }

    constructor(auto info, *string key) {
        self.info = info;
        if (key) {
            self.key = key;
        }
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (info.typeCode() == NT_HASH) {
            if (info.hasKey(name))
                return new AttributeRestClass(info{name});
        } else if (info.typeCode() == NT_LIST && info[0].typeCode() == NT_HASH) {
            # try to find the element requested
            foreach hash<auto> h in (info) {
                if (h{key} == name)
                    return new AttributeRestClass(h - key);
            }
        }
    }

    softstring name() {
        return "attribute";
    }

    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, info);
    }

    hash<auto> putDescription(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, info);
    }
}

/** @REST /jobs/{id_or_name}

    This REST API path provides actions and information related to specific jobs;
    the name can also be provided in the format <tt><i>name</i>:<i>version</i></tt>.
*/
class JobDefinitionRestClass inherits QorusRestClass {
    private {
        hash<auto> jh;
    }

    hash<auto> getValues() {
        return jh;
    }

    constructor(hash<auto> v_jh) {
        jh = JobDefinitionRestClass::addScheduleInfo(v_jh);
    }

    static hash<auto> addScheduleInfo(hash<auto> jh) {
        if (jh.month) {
            return jh + {
                "sched_type": "cron",
                "sched_txt": sprintf("minutes: %s, hours: %s, days: %s, months: %s, wdays: %s", jh.minute, jh.hour,
                    jh.day, jh.month, jh.wday),
            };
        }
        return jh + {
            "sched_type": "recurring",
            "sched_txt": sprintf("every %d seconds", jh.recurring),
        };
    }

    softstring name() {
        return jh.name;
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (name == "results")
            return new JobSpecificResultsRestClass(jh);
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (jh.hasKey(name))
                return new AttributeRestClass(jh{name});
            if (name == "state")
                return new AttributeRestClass(retrieveState());
        }
    }

    /** @REST GET

        @par Description
        Returns a hash of job information

        @par Return Value
        Returns a @ref rest_job_description_hash for the current job, plus the following key:
        - \c state: a hash of job state data (if any)
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        jh.state = retrieveState();
        return RestHandler::makeResponse(200, jh);
    }

    private *hash<auto> retrieveState() {
        # get job state data, if any
        *string str;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                str = get_sql_table_system("omq", "job_state_data").selectRow({
                    "columns": "data",
                    "where": {
                        "jobid": jh.jobid,
                    },
                }).data;
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
        if (exists str) {
            return deserialize_qorus_data(str);
        }
    }

    /** @REST PUT action=setStateData

        @par Description
        Provides an API for externally updating job state data

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c data: a hash of new job state data or @ref nothing which will clear any data

        @par Return Value
        This API returns the new data or @ref nothing if the data is cleared

        @see
        - job_get_state_data()
        - job_save_state_data()
    */
    hash<HttpHandlerResponseInfo> putSetStateData(hash<auto> cx, *hash<auto> ah) {
        AbstractTable t = get_sql_table_system_trans("omq", "job_state_data");

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_success omqp.commit();
                on_error omqp.rollback();

                if (!exists ah.data)
                    t.del(("jobid": jh.jobid));
                else {
                    if (ah.data.typeCode() != NT_HASH)
                        throw "JOB-STATE-ERROR", sprintf("\"data\" argument is type %y (expecting %y)", ah.data.type(), Type::String);
                    string str = serialize_qorus_data(ah.data);
                    t.upsert(("jobid": jh.jobid, "data": str));
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

    /** @REST PUT action=run

        @SCHEMA
        @summary Runs a job and returns the results of job execution

        @desc Runs a job and returns the results of job execution

        @return (hash JobExecResultInfo): the result of job execution
        - job_instanceid (int): the job_instanceid
        - status (string): the status of the execution of the job; see \
          @ref JobStatusDescriptions for possible values

        @ENDSCHEMA

        @see omq.system.job.run()
     */
    hash<HttpHandlerResponseInfo> putRun(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        return RestHandler::makeResponse(200, Qorus.jobManager.runJobNow(jh.name));
    }

    /** @REST PUT action=reset

        @SCHEMA
        @summary Resets and reloads the current job

        @desc Resets and reloads the current job by reloading its configuration in the \
        metadata cache; if the job is currently running, then the reset will cause the job \
        configuration to be reset as soon as it completes its current run.

        @return (string): a descriptive string for the operation

        @error (409): \c API-CALL-ERROR: cannot reset a disabled job
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c API-CALL-ERROR: cannot reset a disabled job

        @see omq.system.job.reset()
    */
    hash<HttpHandlerResponseInfo> putReset(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        return RestHandler::makeResponse(200, Qorus.jobManager.resetJob(jh.name));
    }

    /** @REST PUT action=setActive

        @par Description
        Updates the "active" status of a job; if any errors occur an exception is thrown.
        This API works on all jobs regardless of state; the job does not have to be running or active to be updated.\n\n
        Updating a job to active will start the job immediately unless the expiry date is past or the job is a member of a disabled @ref rbacgroups "group".
        Changing a currently-active job to inactive will stop the job immediately

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c active: (required) parsed with @ref Qore::parse_boolean(); the active state of the job

        @par Return Value
        This API returns a hash with the following keys:
        - \c jobid: the job ID
        - \c name: the job name
        - \c active: the new active state of the job
        - \c info: a descriptive string; ex: <tt><b>jobid 7 "myjob1" is already active and running</b></tt>

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c JOB-ERROR: cannot set expired jobs to active

        @see omq.system.job.set-active()
    */
    hash<HttpHandlerResponseInfo> putSetActive(hash<auto> cx, *hash<auto> ah) {
        return handlePutSetActive(cx, ah);
    }

    /** @REST PUT action=setExpire

        @par Description
        Identical to @ref rest_api_PUT_jobs__id_or_name__setExpiry
    */
    hash<HttpHandlerResponseInfo> putSetExpire(*hash<auto> cx, *hash<auto> ah) {
        return putSetExpiry(cx, ah);
    }

    /** @REST PUT action=setExpiry

        @SCHEMA
        @summary Updates the active status of a job

        @desc Updates the expiry date of a job; if any errors occur an exception is thrown. \
        This API works on all jobs regardless of state; the job does not have to be running or active to be updated. \
        Removing the expiry date or setting a future expiry date from a job that is not started because it has \
        expired will result in the job starting immediately (unless the job is inactive or a member of a disabled \
        @ref rbacgroups "group". Setting a past expiry date on a currently-active job will stop the job immediately.

        @params
        - date (*date): the new expiry date of the job; if not present any expiry date will be removed

        @return (hash JobExpiryUpdateInfo): a hash of information about the update operation
        - jobid (int): the job ID
        - name (string): the job name
        - expiry_date (*date): the new expiry date of the job
        - info (string): a descriptive string
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putSetExpiry(*hash<auto> cx, *hash<auto> ah) {
        # permissions checked in RPC call
        rlog(cx);
        *date v_date = ah.date ? date(ah.date) : NOTHING;

        hash<auto> rv = {
            "jobid": jh.jobid,
            "name": jh.name,
            "expiry_date": v_date,
            "info": Qorus.jobManager.setJobExpiry(jh.name, v_date),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=schedule

        @SCHEMA
        @summary Updates the schedule of a job

        @desc Updates the schedule of a job; if any errors occur an exception is thrown. \
        This API works on all jobs regardless of state; the job does not have to be running or active to be updated.

        @params
        - schedule (*string): a cron-like string giving the job schedule, see @ref job_schedule "job schedule" for \
          information about the format; either this parameter or \c duration must be present, but not both
        - duration (*int): a duration in seconds for triggering the job; either this parameter or \c schedule must \
          be present, but not both; the duration must be less than 10^7.

        @return (hash JobScheduleUpdateInfo): a hash of information about the update operation
        - jobid (int): the job ID
        - name (string): the job name
        - schedule (*string): the new schedule for the job
        - duration (*int): the new dduration for the job
        - info (string): a descriptive string
        @ENDSCHEMA

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c JOB-SCHEDULE-ERROR: neither schedule nor duration parameters given
        - <tt><b>409 Conflict</b></tt>: \c CRON-ERROR: @ref job_schedule "cron schedule" cannot be parsed or 0 second
          (or non-integer) duration given
    */
    hash<HttpHandlerResponseInfo> putSchedule(*hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        hash<auto> rv = {
            "jobid": jh.jobid,
            "name": jh.name,
        };
        if (ah.schedule)
            rv.schedule = ah.schedule;
        else if (ah.duration) {
            if (ah.duration.toInt().toString() != ah.duration) {
                throw "CRON-ERROR", sprintf("invalid duration %y", ah.duration);
            }
            rv.duration = ah.duration.toInt();
        }

        rv.info = Qorus.jobManager.setJobSchedule(jh.name, rv.schedule, rv.duration);

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=setOptions

        @par Description
        Sets options for the current job.  If the job has an option list and any of the options are not valid
        for that job, an exception will be thrown, however, even if an exception is thrown due to an option error,
        all other options will still be set.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c options: a hash of options to set against the job; if the value of this key is a string, then it is
          first parsed with @ref Util::parse_to_qore_value(), which should then return a hash

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing \c "options" argument or \c "options" is not a hash (or string
          parsed to a hash with @ref Util::parse_to_qore_value())
        - <tt><b>409 Conflict</b></tt>: \c JOB-OPTION-ERROR: invalid option for job or option cannot be
          overridden at the job level

        @note
        - job options are persistent (persistent job options were implemented in Qorus 5.0)
    */
    hash<HttpHandlerResponseInfo> putSetOptions(hash<auto> cx, *hash<auto> ah) {
        if (ah.options.typeCode() == NT_STRING) {
            ah.options = parse_to_qore_value(ah.options);
        }
        if (!ah.options) {
            return RestHandler::make400("error setting options on job %s v%s (%d): missing 'options' hash in "
                "message body", jh.name, jh.version, jh.jobid);
        }
        if (ah.options.typeCode() != NT_HASH) {
            return RestHandler::make400("error setting options on job %s v%s (%d): 'options' argument is not "
                "a hash; got type %y instead", jh.name, jh.version, jh.jobid, ah.options.type());
        }

        rlog(cx, "(%s v%s (%d))", jh.name, jh.version, jh.jobid);

        list<string> errs = ();
        foreach hash<auto> i in (ah.options.pairIterator()) {
            try {
                #Qorus.qmm.updateJobOptionErr(jh.jobid, i.key, i.value);
                auto v = Qorus.qmm.updateJobOptionErr(jh.jobid, i.key, i.value);
                QDBG_LOG("JOB OPT UPDATE: %y", v);
            } catch (hash<ExceptionInfo> ex) {
                QDBG_LOG("JOB OPT UPDATE ERR: %s %s", ex.err, ex.desc);
                if (ex.err == "JOB-OPTION-ERROR") {
                    errs += ex.desc;
                } else {
                    rethrow;
                }
            }
        }
        if (errs) {
            throw "JOB-OPTION-ERROR", (foldl $1 + "; " + $2, errs);
        }

        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=enable

        @SCHEMA
        @summary Enables the current job if it is disabled

        @desc Enables the current job if it is disabled; if the job is already enabled, the action is \
        reported as successful anyway

        @return (hash JobUpdateResultInfo): information about the result of the operation
        - jobid (int): the workflow ID
        - name (string): the wojobrkflow name
        - version (string): the job version
        - info (string): a string providing information about the job update action

        @error (409): exception processing the request
        @ENDSCHEMA
    */
    hash<HttpHandlerResponseInfo> putEnable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s v%s (%d))", jh.name, jh.version, jh.jobid);

        Qorus.rbac.enableSyntheticGroup("job", jh.jobid);
        hash<auto> h = jh.("name", "version", "jobid") + {
            "info": sprintf("enabled job %s v%s (%d)", jh.name, jh.version, jh.jobid),
        };
        return RestHandler::makeResponse(200, h);
    }

    /** @REST PUT action=disable

        @SCHEMA
        @summary Disables the current job if it is disabled

        @desc Disables the current job if it is enabled; if the job is already disabled, the action is \
        reported as successful anyway

        @return (hash JobUpdateResultInfo): information about the result of the operation
        - jobid (int): the workflow ID
        - name (string): the wojobrkflow name
        - version (string): the job version
        - info (string): a string providing information about the job update action

        @error (409): exception processing the request
        @ENDSCHEMA
     */
    hash<HttpHandlerResponseInfo> putDisable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx, "(%s v%s (%d))", jh.name, jh.version, jh.jobid);

        # issue #3358: do not return until the interface has been disabled
        Qorus.rbac.disableSyntheticGroupWait("job", jh.jobid);
        hash<auto> h = jh.("name", "version", "jobid") + {
            "info": sprintf("disabled job %s v%s (%d)", jh.name, jh.version, jh.jobid),
        };
        return RestHandler::makeResponse(200, h);
    }

    private hash<HttpHandlerResponseInfo> handlePutSetActive(hash<auto> cx, *hash<auto> ah, *int apiver) {
        # permissions checked in RPC call
        if (!exists ah.active) {
            throw "JOB-ERROR", sprintf("missing 'active' parameter in call for job %s", jh.name);
        }
        rlog(cx);
        bool active = parse_boolean(ah.active);

        bool now_active;
        string info = Qorus.jobManager.setJobStatus(jh.name, active, \now_active);

        hash<auto> rv = {
            "jobid": jh.jobid,
            "name": jh.name,
            "active": now_active,
            "info": info,
        };
        if (apiver >= 3) {
            rv.db_active = active;
        }
        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /jobs

    This REST API path provides actions and information related to Qorus jobs.
*/
class JobRestClass inherits QorusRestClass {
    string name() {
        return "jobs";
    }

    static *hash<auto> staticGetJob(hash<auto> cx, *hash<auto> ah, softint id, *int apiver) {
        *hash<auto> meta = Qorus.qmm.lookupJob(id);
        if (!meta) {
            return;
        }

        meta = FunctionRestClass::moveTags(meta);

        if (exists ah.lib_source && parse_boolean(ah.lib_source)) {
            meta.lib = get_library_source(meta.lib);
        }

        if (ah."date") {
            ah."date" = date(ah."date");
        }

        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;

        *hash<auto> oview = sysinfo.getJobOverview(ah."date", id, ah.sqlcache);

        if (apiver >= 3) {
            meta.process = Qorus.qmm.getJobProcess(id);
            Qorus.qmm.fillConfigItemValues("job", meta.jobid, \meta);
        } else {
            remove meta{"config"};

            if (apiver < 2) {
                remove meta."runtime-options";
            }
        }
        if (apiver < 6) {
            remove meta.edit_lock;
            meta.single_instance = True;
        }

        return (meta + (oview.firstValue() - ("jobid", "version"))) + {
            "connections": Qorus.connDeps.getConnections("JOB", id),
            "alerts": Qorus.alerts.getAlerts("JOB", id),
            "enabled": Qorus.rbac.getSyntheticGroupStatus("job", id),
        };
    }

    static softint staticGetJobId(softstring arg, bool check = False, *reference jh) {
        if (arg =~ /[[:alpha:]]/u) {
            # try to find version
            *string ver;
            if ((int i = arg.find(":")) != -1) {
                ver = extract arg, i + 1;
                splice arg, -1;
            }

            *hash<auto> h = Qorus.qmm.rLookupJob(arg);
            if (h) {
                if (ver.val() && h.version != ver) {
                    throw "JOB-ERROR", sprintf("only job %s v%s is available; the requested version %y is not "
                        "available", arg, h.version, ver);
                }
                jh = h;
                return h.jobid;
            }

            if (check)
                throw "JOB-ERROR", sprintf("can't find any job %y", ver.val() ? sprintf("%s:%s", arg, ver) : arg);
        }

        if (check) {
            *hash<auto> h = Qorus.qmm.lookupJob(arg, True);
            if (!h)
                throw "JOB-ERROR", sprintf("there is no job with jobid %d", arg);
            jh = h;
        }

        return arg;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = JobRestClass::staticGetJobId(arg);
        *hash<auto> job = JobRestClass::staticGetJob(cx, ah, id);
        if (!job)
            return;

        hash<auto> ji = Qorus.jobManager.getActiveInfo();
        JobRestClass::fixJob(\job, ji.(job.name), cx);

        return new JobDefinitionRestClass(job);
    }

    private static fixJob(reference jh, *hash<auto> rjh, hash<auto> cx) {
        jh.db_active = remove jh.active;
        jh += (rjh - ("lib", "config"));
        if (!jh.active) {
            jh.active = False;
        } else {
            jh.log_url = get_log_url(cx, "jobs/%d", jh.jobid);
        }

        # convert job options to a list
        # NOTE: we use round parens instead of curly brackets to ensure a list is returned
        softlist options = map ("name": $1.key, "desc": omq_option_hash{$1.key}.desc, "value": $1.value),
            (remove jh."runtime-options").pairIterator();
        jh.options = options;
    }

    private static list staticGetJobs(hash<auto> cx, *hash<auto> ah, *int apiver, *hash<auto> filter) {
        *hash<auto> meta = Qorus.qmm.getJobMap();

        if (ah.date) {
            ah.date = date(ah.date);
        }

        if (ah.defonly) {
            ah.defonly = parse_boolean(ah.defonly);
        }

        if (ah.source) {
            ah.source = parse_boolean(ah.source);
        }

        ah.sqlcache = ah.sqlcache ? parse_boolean(ah.sqlcache) : True;

        *hash<auto> oview = ah.defonly ? NOTHING : sysinfo.getJobOverview(ah.date, NOTHING, ah.sqlcache);
        hash<auto> ji = Qorus.jobManager.getActiveInfo();

        list<hash<auto>> rvlist = ();

        # filter by specific jobs if necessary
        hash<auto> jfh;
        if (ah.jobs) {
            if (ah.jobs.typeCode() == NT_STRING)
                ah.jobs = ah.jobs.split(",");
            map jfh.(JobRestClass::staticGetJobId($1)) = True, ah.jobs;
        }

        bool do_list = exists ah.list && parse_boolean(ah.list);
        bool do_short = exists ah.short && parse_boolean(ah.short);

    	HashIterator it(meta);
    	while (it.next()) {
            # make sure active status is the actual active status and not the status in the DB
            hash<auto> jh = it.getValue();
            string name = jh.name;

            # skip if we have a filter and the job is not in the filter
            if (ah.jobs && !jfh.(jh.jobid))
                continue;

            JobRestClass::fixJob(\jh, ji{name}, cx);
            if (ah.status) {
                if (ah.status == "active") {
                    if (!jh.active)
                        continue;
                } else if (ah.status == "inactive") {
                    if (jh.active)
                        continue;
                }
            }

            hash<auto> job;
            job.name = name;
            job += jh;
            job.enabled = Qorus.rbac.getSyntheticGroupStatus("job", jh.jobid);

            if (!do_list && !do_short)
                job.groups = Qorus.rbac.getJobGroups(jh.jobid);

            # add instance status overview to workflow metadata
            if (oview{name}) {
                job += oview{name};
                job.TOTAL = foldl $1 + $2, (oview{name} - ("jobid", "version")).iterator();
            }
            job = FunctionRestClass::moveTags(job);

            if (apiver >= 3) {
                job.process = Qorus.qmm.getJobProcess(jh.jobid);
                Qorus.qmm.fillConfigItemValues("job", jh.jobid, \job);
            } else {
                remove job{"config"};
            }
            if (apiver < 6) {
                remove job.edit_lock;
                job.single_instance = True;
            }

            rvlist += JobDefinitionRestClass::addScheduleInfo(job);
        }

        if (filter) {
            rvlist = QorusMapManager::filterList(rvlist, filter);
        }

        if (exists ah.list && parse_boolean(ah.list))
            return map $1.name, rvlist;

        if (exists ah.short && parse_boolean(ah.short))
            return map sprintf("%s v%s (%s) %s", $1.name, $1.version, $1.jobid, $1.active ? "ACTIVE" : "INACTIVE"), rvlist;

        return Qorus.alerts.getAlerts("JOB", Qorus.connDeps.getConnections("JOB", rvlist, "jobid"), "jobid");
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
        If neither \c list nor \c short are used, then this API returns a list of @ref rest_job_description_hash elements; if \c defonly is not @ref True, then any jobs with job result data within the given time period (as defined by the \c date option) will be reflected in the following extra keys:
        - \c IN-PROGRESS: the number of job instances currently in progress
        - \c COMPLETE: the number of job instances with a @ref OMQ::StatComplete status during the given time period
        - \c ERROR: the number of job instances with a @ref OMQ::StatError status during the given time period
    */
    # args: "date", "status"
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, JobRestClass::staticGetJobs(cx, ah));
    }

    /** @REST GET action=list

        @par Description
        Returns information about Qorus jobs according to the arguments

        @see This API is equivalent to @ref rest_api_GET_jobs; see that documentation for details.
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST PUT action=run

        @par Description
        Runs one or more jobs and returns the results of job execution

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more job names or IDs to run; a comma-separated string will be split into a list

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c arg: the job ID or name (the argument passed as input)
        - \c run: @ref True means the job was run, @ref False means it was not
        - \c info: an informative string giving a description of the result or an error message
        - [\c jobid]: the job ID
        - [\c name]: the name of the job
        - [\c version]: the version of the job
        - [\c job_instanceid]: the job_instanceid of the job executed
        - [\c status]: the status of the execution of the job; see @ref JobStatusDescriptions for possible values

        @see
        - @ref rest_api_PUT_jobs__id_or_name__run
        - omq.system.job.run()
     */
    hash<auto> putRun(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "JOB-RUN-ERROR", "missing \"ids\" argument for job IDs to run";

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        list rv = ();

        foreach auto arg in (ah.ids) {
            *hash<auto> jh;
            int id = JobRestClass::staticGetJobId(arg, False, \jh);
            if (!id) {
                rv += ("arg": arg, "run": False, "info": "unknown job");
                continue;
            }

            if (!jh) {
                jh = Qorus.qmm.lookupJob(id, False);
                if (!jh) {
                    rv += ("arg": arg, "run": False, "info": sprintf("JOB-ERROR: jobid %d is unknown", id));
                    continue;
                }
            }

            hash<auto> jih = (
                "arg": arg,
                "jobid": id,
                "name": jh.name,
                "version": jh.version,
            );

            try {
                hash<auto> jsh = Qorus.jobManager.runJobNow(jh.name);
                jih += jsh + (
                    "run": True,
                    "info": sprintf("job %s v%s (%d) job_instanceid %d completed with status '%s' (%s)", jh.name,
                        jh.version, id, jsh.job_instanceid, OMQ::JSMap.(jsh.status), jsh.status),
                );
            } catch (hash<ExceptionInfo> ex) {
                jih += (
                    "run": False,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                );
            }
            rv += jih;
        }

        return RestHandler::makeResponse(200, rv);
    }

    static list<hash<auto>> resetJobs(hash<auto> cx, softlist<auto> ids) {
        list<hash<auto>> rv = ();

        foreach auto arg in (ids) {
            *hash<auto> jh;
            int id = JobRestClass::staticGetJobId(arg, False, \jh);
            if (!id) {
                rv += {
                    "arg": arg,
                    "reset": False,
                    "info": "unknown job",
                };
                continue;
            }

            if (!jh) {
                jh = Qorus.qmm.lookupJob(id, False);
                if (!jh) {
                    rv += {
                        "arg": arg,
                        "reset": False,
                        "info": sprintf("JOB-ERROR: jobid %d is unknown", id),
                    };
                    continue;
                }
            }

            hash<auto> jih = {
                "arg": arg,
                "jobid": id,
                "name": jh.name,
                "version": jh.version,
            };

            try {
                jih += {
                    "reset": True,
                    "info": Qorus.jobManager.resetJob(jh.name),
                };
            } catch (hash<ExceptionInfo> ex) {
                string msg = sprintf("%s: %s", ex.err, ex.desc);
                qlog(LoggerLevel::INFO, "error resetting job %s v%s (%d): %s", jh.name, jh.version, id,
                    Qorus.getDebugSystem() ? get_exception_string(ex) : msg);
                jih += {
                    "reset": False,
                    "info": msg,
                };
            }
            rv += jih;
        }

        return rv;
    }

    /** @REST PUT action=reset

        @par Description
        Reloads one or more jobs from the database; if the job is currently running it is stopped and reloaded.  This API works on all jobs regardless of state; the job does not have to be running or active to be reset.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more job names or IDs to reset; a comma-separated string will be split into a list

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c arg: the job ID or name (the argument passed as input)
        - \c reset: @ref True means the job was reset, @ref False means it was not
        - \c info: an informative string giving a description of the result or an error message
        - [\c jobid]: the job ID
        - [\c name]: the name of the job
        - [\c version]: the version of the job

        @see
        - @ref rest_api_PUT_jobs__id_or_name__reset
        - omq.system.job.reset()
     */
    hash<auto> putReset(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "JOB-RESET-ERROR", "missing \"ids\" argument for job IDs to reset";

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        return RestHandler::makeResponse(200, resetJobs(cx, ah.ids));
    }

    /** @REST PUT action=enable

        @par Description
        Enables one or more disabled jobs.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more job names or IDs to enable; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash with the following keys:
        - \c arg: the job ID or name (the argument passed as input)
        - \c enabled: @ref True means the job was enabled, @ref False means it was not
        - \c info: an informative string giving a description of the result or an error message
        - [\c jobid]: the job ID
        - [\c name]: the name of the job
        - [\c version]: the version of the job

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c JOB-ENABLE-ERROR: missing \c ids argument

        @see
        - @ref rest_api_PUT_jobs_disable
        - @ref rest_api_PUT_jobs__id_or_name__enable
        - @ref rest_api_PUT_jobs__id_or_name__disable
     */
    hash<auto> putEnable(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "JOB-ENABLE-ERROR", "missing \"ids\" argument for job IDs to enable";

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        list rv = ();

        foreach any arg in (ah.ids) {
            *hash<auto> jh;
            int id;
            try {
                id = JobRestClass::staticGetJobId(arg, True, \jh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "enabled": False, "info": "unknown job");
                continue;
            }

            hash<auto> jih = (
                "arg": arg,
                "jobid": id,
                "name": jh.name,
                "version": jh.version,
                );

            try {
                Qorus.rbac.enableSyntheticGroup("job", id);
                jih += (
                    "enabled": True,
                    "info": sprintf("job %s v%s (%d) enabled", jh.name, jh.version, id),
                    );
            } catch (hash<ExceptionInfo> ex) {
                jih += (
                    "enabled": False,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                    );
            }
            rv += jih;
        }

        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=disable

        @par Description
        Disables one or more jobs.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) one or more job names or IDs to disable; a comma-separated string will be split into a list

        @par Return Value
        This API returns a hash with the following keys:
        - \c arg: the job ID or name (the argument passed as input)
        - \c disabled: @ref True means the job was disabled, @ref False means it was not
        - \c info: an informative string giving a description of the result or an error message
        - [\c jobid]: the job ID
        - [\c name]: the name of the job
        - [\c version]: the version of the job

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c JOB-DISABLE-ERROR: missing \c ids argument

        @see
        - @ref rest_api_PUT_jobs_enable
        - @ref rest_api_PUT_jobs__id_or_name__enable
        - @ref rest_api_PUT_jobs__id_or_name__disable
     */
    hash<auto> putDisable(hash<auto> cx, *hash<auto> ah) {
        if (!ah.ids)
            throw "JOB-DISABLE-ERROR", "missing \"ids\" argument for job IDs to disable";

        rlog(cx);

        if (ah.ids.typeCode() == NT_STRING)
            ah.ids = ah.ids.split(",");

        list rv = ();

        foreach any arg in (ah.ids) {
            *hash<auto> jh;
            int id;
            try {
                id = JobRestClass::staticGetJobId(arg, True, \jh);
            } catch (hash<ExceptionInfo> ex) {
                rv += ("arg": arg, "disabled": False, "info": "unknown job");
                continue;
            }

            hash<auto> jih = (
                "arg": arg,
                "jobid": id,
                "name": jh.name,
                "version": jh.version,
                );

            try {
                # issue #3358: do not return until the interface has been disabled
                Qorus.rbac.disableSyntheticGroupWait("job", id);
                jih += {
                    "disabled": True,
                    "info": sprintf("job %s v%s (%d) disabled", jh.name, jh.version, id),
                };
            } catch (hash<ExceptionInfo> ex) {
                jih += {
                    "disabled": False,
                    "info": sprintf("%s: %s", ex.err, ex.desc),
                };
            }
            rv += jih;
        }

        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /system/options/{options}

    This REST URI path provides actions and information related to specific system options; see @ref systemoptions for more information
*/
class SystemOptionRestClass inherits QorusRestClass {
    private {
        hash<auto> h;
    }

    string name() {
        return h.name;
    }

    constructor(hash<auto> v_h) {
        h = v_h;
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (cx.hdr.method == "GET" && h.hasKey(name))
            return new AttributeRestClass(h{name});
    }

    /** @REST GET

        @par Description
        Returns a hash describing the option

        @par Return Value
        This API returns a @ref rest_system_option_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, h);
    }

    /** @REST PUT action=set

        @par Description
        Sets the option to a new value

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c value: (required) the new value for the option

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing \c "value" argument
        - <tt><b>409 Conflict</b></tt>: \c OPTION-ERROR: there was an error setting the option
    */
    hash<auto> putSet(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.value)
            return RestHandler::make400("error setting system option %y: missing 'value' key in message body", h.name);
        rlog(cx);
        # set options
        hash<auto> oh.(h.name) = ah.value;

        *list errs = Qorus.options.set(oh);
        if (errs)
            throw "OPTION-ERROR", sprintf("one or more options given was invalid or could not be set: %y", errs);
        return RestHandler::makeResponse(200, "OK");
    }
}

/** @REST /system/options

    This REST URI path provides actions and information related to system options; see @ref systemoptions for more information
*/
class SystemOptionsRestClass inherits QorusRestClass {
    string name() {
        return "options";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = UserApi::getQorusOptionInfo(arg);
        if (h)
            return new SystemOptionRestClass(h{arg});
    }

    /** @REST GET

        @par Description
        Returns a list of @ref systemoptions "system options"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c hash: optional (parsed with @ref Qore::parse_boolean()); if @ref True then the return type is a hash keyed by option name instead of a list

        @par Return Value
        This API returns a list of hashes if the \c hash argument is not set; each element in the list is a @ref rest_system_option_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        hash<auto> h = UserApi::getQorusOptionInfo();
        if (parse_boolean(ah.hash))
            return RestHandler::makeResponse(200, h);

        return RestHandler::makeResponse(200, (map ("name": $1.key) + $1.value, h.pairIterator()));
    }

    /** @REST PUT action=set

        @par Description
        Sets one or more @ref systemoptions "system options" to a new value

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c options: a hash of options; if the value of this key is a string, then it is first parsed with @ref Util::parse_to_qore_value(), which should then return a hash

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing \c "options" argument or \c "options" is not a hash (or string parsed to a hash with @ref Util::parse_to_qore_value())
        - <tt><b>409 Conflict</b></tt>: \c OPTION-ERROR: one or more options given was invalid or could not be set

        @note
        - when setting multiple options, an error setting one or more options does not block the other options without errors from being set
    */
    hash<auto> putSet(hash<auto> cx, *hash<auto> ah) {
        if (!ah.hasKey("options") && ah.typeCode() == NT_HASH)
            ah.options = remove cx.body;
        else {
            if (ah.options.typeCode() == NT_STRING)
                ah.options = parse_to_qore_value(ah.options);
            if (!ah.options)
                return RestHandler::make400("error setting system options: missing 'options' hash in message body");
            if (ah.options.typeCode() != NT_HASH)
                return RestHandler::make400("error setting system options: 'options' argument is not a hash (got type %y instead)", ah.options.type());
        }

        rlog(cx);

        *list errs = Qorus.options.set(ah.options);
        if (errs)
            throw "OPTION-ERROR", sprintf("one or more options given was invalid or could not be set: %y", errs);

        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=setOptions

        @par Description
        Sets one or more @ref systemoptions "system options" to a new value

        @see This API is equivalent to @ref rest_api_PUT_system_options_set; see that documentation for details.
     */
    hash<auto> putSetOptions(hash<auto> cx, *hash<auto> ah) {
        return putSet(cx, ah);
    }
}

/** @REST /system/props/{domain}/{key}

    This REST URI path provides actions and information related to a specific @ref sysprops "system property key".
*/
class SystemPropertyRestClass inherits QorusRestClass {
    private {
        string dom;
        string name;
        any val;
    }

    constructor(string v_dom, string v_name, any v_val) {
        dom = v_dom;
        name = v_name;
        val = v_val;
    }

    string name() {
        return name;
    }

    /** @REST PUT action=set

        @par Description
        Sets the value of the system property or deletes the system property key if no value is passed.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - [\c parse_args]: any string here will be parsed with @ref Util::parse_to_qore_value() and used as the property value; \c parse_args takes precedence over \c args
        - [\c args]:  arguments passed here will be used directly as the system property value

        @par Return Value
        This API returns a string action code as follows:
        - \c "INSERT": the property was created (only possible with this API with a race condition where the property was deleted in another thread during this request)
        - \c "UPDATE": the property was updated
        - \c "DELETE": the property was deleted (existing key, no value passed)
        - \c "IGNORED": if a non-existent key should be deleted (only possible with this API with a race condition where the property was deleted in another thread during this request)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c UPDATE-ERROR: changes attempted in the \c "omq" domain
        - <tt><b>409 Conflict</b></tt>: \c PROP-ERROR: serialized value exceeds 4000 bytes (column limit)
    */
    hash<auto> putSet(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        auto args = exists ah.parse_args ? parse_to_qore_value(ah.parse_args) : ah.args;
        return RestHandler::makeResponse(200, Qorus.props.update(dom, name, args));
    }

    /** @REST GET

        @par Description
        Returns the value of the system property

        @par Return Value
        This API returns the value of the system property
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, val);
    }

    /** @REST DELETE

        @par Description
        Deletes the system property key-value pair.

        @par Return Value
        This API returns a string action code as follows:
        - \c "DELETE": the property was deleted
        - \c "IGNORED": if a non-existent key should be deleted (only possible with this API with a race condition where the property was deleted in another thread during this request)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c UPDATE-ERROR: changes attempted in the \c "omq" domain
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        rlog(cx);
        return RestHandler::makeResponse(200, Qorus.props.update(dom, name));
    }

    /** @REST POST

        @par Description
        Creates a system property with the given value.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body; one of the following hash keys must be present):
        - [\c parse_args]: any string here will be parsed with @ref Util::parse_to_qore_value() and used as the property value; \c parse_args takes precedence over \c arg
        - [\c arg]: the argument passed here will be used directly as the system property value

        @par Return Value
        This API returns a string action code as follows:
        - \c "INSERT": the property was created
        - \c "UPDATE": the property was updated (only possible with this API with a race condition where the property was created in another thread during this request)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c UPDATE-ERROR: changes attempted in the \c "omq" domain
        - <tt><b>409 Conflict</b></tt>: \c SYSTEM-PROPERTY-ERROR: the given key already exists in the given property domain
        - <tt><b>409 Conflict</b></tt>: \c PROP-ERROR: serialized value exceeds 4000 bytes (column limit)
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        if (exists val)
            throw "SYSTEM-PROPERTY-ERROR", sprintf("cannot POST to create system/prop/%s/%s that already exists", dom, name);

        any arg = exists ah.parse_args ? parse_to_qore_value(ah.parse_args) : ah.arg;
        if (!exists arg)
            throw "SYSTEM-PROPERTY-ERROR", sprintf("missing \"arg\" or \"parse_arg\" hash argument to POST /api/system/prop/%s/%s", dom, name);
        rlog(cx);

        return RestHandler::makeResponse(201, Qorus.props.update(dom, name, arg));
    }
}

/** @REST /system/props/{domain}

    This REST URI path provides actions and information related to a specific @ref sysprops "system property domain".
*/
class SystemPropertyDomainRestClass inherits QorusRestClass {
    private {
        string name;
        *hash<auto> h;
    }

    string name() {
        return name;
    }

    constructor(string v_name, *hash<auto> v_h) {
        name = v_name;
        h = v_h;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        return new SystemPropertyRestClass(name, arg, h{arg});
    }

    /** @REST PUT action=updateMany

        @par Description
        Sets or deletes the values of one or more system property keys in the current system property domain.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c arg: (required) a key-value hash for updating, inserting, or deleting system properties in the current domain

        @par Return Value
        This API returns a hash of \c "INSERT", \c "UPDATE", \c "DELETE" and \c "IGNORED" keys with integer values corresponding to the number of operations performed (deleting a non-existent key or domain causes a \c "IGNORED" value to be returned).

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c UPDATE-ERROR: changes attempted in the \c "omq" domain
        - <tt><b>409 Conflict</b></tt>: \c PROP-ERROR: serialized value exceeds 4000 bytes (column limit)
    */
    hash<auto> putUpdateMany(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        if (!ah.arg || ah.arg.typeCode() != NT_HASH)
            throw "SSYTEM-PROPERTY-ERROR", sprintf("missing \"arg\" hash argument to system/prop/%s?action=updateMany", name);
        rlog(cx);
        hash<auto> h{name} = ah.arg;
        return RestHandler::makeResponse(200, Qorus.props.updateMany(h));
    }

    /** @REST PUT action=set

        @par Description
        Sets the value of a single system property or deletes the system property key if no value is passed.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c key: (required) a string giving the property key value in the current domain
        - [\c parse_args]: any string here will be parsed with @ref Util::parse_to_qore_value() and used as the property value; \c parse_args takes precedence over \c args
        - [\c args]:  arguments passed here will be used directly as the system property value

        @par Return Value
        This API returns a string action code as follows:
        - \c "INSERT": the property was created
        - \c "UPDATE": the property was updated
        - \c "DELETE": the property was deleted (existing key, no value passed)
        - \c "IGNORED": if a non-existent key should be deleted

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c UPDATE-ERROR: changes attempted in the \c "omq" domain
        - <tt><b>409 Conflict</b></tt>: \c PROP-ERROR: serialized value exceeds 4000 bytes (column limit)
    */
    hash<auto> putSet(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        if (!ah.key)
            throw "SYSTEM-PROPERTY-ERROR", "missing \"key\" argument in call to system/props?action=setValue";

        rlog(cx);
        auto args = exists ah.parse_args ? parse_to_qore_value(ah.parse_args) : ah.args;
        return RestHandler::makeResponse(200, Qorus.props.update(name, ah.key, args));
    }

    /** @REST GET

        @par Description
        Returns the value of the system property domain as a hash or of the specific key(s) given

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c key: (optional) one or more property values in the domain to return; if the string is a comma-separated list, it will be interpreted as a list of keys

        @par Return Value
        This API returns the value of the system property domain as a hash (optionally filtered by the \c key argument as above)
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        if (!h)
            throw "SYSTEM-PROPERTY-ERROR", sprintf("domain %y does not exist", name);

        if (ah.key.typeCode() == NT_STRING)
            ah.key = ah.key.split(",");
        return RestHandler::makeResponse(200, exists ah.key ? h.(ah.key) : h);
    }

    /** @REST DELETE

        @par Description
        Deletes the entire system property domain

        @par Return Value
        This API returns a hash of \c "DELETE" (and \c "IGNORED" keys in case of a race condition with a competing delete operation on the same system property domain) with integer values corresponding to the number of operations performed.

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c UPDATE-ERROR: changes attempted in the \c "omq" domain
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        rlog(cx);
        hash<auto> p{name} = map {$1: NOTHING}, keys h;
        return RestHandler::makeResponse(200, Qorus.props.updateMany(p));
    }

    /** @REST POST

        @par Description
        Creates an entire system property domain from a hash of key-value pairs

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c arg: (required) a hash giving all key-value pairs for the new system property domain

        @par Return Value
        This API returns a hash of \c "INSERT" (and \c "UPDATE" in case of a race condition with a parallel request writing to the same system property domain) keys with integer values corresponding to the number of operations performed

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c UPDATE-ERROR: changes attempted in the \c "omq" domain
        - <tt><b>409 Conflict</b></tt>: \c SYSTEM-PROPERTY-ERROR: the given key already exists in the given property domain
        - <tt><b>409 Conflict</b></tt>: \c PROP-ERROR: serialized value exceeds 4000 bytes (column limit)
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        if (h)
            throw "SYSTEM-PROPERTY-ERROR", sprintf("cannot POST to create domain %y that already exists", name);

        rlog(cx);
        if (!ah.arg || ah.arg.typeCode() != NT_HASH)
            throw "SYSTEM-PROPERTY-ERROR", sprintf("missing \"arg\" hash argument to POST system/prop/%s", name);
        hash<auto> h{name} = ah.arg;
        return RestHandler::makeResponse(201, Qorus.props.updateMany(h));
    }
}

/** @REST /system/props

    This REST URI path provides actions and information related to a @ref sysprops "system properties".
*/
class SystemPropertiesRestClass inherits QorusRestClass {
    string name() {
        return "props";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = Qorus.props.get(arg);
        return new SystemPropertyDomainRestClass(arg, h);
    }

    /** @REST GET action=export

        @par Description
        Exports properties as a YAML string.  Attributes in the \c "qorus_properties" tag are only informational and are not used when importing.
        The \c "omq" domain is not exported.

        @par Return Value
        This API returns a YAML-encoded string of all system properties in all domains except the \c "omq" domain.

        @par Example Return Value
        @verbatim
{qorus_properties: {domain1: {key1: "value", key2: "value"},
 ^attributes^: {instance: "quark-1", schema-version: "3.1.0",
 schema-compatibility: "3.1.0", schema-load-compatibility: "3.1.0"}}}
        @endverbatim

        @see @ref rest_api_PUT_system_props_import
    */
    hash<auto> getExport(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        if (ah.arg.typeCode() == NT_STRING)
            ah.arg = ah.arg.split(",");
        # set options
        string fn = sprintf("%s-%s.yml", UserApi::getSystemInfo()."instance-key", now().format("YYYY-MM-DDTHH:mm:SS"));
        return RestHandler::makeResponse(200, Qorus.props.export(ah.arg, True), ("Content-Disposition": "attachment;filename=" + fn));
    }

    /** @REST PUT action=import

        @par Description
        Import properties from a serialized string (such as exported from @ref rest_api_GET_system_props_export); if there are set domains in the list, only enumerated domains are imported

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c domains: (optional) a list of domains to import; a comma-separated string will be split into a list

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c PROP-ERROR: serialized value exceeds 4000 bytes (column limit)

        @see @ref rest_api_GET_system_props_export
    */
    hash<auto> putImport(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        rlog(cx);
        if (ah.domains.typeCode() == NT_STRING)
            ah.domains = ah.domains.split(",");
        Qorus.props.import(ah.arg, ah.domains);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=updateMany

        @par Description
        Sets or deletes the values of one or more system property keys in one or more system property domains

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c arg: (required) must be a hash in the format \c domain.key.value for updating, inserting, or deleting

        @par Return Value
        This API returns a hash of \c "INSERT", \c "UPDATE", \c "DELETE" and \c "IGNORED" keys with integer values corresponding to the number of operations performed (deleting a non-existent key or domain causes a \c "IGNORED" value to be returned).

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c UPDATE-ERROR: changes attempted in the \c "omq" domain
        - <tt><b>409 Conflict</b></tt>: \c PROP-ERROR: serialized value exceeds 4000 bytes (column limit)
    */
    hash<auto> putUpdateMany(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        rlog(cx);
        if (!ah.arg || ah.arg.typeCode() != NT_HASH)
            throw "SYSTEM-PROPERTY-ERROR", "missing \"arg\" hash argument to system/props?action=updateMany";
        return RestHandler::makeResponse(200, Qorus.props.updateMany(ah.arg));
    }

    /** @REST PUT action=reload

        @par Description
        Reloads all system properties from the database.

        @par Return Value
        This API returns the number of domains loaded
    */
    hash<auto> putReload(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        rlog(cx);
        return RestHandler::makeResponse(200, Qorus.props.reload());
    }

    /** @REST PUT action=set

        @par Description
        Sets or deletes the value of a single system property in a single domain.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c domain: (required) a string giving the system property domain for the key-value pair
        - \c key: (required) a string giving the property key value in the given domain
        - [\c parse_args]: any string here will be parsed with @ref Util::parse_to_qore_value() and used as the property value; \c parse_args takes precedence over \c args
        - [\c args]:  arguments passed here will be used directly as the system property value

        @par Return Value
        This API returns a string action code as follows:
        - \c "INSERT": the property was created
        - \c "UPDATE": the property was updated
        - \c "DELETE": the property was deleted (existing key, no value passed)
        - \c "IGNORED": if a non-existent key should be deleted

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c UPDATE-ERROR: changes attempted in the \c "omq" domain
        - <tt><b>409 Conflict</b></tt>: \c SYSTEM-PROPERTY-ERROR: the given key already exists in the given property domain
        - <tt><b>409 Conflict</b></tt>: \c PROP-ERROR: serialized value exceeds 4000 bytes (column limit)
    */
    hash<auto> putSet(hash<auto> cx, *hash<auto> ah) {
        # permissions are checked in the Props class
        if (!ah.domain)
            throw "SYSTEM-PROPERTY-ERROR", "missing \"domain\" argument in call to system/props?action=setValue";
        if (!ah.key)
            throw "SYSTEM-PROPERTY-ERROR", "missing \"key\" argument in call to system/props?action=setValue";

        rlog(cx);
        auto args = exists ah.parse_args ? parse_to_qore_value(ah.parse_args) : ah.args;
        return RestHandler::makeResponse(200, Qorus.props.update(ah.domain, ah.key, args));
    }

    /** @REST GET

        @par Description
        Returns system properties according to the arguments passed.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c domain: (optional) a system property domain to retrieve values for
        - \c key: (optional) a system property key in the given domain; if \c key is given then \c domain must also be passed

        @par Return Value
        This API returns:
        - a hash of all domains if no \c domain value is passed
        - a hash of the given domain if the \c domain value is passed and the domain exists, otherwise @ref nothing
        - the vaule of the given property in the given domain if the \c domain and \c key values are passed and the property exists
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, Qorus.props.get(ah.domain, ah.key));
    }
}

/** @REST /system/sqlcache

    This REST API path provides actions and information related to the system @ref sql-cache "SQL cache"

    @since Qorus 3.1.0
*/
class SqlCacheRestClass inherits QorusRestClass {
    string name() {
        return "sqlcache";
    }

    /** @REST GET

        @par Description
        Returns information about the system cache

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c system: returns information about system objects as well (in the \c "omq" @ref dsconn "datasource")

        @par Return Value
        This API returns a hash keyed by @ref dsconn "datasource" name; values are hashes keyed by SQL object type (ex: "tables");
        the values of this hash are hashes with the following keys:
        - \c count: the number of times accessed
        - \c created: the date/time the object was cached
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = parse_boolean(ah.system) ? get_sql_cache_info_system() : UserApi::getSqlCacheInfo();
        return RestHandler::makeResponse(200, h);
    }

    /** @REST PUT action=clear

        @par Description
        Clears the @ref sql-cache "SQL cache" according to the arguments.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c datasource: (optional) a string giving the @ref dsconn "datasource" to clear all objects for
        - \c name: (optional) the name of the object to clear; if this argument is given, then \c datasource must also be given

        @par Return Value
        This API returns \c "OK" upon successful execution
    */
    hash<auto> putClear(hash<auto> cx, *hash<auto> ah) {
        Qorus.dsmanager.clearTableCache(ah.datasource, ah.name);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=clearCache

        @par Description
        Clears the @ref sql-cache "SQL cache" according to the arguments.

        @see This API is equivalent to @ref rest_api_PUT_system_sqlcache_clear; see that documentation for details.

    */
    hash<auto> putClearCache(hash<auto> cx, *hash<auto> ah) {
        return putClear(cx, ah);
    }
}

/** @REST /system/userhttp

    This REST URI path provides actions and information about user HTTP services.
*/
class SystemUserHttpRestClass inherits QorusRestClass {
    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = services.getUserHttpServiceInfo(cx);
        if (cx.hdr.method == "GET" && h.hasKey(name)) {
            return new AttributeRestClass(h{name});
        }
    }

    string name() {
        return "userhttp";
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
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, services.getUserHttpServiceInfo(cx));
    }
}

/** @REST /system/api

    This REST URI path provides actions and information about the system @ref rpcapi "RPC API"
*/
class SystemApiRestClass inherits QorusRestClass {
    string name() {
        return "api";
    }

    /** @REST PUT action=call

        @par Description
        Calls a system @ref rpcapi "RPC API" method and returns the return value

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c method: (required) the string method name to call; if no \c "." characters are found in the method name, then it is prefixed with \c "omq.system."; if the method starts with \c "system." or \c "user.", then \c "omq." is prefixed to the method; if the method starts with \c "group." or \c "job.", then \c "omq.system." is prefixed to the method name
        - [\c parse_args]: any string here will be parsed with @ref Util::parse_to_qore_value() and used as the method arguments; \c parse_args takes precedence over \c args
        - [\c args]: any arguments passed here will be used directly as the method arguments

        @par Return Value
        This API returns result of calling the given @ref rpcapi "RPC API" method with the given arguments

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c API-ERROR: missing or invalid \c "method" key

        @see the @ref rpcapi "RPC API" method in question for information about arguments, return types, or permissions required
    */
    hash<auto> putCall(hash<auto> cx, *hash<auto> ah) {
        if (!ah.method)
            throw "API-ERROR", "missing \"method\" key in api call arguments";
        if (ah.method.typeCode() != NT_STRING)
            throw "API-ERROR", sprintf("\"method\" key in api call arguments is not a string; got type %y instead",
                ah.method.type());

        auto args = exists ah.parse_args ? parse_to_qore_value(ah.parse_args) : ah.args;

        ensure_create_tld();

        rlog(cx);

        string cmd = ah.method;
        if (index(cmd, ".") == -1)
            cmd = "omq.system." + cmd;
        else switch (cmd) {
            case /^system\./:
            case /^user\./: {
                cmd = "omq." + cmd;
                break;
            }
            case /^group\./:
            case /^job\./: {
                cmd = "omq.system." + cmd;
                break;
            }
        }

        ThreadLocalData tld_save();
        tld_save.tldCopy(tld);
        on_exit tld.tldCopy(tld_save);

        return RestHandler::makeResponse(200, api.callArgs(cmd, args));
    }
}

/** @REST /system/ui/extensions/{name}

    This REST URI path provides actions and information related to a specific system UI extension
*/
class SystemUiExtensionRestClass inherits QorusRestClass {
    public {
        hash<auto> h;
    }

    constructor(hash<auto> v_h) {
        h = v_h;
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (cx.hdr.method == "GET" && h.hasKey(name))
            return new AttributeRestClass(h{name});
    }

    string name() {
        return h.name;
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current UI extension

        @par Return Value
        This API returns a @ref rest_system_ui_extension_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, h);
    }
}

/** @REST /system/ui/extensions

    This REST URI path provides actions and information related to system UI extensions
*/
class SystemUiExtensionsRestClass inherits QorusRestClass {
    public {
        *hash<auto> h;
    }

    constructor(*hash<auto> v_h) {
        h = v_h;
    }

    string name() {
        return "extensions";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> ext = h{arg};
        if (!ext) {
            ext = services.getUiExtensionInfo(arg, cx);
        }
        if (ext) {
            return new SystemUiExtensionRestClass(("name": arg) + ext);
        }
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of information about UI extensions

        @par Return Value
        This API returns a list of @ref rest_system_ui_extension_hash elements
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (map ("name": $1.key) + $1.value, h.pairIterator()));
    }

    /** @REST GET action=list

        @par Description
        Returns a list of hashes of information about UI extensions

        @see This API is equivalent to @ref rest_api_GET_system_ui_extensions; see that documentation for details.
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }
}

/** @REST /system/ui

    This REST URI path provides actions and information related to the system UI
*/
class SystemUiRestClass inherits QorusRestClass {
    string name() {
        return "ui";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        switch (arg) {
            case "extensions":
                return new SystemUiExtensionsRestClass(services.getUiExtensions(cx));
        }
    }

    /** @REST GET

        @par Description
        Returns a list of child URI path components

        @par Return Value
        This API returns a list of child URI path components
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ("extensions",));
    }
}

/** @REST /system/alerts/transient

    This REST URI path provides actions and information related to @ref transientalerts "transient system alerts"
*/
class SystemTransientAlertsRestClass inherits QorusRestClass {
    string name() {
        return "transient";
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of information about @ref transientalerts "transient system alerts"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c remote: (optional) the name of a @ref remoteconn "remote Qorus connection" to retrieve transient alerts for and add to the return value
        - \c max: (optional) the maximum number of local alerts to return; defaults to 50 if not given

        @par Return Value
        This API returns a list of @ref rest_alert_hash elements for @ref transientalerts "transient system alerts"
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        ah.remote = parse_boolean(ah.remote);
        list l = Qorus.alerts.getTransientAlerts(ah.max);

        # get alerts from all connected instances
        if (ah.remote) {
            # get list of remote Qorus instances
            *list<auto> rl = Qorus.remotemonitor.getRemoteList();
            foreach string k in (rl) {
                try {
                    QorusSystemRestHelper rr = Qorus.remotemonitor.getRest(k);
                    list ral = rr.get("system/alerts/transient");
                    #log(LoggerLevel::DEBUG, "transient events retrieved from %y: %d", k, ral.size());
                    l += map $1 - "local", ral;
                } catch (hash<ExceptionInfo> ex) {
                    olog(LoggerLevel::INFO, "could not fetch remote events from %y: %s: %s", k, ex.err, ex.desc);
                }
            }
        }

        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /system/alerts/ongoing

    This REST URI path provides actions and information related to @ref ongoingalerts "ongoing system alerts"
*/
class SystemOngoingAlertsRestClass inherits QorusRestClass {
    string name() {
        return "ongoing";
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of information about @ref ongoingalerts "ongoing system alerts"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c remote: (optional) the name of a @ref remoteconn "remote Qorus connection" to retrieve ongoing alerts for and add to the return value

        @par Return Value
        This API returns a list of @ref rest_alert_hash elements for @ref ongoingalerts "ongoing system alerts"
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        ah.remote = parse_boolean(ah.remote);
        list l = Qorus.alerts.getOngoingAlerts();

        # get alerts from all connected instances
        if (ah.remote) {
            # get list of remote Qorus instances
            *list<auto> rl = Qorus.remotemonitor.getRemoteList();
            foreach string k in (rl) {
                try {
                    QorusSystemRestHelper rr = Qorus.remotemonitor.getRest(k);
                    list ral = rr.get("system/alerts/ongoing");
                    #log(LoggerLevel::DEBUG, "ongoing events retrieved from %y: %d", k, ral.size());
                    l += map $1 - "local", ral;
                } catch (hash<ExceptionInfo> ex) {
                    olog(LoggerLevel::INFO, "could not fetch remote events from %y: %s: %s", k, ex.err, ex.desc);
                }
            }
        }

        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /system/alerts

    This REST URI path provides actions and information related to @ref alerts "system alerts"
*/
class SystemAlertsRestClass inherits QorusRestClass {
    string name() {
        return "alerts";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        switch (arg) {
            case "ongoing":
                return new SystemOngoingAlertsRestClass();
            case "transient":
                return new SystemTransientAlertsRestClass();
        }
    }

    hash<auto> getSummary(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, Qorus.alerts.getAlertCounts());
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of information about @ref alerts "system alerts"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c remote: (optional) the name of a @ref remoteconn "remote Qorus connection" to retrieve alerts for and add to the return value
        - \c summary: (optional) parsed with @ref Qore::parse_boolean(); if @ref True the return value is a hash with the following keys:
          - \c "cutoff": the transient cut off date used
          - \c "transient": the count of transient alerts
          - \c "ongoing": the count of ongoing alerts
        - \c cutoff: (optional) parsed as a date; the cutoff date/time for transient alerts (only used when \c summary is @ref True); transient events after this point in time are not considered in the summarized result

        @par Return Value
        This API returns a list of @ref rest_alert_hash elements for @ref alerts "system alerts" unless the \c summary option is passed (see above for details)
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        ah.remote = parse_boolean(ah.remote);
        ah.summary = parse_boolean(ah.summary);
        if (ah.summary)
            return RestHandler::makeResponse(200, Qorus.alerts.getAlertCounts(ah.remote, ah.cutoff));

        list l = Qorus.alerts.getAllAlerts(ah.max);

        # get alerts from all connected instances
        if (ah.remote) {
            # get list of remote Qorus instances
            *list<auto> rl = Qorus.remotemonitor.getRemoteList();
            foreach string k in (rl) {
                try {
                    QorusSystemRestHelper rr = Qorus.remotemonitor.getRest(k);
                    list ral = rr.get("system/alerts");
                    l += map $1 - "local", ral;
                } catch (hash<ExceptionInfo> ex) {
                    olog(LoggerLevel::INFO, "could not fetch remote events from %y: %s: %s", k, ex.err, ex.desc);
                }
            }
        }

        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /system/health

    This REST URI path provides actions and information about system health
*/
class SystemHealthRestClass inherits QorusRestClass {
    string name() {
        return "health";
    }

    static hash<auto> staticGetHealth() {

        return Qorus.alerts.getHealth() + {
            "instance-key": Qorus.session.getKey(),
            "remote": Qorus.remotemonitor.getRemoteHealthList(),
        };
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        hash<auto> h = SystemHealthRestClass::staticGetHealth();
        if (cx.hdr.method == "GET" && h.hasKey(arg))
            return new AttributeRestClass(h{arg});
    }

    /** @REST GET

        @par Description
        Returns a hash describing the health of the system and monitored remote systems

        @par Return Value
        This API returns a hash with the following keys:
        - \c transient: the number of @ref transientalerts "transient alerts"
        - \c ongoing: the number of @ref ongoingalerts "ongoing alerts"
        - \c health: a string color code for the health of the system with the following values:
          - \c "GREEN": good health
          - \c "YELLOW": warning
          - \c "RED": problems
        - \c instance-key: the instance key for the system
        - \c remote: a list of health information for @ref remoteconn "remotely-monitored Qorus instances" with the same keys as this hash (minus \c "remote")

        @par Return Value Example
        @verbatim
hash: (5 members)
  transient : 0
  ongoing : 123
  health : "RED"
  instance-key : "quark-1"
  remote : <EMPTY LIST>
        @endverbatim
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, SystemHealthRestClass::staticGetHealth());
    }
}

class TestDataStream inherits AbstractDataStreamRequestHandler {
    private {
        const Reql = (
            ("a": 1, "b": 2),
            ("x": 3, "y": 4),
            );

        list reql = Reql;
        list body;
    }

    constructor(hash<auto> cx, *hash<auto> ah) : AbstractDataStreamRequestHandler(cx, ah) {
    }

    private nothing recvDataImpl(any data) {
        qlog(LoggerLevel::INFO, "TEST DATA STREAM RECV: %y", data);
        body += data;
    }

    private any sendDataImpl() {
        qlog(LoggerLevel::INFO, "TEST DATA STREAM SEND: %y", reql[0]);
        return shift reql;
    }
}

class EchoDataStream inherits AbstractDataStreamRequestHandler {
    private {
        list data = ();
    }

    constructor(hash<auto> cx, *hash<auto> ah) : AbstractDataStreamRequestHandler(cx, ah) {
    }

    private nothing recvDataImpl(any n_data) {
        qlog(LoggerLevel::INFO, "TEST DATA STREAM RECV: %y", n_data);
        data += n_data;
    }

    private any sendDataImpl() {
        qlog(LoggerLevel::INFO, "TEST DATA STREAM SEND: %y", data[0]);
        return shift data;
    }
}

class TestStream inherits AbstractRestStreamRequestHandler {
    private {
        const Reql = (
            "\"quark",
            "-1\"",
            );

        list reql = Reql;
        string body;
    }

    constructor(hash<auto> cx, *hash<auto> ah) : AbstractRestStreamRequestHandler(cx, ah) {
    }

    hash<auto> getResponseHeaderMessageImpl() {
        return (
            "code": 200,
            "hdr": (
                "Content-Type": MimeTypeYaml,
                "Transfer-Encoding": "chunked",
            ),
            );
    }

    nothing recvImpl(hash v) {
        qlog(LoggerLevel::INFO, "TEST STREAM RECV: %y", v);
        if (v.data)
            body += v.data;
        else
            qlog(LoggerLevel::INFO, "TEST STREAM RECV DATA: %y", body);
    }

    auto sendImpl() {
        qlog(LoggerLevel::INFO, "TEST STREAM SEND: %y", reql[0]);
        return shift reql;
    }
}

/** @REST /system/rbac
*/
class RbacRestClass inherits QorusRestClass {
    private {
      hash<auto> info;
    }

    string name() {
        return "rbac";
    }

    constructor() {
        info = Qorus.rbac.getInfo();
        info.permissions = map info.permissions.$1 += ('name': $1), keys info.permissions;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg == "perms" || arg == "permissions")
            return new PermsRestClass();

        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            auto rv = info{arg};
            if (info.hasKey(arg))
                return new AttributeRestClass(rv);
            rv = info.providers{arg};
            if (info.providers.hasKey(arg))
                return new AttributeRestClass(rv);
        }
    }

    /** @REST PUT action=reload

        @par Description
        Reloads the all @ref RBAC information (users, permissions, roles, groups) from the system schema

        @par Return Value
        This API returns \c "OK" upon successful execution

        @see omq.system.reload-rbac()
    */
    hash<auto> putReload(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        Qorus.rbac.reload();
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST GET

        @par Description
        Returns information about @ref RBAC configuration and status

        @par Return Value
        This API returns a hash with the following keys:
        - \c loaded: the date/time @ref RBAC information was loaded
        - \c permissions: a list of @ref rest_permission_hash elements
        - \c groups: the number of @ref rbacgroups "interface groups" cached
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, info);
    }
}

/** @REST /system/listeners/{id_or_name}

    This REST URI path provides actions and information related to a specific HTTP listener
*/
class ListenerRestClass inherits QorusRestClass {
    private {
        hash<auto> lh;
    }

    string name() {
        return lh.name;
    }

    constructor(hash<auto> lh) {
        self.lh = lh;
    }

    /** @REST GET

        @SCHEMA
        @summary Returns a hash of information about the current listener

        @desc Returns a hash of information about the current listener

        @return (hash ListenerInfoHash): information about the current listener
        - name (string): the unique name of the listener
        - hostname (*string): the bind hostname
        - hostname_desc (*string): a description for the hostname
        - address (string): the bind address
        - address_desc (string): a description for the address
        - port (*int): the port number (not present in UNIX sockets)
        - family (int): the @ref network_address_family_constants "network address family code" for the socket
        - familystr (string): a descriptive string for the \c family code
        - ssl (bool): @ref True if the listener is a TLS/SSL listener
        - desc (string): a descriptive string for the listener
        - proto (string): the protocol; either \c "http" or \c "https"
        - id (int): the listener ID
        - bind (string): the bind string
        - get_remote_certs (bool): flag if remote client certificates will be captured
        - ssl_verify_flags (list<string>): SSL verification flags (see @ref ssl_mode_constants for the meaning of \
          these values)
        - ssl_accept_all_certs (bool): if the listener will accept all client certificates (verification disabled) \
          or not (verification enabled)
        @ENDSCHEMA
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, lh);
    }

    /** @REST POST action=stop

        @par Description
        Stops the current listener

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: \c LISTENER-ARG-ERROR: cannot stop a listener via a request handled by the
          same listener

        @see This API is equivalent to @ref rest_api_DELETE_system_listeners__id_or_name_; see that documentation for
        details.
    */
    hash<auto> postStop(hash<auto> cx, *hash<auto> ah) {
        # we call ServiceManager::stopListenerId() to handle stopping service listeners gracefully
        services.stopListenerId(cx, lh.id);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=logVerboseAll

        @par Description
        Turns on and off verbose logging for the current listener; verbose logging means that HTTP headers and bodies
        are logged (which can produce lots of data in log files)

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c flag: (optional) if present, parsed with @ref Qore::parse_boolean(); if @ref True then verbose logging is
          enabled for the current listener, if @ref False, then it is disabled; default value if not present @ref True

        @par Return Value
        This API returns \c "OK" upon successful execution

        @note
        - it is recommended to enable verbose logging only as a debug option

        @warning this option can result in @ref sensitive_data "sensitive data" being logged; use with care

        @see
        - @ref rest_api_GET_system_listeners__id_or_name__logOptions
        - @ref rest_api_PUT_system_listeners__id_or_name__setLogOptions
        - @ref HttpServer::HttpServer::getListenerLogOptionsID()
        - @ref HttpServer::HttpServer::setListenerLogOptionsID()
    */
    hash<auto> putLogVerboseAll(hash<auto> cx, *hash<auto> ah) {
        bool flag = exists ah.flag ? parse_boolean(ah.flag) : True;
        Qorus.httpServer.setListenerLogOptionsID(lh.id, flag ? -1 : 0);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=setLogOptions

        @par Description
        Sets @ref ListenerLogOptions "logging options" for the current listener according to the \c option argument passed

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c option: (required) an integer product of @ref ListenerLogOptions combined with binary or

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: missing \c "option" argument

        @warning this option can result in @ref sensitive_data "sensitive data" being logged; use with care

        @see
        - @ref rest_api_GET_system_listeners__id_or_name__logOptions
        - @ref rest_api_PUT_system_listeners__id_or_name__logVerboseAll
        - @ref HttpServer::HttpServer::getListenerLogOptionsID()
        - @ref HttpServer::HttpServer::setListenerLogOptionsID()
    */
    hash<auto> putSetLogOptions(hash<auto> cx, *hash<auto> ah) {
        if (!ah.option.intp())
            return RestHandler::make400("error setting listener log option for listener %y (id %d): missing 'option' key in message body", lh.name, lh.id);

        Qorus.httpServer.setListenerLogOptionsID(lh.id, ah.option);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST GET action=logOptions

        @par Description
        Returns a code giving the @ref ListenerLogOptions "logging options" set for the current listener

        @par Return Value
        Returns the integer value of @ref ListenerLogOptions set for the current listener combined by binary or

        @see
        - @ref rest_api_PUT_system_listeners__id_or_name__logVerboseAll
        - @ref rest_api_PUT_system_listeners__id_or_name__setLogOptions
        - @ref HttpServer::HttpServer::getListenerLogOptionsID()
        - @ref HttpServer::HttpServer::setListenerLogOptionsID()
    */
    hash<auto> getLogOptions(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, Qorus.httpServer.getListenerLogOptionsID(lh.id));
    }

    /** @REST DELETE

        @par Description
        Stops the current listener

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: \c LISTENER-ARG-ERROR: cannot stop a listener via a request handled by the
          same listener

        @note
        - the last listener cannot be stopped; at least one listener must be running at all times
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        return postStop(cx, ah);
    }
}

/** @REST /system/listeners

    This REST URI path provides actions and information related to Qorus HTTP listeners
*/
class ListenersRestClass inherits QorusRestClass {
    string name() {
        return "listeners";
    }

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

        return lh ? new ListenerRestClass(lh) : NOTHING;
    }

    /** @REST GET

        @SCHEMA
        @summary Returns a hash of hashes providing information about HTTP listeners

        @desc Returns a hash of hashes of information about HTTP listeners

        @return (hash[hash ListenerInfoHash] ListenerInfoSet): hash of hashes keyed by listener ID providing \
        information about Qorus listeners
        - name (string): the unique name of the listener
        - hostname (*string): the bind hostname
        - hostname_desc (*string): a description for the hostname
        - address (string): the bind address
        - address_desc (string): a description for the address
        - port (*int): the port number (not present in UNIX sockets)
        - family (int): the @ref network_address_family_constants "network address family code" for the socket
        - familystr (string): a descriptive string for the \c family code
        - ssl (bool): @ref True if the listener is a TLS/SSL listener
        - desc (string): a descriptive string for the listener
        - proto (string): the protocol; either \c "http" or \c "https"
        - id (int): the listener ID
        - bind (string): the bind string
        - get_remote_certs (bool): flag if remote client certificates will be captured
        - ssl_verify_flags (list<string>): SSL verification flags (see @ref ssl_mode_constants for the meaning of \
          these values)
        - ssl_accept_all_certs (bool): if the listener will accept all client certificates (verification disabled) \
          or not (verification enabled)
        @ENDSCHEMA

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of listener names is
          returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of
          listener names and descriptions is returned

        @par Return Value
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_listener_hash elements
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        hash<auto> h = Qorus.httpServer.getListeners();
        if (exists ah.list && parse_boolean(ah.list)) {
            return RestHandler::makeResponse(200, (map $1.name, h.iterator()));
        }

        if (exists ah.short && parse_boolean(ah.short)) {
            return RestHandler::makeResponse(200, (
                map sprintf("%s: %s (HTTP%s)", $1.name, $1.desc, $1.ssl ? "S" : ""), h.iterator()
            ));
        }

        return RestHandler::makeResponse(200, h);
    }

    /** @REST POST action=start

        @par Description
        Starts one or more listeners on the given bind address

        @see This API is equivalent to @ref rest_api_POST_system_listeners; see that documentation for details.
    */
    hash<auto> postStart(hash<auto> cx, *hash<auto> ah) {
        if (!ah.bind || !ah.bind.strp()) {
            throw "START-LISTENER-ERROR", sprintf("missing or invalid \"bind\" argument (%y) for the listener to "
                "start", ah.bind);
        }

        if (ah.family) {
            if (ah.family =~ /[^0-9]/) {
                *int fam = AFStrMap{ah.family};
                if (!fam) {
                    throw "START-LISTENER-ERROR", sprintf("cannot map family %y to an address family constant: known "
                        "address families: %y", ah.family, AFMap.values());
                }
                ah.family = fam;
            } else {
                ah.family = int(ah.family);
            }
        }

        hash<HttpListenerOptionInfo> info();
        if (exists ah.name) {
            info.name = ah.name;
        }
        if (exists ah.family) {
            info.family = ah.family;
        }
        if (exists ah.cert_file) {
            info += http_get_ssl_objects(ah.cert_file, ah.key_file, ah.key_password);
        }
        hash<string, string> errmap;
        list<hash<auto>> l = Qorus.httpServer.addListeners(ah.bind.toString(), info, \errmap);
        # throw an error if no listeners were started
        if (!l && errmap) {
            return RestHandler::makeResponse(400, errmap);
        }
        return RestHandler::makeResponse(200, l);
    }

    /** @REST POST

        @par Description
        Starts one or more listeners on the given bind address

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c bind: the bind address of the new listener; listeners will be started on all possible bind addresses in
          case more than one interface is resolved from the bind address given
        - [\c cert_file]: (optional) the file name of the X.509 certificate in PEM format (only for HTTPS listeners)
        - [\c key_file]: (optional) the file name of the private key for the X.509 certificate in PEM format (only for
          HTTPS listeners)
        - [\c key_password]: (optional) the password to the private key, if any
        - [\c family]: (optional) the integer @ref network_address_family_constants "network address family code" or
          symbolic string name
        - [\c name]: (optional) the name of the listener; if not provided a unique name will be generated

        @par Return Value
        This API returns list of hashes for each listener started, each hash having the following keys (note that for
        UNIX domain socket listeners the \c hostname, \c hostname_desc, and \c port keys will not be present):
        - \c hostname: the hostname of the interface
        - \c hostname_desc: a descriptive string for the hostname including the address family (ex:
          \c "ipv6[localhost]")
        - \c address: the address of the listener (i.e. \c "192.168.30.4", etc)
        - \c address_desc: a descriptive string for the hostname including the address family (ex: \c "ipv6[::1]")
        - \c port: the port number
        - \c family: an integer giving the address family (\c AF_INET, \c AF_INET6, \c AF_UNIX, etc)
        - \c familystr: a string describing the address family (ex: \c "ipv6")
        - \c proto: either \c "http" or \c "https"
        - \c id: the Qorus ID of the listener
        - \c bind: a string giving the bind address used (ex: \c "127.0.0.1:8001")

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: if no listeners can be started, then the message body in the response gives
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        return postStart(cx, ah);
    }
}

/** @REST /system/sessions

    This REST URI path provides actions and information related to @ref appsessionmodel "Qorus application sessions"
*/
class SessionsRestClass inherits QorusRestClass {
    string name() {
        return "sessions";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            *hash<auto> h = sysinfo.searchSessions(ah + ("id": arg))[0];
            if (h)
                return new AttributeRestClass(h);
        }
    }

    /** @REST GET

        @par Description
        Returns a list of hashes for sessions matched according to the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ended_maxdate: (optional) give the upper date range for the session end date
        - \c ended_mindate: (optional) give the lower date range for the session end date
        - \c hostname: (optional) the hostname to search for
        - \c id: (optional) the session ID
        - \c key: (optional) the instance key name
        - \c limit: (optional) the maximum number of sessions to return
        - \c list: (optional) parsed with @ref Qore::parse_boolean(); if @ref True then a list of session names is returned
        - \c short: (optional) parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of session names and descriptions is returned
        - \c started_maxdate: (optional) give the upper date range for the session start date
        - \c started_mindate: (optional) give the lower date range for the session start date
        - \c offset: (optional) the starting release to return (use when paging for example)
        - \c status: (optional) one or more session status values
        - \c url: (optional) the HTTP URL for the instance
        - \c version: (optional) the Qorus version string

        @par Return Value
        If \c list and \c short are not used, then this API returns list of hashes for sessions matched; each hash has the following keys:
        - \c id: the session ID
        - \c key: the instance key for the session
        - \c status: status of the session
        - \c hostname: the hostname hosting the Qorus process running the session
        - \c url: the primary URL for the application session
        - \c version: the Qorus version for the session
        - \c started: the date/time the session started
        - \c ended: the date/time the session ended
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        *list l = sysinfo.searchSessions(ah);

        if ((exists ah.list && parse_boolean(ah.list))
            || (exists ah.short && parse_boolean(ah.short)))
            return RestHandler::makeResponse(200, (map sprintf("%s: %s", $1.id, $1.status), l));

        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /system/metadata

    This REST URI path provides actions and information related to the system metadata cache

    @since Qorus 3.1.0
*/
class MetadataRestClass inherits QorusRestClass {
    public {
        # order is sensitive here; metadata will be refreshed in the order listed
        const Reload = (
            "functions": "reloadFunctions",
            "classes": "reloadClasses",
            "constants": "reloadConstants",
            "queues": "reloadQueues",
            "events": "reloadEvents",
            "mappers": "reloadMappers",
            "pipelines": "reloadPipelines",
            "fsm": "reloadFsms",
            "vmaps": "reloadVMaps",
            "steps": "reloadSteps",
            "workflows": "reloadWorkflows",
            "services": "reloadServices",
            "jobs": "reloadJobs",
            "slas": "reloadSlas",
            "config_values": "reloadConfigItemValues",
            "loggers": "reloadLoggers",
            "types": "reloadTypes",
        );

        const Interfaces = {
            "workflows": True,
            "services": True,
            "jobs": True,
        };

        const Caches = (
            "classmap": "getClassMap",
            "classrmap": "getClassRMap",
            "config_values": "getConfigItemValues",
            "constmap": "getConstantMap",
            "constrmap": "getConstantRMap",
            "emap": "getEventMap",
            "ermap": "getEventRMap",
            "fsm": "getFsmMap",
            "functionmap": "getFunctionMap",
            "functionrmap": "getFunctionRMap",
            "jmap": "getJobMap",
            "jrmap": "getJobRMap",
            "jobids": "getJobIds",
            "loggermap": "getLoggerMap",
            "loggeraliases": "getLoggerAliases",
            "logger_wfmap": "getLoggerWfMap",
            "logger_svcmap": "getLoggerSvcMap",
            "logger_jobmap": "getLoggerJobMap",
            "mmap": "getMapperMap",
            "mrmap": "getMapperRMap",
            "pipelines": "getPipelines",
            "pmap": "getProcessMap",
            "qmap": "getQueueMap",
            "qrmap": "getQueueRMap",
            "servicemap": "getServiceMap",
            "servicermap": "getServiceRMap",
            "serviceamap": "getServiceAMap",
            "stepmap": "getStepMap",
            "steprmap": "getStepRMap",
            "svcids": "getServiceIds",
            "systemserviceids": "getSystemServiceIds",
            "userserviceids": "getUserServiceIds",
            "vmmap": "getVMapMap",
            "vmrmap": "getVMapRMap",
            "wfids": "getWorkflowIds",
            "wfmap": "getWorkflowMap",
            "wfrmap": "getWorkflowRMap",
        );
    }

    string name() {
        return "metadata";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            *string method = Caches{arg};
            if (method)
                return new AttributeRestClass(call_object_method(Qorus.qmm, method));
            if (arg == "types") {
                return new AttributeRestClass(Qorus.qmm.listTypes());
            }
            if (arg == "locked_types") {
                return new AttributeRestClass(Qorus.qmm.getLockedTypes());
            }
        }
    }

    private hash unknownSubClassError(string n_name) {
        throw "REST-CLASS-ERROR", sprintf("class %y has no subclass %y; expecting one of: %y", name(), n_name, Caches.keys());
    }

    /** @REST PUT action=reload

        @par Description
        Reloads data in the named metadata caches and resets affected workflows, services, and jobs

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body); all keys are
        optional:
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
        - \c config_values: a list of config item names to reload in the metadata cache
        - \c types: a list of type paths to reload in the metadata cache

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
        - \c workflow_reset: a hash of workflow reset info; see the return value of @ref rest_api_PUT_workflows_reset
          for a description of this hash
        - \c service_reset: a hash of service reset info; see the return value of @ref rest_api_PUT_services_reset for
          a description of this hash
        - \c job_reset: a hash of job reset info; see the return value of @ref rest_api_PUT_jobs_reset for a
          description of this hash
        - \c types: the number of types in the metadata cache

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c METADATA-RELOAD-ERROR: unknown metadata keys passed
    */
    # reset: reload metadata and reset workflows, services, and jobs
    hash<HttpHandlerResponseInfo> putReload(hash<auto> cx, *hash<auto> ah) {
        return staticReload(cx, ah);
    }

    # static method to be used for per object id reset - for V1 and V3 metadata classes
    static hash<HttpHandlerResponseInfo> staticReload(hash<auto> cx, *hash<auto> ah) {
        # reload permissions checked below
        *hash<auto> h = ah{keys Reload};
        remove ah{keys h};
        if (ah)
            throw "METADATA-RELOAD-ERROR", sprintf("unknown keys %y in metadata reload call; known keys: %y", keys ah,
                keys Reload);

        rlog(cx);

        hash<auto> rv = {};
        *hash<auto> already_reset;
        # call interface reset methods with a reference to a hash of interfaces already reset
        map rv += (Interfaces{$1.key}
            ? call_object_method(Qorus.qmm, Reload{$1.key}, $1.value, False, \already_reset{$1.key})
            : call_object_method(Qorus.qmm, Reload{$1.key}, $1.value)),
            h.pairIterator();

        QDBG_LOG("MetadataRestClass::staticReload() already_reset: %y", already_reset);
        if (h.workflows) {
            if (already_reset.workflows) {
                h.workflows = map $1, h.workflows, !already_reset.workflows{$1};
            }
            if (h.workflows) {
                rv.workflow_reset = WorkflowRestClass::resetWorkflows(cx, h.workflows);
            }
        }
        if (h.services) {
            if (already_reset.services) {
                h.services = map $1, h.services, !already_reset.services{$1};
            }
            if (h.services) {
                rv.service_reset = ServiceRestClass::resetServices(cx, h.services);
            }
        }
        if (h.jobs) {
            if (already_reset.jobs) {
                h.jobs = map $1, h.jobs, !already_reset.jobs{$1};
            }
            if (h.jobs) {
                rv.job_reset = JobRestClass::resetJobs(cx, h.jobs);
            }
        }

        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /system

    This REST URI path provides actions and information for system functionality
*/
class SystemRestClass inherits QorusRestClass {
    public {
        const SubClasses = {
            "options": "SystemOptionsRestClass",
            "props": "SystemPropertiesRestClass",
            "sqlcache": "SqlCacheRestClass",
            "userhttp": "SystemUserHttpRestClass",
            "api": "SystemApiRestClass",
            "ui": "SystemUiRestClass",
            "alerts": "SystemAlertsRestClass",
            "health": "SystemHealthRestClass",
            "rbac": "RbacRestClass",
            "listeners": "ListenersRestClass",
            "debug": "DebugRestClass",
            "sessions": "SessionsRestClass",
            "metadata": "MetadataRestClass",
        };
    }

    string name() {
        return "system";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *string cls = doGetSubClasses(){arg};
        if (cls) {
            return create_object(cls);
        }
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            *hash<auto> h = internGetInfo(cx);
            if (h.hasKey(arg))
                return new AttributeRestClass(h{arg});
        }
    }

    private hash unknownSubClassError(string n_name) {
        throw "REST-CLASS-ERROR", sprintf("class %y has no subclass %y; expecting one of: %y", name(), n_name,
            keys doGetSubClasses());
    }

    /** @REST GET action=stream

        @par Description
        Returns a test stream depending on the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body); all keys are optional:
        - \c stream: (optional) the name of the stream to return; can be:
          - \c "DataStream": returns a short output @ref datastreamprotocol "DataStream" of lists of hashes
          - any other value: returns a short test stream of string data

        @par Return Value
        Returns a stream depending on the arguments; see above for details
    */
    AbstractRestStreamRequestHandler streamGetStream(hash<auto> cx, *hash<auto> ah) {
        if (ah.stream == "DataStream")
            return new TestDataStream(cx, ah);
        return new TestStream(cx, ah);
    }

    /** @REST PUT action=stream

        @par Description
        Returns a test stream depending on the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body); all keys are optional:
        - \c stream: (optional) the name of the stream to return; can be:
          - \c "DataStream": returns a short output @ref datastreamprotocol "DataStream" of lists of hashes
          - \c "EchoDataStream": returns an input/output @ref datastreamprotocol "DataStream" where the input is immediately returned as output
          - any other value: returns a short test stream of string data

        @par Return Value
        Returns a stream depending on the arguments; see above for details
    */
    AbstractRestStreamRequestHandler streamPutStream(hash<auto> cx, *hash<auto> ah) {
        if (ah.stream == "DataStream")
            return new TestDataStream(cx, ah);
        if (ah.stream == "EchoDataStream")
            return new EchoDataStream(cx, ah);
        return new TestStream(cx, ah);
    }

    /** @REST POST action=stream

        @par Description
        Returns a test stream depending on the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body); all keys are optional:
        - \c stream: (optional) the name of the stream to return; can be:
          - \c "DataStream": returns a short output @ref datastreamprotocol "DataStream" of lists of hashes
          - \c "EchoDataStream": returns an input/output @ref datastreamprotocol "DataStream" where the input is immediately returned as output
          - any other value: returns a short test stream of string data

        @par Return Value
        Returns a stream depending on the arguments; see above for details
    */
    AbstractRestStreamRequestHandler streamPostStream(hash<auto> cx, *hash<auto> ah) {
        if (ah.stream == "DataStream")
            return new TestDataStream(cx, ah);
        if (ah.stream == "EchoDataStream")
            return new EchoDataStream(cx, ah);
        return new TestStream(cx, ah);
    }

    /** @REST GET action=wstoken

        @SCHEMA
        @summary Returns an empty string in the Community Edition

        @desc Returns an empty string in the Community Edition

        @params
        - ttl (*int): ignored in the Community Edition

        @return (string): an empty string in the Community Edition
        @ENDSCHEMA
    */
    hash<auto> getWstoken(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, "");
    }

    /** @REST GET action=validateWsToken

        @SCHEMA
        @summary Returns nothing in the Community Edition

        @desc Returns nothing in the Community Edition; not implemented in the Community Edition

        @params
        - token (string): the token string

        @return (*string): returns nothing in the Community Edition

        @error (400): missing \c "token" argument or invalid argument type
        @ENDSCHEMA
    */
    hash<auto> getValidateWsToken(hash<auto> cx, *hash<auto> ah) {
        if (ah.token.typeCode() != NT_STRING)
            throw "VALIDATE-TOKEN-ARG-ERROR", "missing or invalid \"token\" argument";
        return RestHandler::makeResponse(200);
    }

    /** @REST GET action=echo

        @par Description
        Echos the argument(s) passed

        @par Arguments
        Accepts any arguments

        @par Return Value
        Returns all arguments as the response body
    */
    hash<auto> getEcho(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ah);
    }

    /** @REST PUT action=echo

        @SCHEMA
        @summary Echos the argument(s) passed

        @desc Echos the argument(s) passed

        @params (any)

        @return (any): all arguments are returned in the response body
        @ENDSCHEMA
    */
    hash<auto> putEcho(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ah);
    }

    /** @REST GET action=ping

        @SCHEMA
        @summary Returns \c "OK"

        @desc Returns \c "OK"

        @return (string): "OK"
        @ENDSCHEMA
    */
    hash<auto> getPing(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=rotateLogFiles

        @SCHEMA
        @summary Rotates all system log files

        @desc Rotates all system log files. The number of old log files kept is controlled by system option \
        @ref max-log-files .  It is recommended to use the \c qorus-log-rotator service to rotate log files instead \
        of calling this API method directly.

        @return (string): "OK"
        @ENDSCHEMA
    */
    hash<auto> putRotateLogFiles(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        # permissions are checked in QorusApp::rotateLogFiles()
        Qorus.rotateLogFiles(cx);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=reloadRbac

        @SCHEMA
        @summary Reloads the all @ref RBAC information (users, permissions, roles, groups) from the system schema

        @desc Reloads the all @ref RBAC information (users, permissions, roles, groups) from the system schema

        @return (string): "OK"
        @ENDSCHEMA
    */
    hash<auto> putReloadRbac(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        Qorus.rbac.reload();
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=shutdown

        @SCHEMA
        @summary Starts the asynchronous system shutdown process

        @desc This API will start the asynchronous shutdown process in the Qorus system.  The response indicates \
        only that the shutdown process has begun, and not that the system has been fully shut down.  Check the log \
        file or the process list to verify that the system has completely stopped.

        @return (string): "OK"
        @ENDSCHEMA

        @see
        - @ref rest_api_PUT_system_shutdownWait
        - @ref rest_api_PUT_system_restart
        - omq.system.shutdown()
        - omq.system.shutdown-wait()
    */
    hash<auto> putShutdown(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        bool wait = exists ah.wait ? parse_boolean(ah.wait) : False;

        if (Qorus.shutdown() && !wait)
            throw "SHUTDOWN-ALREADY-IN-PROGRESS", "system shutdown is already in progress";

        if (wait)
            Qorus.start_counter.waitForZero();

        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=shutdownWait

        @SCHEMA
        @summary Shuts down the system and returns when the system shutdown process is complete

        @desc Shuts down the system and returns when the system shutdown process is complete

        @return (string): "OK"
        @ENDSCHEMA

        @see
        - @ref rest_api_PUT_system_shutdown
        - @ref rest_api_PUT_system_restart
        - omq.system.shutdown()
        - omq.system.shutdown-wait()
    */
    hash<auto> putShutdownWait(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.shutdown();
        Qorus.start_counter.waitForZero();

        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=restart

        @par Description
        Shuts down and restarts the system; this call starts the process and returns immediately

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c timeout: (optional) a timeout in seconds; the currently running system will be killed if it does not shut down within this time period; if not given, the default timeout is 2 minutes (120 seconds)

        @par Return Value
        This API returns \c "OK" upon successful execution

        @see
        - @ref rest_api_PUT_system_shutdown
        - @ref rest_api_PUT_system_shutdownWait
        - omq.system.shutdown()
        - omq.system.shutdown-wait()
    */
    hash<auto> putRestart(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        if (exists ah.timeout)
            ah.timeout = int(ah.timeout);

        hash<auto> h.shutdown = Qorus.restart(ah.timeout)
            ? "system shutdown is already in progress"
            : "system shutdown started";

        return RestHandler::makeResponse(200, h);
    }

    hash<auto> internGetInfo(hash<auto> cx) {
        return qorus_get_system_info() + {
            "system_log_url": get_log_url(cx, "system"),
            "audit_log_url": get_log_url(cx, "audit"),
            "http_log_url": get_log_url(cx, "http"),
            "mon_log_url": get_log_url(cx, "mon"),
            "alert_log_url": get_log_url(cx, "alert"),
        };
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
        - \c omq-db-version: (any) database server version for the system \c "omq" datasource
        - \c omquser-schema: (string) \c "user@dbname" string for the \c "omquser" datasource
        - \c omquser-driver: (string) driver name for the \c "omquser" datasource
        - \c omquser-db-version: (any) database server version for the \c "omquser" datasource
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
        - \c debug: system debugging flag (when @ref True then more information is provided with exceptions)
        - \c health: a string color code for the health of the system with the following values:
          - \c "GREEN": good health
          - \c "YELLOW": warning
          - \c "RED": problems
        - \c system_log_url: a URL to the websocket source for the main system log
        - \c audit_log_url: a URL to the websocket source for the audit log
        - \c http_log_url: a URL to the websocket source for the HTTP server log
        - \c mon_log_url: a URL to the websocket source for the monitoring log
        - \c alert_log_url: a URL to the websocket source for the alert log
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, internGetInfo(cx));
    }

    /** @REST PUT action=setDebug

        @par Description
        Turns system debugging on or off; when system debugging is enabled, additional information is logged when exceptions are thrown

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c flag: (optional) parsed with @ref Qore::parse_boolean(); if @ref True then system debugging is enabled, if @ref False, then it is disabled; default value if not present: @ref True

        @par Return Value
        This API returns a hash with the following key:
        - \c system-debugging: the system debugging setting as a boolean value
    */
    hash<auto> putSetDebug(hash<auto> cx, *hash<auto> ah) {
        bool flag = ah.hasKey("flag") ? parse_boolean(ah.flag) : True;
        Qorus.setDebug(parse_boolean(flag));
        return RestHandler::makeResponse(200, ("system-debugging": flag));
    }

    private hash<string, string> doGetSubClasses() {
        return SubClasses;
    }
}

/** @REST /groups/{name}

    This URI path provides actions and information related to a specific @ref rbacgroups "interface group"
*/
class GroupRestClass inherits QorusRestClass {
    private {
        hash<auto> gh;
    }

    constructor(hash<auto> v_gh) {
        gh = v_gh;
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (gh.hasKey(name))
                return new AttributeRestClass(gh{name});
        }
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current @ref rbacgroups "interface group"

        @par Return Value
        This API returns a @ref rest_group_detail_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, gh);
    }

    string name() {
        return gh.name;
    }

    /** @REST PUT action=setStatus

        @par Description
        Changes the enabled status of an @ref rbacgroups "interface group"; changes are committed to the database before the call returns

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c enabled: (required) parsed with @ref Qore::parse_boolean(); the new enabled status for the group

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string describing the group enabled status change

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c GROUP-SETSTATUS-ERROR: missing \c enabled argument

        @see
        - @ref rest_api_PUT_groups__name__enable
        - @ref rest_api_PUT_groups__name__disable
        - @ref rest_api_PUT_groups__name__update
        - omq.system.group.set-status()
    */
    hash<auto> putSetStatus(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.enabled)
            throw "GROUP-SETSTATUS-ERROR", "missing \"enabled\" argument to update group status";

        rlog(cx);

        ah.enabled = parse_boolean(ah.enabled);

        if (gh.name == "DEFAULT") {
            return {
                "code": 403,
                "body": "cannot update group \"DEFAULT\"",
            };
        }

        api."omq.system.group.set-status"(gh.name, ah.enabled);
        hash<auto> rv = (
            "info": sprintf("updated group %y; enabled: %y", gh.name, ah.enabled),
            );
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=update

        @par Description
        Modifies an existing @ref rbacgroups "interface group"; changes are committed to the database before the call returns.
        Changes to groups are effected immediately; for example, if a workflow, service, or job is added to a disabled group, the any corresponding running objects are immediately stopped; or if a job is removed from a disabled group, then it is immediately started, etc

        @see This API is equivalent to @ref rest_api_PUT_groups__name_; see that documentation for details.
    */
    hash<auto> putUpdate(hash<auto> cx, *hash<auto> ah) {
        return put(cx, ah);
    }

    /** @REST PUT

        @par Description
        Modifies an existing @ref rbacgroups "interface group"; changes are committed to the database before the call returns.
        Changes to groups are effected immediately; for example, if a workflow, service, or job is added to a disabled group, the any corresponding running objects are immediately stopped; or if a job is removed from a disabled group, then it is immediately started, etc

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body); at least one of the following keys must be present:
        - \c desc: (string) the new description of the group
        - \c workflows: (list of strings or a single string) the list of workflow names to include in the group; the new list will replace the current list unless the workflow names are preceded by \c "+" or \c "-", meaning add or remove a workflow, respectively (in which case all workflow names must be preceded by a \c "+" or \c "-")
        - \c services: (list of strings or a single string) the list of user service names to include in the group; the new list will replace the current list unless the user service names are preceded by \c "+" or \c "-", meaning add or remove a service, respectively (in which case all service names must be preceded by a \c "+" or \c "-")
        - \c jobs: (list of strings or a single string) the list of job names to include in the group; the new list will replace the current list unless the job names are preceded by \c "+" or \c "-", meaning add or remove a job, respectively (in which case all job names must be preceded by a \c "+" or \c "-")
        - \c mappers: (list of strings or a single string) the list of @ref mappers "mapper" names to include in the group; the new list will replace the current list unless the mapper names are preceded by \c "+" or \c "-", meaning add or remove a mapper, respectively (in which case all mapper names must be preceded by a \c "+" or \c "-")
        - \c vmaps: (list of strings or a single string) the list of @ref value-maps "value map" names to include in the group; the new list will replace the current list unless the value map names are preceded by \c "+" or \c "-", meaning add or remove a value map, respectively (in which case all value map names must be preceded by a \c "+" or \c "-")
        - \c enabled: (string) this value will be processed by parse_boolean(); enables or disables the group

        @par Return Value
        This API returns \c "OK" upon successful execution

        - <tt><b>403 Forbidden</b></tt>: cannot update group \c "DEFAULT"
        - <tt><b>409 Conflict</b></tt>: \c RBAC-UPDATE-GROUP-ERROR: at least one of \c desc, \c services, \c workflows, \c jobs, \c mappers, \c vmaps, or \c enabled keys must be passed in the second argument hash to update the group

        @see
        - @ref rest_api_PUT_groups__name__update
        - omq.system.group.set-status()
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        if (gh.name == "DEFAULT") {
            return {
                "code": 403,
                "body": "cannot update group \"DEFAULT\"",
            };
        }

        api."omq.system.group.update"(gh.name, ah);
        return RestHandler::makeResponse(200, ah);
    }

    /** @REST PUT action=enable

        @par Description
        Enables an @ref rbacgroups "interface group"; changes are committed to the database before the call returns

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>403 Forbidden</b></tt>: cannot update group \c "DEFAULT"

        @see
        - @ref rest_api_PUT_groups__name__setStatus
        - @ref rest_api_PUT_groups__name__disable
        - @ref rest_api_PUT_groups__name__update
        - omq.system.group.set-status()
    */
    hash<auto> putEnable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.rbac.updateGroup(gh.name, ("enabled": True));
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=disable

        @par Description
        Disables an @ref rbacgroups "interace group"; changes are committed to the database before the call returns

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>403 Forbidden</b></tt>: cannot update group \c "DEFAULT"

        @see
        - @ref rest_api_PUT_groups__name__setStatus
        - @ref rest_api_PUT_groups__name__enable
        - @ref rest_api_PUT_groups__name__update
        - omq.system.group.set-status()
    */
    hash<auto> putDisable(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        if (gh.name == "DEFAULT") {
            return {
                "code": 403,
                "body": "cannot update group \"DEFAULT\"",
            };
        }

        Qorus.rbac.updateGroup(gh.name, ("enabled": False));
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST DELETE

        @par Description
        Permanently deletes an @ref rbacgroups "interface group"; changes are committed to the database before the call returns.
        When a disabled group is deleted, then any workflows with a positive autostart value, any services with the autostart flag set, and any active jobs are immediately started if the group was previously disabled and the workflow, service, or job is not a member of any other disabled group.

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string describing the group deletion action

        @par Errors
        - <tt><b>403 Forbidden</b></tt>: cannot update group \c "DEFAULT"

        @see
        - @ref rest_api_PUT_groups__name__update
        - omq.system.group.delete()
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        if (gh.name == "DEFAULT") {
            return {
                "code": 403,
                "body": "cannot update group \"DEFAULT\"",
            };
        }

        api."omq.system.group.delete"(gh.name);
        hash<auto> rv = (
            "info": sprintf("deleted group %y", gh.name),
            );
        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /groups

    This URI path provides actions and information related to @ref rbacgroups "interface groups"
*/
class GroupsRestClass inherits QorusRestClass {
    string name() {
        return "groups";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        hash<auto> group;
        try {
            group = Qorus.rbac.getGroupInfo(name);
        } catch (hash<ExceptionInfo> ex) {
            # ignore GROUP-ERROR (group does not exist) and return NOTHING
            if (ex.err == "GROUP-ERROR")
                return;
            rethrow;
        }
        return new GroupRestClass(group);
    }

    /** @REST PUT action=setStatus

        @par Description
        Changes the enabled status of one or more @ref rbacgroups "interface groups"; changes are committed to the database before the call returns

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c groups: (required) one or more group names to modify; a comma-separated string will be split into a list
        - \c enabled: (required) parsed with @ref Qore::parse_boolean(); the new enabled status for the group(s)

        @par Return Value
        This API returns list of descriptive strings for the operations performed

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c GROUPS-SETSTATUS-ERROR: missing \c groups or \c enabled arguments

        @see
        - @ref rest_api_PUT_groups__name__setStatus
        - @ref rest_api_PUT_groups__name__enable
        - @ref rest_api_PUT_groups__name__disable
        - @ref rest_api_PUT_groups__name__update
        - omq.system.group.set-status()
    */
    hash<auto> putSetStatus(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.enabled)
            throw "GROUPS-SETSTATUS-ERROR", "missing \"enabled\" argument to update groups status";

        if (!exists ah.groups)
            throw "GROUPS-SETSTATUS-ERROR", "missing \"groups\" argument to update groups status";

        rlog(cx);

        ah.enabled = parse_boolean(ah.enabled);

        if (ah.groups.typeCode() == NT_STRING)
            ah.groups = ah.groups.split(",");

        list l = ();

        foreach string group in (ah.groups) {
            try {
                if (ah.enabled)
                    Qorus.rbac.enableGroup(group);
                else
                    Qorus.rbac.disableGroup(group);
                l += sprintf("updated group %y; enabled: %y", group, ah.enabled);
            } catch (hash<ExceptionInfo> ex) {
                l += sprintf("error updating group %y: %s: %s", group, ex.err, ex.desc);
            }
        }

        return RestHandler::makeResponse(200, l);
    }

    /** @REST POST

        @par Description
        Creates a new @ref rbacgroups "interface group".  If a new group is created with the enabled flag set to @ref False,
        then workflows, services, and jobs members of the group are stopped immediately if loaded/running.
        Changes are committed to the database before the call returns.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c group: (string) required; the name of the group
        - \c desc: (string) required; the description of the group
        - \c workflows: (list of strings or a single string) optional; a comma-separated string will be split into a list; the list of workflow names or IDs to include in the group
        - \c services: (list of strings or a single string) optional; a comma-separated string will be split into a list; the list of user service names or IDs to include in the group
        - \c jobs: (list of strings or a single string) optional; a comma-separated string will be split into a list; the list of job names or IDs to include in the group
        - \c mappers: (list of strings or a single string) optional; a comma-separated string will be split into a list; the list of @ref mappers "mapper" names or IDs to include in the group
        - \c vmaps: (list of strings or a single string) optional; a comma-separated string will be split into a list the list of @ref value-maps "value map" names or IDs to include in the group
        - \c enabled: (string) this value will be processed by parse_boolean(); the initial enabled flag for the group; if not present defaults to @ref True

        @par Return Value
        This API returns a @ref rest_group_detail_hash for the new group

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c WORKFLOW-ERROR: invalid or unknown workflow
        - <tt><b>409 Conflict</b></tt>: \c SERVICE-ERROR: invalid or unknown service
        - <tt><b>409 Conflict</b></tt>: \c JOB-ERROR: invalid or unknown job
        - <tt><b>409 Conflict</b></tt>: \c MAPPER-ERROR: invalid or unknown mapper
        - <tt><b>409 Conflict</b></tt>: \c VALUE-MAP-ERROR: invalid or unknown value map
        - <tt><b>409 Conflict</b></tt>: \c GROUP-ERROR: missing \c group or \c desc arguments

        @see
        - omq.system.group.create()
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        return internPost(cx, ah);
    }

    private hash<HttpHandlerResponseInfo> internPost(hash<auto> cx, *hash<auto> ah, *int apiver) {
        if (!ah.group || ah.group.typeCode() != NT_STRING)
            throw "GROUP-ERROR", sprintf("missing 'group' argument giving the name for the new interface group");
        if (!ah.desc || ah.desc.typeCode() != NT_STRING)
            throw "GROUP-ERROR", sprintf("missing 'desc' argument giving the description for the new interface group");
        if (!OMQ::is_valid_object_name(ah.group)) {
            return RestHandler::makeResponse(400, sprintf("invalid characters in \"group\" name %y; allowed name "
                "format: [A-Za-z0-9-_]*", ah.group));
        }

        bool enabled = exists ah.enabled ? parse_boolean(ah.enabled) : True;

        rlog(cx);

        if (ah.workflows && ah.workflows.typeCode() == NT_STRING)
            ah.workflows = ah.workflows.split(",");

        foreach auto id in (\ah.workflows)
            id = WorkflowRestClass::staticGetWorkflowId(id, True);

        if (ah.services && ah.services.typeCode() == NT_STRING)
            ah.services = ah.services.split(",");

        foreach auto id in (\ah.services)
            id = ServiceRestClass::staticGetServiceId(id, True);

        if (ah.jobs && ah.jobs.typeCode() == NT_STRING)
            ah.jobs = ah.jobs.split(",");

        foreach auto id in (\ah.jobs)
            id = JobRestClass::staticGetJobId(id, True);

        if (ah.mappers && ah.mappers.typeCode() == NT_STRING)
            ah.mappers = ah.mappers.split(",");

        foreach auto id in (\ah.mappers)
            id = MapperRestClass::staticGetMapperId(id, True);

        if (ah.vmaps && ah.vmaps.typeCode() == NT_STRING)
            ah.vmaps = ah.vmaps.split(",");

        foreach auto id in (\ah.vmaps)
            id = ValueMapRestClass::staticGetVMapId(id, True);

        hash<auto> v5_ah;
        if (apiver >= 5) {
            v5_ah = ah;
            if (v5_ah.fsms && v5_ah.fsms.typeCode() == NT_STRING) {
                v5_ah.fsms = ah.fsms.split(",");
            }

            foreach softstring id in (\v5_ah.fsms) {
                if (!Qorus.qmm.lookupFsm(id)) {
                    throw "FSM-ERROR", sprintf("Finite State Machine %y does not exist", id);
                }
            }

            if (v5_ah.pipelines && v5_ah.pipelines.typeCode() == NT_STRING) {
                v5_ah.pipelines = v5_ah.pipelines.split(",");
            }

            foreach softstring id in (\v5_ah.pipelines) {
                if (!Qorus.qmm.lookupPipeline(id)) {
                    throw "PIPELINE-ERROR", sprintf("data pipeline %y does not exist", id);
                }
            }
        }

        Qorus.rbac.createGroup(ah.group, ah.desc, ah.services, ah.workflows, ah.jobs, ah.mappers, ah.vmaps,
            v5_ah.fsms, v5_ah.pipelines, enabled);
        return RestHandler::makeResponse(201, Qorus.rbac.getGroupInfo(ah.group));
    }

    /** @REST DELETE

        @par Description
        Permanently deletes one or more @ref rbacgroups "interface groups".
        Changes are committed to the database before the call returns.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c groups: (required) list of strings or a single string; a comma-separated string will be split into a list; the names of the groups to delete

        @par Return Value
        This API returns a list of string messages giving the result of each delete operation

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c GROUPS-DELETE-ERROR: missing \c groups argument

        @see
        - omq.system.group.delete()
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.groups)
            throw "GROUPS-DELETE-ERROR", "missing \"groups\" argument to delete groups";

        rlog(cx);

        if (ah.groups.typeCode() == NT_STRING)
            ah.groups = ah.groups.split(",");

        list l = ();

        foreach string group in (ah.groups) {
            try {
                Qorus.rbac.deleteGroup(group);
                l += sprintf("deleted group %y", group);
            } catch (hash<ExceptionInfo> ex) {
                l += sprintf("error deleting group %y: %s: %s", group, ex.err, ex.desc);
            }
        }

        return RestHandler::makeResponse(200, l);
    }

    static list staticGetGroupList(*hash<auto> ah) {
        hash<auto> gh = api."omq.system.group.info"();

        # filter out synthetic groups on request
        if (exists ah.no_synthetic && parse_boolean(ah.no_synthetic))
            gh -= (map $1.name, gh.iterator(), $1.synthetic);

        if (exists ah.list && parse_boolean(ah.list))
            return map $1.name, gh.iterator();

        if (exists ah.short && parse_boolean(ah.short))
            return map sprintf("%s: %s (wfs: %d svcs: %d jobs: %d)", $1.name, $1.description, $1.workflows.lsize(), $1.services.lsize(), $1.jobs.lsize()), gh.iterator();

        return map $1, gh.iterator();
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of information about @ref rbacgroups "interface groups"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body); at least one of the following keys must be present:
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of group names is returned
        - \c no_synthetic: optional; parsed with @ref Qore::parse_boolean(); if @ref True then synthetic groups will not be included in the return value
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of group names and descriptions is returned

        @par Return Value
        Unless \c list or \c short are present, this API returns a list of @ref rest_group_detail_hash elements according to the arguments.

        @see
        - omq.system.group.info()
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, GroupsRestClass::staticGetGroupList(ah));
    }

    /** @REST GET action=list

        @par Description
        Returns a list of hashes of information about @ref rbacgroups "interface groups"

        @see This API is equivalent to @ref rest_api_GET_groups; see that documentation for details.
    */
     hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }
}

/** @REST /users/{user}

    This REST URI path provides actions and information related to a particular user
*/
class UserRestClass inherits QorusRestClass {
    private {
        hash<auto> uh;
    }

    constructor(hash<auto> v_uh) {
        uh = v_uh;
    }

    *QorusRestClass subClassImpl(string id, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (uh.hasKey(id))
                return new AttributeRestClass(uh{id});
        }
    }

    /** @REST GET

        @par Description
        Returns a hash describing the current user

        @par Return Value
        This API returns a @ref rest_user_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, uh);
    }

    /** @REST PUT

        @par Description
        Modifies the current user

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body); at least one of the following keys must be present:
        - \c pass: (string) password
        - \c name: (string) user description
        - \c storage: (hash) updated key-value pairs for server-side user storage; set a key to NOTHING to delete the
          key
        - \c roles: (list of strings) a comma-separated string will be split into a list; the new list will replace
          the current list unless the role names are preceded by \c "+" or \c "-", meaning add or remove a role,
          respectively (in which case all role names must be preceded by a \c "+" or \c "-"); to remove all roles for
          a user, send an empty list here

        @par Return Value
        This API returns the updated attributes of the user as a hash

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c RBAC-UPDATE-USER-ERROR: invalid user, no valid keys in hash, invalid role

        @note This operation is a noop in the Community Edition

        @see
        - omq.system.update-user()
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(400, "This API is not supported in the Community Edition");
    }

    /** @REST PUT action=update

        @par Description
        Modifies the current user

        @see This API is equivalent to @ref rest_api_PUT_users__user_; see that documentation for details.
    */
    hash<auto> putUpdate(hash<auto> cx, *hash<auto> ah) {
        return put(cx, ah);
    }

    /** @REST DELETE

        @par Description
        Deletes the current user

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string describing the user deletion action

        @see
        - omq.system.delete-user()
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(400, "This API is not supported in the Community Edition");
    }

    string name() {
        return uh.username;
    }
}

/** @REST /users

    This REST URI path provides actions and information related to Qorus users

    @note This REST API class is not functional and is only provided for compatibility with the Enterprise Edition;
    the Community Edition does not support users
*/
class UsersRestClass inherits QorusRestClass {
    string name() {
        return "users";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        if (name == "_current_") {
            return new UserRestClass(RBAC::SystemUserDetails);
        }
    }

    static list staticGetUserList() {
        return ();
    }

    /** @REST GET

        @par Description
        Returns a list of hashes describing Qorus users

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of user names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of user names and descriptions is returned

        @par Return Value
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_user_hash elements

        @note Always returns an empty list in the Community Edition
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ());
    }

    /** @REST GET action=current

        @par Description
        Returns a hash describing the current calling user

        @par Return Value
        This API returns a @ref rest_user_hash
    */
    hash<auto> getCurrent(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, RBAC::SystemUserDetails);
    }

    /** @REST GET action=list

        @par Description
        Returns a list of hashes describing Qorus users

        @see This API is equivalent to @ref rest_api_GET_users; see that documentation for details.

        @note Always returns an empty list in the Community Edition
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST POST

        @par Description
        This API is not supported in the Community Edition

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: This API is not supported in the Community Edition

        @note Always returns a <tt>400 Bad Request</tt> response in the Community Edition

        @see
        - omq.system.add-user()
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(400, "This API is not supported in the Community Edition");
    }
}

/** @REST /roles

    This REST URI path provides actions and information related to Qorus roles

    @note This REST API class is not functional and is only provided for compatibility with the Enterprise Edition;
    the Community Edition does not support roles
*/
class RolesRestClass inherits QorusRestClass {
    string name() {
        return "roles";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
    }

    static list staticGetRoleList() {
        return ();
    }

    /** @REST GET

        @par Description
        Returns a list of hashes describing system roles

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of role names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings of role names and descriptions is returned

        @par Return Value
        Always an empty list in the Community Edition
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ());
    }

   /** @REST GET action=list

        @par Description
        Returns a list of hashes describing system roles

        @see This API is equivalent to @ref rest_api_GET_roles; see that documentation for details.
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST POST

        @par Description
        This API is not supported in the Community Edition

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: This API is not supported in the Community Edition

        @note Always returns a <tt>400 Bad Request</tt> response in the Community Edition
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(400, "This API is not supported in the Community Edition");
    }
}

/** @REST /debug/threads/{tid}

    This REST URI path provides actions and information related to a single Qorus thread
*/
class ThreadRestClass inherits QorusRestClass {
    private {
        list l;
    }

    constructor(list v_l) {
        l = v_l;
    }

    string name() {
        return "threads";
    }

    /** @REST GET

        @par Description
        Returns a hash describing the current thread

        @par Return Value
        This API returns a list of @ref rest_debug_callstack_hash elements showing the call stack sorted from most recent to oldest
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /debug/threads

    This REST URI path provides actions and information related to Qorus threads.
*/
class ThreadsRestClass inherits QorusRestClass {
    private {
        hash<auto> th;
    }

    constructor(hash<auto> v_th) {
        th = v_th;
    }

    string name() {
        return "threads";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        *list l = th{name};
        if (!l)
            return;

        return new ThreadRestClass(l);
    }

    /** @REST GET

        @par Description
        Returns a hash keyed by thread ID where the values are lists describing the call stack for the thread

        @par Return Value
        This API returns a hash keyed by thread ID where the values are lists of @ref rest_debug_callstack_hash elements showing the call stack for the thread sorted from most recent to oldest
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, th);
    }
}

/** @REST /debug/sync-cache

    This REST URI path provides information related to internal Qorus synchronization event cache data
*/

/** @REST /debug/sync-summary

    This REST URI path provides information related to internal Qorus synchronization event cache summary info
*/

/** @REST /debug/threads

    This REST URI path provides information related to Qorus threads
*/

/** @REST /debug/order-stats

    This REST URI path provides information related to internal Qorus order statistics processing data
*/

/** @REST /debug/order-stats-summary

    This REST URI path provides summary information related to internal Qorus order statistics processing data
*/

/** @REST /debug/order-stats

    This REST URI path provides information related to the internal Qorus service cache
*/

/** @REST /debug/interface-serialization

    This REST URI path provides information related to Qorus internal interface action serialization data
*/

/** @REST /debug/workflow-control

    This REST URI path provides information related to Qorus internal workflow control data
*/

class DebugWorkflowEntryRestClass inherits QorusRestClass {
    string name() {
        return "wf-entry";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            *hash<auto> rv = SM.getWFEntryDebugHash(name);
            return rv ? new AttributeRestClass(rv) : NOTHING;
        }
    }
}
/** @REST /debug/development

    This REST URI path provides information related to Qorus remote development data
*/

/** @REST /debug

    This REST URI path provides actions and information related to Qorus system debugging
*/
class DebugRestClass inherits QorusRestClass {
    constructor() {
        addClass(new DebugWorkflowEntryRestClass());
    }

    string name() {
        return "debug";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "threads": return new ThreadsRestClass(qorus_get_thread_stacks());
            case "sync-cache": return new AttributeRestClass(Qorus.SEM.TSC.toString());
            case "sync-summary": return new AttributeRestClass(Qorus.SEM.TSC.getSummary());
            case "order-stats": return new AttributeRestClass(Qorus.orderStats.getDetails());
            case "order-stats-summary": return new AttributeRestClass(Qorus.orderStats.getSummary());
            case "services": return new AttributeRestClass(services.getDebugInfo());
            case "interface-serialization": return new AttributeRestClass(AtomicClassActionHelper::getDebugInfo());
            case "workflow-control": return new AttributeRestClass(Qorus.control.getDebugInfo());
            case "jobs": return new AttributeRestClass(Qorus.jobManager.getDebugInfo());
            case "sm-data-cache": return new AttributeRestClass(SM.getDataCacheAsString());
            case "sm-data-cache-summary": return new AttributeRestClass(SM.getDataCacheSummary());
            case "sm-segment-cache": return new AttributeRestClass(SM.getCacheAsString());
            case "sm-segment-summary": return new AttributeRestClass(SM.getCacheSummary());
            case "sm-local": return new AttributeRestClass(SM.getLocalDebugInfo());
            case "development": return new AttributeRestClass(Qorus.remoteDevelopmentHandler.getDebugInfo());
            case "eventlog": return new AttributeRestClass(Qorus.eventLog.getDebugInfo());
            case "descriptors": return new AttributeRestClass({
                "total": QorusSharedApi::getNofile(),
                "used": QorusSharedApi::getCurrentNoFile(),
            });
        }
    }

    private *hash<string, bool> doGetPossibleSubClasses(hash<auto> cx, *hash<auto> ah) {
        return {
            "threads": True,
            "sync-cache": True,
            "sync-summary": True,
            "order-stats": True,
            "order-stats-summary": True,
            "services": True,
            "interface-serialization": True,
            "workflow-control": True,
            "jobs": True,
            "sm-data-cache": True,
            "sm-data-cache-summary": True,
            "sm-segment-cache": True,
            "sm-segment-summary": True,
            "sm-local": True,
            "development": True,
            "eventlog": True,
        };
    }
}

/** @REST /logs

    This REST URI path provides actions and information related to Qorus system logs and websocket log sources
*/
class LogsRestClass inherits QorusRestClass {
    string name() {
        return "logs";
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of system log file and websocket URL information

        @par Return Value
        This API returns a list of hashes with the following keys:
        - \c type: one of the following values:
          - \c "qorus-core": the main system log file
          - \c "audit": the system audit log file
          - \c "http": the HTTP log file
          - \c "mon": the system monitoring log file
          - \c "alert": the system alert log file
          - \c "workflow": a workflow log file
          - \c "service": a service log file
          - \c "job": a job log file
          - \c "qdsp": a @ref qdsp "qdsp" process log file
        - \c log: the log file path on the host filesystem
        - \c log_url: the websocket log URL for the log file
        - [\c name]: (for workflows, services, and jobs) the name of the interface
        - [\c version]: (for workflows, services, and jobs) the version of the interface
        - [\c workflowid]: (for workflows) the ID of the workflow
        - [\c serviceid]: (for services) the ID of the service
        - [\c jobid]: (for jobs) the ID of the job
        - [\c servicetype]: (for services) the type of the service (\c "system" or \c "user")
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        hash<auto> sih = UserApi::getSystemInfo();
        list<hash<auto>> ll = ();
        ll += {
            "type": "system",
            "log_url": get_log_url(cx, "qorus-core"),
        };
        ll += {
            "type": "qorus-master",
            "log_url": get_log_url(cx, "qorus-master"),
        };
        ll += {
            "type": "prometheus",
            "log_url": get_log_url(cx, "prometheus"),
        };
        ll += {
            "type": "grafana",
            "log_url": get_log_url(cx, "grafana"),
        };
        ll += {
            "type": "audit",
            "log_url": get_log_url(cx, "audit"),
        };
        ll += {
            "type": "http",
            "log_url": get_log_url(cx, "http"),
        };
        ll += {
            "type": "mon",
            "log_url": get_log_url(cx, "mon"),
        };
        ll += {
            "type": "alert",
            "log_url": get_log_url(cx, "alert"),
        };

        hash<auto> wh;

        # get workflow list
        list<hash<auto>> wfl = Qorus.control.getWorkflowInfoList();
        foreach hash<auto> eih in (wfl) {
            softstring wfid = eih.workflowid;
            if (wh{wfid})
                continue;
            wh{wfid} = True;
            ll += {
                "type": "workflow",
            } + eih.("name", "version", "workflowid") + {
                "log_url": get_log_url(cx, "workflows/%d", wfid),
            };
        }

        map ll += {
            "type": "service", +
            "servicetype": $1.type,
        } + $1.("name", "version", "serviceid", "log") + {
            "log_url": get_log_url(cx, "services/%d", $1.serviceid),
        }, ServiceRestClass::listAllServices();

        hash<auto> ji = Qorus.jobManager.getActiveInfo();
        map ll += {"type": "job"} + $1.("name", "version", "jobid") + {
            "log_url": get_log_url(cx, "jobs/%d", $1.jobid),
        }, ji.iterator();

        map ll += {
            "type": "qdsp",
            "name": $1,
            "log_url": get_log_url(cx, "qdsp/%s", $1),
        }, Qorus.dsmanager.getDatasourceList();

        return RestHandler::makeResponse(200, ll);
    }

    /** @REST GET action=list

        @par Description
        Returns a list of hashes of system log file and websocket URL information

        @see This API is equivalent to @ref rest_api_GET_logs; see that documentation for details.
    */
    hash<auto> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }
}

/** @REST /remote/user/{name}

    This REST URI path provides actions and information related to a specific @ref userconn "user connection"
*/
class UserConnectionRestClass inherits QorusRestClass {
    private {
        hash<auto> rh;
    }

    string name() {
        return rh.name;
    }

    constructor(hash<auto> v_rh) {
        rh = v_rh;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (rh.hasKey(arg))
                return new AttributeRestClass(rh{arg});
        }
    }

    /** @REST GET

        @par Description
        Returns a hash information for the current @ref userconn "user connection"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c with_password: (optional bool) include the password in the \c "url" and \c "url_hash" keys

        @par Return Value
        This API returns a @ref rest_user_remote_connection_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, rh);
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
    */
    hash<HttpHandlerResponseInfo> putPing(hash<auto> cx, *hash<auto> ah) {
        # += so we maintain "hash<auto>"
        hash<auto> rv += Qorus.connections.ping(rh.name);
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT

        @par Description
        Modifies the current @ref userconn "user connection"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c desc: (optional string) a new description for the connection
        - \c url: (optional string) a new URL for the connection
        - \c options: (optional hash) new options for the connection; also accepts \c "opts" as an alias for this
          option
        - \c tags: (optional hash) new tags for the connection

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string describing the connection update

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c USER-CONNECTION-ERROR: invalid or unparsable \c "options" key

        @note
        - \c opts is accepted as an alias for \c options
    */
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        if (!ah.desc || ah.desc.typeCode() != NT_STRING)
            ah.desc = rh.desc ?? rh.description;
        if (!ah.url || ah.url.typeCode() != NT_STRING)
            ah.url = rh.url;

        # issue #2972: accept also "opts"
        if (!ah.options && ah.hasKey("opts")) {
            ah.options = remove ah.opts;
        }

        # issue #3190: allow options to be deleted
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
        Qorus.connections.replace(rh.name, ah.desc, ah.url, attr, ah.options);

        hash<auto> rv = {
            "info": sprintf("updated user connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=update

        @par Description
        Modifies the current @ref userconn "user connection"

        @see This API is equivalent to @ref rest_api_PUT_remote_user__name_; see that documentation for details.
    */
    hash<auto> putUpdate(hash<auto> cx, *hash<auto> ah) {
        return put(cx, ah);
    }

    /** @REST DELETE

        @par Description
        Permanently deletes the current @ref userconn "user connection"

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the delete operation
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.connections.del(rh.name);

        hash<auto> rv = {
            "info": sprintf("deleted user connection %y", rh.name),
        };
        return RestHandler::makeResponse(200, rv);
    }
}

/** @REST /remote/user

    This REST URI path provides actions and information related to Qorus @ref userconn "user connections"
*/
class UserConnectionsRestClass inherits QorusRestClass {
    constructor() {
    }

    string name() {
        return "user";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
        *hash<auto> rh = Qorus.connections.getInfo(name, {"with_passwords": with_passwords});
        if (rh) {
            return new UserConnectionRestClass(rh);
        }
    }

    /** @REST GET

        @par Description
        Returns a list of hashes providing information for all @ref userconn "user connections"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of connection names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with connection names and brief info is returned

        @par Return Value
        This API returns a list of @ref rest_user_remote_connection_hash elements

        @see
        - @ref rest_api_GET_remote_all
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        *list l = Qorus.connections.list(parse_boolean(ah.monitored));

        # sort by name
        l = sort(l, int sub (hash<auto> lh, hash<auto> rh) {return lh.name <=> rh.name;});

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.name, l));
        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200, (map sprintf("%s: %s (%s)", $1.name, $1.url, $1.up ? "OK" : "DOWN"), l));

        return RestHandler::makeResponse(200, l);
    }

    /** @REST GET action=list

        @par Description
        Returns a list of hashes providing information for all @ref userconn "user connections"

        @see This API is equivalent to @ref rest_api_GET_remote_user; see that documentation for details.
    */
    hash<HttpHandlerResponseInfo> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST PUT action=reload

        @par Description
        Reloads all @ref userconn "user connections" from the database

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the reload operation
    */
    hash<HttpHandlerResponseInfo> putReload(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.connections.reload(cx);
        hash<auto> rv.info = "reloaded user connections from the system database";
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST POST

        @par Description
        Creates a new user connection from the arguments supplied

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c name: (required string) the name of the user connection
        - \c desc: (required string) the description for the new user connection
        - \c url: (required string) the URL for the new user connection
        - \c options: (optional hash) a hash of options for the user connection (also \c "opts" is accepted as an
          alias for \c "options")

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the user connection creation

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c USER-CONNECTION-ERROR: missing or invalid \c name, \c desc, \c url, or \c options arguments
        - <tt><b>409 Conflict</b></tt>: \c CONNECTION-ERROR: connection already exists; unknown scheme in URL

        @see
        - @ref userconntypes "User Connection Types" for information about supported user connection types
        - @ref connection-modules
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        hash<auto> rv = {
            "id": createConnection(cx, ah),
            "info": sprintf("created new user connection %y (%s) with URL %y", ah.name, ah.desc, ah.url),
        };
        return RestHandler::makeResponse(200, rv);
    }

    static int createConnection(hash<auto> cx, *hash<auto> ah, *softint id) {
        if (!ah.name || ah.name.typeCode() != NT_STRING)
            throw "USER-CONNECTION-ARG-ERROR", sprintf("missing 'name' argument giving the name for the new user "
                "connection (args: %y)", ah);
        if (!ah.desc || ah.desc.typeCode() != NT_STRING)
            throw "USER-CONNECTION-ARG-ERROR", sprintf("missing 'desc' argument giving the description for the new user "
                "connection (args: %y)", ah);
        if (!ah.url || ah.url.typeCode() != NT_STRING)
            throw "USER-CONNECTION-ARG-ERROR", sprintf("missing 'url' argument giving the URL for the new user "
                "connection (args: %y)", ah);

        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "name");
        if (error) {
            throw "USER-CONNECTION-ARG-ERROR", error.body;
        }

        rlog(cx);

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
        return Qorus.connections.registerConnection(ah.name, ah.desc, ah.url, attr, ah.options ?? {},
            id).internal_info.id;
    }
}

/** @REST /remote/qorus/{name}

    This REST URI path provides actions and information related to a specific @ref remoteconn "remote connection"
*/
class QorusRemoteConnectionRestClass inherits QorusRestClass {
    private {
        hash<auto> rh;
    }

    string name() {
        return rh.name;
    }

    constructor(hash<auto> v_rh) {
        rh = v_rh;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (rh.hasKey(arg))
                return new AttributeRestClass(rh{arg});
        }
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
    */
    hash<HttpHandlerResponseInfo> putPing(hash<auto> cx, *hash<auto> ah) {
        # += so we maintain "hash<auto>"
        hash<auto> rv += Qorus.remotemonitor.ping(rh.name);
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST GET

        @par Description
        Returns a hash information for the current @ref remoteconn "remote connection"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c with_password: (optional bool) include the password in the \c "url" and \c "url_hash" keys

        @par Return Value
        This API returns a @ref rest_user_remote_connection_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, rh);
    }
}

/** @REST /remote/qorus

    This REST URI path provides actions and information related to Qorus @ref remoteconn "remote connections"
*/
class QorusRemoteConnectionsRestClass inherits QorusRestClass {
    constructor() {
    }

    string name() {
        return "qorus";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        try {
            bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
            return new QorusRemoteConnectionRestClass({"name": name} + Qorus.remotemonitor.getInfo(name,
                {"with_passwords": with_passwords}));
        } catch (hash<ExceptionInfo> ex) {
        }
    }

    /** @REST PUT action=reload

        @par Description
        Reloads all @ref remoteconn "remote connections" from the database

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the reload operation
    */
    hash<HttpHandlerResponseInfo> putReload(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);

        Qorus.remotemonitor.reload(cx);
        hash<auto> rv.info = "reloaded Qorus connections from the system database";
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes providing information for all @ref remoteconn "remote connections"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of connection names is returned
        - \c monitored: optional; parsed with @ref Qore::parse_boolean(); if @ref True then only monitored connections are returned
        - \c remote: optional; parsed with @ref Qore::parse_boolean(); if @ref True then no loopback connections are returned; default if not present: @ref False
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with connection names and brief info is returned

        @par Return Value
        This API returns a list of @ref rest_user_remote_connection_hash elements

        @see
        - @ref rest_api_GET_remote_all
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        bool r = parse_boolean(ah.remote);
        bool m = parse_boolean(ah.monitored);
        list l = Qorus.remotemonitor.list(m, r);

        # sort by name
        l = sort(l, int sub (hash<auto> lh, hash<auto> rh) {return lh.name <=> rh.name;});

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.name, l));

        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200, (map sprintf("%s: %s (%s)", $1.name, $1.url, $1.up || $1.loopback ? "OK" : "DOWN"), l));

        return RestHandler::makeResponse(200, l);
    }

    /** @REST GET action=list

        @par Description
        Returns a list of hashes providing information for all @ref remoteconn "remote connections"

        @see This API is equivalent to @ref rest_api_GET_remote_qorus; see that documentation for details.
    */
    hash<HttpHandlerResponseInfo> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }
}

/** @REST /remote/datasources/{name}

    This REST URI path provides actions and information related to a specific Qorus system @ref dsconn "datasource"
*/
class DatasourceRestClass inherits QorusRestClass {
    private {
        hash<auto> rh;
    }

    string name() {
        return rh.name;
    }

    constructor(hash<auto> v_rh) {
        rh = v_rh;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (rh.hasKey(arg))
                return new AttributeRestClass(rh{arg});
        }
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
    */
    hash<HttpHandlerResponseInfo> putPing(hash<auto> cx, *hash<auto> ah) {
        # += so we maintain "hash<auto>"
        hash<auto> rv += Qorus.dsmanager.ping(rh.name);
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=reset

        @par Description
        Resets the current @ref dsconn "datasource"; after this call, any new requests for instances of this @ref dsconn "datasource" will result in a new datasource or datasource pool being opened

        @par Return Value
        This API returns \c "OK" upon successful execution

        @see @ref qdsp_reset
    */
    hash<HttpHandlerResponseInfo> putReset(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        Qorus.dsmanager.reset(rh.name);
        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT

        @par Description
        Updates the current @ref dsconn "datasource" in the server's internal cache

        @par Arguments
        This API takes a hash argument (either as URI arguments or in the message body) with the keys of a @ref datasource_hash

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c DATASOURCE-ERROR: this exception is thrown if the call tries to modify a locked system datasource or invalid options are passed

        @note
        - in order for any datasource changes to be put into effect, a separate call to
          @ref rest_api_PUT_remote_datasources__name__reset must be made
        - both \c "min" and \c "max" datasource options must be present to be used; if only one is present, it is ignored

        @see
        - @ref rest_api_PUT_remote_datasources__name__reset
        - @ref qdsp_reset
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        rlog(cx);
        Qorus.dsmanager.replace(rh.name, ah);

        return RestHandler::makeResponse(200, "OK");
    }

    /** @REST PUT action=update

        @par Description
        Temporarily updates the current @ref dsconn "datasource"

        @see This API is equivalent to @ref rest_api_PUT_remote_datasources__name_; see that documentation for details.
    */
    hash<HttpHandlerResponseInfo> putUpdate(hash<auto> cx, *hash<auto> ah) {
        return put(cx, ah);
    }

    /** @REST GET

        @par Description
        Returns a hash information for the current @ref dsconn "datasource"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c rtime: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the following attributes are returned as relative date/time values:
          - \c "warning-timeout"
          - \c "error-timeout"
          - \c "pool-wait-max"
        - \c with_password: parsed with @ref Qore::parse_boolean(); if @ref True then the \c pass key is returned in the @ref rest_datasource_connection_hash return value

        @par Return Value
        This API returns a @ref rest_datasource_connection_hash
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, rh);
    }

    /** @REST DELETE

        @par Description
        Deletes the given @ref dsconn "datasource" from the server's internal cache

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c DATASOURCE-ERROR: this exception is thrown if the given datasource does not exist or is a system datasource
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        # permissions checked in the datasource manager
        rlog(cx);
        Qorus.dsmanager.del(rh.name);
        return RestHandler::makeResponse(200, "OK");
    }
}

/** @REST /remote/datasources

    This REST URI path provides actions and information related to Qorus system @ref dsconn "datasources"
*/
class DatasourcesRestClass inherits QorusRestClass {
    constructor() {
    }

    string name() {
        return "datasources";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        try {
            bool with_passwords = cx.hdr.method != "GET" || parse_boolean(ah.with_password ?? ah.with_passwords);
            return new DatasourceRestClass(Qorus.dsmanager.getInfo(name, {
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

    /** @REST PUT action=reload

        @par Description
        Reloads all @ref dsconn "datasources" from the system database

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string confirming the reload operation
    */
    hash<HttpHandlerResponseInfo> putReload(hash<auto> cx, *hash<auto> ah) {
        # permissions checked in the datasource manager
        rlog(cx);

        Qorus.dsmanager.reload(cx);
        hash<auto> rv.info = "reloaded datasources from the system database";
        return RestHandler::makeResponse(200, rv);
    }

    /** @REST PUT action=flush

        @par Description
        removed since Qorus 4.0

        @par Return Value
        This API returns a hash with the following key:
        - \c info: a string indicating that no action was taken; this API no longer has any function

        @see
        - @ref rest_api_POST_remote_datasources
        - @ref rest_api_PUT_remote_datasources__name_
    */
    hash<HttpHandlerResponseInfo> putFlush(hash<auto> cx, *hash<auto> ah) {
        # permissions checked in the datasource manager
        rlog(cx);

        hash<auto> rv.info = "datasources are not stored in any file anymore";
        # 410 Gone
        return RestHandler::makeResponse(410, rv);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes providing information for all Qorus system @ref dsconn "datasources"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of datasource names is returned
        - \c rtime: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the following attributes are returned as relative date/time values:
          - \c "warning-timeout"
          - \c "error-timeout"
          - \c "pool-wait-max"
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with datasource names and brief info is returned
        - \c with_passwords: parsed with @ref Qore::parse_boolean(); if @ref True then the \c pass key is returned in the @ref rest_datasource_connection_hash elements

        @par Return Value
        This API returns a list of @ref rest_datasource_connection_hash elements

        @see
        - @ref rest_api_GET_remote_all
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        # permissions checked in the datasource manager
        list<auto> l = Qorus.dsmanager.list({
            "with_passwords": parse_boolean(ah.with_passwords),
            "rtime": parse_boolean(ah.rtime),
        });

        # sort by name
        l = sort(l, int sub (hash<auto> lh, hash<auto> rh) {return lh.name <=> rh.name;});

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.name, l));

        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200,
                (map sprintf("%s: %s (%s)", $1.name, $1.desc, $1.up ? "OK" : "DOWN"), l));

        return RestHandler::makeResponse(200, l);
    }

    /** @REST GET action=list

        @par Description
        Returns a list of hashes providing information for all Qorus system @ref dsconn "datasources"

        @see This API is equivalent to @ref rest_api_GET_remote_datasources; see that documentation for details.
    */
    hash<HttpHandlerResponseInfo> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }

    /** @REST POST

        @par Description
        Creates a new datasource connection in memory

        @par Arguments
        This API takes a hash argument (either as URI arguments or in the message body) with the keys of a @ref datasource_hash, plus the following key:
        - \c name: (required) the name of the new datasource

        @par Return Value
        This API returns \c "OK" upon successful execution
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        if (!ah.name || ah.name.typeCode() != NT_STRING)
            throw "DATASOURCE-ERROR", sprintf("missing 'name' argument giving the name for the new datasource");

        if (!ah.options && ah.hasKey("opts")) {
            ah.options = remove ah.opts;
        }

        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "name");
        if (exists error) {
            return error;
        }

        # permissions checked in the datasource manager
        Qorus.dsmanager.registerConnection(remove ah.name, ah);
        return RestHandler::makeResponse(200, "OK");
    }
}

/** @REST /remote

    This REST URI path provides actions and information about remote @ref remoteconn "Qorus", @ref userconn "user" and @ref dsconn "datasource" connections
*/
class RemoteRestClass inherits QorusRestClass {
    string name() {
        return "remote";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        switch (name) {
            case "qorus": return new QorusRemoteConnectionsRestClass();
            case "user": return new UserConnectionsRestClass();
            case "datasources": return new DatasourcesRestClass();
        }
    }

    /** @REST GET

        @par Description
        Returns a list of child URI path components

        @par Return Value
        Returns a list of child URI path components as follows:
        - \c "datasources": for the @ref rest_api_remote_datasources
        - \c "qorus": for the @ref rest_api_remote_qorus
        - \c "user": for the @ref rest_api_remote_user
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ("qorus", "user", "datasources"));
    }

    /** @REST GET action=all

        @par Description
        Returns a list of all remote connections (@ref remoteconn "remote connections" under \c "qorus", @ref userconn "user connections" under \c "user", and @ref dsconn "datasource connections" under \c "datasources")

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of connection names is returned
        - \c monitored: optional; (@ref remoteconn "remote" and @ref userconn "user" connections only) parsed with @ref Qore::parse_boolean(); if @ref True then only monitored connections are returned
        - \c remote: optional; (@ref remoteconn "remote connections") parsed with @ref Qore::parse_boolean(); if @ref True then no loopback connections are returned; default if not present: @ref False
        - \c rtime: optional; (@ref dsconn "datasource connections" only) parsed with @ref Qore::parse_boolean(); if @ref True then the following attributes are returned as relative date/time values:
          - \c "warning-timeout"
          - \c "error-timeout"
          - \c "pool-wait-max"
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with connection names and brief info is returned
        - \c with_passwords: (@ref dsconn "datasource connections" only) parsed with @ref Qore::parse_boolean(); if @ref True then the \c pass key is returned in the @ref rest_datasource_connection_hash return value

        @par Return Value
        Returns a list of hashes; the \c "conntype" value determines the hash format as follows:
        - \c "DATASOURCE": a @ref rest_datasource_connection_hash
        - \c "REMOTE" or \c "USER-CONNECTION": a @ref rest_user_remote_connection_hash

        @see
        - @ref rest_api_GET_remote_datasources
        - @ref rest_api_GET_remote_user
        - @ref rest_api_GET_remote_qorus
    */
    hash<HttpHandlerResponseInfo> getAll(hash<auto> cx, *hash<auto> ah) {
        list<auto> l = ();
        # get datasource connections
        l += Qorus.dsmanager.list({
            "with_passwords": parse_boolean(ah.with_passwords),
            "rtime": parse_boolean(ah.rtime),
        });
        # get user connections
        l += Qorus.connections.list(parse_boolean(ah.monitored));
        # get server connections
        l += Qorus.remotemonitor.list(parse_boolean(ah.monitored), parse_boolean(ah.remote));

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.name, l));

        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200, (map sprintf("%s: %s (%s)", $1.name, $1.desc, $1.up ? "OK" : "DOWN"), l));

        return RestHandler::makeResponse(200, l);
    }

    /** @REST GET action=list

        @par Description
        Returns a list of child URI path components

        @see This API is equivalent to @ref rest_api_GET_remote; see that documentation for details.
    */
    hash<HttpHandlerResponseInfo> getList(hash<auto> cx, *hash<auto> ah) {
        return get(cx, ah);
    }
}

/** @REST /perms

    This REST URI path provides actions and information related to RBAC permissions

    @note This REST API class is not functional and is only provided for compatibility with the Enterprise Edition;
    the Community Edition does not support permissions
*/
class PermsRestClass inherits QorusRestClass {
    string name() {
        return "perms";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
    }

    /** @REST GET

        @par Description
        Returns a list of information about permissions

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of permission names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with permission names and brief info is returned

        @par Return Value
        Returns a list of @ref rest_permission_hash elements
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ());
    }

    /** @REST POST

        @par Description
        Creates a new user permission

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c name: (required string) the name of the new user permission
        - \c desc: (required string) the description for the new user permission

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: This API is not supported in the Community Edition

        @note Always returns a <tt>400 Bad Request</tt> response in the Community Edition
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(400, "This API is not supported in the Community Edition");
    }
}

/** @REST /errors/{error}

    This URI path provides actions and information related to a specific @ref globalandworkflowerrors "workflow error"
*/
class ErrorRestClass inherits QorusRestClass {
    private {
        hash<auto> eh;
    }

    constructor(hash<auto> v_eh) {
        eh = v_eh;
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (eh.hasKey(name))
                return new AttributeRestClass(eh{name});
        }
    }

    string name() {
        return eh.error;
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current @ref globalandworkflowerrors "workflow error"

        @par Return Value
        Returns a @ref rest_workflow_error_description_hash_v1
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        # transform to the V1 API format
        bool retry_flag = (remove eh.status) == OMQ::StatRetry;
        return RestHandler::makeResponse(200, eh);
    }

    /** @REST PUT

        @par Description
        Updates the current @ref globalandworkflowerrors "workflow error" with the new definition given as arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c description: (string) the new description of the error
        - \c severity: (string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c retry_flag: (bool) parsed with @ref Qore::parse_boolean(); a retry flag value (if not present then @ref False is assumed)
        - \c business_flag: (bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only accepted if \c retry_flag is also @ref True)

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
    hash<auto> put(hash<auto> cx, *hash<auto> ah) {
        if (ah.error) {
            if (ah.error != eh.error)
                throw "UPDATE-ERROR", sprintf("cannot change the error name from %y to %y; first the existing error must be deleted and then the new error must be added", eh.error, ah.error);
        } else {
            ah.error = eh.error;
        }

        # convert REST API v1 args to V3
        if (parse_boolean(ah.retry_flag))
            ah.status = OMQ::StatRetry;
        else # not possible to set the status with REST API < v3
            remove ah.status;

        return eh.workflowid
            ? RestHandler::makeResponse(200, Qorus.EM.updateError(eh.workflowid, ah))
            : RestHandler::makeResponse(200, Qorus.EM.updateGlobalError(ah));
    }

    /** @REST PUT action=update

        @par Description
        Updates the current @ref globalandworkflowerrors "workflow error"

        @see This API is equivalent to @ref rest_api_PUT_errors__error_; see that documentation for details.
    */
    hash<auto> putUpdate(hash<auto> cx, *hash<auto> ah) {
        return put(cx, ah);
    }

    /** @REST DELETE

        @par Description
        Permanently deletes the current @ref globalandworkflowerrors "workflow error"

        @par Return Value
        This API returns \c "OK" upon successful execution
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        if (eh.workflowid)
            Qorus.EM.deleteWorkflowError(eh.workflowid, eh.error);
        else
            Qorus.EM.deleteError(cx.user, eh.error);

        return RestHandler::makeResponse(200, "OK");
    }
}

/** @REST /errors/global/{error} (/errors/{error})

    This URI path provides actions and information related to a specific @ref globalandworkflowerrors "global workflow error"
*/
    /** @REST PUT

        @par Description
        Updates the current @ref globalandworkflowerrors "global workflow error" with the new definition given as arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c description: (string) the new description of the error
        - \c severity: (string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c retry_flag: (bool) parsed with @ref Qore::parse_boolean(); a retry flag value (if not present then @ref False is assumed)
        - \c business_flag: (bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only used if \c retry_flag is also @ref True)

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "UPDATED-GLOBAL": the existing global error was updated
        - \c "CREATED-GLOBAL": a new global error was created (only possible in case of a race condition where the current error was deleted during this request)
        - \c "UNCHANGED-GLOBAL": the new global definition is identical to the old definition

        @see
        - @ref rest_api_PUT_errors__error_
        - @ref rest_api_PUT_errors_workflow__id_or_name___error_
        - omq.system.update-global-error()
        - omq.system.update-workflow-error()
    */
    /** @REST PUT action=update

        @par Description
        Updates the current @ref globalandworkflowerrors "global workflow error" with the new definition given as arguments

        @see This API is equivalent to @ref rest_api_PUT_errors_global__error_; see that documentation for details.
    */


/** @REST /errors/workflow/{id_or_name}/{error} (/errors/{error})

    This URI path provides actions and information related to a workflow-specific @ref globalandworkflowerrors "workflow error"
*/
    /** @REST PUT

        @par Description
        Updates the current workflow-specific @ref globalandworkflowerrors "workflow error" with the new definition given as arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c description: (string) the new description of the error
        - \c severity: (string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
        - \c retry_flag: (bool) parsed with @ref Qore::parse_boolean(); a retry flag value (if not present then @ref False is assumed)
        - \c business_flag: (bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only used if \c retry_flag is also @ref True)

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "UPDATED-WORKFLOW": the existing workflow-specific error was updated
        - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created (only possible in case of a race condition where the current error was deleted during this request)
        - \c "UNCHANGED-WORKFLOW": the new workflow-specific definition is identical to the old definition

        @see
        - @ref rest_api_PUT_errors__error_
        - @ref rest_api_PUT_errors_global__error_
        - omq.system.update-global-error()
        - omq.system.update-workflow-error()
    */
    /** @REST PUT action=update

        @par Description
        Updates the current workflow-specific @ref globalandworkflowerrors "workflow error" with the new definition given as arguments

        @see This API is equivalent to @ref rest_api_PUT_errors_workflow__id_or_name___error_; see that documentation for details.
    */

/** @REST /errors/global

    This REST URI path provides actions and information related to @ref globalandworkflowerrors "global workflow errors"
*/
class GlobalErrorsRestClass inherits QorusRestClass {
    string name() {
        return "global";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> eh = Qorus.EM.getGlobalError(name);
        if (eh)
            return new ErrorRestClass(eh);
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
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_workflow_error_description_hash_v1 elements for the @ref globalandworkflowerrors "global workflow errors" corresponding to the arguments
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        if (ah.errors.typeCode() == NT_STRING)
            ah.errors = ah.errors.split(",");

        list rl = Qorus.EM.getGlobalErrorsList(ah.errors);

        if (exists ah.list && parse_boolean(ah.list))
            rl = map $1.error, rl;
        else if (exists ah.short && parse_boolean(ah.short))
            rl = map sprintf("%s: (%s) retry: %y, business: %y, type: %s", $1.error, $1.severity, $1.status == OMQ::StatRetry, $1.business_flag, $1.type == "workflow" ? sprintf("%s v%s (%d)", $1.workflowname, $1.workflowversion, $1.workflowid) : "global"), rl;
        else # else convert to REST API v1/v2 format
            rl = map $1 + ("retry_flag": $1.status == OMQ::StatRetry) - "status", rl;

        return RestHandler::makeResponse(200, rl);
    }

    /** @REST POST action=createOrUpdate

        @par Description
        Creates or updates a @ref globalandworkflowerrors "global workflow error"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only used if \c retry_flag is also @ref True)
        - \c retry_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a retry flag value (if not present then @ref False is assumed)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes

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

        # convert REST API v1 args to V3
        if (parse_boolean(ah.retry_flag))
            ah.status = OMQ::StatRetry;
        else # not possible to set the status with REST API < v3
            remove ah.status;

        return RestHandler::makeResponse(200, Qorus.EM.updateGlobalError(ah));
    }

    /** @REST POST

        @par Description
        Creates a @ref globalandworkflowerrors "global workflow error"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only used if \c retry_flag is also @ref True)
        - \c retry_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a retry flag value (if not present then @ref False is assumed)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes

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

        # convert REST API v1 args to V3
        if (parse_boolean(ah.retry_flag))
            ah.status = OMQ::StatRetry;
        else # not possible to set the status with REST API < v3
            remove ah.status;

        return RestHandler::makeResponse(200, Qorus.EM.updateGlobalError(ah, False, True));
    }
}

/** @REST /errors/workflow/{id_or_name}

    This URI path provides actions and information related to workflow-specific @ref globalandworkflowerrors "workflow errors" for a particular workflow
*/
class WorkflowSpecificErrorsRestClass inherits QorusRestClass {
    private {
        int wfid;
    }

    constructor(int v_wfid) {
        wfid = v_wfid;
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> eh = Qorus.EM.getWorkflowError(wfid, name);
        if (eh)
            return new ErrorRestClass(eh);
    }

    softstring name() {
        return wfid;
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
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_workflow_error_description_hash_v1 elements for the @ref globalandworkflowerrors "workflow errors" for the current workflow corresponding to the arguments
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        if (ah.errors.typeCode() == NT_STRING)
            ah.errors = ah.errors.split(",");

        list rl = Qorus.EM.getErrorsList(wfid, ah.errors);

        if (exists ah.list && parse_boolean(ah.list))
            rl = map $1.error, rl;
        else if (exists ah.short && parse_boolean(ah.short))
            rl = map sprintf("%s: (%s) retry: %y, business: %y, type: %s", $1.error, $1.severity, $1.status == OMQ::StatRetry, $1.business_flag, $1.type == "workflow" ? sprintf("%s v%s (%d)", $1.workflowname, $1.workflowversion, $1.workflowid) : "global"), rl;
        else # else convert to REST API v1/v2 format
            rl = map $1 + ("retry_flag": $1.status == OMQ::StatRetry) - "status", rl;

        return RestHandler::makeResponse(200, rl);
    }

    /** @REST POST action=createOrUpdate

        @par Description
        Creates or updates a workflow-specific @ref globalandworkflowerrors "workflow error" for the current workflow

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only used if \c retry_flag is also @ref True)
        - \c retry_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a retry flag value (if not present then @ref False is assumed)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "UPDATED-WORKFLOW": the existing workflow-specific error was updated
        - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created
        - \c "UNCHANGED-WORKFLOW": the new workflow-specific definition is identical to the old definition
        - \c "CREATED-GLOBAL": a new global error was created (only possible if \c forceworkflow is omitted or @ref False)
        - \c "UNCHANGED-GLOBAL": the new global definition is identical to the old definition (only possible if \c forceworkflow is omitted or @ref False)

        @note
        - the default behavior of this API is to create a global error if no global error with the error name exists; in this case a workflow-specific error can be forced to be created by using the \c forceworkflow option as described above
    */
    hash<HttpHandlerResponseInfo> postCreateOrUpdate(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "error", N_WITH_DOT);
        if (exists error) {
            return error;
        }

        # convert REST API v1 args to V3
        if (parse_boolean(ah.retry_flag))
            ah.status = OMQ::StatRetry;
        else # not possible to set the status with REST API < v3
            remove ah.status;

        return RestHandler::makeResponse(200, Qorus.EM.updateWorkflowError(wfid, ah));
    }

    /** @REST POST

        @par Description
        Creates a workflow-specific @ref globalandworkflowerrors "workflow error" for the current workflow

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c forceworkflow: (optional) parsed with @ref Qore::parse_boolean(); if @ref True then the workflow error will be created as a workflow-specific error even if no global error exists; default if not present @ref False
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only used if \c retry_flag is also @ref True)
        - \c retry_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a retry flag value (if not present then @ref False is assumed)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes

        @par Return Value
        This API returns a string giving the result of the operation; one of:
        - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created
        - \c "CREATED-GLOBAL": a new global error was created (only possible if \c forceworkflow is omitted or @ref False)

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c ERROR-EXISTS: this exception is thrown if the workflow-specific error definition already exists

        @note
        - the default behavior of this API is to create a global error if no global error with the error name exists; in this case a workflow-specific error can be forced to be created by using the \c forceworkflow option as described above
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        *hash<HttpHandlerResponseInfo> error = QorusRestClass::validateObjectName(ah, "error", N_WITH_DOT);
        if (exists error) {
            return error;
        }

        # convert REST API v1 args to V3
        if (parse_boolean(ah.retry_flag))
            ah.status = OMQ::StatRetry;
        else # not possible to set the status with REST API < v3
            remove ah.status;

        if (ah.hasKey("forceworkflow") && parse_boolean(remove ah.forceworkflow))
            return RestHandler::makeResponse(200, Qorus.EM.updateWorkflowError(wfid, ah, False, True));

        return RestHandler::makeResponse(200, Qorus.EM.updateError(wfid, ah, False, True));
    }
}

/** @REST /workflows/{id_or_name}/errors (/errors/workflow/{id_or_name})

    This REST URI path provides actions and information about workflow order data instance errors for a particular workflow.
*/

/** @REST /errors/workflow

    This URI path provides actions and information related to workflow-specific @ref globalandworkflowerrors "workflow-specific workflow errors" across all workflows
*/
class WorkflowErrorsRestClass inherits QorusRestClass {
    string name() {
        return "workflow";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int wfid = WorkflowRestClass::staticGetWorkflowId(arg, True);

        return new WorkflowSpecificErrorsRestClass(wfid);
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
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_workflow_error_description_hash_v1 elements for the @ref globalandworkflowerrors "workflow errors" for the current workflow corresponding to the arguments
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        if (ah.errors.typeCode() == NT_STRING)
            ah.errors = ah.errors.split(",");

        list rl = Qorus.EM.getAllWorkflowErrorsList(cx.user, ah.errors);

        if (exists ah.list && parse_boolean(ah.list))
            rl = map $1.error, rl;
        else if (exists ah.short && parse_boolean(ah.short))
            rl = map sprintf("%s: (%s) retry: %y, business: %y, type: %s v%s (%d)", $1.error, $1.severity, $1.status == OMQ::StatRetry, $1.business_flag, $1.workflowname, $1.workflowversion, $1.workflowid), rl;
        else # else convert to REST API v1/v2 format
            rl = map $1 + ("retry_flag": $1.status == OMQ::StatRetry) - "status", rl;

        return RestHandler::makeResponse(200, rl);
    }
}

/** @REST /errors

    This URI path provides actions and information related to @ref globalandworkflowerrors "workflow errors"
*/
class ErrorsRestClass inherits QorusRestClass {
    string name() {
        return "errors";
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        *softlist el = Qorus.EM.getAllErrorsList(cx.user, name);
        if (!el) {
            if (name == "global")
                return new GlobalErrorsRestClass();
            if (name == "workflow")
                return new WorkflowErrorsRestClass();
            return;
        }

        if (el.size() == 1)
            return new ErrorRestClass(el[0]);

        list l = (map $1.workflowid ? sprintf("errors/workflow/%d/%s", $1.workflowid, name) : sprintf("errors/global/%s", name), el);
        throw "AMBIGUOUS-ERROR", sprintf("error %y has %d definitions; use one of the following URI fragments to access: %s", name, el.size(), (foldl $1 + ", " + $2, l));
    }

    static list staticGetErrors(hash<auto> cx, *hash<auto> ah) {
        if (ah.errors.typeCode() == NT_STRING)
            ah.errors = ah.errors.split(",");

        list rl;

        if (ah.filter == "global")
            rl = Qorus.EM.getGlobalErrorsList(ah.errors);
        else if (ah.wf) {
            int wfid = WorkflowRestClass::staticGetWorkflowId(ah.wf, True);
            rl = Qorus.EM.getErrorsList(wfid, ah.errors);
        } else
            rl = ah.errors ? Qorus.EM.searchList(cx.user, ah.errors) : Qorus.EM.getAllErrorsList(cx.user);

        return rl;
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
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_workflow_error_description_hash_v1 elements corresponding to the arguments
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        list rl = staticGetErrors(cx, ah);

        if (exists ah.list && parse_boolean(ah.list))
            rl = map $1.error, rl;
        else if (exists ah.short && parse_boolean(ah.short))
            rl = map sprintf("%s: (%s) retry: %y, business: %y, type: %s", $1.error, $1.severity, $1.status == OMQ::StatRetry, $1.business_flag, $1.type == "workflow" ? sprintf("%s v%s (%d)", $1.workflowname, $1.workflowversion, $1.workflowid) : "global"), rl;
        else # else convert to REST API v1/v2 format
            rl = map $1 + ("retry_flag": $1.status == OMQ::StatRetry) - "status", rl;

        return RestHandler::makeResponse(200, rl);
    }

    /** @REST GET action=search

        @par Description
        Returns a list of information of @ref globalandworkflowerrors "workflow errors" corresponding to the arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c errors: a comma-separated string will be split into a list; the @ref globalandworkflowerrors "workflow errors" to search for

        @par Return Value
        This API returns a list of @ref rest_workflow_error_description_hash_v1 elements corresponding to the arguments
    */
    hash<auto> getSearch(hash<auto> cx, *hash<auto> ah) {
        if (ah.errors.typeCode() == NT_STRING)
            ah.errors = ah.errors.split(",");

        if (!ah.errors)
            return RestHandler::makeResponse(200, ());

        return RestHandler::makeResponse(200, (map $1 + ("retry_flag": $1.status == OMQ::StatRetry) - "status", Qorus.EM.searchList(cx.user, ah.errors)));
    }

    /** @REST PUT action=reload

        @par Description
        Reloads all @ref globalandworkflowerrors "workflow error definitions" from the DB

        @par Return Value
        This API returns a hash with the following keys:
        - \c global: gives the number of global error definitions loaded
        - \c workflow: gives the number of all workflow-specific error definitions loaded

        @see
        - omq.system.reload-errors()
    */
    hash<auto> putReload(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, Qorus.EM.reload());
    }

    /** @REST POST action=createOrUpdate

        @par Description
        Creates or updates a @ref globalandworkflowerrors "workflow error"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c business_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a boolean business flag value (if not present then @ref False is assumed)
        - \c description: (required string) the description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c forceworkflow: (optional) parsed with @ref Qore::parse_boolean(); if @ref True then the workflow error will be created as a workflow-specific error even if no global error exists; default if not present @ref False; only used if \c workflowid also present
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only used if \c retry_flag is also @ref True)
        - \c retry_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a retry flag value (if not present then @ref False is assumed)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
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

        # convert REST API v1 args to V3
        if (parse_boolean(ah.retry_flag))
            ah.status = OMQ::StatRetry;
        else # not possible to set the status with REST API < v3
            remove ah.status;

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
        - \c description: (required string) the description of the error
        - \c error: (required string) the error string (ex: \c "SOCKET-SSL-ERROR")
        - \c forceworkflow: (optional) parsed with @ref Qore::parse_boolean(); if @ref True then the workflow error will be created as a workflow-specific error even if no global error exists; default if not present @ref False; only used if \c workflowid also present
        - \c retry_delay_secs: (optional int) an optional retry value in seconds (only used if \c retry_flag is also @ref True)
        - \c retry_flag: (optional bool) parsed with @ref Qore::parse_boolean(); a retry flag value (if not present then @ref False is assumed)
        - \c severity: (optional string) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
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

        # convert REST API v1 args to V3
        if (parse_boolean(ah.retry_flag))
            ah.status = OMQ::StatRetry;
        else # not possible to set the status with REST API < v3
            remove ah.status;

        if (ah.workflowid) {
            softint wfid = remove ah.workflowid;
            if (ah.hasKey("forceworkflow") && parse_boolean(remove ah.forceworkflow))
                return RestHandler::makeResponse(200, Qorus.EM.updateWorkflowError(wfid, ah, False, True));

            return RestHandler::makeResponse(200, Qorus.EM.updateError(wfid, ah, False, True));
        }

        return RestHandler::makeResponse(200, Qorus.EM.updateGlobalError(ah, False, True));
    }
}

/** @REST /mappers/{id_or_name}

    This URI path provides actions and information related to a specific system @ref mappers "mapper"
*/
class MapperRestClass inherits QorusRestClass {
    private {
        hash<auto> mh;
    }

    constructor(hash<auto> mh) {
        # remove any closure options
        mh.options = map {$1.key: $1.value}, mh.options.pairIterator(), !$1.value.callp();
        self.mh = mh;
    }

    string name() {
        return mh.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (mh.hasKey(arg))
                return new AttributeRestClass(mh{arg});
        }
    }

    /** @REST GET

        @par Description
        Returns a hash describing the current system @ref mappers "mapper"

        @par Return Value
        This API returns a @ref rest_mapper_description_hash with the following additional keys:
        - \c option_source: a hash of the source for the \c "options" key
        - \c field_source: a hash of the source for the actual mapper logic itself; keys are output field names

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c MAPPER-ERROR: invalid or unknown mapper
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, mh);
    }

    /** @REST PUT action=reload

        @par Description
        Reloads the current mapper from the DB

        @par Return Value
        This API returns \c "OK" upon successful execution
    */
    hash<auto> putReload(hash<auto> cx, *hash<auto> ah) {
        Qorus.mappers.reloadMapper(Qorus.qmm.lookupMapper(mh.mapperid));
        return RestHandler::makeResponse(200, "OK");
    }

    static softint staticGetMapperId(softstring arg, bool check = False, *reference mh) {
        if (arg =~ /[[:alpha:]]/u) {
            # we use "*string" for the name here in case invalid argument is passed (string starting with a colon, etc)
            (*string name, *string ver) = (arg =~ x/([^:]+)(?::(.+))?/);
            *hash<auto> h = name ? Qorus.qmm.rLookupMapper(name) : NOTHING;
            if (h) {
                if (ver) {
                    if (h{ver})
                        return h{ver};
                }
                else
                    return h.lastValue();
            }

            if (check)
                throw "MAPPER-ERROR", sprintf("can't find any mapper %y", arg);

            return 0;
        }

        if (check) {
            *hash<auto> h = Qorus.qmm.lookupMapper(arg);
            if (!h)
                throw "MAPPER-ERROR", sprintf("there is no mapper with mapperid %d", arg);
            mh = h;
        }

        return arg;
    }
}

/** @REST /mappers

    This URI path provides actions and information related to system @ref mappers "mappers"
*/
class MappersRestClass inherits QorusRestClass {
    string name() {
        return "mappers";
    }

    private MapperRestClass internGetMapperRestClass(int mapperid) {
        return new MapperRestClass(Qorus.mappers.getInfo(mapperid, True)
            + {"groups": Qorus.rbac.getMapperGroups(mapperid)});
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int mapperid;
        try {
            mapperid = MapperRestClass::staticGetMapperId(arg, True);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "MAPPER-ERROR"
                && (arg == "reload" || arg == "reloadAll")) {
                return NOTHING;
            }
            rethrow;
        }
        return internGetMapperRestClass(mapperid);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes describing all system @ref mappers "mappers"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c full: optional; parsed with @ref Qore::parse_boolean(); if @ref True then the output hashes will include mapper source information
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of mapper names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with mapper names and brief info is returned

        @par Return Value
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_mapper_description_hash elements; if the \c full option is used, then each hash has the following additional keys:
        - \c option_source: a hash of the source for the \c "options" key
        - \c field_source: a hash of the source for the actual mapper logic itself; keys are output field names
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        bool do_list = (exists ah.list && parse_boolean(ah.list));
        bool short = (exists ah.short && parse_boolean(ah.short));

        *list<auto> l = Qorus.mappers.listMappers(!do_list && !short && parse_boolean(ah.full));

        if (do_list)
            l = map $1.name, l;
        else if (short)
            l = map sprintf("%s v%s (%d) type: %s", $1.name, $1.version, $1.mapperid, $1.type), l;
        else {
            l = Qorus.rbac.addMapperGroupInfo(l);
            # issue #3244: do not include options with summary listings
            if (!ah.full) {
                l = map $1 + {"options": $1.options - ("runtime_keys", "input", "output")}, l;
            }
        }

        return RestHandler::makeResponse(200, l);
    }

    /** @REST PUT action=reload

        @par Description
        Reloads the @ref mappers "mappers" given in the \c ids argument from the DB

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) a comma-separated string will be split into a list; the mapper names or IDs to reset

        @par Return Value
        This API returns a list of the mapper IDs reset

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c MAPPER-ERROR: invalid or unknown mapper

        @see @ref rest_api_PUT_mappers_reloadAll
    */
    hash<auto> putReload(hash<auto> cx, *hash<auto> ah) {
        softlist ids = ah.ids.typeCode() == NT_STRING ? ah.ids.split(",") : ah.ids;

        if (!ids)
            throw "RELOAD-MAPPERS-ERROR", "'ids' argument missing giving mappers to reload";

        list<auto> mlist = ();
        foreach auto id in (ids) {
            hash<auto> mh;
            MapperRestClass::staticGetMapperId(id, True, \mh);
            mlist += mh;
        }

        # get a list of mapper IDs
        list<auto> l = map $1.mapperid, mlist;

        Qorus.mappers.reloadMappers(mlist);
        return RestHandler::makeResponse(200, l);
    }

    /** @REST PUT action=reloadAll

        @par Description
        Reloads all system @ref mappers "mappers"

        @par Return Value
        This API returns \c "OK" upon successful execution

        @see @ref rest_api_PUT_mappers_reload
    */
    hash<auto> putReloadAll(hash<auto> cx, *hash<auto> ah) {
        Qorus.mappers.reload();
        return RestHandler::makeResponse(200, "OK");
    }
}

/** @REST /mappertypes/{name}

    This REST URI path provides actions and information related to a specific @ref mapper-types "mapper type"

    @see @ref mapper-modules
*/
class MapperTypeRestClass inherits QorusRestClass {
    private {
        hash<auto> mth;
    }

    constructor(hash<auto> m) {
        mth = m;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (mth.hasKey(arg))
                return new AttributeRestClass(mth{arg});
        }
    }

    string name() {
        return mth.name;
    }

    /** @REST GET

        @par Description
        Returns a hash describing the current system @ref mapper-types "mapper type"

        @par Return Value
        This API returns a @ref rest_mapper_type_description_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, mth);
    }
}

/** @REST /mappertypes

    This REST URI path provides actions and information related to all @ref mapper-types "mapper types"

    @see @ref mapper-modules
*/
class MapperTypesRestClass inherits QorusRestClass {
    string name() {
        return "mappertypes";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        return new MapperTypeRestClass(Qorus.mappers.getProvider(arg));
    }

    /** @REST GET

        @par Description
        Returns a list of hashes describing the system @ref mapper-types "mapper types"

        @par Return Value
        This API returns a list of @ref rest_mapper_type_description_hash elements
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, Qorus.mappers.listProviders());
    }
}

/** @REST /valuemaps/{id_or_name}/{key}

    This URI path provides actions and information related to a specific @ref value-maps "value map" value
*/
/** @REST GET

    @par Description
    Returns the value of the current value map key

    @par Return Value
    This API returns the value of the current value map key
*/

/** @REST /valuemaps/{id_or_name}

    This URI path provides actions and information related to a specific @ref value-maps "value map"
*/
class ValueMapRestClass inherits QorusRestClass {
    private {
        hash<auto> m_map;
    }

    constructor(hash<auto> valuemap) {
        m_map = valuemap;
    }

    string name() {
        return m_map.name;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (m_map.hasKey(arg))
                return new AttributeRestClass(m_map{arg});

            if (arg == 'values')
                return new AttributeRestClass(Qorus.qmm.getVMapValue(m_map.name));

            # otherwise try to return the key value request
            return new AttributeRestClass(Qorus.qmm.getVMapValue(m_map.name, arg));
        }
    }

    /** @REST GET

        @par Description
        Returns a hash describing the current @ref value-maps "value map"

        @par Return Value
        This API returns a @ref rest_vmap_description_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, m_map);
    }

    /** @REST GET action=dump

        @par Description
        Returns a string giving the source of the @ref value-maps "value map" as reconstructed from the database

        @par Return Value
        This API returns a string giving the source of the value map as reconstructed from the database
    */
    hash<auto> getDump(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, (m_map.name : Qorus.qmm.dumpVMap(m_map.name)) );
    }

    /** @REST PUT action=value

        @par Description
        Creates or updates the mapping given as arguments in the current @ref value-maps "value map"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c key: (required) the value map key to create or update
        - \c value: (optional) the value to set; if not present, then the given key will be deleted
        - \c enabled: (optional) parsed with @ref Qore::parse_boolean(); if @ref True then the key is immediately usable; if not present the default is @ref False

        @par Return Value
        This API returns a string describing the operation performed:
        - \c "DELETED": the key was deleted
        - \c "IGNORED": the key to be deleted did not exist
        - \c "CREATED": the key-value pair was created
        - \c "UPDATED": the key-value pair was updated
    */
    hash<auto> putValue(hash<auto> cx, *hash<auto> ah) {
        if (ah.key.typeCode() != NT_STRING)
            throw "VALUEMAP-UPDATEVALUE-ERROR", sprintf("missing \"key\" string for update in value map %s (got type %y)", m_map.name, ah.key.type());
        return RestHandler::makeResponse(200, Qorus.qmm.setVMapValue(m_map.name, ah.key, ah.value, parse_boolean(ah.enabled)));
    }

    /** @REST GET action=lookup

        @par Description
        Looks up the mapping for the key given as an argument in the current @ref value-maps "value map" and returns the mapped value

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c key: (required) the value map key to look up

        @par Return Value
        This API returns the value of the key

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c VALUEMAP-LOOKUP-ERROR: missing \c key argument key
    */
    hash<auto> getLookup(hash<auto> cx, *hash<auto> ah) {
        if (ah.key.typeCode() != NT_STRING)
            throw "VALUEMAP-LOOKUP-ERROR", sprintf("missing \"key\" string for lookup in value map %s (got type %y)", m_map.name, ah.key.type());

        return RestHandler::makeResponse(200, Qorus.qmm.getVMapValue(m_map.name, ah.key));
    }

    /** @REST PUT action=reload

        @par Description
        Reloads the current @ref value-maps "value map" from the DB

        @par Return Value
        This API returns \c "OK" upon successful execution
    */
    hash<auto> putReload(hash<auto> cx, *hash<auto> ah) {
        Qorus.qmm.reloadVMaps(m_map.id);
        return RestHandler::makeResponse(200, "OK");
    }

    static softint staticGetVMapId(softstring arg, bool check = False, *reference vmh) {
        if (arg =~ /[[:alpha:]]/u) {
            *hash<auto> h = Qorus.qmm.rLookupVMap(arg, True);
            if (h)
                return (vmh = h).id;

            if (check)
                throw "VALUE-MAP-ERROR", sprintf("can't find any value map %y", arg);
        }

        if (check) {
            *hash<auto> h = Qorus.qmm.lookupVMap(arg, True);
            if (!h)
                throw "VALUE-MAP-ERROR", sprintf("there is no value map with id %d", arg);
            vmh = h;
        }

        return arg;
    }
}

/** @REST /valuemaps

    This URI path provides actions and information related to Qorus @ref value-maps "value maps"
*/
class ValueMapsRestClass inherits QorusRestClass {
    string name() {
        return "valuemaps";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> vs = arg == int(arg) ? Qorus.qmm.lookupVMap(arg, True) : Qorus.qmm.rLookupVMap(arg, True);

        if (vs) {
            return new ValueMapRestClass(vs);
        }
    }

    /** @REST GET

        @par Description
        Returns a list of hashes describing @ref value-maps "value maps"

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of value map names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with value map names and brief info is returned

        @par Return Value
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_vmap_description_hash elements
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        bool list = (exists ah.list && parse_boolean(ah.list));

        *hash<auto> h = Qorus.qmm.getVMapMap();

        list ret;
        if (h && list)
            ret = map $1.name, h.iterator();
        else if (exists ah.short && parse_boolean(ah.short))
            ret = map sprintf("%s (%d) size: %d", $1.name, $1.id, $1.mapsize), h.iterator();
        else
            ret = Qorus.rbac.addVMapGroupInfo(h.values());

        return RestHandler::makeResponse(200, ret);
    }

    /** @REST PUT action=reload

        @par Description
        Reloads one or more @ref value-maps "value maps" from the DB

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c ids: (required) a comma-separated string will be split into a list; the value map names or IDs to reset

        @par Return Value
        This API returns \c "OK" upon successful execution

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c VALUE-MAP-ERROR: invalid or unknown value map
    */
    hash<auto> putReload(hash<auto> cx, *hash<auto> ah) {
        ah.ids = ah.ids.typeCode() == NT_STRING ? ah.ids.split(",") : ah.ids;
        if (!ah.ids)
            throw "RELOAD-VALUE-MAPS-ERROR", "'ids' argument missing giving value maps to reload";

        list mlist = map ValueMapRestClass::staticGetVMapId($1, True), ah.ids;

        Qorus.qmm.reloadVMaps(mlist);
        return RestHandler::makeResponse(200, mlist);
    }

    /** @REST PUT action=reloadAll

        @par Description
        Reloads all @ref value-maps "value maps"

        @par Return Value
        This API returns \c "OK" upon successful execution
    */
    hash<auto> putReloadAll(hash<auto> cx, *hash<auto> ah) {
        Qorus.qmm.reloadVMaps();
        return RestHandler::makeResponse(200, "OK");
    }
}

/** @REST /async-queues

    This REST URI path provides actions and information about @ref queue_objects "queues for asynchronous workflow steps"
*/
class AsyncQueuesRestClass inherits QorusRestClass {
    private {
        *hash<auto> qh = (map {$1.key: ($1.value - (!$1.value.serviceid ? "serviceid" : ""))}, Qorus.qmm.getQueueMap().pairIterator());
    }

    string name() {
        return "async-queues";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            *hash<auto> mqh = qh{arg};
            if (mqh)
                return new AttributeRestClass(("queueid": arg.toInt()) + mqh);
            mqh = Qorus.qmm.rLookupQueue(arg);
            if (mqh) {
                if (!mqh.serviceid)
                    remove mqh.serviceid;
                return new AttributeRestClass(mqh + ("name": arg));
            }
        }
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the @ref queue_objects "asynchronous queue"

        @par Return Value
        This API returns a hash with the following keys:
        - \c queueid: the queue ID
        - \c name: the queue name
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        *list l = map ("queueid": $1.key.toInt()) + $1.value, qh.pairIterator();
        return RestHandler::makeResponse(200, l);
    }
}

/** @REST /releases/{release}

    This REST URI path provides actions and information about a specific Qorus release
*/
class ReleaseRestClass inherits QorusRestClass {
    private {
        hash<auto> rh;
    }

    constructor(list rl) {
        rh = ReleasesRestClass::fixReleases(rl)[0];
    }

    string name() {
        return rh.name;
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current release

        @par Return Value
        This API returns a hash with the following keys:
        - \c name: the name of the release
        - \c description: the description of the release
        - \c created: the date/time the release was created
        - \c modified: the date/time the release was last modified
        - \c files: a list of file components of the release; each list element is a hash with the following keys:
          - \c name: the full file path
          - \c type: the type of file
          - \c hash_type: the type of cryptographic hash for the file
          - \c hash: the cryptographic hash value of the file
          - \c created: the date/time the file entry was created with the release
          - \c modified: the last modified date/time of the file entry
          - \c components: a list of object components created from the file; each list element is a hash with the following keys:
            - \c component: the name of the component
            - \c version: the version of the component
            - \c id: the ID of the component (ex: if \c type = \c "FUNCTION", then \c id is a function ID)
            - \c content_id: the component content ID
            - \c hash_type: the type of cryptographic hash for the file
            - \c hash: the cryptographic hash value of the file
            - \c created: the date/time the file entry was created with the release
            - \c modified: the last modified date/time of the file entry
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, rh);
    }
}

/** @REST /releases

    This REST URI path provides actions and information about Qorus releases
*/
class ReleasesRestClass inherits QorusRestClass {
    string name() {
        return "releases";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *list l = sysinfo.searchReleases(("name": arg, "with_components": True));
        if (l)
            return new ReleaseRestClass(l);
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of information about release that match the search arguments

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c component: the component name to search for (implies <tt><b>with_files = True</b></tt> and <tt><b>with_components = True</b></tt>)
        - \c component_maxdate: the upper date range for the release search for component (implies <tt><b>with_files = True</b></tt> and <tt><b>with_components = True</b></tt>)
        - \c component_mindate: the lower date range for the release search for component (implies <tt><b>with_files = True</b></tt> and <tt><b>with_components = True</b></tt>)
        - \c file_maxdate: give the upper date range for the release search for files (implies <tt><b>with_files = True</b></tt>)
        - \c file_mindate: give the lower date range for the release search for files (implies <tt><b>with_files = True</b></tt>)
        - \c file_name: the file name to search for; note that this is used with the SQL like operator (implies <tt><b>with_files = True</b></tt>)
        - \c limit: the maximum number of releases to return
        - \c maxdate: give the upper date range for the release search
        - \c mindate: give the lower date range for the release search
        - \c offset: the starting release to return (use when paging for example)
        - \c with_components: if @ref True then file components are in

        @par Return Value
        This API returns a list of hashes matching the arguments; each hash element has the following keys:
        - \c name: the name of the release
        - \c description: the description of the release
        - \c created: the date/time the release was created
        - \c modified: the date/time the release was last modified
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, ReleasesRestClass::fixReleases(sysinfo.searchReleases(ah)));
    }

    # makes a list of releases with hierarchical information for files and contents / components
    static list fixReleases(list rl) {
        hash<auto> rh;
        hash<auto> fh;
        foreach hash<auto> row in (rl) {
            if (!rh{row.release_name}) {
                rh{row.release_name} = (
                    "name": row.release_name,
                    "description": row.description,
                    "created": row.created,
                    "modified": row.modified,
                    );
            }

            if (row.file_name && !fh{row.release_name}{row.file_name})
                fh{row.release_name}{row.file_name} = (
                    "name": row.file_name,
                    "type": row.file_type,
                    "hash_type": row.file_hash_type,
                    "hash": row.file_hash,
                    "created": row.file_created,
                    "modified": row.file_modified,
                ) + (row.component ? ("components": ()) : NOTHING);

            if (row.component)
                fh{row.release_name}{row.file_name}.components += (
                    "component": row.component,
                    "version": row.component_version,
                    "id": row.component_id,
                    "content_id": row.content_id,
                    "hash_type": row.component_hash_type,
                    "hash": row.component_hash,
                    "created": row.component_created,
                    "modified": row.component_modified,
                );
        }

        if (rl[0].file_name) {
            foreach string rn in (keys fh)
                rh{rn}.files = map fh{rn}.$1, keys fh{rn};
        }

        return map $1, rh.iterator();
    }
}

/** @REST /sync-events/{type}/{key}

    This REST URI path provides actions and information about a particular @ref wf_sync_event_objects "workflow synchronization event key"
*/
class SyncEventRestClass inherits QorusRestClass {
    private {
        hash<auto> eh;
    }

    constructor(hash<auto> h) {
        eh = h;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        # only return attributes if we have a GET request
        if (cx.hdr.method == "GET") {
            if (eh.hasKey(arg))
                return new AttributeRestClass(eh{arg});
        }
    }

    string name() {
        return eh.eventkey;
    }

    /** @REST PUT action=post

        @par Description
        Posts a workflow synchronization event, allowing all workflow steps blocked on that event to continue processing.

        @par Return Value
        This API returns a boolean value as follows:
        - @ref True "True": the event was posted for the first time with this call
        - @ref False "False": the event was already posted before this call

        @see
        - @ref rest_api_PUT_sync-events__type__post
        - omq.system.post-event()
        - @ref OMQ::UserApi::UserApi::postSyncEvent() "UserApi::postSyncEvent()"
    */
    hash<auto> putPost(hash<auto> cx, *hash<auto> ah) {
        bool wasposted = SM.postEvent(eh.id, eh.eventkey);
        return RestHandler::makeResponse(200, !wasposted);
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current workflow synchronization event

        @par Return Value
        This API returns a @ref rest_workflow_sync_event_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, eh);
    }
}

/** @REST /sync-events/{type}

    This REST URI path provides actions and information about @ref wf_sync_event_objects "workflow synchronization event types"
*/
class SyncEventTypeRestClass inherits QorusRestClass {
    private {
        hash<auto> eh;
    }

    constructor(hash<auto> h) {
        eh = h;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = sysinfo.searchEvents(("id": eh.id, "eventkey": arg))[0];
        if (h)
            return new SyncEventRestClass(h);
    }

    string name() {
        return eh.name;
    }

    /** @REST PUT action=post

        @par Description
        Posts a workflow synchronization event, allowing all workflow steps blocked on that event to continue processing.

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c eventkey: (required) the workflow synchronization event key

        @par Return Value
        This API returns a boolean value as follows:
        - @ref True "True": the event was posted for the first time with this call
        - @ref False "False": the event was already posted before this call

        @par Errors
        - <tt><b>409 Conflict</b></tt>: \c POST-ERROR: missing \c eventkey argument

        @see
        - @ref rest_api_PUT_sync-events__type___key__post
        - omq.system.post-event()
        - @ref OMQ::UserApi::UserApi::postSyncEvent() "UserApi::postSyncEvent()"
    */
    hash<auto> putPost(hash<auto> cx, *hash<auto> ah) {
        if (!exists ah.eventkey)
            throw "POST-ERROR", sprintf("missing string \"eventkey\" argument in workflow synchronization event post request for event type %y", eh.name);

        bool wasposted = SM.postEvent(eh.id, ah.eventkey);
        return RestHandler::makeResponse(200, !wasposted);
    }

    /** @REST GET

        @par Description
        Returns a hash of information about the current workflow synchronization event type

        @par Return Value
        This API returns a @ref rest_workflow_sync_event_type_hash
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, eh);
    }

    /** @REST GET action=events

        @par Description
        Returns a hash of information about the current workflow synchronization event type

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c desc: parsed with @ref Qore::parse_boolean(); if @ref True, return in descending order
        - \c eventkey: the event key value
        - \c eventname: the event type name
        - \c limit: max number of rows to return
        - \c maxmodified: if present, parsed as a date; maximum modified date
        - \c modified: if present, parsed as a date; minimum modified date
        - \c offset: row offset
        - \c posted: the event posted status (@ref True or @ref False)
        - \c sort: a comma-separated string will be split into a list;columns for sorting the results

        @par Return Value
        This API returns a list of @ref rest_workflow_sync_event_type_hash elements

        @see
        - @ref rest_api_GET_sync-events_events
    */
    hash<auto> getEvents(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, sysinfo.searchEvents(ah + ("id": eh.id)));
    }
}

/** @REST /sync-events

    This REST URI path provides actions and information about @ref wf_sync_event_objects "workflow synchronization events"
*/
class SyncEventTypesRestClass inherits QorusRestClass {
    string name() {
        return "sync-events";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        if (arg.toInt() == arg) {
            *hash<auto> eh = Qorus.qmm.lookupEvent(arg);
            if (eh)
                return new SyncEventTypeRestClass(("id": arg.toInt()) + eh - "workflow_event_typeid");
        }
        else {
            *hash<auto> eh = Qorus.qmm.rLookupEvent(arg);
            if (eh) {
                eh = (
                    "id": eh.workflow_event_typeid.toInt(),
                    "name": arg,
                    "desc": eh.desc,
                    );
                return new SyncEventTypeRestClass(eh);
            }
        }
    }

    /** @REST GET

        @par Description
        Returns a list of hashes of information about workflow synchronization event types

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of workflow synchronization event names is returned
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with workflow synchronization event names and brief info is returned

        @par Return Value
        If neither \a list nor \a short are used, then this API returns a list of @ref rest_workflow_sync_event_type_hash elements
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        hash<auto> h = Qorus.qmm.getEventMap();

        if (exists ah.list && parse_boolean(ah.list))
            return RestHandler::makeResponse(200, (map $1.toInt(), keys h));

        if (exists ah.short && parse_boolean(ah.short))
            return RestHandler::makeResponse(200, (map sprintf("%s: %d", $1.value.name, $1.key), h.pairIterator()));

        return RestHandler::makeResponse(200, (map ("id": $1.key.toInt()) + $1.value - "workflow_event_typeid", Qorus.qmm.getEventMap().pairIterator()));
    }

    /** @REST GET action=events

        @par Description
        Returns a hash of information about the current workflow synchronization event type

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c desc: parsed with @ref Qore::parse_boolean(); if @ref True, return in descending order
        - \c eventkey: the event key value
        - \c eventname: the event type name
        - \c id: one or more event type IDs
        - \c limit: max number of rows to return
        - \c maxmodified: if present, parsed as a date; maximum modified date
        - \c modified: if present, parsed as a date; minimum modified date
        - \c offset: row offset
        - \c posted: the event posted status (@ref True or @ref False)
        - \c sort: a comma-separated string will be split into a list;columns for sorting the results

        @par Return Value
        This API returns a list of @ref rest_workflow_sync_event_type_hash elements

        @see
        - @ref rest_api_GET_sync-events__type__events
    */
    hash<auto> getEvents(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, sysinfo.searchEvents(ah));
    }
}

class MetricsHandler inherits RestHandler {
    private {
        string path;
    }

    constructor(AbstractAuthenticator auth, string v_path) : RestHandler(auth) {
        path = v_path;
        addClass(new MetricsRestClass());
    }

    removeRootPath(reference v_path) {
        # remove root url from path
        v_path = regex_subst(v_path, path, "");
    }

    logInfo(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, fmt, argv);
    }

    logError(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::ERROR, fmt, argv);
    }

    logDebug(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::DEBUG, fmt, argv);
    }
}

class QorusRestHandlerBase inherits RestHandler {
    constructor(AbstractAuthenticator auth) : RestHandler(auth) {
    }

    private hash<HttpHandlerResponseInfo> returnRestException(hash<ExceptionInfo> ex) {
        if (ex.err =~ /-ARG-ERROR$/) {
            return <HttpHandlerResponseInfo>{
                "code": 400,
                "body": ex.desc,
            };
        }
        if (ex.err == "AUTHORIZATION-ERROR" || ex.err =~ /-ACCESS-ERROR$/) {
            return <HttpHandlerResponseInfo>{
                "code": 403,
                "body": ex,
            };
        }
        if (ex.err == "REST-NOT-FOUND-ERROR") {
            return <HttpHandlerResponseInfo>{
                "code": 404,
                "body": ex.desc,
            };
        }
        # for all other errors, return the standard "409 Conflict" response
        return RestHandler::returnRestException(ex);
    }

    private *hash<auto> errorResponseHeaders(hash<auto> cx) {
        return QorusHttpServer::getCorsResponseHeaders(cx);
    }
}

class WebAppHandler inherits QorusRestHandlerBase, QorusOptionsHandlerBase {
    public {}

    private {
        string path;
    }

    constructor(AbstractAuthenticator auth, string v_path) : QorusRestHandlerBase(auth) {
        path = v_path;
        addClass(new WorkflowRestClass());
        addClass(new GlobalOrderRestClass());
        addClass(new GlobalWorkflowExecRestClass());
        addClass(new ServiceRestClass());
        addClass(new JobRestClass());
        addClass(new SystemRestClass());
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
        addClass(new LogoutRestClass());

        # REST API v7
        addClass(new V7RestClass());

        # REST API v6
        addClass(new V6RestClass());

        # REST API v5
        addClass(new V5RestClass());

        # REST API v4
        addClass(new V4RestClass());

        # REST API v3
        addClass(new V3RestClass());

        # REST API v2
        addClass(new V2RestClass());

        # "latest" API
        addClass(new LatestRestClass());
    }

    removeRootPath(reference v_path) {
        # remove root url from path
        v_path = regex_subst(v_path, path + "/", "");
    }

    # custom data masking
    string maskData(string msg) {
        return WebAppHandler::maskMessage(msg);
    }

    static string maskMessage(string msg) {
        msg =~ s/((?:pass(?:word)?|sensitive(?:_data)?|svalue)"?[=:>\s]*).*/$1<masked>.../;
        return msg;
    }

    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr, *data b) {
        logDebug("REST Header: %N", hdr);

        # make sure
        if (hdr.method == "OPTIONS" && (*hash<auto> cors_hdrs = QorusHttpServer::getCorsResponseHeaders(cx))) {
            if (cors_hdrs) {
                # return a CORS response
                return AbstractHttpRequestHandler::makeResponse(200, NOTHING, cors_hdrs);
            }
        }

        # issue #3942: set time zone locale according to client's locale
        *TimeZone old_tz;
        auto client_tz;
        if (validator) {
            client_tz = hdr."qorus-client-time-zone";
            if (client_tz) {
                old_tz = validator.getTimeZoneLocale();
                try {
                    # parse as a UTC offset if a number
                    if (client_tz =~ /^-?[0-9]+$/) {
                        client_tz = client_tz.toInt();
                    }
                    validator.setTimeZoneLocale(new TimeZone(client_tz));
                    logInfo("Qorus-Client-Time-Zone: set request time zone to: %y", client_tz);
                } catch (hash<ExceptionInfo> ex) {
                    logError("Client request with time zone %y cannot be respected; ignoring client's time zone: %s: %s",
                        client_tz, ex.err, ex.desc);
                }
            }
        }
        on_exit if (client_tz) {
            validator.setTimeZoneLocale(old_tz);
        }

        cx.sctx.listener = listener;
        hash<HttpResponseInfo> rv = RestHandler::handleRequest(listener, s, cx, hdr, b);
        if (!rv.hdr."Access-Control-Allow-Origin") {
            rv.hdr += QorusHttpServer::getCorsResponseHeaders(cx);
        }
        return rv;
    }
}

class QorusWebSocketConnectionBase inherits WebSocketConnection {
    constructor(WebSocketHandler handler) : WebSocketConnection(handler) {
    }

    gotMessage(string msg) {
        if (msg == "ping") {
            send("pong");
            return;
        }
        send("error: unknown cmd");
    }
}

class WebAppConnection inherits QorusWebSocketConnectionBase {
    constructor(WebAppSocketHandler handler) : QorusWebSocketConnectionBase(handler) {
    }
}

class QorusWebSocketHandlerBase inherits WebSocketHandler {
    constructor() : WebSocketHandler(Qorus.qorusAuth) {
    }

    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr, *data body) {
        if (hdr.method == "OPTIONS") {
            return QorusHttpServer::handleOptions(cx);
        }
        hash<HttpResponseInfo> rv = WebSocketHandler::handleRequest(listener, s, cx, hdr, body);
        if (!rv.hdr."Access-Control-Allow-Origin") {
            rv.hdr += QorusHttpServer::getCorsResponseHeaders(cx);
        }
        return rv;
    }

    logInfo(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, "WebSocketHandler: " + fmt, argv);
    }

    logError(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::ERROR, "WebSocketHandler: " + fmt, argv);
    }

    logDebug(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::DEBUG, "WebSocketHandler: " + fmt, argv);
    }
}

class WebAppSocketHandler inherits QorusWebSocketHandlerBase {
    public {
        const ExitPollInterval = 250ms;

%ifdef WsBuffer
        # minimum delay between websocket messages for event aggregation
        const MinEventMs = 500;

        const MaxEvents = 100;
%endif

        # blacklist for UI events
        const NFilter = (
            {
                "eventhash": {
                    QEC_SERVICE_METHOD_PERFORMANCE: True,
                    QEC_WORKFLOW_STEP_PERFORMANCE: True,
                },
            },
            {
                "class": QE_CLASS_USER,
            },
        );

        #const EventKeys = ("time","eventstr","info","compositeseveritystr");
    }

    WebAppConnection getConnectionImpl(hash<auto> cx, hash<auto> hdr, softstring cid) {
        return new WebAppConnection(self);
    }

    eventListener() {
        int min_id = 1;

%ifdef WsBuffer
        list l = ();
        int lp = clock_getmillis();
%endif

        while (True) {
%ifndef WsBuffer
            hash<auto> eh = Qorus.events.getEvents(min_id, ExitPollInterval);
            if (eh.shutdown) {
                olog(LoggerLevel::INFO, "system is shutting down; stopping event thread");
                break;
            }
            #log(LoggerLevel::INFO, "DBG: eventListener() min_id: %y -> %y (eh.last_id: %y) eh.events.size(): %y", min_id, eh.lastid + 1, eh.last_id, eh.events.size());
            min_id = eh.lastid + 1;
            if (!eh.events)
                continue;
            try {
                sendAll(make_json(eh.events));
            } catch (hash<ExceptionInfo> ex) {
                printf("%s: %s: %N\n", ex.err, ex.desc, eh.events);
                rethrow;
            }
%else
            #hash eh = Qorus.events.getEvents(min_id, ExitPollInterval);
            hash<auto> eh = Qorus.events.getEventsAnd(min_id, NOTHING, ExitPollInterval, NOTHING, NFilter);
            if (eh.shutdown) {
                olog(LoggerLevel::INFO, "system is shutting down; stopping event thread");
                break;
            }

            # filter out unused event elements
            #eh.events = map $1{EventKeys}, eh.events;

            #map olog(LoggerLevel::DEBUG, "event %d %s %s", $1.id, $1.classstr, $1.eventstr), eh.events;

            min_id = eh.lastid + 1;

            if (eh.events)
                l += eh.events;
            else if (!l)
                continue;

            int np = clock_getmillis();
            #printf("size: %d lp+me: %d np: %d cont: %y\n", l.size(), lp + MinEventMs, np, (l.size() < MaxEvents && ((lp + MinEventMs) > np)));
            # if we have fewer than MaxEvents and the interval between messages was less than MinEvenMs, then buffer the events and try to get more
            if (l.size() < MaxEvents && ((lp + MinEventMs) > np))
                continue;

            lp = np;

            sendAll(make_json(l));
            l = ();
%endif
        }
    }
}

/*
class QorusPerfCacheWebSocketConnection inherits QorusWebSocketConnectionBase {
    public {
        list oidl;
        string cid;
    }

    private {
        # running flag
        bool running = True;

        # event Queue
        Queue q();

        # performance cache list
        list hl = ();

        # listener queue handles
        list qhl = ();
    }

    constructor(QorusPerfCacheWebSocketHandler handler, list n_oidl, string n_cid) : QorusWebSocketConnectionBase(handler) {
        oidl = n_oidl;
        cid = n_cid;

        # get PerformanceCache objects
        hl = map Qorus.pcm.add($1), oidl;

        # register listener Queues
        qhl = map $1.addListenerQueue(q), hl;

        background eventLoop();
    }

    destructor() {
        # deregister listener Queues
        map $1.removeListenerQueue(qhl[$#]), hl;

        # deregister performance cache handles
        map Qorus.pcm.del($1), hl;
    }

    private eventLoop() {
        while (running) {
            any m = q.get();
            #log(LoggerLevel::DEBUG, "QorusPerfCacheWebSocketConnection::eventLoop() oidl: %y m: %N", oidl, m);
            if (m)
                send(make_json(m));
        }
    }

    connectionClosed() {
        running = False;
        # signal for immediate exit
        q.push();
    }
}

class QorusPerfCacheWebSocketHandler inherits QorusWebSocketHandlerBase {
    # no public members
    public {}

    QorusPerfCacheWebSocketConnection getConnectionImpl(hash<auto> cx, hash<auto> hdr, string cid) {
        #logDebug("QorusPerfCacheWebSocketHandler::getConnectionImpl() cid %d: cx: %y", cid, cx);

        # check URL for which event source is required
        if (!cx.url.path)
            throw "QORUS-PERFACHE-WS-ERROR", sprintf("no path found in request URI: %y", cx.url);
        string path = cx.url.path;
        # strip /perfcache from path
        path =~ s/^perfcache(\/)?//;

        # strip any query args from path
        path =~ s/\?.*$//;

        # get perfcache type
        string type;
        if ((int i = path.find("/")) != -1) {
            type = extract path, 0, i;
            splice path, 0, 1;
        }
        else {
            type = path;
            delete path;
        }

        *list l = type ? type.split(",") : NOTHING;

        # check perf type
        if (!l)
            throw "QORUS-PERFCACHE-WS-ERROR", sprintf("invalid or unknown performance class list %y in URI path %y", l, cx.url.path);

        # validate perfcache list
        foreach string oid in (\l) {
            if (oid =~ /^w.+$/) {
                int id = WorkflowRestClass::staticGetWorkflowId(substr(oid, 1));
                if (!id)
                    throw "QORUS-PERFCACHE-WS-ERROR", sprintf("invalid workflow in performance cache id %y in %y", oid, l);
                oid = "w" + id;
            }
            else if (oid =~ /^s.+$/) {
                int id = ServiceRestClass::staticGetServiceId(substr(oid, 1));
                if (!id)
                    throw "QORUS-PERFCACHE-WS-ERROR", sprintf("invalid service in performance cache id %y in %y", oid, l);
                oid = "s" + id;
            }
            else if (oid =~ /^j.+$/) {
                int id = JobRestClass::staticGetJobId(substr(oid, 1));
                if (!id)
                    throw "QORUS-PERFCACHE-WS-ERROR", sprintf("invalid job in performance cache id %y in %y", oid, l);
                oid = "j" + id;
            }
            else if (oid =~ /^m[0-9]+$/) {
                if (!Qorus.qmm.lookupServiceMethod(oid.substr(1)))
                    throw "QORUS-PERFCACHE-WS-ERROR", sprintf("invalid service_methodid in performance cache id %y in %y", oid, l);
            }
            else if (!GlobalPerformanceCacheHash{oid})
                throw "QORUS-PERFCACHE-WS-ERROR", sprintf("invalid performance cache name %y in %y, expecing w<id> (for a workflow), s<id> for a service, j<id> for a job, m<id> for a service method, or one of the global performance caches: %y", oid, l, GlobalPerformanceCacheHash.keys());
        }

        return new QorusPerfCacheWebSocketConnection(self, l, cid);
    }
}
*/

class QorusLogWebSocketConnection inherits QorusWebSocketConnectionBase {
    public {
        string oid;
        string cid;
    }

    constructor(QorusLogWebSocketHandler handler, string n_oid, string n_cid) : QorusWebSocketConnectionBase(handler) {
        oid = n_oid;
        cid = n_cid;
    }

    destructor() {
    }
}

class QorusLogWebSocketHandler inherits QorusWebSocketHandlerBase {
    public {
        # try to get 100 lines of history in the log file when initially connecting
        const DefaultInitialLines = 100;

        # log types
        const LogTypes =
            (map {$1.uri_path: True}, SystemLoggerInfo.iterator())
            + InterfaceLoggers;
    }

    private {
        # read-write lock
        RWLock crwl();

        # hash: connection oid -> connection id -> connection object
        hash<auto> moh;

        # hash: oid -> number of subscribers to that object's log
        hash<string, int> subscriberCount;

        # access lock to subscriberCount
        Mutex subscribersCntLock();
    }

    hash<auto> getDebugInfo() {
        return {
            "subscriberCount": subscriberCount,
        };
    }

    bool isWorkflowLogRequested(softstring wfid) {
        return isLogRequested("w" + wfid);
    }

    bool isServiceLogRequested(softstring svcid) {
        return isLogRequested("s" + svcid);
    }

    bool isJobLogRequested(softstring jobid) {
        return isLogRequested("j" + jobid);
    }

    bool isQdspLogRequested(string name) {
        return isLogRequested("qdsp-" + name);
    }

    bool isLogRequested(string id) {
        subscribersCntLock.lock();
        on_exit {
            subscribersCntLock.unlock();
        }

        return subscriberCount{id} > 0;
    }

    QorusLogWebSocketConnection getConnectionImpl(hash<auto> cx, hash<auto> hdr, string cid) {
        #logDebug("QorusLogWebSocketHandler::getConnectionImpl() cid %d: cx: %y", cid, cx);
        # check URL for which log file is required
        if (!cx.url.path)
            throw "QORUS-LOG-WS-ERROR", sprintf("no path found in request URI: %y", cx.url);
        string path = cx.url.path;
        # strip /log from path
        path =~ s/^log//;

        # strip any query args from path
        path =~ s/\?.*$//;

        if (path[0] == "/")
            splice path, 0, 1;
        # get log type
        string type;
        if ((int i = path.find("/")) != -1) {
            type = extract path, 0, i;
            splice path, 0, 1;
        } else {
            type = path;
            delete path;
        }

        # create and validate object ID
        string oid;
        *string logFilePath;

        code getFirstLogFilename = *string sub (*hash<string, hash<AppenderParams>> h) {
            foreach hash<AppenderParams> ap in (h.iterator()) {
                if ((ap{"appenderType"} == "LoggerAppenderFileRotate" ||
                     ap{"appenderType"} == "LoggerAppenderFile") && ap.hasKey("filename")) {

                    return ap{"filename"};
                }
            }
        };

        *hash<LoggerParams> params;
        switch (type) {
            case "workflows": {
                hash<auto> wh;
                if (!path)
                    throw "QORUS-LOG-WS-ERROR", sprintf("invalid workflow name or id %y in URI path %y", path, cx.url.path);
                WorkflowRestClass::staticGetWorkflowId(path, True, \wh);

                hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                    "name": wh.name,
                    "id": wh.workflowid.toBase(),
                    "version": wh.version,
                };
                params = Qorus.loggerController.getLoggerParamsSubs("workflows", subs, wh.workflowid);
                oid = "w" + wh.workflowid;
                subscribeToLogIfNeeded(oid);
                break;
            }
            case "services": {
                hash<auto> sh;
                if (!path)
                    throw "QORUS-LOG-WS-ERROR", sprintf("invalid service name or id %y in URI path %y", path, cx.url.path);
                ServiceRestClass::staticGetServiceId(path, True, \sh);

                hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                    "name": sh.name,
                    "id": sh.serviceid.toBase(),
                    "version": sh.version,
                };
                params = Qorus.loggerController.getLoggerParamsSubs("services", subs, sh.serviceid);
                oid = "s" + sh.serviceid;
                subscribeToLogIfNeeded(oid);
                break;
            }
            case "jobs": {
                hash<auto> jh;
                if (!path)
                    throw "QORUS-LOG-WS-ERROR", sprintf("invalid job name or id %y in URI path %y", path, cx.url.path);
                JobRestClass::staticGetJobId(path, True, \jh);

                hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                    "name": jh.name,
                    "id": jh.jobid.toBase(),
                    "version": jh.version,
                };
                params = Qorus.loggerController.getLoggerParamsSubs("jobs", subs, jh.jobid);
                oid = "j" + jh.jobid;
                subscribeToLogIfNeeded(oid);
                break;
            }
            case "qdsp": {
                hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                    "name": path,
                };
                params = Qorus.loggerController.getLoggerParamsSubs("qdsp", subs, path);
                oid = "qdsp-" + path;
                subscribeToLogIfNeeded(oid);
                break;
            }
            case "qorus-core": {
                oid = "qorus-core";
                params = Qorus.loggerController.getLoggerParamsSubs("qorus-core");
                break;
            }
            case "prometheus":
            case "grafana":
            case "qorus-master": {
                oid = type;
                params = Qorus.loggerController.getLoggerParamsSubs(type);
                subscribeToLogIfNeeded(oid);
                break;
            }
            case "audit": {
                oid = "audit";
                params = Qorus.loggerController.getLoggerParamsSubs("AUDIT");
                break;
            }
            case "http": {
                oid = "http";
                params = Qorus.loggerController.getLoggerParamsSubs("HTTP");
                break;
            }
            case "mon": {
                oid = "mon";
                params = Qorus.loggerController.getLoggerParamsSubs("MONITORING");
                break;
            }
            case "alert": {
                oid = "alert";
                params = Qorus.loggerController.getLoggerParamsSubs("ALERT");
                break;
            }

            default: throw "QORUS-LOG-WS-ERROR", sprintf("invalid log class name %y; expecting one of: %y", type,
                keys LogTypes);
        }

        logFilePath = getFirstLogFilename(params{"appenders"});

        # get default history lines
        softint lines = hdr."qorus-log-history" > 0 ? hdr."qorus-log-history" : DefaultInitialLines;

        # see if the log file exists; if so, read in the history lines and send them to the client
        *string buf;
        if (logFilePath) {
            buf = QorusLogWebSocketHandler::staticGetBuffer(logFilePath, lines);
        }

        QorusLogWebSocketConnection sc(self, oid, cid);
        registerConnectionIntern(sc, oid, cid);

        if (buf)
            sc.send(buf);

        return sc;
    }

    static *string staticGetBuffer(string lfn, int lines) {
        File f();
        if (f.open(lfn))
            return;

        hash<auto> h = f.hstat();
        if (!h.size())
            return;

        # try 300 bytes per line
        int bs = lines * 300;

        int pos = h.size - bs;
        if (pos > 0)
            f.setPos(pos);

        # read all the data until the end of the file
        *string buf = f.read(-1);
        if (!buf)
            return;

        # see how many lines we have
        list<string> l = buf.split("\n");
        if (l > lines) {
            splice l, 0, (l - lines);
        } else {
            splice l, 0, 1;
        }

        return l.join("\n");
    }

    workflowLogEvent(softstring id, string str) {
        id = "w" + id;

        sendIntern(id, str);
    }

    serviceLogEvent(softstring id, string str) {
        id = "s" + id;

        sendIntern(id, str);
    }

    jobLogEvent(softstring id, string str) {
        id = "j" + id;

        sendIntern(id, str);
    }

    qdspLogEvent(softstring id, string str) {
        id = "qdsp-" + id;

        sendIntern(id, str);
    }

    logEvent(softstring id, string str) {
        sendIntern(id, str);
    }

    private sendIntern(string id, string str) {
        if (!self)
            return;

        crwl.readLock();
        on_exit crwl.readUnlock();

        #printf("QorusLogWebSocketHandler::sendIntern() id: %s msg: %y (%d) consumer cnt: %d\n", id, str, str.size(), moh{id}.size());flush();

        # do not even encode the msg if there are no consumers
        if (!moh{id}) {
            #QDBG_LOG("QorusLogWebSocketHandler::sendIntern() no consumer with id: %y found; known consumers: %y", id, keys moh);
            return;
        }

        # encode the msg
        binary msg = ws_encode_message(str);

        # send to all consumers
        map $1.sendEncoded(msg), moh{id}.iterator();
    }

    deregisterConnectionImpl(WebSocketConnection wsc) {
        QorusLogWebSocketConnection qwsc = wsc;
        QDBG_LOG("QorusLogWebSocketHandler::deregisterConnectionImpl() called on oid: %y cid: %y", qwsc.oid, qwsc.cid);
        unsubscribeFromLogIfNeeded(qwsc.oid);
        crwl.writeLock();
        on_exit crwl.writeUnlock();

        remove moh.(qwsc.oid).(qwsc.cid);
    }

    *hash<string, bool> getSubscriptions(*list<string> logs) {
        AutoLock subscriber_cnt_auto_lock(subscribersCntLock);
        return map {$1: True}, logs, subscriberCount{$1} > 0;
    }

    private registerConnectionIntern(WebSocketConnection sc, string oid, string cid) {
        # register new connection
        crwl.writeLock();
        on_exit crwl.writeUnlock();

        moh{oid}{cid} = sc;
    }

    #! Subscribe to the object's log if the object's counter goes up from 0 to 1
    private subscribeToLogIfNeeded(string oid) {
        AutoLock subscriber_cnt_auto_lock(subscribersCntLock);

        if (!subscriberCount{oid}) {
            subscriberCount{oid} = 1;
            # we need to unlock the lock before making the remote call
            subscriber_cnt_auto_lock.unlock();

            switch (oid) {
                case /^qdsp-/: {
                    string id = (oid =~ x/qdsp-(.+)$/)[0];
                    Qorus.dsmanager.enableLogging(id);
                    break;
                }
                case "prometheus":
                case "grafana":
                case "qorus-master": {
                    Qorus.subscribeToLog(oid);
                    break;
                }
                default: {
                    string id = oid[1..];
                    switch (oid[0]) {
                        case "w":
                            SM.enableLogging(id);
                            break;
                        case "s":
                            services.enableLogging(id);
                            break;
                        case "j":
                            Qorus.jobManager.enableLogging(id);
                            break;
                    }
                    break;
                }
            }
        } else {
            ++subscriberCount{oid};
        }
    }

    #! Unsubscribe from the log if the counter goes from 1 to 0
    private unsubscribeFromLogIfNeeded(string oid) {
        AutoLock subscriber_cnt_auto_lock(subscribersCntLock);

        QDBG_LOG("QorusLogWebSocketHandler::unsubscribeFromLogIfNeeded() oid: %y subs: %y", oid, subscriberCount);

        if (exists subscriberCount{oid}) {
            if (subscriberCount{oid} == 1) {
                subscriberCount{oid} = 0;
                # we need to unlock the lock before making the remote call
                subscriber_cnt_auto_lock.unlock();

                switch (oid) {
                    case /^qdsp-/: {
                        string id = (oid =~ x/qdsp-(.+)$/)[0];
                        Qorus.dsmanager.disableLogging(id);
                        break;
                    }
                    case "prometheus":
                    case "grafana":
                    case "qorus-master": {
                        Qorus.unsubscribeFromLog(oid);
                        break;
                    }
                    default: {
                        string id = oid[1..];
                        switch (oid[0]) {
                            case "w":
                                SM.disableLogging(id);
                                break;
                            case "s":
                                services.disableLogging(id);
                                break;
                            case "j":
                                Qorus.jobManager.disableLogging(id);
                                break;
                        }
                        break;
                    }
                }
            } else {
                QDBG_ASSERT(subscriberCount{oid} > 0);
                --subscriberCount{oid};
            }
        }
    }
}
