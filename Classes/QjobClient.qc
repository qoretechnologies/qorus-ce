# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

# here we add fallback paths to the QORE_INCLUDE_DIR search path,
# in case QORE_INCLUDE_DIR is not set properly
%append-include-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib

%include cpc-api.ql
%include cpc-job-api.ql
%include AbstractQorusClient.qc

%requires Util

# remote workflow client
/**
*/
class QjobClient inherits AbstractQorusClient {
    public {}

    private {
        int jobid;
    }

    private:internal {
    }

    #! creates the object
    /** @param process the owning process object
        @param wf the workflow of the cluster server process
    */
    constructor(AbstractQorusClientProcess process, string name, string version, int id) : AbstractQorusClient(process, QDP_NAME_QJOB, qjob_get_process_id(name, version, id.toString())) {
        self.jobid = id;
    }

    destructor() {
    }
}
