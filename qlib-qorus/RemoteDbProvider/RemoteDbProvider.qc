# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore RemoteDbProvider class definition

/** RemoteDbProvider.qc Copyright 2023 Qore Technologies, s.r.o.

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

#! contains all public definitions in the RemoteDbProvider module
public namespace RemoteDbProvider {
#! The database data provider class, provides tables as children
public class RemoteDbProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "RemoteDbProvider",
            "supports_children": True,
            "constructor_options": ConstructorOptions,
            "children_can_support_records": True,
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
        return "datasources";
    }

    #! Returns the data provider description
    *string getDesc() {
        return sprintf("Qorus remote DB stream data provider for remote `%s` with URL `%s`", remote,
            qrest.getSafeURL());
    }

    #! Return data provider summary info
    *list<hash<DataProviderSummaryInfo>> getChildProviderSummaryInfo() {
        string desctmpl = sprintf("Qorus remote DB stream data provider for remote `%s` and datasource `%%s`", remote);
        return map cast<hash<DataProviderSummaryInfo>>(RemoteDbDataProvider::ProviderInfo{DataProviderSummaryInfoKeys} + {
            "name": $1,
            "desc": sprintf(desctmpl, $1),
        }), qrest.get("remote/datasources?list");
    }

    #! Returns a list of child data provider names
    /** @return a list of child data provider names
    */
    private *list<string> getChildProviderNamesImpl() {
        return cast<*list<string>>(qrest.get("remote/datasources?list"));
    }

    #! Returns the given child provider or @ref nothing if the given child is unknown
    /** @return the given child provider or @ref nothing if the given child is unknown

        @throw CHILD-PROVIDER-ERROR error acquiring child provider

        @see getChildProviderEx()
    */
    private *AbstractDataProvider getChildProviderImpl(string name) {
        try {
            qrest.get("remote/datasources/" + name);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "DATASTREAM-CLIENT-RECEIVE-ERROR" && ex.arg.status_code == 404) {
                return;
            }
            rethrow "CHILD-PROVIDER-ERROR", sprintf("%s: %s", ex.err, ex.desc);
        }
        return new RemoteDbDataProvider(remote, name);
    }

    #! Returns data provider static info
    private hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }
}
}
