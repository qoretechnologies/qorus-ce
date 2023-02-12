# -*- mode: qore; indent-tabs-mode: nil -*-
# Qorus OrderInstanceNotes class definition

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%require-types
%strict-args

# handle ORDER_INSTANCE_NOTES
# Instance keeps list of hashes. hash format:
#  - saved (bool): flag if is the note saved in the database or not
#  - username (string): automatically obtained name of current user
#  - note: (string): note body itself
#  - created (date): timestamp of creation (in Qorus, not DB)
#
# Notes are ordere by created timestamp, descending order
#
# Static methods are used for non-cached WF instances,
# regular methods are used in WF cache.
class OMQ::OrderInstanceNotes inherits Qore::Serializable {
    private {
        softlist notes;
        transient Mutex mutex();
    }

    constructor(*list n) {
        notes = n;
    }

    constructor(softint wfiid) {
        notes = OrderInstanceNotes::getNotes(wfiid);
    }

    # for external locking
    Mutex getLock() {
        return mutex;
    }

    # created from compressed cache data in de-serialization
    set(hash h) {
        self += h;
    }

    # do not need locking here since changes are always made atomically
    list get() {
        return notes;
    }

    # do not need locking here since changes are always made atomically
    int size() {
        return notes.size();
    }

    hash addCommit(softint wfiid, hash note) {
        note = OrderInstanceNotes::formatNew(note);
        if (!note.note)
            return note;

        AutoLock al(mutex);
        notes += note;
        OrderInstanceNotes::saveNotes(wfiid, \notes);
        return note;
    }

    hash add(hash note) {
        note = OrderInstanceNotes::formatNew(note);
        if (!note.note)
            return note;

        AutoLock al(mutex);
        push notes, note;
        return note;
    }

    # for use by the helper object with external locking
    hash addUnlocked(hash note) {
        note = OrderInstanceNotes::formatNew(note);
        if (!note.note)
            return note;

        push notes, note;
        return note;
    }

    save(softint wfiid) {
        AutoLock al(mutex);
        OrderInstanceNotes::saveNotes(wfiid, \notes);
    }

    list saveNoCommit(softint wfiid) {
        AutoLock al(mutex);
        return OrderInstanceNotes::saveNotesNoCommit(wfiid, \notes);
    }

    # for use by the helper object with external locking
    list saveNoCommitUnlocked(softint wfiid) {
        return OrderInstanceNotes::saveNotesNoCommit(wfiid, \notes);
    }

    applySaved(list l) {
        AutoLock al(mutex);
        map notes[$1].saved = True, l;
    }

    # for use by the helper object with external locking
    applySavedUnlocked(list l) {
        map notes[$1].saved = True, l;
    }

    static softlist getNotes(softint wfiid) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();

                QDBG_TEST_CLUSTER_FAILOVER();
                return map ("saved": True) + $1.("username", "note", "created", "modified"), sqlif.orderInstanceNotesGet(wfiid).contextIterator();
            } catch (hash<ExceptionInfo>  ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            break;
        }
    }

    # ensure requested note format. Handle the legacy op_* keys too
    static hash formatNew(hash note) {
        note += (
            "saved": False,
            "created": now_us(),
            "username": tld.cx.user ? tld.cx.user : "system",
            );

        # handle legacy stuff too
        if (!note.note && note.op_comment) {
            note.note = remove note.op_comment;
            olog(LoggerLevel::INFO, "set-option-info command uses obsolete hash key: op_comment");
        }

        return note;
    }

    static list saveNotes(softint wfiid, reference notes) {
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                QDBG_TEST_CLUSTER_FAILOVER();
                return OrderInstanceNotes::saveNotesNoCommit(wfiid, \notes);
            } catch (hash<ExceptionInfo>  ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            break;
        }
    }

    /**
        @return a list of integer index numbers to the notes list of notes that were saved
    */
    static list saveNotesNoCommit(softint wfiid, reference notes) {
        list l = ();
        *list toWrite = OrderInstanceNotes::getSaveNotes(wfiid, \notes, \l);
        if (toWrite && !sqlif.orderInstanceNotesSave(wfiid, toWrite))
            throw "ORDER-INFO-ERROR", sprintf("No workflow instance id '%s' found in the DB", wfiid);
        return l;
    }

    /**
        @param l returns a list of integer index numbers to the notes list of notes that were saved
    */
    static *list getSaveNotes(softint wfiid, reference notes, reference l) {
        list toWrite;

        # iterate and update the list
        foreach hash h in (notes) {
            if (!h.saved) {
                toWrite += h;
                l += $#;
            }
        }

        return toWrite;
    }

    static hash addSave(softint wfiid, string note) {
        return OrderInstanceNotes::addSave(wfiid, ("note": note));
    }

    static hash addSave(softint wfiid, hash note) {
        hash h;
        QorusRestartableTransaction trans();
        while (True) {
            try {
                on_error omqp.rollback();
                on_success omqp.commit();

                list nl;
                h = OrderInstanceNotes::addSaveNoCommit(wfiid, note, \nl);
                QDBG_TEST_CLUSTER_FAILOVER();
            } catch (hash<ExceptionInfo>  ex) {
                # restart the transaction if necessary
                if (trans.restartTransaction(ex))
                    continue;
                rethrow;
            }
            break;
        }
        return h + ("saved": True);
    }

    static hash addSaveNoCommit(softint wfiid, string note) {
        list nl;
        return OrderInstanceNotes::addSaveNoCommit(wfiid, ("note": note), \nl);
    }

    static hash addSaveNoCommit(softint wfiid, hash note, reference nl) {
        note = OrderInstanceNotes::formatNew(note);
        if (!note.note)
            return note;

        softlist l = note;
        nl = OrderInstanceNotes::saveNotesNoCommit(wfiid, \l);
        return note;
    }
} # class OrderInstanceNotes

class OrderInstanceNotesHelper {
    public {
    }

    private:internal {
        OrderInstanceNotes notes;
        Mutex m;
    }

    constructor(OrderInstanceNotes notes) {
        self.notes = notes;
        m = notes.getLock();
        m.lock();
    }

    destructor() {
        m.unlock();
    }

    list saveNoCommit(softint wfiid) {
        return notes.saveNoCommitUnlocked(wfiid);
    }

    applySaved(list l) {
        notes.applySavedUnlocked(l);
    }

    hash add(hash note) {
        return notes.addUnlocked(note);
    }
}
