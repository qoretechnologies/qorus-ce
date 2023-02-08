# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%require-types
%strict-args

class OMQ::QorusMappers inherits OMQ::Mappers {
    private {
        # separate lock for atomic interruption of reloadService
        Mutex m();
        Condition rcond();
        bool reloading;
        int wait_count;
        bool shutdown_flag;
        static hash<string, bool> load_map;
    }

    shutdown() {
        m.lock();
        on_exit m.unlock();

        #printf("0: QorusMappers::shutdown() reloading: %y shutdown_flag: %y wait_count: %y\n", reloading, shutdown_flag, wait_count);
        shutdown_flag = True;
        while (reloading) {
            ++wait_count;
            rcond.wait(m);
            --wait_count;
        }
        #printf("1: QorusMappers::shutdown() reloading: %y shutdown_flag: %y wait_count: %y\n", reloading, shutdown_flag, wait_count); flush();
    }

    private setupIntern(*list<auto> mml) {
        # add external connection handlers
        foreach string mod in (mml) {
            # when qorus-core is restarted in independent mode, do not try to load modules twice
            if (load_map{mod}) {
                continue;
            }
            load_map{mod} = True;
            try {
                list<auto> sl = addMapperTypeProvider(mod);
                olog(LoggerLevel::INFO, "loaded user mapper provider module %y handling: %y", mod, sl);
            } catch (hash<ExceptionInfo> ex) {
                *string desc = !Qorus.getDebugSystem() ? ex.desc : Util::get_exception_string(ex);
                olog(LoggerLevel::FATAL, "failed to load user mapper provider module %y: %s: %s", mod, ex.err, desc);
            }
        }
    }

    reloadMappers(softlist<auto> mlist) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        foreach hash<auto> mmh in (mlist) {
            remove mh{mmh.mapperid};
            reloadMapperIntern(mmh, NOTHING, True);
        }
    }

    reloadMapper(hash<auto> mmh) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        remove mh{mmh.mapperid};
        reloadMapperIntern(mmh, True, True);
    }

    private loadMapperModule(Program pgm, string mod) {
        *hash<ExceptionInfo> warn = pgm.loadApplyToUserModuleWarn(mod);
        if (warn) {
            doProviderWarning(mod, warn);
        }
    }

    private doProviderWarning(string mod, hash<ExceptionInfo> warn) {
        olog(LoggerLevel::INFO, "warning loading mapper provider module %y: %s: %s: %s", mod, get_ex_pos(warn), warn.err, warn.desc);
        if (warn.next) {
            doProviderWarning(mod, warn.next);
        }
    }

    /*
    reloadMapper(int mapperid) {
        *hash mmh = Qorus.qmm.lookupMapper(mapperid);
        if (!mmh)
            throw "MAPPER-ERROR", sprintf("mapperid %d does not exist", mapperid);

        reloadMapper(mmh);
    }
    */

    # mmh: as returned from Qorus map mmap{mapperid}
    private reloadMapperIntern(hash<auto> mmh, *bool log_reload, *bool clear_deps) {
%ifdef QorusCore
        if (clear_deps) {
            # clear mapper dependencies
            Qorus.clearMapperDependencies(mmh.mapperid);
        }
%endif

        *AbstractMapperType mt;
        try {
            mt = sh.(mmh.type);
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "%s: error in mapper %y v%s (%d): %s: %s", get_ex_pos(ex), mmh.name, mmh.version, mmh.mapperid, ex.err, ex.desc);
        }

        string err;
        if (!mt) {
            mt = new InvalidMapperType(mmh.type);
            err = sprintf("mapper %y v%s (%d) refers to unknown mapper type %y; known mapper types: %y", mmh.name, mmh.version, mmh.mapperid, mmh.type, sh.keys());
            olog(LoggerLevel::INFO, err + "; this mapper will be marked as invalid");
        }
        ServerMapperContainer m;
        try {
            m = new ServerMapperContainer(mmh.mapperid, mmh.name, mmh.version, mmh.patch, mmh.description, mt,
                                          mmh.parse_options, mmh.fields, mmh.options, mmh.created, mmh.modified,
                                          mmh.is_yaml.toBool());
            if (log_reload)
                olog(LoggerLevel::INFO, "successfully reloaded mapper %y v%s (%d)", mmh.name, mmh.version, mmh.mapperid);
        } catch (hash<ExceptionInfo> ex) {
            olog(LoggerLevel::INFO, "%s: error in mapper %y v%s (%d): %s: %s", get_ex_pos(ex), mmh.name, mmh.version, mmh.mapperid, ex.err, ex.desc);
            err = sprintf("mapper %y v%s (%d) of type %y could not be loaded: %s: %s", mmh.name, mmh.version, mmh.mapperid, mmh.type, ex.err, ex.desc);
            olog(LoggerLevel::INFO, err + "; this mapper will be marked as invalid");
            olog(LoggerLevel::INFO, "DBG: " + get_exception_string(ex));
            # the following call cannot raise an exception; if so, it's a bug
            m = new ServerMapperContainer(mmh.mapperid, mmh.name, mmh.version, mmh.patch, mmh.description,
                                          new InvalidMapperType(mmh.type), mmh.parse_options, mmh.fields, mmh.options,
                                          mmh.created, mmh.modified, mmh.is_yaml.toBool(), True);
        }
        mh.(mmh.mapperid) = m;
        if (err)
            m.setError(err);
    }

    reloadDelta(list<auto> ids) {
        rwl.writeLock();
        on_exit rwl.writeUnlock();

        map reloadMapperIntern($1, NOTHING, True), Qorus.getMapperMap(){ids}.iterator();
    }

    private reloadIntern(*softlist<auto> ids) {
        {
            m.lock();
            on_exit m.unlock();

            if (shutdown_flag)
                return;
            reloading = True;
        }

        on_exit {
            m.lock();
            on_exit m.unlock();

            reloading = False;
            if (wait_count)
                rcond.broadcast();
        }

        *hash<auto> h;

        if (ids) {
            remove mh{ids};
            h = Qorus.getMapperMap(){ids};
        } else {
%ifdef QorusCore
            Qorus.clearAllMapperDependencies();
%endif
            mh = new hash<string, MapperContainerBase>();
            h = Qorus.getMapperMap();
        }

        foreach hash<auto> nmh in (h.iterator()) {
            reloadMapperIntern(nmh, NOTHING, exists ids);
            if (shutdown_flag)
                break;
        }
    }

    # called in the read lock
    private Mapper getIntern(softstring mapperid, *hash<auto> rtopts) {
        # if we have an invalid mapper then we need to try and reload it again in case it can be loaded now
        ServerMapperContainer smc = getMapperContainer(mapperid);
        if (!smc.valid()) {
            # first release the read lock
            rwl.readUnlock();
            on_exit rwl.readLock();
            # now grab the write lock
            rwl.writeLock();
            on_exit rwl.writeUnlock();

            # check the mappper container again
            ServerMapperContainer smc2 = getMapperContainer(mapperid);
            # try to reload the mapper as long as it hasn't been reloaded in the meantime
            if (smc == smc2) {
                # get the mapper description
                *hash<auto> mmh = Qorus.qmm.lookupMapper(mapperid);
                if (mmh) {
                    # unload the current mapper
                    delete mh{mapperid};
                    # create the new mapper
                    reloadMapperIntern(mmh, True, True);
                    smc = mh{mapperid};
                }
            } else {
                smc = smc2;
            }
        }

        return smc.create(rtopts);
    }
}
