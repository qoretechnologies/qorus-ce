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

/** Remote development test finite state automation for java tests.

    Design info: https://git.qoretechnologies.com/qoretechnologies/wiki/-/wikis/Qorus-Remote-Development

    It's a Qorus private class - not exposed to public API.
*/

class RemoteDevelopment::JavaTestProcessFSA inherits RemoteDevelopment::TestProcessFSA {
    public {
        # sets the Qore JNI class loader as the system class loader to support the execution of Java code using
        # dynamically-imported Python and Qore APIs
        const QoreJniSystemClassLoaderOption = "-Djava.system.class.loader=org.qore.jni.QoreURLClassLoader";
    }

    private {
        const COMPILE_STATE = "compiling";

        # compile FSA for java compilation
        JavaCompileProcessFSA compileFSA;
    }

    #! Constructs JavaTestProcessFSA object with given request
    #  Initialize method must be called to initialize the FSA (ProcessFSA method).
    /** @param request containing qtests to be run

        @throw BAD-REQUEST exception in case request is incorrect
    */
    constructor(TestRequest request) : TestProcessFSA(request, "java") {
        compileFSA = new JavaCompileProcessFSA(request);
        compileFSA.initialize();
    }

    # RemoteDevelopment::ProcessFSA method
    private hash<string, hash<StateInfo>> getTransitions() {
        hash<string, hash<StateInfo>> transitions = TestProcessFSA::getTransitions();

        # Add compiling state
        transitions += {
            COMPILE_STATE: <StateInfo>{
                FSA::INVARIANT: \compile(),
                FSA::TRANSITIONS: {
                    DONE: CREATE_PROCESS_STATE,
                    CANCEL: CANCELED_STATE,
                    FAIL: DONE_STATE,
                }
            },
        };

        # when files are uploaded start the compilation
        transitions{UPLOADING_STATE}{FSA::TRANSITIONS}{DONE} = COMPILE_STATE;
        return transitions;
    }

    # ProcessFSA method
    private list<string> getProcessArgs() {
        string file_name = testFiles[fileIndex].file_name;
        string dest_folder = TestProcessFSA::getDestinationFolder();
        list<string> args = getClassPathArgs(dest_folder + dirname(file_name));
        args += QoreJniSystemClassLoaderOption;

        # add dest folder and remove the java extension
        args += replace(basename(file_name), ".java", "", -5);
        args += getArgList(testFiles[fileIndex].args);
        log(LoggerLevel::INFO, "JavaTestProcessFSA::getProcessArgs: args: %y", args);
        return args;
    }

    #! returns classpath option for java
    private list<string> getClassPathArgs(string file_path) {
        string omq_dir = ENV.OMQ_DIR + Qore::DirSep + "jar" + Qore::DirSep;
        list qorus_jars = map normalize_dir(omq_dir + $1), QORUS_JARS;
        qorus_jars += file_path;
        string jars = join(":", qorus_jars);
        return ("-cp", jars);
    }

    # TestProcessFSA method
    private list<string> getArgList(*hash<auto> args) {
        list<string> result = map sprintf("\"%s\"\n", $1.value), args.pairIterator();
        return result;
    }

    # overrides TestProcessFSA method
    private list<hash<auto>> getTestFiles() {
        return testRequest.javaTestFiles;
    }

    #! Returns status hash of this JavaTestProcessFSA
    /** @return request hash containing all information about this JavaTestProcessFSA
    */
    hash<Status> getStatus() {
        hash<Status> compileStatus = compileFSA.getStatus();
        if (compileStatus.status == STATUS_FAILED) {
            return compileStatus;
        }
        return TestProcessFSA::getStatus();
    }

    #! compiling state (compiles all tests together, but then they are run separately)
    private compile() {
        compileFSA.execute(START);
        if (compileFSA.getStatus().status == STATUS_FAILED) {
            execute(FAIL);
        } else {
            execute(DONE);
        }
    }

    # overrides ProcessFSA method
    private canceled() {
        compileFSA.execute(CANCEL);
        TestProcessFSA::canceled();
    }
}
