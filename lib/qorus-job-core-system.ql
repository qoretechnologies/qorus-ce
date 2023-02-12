# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

sub jilog(int lvl, string msg) {
    tld.job.logArgs(convert_old_log_level(lvl), msg, argv);
}

sub jilog_args(int lvl, string msg, *softlist<auto> args) {
    tld.job.logArgs(convert_old_log_level(lvl), msg, args);
}

auto sub job_get_option() {
    return tld.job.getOption(argv);
}

sub job_set_option(hash<auto> opts) {
    tld.job.setOptions(opts);
}

*int sub job_audit_user_event(string user_event, *string info1, *string info2) {
    return tld.job.auditUserEvent(user_event, info1, info2);
}

int sub job_sleep(softint s) {
    return tld.job.usleep(s * 1000000);
}

int sub job_usleep(softint s) {
    return tld.job.usleep(s);
}

int sub job_usleep(date s) {
    return tld.job.usleep(get_duration_microseconds(s));
}

#! loads the given module and returns the module name to cover the case when the argument is an absolute path
/** requires injection; cannot be in the client module
*/
string sub qorus_load_job_module(string mod) {
    return qorus_load_interface_module(IX_PGM_MOD_FAKE_WF | IX_PGM_MOD_FAKE_SVC, mod, JobClassList);
}
