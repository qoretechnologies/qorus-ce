# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiLogMessageDataProvider class definition

/** QorusApiLogMessageDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the log message API
public class QorusApiLogMessageDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiLogMessageDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiLogMessageRequestDataType();

        #! Response type
        const ResponseType = AbstractDataProviderType::get(NothingType);
    }

    #! Returns the name of the data provider
    string getName() {
        return "log-message";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: writes a log message to the current log file.\n\n"
            "This API call can only be made internally in Qorus.\n\n"
            "This API call does not return any response.";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        UserApi::logWithLevelArgs(LoggerLevel::getLevel(req.level).getValue(), req.message, req.args);
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
public class QorusApiLogMessageRequestDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "level": {
                "type": StringType,
                "desc": "the message level; one of:\n- `ALL`\n- `TRACE`\n- `DEBUG`\n- `INFO`\n- `WARN`\n- `ERROR`\n- `FATAL`\n- `OFF`",
                "default_value": "INFO",
                "allowed_values": ("ALL", "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL", "OFF"),
            },
            "message": {
                "type": StringType,
                "desc": "the message to log; placeholders can be rendered using the `args` value as well",
            },
            "args": {
                "type": AutoType,
                "desc": "any arguments for placeholders in `message`",
            },
        };
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value,
            $1.value.allowed_values)), Fields.pairIterator();
    }
}

}
