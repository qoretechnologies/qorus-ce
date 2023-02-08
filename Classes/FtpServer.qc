# -*- mode: qore; indent-tabs-mode: nil -*-
# FtpServer class

# based on practical testing with vsftpd and RFC 959 (http://www.faqs.org/rfcs/rfc959.html)

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args

class OMQ::FtpServerConnection {
    public {
        FtpListener listener;

        AbstractFtpHandler handler;

        string source;
        *string source_host;
        string source_str;
        any socket;
        int id;
        bool loggedin = False;

        *Socket data;
        *hash mode;

        *string user;

        # data thread TID
        *int dtid;

        # file data
        *data fd;

        # file name
        *string fn;

        # stop data thread
        bool dstop = False;

        # data thread counter
        Counter dc();

        # to flag file transfer errors
        bool err = False;

        # current working directory
%ifdef Windows
        string cwd = "\\";
%else
        string cwd = "/";
%endif

        # saved "from" path from a RNFR command
        *string RNFR;

        # transfer type (I=image or A=ascii)
        string type = "I";
    }

    constructor(FtpListener n_l, Socket n_s, any n_bind, int n_id) {
        listener = n_l;
        handler = n_l.getHandler();

        hash h = n_s.getPeerInfo();
        source = h.address;
        source_str = h.address_desc;
        source_host = h.hostname;

        socket = n_bind;
        id = n_id;
    }

    destructor() {
        resetData();
    }

    resetData() {
        dstop = True;
        dc.waitForZero();

        delete data;
        delete mode;
        delete fd;
        delete fn;

        err = False;
        dstop = False;
    }

    int startReceiveFile(Socket s, string f) {
        fn = f;

        return startData(s, \getData());
    }

    int startSendData(Socket s, data d) {
        code code = sub () { sendData(d); };
        return startData(s, code);
    }

    int startData(Socket s, code m) {
        QDBG_ASSERT(mode.PORT || mode.PASV || mode.EPSV);

        if (exists mode.PORT) {
            if (connectPort()) {
                listener.sendMsg(s, 500, "Illegal PORT command.");
                delete mode;
                return -1;
            }

            dc.inc();
            dtid = background m();
        } else if (exists mode.PASV || exists mode.EPSV) {
            # wait for passive connection to be established
            dc.waitForZero();

            #printf("DEBUG: FtpServerConnection::startData() err=%n data=%n\n", err, data);
            if (err) {
                listener.sendMsg(s, 500, "Error establishing passive data connection.");
                delete mode;
                return -1;
            }

            dc.inc();
            dtid = background m();
        }

        return 0;
    }

    int startPassiveListener(Socket s) {
        Socket d();
        if (d.bind(source + ":0")) {
            listener.logError(self, "PASV bind failed: error %d: %s", errno(), strerror(errno()));
            listener.sendMsg(s, 500, "PASV bind failed.");
            return -1;
        }

        d.listen();

        int port = d.getPort();
        int hb = port / 256;
        int lb = port % 256;
        mode.PASV.addr = source;
        mode.PASV.addr =~ s/\./,/g;
        mode.PASV.addr += sprintf(",%d,%d", hb, lb);
        mode.PASV.port = port;

        dc.inc();
        dtid = background getPassiveConnection(d);

        listener.sendMsg(s, 227, "Entering Passive Mode (%s)", mode.PASV.addr);
        listener.logInfo(self, "PASV received, listening on %s:%d with TID %d", source_str, mode.PASV.port, dtid);
        return 0;
    }

    int startExtendedPassiveListener(Socket s) {
        Socket d();
        if (d.bind(source + ":0")) {
            listener.logError(self, "EPSV bind failed: error %d: %s", errno(), strerror(errno()));
            listener.sendMsg(s, 500, "EPSV bind failed.");
            return -1;
        }

        d.listen();

        int port = d.getPort();
        mode.EPSV.addr = sprintf("|||%d|", port);
        mode.EPSV.port = port;

        dc.inc();
        dtid = background getPassiveConnection(d);

        listener.sendMsg(s, 229, "Entering Extended Passive Mode (%s)", mode.EPSV.addr);
        listener.logInfo(self, "EPSV received, listening on %s:%d with TID %d", source_str, mode.EPSV.port, dtid);
        return 0;
    }

    private getPassiveConnection(Socket d) {
        on_exit dc.dec();

        # wait for a connection from the client
        while (!dstop && !listener.exit) {
            if (d.isDataAvailable(FtpServer::PollTimeout))
                break;
        }

        string m = mode.firstKey();

        if (listener.exit) {
            listener.logInfo(self, "aborting %s data connection due to listener shutdown", m);
            err = True;
            return;
        }

        if (dstop) {
            return;
        }

        Socket newdata;
        try {
            newdata = d.accept();
            data = newdata;
            listener.logInfo(self, "connected %s data on %s:%d", m, source_str, mode{m}.port);
        } catch (hash<ExceptionInfo> ex) {
            listener.logError(self, "error accepting %s data connection: %s: %s", m, ex.err, ex.desc);
            err = True;
        }
    }

