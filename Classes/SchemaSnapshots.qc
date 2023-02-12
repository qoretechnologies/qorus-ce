# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%requires BulkSqlUtil

#! Main Qorus namespace
public namespace OMQ {
/** Snapshots: A helper class for data structure transformation.

    Design info: https://bugs.qoretechnologies.com/projects/qorus/wiki/Qorus_Workflow_and_Job_Instance_Snapshots

    It transforms a hash in form objectid/datemask/status/total_count into
    single-row-hashes with the same keys.

    It's a Qorus private class - not exposed to public API.
  */
class SnapshotIterator inherits AbstractIterator {
    private {
        list<auto> m_data = ();
        bool m_valid = False;
    }

    constructor(hash<auto> h) : AbstractIterator() {
        # in memory transformation. Not ideal. But I don't
        # expect too large datasets here for now
        foreach string objectid in (keys h) {
            foreach string modified in (keys h{objectid}) {
                foreach string status in (keys h{objectid}{modified}) {
                    int val = h{objectid}{modified}{status};
                    hash<auto> row = {
                        "objectid": int(objectid),
                        "modified": date(modified, AbstractSchemaSnapshotManager::DATE_MASK),
                        "status": status,
                        "total_count": val,
                    };

                    push m_data, row;
                }
            }
        }
    }

    hash<auto> getValue() {
        if (!valid()) {
            throw "INVALID-ITERATOR", "Call next() first!";
        }

        return m_data[0];
    }

    bool valid() {
        return m_valid;
    }

    bool next() {
        if (m_valid) {
            shift m_data;
        } else {
            m_valid = True;
        }

        int s = m_data.size();

        if (!s) {
            m_valid = False;
        }

        return s > 0;
    }

} # class SnapshotIterator
/** A base abstract class for all snapshot managers.

    Design info: https://bugs.qoretechnologies.com/projects/qorus/wiki/Qorus_Workflow_and_Job_Instance_Snapshots

    It's a Qorus private class - not exposed to public API.
  */
class AbstractSchemaSnapshotManager {
    private {
        #! A flag to know if is the background processing running
        bool m_running = False;
        Counter m_running_counter();
        # for an interruptible sleep
        Mutex m_running_mtx();
        Condition m_running_cond();

        #! snapshot staging table
        SqlUtil::AbstractTable m_stage_table;
        #! snapshot final table
        SqlUtil::AbstractTable m_snapshot_table;
        #! instance table
        SqlUtil::AbstractTable m_instance_table;

        #! a select statement (hash) for insert as select used m_stage_table -> m_snapshot_table
        const SH_STAGE = {
            "columns" : (
                "rowid", "objectid", "modified_orig", "modified_new",
                "status_orig", "status_new", "dml_operation", "created",
            ),
            "orderby" : "created",
            "forupdate" : True,
        };

        #! default timeout for waiting loops
        const TIMEOUT = 5s;

        #! internal profiler structures
        hash<auto> m_profiler = {};
        date m_profiler_start;

        #! cache used for status instrumentation.
        /** it's read from the DB (snapshot table) ad the beginning of
            processing in readDBSummary() in runImplementation().
            Then all count changes are perfromed in memory because
            the original DB read is a fulltable/group by scan.
            The prometheus API can read it using getStatusCache()
         */
        hash<string, int> m_status_cache = {};
        #! cache used for status per interface instrumentation
        hash<string, hash<string, int>> m_interface_status_cache = {};
    }

    public {
        #! default time window - we split instances per hours
        const DATE_MASK = "YYYYMMDDHH";
    }

    constructor(SqlUtil::AbstractTable instance_table,
                SqlUtil::AbstractTable stage_table,
                SqlUtil::AbstractTable snapshot_table) {
        m_instance_table = instance_table;
        m_stage_table = stage_table;
        m_snapshot_table = snapshot_table;
    }

    destructor() {
        qlog(LoggerLevel::INFO, "snapshot profiler: %n", m_profiler);
    }

    start() {
        m_running_counter.inc();
        m_running = True;
        background runImplementation();
    }

    stop() {
        # interrupt sleep
        {
            m_running_mtx.lock();
            on_exit m_running_mtx.unlock();
            m_running = False;
            m_running_cond.broadcast();
        }
        m_running_counter.waitForZero();
        m_status_cache = {};
        m_interface_status_cache = {};
    }

