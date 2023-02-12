# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args
%enable-all-warnings

%requires HttpServerUtil
%requires RestHandler
%requires SqlUtil

#! This class is not implemented in the Community Edition
/** @see @ref dep_serviceauthlabels for more information on authentication labels in the Enterprise Edition
*/
class OMQ::QorusParametrizedAuthenticator inherits public HttpServer::AbstractAuthenticator {
    private {
        string authlabelname;
        int svcid;
    }

    #! creates the authentication handler with the given label
    /** @param authLabel the authentication label that describes how requests will be authenticated; see
        @ref dep_serviceauthlabels for more information
    */
    constructor(string authLabel) : AbstractAuthenticator() {
        self.authlabelname = authLabel;
        self.svcid = tld.svc.serviceid;

        # validate label on init
        getAuthLabelValue();
    }

    static initializeAuthenticators() {
    }

    #! returns the label name
    string getAuthLabel() {
        return self.authlabelname;
    }

    #! authenticates incoming HTTP requests
    *hash<HttpResponseInfo> authenticateRequest(HttpListenerInterface listener,
                                            hash<auto> hdr, reference<hash> cx) {
    }

    private hash<auto> getAuthLabelValue() {
        *hash<auto> auth_label = Qorus.qmm.getAuthLabel(svcid, authlabelname);
        if (!auth_label) {
            throw "AUTH-ERROR",
                   sprintf("authentication label \"%s\" does not exist in service \"%d\"",
                            authlabelname, svcid);
        }
        return auth_label;
    }
}
