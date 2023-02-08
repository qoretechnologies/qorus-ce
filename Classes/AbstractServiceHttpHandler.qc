# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file AbstractServiceHttpHandler.qc provides the interface to the system's HTTP server to Qorus services

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%push-parse-options

%new-style
%require-types
%strict-args
%enable-all-warnings

const AllowedServiceMethods = {
    "getResource": True,
    "tryGetResource": True,
};

#! this class is used to customize and control the behavior of the Qorus HTTP server as it redirects URLs to services
/** If any listeners are added to the AbstractServiceHttpHandler object with
    @ref OMQ::AbstractServiceHttpHandler::addListener() "addListener()", then the URL set in the object is only bound
    to the new listeners specified in this object.

    Otherwise, the URL is bound to all listeners in the system HTTP server.  Override the
    @ref OMQ::AbstractServiceHttpHandler::handleRequestImpl() "handleRequestImpl()" method to handle HTTP requests.
*/
public class OMQ::AbstractServiceHttpHandler inherits public HttpServer::AbstractHttpRequestHandler {
    public {
        #! The path string or regex to match incoming requests
        string url;

        #! the content-type to check
        *softlist<auto> content_type;

        #! list of special headers; if a request has any of these HTTP headers, then the requests will match this handler
        *softlist<auto> special_headers;

        #! list of listener info; do not write to this list directly
        /** use AbstractServiceHttpHandler::addListener() instead of writing to this list directly
            (the internal format may change)
        */
        list<auto> listeners = ();

        #! thread-local data to add before calling handleRequest()
        OMQ::ThreadLocalData otld();

        #! a closure that allows specific Service methods to be called
        code svcc;

        #! a closure that allows any Service methods to be called
        code svc_method_call;

        #! the type/heading for user HTTP services
        *string utype;

        #! the title for user HTTP services
        *string utitle;

        #! the URL for user HTTP services
        *string uurl;

        #! if the path is a regex or a string
        bool isregex;

        #! the default resource to serve
        *string default_resource;

        #! service info hash
        hash<auto> svcinfo;

        const MembersToSerialize = (
            "decompress",
            "decompress_to_string",
            "stream",
            "timeout_ms",
            "url",
            "listeners",
            "content_type",
            "special_headers",
            "isregex",
            "default_resource",
            "utype",
            "utitle",
            "uurl",
        );
    }

    private:internal {
        AbstractQorusService svc;
    }

    #! creates the object with the given arguments
    /** @param n_path the regular expression for the path to match on incoming requests (ex \c "^my-service(\?|/|$)");
        note see the \a n_isregex parameter to treat this argument as a URL root instead of a regular expression
        @param n_content_type an optional list of Content-Types to match on incoming requests
        @param n_special_headers an optional list of special headers to check that will indicate a match with this
        handler
        @param n_auth the @ref HttpServer::AbstractAuthenticator "AbstractAuthenticator" for the object; if no
        argument is passed, then no authentication is required for any connection
        @param n_isregex if @ref True "True", then the \a path argument is treated as a regular expression pattern,
        otherwise it is treated as a literal URL root; it's normally recommended to set this argument to
        @ref False "False" so that @ref service_file_resources "service file resources" can be matched and served;
        this method has the default value @ref True "True" only for backwards compatibility

        @par Example:
        @code{.py}
class MyHttpHandler inherits OMQ::AbstractServiceHttpHandler {
    constructor() : OMQ::AbstractServiceHttpHandler("my-service", "text/tab-separated-values", NOTHING, NOTHING, False) {
    }
}
        @endcode
     */
    constructor(string n_path, *softlist<auto> n_content_type, *softlist<auto> n_special_headers,
            HttpServer::AbstractAuthenticator n_auth = new DefaultQorusRBACAuthenticator(), bool n_isregex = True)
            : AbstractHttpRequestHandler(n_auth) {
%ifdef QorusDebugInternals
        # this file is shraed between the server & client, so we need the defines for QDBG_*() calls
        QDBG_ASSERT(ensure_tld());
%endif
        otld.clear();
        otld.svc = tld.svc;
        url = n_path;
        content_type = n_content_type;
        special_headers = n_special_headers;

        # do not reference tld in a closure since this would add locking to a thread-local variable
        svc = tld.svc;
        svcc = auto sub (string m) {
            if (AllowedServiceMethods{m}) {
                return call_object_method_args(svc, m, argv);
            }
            throw "SERVICE-ERROR", sprintf("illegal service method %y called", m);
        };
        svc_method_call = auto sub (string m) {
            return call_object_method_args(svc, m, argv);
        };
        isregex = n_isregex;
        svcinfo = svc{"name", "version", "serviceid"};
    }

    hash<auto> getRemoteConfig() {
        # FIXME: need reflection
        # until we have reflection, this is a hack to see if the given methods are available in the current class
        # also this only partially works due to the way get_method_list() works, which returns the methods implemented
        # in the current class, but not of any parent classes, even if the methods are public
        hash<auto> mh = map {$1: True}, get_method_list(self);

        string auth_str;
        if (!exists auth) {
            auth_str = "none";
        } else if (auth instanceof DefaultQorusRBACAuthenticator) {
            auth_str = "def";
        } else {
            auth_str = "remote";
        }

        hash<auto> rv = self{getMembersToSerialize()} + {
            "auth" : auth_str,
            # FIXME: needs reflection to determine if this method is overriden above this class
            "has_handle_request": mh.handleRequest ?? False,
            # FIXME: needs reflection to determine if this method is overriden above this class
            "has_handle_request_impl": mh.handleRequestImpl ?? False,
        };

        return rv;
    }

    string getUniqueHash() {
        string base = getUniqueHashBaseImpl();
        QDBG_LOG("AbstractServiceHttpHandler::getUniqueHash() %y -> %y", base, base.toSHA512());
        return base.toSHA512();
    }

