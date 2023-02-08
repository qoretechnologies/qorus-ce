# -*- mode: qore; indent-tabs-mode: nil -*-

/*
  Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

  **** NOTICE ****
    All information contained herein is, and remains the property of Qore
    Technologies, s.r.o. and its suppliers, if any.  The intellectual and
    technical concepts contained herein are proprietary to Qore Technologies,
    s.r.o. and its suppliers and may be covered by Czech, European, U.S. and
    Foreign Patents, patents in process, and are protected by trade secret or
    copyright law.  Dissemination of this information or reproduction of this
    material is strictly forbidden unless prior written permission is obtained
    from Qore Technologies, s.r.o.
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace RemoteDevelopment;

/** Remote development test finite state automation for python tests.

    Design info: https://git.qoretechnologies.com/qoretechnologies/wiki/-/wikis/Qorus-Remote-Development

    It's a Qorus private class - not exposed to public API.
*/

class RemoteDevelopment::PythonTestProcessFSA inherits RemoteDevelopment::TestProcessFSA {
    #! Constructs PythonTestProcessFSA object with given request
    #  Initialize method must be called to initialize the FSA (ProcessFSA method).
    /** @param request containing qtests to be run
        @throw BAD-REQUEST exception in case request is incorrect
    */
    constructor(TestRequest request) : TestProcessFSA(request, "python3") {
    }

    private hash<auto> getProcessOptions() {
        string pypath = ENV.PYTHONPATH ?? sprintf("%s/python", ENV.OMQ_DIR);
        return TestProcessFSA::getProcessOptions() + {
            "env": ENV + {
                "PYTHONPATH": pypath,
            },
        };
    }

    # overrides TestProcessFSA method
    private list<string> getArgList(*hash<auto> args) {
        list<string> result = map sprintf("-%s\"%s\"\n", $1.key, $1.value), args.pairIterator();
        return result;
    }

    # overrides TestProcessFSA method
    private list<hash<auto>> getTestFiles() {
        if (testRequest.pythonTestFiles) {
            return testRequest.pythonTestFiles;
        }
        return testRequest.pythonScriptFiles;
    }
}