    waitForData(Socket s) {
        dc.waitForZero();

        if (!err)
            listener.sendMsg(s, 226, "Transfer complete.");
        else
            listener.sendMsg(s, 500, "Error in file transfer.");
    }

    string getPath(string fn) {
%ifdef Windows
        if (fn =~ /\//)
            fn = replace(fn, "/", "\\");
%endif
        if (!absolute_path(fn))
            fn = cwd + fn;
        return fn;
    }

    setCWD(string path) {
%ifdef Windows
        # do not allow absolute paths
        if (path =~ /^\\\\/) {
            *string p = (path =~ x/^\\\\[^\\]+\\(.*)/)[0];
            cwd = p ? p : "\\";
        }
        else if (path =~ /^[a-z]:\\/i) {
            *string p = (path =~ x/^[a-z]:\\(.*)/)[0];
            cwd = p ? p : "\\";
        }
        else
            cwd = path;
        if (cwd !~ /\\$/)
            cwd += "\\";
%else
        cwd = path;
        if (cwd !~ /\/$/)
            cwd += "/";
%endif
    }

    private getData() {
        ensure_create_tld();
        tld.add(listener.getThreadContextData());

        on_exit {
            dc.dec();
        }

        while (!dstop && !listener.exit) {
            if (!data.isDataAvailable(FtpServer::PollTimeout))
                continue;

            fd = handler.bin ? data.recvBinary(-1) : data.recv(-1);

            int size = fd.typeCode() == NT_STRING ? strlen(fd) : elements fd;
            listener.logInfo(self, "read %d bytes of file %n", size, fn);

            try {
                if (handler.root) {
                    string realpath = handler.getTargetPath(fn);

                    #printf("rp=%n root=%n p=%n\n", realpath, handler.root, path);

                    # create a file with the same encoding as the string (if the data was read as a string)
                    # to ensure that no conversions are made; has no effect if the data was read as a binary;
                    # however in case the encoding of the string is not the actual encoding of the data - we
                    # want to just write out exactly what we read with no processing)
                    File f(fd.typeCode() == NT_STRING ? get_encoding(fd) : NOTHING);

                    # open file for writing, create file and truncate if already present
                    f.open2(realpath, O_TRUNC | O_WRONLY | O_CREAT);

                    # write out file data
                    f.write(fd);
                }
            } catch (hash<ExceptionInfo> ex) {
                listener.logError(self, "error post-processing file %n: %s: %s: %s", fn, get_ex_pos(ex), ex.err, ex.desc);
                err = True;
            }

            delete data;
            break;
        }
    }

    private sendData(data d) {
        if (!ensure_tld()) {
            create_tld();
        }
        tld.add(listener.getThreadContextData());

        on_exit {
            dc.dec();
        }

        int size = d.size();
        # FIXME: add timeout with polling on exit flag here
        data.send(d);
        listener.logInfo(self, "sent %d bytes on data channel", size);

        delete data;
    }

    private int connectPort() {
        Socket d();
        try {
            d.connectINET(mode.PORT.ip, mode.PORT.port, FtpServer::ConnectTimeout);
            data = d;
        }
        catch (hash<ExceptionInfo> ex) {
            listener.logError(self, "PORT command to %s:%d failed: %s: %s", mode.PORT.ip, mode.PORT.port, ex.err, ex.desc);
            return -1;
        }
        return 0;
    }
}

class OMQ::FtpListener inherits Qore::Socket {
    private {
        FtpServer server;
        AbstractFtpHandler handler;
        # sequence for connection ID
        Sequence ss;
        auto bind_arg;

        # stop mutex
        Mutex sm();

        # bind description
        string bind_desc;

        # hash of socket info as returned from Socket::getSocketInfo()
        hash socket_info;

        # connection counter
        Counter cThreads();
        bool stopped = False;
        int id;

        # thread context
        ThreadLocalData tcx;

        bool handler_requires_auth;

        code lf;
        code elf;
    }

    public {
        # TID of the background listener thread
        int tid = -1;

        # exit flag
        bool exit = False;

        # poll interval
        const PollInterval = 300ms;
    }

