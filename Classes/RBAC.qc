# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus RBAC implementation

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

sub rbaclog(int ll, string fmt) {
    call_function("olog", ll, vsprintf("RBAC: " + fmt, argv));
}

# Workflow/Service Group
class OMQ::Group {
    public {
        # group name
        string name;

        # group description
        string description;

        # group ID
        int id;

        # service hash: key: serviceid
        *hash<string, bool> services;

        # workflow hash: key: workflowid
        *hash<string, bool> workflows;

        # job hash: key: jobid
        *hash<string, bool> jobs;

        # mapper hash: key: mapperid
        *hash<string, bool> mappers;

        # value map hash: key: id
        *hash<string, bool> vmaps;

        # FSM hash: name -> True
        *hash<string, bool> fsms;

        # pipeline hash: name -> True
        *hash<string, bool> pipelines;

        # enabled flag
        bool enabled;

        # number of members
        int size;
    }

    constructor(string name, softstring description = "", softint id, softbool enabled, *hash<string, bool> workflows,
            *hash<string, bool> services, *hash<string, bool> jobs, *hash<string, bool> mappers,
            *hash<string, bool> vmaps, *hash<string, bool> fsms, *hash<string, bool> pipelines) {
        self.name = name;
        self.description = description;
        self.id = id;
        self.enabled = enabled;
        self.workflows = workflows;
        self.services = services;
        self.jobs = jobs;
        self.mappers = mappers;
        self.vmaps = vmaps;
        self.fsms = fsms;
        self.pipelines = pipelines;
        updateSize();
    }

    softstring getId() {
        return id < 0 ? "synthetic" : id;
    }

    # add interface diffs between old and new groups
    addInterfaceDiff(reference<hash<string, hash<string, bool>>> ah, *hash oservices, *hash ojobs, *hash oworkflows, bool svc, bool job, bool wf) {
        if (svc) {
            # add IDs not present in the new group
            map ah{AtomicClassActionHelper::C_Service}{$1} = True, keys services, !oservices.$1;
            # add IDs not present in the old group
            map ah{AtomicClassActionHelper::C_Service}{$1} = True, keys oservices, !services.$1;
        }
        if (job) {
            # add IDs not present in the new group
            map ah{AtomicClassActionHelper::C_Job}{$1} = True, keys jobs, !ojobs.$1;
            # add IDs not present in the old group
            map ah{AtomicClassActionHelper::C_Job}{$1} = True, keys ojobs, !jobs.$1;
        }
        if (wf) {
            # add IDs not present in the new group
            map ah{AtomicClassActionHelper::C_Workflow}{$1} = True, keys workflows, !oworkflows.$1;
            # add IDs not present in the old group
            map ah{AtomicClassActionHelper::C_Workflow}{$1} = True, keys oworkflows, !workflows.$1;
        }
    }

    *hash<string, hash<string, bool>> getAllInterfacesForAtomicAction() {
        hash<string, hash<string, bool>> ah;
        map ah{AtomicClassActionHelper::C_Service}{$1} = True, keys services;
        map ah{AtomicClassActionHelper::C_Job}{$1} = True, keys jobs;
        map ah{AtomicClassActionHelper::C_Workflow}{$1} = True, keys workflows;
        return ah;
    }

    raiseDisabledAlert(ActionReason r) {
        # do not raise an ongoing alert for synthetic groups
        if (!isSynthetic()) {
            list smap;
            map smap += ("type": "WORKFLOW", "id": $1.toInt()), keys workflows;
            map smap += ("type": "SERVICE", "id": $1.toInt()), keys services;
            map smap += ("type": "JOB", "id": $1.toInt()), keys jobs;
            Qorus.alerts.raiseOngoingAlert(r, "GROUP", id, "INTERFACE-GROUP-DISABLED", self.("name", "id"), smap);
        }
    }

    clearAlert(ActionReason r) {
        # ongoing alerts are not raised for synthetic groups
        if (!isSynthetic()) {
            Qorus.alerts.clearAllOngoingAlerts(r, "GROUP", id);
        }
    }

    static list<hash<QorusServiceInfo>> getServiceInfoList(*hash<auto> h) {
        list<hash<QorusServiceInfo>> rv = ();

        foreach softint id in (keys h) {
            *hash<auto> svc = Qorus.qmm.lookupService(id, False);
            if (svc) {
                rv += <QorusServiceInfo>{
                    "serviceid": id,
                    "type": svc.type,
                    "name": svc.name,
                    "version": svc.version,
                    "autostart": svc.autostart,
                };
            }
        }
        return rv;
    }

    static list<hash<QorusWorkflowInfo>> getWorkflowInfoList(*hash<auto> h) {
        list<hash<QorusWorkflowInfo>> rv = ();

        foreach softint id in (keys h) {
            *hash<auto> wf = Qorus.qmm.lookupWorkflow(id);
            if (wf) {
                rv += <QorusWorkflowInfo>{
                    "workflowid": id,
                    "name": wf.name,
                    "version": wf.version,
                };
            }
        }

        return rv;
    }

    static list<hash<QorusJobInfo>> getJobInfoList(*hash<auto> h) {
        list<hash<QorusJobInfo>> rv = ();

        foreach softint id in (keys h) {
            *hash<auto> j = Qorus.qmm.lookupJob(id, False);
            if (j) {
                rv += <QorusJobInfo>{
                    "jobid": id,
                    "name": j.name,
                    "version": j.version,
                };
            }
        }

        return rv;
    }

    static list<hash<QorusMapperInfo>> getMapperInfoList(*hash<auto> h) {
        list<hash<QorusMapperInfo>> rv = ();

        foreach softint id in (keys h) {
            *hash<auto> ih = Qorus.qmm.lookupMapper(id, False);
            if (ih) {
                rv += <QorusMapperInfo>{
                    "mapperid": id,
                    "name": ih.name,
                    "version": ih.version,
                    "type": ih.type,
                };
            }
        }

        return rv;
    }

    static list<hash<QorusVMapInfo>> getVMapInfoList(*hash<auto> h) {
        list<hash<QorusVMapInfo>> rv = ();

        foreach softint id in (keys h) {
            *hash<auto> ih = Qorus.qmm.lookupVMap(id, False);
            if (ih) {
                rv += <QorusVMapInfo>{
                    "id": id,
                    "name": ih.name,
                };
            }
        }

        return rv;
    }

    static softlist<hash<QorusFsmInfo>> getFsmInfoList(*hash<auto> h) {
        return map <QorusFsmInfo>{"name": $1}, keys h, exists Qorus.qmm.lookupFsm($1, False);
    }

    static softlist<hash<QorusPipelineInfo>> getPipelineInfoList(*hash<auto> h) {
        return map <QorusPipelineInfo>{"name": $1}, keys h, exists Qorus.qmm.lookupPipeline($1);
    }

    hash<auto> getInfo() {
        hash<auto> h = self.("name", "description", "id", "enabled", "size");
        h.is_default = boolean(!id);

        if (name == DefaultGroupName) {
            h += {
                "services" : (),
                "workflows": (),
                "jobs"     : (),
                "mappers"  : (),
                "vmaps"    : (),
                "fsms"     : (),
                "pipelines": (),
            };
        } else {
            # enhance services list with service info
            h.services = Group::getServiceInfoList(services);

            # enhance workflows list with workflow info
            h.workflows = Group::getWorkflowInfoList(workflows);

            # enhance jobs list with job info
            h.jobs = Group::getJobInfoList(jobs);

            # enhance mappers list with mapper info
            h.mappers = Group::getMapperInfoList(mappers);

            # enhance vmaps list with value map info
            h.vmaps = Group::getVMapInfoList(vmaps);

            # enhance FSM list with FSM info
            h.fsms = Group::getFsmInfoList(fsms);

            # enhance pipeline list with pipeline info
            h.pipelines = Group::getPipelineInfoList(pipelines);
        }

        if (id < 0)
            h.synthetic = True;

        # for compatibility with the UI
        h.roles = ();

        return h;
    }

    updateSize() {
        size = workflows.size() + jobs.size() + services.size() + mappers.size() + vmaps.size() + fsms.size() + pipelines.size();
    }

    bool isSynthetic() {
        return id < 0;
    }

    *hash getSyntheticInfo() {
        if (id >= 0)
            return;

        string type;
        softint id;
        if (workflows) {
            type = "workflow";
            id = workflows.firstKey();
        } else if (services) {
            type = "service";
            id = services.firstKey();
        } else if (jobs) {
            type = "job";
            id = jobs.firstKey();
        }

        return {
            "synthetic": True,
            "type": type,
            "id": id,
        };
    }
}

class OMQ::AutostartHelper inherits Mutex {
}

class OMQ::RBAC inherits AbstractAuthenticator {
    private {
        # to manage concurrent access to RBAC information
        RWLock rwl();

        # group info: goup name -> Group
        *hash<string, Group> groups;

        # group id hash map: key=id, value=name
        hash<string, string> gmap;

        # map of workflow IDs to groups, key=workflow id, value=hash of group names
        hash<string, hash<string, bool>> wmap;

        # map of service IDs to groups, key=service id, value=hash of group names
        hash<string, hash<string, bool>> smap;

        # map of job IDs to groups, key=job id, value=hash of group names
        hash<string, hash<string, bool>> jmap;

        # map of mapper IDs to groups, key=mapper id, value=hash of group names
        hash<string, hash<string, bool>> mmap;

        # map of value map IDs to groups, key=value map id, value=hash of group names
        hash<string, hash<string, bool>> vmap;

        # map FSM name -> hash of group names
        hash<string, hash<string, bool>> fsmmap;

        # maps pipeline name -> group name -> True
        hash<string, hash<string, bool>> pipemap;

        # synthetic group map: (workflow|service|job).id -> group name
        hash sgmap;

        # initialization flag
        bool init_done = False;

        # date/time loaded
        date loaded;
    }

    public {
        const SystemUserDetails = {
            "provider": "db",
            "username": "system",
            "name": "Internal System User",
            "has_default": True,
            "roles": (
                "superuser",
            ),
            # for the UI
            "permissions": (
                "LOGIN",
                "SHUTDOWN",
                "WORKFLOW-CONTROL",
                "SERVICE-CONTROL",
                "JOB-CONTROL",
                "OPTION-CONTROL",
                "LOGGER-CONTROL",
                "DATASOURCE-CONTROL",
                "SERVER-CONTROL",
                "USER-CONNECTION-CONTROL",
                "SERVER-CONNECTION-CONTROL",
                "FILESYSTEM-CONTROL",
                "MAPPER-CONTROL",
                "VALUE-MAP-CONTROL",
                "SLA-CONTROL",
                "DEBUG-CONTROL",
                "DATA-PROVIDER-CONTROL",
                "TYPE-CACHE-CONTROL",
                "WEBDAV-CONTROL",
                "CREATOR-CONTROL",
            ),
            "workflows": (),
            "jobs": (),
            "services": (),
            "mappers": (),
            "vmaps": (),
            "fsms": (),
            "pipelines": (),
            "groups": (
                "DEFAULT",
            ),
            "storage": {},
        };
    }

    constructor() {
        AtomicClassActionHelper::setLock(rwl);
    }

    init() {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        reloadIntern(False);
    }

    bool initialized() {
        return init_done;
    }

    reload() {
        # fix for bug 558: do not allow a group update or reload operation before all services have been initialized
        services.waitInit();

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        reloadIntern();
    }

    private reloadIntern(bool enforce_changes = True) {
        # set date/time loaded
        loaded = now_us();

        # hash of group info
        hash<string, Group> groups();

        # group id hash map: key=id, value=name
        hash<string, string> gmap();

        # map of workflow IDs to groups, key=workflow id, value=list of group names
        hash<string, hash<string, bool>> wmap = {};

        # map of service IDs to groups, key=service id, value=list of group names
        hash<string, hash<string, bool>> smap = {};

        # map of job IDs to groups, key=job id, value=list of group names
        hash<string, hash<string, bool>> jmap = {};

        # map of mapper IDs to groups, key=mapper id, value=list of group names
        hash<string, hash<string, bool>> mmap = {};

        # map of value map IDs to groups, key=value map id, value=list of group names
        hash<string, hash<string, bool>> vmap = {};

        # maps FSM name -> group name -> True
        hash<string, hash<string, bool>> fsmmap = {};

        # maps pipeline name -> group name -> True
        hash<string, hash<string, bool>> pipemap = {};

        # get information from the DB
        hash<auto> q;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                q = sqlif.rbacLoad();
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # create groups
        context (q.groups) {
            groups.%name = new Group(%name, %description, %groupid, %enabled);
            gmap.%groupid = %name;
        }

        context (q.group_services) {
            *string name = gmap.%groupid;
            if (!name) {
                # new group created since we loaded the groups
                continue;
            }

            # add to Group service list
            Group g = groups{name};
            g.services.%serviceid = True;
            ++g.size;

            # add to service lookup map
            smap.%serviceid{name} = True;
        }

        context (q.group_workflows) {
            *string name = gmap.%groupid;
            if (!name) {
                # new group created since we loaded the groups
                continue;
            }

            # add to Group workflow list
            Group g = groups{name};
            g.workflows.%workflowid = True;
            ++g.size;

            # add to workflow lookup map
            wmap.%workflowid{name} = True;
        }

        context (q.group_jobs) {
            *string name = gmap.%groupid;
            if (!name) {
                # new group created since we loaded the groups
                continue;
            }

            # add to Group job list
            Group g = groups{name};
            g.jobs.%jobid = True;
            ++g.size;

            # add to job lookup map
            jmap.%jobid{name} = True;
        }

        context (q.group_mappers) {
            *string name = gmap.%groupid;
            if (!name) {
                # new group created since we loaded the groups
                continue;
            }

            # add to Group mapper list
            Group g = groups{name};
            g.mappers.%mapperid = True;
            ++g.size;

            # add to mapper lookup map
            mmap.%mapperid{name} = True;
        }

        context (q.group_vmaps) {
            *string name = gmap.%groupid;
            if (!name) {
                # new group created since we loaded the groups
                continue;
            }

            # add to Group mapper list
            Group g = groups{name};
            g.vmaps.%id = True;
            ++g.size;

            # add to mapper lookup map
            vmap.%id{name} = True;
        }

        context (q.group_fsms) {
            *string name = gmap.%groupid;
            if (!name) {
                # new group created since we loaded the groups
                continue;
            }

            # add to Group FSM list
            Group g = groups{name};
            g.fsms.%fsm = True;
            ++g.size;

            # add to FSM lookup map
            fsmmap.%fsm{name} = True;
        }

        context (q.group_pipelines) {
            *string name = gmap.%groupid;
            if (!name) {
                # new group created since we loaded the groups
                continue;
            }

            # add to Group FSM list
            Group g = groups{name};
            g.pipelines.%pipeline = True;
            ++g.size;

            # add to FSM lookup map
            pipemap.%pipeline{name} = True;
        }

        # make a copy of current group info if enforcing changes
        *hash<string, Group> og;
        if (enforce_changes) {
            og = self.groups;
        }

        # if we got to here without an exception then the reload succeeded successfully

        # copy local variables to object in one atomic operation
        self += {
            "groups"          : groups,
            "gmap"            : gmap,
            "wmap"            : wmap,
            "smap"            : smap,
            "jmap"            : jmap,
            "mmap"            : mmap,
            "vmap"            : vmap,
            "fsmmap"          : fsmmap,
            "pipemap"         : pipemap,
        };

        # raise or clear alerts for groups
        if (!enforce_changes) {
            foreach Group g in (groups.iterator()) {
                if (g.enabled) {
                    ActionReason r(tld.cx, sprintf("group %s (%s) enabled in the DB " + (enforce_changes ? "on RBAC reload" : "at system startup"), g.name, g.getId()));
                    g.clearAlert(r);
                } else {
                    ActionReason r(tld.cx, "\"enabled\" flag for interface group \"" + g.name + "\" set to false in the DB " + (enforce_changes ? "on RBAC reload" : "at system startup"));
                    g.raiseDisabledAlert(r);
                }
            }
        } else {
            createDedicatedGroupsIntern();
            enforceGroupChanges(og);
        }
    }

