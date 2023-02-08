# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiCreateDataProvider class definition

/** QorusApiCreateDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the data provider create API
public class QorusApiCreateDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiCreateDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiCreateRequestDataType();

        #! Response type
        const ResponseType = AbstractDataProviderType::anyDataType;
    }

    #! Returns the name of the data provider
    string getName() {
        return "create";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: performs a record create action in the given data provider and "
            "returns the record(s) created as output data.\n\n"
            "The return value is no value if no records were created, a single hash of the record created when a "
            "single record is created, or a list of hashes of the records created when more than one record is "
            "created.";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()
        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        UserApi::logDebug("provider: %y (upsert: %y) input record data: %y", req."provider-path", req.upsert,
            req."record-data");
        # return immediately if there is no record data to create
        if (!req."record-data") {
            return;
        }

        bool output_list;

        # check input_data type
        if (req."record-data".typeCode() == NT_LIST) {
            if (req."record-data"[0].typeCode() != NT_HASH) {
                inputTypeError(req."record-data");
            }
            if (req."record-data".lsize() == 1) {
                req."record-data" = req."record-data"[0];
            } else {
                UserApi::logInfo("QorusApiCreateDataProvider: processing %d elements in the input data",
                    req."record-data".lsize());
                output_list = True;
            }
        } else if (req."record-data".typeCode() != NT_HASH) {
            inputTypeError(req."record-data");
        }

        AbstractDataProvider provider = UserApi::getDataProvider(req."provider-path");
        # ensure that it supports the appropriate API
        if (req.upsert) {
            provider.checkUpsert();
        } else {
            provider.checkCreate();
        }

        auto output_record_data;
        foreach hash<auto> input_record in (req."record-data") {
            UserApi::logDebug("QorusApiCreateDataProvider: provider %y: RECORD: %y options: %y", provider.getName(),
                input_record, req."create-options");
            *hash<auto> output_record;
            try {
                if (req.upsert) {
                    string result = provider.upsertRecord(input_record, req."create-options");
                    UserApi::logDebug("QorusApiCreateDataProvider: upsert result: %y rec: %y", result, input_record);
                    output_record = input_record;
                } else {
                    output_record = provider.createRecord(input_record, req."create-options");
                }
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "DUPLICATE-RECORD" &&
                    req."dupicate-handling" == "SUCCESS" && ex.arg) {
                    UserApi::logInfo("QorusApiCreateDataProvider: duplicate record found; arg: %y", ex.arg);
                    output_record = ex.arg;
                } else {
                    UserApi::logError("QorusApiCreateDataProvider: error inserting record: %y", input_record);
                    rethrow;
                }
            }
            UserApi::logDebug("QorusApiCreateDataProvider: OUTPUT RECORD: %N", output_record);
            if (output_list) {
                if (!output_record_data) {
                    output_record_data = ();
                }
                output_record_data += output_record;
            } else {
                output_record_data = output_record;
            }
        }

        # save output data unconditionally if a record is available
        *hash<auto> output_data = req."output-data";
        if (output_data) {
            UserApi::updateOutputData({"records": output_record_data}, output_data);
        }

        return output_record_data;
    }

    #! Throws an error for invalid input
    static private inputTypeError(auto input_data) {
        throw "INVALID-INPUT", sprintf("input data has type %y; must have \"list of hash\" or \"hash\" format",
            input_data.type());
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
public class QorusApiCreateRequestDataType inherits HashDataType {
    public {
        #! Field descriptions
        const Fields = {
            "provider-path": {
                "type": DataProviderType,
                "desc": "A path to a data provider that supports record creation",
                "required": True,
            },
            "record-data": {
                "type": SoftListOrNothingType,
                "desc": "The hash or list of hashes of the record(s) to create; if this is missing or empty, then no "
                    "records are created",
            },
            "create-options": {
                "type": HashOrNothingType,
                "desc": "An optional hash giving create options",
            },
            "upsert": {
                "type": BoolType,
                "desc": "If `true` then upsert operations are used instead of create operations.",
                "default_value": False,
            },
            "duplicate-handling": {
                "type": StringType,
                "desc": "Determines how calls with duplicate errors should be handled:
- `SUCCESS`: the call succeeds
- `DUPLICATE`: the `DUPLICATE-ERROR` exception is rethrown",
                "default_value": "SUCCESS",
                "allowed_values": ("SUCCESS", "DUPLICATE"),
            },
            "output-data": {
                "type": HashOrNothingType,
                "desc": "Can be used to write the record(s) created in an output location.\n\n"
                    "Records created can be accessed in the `records` key of the hash passed as input to "
                    "`UserApi::updateOutputData()`.\n\n"
                    "Example: `records: $dynamic:records`: to store the records created in workflow dynamic "
                    "data when executed in a workflow context.",
            },
        };
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value,
            $1.value.allowed_values)), Fields.pairIterator();
    }
}
}
