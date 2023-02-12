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

public namespace OMQ {
class QorusSoapApiManager inherits QorusHttpApiManagementHandler {
    public {
        #! SOAP API profile options
        const ProfileOptions = QorusHttpApiManagementHandler::HttpApiProfileOptions;
    }

    constructor(LocalQorusService service, hash<auto> api_manager) : QorusHttpApiManagementHandler(service, api_manager) {
    }

    private string checkApiProfile(hash<string, bool> api_profile_map) {
        if (!api_profile_map.soap) {
            throw "SERVICE-ERROR", sprintf("the SOAP API manager requires a data provider factory that supports "
                "the \"soap\" API profile; the given data provider factory supports %y instead",
                keys api_profile_map);
        }
        return "soap";
    }

    private setupServiceImpl(AbstractDataProviderFactory factory, AbstractDataProvider provider,
            *hash<auto> api_profile_options) {
        AbstractAuthenticator auth = QorusRestApiManagementHandler::getAuthenticator(api_profile_options);
        QorusSoapApiManagementHandler handler(service, endpoint_map, provider, api_profile_options, auth);

        hash<HttpBindOptionInfo> bind_options = setupHandler(handler, api_profile_options);
        ServiceApi::bindHttp(handler, bind_options);
    }

    private hash<auto> getEndpointInfo(string path, AbstractDataProvider provider) {
        hash<auto> rv += {
            "endpoint": path,
        };
        if (provider.className() == "SoapRequestDataProvider") {
            # NOTE: the WSDL and SoapDataProvider modules are loaded dynamically, so we use "object" here
            object sprov = cast<object>(provider);
            rv += {
                "op": sprov.getOperation(),
            };
        }
        return rv;
    }
}

class QorusSoapApiManagementHandler inherits AbstractServiceSoapHandler {
    private {
        LocalQorusService service;
        hash<string, hash<auto>> endpoint_map;
    }

    constructor(LocalQorusService service, hash<string, hash<auto>> endpoint_map, AbstractDataProvider provider,
            hash<auto> api_profile_options, AbstractAuthenticator auth)
            : AbstractServiceSoapHandler(api_profile_options."root-uri", auth) {
        self.service := service;
        self.endpoint_map = cast<hash<string, hash<auto>>>(map {$1.key[1..]: $1.value}, endpoint_map.pairIterator());
        # NOTE: the WSDL and SoapDataProvider modules are loaded dynamically, so we use "object" here
        # get WebService object
        object ws = cast<object>(provider).webservice;

        # add all SOAP methods handled
        foreach hash<auto> i in (endpoint_map.pairIterator()) {
            addMethod(ws, i.value.op, "unused");
        }
    }

    #! Dispatches the SOAP operation call and returns the result for validation and serialization
    private auto dispatchSoapOperationCall(hash<auto> method, hash<auto> cx, auto args) {
        *hash<auto> api = endpoint_map{method.name};
        if (api) {
            UserApi::logInfo("dispatching SOAP API %s with %s %s", method.name, api.call_type, api.name);
            UserApi::logDebug("SOAP API %s %s args: %y", api.call_type, api.name, args);
            auto rv;
            switch (api.call_type) {
                case "method":
                    return services.callMethodExtern(service.type, service.name, api.name, args, NOTHING, True);
                case "fsm":
                    return QorusFsmHandler::executeFsm(api.name, args);
            }
            throw "API-ERROR", sprintf("SOAP API endpoint %s: unknown call_type %y", method.name, api.call_type);
        }

        QDBG_LOG("SOAP API ENDPOINT NO MATCH: operation: %y endpoints: %y", method.name, keys endpoint_map);

        return AbstractServiceSoapHandler::dispatchSoapOperationCall(method, args);
    }
}
}