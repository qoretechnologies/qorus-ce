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

public namespace RemoteDevelopment;

/** @REST /v3/development

    This URI path provides remote development for Qorus.
*/
class RemoteDevelopment::RestClass inherits QorusRestClass {
    private:internal {
        hash<auto> subClasses;
    }

    string name() {
        return "development";
    }

    constructor() {
        addClass(new RemoteDevelopment::DeployRestClass());
        addClass(new RemoteDevelopment::DeleteRestClass());
        addClass(new RemoteDevelopment::ReleaseRestClass());
        addClass(new RemoteDevelopment::TestRestClass());
    }

    *QorusRestClass subClass(string api_path, hash<auto> cx, *hash<auto> ah) {
        return subClasses{api_path};
    }

    /** @REST GET

        @par Description
        Returns all API paths of development API path.

        @par Return Value
        If success 200 OK and \a list of the all API paths.
    */
    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, subClasses.keys());
    }

    private:internal addClass(QorusRestClass restClass) {
        subClasses{restClass.name()} = restClass;
    }
}

#! Helper class providing API to obtain status and cancel a remote development request
class RemoteDevelopment::RequestRestClass inherits QorusRestClass {
    private {
        string id;
    }

    constructor(string id_) {
        id = id_;
    }

    string name() {
        return id;
    }

    hash<auto> get(hash<auto> cx, *hash<auto> ah) {
        try {
            hash<auto> status = Qorus.remoteDevelopmentHandler.getRequestStatus(id);
            qlog(LoggerLevel::DEBUG, "Status: %N", status);
            return RestHandler::makeResponse(200, status);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "NOT-FOUND") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
    }

    hash<auto> del(hash<auto> cx, *hash<auto> ah) {
        try {
            bool success = Qorus.remoteDevelopmentHandler.cancelRequest(id, cx.user);
            if (success) {
                return RestHandler::makeResponse(200, "OK");
            } else {
                return RestHandler::makeResponse(410, "Cannot cancel request");
            }
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "FORBIDDEN") {
                return RestHandler::makeResponse(403, sprintf("%s: %s", ex.err, ex.desc));
            }
            if (ex.err == "NOT-FOUND") {
                return RestHandler::makeResponse(404, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
    }
}
