# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusSubworkflowArrayStep.qc class definition for Qorus subworkflow array steps

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

#! The abstract class for @ref subworkflowsteps "subworkflow array steps"
/** A subworkflow step binds a child workflow (called a subworkflow) to a step and should be used to
    implement support for complex logical branching in Qorus.

    Subworkflow steps may not have validation logic.

    @par Example
    @code{.py}
# name: MySubworkflowArrayStep
# version: 1.0
# desc: my subworkflow array step class
%new-style
%require-types
%strict-types
%enable-all-warnings

class MySubworkflowArrayStep inherits QorusSubworkflowArrayStep {
    softlist<auto> array() {
        # .. array logic
    }

    primary(auto array_arg) {
        # ... primary step logic; must call one of:
        # * wf_bind_subworkflow()
        # * wf_skip_subworkflow()
    }
}
# END
    @endcode

    @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.

    @see @ref subworkflowsteps and @ref arraysteps
*/
public class OMQ::UserApi::Workflow::QorusSubworkflowArrayStep inherits QorusSubworkflowStepBase {
    #! The array method returns the list of elements for the step
    /**
        @return The return value of the array function will determine how many times the step will execute, and on
        what data; null or a zero-length array means to skip the step entirely.  Each element in this array indicates
        an array step element; each element will be passed as the argument to primary() and validation()

        @note this method must always return the same list in the same order in every call (for example if the step
        must be recovereed); use @ref dynamicdata to save the list to ensure that this method always returns the same
        list in the same order if necessary
     */
    abstract public softlist<auto> array();

    #! The primary step logic for the subworkflow step
    /**
        @param array_arg the array element for this step index as returned by @ref array() "the array method"

        This code must call either @ref wf_bind_subworkflow() or @ref wf_skip_subworkflow()
        or an error will be raised.

        If the step is not to be skipped, then the step nust bind a subworkflow order to the step by
        calling the @ref wf_bind_subworkflow() workflow API function.
    */
    abstract public nothing primary(auto array_arg);
}
