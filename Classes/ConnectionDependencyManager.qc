# -*- mode: qore; indent-tabs-mode: nil -*-
# @file ConnectionDependencyManager.qc defines the class that manages connection dependencies

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

class OMQ::ConnectionDependencyManager {
    private {
        # connection dependency hash; monitor source -> connection name -> type -> ID
        hash dh;

        # object dependency hash: type -> ID -> monitor source -> connection name
        hash oh;

        # dormant object dependency hash: type -> ID -> monitor source -> connection name
        hash doh;

        # startup/shutdown action hash: type -> ID -> action
        hash ah;
    }

    public {
        # raise an ongoing alert if the conn goes down
        const CONNECTION_RAISE_ALERT = True;
        # do not raise an ongoing alert if the conn goes down
        const CONNECTION_NO_ALERT = False;
    }

    hash<auto> dbgInfo() {
        return {
            "ah": ah,
            "dh": dh,
            "oh": oh,
            "doh": doh,
        };
    }

    list<hash<auto>> getConnections(string type, list<hash<auto>> l, string k) {
        ReadLockHelper rlh(Qorus.connection_rwl);

        foreach hash<auto> h in (\l) {
            h.connections = getConnectionsIntern(type, h{k});
        }

        return l;
    }

    list<hash<auto>> getConnections(string type, softstring id) {
        ReadLockHelper rlh(Qorus.connection_rwl);

        return getConnectionsIntern(type, id);
    }

    private list<hash<auto>> getConnectionsIntern(string type, softstring id) {
        list<hash<auto>> rv = ();

        foreach string k in (keys oh{type}{id}) {
            foreach string name in (keys oh{type}{id}{k}) {
                bool up;
                switch (k) {
                    case "USER-CONNECTION": up = Qorus.connections.isConnectionUp(name); break;
                    case "REMOTE": up = Qorus.remotemonitor.isConnectionUp(name); break;
                    case "DATASOURCE": up = Qorus.dsmanager.isConnectionUp(name); break;
                }
                rv += {
                    "type": k,
                    "name": name,
                    "up": up,
                };
            }
        }

        return rv;
    }

    hash<auto> getDependencies(hash<auto> h, string type) {
        ReadLockHelper rlh(Qorus.connection_rwl);

        return getDependenciesIntern(h, type);
    }

    hash<auto> getDependenciesHash(hash<auto> h, string type) {
        hash<auto> rv;

        ReadLockHelper rlh(Qorus.connection_rwl);

        return map {$1.key: getDependenciesIntern($1.value, type, $1.key)}, h.pairIterator();
    }

    list<auto> getDependencies(list<auto> l, string type) {
        ReadLockHelper rlh(Qorus.connection_rwl);

        foreach hash<auto> h in (\l) {
            h = getDependenciesIntern(h, type);
        }

        return l;
    }

    private hash<auto> getDependenciesIntern(hash<auto> h, string type, *string name) {
        hash<auto> rv += h;
        rv.deps = ();
        if (!name)
            name = h.name;
        if (dh{type}{name}) {
            foreach string dt in (keys dh{type}{name}) {
                foreach string id in (keys dh{type}{name}{dt}) {
                    rv.deps += {
                        "type": dt,
                    } + dh{type}{name}{dt}{id};
                }
            }
        }

        return rv;
    }

    resetStatus(string type, list<auto> idl) {
        Qorus.connection_rwl.writeLock();
        on_exit Qorus.connection_rwl.writeUnlock();

        map resetStatusIntern(type, $1.toString()), idl;
    }

    resetStatus(string type, softstring id) {
        Qorus.connection_rwl.writeLock();
        on_exit Qorus.connection_rwl.writeUnlock();

        resetStatusIntern(type, id);
    }

    private resetStatusIntern(string type, softstring id) {
        # delete any "CANT" statuses
        clearActionIntern(type, id, "CANT");

        # remove dependencies
        foreach string montype in (keys oh{type}{id}) {
            foreach string cn in (keys oh{type}{id}{montype}) {
                delete dh{montype}{cn}{type}{id};
                if (!dh{montype}{cn}{type}) {
                    delete dh{montype}{cn}{type};
                    if (!dh{montype}{cn}) {
                        delete dh{montype}{cn};
                        if (!dh{montype})
                            delete dh{montype};
                    }
                }
            }
        }

        delete oh{type}{id};
        if (!oh{type})
            delete oh{type};
        delete doh{type}{id};
        if (!doh{type})
            delete doh{type};
    }

