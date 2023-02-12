# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusSystemAPIHelperBase.qc Qorus communication class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

#! the main client namespace
public namespace OMQ {
    #! valid client API options
    public const ValidClientAPIOpts = {
        "timeout": True,
        "connect_timeout": True,
        "headers": True,
        "http_version": True,
        "url": True,
        "max_redirects": True,
        "proxy": True,
    };

    #! This class provides an easy way to call Qorus API functions using the network API
    /** the class does not provide any connection pooling; it is thread-safe, but requests from concurrent threads will block while a request from another thread is in progress
        This class uses @ref YAMLRPC "YAML-RPC" by default, but if calling a Qorus server that does not support @ref YAMLRPC "YAML-RPC", will automatically fall back to XML-RPC
        @note this should not be used directly; use subclass OMQ::QorusSystemAPIHelper (in server code) or OMQ::Client::QorusSystemAPIHelper (in client code) instead
     */
    public class QorusSystemAPIHelperBase inherits private Mutex {
        private {
            bool xmlrpc = False;
            bool jsonrpc = False;
            bool yamlrpc = False;
            bool update_ws = False;
            *object ws;
            hash ws_opts;

            # object initialization closure
            *code init;

            # event queue (assigned externally)
            Queue q;
        }

        #! creates the object based on the options passed
        /** @param n_opts optional hash with the following keys:
            - \c timeout
            - \c connect_timeout
            - \c http_version
            - \c url
            - \c max_redirects
            - \c proxy
            @param n_init an optional initialization closure to be called with the RPC object as the sole argument

            @see ValidClientAPIOpts
        */
        constructor(*hash<auto> n_opts, *code n_init) {
            setOptions(n_opts);
            init = n_init;
        }

        #! creates a copy of the object
        copy() {
            remove ws;
        }

        Qore::AbstractPollOperation startPollConnect() {
            lock();
            on_exit unlock();

            checkInitIntern(True);
            return ws.startPollConnect();
        }

        #! adds default headers to each request; these headers will be sent in all requests
        /** @par Example:
            @code{.py}
# disable gzip and bzip encoding in responses
omqapi.addDefaultHeaders({"Accept-Encoding": "compress"});
            @endcode

            @param h a hash of headers to add to the default headers to send on each request

            @note default headers can also be set in the constructor

            @see @ref getDefaultHeaders()

            @since Qorus 5.0
        */
        addDefaultHeaders(hash<auto> h) {
            lock();
            on_exit unlock();

            addDefaultHeadersIntern(h);
        }

        #! returns the hash of default headers to sent in all requests
        /** @par Example:
            @code{.py}
hash<auto> h = omqapi.getDefaultHeaders();
            @endcode

            @return the hash of default headers to sent in all requests

            @note default headers can be set in the constructor and in addDefaultHeaders()

            @see @ref addDefaultHeaders()

            @since Qorus 5.0
        */
        hash<auto> getDefaultHeaders() {
            return ws_opts.headers ?? {};
        }

        #! this variant of the setOptions() method does nothing when called with no argument
        setOptions() {
        }

        #! sets connection options
        /** @param opts optional hash with the following keys: timeout, connect_timeout, http_version, url, max_redirects, proxy
        */
        setOptions(hash<auto> opts) {
            foreach string key in (keys opts) {
                if (!ValidClientAPIOpts{key})
                    throw "INVALID-API-OPTIONS", sprintf("invalid Qorus client API option %y; valid options: %y", key, ValidClientAPIOpts.keys());
            }

            lock();
            on_exit unlock();

            ws_opts += opts;
            update_ws = True;
        }

        #! sets the URL
        setURL(string url) {
            lock();
            on_exit unlock();

            if (ws_opts.url != url) {
                ws_opts.url = url;
                update_ws = True;
            }
        }

        #! sets or clears the proxy URL
        setProxyURL(*string url) {
            lock();
            on_exit unlock();

            if (!strlen(url)) {
                if (exists ws_opts.proxy) {
                    remove ws_opts.proxy;
                    update_ws = True;
                }
            } else if (ws_opts.proxy != url) {
                ws_opts.proxy = url;
                update_ws = True;
            }
        }

        #! returns the current URL value
        string getURL() {
            lock();
            on_exit unlock();

            # do not try to initialize again if the URL exists
            # because it could throw another exception if the
            # destination is not reachable, for example
            if (!exists ws_opts.url)
                checkInitIntern();

            return ws_opts.url;
        }

        #! returns the current proxy URL value or NOTHING if none is set
        *string getProxyURL() {
            lock();
            on_exit unlock();

            # do not try to initialize again if the URL exists
            # because it could throw another exception if the
            # destination is not reachable, for example
            if (!exists ws_opts.url)
                checkInitIntern();

            return ws_opts.proxy;
        }

        #! returns True if the object is using the XML-RPC protocol
        bool isXmlRpc() {
            lock();
            on_exit unlock();

            checkInitIntern();
            return xmlrpc;
        }

        #! returns True if the object is using the JSON-RPC protocol
        bool isJsonRpc() {
            lock();
            on_exit unlock();

            checkInitIntern();
            return jsonrpc;
        }

