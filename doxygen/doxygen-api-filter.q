#!/usr/bin/env qore
# -*- mode: qore; indent-tabs-mode: nil -*-

/*
  Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

  **** NOTICE ****
    All information contained herein is, and remains the property of Qore
    Technologies, s.r.o. and its suppliers, if any.  The intellectual and
    technical concepts contained herein are proprietary to Qore Technologies,
    s.r.o. and its suppliers and may be covered by Czech, European, U.S. and
    Foreign Patents, patents in process, and are protected by trade secret or
    copyright law.  Dissemination of this information or reproduction of this
    material is strictly forbidden unless prior written permission is obtained
    from Qore Technologies, s.r.o.
*/

%new-style
%strict-args
%require-types

# we need the Util module for compare_version()
%requires Util

# for doxygen processing
%requires Qdx

# for REST schema types
%requires DataProvider

# for HTTP codes
%requires HttpServerUtil

# for filesystem functions
%requires FsUtil

# here we add fallback paths to the QORE_MODULE_DIR search path,
# in case QORE_MODULE_DIR is not set properly for Qorus
%append-module-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib:$OMQ_DIR/user/modules

%requires QorusVersion
%requires yaml

%allow-weak-references

%exec-class Filter

const Opts = {
    "outdir":  "D,outdir=s",
    "lssvc":   "l,list-system-services",
    "python":  "p,python=s",
    "rest":    "r,rest=s",
    "dsvc":    "S,do-system-services",
    "tmpdir":  "t,tmpdir=s",
    "debug":   "d,debug",
    "verbose": "v,verbose:i+",

    "help": "h,help"
};

class RestApi {
    public {
        # parent API
        *RestApi parent;

        # reference API
        *RestApi ref;

        # current URI path component
        *string uri_path;

        # docs for API
        *string docs;

        # hash of RestAction objects
        hash<string, RestAction> actions();

        # API version
        string api_version;

        #! RestAPi objects referencing this object
        *list<RestApi> backrefs;
    }

    private:internal {
        # hash of RestApi children
        hash<string, RestApi> children();

        # reference overridden flag
        bool ref_overridden = True;

        # hash of children inherited from any reference API; name -> parent object
        hash<string, RestApi> inherited_children;
    }

    constructor() {
    }

    constructor(RestApi parent, string uri_path, *string new_api_version) {
        self.parent := parent;
        self.uri_path = uri_path;
        api_version = new_api_version ?? parent.api_version;
    }

    constructor(RestApi parent, string uri_path, RestApi ref, *string new_api_version) {
        self.parent := parent;
        self.uri_path = uri_path;
        api_version = new_api_version ?? parent.api_version;
        setReferenceIntern(ref);
        # allow this automatically-generated reference to be overridden
        ref_overridden = False;
    }

    setDocs(string docs) {
        self.docs = docs;
    }

    setReference(RestApi ref) {
        checkRef("setReference", ref);
        setReferenceIntern(ref);
    }

    setReferenceIntern(RestApi ref) {
        self.ref := ref;
        ref.backrefs[ref.backrefs.size()] := self;
        #Fileter::debug("ref %y -> %y", ref.getUriPath(), getUriPath());
        # inherit all children immediately
        if (ref.children) {
            foreach hash<auto> i in (ref.children.pairIterator()) {
                if (i.value == self || children{i.key}) {
                    continue;
                }
                children{i.key} = inherited_children{i.key} = i.value;
            }
        }

        if (api_version != ref.api_version && api_version == uri_path
            && (*hash<auto> info = Filter::smap{ref.api_version})) {
            Filter::smap{api_version} = info;
            #Filter::debug("copied schema from %y -> %y\n", ref.api_version, api_version);
            return;
        }

        *RestApi pref = ref;
        while (pref) {
            string ref_uri_path = pref.getUriPath();
            # remove api version from path
            if (!ref_uri_path.comparePartial("/" + ref.api_version)) {
                splice ref_uri_path, 0, ref.api_version.length() + 1;
            }
            # copy all matching paths
            string uri_path = getUriPath();
            # remove api version from path
            if (!uri_path.comparePartial("/" + api_version)) {
                splice uri_path, 0, api_version.length() + 1;
            }
            foreach hash<auto> i in (Filter::smap{ref.api_version}.pairIterator()) {
                if (i.key.equalPartialPath(ref_uri_path)) {
                    string target = uri_path;
                    if (ref_uri_path != i.key) {
                        target += i.key.substr(ref_uri_path.length());
                    }
                    Filter::smap{api_version}{target} = i.value;
                    Filter::debug("copied schema from %y%y -> %y%y", ref.api_version, i.key, api_version,
                       target);
                }
            }

            if (*hash<auto> info = Filter::smap{ref.api_version}{ref_uri_path}) {
                string uri_path = getUriPath();
                # remove api version from path
                if (!uri_path.comparePartial("/" + api_version)) {
                    splice uri_path, 0, api_version.length() + 1;
                }
                Filter::smap{api_version}{uri_path} = info;
                #Filter::debug("copied schema from %y%y -> %y%y\n", ref.api_version, ref_uri_path, api_version,
                #   uri_path);
                break;
            }
            pref = pref.ref;
        }
    }

    setApiVersion(string version) {
        api_version = version;
    }

    RestApi getNewChild(string child_uri, *string new_api_version) {
        if (children{child_uri}) {
            # if inherited, override inherited child with new child based on the inherited child
            if (inherited_children{child_uri}) {
                RestApi child = new RestApi(self, child_uri, inherited_children{child_uri}, new_api_version);
                remove inherited_children{child_uri};
                return children{child_uri} = child;
            }
            return children{child_uri};
        } else {
            # otherwise return a new child object
            return children{child_uri} = new RestApi(self, child_uri, new_api_version);
        }
    }

    *RestApi getChild(string child) {
        return children{child};
    }

    hash<string, RestApi> getChildren() {
        hash<string, RestApi> rv;
        if (ref) {
            *hash<string, RestApi> ref_children = map {$1.key: $1.value}, ref.getChildren().pairIterator(),
                $1.value != self && ($1.value.api_version != "public" || self.api_version == "latest");
            rv += ref_children;
        }
        return rv + children;
    }

    private checkRef(string op, RestApi n_ref) {
        if (ref && n_ref != ref) {
            if (!ref_overridden) {
                ref_overridden = True;
                return;
            }
            throw "REST-API-ERROR", sprintf("cannot call %s::%s() if the REST API has a reference already (requested "
                "ref: %y (children: %y) existing: %y (children: %y))", self.className(), op, n_ref.getUriPath(),
                keys n_ref.children, ref.getUriPath(), keys ref.children);
        }
    }

    string getUriPath(*string parent_path) {
        string path;
        if (parent) {
            path = parent_path ?? parent.getUriPath();
        }
        if (path !~ /\/$/) {
            path += "/";
        }
        path += uri_path;
        return path;
    }

    addAction(string hdr, string docs) {
        RestAction action(hdr, docs, self);
        string name = action.getUniqueName();
        if (actions{name}) {
            throw "REST-API-ERROR", sprintf("action %y already defined for %y (%y)\nexisting: %N\nnew: %N\n", name,
                getUriPath(), hdr, actions{name}, action);
        }

        actions{name} = action;

        #Filter::debug("add %s action %y: %y %y", getUriPath(), name, action.schema, exists backrefs);
        if (action.schema && backrefs) {
            string uri_path = getUriPath();
            # remove api version from path
            if (!uri_path.comparePartial("/" + api_version)) {
                splice uri_path, 0, api_version.length() + 1;
            }
            hash<auto> info = Filter::smap{api_version}{uri_path};
        }
    }

    output(File of, *string parent_path, *string api_version) {
        string path = getUriPath(parent_path);
        #printf("%y (%s): ref: %y (parent: %y) pp: %y av: %y\n", path, uri_path, ref ? ref.uri_path : "",
        #    uri_path, parent ? parent.uri_path : "", parent_path, api_version);
        # make index path from path
        string ipath = path;
        ipath =~ s/\//_/g;
        ipath =~ s/{([^}]+)}/_$1_/g;
        ipath =~ s/\./_/g;
        if (docs || actions) {
            of.printf("    @section rest_api%s /api%s\n", ipath, path);
        }

        if (docs) {
            of.printf("%s\n", docs);
        }

        # merge referenced actions with our own
        actions = getActions();

        outputActions(of, ipath, path, api_version);

        # output children in sorted order
        *hash<string, RestApi> ch = getChildren();
        map $1.output(of, path, api_version), ch{sort(keys ch)}.iterator(),
            !api_version || ($1.uri_path !~ /^v[0-9]+/ && $1.uri_path != "latest" && $1.uri_path != "public");
    }

    outputDocs(File of, *string parent_path, *string api_version) {
        RestApi::output(of, parent_path, api_version);
        of.write("\n**/\n");
    }

    # return a sorted list of actions
    /** actions without an explicit action name are sorted before those that have an explicit action name
    */
    AbstractIterator getActionIterator() {
        hash<string, RestAction> actions = getActions();
        code asc = int sub (string l, string r) {
            RestAction la = actions{l};
            RestAction ra = actions{r};
            if (!la.action) {
                return !ra.action ? la.method <=> ra.method : -1;
            }
            return !ra.action ? 1 : la.action <=> ra.action;
        };
        return actions{sort(keys actions, asc)}.iterator();
    }

    private hash<string, RestAction> getActions() {
        return (ref ? ref.getActions() : NOTHING) + actions;
    }

    private outputActions(File of, string ipath, string path, *string api_version) {
        #Filter::debug("processing actions for %s -> %s %y", self.api_version, api_version, path);
        AbstractIterator i = getActionIterator();
        foreach RestAction a in (i) {
            of.printf("    @subsection rest_api_%s %s\n%s\n", a.getIndex(ipath), a.getUriRequest(path), a.getDocs());
            # copy a reference to every RestAction object inherited from a previous API version to the current one,
            # as long as it's >= "v7"
            if (api_version && a.schema && self.api_version != "public"
                && !Filter::smap{api_version}{a.path}{a.method}
                && compare_version(api_version, "v7") >= 0) {
                Filter::smap{api_version}{a.path}{a.method} := a;
                Filter::debug("processed %s -> %s %y (%y) %s", self.api_version, api_version, a.path, a.method);
            } else {
                #Filter::debug("skipped %s -> %s %y %s (%s)", self.api_version, api_version, a.path, a.method,
                #    a.getIndex(ipath));
            }
        }
    }
}

class RootRestApi inherits RestApi {
    private:internal {
        # api versions: version -> RestApi
        hash<string, RestApi> avh;

        # api page text
        hash<string, string> aph;

        # latest API
        RestApi latest;

        # public API
        RestApi publicapi;
    }

    constructor() {
        api_version = "root";
    }

    RestApi getNewChild(string child_uri) {
        string api_version;
        if (child_uri =~ /^v([0-9]+)$/ || child_uri == "latest" || child_uri == "public") {
            api_version = child_uri;
        } else {
            api_version = "v1";
        }
        RestApi rv = RestApi::getNewChild(child_uri, api_version);
        if (child_uri =~ /^v([0-9]+)$/) {
            if (!exists avh{child_uri}) {
                avh{child_uri} = rv;
                #printf("GOT %y\n", child_uri);
            }
        } else if (child_uri == "latest") {
            latest = rv;
        } else if (child_uri == "public") {
            publicapi = rv;
        }
        return rv;
    }

