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

# field types
const FT_Int = "int";
const FT_Bool = "bool";
const FT_String = "string";
const FT_LongString = "long-string";
const FT_ByteSize = "byte-size";
const FT_Url = "url";
const FT_List = "list";
const FT_Hash = "hash";
const FT_Enum = "enum";
const FT_Auto = "auto";
const FT_Cron = "cron";
const FT_Date = "date";

const FieldTypeQoreTypeMap = {
    FT_Int: Type::Int,
    FT_Bool: Type::Boolean,
    FT_String: Type::String,
    FT_LongString: Type::String,
    FT_ByteSize: Type::String,
    FT_Url: Type::String,
    FT_List: Type::List,
    FT_Hash: Type::Hash,
    FT_Enum: Type::String,
    FT_Auto: "auto",
    FT_Cron: Type::String,
    FT_Date: Type::Date,
};

const FieldSubtypeMap = {
    # NOTE: the qorus-identifier subtype is not applied directly to names subject to reservation logic
    "qorus-identifier": sub (string value) {
        # UTF-8 alphanumeric, underscore, or dash characters
        if (value !~ /^[[:alnum:]_-]+$/u) {
            throw WEBIDE_ERROR_INVALID_VALUE, sprintf("%y is not a valid Qorus name identifier", value),
                "invalid-characters-in-value";
        }
    },
    # for strings that must be valid Qore / Python / Java identifiers
    "identifier": sub (string value) {
        # must begin with an underscore or ASCII alphabetic character and then be followed by zero or more ASCII
        # alphanumeric characters or underscores
        if (value !~ /^[a-z_][a-z0-9_]*$/i) {
            throw WEBIDE_ERROR_INVALID_VALUE, sprintf("%y is not a valid identifier", value), "invalid-identifier";
        }
    },
    "cron-string": sub (string value) {
        *list<*string> l = value.split(" ");
        if (l.size() != 5) {
            throw WEBIDE_ERROR_INVALID_VALUE, sprintf("%y is not a valid cron string; requires 5 fields as \"minutes "
                "hours days months day_of_week\", got %d", value, l.size()), "invalid-cron-string";
        }
        try {
            CronTrigger cron_trigger(l[0], l[1], l[2], l[3], l[4]);
        } catch (hash<ExceptionInfo> ex) {
            throw WEBIDE_ERROR_INVALID_VALUE, sprintf("%y is not a valid cron string: %s", value, ex.desc),
                "invalid-cron-string";
        }
    },
};

hashdecl FieldItemInfo {
    string label;
    *string description;
    *string value;
    #! Base-64-encoded PNG image
    *string logo;
}

hashdecl FieldInfo {
    string name;
    # see FieldTypeQoreTypeMap for valid field types
    string type;
    # see FieldSubtypeMap for valid field subtypes
    *string subtype;
    *string icon;
    # only for use with dynamically-generated fields - no translation possible here
    *string description;
    auto value;
    *list<hash<FieldInfo>> fields;
    *list<hash<FieldItemInfo>> items;
    *string selectLabel;
    *bool isAdvanced;
    *bool multiSelect;
    *bool withCreate;
    *bool markdown;
    *bool isValid;
    *bool isSensitive;
    *bool isDisabled;
    #! Should the items be shown in a modal window with descriptions?
    *bool modal;
}

hashdecl FieldGroupInfo {
    string title;
    bool isOpen;
    list<hash<FieldInfo>> fields;
}

hashdecl IdFieldInfo {
    string type;
    int id;
    list<hash<FieldGroupInfo>> fields;
}

/** @REST /v6/creator

    This REST URI path provides actions and information for the base path of the creator API
*/
class CreatorRestClass inherits QorusRestClass {
    constructor() {
        addClass(new CreatorClassRestClass());
        addClass(new CreatorJobRestClass());
        addClass(new CreatorServiceRestClass());
        addClass(new CreatorConnectionRestClass());
        addClass(new CreatorConfigItemRestClass());
    }

    string name() {
        return "creator";
    }

    /** @REST GET action=locks

        @par Description
        Returns a list of lock and reservation information for debugging
    */
    hash<HttpHandlerResponseInfo> getLocks(hash<auto> cx, *hash<auto> args) {
        return RestHandler::makeResponse(200, Qorus.qmm.getEditLocks() + {
            "simple_reservations": Qorus.qmm.getSimpleNameReservations(),
            "complex_reservations": Qorus.qmm.getComplexNameReservations(),
            "reservation_map": Qorus.qmm.getReservationMap(),
        });
    }
}

const CommonDetailOptions = <FieldGroupInfo>{
    "title": "interface-detail-options",
    "isOpen": False,
    "fields": (
        <FieldInfo>{
            "name": "author",
            "type": FT_List,
            "withCreate": True,
            "isAdvanced": True,
            "icon": "User2Line",
        },
        <FieldInfo>{
            "name": "tags",
            "type": FT_Hash,
            "isAdvanced": True,
            "value": {},
        },
    ),
};

const InterfaceDetailOptions = CommonDetailOptions + <FieldGroupInfo>{
    "fields": CommonDetailOptions.fields + (
        <FieldInfo>{
            "name": "enabled",
            "type": FT_Bool,
            "isAdvanced": True,
            "value": True
        },
        <FieldInfo>{
            "name": "stack-size",
            "type": FT_ByteSize,
            "isAdvanced": True,
        },
    ),
};

const ConfigItemOptions = <FieldGroupInfo>{
    "title": "config-item-options",
    "isOpen": False,
    "fields": (
        <FieldInfo>{
            "name": "config_group",
            "type": FT_String,
            "value": "Default",
        },
        <FieldInfo>{
            "name": "name",
            "type": FT_String,
            "subtype": "qorus-identifier",
        },
        <FieldInfo>{
            "name": "description",
            "type": FT_LongString,
            "markdown": True,
        },
        <FieldInfo>{
            "name": "type",
            "type": FT_Enum,
            "items": (
                <FieldItemInfo>{
                    "label": "string",
                },
                <FieldItemInfo>{
                    "label": "int",
                },
                <FieldItemInfo>{
                    "label": "bool",
                },
                <FieldItemInfo>{
                    "label": "float",
                },
                <FieldItemInfo>{
                    "label": "date",
                },
                <FieldItemInfo>{
                    "label": "hash",
                },
                <FieldItemInfo>{
                    "label": "list",
                },
                <FieldItemInfo>{
                    "label": "*string",
                },
                <FieldItemInfo>{
                    "label": "*int",
                },
                <FieldItemInfo>{
                    "label": "*bool",
                },
                <FieldItemInfo>{
                    "label": "*float",
                },
                <FieldItemInfo>{
                    "label": "*date",
                },
                <FieldItemInfo>{
                    "label": "*hash",
                },
                <FieldItemInfo>{
                    "label": "*list",
                },
                <FieldItemInfo>{
                    "label": "*any",
                },
            ),
        },
        <FieldInfo>{
            "name": "sensitive",
            "type": FT_Bool,
            "value": False,
        },
        <FieldInfo>{
            "name": "default_value",
            "type": FT_Auto,
            "isAdvanced": True,
        },
        <FieldInfo>{
            "name": "strictly_local",
            "type": FT_Bool,
            "value": True,
            "isAdvanced": True,
        },
        <FieldInfo>{
            "name": "allowed_values",
            "type": FT_List,
            "isAdvanced": True,
        },
        /*
        <FieldInfo>{
            "name": "value",
            "type": FT_Auto,
            "isAdvanced": True,
            # FIXME: only display when setting the value - type must be the same as the defined type
        },
        <FieldInfo>{
            "name": "value_is_template",
            "type": FT_Bool,
            "value": False,
            "isAdvanced": True,
            # FIXME: only display when setting the value
        },
        <FieldInfo>{
            "name": "prefix",
            "type": FT_String,
            "isAdvanced": True,
            # FIXME: only display when setting the value
        },
        */
    ),
};

class CreatorBaseRestClass {
    private {
        *hash<auto> values;

        static hash<string, string> LogoMap = map {
            $1.key: File::readBinaryFile(ENV.OMQ_DIR + "/etc/images/" + $1.value).toBase64()
        }, Logos.pairIterator(), is_readable(ENV.OMQ_DIR + "/etc/images/" + $1.value);

        const ObjectInfoMap = {
            "job": {
                "class": "CreatorJobRestClassBase",
                "field_class": "CreatorJobDefinitionRestClass",
                "field_method": "staticGetFieldsForJob",
            },
            "service": {
                "class": "CreatorServiceRestClassBase",
                "field_class": "xxx",
                "field_method": "staticGetFieldsForService",
            },
            "class": {
                "class": "CreatorClassRestClassBase",
                "field_class": "CreatorClassDefinitionRestClass",
                "field_method": "staticGetFieldsForClass",
            },
            "connection": {
                "class": "CreatorConnectionRestClassBase",
                "field_class": "CreatorConnectionDefinitionRestClass",
                "field_method": "staticGetFieldsForConnection",
            },
            "config-item": {
                "class": "CreatorConfigItemRestClass",
                "field_class": "xxx",
                "field_method": "staticGetFieldsForConfigItem",
            },
        };

        const Logos = {
            "qore": "Q.png",
            "python": "Python.png",
            "java": "Java.png",
        };
    }

