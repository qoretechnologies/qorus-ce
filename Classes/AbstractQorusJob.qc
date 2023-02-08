# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus abstract job base class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

class OMQ::AbstractQorusJob {
    public {}

    private {
        # job ID
        int jobid;

        # job name
        string name;

        # version of job
        string version;

        # job state data save closure
        static code psave;

        # job persistent state data save closure
        static code ppsave;
    }

    constructor(int jobid, string name, string version) {
        self.jobid = jobid;
        self.name = name;
        self.version = version;
    }

    int getId() {
        return jobid;
    }

    string getName() {
        return name;
    }

    string getVersion() {
        return version;
    }

    abstract logFatal(string msg);
    abstract logError(string msg);
    abstract logWarn(string msg);
    abstract logInfo(string msg);
    abstract logDebug(string msg);
    abstract logTrace(string msg);

    abstract setStopReason(*string reason);

    static staticInit() {
        # initialize state data save closure
        psave = get_sql_table_system("omq", "job_state_data").getUpsertClosure(
            {"jobid": 1, "data": "string"}, AbstractTable::UpsertAuto);
        # initialize persistent state data save closure
        ppsave = get_sql_table_system("omq", "job_persistent_state_data").getUpsertClosure(
            {"jobid": 1, "data": "string"}, AbstractTable::UpsertAuto);
    }
}
