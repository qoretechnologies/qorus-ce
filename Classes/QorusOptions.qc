# -*- mode: qore; indent-tabs-mode: nil -*-

# QorusOptions.qc
#
# functions for setting and accessing Qorus options

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

class OMQ::QorusOptions inherits QorusOptionsBase {
    private {
        # mutex for atomically setting option values
        Mutex lck();

        # locked options
        hash<string, bool> option_locks;
    }

    /* returns a hash with the following keys:
        - \c val: the set of options and values set atomically
        - \c errs: a list of strings about errors
    */
    hash<auto> setExtern(hash<auto> opthash) {
        hash<auto> rv.errs = ();

        on_success if (rv.val)
            Qorus.getMaster().broadcastToAllInterfaces("options", "setExtern", rv.val);

        foreach string k in (keys opthash) {
            string opt = OMQ::get_option_name("qorus", k);
            if (!exists OMQ::QorusSystemOptionHash{opt}) {
                rv.errs += sprintf("ERROR: unknown Qorus system option %y", k);
                continue;
            }

            if (!init_flag)
                manual_opts{opt} = opthash{k};

            *softlist<auto> l = setIntern(opt, opthash{k}, "qorus", False, \rv.val{k});
            if (l)
                rv.errs += l;
        }
        return rv;
    }

    list<auto> set(hash<auto> opthash) {
        list<auto> errs = ();

        hash<auto> rv;
        on_success if (rv)
            Qorus.getMaster().broadcastToAllInterfaces("options", "setExtern", rv);

        foreach string k in (keys opthash) {
            string opt = OMQ::get_option_name("qorus", k);
            if (!exists OMQ::QorusSystemOptionHash{opt}) {
                errs += sprintf("ERROR: unknown Qorus system option %y", k);
                continue;
            }

            if (!init_flag)
                manual_opts{opt} = opthash{k};

            *softlist<auto> l = setIntern(opt, opthash{k}, "qorus", False, \rv{k});
            if (l)
                errs += l;
        }
        return errs;
    }

    private auto setValueIntern(string opt, auto nv) {
        {
            lck.lock();
            on_exit lck.unlock();

            if (option_locks{opt}) {
                throw "OPTION-ERROR", sprintf("ERROR: Qorus system option %y is locked and cannot be changed; in "
                    "order to change the value of this option, please change it in the options file: %y and "
                    "restart the Qorus server", opt, opts."option-file");
            }

            QorusOptionsBase::setValueIntern(opt, nv);
        }
        postProcessOptionValue(opt, nv);
        return nv;
    }

    private static int getSegment(int si, list<auto> seg) {
        # see which segment step is in; get front-end segment for boundary steps
        for (int i = 0; i < elements seg; ++i) {
            if (inlist(si, seg[i].steplist)) {
                #printf("DEBUG: stepid %d in segment %d\n", si, i);
                return i;
            }
        }
        throw "WORKFLOW-SEGMENT-ERROR", sprintf("stepid %d not found in any segment: %y", si, seg);
    }

    int lockOptions(softlist<auto> l) {
        int rv = 0;

        foreach string o in (l) {
            if (!exists OMQ::omq_option_hash{o})
                rv = -1;
            else
                option_locks{o} = True;
        }
        return rv;
    }

    hash<auto> getOptionInfo(*softlist<auto> l) {
        if (!l)
            return getOptionInfoHash();

        return (map {$1: getInfoIntern($1)}, l, OMQ::omq_option_hash.$1) ?? {};
    }

    private hash<auto> getInfoIntern(string o) {
        *hash<auto> oh += OMQ::omq_option_hash{o};
        map oh.$1 = False, ("workflow", "service", "job"), !oh.$1;
        hash<auto> h = {
            "name"         : o,
            "value"        : get(o),
            "expects"      : oh.list ? Type::List : OMQ::omq_option_hash{o}.arg,
            "desc"         : OMQ::get_option_description(oh),
            "default"      : OMQ::QorusSystemOptionDefaults{o},
            "startup-only" : oh."startup-only",
            "status"       : option_locks{o} ? "locked" : "unlocked",
         } + oh.("workflow", "service", "job");
        if (exists OMQ::omq_option_hash{o}.interval)
            h."interval" = OMQ::omq_option_hash{o}.interval;
        if (OMQ::omq_option_hash{o}.list)
            h."list-element-type" = OMQ::omq_option_hash{o}.arg;
        return h;
    }

