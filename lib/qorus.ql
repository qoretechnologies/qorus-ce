# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

#! @file qorus.ql defines constants for the Qorus Integration Engine

# this file is automatically included by the Qorus client library and its
# contents (except global variables) are automatically made available in
# server programs (both service and workflows) and should not be included
# directly by Qorus client programs

%new-style

#! main Qorus system namespace
public namespace OMQ {
    #! the default server port for Qorus servers if no other port is defined
    public const DefaultServerPort = 8001;

    /** @defgroup LibraryObjectTypes Workflow and Service Library Object Types
        These are the possible library object types for workflows and services
    */
    #/@{
    #! for constant library objects
    public const OT_CONSTANT = "CONSTANT";
    #! for class library objects
    public const OT_CLASS    = "CLASS";
    #! for function library objects
    public const OT_FUNCTION = "FUNCTION";
    #! for pipeline library objects
    /** @since Qorus 5.0 */
    public const OT_PIPELINE = "PIPELINE";
    #! for FSM library objects
    /** @since Qorus 5.0 */
    public const OT_FSM = "FSM";
    #! for mapper library objects (only for pipelines and FSMs)
    /** @since Qorus 5.0 */
    public const OT_MAPPER = "MAPPER";
    #/@}

    #! hash giving minimum versions of system services
    public const MinSystemServiceVersion = {
        "arch": "6.0",
        "fs": "6.0",
        "info": "6.0",
        "sqlutil": "6.0",
    };

    #! list of functions common to workflow, service, and job programs
    public const CommonAPI = (
        # some generic functions
        "xml_change_encoding",
        "xml_get_encoding",
        "next_sequence_value",
        "OMQ::UserApi::get_thread_call_stack",

        "restart_transaction",

        # functions no longer accessible due to updated parse restrictions or domain tagging
        ("import": "srand", "actual": "qsrand"),
    );

    #! list of functions specific to workflow programs
    public const WorkflowAPI = (
    ) + CommonAPI;

    #! all sandboxed Qorus code has at least the following parse options
    public const CommonParseOptions = PO_REQUIRE_OUR|PO_NO_TOP_LEVEL_STATEMENTS|PO_NO_THREAD_CONTROL
        |PO_NO_PROCESS_CONTROL|PO_NO_INHERIT_USER_FUNC_VARIANTS|PO_NO_INHERIT_GLOBAL_VARS|PO_NO_INHERIT_USER_CLASSES
        |PO_NO_INHERIT_USER_HASHDECLS|PO_ALLOW_WEAK_REFERENCES|PO_NO_INHERIT_PROGRAM_DATA;

    #! workflow programs will have the following parse options
    public const WorkflowParseOptions = CommonParseOptions|PO_NO_GLOBAL_VARS;
    #! backwards-compatible definition
    public const workflowParseOptions = WorkflowParseOptions;

    #! defines for all Qorus user code
    public const QorusServerDefines = (
        "Qorus",
        "QorusServer",
        "QorusHasUserConnections",
        "QorusHasAlerts",
        "QorusHasTableCache",
        "QorusCE",
    );

    #! defines for workflow programs
    public const QorusWorkflowDefines = QorusServerDefines + "QorusWorkflow";

    #! defines for service programs
    public const QorusServiceDefines = QorusServerDefines + (
        "QorusService",
        "QorusHasHttpUserIndex",
    );

    #! defines for job programs
    public const QorusJobDefines = QorusServerDefines + "QorusJob";

    #! defines for mapper programs
    public const QorusMapperDefines = QorusServerDefines + "QorusMapper";

    #! valid parse options for mappers
    public const MapperParseOptionList = (
        PO_REQUIRE_TYPES,
        PO_REQUIRE_PROTOTYPES,
        PO_STRICT_ARGS,
        PO_ASSUME_LOCAL,
        PO_ALLOW_BARE_REFS,
    );

    # mask of valid parse options for mappers
    public const MapperParseOptionMask = foldl $1 | $2, MapperParseOptionList;

    #! Default internal system username
    public const DefaultSystemUser = "%SYS%";

    /** @defgroup StepFunctionTypes Step Function Types
        These are the possible function types for step functions
    */
    #/@{
    #! step function type
    public const FT_Step        = "STEP";
    #! generic function type
    public const FT_Generic     = "GENERIC";
    #! async start function type for async steps
    public const FT_AsyncStart  = "ASYNC-START";
    #! async end function type for async steps
    public const FT_AsyncEnd    = "ASYNC-END";
    #! validation function type
    public const FT_Validation  = "VALIDATION";
    #! array function type
    public const FT_Array       = "ARRAY";
    #! subworkflow function type
    public const FT_Subworkflow = "SUBWORKFLOW";
    #/@}

    #! list of all valid function types
    public const AllFunctionTypes = (
        FT_Step,
        FT_Generic,
        FT_AsyncStart,
        FT_AsyncEnd,
        FT_Validation,
        FT_Array,
        FT_Subworkflow,
    );

    /** @defgroup StepTypes Step Types
        These are the possible types for steps
    */
    #/@{
    #! step attribute: for normal steps
    public const ExecNormal      = "NORMAL";
    #! step attribute: for async steps
    public const ExecAsync       = "ASYNC";
    #! step attribute: for subworkflow steps
    public const ExecSubWorkflow = "SUBWORKFLOW";
    #! step attribute: for synchronization event steps
    public const ExecEvent       = "EVENT";
    #/@}

    /** @defgroup StepArrayTypes Step Array Attribute Values
        These are the possible values for the array attribute of a step
    */
    #/@{
    #! array type: for non-array steps
    public const ArrayNone     = "NONE";
    #! array type: executed in series (only valid array type)
    public const ArraySeries   = "SERIES";
    #! array type: executed in parallel (not implemented; do not use)
    public const ArrayParallel = "PARALLEL";
    #/@}

    #! list of functions imported into service program objects
    public const ServiceAPI = (
        # Qorus and Service API
        "slog_args",

        # functions with identical names to workflow functions
        ("import": "OMQ::UserApi::getOption", "actual": "qorus_api_service_get_option", "check": True),
        ("import": "OMQ::UserApi::setOption", "actual": "qorus_api_service_set_option", "check": True),
        ("import": "OMQ::UserApi::get_option", "actual": "qorus_api_service_get_option", "check": True),
        ("import": "OMQ::UserApi::set_option", "actual": "qorus_api_service_set_option", "check": True),
        ("import": "OMQ::UserApi::log", "actual": "service_log", "check": True),
        ("import": "OMQ::UserApi::log_args", "actual": "service_log_args", "check": True),
        ("import": "OMQ::UserApi::audit_user_event", "actual": "service_audit_user_event", "check": True),
        ("import": "OMQ::UserApi::omqsleep", "actual": "service_sleep"),
        ("import": "OMQ::UserApi::omqusleep", "actual": "service_usleep"),
    ) + CommonAPI;

    #! list of functions imported into only into system service program objects
    public const SystemServiceAPI = (
        "process_audit_events",
        "qorus_get_thread_stacks",
        "get_sql_table_system",
        "get_sql_table_system_trans",
        "get_sql_cache_info_system",
    );

    /** @defgroup ServiceStatuses Service Status Values
        These are the possible values for the status of a service
    */
    #/@{
    #! service status: running
    public const SSRunning = "running";
    #! service status: running
    public const SSLoaded  = "loaded";
    #/@}

    /** @defgroup MethodLockAttributes Service Method Lock Attribute Values
        These are the possible values for the lock attribute of a service method
    */
    #/@{
    #! service lock type: none
    public const SLNone  = "none";
    #! service lock type: read
    public const SLRead  = "read";
    #! service lock type: write
    public const SLWrite = "write";
    #/@}

    #! list of all service lock types
    public const AllSLTypes = (SLNone, SLRead, SLWrite);

    #! services will have the following parse options
    public const ServiceParseOptions = CommonParseOptions;

    #! backwards-compatible definition
    public const serviceParseOptions = ServiceParseOptions;

    #! system services additionally have the following parse options
    public const SystemServiceParseOptions = 0;

    #! backwards-compatible definition
    public const systemServiceParseOptions = SystemServiceParseOptions;

    #! valid additional parse options for services
    public const ServiceParseOptionList = (
        PO_REQUIRE_TYPES,
        PO_REQUIRE_PROTOTYPES,
        PO_STRICT_ARGS,
        PO_ASSUME_LOCAL,
        PO_ALLOW_BARE_REFS,
    );

    # mask of valid parse options for mappers
    public const ServiceParseOptionMask = foldl $1 | $2, ServiceParseOptionList;

    /** @defgroup WorkflowExecStatus Workflow Execution Instance Status Values
        These are the possible values for a workflow execution instance
    */
    #/@{
    #! workflow instance status: initializing
    public const WISInitializing = "initializing";
    #! workflow instance status: running
    public const WISRunning      = "running";
    #! workflow instance status: waiting
    public const WISWaiting      = "waiting";
    #! workflow instance status: stopping
    public const WISStopping     = "stopping";
    #/@}

    /** @defgroup StatusDescriptions Workflow, Segment, and Step Status Descriptions
        These are the possible values for the descriptive status of a workflow order data instance; most of these can also be
        used for the status of a segment instance and a step instance.

        @note Descriptive status values are returned by almost all API functions even though @ref SQLStatusCodes "abbreviated codes" are actually stored in the database; this is mainly for backwards compatibility.

        @see
        - @ref SQLStatusCodes for the corresponding values stored in the database
        - @ref OMQ::StatMap for a hash that can be used to map from descriptive status codes to @ref SQLStatusCodes
        - @ref OMQ::SQLStatMap for a hash that can be used to map from SQL status codes to @ref StatusDescriptions
    */
    #/@{
    #! This status indicates that the object it is attached to has successfully completed its processing
    /** This is a final status; once a workflow, segment, or step is \c COMPLETE, it will not be processed anymore.

        @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatComplete
    */
    public const StatComplete       = "COMPLETE";

    #! Indicates that the workflow order data instance has at least one step with an @ref OMQ::StatError status
    /** This status takes the highest priority; if any one step in a workflow has an @ref OMQ::StatError status, then the entire workflow will also have an @ref OMQ::StatError status.  Workflow order data instances must be manually updated to @ref OMQ::StatRetry when an @ref OMQ::StatError status is reached.

        @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatError
      */
    public const StatError          = "ERROR";

    #! Indicates that subworkflow steps are in progress and the system is waiting on the subworkflows to become @ref OMQ::StatComplete
    /** @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatWaiting
      */
    public const StatWaiting        = "WAITING";

    #! Indicates that the workflow order data instance is currently being processed
    /** @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatInProgress
      */
    public const StatInProgress     = "IN-PROGRESS";

    #! Indicates that processing for the workflow order data instance is not yet complete yet has no errors
    /** This status will be assigned after asynchronous segments have completed and
        dependent segments have not yet been started.

        @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatIncomplete
      */
    public const StatIncomplete     = "INCOMPLETE";

    #! Indicates that asynchronous steps are in process and the system is waiting on data to become available in the queue assigned to the step
    /** @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatAsyncWaiting
      */
    public const StatAsyncWaiting   = "ASYNC-WAITING";

    #! Indicates that one or more workflow event synchronization steps are in progress and the workflow is waiting for the event(s) to be posted
    /** @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatEventWaiting
      */
    public const StatEventWaiting   = "EVENT-WAITING";

    #! Indicates that workflow processing on the order data instance has generated an error and is now waiting for an automatic retry
    /** @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatRetry
      */
    public const StatRetry          = "RETRY";

    #! Indicates that workflow order data instance processing has been canceled
    /** This status is similar to @ref OMQ::StatBlocked but is considered a final status.
        @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatCanceled
      */
    public const StatCanceled       = "CANCELED";

    #! Indicates that a workflow order data instance has been created and is waiting for processing to start
    /** @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatReady
      */
    public const StatReady          = "READY";

    #! Indicates that a workflow order data instance has been created and has not yet been processed because at the time the order was created, the \c scheduled date (the earliest possible processing date) was in the future.
    /** @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatScheduled
      */
    public const StatScheduled      = "SCHEDULED";

    #! Indicates that workflow order data instance processing has been temporarily blocked
    /** This status is similar to @ref OMQ::StatCanceled but is considered only temporary.
        @note The equivalent status code actually stored in the database is @ref OMQ::SQLStatBlocked
      */
    public const StatBlocked        = "BLOCKED";
    #/@}

    # WARNING: keep the following constants synchronized with QORUS_API pl/sql (TYPES pkg) specification!

    /** @defgroup SQLStatusCodes Workflow, Segment, and Step SQL Status Codes
        These are the possible values for a workflow order data instance; most of these can also be
        used for the status of a segment instance and a step instance

        @see
        - @ref StatusDescriptions for the corresponding description for each status code
        - @ref OMQ::StatMap for a hash that can be used to map from descriptive status codes to @ref SQLStatusCodes
        - @ref OMQ::SQLStatMap for a hash that can be used to map from SQL status codes to @ref StatusDescriptions
    */
    #/@{
    #! SQL Status: COMPLETE
    /** The equivalent descriptive status is @ref OMQ::StatComplete */
    public const SQLStatComplete       = "C";
    #! SQL Status: ERROR
    /** The equivalent descriptive status is @ref OMQ::StatError */
    public const SQLStatError          = "E";
    #! SQL Status: WAITING
    /** The equivalent descriptive status is @ref OMQ::StatWaiting */
    public const SQLStatWaiting        = "W";
    #! SQL Status: IN-PROGRESS
    /** The equivalent descriptive status is @ref OMQ::StatInProgress */
    public const SQLStatInProgress     = "I";
    #! SQL Status: INCOMPLETE
    /** The equivalent descriptive status is @ref OMQ::StatIncomplete */
    public const SQLStatIncomplete     = "N";
    #! SQL Status: ASYNC-WAITING
    /** The equivalent descriptive status is @ref OMQ::StatAsyncWaiting */
    public const SQLStatAsyncWaiting   = "A";
    #! SQL Status: EVENT-WAITING
    /** The equivalent descriptive status is @ref OMQ::StatEventWaiting */
    public const SQLStatEventWaiting   = "V";
    #! SQL Status: RETRY
    /** The equivalent descriptive status is @ref OMQ::StatRetry */
    public const SQLStatRetry          = "R";
    #! SQL Status: CANCELED
    /** The equivalent descriptive status is @ref OMQ::StatCanceled */
    public const SQLStatCanceled       = "X";
    #! SQL Status: READY
    /** The equivalent descriptive status is @ref OMQ::StatReady */
    public const SQLStatReady          = "Y";
    #! SQL Status: SCHEDULED
    /** The equivalent descriptive status is @ref OMQ::StatScheduled */
    public const SQLStatScheduled      = "S";
    #! SQL Status: BLOCKED
    /** The equivalent descriptive status is @ref OMQ::StatBlocked */
    public const SQLStatBlocked        = "B";
    #/@}

    #! map from text descriptions to SQL status characters
    public const StatMap = (
        "COMPLETE"      : "C",
        "ERROR"         : "E",
        "WAITING"       : "W",
        "IN-PROGRESS"   : "I",
        "INCOMPLETE"    : "N",
        "ASYNC-WAITING" : "A",
        "EVENT-WAITING" : "V",
        "RETRY"         : "R",
        "CANCELED"      : "X",
        "READY"         : "Y",
        "SCHEDULED"     : "S",
        "BLOCKED"       : "B"
    );

    #! hash mapping SQL status characters to text descriptions
    public const SQLStatMap = (
        "C": "COMPLETE",
        "E": "ERROR",
        "W": "WAITING",
        "I": "IN-PROGRESS",
        "N": "INCOMPLETE",
        "A": "ASYNC-WAITING",
        "V": "EVENT-WAITING",
        "R": "RETRY",
        "X": "CANCELED",
        "Y": "READY",
        "S": "SCHEDULED",
        "B": "BLOCKED"
    );

    /** @defgroup ErrorSeverityCodes Error Severity Codes
        These are the possible values for workflow error severity codes
    */
    #/@{
    #! Error Severity: FATAL
    public const ES_Fatal   = "FATAL";
    #! Error Severity: MAJOR
    public const ES_Major   = "MAJOR";
    #! Error Severity: MINOR, identical in function to WARNING and INFO
    public const ES_Minor   = "MINOR";
    #! Error Severity: WARNING, identical in function to MINOR and INFO
    public const ES_Warning = "WARNING";
    #! Error Severity: INFO, identical in function to WARNING and MINOR
    public const ES_Info    = "INFO";
    #! Error Severity: NONE
    public const ES_None    = "NONE";
    #/@}

    #! map giving the relative importance of each error code
    public const ErrorSeverityOrder = (
        ES_None    : -1,
        ES_Info    : 0,
        ES_Warning : 1,
        ES_Minor   : 2,
        ES_Major   : 3,
        ES_Fatal   : 4,
    );

    #! map from error importance rankings to codes
    public const ErrorSeverityMap = (
        "-1" : ES_None,
        "0"  : ES_Info,
        "1"  : ES_Warning,
        "2"  : ES_Minor,
        "3"  : ES_Major,
        "4"  : ES_Fatal,
    );

    #! @defgroup errleveltypes Error Level Type Constants
    /** Error level definition constants for error definitionas processed by @ref oload "oload"
    */
    #/@{
    #! auto level: global if no global error exists, workflow if a global exists and differs from the current definition
    /** this is the default if no explicit error level is given in the error definition
    */
    public const ErrLevelAuto = "AUTO";

    #! global level: the error will be created at the global level
    /** if a global level error of the same name already exists and differs from the given definition,
        the error will only be updated if not manually updated in the database
    */
    public const ErrLevelGlobal = "GLOBAL";

    #! workflow level: the error will always be created at the workflow level
    /** if a workflow level error of the same name already exists and differs from the given definition,
        the error will only be updated if not manually updated in the database
    */
    public const ErrLevelWorkflow = "WORKFLOW";

    #! @ref oload "oload" error definition level type hash
    public const ErrLevelTypes = {
        ErrLevelAuto: True,
        ErrLevelGlobal: True,
        ErrLevelWorkflow: True,
    };
    #/@}

    /** @defgroup WorkflowCompleteDisposition Workflow Order Complete Disposition Constants
        These constants provide codes that indicate how a workflow order went to \c COMPLETE
    */
    #/@{
    #! order went to \c COMPLETE without any errors
    public const CS_Clean = "C";
    #! order went to \c COMPLETE after being recovered automatically
    public const CS_RecoveredAuto = "A";
    #! order went to \c COMPLETE after being recovered with manual retries
    public const CS_RecoveredManual = "M";
    #/@}

    /** @defgroup WorkflowModes Workflow Execution Instance Modes
        These are the possible values for a workflow execution instance's mode attribute
    */
    #/@{
    #! Workflow Mode: NORMAL
    public const WM_Normal = "NORMAL";
    #! Workflow Mode: RECOVERY
    public const WM_Recovery = "RECOVERY";
    #! Workflow Mode: SYNCHRONOUS
    /** @deprecated this mode is no longer used
    */
    public const WM_Synchronous = "SYNCHRONOUS";
    #/@}

    /** @defgroup LogLevels Log Levels
        These are the possible values for log levels when calling system logging functions
    */
    #/@{                     -> (equivalent qorus 4.0 logger level)
    #! Log Level: CRITICAL  -> Logger::LoggerLevel::FATAL
    public const LL_CRITICAL   = -1;
    #! Log Level: IMPORTANT -> Logger::LoggerLevel::INFO
    public const LL_IMPORTANT  = 0;
    #! Log Level: INFO      -> Logger::LoggerLevel::INFO
    public const LL_INFO       = 1;
    #! Log Level: DETAIL_1  -> Logger::LoggerLevel::INFO
    public const LL_DETAIL_1   = 2;
    #! Log Level: DETAIL_2  -> Logger::LoggerLevel::INFO
    public const LL_DETAIL_2   = 3;
    #! Log Level: DEBUG_1   -> Logger::LoggerLevel::DEBUG
    public const LL_DEBUG_1    = 4;
    #! Log Level: DEBUG_2   -> Logger::LoggerLevel::DEBUG
    public const LL_DEBUG_2    = 5;
    #! Log Level: DEBUG_3   -> Logger::LoggerLevel::DEBUG
    public const LL_DEBUG_3    = 6;
    #/@}

    #! map giving the relative ranking of status codes (text code -> numeric ranking)
    public const StatusOrder = (
        StatComplete     : 1,
        StatIncomplete   : 2,
        StatWaiting      : 3,
        StatEventWaiting : 4,
        StatAsyncWaiting : 5,
        StatRetry        : 6,
        StatError        : 7,
        StatCanceled     : 8,
    );

    #! map giving the relative ranking of status codes (text code -> numeric ranking), including IN-PROGRESS
    public const SpecialStatusOrder = (
        StatComplete     : 1,
        StatIncomplete   : 2,
        StatWaiting      : 3,
        StatEventWaiting : 4,
        StatAsyncWaiting : 5,
        StatRetry        : 6,
        StatError        : 7,
        StatCanceled     : 8,
        StatInProgress   : 9,
    );

    #! map giving the relative ranking of status codes (text code -> numeric ranking), for calculating array step status
    public const ArrayStatusOrder = (
        StatComplete     : 1,
        StatError        : 2,
        StatWaiting      : 3,
        StatEventWaiting : 4,
        StatAsyncWaiting : 5,
        StatRetry        : 6,
        StatInProgress   : 7,
    );

