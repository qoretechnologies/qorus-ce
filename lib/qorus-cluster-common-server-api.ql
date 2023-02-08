# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file qorus-cluster-common-server-api.ql functions common to workflow, service, and job APIs

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

public namespace OMQ {
    our QorusSystemServiceHelper omqservice;
    class QorusSystemServiceHelper {
        public {
            #! ServiceGate object for system services
            ServiceGate system("system");
            #! ServiceGate object for user services
            ServiceGate user("user");
        }
    }

    class ServiceGate {
        private:internal {
            string type__;
        }

        #! creates the object with the given type
        constructor(string type) {
            self.type__ = type;
        }

        #! tries to load the service; then redirects to the ServiceMethodGate object for the service
        synchronized ServiceMethodGate memberGate(string m) {
            return self{m} = new ServiceMethodGate(type__, m);
        }
    }

    #! ServiceMethodGate provides a gateway to service methods; this class is not designed to be used directly; use ::omqservice instead
    class ServiceMethodGate {
        public {}

        private {
            string type;
            string name;
        }

        #! creates the object
        constructor(string t, string n) {
            type = t;
            name = n;
        }

        #! transparently redirects method calls to the service
        auto methodGate(string m) {
            return services.callMethodExtern(type, name, m, argv, Qorus.getTldContext());
        }

        #! redirects external calls to the service method
        auto externalMethodGateArgs(string m, auto args) {
            return services.callMethodExtern(type, name, m, args, Qorus.getTldContext(), True);
        }
    }

    #! class used to call the Qorus system API for a remote Qorus instance through the network API
    /** @see QorusSystemAPIHelperBase for the method documentation
    */
    public class QorusSystemAPIHelper inherits QorusSystemAPIHelperBase {
        #! creates the object based on the options passed
        /** @param opts optional hash with the following keys:
            - \c timeout
            - \c connect_timeout
            - \c http_version
            - \c url
            - \c max_redirects
            - \c proxy
            @param init an optional initialization closure to be called with the RPC object as the sole argument

            @see ValidClientAPIOpts
        */
        constructor(*hash<auto> opts, *code init) : QorusSystemAPIHelperBase(QorusSystemAPIHelperBase::toConfig(opts), init) {
        }

        #! creates the object based on the connection information for the given @ref remoteconn "remote connection"
        /** @param name the name of the @ref remoteconn "remote connection"
         */
        constructor(string name) {
            hash<auto> h = Qorus.remotemonitor.getInfo(name, {"with_passwords": True});
            if (h.conn_timeout) {
                h.connect_timeout = remove h.conn_timeout;
            }
            setOptions(h);
        }

        #! transparently redirects object method calls to a remote server method call and returns the response
        auto methodGate(string api) {
            return doCallIntern(api, argv);
        }

        #! transparently redirects object member references to a remote server method call and returns the response
        auto memberGate(string api) {
            return doCallIntern(api, argv);
        }
    }

    #! class used to call the Qorus REST API for a remote Qorus instance
    /** @see QorusSystemRestHelperBase for the method documentation
    */
    public class QorusSystemRestHelper inherits QorusSystemRestHelperBase {
        #! creates the object pointing to the first local listener for the current instance using the given user and password for connecting
        /** @param user the username for the connection
            @param pwd the password for the connection

            @since Qorus 3.0.2
        */
        constructor(string user, string pwd) : QorusSystemRestHelperBase({"url": UserApi::qorusGetLocalUrl(user, pwd)},
                True) {
        }

        #! creates the object pointing to the first local listener for the current instance
        /** @since Qorus 3.0.2
        */
        constructor() : QorusSystemRestHelperBase({"url": UserApi::qorusGetLocalUrl()}, True) {
        }

        #! creates the object with the configuration given
        constructor(hash<auto> info) : QorusSystemRestHelperBase(QorusSystemRestHelperBase::toConfig(info), True) {
        }

        #! creates the object with the configuration given by the name of the @ref remoteconn "remote instance"
        constructor(string name) : QorusSystemRestHelperBase(QorusSystemRestHelperBase::toConfig(
                    Qorus.remotemonitor.getInfo(name, {"with_passwords": True})
                ), True) {
        }

        autoSetUrl(*hash<auto> opts) {
            # this method not called with this class
        }

        #! logs a warning
        private warning(string fmt) {
            Qorus.logArgs(LoggerLevel::INFO, fmt, argv);
        }

        auto restDo(string m, string path, auto args, *hash<auto> hdr, *hash<auto> opt, *reference<hash<auto>> info) {
            auto rv = doRequest(m, path, args, \info, True, hdr);
            return rv.body;
        }
    }
}

# internal api: call most non-service system APIs as the current (or other) user
auto sub call_system_api_as_user(string call, softlist args, *string user, bool useTLDContext) {
    return Qorus.callCoreFunction("call_system_api_as_user_tld", call, args, user,
        useTLDContext ? tld.("cx",) : NOTHING);
}

# these functions required for the remote service API are also required for Mapper modules imported in qwf and qjob
# program objects
*hash<auto> sub qorus_api_svc_try_get_wf_static_data() {
    return SMC.tryGetStaticData();
}

*hash<auto> sub qorus_api_svc_try_get_wf_dynamic_data() {
    return SMC.tryGetDynamicData();
}

*hash<auto> sub qorus_api_svc_try_get_wf_temp_data() {
    return SMC.tryGetTempData();
}
