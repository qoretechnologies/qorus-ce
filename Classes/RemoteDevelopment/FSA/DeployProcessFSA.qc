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

/** Remote deployment finite state automation.

    Design info: https://bugs.qoretechnologies.com/projects/qorus/wiki/Qorus_remote_development

    It's a Qorus private class - not exposed to public API.
*/

class RemoteDevelopment::DeployProcessFSA inherits RemoteDevelopment::FileUploadProcessFSA {
    private {
        const ALLOWED_OPTIONS = {
            "allow-redef": "Allows dangerous workflow redefinitions (for dev only)",
            "force": "Force schema verification/downgrade with user schemas",
            "validate": "Validate all functions recursively",
            "reload": "Reload interfaces in the server",
            "verbosity-level": "Sets verbosity level (greater value = more info)"
        };
        const OPTIONS_TO_OLOAD_ARGS = {
            "allow-redef": "A",
            "force": "f",
            "validate": "l",
            "reload": "R",
            "verbosity-level": "v"
        };

        DeployRequest deployRequest;
    }

    #! Constructs DeployProcessFSA object with given request
    #  Initialize method must be called to initialize the FSA (ProcessFSA method).
    /** @param request containing files to deployed, id of the request, user name and options

        @throw BAD-REQUEST exception in case request is incorrect
    */
    constructor(DeployRequest request) : FileUploadProcessFSA(request) {
        deployRequest = request;
        OptionHelper::checkOptions(deployRequest.options, ALLOWED_OPTIONS);
    }

    # RemoteDevelopment::FileUploadProcessFSA method
    private string getDestinationFolder() {
        string omq_dir = ENV.OMQ_DIR;
        if (omq_dir.empty()) {
            log(LoggerLevel::DEBUG, "OMQ_DIR variable is not initialized");
            throw "ENV-ERROR", "OMQ_DIR variable is not initialized";
        }
        return omq_dir + Qore::DirSep + "user" + Qore::DirSep;
    }

    # RemoteDevelopment::FileUploadProcessFSA method
    private string getDestinationFolderForFile(string file_path) {
        if (isModuleFile(file_path)) {
            return "modules";
        }
        return FileUploadProcessFSA::getDestinationFolderForFile(file_path);
    }
    ###

    private bool isModuleFile(string file_path) {
        return (file_path =~ /\.qm$/);
    }

    # ProcessFSA method
    private list<string> getProcessArgs() {
        list<string> args;

        args += OptionHelper::convertOptionsToOloadArguments(deployRequest.options, OPTIONS_TO_OLOAD_ARGS);
        foreach auto file in (deployRequest.files) {
            if (canBeDeployed(file.file_name)) {
                args += getDestinationFolder() + file.file_name;
            }
        }
        return args;
    }
    ###

    #! Checks if file can be deployed
    /** @param file_path path where to save, will be prefixed by OMQ_DIR environment variable
        @return True in case file can be deployed, False if not
    */
    private bool canBeDeployed(string file_path) {
        return (file_path =~ /\.(qfd|qwf|qsd|qjob|qclass|qconst|qconn|qmapper|qvmap|qsm|qrf|qscript|java|yaml)$/);
    }
}
