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

public namespace OMQ {
#! This abstract class represents an observer that will get notified by the subject it observes
public class Observer inherits DataProvider::Observer;

#! This class represents an observable subject that will notify all of its registered observers
public class Observable inherits DataProvider::Observable {
    #! The method notifies all subscribed observers
    /** @param event_id unique ID identifying an event
        @param data_ hash representing new data to be passed to observers' update() methods
    */
    notifyObservers(string event_id, hash<auto> data_) {
        QDBG_LOG("%s::notifyObservers() event_id: %y data: %y map: %y", self.className(), event_id, data_,
            observer_map);
        map $1.observer.update(event_id, data_), observer_map.iterator(), !$1.event_map || $1.event_map{event_id};
    }

    #! Logs to the main process log file
    log(int level, string fmt) {
%ifdef QorusServer
        Qorus.logArgs(level, fmt, argv);
%endif
    }
}

#! This class represents an observable subject that waits for external confirmation before raising events
public class DelayedObservable inherits DataProvider::DelayedObservable;
}
