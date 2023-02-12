# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus workflow entry cache class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

public namespace OMQ;

class OMQ::WFEntryCache {
    public {
        const QuickInfo = ("workflowid", "parent_info", "priority", "status");
    }

    private {
        # RWLock
        RWLock rwl();

        # WFEntry objects currently cached
        hash<string, WFEntry> h;

        # compressed WFEntry objects
        hash<auto> ch;

        # looking for the best tradeoff between speed and compression
        const GZIP_COMPRESSION = 1;
    }

    assign(WFEntry wfe) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        h.(wfe.workflow_instanceid) = wfe;
    }

    *hash getParentWorkflowPriority(softstring wfiid) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        if (h{wfiid}) {
            hash rvh = h{wfiid}.("workflowid", "parent_info", "priority");
            # do not return any information if data has not been cached for this workflow order instance
            return rvh.priority ? rvh : NOTHING;
        }

        if (ch{wfiid})
            return ch{wfiid}.info.("workflowid", "parent_info", "priority");
    }

    *string getStatus(softstring wfiid) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        if (h{wfiid})
            return h{wfiid}.status;

        if (ch{wfiid})
            return ch{wfiid}.info.status;
    }

    *hash<auto> getHash(softstring wfiid) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        if (h{wfiid}) {
            # issue #3137: do not return partially-cached workflow order info
            return h{wfiid}.status ? h{wfiid}.getHash() : NOTHING;
        }

        if (ch{wfiid}) {
            return hash(getIntern(wfiid));
        }
    }

    *hash<auto> getDebugHash(softstring wfiid) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        if (h{wfiid}) {
            return h{wfiid}.getDebugHash();
        }

        if (ch{wfiid}) {
            return hash(getIntern(wfiid));
        }
    }

    store(softstring wfiid) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        #hash<auto> info = h{wfiid}.serializeCustom();
        Workflow wf = h{wfiid}.wf;
        hash<auto> quick_info = h{wfiid}.getInfo(QuickInfo);
        binary info;
        try {
            info = h{wfiid}.serialize();
            ch{wfiid} = {
                "info": quick_info,
                "data": gzip(info, GZIP_COMPRESSION),
            };
            delete h{wfiid};
            #log(LoggerLevel::DEBUG, "compressed wfiid %d %d bytes", wfiid, ch{wfiid}.data.size());
        } catch (hash<ExceptionInfo> ex) {
            # try to compress without tempdata, which could have objects in it, in
            # which case it could not be serialized
            *hash<auto> tdata;
            info = h{wfiid}.serializeWithoutTempData(\tdata);
            #*hash tdata = remove info.tdata;
            try {
                ch{wfiid} = {
                    "info": quick_info,
                    "tdata": tdata,
                    "data": gzip(info, GZIP_COMPRESSION),
                };
                delete h{wfiid};
                #log(LoggerLevel::DEBUG, "compressed wfiid %d %d bytes w/o tdata", wfiid, ch{wfiid}.data.size());
            } catch (hash<ExceptionInfo> ex1) {
                wf.logDebug("WARNING: can't compress wfiid %d: %s: %s: workflow order data will remain in the cache uncompressed", wfiid, ex1.err, ex1.desc);
            }
        }
    }

    private restoreIntern(softstring wfiid) {
        # move to uncompressed map
        WFEntry wfe = getIntern(wfiid);
        if (!h{wfiid}) {
            h{wfiid} = wfe;
            delete ch{wfiid};
        }
    }

    private WFEntry getIntern(softstring wfiid) {
        # first we make an optimistic attempt to get a reference to the wf without grabbing any locks (fails in a wf reset for example)
        *Workflow wf = Qorus.control.tryGetWorkflow(ch{wfiid}.info.workflowid);
        if (!wf) {
            {
                # unlock the lock
                bool rd = rwl.readLockOwner();
                if (rd) rwl.readUnlock(); else rwl.writeUnlock();
                # reacquire the lock on exit
                on_exit if (rd) rwl.readLock(); else rwl.writeLock();

                # get the wf without locks held
                wf = Qorus.control.getWorkflow(ch{wfiid}.info.workflowid);
            }
            # check cache again after unlocking and relocking
            if (h{wfiid}) {
                # issue #3137: if we know that the order was in the compressed cached before, then
                # we must have complete data
                QDBG_ASSERT(h{wfiid}.status);
                return h{wfiid};
            }
        }

        #hash<auto> h = Serializable::deserializeToData(gunzip_to_binary(ch{wfiid}.data));
        #QDBG_LOG("DESERIALIZE: %N", h);
        #WFEntry wfe = Serializable::deserialize(h);

        WFEntry wfe = Serializable::deserialize(gunzip_to_binary(ch{wfiid}.data));
        wfe.wf = wf;
        if (ch{wfiid}.tdata) {
            wfe.setTemporaryData(ch{wfiid}.tdata);
        }
        return wfe;
    }

    *WFEntry get(softstring wfiid) {
        {
            rwl.readLock();
            on_exit rwl.readUnlock();

            if (h{wfiid})
                return h{wfiid};
        }

        {
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            if (ch{wfiid})
                restoreIntern(wfiid);

            if (h{wfiid})
                return h{wfiid};
        }

        if (tld.wfe && tld.wfe.workflow_instanceid == wfiid)
            return tld.wfe;
    }

    list getFlushAndDelete(list l) {
        list fl = ();

        {
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            foreach softstring wfiid in (l) {
                if (ch{wfiid})
                    restoreIntern(wfiid);
                else if (!h{wfiid})
                    continue;

                fl += remove h{wfiid};
            }
        }

        return fl;
    }

    static flushAndDelete(list l) {
        ensure_create_tld();
        ThreadLocalData tld_save();
        tld_save.tldCopy(tld);
        on_exit tld.tldCopy(tld_save);

        # feature 1017: high-performance workflow cache purge
        list fl;
        foreach WFEntry wfe in (l) {
            *hash info = wfe.getFlushInfo();
            if (info)
                fl += info;
        }

        # flush changes to disk
        if (fl)
            sqlif.bulkFlushWorkflowStatus(fl);

        # raise "workflow data released" events and run detach functions
        map $1.flushDetach(), l;

        # delete all WFEntry objects
        foreach WFEntry wfe in (l)
            delete wfe;
    }

    # called with a final status after the wf status has been flushed
    del(softstring wfiid) {
        #QDBG_LOG("deleting %y: %N", wfiid, get_stack());
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        delete h{wfiid};
    }

    WFEntry memberGate(string wfiid) {
%ifdef QorusDebugInternals
        *WFEntry rv = get(wfiid);
        if (!rv) {
            qlog(LoggerLevel::FATAL, "DEBUG: %N", get_stack());
            throw "WORKFLOW-CACHE-ERROR", sprintf("attempt to access workflow_instanceid %d which is not cached", wfiid);
        }
        return rv;
%else
        return get(wfiid);
%endif
    }

    # returns list of all cached workflow order instances for the given workflowid
    list getCachedIds(softstring wfid) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        # issue #2063: only add real elements to the return value, not NOTHING
        list l = (map $1, keys h, h.$1.workflowid == wfid) ?? ();
        l += (map $1, keys ch, ch.$1.info.workflowid == wfid) ?? ();

        return l;
    }
}