    constructor() {
    }

    constructor(hash<auto> values) {
        self.values = values;
    }

    static hash<string, hash<FieldInfo>> doGetFieldHash(string type, reference<hash<string, string>> gmap) {
        *string class_name = ObjectInfoMap{type}."class";
        if (!class_name) {
            throw "OBJECT-ERROR", sprintf("unknown object type %y; known types: %y", type, keys ObjectInfoMap);
        }
        hash<string, hash<FieldInfo>> rv;
        foreach hash<FieldGroupInfo> g in (create_object(class_name).doGetFields()) {
            map rv{$1.name} = $1, g.fields;
            map gmap{$1.name} = g.title, g.fields;
        }
        return rv;
    }

    static *hash<auto> doGetFieldKeyValueData(string type, int id) {
        *hash<auto> info = ObjectInfoMap{type};
        if (!info) {
            throw "OBJECT-ERROR", sprintf("unknown object type %y; known types: %y", type, keys ObjectInfoMap);
        }
        hash<auto> rv;
        string name;
        foreach hash<FieldGroupInfo> g in (call_static_method(info.field_class, info.field_method, id, \name)) {
            map rv{$1.name} = $1.value, g.fields;
            foreach hash<FieldInfo> f in (g.fields) {
                QDBG_LOG("CREATOR FIELD (%y %d): %y", type, id, f - "items");
            }
        }
        return rv;
    }

    static *softlist<hash<auto>> doGetUpdatedFields(string ix_type, int ix_id, string ref_type, int ref_id, string ref_name) {
        *string class_name = ObjectInfoMap{ix_type}."class";
        if (!class_name) {
            throw "OBJECT-ERROR", sprintf("unknown object type %y; known types: %y", ix_type, keys ObjectInfoMap);
        }
        return call_static_method(class_name, "doGetUpdatedFields", ix_id, ref_type, ref_id, ref_name);
    }

    private static checkGroups(hash<auto> cx, *softlist<auto> groups) {
    }

    private static list<hash<FieldGroupInfo>> processFields(list<hash<FieldGroupInfo>> fields, *hash<auto> ah) {
        bool expand_all_groups = parse_boolean(ah.expandAllGroups);
        foreach hash<FieldGroupInfo> group in (\fields) {
            if (expand_all_groups && !group.isOpen) {
                group.isOpen = True;
            }
            foreach hash<FieldInfo> field in (\group.fields) {
                if (field.isAdvanced && !exists field.isValid) {
                    field.isValid = True;
                }
            }
        }
        return fields;
    }

    # returns a list of hashes representing groups of fields
    private list<hash<FieldGroupInfo>> doGetFields(*hash<auto> ah) {
        return processFields(doGetFieldsImpl(), ah);
    }

    private hash<IdFieldInfo> doPutGenerateId(*hash<auto> ah) {
        return doPutGenerateIdImpl(ah);
    }

    private *list<hash<FieldItemInfo>> doGetModules() {
        return doGetModulesImpl();
    }

    private *list<hash<FieldItemInfo>> doGetBaseClasses() {
        return doGetBaseClassesImpl();
    }

    abstract string name();

    softlist<hash<FieldItemInfo>> baseClasses(*hash<FieldItemInfo> base_class) {
        if (!argv) {
            return classNames();
        }

        *hash<auto> class_maps = Qorus.qmm.getClassMaps();

        *hash<string, string> inheritance_pairs =
            cast<hash<string, string>>(map {$1.name: $1.tags.sys.base_class_name}, class_maps.classmap.iterator(),
                $1.name && $1.tags.sys.base_class_name);

        *hash<string, hash<FieldItemInfo>> base_classes;
        if (base_class) {
            base_classes{base_class.label} = base_class;
        }

        bool any_new = True;
        while (any_new) {
            any_new = False;
            foreach hash<string, string> it in (inheritance_pairs.pairIterator()) {
                string class_name = it.key;
                string base_class_name = it.value;

                if (base_classes{base_class_name}) {
                    string version = class_maps.classrmap{class_name}.lastversion;
                    hash<auto> info = class_maps.classmap{class_maps.classrmap{class_name}{version}};
                    base_classes{class_name} = <FieldItemInfo>{
                        "label": sprintf("%s v%s", class_name, version),
                        "description": info.description,
                    };
                    delete inheritance_pairs{class_name};
                    any_new = True;
                    break;
                }
            }
        }

        QDBG_LOG("baseClasses(%y) ip: %N\nbc: %N", base_class, inheritance_pairs, base_classes);

        return map $1, base_classes{sort(keys base_classes)}.iterator();
    }

    hash<HttpHandlerResponseInfo> doPutNew(hash<auto> cx, *hash<auto> ah) {
        hash<IdFieldInfo> rv = doPutGenerateId(ah);
        if (values) {
            processValues(\rv.fields);
            remove values;
        }
        return RestHandler::makeResponse(200, rv);
    }

    private processValue(reference<hash<FieldInfo>> field) {
        switch (field.name) {
            case "author":
                if (values.author) {
                    field.value = split(";", values.author);
                }
                break;
            case "classes":
                if (values.lib.classes) {
                    field.value = map $1.name, values.lib.classes;
                }
                break;
            case "fsms":
                if (values.lib.fsm) {
                    field.value = map $1.name, values.lib.fsm;
                }
                break;
            case "modules":
                if (values.modules) {
                    field.value = split(",", values.modules);
                }
                break;
            case "mappers":
                auto items = values{field.name};
                field.value = items ? map sprintf("%s:%s", $1.name, $1.version), items : ();
                break;
            case "groups":
            case "vmaps":
                auto items = values{field.name};
                field.value = items ? map $1.name, items : ();
                break;
            case "system_options":
                field.value = values.options;
                break;
            default:
                auto val = values{field.name};
                if (exists val) {
                    field.value = val;
                }
                break;
        }
    }

    private processValues(reference<list<hash<FieldGroupInfo>>> fields) {
        foreach hash<FieldGroupInfo> group in (\fields) {
            foreach hash<FieldInfo> field in (\group.fields) {
                processValue(\field);
                if (field.hasKey("value")
                    && (!exists field.value
                            || field.value === ()
                            || field.value === {})) {
                    remove field.value;
                }
                if (exists field.value && field.isDisabled) {
                    remove field.isDisabled;
                }
            }
        }
    }

    private hash<FieldItemInfo> itemify(string name) {
        return <FieldItemInfo>{
            "label": name,
        };
    }

    private list<hash<FieldItemInfo>> groups() {
        return map itemify($1.name), GroupsRestClass::staticGetGroupList();
    }

    static private softlist<hash<FieldItemInfo>> classNames() {
        hash<auto> class_maps = Qorus.qmm.getClassMaps();

        list<hash<FieldItemInfo>> rv;
        foreach string name in (sort(keys class_maps.classrmap)) {

            string version = class_maps.classrmap{name}.lastversion;
            hash<auto> info = class_maps.classmap{class_maps.classrmap{name}{version}};
            rv += <FieldItemInfo>{
                "label": sprintf("%s v%s", name, version),
                "description": info.description,
            };
        }
        return rv;
    }

    private list<hash<FieldItemInfo>> mappers() {
        *hash<auto> mrmap = Qorus.qmm.getMapperRMap();
        return mrmap ? (map itemify($1), keys mrmap) : ();
    }

    private list<hash<FieldItemInfo>> vmaps() {
        *hash<auto> vmaps = Qorus.qmm.getVMapMap();
        return map itemify($1.name), vmaps.iterator();
    }

    private list<hash<FieldItemInfo>> fsms() {
        *list<hash<auto>> fsms = FsmsRestClass::staticGetFsms();
        return fsms ? map itemify($1.name), fsms : ();
    }

    private hash<FieldGroupInfo> doGetCodeOptions() {
        return <FieldGroupInfo>{
            "title": "interface-code-options",
            "isOpen": False,
            "fields": (
                <FieldInfo>{
                    "name": "base_class_name",
                    "items": doGetBaseClasses(),
                    "selectLabel": "select-base-class-name",
                    "type": FT_String,
                    "subtype": "identifier",
                    "icon": "Calendar2Line",
                    "isAdvanced": True,
                    "modal": True,
                },
                <FieldInfo>{
                    "name": "language",
                    "type": FT_Enum,
                    "value": "qore",
                    "items": (
                        <FieldItemInfo>{
                            "label": "Qore",
                            "value": "qore",
                            "logo": LogoMap.qore,
                        },
                        <FieldItemInfo>{
                            "label": "Python",
                            "value": "python",
                            "logo": LogoMap.python,
                        },
                        <FieldItemInfo>{
                            "label": "Java",
                            "value": "java",
                            "logo": LogoMap.java,
                        },
                    ),
                    "isAdvanced": True,
                },
            ),
        };
    }

