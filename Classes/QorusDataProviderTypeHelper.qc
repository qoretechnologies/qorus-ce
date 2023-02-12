
# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusDataProviderTypeHelper.qc helper class to convert a data hash to a data provider type object

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

# this file is automatically included by the Qorus client library and should not be included directly by Qorus client programs

%new-style
%require-types
%strict-args
%enable-all-warnings

public namespace OMQ {
public class QorusDataProviderTypeHelper {
    #! Returns a type from a hash
    static AbstractDataProviderType getType(hash<auto> type) {
        if (type.name.typeCode() != NT_STRING) {
            throw "TYPE-ERROR", sprintf("\"type\" argument is invalid; expecting key \"name\" to have type "
                "\"string\"; got %y instead", type.name.type());
        }
        if (exists type.options && type.options.typeCode() != NT_HASH) {
            throw "TYPE-ERROR", sprintf("\"type\" argument for type %y is invalid; expecting key \"options\" to have "
                "type \"hash\"; got %y instead", type.name, type.options.type());
        }
        if (type.fields || type.base_type =~ /^hash/) {
            HashDataType ht(type.name[0] == "*" ? AutoHashOrNothingType : AutoHashType, type.name, type.options);
            if (type.fields) {
                if (type.fields.typeCode() != NT_HASH) {
                    throw "TYPE-ERROR", sprintf("\"type\" argument for type %y is invalid; expecting key \"fields\" to have "
                        "type \"hash\"; got %y instead", type.name, type.fields.type());
                }
                map ht.addField($1), QorusDataProviderTypeHelper::getFields(type.fields);
            }
            return ht;
        }

        return AbstractDataProviderType::get(type.name, type.options);
    }

    #! For error handling with type errors
    static AbstractDataProviderType getType(auto type) {
        throw "TYPE-ERROR", sprintf("\"type\" argument is invalid; expecting type \"hash\"; got %y instead",
            type.type());
    }

    #! Returns fields from a hash
    static *list<AbstractDataField> getFields(hash<auto> fields) {
        return map QorusDataProviderTypeHelper::getField($1.key, $1.value), fields.pairIterator();
    }

    #! Return a single field
    static AbstractDataField getField(string name, hash<auto> value) {
        return new QoreDataField(name, value.desc, QorusDataProviderTypeHelper::getType(value.type),
            value."default" ? parse_yaml(value."default") : NOTHING);
    }

    #! Adds custom fields to a base field hash and returns the new hash type with all fields
    static HashDataType addCustomFields(AbstractDataProviderType type, hash<auto> custom_fields) {
        *hash<string, AbstractDataField> fields = type.getFields();
        HashDataType hdt();
        map hdt.addField($1), fields.iterator();

        foreach hash<auto> field in (custom_fields.iterator()) {
            type = hdt;
            QDBG_LOG("type: %y custom field: %y", type.getName(), field);
            HashDataType parent = hdt;
            string parent_elem = field.name;
            list<string> path = field.path.split(".");
            string final_elem = pop path;
            foreach string elem in (path) {
                *AbstractDataField f = type.getField(elem);
                if (!f) {
                    HashDataType new_hash();
                    (QorusDataProviderTypeHelper::getHashDataType(parent, parent_elem, type)).addField(new QoreDataField(elem, "custom field", new_hash));
                    parent_elem = elem;
                    parent = type;
                    type = new_hash;
                } else {
                    parent_elem = elem;
                    parent = type;
                    type = f.getType();
                }
            }
            (QorusDataProviderTypeHelper::getHashDataType(parent, parent_elem, type)).addField(QorusDataProviderTypeHelper::getField(final_elem, field));
        }

        return hdt;
    }

    static HashDataType getHashDataType(*HashDataType parent, string elem, AbstractDataProviderType type) {
        if ((type instanceof QoreHashDataType) || (type == AbstractDataProviderType::anyDataType)) {
            type = new HashDataType(new Type(type.getName()), type.getOptions());
            parent.addField(new QoreDataField(elem, "custom field", type));
            return type;
        }

        if (!(type instanceof HashDataType)) {
            throw "TYPE-ERROR", sprintf("cannot add field to type %y (%s)", type.getName(), type.className());
        }
        return cast<HashDataType>(type);
    }

    #! Returns a normalized type path string
    static string normalizeTypePath(string path) {
        return normalize_dir(path, "");
    }
}
}
