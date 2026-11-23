// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

#include "MothBenchmark.h"
#include <sys/resource.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <unistd.h>
#include <string.h>
int moth_benchmark_metrics(pid_t pid, MothProcessMetrics *result) {
 memset(result,0,sizeof(*result));
 struct rusage_info_v6 info; memset(&info,0,sizeof(info));
 int status=proc_pid_rusage(pid,RUSAGE_INFO_V6,(rusage_info_t *)&info);
 if(status) { memset(&info,0,sizeof(info)); status=proc_pid_rusage(pid,RUSAGE_INFO_V4,(rusage_info_t *)&info); }
 else result->energy_supported=1;
 if(status) return status;
 result->cpu_ns=info.ri_user_time+info.ri_system_time;
 // The benchmark process can also use getrusage's explicitly specified timeval units.
 if(pid==getpid()) { struct rusage own; if(!getrusage(RUSAGE_SELF,&own)) result->cpu_ns=((uint64_t)own.ru_utime.tv_sec+(uint64_t)own.ru_stime.tv_sec)*1000000000ULL+((uint64_t)own.ru_utime.tv_usec+(uint64_t)own.ru_stime.tv_usec)*1000ULL; }
 result->physical_bytes=info.ri_phys_footprint; result->resident_bytes=info.ri_resident_size;
 result->peak_physical_bytes=info.ri_lifetime_max_phys_footprint;
 result->interrupt_wakeups=info.ri_interrupt_wkups; result->package_idle_wakeups=info.ri_pkg_idle_wkups;
 result->energy_nj=info.ri_energy_nj;
 mach_timebase_info_data_t clock; mach_timebase_info(&clock);
 result->process_start_seconds=(double)info.ri_proc_start_abstime*(double)clock.numer/(double)clock.denom/1e9;
 return 0;
}
