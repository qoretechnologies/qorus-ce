# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args

class OMQ::ServerMapperContainer inherits MapperContainerBase {
    private {
        hash<auto> serverOptions;
        #! we need to strip types here
        hash serverFields;

        # input provider factory
        AbstractDataProviderFactory input_factory;
        # input provider path
        *list<string> input_provider_path;
        # input provider creation options
        *hash<auto> input_provider_create_options;
        # if input provider creations options should be resolved at runtime
        bool input_provider_create_options_dynamic;

        # ouput provider factory
        AbstractDataProviderFactory output_factory;
        # output provider path
        *list<string> output_provider_path;
        # output provider creation options
        *hash<auto> output_provider_create_options;
        # if output provider creations options should be resolved at runtime
        bool output_provider_create_options_dynamic;

        # initialization flag
        bool init;

        # save the first error for reporting if the mapper is invalid
        # if this member has a value, the mapper is not valid
        string err;

        const SortLast = "zzzzzzzzzzzz";

        # mutually-exclusive input options
        const InputOptions = (
            "mapper-input",
            "input",
            "input-type",
            "input-provider",
        );

        # mutually-exclusive output options
        const OutputOptions = (
            "mapper-output",
            "output",
            "output-type",
            "output-provider",
        );
    }

    public {
        # qorus server mapper keys with handlers
        const QorusServerMapperKeys = {
            "context": cast<hash<MapperRuntimeKeyInfo>>(QorusMapperKeys."context" + {
                "handler": auto sub (auto value, hash<auto> ctx, *reference<bool> missing_input) {
                    return UserApi::expandTemplatedValue(value, ctx, True, \missing_input);
                },
            }),
            "template": cast<hash<MapperRuntimeKeyInfo>>(QorusMapperKeys."template" + {
                "handler": auto sub (bool val, auto arg, hash<auto> ctx, *reference<bool> missing_input) {
                    return val
                        ? UserApi::expandTemplatedValue(arg, ctx, True, \missing_input)
                        : arg;
                },
            }),
            "value_lookup": cast<hash<MapperRuntimeKeyInfo>>(QorusMapperKeys."value_lookup" + {
                "handler": auto sub (string val, hash<auto> ctx, *reference<bool> missing_input) {
                    auto new_arg = UserApi::expandTemplatedValue(val, ctx, True, \missing_input);
                    if (new_arg.typeCode() != NT_STRING) {
                        throw "VALUE-LOOKUP-ERROR", sprintf("\"value-lookup\" argument %y expands to type %y (%y); "
                            "must be or expand to a string in the following format: \"<value-map-name>.<key-name>\"",
                            val, new_arg.type(), new_arg);
                    }
                    (*string vmap, *string key) = (new_arg =~ x/^([^\.]+).(.*)$/);
                    if (!exists vmap || !exists key) {
                        throw "VALUE-LOOKUP-ERROR", sprintf("\"value-lookup\" argument %y does not have format: "
                            "\"<value-map-name>.<key-name>\"", new_arg);
                    }
                    return UserApi::getValueMap(vmap, key);
                },
            }),
        };
    }

