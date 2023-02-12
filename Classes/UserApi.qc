# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file UserApi.qc methods common to workflow, service, and job APIs

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types

public namespace OMQ {
    public namespace UserApi {
        hashdecl BbVariable {
            string contxt;
            string name;
            *bool brackets;
        }

        # private hashdecl for dot and array resolution
        hashdecl DotInfo {
            # the key to read
            string key;
            # if it has a value, then take the array offset
            *softint array_offset;
        }

        string sub _priv_get_expr_arg(string var_name, *hash<auto> local_context, bool expand_complex_values) {
            try {
                auto val = UserApi::expandTemplatedValue(var_name, local_context, expand_complex_values);
                if (val.typeCode() != NT_STRING) {
                    val = _priv_get_string_value(val);
                }
                return val;
            } catch (hash<ExceptionInfo> ex) {
                throw "EXPRESSION-ARG-ERROR", sprintf("expression %y: %s: %s", var_name, ex.err, ex.desc), ex.arg;
            }
        }

        list<hash<DotInfo>> sub _priv_get_dot_string_list(string str) {
            list<hash<DotInfo>> rv();
            # break down string into a list of fields
            list<string> dot_list = str.split(".");
            # allow "." characters to be escaped - if found then recombine fields
            # do not check the last field
            for (int i = 0; i < dot_list.size(); ++i) {
                # check if a single backslash is at the end of the string
                if ((i < (dot_list.size() - 1)) && (dot_list[i] =~ /\\$/)) {
                    splice dot_list[i], -1;
                    dot_list[i] += "." + (extract dot_list, i + 1, 1)[0];
                    --i;
                } else {
                    *string array_offset = (dot_list[i] =~ x/[^\\]?\[(-?[0-9]+)\]$/)[0];
                    if (exists array_offset) {
                        # remove array index from string
                        dot_list[i] =~ s/\[-?[0-9]+\]$//;
                    }
                    rv += <DotInfo>{
                        "key": dot_list[i],
                        "array_offset": exists array_offset ? array_offset : NOTHING,
                    };
                }
            }

            return rv;
        }

        bool sub _priv_needs_template_expansion(string arg) {
            return arg =~ /[^\\]\$[\w-]:/;
        }

        bool sub _priv_needs_template_expansion(auto arg) {
            return False;
        }

        # template tokens
        const TT_String = 1;
        const TT_Template = 2;

        hashdecl TemplateTokenInfo {
            # token type
            int type;
            # string or template value
            string val;
            # template argument
            string arg;
            # alternate (??) expression
            string alt;
        }

        softlist<hash<TemplateTokenInfo>> sub _priv_tokenize_template(string arg) {
            list<hash<TemplateTokenInfo>> tokens();

            #printf("DBG TOKENIZE %y (%d)\n", arg, arg.length());

            int len = arg.length();
            # issue #3466: an empty string needs to have a single token
            if (!arg.val()) {
                return <TemplateTokenInfo>{
                    "type": TT_String,
                    "val": "",
                };
            }
            string str;
            # last character was an escape char
            bool escape;

            for (int i = 0; i < len; ++i) {
                string c = arg[i];

                if (c == "$") {
                    *string template = (arg[(i + 1)..] =~ x/^([\w-]+):/)[0];
                    if (template) {
                        if (escape) {
                            escape = False;
                            QDBG_ASSERT(str[str.size() - 1] == "\\");
                            # remove escape char
                            splice str, -1;
                            str += "$" + template + ":";
                            i += template.length() + 1;
                            continue;
                        }
                        if (str) {
                            tokens += <TemplateTokenInfo>{
                                "type": TT_String,
                                "val": str,
                            };
                            str = "";
                        }
                        int arg_char_len;
                        string raw_arg = arg[(i + template.length() + 2)..];
                        *string token_arg = _priv_get_template_arg(template, raw_arg, \arg_char_len);
                        if (!token_arg.val()) {
                            # otherwise throw an exception
                            throw "FORMAT-ERROR", sprintf("template %y is not followed by a value (%s%s); "
                                "use %s:{...} if the template value requires characters other than [a-zA-Z0-9_.]",
                                template, raw_arg[0..20], raw_arg.length() > 20 ? "..." : "", template);
                        }
                        hash<TemplateTokenInfo> token({
                            "type": TT_Template,
                            "val": template,
                            "arg": token_arg,
                        });
                        # add 1 for the ":" char
                        i += arg_char_len + template.length() + 1;
                        while (*list<string> alt_list = (arg[(i + 1)..] =~ x/^\?\?(({((?:(?> [^{}]+ )|(?2))*)}))/x)) {
                            token.alt = alt_list[2] + alt_list[3];
                            i += token.alt.length() + 4;
                        }
                        tokens += token;
                        #printf("DBG GOT TOKEN: %y next: %y\n", token, arg[(i+1)..]);
                        continue;
                    }
                }

                if (c == "\\") {
                    escape = !escape;
                    if (!escape) {
                        continue;
                    }
                } else if (escape) {
                    escape = False;
                }

                str += c;
            }

            if (str.val()) {
                tokens += <TemplateTokenInfo>{
                    "type": TT_String,
                    "val": str,
                };
            }

            return tokens;
        }

        *string sub _priv_get_template_arg(string template, string arg, reference<int> arg_char_len) {
            if (arg[0] == "{") {
                return _priv_get_template_bracket_arg(template, arg, \arg_char_len);
            }

            *string rv = (arg =~ x/^(\*|\w+[\w\.]*)/)[0];
            if (rv) {
                arg_char_len = rv.length();
            }
            return rv;
        }

        *string sub _priv_get_template_bracket_arg(string template, string arg, reference<int> arg_char_len) {
            int len = arg.length();
            string rv = "";
            int bracket_count = 1;
            int i = 1;
            for (; i < len; ++i) {
                string c = arg[i];
                if (c == "\\") {
                    *string next = arg[i + 1];
                    if (next == "{" || next == "}" || next == "\\") {
                        rv += next;
                        ++arg_char_len;
                        ++i;
                        continue;
                    }
                }
                if (c == "{") {
                    ++bracket_count;
                } else if (c == "}" && !(--bracket_count)) {
                    break;
                }
                rv += c;
            }
            if (i == len) {
                throw "FORMAT-ERROR", sprintf("template %y brackets not balanced in argument: %y", template, arg);
            }

            arg_char_len += (rv.length() + 2);
            #printf("DBG returning %y (%y l: %y)\n", rv, template, arg_char_len);
            return rv;
        }

        # resolves the list reference and returns the value
        /* @param var_data the list source
            @param exp the offset expression; respects dot notation

            @return the value referenced or @ref nothing if not present

            @throw LIST-VALUE-ERROR cannot parse list value expression

            @since Qorus 4.0.3
        */
        auto sub _priv_get_list_arg_value(list<auto> var_data, string exp) {
            if (exp =~ /^\[-?[0-9]+\]/) {
                return _priv_get_complex_value(var_data, UserApi::_priv_get_dot_string_list(exp));
            }
            throw "LIST-VALUE-ERROR", sprintf("cannot dereference list with expression %y; expecting a number in "
                "square brackets giving the list offset as the initial part of the expression", exp);
        }

        # get complex value
        /* @param var_data can be a list or a string
            @param dot_info_list a list of dot or array offsets
            @param missing_input an optional reference that returns True if the input key was missing in case of a
            @ref nothing return value
            @param expanded_list returns True if the result has been expanded from a list
        */
        auto sub _priv_get_complex_value(*auto var_data, list<hash<DotInfo>> dot_info_list,
                *reference<bool> missing_input, *reference<bool> expanded_list) {
            auto v = var_data;
            foreach hash<DotInfo> info in (dot_info_list) {
                if (info.key.val()) {
                    # issue #3829: remove quotes and substitute escaped hashes
                    if ((info.key =~ /^'.*'$/) || (info.key =~ /^".*"$/)) {
                        splice info.key, 0, 1;
                        splice info.key, -1;
                    } if (info.key =~ /\\ /) {
                        info.key =~ s/\\ / /g;
                    }
                    v = v{info.key};
                    if (!exists v) {
                        missing_input = !v.hasKey{info.key};
                        return;
                    }
                }
                if (exists info.array_offset) {
                    if (v.typeCode() != NT_LIST) {
                        return;
                    }
                    v = info.array_offset < 0
                        ? v[v.lsize() + info.array_offset]
                        : v[info.array_offset];
                } else if (v.lsize() > 1 && (v[0].typeCode() == NT_HASH) && $# < (dot_info_list.size() - 1)) {
                    list<hash<DotInfo>> arg = dot_info_list[($# + 1)..];
                    list<auto> rv = ();
                    # resolve the result and ensure that each list element reflects the final value, even in case
                    # of intermediate lists
                    foreach auto val in (v) {
                        bool local_expanded_list;
                        auto result = _priv_get_complex_value(val, arg, \missing_input, \local_expanded_list);
                        if (local_expanded_list) {
                            rv += result;
                        } else {
                            push rv, result;
                        }
                    }
                    expanded_list = True;
                    return rv;
                }
            }
            return v;
        }

        *hash<auto> sub _priv_update_hash_dot_value(*hash<auto> var_data, list<hash<DotInfo>> dot_list, auto value) {
            # recursively update the hash
            code update = sub (reference<auto> ref, list<hash<DotInfo>> dot_list, auto value, int element = 0) {
                if (element == dot_list.size() - 1) {
                    if (exists dot_list[element].array_offset) {
                        ref{dot_list[element].key} = value[dot_list[element].array_offset];
                    } else {
                        ref{dot_list[element].key} = value;
                    }
                } else {
                    if (exists dot_list[element].array_offset) {
                        update(\ref{dot_list[element].key}[dot_list[element].array_offset], dot_list, value, element + 1);
                    } else {
                        update(\ref{dot_list[element].key}, dot_list, value, element + 1);
                    }
                }
            };
            update(\var_data, dot_list, value);
            return var_data;
        }

        # Returns the interface program object or @ref nothing
        *QorusProgram sub _priv_try_get_interface_pgm() {
            # issue #3537: must deserialize in the context of the target program, if any
            *QorusProgram pgm = Mapper::getMapperThreadContext().pgm;
            if (pgm) {
                return pgm;
            }
%ifdef QorusClusterServer
            {
                *CommonInterfaceBase ix = Qorus.tryGetInterface();
                if (ix) {
                    return ix.getProgram();
                }
            }
%endif
            {
                *object ix = tld ? tld.getInterface() : NOTHING;
                if (ix && ix instanceof CommonInterfaceBase) {
                    return cast<*CommonInterfaceBase>(ix).getProgram();
                }
            }
        }

        auto sub _priv_deserialize_with_interface_pgm(*data d) {
            if (!exists d) {
                return;
            }
%ifdef QorusHasIxApis
            if (*QorusProgram pgm = _priv_try_get_interface_pgm()) {
                return pgm.callFunction("_qorus_deserialize", d);
            }
%endif
%ifdef QorusServer
            return qorus_cluster_deserialize(d);
%endif
        }

        *CommonInterfaceBase sub _priv_try_get_interface_object() {
            *CommonInterfaceBase ix = tld ? cast<*CommonInterfaceBase>(tld.getInterface()) : NOTHING;
            if (ix) {
                return ix;
            }
%ifdef QorusClusterServer
            # this *must* appear after the above, because the Qorus.getInterface() call will deadlock in interface
            # programs if called during startup
            return Qorus.getInterface();
%endif
        }

        CommonInterfaceBase sub _priv_get_interface_object() {
            *CommonInterfaceBase ix = _priv_try_get_interface_object();
            if (ix) {
                return ix;
            }
            throw "NO-INTERFACE", "no interface is available in this context";
        }

        *QorusProgram sub _priv_try_get_pgm_ctx() {
%ifdef QorusServer
            if (*QorusProgram pgm = Mapper::getMapperThreadContext().pgm) {
                return pgm;
            }
            if (*CommonInterfaceBase ix = _priv_try_get_interface_object()) {
                return ix.getProgram();
            }
%endif

%ifdef QorusClientInjectedTest
            return ::_priv_get_pgm_ctx();
%endif
        }

        QorusProgram sub _priv_get_pgm_ctx() {
            *QorusProgram pgm = _priv_try_get_pgm_ctx();
            if (pgm) {
                return pgm;
            }
            throw "NO-INTERFACE", "no interface is available in this context";
        }

        auto sub _priv_call_rest_api(string method, string path, *hash<auto> body_args) {
%ifdef QorusCore
            # TLD must be created for remote calls from external interface programs
            ensure_create_tld();

            # setup path
            if (path !~ /^(latest|v[0-9]+\/)/) {
                # remove any leading slash
                path =~ s/^\///;
                path = "/latest/" + path;
            }

            # saves and restores tld on exit
            QorusApiContextHelper tch();

            # setup call context
            tld.cx = {"user": "%SYS%", "ssl": True, "internal": True};
            return Qorus.callRestHandlerMethod("handleExternalRequest", method, path, body_args, tld.cx);
%endif

%ifdef QorusClusterServer
            return Qorus.callCoreStaticMethodTld(Qorus.getTldContext(), "UserApi", "callRestApi", method, path,
                body_args);
%endif

%ifdef QorusClient
            return qrest.restDo(method, path, body_args);
%endif
        }

        object sub _priv_get_connection_provider(string typename) {
%ifdef QorusServer
            switch (typename) {
                case "connection": return Qorus.connections;
                case "datasource": return Qorus.dsmanager;
                case "remote": return Qorus.remotemonitor;
            }
%else
            return omqclient.getConnectionProvider(typename);
%endif
        }

        AbstractDataProvider sub _priv_get_data_provider_from_path(string path, reference<list<string>> path_list,
                string typename, string err_code) {
            # get type from connection
            string connection_name;
            if (!path_list || !(connection_name = shift path_list)) {
                throw err_code, sprintf("data type path %y does not have a %s name", path, typename);
            }
            if (typename == "factory") {
                connection_name += "/" + (foldl $1 + "/" + $2, path_list);
                path_list = ();
                return DataProvider::getFactoryObjectFromString(connection_name);
            }
            return _priv_get_connection_provider(typename).getDataProvider(connection_name);
        }

        # returns a string that represents a valid Qore expression for the given type
        string sub _priv_get_qore_string_value(auto v) {
            switch (v.typeCode()) {
                case NT_STRING:
                    return sprintf("%y", v);

                case NT_DATE:
                    # return in ISO-8601 format for both absolute and relative dates
                    return v.format("IF");

                case NT_BOOLEAN:
                    return v ? "True" : "False";

                case NT_BINARY:
                    return "<" + v.toHex() + ">";

                case NT_INT:
                    return v.toString();

                case NT_FLOAT: {
                    string rv = v.toString();
                    if (rv !~ /\./) {
                        rv += ".0";
                    }
                    return rv;
                }

                case NT_NUMBER:
                    return v.toString() + "n";

                case NT_NOTHING:
                    return "NOTHING";

                case NT_NULL:
                    return "NULL";

                case NT_HASH: {
                    return "{"
                        + (foldl $1 + ", " + $2,
                            (map sprintf("%y: %s", $1.key, _priv_get_qore_string_value($1.value)), v.pairIterator()))
                        + "}";
                }

                case NT_LIST: {
                    return "(" + (foldl $1 + ", " + $2, (map _priv_get_qore_string_value($1), v)) + ")";
                }
            }

            throw "VALUE-ERROR", sprintf("cannot convert %y value (%y) to a string for use in a Qore expression",
                v.type(), v);
        }

        string sub _priv_get_string_value(auto v) {
            # convert to a string
            switch (v.typeCode()) {
                case NT_DATE:
                    # return in ISO-8601 format for both absolute and relative dates
                    return v.format("IF");

                case NT_BOOLEAN:
                    return v ? "True" : "False";

                case NT_BINARY:
                    return "<" + v.toHex() + ">";

                case NT_INT:
                case NT_FLOAT:
                case NT_NUMBER:
                case NT_NOTHING:
                case NT_NULL:
                    return v.toString();
            }

            throw "VALUE-ERROR", sprintf("cannot concatenate %y value (%y) to another value as a string in template "
                "resolution", v.type(), v);
        }

        *hash<auto> sub _priv_parse_ui_hash(*hash<auto> h, *bool ui, *hash<auto> local_context) {
            *hash<auto> rv;
            h = UserApi::expandTemplatedValue(h, local_context);
            if (ui) {
                foreach hash<auto> i in (h.pairIterator()) {
                    if (i.value.value.typeCode() == NT_STRING && i.value.type != "string" && i.value.value !~ /^\$/) {
                        on_error rethrow $1.err, sprintf("%s (while processing element %y of UI hash", $1.desc, i);
                        rv{i.key} = parse_yaml(i.value.value);
                    } else {
                        rv{i.key} = i.value.value;
                    }
                    #QDBG_LOG("_priv_parse_ui_hash() %y = %y -> %y", i.key, i.value, rv{i.key});
                }
            } else {
                rv = h;
            }
            return rv;
        }

        *hash<auto> sub _priv_get_provider_constructor_options(string factory, *hash<auto> opts,
                *hash<string, hash<DataProviderOptionInfo>> constructor_opts, *hash<auto> local_context) {
            hash<auto> rv;
            foreach hash<auto> i in (constructor_opts.pairIterator()) {
                auto val = opts{i.key};
                if (!exists val) {
                    continue;
                }
                # FIXME: eliminate this when the IDE has been updated to always send key = value format
                if (val.typeCode() == NT_HASH && val.size() == 2 && val.hasKey("type") && val.hasKey("value")) {
                    if (val.value.typeCode() == NT_STRING && val.type != "string" && val.value !~ /^\$/) {
                        rv{i.key} = _priv_try_parse_yaml_option(factory, i.key, val.value);
                    } else {
                        rv{i.key} = val.value;
                    }
                } else {
                    # first see if any of the expected types match
                    bool is_string = val.typeCode() == NT_STRING;
                    string typename = val.type();
                    bool ok;
                    foreach AbstractDataProviderType type in (i.value.type) {
                        hash<string, bool> ah = type.getAcceptTypeHash();
                        if (ah{typename}) {
                            rv{i.key} = val;
                            ok = True;
                            break;
                        }
                    }
                    if (!ok) {
                        # value is a string but the type requires a non-string; try to parse as yaml
                        if (is_string) {
                            rv{i.key} = _priv_try_parse_yaml_option(factory, i.key, val);
                        }
                    }
                }
                rv{i.key} = UserApi::expandTemplatedValue(rv{i.key}, local_context);
                if (!exists rv{i.key}) {
                    remove rv{i.key};
                }
            }
            return rv;
        }

        auto sub _priv_try_parse_yaml_option(string factory, string key, string yaml) {
            try {
                return parse_yaml(yaml);
            } catch (hash<ExceptionInfo> ex) {
                rethrow "API-FACTORY-ERROR", sprintf("data provider factory %y constructor option %y given "
                    "invalid YAML value %y: %s: %s", factory, key, yaml, ex.err, ex.desc);
            }
        }

%ifdef QorusServer
        const DataProviderSearchTypes = {
            "search-single": True,
            "search": True,
        };

        const DataProviderUpdateDeleteTypes = {
            "update": True,
            "delete": True,
        };

        const DataProviderActionTypes = DataProviderSearchTypes + DataProviderUpdateDeleteTypes + {
            "create": True,
        };

        const RecordsAffectedDataType = new QorusApiRecordsAffectedDataType();

        # Data type the indicates the number of records affected by an operation
        class QorusApiRecordsAffectedDataType inherits HashDataType {
            public {
                #! Field descriptions
                const Fields = {
                    "records_affected": {
                        "type": IntType,
                        "desc": "Returns the number of records affected by the operation",
                    },
                };
            }

            #! Creates the object
            constructor() {
                map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
                    Fields.pairIterator();
            }
        }

        string sub _priv_get_subtype(AbstractDataProvider prov, hash<auto> type_hash, string key, *bool reverse) {
            if (prov.hasRecord() || DataProviderActionTypes{type_hash.typeAction}) {
                return "record";
            }
            if (prov.supportsObservable()) {
                return "event";
            }
            if (reverse) {
                return key == "base_type" ? "response" : "request";
            }
            return key == "base_type" ? "request" : "response";
        }

        *AbstractDataProviderType sub _priv_get_type_from_provider_intern(hash<auto> type_hash, AbstractDataProvider prov) {
            switch (type_hash.subtype) {
                case "request":
                    return prov.getRequestType();

                case "response":
                    return prov.getResponseType();

                case "error":
                    if (type_hash.error.typeCode() != NT_STRING) {
                        throw "INVALID-ARGUMENT", sprintf("missing or invalid \"error\" key in type hash: %y", type_hash);
                    }
                    return prov.getErrorResponseType(type_hash.error);

                case "event":
                    if (type_hash.event.typeCode() != NT_STRING) {
                        throw "INVALID-ARGUMENT", sprintf("missing or invalid \"event\" key in type hash: %y", type_hash);
                    }
                    return prov.getEventInfo(type_hash.event).type;

                case "message":
                    if (type_hash.event.typeCode() != NT_STRING) {
                        throw "INVALID-ARGUMENT", sprintf("missing or invalid \"message\" key in type hash: %y", type_hash);
                    }
                    return prov.getMessageInfo(type_hash.message).type;

                case "record":
                case NOTHING:
                    return _priv_get_type_from_record_type(prov.getRecordType());
            }
            throw "INVALID-ARGUMENT", sprintf("missing or invalid subtype in type hash: %y", type_hash);
        }

        AbstractDataProviderType sub _priv_get_type_from_provider(hash<auto> type_hash, AbstractDataProvider prov) {
            *AbstractDataProviderType type = _priv_get_type_from_provider_intern(type_hash, prov);
            if (!type) {
                string desc = sprintf("DataProvider %y has no %s type", prov.getName(), type_hash.subtype);
                switch (type_hash.subtype) {
                    case "error":
                        desc += sprintf(" %y", type_hash.error);
                        break;

                    case "event":
                        desc += sprintf(" %y", type_hash.event);
                        break;

                    case "message":
                        desc += sprintf(" %y", type_hash.message);
                        break;
                }
                throw "INVALID-ARGUMENT", desc;
            }
            return type;
        }

        AbstractDataProviderType sub _priv_get_type_from_record_type(*hash<string, AbstractDataField> fields) {
            HashDataType hdt();
            map hdt.addField($1), fields.iterator();
            return hdt;
        }

        AbstractDataProviderType sub _priv_get_type_from_hash(hash<auto> type_hash, string key, *bool reverse) {
            if (key == "type" && DataProviderUpdateDeleteTypes{type_hash.typeAction}) {
                return RecordsAffectedDataType;
            }
            string path = type_hash.name;
            if (exists type_hash.path) {
                if (type_hash.path.typeCode() != NT_STRING) {
                    throw "INVALID-ARGUMENT", sprintf("expecting type \"string\" from argument \"path\"; got type %y "
                        "instead (%y)", type_hash.path.type(), type_hash.path);
                }
                if (type_hash.path && type_hash.path !~ /^\//) {
                    type_hash.path = "/" + type_hash.path;
                }
                path += type_hash.path;
            }
            if (reverse && type_hash.subtype) {
                if (type_hash.subtype == "request") {
                    type_hash.subtype = "response";
                } else if (type_hash.subtype == "response") {
                    type_hash.subtype = "request";
                }
            }

            switch (type_hash.type) {
                case "connection": {
                    AbstractDataProvider prov = ServerMapperContainer::getProvider(path, Qorus.connections);
                    if (!type_hash.subtype) {
                        type_hash.subtype = _priv_get_subtype(prov, type_hash, key, reverse);
                    }
                    return _priv_get_type_from_provider(type_hash, prov);
                }

                case "datasource":
                    return _priv_get_type_from_provider(type_hash,
                        ServerMapperContainer::getProvider(path, Qorus.dsmanager));

                case "remote": {
                    AbstractDataProvider prov = ServerMapperContainer::getProvider(path, Qorus.remotemonitor);
                    if (!type_hash.subtype) {
                        type_hash.subtype = _priv_get_subtype(prov, type_hash, key, reverse);
                    }
                    return _priv_get_type_from_provider(type_hash, prov);
                }

                case "type": {
                    AbstractDataProviderType type = UserApi::getQorusType(path);
                    return type_hash.custom_fields
                        ? QorusDataProviderTypeHelper::addCustomFields(type, type_hash.custom_fields)
                        : type;
                }

                case "factory": {
                    AbstractDataProviderFactory factory = DataProvider::getFactoryEx(type_hash.name);
                    AbstractDataProvider prov;
%ifdef QorusHasSvcApi
                    if (type_hash.hasApiContext) {
                        prov = QorusAbstractApiManager::getDataProvider(factory, type_hash.options);
                    } else
%endif
                    {
                        # verify option types
                        hash<DataProviderFactoryInfo> info = factory.getInfo();
                        type_hash.options = _priv_get_provider_constructor_options(type_hash.name,
                            type_hash.options, info.provider_info.constructor_options);
                        prov = factory.create(type_hash.options);
                    }
                    if (type_hash.path.val() && type_hash.path != "/") {
                        map prov = prov.getChildProviderEx($1), type_hash.path.split("/")[1..];
                    }
                    if (prov.hasRecord() || DataProviderActionTypes{type_hash.typeAction}) {
                        return _priv_get_type_from_record_type(prov.getRecordType());
                    }
                    if (!type_hash.subtype) {
                        type_hash.subtype = key == "base_type" ? "request" : "response";
                    }
                    if (reverse) {
                        if (type_hash.subtype == "request") {
                            type_hash.subtype = "response";
                        } else if (type_hash.subtype == "response") {
                            type_hash.subtype = "request";
                        }
                    }

                    *AbstractDataProviderType type = _priv_get_type_from_provider_intern(type_hash, prov);
                    if (type) {
                        return type;
                    }
                    return AbstractDataProviderType::get(AbstractDataProviderType::anyType);
                }
            }

            throw "INVALID-ARGUMENT", sprintf("type hash missing valid \"type\" entry (unrecognized value: %y)",
                type_hash.type);
        }
%endif

        const FileLocationOpts = ("encoding", "max_file_len");
        const ServiceResourceLocationOpts = ("encoding");
        const HttpClientLocationOpts = (
            "connect_timeout",
            "default_path",
            "default_port",
            "encoding",
            "encoding_passthru",
            "error_passthru",
            "http_version",
            "protocols",
            "proxy",
            "redirect_passthru",
            "ssl_cert_path",
            "ssl_key_path",
            "ssl_key_password",
            "ssl_verify_cert",
            "timeout",
        );
        const LocationSchemes = ("file", "resource");
    }
}

#! main common Qorus API class
/**
    @since Qorus 4.0
*/
public class OMQ::UserApi::UserApi {
    private {
        #! data provider root path values
        const DataProviderRootValues = {
            "connection": True,
            "datasource": True,
            "remote": True,
            "factory": True,
        };

        #! data type root path values
        const DataTypeRootValues = DataProviderRootValues + {
            "type": True,
        };

        #! data type path provider type values
        const DataProviderPathTypeValues = {
            "request": True,
            "response": True,
            "error": True,
            "record": True,
        };

%ifdef QorusServer
        #! Program for dynamic logic
        static QorusProgram DynamicLogic(False, CommonParseOptions | PO_NO_INHERIT_USER_CLASSES
            | PO_NO_INHERIT_USER_FUNC_VARIANTS | PO_NO_INHERIT_GLOBAL_VARS | PO_NO_INHERIT_USER_CONSTANTS
            | PO_NO_INHERIT_USER_HASHDECLS | PO_NEW_STYLE | PO_STRICT_ARGS | PO_REQUIRE_TYPES, QorusServerDefines);
%else
        static QorusProgram DynamicLogic;
%endif
    }

%ifdef QorusClient
    public {
        # any logging at or above this level will be output to the console in the client
        static int verbose = LoggerLevel::ERROR;
    }
%endif

