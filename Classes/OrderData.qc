# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus OrderData class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args

public namespace OMQ;

class OMQ::OrderData inherits Serializable {
    public {
        *softstring external_order_instanceid;
        *hash<auto> staticdata;
        *hash dynamicdata;
        *hash tempdata;
        *hash sensitive_data;
        *hash orderkeys;
        *date scheduled;
        int priority;
        *softint parent_workflow_instanceid;
        bool subworkflow = False;

        const DataKeysV1 = (
            "name",
            "version",
            "staticdata",
            "dynamicdata",
            "tempdata",
            "external_order_instanceid",
            "orderkeys",
            "scheduled",
            "priority",
            "parent_workflow_instanceid",
        );

        const DataKeys = DataKeysV1 + (
            "sensitive_data",
            "global_unique_key",
            "workflow_specific_unique_key",
            "workflow_unique_key",
        );

        const DataKeyHash = map {$1: True}, DataKeys;
    }

    private {
        # extra keys for workflow info
        string name;
        string version;
        softint workflowid;

        # unique keys for atomicity
        hash<string, softlist<softstring>> global_keys;
        hash<string, softlist<softstring>> specific_keys;
        hash<string, softlist<softstring>> workflow_keys;

        const ReservedKeys = ("name", "version", "workflowid", "subworkflow");
    }

    private constructor() {
    }

