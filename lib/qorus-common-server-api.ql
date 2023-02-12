# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file qorus-common-server-api.ql functions common to workflow, service, and job APIs

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

public namespace OMQ {
    #! global service access object; transparently loads and initializes services and redirects calls to service methods
    /** @par Example:
        @code{.py}
*hash rh = omqservice.system.info.searchReleases(("name": "qorus-user-rel1"));
        @endcode

        The @ref omqservice object is available in all user code in Qorus Integration Engine (server and client).  It
        provides transparent service loading and initialization when calling service methods.  That is; if a service
        is not loaded when referenced in a call using the ::omqservice object, Qorus will attempt to load and
        initialize the service before making the method call and returning the result.

        If a service cannot be found (it doesn’t exist) or cannot be initialized, an appropriate exception will be
        returned to the caller.

        @throw NO-SERVICE Service doesn’t exists (type or name invalid)
        @throw BAD-SERVICE-DEFINITION Service has an invalid definition and was not loaded; this should not happen in
        practice.
        @throw INCONSISTENT-SERVICE Service has only one of start or stop methods, but not both.
    */
    our QorusSystemServiceHelper omqservice;

    #! top-level class that allows transparent auto-loading and access to Qorus system and user services
    /** @see omqservice

        @note Do not instantiate this class directly; use the global ::omqservice object instead
    */
    class QorusSystemServiceHelper {
        public {
            #! ServiceGate object for system services
            ServiceGate system("system");
            #! ServiceGate object for user services
            ServiceGate user("user");
        }
    }

    #! ServiceGate allows autoloading of Qorus services on referenced
    /** @note This class is not designed to be used directly; use ::omqservice instead
    */
    class ServiceGate {
        private:internal {
            string type__;
        }
        #public {
        #    default ServiceMethodGate;
        #}

        #! creates the object with the given type
        constructor(string type) {
            self.type__ = type;
        }

        #! tries to load the service; then redirects to the ServiceMethodGate object for the service
        ServiceMethodGate memberGate(string m) {
            services.loadService(self.type__, m, False, sprintf("implicit load of %s.%s for service call", self.type__, m));
            return self{m};
        }
    }

    #! ServiceMethodGate provides a gateway to service methods
    /** @note This class is not designed to be used directly; use ::omqservice instead
    */
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
            return services.callMethod(type, name, m, argv);
        }

        #! redirects external calls to the service method
        auto externalMethodGateArgs(string m, auto args) {
            return services.callMethod(type, name, m, args, True);
        }

        #! redirects internal calls to the service method
        auto internalMethodGateArgs(string m, auto args) {
            return services.callMethod(type, name, m, args);
        }
    }

    #! class used to call the Qorus system API for a remote Qorus instance through the network API
    /** @see QorusSystemAPIHelperBase for the method documentation
    */
    public class QorusSystemAPIHelper inherits QorusSystemAPIHelperBase {
        #! creates the object based on the options passed
        /** @param opts optional hash with the following keys:
            - \c connect_timeout: the connection timeout in seconds
            - \c http_version: the HTTP version string (def: \c "1.1")
            - \c local_token_ttl: the time in seconds that local tokens are valid (only applies if
              \c use_local_token is \c true)
            - \c max_redirects: the maximum number of redirects
            - \c proxy: any HTTP/S proxy to use
            - \c timeout: the I/O timeout in seconds
            - \c url: the target URL
            - \c use_local_token: a boolean option; if \c true a local token with internal system permissions will be
              included in all requests; only valid for loopback connections to the current server
            @param init an optional initialization closure to be called with the RPC object as the sole argument

            @see ValidClientAPIOpts
        */
        constructor(*hash<auto> opts, *code init) : QorusSystemAPIHelperBase(QorusSystemAPIHelperBase::toConfig(opts), init) {
            if (opts.headers && opts.headers.typeCode() == NT_HASH) {
                addDefaultHeaders(opts.headers);
            }
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
        constructor(string user, string pwd)
                : QorusSystemRestHelperBase({"url": UserApi::qorusGetLocalUrl(user, pwd)}, True) {
        }

        #! creates the object pointing to the first local listener for the current instance
        /** This method acquires an authentication token automatically that provides internal system access to Qorus
            APIs and data

            @since Qorus 3.0.2
        */
        constructor() : QorusSystemRestHelperBase({"url": UserApi::qorusGetLocalUrl()}, True) {
        }

        #! creates the object with the configuration given
        constructor(hash<auto> info) : QorusSystemRestHelperBase(QorusSystemRestHelperBase::toConfig(info), True) {
        }

        #! creates the object with the configuration given by the name of the remote instance
        constructor(string name) : QorusSystemRestHelperBase(QorusSystemRestHelperBase::toConfig(
                    Qorus.remotemonitor.getInfo(name, {"with_passwords": True})
                ), True) {
        }

        autoSetUrl(*hash<auto> opts) {
            # this method is not called with this class
        }

        #! logs a warning
        private warning(string fmt) {
            Qorus.logArgs(Logger::LoggerLevel::INFO, fmt, argv);
        }

        auto restDo(string m, string path, auto args, *hash<auto> hdr, *hash<auto> opt, *reference<hash> info) {
            auto rv = doRequest(m, path, args, \info, True, hdr);
            return rv.body;
        }
    }
}
