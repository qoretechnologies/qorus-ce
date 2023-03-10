# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusSubworkflowStepBase.qc interface definition for Qorus subworkflow steps

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

#! The %Qore base interface class for @ref subworkflowsteps "subworkflow steps"
/** @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.

    @see @ref subworkflowsteps
*/
public class OMQ::UserApi::Workflow::QorusSubworkflowStepBase inherits QorusStepBase {
    #! This method binds a workflow to a subworkflow step
    /** If this method is called twice or if called after skipSubworkflow(), then an exception is raised

        To ensure that a given workflow order is only created once for a given unique key value, make sure
        your workflow defines @ref wf_keylist "order keys", and use one of the following options to guarantee
        uniqueness of the order:
        - \c global_unique_key
        - \c workflow_specific_unique_key
        - \c workflow_unique_key

        @param wf This hash identifies the workflow type to be bound to the subworkflow step having the following keys:
        - \c name: (required) the workflow name for the new order
        - \c version: (optional) the version of the workflow for the new order\n
        Other keys will be ignored.  If the \c version key is not present, an order for the latest version of the
        workflow will be created

        @param order A hash defining the order data to be processed.  Valid keys for this hash are:
        - \c dynamicdata: (optional hash) the initial @ref dynamicdata "dynamic data" for the order
        - \c external_order_instanceid: (optional/required string) the external order instance ID for the workflow
          data; one of \c staticdata or \c external_order_instanceid must be provided
        - \c global_unique_key: (optional hash) a hash giving one or more unique @ref wf_keylist "order keys" for the
          order (across all workflows regardless of workflowid, name, or version); if this key already exists for any
          order in the system, then the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key
          must be a valid order key, and the value is the unique key value; this value will also be created as an
          order key
        - \c orderkeys: (optional hash; also \c order-keys is accepted for backwards-compatibility) a hash of
          @ref wf_keylist "order keys" for the order
        - \c priority: the order priority (optional int, default @ref OMQ::DefaultOrderPriority) from 0 - 999;
          priority 0 is the highest; 999 is the lowest
        - \c scheduled: (optional date) the earliest date and time the order can be processed; if this date is given
          as a future date/time value and a @ref OMQ::StatReady status is given, then the initial status of the
          workflow order data instance will be automatically changed to @ref OMQ::StatScheduled instead of
          @ref OMQ::StatReady
        - \c sensitive_data: (optional hash) a hash of sensitive data information for the workflow; this key can only
          be used when submitting the data over a secure (encrypted) connection; the keys are sensitive data key
          types, values are hashes keyed by sensitive data values, and the hash values have the following keys:
            - \c aliases: (optional list of strings) zero or more string aliases for the sensitive data
            - \c data: (required hash) the sensitive data hash itself
            - \c meta: (optional hash) a hash of metadata for the sensitive data with the following recommended keys
              (recommended keys are not enforced by the API itself):
                - \c PURPOSE: free-form information about the purpose of the sensitive data
                - \c CATEGORIES: free-form information about the categories of sensitive data
                - \c RECIPIENTS: free-form information about the recipients or recipient catories of sensitive data
                - \c STORAGE: free-form information about the storage time or rules for sensitive data
        - \c staticdata: (optional/required hash) the initial @ref staticdata "static data" for the order; one of
          \c staticdata or \c external_order_instanceid must be provided
        - \c tempdata: (optional hash) the initial @ref tempdata "temporary data" for the order
        - \c workflow_specific_unique_key: (optional string) a hash giving one or more unique
          @ref wf_keylist "order keys" for the particular workflowid (which matches a unique name and workflow
          version); if this key already exists for an order with the target workflowid, then the order creation will
          fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and the value is the
          unique key value; this value will also be created as an order key
        - \c workflow_unique_key: (optional string) a hash giving one or more unique @ref wf_keylist "order keys" for
          the particular workflow by name only (across all workflows with the same name regardless of version); if
          this key already exists for a workflow order with the same name, then the order creation will fail with a
          \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and the value is the unique key value;
          this value will also be created as an order key

        @return a hash with a single key: \c workflow_instanceid, the value of which is the workflow order data
        instance ID of the subworkflow

        @throw SUBWORKFLOW-ERROR invalid call (multiple call, etc), invalid arguments (unknown workflow, etc)
        @throw WORKFLOW-KEY-ERROR invalid workflow key given
        @throw ORDER-DATA-ERROR missing either \c external_order_instanceid or \c staticdata, unknown workflow;
        invalid keys or sensitive data format
        @throw DUPLICATE-ORDER-KEY the given unique key already exists in the defined scope, also sets \c arg with a
        \c workflow_instance_ids key with a list of all conflicting workflow instance IDs

        @note Subworkflow steps must call either this method or skipSubworkflow() or an error will be raised.

        @since
        - Qorus 3.1.1 implemented support for the following keys in the \a order argument:
          - \c global_unique_key
          - \c sensitive_data
          - \c workflow_specific_unique_key
          - \c workflow_unique_key

        @see
        - @ref wf_bind_subworkflow()
        - @ref skipSubworkflow()
    */
    public static hash<auto> bindSubworkflow(hash<auto> wf, hash<auto> order) {
%ifdef QorusServer
        QDBG_ASSERT(ensure_tld());
        if (!exists tld.subWorkflow) {
            throw "SUBWORKFLOW-ERROR", "QorusSubworkflowStepBase::bindSubworkflow() can only be called in a subworkflow step";
        }

        if (tld.skipSubWorkflow) {
            throw "SUBWORKFLOW-ERROR", "QorusSubworkflowStepBase::bindSubworkflow() called after skip_subworkflow()";
        }

        if (tld.subWorkflowInstanceID) {
            throw "SUBWROKFLOW-ERROR", "QorusSubworkflowStepBase::bindSubworkflow() can only be called once in a step";
        }

        # get workflow parameters
        if (!wf.name) {
            throw "SUBWORKFLOW-ERROR", "workflow name not passed in workflow hash";
        }

        # setup parent info
        hash<auto> parent_info = {
            "parent_workflow_instanceid": tld.wfe.workflow_instanceid,
            "parent_workflowid"         : Qorus.control.execHash{tld.index}.wf.workflowid,
            "parent_stepid"             : tld.stepID,
            "parent_ind"                : tld.ind,
            "subworkflow"               : True,
        };

        OrderData od(order);
        od.setParent(tld.wfe.workflow_instanceid, True);
        od.setNameAndVersion(wf.name, wf.version);

        # start a synchronous subworkflow if the caller is synchronous
        tld.subWorkflowInstanceID = tld.sync
            ? Qorus.control.startSynchronousSubWorkflow(parent_info, od.getWorkflowId(), od)
            : SM.bindSubWorkflow(parent_info, od.getWorkflowId(), od);

        QDBG_LOG("wf_bind_subworkflow finished subwf %y for order %y", tld.subWorkflowInstanceID, od.getWorkflowId());

        return {
            "workflow_instanceid": tld.subWorkflowInstanceID,
        };
%endif
    }