    savePage(string ver, string comment) {
        # remove trailing comment chars from string
        comment =~ s/\*\///;

        aph{ver} = comment;
    }

    output(File of) {
        # output in reverse order of API version
        foreach string api_version in (sort_descending(keys avh)) {
            if (aph{api_version}) {
                of.write(aph{api_version});
            } else {
                of.printf("\n**/\n\n/** @page rest_api_details_%s Qorus REST API %s Details\n\n    "
                    "@tableofcontents\n\n", api_version, api_version);
            }
            avh{api_version}.outputDocs(of, NOTHING, api_version);
        }

        # output the default v1 API third to last
        of.printf("\n/** @page rest_api_page_v1 Qorus REST API v1\n\n    @tableofcontents\n\n");
        outputDocs(of, NOTHING, "v1");

        # output the latest API second to last
        of.printf("\n/** @page rest_api_page_latest Qorus Latest REST API\n\n    @tableofcontents\n\n");
        latest.outputDocs(of, NOTHING);

        # output the public API last
        if (aph."public") {
            of.write(aph."public");
        } else {
            of.printf("\n/** @page rest_api_page_public Qorus Public REST API\n\n    @tableofcontents\n\n");
        }
        publicapi.outputDocs(of, NOTHING);

        of.printf("\n/** @page rest_api_data_structures Qorus REST API Data Structures\n\n    @tableofcontents\n\n");
    }

    #! Output Swagger 2.0 schemas for documented Qorus REST APIs
    outputSwagger(string dir) {
        hash<string, string> ix;
        foreach hash<auto> i in (Filter::smap.pairIterator()) {
            # skip REST API version < v7
            if (i.key != "public" && compare_version(i.key, "v7") < 0) {
                #printf("skipping %s %y\n", i.key, keys i.value);
                continue;
            }

            ix{i.key} = outputSwagger(dir, i.key, i.value);
        }
    }

    #! Output Swagger 2.0 schema for API descriptions
    private string outputSwagger(string dir, string apiver, hash<string, hash<string, RestAction>> amap) {
        string fn = sprintf("qorus-rest-api-%s.yaml", apiver);
        string apiuri = apiver;
        if (apiver == "public") {
            apiver = "v1";
        }
        if (Filter::opts.verbose) {
            printf("writing %y\n", fn);
        }

        FileOutputStream os(join_paths(dir, fn));
        StreamWriter writer(os);

        # write Swagger 2.0 header
        writer.printf("swagger: \"2.0\"
info:
  description: \"Qorus Integration Engine(R) REST API\"
  version: \"%s\"
  title: \"Qorus REST API\"
  contact:
    email: \"info@qoretechnologies.com\"
host: \"localhost\"
basePath: \"/api/%s\"
schemes:
- \"https\"
- \"http\"
produces:
- \"text/x-yaml\"
- \"application/json\"
consumes:
- \"text/x-yaml\"
- \"application/json\"
paths:\n", apiver[1..].toFloat().format(",.1"), apiuri);

        # API version -> definition -> True
        hash<string, bool> defmap;
        foreach hash<auto> i in (amap.pairIterator()) {
            string path = i.key;
            if (apiuri != "v1") {
                if (path.equalPartialPath("/" + apiuri)) {
                    splice path, 0, apiuri.length() + 1;
                } else {
                    #throw "SCHEMA-ERROR", sprintf("invalid path %y; expecting beginning as %y", path, "/" + apiuri);
                }
            }
            writer.printf("  %s:\n", path);
            map $1.outputSwagger(writer, path, \defmap), i.value.iterator();
        }

        outputDefinitions(writer, defmap);
        return fn;
    }

    private outputDefinitions(StreamWriter writer, *hash<string, bool> defmap) {
        if (!defmap) {
            return;
        }
        writer.printf("definitions:\n");
        foreach string typename in (keys defmap) {
            if (typename == "AnyType") {
                writer.print("  AnyType: {}\n");
                continue;
            }
            *HashDataType t = RestAction::tmap{typename};
            if (!t) {
                throw "TYPE-ERROR", sprintf("cannot find type %y in map: %y", typename, keys RestAction::tmap);
            }
            on_error rethrow $1.err, sprintf("type %y: %s", t.getName(), $1.desc);
            string name = t.getName();
            name =~ s/^\*/_/;
            writer.printf("  %s:\n", name);
            writer.printf("    type: \"object\"\n");
            StringOutputStream props();
            StreamWriter propwriter(props);
            list<string> required;
            foreach AbstractDataField field in (t.getFields().iterator()) {
                propwriter.printf("%s%s:\n", strmul(" ", 6), field.getName());
                outputSwaggerTypeInfo(propwriter, 8, field.getType(), field.getDescription());
                if (field.isMandatory()) {
                    required += field.getName();
                }
            }
            if (required) {
                writer.print("    required:\n");
                map writer.printf("    - %y\n", $1), required;
            }
            string propstr = props.getData();
            if (propstr) {
                writer.print("    properties:\n");
                writer.print(propstr);
            }
            if (t instanceof HashDataType) {
                *AbstractDataProviderType deftype = cast<HashDataType>(t).getDefaultOtherFieldType();
                if (deftype) {
                    writer.printf("    additionalProperties:\n");
                    outputSwaggerTypeInfo(writer, 6, deftype);
                }
            }
            if (t.getName()[0] == "_" && !t.isOrNothingType()) {
                throw "ERROR", t.getName();
            }
            if (t.isOrNothingType()) {
                writer.printf("    x-nullable: true\n");
            }
        }
    }

    private static outputSwaggerTypeInfo(StreamWriter writer, int indent, AbstractDataProviderType type,
            *string desc) {
        if (*string typestr = RestAction::getSwaggerTypeString(indent, type)) {
            writer.print(typestr);
        } else if (!desc) {
            writer.printf("%sdescription: not available\n", strmul(" ", indent));
        }
        if (desc) {
            writer.printf("%sdescription: %y\n", strmul(" ", indent), RestAction::fixString(desc));
        }
    }
}

hashdecl TypeStackInfo {
    int depth;
    HashDataType type;
}

class RestAction {
    public {
        string method;
        *string action;

        #! A unique ID in the API version
        string id;

        #! Identifies the full relative URI path starting with "/"
        string path;

        # output in schema?
        bool schema = False;

        # any summary description
        string summary;

        # any description
        string desc;

        #! If the API takes any arguments
        bool any_params;

        #! API param definitions
        HashDataType params;

        #! Return description
        string return_desc;

        #! Return type
        AbstractDataProviderType return_type;

        #! Return code
        string return_code;

        #! Errors
        hash<string, string> errmap;

        #! Permissions required
        list<string> perms;

        #! Any "@see" lines
        list<string> see;

        #! Any "@since" line
        string since;

        #! static map of hash types
        static hash<string, HashDataType> tmap = {
            "UndefinedHash": new HashDataType("UndefinedHash"),
            "_UndefinedHash": new HashDataType(AutoHashOrNothingType, "*UndefinedHash"),
        };

        #! static map of type dependencies; typename -> depname -> True
        static hash<string, hash<string, bool>> depmap;

        #! Vowel map
        const VowelMap = {
            "A": True,
            "E": True,
            "I": True,
            "O": True,
            "U": True,
        };
    }

    private {
        string docs;
    }

    private:internal {
        #! parent object
        RestApi parent;

        #! type stack while parsing
        list<hash<TypeStackInfo>> tstack;

        #! pending hash type to push
        list<HashDataType> pending_types;
    }

    constructor(string hdr, string docs, RestApi parent) {
        self.parent := parent;

        # get HTTP method
        method = (hdr =~ x/([A-Z]+)/)[0];

        # get action if present
        action = (hdr =~ x/action=(.+)/)[0];

        setIds(parent.getUriPath());

        if (*string stxt = (docs =~ x/@SCHEMA(.*)@ENDSCHEMA/s)[0]) {
            schema = True;
            docs = regex_subst(docs, "@SCHEMA.*@ENDSCHEMA", "", RE_MultiLine);

            parseSchema(stxt);

            # NOTE: we may overwrite imported map entries here
            Filter::smap{parent.api_version}{path}{method} := self;
            Filter::debug("set schema for %y %y %y", parent.api_version, path, method);
        }

        self.docs = docs;
    }

    private addPathParams(*list<string> path_params) {
        foreach string param in (path_params) {
            QoreStringDataType type(NOTHING, {"loc": "path"});
            QoreDataField field(param, sprintf("path param %y", param), type);
            addFieldToHash("params", 0, field);
        }
    }

    #! Returns the doxygen doc string for this API action
    string getDocs() {
        if (!schema) {
            return docs;
        }
        string pre = strmul(" ", 4);
        string rv;
        if (desc) {
            rv += pre + sprintf("@par Description\n%s%s\n\n", pre, desc);
        }
        rv += pre + "@par Arguments\n";
        if (any_params) {
            rv += pre + "This API accepts any arguments\n\n";
        } else if (params) {
            *hash<string, AbstractDataField> fields = cast<*hash<string, AbstractDataField>>(
                map {$1.key: $1.value}, params.getFields().pairIterator(),
                    $1.value.getType().getTag("loc") != "path"
            );
            *hash<string, AbstractDataField> body_fields;
            if (method != "GET" && (*AbstractDataField body_field = remove fields.body)) {
                body_fields = body_field.getType().getFields();
            }
            int size = (fields ? fields.size() : 0) + (body_fields ? body_fields.size() : 0);
            if (size) {
                rv += pre + sprintf("This API takes the following hash argument%s:\n", size == 1 ? "" : "s");
                if (fields) {
                    map rv += getDocTypeEntry($1.getName(), $1.getType(), $1.getDescription()),
                        fields.iterator();
                }
                if (body_fields) {
                    map rv += getDocTypeEntry($1.getName(), $1.getType(), $1.getDescription()),
                        body_fields.iterator();
                }
            }
            rv += "\n";
        } else {
            rv += pre + "This API takes no arguments\n\n";
        }

        rv += pre + "@par Return Value\n";
        {
            *hash<string, AbstractDataField> fields = return_type.getFields();
            *AbstractDataProviderType other_type;
            if (!fields) {
                if (return_type instanceof HashDataType
                    && (other_type = cast<HashDataType>(return_type).getDefaultOtherFieldType())) {
                    fields = other_type.getFields();
                }
            }
            if (fields) {
                string name = return_type.getName();
                string aoran = VowelMap{name[0]} ? "n" : "";
                rv += pre + sprintf("This API returns a%s <i>%s</i> hash with the following key%s%s:\n", aoran, name,
                    fields.size() == 1 ? "" : "s", return_desc ? " (" + return_desc + ")" : "");
                map rv += getDocTypeEntry($1.getName(), $1.getType(), $1.getDescription()),
                    fields.iterator();
            } else if (other_type) {
                string name = fixType(return_type.getName());
                string aoran = VowelMap{name[0]} ? "n" : "";
                rv += pre + sprintf("This API returns a%s <i>%s</i> hash; keys have the following format:\n", aoran,
                    name);
                rv += getDocTypeEntry("any", other_type, return_desc ?? "return hash values", 4, True);
            } else {
                rv += pre + sprintf("This API returns a value of type <i>%s</i>%s\n", fixType(return_type.getName()),
                    return_desc ? ": " + return_desc : "");
            }
        }
        rv += "\n";

        if (errmap) {
            rv += pre + "@par Errors\n";
            map rv += pre + sprintf("- <tt><b>%d %s</b></tt>: %s\n", $1.key, HttpCodes{$1.key} ?? "Unknown HTTP code",
                $1.value), errmap.pairIterator();
            rv += "\n";
        }

        if (perms) {
            rv += pre + "@note Requires one of the following permissions:\n";
            map rv += pre + sprintf("- <tt>@ref OMQ::QR_%s \"%s\"</tt>\n", replace($1, "-", "_"), $1), perms;
            rv += "\n";
        }

        if (see) {
            rv += pre + "@see\n";
            map rv += pre + "- " + $1 + "\n", see;
            rv += "\n";
        }

        if (since) {
            rv += pre + "@since " + since + "\n\n";
        }

        return rv;
    }

