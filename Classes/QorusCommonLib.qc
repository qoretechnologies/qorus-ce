# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

hashdecl AutoAssignNodeOptionInfo {
    #! do not exit if there's an error assigning the node value
    bool no_exit_on_error = False;
    #! do not issue a warning when generating the node value
    bool no_assume_warning = False;
}

class QorusCommonLib {
    private {
        static bool in_container;
    }

    static string autoAssignNode(reference<hash<string, bool>> local_addresses, *hash<AutoAssignNodeOptionInfo> options) {
        string addr;
        list<hash<NetIfInfo>> address_list = get_netif_list();
        # first try to find a non-loopback interface
        foreach hash<NetIfInfo> info in (address_list) {
            if (info.family == AF_INET && info.address !~ /^127\./) {
                addr = info.address;
                break;
            }
            if (info.family == AF_INET6 && info.address != "::1") {
                addr = info.address;
                break;
            }
        }
        if (!addr) {
            stderr.printf("WARNING: cannot find a non-loopback address for \"qorus.node\"\n");
            if (address_list) {
                addr = address_list[0].address;
            } else {
                if (options.no_exit_on_error) {
                    return "error";
                }
                stderr.printf("ERROR: this machine has no IPv4 or IPv6 network addresses; Qorus cannot be started on "
                    "this machine\n");
                exit(QSS_ERROR);
            }
        }
        string node = sprintf("%s-%s", gethostname(), addr);
        node =~ s/\./-/g;
        if (!options.no_assume_warning && !QorusCommonLib::inContainer()) {
            stderr.printf("WARNING: assuming %s=%s for the \"qorus.node\" value\n", node, addr);
        }
        local_addresses{addr} = True;
        return node;
    }

    static bool inContainer() {
        if (exists in_container) {
            return in_container;
        }
        if (ENV.KUBERNETES_SERVICE_HOST) {
            return in_container = True;
        }
        if (PlatformOS == "Linux") {
            ReadOnlyFile f("/proc/1/sched");
            string init = f.readLine();
            init =~ s/ .*//;
            if (init == "runsv") {
                return in_container = True;
            }
        }
        return in_container = False;
    }
}