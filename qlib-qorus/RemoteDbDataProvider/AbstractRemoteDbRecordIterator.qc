# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore AbstractRemoteDbRecordIterator class definition

/** AbstractRemoteDbRecordIterator.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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

#! Contains all public definitions in the RemoteDbDataProvider module
public namespace RemoteDbDataProvider {
#! Defines a buffered record iterator class for remote database connections; uses multiplexed I/O
/** @see DbRemoteReceive for more information
*/
public class AbstractRemoteDbRecordIterator inherits AbstractDataProviderRecordIterator {
    private:internal {
        #! The remote select stream
        DbRemoteReceive recv;

        #! Current record iterator
        HashListIterator i;

        #! Done flag
        bool done = False;

        #! Release the transaction with a rollback in the destructor?
        bool release_transaction;
    }

    #! Creates the iterator
    /** @param release_transaction release the transaction with a rollback in the destructor?
        @param recv the remote select stream
    */
    constructor(bool release_transaction, DbRemoteReceive recv) {
        self.release_transaction = release_transaction;
        self.recv = recv;
    }

    #! Rolls back the transaction if a transaction lock was acquired in the constructor and keepTransactionLock() was not called
    destructor() {
        if (release_transaction) {
            recv.rollback();
        }
    }

    #! Returns @ref True if the iterator is valid
    /**
        @return @ref True if the iterator is valid
    */
    bool valid() {
        return !done;
    }

    #! Increments the row pointer when retrieving rows from a select statement; returns @ref True if there is a row to retrieve, @ref False if not
    /**
        @return @ref True if there is a row to retrieve, @ref False if not (no more rows to be retrieved)

        @throw INVALID-ITERATOR the iterator is not pointing at a valid element

        @note Exceptions could be thrown by the DBI driver when the statement is executed; see the relevant DBI driver
        docs for more information
    */
    bool next() {
        if (done) {
            throw "INVALID-ITERATOR", sprintf("%s::next() already returned False and cannot be called again",
                self.className());
        }
        # advance the current iterator or get the next record set
        return (!i || !i.next())
            ? nextRecordSet()
            : True;
    }

    #! Returns a single record if the iterator is valid
    /** @throw INVALID-ITERATOR the iterator is not pointing at a valid element
    */
    hash<auto> getValue() {
        if (done) {
            throw "INVALID-ITERATOR", sprintf("%s::next() already returned False, so %s::getValue() cannot be called",
                self.className(), self.className());
        }
        return i.getValue();
    }

    #! Ensures that no rollback is performed when the object is destroyed
    keepTransactionLock() {
        release_transaction = False;
    }

    #! Returns the value of the given field in the current row, if the iterator is valid
    /** @param key the name of the field

        @return the value of the given field in the current row, if the iterator is valid

        @throw FIELD-ERROR invalid or unknown field name
    */
    auto memberGate(string key) {
        hash<auto> row = i.getValue();
        auto rv = row{key};
        if (!exists rv && !row.hasKey(key)) {
            throw "FIELD-ERROR", sprintf("the current record does not have field %y; valid fields: %y", key,
                keys row);
        }
        return rv;
    }

    #! gets the next record set and sets up the iterator to point at the next record
    private:internal bool nextRecordSet() {
        # try to get next record setup
        *hash<auto> recs = recv.getData();
        if (!recs) {
            done = True;
            return False;
        }
        i = new HashListIterator(recs);
        return i.next();
    }
}
}