    constructor(softint mid, string n, string v, *string pt, *string d, AbstractMapperType m, *string parse_options,
                string fields_, *string options_string, date created, date modified, bool is_yaml, *bool no_exception)
            : MapperContainerBase(mid, n, v, pt, d, m, parse_options, fields_, options_string, Qorus.getRuntimeProps(),
                                  created, modified, is_yaml, no_exception) {
        # get runtime field hash
        try {
            serverFields = exec("fields");
            if (!serverFields) {
                error("mapper has an empty field declaration; mappers must have at least one field to map to be valid");
            }
        } catch (hash<ExceptionInfo> ex) {
            if (Qorus.getDebugSystem()) {
                error(get_exception_string(ex));
            } else {
                error(ex.desc);
            }
        }

        # serverFields may be NOTHING in case of an invalid mapper
        fields = serverFields ?? {};
        prepareFields();

        # resolve any code strings to call references
        if (!(m instanceof InvalidMapperType)) {
            try {
                # do not process options for invalid mappers
                map serverFields{$1.key}."code" = p.getCallReference($1.value."code"),
                    serverFields.pairIterator(), $1.value."code".typeCode() == NT_STRING;
            } catch (hash<ExceptionInfo> ex) {
                if (Qorus.getDebugSystem()) {
                    error(get_exception_string(ex));
                } else {
                    error(ex.desc);
                }
            }
        }

        if (options_string) {
            try {
                # use += so "serverOptions" stays "hash<auto>"
                serverOptions += exec("options");

                QDBG_LOG("INIT mapper %y type: %s", name, m.className());

                # issue #444: check and fix option source with custom fields
                fixOptionSource("mapper-input");
                fixOptionSource("mapper-output");

                # do not process options for invalid mappers
                if (!(m instanceof InvalidMapperType)) {
                    # issue #2133: ensure that input and output record descriptions are hashes if they exist
                    if (exists serverOptions.input && serverOptions.input.typeCode() != NT_HASH) {
                        error("the input record description must be type \"hash\"; got type %y instead", serverOptions.input.type());
                    }
                    if (exists serverOptions.output && serverOptions.output.typeCode() != NT_HASH) {
                        error("the output record description must be type \"hash\"; got type %y instead", serverOptions.output.type());
                    }

                    # ensure that multiple mutually-exclusive options are not provided
                    if ((*hash<auto> input_opts = serverOptions{InputOptions}).size() > 1) {
                        error("maximum one of %y can be provided", keys input_opts);
                    }
                    if ((*hash<auto> output_opts = serverOptions{OutputOptions}).size() > 1) {
                        error("maximum one of %y can be provided", keys output_opts);
                    }

                    if (serverOptions."mapper-input") {
                        if (serverOptions."input".val()) {
                            error("cannot have both \"mapper-input\" and \"input\" options");
                        }
                        getIoInfo("input");
                    } else if (serverOptions.input) {
                        serverOptions.input = Mapper::getInputFromHash(serverOptions.input);
                    } else if (serverOptions."input-type") {
                        setType("input", remove serverOptions."input-type");
                    } else if (serverOptions."input-connection") {
                        setProviderFromConnection("input", remove serverOptions{"input-connection"}, Qorus.connections);
                    } else if (serverOptions."input-datasource") {
                        setProviderFromConnection("input", remove serverOptions{"input-datasource"}, Qorus.dsmanager);
                    } else if (serverOptions."input-remote") {
                        setProviderFromConnection("input", remove serverOptions{"input-remote"}, Qorus.remotemonitor);
                    } else if (serverOptions."input-factory") {
                        setProviderFromFactory("input", remove serverOptions."input-factory",
                            remove serverOptions{"input-provider-create-options"});
                    }

                    if (serverOptions."mapper-output") {
                        if (serverOptions."output".val()) {
                            error("cannot have both \"mapper-output\" and \"output\" options");
                        }
                        getIoInfo("output");
                    } else if (serverOptions.output) {
                        serverOptions.output = Mapper::getOutputFromHash(serverOptions.output);
                    } else if (serverOptions."output-type") {
                        setType("output", remove serverOptions."output-type");
                    } else if (serverOptions."output-connection") {
                        setProviderFromConnection("output", remove serverOptions{"output-connection"}, Qorus.connections);
                    } else if (serverOptions."output-datasource") {
                        setProviderFromConnection("output", remove serverOptions{"output-datasource"}, Qorus.dsmanager);
                    } else if (serverOptions."output-remote") {
                        setProviderFromConnection("output", remove serverOptions{"output-remote"}, Qorus.remotemonitor);
                    } else if (serverOptions."output-factory") {
                        setProviderFromFactory("output", remove serverOptions."output-factory",
                            remove serverOptions{"output-provider-create-options"});
                    }

                    if (!exists serverOptions.input && !serverOptions.input_provider && mtype.requiresInput() && !input_factory) {
                        error("failed to initialize mapper; missing required \"input\" option in mapper describing the input record");
                    }
                    if (!serverOptions.output && !serverOptions.output_provider && mtype.requiresOutput() && !output_factory) {
                        error("failed to initialize mapper; missing required \"output\" option in mapper describing the output record");
                    }
                }

                # issue #3265: add support for the "context" and "template" keys to every mapper
                serverOptions.runtime_keys += QorusServerMapperKeys;
            } catch (hash<ExceptionInfo> ex) {
                if (Qorus.getDebugSystem()) {
                    error("%s", get_exception_string(ex));
                } else {
                    error("%s: %s", ex.err, ex.desc);
                }
            }
        }

        # to avoid getting an OBJECT-ALREADY-DELETED exception when the ServerMapperContainer object is deleted
        # while a mapper is in use
        string tname = name;
        serverOptions += {
            "name": tname,
            "input_log": sub (hash<auto> h) {
                qlog(LoggerLevel::DEBUG, "Mapper %y: input: %y", tname, h);
            },
            "output_log": sub (hash<auto> h) {
                qlog(LoggerLevel::DEBUG, "Mapper %y: output: %y", tname, h);
            },
            "info_log": sub (string fmt) {
                UserApi::logArgsInfo(fmt, argv);
            },
            "submapper_get": Mapper sub (string name, *hash<auto> opts) {
                return UserApi::getMapper(name, opts);
            },
            "template_subst": \UserApi::expandTemplatedValue(),
        };
    }

