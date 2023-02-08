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

#! contains all public definitions in the RemoteApiProvider module
public namespace RemoteApiProvider {
#! Wrapper data type
public class WrapperType inherits Type {
    private {
        string name;
    }

    #! Creates the object
    constructor(string name, string basetype) : Type(basetype) {
        self.name = name;
    }

    #! Returns the type name
    string getName() {
        return name;
    }
}
}