    private string getUniqueHashBaseImpl() {
        string base = self.className() + ";" + url;
        if (content_type) {
            base += ";" + content_type;
        }
        if (special_headers) {
            base += ";" + (foldl $1 + "," + $2, special_headers);
        }
        base += ";" + isregex.toString();
        if (default_resource) {
            base += ";" + default_resource;
        }
        if (utype) {
            base += sprintf(";%s,%s,%s", utype, utitle, uurl);
        }
        return base;
    }

    list<string> getMembersToSerialize() {
        return MembersToSerialize;
    }

    #! returns a hash with info about the linked service
    hash<auto> getServiceInfo() {
        return svcinfo;
    }

    #! adds a listener from a bind string in the format: \c "address:port" (ex: \c "192.168.20.1:8011")
    /** If any listeners are added to the AbstractServiceHttpHandler object, then the URL set in the object is only
        bound to the new listeners specified in this object

        @param opt HTTP listener parameters

        @throw ADDLISTENER-ERROR key_path argument provided, but no certificate provided

        @since Qorus 4.0.3
     */
    addListener(hash<HttpServer::HttpListenerOptionInfo> opt) {
        listeners += {
            "bind": exists opt.service
                ? (exists opt.node ? sprintf("%s:%s", opt.node, opt.service) : opt.service)
                : opt.node,
            "opt": opt,
        };
    }

    #! adds a listener from a bind string in the format: \c "address:port" (ex: \c "192.168.20.1:8011")
    /** If any listeners are added to the AbstractServiceHttpHandler object, then the URL set in the object is only
        bound to the new listeners specified in this object

        @param bind the address:port string or port number to bind the listener to
        @param opt HTTP listener parameters

        @throw ADDLISTENER-ERROR key_path argument provided, but no certificate provided

        @since Qorus 4.0.3
     */
    addListener(softstring bind, hash<HttpServer::HttpListenerOptionInfo> opt) {
        listeners += {
            "bind": bind,
            "opt": opt,
        };
    }

    #! adds a listener from a bind string in the format: \c "address:port" (ex: \c "192.168.20.1:8011")
    /** If any listeners are added to the AbstractServiceHttpHandler object, then the URL set in the object is only
        bound to the new listeners specified in this object

        @param bind the address:port string or port number to bind the listener to
        @param cert_path optional path to an X.509 certificate file
        @param key_path optional path to a private key file for an X.509 certificate
        @param key_password optional password to the private key
        @param opt HTTP listener parameters

        @throw ADDLISTENER-ERROR key_path argument provided, but no certificate provided
     */
    addListener(softstring bind, *string cert_path, *string key_path, *string key_password,
            *hash<HttpServer::HttpListenerOptionInfo> opt) {
        if (exists key_path && !exists cert_path) {
            throw "ADDLISTENER-ERROR", sprintf("key path (%y) provided, but no cert path provided in call to "
                "AbstractServiceHttpHandler::addListener()", key_path);
        }
        listeners += {
            "bind": bind,
            "cert_path": cert_path,
            "key_path": key_path,
            "key_password": key_password,
            "opt": opt,
        };
    }

    #! adds a listener from a bind string in the format: \c "address:port" (ex: \c "192.168.20.1:8011")
    /** If any listeners are added to the AbstractServiceHttpHandler object, then the URL set in the object is only
        bound to the new listeners specified in this object

        @param bind the address:port string or port number to bind the listener to
        @param cert optional X.509 certificate object
        @param key optional private key for an X.509 certificate
        @param opt HTTP listener parameters

        @throw ADDLISTENER-ERROR key argument provided, but no certificate provided
     */
    addListener(softstring bind, *Qore::SSLCertificate cert, *Qore::SSLPrivateKey key,
            *hash<HttpServer::HttpListenerOptionInfo> opt) {
        if (exists key && !exists cert)
            throw "ADDLISTENER-ERROR", "key argument provided, but no certificate provided in call to "
                "AbstractServiceHttpHandler::addListener()";

        listeners += {
            "bind": bind,
            "cert": cert,
            "key": key,
            "opt": opt,
        };
    }