    private hash<FieldGroupInfo> doGetInterfaceCodeOptions() {
        hash<FieldGroupInfo> rv = doGetCodeOptions();
        rv.fields += <FieldInfo>{
            "name": "class_name",
            "type": FT_String,
            "subtype": "identifier",
            "isAdvanced": True,
        };
        return rv;
    }

    private hash<FieldGroupInfo> doGetInterfaceDependencyOptions() {
        return <FieldGroupInfo>{
            "title": "interface-dependency-options",
            "isOpen": False,
            "fields": (
                <FieldInfo>{
                    "name": "groups",
                    "items": groups(),
                    "selectLabel": "select-groups",
                    "icon": "Group2Line",
                    "type": FT_List,
                    "multiSelect": True,
                    "isAdvanced": True,
                },
                <FieldInfo>{
                    "name": "classes",
                    "items": classNames(),
                    "selectLabel": "select-classes",
                    "icon": "CodeLine",
                    "type": FT_List,
                    "multiSelect": True,
                    "isAdvanced": True,
                    "modal": True,
                },
                <FieldInfo>{
                    "name": "mappers",
                    "items": mappers(),
                    "selectLabel": "select-mappers",
                    "icon": "ArrowLeftRightLine",
                    "type": FT_List,
                    "multiSelect": True,
                    "isAdvanced": True,
                },
                <FieldInfo>{
                    "name": "vmaps",
                    "items": vmaps(),
                    "selectLabel": "select-value-maps",
                    "icon": "Apps2Fill",
                    "type": FT_List,
                    "multiSelect": True,
                    "isAdvanced": True,
                },
                <FieldInfo>{
                    "name": "modules",
                    "items": doGetModules(),
                    "selectLabel": "select-modules",
                    "icon": "CodeLine",
                    "type": FT_List,
                    "multiSelect": True,
                    "isAdvanced": True,
                },
                <FieldInfo>{
                    "name": "fsms",
                    "items": fsms(),
                    "selectLabel": "select-fsms",
                    "icon": "FlowChart",
                    "type": FT_List,
                    "multiSelect": True,
                    "isAdvanced": True,
                },
            ),
        };
    }

    # return a list of module items
    private *list<hash<FieldItemInfo>> doGetModulesImpl() {
        # empty in the base class
    }

    # return a list of base classes
    private softlist<hash<FieldItemInfo>> doGetBaseClassesImpl() {
        # empty in the base class
    }

    # returns a list of hashes representing groups of fields
    private abstract list<hash<FieldGroupInfo>> doGetFieldsImpl();

    # make an ID reservation and returns the type, reserved ID, and fields
    private abstract hash<IdFieldInfo> doPutGenerateIdImpl(*hash<auto> ah);
}

/** @REST /v6/creator/config-item

    This REST URI path provides actions and information for config items in the creator API
*/
class CreatorConfigItemRestClass inherits CreatorBaseRestClass, QorusRestClass {
    string name() {
        return "config-item";
    }

    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, {"fields": doGetFields()});
    }

    # returns a list of hashes representing groups of fields
    private list<hash<FieldGroupInfo>> doGetFieldsImpl() {
        return (
            ConfigItemOptions,
        );
    }

    # make an ID reservation and returns the type, reserved ID, and fields
    private hash<IdFieldInfo> doPutGenerateIdImpl(*hash<auto> ah) {
        return <IdFieldInfo>{
            "type": "config-item",
            "id": 0,
            "fields": doGetFields(ah),
        };
    }

    hash<HttpHandlerResponseInfo> putNew(hash<auto> cx, *hash<auto> ah) {
        return doPutNew(cx, ah);
    }
}

class CreatorConnectionRestClassBase inherits CreatorBaseRestClass {
    constructor() {
    }

    constructor(hash<auto> conn) : CreatorBaseRestClass(conn) {
    }

    string name() {
        return values.name ?? (values.connectionid ? values.connectionid.toString() : "connection");
    }

    static *list<hash<FieldInfo>> getOptionFields(reference<hash<auto>> option_values,
            *hash<string, hash<ConnectionOptionInfo>> options) {
        *list<hash<FieldInfo>> rv;
        foreach hash<auto> i in (options.pairIterator()) {
%ifdef QorusDebugInternals
            if (!FieldTypeQoreTypeMap{i.value.type}) {
                QDBG_LOG("unknown option type %y for option %y (%s)", i.value.type, i.key. i.value.desc);
                i.value.type = FT_Auto;
            }
%endif
            hash<FieldInfo> f = <FieldInfo>{
                "name": i.key,
                "type": i.value.type,
                "description": i.value.desc,
            };
            if (exists i.value.default_value && !exists option_values{i.key}) {
                option_values{i.key} = i.value.default_value;
            }
            if (i.value.sensitive) {
                f.isSensitive = True;
            }
            if (i.value.allowed_values) {
                f.items = map <FieldItemInfo>{
                    "label": $1.value.strp() ? $1.value.toString() : sprintf("%y", $1.value),
                    "description": $1.desc,
                    "value": $1.value,
                }, i.value.allowed_values;
                f.modal = True;
            }
            rv += f;
        }
        return rv;
    }

    private processValue(reference<hash<FieldInfo>> field) {
        if (field.name == "options") {
            field.value = values.options;
            # get options for items
            *list<hash<FieldItemInfo>> items;
            if (exists values.url) {
                string scheme = values.url;
                scheme =~ s/^(.*):\/\/.*$/$1/;
                if (scheme && (*hash<ConnectionSchemeInfo> scheme_info = ConnectionSchemeCache::getScheme(scheme))) {
                    field.fields = getOptionFields(\field.value, scheme_info.options);
                    # always enable the field when the URL is valid
                    field.isDisabled = False;
                }
            }

            return;
        }
        CreatorBaseRestClass::processValue(\field);
    }

    private list<hash<FieldGroupInfo>> doGetFieldsImpl() {
        return (
            <FieldGroupInfo>{
                "title": "connection-options",
                "isOpen": True,
                "fields": (
                    <FieldInfo>{
                        "name": "name",
                        "type": FT_String,
                    },
                    <FieldInfo>{
                        "name": "description",
                        "type": FT_LongString,
                        "markdown": True,
                    },
                    <FieldInfo>{
                        "name": "url",
                        "type": FT_Url,
                        "items": doGetUrlSchemeItems(),
                        "icon": "Link",
                    },
                ),
            },
            <FieldGroupInfo>{
                "title": "connection-detail-options",
                "isOpen": False,
                "fields": (
                    <FieldInfo>{
                        "name": "options",
                        "type": FT_Hash,
                        "isAdvanced": True,
                        "isDisabled": True,
                    },
                    <FieldInfo>{
                        "name": "tags",
                        "type": FT_Hash,
                        "isAdvanced": True,
                        "value": {},
                    },
                ),
            }
        );
    }

    private softlist<hash<FieldItemInfo>> doGetUrlSchemeItems() {
        # return sorted schemes
        hash<string, hash<ConnectionSchemeInfo>> schemes = ConnectionSchemeCache::get();

        return map <FieldItemInfo>{
            "label": $1,
        }, sort(keys schemes);
    }

    static *softlist<hash<auto>> doGetUpdatedFields(int ix_id, string ref_type, int ref_id, string ref_name) {
    }

    private hash<IdFieldInfo> doPutGenerateIdImpl(*hash<auto> ah) {
        return <IdFieldInfo>{
            "type": "connection",
            "id": sqlif.getNextSequenceValue("seq_connections"),
            "fields": doGetFields(ah),
        };
    }
}

/** @REST /v6/creator/connection

    This REST URI path provides actions and information for connections in the creator API
*/
class CreatorConnectionRestClass inherits CreatorConnectionRestClassBase, ConnectionsRestClassV6 {
    string name() {
        return "connection";
    }

    static *hash<auto> staticGetConnectionInfo(string name, hash<auto> cx, *hash<auto> ah) {
        int id;
        if (name =~ /^[0-9]+$/) {
            id = name.toInt();
        }
        *hash<auto> h = exists id
            ? Qorus.dsmanager.tryGetInfoFromId(id, ah)
            : Qorus.dsmanager.tryGetInfo(name, ah);
        if (h) {
            h.description = remove h.desc;
            return h;
        }
        if (h = exists id
            ? Qorus.connections.getInfoFromId(id, ah)
            : Qorus.connections.getInfo(name, ah)) {
            h.description = remove h.desc;
            return h;
        }
        if (h = exists id
            ? Qorus.remotemonitor.tryGetInfoFromId(id, ah)
            : Qorus.remotemonitor.tryGetInfo(name, ah)) {
            h.description = remove h.desc;
            return h;
        }
    }

    *QorusRestClass subClassImpl(string name, hash<auto> cx, *hash<auto> ah) {
        *hash<auto> h = staticGetConnectionInfo(name, cx, ah);
        if (!h) {
            if (name =~ /^[0-9]+$/) {
                h.connectionid = name.toInt();
            } else {
                return;
            }
        }
        return new CreatorConnectionDefinitionRestClass(h);
    }

