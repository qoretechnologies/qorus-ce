# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiExecAsynchronousImplicitWorkflowDataProvider class definition

/** QorusApiExecAsynchronousImplicitWorkflowDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the exec asynchronous workflow API
public class QorusApiExecAsynchronousImplicitWorkflowDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiExecAsynchronousImplicitWorkflowDataProvider",
            "supports_request": True,
            "constructor_options": ConstructorOptions,
        };

        #! Constructor options
        const ConstructorOptions = {
            "wfid": <DataProviderOptionInfo>{
                "type": (
                    AbstractDataProviderType::get(IntType),
                ),
                "desc": "the workflow ID",
                "required": True,
            },
        };

        #! The workflow ID
        int wfid;
    }

    constructor(int wfid) {
        self.wfid = wfid;
    }

    #! Creates the object from constructor options
    constructor(*hash<auto> options) {
        *hash<auto> copts = checkOptions("CONSTRUCTOR-ERROR", ConstructorOptions, options);
        wfid = copts.wfid;
    }

    #! Returns the name of the data provider
    string getName() {
        return "exec-async";
    }

    #! Returns the data provider description
    *string getDesc() {
        return sprintf("Request/response data provider: set workflow `%s` autostart to the given value", wfid);
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        try {
            hash<auto> rv = UserApi::callRestApi("POST", "workflows/" + wfid + "/execSynchronousAsync", req);
            return rv + {
                "duplicate": False,
            };
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "DUPLICATE-ORDER-KEY") {
                softint wfiid = ex.arg.workflow_instance_ids[0];
                return {
                    "workflow_instanceid": wfiid,
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
        return QorusApiExecSynchronousImplicitWorkflowDataProvider::RequestType;
    }

    #! Returns the description of a response message, if this object represents a response message
    /** @return the response type for this response message
    */
    private *AbstractDataProviderType getResponseTypeImpl() {
        return QorusApiExecAsynchronousWorkflowDataProvider::ResponseType;
    }

    #! Returns data provider static info
    hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }
}
}
