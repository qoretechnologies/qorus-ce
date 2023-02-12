# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusServiceHelper.qc Qorus communication class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

#! the main client namespace
public namespace OMQ {
    #! mid-level class representing a service type (either \c "user" or \c "system") for transparently redirecting calls to services; this class is not designed to be used directly; use OMQ::QorusRemoteServiceHelper instead
    /** @see OMQ::QorusRemoteServiceHelper
     */
    public class QorusServiceHelper {
        private {
            QorusSystemAPIHelperBase omqapi;
            string type;
        }

        #! creates the object
        constructor(QorusSystemAPIHelperBase n_omqapi, string n_type) {
            omqapi = n_omqapi;
            type = n_type;
        }

        #! redirects calls to the appropriate ServiceMethodGateHelper member object
        synchronized auto memberGate(string m) {
            return self{m} = new ServiceMethodGateHelper(omqapi, type, m);
        }
    }
}
