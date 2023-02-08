# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusSystemAPI.qc defines the Qorus System API methods

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

public namespace OMQ;

# do not include the values of these keys when reporting API info
const OMQ::api_private_keys = ("code", "logopt", "maskkey");

class OMQ::QorusSystemApi {
    # for the omq.system.start-workflows RPC API
    static hash startWorkflows(hash c, hash params) {
        check_workflow_params(\params);

        if (exists params.mode) {
            params.mode = toupper(params.mode);
            if (!inlist(params.mode, (OMQ::WM_Normal, OMQ::WM_Recovery)))
                throw "PARAMETER-ERROR", sprintf("invalid mode %n, must be either NORMAL or RECOVERY", params.mode);
        }
        else
            params.mode = OMQ::WM_Normal;

        if (params.instances <= 0)
            throw "PARAMETER-ERROR", sprintf("'instances' must be assigned a positive integer value (value given: %n)", params.instances);

        list l = ();

        # issue 1775; we use a static method here so that tld is not captured as a closure-bound global thread-local variable
        on_exit
            remove tld.index;

        # workflow access is checked in Control::startWorkflowSetAtomic()
        while (params.instances--) {
            QDBG_LOG("omq.system.start-workflows wfid = %y", params.wfid);
            l += int(Qorus.control.startWorkflowSetAtomic(c, params.wfid, params.mode, params.options));
        }

        return {
            "ids": l,
            "version": params.version,
        };
    }

    # for the omq.system.start-workflow RPC API
    static hash startWorkflow(hash c, hash params) {
        check_workflow_params(\params);

        if (exists params.mode) {
            params.mode = toupper(params.mode);
            if (!inlist(params.mode, (OMQ::WM_Normal, OMQ::WM_Recovery)))
                throw "PARAMETER-ERROR", sprintf("invalid mode %n, must be either NORMAL or RECOVERY", params.mode);
        }
        else
            params.mode = OMQ::WM_Normal;

        # issue 1775; we use a static method here so that tld is not captured as a closure-bound global thread-local variable
        on_exit
            remove tld.index;

        QDBG_LOG("omq.system.start-workflow wfid = %y", params.wfid);
        # workflow access is checked in Control::startWorkflowSetAtomic()
        return {
            "id": int(Qorus.control.startWorkflowSetAtomic(c, params.wfid, params.mode, params.options)),
            "version": params.version,
        };
    }

