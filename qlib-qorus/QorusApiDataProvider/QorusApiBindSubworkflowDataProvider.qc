# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiBindSubworkflowDataProvider class definition

/** QorusApiBindSubworkflowDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the bind subworkflow API
public class QorusApiBindSubworkflowDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiBindSubworkflowDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiBindSubworkflowRequestDataType();

        #! Response type
        const ResponseType = new QorusApiBindSubworkflowResponseDataType();
    }

    #! Returns the name of the data provider
    string getName() {
        return "bind-subworkflow";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: binds a subworkflow order to the current subworkflow step; the "
            "`staticdata` key is required to be set; it can be an empty hash if the workflow does not require any "
            "static data\n\n"
            "This API call can only be made internally in Qorus and also only in a subworkflow step.\n\n";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        if (req.workflow.find(":") > 0) {
            (req.workflow, req.version) = (req.workflow =~ x/([^:]+):(.*)$/);
        }
        return UserApi::bindSubworkflow(req{"workflow", "version"}, req - ("workflow", "version"));
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
public class QorusApiBindSubworkflowRequestDataType inherits QorusApiCreateOrderDataType {
    private {
        #! Field descriptions
        const Fields = QorusApiCreateOrderDataType::Fields - "status";
    }

    #! Return fields
    private hash<auto> getInitFields() {
        return Fields;
    }
}

#! Data type for create order API responses
public class QorusApiBindSubworkflowResponseDataType inherits QorusApiCreateOrderResponseDataType {
    private {
        #! Field descriptions
        const Fields = QorusApiCreateOrderResponseDataType::Fields - "duplicate";
    }

    #! Return fields
    private hash<auto> getInitFields() {
        return Fields;
    }
}
}
