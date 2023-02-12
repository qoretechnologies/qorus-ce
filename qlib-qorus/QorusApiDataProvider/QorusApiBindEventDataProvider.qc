# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiBindEventDataProvider class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html


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
#! The Qorus API data provider for the bind event API
public class QorusApiBindEventDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiBindEventDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiBindEventRequestDataType();

        #! Response type
        const ResponseType = AbstractDataProviderType::get(NothingType);
    }

    #! Returns the name of the data provider
    string getName() {
        return "bind-event";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: binds a workflow synchronization event key to the current workflow "
            "synchronization event step.\n\n"
            "This API call can only be made internally in Qorus and also only in a workflow synchronization event "
            "step.\n\n";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        UserApi::bindEvent(req.key);
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
public class QorusApiBindEventRequestDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "key": {
                "type": StringType,
                "desc": "The workflow synchronization event key to bind to the step",
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
