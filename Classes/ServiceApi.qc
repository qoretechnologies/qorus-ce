# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file ServiceApi.qc the primary Qorus service API

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

public namespace OMQ {
    public namespace UserApi {
        #! Qorus service API namespace
        public namespace Service {}
    }
}

#! primary service API class
/** @note In %Python available as \c svcapi
*/
public class OMQ::UserApi::Service::ServiceApi inherits UserApi {
    public {
        #! keys returned from the \c cx hash in @ref getCallContext() if present
        /** @since Qorus 4.0.3
        */
        const ServiceCallContextKeys = ("socket", "socket-info", "peer-info", "url", "id", "ssl", "user", "client-cert");
    }

    #! registers the current service as a SOAP service and exports its methods that map to SOAP operations in the given WSDL to be called from the Qorus HttpServer with the SOAP protocol
    /** Creates a mapping in the system SoapHandler from the given WSDL to the current service.  SOAP operations defined in the WSDL will be mapped directly to Qorus service methods with the same names as the SOAP operations.

        @param h a hash with the following keys (only \c wsdl or \c wsdl_file is required):
        - \c wsdl, \c wsdl_file, or \c wsdl_resource: a URL to the WSDL, the WSDL string (XSD), a WebService object, or a file resource name giving the WSDL file
        - \c service: a string giving the name of the SOAP service to map to this service; this key is only necessary to set if the WSDL defines multiple SOAP services
        - \c uri_path: an optional string giving an optional URI path to use when binding the SOAP service

        @throw REGISTER-SOAP-HANDLER-ERROR missing \c wsdl or \c wsdl_file key in argument hash; cannot find service; multiple services defined by WSDL but no \c service key given in argument hash
    */
    static registerSoapHandler(hash<auto> h) {
%ifdef QorusServer
        OMQ::LocalQorusService svc = tld.svc;

        auto wsdl;

        # import options
        hash ioh;

        # get web service definition
        if (h.wsdl_resource) {
            wsdl = svc.getResourceData(h.wsdl_resource);
            ioh.try_import = \svc.getResourceData();
            h -= "wsdl_resource";
        } else if (h.wsdl_file) {
            string def_path;
            wsdl = WSDLLib::getWSDL(h.wsdl_file, NOTHING, NOTHING, \def_path);
            ioh.def_path = def_path;
            h -= "wsdl_file";
        } else if (h.wsdl) {
            if (h.wsdl.typeCode() == NT_STRING && h.wsdl !~ /^<\?xml/) {
                string def_path;
                wsdl = WSDLLib::getWSDL(h.wsdl, NOTHING, NOTHING, \def_path);
                ioh.def_path = def_path;
            } else {
                wsdl = h.wsdl;
                ioh.try_import = \svc.getResourceData();
            }
            h -= "wsdl";
        } else {
            throw "REGISTER-SOAP-HANDLER-ERROR", "neither one of required 'wsdl' or 'wsdl_file' keys is present in the hash argument to ServiceApi::registerSoapHandler()";
        }

        WebService w = wsdl instanceof WebService ? wsdl : new WebService(wsdl, h - "service" + ioh);

        #if (Qorus.getDebugSystem()) olog(LoggerLevel::DEBUG, "registerSoapHandler() w=%n", w);

        # get list of services in this wsdl
        if (!h.service) {
            *hash<string, bool> svch = map {$1.name: True}, w.listServices();
            if (svch.size() > 1)
                throw "REGISTER-SOAP-HANDLER-ERROR", sprintf("no 'service' key passed in the option hash argument to ServiceApi::registerSoapHandler() (WSDL defines the following services: %y)", svch.keys());
        }

        if (exists h.uri_path && h.uri_path.typeCode() != NT_STRING) {
            throw "REGISTER-SOAP-HANDLER-ERROR", sprintf("the \"uri_path\" key does not hold a string; type passed: %y", h.uri_path.type());
        }

        # register with new API (3rd argument = True)
        qorus_api_svc_register_soap_service(w, h.service, h.uri_path, True);
%endif
    }

    #! returns a hash with HTTP call context information
    /**
        @note This API method is relevant for any external HTTP call, including SOAP and REST calls
    */
    static *hash<auto> getHttpCallContext() {
%ifdef QorusServer
        # do not return the "sctx" (server context) key
        return tld.cx - "sctx";
%endif
    }

    #! returns the last @ref systemevents "system events"
    /**
        @param count the maximum number of @ref systemevents "system events" to return
        @return a hash with the following keys:
        - \c lastid: the last event ID at the time the method returns
        - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
        - \c shutdown: if this key is returned, it means the system is shutting down

        @throw SHUTDOWN-ERROR this exception is raised if any event API is called a second time after the \c "shutdown" key is returned
    */
     static hash<auto> getLastEvents(softint count) {
%ifdef QorusServer
        hash<auto> h = Qorus.events.getLastEvents(count);
        cast<OMQ::LocalQorusService>(tld.svc).checkEventShutdown(h);
        return h;
%endif
    }

    #! gets the last system events that meet any of the filter criteria and none of the "and_not" criteria, if present
    /** Returns a hash giving the list of the most recent system events matching a filter and the last event ID generated by the system.   Events in the event list returned must match the criteria passed as the second argument; if any of the criteria match an event, then it is included in the return list, unless a third criteria list argument is also passed, which allows for removing elements from the list returned.
        @param count the maximum number of events to return; if this argument is 0, then the size of the returned list is only limited by the number of events in the system that match the filter(s) passed.
        @param filter this argument gives the criteria list for "logical or" comparisons to be applied to the events.  If an event matches any of the criteria hashes in the first argument, then it is included in the resulting list, subject to processing by the optional third argument.  To match a criteria hash in the second argument with this API call, all of the criteria keys in each hash must match, therefore, to get pure "logical or" behavior the caller must specify only one hash key in each criteria hash; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
        @param and_not this argument is an optional criteria list allowing the resulting event list to be filtered; if any event selected by the second argument matches all criteria hashes in the criteria hashes passed as the third argument, then it is filtered out of the resulting list.  Note that the third argument, if present, is processed with inverted logic compared to the second argument; for a criteria hash to match, any of the criteria given as hash keys in a criteria hash can match, however, all criteria hashes must match for the filter to operate.  Therefore, to get pure "logical and" filtering the caller must specify only one hash key per hash in the list making up the third argument; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
        @return a hash with the following keys:
        - \c lastid: the last event ID at the time the method returns
        - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
        - \c shutdown: if this key is returned, it means the system is shutting down

        @throw GET-LAST-EVENTS-OR-ERROR empty or missing filter value
        @throw GET-EVENTS-ERROR non-hash criteria element passed in event filter
        @throw INVALID-CRITERIA-CODE invalid criteria code found in event filter
        @throw SHUTDOWN-ERROR this exception is raised if any event API is called a second time after the \c "shutdown" key is returned
    */
    static hash<auto> getLastEventsOr(softint count, auto filter, auto and_not) {
%ifdef QorusServer
        hash<auto> h = Qorus.events.getLastEventsOr(count, filter, and_not);
        cast<OMQ::LocalQorusService>(tld.svc).checkEventShutdown(h);
        return h;
%endif
    }