    hash<auto> getOptionInfoHash() {
        return map {$1: getInfoIntern($1)}, keys OMQ::omq_option_hash;
    }

    # NOTE: called outside the option mutex
    private postProcessOptionValue(string k, auto val) {
        # FIXME: should not have to hardcode this
        switch (k) {
            case "recover_delay":
            case "async_delay": {
                if (SM)
                    SM.requeueAllRetries();
                break;
            }

            case "detach-delay": {
                if (SM)
                    SM.detachDelayUpdated();
                break;
            }

            case "sync-delay": {
                if (Qorus.SEM)
                    Qorus.SEM.syncDelayUpdated();
                break;
            }

            case "audit": {
                if (Qorus.audit)
                    Qorus.audit.setMask(opts.audit);
                break;
            }

            case "debug-system": {
                Qorus.setDebug(val);
                break;
            }

            case "defines": {
                Qorus.setRuntimeProps(val);
                break;
            }

            case "sla-max-sync-secs": {
                Qorus.qmm.requeueSlaEvents();
                break;
            }

            case =~ /^cors-/:
                QorusHttpServer::corsUpdateOption(k, val);
                break;
        }
    }

    flushToFile(*hash<auto> optHash) {
        string fname = get("option-file");
        File f();

        # backup
        *hash<StatInfo> stat = hstat(fname);
        if (exists stat) {
            string bname = sprintf("%s.%s", fname, now());
            try {
                FileInputStream fo(fname);
                FileOutputStream fb(bname);
                while (*binary b = fo.read(4096)) {
                    fb.write(b);
                }
            } catch (hash<ExceptionInfo> ex) {
                string msg = sprintf("Error in option file backup process: %s: %s", ex.desc, ex.err);
                throw "OPTION-ERROR", msg;
            }
        }

        # create new file
        try {
            f.open2(fname, O_CREAT | O_TRUNC | O_WRONLY);
            f.printf("#\n");
            f.printf("# This file was created with an API call\n");
            f.printf("#     Timestamp: %y\n", now());
            f.printf("#\n\n");
        } catch (hash<ExceptionInfo> ex) {
            throw "OPTION-ERROR",
                 sprintf("Error in option file creation process - %s - %s", ex.desc, ex.err);
        }

        foreach string key in (keys OMQ::omq_option_hash) {
            auto val = (exists optHash{key}) ? optHash{key} : get(key);
            if (val == OMQ::QorusSystemOptionDefaults{key})
                f.printf("# qorus.%s is using its default value\n", key);
            if (key == "http-server") {
                # filter out default UNIX socket listener from value
                list<auto> l = map trim($1), val, $1 !~ /^\/tmp\/qorus-sock-/;
                f.printf("qorus.%s: %s\n", key, valueToString(l));
            } else {
                f.printf("qorus.%s: %s\n", key, valueToString(val));
            }
        }

        # process the "user defined" options back to file.
        foreach string mkey in (keys all_opts) {
            f.printf("#\n# Domain: %s\n", mkey);
            map f.printf("%s.%s: %s\n", mkey, $1.key, valueToString($1.value)), all_opts{mkey}.pairIterator();
        }

        f.close();
    }

    static auto valueToString(auto val) {
        switch (val.typeCode()) {
            case NT_HASH: {
                return foldl $1 + "," + $2, (map sprintf("%s=%s", $1.key, $1.value), val.pairIterator());
            }
            case NT_LIST: {
                return foldl $1 + "," + $2, val;
            }
            default:
                return val;
        }
    }

    private string getStringValue(string o) {
        auto v = get(o);
        if (exists v)
            return sprintf("%y", v);
        if (OMQ::omq_option_hash{o}.arg == Type::Int)
            return "0";
        else if (OMQ::omq_option_hash{o}.arg == Type::List)
            return "[empty list]";
        else if (OMQ::omq_option_hash{o}.arg == Type::Hash)
            return "{empty hash}";
        else
            return "[no value]";
    }
}
