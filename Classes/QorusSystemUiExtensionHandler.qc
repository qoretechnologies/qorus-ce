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

class QorusSystemUiExtensionHandler inherits AbstractHttpRequestHandler {
    constructor() : AbstractHttpRequestHandler(Qorus.rbac) {
    }

    hash<auto> handleRequest(hash<auto> cx, hash<auto> hdr, *data body) {
        *string ename = (hdr.path =~ x/UIExtension\/([^\/\?]+)/)[0];
        if (!ename) {
            return hash<HttpResponseInfo>{
                "code": 400,
                "body": sprintf("UI-EXTENSION-ERROR: cannot find extension name in request path %y", hdr.path),
            };
        }

        return services.handleUiExtensionRequest(ename, cx, hdr, body);
    }
}

