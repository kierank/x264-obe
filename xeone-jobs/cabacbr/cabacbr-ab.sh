#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job CBR: wip/x264-nw-cabacbr (base speed-next 322af72b), round 4 package D,
# CABAC residual writer branch mispredicts. K 3edda89c br writer (branch-free sig map) + checkasm, undispatched
# (placebo layout); D 50e59b9e dispatch br at AVX2+BMI2 (AVX-512 CPUs keep the avx512 writer); R 760b0ca2 saturated
# MPS-run table step in br's level loop. Bit-exact. Laptop driver per writer call: insns 674 -> 708 (+34),
# branches 76 -> 60, misses 2.6-3.2 -> 1.4-1.6; laptop tsc ~+5 % (not the judge).
# Expected D vs K: branch-misses:u -6..-9M on ffm-i ll (sig map ~10M of 53.2M), instructions:u +0.3..+0.6 % on ll.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   FRAMES=120 AB=k bash cabacbr/cabacbr-ab.sh build | live | md5 | time 9 | report
# AB:
#   k     base K 3edda89c, arm D 50e59b9e (primary: same layout but for one pointer)
#   full  base 322af72b, arm R 760b0ca2 (merge view)
#   r     base D 50e59b9e, arm R 760b0ca2 (the saturated-run step alone)
#   lay   full with -falign-functions=64 on every tree
#   10 / 10k  BITDEPTH=10: full / k on 10-bit 4:2:2 lowlat
set -u
JOB=cabacbr; AB=${AB:-k}; BRANCHES="speed-next wip/x264-nw-cabacbr"
K=3edda89c; D=50e59b9e; R=760b0ca2
BASE=322af72b; ARM=$R
case $AB in
k|10k) BASE=$K; ARM=$D ;;
full|lay|10) ;;
r) BASE=$D ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
case $AB in 10|10k) BITDEPTH=10 ;; esac
EVENTS=cycles:u,instructions:u,branches:u,branch-misses:u
if [ "${BITDEPTH:-8}" = 10 ]; then
    CELLS="ffm422p10long-i:lowlat ffm422p10long-i:normal"
    NULLCELLS=""
    MD5CELLS="ffm422p10long-i:thrll ffm422p10long-i:thrnor"
else
    CELLS="field-frame-mix-i:lowlat tile-chaos-p:lowlat credits-i:lowlat ffm422long-i:lowlat field-frame-mix-i:normal tile-chaos-p:normal"
    NULLCELLS=""
    MD5CELLS="fades-i:normal:60 credits-i:normal ffm422long-i:normal field-frame-mix-i:thrll ffm422long-i:thrll
              field-frame-mix-i:thrnor field-frame-mix-i:noasm field-frame-mix-i:sse42"
fi
LIVE_RE='cabac_block_residual|cabac_encode|trellis'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
cqp() { echo "$1" | sed -E 's/--bitrate [0-9]+ //; s/--vbv-maxrate [0-9]+ //; s/--vbv-bufsize [0-9]+ //; s/--nal-hrd fakevbr //; s/$/ --qp 23/'; }
MODE_thrll=$(cqp "${LOWLAT/--threads 1/--threads 4}")
MODE_thrnor=$(cqp "${NORMAL/--threads 1/--threads 4}")
MODE_noasm="$NORMAL --no-asm"
MODE_sse42="$NORMAL --asm SSE4.2"
xe_cflags() { case $AB in lay) echo "-falign-functions=64" ;; esac; }
xe_bench() { (cd $(xe_dir arm t) && for c in checkasm8 checkasm10; do [ -x $c ] && taskset -c $CORE ./$c --bench=cabac 1001 | grep -E '^cabac|^nop'; done); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