    private string fixType(string type) {
        type =~ s/</&lt;/g;
        type =~ s/>/&gt;/g;
        return type;
    }

    private string getDocTypeEntry(string key, AbstractDataProviderType type, string desc, int indent = 4, *bool generic) {
        string pre = strmul(" ", indent);
        string rv = generic
            ? sprintf("%s- <i>%s</i> (%s): %s\n", pre, key, fixType(type.getName()), desc)
            : sprintf("%s- <b><tt>%s</tt></b> (%s): %s\n", pre, key, fixType(type.getName()), desc);
        *hash<string, AbstractDataField> fields = type.getFields();
        *AbstractDataProviderType other_type;
        if (!fields) {
            if (type instanceof HashDataType
                && (other_type = cast<HashDataType>(type).getDefaultOtherFieldType())) {
                if (other_type.getName() != "auto") {
                    fields = other_type.getFields();
                } else {
                    remove other_type;
                }
            }
        }
        if (fields) {
            map rv += getDocTypeEntry($1.getName(), $1.getType(), $1.getDescription(), indent + 2), fields.iterator();
        } else if (other_type) {
            string typename = fixType(other_type.getName());
            rv += sprintf("%s  - <i>key</i> (%s): %s value\n", pre, typename, typename);
        }
        return rv;
    }

    outputSwagger(StreamWriter writer, string realpath, reference<hash<string, bool>> defmap) {
        if (realpath != path) {
            updatePath(realpath);
        }
        Filter::debug("swagger: %s %s", method, path);

        writer.printf("    %s:\n", method.lwr());
        writer.printf("      summary: %y\n", fixString(summary));
        writer.printf("      description: %y\n", fixString(desc));
        writer.printf("      operationId: %y\n", id);
        writer.printf("      parameters:%s\n", params ? "" : " []");
        if (params) {
            outputSwaggerParams(writer, 6, \defmap);
        }
        writer.printf("      responses:\n");
        outputSwaggerResponse(writer, return_code ?? "200", return_type, fixString(return_desc), \defmap);
        string pre = strmul(" ", 8);
        foreach hash<auto> i in (errmap.pairIterator()) {
            # i.key = the HTTP response code
            if (i.key == "409") {
                # NOTE: this should really describe an exception hash
                defmap.UndefinedHash = True;
                writer.printf("%s%y:\n%s  description: %y\n%s  schema:\n%s    "
                    "$ref: \"#/definitions/UndefinedHash\"\n",
                    pre, i.key, pre, fixString(i.value), pre, pre);
            } else {
                writer.printf("%s%y:\n%s  description: %y\n%s  schema: {}\n",
                    pre, i.key, pre, fixString(i.value), pre, pre);
            }
        }
    }

