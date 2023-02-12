# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

class OMQ::DummyListenerInterface inherits HttpListenerInterface {
    addUserThreadContext(hash<auto> uctx) {
        save_thread_data("uctx", get_thread_data("uctx") + uctx);
    }

    auto removeUserThreadContext(*string k) {
        if (!exists k) {
            remove_thread_data("uctx");
            return;
        }
        *hash<auto> h = get_thread_data("uctx");
        auto rv = remove h{k};
        save_thread_data("uctx", h);
        return rv;
    }

    log(string fmt) {
        Qorus.logArgs(LoggerLevel::INFO, "LISTENER LOG: " + fmt, argv);
    }

    logError(string fmt) {
        Qorus.logArgs(LoggerLevel::ERROR, "LISTENER ERROR LOG: " + fmt, argv);
    }
}
