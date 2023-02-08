# -*- mode: qore; indent-tabs-mode: nil -*-

/*
  Qorus Integration Engine

  Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

  **** NOTICE ****
    All information contained herein is, and remains the property of Qore
    Technologies, s.r.o. and its suppliers, if any.  The intellectual and
    technical concepts contained herein are proprietary to Qore Technologies,
    s.r.o. and its suppliers and may be covered by Czech, European, U.S. and
    Foreign Patents, patents in process, and are protected by trade secret or
    copyright law.  Dissemination of this information or reproduction of this
    material is strictly forbidden unless prior written permission is obtained
    from Qore Technologies, s.r.o..
*/

#! contains all public definitions in the QorusApiDataProvider module
public namespace QorusApiDataProvider {
#! Data type for create order API responses
public class QorusApiGetOrderInfoResponseDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = (
            "name": {
                "type": StringType,
                "desc": "The workflow name",
            },
            "version": {
                "type": StringType,
                "desc": "The workflow version",
            },
            "author": {
                "type": StringType,
                "desc": "The workflow author",
            },
            "workflow_instanceid": {
                "type": IntType,
                "desc": "The workflow instance ID",
            },
            "workflowid": {
                "type": IntType,
                "desc": "The workflow ID",
            },
            "workflowstatus": {
                "type": StringType,
                "desc": "The current status of the workflow order",
            },
            "status_sessionid": {
                "type": IntType,
                "desc": "The Qorus application session ID (0 if not assigned to any session)",
            },
            "parent_workflow_instanceid": {
                "type": IntOrNothingType,
                "desc": "The parent workflow instance ID (parent order ID), if any",
            },
            "subworkflow": {
                "type": IntOrNothingType,
                "desc": "1 if the order is being executed as a subworkflow",
            },
            "synchronous": {
                "type": IntType,
                "desc": "1 if the order is being executed synchronously, 0 if not",
            },
            "note_count": {
                "type": IntType,
                "desc": "The number of order notes associated with the order",
            },
            "business_error": {
                "type": BoolType,
                "desc": "True if the order has a business error, False if not",
            },
            "workflowstatus_orig": {
                "type": StringType,
                "desc": "The original status of the order when it was created",
            },
            "custom_status": {
                "type": StringOrNothingType,
                "desc": "The custom status of the order, if any",
            },
            "scheduled": {
                "type": DateOrNothingType,
                "desc": "The scheduled date (earliest processing data) for the order, if any",
            },
            "priority": {
                "type": IntType,
                "desc": "The order priority from 0 (highest) to 999 (lowest)",
            },
            "started": {
                "type": DateType,
                "desc": "The timestamp when the order was created",
            },
            "completed": {
                "type": DateOrNothingType,
                "desc": "The timestamp when processing completed for the order",
            },
            "modified": {
                "type": DateOrNothingType,
                "desc": "The timestamp when the order was last modified",
            },
            "operator_lock": {
                "type": StringOrNothingType,
                "desc": "The user that has the order locked for processing",
            },
            "deprecated": {
                "type": BoolType,
                "desc": "If True then the order belongs to a deprecated workflow (i.e. hidden in the UI)",
            },
            "autostart": {
                "type": IntOrNothingType,
                "desc": "The number of execution instances that will be started when the workflow is enabled",
            },
            "manual_autostart": {
                "type": BoolType,
                "desc": "If True then the autostart flag has been changed by the API / UI and will not be overriden "
                    "by changes when loading updated versions of the workflow",
            },
            "max_instances": {
                "type": IntOrNothingType,
                "desc": "The maximum number of execution instances that can be started simultaneously for the "
                    "workflow",
            },
            "external_order_instanceid": {
                "type": StringOrNothingType,
                "desc": "The unique external order ID, if any",
            },
            "staticdata": {
                "type": HashOrNothingType,
                "desc": "The order's static data",
            },
            "dynamicdata": {
                "type": HashOrNothingType,
                "desc": "The order's dynamic data",
            },
            "sensitive_data": {
                "type": HashOrNothingType,
                "desc": "The order's sensitive data",
            },
            "has_sensitive_data": {
                "type": BoolType,
                "desc": "True if the order has sensitive data",
            },
            "keys": {
                "type": HashOrNothingType,
                "desc": "Workflow order keys, if any",
            },
            "warning_count": {
                "type": IntType,
                "desc": "The number of warnings issued against the order",
            },
            "error_count": {
                "type": IntType,
                "desc": "The number of errors raised on the order",
            },
            "retry_count": {
                "type": IntType,
                "desc": "The number of times the order has been subjected to manual retries",
            },
            "StepInstances": {
                "type": ListOrNothingType,
                "desc": "The list of executed step instances for the order",
            },
            "HierarchyInfo": {
                "type": HashType,
                "desc": "A hash of related order entries keyed by workflow_instanceid, including an entry for the "
                    "current workflow order",
            },
            "AuditEvents": {
                "type": ListOrNothingType,
                "desc": "A list of audit event hashes raised against the order, if any",
            },
            "LastModified": {
                "type": DateType,
                "desc": "The same as `modified`",
            },
            "staticdata_type_path": {
                "type": StringOrNothingType,
                "desc": "The path to the declared static order data type",
            },
            "actions": {
                "type": ListOrNothingType,
                "desc": "a list of status actions that can be perfomed on the order",
            },
            "notes": {
                "type": ListOrNothingType,
                "desc": "a list of note hashes attached to the order, if any",
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
