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

public namespace OMQ {
    public class Audit {
        private {
            SQLInterface sqlif;

            int a_startup;
            int a_recovery_start;

            # mask of audit flags
            int mask = 0;

            # hostname
            string host = gethostname();
        }

        constructor(SQLInterface n_sqlif, *softlist n_options) {
            sqlif = n_sqlif;
            setMask(n_options);
        }

        setMask(*softlist options) {
            if (options)
                mask = (options.size() == 1 && options[0] === "*") ? -1 : (foldl $1 | $2, (map OMQ::AuditOptionMap.$1, options));

            if (mask)
                sqlif.initAuditDatasource();
            #printf("Audit::setMask(%y) mask: 0x%x\n", options, mask);
        }

        logFatal(string msg) {
            logFatalArgs(msg, argv);
        }

        logFatalArgs(string msg, auto args) {
        }

        logInfo(string msg) {
            logInfoArgs(msg, argv);
        }

        logInfoArgs(string msg, auto args) {
        }

        int getMask() {
            return mask;
        }

        string getDescription() {
            if (!mask)
                return "[] = auditing disabled";

            if ((mask & OMQ::AuditMask) == OMQ::AuditMask)
                return "[*] = all events";

            string str = "[";
            foreach softint code in (keys OMQ::AuditCodeMap) {
                if (mask & code)
                    str += OMQ::AuditCodeMap{code} + ",";
            }
            splice str, -1, 1, "]";
            return str;
        }

        bool checkOptionString(string opt) {
            if (!exists OMQ::AuditEventCodeMap{opt})
                throw "AUDIT-EVENT-ERROR", sprintf("event %y does not exist; valid events: %y", opt, keys OMQ::AuditEventCodeMap);
            return boolean(mask & OMQ::AuditOptionMap{opt});
        }

        bool checkOption(softint opt) {
            return boolean(mask & opt);
        }

        static private *string getMsg(*string reason, *string who, *string source, *string info1, *string info2) {
            string str;
            if (exists who)
                str += sprintf(" who: %y", who);
            if (exists source)
                str += sprintf(" source: %y", source);
            if (exists reason)
                str += sprintf(" reason: %y", reason);
            if (exists info1)
                str += sprintf(" info1: %y", info1);
            if (exists info2)
                str += sprintf(" info2: %y", info2);
            return str;
        }

        private int logAuditNoCommit(*int rid, *int wfid, *int wfiid, *int stepid, *int ind, *int jid, *int jiid, *int sid, *int audit_event_code, *string user_event_code, *string reason = "internal call", *string who, *string source, *string info1, *string info2) {
            int id;
            try {
                id = sqlif.logAudit(rid, wfid, wfiid, stepid, ind, jid, jiid, sid, audit_event_code, user_event_code, reason, who, source, info1, info2);
            } catch (hash<ExceptionInfo> ex) {
                logInfo("%s: %s", ex.err, ex.desc);
                # raise a transient alert for the audit log failure as long as it's not a recursive error
                if (!get_thread_data("audit_error")) {
                    save_thread_data(("audit_error": True));
                    on_exit delete_thread_data("audit_error");
                    alert_exception("AUDIT", "AUDIT-LOG-ERROR", ex);
                }
                return -1;
            }
            return id;
        }

        private int logAuditCommit(*int rid, *int wfid, *int wfiid, *int stepid, *int ind, *int jid, *int jiid, *int sid, *int audit_event_code, *string user_event_code, *string reason = "internal call", *string who, *string source, *string info1, *string info2) {
            int id;
            try {
                id = sqlif.logAuditCommit(rid, wfid, wfiid, stepid, ind, jid, jiid, sid, audit_event_code, user_event_code, reason, who, source, info1, info2);
            } catch (hash<ExceptionInfo> ex) {
                logInfo("%s: %s", ex.err, ex.desc);
                return -1;
            }
            return id;
        }

