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

date sub get_minute() {
    date d = now();
    return d - d.seconds();
}

hashdecl DispositionInfo {
    int C = 0;
    int A = 0;
    int M = 0;
};

hashdecl OrderStatInfo {
    # timestamp
    date timestamp = now_us();
    # disposition -> count
    hash<DispositionInfo> event_summary_hash();
    # maps wfid -> list of durations of orders
    hash<string, list<float>> duration;
}

hashdecl OrderSummaryDetailInfo {
    # list of events
    list<hash<OrderStatInfo>> l();
    # summary of events; disposition -> count
    hash<DispositionInfo> event_summary_hash();
}

hashdecl OrderSummaryReportInfo {
    # summary of events; disposition -> count
    hash<DispositionInfo> event_summary_hash();
    # summary of SLA statuses; "0"|"1" -> count
    hash<string, int> slah = {
        "0": 0,
        "1": 0,
    };
}

class OMQ::WorkflowOrderStats {
    private {
        # hash of summary hashes; tag -> hour grouping -> summary info
        hash<string, hash<string, hash<OrderSummaryDetailInfo>>> summary_hash;

        # last output of hash of summary hashes; tag -> hour grouping -> summary info (without event lists)
        hash<string, hash<string, hash<OrderSummaryReportInfo>>> last_summary_hash;

        # mutex
        Mutex l();

        # stop condition
        Condition cond();

        # stop flag
        bool stop;

        # background thread counter
        Counter tc();

        # order expiry cache
        OrderExpiryCache order_expiry_cache();

        # summary points in # of hours
        const SummaryHours = (1, 4, 24);

        # first summary value
        const First = SummaryHours[0].toString();

        # summary update interval
        const UpdateInterval = 1s;

        # order expiry buffer period
        /** to cover the race condition when an order's disposition is reported right after
            its SLA threshold due to serialization / transmission delays
        */
        const OrderExpiryBuffer = 10s;
    }

    constructor() {
        setupTag("global");
    }

    destructor() {
        shutdown();
    }

    start() {
        tc.inc();
        on_error tc.dec();
        background eventThread();
        background populateData();
    }

    synchronized shutdown() {
        if (!stop) {
            stop = True;

            l.lock();
            on_exit l.unlock();
            cond.signal();
        }
        tc.waitForZero();
    }

    *hash getSummary() {
        return {
            "expiry_cache": order_expiry_cache.getSummary(),
        };
    }

    *hash getDetails() {
        return {
            "expiry_cache": order_expiry_cache.getDetails(),
        };
    }

    postCreated(softint wfid, softint wfiid, date created = now()) {
        order_expiry_cache.queueOrder(wfid, wfiid, created.getEpochSeconds());
    }

    post(softint wfid, softint wfiid, string disposition, softfloat duration) {
        # get the event timestamp
        date ts = get_minute();

        softstring tag = wfid;

        l.lock();
        on_exit l.unlock();

        postIntern(wfid, wfiid, disposition, duration, ts);
    }

    /**
        FIXME: if the SLA period changes, then all workflow info for that workflow needs to be requeued
            in this object (https://bugs.qoretechnologies.com/issues/2347)
    */
    requeue(softint wfid, int sla) {
        # to be implemented in issue #2347
    }

    /** this method can handle 3 scenarios:
        1) the order event has a final status within the SLA period (+ buffer / 2)
            in this case the disposition & SLA info is updated
            the workflow instance ID is removed from the expiry cache so that the SLA info is not reported twice
        2) the order does not have a final status yet, but the SLA period has expired
            in this case "disposition" is an empty string and wfiid is ignored and does not need to be set (can be 0)
            also this should only be reported after the SLA has expired and the buffer period has been exceeded
            in this case "count" is passed and is > 0
        3) the order has a final disposition but is >= the SLA period (+ buffer / 2)
            in this case only the disposition is reported and the SLA violation is left in the expiry cache
            to be reported separately - this ensures that the SLA info is not reported twice

        NOTE: durations are tracked here only in relation to the workflow's SLA expiry period; if the
            SLA threshold changes, then all SLA info for that workflow must be recalculated
    */
    private postIntern(softstring wfid, softint wfiid, string disposition, float duration, date ts,
            int group_offset = 0, *int count) {
        postTagIntern("global", wfid, wfiid, disposition, duration, ts, group_offset, count);
        if (!exists summary_hash{wfid}) {
            setupTag(wfid);
        }
        postTagIntern(wfid, wfid, wfiid, disposition, duration, ts, group_offset, count);
    }

