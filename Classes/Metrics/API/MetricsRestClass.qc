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
%enable-all-warnings

public namespace Metrics;

/** @REST /api/metrics

    This REST URI path provides qorus metrics
*/
class MetricsRestClass inherits QorusRestClass {
    string name() {
        return "metrics";
    }

    static string parseFromHash(string label, *hash<auto> h) {
        return (foldl $1 + $2, (map sprintf(label, $1.key, $1.value), h.pairIterator())) ?? "";
    }

    static string parseFromDoubleHash(string label, *hash<auto> h) {
        string res = "";
        #QDBG_LOG("parseFromDoubleHash() label: %y h: %y", label, h);
        map res += MetricsRestClass::parseFromHash(sprintf(label, $1.key, ",status=\"%s\"} %s\n"), $1.value),
            h.pairIterator();
        return res;
    }

    static string getCurrentlyDiscEndSys() {
        int ok = 0;
        int down = 0;
        string res;
        foreach hash i in (Qorus.dsmanager.list(True)) {
            i.up ? ok++ : down++;
        }
        res += sprintf("qorus_currently_disconnected_end_systems{status=\"up\"} %d\n", ok);
        res += sprintf("qorus_currently_disconnected_end_systems{status=\"down\"} %d\n", down);
        return res;
    }

    static string getCurrentlyRunningWfInstances() {
        hash h;
        foreach hash i in (Qorus.control.getWorkflowInfoList()) {
            h{i{"workflowid"}}++;
        }

        if (!h) {
            return "";
        }

        HashIterator it(h);
        string res;
        while (it.next()) {
            res += sprintf("qorus_currently_running_worklflow_instances{id=\"%s\"} %s\n", it.getKey(), it.getValue());
        }
        return res;
    }

    static string getDbSizeB() {
        HashIterator it(Qorus.dsmanager.getDbSizeB(True));
        string res;
        while (it.next()) {
            res += sprintf("qorus_db_size_in_bytes{name=\"%s\"} %s\n", it.getKey(), it.getValue());
        }
        return res;
    }

    static string getOrderSLAAndDispositionStats() {
        string result;
        list order_stats = Qorus.orderStats.getCurrentEvents();
        foreach auto order_stat in (order_stats) {
            foreach auto sla in (order_stat.sla) {
                result += sprintf("qorus_order_stats_sla{in_sla=\"%d\",band=%y} %s\n", sla.in_sla, order_stat.label,
                                  sla.count);
            }

            foreach auto disposition in (order_stat.l) {
                result += sprintf("qorus_order_stats_disposition{disposition=%y,band=%y} %s\n",
                                  disposition.disposition, order_stat.label, disposition.count);
            }
        }
        return result;
    }

