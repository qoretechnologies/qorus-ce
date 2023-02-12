# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Orders class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args

public namespace OMQ;

class OMQ::Orders {
    copy() {
        throw "COPY-ERROR", "this object cannot be copied";
    }

    int submitDataExtern(*hash<auto> cx, string name, *string version, hash<auto> params_arg,
            string status = OMQ::StatReady, *softint parent_workflow_instanceid) {
        ensure_create_tld();
        hash<auto> params += params_arg;
        # issue #2495: if no parent_workflow_instanceid is set in the order, then create it
        if (!params.parent_workflow_instanceid && parent_workflow_instanceid) {
            params.parent_workflow_instanceid = parent_workflow_instanceid;
        }
        return submitData(cx, name, version, params, status);
    }

    int submitData(*hash cx, string name, *string version, hash params, string status = OMQ::StatReady) {
        OrderData order(params);

        # 'S' status is set automatically depending on the scheduled date
        if (status == OMQ::StatScheduled) {
            status = OMQ::StatReady;
        }

        if (!inlist(status, (OMQ::StatReady, OMQ::StatBlocked))) {
            throw "SUBMIT-ORDER-ERROR", sprintf("not allowed status for new order: %s", status);
        }

        order.setNameAndVersion(name, version);
        softstring wfid = order.getWorkflowId();

        # save new order data to DB
        return SM.createWorkflowInstance(wfid, order, status);
    }
}
