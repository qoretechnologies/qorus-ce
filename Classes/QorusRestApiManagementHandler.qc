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

public namespace OMQ {
class QorusRestApiManagementHandler inherits AbstractServiceRestHandler {
    private {
        LocalQorusService service;
        int leading_path_components;

        bool cors_enable;
        list<string> cors_methods;
        list<string> cors_headers;
        int cors_max_age;
        bool cors_credentials;

        # REST endpoint map; method -> path -> {call_type, name}
        hash<string, hash<string, hash<auto>>> rest_endpoint_map;

        # REST wildcard endpoint hash method -> regex path -> {call_type, name}
        hash<string, hash<string, hash<auto>>> rest_wildcard_endpoint_map;
    }

    constructor(LocalQorusService service, hash<string, hash<auto>> endpoint_map, hash<auto> api_profile_options,
            *RestSchemaValidator::AbstractRestSchemaValidator validator)
            : AbstractServiceRestHandler(api_profile_options."root-uri", False,
                QorusRestApiManagementHandler::getAuthenticator(api_profile_options), validator) {
        self.service := service;
        # setup REST endpoint map
        list<string> endpoint_list;
        foreach hash<auto> i in (endpoint_map.pairIterator()) {
            string endpoint = i.key;
            endpoint_list += endpoint;
            # strip leading slash
            endpoint =~ s/^\/*//;
            # remove method name from the end
            int j = endpoint.rfind("/");
            if (j == -1) {
                throw "SERVICE-ERROR", sprintf("REST endpoint %y has no trailing method name", i.key);
            }
            string method = endpoint[(j + 1)..].lwr();
            splice endpoint, j;
            if (endpoint =~ /\*/) {
                endpoint =~ s/\./\\./g;
                endpoint =~ s/\*/.*/g;
                rest_wildcard_endpoint_map{method}{"^" + endpoint + "$"} = i.value;
            } else {
                rest_endpoint_map{method}{endpoint} = i.value;
            }
        }

        cors_enable = api_profile_options."cors-enable" ?? False;
        cors_methods = cast<list<string>>(api_profile_options."cors-methods") ?? ();
        cors_headers = cast<list<string>>(api_profile_options."cors-headers") ?? ();
        cors_credentials = api_profile_options."cors-credentials" ?? False;
        cors_max_age = api_profile_options."cors-max-age" ?? 0;

        if (cors_enable) {
            ServiceApi::logInfo("REST API manager CORS config: enabled: %y methods: %y headers: %y credentials: %y "
                "max-age: %d", cors_enable, cors_methods, cors_headers, cors_credentials, cors_max_age);
        } else {
            ServiceApi::logInfo("REST API manager CORS config: enabled: %y", cors_enable);
        }
        ServiceApi::logInfo("REST API manager mounted on %y serving endpoints: %y", url, endpoint_list);

        # remove any leading slashes from the path
        url =~ s/^\/*//;
        # calculate leading path components
        leading_path_components = url.split("/").size();
    }

    #! Returns a response to the OPTIONS method if CORS is enabled, otherwise returns an error
    hash<HttpHandlerResponseInfo> options(hash<auto> cx, *hash<auto> ah) {
        # check if CORS is enabled
        *hash<auto> hdr = getCorsResponseHeaders(cx);
        if (hdr) {
            # return a CORS response
            return RestHandler::makeResponse(200, NOTHING, hdr);
        }

        # see if alternate methods would work
        list<string> hl = map $1.key, RestHandler::Methods.pairIterator(),
            $1.key != "OPTIONS" && self.hasCallableMethod($1.value + cx.rest_method);
        # if we have alternate methods, return an appropriate 405 Method Not Allowed error
        if (hl) {
            string desc = sprintf("HTTP method %s is unimplemented in REST class %y (%s)", cx.hdr.method, name(),
                self.className());
            if (cx.orig_method)
                desc += sprintf(" REST method %y", cx.orig_method);
            string ml = foldl $1 + "," + $2, hl;
            desc += sprintf(", available methods: %s", ml);
            return cast<hash<HttpHandlerResponseInfo>>(
                HttpServer::AbstractHttpRequestHandler::makeResponse({"Allow": ml}, 405, desc)
            );
        }

        # otherwise return a 501 Not Implemented response
        return cast<hash<HttpHandlerResponseInfo>>(RestHandler::make501("REST class %y (%s) does not "
            "implement method %y", name(), self.className(), "options"));
    }

    #! Dispatches the request and returns the response
    private hash<HttpHandlerResponseInfo> dispatchRequest(HttpListenerInterface listener, Socket s,
            *list<string> class_list, string method_name, string path, hash<auto> cx, *hash<auto> args) {
        # see if we have an endpoint match
        string simple_path = path;
        simple_path =~ s/\?.*//;