    /** @defgroup QueueStatusDescriptions Queue Data Status Descriptions
        These are the possible descriptions for an asynchronous queue data's status code.
        Note that descriptive status values are returned by almost all API functions even though
        @ref SQLQueueStatusCodes "abbreviated codes" are actually stored in the database; this is
        mainly for backwards compatibility.
        @see @ref SQLQueueStatusCodes for the corresponding value for each status description
        @see OMQ::QSMap for a hash that can be used to map from descriptive status codes to @ref SQLQueueStatusCodes
        @see OMQ::SQLQSMap for a hash that can be used to map from SQL status codes to @ref QueueStatusDescriptions
        @see OMQ::QS_ALL for a list of all valid queue statuses
    */
    #/@{
    #! Queue Status Text Description: \c WAITING
    /** The equivalent status code actually stored in the database is @ref OMQ::SQL_QS_Waiting */
    public const QS_Waiting  = "WAITING";
    #! Queue Status Text Description: \c RECEIVED
    /** The equivalent status code actually stored in the database is @ref OMQ::SQL_QS_Received */
    public const QS_Received = "RECEIVED";
    #! Queue Status Text Description: \c ERROR
    /** The equivalent status code actually stored in the database is @ref OMQ::SQL_QS_Error */
    public const QS_Error    = "ERROR";
    #! Queue Status Text Description: \c USED
    /** The equivalent status code actually stored in the database is @ref OMQ::SQL_QS_Used
        @note this status is only used in Oracle databases where the queue rows are not deleted
        in order to preserve the integrity of the indexes on the \c QUEUE_DATA table */
    public const QS_Used     = "USED";
    #/@}

    #! list of all queue status descriptions
    public const QS_ALL      = ( QS_Waiting, QS_Received, QS_Error, QS_Used );

    # WARNING: keep these constants synchronized with QORUS_SYSTEM_QUEUE pl/sql (TYPES pkg) specification!

    /** @defgroup SQLQueueStatusCodes Queue Data Status Codes
        These are the possible values for an asynchronous queue data's status; this is the actual value that is stored in the DB
        @see @ref QueueStatusDescriptions for the corresponding description for each status code
        @see OMQ::QSMap for a hash that can be used to map from descriptive status codes to @ref SQLQueueStatusCodes
        @see OMQ::SQLQSMap for a hash that can be used to map from SQL status codes to @ref QueueStatusDescriptions
    */
    #/@{
    #! Queue Status SQL Character Code: \c WAITING
    /** The equivalent descriptive status is @ref OMQ::QS_Waiting */
    public const SQL_QS_Waiting  = "W";
    #! Queue Status SQL Character Code: \c RECEIVED
    /** The equivalent descriptive status is @ref OMQ::QS_Received */
    public const SQL_QS_Received = "R";
    #! Queue Status SQL Character Code: \c ERROR
    /** The equivalent descriptive status is @ref OMQ::QS_Error */
    public const SQL_QS_Error    = "E";
    #! Queue Status SQL Character Code: \c USED
    /** The equivalent descriptive status is @ref OMQ::QS_Used
        @note this status is only used in Oracle databases where the queue rows are not deleted
        in order to preserve the integrity of the indexes on the \c QUEUE_DATA table */
    public const SQL_QS_Used     = "X";
    #/@}

    #! list of all queue status character codes
    public const SQL_QS_ALL      = ( SQL_QS_Waiting, SQL_QS_Received, SQL_QS_Error, SQL_QS_Used );

    #! map of queue status descriptions to the character code
    public const QSMap = (
        "WAITING"  : "W",
        "RECEIVED" : "R",
        "ERROR"    : "E",
        "USED"     : "X",
    );

    #! map of queue status character codes to the description
    public const SQLQSMap = (
        "W" : "WAITING",
        "R" : "RECEIVED",
        "E" : "ERROR",
        "X" : "USED",
    );

    #! Qorus server option alias hash
    public const omq_option_aliases = {
        "xml-rpc-server"     : "http-server",
        "recover-delay"      : "recover_delay",
        "async-delay"        : "async_delay",
    };

    #! Qorus client option alias hash
    public const client_option_aliases = {
        "xml-rpc-client-url" : "client-url",
    };

    public string sub get_option_name(string domain, string name) {
        if (domain == "qorus" && exists omq_option_aliases{name}) {
            return omq_option_aliases{name};
        }
        if (domain == "qorus-client" && exists client_option_aliases{name}) {
            return client_option_aliases{name};
        }
        return name;
    }

    # error codes for XML-RPC errors

    /** @defgroup ErrorCodes Error Codes
        These are the error codes that are currently defined for various errors; very few errors have an error code at the moment.
    */
    #/@{
    #! RBAC Authorization Error Code
    public const AUTH_OVERRIDE_ERROR                  = 1001;
    #! RBAC Authorization Error Code
    public const AUTH_INVALID_USER_OR_PASSWORD        = 1002;
    #! RBAC Authorization Error Code
    public const AUTH_UNAUTHORIZED                    = 1003;
    #! RBAC Authorization Error Code
    public const AUTH_REQUIRES_AUTHORIZATION          = 1004;
    #! RBAC Authorization Error Code
    public const AUTH_INVALID_USERNAME                = 1005;
    #! RBAC Authorization Error Code
    public const AUTH_USER_ALREADY_EXISTS             = 1006;
    #! RBAC Authorization Error Code
    public const AUTH_INVALID_PERMISSION              = 1007;
    #! RBAC Authorization Error Code
    public const AUTH_INVALID_USER                    = 1008;
    #! RBAC Authorization Error Code
    public const AUTH_MISSING_USERNAME                = 1009;
    #! RBAC Authorization Error Code
    public const AUTH_MISSING_DESCRIPTION             = 1010;
    #! RBAC Authorization Error Code
    public const AUTH_MISSING_PERMISSION              = 1011;
    #! RBAC Authorization Error Code
    public const AUTH_MISSING_ROLE                    = 1012;
    #! RBAC Authorization Error Code
    public const AUTH_INVALID_ROLE                    = 1013;
    #! RBAC Authorization Error Code
    public const AUTH_ROLE_ALREADY_EXISTS             = 1014;
    #! RBAC Authorization Error Code
    public const AUTH_PERMISSION_ALREADY_EXISTS       = 1015;
    #! RBAC Authorization Error Code
    public const AUTH_CANNOT_UPDATE_SYSTEM_PERMISSION = 1016;
    #! RBAC Authorization Error Code
    public const AUTH_CANNOT_DELETE_PERMISSION_IN_USE = 1017;
    #! RBAC Authorization Error Code
    public const AUTH_INVALID_GROUP                   = 1018;
    #! RBAC Authorization Invalid Workflow Error Code
    public const AUTH_INVALID_WORKFLOW                = 1019;
    #! RBAC Authorization Invalid Service Error Code
    public const AUTH_INVALID_SERVICE                 = 1020;
    #! RBAC Authorization Invalid Workflow Error Code
    public const AUTH_INVALID_JOB                     = 1021;
    #! RBAC Authorization Error Code
    public const AUTH_NO_SUCH_ROLE                    = 1022;

    #! error code for invalid XML revied by the XML-RPC handler
    public const XMLRPC_INVALID_XML                   = 2001;
    #/@}

    # event constants

    #! valid event filter criteria code hash
    public const QEM_FILTER_CRITERIA_HASH = (
        "class": True,
        "classhash": True,
        "classstr": True,
        "classstrhash": True,
        "event": True,
        "eventhash": True,
        "eventstr": True,
        "eventstrhash": True,
        "minseverity": True,
        "minuserseverity": True,
        "minseveritystr": True,
        "minuserseveritystr": True,
        "all": True,
        "none": True,
        "mincompositeseverity": True,
        "mincompositeseveritystr": True,
    );

    #! valid event filter criteria code list
    public const QEM_FILTER_CRITERIA = QEM_FILTER_CRITERIA_HASH.keys();

    /** @defgroup EventClasses Qorus Event Classes
        These are the possible event class codes for application event processing.
        @see @ref OMQ::QE_MAP_CLASS for a hash that can be used to map event class codes to event class descriptions
        @see @ref OMQ::QE_RMAP_CLASS for a hash that can be used to map event class descriptions to event class codes
    */
    #/@{
    #! Event Class Code for SYSTEM Events
    public const QE_CLASS_SYSTEM                = 101;
    #! Event Class Code for WORKFLOW Events
    public const QE_CLASS_WORKFLOW              = 102;
    #! Event Class Code for SERVICE Events
    public const QE_CLASS_SERVICE               = 103;
    #! Event Class Code for USER Events
    public const QE_CLASS_USER                  = 104;
    #! Event Class Code for JOB Events
    public const QE_CLASS_JOB                   = 105;
    #! Event Class Code for ALERT Events
    public const QE_CLASS_ALERT                 = 106;
    #! Event Class Code for GROUP Events
    public const QE_CLASS_GROUP                 = 107;
    #! Event Class Code for CONNECTION events
    public const QE_CLASS_CONNECTION            = 108;
    #! Event Class Code for PROCESS events
    /** @since Qorus 4.0 */
    public const QE_CLASS_PROCESS               = 109;
    #! Event Class Code for CLUSTER events
    /** @since Qorus 4.0 */
    public const QE_CLASS_CLUSTER               = 110;
    #! Event Class Code for LOGGER events
    /** @since Qorus 4.0 */
    public const QE_CLASS_LOGGER                = 111;
    #! Event Class Code for CONFIG ITEM events
    /** @since Qorus 4.0 */
    public const QE_CLASS_CONFIG_ITEM           = 112;
    #! Event Class Code for CLASS events
    /** @since Qorus 5.1 */
    public const QE_CLASS_CLASS                 = 113;
    #/@}

    #! hash mapping event class codes to descriptive strings
    public const QE_MAP_CLASS = {
        QE_CLASS_SYSTEM      : "SYSTEM",
        QE_CLASS_WORKFLOW    : "WORKFLOW",
        QE_CLASS_SERVICE     : "SERVICE",
        QE_CLASS_USER        : "USER",
        QE_CLASS_JOB         : "JOB",
        QE_CLASS_ALERT       : "ALERT",
        QE_CLASS_GROUP       : "GROUP",
        QE_CLASS_CONNECTION  : "CONNECTION",
        QE_CLASS_PROCESS     : "PROCESS",
        QE_CLASS_CLUSTER     : "CLUSTER",
        QE_CLASS_LOGGER      : "LOGGER",
        QE_CLASS_CONFIG_ITEM : "CONFIG_ITEM",
        QE_CLASS_CLASS       : "CLASS",
    };

    #! hash mapping event class descriptive strings to class codes
    public const QE_RMAP_CLASS = map {$1.value: $1.key.toInt()}, QE_MAP_CLASS.pairIterator();

    /** @defgroup EventCodes Qorus Event Codes
        These are the possible event codes for application event processing.
        @see OMQ::QE_MAP_EVENT for a hash that can be used to map event codes to event descriptions
        @see OMQ::QE_RMAP_EVENT for a hash that can be used to map event descriptions to event codes
    */
    #/@{
    #! Qorus Event Code: SYSTEM_STARTUP
    /** @see
        - @ref SYSTEM_STARTUP for a description of the event info hash
        - @ref OMQ::AE_SYSTEM_STARTUP
    */
    public const QEC_SYSTEM_STARTUP               = 1001;
    #! Qorus Event Code: SYSTEM_SHUTDOWN
    /** This event has no info hash

        @see
        - @ref SYSTEM_SHUTDOWN
        - @ref OMQ::AE_SYSTEM_SHUTDOWN
    */
    public const QEC_SYSTEM_SHUTDOWN              = 1002;
    #! Qorus Event Code: SYSTEM_ERROR
    /** @see @ref SYSTEM_ERROR
    */
    public const QEC_SYSTEM_ERROR                 = 1003;
    #! Qorus Event Code: SYSTEM_HEALTH_CHANGED
    /** @see @ref SYSTEM_HEALTH_CHANGED for a description of the event info hash
    */
    public const QEC_SYSTEM_HEALTH_CHANGED        = 1004;
    #! Qorus Event Code: SYSTEM_REMOTE_HEALTH_CHANGED
    /** @see @ref SYSTEM_REMOTE_HEALTH_CHANGED for a description of the event info hash
    */
    public const QEC_SYSTEM_REMOTE_HEALTH_CHANGED = 1005;

    #! Qorus Event Code: GROUP_STATUS_CHANGED
    /** @see @ref GROUP_STATUS_CHANGED for a description of the event info hash
    */
    public const QEC_GROUP_STATUS_CHANGED         = 1101;

    #! Qorus Event Code: WORKFLOW_START
    /** @see
        - @ref WORKFLOW_START for a description of the event info hash
        - @ref OMQ::AE_WORKFLOW_START
    */
    public const QEC_WORKFLOW_START               = 2001;
    #! Qorus Event Code: WORKFLOW_STOP
    /** @see
        - @ref WORKFLOW_STOP for a description of the event info hash
        - @ref OMQ::AE_WORKFLOW_STOP
    */
    public const QEC_WORKFLOW_STOP                = 2002;
    #! Qorus Event Code: WORKFLOW_CACHE_RESET
    /** @see @ref WORKFLOW_CACHE_RESET for a description of the event info hash
    */
    public const QEC_WORKFLOW_CACHE_RESET         = 2003;
    #! Qorus Event Code: WORKFLOW_DATA_SUBMITTED
    /** @see
        - @ref WORKFLOW_DATA_SUBMITTED for a description of the event info hash
        - @ref OMQ::AE_WORKFLOW_DATA_CREATED
    */
    public const QEC_WORKFLOW_DATA_SUBMITTED      = 2004;
    #! Qorus Event Code: WORKFLOW_DATA_ERROR
    /** @see @ref WORKFLOW_DATA_ERROR for a description of the event info hash
    */
    public const QEC_WORKFLOW_DATA_ERROR          = 2005;
    #! Qorus Event Code: WORKFLOW_DATA_RELEASED (workflow detach event)
    /** @see @ref WORKFLOW_DATA_RELEASED for a description of the event info hash
    */
    public const QEC_WORKFLOW_DATA_RELEASED       = 2006;
    #! Qorus Event Code: WORKFLOW_DATA_CACHED (workflow attach event)
    /** @see @ref WORKFLOW_DATA_CACHED for a description of the event info hash
    */
    public const QEC_WORKFLOW_DATA_CACHED         = 2007;
    #! Qorus Event Code: WORKFLOW_INFO_CHANGED
    /** @see @ref WORKFLOW_INFO_CHANGED for a description of the event info hash
    */
    public const QEC_WORKFLOW_INFO_CHANGED        = 2008;
    #! Qorus Event Code: WORKFLOW_STATUS_CHANGED
    /** @see
        - @ref WORKFLOW_STATUS_CHANGED for a description of the event info hash
        - @ref OMQ::AE_WORKFLOW_STATUS_CHANGE
    */
    public const QEC_WORKFLOW_STATUS_CHANGED      = 2009;
    #! Qorus Event Code:: WORKFLOW_STEP_PERFORMANCE
    /** @see @ref WORKFLOW_STEP_PERFORMANCE for a description of the event info hash

        @since Qorus 3.0.2
    */
    public const QEC_WORKFLOW_STEP_PERFORMANCE    = 2010;
    #! Qorus Event Code:: WORKFLOW_PERFORMANCE
    /** @see @ref WORKFLOW_PERFORMANCE for a description of the event info hash

        @since Qorus 3.0.2
    */
    public const QEC_WORKFLOW_PERFORMANCE         = 2011;
    #! Qorus Event Code: WORKFLOW_DATA_LOCKED
    /** @see @ref WORKFLOW_DATA_LOCKED for a description of the event info hash

        @since Qorus 3.0.2
    */
    public const QEC_WORKFLOW_DATA_LOCKED         = 2012;
    #! Qorus Event Code: WORKFLOW_DATA_UNLOCKED
    /** @see @ref WORKFLOW_DATA_UNLOCKED for a description of the event info hash

        @since Qorus 3.0.2
    */
    public const QEC_WORKFLOW_DATA_UNLOCKED       = 2013;
    #! Qorus Event Code: WORKFLOW_DATA_UPDATED (static or dynamic data changed)
    /** @see @ref WORKFLOW_DATA_UPDATED for a description of the event info hash

        @since Qorus 3.1.0
    */
    public const QEC_WORKFLOW_DATA_UPDATED        = 2014;
    #! Qorus Event Code: WORKFLOW_STATS_UPDATED
    /** @see @ref WORKFLOW_STATS_UPDATED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_WORKFLOW_STATS_UPDATED       = 2015;
    #! Qorus Event Code: WORKFLOW_RECOVERED
    /** @ref WORKFLOW_RECOVERED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_WORKFLOW_RECOVERED           = 2016;
    #! Qorus Event code: WORKFLOW_UPDATED
    /** @ref WORKFLOW_UPDATED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_WORKFLOW_UPDATED             = 2017;
    #! Qorus Event Code: WORKFLOW_STEP_DATA_UPDATED (step dynamic data changed)
    /** @see @ref WORKFLOW_STEP_DATA_UPDATED for a description of the event info hash

        @since Qorus 4.0.1
    */
    public const QEC_WORKFLOW_STEP_DATA_UPDATED   = 2018;

    #! Qorus Event Code: SERVICE_START
    /** @see
        - @ref SERVICE_START for a description of the event info hash
        - @ref OMQ::AE_SERVICE_START
    */
    public const QEC_SERVICE_START                = 3001;
    #! Qorus Event Code: SERVICE_STOP
    /** @see
        - @ref SERVICE_STOP for a description of the event info hash
        - @ref OMQ::AE_SERVICE_STOP
    */
    public const QEC_SERVICE_STOP                 = 3002;
    #! Qorus Event Code: SERVICE_ERROR
    /** @see @ref SERVICE_ERROR for a description of the event info hash
    */
    public const QEC_SERVICE_ERROR                = 3003;
    #! Qorus Event Code: SERVICE_AUTOSTART_CHANGE
    /** @deprecated This event is no longer raised as of Qorus 4.0
    */
    public const QEC_SERVICE_AUTOSTART_CHANGE     = 3004;
    #! Qorus Event Code:: SERVICE_METHOD_PERFORMANCE
    /** @see @ref SERVICE_METHOD_PERFORMANCE for a description of the event info hash

        @since Qorus 3.0.2
    */
    public const QEC_SERVICE_METHOD_PERFORMANCE   = 3005;
    #! Qorus Event code: SERVICE_UPDATED
    /** @ref SERVICE_UPDATED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_SERVICE_UPDATED              = 3006;

    #! Qorus Event Code: JOB_START
    /** @see
        - @ref JOB_START for a description of the event info hash
        - @ref OMQ::AE_JOB_START
    */
    public const QEC_JOB_START                    = 4001;
    #! Qorus Event Code: JOB_STOP
    /**  for a description of the event info hash@see
        - @ref JOB_STOP for a description of the event info hash
        - @ref OMQ::AE_JOB_STOP
    */
    public const QEC_JOB_STOP                     = 4002;
    #! Qorus Event Code: JOB_ERROR
    /** @see @ref JOB_ERROR for a description of the event info hash
    */
    public const QEC_JOB_ERROR                    = 4003;
    #! Qorus Event Code: JOB_INSTANCE_START
    /** @see
        - @ref JOB_INSTANCE_START for a description of the event info hash
        - @ref OMQ::AE_JOB_INSTANCE_START
    */
    public const QEC_JOB_INSTANCE_START           = 4004;
    #! Qorus Event Code: JOB_INSTANCE_STOP
    /** @see
        - @ref JOB_INSTANCE_STOP for a description of the event info hash
        - @ref OMQ::AE_JOB_INSTANCE_STOP
    */
    public const QEC_JOB_INSTANCE_STOP            = 4005;
    #! Qorus Event Code: JOB_RECOVERED
    /** @ref JOB_RECOVERED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_JOB_RECOVERED                = 4006;
    #! Qorus Event code: JOB_UPDATED
    /** @ref JOB_UPDATED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_JOB_UPDATED                  = 4007;
    #! Qorus Event code: JOB_CREATED
    /** @ref JOB_CREATED for a description of the event info hash

        @since Qorus 5.1
    */
    public const QEC_JOB_CREATED                  = 4008;
    #! Qorus Event code: JOB_DELETED
    /** @ref JOB_DELETED for a description of the event info hash

        @since Qorus 5.1
    */
    public const QEC_JOB_DELETED                  = 4009;

    #! Qorus Event code: QEC_CONFIG_ITEM_CHANGED
    /** @ref CONFIG_ITEM_CHANGED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_CONFIG_ITEM_CHANGED          = 4100;

    #! Qorus Event Code: ALERT_ONGOING_RAISED
    /** @see @ref ALERT_ONGOING_RAISED for a description of the event info hash
    */
    public const QEC_ALERT_ONGOING_RAISED         = 5006;
    #! Qorus Event Code: ALERT_ONGOING_CLEARED
    /** @see @ref ALERT_ONGOING_CLEARED for a description of the event info hash
    */
    public const QEC_ALERT_ONGOING_CLEARED        = 5007;
    #! Qorus Event Code: ALERT_TRANSIENT_RAISED
    /** @see @ref ALERT_TRANSIENT_RAISED for a description of the event info hash
    */
    public const QEC_ALERT_TRANSIENT_RAISED       = 5008;

    #! Qorus Event Code: CONNECTION_UP
    /** @see @ref CONNECTION_UP for a description of the event info hash
    */
    public const QEC_CONNECTION_UP                = 5101;
    #! Qorus Event Code: CONNECTION_DOWN
    /** @see @ref CONNECTION_DOWN for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_CONNECTION_DOWN              = 5102;

    #! Qorus Event Code: CONNECTION_ENABLED_CHANGE
    /** Sent when any connection enabled flag is changed

        @see @ref CONNECTION_ENABLED_CHANGE for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_CONNECTION_ENABLED_CHANGE    = 5103;

    #! Qorus Event Code: CONNECTION_CREATED
    /** Sent when a connection is created by a user using the REST API

        @see @ref CONNECTION_CREATED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_CONNECTION_CREATED           = 5104;

    #! Qorus Event Code: CONNECTION_UPDATED
    /** Sent when is a connection updated by a user using the REST API

        @see @ref CONNECTION_UPDATED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_CONNECTION_UPDATED           = 5105;

    #! Qorus Event Code: CONNECTION_DELETED
    /** Sent when is a connection deleted by a user using the REST API

        @see @ref CONNECTION_DELETED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_CONNECTION_DELETED           = 5106;

    #! Qorus Event Code: CONNECTIONS_RELOADED
    /** Sent when connections are reloaded by a user using the REST API

        @see @ref CONNECTIONS_RELOADED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_CONNECTIONS_RELOADED         = 5107;

    #! Qorus Event Code: CONNECTION_DEBUG_DATA_CHANGE
    /** Sent when the debug data flag flag is changed for any connection

        @see @ref QEC_CONNECTION_DEBUG_DATA_CHANGE for a description of the event info hash

        @since Qorus 4.1
    */
    public const QEC_CONNECTION_DEBUG_DATA_CHANGE    = 5108;

