// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: GPL-3.0-or-later
// Licensed under GNU GPL version 3 or later. See LICENSE.

#ifndef MOTH_BENCHMARK_H
#define MOTH_BENCHMARK_H
#include <stdint.h>
#include <sys/types.h>
typedef struct {
 uint64_t cpu_ns, physical_bytes, resident_bytes, peak_physical_bytes;
 uint64_t interrupt_wakeups, package_idle_wakeups, energy_nj;
 double process_start_seconds;
 int energy_supported;
} MothProcessMetrics;
int moth_benchmark_metrics(pid_t pid, MothProcessMetrics *result);
#endif
