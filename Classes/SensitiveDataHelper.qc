# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file SensitiveDataHelper.qc workflow helper class

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

public namespace OMQ {
    #! user API namespace root
    /** @see
        - @ref jobapi
        - @ref serviceapi
        - @ref workflowapi
        - @ref mapperapi
     */
    public namespace UserApi {
        #! Qorus workflow API namespace
        public namespace Workflow {
            #! This class is a helper class that allows @ref sensitive_data "workflow sensitive data" to be read and updated atomically; the write lock for the data is grabbed in the constructor and released in the destructor
            /** Calls to the following workflow API functions related to @ref sensitive_data "sensitive data" can be
                made normally while this object exists and the write lock is held.

                @note in %Python available as \c wf.SensitiveDataHelper

                @see @ref sensitive_data

                @since Qorus 3.1.1
             */
            final public class SensitiveDataHelper {
                public {
                }

                private:internal {
%ifdef QorusServer
                    SensitiveInstanceData data;
%endif
                }

                #! creates the object and grabs the write lock for @ref sensitive_data "workflow sensitive data" during the lifetime of the object
                /** @par %Python Example
                    @code{.py}
sdh = SensitiveDataHelper()
                    @endcode

                    @par %Qore Example
                    @code{.py}
SensitiveDataHelper sdh();
                    @endcode

                    @throw LOCK-ERROR another SensitiveDataHelper object exists in the same thread; only one object
                    can be used at a time since the object grabs the write lock
                 */
                constructor() {
%ifdef QorusServer
                    data = tld.wfe.sensitive_data;

                    if (!SensitiveInstanceData::externalLock(data))
                        throw "LOCK-ERROR", sprintf("the write lock for workflow_instanceid %d is already held", tld.wfe.workflow_instanceid);
%endif
                }

                #! destroys the object and releases the write lock
                destructor() {
%ifdef QorusServer
                    SensitiveInstanceData::externalUnlock(data);
%endif
                }

                #! returns the value one or more keys in the @ref sensitive_data "workflow sensitive data" hash for the given sensitive data key and value
                /** @par %Python Example
                    @code{.py}
# get the tax number for the person
tax_number = sdh.get("personal_id", personal_id, "tax_number")
                    @endcode

                    @par %Qore Example
                    @code{.py}
# get the tax number for the person
string tax_number = sdh.get("personal_id", personal_id, "tax_number");
                    @endcode

                    @param skey the type of value provided in \a svalue
                    @param svalue the value of the sensitive data key identified by \a skey
                    @param field zero or more string key fields to return

                    @return the value of the entire hash (if no arguments were requested), or a hash of the requested keys (if more than one key was requested), or the given value (if set, if one value is requested)
                 */
                auto get(string skey, string svalue, auto field) {
%ifdef QorusServer
                    return data.get(skey, svalue, field);
%endif
                }

                #! returns a hash with the corresponding sensitive data key and sensitive data value as well as the value of one or more keys in the @ref sensitive_data "workflow sensitive data" hash for the given sensitive data alias corresponding to a sensitive data key and value
                /** @par %Python Example
                    @code{.py}
# get the tax number for the person
tax_number = sdh.getFromAlias("0", "tax_number")
                    @endcode

                    @par %Qore Example
                    @code{.py}
# get the tax number for the person
string tax_number = sdh.getFromAlias("0", "tax_number").svalue;
                    @endcode

                    @param alias the alias to lookup; if the alias is unknown, an \c INVALID-ALIAS exception is raised
                    @param field zero or more string key fields to return

                    @return a hash of information corresponding to the arguments; the hash returned has the following keys:
                    - \c skey: (@ref string_type "string") the sensitive data key type
                    - \c svalue: (@ref string_type "string") the sensitive data value (considered sensitive itself)
                    - \c value: the value of the entire hash (if no arguments were requested), or a hash of the requested keys (if more than one key was requested), or the given value (if set, if one value is requested)

                    @throw INVALID-ALIAS the given alias is unknown
                 */
                hash<auto> getFromAlias(string alias, auto field) {
%ifdef QorusServer
                    return data.getAlias(alias, field);
%endif
                }

