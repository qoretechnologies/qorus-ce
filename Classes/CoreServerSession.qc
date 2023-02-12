# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus CoreServerSession class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

class OMQ::CoreServerSession inherits OMQ::ServerSessionBase {
    private:internal {
        bool reopen;
    }

    constructor(*int sessionid) : ServerSessionBase() {
        if (sessionid) {
            id = sessionid;
            reopen = True;
        }
    }

    logFatal(string msg) {
        OMQ::Session::logFatal(msg);
        Qorus.sendStartupMsg(msg);
    }

    logInfo(string msg) {
        OMQ::Session::logInfo(msg);
        Qorus.sendStartupMsg(msg);
    }

    private openDbSessionImpl() {
        if (id) {
            cast<ServerSQLInterface>(sqlif).sessionReopen(id, key, gethostname(), getFirstServer());
        }
        else {
            id = cast<ServerSQLInterface>(sqlif).sessionOpen2(key, gethostname(), getFirstServer());
        }
    }

    private closeDbSessionImpl() {
        cast<ServerSQLInterface>(sqlif).sessionClose(id);
    }

    private logOpenSessionImpl() {
        logInfo("DB %y: starting instance", desc);
    }

    private logOpenedSessionImpl() {
        logInfo("DB %y: %sopened session id: %d", desc, reopen ? "re" : "", id);
    }

    private logClosedSessionImpl() {
        logInfo("DB %y: closed session id: %d", desc, id);
    }

    private logErrorClosingSessionImpl(hash<ExceptionInfo> ex) {
        logInfo("DB %y: unable to close session id %d: %s: %s", desc, id, ex.err, ex.desc);
    }
}
