# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusClientServer.qc common client/server code

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

# this file is automatically included by the Qorus client library and should not be included directly by Qorus client programs

%new-style
%require-types
%push-parse-options

# common client and server initialization
public class QorusClientServer {
    private {
        const ModuleImportMap = {
            "RemoteDbDataProvider": {
                "classes": (
                    "DbRemoteBase",
                    "DbRemoteSend",
                    "DbRemoteReceive",
                    "DbRemoteRawReceive",
                ),
            },
            "RemoteApiProvider": {
                "classes": (
                    "QorusSystemRestHelper",
                ),
            },
            "RemoteDbProvider": {
                "classes": (
                    "QorusSystemRestHelper",
                ),
            },
            "QorusRemoteConnectionDataProvider": {
                "classes": (
                    "QorusSystemRestHelper",
                ),
            },
            "QorusRemoteDataProvider": {
                "classes": (
                    "QorusSystemRestHelper",
                    "QorusCommonClientServerApi",
                ),
            },
            "QorusApiDataProvider": {
                "classes": (
                    "QorusLocalRestHelper",
                    "UserApi",
                ),
                "defines": (
                    "HasQorusLocalRestHelper",
                ),
            },
            "QorusResourceFileLocationHandler": {
%ifdef QorusServer
                "classes": (
                    "UserApi",
                    "QorusSystemRestHelper",
%ifdef QorusHasSvcApi
                    "ServiceApi",
%endif
                ),
                "gvars": (
%ifdef QorusQsvcServer
                    "Qorus",
%endif
                ),
%endif
                "defines": (
%ifdef QorusHasSvcApi
                    "QorusHasSvcApi",
%endif
%ifdef QorusQsvcServer
                    "QorusQsvcServer",
%endif
                ),
            }
        };
    }

    static init() {
        # set data provider module callbacks
        AbstractDataProvider::setDynamicValueCallbacks(\QorusClientServer::dataProviderCheckValue(),
            \QorusClientServer::dataProviderResolveValue());

        # import the modules with imported APIs
        foreach hash<auto> i in (ModuleImportMap.pairIterator()) {
            if (!get_module_hash(){i.key}) {
                Program p(PO_NO_USER_API);
                # import but do not reexport public classes
                map p.importClass($1, NOTHING, NOTHING, CSP_SETPRIV), i.value.classes;
                map p.define($1, True), i.value.defines;
                map p.importGlobalVariable($1), i.value.gvars;
                p.loadApplyToUserModule(i.key, False, WARN_MODULES, True);
            }
            # ensure the module is loaded in the calling Program container
            load_module(i.key);
        }

%ifndef QorusServer
        QorusClient::init2();
%endif
    }

    static bool dataProviderCheckValue(auto value) {
        return value =~ /\$/;
    }

    static auto dataProviderResolveValue(auto value) {
        try {
            return UserApi::expandTemplatedValue(value);
        } catch (hash<ExceptionInfo> ex) {
            # we must ignore errors here to allow mappers to be displayed / queried outside of the interface context
            return value;
        }
    }
}

# common API
namespace Priv {
class QorusCommonClientServerApi {
    static *list<string> listRemoteConnections() {
%ifdef QorusServer
        return map $1.name, Qorus.remotemonitor.list();
%else
        return keys omqclient.getRemoteInfo();
%endif
    }

    static string getQorusSystemUrl() {
        return UserApi::qorusGetLocalUrl();
    }
}
}


