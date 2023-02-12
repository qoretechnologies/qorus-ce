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

public namespace OMQ;

class OMQ::ClusterServiceManagerClient inherits QorusCoreSubsystemClientBase {
    constructor(AbstractQorusClient core) : QorusCoreSubsystemClientBase(core, "services") {
    }

    auto callMethodExtern(string type, string name, string method, *softlist<auto> args, *hash<auto> my_tld, *bool ext) {
        # issue #3218: serialize the args twice to ensure that they are not deserialized in qorus-core
        return doCallWithSerializedResponse("callMethodExternSerialized",
            (type, name, method, Serializable::serialize(args), my_tld, ext));
    }

    auto methodGate(string method) {
        return methodGateArgs(method, argv);
    }
}
