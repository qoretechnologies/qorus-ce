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

class QorusRawRemoteFileRequestHandler inherits public AbstractHttpRequestHandler {
    constructor() : AbstractHttpRequestHandler(Qorus.qorusAuth) {
    }


    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr,
            *data body) {
        switch (hdr.method) {
            case "POST":
                return handlePost(hdr, body);
            case "GET":
                return handleGet(hdr, body);
            case "DELETE":
                return handleDel(hdr, body);
            default:
                return AbstractHttpRequestHandler::makeResponse(406, sprintf("HTTP method %y is not acceptable; only "
                    "\"GET\", \"POST\" and \"DELETE\" accepted", hdr.method));
        }
    }

    hash<HttpResponseInfo> handlePost(hash<auto> hdr, *data body) {
        string user_directory = hdr.dir
            ? Qorus.getRemoteFileDir() + Qore::DirSep + hdr.dir
            : FsUtil::make_tmp_dir(NOTHING, NOTHING, Qorus.getRemoteFileDir());

        Dir dir("utf-8");
        dir.chdir(user_directory);

        if (!dir.exists()) {
            dir.create(0700);
        }

        try {
            if (dirname(hdr.filepath) == ".") {
                dir.chdir(user_directory);
            } else {
                string dirname = Qore::dirname(hdr.filepath);
                # issue #3715: convert windows dir separators to UNIX separators
                dirname =~ s/\\/\//g;
                mkdir_ex(user_directory + Qore::DirSep + dirname, 0700, True);
                dir.chdir(user_directory + Qore::DirSep + dirname);
            }
            File file = dir.openFile(basename(hdr.filepath), O_CREAT|O_WRONLY|O_TRUNC, 0644, "UTF-8");
            file.write(body);
        } catch (hash<auto> ex) {
            return AbstractHttpRequestHandler::makeResponse(500, sprintf("create file %y: %s: %s", hdr.filepath,
                ex.err, ex.desc));
        }

        return AbstractHttpRequestHandler::makeResponse(200, basename(user_directory));
    }

    hash<HttpResponseInfo> handleGet(hash<auto> hdr, *data body) {
        # issue #3715: convert windows dir separators to UNIX separators
        if (hdr.dir) {
            hdr.dir =~ s/\\/\//g;
        }
        if (hdr.filename) {
            hdr.filename =~ s/\\/\//g;
        }
        string user_directory = Qorus.getRemoteFileDir() + Qore::DirSep + hdr.dir;
        string path = user_directory + Qore::DirSep + hdr.filename;

        hash<HttpResponseInfo> response = AbstractHttpRequestHandler::makeResponse(200, "SUCCESS");
        response.body = File::readBinaryFile(path);
        return response;
    }

    hash<HttpResponseInfo> handleDel(hash<auto> hdr, *data body) {
        if (hdr.dir) {
            # issue #3715: convert windows dir separators to UNIX separators
            hdr.dir =~ s/\\/\//g;
            try {
                string user_directory = Qorus.getRemoteFileDir() + Qore::DirSep + hdr.dir;
                FsUtil::remove_tree(user_directory);
            } catch (hash<auto> ex) {
                return AbstractHttpRequestHandler::makeResponse(500, sprintf("delete directory %y: %s: %s", hdr.dir,
                    ex.err, ex.desc));
            }

            return AbstractHttpRequestHandler::makeResponse(200, hdr.dir);
        } else {
            return AbstractHttpRequestHandler::makeResponse(400, "missing the 'Dir' header providing the directory "
                "tree to delete");
        }
    }
}