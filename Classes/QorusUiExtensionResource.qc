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

class OMQ::QorusUiExtensionResource inherits OMQ::AbstractServiceResource {
    private {
        # Qorus service type: user or system
        string stype;
        # original Qorus service name (real name)
        string sname;

        QorusExtensionHandler handler;
    }

    #! default contructor. it makes <svc type>-<svc name>-<resource id> hander
    /** @param n_st service type (user or system)
        @param n_sn real service name
        @param n_id a resource id
        @param n_handler extension handler
     */
    constructor(string n_st, string n_sn, int n_id, QorusExtensionHandler n_handler)
            : AbstractServiceResource(sprintf("%s-%s-%d", n_st, n_sn, n_id), n_handler.getDesc()) {
        handler = n_handler;
        stype = n_st;
        sname = n_sn;

        init();
    }

    #! named constructor. it makes <url_name> handler
    /** @param n_st service type (user or system)
        @param n_sn real service name
        @param url_name name of the URL path 'alias'
        @param n_handler extension handler
     */
    constructor(string n_st, string n_sn, string url_name, QorusExtensionHandler n_handler)
            : AbstractServiceResource(url_name, n_handler.getDesc()) {
        handler = n_handler;
        stype = n_st;
        sname = n_sn;

        init();
    }

    private init() {
        # make sure a default resource is defined
        if (!handler.default_resource) {
            throw "UI-EXTENSION-ERROR", "no default resource is defined for the UI extension; call "
                "QorusExtensionHandler::setDefaultResource() before calling ServiceApi::uiExtensionRegister()";
        }

        # set url in handler based on extension name
        handler.url = sprintf("%s/%s", UiExtensionRoot, name);

        services.addUiExtension(name, self);
    }

    QorusExtensionHandler getHandler() {
        return handler;
    }

    string getServiceName() {
        return sname;
    }

    # this returns real Qorus service type - "user" or "system".
    # Used to navigate in internal cache tree.
    string getServiceType() {
        return stype;
    }

    string getType() {
        return "UiExtension";
    }

    string getGroup() {
        return handler.getGroup();
    }

    string getMenuName() {
        return handler.getMenuName();
    }

    stop(*bool aborted) {
        services.removeUiExtension(name);
    }

    hash<auto> getInfo(*hash<auto> cx) {
        return {
            "url": cx ? qorus_get_url(cx, handler.url) : handler.url,
            "group": handler.getGroup(),
            "menuname": handler.getMenuName(),
            "desc": desc,
        };
    }

    hash<auto> getUiExtensionInfo(hash<auto> cx) {
        # get target URL
        string scheme;
        if (*string req_scheme = cx.hdr."qorus-proxy-external-scheme") {
            scheme = req_scheme;
        } else {
            scheme = sprintf("http%s", cx.ssl ? "s" : "");
        }
        string url_pfx = sprintf("%s://%s/", scheme, cx.hdr.host);

        return {
            "group": handler.getGroup(),
            "type": stype,
            "service": sname,
            "menuname": handler.getMenuName(),
            "desc": desc,
            "url": url_pfx + handler.url + "/",
            "url_name": name,
        };
    }
}