    /** @REST GET

        @par Description
        Returns a list of all remote connections (@ref remoteconn "remote connections" under \c "qorus",
        @ref userconn "user connections" under \c "user", and
        @ref dsconn "datasource connections" under \c "datasources")

        @par Arguments
        This API takes the following hash arguments (either as URI arguments or in the message body):
        - \c list: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of connection names is
          returned
        - \c monitored: optional; (@ref remoteconn "remote" and @ref userconn "user" connections only) parsed with
          @ref Qore::parse_boolean(); if @ref True then only monitored connections are returned
        - \c remote: optional; (@ref remoteconn "remote connections") parsed with @ref Qore::parse_boolean(); if
          @ref True then no loopback connections are returned; default if not present: @ref False
        - \c rtime: optional; (@ref dsconn "datasource connections" only) parsed with @ref Qore::parse_boolean(); if
          @ref True then the following attributes are returned as relative date/time values:
          - \c "warning-timeout"
          - \c "error-timeout"
          - \c "pool-wait-max"
        - \c short: optional; parsed with @ref Qore::parse_boolean(); if @ref True then a list of short strings with
          connection names and brief info is returned
        - \c with_passwords: (@ref dsconn "datasource connections" only) parsed with @ref Qore::parse_boolean(); if
          @ref True then the \c pass key is returned in the @ref rest_datasource_connection_hash return value

        @par Return Value
        Returns a list of hashes; the \c "conntype" value determines the hash format as follows:
        - \c "DATASOURCE": a @ref rest_datasource_connection_hash
        - \c "REMOTE" or \c "USER-CONNECTION": a @ref rest_user_remote_connection_hash

        @par Errors
        - <tt><b>403 Forbidden</b></tt>: \c AUTHORIZATION-ERROR: this exception is thrown when @ref RBAC is enabled
          and the user does not have sufficient privileges for the operation

        @note
        - @ref dsconn "datasource connections" are always returned; see above for permissions required if the
          \c with_passwords option is used
    */

    /** @REST POST

        @par Description
        Creates a new connection

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c metadata: (hash; required) the metadata for the new connection
        - \c type: (string; optional) if present must be \c "connection"
        - \c tab_token: (string; required if there is a name reservation or if \a lock is \c true) the WS connection
          ID holding a name reservation for the new connection name
        - \c cid: (int; required if the \c lock key is set) the unique connection ID
        - \c lock: (bool; optional) lock the record after creating (in which case \c cid and \a tab_token must also be
          passed)

        @par Return Value
        This API returns a hash with the following keys:
        - \c id: (int) the ID of the connection created

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        if (exists ah.id && ah.id.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"id\" has type %y; must be \"integer\" if present",
                ah.id.type()));
        }

        if (ah.metadata.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, sprintf("argument \"metadata\" has type %y; expecting \"hash\"",
                ah.metadata.type()));
        }

        if (ah.type && ah.type != "connection") {
            return RestHandler::makeResponse(400, sprintf("argument \"type\" = %y; expecting \"connection\"",
                ah.type));
        }

        if (exists ah.tab_token && ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\" if present",
                ah.tab_token.type()));
        }

        if (exists ah.cid && ah.cid.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"id\" has type %y; must be \"integer\" if present",
                ah.id.type()));
        }

        bool lock = parse_boolean(ah.lock);
        if (lock && (!exists ah.cid || !ah.tab_token)) {
            return RestHandler::makeResponse(400, "argument \"lock\" requires valid \"cid\" and \"tab_token\" "
                "arguments");
        }

        hash<string, hash<FieldInfo>> fmap;
        map (fmap += map {$1.name: $1}, $1.fields), doGetFields(ah);

        # check metadata
        foreach hash<auto> i in (ah.metadata.pairIterator()) {
            *hash<FieldInfo> field = fmap{i.key};
            if (!field) {
                return RestHandler::makeResponse(400, sprintf("unknown metadata key %y; valid metadata keys: %y", i.key,
                    keys fmap));
            }
        }

        int id;
        try {
            id = Qorus.qmm.createConnection(ah.id, ah.metadata, ah.tab_token);
            if (lock) {
                Qorus.creatorWsHandler.editLock(ah.cid, ah.tab_token, "connection", values.connectionid);
            }
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CONNECTION-CREATION-ERROR" || ex.err == WEBIDE_ERROR_INVALID_VALUE) {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(201, {"id": id});
    }

    hash<HttpHandlerResponseInfo> putNew(hash<auto> cx, *hash<auto> ah) {
        return doPutNew(cx, ah);
    }
}

/** @REST /v6/creator/connection/{connection}

    This REST URI path provides actions and information for a specific connection in the creator API
*/
class CreatorConnectionDefinitionRestClass inherits CreatorConnectionRestClassBase, QorusRestClass {
    constructor(hash<auto> conn) : CreatorConnectionRestClassBase(conn) {
    }

    /** @REST GET

        @par Description
        Returns information for a specific connection with field information as well
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, {
            "type": "connection",
            "id": values.connectionid,
            "fields": doGetFieldsWithData(ah),
        });
    }

    /** @REST PUT

        @par Description
        Updates a class

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c metadata: (hash) the metadata of the connection to update
        - \c tab_token: (string; required if there is a name reservation) the WS connection ID holding a name reservation for
          the new connection name

        @par Return Value
        This API returns a hash with the following keys:
        - \c id: (int) the connection ID updated
        - all other keys updated for the object

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        if (exists ah.tab_token && ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\" if present",
                ah.tab_token.type()));
        }

        hash<string, hash<FieldInfo>> fmap;
        map (fmap += map {$1.name: $1}, $1.fields), doGetFields(ah);

        # check metadata
        foreach hash<auto> i in (ah.metadata.pairIterator()) {
            *hash<FieldInfo> field = fmap{i.key};
            if (!field) {
                return RestHandler::makeResponse(400, sprintf("unknown connection metadata key %y; valid metadata keys: %y", i.key,
                    keys fmap));
            }
        }

        {
            *hash<auto> extra = ah - ("metadata", "tab_token");
            if (extra) {
                return RestHandler::makeResponse(400, sprintf("unknown arguments %y in request; known args: %y",
                    keys extra, ("code", "metadata")));
            }
        }

        *hash<auto> updates;
        try {
            updates = Qorus.qmm.updateConnection(values.connectionid, ah.metadata, ah.tab_token);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CONNECTION-UPDATE-ERROR") {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, {"id": values.connectionid} + updates);
    }

    /** @REST PUT action=editLock

        @par Description
        Locks a connection for editing in the UI

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c cid: (int) the unique WebSocket connection ID
        - \c tab_token: (string) the unique connection ID for the tab subchannel

        @par Return Value
        This API returns a hash with the following keys:
        - \c locked: (bool) True or False
        - \c info: (hash) only included if the lock fails
            - \c intent: \c warning
            - \c content: msg explaining that the object is already locked

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> putEditLock(hash<auto> cx, *hash<auto> ah) {
        if (ah.cid.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"cid\" has type %y; must be \"integer\"",
                ah.cid.type()));
        }

        if (ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\"",
                ah.tab_token.type()));
        }

        try {
            Qorus.creatorWsHandler.editLock(ah.cid, ah.tab_token, "connection", values.connectionid);
            return RestHandler::makeResponse(200, {"locked": True});
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "lock connection %y cid: %y tab_token: %y failed: %s: %s", values.connectionid, ah.cid,
                ah.tab_token, ex.err, ex.desc);
            if (ex.err == "OPEN-ERROR") {
                return RestHandler::makeResponse(200, {
                    "locked": False,
                    "info": {
                        "intent": "warning",
                        "content": "open-error",
                    },
                });
            }
            rethrow;
        }
    }

    /** @REST PUT action=releaseEditLock

        @par Description
        Releases an edit lock on a connection

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c cid: (int) the unique connection ID
        - \c tab_token: (string) the unique connection ID for the tab subchannel

        @par Return Value
        This API returns a hash with the following keys:
        - \c locked: (bool) True or False
        - \c info: (hash) only included if the lock fails
            - \c intent: \c warning
            - \c content: msg explaining that the object is already locked

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> putReleaseEditLock(hash<auto> cx, *hash<auto> ah) {
        if (ah.cid.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"cid\" has type %y; must be \"integer\"",
                ah.cid.type()));
        }

        if (ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\"",
                ah.tab_token.type()));
        }

        try {
            Qorus.creatorWsHandler.releaseEditLock(ah.cid, ah.tab_token, "connection", values.connectionid);
            return RestHandler::makeResponse(200, {"locked": False});
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "unlock connection %y cid: %y tab_token: %y failed: %s: %s", values.connectionid, ah.cid,
                ah.tab_token, ex.err, ex.desc);
            if (ex.err == "CLOSE-ERROR") {
                return RestHandler::makeResponse(200, {
                    "locked": True,
                    "info": {
                        "intent": "error",
                        "content": "close-error",
                    },
                });
            }
            rethrow;
        }
    }

    /** @REST DELETE

        @par Description
        Deletes the connection

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
        - <tt><b>403 Forbidden</b></tt>: \c AUTHORIZATION-ERROR: this exception is thrown when @ref RBAC is enabled
          and the user does not have sufficient privileges for the operation
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        return staticDeleteConnection(values, cx, ah);
    }

    list<hash<FieldGroupInfo>> doGetFieldsWithData(*hash<auto> ah) {
        list<hash<FieldGroupInfo>> fields = doGetFields(ah);
        if (values) {
            processValues(\fields);
        }
        return fields;
    }

    static hash<HttpHandlerResponseInfo> staticDeleteConnection(hash<auto> h, hash<auto> cx, *hash<auto> ah) {
        try {
            Qorus.qmm.deleteConnection(h.connectionid);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CONNECTION-DELETION-ERROR") {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, {"id": h.connectionid});
    }

    static *list<hash<FieldGroupInfo>> staticGetFieldsForConnection(int connectionid, reference<string> name) {
        *AbstractConnection c;
        {
            ReadLockHelper rlh(Qorus.connection_rwl);
            c = Qorus.qmm.getConnectionFromIdLocked(connectionid);
        }
        if (!c) {
            QDBG_LOG("staticGetFieldsForConnection() connection %d does not exist", connectionid);
            return;
        }
        name = c.name;
        CreatorConnectionDefinitionRestClass crc(c.getExtendedInfo({"with_passwords": True}));
        return crc.doGetFieldsWithData();
    }
}

class CreatorClassRestClassBase inherits CreatorBaseRestClass {
    constructor() {
    }

    constructor(hash<auto> cls) : CreatorBaseRestClass(cls) {
    }

    string name() {
        return values.name ?? (values.classid ? values.classid.toString() : "class");
    }

    static *softlist<hash<auto>> doGetUpdatedFields(int ix_id, string ref_type, int ref_id, string ref_name) {
        if (ref_type == "class") {
            CreatorClassRestClassBase obj();
            # +=: ensure that metadata remains "hash<auto>"
            hash<auto> metadata += {
                "items": obj.classNames(),
            };
            return {
                "type": "class",
                "id": ix_id,
                "field": "base_class_name",
                "group": "interface-code-options",
                "metadata": metadata,
            };
        }
    }

    private list<hash<FieldGroupInfo>> doGetFieldsImpl() {
        return (
            <FieldGroupInfo>{
                "title": "class-options",
                "isOpen": True,
                "fields": (
                    <FieldInfo>{
                        "name": "name",
                        "type": FT_String,
                    },
                    <FieldInfo>{
                        "name": "version",
                        "type": FT_String,
                    },
                    <FieldInfo>{
                        "name": "description",
                        "type": FT_LongString,
                        "markdown": True,
                    },
                ),
            },
            <FieldGroupInfo>{
                "title": "class-config-options",
                "isOpen": False,
                "fields": (
                    <FieldInfo>{
                        "name": "api-managers",
                        "type": FT_List,
                        "selectLabel": "select-api-managers",
                        "icon": "GitPullRequestFill",
                        "isAdvanced": True,
                        "modal": True,
                    },
                    /*
                    <FieldInfo>{
                        "name": "class-connectors",
                        "type": FT_xxx,
                        "isAdvanced": True,
                    },
                    <FieldInfo>{
                        "name": "processor",
                        "type": FT_xxx,
                        "isAdvanced": True,
                    },
                    */
                    <FieldInfo>{
                        "name": "requires",
                        "type": FT_List,
                        "items": classNames(),
                        "selectLabel": "select-requires",
                        "icon": "GitPullRequestFill",
                        "isAdvanced": True,
                        "modal": True,
                    },
                ),
            },
            doGetCodeOptions(),
            CommonDetailOptions,
        );
    }

    private hash<IdFieldInfo> doPutGenerateIdImpl(*hash<auto> ah) {
        return <IdFieldInfo>{
            "type": "class",
            "id": sqlif.getNextSequenceValue("seq_classes"),
            "fields": doGetFields(ah),
        };
    }

    # return a list of base classes
    private softlist<hash<FieldItemInfo>> doGetBaseClassesImpl() {
        return baseClasses();
    }
}