    postTagIntern(softstring tag, softstring wfid, softint wfiid, string disposition, float duration, date ts,
            int group_offset = 0, *int count) {
        # count can never be given with a disposition value
        QDBG_ASSERT(!count || !disposition);

        softstring group = SummaryHours[group_offset];

        # if we are posting a final status, then remove the wfiid from the order expiry cache
        # unless the is order is out of the SLA more than 50% of the buffer time
        if (disposition && wfiid) {
            softint sla = (Qorus.qmm.getWorkflowMapUnlocked(){wfid}.sla_threshold ?? DefaultWorkflowSlaThreshold)
                + (OrderExpiryBuffer / 2);
            if (duration < sla) {
                # case 1)
                # remove the order from the expiry cache (only once with the "global" tag)
                if (tag == "global") {
                    order_expiry_cache.removeOrder(wfid, wfiid);
                }
            } else {
                # case 3)
                # otherwise we let the order expiry cache handle the SLA entry and just post the disposition
                duration = -1;
            }
        }

        # coalesce with existing trailing/latest event if the timestamps match
        if (summary_hash{tag}{group}.l && summary_hash{tag}{group}.l.last().timestamp == ts) {
            reference rec = \summary_hash{tag}{group}.l[summary_hash{tag}{group}.l.size() - 1];
            if (disposition) {
                # cases 1) and 3)
                ++rec.event_summary_hash{disposition};
            }
            if (duration >= 0) {
                # cases 1) and 2)
                if (!rec.duration{wfid}) {
                    rec.duration{wfid} = ();
                }
                if (count) {
                    # case 2)
                    map rec.duration{wfid} += duration, xrange(count);
                } else {
                    # case 1)
                    rec.duration{wfid} += duration;
                }
            }
            #QDBG_LOG("coalescing event: go: %y tag: %y group: %y wfid: %y: %y", group_offset, tag, group, wfid, rec);
        } else {
            hash<OrderStatInfo> osi({
                "timestamp": ts,
            });
            if (disposition) {
                # cases 1) and 3)
                osi.event_summary_hash = new hash<DispositionInfo>({disposition: 1});
            }
            if (duration >= 0) {
                # cases 1) and 2)
                if (count) {
                    # case 2)
                    osi.duration = {wfid: cast<list<float>>(map duration, xrange(count))};
                } else {
                    # case 1)
                    osi.duration = {wfid: (duration,)};
                }
            }

            #QDBG_LOG("adding event: tag: %y group: %y wfid: %y: %y", tag, group, wfid, osi);

            # otherwise add to the end of the list
            summary_hash{tag}{group}.l += osi;
        }

        if (disposition) {
            # update summary statistics for this and all following groups
            map ++summary_hash{tag}{$1}.event_summary_hash{disposition}, SummaryHours[group_offset ..];
        }
    }

    *list<hash<OrderSummaryOutputInfo>> getCurrentEvents(*softint wfid) {
        softstring tag = wfid ?? "global";

        *hash<string, hash<OrderSummaryReportInfo>> this_summary_hash;

        {
            l.lock();
            on_exit l.unlock();

            this_summary_hash = last_summary_hash{tag};
        }

        if (!this_summary_hash) {
            return;
        }

        return WorkflowOrderStats::getOutputEvents(
            cast<hash<string, hash<OrderSummaryReportInfo>>>(this_summary_hash)
        );
    }

