#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job U: wip/x264-nw-lapipe (tip b1d57371): the lookahead's frame costs as
# row-interleaved groups (b-adapt fast pairs, mbtree minigops) so lowres planes are read once per group, plus the
# lookahead_fpel API switch (off). From core3-jobs/lapipe/lapipe-ab.sh: same arms, LOWRES_TRAFFIC counter trees
# (test/x264-nw-lapipe-traffic) and the fpel quality phase; perf pinned with x264, no /usr/bin/time.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=grp bash lapipe-ab.sh build | live | md5 | nondet 20 | time 9 | report
# AB (default grp):
#   grp     item 3, bit-exact: base = 4e292d6a (speed-next), arm = b1d57371 (refactor + b-adapt group + mbtree group,
#           lookahead_fpel off). NORMAL carries the schedule change; LOWLAT must be md5-identical too (null cell:
#           zerolatency has no b-adapt and no mbtree).
#   refac   base = 4e292d6a, arm = 10443289 (frame cost in init / rows / finish, alone)
#   badapt  base = 10443289, arm = 435424dd (b-adapt fast pair group)
#   mbtree  base = 435424dd, arm = dc9122e0 (mbtree minigop group)
#   fpel    item 8, output-changing: base = b1d57371, arm = 271581f8 (test/x264-nw-lapipe-fpel-on: switch on by
#           default). LOWLAT recon differs by design (reported EXPECTED-DIFF; judge with 'quality'); NORMAL must match.
# Cells: t1 on CORE; t4 / t4la4 (obed's 4 lookahead threads) on CORES=12,14 only (4 threads on 2 cpus: cycles:u is
# total CPU work, duration_time the wall time). The sgfades cells are dropped (no sgfades here); fades-p / fades-i
# at 60 frames are md5 cells. Counter trees (live, AB=grp only): cntbase 2cdb8175 / cntarm 0ea63421 built with
# -DX264_LOWRES_TRAFFIC=1; their recon must match each other.
set -u
JOB=lapipe; AB=${AB:-grp}; BRANCHES="wip/x264-nw-lapipe test/x264-nw-lapipe-traffic test/x264-nw-lapipe-fpel-on"
EVENTS=cycles:u,instructions:u,duration_time
N1="tile-chaos-p:normal field-frame-mix-i:normal"; L1="tile-chaos-p:lowlat field-frame-mix-i:lowlat"
NT="tile-chaos-p:normal_t4la4 field-frame-mix-i:normal_t4la4"
NULLCELLS="tile-chaos-p_lowlat field-frame-mix-i_lowlat"; MD5_DIFF_OK=""
case $AB in
grp)    BASE=4e292d6a; ARM=b1d57371; CELLS="$N1 $L1 $NT tile-chaos-p:normal_t4 field-frame-mix-i:normal_t4" ;;
refac)  BASE=4e292d6a; ARM=10443289; CELLS="$N1 $L1 $NT" ;;
badapt) BASE=10443289; ARM=435424dd; CELLS="$N1 $NT" ;;
mbtree) BASE=435424dd; ARM=dc9122e0; CELLS="$N1 $NT" ;;
fpel)   BASE=b1d57371; ARM=271581f8; CELLS="$L1 $N1 tile-chaos-p:lowlat_t4 field-frame-mix-i:lowlat_t4"; NULLCELLS=""
        MD5_DIFF_OK="tile-chaos-p_lowlat field-frame-mix-i_lowlat tile-chaos-p_lowlat_t4 field-frame-mix-i_lowlat_t4 ffm422-i_lowlat fades-p_lowlat_60 fades-i_lowlat_60" ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-p:normal:60 fades-i:normal:60 fades-p:lowlat:60 fades-i:lowlat:60 fades-p:normal_t4la4:60"
LIVE_RE='slicetype|lowres|mbtree|frame_cost|hpel_filter'
if [ $AB = grp ]; then
    COUNT_TREES="cntbase cntarm"; SHA_cntbase=2cdb8175; SHA_cntarm=0ea63421; COUNT_RE=LOWRES_TRAFFIC
    COUNTCELLS="$N1 $NT fades-p:normal:60"
fi
. "$(dirname "$0")/../lib.sh"
MODE_lowlat_t4=${LOWLAT/--threads 1/--threads 4}; MODE_normal_t4=${NORMAL/--threads 1/--threads 4}
MODE_normal_t4la4="$MODE_normal_t4 --lookahead-threads 4"
xe_cflags() { case $1 in cnt*) echo -n "-DX264_LOWRES_TRAFFIC=1" ;; esac; }
XE_PHASES="nondet [N] | traffic | quality"
xe_phase_nondet() { # threaded cells: N repeats per arm, distinct bitstreams (1 1 1 = pass)
    local N=${1:-20} spec a i nb na nr; mkdir -p $W/out
    for spec in tile-chaos-p:normal_t4 field-frame-mix-i:normal_t4 $NT fades-p:normal_t4la4:60; do xe_cell $spec; [ -f $CL ] || continue
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
xe_phase_traffic() { # AB=grp: the counter trees' recon must match (the LOWRES_TRAFFIC lines come from 'live')
    [ $AB = grp ] || { echo "traffic: AB=grp only"; return 1; }
    local spec a; mkdir -p $W/out
    for spec in $N1 $NT fades-p:normal:60; do xe_cell $spec; [ -f $CL ] || continue
        for a in cntbase cntarm; do xe_run $a c $spec tr_$a --dump-yuv $W/out/trrec_$a.yuv; done
        echo "$CN: $(grep -h LOWRES_TRAFFIC $W/out/tr_cntbase.log | sed 's/^/cntbase /') | $(grep -h LOWRES_TRAFFIC $W/out/tr_cntarm.log | sed 's/^/cntarm /')"
        echo "$CN: counter-build recon distinct $(md5sum $W/out/trrec_cnt{base,arm}.yuv | awk '{print $1}' | sort -u | wc -l) (1 = pass)"
        rm -f $W/out/trrec_* $W/out/tr_*.264
    done
}
xe_phase_quality() { # AB=fpel: bitrate / PSNR / SSIM of base vs arm per lowlat cell (the md5 gate cannot judge it)
    local spec a; mkdir -p $W/out
    for spec in $L1 tile-chaos-p:lowlat_t4 field-frame-mix-i:lowlat_t4; do xe_cell $spec; [ -f $CL ] || continue
        for a in base arm; do
            xe_run $a m $spec q_$a --psnr --ssim
            echo "$CN $a: $(grep -E '^x264 \[info\]: (kb/s|PSNR Mean|SSIM Mean)|encoded' $W/out/q_$a.log | tr '\n' ' ') opt:$(strings $W/out/q_$a.264 | grep -o 'lookahead_fpel=1' | head -1)"
        done
    done
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
