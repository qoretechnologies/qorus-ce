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

class OMQ::ServiceResources {
    public {
    }

    private {
    }

    private:internal {
        # hash of file resources
        hash<string, hash<auto>> fh;

        # resource info list; each element is a hash with "name" and "type" keys
        list<hash<auto>> resource_list = ();

        # template manager
        ServiceTemplateManager tm;

        # log closure/call ref
        code log;
    }

    setLog(code log) {
        self.log = log;
    }

    setup(int serviceid, *list<auto> rl, bool sys, *int po) {
        tm = new ServiceTemplateManager(sys, po);

        # load service file resources
        foreach hash<auto> fr in (rl) {
            *hash<auto> rq = AbstractQorusService::getServiceResource(serviceid, fr.name);
            if (!rq) {
                throw "SERVICE-FILE-RESOURCE-ERROR", sprintf("required resource %y not found in the database", fr.name);
            }

            # if it's a text resource, then convert to a string with UTF-8 encoding
            if (rq.resource_type != "B") {
                rq.body = rq.body.toString();
            } else if (!rq.body) {
                rq.body = binary();
            }

            string ct;
            if (rq.resource_type == "N" || rq.resource_type == "B") {
                fh{fr.name} = {
                    "body": rq.body,
                    "ct": ct = get_mime_type_from_ext(fr.name),
                };
            } else {
                *string ext = (fr.name =~ x/\.([a-z0-9]+)$/i)[0];
                if (ext[0] == "q") {
                    ext = ext.substr(1);
                }
                ct = (ext && (ext = MimeTypes{ext.lwr()})) ? ext : MimeTypeUnknown;
                tm.add(fr.name, rq.body, ct);
            }
            log("loaded file resource %y (%s): %d bytes (%s)", fr.name, rq.resource_type, rq.body.size(), ct);
            #QDBG_LOG("ServiceResources::setup() %y: %s", rq.body.encoding(), rq.body);

            resource_list += {
                "name": fr.name,
                "type": rq.resource_type,
            };
        }
    }

    hash<auto> getResource(string n, hash<auto> ctx, int code = 200, *hash<auto> hdr) {
        if (fh{n}) {
            return {
                "code": code,
                "body": fh{n}.body,
                "hdr": hdr + {"Content-Type": fh{n}.ct},
            };
        }
        *hash<auto> h = tm.tryRender(n, ctx, code, hdr);
        if (h) {
            return h;
        }
        throw "SERVICE-FILE-RESOURCE-ERROR", sprintf("resource %y does not exist; known resources: %y", n, getResourceList());
    }

    *hash<auto> tryGetResource(string n, hash<auto> ctx, int code = 200, *hash<auto> hdr) {
        if (fh{n}) {
            return {
                "code": code,
                "body": fh{n}.body,
                "hdr": hdr + {"Content-Type": fh{n}.ct},
            };
        }
        return tm.tryRender(n, ctx, code, hdr);
    }

    data getResourceData(string n, *hash<auto> ctx) {
        if (fh{n}) {
            #QDBG_LOG("ServiceResources::getResourceData(%y) %s: %y", n, fh{n}.body.typeCode() == NT_STRING ? fh{n}.body.encoding() : "binary", fh{n}.body);
            return fh{n}.body;
        }
        *hash<auto> h = tm.tryRender(n, ctx ? ctx : {}, 200);
        if (h) {
            return h.body;
        }
        throw "SERVICE-FILE-RESOURCE-ERROR", sprintf("resource %y does not exist; known resources: %y", n, getResourceList());
    }

    WebService getResourceWsdl(string n, *hash<auto> ctx) {
        data wsdl_src = getResourceData(n, ctx);
        if (wsdl_src.typeCode() == NT_BINARY) {
            throw "SERVICE-WSDL-RESOURCE-ERROR", sprintf("resource %y is a binary resource; only text resources can be parsed as WSDL sources", n);
        }
        return new WebService(wsdl_src, ("try_import": \getResourceData()));
    }

    *data tryGetResourceData(string n, *hash<auto> ctx) {
        if (fh{n}) {
            return fh{n}.body;
        }
        return tm.tryRender(n, ctx ? ctx : {}, 200).body;
    }

    *hash<string, bool> getResourceHash() {
        *hash<string, bool> rv0 = map {$1: True}, keys fh;
        return rv0 + tm.getTemplateHash();
    }

    list<string> getResourceList() {
        list<string> rv = tm.getTemplateList();
        return fh ?
            (keys fh + rv)
            : rv;
    }

    list<hash<auto>> getResourceHashList() {
        return resource_list;
    }

    bool hasResource(string n) {
        if (fh{n}) {
            return True;
        }
        return tm.hasTemplate(n);
    }

    checkDefaultResource(string name) {
        if (fh{name}) {
            return;
        }
        if (!tm.hasTemplate(name)) {
            throw "RESOURCE-ERROR", sprintf("resource %y does not exist; currently available resources: %y", name, getResourceList());
        }
    }

    hash<HttpResponseInfo> renderTemplate(string n, *hash<auto> ctx) {
        return tm.render(n, ctx);
    }

    *hash<HttpResponseInfo> tryRenderTemplate(string n, hash<auto> cx) {
        return tm.tryRender(n, cx);
    }

    *hash<string, bool> getTemplateHash() {
        return tm.getTemplateHash();
    }

    list<string> getTemplateList() {
        return tm.getTemplateList();
    }

    bool hasTemplate(string n) {
        return tm.hasTemplate(n);
    }
}
