# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style

# must be defined for SQLInterface, the dependent method does not call this function in qsvc
hash sub encrypt_order_data(softint wfiid, string skey, string svalue, hash info, *hash meta) {
    throw "ERROR";
}

sub slog_args(softlist args) {
    Qorus.logArgs(convert_old_log_level(shift args), shift args, args);
}

sub service_log(int lvl, string fmt) {
    Qorus.logArgs(convert_old_log_level(lvl), fmt, argv);
}

sub service_log_args(int lvl, string fmt, *softlist<auto> args) {
    Qorus.logArgs(convert_old_log_level(lvl), fmt, args);
}

deprecated sub osqllog(string ds, string fmt) {
    Qorus.logArgs(LoggerLevel::INFO, "SQL " + ds + ": " + fmt, argv);
}

deprecated public sub sqllog(string ds, string fmt) {
    Qorus.logArgs(LoggerLevel::INFO, "SQL " + ds + ": " + fmt, argv);
}

sub qorus_api_service_set_option(hash<auto> h) {
    Qorus.svc.setOptions(h);
}

auto sub qorus_api_service_get_option() {
    return Qorus.svc.getOption(argv);
}

auto sub qorus_api_service_get_option_args(*softlist<auto> args) {
    return Qorus.svc.getOption(args);
}

hash<auto> sub qorus_api_svc_get_service_info(*hash<auto> cx) {
    return Qorus.svc.getInfo(cx) + {"method": tld.method};
}

*hash sub qorus_api_svc_get_service_info_as_current_user(softint id, *hash cx) {
    return Qorus.callCoreFunction("qorus_api_svc_get_service_info_as_current_user", id, cx);
}

*hash sub qorus_api_svc_get_service_info_as_current_user(string type, string name, *hash cx) {
    return Qorus.callCoreFunction("qorus_api_svc_get_service_info_as_current_user", type, name, cx);
}

list<hash<auto>> sub qorus_api_svc_get_running_workflow_list_as_current_user(string name, *string ver) {
    return cast<list<hash<auto>>>(Qorus.callCoreFunction("qorus_api_svc_get_running_workflow_list_as_current_user", name, ver));
}

list sub qorus_api_svc_start_listeners(softstring bind, *string cert_path, *string key_path, *string key_password, *string name, int family = AF_UNSPEC) {
    return Qorus.callCoreFunction("qorus_api_svc_start_listeners", bind, cert_path, key_path, name, family, key_password);
}

sub qorus_api_svc_slog(list args) {
    call_function_args(\Qorus.logArgs(), (convert_old_log_level(shift args), shift args, args));
}

list<string> sub qorus_api_svc_bind_http(OMQ::AbstractServiceHttpHandler handler, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
    return Qorus.svc.bindHttp(handler, opts);
}

sub qorus_api_svc_bind_handler(string name, OMQ::AbstractServiceHttpHandler handler) {
    Qorus.svc.bindHandler(name, handler);
}

sub qorus_api_svc_bind_handler(string name, HttpServer::AbstractHttpRequestHandler handler, string url, *softlist content_type, *softlist special_headers, bool isregex = True) {
    Qorus.svc.bindHandler(name, handler, url, content_type, special_headers, isregex);
}

sub qorus_api_svc_register_soap_service(WebService ws, *softlist<string> service, *string uri_path, bool newapi) {
    Qorus.svc.registerSoapService(ws, service, uri_path, newapi);
}

sub qorus_api_ref_service(AbstractQorusService svc) {
    # noop in qsvc processes
    #Qorus.callCoreFunction("qorus_api_ref_service", svc.type, svc.name);
}

sub qorus_api_deref_service(AbstractQorusService svc) {
    # noop in qsvc processes
    #Qorus.callCoreFunction("qorus_api_deref_service", svc.type, svc.name);
}

*int sub service_audit_user_event(string user_event, *string info1, *string info2) {
    return Qorus.callCoreFunction("service_audit_user_event_remote", tld.svc.type, tld.svc.name, user_event, info1, info2);
}

# public user APIs
public namespace OMQ {
    public namespace UserApi {
        public namespace Service {
            auto sub svc_call_api_as_current_user(string call, softlist args) {
                return call_system_api_as_user(call, args, DefaultSystemUser, False);
            }

            *hash sub svc_get_call_context() {
                hash rv;
                if (tld.wfe) {
                    rv.wf += tld.wfe.("workflow_instanceid", "priority", "started");
                    rv.wf += tld.wfe.wf.("name", "version", "workflowid");
                    rv.wf.stepid = tld.stepID;
                    rv.wf.ind = tld.ind;
                    if (tld.index) {
                        try {
                            rv.wf.options = Qorus.control_client.getAllWorkflowInstanceOptions({"username": "%SYS%"}, tld.index);
                        }
                        catch (hash<ExceptionInfo> ex) {
                        }
                    }
                }
                else if (tld.wf) {
                    rv.wf += tld.wf.("name", "version", "workflowid");
                }
                if (tld.job) {
                    rv.job = tld.job.getInfo();
                }
                if (tld.cx) {
                    rv.cx = tld.cx.("socket", "socket-info", "peer-info", "url", "id", "ssl", "user");
                }

                return rv;
            }
        }

        /*
        public namespace Service {
            *hash sub svc_try_get_wf_static_data() {
                return SM.tryGetStaticData();
            }

            *hash sub svc_try_get_wf_dynamic_data() {
                return SM.tryGetDynamicData();
            }

            *hash sub svc_try_get_wf_temp_data() {
                return SM.tryGetTempData();
            }
        }
        */
    }
}