    clearConnectionDependencies(string montype, list<auto> l) {
        Qorus.connection_rwl.writeLock();
        on_exit Qorus.connection_rwl.writeUnlock();

        # clear dependencies for all connections
        dh{montype} -= l;
    }

    connectionUp(ConnectionsServer mon, string name, string fmt) {
        Qorus.connection_rwl.writeLock();
        on_exit Qorus.connection_rwl.writeUnlock();

        ActionReason reason(tld.cx, vsprintf(fmt, argv), True);
        connectionUpIntern(mon, reason, name);
    }

    connectionUp(ConnectionsServer mon, ActionReason reason, string name, bool clear_deps = False) {
        string montype = mon.getAlertType();

        Qorus.connection_rwl.writeLock();
        on_exit Qorus.connection_rwl.writeUnlock();

        connectionUpIntern(mon, reason, name);

        if (clear_deps) {
            # clear object dependencies for connection
            foreach string type in (dh{montype}{name}.keyIterator()) {
                foreach string id in (dh{montype}{name}{type}.keyIterator()) {
                    delete oh{type}{id}{montype}{name};
                    if (!oh{type}{id}{montype}) {
                        delete oh{type}{id}{montype};
                        if (!oh{type}{id}) {
                            delete oh{type}{id};
                            if (!oh{type})
                                delete oh{type};
                        }
                    }
                    clearDormantIntern(montype, type, id, name);
                }
            }
        }
    }

    private clearDormantIntern(string montype, string type, string id, string name) {
        delete doh{type}{id}{montype}{name};
        if (!doh{type}{id}{montype}) {
            delete doh{type}{id}{montype};
            if (!doh{type}{id}) {
                delete doh{type}{id};
                if (!doh{type})
                    delete doh{type};
            }
        }
    }

    # called in the write lock
    private connectionUpIntern(ConnectionsServer mon, string name, string fmt) {
        ActionReason reason(tld.cx, vsprintf(fmt, argv), True);
        connectionUpIntern(mon, reason, name);
    }

    # called in the write lock
    private connectionUpIntern(ConnectionsServer mon, ActionReason reason, string name, bool change = True) {
        if (change) {
            Qorus.alerts.clearOngoingAlert(reason, mon.getAlertType(), name, mon.getAlertText());
            Qorus.events.postConnectionUpEvent(mon.getAlertType(), name, mon.getAttributes(name));
        }

        string montype = mon.getAlertType();

        foreach string type in (keys dh{montype}{name}) {
            foreach string id in (keys dh{montype}{name}{type}) {
                # clear dormant object hash entry
                clearDormantIntern(montype, type, id, name);

                hash<auto> info = dh{montype}{name}{type}{id};

                # check if object can be reactivated
                if (!doh{type}{id}) {
                    # FIXME is this the right place to check shutting_down?
                    # --PQ 29-Aug-2016
                    if (ah{type}{id}.START || Qorus.shutting_down) {
                        #mon.log(name, "start already in progress for %s; skipping", info.desc);
                        continue;
                    }
                    if (ah{type}{id}.CANT.START) {
                        # delete "can't start" marker so it can be be tried the next time
                        delete ah{type}{id}.CANT.START;
                        #mon.log(name, "start failed previously for %s while all connections were up; skipping", info.desc);
                        continue;
                    }

                    ah{type}{id}.START = True;

                    bool del = True;
                    on_exit
                        if (del) delActionIntern(type, id, "START");

                    switch (type) {
                        case "WORKFLOW": {
                            # do not use control to check the option here; use internal cached data instead since we need it anyway
                            *hash<auto> wf = Qorus.qmm.lookupWorkflow(id);
                            # issue #1921: do not spawn a thread to autostart a workflow if it's already running with its target config
                            if (wf && (wf.autostart
                                       && wf.autostart != Qorus.control.getExecInstanceCountIndication(id))) {
                                if (wf."runtime-options"."manage-interfaces"
                                    || (!exists wf."runtime-options"."manage-interfaces"
                                        && Qorus.options.get("manage-interfaces"))) {
                                    # issue #1921: do not spawn a thread to autostart a workflow if it's already
                                    # running with its target config
                                    if (wf.autostart && wf.autostart != Qorus.control.getExecInstanceCountIndication(id)) {
                                        del = False;
                                        background autoStartWorkflow(mon, name, id, info, wf);
                                    }
                                } else {
                                    mon.log(name, "not attempting to activate %s %s because system option "
                                        "\"manage-interfaces\" is False", type, info.desc);
                                }
                            }
                            break;
                        }
                        case "SERVICE": {
                            # issue #2851: support for overriding the "manage-interfaces" option can be added after
                            # persistent option handling is implemented for services
                            *AbstractQorusCoreService svc = services.getService(info.servicetype, info.name);
                            # only start service if it's not loaded
                            if (!svc) {
                                if (Qorus.options.get("manage-interfaces")) {
                                    *hash<auto> sh = Qorus.qmm.lookupService(id, False);
                                    if (sh.autostart) {
                                        del = False;
                                        background startService(mon, name, id, info, sh);
                                    }
                                } else {
                                    mon.log(name, "not attempting to activate %s %s because system option "
                                        "\"manage-interfaces\" is False", type, info.desc);
                                }
                            }
                            break;
                        }
                        case "JOB": {
                            # issue #1921: check if job is active before starting thread
                            # issue #2851: support for overriding the "manage-interfaces" option can be added after
                            # persistent option handling is implemented for jobs
                            bool active = Qorus.jobManager.getJobActiveIndication(info.name);
                            if (!active) {
                                if (Qorus.options.get("manage-interfaces")) {
                                    del = False;
                                    background startJob(mon, name, id, info);
                                } else {
                                    mon.log(name, "not attempting to activate %s %s because system option \"manage-interfaces\" is False", type, info.desc);
                                }
                            }
                            break;
                        }
                    }
                } else {
                    list<auto> l = ();
                    map l += doh{type}{id}.$1.keys(), doh{type}{id}.keyIterator();
                    mon.log(name, "cannot reactivate %s due to faulty connections: %y", info.desc, l);
                }
            }
        }
    }