    #! adds a list of listeners from hash elements describing the listener
    /** If any listeners are added to the AbstractServiceHttpHandler object, then the URL set in the object is only
        bound to the new listeners specified in this object

        @param l list of listeners; each element should be a hash with the following keys:
        - \c "bind": (required) a bind string in the format: \c "address:port" (ex: \c "192.168.20.1:8011") or an
          integer port, meaning to bind on all interfaces on that port
        - \c "cert_file": (optional) path to an X.509 certificate file (do not include both \c "cert_file" and
          \c "cert")
        - \c "cert": (optional) a Qore::SSLCertificate object (do not include both \c "cert_file" and \c "cert")
        - \c "key_file": (optional) path to a private key file for an X.509 certificate (do not include both
          \c "key_file" and \c "key")
        - \c "key": (optional) a Qore::SSLPrivateKey object (do not include both \c "key_file" and \c "key")

        @throw ADDLISTENERS-ERROR invalid element in argument list
     */
    addListeners(softlist<auto> l) {
        # check parameters
        foreach auto e in (l) {
            if (e.typeCode() != NT_HASH)
                throw "ADDLISTENERS-ERROR", sprintf("element %d (starting from 0) in the list argument to "
                    "AbstractServiceHttpHandler::addListeners() is not a hash (type: %y)", $#, type(e));
            if (exists e.cert_file && exists e.cert)
                throw "ADDLISTENERS-ERROR", sprintf("both 'cert' and 'cert_file' provided in element %d "
                    "(starting from 0) in the list argument to AbstractServiceHttpHandler::addListeners()", $#);
            if (exists e.key_file && exists e.key)
                throw "ADDLISTENERS-ERROR", sprintf("both 'key' and 'key_file' provided in element %d "
                    "(starting from 0) in the list argument to AbstractServiceHttpHandler::addListeners()", $#);
            if ((exists e.key_file || exists e.key) && !exists e.cert_file && !exists e.cert)
                throw "ADDLISTENERS-ERROR", sprintf("a key was provided in element %d (starting from 0) in the list "
                    "argument to AbstractServiceHttpHandler::addListeners(), but no certificate was provided", $#);
        }
        listeners += l;
    }

    #! called before handleRequest()
    /** any data returned here will be given to restoreThreadLocalData() after the handleRequest() call
    */
    final *hash<auto> saveThreadLocalData() {
%ifdef QorusServer
        ensure_create_tld();
        OMQ::ThreadLocalData rv();
        rv.tldCopy(tld);
        tld.add(otld);
        return rv.toHash();
%endif
    }

    #! called after handleRequest() with any data returned from saveThreadLocalData()
    final restoreThreadLocalData(*hash<auto> data) {
%ifdef QorusDebugInternals
        QDBG_ASSERT(ensure_tld());
%endif
        tld.fromHash(data);
    }

    #! logs to the service log file
    log(int ll, string fmt) {
%ifdef QorusServer
        call_function(svc_method_call, "logArgs", convert_old_log_level(ll), vsprintf(fmt, argv));
%else
        delete argv;
%endif
    }

    logInfo(string fmt) {
        logInfoArgs(fmt, argv);
    }

    logError(string fmt) {
        logErrorArgs(fmt, argv);
    }

    logDebug(string fmt) {
        logDebugArgs(fmt, argv);
    }

    logInfoArgs(string fmt, auto args) {
        call_function(svc_method_call, "logInfo", vsprintf(fmt, args));
    }

    logErrorArgs(string fmt, auto args) {
        call_function(svc_method_call, "logError", vsprintf(fmt, args));
    }

    logDebugArgs(string fmt, auto args) {
        call_function(svc_method_call, "logDebug", vsprintf(fmt, args));
    }

    #! sets heading and title for user HTTP services
    setUserIndexInfo(string heading, string title, string url) {
%ifdef QorusServer
        utype = heading;
        utitle = title;
        if (url =~ /:\/\//) {
            uurl = url;
        } else {
            if (listeners) {
                string bu = http_get_url_from_bind(listeners[0].bind, Qorus.getLocalAddress());
                if (listeners[0].cert && bu !~ /https:/)
                    bu =~ s/^http:/https:/;
                uurl = bu + "/" + url;
            } else {
                uurl = UserApi::qorusGetLocalUrl() + "/" + url;
            }
        }
%endif
    }

    #! clears heading and title into for user HTTP services
    /** @since Qorus 4.0
    */
    clearUserIndexInfo() {
        remove utype;
        remove utitle;
        remove uurl;
    }

    #! this method ensures that thread-local data is set properly
    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr,
            *data body) {
        # issue #3534: set service thread context
        setThreadContext(cx);
        return AbstractHttpRequestHandler::handleRequest(listener, s, cx, hdr, body);
    }

    #! This method calls handleRequestImpl() to service the request
    /** If handleRequestImpl() returns @ref nothing, then it tries to automatically serve
        @ref service_file_resources "service file resources" or serve the default resource if no resource can be
        matched

        @param cx call context hash; this hash will have the following keys:
        - \c socket: the bind address used to bind the listener (\c "socket-info" provides more detailed information)
        - \c socket-info: a hash of socket information for the listening socket (as returned by
          @ref Qore::Socket::getSocketInfo() "Socket::getSocketInfo()" "Socket::getSocketInfo()")
        - \c peer-info: a hash of socket information for the remote socket (as returned by
          @ref Qore::Socket::getPeerInfo() "Socket::getPeerInfo()" "Socket::getPeerInfo()")
        - \c url: a hash of broken-down URL information (as returned from @ref Qore::parse_url())
        - \c id: the unique HTTP connection ID
        - \c listener-id: the HTTP server listener ID (see
          @ref HttpServer::HttpServer::getListenerInfo() "HttpServer::getListenerInfo()")
        - \c ssl: if the connection with the client is an SSL/TLS connection, then this key will be present and will
          be @ref True
        @param hdr incoming header hash; all keys will be converted to lower-case, additionally the following keys
        will be present:
        - \c method: the HTTP method received (ie \c "GET", \c "POST", etc)
        - \c path: the HTTP path given in the request, after processing by @ref Qore::decode_url()
        - \c http_version: the HTTP version number in the request (either \c "1.0" or \c "1.1")
        @param body message body, if any

        @return a hash with the following keys:
        - \c "code": the HTTP return code (see @ref HttpServer::HttpCodes)
        - \c "body": the message body to return in the response
        - \c "close": (optional) set this key to @ref True "True" if the connection should be unconditionally closed
          when the handler returns
        - \c "hdr": (optional) set this key to a hash of extra header information to be returned with the response

        The following keys are added to the \a cx argument when calling handleRequestImpl():
        - \c resource_path: the relative path without any query arguments and with the URL root stripped off (if the
          request was matched by the URL root, otherwise this will be the request path with any URI query arguments
          removed)
        - \c url_root: the root URL
        - \c isregex: if the \a url_root string is a regular expression or not (this is always @ref False "False" when
          this class is used)
        - \c hdr: this is added to the \a cx argument directly from the \a hdr argument, however it also includes the
          \c "params" key which holds the URI query parameters as returned in the \a params key from
          @ref HttpServer::parse_uri_query()

        To override the logic in this method and handle requests directly, override this method in your subclass.

        If handleRequestImpl() returns @ref nothing and no resource can be matched and served, then this method
        returns a 501 error code
     */
    hash<auto> handleRequest(hash<auto> cx, hash<auto> hdr, *data body) {
        # get resource path and "localize" it and strip off any query args
        string path = getRequestPath(hdr.path);

        # add URI query parameters to hdr if possible
        hdr.params = parse_uri_query(hdr.path).params;

        cx += {"resource_path": path, "url_root": url, "isregex": isregex, "hdr": hdr};

        {
            *hash<auto> h = handleRequestImpl(\cx, hdr, body);
            if (h)
                return h;
        }

        # handle requests for service file resources automatically
        if (hdr.method == "GET") {
            if (path) {
                *hash<auto> h = call_function(svcc, "tryGetResource", path, cx);
                if (h) {
                    logDebug("serving resource %y (%d bytes) %s", path, h.body.size(), h.hdr."Content-Type");
                    return h;
                } else {
                    logDebug("cannot find resource %y", path);
                }
            }

            if (default_resource)
                return call_function(svcc, "getResource", default_resource, cx);
        }

        logDebug("unhandled request for resource: %s", path);

        return {
            "code": 501,
            "body": sprintf("class %s did not handle the request and no service resource was available",
                self.className()),
            "close": True,
        };
    }

    final hash<auto> handleRequestExternImpl(hash<auto> cx, hash<auto> hdr, *data body) {
        *hash<auto> rv = handleRequestImpl(\cx, hdr, body);
        return {
%ifdef QorusServer
            "cx": get_cx(cx),
%else
            "cx": cx,
%endif
            "rv": rv,
        };
    }

    #! returns the request path with the common leading part of the URL and also any URI query argument stripped
    string getRequestPath(string hpath) {
        string path;
        if (!url)
            path = hpath;
        else {
            if (isregex) {
                list<string> l = regex_extract(hpath, url + "(.*)");
                if (l.last())
                    path = l.last();
                else
                    path = hpath;
            } else {
                if (hpath.equalPartialPath(url))
                    path = hpath.substr(url.size() + 1);
                else
                    path = hpath;
            }
        }
        # strip off any query arguments
        if (path)
            path =~ s/\?.*$//;
        return path;
    }

    #! This method is called by this class's handleRequest()
    /** This method is called before trying to service the request automatically based on
        @ref service_file_resources "service file resources"

        If this method returns a value; then the value is used to serve the request directly, otherwise, if it
        returns @ref nothing, Qorus will try to match <i>cx.resource_path</i> with a
        @ref service_file_resources "service file resource" and serve it automatically.

        @par Example:
        @code{.py}
class MyHttpHandler inherits OMQ::AbstractServiceHttpHandler {
    constructor() : OMQ::AbstractServiceHttpHandler("my-service", "text/tab-separated-values", NOTHING, NOTHING, False) {
    }

    *hash<auto> handleRequestImpl(hash<auto> cx, hash<auto> hdr, *data body) {
        logDebug("message received: hdr=%y", hdr);
        # similate a successful POST, otherwise serve service resources automatically
        if (cx.method == "POST")
            return {"code": 200, "body": "OK"};
    }
}
        @endcode

        @param cx call context hash; this hash will have the following keys:
        - \c hdr: this is a copy of the \a hdr argument, however it also includes the \c "params" key which holds the
          URI query parameters as returned in the \a params key from @ref HttpServer::parse_uri_query(); ex:
          \c hdr.host will contain the \c Host header from the incoming request
        - \c id: the unique HTTP connection ID
        - \c isregex: if the \a url_root string is a regular expression or not
        - \c listener-id: the HTTP server listener ID (see
          @ref HttpServer::HttpServer::getListenerInfo() "HttpServer::getListenerInfo()")
        - \c peer-info: a hash of socket information for the remote socket (as returned by
          @ref Qore::Socket::getPeerInfo() "Socket::getPeerInfo()")
        - \c resource_path: the resource path without any query arguments and with the URL root stripped off (if the
          request was matched by the URL root, otherwise this will be the request path with any URI query arguments
          removed)
        - \c socket: the bind address used to bind the listener (\c "socket-info" provides more detailed information)
        - \c socket-info: a hash of socket information for the listening socket (as returned by
          @ref Qore::Socket::getSocketInfo() "Socket::getSocketInfo()")
        - \c ssl: if the connection with the client is an SSL/TLS connection, then this key will be present and will
          be @ref True
        - \c url: a hash of broken-down URL information (as returned from @ref Qore::parse_url())
        - \c url_root: the root URL
        @param hdr incoming header hash; all keys will be converted to lower-case, additionally the following keys
        will be present:
        - \c method: the HTTP method received (ie \c "GET", \c "POST", etc)
        - \c path: the HTTP path given in the request, after processing by @ref Qore::decode_url()
        - \c http_version: the HTTP version number in the request (either \c "1.0" or \c "1.1")
        - \c params: holds the URI query parameters as returned in the \a params key from
          @ref HttpServer::parse_uri_query()
        @param body message body, if any

        @return either @ref nothing, meaning that Qorus should try to match <i>cx.resource_path</i> with a
        @ref service_file_resources "service file resource" and serve it automaticaly, or a hash with the following
        keys:
        - \c "code": the HTTP return code (see @ref HttpServer::HttpCodes)
        - \c "body": the message body to return in the response
        - \c "close": (optional) set this key to @ref True "True" if the connection should be unconditionally closed
          when the handler returns
        - \c "hdr": (optional) set this key to a hash of extra header information to be returned with the response

        @note
        - this method has the following additional keys in the \a cx hash: \c resource_path, \c url_root, and
          \c isregex
        - the default implementation simply returns @ref nothing for all requests; reimplement this method in a
          subclass to provide the required functionality
        - for @ref service_remote "remote services" running in independent @ref qsvc "qsvc" processes, no
          non-serializable data types can be added to \a cx, or the call will fail
     */
    *hash<auto> handleRequestImpl(reference<hash<auto>> cx, hash<auto> hdr, *data body) {
    }

    #! sets the default @ref service_file_resources "service file resource" to be rendered
    /** The default resource is rendered when the request is not matched to a resource and @ref handleRequestImpl()
        does not return a response
    */
    setDefaultResource(string name) {
%ifdef QorusDebugInternals
        QDBG_ASSERT(ensure_tld());
%endif
        tld.svc.checkDefaultResource(name);
        default_resource = name;
    }

    #! returns the AbstractStreamRequest object for handling chunked requests
    private AbstractStreamRequest getStreamRequestImpl(HttpListenerInterface listener, Socket s, hash<auto> cx,
            hash<auto> hdr, *data body) {
        return new RestStreamRequest(getServiceStreamRequestImpl(s, cx, hdr, body), listener, self, s, cx, hdr, body);
    }

    #! returns the AbstractStreamRequest object for handling chunked requests
    private AbstractServiceStream getServiceStreamRequestImpl(Socket s, hash<auto> cx, hash<auto> hdr, *data body) {
        throw "STREAM-ERROR", sprintf("please implement %s::getServiceStreamRequestImpl() to avoid this error",
            self.className());
    }

    #! for calling the getServiceStreamRequestImpl() externally
    static AbstractServiceStream getServiceStreamRequestExtern(AbstractServiceHttpHandler hr, Socket s, hash<auto> cx,
            hash<auto> hdr, *data body) {
        return hr.getServiceStreamRequestImpl(s, cx, hdr, body);
    }

    #! Sets the service thread context
    /** This should be called from HTTP I/O threads only; no attempt is made to save and restore the thread-local data
        on exit

        @note Does not set the thread context correctly; use the non static mnethod @ref setThreadContext() instead
    */
    static setServiceThreadContext(hash<auto> cx) {
        ensure_create_tld();
        # must overwrite thread-local data on each request in case sockets are reused
        tld.cx = cx;
%ifdef QorusCore
        # issue #3534: set service thread context
        tld._current_ix = "svc";
%endif
    }

    #! Sets the service thread context
    /** This should be called from HTTP I/O threads only; no attempt is made to save and restore the thread-local data
        on exit
    */
    setThreadContext(hash<auto> cx) {
        ensure_create_tld();
        # must overwrite thread-local data on each request in case sockets are reused
        tld.cx = cx;
%ifdef QorusCore
        # issue #3534: set service thread context
        tld += {
            "_current_ix": "svc",
            "svc": svc,
        };
%endif
    }
}

#! this class is used to define a @ref uiextensions "Qorus UI extension" in a Qorus service
/** @see
    - @ref OMQ::UserApi::Service::ServiceApi::uiExtensionRegister() "ServiceApi::uiExtensionRegister()"
    - @ref uiextensions for example code
*/
public class OMQ::QorusExtensionHandler inherits OMQ::AbstractServiceHttpHandler {
    public {}

    private {
        #! menu group
        string group;

        #! extension description
        string menuname;

        #! extension description
        string desc;

        const MembersToSerialize = AbstractServiceHttpHandler::MembersToSerialize + (
            "group",
            "menuname",
            "desc",
        );
    }

    #! creates the extension handler object from the arguments
    /** @param group the menu group name; extensions with the same group name will be grouped together in the
        extension menu
        @param menuname the menu name for this extension
        @param desc a descriptive string for the UI extension
    */
    constructor(string group, string menuname, string desc)
            : AbstractServiceHttpHandler("", NOTHING, NOTHING, NOTHING, False) {
        self.group = group;
        self.menuname = menuname;
        self.desc = desc;
    }

    private string getUniqueHashBaseImpl() {
        return sprintf("%s;%s;%s;%s", AbstractServiceHttpHandler::getUniqueHashBaseImpl(), group, menuname, desc);
    }

    list<string> getMembersToSerialize() {
        return MembersToSerialize;
    }

    #! returns the group name
    string getGroup() {
        return group;
    }

    #! returns the menu name
    string getMenuName() {
        return menuname;
    }

    #! returns the description
    string getDesc() {
        return desc;
    }
}

#! this class supports the implementation of HTTP file-based request handler
/** This class supports the automatic handling of files in a certain root directory as well as rendering of templates
*/
public class OMQ::ServiceFileHandler inherits WebUtil::FileHandler, OMQ::AbstractServiceHttpHandler {
    public {}

    #! create the object optionally with the given AbstractAuthenticator
    /** @param file_root the filesystem root directory for serving files
        @param url_root the root part of the URL path without the leading \c "/"
        @param opt an optional with one or more of the following option keys:
        - \c default_target: the default relative path to use if a request cannot be satisfied
        - \c po: the @ref parse_options "Program parse options" for the template file @ref Qore::Program "programs"
        - \c psetup: an optional @ref closure "closure" or @ref call_reference "call reference" taking a single
          @ref Qore::Program "Program" argument to be called when initializing template @ref Qore::Program "programs"
          to set up a custom template API, etc
        - \c auth: the HttpServer::AbstractAuthenticator for the object
        - \c error_level: the level of error reporting (0, 1, or 2)
    */
    constructor(string file_root, string url_root, *hash<auto> opt)
            : FileHandler(file_root, url_root, opt),
            AbstractServiceHttpHandler(file_root, NOTHING, NOTHING,
                opt.auth ? opt.auth : new DefaultQorusRBACAuthenticator(), False) {
    }

    #! this method ensures that thread-local data is set properly
    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr,
            *data body) {
        # issue #3534: set service thread context
        setThreadContext(cx);
        return cast<hash<HttpResponseInfo>>(FileHandler::handleRequest(listener, s, cx, hdr, body));
    }

    logInfo(string fmt) {
        logInfoArgs(fmt, argv);
    }

    logError(string fmt) {
        logErrorArgs(fmt, argv);
    }

    logDebug(string fmt) {
        logDebugArgs(fmt, argv);
    }
}

#! This class is used to customize and control the behavior of the Qorus HTTP server
/** This class redirects URLs to Qorus services providing HTTP-based REST services
*/
/** If any listeners are added to the AbstractServiceRestHandler object, then the URL set in the object is only bound
    to the new listeners specified in this object.

    Otherwise, the URL is bound to all listeners in the system HTTP server.
*/
public class OMQ::AbstractServiceRestHandler inherits OMQ::AbstractServiceHttpHandler, RestHandler::RestHandler {
    public {}

    #! creates the object with the given arguments
    /** @param path the string or regular expression for the path to match on incoming requests (ex \c "my-service")
        @param isregex determines if \a path is a regular expression or simply the leading path component
        @param auth the HttpServer::AbstractAuthenticator for the object; if no argument is passed, then the system
        authenticator is used; meaning all users can connect without authentication
        @param validator an optional REST schema validator object to validate and process incoming and outgoing requests

        @par Example:
        @code{.py}
class MyRestHandler inherits AbstractServiceRestHandler {
    constructor() : AbstractServiceRestHandler("my-service", svc_get_resource_data("my-swagger-schema-v1.0.yaml")) {
    }
}
        @endcode

        @note that the path argument defaults to a string instead of a regular expression in this constructor
    */
    constructor(string path, bool isregex = False,
            HttpServer::AbstractAuthenticator auth = new DefaultQorusRBACAuthenticator(),
            *RestSchemaValidator::AbstractRestSchemaValidator validator)
            : RestHandler(auth, validator), AbstractServiceHttpHandler(path, NOTHING, NOTHING, auth, isregex) {
    }

    #! creates the object with the given arguments
    /** @param path the string or regular expression for the path to match on incoming requests (ex \c "my-service")
        @param auth the HttpServer::AbstractAuthenticator for the object; if no argument is passed, then the system
        authenticator is used; meaning all users can connect without authentication
        @param validator an optional REST schema validator object to validate and process incoming and outgoing requests

        @par Example:
        @code{.py}
class MyRestHandler inherits AbstractServiceRestHandler {
    constructor() : AbstractServiceRestHandler("my-service", svc_get_resource_data("my-swagger-schema-v1.0.yaml")) {
    }
}
        @endcode

        @note that the path argument defaults to a string instead of a regular expression in this constructor

        @since Qorus 4.0.3
    */
    constructor(string path, HttpServer::AbstractAuthenticator auth = new DefaultQorusRBACAuthenticator(),
            *RestSchemaValidator::AbstractRestSchemaValidator validator)
            : RestHandler(auth, validator), AbstractServiceHttpHandler(path, NOTHING, NOTHING, auth, False) {
    }

    #! this method ensures that thread-local data is set properly
    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr,
            *data body) {
        # issue #3534: set service thread context
        setThreadContext(cx);
        return RestHandler::handleRequest(listener, s, cx, hdr, body);
    }

    hash<auto> getRemoteConfig() {
        return AbstractServiceHttpHandler::getRemoteConfig() + {
            "type": "REST",
            "validator": validator instanceof NullRestSchemaValidator ? "null" : "remote",
        };
    }

    #! removes the root path from the URL
    removeRootPath(reference path) {
        # remove root url from path
        path = regex_subst(path, "^" + url, "");
        #logDebug("path: %y url: %y", path, url);
    }

    # logs errors when the response cannot be serialized
    responseSerializationError(hash<auto> cx, hash<auto> aih, hash<auto> rv) {
        logInfo("cannot serialize response; client accepts: %y", aih.keys());
        logDebug("request: %y discarding response: %y", cx.url.path, rv.body);
    }

    logInfo(string fmt) {
        logInfoArgs(fmt, argv);
    }

    logError(string fmt) {
        logErrorArgs(fmt, argv);
    }

    logDebug(string fmt) {
        logDebugArgs(fmt, argv);
    }

    RestSchemaValidator::AbstractRestSchemaValidator getValidator() {
        return validator;
    }
}

#! This class is used to customize and control the behavior of the Qorus HTTP server with SOAP messages
/** @since Qorus 5.1.30
*/
/** This class redirects URLs to Qorus services providing HTTP-based SOAP services
*/
/** If any listeners are added to the AbstractServiceSoapHandler object, then the URL set in the object is only bound
    to the new listeners specified in this object.

    Otherwise, the URL is bound to all listeners in the system HTTP server.
*/
public class OMQ::AbstractServiceSoapHandler inherits OMQ::AbstractServiceHttpHandler
%ifdef QorusServer
        , SoapHandler::SoapHandler
%endif
        {

    public {}

   #! creates the object with the given arguments
    /** @param path the string or regular expression for the path to match on incoming requests (ex \c "my-service")
        @param auth the HttpServer::AbstractAuthenticator for the object; if no argument is passed, then the system
        authenticator is used; meaning all users can connect without authentication

        @par Example:
        @code{.py}
class MySoapHandler inherits AbstractServiceSoapHandler {
    constructor() : AbstractServiceSoapHandler("my-service")) {
    }
}
        @endcode

        @note that the path argument defaults to a string instead of a regular expression in this constructor

        @since Qorus 5.1.30
    */
    constructor(string path, HttpServer::AbstractAuthenticator auth = new DefaultQorusRBACAuthenticator()) :
%ifdef QorusServer
            SoapHandler(auth, NOTHING, Qorus.getDebugSystem()),
%endif
            AbstractServiceHttpHandler(path, NOTHING, NOTHING, auth, False) {
    }

%ifdef QorusServer
    #! this method ensures that thread-local data is set properly
    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr,
            *data body) {
        # issue #3534: set service thread context
        setThreadContext(cx);
        return SoapHandler::handleRequest(listener, s, cx, hdr, body);
    }