    #! Qorus Event Code: LOGGER_CREATED
    /** Sent when a logger is created by a user using the REST API

        @see @ref LOGGER_CREATED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_LOGGER_CREATED         = 5200;

    #! Qorus Event Code: LOGGER_UPDATED
    /** Sent when a logger is updated by a user using the REST API

        @see @ref LOGGER_UPDATED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_LOGGER_UPDATED         = 5201;

    #! Qorus Event Code: LOGGER_DELETED
    /** Sent when a logger is deleted by a user using the REST API

        @see @ref LOGGER_DELETED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_LOGGER_DELETED         = 5202;

    #! Qorus Event Code: APPENDER_CREATED
    /** Sent when an appender is created by a user using the REST API

        @see @ref APPENDER_CREATED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_APPENDER_CREATED       = 5203;

    #! Qorus Event Code: APPENDER_DELETED
    /** Sent when an appender is deleted by a user using the REST API

        @see @ref APPENDER_DELETED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_APPENDER_DELETED       = 5204;

    #! Qorus Event Code: APPENDER_UPDATED
    /** Sent when an appender is updated by a user using the REST API

        @see @ref APPENDER_UPDATED for a description of the event info hash

        @since Qorus 4.0.3
    */
    public const QEC_APPENDER_UPDATED       = 5205;

    #! Qorus Event Code: PROCESS_STARTED
    /** @see @ref PROCESS_STARTED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_PROCESS_STARTED              = 6001;
    #! Qorus Event Code: PROCESS_STOPPED
    /** @see @ref PROCESS_STOPPED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_PROCESS_STOPPED              = 6002;
    #! Qorus Event Code: PROCESS_START_ERROR
    /** @see @ref PROCESS_START_ERROR for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_PROCESS_START_ERROR          = 6003;
    #! Qorus Event Code: PROCESS_MEMORY_CHANGED
    /** @see @ref PROCESS_MEMORY_CHANGED for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_PROCESS_MEMORY_CHANGED       = 6004;

    #! Qorus Event Code: NODE_INFO
    /** @see @ref NODE_INFO for a description of the event info hash

        @since Qorus 4.0
    */
    public const QEC_NODE_INFO                    = 7001;

    #! Qorus Event Code: NODE_REMOVED
    /** @see @ref NODE_REMOVED for a description of the event info hash

        @since Qorus 5.0
    */
    public const QEC_NODE_REMOVED                 = 7002;

    #! Qorus Event code: CLASS_CREATED
    /** @ref CLASS_CREATED for a description of the event info hash

        @since Qorus 5.1
    */
    public const QEC_CLASS_CREATED                = 8001;
    #! Qorus Event code: CLASS_DELETED
    /** @ref CLASS_DELETED for a description of the event info hash

        @since Qorus 5.1
    */
    public const QEC_CLASS_DELETED                = 8002;
    #! Qorus Event code: CLASS_UPDATED
    /** @ref CLASS_UPDATED for a description of the event info hash

        @since Qorus 5.1
    */
    public const QEC_CLASS_UPDATED                = 8003;

    #! Qorus Event Code: USER_EVENT
    /** this is the generic event code used for all user events

        @see @ref USER_EVENT for a description of the event info hash
    */
    public const QEC_USER_EVENT                   = 9001;
    #/@}

    #! hash mapping event codes to descriptive strings
    public const QE_MAP_EVENT = {
        QEC_SYSTEM_STARTUP                  : "SYSTEM_STARTUP",
        QEC_SYSTEM_SHUTDOWN                 : "SYSTEM_SHUTDOWN",
        QEC_SYSTEM_ERROR                    : "SYSTEM_ERROR",
        QEC_SYSTEM_HEALTH_CHANGED           : "SYSTEM_HEALTH_CHANGED",
        QEC_SYSTEM_REMOTE_HEALTH_CHANGED    : "SYSTEM_REMOTE_HEALTH_CHANGED",

        QEC_GROUP_STATUS_CHANGED            : "GROUP_STATUS_CHANGED",

        QEC_WORKFLOW_START                  : "WORKFLOW_START",
        QEC_WORKFLOW_STOP                   : "WORKFLOW_STOP",
        QEC_WORKFLOW_CACHE_RESET            : "WORKFLOW_CACHE_RESET",
        QEC_WORKFLOW_DATA_SUBMITTED         : "WORKFLOW_DATA_SUBMITTED",
        QEC_WORKFLOW_DATA_ERROR             : "WORKFLOW_DATA_ERROR",
        QEC_WORKFLOW_DATA_RELEASED          : "WORKFLOW_DATA_RELEASED",
        QEC_WORKFLOW_DATA_CACHED            : "WORKFLOW_DATA_CACHED",
        QEC_WORKFLOW_INFO_CHANGED           : "WORKFLOW_INFO_CHANGED",
        QEC_WORKFLOW_STATUS_CHANGED         : "WORKFLOW_STATUS_CHANGED",
        QEC_WORKFLOW_PERFORMANCE            : "WORKFLOW_PERFORMANCE",
        QEC_WORKFLOW_STEP_PERFORMANCE       : "WORKFLOW_STEP_PERFORMANCE",
        QEC_WORKFLOW_DATA_LOCKED            : "WORKFLOW_DATA_LOCKED",
        QEC_WORKFLOW_DATA_UNLOCKED          : "WORKFLOW_DATA_UNLOCKED",
        QEC_WORKFLOW_DATA_UPDATED           : "WORKFLOW_DATA_UPDATED",
        QEC_WORKFLOW_STATS_UPDATED          : "WORKFLOW_STATS_UPDATED",
        QEC_WORKFLOW_RECOVERED              : "WORKFLOW_RECOVERED",
        QEC_WORKFLOW_UPDATED                : "WORKFLOW_UPDATED",
        QEC_WORKFLOW_STEP_DATA_UPDATED      : "WORKFLOW_STEP_DATA_UPDATED",

        QEC_SERVICE_START                   : "SERVICE_START",
        QEC_SERVICE_STOP                    : "SERVICE_STOP",
        QEC_SERVICE_ERROR                   : "SERVICE_ERROR",
        QEC_SERVICE_AUTOSTART_CHANGE        : "SERVICE_AUTOSTART_CHANGE",
        QEC_SERVICE_METHOD_PERFORMANCE      : "SERVICE_METHOD_PERFORMANCE",
        QEC_SERVICE_UPDATED                 : "SERVICE_UPDATED",

        QEC_JOB_START                       : "JOB_START",
        QEC_JOB_STOP                        : "JOB_STOP",
        QEC_JOB_ERROR                       : "JOB_ERROR",
        QEC_JOB_INSTANCE_START              : "JOB_INSTANCE_START",
        QEC_JOB_INSTANCE_STOP               : "JOB_INSTANCE_STOP",
        QEC_JOB_RECOVERED                   : "JOB_RECOVERED",
        QEC_JOB_UPDATED                     : "JOB_UPDATED",
        QEC_JOB_CREATED                     : "JOB_CREATED",
        QEC_JOB_DELETED                     : "JOB_DELETED",

        QEC_CONFIG_ITEM_CHANGED             : "CONFIG_ITEM_CHANGED",

        QEC_ALERT_ONGOING_RAISED            : "ALERT_ONGOING_RAISED",
        QEC_ALERT_ONGOING_CLEARED           : "ALERT_ONGOING_CLEARED",
        QEC_ALERT_TRANSIENT_RAISED          : "ALERT_TRANSIENT_RAISED",

        QEC_CONNECTION_UP                   : "CONNECTION_UP",
        QEC_CONNECTION_DOWN                 : "CONNECTION_DOWN",
        QEC_CONNECTION_ENABLED_CHANGE       : "CONNECTION_ENABLED_CHANGE",
        QEC_CONNECTION_CREATED              : "CONNECTION_CREATED",
        QEC_CONNECTION_UPDATED              : "CONNECTION_UPDATED",
        QEC_CONNECTION_DELETED              : "CONNECTION_DELETED",
        QEC_CONNECTIONS_RELOADED            : "CONNECTIONS_RELOADED",
        QEC_CONNECTION_DEBUG_DATA_CHANGE    : "CONNECTION_DEBUG_DATA_CHANGE",

        QEC_LOGGER_CREATED                  : "LOGGER_CREATED",
        QEC_LOGGER_UPDATED                  : "LOGGER_UPDATED",
        QEC_LOGGER_DELETED                  : "LOGGER_DELETED",
        QEC_APPENDER_CREATED                : "APPENDER_CREATED",
        QEC_APPENDER_DELETED                : "APPENDER_DELETED",
        QEC_APPENDER_UPDATED                : "APPENDER_UPDATED",

        QEC_PROCESS_STARTED                 : "PROCESS_STARTED",
        QEC_PROCESS_STOPPED                 : "PROCESS_STOPPED",
        QEC_PROCESS_START_ERROR             : "PROCESS_START_ERROR",
        QEC_PROCESS_MEMORY_CHANGED          : "PROCESS_MEMORY_CHANGED",

        QEC_NODE_INFO                       : "NODE_INFO",
        QEC_NODE_REMOVED                    : "NODE_REMOVED",

        QEC_USER_EVENT                      : "USER_EVENT",
    };

    #! hash mapping event descriptive strings to codes
    public const QE_RMAP_EVENT = map {$1.value: $1.key.toInt()}, QE_MAP_EVENT.pairIterator();

    # all option related structures should be listed here and mentioned in
    # options_relations hash for properly working clients

    # list of valid omq options and associated functions
    # PV - 2009Jun26 - added "interval": allowed values for Int. -1 means "unlimited".

    #! master Qorus system option hash for all valid system options @showinitializer
    public const QorusSystemOptionHash = {
        "daemon-mode": (
            "arg"  : Type::Boolean,
            "desc" : "if true then Qorus will launch in the background",
            "startup-only" : True,
        ),

        "max-log-files": (
            "arg"  : Type::Int,
            "desc" : "sets the maximum number of old log files to keep when rotating log files when creating new appenders",
            "interval" : (1, "UNLIMITED"),
            "startup-only" : True,
        ),

        "system-pool-minimum": (
            "arg"  : Type::Int,
            "desc" : "sets the minimum number of datasources in the system omq pool",
            "interval" : (1, "UNLIMITED"),
            "startup-only" : True,
        ),

        "system-pool-maximum": (
            "arg"  : Type::Int,
            "desc" : "sets the maximum number of datasources in the system omq pool",
            "interval" : (1, "UNLIMITED"),
            "startup-only" : True,
        ),

        "loglevel": (
            "arg": Type::String,
            "desc": "uses to affect the system log levels",
            "interval": (1, "UNLIMITED"),
            "workflow": True,
            "service": True,
            "job": True,
        ),

        "max-retries": (
            "arg"  : Type::Int,
            "desc" : "sets maximum number of retries before a step receives status 'ERROR'",
            "interval" : (1, "UNLIMITED"),
            "workflow" : True,
        ),

        "max-async-retries": (
            "arg"  : Type::Int,
            "desc" : "sets maximum number of retries before a step with ASYNC-WAITING receives status 'ERROR'",
            "interval" : (1, "UNLIMITED"),
            "workflow" : True,
        ),

        "recover_delay": (
            "arg"  : Type::Int,
            "desc" : "sets delay between automatic recovery attempts of RETRY steps/segments in seconds",
            "interval" : (0, "UNLIMITED"),
            "workflow" : True,
        ),

        "async_delay": (
            "arg"  : Type::Int,
            "desc" : "sets delay between automatic recovery attempts of async-waiting steps in seconds",
            "interval" : (0, "UNLIMITED"),
            "workflow" : True,
        ),

        "detach-delay": (
            "arg"  : Type::Int,
            "desc" : "sets workflow instance data cache expiration delay in seconds",
            "interval" : (0, "UNLIMITED"),
        ),

        "cache-max": (
            "arg"  : Type::Int,
            "desc" : "maximum number of workflow instance cache entries",
            "interval" : (0, "UNLIMITED"),
        ),

        "logdir": (
            "arg"  : Type::String,
            "desc" : "sets log file directory",
            "path" : True,
            "startup-only" : True,
        ),

        "http-server": (
            "arg"          : Type::String,
            "list"         : True,
            "desc"         : "network address on host for HTTP server (giving just a port number will bind to all "
                "interfaces)",
            "startup-only" : True,
        ),

        "http-secure-server": (
            "arg"          : Type::String,
            "list"         : True,
            "desc"         : "network address on host for secure HTTP server (giving just a port number will bind to "
                "all interfaces)",
            "startup-only" : True,
        ),

        "http-secure-certificate": (
            "arg"          : Type::String,
            "desc"         : "file name of PEM certificate file for the secure (SSL-based) HTTP server",
            "path"         : True,
            "startup-only" : True,
        ),

        "http-secure-private-key": (
            "arg"          : Type::String,
            "desc"         : "file name of PEM private key file for the secure (SSL-based) HTTP server, if the "
                "certificate does not include the private key",
            "path"         : True,
            "startup-only" : True,
        ),

        "http-secure-private-key-password": (
            "arg"          : Type::String,
            "desc"         : "the password to the PEM private key for the secure (SSL-based) HTTP server",
            "path"         : True,
            "startup-only" : True,
            "first-in"     : "3.0.4.p2",
        ),

        "instance-key": (
            "arg"          : Type::String,
            "desc"         : "key for this instance of Qorus",
            "startup-only" : True,
        ),

        "option-file": (
            "arg"          : Type::String,
            "desc"         : "Path to the Qorus system option file (this option is only usable from the command-line)",
            "path"         : True,
            "first-in"     : "1.8.0",
            "startup-only" : True,
        ),

        "dbparams-file": (
            "arg"          : Type::String,
            "desc"         : "Deprecated since Qorus 4.0",
            "path"         : True,
            "first-in"     : "1.8.0",
            "startup-only" : True,
            "deprecated-since": "4.0",
        ),

        "logfile-template": (
            "arg"          : Type::String,
            "desc"         : "gives the default logfile template for new system log appenders",
            "first-in"     : "1.8.0",
        ),

        "wf-logfile-template": (
            "arg"          : Type::String,
            "desc"         : "gives the default logfile template for new workflow log appenders",
            "first-in"     : "1.8.0",
        ),

        "svc-logfile-template": (
            "arg"          : Type::String,
            "desc"         : "gives the default logfile template for new service log appenders",
            "first-in"     : "1.8.0",
        ),

        "job-logfile-template": (
            "arg"          : Type::String,
            "desc"         : "gives the default logfile template for new job log appenders",
            "first-in"     : "2.6.1",
        ),

        "force-gui-encoding": (
            "arg"          : Type::String,
            "desc"         : "set to force XML-RPC responses to the Qorus GUI to have a specific character encoding",
            "first-in"     : "2.0.0",
            "startup-only" : True,
        ),

        "max-events": (
            "arg"          : Type::Int,
            "desc"         : "maximum number of events to hold in the internal event cache",
            "first-in"     : "2.0.2",
            "startup-only" : True,
        ),

        "db-max-threads": (
            "arg"          : Type::Int,
            "desc"         : "maximum allowed DB threads for parallelized tasks (ex: session recovery); typically "
                "the system schema DB server's CPU count + 2; must be less than system-pool-maximum",
            "first-in"     : "2.0.3",
            "startup-only" : True,
        ),

        "audit": (
            "arg"         : Type::String,
            "list"        : True,
            "desc"        : "list of objects to audit, elements may be: '*' (enable everything), 'system' (system "
                "events), 'workflows' (workflow start & stop events), 'workflow-data' (events related to workflow "
                "order data processing), 'jobs' (job start & stop events), 'job-data' (events related to job "
                "instance processing), 'services' (service events), 'api' (audit api calls that make changes), "
                "'api-read' (audit api calls that only return information), 'user-events' (audit user events), "
                "'oload' (audit oload code loading events), 'alerts' (audit alert events), 'groups' (audit group "
                "status changes)",
            "first-in"    : "2.6.2",
            "validate"    : sub (list l) {
                code check = sub (string opt) {
                    if (!inlist(tolower(opt), AuditOptionList)) {
                        if (opt == "*") {
                            if (elements l != 1)
                                throw "AUDIT-OPTION-ERROR", sprintf("'*' is only valid if it is the only element in "
                                    "the list (list given: %y)", l);
                        }
                        else {
                            throw "AUDIT-OPTION-ERROR", sprintf("%y is not a valid option (valid options: %y or '*' "
                                "for all options)", opt, AuditOptionList);
                        }
                    }
                };
                map check($1), l;
            },
            "startup-only": True,
        ),

        "max-service-threads": (
            "arg": Type::Int,
            "desc": "maximum amount of threads a Qorus service can start",
            "first-in": "2.7.0.p2",
            "startup-only": True,
        ),

        "debug-system": (
            "arg": Type::Boolean,
            "desc": "turns on Qorus system debugging",
            "first-in": "2.8.1.p3",
        ),

        "defines": (
            "arg": Type::Hash,
            "desc": "defines for Qorus user code",
            "first-in": "2.8.1.p3",
            "startup-only": True,
        ),

        # feature 645: add an option to suppress automatic updating of workflow errors but only allow automatic creation of global errors
        "auto-error-update": (
            "arg": Type::Boolean,
            "desc": "allows workflow error definitions to be updated automatically based on the workflow's error definition function",
            "first-in": "2.8.1.p7",
            "startup-only": True,
        ),

        "transient-alert-max": (
            "arg": Type::Int,
            "desc": "maximum number of transient alerts stored in Qorus",
            "first-in": "3.0.0",
            "startup-only": True,
        ),

        "alert-smtp-connection": (
            "arg": Type::String,
            "desc": "the connection name for the SMTP server for alert email delivery",
            "first-in": "3.0.0",
            "startup-only": True,
        ),

        "alert-smtp-to": (
            "arg": Type::String,
            "list": True,
            "desc": "email recipient 'To:' list for alerts",
            "first-in": "3.0.0",
            "startup-only": True,
        ),

        "alert-smtp-from": (
            "arg": Type::String,
            "desc": "email recipient 'From:' value for alerts",
            "first-in": "3.0.0",
            "startup-only": True,
        ),

        "alert-smtp-interval": (
            "arg": Type::Int,
            "desc": "alert email coalescing interval in seconds",
            "first-in": "3.0.0",
            "startup-only": True,
        ),

        "alert-smtp-enable": (
            "arg": Type::Boolean,
            "desc": "enable alert emails; this property is runtime changeable",
            "first-in": "3.0.0",
        ),

        "alert-fs-full": (
            "arg": Type::Int,
            "desc": "raise an ongoing alert if a monitored filesystem is greater than the given percentage full",
            "first-in": "3.0.0",
            "startup-only": True,
        ),

        "sql-default-blocksize": (
            "arg": Type::Int,
            "desc": "Size of the regular session recovery and workflow startup SQL batches",
            "first-in": "3.0.0",
            "validate": sub (int i) {
                if (i < 1)
                    throw "SQL-DEFAULT-BLOCKSIZE-OPTION-ERROR", sprintf("illegal value %d for sql-default-blocksize: this option can use any integer greater than 0 as a config value", i);
            },
            "startup-only": False,
        ),

        "sql-init-blocksize": (
            "arg": Type::Int,
            "desc": "Size of the first workflow startup SQL batch for instant workflow instance processing as soon as possible",
            "first-in": "3.0.0",
            "validate": sub (int i) {
                if (i < 1)
                    throw "SQL-INIT-BLOCKSIZE-OPTION-ERROR", sprintf("illegal value %d for sql-init-blocksize: this option can use any integer greater than 0 as a config value", i);
            },
            "startup-only": False,
        ),

        "connection-modules": (
            "arg": Type::String,
            "list": True,
            "desc": "module names for externally-defined connection handling",
            "first-in": "3.0.0",
            "startup-only": True,
        ),

        "dsp-warning-timeout": (
            "arg": Type::Int,
            "desc": "the connection acquisition timeout threshold in milliseconds for raising transient alerts against DatasourcePool objects",
            "first-in": "3.0.0",
            "startup-only": True,
        ),

        "dsp-error-timeout": (
            "arg": Type::Int,
            "desc": "the connection acquisition timeout threshold in milliseconds for DatasourcePool objects for raising exceptions",
            "first-in": "3.0.0",
            "startup-only": True,
            "interval": (30000, "UNLIMITED"),
        ),

        "manage-interfaces": (
            "arg": Type::Boolean,
            "desc": "start and stop interfaces depending on their connection status",
            "first-in": "3.0.0",
            "workflow": True,
            # issue #2851: can be applied to services and jobs when persistent option handling is implemented
            # for services and jobs (already implemented for workflows)
        ),

        "socket-warning-timeout": (
            "arg": Type::Int,
            "desc": "the socket operation timeout threshold in milliseconds for raising transient alerts against socket-based connection objects",
            "first-in": "3.0.0",
        ),

        "socket-min-throughput": (
            "arg": Type::Int,
            "desc": "the minimum socket throughput in bytes/second below which a warning will be raised for socket-based connection objects",
            "first-in": "3.0.0",
        ),

        "socket-min-throughput-ms": (
            "arg": Type::Int,
            "desc": "the minimum time in milliseconds a socket transfer must take for it to be eligible for throughput warnings; transfers that take less time than this are ignored",
            "first-in": "3.0.0",
        ),

        "autostart-interfaces": (
            "arg": Type::Boolean,
            "desc": "allows workflows, services, and jobs to be started when the system starts",
            "first-in": "3.0.2",
            "startup-only": True,
        ),

        "service-perf-events": (
            "arg": Type::Boolean,
            "desc": "enables SERVICE_METHOD_PERFORMANCE event emission on all service calls; note that enabling this option can cause service method call performance degredation",
            "first-in": "3.0.3",
        ),

        "workflow-perf-events": (
            "arg": Type::Boolean,
            "desc": "enables WORKFLOW_PERFORMANCE event emission for all workflows",
            "first-in": "4.0",
        ),

        "workflow-step-perf-events": (
            "arg": Type::Boolean,
            "desc": "enables WORKFLOW_STEP_PERFORMANCE event emission for all workflow steps; note that enabling this option can cause workflow step performance degredation",
            "first-in": "3.0.3",
        ),

        "mapper-modules": (
            "arg": Type::String,
            "list": True,
            "desc": "module names for externally-defined data mapper classes",
            "first-in": "3.1.0",
            "startup-only": True,
        ),

        "oracle-datasource-pool": (
            "arg": Type::Boolean,
            "desc": "module names for externally-defined data mapper classes",
            "first-in": "3.1.0",
            "startup-only": True,
        ),

        "vmap-size-threshold": (
            "arg": Type::Int,
            "desc": "Maximum size of a value map for it to be cached entirely on its first reference",
            "first-in": "3.1.0",
        ),

        "sync-delay": (
            "arg": Type::Int,
            "desc": "sets the workflow synchronization event cache expiration delay in seconds",
            "interval": (0, "UNLIMITED"),
            "first-in": "3.1",
        ),

        "systemdb": {
            "arg": Type::String,
            "desc": "A connection string to the system DB schema",
            "first-in": "4.0",
            "startup-only": True,
            "validate": sub (string conn_str) {
                try {
                    auto r = parse_datasource(conn_str);
                    delete r;
                } catch (hash<ExceptionInfo> ex) {
                    throw "OPTIONS-CONFIG-ERROR", sprintf("qorus.systemdb cannot be parsed: %s", ex.desc);
                }
            },
        },

        "stack-size": {
            "arg": Type::Int,
            "desc": "The default stack size in bytes for new threads in all interfaces and in qorus-core; "
                "interface-specific values only take effect in remote processes",
            "first-in": "5.0",
            "startup-only": True,
            "interval" : (512 * 1024, "UNLIMITED"),
            "workflow": True,
            "service": True,
            "job": True,
        },

        "cors-enable": {
            "arg": Type::Boolean,
            "desc": "set to True to enable CORS headers in responses from the Qorus system HTTP handlers",
            "first-in": "5.0.6",
        },

        "cors-allow-origin": {
            "arg": Type::String,
            "list": True,
            "desc": "a list of allowed origins for the 'Access-Control-Allow-Origin' header; if an origin is in this "
                "list, then CORS responses will be enabled for the given origin if the 'cors-enable' option is True; "
                "use '*' to enable CORS for all origins",
            "first-in": "5.0.6",
        },

        "cors-allow-methods": {
            "arg": Type::String,
            "list": True,
            "desc": "a list of HTTP methods in all upper case giving the allowed methods in CORS preflight requests "
                "for accessing HTTP resources; only used if 'cors-enable' is True",
            "first-in": "5.0.6",
        },

        "cors-max-age": {
            "arg": Type::Int,
            "desc": "tells HTTP clients how long the results of a preflight request (the info contained in the '"
                "'Access-Control-Allow-Methods' and 'Access-Control-Allow-Headers' headers) can be cached; only used "
                "if 'cors-enable' is True",
            "first-in": "5.0.6",
        },

        "cors-allow-headers": {
            "arg": Type::String,
            "list": True,
            "desc": "a list of headers allowed in CORS requests; only used if 'cors-enable' is True",
            "first-in": "5.0.6",
        },

        "cors-allow-credentials": {
            "arg": Type::Boolean,
            "desc": "set to True to allow CORS requests using credentials; only used if 'cors-enable' is True",
            "first-in": "5.0.6",
        },

        "disable-https-redirect": {
            "arg": Type::Boolean,
            "desc": "set to True to disable redirecting from HTTP to HTTPS listeners for UI requests",
            "first-in": "5.1",
        },

        "password-policy-min-length": {
            "arg": Type::Int,
            "desc": "The minimum length for new passwords",
            "first-in": "6.0",
        },

        "password-policy-mixed-case": {
            "arg": Type::Boolean,
            "desc": "If both upper and lower-case letters are required in passwords",
            "first-in": "6.0",
        },

        "password-policy-numbers": {
            "arg": Type::Boolean,
            "desc": "If at least one number is required in passwords",
            "first-in": "6.0",
        },

        "password-policy-symbols": {
            "arg": Type::Boolean,
            "desc": "If at least one symbol is required in passwords",
            "first-in": "6.0",
        },

        "debug-qorus-internals": (
            "arg": Type::Boolean,
            "desc": "debug the internals of Qorus",
            "first-in": "4.0",
            "startup-only": True,
        ),

        "sensitive-data-key": (
            "arg": Type::String,
            "desc": "sensitive encryption key file for encrypting and decrypting sensitive data; defines a 32-byte encryption key",
            "path": True,
            "first-in": "3.1.1",
            "startup-only": True,
        ),

        "sensitive-value-key": (
            "arg": Type::String,
            "desc": "sensitive encryption key file for encrypting and decrypting sensitive data values; keys must be from 4 - 56 bytes in length",
            "path": True,
            "first-in": "3.1.1",
            "startup-only": True,
        ),

        "purge-sensitive-data-complete": (
            "arg": Type::Boolean,
            "desc": "if True, sensitive data is deleted immediately when a workflow order goes to COMPLETE",
            "first-in": "3.1.1",
        ),

        "purge-sensitive-data-canceled": (
            "arg": Type::Boolean,
            "desc": "if True, sensitive data is deleted immediately when a workflow order goes to CANCELED",
            "first-in": "3.1.1",
        ),

        "recovery-amount": {
            "arg": Type::Int,
            "desc": "monetary amount for a single recovered workflow order to estimate the cost savings of automatic technical error recovery in Qorus",
            "first-in": "4.0",
            "startup-only" : True,
        },

        "recovery-currency": {
            "arg": Type::String,
            "desc": "currency for recovery-amount",
            "first-in": "4.0",
            "startup-only" : True,
        },

        "sla-max-events": (
            "arg": Type::Int,
            "desc": "the maximum number of SLA events to hold before flushing to disk",
            "first-in": "3.1.1",
            "startup-only": True,
        ),

        "sla-max-sync-secs": (
            "arg": Type::Int,
            "desc": "the maximum number of seconds to hold SLA events before flushing to disk",
            "first-in": "3.1.1",
        ),

        "network-key": {
            "arg": Type::String,
            "desc": "network encryption key file for encrypting and decrypting private cluster network traffic; defines a 32-byte encryption key",
            "path": True,
            "first-in": "4.0",
            "startup-only": True,
        },

        "node": {
            "arg": "node-option-type",
            "desc": "maps hostnames to IP addresses for each node in the cluster",
            "first-in": "4.0",
            "startup-only": True,
        },

        "warning-process-memory-percent": {
            "arg": Type::Int,
            "desc": "the percent of physical memory a single Qorus cluster process can have before a warning is issued; must be lower than max-process-memory-percent",
            "first-in": "4.0",
            "interval": (1, 100),
            "startup-only": True,
        },

        "max-process-memory-percent": {
            "arg": Type::Int,
            "desc": "the maximum percent of physical memory a single Qorus cluster process can have; must be higher than warning-process-memory-percent",
            "first-in": "4.0",
            "interval": (1, 100),
            "startup-only": True,
        },

        "allow-node-overcommit-percent": {
            "arg": Type::Int,
            "desc": "the maximum percent of physical memory that the qorus master process will tolerate on a node "
                "when launching new processes",
            "first-in": "4.1.4.p3",
            "interval": (0, 100),
            "startup-only": True,
        },

        "workflow-modules": {
            "arg": Type::String,
            "list": True,
            "desc": "module names for externally-defined workflow base classes",
            "first-in": "4.0",
        },

        "service-modules": {
            "arg": Type::String,
            "list": True,
            "desc": "module names for externally-defined service base classes",
            "first-in": "4.0",
        },

        "job-modules": {
            "arg": Type::String,
            "list": True,
            "desc": "module names for externally-defined job base classes",
            "first-in": "4.0",
        },

        "default-datasource-coordinated": {
            "arg": Type::Boolean,
            "desc": "if datasources without a coordinated option in the connection definition should have coordinated "
                "mode set by default",
            "first-in": "4.0",
            "startup-only": True,
        },

        "minimum-tls-13": {
            "arg": Type::Boolean,
            "desc": "ensures minimum TLS v1.3 protocol with encrypted connections",
            "first-in": "5.1.36",
            "startup-only": True,
        },

        "dataprovider-modules": {
            "arg": Type::String,
            "list": True,
            "desc": "module names for externally-defined data providers",
            "first-in": "4.1",
        },

        "remoteconnections-file": (
            "arg"         : Type::String,
            "desc"        : "the option is ignored and considered empty from Qorus 4.0",
            "path"        : True,
            "first-in"    : "2.6.1",
            "deprecated-since" : "4.0",
            "startup-only": True,
        ),

        # temporary options / feature toggles
        "unsupported-enable-tsdb": {
            "arg": Type::Boolean,
            "desc": "enable prometheus and grafana",
            "first-in": "4.1",
            "startup-only": True,
        },
    };

