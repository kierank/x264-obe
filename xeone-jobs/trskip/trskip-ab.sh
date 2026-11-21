#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job TRS: wip/x264-nw-trskip (round 4 B), the CABAC trellis skipped
# where the round-to-nearest decimate score proves decimation (inter luma 4x4, chroma ac, i16x16 ac, p8x8).
# Bit-exact: recon identical across all arms. Trellis runs only with trellis >= 1: lowlat cells are the null control.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   FRAMES=120 AB=tip | lay | ovh  bash trskip/trskip-ab.sh build | live | md5 | time 9 | report
# AB (default tip):
#   tip  base = speed-next 322af72b, arm = 1e7584d3 (the whole series: score in quant_4x4x4_scan_last, rtn/dp
#        split, chroma/i16/p8x8 skip, inter luma skip)
#   lay  as tip, both sides -falign-functions=64 (layout twin: instructions fall, placement moves)
#   ovh  base = 322af72b, arm = 97b7a7cc (score + split only, no skip: the cost side; optional)
set -u
JOB=trskip; AB=${AB:-tip}; BRANCHES="speed-next wip/x264-nw-trskip"
case $AB in
tip|lay) BASE=322af72b; ARM=1e7584d3 ;;
ovh)     BASE=322af72b; ARM=97b7a7cc ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
BITDEPTH=all
CELLS="field-frame-mix-i:normal field-frame-mix-i:lowlat tile-chaos-p:normal tile-chaos-p:lowlat ffm422long-i:normal
       credits-i:normal ffm422long-i:normal@10"
NULLCELLS="field-frame-mix-i_lowlat tile-chaos-p_lowlat"
MD5CELLS="ffm422long-i:lowlat credits-i:lowlat fades-i:normal:60 tile-chaos-p:normal7 field-frame-mix-i:normal7"
LIVE_RE='trellis|quant_4x4x4|decimate|macroblock_encode|mb_encode_chroma'
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
MODE_normal7=${NORMAL/--subme 6/--subme 7}
xe_cflags() { [ $AB = lay ] && echo "-falign-functions=64"; }
xe_bench() { # per call: T = (printed + nop/4) / 10; base kernel has no score
    for t in base arm; do (cd $(xe_dir $t t) && taskset -c $CORE ./checkasm8 --bench=quant_4x4x4_scan_last 1001 | grep -E "nop:|scan_last" | sed "s/^/$t /"); done
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