    #! returns information about the given user service (if it's currently loaded)
    /** to get information about user services whether they are loaded or not, call:
        @code{.py}
        omqservice.system.omqmap.lookupserviceinfo("user", <name>)
        @endcode

        @param name the name of the user service to query
        @return a hash of user information or NOTHING if the service is not loaded; the hash will have the following structure:
        - \c type: \c "user"
        - \c name: the name of the service
        - \c version: version of the service
        - \c desc: description of the service
        - \c serviceid: service ID
        - \c status: @ref OMQ::SSRunning or @ref OMQ::SSLoaded
        - \c threads: number of running threads in the service
        - \c autostart: @ref True or @ref False if the autostart flag is set
        - \c loaded: date/time the service was loaded
        - \c methods: list of hashes for each method with \c name and \c desc keys

        @note This API is not available in the client library
    */
    static *hash<auto> getUserServiceInfo(string name) {
%ifdef QorusServer
        return services.getServiceInfo("user", name);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! get a cached table object (suitable for DML) if present, otherwise it creates one from scratch
    /** @par Example:
        @code{.py}
SqlUtil::AbstractTable t = UserApi::getSqlTable("my_datasource", "my_table");
        @endcode

        @param datasource a @ref dsconn "Qorus datasource" name
        @param table_name the name of the table to be acquired; the handling of this parameter is identical to that in
        @ref SqlUtil::Table::constructor(); names are converted to lower-case before performing the lookup and storage
        in the cache to ensure that the cache is based on case-insensitive lookups
        @param register_dependency if @ref True (the default) then if the connection is monitored as down, the
        calling interface will be temporarily disabled until the connection is up again

        @return an @ref SqlUtil::AbstractTable object corresponding to the parameters

        @throw INVALID-DATASOURCE this exception is thrown if the \a datasource argument cannot be matched to a known
        @ref dsconn "datasource"

        @note
        - other exceptions can be thrown when acquiring the table, for example if the given table is not accessible or
          if there are technical errors communicating with the database server, etc
        - you need to call clear_sql_table_cache() any time the table structure has changed

        @see
        - @ref sql-cache

        @since Qorus 4.0.3 added the \a register_dependency parameter
    **/
    static SqlUtil::AbstractTable getSqlTable(string datasource, string table_name, bool register_dependency = True) {
%ifdef QorusServer
        return Qorus.dsmanager.getSqlTable(datasource, table_name, register_dependency);
%endif

%ifdef QorusClient
        return get_sql_table(datasource, table_name);
%endif
    }

    #! get a cached table object (suitable for DML) if present, otherwise it creates one from scratch
    /** @param datasource a @ref Qore::SQL::DatasourcePool "DatasourcePool" object for a @ref dsconn "Qorus datasource"; note that if the @ref Qore::SQL::DatasourcePool object cannot be matched back to a known @ref dsconn "Qorus datasource", an \c INVALID-DATASOURCE exception will be thrown
        @param table_name the name of the table to be acquired; the handling of this parameter is identical to that in @ref SqlUtil::Table::constructor(); names are converted to lower-case before performing the lookup and storage in the cache to ensure that the cache is based on case-insensitive lookups
        @param register_dependency if @ref True (the default) then if the connection is monitored as down, the
        calling interface will be temporarily disabled until the connection is up again

        @return an @ref SqlUtil::AbstractTable object corresponding to the parameters

        @throw INVALID-DATASOURCE this exception is thrown if the \a datasource argument cannot be matched to a known @ref dsconn "Qorus datasource"

        @note
        - \c INVALID-DATASOURCE exceptions can be thrown with a valid Qorus datasource if the given @ref dsconn "datasource" has been reset since it was acquired
        - other exceptions can be thrown when acquiring the table, for example if the given table is not accessible or if there are technical errors communicating with the database server, etc
        - you need to call clear_sql_table_cache() any time the table structure has changed

        @par Example:
        @code{.py}
SqlUtil::AbstractTable t = UserApi::getSqlTable(datasource_pool, "my_table");
        @endcode

        @see
        - @ref sql-cache

        @since Qorus 4.0.3 added the \a register_dependency parameter
    **/
    static SqlUtil::AbstractTable getSqlTable(AbstractDatasource datasource, string table_name, bool register_dependency = True) {
%ifdef QorusServer
        return Qorus.dsmanager.getSqlTable(datasource, table_name);
%endif

%ifdef QorusClient
        return get_sql_table(datasource, table_name);
%endif
    }

    static SqlUtil::AbstractTable getSqlTable(object datasource, string table_name, bool register_dependency = True) {
%ifdef QorusServer
        return Qorus.dsmanager.getSqlTable(datasource, table_name, register_dependency);
%endif

%ifdef QorusClient
        return get_sql_table(datasource, table_name);
%endif
    }

    #! get information about cached object
    /** @return hash the whole sql cache

        Resulting hash (keys are @ref dsconn "datasource" names) of hashes (keys are cache types) of hashes (keys are names of individual cached objects) provides the information about given cached objects as a value. This information has the form of hash with the following keys:

        - count - how many times it was used
        - created - datetime of the first call (when the cache was created)
        - object - stored object that is cached

        @par Example:
        @code{.py}
hash cache = UserApi::getSqlCacheInfo();
hash cache_for_my_datasource = cache.my_datasource;
hash table_cache_for_my_datasource = cache_for_my_datasource.tables;
bool is_mytable_cached = exists table_cache_for_my_datasource.my_table;
date date_when_mytable_was_cached = table_cache_for_my_datasource.my_table.created;
        @endcode

        @note This API is not available in the client library

        @see
        - @ref sql-cache
    **/
    static hash<auto> getSqlCacheInfo() {
%ifdef QorusServer
        return Qorus.dsmanager.getCacheInfo();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! clears all objects for given @ref dsconn "datasource" from the cache (for example, if database objects have been updated in the dataserver)
    /** @param datasource the name of a Qorus @ref dsconn "datasource"
        @param table_name an optional table name to clear; if not present, then all objects in the given datasource are cleared

        @par Example:
        @code{.py}
        UserApi::clearSqlTableCache("omquser");
        @endcode

        @note This API is not available in the client library

        See
        - clear_sql_table_cache()
        - @ref sql-cache
    **/
    static clearSqlTableCache(string datasource, *string table_name) {
%ifdef QorusServer
        Qorus.dsmanager.clearTableCache(datasource, table_name);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! clears cached objects for given @ref dsconn "datasource" (for example, if database objects have been updated in the dataserver)
    /** @param datasource a @ref Qore::SQL::DatasourcePool "DatasourcePool" object for a @ref dsconn "Qorus datasource"; note that if the @ref Qore::SQL::DatasourcePool object cannot be matched back to a known @ref dsconn "Qorus datasource", an \c INVALID-DATASOURCE exception will be thrown
        @param table_name an optional table name to clear; if not present, then all objects in the given datasource are cleared

        @par Example:
        @code{.py}
        UserApi::clearSqlTableCache(datasource_pool);
        @endcode

        @throw INVALID-DATASOURCE this exception is thrown if the \a datasource argument cannot be matched to a known @ref dsconn "Qorus datasource"

        @note This API is not available in the client library

        @see
        - @ref sql-cache
    **/
    static clearSqlTableCache(AbstractDatasource datasource, *string table_name) {
%ifdef QorusServer
        Qorus.dsmanager.clearTableCache(datasource, table_name);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Gets a lookup value from the value map by a key; the value map must be registered to the current interface
    /** @param mapname name of the value map
        @param key a key name

        @return the value assigned to the key

        @throw VALUE-MAP-ERROR the given value map is unknown or not registered to the current interface

        @note This API is not available in the client library

        @see
        - @ref value-maps
        - @ref valuemap-devel
    */
    static auto getValueMap(string mapname, string key) {
%ifdef QorusServer
        if (tld.isServiceContext())
            return tld.svc.getValueMap(mapname, key);

        if (tld.isJobContext())
            return tld.job.getValueMap(mapname, key);

        if (tld.isWorkflowContext())
            return tld.wf.getValueMap(mapname, key);

        throw "VALUE-MAP-ERROR", sprintf("no interface context for UserApi::getValueMap(%y) call", mapname);
%endif

%ifdef QorusClientInjectedTest
        return _get_value_map(mapname, key);
%else
%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
%endif
    }

    #! Gets all value maps valid for the current interface
    /** @return a list of hashes describing available value maps; keys are value map names; values are hashes with the following keys:
        - \c "id": the internal ID of the value map
        - \c "name": the name of the value map
        - \c "description": a string describing the value map
        - \c "author": the author tag
        - \c "throws_exception": a tag that controls the behavior when an unknown mapping is referenced (@ref value-map-exceptions)
        - \c "valuetype": the type of values in the map
        - \c "created": the created time stamp
        - \c "modified": the last modified time stamp

        @note This API is not available in the client library

        @see
        - @ref value-maps
        - @ref valuemap-devel
    */
    static list<auto> getValueMaps() {
%ifdef QorusServer
        if (tld.isServiceContext())
            return tld.svc.getValueMaps();

        if (tld.isJobContext())
            return tld.job.getValueMaps();

        if (tld.isWorkflowContext())
            return tld.wf.getValueMaps();

        throw "VALUE-MAP-ERROR", "no interface context for UserApi::getValueMaps() call";
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! posts a successful SLA event for SLA monitoring and performance tracking
    /** @par Example:
        @code{.py}
        UserApi::postSlaEventSuccess(sla, value);
        @endcode

        @param sla the SLA name
        @param value the SLA performance value

        @return @ref True if the event was posted, @ref False if not (because the SLA does not exist)

        @see post_sla_event_success()
    */
    static bool postSlaEventSuccess(string sla, number value) {
%ifdef QorusServer
        return Qorus.qmm.postSlaEventSuccess(sla, value, CodeActionReason::getSource() ?? "system");
%endif

%ifdef QorusClient
        return qrest.post("slas/" + sla + "/success", {"value": value});
%endif
    }

    #! posts an unsuccessful SLA event for SLA monitoring and performance tracking
    /** @par Example:
        @code{.py}
        UserApi::postSlaEventError(sla, value, ex.err, ex.desc);
        @endcode

        @param sla the SLA name
        @param value the SLA performance value
        @param err the error code for the SLA event error
        @param desc the error description for the SLA event error

        @return @ref True if the event was posted, @ref False if not (because the SLA does not exist)
    */
    static bool postSlaEventError(string sla, number value, string err, string desc) {
%ifdef QorusServer
        return Qorus.qmm.postSlaEventError(sla, value, CodeActionReason::getSource() ?? "system", err, desc);
%endif

%ifdef QorusClient
        return qrest.post("slas/" + sla + "/error", {"value": value, "err": err, "desc": desc});
%endif
    }

    #! flushes all pending SLA events to disk and returns after the data has been committed
    /** @par Example:
        @code{.py}
        UserApi::flushSlaEvents();
        @endcode

        @note This API is not available in the client library
    */
    static flushSlaEvents() {
%ifdef QorusServer
        Qorus.qmm.flushSlaEvents();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns information about the given system service (if it's currently loaded)
    /** to get information about system services whether they are loaded or not, call:
        @code{.py}
        omqservice.system.omqmap.lookupserviceinfo("system", <name>)
        @endcode

        @param name the name of the system service to query
        @return a hash of user information or NOTHING if the service is not loaded; the hash will have the following structure:
        - \c type: \c "system"
        - \c name: the name of the service
        - \c version: version of the service
        - \c desc: description of the service
        - \c serviceid: service ID
        - \c status: @ref OMQ::SSRunning or @ref OMQ::SSLoaded
        - \c threads: number of running threads in the service
        - \c autostart: @ref True or @ref False if the autostart flag is set
        - \c loaded: date/time the service was loaded
        - \c methods: list of hashes for each method with \c name and \c desc keys

        @note This API is not available in the client library
    */
    static *hash<auto> getSystemServiceInfo(string name) {
%ifdef QorusServer
        return services.getServiceInfo("system", name);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns information about the given service (if it's currently loaded)
    /** to get information about services whether they are loaded or not, call:
        @code{.py}
omqservice.system.omqmap.lookupserviceinfo(<type>, <name>)
        @endcode

        @param type the type of service (either \c "system" or \c "user"; case is ignored)
        @param name the name of the system service to query

        @return a hash of service information or NOTHING if the service is not loaded; the hash will have the following structure:
        - \c type: either \c "system" or \c "user" corresponding to the argument
        - \c name: the name of the service
        - \c version: version of the service
        - \c patch: the patch string for the service
        - \c desc: description of the service
        - \c author: the author of the service
        - \c serviceid: service ID
        - \c parse_options: parse options for the service
        - \c status: @ref OMQ::SSRunning or @ref OMQ::SSLoaded
        - \c log: path to the service log file
        - \c active_calls: number of active service calls and persistent connection handlers currently in progress
        - \c waiting_threads: number of threads waiting on the service (for a service reset or unload action)
        - \c threads: number of running threads in the service
        - \c autostart: @ref True or @ref False if the autostart flag is set
        - \c manual_autostart: @ref True or @ref False the autostart value has been manually set
        - \c loaded: date/time the service was loaded
        - \c methods: list of hashes for each method with \c name and \c desc keys
        - \c resources: list of service resources
        - \c resource_files: list of service file resources
        - \c options: service options
        - \c groups: interface groups that the service belongs to
        - \c alerts: any alerts raised against the service

        @note This API is not available in the client library
    */
    static *hash<auto> getServiceInfo(string type, string name) {
%ifdef QorusServer
        return services.getServiceInfo(type.lwr(), name);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns a list of hashes giving information about the currently-running workflow execution instances
    /** @param name optional workflow name for filtering the result list
        @param ver optional workflow version for filtering the result list (only used if \a name also passed)

        @return a list of hashes giving information about the currently-running workflow execution instances; if no matching workflow execution instances are running, then an empty list is returned; otherwise each list element is a hash with the following keys:
        - \c executionID: the workflow execution instance id
        - \c name: the name of the workflow
        - \c version: version of the workflow
        - \c workflowid: the workflowid of the workflow
        - \c mode: @ref OMQ::WM_Normal or @ref OMQ::WM_Recovery
        - \c sync: @ref True if the execution instance is synchronous, @ref False if not
        - \c status: @ref OMQ::WISInitializing, @ref OMQ::WISRunning, @ref OMQ::WISWaiting, @ref OMQ::WISStopping
        - \c iterations: number of segment iterations performed so far
        - \c totalSegments: number of segments executed
        - \c errors: total number of errors encountered
        - \c warnings: total number of warnings raised
        - \c starttime: date/time the execution instance was started
        - \c options: options set on the workflow execution instance
        - \c logfile: log file name
        - \c remote: @ref True if the workflow is running as a remote @ref qwf "qwf" process, @ref False if not

        @note This API is not available in the client library

        @see
        - getRunningWorkflowInfo()
    */
    static list getRunningWorkflowList(*string name, *string ver) {
%ifdef QorusCore
        return Qorus.control.getWorkflowInfoList(name, ver);
%endif

%ifdef QorusClusterServer
        return Qorus.control_client.getWorkflowInfoList(name, ver);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns a hash of the workflow execution instance info if the ID is valid or an empty hash if not
    /** returns an empty hash if the workflow execution ID is not currently valid
        @param id workflow execution instance id

        @return a hash of the workflow execution instance info if the ID is valid or an empty hash if not; if valid, the hash will have the following keys:
        - \c name: the name of the workflow
        - \c version: version of the workflow
        - \c workflowid: the workflowid of the workflow
        - \c executionID: the workflow execution instance id (same as the argument)
        - \c mode: @ref OMQ::WM_Normal or @ref OMQ::WM_Recovery
        - \c sync: @ref True if the execution instance is synchronous, @ref False if not
        - \c status: @ref OMQ::WISInitializing, @ref OMQ::WISRunning, @ref OMQ::WISWaiting, @ref OMQ::WISStopping
        - \c iterations: number of segment iterations performed so far
        - \c totalSegments: number of segments executed
        - \c errors: total number of errors encountered
        - \c warnings: total number of warnings raised
        - \c starttime: date/time the execution instance was started
        - \c options: options set on the workflow execution instance
        - \c logfile: log file name
        - \c remote: @ref True if the workflow is running as a remote @ref qwf "qwf" process, @ref False if not

        @note This API is not available in the client library

        @see
        - getRunningWorkflowList()
    */
    static hash getRunningWorkflowInfo(softint id) {
%ifdef QorusCore
        return Qorus.control.getWorkflowInfo(id);
%endif

%ifdef QorusClusterServer
        return Qorus.control_client.getWorkflowInfo(id);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! creates a workflow order data instance in the database
    /** Creates a workflow order data instance of the specified type with the data passed.

        To ensure that a given workflow order is only created once for a given unique key value, make sure
        your workflow defines @ref wf_keylist "order keys", and use one of the following options to guarantee
        uniqueness of the order:
        - \c global_unique_key
        - \c workflow_specific_unique_key
        - \c workflow_unique_key

        @param name the name of the workflow
        @param version the version of the workflow; if this parameter is not passed, then the latest version of the workflow
        (determined by the latest created date for the workflow_instance entry) will be used
        @param params The hash passed must have at either a \c staticdata key or an \c external_order_instanceid key, valid keys:
        - \c dynamicdata: (optional hash) the initial @ref dynamicdata "dynamic data" for the order
        - \c external_order_instanceid: (optional/required string) the external order instance ID for the workflow data; one
        of \c staticdata or \c external_order_instanceid must be provided
        - \c global_unique_key: (optional hash) a hash giving one or more unique @ref wf_keylist "order keys" for the order
        (across all workflows regardless of workflowid, name, or version); keys are order key names and values are the
        string key values; if this key already exists for any order in the system, then the order creation will fail with a
        \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and the value is the unique key value;
        this value will also be created as an order key
        - \c orderkeys: (optional hash) a hash of @ref wf_keylist "order keys" for the order
        - \c parent_workflow_instanceid: (optional int) a loosely-coupled workflow that will be marked as the parent of this
        workflow; if this key is not set, and this method is called from workflow code (even indirectly, by calling a
        service method that calls this method in the same thread as the call from workflow code), the new order will be
        loosely-coupled with the calling workflow order as the parent; to keep this from happening, set the value of this
        key to \c False
        - \c priority: the order priority (optional int, default @ref OMQ::DefaultOrderPriority) from 0 - 999; priority 0 is the
        highest; 999 is the lowest
        - \c scheduled: (optional date) the earliest date and time the order can be processed; if this date is given as a
        future date/time value and a @ref OMQ::StatReady status is given, then the initial status of the workflow order data
        instance will be automatically changed to @ref OMQ::StatScheduled instead of @ref OMQ::StatReady
        - \c sensitive_data: (optional hash) a hash of sensitive data information for the workflow; this key can only be used
        when submitting the data over a secure (encrypted) connection; the keys are sensitive data key types, values are
        hashes keyed by sensitive data values, and the hash values have the following keys:
            - \c aliases: (optional list of strings) zero or more string aliases for the sensitive data
            - \c data: (required hash) the sensitive data hash itself
            - \c meta: (optional hash) a hash of metadata for the sensitive data with the following recommended keys
            (recommended keys are not enforced by the API itself):
                - \c PURPOSE: free-form information about the purpose of the sensitive data
                - \c CATEGORIES: free-form information about the categories of sensitive data
                - \c RECIPIENTS: free-form information about the recipients or recipient catories of sensitive data
                - \c STORAGE: free-form information about the storage time or rules for sensitive data
        - \c staticdata: (optional/required hash) the initial @ref staticdata "static data" for the order; one of
        \c staticdata or \c external_order_instanceid must be provided
        - \c tempdata: (optional hash) the initial @ref tempdata "temporary data" for the order
        - \c workflow_specific_unique_key: (optional hash) a hash giving one or more unique @ref wf_keylist "order keys" for
        the particular workflowid (which matches a unique name and workflow version); keys are order key names and values
        are the string key values; if any of the keys given already exists for an order with the target workflowid, then
        the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and
        the value is the unique key value; this value will also be created as an order key
        - \c workflow_unique_key: (optional hash) a hash giving one or more unique @ref wf_keylist "order keys" for the
        particular workflow by name only (across all workflows with the same name regardless of version);
        keys are order key names and values are the string key values; if this key already exists for a workflow order
        with the same name, then the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a
        valid order key, and the value is the unique key value; this value will also be created as an order key
        @param status create the workflow order data instance with this status; may be either:
        - @ref OMQ::StatReady which is the default value
        - @ref OMQ::StatBlocked meaning: do not process the order, wait for unblocking later

        @return the workflow instance ID created

        @throw SUBMIT-ORDER-ERROR invalid \a status value
        @throw ORDER-DATA-ERROR missing either \c external_order_instanceid or \c staticdata, unknown workflow; invalid keys
        or sensitive data format
        @throw DUPLICATE-ORDER-KEY the given unique key already exists in the defined scope, also sets \c arg with a
        \c workflow_instance_ids key with a list of all conflicting workflow instance IDs
        @throw WORKFLOW-KEY-ERROR invalid workflow key given

        @note
        - In the \a params argument above, either the \c staticdata or \c external_order_instanceid values must be
          provided; \c staticdata may be omitted if \c external_order_instanceid is provided and vice-versa
        - The \c global_unique_key, \c workflow_specific_unique_key, and \c workflow_unique_key options can be used to
          ensure that given workflow order data is only created once; note that any archiving schema is also searched
          when checking for duplicate keys.  These options may be combined, but it's recommended to use no more than
          one key for uniqueness.

        @see
        - createRemoteOrder()
    */
    static softint createOrder(string name, *string version, hash<auto> params, string status = StatReady) {
%ifdef QorusCore
        return orders.submitData(NOTHING, name, version, params, status);
%endif

%ifdef QorusClusterServer
        return orders.submitDataExtern(NOTHING, name, version, params, status, tld.wfe.workflow_instanceid);
%endif

%ifdef QorusClient
        if (version.val()) {
            name += ":" + version;
        }
        return qrest.post("workflows/" + name + "/createOrder", params + {"status": status}).workflow_instanceid;
%endif
    }

    #! creates a workflow order data instance in a remote Qorus instance
    /** Creates a workflow order data instance of the specified type with the data passed in the specified remote Qorus instance.

        To ensure that a given workflow order is only created once for a given unique key value, make sure
        your workflow defines @ref wf_keylist "order keys", and use one of the following options to guarantee
        uniqueness of the order:
        - \c global_unique_key
        - \c workflow_specific_unique_key
        - \c workflow_unique_key

        @param remote the name of the @ref remoteconn "remote Qorus connection"
        @param name the name of the workflow
        @param version the version of the workflow; if this parameter is not passed, then the latest version of the workflow
        (determined by the latest created date for the workflow_instance entry) will be used
        @param params The hash passed must have at either a \c staticdata key or an \c external_order_instanceid key, valid
        keys:
        - \c dynamicdata: (optional hash) the initial @ref dynamicdata "dynamic data" for the order
        - \c external_order_instanceid: (optional/required string) the external order instance ID for the workflow data; one
        of \c staticdata or \c external_order_instanceid must be provided
        - \c global_unique_key: (optional hash) a hash giving one or more unique @ref wf_keylist "order keys" for the order
        (across all workflows regardless of workflowid, name, or version); keys are order key names and values are the
        string key values; if this key already exists for any order in the system, then the order creation will fail with a
        \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and the value is the unique key value;
        this value will also be created as an order key
        - \c orderkeys: (optional hash) a hash of @ref wf_keylist "order keys" for the order
        - \c parent_workflow_instanceid: (optional int) a loosely-coupled workflow that will be marked as the parent of this
        workflow; if this key is not set, and this method is called from workflow code (even indirectly, by calling a
        service method that calls this method in the same thread as the call from workflow code), the new order will be
        loosely-coupled with the calling workflow order as the parent; to keep this from happening, set the value of this
        key to \c False
        - \c priority: the order priority (optional int, default @ref OMQ::DefaultOrderPriority) from 0 - 999; priority 0 is the
        highest; 999 is the lowest
        - \c scheduled: (optional date) the earliest date and time the order can be processed; if this date is given as a
        future date/time value and a @ref OMQ::StatReady status is given, then the initial status of the workflow order data
        instance will be automatically changed to @ref OMQ::StatScheduled instead of @ref OMQ::StatReady
        - \c sensitive_data: (optional hash) a hash of sensitive data information for the workflow; this key can only be used
        when submitting the data over a secure (encrypted) connection; the keys are sensitive data key types, values are
        hashes keyed by sensitive data values, and the hash values have the following keys:
            - \c aliases: (optional list of strings) zero or more string aliases for the sensitive data
            - \c data: (required hash) the sensitive data hash itself
            - \c meta: (optional hash) a hash of metadata for the sensitive data with the following recommended keys
            (recommended keys are not enforced by the API itself):
                - \c PURPOSE: free-form information about the purpose of the sensitive data
                - \c CATEGORIES: free-form information about the categories of sensitive data
                - \c RECIPIENTS: free-form information about the recipients or recipient catories of sensitive data
                - \c STORAGE: free-form information about the storage time or rules for sensitive data
        - \c staticdata: (optional/required hash) the initial @ref staticdata "static data" for the order; one of
        \c staticdata or \c external_order_instanceid must be provided
        - \c tempdata: (optional hash) the initial @ref tempdata "temporary data" for the order
        - \c workflow_specific_unique_key: (optional hash) a hash giving one or more unique @ref wf_keylist "order keys" for
        the particular workflowid (which matches a unique name and workflow version); keys are order key names and values
        are the string key values; if any of the keys given already exists for an order with the target workflowid, then
        the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a valid order key, and
        the value is the unique key value; this value will also be created as an order key
        - \c workflow_unique_key: (optional hash) a hash giving one or more unique @ref wf_keylist "order keys" for the
        particular workflow by name only (across all workflows with the same name regardless of version);
        keys are order key names and values are the string key values; if this key already exists for a workflow order
        with the same name, then the order creation will fail with a \c DUPLICATE-ORDER-KEY error; the hash key must be a
        valid order key, and the value is the unique key value; this value will also be created as an order key
        @param status create the workflow order data instance with this status; may be either:
        - @ref OMQ::StatReady which is the default value
        - @ref OMQ::StatBlocked meaning: do not process the order, wait for unblocking later
        @param register_dependency if @ref True (the default) then if the connection is monitored as down, the
        calling interface will be temporarily disabled until the connection is up again

        @return the workflow instance ID created

        @throw GET-REMOTE-ERROR The given @ref remoteconn "connection" is not known
        @throw SUBMIT-ORDER-ERROR invalid \a status value
        @throw WORKFLOW-ERROR unknown or invalid workflow
        @throw ORDER-DATA-ERROR missing either \c external_order_instanceid or \c staticdata, invalid keys or sensitive data
        format
        @throw DUPLICATE-ORDER-KEY the given unique key already exists in the defined scope, also sets \c arg with a
        \c workflow_instance_ids key with a list of all conflicting workflow instance IDs
        @throw WORKFLOW-KEY-ERROR invalid workflow key given

        @note
        - In the \a params argument above, either the \c staticdata or \c external_order_instanceid values must be
          provided; \c staticdata may be omitted if \c external_order_instanceid is provided and vice-versa
        - The \c global_unique_key, \c workflow_specific_unique_key, and \c workflow_unique_key options can be used to
          ensure that given workflow order data is only created once; note that any archiving schema is also searched
          when checking for duplicate keys.  These options may be combined, but it's recommended to use no more than
          one key for uniqueness.

        @see
        - createOrder()
    */
    static softint createRemoteOrder(string remote, string name, *string version, hash<auto> params,
            string status = StatReady, bool register_dependency = True) {
%ifdef QorusServer
        QorusSystemRestHelper qorus = UserApi::getRemoteRestConnection(remote, True, register_dependency);
%endif

%ifdef QorusClient
        QorusSystemRestHelper qorus(remote);
%endif

%ifndef QorusFakeApi
        string uri_path = sprintf("workflows/%s", name);
        if (version.val())
            uri_path += ":" + version;
        uri_path += "?action=createOrder";

        params.status = status;

        hash<auto> h = qorus.post(uri_path, params);
        return h.workflow_instanceid;
%endif
    }

    #! executes a workflow order synchronously and returns the final status and order ID in a hash
    /** @param name the workflow name
        @param version the workflow version (if NOTHING then the latest version of the workflow will be used)
        @param sdata the static data hash for the workflow order
        @param opts the options for the synchronous workflow execution instance
        @param ddata the optional initial dynamic data hash for the workflow order
        @param priority the order priority for the order
        @param orderkeys optional order keys for the order
        @param external_order_instanceid the optional external order instanceid for the order
        @param parent_workflow_instanceid: an optional loosely-coupled workflow order ID that will be marked as the
        parent of this order; if this key is not set, and this method is called from workflow code (even indirectly,
        by calling a service method that calls this method in the same thread as the call from workflow code), the
        new order will be loosely-coupled with the calling workflow order as the parent; to keep this from happening,
        set the value of this key to \c False

        @return a hash of workflow order information with the following keys:
        - \c workflow_instanceid (int): the workflow order instance ID
        - \c status (string): the order status commit to the database (for possible values, see @ref OMQ::StatusDescriptions)
        - \c dynamicdata (*hash): the order's @ref dynamicdata "dynamic data hash", if any
        - [\c error (string)]: the last error for the order, if any
        - [\c description (string)]: the last error description for the order, if any
        - [\c info (*hash)]: the last error info hash for the order, if any

        @note This API is not available in the client library
    */
    static hash<auto> execSynchronousWorkflow(string name, *string version, hash<auto> sdata, *hash<auto> opts,
            *hash<auto> ddata, softint priority = DefaultOrderPriority, *hash<auto> orderkeys,
            *softstring external_order_instanceid, *softint parent_workflow_instanceid) {
%ifdef QorusServer
        hash<auto> h = (
            "staticdata": sdata,
            "dynamicdata": ddata,
            "priority": priority,
            "orderkeys": orderkeys,
            "external_order_instanceid": external_order_instanceid,
            "parent_workflow_instanceid": parent_workflow_instanceid,
        );
        OrderData order(h);

        order.setNameAndVersion(name, version);
%endif

%ifdef QorusCore
        hash<auto> rv = Qorus.control.execSynchronousWorkflow({"user": "%SYS%"}, order.getWorkflowId(), order, opts);
%endif

%ifdef QorusClusterServer
        hash<auto> rv = Qorus.control_client.execSynchronousWorkflow({"user": "%SYS%"}, order.getWorkflowId(), order, opts);
%endif

%ifdef QorusServer
        # for new APIs, ensure that "workflow_instanceid" is an int
        return rv + {
            "workflow_instanceid": rv.workflow_instanceid.toInt(),
        };
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! posts an application event of class @ref OMQ::QE_CLASS_USER
    /** @param severity see @ref ErrorSeverityCodes for possible values
        @param info the user-defined information for the event

        @throw POST-USER-EVENT-ERROR invalid severity value

        @note This API is not available in the client library
    */
    static int postUserEvent(string severity, auto info) {
%ifdef QorusServer
        return Qorus.events.postUserEvent(severity, info);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns Qorus runtime properties as a hash
    /** @return Qorus runtime properties as a hash; if no properties are set, returns an empty hash

        @note This API is not available in the client library
    */
    static hash runtimeProperties() {
%ifdef QorusServer
        return Qorus.getRuntimeProps();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! calls a system @ref rpcapi "RPC API" with the argument list to the API method as a top-level argument to this method; the API is called with system permissions (no restrictions)
    /** @param call the full @ref rpcapi "RPC API" method name (ex: \c "omq.system.exec-synchronous-exiting"); see
        @ref qorusapi for a full list
        @param args any arguments to the method; if multiple argument should be passed to the method, use a list of
        arguments here

        @return the return value of the method

        @throw UNKNOWN-API-CALL invalid API method
        @throw INVALID-INTERNAL-API-CALL API may not be called internally (ex: omq.system.shutdown-wait())

        @note This API is not available in the client library

        @see
        - @ref callRestApi()
    */
    static auto callNetworkApiArgs(string call, *softlist<auto> args) {
%ifdef QorusCore
        # TLD must be created for remote calls from external interface programs
        ensure_create_tld();

        QorusApiContextHelper tch();

        return call_system_api_as_user(call, args, "%SYS%", False);
%endif

%ifdef QorusClusterServer
        return Qorus.callCoreStaticMethod("UserApi", "callNetworkApiArgs", call, args);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! calls a system @ref rpcapi "RPC API" and returns the result; the API is called with system permissions (no restrictions)
    /** include any arguments after the method name, ex:
        @code{.py}
        UserApi::callNetworkApi("omq.system.exec-synchronous-existing", ("workflow_instanceid": wfiid));
        @endcode

        @param call the full @ref rpcapi "RPC API" method name (ex: \c "omq.system.exec-synchronous-exiting"); see
        @ref qorusapi for a full list

        @return the return value of the method

        @throw UNKNOWN-API-CALL invalid API method
        @throw INVALID-INTERNAL-API-CALL API may not be called internally (ex: omq.system.shutdown-wait())

        @note This API is not available in the client library

        @see
        - @ref callRestApi()
    */
    static auto callNetworkApi(string call) {
%ifdef QorusCore
        # TLD must be created for remote calls from external interface programs
        ensure_create_tld();

        QorusApiContextHelper tch();

        return call_system_api_as_user(call, argv, "%SYS%", False);
%endif

%ifdef QorusClusterServer
        return Qorus.callCoreStaticMethod("UserApi", "callNetworkApiArgs", call, argv);
%endif

%ifndef QorusServer
        delete argv;
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! calls a system @ref restapi "REST API" method and returns the result; the API is called with system permissions (no restrictions)
    /** @par Example:
        @code{.py}
        int pid = UserApi::callRestApi("GET", "system/pid");
        @endcode

        @param method the HTTP method name in all caps
        @param path the URI path without the leading \c "api"; if it does not begin with \c "latest" or \c "v#" (for a
        REST API version), then \c "/latest/" is prepended ot the path, meaning that the latest version of the REST
        API will be used
        @param body_args the arguments to the call

        @return the return value of the method

        @note to use a specific REST API version, make sure \c path begins with \c "/api"

        @see
        - @ref RestHandler::RestHandler::handleExternalRequest() "RestHandler::handleExternalRequest()" for
          information about possible exceptions
    */
    static auto callRestApi(string method, string path, *hash<auto> body_args) {
        return _priv_call_rest_api(method, path, body_args);
    }

    #! returns a hash of system info
    /** @return a hash of system info with the following keys:
        - \c instance-key: value of the system option by the same name
        - \c session-id: the session ID for the current Qorus application session
        - \c omq-version: the version string for the Qorus server
        - \c omq-version-code: a numeric code of the Qorus server version, where @code{.py} major = (x / 10000), minor
           = (x / 100) % 100, = x % 100 @endcode this value is suitable for comparisons (ex: for Qorus 5.1.0,
           \c omq-version-code = 50100) <!-- % -->
        - \c qore-version: the version string for the qore build used
        - \c datamodel-version: the datamodel version required by this version of Qorus
        - \c omq-schema: the datasource string for the system schema (without the password)
        - \c omq-driver: the DB driver name for the system schema
        - \c omquser-schema: the datasource string for the user schema (without the password)
        - \c starttime: the date and time when the instance was started
        - \c hostname: the hostname of the machine where the Qorus server is running
        - \c pid: the PID of the Qorus server process
        - \c threads: number of threads currently active
        - \c schema-properties: a hash of schema properties with the following keys:
        - \c omq-schema-version
        - \c omq-schema-compatibility
        - \c omq-load-schema-compatibility
        - \c logfile: the path for the system log file
        - \c edition: \c Community for Qorus Integration Engine(R) Community Edition

        @note This API is not available in the client library
    */
    static hash<auto> getSystemInfo() {
%ifdef QorusCore
        return qorus_get_system_info();
%endif

%ifdef QorusClusterServer
        return Qorus.callCoreStaticMethod("UserApi", "getSystemInfo");
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns the current Qorus application session ID
    /** @return the current Qorus application session ID

        @note When used in the @ref clientintro "Qorus client", this method also will implicitly
        @ref client_initialization "initialize the client library"

        @see
        - @ref appsessionmodel for more information about the session ID
    */
    static int getSessionId() {
%ifdef QorusCore
        return Qorus.session.getID();
%endif

%ifdef QorusClusterServer
        return Qorus.sessionid;
%endif

%ifdef QorusClient
        QorusClient::initFast();
        return qrest.get("system/session-id");
%endif
    }

    # returns the current interface object
    static private:internal object getInterfaceForLogging() {
%ifdef QorusCore
        if (tld) {
            *object ix = tld.getInterface();
            return ix ?? Qorus;
        }
        return Qorus;
%endif

%ifdef QorusClusterServer
        return Qorus;
%endif
    }

    #! Starts capturing %Qore objects created from Java APIs in the current interface's object cache
    /** @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @note This API is not available in the client library

        @since Qorus 4.1

        @see @ref jni_qore_object_lifecycle_management
    */
    static startCapturingObjectsFromJava() {
%ifdef QorusServer
        _priv_get_interface_object().startCapturingObjectsFromJava();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Stops capturing %Qore objects created from Java APIs in the current interface's object cache
    /** @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @note This API is not available in the client library

        @since Qorus 4.1

        @see @ref jni_qore_object_lifecycle_management
    */
    static stopCapturingObjectsFromJava() {
%ifdef QorusServer
        _priv_get_interface_object().stopCapturingObjectsFromJava();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Starts capturing %Qore objects created from Python APIs in the current interface's object cache
    /** @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @note This API is not available in the client library

        @since Qorus 5.0

        @see @ref python_qore_object_lifecycle_management
    */
    static startCapturingObjectsFromPython() {
%ifdef QorusServer
        _priv_get_interface_object().startCapturingObjectsFromPython();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Stops capturing %Qore objects created from Python APIs in the current interface's object cache
    /** @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @note This API is not available in the client library

        @since Qorus 5.0

        @see @ref python_qore_object_lifecycle_management
    */
    static stopCapturingObjectsFromPython() {
%ifdef QorusServer
        _priv_get_interface_object().stopCapturingObjectsFromPython();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Saves the object in the object cache
    /** @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @note This API is not available in the client library

        @since Qorus 4.1
    */
    static saveObjectInObjectCache(object obj) {
%ifdef QorusServer
        _priv_get_interface_object().saveObject(obj);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Removes the object from the object cache
    /** @return @ref True if the object was removed, @ref False if it was not in the cache

        @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @since Qorus 4.1
    */
    static bool clearObjectFromObjectCache(object obj) {
%ifdef QorusServer
        return _priv_get_interface_object().clearObject(obj);
%else
        return False;
%endif
    }

    #! Returns the date/time the object was cached or @ref nothing if the object is not in the cache
    /** @param obj the object to check

        @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @since Qorus 4.1
    */
    static *date checkObjectCache(object obj) {
%ifdef QorusServer
        return _priv_get_interface_object().checkCache(obj);
%else
        return NOTHING;
%endif
    }

    #! Returns the number of objects in the cache
    /** @return the number of objects in the cache

        @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @since Qorus 4.1
    */
    static int getObjectCacheSize() {
%ifdef QorusServer
        return _priv_get_interface_object().cacheSize();
%else
        return 0;
%endif
    }

    #! Clears the entire the object cache
    /** @return the number of objects cleared from the cache

        @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @since Qorus 4.1
    */
    static int clearObjectCache() {
%ifdef QorusServer
        return _priv_get_interface_object().clearCache();
%else
        return 0;
%endif
    }

    #! Clears the entire the object cache for all objects cached before the given date/time
    /** @return the number of objects cleared from the cache

        @throw NO-INTERFACE thrown if there is no interface context; this API is only valid when called in a
        workflow, service, or job context

        @since Qorus 4.1
    */
    static int clearObjectCache(date cutoff) {
%ifdef QorusServer
        return _priv_get_interface_object().clearCache(cutoff);
%else
        return 0;
%endif
    }

    #! Allows the current thread's call stack to be retrieved in Qorus
    /** %Qore function ref Qore::get_thread_call_stack() is prohibited from use in Qorus interfaces due to sandboxing restrictions

        @since Qorus 4.1
    */
    static list<hash<CallStackInfo>> getThreadCallStack() {
        return Qore::get_thread_call_stack();
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments

        @see @ref OMQ::UserApi::UserApi::logArgsFatal() "UserApi::logArgsFatal()"
    */
    static logFatal(softstring msg) {
        UserApi::logArgsFatal(msg, argv);
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments

        @see @ref OMQ::UserApi::UserApi::logArgsError() "UserApi::logArgsError()"
    */
    static logError(softstring msg) {
        UserApi::logArgsError(msg, argv);
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments

        @see @ref OMQ::UserApi::UserApi::logArgsWarn() "UserApi::logArgsWarn()"
    */
    static logWarn(softstring msg) {
        UserApi::logArgsWarn(msg, argv);
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments

        @see @ref OMQ::UserApi::UserApi::logArgsWarn() "UserApi::logArgsWarn()"
    */
    static logInfo(softstring msg) {
        UserApi::logArgsInfo(msg, argv);
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments

        @see @ref OMQ::UserApi::UserApi::logArgsDebug() "UserApi::logArgsDebug()"
    */
    static logDebug(softstring msg) {
        UserApi::logArgsDebug(msg, argv);
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments

        @see @ref OMQ::UserApi::UserApi::logTrace() "UserApi::logTrace()"
    */
    static logTrace(softstring msg) {
        UserApi::logArgsTrace(msg, argv);
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments
        @param args the arguments for the format string \a msg

        @see @ref OMQ::UserApi::UserApi::logFatal() "UserApi::logFatal()"
    */
    static logArgsFatal(softstring msg, *softlist<auto> args) {
%ifdef QorusServer
        (UserApi::getInterfaceForLogging()).logFatal("%s", vsprintf(msg, args));
%endif

%ifdef QorusClient
        omqclient.getClientLogger(verbose).log(LoggerLevel::FATAL, "%s", vsprintf(msg, args));
%endif
    }

    #! Writes to the current interface log file with the given log level
    /** @param level log levels as defined by @ref Logger::LoggerLevel
        @param msg the format string for the log message, arguments follow

        @since Qorus 4.1
    */
    static logWithLevel(int level, string msg) {
        UserApi::logWithLevelArgs(level, msg, argv);
    }

    #! Writes to the current interface log file with the given log level
    /** @param level log levels as defined by @ref Logger::LoggerLevel
        @param msg the format string for the log message
        @param args optional argument to format specifiers in \a msg

        @since Qorus 4.1
    */
    static logWithLevelArgs(int level, string msg, *softlist<auto> args) {
%ifdef QorusServer
        (UserApi::getInterfaceForLogging()).logArgs(level, msg, args);
%endif

%ifdef QorusClient
        omqclient.getClientLogger(verbose).logArgs(level, msg, args);
%endif
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments
        @param args the arguments for the format string \a msg

        @see @ref OMQ::UserApi::UserApi::logError() "UserApi::logError()"
    */
    static logArgsError(softstring msg, *softlist<auto> args) {
%ifdef QorusServer
        (UserApi::getInterfaceForLogging()).logError("%s", vsprintf(msg, args));
%endif

%ifdef QorusClient
        omqclient.getClientLogger(verbose).logArgs(LoggerLevel::ERROR, msg, args);
%endif
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments
        @param args the arguments for the format string \a msg

        @see @ref OMQ::UserApi::UserApi::logWarn() "UserApi::logWarn()"
    */
    static logArgsWarn(softstring msg, *softlist<auto> args) {
%ifdef QorusServer
        (UserApi::getInterfaceForLogging()).logWarn("%s", vsprintf(msg, args));
%endif

%ifdef QorusClient
        omqclient.getClientLogger(verbose).logArgs(LoggerLevel::WARN, msg, args);
%endif
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments
        @param args the arguments for the format string \a msg

        @see @ref OMQ::UserApi::UserApi::logInfo() "UserApi::logInfo()"
    */
    static logArgsInfo(softstring msg, *softlist<auto> args) {
%ifdef QorusServer
        (UserApi::getInterfaceForLogging()).logInfo("%s", vsprintf(msg, args));
%endif

%ifdef QorusClient
        omqclient.getClientLogger(verbose).logArgs(LoggerLevel::INFO, msg, args);
%endif
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments
        @param args the arguments for the format string \a msg

        @see @ref OMQ::UserApi::UserApi::logDebug() "UserApi::logDebug()"
    */
    static logArgsDebug(softstring msg, *softlist<auto> args) {
%ifdef QorusServer
        (UserApi::getInterfaceForLogging()).logDebug("%s", vsprintf(msg, args));
%endif

%ifdef QorusClient
        omqclient.getClientLogger(verbose).logArgs(LoggerLevel::DEBUG, msg, args);
%endif
    }

    #! Writes the information passed to the workflow, service, job, or system log file depending on the calling context if the interface logger level is equal or lower
    /**
        @param msg the format string for a vsprintf() call with the remaining arguments
        @param args the arguments for the format string \a msg

        @see @ref OMQ::UserApi::UserApi::logTrace() "UserApi::logTrace()"
    */
    static logArgsTrace(softstring msg, *softlist<auto> args) {
%ifdef QorusServer
        (UserApi::getInterfaceForLogging()).logTrace("%s", vsprintf(msg, args));
%endif

%ifdef QorusClient
        omqclient.getClientLogger(verbose).logArgs(LoggerLevel::TRACE, msg, args);
%endif
    }

    #! creates a user audit event (with audit code @ref AE_USER_EVENT) against the workflow, service, or job instance
    /** @param user_event the user event code string
        @param info1 optional informational string for the \c AUDIT_EVENTS.INFO1 field
        @param info2 optional informational string for the \c AUDIT_EVENTS.INFO2 field
        @return NOTHING if user event auditing is not enabled (see system option @ref audit), or the integer audit
        event id

        @note
        - Nothing will be written to the \c AUDIT_EVENTS table if the @ref audit system option does not include
          the \c "user-events" (@ref AO_USER_EVENTS) option; in case this is not set, the call will have no effect
        - This API is not available in the client library
    */
    static *int auditUserEvent(string user_event, *string info1, *string info2) {
%ifdef QorusCore
        if (tld.isWorkflowExecContext()) {
            return Qorus.control.execHash.(tld.index).auditUserEvent(user_event, info1, info2);
        }

        if (tld.isServiceContext()) {
            return service_audit_user_event(user_event, info1, info2);
        }

        QDBG_ASSERT(tld.isJobContext());
        return job_audit_user_event(user_event, info1, info2);
%endif

%ifdef QorusQwfServer
        return Qorus.control.execHash.(tld.index).auditUserEvent(user_event, info1, info2);
%endif

%ifdef QorusQsvcServer
        service_audit_user_event(user_event, info1, info2);
%endif

%ifdef QorusQjobServer
        QDBG_ASSERT(exists tld.job);
        return job_audit_user_event(user_event, info1, info2);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! checks if the given audit event (given as a string) is enabled
    /** @param opt the audit event code to check; see @ref AuditEventStrings for possible values
        @return @ref True if the event is audited, False if not

        @throw AUDIT-EVENT-ERROR the given audit event string does not exist

        @note This API is not available in the client library
    */
    static bool auditCheckEventString(string opt) {
%ifdef QorusServer
        return Qorus.audit.checkOptionString(opt);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! checks if the given audit event (given as an integer code) is enabled
    /** @param opt the audit event code to check; see @ref AuditEventCodes for possible values
        @return @ref True if the event is audited, False if not

        @note This API is not available in the client library
    */
    static bool auditCheckEvent(softint opt) {
%ifdef QorusServer
        return Qorus.audit.checkOption(opt);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns the audit event mask
    /** @return the audit event mask

        @note This API is not available in the client library
    */
    static int auditGetMask() {
%ifdef QorusServer
        return Qorus.audit.getMask();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! puts the current thread to sleep for a certain number of seconds
    /**
        If the job, workflow execution instance, or service is stopping, this method returns immediately with a
        return value of -1; otherwise the current thread is put to sleep for the full time period requested.  If this
        method (or usleep()) is called again after -1 is returned, then a \c "STOP-ERROR" exception is thrown.

        @param arg the number of seconds to sleep

        @return 0 if current thread was put to sleep for the full time period; -1 if the sleep was interrupted because
        the current object is being stopped

        @throw STOP-ERROR the current object is stopping and this method already returned -1 as a warning

        @see
        - usleep()
    */
    static int sleep(softint arg) {
%ifdef QorusCore
        if (tld.isOrderContext()) {
            return workflow_sleep(arg);
        }

        if (tld.isServiceContext()) {
            return service_sleep(arg);
        }

        QDBG_ASSERT(exists tld.isJobContext());

        return job_sleep(arg);
%endif

%ifdef QorusQwfServer
        return workflow_sleep(arg);
%endif

%ifdef QorusQsvcServer
        return service_sleep(arg);
%endif

%ifdef QorusQjobServer
        return job_sleep(arg);
%endif

%ifdef QorusClient
        return sleep(arg);
%endif
    }

    #! puts the current thread to sleep for a certain number of microseconds
    /**
        If the job, workflow execution instance, or service is stopping, this method returns immediately with a return
        value of -1; otherwise the current thread is put to sleep for the full time period requested.  If this method
        (or sleep()) is called again after -1 is returned, then a \c "STOP-ERROR" exception is thrown.

        @param arg the number of microseconds to sleep (1 microsecond = 1/1000000 of a second)

        @return 0 if current thread was put to sleep for the full time period; -1 if the sleep was interrupted because
        the current object is being stopped

        @throw STOP-ERROR the current object is stopping and this method already returned -1 as a warning

        @see
        - sleep()
    */
    static int usleep(date arg) {
        return UserApi::usleep(arg.durationMicroseconds());
    }

    #! puts the current thread to sleep for a certain number of microseconds
    /**
        If the job, workflow execution instance, or service is stopping, this method returns immediately with a return
        value of -1; otherwise the current thread is put to sleep for the full time period requested.  If this method
        (or sleep()) is called again after -1 is returned, then a \c "STOP-ERROR" exception is thrown.

        @param arg the number of microseconds to sleep (1 microsecond = 1/1000000 of a second)

        @return 0 if current thread was put to sleep for the full time period; -1 if the sleep was interrupted because
        the current object is being stopped

        @throw STOP-ERROR the current object is stopping and this method already returned -1 as a warning

        @see
        - sleep()
    */
    static int usleep(int arg) {
%ifdef QorusCore
        if (tld.isOrderContext()) {
            return workflow_usleep(arg);
        }

        if (tld.isServiceContext()) {
            return service_usleep(arg);
        }

        QDBG_ASSERT(exists tld.isJobContext());

        return job_usleep(arg);
%endif

%ifdef QorusQwfServer
        return workflow_usleep(arg);
%endif

%ifdef QorusQsvcServer
        return service_usleep(arg);
%endif

%ifdef QorusQjobServer
        return job_usleep(arg);
%endif

%ifdef QorusClient
        return usleep(arg);
%endif
    }

    #! returns the value of the given system option or options
    /** @par Examples
        @code{.py}
# return all options
hash<auto> all_options = UserApi::getQorusOptions();

# return the value of a single option
string logdir = UserApi::getQorusOptions("logdir").logdir;

# return the values for multiple options
hash<auto> some_options = UserApi::getQorusOptions("logdir", "systemdb");
        @endcode

        @param ... zero or more options

        @return the return value depends on the arguments as follows:
        - no arguments: the return value is a hash of all options keyed by option name and the values of those options
        - one or more strings as option names: a hash giving the values of the given options keyed by option name

        @note When used in the @ref clientintro "Qorus client", this method also will implicitly
        @ref client_initialization "initialize the client library"
    */
    static hash<auto> getQorusOptions() {
%ifdef QorusServer
        return Qorus.options.get(argv);
%else
%ifdef QorusClient
        QorusClient::initFast();
        hash<auto> rv = omqclient.getOptions("qorus");
        if (argv) {
            rv = rv{argv};
        }
        return rv;
%else
        delete argv;
        return {};
%endif
%endif
    }

    #! returns a hash giving information about system options
    /**
        @note This API is not available in the client library
    */
    static hash<auto> getQorusOptionInfo() {
%ifdef QorusCore
        return Qorus.options.getOptionInfo(argv);
%endif

%ifdef QorusClusterServer
        return Qorus.options_client.getOptionInfo(argv);
%endif

%ifndef QorusServer
        delete argv;
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns a hash giving information about system options
    /**
        @note This API is not available in the client library
    */
    static hash<auto> getQorusOptionInfoArgs(*list<auto> args) {
%ifdef QorusCore
        return Qorus.options.getOptionInfo(args);
%endif

%ifdef QorusClusterServer
        return Qorus.options_client.getOptionInfo(args);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif

%ifdef QorusFakeApi
        delete argv;
%endif
    }

    #! returns the value of the given system option or options
    /**
        @note This API is not available in the client library
    */
    static auto getQorusOptionsArgs(softlist<auto> args) {
%ifdef QorusServer
        return Qorus.options.get(args);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Returns information on all active jobs visible to the calling user
    /** If any active jobs are not accessible to the calling user, then they are filtered from the hash returned.
        @return a hash is keyed by job name; the hash values are job information hashes with the following keys:
        - \c jobid: the metadata jobid of the job type
        - \c name: the job name
        - \c version: the job version
        - \c description: the job description
        - \c trigger: a string describing the timer/trigger for the job
        - [\c job_instanceid]: the id of the job instance (will only have a value if the job is currently executing)
        - [\c last_executed]: the last executed date/time of the job (NOTHING if not yet executed)
        - [\c last_executed_job_instanceid]: the last executed instance id of the job
        - [\c expiry_date]: the expiry date of the job, if any; if this date is present, then the job will not run automatically after this date
        - [\c next]: the next trigger date/time; this key is only included if the job is active
        - \c active: this value is always @ref True because this API only returns information about active jobs

        @note This API is not available in the client library
    */
    static hash<auto> getActiveJobs() {
%ifdef QorusServer
        return Qorus.jobManager.getActiveInfo();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Returns an object corresponding to a defined @ref userconn "user connection"
    /**
        @param name the name of the @ref userconn "connection"
        @param connect if @ref False an unconnected object will be returned, otherwise the object is already connected
        @param register_dependency if @ref True (the default) then if the connection is monitored as down, the calling interface will be temporarily disabled until the connection is up again
        @param rtopts any runtime options accepted by the connection

        @return the object representing the connection

        @throw CONNECTION-ERROR The given connection is not known

        @note When used in the @ref clientintro "Qorus client", this method also will implicitly
        @ref client_initialization "initialize the client library"

        @see
        - getUserConnectionTags()
    */
    static object getUserConnection(string name, bool connect = True, bool register_dependency = True,
            *hash<auto> rtopts) {
%ifdef QorusServer
        return Qorus.connections.get(name, connect, register_dependency, rtopts);
%endif

%ifdef QorusClient
        QorusClient::initFast();
        return omqclient.getUserConnection(name, connect);
%endif
    }

    #! Returns any tags set on the given @ref userconn "user connection"
    /**
        @param name the name of the @ref userconn "connection"

        @return any tags set on the given @ref userconn "user connection"

        @throw CONNECTION-ERROR The given connection is not known

        @see getUserConnection()

        @since Qorus 4.0.3
    */
    static hash<auto> getUserConnectionTags(string name) {
%ifdef QorusServer
        return Qorus.connections.getTags(name);
%endif
    }

    #! returns a new, dedicated @ref Qore::SQL::Datasource "Datasource" object, suitable for transaction management for long-running transactions
    /** @param name the name of the @ref dsconn "datasource"
        @param register_dependency if @ref True (the default) then if the connection is monitored as down, the calling interface will be temporarily disabled until the connection is up again

        @return a new, dedicated @ref Qore::SQL::Datasource "Datasource" object, suitable for transaction management for long-running transactions

        @throw DATASOURCE-ERROR The given connection is not known or is a system @ref dsconn "datasource"

        @note When used in the @ref clientintro "Qorus client", this method also will implicitly
        @ref client_initialization "initialize the client library"

        @see
        - getDatasourcePool()
    */
    static Qore::SQL::Datasource getDatasourceDedicated(string name, bool register_dependency = True) {
%ifdef QorusServer
        return Qorus.dsmanager.getDedicated(name, register_dependency);
%endif

%ifdef QorusClient
        QorusClient::initFast();
        return omqclient.getDatasource(name);
%endif
    }

    #! returns a @ref Qore::SQL::DatasourcePool "DatasourcePool" object for the given @ref dsconn "datasource" name
    /** @param name the name of the @ref dsconn "datasource"
        @param register_dependency if @ref True (the default) then if the connection is monitored as down, the calling interface will be temporarily disabled until the connection is up again

        @return a @ref Qore::SQL::DatasourcePool "DatasourcePool" object

        @throw DATASOURCE-ERROR unknown or system @ref dsconn "datasource"

        @note When used in the @ref clientintro "Qorus client", this method also will implicitly
        @ref client_initialization "initialize the client library"

        @see
        - getDatasourceDedicated()
    */
    static AbstractDatasource getDatasourcePool(string name, bool register_dependency = True) {
%ifdef QorusServer
        return Qorus.dsmanager.getPool(name, register_dependency);
%endif

%ifdef QorusClient
        QorusClient::initFast();
        return omqclient.getDatasourcePool(name);
%endif
    }

    #! returns a hash of information for the given @ref dsconn "datasource", if known, otherwise throws an exception
    /** @param name the name of the @ref dsconn "datasource"

        @return a hash of information for the given @ref dsconn "datasource", if known, otherwise throws an exception; the following keys are returned in the hash:
        - \c name (string): the name of the @ref dsconn "datasource" connection (corresponding to the argument \a name)
        - \c type (string): \c datasource constant
        - \c url (string): a connection string
        - \c url_hash (hash): parsed connection string and options
          - \c type (string): driver name
          - \c user (string): the username for the @ref dsconn "datasource" connection, if any
          - \c pass (string): the password for the @ref dsconn "datasource" connection, if any
          - \c charset (string): the DB-specific character encoding for the @ref dsconn "datasource" connection
          - \c db (string): The database name of the @ref dsconn "datasource" connection
          - \c options (hash): an optional hash of options for the DBI driver for this @ref dsconn "datasource" connection; also \c "min" and \c "max" for the DatasourcePool minimum and maximum options
        - \c locked (bool): a flag indicating if the @ref dsconn "datasource" is locked or not (the system datasource \c "omq" is locked)
        - \c up (bool): a flag indicating if monitoring has discovered if the @ref dsconn "datasource" is up or not
        - \c desc (string): a string description of the @ref dsconn "datasource"
        - \c monitor (bool): a flag indicating if the @ref dsconn "datasource" is monitored or not
        - \c status (string): \c "OK" if the @ref dsconn "datasource" is up or an error string if the datasource is down; set by monitoring
        - \c last_check (date/time): the date and time of the last monitoring check
        - \c shared_pool (string): a string giving the pool state (only present if a pool has been initialized on the @ref dsconn "datasource")
        - \c deps (list): a list of hashes giving interface objects that depend on the connection; each entry is a hash with the following keys:
          - \c type: \c "WORKFLOW", \c "SERVICE", or \c "JOB"
          - \c workflowid: for workflows, gives the workflow ID
          - \c serviceid: for services, gives the service ID
          - \c jobid: for jobs, gives the job ID
          - \c name: the name of the workflow, service, or job
          - \c version: the version of the workflow, service, or job
          - \c desc: a string description of the object

        @throw DATASOURCE-ERROR unknown @ref dsconn "datasource"

        @note This API is not available in the client library
    */
    static hash<auto> getDatasourceInfo(string name) {
%ifdef QorusServer
        return ("name": name) + Qorus.dsmanager.getInfo(name, {"with_passwords": True});
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Returns a new QorusSystemAPIHelper object corresponding to a defined @ref remoteconn "Qorus remote connection"
    /**
        @param name the name of the @ref remoteconn "remote connection"
        @param connect if @ref False an unconnected object will be returned, otherwise the object is already connected
        @param register_dependency if @ref True (the default) then if the connection is monitored as down, the calling interface will be temporarily disabled until the connection is up again

        @return a new QorusSystemAPIHelper object

        @throw GET-REMOTE-ERROR The given @ref remoteconn "connection" is not known

        @note When used in the @ref clientintro "Qorus client", this method also will implicitly
        @ref client_initialization "initialize the client library"
    */
    static QorusSystemAPIHelper getRemoteRpcConnection(string name, bool connect = True, bool register_dependency = True) {
%ifdef QorusServer
        return Qorus.remotemonitor.get(name, connect, register_dependency);
%endif

%ifdef QorusClient
        QorusClient::initFast();
        return omqclient.getRemote(name);
%endif
    }

    #! Returns a new QorusSystemRestHelper object corresponding to a defined @ref remoteconn "Qorus remote connection"
    /**
        @param name the name of the @ref remoteconn "remote connection"
        @param connect if @ref False an unconnected object will be returned, otherwise the object is already connected
        @param register_dependency if @ref True (the default) then if the connection is monitored as down, the calling interface will be temporarily disabled until the connection is up again

        @return a new QorusSystemRestHelper object

        @throw GET-REMOTE-ERROR The given @ref remoteconn "connection" is not known

        @note When used in the @ref clientintro "Qorus client", this method also will implicitly
        @ref client_initialization "initialize the client library"
    */
    static QorusSystemRestHelper getRemoteRestConnection(string name, bool connect = True, bool register_dependency = True) {
%ifdef QorusCore
        return Qorus.remotemonitor.getRest(name, connect, register_dependency);
%endif

%ifdef QorusClusterServer
        return Qorus.restconnections.get(name, connect, register_dependency);
%endif

%ifdef QorusClient
        QorusClient::initFast();
        return omqclient.getRemoteRest(name, connect);
%endif
    }

    #! raises a transient system alert from a workflow, service, or job
    /**
        @param alert the name of the alert (ex: \c "DATA-SIZE-EXCEEDED")
        @param reason the reason or verbose description of the alert
        @param info optional key / value details for the alert

        @note This API is not available in the client library
    */
    static raiseTransientAlert(string alert, string reason, *hash<auto> info) {
%ifdef QorusServer
        # the type of alert
        string type;
        # alert object ID
        softstring id;

        if (tld.isOrderContext()) {
            type = "WORKFLOW";
            id = tld.wfe.wf.workflowid;
            info.name = tld.wfe.wf.name;
        } else if (tld.isWorkflowContext()) {
            type = "WORKFLOW";
            id = tld.wf.workflowid;
            info.name = tld.wf.name;
        } else if (tld.isJobContext()) {
            type = "JOB";
            id = tld.job.jobid;
            info.name = tld.job.name;
        } else if (tld.isServiceContext()) {
            type = "SERVICE";
            id = tld.svc.serviceid;
            info.name = tld.svc.name;
        } else if (tld.cx) {
            ActionReason ar(tld.cx, reason, True);
            Qorus.alerts.raiseTransientAlert(ar, "API", "api", alert, info);
            return;
        } else {
            type = "QORUS";
            id = "qorus";
            info.name = "qorus";
        }

        CodeActionReason ar(reason);
        Qorus.alerts.raiseTransientAlert(ar, type, id, alert, info);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns a string giving the local system URL
    /** @param username an optional username for the new connection
        @param password an optional password for the new connection

        @return a string giving the local system URL

        @note the username and password arguments are only used if both are given
    */
    static string qorusGetLocalUrl(*string username, *string password) {
%ifdef QorusServer
        # return qorus-client.client-url (which is set automatically if not set in the options file)
        return exists username && exists password
            ? Qorus.options.getClientUrl(username, password)
            : Qorus.options.getClientUrl();
%endif
%ifdef QorusClient
        *list<auto> opt = qorus_get_system_options()."http-secure-server";
        *string qorus_core_address = try_get_qorus_core_address();
        return opt
            ? get_url_from_option("https", opt[0], username, password, qorus_core_address)
            : get_url_from_option("http", qorus_get_system_options()."http-server"[0], username, password,
                qorus_core_address);
%endif
    }

    #! Changes option values on a workflow, service, or job
    /** if called from workflow code, and the workflow has defined workflow options and an invalid option is passed to
        the method, an exception will be raised; however all other valid options in the hash will be set before the
        exception is raised

        @param hash a hash of option-value pairs

        @throw WORKFLOW-OPTION-ERROR invalid option name

        @note When used in the @ref clientintro "Qorus client", this method also will implicitly
        @ref client_initialization "initialize the client library"

        @see set_option()
    */
    static setOption(hash<auto> hash) {
%ifdef QorusCore
        if (tld.isWorkflowExecContext()) {
            Qorus.control.execHash.(tld.index).setOption(hash);
        }

        if (tld.isServiceContext()) {
            qorus_api_service_set_option(hash);
        }

        QDBG_ASSERT(exists tld.isJobContext());
        job_set_option(hash);
%endif

%ifdef QorusQwfServer
        Qorus.control.execHash.(tld.index).setOption(hash);
%endif

%ifdef QorusQsvcServer
        qorus_api_service_set_option(hash);
%endif

%ifdef QorusQjobServer
        job_set_option(hash);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Returns the value of the named workflow, service, or job option or options
    /** If the option is not set on the workflow, service, or job level (depending on the calling context) and it is a
        valid system option, then the value of the system option will be returned.

        @return the value requested directly if only one argument is passed, otherwise a hash of option keys and
        values; note that if called from a workflow and no arguments are passed to the method all workflow-level
        options are returned as a hash

        @note
        - When called from workflow code, invalid options do not cause an errors to be raised; the associated key
          values in the hash returned will be NOTHING
        - This API is not available in the client library

        @note When used in the @ref clientintro "Qorus client", this method also will implicitly
        @ref client_initialization "initialize the client library"

        @see
        - @ref OMQ::UserApi::Workflow::WorkflowApi::getOption() "WorkflowApi::getOption()"
        - @ref OMQ::UserApi::Workflow::WorkflowApi::getOptionArgs() "WorkflowApi::getOptionArgs()"
    */
    static auto getOption() {
%ifdef QorusCore
        if (tld.isWorkflowExecContext()) {
            return Qorus.control.execHash.(tld.index).getOption(argv);
        }

        if (tld.isServiceContext()) {
            return qorus_api_service_get_option_args(argv);
        }

        QDBG_ASSERT(exists tld.isJobContext());
        return cast<OMQ::LocalQorusJob>(tld.job).getOption(cast<*list<string>>(argv));
%endif

%ifdef QorusQwfServer
        return Qorus.control.execHash.(tld.index).getOption(argv);
%endif

%ifdef QorusQsvcServer
        return qorus_api_service_get_option_args(argv);
%endif

%ifdef QorusQjobServer
        return cast<OMQ::LocalQorusJob>(tld.job).getOption(cast<*list<string>>(argv));
%endif

%ifndef QorusServer
        delete argv;
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Returns the value of the named workflow, service, or job option or options
    /** If the option is not set on the workflow, service, or job level (depending on the calling context) and it is a
        valid system option, then the value of the system option will be returned.

        @param args the list of options to return

        @return the value requested directly if only one argument is passed, otherwise a hash of option keys and
        values; note that if called from a workflow and no arguments are passed to the method all workflow-level
        options are returned as a hash

        @note
        - When called from workflow code, invalid options do not cause an errors to be raised; the associated key
          values in the hash returned will be NOTHING
        - This API is not available in the client library

        @see
        - @ref OMQ::UserApi::Workflow::WorkflowApi::getOptionArgs() "WorkflowApi::getOptionArgs()"
        - @ref OMQ::UserApi::Workflow::WorkflowApi::getOption() "WorkflowApi::getOption()"
    */
    static auto getOptionArgs(*softlist<string> args) {
%ifdef QorusCore
        if (tld.isWorkflowExecContext()) {
            return Qorus.control.execHash.(tld.index).getOption(args);
        }

        if (tld.isServiceContext()) {
            return qorus_api_service_get_option_args(args);
        }

        QDBG_ASSERT(exists tld.isJobContext());
        return cast<OMQ::LocalQorusJob>(tld.job).getOption(args);
%endif

%ifdef QorusQwfServer
        return Qorus.control.execHash.(tld.index).getOption(args);
%endif

%ifdef QorusQsvcServer
        return qorus_api_service_get_option_args(args);
%endif

%ifdef QorusQjobServer
        return cast<OMQ::LocalQorusJob>(tld.job).getOption(args);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! block the given workflow order data instance
    /** @param wfiid the workflow order instance ID to block

        @return a hash with the following key:
        - \c workflow_status: the status of the workflow order

        An exception will be thrown if the status is @ref OMQ::StatInProgress

        @throw BLOCK-WORKFLOW-ERROR invalid status, foreign session id, missing original status, uncancel operation already in progress
    */
    static hash<auto> blockOrder(softint wfiid) {
%ifdef QorusCore
        return SM.blockWorkflowInstance(("user": "%SYS%"), wfiid.toString(), True);
%endif

%ifdef QorusClusterServer
        return SMC.blockWorkflowInstanceExtern(("user": "%SYS%"), wfiid.toString(), True);
%endif

%ifdef QorusClient
        return qrest.put("orders/" + wfiid + "/block");
%endif
    }

    #! unblocks the given workflow order data instance
    /** @param wfiid the workflow order instance ID to unblock
        @param tempdata optional @ref tempdata "workflow order tempdata" to pass to the workflow order (will only be
        used if the order is immediately cached as a part of the unblockOrder() call)
        @param orderkeys optional workflow order data keys

        @return a hash with the following key:
        - \c workflow_status: the status of the workflow order

        @throw BLOCK-WORKFLOW-ERROR invalid status, foreign session id, missing original status, uncancel operation already in progress
    */
    static hash<auto> unblockOrder(softint wfiid, *hash<auto> tempdata, *hash<auto> orderkeys) {
%ifdef QorusCore
        return SM.blockWorkflowInstance(("user": "%SYS%"), wfiid.toString(), False, tempdata, orderkeys);
%endif

%ifdef QorusClusterServer
        return SMC.blockWorkflowInstanceExtern(("user": "%SYS%"), wfiid.toString(), False, tempdata, orderkeys);
%endif

%ifdef QorusClient
        return qrest.put("orders/" + wfiid + "/unblock");
%endif
    }

    #! cancel the given workflow order data instance
    /** @param wfiid the workflow order instance ID to cancel

        @return a hash with the following key:
        - \c workflow_status: the status of the workflow order

        An exception will be thrown if the status is @ref OMQ::StatInProgress

        @throw CANCEL-WORKFLOW-ERROR invalid status, foreign session id, missing original status, uncancel operation already in progress
    */
    static hash<auto> cancelOrder(softint wfiid) {
%ifdef QorusCore
        return SM.cancelWorkflowInstance(("user": "%SYS%"), wfiid.toString(), True);
%endif

%ifdef QorusClusterServer
        return SMC.cancelWorkflowInstanceExtern(("user": "%SYS%"), wfiid.toString(), True);
%endif

%ifdef QorusClient
        return qrest.put("orders/" + wfiid + "/cancel");
%endif
    }

    #! uncancels the given workflow order data instance
    /** @param wfiid the workflow order instance ID to uncancel
        @param tempdata temporary data to provide when uncanceling the order

        @return a hash with the following key:
        - \c workflow_status: the status of the workflow order

        @throw CANCEL-WORKFLOW-ERROR invalid status, foreign session id, missing original status, uncancel operation
        already in progress
    */
    static hash<auto> uncancelOrder(softint wfiid, *hash<auto> tempdata) {
%ifdef QorusCore
        return SM.cancelWorkflowInstance(("user": "%SYS%"), wfiid.toString(), False, tempdata);
%endif

%ifdef QorusClusterServer
        return SMC.cancelWorkflowInstanceExtern(("user": "%SYS%"), wfiid.toString(), False, tempdata);
%endif

%ifdef QorusClient
        return qrest.put("orders/" + wfiid + "/uncancel");
%endif
    }

    #! updates the given workflow order instance's @ref dynamicdata "dynamic data hash" atomically
    /** The given hash is merged to the order's @ref dynamicdata "dynamic data hash"

        @param wfiid the workflow order instance ID to update
        @param new_data the hash data to merge with the given order's @ref dynamicdata "dynamic data hash"

        @throw UPDATE-WORKFLOW-ERROR foreign session id error

        @note This API is not available in the client library

        @see updateDynamicOrderDataPath()

        @since Qorus 5.1.10
    */
    static updateDynamicOrderData(softint wfiid, hash<auto> new_data) {
%ifdef QorusCore
        SM.updateDynamicData({"user": "%SYS%"}, wfiid, new_data);
%endif

%ifdef QorusClusterServer
        SMC.updateDynamicData({"user": "%SYS%"}, wfiid, new_data);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! updates the given workflow order instance's @ref dynamicdata "dynamic data hash" atomically
    /** The given value is written to the path provided in the workflow order instance's
        @ref dynamicdata "dynamic data hash"

        @param wfiid the workflow order instance ID to update
        @param path the dotted path to the value to update
        @param value the value to update in the location provided by \a path

        @throw UPDATE-WORKFLOW-ERROR foreign session id error

        @note This API is not available in the client library

        @see updateDynamicOrderData()

        @since Qorus 5.1.10
    */
    static updateDynamicOrderDataPath(softint wfiid, string path, auto value) {
%ifdef QorusCore
        SM.updateDynamicDataPath({"user": "%SYS%"}, wfiid, path, value);
%endif

%ifdef QorusClusterServer
        SMC.updateDynamicDataPath({"user": "%SYS%"}, wfiid, path, value);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns a hash for the current user context
    /** @par Example:
        @code{.py}
*hash<auto> h = UserApi::getUserContextInfo();
        @endcode

        @return a hash describing the current user context; hash keys are as in the following table
        <b>UserApi::getUserContextInfo() Return Value When Called from a Service</b>
        |!Key|!Value
        |<b><tt>type</tt></b>|\c "service"
        |<b><tt>servicetype</tt></b>|the type of service (\c "user" or \c "system")
        |<b><tt>name</tt></b>|the name of the service
        |<b><tt>version</tt></b>|the version of the service
        |<b><tt>id</tt></b>|the service id
        \n
        <b>UserApi::getUserContextInfo() Return Value When Called from a Job</b>
        |!Key|!Value
        |<b><tt>type</tt></b>|\c "job"
        |<b><tt>name</tt></b>|the name of the job
        |<b><tt>version</tt></b>|the version of the job
        |<b><tt>id</tt></b>|the job id
        |<b><tt>job_instanceid</tt></b>|the job_instanceid of the current job instance
        \n
        <b>UserApi::getUserContextInfo() Return Value When Called from a Workflow</b>
        |!Key|!Value
        |<b><tt>type</tt></b>|\c "workflow"
        |<b><tt>name</tt></b>|the name of the workflow
        |<b><tt>version</tt></b>|the version of the workflow
        |<b><tt>id</tt></b>|the workflow id
        |<b><tt>workflow_instanceid</tt></b>|the workflow_instanceid of the current workflow instance (if available)
        |<b><tt>stepname</tt></b>|the name of the current step (if available)
        |<b><tt>stepversion</tt></b>|the version of the current step (if available)
        |<b><tt>stepid</tt></b>|the id of the current step (if available)
        |<b><tt>ind</tt></b>|the name of the current step index (if available)
        |<b><tt>execid</tt></b>|the execution ID of the current workflow execution instance (if available)
        \n
        In addition, when called from a @ref finite_state_machines "finite state machine state", the contextual keys
        as above are available, plus the followng.
        \n
        <b>UserApi::getUserContextInfo() Return Value When Called from a Workflow</b>
        |!Key|!Value
        |<b><tt>input</tt></b>|any input data for the current @ref finite_state_machines "finite state machine state"
    */
    static *hash<auto> getUserContextInfo() {
%ifdef QorusCore
        if (tld && tld.isServiceContext()) {
            AbstractQorusCoreService svc = tld.svc;
            return {
                "type": "service",
                "servicetype": svc.type,
                "name": svc.name,
                "version": svc.version,
                "id": svc.serviceid,
            } + (exists tld.fsm_input_data ? {"input": tld.fsm_input_data} : NOTHING);
        }
        if (tld && tld.isJobContext()) {
            hash<auto> jh = tld.job.getInfo();
            return {
                "type": "job",
                "name": jh.name,
                "version": jh.version,
                "id": jh.jobid,
                "job_instanceid": jh.job_instanceid,
            } + (exists tld.fsm_input_data ? {"input": tld.fsm_input_data} : NOTHING);
        }
%endif

%ifdef QorusHasWfApi
        if (tld && tld.isOrderContext()) {
            WFEntry wfe = tld.wfe;
            hash<auto> rv = {
                "type": "workflow",
                "name": wfe.wf.name,
                "version": wfe.wf.version,
                "id": wfe.wf.workflowid,
                "workflow_instanceid": wfe.workflow_instanceid ? wfe.workflow_instanceid.toInt() : NOTHING,
            };
            if (tld.stepID) {
                hash<auto> sih = wfe.wf.stepinfo.(tld.stepID);
                rv += {
                    "stepname": sih.name,
                    "stepversion": sih.version,
                    "stepid": tld.stepID,
                    "ind": tld.ind,
                };
            }
            if (int(tld.index)) {
                rv.execid = tld.index.toInt();
            }
            if (exists tld.fsm_input_data) {
                rv.input = tld.fsm_input_data;
            }

            return rv;
        }

        if (tld && tld.isWorkflowContext()) {
            hash<auto> rv = {
                "type": "workflow",
                "name": tld.wf.name,
                "version": tld.wf.version,
                "id": tld.wf.workflowid,
            };
            if (tld.stepID) {
                hash<auto> sih = tld.wf.stepinfo.(tld.stepID);
                rv += {
                    "stepname": sih.name,
                    "stepversion": sih.version,
                    "stepid": tld.stepID,
                };
            }

            if (int(tld.index)) {
                rv.execid = tld.index.toInt();
            }
            if (exists tld.fsm_input_data) {
                rv.input = tld.fsm_input_data;
            }
            return rv;
        }
%endif

%ifdef QorusQsvcServer
        return {
            "type": "service",
            "servicetype": Qorus.svctype,
            "name": Qorus.interfaceName,
            "version": Qorus.interfaceVersion,
            "id": Qorus.interfaceId,
        } + (exists tld.fsm_input_data ? {"input": tld.fsm_input_data} : NOTHING);
%endif

%ifdef QorusQjobServer
        return {
            "type": "job",
            "name": Qorus.interfaceName,
            "version": Qorus.interfaceVersion,
            "id": Qorus.interfaceId,
            "job_instanceid": tld.job ? tld.job.getInfo().job_instanceid : NOTHING,
        } + (exists tld.fsm_input_data ? {"input": tld.fsm_input_data} : NOTHING);
%endif

%ifdef QorusClient
        return {
            "type": "client",
            "name": "QorusClient",
            "version": OMQ::version,
        "id": 0,
        };
%endif
    }

    #! returns config item value in the current user context
    /** @param cfg_item name of the config item
        @param local_context the caller can supply its "local" context for template variables (plus user context info is
        added - see @ref UserApi::getUserContextInfo() method)
        @param expand_complex_values if @ref True then lists and hashes will have their values expanded recursively

        @throw CONFIG-ITEM-ERROR thrown if the configuration item is not valid in the current context

        @return value for the given config item in the current CONTEXT

        @note
        - The value is always substituted with
          @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure
          and escape any \c "$" characters with a backslash (\c "\") to avoid template substitution
        - In a @ref data_pipeline_processors "pipeline processor" or a
          @ref fsm_data_processing "finite state machine connector", this method will return config item information
          from the @ref data_pipelines "data pipeline" or @ref finite_state_machines "finite state machine" only;
          config item information from the interface is not accessible; use @ref getInterfaceConfigItemHash() to get
          configuration information from the interface from within a @ref data_pipelines "data pipeline" or
          @ref finite_state_machines "finite state machine"

        @see getInterfaceConfigItemValue()

        @since
        - Qorus 4.0.3
        - Qorus 4.1.1 added the \a expand_complex_values parameter
    */
    static auto getConfigItemValue(string cfg_item, *hash<auto> local_context, bool expand_complex_values = True) {
        #QDBG_LOG("UserApi::getConfigItemValue(%y) tld.fsm_ctx: %y td{%y}: %y", cfg_item, tld.fsm_ctx, ProcessorKeyId, get_thread_data(ProcessorKeyId));
%ifdef QorusServer
        if (tld.fsm_ctx) {
            return FsmInfo::getConfigItemValue(tld.fsm_ctx, cfg_item, local_context, expand_complex_values);
        } else if (*hash<auto> processor_info = get_thread_data(ProcessorKeyId)) {
            return Qorus.qmm.getPipelineConfigItemValue(processor_info.name, processor_info.id + ":" + cfg_item,
                local_context, expand_complex_values);
        }
%endif

        return UserApi::getInterfaceConfigItemValue(cfg_item, local_context, expand_complex_values);
    }

    #! returns config item value in the current interface context
    /** @param cfg_item name of the config item
        @param local_context the caller can supply its "local" context for template variables (plus user context info is
        added - see @ref UserApi::getUserContextInfo() method)
        @param expand_complex_values if @ref True then lists and hashes will have their values expanded recursively

        @throw CONFIG-ITEM-ERROR thrown if the configuration item is not valid in the current context

        @return value for the given config item in the current CONTEXT

        @note
        - The value is always substituted with
          @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure and escape any \c "$"
          characters with a backslash (\c "\") to avoid template substitution
        - In a @ref data_pipeline_processors "pipeline processor" or a
          @ref fsm_data_processing "finite state machine connector", this function will return config item information
          from the interface; config item information from the @ref data_pipelines "data pipeline" and
          @ref finite_state_machines "finite state machine" is not accessible; use @ref getConfigItemValue() to get
          configuration information from @ref data_pipelines "data pipelines" and
          @ref finite_state_machines "finite state machines"

        @see getConfigItemValue()

        @since
        - Qorus 5.0
    */
    static auto getInterfaceConfigItemValue(string cfg_item, *hash<auto> local_context, bool expand_complex_values = True) {
        auto value;

        #QDBG_LOG("UserApi::getInterfaceConfigItemValue() %y lc: %y ecv: %y tld: %y", cfg_item, local_context, expand_complex_values, tld);

%ifdef QorusHasWfApi
        if (tld.isWorkflowExecContext()) {
            # this means we're in a workflow
            value = WorkflowApi::getConfigItemValue(cfg_item, local_context, expand_complex_values);
        }
%endif

%ifdef QorusHasSvcApi
        if (tld.isServiceContext()) {
            value = ServiceApi::getConfigItemValue(cfg_item, local_context, expand_complex_values);
        }
%endif

%ifdef QorusHasJobApi
        if (tld.isJobContext()) {
            value = JobApi::getConfigItemValue(cfg_item, local_context, expand_complex_values);
        }
%endif

        return value;
    }

    #! returns a hash of all configuration items for the current interface
    /** @par Example:
        @code{.py}
hash<auto> config = UserApi::getConfigItemHash();
        @endcode

        @param local_context the caller can supply its "local" context for template variables (plus user context info
        is added - see @ref UserApi::getUserContextInfo() method)

        @return a hash of all configuration items for the current interface; keys are config item names; values are
        config item values. If there are no config items for the current interface, then an empty hash is returned.

        @note
        - If there are local configuration item values and values on global level, the
          local values will take precedence over the global values
        - The value is always substituted with
          @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure
          and escape any \c "$" characters with a backslash (\c "\") to avoid template substitution
        - In a @ref data_pipeline_processors "pipeline processor" or a
          @ref fsm_data_processing "finite state machine connector", this method will return config item information
          from the @ref data_pipelines "data pipeline" or @ref finite_state_machines "finite state machine" only;
          config item information from the interface is not accessible; use @ref getInterfaceConfigItemHash() to get
          configuration information from the interface from within a @ref data_pipelines "data pipeline" or
          @ref finite_state_machines "finite state machine"

        @see getInterfaceConfigItemHash()

        @since Qorus 4.0.3
    */
    static hash<auto> getConfigItemHash(*hash<auto> local_context) {
%ifdef QorusServer
        if (tld.fsm_ctx) {
            return FsmInfo::getConfigItemHash(tld.fsm_ctx, local_context);
        } else if (*hash<auto> processor_info = get_thread_data(ProcessorKeyId)) {
            return Qorus.qmm.getPipelineConfigItemHash(processor_info.name, processor_info.id, local_context);
        }
%endif

        return UserApi::getInterfaceConfigItemHash(local_context);
    }

    #! Returns a hash of all configuration items for the current context as a combination of local and global configuration items
    /**
        @par Example:
        @code{.py}
hash<auto> config = UserApi::getInterfaceConfigItemHash();
        @endcode

        @param local_context the caller can supply its "local" context for template variables (plus user context info is
        added - see @ref UserApi::getUserContextInfo() method)

        @return a hash of all configuration items for the current context; keys are config item names; values are
        config item values. If there are no config items for the current context, then an empty hash is returned.

        @note
        - The value is always substituted with
          @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure
          and escape any \c "$" characters with a backslash (\c "\") to avoid template substitution
        - In a @ref data_pipeline_processors "pipeline processor" or a
          @ref fsm_data_processing "finite state machine connector", this method will return config item information
          from the @ref data_pipelines "data pipeline" or @ref finite_state_machines "finite state machine" only;
          config item information from the interface is not accessible; use @ref getInterfaceConfigItemHash() to get
          configuration information from the interface from within a @ref data_pipelines "data pipeline" or
          @ref finite_state_machines "finite state machine"
        - This API is not available in the client library

        @see getConfigItemHash()

        @since Qorus 5.0
    */
    static hash<auto> getInterfaceConfigItemHash(*hash<auto> local_context) {
%ifdef QorusHasWfApi
        if (tld.isRealOrderContext()) {
            # this means we're in a workflow
            return WFEntry::getConfigItemHash(local_context);
        }
%endif

%ifdef QorusHasSvcApi
        if (tld.isRealServiceContext()) {
            return cast<OMQ::LocalQorusService>(tld.svc).getConfigItemHash(local_context);
        }
%endif

%ifdef QorusHasJobApi
        if (tld.isRealJobContext()) {
            return cast<OMQ::LocalQorusJob>(tld.job).getConfigItemHash(local_context);
        }
%endif

%ifdef QorusClient
           throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%else
        return {};
%endif
    }

    #! returns the value of the given configuration item on global level; throws an exception if there is no value on global level for the configuration item
    /** @param item the name of the configuration item to retrieve the value
        @param local_context the caller can supply its "local" context for template variables (plus user context info is
        added - see @ref UserApi::getUserContextInfo() method)
        @param expand_complex_values if @ref True then lists and hashes will have their values expanded recursively

        @return the value of the given configuration item on global level

        @throw CONFIG-ITEM-ERROR thrown if the configuration item is not valid

        @note
        - The value is always substituted with
          @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure and escape any \c "$"
          characters with a backslash (\c "\") to avoid template substitution
        - This API is not available in the client library

        @since
        - Qorus 4.0.3
        - Qorus 4.1.1 added the \a expand_complex_values parameter

        @see getGlobalConfigItemValueWithDefault()
    */
    static auto getGlobalConfigItemValue(string item, *hash<auto> local_context, bool expand_complex_values = True) {
%ifdef QorusServer
        bool is_value_set;
        auto value = UserApi::expandTemplatedValue(Qorus.qmm.getConfigItemValue("global", item, \is_value_set),
            local_context, expand_complex_values);
        if (!is_value_set) {
            throw "CONFIG-ITEM-ERROR", sprintf("value on global level for config item %y does not exist", item);
        }
        return value;
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns the value of the given configuration item on global level; throws an exception if there is no value on global level for the configuration item
    /** @param item the name of the configuration item to retrieve the value
        @param default_value the value to be returned if the value is not set
        @param local_context the caller can supply its "local" context for template variables (plus user context info is
        added - see @ref UserApi::getUserContextInfo() method)
        @param expand_complex_values if @ref True then lists and hashes will have their values expanded recursively

        @return the value of the given global configuration item or \a default_value, if no value is set at the
        global level for the given configuration item

        @note
        - The value is always substituted with
          @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"
        - If the config item is not set, \a default_value is returned after substitutions with
          @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"
        - Make sure and escape any \c "$" characters with a backslash (\c "\") to avoid template substitution
        - This API is not available in the client library

        @since
        - Qorus 4.0.3
        - Qorus 4.1.1 added the \a expand_complex_values parameter

        @see getGlobalConfigItemValue()
    */
    static auto getGlobalConfigItemValueWithDefault(string item, auto default_value, *hash<auto> local_context, bool expand_complex_values = True) {
%ifdef QorusServer
        bool is_value_set;
        auto value = UserApi::expandTemplatedValue(Qorus.qmm.getConfigItemValue("global", item, \is_value_set),
            local_context, expand_complex_values);
        return is_value_set
            ? value
            : UserApi::expandTemplatedValue(default_value, local_context, expand_complex_values);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns the data provider given by a path string
    /** @par Example:
        @code{.py}
AbstractDataProvider d = UserApi::getDataProvider("connection/rest-billing-1/accounts/POST");
        @endcode

        @param path the path to the dataprovider; the first element must be one of the following:
        - \c factory: for data provider factory objects (ex: \c "factory/cvswrite{path=/tmp/file.csv}")
        - \c connection: for @ref userconn "user connections"
        - \c datasource: for @ref dsconn "datasources"
        - \c remote: for Qorus @ref remoteconn "remote connections" \n
        The second element should be the name of the connection, and further elements should be the path to the data
        provider.

        @throw DATA-PROVIDER-ERROR the given data provider path is unknown or invalid

        @note This API is not available in the client library

        @since Qorus 4.1
    */
    static AbstractDataProvider getDataProvider(string path) {
        list<string> path_list = path.split("/");
        string type;
        if (!path_list || !DataProviderRootValues{type = shift path_list}) {
            throw "DATA-PROVIDER-ERROR", sprintf("data provider path %y does not start with one of %y", path,
                keys DataProviderRootValues);
        }

        on_error rethrow "DATA-PROVIDER-ERROR", sprintf("%y: %s: %s", path, $1.err, $1.desc);
        AbstractDataProvider provider = _priv_get_data_provider_from_path(path, \path_list, type,
            "DATA-PROVIDER-ERROR");
        map provider = provider.getChildProviderEx($1), path_list;
        return provider;
    }

    #! returns the data provider given by a path string
    /** @par Example:
        @code{.py}
AbstractDataProvider d = UserApi::getDataProvider("connection", "rest-billing-1", "/accounts/POST");
        @endcode

        @param type must be one of the following:
        - \c factory: for data provider factory objects
        - \c connection: for @ref userconn "user connections"
        - \c datasource: for @ref dsconn "datasources"
        - \c remote: for Qorus @ref remoteconn "remote connections"
        @param name the name of the \a type
        @param path an optional data provider path to the data provider
        @param opts any optional data provider factory creation options; invalid options are ignored; these options,
        if present, are also processed with @ref expandTemplatedValue() using \a ctxt as the local context value
        @param ctxt any local context to use when processing \a opts with @ref expandTemplatedValue()

        @throw DATA-PROVIDER-ERROR a data provider could not be created from the arguments

        @since Qorus 6.0
    */
    static AbstractDataProvider getDataProvider(string type, string name, *string path, *hash<auto> opts,
            *hash<auto> ctxt) {
        path =~ s/^\///;
        *list<string> path_list;
        if (path) {
            path_list = path.split("/");
        }

        on_error rethrow "DATA-PROVIDER-ERROR", sprintf("type: %y: name: %y path: %y: %s: %s", type, name, path,
            $1.err, $1.desc);

        AbstractDataProvider prov;
        if (type == "factory") {
            AbstractDataProviderFactory factory = DataProvider::getFactoryEx(name);
            hash<DataProviderFactoryInfo> info = factory.getInfo();
            *hash<auto> create_opts = remove opts{keys info.provider_info.constructor_options};
            create_opts = _priv_get_provider_constructor_options(name, create_opts,
                info.provider_info.constructor_options, ctxt);
            prov = factory.create(create_opts);
        } else {
            prov = _priv_get_connection_provider(type).getDataProvider(name);
        }
        map prov = prov.getChildProviderEx($1), path_list;
        return prov;
    }

    #! Returns a data provider type from a direct type path
    /** @param type_path the direct path to the type as would be used with
        @ref DataProvider::DataProvider::getTypeEx() "DataProvider::getTypeEx()"

        @return the data provider type corresponding to the type

        @throw DATA-TYPE-ERROR the given type is unknown

        @see getTypeFromPath()

        @since Qorus 4.1.2
    */
    static AbstractDataProviderType getQorusType(string type_path) {
%ifndef QorusFakeApi
        try {
            return DataProvider::getTypeEx(type_path);
        } catch (hash<ExceptionInfo> ex) {
%ifdef QorusClusterServer
            # we need to do a remote cache lookup if the direct local type lookup fails
            if (ex.err == "PROVIDER-ERROR") {
                try {
                    # this will load the local cache as well, if the type is defined as a user type
                    AbstractDataProviderType type = Qorus.qmm.lookupType(type_path);
                    return type;
                } catch (hash<ExceptionInfo> ex1) {
                }
            }
%endif
            # if no remote lookup succeeded, rethrow the exception
            rethrow "DATA-TYPE-ERROR", ex.desc;
        }
%endif
    }

    #! returns a data provider type identified by a path string
    /** @par Example:
        @code{.py}
AbstractDataProviderType type = UserApi::getTypeFromPath("type/qore/ftp/event");
        @endcode

        @param path the path to the type (which will be normalized; any leading \c "/" character(s) will be stripped);
        the first element must be one of the following:
        - \c type: indicates that the rest of the path identifies a registered data provider type
        - \c factory: indicates that the rest of the path identifies a data provider porovided from a factory
          (ex: \c "factory/csvwrite{path=/tmp/file.csv}"
        - \c connection: indicates that the following path element identifies a @ref userconn "user connection"
        - \c datasource: indicates that the following path element identifies a @ref dsconn "datasource"
        - \c remote: indicates that the following path element identifies a Qorus @ref remoteconn "remote connection" \n
        For type paths in data providers (i.e. \c connection, \c datasource, and \c remote), the path element after
        the provider must be one of the following:
        - \c request: for the request type
        - \c response: for the response type
        - \c error: for the error response type, in which case the next path element provides the error code
        - \c record: for the record type

        @throw DATA-TYPE-ERROR the given type is unknown

        @see getQorusType()

        @since Qorus 4.1.1
    */
    static AbstractDataProviderType getTypeFromPath(string path) {
%ifndef QorusFakeApi
        path = QorusDataProviderTypeHelper::normalizeTypePath(path)[1..];
        list<string> path_list = path.split("/");
        string typename;
        if (!path_list || !DataTypeRootValues{typename = shift path_list}) {
            throw "DATA-TYPE-ERROR", sprintf("data type path %y does not start with one of %y", path,
                keys DataTypeRootValues);
        }
        AbstractDataProviderType type;
        try {
            if (typename == "type") {
                string type_path = path_list.join("/");
                return UserApi::getQorusType(type_path);
            }
            AbstractDataProvider provider = _priv_get_data_provider_from_path(path, \path_list, typename,
                "DATA-TYPE-ERROR");

            string elem;
            while (path_list) {
                elem = shift path_list;
                *AbstractDataProvider next_provider = provider.getChildProvider(elem);
                if (!next_provider) {
                    if (!DataProviderPathTypeValues{elem}) {
                        throw "DATA-TYPE-ERROR", sprintf("data type path %y element %y after identifying "
                            "provider %y is invalid; expecting one of %y to identify the data provider record "
                            "type", path, elem, provider.getName(), keys DataProviderPathTypeValues);
                    }
                    break;
                }
                provider = next_provider;
                remove elem;
            }
            if (!exists elem) {
                throw "DATA-TYPE-ERROR", sprintf("data type path %y identifying provider %y missing trailing record "
                    "type identifier; expecting one of %y to identify the data provider record type", path,
                    provider.getName(), keys DataProviderPathTypeValues);
            }
            switch (elem) {
                case "request": {
                    *AbstractDataProviderType new_type = provider.getRequestType();
                    if (!new_type) {
                        throw "DATA-TYPE-ERROR", sprintf("data type path %y, provider %y has no request type",
                            path, provider.getName());
                    }
                    type = new_type;
                    break;
                }

                case "response": {
                    *AbstractDataProviderType new_type = provider.getResponseType();
                    if (!new_type) {
                        throw "DATA-TYPE-ERROR", sprintf("data type path %y, provider %y has no response type",
                            path, provider.getName());
                    }
                    type = new_type;
                    break;
                }

                case "record": {
                    *hash<string, AbstractDataField> fields = provider.getRecordType();
                    if (!fields) {
                        throw "DATA-TYPE-ERROR", sprintf("data type path %y, provider %y has no record type",
                            path, provider.getName());
                    }
                    if (path_list) {
                        elem = shift path_list;
                        *AbstractDataField field = fields{elem};
                        if (!field) {
                            throw "DATA-TYPE-ERROR", sprintf("data type path %y, provider %y record has no field "
                                "%y; known fields: %y", path, provider.getName(), elem, keys fields);
                        }
                        type = field.getType();
                    } else {
                        HashDataType new_type(elem);
                        map new_type.addField($1), fields.iterator();
                        type = new_type;
                    }
                    break;
                }

                case "error": {
                    if (!path_list) {
                        throw "DATA-TYPE-ERROR", sprintf("data type path %y, provider %y missing error response "
                            "code path element for error type; known error response types: %y", path, provider.getName(),
                            keys provider.getErrorResponseTypes());
                    }
                    break;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "DATA-TYPE-ERROR") {
                rethrow;
            }
            rethrow "DATA-TYPE-ERROR", sprintf("%y: %s: %s", path, ex.err, ex.desc), ex.arg;
        }

        # resolve type from fields if there is any path left to process
        while (path_list) {
            string elem = shift path_list;
            *AbstractDataProviderType new_type = type.getFieldType(elem);
            if (!new_type) {
                throw "DATA-TYPE-ERROR", sprintf("%y: field %y is unknown in type %y; known fields: %y", path,
                    elem, type.getName(), keys type.getFields());
            }
            type = new_type;
        }
        return type;
%endif
    }

    #! returns the given mapper if registered for the current interface
    /** @par Example:
        @code{.py}
Mapper m = UserApi::getMapper("my_mapper");
        @endcode

        @param name the name of the mapper
        @param rtopts any runtime options accepted by the mapper

        @throw MAPPER-ERROR the given mapper is unknown or not registered to the current interface

        @note This API is not available in the client library

        @see
        - @ref mappers
        - @ref mapper-devel
    */
    static Mapper::Mapper getMapper(string name, *hash<auto> rtopts) {
%ifdef QorusCore
        if (tld.isServiceContext())
            return tld.svc.getMapper(name, rtopts);

        if (tld.isJobContext())
            return tld.job.getMapper(name, rtopts);

        if (tld.isWorkflowContext())
            return tld.wf.getMapper(name, rtopts);

        throw "MAPPER-ERROR", sprintf("no interface context for get_mapper(%y) call", name);
%endif

%ifdef QorusQwfServer
        return tld.wf.getMapper(name, rtopts);
%endif

%ifdef QorusQsvcServer
        return tld.svc.getMapper(name, rtopts);
%endif

%ifdef QorusQjobServer
        return tld.job.getMapper(name, rtopts);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns an iterator for the named mapper using the iterator argument for input
    /** @par Example:
        @code{.py}
AbstractIterator i = UserApi::getMapperIterator("my_mapper", input);
        @endcode

        @param name the name of the mapper
        @param input an iterator providing the input for the mapper for the iterator returned; the input iterator must iterate hashes (as returned by the @ref Qore::AbstractIterator::getValue() method)
        @param rtopts any runtime options accepted by the mapper

        @return the AbstractIterator object corresponding to the arguments; the @ref Qore::AbstractIterator::getValue() method will return a hash of the current input mapped to the output data structure

        @throw MAPPER-ERROR unknown mapper or not registered to the current interface

        @note This API is not available in the client library

        @see
        - @ref mappers
        - @ref mapper-devel
    */
    static Qore::AbstractIterator getMapperIterator(string name, Qore::AbstractIterator input, *hash<auto> rtopts) {
%ifdef QorusCore
        if (tld.isServiceContext())
            return tld.svc.getMapperIterator(name, input, rtopts);

        if (tld.isJobContext())
            return tld.job.getMapperIterator(name, input, rtopts);

        if (tld.isWorkflowContext())
            return tld.wf.getMapperIterator(name, input, rtopts);

        throw "MAPPER-ERROR", sprintf("no interface context for get_mapper_iterator(%y) call", name);
%endif

%ifdef QorusQwfServer
        return tld.wf.getMapperIterator(name, input, rtopts);
%endif

%ifdef QorusQsvcServer
        return tld.svc.getMapperIterator(name, input, rtopts);
%endif

%ifdef QorusQjobServer
        return tld.job.getMapperIterator(name, input, rtopts);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! posts a workflow synchronization event given the event type name and the unique event key
    /** @par Example:
        @code{.py}
UserApi::postSyncEvent(type, key);
        @endcode

        @param eventtype the event type name
        @param eventkey the event key in the event type queue to post

        @return @ref True if the event was posted for the first time, @ref False if the event had already been posted beforehand

        @throw UNKNOWN-EVENT unknown event type name

        @see
        - @ref eventsteps
        - @ref rest_api_PUT_latest_sync-events__type___key__post
    */
    static bool postSyncEvent(string eventtype, string eventkey) {
%ifdef QorusServer
        # lookup event type id
        *hash<auto> info = Qorus.qmm.rLookupEvent(eventtype);
        if (!info) {
            throw "UNKOWN-EVENT", sprintf("cannot post event %y on unknown event type %y", eventkey, eventtype);
        }
%endif

%ifdef QorusCore
        return !SM.postEvent(info.workflow_event_typeid, eventkey);
%endif

%ifdef QorusClusterServer
        return !SMC.postEvent(info.workflow_event_typeid, eventkey);
%endif

%ifdef QorusClient
        return qrest.put("sync-events/" + eventtype + "/" + eventkey + "/post");
%endif
    }

    #! returns a hash of all system properties in all domains
    /** @par Example:
        @code{.py}
hash<auto> h = UserApi::propGet();
        @endcode

        @return a hash of all system properties in all domains; the top-level keys are domain keys which have as values hashes with all key-value pairs set in the domain

        @see
        - propUpdate()
    */
    static hash<auto> propGet() {
%ifdef QorusServer
        return Qorus.props.get();
%endif

%ifdef QorusClient
        return prop_get();
%endif
    }

    #! returns a hash of all key-value pairs in the given domain or @ref nothing if the system property domain does not exist
    /** @par Example:
        @code{.py}
*hash<auto> h = UserApi::propGet(domain);
        @endcode

        @return a hash of all key-value pairs in the given domain or @ref nothing if the system property domain does not exist

        @see
        - propUpdate()
    */
    static *hash<auto> propGet(string domain) {
%ifdef QorusServer
        return Qorus.props.get(domain);
%endif

%ifdef QorusClient
        return prop_get(domain);
%endif
    }

    #! returns the value of the given system property key in the given domain or @ref nothing if the system property does not exist
    /** @par Example:
        @code{.py}
auto val = UserApi::propGet(domain, key);
        @endcode

        @return the value of the given system property key in the given domain

        @see
        - prop_get()
        - propUpdate()
    */
    static auto propGet(string domain, string key) {
%ifdef QorusServer
        return Qorus.props.get(domain, key);
%endif

%ifdef QorusClient
        return prop_get(domain, key);
%endif
    }

    #! changes (inserts, updates, or deletes) the value of a single system property
    /** @par Example:
        @code{.py}
UserApi::propUpdate(domain, key, val);
        @endcode

        Updates the value of the property in the domain passed.  If the property does not exist, then it is created.
        If the value is \c NOTHING (i.e. if no value is supplied) then the property will be deleted.
        Changes are committed to the database and the internal cache before the method call returns.
        No changes may be made in the system \c "omq" domain.

        @param domain the domain of the property to set
        @param key the key to set
        @param value the value to set in the property domain; if no value is passed here, and the property exists, it will be deleted

        @return the action code, \c "INSERT", \c "UPDATE", \c "DELETE", \c "IGNORED" (if a non-existent key should be deleted)

        @throw PARAMETER-ERROR if the domain or key arguments are empty strings
        @throw PROP-ERROR serialized value exceeds 240 characters (column limit)
        @throw UPDATE-ERROR changes attempted in the \c "omq" domain

        @see
        - prop_update()
        - propGet()
    */
    static string propUpdate(string domain, softstring key, auto value) {
%ifdef QorusServer
        return Qorus.props.update(domain, key, value);
%endif

%ifdef QorusClient
        return qrest.put("system/props/" + domain + "?action=set", {"key": key, "args": value});
%endif
    }

    #! changes (inserts, updates, or deletes) the value of one or more system properties according to a hash argument
    /** @par Example:
        @code{.py}
UserApi::propUpdate(h);
        @endcode

        Updates the values of the properties in the domain corresponding to the top level keys of the hash passed and the keys corresponding to the second-level keys in the hash according to the rules for prop_update(domain, key, value) method.

        The method returns a hash with \c "INSERT", \c "UPDATE", \c "DELETE" and \c "IGNORED" keys having integer values corresponding to the number of operations performed (deleting a non-existent key or domain causes a \c "IGNORED" value to be returned).

        All changes are made atomically in a single transaction.

        @param h in the format \c domain.key.value for updating, inserting, or deleting

        @return a hash of action codes as keys, with the values of each key being the number of actions of that type executed

        @throw PROP-ERROR serialized value exceeds 240 characters (column limit)
        @throw UPDATE-ERROR changes attempted in the \c "omq" domain

        @see
        - prop_update()
        - propGet()
    */
    static hash<auto> propUpdate(hash<auto> h) {
%ifdef QorusServer
        return Qorus.props.updateMany(h);
%endif

%ifdef QorusClient
    return qrest.put("system/props?action=updateMany", {"arg": h});
%endif
    }

    #! returns the next sequence value for the given datasource and sequence
    /** @par Example:
        @code{.py}
        int val = UserApi::getNextSequenceValue(ds, seqnem);
        @endcode

        @param ds the datasource to retrieve the sequence from
        @param name the name of the sequence

        @return the next value of the sequence

        @note
    */
    static softint getNextSequenceValue(AbstractDatasource ds, string name) {
        try {
            switch (ds.getDriverRealName()) {
                case "pgsql":
                case /^postgres/i:
                    return ds.selectRow("select nextval(%v);", name).nextval;
                case /^oracle/i:
                    return ds.selectRow("select %s.nextval from dual", name).nextval;
                case "freetds":
                    return ds.selectRow("select next value for %v as nextval", name).nextval;
                case /^firebird/i:
                    return ds.selectRow("select next value for %s as nextval from rdb$database", name).nextval;
            }
        } catch (hash<ExceptionInfo> ex) {
            # enrich exception with sequence name
            rethrow ex.err, sprintf("%y: %s", name, ex.desc), ex.arg;
        }
        throw "UNSUPPORTED-DRIVER", sprintf("do not know how to get the next sequence value for sequence %y with "
        "driver %y", name, ds.getDriverName());
    }

    #! returns the next sequence value for the given datasource and sequence
    /** @par Example:
        @code{.py}
        int val = UserApi::getNextSequenceValue(ds, seqnem);
        @endcode

        @param ds the @ref dsconn "datasource name" to retrieve the sequence from; a pool corresponding to the
        datasource will be used to retrieve the sequence
        @param name the name of the sequence

        @return the next value of the sequence
    */
    static softint getNextSequenceValue(string ds, string name) {
        return UserApi::getNextSequenceValue(UserApi::getDatasourcePool(ds), name);
    }

    #! returns a string giving the default serialization of the given data structure for storage in Qorus
    /** the default serialization is currently YAML of Qore intermediate serialized data

        @param d the data to serialize

        @return a YAML string representing the given data structure for storage in Qorus, in case the given data is NOTHING
        an empty string is returned

        @see
        - serialize_qorus_data()
        - deserializeQorusData()
    */
    static string serializeQorusData(auto d) {
%ifdef UseQoreDataSerialization
        return !exists d ? "" : make_yaml(Serializable::serializeToData(d));
%else
        return !exists d ? "" : make_yaml(d);
%endif
    }

    #! returns a string giving the default serialization of the given data structure for storage in Qorus
    /** the default serialization is currently YAML of Qore intermediate serialized data

        @param d the data to serialize

        @return a YAML string representing the given data structure for storage in Qorus

        @see
        - serialize_qorus_data()
        - deserializeQorusData()
    */
    static string serializeQorusDataWithNothing(auto d) {
%ifdef UseQoreDataSerialization
        return make_yaml(Serializable::serializeToData(d));
%else
        return make_yaml(d);
%endif
    }

    #! parses serialized data in either XML-RPC or YAML format and returns the corresponding qore data
    /** auto-detects XML-RPC or YAML decoding

        @param data the string data to deserialize

        @return the Qore data represented by the string arugment

        @see
        - deserialize_qorus_data()
        - serializeQorusData()
    */
    static auto deserializeQorusData(string data) {
        auto val = (data =~ /^</ ? parse_xmlrpc_value(data) : parse_yaml(data));
%ifdef UseQoreDataSerialization
        if (val."_data") {
            try {
                val = Serializable::deserialize(cast<hash<SerializationInfo>>(val));
            } catch (hash<ExceptionInfo> ex) {
                # ignore exception; assume that the original data was a non-SerializationInfo hash with a _data key
            }
        }
%endif
        return val;
    }

    #! deserializing a @ref null value from the DB returns @ref nothing "no value"
    static auto deserializeQorusData(null data) {
        # deserializing NULL -> returns NOTHING
    }

    #! returns a string error message if any exception in the chain passed was caused by a recoverable DB error, otherwise returns @ref nothing "NOTHING"
    /** @param driver the database driver name, which must be a driver supported by the Qorus system schema, currently one of \c "oracle", \c "pgsql", or \c "mysql", otherwise an \c UNSUPPORTED-DRIVER exception is thrown
        @param ex the exception hash

        @return a string error message if any exception in the chain passed was caused by a recoverable DB error, otherwise returns @ref nothing "NOTHING"

        @throw UNSUPPORTED-DRIVER only \c "oracle", \c "pgsql", and \c "mysql" are currently supported
    */
    static *string restartTransaction(string driver, hash<auto> ex) {
        # implmented in qorus-common-master-core-client.ql
        return restart_transaction(driver, ex);
    }

    #! returns @ref True if internal system debugging is enabled
    /**
        @note This API is not available in the client library
    */
    static bool isInternalSystemDebuggingEnabled() {
%ifdef QorusServer
        return Qorus.getDebugSystemInternals();
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! returns the value of the given key from the given hash, respects dot notation in the key name
    /** @param var_data the hash to search
        @param var_name the key value to use; respects dot notation
        @param missing_input an optional reference that returns True if the input key was missing in case of a
        @ref nothing return value

        @return the value referenced or @ref nothing if not present

        @since Qorus 4.0.3
    */
    static auto getHashDotValue(*hash<auto> var_data, string var_name, *reference<bool> missing_input) {
        if (var_name =~ /\.|\[-?[0-9]+\]/) {
            return _priv_get_complex_value(var_data, UserApi::_priv_get_dot_string_list(var_name), \missing_input);
        } else if (var_name == "*") {
            if (!exists var_data) {
                missing_input = True;
            }
            return var_data;
        }
        missing_input = !var_data.hasKey(var_name);
        return var_data{var_name};
    }

    #! expands one variable in a templated string
    /** @param str templated string to be expanded; see @ref bb_template_strings for more information on this
        parameter
        @param var_context context of the variable to be expanded (e.g. local, static, dynamic, keys,...)
        @param template_arg the template argument for the given context
        @param local_context local context supplied by the caller (plus user context info is added - see
                             @ref UserApi::getUserContextInfo() method)
        @param brackets if @ref True then the variable was given in curly brackets; currently ignored
        @param expand_complex_values if @ref True then lists and hashes will have their values expanded recursively
        @param missing_input an optional reference that returns True if the input key was missing in case of a
        @ref nothing return value

        @return the specified variable expanded to its value

        @throw LIST-VALUE-ERROR cannot parse list value expression
        @throw REST-EXPRESSION-ERROR cannot parse REST expression and argument
        @throw UNSUPPORTED-CONTEXT-ERROR if an unknown context variable is specified to be expanded
        @throw SENSITIVE-DATA-FORMAT-ERROR if the \c "$sensitive:<skey>.<svalue>.field-ref..." value or
        \c "$sensitive-alias:<alias>.field-ref..." template string does not have the required format

        @note the derived value is returned directly without recursive substitutions

        @see @ref bb_template_strings

        @since
        - added in Qorus 4.0.3
        - Qorus 4.1 removed the UNKNOWN-VALUE-ERROR exception
        - Qorus 4.1.1 added the \a expand_complex_values parameter
    */
    static auto expandOneVariable(string str, string var_context, auto template_arg, *hash<auto> local_context,
            *bool brackets, bool expand_complex_values = True, *reference<bool> missing_input) {
        local_context = UserApi::getUserContextInfo() + local_context;

        #printf("DEBUG eOV t: %y a: %y (lc: %y b: %y)\n", var_context, template_arg, local_context, brackets);

        # first process contexts that take non-string args
        if (var_context == "qore-expr-value") {
            return _priv_get_qore_string_value(template_arg);
        }
        if (template_arg.typeCode() != NT_STRING) {
            if (var_context == "qore-expr") {
                template_arg = _priv_get_qore_string_value(template_arg);
            } else {
                throw "FORMAT-ERROR", sprintf("template context %y takes a string argument; got type %y instead",
                    var_context, template_arg.type());
            }
        }
        string var_name = template_arg;
        auto value;
        switch (var_context) {
            case "local":
                value = UserApi::getHashDotValue(local_context, var_name, \missing_input);
                break;

            case "timestamp":
                if (var_name == "timegm") {
                    value = timegm(now_us());
                } else {
                    value = now_us().format(var_name);
                }
                break;

            case "rest": {
                # get call up to first '.' or '[' char
                (*string uri_path, *string arg) = (var_name =~ x/([^\.\[]+)(.*)$/);
                value = UserApi::callRestApi("GET", uri_path);
                if (arg.val()) {
                    switch (value.typeCode()) {
                        case NT_LIST:
                            value = _priv_get_list_arg_value(value, arg);
                            break;
                        case NT_HASH:
                            value = UserApi::getHashDotValue(value, arg);
                            break;
                        default:
                            throw "REST-EXPRESSION-ERROR", sprintf("cannot process argument %y from uri_path %y "
                                "result of type %y", arg, uri_path, value.type());
                    }
                }
                break;
            }

            case "qore-expr": {
                # do template substitution on argument string
                string expr_arg;
                try {
                    auto val = UserApi::expandTemplatedValue(var_name, local_context, expand_complex_values);
                    if (val.typeCode() != NT_STRING) {
                        val = _priv_get_qore_string_value(val);
                    }
                    expr_arg = val;
                } catch (hash<ExceptionInfo> ex) {
                    throw "EXPRESSION-ARG-ERROR", sprintf("expression %y: %s: %s", var_name, ex.err, ex.desc), ex.arg;
                }
                Expression expr;
                try {
                    expr = new Expression(_priv_try_get_pgm_ctx() ?? DynamicLogic, expr_arg, "qore-expr");
                } catch (hash<ExceptionInfo> ex) {
                    throw "EXPRESSION-PARSE-ERROR", sprintf("expression %y (=> %y): %s: %s", var_name, expr_arg, ex.err, ex.desc), ex.arg;
                }
                try {
                    auto rv = expr.eval();
                    QDBG_LOG("qore-expr: eval %y (=> %y) = %y", var_name, expr_arg, rv);
                    return rv;
                } catch (hash<ExceptionInfo> ex) {
                    throw "EXPRESSION-EVAL-ERROR", sprintf("expression %y (=> %y): %s: %s", var_name, expr_arg, ex.err, ex.desc), ex.arg;
                }
            }

            case "python-expr": {
                # do template substitution on argument string
                string expr_arg = _priv_get_expr_arg(var_name, local_context, expand_complex_values);
                try {
                    auto rv = _priv_get_pgm_ctx().evalPythonExpression(expr_arg);
                    QDBG_LOG("python-expr: eval %y (=> %y) = %y", var_name, expr_arg, rv);
                    return rv;
                } catch (hash<ExceptionInfo> ex) {
                    throw "EXPRESSION-EVAL-ERROR", sprintf("expression %y (=> %y): %s: %s", var_name, expr_arg, ex.err, ex.desc), ex.arg;
                }
            }

            case "value-map": {
                # break down string into a list of fields
                list<hash<DotInfo>> dot_list = UserApi::_priv_get_dot_string_list(var_name);
                if (dot_list.size() < 2) {
                    throw "SENSITIVE-DATA-FORMAT-ERROR", sprintf("value map value %y is not in format "
                        "<valuemap>.<key>", var_name);
                }
                string valuemap = (shift dot_list).key;
                string key = (shift dot_list).key;
                value = UserApi::getValueMap(valuemap, key);
                if (dot_list) {
                    value = _priv_get_complex_value(value, dot_list, \missing_input);
                }
                break;
            }

%ifdef QorusHasAnyIxApi
            case "sysprop": {
                # break down string into a list of fields
                hash<auto> var_data = Qorus.props.get();
                value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                break;
            }
%endif

%ifdef QorusHasWfApi
            case "static":
                if (tld.index) {
                    *hash<auto> var_data = SM.getStaticData();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                } else {
                    throw "UNSUPPORTED-CONTEXT-ERROR", "Static data can't be retrieved out of workflow context.";
                }
                break;

            case "dynamic":
                if (tld.index) {
                    *hash<auto> var_data = SM.getDynamicData();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                } else {
                    throw "UNSUPPORTED-CONTEXT-ERROR", "Dynamic data can't be retrieved out of workflow context";
                }
                break;

            case "sensitive":
                if (tld.index) {
                    # break down string into a list of fields
                    list<hash<DotInfo>> dot_list = UserApi::_priv_get_dot_string_list(var_name);
                    if (dot_list.size() < 3 || exists dot_list[0].array_offset || exists dot_list[1].array_offset) {
                        throw "SENSITIVE-DATA-FORMAT-ERROR", sprintf("sensitive data value %y is not in format "
                            "<skey>.<svalue>.<field-ref>[.<field-ref>...]", var_name);
                    }
                    *hash<auto> var_data;
                    string skey = (shift dot_list).key;
                    string svalue = (shift dot_list).key;
                    var_data = SM.getSensitiveData(skey, svalue);
                    value = _priv_get_complex_value(var_data, dot_list, \missing_input);
                } else {
                    throw "UNSUPPORTED-CONTEXT-ERROR", "Sensitive data can't be retrieved out of workflow context";
                }
                break;

            case "sensitive-alias":
                if (tld.index) {
                    # break down string into a list of fields
                    list<hash<DotInfo>> dot_list = UserApi::_priv_get_dot_string_list(var_name);
                    if (dot_list.size() < 2 || exists dot_list[0].array_offset) {
                        throw "SENSITIVE-DATA-FORMAT-ERROR", sprintf("sensitive data alias value %y is not in format "
                            "<alias>.<field-ref>[.<field-ref>...]", var_name);
                    }
                    string alias = (shift dot_list).key;
                    *hash<auto> var_data = SM.getSensitiveAlias(alias);
                    value = _priv_get_complex_value(var_data, dot_list, \missing_input);
                } else {
                    throw "UNSUPPORTED-CONTEXT-ERROR", "Sensitive data can't be retrieved out of workflow context";
                }
                break;

            case "temp":
                if (tld.index) {
                    *hash<auto> var_data = SM.getTempData();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                } else {
                    throw "UNSUPPORTED-CONTEXT-ERROR", "Temp data can't be retrieved out of workflow context";
                }
                break;

            case "step":
                if (tld.index) {
                    *hash<auto> var_data = SM.getStepData();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                } else {
                    throw "UNSUPPORTED-CONTEXT-ERROR", "Step data can't be retrieved out of workflow context";
                }
                break;

            case "keys":
                if (tld.index) {
                    value = SM.getOrderKeys(var_name, \missing_input);
                } else {
                    throw "UNSUPPORTED-CONTEXT-ERROR", "Order keys can't be retrieved out of workflow context";
                }
                break;
%endif

            # issue #3432: transient data: temporary storage for connectors for all interface types
            case "transient":
                value = UserApi::getHashDotValue(tld.transient_data, var_name, \missing_input);
                break;

            # "block-local" data: temporary thread-local storage for connectors for all interface types
            case "var":
                value = UserApi::getHashDotValue(tld.var_data, var_name, \missing_input);
                break;

            case "config":
                value = var_name == "*"
                    ? UserApi::getConfigItemHash(local_context)
                    : UserApi::getConfigItemValue(var_name, local_context, expand_complex_values);
                break;

            case "xconfig":
                value = var_name == "*"
                    ? UserApi::getInterfaceConfigItemHash(local_context)
                    : UserApi::getInterfaceConfigItemValue(var_name, local_context, expand_complex_values);
                break;

            case "jinfo":
%ifdef QorusHasJobApi
                if (tld.isJobContext()) {
                    *hash<auto> var_data = JobApi::getJobInfo();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                    QDBG_LOG("UserApi::expandOneVariable() jinfo var_data: %y var_name: %y value: %y", var_data,
                        var_name, value);
                    break;
                }
%endif
                throw "UNSUPPORTED-CONTEXT-ERROR", sprintf("%y is not a supported template in this context (%y)",
                    var_context, tld._current_ix ?? "none");

            case "info":
%ifdef QorusHasJobApi
                if (tld.isJobContext()) {
                    *hash<auto> var_data = JobApi::getInfo();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                    QDBG_LOG("UserApi::expandOneVariable() var_data: %y var_name: %y value: %y", var_data, var_name, value);
                    break;
                }
%endif
%ifdef QorusHasSvcApi
                if (tld.isServiceContext()) {
                    *hash<auto> var_data = ServiceApi::getServiceInfo();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                    break;
                }
%endif
%ifdef QorusHasWfApi
                if (tld.isWorkflowExecContext()) {
                    *hash<auto> var_data = WorkflowApi::getWorkflowInstanceData() + {
                        "step": WorkflowApi::getStepInfo(),
                    };
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                    break;
                }
%endif
                throw "UNSUPPORTED-CONTEXT-ERROR", sprintf("%y is not a supported template in this context (%y)",
                    var_context, tld._current_ix ?? "none");

            case "parse-value": {
                string arg = UserApi::expandTemplatedValue(var_name, local_context, expand_complex_values);
                value = parse_to_qore_value(arg);
                break;
            }

            case "pstate":
%ifdef QorusHasJobApi
                # NOTE: "pstate" and "state" are different for jobs
                if (tld.isJobContext()) {
                    *hash<auto> var_data = JobApi::getPersistentStateData();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                    break;
                }
%endif
%ifdef QorusHasSvcApi
                # NOTE: "pstate" and "state" are the same for services
                if (tld.isServiceContext()) {
                    *hash<auto> var_data = ServiceApi::getStateData();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                    break;
                }
%endif
%ifdef QorusHasWfApi
                # NOTE: "pstate" and "dynamic" are the same for workflows
                if (tld.isWorkflowExecContext()) {
                    *hash<auto> var_data = SM.getDynamicData();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                    break;
                }
%endif
                throw "UNSUPPORTED-CONTEXT-ERROR", sprintf("%y is not a supported template in this context (%y)",
                    var_context, tld._current_ix ?? "none");

            case "state":
%ifdef QorusHasSvcApi
                if (tld.isServiceContext()) {
                    *hash<auto> var_data = ServiceApi::getStateData();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                    break;
                }
%endif
%ifdef QorusHasJobApi
                if (tld.isJobContext()) {
                    *hash<auto> var_data = JobApi::getStateData();
                    value = UserApi::getHashDotValue(var_data, var_name, \missing_input);
                    break;
                }
%endif

                # fall down to default
            default:
                throw "UNSUPPORTED-CONTEXT-ERROR", sprintf("%y is not a supported template in this context (%y)",
                    var_context, tld._current_ix ?? "none");
        }

        # check if we have a single-element list
        if (value.typeCode() == NT_LIST && value.lsize() == 1 && value[0].strp()) {
            value = value[0];
        }
        return value;
    }

    #! checks if the given value is a templated string with only one expandable variable
    /** @param value to check
        @return return @ref True if value is a templated string with only one expandable variable otherwise @ref False

        @since Qorus 4.0.3
    */
    static bool isSingleTemplatedString(auto value) {
        return value.typeCode() == NT_STRING && value.regex(BB_EXACTLY_ONE_VARIABLE_RE);
    }

    #! expands all variables in a templated string
    /** @param value templated string to be expanded; see @ref bb_template_strings for more information on this
        parameter
        @param local_context local context supplied by the caller (plus user context info is added - see
        @ref UserApi::getUserContextInfo() method)
        @param expand_complex_values if @ref True then lists and hashes will have their values expanded recursively
        @param missing_input an optional reference that returns True if the input key was missing in case of a
        @ref nothing return value
        @param template_context optional template context

        @return the value of the string as substituted with all variables expanded recursively until there are no more
        expansions to perform (or the derived value is not a string)

        @throw LIST-VALUE-ERROR cannot parse list value expression
        @throw REST-EXPRESSION-ERROR cannot parse REST expression and argument
        @throw UNSUPPORTED-CONTEXT-ERROR if an unknown context variable is specified to be expanded
        @throw FORMAT-ERROR if the templated string doesn't have correct format (e.g. unescaped dollar sign that does
                            not represent a variable)
        @throw VALUE-ERROR if the resolved values cannot be combined for the return value. or
        if the key in a hash is not resolved to a type convertible to a string
        @throw SENSITIVE-DATA-FORMAT-ERROR if the \c "$sensitive:<skey>.<svalue>.field-ref..." value or
        \c "$sensitive-alias:<alias>.field-ref..." template string does not have the required format

        @see @ref bb_template_strings

        @since
        - added in Qorus 4.0.3
        - Qorus 4.1 removed the UNKNOWN-VALUE-ERROR exception
        - Qorus 4.1.1 added the \a expand_complex_values argument
        - Qorus 5.1.21 added the \a template_context argument
    */
    static auto expandTemplatedValue(auto value, *hash<auto> local_context, bool expand_complex_values = True,
            *reference<bool> missing_input, *string template_context) {
        if ((int type_code = value.typeCode()) != NT_STRING) {
            if (expand_complex_values && (type_code == NT_HASH || type_code == NT_LIST)) {
                return UserApi::expandComplexValue(value, local_context, template_context);
            }
            return value;
        }

        list<hash<TemplateTokenInfo>> tokens = _priv_tokenize_template(value);

        # get a Qore string if we get a qore-expr token
        auto rv;
        bool rv_assigned;
        foreach hash<TemplateTokenInfo> token in (tokens) {
            auto new_value;
            if (token.type == TT_String) {
                new_value = token.val;
            } else if (token.type == TT_Template) {
                new_value = UserApi::expandTemplatedValue(token.arg, local_context, expand_complex_values,
                    \missing_input, token.val);
                #printf("DBG GOT VALUE %y = %y (lc: %y)\n", token.arg, new_value, local_context);

                do {
                    new_value = UserApi::expandOneVariable(value, token.val, new_value, local_context, False,
                        expand_complex_values, \missing_input);
                } while (_priv_needs_template_expansion(new_value));

                if (!exists new_value && exists token.alt) {
                    new_value = UserApi::expandTemplatedValue(token.alt, local_context, expand_complex_values,
                        \missing_input, token.val);
                    #printf("DBG GOT ALT VALUE 1: %y = %y (lc: %y)\n", token.alt, new_value, local_context);
                }
            }

            if (!exists new_value && template_context != "qore-expr") {
                continue;
            }
            if (rv_assigned) {
                if (rv.typeCode() != NT_STRING) {
                    # issue #3785: convert to a qore data string in the $qore-expr: template context
                    if (template_context == "qore-expr") {
                        rv = _priv_get_qore_string_value(rv);
                    } else {
                        rv = _priv_get_string_value(rv);
                    }
                }
                if (new_value.typeCode() != NT_STRING) {
                    # issue #3785: convert to a qore data string in the $qore-expr: template context
                    if (template_context == "qore-expr") {
                        new_value = _priv_get_qore_string_value(new_value);
                    } else {
                        new_value = _priv_get_string_value(new_value);
                    }
                }
                rv += new_value;
            } else {
                # new_value might be NOTHING; in case of a $qore-expr template, we may need to process it
                rv = new_value;
                rv_assigned = True;
            }
            #printf("DBG rv: %y\n", rv);
        }
        return rv;
    }

    #! expands all variables in a list with templated values
    /** @param val the value to expand
        @param local_context local context supplied by the caller (plus user context info is added - see
        @ref UserApi::getUserContextInfo() method)
        @param template_context optional template context

        @return the value with templated strings expanded

        @throw VALUE-ERROR if the key in a hash is not resolved to a type convertible to a string

        @see expandTemplatedValue() for information about how strings are expanded

        @since Qorus 4.1.1
    */
    static softlist<auto> expandComplexValue(list<auto> val, *hash<auto> local_context, *string template_context) {
        list<auto> rv;
        foreach auto elem in (val) {
            switch (elem.typeCode()) {
                case NT_STRING:
                    rv += UserApi::expandTemplatedValue(elem, local_context, True, NOTHING, template_context);
                    break;
                case NT_LIST:
                    rv += UserApi::expandComplexValue(elem, local_context, template_context);
                    break;
                case NT_HASH:
                    rv += UserApi::expandComplexValue(elem, local_context, template_context);
                    break;
                default: rv += elem; break;
            }
        }
        return rv;
    }

    #! expands all variables in a hash with templated values
    /** @param val the value to expand
        @param local_context local context supplied by the caller (plus user context info is added - see
        @ref UserApi::getUserContextInfo() method)
        @param template_context optional template context

        @return the value with templated strings expanded

        @throw VALUE-ERROR if the key in a hash is not resolved to a type convertible to a string

        @see expandTemplatedValue() for information about how strings are expanded

        @since Qorus 4.1.1
    */
    static hash<auto> expandComplexValue(hash<auto> val, *hash<auto> local_context, *string template_context) {
        hash<auto> rv = {};
        foreach hash<auto> i in (val.pairIterator()) {
            # expand key
            auto key0 = UserApi::expandTemplatedValue(i.key, local_context, True, NOTHING, template_context);
            if (!key0.strp()) {
                throw "VALUE-ERROR", sprintf("key %y in hash resolved to type %y which is not convertible to a string",
                    i.key, key0.type());
            }
            softstring key = key0;
            # expand value
            switch (i.value.typeCode()) {
                case NT_STRING:
                    rv{key} = UserApi::expandTemplatedValue(i.value, local_context, True, NOTHING, template_context);
                    break;
                case NT_LIST:
                    rv{key} = UserApi::expandComplexValue(i.value, local_context, template_context);
                    break;
                case NT_HASH:
                    rv{key} = UserApi::expandComplexValue(i.value, local_context, template_context);
                    break;
                default: rv{key} = i.value; break;
            }
        }
        return rv;
    }

    const BB_INPUT_DATA_CFG_KEY = "input_data";
    const BB_OUTPUT_DATA_CFG_KEY = "output_data";
    # this is why regular expressions are considered "write-only"
    const BB_ONE_VARIABLE_RE = "\\$([\\w-]+):((?:{.*[^\\\\]})|(?:\\*|[\\w]+[\\w\\.]*))((?:\\w?\\?\\?{.*})*)";
    const BB_EXACTLY_ONE_VARIABLE_RE = "^" + BB_ONE_VARIABLE_RE + "$";

    #! parses one template variable and returns a hash with its parts
    /** @param str templated string to be parsed (has to contain exactly one variable and nothing more); see
        @ref bb_template_strings for more information on this parameter

        @return BbVariable hash representing the variable

        @throw FORMAT-ERROR if the templated string doesn't have correct format

        @since Qorus 4.0.3
    */
    static hash<BbVariable> bbParseExactlyOneVariable(string str) {
        # RE_DotAll = makes a dot (.) match a newline character, equivalent to /s
        *list<*string> var = str.regexExtract(BB_EXACTLY_ONE_VARIABLE_RE, Qore::RE_DotAll);
        bool brackets;
        if (var[1] =~ /^{.*}$/) {
            brackets = True;
            var[1] =~ s/^{(.*)}$/$1/;
        }
        if (!exists var || !exists var[0] || !exists var[1]) {
            throw "FORMAT-ERROR", sprintf("'%s' is not a variable definition", str);
        }

        return <BbVariable>{
            "contxt": var[0],
            "name": var[1],
            "brackets": brackets,
        };
    }

    #! returns specified input data field's value
    /** @par Example:
        @code{.py}
hash<auto> account_info_hash = {
    "accountIdNumber": "123456ABC";
};
# this will be assigned "123456ABC";
string account_id = UserApi::getInputData("account_id", account_info_hash, {"account_id": "$local:accountIdNumber"});
        @endcode

        @param field_name name of the field that should be returned; identifies a key in \a input_data_cfg
        @param local_context the caller can supply its \c "$local:" context for template variables (plus user context
                             info is added - see @ref UserApi::getUserContextInfo()); hash values are subject
                             to recursive template variable expansion
        @param input_data_cfg input data configuration; if not provided, the default location for the input data
                              config is retrieved from current configuration item \c "input_data";
                              \a field_name must be present in this hash; string values of the key referenced with
                              \a field_name in this hash are subject to recursive template variable expansion, and the
                              resulting value is returned; non-string values are returned as-is

        @return the value of the key given by \a field_name in the \a input_data_cfg hash is subject to recursive template
        variable expansion and returned; template variable expansion is performed if the hash value is a string, if the
        value is any other data type, it is returned as-is

        @throw LIST-VALUE-ERROR cannot parse list value expression
        @throw REST-EXPRESSION-ERROR cannot parse REST expression and argument
        @throw UNSUPPORTED-CONTEXT-ERROR if an unknown context variable is specified to be expanded
        @throw SENSITIVE-DATA-FORMAT-ERROR if the \c "$sensitive:<skey>.<svalue>.field-ref..." value or
        \c "$sensitive-alias:<alias>.field-ref..." template string does not have the required format
        @throw INVALID-ARGUMENT if the field_name is not present in input data

        @see @ref bb_template_strings for information on template variable expansion

        @since
        - added in Qorus 4.0.3
        - Qorus 4.1 removed the UNKNOWN-VALUE-ERROR exception
    */
    static auto getInputData(string field_name, *hash<auto> local_context, *hash<auto> input_data_cfg) {
        *string input_data_item = input_data_cfg
            ? input_data_cfg{field_name}
            : UserApi::getConfigItemValue(BB_INPUT_DATA_CFG_KEY, local_context, False){field_name};

        if (!exists input_data_item) {
            throw "INVALID-ARGUMENT", sprintf("Input data config doesn't contain field '%s'", field_name);
        }
        auto value = UserApi::expandTemplatedValue(input_data_item, local_context);
        if (!exists value) {
            throw "INVALID-ARGUMENT", sprintf("Input data field %y was not found", field_name);
        }
        return value;
    }

    #! returns all input data
    /** @par Example:
        @code{.py}
hash<auto> account_info_hash = {
    "accountIdNumber": "123456ABC";
};
# will be assigned {"account_id": "123456ABC"}
hash<auto> input_info = UserApi::getInputData({"account_id": "$local:accountIdNumber"}, account_info_hash);
        @endcode

        @param local_context the caller can supply its \c "$local:" context for template variables (plus user context
                             info is added - see @ref UserApi::getUserContextInfo()); hash values are subject
                             to recursive template variable expansion
        @param input_data_cfg input data configuration; if not provided, the default location for the input data
                              config is retrieved from configuration item \c "input_data"

        @return the entire input data hash with all string hash values subject to recursive template variable
        expansion; input data hash values that are not strings are returned as-is

        @throw LIST-VALUE-ERROR cannot parse list value expression
        @throw REST-EXPRESSION-ERROR cannot parse REST expression and argument
        @throw UNSUPPORTED-CONTEXT-ERROR if an unknown or invalid context variable is specified to be expanded
        @throw SENSITIVE-DATA-FORMAT-ERROR if the \c "$sensitive:<skey>.<svalue>.field-ref..." value or
        \c "$sensitive-alias:<alias>.field-ref..." template string does not have the required format

        @since
        - added in Qorus 4.0.3
        - Qorus 4.1 removed the UNKNOWN-VALUE-ERROR exception
    */
    static hash<auto> getInputData(*hash<auto> input_data_cfg, *hash<auto> local_context) {
        if (!input_data_cfg) {
            return UserApi::getConfigItemValue(BB_INPUT_DATA_CFG_KEY, local_context) ?? {};
        }

        return map {$1.key: UserApi::expandTemplatedValue($1.value, local_context)}, input_data_cfg.pairIterator();
    }

    #! updates the given hash with a key in dot notation with the given value
    /** @par Example:
        @code{.py}
# will assign {"account": {"id": "123456ABC"}}
hash<auto> updated_hash = UserApi::updateHashDotValue({}, "account.id", "123456ABC");
        @endcode

        @param var_data the hash to update
        @param var_name the key name to update in dot notation
        @param value the value to set

        @return the updated hash

        @since Qorus 4.0.3
    */
    static *hash<auto> updateHashDotValue(*hash<auto> var_data, string var_name, auto value) {
        return _priv_update_hash_dot_value(var_data, UserApi::_priv_get_dot_string_list(var_name), value);
    }

    #! updates specified output data field's value
    /** @par Example:
        @code{.py}
# write the account ID to the account -> id field in dynamic data
UserApi::updateOutputData("account_id", account_id, {"account_id": "$dynamic:{account.id}"});
        @endcode

        @param field_name name of the field that should be updated; identifies a key in \a output_data_cfg that
        provides the location for writing the output data
        @param output_data the value to write in the location determined by the \a field_name key in
        \a output_data_cfg
        @param output_data_cfg a hash of values giving output data locations; if not provided, the default location
        for the output data config is retrieved from configuration item \c "output_data";
        \a field_name must be present in this hash; string values of the key referenced with \a field_name in this
        hash provide the location to write \a output_data and are not subject to template variable expansion

        @throw UNSUPPORTED-CONTEXT-ERROR if output data configuration specifies an unsupported context
        @throw OUTPUT-CONFIG-ERROR \a field_name is not present in \a output_data_cfg
        @throw SENSITIVE-DATA-FORMAT-ERROR if the \c "$sensitive:<skey>.<svalue>.field-ref..." value or
        \c "$sensitive-alias:<alias>.field-ref..." template string does not have the required format
        @throw SET-ORDER-KEYS-ERROR missing value for order key
        @throw INVALID-WORKFLOW-KEY workflow key not valid for the current workflow
        @throw DUPLICATE-KEY-VALUE duplicate value provided for order key

        @see @ref writeOutputData()

        @since Qorus 4.0.3
    */
    static updateOutputData(string field_name, auto output_data, *hash<auto> output_data_cfg) {
        UserApi::updateOutputData({field_name: output_data}, output_data_cfg);
    }

    #! updates all output data
    /** @par Example:
        @code{.py}
# write the account ID to the account -> id field in dynamic data
UserApi::updateOutputData({"account_id": account_id}, {"account_id": "$dynamic:{account.id}"});

# write the account ID in the "account" hash to the account -> id field in dynamic data
UserApi::updateOutputData({"account": {"account_id": account_id}}, {"account.account_id": "$dynamic:{account.id}"});

# write the entire output hash (first argument) to the location provided by the value in the second argument
UserApi::updateOutputData(row_data, {"*": "$dynamic:{account.info}"});

# write the entire output account hash (first argument) to the location provided by the value in the second argument
# and ignore the error if the account information is missing
UserApi::updateOutputData(row_data, {"account?.*": "$dynamic:{account.info}"});
        @endcode

        @param all_output_data a hash giving output data; keys in this hash must match a corresponding key in
        \a output_data_cfg which will provide the location for writing the value, values in this hash will be written
        to the locations provided in \a output_data_cfg
        @param output_data_cfg a hash of values giving output data locations; if not provided, the default location
        for the output data config is retrieved from configuration item \c "output_data";
        all keys in this hash (other than \c "*") must also be present in \a all_output_data; string values of
        referenced keys in this hash provide the location to write the values of the \a all_output_data hash; these
        values are not subject to template variable expansion; note special key \c "*" which indicates that the entire
        \a all_output_data hash should be written to the output location; note that this value also accepts hash paths
        such as \c "key1.key2.key3"; if a key contains a \c "." character, you must escape it with backslashes (ex:
        \c "key\.with\.dots"); additionally, this method will throw an exception if any element in the hash does not
        resolve to a value; to ignore the situation when data is missing, append a \c "?" to the key name; ex:
        \c "key1.optional_key?.final_key" or \c "key2.key3.final_key?"; in this case missing data is ignored and no
        exception is thrown.

        For a list of supported output fields for \a output_data_cfg values; see template strings listed in
        @ref bb_template_strings marked as writable (\c W)

        @throw UNSUPPORTED-CONTEXT-ERROR if output data configuration specifies an unsupported context
        @throw OUTPUT-CONFIG-ERROR \a field_name (without a \c "?" appended to the name) is not present in
        \a all_output_data
        @throw SENSITIVE-DATA-FORMAT-ERROR if the \c "$sensitive:<skey>.<svalue>.field-ref..." value or
        \c "$sensitive-alias:<alias>.field-ref..." template string does not have the required format
        @throw SET-ORDER-KEYS-ERROR missing value for order key
        @throw INVALID-WORKFLOW-KEY workflow key not valid for the current workflow
        @throw DUPLICATE-KEY-VALUE duplicate value provided for order key

        @note If the output data is retrieved from a configuration item, it is not subject to recursive expansion

        @see
        - @ref writeOutputData()
        - @ref bb_template_strings

        @since
        - Qorus 4.0.3
        - Qorus 5.1.6 introduced the special key \c "*" in \a output_data_cfg, indicating that the entire output hash
          (\a all_output_data) should be written to the output location provided as the value to this key
        - Qorus 5.1.7 implemented output path following and optional fields in \c all_output_data to suppress the
          \c OUTPUT-CONFIG-ERROR exception in case of missing data
    */
    static updateOutputData(hash<auto> all_output_data,
            hash<auto> output_data_cfg = UserApi::getConfigItemValue(BB_OUTPUT_DATA_CFG_KEY, NOTHING, False)) {
        foreach hash<auto> i in (output_data_cfg.pairIterator()) {
            string field_name = i.key;
            auto value;
            {
                list<hash<DotInfo>> dot_list = _priv_get_dot_string_list(field_name);
                auto target = all_output_data;
                foreach hash<DotInfo> field in (dot_list) {
                    bool ignore_missing;
                    if (field.key =~ /\\\?$/) {
                        splice field.key, -2, 2, "?";
                    } else if (field.key =~ /\?$/) {
                        ignore_missing = True;
                        splice field.key, -1;
                    }
                    bool last = ($# == (dot_list.size() - 1));
                    auto tmp = target{field.key};
                    if (exists field.array_offset) {
                        if (tmp.typeCode() == NT_LIST) {
                            tmp = tmp[field.array_offset];
                        } else {
                            throw "OUTPUT-CONFIG-ERROR", sprintf("field name %y (in path %y position %d) specified "
                                "in the output configuration is not a list but rather type %y, but list offset %d "
                                "should be returned", field.key, field_name, $# + 1, tmp.type(),
                                field.array_offset);
                        }
                    }
                    if (!exists tmp) {
                        if (last && field.key == "*") {
                            value = target;
                            break;
                        }
                        if (ignore_missing) {
                            UserApi::logInfo("field name %y (in path %y position %d) specified in the output "
                                "configuration does not exist in the hash output data argument supplied; fields "
                                "available: %y, as this field was marked optional (\"%s?\"), no output data was "
                                "written", field.key, field_name, $# + 1, keys target, field.key);
                            return;
                        }
                        throw "OUTPUT-CONFIG-ERROR", sprintf("field name %y (in path %y position %d) specified in "
                            "the output configuration does not exist in the hash output data argument supplied; "
                            "fields available: %y", field.key, field_name, $# + 1, keys target);
                    }
                    if (last) {
                        value = tmp;
                    } else {
                        target = tmp;
                    }
                }
            }
            # value supplied to be used to write to the output location; may be a list of locations
            foreach auto val in (i.value) {
                if (val.typeCode() != NT_STRING) {
                    if (exists val) {
                        throw "OUTPUT-CONFIG-ERROR", sprintf("field name %y is assigned to a value of type %y in the "
                            "output configuration; expected type \"string\"", field_name, val.type());
                    }
                    throw "OUTPUT-CONFIG-ERROR", sprintf("field name %y does not exist in the output configuration; "
                        "known output configuration fields: %y", field_name, keys output_data_cfg);
                }
                *string ctx = (val =~ x/^\$([^:]+):/)[0];
                if (!exists ctx) {
                    throw "OUTPUT-CONFIG-ERROR", sprintf("output key %y value %y has no output context prefix "
                        "(\"$<context>:...\")", i.key, val);
                }

                switch (ctx) {
                    # issue #3432: transient data - temporary data for all interface types for temporary storage for
                    # connectors
                    case "transient": {
                        hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                        QDBG_LOG("UserApi::updateOutputData() transient before: %y (update: %y = %y)", tld.transient_data, var, value);
                        # issue #3820: ensure transient and var data is always local to the current FSM
                        tld.transient_data = UserApi::updateHashDotValue(tld.transient_data, var.name, value);
                        QDBG_LOG("UserApi::updateOutputData() transient after: %y", tld.transient_data);
                        break;
                    }

                    # "block-local" data: temporary thread-local storage for connectors for all interface types
                    case "var":
                        hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                        tld.var_data = UserApi::updateHashDotValue(tld.var_data, var.name, value);
                        break;

%ifdef QorusHasAnyIxApi
                    case "sysprop": {
                        hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                        Qorus.props.updatePath(var.name, value);
                        break;
                    }
%endif

%ifdef QorusHasWfApi
                    case "dynamic": {
                        hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                        SM.updateDynamicDataPath(var.name, value);
                        break;
                    }

                    case "sensitive": {
                        hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                        # break down string into a list of fields
                        list<hash<DotInfo>> dot_list = UserApi::_priv_get_dot_string_list(var.name);
                        if (dot_list.size() < 3 || exists dot_list[0].array_offset || exists dot_list[1].array_offset) {
                            throw "SENSITIVE-DATA-FORMAT-ERROR", sprintf("sensitive data value %y is not in format "
                                "<skey>.<svalue>.<field-ref>[.<field-ref>...]", var.name);
                        }
                        string skey = (shift dot_list).key;
                        string svalue = (shift dot_list).key;
                        SM.updateSensitiveDataPath(skey, svalue, dot_list, value);
                        break;
                    }

                    case "sensitive-alias": {
                        hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                        # break down string into a list of fields
                        list<hash<DotInfo>> dot_list = UserApi::_priv_get_dot_string_list(var.name);
                        if (dot_list.size() < 2 || exists dot_list[0].array_offset) {
                            throw "SENSITIVE-DATA-FORMAT-ERROR", sprintf("sensitive data value %y is not in format "
                                "<alias>.<field-ref>[.<field-ref>...]", var.name);
                        }
                        string alias = (shift dot_list).key;
                        SM.updateSensitiveDataAliasPath(alias, dot_list, value);
                        break;
                    }

                    case "temp": {
                        hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                        SM.updateTempDataPath(var.name, value);
                        break;
                    }

                    case "step": {
                        hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                        SM.updateStepDataPath(var.name, value);
                        break;
                    }

                    case "keys": {
                        splice val, 0, ctx.length() + 2;
                        string keyname = UserApi::expandTemplatedValue(val);
                        # order keys do not support dot notation; they must be in string -> value format
                        SM.setOrderKeys({keyname: value}, False);
                        break;
                    }

                    case "feedback": {
                        splice val, 0, ctx.length() + 2;
                        string keyname = UserApi::expandTemplatedValue(val);
                        WorkflowApi::leaveParentFeedback(keyname, value);
                        break;
                    }
%endif
%ifdef QorusHasJobApi
                    case "jinfo":
                    case "info": {
                        hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                        JobApi::saveInfoPath(var.name, value);
                        break;
                    }
%endif
                    case "pstate":
%ifdef QorusHasJobApi
                        if (tld.isJobContext()) {
                            hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                            JobApi::savePersistentStateDataPath(var.name, value);
                            break;
                        }
%endif
%ifdef QorusHasSvcApi
                        if (tld.isServiceContext()) {
                            hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                            ServiceApi::saveStateDataPath(var.name, value);
                            break;
                        }
                        QDBG_LOG("NO SERVICE");
%endif
%ifdef QorusHasWfApi
                        if (tld.isWorkflowExecContext()) {
                            hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                            SM.updateDynamicDataPath(var.name, value);
                            break;
                        }
%endif
                        throw "UNSUPPORTED-CONTEXT-ERROR", sprintf("output config data type %y is not supported in this "
                            "context (%y)", ctx, tld._current_ix ?? "none");

                    case "state":
%ifdef QorusHasSvcApi
                        if (tld.isServiceContext()) {
                            hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                            ServiceApi::saveStateDataPath(var.name, value);
                            break;
                        }
%endif
%ifdef QorusHasJobApi
                        if (tld.isJobContext()) {
                            hash<BbVariable> var = UserApi::bbParseExactlyOneVariable(val);
                            JobApi::saveStateDataPath(var.name, value);
                            break;
                        }
%endif
                        # fall down to default
                    default:
                        remove value;
                        throw "UNSUPPORTED-CONTEXT-ERROR", sprintf("output config data type %y is not supported in this "
                            "context (%y)", ctx, tld._current_ix ?? "none");
                }
            }
        }
    }

    #! Writes output data using a concise format
    /** @par Example
        @code{.py}
# write the the input of FSM state data to the "account" key of the current workflow order's dynamic data hash
UserApi::writeOutputData({"$local:input": "$dynamic:account"});
        @endcode

        @param output_data a hash of output data; keys are template strings to be resolved to values; values are
        locations to write the data to; no value or an empty hash means the call is ignored

        @note local input data is made up of the results of @ref getUserContextInfo(); note that the \c "input" key in
        this hash is set to any current input data when running in a @ref finite_state_machines "finite state machine"

        @see updateOutputData()

        @since Qorus 5.1.29
    */
    static writeOutputData(*hash<auto> output_data) {
        if (!output_data) {
            return;
        }
        *hash<auto> local_context = UserApi::getUserContextInfo();

        int count = 0;
        hash<auto> values;
        hash<auto> output;
        UserApi::logDebug("UserApi::writeOutputData(): local context: %y", local_context);
        foreach hash<auto> i in (output_data.pairIterator()) {
            string key = sprintf("k%d", count++);
            values{key} = UserApi::expandTemplatedValue(i.key, local_context);
            output{key} = i.value;
        }
        UserApi::logDebug("UserApi::writeOutputData() writing output data: %y", (map {output{$1}: values{$1}},
            keys values));
        on_error UserApi::logError("UserApi::writeOutputData(): output error values: %y output: %y (local context: "
            "%y)", values, output, local_context);
        UserApi::updateOutputData(values, output);
    }

    #! returns string data for the given file location
    /** @param location the location of the file data (ex: \c "resource://service-name:path/to/ressource"); see
        @ref file_locations for more information about this parameter

        @return the resource data as a string

        @throw LOCATION-ERROR the location string cannot be parsed; unknown location scheme; invalid location option

        @since
        - Qorus 4.0.3
        - Qorus 4.1 added support for <tt><b>http(s)</b></tt> locations
        - Qorus 4.1.1 implements this method with a call to
          @ref FileLocationHandler::FileLocationHandler::getTextFileFromLocation() "FileLocationHandler::getTextFileFromLocation()",
          adding support for more schemes as well as runtime extensions
    */
    static string getTextFileFromLocation(string location) {
        return FileLocationHandler::getTextFileFromLocation(location);
    }

    #! returns binary data for the given file location
    /** @param location the location of the file data (ex: \c "resource://service-name:path/to/resource"); see
        @ref file_locations for more information about this parameter

        @return the resource data as a binary value

        @throw LOCATION-ERROR the location string cannot be parsed; unknown location scheme; invalid location option

        @since
        - Qorus 4.0.3
        - Qorus 4.1 added support for <tt><b>http(s)</b></tt> locations
        - Qorus 4.1.1 implements this method with a call to
          @ref FileLocationHandler::FileLocationHandler::getBinaryFileFromLocation() "FileLocationHandler::getBinaryFileFromLocation()",
          adding support for more schemes as well as runtime extensions
    */
    static binary getBinaryFileFromLocation(string location) {
        return FileLocationHandler::getBinaryFileFromLocation(location);
    }

    #! Returns a string stream for the file's data at the given location
    /** @param location the location of the file data

        @return a stream reader for the file's data

        @since Qorus 5.1.24
    */
    static Qore::StreamReader getStreamReaderFromLocation(string location) {
        return FileLocationHandler::getStreamReaderFromLocation(location);
    }

    #! Returns an input stream for file data at the given location
    /** @param location the location of the file data

        @return an input stream for the file's data

        @since Qorus 5.1.24
    */
    static Qore::InputStream getBinaryStreamFromLocation(string location) {
        return FileLocationHandler::getBinaryStreamFromLocation(location);
    }

    #! Writes data to a file at the given location
    /** @param location the location of the file data
        @param contents the file contents to write to the location

        @since Qorus 5.1.24
    */
    static writeFileToLocation(string location, data contents) {
        FileLocationHandler::writeFileToLocation(location, contents);
    }

    #! Returns an output stream for writing data to the given location
    /** @param location the location of the file to write

        @return an output stream for writing to the file

        @note
        - OutputStreamWrapper::close() must be called to close the stream after writing terminates in order to avoid a
          deadlock
        - The data written to the OutputStreamWrapper object may be written in the background; to ensure that the data has
          been written to the target, call OutputStreamWrapper::waitForIo()

        @since Qorus 5.1.24
    */
    static FileLocationHandler::OutputStreamWrapper getOutputStreamForLocation(string location) {
        return FileLocationHandler::getOutputStreamForLocation(location);
    }

    #! Executes the given @ref finite_state_machines "Finite State Machine" and returns the final output
    /** @param fsm_name the name of the Finite State Machine to execute; must be a valid Finite State Machine for the
        current interface context
        @param arg any optional input argument for the Finite State Machine

        @return any final output provided by the Finite State Machine

        @throw FSM-NOT-FOUND The given Finite State Machine is not valid for the current interface context

        @note This API is not available in the client library

        @since Qorus 5.0
    */
    static auto executeFsm(string fsm_name, auto arg) {
%ifdef QorusServer
        return QorusFsmHandler::executeFsm(fsm_name, arg);
%endif

%ifdef QorusClient
        throw "CLIENT-ERROR", "this API is not supported in the Qorus client";
%endif
    }

    #! Registers the given @ref finite_state_machines "Finite State Machine" with the given object as an @ref DataProvider::Observer "Observer"
    /** @param fsm_name the name of the Finite State Machine to register with \a observable
        @param observable the event source object
        @param event_id the event ID to register with \a observable

        @throw FSM-NOT-FOUND The given Finite State Machine is not valid for the current interface context

        @since Qorus 5.0
    */
    static registerFsmAsObserver(string fsm_name, DataProvider::Observable observable, string event_id) {
%ifdef QorusServer
        return QorusFsmHandler::registerFsmAsObserver(fsm_name, observable, event_id);
%endif
    }

    #! This method binds a workflow to a subworkflow step
    /** This call is a wrapper for
        @ref OMQ::UserApi::Workflow::QorusSubworkflowStepBase::bindSubworkflow() "QorusSubworkflowStepBase::bindSubworkflow()";
        please see that method for documentation

        @throw SUBWORKFLOW-ERROR in addition to exception thrown by the above function, this error is raised if this
        method is called when not in a workflow context

        @since Qorus 5.1.29
    */
    public static hash<auto> bindSubworkflow(hash<auto> wf, hash<auto> order) {
%ifdef QorusHasWfApi
        return QorusSubworkflowStepBase::bindSubworkflow(wf, order);
%else
        throw "SUBWORKFLOW-ERROR", "the bind subworkflow API can only be called in a workflow context";
%endif
    }

    #! This method skips binding a workflow to a subworkflow step
    /** This call is a wrapper for
        @ref OMQ::UserApi::Workflow::QorusSubworkflowStepBase::skipSubworkflow() "QorusSubworkflowStepBase::skipSubworkflow()";
        please see that method for documentation

        @throw SUBWORKFLOW-ERROR in addition to exception thrown by the above function, this error is raised if this
        method is called when not in a workflow context

        @since Qorus 5.1.29
    */
    public static hash<auto> skipSubworkflow() {
%ifdef QorusHasWfApi
        return QorusSubworkflowStepBase::skipSubworkflow();
%else
        throw "SUBWORKFLOW-ERROR", "the skip subworkflow API can only be called in a workflow context";
%endif
    }

    #! Binds the given key to the asynchronous step
    /** This call is a wrapper for
        @ref OMQ::UserApi::Workflow::QorusAsyncStepBase::submitAsyncKey() "QorusAsyncStepBase::submitAsyncKey()";
        please see that method for documentation

        @throw ASYNC-STEP-ERROR in addition to exception thrown by the above function, this error is raised if this
        method is called when not in a workflow context

        @since Qorus 5.1.29
    */
    public static submitAsyncKey(string key) {
%ifdef QorusHasWfApi
        return QorusAsyncStepBase::submitAsyncKey(key);
%else
        throw "ASYNC-STEP-ERROR", "the submit async key API can only be called in a workflow context";
%endif
    }

    #! This method will skip the execution of an asynchronous step
    /** This call is a wrapper for
        @ref OMQ::UserApi::Workflow::QorusAsyncStepBase::skipAsyncStep() "QorusAsyncStepBase::skipAsyncStep()";
        please see that method for documentation

        @throw ASYNC-STEP-ERROR in addition to exception thrown by the above function, this error is raised if this
        method is called when not in a workflow context

        @since Qorus 5.1.29
    */
    public static skipAsyncStep() {
%ifdef QorusHasWfApi
        return QorusAsyncStepBase::skipAsyncStep();
%else
        throw "ASYNC-STEP-ERROR", "the skip async step API can only be called in a workflow context";
%endif
    }

    #! binds a workflow synchronization event based on the event key to a workflow synchronization event step (type @ref OMQ::ExecEvent)
    /** This call is a wrapper for
        @ref OMQ::UserApi::Workflow::QorusEventStepBase::bindEvent() "QorusEventStepBase::bindEvent()";
        please see that method for documentation

        @throw EVENT-STEP-ERROR in addition to exception thrown by the above function, this error is raised if this
        method is called when not in a workflow context

        @since Qorus 5.1.29
    */
    public static bindEvent(string eventkey) {
%ifdef QorusHasWfApi
        return QorusEventStepBase::bindEvent(eventkey);
%else
        throw "EVENT-STEP-ERROR", "the bind event API can only be called in a workflow context";
%endif
    }

    #! binds a workflow synchronization event based on the event key to a workflow synchronization event step (type @ref OMQ::ExecEvent) only if the event has not yet been posted; if the event has already been posted, then an ALREADY-POSTED exception is raised
    /** This call is a wrapper for
        @ref OMQ::UserApi::Workflow::QorusEventStepBase::bindEventUnposted() "QorusEventStepBase::bindEventUnposted()";
        please see that method for documentation

        @throw EVENT-STEP-ERROR in addition to exception thrown by the above function, this error is raised if this
        method is called when not in a workflow context

        @since Qorus 5.1.29
    */
    public static bindEventUnposted(string eventkey) {
%ifdef QorusHasWfApi
        return QorusEventStepBase::bindEventUnposted(eventkey);
%else
        throw "EVENT-STEP-ERROR", "the bind event unposted API can only be called in a workflow context";
%endif
    }

    #! skips a workflow synchronization event step
    /** This call is a wrapper for
        @ref OMQ::UserApi::Workflow::QorusEventStepBase::skipEvent() "QorusEventStepBase::skipEvent()";
        please see that method for documentation

        @throw EVENT-STEP-ERROR in addition to exception thrown by the above function, this error is raised if this
        method is called when not in a workflow context

        @since Qorus 5.1.29
    */
    public static skipEvent() {
%ifdef QorusHasWfApi
        return QorusEventStepBase::skipEvent();
%else
        throw "EVENT-STEP-ERROR", "the skip event API can only be called in a workflow context";
%endif
    }

    #! leaves feedback for a parent workflow
    /** This call is a wrapper for
        @ref OMQ::UserApi::Workflow::WorkflowApi::leaveParentFeedback() "WorkflowApi::leaveParentFeedback()";
        please see that method for documentation

        @throw FEEDBACK-ERROR in addition to exception thrown by the above function, this error is raised if this
        method is called when not in a workflow context

        @since Qorus 6.0
    */
    static leaveParentFeedback(string key, auto value) {
%ifdef QorusHasWfApi
        WorkflowApi::leaveParentFeedback(key, value);
%else
        throw "FEEDBACK-ERROR", "the leave parent feedback API can only be called in a workflow context";
%endif
    }

    #! gets feedback from a child workflow order with the given key
    /** This call is a wrapper for
        @ref OMQ::UserApi::Workflow::WorkflowApi::getChildFeedback() "WorkflowApi::getChildFeedback()";
        please see that method for documentation

        @throw FEEDBACK-ERROR in addition to exception thrown by the above function, this error is raised if this
        method is called when not in a workflow context

        @since Qorus 6.0
    */
    static auto getChildFeedback(string key) {
%ifdef QorusHasWfApi
        return WorkflowApi::getChildFeedback(key);
%else
        throw "FEEDBACK-ERROR", "the get child feedback API can only be called in a workflow context";
%endif
    }

    #! Returns @ref True if the code is executing in an immediate workflow context, @ref False if not
    /** @return @ref True if the code is executing in an immediate workflow context, @ref False if not

        @since Qorus 6.0
    */
    static bool isWorkflowContext() {
%ifdef QorusCore
        if (tld && tld.isWorkflowContext()) {
            return True;
        }
%endif

%ifdef QorusQwfServer
        return True;
%else
        return False;
%endif
    }

    #! Returns @ref True if the code is executing in an immediate service context, @ref False if not
    /** @return @ref True if the code is executing in an immediate service context, @ref False if not

        @since Qorus 6.0
    */
    static bool isServiceContext() {
%ifdef QorusCore
        if (tld && tld.isServiceContext()) {
            return True;
        }
%endif
%ifdef QorusQsvcServer
        return True;
%else
        return False;
%endif
    }

    #! Returns @ref True if the code is executing in an immediate job context, @ref False if not
    /** @return @ref True if the code is executing in an immediate job context, @ref False if not

        @since Qorus 6.0
    */
    static bool isJobContext() {
%ifdef QorusCore
        if (tld && tld.isJobContext()) {
            return True;
        }
%endif

%ifdef QorusQjobServer
        return True;
%else
        return False;
%endif
    }

%ifdef QorusClient
    static clientInit() {
        QorusClient::initFast();
    }
%endif
}
