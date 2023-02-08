# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file RemoteServiceHelper.qc defines classes used in the client library

# this file must be used with the Qorus client library and should not be included directly by Qorus client programs

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

#! the main client namespace
public namespace OMQ {
    #! top-level class for transparently redirecting calls to services
    public class QorusRemoteServiceHelper {
        public {
            #! QorusServiceHelper object for system services
            QorusServiceHelper system;
            #! QorusServiceHelper object for user services
            QorusServiceHelper user;
        }

        #! creates the object with QorusServiceHelper members for \c "system" and \c "user" services
        constructor(QorusSystemAPIHelperBase omqapi) {
            system = new QorusServiceHelper(omqapi, "system");
            user   = new QorusServiceHelper(omqapi, "user");
        }
    }
}

