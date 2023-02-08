# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types
%enable-all-warnings

public namespace RemoteDevelopment {
    hashdecl Status {
        string status = STATUS_QUEUED;
        int exit_code = -1;
        string stderr = "";
        string stdout = "Request is waiting for processing in queue";
        date created = now();
    }

    hashdecl CreationStatus {
        int id;
        *list<string> warning;
    }

    public const STATUS_QUEUED = "QUEUED";
    public const STATUS_IN_PROGRESS = "IN_PROGRESS";
    public const STATUS_CANCELED = "CANCELED";
    public const STATUS_FAILED = "FAILED";
    public const STATUS_FINISHED = "FINISHED";

    public const STATUS_UPLOADING = "UPLOADING";
    public const STATUS_UPLOADED = "UPLOADED";

    public const QORUS_JARS = ("qorus-client.jar", "qore-jni.jar", "qore-jni-compiler.jar");

    # This class represents common development request. Constructor of this class is private to forbid creating
    # instances outside of the class hierarchy
    public class Request {
        public {
            int id;
            string user;
            *string token;
        }

        private constructor(*string user, *string token) {
            self.user = user ?? "anonymous";
            self.token = token;
        }

        abstract hash<auto> convertToHash();
    }

    #! This class represents common development request with options. Constructor of this class is private to forbid
    # creating instances outside of the class hierarchy
    public class RequestWithOptions inherits Request {
        public {
            *hash<auto> options;
        }

        private constructor(*string user, *string token, *hash<auto> options) : Request(user, token) {
            self.options = options;
        }

        hash<auto> convertToHash() {
            return {"options": options};
        }
    }

    #! This class represents common development upload request. Constructor of this class is private to forbid
    # creating instances outside of the class hierarchy
    public class UploadRequest inherits Request {
        public {
            list<auto> files;
        }

        #! @throw BAD-REQUEST in case list of files is empty
        private constructor(list<auto> files, *string user, *string token) : Request(user, token) {
            self.files = files;
            if (files.empty()) {
                throw "BAD-REQUEST", "File list is empty";
            }
        }

        hash<auto> convertToHash() {
            return {"files": files};
        }
    }

    #! This class represents remote deployment request
    public class DeployRequest inherits UploadRequest, RequestWithOptions {
        constructor(list<auto> files, *string user, *string token, *hash<auto> options) :
            UploadRequest(files, user, token), RequestWithOptions(user, token, options) {
        }

        hash<auto> convertToHash() {
            return UploadRequest::convertToHash() + RequestWithOptions::convertToHash();
        }
    }

    class Interface {
        public {
            *string id;
            *string name;
            string type;
        }

        constructor(string id) {
            self.id = id;
        }

        constructor(string name, string type) {
            self.name = name;
            self.type = type;
        }

        string getIdentifier() {
            return type + ":" + (id ?? name);
        }

        string getDisableUriPath() {
            return sprintf("%ss/%s/disable", type, id ?? name);
        }
    }

    class InterfaceWithVersion inherits Interface {
        public {
            string version;
        }

        constructor(string version, string name, string type) : Interface(name, type) {
            self.version = version;
        }

        string getIdentifier() {
            string identifier = Interface::getIdentifier();
            return identifier + ":" + version;
        }
    }

    class MethodInterface inherits InterfaceWithVersion {
        public {
            string methodName;
        }

        constructor(string method_name, string version, string name, string type)
            : InterfaceWithVersion(name, type, version) {

            methodName = method_name;
        }

        string getIdentifier() {
            string identifier = InterfaceWithVersion::getIdentifier();
            return id ?? identifier + ":" + methodName;
        }
    }

    const INTERFACE_TYPES = {
        "workflow": "InterfaceWithVersion",
        "wfinstances": "InterfaceWithVersion",
        "step": "InterfaceWithVersion",
        "function": "InterfaceWithVersion",
        "class": "InterfaceWithVersion",
        "constant": "InterfaceWithVersion",
        "service": "InterfaceWithVersion",
        "mapper": "InterfaceWithVersion",
        "method": "MethodInterface",

        "datasource": "Interface",
        "event": "Interface",
        "fsm": "Interface",
        "job": "Interface",
        "jobinstances": "Interface",
        "pipeline": "Interface",
        "queue": "Interface",
        "remote": "Interface",
        "uconn": "Interface",
        "vmap": "Interface",
    };

    const INTERFACE_TYPES_WITHOUT_CONNECTIONS = INTERFACE_TYPES - ("uconn", "datasource", "remote");

    #! This class represents remote delete request
    public class DeleteRequest inherits RequestWithOptions {
        public {
            list<Interface> interfaces;
        }

        #! Request hash must contain interfaces to delete and options (optionally)
        constructor(*hash<auto> request_hash, *string user, *string token) :
                RequestWithOptions(user, token, request_hash.options) {
            foreach string type in (keys INTERFACE_TYPES) {
                *softlist<auto> interfaces_ = request_hash{type};
                foreach auto interface in (interfaces_) {
                    if (interface.id) {
                        Interface new_interface = new Interface(interface.id);
                        if (!INTERFACE_TYPES_WITHOUT_CONNECTIONS.hasKey(type)) {
                            throw "BAD-REQUEST", sprintf("interface type %y cannot be deleted by id", type);
                        }
                        new_interface.type = type;
                        interfaces += new_interface;
                        continue;
                    }

                    if (!exists interface.name) {
                        throw "REST-ARG-ERROR", sprintf("missing 'name' key in delete request for type %y", type);
                    }

                    switch (INTERFACE_TYPES{type}) {
                        case "Interface":
                            interfaces += new Interface(interface.name, type);
                            break;
                        case "InterfaceWithVersion":
                            if (!exists interface.version) {
                                throw "REST-ARG-ERROR", sprintf("missing 'version' key in delete request for type %y", type);
                            }
                            interfaces += new InterfaceWithVersion(interface.version, interface.name, type);
                            break;
                        case "MethodInterface":
                            if (!exists interface."method-name") {
                                throw "REST-ARG-ERROR", sprintf("missing 'method-name' key in delete request for type %y", type);
                            }
                            interfaces += new MethodInterface(interface."method-name", interface.version,
                                                              interface.name, type);
                            break;
                        default:
                            throw "BAD-REQUEST", sprintf("Unknown interface type: %y", type);
                    }
                }
            }
        }

