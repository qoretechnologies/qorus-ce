# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

public namespace OMQ;

%new-style
%strict-args
%require-types

class OMQ::AlertManager {
    public {
        const DefaultMax = 1000;

        const InfoKeys = (
            "name", "version", "workflowid", "workflow_instanceid", "stepid", "ind",
            "servicetype", "serviceid", "jobid", "job_instanceid",
        );

        const TransTimeout = 1h;
    }

    private {
        # system health derived from alert status
        string health = "GREEN";

        # total number of active ongoing alerts
        int ongoingAlertCount = 0;

        # total number of transient alerts in the last hour
        int transientAlertCount = 0;

        # Condition for transient health thread
        Condition transientHealthCondition();

        # read-write lock
        RWLock readWriteLock();

        # maximum number of transient alerts to store
        int alertMax = DefaultMax;

        # for transient alerts
        list<hash<auto>> transientAlerts = ();

        # for ongoing alerts
        # interface type -> interface id -> alert
        hash<string, hash<string, hash<string, auto>>> ongoingAlerts;

        # for alerts shadowed by other alerts
        # interface type -> interface id -> alert
        hash<string, hash<string, hash<string, auto>>> shadowedAlerts;

        # SMTP client for alert emails
        SmtpClient smtp;

        # SMTP From: address
        string from;

        # Alert email queue
        Queue queue();

        # Alert notification thread condition
        Condition notificationCondition();

        # Alert thread lock
        Mutex mtx();

        # Alert thread exit counter
        Counter exitCounter();

        # initialized flag
        bool init = False;

        # quit flag
        bool quit = False;

        # alert id sequence
        Sequence alertId(1);

        # process ID -> int
        hash<string, int> processesWithMemoryAlerts();

        # process memory warning percent
        int processMemoryWarnPercent;

        # system alert email/SMTP options
        const Opts = {
            "alert-smtp-connection": True,
            "alert-smtp-to": True,
            "alert-smtp-from": True,
            "alert-smtp-interval": True,
            "alert-smtp-enable": True,
        };

        # alert logger
        Logger logger;
    }

    constructor() {
        logger = createLogger(Qorus.loggerController.getLoggerParamsSubs("ALERT"));
    }

    updateLogger(*hash<LoggerParams> params) {
        params = substituteLogFilename(params, LoggerController::getLoggerSubs("ALERT"));
        logger = createLogger(params);
        logDebug("ALERT logger has been updated with params: %y", params);
    }

    init() {
        # get process memory warning percent
        processMemoryWarnPercent = Qorus.options.get("warning-process-memory-percent");

        # start transient counter thread
        exitCounter.inc();
        {
            on_error exitCounter.dec();
            background transientCounter();
        }

        bool ok = False;

        on_exit {
            init = True;
            if (!ok) {
                queue.clear();
            }
        }

        hash oh = Opts;
        map delete oh.$1, keys Opts, exists Qorus.options.get($1);

        if (oh.size() == Opts.size()) {
            logError("No alert SMTP options were set so alerts will not be emailed; to configure email alerts"
                     ", set the following system options and restart Qorus: %y", Opts.keys());
            return;
        }

        if (!oh.empty() && oh.size() != Opts.size()) {
            logError("The following options were not set so alerts cannot be emailed: %y", oh.keys());
            return;
        }

        if (Qorus.options.get("alert-smtp-interval") <= 0) {
            logError("Option \"alert-smtp-interval\" is set to invalid value %y; using 20 instead",
                     Qorus.options.get("alert-smtp-interval"));
            Qorus.options.set(("alert-smtp-interval" : 20));
        }

        string connection = Qorus.options.get("alert-smtp-connection");
        *hash h;
        try {
            h = Qorus.connections.getInfo(connection);
            if (!h) {
                throw "ALERT-SMTP-ERROR", sprintf("connection %y does not exist", connection);
            }
            if (h.type != "smtp") {
                throw "ALERT-SMTP-ERROR", sprintf("connection %y is not an SMTP connection: type: %y, url: %y",
                                                  connection, h.type, h.url);
            }
            smtp = Qorus.connections.get(connection, False, False);
        } catch (hash ex) {
            logError("cannot acquire SMTP object for alert emails: %s: %s", ex.err, ex.desc);
            return;
        }

        from = regex_subst(Qorus.options.get("alert-smtp-from"), "\\instance", Qorus.options.get("instance-key"));

        logError("using SMTP connection: %y url: %y from: %y for alert emails", connection, h.url, from);

        exitCounter.inc();
        ok = Qorus.options.get("alert-smtp-enable");

        on_error {
            exitCounter.dec();
            ok = False;
        }
        background emailThread();
    }

