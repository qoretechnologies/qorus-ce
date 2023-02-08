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

class QorusRemoteWebSocketConnection inherits public WebSocketConnection {
    private {
        #! WebSocket call context
        hash<auto> cx;

        #! process I/O thread read buffer size
        const ReadBufSize = 32 * 1024;

        #! process I/O thread read polling timeout
        const ReadPollTimeout = 100ms;

        #! text output command
        const QCM_TextOutput = "text-output";
    }

    constructor(QorusRemoteWebSocketHandler handler, hash<auto> cx) : WebSocketConnection(handler) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, "WebSocketConnection open for %y", cx.user);
        Qorus.httpServer.logArgs(LoggerLevel::DEBUG, "WebSocketConnection details: %y", cx);
        self.cx = cx;
    }

    gotMessage(string msg) {
        hash<auto> message = parse_yaml(msg);
        QDBG_LOG("gotMessage(): %y", message);

        if (message.args.typeCode() != NT_LIST) {
            message.args = exists message.args ? (message.args,) : ();
        }

        if (message.cmd.typeCode() != NT_STRING) {
            # any exception in this method will cause the WebSocket connection to be closed with the exception
            # message as the close reason
            throw "WEBSOCKET-ARG-ERROR", sprintf("missing or invalid 'cmd' arg; got type %y (%y); expecting "
                "\"string\"", message.cmd.type(), message.cmd);
        }

        string dir = "";
        string user_directory = "";
        string remote_dir = Qorus.getRemoteFileDir() + Qore::DirSep;
        Qorus.httpServer.logArgs(LoggerLevel::INFO, "remote request for %y using dir: %y", (message.cmd, remote_dir));

        if (message.cmd == "oload") {
            if (message.dir) {
                # issue #3715: convert windows dir separators to UNIX separators
                message.dir =~ s/\\/\//g;
                user_directory = remote_dir + message.dir;
            }

            message.args += message.opts;
            # make sure that all paths are relative
            foreach string file in (message.files) {
                file =~ s/^\/+//g;
                # issue #3715: convert windows dir separators to UNIX separators
                file =~ s/\\/\//g;
                message.args += file;
            }
            Qorus.httpServer.logArgs(LoggerLevel::INFO, "oload: %y", message);
        }

        hash<auto> opts = {};
        if (user_directory) {
            opts.cwd = user_directory;
            QDBG_LOG("gotMessage(): remote command opts: %y", opts);
        }

        Qorus.httpServer.logArgs(LoggerLevel::INFO, "executing remote command: %y %y", (message.cmd, message.args));
        try {
            Process proc(message.cmd, message.args, opts);
            int tid = background readIo(proc);
            Qorus.httpServer.logArgs(LoggerLevel::DEBUG, "remote command process I/O thread running in TID %d", tid);
        } catch (hash<ExceptionInfo> ex) {
            string errtxt = sprintf("%s: %s", ex.err, ex.desc);
            sendToClient(QCM_TextOutput, errtxt + "\n");
            if (Qorus.getDebugSystem()) {
                errtxt = get_exception_string(ex);
            }
            Qorus.httpServer.logArgs(LoggerLevel::ERROR, "remote command error launching process: %s", errtxt);
            # flush I/O and stop server-side WS socket handling for this connection
            flush();
            stop();
        }
    }

    private readIo(Process proc) {
        # we have to ensure that UTF-8 data does not get sent with a partial character
        try {
            on_exit {
                Qorus.httpServer.logArgs(LoggerLevel::DEBUG, "readIo() terminating");
                flush();
                stop();
            }
            code do_io = sub () {
                *string res = getIo(proc, True, ReadPollTimeout);
                res += getIo(proc, False, ReadPollTimeout);
                if (exists res) {
                    QDBG_LOG("readIo() sending initial: %y", res);
                    sendToClient(QCM_TextOutput, res);
                }
                # get remaining output with no timeout
                while (True) {
                    res = getIo(proc, True, 0);
                    res += getIo(proc, False, 0);
                    if (!exists res) {
                        break;
                    }
                    QDBG_LOG("readIo() sending: %y", res);
                    sendToClient(QCM_TextOutput, res);
                }
            };
            # always send as a binary in case we have partial multi-byte chars
            while (proc.running()) {
                do_io();
            }
            QDBG_LOG("readIo(): process terminated");
            # process remaining output, if any
            do_io();
            QDBG_LOG("readIo(): all I/O flushed");
            # issue #3952: send output when the process terminates and include the exit code
            sendToClient(QCM_TextOutput, sprintf("-- process terminated with exit code %d --\n", proc.exitCode()));
        } catch (hash<ExceptionInfo> ex) {
            string errtxt = Qorus.getDebugSystem()
                ? get_exception_string(ex)
                : sprintf("%s: %s", ex.err, ex.desc);
            Qorus.httpServer.logArgs(LoggerLevel::ERROR, "error in WebSocket remote command I/O thread: %s", errtxt);
        }
    }

    private sendToClient(string msgtype, data payload) {
        send(make_yaml({
            "msgtype": msgtype,
            "data": payload,
        }));
    }

    private *string getIo(Process proc, bool out, timeout to) {
        string key;
        string method;
        if (out) {
            method = "readStdout";
        } else {
            method = "readStderr";
        }
        return call_object_method(proc, method, ReadBufSize, to);
    }
}

class QorusRemoteWebSocketHandler inherits public WebSocketHandler {
    constructor() : WebSocketHandler(Qorus.qorusAuth) {
    }

    QorusRemoteWebSocketConnection getConnectionImpl(hash<auto> cx, hash<auto> hdr, string cid) {
        return new QorusRemoteWebSocketConnection(self, cx);
    }

    logInfo(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, "remote command WS INFO: " + fmt, argv);
    }

    logError(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::ERROR, "remote command WS ERROR: " + fmt, argv);
    }

    logDebug(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::DEBUG, "remote command WS DEBUG: " + fmt, argv);
    }
}