    static AbstractDataProvider getProvider(string path, object connserver, *int mapperid) {
        list<string> connection_path = path.split("/");
        path = shift connection_path;
        AbstractDataProvider prov = connserver.getDataProvider(path, mapperid);
        map prov = prov.getChildProviderEx($1), connection_path;
        return prov;
    }

    private:internal fixOptionSource(string key) {
        if (!option_source{key}) {
            return;
        }
        option_source{key} = make_yaml(serverOptions{key} - "custom-fields");
    }

    private:internal setProviderFromFactory(string pfx, string factory_name, *hash<auto> provider_create_options,
            *bool dynamic) {
        *list<string> provider_path;
        if (factory_name.val() && factory_name != "/") {
            provider_path = factory_name.split("/");
        }
        factory_name = shift provider_path;
        self{pfx + "_provider_path"} = provider_path;
        AbstractDataProviderFactory factory = DataProvider::getFactoryEx(factory_name);

        if (!dynamic && !needRuntimeOptions(provider_create_options)) {
            AbstractDataProvider provider = factory.create(provider_create_options);
            if (provider_path) {
                map provider = provider.getChildProviderEx($1), provider_path;
            }
            serverOptions{pfx} = provider.getRecordType();
            serverOptions{pfx + "_provider"} = provider;
        } else {
            # try to create the provider
            try {
                hash<auto> ah = {
                    "provider_options": provider_create_options,
                };
                process_factory_args(\ah);
                AbstractDataProvider provider = factory.createWithTemplate(ah.template_options, ah.provider_options);
                if (provider_path) {
                    map provider = provider.getChildProviderEx($1), provider_path;
                }
                serverOptions{pfx} = provider.getRecordType();
                serverOptions{pfx + "_provider"} = provider;
            } catch (hash<ExceptionInfo> ex) {
                # ignore exceptions: mapper can only be created at runtime
            }

            # save for later execution
            self{pfx + "_provider_create_options"} = provider_create_options;
            self{pfx + "_factory"} = factory;
            if (dynamic) {
                self{pfx + "_provider_create_options_dynamic"} = True;
            }
        }
    }

