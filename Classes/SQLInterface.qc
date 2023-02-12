# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%try-module oracle
%define NO_ORACLE
%endtry

%new-style

public namespace OMQ {
    public class SQLInterface {
        public {
            AbstractDatasource omqp;
            # separate dedicated datasource used for audit logging, only initialized if auditing is enabled
            Datasource omqa;

            # it's a public constant to be reused in tests
            const SNAPSHOTS = {
                "workflow_instance" : {
                    "columns" : (
                        "workflowid",
                        "workflowstatus",
                        SqlUtil::cop_as(SqlUtil::cop_trunc_date("modified", SqlUtil::DT_HOUR), "modified"),
                        SqlUtil::cop_as(SqlUtil::cop_count(), "total_count"),
                    ),
                    "groupby" : (
                        "workflowid",
                        "workflowstatus",
                        # Note: this is tricky. cop_as makes "modifed" an alias for cop_trunc_date already.
                        #       No need to trunc it with cop operator here.
                        "modified",
                    ),
                },
                "job_instance" : {
                    "columns" : (
                        "jobid",
                        "jobstatus",
                        SqlUtil::cop_as(SqlUtil::cop_trunc_date("modified", SqlUtil::DT_HOUR), "modified"),
                        SqlUtil::cop_as(SqlUtil::cop_count(), "total_count"),
                    ),
                    "groupby" : (
                        "jobid",
                        "jobstatus",
                        # Note: this is tricky. cop_as makes "modifed" an alias for cop_trunc_date already.
                        #       No need to trunc it with cop operator here.
                        "modified",
                    )
                },
            };
        }

        private {
            string encoding;

            # to minimize concurrent access to snapshots
            hash m_snapshotMutexes = {
                "workflow_instance" : new Mutex(),
                "job_instance" : new Mutex(),
            };
        }

        constructor(AbstractDatasource n_omqp) {
            omqp = n_omqp;
            encoding = omqp.getOSEncoding();
        }

        initAuditDatasource() {
            omqa = new Datasource(omqp.getConfigHash());
            omqa.setAutoCommit(True);
        }

        commit() {
            omqp.commit();
        }

        rollback() {
            omqp.rollback();
        }

        bool inTransaction() {
            return omqp.inTransaction();
        }

        # takes an exception hash and returns True if the error is related to the fact that the transaction should be restarted (ex: cluster failover error)
        bool restartTransaction(hash<auto> ex) {
            return checkRestartTransaction(ex);
        }

        # takes an exception hash and returns True if the error is related to the fact that the transaction should be restarted (ex: cluster failover error)
        bool checkRestartTransaction(hash<auto> ex) {
            while (True) {
                if (ex.err == "DATASOURCEPOOL-PROCESS-ERROR"
                    || ex.err == "DATASOURCEPOOL-TIMEOUT"
                    || checkRestartTransactionImpl(ex)) {
                    return True;
                }
                if (!ex.next) {
                    break;
                }
                ex = ex.next;
            }
            return False;
        }

        private checkOrderKeys(string key, string value, *bool truncate) {
            if (key.strlen() > ORDER_INSTANCE_KEYS_KEY_LEN)
                throw "ORDER-KEY-ERROR", sprintf("order keys may not be longer than %d characters; the key passed (%y) has a length of %d", ORDER_INSTANCE_KEYS_KEY_LEN, key, key.strlen());
            if (key.empty())
                throw "ORDER-KEY-ERROR", sprintf("an invalid zero-length order key was given with value %y", value);

            if (truncate) {
                value = trunc_str(value, ORDER_INSTANCE_KEYS_VALUE_LEN, encoding);
                return;
            }

            if (strlen(value) > ORDER_INSTANCE_KEYS_VALUE_LEN)
                throw "ORDER-KEY-ERROR", sprintf("order key values may not be longer than %d characters; the value (%y) for the key passed (%y) has a length of %d", ORDER_INSTANCE_KEYS_VALUE_LEN, value, key, strlen(value));
        }

        softbool insertOrderKey(softint wfid, softint wfiid, string key, softstring value, bool truncate) {
            checkOrderKeys(key, value, truncate);
            return omqp.exec("insert into order_instance_keys (workflow_instanceid, keyname, value, workflowid) values (%v, %v, %v, %v)", wfiid, key, string(value), wfid);
        }

