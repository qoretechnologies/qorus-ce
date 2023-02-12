# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file qorus-client.ql this is the main include file for the Qorus client library

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

# push parse options and restore at exit of parsing this file
%push-parse-options
%new-style
%require-types
%require-our
%perl-bool-eval

# uses hard typing; safe with '%require-types'
%requires qore >= 0.8.6

# here we add fallback paths to the QORE_INCLUDE_DIR search path,
# in case QORE_INCLUDE_DIR is not set properly
%append-include-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib:$OMQ_DIR/qlib/intern
# same with the module path
%append-module-path /var/opt/qorus/qlib:$OMQ_DIR/qlib:/opt/qorus/qlib:$OMQ_DIR/qlib/intern

# requires the qorus core client module
%requires QorusClientCore

# uses xml functionality
%requires xml
# uses json functionality
%requires json
# uses yaml functionality
%requires yaml
# uses uuid functionality
%requires uuid
# contains the HttpServerUtil user module
%requires HttpServerUtil
# contains the HttpServer user module
%requires HttpServer
# contains the Mime user module
%requires Mime
# contains the YamlRpcClient user module
%requires YamlRpcClient
# contains the YamlRpcHandler user module
%requires YamlRpcHandler
# requires the XmlRpcHandler user module
%requires XmlRpcHandler
# requires the JsonRpcHandler user module
%requires JsonRpcHandler
# requires the RestHandler user module
%requires RestHandler
# requires the WSDL user module
%requires WSDL
# requires the SoapClient user module
%requires SoapClient
# requires the Util user module
%requires Util

# for parsing cron timer strings
%include CronTimer.qc

# thread-local data object
thread_local OMQ::ThreadLocalData tld;

# fake server application variable
our hash Qorus;

public namespace OMQ;

#! backwards-compatible option parsing - parses everything into a single hash
/** @deprecated use qorus_parse_options() instead
*/
deprecated hash sub omq_read_option_file() {
    hash h = qorus_parse_options();

    hash rh = {};
    foreach string k in (keys h)
	rh += h{k};

    return rh;
}

#! backwards-compatible function
/** @deprecated it is not necessary to call this function directly anymore; just call qorus_client_init() or qorus_client_init2() and then @ref OMQ::QorusClientApi::getDatasource() "::omqclient.getDatasource()", etc
  */
deprecated sub parse_dbparams() {
    qorus_client_init();
}

#! backwards-compatible function
/** @deprecated use omqclient.setDatasourceFromText() instead
  */
deprecated sub process_datasource(string line) {
    qorus_client_init();
    omqclient.setDatasourceFromText(line);
}

#! backwards-compatible function
/** @deprecated use omqclient.getDatasource() or get_datasource_dedicated() instead
  */
deprecated Datasource sub get_datasource(string name) {
    qorus_client_init();
    return omqclient.getDatasource(name);
}

#! opens all system datasource and any optional list of datasources given to the function
sub open_datasources() {
    qorus_client_init();

    foreach string name in (argv)
	omqclient.getDatasource(name);
}

#! returns a string representing a warning from an exception hash
/** @param ex an exception hash
    @return a string representing a warning
  */
string sub getWarningString(hash ex) {
    string str;
    while (ex.val()) {
        str += sprintf("warning at %s: %s: %s", get_ex_pos(ex), ex.err, ex.desc);

        if (!exists ex.next)
            break;
        str += "\nchained warning:\n";
        ex = ex.next;
    }
    return str;
}

#! returns the next value of the given sequence from the system "omq" datasource as a string
/** @param name the name of the sequence to use
    @return the next value of the given sequence from the system "omq" datasource as a string
  */
string sub get_next_sequence_value(string name) {
    return omqclient.getNextSequenceValue(name);
}

#! returns the next value of the given sequence from the system "omq" datasource as an int
/** @param name the name of the sequence to use
    @return the next value of the given sequence from the system "omq" datasource as a string
  */
int sub get_next_sequence_value_int(string name) {
    return omqclient.getNextSequenceValueInt(name);
}

#! inserts an element in a list
/** @deprecated use qore's splice operator instead; it's faster and standard Qore functionality
  */
list sub insert_in_list(list l, any val, int pos) {
   splice l, pos, 0, (val.typeCode() == NT_LIST ? list(val) : val);
   return l;
}

#! inserts an element in a list
/** @deprecated use qore's splice operator instead; it's faster and standard Qore functionality
  */