    private:internal getIoInfo(string io) {
        hash<auto> io_info = serverOptions{"mapper-" + io};
        remove serverOptions{"mapper-" + io}."custom-fields";
        # ensure path is prefixed with "/"
        if (io_info.path && io_info.path !~ /^\//) {
            io_info.path = "/" + io_info.path;
        }
        switch (io_info.type) {
            case "connection":
                setProviderFromConnection(io, io_info.name + io_info.path, Qorus.connections, io_info);
                break;

            case "datasource":
                setProviderFromConnection(io, io_info.name + io_info.path, Qorus.dsmanager);
                break;

            case "remote":
                setProviderFromConnection(io, io_info.name + io_info.path, Qorus.remotemonitor, io_info);
                break;

            case "type":
                if (!io_info.name.val()) {
                    error("invalid mapper hash %y option; type missing \"name\": %y", io, io_info);
                }
                string path = io_info.name + io_info.path;
                if (io_info.subtype) {
                    path += "/" + io_info.subtype;
                }
                #QDBG_LOG("DEBUG mapper %s v%s%s (%d): dir: %y io_info: %y", name, version, patch, mapperid, io, io_info);
                setType(io, path, io_info."custom-fields");
                break;

            case "factory": {
                # issue #3645: fix factory option handling
                bool dynamic;
                if (io_info.options) {
                    # convert options to key -> value format
                    io_info.options = map {$1.key: $1.value.value}, io_info.options.pairIterator();
                    # do template substitution; ignore invalid context errors
                    try {
                        io_info.options = UserApi::expandTemplatedValue(io_info.options);
                    } catch (hash<ExceptionInfo> ex) {
                        if (ex.err == "UNSUPPORTED-CONTEXT-ERROR") {
                            dynamic = True;
                        } else {
                            rethrow;
                        }
                    }
                }
                setProviderFromFactory(io, io_info.name + io_info.path, io_info.options, dynamic);
                break;
            }

            default:
                error("invalid mapper hash %y option; type %y unknown (%y)", io, io_info.type, io_info);
        }
    }

    private:internal setType(string io, string type_path, *hash<auto> custom_fields) {
        AbstractDataProviderType type;
        try {
            type = UserApi::getQorusType(type_path);
        } catch (hash<ExceptionInfo> ex) {
            error("%s: %s", ex.err, ex.desc);
        }
        if (io == "output") {
            type = type.getSoftType();
        }
        *hash<string, AbstractDataField> fields = custom_fields
            ? QorusDataProviderTypeHelper::addCustomFields(type, custom_fields).getFields()
            : type.getFields();
        if (!fields) {
            # allow an empty hash for the input type
            if (io == "input" && (type.isAssignableFrom(HashType) || type.isAssignableFrom(ListType))) {
                fields = {};
            } else {
                error("invalid %y type %y; type has no fields", io, type_path);
            }
        }
        serverOptions{io} = fields;
    }

    private:internal setProviderFromConnection(string pfx, string connection_name, object connserver, *hash<auto> io_info) {
        AbstractDataProvider provider = setProvider(pfx, connection_name, connserver);
        switch (io_info.subtype) {
            case "request":
                setFields(pfx, connection_name, io_info.subtype, provider.getRequestType());
                break;

            case "response":
                setFields(pfx, connection_name, io_info.subtype, provider.getResponseType());
                break;

            case "error":
                if (!io_info.error) {
                    error("%s connection %y error response missing \"error\" key: %y", pfx, connection_name, io_info);
                }
                setFields(pfx, connection_name, io_info.subtype + " (error " + io_info.error + ")",
                    provider.getErrorResponseType(io_info.error));
                serverOptions.input_response_error = io_info.error;
                break;

            case "record":
            case NOTHING:
                serverOptions{pfx} = pfx == "output" ? provider.getSoftRecordType() : provider.getRecordType();
                break;

            default:
                error("%s connection %y references invalid subtype %y", pfx, connection_name, io_info.subtype);
        }
    }

    private:internal setFields(string pfx, string connection_name, string subtype, AbstractDataProviderType type) {
        if (pfx == "output") {
            type = type.getSoftType();
        }
        *hash<string, AbstractDataField> fields = type.getFields();
        if (!fields) {
            error("%s connection %y references %s message of type %y which cannot be mapped", pfx, connection_name,
                subtype, type.getName());
        }
        serverOptions{pfx} = fields;
    }

    private:internal AbstractDataProvider setProvider(string pfx, string connection_name, object connserver) {
        return serverOptions{pfx + "_provider"} = ServerMapperContainer::getProvider(connection_name, connserver, mapperid);
    }

    private:internal bool needRuntimeOptions(*hash<auto> opts) {
        foreach auto val in (opts.iterator()) {
            switch (val.typeCode()) {
                case NT_STRING:
                    if (val.regex(UserApi::BB_ONE_VARIABLE_RE)) {
                        return True;
                    }
                    break;
            }
        }
        return False;
    }

