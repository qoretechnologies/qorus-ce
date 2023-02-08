# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file UserApi.qc methods common to workflow, service, and job APIs

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

public namespace OMQ {
public namespace UserApi {
#! Class that allows for managing restartable transactions
public class QorusRestartableTransaction {
    public {}

    private {
        date start = now_us();
        string driver;
        int count = 0;
        const DefaultDelay = 10s;
    }

    constructor() {
%ifndef QorusFakeApi
%ifdef QorusServer
        driver = Qorus.getSystemDbDriverName();
%else
        driver = omq.getDriverName();
%endif
%endif
    }

    constructor(string driver) {
        self.driver = driver;
    }

    destructor() {
        resetIntern();
    }

    *string restartTransaction(hash<auto> ex) {
%ifndef QorusFakeApi
        while (True) {
            *string msg;
            if (ex.err == "DATASOURCEPOOL-PROCESS-ERROR") {
                msg = "Qorus qdsp cluster server failover event; restart transaction";
            } else if (ex.err == "DATASOURCEPOOL-TIMEOUT") {
                msg = "Qorus qdsp cluster pool access timeout; restart transaction";
            } else {
                msg = restart_transaction_intern(driver, ex);
            }
            if (msg) {
                date delay;
                if (++count > 2) {
                    delay = DefaultDelay;
                } else {
                    delay = 0s;
                }
                string errmsg = sprintf("transaction must be restarted; count: %d; delay: %s", count,
                    delay ? sprintf("%y", delay) : "none");
                if (count > 2) {
                    errmsg += sprintf(" (elapsed time: %y)", now_us() - start);
                }
                errmsg += ": " + msg;

%ifdef QorusCore
                qlog(LoggerLevel::ERROR, "%s", errmsg);
%else
%ifdef QorusServer
                Qorus.log(LoggerLevel::ERROR, "%s", errmsg);
%else
                printf("%s\n", errmsg);
%endif
%endif
                if (delay) {
                    sleep(delay);
                }
                return errmsg;
            }
            if (!ex.next) {
                break;
            }
            ex = ex.next;
        }
%endif
    }

    int getCount() {
        return count;
    }

    reset() {
        resetIntern();
        count = 0;
    }

    private resetIntern() {
        if (!count) {
            return;
        }
        string msg = sprintf("transaction recovered in %d attempts; elapsed time: %y", count + 1,
            now_us() - start);
%ifdef QorusCore
        qlog(LoggerLevel::ERROR, "%s", msg);
%else
%ifdef QorusServer
        Qorus.log(LoggerLevel::ERROR, "%s", msg);
%else
        printf("%s\n", msg);
%endif
%endif
    }
}
}
}