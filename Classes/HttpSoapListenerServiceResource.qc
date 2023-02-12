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

class OMQ::HttpSoapListenerServiceResource inherits OMQ::HttpListenerServiceResource {
    public {
        # list of hashes SOAP handlers; keys: path, url
        list<hash<auto>> sl = ();
    }

    constructor(softstring serviceid, string listener_name, int rsid, int n_id, string desc, softlist paths)
        : OMQ::HttpListenerServiceResource(serviceid, listener_name, listener_name, rsid, n_id, desc) {
        map addPath($1), paths;
    }

    addPath(string path) {
        path = "/SOAP/" + path;
        string soap_url = url + path;
        sl += {
            "path": path,
            "url": soap_url,
            "wsdl": soap_url + "?wsdl",
        };
    }

    string getType() {
        return "HttpSoapListener";
    }

    hash<auto> getInfo(*hash<auto> cx) {
        list<hash<auto>> rsl = sl;
        if (wc_bind && cx)
            rsl = map (map {$1.key: $1.key == "path" ? $1.value : fixUrl($1.value, cx)}, $1.pairIterator()), sl;

        return HttpListenerServiceResource::getInfo(cx) + {
            "services": rsl,
        };
    }
}
