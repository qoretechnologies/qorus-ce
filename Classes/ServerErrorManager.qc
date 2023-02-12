# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Integration Engine
#
# server global workflow error definition cache manager class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args

public namespace OMQ;

public class OMQ::ServerErrorManager inherits ErrorManager {
    constructor(SQLInterface sqlif, *code log) : ErrorManager(sqlif, log) {
        if (!Qorus.options.get("auto-error-update"))
            auto = False;
    }

    *binary getErrorExtern(softstring wfid, string err) {
        *ErrorDef e = getError(wfid, err);
        return e ? e.serialize() : NOTHING;
    }

    *hash search(*string user, list l) {
        hash h;

        rwl.readLock();
        on_exit rwl.readUnlock();

        foreach string err in (l) {
            if (geh{err})
                h{err}.global = geh{err}.getGlobalInfo(False);
            foreach string wfid in (weh.keyIterator()) {
                if (weh{wfid}{err})
                    h{err}.workflow{wfid} = weh{wfid}{err}.getWorkflowInfo(False);
            }
        }

        return h;
    }

    list searchList(*string user, list l) {
        list rl = ();

        rwl.readLock();
        on_exit rwl.readUnlock();

        foreach string err in (l) {
            if (geh{err})
                rl += geh{err}.getGlobalInfo();
            foreach string wfid in (weh.keyIterator()) {
                if (weh{wfid}{err})
                    rl += weh{wfid}{err}.getWorkflowInfo() + ErrorManager::getWorkflowInfo(wfid);
            }
        }

        return rl;
    }

    list getAllErrorsList(*string user, *string name) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        list l = ();
        map l += $1.getGlobalInfo(), geh.iterator(), (!name || name == $1.error);

        foreach string wfid in (weh.keyIterator()) {
            map l += ($1.getWorkflowInfo() + ErrorManager::getWorkflowInfo(wfid)), weh{wfid}.iterator(), (!name || name == $1.error);
        }

        return l;
    }

    *hash getAllErrors(*string user) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        hash eh;
        map eh.$1 = geh.$1.getGlobalInfo(False), geh.keyIterator();

        hash lweh;
        foreach string wfid in (weh.keyIterator()) {
            map lweh{wfid}.$1 = weh{wfid}.$1.getWorkflowInfo(False), weh{wfid}.keyIterator();
        }

        return (
                "global": eh,
                "workflow": lweh,
               );
    }

    list getAllWorkflowErrorsList(*string user, *softlist l) {
        list rl = ();

        # make a lookup hash of any error list
        *hash lh = map {$1: True}, l;

        rwl.readLock();
        on_exit rwl.readUnlock();

        foreach string wfid in (weh.keyIterator()) {
            if (l)
                map rl += $1.value.getWorkflowInfo() + ErrorManager::getWorkflowInfo(wfid), weh{wfid}.pairIterator(), lh{$1.key};
            else
                map rl += $1.getWorkflowInfo() + ErrorManager::getWorkflowInfo(wfid), weh{wfid}.iterator();
        }

        return rl;
    }

    int deleteError(*string user, string err) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (!geh{err})
            return 0;

        # start with a count of 1 for the global error
        int rc = 1;
        foreach string wfid in (weh.keyIterator()) {
            if (!weh{wfid}{err})
                continue;

            remove weh{wfid}{err};
            ++rc;
        }

        remove geh{err};
        sqlif.deleteError(err);

        return rc;
    }
}
