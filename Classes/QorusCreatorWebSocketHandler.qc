# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

hashdecl WsApiArgInfo {
    string type;
    bool required = False;
    hash<auto> allowed_values;
}

hashdecl TabObjectInfo {
    string type;
    int id;
}

class QorusCreatorWebSocketConnection inherits public WebSocketConnection {
    public {
        #! Field updated
        /** arg:
            - \c type: (string) object type (ex: \c job)
            - \c id: (int) object ID to use (reservation or real ID)
            - \c field: (string) field name
            - \c value: (auto) any value for the field
            - \c isAdvanced: (bool) if the field is advanced or not
        */
        const WSCAPI_FIELD_UPDATED = "FIELD-UPDATED";

        /** arg:
            - \c type: object type (ex: \c job)
            - \c id: ID used in open call
            - \c code: (string) source code
        */
        const WSCAPI_CODE_UPDATED = "CODE-UPDATED";

        #! Interface open
        /** arg:
            - \c type: object type (ex: \c job)
            - \c id: ID to use (not reserved - real ID)
        */
        const WSCAPI_OPEN_INTERFACE = "OPEN-INTERFACE";

        #! Interface closed
        /** arg:
            - \c type: object type (ex: \c job)
            - \c id: ID used in open call

            @note If the interface is not open, no error is raised
        */
        const WSCAPI_CLOSE_INTERFACE = "CLOSE-INTERFACE";

        #! Show current reservations
        const WSCAPI_SHOW_LOCKS = "SHOW-LOCKS";

        #! Server -> Client msg
        const WSCAPI_ERROR = "ERROR";
        const WSCAPI_CONNECTION_ID = "CONNECTION-ID";
        const WSCAPI_LOCK_INFO = "LOCK-INFO";

        /** arg:
            - \c type: object type (ex: \c job)
            - \c id: ID used in open call
            - \c field: field name
            - \c metadata:
                - \c isValid: field value is valid?
                - \c messages: list of hashes:
                    - \c intent: info | success | danger | pending | warning
                    - \c content: a message
                - \c items: list of items in case reference data has changed
            - \c show_notifications: list of hashes:
              - \c title: string
              - \c content: string
              - \c duration: number
              - \c id: string
              - \c type: info | success | danger | pending | warning
        */
        const WSCAPI_SERVER_FIELD_UPDATED = "SERVER-FIELD-UPDATED";

        /** arg:
            - \c type: object type (ex: \c job)
            - \c id: ID used in open call
            - \c [code: (string) source code]
            - \c [config-items]: (list) list of config item hashes)
        */
        const WSCAPI_SERVER_TAB_UPDATED = "SERVER-TAB-UPDATED";

        /** arg:
            - \c type: object type (ex: \c job)
            - \c id: ID used in open call
            - \c cid: the cid acquiring the lock
        */
        const WSCAPI_INTERFACE_OPENED = "INTERFACE-OPENED";

        /** arg:
            - \c type: object type (ex: \c job)
            - \c id: ID used in open call
            - \c cid: the cid that released the lock
            - \c name: name of the interface released
            - \c fields: field data for the interface released
            - \c code: source code of the interface released
        */
        const WSCAPI_INTERFACE_RELEASED = "INTERFACE-RELEASED";

        /** arg:
            - \c type: object type (ex: \c job)
            - \c id: ID used in open call
            - \c name: name of the interface released
            - \c fields: field data for the interface released
            - \c code: source code of the interface released
        */
        const WSCAPI_INTERFACE_UPDATED = "INTERFACE-UPDATED";

        const IdArg = <WsApiArgInfo>{
            "type": Type::Int,
            "required": True,
        };

        const RequiredStringArg = <WsApiArgInfo>{
            "type": Type::String,
            "required": True,
        };

        const InterfaceTypeArg = <WsApiArgInfo>{
            "type": Type::String,
            "required": True,
            "allowed_values": {
                "job": True,
                "class": True,
                "connection": True,
            },
        };

        const ValueArg = <WsApiArgInfo>{
            "type": "any",
        };

        const OptionalBoolArg = <WsApiArgInfo>{
            "type": Type::Boolean,
        };

        const HashStart = "####### GENERATED SECTION! DON'T EDIT! ########";
        const HashEnd = "####### GENERATED SECTION! DON'T EDIT! ########";

        const SlashStart = "// ==== GENERATED SECTION! DON'T EDIT! ==== //";
        const SlashEnd = "// ======== GENERATED SECTION END ========= //";

        #! Generated code info
        const GeneratedCodeInfo = {
            "qore": {
                "start": HashStart,
                "end": HashEnd,
            },
            "python": {
                "start": HashStart,
                "end": HashEnd,
            },
            "java": {
                "start": SlashStart,
                "end": SlashEnd,
            },
        };

        #! WS Creator API Descriptions
        const WSCAPIS = {
            WSCAPI_FIELD_UPDATED: {
                "type": InterfaceTypeArg,
                "id": IdArg,
                "field": RequiredStringArg,
                "value": ValueArg,
                "isAdvanced": OptionalBoolArg,
            },
            WSCAPI_CODE_UPDATED: {
                "type": InterfaceTypeArg,
                "id": IdArg,
                "code": RequiredStringArg,
            },
            WSCAPI_OPEN_INTERFACE: {
                "type": InterfaceTypeArg,
                "id": IdArg,
            },
            WSCAPI_CLOSE_INTERFACE: {
                "type": InterfaceTypeArg,
                "id": IdArg,
            },
            WSCAPI_SHOW_LOCKS: {},
        };

        #! Qorus server tab token ID
        const WSCAPI_TAB_TOKEN_QORUS = "qorus";

        #! WS Creator API Response Code: OK
        const WSCAPI_RESPONSE_OK = "OK";

        #! WS Creator API Response Code: ERR
        const WSCAPI_RESPONSE_ERR = "ERR";

        #! WS Creator API Error Code: BAD-ARGS
        const WSCAPI_ERR_BAD_ARGS = "BAD-ARGS";

        #! WS Creator API Error Code: UNKNOWN-API
        const WSCAPI_ERR_UNKNOWN_API = "UNKNOWN-API";

        #! WS Creator API Error Code: BAD-API-ARGS
        const WSCAPI_ERR_BAD_API_ARGS = "BAD-API-ARGS";

        #! WS Creator API Error Code: API-ERROR
        const WSCAPI_ERR_API_ERROR = "API-ERROR";
    }

