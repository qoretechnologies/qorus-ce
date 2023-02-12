# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

# server-only methods
public namespace OMQ {
    class ServerSQLInterface inherits SQLInterface {
        constructor(QdspClient omqp) : SQLInterface(omqp) {
        }

        # takes an exception hash and returns True if the error is related to the fact that the transaction should be
        # restarted (ex: cluster failover error)
        bool restartTransaction(hash<auto> ex) {
%ifdef QorusDebugInternals
            if (ex.err == "TEST-CLUSTER-FAILOVER") {
                qlog(LoggerLevel::FATAL, "RESTART TRANSACTION: %s", ex.desc);
                return True;
            }
%endif

            *string msg;
            while (True) {
                if (ex.err == "DATASOURCEPOOL-PROCESS-ERROR") {
                    # issue #2439: do not assume there was a failover event if the exception happened on the
                    # commit statatement; repeating the transaction in this case would cause additional
                    # problems, because it's possible the commit has been executed
                    if (ex.callStack[0].function !~ /::commit$/) {
                        msg = sprintf("%s: Qorus qdsp cluster server failover event; restart transaction",
                            get_ex_pos(ex));
                    }
                } else {
                    msg = restartTransactionImpl(ex);
                }
                if (msg) {
                    qlog(LoggerLevel::FATAL, "RESTART TRANSACTION: %s", msg);
                    return True;
                }
                if (!ex.next)
                    break;
                ex = ex.next;
            }
            return False;
        }

%ifdef QorusDebugInternals
        bool checkRestartTransaction(hash ex) {
            return (ex.err == "TEST-CLUSTER-FAILOVER")
                ? True
                : checkRestartTransaction(ex);
        }
%endif

        # just a short string to access the system table
        SqlUtil::AbstractTable sysTable(string table_name) {
            return get_sql_table_system(omqp, table_name);
        }

        int getWorkflowSessionStatus(int wfid) {
            return omqp.selectRow("select open from workflows where workflowid = %v", wfid).open;
        }

        int getJobSessionStatus(int jobid) {
            return omqp.selectRow("select open from jobs where jobid = %v", jobid).open;
        }

        int insertSla(string name, string units, string description) {
            AbstractTable sla = sysTable("sla");
            return sla.insert({"name": name, "units": units, "description": description},
                {"returning": "slaid"}).slaid;
        }

        sessionReopen(int sessionid, string key, string hostname, string http_server, string version = OMQ::version) {
            hash<auto> upd = {
                "sessionstatus": "ACTIVE",
                "hostname": hostname,
                "xmlrpc_server": http_server,
                "version": version,
            };
            hash<auto> wh = {
                "sessionid": sessionid,
                "instancekey": key,
            };

%ifdef QorusDebugInternals
            int rc =
%endif
            sysTable("sessions").update(upd, wh);
%ifdef QorusDebugInternals
            if (!rc) QDBG_LOG("ERROR rc: %y sessionid: %y instancekey: %y", rc, sessionid, key);
            QDBG_ASSERT(rc);
%endif
        }

        int sessionOpen2(string key, string hostname, string http_server, string version = OMQ::version) {
            hash<auto> ins = {
                "instancekey": key,
                "sessionstatus": "ACTIVE",
                "hostname": hostname,
                "xmlrpc_server": http_server,
                "version": version,
            };
            return sessionOpen2Impl(ins);
        }

        private int sessionOpen2Impl(hash<auto> ins) {
            return sysTable("sessions").insert(ins, {"returning": "sessionid"}).sessionid;
        }

