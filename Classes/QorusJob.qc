# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusJob.qc base class definition for class-based Qorus jobs

# Qorus Integration Engine

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

#! The abstract class for Qorus jobs
/** Qorus job constructors do not take any arguments; see @ref classjobconstructors for information about
    constructors and static class initialization.
*/
public class OMQ::UserApi::Job::QorusJob inherits OMQ::UserApi::Job::JobApi,
    OMQ::UserApi::QorusConfigurationItemProvider {
    #! The logic for the job
    /**
    */
    abstract public nothing run();
}