    #! gets the last system events that meet all of the filter criteria or none of the "or_not" criteria, if present
    /**
        @param count the maximum number of events to return; if this argument is 0, then the size of the returned list is only limited by the number of events in the system that match the filter(s) passed.
        @param filter this argument is the criteria list for "logical and" comparisons to be applied to the events.  If an event matches all of the criteria hashes in the first argument, then it is included in the resulting list.  To match a criteria hash in the second argument with this API call, any of the criteria keys in a single hash can match, therefore, to get pure "logical and" behavior, the caller must specify only one hash key in each criteria hash; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
        @param or_not this argument is an optional criteria list that can augment the list returned with negative matches.  If this argument is present and any element in the system’s event list does not match any of the criteria hashes in the third argument, then it is also included in the returned event list.  Note that the third argument, if present, is processed with inverted logic compared to the second argument; for a single criteria hash to match, all of the criteria given as hash keys in the criteria hash must match, therefore, to get pure inverted "logical or" logic, the caller must specify only one hash key per hash in the list making up the third argument; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
        @return a hash with the following keys:
        - \c lastid: the last event ID at the time the method returns
        - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
        - \c shutdown: if this key is returned, it means the system is shutting down

        @throw GET-LAST-EVENTS-AND-ERROR empty or missing filter value
        @throw GET-EVENTS-ERROR non-hash criteria element passed in event filter
        @throw INVALID-CRITERIA-CODE invalid criteria code found in event filter
        @throw SHUTDOWN-ERROR this exception is raised if any event API is called a second time after the \c "shutdown" key is returned
    */
    static hash<auto> getLastEventsAnd(softint count, auto filter, auto or_not) {
%ifdef QorusServer
        hash<auto> h = Qorus.events.getLastEventsAnd(count, filter, or_not);
        cast<OMQ::LocalQorusService>(tld.svc).checkEventShutdown(h);
        return h;
%endif
    }

    #! return available system events
    /** by default without any arguments will immediately return all available events in the cache
        @param min_id the minimum event ID to return; no event wil be returned that has an event ID less than this; the first event ID is always 1 (if min_id <= 1 then all events are returned that meet the given criteria)
        @param timeout_ms optional timeout waiting for events; if not present; the method returns immediately
        @return a hash with the following keys:
        - \c lastid: the last event ID at the time the method returns
        - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
        - \c shutdown: if this key is returned, it means the system is shutting down

        @throw SHUTDOWN-ERROR this exception is raised if any event API is called a second time after the \c "shutdown" key is returned

        @note It is not recommended to use this API in @ref service_remote "remote services", as high-volume message processing
        can have a negative impact on a Qorus cluster as a whole
    */
    static hash<auto> waitForEvents(softint min_id = 1, timeout timeout_ms = 0) {
%ifdef QorusServer
        hash<auto> h = Qorus.events.getEvents(min_id, timeout_ms);
        cast<OMQ::LocalQorusService>(tld.svc).checkEventShutdown(h);
        return h;
%endif
    }

    #! return system events that meet any of the given criteria and none of the optional "and not" criteria
    /**
        @param min_id the minimum event ID to return; no event wil be returned that has an event ID less than this; the first event ID is always 1 (if min_id <= 1 then all events are returned that meet the given criteria)
        @param filter this argument is the criteria list for "logical or" comparisons to be applied to the events.  If a system event matches any of the criteria hashes in the first argument, then it is included in the resulting list, subject to processing by the optional fourth argument.  To match a criteria hash in the second argument with this API call, all of the criteria keys in each hash must match, therefore, to get pure "logical or" behavior the caller must specify only one hash key in each criteria hash; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
        @param timeout_ms optional timeout waiting for events; if not present or 0; the method returns immediately
        @param and_not this argument is an optional criteria list allowing the resulting event list to be filtered; if any event selected by the second argument matches all criteria hashes in the criteria hashes passed as the third argument, then it is filtered out of the resulting list.  Note that the fourth argument, if present, is processed with inverted logic compared to the second argument; for a criteria hash to match, any of the criteria given as hash keys in a criteria hash can match, however, all criteria hashes must match for the filter to operate.  Therefore, to get pure "logical and" filtering the caller must specify only one hash key per hash in the list making up the fourth argument; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
        @return a hash with the following keys:
        - \c lastid: the last event ID at the time the method returns
        - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
        - \c shutdown: if this key is returned, it means the system is shutting down

        @throw GET-EVENTS-OR-ERROR empty or missing filter value
        @throw GET-EVENTS-ERROR non-hash criteria element passed in event filter
        @throw INVALID-CRITERIA-CODE invalid criteria code found in event filter
        @throw SHUTDOWN-ERROR this exception is raised if any event API is called a second time after the \c "shutdown" key is returned

        @note It is not recommended to use this API in @ref service_remote "remote services", as high-volume message processing
        can have a negative impact on a Qorus cluster as a whole
    */
    static hash<auto> waitForEventsOr(softint min_id = 1, auto filter, timeout timeout_ms = 0, auto and_not) {
%ifdef QorusServer
        hash<auto> h = Qorus.events.getEventsOr(min_id, filter, timeout_ms, and_not);
        cast<OMQ::LocalQorusService>(tld.svc).checkEventShutdown(h);
        return h;
%endif
    }

    #! return system events that meet all of the given criteria or none of the optional "or not" criteria
    /**
        @param min_id the minimum event ID to return; no event wil be returned that has an event ID less than this; the first event ID is always 1 (if min_id <= 1 then all events are returned that meet the given criteria)
        @param filter this argument is the criteria list for "logical and" comparisons to be applied to the events.  If an event matches all of the criteria hashes in the first argument, then it is included in the resulting list.  To match a criteria hash in the second argument with this API call, any of the criteria keys in a single hash can match, therefore, to get pure "logical and" behavior, the caller must specify only one hash key in each criteria hash; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
        @param timeout_ms optional timeout waiting for events; if not present or 0; the method returns immediately
        @param or_not this argument is an optional criteria list that can augment the list returned with negative matches.  If this argument is present and any element in the system’s event list does not match any of the criteria hashes in the third argument, then it is also included in the returned event list.  Note that the fourth argument, if present, is processed with inverted logic compared to the second argument; for a single criteria hash to match, all of the criteria given as hash keys in the criteria hash must match, therefore, to get pure inverted "logical or" logic, the caller must specify only one hash key per hash in the list making up the fourth argument; see @ref eventfilters "Event Filter Criteria" for a description of each criteria hash
        @return a hash with the following keys:
        - \c lastid: the last event ID at the time the method returns
        - \c events: a list of event hashes (see @ref eventhash "eventhash" for a detailed description); note that this key will be missing if no events are returned
        - \c shutdown: if this key is returned, it means the system is shutting down

        @throw GET-EVENTS-AND-ERROR empty or missing filter value
        @throw GET-EVENTS-ERROR non-hash criteria element passed in event filter
        @throw INVALID-CRITERIA-CODE invalid criteria code found in event filter
        @throw SHUTDOWN-ERROR this exception is raised if any event API is called a second time after the \c "shutdown" key is returned

        @note It is not recommended to use this API in @ref service_remote "remote services", as high-volume message processing
        can have a negative impact on a Qorus cluster as a whole
    */
    static hash<auto> waitForEventsAnd(softint min_id = 1, auto filter, timeout timeout_ms = 0, auto or_not) {
%ifdef QorusServer
        hash<auto> h = Qorus.events.getEventsAnd(min_id, filter, timeout_ms, or_not);
        cast<OMQ::LocalQorusService>(tld.svc).checkEventShutdown(h);
        return h;
%endif
    }

    #! starts a service thread; passes the remaining arguments to the function to the new thread
    /** @param code the function or service method to call; may be a string giving a function name (string), a call reference, or a closure

        @return the TID of the new thread

        @throw START-SERVICE-THREAD-ERROR the service has no "stop()" method or too many threads are already active in this service (see @ref max-service-threads)
    */
    static int startThread(auto code) {
%ifdef QorusServer
        return services.startServiceThreadArgs(code, argv);
%else
        # necessary to set the varargs flag in the client
        delete argv;
%endif
    }

