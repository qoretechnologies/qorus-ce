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
class QorusHttpApiManagementHandler inherits QorusAbstractApiManager {
    public {
        const CS_REQUIRE_CLIENT_CERT = "REQUIRE-CLIENT-CERT";
        const CS_NO_CLIENT_CERT_REQUIRED = "NO-CLIENT-CERT-REQUIRED";
        const CS_REQUEST_CLIENT_CERT = "REQUEST-CLIENT-CERT";

        const SSL_MAP = {
            CS_REQUIRE_CLIENT_CERT: SSL_VERIFY_FAIL_IF_NO_PEER_CERT | SSL_VERIFY_PEER,
            CS_NO_CLIENT_CERT_REQUIRED: SSL_VERIFY_NONE,
            CS_REQUEST_CLIENT_CERT: SSL_VERIFY_PEER,
        };

        const CS_FORMAT_PEM = "PEM";
        const CS_FORMAT_DER = "DER";
        const CS_FORMAT_AUTO = "AUTO";

        const FORMAT_MAP = {
            CS_FORMAT_PEM: True,
            CS_FORMAT_DER: True,
            CS_FORMAT_AUTO: True,
        };

        #! HTTP-based API profile options
        const HttpApiProfileOptions = {
            "root-uri": <ApiOptionInfo>{
                "type": "string",
                "desc": "The root URI path for the API",
                "required": True,
            },
            "listener-bind-address": <ApiOptionInfo>{
                "type": "*string",
                "desc": "The optional bind address for a dedicated listener; if not set, then the API handler will "
                    "bind on all Qorus system listeners as a global handler",
                "default_value": NOTHING,
            },
            "listener-cert-location": <ApiOptionInfo>{
                "type": "*string",
                "desc": "An optional X.509 certificate location name for a dedicated listener; location resolved "
                    "with `UserApi::getTextFileFromLocation()` or `UserApi::getBinaryFileFromLocation()` depending "
                    "on the value of `listener-cert-format` (ex: `file://$OMQ_DIR/user/certs/my-cert.pem`)",
                "default_value": NOTHING,
            },
            "listener-cert-format": <ApiOptionInfo>{
                "type": "string",
                "desc": "possible values giving the format of the data defined by `listener-cert-location`:\n"
                    "- **`PEM`**: PEM format (text)\n"
                    "- **`DER`**: DER format (binary)\n"
                    "- **`AUTO`**: try to determine the format automatically",
                "allowed_values": (
                    "AUTO",
                    "PEM",
                    "DER",
                ),
                "default_value": "AUTO",
            },
            "listener-key-location": <ApiOptionInfo>{
                "type": "*string",
                "desc": "An optional private key resource name for a dedicated listener; location resolved with "
                    "`UserApi::getTextFileFromLocation()` or `UserApi::getBinaryFileFromLocation()` depending on the "
                    "value of `listener-key-format` (ex: `file://$OMQ_DIR/user/certs/my-key.pem`)",
                "default_value": NOTHING,
            },
            "listener-key-format": <ApiOptionInfo>{
                "type": "string",
                "desc": "possible values giving the format of the data defined by `listener-key-location`:\n"
                    "- **`PEM`**: PEM format (text)\n"
                    "- **`DER`**: DER format (binary)\n"
                    "- **`AUTO`**: try to determine the format automatically",
                "allowed_values": (
                    "AUTO",
                    "PEM",
                    "DER",
                ),
                "default_value": "AUTO",
            },
            "listener-key-password": <ApiOptionInfo>{
                "type": "*string",
                "desc": "An optional password to PEM private key data for a dedicated listener",
                "default_value": NOTHING,
            },
            "listener-ssl-mode": <ApiOptionInfo>{
                "type": "string",
                "desc": "Set the SSL mode",
                "allowed_values": (
                    "REQUIRE-CLIENT-CERT",
                    "NO-CLIENT-CERT-REQUIRED",
                    "REQUEST-CLIENT-CERT",
                ),
                "default_value": "NO-CLIENT-CERT-REQUIRED",
            },
            "listener-accept-all-certs": <ApiOptionInfo>{
                "type": "bool",
                "desc": "Flag to accept all client certificates",
                "default_value": True,
            },
            "listener-capture-client-certs": <ApiOptionInfo>{
                "type": "bool",
                "desc": "Flag to capture client certificates",
                "default_value": False,
            },
            "listener-allow-sharing": <ApiOptionInfo>{
                "type": "bool",
                "desc": "Allow multiple Qorus services to bind handlers to the same listener",
                "default_value": True,
            },
            "auth-name": <ApiOptionInfo>{
                "type": "string",
                "desc": "A string identifying the authenticator; the following values are allowed:\n"
                    "- **`default`**: the default Qorus authenticator; new connections must have valid credentials "
                        "for Qorus\n"
                    "- **`default-basic`**: the same as **`default`** except in case of an unauthorized request, a "
                        "`WWW-Authenticate` header is returned indicating that HTTP basic authentication is "
                        "required\n"
                    "- **`permissive`**: no authentication is required; all requests are automatically accepted\n"
                    "- **`cookie`**: same as `default` with also support for cookie-based authentication; the cookie "
                        "name is defined with the `auth-cookie` config item",
                "allowed_values": (
                    "permissive",
                    "default",
                    "default-basic",
                    "cookie",
                ),
                "default_value": "default",
            },
            "auth-cookie": <ApiOptionInfo>{
                "type": "string",
                "desc": "A string providing the name of the cookie for cookie-based authentication, only used when "
                    "`auth-name` is `cookie`",
                "default_value": "qorus_auth_token",
            },
            "auth-redirect": <ApiOptionInfo>{
                "type": "*string",
                "desc": "A string providing the URL to redirect unauthenticated requests; only used when `auth-name` "
                    "is `cookie`",
                "default_value": NOTHING,
            },
        };
    }

