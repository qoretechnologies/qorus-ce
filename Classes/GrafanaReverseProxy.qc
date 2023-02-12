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

#! reverse proxy for grafana access
/** This uses overlapped I/O for the grafana (client) and local (server) HTTP connections; each happens in its own
    thread.

    Also this reverse proxy handles chunked transfers directly; if grafana replies with chunked Transfer-Encoding,
    then the prroxy does as well and forwards each chunk as-is to the requestor.

    HTTP headers are left intact except the Host: header in the request; this reverse proxy also adds a Forwarded:
    header as per <a href="https://tools.ietf.org/html/rfc7239">RFC 7239</a>
*/
class GrafanaReverseProxy inherits AbstractHttpRequestHandler {
    private {
        #! grafana socket file location
        string socket_path = sprintf("%s%sqorus-%s-grafana.sock", tmp_location(), DirSep,
            Qorus.options.get("instance-key"));

        #! the socket URL used for the HTTPClient object
        string socket_url;
    }

    constructor(AbstractAuthenticator auth) : AbstractHttpRequestHandler(auth, True) {
        socket_url = sprintf("socket=%s", encode_url(socket_path, True));
        logInfo("grafana: redirecting requests to: %s", socket_url);
    }

    string getSocketUrl() {
        return socket_url;
    }

    # handles all requests
    private AbstractStreamRequest getStreamRequestImpl(HttpListenerInterface listener, Socket s, hash<auto> cx,
        hash<auto> hdr, *data body) {
        return new GrafanaStreamRequest(listener, self, s, cx, hdr, body);
    }

    static logInfo(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, fmt, argv);
    }

    static logError(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::ERROR, fmt, argv);
    }

    static logDebug(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::DEBUG, fmt, argv);
    }
}

class GrafanaStreamRequest inherits AbstractStreamRequest {
    private {
        #! for communication with grafana
        HTTPClient httpClient;
        #! if the grafana transfer is aborted
        bool aborted;
        #! for incoming request I/O
        Queue request_data_queue();
        #! for grafana I/O
        Queue grafana_data_queue();
        #! body sent flag
        bool body_sent;
        #! grafana header Counter
        Counter grafana_hdr_ctr(1);
        #! grafana header info received
        hash<auto> grafana_hdr_info;
    }

    constructor(HttpListenerInterface listener, AbstractHttpRequestHandler handler, Socket socket, hash<auto> cx,
        hash<auto> hdr, auto body) : AbstractStreamRequest(listener, handler, socket, cx, hdr, body) {
        # start communication with grafana
        string socket_url = cast<GrafanaReverseProxy>(handler).getSocketUrl();
        httpClient = new HTTPClient({
            "url": socket_url,
            "encoding_passthru": True,
            "error_passthru": True,
            "redirect_passthru": True,
        });
        logDebug("grafana: created HTTP client to URL %y for %s %s (body: %d bytes)", socket_url, hdr.method, hdr.path, body.size());

        int tid = background doGrafanaIo();
        logDebug("grafana: started grafana background I/O thread with TID %d", tid);
    }

    private doGrafanaIo() {
        on_exit logDebug("exiting grafana I/O thread");

        #QDBG_LOG("grafana: CX: %N", cx);
        #QDBG_LOG("grafana: HDR: %N", hdr);

        # create Forwarded: header according to https://tools.ietf.org/html/rfc7239
        string for_address = cx."peer-info".address;
        if (cx."peer-info".family = AF_INET6) {
            for_address = "[" + for_address + "]";
        }
        # the by token is supposed to be obfuscated
        # tokens cannot contain "[", "]", ":", so they are quoted
        string forwarded = sprintf("for=%y;proto=http%s;host=%y", for_address, cx.ssl ? "s" : "", hdr.host);
        if (hdr.forwarded.val()) {
            if (hdr.forwarded.typeCode() == NT_LIST) {
                forwarded += forwarded;
            } else {
                QDBG_ASSERT(hdr.forwarded.typeCode() == NT_STRING);
                forwarded = hdr.forwarded + "," + forwarded;
            }
        }
        hash<auto> nhdr = cx."header-info"."headers-raw" - ("Host", "host") + {
            "Forwarded": forwarded,
        };
        string path = hdr.path;
        path =~ s/^grafana\/?//;
        # NOTE: the grafana URI path must always be absolute
        path = "/" + path;
        logDebug("grafana rewrite URL: %s %s HTTP/1.1 -> %s nhdr: %N", hdr.method, hdr.path, path, nhdr);
        try {
            hash<auto> info;
            #on_exit QDBG_LOG("GRAFANA REQUEST INFO: %N", info);
            httpClient.sendWithCallbacks(\grafanaSendCallback(), \grafanaRecvCallback(), hdr.method, path ?? "/", nhdr, timeout_ms, False, \info);
        } catch (hash<ExceptionInfo> ex) {
            logError("%s", get_exception_string(ex));
        }
    }