        private int auditAnyEventIntern(bool commit, *softint rid, int code, *softint wfid, *softint wfiid, *softint stepid, *int ind, *softint jid, *softint jiid, *softint sid, *string user_event, *string reason, *string who, *string source, *string info1, *string info2) {
            int id =
                commit
                ? logAuditCommit(rid, wfid, wfiid, stepid, ind, jid, jiid, sid, code, user_event, reason, who, source, info1, info2)
                : logAuditNoCommit(rid, wfid, wfiid, stepid, ind, jid, jiid, sid, code, user_event, reason, who, source, info1, info2);

            string str = sprintf("%s: %d", AuditEventMap{code}, id);

            # if auditing failed, then mark as failed in log
            if (id == -1)
                str += " (AUDIT ENTRY FAILED DUE TO DB ERROR)";

            if (rid)
                str += sprintf(" rid: %d", rid);
            if (wfid) {
                str += sprintf(" workflowid: %d", wfid);
                if (wfiid) {
                    str += sprintf(" workflow_instanceid: %d", wfiid);
                    if (stepid)
                        str += sprintf(" stepid: %d[%d]", stepid, ind);
                }
            }
            else if (jid) {
                str += sprintf(" jobid: %d", jid);
                if (jiid)
                    str += sprintf(" job_instanceid: %d", jiid);
            }
            else if (sid)
                str += sprintf(" serviceid: %d", sid);

            str += Audit::getMsg(reason, who, source, info1, info2);
            logInfo(str);

            return id;
        }

        private int auditUserEvent(*softint rid, *softint wfid, *softint wfiid, *softint stepid, *int ind, *softint jid, *softint jiid, *softint sid, string user_event, *string reason, *string who, *string source, *string info1, *string info2) {
            return auditAnyEventIntern(True, rid, AE_USER_EVENT, wfid, wfiid, stepid, ind, jid, jiid, sid, user_event, reason, who, source, info1, info2);
        }

        private int auditService(*softint rid, int code, softint sid, *string reason, *string who, *string source, *string info1, *string info2) {
            int id = logAuditCommit(rid, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, sid, code, NOTHING, reason, who, source, info1, info2);
            string str = sprintf("%s: %d", AuditEventMap{code}, id);
            # if auditing failed, then mark as failed in log
            if (id == -1)
                str += " (AUDIT ENTRY FAILED DUE TO DB ERROR)";

            if (rid)
                str += sprintf(" rid: %d", rid);
            str += sprintf(" serviceid: %d", sid);
            str += Audit::getMsg(reason, who, source, info1, info2);
            logInfo(str);

            return id;
        }

        private auditApiCall(string api, string args, *string who, *string source, *string info) {
            int id = logAuditCommit(a_startup, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, AE_API_CALL, NOTHING, api, who, source, args, info);
            string str = sprintf("AE_API_CALL: %d API %s args %y", id, api, args);
            # if auditing failed, then mark as failed in log
            if (id == -1)
                str += " (AUDIT ENTRY FAILED DUE TO DB ERROR)";

            str += Audit::getMsg(NOTHING, who, source, info);
            logInfo(str);
        }

        private int auditJob(bool commit, *softint rid, int code, softint jid, *softint jiid, *string reason, *string who, *string source, *string info1, *string info2) {
            int id = commit
                ? logAuditCommit(rid, NOTHING, NOTHING, NOTHING, NOTHING, jid, jiid, NOTHING, code, NOTHING, reason, who, source, info1, info2)
                : logAuditNoCommit(rid, NOTHING, NOTHING, NOTHING, NOTHING, jid, jiid, NOTHING, code, NOTHING, reason, who, source, info1, info2);
            string str = sprintf("%s: %d", AuditEventMap{code}, id);
            # if auditing failed, then mark as failed in log
            if (id == -1)
                str += " (AUDIT ENTRY FAILED DUE TO DB ERROR)";
            if (exists rid)
                str += sprintf(" rid: %d", rid);
            str += sprintf(" jobid: %d", jid);
            if (exists jiid)
                str += sprintf(" job_instanceid: %d", jiid);
            str += Audit::getMsg(reason, who, source, info1, info2);
            logInfo(str);
            return id;
        }

