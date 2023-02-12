# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%push-parse-options
%new-style
%strict-args
%require-types

public namespace OMQ;

#! defines the class of object returned by the \c "get_schemes()" function in custom user modules
/** @see @ref connection-modules
*/
public class OMQ::ConnectionScheme {
    public {
        #! the name of the scheme
        string name;
        #! DEPRECATED since Qorus 4.0: the callable object to create the object; see subclass docs for details of the arguments for this callable member
        *code maker;
        #! name of the connection class. Eg. "RestConnection"
        string connection_class_name;
        #! the module to load to support the connection
        /** @since Qorus 4.1
        */
        *softlist<string> module_names;
    }

    private {
        Program module_program;
    }

    #! DEPRECATED: creates the object from the arguments passed
    /** @param name the scheme or connection type of the connection (ex: \c "http")
        @param maker a @ref closure "closure" or @ref call_reference "call reference" to code that will return the connection object; this must support the following return type: @ref ConnectionProvider::AbstractConnection, arguments:
        - \c name (@ref string_type "string"): the name of the connection
        - \c desc (@ref string_type "string"): connection description
        - \c url (@ref string_type "string"): connection URL
        - \c monitor (@ref bool_type "bool"): monitoring flag
        - \c opts (@ref hash_or_nothing_type "*hash"): connection options
        - \c urlh (@ref hash_type "hash") broken down URL hash (as returned by @ref Qore::parse_url())

        @deprecated since Qorus 4.0
    */
    constructor(string name, code maker) {
        self.name = name;
        self.maker = maker;
    }

    /** @param name the scheme or connection type of the connection (ex: \c "http")
        @param connection_class_name a name of the AbstractConnection inherited class
        @param module_names an optional list of module names to be loaded before connections are created
    */
    constructor(string name, string connection_class_name, *softlist<string> module_names) {
        self.name = name;
        self.connection_class_name = connection_class_name;
        self.module_names = module_names;
    }

    /*  Set the Program instance in the Connections::addConnectionProvider().
        The Program object has to be valid for the instance lifetime.
        This method is called only for connection providers provided in custom user objects.

        @param module_program Program instance from Connections::addConnectionProvider()

        @note Qorus internal method
     */
    setProgram(Program module_program) {
        self.module_program = module_program;
    }

    /*  Make the real connection object.

        It uses exatcly the same parameters like ConnectionProviders::AbstractConnection

        @note Qorus internal method
     */
    AbstractConnection make(string name, string desc, string url, hash<auto> attributes, hash<auto> options,
            *bool ignore_invalid_options) {
        # first load any required modules
        map load_module($1), module_names;
        # Qorus 4 style of connections
        if (exists connection_class_name) {
            QDBG_LOG("DEBUG: make %y url: %y attr: %y mp: %y ccn: %y", name, url, attributes, module_program,
                connection_class_name);
            # 1) user connection provider = user *.qm files = existing module_program
            if (exists module_program) {
                Reflection::Class class_object = Reflection::Class::forName(module_program, connection_class_name);
                Reflection::ConstructorMethodVariant class_constructor
                     = class_object.getConstructorVariant(
                        Reflection::Type::getType(name),
                        Reflection::Type::getType(desc),
                        Reflection::Type::getType(url),
                        Reflection::Type::getType(attributes),
                        Reflection::Type::getType(options),
                    );
                if (ignore_invalid_options && options) {
                    options = fixOptions(class_object, options);
                }
                return class_constructor.call(name, desc, url, attributes, options);
            } else {
                # 2) builtin connections

                if (ignore_invalid_options && options) {
                    options = fixOptions(Reflection::Class::forName(connection_class_name), options);
                }
                return create_object(connection_class_name, name, desc, url, attributes, options);
            }
        } else if (exists maker) {
            # Qorus 3 legacy object construction - part of "deprecated" stuff
            # qorus4 style of arguments is transformed into deprecated qorus3
            bool monitor = attributes.monitor ?? True;
            # monitor and enabled cannot go into options. Monitor is passed as an arg, enabled is loaded from the DB later.
            hash<auto> opts = {} + attributes - ("monitor", "enabled", "tags", "debug_data") + options;
            hash<auto> urlh = parse_url(url);
            # string name, string desc, string url, bool monitor, *hash opts, hash urlh
            qlog(LoggerLevel::INFO, "WARNING: connection %y uses a deprecated API; please update the connection provider "
                "to use the latest API", name);
            return maker(name, desc, url, monitor, opts, urlh);
        }
        # just a fallback error. It should not go there at all.
        throw "USER-CONNECTION-ERROR", sprintf("Unknown connection module API for %y", name);
    }

    static hash<auto> fixOptions(Reflection::Class class_object, hash<auto> options) {
        try {
            Reflection::ClassConstant constant = class_object.getConstant("ConnectionScheme");
            *hash<auto> connection_options = constant.getValue().options;
            if (connection_options) {
                options = options{keys connection_options};
            }
        } catch (hash<ExceptionInfo> ex) {
            # ignore exceptions
        }
        return options;
    }
}

