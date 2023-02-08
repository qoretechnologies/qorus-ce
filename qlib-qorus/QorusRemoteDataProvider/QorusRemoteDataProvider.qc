# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusRemoteDataProvider class definition

/** QorusRemoteDataProvider.qc Copyright 2023 Qore Technologies, s.r.o.

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

#! contains all public definitions in the QorusRemoteDataProvider module
public namespace QorusRemoteDataProvider {
#! The database data provider class, provides tables as children
public class QorusRemoteDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusRemoteDataProvider",
            "supports_children": True,
            "children_can_support_apis": True,
            "children_can_support_records": True,
        };
    }

    #! creates the object
    constructor() {
    }

    #! Creates the object from constructor options
    constructor(*hash<auto> options) {
        checkOptions("CONSTRUCTOR-ERROR", NOTHING, options);
    }

    #! Returns the remote connection name
    string getName() {
        return "remote";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Qorus remote connection data provider root; children are data providers for remote Qorus "
            "connection";
    }

    #! Return data provider summary info
    *list<hash<DataProviderSummaryInfo>> getChildProviderSummaryInfo() {
        return map cast<hash<DataProviderSummaryInfo>>(QorusRemoteConnectionDataProvider::ProviderInfo{DataProviderSummaryInfoKeys} + {
            "name": $1,
            "desc": sprintf("Qorus remote connection data provider for remote `%s`", $1),
        }), QorusCommonClientServerApi::listRemoteConnections();
    }

    #! Returns a list of child data provider names
    /** @return a list of child data provider names
    */
    private *list<string> getChildProviderNamesImpl() {
        return QorusCommonClientServerApi::listRemoteConnections();
    }

    #! Returns the given child provider or @ref nothing if the given child is unknown
    /** @return the given child provider or @ref nothing if the given child is unknown

        @throw CHILD-PROVIDER-ERROR error acquiring child provider

        @see getChildProviderEx()
    */
    private *AbstractDataProvider getChildProviderImpl(string name) {
        QorusSystemRestHelper qrest;
        try {
            qrest = new QorusSystemRestHelper(name);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "CONNECTION-ERROR") {
                rethrow "CHILD-PROVIDER-ERROR", sprintf("%s: %s", ex.err, ex.desc);
            }
            return;
        }
        return new QorusRemoteConnectionDataProvider(name, qrest);
    }

    #! Returns data provider static info
    private hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }
}
}