        hash<auto> convertToHash() {
            hash<auto> result();
            foreach auto interface in (interfaces) {
                if (!exists result{interface.type}) {
                    result{interface.type} = new list<auto>();
                }

                if (interface.id) {
                    result{interface.type} += {"id": interface.id};
                    continue;
                }

                switch (INTERFACE_TYPES{interface.type}) {
                    case "Interface":
                        result{interface.type} += {"name": interface.name};
                        break;
                    case "InterfaceWithVersion":
                        result{interface.type} += {"name": interface.name, "version": interface.version};
                        break;
                    case "MethodInterface":
                        result{interface.type} += {"name": interface.name, "version": interface.version,
                                                   "method-name": interface.methodName};
                        break;
                    default:
                        throw "BAD-REQUEST", sprintf("Unknown interface type: %y", interface.type);
                }
            }

            return result + RequestWithOptions::convertToHash();
        }
    }

    #! This class represents remote release request
    public class ReleaseRequest inherits UploadRequest, RequestWithOptions {
        constructor(list<auto> files, *string user, *string token, *hash<auto> options) :
            UploadRequest(files, user, token), RequestWithOptions(user, token, options) {
        }

        hash<auto> convertToHash() {
            return UploadRequest::convertToHash() + RequestWithOptions::convertToHash();
        }
    }

    #! This class represents remote test request for execution of .qtest files
    public class TestRequest inherits UploadRequest, RequestWithOptions {
        public {
            list<hash<auto>> qoreTestFiles;
            list<hash<auto>> javaTestFiles;
            list<hash<auto>> pythonTestFiles;

            list<hash<auto>> qoreScriptFiles;
            list<hash<auto>> pythonScriptFiles;
            list<hash<auto>> schemaFiles;
        }

        constructor(list<auto> files, *string user, *hash<auto> options) :
                UploadRequest(files, user, NOTHING), RequestWithOptions(user, NOTHING, options) {
            separateTests();
        }

        int numJavaTests() {
            return javaTestFiles.size();
        }

        int numQoreTests() {
            return qoreTestFiles.size();
        }

        int numPythonTests() {
            return pythonTestFiles.size();
        }

        int numQoreScripts() {
            return qoreScriptFiles.size();
        }

        int numPythonScripts() {
            return pythonScriptFiles.size();
        }

        int numSchemas() {
            return schemaFiles.size();
        }

        hash<auto> convertToHash() {
            return UploadRequest::convertToHash() + RequestWithOptions::convertToHash();
        }

        private separateTests() {
            foreach hash<auto> file in (files) {
                if (isQoreTest(file.file_name)) {
                    qoreTestFiles += file;
                } else if (isJavaTest(file.file_name)) {
                    javaTestFiles += file;
                } else if (isPythonTest(file.file_name)) {
                    pythonTestFiles += file;
                } else if (isQoreScript(file.file_name)) {
                    qoreScriptFiles += file;
                } else if (isPythonScript(file.file_name)) {
                    pythonScriptFiles += file;
                } else if (isSchema(file.file_name)) {
                    schemaFiles += file;
                }
            }

            list<string> clist;
            if (*int num = numQoreTests()) {
                clist += sprintf(" %d Qore test%s", num, num == 1 ? "" : "s");
            }
            if (*int num = numJavaTests()) {
                clist += sprintf(" %d Java test%s", num, num == 1 ? "" : "s");
            }
            if (*int num = numPythonTests()) {
                clist += sprintf(" %d Python test%s", num, num == 1 ? "" : "s");
            }
            if (*int num = numQoreScripts()) {
                clist += sprintf(" %d Qore script%s", num, num == 1 ? "" : "s");
            }
            if (*int num = numPythonScripts()) {
                clist += sprintf(" %d Python script%s", num, num == 1 ? "" : "s");
            }
            if (*int num = numSchemas()) {
                clist += sprintf(" %d schema%s", num, num == 1 ? "" : "s");
            }

            if (clist.size() > 1) {
                throw "BAD-REQUEST", sprintf("One request cannot have more than one type of object to deploy; "
                    "got: %y", clist);
            }

            if (!clist) {
                throw "BAD-REQUEST", sprintf("No tests to be run; none of '*.qtest', '*.qscript', '*.qsm', "
                    "'*Test.java', '*qscript.py', or '*test.py' were provided)");
            }
        }

        private bool isQoreTest(string file_name) {
            return (file_name =~ /\.qtest$/);
        }

        private bool isJavaTest(string file_name) {
            return (file_name =~ /Test.java$/);
        }

        private bool isPythonTest(string file_name) {
            return (file_name =~ /test.py$/);
        }

        private bool isQoreScript(string file_name) {
            return (file_name =~ /qscript$/);
        }

        private bool isPythonScript(string file_name) {
            return (file_name =~ /qscript.py$/);
        }

        private bool isSchema(string file_name) {
            return (file_name =~ /\.qsm$/);
        }
    }
}
