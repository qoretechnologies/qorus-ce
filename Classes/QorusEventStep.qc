# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusEventStep.qc class definition for Qorus event steps

# Qorus Integration Engine

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

#! The abstract class for @ref eventsteps "workflow synchronization event steps"
/** Workflow synchronization event steps allow many workflow orders to synchronize their processing based on a single
    event.

    Event steps may not have validation logic.

    @par Example
    @code{.py}
# name: MyEventStepClass
# version: 1.0
# desc: my event array step class
class MyEventStepClass inherits QorusEventStep {
    primary() {
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

    @see @ref eventsteps
*/
public class OMQ::UserApi::Workflow::QorusEventStep inherits QorusEventStepBase {
    #! The primary step logic for the event step
    /** This code must call either @ref bindEvent(), @ref bindEventUnposted(),
        or @ref skipEvent() or an error will be raised.
    */
    abstract public nothing primary();
}
