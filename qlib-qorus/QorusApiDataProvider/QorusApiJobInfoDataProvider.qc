# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiJobInfoDataProvider class definition

/** QorusApiJobInfoDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
*/

#! contains all public definitions in the QorusApiDataProvider module
public namespace QorusApiDataProvider {
#! The Qorus API data provider for the job info API
public class QorusApiJobInfoDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiJobInfoDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiJobInfoRequestDataType();

        #! Response type
        const ResponseType = new QorusApiJobInfoResponseDataType();
    }

    #! Returns the name of the data provider
    string getName() {
        return "info";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: return information about the given job";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        return UserApi::callRestApi("GET", "jobs/" + req.job);
    }

    #! Returns the description of a successful request message, if any
    /** @return the request type for this provider
    */
    private *AbstractDataProviderType getRequestTypeImpl() {
        return RequestType;
    }

    #! Returns the description of a response message, if this object represents a response message
    /** @return the response type for this response message
    */
    private *AbstractDataProviderType getResponseTypeImpl() {
        return ResponseType;
    }

    #! Returns data provider static info
    hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }
}

#! Data type for create order calls
public class QorusApiJobInfoRequestDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "job": {
                "type": JobType,
                "desc": "the job ID or name",
            },
        };
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            Fields.pairIterator();
    }
}

#! Data type for create order API responses
public class QorusApiJobInfoResponseDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = (
            "jobid": {
                "type": IntType,
                "desc": "The job ID",
            },
            "name": {
                "type": StringType,
                "desc": "The job name",
            },
            "description": {
                "type": StringOrNothingType,
                "desc": "The job description",
            },
            "version": {
                "type": StringType,
                "desc": "The job version",
            },
            "author": {
                "type": StringOrNothingType,
                "desc": "The job author",
            },
            "sessionid": {
                "type": IntType,
                "desc": "The application session that owns the job (0 = none)",
            },
            "remote": {
                "type": BoolType,
                "desc": "If the job runs in a remote qwf process or not",
            },
            "manual_remote": {
                "type": BoolType,
                "desc": "If the job remote status was set with the API or UI",
            },
            "open": {
                "type": BoolType,
                "desc": "If the job is running and has an open job session",
            },
            "run_skipped": {
                "type": BoolType,
                "desc": "If the job shouod be run immediately if Qorus is started and the last trigger time was "
                    "missed",
            },
            "enabled": {
                "type": BoolType,
                "desc": "If the job is enabled",
            },
            "code": {
                "type": StringType,
                "desc": "The source code for the job",
            },
            "class_based": {
                "type": BoolType,
                "desc": "If the job has a job class",
            },
            "class_name": {
                "type": StringOrNothingType,
                "desc": "The class name for class-based jobs",
            },
            "language": {
                "type": StringType,
                "desc": "The language any job-level code is written in",
            },
            "month": {
                "type": StringType,
                "desc": "The month portion of the job schedule",
            },
            "day": {
                "type": StringType,
                "desc": "The day portion of the job schedule",
            },
            "wday": {
                "type": StringType,
                "desc": "The wday portion of the job schedule",
            },
            "hour": {
                "type": StringType,
                "desc": "The hour portion of the job schedule",
            },
            "minute": {
                "type": StringType,
                "desc": "The minute portion of the job schedule",
            },
            "manually_updated": {
                "type": BoolType,
                "desc": "If the job schedule has been updated with the UI or API",
            },
            "created": {
                "type": DateType,
                "desc": "The creation timestamp for the job",
            },
            "modified": {
                "type": DateOrNothingType,
                "desc": "The modified timestamp for the job",
            },
            "source": {
                "type": StringOrNothingType,
                "desc": "The source of the job",
            },
            "line": {
                "type": StringOrNothingType,
                "desc": "The line number of the start of the job code in `source`",
            },
            "fsm_triggers": {
                "type": HashOrNothingType,
                "desc": "A hash of FSM triggers keyed by FSM name",
            },
            "mappers": {
                "type": ListOrNothingType,
                "desc": "A list of mappers associated to the job, if any",
            },
            "vmaps": {
                "type": ListOrNothingType,
                "desc": "A list of value maps associated to the job, if any",
            },
            "lib": {
                "type": HashOrNothingType,
                "desc": "A hash of library information (associated code and interface objects) for the job",
            },
            "tags": {
                "type": HashOrNothingType,
                "desc": "A hash of tags associated with the job",
            },
            "config": {
                "type": HashOrNothingType,
                "desc": "A hash of job-level config item information keyed by config item name, if any",
            },
            "next": {
                "type": DateOrNothingType,
                "desc": "The next trigger timestamp for the job",
            },
            "last_executed": {
                "type": DateOrNothingType,
                "desc": "The last executed timestamp for the job",
            },
            "groups": {
                "type": ListType,
                "desc": "A list of zero or more groups that the current job is specified in",
            },
            "offset": {
                "type": StringOrNothingType,
                "desc": "The line number offset of the start of the job code in `source`",
            },
            "host": {
                "type": StringOrNothingType,
                "desc": "The hostname of the system where the job was loaded from",
            },
            "user": {
                "type": StringOrNothingType,
                "desc": "The name of the OS user that loaded the job",
            },
            "base_class_name": {
                "type": StringOrNothingType,
                "desc": "The name of the base class for the job, if any",
            },
            "process": {
                "type": HashOrNothingType,
                "desc": "The process information hash, if any",
            },
            "connections": {
                "type": ListType,
                "desc": "A list of zero or more connections used by the job",
            },
            "alerts": {
                "type": ListType,
                "desc": "A list of zero or more alerts raised against the job",
            },
            "db_active": {
                "type": BoolType,
                "desc": "A flag indicating if the job is set as active in the DB or not",
            },
            "active": {
                "type": BoolType,
                "desc": "A flag indicating if the job is active or not",
            },
            "options": {
                "type": ListOrNothingType,
                "desc": "A list of job option hashes, if the job supports any",
            },
            "sched_type": {
                "type": StringType,
                "desc": "The type of job schedule",
            },
            "sched_text": {
                "type": StringType,
                "desc": "A descriptive string for the job schedule",
            },
            "state": {
                "type": HashOrNothingType,
                "desc": "A hash of job state date, if any",
            },
            "persistent-state": {
                "type": HashOrNothingType,
                "desc": "A hash of persistent job state date, if any",
            },
        );
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            Fields.pairIterator();
    }
}
}
