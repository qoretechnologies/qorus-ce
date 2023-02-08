# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiServiceInfoDataProvider class definition

/** QorusApiServiceInfoDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the service info API
public class QorusApiServiceInfoDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiServiceInfoDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiServiceInfoRequestDataType();

        #! Response type
        const ResponseType = new QorusApiServiceInfoResponseDataType();
    }

    #! Returns the name of the data provider
    string getName() {
        return "info";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: return information about the given service";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        return UserApi::callRestApi("GET", "services/" + req.service);
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
public class QorusApiServiceInfoRequestDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "service": {
                "type": ServiceType,
                "desc": "the service ID or name",
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
public class QorusApiServiceInfoResponseDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = (
            "serviceid": {
                "type": IntType,
                "desc": "The service ID",
            },
            "type": {
                "type": StringType,
                "desc": "The service type",
            },
            "name": {
                "type": StringType,
                "desc": "The service name",
            },
            "version": {
                "type": StringType,
                "desc": "The service version",
            },
            "description": {
                "type": StringOrNothingType,
                "desc": "The service description",
            },
            "author": {
                "type": StringOrNothingType,
                "desc": "The service author",
            },
            "language": {
                "type": StringType,
                "desc": "The language any service-level code is written in",
            },
            "class_source": {
                "type": StringOrNothingType,
                "desc": "The source code for class-based services",
            },
            "class_name": {
                "type": StringOrNothingType,
                "desc": "The class name for class-based services",
            },
            "remote": {
                "type": BoolType,
                "desc": "If the service runs in a remote qwf process or not",
            },
            "manual_remote": {
                "type": BoolType,
                "desc": "If the service remote status was set with the API or UI",
            },
            "autostart": {
                "type": BoolType,
                "desc": "If the service should be started automatically when Qorus starts",
            },
            "manual_autostart": {
                "type": BoolType,
                "desc": "IIf the service autostart status was set with the API or UIs",
            },
            "enabled": {
                "type": BoolType,
                "desc": "If the service is enabled",
            },
            "created": {
                "type": DateType,
                "desc": "The creation timestamp for the service",
            },
            "modified": {
                "type": DateOrNothingType,
                "desc": "The modified timestamp for the service",
            },
            "class_based": {
                "type": BoolType,
                "desc": "If the service has a service class",
            },
            "mappers": {
                "type": ListOrNothingType,
                "desc": "A list of mappers associated to the service, if any",
            },
            "vmaps": {
                "type": ListOrNothingType,
                "desc": "A list of value maps associated to the service, if any",
            },
            "fsm_triggers": {
                "type": HashOrNothingType,
                "desc": "A hash of FSM triggers keyed by FSM name",
            },
            "config": {
                "type": HashOrNothingType,
                "desc": "A hash of config items that can be set on the service keyed by config item name",
            },
            "latest": {
                "type": BoolType,
                "desc": "If the service is the latest version in the system by its creation date",
            },
            "methods": {
                "type": ListType,
                "desc": "A list of service method hashes",
            },
            "method_name_map": {
                "type": HashType,
                "desc": "A hash of method names to method IDs",
            },
            "tags": {
                "type": HashOrNothingType,
                "desc": "A hash of tags associated with the service",
            },
            "lib": {
                "type": HashOrNothingType,
                "desc": "A hash of library information (associated code and interface objects) for the service",
            },
            "groups": {
                "type": ListType,
                "desc": "A list of zero or more groups that the current service is specified in",
            },
            "resource_files": {
                "type": ListType,
                "desc": "A list of resource file hashes",
            },
            "apiver": {
                "type": IntType,
                "desc": "the REST API version serving the request",
            },
            "options": {
                "type": ListOrNothingType,
                "desc": "A list of service option hashes, if the service supports any",
            },
            "status": {
                "type": StringType,
                "desc": "The service status",
            },
            "connections": {
                "type": ListType,
                "desc": "A list of zero or more connections used by the service",
            },
            "alerts": {
                "type": ListType,
                "desc": "A list of zero or more alerts raised against the service",
            },
            "state": {
                "type": HashOrNothingType,
                "desc": "A hash of service state date, if any",
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
