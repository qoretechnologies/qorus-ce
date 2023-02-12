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

/** Remote development flie upload process finite state automation.

    Design info: https://git.qoretechnologies.com/qoretechnologies/wiki/-/wikis/Qorus-Remote-Development

    It's a Qorus private class - not exposed to public API.
*/

class RemoteDevelopment::FileUploadProcessFSA inherits ProcessFSA {
    private:internal {
        int filesIt = 0;
        UploadRequest uploadRequest;
    }

    private {
        const UPLOADING_STATE = "uploading";
        const FAIL_STATE = "fail";
        const NEXT_FILE = "nextFile";
    }

    #! Constructs FileUploadProcessFSA object with given request and process command.
    #  Initialize method must be called to initialize the FSA (ProcessFSA method).
    /** @param uploadRequest request containing files to be uploaded to the server
        @param process_command the name of the process to be wrapped
    */
    constructor(UploadRequest request, string process_command = "oload") : ProcessFSA(process_command) {
        uploadRequest = request;
    }

    # RemoteDevelopment::ProcessFSA method
    private hash<string, hash<StateInfo>> getTransitions() {
        hash<string, hash<StateInfo>> transitions = ProcessFSA::getTransitions();
        transitions += {
            UPLOADING_STATE: <StateInfo>{
                FSA::INVARIANT: \uploading(),
                FSA::TRANSITIONS: {
                    NEXT_FILE: UPLOADING_STATE,
                    DONE: CREATE_PROCESS_STATE,
                    CANCEL: CANCELED_STATE,
                    FAIL: FAIL_STATE
                }
            },
            FAIL_STATE: <StateInfo>{
                FSA::IS_FINAL: True,
            }
        };

        transitions{IDLE_STATE}{FSA::TRANSITIONS}{START} = UPLOADING_STATE;
        return transitions;
    }
    ###

    #! Returns request of this ProcessFSA
    /** @return request object containing files to be uploaded, id of the request and user name
    */
    UploadRequest getRequest() {
        return uploadRequest;
    }

    # Should be implemented in child classes
    private abstract string getDestinationFolder();

    # Might be re-implemented in child classes
    private string getDestinationFolderForFile(string file_path) {
        return dirname(file_path);
    }

    #! Saves file received with given path and content to the file system
    /** @param file_path path where to save, will be prefixed by OMQ_DIR environment variable
        @param file_content content of the file as base64 encoded string
        @return full path to the file in case of success, otherwise NOTHING
        @throw ENV-ERROR if OMQ_DIR environment variable is not set
    */
    private *string createFile(string file_path, string file_content) {
        string file_name = basename(file_path);
        string directory = getDestinationFolderForFile(file_path);
        log(LoggerLevel::DEBUG, "Creating file: %y", file_name);

        string dirname = getDestinationFolder() + Qore::DirSep + directory + Qore::DirSep;
        Dir dir("utf-8");
        dir.chdir(dirname);

        if (!dir.exists()) {
            dir.create(0700);
            log(LoggerLevel::DEBUG, "Created directory: %y", dir.path());
        }

        try {
            File file = dir.openFile(file_name, O_CREAT|O_WRONLY|O_TRUNC, 0644, "utf-8");
            binary file_data = parse_base64_string(file_content);
            file.write(file_data);
            log(LoggerLevel::DEBUG, "%s: wrote %d bytes", dirname + file_name, file_data.size());

            return dir.path() + Qore::DirSep + file_name;
        } catch (hash<auto> ex) {
            log(LoggerLevel::DEBUG, "Exception: %y", ex);

            {
                AutoLock auto_lock(processMutex);
                status += {"status": STATUS_FAILED, "exit_code": 1, "stderr": ex.desc, "stdout": ""};
            }

            return NOTHING;
        }
    }

    #! Uploading state: files are saved to the file system
    private uploading() {
        {
            AutoLock auto_lock(processMutex);
            status += {"status": STATUS_UPLOADING, "stdout": "files are uploading"};
        }

        hash<auto> file = uploadRequest.files[filesIt];
        int file_size = uploadRequest.files.size();

        *string file_path = createFile(file.file_name, file.file_content);

        if (!exists file_path) {
            execute(FAIL);
            return;
        }

        filesIt++;
        if (filesIt != file_size) {
            execute(NEXT_FILE);
        } else {
            {
                AutoLock auto_lock(processMutex);
                status += {"status": STATUS_UPLOADED, "stdout": "files are uploaded"};
            }
            execute(DONE);
        }
    }

    #! log method; includes the request info in the log message
    private log(int log_level, string format) {
        string prefix = sprintf("ID %d (files: %s user: %s) ",
                                uploadRequest.id,
                                uploadRequest.files.size(),
                                uploadRequest.user);
        qlog(log_level, vsprintf(prefix + format, argv));
    }
}