    #! starts a service thread; uses the second argument as the argument list to pass to the new thread
    /** @param code the function or service method to call; may be a string giving a function name (string), a call reference, or a closure
        @param args the arguments for the function to start in the separate thread

        @return the TID of the new thread

        @throw START-SERVICE-THREAD-ERROR the service has no "stop()" method or too many threads are already active in this service (see @ref max-service-threads)
    */
    static int startThreadArgs(auto code, auto args) {
%ifdef QorusServer
        return services.startServiceThreadArgs(code, args);
%endif
    }

    #! returns information about the current service
    /** @param cx optional thread context hash from HTTP handler if available

        @return a hash with the following keys:
        - \c type: the service type (\c "user" or \c "system")
        - \c name: the name of the service
        - \c version: the version of the service
        - \c desc: the description of the service
        - \c serviceid: the ID of the service, corresponding to \c SERVICES.SERVICEID in the database
        - \c status: either @ref OMQ::SSRunning (if there are running threads) or @ref OMQ::SSLoaded
        - \c threads: the number of currently running threads
        - \c autostart: the autostart flag
        - \c loaded: the date/time the service was loaded/started
        - \c methods: a list of hashes with \c name and \c desc keys for each method
        - \c method: the name of the current method being called
        - \c resources: a hash of resources attached to the service (may be @ref nothing); each hash key is the unique resource name, and the value of each key is a hash with the following keys:
          - \c type: a string giving the resource type name (ie \c "HttpGlobalHandler", \c "HttpListener", \c "FtpListener", etc)
          - \c desc: a struct description of the resource
          - \c info: a hash with additional, free-form information about the resource
        - \c groups: a list of zero or more strings giving group names the service is a member of
    */
    static hash<auto> getServiceInfo(*hash<auto> cx) {
%ifdef QorusServer
        return qorus_api_svc_get_service_info(cx);
%endif
    }

    #! binds an FTP handler to the service; listeners are started according to the listener information in the OMQ::AbstractFtpHandler argument
    /** @param handler defines parameters and callback routines for the system FTP server

        @throw SERVICE-FTP-ERROR no listeners set in OMQ::AbstractFtpHandler, error starting listener
    */
    static bindFtp(OMQ::AbstractFtpHandler handler) {
%ifdef QorusServer
        services.bindFtp(handler);
%endif
    }

    #! binds an HTTP handler to the service
    /** If any listener information is present, then existing listeners with same bind value are reused or new listeners are started according to the listener information in the AbstractHttpHandler argument.
        @param handler defines parameters and callback routines for the system HTTP server
        @param opts additional options for the HTTP handler binding process

        @return a list of service resource names bound to the service; multiple resource names are returned only if there are multiple listeners defined in the handler argument

        @throw SERVICE-HTTP-ERROR error starting listener, error binding URL
        @throw LISTENER-SHARING-ERROR there is already a listener with same bind value and either the service that started it does not allow sharing of it, or the \c allow_listener_sharing option is set to \c False

        @see @ref OMQ::HttpBindOptionInfo
    */
    static list<string> bindHttp(OMQ::AbstractServiceHttpHandler handler, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
%ifdef QorusServer
        return qorus_api_svc_bind_http(handler, opts);
%endif
    }

    #! binds a new handler to a dedicated HTTP service listener by name
    /** @param name the name of the service resource for the dedicated service listener
        @param handler defines parameters and callback routines for the system HTTP server

        @throw BIND-HANDLER-ERROR cannot bind a handler with listeners to an existing HTTP service handler
    */
    static bindHandler(string name, OMQ::AbstractServiceHttpHandler handler) {
%ifdef QorusServer
        if (handler.listeners) {
            throw "BIND-HANDLER-ERROR", sprintf("cannot bind a handler with listeners to an existing HTTP service handler");
        }

        qorus_api_svc_bind_handler(name, handler);
%endif
    }

    #! binds a new handler to a dedicated HTTP service listener by name
    /** @param name the name of the service resource for the dedicated service listener
        @param handler defines parameters and callback routines for the system HTTP server
        @param url a regex for the URL to service
        @param content_type an optional list of Content-Types to match
        @param special_headers an optional list of special headers to match
        @param isregex defines if \a url is a regular expression or not
    */
    static bindHandler(string name, HttpServer::AbstractHttpRequestHandler handler, string url,
        *softlist<auto> content_type, *softlist<auto> special_headers, bool isregex = True) {
%ifdef QorusServer
        qorus_api_svc_bind_handler(name, handler, url, content_type, special_headers, isregex);
%endif
    }

    #! returns contextual information about the current call
    /** @return @ref nothing if no context information is available, otherwise a hash with the following possible keys; keys actually present depend on the context of the caller to the service method:
        - \c wf: this key is present if the call to the service method originated from workflow code while processing an order; the value is a hash with the following keys:
            - \c name: the name of the workflow
            - \c version: the version of the workflow
            - \c workflowid: the workflowid of the workflow
            - \c workflow_instanceid: the workflow_instanceid of the order being executed
            - \c stepid: the stepid of the step being executed
            - \c ind: the array step index of the step being executed
            - \c priority: the priority of the workflow order
            - \c started: the date/time the order started processing
            - \c options: the current workflow execution instance option hash
        - \c job: this key is present if the call to the service method originated from job code; the value is a hash with the following keys:
            - \c jobid: the metadata jobid of the job type
            - \c job_instanceid: the id of the job instance
            - \c name: the job name
            - \c version: the job version
            - \c description: the job description
            - \c trigger: a string describing the timer/trigger for the job
            - \c last_executed: the last executed date/time of the job (@ref nothing if never executed before the current iteration)
            - \c last_executed_job_instanceid: the last executed instance id of the job
            - \c next: the next trigger date/time
        - \c cx: this key is present if the call to the service method originated externally through the network API; the value is a hash with the following keys:
            - \c client-cert: an @ref Qore::SSLCertificate "SSLCertificate" object for the client certificate if
              client certificate capture has been enabled in the listener (see the \a get_remote_certs key in
              @ref HttpServer::HttpListenerOptionInfo "HttpListenerOptionInfo")
            - \c id: the unique HTTP connection ID
            - \c peer-info: a hash of socket information for the remote socket (as returned by Socket::getPeerInfo())
            - \c socket: the bind address used to bind the listener ("socket-info" provides more detailed information)
            - \c socket-info: a hash of socket information for the listening socket (as returned by Socket::getSocketInfo())
            - \c ssl: @ref True if the request was encrypted with HTTPS, @ref False if not
            - \c url: a hash of broken-down URL information (as returned from parseURL())

        @see
        - @ref OMQ::UserApi::UserApi::getUserContextInfo() "UserApi::getUserContextInfo()" for a similar method
          available in all user contexts
    */
    static *hash<auto> getCallContext() {
%ifdef QorusHasSvcApi
        hash<auto> rv;
        if (tld.wfe) {
            rv.wf += tld.wfe{WorkflowOrderCallContextKeys};
            rv.wf += tld.wfe.wf{WorkflowCallContextKeys};
            rv.wf.stepid = tld.stepID;
            rv.wf.ind = tld.ind;
            if (tld.index) {
                try {
                    # try to get workflow options
%ifdef QorusCore
                    rv.wf.options = Qorus.control.execHash{tld.index}.getAllOptions();
%else
                    rv.wf.options = Qorus.control_client.getAllWorkflowInstanceOptions({"username": "%SYS%"}, tld.index);
%endif
                } catch (hash<ExceptionInfo> ex) {
                    # ignore exceptions
                }
            }
        } else if (tld.wf) {
            rv.wf += tld.wf{WorkflowCallContextKeys};
        }

        if (tld.job) {
            if (tld.job.typeCode() == NT_OBJECT) {
                rv.job = tld.job.getInfo();
            } else {
                try {
                    # try to get job info
                    rv.job = Qorus.jobManager.getInfoID(tld.job.jobid);
                } catch (hash<ExceptionInfo> ex) {
                    # ignore exceptions
                }
            }
        }

        if (tld.cx) {
            rv.cx = tld.cx{ServiceCallContextKeys};
        }

        return rv;
%endif
    }