    shutdown() {
        quit = True;
        notificationCondition.signal();
        transientHealthCondition.signal();
        exitCounter.waitForZero();
    }

    # returns a hash of alert type to the number of alerts of that type
    hash<string, int> getOngoingAlertSummary() {
        hash<string, int> rv();
        # get ongoing alert counts
        map rv{$1.key} += $1.value.size(), ongoingAlerts.pairIterator();
        # issue #2819: add "shadowed" alert counts
        map rv{$1.key} += $1.value.size(), shadowedAlerts.pairIterator();
        return rv;
    }

    raiseProcessStartError(string id, hash<ExceptionInfo> ex) {
        # raise an ongoing alert for this process
        ActionReason reason(tld.cx, ex);
        raiseOngoingAlert(reason, "PROCESS", id, "PROCESS-START-ERROR");
    }

    clearProcessStartError(string id) {
        clearOngoingAlert("PROCESS", id, "PROCESS-START-ERROR");
    }

    checkProcessMemory(hash<auto> process_info) {
        readWriteLock.writeLock();
        on_exit if (readWriteLock.lockOwner()) {
            readWriteLock.writeUnlock();
        }

        #logDebug("cPM() process_info: %y processMemoryWarnPercent: %y processesWithMemoryAlerts: %y", process_info,
        #         processMemoryWarnPercent, processesWithMemoryAlerts);

        if (process_info.pct >= processMemoryWarnPercent) {
            # if there is already an alert for this process, then return
            if (processesWithMemoryAlerts{process_info.id} == process_info.pct) {
                return;
            }

            # flag the alert as set
            processesWithMemoryAlerts{process_info.id} = process_info.pct;

            # unlock lock to raise alert
            readWriteLock.writeUnlock();

            # raise an ongoing alert for this process
            ActionReason reason(NOTHING, sprintf("process %y has used %d%% of RAM (%s) on node %y (%s), crossing the"
                                                 " warning threshold set by system option"
                                                 " \"warning-process-memory-percent\" at %d%%", process_info.id,
                                                 process_info.pct, get_byte_size(process_info.priv), process_info.node,
                                                 process_info.host, processMemoryWarnPercent));

            raiseOngoingAlert(reason, "PROCESS", process_info.id, "PROCESS-MEMORY-USAGE", process_info);
        } else if (processesWithMemoryAlerts{process_info.id}) {
            clearProcessMemoryAlertLocked(process_info.id);
        }
    }

    processStopped(hash process_info) {
        readWriteLock.writeLock();
        on_exit if (readWriteLock.lockOwner()) {
            readWriteLock.writeUnlock();
        }

        if (processesWithMemoryAlerts{process_info.id}) {
            clearProcessMemoryAlertLocked(process_info.id);
        }
    }

    # called in the write lock, returns with the lock unlocked
    private clearProcessMemoryAlertLocked(string id) {
        QDBG_ASSERT(processesWithMemoryAlerts.hasKey(id));

        # remove alert flag
        remove processesWithMemoryAlerts{id};

        # unlock lock to clear alert
        readWriteLock.writeUnlock();

        # clear ongoing alert
        clearOngoingAlert("PROCESS", id, "PROCESS-MEMORY-USAGE");
    }