        #! returns True if the object is using the @ref YAMLRPC "YAML-RPC" protocol
        bool isYamlRpc() {
            lock();
            on_exit unlock();

            checkInitIntern();
            return yamlrpc;
        }

        #! returns True if the object is currently connected to the server
        bool isConnected() {
            lock();
            on_exit unlock();

            checkInitIntern();
            return exists ws ? ws.isConnected() : False;
        }

        #! sets the connect timeout from an integer in milliseconds
        setConnectTimeout(int to) {
            lock();
            on_exit unlock();

            if (to != ws_opts.connect_timeout) {
                # issue 1996: ensure that timeouts are set consistently as relateive date/time values
                ws_opts.connect_timeout = milliseconds(to);
                update_ws = True;
            }
        }

        #! sets the connect timeout from a relative date/time value (i.e. 30s)
        setConnectTimeout(date to) {
            lock();
            on_exit unlock();

            if (to != ws_opts.connect_timeout) {
                ws_opts.connect_timeout = to;
                update_ws = True;
            }
        }

        #! sets the send/receive I/O timeout from an integer in milliseconds
        setTimeout(int to) {
            lock();
            on_exit unlock();

            if (to != ws_opts.timeout) {
                # issue 1996: ensure that timeouts are set consistently as relateive date/time values
                ws_opts.timeout = milliseconds(to);
                update_ws = True;
            }
        }

        #! sets the send/receive I/O timeout from a relative date/time value (i.e. 30s)
        setTimeout(date to) {
            lock();
            on_exit unlock();

            if (to != ws_opts.timeout) {
                ws_opts.timeout = to;
                update_ws = True;
            }
        }

        #! gets the send/receive I/O timeout as a relative date/time value
        /** @since Qorus 3.1.0.p16
        */
        *date getTimeout() {
            lock();
            on_exit unlock();

            return ws_opts.timeout;
        }

        #! gets the connect timeout as a relative date/time value
        /** @since Qorus 3.1.0.p16
        */
        *date getConnectTimeout() {
            lock();
            on_exit unlock();

            return ws_opts.connect_timeout;
        }

        #! if a connection is established, closes the connection and reconnects immediately
        reconnect() {
            lock();
            on_exit unlock();

            checkInitIntern();
            if (ws.isConnected())
                ws.close();

            ws.connect();
        }

        private addDefaultHeadersIntern(hash<auto> h) {
            ws_opts.headers += h;
            if (ws) {
                ws.addDefaultHeaders(h);
            }
        }

        # this method should be overridden in subclasses
        # for example, the client library overrides this method to set default
        # options based on the current options file
        private setDefaultOptions(*string proxy) {
            throw "URL-ERROR", "no client URL set for the object; use the 'url' key in the option has in the "
                "constructor when creating the object or call QorusSystemAPIHelper::setURL() with the server URL "
                "before trying to use the object";
        }

        # returns true if a new object was created, false if not
        private bool checkInitIntern(*bool no_connect) {
            if (exists ws) {
                if (update_ws) {
                    delete ws;
                    update_ws = False;
                } else {
                    return False;
                }
            }

            if (!exists ws_opts.url)
                self.setDefaultOptions(ws_opts.proxy);

            hash<UrlInfo> h = parse_url(ws_opts.url);

            if (exists h.protocol && h.protocol =~ /json/i) {
                ws = new JsonRpcClient(ws_opts, no_connect);
                jsonrpc = True;
            } else if (exists h.protocol && h.protocol =~ /xml/i) {
                ws = new XmlRpcClient(ws_opts, no_connect);
                xmlrpc = True;
            } else {
                ws = new YamlRpcClient(ws_opts, no_connect);
                yamlrpc = True;
            }

            if (q)
                ws.setEventQueue(q);
            if (init)
                call_function(init, ws);

            return True;
        }

        #! forces the use of the XML-RPC protocol
        forceXmlRpc() {
            lock();
            on_exit unlock();

            checkInitIntern();
            if (!xmlrpc) {
                ws_opts.url =~ s/^.*rpc/http/;
                ws = new XmlRpcClient(ws_opts);
                yamlrpc = False;
                jsonrpc = False;
                xmlrpc = True;
                if (q)
                    ws.setEventQueue(q);
                if (init)
                    call_function(init, ws);
            }
        }

        #! forces the use of the (proprietary) @ref YAMLRPC "YAML-RPC" protocol
        /** @note @ref YAMLRPC "YAML-RPC" is the preferred protocol when communicating with Qorus servers
            */
        forceYamlRpc() {
            lock();
            on_exit unlock();

            checkInitIntern();
            if (!yamlrpc) {
                ws_opts.url =~ s/^.*rpc/http/;
                ws = new YamlRpcClient(ws_opts);
                yamlrpc = True;
                jsonrpc = False;
                xmlrpc = False;
                if (q)
                    ws.setEventQueue(q);
                if (init)
                    call_function(init, ws);
            }
        }

