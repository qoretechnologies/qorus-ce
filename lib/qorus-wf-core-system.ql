# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

public namespace OMQ {
    #! workflow instance thread data hash
    const WFITDHash = {
        "mode": True,
    };

    #! workflow data hash
    const WFDHash = {
        "name": True,
        "version": True,
        "workflowid": True,
        "remote": True,
    };

    #! workflow entry data hash
    const WFEHash = {
        "workflow_instanceid": True,
        "started": True,
        "priority": True,
        "external_order_instanceid": True,
        "initstatus": True,
        "status": True,
        "dbstatus": True,
    };

    #! workflow entry data hash
    const WFEParentHash = {
        "parent_workflow_instanceid": True,
    };

    #! workflow instance object data hash
    const WFIOHash = {
        "instancemode": True,
        "execid": True,
        "starttime": True,
    };
}

# encrypt the data needed for a row in sensitive_order_data
hash sub encrypt_order_data(softint wfiid, string skey, string svalue, hash info, *hash meta) {
    return Qorus.encryptOrderData(wfiid, skey, svalue, info, meta);
}

# returns NOTHING in case of a DB error
*int sub log_error(string err, softstring desc = "", auto info, *string severity = "UNKNOWN", *string status,
        *softbool business) {
    QDBG_ASSERT(ensure_tld());
    int eeid;

    *softint stepid = tld.attachInProgress ? NOTHING : tld.stepID;
    *softint ind = tld.attachInProgress ? NOTHING : tld.ind;
    bool retry = status == OMQ::StatRetry;

    if (exists info && info.typeCode() != NT_STRING)
        info = serialize_qorus_data(info);

    while (True) {
        try {
            on_error omqp.rollback();
            on_success omqp.commit();

            eeid = sqlif.insertErrorInstance(tld.wfe.workflow_instanceid, stepid, ind, severity, retry, err, desc,
                info, business);
            QDBG_TEST_CLUSTER_FAILOVER();
        } catch (hash<ExceptionInfo> ex) {
            # restart the transaction if necessary
            if (sqlif.restartTransaction(ex))
                continue;
            olog(LoggerLevel::FATAL, "Exception thrown while trying to write error to OMQ error_instance table: "
                "%s: %s", ex.err, ex.desc);
            olog(LoggerLevel::FATAL, "workflow_instanceid: %y, stepid: %y, ind: %y, severity: %y, retry: %y, "
                "error: %y, description: %y, info: %y, business: %y, tld: %y",
                tld.wfe.workflow_instanceid, stepid, ind, severity, retry, err, substr(desc, 0, 240), info, business, tld);
            olog(LoggerLevel::FATAL, get_exception_string(ex));
            #dbg("tld: %N", tld);
            # set fatal error in workflow
            Qorus.control.execHash{tld.index}.setFatalError(ex);
            return;
        }
        break;
    }

    # flag business error on step
    if (business)
        tld.businessError = True;
    #printf("log_error() eeid: %y sev: %y stat: %y %s: %s (info: %y)\n", eeid, severity, status, err, desc, info);

    try {
        Qorus.events.postWorkflowDataError(severity, tld.wf.name, tld.wf.version, tld.wf.workflowid,
            tld.wfe.workflow_instanceid, tld.index, {
                "err": err,
                "desc": desc,
                "info": info,
                "business_error": business,
                "stepid": stepid,
                "ind": ind,
                "retry": retry,
                "errorid": eeid,
            });
    } catch (hash<ExceptionInfo> ex) {
        string estr = !Qorus.getDebugSystem() ? sprintf("%s: %s", ex.err, ex.desc) : get_exception_string(ex);
        olog(LoggerLevel::FATAL, "Exception thrown while trying to raise the workflow order data event: %s", estr);
    }

    return eeid;
}

#! loads the given module and returns the module name to cover the case when the argument is an absolute path
/** requires injection; cannot be in the client module
*/
string sub qorus_load_workflow_module(string mod) {
    return qorus_load_interface_module(IX_PGM_MOD_FAKE_SVC | IX_PGM_MOD_FAKE_JOB, mod, WorkflowClassList);
}
