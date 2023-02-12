# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusStepBase.qc base class definition for class-based Qorus steps

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

#! Base class for workflow step classes
/** @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.
*/
public class OMQ::UserApi::Workflow::QorusStepBase inherits OMQ::UserApi::Workflow::WorkflowApi,
    OMQ::UserApi::QorusConfigurationItemProvider {
    #! Returns the default @ref stepdata "dynamic step data" for the step when the step is first run
    /** @return the default @ref stepdata "dynamic step data" for the step when the step is first run

        The default implementation in the base class returns @ref nothing

        @note This method is executed at runtime when the step instance is first created

        @since Qorus 4.0.1
    */
    *hash<auto> getDefaultStepData() {
    }

    #! Returns @ref step_usermetadata "step user metadata" for the step when the step is loaded by @ref oload "oload"
    /** @return step_usermetadata "step user metadata" for the step when the step is loaded by @ref oload "oload"

        The default implementation in the base class returns @ref nothing

        @note This method is executed by @ref oload "oload" when the step is created in the database and therefore
        this method should not use any runtime functionality.

        @since Qorus 4.0.1
    */
    *hash<auto> getStepMetadata() {
    }

    #! Updates the values of one or more keys in the workflow order data instance’s @ref stepdata "dynamic step data hash"
    /** Dynamic step data is directly linked to the order data the workflow execution instance is processing.

        Changes are committed to the database before the method returns.

        @param new_data the key-value pairs to update in dynamic step data

        @note
        - This call does not replace the step data hash; any keys in the hash parameter are added to the step data
          hash
        - The use of this method causes SQL I/O to be performed in the system schema; to maximize performance, calls
          to this and other similar methods should be minimized if possible

        @see
        - @ref stepdata
        - StepDataHelper

        @since Qorus 4.0.1
    */
    static updateStepData(hash<auto> new_data) {
%ifdef QorusServer
        SM.updateStepData(new_data);
%endif
    }

    #! Deletes one or more keys from the workflow order data instance’s @ref stepdata "dynamic step data hash"
    /** Dynamic step data is directly linked to the order data the workflow execution instance is processing.

        Changes are committed to the database before the method returns.

        @param keylist a single key or a list of keys to delete in the workflow order's dynamic step data

        @note The use of this method causes SQL I/O to be performed in the system schema; to maximize performance, calls to this and other similar methods should be minimized if possible

        @see
        - @ref stepdata
        - StepDataHelper

        @since Qorus 4.0.1
    */
    static deleteStepDataKey(softlist<softstring> keylist) {
%ifdef QorusServer
        SM.deleteStepDataKey(keylist);
%endif
    }

    #! Retrieves the values of one or more keys from the workflow order data instance’s @ref stepdata "dynamic step data hash"
    /** Dynamic step data is directly linked to the order data the workflow execution instance is processing.

        Pass a single string argument, in which case the value of that key is returned, or a list of strings, in
        which case a hash is returned giving the values of all the keys requested

        @see
        - @ref stepdata
        - getStepDataArgs()
        - StepDataHelper
        - WorkflowDataHelper::get()

        @since Qorus 4.0.1
    */
    static auto getStepData() {
%ifdef QorusServer
        return SM.getStepData(argv);
%else
        delete argv;
%endif
    }

    #! Retrieves the values of one or more keys from the workflow order data instance’s @ref stepdata "dynamic step data hash"
    /** Dynamic step data is directly linked to the order data the workflow execution instance is processing.

        @param keylist for a single string argument, the value of that key is returned, for a list of strings, a hash
        is returned giving the values of all the keys requested

        @see
        - @ref stepdata
        - getStepData()
        - StepDataHelper
        - WorkflowDataHelper::get()

        @since Qorus 4.0.1
    */
    static auto getStepDataArgs(*softlist<softstring> keylist) {
%ifdef QorusServer
        return SM.getStepData(keylist);
%endif
    }
}