    constructor(FtpServer n_server, AbstractFtpHandler n_handler, ThreadLocalData n_tcx, int n_id, Sequence n_ss,
            auto n_bind, *code n_lf, *code n_elf) {
    	server = n_server;
        handler = n_handler;
        tcx = n_tcx;
        id = n_id;
        ss = n_ss;
        lf = n_lf ?? \server.logInfo();
        elf = n_elf ?? \server.logError();

        # only call requiresAuthentication() once
        handler_requires_auth = handler.auth.requiresAuthentication();

        if (n_bind =~ /^\//) {
            # try to unlink the file first if it's a UNIX domain socket
            unlink(n_bind);
            bindUNIX(n_bind, True);
        } else {
            if (int(n_bind) == n_bind)
                n_bind = int(n_bind);
            if (bind(n_bind, True))
                throw "FTPLISTENER-BIND-ERROR", strerror();
        }

        bind_arg = n_bind;
        socket_info = getSocketInfo();

        # make 'desc' key for logging
        socket_info.desc = socket_info.address_desc;
        if (socket_info.port) {
            socket_info.desc += ":" + socket_info.port;
        }

        bind_desc = socket_info.address_desc + ":" + socket_info.port;

        if (bind_arg == "0") {
            bind_arg = socket_info.port.toString();
        } else if (bind_arg =~ /:0$/) {
            bind_arg = bind_desc;
        }

        # set TCP_NODELAY
        setNoDelay(True);

        # set listening state on socket
        if (listen()) {
            throw "FTP-LISTEN-ERROR", sprintf("listen error on socket %s: %s", n_bind, strerror());
        }

        # start main listener thread
        cThreads.inc();
        tid = background mainThread();
    }

    destructor() {
        stop();
    }

    string getBindDescription() {
        return bind_desc;
    }

    AbstractFtpHandler getHandler() {
        return handler;
    }

    ThreadLocalData getThreadContextData() {
        return tcx;
    }

    stopNoWait() {
        background stop();
    }

    stop() {
        bool update = False;
        {
            sm.lock();
            on_exit sm.unlock();

            if (!cThreads)
                return;

            if (stopped)
                return;

            if (!exit) {
                exit = True;
                update = True;
            }
        }

        # wait for all connection threads to terminate
        cThreads.waitForZero();

        if (!update)
            return;

        {
            sm.lock();
            on_exit sm.unlock();
            stopped = True;
        }

        logInfo("stopped listener");

        server.listenerStopped(self);
    }

    auto getAddress() {
        return bind_arg;
    }

    int getID() {
        return id;
    }

    hash<auto> getInfo() {
        return {
            "proto": "ftp",
            "bind": bind_arg,
            "id": id,
        } + socket_info;
    }

    private string enrichLogMsgArgs(FtpServerConnection cx, string msg, auto args) {
        string fmsg = sprintf("%s (cid %d): %s", exists cx.user ? cx.user : "<none>", cx.id, msg);
        return enrichLogMsgArgs(fmsg, args);
    }

    private string enrichLogMsgArgs(string msg, auto args) {
        string fmsg = sprintf("FTP %s: %s", bind_desc, msg);
        return vsprintf(fmsg, args);
    }

    logInfo(FtpServerConnection cx, string msg) {
        call_function_args(lf, enrichLogMsgArgs(cx, msg, argv));
    }

    logInfo(string msg) {
        call_function_args(lf, enrichLogMsgArgs(msg, argv));
    }

    logError(FtpServerConnection cx, string msg) {
        call_function_args(elf, enrichLogMsgArgs(cx, msg, argv));
    }

    logError(string msg) {
        call_function_args(elf, enrichLogMsgArgs(msg, argv));
    }

    private mainThread() {
        # DEBUG
        #printf("FTP DEBUG: listener(%s): mainThread() started TID %d\n", bind_arg, gettid());

        # start listening
        while (!exit) {
            *Socket r;
            try {
                r = accept(PollInterval);
                if (!exists r)
                    continue;
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err != "SOCKET-CLOSED")
                    logError("error accepting connection: %s: %s", ex.err, ex.desc);
                delete r;
                continue;
            }

            if (exit)
                break;

            # DEBUG
            #printf("FTP DEBUG: listener(%s): accepting FTP connection from %s\n", bind_arg, r.getPeerInfo().address_desc);
            #logInfo("accepting FTP connection from %s", r.getPeerInfo().address_desc);

            cThreads.inc();
            background connectionThread(r);
        }
        #printf("FTP DEBUG: Listener::mainThread() closing socket %s\n", bind_arg);
        shutdown();
        close();
        cThreads.dec();
        #printf("FTP DEBUG: Listener::mainThread() TID %d terminating\n", gettid());
    }