    static string fixString(string str) {
        # remove doxygen links
        str =~ s/@ref (?:[^"]+) "([^"]+)"/$1/g;
        str =~ s/@ref nothing/no value/g;
        str =~ s/@ref True/true/g;
        str =~ s/@ref False/false/g;
        str =~ s/@ref //g;
        # remove doxygen markup
        str =~ s/\\c //g;
        str =~ s/\\a //g;
        return str;
    }

    static *string getSwaggerTypeString(int indent, AbstractDataProviderType type,
            *reference<hash<string, bool>> defmap, *bool output_any) {
        return RestAction::getSwaggerTypeString(indent, type.getName(), \defmap, output_any);
    }

    static *string getSwaggerTypeString(int indent, string typename, *reference<hash<string, bool>> defmap,
            *bool output_any) {
        string rv;
        string pre = strmul(" ", indent);
        if (*HashDataType t = RestAction::lookupType(\typename)) {
            string name = t.getName();
            name =~ s/^\*/_/;
            rv = sprintf("%s$ref: \"#/definitions/%s\"\n", pre, name);
            RestAction::addDependencies(typename, \defmap);
        } else {
            string format;
            bool required;
            string subtype;
            string swagger_type = RestAction::getSwaggerType(typename, \format, \required, \subtype);
            if (swagger_type != "any") {
                rv = sprintf("%stype: \"%s\"\n", pre, swagger_type);
                if (format) {
                    rv += sprintf("%sformat: \"%s\"\n", pre, format);
                }
                if (subtype) {
                    rv += sprintf("%sitems:\n", pre);
                    rv += RestAction::getSwaggerTypeString(indent + 2, subtype, \defmap, True);
                }
                if (!required) {
                    rv += sprintf("%sx-nullable: true\n", pre);
                }
            } else if (output_any) {
                rv = sprintf("%s$ref: \"#/definitions/AnyType\"\n", pre);
                defmap.AnyType = True;
            }
        }
        return rv;
    }

    static *HashDataType lookupType(reference<string> name) {
        if (name == "hash<auto>") {
            name = "UndefinedHash";
            return tmap.UndefinedHash;
        }
        if (name == "*hash<auto>") {
            name = "_UndefinedHash";
            return tmap._UndefinedHash;
        }
        return tmap{name};
    }

    static addDependencies(string typename, *reference<hash<string, bool>> defmap, *hash<string, bool> pmap) {
        if (defmap{typename}) {
            return;
        }
        defmap{typename} = True;
        map RestAction::addDependencies($1, \defmap), keys depmap{typename};
    }

    private outputSwaggerParams(StreamWriter writer, int indent, reference<hash<string, bool>> defmap) {
        *hash<string, AbstractDataField> fields = params.getFields();
        string loc = method == "GET" ? "query": "body";
        if (!fields) {
            outputAnySwaggerParams(writer, indent);
            return;
        }
        outputSwaggerFieldsIntern(writer, indent, loc, fields, \defmap);
    }

    private outputSwaggerFieldsIntern(StreamWriter writer, int indent, string loc, hash<string, AbstractDataField> fields,
            reference<hash<string, bool>> defmap) {
        foreach AbstractDataField field in (fields.iterator()) {
            string thisloc = field.getType().getTag("loc") ?? loc;
            writer.printf("%s- in: %y\n", strmul(" ", indent), thisloc);
            writer.printf("%sname: %y\n", strmul(" ", indent + 2), field.getName());
            writer.printf("%sdescription: %y\n", strmul(" ", indent + 2), fixString(field.getDescription()));
            writer.printf("%srequired: %s\n", strmul(" ", indent + 2), field.isMandatory() ? "true" : "false");
            *string typestr = getSwaggerTypeString(indent + 2, field.getType(), \defmap);
            if (typestr =~ /\$ref/) {
                writer.printf("%sschema:\n", strmul(" ", indent + 2));
                writer.print("  " + typestr);
            } else {
                writer.print(typestr);
            }
        }
    }

    private outputAnySwaggerParams(StreamWriter writer, int indent) {
        if (method == "GET") {
            throw "SCHEMA-ERROR", sprintf("%s: cannot support any arguments with GET", id);
        }
        if (!any_params) {
            throw "SCHEMA-ERROR", sprintf("%s: no fields but any_params not set", id);
        }
        writer.printf("%s- in: \"body\"\n", strmul(" ", indent));
        writer.printf("%sname: \"body\"\n", strmul(" ", indent + 2));
        writer.printf("%sdescription: \"This API takes any arguments\"\n", strmul(" ", indent + 2));
        writer.printf("%srequired: false\n", strmul(" ", indent + 2));
        writer.printf("%sschema:\n", strmul(" ", indent + 2));
        writer.printf("%stype: \"object\"\n", strmul(" ", indent + 4));
    }

    private static outputSwaggerResponse(StreamWriter writer, string status_code, AbstractDataProviderType type,
            string return_desc, reference<hash<string, bool>> defmap) {
        writer.printf("        %y:\n", status_code);
        writer.printf("%sdescription: %y\n", strmul(" ", 10), return_desc);
        *string typestr = RestAction::getSwaggerTypeString(12, type, \defmap, True);
        if (typestr) {
            writer.printf("%sschema:\n", strmul(" ", 10));
            writer.print(typestr);
        }
    }

    private static string getSwaggerType(AbstractDataProviderType type, reference<string> format,
            reference<bool> required, reference<string> subtype) {
        return RestAction::getSwaggerType(type.getName(), \format, \required, \subtype);
    }

    private static string getSwaggerType(string name, reference<string> format, reference<bool> required,
            reference<string> subtype) {
        required = (name[0] != "*" && name != "any");
        name =~ s/^\*//;
        name =~ s/^soft//;
        switch (name) {
            case "int":
                format = "int64";
                return "integer";
            case "number":
            case "float":
                format = "double";
                return "number";
            case "binary":
                format = "base64";
                return "string";
            case "bool":
                return "boolean";
            case "string":
                return name;
            case "date":
                format = "date-time";
                return "string";
            case "any":
            case "auto":
                return "any";
            case "hash":
            case "hash<auto>": {
                throw "ERROR", sprintf("%y must be handled at a higher level as UndefinedHash", name);
            }
            case =~ /^list/: {
                *string st = (name =~ x/^list<(.*)>$/)[0];
                if (st) {
                    subtype = st;
                    if (*string swagger_type = (st =~ x/ (.*)$/)[0]) {
                        subtype = swagger_type;
                    }
                }
                return "array";
            }
            default:
                throw "UNKNOWN-TYPE", sprintf("can't convert qore type %y to Swagger type", name);
        }
    }

    #! returns a unique name for the action
    string getUniqueName() {
        string name = method;
        if (action)
            name += "_" + action;
        return name;
    }

    #! returns a section name for the action
    *string getIndex(string ipath) {
        string str = sprintf("%s%s", method, ipath);
        if (action) {
            str += "_" + action;
        }

        return str;
    }

    #! returns a URI request string
    string getUriRequest(string path) {
        string ur = sprintf("%s /api%s", method, path);
        if (action)
            ur += sprintf("?action=%s", action);
        return ur;
    }

    private updatePath(string path) {
        setIds(path);
        if (params) {
            # remove path params and add new ones
            HashDataType new_params("params");
            map new_params.addField($1), params.getFields().iterator(), $1.getType().getTags().loc != "path";

            if (*list<string> path_params = (path =~ x/\/{([^}]+)}/g)) {
                tstack = ();
                push(0, new_params);
                addPathParams(path_params);
            }
            params = new_params;
        }
    }

    private setIds(string uri) {
        uri =~ s/^\/(v[0-9]|public)//g;
        path = uri;
        uri =~ s/^\///g;
        uri =~ s/\//-/g;
        id = sprintf("%s-%s", method.lwr(), uri);
        if (exists action) {
            id += "-" + action;
            path += "/" + action;
        }
    }

    private parseSchema(string stxt) {
        on_error rethrow $1.err, sprintf("%s (while parsing schema for id %y)", $1.desc, id);
        string state;
        hash<string, hash<auto>> query_params;
        HashDataType body_param;
        DataLineIterator i(stxt);
        while (i.next()) {
            string line = i.getValue();
            int depth = (line =~ x/^( +)/g)[0].size();
            if (line && !depth) {
                throw "SCHEMA-ERROR", sprintf("invalid line with depth 0: %y", line);
            }
            while (line =~ /\\$/) {
                if (!i.next()) {
                    throw "LINE-CONTINUATION-ERROR", "line ends in '\\' at the end of input";
                }
                string nline = i.getValue();
                trim nline;
                splice line, -1, 1, nline;
            }
            trim line;
            line =~ s/\s+/ /g;

            #Filter::debug("line: %y", line);

            *string str = (line =~ x/^\s*@([a-z]+)/)[0];
            if (str) {
                if (depth < 4) {
                    throw "SCHEMA-ERROR", sprintf("insufficent indentation: %y", line);
                }
                switch (str) {
                    case "return":
                        if (return_type) {
                            throw "SCHEMA-ERROR", sprintf("duplicate return declaration in ID %y", id);
                        }
                        string str0 = line;
                        str0 =~ s/^@return //;
                        return_type = getDataType(str0, \return_desc, \return_code, depth);
                        if (pending_types) {
                            pushDependency(depth - 2);
                        }
                        break;

                    case "summary":
                        string str0 = line;
                        str0 =~ s/^@summary //;
                        summary = str0;
                        break;

                    case "desc":
                        string str0 = line;
                        str0 =~ s/^@desc //;
                        desc = str0;
                        break;

                    case "error": {
                        string str0 = line;
                        str0 =~ s/^@error //;
                        (*string err, *string desc) = (str0 =~ x/\(([^\)]+)\): (.*)$/);
                        if (!err || !desc) {
                            throw "SCHEMA-ERROR", sprintf("invalid schema type declaration: %y (err: %y desc: %y)",
                                str0, err, desc);
                        }
                        if (errmap{err}) {
                            throw "SCHEMA-ERROR", sprintf("duplicate error %y", err);
                        }
                        errmap{err} = desc;
                        break;
                    }

                    case "params":
                        if (any_params || params) {
                            throw "SCHEMA-ERROR", "params declared twice";
                        }
                        if (line =~ /^@params \(any\)/) {
                            if (method == "GET") {
                                throw "SCHEMA-ERROR", sprintf("%s: cannot support any arguments with GET", id);
                            }
                            any_params = True;
                            params = new HashDataType("params");
                        } else {
                            params = new HashDataType("params");
                            tstack = ();
                            if (method != "GET") {
                                string name = getBodyParamName();
                                body_param = new HashDataType(name);
                                tmap{name} = body_param;
                                QoreDataField field("body", "message body", body_param);
                                params.addField(field);
                                push(depth, body_param);
                            } else {
                                push(depth, params);
                            }
                        }
                        break;

                    case "since": {
                        string str0 = line;
                        str0 =~ s/^@since //;
                        desc = str0;
                        break;
                    }

                    case "perms": {
                        string str0 = line;
                        str0 =~ s/^@perms //;
                        perms = map trim($1), str0.split(",");
                        break;
                    }

                    case "see":
                        break;

                    default:
                        throw "INVALID-SCHEMA-STATE", sprintf("unknown state: %y", str);
                }
                state = str;
                continue;
            }
            if (state == "see" && (str = (line =~ x/- (.*)$/)[0])) {
                see += str;
                continue;
            }
            *string loc;
            *string rest;
            (loc, str, rest) = (line =~ x/- (Q )?([a-z_0-9-]+) (.*)$/i);
            #Filter::debug("loc: %y str: %y rest: %y", loc, str, rest);
            if (str && rest) {
                if (depth < 4) {
                    throw "SCHEMA-ERROR", sprintf("insufficent indentation: %y", line);
                }
                string desc;
                bool query_param;
                if (loc == "Q ") {
                    query_param = True;
                } else if (loc) {
                    throw "SCHEMA-ERROR", sprintf("unknown parameter location code %y; expecting Q", loc);
                }
                if (query_param) {
                    if (state != "params") {
                        throw "SCHEMA-ERROR", sprintf("parameter location can only be set for parameters; "
                            "parameter %y set in state %y; expecting \"params\"", str, state);
                    }
                    if (depth != tstack.last().depth) {
                        throw "SCHEMA-ERROR", sprintf("parameter location can only be set for top-level parameters; "
                            "parameter %y cannot be set", str);
                    }
                }
                AbstractDataProviderType t = getDataType(rest, \desc, NOTHING, depth, query_param);
                Filter::debug("state: %y str: %y (%s qp: %y) desc: %s", state, str, t.getName(), query_param, desc);
                on_exit remove pending_types;
                switch (state) {
                    case "return":
                        QoreDataField field(str, desc, t);
                        addFieldToHash(state, depth, field);
                        break;

                    case "params":
                        if (query_param) {
                            query_params{str} = {
                                "desc": desc,
                                "type": t,
                            };
                        } else {
                            QoreDataField field(str, desc, t);
                            addFieldToHash(state, depth, field);
                        }
                        #printf("REST %s: added param %y\n", id, str);
                        break;

                    default:
                        throw "SCHEMA-ERROR", sprintf("member type declared with state %y: %y", state, line);
                }
            }
        }

        # process any path parameters
        *list<string> path_params = (path =~ x/\/{([^}]+)}/g);
        if (path_params || query_params) {
            if (!params) {
                params = new HashDataType("params");
            }
            tstack = ();
            push(0, params);
            foreach string param in (path_params) {
                QoreStringDataType type(NOTHING, {"loc": "path"});
                QoreDataField field(param, sprintf("path param %y", param), type);
                addFieldToHash(state, 0, field);
            }
            foreach hash<auto> i in (query_params.pairIterator()) {
                QoreDataField field(i.key, i.value.desc, i.value.type);
                addFieldToHash(state, 0, field);
            }
        }

        if (method != "GET" && body_param && !body_param.getFields()) {
            remove body_param;
            HashDataType new_params("params");
            map new_params.addField($1.value), params.getFields().pairIterator(), $1.key != "body";
            if (new_params.getFields()) {
                Filter::debug("setting new params: %y", keys new_params.getFields());
                params = new_params;
            } else {
                Filter::debug("removing params");
                remove params;
            }
        }

        # rewrite body parameter with an "or nothing" type if all parameters are optional
        if (body_param) {
            bool rewrite = True;
            foreach AbstractDataField f in (body_param.getFields().iterator()) {
                if (!f.getType().isOrNothingType()) {
                    rewrite = False;
                    break;
                }
            }
            if (rewrite) {
                string name = "*" + getBodyParamName();
                HashDataType new_body_param(AutoHashOrNothingType, name);
                tmap{name} = new_body_param;
                map new_body_param.addField($1), body_param.getFields().iterator();
                QoreDataField field("body", "message body", new_body_param);

                HashDataType new_params("params");
                map new_params.addField($1.key == "body" ? field : $1.value),
                    params.getFields().pairIterator();
                params = new_params;
                body_param = new_body_param;
            }
        }

        if (!return_type) {
            throw "SCHEMA-ERROR", sprintf("%s: no return type declared", id);
        }
    }

    #! Returns the body parameter name
    string getBodyParamName() {
        string name = id;
        name =~ s/[{}]//g;
        name = sprintf("%s-body", name);
        return name;
    }

    #! Adds a field to the correct data structure
    private addFieldToHash(string state, int depth, QoreDataField field) {
        if (!tstack) {
            throw "SCHEMA-ERROR", sprintf("cannot add field %y (state %y); no current hash on stack",
                field.getName(), state);
        }
        hash<TypeStackInfo> p = tstack.last();
        Filter::debug("addFieldToHash() state: %y depth: %d field: %y (%s): stack depth: %d (%y)", state, depth,
            field.getName(), field.getType().getName(), p.depth, p.type.getName());
        while (depth < p.depth) {
            pop tstack;
            if (!tstack) {
                throw "SCHEMA-ERROR", sprintf("%s: cannot add field %y (state %y) with depth %d; stack has no "
                    "suitable entries", parent.getUriPath(), field.getName(), state, depth);
            }
            p = tstack.last();
            Filter::debug("addFieldToHash() popped; new stack depth %d (%y)", p.depth, p.type.getName());
        }
        if (depth > p.depth) {
            throw "SCHEMA-ERROR", sprintf("cannot add field %y (state %y) with depth %d to stack entry %y with "
                "depth %d", field.getName(), state, depth, p.type.getName(), p.depth);
        }

        if (childHasFields(p.type)) {
            throw "SCHEMA-ERROR", sprintf("duplicated type info in type %y (while adding field %y)", p.type.getName(),
                field.getName());
        }

        p.type.addField(field);
        if (pending_types) {
            pushDependency(depth);
        }
    }

    private static bool childHasFields(AbstractDataProviderType type) {
        if (type.getFields() || !(type instanceof HashDataType)) {
            return False;
        }
        *AbstractDataProviderType other = cast<HashDataType>(type).getDefaultOtherFieldType();
        if (!other) {
            return False;
        }
        if (other.getFields()) {
            return True;
        }
        return RestAction::childHasFields(other);
    }

    #! Returns the given type and a reference to the description
    private AbstractDataProviderType getDataType(string str, reference<string> desc, *reference<string> http_code,
            int depth, *bool query_param) {
        (*string type, *string desc0) = (str =~ x/\(([^\)]+)\): (.*)$/);
        if (!type || !desc0) {
            throw "SCHEMA-ERROR", sprintf("invalid schema type declaration: %y (type: %y desc: %y)", str, type,
                desc0);
        }
        desc = desc0;
        if (*string http_code0 = (desc =~ x/^([0-9]{3}):/)[0]) {
            http_code = http_code0;
            desc =~ s/^([0-9]{3}): ?//;
        }
        if (*string arraytype = (type =~ x/\*?list<(.*)>$/)[0]) {
            string decl = sprintf("(%s): ignored", arraytype);
            string fakedesc;
            AbstractDataProviderType st = RestAction::getDataType(decl, \fakedesc, NOTHING, depth);
            return query_param
                ? new ListDataType(st, type[0] == "*", NOTHING, {"loc": "query"})
                : new ListDataType(st, type[0] == "*");
        } else if (type =~ / /) {
            string orig_type = type;
            string subtype;
            # check for subtype
            if (*string st = (type =~ x/^\*?hash\[(.+)\]/)[0]) {
                subtype = st;
                type =~ s/hash\[.*\](.*)/hash$1/;
            }
            list<string> l = type.split(" ");
            type = l[0];
            *string name = l[1];
            if (!name) {
                throw "SCHEMA-ERROR", sprintf("invalid type %y; missing hash name", orig_type);
            }
            if (type[0] == "*") {
                name = "*" + name;
            }
            if (type =~ /hash/ && (*HashDataType t = RestAction::lookupType(\name))) {
                push pending_types, t;
                return t;
            }
            string subtypename;
            if (l.size() > 2) {
                if (subtype !~ /^\*?hash^/ || l.size() != 3) {
                    throw "SCHEMA-ERROR", sprintf("invalid type declaration %y", l.join(" "));
                }
                subtypename = l[2];
            }
            HashDataType hashtype(name[0] == "*" ? AutoHashOrNothingType : AutoHashType, name);
            tmap{name} = hashtype;
            if (pending_types) {
                depmap{pending_types.last().getName()}{name} = True;
                Filter::debug("adding dep %y -> %y", pending_types.last().getName(), name);
            } else {
                registerDependency(name, depth);
            }
            push pending_types, hashtype;
            if (subtype) {
                string decl = sprintf("(%s): ignored", subtype);
                string fakedesc;
                AbstractDataProviderType st = RestAction::getDataType(decl, \fakedesc, NOTHING, depth);
                hashtype.setDefaultOtherFieldType(st);
            }
            return hashtype;
        }

        if (type == "string" && query_param) {
            return new QoreStringDataType(NOTHING, {"loc": "query"});
        }
        if (type == "*string" && query_param) {
            return new QoreStringOrNothingDataType(NOTHING, {"loc": "query"});
        }
        if (query_param) {
            throw "SCHEMA-ERROR", sprintf("cannot set a query parameter with type %y; must be \"string\" "
                "(str: %y desc: %y)", type, str, desc);
        }
        return AbstractDataProviderType::get(type);
    }

