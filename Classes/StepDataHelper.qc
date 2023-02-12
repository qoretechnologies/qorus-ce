# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file StepDataHelper.qc workflow helper class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
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
            #! This class is a helper class that allows @ref stepdata "workflow dynamic step data" to be read and updated atomically; the write lock for the data is grabbed in the constructor and released in the destructor
            /** Calls to the following workflow API methods related to @ref stepdata "workflow dynamic step data"
                can be made normally while this object exists and the write lock is held; the nethods are aware of
                and automatically use the write lock held by this object:
                - @ref OMQ::UserApi::Workflow::QorusStepBase::updateStepData() "QorusStepBase::updateStepData()"
                - @ref OMQ::UserApi::Workflow::QorusStepBase::deleteStepDataKey() "QorusStepBase::deleteStepDataKey()"
                - @ref OMQ::UserApi::Workflow::QorusStepBase::getStepData() "QorusStepBase::getStepData()"
                - @ref OMQ::UserApi::Workflow::QorusStepBase::getStepDataArgs() "QorusStepBase::getStepDataArgs()"

                @since Qorus 4.0.1
             */
            final public class StepDataHelper {
                private {
%ifdef QorusServer
                    StepData sdata;
%endif
                }

                #! creates the object and grabs the write lock for @ref stepdata "workflow dynamic step data" during the lifetime of the object
                /** @throw LOCK-ERROR another StepDataHelper object exists in the same thread; only one object can be used at a time since the object grabs the write lock
                 */
                constructor() {
%ifdef QorusServer
                    sdata = tld.wfe.step_data;
                    if (!StepData::externalLock(sdata)) {
                        throw "LOCK-ERROR", sprintf("the write lock for step data for workflow_instanceid %d is "
                            "already held", tld.wfe.workflow_instanceid);
                    }
%endif
                }

                #! destroys the object and releases the write lock
                destructor() {
%ifdef QorusServer
                    StepData::externalUnlock(sdata);
%endif
                }

                #! returns the value of one or more keys in the data or the entire data structure depending on the argument
                /** this method is equivalent to
                    @ref OMQ::UserApi::Workflow::QorusStepBase::getStepData() "QorusStepBase::getStepData()"
                 */
                auto get(auto field) {
%ifdef QorusServer
                    return sdata.get(tld.stepID, tld.ind, field);
%endif
                }

                #! replaces @ref stepdata "dynamic step data"; the data has already been committed to the database when the method returns
                /** @note
                    - There is currently no function equivalent to this method for
                      @ref stepdata "workflow dynamic step data"; this method replaces all the data with \a new_data
                    - The use of this method causes SQL I/O to be performed in the system schema; to maximize
                      performance, calls to this and other similar methods should be minimized if possible
                 */
                nothing replace(*hash<auto> new_data) {
%ifdef QorusServer
                    sdata.replaceAndSave(tld.stepID, tld.ind, new_data, tld.wfe.workflow_instanceid);
                    Qorus.events.postWorkflowStepDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, tld.stepID, tld.ind);
%endif
                }

                #! adds data to @ref stepdata "dynamic step data"; the data has already been committed to the database when the method returns
                /** this method is equivalent to @ref OMQ::UserApi::Workflow::QorusStepBase::updateStepData() "QorusStepBase::updateStepData()"

                    @note The use of this method causes SQL I/O to be performed in the system schema; to maximize
                    performance, calls to this and other similar methods should be minimized if possible
                 */
                nothing update(hash<auto> new_data) {
%ifdef QorusServer
                    sdata.updateAndSave(tld.stepID, tld.ind, new_data, tld.wfe.workflow_instanceid);
                    Qorus.events.postWorkflowStepDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, tld.stepID, tld.ind);
%endif
                }

                #! deletes one or more keys from @ref stepdata "dynamic step data"; the changes have already been committed to the database when the method returns
                /** this method is equivalent to @ref OMQ::UserApi::Workflow::QorusStepBase::deleteStepDataKey() "QorusStepBase::deleteStepDataKey()"

                    @note The use of this method causes SQL I/O to be performed in the system schema; to maximize
                    performance, calls to this and other similar methods should be minimized if possible
                 */
                nothing deleteKey(softlist<softstring> keylist) {
%ifdef QorusServer
                    if (sdata.deleteAndSave(tld.stepID, tld.ind, keylist, tld.wfe.workflow_instanceid)) {
                        Qorus.events.postWorkflowStepDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, tld.stepID, tld.ind);
                    }
%endif
                }
            }
        }
    }
}
