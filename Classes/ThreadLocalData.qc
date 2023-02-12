# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus ThreadLocalData class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args

/**
 * global thread-local instance of @ref ThreadLocalData. Use one of @ref create_tld
 * or @ref ensure_tld before using this variable.
 */
thread_local ThreadLocalData tld;  # global thread-local variable

public namespace OMQ {

/**
 * contains the thread-local context information.
 */
public class ThreadLocalData {
    public {
        *softstring index;
        *string stepID;
        *int ind;
        *string stepName;
        auto wfe; # FIXME WFEntry
        auto svc; # FIXME AbstractQorusService
        auto job; # FIXME Job
        *string method;
        auto wf; # Workflow
        *hash cx;
        *softstring sync;
        #auto async;
        *bool attachInProgress;
        *bool attachIsBlocked;
        *bool virtual;
        *string mode;
        *bool skipAsync;
        *bool skipSubWorkflow;
        *bool skipEvent;
        *bool businessError;
        *date retryDelay;
        *bool attachReschedule;
        *int segID;
        *hash stepError;
        *string eventKey;
        *bool inOneTimeInit;
        *int asyncQueueID;
        *int arraySize;
        *bool subWorkflow;
        *int eventTypeID;
        #auto event_name;
        *softstring subWorkflowInstanceID;
        *softstring parentWorkflowInstanceID;
        #auto workflow_instanceid;
        auto _wf; # FIXME Workflow class

        #! current array element when executing an array step
        /** @since Qorus 4.1.4
        */
        auto arrayElement;

        *hash dspHashCache;
        *hash dspNameCache;
        # map of service type -> service name -> (RO | EXCL) -> TID -> True
        *hash<string, hash<string, hash<string, hash<string, bool>>>> svc_locks;
        # map of external exclusive service locks held
        *hash<string, bool> external_locks;
        # issue #2647: hierarchical map of workflow execution instance IDs; parent -> child -> True
        *hash<string, hash<string, bool>> index_map;
        #auto error;
        #auto noerror;
        # issue #3319: to ensure that the correct interface context is always used
        *string _current_ix;
        # issue #3432: temporary data for interfaces
        *hash<auto> transient_data;
        # "block-local" data for interfaces
        *hash<auto> var_data;
        # issue #3485: for config items in finite state machines
        *hash<auto> fsm_ctx;
        # issue #3816: current FSM state input data
        auto fsm_input_data;
    }

    private {
        # FIXME nameMap is necessary for fromHash and toHash.
        const nameMap = {
            "stepID": "stepid",
            "stepName": "stepname",
            "attachInProgress": "attachinprogress",
            "attachIsBlocked": "attachisblocked",
            "skipAsync": "skip_async",
            "skipSubWorkflow": "skip_subworkflow",
            "skipEvent": "skip_event",
            "businessError": "business_error",
            "retryDelay": "retry_delay",
            "attachReschedule": "attachreschedule",
            "segID": "segid",
            "stepError": "steperror",
            "eventKey": "eventkey",
            "inOneTimeInit": "inonetimeinit",
            "asyncQueueID": "async_queueid",
            "arraySize": "array_size",
            "subWorkflow": "subworkflow",
            "eventTypeID": "event_typeid",
            "subWorkflowInstanceID": "subworkflow_instanceid",
            "parentWorkflowInstanceID": "parent_workflow_instanceid",
            "dspHashCache": "dsphashcache",
            "dspNameCache": "dspnamecache",
        };
    }

    #! Creates the object with the given members
    constructor(*hash<auto> members) {
        if (members) {
            self += members;
        }
    }

    bool isServiceContext() {
%ifdef QorusHasSvcApi
%ifdef QorusHasIxApis
        return svc && _current_ix == "svc";
%else
        return exists svc;
%endif
%else
        return False;
%endif
    }

    bool isJobContext() {
%ifdef QorusHasJobApi
%ifdef QorusHasIxApis
        return job && _current_ix == "job";
%else
        return exists job;
%endif
%else
        return False;
%endif
    }

    bool isWorkflowContext() {
%ifdef QorusHasWfApi
%ifdef QorusHasIxApis
        return wf && _current_ix == "wf";
%else
        return exists wf;
%endif
%else
        return False;
%endif
    }

    bool isWorkflowExecContext() {
%ifdef QorusHasWfApi
%ifdef QorusHasIxApis
        return (index || stepID) && _current_ix == "wf";
%else
        return exists index || exists stepID;
%endif
%else
        return False;
%endif
    }

    bool isOrderContext() {
%ifdef QorusHasWfApi
%ifdef QorusHasIxApis
        return wfe && _current_ix == "wf";
%else
        return exists wfe;
%endif
%else
        return False;
%endif
    }

    bool isRealOrderContext() {
%ifdef QorusHasWfApi
%ifdef QorusHasIxApis
        return wfe instanceof WFEntry && _current_ix == "wf";
%else
        return wfe instanceof WFEntry;
%endif
%else
        return False;
%endif
    }

    bool isRealServiceContext() {
%ifdef QorusHasSvcApi
%ifdef QorusHasIxApis
        return svc instanceof LocalQorusService && _current_ix == "svc";
%else
        return svc instanceof LocalQorusService;
%endif
%else
        return False;
%endif
    }

    bool isRealJobContext() {
%ifdef QorusHasJobApi
%ifdef QorusHasIxApis
        return job instanceof LocalQorusJob && _current_ix == "job";
%else
        return job instanceof LocalQorusJob;
%endif
%else
        return False;
%endif
    }