    constructor(hash<auto> orig_data) {
        # use += to ensure that "order_data" stays "hash<auto>"
        hash<auto> order_data += orig_data;
        # rename "order-keys" to "orderkeys"
        if (exists order_data."order-keys")
            order_data.orderkeys = remove order_data."order-keys";

        if (!exists order_data.priority)
            order_data.priority = OMQ::DefaultOrderPriority;
        else if (order_data.priority < 0)
            order_data.priority = 0;
        else if (order_data.priority > 999)
            order_data.priority = 999;

        if (order_data{ReservedKeys})
            throw "ORDER-DATA-ERROR", sprintf("invalid keys in order hash: %y", order_data{ReservedKeys});

        # process unique keys
        global_keys = addOrderKeys(\order_data.orderkeys, remove order_data.global_unique_key);
        specific_keys = addOrderKeys(\order_data.orderkeys, remove order_data.workflow_specific_unique_key);
        workflow_keys = addOrderKeys(\order_data.orderkeys, remove order_data.workflow_unique_key);

        # copy all members to object
        self += order_data;

        # must have at least external_order_instanceid or staticdata
        if (!exists staticdata && !exists external_order_instanceid)
            throw "ORDER-DATA-ERROR", sprintf("missing staticdata and external_order_instanceid keys in order hash; "
                "at least one of these must be present for the order to be accepted (keys: %y)", order_data.keys());

        # set the loosely-coupled parent workflow instance id on the current workflow_instanceid, assuming there is no
        # "parent_workflow_instanceid" key in the order with no value assigned
        if (!parent_workflow_instanceid && tld.wfe.workflow_instanceid)
            parent_workflow_instanceid = tld.wfe.workflow_instanceid;

        # make sure we have a hash of keyname -> value -> ("aliases": list of strings, "data": hash)
        foreach hash<auto> h in (sensitive_data.pairIterator()) {
            if (h.value.typeCode() != NT_HASH)
                throw "ORDER-DATA-ERROR", sprintf("sensitive data keytype %y is not assigned to a hash; got type %y "
                    "instead", h.key, h.value.type());
            foreach hash<auto> kh in (h.value.pairIterator()) {
                # refer to the key value as its offset; value is sensitive
                int key = $# + 1;

                if (kh.value.typeCode() != NT_HASH)
                    throw "ORDER-DATA-ERROR", sprintf("sensitive data keytype %y value %d is assigned type %y; "
                        "expecting \"hash\"", h.key, key, kh.value.type());

                {
                    hash<auto> kch = kh.value;
                    kch -= ("aliases", "data", "meta");
                    if (kch)
                        throw "ORDER-DATA-ERROR", sprintf("sensitive data keytype %y value %d is assigned to a hash "
                            "with unknown keys %y; expecting only \"aliases\" and \"data\"", h.key, key, kch.keys());
                }
                if (!h.value.size())
                    throw "ORDER-DATA-ERROR", sprintf("sensitive data keytype %y value %d is assigned to an empty "
                        "hash", h.key, key);

                # check data
                if (kh.value.data.typeCode() != NT_HASH)
                    throw "ORDER-DATA-ERROR", sprintf("sensitive data keytype %y value %d \"data\" is assigned to "
                        "type %y; expecting \"hash\"", h.key, key, kh.value.data.type());

                if (!kh.value.data)
                    throw "ORDER-DATA-ERROR", sprintf("sensitive data keytype %y value %d has an empty data hash",
                        h.key, key);

                if (kh.value.hasKey("meta")) {
                    if (kh.value.meta.typeCode() != NT_HASH)
                        throw "ORDER-DATA-ERROR", sprintf("sensitive data keytype %y value %d \"meta\" is assigned "
                            "to type %y; expecting \"hash\"", h.key, key, kh.value.meta.type());
                }

                foreach auto alias in (\kh.value.aliases) {
                    if (!alias.strp())
                        throw "ORDER-DATA-ERROR", sprintf("sensitive data keytype %y value %d alias %d is invalid; "
                            "expecting a string; got type %y instead", h.key, key, $#, alias.type());
                    alias = alias.toString();
                    if (alias.empty())
                        throw "ORDER-DATA-ERROR", sprintf("sensitive data keytype %y value %d alias %d is invalid; "
                            "expecting a non-empty string; got value %y instead", h.key, key, $#, alias.type());
                }

                # check key sizes
                SensitiveInstanceData::checkKeys(h.key, kh.key, kh.value.aliases);
            }
        }
    }

    hash<string, softlist<softstring>> addOrderKeys(reference ok, *hash<auto> kh) {
        if (!kh) {
            return {};
        }
        hash<string, softlist<softstring>> rv();

        # add kh to orderkeys
        foreach hash<auto> h in (kh.pairIterator()) {
            auto v = h.value;
            switch (v.typeCode()) {
                case NT_LIST:
                    foreach auto lv in (\v) {
                        if (lv.typeCode() != NT_STRING) {
                            if (!lv.strp())
                                throw "ORDER-DATA-ERROR", sprintf("order key %y list value %d/%d assigned to type %y "
                                    "which cannot be converted to a string", h.key, $# + 1, v.size(), lv.type());
                            lv = lv.toString();
                        }
                    }
                    break;
                case NT_STRING:
                    break;
                default:
                    if (!v.strp())
                        throw "ORDER-DATA-ERROR", sprintf("order key %y assigned to type %y which cannot be "
                            "converted to a string", h.key, v.type());
                    v = v.toString();
                    break;
            }
            reference key_target = \ok{h.key};
            if (exists key_target) {
                # ensure keys are not duplicated
                hash<string, bool> kth = map {$1: True}, key_target.iterator();
                map kth.$1 = True, v;
                rv{h.key} = key_target = keys kth;
            } else {
                rv{h.key} = key_target = v;
            }
        }
        return rv;
    }

    setParent(softint pwfiid, bool swf) {
        parent_workflow_instanceid = pwfiid;
        subworkflow = swf;
    }

    setParent(nothing pwfiid, bool swf) {
        # do nothing in this case
    }

    setNameAndVersion(string n_name, *string n_ver) {
        name = n_name;
        if (!exists n_ver || n_ver.empty()) {
            *hash wfh = Qorus.qmm.rLookupWorkflow(n_name);
            if (!wfh)
                throw "PARAMETER-ERROR", sprintf("no workflow %y has been cached (to fix this error: correct the "
                    "workflow name or deploy the workflow into the system. Then retry this operation)", n_name);

            n_ver = wfh.lastversion;
            workflowid = wfh.(wfh.lastversion).workflowid;
        } else
            workflowid = Qorus.qmm.getWorkflowId(n_name, n_ver);

        version = n_ver;

        # issue #3446: check workflow order data if applicable
        staticdata = verifyStaticData(name, version, workflowid, staticdata);
    }

    static *hash<auto> verifyStaticData(string name, string version, softstring workflowid, *hash<auto> staticdata,
            *string staticdata_type) {
        if (!exists staticdata_type) {
            staticdata_type = Qorus.qmm.lookupWorkflow(workflowid).staticdata_type_path;
        }
        QDBG_LOG("OrderData::verifyStaticData() %s v%s (%d) type: %y sd: %y", name, version, workflowid,
            staticdata_type, staticdata);
        if (staticdata_type) {
            AbstractDataProviderType type;
            try {
                type = UserApi::getTypeFromPath(staticdata_type).getSoftType();
            } catch (hash<ExceptionInfo> ex) {
                rethrow "ORDER-DATA-ERROR", sprintf("workflow %s v%s (%d) static data type %y cannot be resolved: "
                    "%s: %s", name, version, workflowid, staticdata_type, ex.err, ex.desc);
            }
            # issue #3496: the defined type should accept a list of the
            try {
                staticdata = type.acceptsValue(staticdata);
                olog(LoggerLevel::INFO, "VSD type %y data: %y", type.getName(), staticdata);
            } catch (hash<ExceptionInfo> ex) {
                rethrow "ORDER-DATA-ERROR", sprintf("workflow %s v%s (%d) static data does not conform to the "
                    "defined type %y (type %s): %s: %s", name, version, workflowid, staticdata_type,
                    type.getName(), ex.err, ex.desc);
            }
        }
        return staticdata;
    }

    string getName() {
        return name;
    }

    string getVersion() {
        return version;
    }

    int getWorkflowId() {
        return workflowid;
    }

    hash<string, softlist<softstring>> getGlobalKeys() {
        return global_keys;
    }

    hash<string, softlist<softstring>> getWorkflowKeys() {
        return workflow_keys;
    }

    hash<string, softlist<softstring>> getSpecificKeys() {
        return specific_keys;
    }
}
