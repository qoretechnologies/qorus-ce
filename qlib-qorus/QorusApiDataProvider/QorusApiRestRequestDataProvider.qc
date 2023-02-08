# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiRestRequestDataProvider class definition

/** QorusApiRestRequestDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
*/

%requires RestClient
%requires Swagger

#! contains all public definitions in the QorusApiDataProvider module
public namespace QorusApiDataProvider {
#! The Qorus API data provider for the data provider REST request API
public class QorusApiRestRequestDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiRestRequestDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiRestRequestRequestDataType();

        #! Response type
        const ResponseType = new QorusApiRestRequestResponseDataType();
    }

    #! Returns the name of the data provider
    string getName() {
        return "rest-request";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: performs a REST API call and returns the response (with call "
            "metadata information) as output data.\n\n"
            "This API also includes arguments that allow it to do inline recoveries from technical errors; by "
            "default up to 3 retries are made up to 5 seconds apart; see the `retries`, `retry-delay`, and "
            "`retry-errors` arguments";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        int retries = req.retries ?? QorusApiSearchRequestDataType::Fields."retries".default_value;
        if (retries < 0) {
            retries = 0;
        }
        int retry_delay_secs = req."retry-delay" ?? QorusApiSearchRequestDataType::Fields."retry-delay".default_value;
        if (retries > 0 && retry_delay_secs < 0) {
            retry_delay_secs = 0;
        }

        UserApi::logInfo("QorusApiRestRequestDataProvider: REST connection: %y %s %s arg/body: %y",
            req.connection, req.method, req."uri-path", req.arg);

        # remove null args from the request body if applicable
        if (req."remove-nulls" && req.arg.typeCode() == NT_HASH) {
            req.arg -= (map $1.key, req.arg.pairIterator(), !$1.value.val());
        }

        hash<auto> response;
        int retry_count = 0;
        hash<auto> info;
        while (True) {
            UserApi::logInfo("retries: %y retry_delay_secs: %y", retries, retry_delay_secs);
            # ensure that request info gets logged
            on_exit {
                UserApi::logDebug("REST REQUEST INFO: %N", info);
            }
            # make the request and get the unique ID (if applicable)
            try {
                # NOTE: the socket connection to the remote service is already established in the call to
                # getConnection(), so it has to be made in the try block
                RestClient rc = getConnection(req);
                # make the request to the server
                response = rc.doRequest(
                    req.method,
                    req."uri-path",
                    req.arg,
                    \info,
                    NOTHING,
                    req.headers,
                );
                if (retry_count) {
                    UserApi::logInfo("QorusApiRestRequestDataProvider: successfully recovered the REST action after "
                        "%d retr%s", retry_count,
                        retry_count == 1 ? "y" : "ies");
                }
            } catch (hash<ExceptionInfo> ex) {
                if (retries && isConnectionIoError(req, ex)) {
                    if (retry_count == retries) {
                        UserApi::logError("QorusApiRestRequestDataProvider: %s: %s: maximum retries reached (%d), not "
                            "retrying again", ex.err, ex.desc, retries);
                    } else {
                        ++retry_count;
                        UserApi::logInfo("QorusApiRestRequestDataProvider: %s: %s: waiting %d second%s for retry...",
                            ex.err, ex.desc, retry_delay_secs, retry_delay_secs == 1 ? "" : "s");
                        UserApi::sleep(retry_delay_secs);
                        UserApi::logInfo("QorusApiRestRequestDataProvider: retrying the REST equest action now");
                        continue;
                    }
                }
                rethrow ex.err, ex.desc, info;
            }
            break;
        }
        UserApi::logDebug("REST RESPONSE: %N", response);

        *string id_loc = req."id-location";
        auto val;
        if (exists id_loc) {
            if (id_loc == "-") {
                val = response;
            } else {
                if (response.typeCode() != NT_HASH) {
                    throw "REST-RESPONSE-ERROR", sprintf("\"id-location\" is set to %y, but the response is "
                        "not a hash (type: %y)", id_loc, response.type());
                }
                val = UserApi::getHashDotValue(response, id_loc);
            }
            if (!exists val) {
                throw "REST-RESPONSE-MISSING", sprintf("no value was found in the response at location %y; "
                    "response: %y", id_loc, response);
            }
            UserApi::logInfo(req."id-log-msg", val);
        }

        # get response value
        hash<auto> rv = {
            "body": response.body,
            "request-uri": info."request-uri",
            "request-headers": info.headers,
            "request-serialization": info."request-serialization",
            "response-code": info."response-code",
            "response-uri": info."response-uri",
            "response-headers": info."response-headers",
            "response-serialization": info."response-serialization",
            "response-chunked": info.chunked ?? False,
        };

        # save output data
        *hash<auto> output_data = req."output-data";
        if (output_data) {
            UserApi::updateOutputData({"response": rv}, output_data);
        }

        return rv;
    }

    #! returns a REST connection to the server, optionally setting a Swagger schema from a service resource
    private RestClient getConnection(hash<auto> req) {
        # connection options, if any
        hash<auto> connection_opts;
        {
            # get Swagger schema resource name, if any
            *string schema = req."swagger-schema-location";
            if (schema) {
                UserApi::logInfo("using swagger schema location: %y", schema);
                # create Swagger REST schema validator object
                connection_opts = {
                    "validator": SwaggerLoader::fromString(UserApi::getTextFileFromLocation(schema), False),
                };
            }
        }
        # get REST connecting and use validator, if present
        return UserApi::getUserConnection(req.connection, True, True, connection_opts);
    }

    #! Returns True if the error is a connection I/O error
    private static bool isConnectionIoError(hash<auto> req, hash<ExceptionInfo> ex) {
        *hash<string, bool> errmap = map {$1: True}, req."retry-errors";
        bool rv = errmap{ex.err} ?? False;
        UserApi::logDebug("QorusApiRestRequestDataProvider: %y I/O error: %y", ex.err, rv);
        return rv;
    }

    #! Returns the description of a successful request message, if any
    /** @return the request type for this provider
    */
    private *AbstractDataProviderType getRequestTypeImpl() {
        return RequestType;
    }

    #! Returns the description of a response message, if this object represents a response message
    /** @return the response type for this response message
    */
    private *AbstractDataProviderType getResponseTypeImpl() {
        return ResponseType;
    }

    #! Returns data provider static info
    hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }
}