    #! This method is called by this class's handleRequest()
    /** This method is called before trying to service the request automatically based on
        @ref service_file_resources "service file resources"
    */
    *hash<auto> handleRequestImpl(reference<hash<auto>> cx, hash<auto> hdr, *data body) {
        return SoapHandler::handleRequest(cx, hdr, body);
    }
%endif

   hash<auto> getRemoteConfig() {
        return AbstractServiceHttpHandler::getRemoteConfig() + {
            "type": "SOAP",
        };
    }

    logInfo(string fmt) {
        logInfoArgs(fmt, argv);
    }

    logError(string fmt) {
        logErrorArgs(fmt, argv);
    }

    logDebug(string fmt) {
        logDebugArgs(fmt, argv);
    }
}

#! This wraps @ref WebSocketHandler::WebSocketConnection
/** By using this class, service programs do not have to import the entire \c WebSocketHandler module to access the
    connection class
*/
public class OMQ::QorusWebSocketConnection inherits WebSocketHandler::WebSocketConnection {
    #! Constructor for new WebSocket connections
    /** Called by the @ref OMQ::AbstractServiceWebSocketHandler "AbstractServiceWebSocketHandler" when a new
        connection is made by a WebSocket client; it is called from
        @ref OMQ::AbstractServiceWebSocketHandler::getConnectionImpl() "AbstractServiceWebSocketHandler::getConnectionImpl()",
        which can be overridden in subclasses to allow a subclass of this class to be used as the connection object
    */
    constructor(OMQ::AbstractServiceWebSocketHandler handler) : WebSocketConnection(handler) {
    }
}

