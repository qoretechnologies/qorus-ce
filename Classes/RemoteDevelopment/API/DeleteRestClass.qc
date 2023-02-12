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

public namespace RemoteDevelopment;

/** @REST /v3/development/delete/{id}

    This URI path implements delete request to Qorus.
*/
class RemoteDevelopment::DeleteRequestRestClass inherits RequestRestClass {
    constructor(string id) : RequestRestClass(id) {
    }

    /** @REST GET

        @par Description
        Returns status of a delete request with given request id.

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; id of the request to obtain status.

        @par Return Value
        If success 200 OK and \a hash of the request status, in case of fail 404 not found error.
        The status hash has the following keys:
        - \c status: the status of the request:
            - \c QUEUED - the request is waiting in the queue
            - \c IN_PROGRESS - the request is in progress
            - \c CANCELED - the request has been canceled by the user
            - \c FAILED - the request has failed
            - \c FINISHED - the request is finished
        - \c exit_code: the exit code of the request
        - \c stderr: the standard error output
        - \c stdout: the standard output
        - \c created: the date/time the request was created
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RequestRestClass::get(cx, ah);
    }

    /** @REST DELETE

        @par Description
        Cancel a delete request with given request id.

        @par Arguments
        This API takes the following argument as URI arguments:
        - \c id: required; id of the request to be canceled.

        @par Return Value
        If success 200 OK, in case of fail one of the error codes: 410, 403, 404 and \a string of error description.
    */
    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        return RequestRestClass::del(cx, ah);
    }
}

/** @REST /v3/development/delete

    This URI path provides API to delete interfaces from Qorus.
*/
class RemoteDevelopment::DeleteRestClass inherits QorusRestClass {
    string name() {
        return "delete";
    }

    *QorusRestClass subClass(string request_id, hash<auto> cx, *hash<auto> ah) {
        return new DeleteRequestRestClass(request_id);
    }

    /** @REST POST

        @par Description
        Asynchronously creates a delete request and returns id and resource location.

        @par Arguments
        This API takes the following argument as method body (all arguments are optional, but at least one must be
        presented otherwise 400 BAD-REQUEST error will be returned)
        - \c function: optional; \a list of functions to be deleted
        - \c class: optional; \a list of classes to be deleted
        - \c constant: optional; \a list of constants to be deleted
        - \c service: optional; \a list of services to be deleted
        - \c step: optional; \a list of workflow steps to be deleted
        - \c wfinstances: optional; \a list of workflow instances to be deleted
        - \c workflow: optional; \a list of workflows to be deleted

        Each element of the above lists is a hash with the following keys:
        - \c name: required; name of the interface.
        - \c version: required; version of the interface.
        Also each interface can be deleted by providing only its id:
        - \c id: required; id of the interface.

        - \c method: optional; \a list of service methods to be deleted. Each element is a hash with the following keys:
          - \c name: required; name of the service.
          - \c version: required; version of the service.
          - \c method-name: required; name of the method.
        Also methods can be deleted by providing only its id:
        - \c id: required; id of the method.

        The follow hash keys are accepted and take only the object name for deletion:
        - \c datasource: optional; \a list of datasource connections to be deleted.
        - \c event: optional; \a list of events to be deleted.
        - \c fsm: optional; \a list of FSMs to be deleted
        - \c job: optional; \a list of jobs to be deleted.
        - \c jobinstances: optional; \a list of job instances to be deleted.
        - \c mapper: optional; \a list of mappers to be deleted.
        - \c pipeline: optional; \a list of pipelines to be deleted
        - \c queue: optional; \a list of queues to be deleted.
        - \c remote: optional; \a list of remote connections to be deleted.
        - \c uconn: optional; \a list of user connections to be deleted.
        - \c vmap: optional; \a list of value maps to be deleted.

        Each element of the above lists is a hash with the following keys:
        - \c name: required; name of the value map.
        Also each interface from the above list (except for all connections) can be deleted by providing only its id:
        - \c id: required; id of the interface.

        - \c options: optional; \a hash of delete options. List of valid options:
          - \c reload: reload interfaces in the server
          - \c verbosity-level: sets verbosity level (greater value = more info)

        @note By default all options are set to \a False and verbosity level is set to 0.

        <b>Example of POST request:</b>

        @code
        {
            "workflow":
            [
                {
                    "name" : "workflow1",
                    "version" : "1.0"
                },
                {
                    "id" : "4"
                }
            ],
            "method": [
                {
                    "service-name": "service1",
                    "version": "1.0",
                    "method-name": "method1"
                }
            ],
            "options": {
                "reload": true,
                "verbosity-level": 2
            }
        }
        @endcode

        @par Return Value
        If success 202 Accepted, resource location and \a id of the created request is returned. In case of fail 400
        bad request error is returned.
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        try {
            Request request = new DeleteRequest(ah, cx.user, cx.hdr."qorus-token");
            hash<CreationStatus> result = Qorus.remoteDevelopmentHandler.createRequest(request);
            return RestHandler::makeResponse(202, {"id": result.id, "href": cx.url.path + "/" + result.id});
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "BAD-REQUEST") {
                Qorus.logError("%s", get_exception_string(ex));
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
    }
}
