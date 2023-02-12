# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%allow-debugger

public namespace OMQ;

#! Implements logging to qorus log
class OMQ::QorusDebugLogger inherits DebugUtil::DebugLogger {
    constructor() : DebugLogger() {
    }

    public log2(int verbosity, string fmt, *list args) {
        if (verbose >= verbosity) {
            Qorus.log(verbosity, "DebugHandler: " + vsprintf(fmt, args));
        }
    }
}
