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

class OMQ::FtpServiceResource inherits OMQ::AbstractServiceResource {
    public {
        int id;
    }

    constructor(int rsid, int n_id, string desc) : AbstractServiceResource(sprintf("ftp-%d", rsid), desc) {
        id = n_id;
    }

    string getType() {
        return "FtpListener";
    }

    private bool disableImpl() {
        Qorus.ftpServer.stopListenerIdNoWait(id);
        return False;
    }

    stop(*bool aborted) {
        Qorus.ftpServer.stopListenerId(id);
    }

    hash<auto> getInfo(*hash<auto> cx) {
        return Qorus.ftpServer.getListenerInfo(id);
    }
}

