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

class OMQ::RemoteHandlerBase {
    public {
        RemoteQorusService svc;
        string rid;
    }

    constructor(RemoteQorusService svc, string rid) {
        self.svc = svc;
        self.rid = rid;

        QDBG_LOG("RemoteHandlerBase self: %y svc: %y (%y) rid: %y keys: %y", self.uniqueHash(), svc ? svc.uniqueHash() : "NO SVC!", self.svc ? self.svc.uniqueHash() : "NO SVC!", rid, keys self);
    }
}
