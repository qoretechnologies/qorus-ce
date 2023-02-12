# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusSystemRestHelperBase.qc Qorus communication class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

#! the main client namespace
public namespace OMQ {
    #! base class for accessing the system REST API
    public class QorusSystemRestHelperBase inherits DataStreamClient::DataStreamClient {
        public {
            #! default values for connection options
            const Defaults = {
                "connect_timeout": 20s,
                "timeout": 120s,
                "api_version": "latest",
            };

            #! connection params
            hash conn_opts;

            #! api version
            *string api_version;

            #! connection name if known
            *string name;
        }

        private:internal {
            bool api_version_set;
        }

        #! Creates the object with the given options
        /** A connection is automatically made unless the \a do_not_connect argument is @ref False "False"

            @param opts options as follows:
            - \c api_version: the REST API version (defaults to the latest version)
            - \c connect_timeout: the connect timeout value in milliseconds
            - \c timeout: the socket I/O timeout value in milliseconds
            - \c url: the target URL
            - \c use_schema: if @ref True then the Swagger schema will be used
            @param do_not_connect if @ref True "True", then the object will be created in an unconnected state

            @since
            - Qorus 3.1.1 added the \a api_version option
            - Qorus 6.0 added the setSchema() method
        */
        constructor(*hash<auto> opts, *softbool do_not_connect)
                : DataStreamClient({
                    "default_path": "api" + (
                        opts.opts.api_version == "v1"
                            ? ""
                            : ("/" + (opts.opts.api_version ?? Defaults.api_version))
                        ),
                    } + opts, True) {
            if (!opts.connect_timeout) {
                setConnectTimeout(Defaults.connect_timeout);
            }
            if (!opts.timeout) {
                setTimeout(Defaults.timeout);
            }

            api_version = opts.opts.api_version ?? Defaults.api_version;
            if (api_version != "latest") {
                api_version_set = True;
                if (api_version == "v1") {
                    delete api_version;
                }
            }

            # save connection name
            name = opts.name;

            if (!opts.url) {
                autoSetUrl(opts);
            }

            if (opts.use_schema) {
                setSchema();
            }

            if (!do_not_connect) {
                connect();
            }
        }

        #! Sets the REST validator to the latest version of the schema for the Qorus API
        /** @since Qorus 6.0
        */
        setSchema() {
%ifndef QorusFakeApi
            # get the Swagger path URL from the system URL
            hash<UrlInfo> info = parse_url(getURL());
            string swagger_url = sprintf("%s://%s", info.protocol, info.host);
            if (info.port) {
                swagger_url += ":" + info.port;
            }
            swagger_url += sprintf("/schema/qorus-rest-api-v%d.yaml", RestApiVersion);
            # create the Swagger validator from the swagger URL
            validator = SwaggerLoader::fromUrl(swagger_url);
            # clear default path
            setDefaultPath();
            # clear connection path
            setConnectionPath();
%endif
        }

        #! Sets the REST validator to the latest version of the public schema for the Qorus API
        /** @since Qorus 6.0
        */
        setPublicSchema() {
%ifndef QorusFakeApi
            # get the Swagger path URL from the system URL
            hash<UrlInfo> info = parse_url(getURL());
            string swagger_url = sprintf("%s://%s", info.protocol, info.host);
            if (info.port) {
                swagger_url += ":" + info.port;
            }
            swagger_url += "/schema/qorus-rest-api-public.yaml";
            # create the Swagger validator from the swagger URL
            validator = SwaggerLoader::fromUrl(swagger_url);
            # clear default path
            setDefaultPath();
            # clear connection path
            setConnectionPath();
%endif
        }

        #! sets the URL automatically; must be reimplemented in subclasses
        private abstract autoSetUrl(*hash<auto> opts);

        #! sets the URL for the object
        setURL(string url) {
            hash<UrlInfo> uh = parse_url(url);
            if (!uh.path) {
                if (url !~ /\/$/) {
                    url += "/";
                }
                url += "api" + (api_version ? "/" + api_version : "");
            } else if (uh.path == "/") {
                url += "api" + (api_version ? "/" + api_version : "");
            }
            DataStreamClient::setURL(url);
        }

