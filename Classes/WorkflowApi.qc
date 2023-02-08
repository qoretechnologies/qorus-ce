# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file WorkflowApi.qc class-based workflow API

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace OMQ {
    public namespace UserApi {
        #! main workflow API namespace
        public namespace Workflow {}
    }
}

#! primary workflow API class
/** @note In %Python available as \c wfapi
*/
public class OMQ::UserApi::Workflow::WorkflowApi inherits UserApi {
    #! returns a unique async key for the order for use with @ref OMQ::UserApi::Workflow::QorusAsyncStepBase::submitAsyncKey() "QorusAsyncStepBase::submitAsyncKey()"
    /** the generated key uses the workflow_instanceid, stepid, and ind number for the step
        to generate a unique key.  Another alterative would be to call UUID::get()
    */
    static string generateUniqueKey() {
%ifdef QorusServer
        return Qorus.control.execHash{tld.index}.generateUniqueKey();
%endif
    }

    #! Raises an error against the current step without affecting the flow of processing
    /** This method will affect the final status of the step, segment, and workflow, if the severity of the error is @ref OMQ::ES_Major or @ref OMQ::ES_Fatal.  If the error raised is not defined, severity @ref OMQ::ES_Major is assumed.

        @param err the string error code
        @param info additional information for the error; should normally be a string in order to be logged in the database; if not a string then it will be converted to a string for saving in error history

        @note workflow errors can also be raised by throwing an exception
    */
    static stepError(string err, auto info) {
%ifdef QorusServer
        Qorus.control.execHash.(tld.index).stepError(err, info);
%endif
    }

    #! Raises an error against the current step without affecting the flow of processing
    /** This method will affect the final status of the step, segment, and workflow, if the severity of the error is @ref OMQ::ES_Major or @ref OMQ::ES_Fatal.  If the error raised is not defined, severity @ref OMQ::ES_Major is assumed.

        @param err the string error code
        @param info additional information for the error; should normally be a string in order to be logged in the database; if not a string then it will be converted to a string for saving in error history
        @param retry_delay the amount of time to wait until a retry is made; overrides any value in the error definition; this may be either a relative date/time value (in which case the value is added to the current time to arrive at an absolute date/time value), or an absolute date/time value, giving the earliest date/time that the error will be retried

        @note workflow errors can also be raised by throwing an exception
    */
    static stepError(string err, auto info, date retry_delay) {
%ifdef QorusServer
        softstring id = tld.index;
        Qorus.control.execHash{id}.stepError(err, info);
        WorkflowApi::setRetryDelay(retry_delay);
%endif
    }

    #! Raises an error against the current step without affecting the flow of processing
    /** This method will affect the final status of the step, segment, and workflow, if the severity of the error is @ref OMQ::ES_Major or @ref OMQ::ES_Fatal.  If the error raised is not defined, severity @ref OMQ::ES_Major is assumed.

        @param err the string error code
        @param info additional information for the error; should normally be a string in order to be logged in the database; if not a string then it will be converted to a string for saving in error history
        @param retry_delay the amount of time in seconds to wait until a retry is made; overrides any value in the error definition

        @note workflow errors can also be raised by throwing an exception
    */
    static stepError(string err, auto info, int retry_delay) {
%ifdef QorusServer
        softstring id = tld.index;
        Qorus.control.execHash{id}.stepError(err, info);
        WorkflowApi::setRetryDelay(retry_delay);
%endif
    }

    #! Raises a warning against the step
    /** The information is logged, but does not affect the step’s status.

        @param err the string error code
        @param info additional information for the error; should normally be a string in order to be logged in the
        database; if not a string then it will be converted to a string for saving in error history
    */
    static stepWarning(string err, auto info) {
%ifdef QorusServer
        softstring id = tld.index;
        Qorus.control.execHash{id}.stepWarning(err, info);
%endif
    }

    #! Raises a warning against the step
    /** The information is logged, but does not affect the step’s status.

        @param err the string error code
        @param fmt a format string to format additional arguments
    */
    static stepWarning(string err, string fmt) {
%ifdef QorusServer
        softstring id = tld.index;
        string info = vsprintf(fmt, argv);
        Qorus.control.execHash{id}.stepWarning(err, info);
%else
        delete argv;
%endif
    }

    #! Sets the value of the retry delay for a step error or an asynchronous step
    /** Only takes effect when called from an asynchronous step that will receive an @ref OMQ::StatAsyncWaiting
        (\c "A") status or when called from a normal step after an error has been raised that will cause the step to
        get a @ref OMQ::StatRetry (\c "R") status.  Note that if this method is called before an error is raised, the
        retry delay setting will be lost.

        Otherwise, to affect the retry of a normal step when an error has been raised that will give the step a status
        of @ref OMQ::StatRetry (\c "R"), you can also use the stepError() method with the optional third argument
        giving the retry delay instead of calling this method after the call to stepError().

        @param delay the amount of time to wait until a retry is made; overrides any value in the error definition
    */
    static setRetryDelay(date delay) {
%ifdef QorusServer
        QDBG_ASSERT(ensure_tld());
        tld.retryDelay = delay.relative() ? now_us() + delay : delay;
%endif
    }

    #! Sets the value of the retry delay for a step error or an asynchronous step
    /** Only takes effect when called from an asynchronous step that will receive an @ref OMQ::StatAsyncWaiting
        (\c "A") status or when called from a normal step after an error has been raised that will cause the step to
        get a @ref OMQ::StatRetry (\c "R") status.  Note that if this method is called before an error is raised, the
        retry delay setting will be lost.

        Otherwise, to affect the retry of a normal step when an error has been raised that will give the step a status
        of @ref OMQ::StatRetry (\c "R"), you can also use the stepError() method with the optional third argument
        giving the retry delay instead of calling this method after the call to stepError().

        @param secs the amount of time in seconds to wait until a retry is made; overrides any value in the error
        definition
    */
    static setRetryDelay(int secs) {
%ifdef QorusServer
        QDBG_ASSERT(ensure_tld());
        tld.retryDelay = now_us() + seconds(secs);
%endif
    }

    #! Returns the hash data associated with the error code passed as an argument
    /** @param err the error name

        @return normally returns a hash of error information or @ref nothing if the error is not defined
    */
    static *hash<auto> getErrorInfo(string err) {
%ifdef QorusServer
        return Qorus.control.execHash.(tld.index).getErrorInfo(err);
%endif
    }

