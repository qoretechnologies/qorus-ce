# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusPluginService.qc base class definition for Qorus plugin services

# Qorus Integration Engine

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

#! The base class for Qorus plugin services
public namespace OMQ {
    public namespace UserApi {
        public namespace Service {
            public class QorusPluginService inherits QorusSystemService {
                private static registerPlugin(string name) {
%ifdef QorusServer
                    # functionality is only available in Qorus server (doesn't make sense for client anyway)
                    ServiceApi::logInfo("Registering plugin '%s'.", name);
                    Qorus.qmm.registerPlugin(name);
%endif
                }

                private static deregisterPlugin(string name) {
%ifdef QorusServer
                    # functionality is only available in Qorus server (doesn't make sense for client anyway)
                    ServiceApi::logInfo("Deregistering plugin '%s'.", name);
                    Qorus.qmm.deregisterPlugin(name);
%endif
                }
            }
        }
    }
}
