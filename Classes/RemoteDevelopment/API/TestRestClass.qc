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

/** @REST /v3/development/test/{id}

    This URI path implements test request to Qorus.
*/
class RemoteDevelopment::TestRequestRestClass inherits RequestRestClass {
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
            - \c UPLOADING - the files are uploading
            - \c UPLOADED - all files are uploaded to the server
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

/** @REST /v3/development/test

    This URI path provides API to execute qtests.
*/
class RemoteDevelopment::TestRestClass inherits QorusRestClass {
    string name() {
        return "test";
    }

    *QorusRestClass subClass(string request_id, hash<auto> cx, *hash<auto> ah) {
        return new TestRequestRestClass(request_id);
    }

    /** @REST POST

        @par Description
        Asynchronously creates a test request and returns id and resource location.

        @par Arguments
        This API takes the following argument as method body:
        - \c files: required; \a list of qtest files. Each element is a hash with in the following format:
            - \c file_name: \a string.
            - \c file_content: base64 encoded \a string.
        - \c options: optional; \a hash of delete options. List of valid options:
            - \c continue_on_error: if \a True and one of the tests fails, server will continue on execution of the rest.

        @note By default all options are set to \a False.

        <b>Example of POST request:</b>

        @code
        {
            "files":
            [
                {
                    "file_name": "file1.qtest",
                    "file_content": "dGV4dCBmcm9tIHRtcCAw",
                    "args": {
                        "arg1": "value1",
                        "arg2": "value2"
                    }
                },
                {
                    "file_name": "path/file2.qtest",
                    "file_content": "dGV4dCBmcm9tIHRtcCAx"
                },
            ],
            options: {
                "continue_on_error": True
            }
        }
        @endcode

        File content is base64 encoded. Options parameter is optional.

        @par Return Value
        If success 202 Accepted, resource location and \a id of the created request is returned. In case of fail 400
        bad request error is returned.
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        try {
            Request request = new TestRequest(ah.files, cx.user, ah.options);
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
