# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%requires qore >= 0.9

%new-style
%require-our
%strict-args
%require-types

%enable-all-warnings

public namespace OMQ;

# this class is shared in all Qorus programs: qorus, qorus-core, qdsp, qsvc, qjob, qwf, and qctl
class OMQ::QorusSharedApi {
    public {
        #! hash giving minimum system limits required for Qorus
        /** If the current values are less than these limits, the system will not start
        */
        const QorusLimits = {
            "nofile": 2048,
            "nproc": 2048,
        };

        # runtime buffer for descriptors and threads
        const RuntimeBuffer = 50;
    }

    private {
        #! nofile limit
        static softint nofile;

        #! nproc limit
        static softint nproc;
    }

    # check runtime limits
    /** @throw RUNTIME-LIMIT-ERROR runtime limits exceed limits
    */
    static checkLimits(*string err) {
        # check nofile
        softint current_nofile = QorusSharedApi::getCurrentNoFile();
        if (current_nofile) {
            int buffer_limit = QorusSharedApi::getNofile() - RuntimeBuffer;
            # do not throw an exception if the limit is unlimited
            if (buffer_limit > 0 && (current_nofile > buffer_limit)) {
                throw "RUNTIME-LIMIT-ERROR", sprintf("%s%snumber of descriptors (%d) has exceeded the buffer limit (%d) "
                    "calculated by the \"nofile\" system limit (%d) minus a buffer of %d for system descriptors", err,
                    err ? ": " : "", current_nofile, buffer_limit, QorusSharedApi::getNofile(), RuntimeBuffer);
            }
        }

        # check nproc (number of threads: num_threads())
        switch (PlatformOS) {
            case "Darwin":
            case "Linux":
            case "FreeBSD": {
                int buffer_limit = QorusSharedApi::getNproc() - RuntimeBuffer;
                # do not throw an exception if the limit is unlimited
                if (buffer_limit > 0 && ((int threads = num_threads()) > buffer_limit)) {
                    throw "RUNTIME-LIMIT-ERROR", sprintf("%s%snumber of threads (%d) has exceeded the buffer limit (%d) "
                        "calculated by the \"nproc\" system limit (%d) minus a buffer of %d for system threads", err,
                        err ? ": " : "", threads, buffer_limit, QorusSharedApi::getNproc(), RuntimeBuffer);
                }
                break;
            }
        }
    }

    # returns an integer with the number of descriptors currently in use by the current process
    /** if supported on the platform, otherwise 0
    */
    static int getCurrentNoFile() {
        try {
            switch (PlatformOS) {
                case "Darwin":
                case "FreeBSD": {
                    # using a Dir object to list files is much faster than launching a process like
                    # `ls -l /dev/fd|wc -l`
                    Dir d();
                    # this magic directory has one file per open descriptor in the process
                    d.chdir("/dev/fd");
                    return d.list().size();
                }
                case "Linux": {
                    # using a Dir object to list files is much faster than launching a process like
                    # `ls -l /proc/<pid>/fd|wc -l`
                    Dir d();
                    d.chdir("/proc/self/fd");
                    return d.list().size();
                }
            }
        } catch (hash<ExceptionInfo> ex) {
            string err = sprintf("error retrieving file descriptors in use: %s: %s", ex.err, ex.desc);
%ifdef QorusServer
            Qorus.logError("%s", err);
%else
            stderr.print(err + "\n");
%endif
        }
        return 0;
    }

    # check if the system can start; throws an exception if there's an error
    static checkSystemStart() {
        switch (PlatformOS) {
            case "Darwin":
            case "SunOS":
            case "FreeBSD":
                QorusSharedApi::checkUnixNofile();
                break;
            case "Linux":
                QorusSharedApi::checkUnixNofile();
                QorusSharedApi::checkUnixNproc();
                break;
        }
    }

    # returns the soft "nofile" limit
    static int getNofile() {
        return nofile ?? (nofile = get_limit_soft_nofile());
    }

    # returns the "nproc" limit
    static int getNproc() {
        return nproc ?? (nproc = get_limit_soft_nproc());
    }

    # check descriptors per process for this user
    /** @throw QORUS-START-LIMIT-ERROR if the nofile value is less than the minimum defined in @ref OMQ::QorusLimits
    */
    static checkUnixNofile() {
        softint nofile = QorusSharedApi::getNofile();
        # do not throw an exception if the limit is unlimited
        if (nofile > 0 && (nofile < QorusLimits.nofile)) {
            # try to set rlimit
            try {
                setrlimit(RLIMIT_NOFILE, QorusLimits.nofile);
            } catch (hash<ExceptionInfo> ex) {
                throw "QORUS-START-LIMIT-ERROR", sprintf("the per-process (file/socket) soft descriptor limit \"nofile\" "
                    "is currently set to %d which is below the minimum limit %d recommended to start Qorus; if system "
                    "limits on the number of file descriptors are reached, interfaces cannot be started; see your system "
                    "documentation for information on how to update this value (setrlimit(RLIMIT_NOFILE, %d) failed: "
                    "%s: %s)", nofile, QorusLimits.nofile, QorusLimits.nofile, ex.err, ex.desc);
            }
        }
    }

    # check threads per process for this user
    /** @throw QORUS-START-LIMIT-ERROR if the nofile value is less than the minimum defined in @ref OMQ::QorusLimits
    */
    static checkUnixNproc() {
        softint nproc = QorusSharedApi::getNproc();
        # do not throw an exception if the limit is unlimited
        if (nproc > 0 && (nproc < QorusLimits.nproc)) {
            try {
                setrlimit(RLIMIT_NPROC, QorusLimits.nproc);
            } catch (hash<ExceptionInfo> ex) {
                throw "QORUS-START-LIMIT-ERROR", sprintf("the per-process soft thread limit \"nproc\" is currently set to "
                    "%d which is below the minimum limit %d required to start Qorus; if system limits on the number of "
                    "threads are reached, interfaces cannot be started; see your system documentation for information on "
                    "how to update this value (setrlimit(RLIMIT_NOFILE, %d) failed: %s: %s)", nproc, QorusLimits.nproc,
                    QorusLimits.nproc, ex.err, ex.desc);
            }
        }
    }

    #! Ensures that an interruptible wait waits the entire time it should
    /** The lock must be acquired prior to calling
    */
    static waitCondition(Condition cond, AbstractSmartLock lock, timeout to, *reference<bool> stop_flag) {
        date start = now_us();
        while (!stop_flag) {
            cond.wait(lock, to);
            int delta = (now_us() - start).durationMilliseconds();
            if (delta >= to) {
                break;
            }
            to -= delta;
        }
    }

    #! Ensures that an interruptible wait waits the entire time it should
    static waitConditionLock(Condition cond, Mutex lck, timeout to, *reference<bool> stop_flag) {
        lck.lock();
        on_exit lck.unlock();

        QorusSharedApi::waitCondition(cond, lck, to, \stop_flag);
    }
}
