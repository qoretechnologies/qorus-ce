# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file DynamicDataHelper.qc workflow helper class

# Qorus Integration Engine

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

public namespace OMQ {
    #! user API namespace root
    /** @see
        - @ref jobapi
        - @ref serviceapi
        - @ref workflowapi
        - @ref mapperapi
     */
    public namespace UserApi {
        #! Qorus workflow API namespace
        public namespace Workflow {
            #! This class is a helper class that allows @ref dynamicdata "workflow dynamic data" (DynamicDataHelper) and @ref tempdata "workflow temp data" (TempDataHelper) to be read and updated atomically; the write lock for the data is grabbed in the constructor and released in the destructor
            /**
                @note in %Python available as \c wf.WorkflowDataHelper

                @since Qorus 3.1.0
             */
            class WorkflowDataHelper {
                public {
                }

                private {
%ifdef QorusServer
                    InstanceData data;
%endif
                }

%ifdef QorusServer
                constructor(InstanceData d) {
                    data = d;
                    if (!InstanceData::externalLock(d))
                        throw "LOCK-ERROR", sprintf("the write lock for workflow_instanceid %d is already held", tld.wfe.workflow_instanceid);
                }

                #! destroys the object and releases the write lock
                destructor() {
                    InstanceData::externalUnlock(data);
                }
%endif

                #! returns the value of one or more keys in the data or the entire data structure depending on the argument
                /**
                 */
                auto get(auto field) {
%ifdef QorusServer
                    return data.get(field);
%endif
                }
            }

            #! This class is a helper class that allows @ref dynamicdata "workflow dynamic data" to be read and updated atomically; the write lock for the data is grabbed in the constructor and released in the destructor
            /** Calls to the following workflow API functions related to @ref dynamicdata "workflow dynamic data" can
                be made normally while this object exists and the write lock is held

                @since Qorus 3.1.0
             */
            final public class DynamicDataHelper inherits WorkflowDataHelper {
                #! creates the object and grabs the write lock for @ref dynamicdata "workflow dynamic data" during the lifetime of the object
                /** @throw LOCK-ERROR another DynamicDataHelper object exists in the same thread; only one object can
                    be used at a time since the object grabs the write lock
                */
                constructor() : WorkflowDataHelper(tld.wfe.ddata) {
                }

                #! replaces @ref dynamicdata "dynamic data"; the data has already been committed to the database when the method returns
                /** @note
                    - There is currently no function equivalent to this method for
                      @ref dynamicdata "workflow dynamic data"; this method replaces all the data with \a new_data
                    - The use of this method causes SQL I/O to be performed in the system schema; to maximize
                      performance, calls to this and other similar methods should be minimized if possible
                */
                nothing replace(*hash<auto> new_data) {
%ifdef QorusServer
                    data.replaceAndSave(new_data, tld.wfe.workflow_instanceid);
                    Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "dynamic");
%endif
                }

                #! adds data to @ref dynamicdata "dynamic data"; the data has already been committed to the database when the method returns
                /** this method is equivalent to WorkflowApi::updateDynamicData()

                    @note The use of this method causes SQL I/O to be performed in the system schema; to maximize
                    performance, calls to this and other similar methods should be minimized if possible
                */
                nothing update(hash<auto> new_data) {
%ifdef QorusServer
                    data.updateAndSave(new_data, tld.wfe.workflow_instanceid);
                    Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "dynamic");
%endif
                }

                #! deletes one or more keys from @ref dynamicdata "dynamic data"; the changes have already been committed to the database when the method returns
                /** this method is equivalent to WorkflowApi::deleteDynamicDataKey()

                    @note The use of this method causes SQL I/O to be performed in the system schema; to maximize
                    performance, calls to this and other similar methods should be minimized if possible
                */
                nothing deleteKey(softlist<softstring> keysv) {
%ifdef QorusServer
                    if (data.deleteAndSave(keysv, tld.wfe.workflow_instanceid)) {
                        Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "dynamic");
                    }
%endif
                }
            }
        }
    }
}
