# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

#! @file misc.ql defines functions used in the client library

# this file is automatically included by the Qorus client library and should not be included directly by Qorus client programs

%new-style
%require-types
%push-parse-options

%requires reflection

namespace Temp {
    auto sub to_delete_sql_value(string driver, auto v) {
        switch (v.typeCode()) {
            case NT_STRING:
                return sprintf("'%s'", to_delete_fix_quotes(v));
            case NT_DATE:
                return to_delete_db_date(driver, v);
            case NT_BOOLEAN:
                return int(v);
        }
        if (!exists v || v === NULL)
            return "NULL";

        return v;
    }

    string sub to_delete_fix_quotes(string str) {
        int p;

        while ((int i = index(str, "'", p)) != -1) {
            splice str, i, 0, "'";
            p = i + 2;
        }
        return str;
    }

    string sub to_delete_fix_quotes(reference str) {
        return str = to_delete_fix_quotes(string(str));
    }

    auto sub to_delete_get_sql_number(auto v) {
        return inlist_hard(v.typeCode(), (NT_INT, NT_FLOAT, NT_BOOLEAN, NT_STRING)) ? v : "NULL";
    }

    string sub to_delete_get_sql_string(auto v, int size = 0) {
        int t = v.typeCode();
        if (t == NT_INT || t == NT_FLOAT
            || t == NT_BOOLEAN || t == NT_STRING)
            if (size)
            return "'" + to_delete_fix_quotes(substr(v, 0, size)) + "'";
        else
            return "'" + to_delete_fix_quotes(v) + "'";
        return "NULL";
    }

    string sub to_delete_db_date(string driver, date date) {
        return driver == "oracle"
            ? to_delete_oracle_date(date)
            : date.format("'YYYY-MM-DD HH:mm:SS.ms'");
    }

    string sub to_delete_oracle_date(date date) {
        return "to_date('" + date.format("YYYYMMDDHHmmSS") + "', 'YYYYMMDDHH24MISS')";
    }
}

namespace Priv {
    # constants for parsing
    const ET_RawString = 0;
    const ET_QuotedString = 1;
    const ET_Eq = 2;
    const ET_Comma = 3;
    const ET_OpenParen = 4;
    const ET_CloseParen = 5;
    const EtMap = (
        ET_RawString: "raw string",
        ET_QuotedString: "quoted string",
        ET_Eq: "=",
        ET_Comma: ",",
        ET_OpenParen: "(",
        ET_CloseParen: ")",
    );

    #! Old qorus loging levels to currenct logger level
    const OLD_QORUS_LEVEL_TO_LEVEL = {
        LL_CRITICAL:    Logger::LoggerLevel::FATAL,
        LL_IMPORTANT:   Logger::LoggerLevel::INFO,
        LL_INFO:        Logger::LoggerLevel::INFO,
        LL_DETAIL_1:    Logger::LoggerLevel::INFO,
        LL_DETAIL_2:    Logger::LoggerLevel::INFO,
        LL_DEBUG_1:     Logger::LoggerLevel::DEBUG,
        LL_DEBUG_2:     Logger::LoggerLevel::DEBUG,
        LL_DEBUG_3:     Logger::LoggerLevel::DEBUG,
    };

    int sub convert_old_log_level(int old_lvl) {
        return OLD_QORUS_LEVEL_TO_LEVEL{old_lvl} ?? LoggerLevel::TRACE;
    }

    class DefineStack {
        public {}

        private {
            string fname;
            *hash<auto> defines;
            list<auto> ds = ();
        }

        constructor(string fname, *hash<auto> defines) {
            self.fname = fname;
            self.defines = defines;
        }

        destructor() {
            if (ds)
                throw "CONNECTION-ERROR", sprintf("%s: define block %y not closed with an %%endif", fname, ds.last().define);
        }

        doElse(int line) {
            if (!ds)
                throw "CONNECTION-ERROR", sprintf("%s:%d: \"%%else\" used without a corresponding %%ifdef or %%ifndef", fname, line);

            hash<auto> dh = ds.last();

            if (dh.block)
                throw "CONNECTION-ERROR", sprintf("%s:%d: \"%%else\" used without an %%endif in %y define", fname, line, dh.define);

            ds[ds.size() - 1] += (
                "block": 1,
                "active": !dh.active,
            );
        }

