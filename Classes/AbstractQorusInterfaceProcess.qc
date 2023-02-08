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

class AbstractQorusInterfaceProcess inherits AbstractQorusInternProcess {
    private {
        int stack_size;
    }

    # creates the object
    /** @param parent the process manager object
        @param node the unique node name where the process is running
        @param name the name of the server process
        @param client_id the server-specific name
        @param cl_opts optional command-line arguments for the child process
    */
    constructor(AbstractQorusProcessManager parent, string node, string host, string name, string client_id,
            bool restarted, int stack_size, *softlist<softstring> cl_opts)
            : AbstractQorusInternProcess(parent, node, host, name, client_id, restarted, cl_opts) {
        self.stack_size = stack_size;
    }

    # returns information needed to restart the process if it terminates unexpectedly (or is killed)
    *hash<auto> getProcessInfo() {
        return {
            "stack_size": stack_size,
        };
    }

    # sends a message to a subsystem of an interface process with no response expected
    broadcastSubsystemOneWay(data msgdata) {
        AbstractQorusClient client = getClient();
        client.sendCmdOneWaySerialized(CPC_BCAST_SUBSYSTEM, msgdata);

    }
    # sends a message for a direct call in an interface process with no response expected
    broadcastSubsystemOneWayDirect(data msgdata) {
        AbstractQorusClient client = getClient();
        client.sendCmdOneWaySerialized(CPC_BCAST_DIRECT, msgdata);
    }

    abstract addToCore(QorusCoreProcess proc);
}
