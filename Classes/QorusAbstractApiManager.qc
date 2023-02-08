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

public namespace OMQ {
hashdecl ApiOptionInfo {
    string type;
    string desc;
    auto default_value;
    *list<auto> allowed_values;
    bool required = False;
}

class QorusAbstractApiManager {
    public {
        #! Options per API profile
        const ApiProfileOptionsMap = {
            "rest": QorusSwaggerApiManager::ProfileOptions,
            "soap": QorusSoapApiManager::ProfileOptions,
        };
    }

    private {
        #! weak reference to Qorus service
        LocalQorusService service;

        #! Qorus API profile in use
        string api_profile;

        #! endpoint map; endpoint -> {call_type, name}
        hash<string, hash<auto>> endpoint_map;
    }

    constructor(LocalQorusService service, hash<auto> api_manager) {
        self.service := service;

        AbstractDataProviderFactory factory = DataProvider::getFactoryEx(api_manager.factory);
        hash<DataProviderFactoryInfo> info = factory.getInfo();
        if (!info.api_management) {
            throw "SERVICE-ERROR", sprintf("service requires API management factory %y, however it does not support "
                "API management", api_manager.factory);
        }
        if (!info.api_profiles) {
            throw "SERVICE-ERROR", sprintf("data provider factory %y does not support any API profiles",
                api_manager.factory);
        }
        api_profile = checkApiProfile(map {$1: True}, info.api_profiles);

        *hash<string, hash<ApiOptionInfo>> api_option_info = ApiProfileOptionsMap{api_profile};
        if (!api_option_info) {
            throw "SERVICE-ERROR", sprintf("data provider factory %y API profile %y is not supported by Qorus; "
                "supported API profiles: %y", factory, api_profile, keys ApiProfileOptionsMap);
        }

        # create data provider
        hash<auto> opts = (map {$1.key: $1.value.value}, api_manager."provider-options".pairIterator()) ?? {};
        *hash<auto> provider_options = remove opts{keys info.provider_info.constructor_options};
        AbstractDataProvider provider = factory.create(provider_options);

        # process API options
        hash<auto> api_profile_options;
        foreach hash<auto> i in (api_option_info.pairIterator()) {
            auto val = remove opts{i.key};
            if (exists val) {
                string expected_type = i.value.type;
                expected_type =~ s/^\*//;
                if (val.type() != expected_type) {
                    switch (expected_type) {
                        case "data-provider":
                            val = UserApi::getDataProvider(val);
                            break;
                        default:
                            if (val.typeCode() != NT_STRING) {
                                throw "SERVICE-ERROR", sprintf("API profile %y for API management factory %y "
                                    "requires a string value for option %y, but a value of type %y was provided "
                                    "instead (%y)", api_profile, api_manager.factory, i.key, val.type(), val);
                            }
                    }
                }
            } else {
                if (exists i.value.default_value) {
                    val = i.value.default_value;
                } else if (i.value.type !~ /^\*/) {
                    throw "SERVICE-ERROR", sprintf("API profile %y for API management factory %y requires option %y, "
                        "but no such option value was supplied", api_profile, api_manager.factory, i.key);
                }
            }
            api_profile_options{i.key} = val;
        }
        if (opts) {
            throw "SERVICE-ERROR", sprintf("extra option%s %y provided to API management factory %y (API profile %y)",
                opts.size() == 1 ? "" : "s", keys opts, api_manager.factory, api_profile);
        }

        # get and verify endpoints from data provider and set up endpoint map
        {
            list<hash<auto>> endpoints = ();
            # scan data provider for request-response endpoints
            scanProviderForApiEndpoints(\endpoints, "/", provider, False);

            endpoint_map = map {$1.endpoint: $1 - "endpoint"}, endpoints;

            # ensure all endpoints declared in the service exist
            foreach hash<auto> endpoint_info in (api_manager.endpoints) {
                reference<*hash<auto>> ep = \endpoint_map{endpoint_info.endpoint};
                if (!exists ep) {
                    throw "SERVICE-ERROR", sprintf("endpoint %y referenced in service is not defined by API "
                        "management provider %y of type %y; known endpoints: %y", endpoint_info.endpoint,
                        provider.getName(), provider.className(), keys endpoint_map);
                }
                switch (endpoint_info.type) {
                    case "method":
                        ep += {
                            "call_type": "method",
                            "name": endpoint_info.value,
                        };
                        break;

                    case "fsm":
                        ep += {
                            "call_type": "fsm",
                            "name": endpoint_info.value,
                        };
                        break;

                    default:
                        throw "SERVICE-ERROR", sprintf("endpoint %y referenced in service does not declare either a "
                            "method or an FSM: %y", endpoint_info.endpoint, endpoint_info);
                }
            }
        }

        setupServiceImpl(factory, provider, api_profile_options);
    }