                #! Returns the sensitive metadata hash for the given sensitive data key and value if present, otherwise returns an empty hash
                /** @par %Python Example
                    @code{.py}
# get the tax number for the person
tax_number = sdh.getFromAlias("0", "tax_number")
                    @endcode

                    @par %Qore Example
                    @code{.py}
hash<auto> metadata = sdh.getMetadata("personal_id", personal_id);
                    @endcode

                    @param skey the type of sensitive key provided in \a svalue
                    @param svalue the value of the sensitive data key identified by \a skey

                    @return the sensitive metadata hash stored according to the sensitive data key and value; if no such sensitive key and value exist for the order, or no metadata is present for the given sensitive key and value, then an empty hash is returned

                    @note
                    - returns sensitive data; take care not to log any of the data returned by this function

                    @see
                    - @ref SensitiveDataHelper::getMetadataFromAlias()
                    - @ref sensitive_data
                 */
                hash<auto> getMetadata(string skey, string svalue) {
%ifdef QorusServer
                    return data.getMetadata(skey, svalue);
%endif
                }

                #! returns a hash with the corresponding sensitive data key and sensitive data value as well as the value of the sensitive metadata hash for the given sensitive data alias corresponding to a sensitive data key and value
                /** @par %Python Example
                    @code{.py}
# get sensitive metadata
metadata = sdh.getMetadataFromAlias('0')['value']
                    @endcode

                    @par %Qore Example
                    @code{.py}
# get sensitive metadata
hash<auto> metadata = sdh.getMetadataFromAlias("0").value;
                    @endcode

                    @param alias the alias to lookup; if the alias is unknown, an \c INVALID-ALIAS exception is raised

                    @return a hash of information corresponding to the arguments; the hash returned has the following keys:
                    - \c skey: (@ref string_type "string") the sensitive data key type
                    - \c svalue: (@ref string_type "string") the sensitive data value (considered sensitive itself)
                    - \c value: (@ref hash_type "hash") the value of the sensitive metadata hash, if any

                    @throw INVALID-ALIAS the given alias is unknown

                    @note
                    - returns sensitive data; take care not to log any of the sensitive data returned by this function

                    @see
                    - @ref SensitiveDataHelper::getMetadata()
                    - @ref sensitive_data
                 */
                hash<auto> getMetadataFromAlias(string alias) {
%ifdef QorusServer
                    return data.getMetadataAlias(alias);
%endif
                }

                #! returns a hash of all sensitive data aliases for the current order or an empty hash if there are none
                /** @par %Python Example
                    @code{.py}
ah = sdh.getAliases()
                    @endcode

                    @par %Qore Example
                    @code{.py}
hash<auto> ah = sdh.getAliases();
                    @endcode

                    @return a hash of all sensitive data aliases for the current order or an empty hash if there are
                    none, otherwise keys are alias names and values are hashes with the following keys:
                    - \c skey: (@ref string_type "string") the sensitive data key type
                    - \c svalue: (@ref string_type "string") the sensitive data value (considered sensitive itself)

                    @note
                    - returns sensitive data; take care not to log any of the sensitive data returned by this function
                 */
                hash<auto> getAliases() {
%ifdef QorusServer
                    return data.getAliases();
%endif
                }

                #! Returns a hash of sensitive data keys and values saved against the order; the sensitive data hashes themselves are not returned, just the information used to index sensitive data against the order
                /** @par %Python Example
                    @code{.py}
h = sdh.getKeyValues()
                    @endcode

                    @par %Qore Example
                    @code{.py}
hash<auto> h = sdh.getKeyValues();
                    @endcode

                    @return a hash of sensitive data keys and values saved against the order; the sensitive data
                    hashes themselves are not returned, just the information used to index sensitive data against the
                    order; if no sensitive data is stored against the order, an empty hash is returned

                    @note returns sensitive data; sensitive data values should not be logged

                    @see
                    - @ref sensitive_data
                 */
                hash<auto> getKeyValues() {
%ifdef QorusServer
                    return data.getKeyValues();
%endif
                }

