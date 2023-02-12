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

public namespace OMQ;

class OMQ::ServiceTemplateManager inherits WebUtil::StaticTemplateManager {
    private:internal {
        bool sys;
    }

    constructor(bool sys, *int po) : StaticTemplateManager(TextTemplateBase::DefaultProgramOptions | ServiceParseOptions | po) {
        self.sys = sys;
    }

    setupProgram(Program p) {
        # define OMQ namespace for API
        p.parsePending("public namespace OMQ;", "<static webutil template: OMQ namespace>");

        # define all runtime properties in the template program
        map p.define($1.key, $1.value), Qorus.getRuntimeProps().pairIterator();

        # define all strings in the QorusServiceDefines list in the template program
        map p.define($1, True), QorusServiceDefines;

        # load in service api functions
        map $1.import ? p.importFunction($1.actual, $1.import) : p.importFunction($1), ServiceAPI;

        # setup program
        LocalQorusService::setupProgram(p, sys, True);
    }
}
