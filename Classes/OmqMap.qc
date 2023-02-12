# -*- mode: qore; indent-tabs-mode: nil -*-
# @file OmqMap.qc defines the class that stores system metadata

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args

class OmqMap inherits Map {
    public {
        *hash<auto> wfmap;
        *hash<auto> wfrmap;
        # map of loggerid -> workflowid
        *hash<string, int> logger_wfmap;

        *hash servicemap;
        *hash servicermap;
        *hash serviceamap;
        *hash servicemethodmap;
        # map of loggerid -> serviceid
        *hash<string, int> logger_svcmap;

        # cache for loggers: logger ID -> logger info
        *hash<auto> loggerMap;
        # map of logger aliases to logger IDs: alias -> logger ID
        *hash<string, int> loggerAliases;

        *hash jmap;
        *hash jrmap;
        # map of loggerid -> jobid
        *hash<string, int> logger_jobmap;

        *hash stepmap;
        *hash steprmap;

        *hash functionmap;
        *hash functionrmap;

        *hash constmap;
        *hash constrmap;

        *hash classmap;
        *hash classrmap;

        *hash emap;
        *hash ermap;

        *hash qmap;
        *hash qrmap;

        *hash mmap;
        *hash mrmap;

        *hash vmmap;
        *hash vmrmap;

        *hash authlabelmap;

        # sla map: keyed by slaid
        *hash<string, hash<SlaInfo>> slamap;
        # sla rmap: keyed by sla name
        *hash<string, hash<SlaInfo>> slarmap;

        # config item values map (prefix + name -> level -> value)
        *hash<auto> configItemValues;

        *list wfids;
        *list svcids;
        *list systemserviceids;
        *list userserviceids;
        *list jobids;

        *hash<auto> pipelines;
        *hash<auto> fsm;
    }
}