                #! replaces @ref sensitive_data "sensitive data" for the sensitive key value given; the data has already been committed to the database when the method returns
                /** @par %Python Example
                    @code{.py}
sdh.replace("personal_id", personal_id, new_data)
                    @endcode

                    @par %Qore Example
                    @code{.py}
sdh.replace("personal_id", h.personal_id, h{upd});
                    @endcode

                    @param skey the type of value provided in \a svalue; must not be longer than 100 bytes long or a
                    \c SENSITIVE-DATA-ERROR exception is raised
                    @param svalue the value of the sensitive data key identified by \a skey; if this string is empty
                    or longer than 100 bytes, a \c SENSITIVE-DATA-ERROR exception is raised
                    @param new_data the data to use to replace the sensitive data hash for the given sensitive data
                    key and value
                    @param aliases zero or more aliases for the sensitive key value given
                    @param meta optional sensitve data metadata with the following recommended keys:
                    - \c PURPOSE: free-form information about the purpose of the sensitive data
                    - \c CATEGORIES: free-form information about the categories of sensitive data
                    - \c RECIPIENTS: free-form information about the recipients or recipient catories of sensitive
                      data
                    - \c STORAGE: free-form information about the storage time or rules for sensitive data

                    @throw SENSITIVE-DATA-ERROR no sensitive key value was provided; sensitive key or alias value too
                    long (100 bytes maximum length in the encoding used by the system schema)

                    @note
                    - there is currently no function equivalent to this method for
                      @ref sensitive_data "sensitive dynamic data"; this method replaces all the sensitive data for
                      the given sensitive key and value
                    - The metadata keys listed above are recommended for consistency's sake but are not checked; a
                      hash with any keys can be stored with this API
                    - The use of this method causes SQL I/O to be performed in the system schema; to maximize
                      performance, calls to this and other similar methods should be minimized if possible
                    - this method only replaces sensitive data for a single sensitive data key and value, for a method
                      that replaces sensitive data for multiple sensitive data keys and values in a single
                      transaction, see @ref replaceMulti()
                    - use @ref replaceMulti() when replacing sensitive data for more than one key and value at a time
                      as it is more efficient from a database transaction I/O point of view
                 */
                nothing replace(string skey, string svalue, *hash<auto> new_data, *softlist aliases, *hash<auto> meta) {
%ifdef QorusServer
                    data.replaceAndSave(skey, svalue, new_data, aliases, meta, tld.wfe.workflow_instanceid);
                    Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "sensitive");
%endif
                }

                #! replaces @ref sensitive_data "sensitive data" for one more more sensitive key values given; the data has already been committed to the database when the method returns
                /** @par %Qore Example
                    @code{.py}
hash<string, hash<string, hash<SensitiveDataInfo>>> sinfo();
# get_my_data() returns a hash of sensitive "personal_id" keys and sensitive data hashes
# this is then mapped to the data structure required for the call
map sinfo.personal_id{$1.key} = new hash<SensitiveDataInfo>(("data": $1.value)), get_my_data().pairIterator();
sdh.replaceMulti(sinfo);
                    @endcode

                    @param sinfo a hash keyed by sensitive data key, where each value is a hash keyed by sensitive
                    data value, where each value of that hash is a @ref OMQ::SensitiveDataInfo "SensitiveDataInfo"
                    hash giving the sensitive information for the given sensitive data key and value

                    @throw SENSITIVE-DATA-ERROR no sensitive key value was provided; sensitive key or alias value too
                    long (100 bytes maximum length in the encoding used by the system schema)

                    @note
                    - there is currently no function equivalent to this method for
                      @ref sensitive_data "sensitive dynamic data"; this method replaces all the sensitive data for
                      the given sensitive keys and values
                    - metadata keys are not checked; a hash with any metadata keys can be stored with this API
                    - The use of this method causes SQL I/O to be performed in the system schema; to maximize
                      performance, calls to this and other similar methods should be minimized if possible
                    - this method replaces sensitive data for multiple sensitive data keys and values in a single
                      transaction and therefore is preferred when updating multiple sensitive data elements over
                      @ref replace()

                    @since Qorus 3.1.1.p1
                */
                nothing replaceMulti(hash<string, hash<string, hash<SensitiveDataInfo>>> sinfo) {
%ifdef QorusServer
                    data.replaceAndSaveMulti(sinfo, tld.wfe.workflow_instanceid);
                    Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "sensitive");
%endif
                }