    private:internal *hash<auto> getRuntimeOptions(*hash<auto> opts, *hash<auto> local_context) {
        *hash<auto> rv;
        foreach hash<auto> i in (opts.pairIterator()) {
            switch (i.value.typeCode()) {
                case NT_STRING:
                    rv{i.key} = UserApi::expandTemplatedValue(i.value, local_context);
                    break;
                default:
                    rv{i.key} = i.value;
                    break;
            }
        }
        return rv;
    }

    private:internal *string getCodeString(string code_) {
        # {\"code\": auto sub(auto ctx, auto record) { return func(ctx, record); } }
        (*string result,) = code_ =~ x/[^:]+:(.+)(}|\)).*$/s;
        trim result;
        return result;
    }

    private:internal prepareFields() {
        int type;
        foreach string key in (keys fields) {
            type = fields{key}.typeCode();
            if (type == NT_HASH) {
                if (fields{key}.hasKey("code")) {
                    type = fields{key}{"code"}.typeCode();
                    if (type == NT_CALLREF || type == NT_CLOSURE) {
                        fields{key}{"code"} = getCodeString(field_source{key});
                    }
                } else if (!fields{key}) {
                    # if we have an empty hash, then a 1:1 mapping is implied
                    fields{key}.name = key;
                }
            } else if (type == NT_STRING) {
                fields{key} = {"name": fields{key}};
            } else if (type == NT_BOOLEAN) {
                fields{key} = {"name": key};
            } else if (type == NT_CALLREF || type == NT_CLOSURE) {
                remove fields{key};
                fields{key}{"code"} = getCodeString(field_source{key});
            }
        }
    }

    setError(string err) {
        self.err = err;
    }

    Mapper create(*hash<auto> rtopts, *hash<auto> local_context) {
        needsInit();
        hash<auto> opts = setupOptionContext(local_context);
        return mtype.get(serverFields, opts + rtopts);
    }

    AbstractIterator createIterator(AbstractIterator i, *hash<auto> rtopts, *hash<auto> local_context) {
        needsInit();
        hash<auto> opts = setupOptionContext(local_context);
        return mtype.getIterator(i, serverFields, opts + rtopts);
    }

    private hash<auto> setupOptionContext(*hash<auto> local_context) {
        hash<auto> opts = serverOptions - ("mapper-input", "mapper-output");
        if (input_factory) {
            hash<auto> options = input_provider_create_options;
            if (input_provider_create_options_dynamic) {
                options = UserApi::expandTemplatedValue(options);
            }
            opts.input_provider = input_factory.create(getRuntimeOptions(options, local_context));
            map opts.input_provider = opts.input_provider.getChildProviderEx($1), input_provider_path;
        }
        if (output_factory) {
            hash<auto> options = output_provider_create_options;
            if (output_provider_create_options_dynamic) {
                options = UserApi::expandTemplatedValue(options);
            }
            opts.output_provider = output_factory.create(getRuntimeOptions(options, local_context));
            map opts.output_provider = serverOptions.output_provider.getChildProviderEx($1), output_provider_path;
        }
        if (opts.input_provider) {
            remove opts.input;
        }
        if (opts.output_provider) {
            remove opts.output;
        }
        if (serverOptions."mapper-input".is_api_call) {
            opts.input_suppress_data_provider = True;
        }
        if (serverOptions."mapper-output".is_api_call) {
            opts.output_suppress_data_provider = True;
        }

        # setup mapper_handler_context for fields with qore-expressions
        map (opts.mapper_handler_context.qore_exp_map{$1.key} =
                new Expression(p, $1.value."qore-expression", "qore expression for output field \"" + $1.key + "\"")),
            serverFields.pairIterator(),
            exists $1.value."qore-expression";

        # setup mapper thread context option
        opts.mapper_thread_context = {
            "pgm": p,
        };

        return opts;
    }

    hash<auto> getInfo(*bool full) {
        checkInit();
        hash<auto> rv = MapperContainerBase::getInfo(full) + {
            "options": serverOptions - ("input_log", "output_log", "input", "output"),
            "valid": !exists err,
        };
        # remove closures / call refs from runtime_keys
        map rv.options.runtime_keys{$1} -= "handler", keys rv.options.runtime_keys;

        #QDBG_LOG("INFO mapper %y INPUT: %N", name, serverOptions.input);
        # get option info and remove objects
        if (serverOptions.input && (serverOptions.input.firstValue() instanceof AbstractDataField)) {
            rv.options.input = map {
                $1.key: $1.value.getInputInfo(),
            }, serverOptions.input.pairIterator();
        }
        if (serverOptions.output && (serverOptions.output.firstValue() instanceof AbstractDataField)) {
            rv.options.output = map {
                $1.key: $1.value.getInfo(),
            }, serverOptions.output.pairIterator();
        }

        if (serverOptions.input_provider) {
            try {
                rv.options.input_provider = serverOptions.input_provider.getInfoAsData(full);
            } catch (hash<ExceptionInfo> ex) {
                olog(LoggerLevel::ERROR, "MAPPER-ERROR: invalid input provider: %s", getErrorMsg("%s: %s: %s",
                    get_ex_pos(ex), ex.err, ex.desc));
            }
        }
        if (serverOptions.output_provider) {
            try {
                rv.options.output_provider = serverOptions.output_provider.getInfoAsData(full);
            } catch (hash<ExceptionInfo> ex) {
                olog(LoggerLevel::ERROR, "MAPPER-ERROR: invalid output provider: %s", getErrorMsg("%s: %s: %s",
                    get_ex_pos(ex), ex.err, ex.desc));
            }
        }

        if (err) {
            rv.error = err;
        }

        # issue #3519: remove closures / call refs from options
        rv.options = map {$1.key: $1.value}, rv.options.pairIterator(), !$1.value.callp();

        #QDBG_LOG("INFO mapper %y rv: %N", name, rv);
        return rv;
    }

    string getErrorMsg(string fmt) {
        return sprintf("mapper %s v%s%s (%d): %s", name, version, patch, mapperid, vsprintf(fmt, argv));
    }

    error(string fmt) {
        string errstr = sprintf("mapper %s v%s%s (%d): %s", name, version, patch, mapperid, vsprintf(fmt, argv));
        olog(LoggerLevel::ERROR, "MAPPER-ERROR: %s", errstr);
        if (!err)
            err = errstr;
        if (no_exception) {
            olog(LoggerLevel::INFO, "%s", errstr);
        } else {
            throw "MAPPER-ERROR", errstr;
        }
    }

    bool valid() {
        return err ? False : True;
    }

    private needsInit() {
        checkInit();
        if (err) {
            throw "INVALID-MAPPER", err;
        }
    }

    private synchronized checkInit() {
        if (!init && !err) {
            try {
                initIntern();
            } catch (hash<ExceptionInfo> ex) {
                err = sprintf("mapper %y v%s (%d) of type %y could not be initialized: ", name, version, mapperid, mtype.getName());
                if (Qorus.getDebugSystem()) {
                    err += get_exception_string(ex);
                } else {
                    err += sprintf("%s: %s", ex.err, ex.desc);
                }
            }
        }
    }

    private initIntern() {
        QDBG_ASSERT(!err);
        QDBG_ASSERT(!init);
        # set initialization flag
        init = True;

        olog(LoggerLevel::INFO, "initializing mapper %y v%s (%d) of type %y", name, version, mapperid, mtype.getName());

        serverOptions.input = mtype.getInput(name, serverOptions);
        #QDBG_LOG("DBG: mapper %y input: %y", tname, serverOptions.input);
        serverOptions.output = mtype.getOutput(name, serverOptions);

        # output field order hash
        hash<string, int> ooh;

        # sort input and output options by used fields
        if (serverOptions.output && serverFields) {
            # issue #2159 sort using the input field name with complex mappings
            # build a hash of the count of input mappings per output key
            code get_input_field = string sub (hash h) {
                switch (h.value.typeCode()) {
                    case NT_HASH: {
                        if (exists h.value.name) {
                            return (h.value.name =~ x/^([^\.]+)/)[0] ?? "";
                        }
                        return exists h.value.struct && h.value.struct.typeCode() == NT_LIST
                            ? h.value.struct[0]
                            : h.key;
                    }
                    case NT_STRING: {
                        # issue #2159: we must cover the case when the mapping is missing or invalid
                        return (h.value =~ x/^([^\.]+)/)[0] ?? "";
                    }
                }
                return h.key;
            };
            # first hash<string, int>, then hash<string, string>
            hash<auto> ich;
            map ++ich{get_input_field($1)}, serverFields.pairIterator();

            # transform numbers to strings of a unified length for sorting
            {
                # get format mask
                string fmt = sprintf("%%0%dd", ceil(log10(serverFields.size() + 1), 0));
                ich = map {$1.key: sprintf(fmt, $1.value)}, ich.pairIterator();
            }

            # build a hash of used output fields
            code get_mapping = string sub(hash<auto> h) {
                # issue #2159: sort based on number of input mappings if possible
                *string pfx = ich{get_input_field(h)};
                switch (h.value.typeCode()) {
                    case NT_HASH:
                        return (exists h.value.name
                                || exists h.value.struct
                                || serverOptions.input.hasKey(h.key))
                            ? pfx + h.key
                            : SortLast;
                    case NT_STRING: {
                        *string val = (h.value =~ x/^([^\.]+)/)[0];
                        #return exists val && serverOptions.input.hasKey(val) ? val : SortLast;
                        return exists val && serverOptions.input.hasKey(val) ? pfx + h.key : SortLast;
                    }
                    default:
                        return serverOptions.input.hasKey(h.key) ? pfx + h.key : SortLast;
                }
            };
            hash<auto> h = map {$1.key: get_mapping($1)}, serverFields.pairIterator();
            serverOptions.output = sortKeys(serverOptions.output, h);

            ooh = map {$1: $# + 1}, keys serverOptions.output;
        }
        if (serverOptions.input) {
            # make a hash of input fields order values
            hash<auto> h;

            # only set the sort value for the key if not already set or if the new value is lower
            code setter = sub(reference<*int> lv, *int nv) {
                if (!exists lv || lv > nv)
                    lv = nv;
            };
            # build a hash of used input fields
            foreach hash<auto> mh in (serverFields.pairIterator()) {
                auto val = mh.value;
                switch (val.typeCode()) {
                    case NT_HASH: {
                        if (exists val.name) {
                            # issue #2159 sort using the input field name with complex mappings
                            *string kval = (val.name =~ x/^([^\.]+)/)[0];
                            if (kval.val())
                                setter(\h{kval}, ooh{mh.key});
                            break;
                        } else if (exists val.struct && val.struct.typeCode() == NT_LIST) {
                            setter(\h{val.struct[0]}, ooh{mh.key});
                            break;
                        } else if (serverOptions.input.hasKey(mh.key)) {
                            setter(\h{mh.key}, ooh{mh.key});
                        }
                        break;
                    }
                    case NT_STRING: {
                        # issue #2159 sort using the input field name with complex mappings
                        *string kval = (val =~ x/^([^\.]+)/)[0];
                        if (kval.val() && serverOptions.input.hasKey(kval)) {
                            setter(\h{kval}, ooh{mh.key});
                        }
                        break;
                    }
                    default: {
                        if (serverOptions.input.hasKey(mh.key)) {
                            setter(\h{mh.key}, ooh{mh.key});
                        }
                        break;
                    }
                    break;
                }
            }

            if (h) {
                serverOptions.input = sortKeys(serverOptions.input, h);
            }
        }
    }

    private hash<auto> sortKeys(hash<auto> h, hash<auto> kh) {
        code comparekeys = int sub (string l, string r) {
            if (kh{l}) {
                return kh{r} ? kh{l} <=> kh{r} : -1;
            }
            return kh{r} ? 1 : l <=> r;
        };

        return h{sort(h.keys(), comparekeys)};
    }

    private loadLibraryImpl(MapperProgram p) {
        *hash<auto> lib = Qorus.qmm.lookupMapper(mapperid).lib;
        if (!lib)
            return;

        qorus_load_library(lib, p, sub (string msg) {olog(LoggerLevel::INFO, "Mapper %y: " + msg, name);});
    }
}