#! Qorus HTTP connection object
/** accepts the same options as @ref ConnectionProvider::HttpConnection "HttpConnection" as well as:
    - \c conn_timeout: accepted as a synonym for \c connect_timeout
*/
public class OMQ::QorusHttpConnection inherits ConnectionProvider::HttpConnection {
    public {
        string health = "UNKNOWN";
        string instance_key = "unknown";
        string omq_version;
        auto alert_summary; # TODO/FIXME ref 2353 - it looks like it is not used anywhere
        *string error;

        #! Connection entry info
        const ConnectionScheme = <ConnectionSchemeInfo>{
            "cls": Class::forName("QorusHttpConnection"),
            "options": HttpConnection::ConnectionScheme.options + {
                "api_version": <ConnectionOptionInfo>{
                    "type": "string",
                    "desc": "",
                    "default_value": "latest",
                },
                # overrides the HttpConnection definition which is in milliseconds
                "connect_timeout": <ConnectionOptionInfo>{
                    "type": "int",
                    "desc": "connection timeout to use in seconds (default: 45 seconds)",
                    "default_value": 45,
                },
                "ignore_socket_warnings": <ConnectionOptionInfo>{
                    "type": "bool",
                    "desc": "",
                    "default_value": False,
                },
                # overrides the HttpConnection definition which is in milliseconds
                "timeout": <ConnectionOptionInfo>{
                    "type": "int",
                    "desc": "transfer timeout to use in seconds (default: 45 seconds)",
                    "default_value": 45,
                },
            },
        };
    }

    #! creates the QorusHttpConnection object
    /** @param name the name of the connection
        @param desc connection description
        @param url connection URL (potentially with password info)
        @param attributes connection attributes
        @param options connection options
    */
    constructor(string name, string desc, string url, hash<auto> attributes = {}, hash<auto> options = {})
            : HttpConnection(name, desc, url, attributes, QorusHttpConnection::getOptions(options)) {
        # bug 1147: ignore URI path = "/" in remote connections, throw an error for any other path
        if (urlh.path == "/") {
            url = regex_subst(url, urlh.path + "\$", "");
            delete urlh.path;
        } else if (urlh.path) {
            throw "CONNECTION-ERROR", sprintf("Qorus remote connection %s has an error in URL %y contains a URI "
                "path; remove the path from the url and try again", name, url);
        }

        # make qorus:// and qoruss:// -> http:// https://
        self.url = regex_subst(url, "^qorus", "http");
        urlh.protocol = regex_subst(urlh.protocol, "^qorus", "http");

        # issue #3617: do not convert timeout values from seconds to miilliseconds here; they are converted in
        # QorusSystemAPIHelperBase

        checkLoopbackIntern();
    }

    hash<auto> getHealthInfo() {
        return {
            "health": health,
            "instance-key": instance_key,
            "omq-version": omq_version,
            "alert-summary": alert_summary,
            "error": error,
        };
    }

    #! returns a data provider object for this connection
    /** @return a data provider object for this connection
    */
    DataProvider::AbstractDataProvider getDataProvider() {
        QorusClientServer::init();
        return DataProvider::getFactoryObject("remote/" + name);
    }

    #! returns @ref True as all Qorus connections return a data provider with the @ref getDataProvider() method
    /** @return @ref True as all Qorus connections return a data provider with the @ref getDataProvider() method

        @see @ref getDataProvider()
    */
    bool hasDataProvider() {
        return True;
    }

    #! returns a hash with the connection status with \c "ok" and \c "info" keys
    *hash<PingInfo> ping(bool throw_exception = False) {
        hash<PingInfo> rv(self{"name", "desc", "url", "opts"});
        last_check = now_us();

        try {
            QDBG_LOG("PING connection %y opts: %y (c: %d t: %d)", name, opts, opts.connect_timeout, opts."timeout");
            QorusSystemAPIHelper rapi = get();
            auto rh += rapi."get-status"("instance-key", "alert-summary", "health", "omq-version");
            if (!rh.health) {
                rh.health = "UNKNOWN";
            }
            date delta = now_us() - last_check;
            handlePingSuccess(delta);
            updateRemoteHealth(rh);
            rv += {
                "ping_info": rh,
                "ok": True,
                "time": delta,
                "info": "OK",
            };
            return rv;
        } catch (hash<ExceptionInfo> ex) {
            if (throw_exception) {
                rethrow;
            }

            string error = sprintf("%s: %s", ex.err, ex.desc);
            updateRemoteHealth({
                "health": (ex.err == "SOCKET-CONNECT-ERROR" ? "UNREACHABLE" : "ERROR"),
                "error": error,
            });

            date delta = now_us() - last_check;
            handlePingFailed(delta, ex);
            return rv += {
                "ok": False,
                "time": delta,
                "info": sprintf("%s: %s", ex.err, ex.desc),
                "ex": ex,
            };
        }
    }

    updateRemoteHealth(hash<auto> rh) {
        # health
        if (rh.health != self.health) {
            *string old = self.health;
            if (!old)
                old = "UNDEFINED";
%ifdef QorusServer
            Qorus.events.postSystemRemoteHealthChanged(self.name, self.url, rh.health, old, rh."alert-summary",
                rh.error);
%endif
            self.health = rh.health;
        }
        self.instance_key = rh."instance-key" ?? rh."instance_key" ?? "unknown";
        self.omq_version = rh."omq-version" ?? rh."omq_version" ?? "unknown";
        self.alert_summary = rh."alert-summary" ?? rh."alert_summary";
        self.error = rh.error;
        self.updated = now_us();
    }

    Qore::AbstractPollOperation startPollConnect() {
        return getImpl(False).startPollConnect();
    }

    private QorusSystemAPIHelper getImpl(bool connect = True, *hash<auto> rtopts) {
        # QorusSystemAPIHelper has fewer options than QorusHttpConnection
        hash<auto> strip_opts = opts{keys HttpConnection::ConnectionScheme.options};
%ifdef QorusServer
        code init = sub (object obj) {
            MonitorSingleton::setSocketMonitor(obj, {"mon": AlertTypeRemote, "name": name});
            if (debug_data) {
                MonitorSingleton::setEventMonitor(obj, AlertTypeRemote, name);
            }
        };
        QDBG_LOG("new connection %y strip_opts: %y", name, strip_opts);
        QorusSystemAPIHelper ret(strip_opts, init);
%else
        QorusSystemAPIHelper ret(strip_opts);
%endif
        ret.setURL(url);

        if (strip_opts.proxy)
            ret.setProxyURL(strip_opts.proxy);

        if (connect) {
            if (!ret.isConnected())
                ret.reconnect();
            ret.ping();
        }

        return ret;
    }

