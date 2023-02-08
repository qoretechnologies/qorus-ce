# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusSubworkflowStep.qc class definition for Qorus subworkflow steps

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

#! The abstract class for @ref subworkflowsteps "subworkflow steps"
/** A subworkflow step binds a child workflow (called a subworkflow) to a step and should be used to
    implement support for complex logical branching in Qorus.

    Subworkflow steps may not have validation logic.

    @par Example
    @code{.py}
# name: MySubworkflowStep
# version: 1.0
# desc: my subworkflow step class
%new-style
%require-types
%strict-types
%enable-all-warnings

class MySubworkflowStep inherits QorusSubworkflowStep {
    primary() {
        # ... primary step logic; must call one of:
        # * wf_bind_subworkflow()
        # * wf_skip_subworkflow()
    }
}
# END
    @endcode

    @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.

    @see @ref subworkflowsteps
*/
public class OMQ::UserApi::Workflow::QorusSubworkflowStep inherits QorusSubworkflowStepBase {
    #! The primary step logic for the subworkflow step
    /**
        This code must call either @ref wf_bind_subworkflow() or @ref wf_skip_subworkflow()
        or an error will be raised.

        If the step is not to be skipped, then the step nust bind a subworkflow order to the step by
        calling the @ref wf_bind_subworkflow() workflow API function.
    */
    abstract public nothing primary();
}