#! Data type for REST request calls
public class QorusApiRestRequestRequestDataType inherits HashDataType {
    public {
        #! Field descriptions
        const Fields = {
            "connection": {
                "type": ConnectionType,
                "desc": "The name of the REST connection",
                "required": True,
            },
            "method": {
                "type": StringType,
                "desc": "The REST/HTTP method to use",
                "required": True,
            },
            "uri-path": {
                "type": StringOrNothingType,
                "desc": "The path part of the URI to use; it will be appended to any default path in the connection",
            },
            "arg": {
                "type": AutoType,
                "desc": "The REST request message body or argument",
            },
            "id-location": {
                "type": StringOrNothingType,
                "desc": "The location in the response for a response message ID; `-` means the entire response is "
                "the ID; if this argument has a value, and no value is found in the response at the location given, "
                "an exception is thrown",
            },
            "headers": {
                "type": HashOrNothingType,
                "desc": "Additional headers to send with each REST request",
            },
            "swagger-schema-location": {
                "type": StringOrNothingType,
                "desc": "The location of the Swagger schema for the REST connection; this will be resolved by "
                    "calling `UserApi::getTextFileFromLocation()`",
            },
            "remove-nulls": {
                "type": BoolType,
                "desc": "If `true` then any empty key values in the request body will be removed before sending the "
                    "request to the server",
                "default_value": False,
            },
            "output-data": {
                "type": HashOrNothingType,
                "desc": "Can be used to write the response message to an output location.\n\n"
                    "The entire REST response hash can be found in the `response` key of the hash value passed to "
                    "`UserApi::updateOutputData()`.\n\n"
                    "If the *id-location* argument has a value, then the value retrieved can be referenced with key "
                    "`rest-id` in the output data hash.\n\n"
                    "Example: `response.body: $dynamic:record`: to store the response body in workflow dynamic "
                    "data when executed in a workflow context.",
            },
            "id-log-msg": {
                "type": StringOrNothingType,
                "desc": "A string giving a log message for successful retrieval of the ID identified by "
                    "`id-location`; this ID will be passed as an argument after the log message string and can be "
                    "referred to with a placeholder like `%y` in the log string.\n\n"
                    "This value is ignored if `id-location` is not set.",
                "default_value": "response ID: %y",
            },
            "retries": {
                "type": IntType,
                "desc": "Number of times a request action will be retried if a connection error is encountered; if "
                    "this number is <=0, then no retries are made",
                "default_value": 3,
            },
            "retry-delay": {
                "type": IntType,
                "desc": "The retry delay in number of seconds; only takes effect if `retries` is > 0",
                "default_value": 5,
            },
            "retry-errors": {
                "type": ListOrNothingType,
                "desc": "The list of error codes that result in a retry of the REST request operation if `retries` > 0",
                "default_value": (
                    "SOCKET-CONNECT-ERROR",
                    "SOCKET-CLOSED",
                ),
            },
        };
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            Fields.pairIterator();
    }
}

#! Data type for REST request calls
public class QorusApiRestRequestResponseDataType inherits HashDataType {
    public {
        #! Field descriptions
        const Fields = {
            "body": {
                "type": AutoType,
                "desc": "The response message body, if any",
            },
            "request-uri": {
                "type": StringType,
                "desc": "The request URI string sent (ex: `GET /services/async/38.0/job HTTP/1.1`)",
            },
            "request-headers": {
                "type": HashType,
                "desc": "Hash of outgoing HTTP request headers",
            },
            "request-serialization": {
                "type": StringType,
                "desc": "The message serialization used in the request body",
            },
            "response-code": {
                "type": IntType,
                "desc": "The HTTP response code",
            },
            "response-uri": {
                "type": StringType,
                "desc": "The HTTP response URI",
            },
            "response-headers": {
                "type": HashType,
                "desc": "A hash of processed incoming HTTP headers in the response with keys converted to lower case "
                    "and with additional information added",
            },
            "response-serialization": {
                "type": StringType,
                "desc": "The message serialization used in the response body",
            },
            "response-chunked": {
                "type": BoolType,
                "desc": "`true` if the response body was sent chunked",
            },
        };
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            Fields.pairIterator();
    }
}
}
