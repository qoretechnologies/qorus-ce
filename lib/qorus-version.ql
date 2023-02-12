# -*- mode: qore; indent-tabs-mode: nil -*-
# qorus-version.ql

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

public namespace OMQ {
    public const ProductName      = "Qorus Integration Engine(R) Community Edition";

    public const version_major    = 6;
    public const version_minor    = 0;
    public const version_sub      = 0;
    public const version_patch    = "";
    public const version_release  = "dev";
    public const datamodel        = "6.0.0.1";
    public const compat_datamodel = "6.0.0.1";
    public const load_datamodel   = "6.0.0.1";
    public const version_code     = version_major * 10000 + version_minor * 100 + version_sub;
    public const RestApiVersion   = 7;

    public const version = version_major + "." + version_minor + "." + version_sub
    	+ (version_patch.val() ? ("." + version_patch) : "")
	    + (version_release.val() ? ("_" + version_release) : "");

    #! hash giving minimum driver versions for the system ("omq") datasource
    public const MinSystemDBDriverVersion = {
        "oracle": "3.3.1",
        "pgsql": "3.2",
        "mysql": "2.1",
        "jni": "2.1",
        "odbc": "1.4",
    };

    # UI compatibility version (used e.g. by plugins)
    public const ui_compatibility_version = "1.0";
}