    /** @REST GET

        @par Description
        Returns qorus metrics

        @par Return Value
        This API returns a list of qorus metrics
        - \c TODO: the todo part
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        # return RestHandler::makeResponse(200, make_yaml({"ok": "none"}, YAML::BlockStyle));
        # return RestHandler::makeResponse(200, make_json("ok"));
        # return RestHandler::makeResponse(200, make_json("ok"));
        return {
            "code": 200,
            "body": getMetrics(),
            "hdr": {
                "Content-Type": "text/plain",
            },
        };
    }

    static string getMetrics() {
        hash<auto> info = UserApi::getSystemInfo();

        string ret = sprintf("qorus_threads %s\n", info.threads);
        ret += sprintf("qorus_cache_size %s\n", info.cache_size);
        ret += sprintf("qorus_alerts{type=\"transient\"} %s\n", info."alert-summary"."transient");
        ret += sprintf("qorus_alerts{type=\"ongoing\"} %s\n", info."alert-summary"."ongoing");

        # cluster info
        hash<auto> cluster = Qorus.getMaster().getInfo(10s);
        foreach hash<auto> i in (cluster.cluster_info.pairIterator()) {
            ret += sprintf("qorus_cluster_info_node_priv{node_name=%y} %s\n", i.key, i.value.node_priv);
            ret += sprintf("qorus_cluster_info_node_ram{node_name=%y} %s\n", i.key, i.value.node_ram);
            ret += sprintf("qorus_cluster_info_node_ram_in_use{node_name=%y} %s\n", i.key, i.value.node_ram_in_use);
            ret += sprintf("qorus_cluster_info_process_count{node_name=%y} %s\n", i.key, i.value.process_count);
            ret += sprintf("qorus_cluster_info_node_load_pct{node_name=%y} %s\n", i.key, i.value.node_load_pct);
        }
        # processes
        foreach hash<auto> i in (cluster.processes.pairIterator()) {
            ret += sprintf("qorus_processes_status{node_name=%y,process_name=%y} %s\n",
                        i.value.node, i.key, i.value.status);
            # do not include line where the metric is missing
            if (i.value.vsz) {
                ret += sprintf("qorus_processes_vsz{node_name=%y,process_name=%y} %s\n",
                               i.value.node, i.key, i.value.vsz);
            }
            if (i.value.rss) {
                ret += sprintf("qorus_processes_rss{node_name=%y,process_name=%y} %s\n",
                               i.value.node, i.key, i.value.rss);
            }
            if (i.value.priv) {
                ret += sprintf("qorus_processes_priv{node_name=%y,process_name=%y} %s\n",
                               i.value.node, i.key, i.value.priv);
            }
        }
        hash<string, int> alerts = Qorus.alerts.getOngoingAlertSummary();
        ret += sprintf("qorus_workflow_total %s\n", Qorus.qmm.getWorkflowIds().lsize());
        ret += sprintf("qorus_workflow_alerts %s\n", alerts.WORKFLOW ?? 0);
        ret += sprintf("qorus_service_total %s\n", Qorus.qmm.getServiceIds().lsize());
        ret += sprintf("qorus_service_alerts %s\n", alerts.SERVICE ?? 0);
        ret += sprintf("qorus_job_total %s\n", Qorus.qmm.getJobIds().lsize());
        ret += sprintf("qorus_job_alerts %s\n", alerts.JOB ?? 0);
        ret += sprintf("qorus_remote_total %s\n", Qorus.remotemonitor.size());
        ret += sprintf("qorus_remote_alerts %s\n", alerts{"REMOTE"} ?? 0);
        ret += sprintf("qorus_user_total %s\n", Qorus.connections.size());
        ret += sprintf("qorus_user_alerts %s\n", alerts{"USER"} ?? 0);
        ret += sprintf("qorus_datasource_total %s\n", Qorus.dsmanager.size());
        ret += sprintf("qorus_datasource_alerts %s\n", alerts{"DATASOURCE"} ?? 0);

        ret += MetricsRestClass::parseFromHash("qorus_actual_workflow_overall_statuses{status=\"%s\"} %s\n",
            Qorus.getWfStatusCache());
        ret += MetricsRestClass::parseFromHash("qorus_actual_job_overall_statuses{status=\"%s\"} %s\n",
            Qorus.getJobStatusCache());

        ret += MetricsRestClass::parseFromDoubleHash("qorus_actual_workflow_instances_statuses{id=\"%s\"%s",
            Qorus.getWfInterfaceStatusCache());
        ret += MetricsRestClass::parseFromDoubleHash("qorus_actual_job_instances_statuses{id=\"%s\"%s",
            Qorus.getJobInterfaceStatusCache());

        ret += MetricsRestClass::getCurrentlyDiscEndSys();
        ret += MetricsRestClass::getCurrentlyRunningWfInstances();
        ret += MetricsRestClass::getDbSizeB();

        ret += MetricsRestClass::getOrderSLAAndDispositionStats();
        #QDBG_LOG("metrics: %s", ret);
        return ret;
    }

} # class MetricsRestClass