    *string getContext() {
%ifdef QorusHasIxApis
        return _current_ix;
%else
%ifdef QorusHasWfApi
        return "wf";
%endif

%ifdef QorusHasSvcApi
        return "svc";
%endif

%ifdef QorusHasJobApi
        return "job";
%endif
%endif
    }

    /** erase all the elements of ThreadLocalData
     */
    nothing clear() {
        remove self{keys self};
    }

    /** overwrite the content of the current @ref ThreadLocalData instance with the argument.
     * Note that overwrite is optional in the way that if \c a.<something is @ref NOTHING
     * then the original value is kept.
     * @param a @ref ThreadLocalData instance to use for overriding the current instance
     */
    nothing add(OMQ::ThreadLocalData a) {
        # must not overwrite if a.<something> = NOTHING?
        map self{$1.key} = $1.value, a.pairIterator(), exists $1.value;
        # FIXME how to log from here, when it is included in QorusClientCore too?
    }

    add(hash<auto> h) {
%ifdef QorusCore
        if (h.svc.typeCode() == NT_HASH && h.svc.name) {
            svc = services.getService(h.svc.type, h.svc.name);
            remove h.svc;
        }
%endif
        map self{$1.key} = $1.value, h.pairIterator(), exists $1.value;
    }

    /**
     * overwrites the current instance unconditionally with the argument.
     * @see ThreadLocalData::add
     * @param a a @ref ThreadLocalData instance to be used for overwrite
     *
     * @note copy() cannot be used as it is a special method
     */
    tldCopy(OMQ::ThreadLocalData a) {
        map self{$1.key} = $1.value, a.pairIterator();
    }

    #! clears the current object
    tldCopy() {
        clear();
    }

    /**
        Sets the current instance with the given tld
     */
    static set(ThreadLocalData new_tld) {
        QDBG_ASSERT(!tld);
        tld = new_tld;
    }

    /**
        Replaces the current data with the given tld
     */
    static replace(hash<auto> new_tld) {
        tld = new ThreadLocalData(new_tld);
    }

    /**
     * converts the data to a hash
     * @returns the hash that was constructed; it could be used in
     *          @ref ThreadLocalData::fromHash to restore the @ref ThreadLocalData instance.
     */
    hash<auto> toHash() {
        return map {(nameMap{$1} ?? $1) : self{$1}}, keys self;
    }

    /**
     * restores the data from a hash, @see ThreadLocalData::toHash
     * @param h a hash to restore the data from, @see ThreadLocalData::toHash
     */
    # FIXME this is bad design, and implemented solely for
    # HttpServer::AbstractHttpRequestHandler::saveThreadLocalData and restoreThreadLocalData.
    # The class is part of HttpServerUtil.qm in Qore, which does not know anything about
    # Qorus and its ThreadLocalData. It would be better to have some AbstractThreadLocalData
    # in Qore and derive ThreadLocalData from it... --PQ 01-Jul-2016
    nothing fromHash(*hash<auto> h) {
        if (!h) {
            throw "ERROR", "ThreadLocalData::fromHash cannot restore from NOTHING";
        }
        clear();
        ObjectKeyIterator it(self);
        while (it.next()) {
            string name = it.getValue();
            self{name} = h{nameMap{name} ?? name};
        }
    }

    #! returns the current interface if known
    *object getInterface() {
        *string ix = _current_ix;
        if (ix) {
            return self{ix};
        }
    }
} # of class ThreadLocalData

#! saves and clears data in the constructor and restores it in the destructor
public class DataHelperBase {
    public {
        string type;
        *hash<auto> saved_data;
    }

    constructor(string type) {
        type += "_data";
        self.type = type;
        saved_data = remove tld{type};
    }

    destructor() {
        tld{type} = saved_data;
    }
}

#! saves and clears transient and var data in the constructor and restores it in the destructor
public class TransientDataHelper inherits DataHelperBase {
    public {
        *hash<auto> saved_var_data;
    }

    constructor() : DataHelperBase("transient") {
        saved_var_data = remove tld.var_data;
    }

    destructor() {
        tld.var_data = saved_var_data;
    }
}

#! saves and clears var data in the constructor and restores it in the destructor
public class VarDataHelper inherits DataHelperBase {
    constructor() : DataHelperBase("var") {
    }
}

/**
 * creates the global thread-local instance of @ref ThreadLocalData, i.e.
 * the variable @ref tld.
 */
nothing sub create_tld() {
%ifdef QorusDebugInternals
    if (tld) {
        throw "ERROR", "create_tld(): tld already exists";
    }
    #QDBG_LOG("create_tld creating tld: %y", get_stack());
%endif
    tld = new ThreadLocalData();
}

/**
 * returns @ref True if @ref tld exists and its members (given in \c names) are not @ref NOTHING.
 * Otherwise returns @ref False.
 */
# Typical use is like: QDBG_ASSERT(ensure_tld());
bool sub ensure_tld(*list names) {
    if (!tld) {
%ifdef QorusDebugInternals
        #QDBG_LOG("ensure_tld returns False: %y", get_stack());
%endif
        return False;
    }
    foreach string n in (names) {
        if (!exists tld{n}) {
            return False;
        }
    }
    return True;
}

#! creates thread local data if it doesn't already exist
/** @return @ref True if @ref tld already existed and @ref False if it was created
*/
public bool sub ensure_create_tld() {
    if (!tld) {
        tld = new ThreadLocalData();
        return False;
    }
    return True;
}
} # namespace OMQ
