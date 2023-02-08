# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args
%enable-all-warnings

# used when binding SOAP listeners in *ServiceManager::bindSoapListener*()
const ListenerParams = ("cert_path", "key_path", "key_password", "key", "cert");

int sub service_sleep(softint s) {
    OMQ::LocalQorusService svc = tld.svc;
    return svc.usleep(s * 1000000);
}

int sub service_usleep(softint s) {
    OMQ::LocalQorusService svc = tld.svc;

    return svc.usleep(s);
}

int sub service_usleep(date s) {
    OMQ::LocalQorusService svc = tld.svc;
    return svc.usleep(get_duration_microseconds(s));
}

hash sub qorus_get_thread_stacks() {
    return get_all_thread_call_stacks();
}

#! loads the given module and returns the module name to cover the case when the argument is an absolute path
/** requires injection; cannot be in the client module
*/
string sub qorus_load_service_module(string mod) {
    return qorus_load_interface_module(IX_PGM_MOD_FAKE_WF | IX_PGM_MOD_FAKE_JOB, mod, ServiceClassList);
}