    private delAction(string type, string id, string action, *bool err) {
        Qorus.connection_rwl.writeLock();
        on_exit Qorus.connection_rwl.writeUnlock();

        delActionIntern(type, id, action, err);
    }

    private clearActionIntern(string type, string id, string action) {
        delete ah{type}{id}{action};
        if (!ah{type}{id}) {
            delete ah{type}{id};
            if (!ah{type})
                delete ah{type};
        }
    }

    private delActionIntern(string type, string id, string action, *bool err) {
        clearActionIntern(type, id, action);

        if (err) {
            bool ok = True;
            foreach string mt in (keys oh{type}{id}) {
                ConnectionsServer mon = getConnectionsHandlerFromType(mt);
                foreach string cn in (oh{type}{id}.(mon.getAlertType()).keyIterator()) {
                    #printf("delActionIntern(type: %y, id: %y, action: %y, err: %y): checking monitor %y conn %y (%y)\n", type, id, action, err, mon.getAlertType(), cn, mon.isConnectionUp(cn));

                    if (!mon.isConnectionUp(cn)) {
                        #printf("delActionIntern(): %y: connection is down\n", cn);
                        ok = False;
                        break;
                    }
                }
            }

            #printf("delActionIntern(type: %y, id: %y, action: %y, err: %y): final ok: %y\n", type, id, action, err, ok);

            if (ok)
                ah{type}{id}.CANT{action} = True;
        }
    }

    /*  Get connection handler type by the string type.
        @param type a name of the connection type. One of these values:
                    \c DATASOURCE, \c REMOTE, or \c USER-CONNECTION
        @return particular ConnectionsServer object instance which belongs to the \c type

        See: https://bugs.qoretechnologies.com/projects/qorus/wiki/User_Connections
     */
    private ConnectionsServer getConnectionsHandlerFromType(string type) {
        switch (type) {
            case "DATASOURCE": return Qorus.dsmanager;
            case "REMOTE": return Qorus.remotemonitor;
            case "USER-CONNECTION": return Qorus.connections;
        }
%ifdef QoreDebug
        throw "MONITOR-ERROR", sprintf("unknown monitor type %y", type);
%endif
    }

    private autoStartWorkflow(ConnectionsServer mon, string name, string id, hash<auto> info, hash<auto> wf) {
        string errstr;
        on_exit delAction("WORKFLOW", id, "START", boolean(errstr));

        int num = Qorus.control.getExecInstanceCount(id);
        if (num)
            return;

        try {
            Qorus.rbac.canStartWorkflow(id);
            mon.log(name, "restarting %s due to connection coming online", info.desc);
            string msg = sprintf("restarting %s due to %s connection %y coming online", info.desc, mon.getMonitorType(), name);
            hash h;
            Qorus.control.autoStartWorkflow(NOTHING, wf, \h, msg, \errstr);
            if (!errstr)
                mon.log(name, "restarted %s due to connection coming online", info.desc);
            else
                mon.log(name, "failed to start %s: %s", info.desc, errstr);
        } catch (hash<ExceptionInfo> ex) {
            mon.log(name, "error starting %s: %s: %s", info.desc, ex.err, ex.desc);
            errstr = "1";
        }
    }