    #! Updates the values of one or more keys in the workflow order data instance’s @ref dynamicdata "dynamic data hash"
    /** Dynamic data is directly linked to the order data the workflow execution instance is processing.

        Changes are committed to the database before the method returns.
        @see @ref dynamicdata "Workflow Order Dynamic Data"
        @param hash the key-value pairs to update in dynamic data

        @note
        - This call does not replace the dynamic data hash; any keys in the hash parameter are added to the dynamic data hash
        - The use of this method causes SQL I/O to be performed in the system schema; to maximize performance, calls to this and other similar methods should be minimized if possible

        @see
        - @ref dynamicdata
        - DynamicDataHelper
        - @ref OMQ::UserApi::Workflow::DynamicHelper::update() "DynamicHelper::update()"
    */
    static updateDynamicData(hash<auto> hash) {
%ifdef QorusServer
        SM.updateDynamicData(hash);
%endif
    }

    #! Deletes one or more keys from the workflow order data instance’s @ref dynamicdata "dynamic data hash"
    /** Dynamic data is directly linked to the order data the workflow execution instance is processing.

        Changes are committed to the database before the method returns.

        @see @ref dynamicdata "Workflow Order Dynamic Data"

        @param list a single key or a list of keys to delete in the workflow order's dynamic data

        @note The use of this method causes SQL I/O to be performed in the system schema; to maximize performance, calls to this and other similar methods should be minimized if possible

        @see
        - @ref dynamicdata
        - DynamicDataHelper
    */
    static deleteDynamicDataKey(softlist<auto> list) {
%ifdef QorusServer
        SM.deleteDynamicDataKey(list);
%endif
    }

    #! Retrieves the values of one or more keys from the workflow order data instance’s @ref dynamicdata "dynamic data hash"
    /** Dynamic data is directly linked to the order data the workflow execution instance is processing.

        @see @ref dynamicdata "Workflow Order Dynamic Data"

        Pass a single string argument, in which case the value of that key is returned, or a list of strings, in
        which case a hash is returned giving the values of all the keys requested

        @see
        - @ref dynamicdata
        - getDynamicDataArgs()
        - DynamicDataHelper
        - @ref OMQ::UserApi::Workflow::WorkflowDataHelper::get() "WorkflowDataHelper::get()"
    */
    static auto getDynamicData() {
%ifdef QorusServer
        return SM.getDynamicData(argv);
%else
        delete argv;
%endif
    }

    #! Retrieves the values of one or more keys from the workflow order data instance’s @ref dynamicdata "dynamic data hash"
    /** Dynamic data is directly linked to the order data the workflow execution instance is processing.

        @see @ref dynamicdata "Workflow Order Dynamic Data"

        @param keylist for a single string argument, the value of that key is returned, for a list of strings, a hash
        is returned giving the values of all the keys requested

        @see
        - @ref dynamicdata
        - getDynamicData()
        - DynamicDataHelper
        - @ref OMQ::UserApi::Workflow::WorkflowDataHelper::get() "WorkflowDataHelper::get()"
    */
    static auto getDynamicDataArgs(*softlist<auto> keylist) {
%ifdef QorusServer
        return SM.getDynamicData(keylist);
%endif
    }

    #! Retrieves the values of one or more keys from the workflow order data instance’s @ref staticdata "static data hash"
    /** Pass a single string argument, in which case the value of that key is returned, or a list of strings, in
        which case a hash is returned giving the values of all the keys requested

        Workflow order static data corresponds to the deserialized contents of the database field
        \c ORDER_INSTANCE.STATICDATA for the current workflow order data instance.

        @see @ref staticdata "Workflow Order Static Data"

        @return data from the workflow order data instance’s static data hash according to the arguments passed

        @see
        - @ref staticdata
        - getStaticDataArgs()
    */
    static auto getStaticData() {
%ifdef QorusServer
        return SM.getStaticData(argv);
%else
        delete argv;
%endif
    }

    #! Retrieves the values of one or more keys from the workflow order data instance’s @ref staticdata "static data hash"
    /** Pass a single string argument, in which case the value of that key is returned, or a list of strings, in
        which case a hash is returned giving the values of all the keys requested

        Workflow order static data corresponds to the deserialized contents of the database field
        \c ORDER_INSTANCE.STATICDATA for the current workflow order data instance.

        @see @ref staticdata "Workflow Order Static Data"

        @return data from the workflow order data instance’s static data hash according to the arguments passed

        @see
        - @ref staticdata
        - getStaticData()
    */
    static auto getStaticDataArgs(*softlist<auto> keylist) {
%ifdef QorusServer
        return SM.getStaticData(keylist);
%endif
    }

    #! Updates the values of one or more keys in the workflow order data instance’s @ref tempdata "temporary data hash"
    /** @param hash the key-value pairs to update in workflow temporary data
        @see @ref tempdata "Workflow Temporary Data"

        @note This call does not replace the @ref tempdata "temporary data hash"; any keys in the hash parameter are
        added to the @ref tempdata "temporary data hash"

        @see
        - @ref tempdata
        - TempDataHelper
        - @ref OMQ::UserApi::Workflow::TempDataHelper::update() "TempDataHelper::update()"
    */
    static updateTempData(hash<auto> hash) {
%ifdef QorusServer
        SM.updateTempData(hash);
%endif
    }

    #! Retrieves the values of one or more keys from the workflow order data instance’s @ref tempdata "temporary data hash"
    /** @see @ref tempdata "Workflow Temporary Data"

        @see
        - @ref tempdata
        - getTempDataArgs()
        - TempDataHelper
        - @ref OMQ::UserApi::Workflow::TempDataHelper::get() "TempDataHelper::get()"
    */
    static auto getTempData() {
%ifdef QorusServer
        return SM.getTempData(argv);
%else
        delete argv;
%endif
    }

    #! Retrieves the values of one or more keys from the workflow order data instance’s @ref tempdata "temporary data hash"
    /** @see @ref tempdata "Workflow Temporary Data"

        @see
        - @ref tempdata
        - getTempData()
        - TempDataHelper
        - @ref OMQ::UserApi::Workflow::TempDataHelper::get() "TempDataHelper::get()"
    */
    static auto getTempDataArgs(*softlist<auto> keylist) {
%ifdef QorusServer
        return SM.getTempData(keylist);
%endif
    }

    #! Deletes one or more keys from the workflow order data instance’s @ref tempdata "temporary data hash"
    /** @param list a single key or a a list of strings (keys) to delete in workflow temporary data

        @see @ref tempdata "Workflow Temporary Data"

        @see
        - @ref tempdata
        - TempDataHelper
    */
    static deleteTempDataKey(softlist<auto> list) {
%ifdef QorusServer
        SM.deleteTempDataKey(list);
%endif
    }