    constructor(LocalQorusService service, hash<auto> api_manager) : QorusAbstractApiManager(service, api_manager) {
    }

    hash<HttpBindOptionInfo> setupHandler(AbstractServiceHttpHandler handler, hash<auto> api_profile_options) {
        hash<HttpBindOptionInfo> bind_options = <HttpBindOptionInfo>{
            "allow_listener_sharing": api_profile_options."listener-allow-sharing",
        };

        if (*string bind = api_profile_options."listener-bind-address") {
            ServiceApi::logInfo("REST API manager: bind address: %y", bind);

            hash<HttpListenerOptionInfo> info = http_get_listener_options_from_bind(bind);
            if (*string location = api_profile_options."listener-cert-location") {
                data cert_data = getFileData(location, api_profile_options."listener-cert-format");
                info.cert = new SSLCertificate(cert_data);
            }
            if (*string location = api_profile_options."listener-key-location") {
                data key_data = getFileData(location, api_profile_options."listener-key-format");
                if (key_data.typeCode() == NT_STRING) {
                    info.key = new SSLPrivateKey(key_data, api_profile_options."listener-key-password");
                } else {
                    info.key = new SSLPrivateKey(key_data);
                }
            }
            if (api_profile_options."listener-accept-all-certs") {
                info.ssl_accept_all_certs = True;
            }
            if (api_profile_options."listener-capture-client-certs") {
                info.get_remote_certs = True;
            }
            info.ssl_verify_flags = SSL_MAP{api_profile_options."listener-ssl-mode"};
            ServiceApi::logInfo("REST API manager: setup HTTP%s handler with bind arg: %y", info.cert ? "S" : "",
                info);

            handler.addListener(info);
        }

        return bind_options;
    }

    static private data getFileData(string location, string format) {
        switch (format) {
            case CS_FORMAT_PEM:
                return UserApi::getTextFileFromLocation(location);
            case CS_FORMAT_DER:
                return UserApi::getBinaryFileFromLocation(location);
        }
        # get a binary and check for non-ascii bytes instead of checking the file's extension
        binary file_data = UserApi::getBinaryFileFromLocation(location);
        try {
            # this will throw an excption if there is non-ascii data in the string
            return binary_to_string(file_data, "ASCII");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "ENCODING-CONVERSION-ERROR") {
                return file_data;
            }
            rethrow;
        }
    }
}
}