    private profilerStart() {
        m_profiler_start = now_ms();
    }

    private profiler(string phase) {
        m_profiler{phase} = now_ms() - m_profiler_start;
        m_profiler_start = now_ms();
    }

    #! Return actual status cache for instrumentation metrics.
    /**
        note: it's locked to avoid conflicts with runImplementationInDbImpl()
     */
    hash<auto> getStatusCache() {
        sqlif.lockSnapshot(m_instance_table.getName().lwr());
        on_exit sqlif.unlockSnapshot(m_instance_table.getName().lwr());
        return m_status_cache;
    }

    #! the same as in getStatusCache(), but it's split per interface name
    hash<auto> getInterfaceStatusCache() {
        sqlif.lockSnapshot(m_instance_table.getName().lwr());
        on_exit sqlif.unlockSnapshot(m_instance_table.getName().lwr());
        return m_interface_status_cache;
    }

    # don't override this method. All sub-calls are mandatory here
    private runImplementation() {
        on_exit {
            m_running_counter.dec();
        }
        try {
            readDBSummary();
            runImplementationImpl();
        } catch (hash<ExceptionInfo> ex) {
            qlog(LoggerLevel::ERROR, "error in snapshot thread: %s", get_exception_string(ex));
        }
    }

    /** Separate DB handling from waiting code to prevent sending commit/rollback into DB.
        The waiting condition code is handled by 'abstract runImplementation()'

        runImplementationInDb() iterates over a staging table and upserts rows
        in a snapshot target table. It also deletes snapshot target data when required.

        @returns int count of lines processed from staging to target tables
      */
%ifdef QorusServer
    private
%endif
    int runImplementationInDb() {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                return runImplementationInDbImpl();
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::ERROR, "error in snapshot thread: %s", get_exception_string(ex));
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }
    }

    # perform "clever" decrement of the interface cache. Keys should be removed
    # if there are no data to be hold. It follows how the per interface data
    # display works.
    private ifaceStatusCacheDecrement(softstring objectid, string status_orig) {
        # really decrement
        m_interface_status_cache{objectid}{status_orig}--;

        # delete objectid.statuscode if needed
        if (m_interface_status_cache{objectid}{status_orig} <= 0) {
            delete m_interface_status_cache{objectid}{status_orig};
            # delete objectid if there are no statuses in it
            if (!m_interface_status_cache{objectid}.size()) {
                delete m_interface_status_cache{objectid};
            }
        }
    }

    private int runImplementationInDbImpl() {
        on_success m_stage_table.commit();
        on_error m_stage_table.rollback();

        sqlif.lockSnapshot(m_instance_table.getName().lwr());
        on_exit sqlif.unlockSnapshot(m_instance_table.getName().lwr());

        int ret = 0;
        AbstractSQLStatement stmt = m_stage_table.getStatement(SH_STAGE);
        # SqlUtil::AbstractTable::UpsertUpdateFirst is used here because there is
        # always one insert but usually more updates (status change)
        BulkUpsertOperation bulk_upsert(m_snapshot_table,
                        {"upsert_strategy" : SqlUtil::AbstractTable::UpsertUpdateFirst });

        while (hash data = stmt.fetchColumns(1000)) {
            m_profiler.iterations++;
            profilerStart();

            # data to be inserted
            hash to_change = hash();
            list rowids_to_delete = list();

            context (data) {
                push rowids_to_delete, %rowid;
                ret++;

                switch (%dml_operation) {
                    case "I":
                        string mn = format_date(DATE_MASK, %modified_new);
                        to_change{%objectid}{mn}{%status_new}++;
                        m_status_cache{%status_new}++;
                        m_interface_status_cache{%objectid}{%status_new}++;
                        break;
                    case "U":
                        string mn = format_date(DATE_MASK, %modified_new);
                        string mo = format_date(DATE_MASK, %modified_orig);
                        to_change{%objectid}{mn}{%status_new}++;
                        m_status_cache{%status_new}++;
                        m_interface_status_cache{%objectid}{%status_new}++;
                        to_change{%objectid}{mo}{%status_orig}--;
                        m_status_cache{%status_orig}--;
                        ifaceStatusCacheDecrement(%objectid, %status_orig);
                        break;
                    case "D":
                        string mo = format_date(DATE_MASK, %modified_orig);
                        to_change{%objectid}{mo}{%status_orig}--;
                        m_status_cache{%status_orig}--;
                        ifaceStatusCacheDecrement(%objectid, %status_orig);
                        break;
                } # switch
            } # context

            profiler("context_tranformation");

            # batch updates regarding to_change
            SnapshotIterator it(to_change);
            #auto res = m_snapshot_table.upsertFromIterator(it); # pending #2962
            hash target_cache = {};

            while (it.next()) {
                hash it_row = it.getValue();

                string target_cache_key = sprintf("%s-%n-%s",
                                                 it_row.objectid,
                                                 it_row.modified,
                                                 it_row.status
                                                 );

                if (!target_cache.hasKey(target_cache_key)) {
                    *hash row = m_snapshot_table.selectRow({"where" : it.getValue() - "total_count"});
                    it_row.total_count += row.total_count;
                    target_cache{target_cache_key} = it_row;
                } else {
                    target_cache{target_cache_key}.total_count += it_row.total_count;
                }
            }

            profiler("cache_calculation");

            on_success {
                bulk_upsert.flush();
            }
            on_error {
                bulk_upsert.discard();
            }

            bulk_upsert.queueData(target_cache.values());
            bulk_upsert.flush();

            profiler("bulk_upsert");

            # delete processed lines from snapshot stage
            m_stage_table.del({"rowid": SqlUtil::op_in(rowids_to_delete)});

            profiler("delete_stage");
        } # while fetch

        # clear "deleted" data - just remove it if it's less than 1 - it goes full table scan
        profilerStart();
        m_snapshot_table.del({"total_count" : SqlUtil::op_lt(1),});
        profiler("delete_snapshot");

        return ret;

    } # runImplementationInDb

    /** Reimplement this method for each snapshot manager. It must call
        runImplementationInDb() inside.
      */
    abstract runImplementationImpl();

    /** Reimplement this method for each snapshot manager. It must fill
        m_status_cache with status:count hash
     */
    abstract readDBSummary();

} # class AbstractSchemaSnapshotManager

