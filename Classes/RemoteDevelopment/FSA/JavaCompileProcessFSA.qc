# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace RemoteDevelopment;

/** Remote development finite state automation for compilation of java files.

    Design info: https://git.qoretechnologies.com/qoretechnologies/wiki/-/wikis/Qorus-Remote-Development

    private class; not exposed to the public API
*/

class RemoteDevelopment::JavaCompileProcessFSA inherits ProcessFSA {
    private {
        UploadRequest uploadRequest;
    }

    #! Constructs JavaCompileProcessFSA object with given request
    #  Initialize method must be called to initialize the FSA (ProcessFSA method).
    /** @param request containing files to be compiled, id of the request, user name

        @throw BAD-REQUEST exception in case request is incorrect
    */
    constructor(UploadRequest request) : ProcessFSA(ENV.OMQ_DIR + "/bin/qjavac") {
        uploadRequest = request;
    }

    # overrides ProcessFSA method
    private hash<auto> getProcessOptions() {
        return {};
    }

    private string getDestinationFolder() {
        string omq_dir = ENV.OMQ_DIR;
        if (omq_dir.empty()) {
            log(LoggerLevel::DEBUG, "OMQ_DIR variable is not initialized");
            throw "ENV-ERROR", "OMQ_DIR variable is not initialized";
        }
        return omq_dir + Qore::DirSep + "user" + Qore::DirSep;
    }

    # ProcessFSA method
    private list<string> getProcessArgs() {
        list<string> args = getClassPathArgs();
        foreach auto file in (uploadRequest.files) {
            if (canBeCompiled(file.file_name)) {
                args += getDestinationFolder() + file.file_name;
            }
        }
        return args;
    }

    #! returns classpath option for javac
    private list<string> getClassPathArgs() {
        string omq_jar_dir = ENV.OMQ_DIR + Qore::DirSep + "jar" + Qore::DirSep;
        list<auto> qorus_jars = map normalize_dir(omq_jar_dir + $1), QORUS_JARS;
        string jars = join(":", qorus_jars);
        return ("-cp", jars);
    }

    #! Checks if file can be compiled
    /** @param file_path pathname to check

        @return True in case file can be compiled, False if not
    */
    private bool canBeCompiled(string file_path) {
        return (file_path =~ /\.java$/);
    }
}
