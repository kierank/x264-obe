#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job T: wip/x264-nw-trprep (tip 2534f770), the CABAC trellis input
# through quant_*_scan_trellis and the output through dequant_*_scan (AVX2 prep + 4x4x4 post kernels).
# From core3-jobs/trprep/trprep-ab.sh: same arms, TRCNT counters (trcnt.sh) and post8-dispatch.patch beside this
# script; perf pinned with x264, no /usr/bin/time.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=tip bash trprep-ab.sh build | live | md5 | time 9 | report; then AB=post8
# AB (default tip):
#   tip    base = 40527133 (tip~1: kernels assembled, callers in place, all NULL), arm = 2534f770 (AVX2 dispatch)
#   post8  base = 2534f770, arm = 2534f770 + post8-dispatch.patch (dequant_8x8_scan avx2: the 8x8 trellis post,
#          neutral/loss on the laptop, Intel decides)
#   (core3's AB=icl is AVX-512: rack01 only.)
# Reached only with trellis >= 1: NORMAL, and NORMAL7 (production's subme 7 for B-frame RD). LOWLAT is trellis 0:
# the zero-call null cell (identical recon, ~0 delta).
set -u
JOB=trprep; AB=${AB:-tip}; BRANCHES=wip/x264-nw-trprep
case $AB in
tip)   BASE=40527133; ARM=2534f770 ;;
post8) BASE=2534f770; ARM=2534f770 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
CELLS="tile-chaos-p:normal tile-chaos-p:normal7 tile-chaos-p:lowlat field-frame-mix-i:normal field-frame-mix-i:normal7 field-frame-mix-i:lowlat"
NULLCELLS="tile-chaos-p_lowlat field-frame-mix-i_lowlat"
MD5CELLS="ffm422-i:lowlat ffm422-i:normal ffm422-i:normal7"
LIVE_RE='trellis|quant_(4x4x4|8x8)_scan|dequant_(4x4x4|8x8)_scan'
COUNT_TREES=armcnt; COUNT_RE=TRCNT
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
MODE_normal7=${NORMAL/--subme 6/--subme 7}
xe_patch() { # tree flavour (in the tree)
    if [ $AB = post8 ]; then case $1 in arm*) git apply $HERE/post8-dispatch.patch || return 1; git diff --stat ;; esac; fi
    case $1 in *cnt) sh $HERE/trcnt.sh $PWD || return 1 ;; esac
}
xe_bench() { # per call: T = (printed + nop/4) / 10
    (cd $(xe_dir arm t) && for p in quant_4x4x4_scan_trellis quant_8x8_scan_trellis dequant_4x4x4_scan dequant_8x8_scan; do
        taskset -c $CORE ./checkasm8 --bench=$p 1001 | grep -E "nop:|_flat" | grep -v cqm; done)
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