                #! replaces @ref sensitive_data "sensitive data" for the sensitive alias given; the data has already been committed to the database when the method returns
                /** @par %Python Example
                    @code{.py}
sdh.replaceWithAlias(alias, new_data)
                    @endcode

                    @par %Qore Example
                    @code{.py}
sdh.replaceWithAlias(alias, h{upd});
                    @endcode

                    @param alias the sensitive data alias; must be an existing alias or an \c INVALID-ALIAS exception
                    is raised
                    @param new_data the data to use to replace the sensitive data hash for the given sensitive data
                    alias
                    @param meta optional sensitve data metadata with the following recommended keys:
                    - \c PURPOSE: free-form information about the purpose of the sensitive data
                    - \c CATEGORIES: free-form information about the categories of sensitive data
                    - \c RECIPIENTS: free-form information about the recipients or recipient catories of sensitive
                      data
                    - \c STORAGE: free-form information about the storage time or rules for sensitive data

                    @throw INVALID-ALIAS the given alias is unknown

                    @note
                    - there is currently no function equivalent to this method for
                      @ref sensitive_data "sensitive dynamic data"; this method replaces all the sensitive data for
                      the given sensitive key and value
                    - The metadata keys listed above are recommended for consistency's sake but are not checked; a
                      hash with any keys can be stored with this API
                    - The use of this method causes SQL I/O to be performed in the system schema; to maximize
                      performance, calls to this and other similar methods should be minimized if possible
                 */
                nothing replaceFromAlias(string alias, *hash<auto> new_data, *hash<auto> meta) {
%ifdef QorusServer
                    data.replaceAndSaveAlias(alias, new_data, meta, tld.wfe.workflow_instanceid);
                    Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "sensitive");
%endif
                }

                #! Updates or creates the values of one or more keys in the workflow order's sensitive data hash for the given sensitive data key and value; the data has already been committed to the database when the method returns
                /** @par %Python Example
                    @code{.py}
sdh.update("personal_id", personal_id, new_data, new_data["tax_number"])
                    @endcode

                    @par %Qore Example
                    @code{.py}
sdh.update("personal_id", h.person.personal_id, h, h{"tax_number",});
                    @endcode

                    @param skey the type of value provided in \a svalue; must not be longer than 100 bytes long or a
                    \c SENSITIVE-DATA-ERROR exception is raised
                    @param svalue the value of the sensitive data key identified by \a skey; if this string is empty
                    or longer than 100 bytes, a \c SENSITIVE-DATA-ERROR exception is raised
                    @param new_data the data to create or update against \a skey; existing keys will be replaced; new
                    keys will be added; if the new hash does not refer to existing keys, then those existing keys
                    remain untouched
                    @param aliases zero or more string aliases for the sensitive key and value given
                    @param meta optional sensitve data metadata with the following recommended keys:
                    - \c PURPOSE: free-form information about the purpose of the sensitive data
                    - \c CATEGORIES: free-form information about the categories of sensitive data
                    - \c RECIPIENTS: free-form information about the recipients or recipient categories of sensitive
                      data
                    - \c STORAGE: free-form information about the storage time or rules for sensitive data

                    @throw SENSITIVE-DATA-ERROR no sensitive key value was provided; sensitive key or alias value too
                    long (100 bytes maximum length in the encoding used by the system schema)

                    @note
                    - do not use sensitive data for the sensitive key names itself (\a skey) or alias(es)
                      (\a aliases); key names and aliases may be logged to provide an audit trail of changes to
                      sensitive data
                    - metadata keys listed above for the \a meta argument are recommended for consistency's sake but
                      are not checked; a hash with any keys can be stored with this API
                    - The use of this method causes SQL I/O to be performed in the system schema; to maximize
                      performance, calls to this and other similar methods should be minimized if possible

                    @see
                    - @ref sensitive_data
                */
                nothing update(string skey, string svalue, hash<auto> new_data, *softlist aliases, *hash<auto> meta) {
%ifdef QorusServer
                    data.updateAndSave(skey, svalue, new_data, aliases, meta, tld.wfe.workflow_instanceid);
                    Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "sensitive");
%endif
                }

                #! Updates or creates the values of one or more keys in the workflow order's sensitive data hash for the given sensitive data alias; the data has already been committed to the database when the method returns
                /** @par %Python Example
                    @code{.py}
sdh.updateFromAlias(alias, new_data)
                    @endcode

                    @par %Qore Example
                    @code{.py}
sdh.updateFromAlias(alias, h);
                    @endcode

                    @param alias the sensitive data alias; must be an existing alias or an \c INVALID-ALIAS exception
                    is raised
                    @param new_data the data to create or update against \a skey; existing keys will be replaced; new
                    keys will be added; if the new hash does not refer to existing keys, then those existing keys
                    remain untouched
                    @param meta optional sensitve data metadata with the following recommended keys:
                    - \c PURPOSE: free-form information about the purpose of the sensitive data
                    - \c CATEGORIES: free-form information about the categories of sensitive data
                    - \c RECIPIENTS: free-form information about the recipients or recipient categories of sensitive data
                    - \c STORAGE: free-form information about the storage time or rules for sensitive data

                    @throw INVALID-ALIAS the given alias is unknown

                    @note
                    - do not use sensitive data for the sensitive data alias value; alias values can be logged to
                      provide an audit trail of changes to sensitive data
                    - metadata keys listed above for the \a meta argument are recommended for consistency's sake but
                      are not checked; a hash with any keys can be stored with this API
                    - The use of this method causes SQL I/O to be performed in the system schema; to maximize
                      performance, calls to this and other similar methods should be minimized if possible

                    @see
                    - @ref sensitive_data
                */
                nothing updateFromAlias(string alias, hash<auto> new_data, *hash<auto> meta) {
%ifdef QorusServer
                    data.updateAndSaveAlias(alias, new_data, meta, tld.wfe.workflow_instanceid);
                    Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "sensitive");