    #! Updates or creates the values of one or more keys in the workflow order's sensitive data hash for the given sensitive data key and value
    /** @par Example:
        @code{.py}
WorkflowApi::updateSensitiveData("personal_id", h.person.personal_id, h, h.("tax_number",));
        @endcode

        @param skey the type of value provided in \a svalue; must not be longer than 100 bytes long or a \c SENSITIVE-DATA-ERROR exception is raised
        @param svalue the value of the sensitive data key identified by \a skey; if this string is empty or longer than 100 bytes, a \c SENSITIVE-DATA-ERROR exception is raised
        @param hash the data to create or update against \a skey; existing keys will be replaced; new keys will be added; if the new hash does not refer to existing keys, then those existing keys remain untouched
        @param aliases other values for the sensitive data
        @param meta optional sensitve data metadata with the following recommended keys:
        - \c PURPOSE: free-form information about the purpose of the sensitive data
        - \c CATEGORIES: free-form information about the categories of sensitive data
        - \c RECIPIENTS: free-form information about the recipients or recipient catories of sensitive data
        - \c STORAGE: free-form information about the storage time or rules for sensitive data

        @throw SENSITIVE-DATA-ERROR no sensitive key value was provided; sensitive key value too long (100 bytes maximum length in the encoding used by the system schema)

        @note
        - do not use sensitive data for the sensitive key names itself (\a skey); key names are logged to provide an audit trail of changes to sensitive data
        - metadata keys listed above for the \a meta argument are recommended for consistency's sake but are not checked; a hash with any keys can be stored with this API

        @see
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static updateSensitiveData(string skey, string svalue, hash<auto> hash, *softlist aliases, *hash<auto> meta) {
%ifdef QorusServer
        SM.updateSensitiveData(skey, svalue, hash, aliases, meta);
%endif
    }

    #! Updates or creates the values of one or more keys in the workflow order's sensitive data hash for the given sensitive data alias
    /** @par Example:
        @code{.py}
WorkflowApi::updateSensitiveDataFromAlias("0", h);
        @endcode

        @param alias the alias to use for updating the data; if the alias is unknown, an \c INVALID-ALIAS exception is raised
        @param hash the data to create or update against \a skey; existing keys will be replaced; new keys will be added; if the new hash does not refer to existing keys, then those existing keys remain untouched
        @param meta optional sensitve data metadata with the following recommended keys:
        - \c PURPOSE: free-form information about the purpose of the sensitive data
        - \c CATEGORIES: free-form information about the categories of sensitive data
        - \c RECIPIENTS: free-form information about the recipients or recipient catories of sensitive data
        - \c STORAGE: free-form information about the storage time or rules for sensitive data

        @throw INVALID-ALIAS the alias given is unknown

        @note
        - metadata keys listed above for the \a meta argument are recommended for consistency's sake but are not checked; a hash with any keys can be stored with this API

        @see
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static updateSensitiveDataFromAlias(string alias, hash<auto> hash, *hash<auto> meta) {
%ifdef QorusServer
        SM.updateSensitiveDataAlias(alias, hash, meta);
%endif
    }

    #! Returns the sensitive metadata hash for the given sensitive data key and value if present, otherwise returns an empty hash
    /** @par Example:
        @code{.py}
hash<auto> metadata = WorkflowApi::getSensitiveMetadata("personal_id", personal_id);
        @endcode

        @param skey the type of sensitive key provided in \a svalue
        @param svalue the value of the sensitive data key identified by \a skey

        @return the sensitive metadata hash stored according to the sensitive data key and value; if no such sensitive key and value exist for the order, or no metadata is present for the given sensitive key and value, then an empty hash is returned

        @note returns sensitive data; take care not to log any of the data returned by this method

        @see
        - @ref getSensitiveMetadataFromAlias()
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static auto getSensitiveMetadata(string skey, string svalue) {
%ifdef QorusServer
        return SM.getSensitiveMetadata(skey, svalue);
%endif
    }

    #! returns a hash with the corresponding sensitive data key and sensitive data value as well as the value of the sensitive metadata hash for the given sensitive data alias corresponding to a sensitive data key and value
    /** @par Example:
        @code{.py}
# get sensitive metadata
hash<auto> metadata = WorkflowApi::getSensitiveMetadataFromAlias("0").value;
        @endcode

        @param alias the alias to lookup; if the alias is unknown, an \c INVALID-ALIAS exception is raised

        @return a hash of information corresponding to the arguments; the hash returned has the following keys:
        - \c skey: (@ref string_type "string") the sensitive data key type
        - \c svalue: (@ref string_type "string") the sensitive data value (considered sensitive itself)
        - \c value: (@ref hash_type "hash") the value of the sensitive metadata hash, if any

        @throw INVALID-ALIAS the given alias is unknown

        @note returns sensitive data; take care not to log any of the sensitive data returned by this method

        @see
        - @ref getSensitiveMetadata()
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static hash getSensitiveMetadataFromAlias(string alias) {
%ifdef QorusServer
        return SM.getSensitiveMetadataAlias(alias);
%endif
    }

    #! Returns the sensitive data for the given sensitive data key and value
    /** @par Example:
        @code{.py}
string tax_number = WorkflowApi::getSensitiveData("personal_id", personal_id, "tax_number");
        @endcode

        @param skey the type of sensitive key provided in \a svalue
        @param svalue the value of the sensitive data key identified by \a skey
        @param ... any sensitive data keys for the given key and value

        @return the sensitive data according to the sensitive data key and value; if no such sensitive key and value
        exist for the order, then @ref nothing is returned; if no key arguments are present, then the entire hash is
        returned (if any), otherwise only the given key values are returned; if mutiple keys are given, then a hash is
        returned, if a single key is given, then only that key value is returned

        @note returns sensitive data; take care not to log any of the data returned by this method

        @see
        - @ref getSensitiveDataFromAlias()
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static auto getSensitiveData(string skey, string svalue) {
%ifdef QorusServer
        return SM.getSensitiveData(skey, svalue, argv);
%else
        delete argv;
%endif
    }

    #! Returns the sensitive data for the given sensitive data key and value
    /** @par Example:
        @code{.py}
string tax_number = WorkflowApi::getSensitiveDataArgs("personal_id", personal_id, "tax_number");
        @endcode

        @param skey the type of sensitive key provided in \a svalue
        @param svalue the value of the sensitive data key identified by \a skey
        @param keylist any sensitive data keys for the given key and value

        @return the sensitive data according to the sensitive data key and value; if no such sensitive key and value
        exist for the order, then @ref nothing is returned; if \a keylist is empty, then the entire hash is
        returned (if any), otherwise only the given key values are returned; if mutiple keys are given, then a hash is
        returned, if a single key is given, then only that key value is returned

        @note returns sensitive data; take care not to log any of the data returned by this method

        @see
        - @ref getSensitiveDataFromAlias()
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static auto getSensitiveDataArgs(string skey, string svalue, *list<auto> keylist) {
%ifdef QorusServer
        return SM.getSensitiveData(skey, svalue, keylist);
%endif
    }

    #! returns a hash with the corresponding sensitive data key and sensitive data value as well as the value of one or more keys in the @ref sensitive_data "workflow sensitive data" hash for the given sensitive data alias corresponding to a sensitive data key and value
    /** @par Example:
        @code{.py}
# get the tax number for the person
string tax_number = WorkflowApi::getSensitiveDataFromAlias("0", "tax_number").value;
        @endcode

        @param alias the alias to lookup; if the alias is unknown, an \c INVALID-ALIAS exception is raised
        @param ... zero or more string key fields to return

        @return a hash of information corresponding to the arguments; the hash returned has the following keys:
        - \c skey: (@ref string_type "string") the sensitive data key type
        - \c svalue: (@ref string_type "string") the sensitive data value
        - \c value: the value of the entire hash (if no arguments were requested), or a hash of the requested keys (if
          more than one key was requested), or the given value (if set, if one value is requested)

        @throw INVALID-ALIAS the given alias is unknown

        @note returns sensitive data; take care not to log any of the data returned by this method

        @see
        - @ref getSensitiveDataFromAliasArgs()
        - @ref getSensitiveData()
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static hash<auto> getSensitiveDataFromAlias(string alias) {
%ifdef QorusServer
        return SM.getSensitiveAlias(alias, argv);
%else
        delete argv;
%endif
    }

    #! returns a hash with the corresponding sensitive data key and sensitive data value as well as the value of one or more keys in the @ref sensitive_data "workflow sensitive data" hash for the given sensitive data alias corresponding to a sensitive data key and value
    /** @par Example:
        @code{.py}
# get the tax number for the person
string tax_number = WorkflowApi::getSensitiveDataFromAlias("0", "tax_number").value;
        @endcode

        @param alias the alias to lookup; if the alias is unknown, an \c INVALID-ALIAS exception is raised
        @param keylist zero or more string key fields to return

        @return a hash of information corresponding to the arguments; the hash returned has the following keys:
        - \c skey: (@ref string_type "string") the sensitive data key type
        - \c svalue: (@ref string_type "string") the sensitive data value
        - \c value: the value of the entire hash (if no arguments were requested), or a hash of the requested keys (if
          more than one key was requested), or the given value (if set, if one value is requested)

        @throw INVALID-ALIAS the given alias is unknown

        @note returns sensitive data; take care not to log any of the data returned by this method

        @see
        - @ref getSensitiveDataFromAlias()
        - @ref getSensitiveData()
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static hash<auto> getSensitiveDataFromAliasArgs(string alias, *list<auto> keylist) {
%ifdef QorusServer
        return SM.getSensitiveAlias(alias, keylist);
%endif
    }

    #! returns a hash of all sensitive data aliases for the current order or an empty hash if there are none
    /** @par Example:
        @code{.py}
hash<auto> ah = WorkflowApi::getSensitiveDataAliases();
        @endcode

        @return a hash of all sensitive data aliases for the current order or an empty hash if there are none, otherwise keys are alias names and values are hashes with the following keys:
        - \c skey: (@ref string_type "string") the sensitive data key type
        - \c svalue: (@ref string_type "string") the sensitive data value (considered sensitive itself)

        @note returns sensitive data; sensitive data values (\a svalue) should not be logged

        @see
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static hash<auto> getSensitiveDataAliases() {
%ifdef QorusServer
        return SM.getSensitiveAliases();
%endif
    }

    #! Deletes the sensitive data hash for the given sensitive data key and value; changes have already been committed to the database when this method returns
    /** @par Example:
        @code{.py}
WorkflowApi::deleteSensitiveData("personal_id", personal_id);
        @endcode

        @param skey the type of sensitive key provided in \a svalue
        @param svalue the value of the sensitive data key identified by \a skey

        @return @ref True "True" if the data existed and was deleted, @ref False "False" if no such sensitive data key and value were present in the order

        @note the use of this method causes SQL I/O to be performed in the system schema; to maximize performance, calls to this and other similar methods should be minimized if possible

        @see
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static bool deleteSensitiveData(string skey, string svalue) {
%ifdef QorusServer
        return SM.deleteSensitiveData(skey, svalue);
%endif
    }

    #! Deletes one or more keys from the workflow order data instance’s sensitive data hash for the given sensitive data key and value; changes have already been committed to the database when this method returns
    /** @par Example:
        @code{.py}
# delete the "tax_number" and "insurance_number" keys from the sensitive data hash for the given person
WorkflowApi::deleteSensitiveDataKey("personal_id", personal_id, ("tax_number", "insurance_number"));
        @endcode

        Changes are committed to the database before the method returns.

        @param skey the type of sensitive key provided in \a svalue
        @param svalue the value of the sensitive data key identified by \a skey
        @param list a single key or a list of keys to delete in the workflow order's sensitive data hash for the given sensitive key-value pair

        @return @ref True "True" if the data existed and was deleted, @ref False "False" if no data was deleted

        @note the use of this method causes SQL I/O to be performed in the system schema; to maximize performance, calls to this and other similar methods should be minimized if possible

        @see
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static bool deleteSensitiveDataKey(string skey, string svalue, softlist<auto> list) {
%ifdef QorusServer
        return SM.deleteSensitiveDataKey(skey, svalue, list);
%endif
    }

    #! Returns a hash of sensitive data keys and values saved against the order; the sensitive data hashes themselves are not returned, just the information used to index sensitive data against the order
    /** @par Example:
        @code{.py}
*hash<auto> h = WorkflowApi::getSensitiveDataKeyValues();
        @endcode

        @return a hash of sensitive data keys and values saved against the order; the sensitive data hashes themselves are not returned, just the information used to index sensitive data against the order; if no sensitive data is stored against the order, an empty hash is returned

        @note returns sensitive data; sensitive data values should not be logged

        @see
        - @ref sensitive_data
        - @ref SensitiveDataHelper
    */
    static hash getSensitiveDataKeyValues() {
%ifdef QorusServer
        return SM.getSensitiveDataKeyValues();
%endif
    }

