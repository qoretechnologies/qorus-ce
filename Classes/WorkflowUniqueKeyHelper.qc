# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus WorkflowUniqueKeyHelper class definition
#
# manages workflow, segment, and step statuses & order instance data
# in the context of multiple asychronous segments

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

public namespace OMQ;

class OMQ::UniqueKeyHelper {
    public {
        # reference to pending data: key -> value -> key helper
        reference<hash<string, hash<string, UniqueKeyHelper>>> order_key_reference;
    }

    private {
        #! the order keys being set
        hash<string, softlist<softstring>> order_key_hash;

        #! number of threads waiting on this object
        int waiting = 0;

        #! global mutex for atomicity
        static Mutex m();

        #! for waiting until conflicts are resolved; the DB will provide the final error condition or not
        /** we cannot throw an error if there is a pending conflict; the other request(s) might fail
        */
        static Condition cond();
    }

    constructor(hash<string, softlist<softstring>> order_key_hash) {
        self.order_key_hash = order_key_hash;
    }

    destructor() {
        release();
    }

    private release() {
        AutoLock l(m);

        # remove keys from hash
        removeKeysIntern();

        # signal any waiting threads
        if (waiting) {
            cond.broadcast();
        }
    }

    private check() {
        try {
            {
                AutoLock l(m);

                # first we make sure there are no pending requests
                while (waitPendingIntern()) {}

                # otherwise save & set the keys optimistically
                setKeysIntern();
            }

            # make sure the keys are not set in the DB
            checkDbImpl();
        } catch (hash<ExceptionInfo> ex) {
            # destructors are not run when an exception happens in the constructor
            # so we have to release resources manually
            release();
            rethrow;
        }
    }

    #! wait for any pending keys to be removed
    /** must be called with the global mutex held

        @return True if the scan must be repeated
    */
    private bool waitPendingIntern() {
        # FIXME: revert this code thwn https://github.com/qorelanguage/qore/issues/3523 is fixed
        reference<auto> r = \self.order_key_reference;
        *hash<string, hash<string, UniqueKeyHelper>> order_key_reference = r;
        return UniqueKeyHelper::waitPendingIntern(order_key_reference, order_key_hash) || waitPendingInternImpl();
        #return UniqueKeyHelper::waitPendingIntern(order_key_reference, order_key_hash) || waitPendingInternImpl();
    }

    #! set keys in global unique hash(es)
    /** must be called with the global mutex held
    */
    private setKeysIntern() {
        map order_key_reference{$1.key}{$1.value} := self, order_key_hash.pairIterator();

        # set keys in more generic parent
        setKeysInternImpl();
    }

    #! wait for keys in the given hash to be free of conflicts
    /** must be called with the global mutex held

        @return True if the scan must be repeated
    */
    static private bool waitPendingIntern(*hash<auto> order_key_reference, hash<string, softlist<softstring>> order_key_hash) {
        if (order_key_reference) {
            foreach hash<auto> ki in (order_key_hash.pairIterator()) {
                foreach string value in (keys ki.value) {
                    # if we have a pending conflict, then wait until it has been resolved
                    *UniqueKeyHelper key_helper = order_key_reference{ki.key}{value};
                    if (key_helper) {
                        ++key_helper.waiting;
                        UniqueKeyHelper::cond.wait(m);
                        --key_helper.waiting;
                        return True;
                    }
                }
            }
        }
        return False;
    }

    #! removes keys from the given hash
    /** must be called with the global mutex held
    */
    private removeKeysIntern() {
        UniqueKeyHelper::removeKeysIntern(\order_key_reference, order_key_hash);
        # remove any parent keys while inside the lock if applicable
        removeKeysInternImpl();
    }

    #! removes keys from the given hash
    /** must be called with the global mutex held
    */
    static private removeKeysIntern(reference<hash<string, hash<string, UniqueKeyHelper>>> order_key_reference, hash<string, softlist<softstring>> order_key_hash) {
        # note: if $1.value is a list, then all keys are removed in one remove expression
        map remove order_key_reference{$1.key}{$1.value}, order_key_hash.pairIterator();
        # remove keys with no more values
        map remove order_key_reference{$1}, keys order_key_hash, !order_key_reference{$1};
    }