    private transientCounter() {
        readWriteLock.writeLock();

        on_exit {
            readWriteLock.writeUnlock();
            exitCounter.dec();
        }

        while (True) {
            # trigger time for disregarding events
            date trig = now_us() - TransTimeout;

            # adjust count for events past the deadline
            int n_tcnt = transientAlertCount;
            if (transientAlertCount > transientAlerts.size()) {
                transientAlertCount = transientAlerts.size();
            }

            while (transientAlertCount && transientAlerts[transientAlertCount - 1].when <= trig) {
                --transientAlertCount;
            }

            if (n_tcnt != transientAlertCount) {
                checkHealthChangeIntern();
            }

            if (transientAlertCount) {
                transientHealthCondition.wait(readWriteLock, transientAlerts[transientAlertCount - 1].when - trig);
            } else {
                transientHealthCondition.wait(readWriteLock);
            }

            if (quit) {
                return;
            }
        }
    }

    private checkHealthChangeIntern() {
        int t = ongoingAlertCount + transientAlertCount;
        string nh;
        if (!t) {
            nh = "GREEN";
        } else if (t < 10) {
            nh = "YELLOW";
        } else {
            nh = "RED";
        }
        if (nh != health) {
            Qorus.events.postSystemHealthChanged(nh, health, {
                "ongoing": ongoingAlertCount,
                "transient": transientAlertCount,
                "cutoff": now_us() - TransTimeout
            });
            health = nh;
        }
    }

    private bool sleep() {
        # interruptible sleep
        mtx.lock();
        on_exit mtx.unlock();
        if (!notificationCondition.wait(mtx, Qorus.options.get("alert-smtp-interval") * 1000)) {
            return True;
        }
        return False;
    }

    private emailThread() {
        on_exit exitCounter.dec();

        # wait for initial alerting delay on startup
        if (sleep()) {
            return;
        }

        while (!quit) {
            if (!queue.empty()) {
                sendEmails();
            }

            if (sleep()) {
                break;
            }
        }
    }

    private sendEmails() {
        list l = ();
        while (!queue.empty()) {
            l += queue.pop();
        }

        # build email body
        string body = "Do not reply to this email; it is sent from an unattended address\n\n";
        body += "*************\nAlert Summary\n*************\n";
        # first add index
        map body += sprintf("+ %s: %s: %s\n", $1.alerttype, $1.object, $1.alert), l;
        body += "\n*************\nAlert Details\n*************\n";
        # now add details
        map body += sprintf("+ %s: %s: %s: %s\n  + %y\n\n",
                            $1.when.format("YYYY-MM-DD HH:mm:SS.us"), $1.alerttype, $1.object, $1.alert,
                            $1 - ("when", "object", "alert", "type", "servicetype", "name", "id", "version", "smap")),
            l;

        string subject = sprintf("%d ALERT%s from Qorus instance %y sessionid %d on %s PID %d started %s",
                                 l.size(), l.size() == 1 ? "" : "S", Qorus.session.getKey(), Qorus.session.getID(),
                                 gethostname(), getpid(), Qorus.start_time.format("YYYY-MM-DD HH:mm:SS.us"));

        try {
            Message msg(from, subject);
            msg.setBody(body);

            foreach string addr in (Qorus.options.get("alert-smtp-to")) {
                msg.addTO(addr);
            }

            smtp.sendMessage(msg);
            #logDebug("body: %s", body);
            logInfo("sent alert email to %y with %d alert%s", Qorus.options.get("alert-smtp-to"), l.size(),
                    l.size() == 1 ? "" : "s");
        } catch (hash ex) {
            logError("failed to send alert email: %s: %s", ex.err, ex.desc);
        }
    }

    setTransientMax(int max) {
        readWriteLock.writeLock();
        on_exit readWriteLock.writeUnlock();

        alertMax = max;
        checkIntern();
    }

    list getAlerts(string type, softstring id) {
        readWriteLock.readLock();
        on_exit readWriteLock.readUnlock();

        return getAlertsIntern(type, id);
    }

    list<hash<auto>> getAlerts(string type, list<hash<auto>> l, string k) {
        readWriteLock.readLock();
        on_exit readWriteLock.readUnlock();

        return map $1 + {"alerts": getAlertsIntern(type, $1{k})}, l;
    }