    # thread for handling communication per connection
    private connectionThread(Socket s) {
        create_tld();
        tld.add(tcx);

        on_exit {
            cThreads.dec();
        }

        hash<auto> h = s.getPeerInfo();

        FtpServerConnection cx(self, s, bind_arg, ss.next());

        # set TCP_NODELAY on incoming socket
        s.setNoDelay(True);

        logInfo(cx, "connected control channel from %s", h.address_desc);
        on_exit {
            logInfo(cx, "disconnected control channel from %s", h.address_desc);
            s.close();
        }

        # if no authentication is required, then set system user
        if (!handler_requires_auth) {
            cx.user = "SYSTEM";
            logInfo(cx, "no authentication required");
        }

        try {
            sendMsg(s, 220, server.banner);

            while (!exit) {
                if (!s.isDataAvailable(FtpServer::PollTimeout))
                    continue;

                *hash<auto> msg = getMsg(s, cx);
                if (!msg) {
                    logInfo(cx, "client closed connection");
                    break;
                }

                if (exit) {
                    sendMsg(s, 500, "FTP server shutting down.");
                    break;
                }

                if (msg.cmd == FtpServer::FC_QUIT) {
                    sendMsg(s, 221, "Goodbye.");
                    break;
                }

                if (msg.cmd == FtpServer::FC_HELP) {
                    string str = "The following commands are supported:\r\n";
                    string line = "    ";
                    foreach string cmd in (FtpServer::AllCommands) {
                        line += sprintf("%-4s", cmd);
                        if (strlen(line) < 74)
                            line += "  ";
                        else {
                            str += line + "\r\n";
                            line = "    ";
                        }
                    }
                    if (strlen(line))
                        str += line + "\r\n";

                    sendMsg(s, 214, str);
                    continue;
                }

                if (msg.cmd == FtpServer::FC_FEAT) {
                    string str = "Features supported\r\n";
                    foreach string feat in (FtpServer::Features) {
                        str += sprintf(" %s\r\n", feat);
                    }

                    sendMsg(s, 211, str);
                    continue;
                }

                if (cx.RNFR && msg.cmd != FtpServer::FC_RNTO)
                    remove cx.RNFR;

                if (!exists cx.user || msg.cmd == FtpServer::FC_USER) {
                    if (msg.cmd != FtpServer::FC_USER || !msg.arg) {
                        sendMsg(s, 530, "Please login with USER and PASS.");
                        continue;
                    }

                    cx.user = msg.arg;
                    cx.loggedin = False;

                    sendMsg(s, 331, "Please specify the password.");
                    continue;
                }

                if (!cx.loggedin || msg.cmd == FtpServer::FC_PASS) {
                    if (msg.cmd != FtpServer::FC_PASS || !msg.arg) {
                        sendMsg(s, 331, "Please specify the password.");
                        continue;
                    }

                    if (handler_requires_auth) {
                        try {
                            handler.auth.authenticate(cx.user, msg.arg);
                            logInfo(cx, "login successful");
                        } catch (hash<ExceptionInfo> ex) {
                            logInfo(cx, "invalid user or password; login rejected (%s: %s) %y %y", ex.err, ex.desc,
                                cx.user, msg.arg);
                            remove cx.user;
                            sendMsg(s, 530, "Login incorrect.");
                            cx.loggedin = False;
                            continue;
                        }
                    }

                    cx.loggedin = True;
                    sendMsg(s, 230, "Login successful.");
                    logInfo(cx, "logged in");
                    continue;
                }

                if (!cx.loggedin && !checkLogin(s, cx)) {
                    sendMsg(s, 530, "Please login with USER and PASS.");
                    continue;
                }

                if (msg.cmd == FtpServer::FC_PWD) {
                    string path = FtpListener::getDirString(cx.cwd, True);
                    sendMsg(s, 257, "%n is the current directory.", path);
                    continue;
                }

                if (msg.cmd == FtpServer::FC_CWD) {
                    if (!strlen(msg.arg) || msg.arg == ".") {
                        sendMsg(s, 250, "CWD command successful.");
                        continue;
                    }

                    string orig = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    try {
                        msg.arg = handler.authChangeDir(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    cx.setCWD(msg.arg);
                    logInfo(cx, "CWD %s", msg.arg);
                    sendMsg(s, 250, "CWD command successful.");
                    continue;
                }

                if (msg.cmd == FtpServer::FC_PORT) {
                    cx.resetData();

                    list lst = split(",", msg.arg);
                    trim lst;
                    string ip = sprintf("%d.%d.%d.%d", lst[0], lst[1], lst[2], lst[3]);
                    int port = int(lst[4]) * 256 + int(lst[5]);
                    logInfo("PORT %s (%s:%d) received", msg.arg, ip, port);

                    sendMsg(s, 200, "PORT command successful. Consider using PASV.");

                    cx.mode.PORT = ("ip": ip, "port": port);
                    #cx.data = d;
                    continue;
                }

                if (msg.cmd == FtpServer::FC_PASV) {
                    cx.resetData();

                    cx.startPassiveListener(s);
                    continue;
                }

                if (msg.cmd == FtpServer::FC_EPSV) {
                    cx.resetData();

                    cx.startExtendedPassiveListener(s);
                    continue;
                }

                if (msg.cmd == FtpServer::FC_RETR) {
                    if (!exists cx.mode) {
                        sendMsg(s, 425, "Use PORT or PASV first.");
                        continue;
                    }
                    if (!strlen(msg.arg)) {
                        sendMsg(s, 504, "Bad RETR command.");
                        continue;
                    }

                    string orig = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    try {
                        msg.arg = handler.authSendFile(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    logInfo(cx, "RETR received for file %n", msg.arg);

                    # get file data
                    data d;
                    try {
                        d = handler.sendFile(msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        logError(cx, "error retrieving file data: %s: %s", ex.err, ex.desc);
                        sendMsg(s, 500, "Error reading file data.");
                        continue;
                    }

                    if (cx.startSendData(s, d))
                        continue;

                    int size = d.size();
                    sendMsg(s, 150, "Opening %s mode data connection for '%s' (%d bytes).",
                        cx.type == "I" ? "BINARY" : "ASCII", orig, size);

                    # stop data transfer and send confirmation (or error message) on control port
                    if (!cx.waitForData(s)) {
                        # notify handler that file has been received
                        handler.fileSent(msg.arg);
                    }

                    continue;
                }

                if (msg.cmd == FtpServer::FC_SIZE) {
                    if (!strlen(msg.arg)) {
                        sendMsg(s, 504, "Bad SIZE command.");
                        continue;
                    }

                    string orig = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    int size;
                    try {
                        size = handler.size(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    sendMsg(s, 213, "%d", size);
                    continue;
                }

                if (msg.cmd == FtpServer::FC_MDTM) {
                    if (!strlen(msg.arg)) {
                        sendMsg(s, 504, "Bad MDTM command.");
                        continue;
                    }

                    string orig = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    date mdate;
                    try {
                        mdate = handler.modifiedTime(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    sendMsg(s, 213, mdate.format("YYYYMMDDHHmmSS"));
                    continue;
                }

                if (msg.cmd == FtpServer::FC_STOR) {
                    if (!exists cx.mode) {
                        sendMsg(s, 425, "Use PORT or PASV first.");
                        continue;
                    }
                    if (!strlen(msg.arg)) {
                        sendMsg(s, 504, "Bad STOR command.");
                        continue;
                    }

                    string orig = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    try {
                        msg.arg = handler.authReceiveFile(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    logInfo(cx, "STOR received for file %y", msg.arg);

                    if (cx.startReceiveFile(s, msg.arg)) {
                        continue;
                    }

                    sendMsg(s, 150, "Ok to send data.");

                    # stop data transfer and send confirmation (or error message) on control port
                    if (!cx.waitForData(s)) {
                        # notify handler that file has been received
                        handler.fileReceived(msg.arg);

                        if (!exists handler.root) {
                            # pass file data to handler
                            handler.fileDataReceived(msg.arg, cx.fd);
                        }
                    }

                    continue;
                }

                if (msg.cmd == FtpServer::FC_RNFR) {
                    if (!strlen(msg.arg)) {
                        sendMsg(s, 504, "Bad RNFR command.");
                        continue;
                    }

                    string orig = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    try {
                        msg.arg = handler.authRename(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    cx.RNFR = msg.arg;
                    logInfo(cx, "RNFR %s", msg.arg);
                    sendMsg(s, 350, "File exists, ready for destination name.");
                    continue;
                }

                if (msg.cmd == FtpServer::FC_RNTO) {
                    if (!exists cx.RNFR) {
                        sendMsg(s, 503, "Bad sequence of commands.");
                        continue;
                    }
                    string from = remove cx.RNFR;

                    string orig_to = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    *string errstr;
                    try {
                        errstr = handler.rename(cx.cwd, orig_to, from, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    if (errstr) {
                        sendMsg(s, 550, errstr);
                        continue;
                    }

                    sendMsg(s, 250, "RNTO command successful.");
                    continue;
                }

                if (msg.cmd == FtpServer::FC_MKD) {
                    if (!strlen(msg.arg)) {
                        sendMsg(s, 550, "Create directory operation failed.");
                        continue;
                    }

                    string orig = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    *string errstr;
                    try {
                        errstr = handler.makeDir(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    if (errstr) {
                        sendMsg(s, 550, errstr);
                        continue;
                    }

                    sendMsg(s, 257, "%y created", msg.arg);
                    continue;
                }

                if (msg.cmd == FtpServer::FC_RMD) {
                    if (!strlen(msg.arg)) {
                        sendMsg(s, 550, "Remove directory operation failed.");
                        continue;
                    }

                    string orig = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    *string errstr;
                    try {
                        errstr = handler.removeDir(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    if (errstr) {
                        sendMsg(s, 550, errstr);
                        continue;
                    }

                    sendMsg(s, 250, "Remove directory operation successful.");
                    continue;
                }

                if (msg.cmd == FtpServer::FC_DELE) {
                    if (!strlen(msg.arg)) {
                        sendMsg(s, 550, "Delete operation failed.");
                        continue;
                    }

                    string orig = msg.arg;
                    msg.arg = cx.getPath(msg.arg);

                    *string errstr;
                    try {
                        errstr = handler.deleteFile(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    if (errstr) {
                        sendMsg(s, 550, errstr);
                        continue;
                    }

                    sendMsg(s, 250, "Delete operation successful.");
                    continue;
                }

                if (inlist(msg.cmd, (FtpServer::FC_LIST, FtpServer::FC_NLST))) {
                    if (!exists cx.mode) {
                        sendMsg(s, 425, "Use PORT or PASV first.");
                        continue;
                    }

                    string output;
                    try {
                        output = (msg.cmd == FtpServer::FC_LIST)
                            ? handler.list(cx.cwd, msg.arg)
                            : handler.nlst(cx.cwd, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    if (cx.startSendData(s, output))
                        continue;

                    sendMsg(s, 150, "Opening ASCII mode data connection for '/bin/ls'.");

                    # stop data transfer and send confirmation (or error message) on control port
                    cx.waitForData(s);
                    continue;
                }

                if (msg.cmd == FtpServer::FC_MLSD) {
                    if (!exists cx.mode) {
                        sendMsg(s, 425, "Use PORT or PASV first.");
                        continue;
                    }

                    *string orig = msg.arg;
                    msg.arg = exists orig ? cx.getPath(msg.arg) : cx.cwd;

                    string output;
                    try {
                        output = handler.machineListDir(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    if (cx.startSendData(s, output)) {
                        continue;
                    }

                    sendMsg(s, 150, "Opening ASCII mode data connection for '%s'.", msg.cmd);

                    # stop data transfer and send confirmation (or error message) on control port
                    cx.waitForData(s);
                    continue;
                }

                if (msg.cmd == FtpServer::FC_MLST) {
                    string orig;
                    if (!msg.arg.val()) {
                        orig = ".";
                        msg.arg = cx.cwd;
                    } else {
                        orig = msg.arg;
                        msg.arg = cx.getPath(msg.arg);
                    }
                    #printf("mlst cwd=%n orig=%n arg=%n\n", cx.cwd, orig, msg.arg);

                    string output;
                    try {
                        output = handler.machineListFile(cx.cwd, orig, msg.arg);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "FTP-RESPONSE-ERROR") {
                            sendMsg(s, ex.arg.typeCode() == NT_INT ? ex.arg : 550, ex.desc);
                            continue;
                        }
                        rethrow;
                    }

                    sendMsg(s, 250, "MLST %s\r\n%s", orig, output);
                    continue;
                }

                # allows TYPE I or A but does not really do anything
                if (msg.cmd == FtpServer::FC_TYPE) {
                    msg.arg =~ tr/a-z/A-Z/;
                    if (msg.arg == "I" || msg.arg == "L8") {
                        cx.type = "I";
                        sendMsg(s, 200, "Switching to Binary mode.");
                    } else if (msg.arg == "A") {
                        cx.type = "A";
                        sendMsg(s, 200, "Switching to ASCII mode.");
                    } else
                        sendMsg(s, 500, "Unrecognised TYPE command.");

                    continue;
                }

                if (msg.cmd == FtpServer::FC_SYST) {
                    sendMsg(s, 215, "UNIX Type: L8");
                    continue;
                }

                # only allows STRU F
                if (msg.cmd == FtpServer::FC_STRU) {
                    msg.arg =~ tr/a-z/A-Z/;
                    if (msg.arg != "F")
                        sendMsg(s, 504, "Bad STRU command.");
                    else
                        sendMsg(s, 200, "Structure set to F.");
                    continue;
                }

                # only allows MODE S
                if (msg.cmd == FtpServer::FC_MODE) {
                    msg.arg =~ tr/a-z/A-Z/;
                    if (msg.arg != "S")
                        sendMsg(s, 504, "Bad MODE command.");
                    else
                        sendMsg(s, 200, "Mode set to S.");
                    continue;
                }

                if (msg.cmd == FtpServer::FC_NOOP) {
                    sendMsg(s, 200, "NOOP ok.");
                    continue;
                }

                logError(cx, "unknown command %y arg: %y", msg.cmd, msg.arg);
                sendMsg(s, 500, "Unknown command.");
            }
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "SOCKET-CLOSED" || !s.isOpen())
                logInfo(cx, "client closed connection");
            else {
                string etxt = !Qorus.getDebugSystem()
                    ? sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc)
                    : Util::get_exception_string(ex);

                string str = sprintf("%s: received from %s via %s", etxt, h.address_desc, bind_arg);
                logError(str);
            }
        }
    }

    private bool checkLogin(Socket s, FtpServerConnection cx) {
        # try to authenticate by IP
        try {
            handler.auth.authenticateByIP(s.getPeerInfo().address, \cx.user);
            cx.loggedin = True;
            logInfo(cx, "authentication by source address successful");
            return True;
        } catch (hash<ExceptionInfo> ex) {
            # ignore errors
        }
        return False;
    }

    private *hash<auto> getMsg(Socket s, FtpServerConnection cx) {
        string str = "";
        while (True) {
            try {
                if (!s.isDataAvailable(PollInterval)) {
                    if (exit)
                        return;
                    continue;
                }
            } catch (hash<ExceptionInfo> ex) {
                if (ex.err == "SOCKET-NOT-OPEN") {
                    return;
                }
                rethrow;
            }
            string c = s.recv(1);
            if (c == "\n")
                break;
            if (c != "\r")
                str += c;
        }

        #printf("getMsg(): msg=%s\n", str);
        *list<*string> l = (str =~ x/([a-z]+)( )?(.*)?/i);
        if (!exists l[0])
            return;

        hash<auto> h = {
            "cmd": l[0],
            "arg": l[2],
        };
        # ensure command is upper case
        h.cmd =~ tr/a-z/A-Z/;
        handler.logDebug("FTP RECV (conn %d): %s", id, trim(str));
        return h;
    }

    sendMsg(Socket s, int code, string msg) {
        if (msg !~ /\r\n/)
            msg = sprintf("%03d %s\r\n", code, vsprintf(msg, argv));
        else
            msg = sprintf("%03d-%s%03d END\r\n", code, vsprintf(msg, argv), code);
        handler.logDebug("FTP SEND (conn %d): %s", id, trim(vsprintf(msg, argv)));
        #printf("sendMsg(): msg=%s", msg);
        if (s.send(msg) < 0)
            throw "SEND-ERROR", sprintf("error %d sending control message: %s (msg=%n)", errno(), strerror(errno()), msg);
    }

    static string getDirString(string path, bool rs = False) {
        path =~ s/"/""/g;

        # remove trailing "/" if path is more than 1 character long
        if (rs && strlen(path) > 1)
            splice path, -1;

        return path;
    }
}

class OMQ::FtpServer {
    const Version = "0.1";

    #! default read timeout in ms (30 secs)
    const ReadTimeout = 30000;
    #! default poll timeout in ms (1 sec)
    const PollTimeout = 1000;
    #! default connect timeout (15 secs)
    const ConnectTimeout = 15000;

    # implemented FTP commands
    const FC_USER = "USER";
    const FC_PASS = "PASS";
    const FC_PORT = "PORT";
    const FC_PASV = "PASV";
    const FC_EPSV = "EPSV";
    const FC_STOR = "STOR";
    const FC_RETR = "RETR";
    const FC_QUIT = "QUIT";
    const FC_CWD  = "CWD";
    const FC_PWD  = "PWD";
    const FC_RNFR = "RNFR";
    const FC_RNTO = "RNTO";
    const FC_TYPE = "TYPE";
    const FC_SYST = "SYST";
    const FC_STRU = "STRU";
    const FC_NOOP = "NOOP";
    const FC_MODE = "MODE";
    const FC_LIST = "LIST";
    const FC_NLST = "NLST";
    const FC_MKD  = "MKD";
    const FC_RMD  = "RMD";
    const FC_DELE = "DELE";
    const FC_SIZE = "SIZE";
    const FC_FEAT = "FEAT";
    const FC_MDTM = "MDTM";
    const FC_MLSD = "MLSD";
    const FC_MLST = "MLST";
    const FC_HELP = "HELP";

    # all commands
    const AllCommands = (FC_USER, FC_PASS, FC_PORT, FC_PASV,
                         FC_EPSV,
                         FC_STOR, FC_RETR,
                         FC_QUIT, FC_CWD, FC_PWD,
                         FC_RNFR, FC_RNTO,
                         FC_TYPE, FC_SYST,
                         FC_STRU, FC_NOOP, FC_MODE,
                         FC_LIST, FC_NLST,
                         FC_MKD,  FC_RMD, FC_DELE,
                         FC_SIZE,
                         FC_FEAT,
                         FC_MDTM,
                         FC_MLSD,
                         FC_MLST,
                         FC_HELP,
        );

    const Features = ( "SIZE", "MDTM", "MLSD", "MLST Type*;Size*;Modify*;Unique*;" );

    const AIFlags = AI_PASSIVE | AI_ADDRCONFIG;

    private {
        # log function/closure
        *code logfunc;
        # error log function/closure
        *code errlogfunc;

        # quit server flag
        bool exit = False;

        Sequence seqSessions(1);
        Sequence seqListeners(1);

        bool stopped = False;

        # has of FtpListener objects, keyed by listener ID
        hash<string, FtpListener> listeners;

        # map of bind addresses to listener IDs
        hash<string, int> smap;

        # FtpListener access Gate
        Gate lm();

        # running listener counter
        Counter c();
    }

    # no public members
    public {
        string banner = sprintf("(qftpd %s for Qorus %s)", FtpServer::Version, OMQ::version);
    }

    constructor(*code lf, *code elf) {
        logfunc = lf;
        errlogfunc = elf;
    }

    #! throws an exception; these objects to not support copying
    copy() {
        throw "COPY-ERROR", "this object cannot be copied";
    }

    #! calls FtpServer::stop()
    destructor() {
        stop();
    }

    #! adds and starts a listener and returns a hash of listener info
    private hash<auto> addListenerIntern(AbstractFtpHandler handler, ThreadLocalData tcx, softstring sock, *code lf,
            *code elf) {
        lm.enter();
        on_exit lm.exit();

        if (smap{sock})
            throw "FTPLISTENER-ERROR", sprintf("cannot add listener on %n; there is already an existing listener with "
                "this bind address", sock);

        c.inc();
        #printf("HttpServer::addListenerIntern() %n c=%n\n", sock, c.getCount());
        on_error c.dec();

        int id = seqListeners.next();
        FtpListener l(self, handler, tcx, id, seqSessions, sock, lf, elf);
        listeners{id} = l;
        smap{l.getBindDescription()} = id;
        return l.getInfo();
    }

    list addListeners(AbstractFtpHandler handler, ThreadLocalData tcx, softstring sock, *code lf, *code elf) {
        if (sock !~ /:/) {
            if (sock =~ /^\//)
                return list(addListenerIntern(handler, tcx, sock, lf, elf));

            return addINETListeners(handler, tcx, NOTHING, sock, lf, elf);
        }

        (string node, string service) = (sock =~ x/(\w+):(\w+)/);
        return addINETListeners(handler, tcx, node, service, lf, elf);
    }

    list addINETListeners(AbstractFtpHandler handler, ThreadLocalData tcx, *string node, softstring service, *code lf, *code elf) {
        list al = getaddrinfo(node, service, AF_UNSPEC, AIFlags);

        # sort ipv6 addresses first in list
        al = sort(al, int sub (hash l, hash r) { return l.family === AF_INET6 ? -1 : 0; });

        list l = ();
        hash errh;
        foreach hash h in (al) {
            string bind = h.address + ":" + h.port;
            try {
                l += addListenerIntern(handler, tcx, bind, lf, elf);
            }
            catch (hash<ExceptionInfo> ex) {
                logInfo("cannot add listener on %s:%d: %s: %s", h.address_desc, h.port, ex.err, ex.desc);
                errh = ex;
            }
        }
        if (!l && errh)
            throw errh.err, errh.desc, errh.arg;
        return l;
    }

    #! returns a hash of listener information
    *hash<string, hash<auto>> getListeners() {
        hash<string, hash<auto>> h;

        lm.enter();
        on_exit lm.exit();

        map h.$1 = listeners.$1.getInfo(), keys listeners;
        return h;
    }

    #! called by listeners when they have shut down
    listenerStopped(FtpListener l) {
        # decrement listener count
        on_exit c.dec();

        lm.enter();
        on_exit lm.exit();

        # remove from bind -> id map
        delete smap{l.getBindDescription()};

        # remove from id -> bind map and delete listener
        delete listeners.(l.getID());
    }

    #! stops all listeners; does not wait for all connections on the listeners to close
    /** do not call FtpServer::stop() after calling FtpServer::stopNoWait(); it can cause a deadlock */
    stopNoWait() {
        # stop all listeners
        lm.enter();
        on_exit lm.exit();

        map listeners.$1.stopNoWait(), keys listeners;
    }

    #! waits for all listeners to be stopped; call after calling FtpServer::stopNoWait()
    waitStop() {
        c.waitForZero();
    }

    #! stops all listeners; only returns when all connections are closed on all listeners
    /** do not call FtpServer::stop() after calling FtpServer::stopNoWait(); it can cause a deadlock */
    stop() {
        # shutdown all listeners
        {
            lm.enter();
            on_exit lm.exit();
            map listeners.$1.stop(), keys listeners;
        }

        c.waitForZero();
    }

    #! stops a single listener based on its bind address; does not return until all connections on the listener have closed
    stopListener(softstring bind) {
        lm.enter();
        on_exit lm.exit();

        *int id = smap{bind};

        if (!exists id)
            throw "FTP-SERVER-ERROR", sprintf("there is no listener with bind address %n", bind);

        listeners{id}.stop();
    }

    #! stops a single listener based on its listener ID; does not return until all connections on the listener have closed
    auto stopListenerId(softint id) {
        lm.enter();
        on_exit lm.exit();

        if (!exists listeners{id}) {
            throw "FTP-SERVER-ERROR", sprintf("there is no listener with ID %d", id);
        }

        listeners{id}.stop();
    }

    #! stops a single listener based on its listener ID; returns immediately before the listener is stopped
    /** @throws FTP-SERVER-ERROR if the listener ID is not valid
    */
    auto stopListenerIdNoWait(softint id) {
        lm.enter();
        on_exit lm.exit();

        if (!exists listeners{id}) {
            throw "FTP-SERVER-ERROR", sprintf("there is no listener with ID %d", id);
        }

        background listeners{id}.stop();
    }

    #! gets the TID of a listener based on its listener ID
    int getListenerTID(softint id) {
        lm.enter();
        on_exit lm.exit();

        if (!exists listeners{id})
            throw "FTP-SERVER-ERROR", sprintf("there is no listener with ID %d", id);

        return listeners{id}.tid;
    }

    #! gets listener info
    hash getListenerInfo(softint id) {
        lm.enter();
        on_exit lm.exit();

        if (!exists listeners{id})
            throw "FTP-SERVER-ERROR", sprintf("there is no listener with ID %d", id);

        return listeners{id}.getInfo();
    }

    logInfo(string msg) {
        if (!logfunc) {
            return;
        }

        #args[0] = "FTP: " + args[0];
        call_function_args(logfunc, vsprintf(msg, argv));
    }

    logError(string msg) {
        if (!errlogfunc)
            return;

        #args[0] = "FtpServer: " + args[0];
        call_function_args(errlogfunc, vsprintf(msg, argv));
    }
}
