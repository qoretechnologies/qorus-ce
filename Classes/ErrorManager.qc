# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus Integration Engine
#
# global workflow error definition cache manager class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

public namespace OMQ;

public class OMQ::ErrorManager {
    public {
        const ValidStatuses = {
            OMQ::StatRetry: True,
            OMQ::StatError: True,
            OMQ::StatCanceled: True,
        };
    }

    private {
        # global error hash (name -> error def)
        hash<string, ErrorDef> geh;

        # workflow-specific error hash (workflowid -> name -> error def)
        hash<string, hash<string, ErrorDef>> weh;

        # sql interface
        SQLInterface sqlif;

        # read-write lock
        RWLock rwl();

        # logging closure / call ref
        *code logc;

        # initialization flag
        bool initflag = False;

        # feature 645: add an option to suppress automatic updating of workflow errors but only allow automatic creation of global errors
        # flag for automatic workflow-specific error creation
        bool auto = True;
    }

    constructor(SQLInterface sqlif, *code log) {
        self.sqlif = sqlif;
        self.logc = log;
    }

    bool getAuto() {
        return auto;
    }

    setAuto(bool auto = True) {
        self.auto = auto;
    }

    int init() {
        hash<auto> h = sqlif.getAllErrorDefs();

        foreach hash<auto> e in (h.global.contextIterator()) {
            geh{e.error} = getError(e, True);
        }
        log("cached %d global error definition%s", geh.size(), geh.size() == 1 ? "" : "s");

        int ec = 0;
        foreach hash<auto> e in (h.workflow.contextIterator()) {
            weh{e.workflowid}{e.error} = getError(e, True);
            ++ec;
        }
        log("cached %d workflow error definition%s in %d workflow%s", ec, ec == 1 ? "" : "s", weh.size(),
            weh.size() == 1 ? "" : "s");

        initflag = True;

        return ec;
    }

    initOnce() {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (initflag) {
            return;
        }

        init();
    }

    hash reload() {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        return reloadIntern();
    }

    # must be called with the write lock held
    private hash reloadIntern() {
        delete geh;
        delete weh;

        int ec = init();

        return {
            "global": geh.size(),
            "workflow": ec,
        };
    }

    private checkError(reference<hash> e, *bool init) {
        if (exists e.retry_flag) {
            # recognize retry_flag for backward compatibility
            if (exists e.status) {
                throw "ERROR-UPDATE-ERROR",
                    sprintf("both 'retry_flag' and 'status' keys have "
                            "been filled in error hash %y", e);
            }
            e.status = e.retry_flag ? OMQ::StatRetry : OMQ::StatError;
            remove e.retry_flag;
        }
        if (!exists e.status) {
            e.status = OMQ::StatError;
        } else {
            if (!ValidStatuses{e.status}) {
                if (init) {
                    log("init error: invalid status %y given in error %y; expected one of: %y; updating "
                        "to \"ERROR\"", e.status, e, keys ValidStatuses);
                        e.status = OMQ::StatError;
                } else {
                    throw "ERROR-UPDATE-ERROR", sprintf("invalid status %y given in error %y; expected one of: %y",
                        e.status, e, keys ValidStatuses);
                }
            }
        }

        if (e.status != OMQ::StatRetry && e.retry_delay_secs) {
            if (init) {
                log("error %y cannot have a retry delay if 'status' is not 'RETRY'; ignoring retry "
                    "delay", e);
                remove e.retry_delay_secs;
            } else {
                throw "ERROR-UPDATE-ERROR", sprintf("error %y cannot have a retry delay if 'status' is not 'RETRY'", e);
            }
        }

        # rename keys to keys used in class
        if (e.desc && !e.description) {
            e.description = remove e.desc;
        }

        if (e.business) {
            e.business_flag = remove e.business;
        }
    }

    private ErrorDef getError(hash e, *bool init) {
        foreach string attr in (ErrorDef::BoolAttrs) {
            if (e{attr}) {
                e{attr} = parse_boolean(e{attr});
            }
        }

        checkError(\e, init);

        ErrorDef err(e);
        checkSeverity(err);
        return err;
    }

    private ErrorDef getWfError(hash e) {
        # delete illegal direct references
        e -= ("business_flag", "retry_delay_secs", "manually_updated");

        auto v = e."retry-delay";
        if (exists v) {
            switch (v.typeCode()) {
                case NT_INT: e.retry_delay_secs = v; break;
                case NT_DATE: e.retry_delay_secs = v.durationSeconds(); break;
                default:
                    log("error %y has an invalid 'retry-delay' key of type '%s' (expecting 'int' or "
                        "'date')", e, v.type());
                    break;
            }
        }

        checkError(\e);

        ErrorDef err(e);
        checkSeverity(err);
        return err;
    }