    private startService(ConnectionsServer mon, string name, string id, hash info, hash<auto> sh) {
        bool err;
        on_exit delAction("SERVICE", id, "START", err);

        try {
            Qorus.rbac.canStartService(id);
            string str = sprintf("restarting %s due to %s connection %y coming online", info.desc, mon.getMonitorType(), name);
            mon.log(name, "restarting %s due to connection coming online", info.desc);
            services.loadService(info.servicetype, info.name, False, str);
            mon.log(name, "restarted %s due to connection coming online", info.desc);
        } catch (hash<ExceptionInfo> ex) {
            mon.log(name, "error starting %s: %s: %s", info.desc, ex.err, ex.desc);
            err = True;
        }
    }

    private startJob(ConnectionsServer mon, string name, string id, hash<auto> info) {
        bool err;
        on_exit delAction("JOB", id, "START", err);

        if (Qorus.jobManager.jobActive(id))
            return;

        try {
            Qorus.rbac.canStartJob(id);
            mon.log(name, "restarting %s due to connection coming online", info.desc);
            string str = sprintf("restarting %s due to %s connection %y coming online", info.desc, mon.getMonitorType(), name);
            Qorus.jobManager.startJob(info.name, str);
            mon.log(name, "restarted %s due to connection coming online", info.desc);
        } catch (hash<ExceptionInfo> ex) {
            mon.log(name, "error starting %s: %s: %s", info.desc, ex.err, ex.desc);
            err = True;
        }
    }

    # raise_alert - see CONNECTION_RAISE_ALERT and CONNECTION_NO_ALERT
    connectionDown(ConnectionsServer mon, ActionReason reason, string name, bool raise_alert) {
        Qorus.connection_rwl.writeLock();
        on_exit Qorus.connection_rwl.writeUnlock();

        connectionDownIntern(mon, reason, name, raise_alert);
    }

    # called in the write lock
    private connectionDownIntern(ConnectionsServer mon, ActionReason reason, string name, bool raise_alert) {
        if (raise_alert) {
            Qorus.alerts.raiseOngoingAlert(reason, mon.getAlertType(), name, mon.getAlertText(), ("name": name));
        }
        Qorus.events.postConnectionDownEvent(mon.getAlertType(), name, reason.getReason(), mon.getAttributes(name));

        string montype = mon.getAlertType();

        foreach string type in (keys dh{montype}{name}) {
            foreach string id in (keys dh{montype}{name}{type}) {
                # add entry to dormant object hash
                doh{type}{id}{montype}{name} = True;

                hash<auto> info = dh{montype}{name}{type}{id};

                if (ah{type}{id}.STOP) {
                    mon.log(name, "stop already in progress for %s; skipping", info.desc);
                    continue;
                }

                ah{type}{id}.STOP = True;

                bool del = True;
                on_exit
                    if (del) delActionIntern(type, id, "STOP");

                switch (type) {
                    case "WORKFLOW": {
                        *Workflow wf = Qorus.control.tryGetWorkflow(id);
                        if (wf && Qorus.control.getExecInstanceCountIndication(id)) {
                            if (wf.getOption("manage-interfaces")) {
                                del = False;
                                background stopWorkflow(mon, name, id, info);
                            } else {
                                mon.log(name, "not attempting to deactivate %s %s because system option "
                                    "\"manage-interfaces\" is False", type, info.desc);
                            }
                        }
                        break;
                    }
                    case "SERVICE": {
                        # issue #2851: support for overriding the "manage-interfaces" option can be added after
                        # persistent option handling is implemented for services
                        *AbstractQorusCoreService svc = services.getService(info.servicetype, info.name);
                        if (svc) {
                            if (Qorus.options.get("manage-interfaces")) {
                                del = False;
                                background unloadService(mon, name, id, info);
                            } else {
                                mon.log(name, "not attempting to deactivate %s %s because system option "
                                    "\"manage-interfaces\" is False", type, info.desc);
                            }
                        }
                        break;
                    }
                    case "JOB": {
                        # issue #2851: support for overriding the "manage-interfaces" option can be added after
                        # persistent option handling is implemented for jobs
                        bool active = Qorus.jobManager.getJobActiveIndication(info.name);
                        if (active) {
                            if (Qorus.options.get("manage-interfaces")) {
                                del = False;
                                background disableJob(mon, name, id, info);
                            } else {
                                mon.log(name, "not attempting to deactivate %s %s because system option "
                                    "\"manage-interfaces\" is False", type, info.desc);
                            }
                        }
                        break;
                    }
                }
            }
        }
    }

