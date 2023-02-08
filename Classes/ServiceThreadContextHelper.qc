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

class ServiceThreadContextHelper {
    public {
        *OMQ::AbstractQorusService svc;
        *string _current_ix;
        *string method;
    }

    constructor(OMQ::AbstractQorusService svc, string method) {
        ensure_create_tld();
        # save old values
        self += tld{"svc", "_current_ix", "method"};

        # set new values
        tld += {
            "svc": svc,
            "_current_ix": "svc",
            "method": "method",
        };
    }

    destructor() {
        QDBG_ASSERT(ensure_tld());
        # restore old values
        if (exists svc) {
            tld.svc = svc;
        } else {
            remove tld.svc;
        }
        if (exists _current_ix) {
            tld._current_ix = _current_ix;
        } else {
            remove tld._current_ix;
        }
        if (exists method) {
            tld.method = method;
        } else {
            remove tld.method;
        }
    }
}

