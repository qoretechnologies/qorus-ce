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

class OMQ::QorusStreamHandlerResource inherits OMQ::AbstractServiceResource {
    public {
        list<string> methods;
    }

    constructor(string name, list<string> methods, string desc) : AbstractServiceResource(name, desc) {
        self.methods = methods;
    }

    string getType() {
        return "StreamHandler";
    }

    stop(*bool aborted) {
    }

    hash<auto> getInfo(*hash<auto> cx) {
        return {"methods": methods};
    }
}