    private list<hash<auto>> getAlertsIntern(string type, softstring id) {
        list<hash<auto>> rv = ();
        foreach string alert in (keys ongoingAlerts{type}{id}) {
            rv += {"type": type, "id": id} + ongoingAlerts{type}{id}{alert} - "smap";

            map rv += {"type": "GROUP", "id": $1} + ongoingAlerts.GROUP{$1} - "smap",
                keys shadowedAlerts{type}{id}{alert}."by";
        }

        return rv;
    }

    private logArgs(int lvl, string msg, auto args) {
        string fmsg = vsprintf(msg, args);
        logger.log(lvl, "%s", fmsg, new LoggerEventParameter(\Qorus.eventLog.logEvent(), "alert",
            sprintf("%s T%d [%s]: ", log_now(), gettid(), LoggerLevel::getLevel(lvl).getStr()) + fmsg + "\n"));
    }

    logDebug(string msg) {
        logArgs(Logger::LoggerLevel::DEBUG, msg, argv);
    }

    logInfo(string msg) {
        logArgs(Logger::LoggerLevel::INFO, msg, argv);
    }

    logError(string msg) {
        logArgs(Logger::LoggerLevel::ERROR, msg, argv);
    }

    logFatal(string msg) {
        logArgs(Logger::LoggerLevel::FATAL, msg, argv);
    }

    rotateLogFiles() {
        foreach auto appender in (logger.getAppenders()) {
            if (appender instanceof AbstractLoggerAppenderFileRotate) {
                cast<AbstractLoggerAppenderFileRotate>(appender).rotate();
            }
        }
    }

    private removeShadowIntern(softstring id, string stype, softstring sid, string alert) {
        reference<auto> sm = \shadowedAlerts{stype}{sid}{alert};
        # remove "by" entry
        delete sm."by"{id};

        if (sm."by") {
            return;
        }

        # move back to ongoing hash if no longer shadowed
        # if there is no shadowed object or "alert" is not set, then just delete it
        if (!sm.alert) {
            remove sm;
        } else {
            ongoingAlerts{stype}{sid}{alert} = remove sm;
        }
        if (!shadowedAlerts{stype}) {
            delete shadowedAlerts{stype};
        }
    }

    private addShadowedAlert(softstring id, string stype, softstring sid, string alert) {
        reference<auto> sm = \shadowedAlerts{stype}{sid}{alert};
        if (ongoingAlerts{stype}{sid}{alert}) {
            #if (!sm)
            #    ++ongoingAlertCount;
            sm = (remove ongoingAlerts{stype}{sid}{alert});
        }
        # add "by" entry (alerts can only be shadowed by groups so only the id is used)
        sm."by"{id} = True;
    }

    updateShadowedAlerts(string type, softstring id, string stype, string alert, *list<auto> add, *list<auto> del) {
        readWriteLock.writeLock();
        on_exit readWriteLock.writeUnlock();

        reference<auto> ah = \ongoingAlerts{type}{id}{alert};
        if (!ah) {
            return;
        }

        # remove any shadowed alerts in del list
        if (del) {
            map removeShadowIntern(id, stype, $1, alert), del;

            # make a hash of ids to delete from smap
            hash<string, bool> dh;
            map dh.$1 = True, del;
            ah.smap = select ah.smap, ($1.type != stype || !dh.($1.id));
        }

        # move any new shadowed alerts to shadow map / increment shadow count
        foreach softstring sid in (add) {
            addShadowedAlert(id, stype, sid, alert);

            # add to shadow list in shadowing object
            ah.smap += {"type": stype, "id": sid};
        }
    }

    private static *int auditAlert(int ae, ActionReason r, string alert, *hash<auto> info) {
        if (!Qorus.audit) {
            Qorus.waitForStartup();
        }
        return Qorus.audit.alertEvent(NOTHING, ae, info.workflowid,
            info.workflow_instanceid, info.stepid, info.ind,
            info.jobid, info.job_instanceid, info.serviceid,
            NOTHING, r.getReason(), r.getWho(), r.getSource(),
            alert, info - ("workflowid", "workflow_instanceid", "stepid", "ind",
                            "user_event", "serviceid", "jobid", "job_instanceid"));
    }

