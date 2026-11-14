#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job MBP: wip/x264-nw-mbaffplanes 2d0dbfac (memfd double-maps the MBAFF
# field F/H planes onto the frame planes' pages: -4.16 MB written per MBAFF ref frame) vs c664d151 (copy path).
# Core 3 Job AA proved it bit-exact (15/15 single-thread cells, threaded at CQP) with aliasing live (maps, write
# counters, hpel_filter_copy -> hpel_filter_vc). Its costs: F/H lose THP (4K shmem pages), 2.8-4.5x page faults
# (5900 major per 30-frame encode), cycles:k +12-17 % lowlat. This is the Intel cycles verdict (E-2400 1080i goal).
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=full bash mbaffplanes/mbaffplanes-ab.sh build | live | md5 | time 9 | report
#   AB=lay  as full, both trees -falign-functions=64 (code-placement control, diagnostic only)
# Interlaced cells decide. Progressive cells allocate no field planes: they are the null control.
# FRAMES=120 is recommended for time (page-fault costs are per allocation; 30 frames over-weights start-up).
set -u
JOB=mbaffplanes; AB=${AB:-full}; BRANCHES=wip/x264-nw-mbaffplanes
case $AB in
full|lay) BASE=c664d151; ARM=2d0dbfac ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
EVENTS=${EVENTS:-cycles:u,instructions:u}
CELLS="field-frame-mix-i:normal field-frame-mix-i:lowlat credits-i:normal credits-i:lowlat ffm422-i:normal tile-chaos-p:normal pan-fast-p:lowlat"
NULLCELLS="tile-chaos-p_normal pan-fast-p_lowlat"
MD5CELLS="fades-i:normal:60 fades-i:lowlat:60 ffm422-i:lowlat"
LIVE_RE='hpel_filter|frame_filter|plane_copy|memcpy|frame_expand|cache_load_interlaced'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
xe_cflags() { [ $AB = lay ] && echo "-falign-functions=64"; }
xe_phase_faults() { # page-faults, major faults and cycles:k per arm, field-frame-mix-i normal + lowlat (3 reps)
    local c a r b
    for c in field-frame-mix-i:normal field-frame-mix-i:lowlat; do for a in base arm; do for r in 1 2 3; do
        b=$(xe_bin $a t); xe_cell $c
        taskset -c $CC perf stat -x, -e page-faults,major-faults,cycles:k,cycles:u -o $W/out/pf.txt -- $b $CO -o /dev/null $CL 2> /dev/null
        echo "$c $a rep $r: $(awk -F, '{ printf "%s %s  ", $3, $1 }' $W/out/pf.txt)"
    done; done; done
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