%endif
                }

                #! Deletes one or more keys from the workflow order data instance’s sensitive data hash for the given sensitive data key and value; the changes have already been committed to the database when the method returns
                /** @par %Python Example
                    @code{.py}
# delete the "tax_number" and "insurance_number" keys from the sensitive data hash for the given person
sdh.deleteKey("personal_id", personal_id, ("tax_number", "insurance_number"))
                    @endcode

                    @par %Qore Example
                    @code{.py}
# delete the "tax_number" and "insurance_number" keys from the sensitive data hash for the given person
sdh.deleteKey("personal_id", personal_id, ("tax_number", "insurance_number"));
                    @endcode

                    @param skey the type of sensitive key provided in \a svalue
                    @param svalue the value of the sensitive data key identified by \a skey
                    @param keysv a single key or a list of keys to delete in the workflow order's sensitive data hash for the given sensitive key-value pair

                    @return @ref Qore::True "True" if the data existed and was deleted, @ref Qore::False "False" if no data was deleted

                    @note
                    - The use of this method causes SQL I/O to be performed in the system schema; to maximize
                      performance, calls to this and other similar methods should be minimized if possible

                    @see
                    - @ref sensitive_data
                 */
                bool deleteKey(string skey, string svalue, softlist<softstring> keysv) {
%ifdef QorusServer
                    if (data.deleteAndSave(skey, svalue, keysv, tld.wfe.workflow_instanceid)) {
                        Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "sensitive");
                        return True;
                    }
                    return False;
%endif
                }

                #! Deletes the sensitive data hash for the given sensitive data key and value; the changes have already been committed to the database when the method returns
                /** @par %Python Example
                    @code{.py}
sdh.del("personal_id", personal_id)
                    @endcode

                    @par %Qore Example
                    @code{.py}
sdh.del("personal_id", personal_id);
                    @endcode

                    @param skey the type of sensitive key provided in \a svalue
                    @param svalue the value of the sensitive data key identified by \a skey

                    @return @ref Qore::True "True" if the data existed and was deleted, @ref Qore::False "False" if no
                    such sensitive data key and value were present in the order

                    @note
                    - The use of this method causes SQL I/O to be performed in the system schema; to maximize
                      performance, calls to this and other similar methods should be minimized if possible

                    @see
                    - @ref sensitive_data
                */
                bool del(string skey, string svalue) {
%ifdef QorusServer
                    if (data.deleteAndSave(skey, svalue, tld.wfe.workflow_instanceid)) {
                        Qorus.events.postWorkflowDataUpdated(tld.wfe.workflowid, tld.wfe.workflow_instanceid, "sensitive");
                        return True;
                    }
                    return False;
%endif
                }
            }
        }
    }
}