#! this class is used to allow Qorus services to provide dedicated WebSocket server services to external clients
/** If any listeners are added to the AbstractServiceRestHandler object, then the URL set in the object is only bound
    to the new listeners specified in this object.  Otherwise, the URL is bound to all listeners in the system HTTP
    server.
*/
public class OMQ::AbstractServiceWebSocketHandler inherits WebSocketHandler::WebSocketHandler,
        OMQ::AbstractServiceHttpHandler {
    public {}

    #! creates the object with the given arguments
    /** @param path the URI path match on incoming requests
        @param auth the HttpServer::AbstractAuthenticator for the object; if no argument is passed, then the system
        authenticator is used; meaning all users can connect without authentication
        @param path_is_regex if @ref True then \a path is interpreted as a regular expression; note that matching
        requests based on regular expressions is much slower than a simple string match

        @par %Python Example
        @code{.py}
from svc import QorusService
from qore.WebSocketHandler import WebSocketHandler, WebSocketConnection
from qore.json import make_json
from datetime import timedelta

quit = False
ExitPollInterval = timedelta(seconds = 1)

class MyWebSocketConnection(WebSocketConnection):
    def __init__(self, handler):
        super(MyWebSocketConnection, self).__init__(handler)

    def gotMessage(self, msg):
        UserApi.logInfo("got msg: %y", msg)
        self.send("echo " + msg)

class MyWebSocketHandler(OMQ.AbstractServiceWebSocketHandler):
    def __init__(self):
        super(MyWebSocketHandler, self).__init__("my-websocket")
        svcapi.startThread(self.eventListener)

    def eventListener(self):
        global quit
        global ExitPollInterval
        min_id = 1
        while not quit:
            eh = svcapi.waitForEvents(min_id, ExitPollInterval)
            if 'shutdown' in eh:
                UserApi.logInfo("system is shutting down; stopping event thread")
                break
            min_id = eh['lastid'] + 1
            if not 'events' in eh:
                continue
            json = make_json(eh['events'])
            self.sendAll(json)

    def getConnectionImpl(self, cx, hdr, cid):
        return MyWebSocketConnection(self)

class MyPythonWebSocketService(QorusService):
    # "init" is a registered service method in the corresponding YAML metadata file
    def init(self):

    # "stop" is a registered service method in the corresponding YAML metadata file
    def stop(self):
        global quit
        quit = True
        @endcode

        @par %Qore Example
        @code{.py}
class MyWebSocketHandler inherits OMQ::AbstractServiceWebSocketHandler {
    constructor() : AbstractServiceWebSocketHandler("my-websocket") {
    }

    WebSocketHandler::WebSocketConnection getConnectionImpl(hash<auto> cx, hash<auto> hdr, string cid) {
       return new WebSocketHandler::WebSocketConnection(self);
    }
}
        @endcode

        @since Qorus 5.0 the \a path argument is assumed to be a regular string for faster performance
    */
    constructor(string path, HttpServer::AbstractAuthenticator auth = new DefaultQorusRBACAuthenticator(),
            bool path_is_regex = False)
            : WebSocketHandler(auth), AbstractServiceHttpHandler(path, NOTHING, NOTHING, NOTHING, path_is_regex) {
    }

    #! this method ensures that thread-local data is set properly
    hash<HttpResponseInfo> handleRequest(HttpListenerInterface listener, Socket s, hash<auto> cx, hash<auto> hdr,
            *data body) {
        # issue #3534: set service thread context
        setThreadContext(cx);
        return WebSocketHandler::handleRequest(listener, s, cx, hdr, body);
    }

    hash<auto> getRemoteConfig() {
        return AbstractServiceHttpHandler::getRemoteConfig() + {
            "type": "WS",
        };
    }

    logInfo(string fmt) {
        logInfoArgs(fmt, argv);
    }

    logError(string fmt) {
        logErrorArgs(fmt, argv);
    }

    logDebug(string fmt) {
        logDebugArgs(fmt, argv);
    }

    #! called when a connection is established; the default implementation creates an OMQ::QorusWebSocketConnection object
    OMQ::QorusWebSocketConnection getConnectionImpl(hash<auto> cx, hash<auto> hdr, string cid) {
        return new OMQ::QorusWebSocketConnection(self);
    }
}

