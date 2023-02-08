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
#! Data type for create order API responses
public class QorusApiCancelOrderResponseDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = (
            "workflow_status": {
                "type": StringType,
                "desc": "The order's status after the update",
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