        #! executes the remote REST call and returns the response
        /** @param m the HTTP method for the request (ex: \c "GET")
            @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request
            @param opt output options; as defined in the child class

            @return a hash with the following keys:
            - \c rv: the deserialized response body
            - \c info: a hash of request headers and other information about the HTTP request; if present the hash
              will contain the following keys:
              - \c headers: a hash of outgoing HTTP request headers
              - \c request-uri: the request URI string sent (ex: \c "GET /services/async/38.0/job HTTP/1.1")
              - \c body-content-type: the outgoing message body Mime \c Content-Type value
              - \c response-headers: a hash of incoming HTTP headers in the response
              - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
              - \c response-code: the HTTP response code
              - \c response-body: the raw message body in the response (after any content decoding)
              - \c response-serialization: the type of message serialization in the response; see
                @ref RestClient::RestClient::DataSerializationOptions for possible values
              - \c request-body: the raw message body in the request (before any content encoding)
              - \c request-serialization: the type of message serialization in the request; see
                @ref RestClient::RestClient::DataSerializationOptions for possible values

            @since Qorus 4.0
        */
        hash<auto> restDoWithInfo(string m, string path, auto args, *hash<auto> hdr, *hash<auto> opt) {
            hash<auto> info;
            auto rv = restDo(m, path, args, hdr, opt, \info);
            return {
                "rv": rv,
                "info": info,
            };
        }

        #! executes the remote REST call and returns the response
        /** @param m the HTTP method for the request (ex: \c "GET")
            @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request
            @param opt output options; as defined in the child class
            @param info an optional reference to a hash that will be used as an output variable giving a hash of
            request headers and other information about the HTTP request; if present the hash will contain the
            following keys:
            - \c headers: a hash of outgoing HTTP request headers
            - \c request-uri: the request URI string sent (ex: \c "GET /services/async/38.0/job HTTP/1.1")
            - \c body-content-type: the outgoing message body Mime \c Content-Type value
            - \c response-headers: a hash of incoming HTTP headers in the response
            - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
            - \c response-code: the HTTP response code
            - \c response-body: the raw message body in the response (after any content decoding)
            - \c response-serialization: the type of message serialization in the response; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values
            - \c request-body: the raw message body in the request (before any content encoding)
            - \c request-serialization: the type of message serialization in the request; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values

            @return the deserialized response body
        */
        abstract auto restDo(string m, string path, auto args, *hash<auto> hdr, *hash<auto> opt,
            *reference<hash<auto>> info);

        #! issue a warning on the console (for the client) or in the current log file (for the server)
        /** @since Qorus 3.1.1
        */
        private abstract nothing warning(string fmt);

        #! executes a \c GET call on the remote REST service and returns the response
        /** @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request
            @param info an optional reference to a hash that will be used as an output variable giving a hash of
            request headers and other information about the HTTP request; if present the hash will contain the following keys:
            - \c headers: a hash of outgoing HTTP request headers
            - \c request-uri: the request URI string sent (ex: \c "GET /services/async/38.0/job HTTP/1.1")
            - \c body-content-type: the outgoing message body Mime \c Content-Type value
            - \c response-headers: a hash of incoming HTTP headers in the response
            - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
            - \c response-code: the HTTP response code
            - \c response-body: the raw message body in the response (after any content decoding)
            - \c response-serialization: the type of message serialization in the response; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values
            - \c request-body: the raw message body in the request (before any content encoding)
            - \c request-serialization: the type of message serialization in the request; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values

            @return the deserialized response body
        */
        auto get(string path, auto args, *hash<auto> hdr, *reference<hash<auto>> info) {
            return restDo("GET", path, args, hdr, NOTHING, \info);
        }

        #! executes a \c GET call on the remote REST service and returns the response
        /** @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request

            @return a hash with the following keys:
            - \c rv: the deserialized response body
            - \c info: a hash of request headers and other information about the HTTP request; if present the hash
              will contain the following keys:
              - \c headers: a hash of outgoing HTTP request headers
              - \c request-uri: the request URI string sent (ex: \c "GET /services/async/38.0/job HTTP/1.1")
              - \c body-content-type: the outgoing message body Mime \c Content-Type value
              - \c response-headers: a hash of incoming HTTP headers in the response
              - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
              - \c response-code: the HTTP response code
              - \c response-body: the raw message body in the response (after any content decoding)
              - \c response-serialization: the type of message serialization in the response; see
                @ref RestClient::RestClient::DataSerializationOptions for possible values
              - \c request-body: the raw message body in the request (before any content encoding)
              - \c request-serialization: the type of message serialization in the request; see
                @ref RestClient::RestClient::DataSerializationOptions for possible values

            @since Qorus 4.0
        */
        hash<auto> getWithInfo(string path, auto args, *hash<auto> hdr) {
            return restDoWithInfo("GET", path, args, hdr);
        }