    private {
        #! WebSocket call context
        hash<auto> cx;

        #! Open object amd object cache lock (always used for writes)
        Mutex omap_lock();

        #! Open objects; will be released when the connection is closed; keys are tab_token values
        hash<string, hash<TabObjectInfo>> omap;

        #! Object attribute hash while editing; tab_token -> attributes
        hash<string, hash<auto>> obj_cache;

        #! object type -> field name -> field info
        static hash<string, hash<string, hash<FieldInfo>>> fmap;

        #! object type -> field name -> group name
        static hash<string, hash<string, string>> gmap;

        #! Mutex for fmap
        static Mutex fmap_lock();

        #! Name to version map
        const NameVersionMap = {
            "name": "version",
            "version": "name",
        };

        #! Minimum attributes to do code generation
        const MinCodeMap = {
            "name": True,
            "language": True,
        };

        #! Attributes that affect code generation
        const OtherCodeMap = {
            "base_class_name": True,
            "class_name": True,
        };

        #! Attributes that affect code generation
        const CodeAttrMap = MinCodeMap + OtherCodeMap;

        #! Default base class names per object type
        const BaseClassMap = {
            "job": "QorusJob",
            "service": "QorusService",
        };

        #! Maps object types to Python modules
        const PythonApiModuleMap = {
            "job": "job",
            "service": "svc",
            "workflow": "wf",
        };

        #! Maps object types to Java imports
        const JavaApiImportMap = {
            "job": "qore.OMQ.UserApi.Job.QorusJob",
            "service": "qore.OMQ.UserApi.Service.QorusService",
            "workflow": "qore.OMQ.UserApi.Workflow.QorusWorkflow",
        };
    }

