# -*- mode: qore; indent-tabs-mode: nil -*-
# @file DatasourceConnection.qc defines the datasource connection class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

/** DB connection URLs are stored in this form:
    \c db://&lt;connection string&gt;
    Where the connection string is the regular Datasource/DatasourcePool connection string

    https://bugs.qoretechnologies.com/projects/qorus/wiki/User_Connections
 */
public class OMQ::DatasourceConnection inherits AbstractConnectionWithInfo {
    public {
        Datasource shared;
%ifdef QorusServer
        *QdspClient pool;
        # shared lock
        Mutex sm();
        # pool lock
        Mutex pm();
        # qdsp process object hash
        *hash<ClusterProcInfo> qdspc;
        # if the datasource is in coordinated mode or not
        bool coord_mode = Qorus.options.get("default-datasource-coordinated");
%endif
        *softint loggerid;

        # datasource hash args with Qorus system args removed
        hash<auto> ds_urlh;

        #! Connection entry info
        const ConnectionScheme = <ConnectionSchemeInfo>{
            "cls": Class::forName("DatasourceConnection"),
        };

        # Qorus system options to be removed from real datasource connections
        const QorusDsOptions = (
            # for qdsp coordinated mode
            "coord-mode",
        );
    }

    constructor(string name, string desc, string url, hash<auto> attributes = {}, hash<auto> options = {})
        : AbstractConnectionWithInfo(name, desc, url, attributes, options - "loggerid") {
        if (options.loggerid) {
            self.loggerid = remove options.loggerid;
        }
        # we need real empty hash if there is not any for further processing
        if (!opts) {
            opts = {};
        }

        # move all potentially parsed options into dedicated self.opts hash
        if (urlh.hasKey("options")) {
            opts += urlh.options;
            delete urlh.options;
        }

        # override the system props
        if (self.name == "omq") {
            # check and set pool params for system pool
            int sys_min = getQorusOption("system-pool-minimum") ?? 1;
            if (!opts.min) {
                opts.min = sys_min;
            }

            int sys_max = getQorusOption("system-pool-maximum") ?? 3;
            if (!opts.max) {
                opts.max = sys_max;
            }

            if ((opts.min && opts.min != sys_min)
                || (opts.max && opts.max != sys_max)) {
                qlog(LoggerLevel::INFO, "WARNING: system options system-pool-minimum: %d and system-pool-maximum: %d do "
                    "not agree with the pool options set in 'systemdb' option; using min: %d, max: %d from systemdb "
                    "configuration",
                    sys_min,
                    sys_max,
                    opts.min,
                    opts.max);
            }
        }

        # only accept min and max if both are set
        # issue 1875: make sure and delete options instead of setting to 0
        if (!exists opts.min || !exists opts.max) {
            opts -= ("min", "max");
        } else {
            # esnure it's always integer - to make safe comparations
            opts.min = int(opts.min);
            opts.max = int(opts.max);

            # ensure that min >= 0 and max >= min and max > 0
            if (opts.min < 0)
                throw "DATASOURCE-CONNECTION-ERROR", sprintf("invalid option 'min' = %d", opts.min);
            if (opts.max < opts.min)
                throw "DATASOURCE-CONNECTION-ERROR", sprintf("invalid option 'max' %d < 'min' %d", opts.max, opts.min);
            if (opts.max < 1)
                throw "DATASOURCE-CONNECTION-ERROR", sprintf("invalid option 'max' = %d", opts.max);
        }

        # AbstractConnection::getInfo() uses orig_opts as a return value
        # in {"opts": orig_opts}. So here we are simulating pre-process
        # of options for datasources. Real options are orig_opts.
        orig_opts = opts;

        ds_urlh = urlh;
        if (*hash<auto> ds_options = opts - QorusDsOptions) {
            ds_urlh.options = ds_options;
        }

%ifdef QorusServer
        if (opts.hasKey("coord-mode")) {
            coord_mode = parse_boolean(opts{"coord-mode"});
        }
%endif

        children_can_support_records = True;
    }

