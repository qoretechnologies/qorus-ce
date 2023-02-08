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

public namespace OMQ {
class QorusSwaggerApiManager inherits QorusHttpApiManagementHandler {
    public {
        #! REST API profile options
        const ProfileOptions = QorusHttpApiManagementHandler::HttpApiProfileOptions + {
            "cors-enable": <ApiOptionInfo>{
                "type": "bool",
                "desc": "Set to `true` to enable CORS",
                "default_value": False,
            },
            "cors-methods": <ApiOptionInfo>{
                "type": "list",
                "desc": "HTTP methods allowed with CORS; ignored if `cors-enable` is `false`",
                "default_value": (
                    "GET",
                    "POST",
                    "PUT",
                    "PATCH",
                    "DELETE",
                    "OPTIONS",
                ),
            },
            "cors-max-age": <ApiOptionInfo>{
                "type": "int",
                "desc": "The value for the `Access-Control-Max-Age` header",
                "default_value": 9999999,
            },
            "cors-headers": <ApiOptionInfo>{
                "type": "*list",
                "desc": "Values for the `Access-Control-Allow-Headers` header",
                "default_value": (
                    "Content-Type",
                    "content-type",
                    "Content-Language",
                    "content-language",
                    "Accept",
                    "Accept-Language",
                    "Authorization",
                ),
            },
            "cors-credentials": <ApiOptionInfo>{
                "type": "bool",
                "desc": "if `true` then the `Access-Control-Allow-Credentials: true` header is sent",
                "default_value": False,
            },
        };
    }

    constructor(LocalQorusService service, hash<auto> api_manager) : QorusHttpApiManagementHandler(service, api_manager) {
    }

    private string checkApiProfile(hash<string, bool> api_profile_map) {
        if (!api_profile_map.rest) {
            throw "SERVICE-ERROR", sprintf("the Swagger API manager requires a data provider factory that supports "
                "the \"rest\" API profile; the given data provider factory supports %y instead",
                keys api_profile_map);
        }
        return "rest";
    }

    private setupServiceImpl(AbstractDataProviderFactory factory, AbstractDataProvider provider,
            *hash<auto> api_profile_options) {
        QorusSwaggerApiManagementRestHandler handler(service, endpoint_map, provider, api_profile_options);

        hash<HttpBindOptionInfo> bind_options = setupHandler(handler, api_profile_options);
        ServiceApi::bindHttp(handler, bind_options);
    }

    private hash<auto> getEndpointInfo(string path, AbstractDataProvider provider) {
        hash<auto> rv += {
            "endpoint": path,
        };
        if (provider.className() == "SwaggerRequestDataProvider") {
            # NOTE: the SwaggerDataProvider module is loaded dynamically, so we use "object" here
            object sprov = cast<object>(provider);
            rv += {
                "op": sprov.op,
                "success_code": sprov.success_response.toInt(),
            };
        }
        return rv;
    }
}

class QorusSwaggerApiManagementRestHandler inherits QorusRestApiManagementHandler {
    constructor(LocalQorusService service, hash<string, hash<auto>> endpoint_map, AbstractDataProvider provider,
            hash<auto> api_profile_options)
            : QorusRestApiManagementHandler(service, endpoint_map, api_profile_options,
                cast<object>(provider).schema) {
        # NOTE: the SwaggerDataProvider module is loaded dynamically, so we use "object" here
    }

    #! Dispatches the request and returns the response
    private hash<HttpHandlerResponseInfo> dispatchApiRequest(string method_name, string simple_path, hash<auto> api,
            *hash<auto> args) {
        try {
            #UserApi::logDebug("Swagger API %s %s: responses: %y", api.op.method, api.op.path, keys api.op.responses.responses);
            return QorusRestApiManagementHandler::dispatchApiRequest(method_name, simple_path, api, args);
        } catch (hash<ExceptionInfo> ex) {
            UserApi::logError("Swagger API error: %s", get_exception_string(ex));
            if (ex.err == "SWAGGER-ERROR") {
                if (api.op.responses.responses{ex.desc}) {
                    UserApi::logInfo("Swagger error response %d error body type: %y", ex.desc, ex.arg.type());
                    return <HttpHandlerResponseInfo>{
                        "code": ex.desc.toInt(),
                        "body": ex.arg,
                    };
                }
                string desc = sprintf("Swagger error response %y is not defined in the schema; rethrowing exception", ex.desc);
                UserApi::logInfo("%s", desc);
                rethrow ex.err, desc;
            }
            rethrow;
        }
    }
}
}