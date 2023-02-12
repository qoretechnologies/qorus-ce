# -*- mode: qore; indent-tabs-mode: nil -*-
# qorus-logger.ql

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

sub qorus_log_args(softint lvl, string msg, auto args) {
    # log to system logger
    if (Qorus) {
        Qorus.logArgs(lvl, msg, args);
    } else {
        # otherwise log to stdout
        stdout.printf("%s T%d: %s\n", log_now(), gettid(), vsprintf(msg, args));
    }
}

# for logging OMQ messages
sub olog_args(softint lvl, string msg, auto args) {
    Qorus.logArgs(lvl, "OMQ: " + msg, args);
}

# for logging OMQ messages
sub olog(softint lvl, string msg) {
    Qorus.logArgs(lvl, "OMQ: " + msg, argv);
}

# for logging JOB messages
sub jlog_args(softint lvl, string msg, auto args) {
    Qorus.logArgs(lvl, "JOB: " + msg, args);
}

# for logging JOB messages
sub jlog(softint lvl, string msg) {
    Qorus.logArgs(lvl, "JOB: " + msg, argv);
}

# NOTE: this is used in the mapper context, where it is probably too tricky to
# get the context? --PQ 16-Jun-2016
sub qlog(softint lvl, string fmt) {
    qlog_args(lvl, fmt, argv);
}

sub qlog_args(softint lvl, string fmt, auto args) {
    try {
        if (tld.svc instanceof OMQ::Service) {
            cast<OMQ::Service>(tld.svc).logArgs(lvl, fmt, args);
            return;
        }
        if (tld.job instanceof OMQ::Job) {
            cast<OMQ::Job>(tld.job).logArgs(lvl, fmt, args);
            return;
        }
    } catch (hash<ExceptionInfo> ex) {
        if (ex.err != "OBJECT-ALREADY-DELETED") {
            rethrow;
        }
    }

    Qorus.logArgs(lvl, fmt, args);
}

#! Saves the information passed to the system log file.
/** @deprecated This function is present for backwards-compatibility; use @ref log() instead
    @param ds the datasource for the SQL message
    @param msg the format string for a vsprintf() call with the remaining arguments
*/
deprecated sub osqllog(string ds, string str) {
    Qorus.logInfo(sprintf("SQL %s: %s", ds, vsprintf(str, argv)));
}