    hash<auto> takeResetConfig() {
        return {
%ifdef QorusServer
            "pool": remove pool,
            "qdspc": remove qdspc,
%endif
        };
    }

%ifdef QorusServer
    processAborted(bool restarted) {
        QDBG_LOG("DatasourceConnection::processAborted() %y: restarted: %y", name, restarted);
        if (!restarted) {
            pm.lock();
            on_exit pm.unlock();

            remove pool;
            remove qdspc;
        } else {
            subscribeToLogIfNeeded();
        }
    }
%endif

    #! returns a DbDataProvider::DbDataProvider "DbDataProvider" object for this connection
    /** @return a DbDataProvider::DbDataProvider "DbDataProvider" object for this connection; in the client library,
        a dedicated @ref Qore::SQL::Datasource "Datasource" object is returned; in the server, a
        @ref Qore::SQL::DatasourcePool "DatasourcePool" object is returned.

        @see @ref hasDataProvider()

        @since Qorus 4.1
    */
    AbstractDataProvider getDataProvider() {
%ifdef QorusServer
        return new DbDataProvider(getPool());
%else
        DataProvider::registerKnownFactories();
        return create_object("DbDataProvider", getImpl());
%endif
    }

    #! returns @ref True as this connection returns a data provider with the @ref getDataProvider() method
    /** @return @ref True as this connection returns a data provider with the @ref getDataProvider() method

        @see @ref getDataProvider()

        @since Qorus 4.1
    */
    bool hasDataProvider() {
        return True;
    }

    private hash<auto> parseUrl(string url) {
        return DatasourceConnection::parseDbUrl(url);
    }

    static hash<auto> parseDbUrl(string url) {
        url = regex_subst(url, "^db:\/\/", "");
        return parse_datasource(url);
    }

    private string getSafeUrl(hash<auto> urlh) {
        return "db://" + get_ds_desc(urlh + {"options": opts});
    }

    hash<auto> validateOptions(hash<auto> options) {
        return options;
    }

    # This is a hack for QorusClientCore where this class
    # has to be included as well
    private:internal auto getQorusOption(string option_name) {
%ifdef QorusServer
        return Qorus.options.get(option_name);
%endif
    }

    string getType() {
        return "datasource";
    }

%ifdef QorusServer
    destructor() {
        stop();
    }

    stop() {
        if (qdspc) {
            # issue #2564: delete clients before stopping process
            delete pool;
            Qorus.stopProcess(qdspc);
        }
    }

    static poolWarning(string desc, int time, int to, string dsn) {
        # raise a transient alert when the connection pool time is exceeded
        string err = sprintf("datasource %y pool connection waited for %y, exceeding the warning timeout limit of %y, consider raising the maximum connection value from %d to a higher number to avoid congestion in the pool", dsn, microseconds(time), milliseconds(to), dsn == "omq" ? omqp.getConfigHash().options.max : Qorus.dsmanager.getConfigHash(dsn).options.max);
        ActionReason r(tld.cx, err, True);
        Qorus.alerts.raiseTransientAlert(r, "DATASOURCE", dsn, "DATASOURCEPOOL-CONTENTION-ERROR", ("name": dsn));
    }

    hash<auto> getConfigInfo() {
        return AbstractConnection::getInfo({"with_passwords": True});
    }