    #! Updates the values of one or more keys in the workflow execution instance’s instance data hash
    /** @param hash the key-value pairs to update in workflow execution instance data

        @see
        - @ref instancedata "Workflow Execution Instance Data"
    */
    static updateInstanceData(hash<auto> hash) {
%ifdef QorusServer
        Qorus.control.execHash.(tld.index).updateInstanceData(hash);
%endif
    }

    #! Deletes a single key or a list of keys from the workflow execution instance’s instance data hash
    /** @param list a single key or a list of strings (keys) to delete in workflow execution instance data

        @see
        - @ref instancedata "Workflow Execution Instance Data"
    */
    static deleteInstanceDataKey(softlist<auto> list) {
%ifdef QorusServer
        Qorus.control.execHash.(tld.index).deleteInstanceDataKey(list);
%endif
    }

    #! Retrieves the values of one or more keys from the workflow execution instance’s instance data hash
    /** This data is set by the user (by calling updateInstanceData()) and is not associated to the order data
        being processed, but rather directly with the workflow execution instance.  In this sense, this data is
        similar to global variables in a program.

        Pass a single string argument, in which case the value of that key is returned, or a list of strings, in
        which case a hash is returned giving the values of all the keys requested.

        @return a single value or hash of @ref instancedata "workflow execution instance data", depending on the
        argument(s)

        @note not to be confused with getWorkflowInstanceData(), which returns system properties of the workflow
        execution instance

        @see
        - getInstanceDataArgs()
        - @ref instancedata "Workflow Execution Instance Data"
    */
    static auto getInstanceData() {
%ifdef QorusServer
        return Qorus.control.execHash.(tld.index).getInstanceData(argv);
%else
        delete argv;
%endif
    }

