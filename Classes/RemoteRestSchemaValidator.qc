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

class OMQ::RemoteRestSchemaValidator inherits RestSchemaValidator::AbstractRestSchemaValidator, RemoteHandlerBase {
    constructor(RemoteQorusService svc, string rid) : RemoteHandlerBase(svc, rid) {
        #QDBG_LOG("RemoteRestSchemaValidator::constructor() svc: %s %s rid: %y", svc.type, svc.name, rid);
    }

    auto methodGate(string m) {
        return svc.doRemoteRestValidatorRequest(rid, m, argv);
    }

    string getHashImpl() {
        return svc.doRemoteRestValidatorRequest(rid, "getHashImpl");
    }

    string getTargetUrlImpl() {
        return svc.doRemoteRestValidatorRequest(rid, "getTargetUrlImpl");
    }

    hash<RestRequestClientInfo> processRequestImpl(string method, string path, auto body, *hash headers,
            *softlist<string> content_types) {
        return cast<hash<RestRequestClientInfo>>(svc.doRemoteRestValidatorRequest(rid, "processRequestImpl",
            (method, path, body, headers, content_types)));
    }

    hash<RestRequestServerInfo> parseRequestImpl(string method, string path, *data http_body,
            reference<hash> headers) {
        hash<auto> h = svc.doRemoteRestValidatorRequest(rid, "parseRequestImplExtern",
            (method, path, http_body, headers));
        headers = remove h.headers;
        return cast<hash<RestRequestServerInfo>>(h);
    }

    hash<HttpResponseInfo> processResponseImpl(string method, string path, int code, any response_body, *hash headers,
            *softlist<string> content_types) {
        return cast<hash<HttpResponseInfo>>(svc.doRemoteRestValidatorRequest(rid, "processResponseImpl",
            (method, path, code, response_body, headers, content_types)));
    }

    hash<RestResponseClientInfo> parseResponseImpl(string method, string path, int code, *data response_body,
            hash hdr) {
        return cast<hash<RestResponseClientInfo>>(svc.doRemoteRestValidatorRequest(rid, "parseResponseImpl",
            (method, path, code, response_body, hdr)));
    }

    hash<string, list<string>> getPathOperationHashImpl() {
        return cast<hash<string, list<string>>>(svc.doRemoteRestValidatorRequest(rid, "getPathOperationHashImpl"));
    }

    string getBasePathImpl() {
        return svc.doRemoteRestValidatorRequest(rid, "getBasePathImpl");
    }

    setBasePathImpl(string basePath) {
        svc.doRemoteRestValidatorRequest(rid, "setBasePathImpl", basePath);
    }

    hash<RestQoreExampleCodeInfo> getQoreExampleRequestImpl(string method, string path) {
        return cast<hash<RestQoreExampleCodeInfo>>(svc.doRemoteRestValidatorRequest(rid, "getQoreExampleRequestImpl",
            (method, path)));
    }

    hash<RestExampleRequestInfo> getExampleRequestImpl(string method, string path, *softlist<string> content_types) {
        return cast<hash<RestExampleRequestInfo>>(svc.doRemoteRestValidatorRequest(rid, "getExampleRequestImpl",
            (method, path, content_types)));
    }

    hash<RestQoreExampleCodeInfo> getQoreExampleResponseImpl(string method, string path, int code) {
        return cast<hash<RestQoreExampleCodeInfo>>(svc.doRemoteRestValidatorRequest(rid, "getQoreExampleResponseImpl",
            (method, path, code)));
    }

    hash<RestExampleResponseInfo> getExampleResponseImpl(string method, string path, int code,
            *softlist<string> content_types) {
        return cast<hash<RestExampleResponseInfo>>(svc.doRemoteRestValidatorRequest(rid, "getExampleResponseImpl",
            (method, path, code, content_types)));
    }

    private setTimeZoneLocaleImpl(*TimeZone tz) {
        svc.doRemoteRestValidatorRequest(rid, "setTimeZoneLocale", (tz,));
    }

    private *TimeZone getTimeZoneLocaleImpl() {
        return svc.doRemoteRestValidatorRequest(rid, "getTimeZoneLocale");
    }
}
