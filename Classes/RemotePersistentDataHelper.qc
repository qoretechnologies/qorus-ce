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

class OMQ::RemotePersistentDataHelper inherits AbstractPersistentDataHelper {
    private {
        string rid;
    }

    constructor(string rid, hash<auto> cx, *hash<auto> ah) : AbstractPersistentDataHelper(cx, ah) {
        self.rid = rid;
    }

    destructor() {
        cast<RemoteQorusService>(getService()).deletePersistenceObject(rid);
    }

    auto methodGate(string m) {
        cast<RemoteQorusService>(getService()).doRemotePersistenceRequest(rid, m, argv);
    }
}