    #! Retrieves the values of one or more keys from the workflow execution instance’s instance data hash
    /** This data is set by the user (by calling updateInstanceData()) and is not associated to the order data
        being processed, but rather directly with the workflow execution instance.  In this sense, this data is
        similar to global variables in a program.

        Pass a single string argument, in which case the value of that key is returned, or a list of strings, in
        which case a hash is returned giving the values of all the keys requested.

        @return a single value or hash of @ref instancedata "workflow execution instance data", depending on the
        argument(s)

        @note not to be confused with getWorkflowInstanceData(), which returns system properties of the workflow
        execution instance

        @see
        - getInstanceData()
        - @ref instancedata "Workflow Execution Instance Data"
    */
    static auto getInstanceDataArgs(*list<auto> keylist) {
%ifdef QorusServer
        return Qorus.control.execHash.(tld.index).getInstanceData(keylist);
%endif
    }

    #! Retrieves the value of a single key (system-defined property) from the workflow execution instance object itself
    /** @param field the workflow execution instance key; see
        @ref workflowexecutioninstanceinfo "Running Workflow Execution Instance Properties" for valid keys

        @return the value of the key in the current workflow execution instance

        @note not to be confused with getInstanceData()

        @see
        - parentWfiid()
        - getWfiid()
    */
    static auto getWorkflowInstanceData(string field) {
%ifdef QorusServer
        return Qorus.control.execHash.(tld.index).getWorkflowInstanceData(field);
%endif
    }

    #! Retrieves the values of multiple keys (system-defined properties) from the workflow execution instance object itself
    /** Pass a list of string keys, in which case a hash is returned giving the values of all the keys requested; see
        @ref workflowexecutioninstanceinfo "Running Workflow Execution Instance Properties" for valid keys; if no
        arguments are passed, then a hash of all possible keys is returned

        @return a hash of key-value pairs giving the value of the given keys in the current workflow execution instance

        @throw GET-WORKFLOW-INSTANCE-DATA-ERROR invalid arguments to method

        @note not to be confused with getInstanceData()

        @see
        - getWorkflowInstanceDataArgs()
        - parentWfiid()
        - getWfiid()
    */
    static hash<auto> getWorkflowInstanceData() {
%ifdef QorusServer
        if (elements argv == 1) {
            throw "GET-WORKFLOW-INSTANCE-DATA-ERROR",
                sprintf("getWorkflowInstanceData() expects either a list of strings or a single string argument; single argument passed of type '%s'",
                    type(argv[0]));
        }
        return Qorus.control.execHash.(tld.index).getWorkflowInstanceData(argv);
%else
        delete argv;
%endif
    }

    #! Retrieves the values of one or more keys (system-defined properties) from the workflow execution instance object itself as a hash
    /** @param keylist a list of string keys; see
        @ref workflowexecutioninstanceinfo "Running Workflow Execution Instance Properties" for valid keys; if no
        arguments are passed, then a hash of all possible keys is returned

        @return a hash of key-value pairs giving the value of the given keys in the current workflow execution
        instance

        @throw GET-WORKFLOW-INSTANCE-DATA-ERROR invalid arguments to method

        @note not to be confused with getInstanceData()

        @see
        - getWorkflowInstanceData()
        - parentWfiid()
        - getWfiid()
    */
    static hash<auto> getWorkflowInstanceDataArgs(*list<auto> keylist) {
%ifdef QorusServer
        return keylist.size() == 1
            ? Qorus.control.execHash.(tld.index).getWorkflowInstanceData(keylist[0])
            : Qorus.control.execHash.(tld.index).getWorkflowInstanceData(keylist);
%endif
    }

    #! This method sets user-defined order keys against an order, so that the workflow order data instance can be quickly searched and retrieved using the key value
    /** The hash provided replaces orders keys on the workflow order; existing order keys matching keys given in the
        hash provided as an argument to this method are replaced and any new keys in the hash are added.

        The data is committed to the database before the method returns.

        @param h key-value pairs to set for order keys; the keys in this hash must match those defined for the
        workflow
        @param truncate allow key values to be truncated without an error

        @throw SET-ORDER-KEYS-ERROR empty hash passed to setOrderKeys()
        @throw INVALID-WORKFLOW-KEY invalid key for workflow
        @throw DUPLICATE-KEY-VALUE an order key was assigned a value more than once

        @note the use of this method causes SQL I/O to be performed in the system schema; to maximize performance,
        calls to this and other similar methods should be minimized if possible

        @see
        - setOrderKey()
        - appendOrderKeys()
    */
    static setOrderKeys(hash<auto> h, bool truncate = False) {
%ifdef QorusServer
        SM.setOrderKeys(h, truncate);
%endif
    }

    #! This method sets the values for a sinle user-defined order key against an order, so that the workflow order data instance can be quickly searched and retrieved using the key value
    /** The value provided replaces any order key value on the workflow order

        The data is committed to the database before the method returns.

        @param key the workflow key to set; must be a valid workflow key
        @param value one or more values for the workflow key
        @param truncate allow key values to be truncated without an error

        @throw INVALID-WORKFLOW-KEY invalid key for workflow
        @throw DUPLICATE-KEY-VALUE an order key was assigned a value more than once

        @note the use of this method causes SQL I/O to be performed in the system schema; to maximize performance,
        calls to this and other similar methods should be minimized if possible

        @see
        - appendOrderKeys()
        - getOrderKeys()
        - setOrderKeys()
    */
    static setOrderKey(string key, softlist<softstring> value, bool truncate = False) {
%ifdef QorusServer
        SM.setOrderKeys({key: value}, truncate);
%endif
    }

    #! This method appends user-defined order key values to a workflow order key, so that the workflow order data instance can be quickly searched and retrieved using the key value
    /** The hash provided appends orders keys to the workflow order; existing order keys matching keys given in the hash provided as an argument to this method are updated and any new keys are added.

        The data is committed to the database before the method returns.

        @param h key-value pairs to append to workflow order keys; the keys in this hash must match those defined for the workflow
        @param truncate allow key values to be truncated without an error

        @throw APPEND-ORDER-KEYS-ERROR empty hash passed to appendOrderKeys()
        @throw INVALID-WORKFLOW-KEY invalid key for workflow
        @throw SET-ORDER-KEYS-ERROR an invalid data type (not convertible to a string) was given as a key value

        @note the use of this method causes SQL I/O to be performed in the system schema; to maximize performance, calls to this and other similar methods should be minimized if possible

        @see
        - setOrderKeys()
        - setOrderKey()
        - getOrderKeys()
    */
    static appendOrderKeys(hash<auto> h, bool truncate = False) {
%ifdef QorusServer
        SM.appendOrderKeys(h, truncate);
%endif
    }