    #! returns a string describing the current call context
    /** @par Example:
        @code{.py}
string str = ServiceApi::getCallContextString();
        @endcode

        @param cx optional thread context hash from HTTP handler if available

        @return a string describing the current call context
    */
    static string getCallContextString(*hash<auto> cx) {
%ifdef QorusServer
        string ctxt;
        *hash<auto> h = ServiceApi::getCallContext();
        if (h.wf) {
            ctxt = sprintf("workflow %s v%s(%d)", h.wf.name, h.wf.version, h.wf.workflowid);
            if (h.wf.workflow_instanceid) {
                ctxt += sprintf(" (wfiid %d)", h.wf.workflow_instanceid);
            }
        } else if (h.job) {
            ctxt = sprintf("job %s v%s(%d) (jiid %d)", h.job.name, h.job.version, h.job.jobid, h.job_instanceid);
        } else {
            if (!h.cx && cx) {
                h.cx = cx;
            }
            if (h.cx) {
                ActionReason reason(h.cx);
                ctxt = sprintf("%y from %y (%s)", reason.getWho(), reason.getSource(), reason.getReason());
            } else {
                ctxt = "<no info available>";
            }
        }

        return ctxt;
%endif
    }

    #! calls a system API with the argument list to the API method as a top-level argument to this method as the current user
    /** @param call the full api method name (ex: \c "omq.system.exec-synchronous-exiting"); see @ref qorusapi for a full list
        @param args any arguments to the method; if multiple argument should be passed to the method, use a list of arguments here

        @return the return value of the method

        @throw UNKNOWN-API-CALL invalid API method
        @throw INVALID-INTERNAL-API-CALL API may not be called internally (ex: omq.system.shutdown-wait())

        @see
        - @ref OMQ::UserApi::UserApi::callNetworkApiArgs() "UserApi::callNetworkApiArgs()"
        - @ref OMQ::UserApi::UserApi::callNetworkApi() "UserApi::callNetworkApi()"
    */
    static auto callApiAsCurrentUser(string call, softlist<auto> args) {
%ifdef QorusCore
        QorusApiContextHelper tch();
        return call_system_api_as_user(call, args, DefaultSystemUser, False);
%endif

%ifdef QorusQsvcServer
        return call_system_api_as_user(call, args, DefaultSystemUser, False);
%endif
    }

    #! returns information about the given service from the service name (if it's currently loaded) and if the calling user can access the service
    /** to get information about services whether they are loaded or not, call REST API:
        @code{.py}
system/metadata/lookupserviceinfo/<type>/<name>
        @endcode

        @param type the type of service (either \c "system" or \c "user"; case is ignored)
        @param name the name of the system service to query
        @param cx optional thread context hash from HTTP handler if available

        @return a hash of service information or @ref nothing if the service is not loaded; the hash will have the following structure:
        - \c type: either \c "system" or \c "user" corresponding to the argument
        - \c name: the name of the service
        - \c version: version of the service
        - \c desc: description of the service
        - \c serviceid: service ID
        - \c status: @ref OMQ::SSRunning or @ref OMQ::SSLoaded
        - \c threads: number of running threads in the service
        - \c autostart: \c True or \c False if the autostart flag is set
        - \c loaded: date/time the service was loaded
        - \c methods: list of hashes for each method with \c name and \c desc keys
        - \c processes: list of process info hashes for remote services

        @throw SERVICE-ACCESS-ERROR the current user does not have the right to access the given service
    */
    static *hash<auto> getServiceInfoAsCurrentUser(string type, string name, *hash<auto> cx) {
%ifdef QorusServer
        qorus_api_svc_get_service_info_as_current_user(type, name, cx);
%endif
    }

    #! returns information about the given service from the serviceid (if it's currently loaded) and if the calling user can access the service
    /** to get information about services whether they are loaded or not, call REST API:
        @code{.py}
system/metadata/lookupserviceinfo/<type>/<name>
        @endcode

        @param id the serviceid of the service
        @param cx optional thread context hash from HTTP handler if available

        @return a hash of service information or @ref nothing if the service is not loaded; the hash will have the following structure:
        - \c type: either \c "system" or \c "user" corresponding to the argument
        - \c name: the name of the service
        - \c version: version of the service
        - \c desc: description of the service
        - \c serviceid: service ID
        - \c status: @ref OMQ::SSRunning or @ref OMQ::SSLoaded
        - \c threads: number of running threads in the service
        - \c autostart: \c True or \c False if the autostart flag is set
        - \c loaded: date/time the service was loaded
        - \c methods: list of hashes for each method with \c name and \c desc keys

        @throw SERVICE-ACCESS-ERROR the current user does not have the right to access the given service
    */
    static *hash<auto> getServiceInfoAsCurrentUser(softint id, *hash<auto> cx) {
%ifdef QorusServer
        return qorus_api_svc_get_service_info_as_current_user(id, cx);
%endif
    }

    #! returns a list of hashes giving information about the currently-running workflow execution instances if the current user can access them
    /** @return a list of hashes giving information about the currently-running workflow execution instances; if no workflow execution instances are running, then an empty list is returned; otherwise each list element is a hash with the following keys:
    - \c executionID: the workflow execution instance id
        - \c name: the name of the workflow
        - \c version: version of the workflow
        - \c workflowid: the workflowid of the workflow
        - \c mode: @ref OMQ::WM_Normal, @ref OMQ::WM_Recovery, @ref OMQ::WM_Synchronous
        - \c status: @ref OMQ::WISInitializing, @ref OMQ::WISRunning, @ref OMQ::WISWaiting, @ref OMQ::WISStopping
        - \c iterations: number of segment iterations performed so far
        - \c totalSegments: number of segments executed
        - \c errors: total number of errors encountered
        - \c warnings: total number of warnings raised
        - \c starttime: date/time the execution instance was started
        - \c options: options set on the workflow execution instance

        @throw WORKFLOW-ACCESS-ERROR the current user does not have the right to access one or more running workflows
    */
    static list<hash<auto>> getRunningWorkflowListAsCurrentUser(string name, *string ver) {
%ifdef QorusServer
        return qorus_api_svc_get_running_workflow_list_as_current_user(name, ver);
%endif
    }

    #! Returns information on all active jobs visible to the given user
    /** If any active jobs are not accessible to the calling user, then they are filtered from the hash returned.

        @return a hash is keyed by job name; the hash values are job information hashes with the following keys:
        - \c jobid: the metadata jobid of the job type
        - \c name: the job name
        - \c version: the job version
        - \c description: the job description
        - \c trigger: a string describing the timer/trigger for the job
        - [\c job_instanceid]: the id of the job instance (will only have a value if the job is currently executing)
        - [\c last_executed]: the last executed date/time of the job (@ref nothing if not yet executed)
        - [\c last_executed_job_instanceid]: the last executed instance id of the job
        - [\c expiry_date]: the expiry date of the job, if any; if this date is present, then the job will not run automatically after this date
        - [\c next]: the next trigger date/time; this key is only included if the job is active
        - \c active: this value is always \c True because this API only returns information about active jobs
    */
    static hash<auto> getActiveJobsAsCurrentUser() {
%ifdef QorusServer
        return Qorus.jobManager.getActiveInfo(DefaultSystemUser);
%endif
    }