    #! This method will skip the execution of a subworkflow step
    /** Calling after bindSubworkflow() has already been called, and a subworkflow order instance has been bound to
        the step, will result in an exception.

        Calling this method twice for the same step will simply cause a message to be logged that the method was
        called twice.
        @return a hash with the following keys:
        - \c workflow_instanceid: the current workflow_instanceid
        - \c skipped: constant boolean \c True

        @throw SUBWORKFLOW-ERROR invalid call (not subworkflow step, subworkflow already bound, etc)

        @note Subworkflow steps must call either this method or bindSubworkflow() or an error will be raised.

        @see
        - @ref wf_skip_subworkflow()
        - @ref bindSubworkflow()
    */
    public static hash<auto> skipSubworkflow() {
%ifdef QorusServer
        QDBG_ASSERT(ensure_tld());
        if (!exists tld.subWorkflow) {
            throw "SUBWORKFLOW-ERROR", "QorusSubworkflowStepBase::skipSubworkflow() can only be called in a subworkflow step";
        }

        *string swfiid = tld.subWorkflowInstanceID;
        if (exists swfiid) {
            # if bindSubworkflow() has already been called, then throw an exception
            if (swfiid != tld.wfe.workflow_instanceid)
                throw "SKIP-SUBWORKFLOW-ERROR",
                    sprintf("QorusSubworkflowStepBase::bindSubworkflow() has already been called on this step which created workflow_instanceid %d bound to this step",
                        swfiid);

            tld.wf.logInfo("QorusSubworkflowStepBase::skipSubworkflow() can only be called once; ignoring superfluous call to skipSubworkflow()");
            return {
                "workflow_instanceid": swfiid,
                "skipped": True,
            };
        }

        tld.wf.logInfo("marking step for skipping subworkflow step");
        tld.skipSubWorkflow = True;

        softint wfiid = tld.wfe.workflow_instanceid;
        hash<auto> rh = {
            "workflow_instanceid" : wfiid,
            "skipped"             : True,
        };

        tld.subWorkflowInstanceID = wfiid;
        return rh;
%endif
    }
}
