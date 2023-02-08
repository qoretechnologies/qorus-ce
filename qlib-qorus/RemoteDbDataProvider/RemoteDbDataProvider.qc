# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore RemoteDbDataProvider class definition

/** RemoteDbDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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

#! contains all public definitions in the RemoteDbDataProvider module
public namespace RemoteDbDataProvider {
#! The database data provider class, provides tables as children
public class RemoteDbDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "RemoteDbDataProvider",
            "supports_read": True,
            "supports_bulk_read": True,
            "supports_children": True,
            "constructor_options": ConstructorOptions,
            "search_options": SearchOptions,
            "transaction_management": True,
            "has_record": True,
            "record_requires_search_options": True,
            "children_can_support_apis": False,
            "children_can_support_records": True,
            "children_can_support_observers": False,
        };

        #! Constructor options
        const ConstructorOptions = {
            "remote": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(StringType),
                "desc": "the name of the remote Qorus connection",
                "required": True,
            },
            "datasource": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(StringType),
                "desc": "the datasource connection string",
                "required": True,
            },
            "options": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(AutoHashType),
                "desc": "remote connection options",
            },
        };

        #! Search options
        const SearchOptions = {
            "sql": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(StringType),
                "desc": "the raw SQL for the select statement",
                "required": True,
            },
            "args": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(AutoListType),
                "desc": "any bind arguments for the select statement",
            },
        };
    }

    private {
        #! The remote connection name
        string remote;

        #! The remote stream object
        DbRemoteBase db;
    }

    #! creates the object
    constructor(string remote, DbRemoteBase db) {
        self.remote = remote;
        self.db = db;
    }

    #! creates the object
    constructor(string remote, string datasource, *hash<auto> opts) {
        self.remote = remote;
        db = new DbRemoteBase(remote, datasource, opts);
    }

    #! Creates the object from constructor options
    constructor(*hash<auto> options) {
        *hash<auto> copts = checkOptions("CONSTRUCTOR-ERROR", ConstructorOptions, options);
        remote = copts.remote;
        db = new DbRemoteBase(copts.remote, copts.datasource, copts.options);
    }

    #! Returns the datasource name
    string getName() {
        return db.datasourceName();
    }

    #! Returns the data provider description
    *string getDesc() {
        return sprintf("Qorus remote DB stream data provider for remote `%s` and datasource `%s`", remote,
            db.datasourceName());
    }

    #! Commits any transaction in progress in the remote datasource
    /**
    */
    commit() {
        db.commit();
    }

    #! Rolls back any transaction in progress in the remote datasource
    /**
    */
    rollback() {
        db.rollback();
    }

    #! Returns the description of the record type, if any
    /** @param search_options to be included and processed by validateSearchOptions() if
        \a recordRequiresSearchOptions() is @ref True for this provider, otherwise any value provided in this argument
        is ignored
    */
    private *hash<string, AbstractDataField> getRecordTypeImpl(*hash<auto> search_options) {
        bool in_trans = db.inTransaction();
        on_error {
            if (!in_trans) {
                db.rollback();
            }
        }
        on_success {
            if (!in_trans) {
                db.commit();
            }
        }

        list<auto> args;
        args += search_options.sql;
        if (search_options.args) {
            args += search_options.args;
        }
        HashDataType input_data();
        foreach hash<auto> i in (db.methodGateArgs("describe_query", args).pairIterator()) {
            # get input column name
            string key = i.key.lwr();
            string desc = i.value.native_type.lwr();
            # add DB maximum size to desc
            if (i.value.maxsize) {
                desc += sprintf("(%d)", i.value.maxsize);
            }
            #printf("i: %y\n", i);
            *string type = DataProvider::OptimalQoreDataTypeMap{TypeCodeMap{i.value.type}};
            AbstractDataProviderType data_type;
            if (!type.val() || type == "any") {
                data_type = AbstractDataProviderType::get(AutoType);
            } else {
                # maps standard types to auto types to avoid type stripping
                if (type =~ /(hash|list)$/) {
                    type += "<auto>";
                }
                data_type = AbstractDataProviderType::get(type);
            }
            input_data.addField(new QoreDataField(key, desc, data_type));
        }
        return input_data.getFields();
    }

    #! Returns an iterator for zero or more records matching the search options
    /** @param block_size the number of records in a read block; must be a positive number
        @param where_cond the search criteria after processing by processFieldValues()
        @param search_options the search options after processing by validateSearchOptions()

        @throw INVALID-BLOCK-SIZE the block size must be a positive number
        @throw INVALID-OPERATION the data provider does not support reading
    */
    private AbstractDataProviderBulkRecordInterface searchRecordsBulkImpl(int block_size = 1000,
            *hash<auto> where_cond, *hash<auto> search_options) {
        return new RemoteDbSelectBulkRecordInterface(db, block_size, where_cond, search_options);
    }

    #! Returns an iterator for zero or more records matching the search options
    /** @param where_cond the search criteria
        @param search_options the search options after processing by validateSearchOptions()

        @see requestSearchRecordsImpl()
    */
    private AbstractDataProviderRecordIterator searchRecordsImpl(*hash<auto> where_cond, *hash<auto> search_options) {
        return new RemoteDbSelectRecordIterator(db, where_cond, search_options);
    }

    #! Returns a list of child data provider names, if any
    /** @return a list of child data provider names, if any
    */
    private *list<string> getChildProviderNamesImpl() {
        return db.list_tables();
    }

    #! Returns the given child provider or @ref nothing if the given child is unknown
    /** @return the given child provider or @ref nothing if the given child is unknown

        @throw CHILD-PROVIDER-ERROR error acquiring child provider

        @see getChildProviderEx()
    */
    private *AbstractDataProvider getChildProviderImpl(string name) {
        if (db.exists_table(name)) {
            return new RemoteDbTableDataProvider(remote, db, name);
        }
    }

    #! Returns data provider static info
    private hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }
}
}
