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

class OMQ::RemoteFtpHandler inherits OMQ::AbstractFtpHandler, OMQ::RemoteHandlerBase {
    private {
        hash<auto> mh;
    }

    constructor(RemoteQorusService svc, string rid, hash<auto> conf)
            : AbstractFtpHandler(conf.root, conf.bin, RemoteFtpHandler::getAuth(conf.auth, svc, rid)),
            RemoteHandlerBase(svc, rid) {
        mh = conf.mh;

        map addListener($1), conf.listeners;
    }

    string authReceiveFile(string cwd, string orig, string path) {
        if (mh.authReceiveFile) {
            return svc.doRemoteFtpRequest(rid, "authReceiveFile", (cwd, orig, path));
        }
        return AbstractFtpHandler::authReceiveFile(cwd, orig, path);
    }

    fileDataReceived(string path, data data) {
        if (mh.fileDataReceived) {
            svc.doRemoteFtpRequest(rid, "fileDataReceived", (path, data));
        }
        AbstractFtpHandler::fileDataReceived(path, data);
    }

    fileReceived(string path) {
        if (mh.fileReceived) {
            svc.doRemoteFtpRequest(rid, "fileReceived", (path));
        }
        AbstractFtpHandler::fileReceived(path);
    }

    string authSendFile(string cwd, string orig, string path) {
        if (mh.authSendFile) {
            return svc.doRemoteFtpRequest(rid, "authSendFile", (cwd, orig, path));
        }
        return AbstractFtpHandler::authSendFile(cwd, orig, path);
    }

    data sendFile(string path) {
        if (mh.sendFile) {
            return svc.doRemoteFtpRequest(rid, "sendFile", (path));
        }
        return AbstractFtpHandler::sendFile(path);
    }

    int size(string cwd, string orig, string path) {
        if (mh.size) {
            return svc.doRemoteFtpRequest(rid, "size", (cwd, orig, path));
        }
        return AbstractFtpHandler::size(cwd, orig, path);
    }

    date modifiedTime(string cwd, string orig, string path) {
        if (mh.modifiedTime) {
            return svc.doRemoteFtpRequest(rid, "modifiedTime", (cwd, orig, path));
        }
        return AbstractFtpHandler::modifiedTime(cwd, orig, path);
    }

    fileSent(string path) {
        if (mh.fileSent) {
            svc.doRemoteFtpRequest(rid, "fileSent", (path));
        }
        AbstractFtpHandler::fileSent(path);
    }

    string authChangeDir(string cwd, string orig, string path) {
        if (mh.authChangeDir) {
            return svc.doRemoteFtpRequest(rid, "authChangeDir", (cwd, orig, path));
        }
        return AbstractFtpHandler::authChangeDir(cwd, orig, path);
    }

    string authRename(string cwd, string orig, string path) {
        if (mh.authRename) {
            return svc.doRemoteFtpRequest(rid, "authRename", (cwd, orig, path));
        }
        return AbstractFtpHandler::authRename(cwd, orig, path);
    }

    *string rename(string cwd, string orig_to, string from, string to) {
        if (mh.rename) {
            return svc.doRemoteFtpRequest(rid, "rename", (cwd, orig_to, from, to));
        }
        return AbstractFtpHandler::rename(cwd, orig_to, from, to);
    }

    string list(string cwd, *string path) {
        if (mh."list") {
            return svc.doRemoteFtpRequest(rid, "list", (cwd, path));
        }
        return AbstractFtpHandler::list(cwd, path);
    }

    string nlst(string cwd, *string path) {
        if (mh.nlst) {
            return svc.doRemoteFtpRequest(rid, "nlst", (cwd, path));
        }
        return AbstractFtpHandler::nlst(cwd, path);
    }

    string machineListFile(string cwd, *string orig, string path) {
        if (mh.machineListFileRemote) {
            return svc.doRemoteFtpRequest(rid, "machineListFile", (cwd, orig, path));
        }
        return AbstractFtpHandler::machineListFile(cwd, orig, path);
    }

    string machineListDir(string cwd, *string orig, string path) {
        if (mh.machineListDirRemote) {
            return svc.doRemoteFtpRequest(rid, "machineListDir", (cwd, orig, path));
        }
        return AbstractFtpHandler::machineListDir(cwd, orig, path);
    }

    string getTargetPath(string path) {
        if (mh.getTargetPath) {
            return svc.doRemoteFtpRequest(rid, "getTargetPath", (path));
        }
        return AbstractFtpHandler::getTargetPath(path);
    }

    *string makeDir(string cwd, string orig, string path) {
        if (mh.makeDir) {
            return svc.doRemoteFtpRequest(rid, "makeDir", (cwd, orig, path));
        }
        return AbstractFtpHandler::makeDir(cwd, orig, path);
    }

    *string removeDir(string cwd, string orig, string path) {
        if (mh.removeDir) {
            return svc.doRemoteFtpRequest(rid, "removeDir", (cwd, orig, path));
        }
        return AbstractFtpHandler::removeDir(cwd, orig, path);
    }

    *string deleteFile(string cwd, string orig, string path) {
        if (mh.deleteFile) {
            return svc.doRemoteFtpRequest(rid, "deleteFile", (cwd, orig, path));
        }
        return AbstractFtpHandler::deleteFile(cwd, orig, path);
    }

    static *AbstractAuthenticator getAuth(string auth, RemoteQorusService svc, string rid) {
        switch (auth) {
            case "def": return new DefaultQorusRBACAuthenticator();
            case "remote": return new RemoteFtpServiceAuthenticator(svc, rid);
            case "none": break;
            default: throw "UNSUPPORTED-AUTHENTICATION", sprintf("unrecognized authentication %y for FTP handler", auth);
        }
    }
}
