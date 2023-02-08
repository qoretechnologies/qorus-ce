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

class OMQ::HttpUserServiceResource inherits OMQ::AbstractServiceResource {
    public {
        AbstractServiceHttpHandler handler;
    }

    private:internal {
        # we must save the user info here, as the handler can be reused without this information
        string heading;
        string title;
        string url;
    }

    constructor(AbstractServiceHttpHandler n_handler) : AbstractServiceResource(n_handler.utitle,
            sprintf("serving URL: %s", n_handler.uurl)) {
        handler = n_handler;
        heading = handler.utype;
        title = handler.utitle;
        url = handler.uurl;
        services.setUserHttpServiceInfo(url, handler);
    }

    string getType() {
        return "HttpUserService";
    }

    stop(*bool aborted) {
        services.removeUserHttpServiceInfo(url);
    }

    hash<auto> getInfo(*hash<auto> cx) {
        return {
            "heading": heading,
            "title": title,
            "url": cx ? qorus_get_url(cx, url) : url,
        };
    }
}
