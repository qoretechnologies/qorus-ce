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

/** @page rest_api_page_public Qorus Public REST API

    @tableofcontents

    @section rest_api_public_overview Qorus Public REST API Overview

    The APIs documented here do not require any authentication to access.

    @par Swagger Schema
    A static version can be downloaded here: <a href="qorus-rest-api-public.yaml">qorus-rest-api-public.yaml</a>; a
    dynamic version is available from every Qorus instance without authentication at URI paths
    <tt>/schema/qorus-rest-api-public.yaml</tt> and <tt>/schema/qorus-rest-api-public.json</tt> (ex: if Qorus is
    available on <tt>https://localhost:8011</tt>, then the dynamic schema can be retrieved from
    <tt>https://localhost:8011/schema/qorus-rest-api-public.yaml</tt> and
    <tt>https://localhost:8011/schema/qorus-rest-api-public.json</tt>).
*/

/** @REST /public/login

    This URI path implements token-based user authentication.
*/
class LoginRestClass inherits QorusRestClass {
    string name() {
        return "login";
    }

    /** @REST POST

        @SCHEMA
        @summary Noop in the Community Edition

        @desc Noop in the Community Edition

        @params
        - user (string): The username to log in
        - pass (string): The user's password

        @return (hash QorusTokenInfo): Authentication info
        - token (string): Always returns an empty string in the Community Edition

        @error (400): invalid or missing arguments
        @ENDSCHEMA
    */
    hash<auto> post(hash<auto> cx, *hash<auto> ah) {
        switch (ah.user.typeCode()) {
            case NT_STRING: break;
            case NT_NOTHING:
                throw "LOGIN-ARG-ERROR", "missing \"user\" argument in call to PUT /api/login";
            default:
                throw "LOGIN-ARG-ERROR", sprintf("\"user\" argument is type %y (expecting %y)", ah.user.type(), Type::String);
        }
        switch (ah.pass.typeCode()) {
            case NT_STRING: break;
            case NT_NOTHING:
                throw "LOGIN-ARG-ERROR", "missing \"pass\" argument in call to PUT /api/login";
            default:
                throw "LOGIN-ARG-ERROR", sprintf("\"pass\" argument is type %y (expecting %y)", ah.user.type(), Type::String);
        }

        return RestHandler::makeResponse(200, {"token" : ""});
    }
}

/** @REST /public/info

    This URI path implements token-based user authentication.
*/
class InfoRestClass inherits QorusRestClass {
    string name() {
        return "info";
    }

    /** @REST GET

        @SCHEMA
        @summary Returns public information about the server

        @desc Returns public information about the server; this API does not require authentication.

        @return (hash QorusPublicInfo): information about the current Qorus instance
        - instance-key (string): Qorus instance identifier
        - omq-version (string): Qorus executable version
        - omq-build (string): Qorus executable git hash
        - qore-version (string): Qore library version
        - omq-schema (string): Qorus system schema info
        - noauth (bool): Always True in the Community Edition
        - edition (string): \c Community for Qorus Integration Engine(R) Community Edition
        - tz_region (string): the time zone region the server is running in
        - tz_utc_offset (int): the UTC offset in seconds east of UTC; negative numbers indicate west of UTC

        @since
        - %Qorus 3.1.0.p10 added the \c omq-schema key
        - %Qorus 6.0.0 added the \c edition key
        @ENDSCHEMA
     */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200,
            UserApi::getSystemInfo(){
                "instance-key",
                "omq-version",
                "omq-build",
                "qore-version",
                "omq-schema",
                "edition",
                "tz_region",
                "tz_utc_offset",
            } +
            {"noauth": True});
    }
}

class PublicWebAppHandler inherits QorusRestHandlerBase {
    public {}

    private {
        string path;
    }

    constructor(AbstractAuthenticator auth, string v_path) : QorusRestHandlerBase(auth) {
        path = v_path;
        addClass(new LoginRestClass());
        addClass(new InfoRestClass());
    }

    removeRootPath(reference v_path) {
        # remove root url from path
        v_path = regex_subst(v_path, path + "/", "");
    }

    logInfo(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, fmt, argv);
    }

    logError(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::ERROR, fmt, argv);
    }

    logDebug(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::DEBUG, fmt, argv);
    }

    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr,
            *data b) {
        if (hdr.method == "OPTIONS") {
            return QorusHttpServer::handleOptions(cx);
        }
        cx.sctx.listener = listener;
        hash<HttpResponseInfo> rv = RestHandler::handleRequest(listener, s, cx, hdr, b);
        if (!rv.hdr."Access-Control-Allow-Origin") {
            rv.hdr += QorusHttpServer::getCorsResponseHeaders(cx);
        }
        return rv;
    }
}