/** @REST /v6/creator/class/{class}

    This REST URI path provides actions and information for a specific class in the creator API
*/
class CreatorClassDefinitionRestClass inherits CreatorClassRestClassBase, ClassDefinitionRestClass {
    constructor(hash<auto> cls) : CreatorClassRestClassBase(cls), ClassDefinitionRestClass(cls) {
    }

    /** @REST GET

        @par Description
        Returns information for a specific class with field information as well
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, {
            "type": "class",
            "id": h.classid,
            "fields": doGetFieldsWithData(ah),
            "code": h.body,
        });
    }

    /** @REST PUT

        @par Description
        Updates a class

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c code: (string) the source code for the class
        - \c metadata: (hash) the metadata of the class to update
        - \c tab_token: (string; required if there is a name reservation) the WS connection ID holding a name
          reservation for the new class name

        @par Return Value
        This API returns a hash with the following keys:
        - \c id: (int) the class ID updated

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        if (exists ah."code" && ah."code".typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"code\" has type %y; expecting \"string\"",
                ah."code".type()));
        }

        if (exists ah.tab_token && ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\" if "
                "present", ah.tab_token.type()));
        }

        hash<string, hash<FieldInfo>> fmap;
        map (fmap += map {$1.name: $1}, $1.fields), doGetFields(ah);

        # check metadata
        foreach hash<auto> i in (ah.metadata.pairIterator()) {
            *hash<FieldInfo> field = fmap{i.key};
            if (!field) {
                return RestHandler::makeResponse(400, sprintf("unknown class metadata key %y; valid metadata keys: "
                    "%y", i.key, keys fmap));
            }
        }

        {
            *hash<auto> extra = ah - ("code", "metadata", "tab_token");
            if (extra) {
                return RestHandler::makeResponse(400, sprintf("unknown arguments %y in request; known args: %y",
                    keys extra, ("code", "metadata")));
            }
        }

        if (ah.metadata.groups) {
            checkGroups(cx, ah.metadata.groups);
        }

        *hash<auto> updates;
        try {
            updates = Qorus.qmm.updateClass(h.classid, ah."code", ah.metadata, ah.tab_token);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CLASS-UPDATE-ERROR") {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, {"id": h.classid} + updates);
    }

    /** @REST PUT action=editLock

        @par Description
        Locks a class for editing in the UI

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c cid: (int) the unique connection ID
        - \c tab_token: (string) the unique connection ID for the tab subchannel

        @par Return Value
        This API returns a hash with the following keys:
        - \c locked: (bool) True or False
        - \c info: (hash) only included if the lock fails
            - \c intent: \c warning
            - \c content: msg explaining that the object is already locked

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> putEditLock(hash<auto> cx, *hash<auto> ah) {
        if (ah.cid.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"cid\" has type %y; must be \"integer\"",
                ah.cid.type()));
        }

        if (ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\"",
                ah.tab_token.type()));
        }

        try {
            Qorus.creatorWsHandler.editLock(ah.cid, ah.tab_token, "class", h.classid);
            return RestHandler::makeResponse(200, {"locked": True});
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "lock class %y cid: %y tab_token: %y failed: %s: %s", h.classid, ah.cid,
                ah.tab_token, ex.err, ex.desc);
            if (ex.err == "OPEN-ERROR") {
                return RestHandler::makeResponse(200, {
                    "locked": False,
                    "info": {
                        "intent": "warning",
                        "content": "open-error",
                    },
                });
            }
            rethrow;
        }
    }

    /** @REST PUT action=releaseEditLock

        @par Description
        Releases an edit lock on a class

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c cid: (int) the unique connection ID
        - \c tab_token: (string) the unique connection ID for the tab subchannel

        @par Return Value
        This API returns a hash with the following keys:
        - \c locked: (bool) True or False
        - \c info: (hash) only included if the lock fails
            - \c intent: \c warning
            - \c content: msg explaining that the object is already locked

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> putReleaseEditLock(hash<auto> cx, *hash<auto> ah) {
        if (ah.cid.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"cid\" has type %y; must be \"integer\"",
                ah.cid.type()));
        }

        if (ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\"",
                ah.tab_token.type()));
        }

        try {
            Qorus.creatorWsHandler.releaseEditLock(ah.cid, ah.tab_token, "class", h.classid);
            return RestHandler::makeResponse(200, {"locked": False});
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "unlock class %y cid: %y tab_token: %y failed: %s: %s", h.classid, ah.cid,
                ah.tab_token, ex.err, ex.desc);
            if (ex.err == "CLOSE-ERROR") {
                return RestHandler::makeResponse(200, {
                    "locked": True,
                    "info": {
                        "intent": "error",
                        "content": "close-error",
                    },
                });
            }
            rethrow;
        }
    }

    /** @REST DELETE

        @par Description
        Deletes the class

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
        - <tt><b>403 Forbidden</b></tt>: \c AUTHORIZATION-ERROR: this exception is thrown when @ref RBAC is enabled
          and the user does not have sufficient privileges for the operation
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        return staticDeleteClass(h, cx, ah);
    }

    list<hash<FieldGroupInfo>> doGetFieldsWithData(*hash<auto> ah) {
        list<hash<FieldGroupInfo>> fields = doGetFields(ah);
        if (values) {
            processValues(\fields);
        }
        return fields;
    }

    static hash<HttpHandlerResponseInfo> staticDeleteClass(hash<auto> h, hash<auto> cx, *hash<auto> ah) {
        try {
            Qorus.qmm.deleteClass(h.classid);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CLASS-DELETION-ERROR") {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, {"id": h.classid});
    }

    static *list<hash<FieldGroupInfo>> staticGetFieldsForClass(int classid, reference<string> name) {
        *hash<auto> cls = ClassRestClass::staticGetClassInfo(classid, 6);
        if (!cls) {
            QDBG_LOG("staticGetFieldsForClass() classid %d has no data: %y", classid, Qorus.qmm.lookupClass(classid));
            return;
        }
        name = cls.name;
        CreatorClassDefinitionRestClass crc(cls);
        return crc.doGetFieldsWithData();
    }

    static string staticGetCodeForClass(int classid) {
        return Qorus.qmm.lookupClass(classid).body ?? "";
    }
}

/** @REST /v6/creator/class

    This REST URI path provides actions and information for classes in the creator API
*/
class CreatorClassRestClass inherits CreatorClassRestClassBase, ClassRestClassV5 {
    string name() {
        return "class";
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id;
        if (arg !~ /^[[:digit:]]+$/u) {
            *int clsid = Qorus.qmm.tryGetClassId(arg);
            if (!clsid) {
                return;
            }
            id = clsid;
        } else {
            id = arg.toInt();
        }
        *hash<auto> cls = ClassRestClass::staticGetClassInfo(id, 6);
        if (!cls) {
            if (arg =~ /^[0-9]+$/) {
                cls.classid = id;
            } else {
                return;
            }
        }
        return new CreatorClassDefinitionRestClass(cls);
    }

