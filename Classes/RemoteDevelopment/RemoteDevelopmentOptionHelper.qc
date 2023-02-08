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

#! Helper class allows to check options and convert options to oload arguments
public class RemoteDevelopment::OptionHelper {
    public {
        const MAX_VERBOSITY_LEVEL = 10;
    }

    #! Checks RemoteDevelopment options
    /** @param options hash containing options to check
        @param allowed_options hash containing allowed options
        @throw BAD-REQUEST in case any option from the options is not present in allowed_options
        */
    static checkOptions(*hash<auto> options, hash<auto> allowed_options) {
        foreach string option in (keys options) {
            if (!exists allowed_options{option}) {
                string err = sprintf("Unknown option: %s; known options: %N", option, allowed_options);
                throw "BAD-REQUEST", err;
            }
        }
    }

    #! Converts options to oload arguments
    /** @param options hash containing options to be converted
        @param options_to_oload_args mapping from options to oload arguments
        @return list<string> of oload arguments
    */
    static list<string> convertOptionsToOloadArguments(*hash<auto> options, hash<auto> options_to_oload_args) {
        list<string> result();
        foreach string option_key in (keys options) {
            if (option_key == "verbosity-level" && options{option_key} > 010) {
                result += "-" + strmul(options_to_oload_args{option_key}, min(options{option_key},
                                                                              MAX_VERBOSITY_LEVEL));
            } else if (options{option_key} && options_to_oload_args.hasKey(option_key)) {
                result += "-" + options_to_oload_args{option_key};
            }
        }
        QDBG_LOG("OptionHelper:convertOptionsToOloadArguments() result: %y options: %y options_to_oload_args: %y",
            result, options, options_to_oload_args);
        return result;
    }
}