        doIfdef(int line, string def) {
            #printf("%s:%d ifdef %y: %y\n", fname, line, def, exists defines{def});
            hash<auto> dfh = {
                "define": def,
                "block": 0,
                "active": exists defines{def},
                #"parent_active": ds ? ds.last().active : True,
            };
            ds += dfh;
        }

        doIfndef(int line, string def) {
            #printf("%s:%d ifndef %y: %y\n", fname, line, def, exists defines{def});
            hash<auto> dfh = {
                "define": def,
                "block": 0,
                "active": !(exists defines{def}),
                #"parent_active": ds ? ds.last().active : True,
            };
            ds += dfh;
        }

        doEndif(int line) {
            if (!ds)
                throw "CONNECTION-ERROR", sprintf("%s:%d \"%%endif\" used without a corresponding %%ifdef or %%ifndef", fname, line);
            #printf("%s:%d endif %y: %y\n", fname, line, ds.last().define, ds.size() <= 1 || ds[ds.size() - 2].active);
            pop ds;
        }

        bool active() {
            return !ds || ds.last().active;
        }
    }

    # helper function to create a URL
    string sub get_url_from_option(string prot, softstring opt, *string username, *string password,
            *string hostname) {
        # remove any options from "opt"
        opt =~ s/{.*}//;
        prot += "://";
        if (username && password) {
            prot += sprintf("%s:%s@", username, password);
        }

        if (!exists hostname) {
            hostname = "localhost";
        }

        if (opt =~ /:/) {
            # convert "0.0.0.0", "::", and "[::]" to "localhost"
            opt = regex_subst(opt, "^(0.0.0.0|::|\\[::\\]):", hostname + ":");
            return sprintf("%s%s", prot, opt);
        }
        if (opt =~ /^\//) {
            return sprintf("%ssocket=%s", prot, encode_url(opt, True));
        }
        return sprintf("%s%s:%d", prot, hostname, opt);
    }