    /** @REST GET

        @par Description
        Returns information about class metadata
    */

    /** @REST POST

        @par Description
        Creates a new class

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c code: (string; required) the source code for the class; must be a non-empty string
        - \c id: (int; optional) if present, must be the new class ID from a reservation call
        - \c metadata: (hash; required) the metadata for the new class
        - \c type: (string; optional) if present must be \c "class"
        - \c tab_token: (string; required if there is a name reservation or if \a lock is \c true) the WS connection
          ID holding a name reservation for the new class name
        - \c cid: (int; required if the \c lock key is set) the unique connection ID
        - \c lock: (bool; optional) lock the record after creating (in which case \c cid and \a tab_token must also be
          passed)

        @par Return Value
        This API returns a hash with the following keys:
        - \c id: (int) the class ID for the class created

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        if (ah."code".typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"code\" has type %y; expecting \"string\"",
                ah."code".type()));
        }
        if (!ah."code".val()) {
            return RestHandler::makeResponse(400, "argument \"code\" is empty; must be a non-empty string");
        }

        if (exists ah.id && ah.id.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"id\" has type %y; must be \"integer\" if present",
                ah.id.type()));
        }

        if (ah.metadata.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, sprintf("argument \"metadata\" has type %y; expecting \"hash\"",
                ah.metadata.type()));
        }

        if (ah.type && ah.type != "class") {
            return RestHandler::makeResponse(400, sprintf("argument \"type\" = %y; expecting \"class\"", ah.type));
        }

        if (exists ah.tab_token && ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\" if present",
                ah.tab_token.type()));
        }

        if (exists ah.cid && ah.cid.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"id\" has type %y; must be \"integer\" if present",
                ah.id.type()));
        }

        bool lock = parse_boolean(ah.lock);
        if (lock && (!exists ah.cid || !ah.tab_token)) {
            return RestHandler::makeResponse(400, "argument \"lock\" requires valid \"cid\" and \"tab_token\" "
                "arguments");
        }

        hash<string, hash<FieldInfo>> fmap;
        map (fmap += map {$1.name: $1}, $1.fields), doGetFields();

        # check metadata
        foreach hash<auto> i in (ah.metadata.pairIterator()) {
            *hash<FieldInfo> field = fmap{i.key};
            if (!field) {
                return RestHandler::makeResponse(400, sprintf("unknown metadata key %y; valid metadata keys: %y", i.key,
                    keys fmap));
            }
        }

        checkGroups(cx, ah.metadata.groups);

        int id;
        try {
            id = Qorus.qmm.createClass(ah.id, ah."code", ah.metadata, ah.tab_token);
            if (lock) {
                Qorus.creatorWsHandler.editLock(ah.cid, ah.tab_token, "class", id);
            }
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "CLASS-CREATION-ERROR" || ex.err == WEBIDE_ERROR_INVALID_VALUE) {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(201, {"id": id});
    }

    /** @REST PUT action=new

        @par Description
        Reserves a class id for creation and returns metadata information for classes

        @par Return Value
        This API returns a hash with the following keys:
        - \c type: (string) \c class
        - \c id: (int) the class ID reserved
        - \c fields: (hash) field description for a new class

        @par Errors
        - <tt><b>403 Forbidden</b></tt>: \c AUTHORIZATION-ERROR: this exception is thrown when @ref RBAC is enabled
          and the user does not have sufficient privileges for the operation
    */
    hash<HttpHandlerResponseInfo> putNew(hash<auto> cx, *hash<auto> ah) {
        return doPutNew(cx, ah);
    }
}

class CreatorJobRestClassBase inherits CreatorBaseRestClass {
    constructor() {
    }

    constructor(hash<auto> job) : CreatorBaseRestClass(job) {
    }

    string name() {
        return values.name ?? (values.jobid ? values.jobid.toString() : "job");
    }

    private processValue(reference<hash<FieldInfo>> field) {
        if (field.name == "schedule") {
            field.value = join(" ", map values{$1}, ("minute", "hour", "day", "month", "wday"));
            return;
        }
        CreatorBaseRestClass::processValue(\field);
    }

    static *hash<auto> staticGetJob(hash<auto> cx, *hash<auto> ah, softint id, int apiver = 6) {
        *hash<auto> job = JobRestClass::staticGetJob(cx, ah, id, apiver);
        # move options to position expected by UI
        if (job && job."runtime-options"."stack-size") {
            job."stack-size" = get_byte_size(remove job."runtime-options"."stack-size", 50);
            job."stack-size" =~ s/([^\.])0+( .iB)$/$1$2/;
        }
        return job;
    }

    static *softlist<hash<auto>> doGetUpdatedFields(int ix_id, string ref_type, int ref_id, string ref_name) {
        if (ref_type == "class") {
            CreatorJobRestClassBase obj();
            # +=: ensure that metadata remains "hash<auto>"
            hash<auto> base_class_metadata += {
                "items": obj.doGetBaseClasses(),
            };
            # +=: ensure that metadata remains "hash<auto>"
            hash<auto> class_metadata += {
                "items": obj.classNames(),
            };
            return (
                {
                    "type": "job",
                    "id": ix_id,
                    "field": "base_class_name",
                    "group": "interface-code-options",
                    "metadata": base_class_metadata,
                },
                {
                    "type": "job",
                    "id": ix_id,
                    "field": "classes",
                    "group": "interface-dependency-options",
                    "metadata": class_metadata,
                },
            );
        }
    }

    private list<hash<FieldGroupInfo>> doGetFieldsImpl() {
        return (
            <FieldGroupInfo>{
                "title": "job-options",
                "isOpen": True,
                "fields": (
                    <FieldInfo>{
                        "name": "name",
                        "type": FT_String,
                    },
                    <FieldInfo>{
                        "name": "version",
                        "type": FT_String,
                    },
                    <FieldInfo>{
                        "name": "description",
                        "type": FT_LongString,
                        "markdown": True,
                    },
                    <FieldInfo>{
                        "name": "schedule",
                        "type": FT_Cron,
                        "subtype": "cron-string",
                        "value": "0 0 * * *",
                    },
                ),
            },
            <FieldGroupInfo>{
                "title": "job-exec-options",
                "isOpen": False,
                "fields": (
                    <FieldInfo>{
                        "name": "remote",
                        "type": FT_Bool,
                        "isAdvanced": True,
                        "value": True
                    },
                    <FieldInfo>{
                        "name": "active",
                        "type": FT_Bool,
                        "isAdvanced": True,
                        "value": True
                    },
                    <FieldInfo>{
                        "name": "run_skipped",
                        "type": FT_Bool,
                        "value": False,
                        "isAdvanced": True,
                    },
                    <FieldInfo>{
                        "name": "expiry_date",
                        "type": FT_Date,
                        "isAdvanced": True,
                    },
                ),
            },
            doGetInterfaceCodeOptions(),
            doGetInterfaceDependencyOptions(),
            InterfaceDetailOptions,
        );
    }

    private hash<IdFieldInfo> doPutGenerateIdImpl(*hash<auto> ah) {
        return <IdFieldInfo>{
            "type": "job",
            "id": sqlif.getNextSequenceValue("seq_jobs"),
            "fields": doGetFields(ah),
        };
    }

    private list<hash<FieldItemInfo>> doGetModulesImpl() {
        auto modules =  Qorus.options.get("job-modules");
        return modules ? map itemify($1), modules : ();
    }

