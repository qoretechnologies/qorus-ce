# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiSearchDataProvider class definition

/** QorusApiSearchDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the data provider search API
public class QorusApiSearchDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiSearchDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiSearchRequestDataType();

        #! Response type
        const ResponseType = AbstractDataProviderType::get(ListOrNothingType);
    }

    #! Returns the name of the data provider
    string getName() {
        return "search";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: performs a search in the given data provider and returns the results "
            "as output data.\n\n"
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
        AbstractDataProvider prov = UserApi::getDataProvider(req."provider-path");
        prov.checkRead();

        int retries = req.retries ?? QorusApiSearchRequestDataType::Fields."retries".default_value;
        if (retries < 0) {
            retries = 0;
        }
        int retry_delay_secs = req."retry-delay" ?? QorusApiSearchRequestDataType::Fields."retry-delay".default_value;
        if (retries > 0 && retry_delay_secs < 0) {
            retry_delay_secs = 0;
        }

        # get all records from search
        softlist<hash<auto>> records;
        int retry_count = 0;
        while (True) {
            try {
                records = map $1, prov.searchRecords(req."where", req."search-options");
                break;
            } catch (hash<ExceptionInfo> ex) {
                if (retries && isConnectionIoError(req, ex)) {
                    if (retry_count == retries) {
                        UserApi::logError("QorusApiSearchDataProvider: %s: %s: maximum retries reached (%d), not "
                            "retrying again", ex.err, ex.desc, retries);
                    } else {
                        ++retry_count;
                        UserApi::logInfo("QorusApiSearchDataProvider: %s: %s: waiting %d second%s for retry...",
                            ex.err, ex.desc, retry_delay_secs, retry_delay_secs == 1 ? "" : "s");
                        UserApi::sleep(retry_delay_secs);
                        UserApi::logInfo("QorusApiSearchDataProvider: retrying search action now");
                        continue;
                    }
                }
                rethrow;
            }
        }

        UserApi::logInfo("QorusApiSearchDataProvider: records retrieved: %d", records.size());
        UserApi::logDebug("QorusApiSearchDataProvider: RECORDS: %N", records);

        if (!records && req."requires-result") {
            throw "SEARCH-ERROR", sprintf("QorusApiSearchDataProvider: arguments indicates that a search result is "
                "required, but none was returned; provider: %y search criteria: %y search options: %y",
                req."provider-path", req."where", req."search-options");
        }

        # save output data unconditionally if a record is available
        *hash<auto> output_data = req."output-data";
        if (output_data) {
            UserApi::updateOutputData({"records": records}, output_data);
        }

        return records;
    }

    #! Returns True if the error is a connection I/O error
    private static bool isConnectionIoError(hash<auto> req, hash<ExceptionInfo> ex) {
        *hash<string, bool> errmap = map {$1: True}, req."retry-errors";
        bool rv = errmap{ex.err} ?? False;
        UserApi::logDebug("QorusApiSearchDataProvider: %y I/O error: %y", ex.err, rv);
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

#! Data type for create order calls
public class QorusApiSearchRequestDataType inherits HashDataType {
    public {
        #! Field descriptions
        const Fields = {
            "provider-path": {
                "type": DataProviderType,
                "desc": "A path to a data provider that supports searches",
                "required": True,
            },
            "where": {
                "type": HashOrNothingType,
                "desc": "An optional hash giving search criteria",
            },
            "search-options": {
                "type": HashOrNothingType,
                "desc": "An optional hash giving search options",
            },
            "requires-result": {
                "type": BoolType,
                "desc": "An optional hash giving search options",
                "default_value": False,
            },
            "output-data": {
                "type": HashOrNothingType,
                "desc": "Can be used to write records retrieved in an output location.\n\n"
                    "Records retrieved can be accessed in the `records` key of the hash passed as input to "
                    "`UserApi::updateOutputData()`.\n\n"
                    "Example: `records: $dynamic:records`: to store the records retrieved in workflow dynamic "
                    "data when executed in a workflow context.",
            },
            "retries": {
                "type": IntType,
                "desc": "Number of times a search action will be retried if a connection error is encountered; if "
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
                "desc": "The list of error codes that result in a retry of the search operation if `retries` > 0",
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
}