    #! This method appends user-defined order key values to a workflow order key, so that the workflow order data instance can be quickly searched and retrieved using the key value
    /** This method appends order keys to the workflow order; existing order keys matching keys given in the
        arguments provided are updated and any new keys are added.

        The data is committed to the database before the method returns.

        @param key the workflow order key to append to; this key must match a defined workflow order key
        @param value one or more values to append for the given key
        @param truncate allow key values to be truncated without an error

        @throw APPEND-ORDER-KEYS-ERROR empty hash passed to appendOrderKeys()
        @throw INVALID-WORKFLOW-KEY invalid key for workflow
        @throw DUPLICATE-KEY-VALUE an order key was assigned a value more than once

        @note the use of this method causes SQL I/O to be performed in the system schema; to maximize performance,
        calls to this and other similar methods should be minimized if possible

        @see
        - setOrderKeys()
        - getOrderKeys()
    */
    static appendOrderKeys(string key, softlist<softstring> value, bool truncate = False) {
%ifdef QorusServer
        SM.appendOrderKeys((key: value), truncate);
%endif
    }

    #! This method retrieves the user-defined order key information saved against the workflow order data instance
    /** Pass a single string argument, in which case the value of that key is returned, or a list of strings, in which case a hash is returned giving the values of all the keys requested.  Pass @ref nothing to the method to get a hash of all keys (if any are set).
    */
    static auto getOrderKeys() {
%ifdef QorusServer
        return SM.getOrderKeys(argv);
%else
        delete argv;
%endif
    }

    #! This method retrieves the user-defined order key information saved against the workflow order data instance
    /** @param keylist for a single string argument, te value of that key is returned, for a list of strings, a hash
        is returned giving the values of all the keys requested.  Pass @ref nothing to the method to get a hash of
        all keys (if any are set).
    */
    static auto getOrderKeysArgs(*softlist<auto> keylist) {
%ifdef QorusServer
        return SM.getOrderKeys(keylist);
%endif
    }

    #! This method returns True if the step passed has been executed and has status @ref OMQ::StatComplete (\c "C")
    /** If the step name does not exist then an exception is thrown

        @return True if the step passed has been executed and has status @ref OMQ::StatComplete (\c "C")
    */
    static bool stepExecuted(string stepname) {
%ifdef QorusServer
        return tld.wfe.getStepStatus(stepname) == OMQ::StatComplete;
%endif
    }

    #! Returns the current status of the given step for the current workflow order instance
    /** If the step name does not exist then an exception is thrown

        @return the current status of the given step for the current workflow order instance
    */
    static *string getStepStatus(string stepname) {
%ifdef QorusServer
        return tld.wfe.getStepStatus(stepname);
%endif
    }

    #! This method will return a hash of step information for the current step
    /**
        @return if not called from a step; returns @ref nothing, otherwise returns a hash with the following members:
        - \c stepid: the ID of the step
        - \c name: the name of the step
        - [\c patch]: the patch string for the step
        - [\c desc]: the description of the step
        - \c version: the version of the step
        - \c steptype: @ref OMQ::ExecNormal, @ref OMQ::ExecSubWorkflow, or @ref OMQ::ExecAsync
        - \c arraytype: either @ref OMQ::ArraySeries or @ref OMQ::ArrayNone for non-array steps
        - \c index: the element number for @ref arraysteps "array steps" (always 0 for non-array steps)
        - [\c array_size]: the number of elements in the array for @ref arraysteps "array steps"
        - [\c array_element]: the current array element, if executing an @ref arraysteps "array step"
        - [\c stepstatus]: the previous step status when called from a workflow execution instance run in
          @ref OMQ::WM_Recovery mode
        - [\c retries]: the current retry number when called from a workflow execution instance run in
          @ref OMQ::WM_Recovery mode
        - [\c step_sourceid]: the class ID of the step's class for @ref step_source "class-based steps"; either this
          value or \c stepfunction_instanceid will be returned
        - [\c stepfunction_instanceid]: the function instance ID of the primary step function for
          @ref dep_funcstepdefs "function-based steps"
        - [\c sfname]: the name of the primary step function for @ref dep_funcstepdefs "function-based steps"
        - [\c validationfunction_instanceid]: the function instance ID of the validation function for
          @ref dep_funcstepdefs "function-based steps"
        - [\c vfname]: the name of the validation function (corresponds to \c validationfunction_instanceid) for
          @ref dep_funcstepdefs "function-based steps"
        - [\c endfunction_instanceid]: the function instance ID of the asynchronous end function for asynchronous
          steps for @ref dep_funcstepdefs "function-based" @ref asyncsteps "asynchronous steps"
        - [\c efname]: the name of the end function (corresponds to \c endfunction_instanceid) for
          @ref dep_funcstepdefs "function-based" @ref asyncsteps "asynchronous steps"
        - [\c arrayfunction_instanceid]: the function instance ID of the array function for
          @ref dep_funcstepdefs "function-based" @ref arraysteps "array steps"
        - [\c afname]: the name of the array function (corresponds to \c arrayfunction_instanceid) for
          @ref dep_funcstepdefs "function-based" @ref arraysteps "array steps"
        - [\c queueid]: the ID of the asynchronous queue for asynchronous steps for @ref dep_funcstepdefs "function-based"
          @ref asyncsteps "asynchronous steps"
        - [\c queuename]: the name of the asynchronous queue (corresponds to \c queueid) for
          @ref dep_funcstepdefs "function-based" @ref asyncsteps "asynchronous steps"
        - [\c workflow_event_typeid]: the event type ID for workflow synchronization event steps for
          @ref eventsteps "workflow synchronization event steps"
        - [\c eventtype]: the name of the event type (corresponds to \c workflow_event_typeid) for
          @ref eventsteps "workflow synchronization event steps"
    */
    static *hash<auto> getStepInfo() {
%ifdef QorusServer
        return Qorus.control.execHash.(tld.index).getStepInfo();
%endif
    }

    #! returns workflow metadata for the currently running workflow as a hash
    /** @return a hash of workflow metadata; see @ref workflowmetadata for the hash description
    */
    static hash<auto> getWorkflowMetadata() {
%ifdef QorusServer
        *Workflow wf = Qorus.control.execHash{tld.index}.wf;
        if (!exists wf && exists tld._wf) {
            wf = tld._wf;
        }
        # return only documented attributes
        return wf{
            "name",
            "version",
            "patch",
            "workflowid",
            "remote",
            "description",
            "cached",
            "errorfunction_instanceid",
            "attach_func_instanceid",
            "detach_func_instanceid",
            "onetimeinit_func_instanceid",
            "errhandler_func_instanceid",
            "keylist",
            "options",
        };
%endif
    }