    private stopWorkflow(ConnectionsServer mon, string name, string id, hash<auto> info) {
        on_exit delAction("WORKFLOW", id, "STOP");

        # stop dependent objects
        try {
            string stopmsg = sprintf("stopping %s due to faulty %s connection %y", info.desc, mon.getMonitorType(), name);
            mon.log(name, "stopping %s due to faulty connection", info.desc);
            hash h;
            Qorus.control.pauseWorkflow(info.name, info.version, info.workflowid, stopmsg);
            mon.log(name, "stopped %s due to faulty connection", info.desc);
        } catch (hash<ExceptionInfo> ex) {
            mon.log(name, "error stopping %s: %s: %s", info.desc, ex.err, ex.desc);
        }
    }

    private unloadService(ConnectionsServer mon, string name, string id, hash<auto> info) {
        on_exit delAction("SERVICE", id, "STOP");

        # stop dependent objects
        try {
            string msg = sprintf("unloading %s due to faulty connection %y", info.desc, name);
            mon.log(name, "unloading %s due to fauly connection", info.desc);
            services.unloadService(info.servicetype, info.name, NOTHING, False, msg);
            mon.log(name, "unloaded %s due to faulty connection", info.desc);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "SERVICE-NOT-LOADED") {
                mon.log(name, "service %s already unloaded", info.desc);
            }
            else
                mon.log(name, "error unloading %s: %s: %s", info.desc, ex.err, ex.desc);
        }
    }

    private disableJob(ConnectionsServer mon, string name, string id, hash<auto> info) {
        on_exit delAction("JOB", id, "STOP");

        # stop dependent objects
        try {
            string msg = sprintf("unloading %s due to faulty connection %y", info.desc, name);
            mon.log(name, "stopping %s due to faulty connection", info.desc);
            Qorus.jobManager.stopJobID(id, msg);
            mon.log(name, "stopping %s due to faulty connection %y", info.desc, name);
        } catch (hash<ExceptionInfo> ex) {
            mon.log(name, "error stopping %s: %s: %s", info.desc, ex.err, ex.desc);
        }
    }

    manageDependency(ConnectionsServer mon, AbstractConnection c, *hash<auto> src, bool register_connection, *bool connected, *bool was_connected, *string err, *hash<auto> ex) {
        QDBG_LOG("ConnectionDependencyManager::manageDependency() DEBUG %y %y: %s RC: %y src: %y", mon.getMonitorType(), c.name, c.className(), register_connection, src);

        Qorus.connection_rwl.writeLock();
        on_exit Qorus.connection_rwl.writeUnlock();

        # clear any ongoing alert if connected
        if (exists connected && connected !== was_connected) {
            if (connected) {
                connectionUpIntern(mon, c.name, "remote %s connection %y (%s) url: %y successfully acquired", mon.getMonitorType(), c.name, c.desc, c.safe_url);
            } else {
                ActionReason ar(tld.cx, ex, err);
                connectionDownIntern(mon, ar, c.name, CONNECTION_RAISE_ALERT);
            }
        }

        if (src && register_connection) {
            string montype = mon.getAlertType();

            # now register dependency
            dh{montype}.(c.name).(src.type).(src.id) = src.info;
            oh.(src.type).(src.id){montype}.(c.name) = True;
        }
    }

    manageDependency(ConnectionsServer mon, string name, *hash<auto> src, bool register_connection, *string err, *hash<auto> ex) {
        Qorus.connection_rwl.writeLock();
        on_exit Qorus.connection_rwl.writeUnlock();

        if (src && register_connection) {
            string montype = mon.getAlertType();

            # now register dependency
            dh{montype}{name}.(src.type).(src.id) = src.info;
            oh.(src.type).(src.id){montype}{name} = True;
        }
    }

    checkStatusChange(ConnectionsServer mon, AbstractConnection c, *bool oldok, bool nowok, *string errtxt) {
        bool change = (oldok !== nowok);
        if (nowok) {
            if (change)
                mon.log(c.name, "connection is up", c.name);

            Qorus.connection_rwl.writeLock();
            on_exit Qorus.connection_rwl.writeUnlock();

            string err = sprintf("%s connection %y (%s) url: %y ping successful", mon.getMonitorType(), c.name, c.desc, c.safe_url);
            ActionReason reason(tld.cx, err, True);
            connectionUpIntern(mon, reason, c.name, change);
        } else {
            if (change)
                mon.log(c.name, "connection is down", c.name);
            string err = sprintf("%s connection: ping failed to %y (%s) url: %y", mon.getMonitorType(), c.name, c.desc, c.safe_url);
            ActionReason ar(tld.cx, err + "; " + errtxt, True);
            connectionDown(mon, ar, c.name, CONNECTION_RAISE_ALERT);
        }
    }

    #! manually registers an interface dependency with the given connection
    registerDependency(ConnectionsServer mon, AbstractConnection c) {
        manageDependency(mon, c, qorus_get_source_hash(), True);
    }

    #! manually registers an interface dependency with the given connection
    registerDependency(ConnectionsServer mon, string name, string err, hash<ExceptionInfo> ex) {
        manageDependency(mon, name, qorus_get_source_hash(), True, err, ex);
    }

    # method called internally in qorus-core
    object get(ConnectionsServer mon, string name, bool connect = True, bool register_dependency = True, *hash<auto> rtopts) {
        *hash<auto> src = qorus_get_source_hash();

        AbstractConnection c;
        *bool oldok;
        object obj;

        try {
            c = mon.getConnection(name, \rtopts);
            # the exception is thrown here, not in getConnection because
            # it must be thrown only for user code
            Connections::checkConnectionEnabled(c);

            oldok = c.last_check ? c.up : NOTHING;
            obj = c.get(connect, rtopts);
        } catch (hash<ExceptionInfo> ex) {
            # add dependency and then rethrow
            if (c) {
                string err = sprintf("%s connection monitor: connection could not be acquired to %y (%s) url: %y", mon.getMonitorType(), c.name, c.desc, c.safe_url);
                manageDependency(mon, c, src, register_dependency, False, oldok, err, ex);
            } else {
                string err = sprintf("%s connection monitor: connection could not be acquired to unknown connection %y", mon.getMonitorType(), name);
                manageDependency(mon, name, src, register_dependency, err, ex);
            }
            rethrow;
        }

        manageDependency(mon, c, src, register_dependency, connect ? connect : NOTHING, oldok);

        return obj;
    }

    resetDependentWorkflowsAndServices(ConnectionsServer mon, string name, string why) {
        # get dependent workflow and service ID lists
        list sl = ();
        list wl = ();

        string type = mon.getAlertType();
        {
            ReadLockHelper rlh(Qorus.connection_rwl);

            if (dh{type}{name}) {
                sl += dh{type}{name}.SERVICE.keys();
                wl += dh{type}{name}.WORKFLOW.keys();
            }
        }

        foreach softint svcid in (sl) {
            *hash sh = Qorus.qmm.lookupService(svcid, False);
            try {
                if (!sh) {
                    # can happen if the service was deleted and omqmap refreshed while the service was running
                    mon.log(LoggerLevel::INFO, "cannot reset unknown serviceid %d", svcid);
                    continue;
                }
                services.reloadService(tld.cx, sh.type, sh.name, False, why);
                mon.log(name, "%s: reset %s service %s v%s (%d)", why, sh.type, sh.name, sh.version, svcid);
            } catch (hash<ExceptionInfo> ex) {
                mon.log(name, "%s: failed to reset %s service %s v%s (%d): %s: %s", why, sh.type, sh.name, sh.version, svcid, ex.err, ex.desc);
            }
        }

        foreach softint wfid in (wl) {
            *hash wh = Qorus.qmm.lookupWorkflow(wfid, False);
            try {
                if (!wh) {
                    # can happen if the workflow was deleted and omqmap refreshed while the workflow was running
                    mon.log(LoggerLevel::INFO, "cannot reset unknown workflowid %d", wfid);
                    continue;
                }
                Qorus.control.deleteWorkflowCacheEntry(tld.cx, wfid);
                mon.log(name, "%s: reset workflow %s v%s (%d)", why, wh.name, wh.version, wfid);
            } catch (hash<ExceptionInfo> ex) {
                mon.log(name, "%s: failed to reset workflow %s v%s (%d): %s: %s", why, wh.name, wh.version, wfid, ex.err, ex.desc);
            }
        }
    }
}