    #! Returns the ConnectionSchemeInfo hash for this object
    private hash<ConnectionSchemeInfo> getConnectionSchemeInfoImpl() {
        return ConnectionScheme;
    }

    # check loopback is moved here into the connection itself because it allows us
    # to set the loopback flag even in connection updates. Not only in case of
    # reload as it was when this method was part of RemoteMonitor
    private checkLoopbackIntern() {
%ifdef QorusCore
        if (urlh.host == "localhost" || urlh.host == "127.0.0.1" || urlh.host == "::1") {
            string port = (urlh.port ?? (urlh.protocol == "http" ? 80 : 443)).toString();
            # check if port is a port for a system listener
            foreach hash<auto> info in (Qorus.httpServer.getListeners().values()) {
                if (info.family != AF_INET && info.family != AF_INET6) {
                    continue;
                }
                string bind = info.bind;
                # strip any wildcard bind from port
                bind =~ s/^(::|localhost|0.0.0.0)://;
                QDBG_LOG("QorusHttpConnection::checkLoopbackIntern() remote %y loopback bind: %y == %y", name, bind, port);
                if (bind == port) {
                    loopback = True;
                    break;
                }
            }
        }
        if (!loopback) {
            loopback = False;
        }
        qlog(LoggerLevel::INFO, "remote %y loopback: %y", name, self.loopback);
%endif
    }

    private static hash<auto> getOptions(hash<auto> opts) {
        if (opts.conn_timeout) {
            opts.connect_timeout = remove opts.conn_timeout;
        }
        return opts;
    }
}

public class OMQ::Connections {
    public {
        #! list of AbstractConnection public attributes which are appended to Qorus event's info using getAttributes()
        const CONNECTION_ATTRIBUTE_KEYS = (
            "name",
            "desc",
            "last_check",
            "loopback",
            "monitor",
            "debug_data",
            "safe_url",
            "status",
            "up",
            "updated",
            "enabled",
            "tags",
        );

        #! known connection/scheme types to creation code references
        const BuiltinSchemes = {
            "cdsrests": {
                "name": "CdsRestConnection",
                "modules": "CdsRestClient",
            },

            "sftp": {
                "name": "SftpConnection",
                "modules": ("ssh2", "Ssh2Connections"),
            },

            "ftp": {
                "name": "FtpConnection",
            },
            "ftps": {
                "name": "FtpConnection",
            },

            "http": {
                "name": "HttpConnection",
            },
            "https": {
                "name": "HttpConnection",
            },

            "file": {
                "name": "FilesystemConnection",
            },
            "dir": {
                "name": "FilesystemConnection",
            },

            "smtp": {
                "name": "SmtpConnection",
                "modules": "SmtpClient",
            },
            "smtps": {
                "name": "SmtpConnection",
                "modules": "SmtpClient",
            },
            "smtptls": {
                "name": "SmtpConnection",
                "modules": "SmtpClient",
            },
            "esmtp": {
                "name": "SmtpConnection",
                "modules": "SmtpClient",
            },
            "esmtptls": {
                "name": "SmtpConnection",
                "modules": "SmtpClient",
            },

            "pop3": {
                "name": "Pop3Connection",
                "modules": "Pop3Client",
            },
            "pop3s": {
                "name": "Pop3Connection",
                "modules": "Pop3Client",
            },

            "telnet": {
                "name": "TelnetConnection",
                "modules": "TelnetClient",
            },

            "soap": {
                "name": "SoapConnection",
                "modules": "SoapClient",
            },
            "soaps": {
                "name": "SoapConnection",
                "modules": "SoapClient",
            },

            "rest": {
                "name": "RestConnection",
            },
            "rests": {
                "name": "RestConnection",
            },

            "awsrests": {
                "name": "AwsRestConnection",
                "modules": "AwsRestClient",
            },

            "sewiorest": {
                "name": "SewioRestConnection",
                "modules": "SewioRestClient",
            },
            "sewiorests": {
                "name": "SewioRestConnection",
                "modules": "SewioRestClient",
            },

            "sap4hanarests": {
                "name": "Sap4HanaRestConnection",
                "modules": "Sap4HanaRestClient",
            },

            "sewiows": {
                "name": "SewioWebSocketConnection",
                "modules": "SewioWebSocketClient",
            },
            "sewiowss": {
                "name": "SewioWebSocketConnection",
                "modules": "SewioWebSocketClient",
            },

            "sfrests": {
                "name": "SalesforceRestConnection",
                "modules": "SalesforceRestClient",
            },

            "snrests": {
                "name": "ServiceNowRestConnection",
                "modules": "ServiceNowRestClient",
            },

            "zeyosrest": {
                "name": "ZeyosRestConnection",
                "modules": "ZeyosRestClient",
            },
            "zeyosrests": {
                "name": "ZeyosRestConnection",
                "modules": "ZeyosRestClient",
            },

            "billwerkrest": {
                "name": "BillwerkRestConnection",
                "modules": "BillwerkRestClient",
            },
            "billwerkrests": {
                "name": "BillwerkRestConnection",
                "modules": "BillwerkRestClient",
            },

            "yamlrpc": {
                "name": "YamlRpcConnection",
                "modules": "YamlRpcClient",
            },
            "yamlrpcs": {
                "name": "YamlRpcConnection",
                "modules": "YamlRpcClient",
            },

            "xmlrpc": {
                "name": "XmlRpcConnection",
                "modules": "xml",
            },
            "xmlrpcs": {
                "name": "XmlRpcConnection",
                "modules": "xml",
            },

            "jsonrpc": {
                "name": "JsonRpcConnection",
                "modules": "json",
            },
            "jsonrpcs": {
                "name": "JsonRpcConnection",
                "modules": "json",
            },

            "ws": {
                "name": "WebSocketConnectionObject",
                "modules": "WebSocketClient",
            },
            "wss": {
                "name": "WebSocketConnectionObject",
                "modules": "WebSocketClient",
            },

            # datasource/pool/process connections
            "db": {
                "name": "DatasourceConnection",
            },

            # Qorus Remote connections
            "qorus": {
                "name": "QorusHttpConnection",
            },
            "qoruss": {
                "name": "QorusHttpConnection",
            },
        };

        #! known resources that can be required by connection modules
        const ConnectionResources = ("omqservice", "log", "dbglog", "set_socket_monitor");

        #! Connection attributes to pass to alerts
        const ConnectionAlertAttrs = (
            "connection_type",
            "name",
            "description",
            "url",
        );
    }