        private int auditJob(*softint rid, int code, softint jid, *softint jiid, *string reason, *string who, *string source, *string info1, *string info2) {
            int id = -1;
            try {
                id = auditJob(True, rid, code, jid, jiid, reason, who, source, info1, info2);
            } catch (hash<ExceptionInfo> ex) {
                logInfo("%s: %s", ex.err, ex.desc);
            }
            return id;
        }

        private int auditWorkflowData(bool commit, *softint rid, int code, softint wfid, softint wfiid, *string reason, *string who, *string source, *string info1, *string info2) {
            int id = commit
                ? logAuditCommit(rid, wfid, wfiid, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, code, NOTHING, reason, who, source, info1, info2)
                : logAuditNoCommit(rid, wfid, wfiid, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, code, NOTHING, reason, who, source, info1, info2);
            string str = sprintf("%s: %d", AuditEventMap{code}, id);
            # if auditing failed, then mark as failed in log
            if (id == -1)
                str += " (AUDIT ENTRY FAILED DUE TO DB ERROR)";
            if (exists rid)
                str += sprintf(" rid: %d", rid);
            str += sprintf(" workflowid: %d", wfid);
            if (wfiid)
                str += sprintf(" workflow_instanceid: %d", wfiid);
            str += Audit::getMsg(reason, who, source, info1, info2);
            logInfo(str);
            return id;
        }

        private int auditWorkflowData(*softint rid, int code, softint wfid, softint wfiid, *string reason, *string who, *string source, *string info1, *string info2) {
            int id = -1;
            try {
                id = auditWorkflowData(True, rid, code, wfid, wfiid, reason, who, source, info1, info2);
            } catch (hash<ExceptionInfo> ex) {
                logInfo("%s: %s", ex.err, ex.desc);
            }
            return id;
        }

        private int auditWorkflow(*softint rid, int code, softint wfid, *string reason, *string who, *string source, *string info1, *string info2) {
            int id = logAuditCommit(rid, wfid, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, code, NOTHING, reason, who, source, info1, info2);
            string str = sprintf("%s: %d", AuditEventMap{code}, id);
            # if auditing failed, then mark as failed in log
            if (id == -1)
                str += " (AUDIT ENTRY FAILED DUE TO DB ERROR)";
            if (exists rid)
                str += sprintf(" rid: %d", rid);
            str += sprintf(" workflowid: %d", wfid);
            str += Audit::getMsg(reason, who, source, info1, info2);
            logInfo(str);
            return id;
        }

        private int audit(bool commit, *softint rid, int code, *string reason, *string who, *string source, *string info1, *string info2) {
            int id = commit
                ? logAuditCommit(rid, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, code, NOTHING, reason, who, source, info1, info2)
                : logAuditNoCommit(rid, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, code, NOTHING, reason, who, source, info1, info2);
            string str = sprintf("%s: %d", AuditEventMap{code}, id);
            # if auditing failed, then mark as failed in log
            if (id == -1)
                str += " (AUDIT ENTRY FAILED DUE TO DB ERROR)";
            if (exists rid)
                str += sprintf(" rid: %d", rid);
            str += Audit::getMsg(reason, who, source, info1, info2);
            logInfo(str);
            return id;
        }

        private int audit(*softint rid, int code, *string reason, *string who, *string source, *string info1, *string info2) {
            int id = -1;
            try {
                id = audit(True, rid, code, reason, who, source, info1, info2);
            } catch (hash<ExceptionInfo> ex) {
                logInfo("%s: %s", ex.err, ex.desc);
            }
            return id;
        }

        systemStartup() {
            if (!(mask & OMQ::AOC_SYSTEM))
                return;

            a_startup = audit(NOTHING, AE_SYSTEM_STARTUP, NOTHING, Audit::getUNIXUser(), host);
        }

        systemShutdown(*hash cx) {
            if (!(mask & OMQ::AOC_SYSTEM))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            audit(a_startup, AE_SYSTEM_SHUTDOWN, h.reason, h.who, h.source);
        }

