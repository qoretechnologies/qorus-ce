# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file TempDataHelper.qc workflow helper class

# Qorus Integration Engine

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%strict-args
%require-types

public namespace OMQ {
    #! user API namespace root
    /** @see
        - @ref jobapi
        - @ref serviceapi
        - @ref workflowapi
        - @ref mapperapi
     */
    public namespace UserApi {
        #! Qorus workflow API namespace
        public namespace Workflow {
            #! This class is a helper class that allows @ref tempdata "workflow temp data" to be read and updated atomically; the write lock for the data is grabbed in the constructor and released in the destructor
            /** Calls to the following workflow API functions related to @ref tempdata "workflow temp data" can be
                made normally while this object exists and the write lock is held

                @note in %Python available as \c wf.TempDataHelper

                @since Qorus 3.1.0
             */
            final public class TempDataHelper inherits WorkflowDataHelper {
                #! creates the object and grabs the write lock for @ref tempdata "workflow temp data" during the lifetime of the object
                /** @throw LOCK-ERROR another TempDataHelper object exists in the same thread; only one object can be
                    used at a time since the object grabs the write lock
                */
                constructor() : WorkflowDataHelper(tld.wfe.tdata) {
                }

                #! replaces or erases the @ref tempdata "workflow temp data"
                /** @note There is currently no function equivalent to this method for
                    @ref tempdata "workflow temp data"; this method replaces all the data with \a new_data
                */
                nothing replace(*hash<auto> new_data) {
%ifdef QorusServer
                    data.replace(new_data);
%endif
                }

                #! adds data to @ref tempdata "workflow temp data"
                /**
                */
                nothing update(hash<auto> new_data) {
%ifdef QorusServer
                    data.update(new_data);
%endif
                }

                #! deletes one or more keys from @ref tempdata "workflow temp data"
                /**
                */
                nothing deleteKey(softlist keysv) {
%ifdef QorusServer
                    data.deleteKey(keysv);
%endif
                }
            }
        }
    }
}
