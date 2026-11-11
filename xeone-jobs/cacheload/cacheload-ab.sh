#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job M: wip/x264-nw-cacheload (tip ab419b5c), x264_macroblock_cache_load's
# reference pointers from a per-slice table of bases (C, 312ea673) and the table add as one kernel
# (mb_fref_load avx2, dispatched at ab419b5c). No committed script existed; this follows the package report.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=c1 bash cacheload-ab.sh build | live | md5 | time 9 | report; then AB=k
# AB (default c1):
#   c1  the C table: base = 42c3f783 (speed-next), arm = 312ea673
#   k   the avx2 kernel: base = 1720dcb3 (tip~1: avx2 + avx512 kernels assembled, undispatched), arm = ab419b5c
# cache_load runs for every MB in every mode: there is no zero-call cell. Weighted refs (p_fref_w, the table's
# weighted-plane choice) need weightp content: fades-p / fades-i at 60 frames (no sgfades here) as md5 cells.
# Liveness: c1 = cache_load_* samples / instructions:u fall, macroblock_thread_init gains samples (one per slice);
# k = x264_8_mb_fref_load_avx2 samples in the arm, none in the base.
set -u
JOB=cacheload; AB=${AB:-c1}; BRANCHES=wip/x264-nw-cacheload
case $AB in
c1) BASE=42c3f783; ARM=312ea673 ;;
k)  BASE=1720dcb3; ARM=ab419b5c ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
CELLS="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal"
MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-p:normal:60 fades-i:normal:60 fades-p:lowlat:60 fades-i:lowlat:60"
LIVE_RE='cache_load|cache_save|thread_init|mb_fref_load'
. "$(dirname "$0")/../lib.sh"
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=mb_fref_load 1001 | grep -E 'mb_fref_load|nop'); }
# counters for c1 (the report's request): branch-misses beside cycles / instructions, base vs arm, normal cells
XE_PHASES=branches
xe_phase_branches() {
    mkdir -p $W/out; local spec a
    for spec in field-frame-mix-i:normal tile-chaos-p:normal fades-i:normal:60; do xe_cell $spec; [ -f $CL ] || continue
        for a in base arm; do
            taskset -c $CC perf stat -x, -e cycles:u,instructions:u,branch-misses:u -r 3 -o $W/out/br_$a.txt -- $(xe_bin $a t) $CO -o /dev/null $CL 2> /dev/null
            echo "$CN $a: $(awk -F, '$3 ~ /cycles|instructions|branch-misses/ { printf "%s %s; ", $3, $1 }' $W/out/br_$a.txt)"
        done
    done
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
