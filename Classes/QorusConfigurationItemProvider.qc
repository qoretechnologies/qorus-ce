# -*- mode: qore; indent-tabs-mode: nil -*-
#! @file QorusConfigurationItemProvider.qc base class definition for class-based Qorus steps

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

#! Base class for object providing configuration items
/**
*/
public class OMQ::UserApi::QorusConfigurationItemProvider {
    #! Method to return local configuration items
    /** @return a hash of local configuration items

        This is executed by @ref oload "oload" when the object is loaded. The base class implementation returns no
        value.

        @note
        - If any configuration items have an invalid type, an error is raised
        - Child classes should override getConfigItemsImpl(); this method cannot be overridden
    */
    public final *hash<string, hash<ConfigItemInfo>> getConfigItems() {
        return getConfigItemsImpl();
    }

    #! Method to return local configuration items; this method should be overridden by child classes to provide item configuration
    /** @return a hash of local configuration items

        This is executed by getConfigItems() by @ref oload when the object is loaded into the system. The base class
        implementation is empty and returns no value.

        @note If any configuration items have an invalid type, an error is raised
    */
    *hash<string, hash<ConfigItemInfo>> getConfigItemsImpl() {
    }
}