        #! executes a \c PUT call on the remote REST service and returns the response
        /** @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request
            @param info an optional reference to a hash that will be used as an output variable giving a hash of
            request headers and other information about the HTTP request; if present the hash will contain the
            following keys:
            - \c headers: a hash of outgoing HTTP request headers
            - \c request-uri: the request URI string sent (ex: \c "PUT /services/async/38.0/job HTTP/1.1")
            - \c body-content-type: the outgoing message body Mime \c Content-Type value
            - \c response-headers: a hash of incoming HTTP headers in the response
            - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
            - \c response-code: the HTTP response code
            - \c response-body: the raw message body in the response (after any content decoding)
            - \c response-serialization: the type of message serialization in the response; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values
            - \c request-body: the raw message body in the request (before any content encoding)
            - \c request-serialization: the type of message serialization in the request; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values

            @return the deserialized response body
        */
        auto put(string path, auto args, *hash<auto> hdr, *reference<hash<auto>> info) {
            return restDo("PUT", path, args, hdr, NOTHING, \info);
        }

        #! executes a \c PUT call on the remote REST service and returns the response
        /** @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request

            @return a hash with the following keys:
            - \c rv: the deserialized response body
            - \c info: a hash of request headers and other information about the HTTP request; if present the hash
              will contain the following keys:
                - \c headers: a hash of outgoing HTTP request headers
                - \c request-uri: the request URI string sent (ex: \c "PUT /services/async/38.0/job HTTP/1.1")
                - \c body-content-type: the outgoing message body Mime \c Content-Type value
                - \c response-headers: a hash of incoming HTTP headers in the response
                - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
                - \c response-code: the HTTP response code
                - \c response-body: the raw message body in the response (after any content decoding)
                - \c response-serialization: the type of message serialization in the response; see
                  @ref RestClient::RestClient::DataSerializationOptions for possible values
                - \c request-body: the raw message body in the request (before any content encoding)
                - \c request-serialization: the type of message serialization in the request; see
                  @ref RestClient::RestClient::DataSerializationOptions for possible values

            @since Qorus 4.0
        */
        hash<auto> putWithInfo(string path, auto args, *hash<auto> hdr) {
            return restDoWithInfo("PUT", path, args, hdr);
        }

        #! executes a \c POST call on the remote REST service and returns the response
        /** @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request
            @param info an optional reference to a hash that will be used as an output variable giving a hash of
            request headers and other information about the HTTP request; if present the hash will contain the
            following keys:
            - \c headers: a hash of outgoing HTTP request headers
            - \c request-uri: the request URI string sent (ex: \c "POST /services/async/38.0/job HTTP/1.1")
            - \c body-content-type: the outgoing message body Mime \c Content-Type value
            - \c response-headers: a hash of incoming HTTP headers in the response
            - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
            - \c response-code: the HTTP response code
            - \c response-body: the raw message body in the response (after any content decoding)
            - \c response-serialization: the type of message serialization in the response; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values
            - \c request-body: the raw message body in the request (before any content encoding)
            - \c request-serialization: the type of message serialization in the request; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values

            @return the deserialized response body
        */
        auto post(string path, auto args, *hash<auto> hdr, *reference<hash<auto>> info) {
            return restDo("POST", path, args, hdr, NOTHING, \info);
        }

        #! executes a \c POST call on the remote REST service and returns the response
        /** @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request

            @return a hash with the following keys:
            - \c rv: the deserialized response body
            - \c info: a hash of request headers and other information about the HTTP request; if present the hash
              will contain the following keys:
                - \c headers: a hash of outgoing HTTP request headers
                - \c request-uri: the request URI string sent (ex: \c "POST /services/async/38.0/job HTTP/1.1")
                - \c body-content-type: the outgoing message body Mime \c Content-Type value
                - \c response-headers: a hash of incoming HTTP headers in the response
                - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
                - \c response-code: the HTTP response code
                - \c response-body: the raw message body in the response (after any content decoding)
                - \c response-serialization: the type of message serialization in the response; see
                  @ref RestClient::RestClient::DataSerializationOptions for possible values
                - \c request-body: the raw message body in the request (before any content encoding)
                - \c request-serialization: the type of message serialization in the request; see
                  @ref RestClient::RestClient::DataSerializationOptions for possible values

            @since Qorus 4.0
        */
        hash<auto> postWithInfo(string path, auto args, *hash<auto> hdr) {
            return restDoWithInfo("POST", path, args, hdr);
        }

