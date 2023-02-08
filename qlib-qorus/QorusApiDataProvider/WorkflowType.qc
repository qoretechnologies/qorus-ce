# -*- mode: qore; indent-tabs-mode: nil -*-

/*
  Qorus Integration Engine

  Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

  **** NOTICE ****
    All information contained herein is, and remains the property of Qore
    Technologies, s.r.o. and its suppliers, if any.  The intellectual and
    technical concepts contained herein are proprietary to Qore Technologies,
    s.r.o. and its suppliers and may be covered by Czech, European, U.S. and
    Foreign Patents, patents in process, and are protected by trade secret or
    copyright law.  Dissemination of this information or reproduction of this
    material is strictly forbidden unless prior written permission is obtained
    from Qore Technologies, s.r.o..
*/

#! contains all public definitions in the QorusApiDataProvider module
public namespace QorusApiDataProvider {
#! workflow type object
public const WorkflowType = new WorkflowType();
#! workflow or nothing type object
public const WorkflowOrNothingType = new WorkflowOrNothingType();

#! Workflow type
public class WorkflowType inherits WrapperType {
    #! Creates the object
    constructor() : WrapperType("workflow", "softstring") {
    }
}

#! Workflow or nothing type
public class WorkflowOrNothingType inherits WrapperType {
    #! Creates the object
    constructor() : WrapperType("*workflow", "*softstring") {
    }
}
}