    private static string getObject(string type, string id, *hash info) {
        if (!info.name) {
            return sprintf("%s %s", type, id);
        }
        if (info.servicetype) {
            return sprintf("%s %s %s v%s (%s)", info.servicetype, type, info.name, info.version, id);
        }
        string str = type + " " + info.name;
        if (info.version) {
            str += " " + info.name;
        }
        if (info.name != id) {
            str += sprintf(" (%d)", id);
        }
        return str;
    }

    raiseOngoingAlert(ActionReason reason, string type, softstring id, string alert, *hash<auto> info, *list<auto> smap) {
        if (!Qorus.audit) {
            background raiseOngoingAlertIntern(reason, type, id, alert, info, smap, True);
            return;
        }
        raiseOngoingAlertIntern(reason, type, id, alert, info, smap);
    }

    private raiseOngoingAlertIntern(ActionReason reason, string type, softstring id, string alert, *hash<auto> info,
            *list<auto> smap, *bool wait_for_startup) {
        if (wait_for_startup) {
            Qorus.waitForStartup();
        }
        hash<auto> alert_info = {
            "alert": alert,
            "alertid": alertId.next(),
            "reason": reason.getReason(),
            "who": reason.getWho(),
            "source": reason.getSource(),
            "object": AlertManager::getObject(type, id, info),
            "instance": Qorus.session ? Qorus.session.getKey() : "unknown",
        } + info;

        hash<auto> alert_hash = {
            "alerttype": "ONGOING",
            "when": now_us(),
            "smap": smap,
            "local": True,
        } + alert_info;

        {
            code doalert = sub () {
                alert_info.auditid = alert_hash.auditid = AlertManager::auditAlert(AE_ALERT_ONGOING_RAISED, reason,
                                                                                   alert, info);
                # raise system event
                hash<auto> alert_event_info = {"type": type, "id": id} + alert_info;
                Qorus.events.postAlertOngoingRaised(alert_event_info);

                if (Qorus.options.get("alert-smtp-enable") && (smtp || !init)) {
                    queue.push({"alerttype": "ONGOING"} + alert_event_info + alert_hash);
                }
            };

            readWriteLock.writeLock();
            on_exit readWriteLock.writeUnlock();

            # if adding a new ongoing alert, then increment the ongoing alert count
            if (!shadowedAlerts{type}{id}{alert} && !ongoingAlerts{type}{id}{alert}) {
                ++ongoingAlertCount;
                checkHealthChangeIntern();
            }

            # update and return if the alert is already shadowed
            if (shadowedAlerts{type}{id}{alert}) {
                if (!shadowedAlerts{type}{id}{alert}.first_raised) {
                    shadowedAlerts{type}{id}{alert}.first_raised = shadowedAlerts{type}{id}{alert}.when;
                }
                shadowedAlerts{type}{id}{alert} += alert_hash;

                return;
            }

            # check if the alert is already ongoing
            bool new_info = True;
            if (ongoingAlerts{type}{id}{alert}) {
                new_info = False;

                if (!ongoingAlerts{type}{id}{alert}.first_raised) {
                    ongoingAlerts{type}{id}{alert}.first_raised = shadowedAlerts{type}{id}{alert}.when;
                }

                alert_hash -= "alertid";
            } else {
                doalert();
            }

            ongoingAlerts{type}{id}{alert} += alert_hash;

            # move any shadowed alerts to shadow map / increment shadow count
            map addShadowedAlert(id, $1.type, $1.id, alert), smap;

            # return without additional logging if the event was already ongoing
            if (!new_info) {
                return;
            }
        }

        logInfo("ALERT_ONGOING_RAISED: type: %y, id: %y, alert: %y, reason: %y, info: %y", type, id, alert,
                reason.getReason(), info);
    }

