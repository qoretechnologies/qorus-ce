# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus ServerSessionBase class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

class OMQ::ServerSessionBase inherits OMQ::Session {
    constructor() : Session(::sqlif, Qorus.options.get("instance-key"), Qorus.options.get("db-max-threads"),
            Qorus.options.get("sql-default-blocksize")) {
    }

    destructor() {
        close();
    }

    private checkSystemProperties() {
%ifdef QorusQwfServer
        if (is_file(string filename = sprintf("%s/%s-check-system-props", tmp_location(), Qorus.getNetworkId()))) {
            QDBG_LOG("ServerSessionBase::checkSystemProperties() SIGNAL FILE %y found; unlinking", filename);
            unlink(filename);
            QDBG_LOG("ServerSessionBase::checkSystemProperties() TERMINATING");
            exit(1);
        } else {
            QDBG_LOG("ServerSessionBase::checkSystemProperties() NOT FOUND: %s", filename);
        }
%endif

        QorusRestartableTransaction trans();
        while (True) {
            try {
                Qorus.sysprops = checkSystemPropertiesIntern();

                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            break;
        }
    }

    synchronized open(Audit audit) {
        if (is_open) {
            return;
        }

        # check schema version and check for open sessions
        checkRecover(audit, "SYSTEM");

        logOpenSessionImpl();

        # get session ID and save session
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                openDbSessionImpl();

                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }

        logOpenedSessionImpl();

        is_open = True;
    }

    logFatal(string msg) {
        Qorus.logFatal(vsprintf("OMQ: " + msg, argv));
    }

    logError(string msg) {
        Qorus.logError(vsprintf("OMQ: " + msg, argv));
    }

    logWarn(string msg) {
        Qorus.logWarn(vsprintf("OMQ: " + msg, argv));
    }

    logInfo(string msg) {
        Qorus.logInfo(vsprintf("OMQ: " + msg, argv));
    }

    logDebug(string msg) {
        Qorus.logDebug(vsprintf("OMQ: " + msg, argv));
    }

    logTrace(string msg) {
        Qorus.logTrace(vsprintf("OMQ: " + msg, argv));
    }

    private abstract logOpenSessionImpl();
    private abstract logOpenedSessionImpl();
    private abstract logClosedSessionImpl();
    private abstract logErrorClosingSessionImpl(hash<ExceptionInfo> ex);

    private abstract openDbSessionImpl();
    private abstract closeDbSessionImpl();

    private string getFirstServer() {
        if (Qorus.options.get("http-secure-server")) {
            return ServerSessionBase::getServer("https", Qorus.options.get("http-secure-server"));
        }

        return ServerSessionBase::getServer("http", Qorus.options.get("http-server"));
    }

    synchronized close() {
        if (!is_open) {
            return;
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error sqlif.rollback();
                on_success sqlif.commit();

                closeDbSessionImpl();
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                logErrorClosingSessionImpl(ex);
                logInfo("DB %y: session will have to be recovered on next startup", desc);
            }
            trans.reset();
            break;
        }

        logClosedSessionImpl();

        is_open = False;
    }

    private static string getServer(string scheme, auto v) {
        string url = scheme + "://";
        softstring hp = v.typeCode() == NT_LIST ? v[0] : v;
        if (hp !~ /:/) {
            url += gethostname() + ":";
        }
        return url + hp;
    }
}
