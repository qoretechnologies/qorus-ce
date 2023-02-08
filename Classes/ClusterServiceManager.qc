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

public namespace OMQ;

class OMQ::ClusterServiceManager {
    public {
    }

    private:internal {
        static Mutex m();
    }

    static bindFtp(AbstractFtpHandler handler) {
        Qorus.svc.bindFtp(handler);
    }

    static uiExtensionRegister(QorusExtensionHandler handler) {
        Qorus.svc.uiExtensionRegister(handler);
    }

    static uiExtensionRegister(QorusExtensionHandler handler, string url_name) {
        Qorus.svc.uiExtensionRegister(handler, url_name);
    }

    static list<string> registerSoapListener(hash<auto> sh, softstring bind, int family = AF_UNSPEC, *HttpServer::AbstractAuthenticator auth, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        return Qorus.svc.registerSoapListener(sh, bind, family, auth, opts);
    }

    static list<string> registerSoapListeners(list<auto> sl, softstring bind, *hash<auto> lh, int family = AF_UNSPEC, *HttpServer::AbstractAuthenticator auth, hash<HttpBindOptionInfo> opts = <HttpBindOptionInfo>{}) {
        return Qorus.svc.registerSoapListeners(sl, bind, lh, family, auth, opts);
    }

    static stopListenerName(*hash<auto> cx, string name) {
        Qorus.services_client.stopListenerName(get_cx(cx), name);
    }

    static stopListenerId(*hash<auto> cx, softstring lid) {
        Qorus.services_client.stopListenerName(get_cx(cx), lid);
    }

    static auto callMethodExtern(string type, string name, string method, *softlist<auto> args, *hash<auto> my_tld, *bool ext) {
        if (type == Qorus.svc.type && name == Qorus.svc.name) {
            return Qorus.svc.callMethodImpl(method, args);
        }
        # issue #3218: serialize the args twice to ensure that they are not deserialized in qorus-core
        return Qorus.services_client.doCallWithSerializedResponse("callMethodExternSerialized",
            (type, name, method, Serializable::serialize(args), my_tld, ext));
    }

    static *hash<auto> getServiceInfo(string type, string name, *hash<auto> cx) {
        return Qorus.services_client.getServiceInfo(type, name, cx);
    }

    static int startServiceThreadArgs(auto func, auto args) {
        return Qorus.svc.startThread(m, func, args);
    }
}