    private eventThread() {
        on_exit tc.dec();

        while (!stop) {
            # get current workflow SLA values; wfid -> sla threshold
            *hash<auto> wf_sla_map = map {$1.key: $1.value.sla_threshold},
                Qorus.qmm.getWorkflowMapUnlocked().pairIterator();

            {
                l.lock();
                on_exit l.unlock();

                # post expired orders in order expiry cache
                {
                    # get the event timestamp
                    date ts = get_minute();

                    foreach hash<auto> eh in (order_expiry_cache.getEvents(wf_sla_map,
                        OrderExpiryBuffer).pairIterator()) {
                        float duration = (wf_sla_map{eh.key} ?? DefaultWorkflowSlaThreshold)
                            + DefaultWorkflowSlaThreshold;
                        postIntern(eh.key, 0, "", duration, ts, NOTHING, eh.value);
                    }
                }

                #QDBG_LOG("sh: %N", sh);

                foreach string tag in (keys summary_hash) {
                    # current events summary info; hour grouping -> summary
                    hash<string, hash<OrderSummaryReportInfo>> this_summary_hash();

                    foreach int d in (SummaryHours) {
                        string label = d.toString();
                        date cutoff = now_us() - hours(d);

                        # get elements to remove
                        int i = 0;
                        while (i < summary_hash{tag}{label}.l.size()) {
                            if (summary_hash{tag}{label}.l[i].timestamp > cutoff) {
                                break;
                            }
                            ++i;
                        }

                        if (i) {
                            # remove expired events
                            list<hash<OrderStatInfo>> l = remove summary_hash{tag}{label}.l[0 .. --i];

                            # add to next event list, if any
                            if ($# < (SummaryHours.size() - 1)) {
                                softstring nl = SummaryHours[$# + 1];
                                summary_hash{tag}{nl}.l += l;
                            }

                            # remove from current summary figures
                            foreach hash<OrderStatInfo> h in (l) {
                                map summary_hash{tag}{label}.event_summary_hash{$1.key} -= $1.value,
                                    h.event_summary_hash.pairIterator();
                                # do not add to next summary figures, because the information is already there
                            }
                        }
                    }

                    # get current event summary info
                    string lastkey;
                    foreach hash<auto> h in (summary_hash{tag}.pairIterator()) {
                        # h.key: hour, h.value: hash<OrderSummaryDetailInfo> for that hour grouping
                        # copy SLA stats from previous band
                        if (lastkey && this_summary_hash{lastkey}.slah) {
                            this_summary_hash{h.key} =
                                new hash<OrderSummaryReportInfo>({"slah": this_summary_hash{lastkey}.slah});
                        } else {
                            this_summary_hash{h.key} = new hash<OrderSummaryReportInfo>();
                        }
                        # set the key for the next band, if any
                        lastkey = h.key;
                        # if there are no events in this band then continue
                        if (!h.value.event_summary_hash) {
                            continue;
                        }
                        # assign summary hash
                        this_summary_hash{h.key}.event_summary_hash = h.value.event_summary_hash;
                        # iterate events
                        foreach hash<OrderStatInfo> osih in (h.value.l) {
                            foreach hash<auto> dh in (osih.duration.pairIterator()) {
                                # check if workflow matches current tag
                                if (tag == "global" || dh.key == tag) {
                                    # increment "in_sla" status appropriately for the event
                                    map ++this_summary_hash{h.key}.slah{($1 <= (wf_sla_map{dh.key}
                                        ?? DefaultWorkflowSlaThreshold)).toString()}, dh.value;
                                }
                            }
                        }
                    }

                    #QDBG_LOG("tag: %y this_summary_hash: %N", tag, this_summary_hash);
                    #QDBG_LOG("match: %y last_summary_hash{%y}: %N", this_summary_hash == last_summary_hash{tag}, tag, last_summary_hash{tag});

                    if (this_summary_hash != last_summary_hash{tag}) {
                        last_summary_hash{tag} = this_summary_hash;
                        emitEvents(tag, this_summary_hash);
                    }
                }
            }
            # interruptible sleep until next event interval
            l.lock();
            on_exit l.unlock();
            cond.wait(l, UpdateInterval);
        }
    }

    # reads in data from the DB for more accurate reporting
    private populateData() {
        # must populate data from oldest to newest
        date now = now_us();
        list<int> reverse_hours = reverse(SummaryHours);
        foreach int d in (reverse_hours) {
            date cutoff = now - hours(d);
            *date lastcutoff;
            int group_offset = 2 - $#;
            if ($# < (SummaryHours.size() - 1)) {
                lastcutoff = now - hours(reverse_hours[$# + 1]);
            }
            QorusRestartableTransaction trans();
            while (True) {
                try {
                    AbstractTable workflow_instance = get_sql_table_system("omq", "workflow_instance");

                    # read in all workflows in the time range
                    hash<auto> summary_hash = {
                        "columns": (
                            "workflowid", "workflow_instanceid", "workflowstatus", "errors",
                            "retries", "started", "completed", "modified",
                        ),
                        "where": {
                            "started": op_ge(cutoff),
                        },
                        "orderby": "started",
                    };
                    if (lastcutoff) {
                        summary_hash."where"."1:started" = op_lt(lastcutoff);
                    }

                    #QDBG_LOG("summary_hash: %N", summary_hash);

                    #QDBG_LOG("historical order data band %d/%d cutoff: %y starting (query params: %y)", $# + 1, SummaryHours.size(), cutoff, summary_hash); date qstart = now_us();
                    # the above purposefully put on the same line so it's only present in debug builds
                    *hash<auto> q = workflow_instance.select(summary_hash);
                    #QDBG_LOG("historical order data band %d/%d cutoff: %y time: %y rows: %d", $# + 1, SummaryHours.size(), cutoff, now_us() - qstart, q.workflowid.lsize());
%ifdef QorusDebugInternals
                    #map QDBG_LOG("hod: %y", $1), q.contextIterator();
%endif

                    l.lock();
                    on_exit l.unlock();

                    context (q) {
                        if (%workflowstatus != OMQ::SQLStatComplete && %workflowstatus != OMQ::SQLStatCanceled) {
                            #QDBG_LOG("queueData() status: %y wfid: %y wfiid: %y started: %y", %workflowstatus, %workflowid, %workflow_instanceid, %started);
                            order_expiry_cache.queueOrder(%workflowid, %workflow_instanceid, %started.getEpochSeconds());
                            continue;
                        }

                        # get completed date
                        date completed = %completed ?? %modified;
                        # get total duration as a floating-point value in seconds
                        float duration = (completed - %started).durationMicroseconds().toFloat() / 1000000.0;

                        # round completed down to the minute
                        completed -= completed.seconds();
                        completed -= microseconds(completed.microseconds());

                        # get complete disposition
                        string disposition = !%errors ? CS_Clean : (%errors == %retries ? CS_RecoveredAuto : CS_RecoveredManual);

                        #QDBG_LOG("populate data: wfid: %y disp: %y dur: %y com: %y g: %y (group: %y)", %workflowid, disposition, duration, completed, group_offset, SummaryHours[group_offset]);
                        postIntern(%workflowid, 0, disposition, duration, completed, group_offset);
                    }

                    #QDBG_LOG("historical order data band %d/%d cutoff: %y inserted %d historical records for this band", $# + 1, SummaryHours.size(), cutoff, q.workflowid.lsize());
                } catch (hash<ExceptionInfo> ex) {
                    if (trans.restartTransaction(ex))
                        continue;
                    # log error and try next band
                    qlog(LoggerLevel::INFO, "fatal error populating historical workflow order event data for band %d/%d (cutoff: %y): %s",
                         $# + 1, SummaryHours.size(), cutoff, get_exception_string(ex));
                }
                trans.reset();
                break;
            }
        }
        #QDBG_LOG("population done: summary_hash: %N", summary_hash);
        #QDBG_LOG("population done: last_summary_hash: %N", last_summary_hash);
    }

    private setupTag(softstring tag) {
        # create summary info for each hour
        map summary_hash{tag}.$1 = new hash<OrderSummaryDetailInfo>(), SummaryHours;

        # create empty last summary hash
        map last_summary_hash{tag}.$1 = new hash<OrderSummaryReportInfo>(), SummaryHours;
    }

    static private emitEvents(string tag, hash<string, hash<OrderSummaryReportInfo>> this_summary_hash) {
        list<hash<OrderSummaryOutputInfo>> l = WorkflowOrderStats::getOutputEvents(this_summary_hash);
        Qorus.events.postOrderStats(tag, l);
    }

    static private list<hash<OrderSummaryOutputInfo>> getOutputEvents(
            hash<string, hash<OrderSummaryReportInfo>> this_summary_hash) {
        list<hash<OrderSummaryOutputInfo>> rv();

        date ts = now_us();

        foreach string d in (keys this_summary_hash) {
            # get total events in band
            float total = (foldl $1 + $2, this_summary_hash{d}.event_summary_hash.iterator()) ?? 0;
            list<hash<OrderStatusOutputInfo>> l = map cast<hash<OrderStatusOutputInfo>>({
                "disposition": $1.key,
                "count": $1.value,
                "pct": total ? (100.0 * ($1.value.toFloat() / total)) : 0.0,
            }), this_summary_hash{d}.event_summary_hash.pairIterator();

            # get total SLA events
            total = (foldl $1 + $2, this_summary_hash{d}.slah.iterator()) ?? 0;
            list<hash<OrderSlaOutputInfo>> sla = map cast<hash<OrderSlaOutputInfo>>({
                "in_sla": $1.key.toBool(),
                "count": $1.value,
                "pct": total ? (100.0 * ($1.value.toFloat() / total)) : 0.0,
            }), this_summary_hash{d}.slah.pairIterator();

            rv += new hash<OrderSummaryOutputInfo>({
                "label": sprintf("%d_hour_band", d),
                "range_start": ts - hours(d),
                "l": l,
                "sla": sla,
            });
        }

        return rv;
    }
}