#! base class for objects that capture a service context for logging
public class OMQ::ServiceLogBase {
    public {}

    private {
        #! service logging method call reference
        code slog;
    }

    #! creates the object and sets the service context for logging
    constructor() {
        slog = \tld.svc.logArgs();
    }

    #! logs to the service log file
    log(int ll, string fmt) {
%ifdef QorusServer
        call_function(slog, convert_old_log_level(ll), vsprintf(fmt, argv));
%else
        delete argv;
%endif
    }
}

#! class used for handling chunked requests and responses in services
public class OMQ::AbstractServiceStream inherits RestHandler::AbstractRestStreamRequestHandler, OMQ::ServiceLogBase {
    #! creates the object from an inbound request
    /** @param cx call context hash; this hash will have the following keys:
        - \c socket: the bind address used to bind the listener (\c "socket-info" provides more detailed information)
        - \c socket-info: a hash of socket information for the listening socket (as returned by
          @ref Qore::Socket::getSocketInfo() "Socket::getSocketInfo()")
        - \c peer-info: a hash of socket information for the remote socket (as returned by
          @ref Qore::Socket::getPeerInfo() "Socket::getPeerInfo()")
        - \c url: a hash of broken-down URL information (as returned from @ref Qore::parse_url() "parse_url()")
        - \c id: the unique HTTP connection ID
        - \c listener-id: the HTTP server listener ID (see
          @ref HttpServer::HttpServer::getListenerInfo() "HttpServer::getListenerInfo()")
        - \c user: the current RBAC username (if any)
        - \c hdr: a hash of header information as returned by
          @ref Qore::Socket::readHTTPHeader() "Socket::readHTTPHeader()"
        - \c body: the deserialized message body
        - \c aih: a hash of \c "Accept" values
        @param ah any URI arguments in the request
    */
    constructor(hash<auto> cx, *hash<auto> ah) : AbstractRestStreamRequestHandler(cx, ah) {
    }
}