    private checkSeverity(ErrorDef err) {
        if (!exists ErrorSeverityOrder.(err.severity)) {
            log("unknown severity %y in error %y; setting to %y", err.severity, hash(err), ES_Major);
            err.severity = ES_Major;
        }
    }

    list<hash<auto>> getGlobalErrorsList(*softlist<auto> l) {
        list<hash<auto>> rl = ();

        rwl.readLock();
        on_exit rwl.readUnlock();

        if (l) {
            foreach string err in (l) {
                if (geh{err}) {
                    rl += geh{err}.getGlobalInfo();
                }
            }
        } else {
            map rl += $1.getGlobalInfo(), geh.iterator();
        }
        return rl;
    }

    *hash<auto> getGlobalErrors(*softlist<auto> l) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        hash<auto> eh;
        if (l) {
            # get information about all global errors in the list that exist
            eh = map {$1: geh{$1}.getGlobalInfo()}, l, geh{$1};
        } else {
            # get information about all globals errors
            map eh{$1.key} = $1.value.getGlobalInfo(), geh.pairIterator();
        }
    	return eh;
    }

    *hash<auto> getGlobalError(string err) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return geh{err} ? geh{err}.getGlobalInfo() : NOTHING;
    }

    bool hasManuallyUpdatedWorkflowError(softstring wfid, string err) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        *ErrorDef ed = weh{wfid}{err};
        return !ed ? False : ed.manually_updated;
    }

    static hash<auto> getWorkflowInfo(softstring wfid) {
        try {
%ifdef QorusServer
            hash<auto> h = Qorus.qmm.lookupWorkflow(wfid, False);
%else
            hash<auto> h = qrest.get("system/metadata/lookupworkflow/" + wfid);
%endif
            return {
                "workflowname": h.name,
                "workflowversion": h.version,
                "workflowid": wfid.toInt(),
            };
        } catch (hash<ExceptionInfo> ex) {
            return {
                "workflowname": "unknown/deleted",
                "workflowversion": "unknown/deleted",
                "workflowid": wfid.toInt(),
                "error": sprintf("%s: %s", ex.err, ex.desc),
            };
        }
    }

    *hash<auto> getWorkflowError(softstring wfid, string err) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return weh{wfid}{err} ? weh{wfid}{err}.getWorkflowInfo() + ErrorManager::getWorkflowInfo(wfid) : NOTHING;
    }

    list<hash<auto>> getErrorsList(softstring wfid, *softlist<auto> l) {
        list<hash<auto>> rl = ();

        rwl.readLock();
        on_exit rwl.readUnlock();

        foreach string err in (l ? l : weh{wfid}.keyIterator()) {
            *ErrorDef rv = weh{wfid}{err};
            if (rv) {
                rl += rv.getWorkflowInfo() + ErrorManager::getWorkflowInfo(wfid);
            } else if (geh{err}) {
                rl += geh{err}.getGlobalInfo();
            }
        }

        return rl;
    }

    *hash<string, hash<auto>> getErrors(softstring wfid, *softlist<auto> l) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        hash<string, hash<auto>> h;
        foreach string err in (l ? l : keys weh{wfid}) {
            *ErrorDef rv = weh{wfid}{err};
            if (rv) {
                h{err} = rv.getWorkflowInfo();
            } else if (geh{err}) {
                h{err} = geh{err}.getGlobalInfo();
            }
        }

        return h;
    }

    *ErrorDef getError(softstring wfid, string err) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return weh{wfid}{err} ?? geh{err};
    }

    bool hasWorkflow(softstring wfid) {
        rwl.readLock();
        on_exit rwl.readUnlock();

        return exists weh{wfid};
    }

    string updateGlobalError(hash<auto> eh, bool from_wf = False, bool create_only = False) {
        ErrorDef err = from_wf ? getWfError(eh) : getError(eh);

        #printf("updateGlobalError: eh: %N\nerr: %N\n", eh, err);

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        # fix for bug 933: detect when the DB is out of sync and resync automatically
        while (True) {
            try {
                *ErrorDef e = geh.(err.error);
                if (e) {
                    if (create_only)
                        throw "ERROR-EXISTS", sprintf("global error %y already exists", eh.error);

                    # feature 645: add an option to suppress automatic updating of workflow errors but only allow automatic creation of global errors
                    if (from_wf && !auto)
                        return "IGNORED-GLOBAL";

                    # update global error if different
                    if (!err.equal(e)) {
                        sqlif.updateGlobalError(err);
                        geh.(err.error) = err;
                        log("updated global error: %y", hash(err));
                        return "UPDATED-GLOBAL";
                    }
                    log("global error definition unchanged: %y", hash(err));
                    return "UNCHANGED-GLOBAL";
                }

                # insert a new global error
                sqlif.createGlobalError(err);
            } catch (hash<ExceptionInfo> ex) {
                if (checkDup(ex))
                    continue;
                rethrow;
            }
            break;
        }
        geh.(err.error) = err;
        log("added global error: %y", hash(err));
        return "CREATED-GLOBAL";
    }

    string updateWorkflowError(softint wfid, hash<auto> eh, bool from_wf = False, bool create_only = False) {
        ErrorDef err = from_wf ? getWfError(eh) : getError(eh);

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        # fix for bug 933: detect when the DB is out of sync and resync automatically
        while (True) {
            try {
                # get any workflow-specific error
                *ErrorDef we = weh{wfid}.(err.error);

                if (we) {
                    if (create_only)
                        throw "ERROR-EXISTS", sprintf("error %y for workflowid %d already exists", eh.error, wfid);

                    # feature 645: add an option to suppress automatic updating of workflow errors but only allow automatic creation of global errors
                    if (from_wf && !auto)
                        return "IGNORED-WORKFLOW";

                    # update error if the definition has changed
                    if (!err.equal(we)) {
                        sqlif.updateWorkflowError(wfid, err, !from_wf);
                        weh{wfid}.(err.error) = err;
                        log("updated error for wfid %d: %y", wfid, hash(err));
                        return "UPDATED-WORKFLOW";
                    }
                    return "UNCHANGED-WORKFLOW";
                }

                # create a new workflow-specific error
                sqlif.createWorkflowError(wfid, err, !from_wf);
            } catch (hash<ExceptionInfo> ex) {
                if (checkDup(ex))
                    continue;
                rethrow;
            }
            break;
        }

        weh{wfid}.(err.error) = err;
        log("created workflow-specific error for wfid %d: %y", wfid, hash(err));
        return "CREATED-WORKFLOW";
    }

    private bool checkDup(hash ex) {
        switch (sqlif.omqp.getDriverName()) {
            case "oracle": {
                               if (ex.desc =~ /ORA-0+1:/) {
                                   reloadIntern();
                                   return True;
                               }
                               break;
                           }
            case "pgsql": {
                              if (ex.desc =~ /duplicate key value/) {
                                  reloadIntern();
                                  return True;
                              }
                              break;
                          }
            case "mysql": {
                              if (ex.desc =~ /Duplicate entry/) {
                                  reloadIntern();
                                  return True;
                              }
                              break;
                          }
        }
        return False;
    }

    string updateError(softint wfid, hash<auto> eh, bool from_wf = False, bool create_only = False) {
        ErrorDef err = from_wf ? getWfError(eh) : getError(eh);

        rwl.writeLock();
        on_exit rwl.writeUnlock();

        # fix for bug 933: detect when the DB is out of sync and resync automatically
        while (True) {
            try {
                # get any workflow-specific error
                *ErrorDef we = weh{wfid}.(err.error);

                if (we) {
                    if (create_only)
                        throw "ERROR-EXISTS", sprintf("error %y for workflowid %d already exists", eh.error, wfid);

                    # feature 645: add an option to suppress automatic updating of workflow errors but only allow automatic creation of global errors
                    if (from_wf && !auto)
                        return "IGNORED-WORKFLOW";
                    # update error if the definition has changed
                    if (!err.equal(we)) {
                        sqlif.updateWorkflowError(wfid, err, !from_wf);
                        weh{wfid}.(err.error) = err;
                        log("updated error for wfid %d: %y", wfid, hash(err));
                        return "UPDATED-WORKFLOW";
                    }
                    return "UNCHANGED-WORKFLOW";
                }

                # get any global error definition
                *ErrorDef e = geh.(err.error);
                if (e) {
                    # feature 645: add an option to suppress automatic updating of workflow errors but only allow automatic creation of global errors
                    if (from_wf && !auto)
                        return "IGNORED-GLOBAL";
                    # add workflow-specific error if the definition differs from the global definition
                    if (!err.equal(e)) {
                        sqlif.createWorkflowError(wfid, err, !from_wf);
                        weh{wfid}.(err.error) = err;
                        log("created workflow-specific error for wfid %d: %y", wfid, hash(err));
                        return "CREATED-WORKFLOW";
                    }

                    return "UNCHANGED-GLOBAL";
                }

                # register internal error
                geh.(err.error) = err;

                # create global error definition
                sqlif.createGlobalError(err);
            } catch (hash<ExceptionInfo> ex) {
                if (checkDup(ex))
                    continue;
                rethrow;
            }
            break;
        }
        return "CREATED-GLOBAL";
    }

    bool deleteWorkflowError(softint wfid, string err) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        if (!(remove weh{wfid}{err}))
            return False;

        if (!weh{wfid})
            remove weh{wfid};

        sqlif.deleteWorkflowError(wfid, err);
        log("deleted workflow-specific error for wfid: %d: %s", wfid, err);
        return True;
    }

    log(string msg) {
        if (logc) {
            string fmsg = vsprintf("ErrorManager: " + msg, argv);
            call_function_args(logc, fmsg);
        }
    }
}

%old-style
