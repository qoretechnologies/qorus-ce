# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

#! main Qorus namespace
public namespace OMQ {
class AbstractServiceEventObserver inherits DataProvider::Observer {
    private {
        LocalQorusService svc;
        string event_source_name;
    }

    constructor(LocalQorusService svc, string event_source_name) {
        self.svc = svc;
        self.event_source_name = event_source_name;
    }

    string getEventSourceName() {
        return event_source_name;
    }

    update(string event_id, hash<auto> data_) {
        svc.logDebug("%s event %y: %y", event_source_name, event_id, data_);
        try {
            updateImpl(event_id, data_);
        } catch (hash<ExceptionInfo> ex) {
            svc.logError("%s service %s v%s (%d) event source %y: error processing event %y: %s",
                svc.type, svc.name, svc.version, svc.serviceid, event_source_name, event_id,
                get_exception_string(ex));
        }
    }

    abstract updateImpl(string event_id, hash<auto> data_);
}
}
