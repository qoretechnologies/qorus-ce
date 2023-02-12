# -*- mode: qore; indent-tabs-mode: nil -*-

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

public namespace OMQ;

class OMQ::AbstractHttpServiceResource inherits OMQ::AbstractHttpServiceResourceBase {
    public {
        string url;
    }

    constructor(string name, string desc, string n_url, *softlist<auto> n_content_type,
            *softlist<auto> n_special_headers) : AbstractHttpServiceResourceBase(name, desc, n_content_type,
                n_special_headers) {
        url = n_url;
    }
}