    # @param og old group hash
    private enforceGroupChanges(*hash<string, Group> og, bool wf = True, bool svc = True, bool job = True) {
        # fix for bug 560: make a hash of group status info from before the reset and compare to after the reset
        #                  and only execute the delta
        # make a hash of Group statuses to compare afer the load; name -> enabled status
        hash<string, bool> group_status_hash;
        # hash of service IDs in disabled groups; in case they are removed from the group, they will be restarted
        hash<string, Group> dis_svc;
        # hash of job IDs in disabled groups; in case they are removed from the group, they will be restarted
        hash<string, Group> dis_job;
        # hash of workflow IDs in disabled groups; in case they are removed from the group, they will be restarted
        hash<string, Group> dis_wf;

        # hash of affected interaces for atomicity
        hash<string, hash<string, bool>> ah;

        # process interfaces in new groups
        foreach Group g in (og.iterator()) {
            {
                bool scan = True;
                *Group new_group = groups{g.name};
                # add to atomic interface change maps
                if (new_group.enabled) {
                    # if the group is now enabled and was already enabled, then ignore
                    if (g.enabled) {
                        scan = False;
                    }
                } else if (exists new_group && !g.enabled) {
                    # otherwise if the group existed and is now disabled and was disabled before, only add differences
                    g.addInterfaceDiff(\ah, svc ? new_group.services : NOTHING, job ? new_group.jobs : NOTHING, wf ? new_group.workflows : NOTHING, svc, job, wf);
                    scan = False;
                }
                if (scan) {
                    # otherwise add the union of all relevant interfaces
                    if (svc) {
                        map ah{AtomicClassActionHelper::C_Service}{$1} = True, keys g.services;
                        map ah{AtomicClassActionHelper::C_Service}{$1} = True, keys new_group.services;
                    }
                    if (job) {
                        map ah{AtomicClassActionHelper::C_Job}{$1} = True, keys g.jobs;
                        map ah{AtomicClassActionHelper::C_Job}{$1} = True, keys new_group.jobs;
                    }
                    if (wf) {
                        map ah{AtomicClassActionHelper::C_Workflow}{$1} = True, keys g.workflows;
                        map ah{AtomicClassActionHelper::C_Workflow}{$1} = True, keys new_group.workflows;
                    }
                }
            }

            group_status_hash.(g.name) = g.enabled;
            if (g.enabled) {
                continue;
            }

            # create maps for interfaces from their IDs to formerly disabled groups
            # regardless of the status of the new group
            if (svc) {
                map dis_svc{$1} = g, keys g.services, !dis_svc{$1};
            }
            if (job) {
                map dis_job{$1} = g, keys g.jobs, !dis_job{$1};
            }
            if (wf) {
                map dis_wf{$1} = g, keys g.workflows, !dis_wf{$1};
            }
        }

        # process interfaces in existing groups

        # ensures that enable/disable actions for interfaces are performed automatically
        AtomicMultiClassActionHelper atomic_action_helper(ah);

        # perform delta operations on groups
        foreach string name in (keys groups) {
            Group g = groups{name};
            if (g.enabled) {
                # bug 560: if the group is now enabled and was already enabled before or did not exist before, then
                # skip
                if (group_status_hash.(g.name) || !exists group_status_hash.(g.name)) {
                    continue;
                }
                rbaclog(LoggerLevel::INFO, "group %y was disabled and is now enabled; attempting to start workflows, "
                    "jobs, and services", name);

                # enable group autostart counter
                Counter ec();

                # start any services that have their autostart flag and
                # are not in any other disabled groups
                if (svc && g.services) {
                    ec.inc();
                    atomic_action_helper.doBackgroundServices(keys g.services, \autoStartServices(), tld.cx,
                        "refresh services in enabled", g, g.services, atomic_action_helper, ec);
                }

                # start any active jobs that are not in any other disabled groups
                if (job && g.jobs) {
                    ec.inc();
                    atomic_action_helper.doBackgroundJobs(keys g.jobs, \startJobs(), tld.cx, "refresh jobs in "
                        "enabled", g, g.jobs, atomic_action_helper, ec);
                }

                # start any workflows that have their autostart flag set and
                # are not in any other disabled groups
                if (wf && g.workflows) {
                    ec.inc();
                    atomic_action_helper.doBackgroundWorkflows(keys g.workflows, \autoStartWorkflows(), tld.cx,
                        "refresh workflows in enabled", g, g.workflows, atomic_action_helper, ec);
                }

                # wait for autostart to complete then remove ongoing alert
                background waitForAutostart(tld.cx, g, ec);

                continue;
            }
            # bug 560: if the group existed and was already disabled before, then there is no action to take
            if (exists group_status_hash.(g.name) && !group_status_hash.(g.name)) {
                continue;
            }
            rbaclog(LoggerLevel::INFO, "group %y was enabled and is now disabled; stopping all workflows, jobs, and "
                "services", name);

            ActionReason r(tld.cx, "RBAC refresh with disabled group");
            g.raiseDisabledAlert(r);

            if (wf && g.workflows) {
                atomic_action_helper.doBackgroundWorkflows(keys g.workflows, \stopWorkflows(),
                    "refresh with disabled", g, g.workflows, atomic_action_helper);
            }
            # fix for bug 842: do not unload services with the RBAC write lock held
            if (svc && g.services) {
                atomic_action_helper.doBackgroundServices(keys g.services, \stopServices(), "refresh with disabled",
                    g, g.services, atomic_action_helper);
            }
            if (job && g.jobs) {
                atomic_action_helper.doBackgroundJobs(keys g.jobs, \stopJobs(), "refresh with disabled", g, g.jobs,
                    atomic_action_helper);
            }
        }

        # get list of formerly disabled services that are no longer in any list
        foreach string id in (keys dis_svc) {
            if (!smap{id}) {
                atomic_action_helper.doBackgroundService(id, \autoStartServices(), tld.cx,
                    "refresh services in formerly disabled", dis_svc{id}, {id: True}, atomic_action_helper);
            }
        }

        # get list of formerly disabled jobs that are no longer in any list
        foreach string id in (keys dis_job) {
            if (!jmap{id}) {
                atomic_action_helper.doBackgroundJob(id, \startJobs(), tld.cx, "refresh jobs in formerly disabled",
                    dis_job{id}, {id: True}, atomic_action_helper);
            }
        }

        # get list of formerly disabled workflows that are no longer in any list
        foreach string id in (keys dis_wf) {
            if (!wmap{id}) {
                atomic_action_helper.doBackgroundWorkflow(id, \autoStartWorkflows(), tld.cx,
                    "refresh workflows in formerly disabled", dis_wf{id}, {id: True}, atomic_action_helper);
            }
        }
    }

    rescanMetadata(bool wf = False, bool svc = False, bool job = False) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        # make a copy of current group info to enforce changes
        *hash<string, Group> og = groups;

        foreach Group g in (groups.iterator()) {
            # only consider synthetic groups
            if (g.id > 0)
                continue;

            # delete group if it matches the criteria
            if ((wf && g.workflows) || (svc && g.services) || (job && g.jobs)) {
                deleteGroupIntern(g);
            }
        }

