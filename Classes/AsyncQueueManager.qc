# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

public namespace OMQ {
/**
    It's a Qorus private class - not exposed to public API.
  */
class AsyncQueueManager {
/*  Just a shortcut wrapper for lookupQueue()
 */
private static string qName(int queueid) {
    return Qorus.qmm.lookupQueue(queueid).name;
}

/*  Updates a pending entry in a system queue with status @ref OMQ::QS_Waiting,
    sets the status to @ref OMQ::QS_Received (params: queue name, key, data).
    data is stored serialized in YAML format so that type information is preserved
    when passed to the asynchronous step back end function

    @param queueid ID of the queue
    @param key value of the key in the given queue
    @param data data to post in the queue entry; this data will be passed to the back end function for evaluation

    @throw UNKNOWN-QUEUE invalid queue name
    @throw INVALID-KEY no entry exists in the given queue with the given key value
    @throw INVALID-STATUS queue entry does not have status @ref OMQ::QS_Waiting
    @throw WORKFLOW-ACCESS-ERROR this is exeption is thrown when RBAC is enabled, and the call is made externally, and the user does not have the right to access the given workflow
 */
static nothing updateData(int queueid, softstring key, auto data) {
    # create serialized data string
    string strdata = serialize_qorus_data(data);

    hash<auto> q = sqlif.updateQueueData(AsyncQueueManager::qName(queueid), queueid, key, strdata);

    # update internal cache
    SM.updateQueue(q.workflowid, q.stepid, q.workflow_instanceid, q.ind, q.priority, False, key, data);
}

/*  corrects a queue entry with status @ref OMQ::QS_Waiting,
    sets the status to @ref OMQ::QS_Received and sets the
    \c corrected attribute to \c True

    this will effective cause an asynchronous step to be skipped
    without the back end function being run at all; the step will
    be processed to @ref OMQ::StatComplete as soon as the
    corrected queue entry is delivered to workflow execution
    instance processing this order.
    @param wfiid the workflow_instanceid of the entry to update
    @param stepid the stepid to update
    @param ind the array index offset of the step to update (0 for non-array steps)

    @note Data is stored serialized in YAML format so that type information
          is preserved when passed to the asynchronous step back end function

    @throw QUEUE-CORRECT-DATA-ERROR invalid workflow_instanceid or stepid
    @throw INVALID-WORKFLOW-DATA no queue data for the given step
    @throw INVALID-STATUS queue entry does not have status @ref OMQ::QS_Waiting
    @throw ALREADY-CORRECTED queue entry has already been corrected
    @throw WORKFLOW-ACCESS-ERROR this is exeption is thrown when RBAC is enabled, and the call is made externally, and the user does not have the right to access the given workflow
 */
static nothing correctData(softint wfiid, softint stepid, softint ind) {
    try {
        hash q = sqlif.correctQueueDataCheck(wfiid, stepid, ind);
        # update internal cache
        SM.updateQueue(q.workflowid, stepid, wfiid, ind, q.priority, True, q.queuekey);
    } catch (hash<ExceptionInfo> ex) {
        qlog(LoggerLevel::INFO, "error in queue.correctData(workflow_instanceid: %y, stepid: %y, ind: %y): %s: %s: %s", wfiid, stepid, ind, get_ex_pos(ex), ex.err, ex.desc);
        rethrow;
    }
}

/*  cancels a queue entry with status @ref OMQ::QS_Waiting (params: queue name, key)

    Either deletes the queue entry outright or, on Oracle, updates the status of the
    queue entry to @ref OMQ::QS_Used.
    Queue entries are no longer deleted when they are no longer needed in order
    to avoid corrupting indexes on Oracle, instead, they are deleted by
    the system service method arch.purge() when workflow data is deleted
    from the database (this method can also automatically analyze and rebuild
    indexes on Oracle as well).

    @param name the queue name for the entry to cancel
    @param key the key to the entry in the given queue to cancel
    @throw UNKNOWN-QUEUE invalid queue name
    @throw INVALID-KEY no entry exists in the given queue with the given key value
    @throw INVALID-STATUS queue entry does not have status @ref OMQ::QS_Waiting
    @throw WORKFLOW-ACCESS-ERROR this is exeption is thrown when RBAC is enabled, and the call is made externally, and the user does not have the right to access the given workflow
 */
static nothing cancelData(int queueid, softstring key) {
    hash q = sqlif.discardQueueDataCheck(queueid, key);

    if (exists q.err && q.err != NULL) {
        if (q.err == "INVALID-KEY")
            throw "INVALID-KEY", sprintf("no entry exists in queue %y with key %y", AsyncQueueManager::qName(queueid), key);
        else if (q.err == "INVALID-STATUS")
            throw "INVALID-STATUS", sprintf("queue %y key %y: data entry has status '%s' (%s), must be 'W' (WAITING), 'E' (ERROR), 'X' (USED) to cancel", AsyncQueueManager::qName(queueid), key, q.queue_data_status, OMQ::SQLQSMap.(q.queue_data_status));
    }
}

/*  changes the key for a pending entry in a system queue, only when
    the status is @ref OMQ::QS_Waiting (args: queue name, old key, new key)

    @param queuename the name of the queue
    @param oldkey the old key name
    @param newkey the new key name

    @throw UNKNOWN-QUEUE invalid queue name
    @throw UPDATE-KEY-ERROR empty string passed for oldkey or newkey
    @throw QUEUE-KEY-UPDATE-ERROR no queue entry; queue entry does not have status @ref OMQ::QS_Waiting
    @throw WORKFLOW-ACCESS-ERROR this is exeption is thrown when RBAC is enabled, and the call is made externally, and the user does not have the right to access the given workflow
 */
static nothing updateKey(int queueid, softstring oldkey, softstring newkey) {
    if (!strlen(oldkey))
        throw "UPDATE-KEY-ERROR", sprintf("missing current key argument as string, value passed: %y", oldkey);

    if (!strlen(newkey))
        throw "UPDATE-KEY-ERROR", sprintf("missing new key argument as string, value passed: %y", newkey);

    int rc = sqlif.updateQueueKey(queueid, oldkey, newkey);

    if (!rc)
        throw "QUEUE-KEY-UPDATE-ERROR", sprintf("no rows were updated on queue=%y with key=%y and status='W' (WAITING), check the queue key and status", AsyncQueueManager::qName(queueid), oldkey);
}

/*  gets queue information for a particular workflow and step

    @param wfiid the workflow_instanceid of the entry to query
    @param stepid the stepid to query
    @param ind the array index offset of the step to query (0 for non-array steps)

    @return The return value depends on the values passed; if either the stepid or the ind arguments are missing, then a list of all queue entries is returned.
    Otherwise a hash of a single queue entry is returned (if any exists).  If no queue entry exists matching the arguments, then either no value or an empty list is returned.

    The queue info hash has the following keys:
    - \c workflow_instanceid: the workflow instance ID of the step and queue entry
    - \c stepid: the step ID of the step and queue entry
    - \c ind: the array index of the step and queue entry (0 for non-array steps)
    - \c queuekey: the queue key string
    - \c queue_data_status: the status of the queue entry: @ref OMQ::QS_Waiting, @ref OMQ::QS_Received, @ref OMQ::QS_Used (Oracle only), or @ref OMQ::QS_Error (rarely, in case of unparsable queue data)
    - \c corrected: if 1, then the queue entry has been corrected. meaning that the back-end function will not be executed and the step will automatically get a @ref OMQ::StatComplete status.
    - \c data: the queue data, if any, set only when the queue data status is @ref OMQ::QS_Received

    @throw GET-INFO-ERROR invalid workflow_instanceid
    @throw WORKFLOW-ACCESS-ERROR this is exeption is thrown when RBAC is enabled, and the call is made externally, and the user does not have the right to access the given workflow
 */
static list getInfo(softint wfiid, softint stepid = 0, *softint ind) {
    if (!wfiid)
        throw "GET-INFO-ERROR", "missing required parameter: workflow_instanceid";

    return sqlif.queueGetInfo(wfiid, stepid, ind);
}

/*  gets queue information for a queue entry from the queue
    name and key (params: queue_name, key)

    @param queue the queue name for the entry to cancel
    @param key the key to the entry in the given queue to cancel

    @return no value if no information is available, or a hash with the following keys:
    - \c workflow_instanceid: the workflow instance ID of the step and queue entry
    - \c stepid: the step ID of the step and queue entry
    - \c ind: the array index of the step and queue entry (0 for non-array steps)
    - \c queuekey: the queue key string
    - \c queue_data_status: the status of the queue entry: @ref OMQ::QS_Waiting, @ref OMQ::QS_Received, @ref OMQ::QS_Used (Oracle only), or @ref OMQ::QS_Error (rarely, in case of unparsable queue data)
    - \c corrected: if 1, then the queue entry has been corrected. meaning that the back-end function will not be executed and the step will automatically get a @ref OMQ::StatComplete status.
    - \c data: the queue data, if any, set only when the queue data status is @ref OMQ::QS_Received

    @throw UNKNOWN-QUEUE invalid queue name
    @throw WORKFLOW-ACCESS-ERROR this is exeption is thrown when RBAC is enabled, and the call is made externally, and the user does not have the right to access the given workflow
 */
static *hash getInfoFromQueueKey(int queueid, softstring key) {
    return sqlif.queueGetInfoFromQueueKey(queueid, key);
}

#! gives internal queue status (without parameters: for all queues)
/**
    @param name optionally the name of the single queue to check

    @return depends on the argument; if no argument is passed, then summarized information for all queues is returned; the top level key is the queue name, and the values are queue summary hashes.
    If a value is passed, then the queue summary hash is returned immediately.

    If no information is available at all, then no value is returned.

    The queue summary hash has the following structure: key values are strings with the following format: \c "<workflow name>/<workflow version>" with queue status subkeys and with integer values corresponding to the number of workflows that have queue entries with the given statuses.

    @throw UNKNOWN-QUEUE invalid queue name
 */
static *hash status(int queueid) {
    *hash rv;
    context (sqlif.queueStatus(queueid)) {
        rv.%name.(%workflowname + "/" + %version).(OMQ::SQLQSMap.%status) = %count;
    }
    return rv;
}

#! Returns a list of queue entries on a given queue from the queue ID and an optional status filter
/**
    @param queueid the id of the queue
    @param opts options accepted:
    - \c status: a single SQL status value; see @ref SQL_QS_ALL and @ref QS_ALL for valid values (takes both short and
      long status codes); default all statuses except \c "USED" are returned
    - \c user: the username to search for
    - \c user_interaction_locked: 1 or 0 for the user interaction locked status
    - \c limit: the maximum number of entries to return; default 100
    - \c offset: the offset to return; default 0

    @return either no value or a list of hashes having the following keys:
    - \c queuekey: (string) the key name
    - \c queue_data_status: (string) queue entry status:
      - @ref OMQ::QS_Waiting
      - @ref OMQ::QS_Received
      - @ref OMQ::QS_Used
      - @ref OMQ::QS_Error (rarely, in case of unparsable queue data)
    - \c workflow_instanceid: (int) the workflow instance ID of the queue record
    - \c stepid: (int) the step ID of the queue record
    - \c ind: (int) the step index of the queue record
    - \c user_interaction_locked: (bool) \c True if locked, \c False if not
    - \c user_interaction_user: (string) current user with owning the lock on the queue record, if set
    - \c user_interaction_modified: (date) the timestamp the \a user_interaction_user was last updated, if set
    - \c created: (date) created timestamp for the queue entry
    - \c modified: (date) modified timestamp for the queue entry

    @throw GET-QUEUE-INFO-ERROR queueid is invalid
    @throw INVALID-STATUS status is invalid

    @note Queue entries with a \c "USED" status are only returned if the \a status argument is \c "USED"
    (@ref QS_Used) or \c "X" (@ref SQL_QS_Used)
 */
static *list<auto> getQueueInfo(int queueid, *hash<auto> opts) {
    if (exists opts.status) {
        # map from long descriptions to SQL short descriptions
        if (opts.status.size() > 1) {
            *string newstatus = QSMap{opts.status};
            if (!newstatus) {
                throw "INVALID-STATUS", sprintf("%y is not a valid queue status; expecting one of: %y", opts.status,
                    QS_ALL);
            }
            opts.status = newstatus;
        } else {
            if (!SQLQSMap{opts.status}) {
                throw "INVALID-STATUS", sprintf("%y is not a valid queue status; expecting one of: %y", opts.status,
                    SQL_QS_ALL);
            }
        }
    }

    *list<auto> l = sqlif.queueGetQueueInfo(queueid, opts);
    return map $1 + {
        "queue_data_status":OMQ::SQLQSMap.($1.queue_data_status),
        "user_interaction_locked": $1.user_interaction_locked.toBool(),
    }, l;
}
} # class AsyncQueueManager

} # namespace OMQ