list sub insert_in_list(reference l, any val, int pos) {
   splice l, pos, 0, (val.typeCode() == NT_LIST ? list(val) : val);
   return l;
}

#! removes a key from a hash
/** @deprecated use the "-" operator instead (hash - string); it is faster and standard Qore functionality
  */
hash sub remove_key(hash h, string key) {
   h -= key;
   return h;
}

#! returns the index of the first element in the list that matches the 2nd argument with soft comparisons
int sub get_index(list l, any val) {
   for (int i = 0; i < elements l; i++)
      if (l[i] == val)
         return i;
   return -1;
}

#! returns True if the two list arguments are equal ignoring the order of the elements with soft comparisons
bool sub lists_equal_ignore_order(list list1, list list2) {
   if (elements list1 != elements list2)
      return False;

   while (elements list1) {
       any e = shift list1;
       for (int i = 0; i < elements list2; ++i) {
           if (e == list2[i]) {
               # removed matched element
               splice list2, i, 1;
               break;
           }
       }
       if (elements list1 != elements list2)
           return False;
   }

   return True;
}

#! returns True if the two list arguments are equal ignoring the order of the elements with hard comparisons
bool sub lists_equal_ignore_order_hard(list list1, list list2) {
   if (elements list1 != elements list2)
      return False;

   while (elements list1) {
       any e = shift list1;
       for (int i = 0; i < elements list2; ++i) {
           if (e === list2[i]) {
               # removed matched element
               splice list2, i, 1;
               break;
           }
       }
       if (elements list1 != elements list2)
           return False;
   }

   return True;
}

#! returns True if small only has elements that are present in big (small <= big) with soft comparisons
/** @see list_subset_hard()
  */
bool sub list_subset(list small, list big) {
    if (!elements big)
        return !elements small ? True : False;

    foreach any e in (small) {
        bool ok = False;
        for (int i = 0; i < elements big; ++i) {
            if (e == big[i]) {
                # remove element from big
                splice big, i, 1;
                ok = True;
                break;
            }
        }
        if (!ok)
            return False;
    }
    return True;
}

#! returns True if small is in big (or big is empty and small is NOTHING) otherwise returns False; uses soft comparisons
/** @see list_subset_hard()
  */
bool sub list_subset(any small, list big) {
    if (!elements big)
        return !exists small ? True : False;

    return !inlist(small, big) ? False : True;
}

#! returns True if small only has elements that are present in big (small <= big) with hard comparisons
/** @see list_subset()
  */
bool sub list_subset_hard(list small, list big) {
    if (!elements big)
        return !elements small ? True : False;

    foreach any e in (small) {
        bool ok = False;
        for (int i = 0; i < elements big; ++i) {
            if (e === big[i]) {
                # remove element from big
                splice big, i, 1;
                ok = True;
                break;
            }
        }
        if (!ok)
            return False;
    }
    return True;
}

#! returns True if small is in big (or big is empty and small is NOTHING) otherwise returns False; uses hard comparisons
/** @see list_subset()
  */
bool sub list_subset_hard(any small, list big) {
    if (!elements big)
        return !exists small ? True : False;

    return !inlist_hard(small, big) ? False : True;
}

#! returns the current script name
/** @deprecated use standard Qore function get_script_name() instead
  */
deprecated *string sub get_program_name() {
    return get_script_name();
}

# do not use this function; will be removed in a future version of Qore
bool sub omq_inlist_sorted(int i, list l, reference r) {
    foreach int bi in (l) {
        if (i === bi)
            return True;
        if (bi > i) {
            r = bi;
            return False;
        }
    }
    return False;
}

#! returns True if the list has all unique elements; uses soft comparisons
bool sub unique_elements(list l, any dup) {
    for (int i = 0; i < (elements l - 1); ++i) {
        for (int j = i + 1; j < elements l; ++j) {
            if (l[i] == l[j]) {
                dup = l[i];
                return False;
            }
        }
    }
    return True;
}

#! returns True if the list has all unique elements; uses hard comparisons
bool sub unique_elements_hard(list l, any dup) {
    for (int i = 0; i < (elements l - 1); ++i) {
        for (int j = i + 1; j < elements l; ++j) {
            if (l[i] === l[j]) {
                dup = l[i];
                return False;
            }
        }
    }
    return True;
}

# to avoid a warning about tld
nothing sub __DUMMY() {
    delete tld;
}