    #! set the current workflow order status to @ref OMQ::StatBlocked, can only be called from the @ref attach "attach function"
    /** Processing of the workflow order will stop after this call; in order to be further processed the workflow order must be unblocked

        @throw BLOCK-ERROR method not called from @ref attach "attach function"

        @note This method can only be called in the @ref attach "attach function" of the workflow; if called from any other code, an exception will result.
    */
    static setBlocked() {
%ifdef QorusServer
        SM.setBlocked();
%endif
    }

    #! Get @ref order_instance_notes
    /** @param count an optional integer to limit the list size

        @return list of hashes of @ref order_instance_notes

        @see
        - addOrderNote()
    */
    static list getOrderNotes(*int count) {
%ifdef QorusServer
        return SM.getOrderInstanceNotes(tld.wfe.workflow_instanceid, count);
%endif
    }

    #! Add new note as described in @ref order_instance_notes
    /** @param notestr a string with note

        @see
        - getOrderNotes()
    */
    static addOrderNote(string notestr) {
%ifdef QorusServer
        SM.setOrderInstanceNoteIntern(tld.wfe.workflow_instanceid, ("note" : notestr));
%endif
    }

    #! Sets a user-defined custom status for the current step
    /** The custom status is also propagatef to the segment and workflow order data instances. The status is reset when the step is updated subsequently.  The value of the custom status is only used for display purposes; it does not affect Qorus’ internal behavior at all.

        @param stat the custom user-defined status to set for the step

        @throw CUSTOM-STATUS-ERROR this exception is thrown if this method is called outside of step code

        @note The custom status must be a single character
    */
    static setCustomStatus(string stat) {
%ifdef QorusServer
        if (!tld.stepID)
            throw "CUSTOM-STATUS-ERROR", "WorkflowApi::setCustomStatus() can only be called in step code";
        SM.setCustomStatus(tld.wfe.workflow_instanceid, tld.stepID, stat);
%endif
    }

    #! reschedules the current workflow order instance for later processing
    /** Can only be called in the @ref attach "attach function"; calling anywhere else will cause an exception to be raised.
        Can only be called when the workflow order has status @ref OMQ::StatReady or @ref OMQ::StatScheduled; otherwise an exception will be raised.

        @param scheduled If the date is ealier than the current time; then this call is ignored

        @throw RESCHEDULE-ERROR method not called from the @ref attach "attach function"; order data does not have @ref OMQ::StatReady or @ref OMQ::StatScheduled status

        @note The scheduled date can be changed or cleared by calling the system API method omq.system.reschedule-order()
    */
    static rescheduleOrder(date scheduled) {
%ifdef QorusServer
        SM.rescheduleOrder(scheduled);
%endif
    }

    #! changes the order priority for the current workflow order instance
    /** @param prio must be an integer >= 0 and <= 999

        @note The order priority can be changed externally by calling the system API method omq.system.reprioritize-order()
    */
    static reprioritizeOrder(int prio) {
%ifdef QorusServer
        SM.reprioritizeOrder(prio);
%endif
    }

    #! leaves feedback for a parent workflow
    /** When this call returns, the feedback data has already been committed to the database.

        @param key the key name for the feedback in the parent workflow
        @param value the value of the key

        @throw FEEDBACK-ERROR the current workflow is not a subworkflow; value is @ref nothing or an error occurred accessing the parent workflow order
        @throw SESSION-ERROR the parent workflow order is being processed by another Qorus session
        @throw STATUS-ERROR the parent workflow order is already COMPLETE or CANCELED and cannot be updated

        The parent workflow should then call getChildFeedback() to get the feedback data left by the child workflow.

        @note The use of this method causes SQL I/O to be performed in the system schema; to maximize performance, calls to this and other similar methods should be minimized if possible

        @see
        - @ref subworkflowsteps
        - getChildFeedback()
    */
    static leaveParentFeedback(string key, auto value) {
%ifdef QorusHasWfApi
        *softstring pwfiid = tld.wfe.parent_info.parent_workflow_instanceid;
        if (!pwfiid)
            throw "FEEDBACK-ERROR", sprintf("the current workflow order %d has no parent order to give feedback to", tld.wfe.workflow_instanceid);

        if (!exists value)
            throw "FEEDBACK-ERROR", sprintf("feedback from child workflow_instanceid %d for parent order %d with key %y has no value", tld.wfe.workflow_instanceid, pwfiid, key);

        SM.leaveFeedback(pwfiid, key, value);
        QDBG_LOG("WorkflowApi::leaveParentFeedback() pwfiid %y index %y wfe %y", pwfiid, tld.index, tld.wfe);
%endif
    }

    #! gets feedback from a child workflow order with the given key
    /** the child workflow has to set a value with the given key first with leaveParentFeedback() for any value to be returned with this method call

        @param key the feedback key name used by the child workflow

        @return the value of the feedback saved by the child workflow order with leaveParentFeedback() under the given key

        @see
        - @ref subworkflowsteps
        - leaveParentFeedback()
    */
    static auto getChildFeedback(string key) {
%ifdef QorusServer
        return tld.wfe.getFeedback(key);
%endif
    }

    #! gets all feedback from all child workflow orders as a hash
    /** child workflows have to set feedback values with leaveParentFeedback() for any value to be returned with this method call

        @return a hash representing all feedback values saved by child workflow orders with leaveParentFeedback()

        @see
        - @ref subworkflowsteps
        - leaveParentFeedback()
    */
    static *hash<auto> getChildFeedback() {
%ifdef QorusServer
        return tld.wfe.getFeedback();
%endif
    }

    #! Changes option values on a workflow
    /** If the workflow has defined workflow options, and at least one invalid option is passed to
        the method, an exception will be raised; however all other valid options in the hash will be set before the
        exception is raised

        @param hash a hash of option-value pairs

        @throw WORKFLOW-OPTION-ERROR invalid option name

        @see
        - set_option()
        - getOption()
        - getOptionArgs()
    */
    static setOption(hash<auto> hash) {
%ifdef QorusServer
        Qorus.control.execHash.(tld.index).setOption(hash);
%endif
    }

    #! Changes a single option value on a workflow
    /** If the workflow has defined workflow options and an invalid option is passed to the method, an exception will
        be raised.

        @param option the option to set
        @param value the value to set for the option

        @throw WORKFLOW-OPTION-ERROR invalid option name

        @see
        - set_option()
        - getOption()
        - getOptionArgs()
    */
    static setOption(string option, auto value) {
        WorkflowApi::setOption({option: value});
    }