    constructor(QorusCreatorWebSocketHandler handler, hash<auto> cx) : WebSocketConnection(handler) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, "WebSocketConnection open for %y", cx.user);
        Qorus.httpServer.logArgs(LoggerLevel::DEBUG, "WebSocketConnection details: %y", cx);
        self.cx = cx;

        # send cid
        sendResponse(-1, WSCAPI_TAB_TOKEN_QORUS, WSCAPI_CONNECTION_ID, {"cid": cx.id});
    }

    destructor() {
        QDBG_LOG("QorusCreatorWebSocketConnection::destructor() omap: %y", omap);

        # close all open interfaces and release reservations
        map Qorus.qmm.closeInterface($1.key, $1.value.type, $1.value.id, True), omap.pairIterator();
    }

    #! Receives an incoming message
    /** format: json hash:
        - id: (int) unique request ID (uniquess not checked; will be used in the response)
        - event: (string) the API command
        - args: (hash) optional arguments for \a event
    */
    gotMessage(string msg) {
        auto raw_message;
        try {
            raw_message = parse_json(msg);
            QDBG_LOG("gotMessage(): %y", raw_message);
        } catch (hash<ExceptionInfo> ex) {
            sendErrorResponse(-1, WSCAPI_TAB_TOKEN_QORUS, WSCAPI_ERR_BAD_ARGS, "invalid message; cannot parse as JSON: %s: %s",
                ex.err, ex.desc);
            return;
        }
        if (raw_message.typeCode() != NT_HASH) {
            sendErrorResponse(-1, WSCAPI_TAB_TOKEN_QORUS, WSCAPI_ERR_BAD_ARGS, "invalid message; got type %y; expecting \"hash\"",
                raw_message.type());
            return;
        }
        hash<auto> message = raw_message;

        if (message.tab_token.typeCode() != NT_STRING) {
            sendErrorResponse(-1, WSCAPI_TAB_TOKEN_QORUS, WSCAPI_ERR_BAD_ARGS, "missing or invalid 'tab_token' arg; got "
                "type %y (%y); expecting \"string\"", message.tab_token.type(), message.tab_token);
            return;
        }

        if (message.event.typeCode() != NT_STRING) {
            sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_BAD_ARGS, "missing or invalid 'event' arg; got type "
                "%y (%y); expecting \"string\"", message.event.type(), message.event);
            return;
        }

        if (exists message.id) {
            if (message.id.typeCode() != NT_INT) {
                sendErrorResponse(-1, message.tab_token, WSCAPI_ERR_BAD_ARGS, "missing or invalid 'id' arg; got type %y (%y); "
                    "expecting \"integer\"", message.id.type(), message.id);
                return;
            }
        } else {
            message.id = 0;
        }

        if (exists message.args && message.args.typeCode() != NT_HASH) {
            sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_BAD_ARGS, "invalid 'args' arg; got type %y (%y); "
                "expecting \"hash\"", message.args.type(), message.args);
            return;
        }

        *hash<string, hash<WsApiArgInfo>> api = WSCAPIS{message.event};
        if (!exists api) {
            sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_UNKNOWN_API, "unknown command %y; known commands: %y",
                message.event, keys WSCAPIS);
            return;
        }
        if (checkApiArgs(api, message)) {
            return;
        }

        QDBG_LOG("CREATOR WS < cid %d message: %y", cx.id, message);

        try {
            switch (message.event) {
                case WSCAPI_FIELD_UPDATED: {
                    processFieldUpdated(message);
                    break;
                }

                case WSCAPI_CODE_UPDATED: {
                    processCodeUpdated(message);
                    break;
                }

                case WSCAPI_OPEN_INTERFACE: {
                    editLock(message.tab_token, message.args.type, message.args.id);
                    break;
                }

                case WSCAPI_CLOSE_INTERFACE: {
                    releaseEditLock(message.tab_token, message.args.type, message.args.id);
                    break;
                }

                case WSCAPI_SHOW_LOCKS: {
                    sendResponse(message.id, message.tab_token, WSCAPI_LOCK_INFO, {
                        "reservation_info": Qorus.qmm.getReservationMap(){message.tab_token},
                        "open_object": omap{message.tab_token},
                    });
                    break;
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "error processing WS event %y (cid: %y tab_token: %y): %s", message.event,
                cx.id, message.tab_token, get_exception_string(ex));
            sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_API_ERROR, ex, "event %y error: %s: %s",
                message.event, ex.err, ex.desc);
            return;
        }
    }

    editLock(string tab_token, string type, int id) {
        *hash<auto> current_data = Qorus.qmm.openInterface(cx.id, tab_token, type, id);
        QDBG_LOG("CREATOR: type %y id %y current_data: %y", type, id, current_data);

        AutoLock al(omap_lock);

        # automatically close any open interface
        *hash<TabObjectInfo> info = omap{tab_token};
        if (info && (info.type != type || info.id != id)) {
            # close interface also releases any reservations held
            Qorus.qmm.closeInterface(tab_token, info.type, info.id);
            remove obj_cache{tab_token};
        }

        omap{tab_token} = <TabObjectInfo>{
            "type": type,
            "id": id,
        };

        # populate initial data for object if possible
        if (current_data) {
            obj_cache{tab_token} = current_data;
        }
    }

    releaseEditLock(string tab_token, string type, int id) {
        # close interface also releases any reservations heldshow_not
        Qorus.qmm.closeInterface(tab_token, type, id);
        remove omap{tab_token};
        remove obj_cache{tab_token};
    }

    sourceCodeUpdated(string tab_token, string type, int id, string source_code) {
        sendResponse(-1, tab_token, WSCAPI_SERVER_TAB_UPDATED, {
            "type": type,
            "id": id,
            "code": source_code,
        });
    }

    #! Handles CODE-UPDATED messages
    processCodeUpdated(hash<auto> message) {
        string type = message.args.type;
        string id = message.args.id;
        string source_code = message.args."code";
        try {
            Qorus.qmm.codeUpdated(message.tab_token, type, id, source_code);
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "error processing WS event %y (cid: %y tab_token: %y): %s", message.event,
                cx.id, message.tab_token, get_exception_string(ex));
            sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_API_ERROR, ex, "event %y error: %s: %s",
                message.event, ex.err, ex.desc);
        }
    }

    #! Handles FIELD-UPDATED messages
    processFieldUpdated(hash<auto> message, *bool no_complementary_field, *string invalid_other, *hash<auto> metadata) {
        # check new field value
        string type = message.args.type;
        string field_name = message.args.field;
        auto value = message.args.value;

        bool name_reservation_only = QorusMapManager::UniqueNameMap{type} ?? False;

        hash<auto> msg_info = message.args{"type", "id", "field"};

        bool valid;
        auto old_field_value;
        try {
            # first check field validity
            hash<FieldInfo> field = getFieldInfo(type, field_name, \msg_info.group);
            QDBG_LOG("field: %y", field);
            # treat an empty string / hash / list as no value
            if (!value.val()) {
                remove value;
            }

            int id = message.args.id;

            if (!exists value) {
                {
                    AutoLock al(omap_lock);
                    old_field_value = remove obj_cache{message.tab_token}{field_name};
                }
                valid = field.isAdvanced ?? False;
                if (!valid && message.args.hasKey("value")) {
                    # release any reservation
                    if (exists old_field_value
                        && (field_name == "name" || (!name_reservation_only && field_name == "version"))) {
                        Qorus.qmm.releaseReservationForTabToken(message.tab_token);
                    }
                    throw WEBIDE_ERROR_INVALID_VALUE, sprintf("%s %s %y is invalid because it is empty", type,
                        field_name, value), "empty-value";
                }
            } else {
                # check value type against the field's declared type
                {
                    string qore_type = FieldTypeQoreTypeMap{field.type};
                    if (qore_type != "auto" && value.type() != qore_type) {
                        # NOTE: the expected type is returned as the "contentMeta" value in the response message
                        throw WEBIDE_ERROR_INVALID_TYPE, sprintf("%s %s %y is invalid because it has type %y, "
                            "whereas type %y was expected", type, field_name, value, value.type, qore_type),
                            qore_type;
                    }

                    if (field.subtype && (*code check = FieldSubtypeMap{field.subtype})) {
                        check(value);
                    }
                }

                valid = True;
                {
                    AutoLock al(omap_lock);
                    old_field_value = obj_cache{message.tab_token}{field_name};
                    obj_cache{message.tab_token}{field_name} = value;
                }
            }
            metadata += {
                "isValid": valid,
                "messages": (),
            };
            *hash<auto> cached_data = obj_cache{message.tab_token};
            if (invalid_other) {
                QDBG_ASSERT(!name_reservation_only);
                QDBG_ASSERT(no_complementary_field);
                remove cached_data{invalid_other};
            }
            Qorus.qmm.fieldUpdated(message.tab_token, type, id, field_name, value, cached_data);
            QDBG_LOG("CREATOR: field: %y old value: %y new value: %y", field_name, old_field_value, value);
            if (old_field_value != value) {
                # see if we can and should do codegen
                if (CodeObjectMap{type} && CodeAttrMap{field_name}) {
                    hash<auto> code_attrs;
                    # see if we have the minimum attributes to do code generation
                    bool ok = True;
                    foreach string attr in (keys MinCodeMap) {
                        auto val = field_name == attr ? value : cached_data{attr};
                        if (!exists val) {
                            ok = False;
                            break;
                        }
                        code_attrs{attr} = val;
                    }
                    if (ok) {
                        # add additional attributes
                        foreach string attr in (keys OtherCodeMap) {
                            auto val = field_name == attr ? value : cached_data{attr};
                            if (exists val) {
                                code_attrs{attr} = val;
                            }
                        }
                        # generate class name if necessary
                        if (!code_attrs.class_name) {
                            code_attrs.class_name = field_name == "name" ? value : cached_data.name;
                            code_attrs.class_name =~ s/[^a-z0-9_]//ig;
                        }
                        # generate base class name if necessary
                        if (code_attrs.base_class_name) {
                            # remove version label
                            code_attrs.base_class_name =~ s/ v.*$//;
                            code_attrs.base_class_name =~ s/[^a-z0-9_]//ig;
                        } else if (*string base_class_name = BaseClassMap{type}) {
                            code_attrs.base_class_name = base_class_name;
                            code_attrs.base_class_api = True;
                        }

                        regenerateSourceCode(message.id, message.tab_token, type, id, code_attrs);
                    }
                }
            }
            # always send the value
            metadata.value = message.args.value;
        } catch (hash<ExceptionInfo> ex) {
            QDBG_LOG("FIELD-UPDATED error: %s", get_exception_string(ex));
            string content = ex.err;
            content =~ tr/A-Z/a-z/;
            valid = False;
            if (exists message.args.value) {
                hash<auto> err_msg = {
                    "intent": "danger",
                    "content": content,
                };
                if (ex.arg.typeCode() == NT_STRING) {
                    err_msg.contentMeta = ex.arg;
                }
                metadata += {
                    "isValid": valid,
                    "messages": (err_msg,),
                };
            } else {
                # do not send messages when the value is null, just leave the field as invalid
                metadata += {
                    "isValid": valid,
                    "messages": (),
                };
            }
        }

        # validate connection URL
        *hash<ConnectionSchemeInfo> new_scheme_info;
        if (metadata.isValid && type == "connection" && field_name == "url") {
            *string new_scheme = value;
            if (new_scheme) {
                new_scheme =~ s/^(.*):\/\/.*$/$1/;
                new_scheme_info = ConnectionSchemeCache::getScheme(new_scheme);
            }

            if (!new_scheme_info) {
                hash<auto> err_msg = {
                    "intent": "danger",
                    "content": "invalid-value",
                    "contentMeta": "unknown-scheme",
                };
                metadata += {
                    "isValid": False,
                    "messages": (err_msg,),
                };
            }
        }

        # NOTE: we need to send this message to the client even when the value has not changed
        sendResponse(message.id, message.tab_token, WSCAPI_SERVER_FIELD_UPDATED, msg_info +
            {"metadata": metadata});
        # send out a reciprocal message for interfaces with complex reservation requirements
        # when "name" or "version" is processed
        if (!no_complementary_field) {
            if (!name_reservation_only && (*string other = NameVersionMap{field_name})
                && exists (auto other_value = obj_cache{message.tab_token}{other})) {
                message.args.field = other;
                message.args.value = other_value;

                processFieldUpdated(message, True, !valid ? field_name : NOTHING);
            } else if (type == "connection" && field_name == "url") {
                checkUrlUpdated(message, old_field_value, new_scheme_info);
            }
        }
    }

    #! Check if scheme has changed
    private checkUrlUpdated(hash<auto> message, *string old_scheme, *hash<auto> new_scheme_info) {
        # see if options have changed
        *hash<ConnectionSchemeInfo> old_scheme_info;
        if (old_scheme) {
            old_scheme =~ s/^(.*):\/\/.*$/$1/;
            old_scheme_info = ConnectionSchemeCache::getScheme(old_scheme);
        }
        QDBG_LOG("url: %y old scheme: %y new scheme: %y", message.args.value, old_scheme, exists new_scheme_info);
        if (new_scheme_info) {
            #QDBG_LOG("old opts: %y new opts: %y", old_scheme_info.options, new_scheme_info.options);
            if (new_scheme_info.options != old_scheme_info.options) {
                # generate a message with new options
                message.args.field = "options";
                # move any common options to new options, if possible
                message.args.value = NOTHING;
                if (*hash<auto> old_value = obj_cache{message.tab_token}.options) {
                    message.args.value = old_value{keys new_scheme_info.options};
                }
                hash<auto> metadata.fields = CreatorConnectionRestClassBase::getOptionFields(\message.args.value,
                    new_scheme_info.options);
                metadata.isDisabled = False;
                #QDBG_LOG("fields: %N", message.fields);
                processFieldUpdated(message, True, NOTHING, metadata);
            }
            # if the options are the same, there is no message to send
            return;
        }
        # emit message if options status is changing
        if (old_scheme_info && !new_scheme_info) {
            message.args.field = "options";
            remove message.args.value;
            hash<auto> metadata.isDisabled = True;
            processFieldUpdated(message, True, NOTHING, metadata);
        }
    }

    #! Need to regenerate source code
    private regenerateSourceCode(int mid, string tab_token, string type, int id, hash<auto> code_attrs) {
        string source;
        switch (code_attrs.language) {
            case "qore":
                source = regenerateQoreSourceCode(tab_token, type, id, code_attrs);
                break;

            case "python":
                source = regeneratePythonSourceCode(tab_token, type, id, code_attrs);
                break;

            case "java":
                source = regenerateJavaSourceCode(tab_token, type, id, code_attrs);
                break;
        }
        sendResponse(mid, tab_token, WSCAPI_SERVER_TAB_UPDATED, {
            "type": type,
            "id": id,
            "code": source,
        });
    }

    #! Need to regenerate Qore source code
    private string regenerateQoreSourceCode(string tab_token, string type, int id, hash<auto> code_attrs) {
        string source_code = sprintf("class %s ", code_attrs.class_name);
        if (code_attrs.base_class_name) {
            source_code += sprintf("inherits %s ", code_attrs.base_class_name);
        }
        source_code += "{\n}\n";

        return source_code;
    }

    #! Need to regenerate Python source code
    private string regeneratePythonSourceCode(string tab_token, string type, int id, hash<auto> code_attrs) {
        string source_code;
        if (code_attrs.base_class_api) {
            source_code = sprintf("from %s import %s\n\n", PythonApiModuleMap{type}, code_attrs.base_class_name);
        } else if (code_attrs.base_class_name) {
            source_code = sprintf("from qore.__root__ import %s\n\n", code_attrs.base_class_name);
        }
        source_code += sprintf("class %s", code_attrs.class_name);
        if (code_attrs.base_class_name) {
            source_code += sprintf("(%s)", code_attrs.base_class_name);
        }
        source_code += ":\n    pass\n";

        return source_code;
    }

    #! Need to regenerate Java source code
    private string regenerateJavaSourceCode(string tab_token, string type, int id, hash<auto> code_attrs) {
        string source_code;
        if (code_attrs.base_class_api) {
            source_code = sprintf("import %s;\n", JavaApiImportMap{type});
        } else if (code_attrs.base_class_name) {
            source_code = sprintf("import qore.%s;\n", code_attrs.base_class_name);
        }
        if (source_code) {
            source_code += "\n";
        }
        source_code += sprintf("class %s", code_attrs.class_name);
        if (code_attrs.base_class_name) {
            source_code += sprintf(" extends %s", code_attrs.base_class_name);
        }
        source_code += " {\n}\n";

        return source_code;
    }

    #! Dependency updated; need to update dependent fields in open tabs
    updateDependency(string type, int id, string name, *hash<auto> old_delta_info, *hash<auto> new_info) {
        QDBG_LOG("updateDependency() type: %y id: %y name: %y old: %y new: %y", type, id, name, old_delta_info, new_info);

        AutoLock al(omap_lock);
        foreach hash<auto> i in (omap.pairIterator()) {
            foreach hash<auto> msg_info in
                (CreatorBaseRestClass::doGetUpdatedFields(i.value.type, i.value.id, type, id, name)) {
                QDBG_LOG("updateDependency() tt: %y type: %y id: %d name: %y field: %y old: %y new: %y cache: %y", i.key, type, id, name, msg_info.field, old_delta_info, old_delta_info ? new_info{keys old_delta_info} : new_info, obj_cache);
                if (old_delta_info.label && obj_cache{i.key}{msg_info.field}) {
                    if (obj_cache{i.key}{msg_info.field}.typeCode() == NT_LIST) {
                        if (inlist(old_delta_info.label, obj_cache{i.key}{msg_info.field})) {
                            msg_info.metadata.value = obj_cache{i.key}{msg_info.field};
                            foreach auto v in (\msg_info.metadata.value) {
                                if (v == old_delta_info.label) {
                                    v = new_info.label;
                                }
                            }
                            obj_cache{i.key}{msg_info.field} = msg_info.metadata.value;
                            QDBG_LOG("updated value list %y => %y", msg_info.field, msg_info.metadata.value);
                        }
%ifdef QorusDebugInternals
                        else {
                            QDBG_LOG("value %y is not in list: %y", old_delta_info.label, obj_cache{i.key}{msg_info.field});
                        }
%endif
                    } else if (obj_cache{i.key}{msg_info.field} == old_delta_info.label) {
                        msg_info.metadata.value = new_info.label;
                        obj_cache{i.key}{msg_info.field} = msg_info.metadata.value;
                        QDBG_LOG("updated value %y => %y", msg_info.field, msg_info.metadata.value);
                    }
                }
%ifdef QorusDebugInternals
                if (!exists msg_info.metadata.value) {
                    QDBG_LOG("not updating tab: %y type: %y field: %y (val: %y)", i.key, type, msg_info.field, obj_cache{i.key}{msg_info.field});
                }
%endif
                msg_info.show_notifications = (
                    {
                        "title": "Field Externally Updated",
                        "content": "items-updated",
                        "duration": 3000,
                        "id": UUID::get(),
                        "type": "info",
                    },
                );
                sendResponse(-1, i.key, WSCAPI_SERVER_FIELD_UPDATED, msg_info);
            }
        }
    }

    #! Checks API arguments; returns 0 for OK, -1 for error
    private int checkApiArgs(hash<string, hash<WsApiArgInfo>> api, hash<auto> message) {
        foreach hash<auto> i in (message.args.pairIterator()) {
            *hash<WsApiArgInfo> arg = api{i.key};
            if (!arg) {
                sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_BAD_API_ARGS, "%y: invalid arg %y; known "
                    "args: %y", message.event, i.key, keys api);
                return -1;
            }
            if (!exists i.value) {
                if (arg.required) {
                    sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_BAD_API_ARGS, "%y: invalid arg %y "
                        "value %y; argument is required", message.event, i.key, i.value);
                    return -1;
                }
                continue;
            }
            if (arg.type != "any" && i.value.type() != arg.type) {
                sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_BAD_API_ARGS, "%y: invalid arg %y "
                    "type %y; expecting type %y (value %y)", message.event, i.key, i.value.type(), arg.type, i.value);
                return -1;
            }
            if (arg.allowed_values && !arg.allowed_values{i.value}) {
                sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_BAD_API_ARGS, "%y: invalid arg %y "
                    "value %y; valid values: %y", message.event, i.key, i.value, keys arg.allowed_values);
                return -1;
            }
            # remove arg in local copy; does not need to be checked afterwards
            remove api{i.key};
        }

        # ensure all required args are present
        foreach hash<auto> i in (api.pairIterator()) {
            if (i.value.required && !message.args.hasKey(i.key)) {
                sendErrorResponse(message.id, message.tab_token, WSCAPI_ERR_BAD_API_ARGS, "%y (tab_token %y): "
                    "missing required arg %y in API request: args provided: %y", message.event, message.tab_token,
                    i.key, message.args);
                return -1;
            }
        }
        return 0;
    }

    static string getMessage(int id, string tab_token, string event, *hash<auto> info) {
        return make_json({
            "id": id,
            "tab_token": tab_token,
            "event": event,
            "info": info,
        });
    }

    private static hash<FieldInfo> getFieldInfo(string type, string field, reference<string> group) {
        *hash<FieldInfo> rv = fmap{type}{field};
        if (!rv) {
            fmap_lock.lock();
            on_exit fmap_lock.unlock();

            # check again inside the lock
            rv = fmap{type}{field};
            if (!rv && !fmap{type}) {
                fmap{type} = CreatorBaseRestClass::doGetFieldHash(type, \gmap{type});
                rv = fmap{type}{field};
            }
            if (!rv) {
                throw "INVALID-FIELD", sprintf("field %y is unknown in type %y; known fields: %y", field, type,
                    keys fmap{type});
            }
        }
        QDBG_ASSERT(gmap{type}{field});
        group = gmap{type}{field};
        return rv;
    }

    private sendResponse(int id, string tab_token, string event, *hash<auto> info) {
        QDBG_LOG("CREATOR WS > cid: %d id: %d tab_token: %y event: %y info: %y", cx.cid, id, tab_token, event, info);
        send(getMessage(id, tab_token, event, info));
    }

    private sendErrorResponse(int id, string tab_token, string error, string desc) {
        sendErrorResponseArgs(id, tab_token, error, NOTHING, desc, argv);
    }

    private sendErrorResponse(int id, string tab_token, string error, *hash<auto> info, string desc) {
        sendErrorResponseArgs(id, tab_token, error, info, desc, argv);
    }

    private sendErrorResponseArgs(int id, string tab_token, string error, *hash<auto> info, string desc,
            *softlist<auto> args) {
        hash<auto> msg_info = {
            "error": error,
            "desc": vsprintf(desc, args),
        } + (info ? {"info": info} : NOTHING);
        QDBG_LOG("CREATOR WS > cid: %d tab_token: %y event: %y info: %y", cx.cid, tab_token, WSCAPI_ERROR, msg_info);
        send(getMessage(id, tab_token, WSCAPI_ERROR, msg_info));
    }
}

