# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusAsyncStepBase.qc interface definition for Qorus async steps

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

#! The %Qore base interface class for @ref asyncsteps "asynchronous steps"
/**
    @note Qorus step constructors do not take any arguments; see @ref classstepconstructors for information about
    constructors and static class initialization.

    @see @ref asyncsteps
*/
public class OMQ::UserApi::Workflow::QorusAsyncStepBase inherits QorusStepBase {
    #! Binds the given key to the asynchronous step
    /**
        If this method is called more than once from an asynchronous step, an exception will be thrown.

        If the key already exists in the queue, an exception will be thrown.

        The queue name and ID is taken from the step definition; queue entries are created in the table \c QUEUE_DATA.

        @param key the key for the queue entry; must be unique in the queue

        @throw INVALID-FUNCTION-CALL invalid method call (double call, etc)
        @throw INVALID-KEY empty string passed for key

        @note Asynchronous steps must call either this method or skipAsyncStep() or an error will be raised.

        @see @ref wf_submit_async_key()
    */
    public static submitAsyncKey(string key) {
%ifdef QorusServer
        Qorus.control.execHash.(tld.index).submitAsyncKey(key);
%endif
    }

    #! This method will skip the execution of an asynchronous step
    /** Calling this method or submitAsyncKey() more than once from an asynchronous step will result in an exception.

        @throw INVALID-FUNCTION-CALL invalid method call (double call, etc)

        @note Asynchronous steps must call either this method or submitAsyncKey() or an error will be raised.

        @see @ref wf_submit_async_key()
    */
    public static skipAsyncStep() {
%ifdef QorusServer
        Qorus.control.execHash.(tld.index).skipAsyncStep();
%endif
    }
}