        int createWorkflowInstance(softint wfid, softint sessionid = 0, *softint pwfiid, bool subworkflow, *hash<auto> staticdata, *hash<auto> dynamicdata, *hash<auto> sensitive_data, *softstring eoiid, int priority, *softdate scheduled, softint sync = 0, string status = OMQ::StatReady) {
            # save new order data to DB
            string sdata = serialize_qorus_data(staticdata);
            string ddata = serialize_qorus_data(dynamicdata);

            if (status == OMQ::StatReady && scheduled > now())
                status = OMQ::StatScheduled;
            else if (status == OMQ::StatScheduled && scheduled < now())
                status = OMQ::StatReady;

            string wfstatus = OMQ::StatMap{status};
            any wf_status_orig;
            if (status == OMQ::StatBlocked)
                wf_status_orig = scheduled > now() ? OMQ::SQLStatScheduled : OMQ::SQLStatReady;
            else
                wf_status_orig = NULL;

            try {
                int wfiid = createWorkflowInstanceImpl(wfid, sessionid, pwfiid, subworkflow, sdata, ddata, eoiid, priority, scheduled, sync, wfstatus, wf_status_orig);
                # save any sensitive data
                foreach hash<auto> skh in (sensitive_data.pairIterator()) {
                    foreach hash<auto> svh in (skh.value.pairIterator()) {
                        hash<auto> eh = encrypt_order_data(wfiid, skh.key, svh.key, svh.value."data", svh.value.meta);
                        # save row
                        omqp.exec("insert into sensitive_order_data (workflow_instanceid, skey, svalue, data, iv, mac, meta, miv, mmac) values (%v, %v, %v, %v, %v, %v, %v, %v, %v)",
                                wfiid, skh.key, eh.svalue, eh."data", eh.iv, eh.mac, eh.meta, eh.miv, eh.mmac);

                        # insert aliases
                        map omqp.exec("insert into sensitive_order_data_keys (workflow_instanceid, skey, svalue, alias) values (%v, %v, %v, %v)",
                                    wfiid, skh.key, eh.svalue, $1), svh.value.aliases;
                    }
                }
                return wfiid;
            } catch (hash<ExceptionInfo> ex) {
                throw ex.err, sprintf("%s: create workflow instance error (workflow_id: %d sessionid: %d, parent_workflow_instanceid: %y, subworkflow: %d, staticdata: %d byte%s, dynamicdata: %d byte%s, external_order_instanceid: %d, priority: %d, scheduled: %y, synchronous: %d, status: %s): %s", get_ex_pos(ex), wfid, sessionid, pwfiid, subworkflow, sdata.size(), sdata.size() == 1 ? "" : "s", ddata.size(), ddata.size() == 1 ? "" : "s", eoiid, priority, scheduled, sync, status, ex.desc);
            }
        }

        int createWorkflowInstanceImpl(softint wfid, softint sessionid = 0, *softint pwfiid, bool subworkflow, string sdata, string ddata, *softstring eoiid, int priority, *softdate scheduled, softint sync = 0, string wfstatus, auto wf_status_orig) {
            # get workflow instance ID
            int wfiid = getNextSequenceValue("seq_workflow_instance");

            # create workflow_instance row
            omqp.exec("insert into workflow_instance
                            (workflow_instanceid, workflowid, workflowstatus, workflowstatus_orig,
                            status_sessionid, parent_workflow_instanceid, subworkflow, synchronous, scheduled,
                            priority)
                        values (%v, %v, %v, %v, %v, %v, %v, %v, %v, %v)",
                        wfiid, wfid, wfstatus, wf_status_orig,
                        sessionid, pwfiid, subworkflow ? 1 : NULL, sync, scheduled,
                        priority);
            # insert order data
            omqp.exec("insert into order_instance (workflow_instanceid, external_order_instanceid, staticdata, dynamicdata) values (%v, %v, %v, %v)", int(wfiid), eoiid, sdata, ddata);

            return wfiid;
        }

        *hash<auto> getTags(string t, softint id) {
            *hash<auto> h;
            foreach hash<auto> row in (omqp.select("select tag, value from %s_tags where %sid = %v", t, t, id).contextIterator()) {
                if (row.tag =~ /^_/) {
                    splice row.tag, 0, 1;
                    h.sys.(row.tag) = row.value;
                } else
                    h.(row.tag) = row.value;
            }

            return h;
        }

        # Session
        # issue #2304: if we are recovering a session, then ensure that all orders for workflows previously
        # running in a separate process with open = 1 where remote is now = 0 are recovered immediately
        int sessionRecoverUpdatedWorkflows(hash<string, bool> rwfh) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    AbstractTable workflows = get_sql_table_system(omqp, "workflows");

