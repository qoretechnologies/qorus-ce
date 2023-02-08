# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusService.qc base class definition for class-based Qorus services

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

#! The base class for Qorus services
/** Qorus service constructors do not take any arguments; see @ref classserviceconstructors for information about
    constructors and static class initialization.
*/
public class OMQ::UserApi::Service::QorusService inherits OMQ::UserApi::Service::ServiceApi,
    OMQ::UserApi::QorusConfigurationItemProvider {
}
