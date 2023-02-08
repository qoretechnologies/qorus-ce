# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiWorkflowDataProvider class definition

/** QorusApiWorkflowDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The main Qorus implicit workflow data provider class
public class QorusApiWorkflowDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiWorkflowDataProvider",
            "supports_children": True,
            "constructor_options": ConstructorOptions,
            "children_can_support_apis": True,
            "children_can_support_records": False,
            "children_can_support_observers": False,
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

        #! Registered API classes
        const ApiClasses = {
            "enable": "QorusApiEnableImplicitWorkflowDataProvider",
            "exec-async": "QorusApiExecAsynchronousImplicitWorkflowDataProvider",
            "exec-sync": "QorusApiExecSynchronousImplicitWorkflowDataProvider",
            "disable": "QorusApiDisableImplicitWorkflowDataProvider",
            "info": "QorusApiImplicitWorkflowInfoDataProvider",
            "reset": "QorusApiResetImplicitWorkflowDataProvider",
            "set-autostart": "QorusApiSetImplicitWorkflowAutostartDataProvider",
        };

        int wfid;
        string name;
    }

    #! creates the object
    constructor(int wfid, string name) {
        self.wfid = wfid;
        self.name = name;
    }

    #! Creates the object from constructor options
    constructor(*hash<auto> options) {
        *hash<auto> copts = checkOptions("CONSTRUCTOR-ERROR", ConstructorOptions, options);
        wfid = copts.wfid;
        name = UserApi::callRestApi("GET", "workflows/" + wfid).name;
    }

    #! Returns the data provider name
    string getName() {
        return name;
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Data provider providing child request-response data providers representing supported workflow APIs "
            "in Qorus";
    }

    #! Returns a list of child data provider names
    /** @return a list of child data provider names
    */
    private *list<string> getChildProviderNamesImpl() {
        return keys ApiClasses;
    }

    #! Returns the given child provider or @ref nothing if the given child is unknown
    /** @return the given child provider or @ref nothing if the given child is unknown

        @throw CHILD-PROVIDER-ERROR error acquiring child provider

        @see getChildProviderEx()
    */
    private *AbstractDataProvider getChildProviderImpl(string name) {
        *string cls = ApiClasses{name};
        if (cls) {
            return create_object(cls, wfid);
        }
    }

    #! Returns data provider static info
    private hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }
}
}