                    return workflows.update({"open": 0}, {"open": 1, "remote": 0, "workflowid": op_not(op_in((map $1.toInt(), keys rwfh)))});
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        hash<auto> sessionRecoverInit(softint sid, *int wfid) {
            return wfid
                ? omqp.selectRow("select min(workflow_instanceid) as \"minimum\",
                                        max(workflow_instanceid) as \"maximum\",
                                        count(1) as r_count
                                from workflow_instance wi, workflows w
                                where
                                    wi.workflowid = w.workflowid
                                    and status_sessionid = %v
                                    and w.workflowid = %v",
                                  sid, wfid)
                : omqp.selectRow("select min(workflow_instanceid) as \"minimum\",
                                        max(workflow_instanceid) as \"maximum\",
                                        count(1) as r_count
                                from workflow_instance wi, workflows w
                                where
                                    wi.workflowid = w.workflowid
                                    and status_sessionid = %v
                                    and w.open = 0",
                                  sid);
        }

        # update old session status to recovered
        sessionRecoverFinalize(softint sid) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update sessions set sessionstatus = 'RECOVERED' where sessionid = %v", sid);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        auditSessionPartRecoveryNoCommit(Audit audit, string trigger, int sid, *int wfid, softint min, softint max) {
            if (audit.checkOption(AOC_WORKFLOW_DATA)) {
                *hash<auto> q = wfid
                    ? omqp.select("select w.workflowid, workflow_instanceid, workflowstatus from workflow_instance wi, workflows w where wi.workflowid = w.workflowid and status_sessionid = %v and workflow_instanceid >= %v and workflow_instanceid <= %v and w.workflowid = %v", sid, min, max, wfid)
                    : omqp.select("select w.workflowid, workflow_instanceid, workflowstatus from workflow_instance wi, workflows w where wi.workflowid = w.workflowid and status_sessionid = %v and workflow_instanceid >= %v and workflow_instanceid <= %v and w.open = 0", sid, min, max);

                context (q) {
                    audit.workflowRecoveryNoCommit(%workflowid, %workflow_instanceid, %workflowstatus, trigger);
                }
            }
        }

