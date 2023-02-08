# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiUtilDataProvider class definition

/** QorusApiUtilDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API util data provider class
public class QorusApiUtilDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiDataProvider",
            "supports_children": True,
            "children_can_support_apis": True,
            "children_can_support_records": False,
            "children_can_support_observers": False,
        };

        #! Registered API classes
        const ApiClasses = {
            "break": new QorusApiBreakDataProvider(),
            "continue": new QorusApiContinueDataProvider(),
            "get-data": new QorusApiGetDataDataProvider(),
            "log-message": new QorusApiLogMessageDataProvider(),
            "post-async-queue": new QorusApiPostAsyncQueueDataProvider(),
            "post-sla-error": new QorusApiPostSlaErrorDataProvider(),
            "post-sla-success": new QorusApiPostSlaSuccessDataProvider(),
            "post-sync-event": new QorusApiPostSyncEventDataProvider(),
            "rest-request": new QorusApiRestRequestDataProvider(),
            "throw-exception": new QorusApiThrowExceptionDataProvider(),
            "write-output": new QorusApiWriteOutputDataProvider(),

            "workflow": new QorusApiUtilWorkflowDataProvider(),
        };
    }

    #! creates the object
    constructor() {
    }

    #! Creates the object from constructor options
    constructor(*hash<auto> options) {
        checkOptions("CONSTRUCTOR-ERROR", NOTHING, options);
    }

    #! Returns the data provider name
    string getName() {
        return "util";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Data provider providing child request-response data providers representing supported utility APIs in "
            "Qorus";
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
        return ApiClasses{name};
    }

    #! Returns data provider static info
    private hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }
}
}
