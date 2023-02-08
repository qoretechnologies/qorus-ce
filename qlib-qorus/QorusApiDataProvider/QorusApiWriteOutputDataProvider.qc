# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiWriteOutputDataProvider class definition

/** QorusApiWriteOutputDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the write output data API
public class QorusApiWriteOutputDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiWriteOutputDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = AbstractDataProviderType::get(HashOrNothingType);

        #! Response type
        const ResponseType = AbstractDataProviderType::get(NothingType);
    }

    #! Returns the name of the data provider
    string getName() {
        return "write-output";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: Writes output data to locations provided by the argument, which must "
            "be a hash where keys provide values to be stored; each key is subject to template substitution with "
            "`UserApi::expandTemplatedValue()`; hash values provide the locations to store the values in.\n\n"
            "Example: `\\$local:input: \\$dynamic:account`\n\n"
            "This above value would result in input data being stored in workflow dynamic data when executed in a "
            "workflow context.\n\n"
            "Note:\n"
            "- \\$local:input represents input data\n"
            "- Escape all `$` signs so they are evaluated by the API call and not during standard template "
            "evaluation of API call arguments by Qorus itself";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        UserApi::writeOutputData(req);
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