        hash<WorkflowRecoveryInfo> sessionRecoverPart(softint sid, *int wfid, softint min, softint max, Audit audit, string trigger) {
            hash<WorkflowRecoveryInfo> ret();
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    # update all IN-PROGRESS steps with this sessionid to RETRY
                    ret.count = wfid
                        ? omqp.exec("update step_instance
                                            set stepstatus = 'R' where stepstatus = 'I'
                                            and workflow_instanceid in (select workflow_instanceid
                                                from workflow_instance where workflowstatus = 'I'
                                                and status_sessionid = %v
                                                and workflow_instanceid >= %v
                                                and workflow_instanceid <= %v
                                                and workflowid = %v)", sid, min, max, wfid)
                        : omqp.exec("update step_instance
                                            set stepstatus = 'R' where stepstatus = 'I'
                                            and workflow_instanceid in (select workflow_instanceid
                                                from workflow_instance where workflowstatus = 'I'
                                                and status_sessionid = %v
                                                and workflow_instanceid >= %v
                                                and workflow_instanceid <= %v
                                                and workflowid in
                                                    (select workflowid from workflows where open = 0))", sid, min, max);

                    # update all IN-PROGRESS segments with this sessionid to RETRY
                    ret.sgcount = wfid
                        ? omqp.exec("update segment_instance set segmentstatus = 'R'
                                            where workflow_instanceid in (select workflow_instanceid
                                            from workflow_instance where workflowstatus = 'I'
                                            and status_sessionid = %v
                                            and workflow_instanceid >= %v
                                            and workflow_instanceid <= %v
                                            and workflowid = %v)", sid, min, max, wfid)
                        : omqp.exec("update segment_instance set segmentstatus = 'R'
                                            where workflow_instanceid in (select workflow_instanceid
                                            from workflow_instance where workflowstatus = 'I'
                                            and status_sessionid = %v
                                            and workflow_instanceid >= %v
                                            and workflow_instanceid <= %v
                                            and workflowid not in
                                                (select workflowid from workflows where open = 1))", sid, min, max);

                    # audit each recovered workflow if the option is set
                    auditSessionPartRecoveryNoCommit(audit, trigger, sid, wfid, min, max);

                    # update all IN-PROGRESS workflows with this sessionid to RETRY
                    ret.wcount = wfid
                        ? omqp.exec("update workflow_instance set workflowstatus = 'R', status_sessionid = 0,
                                            synchronous = 0 where workflowstatus = 'I' and status_sessionid = %v
                                                and workflow_instanceid >= %v
                                                and workflow_instanceid <= %v
                                                and workflowid = %v", sid, min, max, wfid)
                        : omqp.exec("update workflow_instance set workflowstatus = 'R', status_sessionid = 0,
                                            synchronous = 0 where workflowstatus = 'I' and status_sessionid = %v
                                                and workflow_instanceid >= %v
                                                and workflow_instanceid <= %v
                                                and workflowid in
                                                    (select workflowid from workflows where open = 0)", sid, min, max);
                    ret.wcount += wfid
                        ? omqp.exec("update workflow_instance set status_sessionid = 0
                                                    where status_sessionid = %v
                                                    and workflow_instanceid >= %v
                                                    and workflow_instanceid <= %v
                                                    and workflowid = %v", sid, min, max, wfid)
                        : omqp.exec("update workflow_instance set status_sessionid = 0
                                                    where status_sessionid = %v
                                                    and workflow_instanceid >= %v
                                                    and workflow_instanceid <= %v
                                                    and workflowid in
                                                        (select workflowid from workflows where open = 0)", sid, min, max);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }

            return ret;
        }

        *hash sessionCheckSystemProperties() {
            return omqp.select("select * from system_properties where domain = 'omq'");
        }

        *list sessionOpen1() {
            # check for still open sessions
            return omqp.selectRows("select * from sessions where sessionstatus = 'ACTIVE'");
        }

        # there will never be a large number of jobs to recover, so we don't even try to divide this up
        hash<JobRecoveryInfo> recoverJobs(softint sid, Audit audit, string trigger, *int jobid) {
            hash<JobRecoveryInfo> h;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    if (audit.checkOption(AOC_JOB_DATA)) {
                        *hash<auto> q = jobid
                            ? omqp.select("select jobid, job_instanceid from job_instance where sessionid = %v and "
                                "jobid = %v", sid, jobid)
                            : omqp.select("select jobid, job_instanceid from job_instance where sessionid = %v", sid);
                        context (q) {
                            audit.jobRecoveryNoCommit(%jobid, %job_instanceid, trigger);
                        }
                        q = jobid
                            ? omqp.select("select jobid from jobs where sessionid = %v and jobid = %v", sid, jobid)
                            : omqp.select("select jobid from jobs where sessionid = %v", sid);
                        context (q) {
                            audit.jobRecoveryNoCommit(%jobid, NOTHING, trigger);
                        }
                    }

                    h = jobid
                        ? hash<JobRecoveryInfo>{
                            # recover job instances and get count
                            "jcount": omqp.exec("update job_instance set jobstatus = 'Z', sessionid = 0 where "
                                "jobstatus = 'I' and sessionid = %v and jobid = %v", sid, jobid),
                            # recover job record and get count
                            "jrcount": omqp.exec("update jobs set sessionid = 0 where sessionid = %v and jobid = %v",
                                sid, jobid),
                        }
                        : hash<JobRecoveryInfo>{
                            # recover job instances and get count
                            "jcount": omqp.exec("update job_instance set jobstatus = 'Z', sessionid = 0 where "
                                "jobstatus = 'I' and sessionid = %v", sid),
                            # recover job records and get count
                            "jrcount": omqp.exec("update jobs set sessionid = 0 where sessionid = %v", sid),
                        };
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex)) {
                        continue;
                    }
                    rethrow;
                }
                break;
            }
            return h;
        }

        #! creates a group in the DB
        int addGroup(string group, *string desc, softbool enabled = True, *list<auto> wf_cmds, *list<auto> svc_cmds,
                *list<auto> job_cmds, *list<auto> mapper_cmds, *list<auto> vmap_cmds, *list<auto> fsm_cmds,
                *list<auto> pipeline_cmds) {
            int id;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    id = createGroup(group, desc, enabled);

                    map omqp.exec("insert into group_workflows (groupid, workflowid) values (%v, %v)", id, $1.arg), wf_cmds;
                    map omqp.exec("insert into group_services (groupid, serviceid) values (%v, %v)", id, $1.arg), svc_cmds;
                    map omqp.exec("insert into group_jobs (groupid, jobid) values (%v, %v)", id, $1.arg), job_cmds;
                    map omqp.exec("insert into group_mappers (groupid, mapperid) values (%v, %v)", id, $1.arg), mapper_cmds;
                    map omqp.exec("insert into group_vmaps (groupid, id) values (%v, %v)", id, $1.arg), vmap_cmds;
                    map omqp.exec("insert into group_fsms (groupid, fsm) values (%v, %v)", id, $1.arg), fsm_cmds;
                    map omqp.exec("insert into group_pipelines (groupid, pipeline) values (%v, %v)", id, $1.arg), pipeline_cmds;
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }

            return id;
        }

        *hash getGroups() {
            return omqp.select("select * from groups");
        }

        *hash getGroupServices() {
            return omqp.select("select * from group_services");
        }

        *hash getGroupWorkflows() {
            return omqp.select("select * from group_workflows");
        }

        *hash getGroupJobs() {
            return omqp.select("select * from group_jobs");
        }

        *hash getGroupMappers() {
            return omqp.select("select * from group_mappers");
        }

        *hash<auto> getGroupVMaps() {
            return omqp.select("select * from group_vmaps");
        }

        *hash<auto> getGroupFsms() {
            return omqp.select("select * from group_fsms");
        }

        *hash<auto> getGroupPipelines() {
            return omqp.select("select * from group_pipelines");
        }

        int createGroup(string name, string description, bool enabled = True) {
            int id = getNextSequenceValue("seq_groups");

            omqp.exec("insert into groups (groupid, name, description, enabled) values (%v, %v, %v, %v)", id, name, description, int(enabled));
            return id;
        }

        addServicesToGroup(softint id, auto svcids) {
            map omqp.exec("insert into group_services (groupid, serviceid) values (%v, %v)", id, $1.toInt()), svcids;
        }

        addWorkflowsToGroup(softint id, auto wfids) {
            map omqp.exec("insert into group_workflows (groupid, workflowid) values (%v, %v)", id, $1.toInt()), wfids;
        }

        addJobsToGroup(softint id, auto jids) {
            map omqp.exec("insert into group_jobs (groupid, jobid) values (%v, %v)", id, $1), jids;
        }

        addMappersToGroup(softint id, auto mids) {
            map omqp.exec("insert into group_mappers (groupid, mapperid) values (%v, %v)", id, $1), mids;
        }

        addVMapsToGroup(softint id, auto vmids) {
            map omqp.exec("insert into group_vmaps (groupid, id) values (%v, %v)", id, $1), vmids;
        }

        addFsmsToGroup(softint id, auto fsms) {
            map omqp.exec("insert into group_fsms (groupid, fsm) values (%v, %v)", id, $1), fsms;
        }

        addPipelinesToGroup(softint id, auto pipelines) {
            map omqp.exec("insert into group_pipelines (groupid, pipeline) values (%v, %v)", id, $1), pipelines;
        }

        hash deleteGroup(softint id) {
            hash h;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    on_success
                        omqp.exec("delete from groups where groupid = %v", id);

                    h = {
                        "workflows": omqp.exec("delete from group_workflows where groupid = %v", id),
                        "services": omqp.exec("delete from group_services where groupid = %v", id),
                        "jobs": omqp.exec("delete from group_jobs where groupid = %v", id),
                        "mappers": omqp.exec("delete from group_mappers where groupid = %v", id),
                        "vmaps": omqp.exec("delete from group_vmaps where groupid = %v", id),
                        "fsms": omqp.exec("delete from group_fsms where groupid = %v", id),
                        "pipelines": omqp.exec("delete from group_pipelines where groupid = %v", id),
                    };
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
            return h;
        }

        deleteServicesFromGroup(softint id, auto svcids) {
            map omqp.exec("delete from group_services where groupid = %v and serviceid = %v", id, $1.toInt()), svcids;
        }

        deleteWorkflowsFromGroup(softint id, auto wfids) {
            map omqp.exec("delete from group_workflows where groupid = %v and workflowid = %v", id, $1.toInt()), wfids;
        }

        deleteJobsFromGroup(softint id, auto jids) {
            map omqp.exec("delete from group_jobs where groupid = %v and jobid = %v", id, $1), jids;
        }

        deleteMappersFromGroup(softint id, auto mids) {
            map omqp.exec("delete from group_mappers where groupid = %v and mapperid = %v", id, $1), mids;
        }

        deleteVMapsFromGroup(softint id, auto vmids) {
            map omqp.exec("delete from group_vmaps where groupid = %v and id = %v", id, $1), vmids;
        }

        deleteFsmsFromGroup(softint id, auto names) {
            map omqp.exec("delete from group_fsms where groupid = %v and fsm = %v", id, $1), names;
        }

        deletePipelinesFromGroup(softint id, auto names) {
            map omqp.exec("delete from group_pipelines where groupid = %v and pipeline = %v", id, $1), names;
        }

        #! updates an RBAC group in the DB
        updateGroup(int id, *string desc, *bool enabled, *list<auto> wf_cmds, *list<auto> svc_cmds,
                *list<auto> job_cmds, *list<auto> mapper_cmds, *list<auto> vmap_cmds, *list<auto> fsm_cmds,
                *list<auto> pipeline_cmds) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    foreach hash cmd in (wf_cmds) {
                        if (cmd.action == "add")
                            omqp.exec("insert into group_workflows (groupid, workflowid) values (%v, %v)", id, cmd.arg);
                        else if (cmd.action == "delete-all")
                            omqp.exec("delete from group_workflows where groupid = %v", id);
                        else
                            omqp.exec("delete from group_workflows where groupid = %v and workflowid = %v", id, cmd.arg);
                    }

                    foreach hash cmd in (svc_cmds) {
                        if (cmd.action == "add")
                            omqp.exec("insert into group_services (groupid, serviceid) values (%v, %v)", id, cmd.arg);
                        else if (cmd.action == "delete-all")
                            omqp.exec("delete from group_services where groupid = %v", id);
                        else
                            omqp.exec("delete from group_services where groupid = %v and serviceid = %v", id, cmd.arg);
                    }

                    foreach hash cmd in (job_cmds) {
                        if (cmd.action == "add")
                            omqp.exec("insert into group_jobs (groupid, jobid) values (%v, %v)", id, cmd.arg);
                        else if (cmd.action == "delete-all")
                            omqp.exec("delete from group_jobs where groupid = %v", id);
                        else
                            omqp.exec("delete from group_jobs where groupid = %v and jobid = %v", id, cmd.arg);
                    }

                    foreach hash cmd in (mapper_cmds) {
                        if (cmd.action == "add")
                            omqp.exec("insert into group_mappers (groupid, mapperid) values (%v, %v)", id, cmd.arg);
                        else if (cmd.action == "delete-all")
                            omqp.exec("delete from group_mappers where groupid = %v", id);
                        else
                            omqp.exec("delete from group_mappers where groupid = %v and mapperid = %v", id, cmd.arg);
                    }

                    foreach hash cmd in (vmap_cmds) {
                        if (cmd.action == "add")
                            omqp.exec("insert into group_vmaps (groupid, id) values (%v, %v)", id, cmd.arg);
                        else if (cmd.action == "delete-all")
                            omqp.exec("delete from group_vmaps where groupid = %v", id);
                        else
                            omqp.exec("delete from group_vmaps where groupid = %v and id = %v", id, cmd.arg);
                    }

                    foreach hash<auto> cmd in (fsm_cmds) {
                        if (cmd.action == "add")
                            omqp.exec("insert into group_fsms (groupid, fsm) values (%v, %v)", id, cmd.arg);
                        else if (cmd.action == "delete-all")
                            omqp.exec("delete from group_fsms where groupid = %v", id);
                        else
                            omqp.exec("delete from group_fsms where groupid = %v and fsm = %v", id, cmd.arg);
                    }

                    foreach hash<auto> cmd in (pipeline_cmds) {
                        if (cmd.action == "add")
                            omqp.exec("insert into group_pipelines (groupid, pipeline) values (%v, %v)", id, cmd.arg);
                        else if (cmd.action == "delete-all")
                            omqp.exec("delete from group_pipelines where groupid = %v", id);
                        else
                            omqp.exec("delete from group_pipelines where groupid = %v and pipeline = %v", id, cmd.arg);
                    }

                    # update enabled and description
                    if (desc && exists enabled)
                        omqp.exec("update groups set description = %v, enabled = %v where groupid = %v", desc, int(enabled), id);
                    else if (desc) # update group description
                        omqp.exec("update groups set description = %v where groupid = %v", desc, id);
                    else if (exists enabled) # update enabled flag
                        omqp.exec("update groups set enabled = %v where groupid = %v", int(enabled), id);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        int logAudit(*int rid, *int wfid, *int wfiid, *int stepid, *int ind, *int jid, *int jiid, *int sid, *int audit_event_code, *string user_event_code, *string reason = "internal call", *string who, *string source, *string info1, *string info2) {
            int id = getNextSequenceValue("seq_audit_eventid");
            omqp.exec("insert into audit_events (audit_eventid, related_audit_eventid, workflowid, workflow_instanceid, stepid, ind, jobid, job_instanceid, serviceid, audit_event_code, audit_user_event, reason, who, source, info1, info2) values (%v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v)", id, rid, wfid, wfiid, stepid, ind, jid, jiid, sid, audit_event_code, user_event_code, reason, who, source, info1, info2);
            return id;
        }

        int logAuditCommit(*int rid, *int wfid, *int wfiid, *int stepid, *int ind, *int jid, *int jiid, *int sid, *int audit_event_code, *string user_event_code, *string reason = "internal call", *string who, *string source, *string info1, *string info2) {
            int id = getNextSequenceValue("seq_audit_eventid");
            omqa.exec("insert into audit_events (audit_eventid, related_audit_eventid, workflowid, workflow_instanceid, stepid, ind, jobid, job_instanceid, serviceid, audit_event_code, audit_user_event, reason, who, source, info1, info2) values (%v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v, %v)", id, rid, wfid, wfiid, stepid, ind, jid, jiid, sid, audit_event_code, user_event_code, reason, who, source, info1, info2);
            return id;
        }

        #! refresh one particular snapshot
        private int refreshSnapshot(string table_base)
        {
            AutoLock al(m_snapshotMutexes{table_base});
            int ret;
            hash sh = SNAPSHOTS{table_base};

            # live table
            SqlUtil::AbstractTable t_src = get_sql_table_system(omqp, table_base);
            # stats snapshot
            SqlUtil::AbstractTable t_tgt = get_sql_table_system(omqp, table_base + "_stats");
            # snapshot's stage table
            SqlUtil::AbstractTable t_stg = get_sql_table_system(omqp, table_base + "_stats_stage");

            t_tgt.truncate(); # truncate the snapshot
            t_stg.truncate(); # The perfect solution would be to lock stage table in exclusive mode, but it's not available cross platform

            date d = now_ms();
            ret = t_tgt.insertFromSelect(("objectid", "status", "modified", "total_count",),
                                         t_src, sh);

            t_stg.del({"created": op_lt(d)});

            return ret;
        }

        #! An universal wrapper for "snapshot refreshing"
        /** @retval a hash with "snaphsot" : "result" map
        */
        hash refreshSnapshots() {
            code logger = sub(string msg) {
%ifdef QorusServer
                qlog(LoggerLevel::INFO, "Schema Snapshots refresh: %s", msg);
%else
                printf("%n: Schema Snapshots refresh: %s\n", now(), msg);
%endif
            };

            logger("start");
            on_success {
		logger("end");
            }
            on_error {
                logger("ERROR");
            }

            hash ret;

            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    logger("workflow_instance start");
                    int i = refreshSnapshot("workflow_instance");
                    ret.workflow_instance = i;
                    logger(sprintf("workflow_instance lines: %d", i));

                    logger("job_instance start");
                    i = refreshSnapshot("job_instance");
                    ret.job_instance = i;
                    logger(sprintf("job_instance lines: %d", i));
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }

            return ret;
        }

        lockSnapshot(string table) {
            m_snapshotMutexes{table}.lock();
        }

        unlockSnapshot(string table) {
            m_snapshotMutexes{table}.unlock();
        }

        checkUserStorage(string provider, string user, string key, string value) {
            if (value.size() > MaxStorageSize) {
                throw "STORAGE-ERROR", sprintf("provider %y user %y key %y: cannot store serialized value with %d "
                    "bytes; maximum serialized byte length is %d bytes", provider, user, key, value.size(),
                        MaxStorageSize);
            }
        }

        int updateUserStorage(string username, string key, any value) {
            value = serialize_qorus_data(value);
            checkUserStorage("db", username, key, value);
            return omqp.exec("update user_storage set value = %v where username = %v and keyname = %v", value,
                username, key);
        }

        int insertUserStorage(string username, string key, any value) {
            value = serialize_qorus_data(value);
            checkUserStorage("db", username, key, value);
            return omqp.exec("insert into user_storage (username, keyname, value) values (%v, %v, %v)", username, key,
                value);
        }

        int deleteUserStorage(string username, string key) {
            return omqp.exec("delete from user_storage where username = %v and keyname = %v", username, key);
        }

        hash<auto> getAllErrorDefs() {
            hash<auto> ret = {
                "global": omqp.select("select * from global_workflow_errors"),
                "workflow": omqp.select("select * from workflow_errors"),
            };
            # convert statuses here
            *list<auto> nl = map OMQ::SQLStatMap{$1}, ret.global.status;
            ret.global.status = nl;
            nl = map OMQ::SQLStatMap{$1}, ret.workflow.status;
            ret.workflow.status = nl;
            return ret;
        }

        createGlobalError(ErrorDef err) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("insert into global_workflow_errors (error, description, severity, status, business_flag, retry_delay_secs) values (%v, %v, %v, %v, %v, %v)", err.error, err.description, err.severity, OMQ::StatMap{err.status}, int(err.business_flag), err.retry_delay_secs);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        updateGlobalError(ErrorDef err) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update global_workflow_errors set description = %v, severity = %v, status = %v, business_flag = %v, retry_delay_secs = %v where error = %v", err.description, err.severity, OMQ::StatMap{err.status}, int(err.business_flag), err.retry_delay_secs, err.error);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        hash deleteError(string err) {
            hash h;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    h = (
                        "workflow": omqp.exec("delete from workflow_errors where error = %v", err),
                        "global": omqp.exec("delete from global_workflow_errors where error = %v", err),
                        );
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
            return h;
        }

        createWorkflowError(softint wfid, ErrorDef err, bool manually_updated = False) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("insert into workflow_errors (workflowid, error, description, severity, status, business_flag, retry_delay_secs, manually_updated) values (%v, %v, %v, %v, %v, %v, %v, %v)", wfid, err.error, err.description, err.severity, OMQ::StatMap{err.status}, int(err.business_flag), err.retry_delay_secs, int(manually_updated));
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        updateWorkflowError(softint wfid, ErrorDef err, bool manually_updated = False) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update workflow_errors set description = %v, severity = %v, status = %v,  business_flag = %v, retry_delay_secs = %v, manually_updated = %v where workflowid = %v and error = %v", err.description, err.severity, OMQ::StatMap{err.status}, int(err.business_flag), err.retry_delay_secs, int(manually_updated), wfid, err.error);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        int deleteWorkflowError(softint wfid, string err) {
            int rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = omqp.exec("delete from workflow_errors where workflowid = %v and error = %v", wfid, err);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
            return rv;
        }

