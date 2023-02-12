# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusNormalStep.qc class definition for Qorus normal steps

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

#! The abstract class for @ref normalsteps "normal steps"
/** @par Example
    @code{.py}
%new-style
%require-types
%strict-types
%enable-all-warnings

class MyNormalStepClass inherits QorusNormalStep {
    primary() {
        # ... primary step logic
    }

    string validation() {
        # call checkAction() to check in the target DB if the action has completed
        if (checkAction()) {
            return OMQ::StatComplete;
        }

        # call checkPending() to see if we retry or still wait
        return checkPending() ? OMQ::StatAsyncWaiting : OMQ::StatRetry;
    }

    bool checkAction() {
        # ... logic here
    }

    bool checkPending() {
        # ... logic here
    }
}
# END
    @endcode

    @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.

    @see @ref normalsteps
*/
public class OMQ::UserApi::Workflow::QorusNormalStep inherits QorusStepBase {
    #! The primary step logic for the normal step
    /**
    */
    abstract public nothing primary();

    #! Validation logic for the step
    /**
        This method must be overridden for steps that can only execute once; by default this method will return
        @ref OMQ::StatRetry, meaning that the primary step logic will be repeated.

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
    public string validation() {
        return OMQ::StatRetry;
    }
}