    #! default values for Qorus system options
    public const QorusSystemOptionDefaults = {
        "max-log-files"                     : 10,                       # keep 10 log files when rotating
        "system-pool-minimum"               : 3,                        # minumum 3 connections to the Qorus system schema
        "system-pool-maximum"               : 40,                       # maximum 40 connections to the Qorus system schema
        "loglevel"                          : Logger::LoggerLevel::INFO,# default maximum log level = LL_DETAIL_1
        "recover_delay"                     : 300,                      # default error recovery delay = 5 minutes
        "async_delay"                       : 1200,                     # default async recovery delay = 20 minutes
        "detach-delay"                      : 3600,                     # default detach delay for workflow instance cache
        "cache-max"                         : 50000,                    # maximum number of workflow instances to cache
        "daemon-mode"                       : True,                     # default = run in the background
        "max-retries"                       : 5,                        # default 5 retries before reaching ERROR status
        "max-async-retries"                 : 20,                       # default 20 retries before reaching ERROR status
        "instance-key"                      : "qorus-test-instance",    # default instance key
        "logfile-template"                  : "OMQ-$instance-$name.log",
        "wf-logfile-template"               : "OMQ-$instance-WF-$name.log",
        "svc-logfile-template"              : "OMQ-$instance-SVC-$name.log",
        "job-logfile-template"              : "OMQ-$instance-JOB-$name.log",
        "max-events"                        : 10000,                    # 10,000 events by default stored in the event cache
        "db-max-threads"                    : 30,                       # 30 background threads for helper DB operations
        "max-service-threads"               : 200,                      # maximum 200 threads per service
        "auto-error-update"                 : True,
        "transient-alert-max"               : 1000,
        "alert-smtp-from"                   : "alert_noreply@$instance",
        "alert-smtp-interval"               : 60,
        "alert-smtp-enable"                 : False,
        "alert-fs-full"                     : 85,
        "sql-default-blocksize"             : SQL_DEF_BLOCKSIZE,
        "sql-init-blocksize"                : SQL_DEF_INIT_BLOCKSIZE,
        "dsp-warning-timeout"               : 5000,   # 5 seconds
        "dsp-error-timeout"                 : 120000, # 2 minutes
        "manage-interfaces"                 : True,
        "socket-warning-timeout"            : 10000,  # 10 second socket operation timeout
        "socket-min-throughput"             : 20480,  # 20 KiB/sec minimum socket throughput
        "socket-min-throughput-ms"          : 1000,   # 1 second minimum transfer time for socket events to be eligible for throughput warnings
        "autostart-interfaces"              : True,
        "service-perf-events"               : False,
        "workflow-perf-events"              : True,
        "workflow-step-perf-events"         : False,
        "oracle-datasource-pool"            : True,
        "vmap-size-threshold"               : 100,
        "sync-delay"                        : 3600,                     # default purge delay for workflow synchronization events
        "debug-system"                      : False,
        "debug-qorus-internals"             : False,
        "purge-sensitive-data-complete"     : True,
        "purge-sensitive-data-canceled"     : True,
        "recovery-amount"                   : 750,
        "recovery-currency"                 : "USD",
        "default-datasource-coordinated"    : False,
        "minimum-tls-13"                    : False,
        "cors-enable"                       : False,
        "cors-allow-origin"                 : ("*",),
        "cors-allow-methods"                : ("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"),
        "cors-max-age"                      : 9999999,
        "cors-allow-headers"                : (
            "Content-Type", "content-type", "Content-Language", "content-language",
            "Accept", "Accept-Language", "Authorization", "Qorus-Client-Time-Zone",
        ),
        "cors-allow-credentials"            : True,
        "disable-https-redirect"            : False,

        # SLA options
        "sla-max-events"                    : 100,           # default max 100 SLA events to hold before flushing to DB
        "sla-max-sync-secs"                 : 30,            # default max 30 seconds to hold SLA events before flushing to DB

        # cluster options
        "warning-process-memory-percent"    : 50,            # default process memory warning linit: 50% of RAM
        "max-process-memory-percent"        : 99,            # default process memory limit: max 99% of RAM
        "allow-node-overcommit-percent"     : 0,             # default tolerance for overcommitting memory

        # password policy options
        "password-policy-min-length"        : 0,
        "password-policy-mixed-case"        : False,
        "password-policy-numbers"           : False,
        "password-policy-symbols"           : False,

        # temporary options / feature toggles
        "unsupported-enable-tsdb"       : False,
    };

    #! valid Qorus client options in the options file under domain "qorus-client"
    /**
        <table>
          <tr><th>Option</th><th>Type</th><th>Description</th></tr>
          <tr><td>\c applications</td><td>@ref list_type "list" of @ref string_type "string"</td><td>application(s) served by this Qorus instance, can be used to allow @ref oload "oload" to refuse to load code tagged for applications not in the list</td></tr>
          <tr><td>\c client-pool-maximum</td><td>@ref int_type "int"</td><td>Maximum size of the connection pool</td></tr>
          <tr><td>\c client-pool-minimum</td><td>@ref int_type "int"</td><td>Minimum size of the connection pool</td></tr>
          <tr><td>\c client-url</td><td>@ref string_type "string"</td><td>URL of the Qorus server</td></tr>
          <tr><td>\c missing-tag-warning</td><td>@ref bool_type "bool"</td><td>Show missing tag warnings in @ref oload "oload"</td></tr>
          <tr><td>\c omq-data-tablespace</td><td>@ref string_type "string"</td><td>Override the system schema's data tablespace name</td></tr>
          <tr><td>\c omq-index-tablespace</td><td>@ref string_type "string"</td><td>Override the system schema's index tablespace name</td></tr>
          <tr><td>\c override-job-params</td><td>@ref bool_type "bool"</td><td>Override job schedule and runtime parameters in @ref oload "oload"</td></tr>
          <tr><td>\c proxy-url</td><td>@ref string_type "string"</td><td>URL of the proxy for the Qorus server</td></tr>
          <tr><td>\c warn-deprecated-api</td><td>@ref bool_type "bool"</td><td>if @ref True "True" will cause @ref oload "oload" to raise warnings when loading user code that references deprecated APIs</td></tr>
          <tr><td><i>&lt;datasource&gt;</i><tt>-data-tablespace</tt></td><td>@ref string_type "string"</td><td>Override the data tablespace name for given \c datasource</td></tr>
          <tr><td><i>&lt;datasource&gt;</i><tt>-index-tablespace</tt></td><td>@ref string_type "string"</td><td>Override the index tablespace name for given \c datasource</td></tr>
          <tr><td>\c allow-test-execution</td><td>@ref bool_type "bool"</td>allows execution of QorusInterfaceTest<td></td></tr>
        </table>
    */
    public const QorusClientOptionHash = (
        "applications": (
            "arg": Type::String,
            "list": True,
            "desc": "list of user applications present in this instance of Qorus",
            "first-in": "2.8.0.p7",
        ),
        "client-url": (
            "arg": Type::String,
            "desc": "URL of the Qorus server",
        ),
        "proxy-url": (
            "arg": Type::String,
            "desc": "URL of the proxy for the Qorus server",
        ),
        "client-pool-minimum": (
            "arg": Type::Int,
            "desc": "Minimum size of the connection pool",
        ),
        "client-pool-maximum": (
            "arg": Type::Int,
            "desc": "Maximum size of the connection pool",
        ),
        "missing-tag-warning": (
            "arg": Type::Boolean,
            "desc": "Show missing tag warnings in oload",
        ),
        "override-job-params": (
            "arg": Type::Boolean,
            "desc": "Override job schedule and runtime parameters in oload",
        ),
        # FIXME we accept any *-(data|index)-tablespace options, but only "omq"
        # datasource is listed here so that it gets its type verified. This is
        # unfortunate. --PQ 30-Aug-2016
        "omq-data-tablespace": (
            "arg": Type::String,
            "desc": "Override the system schema's data tablespace name",
        ),
        "omq-index-tablespace": (
            "arg": Type::String,
            "desc": "Override the system schema's index tablespace name",
        ),
        "warn-deprecated-api": (
            "arg": Type::Boolean,
            "desc": "oload will warn if a deprecated API is referenced in workflow, service, job, or library code",
            "first-in": "3.0.2",
        ),
        "remote": {
            "arg": Type::Boolean,
            "desc": "the default value of the 'remote' option for workflows, services, and jobs that have no remote specification",
            "first-in": "4.0",
        },
        # feature 2932: add new option to dis/allow execution of QorusInterfaceTest
        "allow-test-execution": {
            "arg": Type::Boolean,
            "desc": "allows execution of QorusInterfaceTest",
            "first-in": "4.0.1"
        },
    );

    #! the following are default values for options when no option is set in the option file
    public const QorusClientOptionDefaults = {
        "client-url": "http://localhost:" + OMQ::DefaultServerPort,
        "client-pool-minimum": 3,
        "client-pool-maximum": 10,
        "missing-tag-warning": True,
        "override-job-params": False,
        "warn-deprecated-api": True,
        "remote": True,
        "allow-test-execution": False,
    };

    #! backwards-compatible constant name for @ref QorusSystemOptionHash
    public const omq_option_hash = QorusSystemOptionHash;

    #! backwards-compatible constant name for @ref QorusSystemOptionDefaults
    public const option_defaults = QorusSystemOptionDefaults;

    #! backwards-compatible constant name for @ref QorusClientOptionHash
    public const client_option_hash = QorusClientOptionHash;

    #! backwards-compatible constant name for @ref QorusClientOptionDefaults
    public const client_defaults = QorusClientOptionDefaults;

    #! returns the option description including the deprecated info
    public string sub get_option_description(hash oh) {
        string desc = oh.desc;
        if (oh{"deprecated-since"})
            desc += sprintf(" (deprecated since Qorus %s)", oh{"deprecated-since"});
        return desc;
    }

    public sub check_deprecated_option(reference<*hash> oh, string k, auto val, code log) {
        if (oh."deprecated-since" && !oh."deprecated-warning-issued") {
            oh."deprecated-warning-issued" = True;
            log(sprintf("WARNING: setting deprecated option %y to %y; deprecated since Qorus %y", k, val, oh."deprecated-since"));
        }
    }

    public auto sub process_option_value(string k, auto val, hash<auto> opthash, string domain) {
        if (!opthash{k} || !exists val)
            return val;

        # bug 919
        if (val === "")
            return NOTHING;

        if (opthash{k}.arg =~ /^hash/) {
            list l = split(",", val);
            # collapse list values
            for (int i = 0; i < l.size(); ++i) {
                while ((i + 1) < l.size() && l[i + 1] !~ /=/) {
                    l[i] += "," + l[i + 1];
                    splice l, i + 1, 1;
                }
            }
            hash h;
            if (l.size() > 1) {
                foreach string e in (l) {
                    trim e;

                    h += process_single_option_value(e, opthash{k}.arg, k, domain);
                }
                val = h;
            }
        } else if (opthash{k}."list") {
            if (val.typeCode() == NT_STRING) {
                val = split(",", val);
            } else if (val.typeCode() != NT_LIST) {
                val = (val,);
            }

            # process each list entry
            for (int i = 0; i < elements val; ++i) {
                trim val[i];
                val[i] = process_single_option_value(val[i], opthash{k}.arg, k, domain);
            }

            return val;
        }

        auto rv = process_single_option_value(val, opthash{k}.arg, k, domain);
        if (opthash{k}.path) {
            rv = substitute_env_vars(rv);
        }

        return rv;
    }

    public string sub substitute_env_vars(string rv) {
        return Util::substitute_env_vars(rv);
    }

    public list<string> sub substitute_env_vars(list<auto> rv) {
        return map substitute_env_vars($1), rv;
    }

    public auto sub process_single_option_value(auto val, string type, string name, string dom) {
        switch (type) {
            case Type::Int:
                return int(val);

            case Type::String:
                return trim(string(val));

            case Type::Boolean:
                return parse_boolean(val);

            case Type::Binary:
                return binary(val);

            case Type::CallReference:
                throw "OPTION-ERROR", sprintf("cannot parse option %s.%s of type %y", dom, name, type);

            case Type::Hash:
                return process_single_hash_value(val, name);

            case "node-option-type": {
                hash<auto> h = process_single_hash_value(val, name);
                auto hval = h.firstValue();
                if (!exists hval) {
                    throw "OPTION-ERROR", sprintf("cannot parse option \"%s.%s\" with value %y; expecting "
                        "string=val[,...] format (node=ip-address[,...]); ex: \"node-a=192.168.50.45\"", dom, name,
                        val);
                }
                if (hval.typeCode() != NT_LIST) {
                    hval = split(",", hval);
                }
                if (name == "node") {
                    # verify that the values are IP addresses
                    map check_ip_address($1, True), hval;
                }
                return h;
            }

            default:
                 return val;
        }
    }

