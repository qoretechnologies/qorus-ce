# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%requires qore >= 1.0

%new-style
%require-our
%strict-args
%require-types

%enable-all-warnings

class QorusOptionsBase {
    private {
        # Options (domain => (key => value, ...), ...) which are not handled by Qorus
        # but are defined in the option file.
        hash<auto> all_opts;

        # etc file prefix
        string configdir = (ENV.OMQ_DIR == "LSB" ? "/etc/qorus/" : ENV.OMQ_DIR + (PlatformOS != "Windows" ? "/etc/" : "\\etc\\"));

        # hash of manually-overridden options
        hash<string, softstring> manual_opts;

        # hash of actual Qorus options
        hash<auto> opts;

        # updated options
        hash<string, bool> updated;

        # initialized flag
        bool init_flag = False;

        # client domain
        hash<auto> client;
    }

    public {
        const EtcOptions = DirSep + "etc" + DirSep + "options";
    }

    bool needsInit() {
        return !init_flag;
    }

    init(*bool silent) {
        beginInit(silent);
        finalizeInit();
    }

    beginInit(*bool silent) {
        if (init_flag) {
            return;
        }
        on_exit {
            init_flag = True;
        }

        readOptionFile(silent);
    }

    finalizeInit() {
        setDefaults();

        # check for sane server option values
        # check for session key
        if (!exists opts."instance-key") {
            stderr.printf("ERROR cannot start Qorus: no instance key set (add to %s%s)\n", ENV.OMQ_DIR, EtcOptions);
            exit(QSE_NO_INSTANCE_KEY);
        }

        # show a warning if OMQ connection pool is less than the number of db threads to use
        if (opts."system-pool-maximum" < opts."db-max-threads") {
            stderr.printf("WARNING: value set for db-max-threads is greater than system-pool-maximum:\n");
            stderr.printf("         system-pool-maximum: %d\n", opts."system-pool-maximum");
            stderr.printf("         db-max-threads: %d\n", opts."db-max-threads");
            stderr.printf("         assuming db-max-threads: %d\n", opts."system-pool-maximum");
            opts."db-max-threads" = opts."system-pool-maximum";
        }

        # show a warning if the max-service-threads value is too small
        if (opts."max-service-threads" < 5) {
            stderr.printf("WARNING: max-service-threads is too small (%d); assuming max-service-threads: 5\n",
                opts."max-service-threads");
            opts."max-service-threads" = 5;
        }
    }

    string getClientUrl(string username, string password) {
        return regex_subst(client."client-url", "(https?://)", sprintf("$1%s:%s@", username, password));
    }

    string getClientUrl() {
        return client."client-url";
    }

    *hash<auto> getClientOptions() {
        return client;
    }

