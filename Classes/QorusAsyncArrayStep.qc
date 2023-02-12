# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusAsyncArrayStep.qc class definition for Qorus async array steps

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

#! The abstract class for @ref asyncsteps "asynchronous array steps"
/** An asynchronous step should be used any time a workflow action should be executed and it's not known in advance
    how long the action could take, or if the action should take a long period of time.

    @par Example
    @code{.py}
# name: MyAsyncArrayStepClass
# version: 1.0
# desc: my async step class
%new-style
%require-types
%strict-types
%enable-all-warnings

class MyAsyncArrayStepClass inherits QorusAsyncArrayStep {
    softlist<auto> array() {
        # ... array logic
    }

    primary(auto array_arg) {
        # ... primary step logic
    }

    string validation(*string key, auto array_arg) {
        # call checkAction() to check in the target DB if the action has completed
        if (checkAction(key)) {
            return OMQ::StatComplete;
        }

        # call checkPending() to see if we retry or still wait
        return checkPending(key) ? OMQ::StatAsyncWaiting : OMQ::StatRetry;
    }

    end(hash<auto> data, auto array_arg) {
        # the error thrown here should be defined as a workflow error
        if (data.status == "ERROR") {
            throw "ASYNC-RECEIVE-ERROR";
        } else {
            log(LoggerLevel::INFO, "data status: %y", data.status);
        }
    }

    bool checkAction(string key) {
        # ... logic here
    }

    bool checkPending(string key) {
        # ... logic here
    }
}
# END
    @endcode

    @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.

    @see @ref asyncsteps and @ref arraysteps
*/
public class OMQ::UserApi::Workflow::QorusAsyncArrayStep inherits QorusAsyncStepBase {
    #! The array method returns the list of elements for the step
    /**
        @return The return value of the array method will determine how many times the step will execute, and on what
        data; null or a zero-length array means to skip the step entirely.  Each element in this array indicates an
        array step element; each element will be passed as the argument to primary() and validation()

        @note this method must always return the same list in the same order in every call (for example if the step
        must be recovereed); use @ref dynamicdata to save the list to ensure that this method always returns the same
        list in the same order if necessary
     */
    abstract public softlist<auto> array();

    #! The primary step logic for the async step
    /**
        @param array_arg the array element for this step index as returned by @ref array() "the array method"

        This code must call either @ref submitAsyncKey() or @ref skipAsyncStep()
        or an error will be raised.

        If the step is not to be skipped, then the step nust start the asynchronous action and save a unique key for
        the action by calling the @ref submitAsyncKey() workflow API method.
    */
    abstract public nothing primary(auto array_arg);

    #! Validation logic for the step
    /**
        This method must be overridden for steps that can only execute once; by default this method will return
        @ref OMQ::StatRetry, meaning that the primary step logic will be repeated.

        @param async_key the asynchronous key for the step, if bound, if not, this value will be @ref nothing
        @param array_arg the array element for this step index as returned by @ref array() "the array method"

        @return this must be one of the following @ref StatusDescriptions "step status constants":
        - @ref OMQ::StatComplete "StatComplete": do not run the primary step logic; mark the step as \c "COMPLETE" and continue.
          For asynchronous steps, the @ref asyncbackendcode "back-end logic" (@ref end()) will not be run in this case
        - @ref OMQ::StatError "StatError": do not run the primary step logic; mark the step as \c "ERROR" and stop running any
          further dependencies of this step
        - @ref OMQ::StatRetry "StatRetry": run the step logic again immediately.  If the step is an asynchronous step with queue
          data with a @ref OMQ::QS_Waiting status, the queue data will be deleted immediately before the step code
          is run again
        - @ref OMQ::StatAsyncWaiting "StatAsyncWaiting": for asynchronous steps only, do not run the step code and keep the
          \c "ASYNC-WAITING" status.  For non-asynchronous steps, raises an error and the return value is treated like
          @ref OMQ::StatError

        @note if any other value than the above is returned, an error is raised and the return value is treated like
        @ref OMQ::StatError

        @see
        - @ref validationcode
        - @ref req3 "Non-Repeatable Steps Must Include Validation"
    */
    public string validation(*string async_key, auto array_arg) {
        return OMQ::StatRetry;
    }

    #! This method is run when the queue data bound to the asynchronous is updated and receives status @ref OMQ::QS_Received
    /**
        The job of this method is to determine if the asynchronously-received data is correct or not; if it is not
        correct, then the code should raise an error by calling wf_serror() or by throwing an appropriate exception.
        If no validation of the data is required, then the method body may be empty.

        @param queue_data any data that was posted when the queue status got status @ref OMQ::QS_Received
        @param array_arg the array element for this step index as returned by @ref array() "the array method"

        @note the implementation of the logic in this base class is empty; it must be overridden in child classes to
        react to the async queue data
    */
    public nothing end(auto queue_data, auto array_arg) {
    }
}