    public hash<auto> sub process_single_hash_value(auto val, string name) {
        if (val.typeCode() == NT_HASH)
            return val;
        hash<auto> rv = {};
        if (!exists val || val.empty())
            return rv;
        auto orig_val = val;
        while (True) {
            *string last = (val =~ x/(?:[^=]*,\s*)?(.+=[^=]+)$/)[0];
            if (!last) {
                break;
            }
            (*string key, *string value) = (last =~ x/(.+)=(.*)/);
            if (!exists key || !exists value) {
                throw "OPTION-ERROR", sprintf("expected key=value, got: %y when processing option %y", orig_val, name);
            }
            if (rv.hasKey(key)) {
                throw "OPTION-ERROR", sprintf("key %y repeated in option %y (val: %s)", key, name, orig_val);
            }
            rv{key} = value;
            val = replace(val, last, "");
            val =~ s/,\s*//;
        }
        return rv;
    }

    #! Mapper keys to be added to all data provider info hashes
    /** @since Qorus 4.1
    */
    public const QorusMapperKeys = {
        "context": <MapperRuntimeKeyInfo>{
            "desc": "the option's value will be processed by UserApi::expandTemplatedValue(), and the "
                "resulting value will be used",
            "value_type": "string",
            "unique_roles": "value",
        },
        "template": <MapperRuntimeKeyInfo>{
            "desc": "the value of the input field will be processed by UserApi::expandTemplatedValue(), "
                "and the resulting value will be used",
            "value_type": "bool",
            "requires_roles": "value",
        },
        "value_lookup": <MapperRuntimeKeyInfo>{
            "desc": "the format is <value map name>.<key>; the result of the lookup will be used",
            "value_type": "string",
            "unique_roles": "value",
        },
    };

    #! valid segment options
    public const segment_options = ("async", "retry");

    #! default SQL blocksize for the initial block for piecewise parallel SQL execution
    public const SQL_DEF_INIT_BLOCKSIZE = 200;

    #! default SQL blocksize when reading in new data to the WorkflowQueue
    public const SQL_DEF_BLOCKSIZE = 5000;

    #! default system workflow synchronization event type ID
    public const DefaultEventTypeID = 0;

    #! default system workflow synchronization event key
    public const DefaultEventKey = "OMQ-SYSTEM-DEFAULT-EVENT";

    #! Qorus system role hash
    public const SystemRoleHash = (
        "superuser": True,
        "operator": True,
        "read-only": True,
        "remote": True,
        "maintenance": True,
    );

    /** @defgroup QorusStartupCodes Qorus Startup Codes
        These are the possible values returned by the Qorus process when it starts up
    */
    #/@{
    public const QSE_OK                     = 0;   #!< Qorus Startup Error Code: no error
    public const QSE_NO_INSTANCE_KEY        = 1;   #!< Qorus Startup Error Code: no instance key set
    public const QSE_INVALID_DB_MAX_THREADS = 2;   #!< Qorus Startup Error Code: invalid db-max-threads option
    public const QSE_DATASOURCE             = 3;   #!< Qorus Startup Error Code: can't open system datasources
    public const QSE_LOG_ERROR              = 4;   #!< Qorus Startup Error Code: error opening system log files
    public const QSE_RBAC_ERROR             = 5;   #!< Qorus Startup Error Code: error initializing RBAC framework
    public const QSE_EVENT_ERROR            = 6;   #!< Qorus Startup Error Code: error initializing event framework
    public const QSE_SESSION_ERROR          = 7;   #!< Qorus Startup Error Code: error opening or recovering application session
    public const QSE_COMMAND_LINE_ERROR     = 8;   #!< Qorus Startup Error Code: error in command-line options
    public const QSE_OPTION_ERROR           = 9;   #!< Qorus Startup Error Code: error setting options on startup
    public const QSE_VERSION_ONLY           = 10;  #!< Qorus Startup Error Code: command-line option requested version display and exit
    public const QSE_STARTUP_ERROR          = 99;  #!< Qorus Startup Error Code: other error starting server
    #/@}

    #! groupid of the default workflow and service group
    public const DefaultGroupID   = 0;

    #! name of the default workflow and service group
    public const DefaultGroupName = "DEFAULT";

    #! default order priority
    public const DefaultOrderPriority = 500;

    #! default description length in bytes for user objects
    public const SQLDescLen = 4000;

    #! length of name columns in bytes
    public const SQLNameLen = 160;

    #! length of author columns in bytes
    public const SQLAuthorLen = 240;

    #! length of patch columns in bytes
    public const SQLPatchLen = 80;

    #! length of version columns in bytes
    public const SQLVersionLen = 80;

    #! length of sensitive data keys in bytes
    /** @since Qorus 3.1.1
     */
    public const SQLSensitiveKeyLen = 150;

    #! length of sensitive data key values in bytes
    /** @since Qorus 3.1.1
     */
    public const SQLSensitiveValueLen = 150;

    /** @defgroup JobStatusDescriptions Job Data Status Descriptions
        These are the possible descriptions for a job's status code.
        Note that descriptive status values are returned by almost all API functions even though
        @ref SQLJobStatusCodes "abbreviated codes" are actually stored in the database.
        @see @ref SQLJobStatusCodes for the corresponding value for each status description
        @see OMQ::JSMap for a hash that can be used to map from descriptive status codes to @ref SQLJobStatusCodes
        @see OMQ::SQLJSMap for a hash that can be used to map from SQL status codes to @ref JobStatusDescriptions
        @see OMQ::JS_ALL for a list of all valid Job statuses

        @since Qorus 2.6.1
    */
    #/@{
    #! Job Status Text Description: \c COMPLETE
    /** The equivalent status code actually stored in the database is @ref OMQ::SQL_JS_Complete */
    public const JS_Complete   = "COMPLETE";
    #! Job Status Text Description: \c IN-PROGRESS
    /** The equivalent status code actually stored in the database is @ref OMQ::SQL_JS_InProgress */
    public const JS_InProgress = "IN-PROGRESS";
    #! Job Status Text Description: \c ERROR
    /** The equivalent status code actually stored in the database is @ref OMQ::SQL_JS_Error */
    public const JS_Error      = "ERROR";
    #! Job Status Text Description: \c CRASH
    /** The equivalent status code actually stored in the database is @ref OMQ::SQL_JS_Crash */
    public const JS_Crash      = "CRASH";
    #/@}

    #! list of all Job status descriptions
    public const JS_ALL      = ( JS_Complete, JS_InProgress, JS_Error, JS_Crash );

    # WARNING: keep these constants synchronized with QORUS_SYSTEM_JOB pl/sql (TYPES pkg) specification!

    /** @defgroup SQLJobStatusCodes Job Data Status Codes
        These are the possible values for a job's status; this is the actual value that is stored in the DB
        @see @ref JobStatusDescriptions for the corresponding description for each status code
        @see OMQ::JSMap for a hash that can be used to map from descriptive status codes to @ref SQLJobStatusCodes
        @see OMQ::SQLJSMap for a hash that can be used to map from SQL status codes to @ref JobStatusDescriptions

        @since Qorus 2.6.1
    */
    #/@{
    #! Job Status SQL Character Code: \c COMPLETE
    /** The equivalent descriptive status is @ref OMQ::JS_Complete */
    public const SQL_JS_Complete   = "C";
    #! Job Status SQL Character Code: \c IN-PROGRESS
    /** The equivalent descriptive status is @ref OMQ::JS_InProgress */
    public const SQL_JS_InProgress = "I";
    #! Job Status SQL Character Code: \c ERROR
    /** The equivalent descriptive status is @ref OMQ::JS_Error */
    public const SQL_JS_Error      = "E";
    #! Job Status SQL Character Code: \c CRASH
    /** The equivalent descriptive status is @ref OMQ::JS_Crash */
    public const SQL_JS_Crash      = "Z";
    #/@}

    #! list of all Job status character codes
    public const SQL_JS_ALL = (
        SQL_JS_Complete,
        SQL_JS_InProgress,
        SQL_JS_Error,
        SQL_JS_Crash,
    );

    #! map of Job status descriptions to the character code
    public const JSMap = {
        "COMPLETE"    : "C",
        "IN-PROGRESS" : "I",
        "ERROR"       : "E",
        "CRASH"       : "Z",
    };

    #! map of Job status character codes to the description
    public const SQLJSMap = {
        "C" : "COMPLETE",
        "I" : "IN-PROGRESS",
        "E" : "ERROR",
        "Z" : "CRASH",
    };

    #! job programs will have the following parse options
    public const JobParseOptions = CommonParseOptions;

    #! mapper programs will have the following parse options when created before importing modules
    public const MapperParseOptions1 = CommonParseOptions;

    #! mapper programs will have the following parse options added after importing modules
    public const MapperParseOptions2 = PO_LOCKDOWN;

    #! mapper programs will have the following parse options at the end of setup
    public const MapperParseOptions = MapperParseOptions1|MapperParseOptions2;

    #! job programs have the following API
    public const JobAPI = (
    ) + CommonAPI;

    #! mapper programs have the following API
    public const MapperAPI = (
    );

    #! @defgroup AuditEventCodes Audit Event Codes
    /** These are the possible audit event codes for system auditing events.
    */
    #/@{
    #! user event audit code
    /** this code is used when a user audit event is written to the \c AUDIT_EVENTS table
    */
    public const AE_USER_EVENT = 1;

    #! system startup audit code
    /** this code is used when a "system startup" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_SYSTEM_STARTUP
    */
    public const AE_SYSTEM_STARTUP = 2;

    #! system shutdown audit code
    /** this code is used when a "system shutdown" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_SYSTEM_SHUTDOWN
    */
    public const AE_SYSTEM_SHUTDOWN = 3;

    #! system recovery start audit code
    /** this code is used when a "system recovery start" audit event is written to the \c AUDIT_EVENTS table
    */
    public const AE_SYSTEM_RECOVERY_START = 4;

    #! system recovery complete audit code
    /** this code is used when a "system recovery complete" audit event is written to the \c AUDIT_EVENTS table
    */
    public const AE_SYSTEM_RECOVERY_COMPLETE = 5;

    #! workflow status change audit code
    /** this code is used when a "workflow status change" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_WORKFLOW_STATUS_CHANGED
    */
    public const AE_WORKFLOW_STATUS_CHANGE = 6;

    #! workflow start audit code
    /** this code is used when a "workflow start" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_WORKFLOW_START
    */
    public const AE_WORKFLOW_START = 7;

    #! workflow stop audit code
    /** this code is used when a "workflow stop" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_WORKFLOW_STOP
    */
    public const AE_WORKFLOW_STOP = 8;

    #! service start audit code
    /** this code is used when a "service start" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_SERVICE_START
    */
    public const AE_SERVICE_START = 9;

    #! service stop audit code
    /** this code is used when a "service stop" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_SERVICE_STOP
    */
    public const AE_SERVICE_STOP = 10;

    #! job start audit code
    /** this code is used when a "job start" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_JOB_START
    */
    public const AE_JOB_START = 11;

    #! job stop audit code
    /** this code is used when a "job stop" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_JOB_STOP
    */
    public const AE_JOB_STOP = 12;

    #! job instance start audit code
    /** this code is used when a "job instance start" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_JOB_INSTANCE_START
    */
    public const AE_JOB_INSTANCE_START = 13;

    #! job instance stop audit code
    /** this code is used when a "job instance stop" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_JOB_INSTANCE_STOP
    */
    public const AE_JOB_INSTANCE_STOP = 14;

    #! api call audit code
    /** this code is used when a "api call" audit event is written to the \c AUDIT_EVENTS table
    */
    public const AE_API_CALL = 15;

    #! job recovery audit code
    /** this code is used when a "job recovery" audit event is written to the \c AUDIT_EVENTS table
    */
    public const AE_JOB_RECOVERY = 16;

    #! workflow order data created audit code
    /** this code is used when a workflow order is created and the "order created" audit event is written to the \c AUDIT_EVENTS table
    */
    public const AE_WORKFLOW_DATA_CREATED = 17;

    #! ongoing alert raised audit code
    /** this code is used when an ongoing alert is raised and the "alert ongoing raised" audit event is written to the \c AUDIT_EVENTS table

        @since Qorus 3.0.0
    */
    public const AE_ALERT_ONGOING_RAISED = 18;

    #! ongoing alert cleared audit code
    /** this code is used when an ongoing alert is cleared and the "alert ongoing cleared" audit event is written to the \c AUDIT_EVENTS table

        @since Qorus 3.0.0
    */
    public const AE_ALERT_ONGOING_CLEARED = 19;

    #! transient alert raised audit code
    /** this code is used when a transient alert is raised and the "alert transient raised" audit event is written to the \c AUDIT_EVENTS table

        @since Qorus 3.0.0
    */
    public const AE_ALERT_TRANSIENT_RAISED = 20;

    #! source file loaded into the system schema by @ref oload "oload"
    /** this code is used when any source file is loaded into the database by @ref oload "oload" and the "source file loaded" event is written to the \c AUDIT_EVENTS table

        @since Qorus 3.0.0
    */
    public const AE_SOURCE_FILE_LOADED = 21;

    #! group status changed audit code
    /** this code is used when an RBAC interface group's status changes and the "group status changed" event is writteo the the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_GROUP_STATUS_CHANGED

        @since Qorus 3.0.0
    */
    public const AE_GROUP_STATUS_CHANGED = 22;

    #! Job created audit code
    /** This code is used when a "job created" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_JOB_CREATED

        @since Qorus 5.1
    */
    public const AE_JOB_CREATED = 23;

    #! Job deleted audit code
    /** This code is used when a "job deleted" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_JOB_DELETED

        @since Qorus 5.1
    */
    public const AE_JOB_DELETED = 24;

    #! Job updated audit code
    /** This code is used when a "job updated" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_JOB_UPDATED

        @since Qorus 5.1
    */
    public const AE_JOB_UPDATED = 25;

    #! class created audit code
    /** This code is used when a "class created" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_CLASS_CREATED

        @since Qorus 5.1
    */
    public const AE_CLASS_CREATED = 23;

    #! Class deleted audit code
    /** This code is used when a "class deleted" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_CLASS_DELETED

        @since Qorus 5.1
    */
    public const AE_CLASS_DELETED = 24;

    #! Class updated audit code
    /** This code is used when a "class updated" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_CLASS_UPDATED

        @since Qorus 5.1
    */
    public const AE_CLASS_UPDATED = 25;

    #! connection created audit code
    /** This code is used when a "connection created" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_CONNECTION_CREATED

        @since Qorus 5.1
    */
    public const AE_CONNECTION_CREATED = 26;

    #! Connection deleted audit code
    /** This code is used when a "connection deleted" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_CONNECTION_DELETED

        @since Qorus 5.1
    */
    public const AE_CONNECTION_DELETED = 27;

    #! Connection updated audit code
    /** This code is used when a "connection updated" audit event is written to the \c AUDIT_EVENTS table
        @see @ref OMQ::QEC_CONNECTION_UPDATED

        @since Qorus 5.1
    */
    public const AE_CONNECTION_UPDATED = 28;
    #/@}

    #! @defgroup AuditEventStrings Audit Event Strings
    /** These are the possible audit event strings corresponding to the audit event codes for system auditing events
    */
    #/@{
    #! user event audit code
    /** this code is used when a user audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_USER_EVENT
    */
    public const AES_USER_EVENT = "USER-EVENT";

    #! system startup audit code
    /** this code is used when a "system startup" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_SYSTEM_STARTUP
    */
    public const AES_SYSTEM_STARTUP = "SYSTEM-STARTUP";

    #! system shutdown audit code
    /** this code is used when a "system shutdown" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_SYSTEM_SHUTDOWN
    */
    public const AES_SYSTEM_SHUTDOWN = "SYSTEM-SHUTDOWN";

    #! system recovery start audit code
    /** this code is used when a "system recovery start" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_SYSTEM_RECOVERY_START
    */
    public const AES_SYSTEM_RECOVERY_START = "SYSTEM-RECOVERY-START";

    #! system recovery complete audit code
    /** this code is used when a "system recovery complete" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_SYSTEM_RECOVERY_COMPLETE
    */
    public const AES_SYSTEM_RECOVERY_COMPLETE = "SYSTEM-RECOVERY-COMPLETE";

    #! workflow status change audit code
    /** this code is used when a "workflow status change" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_WORKFLOW_STATUS_CHANGE
    */
    public const AES_WORKFLOW_STATUS_CHANGE = "WORKFLOW-STATUS-CHANGE";

    #! workflow start audit code
    /** this code is used when a "workflow start" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_WORKFLOW_START
    */
    public const AES_WORKFLOW_START = "WORKFLOW-START";

    #! workflow stop audit code
    /** this code is used when a "workflow stop" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_WORKFLOW_STOP
    */
    public const AES_WORKFLOW_STOP = "WORKFLOW-STOP";

    #! service start audit code
    /** this code is used when a "service start" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_SERVICE_START
    */
    public const AES_SERVICE_START = "SERVICE-START";

    #! service stop audit code
    /** this code is used when a "service stop" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_SERVICE_STOP
    */
    public const AES_SERVICE_STOP = "SERVICE-STOP";

    #! job start audit code
    /** this code is used when a "job start" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_JOB_START
    */
    public const AES_JOB_START = "JOB-START";

    #! job stop audit code
    /** this code is used when a "job stop" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_JOB_STOP
    */
    public const AES_JOB_STOP = "JOB-STOP";

    #! job instance start audit code
    /** this code is used when a "job instance start" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_JOB_INSTANCE_START
    */
    public const AES_JOB_INSTANCE_START = "JOB-INSTANCE-STOP";

    #! job instance stop audit code
    /** this code is used when a "job instance stop" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_JOB_INSTANCE_STOP
    */
    public const AES_JOB_INSTANCE_STOP = "JOB-INSTANCE-START";

    #! api call audit code
    /** this code is used when a "api call" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_API_CALL
    */
    public const AES_API_CALL = "API-CALL";

    #! job recovery audit code
    /** this code is used when a "job recovery" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_JOB_RECOVERY
    */
    public const AES_JOB_RECOVERY = "JOB-RECOVERY";

    #! workflow order data created audit code
    /** this code is used when a workflow order is created and the "order created" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_WORKFLOW_DATA_CREATED
    */
    public const AES_WORKFLOW_DATA_CREATED = "WORKFLOW-DATA-CREATED";

    #! ongoing alert raised audit code
    /** this code is used when an ongoing alert is raised and the "alert ongoing raised" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_ALERT_ONGOING_RAISED

        @since Qorus 3.0.0
    */
    public const AES_ALERT_ONGOING_RAISED = "ALERT-ONGOING-RAISED";

    #! ongoing alert cleared audit code
    /** this code is used when an ongoing alert is cleared and the "alert ongoing cleared" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_ALERT_ONGOING_CLEARED

        @since Qorus 3.0.0
    */
    public const AES_ALERT_ONGOING_CLEARED = "ALERT-ONGOING-CLEARED";

    #! transient alert raised audit code
    /** this code is used when a transient alert is raised and the "alert transient raised" audit event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_ALERT_TRANSIENT_RAISED

        @since Qorus 3.0.0
    */
    public const AES_ALERT_TRANSIENT_RAISED = "ALERT-TRANSIENT-RAISED";

    #! source file loaded into the system schema by oload audit code
    /** this code is used when any source file is loaded into the database by oload and the "source file loaded" event is written to the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_SOURCE_FILE_LOADED

        @since Qorus 3.0.0
    */
    public const AES_SOURCE_FILE_LOADED = "SOURCE-FILE-LOADED";

    #! group status changed audit code
    /** this code is used when an RBAC interface group's status changes and the "group status changed" event is writteo the the \c AUDIT_EVENTS table; corresponds to @ref OMQ::AE_GROUP_STATUS_CHANGED

        @since Qorus 3.0.0
    */
    public const AES_GROUP_STATUS_CHANGED = "GROUP-STATUS-CHANGED";
    #/@}

    #! map of audit event codes to descriptions @showinitializer
    public const AuditEventMap = (
        AE_USER_EVENT               : AES_USER_EVENT,
        AE_SYSTEM_STARTUP           : AES_SYSTEM_STARTUP,
        AE_SYSTEM_SHUTDOWN          : AES_SYSTEM_SHUTDOWN,
        AE_SYSTEM_RECOVERY_START    : AES_SYSTEM_RECOVERY_START,
        AE_SYSTEM_RECOVERY_COMPLETE : AES_SYSTEM_RECOVERY_COMPLETE,
        AE_WORKFLOW_STATUS_CHANGE   : AES_WORKFLOW_STATUS_CHANGE,
        AE_WORKFLOW_START           : AES_WORKFLOW_START,
        AE_WORKFLOW_STOP            : AES_WORKFLOW_STOP,
        AE_SERVICE_START            : AES_SERVICE_START,
        AE_SERVICE_STOP             : AES_SERVICE_STOP,
        AE_JOB_START                : AES_JOB_START,
        AE_JOB_STOP                 : AES_JOB_STOP,
        AE_JOB_INSTANCE_START       : AES_JOB_INSTANCE_START,
        AE_JOB_INSTANCE_STOP        : AES_JOB_INSTANCE_STOP,
        AE_API_CALL                 : AES_API_CALL,
        AE_JOB_RECOVERY             : AES_JOB_RECOVERY,
        AE_WORKFLOW_DATA_CREATED    : AES_WORKFLOW_DATA_CREATED,
        AE_ALERT_ONGOING_RAISED     : AES_ALERT_ONGOING_RAISED,
        AE_ALERT_ONGOING_CLEARED    : AES_ALERT_ONGOING_CLEARED,
        AE_ALERT_TRANSIENT_RAISED   : AES_ALERT_TRANSIENT_RAISED,
        AE_SOURCE_FILE_LOADED       : AES_SOURCE_FILE_LOADED,
        AE_GROUP_STATUS_CHANGED     : AES_GROUP_STATUS_CHANGED,
    );