    clearOngoingAlert(string type, softstring id, string alert) {
        ActionReason reason();
        reason.set(tld.cx);
        clearOngoingAlert(reason, type, id, alert);
    }

    clearAllOngoingAlerts(string type, softstring id) {
        foreach string alert in (keys ongoingAlerts{type}{id}) {
            clearOngoingAlert(type, id, alert);
        }
    }

    clearAllOngoingAlerts(ActionReason reason, string type, softstring id) {
        foreach string alert in (keys ongoingAlerts{type}{id}) {
            clearOngoingAlert(reason, type, id, alert);
        }
    }

    clearOngoingAlert(ActionReason reason, string type, softstring id, string alert) {
        *hash alert_hash;
        {
            readWriteLock.writeLock();
            on_exit readWriteLock.writeUnlock();

            if (alert) {
                reference<auto> ref = shadowedAlerts{type}{id}{alert}
                    ? \shadowedAlerts
                    : \ongoingAlerts;

                alert_hash = remove ref{type}{id}{alert};
                # issue #3248: make sure and remove all parent keys if possible
                if (!ref{type}{id}) {
                    remove ref{type}{id};
                    if (!ref{type}) {
                        remove ref{type};
                    }
                }
            }

            # if there was no such alert, then return
            if (!alert_hash) {
                return;
            }

            # if clearing an ongoing alert, then decrement the ongoing alert count
            if (alert_hash.alert) {
                --ongoingAlertCount;
                checkHealthChangeIntern();
            }

            # remove shadow references and re-enable any shadowed alerts when the last one is removed
            map removeShadowIntern(id, $1.type, $1.id, alert), alert_hash.smap;
        }

        hash event_info = ("type": type, "id": id, "reason": reason.getReason()) +
            alert_hash.("alertid", "servicetype", "name", "version");
        if (alert_hash.auditid)
            Qorus.audit.alertEvent(alert_hash.auditid, AE_ALERT_ONGOING_CLEARED, alert_hash.workflowid,
                                   alert_hash.workflow_instanceid, alert_hash.stepid, alert_hash.ind,
                                   alert_hash.jobid, alert_hash.job_instanceid, alert_hash.serviceid, NOTHING,
                                   reason.getReason(), reason.getWho(), reason.getSource(),
                                   alert_hash.alert, event_info);

        # raise system event
        Qorus.events.postAlertOngoingCleared(event_info);

        logInfo("ALERT_ONGOING_CLEARED: type: %y, id: %y, reason: %y, info: %y", type, id, reason.getReason(),
                alert_hash.InfoKeys);
    }

    raiseTransientAlert(ActionReason reason, string type, softstring id, string alert, *hash info) {
        *int audit_id = AlertManager::auditAlert(AE_ALERT_TRANSIENT_RAISED, reason, alert, info);

        # common between alert info and alert event info
        hash<auto> alert_info = {
            "alert": alert,
            "alertid": alertId.next(),
            "reason": reason.getReason(),
            "who": reason.getWho(),
            "source": reason.getSource(),
            "object": AlertManager::getObject(type, id, info),
            "instance": Qorus.session.getKey(),
        } + info + (audit_id ? {"auditid": audit_id} : NOTHING);

        hash<auto> alert_hash = {
            "alerttype": "TRANSIENT",
            "when": now_us(),
            "type": type,
            "id": id,
            "local": True,
        } + alert_info;

        {
            readWriteLock.writeLock();
            on_exit readWriteLock.writeUnlock();

            bool tset = transientAlerts.empty();
            transientAlerts += alert_hash;

            ++transientAlertCount;
            checkHealthChangeIntern();

            # set transient index if adding the first transient alert to the list
            if (tset) {
                transientHealthCondition.signal();
            }

            checkIntern();
        }

        # raise event
        hash<auto> aih = {"type": type, "id": id} + alert_info;
        Qorus.events.postAlertTransientRaised(aih);
        if (Qorus.options.get("alert-smtp-enable") && (smtp || !init)) {
            queue.push({"alerttype": "TRANSIENT"} + aih + alert_hash);
        }

        logInfo("ALERT_TRANSIENT_RAISED: type: %y, id: %y, alert: %y, reason: %y, info: %y", type, id, alert,
                reason.getReason(), info);
    }

