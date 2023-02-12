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

class OMQ::SoapServiceResource inherits OMQ::AbstractServiceResource {
    public {
        WebService ws;
        string orig_path;
        string path;
        string url;
        string unique_id;
    }

    constructor(string service_name, WebService ws, string path, string unique_id)
            : AbstractServiceResource(SoapServiceResource::getResourceName(service_name, ws),
                sprintf("serving path: /SOAP/%s", path)) {
        self.ws = ws;
        orig_path = path;
        self.path = "/SOAP/" + path;
        url = UserApi::qorusGetLocalUrl() + self.path;
        self.unique_id = unique_id;
    }

    string getType() {
        return "SoapServer";
    }

    # cannot lock; returns True if stopped
    private bool disableImpl() {
        Qorus.soapHandler.removeService(unique_id);
        QDBG_LOG("SoapServiceResource::disableImpl() unique_id: %y", unique_id);
        return True;
    }

    stop(*bool aborted) {
        Qorus.soapHandler.removeService(unique_id);
    }

    hash<auto> getInfo(*hash<auto> cx) {
        string req_url = cx ? qorus_get_url(cx, url) : url;
        return {
            "path": path,
            "url": req_url,
            "wsdl": req_url + "?wsdl",
        };
    }

    static string getResourceName(string service_name, WebService ws) {
        return sprintf("soap-%s-%s", service_name, ws.getWSDLHash());
    }
}
