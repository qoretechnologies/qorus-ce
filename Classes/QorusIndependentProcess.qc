# -*- mode: qore; indent-tabs-mode: nil -*-

/*
    Qorus Integration Engine(R) Community Edition

    Copyright (C) 2003 - 2023 Qore Technologies, s.r.o., all rights reserved

    LICENSE: Creative Commons Attribution-ShareAlike 4.0 International

    https://creativecommons.org/licenses/by-sa/4.0/legalcode
*/

%new-style
%enable-all-warnings
%strict-args
%require-types

class QorusIndependentProcess inherits QorusMasterCoreQsvcCommon {
    public {
        # machine page size in bytes
        const MachinePageSize = sysconf(SC_PAGESIZE);
    }

    private {
        #! termination flag
        bool terminate;

        #! total private memory for the current node
        int total_private_memory = 0;

        #! total system memory in bytes (note: contants are initialized first in static initialization)
        int machine_ram_total = sysconf(SC_PHYS_PAGES) * MachinePageSize;

        #! CPU load percent over the last 60 seconds; load / CPU count
        float machine_load_pct = 0;

        #! CPU load
        list<float> machine_load_avg = Process::getLoadAvg();

        #! number of CPUs
        int machine_cpus = sysconf(SC_NPROCESSORS_ONLN);

        #! system memory in use in bytes
        int machine_ram_in_use = 0;

        #! memory history; node memory info list
        list<hash<auto>> mem_history;

        #! monitor thread counter
        Counter monitor_cnt();

        #! monitor lock
        Mutex monitor_lck();

        #! monitor condition variable
        Condition monitor_cond();

        #! information to be used to deliver the STOP acknowledgement message
        hash<auto> stop_info;

        #! Process information about the current active master
        hash<ClusterProcInfo> master_proc_info;

        #! polling interval for an active qorus-master process
        const MasterPollingInterval = 1s;

        #! timeout for registering with the active master
        const MasterRegistrationTimeout = 20s;

        #! monitor polling interval
        const ProcessMonitoringPollingInterval = 10s;

        #! number of history entries for memory and process counts (60 * 10s = 10 minutes)
        const HistoryDepth = 60;
    }

    private monitor() {
        on_exit {
            monitor_cnt.dec();
            logCommonInfo("stopped process memory monitor thread");
        }

        logCommonInfo("started process memory monitor thread");

        while (!terminate) {
            # total system memory in bytes (in case it changes while running; hotplugging RAM
            # is possible on some VMs at least)
            int current_mem = sysconf(SC_PHYS_PAGES) * MachinePageSize;
            if (current_mem != machine_ram_total) {
                logCommonInfo("total physical system memory changed from %s to %s",
                    get_byte_size(machine_ram_total), get_byte_size(current_mem));
                machine_ram_total = current_mem;
            }

            # check for changed CPU count
            int current_cpus = sysconf(SC_NPROCESSORS_ONLN);
            if (current_cpus != machine_cpus) {
                logCommonInfo("total CPUs changed from %s to %s", machine_cpus, current_cpus);
                machine_cpus = current_cpus;
            }

%ifndef DARWIN
            # issue #2403: get RAM in use; API not supported on Darwin
            machine_ram_in_use = current_mem - (sysconf(SC_AVPHYS_PAGES) * MachinePageSize);
%else
            # on Darwin we have to use vm_stat :(
            machine_ram_in_use = current_mem - ((`vm_stat` =~ x/Pages free:\s+([0-9]+)/m)[0].toInt() * MachinePageSize);
%endif
            # issue #2402: get load average
            machine_load_avg = Process::getLoadAvg();
            machine_load_pct = machine_load_avg[0] / machine_cpus * 100.0;
            hash<MemorySummaryInfo> pi = Process::getMemorySummaryInfo();
            total_private_memory = pi.priv;

            node_memory_info = {
                "node_priv": total_private_memory,
                "node_priv_str": get_byte_size(total_private_memory),
                "node_ram_in_use": machine_ram_in_use,
                "node_ram_in_use_str": get_byte_size(machine_ram_in_use),
                "node_cpu_count": machine_cpus,
                "node_load_pct": machine_load_pct,
            };

            mem_history += node_memory_info + {
                "timestamp": now_us(),
            };

            # trim off excess history entries
            if (mem_history.size() > HistoryDepth) {
                splice mem_history, HistoryDepth;
            }

            monitorLoopImpl();

            # sleep for polling period
            QorusSharedApi::waitConditionLock(monitor_cond, monitor_lck, ProcessMonitoringPollingInterval, \terminate);
        }
    }

    synchronized stopIndependent() {
        QDBG_ASSERT(terminate);
        {
            monitor_lck.lock();
            on_exit monitor_lck.unlock();

            monitor_cond.broadcast();
        }
        monitor_cnt.waitForZero();
    }

    #! Called each iteration of the monitor loop
    private monitorLoopImpl() {
        # this method intentionally left empty
    }

    private openIndependentQorusDatasource(string systemdb) {
        if (!omqds) {
            omqds = new Datasource(systemdb);
        }
    }

    #! returns node memory info for inter-master memory reporting
    private hash<auto> getNodeMemoryInfo() {
        return node_memory_info + {
            "machine_ram_total": machine_ram_total,
            "machine_load_pct": machine_load_pct,
        };
    }
}