    #! map of audit event descriptions to codes @showinitializer
    public const AuditEventCodeMap = (
        AES_USER_EVENT               : AE_USER_EVENT,
        AES_SYSTEM_STARTUP           : AE_SYSTEM_STARTUP,
        AES_SYSTEM_SHUTDOWN          : AE_SYSTEM_SHUTDOWN,
        AES_SYSTEM_RECOVERY_START    : AE_SYSTEM_RECOVERY_START,
        AES_SYSTEM_RECOVERY_COMPLETE : AE_SYSTEM_RECOVERY_COMPLETE,
        AES_WORKFLOW_STATUS_CHANGE   : AE_WORKFLOW_STATUS_CHANGE,
        AES_WORKFLOW_START           : AE_WORKFLOW_START,
        AES_WORKFLOW_STOP            : AE_WORKFLOW_STOP,
        AES_SERVICE_START            : AE_SERVICE_START,
        AES_SERVICE_STOP             : AE_SERVICE_STOP,
        AES_JOB_START                : AE_JOB_START,
        AES_JOB_STOP                 : AE_JOB_STOP,
        AES_JOB_INSTANCE_START       : AE_JOB_INSTANCE_START,
        AES_JOB_INSTANCE_STOP        : AE_JOB_INSTANCE_STOP,
        AES_API_CALL                 : AE_API_CALL,
        AES_JOB_RECOVERY             : AE_JOB_RECOVERY,
        AES_WORKFLOW_DATA_CREATED    : AE_WORKFLOW_DATA_CREATED,
        AES_ALERT_ONGOING_RAISED     : AE_ALERT_ONGOING_RAISED,
        AES_ALERT_ONGOING_CLEARED    : AE_ALERT_ONGOING_CLEARED,
        AES_ALERT_TRANSIENT_RAISED   : AE_ALERT_TRANSIENT_RAISED,
        AES_SOURCE_FILE_LOADED       : AE_SOURCE_FILE_LOADED,
        AES_GROUP_STATUS_CHANGED     : AE_GROUP_STATUS_CHANGED,
    );

    #! @defgroup AuditOptions Audit Options
    /** These are the possible audit option codes for the system option @ref audit
    */
    #/@{
    #! Audit option: system events
    /** audits the following events:
    - @ref OMQ::AE_SYSTEM_RECOVERY_START
    - @ref OMQ::AE_SYSTEM_RECOVERY_COMPLETE
    - @ref OMQ::AE_SYSTEM_STARTUP
    - @ref OMQ::AE_SYSTEM_SHUTDOWN
    */
    public const AO_SYSTEM = "system";

    #! Audit option: workflow events
    /** audits the following events:
    - @ref OMQ::AE_WORKFLOW_START
    - @ref OMQ::AE_WORKFLOW_STOP
    */
    public const AO_WORKFLOWS = "workflows";

    #! Audit option: workflow data events
    /** audits the following events:
    - @ref OMQ::AE_WORKFLOW_STATUS_CHANGE
    */
    public const AO_WORKFLOW_DATA = "workflow-data";

    #! Audit option: job events
    /** audits the following events:
    - @ref OMQ::AE_JOB_START
    - @ref OMQ::AE_JOB_STOP
    */
    public const AO_JOBS = "jobs";

    #! Audit option: job data events
    /** audits the following events:
    - @ref OMQ::AE_JOB_INSTANCE_START
    - @ref OMQ::AE_JOB_INSTANCE_STOP
    - @ref OMQ::AE_JOB_RECOVERY
    */
    public const AO_JOB_DATA = "job-data";

    #! Audit option: service events
    /** audits the following events:
    - @ref OMQ::AE_SERVICE_START
    - @ref OMQ::AE_SERVICE_STOP
    */
    public const AO_SERVICES = "services";

    #! Audit option: api write events
    /** audits the following events: @ref OMQ::AE_API_CALL for external network API calls that cause changes to be made
    */
    public const AO_API = "api";

    #! Audit option: user events
    /** audits the following events: @ref OMQ::AE_USER_EVENT
    */
    public const AO_USER_EVENTS = "user-events";

    #! Audit option: oload events
    /** audits the following event: @ref OMQ::AE_SOURCE_FILE_LOADED

        @since Qorus 3.0.0
    */
    public const AO_OLOAD_EVENTS = "oload";

    #! Audit option: alert events
    /** audits the following events: @ref OMQ::AE_ALERT_ONGOING_RAISED, @ref OMQ::AE_ALERT_ONGOING_CLEARED, @ref OMQ::AE_ALERT_TRANSIENT_RAISED

        @since Qorus 3.0.0
    */
    public const AO_ALERT_EVENTS = "alerts";

    #! Audit option: RBAC interface group events
    /** audits the following events: @ref OMQ::AE_GROUP_STATUS_CHANGED

        @since Qorus 3.0.0
    */
    public const AO_GROUP_EVENTS = "groups";

    #! Audit option: code events
    /** audits the following events:
        - @ref OMQ::AE_CLASS_CREATED
        - @ref OMQ::AE_CLASS_DELETED
        - @ref OMQ::AE_CLASS_UPDATED
        - @ref OMQ::AE_CONNECTION_CREATED
        - @ref OMQ::AE_CONNECTION_DELETED
        - @ref OMQ::AE_CONNECTION_UPDATED
        - @ref OMQ::AE_JOB_CREATED
        - @ref OMQ::AE_JOB_DELETED
        - @ref OMQ::AE_JOB_UPDATED

        @since Qorus 5.1
    */
    public const AO_CODE_EVENTS = "code";
    #/@}

    #! list of all audit options
    public const AuditOptionList = (
        AO_SYSTEM, AO_WORKFLOWS, AO_WORKFLOW_DATA, AO_JOBS,
        AO_JOB_DATA, AO_SERVICES, AO_API, AO_USER_EVENTS,
        AO_OLOAD_EVENTS, AO_ALERT_EVENTS, AO_GROUP_EVENTS,
        AO_CODE_EVENTS,
    );

    #! @defgroup AuditOptionCodes Audit Option Codes
    /** Internal codes corresponding to each audit option
    */
    #/@{
    #! Audit option code: system events
    public const AOC_SYSTEM = (1 << 0);

    #! Audit option code: workflow events
    public const AOC_WORKFLOWS = (1 << 1);

    #! Audit option code: workflow data events
    public const AOC_WORKFLOW_DATA = (1 << 2);

    #! Audit option code: job events
    public const AOC_JOBS = (1 << 3);

    #! Audit option code: job data events
    public const AOC_JOB_DATA = (1 << 4);

    #! Audit option code: service events
    public const AOC_SERVICES = (1 << 5);

    #! Audit option code: api write events
    public const AOC_API = (1 << 6);

    #! Audit option code: user events
    public const AOC_USER_EVENTS = (1 << 7);

    #! Audit option code: oload events
    /**
        @since Qorus 3.0.0
    */
    public const AOC_OLOAD_EVENTS = (1 << 8);

    #! Audit option code: alert events
    /**
        @since Qorus 3.0.0
    */
    public const AOC_ALERT_EVENTS = (1 << 9);

    #! Audit option code: RBAC interface group events
    /**
        @since Qorus 3.0.0
    */
    public const AOC_GROUP_EVENTS = (1 << 10);

    #! Audit option code: code events
    /**
        @since Qorus 5.1
    */
    public const AOC_CODE_EVENTS = (1 << 11);
    #/@}

    #! mask of all audit options
    public const AuditMask = (AOC_SYSTEM|AOC_WORKFLOWS|AOC_WORKFLOW_DATA|AOC_JOBS|AOC_JOB_DATA|AOC_SERVICES|AOC_API
        |AOC_USER_EVENTS|AOC_OLOAD_EVENTS|AOC_ALERT_EVENTS|AOC_GROUP_EVENTS|AOC_CODE_EVENTS);

    #! map of audit options to audit codes
    public const AuditOptionMap = (
        AO_SYSTEM: AOC_SYSTEM,
        AO_WORKFLOWS: AOC_WORKFLOWS,
        AO_WORKFLOW_DATA: AOC_WORKFLOW_DATA,
        AO_JOBS: AOC_JOBS,
        AO_JOB_DATA: AOC_JOB_DATA,
        AO_SERVICES: AOC_SERVICES,
        AO_API: AOC_API,
        AO_USER_EVENTS: AOC_USER_EVENTS,
        AO_OLOAD_EVENTS: AOC_OLOAD_EVENTS,
        AO_ALERT_EVENTS: AOC_ALERT_EVENTS,
        AO_GROUP_EVENTS: AOC_GROUP_EVENTS,
        AO_CODE_EVENTS: AOC_CODE_EVENTS,
    );

    #! map of audit codes to audit options
    public const AuditCodeMap = (
        AOC_SYSTEM: AO_SYSTEM,
        AOC_WORKFLOWS: AO_WORKFLOWS,
        AOC_WORKFLOW_DATA: AO_WORKFLOW_DATA,
        AOC_JOBS: AO_JOBS,
        AOC_JOB_DATA: AO_JOB_DATA,
        AOC_SERVICES: AO_SERVICES,
        AOC_API: AO_API,
        AOC_USER_EVENTS: AO_USER_EVENTS,
        AOC_OLOAD_EVENTS: AO_OLOAD_EVENTS,
        AOC_ALERT_EVENTS: AO_ALERT_EVENTS,
        AOC_GROUP_EVENTS: AO_GROUP_EVENTS,
        AOC_CODE_EVENTS: AO_CODE_EVENTS,
    );

    #! Maximum serialized user storage key size (16K)
    public const MaxStorageSize = 16 * 1024;

    #! Root part of UI extension URL paths
    public const UiExtensionRoot = "UIExtension";

    #! byte length of the order_instance_keys keyname column
    public const ORDER_INSTANCE_KEYS_KEY_LEN = 240;

    #! byte length of the order_instance_keys value column
    public const ORDER_INSTANCE_KEYS_VALUE_LEN = 4000;

    #! source tag name
    public const SysTagSource = "_source";

    #! offset tag name
    public const SysTagOffset = "_offset";

    #! known system tags
    public const SysTagSet = {
        SysTagSource: True,
        SysTagOffset: True,
    };

    /** @defgroup RestApiHashes REST API Hash Descriptions
        This group contains REST API hash declarations
    */
    #/@{
    #! workflow order stats band info; summarizes info for a particular status code in a band
    /** @since Qorus 4.0
    */
    public hashdecl OrderStatusOutputInfo {
        #! order status disposition being summarized; see @ref WorkflowCompleteDisposition for valid codes and their meanings
        string disposition;
        #! number of events
        int count;
        #! percentage of events with the given status as a value from 0 - 100
        float pct;
    }

    #! workflow order SLA band info; summarizes info for a particular status code in a band
    /** @since Qorus 4.0
    */
    public hashdecl OrderSlaOutputInfo {
        #! completed within SLA flag
        bool in_sla;
        #! number of events
        int count;
        #! percentage of events with the given status as a value from 0 - 100
        float pct;
    }

    #! workflow order stats summary info hash
    /** @since Qorus 4.0
    */
    public hashdecl OrderSummaryOutputInfo {
        #! label for output
        string label;

        #! start of date range for output
        date range_start;

        #! list of summary info of events in each status
        list<hash<OrderStatusOutputInfo>> l();

        #! list of SLA info information; max two elements for where \c in_sla is @ref True "True" and where one where \c in_sla is @ref False "False"
        list<hash<OrderSlaOutputInfo>> sla();
    }

    #! this hash describes service methods with a particular SLA
    /** @since Qorus 3.1.1
    */
    public hashdecl SlaServiceMethodInfo {
        #! the service ID
        int serviceid;
        #! the service type; either \c "system" or \c "user"
        string type;
        #! the service name
        string service_name;
        #! the service methods ID
        int service_methodid;
        #! the service method name
        string method_name;
    }

    #! this hash describes jobs with a particular SLA
    /** @since Qorus 3.1.1
    */
    public hashdecl SlaJobInfo {
        #! the job ID
        int jobid;
        #! the job name
        string name;
    }

    #! this hash describes SLAs
    /** @since Qorus 3.1.1
    */
    public hashdecl SlaInfo {
        #! the ID of the SLA
        int slaid;
        #! the name of the SLA
        string name;
        #! describes the meaning of SLA event values (allowed values: \c "seconds" and \c "other")
        string units;
        #! the description of the SLA
        string description;
        #! list of service methods with the SLA
        list<hash<SlaServiceMethodInfo>> methods();
        #! list of jobs with the SLA
        list<hash<SlaJobInfo>> jobs();
    }

    #! this hash describes SLA events
    /** @since Qorus 3.1.1
    */
    public hashdecl SlaEventInfo {
        #! the ID of the SLA
        int slaid;
        #! the name of the SLA
        string name;
        #! the SLA event ID
        softint sla_eventid;
        #! the SLA performance value
        number value;
        #! the SLA event producer string
        string producer;
        #! indicates if the SLA event was successful or not
        softbool success;
        #! the SLA event error code string in case of an error
        *string err;
        #! the SLA event error description string in case of an error
        *string errdesc;
        #! the SLA event timestamp
        date created;
        #! a boolean flag indicating if the SLA event was retrieved from the archive schema
        *bool archive;
    }

    #! this hash provides SLA performance info
    /** @since Qorus 3.1.1
    */
    public hashdecl SlaPerformanceInfo {
        #! a string describing the group when grouping performance events
        string grouping;
        #! the number of records in the group
        int count;
        #! the minimum timestamp for the group (@ref nothing if no events were found in the group)
        *date mindate;
        #! the maximum timestamp for the group (@ref nothing if no events were found in the group)
        *date maxdate;
        #! the minimum SLA event processing value in the group (@ref nothing if no events were found in the group)
        *number minprocessing;
        #! the average SLA event processing value in the group (@ref nothing if no events were found in the group)
        *number avgprocessing;
        #! the maximum SLA event processing value in the group (@ref nothing if no events were found in the group)
        *number maxprocessing;
        #! the ratio of success (1) to failure (0) in calls in the group (@ref nothing if no events were found in the group)
        *number successratio;
    }

    #! this hash provides info about @ref sensitive_data "workflow order sensitive data"
    /** @since Qorus 3.1.1.p1
    */
    public hashdecl SensitiveDataInfo {
        #! the sensitive data hash for the sensitive data key and value
        hash data;

        #! zero or more aliases for the sensitive key value
        *softlist aliases;

        #! optional sensitve data metadata
        /** the following keys are recommended:
            - \c PURPOSE: free-form information about the purpose of the sensitive data
            - \c CATEGORIES: free-form information about the categories of sensitive data
            - \c RECIPIENTS: free-form information about the recipients or recipient categories of sensitive data
            - \c STORAGE: free-form information about the storage time or rules for sensitive data
        */
         *hash meta;
    }

    #! This hash provides information about job instance execution
    /** @since Qorus 4.0
    */
    public hashdecl JobResultInfo {
        #! the job_instanceid for the result
        softint job_instanceid;

        #! the status of the result; see @ref JobStatusDescriptions for possible values
        string status;
    }
    #/@}

    #! Job recovery information
    /** @since Qorus 4.0
    */
    public hashdecl JobRecoveryInfo {
        #! number of job instances recovered
        softint jcount = 0;

        #! number of job (types) recovered
        softint jrcount = 0;
    }

    #! Workflow recovery information
    /** @since Qorus 4.0
    */
    public hashdecl WorkflowRecoveryInfo {
        #! number of job instances recovered
        softint count = 0;

        #! number of job (types) recovered
        softint sgcount = 0;

        #! number of workflow (types) recovered
        softint wcount = 0;
    }

    #! the default workflow SLA threshold value as an integer in seconds
    /** the default value is equal to 30 minutes

        @since Qorus 4.0
    */
    public const DefaultWorkflowSlaThreshold = 1800;

    #! class that defines workflow attributes
    public class WorkflowDef {
        public {
            softint workflowid;
            string name;
            string version;
            *string patch;
            *string description;
            *string author;
            *string workflow_modules;
            softbool remote;
            softbool manual_remote;
            softint autostart;
            softbool manual_autostart;
            softint sla_threshold;
            softbool manual_sla_threshold;
            *softint max_instances;
            softbool enabled;
            *string code;
            string language;
            *string language_info;
            *string class_name;
            *string staticdata_type_path;
            softbool has_detach;
            *softint errorfunction_instanceid;
            *softint attach_func_instanceid;
            *softint detach_func_instanceid;
            *softint onetimeinit_func_instanceid;
            *softint errhandler_func_instanceid;
            softdate created;
            *softdate modified;
            *list<string> keylist;
            *hash<string, bool> order_key_map;
            *list<hash<auto>> mappers;
            *list<hash<auto>> vmaps;

            #! maps step IDs to step names
            hash stepmap;

            hash steps;
            list segment;
            hash stepseg;
            *hash options;
            *hash lib;
            *hash custom_statuses;
            *softbool depr;
            *hash tags;
            *softint loggerid;
        }
    }

    #! class that defines job attributes
    public class JobDef {
        public {
            softint jobid;
            string name;
            *string description;
            string version;
            *string author;
            *string job_modules;
            softbool remote;
            softbool manual_remote;
            *softint sessionid;
            softbool active;
            softbool manual_active;
            softbool run_skipped;
            softbool manually_updated;
            softbool enabled;
            softbool open;
            string code;
            string language;
            *string language_info;
            softbool class_based;
            *string class_name;
            *string yaml_config_items;
            *string yaml_fsm_triggers;
            *string minute;
            *string hour;
            *string day;
            *string month;
            *string wday;
            *softint recurring;
            *softdate last_executed;
            *int last_executed_job_instanceid;
            *softdate expiry_date;
            *softdate custom_trigger;
            *list mappers;
            *list vmaps;
            *softint slaid;
            softdate created;
            *softdate modified;
            *hash tags;
            *softint loggerid;
        }
    }

    #! class that defined mapper attributes
    public class MapperDef {
        public {
            softint mapperid;
            string name;
            string version;
            *string patch;
            *string description;
            *string author;
            string type;
            hash fields;
            *hash options;
            softdate created;
            *softdate modified;
        }
    }

    #! class that defines error attributes
    public class ErrorDef inherits Qore::Serializable {
        public {
            #! Error attributes
            const BoolAttrs = ("business_flag");
            const ErrorAttrs = BoolAttrs + ("error", "description", "severity", "retry_delay_secs", "manually_updated", "status");
            const AllErrorAttrs = ErrorAttrs + "manually_updated";

            string error;
            *string description;
            string severity;
            string status;
            softbool business_flag;
            *softint retry_delay_secs;
            softbool manually_updated;
        }

        constructor(hash<auto> h) {
            if (!h.error)
                throw "BAD-ERROR-DEFINITION", sprintf("missing required \"error\" key in error hash: %y", h);
            if (!h.severity)
                h.severity = ES_Major;
            if (!exists h.status)
                h.status = OMQ::StatError;
            if (!exists h.business_flag)
                h.business_flag = False;
            if (!exists h.manually_updated)
                h.manually_updated = False;
            map self.$1 = h.$1 === NULL ? NOTHING : h.$1, AllErrorAttrs;
        }

        bool equal(ErrorDef e) {
            foreach string attr in (ErrorAttrs) {
                if (e{attr} != self{attr})
                    return False;
            }
            return True;
        }

        hash<auto> getCompatHash() {
            # NOTE: hash(<object>) only works with public members
            hash<auto> h = hash(self);
            h.desc = remove h.description;
            h.business = remove h.business_flag;
            return h;
        }

        hash<auto> getGlobalInfo(bool with_type = True) {
            return hash(self) - "manually_updated" + (with_type ? ("type": "global") : NOTHING);
        }

        hash<auto> getWorkflowInfo(bool with_type = True) {
            return hash(self) + (with_type ? ("type": "workflow") : NOTHING);
        }
    }

    #! list of module loaded in all Qorus Program containers including mapper Programs
    public const CommonModuleList = (
        "uuid",
        "xml",
        "json",
        "yaml",
        "Mime",
        "Util",
        "SqlUtil",
        "DataStreamClient",
        "RestClient",
    );

    #! list of modules automatically loaded into Qorus programs (for workflows, services, jobs, etc)
    public const ModuleList = CommonModuleList + ("SoapClient", "MapperUtil", "Mapper", "TableMapper");

    #! list of modules automatically loaded into Qorus service programs
    public const ServiceModuleList = ModuleList + ("HttpServerUtil", "RestHandler");

    # list of classes common to all user code Program objects
    public const CommonClassList = (
        "QorusRemoteServiceHelper", "QorusSystemAPIHelper", "QorusSystemRestHelper", "QorusLocalRestHelper",
        "AbstractParallelStream", "DbRemote", "DbRemoteSend", "DbRemoteReceive", "DbRemoteRawReceive",
        "FsRemote", "FsRemoteSend",
        "AbstractFsRemoteReceive", "QorusInboundTableMapper", "QorusInboundTableMapperIterator",
        "QorusSqlStatementOutboundMapper", "QorusRawSqlStatementOutboundMapper", "OMQ::UserApi::UserApi",
        "QorusConfigurationItemProvider", "OMQ::Observer", "OMQ::Observable", "OMQ::DelayedObservable",
        "QorusSystemAPIHelperBase",
        "QorusSystemRestHelperBase",
        "QorusMapper",
        "QorusRestartableTransaction",
    );

    #! list of service classes
    public const ServiceOnlyClassList = (
        "ServiceApi", "QorusService", "AbstractServiceHttpHandler",
        "AbstractFtpHandler", "AbstractServiceRestHandler",
        "AbstractServiceWebSocketHandler", "QorusWebSocketConnection", "QorusExtensionHandler",
        "AbstractServiceDataStreamResponseHandler", "AbstractServiceStream",
        "AbstractPersistentDataHelper", "OMQ::PermissiveAuthenticator", "ServiceFileHandler",
        "QorusParametrizedAuthenticator", "DefaultQorusRBACAuthenticator", "DefaultQorusRBACBasicAuthenticator",
        "QorusCookieAuthenticator",
    );

