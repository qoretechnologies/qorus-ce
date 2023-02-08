# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore RemoteApiProvider class definition

/** RemoteApiProvider.qc Copyright 2023 Qore Technologies, s.r.o.

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
public class RemoteApiProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "RemoteApiProvider",
            "supports_children": True,
            "constructor_options": ConstructorOptions,
            "children_can_support_apis": True,
        };

        #! Constructor options
        const ConstructorOptions = {
            "remote": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(StringType),
                "desc": "the name of the remote Qorus connection",
                "required": True,
            },
        };
    }

    private {
        #! The remote connection name
        string remote;

        #! The remote connection
        QorusSystemRestHelper qrest;
    }

    #! creates the object
    constructor(string remote, QorusSystemRestHelper qrest) {
        self.remote = remote;
        self.qrest = qrest;
    }

    #! Creates the object from constructor options
    constructor(*hash<auto> options) {
        *hash<auto> copts = checkOptions("CONSTRUCTOR-ERROR", ConstructorOptions, options);
        remote = copts.remote;
        qrest = new QorusSystemRestHelper(copts.remote);
    }

    #! Returns the remote connection name
    string getName() {
        return "qorus-api";
    }

    #! Returns the data provider description
    *string getDesc() {
        return sprintf("Data provider providing API access to remote Qorus instance `%s` with URL `%s`", remote,
            qrest.getSafeURL());
    }

    *list<hash<DataProviderSummaryInfo>> getChildProviderSummaryInfo() {
        return map cast<hash<DataProviderSummaryInfo>>($1),
            qrest.get("dataprovider/factories/qorus-api/provider?action=childDetails").children;
    }

    #! Returns a list of child data provider names
    /** @return a list of child data provider names
    */
    private *list<string> getChildProviderNamesImpl() {
        return cast<*list<string>>(qrest.get("dataprovider/factories/qorus-api/provider/children"));
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
            *hash<auto> h = qrest.get("dataprovider/factories/qorus-api/provider/" + name);
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
        return new RemoteApiDataProvider(remote, qrest, name);
    }

    #! Returns data provider static info
    private hash<DataProvider::DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }
}
}
