# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%requires qore >= 0.9

%new-style
%require-our
%strict-args
%require-types

%enable-all-warnings

class QorusClusterOptions {
    private {
        hash<auto> opts;
    }

    init() {
        remove opts;
        opts += Qorus.options_client.get();
    }

    setExtern(string opt, auto val) {
        opts{opt} = val;
    }

    setExtern(hash new_opts) {
        opts += new_opts;
    }

    auto get() {
        return opts;
    }

    auto get(string opt) {
        return opts{opt};
    }

    auto get(list<auto> l) {
        return opts{l};
    }

    set(hash<auto> h) {
        hash<auto> oh = Qorus.options_client.setExtern(h);
        opts += oh.val;

        if (oh.errs) {
            throw "OPTION-ERROR", sprintf("the following error%s occurred setting system options: %y",
                oh.errs == 1 ? "" : "s", oh.errs);
        }
    }

    string getClientUrl() {
        return Qorus.options_client.getClientUrl();
    }

    string getClientUrl(string username, string password) {
        return Qorus.options_client.getClientUrl(username, password);
    }
}
