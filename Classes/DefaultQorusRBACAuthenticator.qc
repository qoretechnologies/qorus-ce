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

#! main Qorus system namespace
public namespace OMQ {
#! Class for authenticating with standard Qorus RBAC authentication (Enterprise Edition only)
/** @see
    - @ref OMQ::DefaultQorusRBACBasicAuthenticator
    - @ref RBAC
    - @ref rbac-security
    - @ref rbac-external

    @note This class is only included for API compatibility with the Enterprise Edition; In the Community Edition,
    this class allows all requests
*/
class DefaultQorusRBACAuthenticator inherits public AbstractAuthenticator {
    #! Returns the authentication realm as a string
    /** @return the authentication realm as a string; the value returned is \c "Qorus Integration Engine"
    */
    string getRealm() {
        return Qorus.rbac.getRealm();
    }

    #! Can be overridden to return a header with <tt>401 Unauthorized</tt> responses
    /** @return an empty hash

        For example to return a header that tells the caller to require basic authentication (which will cause web
        browsers to show a dialog box asking for a username and password before repeating the request); use the
        following:
        @code
private hash<auto> getAuthHeader() {
    return {"WWW-Authenticate": sprintf("Basic realm=%y", getRealm())};
}
        @endcode
    */
    private hash<auto> getAuthHeader(*hash<auto> cx) {
        # issue #2379: do not send any basic authentication header in Qorus ever
        return {};
    }
}

#! Class for authenticating with standard Qorus RBAC authentication with basic authentication (Enterprise Edition only)
/**
    @see
    - @ref RBAC
    - @ref rbac-security
    - @ref rbac-external

    @note This class is only included for API compatibility with the Enterprise Edition; In the Community Edition,
    this class allows all requests
*/
class DefaultQorusRBACBasicAuthenticator inherits public DefaultQorusRBACAuthenticator {
}

#! Class for authenticating with standard Qorus RBAC authentication based on a cookie (Enterprise Edition only)
/**
    @see
    - @ref RBAC
    - @ref rbac-security
    - @ref rbac-external

    @note This class is only included for API compatibility with the Enterprise Edition; In the Community Edition,
    this class allows all requests
*/
class QorusCookieAuthenticator inherits public DefaultQorusRBACAuthenticator {
    #! Creates the object with the argument giving the cookie name to use for authentication
    /** @param cookie the cookie to check for an authentication token
        @param redirect_url the URL to redirect unauthenticated requests to

        @note Arguments are ignored in the Community Edition
    */
    constructor(string cookie = "", *string redirect_url) {
    }
}
}
