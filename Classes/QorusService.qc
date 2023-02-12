# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusService.qc base class definition for class-based Qorus services

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

#! The base class for Qorus services
/** Qorus service constructors do not take any arguments; see @ref classserviceconstructors for information about
    constructors and static class initialization.
*/
public class OMQ::UserApi::Service::QorusService inherits OMQ::UserApi::Service::ServiceApi,
    OMQ::UserApi::QorusConfigurationItemProvider {
}
