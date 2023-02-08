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

class OMQ::AbstractHttpServiceResourceBase inherits OMQ::AbstractServiceResource {
    public {
        *softlist content_type;
        *softlist special_headers;
    }

    constructor(string name, string desc, *softlist<auto> n_content_type, *softlist<auto> n_special_headers)
            : AbstractServiceResource(name, desc) {
        content_type = n_content_type;
        special_headers = n_special_headers;
    }

    hash<auto> getInfo(*hash<auto> cx) {
        return {
            "content": content_type,
            "headers": special_headers,
        };
    }
}

