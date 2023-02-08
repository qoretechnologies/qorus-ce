# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusWorkflowContextDataType class definition

/** QorusWorkflowContextDataType.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The data type for workflow contexts in Qorus
public class QorusWorkflowContextDataType inherits HashDataType {
    #! Creates the type
    constructor() : HashDataType("workflow context hash") {
        addField(new QoreDataField("author", "the author if the workflow, if present", StringOrNothingType));
        addField(new QoreDataField("dbstatus", "the status of the workflow order in the database; normally "
            "\"IN-PROGRESS\"", StringType));
        addField(new QoreDataField("external_order_instanceid", "The external order instance ID saved against the "
            "order, if any", StringOrNothingType));
        addField(new QoreDataField("execid", "the execution instance ID", StringType));
        addField(new QoreDataField("initstatus", "the status of the workflow when it was cached", StringType));
        addField(new QoreDataField("instancemode", "The mode the workflow execution instance process is running in; "
            "normally \"NORMAL\"", StringOrNothingType));
        addField(new QoreDataField("mode", "The mode the current thread is running in; normally \"NORMAL\"",
            StringOrNothingType));
        addField(new QoreDataField("name", "name of the workflow", StringType));
        addField(new QoreDataField("parent_workflow_instanceid", "The order data instance ID of any parent workflow",
            SoftIntOrNothingType));
        addField(new QoreDataField("patch", "the patch value of the workflow", StringOrNothingType));
        addField(new QoreDataField("priority", "The priority (0 - 999) of the workflow order data instance",
            IntType));
        addField(new QoreDataField("remote", "a boolean value giving the remote status of the workflow", BoolType));
        addField(new QoreDataField("started", "The date/time the workflow order data instance was created",
            DateType));
        addField(new QoreDataField("starttime", "The date/time the workflow execution instance was created",
            DateType));
        addField(new QoreDataField("status", "The current status of the workflow order data instance; normally "
            "\"IN-PROGRESS\"", StringType));
        addField(new QoreDataField("step", "information about the current step", getStepDataType()));
        addField(new QoreDataField("sync", "True if the workflow execution instance is synchronous, False if not",
            BoolType));
        addField(new QoreDataField("version", "version of the workflow", StringType));
        addField(new QoreDataField("workflowid", "ID of the current workflow", IntType));
        addField(new QoreDataField("workflow_instanceid", "The current workflow order data instance ID being "
            "processed", SoftIntType));
    }

    #! Returns the step data type
    private HashDataType getStepDataType() {
        HashDataType step("step context hash");
        step.addField(new QoreDataField("afname", "the name of the array function (corresponds to "
            "arrayfunction_instanceid) for function-based array steps", StringOrNothingType));
        step.addField(new QoreDataField("array_size", "the number of elements in the array for array steps",
            IntOrNothingType));
        step.addField(new QoreDataField("arrayfunction_instanceid", "the function instance ID of the array function "
            "for function-based array steps", IntOrNothingType));
        step.addField(new QoreDataField("author", "the author if the step, if present", StringOrNothingType));
        step.addField(new QoreDataField("created", "the creation date for the step", DateType));
        step.addField(new QoreDataField("modified", "the modified date for the step", DateType));
        step.addField(new QoreDataField("user_interaction", "user interaction flag", BoolOrNothingType));
        step.addField(new QoreDataField("classname", "the name of the step class", StringOrNothingType));
        step.addField(new QoreDataField("code", "the source code for the step", StringType));
        step.addField(new QoreDataField("language", "the language of the step's source code", StringType));
        step.addField(new QoreDataField("efname", "the name of the end function (corresponds to "
            "endfunction_instanceid) for function-based asynchronous steps", StringOrNothingType));
        step.addField(new QoreDataField("endfunction_instanceid", "the function instance ID of the asynchronous end "
            "function for asynchronous steps for function-based asynchronous steps", IntOrNothingType));
        step.addField(new QoreDataField("eventtype", "the name of the event type (corresponds to "
            "workflow_event_typeid) for workflow synchronization event steps", StringOrNothingType));
        step.addField(new QoreDataField("stepfunction_instanceid", "the function instance ID of the primary step "
            "function for function-based steps", IntOrNothingType));
        step.addField(new QoreDataField("arraytype", "the array type of the step; one of \"NONE\" or \"SERIES\"",
            StringType));
        step.addField(new QoreDataField("desc", "the description of the current step", StringOrNothingType));
        step.addField(new QoreDataField("index", " element number for array steps (always 0 for non-array steps)",
            IntType));
        step.addField(new QoreDataField("queueid", "the ID of the asynchronous queue for asynchronous steps for "
            "function-based asynchronous steps", IntOrNothingType));
        step.addField(new QoreDataField("queuename", "the name of the asynchronous queue (corresponds to queueid) "
            "for function-based asynchronous steps", StringOrNothingType));
        step.addField(new QoreDataField("name", "name of the step", StringType));
        step.addField(new QoreDataField("patch", "the patch value of the current step", StringOrNothingType));
        step.addField(new QoreDataField("retries", "the current retry number when called from a workflow execution "
            "instance run in RECOVERY mode", IntType));
        step.addField(new QoreDataField("sfname", "the name of the primary step function for function-based steps",
            StringOrNothingType));
        step.addField(new QoreDataField("step_classid", "the class ID of the step's class for class-based steps; "
            "either this value or stepfunction_instanceid will be returned", IntOrNothingType));
        step.addField(new QoreDataField("stepid", "ID of the current step", IntType));
        step.addField(new QoreDataField("stepstatus", "the previous step status when called from a workflow "
            "execution instance run in RECOVERY mode", StringOrNothingType));
        step.addField(new QoreDataField("steptype", "the type of the step; one of \"NORMAL\", \"ASYNC\", "
            "\"SUBWORKFLOW\", or \"EVENT\"", StringOrNothingType));
        step.addField(new QoreDataField("validationfunction_instanceid", "the function instance ID of the validation "
            "function for function-based steps", IntOrNothingType));
        step.addField(new QoreDataField("version", "version of the step", StringType));
        step.addField(new QoreDataField("vfname", "the name of the validation function (corresponds to "
            "validationfunction_instanceid) for function-based steps", StringOrNothingType));
        step.addField(new QoreDataField("workflow_event_typeid", "the event type ID for workflow synchronization "
            "event steps for workflow synchronization event steps", IntOrNothingType));
        return step;
    }
}
}