    private readOptionFile(*bool silent) {
        int errors;

        # was "option-file" set from the command line?
        bool cl = exists opts."option-file";
        if (!cl)
            opts."option-file" = configdir + "options";

        File f();
        if (f.open(opts."option-file", "r")) {
            if (!cl) {
                if (!silent)
                    stderr.printf("WARNING: cannot read option file %y: %s, setting default options\n",
                        opts."option-file", strerror(errno()));
                return;
            }

            # exit with an error if the option file set from the command line is not readable
            stderr.printf("ERROR: cannot read option file %y: %s, cannot start Qorus\n", opts."option-file",
                strerror(errno()));
            exit(1);
        }

        int lc;
        bool ue;
        while (exists (*string line = f.readLine())) {
            lc++;

            # remove eol marker and preceding and trailing spaces
            trim line;

            # skip commented-out and blank lines
            if (line =~ /^#/ || !strlen(line))
                continue;

            # get line line: domain.option:value
            *list<string> l = (line =~ x/([^\.:=]+)\.([^\.:=]+)[=:](.*)/);
            trim l;
            (*string domain, *string opt, *string value) = (l[0], l[1], l[2]);

            if (!exists value) {
                stderr.printf("error parsing options file %s:%d: %y does not have \"domain.option: value\" format\n",
                    opts."option-file", lc, line);
                errors++;
                continue;
            }

            trim opt;
            trim value;

            # ignore case for domain and option
            domain = domain.lwr();
            opt = opt.lwr();

            if (exists all_opts{domain}{opt} && !silent
                && (domain != "qorus"
                    && !(OMQ::QorusSystemOptionHash{opt}."list"
                        || OMQ::QorusSystemOptionHash{opt}.arg =~ /^hash/)))
                stderr.printf("WARNING: option %s.%s appears multiple times in %s\n", domain, opt, opts."option-file");

            # "omq" is accepted as equal to "qorus" for backwards-compatibility reasons
            if (domain == "omq")
                domain = "qorus";

            # save all processed options for flushToFile()
            all_opts{domain}{opt} = value;

            # "omq" is accepted as equal to "qorus" for backwards-compatibility reasons
            if (domain == "qorus") {
                # get option name in case an alias is used
                opt = OMQ::get_option_name("qorus", opt);

                # set the option if it has not already been set from the command line
                if (!manual_opts{opt}) {
                    *list<auto> el = setIntern(opt, value, "qorus", True);
                    if (el) {
                        stderr.printf("error in options file %s:%d: %s\n", opts."option-file", lc, el[0]);
                        ++errors;
                        continue;
                    }
                }
                else # remove already processed option (if it's supported by Qorus)
                    remove all_opts.qorus{opt};
            } else if (domain == "qorususer" || domain == "omquser") {
                if (!ue) {
                    stderr.printf("error in options file: outdated user definition, run user-tool -M to migrate user "
                        "info to RBAC DB, ignoring further user definitions\n");
                    ++errors;
                    ue = True;
                }
            } else {
                processOtherDomain(domain, opt, value);
            }
        }

        if (errors) {
            stderr.printf("please correct the errors listed above and try again\n");
            exit(1);
        }
    }

    softlist<string> getCommandLineOptions() {
        return map sprintf("%s=%s", $1.key, $1.value), manual_opts.pairIterator();
    }

    # ignore other domains by default in the base class
    private processOtherDomain(string domain, string opt, string value) {
        if (domain == "qorus-client") {
            client{opt} = processOptionValue(opt, value, OMQ::client_option_hash, domain, False);
        }
    }

    private setDefaults() {
        # set default server options
        map opts.$1 = OMQ::QorusSystemOptionDefaults.$1, keys OMQ::QorusSystemOptionDefaults, !exists opts.$1;

        # set default options that are computed
        if (!opts.logdir) {
            opts.logdir = ENV.OMQ_LOG_DIR ?? (ENV.OMQ_DIR + (PlatformOS != "Windows" ? "/log" : "\\log"));  # default log directory
        }
        if (opts.logdir && substr(opts.logdir, -1) != DirSep) {
            opts.logdir += DirSep;
        }
        if (!opts."http-server" && !opts."http-secure-server") {
            opts."http-server" = list(OMQ::DefaultServerPort);
        }

        # ensure client-url is set to the server's url if not already set
        if (!client."client-url") {
            client."client-url" = opts."http-secure-server"
                ? getURLFromOption("https", opts."http-secure-server"[0])
                : getURLFromOption("http", opts."http-server"[0]);
        }

        # set client-pool-minimum and client-pool-maximum from system values if not explicitly set
        if (!client."client-pool-minimum")
            client."client-pool-minimum" = opts."system-pool-minimum";
        if (!client."client-pool-maximum")
            client."client-pool-maximum" = opts."system-pool-maximum";

        # set default client options
        map client.$1 = OMQ::client_defaults.$1, keys OMQ::client_defaults, !exists client.$1;
    }

    static private string getURLFromOption(string prot, softstring opt, string hostname = Qorus.getLocalAddress()) {
        # remove any cert,key options, etc
        opt =~ s/{.*}$//;
        if (opt =~ /:/) {
            # convert "0.0.0.0", "::", and "[::]" to the qorus-core IP address
            opt = regex_subst(opt, "^(0.0.0.0|::|\\[::\\]):", hostname + ":");
            return sprintf("%s://%s", prot, opt);
        }
        return sprintf("%s://%s:%d", prot, hostname, opt);
    }

    list<auto> set(hash<auto> opthash) {
        list<auto> errs = ();

        foreach string k in (keys opthash) {
            string opt = OMQ::get_option_name("qorus", k);
            if (!exists OMQ::QorusSystemOptionHash{opt}) {
                errs += sprintf("ERROR: unknown Qorus system option %y", k);
                continue;
            }

            if (!init_flag)
                manual_opts{opt} = opthash{k};

            *softlist<auto> l = setIntern(opt, opthash{k}, "qorus");
            if (l)
                errs += l;
        }
        return errs;
    }

    private *softlist<auto> setIntern(string opt, auto v, string domain, bool add = False, *reference<auto> val) {
        try {
            *hash<auto> opthash = domain == "qorus" ? OMQ::QorusSystemOptionHash : NOTHING;
            auto nv = processOptionValue(opt, v, opthash, domain, True);
            if (add && exists opts{opt}) {
                if (opthash{opt}."list") {
                    nv = opts{opt} + nv;
                } else if (opthash{opt}.arg =~ /^hash/) {
                    # check for duplicate hash keys
                    *hash<auto> dh = opts{opt}{keys nv};
                    if (dh) {
                        throw "OPTION-ERROR", sprintf("option %y defined with the following duplicate hash keys: %y",
                            opt, keys dh);
                    }
                    #printf("nv: %y opts{%y}: %y\n", nv, opt, opts{opt});
                    nv = opts{opt} + nv;
                } else if (!manual_opts.hasKey(opt)) {
                    throw "OPTION-ERROR", sprintf("option %y given multiple times but can only hold a single value "
                        "(type %y)", opt, opthash{opt}.arg);
                }
            }

            # process interval
            if (!opthash{opt}."list" && (*list<auto> iv = opthash{opt}.interval)) {
                if (iv[0] != "UNLIMITED" && (nv.toInt() < iv[0])) {
                    stderr.printf("WARNING: option %y cannot be less than %d; ignoring value %d and setting to "
                        "minimum value %d\n", opt, iv[0], nv, iv[0]);
                    nv = iv[0];
                }
                if (iv[1] != "UNLIMITED" && (nv.toInt() > iv[1])) {
                    stderr.printf("WARNING: option %y cannot be greater than %d; ignoring value %d and setting to "
                        "maximum value %d\n", opt, iv[1], nv, iv[1]);
                    nv = iv[1];
                }
            }

            val = setValueIntern(opt, nv);
        } catch (*hash<ExceptionInfo> ex) {
            list<auto> l;
            do {
                l += sprintf("%s: %s", get_ex_pos(ex), ex.desc);
                ex = ex.next;
            } while (ex);
            return l;
        }
        #printf("DEBUG: %s = %y\n", opt, opts{opt});
    }

    private auto setValueIntern(string opt, auto nv) {
        opts{opt} = nv;
        updated{opt} = True;
        return nv;
    }

    hash<auto> get() {
        return opts.(OMQ::QorusSystemOptionHash.keys());
    }

    auto get(string field) {
        return opts{field};
    }

    auto get(list<auto> field) {
        return opts{field};
    }

    auto processOptionValue(string k, auto val, *hash<auto> opthash, string dom, bool sys) {
        auto rv;
        if (opthash) {
            rv = OMQ::process_option_value(k, val, opthash, dom);
            check_deprecated_option(\opthash{k}, k, rv, sub (string str) {
                if (Qorus) {
                    Qorus.log(LoggerLevel::FATAL, str);
                } else {
                    printf("%s\n", str);
                }
            });
        } else
            rv = val;

        # validate the option if a validation closure is available
        if (opthash{k}.validate)
            opthash{k}.validate(rv);

        return rv;
    }
}