        private auto doCallIntern(string api, auto args, auto info, bool literal = False) {
            lock();
            on_exit unlock();

            checkInitIntern();

            if (!literal && api !~ /\./)
                api = "omq.system." + api;

            bool has_info = exists info ? True : False;

            hash rv;
            while (True) {
                try {
                    if (has_info) {
                        rv = ws.callArgsWithInfo(\info, api, args);
                        info.orig_response = rv;
                    } else
                        rv = ws.callArgsWithInfo(\info, api, args);
                } catch (hash<ExceptionInfo> ex) {
                    # if we have gotten a 400 Bad Request or 501 Not Implemented response
                    # and we are using YAML, then maybe we are talking to an older version
                    # of the server so we can switch to XML-RPC and try again
                    if ((ex.arg.status_code == 400 || ex.arg.status_code == 501) && yamlrpc) {
                        ws_opts.url =~ s/^.*rpc/http/;
                        ws = new XmlRpcClient(ws_opts);
                        yamlrpc = False;
                        xmlrpc = True;
                        if (q)
                            ws.setEventQueue(q);
                        if (init)
                            call_function(init, ws);
                        # try again
                        continue;
                    }
%ifdef QorusServer
                    QDBG_LOG("%s", get_exception_string(ex));
%endif
                    rethrow;
                }
                break;
            }

            if (xmlrpc) {
                if (rv.fault) {
                    # fix for bug 993:
                    (*string prefix, *string type, *string qe) = (rv.fault.faultString =~ x/^((User|System) exception: [A-Za-z][A-Za-z0-9_\.]*:[0-9]+: ([-A-Z0-9_]+): )/);
                    if (qe) {
                        # remove exception error from beginning of string
                        splice rv.fault.faultString, 0, prefix.size();
                        throw qe, sprintf("remote XML-RPC server at %y reported an error: %s", ws_opts.url, rv.fault.faultString);
                    }
                    throw "API-CALL-ERROR", rv.fault.faultString;
                }
                return rv.params;
            }
            if (rv.error) {
                # fix for bug 993:
                (*string pfx, *string qe) = (rv.error.message =~ x/^([A-Za-z][A-Za-z0-9_\.]*:[0-9]+: )?([-A-Z0-9_]+): /);
                if (qe) {
                    # remove exception error from beginning of string
                    splice rv.error.message, 0, pfx.size() + qe.size() + 2;
                    throw qe, sprintf("remote %s-RPC server at %y reported an error: %s", (yamlrpc ? "YAML" : "JSON"), ws_opts.url, rv.error.message);
                }
                throw "API-CALL-ERROR", rv.error.message;
            }

            return rv.result;
        }

        #! this method is used to redirect calls to unknown methods as the method name when calling the server
        auto methodGate(string api) {
            return doCallIntern(api, argv);
        }

        #! this method is used to redirect calls to unknown methods as the method name when calling the server
        auto memberGate(string api) {
            return doCallIntern(api, argv);
        }

        #! with this method you can call a method on the server and give the argument list directly as a list
        /** if an error message is returned, then an equivalent Qore-language exception is thrown
            @param api the server method name to call
            @param args the argument or argument list to give to the method
            @param literal if True then the object will not try to prepend "omq.system." to the method name if it does not have any "." characters in it
            @return returns the value returned by the server
            */
        auto callAPIArgs(string api, auto args, bool literal = False) {
            return doCallIntern(api, args, NOTHING, literal);
        }

        #! with this method you can call a method on the server and give the argument list directly as a list and it also requires a reference to a hash as the first argument, which will return technical information about the call
        /** if an error message is returned, then an equivalent Qore-language exception is thrown
            @param info a reference to a hash that will be returned with technical information about the call (request and response headers, actual request and response messages, etc)
            @param api the server method name to call
            @param args the argument or argument list to give to the method
            @param literal if True then the object will not try to prepend "omq.system." to the method name if it does not have any "." characters in it
            @return returns the value returned by the server
            */
        auto callAPIArgsWithInfo(reference<hash<auto>> info, string api, auto args, bool literal = False) {
            info = {};
            return doCallIntern(api, args, \info, literal);
        }

        #! with this method you can call a method on the server, the arguments to the server method should follow the method name normally as arguments to this method
        /** if an error message is returned, then an equivalent Qore-language exception is thrown
            @param api the server method name to call
            @return returns the value returned by the server
            */
        auto callAPI(string api) {
            return doCallIntern(api, argv);
        }

        #! this method allows you to set a Queue object to get I/O events from the underlying HTTPClient object
        setQueue(Queue n_q) {
            lock();
            on_exit unlock();

            q = n_q;

            if (!checkInitIntern())
                ws.setQueue(n_q);
        }

        #! returns a hash of configuration information for the object
        static hash<auto> toConfig(hash<auto> info) {
            hash<auto> h += info{("connect_timeout", "timeout")};
            # issue 1996: sometimes timeout and/or connect_timeout is an int in seconds, sometimes a relative date
            if (h.connect_timeout && h.connect_timeout.typeCode() == NT_INT) {
                h.connect_timeout *= 1000;
            }
            if (h.timeout && h.timeout.typeCode() == NT_INT) {
                h.timeout *= 1000;
            }
            return h;
        }
    }
}

