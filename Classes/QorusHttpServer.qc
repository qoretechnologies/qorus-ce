# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

class OMQ::QorusHttpServer inherits HttpServer::HttpServer {
    public {
        #! CORS options
        static bool cors_enable = QorusSystemOptionDefaults{"cors-enable"};
        static *softlist<string> cors_accept_origin = QorusSystemOptionDefaults{"cors-accept-origin"};
        static *string cors_allow_methods = foldl $1 + ", " + $2, QorusSystemOptionDefaults{"cors-allow-methods"};
        static string cors_max_age = QorusSystemOptionDefaults{"cors-max-age"}.toString();
        static *string cors_allow_headers = foldl $1 + ", " + $2, QorusSystemOptionDefaults{"cors-allow-headers"};
        static bool cors_allow_credentials = QorusSystemOptionDefaults{"cors-allow-credentials"};

        #! Derived / calculated CORS options
        static bool cors_accept_all_origins = True;
        static hash<string, bool> cors_origin_map;

        # server name as reported in HTTP response headers
        const QorusServerName = sprintf("Qorus-HTTP-Server/%s", HttpServer::Version);

        const HttpOptions = {
            "cert": True,
            "key": True,
            "password": True,
        };
    }

    private {
        # hash of system listeners keyed by listener id
        hash<string, hash<auto>> linfo;

        # flag signifying that all system listeners have been started
        bool started = False;
    }

    constructor(*bool dbg) : HttpServer(<HttpServerOptionInfo>{
        "name": QorusServerName,
        "debug": dbg,
    }) {
        # initialize logger with params from db. qmm must be already inited
        updateLogger(Qorus.qmm.lookupLogger("HTTP").params);
    }

    updateLogger(*hash<LoggerParams> params) {
        params = substituteLogFilename(params, LoggerController::getLoggerSubs("HTTP"));
        logger = createLogger(params);
        # WebDAV handler shares the same logger
        Qorus.webDavHandler.setLogger(logger);
        # REST handler shares the same logger
        Qorus.restHandler.setLogger(logger);
        Qorus.logDebug("HTTP logger params: %N", params);
        logDebug("HTTP logger has been updated with params: %y", params);
    }

