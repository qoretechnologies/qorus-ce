# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore QorusApiSearchBulkIteratorDataProvider class definition

/** QorusApiSearchBulkIteratorDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! The Qorus API data provider for the data provider search API
public class QorusApiSearchBulkIteratorDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "QorusApiSearchBulkIteratorDataProvider",
            "supports_request": True,
        };

        #! Request type
        const RequestType = new QorusApiSearchBulkIteratorRequestDataType();

        #! Response type
        const ResponseType = AbstractDataProviderType::get(ListOrNothingType);
    }

    #! Returns the name of the data provider
    string getName() {
        return "search-bulk-iterator";
    }

    #! Returns the data provider description
    *string getDesc() {
        return "Request/response data provider: performs a search in the given data provider and returns the results "
            "as a bulk iterator (`AbstractDataProviderBulkRecordInterface` object) for the output data.\n\n"
            "This API can be used to provide efficient bulk input to a data pipeline from a data provider, for "
            "example.";
    }

    #! Makes a request and returns the response
    /** @param req the request to serialize and make according to the request type
        @param request_options the request options; will be processed by validateRequestOptions()

        @return the response to the request
    */
    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        AbstractDataProvider prov = UserApi::getDataProvider(req."provider-path");
        prov.checkRead();
        UserApi::logInfo("QorusApiSearchBulkIteratorDataProvider: using data provider: %y options: %y "
            "search criteria: %y block size: %d", req."provider-path", req."search-options",
            req."where", req."block-size");
        return prov.searchRecordsBulk(req."block-size", req."where", req."search-options");
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
public class QorusApiSearchBulkIteratorRequestDataType inherits HashDataType {
    private {
        #! Field descriptions
        const Fields = {
            "provider-path": {
                "type": DataProviderType,
                "desc": "A path to a data provider that supports searches",
                "required": True,
            },
            "where": {
                "type": HashOrNothingType,
                "desc": "An optional hash giving search criteria, where keys are field names and values are field "
                    "values or hash operator expressions",
            },
            "search-options": {
                "type": HashOrNothingType,
                "desc": "An optional hash giving search options",
            },
            "block-size": {
                "type": IntType,
                "desc": "The block size for record sets to be returned",
                "default_value": 1000,
            },
        };
    }

    #! Creates the object
    constructor() {
        map addField(new QoreDataField($1.key, $1.value.desc, $1.value.type, $1.value.default_value)),
            Fields.pairIterator();
    }
}
}