        #! executes a \c DELETE call on the remote REST service and returns the response
        /** @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request
            @param info an optional reference to a hash that will be used as an output variable giving a hash of
            request headers and other information about the HTTP request; if present the hash will contain the
            following keys:
            - \c headers: a hash of outgoing HTTP request headers
            - \c request-uri: the request URI string sent (ex: \c "DELETE /users/olduser HTTP/1.1")
            - \c body-content-type: the outgoing message body Mime \c Content-Type value
            - \c response-headers: a hash of incoming HTTP headers in the response
            - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
            - \c response-code: the HTTP response code
            - \c response-body: the raw message body in the response (after any content decoding)
            - \c response-serialization: the type of message serialization in the response; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values
            - \c request-body: the raw message body in the request (before any content encoding)
            - \c request-serialization: the type of message serialization in the request; see
              @ref RestClient::RestClient::DataSerializationOptions for possible values

            @return the deserialized response body
        */
        auto del(string path, auto args, *hash<auto> hdr, *reference<hash<auto>> info) {
            return restDo("DELETE", path, args, hdr, NOTHING, \info);
        }

        #! executes a \c DELETE call on the remote REST service and returns the response
        /** @param path the URI path for the request
            @param args any arguments to the REST request
            @param hdr a hash of optional HTTP header info to add to the request

            @return a hash with the following keys:
            - \c rv: the deserialized response body
            - \c info: a hash of request headers and other information about the HTTP request; if present the hash
              will contain the following keys:
                - \c headers: a hash of outgoing HTTP request headers
                - \c request-uri: the request URI string sent (ex: \c "DELETE /users/olduser HTTP/1.1")
                - \c body-content-type: the outgoing message body Mime \c Content-Type value
                - \c response-headers: a hash of incoming HTTP headers in the response
                - \c chunked: set to @ref True "True" if the response was received with chunked transfer encoding
                - \c response-code: the HTTP response code
                - \c response-body: the raw message body in the response (after any content decoding)
                - \c response-serialization: the type of message serialization in the response; see
                  @ref RestClient::RestClient::DataSerializationOptions for possible values
                - \c request-body: the raw message body in the request (before any content encoding)
                - \c request-serialization: the type of message serialization in the request; see
                  @ref RestClient::RestClient::DataSerializationOptions for possible values

            @since Qorus 4.0
        */
        hash<auto> delWithInfo(string path, auto args, *hash<auto> hdr) {
            return restDoWithInfo("DELETE", path, args, hdr);
        }

        #! sends an HTTP request to the REST server and returns the response
        /** @par Example:
            @code{.py}
hash<auto> ans = rest.doRequest("DELETE", "/orders/1");
            @endcode

            @see @ref RestClient::RestClient::doRequest() for details

            @note This method will attempt to switch to the base API level if set to "latest" and a URI path error is
            returned from the server

            @since Qorus 3.1.1
         */
        hash<auto> doRequest(string m, string path, auto body, *reference<hash<auto>> info,
                softbool decode_errors = True, *hash<auto> hdr) {
            while (True) {
                try {
                    return DataStreamClient::doRequest(m, path, body, \info, decode_errors, hdr);
                } catch (hash<ExceptionInfo> ex) {
                    # if we have api_version = "latest" and we get an error with this part of the path, then
                    # we will try to set the base REST API and try again in case we are working with an
                    # older Qorus server
                    if (!api_version_set
                        && (ex.err == "REST-CLASS-ERROR"
                            || ex.err == "DESERIALIZATION-ERROR")
                        && ex.desc =~ /unknown REST class.*latest/
                        && getDefaultPath() == "api/latest") {
                        string url = getURL();
                        string wstr = "WARNING: ";
                        if (name)
                            wstr += sprintf("remote connection %y: ", name);
                        warning(wstr + "error using URL %y; switching to base API; update the remoteconnection entry "
                            "with \"api_version = v1\" to avoid seeing this warning", url);
                        setDefaultPath("api");
                        url =~ s/api\/latest/api/;
                        setURL(url);
                        api_version_set = True;
                        continue;
                    }
                    rethrow ex.err, sprintf("%s (URL %s)", ex.desc, getSafeURL() + "/" + path);
                }
            }
        }

        #! returns a hash of configuration information for the object
        static hash<auto> toConfig(hash<auto> info) {
            # issue 1996: ensure that connect_timeout and timeout information is converted from seconds to milliseconds
            # and is present in the top-level of the option hash
            hash<auto> h = info - "loopback" + info.opts;
            if (h.connect_timeout)
                h.connect_timeout *= 1000;
            if (h.timeout)
                h.timeout *= 1000;
            return h;
        }
    }
}