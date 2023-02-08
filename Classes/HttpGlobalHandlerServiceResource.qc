# -*- mode: qore; indent-tabs-mode: nil -*-

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

public namespace OMQ;

class OMQ::HttpGlobalHandlerServiceResource inherits OMQ::AbstractHttpServiceResource {
    public {
        string hname;
    }

    constructor(int rsid, string n_name, string desc, string url, *softlist<auto> content_type,
            *softlist<auto> special_headers) :
                OMQ::AbstractHttpServiceResource(sprintf("http-global-%d", rsid), desc, url, content_type,
                    special_headers) {
        hname = n_name;
    }

    string getType() {
        return "HttpGlobalHandler";
    }

    stop(*bool aborted) {
        Qorus.httpServer.removeDynamicHandler(hname, aborted);
    }

    private bool disableImpl() {
        Qorus.httpServer.disableDynamicHandler(hname);
        return False;
    }
}
