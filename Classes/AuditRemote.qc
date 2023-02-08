# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

public namespace OMQ {
    public class AuditRemote inherits Audit {
        private {
            # connection to qorus-core
            AbstractQorusClient core;
        }

        constructor(SQLInterface n_sqlif, *softlist n_options, AbstractQorusClient n_core) : Audit(n_sqlif, n_options) {
            core = n_core;
        }

        logFatal(string msg) {
            Qorus.logFatal(msg, argv);
            logInfo(msg, argv);
        }

        logInfo(string msg) {
            string fmsg = vsprintf(msg, argv);
            core.checkResponseMsg(CPC_CORE_LOG_AUDIT, CPC_OK, core.sendCmdSerialized(CPC_CORE_LOG_AUDIT, fmsg));
        }
    }
}