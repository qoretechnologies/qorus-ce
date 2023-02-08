
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

#! main Qorus namespace
public namespace OMQ {
#! class for local REST API calls
/** @since Qorus 4.1
*/
public class QorusLocalRestHelper {
    #! makes a local REST request and returns the response
    /** @param m the HTTP method in upper case
        @param path the REST URI path
        @param args the arguments in the message body for the request

        @return the response from the server
    */
    auto doRequest(string m, string path, *hash<auto> args) {
        return _priv_call_rest_api(m, path, args);
    }

    #! makes a local REST \c GET request and returns the response
    /** @param path the REST URI path
        @param args the arguments in the message body for the request

        @return the response from the server

        @note \c GET requests should not contain a message body
    */
    auto get(string path, *hash<auto> args) {
        return doRequest("GET", path, args);
    }

    #! makes a local REST \c PUT request and returns the response
    /** @param path the REST URI path
        @param args the arguments in the message body for the request

        @return the response from the server
    */
    auto put(string path, *hash<auto> args) {
        return doRequest("PUT", path, args);
    }

    #! makes a local REST \c POST request and returns the response
    /** @param path the REST URI path
        @param args the arguments in the message body for the request

        @return the response from the server
    */
    auto post(string path, *hash<auto> args) {
        return doRequest("POST", path, args);
    }

    #! makes a local REST \c DELETE request and returns the response
    /** @param path the REST URI path
        @param args the arguments in the message body for the request

        @return the response from the server
    */
    auto del(string path, *hash<auto> args) {
        return doRequest("DELETE", path, args);
    }
}
}
