#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job AC: wip/x264-nw-hpelfly (tip 401d882f): subpel samples interpolated
# on the fly into per-reference bands and windows, no stored H/V/C planes, on by default at 8-bit.
# From core3-jobs/hpelfly/ab-hpelfly.sh: same arms, BASE_CFLAGS swap arm, the extra md5 cells (threads, subme 1,
# slower, chroma-me, esa) and the HPELFLY_STATS traffic / hit-miss line (counter trees); gdb liveness replaced by
# perf samples, perf pinned with x264. MBM (rack01) and the 10-bit TEN cells are not part of this pack.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=series bash hpelfly-ab.sh build | live | md5 | time 9 | report; then AB=swap
# AB (default series):
#   series  base = 14953cf5 (engine + consumers, HPEL_FLY default off: stored planes), arm = 401d882f (default on)
#   swap    base = 401d882f built with -DHPELFLY_SWAP=0 (fused search off the band: C search on a fly ref),
#           arm = 401d882f (the band-pointer swap of 33d409a1 on)
# Bit-exact by design (the same 6-tap); recon md5 across all arms, bitstreams within one sha.
# No zero-call cell: every P/B search reads subpel samples. The sgfades cells are dropped (no sgfades here);
# fades-p / fades-i 60 frames are md5 cells.
set -u
JOB=hpelfly; AB=${AB:-series}; BRANCHES=wip/x264-nw-hpelfly
BASE_CFLAGS=""
case $AB in
series) BASE=14953cf5; ARM=401d882f ;;
swap)   BASE=401d882f; ARM=401d882f; BASE_CFLAGS="-DHPELFLY_SWAP=0" ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
CELLS="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal"
MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-p:normal:60 fades-i:normal:60 fades-p:lowlat:60 fades-i:lowlat:60
          tile-chaos-p:normal_t4 field-frame-mix-i:normal_t4 tile-chaos-p:lowlat_t4 field-frame-mix-i:lowlat_t4
          tile-chaos-p:sub1 field-frame-mix-i:sub1 tile-chaos-p:slow field-frame-mix-i:slow tile-chaos-p:chme field-frame-mix-i:chme
          tile-chaos-p:plac:10 field-frame-mix-i:plac:10"
LIVE_RE='me_search_fpel|satd_subpel_search|qpel_search|me_search_ref|refine_subpel|hpel_filter|fly|get_ref'
COUNT_TREES="basecnt armcnt"; COUNT_RE=hpelfly
. "$(dirname "$0")/../lib.sh"
MODE_normal_t4=${NORMAL/--threads 1/--threads 4}; MODE_lowlat_t4=${LOWLAT/--threads 1/--threads 4}
MODE_sub1="--preset superfast --subme 1 --bframes 2 --threads 1"
MODE_slow="--preset slower --bframes 3 --b-adapt 1 --threads 1"
MODE_chme="--preset medium --chroma-me --subme 7 --threads 1"
MODE_plac="--preset slower --subme 11 --me esa --merange 16 --partitions all --ref 3 --bframes 3 --b-adapt 1 --threads 1"
xe_cflags() { # tree flavour
    case $1 in base*) echo -n "$BASE_CFLAGS " ;; esac
    case $1 in *cnt) echo -n "-DHPELFLY_STATS=1" ;; esac
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
