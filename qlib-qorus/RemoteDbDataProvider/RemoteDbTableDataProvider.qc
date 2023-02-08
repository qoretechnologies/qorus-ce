# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore RemoteDbTableDataProvider class definition

/** RemoteDbTableDataProvider.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! Defines a data provider based on a single SQL table
public class RemoteDbTableDataProvider inherits AbstractDataProvider {
    public {
        #! Provider info
        const ProviderInfo = <DataProviderInfo>{
            "type": "RemoteDbTableDataProvider",
            "supports_read": True,
            "supports_create": True,
            "supports_update": True,
            "supports_upsert": True,
            "supports_delete": True,
            "supports_native_search": True,
            "supports_bulk_read": True,
            "supports_bulk_create": True,
            "supports_bulk_upsert": True,
            "supports_children": False,
            "constructor_options": ConstructorOptions,
            "search_options": SearchOptions,
            "create_options": CreateOptions,
            "upsert_options": UpsertOptions,
            "expressions": (AbstractDataProvider::GenericExpressions - DP_SEARCH_OP_REGEX) + {
                OP_LIKE: <DataProviderExpressionInfo>{
                    "type": DET_Operator,
                    "name": "like",
                    "label": OP_LIKE,
                    "symbol": "like",
                    "desc": "The SQL 'like' operator",
                    "args": (DataProviderSignatureStringType, DataProviderSignatureStringValueType),
                    "return_type": AbstractDataProviderTypeMap."bool",
                },
            },
            "transaction_management": True,
            "has_record": True,
            "mapper_keys": MapperKeyInfo,
        };

        #! Mapper runtime key info
        const MapperKeyInfo = Mapper::MapperKeyInfo + {
            "sequence": <MapperRuntimeKeyInfo>{
                "desc": "names the DB sequence that will be used to populate the field",
                "value_type": "string",
                "unique_roles": "*",
                "returns_type": "hash",
            },
            "sequence_currval": <MapperRuntimeKeyInfo>{
                "desc": "names the DB sequence that will be used to populate the field; the current value of the "
                    "sequence is used; will not increment the sequence",
                "value_type": "string",
                "unique_roles": "*",
                "returns_type": "hash",
            },
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
            "table": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(StringType),
                "required": True,
                "desc": "the table name or table object; if a table string is provided, then the \"datasource\" "
                    "option must also be provided",
            },
            "options": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(AutoHashType),
                "desc": "remote connection options",
            },
        };

        #! Search options
        const SearchOptions = {
            "block": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(IntType),
                "desc": "data block size; the number of rows to retrieve from the remote database and send in each "
                    "block",
            },
            "block_queue_size": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(IntType),
                "desc": "the number of blocks to queue for receiving before the I/O thread will block (default: 2); "
                    "the total number of rows that can be queued = _block_queue_size_ * _block_",
            },
            "timeout": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(IntType),
                "desc": "an HTTP socket timeout value in milliseconds; used locally and in the remote for socket I/O "
                    "and queue operations; default value: `300000` (5 minutes)",
            },
            "loglevel": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(IntType),
                "desc": "loglevel for logging",
            },
            "select": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(AutoHashType),
                "desc": "an SqlUtil select hash without the `where` key, which will be added by the select argument",
            },
            "transaction": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(BoolType),
                "desc": "start a remote transaction; if this option is not given or `False`, the remote transaction "
                    "status is left unchanged",
            },
        };

        #! Create options
        const CreateOptions = {
            "returning": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(AbstractDataProviderType::anyType),
                "desc": "a string (giving the output name) or a hash describing the return parameters for an insert; "
                    "a hash will have the following keys: 'key': (required) the column name to return, and 'type' "
                    "(optional) the data type for the output placeholder buffer (ex: 'number')",
            },
        };

        #! Upsert options
        const UpsertOptions = {
            "upsert_strategy": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(StringType),
                "desc": "providers the upsert strategy; 'UpsertInsertFirst': try to insert first, if it fails, try "
                    "updating; 'UpsertUpdateFirst': try to update first, if it fails, try inserting; "
                    "'UpsertSelectFirst': try to select first, if it fails, insert, if it succeeds, update if "
                    "necessary; 'UpsertInsertOnly': only insert, never update, 'UpsertUpdateOnly': only update, "
                    "never insert; 'UpsertAuto' (the default) use the most efficient upsert for the underlying DB",
            },
            "omit_update": <DataProviderOptionInfo>{
                "type": AbstractDataProviderType::get(new Type("softlist<string>")),
                "desc": "allows for an asymmetrical upsert where a set of column values is inserted, but a smaller "
                    "set is updated in case the unique key values are present in the target table; the value of this "
                    "option should be set to the columns to omit in the update clause",
            },
        };

        #! Maps SqlUtil @ref upsert_results to @ref db_provider_upsert_results
        const DbUpsertMap = {
            AbstractTable::UR_Inserted: UpsertResultInserted,
            AbstractTable::UR_Verified: UpsertResultVerified,
            AbstractTable::UR_Updated: UpsertResultUpdated,
            AbstractTable::UR_Unchanged: UpsertResultUnchanged,
            AbstractTable::UR_Deleted: UpsertResultDeleted,
        };
    }

    private {
        #! The remote connection name
        string remote;

        #! The remote stream object
        DbRemoteBase db;

        #! The table name
        string table;
    }

    #! Creates the object
    constructor(string remote, DbRemoteBase db, string table) {
        self.remote = remote;
        self.db = db;
        self.table = table;
    }

    #! Creates the object from constructor options
    constructor(*hash<auto> options) {
        *hash<auto> copts = checkOptions("CONSTRUCTOR-ERROR", ConstructorOptions, options);
        remote = copts.remote;
        db = new DbRemoteBase(copts.remote, copts.datasource, copts.options);
        table = copts.table;
    }

    #! Returns the data provider name
    string getName() {
        return table;
    }

    #! Returns the data provider description
    *string getDesc() {
        return sprintf("Qorus remote DB stream data provider for remote `%s`, datasource `%s`, and table `%s`",
            remote, db.datasourceName(), table);
    }

    #! Returns the description of the record type, if any
    private *hash<string, AbstractDataField> getRecordTypeImpl(*hash<auto> search_options) {
        *hash<auto> columns = db.describe_table(table);
        hash<string, AbstractDataField> rv;
        foreach hash<auto> i in (columns.pairIterator()) {
            Type type;
            try {
                type = new Type(OptimalQoreDataTypeMap{i.value.qore_type ?? "all"});
            } catch (hash<ExceptionInfo> ex) {
                type = AbstractDataProviderType::anyType;
            }
            string desc = i.value.native_type;
            if (!i.value.nullable) {
                desc += " NOT NULL";
            }
            if (i.value.comment) {
                desc += "; " + i.value.comment;
            }
            if (i.value.nullable || i.value.default_value) {
                type = type.getOrNothingType();
            }
            SqlUtilColumnDataType sqlutil_type(i.value.native_type, type);
            rv{i.key} = new SqlUtilColumnField(i.key, desc, sqlutil_type, i.value.default_value);
        }
        return rv;
    }

    #! Returns child providers; return @ref nothing if there are no child providers
    *AbstractDataProvider getChildProviders() {
    }

    #! Returns @ref True if the data provider supports transaction management
    /** @return @ref True if the data provider supports transaction management, in which case commit() or rollback()
        must be called to flush or discard data written to the data provider
    */
    bool requiresTransactionManagement() {
        return True;
    }

    #! Commits data written to the data provider
    /** Has no effect if the data provider does not support transaction management
    */
    commit() {
        db.commit();
    }

    #! Rolls back data written to the data provider
    /** Has no effect if the data provider does not support transaction management
    */
    rollback() {
        db.rollback();
    }

    #! Returns a bulk insert operation object for the data provider
    /** @return a bulk insert operation object for the data provider
    */
    AbstractDataProviderBulkOperation getBulkInserter() {
        return new RemoteDbTableBulkSendOperation(self, db, table, "insert");
    }

    #! Returns a bulk upsert operation object for the data provider
    /** @return a bulk upsert operation object for the data provider
    */
    AbstractDataProviderBulkOperation getBulkUpserter() {
        return new RemoteDbTableBulkSendOperation(self, db, table, "upsert");
    }

    #! Returns custom data mapper runtime keys
    /** @return custom data mapper runtime keys
    */
    *hash<string, hash<MapperRuntimeKeyInfo>> getMapperRuntimeKeys() {
        hash<string, hash<MapperRuntimeKeyInfo>> rv(MapperKeyInfo);
        rv.sequence.handler = \doSequenceKey();
        rv.sequence_currval.handler = \doSequenceCurrvalKey();
        return rv;
    }

    #! Writes the given record to the data provider
    /** @param rec a hash representing a single input record
        @param create_options the create options after processing by validateCreateOptions()

        @return the data written to the data provider plus any output (returning) variables

        @note this API will commit the row to the database unless the datasource was already in a transaction before
        this call
    */
    private *hash<auto> createRecordImpl(hash<auto> rec, *hash<auto> create_options) {
        *hash<auto> returning = db.insert(table, rec, create_options);
        return rec + returning;
    }

    #! Upserts the given record to the data provider
    /** @param rec a hash representing a single input record
        @param upsert_options the create options after processing by validateUpsertOptions()

        @return see @ref db_provider_upsert_results for possible values

        @note this API will commit the row to the database unless the datasource was already in a transaction before
        this call
    */
    string upsertRecordImpl(hash<auto> rec, *hash<auto> upsert_options) {
        return DbUpsertMap{db.upsert_row(table, rec,
            AbstractTable::UpsertStrategyDescriptionMap{remove upsert_options.upsert_strategy}
            ?? AbstractTable::UpsertAuto, upsert_options)};
    }

    #! Returns a single record matching the search options
    /** @param where_cond a hash for identifying the record(s)
        @param search_options the search options after processing by validateSearchOptions()

        @throw MULTIPLE-RECORDS-ERROR multiple records found
    */
    private *hash<auto> searchSingleRecordImpl(hash<auto> where_cond, *hash<auto> search_options) {
        try {
            return db.select_row(table, {"where": where_cond});
        } catch (hash<ExceptionInfo> ex) {
            if (ex.err == "DBI-SELECT-ROW-ERROR") {
                throw "MULTIPLE-RECORDS-ERROR", ex.desc, ex.arg;
            }
            rethrow;
        }
    }

    #! Returns an iterator for zero or more records matching the search options
    /** @param block_size the number of records in a read block; must be a positive number
        @param where_cond the search criteria; will be processed by processFieldValues()
        @param search_options the search options; will be processed by validateSearchOptions()

        @throw INVALID-BLOCK-SIZE the block size must be a positive number
        @throw INVALID-OPERATION the data provider does not support reading
    */
    private AbstractDataProviderBulkRecordInterface searchRecordsBulkImpl(int block_size = 1000, *hash<auto> where_cond,
            *hash<auto> search_options) {
        return new RemoteDbTableBulkRecordInterface(db, block_size, table, where_cond, search_options);
    }

    #! Returns an iterator for zero or more records matching the search options
    /** @param where_cond a hash for identifying the record(s)
        @param search_options the search options after processing by validateSearchOptions()

        @note this method acquires a transaction lock if one is not already acquired; the iterator returned performs a
        rollback in the destructor if a new transaction lock was acquired by this call and
        @ref RemoteDbDataProvider::RemoteDbTableRecordIterator::keepTransactionLock() "RemoteDbTableRecordIterator::keepTransactionLock()"
        is not called
    */
    private RemoteDbTableRecordIterator searchRecordsImpl(*hash<auto> where_cond, *hash<auto> search_options) {
        return new RemoteDbTableRecordIterator(db, table, where_cond, search_options);
    }

    #! Updates a single record matching the search options
    /** @param set the hash of field data to set
        @param where_cond a hash for identifying the record to be update
        @param search_options the update options after processing by validateSearchOptions()

        @throw UPDATE-SINGLE-RECORD-ERROR if the update would update more than one record

        @note this API will commit the row to the database unless the datasource was already in a transaction before
        this call
    */
    private bool updateSingleRecordImpl(hash<auto> set, hash<auto> where_cond, *hash<auto> search_options) {
        int rows = updateRecordsImpl(set, where_cond, search_options);
        if (rows > 1) {
            bool in_trans = db.inTransaction();
            throw "UPDATE-SINGLE-RECORD-ERROR", sprintf("%d record(s) were updated; %ssearch args: %y (set: %y)", rows,
                (!in_trans ? "the update has been rolled back; " : ""), search_options, set);
        }
        return rows.toBool();
    }

    #! Updates zero or more records matching the search options
    /** @param set the hash of field data to set
        @param where_cond a hash for identifying the record(s) to be updated
        @param search_options the update options after processing by validateSearchOptions()

        @return the number of records updated

        @note this API will commit the row to the database unless the datasource was already in a transaction before
        this call
    */
    private int updateRecordsImpl(hash<auto> set, *hash<auto> where_cond, *hash<auto> search_options) {
        return db.update(table, set, where_cond);
    }

    #! Deletes zero or more records
    /**
        @param where_cond a hash for identifying the record(s) to be deleted
        @param search_options the delete options after processing by validateSearchOptions()

        @return the number of records deleted

        @throw INVALID-OPERATION the data provider does not support record updating

        @note this API will commit the row to the database unless the datasource was already in a transaction before
        this call
    */
    private int deleteRecordsImpl(*hash<auto> where_cond, *hash<auto> search_options) {
        return db.del(table, where_cond);
    }

    #! Returns data provider static info
    private hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }

    #! Processes the \c sequence runtime key in mappers as a mapper key handler
    hash<auto> doSequenceKey(string sequence_name, hash<auto> ctx, *reference<bool> missing_input) {
        return iop_seq(sequence_name);
    }

    #! Processes the \c sequence_currval runtime key in mappers as a mapper key handler
    hash<auto> doSequenceCurrvalKey(string sequence_name, hash<auto> ctx, *reference<bool> missing_input) {
        return iop_seq_currval(sequence_name);
    }
}
}