    #! Returns the given text or binary @ref service_file_resources "file resource" as its native type in the \c "body" key of a hash along with an HTTP response code and optionally HTTP headers; if a template exists, then the template is rendered and returned, if the given resource does not exist, then an exception is raised
    /** @par Example:
        @code{.py}
hash<auto> h = ServiceApi::getResource("image.jpg", cx);
        @endcode

        @param name the name of the resource
        @param ctx the argument hash to the template code
        @param code the HTTP response code for the response, if not present then 200 \c "OK" is assumed
        @param hdr any optional headers for the response (the \c "Content-Type" header is set from the templates \c "Content-Type" value automatically)

        @return a hash with the following keys:
        - \c code: the HTTP response code corresponding to the \a code argument
        - \c body: the rendered template or @ref service_file_resources "file resource"
        - \c hdr: a hash of headers corresponding to the \a hdr argument plus the \c "Content-Type" key set from the template's "Content-Type" value)

        @throw SERVICE-FILE-RESOURCE-ERROR the given service file resource does not exist

        @see
        - getResourceData()
        - getResourceWsdl()
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static hash<auto> getResource(string name, hash<auto> ctx, int code = 200, *hash<auto> hdr) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).getResource(name, ctx, code, hdr);
%endif
    }

    #! Returns the given text or binary  @ref service_file_resources "file resource" as its native type in the \c "body" key of a hash along with an HTTP response code and optionally HTTP headers; if a template exists, then the template is rendered and returned, if the given resource does not exist, then @ref nothing is returned
    /** @par Example:
        @code{.py}
*hash<auto> h = ServiceApi::tryGetResource("image.jpg", cx);
        @endcode

        @param name the name of the resource
        @param ctx the argument hash to the template code
        @param code the HTTP response code for the response, if not present then 200 \c "OK" is assumed
        @param hdr any optional headers for the response (the \c "Content-Type" header is set from the templates \c "Content-Type" value automatically)

        @return @ref nothing if the resource does not exist or a hash with the following keys:
        - \c code: the HTTP response code corresponding to the \a code argument
        - \c body: the rendered template or @ref service_file_resources "file resource"
        - \c hdr: a hash of headers corresponding to the \a hdr argument plus the \c "Content-Type" key set from the template's "Content-Type" value)

        @see
        - tryGetResourceData()
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static *hash<auto> tryGetResource(string name, hash<auto> ctx, int code = 200, *hash<auto> hdr) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).tryGetResource(name, ctx, code, hdr);
%endif
    }

    #! returns a hash of the service's @ref service_file_resources "file resources" (hash keys are service file resource names) or @ref nothing if the service has none
    /** @par Example:
        @code{.py}
*hash<auto> h = ServiceApi::getResourceHash();
        @endcode

        @return a hash of the service's @ref service_file_resources "file resources" (hash keys are service file resource names) or @ref nothing if the service has none

        @see
        - getResourceList()
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static *hash<auto> getResourceHash() {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).getResourceHash();
%endif
    }

    #! returns a list of the service's @ref service_file_resources "file resources" or @ref nothing if the service has none
    /** @par Example:
        @code{.py}
list<auto> l = ServiceApi::getResourceList();
        @endcode

        @return a list of the service's @ref service_file_resources "file resources" or @ref nothing if the service has none

        @see
        - getResourceHash()
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static list<string> getResourceList() {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).getResourceList();
%endif
    }

    #! Returns the given text or binary @ref service_file_resources "file resource" as its native type; if a template exists, then the template is rendered and returned, if the given resource does not exist, then an exception is raised
    /** @par Example:
        @code{.py}
binary img = ServiceApi::getResourceData("image.jpg");
        @endcode

        @param name the name of the @ref service_file_resources "file resource"
        @param ctx an optional argument hash used if rendering a template resource

        @return the given text or binary @ref service_file_resources "file resource" as its native type; if a template exists, then the template is rendered and returned

        @throw SERVICE-FILE-RESOURCE-ERROR the given service file resource does not exist

        @see
        - getResourceData()
        - getResource()
        - getResourceWsdl()
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static data getResourceData(string name, *hash<auto> ctx) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).getResourceData(name, ctx);
%endif
    }

    #! Returns the given @ref service_file_resources "file resource" as a @ref WSDL::WebService object; any XSD imports are resolved as service resources; if a template exists, then the template is rendered and returned, if the given resource does not exist, then an exception is raised
    /** @par Example:
        @code{.py}
WebService wsdl = ServiceApi::getResourceWsdl("interface1.wsdl");
        @endcode

        @param name the name of the @ref service_file_resources "file resource" representing the WSDL source
        @param ctx an optional argument hash used if rendering a template resource

        @return the given @ref service_file_resources "file resource" as a @ref WSDL::WebService object; any XSD imports are resolved as service resources; if a template exists, then the template is rendered and returned

        @throw SERVICE-FILE-RESOURCE-ERROR the given service file resource does not exist

        @see
        - getResource()
        - getResourceData()
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static WSDL::WebService getResourceWsdl(string name, *hash<auto> ctx) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).getResourceWsdl(name, ctx);
%endif
    }

    #! Returns the given text or binary @ref service_file_resources "file resource" as its native type; if a template exists, then the template is rendered and returned, if the given resource does not exist, then @ref nothing is returned
    /** @par Example:
        @code{.py}
*binary img = UserApi::tryGetResourceData("image.jpg", cx);
        @endcode

        @param name the name of the resource
        @param ctx an optional argument hash to the template code

        @return @ref nothing if the @ref service_file_resources "file resource" does not exist or the given text or binary @ref service_file_resources "file resource" as its native type; if a template exists, then the template is rendered and returned

        @see
        - tryGetResource()
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static *data tryGetResourceData(string name, *hash<auto> ctx) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).tryGetResourceData(name, ctx);
%endif
    }

    #! returns @ref True if the given service @ref service_file_resources "file resource" exists, @ref False if not
    /** @par Example:
        @code{.py}
bool b = ServiceApi::hasResource(name);
        @endcode

        @return @ref True if the given service @ref service_file_resources "file resource" exists, @ref False if not

        @see
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static bool hasResource(string name) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).hasResource(name);
%endif
    }

    #! explicitly renders a @ref service_file_resources "template file resource" given the template argument hash
    /** @par Example:
        @code{.py}
hash<auto> h = ServiceApi::renderTemplate("html/index.qhtml", ctx);
        @endcode

        @param name the @ref service_file_resources "template file resource" name
        @param ctx the argument hash to the template code

        @return a hash with the following keys:
        - \c code: the HTTP response code corresponding to the \a code argument
        - \c body: the rendered template
        - \c hdr: a hash of headers corresponding to the \a hdr argument plus the \c "Content-Type" key set from the
          template's "Content-Type" value)

        @throw TEMPLATE-ERROR the named template does not exist

        @see
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static hash<auto> renderTemplate(string name, hash<auto> ctx) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).renderTemplate(name, ctx);
%endif
    }

    #! render a @ref service_file_resources "template file resource" and returns the rendered template if the template exists, otherwise returns @ref nothing
    /** @par Example:
        @code{.py}
*hash<auto> h = ServiceApi::tryRenderTemplate(name, ctx);
        @endcode

        @param name the @ref service_file_resources "template file resource" name
        @param ctx the argument hash to the template code

        @return @ref nothing if the template does not exist or a hash with the following keys:
        - \c code: the HTTP response code corresponding to the \a code argument
        - \c body: the rendered template
        - \c hdr: a hash of headers corresponding to the \a hdr argument plus the \c "Content-Type" key set from the template's "Content-Type" value)

        @see
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static *hash<auto> tryRenderTemplate(string name, hash<auto> ctx) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).tryRenderTemplate(name, ctx);
%endif
    }

    #! returns a hash of the service's @ref service_file_resources "template file resources" (hash keys are service template resource names) or @ref nothing if the service has none
    /** @par Example:
        @code{.py}
*hash<auto> h = ServiceApi::getTemplateHash();
        @endcode

        @return a hash of the service's @ref service_file_resources "template file resources" (hash keys are service template resource names) or @ref nothing if the service has none

        @see
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static *hash<auto> getTemplateHash() {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).getTemplateHash();
%endif
    }

    #! returns a list of the service's @ref service_file_resources "template file resources" or @ref nothing if the service has none
    /** @par Example:
        @code{.py}
list<auto> l = ServiceApi::getTemplateList();
        @endcode

        @return a list of the service's @ref service_file_resources "template file resources" or @ref nothing if the service has none

        @see
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static list<string> getTemplateList() {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).getTemplateList();
%endif
    }

    #! returns @ref True if the given service @ref service_file_resources "template file resource" exists, @ref False if not
    /** @par Example:
        @code{.py}
bool b = ServiceApi::hasTemplate(name);
        @endcode

        @return @ref True if the given service @ref service_file_resources "template file resource" exists, @ref False if not

        @see
        - @ref service_file_resources
        - @ref bindHttp()
        - @ref OMQ::AbstractServiceHttpHandler
    */
    static bool hasTemplate(string name) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).hasTemplate(name);