    private list<hash<FieldItemInfo>> doGetBaseClassesImpl() {
        return baseClasses(<FieldItemInfo>{
            "label": "QorusJob",
            "description": "Default Qorus job base class; part of the Qorus API",
        });
    }
}

/** @REST /v6/creator/job/{job}

    This REST URI path provides actions and information for a specific job in the creator API
*/
class CreatorJobDefinitionRestClass inherits CreatorJobRestClassBase, JobDefinitionRestClassV5 {
    constructor(hash<auto> job) : CreatorJobRestClassBase(job), JobDefinitionRestClassV5(job) {
    }

    /** @REST GET

        @par Description
        Returns information for a specific job with field information as well
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        return RestHandler::makeResponse(200, {
            "type": "job",
            "id": jh.jobid,
            "fields": doGetFieldsWithData(ah),
            "code": staticGetCodeForJob(jh.jobid),
        });
    }

    /** @REST PUT

        @par Description
        Updates a job

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c code: (string) the source code for the job
        - \c metadata: (hash) the metadata of the job to update
        - \c tab_token: (string; required if there is a name reservation) the WS connection ID holding a name reservation for
          the new job name

        @par Return Value
        This API returns a hash with the following keys:
        - \c id: (int) the job ID updated

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> put(hash<auto> cx, *hash<auto> ah) {
        if (exists ah."code" && ah."code".typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"code\" has type %y; expecting \"string\"",
                ah."code".type()));
        }

        if (exists ah.tab_token && ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\" if present",
                ah.tab_token.type()));
        }

        hash<string, hash<FieldInfo>> fmap;
        map (fmap += map {$1.name: $1}, $1.fields), doGetFields(ah);

        # check metadata
        foreach hash<auto> i in (ah.metadata.pairIterator()) {
            *hash<FieldInfo> field = fmap{i.key};
            if (!field) {
                return RestHandler::makeResponse(400, sprintf("unknown job metadata key %y; valid metadata keys: %y", i.key,
                    keys fmap));
            }
            auto value;
            if (exists i.value) {
                switch (field.type) {
                    case "byte-size":
                        value = parse_memory_size(i.value);
                        break;
                    case "cron":
                        list<string> cron = i.value.split(" ");
                        value = {
                            "minute": cron[0],
                            "hour": cron[1],
                            "day": cron[2],
                            "month": cron[3],
                            "wday": cron[4],
                        };
                        break;
                    case "date":
                        value = date(i.value);
                        break;
                    default:
                        value = i.value;
                        break;
                }
            }
            ah.metadata{i.key} = value;
        }

        {
            *hash<auto> extra = ah - ("code", "metadata", "tab_token");
            if (extra) {
                return RestHandler::makeResponse(400, sprintf("unknown arguments %y in request; known args: %y",
                    keys extra, ("code", "metadata")));
            }
        }

        if (ah.metadata.groups) {
            checkGroups(cx, ah.metadata.groups);
        }

        *hash<auto> updates;
        try {
            updates = Qorus.qmm.updateJob(jh.jobid, ah."code", ah.metadata, ah.tab_token);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "JOB-UPDATE-ERROR") {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, {"id": jh.jobid} + updates);
    }

    /** @REST PUT action=editLock

        @par Description
        Locks a job for editing in the UI

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c cid: (int) the unique connection ID
        - \c tab_token: (string) the unique connection ID for the tab subchannel

        @par Return Value
        This API returns a hash with the following keys:
        - \c locked: (bool) True or False
        - \c info: (hash) only included if the lock fails
            - \c intent: \c warning
            - \c content: msg explaining that the object is already locked

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> putEditLock(hash<auto> cx, *hash<auto> ah) {
        if (ah.cid.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"cid\" has type %y; must be \"integer\"",
                ah.cid.type()));
        }

        if (ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\"",
                ah.tab_token.type()));
        }

        try {
            Qorus.creatorWsHandler.editLock(ah.cid, ah.tab_token, "job", jh.jobid);
            return RestHandler::makeResponse(200, {"locked": True});
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "lock job %y cid: %y tab_token: %y failed: %s: %s", jh.jobid, ah.cid,
                ah.tab_token, ex.err, ex.desc);
            if (ex.err == "OPEN-ERROR") {
                return RestHandler::makeResponse(200, {
                    "locked": False,
                    "info": {
                        "intent": "warning",
                        "content": "open-error",
                    },
                });
            }
            rethrow;
        }
    }

    /** @REST PUT action=releaseEditLock

        @par Description
        Releases an edit lock on a job

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c cid: (int) the unique connection ID
        - \c tab_token: (string) the unique connection ID for the tab subchannel

        @par Return Value
        This API returns a hash with the following keys:
        - \c locked: (bool) True or False
        - \c info: (hash) only included if the lock fails
            - \c intent: \c warning
            - \c content: msg explaining that the object is already locked

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> putReleaseEditLock(hash<auto> cx, *hash<auto> ah) {
        if (ah.cid.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"cid\" has type %y; must be \"integer\"",
                ah.cid.type()));
        }

        if (ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\"",
                ah.tab_token.type()));
        }

        try {
            Qorus.creatorWsHandler.releaseEditLock(ah.cid, ah.tab_token, "job", jh.jobid);
            return RestHandler::makeResponse(200, {"locked": False});
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "unlock job %y cid: %y tab_token: %y failed: %s: %s", jh.jobid, ah.cid,
                ah.tab_token, ex.err, ex.desc);
            if (ex.err == "CLOSE-ERROR") {
                return RestHandler::makeResponse(200, {
                    "locked": True,
                    "info": {
                        "intent": "error",
                        "content": "close-error",
                    },
                });
            }
            rethrow;
        }
    }

    /** @REST DELETE

        @par Description
        Deletes the job

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
        - <tt><b>403 Forbidden</b></tt>: \c AUTHORIZATION-ERROR: this exception is thrown when @ref RBAC is enabled
          and the user does not have sufficient privileges for the operation
    */
    hash<HttpHandlerResponseInfo> del(hash<auto> cx, *hash<auto> ah) {
        return staticDeleteJob(jh, cx, ah);
    }

    list<hash<FieldGroupInfo>> doGetFieldsWithData(*hash<auto> ah) {
        list<hash<FieldGroupInfo>> fields = doGetFields(ah);
        if (values) {
            processValues(\fields);
        }
        return fields;
    }

    static hash<HttpHandlerResponseInfo> staticDeleteJob(hash<auto> jh, hash<auto> cx, *hash<auto> ah) {
        try {
            Qorus.qmm.deleteJob(jh.jobid);
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "JOB-DELETION-ERROR") {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(200, {"id": jh.jobid});
    }

    static *list<hash<FieldGroupInfo>> staticGetFieldsForJob(int jobid, reference<string> name) {
        *hash<auto> job = CreatorJobRestClassBase::staticGetJob({"user": "%SYS%"}, NOTHING, jobid);
        if (!job) {
            QDBG_LOG("staticGetFieldsForJob() jobid %d has no data: %y", jobid, Qorus.qmm.lookupJob(jobid));
            return;
        }
        name = job.name;
        CreatorJobDefinitionRestClass jrc(job);
        return jrc.doGetFieldsWithData();
    }

    static string staticGetCodeForJob(int jobid) {
        return Qorus.qmm.lookupJob(jobid, False)."code" ?? "";
    }
}

/** @REST /v6/creator/job

    This REST URI path provides actions and information for jobs in the creator API
*/
class CreatorJobRestClass inherits CreatorJobRestClassBase, JobRestClassV5 {
    string name() {
        return "job";
    }

    static *hash<auto> staticGetJob(hash<auto> cx, *hash<auto> ah, softint id, int apiver = 6) {
        *hash<auto> job = JobRestClass::staticGetJob(cx, ah, id, apiver);
        # move options to position expected by UI
        if (job && job."runtime-options"."stack-size") {
            job."stack-size" = get_byte_size(remove job."runtime-options"."stack-size", 50);
            job."stack-size" =~ s/([^\.])0+( .iB)$/$1$2/;
        }
        return job;
    }

    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = JobRestClass::staticGetJobId(arg);
        *hash<auto> job = CreatorJobRestClass::staticGetJob(cx, ah, id, 6);
        if (!job) {
            if (arg =~ /^[0-9]+$/) {
                job.jobid = id;
            } else {
                return;
            }
        }
        return new CreatorJobDefinitionRestClass(job);
    }

    /** @REST GET

        @par Description
        Returns information about job metadata
    */