        *list<int> getOpenSessionsWithOrders(int wfid) {
            *list<int> rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = omqp.select("select distinct status_sessionid from workflow_instance where workflowid = %v and "
                        "status_sessionid != 0", wfid).status_sessionid;
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        commitUpdateWorkflowSlaStatus(softint wfid, int sla) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update workflows set sla_threshold = %v, manual_sla_threshold = 1 where workflowid = %v", sla, wfid);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        commitUpdateWorkflowRemoteStatus(softint wfid, bool remote) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update workflows set remote = %v, manual_remote = 1 where workflowid = %v",
                        remote.toInt(), wfid);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        commitUpdateServiceRemoteStatus(softint svcid, bool remote) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update services set remote = %v, manual_remote = 1 where serviceid = %v",
                        remote.toInt(), svcid);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        commitUpdateJobRemoteStatus(softint jobid, bool remote) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update jobs set remote = %v, manual_remote = 1 where jobid = %v", remote.toInt(),
                        jobid);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        *list<int> getOpenSessionsWithJobs(int jobid) {
            *list<int> rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = omqp.select("select distinct sessionid from job_instance where jobid = %v and "
                        "jobstatus = 'I'", jobid).sessionid;
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        # SegmentManager
        # dynamic SQL uses only 2 values - staticdata|dynamicdata. Nothing more.
        # We can leave it here.
        # transaction restart managed by caller
        *hash smReplaceExternalData(string f, softint wfiid) {
            # check for SQL injections
            if (!inlist(f, ("staticdata", "dynamicdata")))
                throw "REPLACE-EXTERNAL-DATA-ERROR", sprintf("Use of unregistered column name: %s", f);
            return omqp.selectRow("select status_sessionid, operator_lock, %s from workflow_instance wi, order_instance oi where oi.workflow_instanceid = %v and oi.workflow_instanceid = wi.workflow_instanceid for update", f, wfiid);
        }

        # dynamic SQL uses only 2 values - staticdata|dynamicdata. Nothing more.
        # We can leave it here.
        smReplaceExternalDataUpdate(string f, any str, softint wfiid) {
            # check for SQL injections
            if (!inlist(f, ("staticdata", "dynamicdata")))
                throw "REPLACE-EXTERNAL-DATA-ERROR", sprintf("Use of unregistered column name: %s", f);
            omqp.exec("update order_instance set %s = %v where workflow_instanceid = %v", f, str, wfiid);
        }

        # SegmentManager
        # transaction restart managed by caller
        *hash<auto> smReplaceExternalStepData(softint wfiid, softint stepid, int ind) {
            # do the for update select first
            *hash<auto> wh = omqp.selectRow("select status_sessionid, operator_lock from workflow_instance wi where "
                "workflow_instanceid = %v for update", wfiid);
            if (!wh) {
                return;
            }

            # here we get the current step instance, step instance data, and queue data row(s) for the step
            # cannot do a for update select with an outer join
            *hash<auto> sh = omqp.selectRow("select * from step_instance si left join step_instance_data sid on "
                "(si.workflow_instanceid = sid.workflow_instanceid and si.stepid = sid.stepid and si.ind = sid.ind) "
                "left join queue_data qd on (si.workflow_instanceid = qd.workflow_instanceid and "
                "si.stepid = qd.stepid and si.ind = qd.ind) "
                "where si.workflow_instanceid = %v and si.stepid = %v and si.ind = %v",
                wfiid, stepid, ind);
            if (!sh) {
                throw "NO-DATA", sprintf("workflow_instanceid %d stepid %d[%d] does not exist and therefore "
                    "cannot be updated", wfiid, stepid, ind);
            }
            if (sh.stepstatus == SQLStatComplete) {
                throw "REPLACE-STEP-DATA-ERROR", sprintf("workflow_instanceid %d stepid %d[%d] has status \"COMPLETE\" and "
                    "cannot be updated", wfiid, stepid, ind);
            }

            return wh + sh;
        }

        # transaction restart managed by caller
        smReplaceExternalStepDataUpdate(*string str, softint wfiid, softint stepid, int ind) {
            AbstractTable step_instance_data = sysTable("step_instance_data");

            if (!str) {
                # delete step data
                step_instance_data.del({
                    "workflow_instanceid": wfiid,
                    "stepid": stepid,
                    "ind": ind,
                });
            } else {
                # insert or update step data
                step_instance_data.upsert({
                    "workflow_instanceid": wfiid,
                    "stepid": stepid,
                    "ind": ind,
                    "data": str,
                });
            }
        }

        *hash smWorkflowInstanceLock(softint wfiid) {
            # lock with "select for update"
            hash sh = {
                "columns": ("workflowid", "workflowstatus", "status_sessionid",
                            "parent_workflow_instanceid", "operator_lock"),
                "where": {
                    "workflow_instanceid": wfiid,
                },
                "forupdate": True,
            };
            return sysTable("workflow_instance").selectRow(sh);
        }

        int smRetryWorkflowInstanceUpdate(softint wfiid) {
            hash upd = {
                "segmentstatus": "R",
                "retry_trigger": now_us(),
            };
            hash wh = {
                "segmentstatus": op_in(("E", "A")),
                "workflow_instanceid": wfiid,
            };

            softint segcount += sysTable("segment_instance").update(upd, wh);

            if (!segcount)
                throw "STATUS-ERROR", sprintf("workflow_instanceid %d is inconsistent; it has no segments with status 'E' (ERROR) or 'A' (ASYNC-WAITING)", wfiid);

            sysTable("workflow_instance").update({"workflowstatus": "R"},
                                                 {"workflow_instanceid": wfiid});

            return segcount;
        }

        hash<auto> smCommitBlockOrCancel(softint wfiid, int qsid, string stat, bool block, bool assignSession,
            bool attachinprogress = False, string user = "system") {
            # try to lock workflow
            # start transaction management
            omqp.beginTransaction();
            *hash q = omqp.selectRow("select status_sessionid, workflowstatus, parent_workflow_instanceid, subworkflow, workflowstatus_orig, scheduled, operator_lock, started from workflow_instance where workflow_instanceid = %v for update", wfiid);

            # get exception string, pass status argument to closure so that it remains an unlocked lock variable
            code geterr = string sub (string ss) { return sprintf("%s-WORKFLOW-ERROR", ss == OMQ::StatCanceled ? "CANCEL" : "BLOCK"); };

            if (!exists q)
                throw geterr(stat), sprintf("workflow_instanceid %d does not exist", wfiid);

            if (block) {
                # check if it's being processed by another instance
                if (q.status_sessionid && q.status_sessionid != qsid)
                    throw geterr(stat), sprintf("workflow_instanceid %d is currently being processed by foreign session %d", wfiid, q.status_sessionid);

                # check for B in the case of X and vice versa
                string statComplement = (stat == OMQ::StatCanceled) ? OMQ::SQLStatBlocked : OMQ::SQLStatCanceled;
                if (!inlist(q.workflowstatus, (OMQ::SQLStatError, OMQ::SQLStatRetry,
                                                OMQ::SQLStatAsyncWaiting, OMQ::SQLStatWaiting,
                                                OMQ::SQLStatReady, OMQ::SQLStatScheduled,
                                                OMQ::SQLStatIncomplete, OMQ::SQLStatEventWaiting,
                                                statComplement))
                    || (q.workflowstatus == OMQ::SQLStatInProgress && !attachinprogress)) {
                    throw geterr(stat), sprintf("Cannot block/cancel(%s) workflow %s, stat: %s", stat, wfiid, OMQ::SQLStatMap.(q.workflowstatus));
                }

                # update orig stat only if it should contain something else than X or B.
                # These values are storing orig in the same way and it *must not* be rewritten.
                # And next rule - if it's I then store it as Y or S (attach function etc)
                string wfstat;
                if (q.workflowstatus == 'I')
                    wfstat = q.scheduled > now() ? 'S' : 'Y';
                else
                    wfstat = q.workflowstatus;

                if (wfstat == OMQ::SQLStatBlocked || wfstat == OMQ::SQLStatCanceled) {
                    omqp.exec("update workflow_instance
                                    set workflowstatus = %v,
                                        status_sessionid = 0
                                    where workflow_instanceid = %v",
                                OMQ::StatMap{stat}, wfiid);
                } else {
                    # update workflow status
                    omqp.exec("update workflow_instance
                                    set workflowstatus_orig = %v,
                                        workflowstatus = %v,
                                        status_sessionid = 0
                                    where workflow_instanceid = %v",
                                wfstat, OMQ::StatMap{stat}, wfiid);
                } # if wfstat
            } else {
                if (q.workflowstatus != OMQ::StatMap{stat}) {
                    throw geterr(stat), sprintf("Cannot 'unblock/restore cancel' workflow %s, stat: %s but it must be %s",
                                                wfiid, OMQ::SQLStatMap.(q.workflowstatus), stat);
                }
                # update workflow status
                # only the newly (2.5.0 or later) cancelled wfs can be restored
                if (q.workflowstatus_orig == NULL)
                    throw geterr(stat), "Original status is <NULL> - workflow instance cannot be restored";
                omqp.exec("update workflow_instance
                                    set workflowstatus = workflowstatus_orig,
                                        workflowstatus_orig = null,
                                        status_sessionid = %v
                                    where workflow_instanceid = %v", assignSession ? qsid : 0, wfiid);
            }

            # remove NULL values
            map delete q.$1, q.keyIterator(), q.$1 === NULL;
            return q;
        }

        hash<auto> smSetErrorIntern(softint wfiid, softint qsid, string user = "system") {
            # try to lock workflow
            *hash<auto> res = omqp.selectRow("select workflowstatus, status_sessionid, parent_workflow_instanceid, subworkflow, priority, operator_lock from workflow_instance where workflow_instanceid = %v for update", wfiid);
            if (!res) {
                throw "WORKFLOW-ERROR", sprintf("workflow_instanceid %d does not exist", wfiid);
            }

            if (res.status_sessionid && res.status_sessionid != qsid) {
                throw "WORKFLOW-SESSION-ERROR", sprintf("workflow_instanceid %d is currently being processed by foreign session %d", wfiid, res.status_sessionid);
            }

            if (!inlist(res.workflowstatus, (OMQ::SQLStatRetry, OMQ::SQLStatCanceled,
                                            OMQ::SQLStatBlocked, OMQ::SQLStatAsyncWaiting,
                                            OMQ::SQLStatError))) {
                throw "WORKFLOW-STATUS-ERROR", sprintf("cannot update status %s ('%s') to ERROR ('E')", SQLStatMap.(res.workflowstatus), res.workflowstatus);
                                            }

            #any wfu;

            # update all steps
            # query cost: 2
            res.stepcount = omqp.exec("update step_instance set stepstatus = 'E', custom_status = NULL where workflow_instanceid = %v and stepstatus = 'R'", wfiid);

            # update all segments
            # query cost: 2
            res.segcount = omqp.exec("update segment_instance set segmentstatus = 'E', custom_status = NULL where workflow_instanceid = %v and segmentstatus in ('R', 'X')", wfiid);

            # update workflow status
            omqp.exec("update workflow_instance set workflowstatus = 'E', status_sessionid = %v, custom_status = NULL where workflow_instanceid = %v", res.workflowstatus == OMQ::SQLStatCanceled ? qsid : 0, wfiid);
            return res;
        }

        nothing smSkipStepSQL(softint wfiid, softint stepid, softint ind, softint qsid, bool swf, string user = "system") {
            omqp.beginTransaction();

            # try to lock flow
            *hash fq = omqp.selectRow("select * from workflow_instance where workflow_instanceid = %v for update", wfiid);
            if (!exists fq.workflowstatus)
                throw "SKIP-STEP-ERROR", sprintf("workflow_instanceid %d does not exist", wfiid);

            fq.workflowstatus = OMQ::SQLStatMap.(fq.workflowstatus);
            if (inlist(fq.workflowstatus, (OMQ::StatInProgress, OMQ::StatCanceled)))
                throw "STEP-STATUS-ERROR", sprintf("cannot update a step for a workflow with status %s", fq.workflowstatus);

            if (fq.status_sessionid && fq.status_sessionid != qsid)
                throw "SESSION-ERROR", sprintf("workflow instance %d is currently owned by foreign session %d and cannot be updated by this session (%d)", wfiid, fq.status_sessionid, qsid);

            # get step info
            *hash sq = omqp.selectRow("select * from step_instance where workflow_instanceid = %v and stepid = %v and ind = %v for update", wfiid, stepid, ind);
            if (!exists sq.stepstatus)
                throw "SKIP-STEP-ERROR", sprintf("stepid %d/%d has not been executed in workflow_instance %d", stepid, ind, wfiid);

            sq.stepstatus = OMQ::SQLStatMap.(sq.stepstatus);
            if (!inlist(sq.stepstatus, (OMQ::StatRetry, OMQ::StatError, OMQ::StatAsyncWaiting)))
                throw "STEP-STATUS-ERROR", sprintf("can't update steps with status %n", sq.stepstatus);

            # make sure no subworkflow step has been bound
            if (swf) {
                *hash swfq = workflowInstanceExecuteSubWorkflowStep(wfiid, stepid, ind);
                if (swfq.val())
                    throw "SKIP-STEP-ERROR", sprintf("cannot skip subworkflow step %d/%d with workflow_instanceid %d with bound subworkflow instanceid %d (corrected: %d)", stepid, ind, wfiid, swfq.subworkflow_instanceid, swfq.currected);
            }

            omqp.exec("update step_instance set skip = 1 where workflow_instanceid = %v and stepid = %v and ind = %v", wfiid, stepid, ind);
            # no return here
        }

        # transaction restart handled by caller
        *hash smGetSubWorkflowStatus(softint wfiid, softint stepid, softint ind) {
            hash sh = {
                "columns": ("wi.workflow_instanceid", "wi.workflowstatus",),
                "join": join_inner(sysTable("workflow_instance"),
                                   "wi",
                                   {"subworkflow_instanceid": "workflow_instanceid"}),
                "where": {
                    "workflow_instanceid": wfiid,
                    "stepid": stepid,
                    "ind": ind,
                }
            };
            return sysTable("subworkflow_instance").selectRow(sh);
        }

        # transaction handling/recovery handled by the caller
        *hash smGetWorkflowInstanceStatusSQL(softint wfiid) {
            # get workflow & workflow_instance information
            string sql = sprintf("select
        name, version, author, workflowstatus, w.workflowid,
        status_sessionid, parent_workflow_instanceid,
        started, completed, warnings as \"warning_count\", errors as \"error_count\",
        wi.modified, business_error, wi.custom_status,
        wi.scheduled, priority, operator_lock, note_count
        from
        workflow_instance wi, workflows w, order_instance oi
        where
        w.workflowid = wi.workflowid
        and wi.workflow_instanceid = oi.workflow_instanceid
        and wi.workflow_instanceid = %d", wfiid);
            *hash wq = omqp.selectRow(sql);
            if (!exists wq)
                return;

            hash ret.wq = wq;
            # add in workflow_instanceid key
            ret.wq.workflow_instanceid = wfiid;

            # get segment information
            sql = sprintf("select segmentid, segmentstatus, created, modified, custom_status from segment_instance where workflow_instanceid = %d order by segmentid", wfiid);
            ret.seg = omqp.select(sql);
            return ret;
        }

        # transaction handling/recovery handled by the caller
        *hash smGetWorkflowInstanceStatusSQLContextSeg(softint wfid, any segid) {
            # get step status per segment as well
            hash sh = {
                "columns": "stepid",
                "where": {
                    "workflowid": wfid,
                    "segmentid": segid,
                },
            };

            return sysTable("segment_steps").select(sh);
        }

        # transaction handling/recovery handled by the caller
        *hash smGetWorkflowInstanceStatusSQLContextStep(softint wfiid) {
            # get step information
            return omqp.select("select name, version, steptype, arraytype,
                                       stepid, ind, stepstatus, retries,
                                       started, completed,
                                       si.custom_status, s.workflow_event_typeid, eventkey
                            from
                                step_instance si left outer join
                                    step_instance_events sie using (workflow_instanceid, stepid, ind)
                                join steps s using (stepid)
                                join step_type st using (steptype)
                            where
                                    workflow_instanceid = %v
                                order by started", wfiid);
        }

        # transaction handling/recovery handled by the caller
        *hash smGetAllSubWorkflowInfo(softint wfiid) {
            hash sh = {
                "columns": ("stepid", "ind", "subworkflow_instanceid", "corrected",),
                "where": {
                    "workflow_instanceid": wfiid,
                },
            };
            return sysTable("subworkflow_instance").select(sh);
        }

        # must order by created; ordering by error_instanceid does not work in DB clusters where sequence IDs are not necessarily generated in order
        /*
            @param wfiid a workflow instance id
            @param upstream_minerr an error id which is the minimal in the cache. This
                                   method has to select older instances only (if present).
                                   Resulting in "where error_instanceid < upstream_minerr"
            @param error_limit a SQL limit for the resultset
         */
        *list smGetDBErrors(softint wfiid, *softint upstream_minerr, softint error_limit) {
            hash sh = {
                "columns": ("error_instanceid", "stepid", "ind", "severity",
                            "error", "description", "info", "retry", "business_error",
                            "created"),
                "where": {
                    "workflow_instanceid": wfiid,
                },
                "orderby": ("created", "error_instanceid"),
                "limit": error_limit,
            };

            if (upstream_minerr > 0) {
                sh.where.error_instanceid = op_lt(upstream_minerr);
            }

            return sysTable("error_instance").selectRows(sh);
        }

        # transaction restart handled by the caller
        *hash smGetWorkflowInstanceInfoSQLIntern(softint wfiid) {
            hash sh = {
                "columns": ("name", "version", "author", "wi.*",),
                "join": join_inner(sysTable("workflow_instance"),
                                   "wi",
                                   {"workflowid": "workflowid"}
                                ),
                "where": {"wi.workflow_instanceid": wfiid},
            };

            return sysTable("workflows").selectRow(sh);
        }

        # transaction handling/recovery handled by the caller
        *hash smGetParentInfo(softint wfiid) {
            hash sh = {
                "columns": ("parent_workflow_instanceid", "subworkflow", "priority",),
                "where": {
                    "workflow_instanceid": wfiid,
                }
            };

            return sysTable("workflow_instance").selectRow(sh);
        }

        # transaction handling/recovery handled by the caller
        *hash smGetTreeWithWorkflowInstanceIntern(any toFetch) {
            hash sh = (
                "columns": ("name", "version", "wi.*"),
                "join": (join_inner(sysTable("workflow_instance"), "wi", ("workflowid": "workflowid"))),
                "where": (
                    "wi.parent_workflow_instanceid": op_in(toFetch),
                ),
                );
            return sysTable("workflows").select(sh);
        }

        # transaction handling/recovery handled by the caller
        *hash smGetOrderInfoFromQueryResults(softint wfiid) {
            # get workflow and workflow status info
            return omqp.select("select name, version, w.workflowid, workflow_instanceid, workflowstatus from workflows w, workflow_instance wi where wi.WORKFLOWID = w.WORKFLOWID and wi.workflow_instanceid = %v",
                            wfiid);
        }

        # transaction handling/recovery handled by the caller
        *list smGetOrderInfoSQL(string column, any id) {
            # check for SQL injections
            switch (column) {
                case "workflow_instanceid": id = id.toInt(); break;
                case "external_order_instanceid": break;
                default:
                    throw "GET-ORDER-INFO-SQL-ERROR", sprintf("Using of unregistered column name: %s", column);
            }

            return omqp.selectRows(
                    "select wi.workflow_instanceid,
                        name, version, external_order_instanceid,
                        staticdata, dynamicdata, oi.created, oi.modified
                    from
                        order_instance oi, workflow_instance wi, workflows w
                    where
                        oi.workflow_instanceid = wi.workflow_instanceid
                    and wi.workflowid = w.workflowid
                    and oi.%s = %v", column, id);
        }

        # transaction handling/recovery handled by the caller
        hash smQueueEventsIntern(softint wfiid) {
            hash ret = {};
            ret.segmentids = omqp.select("select segmentid from segment_instance where workflow_instanceid = %d and segmentstatus = 'Y'", wfiid).segmentid;
            ret.subworkflows = omqp.select("select
        swi.workflow_instanceid as \"subworkflow_instanceid\", si.stepid, si.ind, swi.workflowstatus as \"status\", corrected
        from
        step_instance si, subworkflow_instance sswi, workflow_instance swi
        where
        si.workflow_instanceid = %d and si.stepstatus != 'C'
        and si.workflow_instanceid = sswi.workflow_instanceid
        and si.stepid = sswi.stepid and si.ind = sswi.ind
        and sswi.subworkflow_instanceid = swi.workflow_instanceid
        and ((corrected is null
                and swi.workflowstatus in ('C', 'E')
                and stepstatus != swi.workflowstatus)
            or corrected = 1)", wfiid);
            ret.asyncs = omqp.select("select queuekey, stepid, ind, corrected from queue_data where workflow_instanceid = %d and queue_data_status = 'R'", wfiid);

            # workflow synchronization events
            ret.syncs = omqp.select("select si.stepid, si.ind, si.skip as \"corrected\" from step_instance si, step_instance_events sie, workflow_events we where si.workflow_instanceid = %v and si.stepstatus != 'C'
        and si.workflow_instanceid = sie.workflow_instanceid
        and si.stepid = sie.stepid
        and si.ind = sie.ind
        --
        and sie.workflow_event_typeid = we.workflow_event_typeid
        and sie.eventkey = we.eventkey
        and (we.event_posted = 1 or si.skip = 1)
        order by sie.modified", wfiid);

            ret.retries = omqp.select("select segmentid, modified, segmentstatus, retry_trigger from segment_instance where workflow_instanceid = %d and segmentstatus in ('A', 'R') order by modified", wfiid);
            return ret;
        }

        # issue #1851: make sure that rescheduled BLOCKED or CANCELED orders are not rescheduled in the workflow queue as it can lead to a race condition
        #! returns @ref True "True" if the order has a BLOCKED or CANCELED status, @ref False "False" otherwise
        bool rescheduleWorkflow(softint wfiid, *date scheduled, int qsid, string user = "system") {
            if (scheduled && scheduled < now_us())
                delete scheduled;
            omqp.beginTransaction();

            *hash q = omqp.selectRow("select status_sessionid, workflowstatus, workflowstatus_orig, scheduled, operator_lock from workflow_instance where workflow_instanceid = %v for update", wfiid);
            if (!q)
                throw "INVALID-WORKFLOW-INSTANCE", sprintf("workflow_instanceid %d does not exist", wfiid);

            if (q.status_sessionid && q.status_sessionid != qsid)
                throw "SESSION-ERROR", sprintf("workflow instance %d is currently owned by foreign session %d and cannot be updated by this session (%d)", wfiid, q.status_sessionid, qsid);

            # is workflow blocked or canceled?
            bool bc = inlist(q.workflowstatus, (OMQ::SQLStatCanceled, OMQ::SQLStatBlocked));

            string new_status = scheduled ? "S" : "Y";

            # issue 1812: keep original status if rescheduling a blocked or canceled order
            if (bc)
                new_status = q.workflowstatus;

            # check valid status for rescheduling
            if ((q.workflowstatus != SQLStatReady && q.workflowstatus != SQLStatScheduled)
                && (!bc || (q.workflowstatus_orig != OMQ::SQLStatReady && q.workflowstatus_orig != SQLStatScheduled))) {
                if (bc)
                    throw "WORKFLOW-STATUS-ERROR", sprintf("cannot reschedule a workflow with status %s ('%s'), original status %s ('%s')", SQLStatMap.(q.workflowstatus), q.workflowstatus, SQLStatMap.(q.workflowstatus_orig), q.workflowstatus_orig);
                else
                    throw "WORKFLOW-STATUS-ERROR", sprintf("cannot reschedule a workflow with status %s ('%s')", SQLStatMap.(q.workflowstatus), q.workflowstatus);
            }

            omqp.exec("update workflow_instance set scheduled = %v, workflowstatus = %v where workflow_instanceid = %v", scheduled, new_status, wfiid);

            return bc;
        }

        # returns True if the priority was updated
        bool reprioritizeWorkflow(softint wfiid, int prio, int qsid, string user = "system") {
            omqp.beginTransaction();

            *hash q = omqp.selectRow("select status_sessionid, workflowstatus, workflowstatus_orig, priority, operator_lock from workflow_instance where workflow_instanceid = %v for update", wfiid);
            if (!q)
                throw "INVALID-WORKFLOW-INSTANCE", sprintf("workflow_instanceid %d does not exist", wfiid);

            if (q.status_sessionid && q.status_sessionid != qsid)
                throw "SESSION-ERROR", sprintf("workflow instance %d is currently owned by foreign session %d and cannot be updated by this session (%d)", wfiid, q.status_sessionid, qsid);

            # is workflow complete?
            if (q.workflowstatus == OMQ::SQLStatComplete)
                throw "WORKFLOW-STATUS-ERROR", sprintf("cannot change the priority of a workflow order with status %s ('%s')", SQLStatMap.(q.workflowstatus), q.workflowstatus);

            # do not update if the priority is already the same
            if (prio == q.priority)
                return False;

            omqp.exec("update workflow_instance set priority = %v where workflow_instanceid = %v", prio, wfiid);
            return True;
        }

        # returns True if the lock was updated
        bool lockOrderNoCommit(softint wfiid, string user = "system", int qsid) {
            omqp.beginTransaction();

            *hash q = omqp.selectRow("select status_sessionid, workflowstatus, operator_lock from workflow_instance where workflow_instanceid = %v for update", wfiid);
            if (!q)
                throw "INVALID-WORKFLOW-INSTANCE", sprintf("workflow_instanceid %d does not exist", wfiid);

            if (q.operator_lock == user)
                return False;

            if (q.status_sessionid && q.status_sessionid != qsid)
                throw "SESSION-ERROR", sprintf("workflow instance %d is currently owned by foreign session %d and cannot be updated by this session (%d)", wfiid, q.status_sessionid, qsid);

            # is workflow complete?
            if (q.workflowstatus == OMQ::SQLStatComplete)
                throw "WORKFLOW-STATUS-ERROR", sprintf("cannot lock a workflow order with status %s ('%s')", SQLStatMap.(q.workflowstatus), q.workflowstatus);

            omqp.exec("update workflow_instance set operator_lock = %v where workflow_instanceid = %v", user, wfiid);
            return True;
        }

        # returns True if the lock was updated
        bool unlockOrderNoCommit(softint wfiid, string user = "system", int qsid) {
            omqp.beginTransaction();

            *hash q = omqp.selectRow("select status_sessionid, workflowstatus, operator_lock from workflow_instance where workflow_instanceid = %v for update", wfiid);
            if (!q)
                throw "INVALID-WORKFLOW-INSTANCE", sprintf("workflow_instanceid %d does not exist", wfiid);

            if (!q.operator_lock)
                return False;

            if (q.status_sessionid && q.status_sessionid != qsid)
                throw "SESSION-ERROR", sprintf("workflow instance %d is currently owned by foreign session %d and cannot be updated by this session (%d)", wfiid, q.status_sessionid, qsid);

            omqp.exec("update workflow_instance set operator_lock = %v where workflow_instanceid = %v", NULL, wfiid);
            return True;
        }

        # returns True if the lock was updated
        bool breakOrderLockNoCommit(softint wfiid, int qsid) {
            omqp.beginTransaction();

            *hash q = omqp.selectRow("select status_sessionid, workflowstatus, operator_lock from workflow_instance where workflow_instanceid = %v for update", wfiid);
            if (!q)
                throw "INVALID-WORKFLOW-INSTANCE", sprintf("workflow_instanceid %d does not exist", wfiid);

            if (!q.operator_lock)
                return False;

            if (q.status_sessionid && q.status_sessionid != qsid)
                throw "SESSION-ERROR", sprintf("workflow instance %d is currently owned by foreign session %d and cannot be updated by this session (%d)", wfiid, q.status_sessionid, qsid);

            omqp.exec("update workflow_instance set operator_lock = %v where workflow_instanceid = %v", NULL, wfiid);
            return True;
        }

        rescheduleWorkflowUnconditional(softint wfiid, *date sched) {
            omqp.exec("update workflow_instance set scheduled = %v where workflow_instanceid = %v", sched, wfiid);
        }

        reprioritizeWorkflowUnconditional(softint wfiid, int prio) {
            omqp.exec("update workflow_instance set priority = %v where workflow_instanceid = %v", prio, wfiid);
        }

        # transaction restart handled by caller
        *hash workflowQueueInitWorkflowInstanceQueue(softint min, softint max, softint sid, softint wid) {
            hash sh = {
                "columns": ("workflow_instanceid", "parent_workflow_instanceid",
                            "subworkflow", "scheduled", "priority",),
                "where": {
                    "workflowid": wid,
                    "status_sessionid": sid,
                    "0:workflow_instanceid": op_ge(min),
                    "1:workflow_instanceid": op_le(max),
                },
                "orderby": "started",
            };

            return sysTable("workflow_instance").select(sh);
        }

        # transaction restart handled by caller
        *hash workflowQueueInitCommonSegments(softint min, softint max, softint sid, softint wid) {
            return omqp.select("select si.workflow_instanceid,
                wi.parent_workflow_instanceid,
                wi.subworkflow,
                si.modified,
                si.segmentid,
                si.segmentstatus,
                si.retry_trigger,
                wi.priority
                from workflow_instance wi, segment_instance si
                where
                        si.workflow_instanceid = wi.workflow_instanceid
                    and si.workflowid = wi.workflowid
                    and wi.workflowid = %v
                    and wi.workflowstatus not in ('X', 'B')
                    and si.segmentstatus in ('Y', 'A', 'R')
                    and status_sessionid = %v
                    and synchronous = 0
                    and wi.workflow_instanceid >= %v
                    and wi.workflow_instanceid <= %v
                order by si.modified", wid, sid, min, max);
        }

        # transaction restart handled by caller
        hash<auto> rbacLoad() {
            return {
                "groups"              : omqp.select("select * from groups"),
                "group_services"      : omqp.select("select * from group_services"),
                "group_workflows"     : omqp.select("select * from group_workflows"),
                "group_jobs"          : omqp.select("select * from group_jobs"),
                "group_mappers"       : omqp.select("select * from group_mappers"),
                "group_vmaps"         : omqp.select("select * from group_vmaps"),
                "group_fsms"          : omqp.select("select * from group_fsms"),
                "group_pipelines"     : omqp.select("select * from group_pipelines"),
            };
        }

        #! updates a synthetic group's actual object's enabled status in the DB
        updateSyntheticGroup(string obj, softint id, bool enabled) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update %ss set enabled = %v where %sid = %v", obj, enabled.toInt(), obj, id);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        commitGroupStatus(int id, bool enabled) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update groups set enabled = %v where groupid = %v", int(enabled), id);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        int commitJobActiveStatus(softint jobid, bool active) {
            int rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = omqp.exec("update jobs set active = %v, manual_active = %v where jobid = %v", int(active), 1,
                        jobid);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        int commitJobExpiry(softint jobid, *date expiry) {
            int rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = omqp.exec("update jobs set expiry_date = %v, manually_updated = 1 where jobid = %v", expiry, jobid);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        int commitJobCustomTrigger(softint jobid, date ts) {
            int rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = omqp.exec("update jobs set custom_trigger = %v where jobid = %v", ts, jobid);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        int insertJobError(*softint jiid, string severity, string err, string desc, any info, softbool business) {
            info = serialize_qorus_data(info);

            if (strlen(desc) > OMQ::SQLDescLen)
                desc = trunc_str(desc, OMQ::SQLDescLen, encoding);

            hash ins = {
                "job_instanceid": jiid,
                "severity": severity,
                "error": err,
                "description": substr(desc, 0, 240),
                "info": info,
                "business_error": int(business),
            };

            return insertJobErrorImpl(ins);
        }

        private int insertJobErrorImpl(hash ins) {
            return sysTable("job_errors").insert(ins, {"returning": "job_errorid"}).job_errorid;
        }

        int insertJobInstance(int jobid, int sid) {
            hash ins = {
                "jobid": jobid,
                "sessionid": sid,
                "jobstatus": "I",
            };

            int ret;

            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    ret = insertJobInstanceImpl(ins);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        private int insertJobInstanceImpl(hash ins) {
            return sysTable("job_instance").insert(ins, {"returning": "job_instanceid"}).job_instanceid;
        }

        auto getJobInstanceInfo(int jiid) {
            while (True) {
                try {
                    on_exit omqp.rollback();

                    auto rv = omqp.selectRow("select info from job_instance where job_instanceid = %v", jiid).info;
                    QDBG_TEST_CLUSTER_FAILOVER();
                    return deserialize_qorus_data(rv);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        updateJobInstanceInfo(int jiid, any info) {
            info = serialize_qorus_data(info);
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.exec("update job_instance set info = %v where job_instanceid = %v", info, jiid);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        updateFinalJobInstanceStatus(int jid, int jiid, string stat, date last_executed) {
            omqp.exec("update job_instance set jobstatus = %v, sessionid = 0 where job_instanceid = %v", stat, jiid);
            omqp.exec("update jobs set last_executed = %v, last_executed_job_instanceid = %v where jobid = %v",
                      last_executed, jiid, jid);
        }

        int commitJobSchedule(softint jobid, string minute, string hour, string day, string month, string wday) {
            int rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = omqp.exec("update jobs set month = %v, day = %v, hour = %v, minute = %v, wday = %v, recurring = null, manually_updated = 1 where jobid = %v", month, day, hour, minute, wday, jobid);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        int commitJobRecurring(softint jobid, int recurring) {
            int rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = omqp.exec("update jobs set recurring = %v, month = null, day = null, hour = null, minute = null, wday = null, manually_updated = 1 where jobid = %v", recurring, jobid);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        int updateInterfaceOption(string type, softint id, string opt, auto val) {
            val = serialize_qorus_data(val);
            int rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = omqp.exec("update %s_options set value = %v where %sid = %v and name = %v", type, val, type, id, opt);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        int insertInterfaceOption(string type, softint id, string opt, string desc, bool config, auto val) {
            int rv;
            string optval = serialize_qorus_data(val);
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = insertInterfaceOptionRawNoCommit(type, id, opt, desc, config, optval);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        int deleteInterfaceOption(string type, softint id, string opt) {
            int rv;
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = deleteInterfaceOptionNoCommit(type, id, opt);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        int updateWorkflowDeprecated(softint wfid, bool deprecatedv) {
            int rv;

            hash upd = {
                "deprecated": deprecatedv ? 1: 0,
            };
            if (deprecatedv) {
                upd += {
                    "autostart": 0,
                    "manual_autostart": 1,
                };
            }

            hash wh = {
                "workflowid": wfid,
            };

            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = sysTable("workflows").update(upd, wh);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        int updateWorkflowAutostart(softint wfid, int autostart) {
            int rv;

            hash<auto> upd = {
                "autostart": autostart,
                "manual_autostart": 1,
            };
            hash<auto> wh = {
                "workflowid": wfid,
            };

            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    rv = sysTable("workflows").update(upd, wh);
                    QDBG_TEST_CLUSTER_FAILOVER();
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

        # generic bulk flush method
        bulkFlushWorkflowStatus(list l) {
            while (True) {
                try {
                    hash bulk_opts_update_only = {
                        "upsert_strategy": SqlUtil::AbstractTable::UpsertUpdateOnly,
                    };
                    # issue #3053: notes are always saved to the DB when added, no need to flush notes here
                    BulkUpsertOperation bulk_segments(sysTable("segment_instance"), bulk_opts_update_only);
                    BulkUpsertOperation bulk_steps(sysTable("step_instance"), bulk_opts_update_only);
                    BulkUpsertOperation bulk_wfstatus(sysTable("workflow_instance"), bulk_opts_update_only);
                    # audits are write only
                    BulkInsertOperation bulk_audits(sysTable("audit_events")); # insert only
                    on_error {
                        bulk_segments.discard();
                        bulk_steps.discard();
                        bulk_wfstatus.discard();
                        bulk_audits.discard();
                        omqp.rollback();
                    }
                    on_success omqp.commit();

                    foreach hash h in (l) {
                        #printf("TID %d: SQLInterface::bulkFlushWorkflowStatus() wfiid: %y h: %y\n", gettid(), h.workflow_instanceid, h - ("notes", "segments", "steps"));

                        # save segments
                        if (h.segments) {
                            ListIterator it(h.segments);
                            while (it.next()) {
                                hash obj = it.getValue();
                                obj.retry_trigger = remove obj.retry_delay;
                                obj."workflow_instanceid" = h.workflow_instanceid;
                                bulk_segments.queueData(obj);
                            }
                        }

                        # save steps
                        if (h.steps) {
                            ListIterator it(h.steps);
                            while (it.next()) {
                                hash obj = it.getValue();
                                obj."workflow_instanceid" = h.workflow_instanceid;
                                obj.skip = int(obj.skip);
                                # issue #2524: ensure that stepid is an integer
                                obj.stepid = obj.stepid.toInt();
                                bulk_steps.queueData(obj);
                            }
                        }

                        # save workflowstatus
                        if (h.workflowstatus) {
                            hash obj = (
                                        "workflow_instanceid"   : h.workflow_instanceid,
                                        "workflowstatus"        : h.workflowstatus,
                                        "workflowstatus_orig"   : h.workflowstatus_orig,
                                        "business_error"        : h.business_error,
                                        "custom_status"         : h.custom_status,
                                        "scheduled"             : h.reschedule,
                                        "operator_lock"         : h.operator_lock,
                                        "status_sessionid"      : 0,
                                        "synchronous"           : 0,
                                );
                            bulk_wfstatus.queueData(obj);
                        }

                        if (h.audit) {
                            hash obj = (
                                        "workflowid"            : h.audit.workflowid,
                                        "workflow_instanceid"   : h.workflow_instanceid,
                                        "audit_event_code"      : AE_WORKFLOW_STATUS_CHANGE,
                                        "who"                   : h.audit.who,
                                        "source"                : h.audit.source,
                                        "info1"                 : h.audit.oldstatus,
                                        "info2"                 : h.audit.newstatus,
                                );
                            bulk_audits.queueData(obj);
                        }
                    }

                    bulk_segments.flush();
                    bulk_steps.flush();
                    bulk_wfstatus.flush();
                    bulk_audits.flush();

                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        *hash getPriorityWorkflowIDAndParentTrans(softint wfiid) {
            hash sh = {
                "columns": ("workflowid", "parent_workflow_instanceid", "subworkflow", "priority"),
                "where": {"workflow_instanceid": wfiid},
            };

            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return sysTable("workflow_instance").selectRow(sh);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
            }
        }

        *hash getWorkflowIDAndPriorityTrans(softint wfiid) {
            hash sh = {
                "columns": ("workflowid", "priority"),
                "where": {"workflow_instanceid": wfiid},
            };

            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return sysTable("workflow_instance").selectRow(sh);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
            }
        }

        *hash getOrderKeysTrans(softint wfiid) {
            *hash q;
            while (True) {
                try {
                    on_error omqp.rollback();

                    q = getOrderKeysImpl(wfiid);
                    QDBG_TEST_CLUSTER_FAILOVER();
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }

            return processOrderKeys(q);
        }

        # transaction restart handled by caller
        *hash getOrderKeys(softint wfiid) {
            return processOrderKeys(getOrderKeysImpl(wfiid));
        }

        private hash getOrderKeysImpl(softint wfiid) {
            hash sh = {
                "columns": ("keyname", "value",),
                "where": {
                    "workflow_instanceid": wfiid,
                }
            };

            return sysTable("order_instance_keys").select(sh);
        }

        private *hash processOrderKeys(hash q) {
            hash h;
            context (q) {
                if (exists h.%keyname) {
                    if (h.%keyname.typeCode() != NT_LIST)
                        h.%keyname = (h.%keyname, %value);
                    else
                        h.%keyname += %value;
                } else
                    h.%keyname = %value;
            }
            return h;
        }

        *hash getSubWorkflowStepTrans(softint swfiid) {
            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return getSubWorkflowStepImpl(swfiid);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
            }
        }

        private *hash getSubWorkflowStepImpl(int swfiid) {
            hash sh = {
                "columns": ("stepid", "ind"),
                "where": {
                    "subworkflow_instanceid": swfiid,
                    "workflow_instanceid": op_ne(swfiid),
                },
            };
            return sysTable("subworkflow_instance").selectRow(sh);
        }

        *hash getSubworkflowParentAndGrandparentInfoTrans(softint wfiid) {
            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return getSubworkflowParentAndGrandparentInfoImpl(wfiid);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
            }
        }

        private *hash getSubworkflowParentAndGrandparentInfoImpl(int wfiid) {
            return omqp.selectRow("select swf.workflow_instanceid, stepid, ind, workflowid, wi.parent_workflow_instanceid, wi.subworkflow, priority, workflowstatus as status from subworkflow_instance swf, workflow_instance wi where subworkflow_instanceid = %v and wi.workflow_instanceid = swf.workflow_instanceid and subworkflow_instanceid != swf.workflow_instanceid", wfiid);
        }

        hash getQueueAndWorkflowInfoTrans(softint queueid, softstring queuekey) {
            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return getQueueAndWorkflowInfoImpl(queueid, queuekey);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
            }
        }

        private hash getQueueAndWorkflowInfoImpl(int queueid, string queuekey) {
            return omqp.selectRow("select data, corrected, parent_workflow_instanceid, subworkflow, status_sessionid, queue_data_status from queue_data qd, workflow_instance wi where wi.workflow_instanceid = qd.workflow_instanceid and queueid = %v and queuekey = %v", queueid, queuekey);
        }

        hash getParentAndStatusFromQueueTrans(softint queueid, softstring queuekey) {
            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return getParentAndStatusFromQueueImpl(queueid, queuekey);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
            }
        }

        private hash getParentAndStatusFromQueueImpl(int queueid, string queuekey) {
            # query cost: 3
            return omqp.selectRow("select parent_workflow_instanceid, subworkflow, status_sessionid from queue_data qd, workflow_instance wi where wi.workflow_instanceid = qd.workflow_instanceid and queueid = %v and queuekey = %v", queueid, queuekey);
        }

        # transaction restart handled by caller
        *hash cacheSteps(softint wfiid) {
            return omqp.select("select stepid, ind, stepstatus, retries, skip, started, completed, custom_status, workflow_event_typeid, eventkey
                                    from step_instance natural left join step_instance_events where workflow_instanceid = %v order by started", wfiid);
        }

        insertStep(softint wfiid, softint stepid, softint ind, *hash<auto> step_data) {
            #log(LoggerLevel::DEBUG, "DEBUG: SQLInterface::insertStep(wfiid=%n, stepid=%n, ind=%n)", wfiid, stepid, ind);
            hash<auto> h = {
                "workflow_instanceid" : wfiid,
                "stepid": stepid,
                "ind": ind,
            };
            sysTable("step_instance").insert(h);
            if (step_data) {
                sysTable("step_instance_data").insert(h + {
                    "data": serialize_qorus_data(step_data),
                });
            }
        }

        int updateStepStatus(softint wfiid, softint stepid, softint ind, string status) {
            hash<auto> upd = {
                "stepstatus": status,
            };
            hash<auto> wh = {
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
            };
            return sysTable("step_instance").update(upd, wh);
        }

        int updateStep(softint wfiid, softint stepid, softint ind, string status, *softint retries, *string custom_status, bool skip = False, *date completed) {
            if (status == OMQ::SQLStatComplete && !completed.val())
                completed = now_us();

            hash<auto> upd = {
                "stepstatus": status,
                "retries": retries,
                "custom_status": custom_status,
                "skip": skip ? 1 : 0,
                "completed": completed,
            };
            hash<auto> wh = {
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
            };

            return sysTable("step_instance").update(upd, wh);
        }

        int insertSegment(softint wfid, softint wfiid, softint segid) {
            hash<auto> ins = {
                "workflowid": wfid,
                "workflow_instanceid": wfiid,
                "segmentid": segid,
            };
            sysTable("segment_instance").insert(ins);
            return 1;
        }

        int updateSegment(softint wfiid, softint segid, string status, *string custom_status, *date trigger) {
            hash<auto> upd = {
                "segmentstatus": status,
                "custom_status": status,
                "retry_trigger": trigger,
            };
            hash<auto> wh = {
                "workflow_instanceid": wfiid,
                "segmentid": segid,
            };
            return sysTable("segment_instance").update(upd, wh);
        }

        # marks a 'Y' (READY) or 'S' (SCHEDULED) workflow as 'E' and creates the initial segment with an ERROR status as well
        int markReadyWorkflowAsError(softint wfid, softint wfiid) {
            # update workflow_instance status to ERROR
            omqp.exec("update workflow_instance set workflowstatus = 'E' where workflow_instanceid = %v", wfiid);
            return omqp.exec("insert into segment_instance (workflowid, workflow_instanceid, segmentid, segmentstatus) values (%v, %v, 0, 'E')", wfid, wfiid);
        }

        insertArrayStep(softint wfiid, softint stepid, int elementsv) {
            BulkInsertOperation bulk(sysTable("step_instance"));
            on_error {
                bulk.discard();
            }

            # step ind 0 already inserted
            for (int i = 1; i < elementsv; i++) {
                hash<auto> h = {
                    "workflow_instanceid" : wfiid,
                    "stepid": stepid,
                    "ind": i,
                };
                bulk.queueData(h);
            }

            bulk.flush();
        }

        insertArrayStepRecover(softint wfiid, softint stepid, int elementsv, int start, *hash<auto> step_data) {
            map insertStep(wfiid, stepid, $1, step_data), xrange(start, elementsv);
        }

        insertSubWorkflowInstance(softint wfiid, softint stepid, softint ind, softint swfiid, *softint corrected) {
            hash<auto> ih = {
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
                "subworkflow_instanceid": swfiid,
                "corrected": corrected,
            };
            sysTable("subworkflow_instance").insert(ih);
        }

        insertStepInstanceEvent(softint wfiid, softint stepid, softint ind, softint eventid, softstring eventkey) {
            hash<auto> ih = {
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
                "workflow_event_typeid": eventid,
                "eventkey": eventkey,
            };
            sysTable("step_instance_events").insert(ih);
        }

        softbool setWorkflowInstanceInProgress(softint wfiid, softint sessionid) {
            hash<auto> upd = {
                "workflowstatus": "I",
                "status_sessionid": sessionid,
                "business_error": NOTHING,
            };
            hash<auto> wh = {
                "workflow_instanceid": wfiid,
                "workflowstatus": op_not(op_in(("X", "C", "B",))),
                "status_sessionid": op_in((0, sessionid)),
            };
            return sysTable("workflow_instance").update(upd, wh);
        }

        softbool updateFinalWorkflowStatus(softint wfiid, softint sessionid, string stat, *string stat_orig, *softint business_error, *string custom_status, *date reschedule, *string operator_lock) {
            hash<auto> upd = {
                "workflowstatus": stat,
                "workflowstatus_orig": stat_orig,
                "status_sessionid": sessionid,
                "business_error": business_error,
                "custom_status": custom_status,
                "scheduled": reschedule,
                "operator_lock": operator_lock,
                "synchronous": 0,
            };
            hash<auto> wh = {
                "workflow_instanceid": wfiid,
                "workflowstatus": op_not(op_in(("X", "C", "B"))),
            };
            return sysTable("workflow_instance").update(upd, wh);
        }

        softint grabWorkflow(softint wfiid, softint sessionid) {
            hash<auto> upd = {
                "status_sessionid": sessionid,
            };
            hash<auto> wh = {
                "workflow_instanceid": wfiid,
                "workflowstatus": op_not(op_in(("X", "C", "B"))),
                "status_sessionid": op_in((0, sessionid)),
            };
            return sysTable("workflow_instance").update(upd, wh);
        }

        insertQueueData(softint wfiid, softint stepid, softint ind, softint queueid, string key) {
            hash<auto> ih = {
                "queueid": queueid,
                "queuekey": key,
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
            };
            sysTable("queue_data").insert(ih);
        }

        insertOrUpdateQueueData(softint wfiid, softint stepid, softint ind, softint queueid, string key) {
            # start transaction if not already in one
            omqp.beginTransaction();

            AbstractTable t = sysTable("queue_data");

            hash<auto> sh = {
                "columns": "queue_data_status",
                "where": {
                    "workflow_instanceid": wfiid,
                    "stepid": stepid,
                    "ind": ind,
                },
                "forupdate": True,
            };

            *hash<auto> row = t.selectRow(sh);

            if (exists row && row.queue_data_status != 'X') {
                throw "QUEUE-ERROR",
                      sprintf("step %d/%d already has a queue entry with key %y, status '%s' (%s)",
                              stepid, ind, key, row.queue_data_status, OMQ::SQLQSMap.(row.queue_data_status));
            }

            hash<auto> ins = {
                "queueid": queueid,
                "queuekey": key,
                "queue_data_status": "W",
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
                "corrected": NOTHING,
            };
            t.upsert(ins);
        }

        int insertCorrectedQueueData(softint wfiid, softint stepid, softint ind, softint queueid, string key) {
            hash<auto> ins = {
                "queueid": queueid,
                "queuekey": key,
                "queue_data_status": "R",
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
                "corrected": 1,
            };
            sysTable("queue_data").insert(ins);
            return 1;
        }

        int insertOrUpdateCorrectedQueueData(softint wfiid, softint stepid, softint ind, any queueid, any key) {
            # start transaction if not already in one
            omqp.beginTransaction();
            *hash<auto> q = omqp.selectRow("select queuekey, queue_data_status from queue_data where workflow_instanceid = %v and stepid = %v and ind = %v for update", wfiid, stepid, ind);
            if (!exists q)
                return insertCorrectedQueueData(wfiid, stepid, ind, queueid, key);

            if (q.queue_data_status == 'R')
                throw "QUEUE-ERROR", sprintf("step %d/%d already has a queue entry with key %y, status '%s' (%s)", stepid, ind, q.queuekey, q.queue_data_status, OMQ::SQLQSMap.(q.queue_data_status));

            return omqp.exec("update queue_data set queuekey = %v, queue_data_status = 'R', corrected = 1 where workflow_instanceid = %v and stepid = %v and ind = %v", key, wfiid, stepid, ind);
        }

        # correct queue item - called by Qorus internals
        softint correctQueueData(softint wfiid, softint stepid, softint ind) {
            hash<auto> upd = {
                "corrected": 1,
                "queue_data_status": "R",
            };
            hash<auto> wh = {
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
                "queue_data_status": op_ne("R"),
            };
            return sysTable("queue_data").update(upd, wh);
        }

        # correct queue item - called by queue system service
        # additional locking and data checks implemented
        hash<auto> correctQueueDataCheck(softint wfiid, softint stepid, softint ind) {
            while (True) {
                try {
                    # commit transaction before calling SegmentManager (which grabs locks)
                    on_error omqp.rollback();
                    on_success omqp.commit();
                    omqp.beginTransaction();

                    AbstractTable t_queue_data = sysTable("queue_data");
                    AbstractTable t_workflow_instance = sysTable("workflow_instance");

                    hash sh = {
                        "columns": ("qd.queuekey", "workflowid", "qd.workflow_instanceid", "qd.queue_data_status", "qd.corrected", "priority", ),
                        "join": join_inner(t_queue_data, "qd", {"workflow_instanceid": "workflow_instanceid"}),
                        "where": {
                            "workflow_instanceid": wfiid,
                            "qd.stepid": stepid,
                            "qd.ind": ind,
                        },
                        "forupdate": True,
                    };
                    *hash q = t_workflow_instance.selectRow(sh);

                    if (!exists q) {
                        throw "INVALID-WORKFLOW-DATA",
                              sprintf("no queue data exists with workflow_instanceid: %y, stepid: %y, ind: %y'",
                                      wfiid, stepid, ind);
                    }
                    else if (q.queue_data_status != OMQ::SQL_QS_Waiting) {
                        throw "INVALID-STATUS",
                              sprintf("workflow_instanceid: %y, stepid: %y, ind: %y: queue data entry has status '%s' (%s), must be 'W' (WAITING) to update",
                                      wfiid, stepid, ind, q.queue_data_status, OMQ::SQLQSMap.(q.queue_data_status));
                    }
                    else if (q.corrected) {
                        throw "ALREADY-CORRECTED",
                              sprintf("workflow_instanceid: %y, stepid: %y, ind: %y: queue data entry has already been corrected",
                                      wfiid, stepid, ind);
                    }

                    q.rowcount = t_queue_data.update({"corrected": 1, "queue_data_status": "R",},
                                                    {"workflow_instanceid": wfiid, "stepid": stepid, "ind": ind});
                    return q;
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        # update queue data - called from queue system service only
        hash updateQueueData(string queue_name, softint queueid, softstring key, any data) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.beginTransaction(); # just to be sure because we are using for update in the 1st select
                    AbstractTable queue_table = sysTable("queue_data");
                    AbstractTable wi_table = sysTable("workflow_instance");

                    hash sh = {
                        "columns": ("queue_data_status", "wi.workflowid", "workflow_instanceid",
                                    "stepid", "ind", "wi.priority"),
                        "join": join_inner(wi_table, "wi", {"workflow_instanceid": "workflow_instanceid"}),
                        "where": {
                            "queueid": queueid,
                            "queuekey": key,
                        },
                        "forupdate": True,
                    };
                    *hash q = queue_table.selectRow(sh);

                    if (!q) {
                        throw "INVALID-KEY",
                            sprintf("no entry exists in queue '%s' with key '%s'", queue_name, key);
                    } else if (q.queue_data_status != OMQ::SQL_QS_Waiting) {
                        throw "INVALID-STATUS",
                            sprintf("queue %y key %y: data entry has status '%s' (%s), must be 'W' (WAITING) to update",
                                    queue_name, key, q.queue_data_status, OMQ::SQLQSMap.(q.queue_data_status));
                    }

                    q.rowcount = queue_table.update({"data": data, "queue_data_status": "R"},
                                                    {"queueid": queueid,
                                                    "queuekey": key,
                                                    "queue_data_status": OMQ::SQL_QS_Waiting,
                                                    });
                    return q;
                } catch (hash<ExceptionInfo> ex) {
                    if (restartTransaction(ex)) {
                        continue;
                    }
                    rethrow;
                }
                break;
            }
        }

        # discard queue item - called internally from Qorus
        int discardQueueDataUnconditional(softint queueid, string key) {
            hash upd = {
                "queue_data_status": "X",
                "data": NOTHING,
            };
            hash wh = {
                "queueid": queueid,
                "queuekey": key,
            };
            return sysTable("queue_data").update(upd, wh);
        }

        int discardQueueDataUnconditional(softint queueid, list keylist) {
            hash upd = {
                "queue_data_status": "X",
                "data": NOTHING,
            };
            hash wh = {
                "queueid": queueid,
                "queuekey": op_in(keylist),
            };
            return sysTable("queue_data").update(upd, wh);
        }

        # discard queue item - called by queue system service
        # additional locking and data checks implemented
        hash discardQueueDataCheck(softint queueid, string key) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    omqp.beginTransaction();

                    hash sh = {
                        "columns": "queue_data_status",
                        "where": {
                            "queueid": queueid,
                            "queuekey": key,
                        },
                        "forupdate": True,
                    };

                    *hash q = sysTable("queue_data").selectRow(sh);

                    if (!exists q) {
                        q.err = "INVALID-KEY";
                        return q;
                    }

                    if (q.queue_data_status == 'R') {
                        # unlock row
                        q.err = "INVALID-STATUS";
                        return q;
                    }

                    q.rowcount = sysTable("queue_data").update({"data": NOTHING, "queue_data_status": "X"},
                                                            {"queueid": queueid,
                                                                "queuekey": key,});
                    return q;
                } catch (hash<ExceptionInfo> ex) {
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        # transaction restart managed by caller
        *hash getQueueInfo(softint wfiid, softint stepid, softint ind) {
            hash sh = {
                "columns": ("queuekey", "queue_data_status", "corrected", "data", ),
                "where": {
                    "workflow_instanceid": wfiid,
                    "stepid": stepid,
                    "ind": ind,
                }
            };
            return sysTable("queue_data").selectRow(sh);
        }

        int updateQueueKey(softint queueid, softstring oldkey, softstring newkey) {
            hash upd_where = {
                "queueid": queueid,
                "queuekey": oldkey,
                "queue_data_status": "W",
            };

            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    AbstractTable t = sysTable("queue_data");
                    return t.update({"queuekey": newkey}, upd_where);
                } catch (hash<ExceptionInfo> ex) {
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        # transaction restart managed by caller
        list queueGetInfo(softint wfiid, softint stepid = 0, *softint ind) {
            hash sh = {
                "columns": ("workflow_instanceid", "stepid", "ind",
                            "queuekey", "queue_data_status", "corrected",
                            "data", "created", "modified",),
                "where": {
                    "workflow_instanceid": wfiid,
                },
            };
            if (stepid) {
                sh."where" += {"stepid": stepid};
            }
            if (exists ind) {
                sh."where" += {"ind": ind};
            }

            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    return sysTable("queue_data").selectRows(sh);
                } catch (hash<ExceptionInfo> ex) {
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        # transaction restart managed by caller
        *hash queueGetInfoFromQueueKey(softint queueid, softstring key) {
            hash sh = {
                "columns": ("workflow_instanceid", "stepid", "ind", "queue_data_status",
                            "corrected", "data", "created", "modified"),
                "where": {
                    "queueid": queueid,
                    "queuekey": key,
                }
            };

            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    return sysTable("queue_data").selectRow(sh);
                } catch (hash<ExceptionInfo> ex) {
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        *hash queueStatus(softint queueid) {
            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    return omqp.select("select q.name, wi.workflowid, w.name as \"workflowname\", w.version, qd.queue_data_status as \"status\", count(*) as \"count\" from queue_data qd, queues q, workflows w, workflow_instance wi where q.queueid = qd.queueid and wi.workflow_instanceid = qd.workflow_instanceid
        and wi.workflowid = w.workflowid and q.queueid = %v group by q.name, wi.workflowid, w.name, w.version, qd.queue_data_status", queueid);
                } catch (hash<ExceptionInfo> ex) {
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        /** @param queueid the queue ID to search for
            @param opts options accepted:
            - \c status: SQL status values; see @ref SQL_QS_ALL for possible values
            - \c user: the username to search for
            - \c user_interaction_locked: 1 or 0 for the user interaction locked status
            - \c limit: the maximum number of entries to return; default 100
            - \c offset: the offset to return; default 0
        */
        *list<auto> queueGetQueueInfo(softint queueid, *hash<auto> opts) {
            hash<auto> wh = {
                "queueid": queueid,
                "queue_data_status": opts.status ?? op_ne("X"),
            } + opts{"user", "user_interaction_locked"};
            if (wh.user_interaction_locked) {
                wh.user_interaction_locked = wh.user_interaction_locked.toInt();
            }

            hash<auto> sh = {
                "columns": (
                    "queuekey",
                    "queue_data_status",
                    "workflow_instanceid",
                    "stepid",
                    "ind",
                    "user_interaction_locked",
                    "user_interaction_user",
                    "user_interaction_modified",
                    "created",
                    "modified",
                ),
                "where": wh,
                "limit": opts.limit ?? 100,
                "offset": opts.offset ?? 0,
            };

            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    return sysTable("queue_data").selectRows(sh);
                } catch (hash<ExceptionInfo> ex) {
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
                break;
            }
        }

        *hash<auto> returnLockUserInteractionStep(int queueid, string user, *softint wfiid) {
            AbstractTable queues = get_sql_table_system_trans(omqp, "queues");
            AbstractTable step_instance_data = get_sql_table_system_trans(omqp, "step_instance_data");
            hash<auto> sh = {
                "columns": (
                    "workflow_instanceid",
                    "stepid",
                    "ind",
                    "queuekey",
                    "created",
                    "queueid",
                    cop_as("q.name", "queuename"),
                    cop_as(cop_over(cop_min("created"), "queueid"), "min_created"),
                    cop_as("sid.data", "data"),
                ),
                "where": {
                    "queue_data_status": "W",
                    "queueid": queueid,
                } + wop_or({
                    "user_interaction_locked": 0,
                    "user_interaction_user": NOTHING,
                }, {
                    "user_interaction_locked": 1,
                    "user_interaction_user": user,
                }),
                "join": join_inner(queues, "q") + join_left(step_instance_data, "sid", {
                    "workflow_instanceid": "workflow_instanceid",
                    "stepid": "stepid",
                    "ind": "ind",
                }),
                "superquery": {
                    "columns": (
                        "workflow_instanceid",
                        "stepid",
                        "ind",
                        "queuekey",
                        "queueid",
                        "queuename",
                        "data",
                    ),
                    "where": {"min_created": op_ceq("created")},
                    "limit": 1,
                },
            };
            if (wfiid) {
                sh."where".workflow_instanceid = wfiid;
            }

            while (True) {
                try {
                    on_error omqp.rollback();
                    on_success omqp.commit();

                    AbstractTable queue_data = sysTable("queue_data");
                    *hash<auto> rv = queue_data.selectRow(sh);
                    if (rv) {
                        # lock row before returning
                        queue_data.update(
                            {"user_interaction_locked": 1, "user_interaction_user": user},
                            {"queueid": queueid, "queuekey": rv.queuekey}
                        );
                        rv.data = deserialize_qorus_data(rv.data);
                    }
                    return rv;
                } catch (hash<ExceptionInfo> ex) {
                    if (restartTransaction(ex)) {
                        continue;
                    }
                    rethrow;
                }
                break;
            }
        }

        /*
            @param wfiid resolves into workflow_instanceid numeric(14) NULL,
            @param stepid resolves into stepid numeric(14) NULL,
            @param ind resolves into ind numeric(5) NULL,
            @param severity resolves into severity varchar(20) NOT NULL,
            @param status resolves into retry numeric(1) NOT NULL,
            @param err resolves into error varchar(240) NOT NULL,
            @param desc resolves into description varchar(4000) NULL,
            @param info resolves into info text NULL,
            @param business resolves into business_error numeric(1) NULL,

            @return error_instanceid numeric(14) NOT NULL,
         */
        int insertErrorInstance(*softint wfiid, *softint stepid, *softint ind, string severity, softint status, string err, string desc, any info, *softbool business) {
            info = serialize_qorus_data(info);

            if (desc.size() > OMQ::SQLDescLen)
                desc = trunc_str(desc, OMQ::SQLDescLen, encoding);

            hash ins = {
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
                "severity": severity,
                "retry": status,
                "error": err,
                "description": desc.substr(0, 240),
                "info": info,
                "business_error": business ? 1 : NOTHING,
            };
            return insertErrorInstanceImpl(ins);
        }

        private int insertErrorInstanceImpl(hash ins) {
            AbstractTable t = sysTable("error_instance");
            return t.insert(ins, {"returning": "error_instanceid"}).error_instanceid;
        }

        softbool deleteOrderKey(softint wfiid, string key, softstring value) {
            checkOrderKeys(key, value);
            hash wh = {
                "workflow_instanceid": wfiid,
                "keyname": key,
                "value": value,
            };
            return sysTable("order_instance_keys").del(wh);
        }

        softbool updateOrderKey(softint wfiid, string key, softstring new_value, softstring old_value, bool truncate) {
            checkOrderKeys(key, new_value, truncate);
            hash upd = {
                "value": new_value,
            };
            hash wh = {
                "workflow_instanceid": wfiid,
                "keyname": key,
                "value": old_value,
            };
            return sysTable("order_instance_keys").update(upd, wh);
        }

        # transaction restart managed by caller
        *hash cacheSegments(softint wfiid) {
            hash sh = {
                "columns": ("segmentid", "segmentstatus", "custom_status"),
                "where": {"workflow_instanceid": wfiid,},
                "orderby": "created",
            };
            return sysTable("segment_instance").select(sh);
        }

        # transaction restart managed by caller
        *hash<auto> cacheWorkflowData(softint wfiid) {
            *hash q = omqp.selectRow("select workflowid, workflowstatus, status_sessionid,
                                    parent_workflow_instanceid, subworkflow, external_order_instanceid,
                                    staticdata, dynamicdata, business_error,
                                    wi.workflowstatus_orig, wi.custom_status,
                                    operator_lock, scheduled, priority, started, errors, retries
                                from workflow_instance wi, order_instance oi
                                where wi.workflow_instanceid = oi.workflow_instanceid
                                and wi.workflow_instanceid = %v", wfiid);

            # in case there is no workflow order data, do not make useless further queries
            if (!q) {
                return;
            }
            # add workflow_feedback data if any
            HashListIterator hi(omqp.select("select keyname, info from workflow_feedback where "
                "workflow_instanceid = %v", wfiid));
            map q.feedback.($1.keyname) = deserialize_qorus_data($1.info), hi;

            # add sensitive data if any
            hi = new HashListIterator(omqp.select("select skey, svalue, data, iv, mac, meta, miv, mmac from "
                "sensitive_order_data where workflow_instanceid = %v", wfiid));
            map q.sensitive_data{$1.skey}{$1.svalue} = $1.("data", "iv", "mac", "meta", "miv", "mmac"), hi;

            # add sensitive data aliases if any
            hi = new HashListIterator(omqp.select("select alias, skey, svalue from sensitive_order_data_keys where "
                "workflow_instanceid = %v", wfiid));
            foreach hash<auto> h in (hi) {
                reference a = \q.sensitive_data{h.skey}{h.svalue}.aliases;
                if (!a)
                    a = ();
                a += h.alias;
            }

            # issue #2880: add step data if any
            hi = new HashListIterator(omqp.select("select stepid, ind, data from step_instance_data where "
                "workflow_instanceid = %v", wfiid));
            map q.step_data{$1.stepid}[$1.ind] = deserialize_qorus_data($1.data), hi;

            return q;
        }

        # returns NOTHING for OK, -1 for error
        *int setWorkflowInstanceError(softint wfiid, softint segid, softint stepid, softlist<softint> ind, softint sessionid, any business_error) {
            if (!omqp.exec("update workflow_instance set workflowstatus = 'E', business_error = %v, custom_status = NULL where workflow_instanceid = %v and workflowstatus not in ('X', 'C', 'B') and status_sessionid in (0, %v)", business_error, wfiid, sessionid)) {
                #log(LoggerLevel::FATAL, "DEBUG: SQLInterface::setWorkflowInstanceError(wfiid=%n, segid=%n, stepid=%n, ind=%n, sessionid=%n) wf failed: %n", wfiid, segid, stepid, ind, sessionid, omqp.selectRow("select * from workflow_instance where workflow_instanceid = %d", any wfiid));
                return -1;
            }
            if (!omqp.exec("update segment_instance set segmentstatus = 'E', custom_status = NULL where workflow_instanceid = %v and segmentid = %v and segmentstatus not in ('C', 'X')", wfiid, segid)) {
                #log(LoggerLevel::FATAL, "DEBUG: SQLInterface::setWorkflowInstanceError(wfiid=%n, segid=%n, stepid=%n, ind=%n, sessionid=%n) seg failed: %n", wfiid, segid, stepid, ind, sessionid, omqp.selectRow("select * from segment_instance where workflow_instanceid = %d and segmentid = %d", any wfiid, any segid));
                return -1;
            }

            if (!sysTable("step_instance").update({"stepstatus": "E", "custom_status": NULL},
                {"workflow_instanceid": wfiid, "stepid": stepid, "ind": op_in(ind), "stepstatus": op_ne("C")})) {
                #log(LoggerLevel::FATAL, "DEBUG: SQLInterface::setWorkflowInstanceError(wfiid=%n, segid=%n, stepid=%n, ind=%n, sessionid=%n) step failed: %n", wfiid, segid, stepid, ind, sessionid, omqp.selectRow("select * from step_instance where workflow_instanceid = %d and stepid = %d and ind = %d", any wfiid, any stepid, any ind));
                return -1;
            }
        }

        softbool updateWorkflowStatus(softint wfiid, string status) {
            return sysTable("workflow_instance").update({"workflowstatus": status,},
                                                        {"workflow_instanceid": wfiid});
        }

        int setQueueDataError(softint queueid, softstring queuekey) {
            hash upd = {
                "queue_data_status": "E",
            };
            hash wh = {
                "queueid": queueid,
                "queuekey": queuekey,
            };
            return sysTable("queue_data").update(upd, wh);
        }

        # WorkflowQueue
        # transaction restart managed by caller
        hash workflowReadyQueueInit(softint wfid) {
            return omqp.selectRow("select min(workflow_instanceid) as minimum,
                                        max(workflow_instanceid) as maximum,
                                        count(1) as count
                                    from workflow_instance
                                    where status_sessionid = 0
                                        and workflowid = %v
                                        and workflowstatus in ('Y', 'S')",
                                    wfid);
        }

        # transaction restart managed by caller
        hash workflowEventQueueInit(softint wfid) {
            return omqp.selectRow("select min(workflow_instanceid) as minimum,
                                        max(workflow_instanceid) as maximum,
                                        count(1) as count
                                    from workflow_instance
                                    where status_sessionid = 0
                                        and workflowid = %v
                                        and workflowstatus not in ('X', 'C', 'Y', 'S', 'B')",
                                    wfid);
        }

        # transaction restart managed by caller
        hash workflowDestructorQueueInit(softint wfid, softint sid) {
            return omqp.selectRow("select min(workflow_instanceid) as minimum,
                                        max(workflow_instanceid) as maximum,
                                        count(1) as count
                                    from workflow_instance
                                    where status_sessionid = %v
                                  and synchronous = 0
                                        and workflowid = %v",
                                        sid, wfid);
        }

        int workflowReadyQueueConstructor(softint min, softint max, softint sid, softint wid) {
            # grab WFs
            # Oracle query cost: 208 - this is an expensive query when there are a lot of workflow instances in the DB
            return omqp.exec("update workflow_instance set status_sessionid = %v
                                where status_sessionid = 0
                                    and workflowid = %v
                                    and workflowstatus in ('Y','S')
                                    and workflow_instanceid >= %v
                                    and workflow_instanceid <= %v", sid, wid, min, max);
        }

        int workflowEventQueueConstructor(softint min, softint max, softint sid, softint wid) {
            # grab WFs
            # Oracle query cost: 208 - this is an expensive query when there are a lot of workflow instances in the DB
            return omqp.exec("update workflow_instance set status_sessionid = %v
                                where status_sessionid = 0
                                    and workflowid = %v
                                    and workflowstatus not in ('X', 'C', 'Y', 'S', 'B')
                                    and workflow_instanceid >= %v
                                    and workflow_instanceid <= %v", sid, wid, min, max);
        }
        int workflowQueueDestructor(softint min, softint max, softint sid, softint wid) {
            # release WFs
            return omqp.exec("update workflow_instance set status_sessionid = 0
                        where workflowid = %v and synchronous = 0 and status_sessionid = %v
                                    and workflow_instanceid >= %v
                                    and workflow_instanceid <= %v", wid, sid, min, max);
        }

        # transaction restart managed by caller
        hash workflowQueueInitCommonSubAsync(softint min, softint max, softint sid, softint wid) {
            hash res;
            res.subwf = omqp.select("
                select
                    wi.workflow_instanceid,
                    wi.parent_workflow_instanceid,
                    wi.subworkflow,
                    swi.workflow_instanceid as subworkflow_instanceid,
                    si.ind,
                    swi.workflowstatus as status,
                    sswi.corrected,
                    swi.modified,
                    si.stepid,
                    wi.priority
                from
                    workflow_instance wi,
                    step_instance si,
                    subworkflow_instance sswi,
                    workflow_instance swi
                where
                        wi.workflowid = %v
                    and wi.workflow_instanceid = si.workflow_instanceid
                    and wi.workflowstatus not in ('X', 'B')
                    and si.stepstatus != 'C'
                    and wi.synchronous = 0
                    and wi.status_sessionid = %v
                    --
                    and si.workflow_instanceid = sswi.workflow_instanceid
                    and si.stepid = sswi.stepid
                    and si.ind = sswi.ind
                    --
                    and sswi.subworkflow_instanceid = swi.workflow_instanceid
                    and ((corrected is null
                            and swi.workflowstatus in ('C', 'E')
                            and stepstatus != swi.workflowstatus)
                        or corrected = 1)
                    and wi.workflow_instanceid >= %v
                    and wi.workflow_instanceid <= %v",
                                    wid, sid, min, max);
            res.queue = omqp.select("
            select
                    queuekey, qd.workflow_instanceid,
                    ind, corrected, parent_workflow_instanceid,
                    subworkflow,
                    qd.modified,
                    qd.stepid,
                    queueid,
                    wi.priority
                from
                    workflow_instance wi, queue_data qd
                where
                    qd.workflow_instanceid = wi.workflow_instanceid
                    and workflowstatus not in ('X', 'B')
                    and wi.workflowid = %v
                    and status_sessionid = %v
                    and synchronous = 0
                    and queue_data_status = 'R'
                    and wi.workflow_instanceid >= %v
                    and wi.workflow_instanceid <= %v",
                                    wid, sid, min, max);

            res.sync = omqp.select("
                select
                    wi.workflow_instanceid,
                    wi.parent_workflow_instanceid,
                    wi.subworkflow,
                    si.ind,
                    si.skip as \"corrected\",
                    we.modified,
                    si.stepid,
                    wi.priority
                from
                    workflow_instance wi,
                    step_instance si,
                    step_instance_events sie,
                    workflow_events we
                where
                        wi.workflowid = %v
                    and wi.workflow_instanceid = si.workflow_instanceid
                    and wi.workflowstatus not in ('X', 'B', 'C')
                    and si.stepstatus != 'C'
                    and wi.synchronous = 0
                    and wi.status_sessionid = %v
                    --
                    and si.workflow_instanceid = sie.workflow_instanceid
                    and si.stepid = sie.stepid
                    and si.ind = sie.ind
                    --
                    and sie.workflow_event_typeid = we.workflow_event_typeid
                    and sie.eventkey = we.eventkey
                    and (we.event_posted = 1 or si.skip = 1)
                    and wi.workflow_instanceid >= %v
                    and wi.workflow_instanceid <= %v",
                                    wid, sid, min, max);

            return res;
        }

        # WorkflowInstance
        workflowInstanceCleanupSynchronous(softint wfiid) {
            # unset synchronous flag on workflow instance
            sysTable("workflow_instance").update({"synchronous": 0},
                                                 {"workflow_instanceid": wfiid});
        }

        # transaction restart managed by caller
        *hash workflowInstanceExecuteSubWorkflowStep(softint wid, softint stepid, softint ind) {
            # first get subworkflow_instanceid
            hash sh = {
                "columns": ("subworkflow_instanceid", "corrected"),
                "where": {
                    "workflow_instanceid": wid,
                    "stepid": stepid,
                    "ind": ind,
                },
            };
            return sysTable("subworkflow_instance").selectRow(sh);
        }

        # transaction restart managed by caller
        *hash workflowInstanceGetStepInstanceEvent(softint wfiid, softint stepid, softint ind) {
            hash sh = {
                "columns": ("workflow_event_typeid", "eventkey",),
                "where": {
                    "workflow_instanceid": wfiid,
                    "stepid": stepid,
                    "ind": ind,
                },
            };
            return sysTable("step_instance_events").selectRow(sh);
        }

        # returns False, True, or NOTHING
        # transaction restart managed by caller
        *softbool getWorkflowEventStatus(softint eventid, string eventkey) {
            hash sh = {
                "columns": ("event_posted",),
                "where": {
                    "workflow_event_typeid": eventid,
                    "eventkey": eventkey,
                },
            };
            return sysTable("workflow_events").selectRow(sh).event_posted;
        }

        createWorkflowEvent(softint eventid, string eventkey, bool posted = False) {
            hash ins = {
                "workflow_event_typeid": eventid,
                "eventkey": eventkey,
                "event_posted": posted ? 1 : 0,
            };
            sysTable("workflow_events").insert(ins);
        }

        softint postWorkflowEvent(softint eventid, string eventkey) {
            hash wh = {
                "workflow_event_typeid": eventid,
                "eventkey": eventkey,
            };
            return sysTable("workflow_events").update({"event_posted": 1}, wh);
        }

        # transaction handling/recovery handled by the caller
        /** returns a hash keyed by workflowid, values are the row hashes selected below
        */
        *hash<string, list<hash<auto>>> getStepInstanceEventList(softint eventid, string eventkey) {
            hash<auto> sh = {
                "columns": ("workflowid", "parent_workflow_instanceid", "subworkflow", "priority", "sie.workflow_instanceid", "sie.stepid", "sie.ind",),
                "join": join_inner(sysTable("step_instance_events"), "sie", ("workflow_instanceid": "workflow_instanceid")),
                "where": {
                    "sie.workflow_event_typeid": eventid,
                    "sie.eventkey": eventkey,
                },
            };
            hash<string, list<hash<auto>>> rv;
            foreach hash<auto> row in (sysTable("workflow_instance").selectRows(sh)) {
                row.subworkflow = row.subworkflow.toBool();
                if (!rv{row.workflowid}) {
                    rv{row.workflowid} = ();
                }
                rv{row.workflowid} += row;
            }
            return rv;
        }

        # Workflow
        *hash<auto> workflowLoadFunctionID(softint fid) {
            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return workflowLoadFunctionIDImpl(fid);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
            }
        }

        private *hash<auto> workflowLoadFunctionIDImpl(softint fid) {
            hash<auto> sh = {
                "columns": ("name", "version", "body", ),
                "where": {"function_instanceid": fid},
            };
            return sysTable("function_instance").selectRow(sh);
        }

        *hash<auto> workflowLoadFunctionIDs(any fid_list) {
            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return workflowLoadFunctionIDsImpl(fid_list);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
            }
        }

        private *hash<auto> workflowLoadFunctionIDsImpl(any fid_list) {
            hash<auto> sh = (
                "columns": ("name", "version", "function_instanceid", "body"),
                "where": (
                    "function_instanceid": op_in(fid_list),
                ),
            );
            return sysTable("function_instance").select(sh);
        }

        # ServiceManager
        *hash<auto> serviceManagerAutoStart() {
            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return omqp.select("select service_type, name, version, serviceid from services where (name, "
                        "created) in (select name, max(created) as created from services group by name) and "
                        "autostart = 1");
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex)) {
                        continue;
                    }
                    rethrow;
                }
            }
        }

        serviceManagerSetAutostartStatus(softbool status, softint serviceid) {
            hash<auto> upd = {
                "autostart": status ? 1 : 0,
                "manual_autostart": 1,
            };
            hash<auto> wh = {
                "serviceid": serviceid,
            };
            sysTable("services").update(upd, wh);
        }

        # Control
        *hash<auto> controlExecSynchronousWorkflowOnExistingOrder(softint wfiid) {
            while (True) {
                try {
                    on_error omqp.rollback();

                    QDBG_TEST_CLUSTER_FAILOVER();
                    return controlExecSynchronousWorkflowOnExistingOrderImpl(wfiid);
                } catch (hash<ExceptionInfo> ex) {
                    # restart the transaction if necessary
                    if (restartTransaction(ex))
                        continue;
                    rethrow;
                }
            }
        }

        private *hash<auto> controlExecSynchronousWorkflowOnExistingOrderImpl(softint wfiid) {
            hash<auto> sh = {
                "columns": ("w.name", "w.version", "w.workflowid",),
                "join": join_inner(sysTable("workflows"), "w", {"workflowid": "workflowid"}),
                "where": {
                    "workflow_instanceid": wfiid,
                },
            };
            return sysTable("workflow_instance").selectRow(sh);
        }

        # InstanceData
        int instanceDataSaveData(*softstring str, softint wfiid) {
            return sysTable("order_instance").update({"dynamicdata": str},
                                                     {"workflow_instanceid": wfiid});
        }

        # update StepInstanceData; optionally check queue_data for a user lock on the step data
        int stepInstanceDataSaveData(*softstring str, softint wfiid, softint stepid, int ind, *string user) {
            hash<auto> wh = {
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
            };
            if (user && user != "%SYS%") {
                *string current_user = sysTable("queue_data").selectRow({
                    "columns": "user_interaction_user",
                    "where": wh,
                    "forupdate": True,
                }).user_interaction_user;
                if (current_user.val() && current_user != user) {
                    throw "REPLACE-STEP-DATA-ERROR", sprintf("user %y cannot replace step data for workflow instance "
                        "%d stepid %d[%d] because user %y already owns the lock", user, wfiid, stepid, ind,
                        current_user);
                }
            }

            if (!str.val()) {
                return sysTable("step_instance_data").del(wh);
            } else {
                return sysTable("step_instance_data").update({"data": str},
                    {"workflow_instanceid": wfiid, "stepid": stepid, "ind": ind});
            }
        }

        # returns True if the lock was broken, False if not (was not set)
        bool clearQueueDataLock(softint wfiid, softint stepid, int ind) {
            hash<auto> wh = {
                "workflow_instanceid": wfiid,
                "stepid": stepid,
                "ind": ind,
            };

            AbstractTable queue_data = sysTable("queue_data");

            *hash<auto> row = queue_data.selectRow({
                "where": wh,
                "forupdate": True,
            });

            if (!row) {
                throw "NO-DATA", sprintf("no step corresponding to %y can be found", wh);
            }

            if (!row.user_interaction_user) {
                return False;
            }

            queue_data.update({
                    "user_interaction_user": NOTHING,
                    "user_interaction_locked": 0,
            }, wh);
            return True;
        }

        # WFEntry (SegmentManager.qc)
        int wfEntryReplaceStaticData(*string str, softint wfiid) {
            return sysTable("order_instance").update({"staticdata": str},
                                                     {"workflow_instanceid": wfiid});
        }

        # OrderInstanceNotes
        int orderInstanceNotesSave(softint wfiid, list notes) {
            BulkInsertOperation bulk(sysTable("order_instance_notes"));
            on_error {
                bulk.discard();
            }

            ListIterator it(notes);
            while (it.next()) {
                hash obj = it.getValue() + {"workflow_instanceid": wfiid};
                delete obj.saved;
                bulk.queueData(obj);
            }
            bulk.flush();

            sysTable("workflow_instance").update({"note_count": uop_plus(notes.size())},
                                                 {"workflow_instanceid": wfiid}
                                                );
            return notes.size();
        }

        # transaction restart handled by caller
        hash orderInstanceNotesGet(softint wfiid) {
            hash sh = {
                "where": { "workflow_instanceid": wfiid, },
                "orderby": "created",
            };
            return sysTable("order_instance_notes").select(sh);
        }

        sessionClose(softint sid) {
            sysTable("sessions").update({"sessionstatus": "COMPLETE"},
                                        {"sessionid": sid});
        }

        upsertFeedback(softint wfiid, string key, string val) {
            hash vals = {
                "workflow_instanceid": wfiid,
                "keyname": key,
                "info": val,
            };
            sysTable("workflow_feedback").upsert(vals);
        }
    }

    public class OracleServerSQLInterface inherits OracleSQLInterface, ServerSQLInterface {
        constructor(QdspClient omqp) : ServerSQLInterface(omqp), OracleSQLInterface(omqp) {
        }

        hash<auto> smSetErrorIntern(softint wfiid, softint qsid, string user = "system") {
            # try to lock workflow
            hash<auto> q = omqp.exec("begin qorus_api.sm_set_error_intern(%v, %v, %v, :status_sessionid, :workflowstatus, :parent_workflow_instanceid, :subworkflow, :priority, :operator_lock, :stepcount, :segcount, :err); end;",
                                    wfiid, qsid, user);
            #printf("q=%n\n", q);

            if (q.err == NULL) {
                return q;
            }

            if (q.err == "WORKFLOW-ERROR") {
                throw "WORKFLOW-ERROR", sprintf("workflow_instanceid %d does not exist", wfiid);
            }
            else if (q.err == "WORKFLOW-SESSION-ERROR") {
                throw "WORKFLOW-SESSION-ERROR", sprintf("workflow_instanceid %d is currently being processed by foreign session %d", wfiid, q.status_sessionid);
            }
            else if (q.err == "WORKFLOW-STATUS-ERROR") {
                throw "WORKFLOW-STATUS-ERROR", sprintf("cannot update status %s ('%s') to ERROR ('E')", SQLStatMap.(q.workflowstatus), q.workflowstatus);
            }

            throw "UNKNOWN-ERROR", sprintf("err: %y", q.err);
        }

        nothing smSkipStepSQL(softint wfiid, softint stepid, softint ind, softint qsid, bool swf, string user = "system") {
            omqp.beginTransaction();

            # issue 1952: make sure no subworkflow step has been bound before executing changes in the schema
            if (swf) {
                *hash swfq = workflowInstanceExecuteSubWorkflowStep(wfiid, stepid, ind);
                if (swfq.val())
                    throw "SKIP-STEP-ERROR", sprintf("cannot skip subworkflow step %d/%d with workflow_instanceid %d with bound subworkflow instanceid %d (corrected: %d)", stepid, ind, wfiid, swfq.subworkflow_instanceid, swfq.currected);
            }

            # try to lock flow
            hash res = omqp.exec("begin qorus_api.sm_skip_step_sql(%v, %v, %v, %v, %v, :err, :operator_lock, :wfstat, :statsid, :stepstat); end;",
                                wfiid, qsid, stepid, ind, user, Type::String, Type::String, Type::String, Type::String);
            if (res.err == NULL) return;

            if (res.err == "SKIP-STEP-ERROR-WF")
                throw "SKIP-STEP-ERROR", sprintf("workflow_instanceid %d does not exist", wfiid);
            else if (res.err == "WORKFLOW-IN-PROGRESS")
                throw "STEP-STATUS-ERROR", sprintf("cannot update a step for a workflow with status %s", res.wfstat);
            else if (res.err == "SESSION-ERROR")
                throw "SESSION-ERROR", sprintf("workflow instance %d is currently owned by foreign session %d and cannot be updated by this session (%d)", wfiid, res.statsid, qsid);
            else if (res.err == "SKIP-STEP-ERROR")
                throw "SKIP-STEP-ERROR", sprintf("stepid %d/%d has not been executed in workflow_instance %d", stepid, ind, wfiid);
            else if (res.err == "STEP-STATUS-ERROR")
                throw "STEP-STATUS-ERROR", sprintf("can't update steps with status %n", res.stepstat);

            # no return here
        }

        # transaction restart handled by caller
        *hash smGetWorkflowInstanceStatusSQL(any wfiid) {
            # need wq in hash format; need seg in select (hash of lists) format
            *hash res = omqp.select("begin qorus_api.sm_get_wf_instance_status_sql(%v, :status, :wq, :seg); end;",
                                    wfiid, Type::String, Type::Hash, Type::Hash);

            if (!elements res.wq.name)
                return;

            hash ret;

            # get workflow & workflow_instance information
            context (res.wq) {
                ret.wq = %%;
                break;
            }

            # add in workflow_instanceid key
            ret.wq.workflow_instanceid = wfiid;

            # get segment information
            ret.seg = res.seg;

            return ret;
        }

        # transaction restart handled by caller
        hash smQueueEventsIntern(softint wfiid) {
            # check for SQL injections is done in PL/SQL package
            *hash rv = omqp.select("begin qorus_api.sm_queue_events_intern(%v, :segmentids, :subworkflows, :asyncs, :retries, :syncs); end;",
                                   wfiid, Type::Hash, Type::Hash, Type::Hash, Type::Hash, Type::Hash);
            return rv;
        }

        updateFinalJobInstanceStatus(int jid, int jiid, string stat, date last_executed) {
            omqp.exec("begin qorus_api.update_final_job_inst_status(%v, %v, %v, %v); end;",
                        jid, jiid, stat, last_executed);
        }

        *hash<auto> cacheWorkflowData(softint wfiid) {
            hash<auto> q = omqp.selectRows("begin qorus_api.cache_workflow_data(%v, :resultset, :feedback, "
                ":sensitive_data, :sensitive_data_keys, :step_data); end;", wfiid, Type::Hash, Type::Hash, Type::Hash,
                Type::Hash, Type::Hash);
            hash h = q.resultset[0];
            # add workflow_feedback data if any
            map h.feedback.($1.keyname) = deserialize_qorus_data($1.info), q.feedback.iterator();
            # add sensitive data if any
            map h.sensitive_data{$1.skey}{$1.svalue} = $1.("data", "iv", "mac", "meta", "miv", "mmac"),
                q.sensitive_data.iterator();
            # add sensitive data aliases if any
            foreach hash sh in (q.sensitive_data_keys) {
                reference a = \h.sensitive_data{sh.skey}{sh.svalue}.aliases;
                if (!a)
                    a = ();
                a += sh.alias;
            }
            # issue #2880: add step data if any
            map h.step_data{$1.stepid}[$1.ind] = deserialize_qorus_data($1.data), q.step_data;

            return h;
        }
    }

    public class PostgreServerSQLInterface inherits PostgreSQLInterface, ServerSQLInterface {
        constructor(QdspClient omqp) : ServerSQLInterface(omqp), PostgreSQLInterface(omqp) {
        }
    }

    public class MySQLServerSQLInterface inherits MySQLInterface, ServerSQLInterface {
        constructor(QdspClient omqp) : ServerSQLInterface(omqp), MySQLInterface(omqp) {
        }

        int insertSla(string name, string units, string description) {
            AbstractTable sla = sysTable("sla");
            softint id = getNextSequenceValue("seq_sla");
            sla.insert(("slaid": id, "name": name, "units": units, "description": description));
            return id;
        }

        private int sessionOpen2Impl(hash ins) {
            ins.sessionid = getNextSequenceValue("seq_sessions");
            sysTable("sessions").insert(ins);
            return ins.sessionid;
        }

        private int insertErrorInstanceImpl(hash ins) {
            ins.error_instanceid = getNextSequenceValue("seq_error_instance");
            sysTable("error_instance").insert(ins);
            return ins.error_instanceid;
        }

        private int insertJobErrorImpl(hash ins) {
            ins.job_errorid = getNextSequenceValue("seq_job_errorid");
            sysTable("job_errors").insert(ins);
            return ins.job_errorid;
        }

        private int insertJobInstanceImpl(hash ins) {
            ins.job_instanceid = getNextSequenceValue("seq_job_instance");
            sysTable("job_instance").insert(ins);
            return ins.job_instanceid;
        }

    }
}
