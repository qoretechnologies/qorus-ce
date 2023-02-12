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
%include cpc-svc-api.ql
%include AbstractQorusClient.qc

# remote service client
/**
*/
class QsvcClient inherits AbstractQorusClient {
    public {
        int svcid;
    }

    #! creates the object
    /** @param process the owning process object
        @param type service type
        @param name service name
        @param version service version
        @param id service ID
        @param state_label ignored in the Community Edition
    */
    constructor(AbstractQorusClientProcess process, string type, string name, string version, int id,
            *string state_label)
            : AbstractQorusClient(process, QDP_NAME_QSVC, qsvc_get_process_id(type, name, version, id.toString(),
                state_label)) {
        svcid = id;
    }
}
