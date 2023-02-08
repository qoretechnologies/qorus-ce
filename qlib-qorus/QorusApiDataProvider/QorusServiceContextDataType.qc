# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusServiceContextDataType class definition

/** QorusServiceContextDataType.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The data type for service contexts in Qorus
public class QorusServiceContextDataType inherits HashDataType {
    #! Creates the type
    constructor() : HashDataType("service context hash") {
        addField(new QoreDataField("active_calls", "the number of active calls in the service", IntType));
        addField(new QoreDataField("alerts", "a list of zero or more alerts against the service", ListOrNothingType));
        addField(new QoreDataField("author", "the author if the service, if present", StringOrNothingType));
        addField(new QoreDataField("autostart", "the autostart flag", BoolType));
        addField(new QoreDataField("desc", "the description of the service", StringOrNothingType));
        addField(new QoreDataField("groups", "a list of zero or more hashes for groups the service is a member of",
            new QoreListDataType(new Type("list<hash<auto>>"))));
        addField(new QoreDataField("loaded", "the date/time the service was loaded/started", DateType));
        addField(new QoreDataField("manual_autostart", "a falg indicating if the 'autostart' value has been manually "
            "updated", BoolType));
        addField(new QoreDataField("method", "the name of the current method being called", StringType));
        addField(new QoreDataField("methods", "a list of hashes with name and desc keys for each method",
            AutoListType));
        addField(new QoreDataField("name", "name of the service", StringType));
        addField(new QoreDataField("options", "a hash of options set on the service, if any", HashOrNothingType));
        addField(new QoreDataField("parse_options", "parse options set on any Qore code", IntOrNothingType));
        addField(new QoreDataField("patch", "the patch value of the service", StringOrNothingType));
        addField(new QoreDataField("remote", "a boolean value giving the remote status of the service", BoolType));
        addField(new QoreDataField("resource_files", "a list of one or more file resources", ListOrNothingType));
        addField(new QoreDataField("resources", "a hash of resources attached to the service; each hash key is the "
            "unique resource name", AutoHashOrNothingType));
        addField(new QoreDataField("serviceid", "ID of the current service", IntType));
        addField(new QoreDataField("status", "either \"running\" (active threads) or \"loaded\" (no active threads)",
            StringType));
        addField(new QoreDataField("threads", "number of threads currently in progress", IntType));
        addField(new QoreDataField("type", "the service type (\"user\" or \"system\")", StringType));
        addField(new QoreDataField("version", "version of the service", StringType));
        addField(new QoreDataField("waiting_threads", "the number of waiting threads in the service", IntType));
    }
}
}