    #! list of service classes + common classes
    public const ServiceClassList = CommonClassList + ServiceOnlyClassList;

    #! list of system service classes
    public const SystemServiceClassList = (
        "SQLInterface", "Map", "QdspClient",
        "QdspStatement", "SnapshotsInfoHelper", "QorusPluginService", "QorusSystemService",
    );

    #! list of workflow classes
    public const WorkflowOnlyClassList = (
        "WorkflowApi",
        "DynamicDataHelper",
        "StepDataHelper",
        "TempDataHelper",
        "SensitiveDataHelper",
        "QorusStepBase",
        "QorusAsyncArrayStep",
        "QorusAsyncStep",
        "QorusEventArrayStep",
        "QorusEventStep",
        "QorusNormalArrayStep",
        "QorusNormalStep",
        "QorusSubworkflowArrayStep",
        "QorusSubworkflowStep",
        "QorusWorkflow",
    );

    #! list of workflow classes + common classes
    public const WorkflowClassList = CommonClassList + WorkflowOnlyClassList;

    #! list of job classes
    public const JobOnlyClassList = (
        "OMQ::UserApi::Job::JobApi",
        "OMQ::UserApi::Job::QorusJob",
    );

    #! list of job classes + common classes
    public const JobClassList = CommonClassList + JobOnlyClassList;

    #! list of hashdecls common to all user code Program objects (except mappers)
    public const CommonHashDeclList = (
        "SlaInfo",
        "SlaEventInfo",
        "SlaPerformanceInfo",
        "SensitiveDataInfo",
        "ConfigItemInfo",
        "HttpBindOptionInfo",
        "QorusWorkflowInfo",
        "QorusServiceInfo",
        "QorusJobInfo",
        "QorusMapperInfo",
        "QorusVMapInfo",
        "QorusFsmInfo",
        "QorusPipelineInfo",
        "QorusUserInfo",
    );

    #! hash of config item info
    /** @since Qorus 4.0
    */
    public hashdecl ConfigItemInfo {
        #! the type of the configuration item
        /** valid types are:
            - \c "string" (the default)
            - \c "int"
            - \c "bool"
            - \c "float"
            - \c "date"
            - \c "hash"
            - \c "list"
            - \c "connection"
            - \c "data-provider"
            - \c "job"
            - \c "service"
            - \c "value-map"
            - \c "workflow"
            - \c "*string"
            - \c "*int"
            - \c "*bool"
            - \c "*float"
            - \c "*date"
            - \c "*hash"
            - \c "*list"
            - \c "*connection"
            - \c "*data-provider"
            - \c "*job"
            - \c "*service"
            - \c "*value-map"
            - \c "*workflow"
        */
        string type = "string";
        #! the description of the configuration item
        string description;
        #! the default value of the configuration item
        auto default_value;
        #! allow the item to be overridden at the next level?
        /** @since Qorus 4.0.3
        */
        bool strictly_local = False;

        #! the group of the configuration item
        /** @since Qorus 4.0.3
        */
        string config_group = "Default";

        #! the list of allowed values for the configuration item
        /**
            Only compatible with the following types:
            - \c int
            - \c string
            - \c float
            - \c date
            - \c *int
            - \c *string
            - \c *float
            - \c *date

            @since Qorus 4.0.3
        */
        list<auto> allowed_values;

        #! flags the type as a sensitive value - to be displayed masked by default
        bool sensitive = False;

        #! the prefix of the configuration item
        /** @since Qorus 4.1.2
        */
        *string prefix;
    }

    #! HTTP binding options
    /** @since Qorus 4.0.3
    */
    public hashdecl HttpBindOptionInfo {
        #! whether to allow sharing of listener by other services
        bool allow_listener_sharing = False;
    }

    #! base class for Qorus program classes, where the parse options are reset after each object is parsed
    public class QorusProgram inherits Program {
        public {
            # to support languages other than Qore; do not use "hash<auto>" here
            hash lang_data;

            # to manage %Qore objects created from other programming languages without deterministic GC
            hash<string, object> object_cache;

            # runtime python initialization mutex
            Mutex rt_lck();

            # class ID -> True
            hash<string, bool> lib_cache_class;

            # function ID -> True
            hash<string, bool> lib_cache_func;

            # pipeline name -> True
            hash<string, bool> lib_cache_pipe;

            # FSM name -> True
            hash<string, bool> lib_cache_fsm;

            # marked default qore modules as injected
            bool compat_qore_module_imports;

            # Java initialization constants
            const QPJ_None =       0;
            const QPJ_Old =        (1 << 0);
            const QPJ_New =        (1 << 1);
            const QPJ_CompatMods = (1 << 2);
        }

        constructor(bool inject, int po, list<auto> stddefs, *hash<auto> opts, *hash<auto> defs,
                *list<auto> ml = ModuleList) : Program(QorusProgram::getQorusParseOptions(inject, po, opts)) {
%ifdef QorusServer
            if (inject) {
                # perform injections
                importClass("QdspClient", "Qore::SQL::DatasourcePool", True);
                importClass("QdspStatement", "Qore::SQL::SQLStatement", True);
                importSystemClasses();
            }
%endif

            # load in default modules
            map loadModule($1), ml;
            # define all strings in the standard defines list
            map define($1, True), stddefs;
            # define extra defines
            map define($1.key, $1.value), defs.pairIterator();

%ifdef QorusCore
            define("QorusCore", True);
            define("QorusHasIxApis", True);
%else
            define("QorusClusterServer", True);
%endif
            define("QorusServer", True);
            define("QorusHasAnyIxApi", True);

            # issue #3217: inject deserialization function so that any locally-declared hashdecls or objects can be deserialized
            if (po & PO_ALLOW_BARE_REFS) {
                parsePending("auto sub _qorus_deserialize(data d) { return Serializable::deserialize(d); }",
                    "injected deserialization");
                parsePending("auto sub _qorus_call_code(code c) { return call_function_args(c, argv); }",
                    "injected call_code");
            } else {
                parsePending("auto sub _qorus_deserialize(data $d) { return Serializable::deserialize($d); }",
                    "injected deserialization");
                parsePending("auto sub _qorus_call_code(code $c) { return call_function_args($c, $argv); }",
                    "injected call_code");
            }
        }

        *hash<auto> parse(string code, string label, *softint warn_mask, *string source, *softint offset) {
%ifndef QorusClientInjectedTest
            int po = getParseOptions();
            on_success replaceParseOptions(po);
%endif
            return Program::parse(code, label, warn_mask, source, offset);
        }

        *hash<auto> parsePending(string code, string label, *softint warn_mask, *string source, *softint offset) {
%ifndef QorusClientInjectedTest
            int po = getParseOptions();
            on_success replaceParseOptions(po);
%endif
            return Program::parsePending(code, label, warn_mask, source, offset);
        }

%ifdef QorusServer
        nothing setProgramName(softstring id, string name, string version) {
            # used when debugging to identify program, name:version to get correct getScriptName()
            setScriptPath(sprintf("%s/%s/%s/%s:%s", Qorus.options.get("instance-key"), self.className(), id, name, version));
        }
%endif

        #! gets the parse options for the interface's @ref Qore::Program "Program container"
        static int getQorusParseOptions(bool inject, int po, *hash<auto> opts) {
%ifdef QorusServer
            if (inject) {
                po |= PO_NO_SYSTEM_CLASSES|PO_ALLOW_INJECTION;
            }
%endif
            return po;
        }

        hash<auto> javaCompile(hash<string, string> sources, *object options, *hash<string, binary> injected_classes,
                *string classpath, *int java_api) {
            if (!lang_data.java.init) {
                if (!java_api) {
                    foreach string source in (sources.values()) {
                        if (source =~ /^import (qore|qoremod|python|pythonmod)\./m) {
                            java_api = QPJ_New;
                            break;
                        }
                    }
                }
                initJava(java_api);
            }
            if (!compat_qore_module_imports) {
                foreach string source in (sources.values()) {
                    if (checkCompatQoreModuleImports(source)) {
                        setCompatQoreModuleImports();
                        compat_qore_module_imports = True;
                        break;
                    }
                }
            }
            hash<auto> comp = getJavaCompilationObjects(options, injected_classes, classpath);
            map comp.compiler.injectClass($1.key, $1.value), injected_classes.pairIterator();
            return map {
                ($1.key =~ x/([^\.]+)$/)[0]: $1.value,
            }, comp.compiler.compile(sources, comp.diags).pairIterator();
        }

        initJava(int java_api = QPJ_New) {
            lang_data.java.init = True;
            loadModule("jni");

            # setup Qorus common Java API
            issueModuleCmd("jni", "add-classpath " + ENV.OMQ_DIR + "/jar/qore-jni.jar");
            if (java_api & QPJ_Old) {
                throw "UNSUPPORTED", "the deprecated hardcoded Java API is not supported in the Community Edition";
            }
            if (java_api & QPJ_New) {
                issueModuleCmd("jni", "import qore.OMQ.*");
                issueModuleCmd("jni", "import qore.OMQ.UserApi.*");
            }
            if (java_api & QPJ_CompatMods) {
                setCompatQoreModuleImports();
                compat_qore_module_imports = True;
            }
            issueModuleCmd("jni", "import org.qore.*");
            issueModuleCmd("jni", "import org.qore.jni.*");

            # setup dynamic compilation
            issueModuleCmd("jni", "add-classpath $OMQ_DIR/jar/qore-jni-compiler.jar");

            issueModuleCmd("jni", "import java.util.ArrayList");
            issueModuleCmd("jni", "import javax.tools.DiagnosticCollector");
            issueModuleCmd("jni", "import org.qore.jni.compiler.QoreJavaCompiler");
            issueModuleCmd("jni", "import org.qore.jni.compiler.CompilerOutput");

            # create function to return a Java object from the class name and class bytecode
            # get and restore parse options
%ifndef QorusClientInjectedTest
            int po = getParseOptions();
            on_success replaceParseOptions(po);
%endif

            setParseOptions(PO_NEW_STYLE | PO_REQUIRE_TYPES | PO_STRICT_ARGS);
            loadModule("reflection");
        }

