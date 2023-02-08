# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusJobContextDataType class definition

/** QorusJobContextDataType.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The data type for job contexts in Qorus
public class QorusJobContextDataType inherits HashDataType {
    #! Creates the type
    constructor() : HashDataType("job context hash") {
        addField(new QoreDataField("active", "the active flag (True for active jobs)", BoolType));
        addField(new QoreDataField("author", "the author if the job, if present", StringOrNothingType));
        addField(new QoreDataField("description", "the description of the job", StringOrNothingType));
        addField(new QoreDataField("expiry_date", "The date/time the job expires", DateOrNothingType));
        addField(new QoreDataField("groups", "a list of zero or more hashes for groups the job is a member of",
            new QoreListDataType(new Type("list<hash<auto>>"))));
        addField(new QoreDataField("job_instanceid", "The current job order data instance ID being processed",
            IntType));
        addField(new QoreDataField("jobid", "ID of the current job", IntType));
        addField(new QoreDataField("last_executed", "the last executed date/time of the job (no value if never "
            "executed before the current iteration)", DateOrNothingType));
        addField(new QoreDataField("last_executed_job_instanceid", "the last executed instance id of the job",
            IntOrNothingType));
        addField(new QoreDataField("name", "name of the job", StringType));
        addField(new QoreDataField("next", "the next trigger date/time", DateOrNothingType));
        addField(new QoreDataField("patch", "the patch value of the job", StringOrNothingType));
        addField(new QoreDataField("remote", "a boolean value giving the remote status of the job", BoolType));
        addField(new QoreDataField("started", "The date/time the job order data instance was created", DateType));
        addField(new QoreDataField("trigger", "a string describing the timer/trigger for the job", StringType));
        addField(new QoreDataField("version", "version of the job", StringType));

        addField(new QoreDataField("run_skipped", "a flag that indicates if a skipped trigger time should be "
            "executed on restart", BoolType));
        addField(new QoreDataField("custom_trigger", "a customer trigger time for the job", DateOrNothingType));
        addField(new QoreDataField("options", "a hash of job options, if any", HashOrNothingType));
        addField(new QoreDataField("alerts", "a list of zero or more alerts against the job", ListOrNothingType));
    }
}
}