        systemRecoveryStart(string trigger, string info) {
            if (!(mask & OMQ::AOC_SYSTEM))
                return;

            a_recovery_start = audit(NOTHING, AE_SYSTEM_RECOVERY_START, NOTHING, Audit::getUNIXUser(), trigger + " on " + host, info);
        }

        systemRecoveryComplete(string trigger, string info) {
            if (!(mask & OMQ::AOC_SYSTEM))
                return;

            audit(a_recovery_start, AE_SYSTEM_RECOVERY_COMPLETE, NOTHING, Audit::getUNIXUser(), trigger + " on " + host, info);
        }

        workflowRecoveryNoCommit(softint wfid, softint wfiid, string old_status, string trigger) {
%ifdef QorusDebugInternals
            QDBG_ASSERT(mask & OMQ::AOC_WORKFLOW_DATA);
%endif
            auditWorkflowData(False, a_recovery_start, AE_WORKFLOW_STATUS_CHANGE, wfid, wfiid, "schema recovery", Audit::getUNIXUser(), trigger + " on " + host, old_status, "R");
        }

        *int startWorkflow(*hash cx, softint wfid, string mode, string execid, *hash opts) {
            if (!(mask & OMQ::AOC_WORKFLOWS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            return auditWorkflow(a_startup, AE_WORKFLOW_START, wfid, h.reason, h.who, h.source, execid, exists opts ? sprintf("%y", opts) : NOTHING);
        }

        stopWorkflow(*int rid, softint wfid, string execid, string reason, string who, string source) {
            if (!(mask & OMQ::AOC_WORKFLOWS))
                return;

            auditWorkflow(rid, AE_WORKFLOW_STOP, wfid, reason, who, source, execid);
        }

        jobRecoveryNoCommit(softint jid, *softint jiid, string trigger) {
%ifdef QorusDebugInternals
            QDBG_ASSERT(mask & OMQ::AOC_WORKFLOW_DATA);
%endif
            auditJob(False, a_recovery_start, AE_JOB_RECOVERY, jid, jiid, "schema recovery", Audit::getUNIXUser(), trigger + " on " + host, "I", "Z");
        }

        workflowOrderCreatedNoCommit(*hash cx, softint wfid, softint wfiid, softint priority, string status, *string eoiid, *date scheduled, *softint pwfiid, bool subworkflow = False, bool sync = False) {
            if (!(mask & OMQ::AOC_WORKFLOW_DATA))
                return;

            string info = sprintf("status: %y parent: %y, subworkflow: %y, prio: %y, sync: %y, externalid: %y, scheduled: %y", status, pwfiid, subworkflow, priority, sync, eoiid, scheduled);

            hash<auto> h = Audit::getContextInfo(cx);
            auditWorkflowData(False, NOTHING, AE_WORKFLOW_DATA_CREATED, wfid, wfiid, h.reason, h.who, h.source, info);
        }

        workflowStatusChange(*hash cx, softint wfid, softint wfiid, *string old_status, string new_status, *string reason) {
%ifdef QorusDebugInternals
            if (new_status == old_status) {
                logFatal("workflowStatusChange() wfiid=%d %s -> %s", wfiid, old_status, new_status);
                logFatal("DEBUG: %N", get_stack());
            }
%endif
            if (!(mask & OMQ::AOC_WORKFLOW_DATA))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditWorkflowData(NOTHING, AE_WORKFLOW_STATUS_CHANGE, wfid, wfiid, exists reason ? reason : h.reason, h.who, h.source, old_status, new_status);
        }

        workflowStatusChangeNoCommit(*hash cx, softint wfid, softint wfiid, *string old_status, string new_status, *string reason) {
%ifdef QorusDebugInternals
            if (new_status == old_status) {
                logFatal("workflowStatusChange() wfiid=%d %s -> %s", wfiid, old_status, new_status);
                logFatal("DEBUG: %N", get_stack());
            }
%endif
            if (!(mask & OMQ::AOC_WORKFLOW_DATA))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditWorkflowData(False, NOTHING, AE_WORKFLOW_STATUS_CHANGE, wfid, wfiid, exists reason ? reason : h.reason, h.who, h.source, old_status, new_status);
        }

        *int startJobNoCommit(softint jid, string info, string reason, string who, string source) {
            if (!(mask & OMQ::AOC_JOBS))
                return;

            return auditJob(False, a_startup, AE_JOB_START, jid, NOTHING, reason, who, source, info);
        }

        stopJob(*int eid, softint jid, *string info, string reason, string who, string source) {
            if (!(mask & OMQ::AOC_JOBS))
                return;

            auditJob(eid, AE_JOB_STOP, jid, NOTHING, reason, who, source, info);
        }

        *int startJobInstance(*hash cx, softint jid, softint jiid, *string info) {
            if (!(mask & OMQ::AOC_JOB_DATA))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            return auditJob(a_startup, AE_JOB_INSTANCE_START, jid, jiid, h.reason, h.who, h.source, info);
        }

        # the job_instanceid (jiid) may be NOTHING in the rare case that the job was deleted while an instance was in progress
        stopJobInstance(*hash cx, *int eid, softint jid, *softint jiid, string status, *string info) {
            if (!(mask & OMQ::AOC_JOB_DATA))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(eid, AE_JOB_INSTANCE_STOP, jid, jiid, h.reason, h.who, h.source, status, info);
        }

        jobCreated(*hash<auto> cx, softint jid, *string info) {
            if (!(mask & OMQ::AOC_JOBS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(a_startup, AE_JOB_CREATED, jid, NOTHING, h.reason, h.who, h.source, info);
        }

        jobDeleted(*hash<auto> cx, softint jid, *string info) {
            if (!(mask & OMQ::AOC_JOBS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(a_startup, AE_JOB_DELETED, jid, NOTHING, h.reason, h.who, h.source, info);
        }

        jobUpdated(*hash<auto> cx, softint jid, *string info) {
            if (!(mask & OMQ::AOC_JOBS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(a_startup, AE_JOB_UPDATED, jid, NOTHING, h.reason, h.who, h.source, info);
        }

        classCreated(*hash<auto> cx, softint classid, *string info) {
            if (!(mask & OMQ::AOC_CODE_EVENTS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(a_startup, AE_CLASS_CREATED, classid, NOTHING, h.reason, h.who, h.source, info);
        }

        classDeleted(*hash<auto> cx, softint classid, *string info) {
            if (!(mask & OMQ::AOC_CODE_EVENTS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(a_startup, AE_CLASS_DELETED, classid, NOTHING, h.reason, h.who, h.source, info);
        }

        classUpdated(*hash<auto> cx, softint classid, *string info) {
            if (!(mask & OMQ::AOC_CODE_EVENTS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(a_startup, AE_CLASS_UPDATED, classid, NOTHING, h.reason, h.who, h.source, info);
        }

        connectionCreated(*hash<auto> cx, softint connectionid, *string info) {
            if (!(mask & OMQ::AOC_CODE_EVENTS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(a_startup, AE_CONNECTION_CREATED, connectionid, NOTHING, h.reason, h.who, h.source, info);
        }

        connectionDeleted(*hash<auto> cx, softint connectionid, *string info) {
            if (!(mask & OMQ::AOC_CODE_EVENTS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(a_startup, AE_CONNECTION_DELETED, connectionid, NOTHING, h.reason, h.who, h.source, info);
        }

        connectionUpdated(*hash<auto> cx, softint connectionid, *string info) {
            if (!(mask & OMQ::AOC_CODE_EVENTS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditJob(a_startup, AE_CONNECTION_UPDATED, connectionid, NOTHING, h.reason, h.who, h.source, info);
        }

        apiCall(*hash<auto> cx, string args, *string info) {
            if (!(mask & OMQ::AOC_API))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditApiCall(h.reason, args, h.who, h.source, info);
        }

        *int serviceStart(softint sid, *string info1, *string info2, string reason, string who, string source) {
            if (!(mask & OMQ::AOC_SERVICES))
                return;

            return auditService(a_startup, AE_SERVICE_START, sid, reason, who, source, info1, info2);
        }

        serviceStop(*int rid, softint sid, *string info1, *string info2, string reason, string who, string source) {
            if (!(mask & OMQ::AOC_SERVICES))
                return;

            auditService(rid, AE_SERVICE_STOP, sid, reason, who, source, info1, info2);
        }

        *int userWorkflowEvent(*hash cx, *softint rid, softint wfid, softint wfiid, *softint stepid, *int ind, string user_event, *string info1, *string info2) {
            if (!(mask & OMQ::AOC_USER_EVENTS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditUserEvent(rid, wfid, wfiid, stepid, ind, NOTHING, NOTHING, NOTHING, user_event, h.reason, h.who, h.source, info1, info2);
        }

        *int userServiceEvent(*hash cx, *softint rid, softint sid, string user_event, *string info1, *string info2) {
            if (!(mask & OMQ::AOC_USER_EVENTS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditUserEvent(rid, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, NOTHING, sid, user_event, h.reason, h.who, h.source, info1, info2);
        }

        *int userJobEvent(*hash cx, *softint rid, softint jid, softint jiid, string user_event, *string info1, *string info2) {
            if (!(mask & OMQ::AOC_USER_EVENTS))
                return;

            hash<auto> h = Audit::getContextInfo(cx);
            auditUserEvent(rid, NOTHING, NOTHING, NOTHING, NOTHING, jid, jiid, NOTHING, user_event, h.reason, h.who, h.source, info1, info2);
        }

        *int alertEvent(*softint rid, int code, *softint wfid, *softint wfiid, *softint stepid, *softint ind, *softint jid, *softint jiid, *softint sid, *string user_event, string reason, string who, string source, string alert, *hash ih) {
            if (!(mask & OMQ::AOC_ALERT_EVENTS))
                return;

            string info;
            if (ih)
                info = sprintf("%y", ih);

            return auditAnyEventIntern(True, rid, code, wfid, wfiid, stepid, ind, jid, jiid, sid, user_event, reason, who, source, alert, info);
        }

        *int sourceLoadedEvent(*softint rid, *softint wfid, *softint jid, *softint sid, string file, string type, string name, *string version, softint id, *string info) {
            if (!(mask & OMQ::AOC_OLOAD_EVENTS))
                return;

            file = gethostname() + ":" + file;
            string object = sprintf("%s %s(%d)", name, exists version ? sprintf("v%s ", version) : "", id);
            if (info)
                object += " " + info;
            return auditAnyEventIntern(False, rid, AE_SOURCE_FILE_LOADED, wfid, NOTHING, NOTHING, NOTHING, jid, NOTHING, sid, NOTHING, sprintf("oload pid %d", getpid()), getusername(), file, type, object);
        }

        static hash<auto> getContextInfo(*hash cx) {
            if (!exists cx || cx.user == "%SYS%") {
                return {
                    "who": "Qorus",
                    "source": qorus_get_source(),
                };
            }

            string source = "source: " + cx."peer-info".address_desc;
            if (cx."peer-info".port)
                source += ":" + cx."peer-info".port;
            source += " listener: " + cx."socket-info".address_desc;
            if (cx."socket-info".port)
                source += ":" + cx."socket-info".port;

            string reason;
            if (cx.method)
                reason = cx.method;
            else if (cx.orig_method) {
                reason = sprintf("REST %s %s", cx.hdr.method, cx.url.path);
                if (reason !~ /\?/)
                    reason += sprintf("?action=%s", cx.orig_method);
            } else
                reason = "external API call";

            return {
                "reason": reason,
                "who": cx.user,
                "source": source,
            };
        }

        static string getUNIXUser() {
%ifdef HAVE_UNIX_USERMGT
            int uid = getuid();
            int gid = getgid();
            return sprintf("UNIX: user %s:%s (%d:%d)", getpwuid(uid).pw_name, getgrgid(gid).gr_name, uid, gid);
%else
            return getusername();
%endif
        }
    }
}
