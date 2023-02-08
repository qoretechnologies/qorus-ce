# -*- mode: qore; indent-tabs-mode: nil -*-
# Oload Test Helper

/*
  Qorus Integration Engine

  Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

  **** NOTICE ****
    All information contained herein is, and remains the property of Qore
    Technologies, s.r.o. and its suppliers, if any.  The intellectual and
    technical concepts contained herein are proprietary to Qore Technologies,
    s.r.o. and its suppliers and may be covered by Czech, European, U.S. and
    Foreign Patents, patents in process, and are protected by trade secret or
    copyright law.  Dissemination of this information or reproduction of this
    material is strictly forbidden unless prior written permission is obtained
    from Qore Technologies, s.r.o.
 */

%new-style
%strict-args
%require-types
%enable-all-warnings

%requires process

class OloadTestHelper {
    private {
        const DefaultOutputSize = 64 * 1024;
        const DefaultTimeout = 250;
    }

    private static *string getStdout(Process process) {
        string rv;
        while (True) {
            *string str = process.readStdout(DefaultOutputSize, DefaultTimeout);
            if (!str) {
                break;
            }
            rv += str;
        }
        return rv;
    }

    private static *string getStderr(Process process) {
        string rv;
        while (True) {
            *string str = process.readStderr(DefaultOutputSize, DefaultTimeout);
            if (!str) {
                break;
            }
            rv += str;
        }
        return rv;
    }

    # runs oload with the given args
    static hash<auto> runOload(list<auto> args, bool print = True) {
        hash<auto> options = {
            "path": (ENV.OMQ_DIR + "/bin",)
        };

        if (print) {
            printf("Arguments for oload process: %y\n", args);
        }
        Process process("oload", args, options);
        process.wait();

        hash<auto> result = {
            "stdout": OloadTestHelper::getStdout(process),
            "stderr": OloadTestHelper::getStderr(process),
            "exit_code": process.exitCode()
        };
        if (print) {
            printf("result: %N\n", result);
        }
        return result;
    }

    private static list<auto> prepareFiles(string directory, bool redef = False, *string regex = NOTHING,
                                     hash<auto> ignore_files = {}) {
        Dir dir();
        dir.chdir(directory);

        list files = dir.listFiles(regex);
        if (ignore_files) {
            files = select files, !ignore_files.hasKey($1);
        }
        files = map directory + Qore::DirSep + $1, files;

        return files;
    }

    # oloads files from the given directory
    static hash<auto> oloadFiles(string directory, bool redef = False, *string regex = NOTHING, bool print = True,
                           hash<auto> ignore_files = {}) {
        list<auto> files = OloadTestHelper::prepareFiles(directory, redef, regex, ignore_files);

        list<auto> args = ("-l", "-R", "-v");
        if (redef) {
            args += "-A";
        }
        args += files;
        return OloadTestHelper::runOload(args, print);
    }

    # oloads files one by one from the given directory
    static list<hash<auto>> oloadFileByFile(string directory, bool redef = False, *string regex = NOTHING, bool print = True,
                                      hash<auto> ignore_files = {}) {
        list<auto> files = OloadTestHelper::prepareFiles(directory, redef, regex, ignore_files);

        list<hash<auto>> result;
        while (!files.empty()) {
            list<auto> args = ("-l", "-R", "-v");
            if (redef) {
                args += "-A";
            }

            args += pop files;
            result += OloadTestHelper::runOload(args, print);
        }
        return result;
    }

    # deletes given interfaces (format: <type>:<name>:<version>)
    static hash<auto> deleteInterfaces(list<auto> interfacesToDelete, bool redef = False, bool print = True) {
        list<auto> args = ("-l", "-R");
        if (redef) {
            args += "-A";
        }
        args += map sprintf("-X%s", $1), interfacesToDelete;
        hash<auto> deletion_result = OloadTestHelper::runOload(args, print);
        return deletion_result;
    }
}