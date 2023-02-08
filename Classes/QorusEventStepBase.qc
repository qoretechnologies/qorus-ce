# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusEventStepBase.qc interface definition for Qorus event steps

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
%enable-all-warnings

#! The %Qore base interface class for @ref eventsteps "event steps"
/** @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.

    @see @ref eventsteps
*/
public class OMQ::UserApi::Workflow::QorusEventStepBase inherits QorusStepBase {
    #! binds a workflow synchronization event based on the event key to a workflow synchronization event step (type @ref OMQ::ExecEvent)
    /** If this method is called twice for the same step,  or if called after skipEvent(), then an exception is
        raised.  The @ref wf_sync_event_objects "event type" is defined when the step is defined in the workflow definition
        (see @ref step_event_type); this information does not need to be supplied here; only the event key, and the event
        will be automatically created (if it does not exist) or found in the queue as defined by its
        @ref wf_sync_event_objects "event type".

        @param eventkey the event key to bind the step to; if the event key does not already exist, then it is created
        in the table \c WORKFLOW_EVENTS and automatically tagged with its @ref wf_sync_event_objects "event type".  A record
        for this step is also created in \c STEP_INSTANCE_EVENTS

        @throw WORKFLOW-EVENT-ERROR invalid method call (multiple call, etc)

        @see
        - @ref wf_bind_event()
        - @ref eventsteps
        - @ref bindEventUnposted()
        - @ref skipEvent()

        @note either bindEvent(), bindEventUnposted(), or skipEvent() must be called in a workflow synchronization
        event step
    */
    public static bindEvent(string eventkey) {
%ifdef QorusServer
        SegmentManagerBase::bindEvent(eventkey);
%endif
    }

    #! binds a workflow synchronization event based on the event key to a workflow synchronization event step (type @ref OMQ::ExecEvent) only if the event has not yet been posted; if the event has already been posted, then an ALREADY-POSTED exception is raised
    /** If this method is called twice for the same step, or if called after skipEvent(), then an exception is raised.
        The @ref wf_sync_event_objects "event type" is defined when the step is defined in the workflow definition (see
        @ref step_event_type); this information does not need to be supplied here; only the event key, and the event will
        be automatically created (if it does not exist) or found in the queue as defined by its
        @ref wf_sync_event_objects "event type".

        @param eventkey the event key to bind the step to; if the event key does not already exist, then it is created
        in the table \c WORKFLOW_EVENTS and automatically tagged with its @ref wf_sync_event_objects "event type".  A record for
        this step is also created in \c STEP_INSTANCE_EVENTS

        @throw ALREADY-POSTED the given event has already been posted
        @throw WORKFLOW-EVENT-ERROR invalid method call (multiple call, etc)

        @see
        - @ref wf_bind_event_unposted()
        - @ref eventsteps
        - @ref bindEvent()
        - @ref skipEvent()

        @note either bindEvent(), bindEventUnposted(), or skipEvent() must be called in a workflow synchronization
        event step
    */
    public static bindEventUnposted(string eventkey) {
%ifdef QorusServer
        SegmentManagerBase::bindEventUnposted(eventkey);
%endif
    }

    #! skips a workflow synchronization event step
    /** If this method is called from any other step type, or if called after bindEvent(), then an exception is
        raised.  If called twice for the same step a message is logged, but no exception is raised.

        @throw WORKFLOW-EVENT-ERROR invalid method call (multiple call, etc)

        @see
        - @ref wf_skip_event()
        - @ref eventsteps
        - @ref bindEvent()
        - @ref bindEventUnposted()

        @note either bindEvent(), bindEventUnposted(), or skipEvent() must be called in a workflow synchronization
        event step
    */
    public static skipEvent() {
%ifdef QorusServer
        QDBG_ASSERT(ensure_tld());
        if (!exists tld.eventTypeID) {
            throw "WORKFLOW-EVENT-ERROR", "QorusEventStepBase::skipEvent() can only be called in a workflow event step";
        }

        if (exists tld.eventKey) {
            throw "WORKFLOW-EVENT-ERROR", sprintf("QorusEventStepBase::skipEvent() called, but event %y is already bound to this step",
                tld.eventKey);
        }

        if (tld.skipEvent) {
            tld.wf.logInfo("QorusEventStepBase::skipEvent() called multiple times for this step");
        }

        tld.wf.logInfo("marking step for skipping event step");
        tld.skipEvent = True;
%endif
    }
}
