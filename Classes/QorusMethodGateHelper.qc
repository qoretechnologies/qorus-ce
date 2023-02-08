# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file ServiceMethodGateHelper.qc Qorus communication class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

#! the main client namespace
public namespace OMQ {
    #! this class provides an easy way to call service methods on a Qorus server; this class is not designed to be used directly; use OMQ::QorusRemoteServiceHelper instead
    /** this classes uses OMQ::QorusSystemAPIHelperBase to make calls to service methods transparently as if the remote server service were a local class
        @see OMQ::QorusRemoteServiceHelper
     */
    public class ServiceMethodGateHelper {
        private {
            QorusSystemAPIHelperBase omqapi;
        }

        public {
            #! service type (either \c "system" or \c "user")
            string type;
            #! name of the service
            string name;
        }

        #! creates the object
        constructor(QorusSystemAPIHelperBase n_omqapi, string n_type, string n_name) {
            omqapi = n_omqapi;
            type = n_type;
            name = n_name;
        }

        #! redirects requests to the appropriate service method
        auto methodGate(string m) {
            string api = sprintf("omq.%s.service.%s.%s", type, name, m);
            return omqapi.callAPIArgs(api, argv);
        }

        #! redirects requests to the appropriate service method
        code memberGate(string m) {
            string api = sprintf("omq.%s.service.%s.%s", type, name, m);
            return auto sub () { return omqapi.callAPIArgs(api, argv); };
        }
    }
}
