# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file JobApi.qc class-based job API

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

public namespace OMQ {
    public namespace UserApi {
        #! main job API namespace
        public namespace Job {}
    }
}

#! primary job API class
/** @note In %Python available as \c jobapi
*/
public class OMQ::UserApi::Job::JobApi inherits UserApi {
    #! raises an error in a running job; does not affect the flow of execution in the job code
    /** the error information is stored in the \c job_errors table with a severity of @ref OMQ::ES_Major and
        the business flag set to @ref True "True"

        @param err the error code
        @param desc_fmt the @ref string_formatting "format specifier" for the warning description string;
        following arguments will be included in the description string as combined with
        @ref Qore::vsprintf() "vsprintf()"

        @since %Qorus 3.1.0

        @see
        - errWithInfo()
        - warn()
        - warnWithInfo()
    */
    static err(string err, string desc_fmt) {
%ifdef QorusServer
        cast<OMQ::LocalQorusJob>(tld.job).raiseError(err, vsprintf(desc_fmt, argv), NOTHING, OMQ::ES_Major, True);
%else
        delete argv;
%endif
    }

    #! raises an error in a running job; does not affect the flow of execution in the job code
    /** the error information is stored to the \c job_errors table, errors errors with a severity less than or
        equal to @ref OMQ::ES_Warning are treated as warnings

        @param err the error code
        @param desc a description for the error
        @param info additional information to be saved with the error (data structures are serialized in YAML
        format and saved in the database)
        @param severity the severity of the error, errors with a severity less than or equal to
        @ref OMQ::ES_Warning are treated as warnings; see @ref ErrorSeverityCodes for valid values (default =
        @ref OMQ::ES_Major)
        @param business set to True if the error represents a business error

        @note If the severity is less than or equal to @ref OMQ::ES_Warning, the job instance
        does not get an @ref OMQ::JS_Error status

        @see
        - err()
        - warn()
        - warnWithInfo()
    */
    static errWithInfo(string err, softstring desc = "", auto info, softstring severity = OMQ::ES_Major,
        softbool business = False) {
%ifdef QorusServer
        cast<OMQ::LocalQorusJob>(tld.job).raiseError(err, desc, info, severity, business);
%endif
    }

    #! raises a warning in a running job; does not affect the flow of execution in the job code
    /** the warning information is stored to the \c job_errors table with a severity of @ref OMQ::ES_Warning
        and the business flag set to @ref True "True"

        @param err the warning or error code
        @param desc_fmt the @ref string_formatting "format specifier" for the warning description string;
        following arguments will be included in the description string as combined with
        @ref Qore::vsprintf() "vsprintf()"

        @see
        - warnWithInfo()
        - err()
        - errWithInfo()
    */
    static warn(string err, string desc_fmt) {
%ifdef QorusServer
        cast<OMQ::LocalQorusJob>(tld.job).raiseError(err, vsprintf(desc_fmt, argv), NOTHING, OMQ::ES_Warning, True);
%else
        delete argv;
%endif
    }

    #! raises a warning in a running job; does not affect the flow of execution in the job code
    /** the warning information is stored to the \c job_errors table with a severity of @ref OMQ::ES_Warning
        @param err the warning or error code
        @param desc a description for the warning
        @param info additional information to be saved with the warning (data structures are serialized in
        YAML format and saved in the database)
        @param business set to True if the warning represents a business warning

        @see
        - warn()
        - err()
        - errWithInfo()
    */
    static warnWithInfo(string err, softstring desc = "", auto info, softbool business = False) {
%ifdef QorusServer
        cast<OMQ::LocalQorusJob>(tld.job).raiseError(err, desc, info, OMQ::ES_Warning, business);
%endif
    }

    #! saves information against the job instance in the database
    /** The information is serialized in YAML format and saved in the database in the \c JOB_INSTANCE row as a
        part of the job results.

        This information is returned in the API as the \c info key in @ref rest_job_result_hash data,
        for example in the return value to the REST @ref rest_api_GET_latest_jobresults__id_ call.

        @param info the information to save

        @note the data stored here is different from the data returned by @ref getInfo()

        @see
        - getInfo()
    */
    static saveInfo(auto info) {
%ifdef QorusHasJobApi
        cast<OMQ::LocalQorusJob>(tld.job).saveInfo(info);
%endif
    }