#! This class implements a request handler supporting the @ref datastreamprotocol "DataStream protocol" for Qorus services
/** This class also allows logging to the service log file and must be subclassed; the @ref recvDataImpl() and
    @ref sendDataImpl() methods must be overridden to provide data receiving and sending support, respectively.
*/
public class OMQ::AbstractServiceDataStreamResponseHandler inherits DataStreamRequestHandler::AbstractDataStreamRequestHandler, OMQ::ServiceLogBase {
    #! creates the object from an inbound request
    /** @param cx call context hash; this hash will have the following keys:
        - \c socket: the bind address used to bind the listener (\c "socket-info" provides more detailed information)
        - \c socket-info: a hash of socket information for the listening socket (as returned by
          @ref Qore::Socket::getSocketInfo() "Socket::getSocketInfo()")
        - \c peer-info: a hash of socket information for the remote socket (as returned by
          @ref Qore::Socket::getPeerInfo() "Socket::getPeerInfo()")
        - \c url: a hash of broken-down URL information (as returned from @ref Qore::parse_url() "parse_url()")
        - \c id: the unique HTTP connection ID
        - \c listener-id: the HTTP server listener ID (see
          @ref HttpServer::HttpServer::getListenerInfo() "HttpServer::getListenerInfo()")
        - \c user: the current RBAC username (if any)
        - \c hdr: a hash of header information as returned by
          @ref Qore::Socket::readHTTPHeader() "Socket::readHTTPHeader()"
        - \c body: the deserialized message body
        - \c aih: a hash of \c "Accept" values
        @param ah any URI arguments in the request
    */
    constructor(hash<auto> cx, *hash<auto> ah) : AbstractDataStreamRequestHandler(cx, ah) {
        if (cx.uctx.persistent_data)
            rhdr."Qorus-Connection" = "Persistent";
    }
}