    /** @REST POST

        @par Description
        Creates a new job

        @par Arguments
        This API takes the following hash arguments (in the message body):
        - \c code: (string; required) the source code for the job; must be a non-empty string
        - \c id: (int; optional) if present, must be the new job ID from a reservation call
        - \c metadata: (hash; required) the metadata for the new job
        - \c type: (string; optional) if present must be \c "job"
        - \c tab_token: (string; required if there is a name reservation or if \a lock is \c true) the WS connection
          ID holding a name reservation for
          the new job name
        - \c cid: (int; required if the \c lock key is set) the unique connection ID
        - \c lock: (bool; optional) lock the record after creating (in which case \c cid and \a tab_token must also be
          passed)

        @par Return Value
        This API returns a hash with the following keys:
        - \c id: (int) the job ID for the job created

        @par Errors
        - <tt><b>400 Bad Request</b></tt>: returned if the request has invalid arguments
    */
    hash<HttpHandlerResponseInfo> post(hash<auto> cx, *hash<auto> ah) {
        if (ah."code".typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"code\" has type %y; expecting \"string\"",
                ah."code".type()));
        }
        if (!ah."code".val()) {
            return RestHandler::makeResponse(400, "argument \"code\" is empty; must be a non-empty string");
        }

        if (exists ah.id && ah.id.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"id\" has type %y; must be \"integer\" if present",
                ah.id.type()));
        }

        if (ah.metadata.typeCode() != NT_HASH) {
            return RestHandler::makeResponse(400, sprintf("argument \"metadata\" has type %y; expecting \"hash\"",
                ah.metadata.type()));
        }

        if (ah.type && ah.type != "job") {
            return RestHandler::makeResponse(400, sprintf("argument \"type\" = %y; expecting \"job\"", ah.type));
        }

        if (exists ah.tab_token && ah.tab_token.typeCode() != NT_STRING) {
            return RestHandler::makeResponse(400, sprintf("argument \"tab_token\" has type %y; must be \"string\" if present",
                ah.tab_token.type()));
        }

        if (exists ah.cid && ah.cid.typeCode() != NT_INT) {
            return RestHandler::makeResponse(400, sprintf("argument \"id\" has type %y; must be \"integer\" if present",
                ah.id.type()));
        }

        bool lock = parse_boolean(ah.lock);
        if (lock && (!exists ah.cid || !ah.tab_token)) {
            return RestHandler::makeResponse(400, "argument \"lock\" requires valid \"cid\" and \"tab_token\" "
                "arguments");
        }

        hash<string, hash<FieldInfo>> fmap;
        map (fmap += map {$1.name: $1}, $1.fields), doGetFields(ah);

        # check metadata
        foreach hash<auto> i in (ah.metadata.pairIterator()) {
            *hash<FieldInfo> field = fmap{i.key};
            if (!field) {
                return RestHandler::makeResponse(400, sprintf("unknown metadata key %y; valid metadata keys: %y", i.key,
                    keys fmap));
            }
            auto value;
            if (exists i.value) {
                switch (field.type) {
                    case "byte-size":
                        value = parse_memory_size(i.value);
                        break;
                    case "cron":
                        list<string> cron = i.value.split(" ");
                        value = {
                            "minute": cron[0],
                            "hour": cron[1],
                            "day": cron[2],
                            "month": cron[3],
                            "wday": cron[4],
                        };
                        break;
                    case "date":
                        value = date(i.value);
                        break;
                    default:
                        value = i.value;
                        break;
                }
            }
            ah.metadata{i.key} = value;
        }

        checkGroups(cx, ah.metadata.groups);

        int id;
        try {
            id = Qorus.qmm.createJob(ah.id, ah."code", ah.metadata, ah.tab_token);
            if (lock) {
                Qorus.creatorWsHandler.editLock(ah.cid, ah.tab_token, "job", id);
            }
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "JOB-CREATION-ERROR" || ex.err == WEBIDE_ERROR_INVALID_VALUE) {
                return RestHandler::makeResponse(400, sprintf("%s: %s", ex.err, ex.desc));
            }
            rethrow;
        }
        return RestHandler::makeResponse(201, {"id": id});
    }

    /** @REST PUT action=new

        @par Description
        Reserves a job id for creation and returns metadata information for jobs

        @par Return Value
        This API returns a hash with the following keys:
        - \c type: (string) \c job
        - \c id: (int) the job ID reserved
        - \c fields: (hash) field description for a new job

        @par Errors
        - <tt><b>403 Forbidden</b></tt>: \c AUTHORIZATION-ERROR: this exception is thrown when @ref RBAC is enabled
          and the user does not have sufficient privileges for the operation
    */
    hash<HttpHandlerResponseInfo> putNew(hash<auto> cx, *hash<auto> ah) {
        return doPutNew(cx, ah);
    }
}

class CreatorServiceRestClassBase inherits CreatorBaseRestClass {
    constructor() {
    }

    constructor(hash<auto> svc) : CreatorBaseRestClass(svc) {
    }

    string name() {
        return "service";
    }

    static *hash<auto> staticGetService(hash<auto> cx, *hash<auto> ah, softint id, int apiver = 6) {
        *hash<auto> svc = ServiceRestClass::staticGetService(cx, id, ah, apiver);
        # move options to position expected by UI
        if (svc && svc."runtime-options"."stack-size") {
            svc."stack-size" = get_byte_size(remove svc."runtime-options"."stack-size", 50);
            svc."stack-size" =~ s/([^\.])0+( .iB)$/$1$2/;
        }
        return svc;
    }

    static *softlist<hash<auto>> doGetUpdatedFields(int ix_id, string ref_type, int ref_id, string ref_name) {
        if (ref_type == "class") {
            CreatorServiceRestClassBase obj();
            # +=: ensure that metadata remains "hash<auto>"
            hash<auto> metadata += {
                "items": obj.doGetBaseClasses(),
            };
            return {
                "type": "service",
                "id": ix_id,
                "field": "base_class_name",
                "group": "interface-code-options",
                "metadata": metadata,
            };
        }
    }

    private list<hash<FieldGroupInfo>> doGetFieldsImpl() {
        return (
            <FieldGroupInfo>{
                "title": "service-options",
                "isOpen": True,
                "fields": (
                    <FieldInfo>{
                        "name": "name",
                        "type": FT_String,
                    },
                    <FieldInfo>{
                        "name": "version",
                        "type": FT_String,
                    },
                    <FieldInfo>{
                        "name": "description",
                        "type": FT_LongString,
                        "markdown": True,
                    },
                ),
            },
        );
    }

    private hash<IdFieldInfo> doPutGenerateIdImpl(*hash<auto> ah) {
        return <IdFieldInfo>{
            "type": "service",
            "id": sqlif.getNextSequenceValue("seq_services"),
            "fields": doGetFields(ah),
        };
    }

    private list<hash<FieldItemInfo>> doGetModulesImpl() {
        auto modules =  Qorus.options.get("service-modules");
        return modules ? map itemify($1), modules : ();
    }

    private list<hash<FieldItemInfo>> doGetBaseClassesImpl() {
        return baseClasses(<FieldItemInfo>{
            "label": "QorusService",
            "description": "Default Qorus service base class; part of the Qorus API",
        });
    }
}

/** @REST /v6/creator/service/{service}

    This REST URI path provides actions and information for a specific service in the creator API
*/
class CreatorServiceDefinitionRestClass inherits CreatorServiceRestClassBase, ServiceDefinitionRestClassV5 {
    constructor(hash<auto> svc) : CreatorServiceRestClassBase(svc), ServiceDefinitionRestClassV5(svc) {
    }

    /** @REST GET

        @par Description
        Returns information for a specific service with field information as well
    */
    hash<HttpHandlerResponseInfo> get(hash<auto> cx, *hash<auto> ah) {
        list<hash<FieldGroupInfo>> fields = doGetFields(ah);

        if (values) {
            processValues(\fields);
            remove values;
        }
        return RestHandler::makeResponse(200, {
            "type": "service",
            "id": sh.serviceid,
            "fields": fields,
            "code": Qorus.dsmanager.getOmqTable("services").selectRow({
                "where": {
                    "serviceid": sh.serviceid,
                },
                "columns": "code",
            }){"code"},
        });
    }
}

/** @REST /v6/creator/service

    This REST URI path provides actions and information for services in the creator API
*/
class CreatorServiceRestClass inherits CreatorServiceRestClassBase, ServiceRestClassV6 {
    *QorusRestClass subClassImpl(string arg, hash<auto> cx, *hash<auto> ah) {
        int id = ServiceRestClass::staticGetServiceId(arg);
        *hash<auto> svc = CreatorServiceRestClass::staticGetService(cx, ah, id, 6);
        if (!svc) {
            if (arg =~ /^[0-9]+$/) {
                svc.serviceid = id;
            } else {
                return;
            }
        }
        return new CreatorServiceDefinitionRestClass(svc);
    }

    /** @REST GET

        @par Description
        Returns information about service metadata
    */

    /** @REST PUT action=new

        @par Description
        Reserves a service id for creation and returns metadata information for services

        @par Return Value
        This API returns a hash with the following keys:
        - \c type: (string) \c service
        - \c id: (int) the service ID reserved
        - \c fields: (hash) field description for a new service

        @par Errors
        - <tt><b>403 Forbidden</b></tt>: \c AUTHORIZATION-ERROR: this exception is thrown when @ref RBAC is enabled
          and the user does not have sufficient privileges for the operation
    */
    hash<HttpHandlerResponseInfo> putNew(hash<auto> cx, *hash<auto> ah) {
        return doPutNew(cx, ah);
    }
}