    #! Returns the value of the named workflow option(s)
    /** If the option is not set on the workflow level, and it is a valid system option, then the value of the system
        option will be returned.

        @return the value requested directly if only one argument is passed, otherwise a hash of option keys and
        values; note that if no arguments are passed to the method all workflow-level options are returned as a hash

        @note Invalid options do not cause an errors to be raised; the associated key
        values in the hash returned will be NOTHING

        @see
        - get_option()
        - getOptionArgs()
        - setOption()
    */
    static auto getOption() {
%ifdef QorusServer
        return Qorus.control.execHash.(tld.index).getOption(argv);
%endif
    }

    #! Returns the value of the named workflow option or options
    /** If the option is not set on the workflow, and it is a valid system option, then the value of the system
        option will be returned.

        @param args the list of options to return

        @return the value requested directly if only one argument is passed, otherwise a hash of option keys and
        values; note that if no arguments are passed to the method all workflow-level options are returned as a hash

        @note When called from workflow code, invalid options do not cause an errors to be raised; the associated key
        values in the hash returned will be NOTHING

        @see
        - getOption()
        - setOption()
    */
    static auto getOptionArgs(*softlist<string> args) {
%ifdef QorusServer
        return Qorus.control.execHash.(tld.index).getOption(args);
%endif
    }

    #! Returns the parent workflow order data instance ID from a subworkflow or @ref nothing if the current workflow order is not a subworkflow and therefore has no parent
    /** @return the parent workflow order data instance ID of a subworkflow or @ref nothing if the current workflow
        order is not a subworkflow

        @see
        - getWorkflowInstanceData()
        - getWfiid()
    */
    static *softint parentWfiid() {
%ifdef QorusServer
        return tld.wfe.parent_info.parent_workflow_instanceid;
%endif
    }

    #! returns the current workflow_instanceid as an integer; returns @ref nothing if not called in a workflow order context (ex: @ref onetimeinit "onetimeinit function", etc)
    /**
        @return the current workflow_instanceid as an integer; returns @ref nothing if not called in a workflow order
        context (ex: @ref onetimeinit "onetimeinit function", etc)

        @see
        - parentWfiid()
        - getWorkflowInstanceData()
        - getWfiid()
    */
    static *softint getWfiid() {
%ifdef QorusServer
        return tld.wfe.workflow_instanceid;
%endif
    }

    #! puts the current thread to sleep for a certain number of seconds
    /**
        If the workflow is stopping, this method returns immediately with a
        return value of -1; otherwise the current thread is put to sleep for the full time period requested.  If this
        method (or usleep()) is called again after -1 is returned, then a \c "STOP-ERROR" exception is thrown.

        @param arg the number of seconds to sleep

        @return 0 if current thread was put to sleep for the full time period; -1 if the sleep was interrupted because
        the current object is being stopped

        @throw STOP-ERROR the current object is stopping and this method already returned -1 as a warning

        @see
        - omqsleep()
        - usleep()
    */
    static int sleep(softint arg) {
%ifdef QorusServer
        return workflow_sleep(arg);
%endif
    }

    #! puts the current thread to sleep for a certain number of microseconds
    /**
        If the workflow is stopping, this method returns immediately with a return
        value of -1; otherwise the current thread is put to sleep for the full time period requested.  If this method
        (or sleep()) is called again after -1 is returned, then a \c "STOP-ERROR" exception is thrown.

        @param arg the number of microseconds to sleep (1 microsecond = 1/1000000 of a second)

        @return 0 if current thread was put to sleep for the full time period; -1 if the sleep was interrupted because
        the current object is being stopped

        @throw STOP-ERROR the current object is stopping and this method already returned -1 as a warning

        @see
        - omqusleep()
        - sleep()
    */
    static int usleep(softint arg) {
%ifdef QorusServer
        return workflow_usleep(arg);
%endif
    }

    #! puts the current thread to sleep for a certain number of microseconds
    /**
        If the workflow is stopping, this method returns immediately with a return
        value of -1; otherwise the current thread is put to sleep for the full time period requested.  If this method
        (or sleep()) is called again after -1 is returned, then a \c "STOP-ERROR" exception is thrown.

        @param arg the amount of time in microseconds to sleep (1 microsecond = 1/1000000 of a second)

        @return 0 if current thread was put to sleep for the full time period; -1 if the sleep was interrupted because
        the current object is being stopped

        @throw STOP-ERROR the current object is stopping and this method already returned -1 as a warning

        @see
        - omqusleep()
        - sleep()
    */
    static int usleep(date arg) {
%ifdef QorusServer
        return workflow_sleep(get_duration_microseconds(arg));
%endif
    }

    #! returns the value of the given step configuration item
    /** @par Example:
        @code{.py}
auto val = WorkflowApi::getConfigItemValue(item);
        @endcode

        @param item the name of the step configuration item; step configuration item values
        take precedence over values on workflow level. Values on workflow level take precedence over
        values on global level. If there is no value on the previous levels then the default value is returned.
        @param local_context the caller can supply its "local" context for template variables (plus user context info is
        added - see the @ref OMQ::UserApi::UserApi::getUserContextInfo() "UserApi::getUserContextInfo()" method)
        @param expand_complex_values if @ref True then lists and hashes will have their string values expanded
        recursively

        @return the value of the given configuration item

        @throw CONFIG-ITEM-ERROR thrown if the configuration item is not valid

        @note Any global configuration item declared for any step in a workflow can be accessed in any other step in
        that workflow regardless of whether the step declared the global configuration item or not.

        @note the value is always substituted with
        @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure and escape any \c "$"
        characters with a backslash (\c "\") to avoid template substitution

        @since
        - Qorus 4.1.1 added the \a expand_complex_values parameter

        @see
        - @ref step_config_items
        - getConfigItemHash()
    */
    static auto getConfigItemValue(string item, *hash<auto> local_context, bool expand_complex_values = True) {
%ifdef QorusHasWfApi
        return WFEntry::getConfigItemValue(item, local_context, expand_complex_values);
%endif
    }

    #! returns a hash of all configuration items for the current step
    /** @par Example:
        @code{.py}
hash<auto> config = WorkflowApi::getConfigItemHash();
        @endcode

        @param local_context the caller can supply its "local" context for template variables (plus user context info is
                             added - see @ref UserApi::getUserContextInfo() method)

        @return a hash of all configuration items for the current step; keys are config item names; values are
        config item values. If there are no config items for the current step, then an empty hash is returned.

        @note if there are local configuration item values and values on workflow or global level, the
        local values will take precedence over the workflow values and the workflow values will take precedence
        over the global values.

        @note values are always substituted with
        @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure and escape any \c "$"
        characters with a backslash  (\c "\") to avoid template substitution

        @see @ref step_config_items
    */
    static hash<auto> getConfigItemHash(*hash<auto> local_context) {
%ifdef QorusServer
        return WFEntry::getConfigItemHash(local_context);
%endif
    }
}