    #! saves information against the job instance in the database
    /** @code{.py}
# will assign {"account": {"id": "123456ABC"}}
JobApi::saveInfoPath("account.id", "123456ABC");
        @endcode

        @param path the path to the data to save
        @param value the value to merge into existing info data at the given path

        The information is serialized in YAML format and saved in the database in the \c JOB_INSTANCE row as a
        part of the job results.

        This information is returned in the API as the \c info key in @ref rest_job_result_hash data,
        for example in the return value to the REST @ref rest_api_GET_latest_jobresults__id_ call.

        @note the data stored here is different from the data returned by @ref getInfo()

        @since Qorus 5.0

        @see
        - getInfo()
    */
    static saveInfoPath(string path, auto value) {
%ifdef QorusHasJobApi
        cast<OMQ::LocalQorusJob>(tld.job).saveInfoPath(path, value);
%endif
    }

    #! returns a hash of job information about the current job
    /** @return a hash with the following keys:
        - \c jobid: the metadata jobid of the job type
        - \c job_instanceid: the id of the job instance
        - \c name: the job name
        - \c version: the job version
        - \c description: the job description
        - \c trigger: a string describing the timer/trigger for the job
        - \c last_executed: the last executed date/time of the job (NOTHING if never executed before the
            current iteration)
        - \c last_executed_job_instanceid: the last executed instance id of the job
        - \c remote: the remote status of the job
        - \c next: the next trigger date/time

        @note the data returned here is different from the data stored by @ref saveInfo()

        @see
        - saveInfo()
    */
    static hash<auto> getInfo() {
%ifdef QorusHasJobApi
        return cast<OMQ::LocalQorusJob>(tld.job).getInfo();
%endif
    }

    #! returns any hash stored with a call to saveInfo()
    /** @return any hash stored with a call to saveInfo()

        @see
        - saveInfo()

        @since Qorus 5.0.10
    */
    static *hash<auto> getJobInfo() {
%ifdef QorusHasJobApi
        return cast<OMQ::LocalQorusJob>(tld.job).getJobInfo();
%endif
    }

    #! serializes the given hash and stores against the job's state data in \c JOB_STATE_DATA
    /** @param data the state data to serialize and store against the job's state data in \c JOB_STATE_DATA

        @note job state data is automatically cleared when a job instance gets a @ref OMQ::StatComplete
        status

        @see
        - saveStateDataPath()
        - getStateData()
        - svc_get_state_data()
        - @ref rest_api_GET_latest_jobs__id_or_name_
        - @ref rest_api_PUT_latest_jobs__id_or_name__setStateData

    */
    static saveStateData(hash<auto> data) {
%ifdef QorusHasJobApi
        cast<OMQ::LocalQorusJob>(tld.job).saveStateData(data);
%endif
    }

    #! serializes the given hash and stores against the job's state data in \c JOB_STATE_DATA
    /** @code{.py}
# will assign {"account": {"id": "123456ABC"}}
JobApi::saveStateDataPath("account.id", "123456ABC");
        @endcode

        @param path the path to the data to save
        @param value the value to merge into existing persistent state data at the given path

        @note job state data is automatically cleared when a job instance gets a @ref OMQ::StatComplete
        status

        @see
        - saveStateData()
        - getStateData()
        - svc_get_state_data()
        - @ref rest_api_GET_latest_jobs__id_or_name_
        - @ref rest_api_PUT_latest_jobs__id_or_name__setStateData

        @since Qorus 5.0
    */
    static saveStateDataPath(string path, auto value) {
%ifdef QorusHasJobApi
        cast<OMQ::LocalQorusJob>(tld.job).saveStateDataPath(path, value);
%endif
    }