/** Snapshot manager for workflow instances.

    Design info: https://bugs.qoretechnologies.com/projects/qorus/wiki/Qorus_Workflow_and_Job_Instance_Snapshots

    The trigger is Qorus event related to WFIID status change.

    It's a Qorus private class - not exposed to public API.
  */
class WfSchemaSnapshotManager inherits AbstractSchemaSnapshotManager {
    constructor()
        : AbstractSchemaSnapshotManager(
            get_sql_table_system_trans("omq", "workflow_instance"),
            get_sql_table_system_trans("omq", "workflow_instance_stats_stage"),
            get_sql_table_system_trans("omq", "workflow_instance_stats")
        ) {
    }

    private list<auto> eventFilters() {
        return (
            {"event": QEC_WORKFLOW_DATA_SUBMITTED},
            {"event": QEC_WORKFLOW_STATUS_CHANGED},
            {"event": QEC_WORKFLOW_RECOVERED},
            {"event": QEC_SYSTEM_STARTUP}, # to trigger runImplementationInDb() at the beginning of the processing
            {"event": QEC_SYSTEM_SHUTDOWN}, # to stop runImplementation() in case of shutdown
        );
    }

    readDBSummary() {
        hash<auto> ret = m_stage_table.getDatasource().select("
                select ws.workflowstatus, coalesce(s.total_count, 0) total_count
                from workflow_status ws left outer join
                    (
                        select status, sum(total_count) total_count
                            from workflow_instance_stats
                            group by status
                    ) s
                    on (ws.workflowstatus = s.status)");
        context (ret) {
            m_status_cache{%workflowstatus} = %total_count;
        }

        ret = m_stage_table.getDatasource().select("
                select objectid, status, sum(total_count) total_count
                    from workflow_instance_stats
                    group by objectid, status");
        context (ret) {
            m_interface_status_cache{%objectid}{%status} = %total_count;
        }
    }

    /** Wait until Qorus internal event arrives. It's interested
        in events provided in 'list<auto> eventFilters()'.

        There is also a event-wait-timeout in the loop.
    */
    private runImplementationImpl() {
        int event_id = 1;
        list<auto> event_filter = eventFilters();

        # sometimes it happens that there are no new events for a long period of time, and lines in the
        # STAGE table are kept for long periods or until another unrelated event is raised.
        # For this case we will run a fallback runImplementationInDb() every 15s.
        int fallback_counter = 0;

        while (m_running) {
            hash<auto> events = Qorus.events.getEventsOr(event_id, event_filter, TIMEOUT);
            # exit immediately if shutdown time has arrived
            if (events.shutdown) {
                break;
            }

            # issue #3159: always update the last event_id to ensure that already-scanned events are not rescanned;
            # failure to do this can lead to 100% CPU usage with idle instances
            # NOTE: always set the minimum event ID for the next query to the lastid + 1, so we don't rescan events
            event_id = events.lastid + 1;

            if (events."events".size()) {
                fallback_counter = 0;
            } else {
                ++fallback_counter;
                if (fallback_counter < 4) {
                    continue;
                }
                fallback_counter = 0;
            }

            # issue #3401: exceptions must be handled here as this is running in a background thread
            try {
                runImplementationInDb();
            } catch (hash<ExceptionInfo> ex) {
                qlog(LoggerLevel::ERROR, "exception in snapshot thread: %s", get_exception_string(ex));
            }
        }
    }
} # class WfSchemaSnapshotManager

/** Snapshot manager for job instances.

    Design info: https://bugs.qoretechnologies.com/projects/qorus/wiki/Qorus_Workflow_and_Job_Instance_Snapshots

    The trigger is plain timeout/sleep.

    It's a Qorus private class - not exposed to public API.
  */
class JobSchemaSnapshotManager inherits AbstractSchemaSnapshotManager {
    constructor()
        : AbstractSchemaSnapshotManager(
            get_sql_table_system_trans("omq", "job_instance"),
            get_sql_table_system_trans("omq", "job_instance_stats_stage"),
            get_sql_table_system_trans("omq", "job_instance_stats")
        ) {
    }

    readDBSummary() {
        hash<auto> ret = m_stage_table.getDatasource().select("
                select ws.jobstatus, coalesce(s.total_count, 0) total_count
                    from job_status ws left outer join
                        (
                            select status, sum(total_count) total_count
                                from job_instance_stats
                                group by status
                        ) s
                        on (ws.jobstatus = s.status)");
        context (ret) {
           m_status_cache{%jobstatus} = %total_count;
        }

        ret = m_stage_table.getDatasource().select("
                select objectid, status, sum(total_count) total_count
                    from job_instance_stats
                    group by objectid, status");
        context (ret) {
            m_interface_status_cache{%objectid}{%status} = %total_count;
        }
    }

    /** Wait until timeout/sleep.
    */
    private runImplementationImpl() {
        while (m_running) {
            runImplementationInDb();
            # interruptible sleep
            m_running_mtx.lock();
            on_exit m_running_mtx.unlock();
            m_running_cond.wait(m_running_mtx, TIMEOUT);
        }
    }

} # class JobSchemaSnapshotManager

/** Snapshot public API provider. It provides standalone, static,
    api for SYSTEM services (system.info).

    Design info: https://bugs.qoretechnologies.com/projects/qorus/wiki/Qorus_Workflow_and_Job_Instance_Snapshots

    Keep it in sync with QorusClientCore.qm dummy wrapper for oload
*/
public class SnapshotsInfoHelper {
    #! get report for workflows
    static *hash getReportWfs(date in_date, *softlist wfids, bool with_deprecated = True,
            bool system_overview = False) {
        date trunc_date =  date(format_date(AbstractSchemaSnapshotManager::DATE_MASK, in_date + 1h),
            AbstractSchemaSnapshotManager::DATE_MASK);

        AbstractTable workflows = get_sql_table_system_trans("omq", "workflows");
        AbstractTable workflow_instance = get_sql_table_system_trans("omq", "workflow_instance");
        AbstractTable workflow_instance_stats = get_sql_table_system_trans("omq", "workflow_instance_stats");
        AbstractDatasource ds = workflows.getDatasource();

        list cols = (!system_overview ? ( "w.name", "w.version", "w.workflowid",) : list());

        hash sh_snap = {
            "columns" : cols + ( cop_as("status", "workflowstatus"), cop_as(cop_sum("total_count"), "total"), ),
            "join": join_inner(workflows, "w", {"objectid" : "workflowid"} ),
            "where" : {
                "modified" : op_ge(trunc_date),
            },
            "groupby" : cols + "status",
        };

        if (wfids) {
            sh_snap."where" += {"w.workflowid" : op_in(wfids)};
        }

        if (!with_deprecated) {
            sh_snap."where" += {"w.deprecated" : op_in(NULL, 0)};
        }

        hash sh_live = {
            "columns" : cols + ( "workflowstatus", cop_as(cop_count(), "total"), ),
            "join": join_inner(workflows, "w", {"workflowid" : "workflowid"} ),
            "where" : {
                "0:modified" : op_lt(trunc_date),
                "1:modified" : op_ge(in_date),
            },
            "groupby" : cols + "workflowstatus",
        };

        if (wfids) {
            sh_live."where" += {"w.workflowid" : op_in(wfids)};
        }

        if (!with_deprecated) {
            sh_live."where" += {"w.deprecated" : op_in(NULL, 0)};
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                # we can just release the lock because the query is read-only
                on_error ds.rollback();
                hash snap = workflow_instance_stats.select(sh_snap);
                hash live = workflow_instance.select(sh_live);

                string key = !system_overview ? "workflowid" : "workflowstatus";
                SnapshotsInfoHelper::mergeContextHashes(\snap, live, key);

                return snap;
            }  catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }
    } # getReportWfs

    #! get report for jobs
    static *hash getReportJobs(date in_date, *softlist jobids) {
        date trunc_date = date(format_date(AbstractSchemaSnapshotManager::DATE_MASK, in_date+1h),
            AbstractSchemaSnapshotManager::DATE_MASK);

        AbstractTable jobs = get_sql_table_system_trans("omq", "jobs");
        AbstractTable job_instance = get_sql_table_system_trans("omq", "job_instance");
        AbstractTable job_instance_stats = get_sql_table_system_trans("omq", "job_instance_stats");
        AbstractDatasource ds = jobs.getDatasource();

        hash sh_snap = {
            "columns" : ("w.name", "w.version", "w.jobid",
                         cop_as("status", "jobstatus"),
                         cop_as(cop_sum("total_count"), "total"),
                        ),
            "join": join_inner(jobs, "w", ("objectid" : "jobid") ),
            "where" : (
                    "modified" : op_ge(trunc_date),
                ),
            "groupby" : ("w.name", "w.version", "w.jobid", "status"),
        };
        if (jobids) {
            sh_snap.where += ("w.jobid" : op_in(jobids));
        }

        hash sh_live = {
                "columns" : ("w.name", "w.version", "w.jobid",
                             "jobstatus",
                             cop_as(cop_count(), "total"),
                            ),
                "join": join_inner(jobs, "w", ("jobid" : "jobid") ),
                "where" : (
                        "0:modified" : op_lt(trunc_date),
                        "1:modified" : op_ge(in_date),
                    ),
                "groupby" : ("w.name", "w.version", "w.jobid", "jobstatus"),
        };
        if (jobids) {
            sh_live.where += ("w.jobid" : op_in(jobids));
        }

        QorusRestartableTransaction trans();
        while (True) {
            try {
                # we can just release the lock because the query is read-only
                on_error ds.rollback();
                hash snap = job_instance_stats.select(sh_snap);
                hash live = job_instance.select(sh_live);

                SnapshotsInfoHelper::mergeContextHashes(\snap, live, "jobid");

                return snap;
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            trans.reset();
            break;
        }
    } # getReportJobs

    static mergeContextHashes(reference<hash> snap, hash<auto> live, string pk_key) {
        hash tmp = hash();
        context (live) {
            tmp{%%{pk_key}} = %%;
        }

        # merge existing keys
        context(snap) {
            auto key = %%{pk_key};
            if (tmp.hasKey(key)) {
                snap.total[cx_pos()] += tmp{key}.total;
                delete tmp{key};
            }
        }

        # append remaining values
        HashIterator it(tmp);
        while (it.next()) {
            foreach string i in (keys snap) {
                push snap{i}, it.getValue(){i};
            }
        }
    }
} # class SnapshotsInfoHelper
} # namespace OMQ