    #! To call a listener's stop callback
    callListenerStopCallback(code stopc, string name, hash<auto> socket_info) {
        try {
            call_function(stopc, name);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "OBJECT-ALREADY-DELETED") {
                logError("%y (%s): error calling stop notification closure: %s: %s: %s", name, socket_info.desc,
                    get_ex_pos(ex), ex.err, ex.desc);
            }
        }
    }

    log(string fmt) {
        logArgs(Logger::LoggerLevel::INFO, fmt, argv);
    }

    logArgs(int lvl, string msg, auto args) {
        string fmsg = vsprintf(msg, args);
        logger.log(lvl, "%s", fmsg, new LoggerEventParameter(\Qorus.eventLog.logEvent(), "http",
            sprintf("%s T%d [%s]: ", log_now(), gettid(), LoggerLevel::getLevel(lvl).getStr()) + fmsg + "\n"));
    }

    logFatal(string msg) {
        logArgs(Logger::LoggerLevel::FATAL, msg, argv);
    }

    logError(string msg) {
        logArgs(Logger::LoggerLevel::ERROR, msg, argv);
    }

    logInfo(string msg) {
        logArgs(Logger::LoggerLevel::INFO, msg, argv);
    }

    logDebug(string msg) {
        logArgs(Logger::LoggerLevel::DEBUG, msg, argv);
    }

    rotateLogFiles() {
        foreach auto appender in (logger.getAppenders()) {
            if (appender instanceof AbstractLoggerAppenderFileRotate) {
                cast<AbstractLoggerAppenderFileRotate>(appender).rotate();
            }
        }
    }

    startup() {
        softlist http_servers = Qorus.options.get("http-server");
        softlist http_ssl_servers = Qorus.options.get("http-secure-server");
        if (!http_servers && !http_ssl_servers) {
            logFatal("no 'http-server' or 'http-secure-server' value is set in the options file");
            throw "QORUS-OPTION-ERROR", "no 'http-server' or 'http-secure-server' value is set in the options file";
        }

        map doListener($1.toString()), http_servers;
        map doListener($1.toString(), True), http_ssl_servers;

        started = True;
    }

    private doListener(string hs, bool ssl = False) {
        try {
            trim hs;

            hash<UrlInfo> url;
            string http_sock;

            hash hopt;
            if (ssl && (*string ho = (hs =~ x/{([^}]+)}/)[0])) {
                hs = replace(hs, "{" + ho + "}", "");
                foreach string opt in (ho.split(";")) {
                    (*string k, *string v) = (opt =~ x/([^=]+)=(.*)/);
                    if (!k) {
                        logFatal("invalid HTTPS option: %y; format is \"option=value\"; known options: %y (hs: %y ho: %y)", opt,
                            keys HttpOptions, hs, ho);
                        throw True;
                    }
                    if (!HttpOptions{k}) {
                        logFatal("unknown HTTPS option %y in %y; known options: %y", k, opt, keys HttpOptions);
                        throw True;
                    }

                    hopt{k} = OMQ::substitute_env_vars(v);
                }
            }

            # check if URL is just a port number
            if (int(hs) == hs)
                http_sock = hs;
            else {
                url = parse_url(hs);
                #printf("URL: %y\n", url);
                if (url.username || url.password) {
                    logFatal("illegal username and/or password supplied in http server url: %y", hs);
                    throw True;
                }
                if (url.path && url.host) {
                    logFatal("illegal path supplied in http server url: %y", hs);
                    throw True;
                }

                if (url.path || url.protocol == "file") {
                    if (url.port) {
                        logFatal("illegal HTTP server specification, protocol 'file' indicates UNIX domain socket, "
                            "but port %d also supplied", url.port);
                        throw True;
                    }
                    delete url.protocol;
                    if (!url.host && url.path)
                        http_sock = url.path;
                    else
                        http_sock = url.host;
                } else {
                    if (url.port)
                        http_sock = sprintf("%s:%d", url.host, url.port);
                    else if (!strlen(url.host) && exists url.path)
                        http_sock = url.path;
                    else
                        http_sock = url.host;
                }
                if (url.protocol == "http" && ssl) {
                    logFatal("'http' specified in http-secure-server option in %y", hs);
                    throw True;
                }
            }

            if (ssl || url.protocol == "https") {
                *string cert = hopt.cert ? hopt.cert : Qorus.options.get("http-secure-certificate");
                *string key  = hopt.key ? hopt.key : Qorus.options.get("http-secure-private-key");
                *string pwd  = hopt.password ? hopt.password : Qorus.options.get("http-secure-private-key-password");
                if (!cert) {
                    string error = sprintf("'http-secure-certificate' is not set for secure server %y and there is no 'cert' "
                        "option given", hs);
                    logFatal("%s", error);
                    throw "HTTP-STARTUP-ERROR", error;
                }

                try {
                    hash<HttpListenerOptionInfo> info = http_get_listener_options_from_bind(http_sock, cert, key,
                        pwd);
                    info.name = "qorus";
                    list<auto> l = addListeners(info);
                    foreach hash<auto> h in (l) {
                        logInfo("TID %d: HTTP secure listener %s started on %s", getListenerTID(h.id), hs,
                            h.address_desc);
                        linfo{h.id} = h;
                    }
                } catch (hash<ExceptionInfo> ex) {
                    logFatal("Unable to start secure HTTP listener on %y (%s: %s), aborting", hs, ex.err, ex.desc);
                    rethrow;
                }
            } else if (!exists url.protocol || url.protocol == "http") {
                try {
                    #QDBG_LOG("about to call addListeners(): %y", http_sock);
                    list<auto> l = addListeners(http_sock, <HttpListenerOptionInfo>{"name": "qorus"});
                    foreach hash<auto> h in (l) {
                        logInfo("TID %d: HTTP listener %s started on %s", getListenerTID(h.id), hs, h.address_desc);
                        linfo{h.id} = h;
                    }
                } catch (hash<ExceptionInfo> ex) {
                    logFatal("Unable to start HTTP listener on %y (%s: %s), aborting", hs, ex.err, ex.desc);
                    rethrow;
                }
            } else {
                string error = sprintf("Unable to start HTTP listener with unknown protocol %y (%y), aborting",
                    url.protocol, hs);
                logFatal("%s", error);
                throw "HTTP-STARTUP-ERROR", error;
            }
        } catch (hash<ExceptionInfo> ex) {
            # issue #3523: allow Qorus to start if the UNIX domain socket fails to bind
            if (hs == (*string unix_socket_path = Qorus.getUnixSocketPath()) && ex.arg == EADDRINUSE) {
                Qorus.sendStartupMsg("WARNING: cannot bind HTTP server to UNIX domain path %y; starting without "
                    "local socket listener", unix_socket_path);
            } else {
                rethrow;
            }
        }
    }

    # only called from listeners; do not call externally
    listenerStarted(int id, hash<auto> sinfo) {
        # only report the startup status of system listeners
        if (!started || linfo{id}) {
            string label = sinfo.label ?? sprintf("HTTP%s", sinfo.ssl ? "S" : "");
            Qorus.sendStartupMsg("%s listener %d started on %s", label, id, sinfo.desc);
        }
        HttpServer::listenerStarted(id, sinfo);
    }

    static corsUpdateOption(string opt, auto value) {
        switch (opt) {
            case "cors-enable":
                cors_enable = value;
                break;

            case "cors-allow-origin": {
                cors_accept_origin = value;
                cors_accept_all_origins = False;
                foreach string origin in (cors_accept_origin) {
                    if (origin == "*") {
                        cors_accept_all_origins = True;
                    }
                    cors_origin_map{origin} = True;
                }
                break;
            }

            case "cors-allow-methods":
                cors_allow_methods = foldl $1 + ", " + $2, value;
                break;

            case "cors-max-age":
                cors_max_age = value.toString();
                break;

            case "cors-allow-headers":
                cors_allow_headers = foldl $1 + ", " + $2, value;
                break;

            case "cors-allow-credentials":
                cors_allow_credentials = value;
                break;
        }
    }

    static bool corsOriginOk(hash<auto> cx, *reference<bool> explicit_match) {
        if (!cors_enable) {
            return False;
        }
        if (cors_accept_all_origins) {
            return True;
        }
        if (cors_origin_map{cx.hdr.origin}) {
            explicit_match = True;
            return True;
        }
        return False;
    }

    static *hash<auto> getCorsResponseHeaders(hash<auto> cx) {
        bool explicit_match;
        if (!QorusHttpServer::corsOriginOk(cx, \explicit_match)) {
            return;
        }
        return QorusHttpServer::getCorsResponseHeadersIntern(cx, explicit_match);
    }

    static private hash<auto> getCorsResponseHeadersIntern(hash<auto> cx, *bool explicit_match) {
        hash<auto> rv;
        # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Access-Control-Allow-Origin
        # if the server supports clients from multiple origins, it must return the origin for the specific client
        # making the request
        if (cx.hdr.origin && !cors_accept_all_origins) {
            rv = {
                "Access-Control-Allow-Origin": cx.hdr.origin,
                "Vary": "Origin",
            };
        } else {
            rv = {
                "Access-Control-Allow-Origin": "*",
            };
        }
        # return other headers for preflight (OPTIONS) requests
        if (cx.hdr.method == "OPTIONS") {
            rv += {
                "Access-Control-Allow-Methods": cors_allow_methods,
                "Access-Control-Max-Age": cors_max_age,
            };
            if (cors_allow_headers) {
                rv."Access-Control-Allow-Headers" = cors_allow_headers;
            }
        }
        if (cors_allow_credentials) {
            rv."Access-Control-Allow-Credentials" = "true";
        }
        QDBG_LOG("hdr: %y accept_all: %y rv: %y", cx.hdr, cors_accept_all_origins, rv);
        return rv;
    }

    #! handles OPTIONS requests
    static hash<HttpResponseInfo> handleOptions(hash<auto> cx) {
        # check if CORS is enabled
        *hash<auto> hdr = QorusHttpServer::getCorsResponseHeaders(cx);
        if (hdr) {
            # return a CORS response
            return AbstractHttpRequestHandler::makeResponse(200, NOTHING, hdr);
        }

        # otherwise return a 501 Not Implemented response
        return AbstractHttpRequestHandler::makeResponse(501, "OPTIONS not implemented");
    }
}
