# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore RemoteDbTableBulkRecordInterface class definition

/** RemoteDbTableBulkRecordInterface.qc Copyright 2023 Qore Technologies, s.r.o.

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

#! contains all public definitions in the RemoteDbDataProvider  module
public namespace RemoteDbDataProvider  {
#! Defines the record iterator class for Table-based iterators
public class RemoteDbTableBulkRecordInterface inherits AbstractDataProviderBulkRecordInterface {
    private:internal {
        #! the remote select stream
        DbRemoteReceive recv;

        #! release the transaction with a rollback in the destructor?
        bool release_transaction;
    }

    #! creates the iterator
    /** @param remote the remote connection
        @param block_size the number of records in a read block; must be a positive number; will override any \c block
        value in \c search_options
        @param table the table to iteratate
        @param where_cond the search criteria; will be processed by processFieldValues()
        @param search_options search options; assumed to have already been processed for validity before this call
    */
    constructor(DbRemoteBase remote, int block_size, string table, *hash<auto> where_cond, *hash<auto> search_options)
        : AbstractDataProviderBulkRecordInterface(block_size) {
        # release the transaction with a rollback in the destructor by default if we do not already have a transaction
        # lock
        release_transaction = !remote.inTransaction();

        # setup remote select stream
        hash<auto> opts = {} + search_options + {
            "block": block_size,
        };
        opts.select."where" = where_cond;
        recv = new DbRemoteReceive(remote, "select", table, opts);
    }

    #! rolls back the transaction if a transaction lock was acquired in the constructor and keepTransactionLock() was not called
    destructor() {
        if (release_transaction) {
            recv.rollback();
        }
    }

    #! Ensures that no rollback is performed when the object is destroyed
    keepTransactionLock() {
        release_transaction = False;
    }

    #! Returns a hash of lists according to the block size
    /** @throw INVALID-ITERATOR the iterator is not pointing at a valid element

        @note This call moves the internal record pointer forward, therefore multiple calls of this methods will
        return different results as long as data is available
    */
    private hash<string, list<auto>> getValueImpl() {
        return cast<*hash<string, list<auto>>>(recv.getData()) ?? {};
    }
}
}
