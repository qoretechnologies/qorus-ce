# -*- mode: qore; indent-tabs-mode: nil -*-

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

public namespace OMQ;

class OMQ::RemoteHttpRequestHandler inherits AbstractServiceDataStreamResponseHandler {
    constructor(RemoteQorusService svc, string rid, hash<auto> conf) : AbstractServiceHttpHandler(conf.url, conf.content_type, conf.special_headers, RemoteHttpRequestHandler::getAuth(svc, rid, conf), conf.isregex) {
    }
}