    static hash get() {
        return (
            # info functions

            #! gives a hash of API information, where each key is a Qorus system API method
            /**
                This method accepts optional string arguments will select the methods to provide help for; if the method name has no '.' in it, then \c "omq.system." will be prepended.  For example:
                @code{.py}
omq.system.help("add-user");
                @endcode

                This will produce the following response:

                @code{.py}
omq.system.add-user:
   params: "username, password, descriptive_name, permission_list, groups"
   category: "permission based access control"
   maskargs: 1
   description: "creates a new RBAC user"
                @endcode

                @return a hash of API information, where each key is a Qorus system API method, if arguments are supplied, then only methods given by the arguments are returned in the response hash.  The hash keys are the command names, and the values are hashes with at least the following keys:
                - \c params: a description of the parameters
                - \c category: a string giving the method category
                - \c description: a description of the method
              */
            "omq.system.help" : (
                "code" : hash sub (hash c) {
                    hash h = {};

                    # remove internal keys, rename "help" -> "description"
                    code edit = hash sub (hash eh) { eh.description = remove eh.help; eh -= api_private_keys; return eh; };

                    if (elements argv)
                        foreach any cmd in (argv) {
                            if (!cmd.strp())
                                continue;
                            softstring ocmd = cmd;
                            if (cmd.typeCode() != NT_STRING)
                                cmd = cmd.toString();
                            # new prefix
                            string np;
                            if (cmd !~ /\./)
                                np = "omq.system";
                            else switch (cmd) {
                                case /^system\./: #/:
                                case /^user\./: { #/:{
                                    np = "omq";
                                    break;
                                }
                                case /^group\./: #/:
                                case /^job\./: { #/:{
                                    np = "omq.system";
                                    break;
                                }
                            }
                            if (np)
                                cmd = np + "." + cmd;
                            if (Qorus.system_api{cmd})
                                h{cmd} = edit(Qorus.system_api{cmd});
                            else {
                                HashIterator hi(Qorus.system_api);
                                bool found = False;
                                while (hi.next()) {
                                    if (hi.getKey().regex(ocmd)) {
                                        h.(hi.getKey()) = edit(hi.getValue());
                                        found = True;
                                    }
                                }
                                if (!found)
                                    h{cmd}.description = sprintf("error: no match found for method %y", ocmd);
                            }
                    }
                    else {
                        # setup return value by editing each key of the api hash in turn.
                        # use Qorus.system_api in case api methods have been added dynamically
                        map h.$1 = edit(Qorus.system_api.$1), Qorus.system_api.keyIterator();
                    }
                    return h;
                },
                "params"   : "[command_name]",
                "help"     : "gives Qorus network API method information",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a hash of all global Qorus system options and their current values
            /**
                   @return a hash of all global Qorus system options and their current values; hash keys:
                - \c value: (any) the value of the option
                - \c expects: (string) the data type the option expects
                - \c desc: (string) description of the option
                - \c default: (any) the default value of the option (if any)
                - \c startup-only: (boolean) if the option can only be set when the system is started
                - \c status: (string) either \c locked or \c unlocked
              */
            "omq.system.get-option-info" : (
                "code"     : hash sub (hash c) { return Qorus.options.getOptionInfoHash(); },
                "help"     : "gives information on available options",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a hash giving information about system status
            /**
                @return a hash giving information about system status; hash keys:
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
            "omq.system.get-status" : (
                "code" : hash sub (hash c) {
                    return argv ? qorus_get_system_info(){argv} : qorus_get_system_info();
                },
                "help"     : "returns system status information",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            #! sets one or more system options
            /**
                if any errors occur, an exception is thrown with error information, but all other options will be processed and set
                @param params key-value pairs where the key names are system option names

                @return "OK"

                @throw OPTION-ERROR invalid or locked option

                @see OMQ::omq_option_hash for valid options
              */
            "omq.system.set-option" : (
                "code" : string sub (hash c, hash params) {
                    *list errs = Qorus.options.set(params);
                    if (errs)
                        throw "OPTION-ERROR", sprintf("one or more options given was invalid or could not be set: %y", errs);
                    return "OK";
                },
                "params"   : "hash: option = value",
                "help"     : "sets Qorus system options",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! write the server's options to the @ref options "option file" on the server's filesystem
            /**
                If any option hash if passed, then such options will be saved in the file but not applied to the running process.
                If any errors occur, an exception will be thrown.

                @param params options to set in the options file

                @return "OK"

                @throw OPTION-ERROR an error occurred in creating or writing to the output file
            */
            "omq.system.flush-options" : (
                "code" : string sub (hash c, *hash params) {
                    Qorus.options.flushToFile(params);
                    return "OK";
                },
                "params"   : "optional hash: option = value or NOTHING",
                "help"     : "Write Qorus options into option file (specified by hash or running options)",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            #! initiates the system shutdown process
            /**
                This API will start the asynchronous shutdown process in the Qorus system.  The response indicates only that the shutdown process has begun, and not that the system has been fully shut down.  Check the log file or the process list (‘ps –ef') to verify that the system has completely stopped.

                @return "OK"

                @throw SHUTDOWN-ALREADY-IN-PROGRESS system shutdown is already in progress
            */
            "omq.system.shutdown" : (
                "code" : string sub (hash cx) {
                    if (Qorus.shutdown())
                        throw "SHUTDOWN-ALREADY-IN-PROGRESS", "system shutdown is already in progress";

                    olog(LoggerLevel::FATAL, "Qorus PID %d shutting down now", getpid());
                    return "OK";
                },
                "help"     : "queues an immediate system shutdown; returns immediately",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            #! shuts down the system; returns when the system shutdown process is complete
            /** @return "OK"
            */
            "omq.system.shutdown-wait" : (
                "code" : string sub (hash cx) {
                    if (!Qorus.shutdown())
                        olog(LoggerLevel::FATAL, "Qorus PID %d shutting down now", getpid());

                    Qorus.start_counter.waitForZero();
                    return "OK";
                },
                "help"     : "shuts down the Qorus system; returns when shutdown process is complete",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            # workflow functions
            #! create workflow order (workflow order data instance)
            /**
                Creates a workflow order data instance of the specified type with the data passed as the static order data.

                @param params The hash passed must have at either a \c staticdata key or an \c external_order_instanceid key, valid keys:
                - \c staticdata: the static data for the order
                - \c external_order_instanceid: the external order instance ID for the workflow data
                - \c dynamicdata: the initial dynamic data for the order
                - \c orderkeys: a hash of order keys for the order
                - \c scheduled: the earliest date and time the order can be processed; if this date is given as a future date/time value and a @ref OMQ::StatReady status is given, then the initial status of the workflow order data instance will be automatically changed to @ref OMQ::StatScheduled instead of @ref OMQ::StatReady
                - \c priority: the order priority (default @ref OMQ::DefaultOrderPriority) from 0 - 999; priority 0 is the highest; 999 is the lowest
                - \c parent_workflow_instanceid: a loosely-coupled workflow that will be marked as the parent of this workflow
                @param status create the workflow order data instance with this status; may be either:
                - @ref OMQ::StatReady which is the default value
                - @ref OMQ::StatBlocked meaning: do not process the order, wait for unblocking later

                @return a hash with the following key:
                - \c workflow_instanceid the workflow instance ID of the workflow order instance ID created

                @throw SUBMIT-ORDER-ERROR unknown workflow, invalid status

                @see omq.system.create-order()
              */
            "omq.system.submit-data.[workflow].[version]": {
                "name"     : "^omq\.system\.submit-data\..*",
                "code"     : hash sub (hash c, hash params, string status = OMQ::StatReady) {
                    string name = substr(c.method, 23);
                    int i = index(name, ".");
                    string version = substr(name, i + 1);
                    name = substr(name, 0, i);

                    status = toupper(status);

                    softstring rv;
                    try {
                        # workflow access is checked in Orders::submitData()
                        rv = orders.submitData(c, name, version, params, status);
                    }
                    catch (hash ex) {
                        string errstr = sprintf("ERROR saving order %s/%s: %s: %s", name, version, ex.err, ex.desc);
                        olog(LoggerLevel::FATAL, errstr);

                        rethrow;
                    }

                    olog(LoggerLevel::INFO, "order %s/%s from %s: created workflow instance %d", name, version, c."peer-info".address_desc, rv);

                    return ( "workflow_instanceid" : rv );
                },
                "params"   : "order data, order inital status",
                "help"     : "submits workflow order data",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO
            },

            #! create workflow order method (workflow order data instance)
            /**
                Creates a workflow order data instance of the specified type with the data passed as the static order data
                @param params The hash passed must have at either a \c staticdata key or an \c external_order_instanceid key, valid keys:
                - \c name: the name of the workflow to create
                - [\c version]: the version of the workflow to create; if this is omitted, then the latest version of the workflow is used
                - [\c staticdata]: the static data for the order; either this key or \c external_order_instanceid is required
                - [\c external_order_instanceid]: the external order instance ID for the workflow data; either this key or \c staticdata is required
                - [\c dynamicdata]: the initial dynamic data for the order
                - [\c orderkeys]: a hash of order keys for the order
                - [\c scheduled]: the earliest date and time the order can be processed; if this date is given as a future date/time value and a @ref OMQ::StatReady status is given, then the initial status of the workflow order data instance will be automatically changed to @ref OMQ::StatScheduled instead of @ref OMQ::StatReady
                - [\c priority]: the order priority (default @ref OMQ::DefaultOrderPriority) from 0 - 999; priority 0 is the highest; 999 is the lowest
                - [\c status]: the initial order status (default @ref OMQ::StatReady); must be either @ref OMQ::StatReady or @ref OMQ::StatBlocked
                - [\c parent_workflow_instanceid]: a loosely-coupled workflow that will be marked as the parent of this workflow

                @return a hash with the following key:
                - \c workflow_instanceid the workflow instance ID of the workflow order instance ID created

                @throw SUBMIT-ORDER-ERROR unknown workflow, invalid status
              */
            "omq.system.create-order" : (
                "code"     : hash sub (hash c, hash params) {
                    if (params.name.typeCode() != NT_STRING)
                        throw "SUBMIT-ORDER-ERROR", "missing 'name' with string value in parameter hash";
                    if (exists params.status && params.status.typeCode() != NT_STRING)
                        throw "SUBMIT-ORDER-ERROR", sprintf("'status' present but is not a string (type %y)", type(params.status));
                    if (exists params.version && params.version.typeCode() != NT_STRING)
                        throw "SUBMIT-ORDER-ERROR", sprintf("'version' present but is not a string (type %y)", type(params.version));

                    string name = remove params.name;
                    *string version = remove params.version;

                    # get version immediately for logging
                    if (!exists version || version.empty()) {
                        version = Qorus.qmm.rLookupWorkflow(name).lastversion;
                        if (!version)
                            throw "SUBMIT-ORDER-ERROR", sprintf("no workflow %n has been cached", name);
                    }

                    softstring rv;
                    try {
                        *string status = remove params.status;
                        # workflow access is checked in Orders::submitData()
                        rv = orders.submitData(c, name, version, params, status);
                    }
                    catch (hash ex) {
                        string errstr = sprintf("ERROR saving order %s/%s: %s: %s", name, version, ex.err, ex.desc);
                        olog(LoggerLevel::FATAL, errstr);

                        rethrow;
                    }

                    olog(LoggerLevel::INFO, "order %s/%s from %s: created workflow instance %d", name, version, c."peer-info".address_desc, rv);

                    return ( "workflow_instanceid" : rv );
                },
                "params"   : "order data, order inital status",
                "help"     : "submits workflow order data",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO ),

            #! returns workflow information for the execution id passed, or for all workflows if no execution id is passed
            /** @param id the optional workflow execution id

                @return if id is passed, then a single hash is returned, otherwise a list of workflow information hashes is returned.  The workflow information hash has the following format:
                - \c executionID: (string) the execution ID of the workflow
                - \c name: (string) the name of the workflow
                - \c version: (string) the version of the workflow
                - \c workflowid: (string) the ID of the workflow
                - \c mode: (string) the mode of the workflow
                - \c status: (string) the status of the workflow
                - \c iterations: (int) number of iterations of all segments
                - \c totalSegments: (int) number of segments in the workflow
                - \c errors: (int) number of errors encountered
                - \c warnings: (int) number of warnings encountered
                - \c starttime: (date) date and time workflow execution instance started
                - \c options: (hash) workflow options
                - \c logfile: (string) the workflow log file

                @throw INVALID-WORKFLOW-EXECUTION-ID invlaid workflow execution ID
              */
            "omq.system.get-workflow-info" : (
                "code" : any sub (hash c, *softstring id) {
                    if (!exists id) {
                        list l = Qorus.control.getWorkflowInfoList();
                        return l;
                    }

                    hash h = Qorus.control.getWorkflowInfo(id);
                    if (!exists h.workflowid)
                        throw "INVALID-WORKFLOW-EXECUTION-ID", sprintf("there is no workflow with execution ID %n", id);

                    return h;
                },
                "params"   : "[execution id]",
                "help"     : "returns workflow information for the id passed, or for all workflows if no id is passed",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a list of the workflows currently cached
            /** @return a list of hashes with the following keys:
                - \c name: (string) the name of the workflow
                - \c version: (string) the version of the workflow
                - \c workflowid: (int) the workflow ID of the workflow
                - \c cached: (date) the date and time the workflow was cached
              */
            "omq.system.show-workflow-cache" : (
                "code" : list sub (hash c) {
                    list l = Qorus.control.getWorkflowCache();
                    return l;
                },
                "help"     : "returns a list of all workflows cached",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO ),

            #! Starts a workflow execution instance with the designated name and version
            /**
                If any errors occur, an exception is thrown.
                @param params a hash with the following keys:
                - \c name: (string) the name of the workflow; this key must be present
                - \c version: (string) the version of the workflow; if the \c version key is not supplied, then the latest version of the workflow is started
                - \c mode: (string) either @ref OMQ::WM_Normal (the default if no \c mode key is present) or @ref OMQ::WM_Recovery
                - \c options: (hash) a hash of option names and values; if any options are not valid for the workflow, then an exception is raised and the workflow execution instance is not started

                @return a hash with the following keys:
                - \c id: (int) the execution ID of the workflow execution instance
                - \c version: (string) the version of the workflow started (useful if no version key supplied in the call)

                @throw PARAMETER-ERROR invalid workflow, mode, or \c options key in incorrect format (not a hash)
                @throw SHUTDOWN-IN-PROGRESS cannot start new workflows because the system is shutting down

                @note
                - the @ref ostart "ostart" command provides a user-friendly command-line interface to this method
                - also aliased by omq.system.start()

                @see omq.system.start-workflows()
              */
            "omq.system.start-workflow" : (
                "code"     : hash sub (hash c, hash params) {
                    # issue 1775: we use a static method here so we can clear tld after each call
                    # so that tld is not bound as a closure-bound global thread-local variable
                    return QorusSystemApi::startWorkflow(c, params);
                },
                "alias"    : "omq.system.start",
                "params"   : "hash: keys: name (required), [version], [options]. [mode]",
                "help"     : "starts an instance of the workflow given (or more than one instance if the 'instances' key is given",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Starts one or more workflow execution instances with the designated name and version
            /**
                If any errors occur, an exception is thrown
                @param params a hash with the following keys:
                - \c name: (string) the name of the workflow; this key must be present
                - \c instances: (int) number of execution instances to start; must be > 0
                - \c version: (string) the version of the workflow; if the \c version key is not supplied, then the latest version of the workflow is started
                - \c mode: (string) either @ref OMQ::WM_Normal (the default if no \c mode key is present) or @ref OMQ::WM_Recovery
                - \c options: (hash) a hash of option names and values; if any options are not valid for the workflow, then an exception is raised and the workflow execution instance is not started

                @return a hash with the following key:
                - \c id: (list of int) the execution IDs of the workflow execution instances started
                - \c version: (string) the version of the workflows started (useful if no version key supplied in the call)

                @throw PARAMETER-ERROR invalid workflow, mode, options key in incorrect format (not a hash), or invalid number of instances
                @throw SHUTDOWN-IN-PROGRESS cannot start new workflows because the system is shutting down

                @see omq.system.start-workflow()
              */
            "omq.system.start-workflows" : (
                "code"     : hash sub (hash c, hash params) {
                    # issue 1775: we use a static method here so we can clear tld after each call
                    # so that tld is not bound as a closure-bound global thread-local variable
                    return QorusSystemApi::startWorkflows(c, params);
                },
                "params"   : "hash: keys: name (required), instances (required), [version], [options]",
                "help"     : "starts one or more instance of the workflow given according to the value of the 'instances' key",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Executes a workflow in synchronous mode and returns the final status of the order after processing
            /**
                Starts a workflow execution instance with the designated name and version in synchronous mode against the order data given in the call.  The call will normally return only after the workflow reaches a @ref OMQ::StatComplete or @ref OMQ::StatError state, unless the system or the workflow order data instance are manually stopped while the workflow order data instance is being processed, in which case other statuses can be returned.
                @param params a hash with the following keys:
                - \c name: (string) the name of the workflow (required)
                - \c version: (string) the version of the workflow; if the \c version key is not supplied, then the latest version of the workflow is used
                - \c orderdata: (hash) the static workflow order data (required)
                - \c dynamicdata: (hash) the initial dynamic data for the workflow (optional)
                - \c options: (hash) a hash of option names and values; if any options are not valid for the workflow, then an exception is raised and the workflow execution instance is not started (optional)
                - \c priority: the order priority (default @ref OMQ::DefaultOrderPriority), ignored while the order is processed synchronously; from 0 - 999; priority 0 is the highest; 999 is the lowest
                - \c orderkeys: order keys for the order
                - \c external_order_instanceid: the optional external order instanceid for the order
                - \c parent_workflow_instanceid: a loosely-coupled workflow that will be marked as the parent of this workflow

                @return a hash with the following keys:
                - \c workflow_instanceid: the workflow instance ID for the order created
                - \c status: the status of the workflow
                - \c dynamicdata: the dynamic data of the workflow order instance
                - \c version: (string) the version of the workflow executed (useful if no version key supplied in the call)

                @throw PARAMETER-ERROR invalid workflow, mode, \c options key in incorrect format (not a hash), or \c orderdata key missing from argument hash
                @throw SHUTDOWN-IN-PROGRESS cannot start new workflows because the system is shutting down

                @see omq.system.exec-synchronous-existing()
              */
            "omq.system.exec-synchronous-workflow" : (
                "code" : hash sub (hash c, hash params) {
                    check_workflow_params(\params);

                    if (!exists params.orderdata)
                        throw "PARAMETER-ERROR", "mandatory orderdata key was not passed";

                    if (params.priority < 0)
                        params.priority = 0;
                    else if (params.priority > 999)
                        params.priority = 999;

                    # rename "orderdata" key so we can take a slice of this hash below to create the OrderData object
                    params.staticdata = remove params.orderdata;
                    OrderData order(params.("staticdata", "dynamicdata", "priority", "orderkeys",
                                                 "external_order_instanceid", "parent_workflow_instanceid"));

                    # set workflow name and version in order data
                    order.setNameAndVersion(params.name, params.version);

                    # workflow access is checked in Control::setupWorkflow()
                    return Qorus.control.execSynchronousWorkflow(c, params.wfid, order, params.options) +
                        ("version": params.version);
                },
                "params"   : "hash: keys: name (required), version (required), options (optional), orderdata (required), dynamicdata (optional)",
                "help"     : "executes an instance of the workflow given in synchronous mode",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Executes a workflow in synchronous mode against an already-existing order in the database with status @ref OMQ::StatReady
            /**
                Starts a workflow execution instance in synchronous mode against the already existing workflow order data instance identified in the hash argument (must correspond to the \c WORKFLOW_INSTANCE.WORKFLOW_INSTANCE_ID value for the data to be processed).   Note that the workflow must have a @ref OMQ::StatReady or @ref OMQ::StatScheduled (\c WORKFLOW_INSTANCE.WORKFLOW_STATUS = "Y" or "S") status in the database in order to be processed in a synchronous workflow instance; it's not possible to process workflow data with other statuses synchronously.
                The call will normally return only after the workflow reaches a @ref OMQ::StatComplete or @ref OMQ::StatError state, unless the system or the workflow order data instance are manually stopped while the workflow order data instance is being processed, in which case other statuses can be returned.

                @param params a hash with the following keys:
                - \c workflow_instanceid: the workflow instance ID of the order to process; this key is required to be set
                - \c options: (hash) an optional hash of option names and values; if any options are not valid for the workflow, then an exception is raised and the synchronous workflow execution instance is not started

                @return a hash with the following keys:
                - \c workflow_instanceid: the workflow instance ID of the order
                - \c status: the status of the workflow
                - \c dynamicdata: the dynamic data of the workflow order instance

                @throw PARAMETER-ERROR \c workflow_instanceid key missing from argument hash
                @throw SHUTDOWN-IN-PROGRESS cannot start new workflows because the system is shutting down

                @see omq.system.exec-synchronous-workflow()
              */
            "omq.system.exec-synchronous-existing" : (
                "code" : hash sub (hash c, hash params) {
                    if (!params.workflow_instanceid)
                        throw "PARAMETER-ERROR", "missing mandatory workflow_instanceid key";

                    # workflow access is checked in Control::setupWorkflow()
                    return Qorus.control.execSynchronousWorkflowOnExistingOrder(c, params.workflow_instanceid, params.options);
                },
                "params"   : "hash: keys: workflow_instanceid (required), options (optional)",
                "help"     : "start executing a synchronous workflow on the given workflow order data instance with 'Y' (READY) status",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! stops all running workflows
            /** On errors, an exception is thrown
            @return a string describing the number of workflows being stopped
            @note
            - the \c "ostop -a" command (@ref ostop "ostop") provides a user-friendly command-line interface to this method
              */
            "omq.system.stop-all-workflows" : (
                "code" : string sub (hash c) {
                    # workflow access is checked in Control::stopAllWorkflows()
                    int stopped = Qorus.control.stopAllWorkflows(c);

                    return sprintf("%d workflow execution instance%s %s been stopped", stopped,
                                   stopped != 1 ? "s" : "",
                                   stopped != 1 ? "have" : "has");
                },
                "help"     : "stops all instances of all active workflows",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO ),

            #! stops the given workflow execution instance given its ID
            /** On errors, an exception is thrown
            @param id the execution instance ID of the workflow execution instance to stop
            @return a string confirming that the workflow is stopping
            @throw INVALID-WORKFLOW-EXECUTION-ID invalid workflow execution ID
            @throw STOP-ERROR workflow is already stopping; cannot stop workflow if called from within the workflow to be stopped

            @note
            - the @ref ostop "ostop" command provides a user-friendly command-line interface to this method
              */
            "omq.system.stop-workflow-instance" : (
                "code" : string sub (hash c, softint id) {
                    # workflow access is checked in Control::stopWorkflowInstance()
                    if (Qorus.control.stopWorkflowInstance(c, id))
                        throw "INVALID-WORKFLOW-EXECUTION-ID", sprintf("there is no workflow with execution ID %n", id);

                    return sprintf("workflow execution instance with ID %d has been stopped", id);
                },
                "params"   : "integer: workflow exec id",
                "help"     : "stops the given workflow execution instance",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! stops all instances of the given workflow
            /** On errors, an exception is thrown
            @param name the name of the workflow to stop
            @param version the optional version of the workflow to stop; if this parameter is not passed, then all versions of the given workflow are stopped
            @return a string describing the number of workflows being stopped
            @throw PARAMETER-ERROR no instances of the given workflow are running

            @note
            - the @ref ostop "ostop" command provides a user-friendly command-line interface to this method
            - also aliased by omq.system.stop()
            */
            "omq.system.stop-workflow" : (
                "code" : string sub (hash c, string name, *string version) {
                    string dname = name + "/" + (exists version ? version : "*");

                    int stopped;
                    # workflow access is checked in Control::stopWorkflow()
                    if (!(stopped = Qorus.control.stopWorkflow(c, name, version)))
                        throw "PARAMETER-ERROR", sprintf("no instances of workflow %s are running", dname);

                    return sprintf("%d instance%s of %s %s been stopped", stopped,
                                   stopped != 1 ? "s" : "", dname,
                                   stopped != 1 ? "have" : "has");
                },
                "alias"    : "omq.system.stop",
                "params"   : "list: 1:string:name, [2:string:version]",
                "help"     : "stops all instances of the workflow given",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Sets the options given in the hash on the running workflow identified by the execution ID passed
            /**
                If the workflow has an option list and any of the options are not valid for that workflow, an exception will be thrown,
                however, even if an exception is thrown due to an option error, all other options will still be set.

                @param id the workflow execution ID to set options on
                @param hash option-value pairs

                @return a string confirming that the options have been set

                @throw INVALID-WORKFLOW-EXECUTION-ID invalid workflow execution ID
                @throw WORKFLOW-OPTION-ERROR invalid option for workflow or option cannot be overridden at the workflow level

                @note
                - workflow options are now actually global for the given workflow; this API takes an execution instance ID, but the options are still set against the workflow and not just on the execution instance level (global workflow options were implemented in Qorus 3.0.0)
                - workflow options are persistent (persistent workflow options were implemented in Qorus 3.0.0)

                @since Qorus 3.0.0 workflow options are global and persistent
            */
            "omq.system.set-workflow-option" : (
                "code" : string sub (hash c, softint id, hash hash) {
                    # workflow access is checked in Control::setWorkflowInstanceOption()
                    if (Qorus.control.setWorkflowInstanceOption(c, id, hash))
                        throw "INVALID-WORKFLOW-EXECUTION-ID", sprintf("there is no workflow with execution ID %d", id);

                    return sprintf("options set on workflow with execution ID %d", id);
                },
                "params"   : "list: 1:integer:workflow exec id, 2:hash:option = value",
                "help"     : "sets the value of a particular option or options for a workflow",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Returns options set on the running workflow identified by the execution ID passed
            /**
                Additional optional string arguments giving option names are accepted after the execution ID.  If no additional arguments are passed, then all options set on the workflow are returned, otherwise only the values for the given options are returned.

                When returning individual option values, any option that is not set at the workflow level will be returned with the value system level if the option is a valid system option.

                If the execution instance ID is not valid, then an exception is raised

                @param id the workflow execution ID

                @return a hash of options set for the workflow or NOTHING if no options are set

                @throw INVALID-WORKFLOW-EXECUTION-ID invalid workflow execution ID

                @note
                - workflow options are now actually global for the given workflow; this API takes an execution instance ID, but the options are still set against the workflow and not just on the execution instance level (global workflow options were implemented in Qorus 3.0.0)
                - workflow options are persistent (persistent workflow options were implemented in Qorus 3.0.0)

                @since Qorus 3.0.0 workflow options are global and persistent
              */
            "omq.system.get-workflow-option" : (
                "code" : any sub (hash c, softint id) {
                    # workflow access is checked in Control::getWorkflowInstanceOption()
                    return Qorus.control.getWorkflowInstanceOption(c, id, argv);
                },
                "params"   : "list: 1:integer:workflow exec id, 2:list or string:option names",
                "help"     : "gets the value of a particular option for a workflow",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO ),

            #! Returns all options set on the running workflow identified by the execution ID passed
            /**
                If the execution instance ID is not valid, then an exception is raised

                @param id the workflow execution ID

                @return a hash of options set for the workflow or NOTHING if no options are set

                @throw INVALID-WORKFLOW-EXECUTION-ID invalid workflow execution ID

                @note
                - workflow options are now actually global for the given workflow; this API takes an execution instance ID, but the options are still set against the workflow and not just on the execution instance level (global workflow options were implemented in Qorus 3.0.0)
                - workflow options are persistent (persistent workflow options were implemented in Qorus 3.0.0)

                @since Qorus 3.0.0 workflow options are global and persistent
              */
            "omq.system.get-workflow-options" : (
                "code" : hash sub (hash c, softint id) {
                    # workflow access is checked in Control::getAllWorkflowInstanceOptions()
                    return Qorus.control.getAllWorkflowInstanceOptions(c, id);
                },
                "params"   : "integer: workflow exec id",
                "help"     : "returns all options set for a workflow",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO ),

            #! Deletes the configuration for the specified workflow from the cache
            /**
                If there are any running instances of the affected workflow(s) then the reset will cause the workflow to be
                reloaded from the database on their next iteration.
                @param name the name of the workflow to reset
                @param version the version of the workflow to reset; if no version string is passed, then all versions of the specified workflow are purged from the workflow cache.

                @return a string confirming the workflow(s) deleted from the cache
            */
            "omq.system.reset-workflow" : (
                "code" : string sub (hash c, string name, *string version) {
                    if (exists version) {
                        # workflow access is checked in Control::deleteWorkflowCacheEntry()
                        Qorus.control.deleteWorkflowCacheEntry(c, Qorus.qmm.getWorkflowId(name, version));
                        return sprintf("workflow %s/%s has been deleted from the cache", name, version);
                    }

                    # workflow access is checked in Control::deleteWorkflowCacheEntries()
                    int count = Qorus.control.deleteWorkflowCacheEntries(c, name);
                    return sprintf("%d version%s of workflow %s %s been deleted from the cache", count, count == 1 ? "" : "s",
                                   count == 1 ? "has" : "have", name);
                },
                "params"   : "list: 1:string:name, 2:string:version",
                "help"     : "reloads a cached workflow definition from the Qorus database",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Deletes the configuration for all workflows from the workflow configuration cache
            /**
                If there are any running workflow execution instances then the reset will cause the workflow to be reloaded from the database on their next iteration.

                @return a string confirming the workflow(s) deleted from the cache
            */
            "omq.system.reset-all-workflows" : (
                "code" : string sub (hash c) {
                    # workflow access is checked in Control::deleteAllWorkflowCacheEntries()
                    int count = Qorus.control.deleteAllWorkflowCacheEntries(c).size();
                    return sprintf("%d workflow%s been deleted from the cache", count, count == 1 ? " has" : "s have");
                },
                "params"   : "list: 1:string:name, 2:string:version",
                "help"     : "reloads all cached workflow definitions from the Qorus database",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO),

            #! Replaces the dynamic data for the given workflow order data instance
            /**
                This API call should be used with care as erroneous changes to workflow order data instances can render further workflow processing impossible.
                If the workflow order data instance ID is not valid then an exception is thrown.

                @param wfiid the workflow order data instance id
                @param data the dynamic data to replace

                @returns "OK"
              */
            "omq.system.replace-dynamic-data" : (
                "code" : string sub (hash c, softstring wfiid, *hash data) {
                    # workflow access is checked in SegmentManager::replaceDynamicData()
                    SM.replaceDynamicData(c, wfiid, data);
                    return "OK";
                },
                "params"   : "list: 1:string:workflow_instanceid, 2:hash:dynamic_data",
                "help"     : "replaces the dynamic data for a workflow with a new set of data",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Replaces the static data for the given workflow order data instance
            /**
                This API call should be used with care as erroneous changes to workflow order data instances can render further workflow processing impossible.                       If the workflow order data instance ID is not valid then an exception is thrown

                @param wfiid the workflow order data instance id
                @param data the static data to replace

                @returns "OK"
              */
            "omq.system.replace-static-data" : (
                "code" : string sub (hash c, softstring wfiid, *hash data) {
                    # workflow access is checked in SegmentManager::replaceDynamicData()
                    SM.replaceStaticData(c, wfiid, data);
                    return "OK";
                },
                "params"   : "list: 1:string:workflow_instanceid, 2:hash:static_data",
                "help"     : "replaces the static data for a workflow with a new set of data",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! retries the given workflow order instance
            /**
                In order to make a retry; the workflow order status must be @ref OMQ::StatError, @ref OMQ::StatAsyncWaiting, or OMQ::StatRetry

                @param wfiid the workflow_instanceid to retry

                @return a hash with the following keys:
                - \c steps_updated: (deprecated) always 0 in this version of Qorus
                - \c segments_updated: the number of segments updated
                - \c workflow_updated: always @ref True in this version of Qorus
                - \c workflow_status: always @ref OMQ::StatRetry in this version of Qorus
                - \c cached: @ref True if the workflow data is currently cached

                @throw STATUS-ERROR workflow data does not have @ref OMQ::StatError, @ref OMQ::StatAsyncWaiting, or OMQ::StatRetry status
                @throw SESSION-ERROR cannot change status for workflow data managed by another Qorus instance (foreign session ID)
                @throw RETRY-ERROR invalid workflow instance ID

                @note
                - also aliased by omq.system.retry()

               @see omq.system.retry-workflow-instances()
              */
            "omq.system.retry-workflow-instance" : (
                "code" : hash sub (hash c, softstring wfiid) {
                    # workflow access is checked in SegmentManager::retryWorkflowInstanceExtern()
                    return SM.retryWorkflowInstanceExtern(c, wfiid);
                },
                "alias"    : "omq.system.retry",
                "params"   : "integer: workflow_instance_id",
                "help"     : "sets workflow_instance and all steps/segments with an ERROR status (segments must not be IN-PROGRESS or CANCELED) to RETRY",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! retries the given workflow order instances
            /**
                In order to make a retry; the workflow order status must be @ref OMQ::StatError, @ref OMQ::StatAsyncWaiting, or OMQ::StatRetry

                @param l a list of workflow_instanceids to retry

                @return a hash where the top level key is the workflow_instanceid, and the value is either an exception string (indicating that the operation failed) or a hash with the following keys:
                - \c steps_updated: (deprecated) always 0 in this version of Qorus
                - \c segments_updated: the number of segments updated
                - \c workflow_updated: always @ref True in this version of Qorus
                - \c workflow_status: always @ref OMQ::StatRetry in this version of Qorus
                - \c cached: @ref True if the workflow data is currently cached

                @see omq.system.retry-workflow-instance()

                @since Qorus 2.5.1.p7
            */
            "omq.system.retry-workflow-instances" : (
                "code" : hash sub (hash c, softlist l) {
                    hash h = {};

                    # workflow access is checked in SegmentManager::retryWorkflowInstanceExtern()
                    foreach softstring wfiid in (l) {
                        try {
                            h{wfiid} = SM.retryWorkflowInstanceExtern(c, wfiid);
                        }
                        catch (hash ex) {
                            h{wfiid} = sprintf("%s: %s", ex.err, ex.desc);
                        }
                    }

                    return h;
                },
                "params"   : "list of workflow_instance_ids",
                "help"     : "sets workflow_instance and all steps/segments with an ERROR status (segments must not be IN-PROGRESS or CANCELED) to RETRY",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! cancels the given workflow order data instance or resets a canceled order to the original status
            /**
                If the cancel argument is @ref True (or missing) it changes a workflow order data instance's status to @ref OMQ::StatCanceled.
                An exception will be thrown if the status is @ref OMQ::StatInProgress.
                No further processing can be done on workflow order data instances with a @ref OMQ::StatCanceled status (unless the workflow instance is recovered back from @ref OMQ::StatCanceled or the status is first updated to @ref OMQ::StatError and then to @ref OMQ::StatRetry).

                @param wfiid the workflow_instanceid of the order to process
                @param cancel if set to @ref False the workflow instance is recovered back to its original status and it is processed, otherwise if @ref True or missing then the order is canceled

                @return a hash with the following key:
                - \c workflow_status: the status of the workflow order

                @throw CANCEL-WORKFLOW-ERROR invalid status, foreign session id, missing original status, uncancel operation already in progress

                @note
                - also aliased by omq.system.cancel()

                @see omq.system.cancel-workflow-instances()
             */
            "omq.system.cancel-workflow-instance" : (
                "code" : hash sub (hash c, softint wfiid, any cancel) {
                    # workflow access is checked in SegmentManager::cancelWorkflowInstance()
                    return SM.cancelWorkflowInstance(c, wfiid, boolean(exists cancel ? parse_boolean(cancel) : True));
                },
                "alias"    : "omq.system.cancel",
                "params"   : "integer: workflow_instance_id, boolean: True for cancel (default - used without argument), False for restore",
                "help"     : "sets a workflow instance with status ERROR, RETRY, ASYNC-WAITING, BLOCKED, WAITING, or EVENT-WAITING to CANCELED",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! cancels the given workflow order data instance or resets a canceled order to the original status
            /**
                If the cancel argument is set to @ref True (or missing) it changes a workflow order data instance's status to @ref OMQ::StatCanceled.
                An exception will be thrown if the status is @ref OMQ::StatInProgress.
                No further processing can be done on workflow order data instances with a @ref OMQ::StatCanceled status (unless the workflow instance is recovered back from @ref OMQ::StatCanceled or the status is first updated to @ref OMQ::StatError and then to @ref OMQ::StatRetry).
                If the cancel argument is set to @ref False the workflow instance is recovered back to its original status and it is processed.

                @param ih a hash where each key is the workflow_instanceid to cancel or uncancel, and the value is the cancel status (boolean @ref True means cancel or @ref False means uncancel)

                @return a hash where the top-level key is the workflow_instanceid, and each value is either an exception string (indicating that the operation for that workflow_instanceid failed) or a hash with the following key:
                - \c workflow_status: the status of the workflow order

                @throw CANCEL-WORKFLOW-ERROR invalid status, foreign session id, missing original status, uncancel operation already in progress

                @see omq.system.cancel-workflow-instance()

                @since Qorus 2.5.1.p7
            */
            "omq.system.cancel-workflow-instances" : (
                "code" : hash sub (hash c, hash ih) {
                    hash h = {};

                    # workflow access is checked in SegmentManager::cancelWorkflowInstance()
                    foreach softstring wfiid in (keys ih) {
                        bool cancel = parse_boolean(ih{wfiid});
                        try {
                            h{wfiid} = SM.cancelWorkflowInstance(c, wfiid, cancel);
                        }
                        catch (hash ex) {
                            h{wfiid} = sprintf("%s: %s", ex.err, ex.desc);
                        }
                    }

                    return h;
                },
                "params"   : "integer: workflow_instance_id, boolean: True for cancel (default - used without argument), False for restore",
                "help"     : "sets a workflow instance with status ERROR, RETRY, ASYNC-WAITING, BLOCKED, WAITING, or EVENT-WAITING to CANCELED",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! sets or removes the scheduled date for a workflow order data instance
            /** Sets or removes the scheduled date for a workflow order data instance, which means that the
            workflow order data will not be processed before the scheduled date and time.

            The workflow order data must normally have status @ref OMQ::StatReady or @ref OMQ::StatScheduled to be rescheduled, however also workflows with @ref OMQ::StatCanceled and @ref OMQ::StatBlocked statuses can be rescheduled if their original status is @ref OMQ::StatReady or @ref OMQ::StatScheduled.

            @param wfiid the workflow order instance ID
            @param scheduled the scheduled date or NOTHING to clear the scheduled date
            @return \c "OK"
            @throw INVALID-WORKFLOW-INSTANCE invalid workflow instance ID
            @throw SESSION-ERROR cannot reschedule workflow data owned by a foreign session
            @throw WORKFLOW-STATUS-ERROR only workflows with status @ref OMQ::StatReady or @ref OMQ::StatScheduled or blocked or canceled workflows with original status @ref OMQ::StatReady or @ref OMQ::StatScheduled can be rescheduled
            @throw RESCHEDULE-ERROR reschedule failed because workflow order data started processing while the request was being processed

            @note
            - also aliased by omq.system.reschedule()

            @since Qorus 2.6.0

            @see omq.system.reschedule-orders()
              */
            "omq.system.reschedule-order" : (
                "code" : string sub (hash c, softint wfiid, *softdate scheduled) {
                    # workflow access is checked in SegmentManager::rescheduleWorkflowExtern()
                    SM.rescheduleWorkflowExtern(c, wfiid, scheduled);
                    return "OK";
                },
                "alias"    : "omq.system.reschedule",
                "params"   : "integer: workflow_instance_id, NOTHING or date for rescheduling",
                "help"     : "reschedules a workflow order with READY status to be processed at a later date",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! sets or removes the scheduled date for a list of workflow order data instances
            /** Sets or removes the scheduled date for a list of workflow order data instance, which means that the
            workflow order data will not be processed before the scheduled date and time if the scheduled date is set.
            If the scheduled date is cleared, it means that the order can be processed at any time.

            The workflow order data must normally have status @ref OMQ::StatReady or @ref OMQ::StatScheduled to be rescheduled, however also workflows with @ref OMQ::StatCanceled and @ref OMQ::StatBlocked statuses can be rescheduled if their original status is @ref OMQ::StatReady or @ref OMQ::StatScheduled.

            @param ih a hash where the keys are workflow_instanceids to process and the value is either a scheduled date or \c NOTHING, indicating that the scheduled date should be cleared from the order
            @return a hash where the top-level keys are workflow_instanceids and the value is either an exception string (indicating that the operation failed for that order) or a constant string \c "OK"
            @since Qorus 2.6.0
            @see omq.system.reschedule-order()
              */
            "omq.system.reschedule-orders" : (
                "code" : hash sub (hash c, hash ih) {
                    hash h = {};

                    # workflow access is checked in SegmentManager::rescheduleWorkflowExtern()
                    foreach softstring wfiid in (keys ih) {
                        try {
                            if (exists ih{wfiid} && ih{wfiid}.typeCode() != NT_DATE)
                                ih{wfiid} = date(ih{wfiid});
                            if (ih{wfiid} < now())
                                throw "SCHEDULED-DATE-ERROR", sprintf("cannot reschedule order with a date in the past (%n)", ih{wfiid});
                            SM.rescheduleWorkflowExtern(c, wfiid, ih{wfiid});
                            h{wfiid} = "OK";
                        }
                        catch (hash ex) {
                            h{wfiid} = sprintf("%s: %s", ex.err, ex.desc);
                        }
                    }

                    return h;
                },
                "params"   : "hash of workflow_instance_ids, value = NOTHING or date for rescheduling",
                "help"     : "reschedules a workflow order with READY status to be processed at a later date",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! changes the priority for an existing workflow order data instance
            /** The workflow order data must not have status @ref OMQ::StatComplete
            @param wfiid the workflow order instance ID
            @param priority the new order priority from 0 - 999; priority 0 is the highest; 999 is the lowest
            @return \c "OK"
            @throw INVALID-WORKFLOW-INSTANCE invalid workflow instance ID
            @throw SESSION-ERROR cannot reschedule workflow data owned by a foreign session
            @throw WORKFLOW-STATUS-ERROR workflows with status @ref OMQ::StatComplete cannot have their priority changed

            @note
            - also aliased by omq.system.reprioritize()

            @since Qorus 2.6.0

            @see omq.system.reprioritize-orders()
              */
            "omq.system.reprioritize-order" : (
                "code" : string sub (hash c, softint wfiid, softint priority) {
                    # workflow access is checked in SegmentManager::reprioritizeWorkflowExtern()
                    SM.reprioritizeWorkflowExtern(c, wfiid, priority);
                    return "OK";
                },
                "alias"    : "omq.system.reprioritize",
                "params"   : "int: workflow_instance_id, int: priority (0-999)",
                "help"     : "change the order priority a for an existing order",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! changes the priority for a list of workflow order data instances
            /** The workflow order data must not have status @ref OMQ::StatComplete
            @param ih a hash where the keys are workflow_instanceids to process and the value is an integer giving the new order priority from 0 - 999; priority 0 is the highest; 999 is the lowest
            @return a hash where the top-level keys are workflow_instanceids and the value is either an exception string (indicating that the operation failed for that order) or a constant string \c "OK"
            @since Qorus 2.6.0
            @see omq.system.reprioritize-order()
              */
            "omq.system.reprioritize-orders" : (
                "code" : hash sub (hash c, hash ih) {
                    hash h = {};

                    # workflow access is checked in SegmentManager::rescheduleWorkflowExtern()
                    foreach softstring wfiid in (keys ih) {
                        try {
                            if (exists ih{wfiid} && ih{wfiid}.typeCode() != NT_DATE)
                                ih{wfiid} = date(ih{wfiid});
                            if (ih{wfiid} < now())
                                throw "SCHEDULED-DATE-ERROR", sprintf("cannot reschedule order with a date in the past (%n)", ih{wfiid});
                            SM.reprioritizeWorkflowExtern(c, wfiid, ih{wfiid});
                            h{wfiid} = "OK";
                        }
                        catch (hash ex) {
                            h{wfiid} = sprintf("%s: %s", ex.err, ex.desc);
                        }
                    }

                    return h;
                },
                "params"   : "hash of workflow_instance_ids, value = new priority (0 - 999)",
                "help"     : "updates the priority for multiple workflow orders",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! block the given workflow order data instance or resets a blocked order to the original status
            /**
                If the block argument set to @ref True (or missing) it changes a workflow order data instance's status to @ref OMQ::StatBlocked.
                An exception will be thrown if the status is @ref OMQ::StatInProgress.
                No further processing can be done on workflow order data instances with a @ref OMQ::StatBlocked status (unless the workflow instance is recovered back from @ref OMQ::StatBlocked or the status is first updated to @ref OMQ::StatError and then to @ref OMQ::StatRetry).
                If the blocked argument is set to @ref False the workflow instance is recovered back to its original status and it is processed.

                @param wfiid the workflow order data instance ID
                @param block if missing or evaluates to @ref True, then the order is blocked, if @ref False then the order is unblocked

                @return a hash with the following key:
                - \c workflow_status: the status of the workflow order

                @throw BLOCK-WORKFLOW-ERROR invalid status, foreign session id, missing original status, unblock operation already in progress

                @note
                - also aliased by omq.system.block()

                @see omq.system.block-workflow-instances()

                @since Qorus 2.5.0
              */
            "omq.system.block-workflow-instance" : (
                "code" : hash sub (hash c, softint wfiid, any block) {
                    # workflow access is checked in SegmentManager::blockWorkflowInstance()
                    return SM.blockWorkflowInstance(c, string(wfiid), boolean(exists block ? parse_boolean(block) : True));
                },
                "alias"    : "omq.system.block",
                "params"   : "integer: workflow_instance_id, boolean: True for block (default - used without argument), False for unblock",
                "help"     : "sets a workflow instance with status ERROR, RETRY, ASYNC-WAITING, CANCELED, WAITING, or EVENT-WAITING to BLOCKED",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! block or restore the list of workflow order data instances
            /**
                If the block argument is set to @ref True it changes a workflow order data instance's status to @ref OMQ::StatBlocked, otherwise orders with a @ref OMQ::StatBlocked status are restored to their original status.
                An exception will be thrown if the status is @ref OMQ::StatInProgress.
                No further processing can be done on workflow order data instances with a @ref OMQ::StatBlocked status (unless the workflow instance is recovered back from @ref OMQ::StatBlocked or the status is first updated to @ref OMQ::StatError and then to @ref OMQ::StatRetry).
                If the blocked argument is set to @ref False the workflow instance is recovered back to its original status and it is processed.

                @param ih a hash where each key is the workflow_instanceid to block or unblock, and the value is the block status (boolean @ref True means block or @ref False means unblock)

                @return a hash where the top-level key is the workflow_instanceid, and each value is either an exception string (indicating that the operation for that workflow_instanceid failed) or a hash with the following key:
                - \c workflow_status: the status of the workflow order

                @since Qorus 2.5.1.p7

                @see omq.system.block-workflow-instance()
            */
            "omq.system.block-workflow-instances" : (
                "code" : hash sub (hash c, hash ih) {
                    hash h = {};

                    # workflow access is checked in SegmentManager::blockWorkflowInstance()
                    foreach softstring wfiid in (keys ih) {
                        bool block = parse_boolean(ih{wfiid});
                        try {
                            h{wfiid} = SM.blockWorkflowInstance(c, wfiid, block);
                        }
                        catch (hash ex) {
                            h{wfiid} = sprintf("%s: %s", ex.err, ex.desc);
                        }
                    }

                    return h;
                },
                "params"   : "hash: keys are workflow_instance_ids, values are block action: boolean: True for block, False for unblock",
                "help"     : "sets a workflow instance with status ERROR, RETRY, ASYNC-WAITING, CANCELED, WAITING, or EVENT-WAITING to BLOCKED",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Changes a workflow order data instance's status to @ref OMQ::StatError, as long as the starting status is @ref OMQ::StatRetry, @ref OMQ::StatCanceled, @ref OMQ::StatBlocked, or @ref OMQ::StatAsyncWaiting
            /** If the status is any other status, an exception will be thrown.
            To set a workflow order data instance with a @ref OMQ::StatWaiting status to @ref OMQ::StatError, set the child workflows to @ref OMQ::StatError first and the parent workflow's status will be updated automatically.
            When setting a workflow order from @ref OMQ::StatCanceled to @ref OMQ::StatError, outstanding events will be queued and the associated queued event keys will be present in the return value.
            @param wfiid the workflow order data instance ID
            @return a hash with the following keys:
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

            @note
            - also aliased by omq.system.set-error()

            @see omq.system.set-workflow-instance-error()
              */
            "omq.system.set-workflow-instance-error" : (
                "code" : hash sub (hash c, softint wfiid) {
                    # workflow access is checked in SegmentManager::setWorkflowInstanceError()
                    return SM.setWorkflowInstanceError(c, wfiid);
                },
                "alias"    : "omq.system.set-error",
                "params"   : "integer: workflow_instance_id",
                "category" : "workflow",
                "help"     : "sets a workflow instance with status RETRY, ASYNC-WAITING, or CANCELED to ERROR (+ all associated segments)",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Changes a list of workflow order data instances' statuses to @ref OMQ::StatError, as long as the starting status is @ref OMQ::StatRetry, @ref OMQ::StatCanceled, @ref OMQ::StatBlocked, or @ref OMQ::StatAsyncWaiting
            /** If the status is any other status, an exception will be thrown.
            To set a workflow order data instance with a @ref OMQ::StatWaiting status to @ref OMQ::StatError, set the child workflows to @ref OMQ::StatError first and the parent workflow's status will be updated automatically.
            When setting a workflow order from @ref OMQ::StatCanceled to @ref OMQ::StatError, outstanding events will be queued and the associated queued event keys will be present in the return value.
            @param l a list of workflow order data instance IDs to set to @ref OMQ::StatError
            @return a hash where the top-level keys are workflow_instanceids and the value is either an exception string (indicating that the operation failed for that workflow instance ID) or a hash with the following keys:
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
            @since Qorus 2.5.1.p7
            @see omq.system.set-workflow-instance-error()
              */
            "omq.system.set-workflow-instances-error" : (
                "code" : hash sub (hash c, softlist l) {
                    hash h = {};

                    # workflow access is checked in SegmentManager::setWorkflowInstanceError()
                    foreach softstring wfiid in (l) {
                        try {
                            h{wfiid} = SM.setWorkflowInstanceError(c, wfiid);
                        }
                        catch (hash ex) {
                            h{wfiid} = sprintf("%s: %s", ex.err, ex.desc);
                        }
                    }

                    return h;
                },
                "params"   : "integer: workflow_instance_id",
                "category" : "workflow",
                "help"     : "sets a workflow instance with status RETRY, ASYNC-WAITING, or CANCELED to ERROR (+ all associated segments)",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Skips execution of a step in a workflow
            /** Sometimes, for reasons outside of a workflow's control, execution for a given step must be skipped, but the rest of the workflow's logic should be executed.  This call allows Qorus to continue executing a workflow order data instance after skipping the given step.  Only steps with @ref OMQ::StatError, @ref OMQ::StatRetry, @ref OMQ::StatEventWaiting, or @ref OMQ::StatAsyncWaiting can be skipped.  Subworkflow steps with any status cannot be skipped; the child workflow must be corrected instead.

            Note that this method will also queue internal events for asynchronous steps, and will trigger a retry of the workflow for all other steps to ensure that the workflow is immediately reprocessed.

            If several steps should be retried, use omq.system.skip-step-without-retry() on every step except the last one to be retried, as this function will trigger a retry of the entire workflow order data instance.
            @param wfiid the workflow order data instance ID
            @param stepid the step ID
            @param ind the step index for array steps
            @throw SKIP-STEP-ERROR step is a subworkflow step; step has not been executed in the given workflow order instance; the given workflow instance ID does not exist
            @throw STEP-STATUS-ERROR step status does not allow it to be skipped (ex: IN-PROGRESS, COMPLETE)
            @throw SESSION-ERROR workflow order instance belongs to another Qorus session
              */
            "omq.system.skip-step" : (
                "code" : nothing sub (hash c, softstring wfiid, softstring stepid, softint ind = 0) {
                    # workflow access is checked in SegmentManager::skipStep()
                    SM.skipStep(c, wfiid, stepid, ind);
                },
                "params"   : "integer: workflow_instance_id, integer: stepid, integer: ind",
                "help"     : "skips execution of a step and marks it automatically as COMPLETE; executes an immediate workflow instance retry with non-async steps",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Skips execution of a step in a workflow without initiating an immediate retry
            /** Sometimes, for reasons outside of a workflow's control, execution for a given step must be skipped, but the rest of the workflow's logic should be executed.  This call allows Qorus to continue executing a workflow order data instance after skipping the given step.  Only steps with @ref OMQ::StatError, @ref OMQ::StatRetry, @ref OMQ::StatEventWaiting, or @ref OMQ::StatAsyncWaiting can be skipped.  Subworkflow steps with any status cannot be skipped; the child workflow must be corrected instead.

            Note that this method will also queue internal events for asynchronous steps.

            If several steps should be retried, execute this method on every step except the last one to be retried, as this function will trigger a retry of the entire workflow order data instance.  Execute omq.system.skip-step() on the final step to also trigger a retry of the workflow order data after the skipo is marked to be skipped.
            @param wfiid the workflow order data instance ID
            @param stepid the step ID
            @param ind the step index for array steps

            @throw SKIP-STEP-ERROR step is a subworkflow step; step has not been executed in the given workflow order instance; the given workflow instance ID does not exist
            @throw STEP-STATUS-ERROR step status does not allow it to be skipped (ex: IN-PROGRESS, COMPLETE)
            @throw SESSION-ERROR workflow order instance belongs to another Qorus session
              */
            "omq.system.skip-step-without-retry" : (
                "code" : nothing sub (hash c, softint wfiid, softint stepid, softint ind = 0) {
                    # workflow access is checked in SegmentManager::skipStepWithoutRetry()
                    SM.skipStepWithoutRetry(c, wfiid, stepid, ind);
                },
                "params"   : "integer: workflow_instance_id, integer: stepid, integer: ind",
                "help"     : "skips execution of a step and marks it automatically as COMPLETE; does not execute an immediate workflow instance retry with non-async steps",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Sets or clears additional info for the given workflow order data instance
            /** @deprecated This function is present for backwards-compatibility and uses @ref order_instance_notes

                If a key is present in the hash, but has no value, then the associated value is cleared; no change is made for keys not present in the hash

                @param wfiid the workflow instance id
                @param h a hash with the following keys:
                - \c op_username: the username of the operator working on the order
                - \c op_comment: notes about processing the order

                @since Qorus 2.5.0
              */
            "omq.system.set-order-info": (
                "code" : nothing sub (hash c, softstring wfiid, hash h) {
                    SM.setOrderInstanceNote(c, wfiid, h);
                },
                "params"   : "workflow_instanceid and a hash with info values",
                "help"     : "Set the addional information for order instance (workflow instance); 1st arg must be a workflow instance id, 2nd hash with keys op_username and/or op_comment.  Data for the given key is cleared when the key is present but the value is missing (NOTHING) or NULL",
                "category" : "obsolete",
                "logopt"   : LoggerLevel::INFO ),

            #! Gets additional info for the given workflow order data instance
            /** @param wfiid the workflow instance id

                @return a hash with the following keys:
                - \c op_username: the username of the operator working on the order
                - \c op_comment: notes about processing the order

                @since Qorus 2.5.0

                @deprecated This function is present for backwards-compatibility and uses @ref order_instance_notes
            */
            "omq.system.get-order-info": (
                "code": hash sub (hash c, softstring wfiid) {
                    list ret =  SM.getOrderInstanceNotes(wfiid, 1);
                    return elements ret ? ret[0] : {};
                },
                "params"   : "Workflow instance id",
                "help"     : "Returns a hash with order_instance additional information",
                "category" : "obsolete",
                "logopt"   : LoggerLevel::INFO,
            ),

            #! Add new @ref order_instance_notes
            /**
                Some additional information are attached automatically - username, date of creation etc.
                @param wfiid the workflow_instanceid of the workflow order to update
                @param notestr string, a text note

                @since Qorus 3.0.2
              */
            "omq.system.set-order-note" : (
                "code" : nothing sub (hash c, softstring wfiid, string notestr) {
                    SM.setOrderInstanceNote(c, wfiid, ("note" : notestr) );
                },
                "params"   : "workflow_instanceid and a string with note",
                "help"     : "Set the addional information for order instance (workflow instance); 1st arg must be a workflow instance id, 2nd is a string with comment/note",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO ),


            #! Gets @ref order_instance_notes
            /**
                @param wfiid the workflow instance id
                @param count an optional limit-count of returned notes

                @return a hash with the notes. See @ref order_instance_notes

                @since Qorus 3.0.2
              */
            "omq.system.order-notes" : (
                "code" : list sub (hash c, softstring wfiid, *softint count) {
                    list ret =  SM.getOrderInstanceNotes(wfiid, count);
                    return ret;
                },
                "params"   : "Workflow instance id; optional count of notes",
                "help"     : "Returns a list of notes hash.",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO ),


            #! Posts a workflow synchronization event with the event type name and key value
            /**
                Note that this API is not checked against the @ref rbacgroups membership of the caller, because a
                synchronization event could be accessed by multiple workflows.

                @param eventtype the event type name
                @param eventkey the event key in the event type queue to post

                @throw UNKNOWN-EVENT unknown event type name

                @see
                - @ref eventsteps
                - @ref post_sync_event()

                @since Qorus 2.6.0
              */
            "omq.system.post-event" : (
                "code" : nothing sub (hash c, softstring eventtype, softstring eventkey) {
                    # lookup event type id
                    *hash info = Qorus.qmm.rLookupEvent(eventtype);
                    if (!info)
                        throw "UNKOWN-EVENT", sprintf("cannot post event %y on unknown event type %y", eventkey, eventtype);

                    SM.postEvent(info.workflow_event_typeid, eventkey);
                },
                "params"   : "event type name, event key",
                "help"     : "posts a workflow synchronization event",
                "category" : "workflow",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Returns a hash with runtime properties specified with \c -D in the Qorus system startup command-line
            /** @return a hash with runtime properties specified with \c -D in the Qorus system startup command-line
                @since Qorus 2.5.0
              */
            "omq.system.runtime-properties" : (
                "code" : hash sub (hash c) {
                    return Qorus.getRuntimeProps();
                },
                "params"   : "no params",
                "help"     : "returns a hash with runtime properties specified with -D on the startup (different from "
                    "system properties)",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            # service functions
            #! returns a list of all services currently loaded or a constant string if the services have not been updated since the optional date argument
            /** @param date an optional date argument; if given and the service cache has not been updated since the date, a constant string is returned instead of a list of services
                @return a list of all services currently loaded or a constant string if the services have not been updated since the optional date argument; if a list is returned, each element is a hash with the following keys:
            - \c type: \c "user" or \c "system"
            - \c name: the name of the service
            - \c version: version of the service
            - \c desc: description of the service
            - \c log: log file path
            - \c serviceid: service ID
            - \c status: @ref OMQ::SSRunning or @ref OMQ::SSLoaded
            - \c threads: number of running threads in the service
            - \c autostart: True of False if the autostart flag is set
            - \c loaded: date/time the service was loaded
            - \c methods: list of hashes for each method with \c name and \c desc keys for each method
            - \c resources: a hash of resources attached to the service (may be NOTHING); each hash key is the unique resource name, and the value of each key is a hash with the following keys:
              - \c type: a string giving the resource type name (ie \c "HttpGlobalHandler", \c "HttpListener", \c "FtpListener", etc)
              - \c desc: a struct description of the resource
              - \c info: a hash with additional, free-form information about the resource
            - \c groups: a list of zero or more strings giving @ref rbacgroups "interface group" names the service is a member of

            @since 2.6.3.p17 added the \c "log" key to the return hash
              */
            "omq.system.list-all-services" : (
                "code"     : any sub (hash c, *date date) {
                    if (exists date && date > services.getUpdated())
                        return "No Changes";
                    # service access is checked in ServiceManager::getCache()
                    return services.getCache(c);
                },
                "params"   : "optional: datetime (returns services if list changed since date passed)",
                "help"     : "returns a list of all cached system and user services",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a list of all system services currently loaded
            /** @return a list of all currently loaded system services; each element is a hash with the following keys:
            - \c type: \c "system"
            - \c name: the name of the service
            - \c version: version of the service
            - \c desc: description of the service
            - \c log: log file path
            - \c serviceid: service ID
            - \c status: @ref OMQ::SSRunning or @ref OMQ::SSLoaded
            - \c threads: number of running threads in the service
            - \c autostart: True of False if the autostart flag is set
            - \c loaded: date/time the service was loaded
            - \c methods: list of hashes for each method with \c name and \c desc keys
            - \c resources: a hash of resources attached to the service (may be NOTHING); each hash key is the unique resource name, and the value of each key is a hash with the following keys:
              - \c type: a string giving the resource type name (ie \c "HttpGlobalHandler", \c "HttpListener", \c "FtpListener", etc)
              - \c desc: a struct description of the resource
              - \c info: a hash with additional, free-form information about the resource

            @since 2.6.3.p17 added the \c "log" key to the return hash
              */
            "omq.system.list-services" : (
                # all users are allowed access to system services
                "code"     : list sub (hash c) {
                    return services.getCache(c, "system");
                },
                "help"     : "returns a list of all cached system services",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! unloads all services currently loaded in memory and reloads them from the database
            /**
                If the calling user has restricted access to user services, only services visible by the current user are reset.

                @return list of hashes of services reset with the following keys:
                - \c type: either \c "system" or \c "user"
                - \c name: name of the service

                @see
                - omq.system.reset-services()
                - omq.system.reset-service()
                - omq.user.reset-services()
                - omq.user.reset-service()

                @since Qorus 2.6.0
              */
            "omq.system.reset-all-services" : (
                "code"     : list sub (hash c) {
                    # service access is checked in ServiceManager::reloadAll()
                    return services.reloadAll(c);
                },
                "help"     : "unloads and reloads all user services from the database",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! unloads all system services currently loaded in memory and reloads them from the database
            /**
                @return list of hashes of services reset with the following keys:
                - \c type: always \c "system" with this call
                - \c name: name of the service

                @see
                - omq.system.reset-all-services()
                - omq.system.reset-service()
                - omq.user.reset-services()
                - omq.user.reset-service()

                @since Qorus 2.6.0
              */
            "omq.system.reset-services" : (
                "code"     : list sub (hash c) {
                    return services.reloadServices(c, "system");
                },
                "help"     : "unloads and reloads all system services from the database",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! unloads a single system service and reloads it from the database
            /** @param name the name of the system service to reset
                @param load if @ref True then the service will be loaded and initialized if it was not already loaded

                @return @ref True if the service was already loaded before this call, @ref False if not

                @see
                - omq.system.reset-all-services()
                - omq.system.reset-service()
                - omq.user.reset-services()
                - omq.user.reset-service()

                @since Qorus 2.6.0
              */
            "omq.system.reset-service" : (
                "code"     : bool sub (hash c, string name, bool load = False) {
                    return services.reloadService(c, "system", name, load);
                },
                "help"     : "unloads and reloads a single system service from the database",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! calls a system service method and returns the result
            /** The service is loaded and started if necessary
            @return the result of calling the system service method
              */
            "omq.system.service.[servicename].[method]" : (
                "name"     : "^omq\.system\.service\..*",
                "code" : any sub (hash c) {
                    string service = substr(c.method, 19);
                    int t = index(service, ".");
                    if (t == -1)
                        throw "SERVICE-ERROR", "no method name given";

                    string method = substr(service, t + 1);
                    service = substr(service, 0, t);

                    # all users are allowed access to system services
                    return omqservice.system{service}.externalMethodGateArgs(method, argv);
                },
                "params"   : "depends on service",
                "help"     : "calls a system service",
                "logopt"   : LoggerLevel::INFO ),

            #! Unloads the named system service from the system
            /** If the service is running, it is first stopped.  Additionally, any outstanding method calls must return before the service can be unloaded.
            @param name the name of the system service to unload
            @param version the version of the service to unload; normally this parameter should not be given; only one version of a service can be loaded at a time and giving the wrong version string will cause an exception to be thrown
            @return "OK"
            @note does not delete any data from the system database schema; only unloads the service from memory
            @throw SERVICE-NOT-LOADED this exception is thrown when the service is not loaded
              */
            "omq.system.delete-service" : (
                "code" : string sub (hash c, string name, *string version) {
                    # all users are allowed access to system services
                    services.unloadService("system", name, version);
                    return "OK";
                },
                "params"   : "list: 1:string:name [2:string:version]",
                "help"     : "deletes a system service so it will be reloaded on next access",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Sets the autostart status of the given system service
            /** @param name the name of the system service
                @param stat the autostart status for the service (parsed with parse_boolean())
                @return "OK"
              */
            "omq.system.set-service-autostart" : (
                "code" : string sub (hash c, string name, softstring stat) {
                    # all users are allowed access to system services
                    services.setAutostartStatus("SYSTEM", name, parse_boolean(stat));
                    return "OK";
                },
                "params"   : "list: 1:string:name 2:boolean:status",
                "help"     : "sets the autostart status on a system service",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! returns the autostart status of the given system service
            /** @param name the name of the system service
                @return the autostart status
              */
            "omq.system.get-service-autostart" : (
                "code"     : bool sub (hash c, string name) {
                    # all users are allowed access to system services
                    return services.getAutostartStatus("SYSTEM", name);
                },
                "text"     : "omq.system.get-service-autostart",
                "params"   : "string:name",
                "help"     : "retrieves the autostart status for a system service",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! Sets the options given in the hash on the given service
            /** Options set override the system options of the same name.  Only system options valid for services may be set.
                The service is loaded and initialized if not already loaded.
                If an exception is thrown due to an option error, all other options will still be set.
                @param name the name of the system service to set options on
                @param hash option-value pairs
                @return "OK"
                @throw SERVICE-ERROR the given service cannot be loaded (unknown or error initializing the service)
                @throw SERVICE-OPTION-ERROR invalid option
            */
            "omq.system.set-service-options" : (
                "code" : string sub (hash<auto> c, string name, hash hash) {
                    # service access is checked in ServiceManager::setServiceOption()
                    services.setServiceOptions(c, "system", name, hash);

                    return "OK";
                },
                "params"   : "list: string:service name, 2:hash:option = value",
                "help"     : "sets the value of a particular option or options for a service",
                "category" : "service",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Returns options set on the given system service; the service must be already loaded or an exception is raised
            /** If no arguments are passed, then all service-level options are returned, otherwise only the values for the given options are returned.
                If the given option is not overridden on the service level, then the value of the system option is returned.
                If the service is not already loaded is not valid, then an exception is raised.
                @param name the service name
                @return a single value if only a single option is requested, a hash of options if nore than one option is requested; note that the value for the option returned may by NOTHING if the given option is not set at the service level
                @throw SERVICE-ERROR the given service is not loaded
              */
            "omq.system.get-service-options" : (
                "code" : any sub (hash c, string name) {
                    # workflow access is checked in ServiceManager::getServiceOptions()
                    return services.getServiceOptions(c, "system", name, argv);
                },
                "params"   : "list: string: service name, 2:list or string:option names",
                "help"     : "gets the value of a particular option for a service",
                "category" : "service",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a list of all user services currently loaded
            /** @return a list of all currently loaded user services; each element is a hash with the following keys:
                - \c type: \c "user"
                - \c name: the name of the service
                - \c version: version of the service
                - \c desc: description of the service
                - \c log: log file path
                - \c serviceid: service ID
                - \c status: @ref OMQ::SSRunning or @ref OMQ::SSLoaded
                - \c threads: number of running threads in the service
                - \c autostart: True of False if the autostart flag is set
                - \c loaded: date/time the service was loaded
                - \c methods: list of hashes for each method with \c name and \c desc keys
                - \c resources: a hash of resources attached to the service (may be NOTHING); each hash key is the unique resource name, and the value of each key is a hash with the following keys:
                - \c type: a string giving the resource type name (ie \c "HttpGlobalHandler", \c "HttpListener", \c "FtpListener", etc)
                - \c desc: a struct description of the resource
                - \c info: a hash with additional, free-form information about the resource
                - \c groups: a list of @ref rbacgroups "interface group" names that this service is a member of

                @since 2.6.3.p17 added the \c "log" key to the return hash
              */
            "omq.user.list-services" :  (
                # service access is checked in ServiceManager::getCache()
                "code"     : list sub (hash c) {
                    return services.getCache(c, "user");
                },
                "text"     : "omq.user.list-services",
                "help"     : "returns a list of all cached user services",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! unloads all user services currently loaded in memory and reloads those services from the database
            /**
                If the calling user has restricted access to user services, only services visible by the current user are reset.

                @return list of hashes of services reset with the following keys:
                - \c type: always \c "user" with this call
                - \c name: name of the service

                @see
                - omq.system.reset-all-services()
                - omq.system.reset-services()

                @since Qorus 2.6.0
              */
            "omq.user.reset-services" : (
                "code"     : list sub (hash c) {
                    # service access is checked in ServiceManager::reloadServices()
                    return services.reloadServices(c, "user");
                },
                "help"     : "unloads and reloads all user services from the database",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! unloads a single user service and reloads it from the database
            /** @param name the name of the user service to reset
                @param load if @ref True then the service will be loaded and initialized if it was not already loaded

                @return @ref True if the service was already loaded before this call, @ref False if not

                @see
                - omq.system.reset-all-services()
                - omq.system.reset-services()
                - omq.system.reset-service()
                - omq.user.reset-services()

                @since Qorus 2.6.0
              */
            "omq.user.reset-service" : (
                "code"     : bool sub (hash c, string name, bool load = False) {
                    return services.reloadService(c, "user", name, load);
                },
                "help"     : "unloads and reloads a single user service from the database",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! calls a user service method and returns the result
            /**
                The service is loaded and started if necessary

                @return the result of calling the user service method

                @throw SERVICE-ERROR invalid method call; missing method name
              */
            "omq.user.service.[servicename].[method]" : (
                "name"     : "^omq\.user\.service\..*",
                "code"     : any sub (hash c) {
                    string service = substr(c.method, 17);
                    int t = index(service, ".");
                    if (t == -1)
                        throw "SERVICE-ERROR", "no method name given";

                    string method = substr(service, t + 1);
                    service = substr(service, 0, t);

                    return omqservice.user{service}.externalMethodGateArgs(method, argv);
                },
                "params"   : "depends on service",
                "help"     : "calls a user service",
                "logopt"   : LoggerLevel::INFO ),

            #! Unloads the named user service from the system
            /** If the service is running, it is first stopped.  Additionally, any outstanding method calls must return before the service can be unloaded.
            @param name the name of the user service to unload
            @param version the version of the service to unload; normally this parameter should not be given; only one version of a service can be loaded at a time and giving the wrong version string will cause an exception to be thrown
            @return "OK"
            @note does not delete any data from the system database schema; only unloads the service from memory
            @throw SERVICE-NOT-LOADED this exception is thrown when the service is not loaded
              */
            "omq.user.delete-service" : (
                "code" : string sub (hash c, string name, *string version) {

                    services.unloadService("user", name, version);
                    return "OK";
                },
                "params"   : "list: 1:string:name [2:string:version]",
                "help"     : "deletes a user service so it will be reloaded on next access",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Sets the autostart status of the given user service
            /**
                @param name the name of the user service
                @param stat the autostart status for the service (parsed with parse_boolean())

                @return "OK"
              */
            "omq.user.set-service-autostart" : (
                "code"     : string sub (hash c, string name, softstring stat) {
                    services.setAutostartStatus("USER", name, parse_boolean(stat));
                    return "OK";
                },
                "params"   : "list: 1:string:name 2:boolean:status",
                "help"     : "sets the autostart status on a user service",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! returns the autostart status of the given user service
            /**
                @param name the name of the user service

                @return the autostart status
              */
            "omq.user.get-service-autostart" : (
                "code"     : bool sub (hash c, string name) {
                    return services.getAutostartStatus("USER", name);
                },
                "text"     : "omq.user.get-service-autostart",
                "params"   : "string:name",
                "help"     : "retrieves the autostart status for a user service",
                "category" : "service access and control",
                "logopt"   : LoggerLevel::INFO ),

            #! Sets the options given in the hash on the given service
            /** Options set override the user options of the same name.  Only system options valid for services may be set.
            The service is loaded and initialized if not already loaded.
            If an exception is thrown due to an option error, all other options will still be set.
            @param name the name of the user service to set options on
            @param hash option-value pairs
            @return "OK"
            @throw SERVICE-ERROR the given service cannot be loaded (unknown or error initializing the service)
            @throw SERVICE-OPTION-ERROR invalid option
            */
            "omq.user.set-service-options" : (
                "code" : string sub (hash c, string name, hash hash) {
                    # service access is checked in ServiceManager::setServiceOption()
                    services.setServiceOptions(c, "user", name, hash);

                    return "OK";
                },
                "params"   : "list: string:service name, 2:hash:option = value",
                "help"     : "sets the value of a particular option or options for a service",
                "category" : "service",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Returns options set on the given unsert service; the service must be already loaded or an exception is raised
            /** If no arguments are passed, then all options are returned, otherwise only the values for the given options are returned.
            If the given option is not overridden on the service level, then the value of the system option is returned.
            If the service is not already loaded is not valid, then an exception is raised
            @param name the service name
            @return a single value if only a single option is requested, a hash of options if nore than one option is requested; note that the value for the option returned may by NOTHING if the given option is not set at the service level
            @throw SERVICE-ERROR the given service is not loaded
              */
            "omq.user.get-service-options" : (
                "code" : any sub (hash c, string name) {
                    # workflow access is checked in ServiceManager::getServiceOptions()
                    return services.getServiceOptions(c, "user", name, argv);
                },
                "params"   : "list: string: service name, 2:list or string:option names",
                "help"     : "gets the value of a particular option for a service",
                "category" : "service",
                "logopt"   : LoggerLevel::INFO ),

            # RBAC functions (users, permissions, roles)
            #! Reloads the all RBAC information (users, permissions, roles, groups) from the system schema
            /**
                Useful for updating Qorus after updating RBAC information with the offline @ref user-tool "user-tool" program

                @return "OK"
              */
            "omq.system.reload-rbac" : (
                "code" : string sub (hash c) {
                    Qorus.rbac.reload();
                    return "OK";
                },
                "text"     : "omq.system.reload-rbac",
                "help"     : "reloads RBAC information from the database",
                "category" : "role based access control",
                "logopt"   : LoggerLevel::INFO ),

            # misc functions
            #! Rotates all system log files
            /**
                The number of old log files kept is controlled by system option @ref max-log-files

                @return "OK"
              */
            "omq.system.rotate-log-files" : (
                "code" : string sub (hash c) {
                    Qorus.rotateLogFiles(c);

                    olog(LoggerLevel::INFO, "log files rotated");

                    return "OK";
                },
                "help"     : "rotates all log files",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            #! Returns a constant "OK" string
            /**
                Useful for checking that the system is up and running
                @return "OK"
              */
            "omq.system.ping" : (
                "code" : string sub (hash c) { return "OK"; },
                "help"     : "response shows that the instance is alive",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a constant string "admin"
            /** @deprecated This function is present for backwards-compatibility and no longer performs any useful function now that the RBAC framework is in place
                @return "admin"
              */
            "omq.system.authenticate" : (
                "code" : string sub (hash c) { return "admin"; },
                "help"     : "returns a constant 'admin': do not use; OBSOLETE",
                "category" : "obsolete",
                "logopt"   : LoggerLevel::INFO ),

            #! Returns a hash giving the list of the new events and the last event ID generated by the system
            /**
                A required argument must be supplied giving the minimum event ID to return; an optional argument may be passed giving a timeout in milliseconds to wait for new events.  This API is suitable for unconditional event polling.

                @param min_id the minimum event ID to return; events will only be returned with an event ID at least as large as this value
                @param timeout_ms a optional timeout in milliseconds; if this value is not present or zero then the function returns immediately

                @return a hash with the following keys:
                - \c lastid: the highest existing event ID in the system at the time the results were returned
                - \c events: a list of event hashes; this key will not be present if there are no events available
                - \c shutdown: if this key is returned, it means the system is shutting down

                @see
                - @ref eventhash "Event Hash Description" for the description of the event hash elements in the event list returned.
                - @ref eventinfo "Event Information Descriptions" for a description of the event-specific \c info hash value in the event hash

                @since Qorus 2.0.2

                @bug these service methods are not filtered for the calling user's @ref rbacgroups membership when called externally
              */
            "omq.system.wait-for-events" : (
                "code" : hash sub (hash c, softint min_id, *timeout timeout_ms) { return Qorus.events.getEvents(min_id, timeout_ms); },
                "params"   : "last event number, [timeout in ms]",
                "help"     : "waits for events",
                "category" : "event",
                "logopt"   : LoggerLevel::INFO ),

            #! return system events that meet any of the given criteria and none of the optional "and not" criteria
            /**
                @param min_id the minimum event ID to return; no event wil be returned that has an event ID less than this; the first event ID is always 1 (if min_id <= 1 then all events are returned that meet the given criteria)
                @param criteria this argument is the criteria list for “logical or” comparisons to be applied to the events.  If a system event matches any of the criteria hashes in the first argument, then it is included in the resulting list, subject to processing by the optional fourth argument.  To match a criteria hash in the second argument with this API call, all of the criteria keys in each hash must match, therefore, to get pure “logical or” behavior the caller must specify only one hash key in each criteria hash; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
                @param timeout_ms optional timeout waiting for events; if not present or 0; the function returns immediately
                @param and_not this argument is an optional criteria list allowing the resulting event list to be filtered; if any event selected by the second argument matches all criteria hashes in the criteria hashes passed as the third argument, then it is filtered out of the resulting list.  Note that the fourth argument, if present, is processed with inverted logic compared to the second argument; for a criteria hash to match, any of the criteria given as hash keys in a criteria hash can match, however, all criteria hashes must match for the filter to operate.  Therefore, to get pure “logical and” filtering the caller must specify only one hash key per hash in the list making up the fourth argument; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
                @param nfilt this argument is an optional criteria list which will filter out elements matched by the above rules; if any event matched by the above rules then matches all the hash values in any of the elements of this list, then it's filtered out of the result list

                @return a hash with the following keys:
                - \c lastid: the last event ID at the time the function returns
                - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
                - \c shutdown: if this key is returned, it means the system is shutting down

                @throw GET-EVENTS-OR-ERROR empty or missing filter value
                @throw GET-EVENTS-ERROR non-hash criteria element passed in event filter
                @throw INVALID-CRITERIA-CODE invalid criteria code found in event filter

                @see
                - @ref eventhash "Event Hash Description" for the description of the event hash elements in the event list returned.
                - @ref eventinfo "Event Information Descriptions" for a description of the event-specific \c info hash value in the event hash

                @since Qorus 2.0.2, Qorus 3.0 added the \a nfilt argument

                @bug these service methods are not filtered for the calling user's @ref rbacgroups membership when called externally
            */
            "omq.system.wait-for-events-or" : (
                "code" : hash sub (hash c, softint min_id, *softlist criteria, *timeout timeout_ms, *softlist and_not, *softlist nfilt) { return Qorus.events.getEventsOr(min_id, criteria, timeout_ms, and_not, nfilt); },
                "params"   : "last event number, list of OR criteria hashes, [timeout in ms], [list of AND NOT criteria hashes], [AND NOT...]",
                "help"     : "waits for events and returns all events matching at least one of the criteria passed, if any AND NOT lists of criteria hashes are passed, will filter out any events matching all of the criteria in any of the AND NOT list elements",
                "category" : "event",
                "logopt"   : LoggerLevel::INFO ),

            #! return system events that meet all of the given criteria or none of the optional "or not" criteria
            /**
                @param min_id the minimum event ID to return; no event wil be returned that has an event ID less than this; the first event ID is always 1 (if min_id <= 1 then all events are returned that meet the given criteria)
                @param criteria this argument is the criteria list for “logical and” comparisons to be applied to the events.  If an event matches all of the criteria hashes in the first argument, then it is included in the resulting list.  To match a criteria hash in the second argument with this API call, any of the criteria keys in a single hash can match, therefore, to get pure “logical and” behavior, the caller must specify only one hash key in each criteria hash; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
                @param timeout_ms optional timeout waiting for events; if not present or 0; the function returns immediately
                @param or_not this argument is an optional criteria list that can augment the list returned with negative matches.  If this argument is present and any element in the system's event list does not match any of the criteria hashes in the third argument, then it is also included in the returned event list.  Note that the fourth argument, if present, is processed with inverted logic compared to the second argument; for a single criteria hash to match, all of the criteria given as hash keys in the criteria hash must match, therefore, to get pure inverted “logical or” logic, the caller must specify only one hash key per hash in the list making up the fourth argument; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
                @param nfilt this argument is an optional criteria list which will filter out elements matched by the above rules; if any event matched by the above rules then matches all the hash values in any of the elements of this list, then it's filtered out of the result list

                @return a hash with the following keys:
                - \c lastid: the last event ID at the time the function returns
                - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
                - \c shutdown: if this key is returned, it means the system is shutting down

                @throw GET-EVENTS-AND-ERROR empty or missing filter value
                @throw GET-EVENTS-ERROR non-hash criteria element passed in event filter
                @throw INVALID-CRITERIA-CODE invalid criteria code found in event filter

                @see
                - @ref eventhash "Event Hash Description" for the description of the event hash elements in the event list returned.
                - @ref eventinfo "Event Information Descriptions" for a description of the event-specific \c info hash value in the event hash

                @since Qorus 2.0.2, Qorus 3.0 added the \a nfilt argument

                @bug these service methods are not filtered for the calling user's @ref rbacgroups membership when called externally
            */
            "omq.system.wait-for-events-and" : (
                "code" : hash sub (hash c, softint min_id, *softlist criteria, *timeout timeout_ms, *softlist or_not, *softlist nfilt) { return Qorus.events.getEventsAnd(min_id, criteria, timeout_ms, or_not, nfilt); },
                "params"   : "last event number, list of AND criteria hashes, [timeout in ms], [list of OR NOT criteria hashes]",
                "help"     : "waits for events and returns all events matching all of the criteria passed, if the OR NOT list of criteria hashes is passed, will also include any events not matching any of the criteria in that list",
                "category" : "event",
                "logopt"   : LoggerLevel::INFO ),

            #! returns the last system event ID generated
            /** @return the last system event ID generated
              */
            "omq.system.get-last-event-id" : (
                "code" : int sub (hash c) { return Qorus.events.getCurrentEventID() - 1; },
                "help"     : "returns the last event ID",
                "category" : "event",
                "logopt"   : LoggerLevel::INFO ),

            #! returns the last system events
            /**
                @param count the maximum number of events to return

                @return a hash with the following keys:
                - \c lastid: the last event ID at the time the function returns
                - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
                - \c shutdown: if this key is returned, it means the system is shutting down

                @see
                - @ref eventhash "Event Hash Description" for the description of the event hash elements in the event list returned.
                - @ref eventinfo "Event Information Descriptions" for a description of the event-specific \c info hash value in the event hash

                @since Qorus 2.0.2

                @bug these service methods are not filtered for the calling user's @ref rbacgroups membership when called externally
            */
            "omq.system.get-last-events" : (
                "code" : hash sub (hash c, softint count) { return Qorus.events.getLastEvents(count); },
                "params"   : "maximum number of events",
                "help"     : "returns a list of the last events",
                "category" : "event",
                "logopt"   : LoggerLevel::INFO ),

            #! gets the last system events that meet any of the filter criteria and none of the "and_not" criteria, if present
            /**
                Returns a hash giving the list of the most recent system events matching a filter and the last event ID generated by the system.   Events in the event list returned must match the criteria passed as the second argument; if any of the criteria match an event, then it is included in the return list, unless a third criteria list argument is also passed, which allows for removing elements from the list returned.
                @param count the maximum number of events to return; if this argument is 0, then the size of the returned list is only limited by the number of events in the system that match the filter(s) passed.
                @param filter this argument gives the criteria list for “logical or” comparisons to be applied to the events.  If an event matches any of the criteria hashes in the first argument, then it is included in the resulting list, subject to processing by the optional third argument.  To match a criteria hash in the second argument with this API call, all of the criteria keys in each hash must match, therefore, to get pure “logical or” behavior the caller must specify only one hash key in each criteria hash; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
                @param and_not this argument is an optional criteria list allowing the resulting event list to be filtered; if any event selected by the second argument matches all criteria hashes in the criteria hashes passed as the third argument, then it is filtered out of the resulting list.  Note that the third argument, if present, is processed with inverted logic compared to the second argument; for a criteria hash to match, any of the criteria given as hash keys in a criteria hash can match, however, all criteria hashes must match for the filter to operate.  Therefore, to get pure “logical and” filtering the caller must specify only one hash key per hash in the list making up the third argument; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
                @param nfilt this argument is an optional criteria list which will filter out elements matched by the above rules; if any event matched by the above rules then matches all the hash values in any of the elements of this list, then it's filtered out of the result list

                @return a hash with the following keys:
                - \c lastid: the last event ID at the time the function returns
                - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
                - \c shutdown: if this key is returned, it means the system is shutting down

                @throw GET-LAST-EVENTS-OR-ERROR empty or missing filter value
                @throw GET-EVENTS-ERROR non-hash criteria element passed in event filter
                @throw INVALID-CRITERIA-CODE invalid criteria code found in event filter

                @see
                - @ref eventhash "Event Hash Description" for the description of the event hash elements in the event list returned.
                - @ref eventinfo "Event Information Descriptions" for a description of the event-specific \c info hash value in the event hash

                @since Qorus 2.0.2, Qorus 3.0 added the \a nfilt argument

                @bug these service methods are not filtered for the calling user's @ref rbacgroups membership when called externally
            */
            "omq.system.get-last-events-or" : (
                "code" : hash sub (hash c, softint count, *softlist filter, *softlist and_not, *softlist nfilt) { return Qorus.events.getLastEventsOr(count, filter, and_not, nfilt); },
                "params"   : "maximum number of events, list of criteria hashes, [list of AND NOT criteria hashes], [AND NOT...]",
                "help"     : "returns a list of the last events meeting any of the criteria passed, if any AND NOT lists of criteria hashes are passed, will filter out any events matching all of the criteria in any of the AND NOT list elements",
                "category" : "event",
                "logopt"   : LoggerLevel::INFO ),

            #! gets the last system events that meet all of the filter criteria or none of the "or_not" criteria, if present
            /**
                @param count the maximum number of events to return; if this argument is 0, then the size of the returned list is only limited by the number of events in the system that match the filter(s) passed.
                @param filter this argument is the criteria list for “logical and” comparisons to be applied to the events.  If an event matches all of the criteria hashes in the first argument, then it is included in the resulting list.  To match a criteria hash in the second argument with this API call, any of the criteria keys in a single hash can match, therefore, to get pure “logical and” behavior, the caller must specify only one hash key in each criteria hash; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
                @param or_not this argument is an optional criteria list that can augment the list returned with negative matches.  If this argument is present and any element in the system's event list does not match any of the criteria hashes in the third argument, then it is also included in the returned event list.  Note that the third argument, if present, is processed with inverted logic compared to the second argument; for a single criteria hash to match, all of the criteria given as hash keys in the criteria hash must match, therefore, to get pure inverted “logical or” logic, the caller must specify only one hash key per hash in the list making up the third argument; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
                @param nfilt this argument is an optional criteria list which will filter out elements matched by the above rules; if any event matched by the above rules then matches all the hash values in any of the elements of this list, then it's filtered out of the result list

                @return a hash with the following keys:
                - \c lastid: the last event ID at the time the function returns
                - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
                - \c shutdown: if this key is returned, it means the system is shutting down

                @throw GET-LAST-EVENTS-AND-ERROR empty or missing filter value
                @throw GET-EVENTS-ERROR non-hash criteria element passed in event filter
                @throw INVALID-CRITERIA-CODE invalid criteria code found in event filter

                @see
                - @ref eventhash "Event Hash Description" for the description of the event hash elements in the event list returned.
                - @ref eventinfo "Event Information Descriptions" for a description of the event-specific \c info hash value in the event hash

                @since Qorus 2.0.2, Qorus 3.0 added the \a nfilt argument

                @bug these service methods are not filtered for the calling user's @ref rbacgroups membership when called externally
            */
            "omq.system.get-last-events-and" : (
                "code" : hash sub (hash c, softint count, *softlist filter, *softlist or_not, *softlist nfilt) { return Qorus.events.getLastEventsAnd(count, filter, or_not, nfilt); },
                "params"   : "maximum number of events, list of criteria hashes, [list of OR NOT criteria hashes]",
                "help"     : "returns a list of the last events meeting all of the criteria passed, if the OR NOT list of criteria hashes is passed, will also include any events not matching any of the criteria in that list",
                "category" : "event",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a hash of listener information for the HTTP server
            /**
                @return a hash where the keys are the listener IDs and the values are hashes with the following keys:
                - \c proto: http or https
                - \c bind: the bind address of the listener

                @since Qorus 2.6.0
              */
            "omq.system.get-listeners" :(
                "code" : hash sub (hash c) { return Qorus.httpServer.getListeners(); },
                "help"     : "returns a list of listener hashes with the following keys: id, bind, proto",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            #! stops the listener from the bind address
            /**
                @param name the name or bind address of the listener to stop

                @throw INVALID-LISTENER-ERROR invalid name or bind address, cannot stop last listener

                @see omq.system.stop-listener-id()

                @since Qorus 2.6.0

                @note
                - the last listener cannot be stopped; at least one listener must be running at all times
             */
            "omq.system.stop-listener" : (
                "code" : nothing sub (hash c, softstring name) {
                    # we call ServiceManager::stopListenerName() to handle stopping service listeners gracefully
                    services.stopListenerName(c, name);
                },
                "params"   : "string|int: bind address",
                "help"     : "stops a listener based on its bind address",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS),

            #! stops the listener from listener ID
            /**
                @param id the ID listener to stop

                @throw INVALID-LISTENER-ERROR invalid listener ID, cannot stop last listener

                @see omq.system.stop-listener()

                @since Qorus 2.6.0

                @note
                - the last listener cannot be stopped; at least one listener must be running at all times
              */
            "omq.system.stop-listener-id" : (
                "code" : nothing sub (hash c, softint id) {
                    # we call ServiceManager::stopListenerId() to handle stopping service listeners gracefully
                    services.stopListenerId(c, id);
                },
                "params"   : "int: listener ID",
                "help"     : "stops a listener based on its listener ID",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! starts a new HTTP listener; listeners will be started on all possible bind addresses in case more than one interface is resolved from the bind address given
            /**
                @param bind the bind address of the new listener; listeners will be started on all possible bind addresses in case more than one interface is resolved from the bind address given
                @param cert_file the file name of the X.509 certificate in PEM format (only for HTTPS listeners)
                @param key_file the file name of the private key for the X.509 certificate in PEM format (only for HTTPS listeners)

                @return a list of hashes for each listener started, each hash having the following keys (note that for UNIX domain socket listeners the \c hostname, \c hostname_desc, and \c port keys will not be present):
                - \c hostname: the hostname of the interface
                - \c hostname_desc: a descriptive string for the hostname including the address family (ex: \c "ipv6[localhost]")
                - \c address: the address of the listener (i.e. \c "192.168.30.4", etc)
                - \c address_desc: a descriptive string for the hostname including the address family (ex: \c "ipv6[::1]")
                - \c port: the port number
                - \c family: an integer giving the address family (\c AF_INET, \c AF_INET6, \c AF_UNIX, etc)
                - \c familystr: a string describing the address family (ex: \c "ipv6")
                - \c proto: either \c "http" or \c "https"
                - \c id: the Qorus ID of the listener
                - \c bind: a string giving the bind address used (ex: \c "127.0.0.1:8001")

                @see omq.system.stop-listener()

                @since Qorus 2.6.0
            */
            "omq.system.start-listeners" : (
                "code" : list sub (hash c, softstring bind, *string cert_file, *string key_file) {
                    return Qorus.httpServer.addListeners(bind, http_get_listener_options(NOTHING, NOTHING, cert_file, key_file));
                },
                "params"   : "string: bind address, [string: X.509 certificate file, [string: certificate's private key file]]",
                "help"     : "starts one or more HTTP listeners",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            # group functions
            #! Enables or disables an interface group
            /**
                Workflows, services, and jobs in disabled groups are stopped immediately if loaded/running/active.
                When a group is enabled, then any services with the autostart flag are immediately started if the group was previously disabled and the service is not a member of any other disabled group.

                @param name the name of the group
                @param enabled the new status of the group

                @throw GROUP-ERROR group does not exist

                @since Qorus 2.6.0
              */
            "omq.system.group.set-status" : (
                "code" : nothing sub (hash c, string name, softstring enabled) {
                    if (parse_boolean(enabled))
                        Qorus.rbac.enableGroup(name);
                    else
                        Qorus.rbac.disableGroup(name);
                },
                "params"   : "string: group name, bool: enabled",
                "help"     : "enables or disables a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Creates an interface group
            /**
                Workflows, services, and jobs in disabled groups are stopped immediately if loaded/running.
                When a group is enabled, then any services with the autostart flag set and any jobs with the active flag set are immediately started if the group was previously disabled and the service/job is not a member of any other disabled group.

                @param name the name of the group
                @param desc the description of the group
                @param svcids a list of integer service IDs
                @param wfids a list of integer workflow IDs
                @param enabled the new status of the group (to be parsed with parse_boolean())
                @param jobids a list of integer job IDs
                @param mapperids a list of integer mapper IDs
                @param vmapids a list of integer value map IDs

                @return the group ID of the new group

                @throw GROUP-ERROR group already exists, invalid service, workflow, or job ID

                @since Qorus 2.6.0
              */
            "omq.system.group.create" : (
                "code" : int sub (hash c, string name, string desc, softlist svcids, softlist wfids, softstring enabled = True, softlist jobids = (), softlist mapperids = (), softlist vmapids = ()) {
                    return Qorus.rbac.createGroup(name, desc, svcids, wfids, jobids, mapperids, vmapids, NOTHING, NOTHING, parse_boolean(enabled));
                },
                "params"   : "string: group name, string: description, [list: serviceids, [list: workflowids, [bool: enabled = True, [list: jobids, [list: mapperids, [list: vmapids]]]]]]",
                "help"     : "creates a new interface group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Modifies an existing interface group in the database and in the RBAC cache
            /**
                Changes to groups are effected immediately; for example, if a workflow, service, or job is added to a disabled group, the any corresponding running objects are immediately stopped; or if a job is removed from a disabled group, then it is immediately started, etc
                @param group the group to update
                @param hash a hash giving the information to update, valid keys are as follows; at least one of the following keys must be present:
                - \c desc: (string) the new description of the group
                - \c workflows: (list of strings or a single string) the list of workflow names to include in the group; the new list will replace the current list unless the workflow names are preceded by \c "+" or \c "-", meaning add or remove a workflow, respectively (in which case all workflow names must be preceded by a \c "+" or \c "-"); note that if the key is present and contains an empty list or string then all workflows are removed from the group
                - \c services: (list of strings or a single string) the list of user service names to include in the group; the new list will replace the current list unless the user service names are preceded by \c "+" or \c "-", meaning add or remove a service, respectively (in which case all service names must be preceded by a \c "+" or \c "-"); note that if the key is present and contains an empty list or string then all services are removed from the group
                - \c jobs: (list of strings or a single string) the list of job names to include in the group; the new list will replace the current list unless the job names are preceded by \c "+" or \c "-", meaning add or remove a job, respectively (in which case all job names must be preceded by a \c "+" or \c "-"); note that if the key is present and contains an empty list or string then all jobs are removed from the group
                - \c mappers: (list of strings or a single string) the list of @ref mappers "mapper" names to include in the group; the new list will replace the current list unless the mapper names are preceded by \c "+" or \c "-", meaning add or remove a mapper, respectively (in which case all mapper names must be preceded by a \c "+" or \c "-"); note that if the key is present and contains an empty list or string then all mappers are removed from the group

                - \c vmaps: (list of strings or a single string) the list of @ref value-maps "value map" names to include in the group; the new list will replace the current list unless the value map names are preceded by \c "+" or \c "-", meaning add or remove a value map, respectively (in which case all value map names must be preceded by a \c "+" or \c "-"); note that if the key is present and contains an empty list or string then all value maps are removed from the group

                - \c enabled: (string) this value will be processed by parse_boolean(); enables or disables the group

                @return "OK"

                @since Qorus 2.6.3.p2
              */
            "omq.system.group.update" : (
                "code" : string sub (hash c, string group, hash hash) {
                    Qorus.rbac.updateGroup(group, hash);
                    return "OK";
                },
                "params"   : "group name, hash=(valid keys: 'workflows', 'services', 'jobs', 'mappers', 'vmaps', 'desc', 'enabled')",
                "help"     : "updates an existing interface group, replaces or edits values",
                "category" : "role based access control",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS),

            #! Permanently deletes a workflow/service/job group
            /**
                When a disabled group is deleted, then any services with the autostart flag set and any active jobs are immediately started if the group was previously disabled and the service/job is not a member of any other disabled group
                @param name the name of the group

                @throw GROUP-ERROR group does not exist

                @since Qorus 2.6.0
             */
            "omq.system.group.delete" : (
                "code" : nothing sub (hash c, string name) {
                    Qorus.rbac.deleteGroup(name);
                },
                "params"   : "string: group name",
                "help"     : "deletes a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Adds a workflow to a workflow/service/job group from the workflow's name and optional version
            /**
                If a workflow is added to a disabled group, the any instances of the workflow are immediately stopped
                @param name the name of the group
                @param wname the name of the workflow to add
                @param ver the optional version of the workflow to add; if no version string is passed, then all existing versions of the workflow are added

                @throw GROUP-ERROR group or workflow does not exist

                @since Qorus 2.6.0

                @see omq.system.group.update()
              */
            "omq.system.group.add-workflow" : (
                "code" : nothing sub (hash c, string name, string wname, *string ver) {
                    Qorus.rbac.addWorkflow(name, wname, ver);
                },
                "params"   : "string: group name, string: workflow name, [string: version]",
                "help"     : "adds a single workflow or all current versions of a workflow (in case the version parameter is not sent) to a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Adds a service to a workflow/service/job group from the service's name and optional version
            /**
                If a service is added to a disabled group, the any instances of the service are immediately stopped
                @param name the name of the group
                @param sname the name of the service to add
                @param ver the optional version of the service to add; if no version string is passed, then all existing versions of the service are added

                @throw GROUP-ERROR group or service does not exist

                @since Qorus 2.6.0

                @see omq.system.group.update()
              */
            "omq.system.group.add-service" : (
                "code" : nothing sub (hash c, string name, string sname, *string ver) {
                    Qorus.rbac.addService(name, sname, ver);
                },
                "params"   : "string: group name, string: service name, [string: version]",
                "help"     : "adds a particular user service and version or all current versions of a user service (in case the version parameter is not sent) to a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Adds a job to a workflow/service/job group from the job's name
            /** If a job is added to a disabled group and the job is active, then the job is immediately stopped
            @param name the name of the group
            @param jname the name of the job to add

            @throw GROUP-ERROR group or job does not exist
            @since Qorus 2.6.1
            @see omq.system.group.update()
              */
            "omq.system.group.add-job" : (
                "code" : nothing sub (hash c, string name, string jname) {
                    Qorus.rbac.addJob(name, jname);
                },
                "params"   : "string: group name, string: job name",
                "help"     : "adds a particular job to a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Adds one or more workflows to a workflow/service/job group from the workflowids
            /**
                If a workflow is added to a disabled group, the any instances of the workflow are immediately stopped

                @param name the name of the group
                @param ids a list of workflow ids or a single workflow id

                @throw GROUP-ERROR group or workflow does not exist

                @since Qorus 2.6.0

                @see omq.system.group.update()
              */
            "omq.system.group.add-workflow-id" : (
                "code" : nothing sub (hash c, string name, softlist ids) {
                    Qorus.rbac.addWorkflowIDs(name, ids);
                },
                "params"   : "string: group name, int: workflowid",
                "help"     : "adds a workflow to a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Adds one or more services to a workflow/service/job group from the serviceids
            /**
                If services are added to a disabled group, the services are immediately stopped and unloaded
                @param name the name of the group
                @param ids a list of service ids or a single service id

                @throw GROUP-ERROR group or service does not exist

                @since Qorus 2.6.0

                @see omq.system.group.update()
              */
            "omq.system.group.add-service-id" : (
                "code" : nothing sub (hash c, string name, softlist ids) {
                    Qorus.rbac.addServiceIDs(name, ids);
                },
                "params"   : "string: group name, int: serviceid",
                "help"     : "adds a user service to a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Adds one or more jobs to a workflow/service/job group from the jobids
            /**
                If jobs are added to a disabled group, the jobs are immediately stopped
                @param name the name of the group
                @param ids a list of job ids or a single job id

                @throw GROUP-ERROR group or job does not exist

                @since Qorus 2.6.1

                @see omq.system.group.update()
              */
            "omq.system.group.add-job-id" : (
                "code" : nothing sub (hash c, string name, softlist ids) {
                    Qorus.rbac.addJobIDs(name, ids);
                },
                "params"   : "string: group name, int: jobid",
                "help"     : "adds a user job to a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Permanently deletes a workflow from a workflow/service/job group using the workflow's name and optional version
            /**
                No error is raised if an attempt is made to remove workflows from a group that are not in the group

                @param name the name of the group
                @param wname the name of the workflow to delete
                @param ver the optional version of the workflow to delete; if no version string is passed, then all existing versions of the workflow are deleted

                @throw GROUP-ERROR group or workflow does not exist

                @since Qorus 2.6.0

                @see omq.system.group.update()
              */
            "omq.system.group.delete-workflow" : (
                "code" : nothing sub (hash c, string name, string wname, *string ver) {
                    Qorus.rbac.deleteWorkflow(name, wname, ver);
                },
                "params"   : "string: group name, string: workflow name, [string: version]",
                "help"     : "deletes a single workflow or all current versions of a workflow (in case the version parameter is not sent) from a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Permanently deletes a service from a workflow/service/job group using the service's name and optional version
            /** No error is raised if an attempt is made to remove service from a group that are not in the group.
            When services are removed from disabled groups, any services with the autostart flag are immediately started if the group was previously disabled and the service is not a member of any other disabled group.

                @param name the name of the group
                @param sname the name of the service to delete
                @param ver the optional version of the service to delete; if no version string is passed, then all existing versions of the service are deleted

                @throw GROUP-ERROR group or service does not exist

                @since Qorus 2.6.0

                @see omq.system.group.update()
              */
            "omq.system.group.delete-service" : (
                "code" : nothing sub (hash c, string name, string sname, *string ver) {
                    Qorus.rbac.deleteService(name, sname, ver);
                },
                "params"   : "string: group name, string: service name, [string: version]",
                "help"     : "deletes a user service or all current versions of a service (in case the version parameter is not sent) from a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Permanently deletes a job from an @ref rbacgroups "interface group" using the job's name
            /**
                No error is raised if an attempt is made to remove jobs from a group that are not in the group
                @param name the name of the group
                @param jname the name of the job to delete

                @throw GROUP-ERROR group or job does not exist

                @since Qorus 2.6.1.p2

                @see omq.system.group.update()
              */
            "omq.system.group.delete-job" : (
                "code" : nothing sub (hash c, string name, string jname) {
                    Qorus.rbac.deleteJob(name, jname);
                },
                "params"   : "string: group name, string: job name",
                "help"     : "deletes a single job from an interface group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Permanently deletes one or more workflows from a workflow/service/job group using workflow ids
            /**
                @param name the name of the group
                @param ids a list of workflow ids or a single workflow id

                @throw GROUP-ERROR group or workflow does not exist

                @since Qorus 2.6.0

                @see omq.system.group.update()
              */
            "omq.system.group.delete-workflow-id" : (
                "code" : nothing sub (hash c, string name, softlist ids) {
                    Qorus.rbac.deleteWorkflowIDs(name, ids);
                },
                "params"   : "string: group name, int: workflowid",
                "help"     : "deletes a workflow from a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Permanently deletes one or more services to a workflow/service/job group from the service ids
            /**
                When services are removed from disabled groups, any services with the autostart flag are immediately started if the group was previously disabled and the service is not a member of any other disabled group.

                @param name the name of the group
                @param ids a list of service ids or a single service id

                @throw GROUP-ERROR group or service does not exist

                @since Qorus 2.6.0

                @see omq.system.group.update()
              */
            "omq.system.group.delete-service-id" : (
                "code" : nothing sub (hash c, string name, softlist ids) {
                    Qorus.rbac.deleteServiceIDs(name, ids);
                },
                "params"   : "string: group name, int: serviceid",
                "help"     : "deletes a user service from a workflow/service/job group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Permanently deletes one or more jobs from an @ref rbacgroups "interface group" using job ids
            /**
                @param name the name of the group
                @param ids a list of job ids or a single job id

                @throw GROUP-ERROR group or job does not exist

                @since Qorus 2.6.1.p2

                @see omq.system.group.update()
              */
            "omq.system.group.delete-job-id" : (
                "code" : nothing sub (hash c, string name, softlist ids) {
                    Qorus.rbac.deleteJobIDs(name, ids);
                },
                "params"   : "string: group name, int: jobid",
                "help"     : "deletes a job from an interface group",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Returns information for a group or all groups if no group name argument is passed
            /**
                @param name the optional name of the group to query; if no group name is passed, then information for all groups is returned

                @return if no argument is passed, then the hash is keyed by group names with each value a group information hash, otherwise a group information hash is directly returned with the following keys:
                - \c name: the name of the group
                - \c description: the description of the group
                - \c enabled: @ref True if enabled or @ref False if disabled
                - \c is_default: @ref True if the group is the @ref defaultgroup "DEFAULT" group, in this case the \c workflows, \c services, and \c jobs keys will be assigned to empty lists and the group authorizes access all workflows, services, and jobs
                - \c id: the id of the group
                - \c roles: a list of roles that have the group
                - \c workflows: a list of hashes of workflow information that the group authorizes access to (empty if \c is_default is @ref True, otherwise if \c is_default is @ref False and this list is empty, it means that the group does not authorize access to any workflows); each hash has the following keys:
                    - \c workflowid: the ID of the workflow
                    - \c name: the name of the workflow
                    - \c version: the version of the workflow
                - \c services: a list of hashes of user service information the group authorizes access to (empty if \c is_default is @ref True, otherwise if \c is_default is @ref False and this list is empty, it means that the group does not authorize access to any services); each hash has the following keys:
                    - \c serviceid: the ID of the service
                    - \c type: always \c "user"; it's not possible to restrict access to system services through @ref rbacgroups "interface groups"
                    - \c name: the name of the service
                    - \c version: the version of the service
                    - \c autostart: the autostart flag for the service
                - \c jobs: a list of hashes of job information the group authorizes access to (empty if \c is_default is @ref True, otherwise if \c is_default is @ref False and this list is empty, it means that the group does not authorize access to any jobs); each hash has the following keys:
                    - \c jobid: the ID of the job
                    - \c name: the name of the job
                    - \c version: the version of the job
              */
            "omq.system.group.info" : (
                "code" : hash sub (hash c, *string name) { return Qorus.rbac.getGroupInfo(name); },
                "params"   : "[string: group name]",
                "help"     : "returns all information about a single group or all groups if no argument is passed",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO ),

            # job methods
            #! Returns information on all jobs or a specific job depending on the argument (or lack thereof)
            /**
                @param name the optional name of the job to query; if no job name is passed, then information for all jobs is returned (note that the hash is filtered for jobs not visible to the calling user if the calling user has no role with the @ref defaultgroup "DEFAULT" @ref rbacgroups "interface group"), however, if this argument is passed and no job with this name exists, then a \c JOB-ERROR exception is raised

                @return if no argument is passed, then the hash is keyed by job names with each value a job information hash, otherwise a job information hash is directly returned with the following keys:
                - \c jobid: the metadata jobid of the job type
                - \c name: the job name
                - \c version: the job version
                - \c description: the job description
                - \c trigger: a string describing the timer/trigger for the job
                - [\c job_instanceid]: the id of the job instance (will only have a value if the job is currently executing)
                - [\c last_executed]: the last executed date/time of the job (NOTHING if not yet executed)
                - [\c last_executed_job_instanceid]: the last executed instance id of the job
                - [\c expiry_date]: the expiry date of the job, if any; if this date is present, then the job will not run automatically after this date
                - [\c next]: the next trigger date/time; this key is only included if the job is active
                - \c active: this value will only be @ref True if the job is actually loaded; note that the job can be active in the database but not actually loaded if the job is a member of a disabled @ref rbacgroups "Interface Group", in which case the value of this key will be @ref False
                - \c groups: a list of zero or more strings giving group names the job is a member of

                @throw JOB-ERROR no job with the given name exists
                @throw JOB-ACCESS-ERROR the user does not have the right to access the given job (for more information, see @ref rbacgroups)

                @since Qorus 2.6.1
            */
            "omq.system.job.info" : (
                "code" : hash sub (hash c, *string name) {

                    if (exists name) {
                        return Qorus.jobManager.getInfo(name);
                    }

                    return Qorus.jobManager.getInfo();
                },
                "params"   : "[string: job name]",
                "help"     : "returns all information about a single job or all jobs if no argument is passed",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO ),

            #! Returns information on a specific job by the jobid
            /**
                @param id the jobid of the job to query

                @return a job information hash is returned with the following keys:
                - \c jobid: the metadata jobid of the job type
                - \c name: the job name
                - \c version: the job version
                - \c description: the job description
                - \c trigger: a string describing the timer/trigger for the job
                - [\c job_instanceid]: the id of the job instance (will only have a value if the job is currently executing)
                - [\c last_executed]: the last executed date/time of the job (NOTHING if not yet executed)
                - [\c last_executed_job_instanceid]: the last executed instance id of the job
                - [\c expiry_date]: the expiry date of the job, if any; if this date is present, then the job will not run automatically after this date
                - [\c next]: the next trigger date/time
                - \c active: this value will only be @ref True if the job is actually loaded; note that the job can be active in the database but not actually loaded if the job is a member of a disabled @ref rbacgroups "Interface Group", in which case the value of this key will be @ref False

                @throw JOB-ERROR no job with the given id exists

                @since Qorus 2.6.1
            */
            "omq.system.job.info-id" : (
                "code" : hash sub (hash c, softint id) {
                    return Qorus.jobManager.getInfoID(id);
                },
                "params"   : "int: jobid",
                "help"     : "returns all information about the jobid given (must be active)",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO ),

            #! Returns information on all active jobs visible to the calling user
            /**
                If any active jobs are not accessible to the calling user, then they are filtered from the hash returned.
                @return a hash is keyed by job name; the hash values are job information hashes with the following keys:
                - \c jobid: the metadata jobid of the job type
                - \c name: the job name
                - \c version: the job version
                - \c description: the job description
                - \c trigger: a string describing the timer/trigger for the job
                - [\c job_instanceid]: the id of the job instance (will only have a value if the job is currently executing)
                - [\c last_executed]: the last executed date/time of the job (NOTHING if not yet executed)
                - [\c last_executed_job_instanceid]: the last executed instance id of the job
                - [\c expiry_date]: the expiry date of the job, if any; if this date is present, then the job will not run automatically after this date
                - [\c next]: the next trigger date/time; this key is only included if the job is active
                - \c active: this value is always @ref True because this API only returns information about active jobs

                @since Qorus 2.6.3
            */
            "omq.system.job.list-active" : (
                "code" : hash sub (hash c) { return Qorus.jobManager.getActiveInfo(c.user); },
                "help"     : "returns all information about all active jobs visible to the calling user",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO ),

            #! Runs the given job immediately (regardless of the trigger time) from the job name even if the job is expired, inactive, or dedicated to another instance
            /**
                @param name the name of the job to run

                @return a hash with the following keys:
                - \c job_instanceid: the job_instanceid
                - \c status: the status of the execution of the job

                @throw JOB-ERROR no job with the given name exists

                @since Qorus 2.6.1
            */
            "omq.system.job.run" : (
                "code" : hash sub (hash c, string name) {
                    return Qorus.jobManager.runJobNow(name);
                },
                "params"   : "string: job name",
                "help"     : "returns a hash giving the result of running the job",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Runs the given job immediately (regardless of the trigger time) from the jobid even if the job is expired, inactive, or dedicated to another instance
            /**
            @param id the jobid to run
            @return a hash with the following keys:
            - \c job_instanceid: the job_instanceid
            - \c status: the status of the execution of the job

            @throw JOB-ERROR no job with the given jobid exists

            @since Qorus 2.6.1
            */
            "omq.system.job.run-id" : (
                "code" : hash sub (hash c, softint id) {
                    return Qorus.jobManager.runJobIDNow(id);
                },
                "params"   : "int: jobid",
                "help"     : "returns a hash giving the result of running the job",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Updates the "active" status of a job from the job name; if any errors occur an exception is thrown
            /**
            This API works on all jobs regardless of state; the job does not have to be running or active to be updated.
            Updating a job to active will start the job immediately unless the expiry date is past or the job is a member of a disabled @ref rbacgroups "group".
            Changing a currently-active job to inactive will stop the job immediately.

            @param name the name of the job to update
            @param active the new status of the job; if not present, then True is assumed; note that this parameter is parsed with parse_boolean() so it's safe to pass a boolean, or a string like \c "true" or an integer that will be converted to a boolean value, see parse_boolean() for more information
            @return a string giving a description of the result of the operation

            @throw JOB-ERROR no job with the given name exist

            @since Qorus 2.6.1
            */
            "omq.system.job.set-active": (
                "code" : string sub (hash c, string name, *softstring active) {
                    return Qorus.jobManager.setJobStatus(name, exists active ? parse_boolean(active) : True);
                },
                "params"   : "string: job name, bool: active status",
                "help"     : "returns a string giving the result of the operation",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Updates the "active" status of a job from the job id; if any errors occur an exception is thrown
            /**
            This API works on all jobs regardless of state; the job does not have to be running or active to be updated.
            Updating a job to active will start the job immediately unless the expiry date is past or the job is a member of a disabled @ref rbacgroups "group".
            Changing a currently-active job to inactive will stop the job immediately.

            @param id the jobid of the job to update
            @param active the new status of the job; if not present, then True is assumed; note that this parameter is parsed with parse_boolean() so it's safe to pass a boolean, or a string like \c "true" or an integer that will be converted to a boolean value, see parse_boolean() for more information
            @return a string giving a description of the result of the operation

            @throw JOB-ERROR no job with the given id exists

            @since Qorus 2.6.1
            */
            "omq.system.job.set-active-id": (
                "code" : string sub (hash c, softint id, *softstring active) {
                    return Qorus.jobManager.setJobStatusID(id, exists active ? parse_boolean(active) : True);
                },
                "params"   : "int: jobid, bool: active status",
                "help"     : "returns a string giving the result of the operation",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Updates the expiry date of a job from the job name; if any errors occur an exception is thrown
            /**
            This API works on all jobs regardless of state; the job does not have to be running or active to be updated.
            Removing the expiry date or setting a future expiry date from a job that is not started because it has expired
            will result in the job starting immediately (unless the job is inactive or a member of a disabled @ref rbacgroups "group".
            Setting a past expiry date on a currently-active job will stop the job immediately.

            @param name the name of the job to update
            @param expiry the new expiration date for the job; if this parameter is not present or NOTHING then any expiration date for the job will be removed
            @return a string giving a description of the result of the operation

            @throw JOB-ERROR no job with the given name exists

            @since Qorus 2.6.1
            */
            "omq.system.job.set-expiry": (
                "code" : string sub (hash c, string name, *date expiry) {
                    return Qorus.jobManager.setJobExpiry(name, expiry);
                },
                "params"   : "string: job name, [date: expiration date]",
                "help"     : "returns a string giving the result of the operation",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Updates the expiry date of a job from the job id; if any errors occur an exception is thrown
            /**
            This API works on all jobs regardless of state; the job does not have to be running or active to be updated.
            Removing the expiry date or setting a future expiry date from a job that is not started because it has expired
            will result in the job starting immediately (unless the job is inactive or a member of a disabled @ref rbacgroups "group".
            Setting a past expiry date on a currently-active job will stop the job immediately.

            @param id the jobid to update
            @param expiry the new expiration date for the job; if this parameter is not present or NOTHING then any expiration date for the job will be removed
            @return a string giving a description of the result of the operation

            @throw JOB-ERROR no job with the given id exists

            @since Qorus 2.6.1
            */
            "omq.system.job.set-expiry-id": (
                "code" : string sub (hash c, softint id, *date expiry) {
                    return Qorus.jobManager.setJobExpiryID(id, expiry);
                },
                "params"   : "int: jobid, [date: expiration date]",
                "help"     : "returns a string giving the result of the operation",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Updates a job's schedule from the job name; if any errors occur an exception is thrown
            /**
            This API works on all jobs regardless of state; the job does not have to be running or active to be updated.

            @param name the name of the job to update
            @param schedule a cron-like string giving the job schedule, see @ref job_schedule for information about the format; either this parameter or \c recurring must be present, but not both
            @param recurring a duration in sections for triggering the job; either this parameter or \c schedule must be present, but not both
            @return a string giving a description of the result of the operation

            @throw JOB-SCHEDULE-ERROR both schedule and duration parameters given or neither given
            @throw CRON-ERROR cron schedule cannot be parsed or 0 second duration given
            @throw JOB-ERROR no job with the given name exists

            @since Qorus 2.6.1.p4
            */
            "omq.system.job.schedule": (
                "code" : string sub (hash c, string name, *string schedule, *softint recurring) {
                    return Qorus.jobManager.setJobSchedule(name, schedule, recurring);
                },
                "params"   : "string: job name, *string: cron schedule, *string: duration in seconds",
                "help"     : "returns a string giving the result of the operation",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Updates a job's schedule from the jobid; if any errors occur an exception is thrown
            /**
            This API works on all jobs regardless of state; the job does not have to be running or active to be updated.

            @param id the jobid to update
            @param schedule a cron-like string giving the job schedule, see @ref job_schedule for information about the format; either this parameter or recurring must be present, but not both
            @param recurring a duration in sections for triggering the job; either this parameter or recurring must be present, but not both
            @return a string giving a description of the result of the operation

            @throw JOB-SCHEDULE-ERROR both schedule and duration parameters given or neither given
            @throw CRON-ERROR cron schedule cannot be parsed or 0 second duration given
            @throw JOB-ERROR no job with the given ID exists

            @since Qorus 2.6.1.p4
            */
            "omq.system.job.schedule-id": (
                "code" : string sub (hash c, softint id, *string schedule, *softint recurring) {
                    return Qorus.jobManager.setJobScheduleID(id, schedule, recurring);
                },
                "params"   : "int: jobid, *string: cron schedule, *string: duration in seconds",
                "help"     : "returns a string giving the result of the operation",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Reloads a job from the database from its name; if it's currently running it is stopped and reloaded
            /**
            This API works on all jobs regardless of state; the job does not have to be running or active to be reset.

            @param name the name of the job to reset
            @return a string giving a description of the result of the operation

            @throw JOB-ERROR no job with the given name exists
            @throw API-CALL-ERROR cannot reset a disabled job

            @since Qorus 2.6.1
            */
            "omq.system.job.reset": (
                "code" : string sub (hash c, string name) {
                    return Qorus.jobManager.resetJob(name);
                },
                "params"   : "string: job name",
                "help"     : "returns a string giving the result of the operation",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Reloads a job from the database from its id; if it's currently running it is stopped and reloaded
            /**
            This API works on all jobs regardless of state; the job does not have to be running or active to be reset.

            @param id the jobid to reset
            @return a string giving a description of the result of the operation

            @throw JOB-ERROR no job with the given name exists

            @since Qorus 2.6.1
            */
            "omq.system.job.reset-id": (
                "code" : string sub (hash c, softint id) {
                    return Qorus.jobManager.resetJobID(id);
                },
                "params"   : "int: jobid",
                "help"     : "returns a string giving the result of the operation",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Reloads all jobs from the database; all currently-running jobs are stopped and reloaded
            /**
            @return a string giving a description of the result of the operation

            @since Qorus 2.6.1
            */
            "omq.system.job.reset-all": (
                "code" : string sub (hash c) {
                    return Qorus.jobManager.reset();
                },
                "help"     : "returns a string giving the result of the operation",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),

            #! Sets the options given in the hash on the given job; the job must be active or an exception is raised
            /** Options set override the system options of the same name; only system options valid for jobs may be set.
            If an exception is thrown due to an option error, all other options will still be set.

            @param name the name of the job to set options on
            @param hash option-value pairs

            @return "OK"

            @throw JOB-ERROR no job with the given name is active
            @throw JOB-OPTION-ERROR invalid option

            @since Qorus 2.8.0
            */
            "omq.system.job.set-options" : (
                "code" : string sub (hash c, string name, hash hash) {
                    Qorus.jobManager.setOptions(name, hash);

                    return "OK";
                },
                "params"   : "list: string:job name, 2:hash:option = value",
                "help"     : "sets the value of a particular option or options for an active job",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS,
            ),

            #! Returns options set on the given job; the job must be active or an exception is raised
            /** If no arguments are passed, then all service-level options are returned, otherwise only the values for the given options are returned.
            If the given option is not overridden on the job level, then the value of the system option is returned.
            If the job is not active, then an exception is raised.

            @param name the job name

            @return a single value if only a single option is requested, a hash of options if nore than one option is requested; note that the value for the option returned may by NOTHING if the given option is not set at the job level

            @throw JOB-ERROR no job with the given name is active
            @since Qorus 2.8.0
              */
            "omq.system.job.get-options" : (
                "code" : any sub (hash c, string name) {
                    return Qorus.jobManager.getOptions(name, argv);
                },
                "params"   : "list: string: job name, 2:list or string:option names",
                "help"     : "gets the value of a particular option for a job",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO,
            ),

            #! Sets the options given in the hash on the given job; the job must be active or an exception is raised
            /** Options set override the system options of the same name; only system options valid for jobs may be set.
            If an exception is thrown due to an option error, all other options will still be set.

            @param id the ID of the job to set options on
            @param hash option-value pairs

            @return "OK"

            @throw JOB-ERROR no job with the given name is active
            @throw JOB-OPTION-ERROR invalid option

            @since Qorus 2.8.0
            */
            "omq.system.job.set-options-id" : (
                "code" : string sub (hash c, softint id, hash hash) {
                    Qorus.jobManager.setOptionsID(id, hash);

                    return "OK";
                },
                "params"   : "list: int:job id, 2:hash:option = value",
                "help"     : "sets the value of a particular option or options for an active job",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS,
            ),

            #! Returns options set on the given job; the job must be active or an exception is raised
            /** If no arguments are passed, then all service-level options are returned, otherwise only the values for the given options are returned.
            If the given option is not overridden on the job level, then the value of the system option is returned.
            If the job is not active, then an exception is raised.

            @param id the job ID

            @return a single value if only a single option is requested, a hash of options if nore than one option is requested; note that the value for the option returned may by NOTHING if the given option is not set at the job level

            @throw JOB-ERROR no job with the given name is active

            @since Qorus 2.8.0
              */
            "omq.system.job.get-options-id" : (
                "code" : any sub (hash c, softint id) {
                    return Qorus.jobManager.getOptionsId(id, argv);
                },
                "params"   : "list: int:job id, 2:list or string:option names",
                "help"     : "gets the value of a particular option for a job",
                "category" : "job",
                "logopt"   : LoggerLevel::INFO,
            ),

            #! Refresh helper database snapshots
            /**
            @return a hash giving a result of the operation in the form (snapshot name: result message)

            @since Qorus 2.6.3
            */
            "omq.system.schema.refresh-snapshots": (
                "code" : hash sub (hash c) {
                    return Qorus.refreshSnapshots();
                },
                "help"     : "refreshes system schema's helper snapshots. Use with extreme care. See documentation for more info",
                "category" : "system",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS,
            ),

            # error definition methods
            #! returns global error definition information
            /**
                @param l @ref nothing (meaning return all errors) or a single string (meaning return the global definition for that error string) or a list of strings (meaning return a hash of the requested errors)

                @return nothing if no errors match the arguments or a hash of global error definitions, each key is the error name, and the values are hashes with the following keys:
                - \c error: the name of the error repeated
                - \c description: the description of the error
                - \c severity: the severity of the error (see @ref ErrorSeverityCodes for possible values)
                - \c business_flag: indicates if the error is a business error or a technical error
                - \c retry_flag: indicates if the error should cause the order to get a \c "RETRY" status
                - \c retry_delay_secs: indicates the retry delay in seconds for this error; if not set then the error gets the standard retry period
                - \c type: \c "global", meaning that the error definition is global

                @since Qorus 2.8.0
            */
            "omq.system.get-global-errors": (
                "code": *hash sub (hash c, *softlist l) {
                    return Qorus.EM.getGlobalErrors(l);
                },
                "help": "returns global error definitions",
                "category": "workflow",
                "logopt": LoggerLevel::INFO,
            ),

            #! returns workflow-specific error definition information
            /**
                @param wfid the workflowid of the workflow to query
                @param l nothing (meaning return all workflow-specific errors for this workflow) or a single string (meaning return the definition for that error string that will be used for the given workflow) or a list of strings (meaning return a hash of the requested errors used for the given workflow)

                @return nothing if no errors match the arguments or a hash of error definitions, each key is the error name, and the values are hashes with the following keys:
                - \c error: the name of the error repeated
                - \c description: the description of the error
                - \c severity: the severity of the error (see @ref ErrorSeverityCodes for possible values)
                - \c business_flag: indicates if the error is a business error or a technical error
                - \c retry_flag: indicates if the error should cause the order to get a \c "RETRY" status
                - \c retry_delay_secs: indicates the retry delay in seconds for this error; if not set then the error gets the standard retry period
                - \c type: either \c "workflow", meaning that the error definition is workflow-specific, or \c "global", meaning that the error definition is global

                @since Qorus 2.8.0
            */
            "omq.system.get-workflow-errors": (
                "code": *hash sub (hash c, softint wfid, *softlist l) {
                    return Qorus.EM.getErrors(wfid, l);
                },
                "help": "returns error definitions for the given workflow",
                "category": "workflow",
                "logopt": LoggerLevel::INFO,
            ),

            #! returns all global and workflow-specific error definitions
            /**
            @return a hash with the following keys: \c "global" and \c "workflow"; the \c "global" key is assigned a hash of global error definitions, where each key is the error name and the value of each key is a hash representing the error definition.  The \c "workflow" key is assigned a hash of workflow IDs, each of which is then assigned a hash of error definitions, representing the workflow-specific error definitions.  Each error hash has the following keys:
            - \c error: the name of the error repeated
            - \c description: the description of the error
            - \c severity: the severity of the error (see @ref ErrorSeverityCodes for possible values)
            - \c business_flag: indicates if the error is a business error or a technical error
            - \c status: the status the order should fall in when the error occurs
            - \c retry_delay_secs: indicates the retry delay in seconds for this error; if not set then the error gets the standard retry period

            @since Qorus 2.8.0
            */
            "omq.system.get-all-errors": (
                "code": hash sub (hash c) {
                    return Qorus.EM.getAllErrors(c.user);
                },
                "help": "returns all error definitions",
                "category": "workflow",
                "logopt": LoggerLevel::INFO,
            ),

            #! searches for error definitions at all levels for the given error(s)
            /**
            @param l one or more error strings to search for

            @return a hash keyed by the error name, where each value is a hash with the following optional keys:
            - \c global: an optional hash giving the global error definition (if any)
            - \c workflow: an optional hash of workflow IDs where each value is an error definition

            @since Qorus 2.8.0
            */
            "omq.system.search-errors": (
                "code": *hash sub (hash c, softlist l) {
                    if (!l)
                        return;
                    return Qorus.EM.search(c.user, l);
                },
                "help": "searches for all error definitions at all levels for the given error(s)",
                "category": "workflow",
                "logopt": LoggerLevel::INFO,
            ),

            #! creates or updates a global error
            /** Error definitions are committed internally and also to the database in this method (i.e. all changes are persistent)
            @param eh an error hash with the following keys:
            - \c "error": the name of the error
            - \c "description": the description of the error
            - \c "severity": (optional) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
            - \c "retry_flag": (optional, deprecated) a boolean retry flag value (if not present then @ref False is assumed); this key is deprecated by \c status and is present only for backwards compatibility; at most one of \c retry_flag and \c status must be present; the mapping from \c retry_flag to \c status is @ref True to @ref OMQ::StatRetry and @ref False to @ref OMQ::StatError
            - \c "status" : (optional) the status the order enters when this error appears (@ref OMQ::StatError, @ref OMQ::StatRetry, @ref OMQ::StatCanceled); at most one of \c retry_flag and \c status must be present
            - \c "business_flag": (optional) a boolean business flag value (if not present then @ref False is assumed)
            - \c "retry_delay_secs": (optional) an optional retry value in seconds (only used if \c status is @ref OMQ::StatRetry)

            @return a string giving the result of the operation; one of:
            - \c "UPDATED-GLOBAL": the existing global error was updated
            - \c "CREATED-GLOBAL": a new global error was created
            - \c "UNCHANGED-GLOBAL": the new definition is identical to the old definition

            @throw ERROR-UPDATE-ERROR when the arguments are invalid

            @since Qorus 2.8.0
            */
            "omq.system.update-global-error": (
                "code": string sub (hash c, hash eh) {
                    return Qorus.EM.updateGlobalError(eh);
                },
                "params"   : "hash:(error, description, severity, retry_flag, status, business_flag, retry_delay_secs)",
                "help": "updates or creates a global error definition",
                "category": "workflow",
                "logopt": LoggerLevel::INFO | HttpServer::LP_LOGPARAMS,
            ),

            #! creates or updates a workflow-specific error definition
            /** Error definitions are committed internally and also to the database in this method (i.e. all changes are persistent)
            @param wfid the workflow ID of the workflow to update
            @param eh an error hash with the following keys:
            - \c "error": the name of the error
            - \c "description": the description of the error
            - \c "severity": (optional) a severity code for the error (if not present @ref OMQ::ES_Major is assumed); for possible values see @ref ErrorSeverityCodes
            - \c "retry_flag": (optional, deprecated) a boolean retry flag value (if not present then @ref False is assumed); this key is deprecated by \c status and is present only for backwards compatibility; at most one of \c retry_flag and \c status must be present; the mapping from \c retry_flag to \c status is @ref True to @ref OMQ::StatRetry and @ref False to @ref OMQ::StatError
            - \c "status" : (optional) the status the order enters when this error appears (@ref OMQ::StatError, @ref OMQ::StatRetry, @ref OMQ::StatCanceled); at most one of \c retry_flag and \c status must be present
            - \c "business_flag": (optional) a boolean business flag value (if not present then @ref False is assumed)
            - \c "retry_delay_secs": (optional) an optional retry value in seconds (only used if \c status is @ref OMQ::StatRetry)
            @param forceworkflow if @ref True "True" then error processing will only be made on the workflow level regardless of any global error of the same name

            @return a string giving the result of the operation; one of:
            - \c "UPDATED-WORKFLOW": the existing workflow-specific error was updated
            - \c "CREATED-WORKFLOW": a new workflow-specific error definition was created
            - \c "UNCHANGED-WORKFLOW": the new workflow-specific definition is identical to the old definition
            - \c "CREATED-GLOBAL": a new global error was created
            - \c "UNCHANGED-GLOBAL": the new global definition is identical to the old definition

            @throw ERROR-UPDATE-ERROR when the arguments are invalid

            @since Qorus 2.8.0
            */
            "omq.system.update-workflow-error": (
                "code": string sub (hash c, softint wfid, hash eh, *bool forceworkflow) {
                    return forceworkflow ? Qorus.EM.updateWorkflowError(wfid, eh) : Qorus.EM.updateError(wfid, eh);
                },
                "params": "int:wfid, hash:(error, description, severity, retry_flag, status, business_flag, retry_delay_secs)",
                "help": "creates a global or creates or updates a workflow-specific error definition",
                "category": "workflow",
                "logopt": LoggerLevel::INFO | HttpServer::LP_LOGPARAMS,
            ),

            #! deletes a workflow-specific error so that the global error definition will be used instead
            /**
                Changes are committed internally and also to the database in this method (i.e. all changes are persistent)
                @param wfid the workflow ID of the workflow-specific error to delete
                @param err the name of the error to delete

                @return @ref True if the error was deleted, @ref False if it did not exist

                @since Qorus 2.8.0
            */
            "omq.system.delete-workflow-error": (
                "code": bool sub (hash c, softint wfid, string err) {
                    return Qorus.EM.deleteWorkflowError(wfid, err);
                },
                "params"   : "int: wfid, string: err",
                "help": "deletes a workflow-specific error definition",
                "category": "workflow",
                "logopt": LoggerLevel::INFO | HttpServer::LP_LOGPARAMS,
            ),

            #! deletes all definitions of an error from all workflows and at the global level
            /** Changes are committed internally and also to the database in this method (i.e. all changes are persistent)
            @param err the name of the error to delete

            @return a count of all error definition instances deleted

            @since Qorus 2.8.0
            */
            "omq.system.delete-error": (
                "code": int sub (hash c, string err) {
                    return Qorus.EM.deleteError(c.user, err);
                },
                "params"   : "string: err",
                "help": "deletes a workflow-specific error definition",
                "category": "workflow",
                "logopt": LoggerLevel::INFO | HttpServer::LP_LOGPARAMS,
            ),

            #! reloads all error definitions from the DB
            /**
            @return a hash with the following keys:
            - \c global: gives the number of global error definitions loaded
            - \c workflow: gives the number of all workflow-specific error definitions loaded

            @since Qorus 2.8.0
            */
            "omq.system.reload-errors": (
                "code": hash sub (hash c) {
                    return Qorus.EM.reload();
                },
                "help": "reloads all error definitions from the DB",
                "category": "workflow",
                "logopt": LoggerLevel::INFO,
            ),

            # debugging methods
            #! echos any argument passed
            /** @return echos any argument passed
              */
            "omq.system.debug.echo" : (
                "code" : any sub (hash c) { return argv; },
                "help"     : "echos any arguments passed",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns information about the status of running threads
            /** @return information about the status of running threads
              */
            "omq.system.debug.get-thread-stacks" : (
                "code" : hash sub (hash c) { return get_all_thread_call_stacks(); },
                "help"     : "returns the current execution location of all threads",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns detailed technical data about the workflow order data cache for debugging purposes
            /** @return detailed technical data about the workflow order data cache for debugging purposes
              */
            "omq.system.debug.get-data-cache" : (
                "code" : string sub (hash c) { return SM.getDataCacheAsString(); },
                "help"     : "returns a dump of the internal timed data cache",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns summarized technical data about the workflow order data cache for debugging purposes
            /** @return summarized technical data about the workflow order data cache for debugging purposes
              */
            "omq.system.debug.get-data-cache-summary" : (
                "code" : string sub (hash c) { return SM.getDataCacheSummary(); },
                "help"     : "returns a summary of the internal timed data cache",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns detailed technical data about the segment event cache for debugging purposes
            /** @return detailed technical data about the segment event cache for debugging purposes
              */
            "omq.system.debug.get-segment-cache" : (
                "code" : string sub (hash c) { return SM.getCacheAsString(); },
                "help"     : "returns a dump of the internal segment event cache",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns summarized technical data about the segment event cache for debugging purposes
            /** @return summarized technical data about the segment event cache for debugging purposes
              */
            "omq.system.debug.get-segment-summary" : (
                "code" : string sub (hash c) { return SM.getCacheSummary(); },
                "help"     : "returns a summary of the internal segment event cache",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a description of the workflow queue thread pool
            /** @return a description of the workflow queue thread pool
              */
            "omq.system.debug.get-workflow-queue-status" : (
                "code" : string sub (hash c) { return Qorus.wqtp.getInfo(); },
                "help"     : "returns a summary of the internal workflow queue thread pool processing status",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a description of internal monitoring data structures
            /** @return a description of internal monitoring data structures
              */
            "omq.system.debug.get-mon" : (
                "code" : hash sub (hash c) { return Qorus.connections.dbgInfo(); },
                "help"     : "returns a description of internal monitoring data structures",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns technical data about the segment cache for debugging purposes
            /** @return technical data about the segment cache for debugging purposes
              */
            "omq.system.debug.dump-caches" : (
                "code" : string sub (hash c) { return SM.dumpCaches(); },
                "help"     : "returns the contents of the SegmentManager caches",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns a description of the status of the system DatasourcePool
            /** @return a description of the status of the system DatasourcePool
              */
            "omq.system.debug.dump-system-pool" : (
                "code" : string sub (hash c) { return omqp.toString(); },
                "help"     : "returns a description of the DatasourcePool for the system schema",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns technical data about the execution cache for debugging purposes
            /** @return technical data about the execution cache for debugging purposes
              */
            "omq.system.debug.dump-exec-cache" : (
                "code" : string sub (hash c) { return sprintf("%N", Qorus.control); },
                "help"     : "returns the internal workflow execution instance cache",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

            #! returns technical cache data about an internal workflow entry for debugging purposes
            /** @return technical cache data about an internal workflow entry for debugging purposes
              */
            "omq.system.debug.get-workflow-entry" : (
                "code" : string sub (hash c, softint wfiid) { return sprintf("%N", SM.getWFEntryDebugHash(wfiid)); },
                "help"     : "returns a string describing an internally cached workflow entry",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO ),

           #! sets the debug flag on a cached workflow entry for debugging purposes
            /** @return nothing
              */
            "omq.system.debug.workflow-entry" : (
                "code"    : nothing sub (hash c, softint wfiid, *string flag) { SM.setWFEntryDebug(wfiid, exists flag ? parse_boolean(flag) : True); },
                "help"    : "sets the debug flag on a cached workflow entry for debugging purposes",
                "params"  : "int: workflow_instanceid, [bool: flag]",
                "category": "debug",
                "logopt"  : LoggerLevel::INFO ),

            #! turns system debugging on or off
            /** @param flag turns system debugging on or off
              */
            "omq.system.debug.system" : (
                "code" : nothing sub (hash c, softstring flag) { Qorus.setDebug(parse_boolean(flag)); },
                "params"   : "bool: flag",
                "help"     : "set system debugging flag on or off",
                "category" : "debug",
                "logopt"   : LoggerLevel::INFO | HttpServer::LP_LOGPARAMS ),
            );
    }
}

sub check_workflow_params(reference params) {
    if (!params.name)
        throw "PARAMETER-ERROR", "missing workflow name";

    if (!params.version) {
        *hash wfh = Qorus.qmm.rLookupWorkflow(params.name);
        if (!wfh)
            throw "PARAMETER-ERROR", sprintf("no workflow %y has been cached", params.name);
        params.version = wfh.lastversion;
        params.wfid = wfh.(wfh.lastversion).workflowid;
    }
    else
        params.wfid = Qorus.qmm.getWorkflowId(params.name, params.version);

    if (params.options && params.options.typeCode() != NT_HASH)
        throw "PARAMETER-ERROR", sprintf("workflow options must be given in hash format (option=value), type given: %y", params.options.type());
}