class QorusCreatorWebSocketHandler inherits public WebSocketHandler {
    public {
        #! Dependent objects; reference fields need to updated
        const DepMap = {
            "class": True,
            "event": True,
            "fsm": True,
            "group": True,
            "mapper": True,
            "pipeline": True,
            "queue": True,
            "step": True,
        };
    }

    constructor() : WebSocketHandler(Qorus.qorusAuth) {
    }

    QorusCreatorWebSocketConnection getConnectionImpl(hash<auto> cx, hash<auto> hdr, string cid) {
        return new QorusCreatorWebSocketConnection(self, cx);
    }

    sourceCodeUpdated(int cid, string tab_token, string type, int id, string source_code) {
        *QorusCreatorWebSocketConnection conn = ch{cid};
        if (!conn) {
            throw "CONNECTION-ERROR", sprintf("cid %y does not belong to any active connection", cid);
        }
        conn.sourceCodeUpdated(tab_token, type, id, source_code);
    }

    editLock(int cid, string tab_token, string type, int id) {
        *QorusCreatorWebSocketConnection conn = ch{cid};
        if (!conn) {
            throw "CONNECTION-ERROR", sprintf("cid %y does not belong to any active connection", cid);
        }
        conn.editLock(tab_token, type, id);
    }

    releaseEditLock(int cid, string tab_token, string type, int id) {
        *QorusCreatorWebSocketConnection conn = ch{cid};
        if (!conn) {
            throw "CONNECTION-ERROR", sprintf("cid %y does not belong to any active connection", cid);
        }
        conn.releaseEditLock(tab_token, type, id);
    }

