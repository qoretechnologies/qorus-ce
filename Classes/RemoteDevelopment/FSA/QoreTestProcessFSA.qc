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

public namespace RemoteDevelopment;

/** Remote development test finite state automation for qore tests.

    Design info: https://git.qoretechnologies.com/qoretechnologies/wiki/-/wikis/Qorus-Remote-Development

    It's a Qorus private class - not exposed to public API.
*/

class RemoteDevelopment::QoreTestProcessFSA inherits RemoteDevelopment::TestProcessFSA {
    #! Constructs QoreTestProcessFSA object with given request
    #  Initialize method must be called to initialize the FSA (ProcessFSA method).
    /** @param request containing qtests to be run
        @throw BAD-REQUEST exception in case request is incorrect
        */
    constructor(TestRequest request) : TestProcessFSA(request, "qore") {
    }

    # overrides TestProcessFSA method
    private list<string> getArgList(*hash<auto> args) {
        list<string> result = map sprintf("-%s\"%s\"\n", $1.key, $1.value), args.pairIterator();
        return result;
    }

    # overrides TestProcessFSA method
    private list<hash<auto>> getTestFiles() {
        if (testRequest.qoreTestFiles) {
            return testRequest.qoreTestFiles;
        }
        return testRequest.qoreScriptFiles;
    }
}