    hash<auto> getExtendedInfo(*hash<auto> opts) {
        hash<auto> rv = getInfo(opts) + {
            "coord-mode": coord_mode,
            "safe_url": self.safe_url
        };

        # remove password if necessary
        if (!opts.with_passwords) {
            remove rv.url_hash.pass;
        }

        # add in pool status
        {
            pm.lock();
            on_exit pm.unlock();
            QdspClient p;
            if (pool)
                p = pool;
            else if (name == "omq")
                p = omqp;
            if (p) {
                try {
                    rv."shared-pool" = p.toString();
                    *hash<auto> h = p.getUsageInfo();
                    if (h.timeout) {
                        rv."warning-timeout" = opts.rtime ? milliseconds(h.timeout) : h.timeout;
                    }
                    rv += {
                        "error-timeout": opts.rtime ? milliseconds(p.getErrorTimeout()) : p.getErrorTimeout(),
                        "pool-wait-max": opts.rtime ? microseconds(h.wait_max) : h.wait_max,
                        "pool-reqs": h.stats_reqs,
                        "pool-hits": h.stats_hits,
                        "pool-miss": h.stats_reqs - h.stats_hits,
                        "pool-hit-pct": !h.stats_reqs ? 0n : h.stats_hits.toNumber() / h.stats_reqs.toNumber() * 100n,
                    };
                } catch (hash<ExceptionInfo> ex) {
                    if (ex.err != "DATASOURCEPOOL-PROCESS-ERROR" && ex.err != "CLIENT-DEAD") {
                        rethrow;
                    }
                    # pool and process will be removed with process abort msg from qorus-master
                }
            }
        }

        return rv + {
            "alerts": Qorus.alerts.getAlerts(AlertTypeDatasource, name),
        };
    }

    Datasource getShared(*bool for_ping) {
        bool nd = False;

        Datasource rv;

        {
            sm.lock();
            on_exit sm.unlock();

            if (!shared) {
                Datasource ds = new Datasource(ds_urlh, MonitorSingleton::ds_queue, {"mon": AlertTypeDatasource, "name": name});
                # set autocommit to true
                ds.setAutoCommit(True);
                ds.open();
                shared = ds;
                nd = True;
            }

            rv = shared;
        }

        if (!nd && !for_ping)
            DatasourceConnection::doPingDs(rv);

        return rv;
    }

    QdspClient getPool() {
        bool nd = False;

        *QdspClient rv = pool;

        if (!rv) {
            # check system properties for overriding min/max params
            *hash<auto> dsp = getQorusOption("datasource");

            pm.lock();
            on_exit pm.unlock();

            if (!pool) {
                hash<auto> ds_conn_hash = getConnectionHash(dsp);
                # start cluster process
                qdspc = Qorus.startDatasourcePoolProcess(name, ds_conn_hash).info;
                pool = new QdspClient(Qorus, name, {
                    "set_context": ds_conn_hash.type == "oracle" && Qorus.options.get("oracle-datasource-pool"),
                });
                QDBG_LOG("DatasourceConnection::getPool() created new process: %y, client aborted: %y", qdspc, pool.isAborted());

                nd = True;
            }

            rv = pool;
        }

        if (!nd) {
            DatasourceConnection::doPingDs(rv);
        }

        return rv;
    }

    hash<auto> getConnectionHash(*hash<auto> dsp) {
        string minkey = sprintf("%s-min", name);
        string maxkey = sprintf("%s-max", name);

        hash<auto> ph;

        # set/override min/max params only if both are present
        if (dsp{minkey} && dsp{maxkey}) {
            ph.min = dsp{minkey};
            ph.max = dsp{maxkey};
        }

        # otherwise try to set from default values in the datasource system property domain
        if (!ph.min || !ph.max) {
            ph.min = dsp.poolMinimum;
            ph.max = dsp.poolMaximum;
        }

        # set/override parameters only if both are present
        if (!ph.min || !ph.max) {
            delete ph;
        }

        hash<auto> h = urlh;
        if (opts) {
            h.options = opts;
        }
        if (ph) {
            h.options += ph;
        }
        return h;
    }

    Datasource getDedicated() {
        Datasource ds(ds_urlh, MonitorSingleton::ds_queue, {"mon": AlertTypeDatasource, "name": name});
        ds.open();
        return ds;
    }

