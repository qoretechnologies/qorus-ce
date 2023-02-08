# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

# here we add fallback paths to the QORE_INCLUDE_DIR search path,
# in case QORE_INCLUDE_DIR is not set properly
%append-include-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib

%include cpc-api.ql
%include cpc-wf-api.ql
%include AbstractQorusClient.qc

%requires Util

# remote workflow client
/**
*/
class QwfClient inherits AbstractQorusClient {
    public {}

    private {
        int wfid;
    }

    private:internal {
    }

    #! creates the object
    /** @param process the owning process object
        @param wf the workflow of the cluster server process
    */
    constructor(AbstractQorusClientProcess process, string wfname, string wfversion, softint wfid) : AbstractQorusClient(process, QDP_NAME_QWF, qwf_get_process_id(wfname, wfversion, wfid.toString())) {
        self.wfid = wfid;
    }

    destructor() {
    }
}
