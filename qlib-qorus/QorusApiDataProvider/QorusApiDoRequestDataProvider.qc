# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiDoRequestDataProvider class definition

/** QorusApiDoRequestDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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

#! contains all public definitions in the QorusApiDataProvider module
public namespace QorusApiDataProvider {
#! The Qorus API data provider for the data provider do request API
public class QorusApiDoRequestDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiDoRequestDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiDoRequestRequestDataType();

        #! Response type
        const ResponseType = AbstractDataProviderType::anyDataType;
    }

    #! Returns the name of the data provider
    string getName() {
        return "do-request";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: performs an API call (request action) in the given data provider and "
            "returns the API response as output data.\n\n"
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

        UserApi::logInfo("QorusApiDoRequestDataProvider: do-request provider: %y arg: %y opts: %y",
            req."provider-path", req.arg, req."request-options");

        AbstractDataProvider prov = UserApi::getDataProvider(req."provider-path");
        prov.checkRequest();

        # remove null args from the request body if applicable
        if (req."remove-nulls" && req.arg.typeCode() == NT_HASH) {
            req.arg -= (map $1.key, req.arg.pairIterator(), !$1.value.val());
        }

        auto response;
        # process lists appropriately
        if (req.arg.typeCode() == NT_LIST && !prov.getRequestType().getAcceptTypeHash(){Type::List}) {
            response = ();
            foreach auto elem in (req.arg) {
                auto res = doRequestIntern(prov, elem, req, retries, retry_delay_secs);
                UserApi::logDebug("QorusApiDoRequestDataProvider: elem %d/%d: RESPONSE: %N", $# + 1, req.arg.lsize(), res);
                response += res;
            }
        } else {
            response = doRequestIntern(prov, req.arg, req, retries, retry_delay_secs);
            UserApi::logDebug("QorusApiDoRequestDataProvider: RESPONSE: %N", response);
        }

       *string id_loc = req."id-location";
        auto val;
        if (exists id_loc) {
            if (id_loc == "-") {
                val = response;
            } else {
                if (response.typeCode() != NT_HASH) {
                    throw "DATA-PROVIDER-RESPONSE-ERROR", sprintf("\"id-location\" is set to %y, but the response is "
                        "not a hash (type: %y)", id_loc, response.type());
                }
                val = UserApi::getHashDotValue(response, id_loc);
            }
            if (!exists val) {
                throw "DATA-PROVIDER-RESPONSE-MISSING", sprintf("no value was found in the response at location %y; "
                    "response: %y", id_loc, response);
            }
            UserApi::logInfo(req."id-log-msg", val);
        }

        # save output data
        *hash<auto> output_data = req."output-data";
        if (output_data) {
            UserApi::updateOutputData({"response": response}, output_data);
        }

        return response;
    }

    #! Performs a request
    auto doRequestIntern(AbstractDataProvider prov, auto arg, hash<auto> req, int retries, int retry_delay_secs) {
        auto res;
        int retry_count = 0;
        while (True) {
            try {
                res = prov.doRequest(arg, req."request-options");
                break;
            } catch (hash<ExceptionInfo> ex) {
                if (retries && isConnectionIoError(req, ex)) {
                    if (retry_count == retries) {
                        UserApi::logError("QorusApiDoRequestDataProvider: %s: %s: maximum retries reached (%d), not "
                            "retrying again", ex.err, ex.desc, retries);
                    } else {
                        ++retry_count;
                        UserApi::logInfo("QorusApiDoRequestDataProvider: %s: %s: waiting %d second%s for retry...",
                            ex.err, ex.desc, retry_delay_secs, retry_delay_secs == 1 ? "" : "s");
                        UserApi::sleep(retry_delay_secs);
                        UserApi::logInfo("QorusApiDoRequestDataProvider: retrying the request action now");
                        continue;
                    }
                }
                rethrow;
            }
        }
        return res;
    }

    #! Returns True if the error is a connection I/O error
    private static bool isConnectionIoError(hash<auto> req, hash<ExceptionInfo> ex) {
        *hash<string, bool> errmap = map {$1: True}, req."retry-errors";
        bool rv = errmap{ex.err} ?? False;
        UserApi::logDebug("QorusApiDoRequestDataProvider: %y I/O error: %y", ex.err, rv);
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

#! Data type for do request calls
public class QorusApiDoRequestRequestDataType inherits HashDataType {
    public {
        #! Field descriptions
        const Fields = {
            "provider-path": {
                "type": DataProviderType,
                "desc": "A path to a data provider that supports record creation",
                "required": True,
            },
            "arg": {
                "type": AutoType,
                "desc": "The request message or argument",
                "required": True,
            },
            "request-options": {
                "type": HashOrNothingType,
                "desc": "An optional hash giving request options",
            },
            "id-location": {
                "type": StringOrNothingType,
                "desc": "The location in the response for a response message ID; `-` means the entire response is "
                "the ID; if this argument has a value, and no value is found in the response at the location given, "
                "an exception is thrown",
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
                    "The response message can be found in the `response` key of the hash value passed to "
                    "`UserApi::updateOutputData()`.\n\n"
                    "Example: `response: $dynamic:record`: to store the response value in workflow dynamic "
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
                "desc": "The list of error codes that result in a retry of the request operation if `retries` > 0",
                "default_value": (
                    "SOCKET-CONNECT-ERROR",
                    "SOCKET-CLOSED",
                ),
            },
        };
    }

    #! creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            Fields.pairIterator();
    }
}
}