#! this class is the base class for persistent HTTP connection support in services
public class OMQ::AbstractPersistentDataHelper inherits OMQ::ServiceLogBase {
    public {
        #! error flag
        bool err;
    }

    private:internal {
        # service object for notifications when the persistent connection is closed
        AbstractQorusService svc;
    }

    #! creates the object from an inbound request
    /** @param cx call context hash; this hash will have the following keys:
        - \c socket: the bind address used to bind the listener (\c "socket-info" provides more detailed information)
        - \c socket-info: a hash of socket information for the listening socket (as returned by
          @ref Qore::Socket::getSocketInfo() "Socket::getSocketInfo()")
        - \c peer-info: a hash of socket information for the remote socket (as returned by
          @ref Qore::Socket::getPeerInfo() "Socket::getPeerInfo()")
        - \c url: a hash of broken-down URL information (as returned from @ref Qore::parse_url() "parse_url()")
        - \c id: the unique HTTP connection ID
        - \c listener-id: the HTTP server listener ID (see
          @ref HttpServer::HttpServer::getListenerInfo() "HttpServer::getListenerInfo()")
        - \c user: the current RBAC username (if any)
        - \c hdr: a hash of header information as returned by
          @ref Qore::Socket::readHTTPHeader() "Socket::readHTTPHeader()"
        - \c body: the deserialized message body
        - \c aih: a hash of \c "Accept" values
        @param ah any URI arguments in the request
    */
    constructor(hash<auto> cx, *hash<auto> ah) {
    }

    destructor() {
        # dereference the service to allow resets/deletes to be processed after closing the persistent connection
        qorus_api_deref_service(svc);
    }

    #! allows the service to be notified that the persistent connection has been closed
    setService(AbstractQorusService s) {
        svc = s;
        # reference the service for the lifetime of the persistent connection
        qorus_api_ref_service(svc);
    }

    #! returns the current service
    OMQ::AbstractQorusService getService() {
        return svc;
    }

    #! sets the error flag on the object
    setError() {
        err = True;
    }
}

#! class providing automatic authentication for all requests
public class OMQ::PermissiveAuthenticator inherits HttpServer::PermissiveAuthenticator {
    #! primary method called to authenticate each request
    /** @param listener an @ref HttpServer::HttpListenerInterface object for the listener serving the request for
        logging purposes
        @param hdr a hash of request headers
        @param cx a reference to the call context hash; sets the \c "user" key to the internal system user

        @return returns @ref nothing indicating that the request is authenticated
    */
    *hash<auto> authenticateRequest(HttpListenerInterface listener, hash<auto> hdr, reference<hash<auto>> cx) {
        ensure_create_tld();
        return HttpServer::PermissiveAuthenticator::authenticateRequest(listener, hdr, \cx);
    }
}

%ifndef QorusHasSvcApi
public class OMQ::AbstractQorusService {
    public {
        string name;
        string version;
        int serviceid;
    }
}
sub qorus_api_ref_service(AbstractQorusService svc) {}
sub qorus_api_deref_service(AbstractQorusService svc) {}
%endif