    private setupService(AbstractDataProviderFactory factory, AbstractDataProvider provider,
            *hash<auto> api_profile_options) {
        ServiceApi::logInfo("setting up %s API manager for endpoints: %y", factory.getName(), keys endpoint_map);
        setupServiceImpl(factory, provider, api_profile_options);
    }

    #! Returns the data provider from the given factory as well as api profile options
    static AbstractDataProvider getDataProvider(AbstractDataProviderFactory factory, *hash<auto> constructor_opts) {
        hash<DataProviderFactoryInfo> info = factory.getInfo();
        if (!info.api_management) {
            throw "API-FACTORY-ERROR", sprintf("context requires API management factory %y, however it does not "
                "support API management", factory.getName());
        }
        if (!info.api_profiles) {
            throw "API-FACTORY-ERROR", sprintf("data provider factory %y does not support any API profiles",
                factory.getName());
        }

        string api_profile = info.api_profiles[0];
        hash<string, hash<ApiOptionInfo>> api_option_info = ApiProfileOptionsMap{api_profile};
        if (!api_option_info) {
            throw "API-FACTORY-ERROR", sprintf("data provider factory %y API profile %y is not supported by Qorus; "
                "supported API profiles: %y", factory.getName(), api_profile, keys ApiProfileOptionsMap);
        }

        # create data provider
        *hash<auto> provider_options = _priv_get_provider_constructor_options(factory.getName(),
            constructor_opts, info.provider_info.constructor_options);
        QDBG_LOG("QorusAbstractApiManager::getDataProvider() factory %y opts %y (%y) -> %y", info.name,
            constructor_opts, keys info.provider_info.constructor_options, provider_options);
        return factory.create(provider_options);
    }

    static hash<string, hash<ApiOptionInfo>> getOptionsForApiManagement(string factory_name, *string api_profile) {
        AbstractDataProviderFactory factory = DataProvider::getFactoryEx(factory_name);
        hash<DataProviderFactoryInfo> info = factory.getInfo();
        if (!info.api_management) {
            throw "FACTORY-ERROR", sprintf("data provider factory %y does not support API management", factory_name);
        }
        if (!info.api_profiles) {
            throw "FACTORY-ERROR", sprintf("data provider factory %y does not support any API profiles", factory_name);
        }
        if (api_profile) {
            hash<string, bool> api_profile_map = map {$1: True}, info.api_profiles;
            if (!api_profile_map{api_profile}) {
                throw "FACTORY-ERROR", sprintf("data provider factory %y does not support API profile %y; API "
                    "profiles supported: %y", factory_name, api_profile, info.api_profiles);
            }
        } else {
            api_profile = info.api_profiles[0];
        }
        *hash<string, hash<ApiOptionInfo>> api_option_info = ApiProfileOptionsMap{api_profile};
        if (!api_option_info) {
            throw "FACTORY-ERROR", sprintf("data provider factory %y API profile %y is not supported by Qorus; "
                "supported API profiles: %y", factory_name, api_profile, keys ApiProfileOptionsMap);
        }
        return api_option_info;
    }

    private scanProviderForApiEndpoints(reference<list<hash<auto>>> rv, string path, AbstractDataProvider provider,
            bool soft = False) {
        if (provider.supportsRequest()) {
            rv += getEndpointInfo(path, provider);
        }

        # scan children
        map scanProviderForApiEndpoints(\rv, path == "/" ? path + $1 : path + "/" + $1,
            provider.getChildProviderEx($1)), provider.getChildProviderNames();
    }

    private hash<auto> getEndpointInfo(string path, AbstractDataProvider provider) {
        return {
            "endpoint": path,
        };
    }

    private abstract string checkApiProfile(hash<string, bool> api_profile_map);

    private abstract setupServiceImpl(AbstractDataProviderFactory factory, AbstractDataProvider provider,
            *hash<auto> api_profile_options);
}
}