    #! wait for any pending parent keys to be removed
    /** must be called with the global mutex held
    */
    abstract private bool waitPendingInternImpl();

    #! set keys in more generic parent while inside the lock if applicable
    abstract private setKeysInternImpl();

    #! remove any parent keys in the destructor while inside the lock if applicable
    abstract private removeKeysInternImpl();

    #! check the DB for uniqueness
    abstract private checkDbImpl();
}

class OMQ::GlobalUniqueKeyHelper inherits UniqueKeyHelper {
    constructor(hash<string, softlist<softstring>> order_key_hash) : UniqueKeyHelper(order_key_hash) {
        order_key_reference = \WorkflowUniqueKeyHelper::global_keys;
        check();
    }

    # wait for any pending parent keys to be removed
    /** must be called with the global mutex held
    */
    private bool waitPendingInternImpl() {
        return False;
    }

    # set keys in more generic parent while inside the lock if applicable
    private setKeysInternImpl() {
    }

    # remove any parent keys in the destructor while inside the lock if applicable
    private removeKeysInternImpl() {
    }

    private checkDbImpl() {
        *list<auto> l = sysinfo.searchOrderKeys(("orderkeys": order_key_hash));
        if (l) {
            # issue #2920: if multiple keys are selected, then the same order can be matched more than once, so we
            # create a unique hash of the workflow orders
            hash<string, bool> wfih = map {$1.workflow_instanceid: True}, l;
            list<int> wfids = map $1.toInt(), keys wfih;
            throw "DUPLICATE-ORDER-KEY", sprintf("global atomic workflow order key%s %y %s already been set in the DB for the following orders: %y",
                                                 order_key_hash.size() == 1 ? "" : "s", order_key_hash, order_key_hash.size() == 1 ? "has" : "have", wfids),
                                         {"workflow_instance_ids": wfids};
        }
    }
}

class OMQ::WorkflowNameUniqueKeyHelper inherits UniqueKeyHelper {
    private:internal {
        # workflow name
        string name;
    }

    constructor(hash<string, softlist<softstring>> order_key_hash, string name) : UniqueKeyHelper(order_key_hash) {
        order_key_reference = \WorkflowUniqueKeyHelper::workflow_keys{name};
        self.name = name;
        check();
    }

    # wait for any pending parent keys to be removed
    /** must be called with the global mutex held
    */
    private bool waitPendingInternImpl() {
        return UniqueKeyHelper::waitPendingIntern(WorkflowUniqueKeyHelper::global_keys, order_key_hash);
    }

    # set keys in more generic parent while inside the lock if applicable
    private setKeysInternImpl() {
        # set global keys
        map WorkflowUniqueKeyHelper::global_keys{$1.key}{$1.value} := self, order_key_hash.pairIterator();
    }

    # remove any parent keys in the destructor while inside the lock if applicable
    private removeKeysInternImpl() {
        removeWorkflowNameUniqueKeys(name, order_key_hash);
    }

    private checkDbImpl() {
        *list<auto> l = sysinfo.searchOrderKeys(("workflowname": name, "orderkeys": order_key_hash));
        if (l) {
            # issue #2920: if multiple keys are selected, then the same order can be matched more than once, so we
            # create a unique hash of the workflow orders
            hash<string, bool> wfih = map {$1.workflow_instanceid: True}, l;
            list<int> wfids = map $1.toInt(), keys wfih;
            throw "DUPLICATE-ORDER-KEY", sprintf("atomic workflow order key%s %y for workflow %y %s already been set in the DB for the following orders: %y",
                                                 order_key_hash.size() == 1 ? "" : "s", order_key_hash, name, order_key_hash.size() == 1 ? "has" : "have", wfids),
                                         {"workflow_instance_ids": wfids};
        }
    }

    # remove any parent keys in the destructor while inside the lock if applicable
    static removeWorkflowNameUniqueKeys(string name, hash<string, softlist<softstring>> order_key_hash) {
        if (!WorkflowUniqueKeyHelper::workflow_keys{name}) {
            remove WorkflowUniqueKeyHelper::workflow_keys{name};
        }

        # remove global keys
        UniqueKeyHelper::removeKeysIntern(\WorkflowUniqueKeyHelper::global_keys, order_key_hash);
    }
}

