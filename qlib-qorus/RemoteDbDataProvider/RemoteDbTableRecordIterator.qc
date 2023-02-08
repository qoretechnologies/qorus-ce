# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore RemoteDbTableRecordIterator class definition

/** RemoteDbTableRecordIterator.qc Copyright 2019 - 2023 Qore Technologies, s.r.o.

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
#! Defines a buffered record iterator class for remote database connections; uses multiplexed I/O
/** @see DbRemoteReceive for more information
*/
public class RemoteDbTableRecordIterator inherits AbstractRemoteDbRecordIterator {
    #! Creates the iterator
    /** @param remote the remote connection
        @param table the remote table to select from
        @param where_cond there "where" condition hash
        @param search_options search options; assumed to have already been processed for validity before this call
    */
    constructor(DbRemoteBase remote, string table, *hash<auto> where_cond, *hash<auto> search_options) : AbstractRemoteDbRecordIterator(!remote.inTransaction(), RemoteDbTableRecordIterator::getReceiver(remote, table, where_cond, search_options)) {
    }

    #! Creates the receiver
    private static DbRemoteReceive getReceiver(DbRemoteBase remote, string table, *hash<auto> where_cond, *hash<auto> search_options) {
        # setup remote select stream
        hash<auto> opts = search_options ?? {};
        opts.select."where" = where_cond;
        return new DbRemoteReceive(remote, table, opts);
    }
}
}