%endif
    }

    #! registers the service as an extension of the system UI
    /** @par Example:
        @code{.py}
ServiceApi::uiExtensionRegister(new MyExtensionHandler());
        @endcode

        @param handler the request handler for the requests to the extension, must be derived from @ref OMQ::QorusExtensionHandler

        The registered extension will be available from:
        - default Qorus UI, "Extensions" section
        - directly in URL <tt>http(s)://&lt;hostname&gt;:&lt;port&gt;/UIExtension/&lt;service type&gt;-&lt;service name&gt;-&lt;system resource id&gt;</tt>

        The <tt>system resource id</tt> value is assigned by Qorus itself, it is not predictable. Also it can vary accross various instalations.
        You can use <tt>uiExtensionRegister(handler, url_name)</tt> variant of this method to ensure usage of deterministic URL.
    */
    static uiExtensionRegister(OMQ::QorusExtensionHandler handler) {
%ifdef QorusServer
        services.uiExtensionRegister(handler);
%endif
    }

    #! registers the service as an extension of the system UI with deterministic URL path
    /** @par Example:
        @code{.py}
ServiceApi::uiExtensionRegister(new MyExtensionHandler(), "my_extension");
        @endcode

        @param handler the request handler for the requests to the extension, must be derived from @ref OMQ::QorusExtensionHandler
        @param url_name custom name used in public URL

        The registered extension will be available from:
        - default Qorus UI, "Extensions" section
        - directly in URL <tt>http(s)://&lt;hostname&gt;:&lt;port&gt;/UIExtension/&lt;<b>url_name</b>&gt;</tt>
    */
    static uiExtensionRegister(OMQ::QorusExtensionHandler handler, string url_name) {
%ifdef QorusServer
        services.uiExtensionRegister(handler, url_name);
%endif
    }

    #! registers an HTTP chunked data handler as a service resource
    /** @par Example:
        @code{.py}
ServiceApi::streamRegister("stream", "GET", factory, "returns a data stream with log information");
        @endcode

        @param name the name of the stream handler
        @param methods one or more HTTP methods acceptable for this stream; when acquired with other methods, a
        <tt>405 Method Not Allowed</tt> response is returned
        @param factory a closure or call reference that returns an AbstractRestStreamRequestHandler object, takes the
        following args: <tt>hash&lt:auto&gt; cx, *hash&lt;auto&gt; ah</tt>
        @param desc a description for the stream
    */
    static streamRegister(string name, softlist<string> methods, code factory, string desc) {
%ifdef QorusServer
        cast<OMQ::LocalQorusService>(tld.svc).streamRegister(name, methods, factory, desc);
%endif
    }

    #! registers the service as providing persistent/dedicated HTTP connection support
    /** @par Example:
        @code{.py}
ServiceApi::persistenceRegister(code);
        @endcode

        @param factory a closure or call reference that returns a persistence tracking object derived from
        @ref OMQ::AbstractPersistentDataHelper, takes the following args:
        <tt>hash&lt:auto&gt; cx, *hash&lt;auto&gt; ah</tt>

        @throw SERVICE-PERSISTENCE-ERROR a persistence handler has already been registered
    */
    static persistenceRegister(code factory) {
%ifdef QorusServer
        cast<OMQ::LocalQorusService>(tld.svc).persistenceRegister(factory);
%endif
    }

    #! terminates a persistent connection in the current thread
    /** @par Example:
        @code{.py}
ServiceApi::persistenceThreadTerminate();
        @endcode

        @throw SERVICE-PERSISTENCE-ERROR the current thread is not in a persistent connection
    */
    static persistenceThreadTerminate() {
%ifdef QorusServer
        cast<OMQ::LocalQorusService>(tld.svc).persistenceThreadTerminate();
%endif
    }

    #! starts one or more new global HTTP listeners; listeners will be started on all possible bind addresses in case more than one interface is resolved from the bind address given
    /** @param bind the bind address of the new listener; listeners will be started on all possible bind addresses in case more than one interface is resolved from the bind address given
        @param cert_path the file name of the X.509 certificate in PEM format (only for HTTPS listeners)
        @param key_path the file name of the private key for the X.509 certificate in PEM format (only for HTTPS listeners)
        @param key_password the optional password for the private key
        @param name an optional name prefix for the listener; the final listener name will have the listener id appended to it and will be returned in the \c "name" key in each hash element in the return value for each listener started
        @param family one of the following @ref network_address_family_constants "network family constants":
        - @ref Qore::AF_INET "AF_INET": for binding an IPv4 socket
        - @ref Qore::AF_INET6 "AF_INET6": for binding an IPv6 socket
        - @ref Qore::AF_UNSPEC "AF_UNSPEC": for binding a socket with any available address family

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

        @note listeners started with this API will be served by global Qorus HTTP handlers; they will not be added as service-specific listeners

        @see
        - stopListener()
        - stopListenerId()
    */
    static list<hash<auto>> startListeners(softstring bind, *string cert_path, *string key_path, *string key_password,
        *string name, int family = AF_UNSPEC) {
%ifdef QorusServer
        return cast<list<hash<auto>>>(qorus_api_svc_start_listeners(bind, cert_path, key_path, key_password, name, family));
%endif
    }

    #! stops a single listener based on its name or bind address; does not return until all connections on the listener have closed
    /** @see
        - startListeners()
        - stopListenerId()
    */
    static stopListener(softstring name) {
%ifdef QorusServer
        # we call ServiceManager::stopListenerName() to handle stopping service listeners gracefully
        services.stopListenerName(NOTHING, name);
%endif
    }

    #! stops a single listener based on its listener ID; does not return until all connections on the listener have closed
    /** @see
        - startListeners()
        - stopListener()
    */
    static stopListenerId(softint id) {
%ifdef QorusServer
        # we call ServiceManager::stopListenerId() to handle stopping service listeners gracefully
        services.stopListenerId(NOTHING, id);
%endif
    }

    #! starts a dedicated SOAP listener with the given WSDL and registers the current service as a SOAP service and exports its methods that map to SOAP operations in the given WSDL to be called from the Qorus HttpServer with the SOAP protocol
    /** @par Example:
        @code{.py}
hash opts.wsdl = ServiceApi::getResourceData("MySoapService.wsdl");
list ret = ServiceApi::registerSoapListener(opts, port);
logInfo("soap listeners: %y", ret);
        @endcode

        Creates a mapping in the system SoapHandler from the given WSDL to the current service.  SOAP operations defined in the WSDL will be mapped directly to Qorus service methods with the same names as the SOAP operations.

        @param sh a hash with the following keys (only \c wsdl, \c wsdl_file, or \c wsdl_resource is required)):
        - \c wsdl, \c wsdl_file, or \c wsdl_resource: a URL to the WSDL, the WSDL string (XSD), a WebService object, or a file resource name giving the WSDL file
        - \c service: a string giving the name of the SOAP service to map to this service; this key is only necessary to set if the WSDL defines multiple SOAP services
        - \c cert_path: (optional) a path to an X509 certificate for HTTPS listeners
        - \c key_path: (optional) a path to a private key file for an X509 certificate for HTTPS listeners
        - \c key_password: (optional) an optional string giving the password for the private key (PEM format only)
        - \c cert: (optional) a Qore::SSLCertificate object for HTTPS listeners
        - \c key: (optional) a Qore::SSLPrivateKey object for HTTPS listeners
        @param bind the bind address of the new listener; listeners will be started on all possible bind addresses in case more than one interface is resolved from the bind address given
        @param family one of the following @ref network_address_family_constants "network family constants":
        - @ref Qore::AF_INET "AF_INET": for binding an IPv4 socket
        - @ref Qore::AF_INET6 "AF_INET6": for binding an IPv6 socket
        - @ref Qore::AF_UNSPEC "AF_UNSPEC": for binding a socket with any available address family
        @param auth if @ref nothing then the system authenticator is used, otherwise an authenticator object for the listener; to authenticate all requests, use an object of class @ref OMQ::PermissiveAuthenticator "PermissiveAuthenticator"
        @param opts additional options for the HTTP handler binding process

        @return a list of resource names for the HTTP listener resources added to the service

        @throw REGISTER-SOAP-LISTENER-ERROR missing \c wsdl or \c wsdl_file key in argument hash; cannot find service; multiple services defined by WSDL but no \c service key given in argument hash

        @see
        - registerSoapListeners()
    */
    static list<string> registerSoapListener(hash<auto> sh, softstring bind, int family = AF_UNSPEC, *HttpServer::AbstractAuthenticator auth, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
%ifdef QorusServer
        return services.registerSoapListener(sh, bind, family, auth, opts);
%endif
    }

    #! starts a dedicated SOAP listener with one or more WSDLs and registers the current service as a SOAP service and exports all methods that map to SOAP operations in the given WSDLs to be called from the Qorus HttpServer with the SOAP protocol
    /** @par Example:
        @code{.py}
list<hash<auto>> sl = (
    {"wsdl": ServiceApi::getResourceData("MySoapService1.wsdl"},
    {"wsdl": ServiceApi::getResourceData("MySoapService2.wsdl"},
);
list<auto> ret = ServiceApi::registerSoapListeners(sl, port);
logInfo("soap listeners: %y", ret);
        @endcode

        Creates a mapping in the system SoapHandler from the given WSDLs to the current service.  SOAP operations defined in the WSDLs will be mapped directly to Qorus service methods with the same names as the SOAP operations.

        @param sl a list of hashes with the following keys (only \c wsdl, \c wsdl_file, or \c wsdl_resource is required):
        - \c wsdl, \c wsdl_file, or \c wsdl_resource: a URL to the WSDL, the WSDL string (XSD), a WebService object, or a file resource name giving the WSDL file
        - \c service: a string giving the name of the SOAP service to map to this service; this key is only necessary to set if the WSDL defines multiple SOAP services
        @param bind the bind address of the new listener; listeners will be started on all possible bind addresses in case more than one interface is resolved from the bind address given
        @param lh an optional hash of listener info for HTTPS listeners
        - \c cert_path: (optional) a path to an X509 certificate for HTTPS listeners
        - \c key_path: (optional) a path to a private key file for an X509 certificate for HTTPS listeners
        - \c key_password: (optional) an optional string giving the password for the private key (PEM format only)
        - \c cert: (optional) a Qore::SSLCertificate object for HTTPS listeners
        - \c key: (optional) a Qore::SSLPrivateKey object for HTTPS listeners
        @param family one of the following @ref network_address_family_constants "network family constants":
        - @ref Qore::AF_INET "AF_INET": for binding an IPv4 socket
        - @ref Qore::AF_INET6 "AF_INET6": for binding an IPv6 socket
        - @ref Qore::AF_UNSPEC "AF_UNSPEC": for binding a socket with any available address family
        @param auth if @ref nothing then the system authenticator is used, otherwise an authenticator object for the listener; to authenticate all requests, use an object of class @ref OMQ::PermissiveAuthenticator "PermissiveAuthenticator"
        @param opts additional options for the HTTP handler binding process

        @return a list of resource names for the HTTP listener resources added to the service

        @throw REGISTER-SOAP-LISTENER-ERROR missing \c wsdl or \c wsdl_file key in argument hash; cannot find service; multiple services defined by WSDL but no \c service key given in argument hash

        @see
        - registerSoapListener()
    */
    static list<string> registerSoapListeners(list<auto> sl, softstring bind, *hash<auto> lh, int family = AF_UNSPEC, *HttpServer::AbstractAuthenticator auth, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
%ifdef QorusServer
        return services.registerSoapListeners(sl, bind, lh, family, auth, opts);
%endif
    }

    #! return the static data hash for the current workflow order if the service call was made from a workflow order, otherwise return @ref nothing
    /**
    */
    static *hash<auto> tryGetWfStaticData() {
%ifdef QorusServer
        return qorus_api_svc_try_get_wf_static_data();
%endif
    }

    #! return the dynamic data hash for the current workflow order if the service call was made from a workflow order, otherwise return @ref nothing
    /**
    */
    static *hash<auto> tryGetWfDynamicData() {
%ifdef QorusServer
        return qorus_api_svc_try_get_wf_dynamic_data();
%endif
    }

    #! return the temp data hash for the current workflow order if the service call was made from a workflow order, otherwise return @ref nothing
    /**
    */
    static *hash<auto> tryGetWfTempData() {
%ifdef QorusServer
        return qorus_api_svc_try_get_wf_temp_data();
%endif
    }

    #! serializes the given hash and stores against the service's state data in \c SERVICE_STATE_DATA
    /** @param data the state data to serialize and store against the service's state data in \c SERVICE_STATE_DATA

        @see
        - getStateData()
        - @ref OMQ::UserApi::Job::JobApi::saveStateData() "JobApi::saveStateData()"
        - @ref OMQ::UserApi::Job::JobApi::getStateData() "JobApi::getStateData()"
        - @ref rest_api_GET_latest_services__id_or_name_
        - @ref rest_api_PUT_latest_services__id_or_name__setStateData
    */
    static saveStateData(*hash<auto> data) {
%ifdef QorusHasSvcApi
        cast<OMQ::LocalQorusService>(tld.svc).saveStateData(data);
%endif
    }

    #! serializes the given hash and stores against the service's state data in \c SERVICE_STATE_DATA
    /** @code{.py}
# will assign {"account": {"id": "123456ABC"}}
ServiceApi::saveStateDataPath("account.id", "123456ABC");
        @endcode

        @param path the path to the data to save
        @param value the value to merge into existing persistent state data at the given path

        @see
        - saveStateData()
        - getStateData()

        @since Qorus 5.0
    */
    static saveStateDataPath(string path, auto value) {
%ifdef QorusHasSvcApi
        cast<OMQ::LocalQorusService>(tld.svc).saveStateDataPath(path, value);
%endif
    }

    #! returns any service state state data stored with saveStateData()
    /** @return any service state state data stored with saveStateData()

        @note service state state data is automatically cleared when a service instance gets a @ref OMQ::StatComplete status

        @see
        - saveStateData()
        - @ref OMQ::UserApi::Job::JobApi::getStateData() "JobApi::getStateData()"
        - @ref OMQ::UserApi::Job::JobApi::saveStateData() "JobApi::saveStateData()"
        - @ref rest_api_GET_latest_services__id_or_name_
        - @ref rest_api_PUT_latest_services__id_or_name__setStateData
    */
    static *hash<auto> getStateData() {
%ifdef QorusHasSvcApi
        return cast<OMQ::LocalQorusService>(tld.svc).getStateData();
%endif
    }

    #! Changes option values on a service
    /** If at least one invalid option is passed to the method, an exception will be raised; however all other valid
        options in the hash will be set before the exception is raised

        @param opts a hash of option-value pairs

        @throw SERVICE-OPTION-ERROR invalid option name

        @see
        - set_option()
        - getOption()
        - getOptionArgs()
    */
    static setOption(hash<auto> opts) {
%ifdef QorusCore
        Qorus.qmm.updateServiceOptionsErr(tld.svc.serviceid, opts);
%endif

%ifdef QorusQsvcServer
        Qorus.svc.setOptions(opts);
%endif
    }

    #! Changes a single option value on a service
    /** If an invalid option is passed to the method, an exception will be raised.

        @param option the option to set
        @param value the value to set for the option

        @throw SERVICE-OPTION-ERROR invalid option name

        @see
        - set_option()
        - getOption()
        - getOptionArgs()
    */
    static setOption(string option, auto value) {
        ServiceApi::setOption({option: value});
    }

    #! Returns the value of the named service option(s)
    /** If the option is not set on the service level, and it is a valid system option, then the value of the system
        option will be returned.

        @return the value requested directly if only one argument is passed, otherwise a hash of option keys and
        values; note that if no arguments are passed to the method all service-level options are returned as a hash

        @note Invalid options do not cause an errors to be raised; the associated key
        values in the hash returned will be NOTHING

        @see
        - get_option()
        - getOptionArgs()
        - setOption()
    */
    static auto getOption() {
%ifdef QorusServer
        return qorus_api_service_get_option_args(argv);
%else
        # necessary to set the varargs flag in the client
        delete argv;
%endif
    }

    #! Returns the value of the named service option or options
    /** If the option is not set on the service, and it is a valid system option, then the value of the system
        option will be returned.

        @param args the list of options to return

        @return the value requested directly if only one argument is passed, otherwise a hash of option keys and
        values; note that if no arguments are passed to the method all service-level options are returned as a hash

        @note Invalid options do not cause an errors to be raised; the associated key
        values in the hash returned will be NOTHING

        @see
        - getOption()
        - setOption()
    */
    static auto getOptionArgs(*softlist<string> args) {
%ifdef QorusServer
        return qorus_api_service_get_option_args(args);
%else
        # necessary to set the varargs flag in the client
        delete argv;
%endif
    }

    #! puts the current thread to sleep for a certain number of seconds
    /**
        If the service is stopping, this method returns immediately with a
        return value of -1; otherwise the current thread is put to sleep for the full time period requested.  If this
        method (or usleep()) is called again after -1 is returned, then a \c "STOP-ERROR" exception is thrown.

        @param arg the number of seconds to sleep

        @return 0 if current thread was put to sleep for the full time period; -1 if the sleep was interrupted because
        the current object is being stopped

        @throw STOP-ERROR the current object is stopping and this method already returned -1 as a warning

        @see
        - omqsleep()
        - usleep()
    */
    static int sleep(softint arg) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).usleep(arg * 1000000);