    #! returns any job state data stored with saveStateData()
    /** @return any job state data stored with saveStateData()

        @note job state data is automatically cleared when a job instance gets a @ref OMQ::StatComplete
        status

        @see
        - saveStateData()
        - svc_save_state_data()
        - @ref rest_api_GET_latest_jobs__id_or_name_
        - @ref rest_api_PUT_latest_jobs__id_or_name__setStateData
    */
    static *hash<auto> getStateData() {
%ifdef QorusHasJobApi
        return cast<OMQ::LocalQorusJob>(tld.job).getStateData();
%endif
    }

    #! serializes the given hash and stores against the job's state data in \c JOB_PERSISTENT_STATE_DATA
    /** @param data the state data to serialize and store against the job's state data in \c JOB_PERSISTENT_STATE_DATA

        @note unlike job state data, job persistent state data is stored persistently across job runs

        @see
        - savePersistentStateDataPath()
        - getPersistentStateData()
        - clearPersistentStateData()

        @since Qorus 4.1.2
    */
    static savePersistentStateData(hash<auto> data) {
%ifdef QorusHasJobApi
        cast<OMQ::LocalQorusJob>(tld.job).savePersistentStateData(data);
%endif
    }

    #! serializes the given hash and stores against the job's state data in \c JOB_PERSISTENT_STATE_DATA
    /** @code{.py}
# will assign {"account": {"id": "123456ABC"}}
JobApi::savePersistentStateDataPath("account.id", "123456ABC");
        @endcode

        @param path the path to the data to save
        @param value the value to merge into existing persistent state data at the given path

        @note unlike job state data, job persistent state data is stored persistently across job runs

        @see
        - savePersistentStateData()
        - getPersistentStateData()
        - clearPersistentStateData()

        @since Qorus 5.0
    */
    static savePersistentStateDataPath(string path, auto value) {
%ifdef QorusHasJobApi
        cast<OMQ::LocalQorusJob>(tld.job).savePersistentStateDataPath(path, value);
%endif
    }

    #! clears the job's state data in \c JOB_PERSISTENT_STATE_DATA
    /** @note unlike job state data, job persistent state data is stored persistently across job runs

        @see
        - getPersistentStateData()
        - savePersistentStateData()

        @since Qorus 4.1.2
    */
    static clearPersistentStateData() {
%ifdef QorusHasJobApi
        cast<OMQ::LocalQorusJob>(tld.job).savePersistentStateData({});
%endif
    }

    #! returns any job state data stored with savePersistentStateData()
    /** @return any job state data stored with savePersistentStateData()

        @note unlike job state data, job persistent state data is stored persistently across job runs

        @see
        - savePersistentStateData()
        - clearPersistentStateData()

        @since Qorus 4.1.2
    */
    static *hash<auto> getPersistentStateData() {
%ifdef QorusHasJobApi
        return cast<OMQ::LocalQorusJob>(tld.job).getPersistentStateData();
%endif
    }

    #! sets a one-time custom trigger time for the job; returns @ref True if set, @ref False if ignored
    /** @param ts the timestamp to trigger the job; must be in the future and before the next trigger time

        @return @ref True if set, @ref False if ignored; the call will be ignored if the date/time value is in
        the past or after the next scheduled job trigger time

        @note when this API returns with a @ref True return value, the job's custom trigger time has already
        been committed to the database
    */
    static bool setTrigger(date ts) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusJob>(tld.job).setTrigger(ts);
%endif
    }

    #! Changes option values on a job
    /** If at least one invalid option is passed to the method, an exception will be raised; however all other valid
        options in the hash will be set before the exception is raised

        @param opts a hash of option-value pairs

        @throw JOB-OPTION-ERROR invalid option name

        @see
        - set_option()
        - getOption()
        - getOptionArgs()
    */
    static setOption(hash<auto> opts) {
%ifdef QorusServer
        cast<OMQ::LocalQorusJob>(tld.job).setOptions(opts);
%endif
    }

    #! Changes a single option value on a job
    /** If an invalid option is passed to the method, an exception will be raised.

        @param option the option to set
        @param value the value to set for the option

        @throw JOB-OPTION-ERROR invalid option name

        @see
        - set_option()
        - getOption()
        - getOptionArgs()
    */
    static setOption(string option, auto value) {
        JobApi::setOption({option: value});
    }

    #! Returns the value of the named job option(s)
    /** If the option is not set on the job level, and it is a valid system option, then the value of the system
        option will be returned.

        @return the value requested directly if only one argument is passed, otherwise a hash of option keys and
        values; note that if no arguments are passed to the method all job-level options are returned as a hash

        @note Invalid options do not cause an errors to be raised; the associated key
        values in the hash returned will be NOTHING

        @see
        - get_option()
        - getOptionArgs()
        - setOption()
    */
    static auto getOption() {
%ifdef QorusServer
        return cast<OMQ::LocalQorusJob>(tld.job).getOption(cast<*list<string>>(argv));
%else
        delete argv;
%endif
    }

    #! Returns the value of the named job option or options
    /** If the option is not set on the job, and it is a valid system option, then the value of the system
        option will be returned.

        @param args the list of options to return

        @return the value requested directly if only one argument is passed, otherwise a hash of option keys and
        values; note that if no arguments are passed to the method all job-level options are returned as a hash

        @note Invalid options do not cause an errors to be raised; the associated key
        values in the hash returned will be NOTHING

        @see
        - getOption()
        - setOption()
    */
    static auto getOptionArgs(*softlist<string> args) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusJob>(tld.job).getOption(args);
