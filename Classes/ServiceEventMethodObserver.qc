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

#! main Qorus namespace
public namespace OMQ {
class ServiceEventMethodObserver inherits AbstractServiceEventObserver {
    private {
        string method;
    }

    constructor(LocalQorusService svc, string event_source_name, hash<auto> config)
            : AbstractServiceEventObserver(svc, event_source_name) {
        self.method = config.value;
    }

    updateImpl(string event_id, hash<auto> data_) {
        svc.callLocalMethod(method, event_id, data_);
    }
}
}