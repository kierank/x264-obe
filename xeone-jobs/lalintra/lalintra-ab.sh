#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job LAI: wip/x264-nw-lalintra (base speed-next 322af72b), round 4 package C.
#   S1  = step 1: slicetype: a B pass's lowres intra cost counts as computed (C only; normal/B-frame cells; lowlat is
#         the null control, no B passes).
#   K   = F1 kernel: x86: lowres_p_mbs_regs avx2, assembled and checkasm'd, undispatched (layout control).
#   TIP = F1 dispatch: pixf.lowres_p_mbs = lowres_p_mbs_regs (every AVX2 CPU, Zen 4 included; weighted refs run the
#         old entry).
# Bit-exact: recon md5 base == arm everywhere.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   FRAMES=120 AB=full bash lalintra/lalintra-ab.sh build | live | md5 | time 9 | report
# AB (default full):
#   full  base 322af72b, arm TIP (step 1 + F1)
#   lay   full with -falign-functions=64 on every tree (the code-placement twin)
#   s1    base 322af72b, arm S1 (step 1 alone; lowlat cells null)
#   k     base K (F1 kernel assembled, undispatched), arm TIP (F1 on, same layout but for the pointer)
#   klay  k with -falign-functions=64
#   10    BITDEPTH=10, base 322af72b, arm TIP: 10-bit 4:2:2 interlaced (lookahead8 runs the 8-bit lowres_p_mbs)
set -u
JOB=lalintra; AB=${AB:-full}; BRANCHES="speed-next wip/x264-nw-lalintra"
S1=c32cda73; K=ba3748de; TIP=19eb3158
BASE=322af72b; ARM=$TIP
case $AB in
full|lay) ;;
s1) ARM=$S1 ;;
k|klay) BASE=$K ;;
10) BITDEPTH=10 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
if [ "${BITDEPTH:-8}" = 10 ]; then
    CELLS="ffm422p10long-i:lowlat ffm422p10long-i:normal tc422p10-p:lowlat tc422p10-p:normal"
    NULLCELLS=""
    MD5CELLS="ffm422p10long-i:thrll ffm422p10long-i:thrnor ffm422p10long-i:zsub"
else
    CELLS="field-frame-mix-i:lowlat field-frame-mix-i:normal tile-chaos-p:lowlat tile-chaos-p:normal
           ffm422long-i:lowlat ffm422long-i:normal credits-i:lowlat credits-i:normal"
    NULLCELLS=""
    [ $AB = s1 ] && NULLCELLS="field-frame-mix-i_lowlat tile-chaos-p_lowlat ffm422long-i_lowlat credits-i_lowlat"
    MD5CELLS="fades-i:normal:60 fades-i:lowlat:60 fades-p:normal:60 fades-p:lowlat:60
              field-frame-mix-i:thrll field-frame-mix-i:thrnor tile-chaos-p:thrnor ffm422long-i:thrll ffm422long-i:thrnor
              field-frame-mix-i:lathr tile-chaos-p:lathr field-frame-mix-i:sliced tile-chaos-p:zsub field-frame-mix-i:zsub
              tile-chaos-p:badapt2 field-frame-mix-i:pyramid tile-chaos-p:nombtree field-frame-mix-i:noasm
              tc422p10-p:lowlat tc422p10-p:normal"
fi
COUNT_TREES="basecnt armcnt"; COUNT_RE=LAICNT
COUNTCELLS="field-frame-mix-i:lowlat field-frame-mix-i:normal tile-chaos-p:lowlat tile-chaos-p:normal credits-i:lowlat credits-i:normal ffm422long-i:normal fades-p:normal:60 fades-i:lowlat:60"
LIVE_RE='lowres_p_mbs|lowres_b_mbs|lowres_i_mbs|intra_satd_lowres|sad_hex_search|sad_hpel_min|satd_pre_8x8|satd_avg2_pre_8x8|sad_avg2_8x8|satd_fenc_pre_8x8|slicetype'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
# md5-only modes: threaded at CQP (threaded VBV is nondeterministic run to run); lookahead slices (lowres_p_mbs on
# slices: slice_end clips the mv predictors) and sliced threads (lookahead on lookahead_thread[0]); subme zones
# (reconfig of h with --threads 1: the lookahead runs on h, subme 6 <-> 1 between passes of one frame: the
# b_intra_calculated tag path); b-adapt 2 and b-pyramid (more B pass pairs per frame); no mbtree; no asm (C paths)
cqp() { echo "$1" | sed -E 's/--bitrate [0-9]+ //; s/--vbv-maxrate [0-9]+ //; s/--vbv-bufsize [0-9]+ //; s/--nal-hrd fakevbr //; s/$/ --qp 23/'; }
MODE_thrll=$(cqp "${LOWLAT/--threads 1/--threads 4}")
MODE_thrnor=$(cqp "${NORMAL/--threads 1/--threads 4}")
MODE_lathr=$(cqp "${NORMAL/--threads 1/--threads 4 --lookahead-threads 3}")
MODE_sliced=$(cqp "${LOWLAT/--threads 1/--threads 4 --sliced-threads}")
MODE_zsub="$NORMAL --zones 6,13,subme=1/20,27,subme=1/40,47,subme=1"
MODE_badapt2="$NORMAL --b-adapt 2"
MODE_pyramid="$NORMAL --b-pyramid normal"
MODE_nombtree="$NORMAL --no-mbtree"
MODE_noasm="$NORMAL --no-asm"
xe_patch() { case $1 in *cnt) sh $HERE/laicnt.sh $PWD || return 1 ;; esac; }
xe_cflags() { case $AB in lay|klay) echo "-falign-functions=64" ;; esac; }
xe_bench() { [ $BITDEPTH = 8 ] && (cd $(xe_dir arm t) && for r in 1 2 3; do taskset -c $CORE ./checkasm8 --bench=lowres_p_mbs 1001 | grep -E '^lowres_p|^nop'; done); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