    # connection scanner
    list<auto> sub scan_conn_exp(string fname, *hash<auto> defines, string arg, int line = 1) {
        #printf("DBG se: %y\n", arg);

        list<auto> l = ();

        # active quote character
        *string quote;

        # active comment
        bool comment = False;

        int len = arg.length();

        # scanner start line
        int start_line = line;

        # define stack
        DefineStack ds(fname, defines);

        # character position in input
        int i = 0;

        # check for parse commands related to defines
        code checkdef = sub () {
            if (arg[i + 1] != '%')
                return;
            string str = arg.substr(i + 1, 100);
            if (str =~ /^%else\s*/) { #/){
                ds.doElse(line);
                i += 5;
            } else if (str =~ /^%ifdef\s+\w+/) {
                (string blnk, string def) = (str =~ x/^%ifdef(\s+)(\w+)/);
                ds.doIfdef(line, def);
                i += blnk.size() + def.size() + 6;
            } else if (str =~ /^%ifndef\s+\w+/) {
                (string blnk, string def) = (str =~ x/^%ifndef(\s+)(\w+)/);
                ds.doIfndef(line, def);
                i += blnk.size() + def.size() + 7;
            } else if (str =~ /^%endif\s*/) { #/){
                ds.doEndif(line);
                i += 6;
            }
        };

        code add = sub (int type, *string val) {
            #printf("active, adding %y: %y\n", EtMap{type}, val);
            l += ("type": type, "val": val, "start_line": start_line, "end_line": line);
            start_line = line;
        };

        string str;

        # we only recognize quotes and parens if we are not in a raw string with alphabetic characters
        # for backwards compatibility
        code quote_paren_ok = bool sub () {
            #printf("i %d arg: %y: %y\n", i, arg.substr(i + 1, 10), (arg.substr(i + 1) =~ /^\s*(#.*)?\n/));
            if (!l)
                return False;
            if (str.empty() || str =~ /^(\s|[0-9])+$/ || str =~ /\n\s*$/ || i == (len - 1))
                return True;
            *string ss = arg.substr(i + 1);
            if (ss =~ /^\s*(#.*)?(\n|$)/)
                return True;
            return False;
        };

        for (; i < len; ++i) {
            string c = arg[i];
            if (comment) {
                if (c == "\n") {
                    comment = False;
                    ++line;
                    checkdef();
                }
                continue;
            }
            if (c == "\n") {
                ++line;
                if (!quote) {
                    checkdef();
                }
            } else if (!ds.active())
                continue;
            else if (c == "\r")  # ignore CR chars
                continue;
            else if (c == ",") {
                if (!quote) {
                    #printf("DBG: got comma i:%d\n", i);
                    trim str;
                    if (str.val()) {
                        add(ET_RawString, str);
                        str = "";
                    }
                    add(ET_Comma);
                    continue;
                }
            } else if (c == "=") {
                if (!quote) {
                    trim str;
                    if (str.val()) {
                        add(ET_RawString, str);
                        str = "";
                    }
                    add(ET_Eq);
                    continue;
                }
            } else if (c == '"') {
                if (quote) {
                    if (c == quote) {
                        delete quote;
                        add(ET_QuotedString, str);
                        str = "";
                        continue;
                    }
                } else if (quote_paren_ok()) {
                    quote = c;
                    trim str;
                    if (str.val()) {
                        add(ET_RawString, str);
                        str = "";
                    }
                    continue;
                }
            } else if (quote) {
                # only process the backslash if not parsing a bracket expression
                # because these strings are parsed a second time later
                if (c == "\\") {
                    switch (arg[++i]) {
                        case "n": str += "\n"; break;
                        case "r": str += "\r"; break;
                        case "t": str += "\t"; break;
                        case "\$": str += "\\\$"; break;
                        default: str += arg[i]; break;
                    }
                    continue;
                }
            } else {
                if (c == "#") {
                    if (!comment)
                        comment = True;
                } else {
                    if (c == "(" && quote_paren_ok()) {
                        trim str;
                        if (str.val()) {
                            add(ET_RawString, str);
                            str = "";
                        }
                        add(ET_OpenParen);
                        continue;
                    } else if (c == ")" && quote_paren_ok()) {
                        trim str;
                        if (str.val()) {
                            add(ET_RawString, str);
                            str = "";
                        }
                        add(ET_CloseParen);
                        continue;
                    }
                }
            }
            if (!comment)
                str += c;
        }

        trim str;
        if (str.val())
            add(ET_RawString, str);

        return l;
    }

    string sub replace_env_quoted(string str) {
        #printf("replace_env_quoted() str: %y\n", str);
        int start = 0;
        while (True) {
            start = str.find("\$", start);
            if (start == -1)
                break;
            # skip it if the $ is escaped
            if (start > 0 && str[start - 1] == "\\") {
                # replace backquote char
                splice str, start - 1, 1;
                continue;
            }
            string var;
            # find the end of the env var
            int end = start + 1;
            bool bracket = str[end] == "{";
            if (bracket)
                ++end;

            # find the end of the word
            while (True) {
                if (str[end] !~ /[[:word:]]/)
                    break;
                ++end;
            }

            # process end of env var word
            if (bracket) {
                if (str[end] == "}" && (end - start) > 2) {
                    var = str.substr(start + 2, end - start - 2);
                    ++end;
                } else {
                    # skip it: empty string or missing closing bracket
                    start = end;
                    continue;
                }
            } else {
                if ((end - start) > 1) {
                    var = str.substr(start + 1, end - start - 1);
                } else {
                    # skip it: empty string
                    start = end;
                    continue;
                }
            }

            string val = ENV{var} ?? "";
            #printf("GOT VAR: %y = %y (%d) (bracket: %y start: %d end: %d)\n", var, val, val.size(), bracket, start, end);

            # replace value in string
            splice str, start, (end - start), val;
            # start looking at next position
            start += val.size();
            #printf("new val: %y new start: %d\n", str, start);
        }
        return str;
    }
}

public namespace OMQ {
    #! this class is used to parse the connection files in the server and client
    public class AbstractConnectionFileHelper {
        public {
            #! default description for connections with no \c "desc" key
            const DefaultDescription = "<no description provided>";
        }

        private {
            hash<auto> data;
            *hash<auto> defines;
        }

        #! creates the object and sets the log code reference/closure
        constructor(*hash<auto> n_defines) {
            defines = n_defines;
        }

        #! parses the given file
        parse(string fname, *bool no_path) {
            delete data;

            parseImpl(fname, no_path);
        }

        #! returns the type of connection being managed
        abstract string getType();

        #! log method
        abstract log(string conn, string fmt);

        #! parses the given file
        private abstract parseImpl(string fname, *bool no_path);

        #! checks the values and types of keys and optionally does transformations
        private abstract checkKeyValues(string fname, string n, reference h);

        #! parses a connection configuration file
        /** warnings (ex: unknown option key) are logged through the log code reference/closure
            @param fname the file name to parse
            @param no_path if @ref True "True", then URI paths are not allowed in the connection URL

            @throw CONNECTION-ERROR Missing config file or malformed syntax
            @throw FILE-OPEN2-ERROR error opening configuration file
        */
        private hash<auto> parseIntern(string fname, *bool no_path) {
            hash<auto> dh = {};

            list<auto> l = scan_conn_exp(fname, defines, ReadOnlyFile::readTextFile(fname));

            #printf("scan l: %y\n", (map EtMap{$1.type}, l));
            #printf("scan: %N\n", l);

            code check = sub (hash<auto> h, list<auto> args) {
                int m = 0;
                #printf("checking %y (%y) for %y\n", EtMap{h.type}, h.val, (map EtMap.$1, args));
                map ++m, args, h.type == $1;
                if (!m)
                    throw "CONNECTION-PARSE-ERROR", sprintf("%s:%d expecting token %s; got %y instead", fname,
                        h.start_line, (foldl $1 + " or " + $2, (map "\"" + EtMap{$1} + "\"", args)), EtMap{h.type});
            };

            for (int i = 0; i < l.size();) {
                hash<auto> h = l[i];
                #printf("h: %y\n", h);
                check(h, (ET_RawString, ET_QuotedString));

                # set connection name
                string cname = h.val;

                # increment scan position and check type
                code inc = sub () {
                    if (++i == l.size())
                        throw "CONNECTION-PARSE-ERROR", sprintf("%s:%d premature end of file found while parsing "
                            "connection %y", fname, h.end_line, cname);
                    h = l[i];
                    if (argv)
                        check(h, argv);
                };

                # get equals sign
                inc(ET_Eq);

                # get value
                inc(ET_OpenParen);

                ++i;

                #printf("connection %y: %s\n", cname, h.val);

                # attribute hash
                hash<auto> ah;

                *bool ok;

                for (; i < l.size(); ++i) {
                    h = l[i];
                    check(h, (ET_RawString, ET_QuotedString));

                    # set attribute name
                    string aname = h.val;

                    # get equals char
                    inc(ET_Eq);

                    # get attribute string definition
                    inc(ET_RawString, ET_QuotedString);

                    # process quoted string with environment variable substitution
                    if (h.type == ET_QuotedString)
                        h.val = replace_env_quoted(h.val);
                    else {
                        # process raw string with environment variable substitution
                        if (h.val.find("\$") != -1) {
                            map h.val = replace(h.val, "\$" + $1, ENV.$1 ?? ""), (h.val =~ x/\$(\w+)/g);
                            map h.val = replace(h.val, "\${" + $1 + "}", ENV.$1 ?? ""), (h.val =~ x/\${(\w+)}/g);
                        }
                    }

                    # set attribute definition
                    ah{aname} = h.val;

                    # require either a comma or a close paren
                    inc(ET_Comma, ET_CloseParen);

                    # check for end of declaration
                    if (l[i].type == ET_CloseParen) {
                        ok = True;
                        ++i;
                        break;
                    } else if (l[i].type == ET_Comma && l[i + 1].type == ET_CloseParen) {
                        ok = True;
                        i += 2;
                        break;
                    }
                }

                if (!ok)
                    throw "CONNECTION-PARSE-ERROR", sprintf("%s:%d premature end of file found; missing closing parenthesis (\")\") in declaration of connection %y", fname, l.last().end_line, cname);

                if (!ah.url)
                    throw "CONNECTION-ERROR", sprintf("%s file %y connection %y is missing the 'url' option; please correct the file and try again", getType(), fname, cname);

                if (cname =~ /[^[:alnum:]-_]/u) {
                    throw "QORUS-REMOTE-ERROR",
                          sprintf("invalid characters in name %y; allowed name format: [A-Za-z0-9-_]*", cname);
                }

                # check for valid keys and issue a warning for invalid keys
                checkKeyValues(fname, cname, \ah);

                # create Connection definition
                dh{cname} = ah - ("urlh", );
            }

            return dh;
        }

        private static int getConnectionEnd(string content, int i) {
            int c;
            int nest = 1;
            while (True) {
                c = index(content, ')', i);
                if (c == -1)
                    break;
                # see if there are any open parens in this string
                string cstr = content.substr(i, c - i + 1);
                *list<auto> l = (cstr =~ x/(\()/g);
                nest += l.size() - 1;
                if (!nest)
                    break;
                i = c + 1;
            }
            return c;
        }

        #! returns the number of connections defined
        int connectionCount() {
            return data.size();
        }

        #! returns available connections as a list
        list<auto> list() {
            return data.keys();
        }

        #! returns a hash of connection info for the given connection or throws an exception if the connection does not exist
        /**
            @throw CONNECTION-ERROR the given remote connection is not defined
        */
        hash<auto> getInfo(string conn, bool with_password) {
            return getInfo(conn, {
                "with_passwords": with_password,
            });
        }

        #! returns a hash of connection info for the given connection or throws an exception if the connection does not exist
        /**
            @throw CONNECTION-ERROR the given remote connection is not defined
        */
        hash<auto> getInfo(string conn, *hash<auto> opts) {
            if (!data{conn}) {
                throw "CONNECTION-ERROR", sprintf("%s connection %y is not defined (known connections: %y)",
                    getType(), conn, keys data);
            }
            if (opts.with_password) {
                opts.with_passwords = remove opts.with_password;
            }
            return data{conn}.getInfo(opts);
        }

        #! returns a hash of connection info keyed by connection name or @ref nothing if no connections exist
        /**
        */
        *hash<auto> getInfo(bool with_password = False) {
            return getInfo({
                "with_passwords": with_password,
            });
        }

        #! returns a hash of connection info keyed by connection name or @ref nothing if no connections exist
        /**
        */
        *hash<auto> getInfo(*hash<auto> opts) {
            return map {
                $1.key: $1.value.getInfo(opts)
            }, data.pairIterator();
        }

        #! the default logging action is to print out the log message to stderr
        private static logDefault(string msg) {
            stderr.vprintf(msg + "\n", argv);
            stderr.sync();
        }
    }

    public namespace Internal {
        public auto sub vmap_value(hash<auto> vh, reference value) {
            int t = value.typeCode();
            switch (vh.valuetype) {
                case "int": return serialize_qorus_data(value = int(value));
                case "float": return serialize_qorus_data(value = float(value));
                case "date": return serialize_qorus_data(t == NT_DATE ? value : (value = date(string(value), vh.dateformat)));
                case "string": return serialize_qorus_data(value = string(value));
                case "raw": return value;
            }
            throw "INVALID-VALUEMAP-TYPE", sprintf("don't know how to handle value map data type %y", vh.valuetype);
        }
    }

    public namespace UserApi {
        #! @defgroup dd_opts Datasource Description Options
        /** The following options can be combined with binary or and used in calls to get_ds_desc()
        */
        #/@{
        #! includes the password in the return value
        public const DD_WITH_PASSWORD = 1 << 0;

        #! does not include character encoding and options in the return value
        public const DD_SHORT = 1 << 1;
        #/@}

        #! @defgroup client_server_funcs Qorus API Functions in the Client and Server
        /** The following functions are available in the Qorus client and in all server contexts
        */
        #/@{
        #! uses the select operator to remove all occurences of a value from a list
        /** @note @em O(n) performance
        */
        public list<auto> sub remove_from_list(list<auto> list, auto val) {
            return select list, $1 != val;
        }

        #! uses the select operator to remove all occurences of a value from a list
        /** @note @em O(n) performance
        */
        public list<auto> sub remove_from_list(reference list, auto val) {
            return list = (select list, $1 != val);
        }

        #! returns a string with the XML encoding name changed to that given as an argument
        /** does not change the actual encoding of the string (which may be different)
        */
        public string sub xml_change_encoding(string xml, string enc) {
            return regex_subst(xml, "\<\?.* version=\"1.0\".*\?\>", sprintf("<?xml version=\"1.0\" encoding=\"%s\"?>", enc));
        }

        #! returns the XML encoding name given in the string (not the actual string encoding, which may be different)
        /** @throw XML-NO-HEADER the XML string did not contain an XML header
            @throw XML-INVALID-HEADER the XML string contained an invalid XML header
        */
        public string sub xml_get_encoding(string xml) {
            *string header = regex_extract(xml, "(\<\?xml.*\?\>)")[0];
            if (!exists header)
                throw "XML-NO-HEADER", sprintf("the XML string did not contain an XML header (%s...)", xml.substr(0, 20));
            string mask = "encoding=\"";
            int i = index(header, mask);
            if (i == -1) {
                string ret;
                return ret;
            }
            int len = i + length(mask);
            int j = index(substr(header, len), "\"");
            if (j == -1)
                throw "XML-INVALID-HEADER", sprintf("the XML string contained an invalid header: %s", header);
            return substr(header, len, j);
        }

        #! returns a string giving the default serialization of the given data structure for storage in Qorus
        /** the default serialization is currently YAML
            @param d the data to serialize
            @return a YAML string representing the given data structure for storage in Qorus
        */
        public string sub serialize_qorus_data(auto d) {
            return UserApi::serializeQorusData(d);
        }

        #! parses serialized data in either XML-RPC or YAML format and returns the corresponding qore data
        /** auto-detects XML-RPC or YAML decoding
            @param data the string data to deserialize
            @return the Qore data represented by the string arugment
        */
        public auto sub deserialize_qorus_data(string data) {
            return UserApi::deserializeQorusData(data);
        }

        public nothing sub deserialize_qorus_data(null data) {
        }

        #! returns a string that has been x-ored with binary "salt" data
        public string sub get_salted_string(string str, binary salt) {
            binary str_bin = binary(str);
            string sp = "";
            # get length of binary string in bytes
            int strl = elements str_bin;
            # get length of binary object in bytes
            int saltl = elements salt;
            int j = 0;
            for (int i = 0; i < strl; ++i) {
                int c = get_byte(str_bin, i) ^ get_byte(salt, j);
                if (++j == saltl)
                    j = 0;
                sp += chr(c);
            }
            return sp;
        }

        #! returns the next sequence value for the given sequence
        public softint sub next_sequence_value(AbstractDatasource ds, string name) {
            return UserApi::getNextSequenceValue(ds, name);
        }

        #! returns a datasource description string from a datasource configuration hash
        /** @param h a datasource configuration hash as returned by
            @ref Qore::SQL::AbstractDatasource::getConfigHash() "AbstractDatasource::getConfigHash()"
            @param dd_opts a bitfield of datasource description options; see @ref dd_opts for more information
        */
        public string sub get_ds_desc(hash<auto> h, *int dd_opts) {
            string desc = sprintf("%s:%s%s@%s", h.type, h.user, (dd_opts & DD_WITH_PASSWORD ? "/" + h.pass : ""), h.db);
            # add encoding
            if (h.charset && !(dd_opts & DD_SHORT))
                desc += sprintf("(%s)", h.charset);

            if (h.host)
                desc += "%" + h.host;

            if (h.port)
                desc += sprintf(":%d", h.port);

            # add options
            if (h.options && !(dd_opts & DD_SHORT)) {
                desc += "{";
                desc += foldl $1 + "," + $2, (map sprintf("%s=%s", $1.key, $1.value), h.options.pairIterator());
                desc += "}";
            }

            return desc;
        }

        #! allows @ref Qore::get_thread_call_stack() to be called from Qorus interfaces
        /** The Qore function is normally prohibited from use in Qorus interfaces due to sandboxing restrictions
        */
        public list<hash<CallStackInfo>> sub get_thread_call_stack() {
            return Qore::get_thread_call_stack();
        }
        #/@}
    }

    #! manages Qorus encryption keys
    public class CryptoKeyHelper {
        private:internal {
            # sensitive data encryption key
            *binary sd_key;
            # sensitive value encryption key
            *binary sv_key;
        }

        #! returns a binary object encrypted with AES-256 for a sensitive data hash
        /** @par Example:
            @code{.py}
            binary mac;
            binary iv = get_random_bytes(12);
            binary b = serializeEncryptSensitiveData(h, iv, \mac, aad);
            @endcode

            @param data the sensitive data hash to encrypt
            @param iv a 12-byte initialization vector for the AES-256 encryption algorithm
            @param mac a reference to a @ref binary_type "binary" object that will return the Message Authentication Code
            @param aad Additional Authenticated Data for the \a mac

            @return the binary object encrypted with AES-256 for a sensitive data hash

            @throw SENSITIVE-DATA-ERROR encryption options are not set with valid encryption keys

            @see
            - @ref Qore::encrypt() for additional exceptions that can be thrown when encrypting
            - @ref Qore::YAML::make_yaml() for additional exceptions that can be thrown when serializing in case of a data error
            - deserializeDecryptSensitiveData()
            - @ref Qore::CRYPTO_ALG_AES_256
        */
        binary serializeEncryptSensitiveData(hash<auto> data, binary iv, reference mac, string aad) {
            if (!sd_key)
                throw "SENSITIVE-DATA-ERROR", "sensitive data APIs cannot be used until the 'sensitive-data-key' and 'sensitive-value-key' options are set";
            return encrypt(CRYPTO_ALG_AES_256, make_yaml(data), sd_key, iv, \mac, 16, aad);
        }

        #! returns a decrypted sensitive data hash from the AES-256-encrypted binary object and other encryption arguments
        /** @par Example:
            @code{.py}
            hash data = deserializeDecryptSensitiveData(data, iv, mac, aad);
            @endcode

            @param data the sensitive data to decrypt using the AES-256 algorithm
            @param iv the 12-byte initialization vector used for encryption
            @param mac a reference to a @ref binary_type "binary" object that will return the Message Authentication Code
            @param aad Additional Authenticated Data for the \a mac

            @return the decrypted sensitive data hash corresponding to the arguments

            @throw SENSITIVE-DATA-ERROR encryption options are not set with valid encryption keys

            @see
            - @ref Qore::decrypt_to_string() for additional exceptions that can be thrown when encrypting
            - @ref Qore::YAML::parse_yaml() for additional exceptions that can be thrown when deserializing in case of a data error
            - serializeEncryptSensitiveData()
            - @ref Qore::CRYPTO_ALG_AES_256
        */
        hash<auto> deserializeDecryptSensitiveData(binary data, binary iv, binary mac, string aad) {
            if (!sd_key)
                throw "SENSITIVE-DATA-ERROR", "sensitive data APIs cannot be used until the 'sensitive-data-key' and 'sensitive-value-key' options are set";
            return parse_yaml(decrypt_to_string(CRYPTO_ALG_AES_256, data, sd_key, iv, mac, aad));
        }

        #! returns a string encrypted with Blowfish and subjected to base64 encoding for a sensitive data key value
        /** @par Example:
            @code{.py}
            string svalue = encodeEncryptSensitiveValue(get_sensitive_key_value());
            @endcode

            @param svalue the sensitive data key value to encrypt

            @return a string encrypted with Blowfish and subjected to base64 encoding

            @throw SENSITIVE-DATA-ERROR encryption options are not set with valid encryption keys

            @see
            - @ref Qore::encrypt() for additional exceptions that can be thrown when encrypting
            - decodeDecryptSensitiveValue()
            - @ref Qore::CRYPTO_ALG_BLOWFISH
        */
        string encodeEncryptSensitiveValue(string svalue) {
            if (!sv_key)
                throw "SENSITIVE-DATA-ERROR", "sensitive data APIs cannot be used until the 'sensitive-data-key' and 'sensitive-value-key' options are set";
            return make_base64_string(encrypt(CRYPTO_ALG_BLOWFISH, svalue, sv_key));
        }

        #! returns a decoded and decrypted sensitive data key value from the base64-encoded encrypted value
        /** @par Example:
            @code{.py}
            string svalue = decodeDecryptSensitiveValue(get_encrypted_key_value());
            @endcode

            @param svalue the base64-encoded encrypted value

            @return the decrypted sensitive data key value corresponding to the argument

            @throw SENSITIVE-DATA-ERROR encryption options are not set with valid encryption keys

            @see
            - @ref Qore::decrypt_to_string() for additional exceptions that can be thrown when encrypting
            - deserializeDecryptSensitiveData()
            - @ref Qore::CRYPTO_ALG_BLOWFISH
        */
        string decodeDecryptSensitiveValue(string svalue) {
            if (!sv_key)
                throw "SENSITIVE-DATA-ERROR", "sensitive data APIs cannot be used until the 'sensitive-data-key' and 'sensitive-value-key' options are set";
            return decrypt_to_string(CRYPTO_ALG_BLOWFISH, parse_base64_string(svalue), sv_key);
        }

        #! encrypt the data needed for a row in \c sensitive_order_data
        hash<auto> encryptOrderData(softint wfiid, string skey, string svalue, hash<auto> info, *hash<auto> meta) {
            binary mac;
            # generate Additional Authenticated Data
            string aad = sprintf("%d-%s-%s", wfiid, skey, svalue);
            hash rv.iv = get_random_bytes(12);
            rv += (
                "data": serializeEncryptSensitiveData(info, rv.iv, \mac, aad),
                "svalue": encodeEncryptSensitiveValue(svalue),
            );
            rv.mac = mac;
            if (meta) {
                binary mmac;
                rv.miv = get_random_bytes(12);
                rv.meta = serializeEncryptSensitiveData(meta, rv.miv, \mmac, aad);
                rv.mmac = mmac;
            }

            return rv;
        }

        #! returns the value of a system opion as a string
        abstract *string getKeyOption(string opt);

        #! sets up encryption keys and verifies their state
        private setupEncryption() {
            *string dfn = getKeyOption("sensitive-data-key");
            *string vfn = getKeyOption("sensitive-value-key");
            if (!dfn.val()) {
                if (vfn.val())
                    throw "QORUS-ENCRYPTION-ERROR", sprintf("System option \"sensitive-value-key\" is set to %y, but \"sensitive-data-key\" is not set; both values must be set to readable files with encryption keys in order to use sensitive data APIs", vfn);
                return;
            }
            if (!vfn.val())
                throw "QORUS-ENCRYPTION-ERROR", sprintf("System option \"sensitive-data-key\" is set to %y, but \"sensitive-value-key\" is not set; both values must be set to readable files with encryption keys in order to use sensitive data APIs", dfn);

            sd_key = getKey("data", dfn);
            sv_key = getKey("value", vfn);

            # validate keys
            try {
                auto ignored = encrypt(CRYPTO_ALG_AES_256, "x", sd_key);
                remove ignored;

            } catch (hash<ExceptionInfo> ex) {
                throw "QORUS-ENCRYPTION-ERROR", sprintf("System option \"sensitive-data-key\" = %y, however the key is not usable: %s: %s; please correct the key file to contain 32 bytes of key data and try again", dfn, ex.err, ex.desc);
            }
            try {
                auto ignored = encrypt(CRYPTO_ALG_BLOWFISH, "x", sv_key);
                remove ignored;
            } catch (hash<ExceptionInfo> ex) {
                throw "QORUS-ENCRYPTION-ERROR", sprintf("System option \"sensitive-value-key\" = %y, however the key is not usable: %s: %s; please correct the key file to contain 4 - 56 bytes of key data and try again", vfn, ex.err, ex.desc);
            }
        }

        private:internal static binary getKey(string type, string fn) {
            if (!is_readable(fn))
                throw "QORUS-ENCRYPTION-ERROR", sprintf("Unable to read sensitive %s encryption key file: %y; the system cannot be started until this error is resolved; either remove the \"sensitive-%s-key\" option or make sure the file is readable by the application user", type, fn, type);

%ifdef Unix
            hash<auto> sh = hstat(fn);
            if (sh.mode & 022)
                throw "QORUS-ENCRYPTION-ERROR", sprintf("Sensitive %s encryption key file %y as set by the \"sensitive-%s-key\" option has too permissive permissions %y (0%o); the system cannot be started until the group and/or other readable bits are removed", type, fn, type, sh.perm, sh.mode);
%endif

            binary key = ReadOnlyFile::readBinaryFile(fn);
            if (key.empty())
                throw "QORUS-ENCRYPTION-ERROR", sprintf("Sensitive %s encryption key file %y as set by the \"sensitive-%s-key\" option is empty; the system cannot be started until this error is resolved", type, fn, type);

            return key;
        }
    }
}
