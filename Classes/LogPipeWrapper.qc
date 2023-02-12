

# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

#! creates a FIFO and captures information written to the FIFO and redirects it to a Logger
class LogPipeWrapper {
    private {
        #! in milliseconds
        const ReadTimeout = 100ms;

        #! for synmchronizing the exit of the logging thread
        Counter bgThreadCnt();

        #! flag signifying if the output wrapper should run
        bool running = True;

        #! the log pipe path
        string logPipePath;

        #! the process name
        string logPrefix;

        #! the logger for logging
        Logger logger;
    }

    constructor(Logger logger, string logPipePath, string logPrefix) {
        self.logger = logger;
        self.logPipePath = logPipePath;
        self.logPrefix = logPrefix;

        # create the FIFO
        # check if pipe already exists
        {
            *hash<StatInfo> stat_info = hstat(logPipePath);
            # make sure the file is a pipe, otherwise delete it
            if (stat_info && stat_info.type != "FIFO") {
                unlink(logPipePath);
                remove stat_info;
            }
            if (!stat_info) {
                mkfifo(logPipePath);
            }
        }

        start();
    }

    destructor() {
        stop();
        # remove the log pipe
        unlink(logPipePath);
    }

    updateLogger(*hash<LoggerParams> params) {
        logger = createLogger(params);
    }

    private:internal start() {
        bgThreadCnt.inc();
        on_error bgThreadCnt.dec();
        background captureLogInfo();
    }

    private:internal captureLogInfo() {
        on_exit {
            bgThreadCnt.dec();
            logger.info("%s: stopping logging thread for FIFO %y", logPrefix, logPipePath);
        }
        logger.info("%s: starting logging thread for FIFO %y", logPrefix, logPipePath);

        # open the reader in nonblocking mode
        StreamReader logReader(new FileInputStream(logPipePath, ReadTimeout, True));
        while (running) {
            try {
                readLineAndLog(logReader);
            } catch (hash<ExceptionInfo> ex) {
                # ignore timeout errors
                if (ex.err == "FILE-READ-TIMEOUT-ERROR") {
                    continue;
                }
                stderr.printf("%s: exception in log thread: %s", logPrefix, get_exception_string(ex));
            }
        }
    }

    stop() {
        running = False;
        bgThreadCnt.waitForZero();
    }

    #! this method will read in a log line from the stream and issue it to the logger
    abstract readLineAndLog(StreamReader logReader);

    static string getLogPipePath(string logPrefix) {
        return join_paths(tmp_location(), sprintf("qorus-%s-%s-log.pipe", Qorus.options.get("instance-key"), logPrefix));
    }
}
