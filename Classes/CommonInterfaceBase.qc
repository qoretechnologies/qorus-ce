# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%ifdef QorusServer
%enable-all-warnings
%strict-args
%require-types
%endif

public namespace OMQ;

#! Object cache entry hash
hashdecl ObjectCacheInfo {
    #! The timestamp the object was cached
    date timestamp = now_us();

    #! The object cached
    object obj;
}

#! Common interface code: common to workflows, services, and jobs
class OMQ::CommonInterfaceBase {
    public {
        #! Cache for Qore objects created from languages without deterministic GC
        /** the cache key is the object hash
        */
        hash<string, hash<ObjectCacheInfo>> object_cache;
    }

    #! Saves the object in the object cache
    saveObject(object obj) {
        object_cache{obj.uniqueHash()} = <ObjectCacheInfo>{"obj": obj};
    }

    #! Removes the object from the object cache
    /** @return True if the object was removed, False if it was not in the cache
    */
    bool clearObject(object obj) {
        return exists (remove object_cache{obj.uniqueHash()});
    }

    #! Returns the number of objects in the cache
    /** @return the number of objects in the cache
    */
    int cacheSize() {
        return object_cache.size();
    }

    #! Clears the entire object cache
    /** if cached objects are not referenced elsewhere, they will go out of scope

        @return the number of objects cleared
    */
    int clearCache() {
        return (remove object_cache).size();
    }

    #! Clears all entries in the object cache earlier than the given date/time
    /** if cached objects are not referenced elsewhere, they will go out of scope

        @param cutoff the cutoff date; objects saved in the cache earlier than this date will be cleared

        @return the number of objects cleared
    */
    int clearCache(date cutoff) {
        int rv = 0;
        foreach hash<auto> i in (object_cache.pairIterator()) {
            if (i.timestamp > cutoff) {
                break;
            }
            remove object_cache{i.key};
            ++rv;
        }
        return rv;
    }

    #! Returns the date/time the object was cached or @ref nothing if the object is not in the cache
    /** @param obj the object to check
    */
    *date checkCache(object obj) {
        return object_cache{obj.uniqueHash()}.timestamp;
    }

    #! Starts capturing objects from Java
    startCapturingObjectsFromJava() {
        Program pgm = getProgram();
        pgm.callFunction("jni::set_save_object_callback", \saveObject());
    }

    #! Stops capturing objects from Java
    stopCapturingObjectsFromJava() {
        Program pgm = getProgram();
        pgm.callFunction("jni::set_save_object_callback");
    }

    #! Starts capturing objects from Python
    startCapturingObjectsFromPython() {
        Program pgm = getProgram();
        pgm.callStaticMethod("PythonProgram", "setSaveObjectCallback", \saveObject());
    }

    #! Stops capturing objects from Python
    stopCapturingObjectsFromPython() {
        Program pgm = getProgram();
        pgm.callStaticMethod("PythonProgram", "setSaveObjectCallback");
    }

%ifdef QorusServer
    hash<auto> getAllOptions() {
        return getRuntimeOptionsImpl() ?? {};
    }

    *hash<auto> getOption() {
        return getRuntimeOptionsImpl();
    }

    auto getOption(softstring f) {
        *hash<auto> h = getRuntimeOptionsImpl();
        return h{f} ?? Qorus.options.get(f);
    }

    auto getLocalOption(softstring f) {
        *hash<auto> h = getRuntimeOptionsImpl();
        return h{f};
    }

    auto getOption(list<auto> field) {
        *hash<auto> h = getRuntimeOptionsImpl();

        if (!field) {
            return h;
        }

        if (field.size() == 1) {
            auto f = field[0];
            return h{f} ?? Qorus.options.get(f);
        }

        return map {$1: (h.$1 ?? Qorus.options.get($1))}, field;
    }

    setOption(hash<auto> h) {
        setOptionsImpl(h);
    }

    setOptions(hash<auto> h) {
        setOptionsImpl(h);
    }
%endif

    #! Returns the Program object containing the interface code
    abstract Program getProgram();

    #! Returns runtime options
    abstract *hash<auto> getRuntimeOptionsImpl();

    #! Sets options persistently
    abstract setOptionsImpl(hash<auto> h);
}
