# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore RemoteDbTableBulkSendOperation class definition

/** RemoteDbTableBulkSendOperation.qc Copyright 2023 Qore Technologies, s.r.o.

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
#! Bulk insert object for remote tables; uses multiplexed I/O
/** @see DbRemoteSend for more information
*/
public class RemoteDbTableBulkSendOperation inherits DataProvider::AbstractDataProviderBulkOperation {
    private {
        #! This object can only be used from the thread where it was created
        int tid = gettid();

        #! The remote connection
        DbRemoteBase remote;

        #! The table name
        string table;

        #! The stream to use
        string stream;

        #! Options to use when creating the remote send object
        *hash<auto> opts;

        #! The bulk send operation
        DbRemoteSend send;
    }

    #! Creates the object
    /** @param provider the remote data provider (parent object)
        @param remote the remote connection
        @param table the remote table name
        @param stream the stream name
        @param opts bulk send options

        @note that the actual bulk send object is created on demand; once the bulk send operation is in progress, no
        other I/O can be done on the same connection
    */
    constructor(RemoteDbTableDataProvider provider, DbRemoteBase remote, string table, string stream, *hash<auto> opts)
        : AbstractDataProviderBulkOperation(provider) {
        self.remote = remote;
        self.table = table;
        self.stream = stream;
        self.opts = opts;
    }

    #! Queues data in the buffer
    queueData(hash<auto> record) {
        checkSend();
        send.append(record);
    }

    #! Queues data in the buffer
    queueData(list<hash<auto>> records) {
        checkSend();
        send.append(records);
    }

    #! Flushes any remaining data to the data provider
    /** This method should always be called before committing the transaction (if the data provider supports
        transaction management) or destroying the object
    */
    flush() {
        checkSend();
        send.flush();
    }

    #! Discards any buffered data
    /** This method should be called before rolling back the transaction (if the data provider supports transaction
        management) or destroying the object if an error occurs
    */
    discard() {
        # this method intentionally left blank
    }

    private:internal checkSend() {
        if (tid != gettid()) {
            throw "REMOTE-DB-BULK-SEND-THREAD-ERROR", sprintf("this object was created in TID %d and can only be "
                "used in that thread (caller's TID: %d)", tid, gettid());
        }
        if (!send) {
            send = new DbRemoteSend(remote, stream, table, opts);
        }
    }
}
}
