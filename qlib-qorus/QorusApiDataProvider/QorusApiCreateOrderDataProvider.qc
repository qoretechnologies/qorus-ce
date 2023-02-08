# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiCreateOrderDataProvider class definition

/** QorusApiCreateOrderDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the create order API
public class QorusApiCreateOrderDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiCreateOrderDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiCreateOrderDataType();

        #! Response type
        const ResponseType = new QorusApiCreateOrderResponseDataType();
    }

    #! Returns the name of the data provider
    string getName() {
        return "create-order";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: create a workflow order for the given workflow; the `staticdata` key "
            "is required to be set; it can be an empty hash if the workflow does not require any static data";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        try {
            if (req.workflow.find(":") > 0) {
                (req.workflow, req.version) = (req.workflow =~ x/([^:]+):(.*)$/);
            }
            int wfiid = UserApi::createOrder(req.workflow, req.version, req - ("workflow", "status"), req.status);
            return {
                "workflow_instanceid": wfiid,
                "duplicate": False,
            };
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "DUPLICATE-ORDER-KEY") {
                return {
                    "workflow_instanceid": ex.arg.workflow_instance_ids[0],
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
}
