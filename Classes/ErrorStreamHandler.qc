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

class ErrorStreamHandler inherits AbstractRestStreamRequestHandler {
    public {
        int code;
        string msg;
    }

    constructor(hash cx, *hash ah, int n_code, string fmt) : AbstractRestStreamRequestHandler(cx, ah) {
        code = n_code;
        msg = vsprintf(fmt, argv);
    }

    hash getResponseHeaderMessageImpl() {
        return AbstractHttpRequestHandler::makeResponse(code, msg);
    }

    nothing recvImpl(hash v) {}

    auto sendImpl() {}
}