    private registerDependency(string name, *int depth) {
        for (int i = tstack.size() - 1; i >= 0; --i) {
            #Filter::debug("registerDependency() name: %y d: %y tstack: %y d: %y", name, depth, tstack[i].type.getName(),
            #   tstack[i].depth);
            if (!depth || tstack[i].depth < depth) {
                depmap{tstack[i].type.getName()}{name} = True;
                Filter::debug("registerDependency() adding dep %y (%d) -> %y (%y)", tstack[i].type.getName(),
                    tstack[i].depth, name, depth);
                break;
            }
        }
    }

    #! Pushes a hash type on the type stack
    private push(int depth, HashDataType type) {
        Filter::debug("push d: %d -> %d (%y -> %y)", tstack ? tstack.last().depth : 0, depth,
            tstack ? tstack.last().type.getName() : NOTHING, type.getName());
        if (tstack) {
            registerDependency(type.getName());
        }
        push tstack, hash<TypeStackInfo>{
            "depth": depth,
            "type": type,
        };
    }

    #! Pushes the top-level pending type on the stack, adds a dependency to the first pending type
    private pushDependency(int depth) {
        Filter::debug("push d: %d -> %d (%y -> %y / %y)", tstack ? tstack.last().depth : 0, depth + 2,
            tstack ? tstack.last().type.getName() : NOTHING, pending_types[0].getName(),
            pending_types.last().getName());
        if (tstack) {
            registerDependency(pending_types[0].getName());
        }
        push tstack, hash<TypeStackInfo>{
            "depth": depth + 2,
            "type": pop pending_types,
        };
    }
}

hashdecl ServiceTagInfo {
    string desc;
    string name;
    string comment;
    string lock;
    bool intern;
    bool write;
    string source;
}

class Filter {
    private {
        *string sname;
        *string psname;
        string build;
        string qorever;
        static bool debug;

        # REST API info
        RootRestApi root();

        # REST output filename
        string rest_fn;

        # trailing docs for REST API page
        *string restend;
    }

    public {
        # command-line options
        static hash<auto> opts;

        # schema output: api -> path -> method -> RestAction
        static hash<string, hash<string, hash<string, RestAction>>> smap;
    }

    constructor() {
        GetOpt g(Opts);
        opts = g.parse3(\ARGV);
        if (opts.help) {
            Filter::usage();
        }

        if (opts.debug) {
            debug = True;
        }

        getSystemServices();

        if (opts.lssvc) {
            printf("%s\n", opts.ssvc);
            return;
        }

        if (opts.dsvc) {
            map processService("../system/" + $1), opts.svc;
            return;
        }

        if (opts.rest) {
            map processRest($1), ARGV;
            finalizeRest();
            root.outputSwagger(opts.rest ?? dirname(rest_fn));
            return;
        }

        if (opts.python) {
            map processQoreToPython(opts.python, $1), ARGV;
            return;
        }

        # only automatic processing
        *string fn = shift ARGV;
        if (!fn) {
            printf("ERROR: filename required\n");
            Filter::usage();
        }

        *string ofn = shift ARGV;

        if (opts.verbose) {
            printf("fn: %y ofn: %y\n", fn, ofn);
        }

        if (fn =~ /.*qsd$/) {
            processService(fn, ofn);
        } else if (fn =~ /\.qjob$/) {
            processQore(fn, ofn);
        } else if (fn =~ /\.doxygen$/ || fn =~ /\.dox$/) {
            processDoxygen(fn, ofn);
        } else if (fn =~ /\.qm$/) {
            processQore(fn, ofn, True);
        } else if (fn =~ /system-services-mainpage.doxygen.tmpl$/) {
            processServiceIndex(fn, ofn);
        } else if (fn =~ /\.tmpl$/) {
            processLinks(fn, ofn);
        } else if ((fn =~ /\.ql$/ || fn =~ /\.qc$/) && fn !~ /QorusSystemAPI.qc$/) {
            processQore(fn, ofn);
        } else {
            process(fn, ofn);
        }
    }

