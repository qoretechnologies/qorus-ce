# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiDisableWorkflowDataProvider class definition

/** QorusApiDisableWorkflowDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the disable workflow API
public class QorusApiDisableWorkflowDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiDisableWorkflowDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiDisableWorkflowRequestDataType();

        #! Response type
        const ResponseType = new QorusApiDisableWorkflowResponseDataType();
    }

    #! Returns the name of the data provider
    string getName() {
        return "disable";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: disable the given workflow";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        return UserApi::callRestApi("PUT", "workflows/" + req.workflow + "/disable");
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
public class QorusApiDisableWorkflowRequestDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "workflow": {
                "type": SoftStringType,
                "desc": "the workflow ID or name (or name:version string)",
            },
        };
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            Fields.pairIterator();
    }
}

#! Data type for create order API responses
public class QorusApiDisableWorkflowResponseDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = (
            "name": {
                "type": StringType,
                "desc": "The workflow name",
            },
            "version": {
                "type": StringType,
                "desc": "The workflow version",
            },
            "workflowid": {
                "type": IntType,
                "desc": "The workflow ID",
            },
            "info": {
                "type": StringType,
                "desc": "A descriptive string giving the status of the operation",
            },
        );
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            Fields.pairIterator();
    }
}
}