    list<hash<auto>> getOngoingAlerts() {
        list<hash<auto>> l = ();

        readWriteLock.readLock();
        on_exit readWriteLock.readUnlock();

        foreach string type in (keys ongoingAlerts) {
            foreach softstring id in (keys ongoingAlerts{type}) {
                foreach softstring alert in (keys ongoingAlerts{type}{id}) {
                    l += {
                        "type": type,
                        "id": id,
                    } + ongoingAlerts{type}{id}{alert} - "smap";
                }
            }
        }

        return l;
    }

    list<hash<auto>> getTransientAlerts(softint max = 50) {
        list<hash<auto>> l;
        {
            readWriteLock.readLock();
            on_exit readWriteLock.readUnlock();

            l = transientAlerts;
        }
        if (max > 0 && l.size() > max) {
            splice l, 0, (l.size() - max);
        }
        return l;
    }

    list<hash<auto>> getAllAlerts(softint max = 50) {
        return getOngoingAlerts() + getTransientAlerts(max);
    }

    hash<auto> getHealth() {
        readWriteLock.readLock();
        on_exit readWriteLock.readUnlock();

        return {
            "transient": transientAlertCount,
            "ongoing": ongoingAlertCount,
            "health": health,
        };
    }

    hash<auto> getAlertCounts(bool local = True, *softdate trans_cutoff) {
        hash<auto> h = {
            "cutoff": trans_cutoff,
            "transient": 0,
            "ongoing": 0,
        };

        *hash<auto> oh;
        *hash<auto> sh;
        *list<auto> l;
        {
            readWriteLock.readLock();
            on_exit readWriteLock.readUnlock();

            oh = ongoingAlerts;
            sh = shadowedAlerts;
            l = transientAlerts;
        }

        # get total count of ongoing alerts including shadow alerts

        # first add ongoing alerts
        map h.ongoing += $1.size(), oh.iterator();

        # now add shadowed alerts
        int shadowed;
        map shadowed += $1.size(), sh.iterator();
        h.ongoing += shadowed;

        # get count of transient alerts in the cutoff period
        foreach hash ah in (l) {
            if (trans_cutoff && ah.when > trans_cutoff) {
                break;
            }
            ++h."transient";
        }

        return h;
    }

    private checkIntern() {
        int rcnt = transientAlerts.size() - alertMax;
        if (rcnt > 0) {
            splice transientAlerts, 0, rcnt;

            # see if we need to adjust transientAlertCount & wait up the transient thread
            if (transientAlertCount > transientAlerts.size()) {
                transientAlertCount = transientAlerts.size();
                transientHealthCondition.signal();
                checkHealthChangeIntern();
            }
        }
    }

    # clear any alerts for objects that no longer exist
    rescanMetadata(*bool wf, *bool svc, *bool job) {
        # get a copy of current ongoing alerts
        *hash ah;
        {
            readWriteLock.readLock();
            on_exit readWriteLock.readUnlock();

            ah = ongoingAlerts;
        }

        ActionReason reason;
        code get_reason = ActionReason sub () {
            return reason ?? (reason = new ActionReason(NOTHING, "metadata deleted at runtime; object no longer exists"));
        };

        # remove any ongoing alerts for objects that no longer exist
        if (wf) {
            map clearAllOngoingAlerts(get_reason(), "WORKFLOW", $1),
                Qorus.qmm.getInvalidWorkflowIdsFromHash(ah.WORKFLOW);
        }

        if (svc) {
            map clearAllOngoingAlerts(get_reason(), "SERVICE", $1), Qorus.qmm.getInvalidServiceIdsFromHash(ah.SERVICE);
        }

        if (job) {
            map clearAllOngoingAlerts(get_reason(), "JOB", $1), Qorus.qmm.getInvalidJobIdsFromHash(ah.JOB);
        }
    }
}
