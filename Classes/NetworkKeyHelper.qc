# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args
%enable-all-warnings

# private class for managing network keys
class NetworkKeyHelper {
    private {
        # private key file location
        string path;
        # private key for both server and client
        string privkey;
        # public key for both server and client
        string pubkey;
    }

    constructor(hash<auto> options) {
        # issue #3171: report a user-friendly error if no network key is set
        if (!options."network-key".val()) {
            throw "QORUS-ENCRYPTION-ERROR", sprintf("cannot initialize encryption; no \"network-key\" option set in "
                "the options file");
        }
        init(options."network-key");
    }

    constructor(string fn) {
        init(fn);
    }

    private init(string fn) {
        privkey = zmq_z85_encode(getKey("network", fn));
        try {
            pubkey = zmq_curve_public(privkey);
        } catch (hash<ExceptionInfo> ex) {
            throw "QORUS-ENCRYPTION-ERROR", sprintf("cannot derive public network key from private key %y: %s: %s",
                fn, ex.err, ex.desc);
        }
        path = fn;
    }

    string getNetworkKeyPath() {
        return path;
    }

    setServer(ZSocket server) {
        server.setOption(ZMQ_CURVE_SERVER, 1);
        server.setOption(ZMQ_CURVE_SECRETKEY, privkey);
        server.setOption(ZMQ_CURVE_PUBLICKEY, pubkey);
    }

    setClient(ZSocket client) {
        client.setOption(ZMQ_CURVE_SERVER, 0);
        client.setOption(ZMQ_CURVE_SERVERKEY, pubkey);
        client.setOption(ZMQ_CURVE_SECRETKEY, privkey);
        client.setOption(ZMQ_CURVE_PUBLICKEY, pubkey);
    }

    static binary getKey(string label, *string fn) {
        if (!exists fn) {
            string opt = label;
            opt =~ s/ /-/g;
            throw "QORUS-ENCRYPTION-ERROR", sprintf("Qorus option %y is not set; the system cannot be started until this error is resolved; please add a \"qorus.%s\" entry manually or by calling \"schema-tool -V\" and try again", opt, opt);
        }

        if (!is_readable(fn)) {
            string opt = label;
            opt =~ s/ /-/g;
            throw "QORUS-ENCRYPTION-ERROR", sprintf("Unable to read %s encryption key file: %y; the system cannot be started until this error is resolved; either remove the %y option or make sure the file is readable by the application user", label, fn, opt);
        }

%ifdef Unix
        hash sh = hstat(fn);
        if (sh.mode & 022) {
            string opt = label;
            opt =~ s/ /-/g;
            throw "QORUS-ENCRYPTION-ERROR", sprintf("%s encryption key file %y as set by the %y option has too permissive permissions %y (0%o); the system cannot be started until the group and/or other readable bits are removed", label, fn, opt, sh.perm, sh.mode);
        }
%endif

        binary key = ReadOnlyFile::readBinaryFile(fn);
        if (key.empty()) {
            string opt = label;
            opt =~ s/ /-/g;
            throw "QORUS-ENCRYPTION-ERROR", sprintf("%s encryption key file %y as set by the %y option is empty; the system cannot be started until this error is resolved", label, fn, opt);
        }

        return key;
    }
}
