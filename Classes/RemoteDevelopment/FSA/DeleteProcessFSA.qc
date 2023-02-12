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

/** Remote development delete finite state automation.

    Design info: https://bugs.qoretechnologies.com/projects/qorus/wiki/Qorus_remote_development

    It's a Qorus private class - not exposed to public API.
*/

class RemoteDevelopment::DeleteProcessFSA inherits ProcessFSA {
    private {
        const ALLOWED_OPTIONS = {
            "allow-redef": "Allows dangerous workflow redefinitions (for dev only)",
            "reload": "Reload interfaces in the server",
            "verbosity-level": "Sets verbosity level (greater value = more info)"
        };
        const OPTIONS_TO_OLOAD_ARGS = {
            "allow-redef": "A",
            "reload": "R",
            "verbosity-level": "v"
        };

        DeleteRequest deleteRequest;
    }

    #! Constructs DeleteProcessFSA object with given request
    #  Initialize method must be called to initialize the FSA (ProcessFSA method).
    /** @param request containing interfaces to be deleted
        @throw BAD-REQUEST exception in case request is incorrect
        */
    constructor(DeleteRequest request) : ProcessFSA("oload") {
        deleteRequest = request;
        OptionHelper::checkOptions(deleteRequest.options, ALLOWED_OPTIONS);
    }

    # ProcessFSA method
    private list<string> getProcessArgs() {
        list<string> args;

        args += OptionHelper::convertOptionsToOloadArguments(deleteRequest.options, OPTIONS_TO_OLOAD_ARGS);
        foreach Interface interface in (deleteRequest.interfaces) {
            # try to disable object first, if supported
            *string disable_path = interface.getDisableUriPath();
            if (disable_path) {
                QDBG_LOG("disabling interface before deletion: %y", disable_path);
                try {
                    UserApi::callRestApi("PUT", disable_path);
                } catch (hash<ExceptionInfo> ex) {
                    if (ex.arg != 404) {
                        log(LoggerLevel::INFO, "failed to disable interface %y: %s", disable_path, get_exception_string(ex));
                    }
                }
            }

            args += interface.id ? "--delete-id" : "-X";
            args += interface.getIdentifier();
        }
        return args;
    }
    ###
}