        bool checkCompatQoreModuleImports(string source) {
            return (source =~ /^import qore\.(uuid|xml|json|yaml|Mime|Util|SqlUtil|DataStreamClient|"
                "RestClient|SoapClient|Mapper|MapperUtil|TableMapper)\./m);
        }

        setCompatQoreModuleImports() {
            map issueModuleCmd("jni", "mark-module-injected " + $1), ModuleList;
        }

        Reflection::Class getClass(string name) {
            string source = sprintf("Reflection::Class::forName(%y)", name);
            Expression exp(self, source, "QorusProgram::getClass()");
            return exp.eval();
        }

        object getObject(string name) {
            string source = sprintf("Reflection::Class::forName(%y).newObject()", name);
            Expression exp(self, source, "QorusProgram::getObject()");
            return exp.eval();
        }

        hash<auto> getJavaCompilationObjects(*object options, *hash<string, binary> injected_classes, *string classpath) {
            Class cls_compiler = getClass("QoreJavaCompiler");
            Class cls_diags = getClass("DiagnosticCollector");
            object loader = getJavaClassLoader();
            if (classpath) {
                loader.addPath(classpath);
            }
            return {
                "compiler": cls_compiler.newObject(loader, options),
                "diags": cls_diags.newObject(),
            };
        }

        object getJavaClassLoader() {
            Expression exp(self, "jni::get_class_loader()", "QorusProgram::getJavaClassLoader()");
            return exp.eval();
        }

        initPython(bool load_common = True) {
            lang_data.python.init = True;
            loadModule("python");

            issueModuleCmd("python", "import-ns OMQ OMQ");
            issueModuleCmd("python", "alias OMQ.UserApi.UserApi UserApi");

            # setup python module path
            # add generic python module directory
            string path = sprintf("%s/user/python/site-packages", ENV.OMQ_DIR);
            issueModuleCmd("python", "add-module-path " + path);
            issueModuleCmd("python", "import sys");
            hash<auto> info = get_module_hash().python.info;
            string py_ver = sprintf("%d.%d", info.python_major, info.python_minor);
            path = sprintf("%s/user/python/lib/python%s/site-packages", ENV.OMQ_DIR, py_ver);
            issueModuleCmd("python", "add-module-path " + path);
            # check for "lib64" dir
            path = sprintf("%s/user/python/lib64/python%s/site-packages", ENV.OMQ_DIR, py_ver);
            if (is_dir(path)) {
                issueModuleCmd("python", "add-module-path " + path);
            }

            # create function to return a Python object from the class name
            # get and restore parse options
%ifndef QorusClientInjectedTest
            int po = getParseOptions();
            on_success replaceParseOptions(po);
%endif

            setParseOptions(PO_NEW_STYLE | PO_REQUIRE_TYPES | PO_STRICT_ARGS);
            loadModule("reflection");
        }

        auto evalPythonExpressionIntern(string expr) {
            string source = sprintf("PythonProgram::evalExpression(%y)", expr);
            Expression exp(self, source, "QorusProgram::evalPythonExpression()");
            return exp.eval();
        }

        *string cacheJavaClass(string name, string db_language_info, *bool cache_object, *string classpath) {
            hash<auto> lang_hash = parse_yaml(db_language_info);
            return cacheJavaClass(name, lang_hash, cache_object, classpath, NOTHING,
                lang_hash.java_api == "new" ? QPJ_New : QPJ_Old);
        }

        *string cacheJavaClass(string name, hash<auto> lang_hash, *bool cache_object, *string classpath) {
            return cacheJavaClass(name, lang_hash, cache_object, classpath, NOTHING,
                lang_hash.java_api == "new" ? QPJ_New : QPJ_Old);
        }

        *string cacheJavaClass(string name, hash<auto> lang_hash, *bool cache_object, *string classpath,
                *bool pending, int java_api = QPJ_New) {
            if (!lang_data.java.init) {
                if (lang_hash.compat_imports) {
                    java_api |= QPJ_CompatMods;
                }
                initJava(java_api);
            } else if (lang_hash.compat_imports && !compat_qore_module_imports) {
                setCompatQoreModuleImports();
                compat_qore_module_imports = True;
            }

            # first setup classpath for import statements
            if (classpath) {
                # respect multiple values concatenated with unescaped ','
                classpath =~ s/([^\\]),/$1:/g;
                map issueModuleCmd("jni", "add-classpath " + $1), classpath.split(":");
            }

            # define all classes except for the main one
            *string main_class_name;
            foreach hash<auto> i in (lang_hash.class_data.pairIterator()) {
                string class_name = lang_hash.package
                    ? sprintf("%s/%s", lang_hash.package, i.key)
                    : i.key;
                if (i.key != name || pending) {
                    issueModuleCmd("jni", "define-pending-class " + class_name + " " + i.value.toBase64());
                } else {
                    main_class_name = class_name;
                }
            }

            # define the main one
            if (main_class_name) {
                issueModuleCmd("jni", "define-class " + main_class_name + " " + lang_hash.class_data{name}.toBase64());
                if (cache_object) {
                    main_class_name =~ s/\//::/g;
                    lang_data.java.classes{name} = {
                        "class_name": main_class_name,
                    };
                    return main_class_name;
                }
            }
        }

        *string cachePythonClass(string name, string source, *string db_language_info, *bool cache_object,
                *string module_path) {
            return cachePythonClass(name, source,
                db_language_info
                    ? parse_yaml(db_language_info)
                    : {},
                cache_object, module_path
            );
        }

        *string cachePythonClass(string name, string source, hash<auto> lang_info, *bool cache_object,
                *string module_path) {
            if (!lang_data.python.init) {
                initPython();
            }
            if (module_path) {
                # respect multiple values concatenated with unescaped ','
                module_path =~ s/([^\\]),/$1:/g;
                map issueModuleCmd("python", "add-module-path " + $1), module_path.split(":");
            }

            issueModuleCmd("python", "parse " + name + " " + source);
            issueModuleCmd("python", "export-class " + name);
            if (cache_object) {
                lang_data.python.classes{name} = {
                    "class_name": name,
                };
            }
        }

        initQoreObjectClass() {
            lang_data.qore.init = True;

            # create function to return a Java object from the class name and class bytecode
            # get and restore parse options
%ifndef QorusClientInjectedTest
            int po = getParseOptions();
            on_success replaceParseOptions(po);
%endif

            setParseOptions(PO_NEW_STYLE | PO_REQUIRE_TYPES | PO_STRICT_ARGS);
            loadModule("reflection");
        }

        cacheQoreClassObject(string name) {
            if (!lang_data.qore.init) {
                initQoreObjectClass();
            }
            lang_data.qore.classes{name} = {
                "class_name": name,
            };
        }

        parseCommit(*int warning_mask) {
            Program::parseCommit(warning_mask);
%ifdef QorusServer
            # create Java class objects in the Program container
            foreach hash<auto> i in (lang_data.java.classes.pairIterator()) {
                lang_data.java.classes{i.key}.obj = getObject(i.value.class_name);
               #QDBG_LOG("JAVA %y (%y): %y", i.value.class_name, i.key, lang_data.java.classes{i.key}.obj);
            }
            # create Qore class objects in the Program container
            foreach hash<auto> i in (lang_data.qore.classes.pairIterator()) {
                lang_data.qore.classes{i.key}.obj = getObject(i.value.class_name);
                #QDBG_LOG("QORE %y (%y): %y", i.value.class_name, i.key, lang_data.java.classes{i.key}.obj);
            }
%endif
        }

        Reflection::Class getCreateClass(string lang, string name) {
            *Reflection::Class rv = lang_data{lang}.classes{name}.cls;
            if (!rv) {
                rv = lang_data{lang}.classes{name}.cls = getClass(name);
            }
            return rv;
        }

        object getCreateObject(string lang, string name) {
            *object rv = lang_data{lang}.classes{name}.obj;
            if (!rv) {
                rv = lang_data{lang}.classes{name}.obj = getObject(name);
                QDBG_LOG("CREATED ON DEMAND (%y) %y (%y)", lang, name, keys lang_data{lang}.classes);
            }
            return rv;
        }

        #! called at runtime
        auto evalPythonExpression(string expr) {
            # check outside the lock, in the ideal case, it's already been initialized, so no locking necessary
            if (!lang_data.python.init) {
                # we need to ensure that Python initialization is serialized
                rt_lck.lock();
                on_exit rt_lck.unlock();

                # check again in the lock
                if (!lang_data.python.init) {
                    initPython();
                    Program::parseCommit();
                }
            }
            return evalPythonExpressionIntern(expr);
        }
    }

    #! used to create workflow program objects (client & server)
    public class WorkflowProgram inherits QorusProgram {
        private {
            hash<auto> step_objects;
        }

        #! creates an empty Workflow @ref Qore::Program "Program container" with defines set as per @ref QorusWorkflowDefines
        constructor(*hash<auto> opts, *hash<auto> defs, *int po) : QorusProgram(True, WorkflowParseOptions | po,
                QorusWorkflowDefines, opts, defs) {
            define("QorusWfApi", True);
%ifndef QorusCore
            define("QorusQwfServer", True);
%endif
        }

        initJava(int java_api = QPJ_New) {
            QorusProgram::initJava(java_api);
            staticInitJava(self, java_api);
        }

        static staticInitJava(QorusProgram pgm, int java_api) {
            if (java_api & QPJ_Old) {
                throw "UNSUPPORTED", "the deprecated hardcoded Java API is not supported in the Community Edition";
            }
            if (java_api & QPJ_New) {
                pgm.issueModuleCmd("jni", "import qore.OMQ.UserApi.Workflow.*");
            }
        }

        initPython() {
            QorusProgram::initPython();
            # alias Java workflow API
            issueModuleCmd("python", "alias OMQ.UserApi.Workflow wf");
            issueModuleCmd("python", "alias OMQ.UserApi.Workflow.WorkflowApi wfapi");
        }

        parseCommit(hash<auto> step_class_map, *int warning_mask, int java_api = QPJ_New) {
            if (step_class_map.java && !lang_data.java.init) {
                initJava(java_api);
            }
            if (step_class_map.qore && !lang_data.qore.init) {
                initQoreObjectClass();
            }

            Program::parseCommit(warning_mask);
%ifdef QorusHasWfApi
            ensure_create_tld();
            # create Qore class objects in the Program container
            foreach string step_id in (keys step_class_map.qore) {
                # set tld.stepID to be available for step object construction
                QDBG_LOG("QORE (step id: %y), tld.stepID: %y", step_id, tld.stepID);
                tld.stepID = step_id;
                QDBG_LOG("QORE (step id: %y), tld.stepID: %y", step_id, tld.stepID);
                foreach string class_name in (keys step_class_map.qore{step_id}) {
                    step_objects.qore{step_id}{class_name} = getObject(class_name);
                    QDBG_LOG("QORE %y (step id: %y): %y", class_name, step_id, step_objects.qore{step_id}{class_name});
                }
            }

            # create Java class objects in the Program container
            foreach string step_id in (keys step_class_map.java) {
                # set tld.stepID to be available for step object construction
                tld.stepID = step_id;
                foreach string class_name in (keys step_class_map.java{step_id}) {
                    step_objects.java{step_id}{class_name} = getObject(class_name);
                    QDBG_LOG("JAVA %y (step id: %y): %y", class_name, step_id, step_objects.java{step_id}{class_name});
                }
            }
%endif
        }

        # step_id = wf for the workflow class
        object getCreateObject(softstring step_id, string lang, string name) {
            *object step_object = step_objects{lang}{step_id}{name};
            if (!step_object) {
                step_object = step_objects{lang}{step_id}{name} = getObject(name);
                #QDBG_LOG("CREATED ON DEMAND (%y) %y (%y)", lang, name, keys step_objects);
            }
            return step_object;
        }
    }

    #! used to create service program objects (client & server)
    public class ServiceProgram inherits QorusProgram {
        constructor(bool system, *int po, *hash<auto> opts, *hash<auto> defs, list<auto> ml = ServiceModuleList)
                : QorusProgram(!system, ServiceParseOptions
                    | (system ? OMQ::SystemServiceParseOptions : 0) | po,
                QorusServiceDefines, system ? NOTHING : opts, defs, ml) {
            define("QorusSvcApi", True);
%ifndef QorusCore
            define("QorusQsvcServer", True);
%endif
        }

        initJava(int java_api = QPJ_New) {
            QorusProgram::initJava(java_api);
            staticInitJava(self, java_api);
        }

        static staticInitJava(QorusProgram pgm, int java_api) {
            if (java_api & QPJ_Old) {
                throw "UNSUPPORTED", "the deprecated hardcoded Java API is not supported in the Community Edition";
            }
            if (java_api & QPJ_New) {
                pgm.issueModuleCmd("jni", "import qore.OMQ.UserApi.Service.*");
            }
        }

        bool checkCompatQoreModuleImports(string source) {
            return (source =~ /^import qore\.(uuid|xml|json|yaml|Mime|Util|SqlUtil|DataStreamClient|"
                "RestClient|SoapClient|Mapper|MapperUtil|TableMapper|HttpServerUtil|RestHandler)\./m);
        }

        setCompatQoreModuleImports() {
            map issueModuleCmd("jni", "mark-module-injected " + $1), ServiceModuleList;
        }

        initPython() {
            QorusProgram::initPython();
            # alias Java service API
            issueModuleCmd("python", "alias OMQ.UserApi.Service svc");
            issueModuleCmd("python", "alias OMQ.UserApi.Service.ServiceApi svcapi");
        }
    }

    #! used to create job program objects (client & server)
    public class JobProgram inherits QorusProgram {
        constructor(*hash<auto> opts, *hash<auto> defs, *int po) : QorusProgram(True, JobParseOptions | po, QorusJobDefines, opts, defs) {
            define("QorusJobApi", True);
%ifndef QorusCore
            define("QorusQjobServer", True);
%endif
        }

        initJava(int java_api = QPJ_New) {
            QorusProgram::initJava(java_api);
            staticInitJava(self, java_api);
        }

        static staticInitJava(QorusProgram pgm, int java_api) {
            if (java_api & QPJ_Old) {
                throw "UNSUPPORTED", "the deprecated hardcoded Java API is not supported in the Community Edition";
            }
            if (java_api & QPJ_New) {
                pgm.issueModuleCmd("jni", "import qore.OMQ.UserApi.Job.*");
            }
        }

        initPython() {
            QorusProgram::initPython();
            # alias Java job API
            issueModuleCmd("python", "alias OMQ.UserApi.Job job");
            issueModuleCmd("python", "alias OMQ.UserApi.Job.JobApi jobapi");
        }
    }

    #! used to create mapper program objects (client & server)
    public class MapperProgram inherits QorusProgram {
        constructor(int po, *hash<auto> opts, *hash<auto> defs, list<string> ml = CommonModuleList) : QorusProgram(True, MapperParseOptions1 | po, QorusMapperDefines, opts, defs, ml) {
            # now set lockdown parse options after modules have been loaded
            setParseOptions(OMQ::MapperParseOptions2);

            # import system objects in mapper program
            importGlobalVariable("omqservice");

            # import mapper API
            importMapperApi();
        }

        # import mapper API
        private importMapperApi() {
            # import MapperApi class
            importClass("OMQ::MapperApi::MapperApi");
            # import all mapper library functions to mapper program (no imports with different names currently supported)
            map importFunction($1), MapperAPI;
        }

        initJava(int java_api = QPJ_New) {
            # do Java initialization, but do not load common interface APIs
            QorusProgram::initJava(QPJ_None);
            staticInitJava(self, java_api);
        }

        static staticInitJava(QorusProgram pgm, int java_api) {
            if (java_api & QPJ_Old) {
                throw "UNSUPPORTED", "the deprecated hardcoded Java API is not supported in the Community Edition";
            }
            if (java_api & QPJ_New) {
                pgm.issueModuleCmd("jni", "import qore.OMQ.MapperApi.*");
            }
        }
    }

    #! used to create interface module program objects
    public class InterfaceModuleProgram inherits Program {
        constructor(*int po) : Program(PO_NO_INHERIT_GLOBAL_VARS
            |PO_NO_THREAD_CONTROL
            |PO_NO_PROCESS_CONTROL
            |PO_NO_INHERIT_USER_FUNC_VARIANTS
            |PO_NO_INHERIT_USER_CLASSES
            |PO_NO_INHERIT_USER_HASHDECLS
            |PO_NO_INHERIT_PROGRAM_DATA
            |po) {
        }
    }

    #! Default system user info
    /** @since Qorus 5.1.20
    */
    const SystemUserInfo = <QorusUserInfo>{
        "provider": "db",
        "username": DefaultSystemUser,
        "name": "Default Qorus System User",
        "has_default": True,
    };

    #! Workflow info hash
    /** @since Qorus 5.1.20
    */
    public hashdecl QorusWorkflowInfo {
        #! The workflow's ID
        int workflowid;

        #! The workflow name
        string name;

        #! The workflow version
        string version;
    }

    #! Service info hash
    /** @since Qorus 5.1.20
    */
    public hashdecl QorusServiceInfo {
        #! The service's ID
        int serviceid;

        #! The service type
        string type;

        #! The service name
        string name;

        #! The service version
        string version;

        #! The autostart flag for the service
        bool autostart;
    }

    #! Job info hash
    /** @since Qorus 5.1.20
    */
    public hashdecl QorusJobInfo {
        #! The job's ID
        int jobid;

        #! The job name
        string name;

        #! The job version
        string version;
    }

    #! Mapper info hash
    /** @since Qorus 5.1.20
    */
    public hashdecl QorusMapperInfo {
        #! The mapper's ID
        int mapperid;

        #! The type of mapper
        string type;

        #! The mapper name
        string name;

        #! The mapper version
        string version;
    }

    #! Value map info hash
    /** @since Qorus 5.1.20
    */
    public hashdecl QorusVMapInfo {
        #! The value map's ID
        int id;

        #! The value map name
        string name;
    }

    #! Finite State Machine info hash
    /** @since Qorus 5.1.20
    */
    public hashdecl QorusFsmInfo {
        #! The FSM name
        string name;
    }

    #! Pipeline info hash
    /** @since Qorus 5.1.20
    */
    public hashdecl QorusPipelineInfo {
        #! The pipeline name
        string name;
    }

    #! Qorus user information hash
    /** @since Qorus 5.1.20
    */
    public hashdecl QorusUserInfo {
        #! The name of the provider providing the user
        string provider;

        #! The username
        string username;

        #! The display name or description of the user
        string name;

        #! A boolean flag indicating if the user is a member of the \c DEFAULT group
        bool has_default;

        #! The list of roles the user has
        *list<string> roles;

        #! The list of permissions associated to the user
        *list<string> permissions;

        #! The list of workflows associated to the user; will be @ref NOTHING if \a has_default is True
        *list<hash<QorusWorkflowInfo>> workflows;

        #! The list of services associated to the user; will be @ref NOTHING if \a has_default is True
        *list<hash<QorusServiceInfo>> services;

        #! The list of jobs associated to the user; will be @ref NOTHING if \a has_default is True
        *list<hash<QorusJobInfo>> jobs;

        #! The list of mappers associated to the user; will be @ref NOTHING if \a has_default is True
        *list<hash<QorusMapperInfo>> mappers;

        #! The list of value maps associated to the user; will be @ref NOTHING if \a has_default is True
        *list<hash<QorusVMapInfo>> vmaps;

        #! The list of finite state machines associated to the user; will be @ref NOTHING if \a has_default is True
        *list<hash<QorusFsmInfo>> fsms;

        #! The list of pipelines associated to the user; will be @ref NOTHING if \a has_default is True
        *list<hash<QorusPipelineInfo>> pipelines;

        #! The list of interface groups associated to the user; will be @ref NOTHING if \a has_default is True
        *list<string> groups;

        #! User storage information
        *hash<auto> storage;
    }

    /** @defgroup TemplateContextValues Expression Template Context Values
        These constants indicate the possible values of the template context bitfield
    */
    #/@{
    #! For templates valid in a workflow context only
    public const QETC_WORKFLOW = (1 << 0);

    #! For templates valid in a service context only
    public const QETC_SERVICE = (1 << 1);

    #! For templates valid in a job context only
    public const QETC_JOB = (1 << 2);

    #! For templates valid in a non-interface context
    public const QETC_GENERIC = (1 << 3);

    #! For templates valid in any interface context but not outside an interface
    public const QETC_INTERFACE = QETC_WORKFLOW | QETC_SERVICE | QETC_JOB;

    #! For templates valid in all contexts
    public const QETC_ALL = QETC_WORKFLOW | QETC_SERVICE | QETC_JOB | QETC_GENERIC;
    #/@}

    /** @defgroup TemplateAccessValues Expression Template Access Values
        These constants indicate the possible values of the template access bitfield; whether it's available for
        reading, writing, or both
    */
    #/@{
    #! For templates valid in a read context
    public const QETA_READ = (1 << 0);

    #! For templates valid in a write context
    public const QETA_WRITE = (1 << 1);

    #! For templates valid in both read and write contexts
    public const QETA_READ_WRITE = QETA_READ | QETA_WRITE;
    #/@}

    #! Expression template info
    public hashdecl QorusTemplateInfo {
        #! The name of the template
        string name;
        #! A markdown description of the template
        string desc;
        #! A URL to the online documentation for the template
        string doc_url;
        #! a bitfield of the contexts the template is valid in; see @ref TemplateContextValues
        int valid_context;
        #! a bitfield of the access the template has; see @ref TemplateAccessValues
        int access;
    }

    #! Expression template information
    const QorusExpressionTemplateMap = {
%ifndef QorusFakeApi
        "config": <QorusTemplateInfo>{
            "name": "config",
            "desc": "The value of the given configuration item for the current context (see also `$xconfig`); "
                "a value of `*` means the all configuration items as a hash; ex: `$config:item_name`, `$config:*`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_INTERFACE,
            "access": QETA_READ,
        },
        "local": <QorusTemplateInfo>{
            "name": "local",
            "desc": "The local context hash; normally `$local:input` contains any input data as well",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings; ex: `$local:input.account.ID`, `$local:name`",
            "valid_context": QETC_ALL,
            "access": QETA_READ,
        },
        "parse-value": <QorusTemplateInfo>{
            "name": "parse-value",
            "desc": "Parses the string argument with [parse_to_qore_value()](https://qoretechnologies.com/manual/"
                "qorus/current/qore/modules/Util/html/namespace_util.html#a89e8791492287386ece443123163cc7c) after "
                "recursive template substitution; ex: `$parse-value:{id=$static:{account.id}}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_ALL,
            "access": QETA_READ,
        },
        "pstate": <QorusTemplateInfo>{
            "name": "pstate",
            "desc": "Returns or writes to he value of the given key in the interface's persistent state hash or the "
                "entire persistent state hash with `*` (read-only); see "
                "[Universal Persistent Storage](https://qoretechnologies.com/manual/qorus/current/qorus/"
                "commonserverapi.html#bb_persistent_storage); ex: `$pstate:key`, `$pstate:*`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_INTERFACE,
            "access": QETA_READ_WRITE,
        },
        "python-expr": <QorusTemplateInfo>{
            "name": "python-expr",
            "desc": "Performs template substitution on the argument and then parses the argument as a Python "
                "expression; the evaluation of the expression is used as the resulting value.  Use `qore-expr` to "
                "avoid Python's Global Interpreter Lock if possible.  Ex: `$python-expr:{(\"$info:type\" + \".\" + "
                "\"$info:name\" + \" v\" + \"$info:version\")}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb-tmpl-python-"
                "expr",
            "valid_context": QETC_ALL,
            "access": QETA_READ,
        },
        "qore-expr": <QorusTemplateInfo>{
            "name": "qore-expr",
            "desc": "Performs template substitution on the argument and then parses the argument as a Qore "
                "expression; the evaluation of the expression is used as the resulting value.  Ex: "
                "`$qore-expr:{(\"$info:type\" + \".\" + \"$info:name\" + \" v\" + \"$info:version\")}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb-tmpl-qore-"
                "expr",
            "valid_context": QETC_ALL,
            "access": QETA_READ,
        },
        "qore-expr-value": <QorusTemplateInfo>{
            "name": "qore-expr-value",
            "desc": "Returns a string representation of the value that can be used with `$qore-expr:{}`; strings are "
                "quoted (and internal strings are escaped), other values are converted to valid Qore expressions; ex: "
                "`$qore-expr-value:{$static:{order.json}}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb-tmpl-qore-"
                "expr-value",
            "valid_context": QETC_ALL,
            "access": QETA_READ,
        },
        "rest": <QorusTemplateInfo>{
            "name": "rest",
            "desc": "Returns the result of a GET request to the given system API URI path in the latest REST API; ex: "
                "`$rest:{remote/user/my-connection/url_hash/path}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_ALL,
            "access": QETA_READ,
        },
        "sysprop": <QorusTemplateInfo>{
            "name": "sysprop",
            "desc": "Returns or writes to the value from the given [system property](https://qoretechnologies.com/"
                "manual/qorus/current/qorus/sysprops.html) domain and optional key; if only a domain is given then "
                "the value returned or set must be a hash or NOTHING; ex: `$sysprop:{domain-1.key-1}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_ALL,
            "access": QETA_READ_WRITE,
       },
        "timestamp": <QorusTemplateInfo>{
            "name": "timestamp",
            "desc": "If the argument is `timegm` (i.e. `$timestamp:timegm), the return value is the integer number "
                "of seconds after the UNIX epoch (1970-01-01 UTC), otherwise the argument must be a "
                "[date format string](https://qoretechnologies.com/manual/qorus/current/qore/lang/html/"
                "group__date__and__time__functions.html#date_formatting), and the return value is a date/time value "
                "corresponsing to the format argument; ex: `$timestamp:timegm`, "
                "`$timestamp:{YYYY-MM-DD HH:mm:SS.xx Z}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_ALL,
            "access": QETA_READ,
        },
        "transient": <QorusTemplateInfo>{
            "name": "transient",
            "desc": "Returns or writes to the value from the temporary thread-local transient data hash; `*` means "
                "the entire hash (read-only); see "
                "[The Difference Between var and transient Data](https://qoretechnologies.com/manual/qorus/current/"
                "qorus/commonserverapi.html#bb_var_and_transient_difference); ex: `$transient:{account-info.id}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_INTERFACE,
            "access": QETA_READ_WRITE,
        },
        "value-map": <QorusTemplateInfo>{
            "name": "value-map",
            "desc": "The value from the given key of the given [value map](https://qoretechnologies.com/manual/qorus/"
                "current/qorus/valuemap-devel.html); ex: `$value-map:{my-map.key2}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_ALL,
            "access": QETA_READ,
        },
        "var": <QorusTemplateInfo>{
            "name": "var",
            "desc": "Returns or writes to the value from the temporary thread-local/block-local data hash; `*` means "
                "the entire hash (read-only); see "
                "[The Difference Between var and transient Data](https://qoretechnologies.com/manual/qorus/current/"
                "qorus/commonserverapi.html#bb_var_and_transient_difference); ex: `$var:{account-info.id}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb-tmpl-var",
            "valid_context": QETC_INTERFACE,
            "access": QETA_READ_WRITE,
        },
        "xconfig": <QorusTemplateInfo>{
            "name": "xconfig",
            "desc": "Returns the value of the given configuration item for the current interface context; in "
                "[data pipelines](https://qoretechnologies.com/manual/qorus/current/qorus/data_pipelines.html) and "
                "[finite state machines](https://qoretechnologies.com/manual/qorus/current/qorus/"
                "finite_state_machines.html), this will return configuration information for the interface and not "
                "for the data pipeline or finite state machine (see also `$config:`); ex: `$xconfig:item_name`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_INTERFACE,
            "access": QETA_READ,
        },

        "jinfo": <QorusTemplateInfo>{
            "name": "jinfo",
            "desc": "The value of the given key in the `info` in the [job result hash](https://qoretechnologies.com/"
                "manual/qorus/current/qorus/rest_api_data_structures.html#rest_job_result_hash); `*` means the "
                "entire hash (read-only); ex: `$jinfo:key`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_JOB,
            "access": QETA_READ_WRITE,
        },

        "state": <QorusTemplateInfo>{
            "name": "state",
            "desc": "Returns or writes to the value of the given key in the service or job's state hash (in jobs, "
                "this can be used for recovery state and is cleared when the job gets a `COMPLETE` status); `*` "
                "means the entire hash (read-only); ex: `$state:key`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_SERVICE | QETC_JOB,
            "access": QETA_READ_WRITE,
        },

        "dynamic": <QorusTemplateInfo>{
            "name": "dynamic",
            "desc": "Returns or writes to the given value from the workflow order's "
                "[dynamic data](https://qoretechnologies.com/manual/qorus/current/qorus/"
                "designimplworkflows.html#dynamicdata) hash; dot notation accepted; `*` means the entire hash "
                "(read-only); ex: `$dynamic:order.ID`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_WORKFLOW,
            "access": QETA_READ_WRITE,
        },
        "feedback": <QorusTemplateInfo>{
            "name": "feedback",
            "desc": "Provides the name of the key that the given output data value will be saved to in the parent "
                "order; only valid for child orders in a subworkflow hierarchy; each feedback key value is subject "
                "to recursive template substitution with "
                "[UserApi::expandTemplatedValue()](https://qoretechnologies.com/manual/qorus/current/qorus/"
                "classOMQ_1_1UserApi_1_1UserApi.html#a0bc42ca0c0f1bd01bdc31bfab111ce57); ex: `$feedback:key`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_WORKFLOW,
            "access": QETA_WRITE,
        },
        "keys": <QorusTemplateInfo>{
            "name": "keys",
            "desc": "Returns or writes to the value of the given [workflow order key](https://qoretechnologies.com/"
                "manual/qorus/current/qorus/designimplworkflows.html#wf_keylist); each order key value is subject "
                "to recursive template substitution with "
                "[UserApi::expandTemplatedValue()](https://qoretechnologies.com/manual/qorus/current/qorus/"
                "classOMQ_1_1UserApi_1_1UserApi.html#a0bc42ca0c0f1bd01bdc31bfab111ce57); ex: `$keys:order_id`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_WORKFLOW,
            "access": QETA_READ_WRITE,
        },
        "sensitive": <QorusTemplateInfo>{
            "name": "sensitive",
            "desc": "Returns or writes to the given value from the "
                "[workflow order's sensitive data hash](https://qoretechnologies.com/manual/qorus/current/qorus/"
            "designimplworkflows.html#order_sensitive_data); dot notation accepted; the first two components of the "
            "value are the sensitive data key and the sensitive data value; ex: `$sensitive:taxid.xxxx.address`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_WORKFLOW,
            "access": QETA_READ_WRITE,
        },
        "static": <QorusTemplateInfo>{
            "name": "static",
            "desc": "Returns the given value from the "
                "[workflow order's static data hash](https://qoretechnologies.com/manual/qorus/current/qorus/"
                "designimplworkflows.html#staticdata); dot notation accepted; `*` means the entire hash (read-only); "
                "ex: `$static:order.ID`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_WORKFLOW,
            "access": QETA_READ,
        },
        "step": <QorusTemplateInfo>{
            "name": "step",
            "desc": "Returns the given value from the [current step's step data hash](https://qoretechnologies.com/"
                "manual/qorus/current/qorus/designimplworkflows.html#stepdata); dot notation accepted; `*` means the "
                "entire hash (read-only); ex: `$step:{order-data.address}`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_WORKFLOW,
            "access": QETA_READ_WRITE,
        },
        "temp": <QorusTemplateInfo>{
            "name": "temp",
            "desc": "Returns the given value from the "
                "[workflow order's temporary data hash](https://qoretechnologies.com/manual/qorus/current/qorus/"
                "designimplworkflows.html#tempdata); dot notation accepted; `*` means the entire hash (read-only); "
                "ex: `$temp:order.ID`",
            "doc_url": "https://qoretechnologies.com/manual/qorus/current/qorus/commonserverapi.html#bb_template_"
                "strings",
            "valid_context": QETC_WORKFLOW,
            "access": QETA_READ_WRITE,
        },
%endif
    };

    public nothing sub wait_for_all_threads(*code logf) {
        # if we wait too long (10s), we start showing the stacks...
        int mytid = gettid();
        list k;
        do {
            hash<auto> t = get_all_thread_call_stacks();
            k = select keys t, $1 != mytid;
            if (k) {
                sleep(1s);
            }
        } while(k);
    }

    /*
       allowed authentication label values
    */
    public const AUTH_PERMISSIVE = "permissive";
    public const AUTH_DEFAULT = "default";
    public const AUTH_DEFAULT_BASIC = "default-basic";
    public const AUTH_COOKIE = "cookie";

    public const AUTH_LABEL_VALUES = {
        AUTH_PERMISSIVE: True,
        AUTH_DEFAULT: True,
        AUTH_DEFAULT_BASIC: True,
        AUTH_COOKIE: True,
    };

    #! Allow a dot (\c ".") in object names
    public const N_WITH_DOT      = (1 << 0);

    #! Allow an email address to be a valid object name
    public const N_EMAIL_ADDRESS = (1 << 1);

    #! Validates Qorus object (service, workflow, job, ...) names
    /**
        @param name The object name
        @param rules if present, a bitfield made up of @ref N_WITH_DOT or @ref N_EMAIL_ADDRESS

        @returns True if \a name is valid otherwise False

        Note: empty names are allowed and are valid
    */
    public bool sub is_valid_object_name(*string name, *int rules) {
        switch (rules) {
            case N_WITH_DOT:
                return (name !~ /[^[:alnum:]-_\.]/u);

            case N_EMAIL_ADDRESS:
                return (name !~ /[^[:alnum:]-_\.@]/u);
        }
        return (name !~ /[^[:alnum:]-_]/u);
    }
}
