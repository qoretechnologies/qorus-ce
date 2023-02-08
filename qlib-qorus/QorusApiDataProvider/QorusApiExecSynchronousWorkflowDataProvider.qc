# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiExecSynchronousWorkflowDataProvider class definition

/** QorusApiExecSynchronousWorkflowDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the exec synchronous workflow API
public class QorusApiExecSynchronousWorkflowDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiExecSynchronousWorkflowDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiExecSynchronousWorkflowRequestDataType();

        #! Response type
        const ResponseType = new QorusApiExecSynchronousWorkflowResponseDataType();
    }

    #! Returns the name of the data provider
    string getName() {
        return "exec-sync";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: execute a synchronous order for the given workflow and return the "
            "results";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        try {
            hash<auto> rv = UserApi::callRestApi("POST", "workflows/" + req.workflow + "/execSynchronous", req -
                "workflow");
            return rv + {
                "duplicate": False,
            };
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "DUPLICATE-ORDER-KEY") {
                softint wfiid = ex.arg.workflow_instance_ids[0];
                hash<auto> info = UserApi::callRestApi("GET", "orders/" + wfiid);
                return {
                    "workflow_instanceid": wfiid,
                    "status": info.workflowstatus,
                    "dynamicdata": info.dynamicdata,
                    "duplicate": True,
                };
            }
            rethrow;
        }
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

#! Data type for exec synchronous workflow calls
public class QorusApiExecSynchronousWorkflowRequestDataType inherits QorusApiCreateOrderDataType {
    private {
        #! Field descriptions
        const Fields = QorusApiCreateOrderDataType::Fields - "scheduled";
    }

    #! Return fields
    private hash<auto> getInitFields() {
        return Fields;
    }
}

#! Data type for exec synchronous workflow calls
public class QorusApiExecSynchronousWorkflowErrorKeyType inherits HashDataType {
    public {
        #! Field descriptions
        const Fields = {
            "error": {
                "type": StringType,
                "dedsc": "The error code",
            },
            "description": {
                "type": StringOrNothingType,
                "desc": "The description of the error",
            },
            "info": {
                "type": StringOrNothingType,
                "desc": "Additional information about the error",
            },
        };
    }

    #! Creates the object
    constructor() : HashDataType(new Type("*hash<string, hash<auto>>")) {
    }
}

#! Data type for exec synchronous workflow API responses
public class QorusApiExecSynchronousWorkflowResponseDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "workflow_instanceid": {
                "type": SoftIntType,
                "desc": "the workflow_instanceid for the order",
            },
            "status": {
                "type": StringType,
                "desc": "the workflow order's status when processing terminates",
            },
            "dynamicdata": {
                "type": HashOrNothingType,
                "desc": "the dynamic data for the workflow order, if any",
            },
            "error": {
                "type": new QorusApiExecSynchronousWorkflowErrorKeyType(),
                "desc": "error information, if any",
            },
            "duplicate": {
                "type": BoolType,
                "desc": "a flag indicating if the order already existed or not",
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