%endif
    }

    #! puts the current thread to sleep for a certain number of microseconds
    /**
        If the service is stopping, this method returns immediately with a return
        value of -1; otherwise the current thread is put to sleep for the full time period requested.  If this method
        (or sleep()) is called again after -1 is returned, then a \c "STOP-ERROR" exception is thrown.

        @param arg the number of microseconds to sleep (1 microsecond = 1/1000000 of a second)

        @return 0 if current thread was put to sleep for the full time period; -1 if the sleep was interrupted because
        the current object is being stopped

        @throw STOP-ERROR the current object is stopping and this method already returned -1 as a warning

        @see
        - omqusleep()
        - sleep()
    */
    static int usleep(softint arg) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).usleep(arg);
%endif
    }

    #! puts the current thread to sleep for a certain number of microseconds
    /**
        If the service is stopping, this method returns immediately with a return
        value of -1; otherwise the current thread is put to sleep for the full time period requested.  If this method
        (or sleep()) is called again after -1 is returned, then a \c "STOP-ERROR" exception is thrown.

        @param arg the amount of time in microseconds to sleep (1 microsecond = 1/1000000 of a second)

        @return 0 if current thread was put to sleep for the full time period; -1 if the sleep was interrupted because
        the current object is being stopped

        @throw STOP-ERROR the current object is stopping and this method already returned -1 as a warning

        @see
        - omqusleep()
        - sleep()
    */
    static int usleep(date arg) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).usleep(get_duration_microseconds(arg));
