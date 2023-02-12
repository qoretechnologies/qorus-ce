# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusEventArrayStep.qc class definition for Qorus event array steps

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

#! The abstract class for @ref eventsteps "workflow synchronization event array steps"
/** Workflow synchronization event steps allow many workflow orders to synchronize their processing based on a single
    event.

    Event steps may not have validation logic.

    @par Example
    @code{.py}
# name: MyEventArrayStepClass
# version: 1.0
# desc: my event array step class
class MyEventArrayStepClass inherits QorusEventArrayStep {
    softlist<auto> array() {
        # .. array logic
    }

    primary(auto array_arg) {
        # .. primary step logic; must call one of:
        # * bindEvent()
        # * bindEventUnposted()
        # * skipEvent()
    }
}
# END
    @endcode

    @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.

    @see @ref eventsteps and @ref arraysteps
*/
public class OMQ::UserApi::Workflow::QorusEventArrayStep inherits QorusEventStepBase {
    #! The array method returns the list of elements for the step
    /**
        @return The return value of the array function will determine how many times the step will execute, and on what
        data; null or a zero-length array means to skip the step entirely.  Each element in this array indicates an
        array step element; each element will be passed as the argument to primary() and validation()

        @note this method must always return the same list in the same order in every call (for example if the step
        must be recovereed); use @ref dynamicdata to save the list to ensure that this method always returns the same
        list in the same order if necessary
     */
    abstract public softlist<auto> array();

    #! The primary step logic for the event step
    /**
        @param array_arg the array element for this step index as returned by @ref array() "the array method"

        This code must call either @ref bindEvent(), @ref bindEventUnposted(),
        or @ref skipEvent() or an error will be raised.
    */
    abstract public nothing primary(auto array_arg);
}