    auto grafanaSendCallback() {
        if (body.val()) {
            if (body_sent) {
                QDBG_LOG("GrafanaStreamRequest::grafanaSendCallback() body sent; returning NOTHING");
                return;
            }
            body_sent = True;
            QDBG_LOG("GrafanaStreamRequest::grafanaSendCallback() returning: %d bytes", body.size());
            return body;
        }
%ifdef QorusDebugInternals
        auto rv = request_data_queue.get(timeout_ms);
        QDBG_LOG("GrafanaStreamRequest::grafanaSendCallback() returning from queue: %y", rv);
        return rv;
%else
        return request_data_queue.get(timeout_ms);
%endif
    }

    grafanaRecvCallback(hash<auto> msg) {
        QDBG_LOG("GrafanaStreamRequest::grafanaRecvCallback() msg: %N", msg + {"data": msg."data" ? msg."data".size() : 0});
        if (msg.send_aborted) {
            QDBG_LOG("GrafanaStreamRequest::grafanaRecvCallback() ABORTED");
            aborted = True;
            grafana_data_queue.push();
            if (grafana_hdr_ctr.getCount()) {
                grafana_hdr_ctr.dec();
            }
            return;
        }
        bool sent;
        if (exists msg."data") {
            QDBG_LOG("GrafanaStreamRequest::grafanaRecvCallback() DATA: %d bytes", msg."data".size());
            grafana_data_queue.push(msg."data");
            sent = True;
        }
        if (msg.info."response-headers-raw") {
            QDBG_LOG("GrafanaStreamRequest::grafanaRecvCallback() (info: %y) HDR: %N", exists grafana_hdr_info, msg.info."response-headers-raw");
            if (!grafana_hdr_info) {
                grafana_hdr_info = msg;
                grafana_hdr_ctr.dec();
            } else {
                grafana_data_queue.push(msg.info."response-headers-raw");
            }
            sent = True;
        }
        # end of data stream
        if (!sent) {
            QDBG_LOG("GrafanaStreamRequest::grafanaRecvCallback() END OF STREAM");
            grafana_data_queue.push();
        }
    }

    private nothing recvImpl(hash<auto> v) {
        QDBG_LOG("GrafanaStreamRequest::recvImpl() v: %y", v);
        bool sent;
        if (v."data".val()) {
            sent = True;
            request_data_queue.push(v."data");
        }
        if (v."hdr") {
            sent = True;
            request_data_queue.push(v."hdr");
        }
        if (!sent) {
            request_data_queue.push();
        }
    }

    private auto sendImpl() {
        auto rv = grafana_data_queue.get(timeout_ms);
%ifdef QorusDebugInternals
        if (rv.typeCode() == NT_HASH) {
            QDBG_LOG("GrafanaStreamRequest::sendImpl() returning from queue: %y", rv);
        } else {
            QDBG_LOG("GrafanaStreamRequest::sendImpl() returning from queue: %y", rv.size());
        }
%endif
        return rv;
    }

    private hash<HttpResponseInfo> getResponseHeaderMessageImpl() {
        grafana_hdr_ctr.waitForZero();
        if (!grafana_hdr_info) {
            QDBG_ASSERT(aborted);
            return <HttpResponseInfo>{
                "code": 500,
                "body": "an error occured communicating with the Grafana server",
            };
        }
        #QDBG_LOG("GrafanaStreamRequest::getResponseHeaderMessageImpl() grafana_hdr_info: %N", grafana_hdr_info);

        hash<auto> rhdr = grafana_hdr_info.info."response-headers-raw" - ("Server", "Content-Length");
        # process redirect messages
        if (grafana_hdr_info.hdr.status_code >= 300 && grafana_hdr_info.hdr.status_code < 400
            && grafana_hdr_info.hdr.status_code != 304 && rhdr.Location.val()) {
            rhdr.Location =~ s/^\///;
            rhdr.Location = "http" + (cx."socket-info".ssl ? "s" : "") + "://" + hdr.host + "/" + rhdr.Location;
            logDebug("grafana redirect: %y -> %y", hdr.path, rhdr.Location);
        }
        hash<HttpResponseInfo> rv = <HttpResponseInfo>{
            "code": grafana_hdr_info.hdr.status_code,
            "hdr": rhdr,
        };
        # return grafana body if available
        if (grafana_hdr_info.info."response-headers-raw"."Content-Length") {
            rv += {
                "body": grafana_data_queue.get(timeout_ms),
            };
        }
        logDebug("grafana response: %N", rv);

        return rv;
    }

    static logInfo(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, fmt, argv);
    }

    static logError(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::ERROR, fmt, argv);
    }

    static logDebug(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::DEBUG, fmt, argv);
    }
}