    reset() {
        {
            sm.lock();
            on_exit sm.unlock();

            remove shared;
        }

        {
            pm.lock();
            on_exit pm.unlock();

            # issue #2707: update qdsp processes immediately with new connection parameters
            if (pool && qdspc) {
                hash<auto> conn_hash = {
                    "connstr": get_ds_desc(getConnectionHash(getQorusOption("datasource")), DD_WITH_PASSWORD),
                };
                # first we update the master process to ensure that if the qdsp process is restarted, it will be
                # restarted with the new parameters
                Qorus.updateProcessInfo(qdspc, conn_hash);
                # then we update the qdsp process with the new connection info
                pool.reset(conn_hash);
            }
        }
    }

    subscribeToLogIfNeeded() {
        if (Qorus.eventLog.isQdspLogRequested(name)) {
            subscribeToLog();
        }
    }

    subscribeToLog() {
        *QdspClient qdsp;
        {
            pm.lock();
            on_exit pm.unlock();

            qdsp = pool;
        }
        if (qdsp) {
            qdsp.sendCheckResponse(CPC_CORE_LOG_SUBSCRIBE, NOTHING, CPC_OK);
        }
    }

    unsubscribeFromLog() {
        *QdspClient qdsp;
        {
            pm.lock();
            on_exit pm.unlock();

            qdsp = pool;
        }
        if (qdsp) {
            qdsp.sendCheckResponse(CPC_CORE_LOG_UNSUBSCRIBE, NOTHING, CPC_OK);
        }
    }

    updateLogger(*hash<auto> logger) {
        *QdspClient qdsp;
        {
            pm.lock();
            on_exit pm.unlock();

            qdsp = pool;
            loggerid = logger.loggerid;
        }
        if (qdsp) {
            if (logger.params) {
                hash<LogFilenameSubs> subs = <LogFilenameSubs>{
                    "name": name,
                };
                logger.params = substituteLogFilename(logger.params, LoggerController::getLoggerSubs("qdsp", subs));
            }

            #QDBG_LOG("uL %y: p: %y", name, logger.params);
            qdsp.sendCheckResponse(CPC_UPDATE_LOGGER, logger.params, CPC_OK);
        }
    }

    private hash<PingInfo> pingIntern(hash<PingInfo> rv) {
        date start = now_us();
        doPing();
        return rv += {
            "ok": True,
            "time": now_us() - start,
            "info": "OK",
        };
    }

    private doPing(bool connect = True) {
        on_exit
            last_check = now_us();

        try {
            # issue #2196: do not issue a ping on the pool with the lock held
            QdspClient pool_ref;
            {
                pm.lock();
                on_exit pm.unlock();

                if (pool) {
                    pool_ref = pool;
                }
            }

            AbstractQorusDistributedProcess::pingDs(pool_ref ?? getShared(True));

            up = True;
            status = "OK";
        } catch (hash<ExceptionInfo> ex) {
            status = sprintf("%s: %s", ex.err, ex.desc);
            up = False;
            # issue #3030 - a race condition in early stages of qorus startup.
            # Qorus.dsmanager can be uninitialized in this phase. But
            # it will be auto corrected on the next ping
            if (Qorus.dsmanager) {
                Qorus.dsmanager.checkErrorNeedsReset(name, ex);
            }
            rethrow;
        }
    }

    static private doPingDs(QdspClient ds) {
        ds.ping();
    }

    static private doPingDs(AbstractDatasource ds) {
        AbstractQorusDistributedProcess::pingDs(ds);
    }
%endif

    private Datasource getImpl(bool connect = True, *hash rtopts) {
        Datasource ds(ds_urlh);
        if (connect) {
            ds.open();
        }
        return ds;
    }

    #! Returns the ConnectionSchemeInfo hash for this object
    private hash<ConnectionSchemeInfo> getConnectionSchemeInfoImpl() {
        return ConnectionScheme;
    }
}