%endif
    }

    #! puts the current thread to sleep for a certain number of seconds
    /**
        If the job is stopping, this method returns immediately with a
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
        return cast<OMQ::LocalQorusJob>(tld.job).usleep(arg * 1000000);
%endif
    }

    #! puts the current thread to sleep for a certain number of microseconds
    /**
        If the job is stopping, this method returns immediately with a return
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
        return cast<OMQ::LocalQorusJob>(tld.job).usleep(arg);
%endif
    }

    #! puts the current thread to sleep for a certain number of microseconds
    /**
        If the job is stopping, this method returns immediately with a return
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
        return cast<OMQ::LocalQorusJob>(tld.job).usleep(get_duration_microseconds(arg));
%endif
    }

    #! returns the value of the given job configuration item
    /** @par Example:
        @code{.py}
auto val = JobApi::getConfigItemValue(item);
        @endcode

        @param item the name of the job configuration item; job configuration item values
        take precedence over values on global level if both are set otherwise if both are not set
        the default value is returned

        @param local_context the caller can supply its "local" context for template variables (plus user context info is
        added - see the @ref OMQ::UserApi::UserApi::getUserContextInfo() "UserApi::getUserContextInfo()" method)
        @param expand_complex_values if @ref True then lists and hashes will have their string values expanded
        recursively
        @return the value of the given configuration item

        @note values are always substituted with
        @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure and escape any \c "$"
        characters with a backslash  (\c "\") to avoid template substitution

        @throw CONFIG-ITEM-ERROR thrown if the configuration item is not valid

        @since
        - Qorus 4.1.1 added the \a expand_complex_values parameter

        @see @ref job_config_items
    */
    static auto getConfigItemValue(string item, *hash<auto> local_context, bool expand_complex_values = True) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusJob>(tld.job).getConfigItemValue(item, local_context, expand_complex_values);
%endif
    }

    #! returns a hash of all configuration items for the current job
    /** @par Example:
        @code{.py}
hash<auto> config = JobApi::getConfigItemHash();
        @endcode

        @param local_context the caller can supply its "local" context for template variables (plus user context info is
                             added - see @ref UserApi::getUserContextInfo() method)

        @return a hash of all configuration items for the current job; keys are config item names; values are
        config item values. If there are no config items for the current job, then an empty hash is returned.

        @note if there are local configuration item values and values on global level, the
        local values will take precedence over the global values

        @note values are always substituted with
        @ref OMQ::UserApi::UserApi::expandTemplatedValue() "UserApi::expandTemplatedValue()"; make sure and escape any \c "$"
        characters with a backslash  (\c "\") to avoid template substitution

        @see @ref job_config_items
    */
    static hash<auto> getConfigItemHash(*hash<auto> local_context) {
%ifdef QorusServer
        return cast<OMQ::LocalQorusJob>(tld.job).getConfigItemHash(local_context);
%endif
    }
}