        # issue #3965: REST method "delete" arrives as "del" and must be mapped back to "delete" here
        if (method_name == "del") {
            method_name = "delete";
        }
        *hash<auto> api = rest_endpoint_map{method_name}{simple_path};
        if (!api) {
            # check for wildcard match
            foreach hash<auto> i in (rest_wildcard_endpoint_map{method_name}.pairIterator()) {
                if (regex(simple_path, i.key)) {
                    api = i.value;
                    break;
                }
            }
        }
        if (api) {
            UserApi::logInfo("dispatching REST API \"%s %s\" with %s %y", method_name.upr(), simple_path, api.call_type,
                api.name);
            UserApi::logDebug("REST API %s %s args: %y", api.call_type, api.name, args);
            return dispatchApiRequest(method_name, simple_path, api, args);
        }

        QDBG_LOG("API ENDPOINT NO MATCH: method: %y path: %y endpoints: %y wildcard_endpoints: %y", method_name,
            simple_path,
            (map {$1.key: (map {$1: True}, keys $1.value)}, rest_endpoint_map.pairIterator()),
            (map {$1.key: (map {$1: True}, keys $1.value)}, rest_wildcard_endpoint_map.pairIterator()),
            );

        return AbstractServiceRestHandler::dispatchRequest(listener, s, class_list, method_name, path, cx, args);
    }

    #! Dispatches the request and returns the response
    private hash<HttpHandlerResponseInfo> dispatchApiRequest(string method_name, string simple_path, hash<auto> api,
            *hash<auto> args) {
        auto rv;
        switch (api.call_type) {
            case "method":
                rv = services.callMethodExtern(service.type, service.name, api.name, args, NOTHING, True);
                break;
            case "fsm":
                rv = QorusFsmHandler::executeFsm(api.name, args);
                break;
            default:
                throw "API-ERROR", sprintf("REST API endpoint %s %s: unknown call_type %y", method_name,
                    simple_path, api.call_type);
        }
        return <HttpHandlerResponseInfo>{
            "code": api.success_code ?? 200,
            "body": rv,
        };
    }

    #! Returns CORS headers for the request if CORS is enabled, otherwise returns @ref NOTHING
    *hash<auto> getCorsResponseHeaders(hash<auto> cx) {
        if (cors_enable) {
            # IMPLEMENT-ME: check origin
            return getCorsResponseHeadersIntern(cx);
        }
    }

    #! Returns CORS headers for the request; assumes CORS is enabled and the origin is allowed
    hash<auto> getCorsResponseHeadersIntern(hash<auto> cx) {
        hash<auto> hdr = {
            "Access-Control-Allow-Methods": (foldl $1 + ", " + $2, cors_methods),
            "Access-Control-Max-Age": cors_max_age.toString(),
            "Access-Control-Allow-Origin": cx.hdr.origin && cx.hdr.authorization ? cx.hdr.origin : "*",
            "Vary": "Origin",
        };
        if (cors_headers) {
            hdr."Access-Control-Allow-Headers" = (foldl $1 + ", " + $2, cors_headers);
        }
        if (cors_credentials) {
            hdr."Access-Control-Allow-Credentials" = "true";
        }
        return hdr;
    }

    removeRootPath(reference<string> path) {
        if (leading_path_components) {
            list<string> l = path.split("/");
            int start = 1;
            if (path !~ /^\//) {
                --start;
            }
            # leave only any URI query in the path
            if (leading_path_components == l.size()) {
                path =~ s/^[^\?]*//;
            } else {
                splice l, start, leading_path_components;
                path = l.join("/");
            }
        }
    }

    string name() {
        return "/";
    }

    static AbstractAuthenticator getAuthenticator(hash<auto> api_profile_options) {
        switch (api_profile_options."auth-name") {
            case AUTH_PERMISSIVE: return new PermissiveAuthenticator();
            case AUTH_DEFAULT: return new DefaultQorusRBACAuthenticator();
            case AUTH_DEFAULT_BASIC: return new DefaultQorusRBACBasicAuthenticator();
            case AUTH_COOKIE:
                return new QorusCookieAuthenticator(
                    api_profile_options."auth-cookie",
                    api_profile_options."auth-redirect"
                );
        }

        throw "UNKNOWN-AUTHENTICATOR", sprintf("authenticator %y is unknown; expecting one of %y",
            api_profile_options."auth-name", keys AUTH_LABEL_VALUES);
    }
}
}

