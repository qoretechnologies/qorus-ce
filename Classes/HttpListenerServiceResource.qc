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

class OMQ::HttpListenerServiceResource inherits OMQ::AbstractHttpServiceResourceBase {
    public {
        # HTTP listener ID
        int id;
        # listener hash
        hash lh;
        # wildcard bind
        *bool wc_bind;
        # base URL for listener
        string url;
        # service ID as a string
        string serviceid;
        # service listener name
        string listener_name;
        # stopped flag
        bool stopped;

        # handlers
        list<AbstractHttpRequestHandler> handlers;
    }

    constructor(softstring serviceid, string listener_name, string name, int rsid, int n_id, string desc,
            *softlist<auto> content_type, *softlist<auto> special_headers,
            *list<AbstractHttpRequestHandler> n_handlers)
            : OMQ::AbstractHttpServiceResourceBase(name, desc, content_type, special_headers) {
        self.serviceid = serviceid;
        self.listener_name = listener_name;
        if (n_handlers) {
            handlers = n_handlers;
        }

        id = n_id;
        lh = Qorus.httpServer.getListenerInfo(id);

        # see if we're listening on a wildcard
        int p = lh.bind.rfind(":");
        string bind_str = lh.bind;
        if (p != -1) {
            # issue #2187: wildcard binds are with address 0.0.0.0 | :: | [::]
            string addr = bind_str.substr(0, p);
            if (addr == "0.0.0.0" || addr == "::" || addr == "[::]") {
                wc_bind = True;
            }

            # issue #2187: make sure the URL reflects the correct port if the bind port was 0
            string bind_port = bind_str.substr(p + 1);
            if (bind_port == "0" && lh.port) {
                splice bind_str, p + 1, bind_port.length(), lh.port.toString();
            }
        }
        # issue #2187: make sure the protocol is reflected correctly in the URL
        url = http_get_url_from_bind("http" + (lh.ssl ? "s" : "") + "://" + bind_str, Qorus.getLocalAddress());
    }

    string getType() {
        return "HttpListener";
    }

    addHandlers(list<AbstractHttpRequestHandler> n_handlers) {
        handlers += n_handlers;
    }

    synchronized private bool disableImpl() {
        Qorus.httpServer.stopListenerIDNoWait(id);
        return False;
    }

    synchronized stop(*bool aborted) {
        #QDBG_LOG("HttpListenerServiceResource::stop() self: %s %y: ln: %y (%d stopped: %y)", self.uniqueHash(), name, listener_name, id, stopped);
        # make sure ServiceManager::deregisterListener() is only called once
        if (stopped) {
            return;
        }
        stopped = True;

        if (handlers) {
            foreach AbstractHttpRequestHandler handler in (handlers) {
                try {
                    if (Qorus.httpServer.removeHandlerFromListenerID(id, handler)) {
                        # listener was already stopped therefore we don't need to remove any more handlers
                        break;
                    }
                } catch (hash<ExceptionInfo> ex) {
                    # ignore "no listener" errors; the listener has already been stopped
                    if (ex.err == "INVALID-LISTENER-ERROR") {
                        break;
                    }
                    rethrow;
                }
            }

            handlers = new list<AbstractHttpRequestHandler>(); # clear the handler list
        }

        services.deregisterListener(id, listener_name, serviceid);
    }

    hash<auto> getInfo(*hash<auto> cx) {
        return OMQ::AbstractHttpServiceResourceBase::getInfo(cx) + lh + {
            "url": cx && wc_bind ? fixUrl(url, cx) : url,
        };
    }

    string fixUrl(string url, hash<auto> cx) {
        cx.hdr.port = lh.port;
        cx.ssl = lh.ssl;
        return qorus_get_url(cx, url);
    }
}