    static usage() {
      printf("usage: %s [options] <file1> ...
  -d,--debug                 show debug output
  -D,--outdir=ARG            specify output directory for created files
  -l,--list-system-services  list system service file names
  -p,--python=ARG            output docs as python package ARG
  -r,--rest=ARG              process as REST API documentationm Swagger output directory
  -v,--verbose               allows for more verbose output
  -h,--help                  this help text
", get_script_name());
      exit(1);
    }

    static debug(string fmt) {
        if (debug) {
            vprintf("DEBUG: " + fmt + "\n", argv);
        }
    }

    getSystemServices() {
        # get system services
        string systemDir = replace(get_script_path(), get_script_name(), "/../system/");
        Dir d();
        d.chdir(systemDir);

        # get a list of the latest service with each name in case there happen to be old versions in the directory for some reason
        hash<auto> h;
        foreach string str in (d.listFiles("^.*\\.qsd\$")) {
            (string n, string v) = (str =~ x/([^-]+)-v([0-9\.]+)\.qsd/);
            if (h{n} && compare_version(h{n}.ver, v) > 0)
                continue;
            h{n} = {
                "fn": str,
                "ver": v,
            };
        }

        opts.ssvc = (map $1.fn, h.iterator()).join(" ");
    }

    processServiceIndex(string ifn) {
        if (!opts.ssvc)
            throw "ERROR", "--system-services not specified";

        File ifv();
        ifv.open2(ifn);

        string ofn = regex_subst(basename(ifn), ".tmpl", "");
        if (opts.outdir)
            ofn = opts.outdir + "/" + ofn;

        printf("creating service index in %y\n", ifn);

        File of();
        of.open2(ofn, O_CREAT | O_WRONLY | O_TRUNC);

        list<string> l = opts.ssvc.split(" ");

        # hash of non-deprecated services
        hash<string, string> h;
        # hash of deprecated services
        hash<string, string> dh;

        foreach string sfn in (l) {
            if (opts.tmpdir) {
                sfn = opts.tmpdir + DirSep + sfn;
            } else if (!is_readable(sfn)) {
                sfn = normalize_dir(get_script_dir() + "../system/" + sfn);
            }

            hash<auto> meta = parse_yaml(File::readTextFile(sfn + ".yaml"));
            string bfn = basename(sfn);
            if (meta.desc =~ /deprecated/i) {
                dh{bfn} = meta.desc;
            } else {
                h{bfn} = meta.desc;
            }
        }
        #printf("l: %y\n", l);exit(1);

        while (exists (*string line = ifv.readLine())) {
            if (line =~ /DEPRECATED_SERVICE_LIST/) {
                #printf("h: %Y\n", h);
                foreach string fn in (sort(dh.keys())) {
                    string sn = fn;
                    sn =~ s/-v.+//g;
                    of.printf("    - @ref system_%s \"system.%s\": %s\n", sn, sn, dh{fn});
                }
                continue;
            }

            if (line =~ /SERVICE_LIST/) {
                #printf("h: %Y\n", h);
                foreach string fn in (sort(h.keys())) {
                    string sn = fn;
                    sn =~ s/-v.+//g;
                    of.printf("    - @ref system_%s \"system.%s\": %s\n", sn, sn, h{fn});
                }
                continue;
            }

            of.print(line);
        }
    }

    processLinks(string ifn, *string ofn, *File of) {
        # service lookup hash
        hash sh;
        if (opts.ssvc) {
            foreach string svc in (split(" ", opts.ssvc)) {
                if (svc =~ /\~$/)
                    continue;
                string sn = svc =~ x/([-a-z0-9]+)-v/[0];
                sh{sn} = svc;
            }
            #printf("sh: %y\n", sh);exit(1);
        }

        File ifv();
        ifv.open2(ifn);

        if (!ofn) {
            ofn = regex_subst(ifn, ".tmpl", "");
            if (opts.outdir)
                ofn = opts.outdir + "/" + basename(ofn);
        }

        if (!of) {
            of = new File();
            of.open2(ofn, O_CREAT | O_WRONLY | O_TRUNC);
        }

        if (opts.verbose)
            printf("processing %y -> %y for API links\n", ifn, ofn);

        DocumentTableHelper dth();

        while (exists (*string line = ifv.readLine())) {
            while (line =~ /\\$/) {
                *string nl = ifv.readLine();
                if (!exists nl) {
                    throw "LINE-CONTINUATION-ERROR", sprintf("%s: line ends in '\\' at the end of input", ifn);
                }

                trim line;
                splice line, -1, 1;
                line += nl;
            }

            Filter::fixAPIRef(\line);
            line = dth.process(line);

            while (*string svc = (line =~ x/(##[-a-z]+)/[0])) {
                string orig = svc;
                splice svc, 0, 2;
                if (!exists sh{svc})
                    throw "ERROR", sprintf("unknown service: %s (%y)", svc, orig);
                line = replace(line, orig, sh{svc});
                #printf("fixed %Y -> %Y\n", orig, sh{svc});
            }

            if (exists (*string inc = line =~ x/^#include "(.*)"\s*$/[0])) {
                if (opts.outdir) {
                    inc = opts.outdir + "/" + inc;
                }
                processLinks(inc, ofn, of);
                continue;
            }

            # convert asterisks
            line =~ s/([^\/\*]?)\*([a-z])/$1__7_ $2/ig;

            # remove <!--% ... %--> comments to allow for invisible spacing, to allow for "*/" to be outout in particular places, for example
            line =~ s/<!--%.*%-->//g;

            if (line =~ /{datamodel_version}/)
                line = regex_subst(line, "{datamodel_version}", OMQ::datamodel, RE_Global);

            if (line =~ /{compat_datamodel}/)
                line = regex_subst(line, "{compat_datamodel}", OMQ::compat_datamodel, RE_Global);

            if (line =~ /{load_datamodel}/)
                line = regex_subst(line, "{load_datamodel}", OMQ::load_datamodel, RE_Global);

            if (line =~ /{qorus_version}/)
                line = regex_subst(line, "{qorus_version}", OMQ::version, RE_Global);

            if (line =~ /{qorus_build}/)
                line = regex_subst(line, "{qorus_build}", getBuild(), RE_Global);

            if (line =~ /{qore_version}/)
                line = regex_subst(line, "{qore_version}", getQoreVersion(), RE_Global);

            if (line =~ /{oracle_version}/)
                line = regex_subst(line, "{oracle_version}", MinSystemDBDriverVersion.oracle, RE_Global);

            if (line =~ /{pgsql_version}/)
                line = regex_subst(line, "{pgsql_version}", MinSystemDBDriverVersion.pgsql, RE_Global);

            if (line =~ /{mysql_version}/)
                line = regex_subst(line, "{mysql_version}", MinSystemDBDriverVersion.mysql, RE_Global);

            of.print(line);
        }
    }

    private string getBuild() {
        if (!build)
            build = trim(`git rev-parse --abbrev-ref HEAD`) + "-" + trim(`git rev-parse HEAD`);
        return build;
    }

    private string getQoreVersion() {
        if (!qorever)
            qorever = sprintf("%d.%d.%d", Qore::VersionMajor, Qore::VersionMinor, Qore::VersionSub);
        return qorever;
    }

    processService(string ifn, *string ofn) {
        FileLineIterator i(ifn);

        if (!ofn) {
            ofn = basename(ifn);
            if (opts.outdir)
                ofn = opts.outdir + "/" + ofn;
        }

        if (opts.verbose)
            printf("processing service file: %y -> %y\n", ifn, ofn);

        File of();
        of.open2(ofn, O_CREAT | O_WRONLY | O_TRUNC);

        # hash of method info keyed by name
        hash<string, hash<ServiceTagInfo>> method_hash;

        hash<auto> yaml = parse_yaml(File::readTextFile(ifn + ".yaml"));
        foreach hash<auto> m in (yaml.methods) {
            method_hash{m.name} = <ServiceTagInfo>{
                "name": m.name,
                "desc": m.desc,
            };
        }

        of.printf("//! @anchor system_%s\n", yaml.name);

        # get header information about the service
        doServiceFileHeader(i, of, basename(ofn), yaml);
        # if True then a new tag means a new method is being defined
        bool do_reset;

        # hash of method tags
        hash<ServiceTagInfo> tags();

        # class member private bracket count
        int pp;

        # method private flag
        bool mpp;

        # method private count
        int mpc = 0;

        # class bracket count
        int cbc = 0;

        # class source prefix and suffix
        string class_source_prefix;
        string class_source_suffix;

        code saveMethod = sub () {
            if (!tags) {
                do_reset = False;
                return;
            }
            if (!tags.name) {
                return;
                #throw "METHOD-ERROR", sprintf("method has no name: %y\n", tags);
            }
            if (method_hash{tags.name}) {
                throw "METHOD-ERROR", sprintf("method %y declared twice", tags.name);
            }
            #printf("saving method: %y\n", tags);
            method_hash{tags.name} = tags;

            do_reset = False;
            tags = new hash<ServiceTagInfo>();
        };

        string service_name = basename(ifn);
        service_name =~ s/-v.*//;

        bool found_service;
        string last_comment;

        while (i.next()) {
            string line = i.getValue();
            if (line =~ /\s*#!/) {
                last_comment = line;
                continue;
            }
            if (!found_service) {
                if (line =~ /inherits.*Qorus(System)?Service/) {
                    line = regex_subst(line, "class .* inherits", "class " + service_name + " : public");
                    line = last_comment + "\n" + line + "\npublic:";
                    found_service = True;
                } else {
                    continue;
                }
            }

            # process all system API references
            Filter::fixAPIRef(\line);

            if (line =~ /\/\*\*/) {
                string comment = getComment(line, i, True);
                if (!tags.comment) {
                    # remove end comment marker, as it is added on output
                    comment =~ s/\*\///;
                    tags.comment = comment;
                } else {
                    tags.source += "   " + comment;
                }
                continue;
            }

            if (line =~ /sub [a-z_0-9]+/) {
                string sn = (line =~ x/sub ([a-z_0-9]+)\(/i)[0];
                if (!exists tags.name) {
                    tags.name = sn;
                }

                if (tags.name == sn) {
                    line =~ s/sub //;
                    line =~ s/([^\/\*]?)\*([a-z])/$1__7_ $2/ig;
                    tags.source += line + "\n";
                }
                continue;
            }

            if (line =~ /#\s*END/) {
                if (!tags) {
                    throw "METHOD-ERROR", sprintf("%s: # END without a method declaration", ifn);
                }
                saveMethod();
                continue;
            }

            # non-tag line found
            if (tags && !do_reset && line !~ /\s*#\s*[a-z]+:/) {
                #printf("DO RESET: %s", line);
                do_reset = True;
            }

            if (line !~ /^\s*$/) {
                if (*list<string> x = (line =~ x/^(\s*)(public|private|private:internal)\s+{(.*)}/)) {
                    line = sprintf("%s:\n%s%s\npublic:", x[1], x[0], x[1]);
                }

                # convert comments
                line =~ s/\#/\/\//g;
                # remove regular expressions
                line =~ s/[=!]~ *\/.*\//== 1/g;
                # convert asterisks
                line =~ s/([^\/\*]?)\*([a-z])/$1__7_ $2/ig;

                # process public/private sections to convert to pseudo-c++ for doxygen
                if (line =~ /({|})/) {
                    # count how many open curly brackets
                    int ob = (line =~ x/({)/g).size();
                    # count how many close curly brackets
                    int cb = (line =~ x/(})/g).size();
                    int delta = ob - cb;
                    cbc += delta;
                    if (!cbc) {
                        if (line !~ /};/) {
                            line =~ s/}/};/;
                        }
                    } else if (cb && cbc == 1 && mpp) {
                        line += "public:";
                        mpp = False;
                    }

                    if (delta) {
                        #printf("delta: %d pp: %d: %y\n", delta, pp, line);
                        if (pp) {
                            pp += delta;
                            if (!pp) {
                                line = "public:";
                            }
                        }
                    }
                }

                if (line =~ /^\s*(public|private|private:internal)\s*{/) {
                    line =~ s/\s*{/:/;
                    line =~ s/^\s*//;
                    if (!pp) {
                        ++pp;
                    }
                }

                if (*list<string> x = (line =~ x/^(\s*)(public|private|private:internal)\s+{(.*)}/)) {
                    line = sprintf("%s:\n%s%s\npublic:", x[1], x[0], x[1]);
                }

                if (yaml && (*list<*string> l = (line =~ x/\s*([\w]+\s+)?([\w]+)(\(.*\))\s{/))) {
                    string name = l[1];
                    if (name == "_copy") {
                        name = "copy";
                    }
                    if (method_hash{name}) {
                        method_hash{name} += {
                            "source": sprintf("%s%s%s%s {}\n", l[0], name, l[2]),
                        };
                        #printf("DBG got %y: %y\n", name, method_hash{name}.source);
                        if (tags.comment) {
                            method_hash{name}.comment = tags.comment;
                        }
                        do_reset = False;
                        tags = new hash<ServiceTagInfo>();
                        continue;
                    }
                }
            }
        }

        if (tags) {
            saveMethod();
        }

        if (class_source_prefix) {
            of.print(class_source_prefix);
        }

        string padding = "    ";

        of.printf("//! system %s service\nclass %s : public %s {\npublic:\n", yaml.name, yaml."class-name", yaml."base-class-name");

        # output methods
        foreach hash<ServiceTagInfo> mh in (method_hash.iterator()) {
            if (!mh.source) {
                throw "SERVICE-ERROR", sprintf("%s: missing source for method %y", ifn, mh.name);
            }
            if ($#) {
                of.write("\n");
            }
            of.printf("%s//! @brief %s service method\n", padding, mh.name);
            if (mh.comment) {
                of.printf("%s%s\n", padding, mh.comment);
            } else {
                of.printf("%s/**\n", padding);
            }
            if (exists mh.lock && mh.lock != "none") {
                of.printf("%s   @note - \\c lock: @ref OMQ::SL%s\n", padding, mh.lock == "write" ? "Write" : "Read");
            }
            if (mh.intern) {
                of.printf("%s   @note - \\c internal: \\c True (this method can only be called internally)\n", padding);
            }
            if (mh.write) {
                of.printf("%s   @note - \\c write: \\c True (external calls require @ref OMQ::QR_CALL_SYSTEM_SERVICES_RW)\n", padding);
            }
            of.printf("%s*/\n", padding);
            of.write(padding);
            of.write(mh.source);
        }

        if (class_source_suffix) {
            of.print(class_source_suffix);
        } else {
            of.print("};\n");
        }

        #printf("MH: %N\n", method_hash);
    }

    # raw file copy
    processDoxygen(string ifn) {
        File ifv();
        ifv.open2(ifn);

        string ofn = basename(ifn);
        if (opts.outdir)
            ofn = opts.outdir + "/" + ofn;
        else {
            # it makes sense with outdir only
            return;
        }

        if (opts.verbose)
            printf("processing doxygen file %s -> %s\n", ifn, ofn);

        File of();
        of.open2(ofn, O_CREAT | O_WRONLY | O_TRUNC);

        of.write(ifv.read(-1));
    }

    string processQdx(string ifn) {
        string ofn = basename(ifn);
        if (opts.outdir)
            ofn = opts.outdir + DirSep + ofn;

        if (opts.verbose)
            printf("processing QDX %s -> %s\n", ifn, ofn);

        int rc;
        string out = backquote(sprintf("qdx -N \"%s\" \"%s\"", ifn, ofn), \rc);

        if (rc)
            throw "QDX-ERROR", out;

        return ofn;
    }

    processRest(string ifn) {
        File ifv();
        ifv.open2(ifn);

        File of();
        if (!rest_fn) {
            rest_fn = basename(ifn);
            if (opts.outdir)
                rest_fn = opts.outdir + DirSep + rest_fn;
            of.open2(rest_fn, O_CREAT | O_WRONLY | O_TRUNC);
        } else {
            of.open2(rest_fn, O_APPEND | O_WRONLY);
        }

        if (opts.verbose) {
            printf("processing REST API file %s -> %s\n", ifn, rest_fn);
        }

        # current REST API URI path info record
        RestApi current;

        # service hash for links
        hash sh;

        int line_number = 0;

        on_error rethrow $1.err, sprintf("%s:%d: %s", ifn, line_number, $1.desc);

        while (exists (*string line = ifv.readLine())) {
            ++line_number;
            if (line =~ /\/\*\* @page\s+.+$/) {
                string comment = getComment(line, ifv, NOTHING, \line_number);

                # get API version being defined
                *string ver = (comment =~ x/@page [a-z_]+_(v[0-9]+|public)/)[0];
                if (!ver) {
                    # got "master" REST API page
                    of.print(comment);
                } else {
                    root.savePage(ver, comment);
                }

                continue;
            }

            if (line =~ /\/\*\* @REST\s+.+$/) {
                string comment = getComment("", ifv, NOTHING, \line_number);
                # remove trailing comment chars from string
                comment =~ s/\*\///;

                # process service links in REST comments
                foreach string svc in (comment =~ x/(##[-a-z]+)/g) {
                    string orig = svc;
                    splice svc, 0, 2;
                    if (!sh{svc}) {
                        string targ = get_script_dir() + "/../system/" + svc + "*.qsd";
                        *list l = glob(targ);
                        if (l.size() != 1) {
                            throw "SERVICE-ERROR", sprintf("glob(%y) returned %y; cannot find service", targ, l);
                        }
                        sh{svc} = basename(l[0]);
                    }
                    comment = replace(comment, orig, sh{svc});
                    #printf("fixed %Y -> %Y\n", orig, sh{svc});
                }

                string targ = (line =~ x/@REST\s+(.+)$/)[0];

                if (targ[0] == "/") {
                    trim targ;

                    *RestApi ref;
                    # see if we're making a reference to a URI path
                    if (*string refstr = (targ =~ x/\s*\((\/.*)\)/)[0]) {
                        # make sure that refstr begins with a slash
                        if (refstr[0] != "/") {
                            refstr = "/" + refstr;
                        }
                        # remove reference from target
                        targ =~ s/\s*\(\/.*\)//;
                        if (refstr == "/") {
                            ref = root;
                        } else {
                            # find reference
                            ref = root;
                            foreach string pc in (refstr.substr(1).split("/")) {
                                *RestApi c = ref.getChild(pc);
                                if (!c) {
                                    throw "REST-API-ERROR", sprintf("cannot find reference from %y to %y (error "
                                        "component: %y; known children of parent: %y)", targ, refstr, ref.getUriPath(),
                                        keys ref.getChildren());
                                }
                                ref = c;
                            }
                        }
                    }

                    current = root;
                    foreach string pc in (targ.substr(1).split("/")) {
                        current = current.getNewChild(pc);
                    }

                    current.setDocs(comment);

                    if (ref) {
                        current.setReference(ref);
                    }
                } else {
                    if (!current) {
                        throw "REST-API-ERROR", sprintf("cannot add REST API without any URI path context: %y", line);
                    }
                    current.addAction(targ, comment);
                }

                continue;
            }

            if (line =~ /\/\*\* @RESTEND/) {
                restend = getComment("", ifv, NOTHING, \line_number);
            }
        }
    }

    finalizeRest() {
        File of();
        of.open2(rest_fn, O_APPEND | O_WRONLY);

        root.output(of);
        if (restend)
            of.printf("%s\n", restend);
    }

    process(string ifn, *string ofn) {
        File ifv();
        ifv.open2(ifn);

        if (!ofn) {
            ofn = basename(ifn);
            if (opts.outdir)
                ofn = opts.outdir + "/" + ofn;
        }

        if (opts.verbose)
            printf("processing API file %s -> %s\n", ifn, ofn);

        File of();
        of.open2(ofn, O_CREAT | O_WRONLY | O_TRUNC);

        string comment = "";
        *string api;
        while (exists (*string line = ifv.readLine())) {
            if (line =~ /#!/) {
                line =~ s/#!/\/\/!/;
                if (line =~ /@file/) {
                    of.print(line + "\n");
                    continue;
                }
                comment = getComment(line, ifv);
                continue;
            }
            if (comment && !api && (api = (line =~ x/\"(omq\.[-a-z\.\[\]]+)\"/[0]))) {
                #printf("api: %s()\n", api);
                continue;
            }
            if (comment && api && (exists ((*string rv, *string args) = (line =~ x/\"code\"[ \t]*:(.*)sub[ \t]*\(([^{]*)\)/)))) {
                trim rv;
                rv += " ";
                #printf("api: %s, rv: %s, sig: %s", api, rv, line);
                args =~ s/^hash (\$)?[a-z_]+(,( )?)?//;
                args =~ s/(^|[^\/\*])\*([a-z])/$1__7_ $2/ig;
                #args =~ s/\$/__6_/g;
                if (args =~ /\*hash/)
                    printf("args: %s\n", args);
                string orig_api = api;
                orig_api =~ s/[\.-]/_/g;
                orig_api =~ s/_\[.+//g;

                rv =~ s/([^\/\*])\*([a-z])/$1__7_ $2/ig;

                of.printf("/** @anchor %s */\n\n", orig_api);
                of.print(comment);
                Filter::fixAPI(\api);
                of.printf("%s%s(%s) {}\n\n", rv, api, args);
                comment = "";
                delete api;
            }
        }
    }

    doServiceFileHeader(FileLineIterator i, File of, string ofn, hash<auto> yaml) {
        *string comment;

        while (i.next()) {
            string line = i.getValue();

            if (!exists comment && line =~ /\/\*\*/) {
                comment = getComment(line, i);
                comment =~ s/^\/\*\*//g;
                continue;
            }
        }

        of.printf("/** @file %s\n    @brief %s\n", ofn, yaml.desc);
        if (comment) {
            of.print("\n");
            if (comment =~ /^\s*@/) {
                of.print(comment);
            } else {
                of.printf("    @details %s", comment);
            }
        } else {
            of.printf("*/");
        }

        of.print("\n");
    }

    static string fixAPI(any api) {
        api =~ s/\./__4_/g;
        api =~ s/-/__5_/g;
        api =~ s/\[/__1_/g;
        api =~ s/\]/__2_/g;
        return api;
    }

    static fixAPIRef(reference line) {
        while (exists (*string api = (line =~ x/((omq|arch|datasource|info|omqmap|prop|queue|status|sqlutil|fs|tibco|tibrv-api-gateway)\.[-a-zA-Z0-9_\.\[\]]+)\(/)[0])) {
            string na = Filter::fixAPI(api);
            line = replace(line, api + "(", na + "(");
            #printf("replace %y -> %y\n", api, na);
        }

        line =~ s/\$\.//g;
        #line =~ s/\$/__6_/g;
    }

    fixParam(reference line) {
        if (line =~ /@param/) {
            line =~ s/([^\/\*])\*([a-z])/$1__7_ $2/ig;
            #line =~ s/\$/__6_/g;
        }
        if (exists (*string str = regex_extract(line, "(" + sname + "\\.[a-z0-9_]+)", RE_Caseless)[0])) {
            string nstr = str;
            #printf("str: %y nstr: %y\n", str, nstr);
            nstr =~ s/\./__4_/g;
            line = replace(line, str, nstr);
        }
    }

    string getComment(string comment, File ifv, bool fix_param = False, *reference<int> line_number) {
        if (comment =~ /\*\/\s*$/) {
            return comment;
        }
        comment =~ s/^[ \t]+//g;
        if (fix_param)
            fixParam(\comment);

        DocumentTableHelper dth();

        while (exists (*string line = ifv.readLine(False))) {
            ++line_number;
            #line =~ s/\$/__6_/g;

            while (line =~ /\\$/) {
                *string nl = ifv.readLine();
                if (!exists nl) {
                    throw "LINE-CONTINUATION-ERROR", sprintf("%s: line ends in '\\' at the end of input",
                        ifv.getFileName());
                }
                ++line_number;

                trim nl;
                splice line, -1;
                line += nl;
            }
            line += "\n";

            if (fix_param) {
                fixParam(\line);
            }

            Filter::fixAPIRef(\line);
            line = dth.process(line);

            if (line =~ /\*\//) {
                comment += line;
                break;
            }
            comment += line;
        }
        #printf("comment: %s", comment);
        return comment;
    }

    *bool skipModule(AbstractLineIterator ins, reference<string> line) {
        int bc = 0;
        while (True) {
            # count how many open curly brackets
            int ob = (line =~ x/({)/g).size();
            # count how many close curly brackets
            int cb = (line =~ x/(})/g).size();
            if (ob || cb) {
                int delta = ob - cb;
                bc += delta;
                if (!bc) {
                    break;
                }
            }
            if (!ins.next()) {
                return True;
            }
            line = ins.getValue();
        }
    }

    string getComment(string comment, AbstractLineIterator ins, bool fix_param = False) {
        if (comment =~ /\*\/\s*$/) {
            return comment;
        }
        comment += "\n";
        comment =~ s/^[ \t]+//g;
        if (fix_param)
            fixParam(\comment);

        DocumentTableHelper dth();

        while (ins.next()) {
            string line = ins.getValue();
            while (line =~ /\\$/) {
                if (!ins.next()) {
                    throw "LINE-CONTINUATION-ERROR", "line ends in '\\' at the end of input";
                }

                splice line, -1;
                line += trim(ins.getValue());
            }
            if (fix_param)
                fixParam(\line);

            Filter::fixAPIRef(\line);
            line = dth.process(line);

            comment += line + "\n";
            if (line =~ /\*\//) {
                break;
            }
        }

        return comment;
    }

    processQoreToPython(string pkg, string ifn) {
        if (True) { throw "ERROR", sprintf("qore -> python not yet implemented"); }

        FileInputStream fis(ifn);
        InputStreamLineIterator i(new StreamReader(fis));

        File of();
        string fn = basename(pkg + ".py");
        if (opts.outdir) {
            fn = opts.outdir + DirSep + fn;
        }
        of.open2(fn, O_CREAT | O_WRONLY | O_TRUNC);

        if (opts.verbose) {
            printf("processing Python API doc file %s -> %s\n", ifn, fn);
        }

        # output package info
        of.printf("## @package %s\n", pkg);

        # comment buffer
        string comment;

        while (i.next()) {
            string line = i.getValue();

            # skip empty lines
            if (line =~ /^\s*$/) {
                remove comment;
                of.write("\n");
                continue;
            }

            # skip parse commands
            if (line =~ /^%/)
                continue;

            if (*string page = (line =~ x/@mainpage (\w.*)/)[0]) {
                string link = page.lwr();
                link =~ s/\s+/_/g;
                line = regex_subst(line, "@mainpage \w.*", "@page " + link + " " + page);
                continue;
            }

            if (line =~ /\s*#!/) {
                line =~ s/#!/##/;
                comment += line + "\n";
                continue;
            }

            if (line =~ /\/\*/) {
                comment = getComment(line, i);
                comment =~ s/\/\*+(.*)\*+\//$1/ms;
                comment = (map "##" + $1, comment.split("\n")).join("\n");
                continue;
            }

            remove comment;
        }
    }

    processQore(string fn, *string nn, *bool do_mainpage) {
        FileInputStream inf(fn);
        # need to use an unbuffered StreamReader here
        InputStreamLineIterator ins(new StreamReader(inf));

        fn = basename(fn);
        int i = rindex(fn, ".");
        if (i == -1) {
            stderr.printf("%s: no extension; skipping\n", fn);
            return;
        }

        if (!nn) {
            nn = fn;
            if (opts.outdir)
                nn = opts.outdir + "/" + nn;
        }

        if (opts.verbose)
            printf("processing Qore source code file %s -> %s\n", fn, nn);

        FileWrapper of();
        of.open2(nn, O_CREAT|O_WRONLY|O_TRUNC);

        *string class_name;
        *string ns_name;

        # class member private / public block curly bracket count (if > 0 = in block)
        int pp;

        # method private count
        int mpc = 0;

        # class bracket count
        int cbc = 0;

        # namespace bracket count
        int nbc = 0;

        bool in_doc = False;

        # hashdecl flag
        bool hashdecl_flag;

        while (ins.next()) {
            string line = ins.getValue();
            # skip empty lines
            if (line =~ /^\s*$/) {
                of.write("\n");
                continue;
            }

            # skip parse commands
            if (line =~ /^%/) {
                continue;
            }

            if (do_mainpage && (*string page = (line =~ x/@mainpage (\w.*)/)[0])) {
                string link = page.lwr();
                link =~ s/\s+/_/g;
                line = regex_subst(line, "@mainpage \\w.*", "@page " + link + " " + page);
                of.print(line + "\n");
                continue;
            }

            # skip module declarations for now
            if (line =~ /^[[:space:]]*module[[:space:]]+/) {
                if (skipModule(ins, \line)) {
                    break;
                }
                continue;
            }

            line =~ s/\$\.//g;
            line =~ s/([^\/\*])\*([a-z])/$1__7_ $2/ig;
            #line =~ s/\$/__6_/g;

            Filter::fixAPIRef(\line);

            if (line =~ /\/\*\*/) {
                string comment = getComment(line, ins);
                of.print(comment);
                continue;
            }

            line =~ s/\$\.//g;
            #line =~ s/\$//g;
            line =~ s/\#/\/\//;

            if (line =~ /^[ \t]*\/\//) {
                of.print(line + "\n");
                continue;
            }

            line =~ s/our /extern /g;
            line =~ s/my //g;
            line =~ s/sub //;

            # convert hashdecl -> struct
            if (line =~ /[^a-zA-Z0-9_]hashdecl /) {
                line =~ s/([^a-zA-Z0-9_])hashdecl /$1struct /g;
                hashdecl_flag = True;
            }

            # see if we have a function or method declaration that spans multiple lines
            if (line =~ /\w+\s?(\(|\))/) {
                # copy of line to check it without parens in quotes
                string line_copy = line;
                line_copy =~ s/"(?:[^"\\]|\\.)*"/""/g;
                # count how many open parens
                int ob = (line_copy =~ x/(\()/g).size();
                # count how many close parens
                int cb = (line_copy =~ x/(\))/g).size();
                int tot = (ob - cb);
                if (tot > 0) {
                    # read until we have an open bracket
                    while (ins.next()) {
                        string new_line = ins.getValue();
                        # skip lines with parse commands
                        if (new_line =~ /^%/) {
                            continue;
                        }
                        line =~ s/\s+$//;
                        new_line =~ s/\s+$//;
                        line += " " + new_line;
                        #printf("FOUND COMPLEX LINE: %s\n", line);
                        if ((new_line =~ /{\s*(#.*)?$/) || (new_line =~ /\);\s*(#.*)?$/)) {
                            break;
                        }
                    }
                }
            }

            # see if the line is the start of a method or function declaration
            if (regex(line, '\(.*\)[[:blank:]]*{[[:blank:]]*(#.*)?$')
                && line !~ /const .*=/
                && line !~ /extern .*=.*\(.*\)/
                && !regex(line, '^[[:blank:]]*\"')) {
                #if (line =~ /writeOutputData/) { printf("GOT IT: %s\n", line);}
                # printf("method or func: %s", line);

                # remove "$" signs
                line =~ s/\$//g;

                # remove any trailing line comment
                line =~ s/#.*$//;

                # make into a declaration (also remove any parent class constructor calls)
                line =~ s/[[:blank:]]*(?:([^:A-za-z]):[^:].*\(.*)?{[[:blank:]]*$/$1;/;
                #line = regex_subst(line, '[[:blank:]]*(?:([^:]):[^:].*\(.*)?{[[:blank:]]*$', "$1;");

                # modify string default value quoted by quotes to apostrophes
                #line = adjustQuotedStrings(line);

                # read until closing curly bracket '}'
                readUntilCloseBracket(inf);

                list<string> mods = ();
                if (line !~ /"/) {
                    (*string ignore, *string mod_str, *string rest) = (line =~ x/(.*)(synchronized|private(?::internal|:hierarchy)?|public|static)(\s+.*)/);
                    if (mod_str) {
                       # printf("mod_str: %y\n", mod_str);
                        while (exists (*list l = (mod_str =~ x/(synchronized|private(?::internal|:hierarchy)?|public|static)/))) {
                            mods += l[0];
                            mod_str = replace(mod_str, l[0], "");
                        }
                        rest =~ s/^\s*//;
                        line = ignore + rest + "\n";
                    }
                }

                bool this_priv;
                if (mods) {
                    trim mods;
                    #printf("mods: %y line: %y\n",mods, line);
                    foreach string mod in (mods) {
                        if (mod == "private" || mod == "private:hierarchy") {
                            this_priv = True;
                            of.write("protected:\n");
                        } else if (mod == "private:internal") {
                            this_priv = True;
                            of.write("private:\n");
                        }
                        #line = regex_subst(line, mod, "");
                    }
                    #mods = select mods, $1 != "private" && $1 != "public";
                    #line = join(" ", mods) + line;

                    mods = select mods, $1 !~ /^private/ && $1 != "public";
                    if (mods) {
                        (*string ws, *string rest) = (line =~ x/^(\s*)(.*)$/);
                        line = ws + join(" ", mods) + " " + rest + "\n";
                    }
                }

                of.write(line + "\n");
                if (this_priv) {
                    of.write("public:\n");
                }
                continue;
            }

            # remove regular expressions
            line =~ s/[=!]~ *\/.*\//== 1/g;

            auto x;

            # convert class inheritance lists to c++-style declarations
            processInheritance(\line, ins);

            if (!class_name) {
                x = (line =~ x/^\s*(public\s+)?namespace\s+(\w+(::\w+)?)/)[1];
                if (x) {
                    #printf("namespace %y\n", x);
                    line =~ s/public\s+//;
                    ns_name = x;

                    /*
                    if (nbc != 0)
                        throw "ERROR", sprintf("namespace found but nbc: %d\nline: %y\n", nbc, line);
                    */

                    if (line =~ /{/ && line !~ /}/)
                        ++nbc;

                    of.print(line + "\n");
                    continue;
                }

                x = (line =~ x/^\s*(?:(?:public|final)\s+)?class\s+(\w+(::\w+)*)/)[0];
                if (x) {
                    line =~ s/public\s+//;
                    #printf("class %y\n", x);
                    class_name = x;

                    if (cbc != 0) {
                        throw "ERROR", sprintf("class found but cbc: %d\nline: %y\n", cbc, line);
                    }

                    # count how many open curly brackets
                    int ob = (line =~ x/({)/g).size();
                    # count how many close curly brackets
                    int cb = (line =~ x/(})/g).size();
                    int delta = ob - cb;
                    if (delta > 0) {
                        line += "\npublic:\n";
                        cbc += delta;
                    } else if (delta < 0) {
                        throw "ERROR", sprintf("class found with too many close curly brackets; line: %y\n", line);
                    }

                    of.print(line);
                    continue;
                } else if (hashdecl_flag) {
                    if (regex(line, "}") ) {
                        line = regex_subst(line, "}", "};");
                        remove hashdecl_flag;
                    }
                } else if (exists ns_name) {
                    if (line =~ /{/) {
                        if (line !~ /}/)
                            ++nbc;
                    } else if (line =~ /}/) {
                        --nbc;
                        if (!nbc) {
                            trim line;
                            line =~ s/}/};/;
                            delete ns_name;
                        }
                    }
                }
            } else {
                if (line =~ /({|})/) {
                    # count how many open curly brackets
                    int ob = (line =~ x/({)/g).size();
                    # count how many close curly brackets
                    int cb = (line =~ x/(})/g).size();
                    cbc += (ob - cb);
                    if (!cbc) {
                        trim line;
                        line =~ s/}/};/;
                        delete class_name;
                    }
                }

                if (x = (line =~ x/^(\s*)(public|private(?::internal|:hierarchy)?)\s+{(.*)}/)) {
                    switch (x[1]) {
                        case "private":
                        case "private:hierarchy":
                            x[1] = "protected";
                            break;
                        case "private:internal":
                            x[1] = "private";
                            break;
                    }
                    if (x[1] != "public") {
                        of.printf("%s:\n", x[1]);
                    }
                    of.printf("%s%s\n", x[0], x[2]);
                    if (x[1] != "public") {
                        of.printf("public:\n");
                    }
                    continue;
                }

                if (line =~ /^\s*(public|private(?::internal|:hierarchy)?)\s*{/) {
                    line =~ s/\s*{/:/;
                    line =~ s/^\s*//;
                    if (line =~ /private:hierarchy/) {
                        line = replace(line, "private:hierarchy", "protected");
                    } else if (line =~ /private:internal/) {
                        line = replace(line, "private:internal", "private");
                    } else if (line =~ /private/) {
                        line = replace(line, "private", "protected");
                    }
                    #printf("c PP line: %s\n", line);
                    ++pp;
                } else if (pp) {
                    # count how many open curly brackets
                    int ob = (line =~ x/({)/g).size();
                    # count how many close curly brackets
                    int cb = (line =~ x/(})/g).size();
                    int count = (ob - cb);
                    pp += count;
                    if (!pp) {
                        line = "public:\n";
                        #printf("line %d set pp FALSE\n", ins.index());
                    } else if (pp < 0) {
                        throw "ERROR", sprintf("confusing close brackets in class member block: %y", line);
                    }
                }
            }

            of.print(line + "\n");
        }
    }

    private bool processInheritance(reference<string> line, InputStreamLineIterator ins) {
        if (line =~ /inherits / && line !~ /\/(\/|\*)/) {
            # read until end of inheritance list
            while (True) {
                if (line =~ /({|;)\s*$/) {
                    break;
                }
                if (!ins.next()) {
                    throw "INHERITANCE-ERROR", sprintf("cannot find end of inheritance list: %y", line);
                }
                line += ins.getValue();
            }

            # get indentation for line
            *string ws = (line =~ x/^([[:blank:]]+)/)[0];
            trim line;
            *list<string> x = (line =~ x/(.*) inherits ([^{]+)(.*)/);
            x[1] = split(",",x[1]);
            foreach string e in (\x[1]) {
                trim e;
                if (e !~ /(private|public)/) {
                    e = "public " + e;
                }
            }
            trim x[0];

            line = ws + x[0] + " : " + join(", ", x[1]) + " " + x[2] + "\n";
            if (line =~ /;[ \t]*$/) {
                line =~ s/;[ \t]*$/ {};/;
            }
            return True;
        }
        return False;
    }

    # return number of lines processed
    private int readUntilCloseBracket(FileInputStream inf) {
        int cnt = 1;
        int line_cnt = 0;
        string quote;
        bool need = True;
        int regex = 0;

        StreamReader sr(inf);
        *string fc = sr.readString(1);
        if (!exists fc) {
            return line_cnt;
        }

        string c = fc;
        need = False;

        while (True) {
            if (need) {
                c = sr.readString(1);
            }
            else {
                need = True;
            }

            if (c == "\n") {
                line_cnt++;
            }

            if (regex) {
                if (c == "\\")
                    sr.readString(1);
                if (c == "/") {
                    --regex;
                }
                continue;
            }

            if (c == "'" || c == '"') {
                if (quote.val()) {
                    if (c == quote) {
                        delete quote;
                    }
                }
                else {
                    quote = c;
                }
                continue;
            }
            if (quote.val()) {
                if (c == "\\" && quote != "'")
                    sr.readString(1);
                continue;
            }
            if (c == "!" || c == "=") {
                c = sr.readString(1);
                if (c == "~") {
                    regex = 1;
                    while (True) {
                        c = sr.readString(1);
                        if (c == "s") {
                            ++regex;
                        } else if (c == "/") {
                            break;
                        }
                    }
                }
                continue;
            }

            if (c == "{") {
                ++cnt;
            } else if (c == "}") {
                if (!--cnt) {
                    return line_cnt;
                }
            } else if (c == "$") {#"){
                c = sr.readString(1);
                if (c != "#") {
                    need = False;
                }
            } else if (c == "#") {
                # read until EOL
                sr.readLine();
            } else if (c == "/") {
                c = sr.readString(1);
                if (c == "*") {
                    # read until close block comment
                    bool star = False;
                    while (True) {
                        c = sr.readString(1);
                        if (star) {
                            if (c == "/") {
                                break;
                            }
                            star = (c == "*");
                            continue;
                        }
                        if (c == "*") {
                            star = True;
                        }
                    }
                } else {
                    need = False;
                }
            }
        }
        return line_cnt;
    }
}

class FileWrapper inherits File {
    private {
        bool last_empty;
    }

    write(string line) {
        print(line);
    }

    print(string line) {
        if (line == "\n") {
            if (last_empty) {
                return;
            }
            last_empty = True;
        } else if (last_empty) {
            last_empty = False;
        }
        File::write(line);
    }
}