    broadcastInterfaceOpened(int cid, string type, int id) {
        sendAll(QorusCreatorWebSocketConnection::getMessage(-1, QorusCreatorWebSocketConnection::WSCAPI_TAB_TOKEN_QORUS,
            QorusCreatorWebSocketConnection::WSCAPI_INTERFACE_OPENED, {
            "type": type,
            "id": id,
            "cid": cid,
        }));
    }

    broadcastInterfaceReleased(int cid, string type, int id, string name, list<hash<FieldGroupInfo>> fields, *string source_code) {
        hash<auto> msg = {
            "type": type,
            "id": id,
            "cid": cid,
            "name": name,
            "fields": fields,
        };
        if (source_code) {
            msg."code" = source_code;
        }
        QDBG_LOG("QorusCreatorWebSocketHandler::broadcastInterfaceReleased() %s: %y", QorusCreatorWebSocketConnection::WSCAPI_INTERFACE_RELEASED, msg);
        sendAll(QorusCreatorWebSocketConnection::getMessage(-1, QorusCreatorWebSocketConnection::WSCAPI_TAB_TOKEN_QORUS,
            QorusCreatorWebSocketConnection::WSCAPI_INTERFACE_RELEASED, msg));
    }

    broadcastInterfaceUpdated(string type, int id, string name, list<hash<FieldGroupInfo>> fields, *string source_code,
            *hash<auto> old_delta_info, hash<auto> new_info) {
        hash<auto> msg = {
            "type": type,
            "id": id,
            "name": name,
            "fields": fields,
        };
        if (source_code) {
            msg."code" = source_code;
        }
        sendAll(QorusCreatorWebSocketConnection::getMessage(-1, QorusCreatorWebSocketConnection::WSCAPI_TAB_TOKEN_QORUS,
            QorusCreatorWebSocketConnection::WSCAPI_INTERFACE_UPDATED, msg));

        # special processing for dependent objects
        if (!DepMap{type}) {
            return;
        }

        # see if the update is relevant; return if not
        if (!old_delta_info.name && (!QorusMapManager::UniqueNameMap{type} || !old_delta_info.version)) {
            return;
        }

        # fix the name if necessary
        switch (type) {
            case "class": {
                if (exists old_delta_info.name || exists old_delta_info.version) {
                    old_delta_info.label = sprintf("%s v%s", old_delta_info.name ?? new_info.name,
                        old_delta_info.version ?? new_info.version);
                    new_info.label = sprintf("%s v%s", new_info.name, new_info.version);
                }
                break;
            }
            default: {
                if (exists old_delta_info.name) {
                    old_delta_info.label = old_delta_info.name ?? new_info.name;
                    new_info.label = new_info.name;
                }
                break;
            }
        }

        rwl.readLock();
        on_exit rwl.readUnlock();

        map $1.updateDependency(type, id, name, old_delta_info, new_info), ch.iterator();
    }

