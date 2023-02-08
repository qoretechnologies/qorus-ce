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


# issue #3319: to ensure that the correct interface context is always used
class OMQ::InterfaceContextHelper {
    public {}

    private {
        *string ix;
    }

    private constructor(string ix) {
        self.ix = tld._current_ix;
        tld._current_ix = ix;
    }

    destructor() {
        tld._current_ix = ix;
    }
}

class OMQ::WorkflowContextHelper inherits InterfaceContextHelper {
    constructor() : InterfaceContextHelper("wf") {
    }
}

class OMQ::ServiceContextHelper inherits InterfaceContextHelper {
    constructor() : InterfaceContextHelper("svc") {
    }
}

class OMQ::JobContextHelper inherits InterfaceContextHelper {
    constructor() : InterfaceContextHelper("job") {
    }
}