        int insertInterfaceOptionRawNoCommit(string type, softint id, string opt, string desc, bool config, *string val) {
            #printf("SQLInterface::insertWorkflowOptionRawNoCommit() wfid: %y opt: %y desc: %y config: %y val: %y\n", wfid, opt, desc, config, val);
            return omqp.exec("insert into %s_options (%sid, name, description, config, value) values "
                "(%v, %v, %v, %v, %v)", type, type, id, opt, desc, config ? 1 : NULL, val);
        }

        int deleteInterfaceOptionNoCommit(string type, softint id, string opt) {
            return omqp.exec("delete from %s_options where %sid = %v and name = %v", type, type, id, opt);
        }

        int updateOperatorLockNoCommit(softint wfiid, *string user) {
            return omqp.exec("update workflow_instance set operator_lock = %v where workflow_instanceid = %v", user, wfiid);
        }

        abstract softint getNextSequenceValue(string name);

        # takes an exception hash and returns an message string if the error is related to the fact that the transaction should be restarted (ex: cluster failover error)
        *string restartTransactionImpl(hash ex) {
            return restart_transaction_intern(omqp.getDriverName(), ex);
        }

        # takes an exception hash and returns True if the error is related to the fact that the transaction should be restarted (ex: cluster failover error)
        bool checkRestartTransactionImpl(hash ex) {
            return restart_transaction_intern(omqp.getDriverName(), ex) ? True : False;
        }
    }

    public class OracleSQLInterface inherits SQLInterface {
        constructor(AbstractDatasource omqp) : SQLInterface(omqp) {
        }

        softint getNextSequenceValue(string name) {
            return omqp.selectRow("select %s.nextval from dual", name).nextval;
        }
    }

    public class PostgreSQLInterface inherits SQLInterface {
        constructor(AbstractDatasource omqp) : SQLInterface(omqp) {
        }

        softint getNextSequenceValue(string name) {
            return omqp.selectRow("select nextval(%v);", name).nextval;
        }
    }

    public class MySQLInterface inherits SQLInterface {
        private {
            Datasource seqds;
        }

        constructor(AbstractDatasource omqp) : SQLInterface(omqp) {
            seqds = new Datasource(omqp.getConfigHash());
            seqds.setAutoCommit(True);
        }

        softint getNextSequenceValue(string name) {
            return seqds.selectRow("select my_nextval(%v) as \"my_nextval\";", name).my_nextval;
        }
    }
}

%old-style