    broadcastInterfaceCreated(string type, int id, string name, hash<auto> new_info) {
        # special processing for dependent objects
        if (!DepMap{type}) {
            return;
        }

        # fix the name if necessary
        switch (type) {
            case "class": {
                new_info.label = sprintf("%s v%s", new_info.name, new_info.version);
                break;
            }
            default: {
                new_info.label = new_info.name;
                break;
            }
        }

        rwl.readLock();
        on_exit rwl.readUnlock();

        map $1.updateDependency(type, id, name, NOTHING, new_info), ch.iterator();
    }

    broadcastInterfaceDeleted(string type, int id, string name, hash<auto> old_info) {
        # special processing for dependent objects
        if (!DepMap{type}) {
            return;
        }

        # fix the name if necessary
        switch (type) {
            case "class": {
                old_info.label = sprintf("%s v%s", old_info.name, old_info.version);
                break;
            }
            default: {
                old_info.label = old_info.name;
                break;
            }
        }

        rwl.readLock();
        on_exit rwl.readUnlock();

        map $1.updateDependency(type, id, name, old_info), ch.iterator();
    }

    logInfo(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::INFO, "remote command WS INFO: " + fmt, argv);
    }

    logError(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::ERROR, "remote command WS ERROR: " + fmt, argv);
    }

    logDebug(string fmt) {
        Qorus.httpServer.logArgs(LoggerLevel::DEBUG, "remote command WS DEBUG: " + fmt, argv);
    }
}
