# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiWorkflowInfoDataProvider class definition

/** QorusApiWorkflowInfoDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the workflow info API
public class QorusApiWorkflowInfoDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiWorkflowInfoDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiWorkflowInfoRequestDataType();

        #! Response type
        const ResponseType = new QorusApiWorkflowInfoResponseDataType();
    }

    #! Returns the name of the data provider
    string getName() {
        return "info";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: return information about the given workflow";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        return UserApi::callRestApi("GET", "workflows/" + req.workflow);
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
public class QorusApiWorkflowInfoRequestDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "workflow": {
                "type": WorkflowType,
                "desc": "the workflow ID or name (or name:version string)",
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
public class QorusApiWorkflowInfoResponseDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = (
            "workflowid": {
                "type": IntType,
                "desc": "The workflow ID",
            },
            "name": {
                "type": StringType,
                "desc": "The workflow name",
            },
            "version": {
                "type": StringType,
                "desc": "The workflow version",
            },
            "description": {
                "type": StringOrNothingType,
                "desc": "The workflow description",
            },
            "author": {
                "type": StringOrNothingType,
                "desc": "The workflow author",
            },
            "remote": {
                "type": BoolType,
                "desc": "If the workflow runs in a remote qwf process or not",
            },
            "manual_remote": {
                "type": BoolType,
                "desc": "If the workflow remote status was set with the API or UI",
            },
            "sla_threshold": {
                "type": IntType,
                "desc": "The time in seconds since creation that a workflow order should get a final status",
            },
            "manual_sla_threshold": {
                "type": IntType,
                "desc": "If the workflow sla_threshold value was set with the API or UI",
            },
            "enabled": {
                "type": BoolType,
                "desc": "If the workflow is enabled",
            },
            "language": {
                "type": StringType,
                "desc": "The language any workflow-level code is written in",
            },
            "has_detach": {
                "type": BoolType,
                "desc": "If the workflow has attach logic or not",
            },
            "created": {
                "type": DateType,
                "desc": "The creation timestamp for the workflow",
            },
            "modified": {
                "type": DateOrNothingType,
                "desc": "The modified timestamp for the workflow",
            },
            "source": {
                "type": StringOrNothingType,
                "desc": "The source of the workflow",
            },
            "line": {
                "type": StringOrNothingType,
                "desc": "The line number of the start of the workflow code in `source`",
            },
            "deprecated": {
                "type": BoolType,
                "desc": "If the workflow is deprecated (i.e. not shown in the UI) or not",
            },
            "keylist": {
                "type": ListOrNothingType,
                "desc": "A list of zero or more valid workflow keys",
            },
            "order_key_map": {
                "type": HashOrNothingType,
                "desc": "A hash of order keys where the keys are valid order keys",
            },
            "stepmap": {
                "type": HashType,
                "desc": "A hash of steps where the keys are stepids and the values are step names",
            },
            "steps": {
                "type": HashType,
                "desc": "A hash of step dependencies to be used to derive step execution order",
            },
            "segment": {
                "type": ListType,
                "desc": "A list of information about each workflow segment",
            },
            "lib": {
                "type": HashOrNothingType,
                "desc": "A hash of library information (associated code and interface objects) for the workflow",
            },
            "mappers": {
                "type": ListOrNothingType,
                "desc": "A list of mappers associated to the workflow, if any",
            },
            "vmaps": {
                "type": ListOrNothingType,
                "desc": "A list of value maps associated to the workflow, if any",
            },
            "tags": {
                "type": HashOrNothingType,
                "desc": "A hash of tags associated with the workflow",
            },
            "stepinfo": {
                "type": ListType,
                "desc": "A list of step information hashes for all steps in the workflow",
            },
            "wffuncs": {
                "type": ListType,
                "desc": "A list of workflow function information hashes for any workflow-level functions",
            },
            "options": {
                "type": ListOrNothingType,
                "desc": "A list of workflow option hashes, if the workflow supports any",
            },
            "exec": {
                "type": ListOrNothingType,
                "desc": "A list of workflow execution instance hashes, if any",
            },
            "exec_count": {
                "type": IntType,
                "desc": "The number of workflow execution instances running",
            },
            "order_stats": {
                "type": ListOrNothingType,
                "desc": "A list of workflow order processing statistic hashes, if any are available",
            },
            "config": {
                "type": HashOrNothingType,
                "desc": "A hash of workflow-level config item information keyed by config item name, if any",
            },
            "global_config": {
                "type": HashOrNothingType,
                "desc": "A hash of global config item information related to this workflow, if any",
            },
            "alerts": {
                "type": ListType,
                "desc": "A list of zero or more alerts raised against the workflow",
            },
            "connections": {
                "type": ListType,
                "desc": "A list of zero or more connections used by the workflow",
            },
            "groups": {
                "type": ListType,
                "desc": "A list of zero or more groups that the current workflow is specified in",
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
