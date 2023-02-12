# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args

# sets the call context from the current user code context in thread-local data
class CodeActionReason inherits ActionReason {
    private constructor() {
    }

    constructor(string reason) {
        self.reason = reason;
        source = getSource();

        if (tld.cx."peer-info") {
            source += " (ext source: " + tld.cx."peer-info".address_desc;
            if (tld.cx."peer-info".port)
                source += ":" + tld.cx."peer-info".port;
            source += " listener: " + tld.cx."socket-info".address_desc;
            if (tld.cx."socket-info".port)
                source += ":" + tld.cx."socket-info".port;
            source += ")";
        }

        if (tld.cx.method)
            source += sprintf(" (RPC: %s)", tld.cx.method);
        else if (tld.cx.orig_method) {
            source += sprintf(" (REST %s %s", tld.cx.hdr.method, tld.cx.url.path);
            if (tld.cx.url.path !~ /\?/)
                source += sprintf("?action=%s", tld.cx.orig_method);
            source += ")";
        }

        who = tld.cx.user ? tld.cx.user : "Qorus";
    }

    static *string getSource() {
        string source;
        if (tld.wfe) {
            source = sprintf("workflow %s v%s (%d) workflow_instanceid %d", tld.wfe.wf.name, tld.wfe.wf.version, tld.wfe.wf.workflowid, tld.wfe.workflow_instanceid);
            if (tld.stepID) {
                hash sih = tld.wfe.wf.stepinfo.(tld.stepID);
                source += sprintf(" step %s v%s (%d/%d)", sih.name, sih.version, tld.stepID, tld.ind);
            }
            if (int(tld.index))
                source += sprintf(" (execid %d)", tld.index);
        }
        else if (tld.wf) {
            source = sprintf("workflow %s v%s (%d)", tld.wf.name, tld.wf.version, tld.wf.workflowid);
            if (tld.wfe.workflow_instanceid)
                source += sprintf(" workflow_instanceid %d", tld.wfe.workflow_instanceid);
            if (tld.stepID) {
                hash sih = tld.wf.stepinfo.(tld.stepID);
                source += sprintf(" step %s v%s (%d/%d)", sih.name, sih.version, tld.stepID, tld.ind);
            }
            if (int(tld.index))
                source += sprintf(" (execid %d)", tld.index);
        }
        else if (tld.job) {
            hash jh = tld.job.getInfo();
            source = sprintf("job %s v%s (%d) job_instanceid %d", jh.name, jh.version, jh.jobid, jh.job_instanceid);
        }
        else if (tld.svc) {
            source = sprintf("service %s v%s (%d)", tld.svc.name, tld.svc.version, tld.svc.serviceid);
        }
        return source;
    }
}