class OMQ::SpecificUniqueKeyHelper inherits UniqueKeyHelper {
    private:internal {
        int workflowid;
        hash<auto> wf_info;
    }

    constructor(hash<string, softlist<softstring>> order_key_hash, softint workflowid) : UniqueKeyHelper(order_key_hash) {
        *hash<auto> wfh = Qorus.qmm.lookupWorkflow(workflowid);
        if (!wfh) {
            throw "WORKFLOW-ERROR", sprintf("workflowid %d is unknown", workflowid);
        }
        wf_info = wfh;
        order_key_reference = \WorkflowUniqueKeyHelper::specific_keys{workflowid};
        self.workflowid = workflowid;
        check();
    }

    # wait for any pending parent keys to be removed
    /** must be called with the global mutex held
    */
    private bool waitPendingInternImpl() {
        return UniqueKeyHelper::waitPendingIntern(WorkflowUniqueKeyHelper::workflow_keys{wf_info.name}, order_key_hash)
            || UniqueKeyHelper::waitPendingIntern(WorkflowUniqueKeyHelper::global_keys, order_key_hash);
    }

    # set keys in more generic parent while inside the lock if applicable
    private setKeysInternImpl() {
        # set workflow name keys
        map WorkflowUniqueKeyHelper::workflow_keys{wf_info.name}{$1.key}{$1.value} := self, order_key_hash.pairIterator();

        # set global keys
        map WorkflowUniqueKeyHelper::global_keys{$1.key}{$1.value} := self, order_key_hash.pairIterator();
    }

    # remove any parent keys in the destructor while inside the lock if applicable
    private removeKeysInternImpl() {
        if (!WorkflowUniqueKeyHelper::specific_keys{workflowid}) {
            remove WorkflowUniqueKeyHelper::specific_keys{workflowid};
        }

        UniqueKeyHelper::removeKeysIntern(\WorkflowUniqueKeyHelper::workflow_keys{wf_info.name}, order_key_hash);
        WorkflowNameUniqueKeyHelper::removeWorkflowNameUniqueKeys(wf_info.name, order_key_hash);
    }

    private checkDbImpl() {
        *list<auto> l = sysinfo.searchOrderKeys(("workflowid": workflowid, "orderkeys": order_key_hash));
        if (l) {
            # issue #2920: if multiple keys are selected, then the same order can be matched more than once, so we
            # create a unique hash of the workflow orders
            hash<string, bool> wfih = map {$1.workflow_instanceid: True}, l;
            list<int> wfids = map $1.toInt(), keys wfih;
            throw "DUPLICATE-ORDER-KEY", sprintf("atomic workflow-specific order key%s %y for workflow %s %s already been set in the DB for the following orders: %y",
                                                 order_key_hash.size() == 1 ? "" : "s", order_key_hash, getWorkflowDescription(), order_key_hash.size() == 1 ? "has" : "have", wfids),
                                         {"workflow_instance_ids": wfids};
        }
    }

    # get workflow description for error messages
    private string getWorkflowDescription() {
        return sprintf("%s v%s (%d)", wf_info.name, wf_info.version, workflowid);
    }
}

class OMQ::WorkflowUniqueKeyHelper {
    public {
        # direct key hash
        static hash<auto> global_keys;

        # keyed by workflow name -> key hash
        static hash<auto> workflow_keys();

        # keyed by workflowid -> key hash
        static hash<auto> specific_keys();
    }

    private:internal {
        # list of UniqueKeyHelper objects
        list<UniqueKeyHelper> l;
    }

    constructor(OrderData order) {
        hash<string, softlist<softstring>> order_key_hash = order.getGlobalKeys();
        if (order_key_hash) {
            l += new GlobalUniqueKeyHelper(order_key_hash);
        }
        order_key_hash = order.getWorkflowKeys();
        if (order_key_hash) {
            l += new WorkflowNameUniqueKeyHelper(order_key_hash, order.getName());
        }
        order_key_hash = order.getSpecificKeys();
        if (order_key_hash) {
            l += new SpecificUniqueKeyHelper(order_key_hash, order.getWorkflowId());
        }
    }
}