# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiDeleteDataProvider class definition

/** QorusApiDeleteDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the data provider delete API
public class QorusApiDeleteDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiDeleteDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiDeleteRequestDataType();

        #! Response type
        const ResponseType = new QorusApiDeleteResponseDataType();
    }

    #! Returns the name of the data provider
    string getName() {
        return "delete";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: performs a record delete action in the given data provider and "
            "returns the number of records deleted as output data.\n\n"
            "This API also includes arguments that allow it to do inline recoveries from technical errors; by "
            "default up to 3 retries are made up to 5 seconds apart; see the `retries`, `retry-delay`, and "
            "`retry-errors` arguments.";
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

        UserApi::logInfo("QorusApiDeleteDataProvider: delete provider: %y where: %y search opts: %y",
            req."provider-path", req."where", req."search-options");

        AbstractDataProvider prov = UserApi::getDataProvider(req."provider-path");
        prov.checkDelete();

        int rc;
        int retry_count = 0;
        while (True) {
            try {
                rc = prov.deleteRecords(req."where", req."search-options");
                break;
            } catch (hash<ExceptionInfo> ex) {
                if (retries && isConnectionIoError(req, ex)) {
                    if (retry_count == retries) {
                        UserApi::logError("QorusApiDeleteDataProvider: %s: %s: maximum retries reached (%d), not "
                            "retrying again", ex.err, ex.desc, retries);
                    } else {
                        ++retry_count;
                        UserApi::logInfo("QorusApiDeleteDataProvider: %s: %s: waiting %d second%s for retry...",
                            ex.err, ex.desc, retry_delay_secs, retry_delay_secs == 1 ? "" : "s");
                        UserApi::sleep(retry_delay_secs);
                        UserApi::logInfo("QorusApiDeleteDataProvider: retrying delete action now");
                        continue;
                    }
                }
                rethrow;
            }
        }

        UserApi::logInfo("QorusApiDeleteDataProvider: records deleted: %d", rc);

        # save output data
        *hash<auto> output_data = req."output-data";
        if (output_data) {
            UserApi::updateOutputData({"count": rc}, output_data);
        }

        return {"records-deleted": rc};
    }

    #! Returns True if the error is a connection I/O error
    private static bool isConnectionIoError(hash<auto> req, hash<ExceptionInfo> ex) {
        *hash<string, bool> errmap = map {$1: True}, req."retry-errors";
        bool rv = errmap{ex.err} ?? False;
        UserApi::logDebug("QorusApiDeleteDataProvider: %y I/O error: %y", ex.err, rv);
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

#! Data type for delete order calls
public class QorusApiDeleteRequestDataType inherits HashDataType {
    public {
        #! Field descriptions
        const Fields = {
            "provider-path": {
                "type": DataProviderType,
                "desc": "A path to a data provider that supports record creation",
                "required": True,
            },
            "where": {
                "type": HashType,
                "desc": "The hash identifying the records to delete; if this hash is empty, then all records in the "
                    "data provider will be deleted",
                "required": True,
            },
            "search-options": {
                "type": HashOrNothingType,
                "desc": "An optional hash giving search options",
            },
            "output-data": {
                "type": HashOrNothingType,
                "desc": "Can be used to write the record count to an output location.\n\n"
                    "A hash with a `count` key giving the record count will be passed in the call to "
                    "`UserApi::updateOutputData()`.\n\n"
                    "Example: `count: $dynamic:count`: to store the record count in workflow dynamic "
                    "data when executed in a workflow context.",
            },
            "retries": {
                "type": IntType,
                "desc": "Number of times an delete action will be retried if a connection error is encountered; if "
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
                "desc": "The list of error codes that result in a retry of the delete operation if `retries` > 0",
                "default_value": (
                    "SOCKET-CONNECT-ERROR",
                    "SOCKET-CLOSED",
                ),
            },
        };
    }

    #! Deletes the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            Fields.pairIterator();
    }
}

#! Data type for delete order call responses
public class QorusApiDeleteResponseDataType inherits HashDataType {
    public {
        #! Field descriptions
        const Fields = {
            "records-deleted": {
                "type": IntType,
                "desc": "Returns the number of records deleted",
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
