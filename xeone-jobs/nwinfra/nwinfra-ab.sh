#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job R: wip/x264-nw-infra (tip 2464038e): hpel writes its own side pads,
# MBAFF hpel to the field plane, lowres pads inside frame_init_lowres_core, one-pass expand_border_sides (kernels),
# and the threading items (one wake per job, keyframe analysis outside ofbuf.mutex, slice 0 on the caller).
# From core3-jobs/nwinfra/nwinfra-ab.sh: same arms and NWCNT counters (nwcnt.sh beside this script, counter tree =
# the whole series 2464038e for every AB); perf pinned with x264, no /usr/bin/time.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=asm bash nwinfra-ab.sh build | live | md5 | time 9 | report
#   AB=thr bash nwinfra-ab.sh build | md5 | nondet 20 | time 9 | report
# AB (default asm):
#   asm      base = 8df5d016 (all kernels assembled, undispatched), arm = 2464038e (hpel dual/copy_vc, lowres pad,
#            expand_border_sides, hpel side pads dispatched). t1 cells.
#   hpel     base = 8df5d016, arm = a27a3925 (hpel_filter_dual + copy_vc only: MBAFF only, -p cells are null)
#   lowres   base = a27a3925, arm = 60e2dd6c (frame_init_lowres_core_pad only)
#   sides    base = 60e2dd6c, arm = fbcb12be (expand_border_sides only)
#   hpelpad  base = fbcb12be, arm = 2464038e (hpel_filter_pad: hpel writes the filtered side pads)
#   thr      base = 42c3f783 (speed-next), arm = 790c3e79 (threading items). t1 + t4 + t4la4 (obed's 4 lookahead
#            threads) cells; the threaded cells run on CORES=12,14 only (4 threads on 2 cpus: cycles:u is total
#            CPU work, duration_time the wall time; the 4-cpu Core 3 / rack01 cells are not reproducible here).
# The sgfades cells of the Core 3 script are dropped (no sgfades here); fades-p / fades-i 60 frames are md5 cells.
set -u
JOB=nwinfra; AB=${AB:-asm}; BRANCHES=wip/x264-nw-infra
T1="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal"
CELLS=$T1; NULLCELLS=""
case $AB in
asm)     BASE=8df5d016; ARM=2464038e ;;
hpel)    BASE=8df5d016; ARM=a27a3925; NULLCELLS="tile-chaos-p_lowlat tile-chaos-p_normal" ;;
lowres)  BASE=a27a3925; ARM=60e2dd6c ;;
sides)   BASE=60e2dd6c; ARM=fbcb12be ;;
hpelpad) BASE=fbcb12be; ARM=2464038e ;;
thr)     BASE=42c3f783; ARM=790c3e79; EVENTS=cycles:u,instructions:u,duration_time
         CELLS="$T1 tile-chaos-p:lowlat_t4 tile-chaos-p:normal_t4 field-frame-mix-i:lowlat_t4 field-frame-mix-i:normal_t4
                tile-chaos-p:normal_t4la4 field-frame-mix-i:normal_t4la4" ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-p:normal:60 fades-i:normal:60 fades-p:lowlat:60 fades-i:lowlat:60"
LIVE_RE='hpel_filter|frame_init_lowres|expand_border|frame_filter|threadpool|slicetype_slice_cost'
COUNT_TREES=armcnt; SHA_armcnt=2464038e; COUNT_RE=NWCNT
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
MODE_lowlat_t4=${LOWLAT/--threads 1/--threads 4}; MODE_normal_t4=${NORMAL/--threads 1/--threads 4}
MODE_lowlat_t4la4="$MODE_lowlat_t4 --lookahead-threads 4"; MODE_normal_t4la4="$MODE_normal_t4 --lookahead-threads 4"
COUNTCELLS="$T1 field-frame-mix-i:normal_t4la4 fades-p:normal:60"
xe_patch() { case $1 in *cnt) sh $HERE/nwcnt.sh $PWD || return 1 ;; esac; }
xe_bench() {
    (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=hpel 1001 | grep -E "^hpel|nop"
     taskset -c $CORE ./checkasm8 --bench=lowres 1001 | grep -E "^lowres|^frame_init"; taskset -c $CORE ./checkasm8 --bench=expand_border 1001 | grep -E "^expand")
}
XE_PHASES="nondet [N]"
xe_phase_nondet() { # threaded cells: N repeats of base and arm, distinct bitstreams within each (1 1 = pass)
    local N=${1:-20} spec a i nb na nr; mkdir -p $W/out
    for spec in tile-chaos-p:normal_t4 field-frame-mix-i:normal_t4 tile-chaos-p:normal_t4la4 field-frame-mix-i:normal_t4la4 \
                field-frame-mix-i:lowlat_t4 fades-p:normal_t4la4:60; do xe_cell $spec; [ -f $CL ] || continue
        for a in base arm; do
            xe_run $a m $spec nd_${a}_1 --dump-yuv $W/out/ndrec_$a.yuv
            for i in $(seq 2 $N); do xe_run $a m $spec nd_${a}_$i; done
        done
        nb=$(md5sum $W/out/nd_base_*.264 | awk '{print $1}' | sort -u | wc -l)
        na=$(md5sum $W/out/nd_arm_*.264 | awk '{print $1}' | sort -u | wc -l)
        nr=$(md5sum $W/out/ndrec_base.yuv $W/out/ndrec_arm.yuv | awk '{print $1}' | sort -u | wc -l)
        echo "$CN: $N runs per arm, distinct bitstreams within base $nb within arm $na, recon base vs arm distinct $nr (1 1 1 = pass)"
        rm -f $W/out/nd_* $W/out/ndrec_*
    done
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
