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

class OMQ::ServiceResourceHelper {
    public {}

    private {
        OMQ::AbstractQorusCoreService svc;
        # service resource key mark
        int mark;
    }

    constructor(OMQ::AbstractQorusCoreService n_svc) {
        svc = n_svc;
        mark = svc.rsc.size();
    }

    rollback() {
        list l = svc.rsc.keys();
        splice l, 0, mark;
        map svc.removeResource($1), l;
    }
}