    private {
        # OMQ.CONNECTIONS table object
        AbstractTable connection_table;
        # OMQ.CONNECTION_TAGS table object
        AbstractTable connection_tags_table;

        # logger function
        code logf;

        # connection hash: name -> connection
        hash<string, ConnectionProvider::AbstractConnection> connection_map;

        # ID map: ID -> connection
        hash<string, ConnectionProvider::AbstractConnection> id_map;

        # connection provider hash
        hash<auto> providers_map;

        RWLock rwl;

        # known schemes
        hash<string, ConnectionScheme> known_schemes;
    }

    #! creates the object and sets the log code reference/closure
    /*  https://bugs.qoretechnologies.com/projects/qorus/wiki/User_Connections
     */
    constructor(AbstractTable n_conn, AbstractTable n_conn_tags, *code log_function, *softlist<auto> cml,
            RWLock rwl = new RWLock()) {
        self.rwl = rwl;
        connection_table = n_conn;
        connection_tags_table = n_conn_tags;
        logf = log_function ? log_function : \OMQ::Connections::logDefault();

        map known_schemes{$1.key} = new ConnectionScheme($1.key, $1.value.name, $1.value.modules),
            BuiltinSchemes.pairIterator();

%ifdef QorusServer
        # set default connection post-processing code
        AbstractConnection::post_processing = sub (AbstractConnection conn, object o) {
            # set socket monitoring
            MonitorSingleton::setSocketMonitor(o, {"mon": conn.internal_info.conn_type, "name": conn.name});
            # set event monitoring
            if (conn.debug_data) {
                MonitorSingleton::setEventMonitor(o, conn.internal_info.conn_type, conn.name);
            }
        };
%endif

        # add external connection handlers
        foreach string mod in (cml) {
            try {
                list<auto> sl = addConnectionProvider(mod);
                logSystem(mod, "loaded user connection provider module handling: %y", sl);
            } catch (hash<ExceptionInfo> ex) {
%ifdef QorusServer
                *string desc = Qorus.getDebugSystem()
                                ? Util::get_exception_string(ex)
                                : sprintf("%s: %s", ex.err, ex.desc);
%else
                *string desc = sprintf("%s: %s", ex.err, ex.desc);
%endif
                logInfo("module %y: failed to load user connection provider module: %s", mod, desc);
            }
        }
    }

    abstract logInfo(string msg);
    abstract logDebug(string msg);
    abstract string getConnectionDbType();
    abstract string getErrorCode();

    # returns the total number of connections
    int size() {
        return connection_map.size();
    }

    *AbstractConnection getConnectionFromIdLocked(int id) {
        QDBG_ASSERT(rwl.lockOwner());
        return id_map{id};
    }

    *AbstractConnection getConnectionFromNameLocked(string name) {
        QDBG_ASSERT(rwl.lockOwner());
        return connection_map{name};
    }

    list<auto> addConnectionProvider(string mod) {
        if (providers_map{mod})
            return providers_map{mod}.schemes;

        Program pgm(PO_NO_INHERIT_PROGRAM_DATA);
        auto load_output = pgm.loadModuleWarn(mod, WARN_DEPRECATED);
        if (load_output) {
            logSystem(mod, "WARNING module uses a deprecated API; please update your source code");
        }

%ifdef QorusServer
        pgm.setScriptPath(sprintf("%s/%s/%s", Qorus.options.get("instance-key"), "Connection", mod));
%endif

        # first set module resources
        list<auto> rl;
        try {
            rl = pgm.callFunction("required_resources");
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err != "NO-FUNCTION")
                rethrow;
        }

        if (rl) {
            hash<auto> rh;
            foreach string rsrc in (rl) {
                switch (rsrc) {
                    case "omqservice": rh.omqservice = omqservice; break;
%ifdef QorusServer
                    case "log": rh.log = sub (string fmt) { logInfo(fmt, argv); }; break;
                    case "errlog": rh.errlog = sub (string fmt) { logInfo(fmt, argv); }; break;
                    case "dbglog": rh.dbglog = sub (string fmt) { logDebug(fmt, argv); }; break;
%else
                    case "log": rh.log = sub (string fmt) { vprintf("INFO: " + fmt + "\n", argv); }; break;
                    case "errlog": rh.errlog = sub (string fmt) { vprintf("ERROR: " + fmt + "\n", argv); }; break;
                    case "dbglog": rh.dbglog = sub (string fmt) { vprintf("DEBUG: " + fmt + "\n", argv); }; break;
%endif
                    # deprecated; socket and event monitors installed by default on all new connections
                    case "set_socket_monitor": rh.set_socket_monitor = sub (object obj, string name) {}; break;
                    default: throw "RESOURCE-ERROR", sprintf("unknown connection resource %y; known resources: %y",
                        rsrc, ConnectionResources);
                }
            }

            pgm.callFunction("set_resources", rh);
        }

