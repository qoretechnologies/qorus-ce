# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

public namespace OMQ {
    const QEM_DEFAULT_MAX = 100000;

    const QEI_STARTUP_INFO = {
        "name"    : OMQ::ProductName,
        "version" : OMQ::version,
        "build"   : QorusRevision,
    };
}

class OMQ::QorusEventManager inherits RWLock {
    public {
    }

    private {
        # event list
        list<auto> el = ();

        # maximum size of event list
        int max;

        # event sequence number generator; first event ID starts with 1
        int seq = 1;

        # starting event ID in list; event cache starts with event ID 1
        int start = 1;

        int end;       # ending event ID in list
        int waiting;   # number of threads waiting on events

        # condition variable for waiting threads
        Condition cond();

        # shutdown flag
        bool shutdown = False;
    }

    constructor(softint n_max = QEM_DEFAULT_MAX) {
        if (n_max <= 0)
            throw "EVENTMANAGER-ERROR", sprintf("invalid value passed for to QorusEventManager::constructor(): %d", n_max);
        max = n_max;
    }

    int getCurrentEventID() {
        return seq;
    }

    *hash<auto> getRange() {
        AutoReadLock al(self);
        if (!el)
            return;

        return (
            "start": start,
            "end": end
        );
    }

    private int postEvent(int classv, int event, string sys_severity, auto info, *hash<auto> caller, *string user_severity) {
        string api;
        if (caller.method)
            api = "RPC: " + caller.method;
        else if (caller.orig_method) {
            api = sprintf("REST %s %s", caller.hdr.method, caller.url.path);
            if (api !~ /\?/)
                api += sprintf("?action=%s", caller.orig_method);
        }
        else
            api = "external API call";

        # if a connection ID exists, then it's an external call
        if (caller.id) {
            caller = {
                "user"          : caller.user,
                "api"           : api,
                "source"        : caller."peer-info".address,
                "source-host"   : caller."peer-info".hostname,
                "source-family" : caller."peer-info".familystr,
                "socket"        : caller.socket,
                "connection-id" : caller.id,
                "url"           : caller.url,
            };
        }
        else {
            caller = {
                "user": "<internal>",
                "api": api,
            };
        }

        date ts = now_us();
        hash<auto> ei = {
            "id"           : 0, # placeholder - the ID is assigned in the lock below to ensure that events are queued in sequence
            "time"         : ts,
            # send microseconds separately because they cannot be serialized
            # by an XML-RPC date/time type
            "timeus"       : get_microseconds(ts),
            #"timestr"      : format_date("YYYY-MM-DD HH:mm:SS.uu", ts),
            "class"        : classv,
            "classstr"     : OMQ::QE_MAP_CLASS{classv},
            "event"        : event,
            "eventstr"     : OMQ::QE_MAP_EVENT{event},
            "severity"     : OMQ::ErrorSeverityOrder{sys_severity},
            "severitystr"  : sys_severity,
            "caller"       : caller,
            "info"         : info,
        };

        if (user_severity) {
            ei += {
                "userseverity"    : OMQ::ErrorSeverityOrder{user_severity},
                "userseveritystr" : user_severity,
            };

            int ms = (ei.severity > ei.userseverity) ? ei.severity : ei.userseverity;
            ei += {
                "compositeseverity"    : ms,
                "compositeseveritystr" : OMQ::ErrorSeverityMap{ms},
            };
        }
        else {
            ei += {
                "compositeseverity"    : ei.severity,
                "compositeseveritystr" : ei.severitystr,
            };
        }

        AutoWriteLock al(self);

        ei.id = seq++;

        if (el.size() == (max -1)) {
            shift el;
            ++start;
        }

        el += ei;

        end = ei.id;

        if (waiting)
            cond.broadcast();

        return ei.id;
    }

    postSystemStartup() {
        postEvent(QE_CLASS_SYSTEM, QEC_SYSTEM_STARTUP, ES_Info, QEI_STARTUP_INFO);
    }

    postSystemShutdown(*hash<auto> caller) {
        shutdown = True;

        postEvent(QE_CLASS_SYSTEM, QEC_SYSTEM_SHUTDOWN, ES_Info, NOTHING, caller);
    }

    postSystemError(string severity, string err, auto desc, *hash<auto> info) {
        hash<auto> ei = {"err": err, "desc": desc, "info": info};
        postEvent(QE_CLASS_SYSTEM, QEC_SYSTEM_ERROR, ES_Info, ei);
    }

