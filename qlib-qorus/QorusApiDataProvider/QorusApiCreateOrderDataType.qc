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
#! Data type for create order calls
public class QorusApiCreateOrderSensitiveDataInfoType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "aliases": {
                "type": new Type("*softlist<string>"),
                "desc": "one or more aliases for the sensitive data",
            },
            "data": {
                "type": AutoHashType,
                "desc": "the sensitive data hash itself",
            },
            "meta": {
                "type": AutoHashOrNothingType,
                "desc": "the sensitive metadata hash; the following keys are recommended here:\n- `PURPOSE`: "
                    "free-form information about the purpose of the sensitive data\n- `CATEGORIES`: free-form "
                    "information about the categories of sensitive data\n- `RECIPIENTS`: free-form information about "
                    "the recipients or recipient catories of sensitive data\n  - `STORAGE`: free-form information "
                    "about the storage time or rules for sensitive data",
            },
        };
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)), Fields.pairIterator();
    }
}

#! Data type for create order calls
public class QorusApiCreateOrderSensitiveDataValueType inherits HashDataType {
    public {
        const ElementType = new QorusApiCreateOrderSensitiveDataInfoType();
    }

    #! Creates the object
    constructor() : HashDataType(new Type("hash<string, hash<auto>>")) {
    }

    #! returns the value if the value can be assigned to the type
    /** @param value the value to assign to the type

        @return the value to be assigned; can be converted by the type

        @throw RUNTIME-TYPE-ERROR value cannot be assigned to type
    */
    auto acceptsValue(auto value) {
        value = HashDataType::acceptsValue(value);
        map value{$1.key} = ElementType.acceptsValue($1.value), value.pairIterator();
        return value;
    }

    #! returns the subtype (for lists or hashes) if there is only one
    *AbstractDataProviderType getElementType() {
        return ElementType;
    }
}

#! Data type for create order calls
public class QorusApiCreateOrderSensitiveDataKeyType inherits HashDataType {
    public {
        const ElementType = new QorusApiCreateOrderSensitiveDataValueType();
    }

    #! Creates the object
    constructor() : HashDataType(new Type("*hash<string, hash<auto>>")) {
    }

    #! returns the value if the value can be assigned to the type
    /** @param value the value to assign to the type

        @return the value to be assigned; can be converted by the type

        @throw RUNTIME-TYPE-ERROR value cannot be assigned to type
    */
    auto acceptsValue(auto value) {
        value = HashDataType::acceptsValue(value);
        map value{$1.key} = ElementType.acceptsValue($1.value), value.pairIterator();
        return value;
    }

    #! returns the subtype (for lists or hashes) if there is only one
    *AbstractDataProviderType getElementType() {
        return ElementType;
    }
}

#! Data type for create order calls
public class QorusApiCreateOrderDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "workflow": {
                "type": WorkflowType,
                "desc": "The workflow name, name:version, or workflow ID",
            },
            "staticdata": {
                "type": AutoHashType,
                "desc": "The initial static data for the order",
            },
            "dynamicdata": {
                "type": AutoHashOrNothingType,
                "desc": "The initial dynamic data for the order",
            },
            "external_order_instanceid": {
                "type": SoftStringOrNothingType,
                "desc": "An optional external ID for the workflow order",
            },
            "sensitive_data": {
                "type": new QorusApiCreateOrderSensitiveDataKeyType(),
                "desc": "A hash of sensitive data information for the workflow; this key can only be used when "
                    "submitting the data over a secure (encrypted) connection; the keys are sensitive data key "
                    "types, values are hashes keyed by sensitive data values, and the hash values have the following "
                    "keys:\n- `aliases`: (optional list of strings) zero or more string aliases for the sensitive "
                    "data\n- `data`: (hash) the sensitive data hash itself\n- `meta`: (optional hash) a hash of "
                    "metadata for the sensitive data with the following recommended keys (recommended keys are not "
                    "enforced by the API itself):\n  - `PURPOSE`: free-form information about the purpose of the "
                    "sensitive data\n  - `CATEGORIES`: free-form information about the categories of sensitive data\n"
                    "  - `RECIPIENTS`: free-form information about the recipients or recipient catories of sensitive "
                    "data\n  - `STORAGE`: free-form information about the storage time or rules for sensitive data"
            },
            "status": {
                "type": StringOrNothingType,
                "desc": "The initial order status (default `READY`); must be either `READY` or `BLOCKED`",
            },
            "parent_workflow_instanceid": {
                "type": IntOrNothingType,
                "desc": "A loosely-coupled workflow that will be marked as the parent of this workflow",
            },
            "priority": {
                "type": IntOrNothingType,
                "desc": "The order priority from 0 - 999; priority 0 is the highest; 999 is the lowest",
            },
            "scheduled": {
                "type": DateOrNothingType,
                "desc": "The earliest date and time the order can be processed; if this date is given as a future "
                    "date/time value and a `READY` status is given, then the initial status of the workflow order "
                    "data instance will be automatically changed to `SCHEDULED` instead of `READY`",
            },
            "global_unique_key": {
                "type": AutoHashOrNothingType,
                "desc": "A hash giving one or more unique order keys for the order (across all workflows regardless of "
                    "workflowid, name, or version); keys are order key names and values are the string key values; if this "
                    "key already exists for any order in the system, then the order creation will fail with a "
                    "`DUPLICATE-ORDER-KEY` error; the hash key must be a valid order key, and the value is the unique key "
                    "value; this value will also be created as an order key",
            },
            "workflow_specific_unique_key": {
                "type": AutoHashOrNothingType,
                "desc": "A hash giving one or more unique order keys for the particular workflowid (which matches a "
                    "unique name and workflow version); keys are order key names and values are the string key values; if "
                    "any of the keys given already exists for an order with the target workflowid, then the order "
                    "creation will fail with a `DUPLICATE-ORDER-KEY` error; the hash key must be a valid order key, and the "
                    "value is the unique key value; this value will also be created as an order key",
            },
            "workflow_unique_key": {
                "type": AutoHashOrNothingType,
                "desc": "A hash giving one or more unique order keys for the particular workflow by name only (across all "
                    "workflows with the same name regardless of version); keys are order key names and values are the string "
                    "key values; if this key already exists for a workflow order with the same name, then the order creation "
                    "will fail with a `DUPLICATE-ORDER-KEY` error; the hash key must be a valid order key, and the value is the "
                    "unique key value; this value will also be created as an order key",
            },
            "orderkeys": {
                "type": AutoHashOrNothingType,
                "desc": "a hash of order keys for the order",
            },
        };
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            getInitFields().pairIterator();
    }

    #! Return fields
    private hash<auto> getInitFields() {
        return Fields;
    }
}
}
