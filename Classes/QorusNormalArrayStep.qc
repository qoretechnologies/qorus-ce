# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusNormalArrayStep.qc class definition for Qorus normal array steps

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

#! The abstract class for @ref normalsteps "normal array steps"
/** @par Example
    @code{.py}
%new-style
%require-types
%strict-types
%enable-all-warnings

class MyNormalStepClass inherits QorusNormalArrayStep {
    softlist<auto> array() {
        # ... array logic
    }

    primary(auto array_arg) {
        # ... primary step logic
    }

    string validation(auto array_arg) {
        # call checkAction() to check in the target DB if the action has completed
        if (checkAction(array_arg)) {
            return OMQ::StatComplete;
        }

        # call checkPending() to see if we retry or still wait
        return checkPending(array_arg) ? OMQ::StatAsyncWaiting : OMQ::StatRetry;
    }

    bool checkAction(auto array_arg) {
        # ... logic here
    }

    bool checkPending(auto array_arg) {
        # ... logic here
    }
}
# END
    @endcode

    @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.

    @see @ref normalsteps and @ref arraysteps
*/
public class OMQ::UserApi::Workflow::QorusNormalArrayStep inherits QorusStepBase {
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

    #! The primary step logic for the normal step
    /**
        @param array_arg the array element for this step index as returned by @ref array() "the array method"
    */
    abstract public nothing primary(auto array_arg);

    #! Validation logic for the step
    /**
        This method must be overridden for steps that can only execute once; by default this method will return
        @ref OMQ::StatRetry, meaning that the primary step logic will be repeated.

        @param array_arg the array element for this step index as returned by @ref array() "the array method"

        @return this must be one of the following @ref StatusDescriptions "step status constants":
        - @ref OMQ::StatComplete "StatComplete": do not run the primary step logic; mark the step as \c "COMPLETE" and continue
        - @ref OMQ::StatError "StatError": do not run the primary step logic; mark the step as \c "ERROR" and stop running any
          further dependencies of this step
        - @ref OMQ::StatRetry "StatRetry": run the step function again immediately

        @note if any other value than the above is returned, an error is raised and the return value is treated like
        @ref OMQ::StatError

        @see
        - @ref validationcode
        - @ref req3 "Non-Repeatable Steps Must Include Validation"
    */
    public string validation(auto array_arg) {
        return OMQ::StatRetry;
    }
}
