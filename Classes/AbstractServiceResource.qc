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

public namespace OMQ;

# abstract class
class OMQ::AbstractServiceResource {
    private {
        string name;
        string desc;
        bool disabled = False;
    }

    public {}

    constructor(string n_name, string n_desc) {
        name = n_name;
        desc = n_desc;
    }

    string getName() {
        return name;
    }

    string getDesc() {
        return desc;
    }

    bool isDisabled() {
        return disabled;
    }

    # cannot lock; returns True if stopped
    bool disable() {
        disabled = True;
        return disableImpl();
    }

    private bool disableImpl() {
        stop();
        return True;
    }

    abstract stop(*bool aborted);
    abstract string getType();
    abstract hash<auto> getInfo(*hash<auto> cx);
}