        createDedicatedGroupsIntern(wf, svc, job);
        enforceGroupChanges(og, wf, svc, job);
    }

    rescanWorkflowsDelta(list<auto> wfids) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        # make a copy of current group info to enforce changes
        *hash<string, Group> og = groups;

        foreach Group g in (groups.iterator()) {
            # only consider synthetic groups
            if (g.id > 0)
                continue;

            # delete synthetic group if it matches any of the affected workflows
            if (g.workflows{wfids})
                deleteGroupIntern(g);
        }

        createDedicatedGroupsIntern(True, False, False);
        enforceGroupChanges(og, True, False, False);
    }

    rescanServicesDelta(list<auto> svcids) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        # make a copy of current group info to enforce changes
        *hash<string, Group> og = groups;

        foreach Group g in (groups.iterator()) {
            # only consider synthetic groups
            if (g.id > 0)
                continue;

            # delete synthetic group if it matches any of the affected services
            if (g.services{svcids}) {
                #rbaclog(LoggerLevel::INFO, "rescanServicesDelta() deleting group: %N", g);
                deleteGroupIntern(g);
            }
        }

        createDedicatedGroupsIntern(False, True, False);
        #rbaclog(LoggerLevel::INFO, "rescanServicesDelta() og: %N", og);
        enforceGroupChanges(og, False, True, False);
    }

    rescanJobsDelta(list<auto> jobids) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        # make a copy of current group info to enforce changes
        *hash<string, Group> og = groups;

        foreach Group g in (groups.iterator()) {
            # only consider synthetic groups
            if (g.id > 0)
                continue;

            # delete synthetic group if it matches any of the affected jobs
            if (g.jobs{jobids})
                deleteGroupIntern(g);
        }

        createDedicatedGroupsIntern(False, False, True);
        enforceGroupChanges(og, False, False, True);
    }

    createDedicatedGroups() {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        createDedicatedGroupsIntern();

        if (!init_done)
            init_done = True;
    }

    createDedicatedGroupsIntern(bool wf = True, bool svc = True, bool job = True) {
        code get_name = *string sub (string name, string version, *softint id, string key) {
            code check = bool sub () {
                return (groups{name} && (groups{name}.id < 0)
                    && (groups{name}{key}.size() == 1)
                    && groups{name}{key}{id});
            };
            if (check())
                return;
            if (!groups{name})
                return name;

            name += " v" + version;
            if (check())
                return;
            if (!groups{name})
                return name;

            name += sprintf(" (%d)", id);
            if (check())
                return;
            if (!groups{name})
                return name;

            name += " (DEDICATED)";
            if (check())
                return;
            if (!groups{name})
                return name;

            string base = name + " ";
            int i = 0;
            while (True) {
                name = sprintf("%s%d", base, ++i);
                if (check())
                    return;
                if (!groups{name})
                    return name;
            }
        };

        # synthetic group IDs will always be negative (they start with -1)
        int fakeid = 0;
        code get_group = Group sub (string name, string iftype, softint id, bool enabled) {
            sgmap{iftype}{id} = name;
            return new Group(name, sprintf("synthetic group created to manage the single %s member", iftype),
                --fakeid, enabled);
        };

        # create fake groups for each workflow without a dedicated group
        if (wf) {
            *hash<auto> owfmap = Qorus.qmm.getWorkflowMap();

            foreach hash<auto> wfh in (owfmap.iterator()) {
                *string name = get_name(wfh.name, wfh.version, wfh.workflowid, "workflows");
                if (name) {
                    Group g = get_group(name, "workflow", wfh.workflowid, wfh.enabled);
                    groups{name} = g;
                    gmap.(g.id) = name;

                    # add workflow to group
                    g.workflows.(wfh.workflowid) = True;
                    g.updateSize();

                    # add to workflow lookup map
                    wmap.(wfh.workflowid){name} = True;
                }
            }
        }

        # create fake groups for each service without a dedicated group
        if (svc) {
            *hash<auto> oservicemap = Qorus.qmm.getServiceMap(False);

            foreach hash<auto> sh in (oservicemap.iterator()) {
                *string name = get_name(sh.name, sh.version, sh.serviceid, "services");
                if (name) {
                    Group g = get_group(name, "service", sh.serviceid, sh.enabled);
                    groups{name} = g;
                    gmap.(g.id) = name;

                    # add service to group
                    g.services.(sh.serviceid) = True;
                    g.updateSize();

                    # add to service lookup map
                    smap.(sh.serviceid){name} = True;
                }
            }
        }

        # create fake groups for each job without a dedicated group
        if (job) {
            *hash<auto> ojmap = Qorus.qmm.getJobMap(False);

            foreach hash<auto> jh in (ojmap.iterator()) {
                *string name = get_name(jh.name, jh.version, jh.jobid, "jobs");
                if (name) {
                    Group g = get_group(name, "job", jh.jobid, jh.enabled);
                    groups{name} = g;
                    gmap.(g.id) = name;

                    # add job to group
                    g.jobs.(jh.jobid) = True;
                    g.updateSize();

                    # add to service lookup map
                    jmap.(jh.jobid){name} = True;
                }
            }
        }
    }

    resetJobGroups(softstring jobid, *list<auto> groups) {
        *hash<string, bool> gmap = map {$1: True}, groups;

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        # remove groups where no change has been made and make list of groups where the job remains
        list<string> remain = ();
        map (remove gmap{$1}, remain += $1), groups, jmap{jobid}{$1};

        QDBG_LOG("resetJobGroups() jobid: %y groups: %y remain: %y (all: %y)", jobid, groups, remain, keys jmap{jobid});

        # then remove the job from all old groups that are not remaining (except the synthetic group);
        # get list of groups where the job is removed
        list<int> rmv;
        map (
            remove self.groups{$1}.jobs{jobid},
            remove jmap{jobid}{$1},
            rmv += self.groups{$1}.id
        ),
            keys (jmap{jobid} - remain),
            !self.groups{$1}.isSynthetic();

        # then add the job to new groups; get list of groups where the job is added
        list<int> add;
        map ((jmap{jobid}{$1} = self.groups{$1}.jobs{jobid} = True), add += self.groups{$1}.id), keys gmap;

        # update DB
        int id = jobid.toInt();
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                map sqlif.deleteJobsFromGroup($1, id), rmv;
                map sqlif.addJobsToGroup($1, id), add;
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

%ifdef QorusDebugInternals
        QDBG_LOG("RBAC::resetJobGroups() jobid %y groups: %y (remain: %y)", id, groups, remain);
        QDBG_LOG("RBAC::resetJobGroups() removed jobid %y from the following groups: %y -> %y", id, rmv, (map self.gmap{$1}, rmv));
        QDBG_LOG("RBAC::resetJobGroups() added jobid %y to the following groups: %y -> %y", id, add, (map self.gmap{$1}, add));
%endif
    }

    string getRealm() {
        return "Qorus Integration Engine";
    }

    hash<auto> getInfo() {
        return {
            "loaded": loaded,
            "groups": groups.size(),
        };
    }

    static list<hash<auto>> checkWorkflows(string action, string arg, reference<*hash<string, bool>> wfs,
            *hash<auto> current_wfs, bool newv = False) {
        list<hash<auto>> cmds();

        if (!exists wfs) {
            wfs = current_wfs;
            return cmds;
        }
        bool delta = wfs ? inlist(wfs.firstKey()[0], ("+","-")) : False;
        if (!delta || !current_wfs) {
            current_wfs = new hash<string, bool>();
        }

        # check workflow
        code check = int sub (string wf) {
            # if the argument is an ID, then verify that it's valid
            if (wf == int(wf)) {
                if (!Qorus.qmm.lookupWorkflow(wf))
                    throw "WORKFLOW-ERROR", sprintf("workflowid %d is not valid", wf);
                return int(wf);
            }

            return Qorus.qmm.getWorkflowId(wf);
        };

        # add a delta workflow to a group (assumes check already made that the workflow is not in the current_wfs
        # list)
        code add_delta = sub (int wfid) {
            # add the new wf to the list
            current_wfs{wfid} = True;
            cmds += {
                "action": "add",
                "arg": wfid,
            };
        };

        # delete a delta workflow from a group (assumes check already made that the workflow is in the current_wfs
        # list)
        code del_delta = sub (int wfid) {
            remove current_wfs{wfid};
            cmds += {
                "action": "del",
                "arg": wfid,
            };
        };

        foreach string wf in (keys wfs) {
            if (delta) {
                if (!inlist(wf[0], ("+","-")))
                    throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; first workflow "
                        "is a delta (change) workflow command, but non-delta workflow found in position %d: %y",
                        action, arg, $#, wf);

                # remove delta character
                string dc = extract wf, 0, 1;

                if (dc == "+") {
                    if (wf == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (wfs.size() != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; add all "
                                "workflows command (+*) found, but is not the only entry in the workflow list: %y",
                                action, arg, wfs.keys());

                        foreach int wfid in (Qorus.qmm.getWorkflowIds()) {
                            if (!current_wfs{wfid})
                                add_delta(wfid);
                        }
                        break;
                    }

                    int wfid = check(wf);
                    if (current_wfs{wfid}) {
                        # skip workflows the group already has
                        continue;
                    }

                    # add the new workflow to the list
                    add_delta(wfid);
                } else {
                    if (newv)
                        throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                            "workflow command '-%s' found in new workflow list", action, arg, wf);

                    if (wf == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (wfs.size() != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                                "all workflows command (-*) found, but is not the only entry in the workflow "
                                "list: %y", action, arg, keys wfs);

                        foreach softint wfid in (keys current_wfs) {
                            del_delta(wfid);
                        }
                        break;
                    }

                    int wfid = check(wf);
                    if (!current_wfs{wfid}) {
                        # skip workflows the group does not have anyway
                        continue;
                    }

                    # remove the workflow from the list
                    del_delta(wfid);
                }
            } else {
                int wfid = check(wf);
                cmds += {
                    "action": "add",
                    "arg": wfid,
                };
                current_wfs{wfid} = True;
            }
        }

        wfs = current_wfs;

        if (!delta && !newv) {
            # if we are replacing the workflow list, delete the list first
            splice cmds, 0, 0, {
                "action": "delete-all",
            };
        }

        QDBG_LOG("RBAC: %s group %y: wfs: %y cmds: %y", action, arg, wfs, cmds);
        return cmds;
    }

    static list<hash<auto>> checkServices(string action, string arg, reference<*hash<string, bool>> svcs,
            *hash<auto> current_svcs, bool newv = False) {
        list<hash<auto>> cmds();

        if (!exists svcs) {
            svcs = current_svcs;
            return cmds;
        }
        bool delta = svcs ? inlist(svcs.firstKey()[0], ("+","-")) : False;
        if (!delta || !current_svcs) {
            current_svcs = new hash<string, bool>();
        }

        # check service
        code check = int sub (string svc) {
            # if the argument is an ID, then verify that it's valid
            if (svc == int(svc)) {
                if (!Qorus.qmm.lookupService(svc, False))
                    throw "SERVICE-ERROR", sprintf("serviceid %d is not valid", svc);
                return int(svc);
            }
            return Qorus.qmm.getServiceId("USER", svc);
        };

        # add a service to a group (assumes check already made that the service is not in the current_svcs list)
        code add_delta = sub (int svcid) {
            # add the new svc to the list
            current_svcs{svcid} = True;
            cmds += {
                "action": "add",
                "arg": svcid,
            };
        };

        # delete a service from a group (assumes check already made that the service is in the current_svcs list)
        code del_delta = sub (int svcid) {
            remove current_svcs{svcid};
            cmds += {
                "action": "del",
                "arg": svcid,
            };
        };

        foreach string svc in (keys svcs) {
            trim svc;

            if (delta) {
                if (!inlist(svc[0], ("+","-")))
                    throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; first service "
                        "is a delta (change) service command, but non-delta service found in position %d: %y",
                        action, arg, $#, svc);

                # remove delta character
                string dc = extract svc, 0, 1;
                if (dc == "+") {
                    if (svc == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (svcs.size() != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; add all "
                                "services command (+*) found, but is not the only entry in the service list: %y",
                                action, arg, svcs.keys());

                        foreach int svcid in (Qorus.qmm.getUserServiceIds()) {
                            if (!current_svcs{svcid})
                                add_delta(svcid);
                        }
                        break;
                    }

                    int svcid = check(svc);
                    if (current_svcs{svcid}) {
                        # skip services the group already has
                        continue;
                    }

                    # add the new service to the list
                    add_delta(svcid);
                } else {
                    if (newv)
                        throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                            "service command '-%s' found in new service list", action, arg, svc);

                    if (svc == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (svcs.size() != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                                "all services command (-*) found, but is not the only entry in the service list: %y",
                                action, arg, svcs.keys());

                        foreach softint svcid in (keys current_svcs) {
                            del_delta(svcid);
                        }
                        break;
                    }

                    int svcid = check(svc);
                    if (!current_svcs{svcid}) {
                        # skip services the group does not have anyway
                        continue;
                    }

                    # remove the service from the list
                    del_delta(svcid);
                }
            } else {
                int svcid = check(svc);
                cmds += {
                    "action": "add",
                    "arg": svcid,
                };
                current_svcs{svcid} = True;
            }
        }

        svcs = current_svcs;

        if (!delta && !newv) {
            # if we are replacing the service list, delete the list first
            splice cmds, 0, 0, {
                "action": "delete-all",
            };
        }

        QDBG_LOG("RBAC: %s group %y: svcs: %y cmds: %y", action, arg, svcs, cmds);
        return cmds;
    }

    static list<hash<auto>> checkJobs(string action, string arg, reference<*hash<string, bool>> jobs,
            *hash<auto> current_jobs, bool newv = False) {
        list<hash<auto>> cmds();

        if (!exists jobs) {
            jobs = current_jobs;
            return cmds;
        }
        bool delta = jobs ? inlist(jobs.firstKey()[0], ("+","-")) : False;
        if (!delta || !current_jobs) {
            current_jobs = new hash<string, bool>();
        }

        # check job
        code check = int sub (string job) {
            # if the argument is an ID, then verify that it's valid
            if (job == int(job)) {
                if (!Qorus.qmm.lookupJob(job, False))
                    throw "JOB-ERROR", sprintf("jobid %d is not valid", job);
                return int(job);
            }
            return Qorus.qmm.getJobId(job);
        };

        # add a delta job to a group (assumes check already made that the job is not in the current_jobs list)
        code add_delta = sub (int jobid) {
            # add the new job to the list
            current_jobs{jobid} = True;
            cmds += {
                "action": "add",
                "arg": jobid,
            };
        };

        # delete a delta job from a group (assumes check already made that the job is in the current_jobs list)
        code del_delta = sub (int jobid) {
            remove current_jobs{jobid};
            cmds += {
                "action": "del",
                "arg": jobid,
            };
        };

        foreach string job in (keys jobs) {
            if (delta) {
                if (!inlist(job[0], ("+","-")))
                    throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; first job is a "
                        "delta (change) job command, but non-delta job found in position %d: %y", action, arg, $#,
                        job);

                # remove delta character
                string dc = extract job, 0, 1;

                # remove delta character for job check
                if (dc == "+") {
                    if (job == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements jobs != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; add all "
                                "jobs command (+*) found, but is not the only entry in the job list: %y", action, arg,
                                jobs);

                        foreach int jobid in (Qorus.qmm.getJobIds()) {
                            if (!current_jobs{jobid})
                                add_delta(jobid);
                        }
                        break;
                    }

                    int jobid = check(job);
                    if (current_jobs{jobid}) {
                        # skip jobs the group already has
                        continue;
                    }

                    # add the new job to the list
                    add_delta(jobid);
                } else {
                    if (newv)
                        throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete job "
                            "command '-%s' found in new job list", action, arg, job);

                    if (job == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements jobs != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                                "all jobs command (-*) found, but is not the only entry in the job list: %y", action,
                                arg, jobs);

                        foreach softint jobid in (keys current_jobs) {
                            del_delta(jobid);
                        }
                        break;
                    }

                    int jobid = check(job);
                    if (!current_jobs{jobid}) {
                        # skip jobs the group does not have anyway
                        continue;
                    }

                    # remove the job from the list
                    del_delta(jobid);
                }
            } else {
                int jobid = check(job);
                cmds += {
                    "action": "add",
                    "arg": jobid,
                };
                current_jobs{jobid} = True;
            }
        }

        jobs = current_jobs;

        if (!delta && !newv) {
            # if we are replacing the job list, delete the list first
            splice cmds, 0, 0, {
                "action": "delete-all",
            };
        }

        QDBG_LOG("%s group %y: jobs: %ycmds: %y", action, arg, jobs, cmds);
        return cmds;
    }

    static list<hash<auto>> checkMappers(string action, string arg, reference<*hash<string, bool>> mappers,
            *hash<auto> current_mappers, bool newv = False) {
        list<hash<auto>> cmds();

        if (!exists mappers) {
            mappers = current_mappers;
            return cmds;
        }
        bool delta = mappers ? inlist(mappers.firstKey()[0], ("+","-")) : False;
        if (!delta || !current_mappers) {
            current_mappers = new hash<string, bool>();
        }

        # check mappers
        code check = softint sub (string mapper) {
            # if the argument is an ID, then verify that it's valid
            if (mapper == int(mapper)) {
                if (!Qorus.qmm.lookupMapper(mapper, False))
                    throw "MAPPER-ERROR", sprintf("mapperid %d is not valid", mapper);
                return mapper;
            }
            (*string name, *string ver) = (mapper =~ x/^(\w+):(\w+)$/u);
            if (!name)
                throw "MAPPER-ERROR", sprintf("mapper designation %y must be in the format \"name:version\"", mapper);
            return Qorus.qmm.mapperId(name, ver);
        };

        # add a delta mapper to a group (assumes check already made that the mapper is not in the current_mappers
        # list)
        code add_delta = sub (int mapperid) {
            # add the new mappers to the list
            current_mappers{mapperid} = True;
            cmds += {
                "action": "add",
                "arg": mapperid,
            };
        };

        # delete a delta mapper from a group (assumes check already made that the mapper is in the current_mappers
        # list)
        code del_delta = sub (int mapperid) {
            remove current_mappers{mapperid};
            cmds += {
                "action": "del",
                "arg": mapperid,
            };
        };

        foreach string mapper in (keys mappers) {
            if (delta) {
                if (!inlist(mapper[0], ("+","-")))
                    throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; first mapper is "
                        "a delta (change) mapper command, but non-delta mapper found in position %d: %y", action, arg,
                        $#, mapper);

                # remove delta character
                string dc = extract mapper, 0, 1;

                # remove delta character for mappers check
                if (dc == "+") {
                    if (mapper == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements mappers != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; add all "
                                "mappers command (+*) found, but is not the only entry in the mapper list: %y",
                                action, arg, mappers);

                        foreach int mapperid in (Qorus.qmm.getMapperIds()) {
                            if (!current_mappers{mapperid})
                                add_delta(mapperid);
                        }
                        break;
                    }

                    int mapperid = check(mapper);
                    if (current_mappers{mapperid}) {
                        # skip mappers the group already has
                        continue;
                    }

                    # add the new mapper to the list
                    add_delta(mapperid);
                } else {
                    if (newv)
                        throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                            "mapper command '-%s' found in new mapper list", action, arg, mapper);

                    if (mapper == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements mappers != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                                "all mappers command (-*) found, but is not the only entry in the mapper list: %y",
                                action, arg, mappers);

                        foreach softint mapperid in (keys current_mappers) {
                            del_delta(mapperid);
                        }
                        break;
                    }

                    int mapperid = check(mapper);
                    if (!current_mappers{mapperid}) {
                        # skip mappers the group does not have anyway
                        continue;
                    }

                    # remove the mapper from the list
                    del_delta(mapperid);
                }
            } else {
                int mapperid = check(mapper);
                cmds += {
                    "action": "add",
                    "arg": mapperid,
                };
                current_mappers{mapperid} = True;
            }
        }

        mappers = current_mappers;

        if (!delta && !newv) {
            # if we are replacing the mapper list, delete the list first
            splice cmds, 0, 0, (
                    "action": "delete-all",
                    );
        }

        QDBG_LOG("%s group %y: mappers: %y cmds: %y", action, arg, mappers, cmds);
        return cmds;
    }

    static list<hash<auto>> checkVMaps(string action, string arg, reference<*hash<string, bool>> vmaps,
            *hash<auto> current_vmaps, bool newv = False) {
        list<hash<auto>> cmds();

        if (!exists vmaps) {
            vmaps = current_vmaps;
            return cmds;
        }
        bool delta = vmaps ? inlist(vmaps.firstKey()[0], ("+","-")) : False;
        if (!delta || !current_vmaps) {
            current_vmaps = new hash<string, bool>();
        }

        # check vmap
        code check = softint sub (string vmap) {
            # if the argument is an ID, then verify that it's valid
            if (vmap == int(vmap)) {
                if (!Qorus.qmm.lookupVMap(vmap, False))
                    throw "VALUE-MAP-ERROR", sprintf("value map id %d is not valid", vmap);
                return vmap;
            }
            return Qorus.qmm.vmapId(vmap);
        };

        # add a delta vmap to a group (assumes check already made that the vmap is not in the current_vmaps list)
        code add_delta = sub (int vmapid) {
            # add the new vmap to the list
            current_vmaps{vmapid} = True;
            cmds += {
                "action": "add",
                "arg": vmapid,
            };
        };

        # delete a delta vmap from a group (assumes check already made that the vmap is in the current_vmaps list)
        code del_delta = sub (int vmapid) {
            remove current_vmaps{vmapid};
            cmds += {
                "action": "del",
                "arg": vmapid,
            };
        };

        foreach string vmap in (keys vmaps) {
            if (delta) {
                if (!inlist(vmap[0], ("+","-")))
                    throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; first value map "
                        "is a delta (change) value map command, but non-delta value map found in position %d: %y",
                        action, arg, $#, vmap);

                # remove delta character
                string dc = extract vmap, 0, 1;

                # remove delta character for vmap check
                if (dc == "+") {
                    if (vmap == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements vmaps != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; add all "
                                "value maps command (+*) found, but is not the only entry in the 'vmaps' list: %y",
                                action, arg, vmaps);

                        foreach int vmapid in (Qorus.qmm.getVMapIds()) {
                            if (!current_vmaps{vmapid})
                                add_delta(vmapid);
                        }
                        break;
                    }

                    int vmapid = check(vmap);
                    if (current_vmaps{vmapid}) {
                        # skip vmaps the group already has
                        continue;
                    }

                    # add the new vmap to the list
                    add_delta(vmapid);
                } else {
                    if (newv)
                        throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                            "value map command '-%s' found in new value map list", action, arg, vmap);

                    if (vmap == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements vmaps != 1)
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                                "all value map command (-*) found, but is not the only entry in the 'vmaps' list: %y",
                                action, arg, vmaps);

                        foreach softint vmapid in (keys current_vmaps) {
                            del_delta(vmapid);
                        }
                        break;
                    }

                    int vmapid = check(vmap);
                    if (!current_vmaps{vmapid}) {
                        # skip vmaps the group does not have anyway
                        continue;
                    }

                    # remove the vmap from the list
                    del_delta(vmapid);
                }
            } else {
                int vmapid = check(vmap);
                cmds += {
                    "action": "add",
                    "arg": vmapid,
                };
                current_vmaps{vmapid} = True;
            }
        }

        vmaps = current_vmaps;

        if (!delta && !newv) {
            # if we are replacing the vmap list, delete the list first
            splice cmds, 0, 0, (
                    "action": "delete-all",
                    );
        }

        QDBG_LOG("%s group %y: vmaps: %y cmds: %y", action, arg, vmaps, cmds);
        return cmds;
    }

    static list<hash<auto>> checkFsms(string action, string arg, reference<*hash<string, bool>> fsms,
            *hash<auto> current_fsms, bool newv = False) {
        list<hash<auto>> cmds();

        if (!exists fsms) {
            fsms = current_fsms;
            return cmds;
        }
        bool delta = fsms ? inlist(fsms.firstKey()[0], ("+","-")) : False;
        if (!delta || !current_fsms) {
            current_fsms = new hash<string, bool>();
        }

        # check fsm
        code check = string sub (string fsm) {
            if (!Qorus.qmm.lookupFsm(fsm, False)) {
                throw "FSM-ERROR", sprintf("Finite State Machine %y is not valid", fsm);
            }
            return fsm;
        };

        # add a delta fsm to a group (assumes check already made that the fsm is not in the current_fsms list)
        code add_delta = sub (string name) {
            # add the new FSM to the list
            current_fsms{name} = True;
            cmds += {
                "action": "add",
                "arg": name,
            };
        };

        # delete a delta fsm from a group (assumes check already made that the fsm is in the current_fsms list)
        code del_delta = sub (string name) {
            remove current_fsms{name};
            cmds += {
                "action": "del",
                "arg": name,
            };
        };

        foreach string fsm in (keys fsms) {
            if (delta) {
                if (!inlist(fsm[0], ("+","-")))
                    throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; first value map "
                        "is a delta (change) value map command, but non-delta value map found in position %d: %y",
                        action, arg, $#, fsm);

                # remove delta character
                string dc = extract fsm, 0, 1;

                # remove delta character for fsm check
                if (dc == "+") {
                    if (fsm == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements fsms != 1) {
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; add all "
                                "value maps command (+*) found, but is not the only entry in the 'fsms' list: %y",
                                action, arg, fsms);
                        }

                        map add_delta($1), keys Qorus.qmm.getFsmMap(), !current_fsms{$1};
                        break;
                    }

                    string name = check(fsm);
                    if (current_fsms{name}) {
                        # skip fsms the group already has
                        continue;
                    }

                    # add the new fsm to the list
                    add_delta(name);
                } else {
                    if (newv) {
                        throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                            "value map command '-%s' found in new value map list", action, arg, fsm);
                    }

                    if (fsm == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements fsms != 1) {
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                                "all value map command (-*) found, but is not the only entry in the 'fsms' list: %y",
                                action, arg, fsms);
                        }

                        map del_delta($1), keys current_fsms;
                        break;
                    }

                    string name = check(fsm);
                    if (!current_fsms{name}) {
                        # skip fsms the group does not have anyway
                        continue;
                    }

                    # remove the fsm from the list
                    del_delta(name);
                }
            } else {
                string name = check(fsm);
                cmds += {
                    "action": "add",
                    "arg": name,
                };
                current_fsms{name} = True;
            }
        }

        fsms = current_fsms;

        if (!delta && !newv) {
            # if we are replacing the fsm list, delete the list first
            splice cmds, 0, 0, {
                "action": "delete-all",
            };
        }

        QDBG_LOG("%s group %y: fsms: %y cmds: %y", action, arg, fsms, cmds);
        return cmds;
    }

    static list<hash<auto>> checkPipelines(string action, string arg, reference<*hash<string, bool>> pipelines,
            *hash<auto> current_pipelines, bool newv = False) {
        list<hash<auto>> cmds();

        if (!exists pipelines) {
            pipelines = current_pipelines;
            return cmds;
        }
        bool delta = pipelines ? inlist(pipelines.firstKey()[0], ("+","-")) : False;
        if (!delta || !current_pipelines) {
            current_pipelines = new hash<string, bool>();
        }

        # check pipeline
        code check = string sub (string pipeline) {
            if (!Qorus.qmm.lookupPipeline(pipeline, False)) {
                throw "PIPELINE-ERROR", sprintf("data pipeline %y is not valid", pipeline);
            }
            return pipeline;
        };

        # add a delta pipeline to a group (assumes check already made that the pipeline is not in the
        # current_pipelines list)
        code add_delta = sub (string name) {
            # add the new pipeline to the list
            current_pipelines{name} = True;
            cmds += {
                "action": "add",
                "arg": name,
            };
        };

        # delete a delta pipeline from a group (assumes check already made that the pipeline is in the
        # current_pipelines list)
        code del_delta = sub (string name) {
            remove current_pipelines{name};
            cmds += {
                "action": "del",
                "arg": name,
            };
        };

        foreach string pipeline in (keys pipelines) {
            if (delta) {
                if (!inlist(pipeline[0], ("+","-")))
                    throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; first value map "
                        "is a delta (change) value map command, but non-delta value map found in position %d: %y",
                        action, arg, $#, pipeline);

                # remove delta character
                string dc = extract pipeline, 0, 1;

                # remove delta character for pipeline check
                if (dc == "+") {
                    if (pipeline == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements pipelines != 1) {
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; add all "
                                "value maps command (+*) found, but is not the only entry in the 'pipelines' "
                                "list: %y", action, arg, pipelines);
                        }

                        map add_delta($1), keys Qorus.qmm.getPipelineMap(), !current_pipelines{$1};
                        break;
                    }

                    string name = check(pipeline);
                    if (current_pipelines{name}) {
                        # skip pipelines the group already has
                        continue;
                    }

                    # add the new pipeline to the list
                    add_delta(name);
                } else {
                    if (newv) {
                        throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                            "value map command '-%s' found in new value map list", action, arg, pipeline);
                    }

                    if (pipeline == "*") {
                        # make sure any wildcard entry is the only entry in the list
                        if (elements pipelines != 1) {
                            throw sprintf("RBAC-%s-GROUP-ERROR", action.upr()), sprintf("cannot %s group %y; delete "
                                "all value map command (-*) found, but is not the only entry in the 'pipelines' "
                                "list: %y", action, arg, pipelines);
                        }

                        map del_delta($1), keys current_pipelines;
                        break;
                    }

                    string name = check(pipeline);
                    if (!current_pipelines{name}) {
                        # skip pipelines the group does not have anyway
                        continue;
                    }

                    # remove the pipeline from the list
                    del_delta(name);
                }
            } else {
                string name = check(pipeline);
                cmds += {
                    "action": "add",
                    "arg": name,
                };
                current_pipelines{name} = True;
            }
        }

        pipelines = current_pipelines;

        if (!delta && !newv) {
            # if we are replacing the pipeline list, delete the list first
            splice cmds, 0, 0, {
                "action": "delete-all",
            };
        }

        QDBG_LOG("%s group %y: pipelines: %y cmds: %y", action, arg, pipelines, cmds);
        return cmds;
    }

    static updateSyntheticGroupStatusSql(Group g, bool enabled) {
        # handle synthetic groups: can only update enabled status on synthetic groups
        my (string o, softint id);
        if (g.services) {
            o = "service";
            id = g.services.firstKey();
            # update in internal map
            Qorus.qmm.setServiceEnabled(id, enabled);
        } else if (g.workflows) {
            o = "workflow";
            id = g.workflows.firstKey();
            # update in internal maps
            Qorus.qmm.setWorkflowEnabled(id, enabled);
        } else {
            o = "job";
            id = g.jobs.firstKey();
            # update in internal map
            Qorus.qmm.setJobEnabled(id, enabled);
        }
        sqlif.updateSyntheticGroup(o, id, enabled);
    }

    # returns the new group id created
    int createGroup(string name, string desc, *softlist<auto> svcids, *softlist<auto> wfids, *softlist<auto> jids,
            *softlist<auto> mids, *softlist<auto> vmids, *softlist<auto> fsms, *softlist<auto> pipelines,
            softbool enabled = True) {
        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        if (!name)
            throw "GROUP-ERROR", "group name passed as an empty string";

        # if description is too long, then truncate and log warning
        if (desc.size() > SQLDescLen) {
            desc = trunc_str(desc, SQLDescLen, omqp.getOSEncoding());
            rbaclog(LoggerLevel::INFO, "create group '%s': description is longer than %d characters, truncating "
                "to: %y", name, SQLDescLen, desc);
        }

        AutoWriteLock al(rwl);

        if (groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' already exists", name);

        # create hash from workflow list
        *hash<string, bool> wh = map {$1: True}, wfids;

        # get workflow commands and make sure all workflows exist
        list<hash<auto>> wf_cmds = RBAC::checkWorkflows("add", name, \wh, NOTHING, True);

        # create hash from service list
        *hash<string, bool> sh = map {$1: True}, svcids;

        # get service commands and make sure all services exist
        list<hash<auto>> svc_cmds = RBAC::checkServices("add", name, \sh, NOTHING, True);

        # create hash from job list
        *hash<string, bool> jh = map {$1: True}, jids;

        # get job commands and make sure all jobs exist
        list<hash<auto>> job_cmds = RBAC::checkJobs("add", name, \jh, NOTHING, True);

        # create hash from mapper list
        *hash<string, bool> mh = map {$1: True}, mids;

        # get mapper commands and make sure all mappers exist
        list<hash<auto>> mapper_cmds = RBAC::checkMappers("add", name, \mh, NOTHING, True);

        # create hash from value map list
        *hash<string, bool> vmh = map {$1: True}, vmids;

        # get value map commands and make sure all value maps exist
        list<hash<auto>> vmap_cmds = RBAC::checkVMaps("add", name, \vmh, NOTHING, True);

        # create hash from FSM list
        *hash<string, bool> fsmh = map {$1: True}, fsms;

        # get fsm commands and make sure all fsms exist
        list<hash<auto>> fsm_cmds = RBAC::checkFsms("add", name, \fsmh, NOTHING, True);

        # create hash from pipeline list
        *hash<string, bool> pipeh = map {$1: True}, pipelines;

        # get pipeline commands and make sure all pipelines exist
        list<hash<auto>> pipeline_cmds = RBAC::checkPipelines("add", name, \pipeh, NOTHING, True);

        int id = sqlif.addGroup(name, desc, enabled, wf_cmds, svc_cmds, job_cmds, mapper_cmds, vmap_cmds, fsm_cmds,
            pipeline_cmds);

        Group g(name, desc, id, enabled, wh, sh, jh, mh, vmh, fsmh, pipeh);
        groups{name} = g;

        rbaclog(LoggerLevel::INFO, "created RBAC group %y (enabled: %y): workflows: %y, services: %y, jobs: %y, "
            "mappers: %y, value maps: %y, fsms: %y, pipelines: %y", name, enabled,
                (map int($1), keys wh),
                (map int($1), keys sh),
                (map int($1), keys jh),
                (map int($1), keys mh),
                (map int($1), keys vmh),
                keys fsmh,
                keys pipeh,
            );

        # if the group is created as disabled, then make sure all members are stopped
        if (!enabled) {
            # ensure atomic changes to interfaces
            AtomicMultiClassActionHelper atomic_action_helper(keys g.workflows, keys g.services, keys g.jobs);

            # stop all affected workflows
            if (g.workflows) {
                atomic_action_helper.doBackgroundWorkflows(keys g.workflows, \stopWorkflows(), "create disabled", g,
                    g.workflows, atomic_action_helper);
            }

            # stop all affected services
            # fix for bug 842: do not unload services with the RBAC write lock held
            if (g.services) {
                atomic_action_helper.doBackgroundServices(keys g.services, \stopServices(), "create disabled", g,
                    g.services, atomic_action_helper);
            }

            # stop all affected jobs
            if (g.jobs) {
                atomic_action_helper.doBackgroundJobs(keys g.jobs, \stopJobs(), "create disabled", g, g.jobs,
                    atomic_action_helper);
            }
        }

        return id;
    }

    updateGroup(string group, hash<auto> h) {
        if (!h.desc && !h.services && !h.workflows && !h.jobs && !h.mappers && !h.vmaps && !h.fsms && !h.pipelines
            && !exists h.enabled)
            throw "RBAC-UPDATE-GROUP-ERROR", "at least one of 'desc', 'services', 'workflows', 'jobs', 'mappers', "
                "'vmaps', 'fsms', 'pipelines', or 'enabled' keys must be passed in the second argument hash to "
                "update the group";

        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (group == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        if (exists h.enabled)
            h.enabled = parse_boolean(h.enabled);

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (!groups{group})
            throw "RBAC-UPDATE-GROUP-ERROR", sprintf("group %y does not exist", group), OMQ::AUTH_INVALID_GROUP;

        bool syn = groups{group}.isSynthetic();

        OMQ::Group g = groups{group};

        if (syn) {
            hash lh = h - "enabled";
            if (lh)
                throw "RBAC-UPDATE-GROUP-ERROR", sprintf("group %y is a synthetic group and only the 'enabled' status "
                    "can be updated (other update keys passed: %y)", group, lh.keys()), OMQ::AUTH_INVALID_GROUP;

            if (!h.hasKey("enabled"))
                throw "RBAC-UPDATE-GROUP-ERROR", sprintf("group %y is a synthetic group and only the 'enabled' status "
                    "can be updated", group), OMQ::AUTH_INVALID_GROUP;

            # no need to do anything if no changes are made to a synthetic group
            if (h.enabled == g.enabled)
                return;
        }

        # create hash from workflow list
        *hash<string, bool> wh = map {$1: True}, h.workflows;
        # get workflow commands and make sure all workflows exist
        list<hash<auto>> workflow_cmds = RBAC::checkWorkflows("update", group, \wh, g.workflows);

        # create hash from service list
        *hash<string, bool> sh = map {$1: True}, h.services;
        # get service commands and make sure all services exist
        list<hash<auto>> service_cmds = RBAC::checkServices("update", group, \sh, g.services);

        # create hash from job list
        *hash<string, bool> jh = map {$1: True}, h.jobs;
        # get job commands and make sure all jobs exist
        list<hash<auto>> job_cmds = RBAC::checkJobs("update", group, \jh, g.jobs);

        # create hash from mapper list
        *hash<string, bool> mh = map {$1: True}, h.mappers;
        # get mapper commands and make sure all mappers exist
        list<hash<auto>> mapper_cmds = RBAC::checkMappers("update", group, \mh, g.mappers);

        # create hash from vmap list
        *hash<string, bool> vh = map {$1: True}, h.vmaps;
        # get value map commands and make sure all value maps exist
        list<hash<auto>> vmap_cmds = RBAC::checkVMaps("update", group, \vh, g.vmaps);

        # create hash from fsm list
        *hash<string, bool> fsmh = map {$1: True}, h.fsms;
        # get fsm commands and make sure all fsms exist
        list<hash<auto>> fsm_cmds = RBAC::checkFsms("update", group, \fsmh, g.fsms);

        # create hash from pipeline list
        *hash<string, bool> pipeh = map {$1: True}, h.pipelines;
        # get pipeline commands and make sure all pipelines exist
        list<hash<auto>> pipeline_cmds = RBAC::checkPipelines("update", group, \pipeh, g.pipelines);

        # do groups need to be updated?
        bool ur = False;

        # ensure atomic updated for affected interfaces
        hash<string, hash<string, bool>> ah;

        if (!h.enabled || !g.enabled) {
            if (!h.enabled && !g.enabled) {
                # otherwise if the group existed and is now disabled and was disabled before, only add differences
                g.addInterfaceDiff(\ah, sh, jh, wh, True, True, True);
            } else {
                # otherwise add the union of all relevant interfaces
                map ah{AtomicClassActionHelper::C_Service}{$1} = True, keys g.services;
                map ah{AtomicClassActionHelper::C_Service}{$1} = True, keys sh;
                map ah{AtomicClassActionHelper::C_Job}{$1} = True, keys g.jobs;
                map ah{AtomicClassActionHelper::C_Job}{$1} = True, keys jh;
                map ah{AtomicClassActionHelper::C_Workflow}{$1} = True, keys g.workflows;
                map ah{AtomicClassActionHelper::C_Workflow}{$1} = True, keys wh;
            }
        }

        #QDBG_LOG("RBAC::updateGroup() ah: %y", ah);
        #QDBG_LOG("RBAC::updateGroup() wf: %y", workflow_cmds);
        #QDBG_LOG("RBAC::updateGroup() svc: %y", service_cmds);
        #QDBG_LOG("RBAC::updateGroup() job: %y", job_cmds);

        AtomicMultiClassActionHelper atomic_action_helper(ah);

        {
            # set flag if updating a disabled group (that remains disabled)
            bool update_disabled = (!g.enabled && ((exists h.enabled && !h.enabled) || (!exists h.enabled)));

            # closure used to delete an ID from a group's list and update the reverse map as well
            code dellist = sub (string type, string mapv, reference<list<auto>> l) {
                if (!l)
                    return;

                if (!ur)
                    ur = True;

                # remove object IDs from group's member list
                g{type} -= l;

                # remove group from object maps
                map remove self{mapv}.$1.(g.name), l;

                # reset list
                l = ();
            };

            # closure used to add an ID from a group's list and update the reverse map as well
            code addlist = sub (string type, string mapv, reference<list<auto>> l) {
                if (!l)
                    return;

                if (!ur)
                    ur = True;

                # add object IDs to group's member list
                map g{type}.$1 = True, l;

                # add group to object map for each object
                map self{mapv}.$1.(g.name) = True, l;

                # reset list
                l = ();
            };

            # deletion list
            list<auto> dlist = ();

            # add list
            list<auto> alist = ();

            # code to execute the SQL and add the entry to the right list
            code exec = sub (hash<auto> cmd) {
                if (cmd.action == "del")
                    dlist += cmd.arg;
                else if (cmd.action == "add")
                    alist += cmd.arg;
            };

            # update DB
            if (!syn)
                sqlif.updateGroup(g.id, h.desc, h.enabled, workflow_cmds, service_cmds, job_cmds, mapper_cmds,
                    vmap_cmds, fsm_cmds, pipeline_cmds);
            else
                RBAC::updateSyntheticGroupStatusSql(g, h.enabled);

            # update group definition and maps
            # update group workflows
            map exec($1), workflow_cmds;
            if (update_disabled) {
                Qorus.alerts.updateShadowedAlerts("GROUP", g.id, "WORKFLOW", "INTERFACE-GROUP-DISABLED", alist,
                    dlist);
            }
            dellist("workflows", "wmap", \dlist);
            addlist("workflows", "wmap", \alist);

            # update group services
            map exec($1), service_cmds;
            if (update_disabled) {
                Qorus.alerts.updateShadowedAlerts("GROUP", g.id, "SERVICE", "INTERFACE-GROUP-DISABLED", alist, dlist);
            }
            dellist("services", "smap", \dlist);
            addlist("services", "smap", \alist);

            # update group jobs
            map exec($1), job_cmds;
            if (update_disabled) {
                Qorus.alerts.updateShadowedAlerts("GROUP", g.id, "JOB", "INTERFACE-GROUP-DISABLED", alist, dlist);
            }
            dellist("jobs", "jmap", \dlist);
            addlist("jobs", "jmap", \alist);

            # update group mappers
            map exec($1), mapper_cmds;
            dellist("mappers", "mmap", \dlist);
            addlist("mappers", "mmap", \alist);

            # update group value maps
            map exec($1), vmap_cmds;
            dellist("vmaps", "vmap", \dlist);
            addlist("vmaps", "vmap", \alist);

            # update group fsms
            map exec($1), fsm_cmds;
            dellist("fsms", "fsm", \dlist);
            addlist("fsms", "fsm", \alist);

            # update group pipelines
            map exec($1), pipeline_cmds;
            dellist("pipelines", "pipeline", \dlist);
            addlist("pipelines", "pipeline", \alist);

            if (ur)
                g.updateSize();
        }

        # replace all workflows, services, jobs, mappers, value maps, fsms, and pipelines
        g += {
            "workflows": wh,
            "services": sh,
            "jobs": jh,
            "mappers": mh,
            "vmaps": vh,
            "fsms": fsmh,
            "pipelines": pipeh,
        };

        if (h.desc)
            g.description = h.desc;

        if (exists h.enabled) {
            if (h.enabled == g.enabled)
                delete h.enabled;
            else
                g.enabled = h.enabled;
        }

        # did the enabled status change?
        bool ec = exists h.enabled;

        # effect changes
        code start_removed = sub (*hash<auto> cx) {
            # get list of deleted services and start any removed services with the autostart flag set if possible
            *hash<string, bool> th = map {$1.arg: True}, service_cmds, $1.action == "del";
            if (th) {
                atomic_action_helper.doBackgroundServices(keys th, \autoStartServices(), cx, "remove service from "
                    "disabled", g, th, atomic_action_helper);
            }

            # get list of deleted jobs and start any removed jobs if possible
            th = map {$1.arg: True}, job_cmds, $1.action == "del";
            if (th) {
                atomic_action_helper.doBackgroundJobs(keys th, \startJobs(), cx, "remove job from disabled", g, th,
                    atomic_action_helper);
            }

            # get list of deleted workflows and start any removed workflows if possible
            th = map {$1.arg: True}, workflow_cmds, $1.action == "del";
            if (th) {
                atomic_action_helper.doBackgroundWorkflows(keys th, \autoStartWorkflows(), cx, "remove workflow from "
                    "disabled", g, th, atomic_action_helper);
            }
        };

        # stop all workflows added to disabled group
        if (!g.enabled) {
            QDBG_LOG("group %y: g.enabled: %y ec: %y", g.name, g.enabled, ec);
            # if the status did not change, then just stop new objects added to the group and start objects deleted
            # from the group
            if (!ec) {
                # stop interfaces added to the group
                # get list of added workflows
                {
                    *hash<string, bool> wf_th = map {$1.arg: True}, workflow_cmds, $1.action == "add";
                    if (wf_th) {
                        atomic_action_helper.doBackgroundWorkflows(keys wf_th, \stopWorkflows(), "add workflow to "
                            "disabled", g, wf_th, atomic_action_helper);
                    }
                }

                # get list of added services
                {
                    *hash<string, bool> svc_th = map {$1.arg: True}, service_cmds, $1.action == "add";
                    if (svc_th) {
                        # fix for bug 842: do not unload services with the RBAC write lock held
                        atomic_action_helper.doBackgroundServices(keys svc_th, \stopServices(), "add service to "
                            "disabled", g, svc_th, atomic_action_helper);
                    }
                }

                {
                    # get list of added jobs
                    *hash<string, bool> job_th = map {$1.arg: True}, job_cmds, $1.action == "add";
                    if (job_th) {
                        atomic_action_helper.doBackgroundJobs(keys job_th, \stopJobs(), "add job to disabled", g,
                            job_th, atomic_action_helper);
                    }
                }

                # start objects removed from the group
                start_removed(tld.cx);
            } else {
                # status changed from enabled -> disabled
                disableUnlockedIntern(g, atomic_action_helper);
            }
        } else {
            # is now enabled
            if (ec) {
                # status changed from disabled -> enabled
                # start objects removed from the group
                start_removed(tld.cx);

                enableUnlockedIntern(g, atomic_action_helper);
            }
        }

        rbaclog(LoggerLevel::INFO, "updated group %y (%y): %y", group, g.description, h);
    }

    deleteGroup(string name) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "DELETE-GROUP-ERROR", "cannot delete group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!exists groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        if (groups{name}.id < 0)
            throw "GROUP-ERROR", sprintf("group %y is a synthetic group and cannot be deleted", name);

        Group g = groups{name};

        # enable group before deleting
        if (!g.enabled)
            enableUnlocked(g);

        # delete the group from the DB
        sqlif.deleteGroup(g.id);

        deleteGroupIntern(g);
        rbaclog(LoggerLevel::INFO, "deleted group %y (%y)", name, g.description);
    }

    private deleteGroupIntern(Group g) {
        string name = g.name;

        # remove from maps
        delete gmap.(g.id);

        # remove group from service maps
        map remove smap.$1{name}, keys smap;

        # remove group from workflow maps
        map remove wmap.$1{name}, keys wmap;

        # remove group from job maps
        map remove jmap.$1{name}, keys jmap;

        # remove group from mapper maps
        map remove mmap.$1{name}, keys mmap;

        # remove group from vmap maps
        map remove vmap.$1{name}, keys vmap;

        # remove group from fsm maps
        map remove fsmmap.$1{name}, keys fsmmap;

        # remove group from pipeline maps
        map remove pipemap.$1{name}, keys pipemap;

        # remove group instead of deleting (could be referenced in a waitForAutostart() method for example)
        remove groups{name};
    }

    addWorkflow(string name, string wname, *string ver) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        # make sure workflow exists
        *hash<auto> wf = Qorus.qmm.rLookupWorkflow(wname, ver);
        if (!wf)
            throw "GROUP-ERROR", sprintf("cannot update group '%s' with unknown workflow %s%s", name, wname,
                exists ver ? sprintf("/%s", ver) : "");

        list<int> ids = ();

        if (exists wf.lastversion)
            map ids += int(wf.$1.workflowid), keys (wf - "lvcreated" - "lastversion");
        else
            ids += int(wf.workflowid);

        addWorkflowIDsIntern(name, ids);
    }

    addWorkflowIDs(string name, softlist<softint> wfids) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        if (!wfids)
            throw "GROUP-ERROR", sprintf("invalid workflow ID list for group '%s': %y", name, wfids);

        # make sure workflow exists
        foreach softint id in (wfids) {
            *hash<auto> wf = Qorus.qmm.lookupWorkflow(id);
            if (!wf)
                throw "GROUP-ERROR", sprintf("cannot update group '%s' with unknown workflowid %d", name, id);
        }

        addWorkflowIDsIntern(name, wfids);
    }

    private addWorkflowIDsIntern(string name, softlist<softint> ids) {
        # hash of workflow IDs: wfid -> True
        hash<string, bool> wfh;
        # check to make sure workflowids are not already in the list
        foreach int id in (ids) {
            if (!groups{name}.workflows{id}) {
                wfh{id} = True;
            }
        }

        if (!wfh) {
            throw "GROUP-ERROR", sprintf("all workflowids (%y) are already members of group '%s'", ids, name);
        }

        Group g = groups{name};

        if (g.id < 0) {
            throw "GROUP-ERROR", sprintf("group %y is a synthetic group and cannot be updated", g.name);
        }

        list<softint> l = keys wfh;

        # update shadowed objects
        if (!g.enabled) {
            Qorus.alerts.updateShadowedAlerts("GROUP", g.id, "WORKFLOW", "INTERFACE-GROUP-DISABLED", l);
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # add workflows to group's workflow list in DB
                sqlif.addWorkflowsToGroup(g.id, l);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # add workflows to group's workflow list
        g.workflows += wfh;
        g.updateSize();

        # add group to workflow map for each workflow
        map wmap.$1{name} = True, l;

        # stop all workflows added to disabled group
        if (!groups{name}.enabled) {
            # ensure atomic changes to interfaces
            AtomicMultiClassActionHelper atomic_action_helper(keys wfh);

            stopWorkflows("add workflow to disabled", groups{name}, wfh, atomic_action_helper);
        }
    }

    deleteWorkflow(string name, string wname, *string ver) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!exists groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        # make sure workflow exists
        *hash wf = Qorus.qmm.rLookupWorkflow(wname, ver);
        if (!exists wf)
            throw "GROUP-ERROR", sprintf("cannot update group '%s' by removing unknown workflow %s%s", name, wname,
                exists ver ? sprintf("/%s", ver) : "");

        list<int> ids = ();

        if (exists wf.lastversion)
            map ids += int(wf.$1.workflowid), keys (wf - "lvcreated" - "lastversion");
        else
            ids += int(wf.workflowid);

        deleteWorkflowIDsIntern(name, ids);
    }

    deleteWorkflowIDs(string name, softlist wfids) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        if (!wfids)
            throw "GROUP-ERROR", sprintf("invalid workflow ID or list for group '%s': %y", name, wfids);

        # make sure workflow exists
        foreach softint id in (wfids) {
            *hash<auto> wf = Qorus.qmm.lookupWorkflow(id);
            if (!wf)
                throw "GROUP-ERROR", sprintf("cannot update group '%s' by removing unknown workflowid %d", name, id);
        }

        deleteWorkflowIDsIntern(name, wfids);
    }

    private deleteWorkflowIDsIntern(string name, list<auto> ids) {
        Group g = groups{name};

        if (g.id < 0)
            throw "GROUP-ERROR", sprintf("group %y is a synthetic group and cannot be updated", g.name);

        # check to make sure workflowids are not already in the list
        hash<string, bool> h = map {$1: True}, ids, g.workflows{$1};

        if (!h)
            throw "GROUP-ERROR", sprintf("none of the given workflowids (%y) are members of group '%s'", ids, name);

        list<softint> l = h.keys();

        # update shadowed objects
        if (!g.enabled) {
            Qorus.alerts.updateShadowedAlerts("GROUP", g.id, "WORKFLOW", "INTERFACE-GROUP-DISABLED", NOTHING, l);
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # remove workflow from group's workflow list in the DB
                sqlif.deleteWorkflowsFromGroup(g.id, l);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # remove workflows from group's workflow list
        map remove g.workflows.$1, l;
        g.updateSize();

        # remove group from workflow maps
        map remove wmap.$1.(g.name), l;

        # return if group was enabled
        if (groups{name}.enabled)
            return;

        # ensure atomic changes to interface
        AtomicMultiClassActionHelper atomic_action_helper({
            AtomicClassActionHelper::C_Workflow: (map {$1: True}, ids),
        });

        # otherwise start any removed workflows with the autostart flag set
        atomic_action_helper.doBackgroundWorkflows(l, \autoStartWorkflows(), tld.cx, "remove workflow from disabled",
            groups{name}, h, atomic_action_helper);
    }

    addService(string name, string sname, *string ver) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!exists groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        # make sure service exists
        *hash svc = Qorus.qmm.rLookupService("user", sname, ver);
        if (!exists svc)
            throw "GROUP-ERROR", sprintf("cannot update group '%s' with unknown service %s%s", name, sname,
                exists ver ? sprintf("/%s", ver) : "");

        list<int> ids = ();

        if (exists svc.lastversion)
            ids += map int(svc.$1), keys (svc - "lvcreated" - "lastversion");
        else
            ids += int(svc.serviceid);

        addServiceIDsIntern(name, ids);
    }

    addServiceIDs(string name, softlist<softint> svcids) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        if (!svcids)
            throw "GROUP-ERROR", sprintf("invalid service ID or list for group '%s': %y", name, svcids);

        # make sure service exists
        foreach softint id in (svcids) {
            *hash<auto> svc = Qorus.qmm.lookupService(id, False);
            if (!svc)
                throw "GROUP-ERROR", sprintf("cannot update group '%s' with unknown serviceid %d", name, id);
            if (svc.type == "system")
                throw "GROUP-ERROR", sprintf("cannot update group '%s' with system service %s/%s (%d)", name,
                    svc.name, svc.version, id);
        }

        addServiceIDsIntern(name, svcids);
    }

    private addServiceIDsIntern(string name, softlist<softint> ids) {
        Group g = groups{name};

        if (g.id < 0) {
            throw "GROUP-ERROR", sprintf("group %y is a synthetic group and cannot be updated", g.name);
        }

        # hash of service IDs; svcid -> True
        hash<string, bool> svch;
        # check to make sure serviceids are not already in the list
        foreach softstring id in (ids) {
            if (!g.services{id}) {
                svch{id} = True;
            }
        }

        if (!svch) {
            throw "GROUP-ERROR", sprintf("all serviceids (%y) are already members of group '%s'", ids, name);
        }

        list<softint> l = keys svch;

        # update shadowed objects
        if (!g.enabled) {
            Qorus.alerts.updateShadowedAlerts("GROUP", g.id, "SERVICE", "INTERFACE-GROUP-DISABLED", l);
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # add services to group's service list in DB
                sqlif.addServicesToGroup(g.id, l);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # add services to group's service list
        g.services += svch;
        g.updateSize();

        # add group to service map for each service
        map smap.$1{name} = True, l;

        # stop all services added to disabled group
        if (!g.enabled) { # fix for bug 842: do not unload services with the RBAC write lock held
            # ensure atomic changes to interfaces
            AtomicMultiClassActionHelper atomic_action_helper(NOTHING, keys svch);
            atomic_action_helper.doBackgroundServices(l, \stopServices(), "add service to disabled", g, svch,
                atomic_action_helper);
        }
    }

    deleteService(string name, string sname, *string ver) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!exists groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        # make sure service exists
        *hash svc = Qorus.qmm.rLookupService("user", sname, ver);
        if (!exists svc)
            throw "GROUP-ERROR", sprintf("cannot update group '%s' by removing unknown service %s%s", name, sname,
                exists ver ? sprintf("/%s", ver) : "");

        list<int> ids = ();

        if (exists svc.lastversion)
            ids += map int(svc.$1), keys (svc - "lvcreated" - "lastversion");
        else
            ids += int(svc.serviceid);

        deleteServiceIDsIntern(name, ids);
    }

    deleteServiceIDs(string name, softlist svcids) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        if (!svcids)
            throw "GROUP-ERROR", sprintf("invalid service ID or list for group '%s': %y", name, svcids);

        # make sure service exists
        foreach softint id in (svcids) {
            *hash<auto> svc = Qorus.qmm.lookupService(id, False);
            if (!svc)
                throw "GROUP-ERROR", sprintf("cannot update group '%s' by removing unknown serviceid %d", name, id);
        }

        deleteServiceIDsIntern(name, svcids);
    }

    private deleteServiceIDsIntern(string name, softlist<softint> ids) {
        hash h;

        Group g = groups{name};

        if (g.id < 0)
            throw "GROUP-ERROR", sprintf("group %y is a synthetic group and cannot be updated", g.name);

        # check to make sure serviceids are already in the list
        foreach int id in (ids)
            if (g.services{id})
                h{id} = True;

        if (!h)
            throw "GROUP-ERROR", sprintf("none of the given serviceids (%y) are members of group '%s'", ids, name);

        list<softint> l = h.keys();

        # update shadowed objects
        if (!g.enabled) {
            Qorus.alerts.updateShadowedAlerts("GROUP", g.id, "SERVICE", "INTERFACE-GROUP-DISABLED", NOTHING, l);
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # remove service from group's service list in the DB
                sqlif.deleteServicesFromGroup(g.id, l);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # remove service from group's service list
        map remove g.services.$1, l;
        g.updateSize();

        # remove group from service maps
        map remove smap.$1{name}, l;

        # return if group was enabled
        if (groups{name}.enabled)
            return;

        # ensure atomic changes to interfaces
        AtomicMultiClassActionHelper atomic_action_helper({
            AtomicClassActionHelper::C_Service: (map {$1: True}, ids),
        });

        # otherwise start any removed services with the autostart flag set
        atomic_action_helper.doBackgroundServices(l, \autoStartServices(), tld.cx, "remove service from disabled",
            groups{name}, h, atomic_action_helper);
    }

    addJob(string name, string jname, *hash<auto> job) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        # make sure job exists
        if (!job) {
            job = Qorus.qmm.rLookupJob(jname, False);
            if (!job) {
                throw "GROUP-ERROR", sprintf("cannot update group '%s' with unknown job %s", name, jname);
            }
        }

        addJobIDsIntern(name, job.jobid);
    }

    addJobIDs(string name, softlist<softint> jobids) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        if (!jobids)
            throw "GROUP-ERROR", sprintf("invalid job ID or list for group '%s': %y", name, jobids);

        # make sure jobs exist
        foreach softint id in (jobids) {
            *hash<auto> job = Qorus.qmm.lookupJob(id, False);
            if (!job)
                throw "GROUP-ERROR", sprintf("cannot update group '%s' with unknown jobid %d", name, id);
        }

        addJobIDsIntern(name, jobids);
    }

    private addJobIDsIntern(string name, softlist<softint> ids) {
        Group g = groups{name};

        if (g.id < 0) {
            throw "GROUP-ERROR", sprintf("group %y is a synthetic group and cannot be updated", g.name);
        }

        # job ID hash; jobid -> True
        hash<string, bool> jobh;
        # check to make sure jobids are not already in the list
        foreach softstring id in (ids) {
            if (!g.jobs{id}) {
                jobh{id} = True;
            }
        }

        if (!jobh) {
            throw "GROUP-ERROR", sprintf("all jobids (%y) are already members of group '%s'", ids, name);
        }

        list<softint> l = keys jobh;

        # update shadowed objects
        if (!g.enabled) {
            Qorus.alerts.updateShadowedAlerts("GROUP", g.id, "JOB", "INTERFACE-GROUP-DISABLED", l);
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # add jobs to group's job list in DB
                sqlif.addJobsToGroup(g.id, l);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # add jobs to group's job list
        g.jobs += jobh;
        g.updateSize();

        # add group to job map for each job
        map jmap.$1{name} = True, keys jobh;

        # stop all jobs added to disabled group
        if (!g.enabled) {
            # ensure atomic changes to interfaces
            AtomicMultiClassActionHelper atomic_action_helper(NOTHING, NOTHING, keys jobh);
            stopJobs("add job to disabled", g, jobh, atomic_action_helper);
        }
    }

    deleteJob(string name, string jname) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!exists groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        # make sure job exists
        *hash job = Qorus.qmm.rLookupJob(jname, False);
        if (!job)
            throw "GROUP-ERROR", sprintf("cannot update group '%s' by removing unknown job %s", name, jname);

        deleteJobIDsIntern(name, job.jobid);
    }

    deleteJobIDs(string name, softlist<softint> jobids) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName)
            throw "UPDATE-GROUP-ERROR", "cannot update group \"DEFAULT\"";

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        if (!jobids)
            throw "GROUP-ERROR", sprintf("invalid job ID or list for group '%s': %y", name, jobids);

        # make sure job exists
        foreach softint id in (jobids) {
            *hash<auto> job = Qorus.qmm.lookupJob(id, False);
            if (!job)
                throw "GROUP-ERROR", sprintf("cannot update group '%s' by removing unknown jobid %d", name, id);
        }

        deleteJobIDsIntern(name, jobids);
    }

    private deleteJobIDsIntern(string name, softlist<softint> ids) {
        Group g = groups{name};

        if (g.id < 0)
            throw "GROUP-ERROR", sprintf("group %y is a synthetic group and cannot be updated", g.name);

        # check to make sure jobids are already in the list
        hash<string, bool> h = map {$1: True}, ids, g.jobs{$1};

        if (!h)
            throw "GROUP-ERROR", sprintf("none of the given jobids (%y) are members of group '%s'", ids, name);

        list<softint> l = h.keys();

        # update shadowed objects
        if (!g.enabled) {
            Qorus.alerts.updateShadowedAlerts("GROUP", g.id, "JOB", "INTERFACE-GROUP-DISABLED", NOTHING, l);
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                # remove job from group's job list in the DB
                sqlif.deleteJobsFromGroup(g.id, l);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            trans.reset();
            break;
        }

        # remove job from group's job list
        map remove g.jobs.$1, keys h;
        g.updateSize();

        # remove group from job maps
        map remove jmap.$1{name}, keys h;

        # return if group was enabled
        if (groups{name}.enabled) {
            return;
        }

        # ensure atomic changes to interfaces
        AtomicMultiClassActionHelper atomic_action_helper({AtomicClassActionHelper::C_Job: (map {$1: True}, ids)});

        # otherwise start any removed active jobs
        atomic_action_helper.doBackgroundJobs(l, \startJobs(), tld.cx, "remove job from disabled", groups{name}, h,
            atomic_action_helper);
    }

    # returns a list of workflow IDs from the group name
    list<int> getWorkflows(string name) {
        AutoReadLock al(rwl);

        return exists groups{name} ? (map int($1), keys groups{name}.workflows) : ();
    }

    # returns a list of service IDs from the group name
    list<int> getServices(string name) {
        AutoReadLock al(rwl);

        return exists groups{name} ? (map int($1), keys groups{name}.services) : ();
    }

    # returns a list of hashes (keys: name, version, workflowid) of workflow information from the group name
    list<hash<auto>> getWorkflowDetails(string name) {
        hash<auto> h;
        {
            AutoReadLock al(rwl);

            if (!exists groups{name})
                return ();

            h = groups{name}.workflows;
        }

        list<hash> rv();
        foreach softint id in (keys h) {
            hash<auto> wf.workflowid = id;

            *hash<auto> wfi = Qorus.qmm.lookupWorkflow(id);
            if (!exists wfi) {
                # ignore workflows that no longer exist
                continue;
            }

            wf += wfi.("name", "version");
            rv += wf;
        }

        return rv;
    }

    # returns a list of service IDs from the group name
    list<hash<auto>> getServiceDetails(string name) {
        hash<auto> h;
        {
            AutoReadLock al(rwl);

            if (!exists groups{name})
                return ();

            h = groups{name}.services;
        }

        list<hash> rv();
        foreach softint id in (keys h) {
            hash<auto> svc.serviceid = id;

            *hash<auto> svci = Qorus.qmm.lookupService(id, False);
            if (!svci) {
                # ignore services that no longer exist
                continue;
            }

            svc += svci.("type", "name", "version");
            rv += svc;
        }

        return rv;
    }

    # returns a list of workflow IDs from the group ID
    softlist<int> getWorkflowsFromID(softstring id) {
        AutoReadLock al(rwl);

        if (exists gmap{id}) {
            return (map int($1), keys groups.(gmap{id}).workflows);
        }
    }

    # returns a list of service IDs from the group ID
    list<int> getServicesFromID(softstring id) {
        AutoReadLock al(rwl);

        if (!exists gmap{id}) {
            return ();
        }

        return (map int($1), keys groups.(gmap{id}).services);
    }

    # returns a copy of the Group object
    hash getGroupInfo(*string name) {
        AutoReadLock al(rwl);

        if (!exists name)
            return map {$1.key: $1.value.getInfo()}, groups.pairIterator();

        if (!exists groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        return groups{name}.getInfo();
    }

    # returns a copy of the Group object
    Group getGroupInfoFromID(softstring id) {
        AutoReadLock al(rwl);

        if (!gmap{id})
            throw "GROUP-ERROR", sprintf("groupid %d does not exist", id);

        return groups.(gmap{id}).copy();
    }

    # throws an exception if the workflow cannot be started
    private canStartWorkflowUnlocked(softstring id) {
        *hash<auto> wf = Qorus.qmm.lookupWorkflow(id, True);

        bool configured = Qorus.qmm.checkIfWorkflowIsConfigured(wf);
        if (!configured) {
            throw "WORKFLOW-NOT-CONFIGURED",
                   sprintf("cannot start workflow %s/%s (%d) because it is not properly configured",
                           wf.name, wf.version, id);
        }

        foreach string name in (keys wmap{id}) {
            if (!groups{name}.enabled) {
                throw "GROUP-DISABLED", sprintf("cannot start workflow %s/%s (%d) because it is a member of disabled "
                    "group %s (%s); enable group %s by calling PUT /api/latest/groups/%s/enable to be able to "
                    "start this workflow", wf.name, wf.version, id, name, groups{name}.getId(), name, name);
            }
        }
    }

    # returns True if the workflow can be started, False if not
    private bool testStartWorkflowUnlocked(softstring id) {
        *hash<auto> wf = Qorus.qmm.lookupWorkflow(id, True);

        if (!Qorus.qmm.checkIfWorkflowIsConfigured(wf)) {
            return False;
        }

        foreach string name in (keys wmap{id}) {
            if (!groups{name}.enabled)
                return False;
        }
        return True;
    }

    # returns True if the workflow can be started, False if not
    bool testStartWorkflow(softstring id) {
        # only grab and release lock if we don't already own it
        bool have_lock = False;
        if (!rwl.lockOwner()) {
            rwl.readLock();
            have_lock = True;
        }
        on_exit if (have_lock)
            rwl.readUnlock();

        return testStartWorkflowUnlocked(id);
    }

    # throws an exception if the workflow cannot be started
    canStartWorkflow(softstring id) {
        AutoReadLock al(rwl);
        canStartWorkflowUnlocked(id);
    }

    # throws an exception if the service cannot be started
    private canStartServiceUnlocked(softstring id) {
        *hash<auto> svc = Qorus.qmm.lookupService(id, False);

        bool configured = Qorus.qmm.checkIfInterfaceIsConfigured(svc, "service");
        if (!configured) {
            rbaclog(LoggerLevel::INFO, "service %y is not configured", id);
            throw "SERVICE-NOT-CONFIGURED",
                   sprintf("cannot start %s service %s/%s (%d) because it is not properly configured",
                           svc.type, svc.name, svc.version, id);
        }

        foreach string name in (keys smap{id}) {
            if (!groups{name}.enabled) {
                throw "GROUP-DISABLED",
                      sprintf("cannot start %s service %s/%s (%d) because it is a member of disabled group %s (%s); "
                              "enable group %s by calling PUT /api/latest/groups/%s/enable to be able to start this "
                              "service", svc.type, svc.name, svc.version, id, name, groups{name}.getId(), name, name);
            }
        }
    }

    # returns True if the service can be started, False if not
    private bool testStartServiceUnlocked(softstring id) {
        *hash<auto> service = Qorus.qmm.lookupService(id, False);

        if (!Qorus.qmm.checkIfInterfaceIsConfigured(service, "service")) {
            return False;
        }

        foreach string name in (keys smap{id}) {
            if (!groups{name}.enabled)
                return False;
        }
        return True;
    }

    # returns True if the service can be started, False if not
    bool testStartService(softstring id) {
        # only grab and release lock if we don't already own it
        bool have_lock = False;
        if (!rwl.lockOwner()) {
            rwl.readLock();
            have_lock = True;
        }
        on_exit if (have_lock)
            rwl.readUnlock();

        return testStartServiceUnlocked(id);
    }

    # throws an exception if the service cannot be started
    canStartService(softstring id) {
        # only grab and release lock if we don't already own it
        bool have_lock = False;
        if (!rwl.lockOwner()) {
            rwl.readLock();
            have_lock = True;
        }
        on_exit if (have_lock)
            rwl.readUnlock();

        canStartServiceUnlocked(id);
    }

    # throws an exception if the job cannot be started
    private canStartJobUnlocked(softstring id) {
        *hash<auto> job = Qorus.qmm.lookupJob(id, False);

        bool configured = Qorus.qmm.checkIfInterfaceIsConfigured(job, "job");
        if (!configured) {
            throw "JOB-NOT-CONFIGURED",
                  sprintf("cannot start job %s/%s (%d) because it is not properly configured",
                          job.name, job.version, id);
        }

        foreach string name in (keys jmap{id}) {
            if (!groups{name}.enabled) {
                throw "GROUP-DISABLED",
                      sprintf("cannot start job %s/%s (%d) because it is a member of disabled group %s (%s); enable "
                              "group %s by calling PUT /api/latest/groups/%s/enable to be able to start this job",
                              job.name, job.version, id, name, groups{name}.getId(), name, name);
            }
        }
    }

    # returns True if the job can be started, False if not
    private bool testStartJobUnlocked(softstring id) {
        *hash<auto> job = Qorus.qmm.lookupJob(id, False);

        if (!Qorus.qmm.checkIfInterfaceIsConfigured(job, "job")) {
            return False;
        }

        foreach string name in (keys jmap{id}) {
            if (!groups{name}.enabled)
                return False;
        }
        return True;
    }

    # returns True if the job can be started, False if not
    bool testStartJob(softstring id) {
        # only grab and release lock if we don't already own it
        bool have_lock = False;
        if (!rwl.lockOwner()) {
            rwl.readLock();
            have_lock = True;
        }
        on_exit if (have_lock)
            rwl.readUnlock();

        return testStartJobUnlocked(id);
    }

    # throws an exception if the job cannot be started
    canStartJob(softstring id) {
        # only grab and release lock if we don't already own it
        bool have_lock = False;
        if (!rwl.lockOwner()) {
            rwl.readLock();
            have_lock = True;
        }
        on_exit if (have_lock)
            rwl.readUnlock();

        canStartJobUnlocked(id);
    }

    private enableUnlocked(Group g, *AtomicClassActionHelper atomic_action_helper, *Counter enable_counter) {
        CounterHolder ch(enable_counter);
        # if the group is already enabled, then do nothing
        if (g.enabled) {
            rbaclog(LoggerLevel::INFO, "group %s (%s) is already enabled", g.name, g.getId());
            return;
        }

        rbaclog(LoggerLevel::INFO, "enabling group %s (%s)", g.name, g.getId());

        g.enabled = True;

        # first, commit the new group status
        if (!g.isSynthetic())
            sqlif.commitGroupStatus(g.id, g.enabled);
        else
            RBAC::updateSyntheticGroupStatusSql(g, g.enabled);

        if (!atomic_action_helper) {
            atomic_action_helper = new AtomicMultiClassActionHelper(g.getAllInterfacesForAtomicAction());
        }

        enableUnlockedIntern(g, atomic_action_helper, ch.release());
    }

    private waitForAutostart(*hash<auto> cx, Group g, *Counter ec) {
        create_tld();
        # set thread call context info
        tld.cx = cx;

        if (ec) {
            # wait for autostart to be complete
            ec.waitForZero();
        }

        # clear any ongoing alert
        ActionReason r(cx, sprintf("group %s (%s) enabled", g.name, g.getId()));
        g.clearAlert(r);
    }

    private enableUnlockedIntern(Group g, AtomicClassActionHelper atomic_action_helper, *Counter enable_counter) {
        CounterHolder ch(enable_counter);
        QDBG_ASSERT(!enable_counter || enable_counter.getCount() == 1);
        Qorus.events.postGroupStatusChanged(g.name, True, g.getSyntheticInfo());

        # start any services that have their autostart flag and
        # are not in any other disabled groups
        if (g.services) {
            if (enable_counter) {
                enable_counter.inc();
            }
            atomic_action_helper.doBackgroundServices(keys g.services, \autoStartServices(), tld.cx, "enable", g,
                g.services, atomic_action_helper, enable_counter);
        }

        # start any active jobs that are not in any other disabled groups
        if (g.jobs) {
            if (enable_counter) {
                enable_counter.inc();
            }
            atomic_action_helper.doBackgroundJobs(keys g.jobs, \startJobs(), tld.cx, "enable", g, g.jobs,
                atomic_action_helper, enable_counter);
        }

        # start any workflows that have their autostart flag set and
        # are not in any other disabled groups
        if (g.workflows) {
            if (enable_counter) {
                enable_counter.inc();
            }
            atomic_action_helper.doBackgroundWorkflows(keys g.workflows, \autoStartWorkflows(), tld.cx, "enable", g,
                g.workflows, atomic_action_helper, enable_counter);
        }

        delete ch;

        # wait for autostart to complete then remove ongoing alert
        background waitForAutostart(tld.cx, g, enable_counter);
    }

    # must be called outside the write lock to avoid deadlocks when services make
    # calls to the server's HTTP interface because any call to RBAC::authenticateByIP()
    # would otherwise cause a deadlock
    private autoStartServices(*hash<auto> cx, string action, Group g, *hash<auto> idh,
            AtomicClassActionHelper atomic_action_helper, *Counter ec) {
        autoStartServices(cx, action, "enabled", sprintf("interface group %y (%s)", g.name, g.getId()), idh,
            atomic_action_helper, ec);
    }

    autoStartServices(*hash<auto> cx, string action, string adjective, string object_name, *hash<auto> idh,
                      AtomicClassActionHelper atomic_action_helper, *Counter ec) {
        create_tld();
        CounterHolder ch(ec);

        string startmsg = sprintf("restarting service due to %s %s", adjective, object_name);

        tld.cx = cx;
        foreach softint id in (keys idh) {
            try {
                # skip services that have already failed
                if (atomic_action_helper.check(AtomicClassActionHelper::C_Service, id)) {
                    continue;
                }

                *hash<auto> svc = Qorus.qmm.lookupService(id, False);
                if (!exists svc) {
                    rbaclog(LoggerLevel::INFO, "%s %s: ignoring unknown service id %d", action, object_name, id);
                    continue;
                }
                # ignore services that do not have the autostart flag set
                if (!svc.autostart)
                    continue;

                # check if we can start this service
                canStartService(id);

                # load/start the service
                try {
                    services.loadService(svc.type, svc.name, True, startmsg);
                } catch (hash<ExceptionInfo> ex) {
                    # log any error and continue
                    rbaclog(LoggerLevel::INFO, "%s %s: autostart %s service %s/%s (%d): %s: %s", action, object_name,
                        svc.type, svc.name, svc.version, id, ex.err, ex.desc);
                    atomic_action_helper.add(AtomicClassActionHelper::C_Service, id);
                    continue;
                }
            } catch (hash<ExceptionInfo> ex) {
                # handle "GROUP-DISABLED" exceptions
                if (ex.err == "GROUP-DISABLED")
                    rbaclog(LoggerLevel::INFO, "%s %s: autostart service: %s", action, object_name, ex.desc);
                else
                    rbaclog(LoggerLevel::INFO, "%s: autostart service: %s: %s: %s", action, get_ex_pos(ex), ex.err,
                        ex.desc);

                continue;
            }
        }
    }

    # must be called outside the write lock to avoid deadlocks when jobs make
    # calls to the server's HTTP interface because any call to RBAC::authenticateByIP()
    # would otherwise cause a deadlock
    private startJobs(*hash<auto> cx, string action, Group g, *hash<string, bool> idh,
            AtomicClassActionHelper atomic_action_helper, *Counter ec) {
        startJobs(cx, action, "enabled", sprintf("interface group %s (%s)", g.name, g.getId()), idh,
            atomic_action_helper, ec);
    }

    startJobs(*hash<auto> cx, string action, string adjective, string object_name, *hash<string, bool> idh,
              AtomicClassActionHelper atomic_action_helper, *Counter ec) {
        create_tld();
        CounterHolder ch(ec);

        string startmsg = sprintf("restarting job due to %s %s", adjective, object_name);

        tld.cx = cx;
        foreach softint id in (keys idh) {
            try {
                # skip jobs that have already failed
                if (atomic_action_helper.check(AtomicClassActionHelper::C_Job, id)) {
                    continue;
                }

                *hash<auto> job = Qorus.qmm.lookupJob(id, False);
                if (!exists job) {
                    rbaclog(LoggerLevel::INFO, "%s %s: ignoring unknown job id %d", action, object_name, id);
                    continue;
                }
                # ignore inactive jobs that do not have the autostart flag set
                if (!job.active)
                    continue;

                # check if we can start this job
                canStartJob(id);

                # start the job
                try {
                    Qorus.jobManager.startJob(job.name, startmsg);
                } catch (hash<ExceptionInfo> ex) {
                    # log any error and continue
                    rbaclog(LoggerLevel::INFO, "%s %s: start job %s/%s (%d): %s: %s", action, object_name, job.name,
                        job.version, id, ex.err, ex.desc);
                    atomic_action_helper.add(AtomicClassActionHelper::C_Job, id);
                    continue;
                }
            } catch (hash<ExceptionInfo> ex) {
                # handle "GROUP-DISABLED" exceptions
                if (ex.err == "GROUP-DISABLED")
                    rbaclog(LoggerLevel::INFO, "%s %s: start job: %s", action, object_name, ex.desc);
                else
                    rbaclog(LoggerLevel::INFO, "%s: start job: %s: %s: %s", action, get_ex_pos(ex), ex.err, ex.desc);

                continue;
            }
        }
    }

    # must be called outside the write lock to avoid deadlocks when workflows make
    # calls to the server's HTTP interface because any call to RBAC::authenticateByIP()
    # would otherwise cause a deadlock
    private autoStartWorkflows(*hash<auto> cx, string action, Group g, *hash<string, bool> idh,
                               AtomicClassActionHelper atomic_action_helper, *Counter ec) {
        autoStartWorkflows(cx, action, "enabled", sprintf("interface group %y (%s)", g.name, g.getId()), idh,
            atomic_action_helper, ec);
    }

    autoStartWorkflows(*hash<auto> cx, string action, string adjective, string object_name, *hash<string, bool> idh,
                       AtomicClassActionHelper atomic_action_helper, *Counter ec) {
        create_tld();
        CounterHolder ch(ec);

        string startmsg = sprintf("autostarting workflow due to %s %s", adjective, object_name);

        tld.cx = cx;
        foreach softint id in (keys idh) {
            try {
                # skip workflows that have already failed
                if (atomic_action_helper.check(AtomicClassActionHelper::C_Workflow, id)) {
                    continue;
                }

                *hash<auto> wf = Qorus.qmm.lookupWorkflow(id);
                if (!wf) {
                    rbaclog(LoggerLevel::INFO, "%s %s: ignoring unknown workflow id %d", action, object_name, id);
                    continue;
                }
                # ignore workflows that do not have the autostart value set (or have a negative autostart value)
                if (wf.autostart <= 0 || wf.depr) {
                    continue;
                }

                # check if we can start this workflow
                canStartWorkflow(id);

                # start n instances of the workflow
                try {
                    for (int i = 0; i < wf.autostart; ++i) {
                        QDBG_LOG("RBAC::autoStartWorkflows i = %y id = %y", i, id);
                        softint execid = Qorus.control.startWorkflowAtomic(cx, id, OMQ::WM_Normal, NOTHING, startmsg);
                        rbaclog(LoggerLevel::INFO, "autostarted workflow %s v%s (%d) %d/%d: exec ID %d", wf.name,
                            wf.version, id, i, wf.autostart, execid);
                    }
                } catch (hash<ExceptionInfo> ex) {
                    if (ex.err == "SHUTDOWN-IN-PROGRESS") {
                        rethrow;
                    }
                    # log any error and continue
                    rbaclog(LoggerLevel::INFO, "%s %s: autostart workflow %s v%s (%d): %s: %s", action, object_name,
                        wf.name, wf.version, id, ex.err, ex.desc);
                    atomic_action_helper.add(AtomicClassActionHelper::C_Workflow, id);
                    continue;
                }
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SHUTDOWN-IN-PROGRESS") {
                    rethrow;
                }
                # handle "GROUP-DISABLED" exceptions
                if (ex.err == "GROUP-DISABLED") {
                    rbaclog(LoggerLevel::INFO, "%s %s: autostart workflow: %s", action, object_name, ex.desc);
                } else {
                    rbaclog(LoggerLevel::INFO, "%s: autostart workflow: %s: %s: %s", action, get_ex_pos(ex), ex.err,
                        ex.desc);
                }

                continue;
            }
        }
    }

    private bool disableUnlocked(Group g, *AtomicClassActionHelper atomic_action_helper, *Counter done_counter) {
        CounterHolder ch(done_counter);
        # if the group is already disabled, then do nothing
        if (!g.enabled) {
            rbaclog(LoggerLevel::INFO, "group %s (%s) is already disabled", g.name, g.getId());
            return False;
        }

        rbaclog(LoggerLevel::INFO, "disabling group %s (%s)", g.name, g.getId());

        g.enabled = False;

        # first, commit the new group status
        if (!g.isSynthetic()) {
            sqlif.commitGroupStatus(g.id, g.enabled);
        } else {
            RBAC::updateSyntheticGroupStatusSql(g, g.enabled);
        }

        disableUnlockedIntern(g, atomic_action_helper, ch.release());
        return True;
    }

    private disableUnlockedIntern(Group g, *AtomicClassActionHelper atomic_action_helper, *Counter done_counter) {
        CounterHolder ch(done_counter);
        Qorus.events.postGroupStatusChanged(g.name, False, g.getSyntheticInfo());

        # raise ongoing alert before stopping interface objects to ensure that other alerts are shadowed
        {
            ActionReason r(tld.cx);
            g.raiseDisabledAlert(r);
        }

        # issue #2425: enable caller to wait until disable action is complete
        if (done_counter) {
            if (g.workflows) {
                done_counter.inc();
            }
            if (g.services) {
                done_counter.inc();
            }
            if (g.jobs) {
                done_counter.inc();
            }
            # decrement done_counter's original count
            delete ch;
        }

        # ensure atomic changes to interfaces
        if (!atomic_action_helper) {
            atomic_action_helper = new AtomicMultiClassActionHelper(keys g.workflows, keys g.services, keys g.jobs);
        }

        # stop all affected workflows
        if (g.workflows) {
            atomic_action_helper.doBackgroundWorkflows(keys g.workflows, \stopWorkflows(), "disable", g, g.workflows,
                atomic_action_helper, done_counter);
        }

        # stop all affected services
        # fix for bug 842: do not unload services with the RBAC write lock held
        if (g.services) {
            atomic_action_helper.doBackgroundServices(keys g.services, \stopServices(), "disable", g, g.services,
                atomic_action_helper, done_counter);
        }

        # stop all affected jobs
        if (g.jobs) {
            atomic_action_helper.doBackgroundJobs(keys g.jobs, \stopJobs(), "disable", g, g.jobs,
                atomic_action_helper, done_counter);
        }
    }

    # only called when the group is disabled
    private stopWorkflows(string action, Group g, hash<string, bool> idh,
            *AtomicClassActionHelper atomic_action_helper, *Counter done_counter) {
        QDBG_ASSERT(!g.enabled);
        stopWorkflows(action, "disabled", sprintf("interface group %s (%s)", g.name, g.getId()), idh,
            atomic_action_helper, done_counter);
    }

    # called when groups are disabled or when config item values are deleted
    stopWorkflows(string action, string adjective, string object_name, hash<string, bool> idh,
            *AtomicClassActionHelper atomic_action_helper, *Counter done_counter) {
        CounterHolder ch(done_counter);

        ensure_create_tld();
        string stopmsg = sprintf("stopping workflow due to %s %s", adjective, object_name);
        foreach string id in (keys idh) {
            *hash<auto> wf = Qorus.qmm.lookupWorkflow(id);
            # ignore unknown workflows
            if (!exists wf) {
                rbaclog(LoggerLevel::INFO, "%s %s: ignoring unknown workflow id %d", action, object_name, id);
                continue;
            }
            try {
                Qorus.control.stopWorkflowId(tld.cx + ("rbac_nocheck": True), id, NOTHING, stopmsg, True);
            } catch (hash<ExceptionInfo> ex) {
                rbaclog(LoggerLevel::INFO, "%s %s: error stopping all instances of workflow %s/%s (%d): %s: %s: %s",
                    action, object_name, wf.name, wf.version, id, get_ex_pos(ex), ex.err, ex.desc);
                continue;
            }
        }
    }

    private stopServices(string action, Group g, hash<string, bool> idh,
            *AtomicClassActionHelper atomic_action_helper, *Counter done_counter) {
        stopServices(action, "disabled", sprintf("interface group %y (%s)", g.name, g.getId()), idh,
            atomic_action_helper, done_counter);
    }

    stopServices(string action, string adjective, string object_name, hash<string, bool> idh,
            *AtomicClassActionHelper atomic_action_helper, *Counter done_counter) {
        CounterHolder ch(done_counter);
        create_tld();
        string stopmsg = sprintf("stopping service due to %s %s", adjective, object_name);
        foreach softint id in (keys idh) {
            *hash<auto> svc = Qorus.qmm.lookupService(id, False);
            if (!svc) {
                rbaclog(LoggerLevel::INFO, "%s %s: ignoring unknown service id %d", action, object_name, id);
                continue;
            }

            try {
                services.unloadService(svc.type, svc.name, NOTHING, True, stopmsg);
            } catch (hash<ExceptionInfo> ex) {
                # silently ignore SERVICE-NOT-LOADED errors
                if (ex.err == "SERVICE-NOT-LOADED")
                    continue;

                # log any other error and continue
                rbaclog(LoggerLevel::INFO, "%s %s: stop %s service %s/%s (%d): %s: %s", action, object_name, svc.type,
                    svc.name, svc.version, id, ex.err, ex.desc);
                continue;
            }
        }
    }

    private stopJobs(string action, Group g, hash<string, bool> idh, *AtomicClassActionHelper atomic_action_helper,
            *Counter done_counter) {
        stopJobs(action, "disabled", sprintf("interface group %y (%s)", g.name, g.getId()), idh, atomic_action_helper,
            done_counter);
    }

    stopJobs(string action, string adjective, string object_name, hash<string, bool> idh,
            *AtomicClassActionHelper atomic_action_helper, *Counter done_counter) {
        CounterHolder ch(done_counter);
        create_tld();
        string stopmsg = sprintf("stopping job due to %s %s", adjective, object_name);
        foreach softint id in (keys idh) {
            *hash<auto> j = Qorus.qmm.lookupJob(id, False);
            # ignore unknown workflows
            if (!j) {
                rbaclog(LoggerLevel::INFO, "%s %s: ignoring unknown jobid %d", action, object_name, id);
                continue;
            }

            try {
                Qorus.jobManager.stopJobID(id, stopmsg);
                # clear next job run date/time
                Qorus.qmm.clearJobNextTriggerTime(j.jobid, j.name);
            } catch (hash<ExceptionInfo> ex) {
                rbaclog(LoggerLevel::INFO, "%s %s: error stopping all instances of job %s/%s (%d): %s: %s", action,
                    object_name, j.name, j.version, id, ex.err, ex.desc);
                continue;
            }
        }
    }

    bool getSyntheticGroupStatus(string type, softstring id) {
        AutoReadLock al(rwl);

        *string name = sgmap{type}{id};
        if (!name)
            throw "GROUP-ERROR", sprintf("cannot enable or disable unknown %sid %d", type, id);

        if (!groups{name})
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);

        return groups{name}.enabled;
    }

    enableSyntheticGroup(string type, softstring id, *AtomicClassActionHelper atomic_action_helper,
            *Counter enable_counter) {
        CounterHolder ch(enable_counter);

        # FIXME: why can other groups be enabled during shutdown? --PQ 29-Aug-2016
        if (type == "workflow" && Qorus.shutting_down) {
            throw "SHUTDOWN-IN-PROGRESS", "cannot enable workflows because the system is shutting down";
        }

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        *string name = sgmap{type}{id};
        if (!name) {
            throw "GROUP-ERROR", sprintf("cannot enable or disable unknown %sid %d", type, id);
        }

        if (!groups{name}) {
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);
        }

        enableUnlocked(groups{name}, atomic_action_helper, ch.release());
    }

    enableGroup(string name) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName) {
            throw "ENABLE-GROUP-ERROR", "cannot enable or disable group \"DEFAULT\"";
        }

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name}) {
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);
        }

        enableUnlocked(groups{name});
    }

    enableGroupFromID(softstring id) {
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (!id) {
            throw "ENABLE-GROUP-ERROR", "cannot enable or disable group \"DEFAULT\"";
        }

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!gmap{id}) {
            throw "GROUP-ERROR", sprintf("groupid %d does not exist", id);
        }

        enableUnlocked(cast<Group>(groups.(gmap{id})));
    }

    # returns True if the group was enabled and is now disabled, False if the group was already disabled
    /** queues disable actions for execution in the background
        to wait until the action is complete, send the "done_counter" argument with a single increment
        and then call done_counter.waitForZero() after this method call returns
    */
    bool disableSyntheticGroupWait(string type, softstring id, *AtomicClassActionHelper atomic_action_helper) {
        Counter done_counter(1);
        bool rv = disableSyntheticGroup(type, id, atomic_action_helper, done_counter);
        done_counter.waitForZero();
        return rv;
    }

    # returns True if the group was enabled and is now disabled, False if the group was already disabled
    /** queues disable actions for execution in the background
        to wait until the action is complete, send the "done_counter" argument with a single increment
        and then call done_counter.waitForZero() after this method call returns
    */
    bool disableSyntheticGroup(string type, softstring id, *AtomicClassActionHelper atomic_action_helper,
            *Counter done_counter) {
        CounterHolder ch(done_counter);
        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        *string name = sgmap{type}{id};
        if (!name) {
            throw "GROUP-ERROR", sprintf("cannot enable or disable unknown %sid %d", type, id);
        }

        if (!groups{name}) {
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);
        }

        return disableUnlocked(groups{name}, atomic_action_helper, ch.release());
    }

    # queues disable actions for execution in the background
    /** to wait until the action is complete, send the "done_counter" argument with a single increment
        and then call done_counter.waitForZero() after this method call returns
    */
    disableGroup(string name, *Counter done_counter) {
        CounterHolder ch(done_counter);
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (name == DefaultGroupName) {
            throw "DISABLE-GROUP-ERROR", "cannot enable or disable group \"DEFAULT\"";
        }

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!groups{name}) {
            throw "GROUP-ERROR", sprintf("group '%s' does not exist", name);
        }

        disableUnlocked(groups{name}, NOTHING, ch.release());
    }

    # queues disable actions for execution in the background
    /** to wait until the action is complete, send the "done_counter" argument with a single increment
        and then call done_counter.waitForZero() after this method call returns
    */
    disableGroupFromID(softstring id, *Counter done_counter) {
        CounterHolder ch(done_counter);
        # fix for bug 559: do not allow group "DEFAULT" to be manipulated
        if (!id) {
            throw "DISABLE-GROUP-ERROR", "cannot enable or disable group \"DEFAULT\"";
        }

        # NOTE: no need to wait for service initialization here as the atomic change solution ensures that there will
        #       be no deadlocks

        AutoWriteLock al(rwl);

        if (!exists gmap{id}) {
            throw "GROUP-ERROR", sprintf("groupid %d does not exist", id);
        }

        disableUnlocked(cast<Group>(groups.(gmap{id})), NOTHING, ch.release());
    }

    *hash addServiceGroupInfo(*hash h) {
        bool l = !rwl.lockOwner();
        if (l) rwl.readLock();
        on_exit if (l) rwl.readUnlock();

        foreach string id in (keys h)
            h{id}.groups = map groups.$1.("name", "enabled", "size"), keys smap{id};

        return h;
    }

    *hash addJobGroupInfo(*hash h) {
        bool l = !rwl.lockOwner();
        if (l) rwl.readLock();
        on_exit if (l) rwl.readUnlock();

        foreach string id in (keys h) {
            softstring jobid = h{id}.jobid;
            h{jobid}.groups = map groups.$1.("name", "enabled", "size"), keys jmap{jobid};
        }

        return h;
    }

    *hash addJobGroupInfoByName(*hash h) {
        bool l = !rwl.lockOwner();
        if (l) rwl.readLock();
        on_exit if (l) rwl.readUnlock();

        foreach string id in (keys h) {
            softstring jobid = h{id}.jobid;
            h.(h{id}.name).groups = map groups.$1.("name", "enabled", "size"), keys jmap{jobid};
        }

        return h;
    }

    *list addMapperGroupInfo(*list l) {
        bool lck = !rwl.lockOwner();
        if (lck) rwl.readLock();
        on_exit if (lck) rwl.readUnlock();

        foreach hash h in (\l) {
            h.groups = map groups.$1.("name", "enabled", "size"), keys mmap{h.mapperid};
        }

        return l;
    }

    *list addVMapGroupInfo(*list l) {
        bool lck = !rwl.lockOwner();
        if (lck) rwl.readLock();
        on_exit if (lck) rwl.readUnlock();

        foreach hash h in (\l) {
            h.groups = map groups.$1.("name", "enabled", "size"), keys vmap{h.id};
        }

        return l;
    }

    *list addFsmGroupInfo(*list l) {
        bool lck = !rwl.lockOwner();
        if (lck) rwl.readLock();
        on_exit if (lck) rwl.readUnlock();

        foreach hash h in (\l) {
            h.groups = map groups.$1.("name", "enabled", "size"), keys fsmmap{h.id};
        }

        return l;
    }

    *list addPipelineGroupInfo(*list l) {
        bool lck = !rwl.lockOwner();
        if (lck) rwl.readLock();
        on_exit if (lck) rwl.readUnlock();

        foreach hash h in (\l) {
            h.groups = map groups.$1.("name", "enabled", "size"), keys pipemap{h.id};
        }

        return l;
    }

    private *list getObjectGroups(string mapname, string id) {
        bool l = !rwl.lockOwner();
        if (l) rwl.readLock();
        on_exit if (l) rwl.readUnlock();

        # issue 1774: do not include synthetic groups in groups
        return map groups.$1.("name", "enabled", "size"), keys self{mapname}{id}, groups.$1.id > 0;
    }

    *list getWorkflowGroups(softstring id) {
        return getObjectGroups("wmap", id);
    }

    *list getServiceGroups(softstring id) {
        return getObjectGroups("smap", id);
    }

    *list getJobGroups(softstring id) {
        return getObjectGroups("jmap", id);
    }

    *list getMapperGroups(softstring id) {
        return getObjectGroups("mmap", id);
    }

    *list getVMapGroups(softstring id) {
        return getObjectGroups("vmap", id);
    }

    *list getFsmGroups(string id) {
        return getObjectGroups("fsmmap", id);
    }

    *list getPipelineGroups(string id) {
        return getObjectGroups("pipemap", id);
    }

    *list<hash<auto>> addWorkflowGroupsAndAlerts(*list<hash<auto>> wfl) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        foreach hash<auto> h in (\wfl) {
            h += {
                # issue #1895 do not include synthetic groups in groups
                "groups": (map groups.$1.("name", "enabled", "size"), keys wmap.(h.workflowid), groups.$1.id > 0),
                "alerts": Qorus.alerts.getAlerts("WORKFLOW", h.workflowid),
                "enabled": groups.(sgmap."workflow".(h.workflowid)).enabled,
            };
        }

        return wfl;
    }

    *list<hash<auto>> addServiceStatus(*list<hash<auto>> sl) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        foreach hash<auto> h in (\sl) {
            h.enabled = groups.(sgmap."service".(h.serviceid)).enabled;
        }

        return sl;
    }
}

class CounterHolder {
    private {
        *Counter cnt;
    }

    constructor() {}

    constructor(Counter cnt) {
        self.cnt = cnt;
    }

    destructor() {
        if (cnt) {
            #QDBG_LOG("CounterHolder::destructor() %y %d -> %d", cnt.uniqueHash(), cnt.getCount(), cnt.getCount() - 1);
            cnt.dec();
        }
    }

    *Counter release() {
        return remove cnt;
    }
}
