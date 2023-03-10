# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2022 Qore Technologies, s.r.o., all rights reserved

    LICENSE: GNU GPLv3

    https://www.gnu.org/licenses/gpl-3.0.en.html
*/

%new-style

# public user APIs
public namespace OMQ {
    public namespace UserApi {
        public namespace Service {
            *hash sub svc_try_get_wf_static_data() {
                return SM.tryGetStaticData();
            }

            *hash sub svc_try_get_wf_dynamic_data() {
                return SM.tryGetDynamicData();
            }

            *hash sub svc_try_get_wf_temp_data() {
                return SM.tryGetTempData();
            }
        }
    }

    auto sub get_workflow_option() {
        QDBG_ASSERT(tld.index);
        return WorkflowApi::getOptionArgs(argv);
    }
}