%endif
    }

    #! returns the value of the given service configuration item
    /** @par Example:
        @code{.py}
auto val = ServiceApi::getConfigItemValue(item);
        @endcode

        @param item the name of the service configuration item; service configuration item values
        take precedence over values on global level if both are set otherwise if both are not set
        the default value is returned
        @param local_context the caller can supply its "local" context for template variables (plus user context info is
        added - see the @ref OMQ::UserApi::UserApi::getUserContextInfo() "UserApi::getUserContextInfo()" method)
        @param expand_complex_values if @ref True then lists and hashes will have their string values expanded
        recursively

        @return the value of the given configuration item

        @throw CONFIG-ITEM-ERROR thrown if the configuration item is not valid

        @note the value is always substituted with
        @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure and escape any \c "$"
        characters with a backslash (\c "\") to avoid template substitution

        @since
        - Qorus 4.1.1 added the \a expand_complex_values parameter

        @see @ref service_config_items
    */
    static auto getConfigItemValue(string item, *hash<auto> local_context, bool expand_complex_values = True) {
%ifdef QorusServer
        return cast<OMQ::AbstractQorusService>(tld.svc).getConfigItemValue(item, local_context, expand_complex_values);
%endif
    }

    #! returns a hash of all configuration items for the current service
    /** @par Example:
        @code{.py}
hash<auto> config = ServiceApi::getConfigItemHash();
        @endcode

        @param local_context the caller can supply its "local" context for template variables (plus user context info is
                             added - see @ref UserApi::getUserContextInfo() method)

        @return a hash of all configuration items for the current service; keys are config item names; values are
        config item values. If there are no config items for the current service, then an empty hash is returned.

        @note if there are local configuration item values and values on global level, the
        local values will take precedence over the global values

        @throw CONFIG-ITEM-ERROR thrown if the configuration item is not valid

        @note values are always substituted with
        @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure and escape any \c "$"
        characters with a backslash  (\c "\") to avoid template substitution

        @see @ref service_config_items
    */
    static hash<auto> getConfigItemHash(*hash<auto> local_context) {
%ifdef QorusServer
        return cast<OMQ::AbstractQorusService>(tld.svc).getConfigItemHash(local_context);
%endif
    }

    #! Set a callback for config item value changes in the service
    /** @par Example:
        @code{.py}
class MyService inherits QorusService {
    private:internal myCallback(string config_item_name) {
        # ...
    }

    init() {
        setConfigItemChangeCallback(\myCallback());
    }
}
        @endcode

        @param callback the callback in the service; must take a single string argument giving the name of the config
        item whose value was updated

        @note The callback is executed asynchronously to the update; there can be a lag between the actual update and
        the delivery of the message from @ref qorus-core "qorus-core" to the remote process (if the interface is
        running remotely), also the callback is always run in a background thread that is unsynchronized with the
        change of the config item value; keep these facts in mind when writing code that reacts to config item value
        updates.

        @since Qorus 4.1
    */
    static setConfigItemChangeCallback(*code callback) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusService>(tld.svc).setConfigItemChangeCallback(callback);
%endif
    }
}