    int postUserEvent(string user_severity, auto info) {
        if (!ErrorSeverityOrder{user_severity})
            throw "POST-USER-EVENT-ERROR", sprintf("invalid value passed as first argument to postUserEvent(); got: %n, expecting one of: %n", user_severity, keys ErrorSeverityOrder);

        return postEvent(QE_CLASS_USER, QEC_USER_EVENT, ES_Info, info, NOTHING, user_severity);
    }

    postWorkflowRecovered(*hash<auto> caller, string name, string version, int wfid) {
        hash<auto> info = {
            "name"        : name,
            "version"     : version,
            "workflowid"  : wfid,
            "old_statuses": (OMQ::StatInProgress,),
            "new_status"  : OMQ::StatRetry,
        };

        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_RECOVERED, ES_Info, info, caller);
    }

    postOrderStats(string tag, list<hash<OrderSummaryOutputInfo>> l) {
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_STATS_UPDATED, ES_Info, {"tag": tag, "bands": l});
    }

    postWorkflowStart(*hash<auto> caller, string name, string version, softint wfid, auto execid, string mode, bool sync, *hash<auto> options, int autostart) {
        hash<auto> info = {
            "name"        : name,
            "version"     : version,
            "workflowid"  : wfid,
            "execid"      : execid,
            "mode"        : mode,
            "synchronous" : sync,
            "options"     : options,
            "autostart"   : autostart,
        };

        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_START, ES_Info, info, caller);
    }

    postWorkflowStop(*hash<auto> caller, string name, string version, softint wfid, auto execid, string mode, bool sync, int autostart) {
        hash<auto> info = {
            "name"        : name,
            "version"     : version,
            "workflowid"  : wfid,
            "execid"      : execid,
            "mode"        : mode,
            "synchronous" : sync,
            "autostart"   : autostart,
        };

        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_STOP, ES_Info, info, caller);
    }

    postWorkflowCacheReset(*hash<auto> caller, string name, string version, softint wfid) {
        hash<auto> info = {
            "name"        : name,
            "version"     : version,
            "workflowid"  : wfid,
        };

        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_CACHE_RESET, ES_Info, info, caller);
    }

    postWorkflowDataSubmitted(*hash<auto> caller, string name, string version, softint wfid, softint wfiid, string status, *softint pwfiid, bool swf = False, bool sync = False) {
        Qorus.orderStats.postCreated(wfid, wfiid);

        hash<auto> info = {
            "name": name,
            "version": version,
            "workflowid": wfid,
            "workflow_instanceid": wfiid,
            "status": status,
            "parent_workflow_instanceid": pwfiid,
            "subworkflow": swf,
            "synchronous": sync,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_DATA_SUBMITTED, ES_Info, info, caller);
    }

    postWorkflowDataError(string user_severity, string name, string version, softint wfid, *softint wfiid, softstring execid, hash<auto> err) {
        hash<auto> info = {
            "name"                : name,
            "version"             : version,
            "workflowid"          : wfid,
            "workflow_instanceid" : wfiid,
            "execid"              : execid,
            "error"               : err,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_DATA_ERROR, ES_Info, info, NOTHING, user_severity);
    }

    postWorkflowDataReleased(string wfname, string wfversion, softint wfid, softint wfiid, string status, softbool business_error = False) {
        hash<auto> info = {
            "name"                : wfname,
            "version"             : wfversion,
            "workflowid"          : wfid,
            "workflow_instanceid" : wfiid,
            "status"              : status,
            "business_error"      : business_error,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_DATA_RELEASED, ES_Info, info);
    }

    postWorkflowDataCached(string wfname, string wfversion, softint wfid, softint wfiid, string status, softbool business_error = False, auto external_order_instanceid, auto keysv) {
        hash<auto> info = {
            "name"                      : wfname,
            "version"                   : wfversion,
            "workflowid"                : wfid,
            "workflow_instanceid"       : wfiid,
            "status"                    : status,
            "business_error"            : business_error,
            "external_order_instanceid" : external_order_instanceid,
            "keys"                      : keysv,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_DATA_CACHED, ES_Info, info);
    }

    postWorkflowDataUpdated(softint wfid, softint wfiid, string datatype) {
        # do not call the locking version of the lookup here, as it can lead to a deadlock when called from an
        # external process
        *hash<auto> wf = Qorus.qmm.lookupWorkflowUnlocked(wfid);
        if (!wf) {
            QDBG_LOG("cannot post %y event got unknown workflow %y (wfiid %y)", QEC_WORKFLOW_DATA_UPDATED, wfid, wfiid);
            return;
        }
        hash<auto> info = {
            "name"                      : wf.name,
            "version"                   : wf.version,
            "workflowid"                : wfid,
            "workflow_instanceid"       : wfiid,
            "datatype"                  : datatype,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_DATA_UPDATED, ES_Info, info);
    }

    postWorkflowStepDataUpdated(softint wfid, softint wfiid, softint stepid, int ind) {
        # do not call the locking version of the lookup here, as it can lead to a deadlock when called from an
        # external process
        *hash<auto> wf = Qorus.qmm.lookupWorkflowUnlocked(wfid);
        if (!wf) {
            QDBG_LOG("cannot post %y event got unknown workflow %y (wfiid %y)", QEC_WORKFLOW_STEP_DATA_UPDATED, wfid, wfiid);
            return;
        }
        hash<auto> info = {
            "name"                      : wf.name,
            "version"                   : wf.version,
            "workflowid"                : wfid,
            "workflow_instanceid"       : wfiid,
            "stepid"                    : stepid,
            "ind"                       : ind,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_STEP_DATA_UPDATED, ES_Info, info);
    }

    postWorkflowInfoChanged(*hash<auto> caller, string name, string version, softint wfid, softint wfiid, hash<auto> winfo) {
        hash<auto> info = {
            "name"               : name,
            "version"            : version,
            "workflowid"         : wfid,
            "workflow_instanceid": wfiid,
            "info"               : winfo,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_INFO_CHANGED, ES_Info, info, caller);
    }

    postWorkflowStatusChanged(*hash<auto> caller, string name, string version, softint wfid, softint wfiid, hash<auto> winfo) {
        #QDBG_LOG("postWorkflowStatusChanged() wfiid: %y info: %y stack: %N", wfiid, winfo, get_stack());
        hash<auto> info = {
            "name"               : name,
            "version"            : version,
            "workflowid"         : wfid,
            "workflow_instanceid": wfiid,
            "info"               : winfo,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_STATUS_CHANGED, ES_Info, info, caller);
    }

    postWorkflowPerformance(*hash<auto> caller, string name, string version, softint wfid, softint wfiid, string status, string disposition, date n_start, date n_end) {
        if (!Qorus.options.get("workflow-perf-events")) {
            return;
        }

        hash<auto> info = {
            "name": name,
            "version": version,
            "workflowid": wfid,
            "workflow_instanceid": wfiid,
            "status": status,
            "disposition": disposition,
            "start": n_start,
            "end": n_end,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_PERFORMANCE, ES_Info, info, caller);
    }

    postWorkflowStepPerformance(*hash<auto> caller, string name, string version, softint wfid, softint wfiid, string stepname, softint stepid, softint ind, date n_start, date n_end) {
        # feature 844: service, and workflow step performance events should only be emitted if specifically enabled with system options since they can cause performance degradation
        if (!Qorus.options.get("workflow-step-perf-events"))
            return;
        hash<auto> info = {
            "name": name,
            "version": version,
            "workflowid": wfid,
            "workflow_instanceid": wfiid,
            "stepname": stepname,
            "stepid": stepid,
            "ind": ind,
            "start": n_start,
            "end": n_end,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_STEP_PERFORMANCE, ES_Info, info, caller);
    }

    postWorkflowDataLocked(*hash<auto> caller, string name, string version, softint wfid, softint wfiid, string note) {
        hash<auto> info = {
            "name"                : name,
            "version"             : version,
            "workflowid"          : wfid,
            "workflow_instanceid" : wfiid,
            "note"                : note,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_DATA_LOCKED, ES_Info, info, caller);
    }

    postWorkflowDataUnlocked(*hash<auto> caller, string name, string version, softint wfid, softint wfiid, string note) {
        hash<auto> info = {
            "name"                : name,
            "version"             : version,
            "workflowid"          : wfid,
            "workflow_instanceid" : wfiid,
            "note"                : note,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_DATA_UNLOCKED, ES_Info, info, caller);
    }

    postWorkflowUpdated(*hash<auto> caller, string name, string version, softint wfid, hash<auto> winfo) {
        hash<auto> info = {
            "name"               : name,
            "version"            : version,
            "workflowid"         : wfid,
            "info"               : winfo,
        };
        postEvent(QE_CLASS_WORKFLOW, QEC_WORKFLOW_UPDATED, ES_Info, info, caller);
    }

    postServiceStart(*hash<auto> caller, string type, string name, string version, softint svcid) {
        hash<auto> info = {
            "type"                      : type,
            "name"                      : name,
            "version"                   : version,
            "serviceid"                 : svcid
        };
        postEvent(QE_CLASS_SERVICE, QEC_SERVICE_START, ES_Info, info, caller);
    }

    postServiceStop(*hash<auto> caller, string type, string name, string version, softint svcid) {
        hash<auto> info = {
            "type"                      : type,
            "name"                      : name,
            "version"                   : version,
            "serviceid"                 : svcid
        };
        postEvent(QE_CLASS_SERVICE, QEC_SERVICE_STOP, ES_Info, info, caller);
    }

    postServiceError(*hash<auto> caller, string severity, string type, string name, string version, softint svcid, string err, auto desc, auto info) {
        hash<auto> ei = {
            "type"                      : type,
            "name"                      : name,
            "version"                   : version,
            "serviceid"                 : svcid,
            "err"                       : err,
            "desc"                      : desc,
            "info"                      : info,
        };
        postEvent(QE_CLASS_SERVICE, QEC_SERVICE_ERROR, severity, ei, caller);
    }

    postServiceMethodPerformance(*hash<auto> caller, string type, string name, string version, softint svcid, string method, date n_start, date n_end, bool err) {
        # feature 844: service, and workflow step performance events should only be emitted if specifically enabled with system options since they can cause performance degradation
        if (!Qorus.options.get("service-perf-events"))
            return;
        hash<auto> ei = {
            "type": type,
            "name": name,
            "version": version,
            "serviceid": svcid,
            "method": method,
            "start": n_start,
            "end": n_end,
            "error": err,
        };
        postEvent(QE_CLASS_SERVICE, QEC_SERVICE_METHOD_PERFORMANCE, ES_Info, ei, caller);
    }

    postServiceUpdated(*hash<auto> caller, string type, string name, string version, softint svcid,
        hash<auto> winfo) {
        hash<auto> info = {
            "type": type,
            "name": name,
            "version": version,
            "serviceid": svcid,
            "info": winfo,
        };
        postEvent(QE_CLASS_SERVICE, QEC_SERVICE_UPDATED, ES_Info, info, caller);
    }

    postJobStart(string name, string version, softint jid, hash<auto> ji) {
        hash<auto> info = {
            "name"        : name,
            "version"     : version,
            "jobid"       : jid,
            "info"        : ji,
        };

        postEvent(QE_CLASS_JOB, QEC_JOB_START, ES_Info, info, tld.cx);
    }

    postJobStop(string name, string version, softint jid) {
        hash<auto> info = {
            "name"        : name,
            "version"     : version,
            "jobid"       : jid,
        };

        postEvent(QE_CLASS_JOB, QEC_JOB_STOP, ES_Info, info, tld.cx);
    }

    postJobInstanceStart(string name, string version, softint jid, softint jiid) {
        hash<auto> info = {
            "name"          : name,
            "version"       : version,
            "jobid"         : jid,
            "job_instanceid": jiid,
        };

        postEvent(QE_CLASS_JOB, QEC_JOB_INSTANCE_START, ES_Info, info, tld.cx);
    }

    postJobInstanceStop(string name, string version, softint jid, softint jiid, string status, date n_start, date n_end,
                        date n_next) {
        hash<auto> info = {
            "name"          : name,
            "version"       : version,
            "jobid"         : jid,
            "job_instanceid": jiid,
            "status"        : status,
            "start"         : n_start,
            "end"           : n_end,
            "next"          : n_next,
        };

        postEvent(QE_CLASS_JOB, QEC_JOB_INSTANCE_STOP, ES_Info, info, tld.cx);
    }

    postJobError(string user_severity, string name, string version, softint jobid, *softint jiid, hash<auto> err) {
        hash<auto> info = {
            "name"           : name,
            "version"        : version,
            "jobid"          : jobid,
            "job_instanceid" : jiid,
            "error"          : err,
        };

        postEvent(QE_CLASS_JOB, QEC_JOB_ERROR, ES_Info, info, tld.cx, user_severity);
    }

    postJobRecovered(*hash<auto> caller, string name, string version, int jobid) {
        hash<auto> info = {
            "name"        : name,
            "version"     : version,
            "jobid"       : jobid,
            "old_statuses": (OMQ::JS_InProgress,),
            "new_status"  : OMQ::JS_Crash,
        };

        postEvent(QE_CLASS_JOB, QEC_JOB_RECOVERED, ES_Info, info, caller);
    }

    postJobUpdated(*hash<auto> caller, string name, string version, softint jobid, hash<auto> jinfo) {
        hash<auto> info = {
            "name": name,
            "version": version,
            "jobid": jobid,
            "info": jinfo,
        };
        postEvent(QE_CLASS_JOB, QEC_JOB_UPDATED, ES_Info, info, caller);
    }

    postJobCreated(*hash<auto> caller, string name, string version, softint jobid, hash<auto> jinfo) {
        hash<auto> info = {
            "name": name,
            "version": version,
            "jobid": jobid,
            "info": jinfo,
        };
        postEvent(QE_CLASS_JOB, QEC_JOB_CREATED, ES_Info, info, caller);
    }

    postJobDeleted(*hash<auto> caller, string name, string version, softint jobid) {
        hash<auto> info = {
            "name": name,
            "version": version,
            "jobid": jobid,
        };
        postEvent(QE_CLASS_JOB, QEC_JOB_DELETED, ES_Info, info, caller);
    }

    postClassUpdated(*hash<auto> caller, string name, string version, softint classid, hash<auto> clsinfo) {
        hash<auto> info = {
            "name": name,
            "version": version,
            "classid": classid,
            "info": clsinfo,
        };
        postEvent(QE_CLASS_CLASS, QEC_CLASS_UPDATED, ES_Info, info, caller);
    }

    postClassCreated(*hash<auto> caller, string name, string version, softint classid, hash<auto> clsinfo) {
        hash<auto> info = {
            "name": name,
            "version": version,
            "classid": classid,
            "info": clsinfo,
        };
        postEvent(QE_CLASS_CLASS, QEC_CLASS_CREATED, ES_Info, info, caller);
    }

    postClassDeleted(*hash<auto> caller, string name, string version, softint classid) {
        hash<auto> info = {
            "name": name,
            "version": version,
            "classid": classid,
        };
        postEvent(QE_CLASS_CLASS, QEC_CLASS_DELETED, ES_Info, info, caller);
    }

    postConfigItemChanged(*hash<auto> caller, hash<auto> event_info, string item_name, auto value) {
        hash<auto> info = {
            "name": item_name,
            "value": value,
        } + event_info;
        postEvent(QE_CLASS_CONFIG_ITEM, QEC_CONFIG_ITEM_CHANGED, ES_Info, info, caller);
    }

    postAlertOngoingRaised(hash<auto> info) {
        postEvent(QE_CLASS_ALERT, QEC_ALERT_ONGOING_RAISED, ES_Major, info, tld.cx);
    }

    postAlertOngoingCleared(hash<auto> info) {
        postEvent(QE_CLASS_ALERT, QEC_ALERT_ONGOING_CLEARED, ES_Major, info, tld.cx);
    }

    postAlertTransientRaised(hash<auto> info) {
        postEvent(QE_CLASS_ALERT, QEC_ALERT_TRANSIENT_RAISED, ES_Major, info, tld.cx);
    }

    postConnectionUpEvent(string type, string name, hash<auto> attributes) {
        hash<auto> info = {
            "type": type,
            "name": name,
        } + attributes;
        postEvent(QE_CLASS_CONNECTION, QEC_CONNECTION_UP, ES_Major, info, tld.cx);
    }

    postConnectionDownEvent(string type, string name, string err, hash<auto> attributes) {
        hash<auto> info = {
            "type": type,
            "name": name,
            "err": err,
        } + attributes;
        postEvent(QE_CLASS_CONNECTION, QEC_CONNECTION_DOWN, ES_Major, info, tld.cx);
    }

    postConnectionEnabledChange(string type, string name, bool enabled) {
        hash<auto> info = {
            "type": type,
            "name": name,
            "enabled": enabled,
        };
        postEvent(QE_CLASS_CONNECTION, QEC_CONNECTION_ENABLED_CHANGE, ES_Major, info, tld.cx);
    }

    postConnectionDebugDataChange(string type, string name, bool debug_data) {
        hash<auto> info = {
            "type": type,
            "name": name,
            "debug_data": debug_data,
        };
        postEvent(QE_CLASS_CONNECTION, QEC_CONNECTION_DEBUG_DATA_CHANGE, ES_Major, info, tld.cx);
    }

    postConnectionCreated(hash<auto> connection_info) {
        QDBG_ASSERT(connection_info.connectionid);
        QDBG_ASSERT(connection_info.conntype);
        QDBG_ASSERT(connection_info.name);
        postEvent(QE_CLASS_CONNECTION, QEC_CONNECTION_CREATED, ES_Major, connection_info, tld.cx);
    }

    postConnectionUpdated(int id, string conntype, string name, hash<auto> connection_info) {
        connection_info = {
            "id": id,
            "conntype": conntype,
            "name": name,
        } + connection_info;
        postEvent(QE_CLASS_CONNECTION, QEC_CONNECTION_UPDATED, ES_Major, connection_info, tld.cx);
    }

    postConnectionDeleted(string connection_alert_type, string connection_name) {
        hash<auto> info = {
            "type": connection_alert_type,
            "name": connection_name,
        };
        postEvent(QE_CLASS_CONNECTION, QEC_CONNECTION_DELETED, ES_Major, info, tld.cx);
    }

    postLoggerCreated(hash<auto> info) {
        postEvent(QE_CLASS_LOGGER, QEC_LOGGER_CREATED, ES_Major, info, tld.cx);
    }

    postLoggerUpdated(hash<auto> info) {
        postEvent(QE_CLASS_LOGGER, QEC_LOGGER_UPDATED, ES_Major, info, tld.cx);
    }

    postLoggerDeleted(hash<auto> info) {
        postEvent(QE_CLASS_LOGGER, QEC_LOGGER_DELETED, ES_Major, info, tld.cx);
    }

    postAppenderCreated(hash<auto> info) {
        postEvent(QE_CLASS_LOGGER, QEC_APPENDER_CREATED, ES_Major, info, tld.cx);
    }

    postAppenderUpdated(hash<auto> info) {
        postEvent(QE_CLASS_LOGGER, QEC_APPENDER_UPDATED, ES_Major, info, tld.cx);
    }

    postAppenderDeleted(hash<auto> info) {
        postEvent(QE_CLASS_LOGGER, QEC_APPENDER_DELETED, ES_Major, info, tld.cx);
    }

    postConnectionReloaded(string connections_type, list connection_info) {
        hash<auto> info = {
            "type": connections_type,
            "connections": connection_info,
        };
        postEvent(QE_CLASS_CONNECTION, QEC_CONNECTIONS_RELOADED, ES_Major, info, tld.cx);
    }

    postGroupStatusChanged(string name, bool enabled, *hash<auto> info) {
        info += {
            "name": name,
            "enabled": enabled,
        };
        postEvent(QE_CLASS_GROUP, QEC_GROUP_STATUS_CHANGED, ES_Major, info, tld.cx);
    }

    postSystemHealthChanged(string newv, string old, hash<auto> ah) {
        hash<auto> info = {
            "health": newv,
            "old-health": old,
         } + ah;
        postEvent(QE_CLASS_SYSTEM, QEC_SYSTEM_HEALTH_CHANGED, ES_Major, info, tld.cx);
    }

    postSystemRemoteHealthChanged(string name, string url, string newv, string old, *hash<auto> ah, *string err) {
        hash<auto> info = (
            "name": name,
            "health": newv,
            "old-health": old,
            "url": url,
        ) + ah;
        if (err)
            info.error = err;
        postEvent(QE_CLASS_SYSTEM, QEC_SYSTEM_REMOTE_HEALTH_CHANGED, ES_Major, info, tld.cx);
    }

    postProcessStarted(hash<auto> info) {
        postEvent(QE_CLASS_PROCESS, QEC_PROCESS_STARTED, ES_Major, info, tld.cx);
    }

    postProcessStopped(hash<auto> info) {
        postEvent(QE_CLASS_PROCESS, QEC_PROCESS_STOPPED, ES_Major, info, tld.cx);
    }

    postProcessStartError(hash<auto> info) {
        postEvent(QE_CLASS_PROCESS, QEC_PROCESS_START_ERROR, ES_Major, info, tld.cx);
    }

    postProcessMemoryChanged(hash<auto> info) {
        postEvent(QE_CLASS_PROCESS, QEC_PROCESS_MEMORY_CHANGED, ES_Major, info, tld.cx);
    }

    postProcessNodeInfo(hash<auto> info) {
        postEvent(QE_CLASS_CLUSTER, QEC_NODE_INFO, ES_Major, info, tld.cx);
    }

    postProcessNodeRemoved(hash<auto> info) {
        postEvent(QE_CLASS_CLUSTER, QEC_NODE_REMOVED, ES_Major, info, tld.cx);
    }

    private list<auto> getLastEventsUnlocked(int count) {
        int size = el.size();

        # in case there are fewer elements, return the entire list
        if (count >= size)
            return el;

        # issue #2280: this is approximately 3500x faster than copying the event list and truncating the elements we don't want
        return el[(size - count)..];
    }

    # get max <count> events from the end of the list
    hash<auto> getLastEvents(softint count) {
        AutoReadLock al(self);

        return (
            "events": getLastEventsUnlocked(count),
            "lastid": end,
        );
    }

    hash<auto> getLastEventsOr(softint count, *softlist<auto> list, *softlist<auto> and_not, *softlist<auto> nfilt) {
        # check is valid for list or hash
        if (!list && !and_not && !nfilt)
            throw "GET-LAST-EVENTS-OR-ERROR", "no criteria passed to get-last-events-or()";

        QorusEventManager::checkCriteriaArg(list);
        QorusEventManager::checkCriteriaArg(and_not);
        QorusEventManager::checkCriteriaArg(nfilt);

        AutoReadLock al(self);

        return (
            "events" : applyFilterOr(el.size() - count, list, and_not, nfilt),
            "lastid" : end,
        );
    }

    hash<auto> getLastEventsAnd(softint count, *softlist<auto> list, *softlist<auto> or_not, *softlist<auto> nfilt) {
        # check is valid for list or hash
        if (!list && !or_not && !nfilt)
            throw "GET-LAST-EVENTS-AND-ERROR", "no criteria passed to get-last-events-and()";

        QorusEventManager::checkCriteriaArg(list);
        QorusEventManager::checkCriteriaArg(or_not);
        QorusEventManager::checkCriteriaArg(nfilt);

        AutoReadLock al(self);

        return (
            "events" : applyFilterAnd(el.size() - count, list, or_not, nfilt),
            "lastid" : end,
        );
    }

    # return all events greater than min_id
    hash<auto> getEvents(softint min_id = 1, *timeout timeout_ms) {
        if (min_id <= 0)
            min_id = 1;

        AutoReadLock al(self);

        while (!el || end < min_id) {
            if (shutdown)
                return (
                    "lastid" : end,
                    "shutdown": True,
                );

            ++waiting;
            on_exit --waiting;

            if (!timeout_ms || cond.wait(self, timeout_ms))
                return ( "lastid" : end );
        }

        #int size = elements el;

        # how many elements will we return
        int nel = end - min_id + 1;

        return (
            "events" : getLastEventsUnlocked(nel),
            "lastid" : end,
        );
    }

    # return all events greater than min_id and at least one of the conditions passed is met
    hash<auto> getEventsOr(softint min_id = 1, *softlist<auto> list, *timeout timeout_ms, *softlist<auto> and_not, *softlist<auto> nfilt) {
        if (min_id <= 0)
            min_id = 1;

        # check is valid for list or hash
        if (!list && !and_not && !nfilt)
            throw "GET-EVENTS-OR-ERROR", "no criteria passed to get-events-or()";

        QorusEventManager::checkCriteriaArg(list);
        QorusEventManager::checkCriteriaArg(and_not);
        QorusEventManager::checkCriteriaArg(nfilt);

        int estart = clock_getmillis();

        while (True) {
            AutoReadLock al(self);

            while (!el || end < min_id) {
                if (shutdown)
                    return (
                        "lastid" : end,
                        "shutdown": True,
                    );

                ++waiting;
                on_exit --waiting;

                if (!timeout_ms || cond.wait(self, timeout_ms))
                    return ( "lastid" : end );
            }

            # how many elements will we return
            int count = end - min_id + 1;

            list<auto> rv = applyFilterOr(el.size() - count, list, and_not, nfilt);

            if (rv)
                return (
                    "events" : rv,
                    "lastid" : end,
                );

            # determine timeout time remaining
            timeout_ms = timeout_ms - (clock_getmillis() - estart);

            # see if we have any time left on the timeout
            if (timeout_ms <= 0)
                return ( "lastid" : end );

            # start search from last event
            min_id = end + 1;
        }
    }

    private static checkCriteriaArg(auto list) {
        # check criteria list
        foreach auto c in (list) {
            if (c.typeCode() != NT_HASH)
                throw "GET-EVENTS-ERROR", sprintf("non-hash criteria element passed as event filter (type found: %s)",
                    type(c));

            foreach string k in (keys c) {
                if (!QEM_FILTER_CRITERIA_HASH{k})
                    throw "INVALID-CRITERIA-CODE", sprintf("invalid criteria code %y found in event filter, "
                        "expecting one of: %n", k, QEM_FILTER_CRITERIA);
            }
        }
    }

    # return all events greater than min_id and all of the conditions passed are met
    hash<auto> getEventsAnd(softint min_id = 0, softlist<auto> list, *timeout timeout_ms, *softlist<auto> or_not,
            *softlist<auto> nfilt) {
        if (!min_id)
            min_id = 1;

        # check is valid for list or hash
        if (!list && !or_not && !nfilt)
            throw "GET-EVENTS-AND-ERROR", "no criteria passed to get-events-and()";

        QorusEventManager::checkCriteriaArg(list);
        QorusEventManager::checkCriteriaArg(or_not);
        QorusEventManager::checkCriteriaArg(nfilt);

        int estart = clock_getmillis();

        while (True) {
            AutoReadLock al(self);

            while (!el || end < min_id) {
                if (shutdown)
                    return (
                        "lastid" : end,
                        "shutdown": True,
                    );

                ++waiting;
                on_exit --waiting;

                if (!timeout_ms || cond.wait(self, timeout_ms))
                    return ( "lastid" : end );
            }

            # how many elements will we return
            int count = end - min_id + 1;

            list<auto> rv = applyFilterAnd(el.size() - count, list, or_not, nfilt);

            if (rv)
                return (
                    "events" : rv,
                    "lastid" : end,
                );

            # determine timeout time remaining
            int nt = clock_getmillis();
            timeout_ms -= (nt - estart);

            # see if we have any time left on the timeout
            if (timeout_ms <= 0)
                return ( "lastid" : end );

            # start search from last event
            min_id = end + 1;
        }
    }

    # criteria hash keys corresponds to QEM_FILTER_CRITERIA list (defined in qorus.ql)
    static private bool checkCriteria(hash<auto> e, string k, auto v) {
        switch (k) {
            case "class":
                return e.class == v ? True : False;
            case "classhash":
                return boolean(v{e.class});
            case "classstr":
                return e.classstr == v ? True : False;
            case "classstrhash":
                return boolean(v{e.classstr});
            case "event":
                return e.event == v ? True : False;
            case "eventhash":
                return boolean(v{e.event});
            case "eventstr":
                return e.eventstr == v ? True : False;
            case "eventstrhash":
                return boolean(v{e.eventstr});
            case "minseverity":
                return e.severity >= v;
            case "minseveritystr":
                return ErrorSeverityOrder.(e.severity) >= ErrorSeverityOrder{v};
            case "minuserseverity":
                return exists e.userseverity && e.userseverity >= v;
            case "minuserseveritystr":
                return exists e.userseverity && ErrorSeverityOrder.(e.userseverity) >= ErrorSeverityOrder{v};
            case "mincompositeseverity":
                return e.compositeseverity >= v;
            case "mincompositeseveritystr":
                return ErrorSeverityOrder.(e.compositeseverity) >= ErrorSeverityOrder{v};
            case "all": # value is ignored with this criteria
                return True;
            case "none": # value is ignored with this criteria
                return False;
        }
        return False;
    }

    bool checkAnd(hash<auto> event, *softlist<auto> list) {
        foreach hash<auto> c in (list) {
            bool ok;
            foreach string k in (keys c) {
                if (QorusEventManager::checkCriteria(event, k, c{k})) {
                    ok = True;
                    break;
                }
            }
            if (!ok)
                return False;
        }
        return True;
    }

    bool checkOr(hash<auto> event, *softlist<auto> list) {
        foreach hash<auto> c in (list) {
            bool ok = True;
            foreach string k in (keys c) {
                if (!QorusEventManager::checkCriteria(event, k, c{k})) {
                    ok = False;
                    break;
                }
            }
            if (ok)
                return True;
        }
        return False;
    }

    list<auto> applyFilterOr(softint estart, *softlist<auto> list, *softlist<auto> and_not, *softlist<auto> nfilt) {
        if (estart < 0)
            estart = 0;

        list<auto> rv = ();
        int size = el.size();

        # check elements to see if they meet the filter criteria
        for (int i = estart; i < size; ++i) {
            hash<auto> e = el[i];

            if ((checkOr(e, list) && (!and_not || !checkAnd(e, and_not))) && (!nfilt || !checkOr(e, nfilt)))
                rv += e;
        }

        return rv;
    }

    list<auto> applyFilterAnd(softint estart, *softlist<auto> list, *softlist<auto> or_not, *softlist<auto> nfilt) {
        if (estart < 0)
            estart = 0;

        list<auto> rv = ();
        int size = el.size();

        # check elements to see if they meet the filter criteria
        for (int i = estart; i < size; ++i) {
            hash<auto> e = el[i];

            if ((checkAnd(e, list) || (or_not && !checkOr(e, or_not))) && (!nfilt || !checkOr(e, nfilt)))
                rv += e;
        }

        return rv;
    }
}