        providers_map{mod}.schemes = ();

        foreach ConnectionScheme scheme in (pgm.callFunction("get_schemes")) {
            try {
                if (known_schemes{scheme.name}) {
                    throw getErrorCode(), sprintf("scheme %y is already registered", scheme.name);
                }

                # save the Program container to ensure that the factory objects returned above remain valid
                scheme.setProgram(pgm);
                known_schemes{scheme.name} = scheme;
                push providers_map{mod}.schemes, scheme.name;
            } catch (hash<ExceptionInfo> ex) {
                # remove all schemes already registered by this module
                map delete known_schemes.$1, providers_map{mod}.schemes.iterator();
                rethrow;
            }
        }

        return providers_map{mod}.schemes;
    }

    *hash<string, hash<auto>> reload() {
        # get an object that will hold the write lock and release it when the variable goes out of scope
        AutoWriteLock wlh = getWriteLockHelper();

        return reloadIntern();
    }

    # return some (safe) public attributes of the given connection
    /*
        @param name a connection name
        @return hash with keys/attributes as defined in CONNECTION_ATTRIBUTE_KEYS
     */
    hash<auto> getAttributes(string name) {
        ReadLockHelper rlh(rwl);

        # getConnection()/getConnectionIntern() is not used here with a reason.
        # these methods are checking for status of the connection:
        # up/down, enabled/disabled can theoretically throw an exception
        # during accessing the attributes. This is simple read-only method
        # where we want to access connection's attributes as-is.
        return connection_map.hasKey(name) ? connection_map{name}{CONNECTION_ATTRIBUTE_KEYS} : {};
    }

    hash<string, ConnectionProvider::AbstractConnection> getConnections() {
        return connection_map;
    }

    *ConnectionProvider::AbstractConnection tryGetConnection(string name) {
        ReadLockHelper rlh(rwl);

        *AbstractConnection conn = connection_map{name};
        if (!conn || (conn instanceof InvalidConnection)) {
            return;
        }
        return Connections::checkConnectionEnabled(conn);
    }

    ConnectionProvider::AbstractConnection getConnection(string name) {
        ReadLockHelper rlh(rwl);

        return getConnectionIntern(name);
    }

    private AutoWriteLock getWriteLockHelper() {
        return new AutoWriteLock(rwl);
    }

    private ConnectionProvider::AbstractConnection getConnectionIntern(string name) {
        if (!connection_map{name})
            throw getErrorCode(), sprintf("cannot retrieve unknown user connection %y; known user connections: %y",
                name, connection_map.keys());

        # This check (and this call) is performed only in the QorusClientCore module.
        # Real runtime Qorus processing is done in inherited classes and also in
        # the ConnectionDependencyManager class.
        return Connections::checkConnectionEnabled(connection_map{name});
    }

    object get(string name, bool connect = True, *hash rtopts) {
        ReadLockHelper rlh(rwl);

        AbstractConnection conn = getConnectionIntern(name).get(connect, rtopts);
        # This check (and this call) is performed only in QorusClientCore module.
        # Real runtime Qorus processing is done in inherited classes and also in
        # the ConnectionDependencyManager class.
        Connections::checkConnectionEnabled(conn);

        return conn;
    }

    static ConnectionProvider::AbstractConnection checkConnectionEnabled(AbstractConnection conn) {
        if (!conn.enabled) {
            throw "CONNECTION-DISABLED", sprintf("Connection %s has been disabled by a user", conn.name);
        }
        return conn;
    }

    /*  Return connection type as required by OMQ.CONNECTIONS.CONNECTION_TYPE column value.
        Basically it's a map of AbstractConnection to a connection type as in system DB
     */
    string getQorusConnectionType(AbstractConnection connection) {
        # Reflection is used here because:
        # - it's cool
        # - instanceof operator requires the presence of DatasourceConnection in qwf, qsvc, and qjob processes
        #   And it's not necessary to be there...
        Reflection::Class c = Reflection::Class::getClass(connection);

        if (c.getInheritanceAccess(Reflection::Class::forName("OMQ::DatasourceConnection"))) {
            return "DATASOURCE";
        } else if (c.getInheritanceAccess(Reflection::Class::forName("OMQ::QorusHttpConnection"))) {
            return "REMOTE";
        }
        return "USER";
    }

    list<auto> list(bool monitored_only = False, bool remote_only = False) {
        ReadLockHelper rlh(rwl);

        return map $1.getExtendedInfo() + {
            "connectionid": $1.internal_info.id,
        }, connection_map.iterator(), (!monitored_only || $1.monitored);
    }

    *hash<string, hash<auto>> getInfo(*hash<auto> opts) {
        ReadLockHelper rlh(rwl);

        return cast<hash<string, hash<auto>>>(map {
            $1.key: $1.value.getExtendedInfo() + {
                "connectionid": $1.value.internal_info.id,
            }}, connection_map.pairIterator());
    }

    *hash<auto> getInfo(string name, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        ReadLockHelper rlh(rwl);

        *AbstractConnection c = connection_map{name};
        if (c) {
            return c.getExtendedInfo(opts) + {
                "connectionid": c.internal_info.id,
            };
        }
    }

    hash<auto> getInfoEx(string name, *hash<auto> opts) {
        if (opts.with_password) {
            opts.with_passwords = remove opts.with_password;
        }

        ReadLockHelper rlh(rwl);

        *AbstractConnection c = connection_map{name};
        if (c) {
            return c.getExtendedInfo(opts) + {
                "connectionid": c.internal_info.id,
            };
        }
        throw "CONNECTION-ERROR", sprintf("%s connection %y is unknown; known connections: %y",
            getConnectionDbType(), name, keys connection_map);
    }

    # called with the lock held
    private hash<auto> getInfoIntern(AbstractConnection c, *hash<auto> opts) {
        QDBG_ASSERT(rwl.lockOwner());

        return c.getExtendedInfo(opts) + {
            "connection_type": getConnectionDbType(),
            "connectionid": c.internal_info.id,
        };
    }

    private hash<auto> getSelectHash() {
        return {
            "where": {
                "connection_type": getConnectionDbType(),
            },
        };
    }

    #! returns a hash of updates
    /** @return a hash of updates keyed by connection name with \c old_conn and \c new_conn keys
    */
    private *hash<string, hash<auto>> reloadIntern() {
        hash<string, hash<auto>> updates;

        hash<auto> sh = getSelectHash();

        hash<auto> conn_select;
        hash<auto> tag_select;
        # make selects in advance
        QorusRestartableTransaction trans(connection_table.getDriverName());
        while (True) {
            try {
                on_error connection_table.rollback();

                conn_select = connection_table.select(sh);
                tag_select = connection_tags_table.select({
                    "where": {
                        "connectionid": op_in(conn_select.connectionid)
                    },
                });
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            break;
        }

        # map tags to connection; connection name -> tag name -> value
        hash<auto> tags;
        map tags{$1.name}{$1.tag} = deserialize_qorus_data($1.value), tag_select.contextIterator();

%ifdef QorusServer
        QdspStatement stmt = connection_table.getStatement(sh);
%else
        SQLStatement stmt = connection_table.getStatement(sh);
%endif
        # get hash of connections loaded
        hash<string, bool> ch;

        on_exit stmt.rollback();
        while (stmt.next()) {
            ch{stmt.name} = True;
            try {
                updates{stmt.name} = reloadConnection(stmt, getConnectionValues(stmt), tags);
            } catch (hash<ExceptionInfo> ex) {
                connectionErrorImpl(ex, stmt.name, stmt.getValue(){ConnectionAlertAttrs});
                string err = sprintf("%s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);
                hash<auto> attributes = {
                    "error": err,
                };
                InvalidConnection c(stmt.name, stmt.description, stmt.url, attributes);
                # mark connection ID
                c.internal_info.id = stmt.connectionid;
                if (connection_map{stmt.name}) {
                    updates{stmt.name} = {
                        "old_conn": connection_map{stmt.name},
                        "new_conn": NOTHING,
                    };
                }
                id_map{stmt.connectionid} = connection_map{stmt.name} = c;
                log(stmt.name, "registering invalid connection (%s) url: %y: %s", stmt.description, stmt.url,
                    get_exception_string(ex));
            }
        }
        # add connections no longer present
        foreach hash<auto> i in ((connection_map - (keys ch)).pairIterator()) {
            updates{i.key} = {
                "old_conn": i.value,
                "new_conn": NOTHING,
            };
        }

        return updates;
    }

    private hash<auto> getConnectionValues(AbstractSQLStatement stmt) {
        return stmt.getValue();
    }

    private hash<auto> reloadConnection(AbstractSQLStatement stmt, hash<auto> row, *hash<auto> tags) {
        *hash<auto> opts = deserialize_qorus_data(stmt.options) ?? {};
        if (row.loggerid) {
            opts.loggerid = row.loggerid;
        }
        hash<auto> attributes = {
            "monitor": boolean(row.monitor),
            "enabled": boolean(row.enabled),
            "tags": tags{row.name},
            "debug_data": row.debug_data.toBool(),
        };

        AbstractConnection c = newConnection(stmt.name, stmt.description, row.url, attributes, opts);
        # mark connection type
        c.internal_info.conn_type = getConnectionDbType();
;
        # mark connection ID
        c.internal_info.id = stmt.connectionid;
        QDBG_ASSERT(c.internal_info.id.typeCode() == NT_INT);
        hash<auto> rv = {
            "old_conn": connection_map{stmt.name},
            "new_conn": c,
        };
        c.enabled = boolean(stmt.enabled);
        id_map{stmt.connectionid} = connection_map{stmt.name} = c;
        connectionLoadedImpl(stmt.name);
        return rv;
    }

    private connectionLoadedImpl(string name) {
    }

    private connectionDeletedImpl(string name) {
    }

    private connectionErrorImpl(hash ex, string name, hash<auto> h) {
    }

    AbstractConnection removeConnection(int id, AtomicConnectionHelper ach) {
%ifdef QorusServer
        QDBG_ASSERT(Qorus.connection_rwl.lockOwner());
%endif
        QDBG_ASSERT(id_map{id});
        AbstractConnection c = remove id_map{id};
        QDBG_ASSERT(c.internal_info.id == id);
        QDBG_ASSERT(connection_map{c.name});
        remove connection_map{c.name};
        return c;
    }

    AbstractConnection replace(string name, string desc, string url, hash<auto> attributes = {},
            hash<auto> options = {}, *reference<bool> do_reset) {
        AbstractConnection c = newConnection(name, desc, url, attributes, options);
        QDBG_LOG("DEBUG: (Connections) name: %y (%s) url: %y attr: %y (tags: %y)", name, desc, url, attributes, c.getTags());

        {
            # get an object that will hold the write lock and release it when the variable goes out of scope
            AutoWriteLock wlh = getWriteLockHelper();

            AbstractConnection old_conn = checkReplaceIntern(name);
            c.internal_info.id = old_conn.internal_info.id;
            replaceIntern(name, c, old_conn);

            if (old_conn.url != url || old_conn.opts != options) {
                do_reset = True;
            }
        }

        return c;
    }

    #! Returns the old connection or throws an exception if the connection does not exist or is locked
    private AbstractConnection checkReplaceIntern(string name) {
        if (!connection_map{name}) {
            throw getErrorCode(), sprintf("connection %y does not exist; known connections: %y", name,
                connection_map.keys());
        }

        if (connection_map{name}.locked) {
            throw getErrorCode(), sprintf("connection %y is locked and cannot be updated", name);
        }

        return connection_map{name};
    }

    #! Replaces a connection
    /** must be called with the write lock held
    */
    private replaceIntern(string name, AbstractConnection new_connection, AbstractConnection old_connection) {
        updateConnection(new_connection, True); # True = set manually updated in DB
        new_connection.updated = now_us();
        QDBG_ASSERT(new_connection.internal_info.id);
        int id = new_connection.internal_info.id;
        id_map{id} = connection_map{name} = new_connection;
    }

    AbstractConnection del(string name) {
        AbstractConnection c;
        int id;
        {
            # get an object that will hold the write lock and release it when the variable goes out of scope
            AutoWriteLock wlh = getWriteLockHelper();

            if (!connection_map{name})
                throw getErrorCode(), sprintf("connection %y does not exist; known connections: %y", name,
                    keys connection_map);

            if (connection_map{name}.locked)
                throw getErrorCode(), sprintf("connection %y is locked and cannot be deleted", name);

            QDBG_ASSERT(connection_map{name}.internal_info.id);
            id = connection_map{name}.internal_info.id;

            deleteConnection(connection_map{name});

            # do not delete the object here as it will trigger a race condition
            # let it go out of scope naturally (issue 1674)
            c = remove connection_map{name};
            remove id_map{id};
        }

        return c;
    }

    AbstractConnection removeConnection(string name) {
        # get an object that will hold the write lock and release it when the variable goes out of scope
        AutoWriteLock wlh = getWriteLockHelper();

        *AbstractConnection conn = connection_map{name};
        if (!conn) {
            throw getErrorCode(), sprintf("onnection %y does not exist; known connections: %y", name,
                keys connection_map);
        }

        if (conn.locked) {
            throw getErrorCode(), sprintf("connection %y is locked and cannot be updated or deleted", name);
        }

        QDBG_ASSERT(conn.internal_info.id);
        remove id_map{conn.internal_info.id};
        remove connection_map{name};

        return conn;
    }

    hash<PingInfo> ping(string name) {
        *AbstractConnection c;

        {
            ReadLockHelper rlh(rwl);

            c = connection_map{name};
            if (!c)
                throw getErrorCode(), sprintf("connection %y does not exist; known connections: %y", name,
                    keys connection_map);
        }

        return c.ping();
    }

    logSystem(string name, string fmt) {
        fmt = sprintf("Connections: %s %y: ", getConnectionDbType().lwr(), name) + fmt;
        call_function_args(logf, Qore::list(fmt) + (argv ? argv : NOTHING));
    }

    log(string name, string fmt) {
        fmt = sprintf("Connections: %s %y: ", getConnectionDbType().lwr(), name) + fmt;
        call_function_args(logf, Qore::list(fmt) + (argv ? argv : NOTHING));
    }

    #! the default logging action is to print out the log message to stderr
    private static logDefault(string msg) {
        stderr.vprintf(msg + "\n", argv);
        stderr.sync();
    }

    private insertConnection(AbstractConnection c, *int id) {
        insertDbConnectionIntern(c, id);
        log(c.name, "new connection (%s) registered with url: %y opts: %y", c.desc, c.url, c.getRealOptions());
    }

    private updateConnection(AbstractConnection c, bool set_updated) {
        updateDbConnectionIntern(c, set_updated);
        connectionLoadedImpl(c.name);
        log(c.name, "connection (%s) updated with url: %y opts: %y", c.desc, c.url, c.getRealOptions());
    }

    private deleteConnection(AbstractConnection c) {
        deleteDbConnectionIntern(c);
        log(c.name, "connection deleted");
        connectionDeletedImpl(c.name);
    }

    private insertDbConnectionIntern(AbstractConnection c, *int id) {
        on_success connection_table.commit();
        on_error connection_table.rollback();

        # get PK hash
        hash<auto> pkh = {
            "connectionid": id ??
%ifdef QorusServer
                sqlif.getNextSequenceValue("seq_connections"),
%else
                omqclient.getSQLIF().getNextSequenceValue("seq_connections"),
%endif
        };
        c.internal_info.id = pkh.connectionid;

        hash<auto> ih = pkh + {
            "connection_type": getQorusConnectionType(c),
            "name": c.name,
            "description": c.desc,
            "url": c.url,
            "options": serialize_qorus_data(c.getRealOptions() ?? {}),
            "enabled" : int(c.enabled),
            "debug_data": int(c.debug_data),
        };

        connection_table.insert(ih);

        # do tags
        insertTagsIntern(c, pkh);
    }

    private updateDbConnectionIntern(AbstractConnection c, bool set_updated) {
        on_success connection_table.commit();
        on_error connection_table.rollback();

        hash<auto> uh = {
            "connection_type": getQorusConnectionType(c),
            "name": c.name,
            "description": c.desc,
            "url": c.url,
            "options": serialize_qorus_data(c.getRealOptions() ?? {}),
            # bool/int conversion because of underlying DB storage. Some DBMS engines do not have BOOL
            "enabled": int(c.enabled),
            "debug_data": int(c.debug_data),
        };
        if (set_updated) {
            uh.manually_updated = 1;
        }

        # get where hash
        hash<auto> wh = {
            "connectionid": c.internal_info.id,
        };

        # clear any tags
        connection_tags_table.del(wh);
        connection_table.update(uh, wh);

        insertTagsIntern(c, wh);
    }

    private insertTagsIntern(AbstractConnection c, hash<auto> wh) {
        if (hash<auto> tags = c.getTags()) {
            map connection_tags_table.insert(wh + {
                "tag": $1.key,
                "value": serialize_qorus_data($1.value),
            }), tags.pairIterator();
        }
    }

    private deleteDbConnectionIntern(AbstractConnection c) {
        on_success connection_table.commit();
        on_error connection_table.rollback();
        # issue #3700: delete connection tags before deleting connection
        connection_tags_table.del({"connectionid": c.internal_info.id});
        connection_table.del({"connectionid": c.internal_info.id});
    }

    AbstractConnection newConnection(string name, string desc, string url, hash<auto> attributes = {},
            hash<auto> options = {}, *bool ignore_invalid_options) {
        string conn_type = getConnectionDbType();
        *string scheme_name;
        try {
            switch (conn_type) {
                case "USER":
                    scheme_name = parse_url(url).protocol;
                    break;
                case "REMOTE":
                    scheme_name = "qorus";
                    break;
                case "DATASOURCE":
                    scheme_name = "db";
                    break;
                default:
                    # this is for client/oload
                    if (url =~ /^db:/) {
                        scheme_name = "db";
                    } else if (url =~ /^qorus/) {
                        scheme_name = "qorus";
                    } else {
                        scheme_name = parse_url(url).protocol;
                    }
            }
        } catch (hash<ExceptionInfo> ex) {
            QDBG_ASSERT(ex.err == "PARSE-URL-ERROR");
            throw "URL-ARG-ERROR", sprintf("cannot parse URL %y for connection %y: %s", url, name, ex.desc);
        }
        if (!exists scheme_name) {
            throw "URL-ARG-ERROR", sprintf("cannot parse URL for connection %y: no scheme present in URL %y", name,
                url);
        }

        if (!known_schemes.hasKey(scheme_name)) {
            throw "URL-ARG-ERROR", sprintf("connection %y has unknown scheme/protocol %y in URL %y; known "
                "schemes/protocols: %y", name, scheme_name, url, known_schemes.keys());
        }

        ConnectionScheme scheme;
        {
            ReadLockHelper rlh(rwl);

            scheme = known_schemes{scheme_name};
        }

        AbstractConnection c = scheme.make(name, desc, url, attributes, options ?? {}, ignore_invalid_options);
        # mark connection type
        c.internal_info.conn_type = conn_type;
        return c;
    }

    # A base class enable() implementation. It's just a wrapper around DB
    # update only. The real Qorus related implementation stays in the inherited
    # classes
    enable(string name) {
        enableIntern(name, True);
    }

    # A base class enable() implementation. It's just a wrapper around DB
    # update only. The real Qorus related implementation stays in the inherited
    # classes
    disable(string name) {
        enableIntern(name, False);
    }

    #! updates the DB entry for the connection to enable data debugging for the given connection
    enableDebugData(string name) {
        enableDebugDataIntern(name, True);
    }

    #! updates the DB entry for the connection to disable data debugging for the given connection
    disableDebugData(string name) {
        enableDebugDataIntern(name, False);
    }

    # An internal method to handle enable/disable flag in a connection
    private bool enableIntern(string name, bool enable) {
        # get an object that will hold the write lock and release it when the variable goes out of scope
        AutoWriteLock wlh = getWriteLockHelper();

        AbstractConnection c = connection_map{name};
        if (enable == c.enabled) {
            return False;
        }

        updateIntern(c, {"enabled": int(enable)});
        c.enabled = enable;
        return True;
    }

    # An internal method to handle enable/disable flag in a connection
    private bool enableDebugDataIntern(string name, bool debug_data) {
        # get an object that will hold the write lock and release it when the variable goes out of scope
        AutoWriteLock wlh = getWriteLockHelper();

        AbstractConnection c = connection_map{name};
        if (debug_data == c.debug_data) {
            return False;
        }

        updateIntern(c, {"debug_data": int(debug_data)});
        c.debug_data = debug_data;
        return True;
    }

    # An internal method to update connection rows in the DB; must be already locked
    private bool updateIntern(AbstractConnection c, hash<auto> cond) {
        QDBG_ASSERT(c.internal_info.id);
        QorusRestartableTransaction trans(connection_table.getDriverName());
        while (True) {
            try {
                on_success connection_table.commit();
                on_error connection_table.rollback();

                QDBG_LOG("Connections::updateIntern() conf: %y id: %y", cond, c.internal_info.id);
                connection_table.update(cond, {
                    "connectionid": c.internal_info.id,
                });
            } catch (hash<ExceptionInfo> ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex)) {
                    continue;
                }
                rethrow;
            }
            break;
        }

        return True;
    }
}

class AtomicConnectionHelper {
    private {
        list<code> post_actions;
    }

    constructor() {
%ifdef QorusServer
        Qorus.connection_rwl.writeLock();
%endif
    }

    destructor() {
%ifdef QorusServer
        Qorus.connection_rwl.writeUnlock();
%endif
        map $1(), post_actions;
    }

    addPostAction(code action) {
        post_actions += action;
    }
}

class ReadLockHelper {
    private {
        RWLock rwl;
    }

    constructor(RWLock rwl) {
        if (!rwl.lockOwner()) {
            rwl.readLock();
            self.rwl = rwl;
        }
    }

    destructor() {
        if (rwl) {
            rwl.readUnlock();
        }
    }
}

class WriteLockHelper {
    private {
        RWLock rwl;
    }

    constructor(RWLock rwl) {
        if (!rwl.writeLockOwner()) {
            rwl.writeLock();
            self.rwl = rwl;
        }
    }

    destructor() {
        if (rwl) {
            rwl.writeUnlock();
        }
    }
}
