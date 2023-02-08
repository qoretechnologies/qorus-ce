# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore RemoteApiDataProvider class definition

/** RemoteApiDataProvider.qc Copyright 2023 Qore Technologies, s.r.o.

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

#! contains all public definitions in the RemoteApiProvider module
public namespace RemoteApiProvider {
#! The remote Qorus API data provider class, provides remote Qorus API endpoints as children
public class RemoteApiDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "RemoteApiDataProvider",
            "supports_children": True,
            "constructor_options": ConstructorOptions,
        };

        #! Constructor options
        const ConstructorOptions = RemoteApiProvider::ConstructorOptions + {
            "path": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(StringType),
                "desc": "the path to the remote data provider",
                "required": True,
            },
        };

        const WorkflowDataType = new QoreStringDataTypeBase(new WrapperType("workflow", "string"));
        const ServiceDataType = new QoreStringDataTypeBase(new WrapperType("service", "string"));
        const JobDataType = new QoreStringDataTypeBase(new WrapperType("job", "string"));
        const DataProviderDataType = new QoreStringDataTypeBase(new WrapperType("data-provider", "string"));
        const ConnectionDataType = new QoreStringDataTypeBase(new WrapperType("connection", "string"));
        const MapperDataType = new QoreStringDataTypeBase(new WrapperType("mapper", "string"));
        const ValueMapDataType = new QoreStringDataTypeBase(new WrapperType("value-map", "string"));

        const WorkflowOrNothingDataType = new QoreStringDataTypeBase(new WrapperType("workflow", "*string"));
        const ServiceOrNothingDataType = new QoreStringDataTypeBase(new WrapperType("service", "*string"));
        const JobOrNothingDataType = new QoreStringDataTypeBase(new WrapperType("job", "*string"));
        const DataProviderOrNothingDataType = new QoreStringDataTypeBase(new WrapperType("data-provider", "*string"));
        const ConnectionOrNothingDataType = new QoreStringDataTypeBase(new WrapperType("connection", "*string"));
        const MapperOrNothingDataType = new QoreStringDataTypeBase(new WrapperType("mapper", "*string"));
        const ValueMapOrNothingDataType = new QoreStringDataTypeBase(new WrapperType("value-map", "*string"));
    }

    private {
        #! The remote connection name
        string remote;

        #! The remote connection
        QorusSystemRestHelper qrest;

        #! The path to the API
        string path;
    }

    #! creates the object
    constructor(string remote, QorusSystemRestHelper qrest, string path) {
        self.remote = remote;
        self.qrest = qrest;
        self.path = path;
    }

    #! Creates the object from constructor options
    constructor(*hash<auto> options) {
        *hash<auto> copts = checkOptions("CONSTRUCTOR-ERROR", ConstructorOptions, options);
        remote = copts.remote;
        qrest = new QorusSystemRestHelper(copts.remote);
        path = copts.path;
    }

    #! Returns the remote connection name
    string getName() {
        return basename(path);
    }

    #! Returns the data provider description
    *string getDesc() {
        return sprintf("Data provider providing access to remote Qorus instance `%s` with URL `%s` handling path "
            "`%s`", remote, qrest.getSafeURL(), path);
    }

    *list<hash<DataProviderSummaryInfo>> getChildProviderSummaryInfo() {
        return map cast<hash<DataProviderSummaryInfo>>($1), qrest.get(getUriPath() + "?action=childDetails").children;
    }

    #! Returns a list of child data provider names
    /** @return a list of child data provider names
    */
    private *list<string> getChildProviderNamesImpl() {
        return cast<*list<string>>(qrest.get(getUriPath() + "children"));
    }

    #! Returns the given child provider or @ref nothing if the given child is unknown
    /** @return the given child provider or @ref nothing if the given child is unknown

        @throw CHILD-PROVIDER-ERROR error acquiring child provider

        @see getChildProviderEx()
    */
    private *DataProvider::AbstractDataProvider getChildProviderImpl(string name) {
        if (name == "childDetails") {
            return;
        }
        try {
            *hash<auto> h = qrest.get(getUriPath() + name);
            # heuristic to ensure that we are really dealing with a data provider info response
            if (!h.name || !h.type || !h.hasKey("mapper_keys") || !h.hasKey("supports_read") || !h.hasKey("children")
                || !h.hasKey("supports_search_expressions")) {
                return;
            }
        } catch (hash<ExceptionInfo> ex) {
            if ((ex.err == "DATASTREAM-CLIENT-RECEIVE-ERROR" && ex.arg.status_code == 404) ||
                ex.err == "RUNTIME-TYPE-ERROR") {
                return;
            }
            rethrow "CHILD-PROVIDER-ERROR", sprintf("%s: %s", ex.err, ex.desc);
        }
        return new RemoteApiDataProvider(remote, qrest, path + "/" + name);
    }

    #! Returns data provider static info
    private hash<DataProvider::DataProviderInfo> getStaticInfoImpl() {
        hash<auto> info = qrest.get(getUriPath());
        hash<DataProviderInfo> rv();
        if (info.mapper_keys) {
            rv.mapper_keys = map {$1.key: cast<hash<MapperRuntimeKeyInfo>>($1.value)},
                (remove info.mapper_keys).pairIterator();
        }
        on_error rethrow $1.err, sprintf("%s: uri path: %y info: %y", $1.desc, getUriPath(), info);
        map rv{$1.key} = $1.value, info.pairIterator();
        return rv;
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        return qrest.post(getUriPath() + "request", {"request_options": req});
    }

    #! Returns the description of a successful request message, if any
    /** @return the request type for this provider

        @note only called if the provider supports the request / response API
    */
    private *DataProvider::AbstractDataProviderType getRequestTypeImpl() {
        return getTypeFromInfo(qrest.get(getUriPath() + "request"));
    }

    #! Returns the description of a response message, if this object represents a response message
    /** @return the response type for this response message

        @note only called if the provider supports the request / response API
    */
    private *DataProvider::AbstractDataProviderType getResponseTypeImpl() {
        return getTypeFromInfo(qrest.get(getUriPath() + "response"));
    }

    #! Returns the URI path segment for this provider
    private string getUriPath() {
        return "dataprovider/factories/qorus-api/provider/" + path + "/";
    }

    #! Returns a type object from a type description hash
    static *DataProvider::AbstractDataProviderType getTypeFromInfo(*hash<auto> info) {
        if (!info) {
            return;
        }

        switch (info.name) {
            case "hash<auto>":
                return RemoteApiDataProvider::getHashTypeFromInfo(info);

            case "workflow":
                return WorkflowDataType;

            case "service":
                return ServiceDataType;

            case "job":
                return JobDataType;

            default:
                return AbstractDataProviderType::get(info.name, info.options, info.tags);
        }
    }

    #! Returns a hash type from a type description hash
    static DataProvider::HashDataType getHashTypeFromInfo(hash<auto> info) {
        HashDataType rv(info.name, info.options, info.tags);
        map rv.addField(new QoreDataField($1.name, $1.desc, RemoteApiDataProvider::getTypeFromInfo($1.type),
            $1.default_value)), info.fields.iterator();
        return rv;
    }
}
}

class JobNameType inherits Type {

}