#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job AC: wip/x264-nw-hpelfly (tip e40733b2): subpel samples interpolated
# on the fly into per-reference bands and windows, no stored H/V/C planes, on by default at 8-bit.
# From core3-jobs/hpelfly/ab-hpelfly.sh: same arms, BASE_CFLAGS swap arm, the extra md5 cells (threads, subme 1,
# slower, chroma-me, esa) and the HPELFLY_STATS traffic / hit-miss line (counter trees); gdb liveness replaced by
# perf samples, perf pinned with x264. MBM (rack01) and the 10-bit TEN cells are not part of this pack.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=series bash hpelfly-ab.sh build | live | md5 | time 9 | report; then AB=swap
# AB (default series):
#   series  base = e8bb50a5 (engine, consumers, band swap, B BI-cost stride fix; HPEL_FLY default off: stored
#           planes), arm = e40733b2 (default on). History rewritten 11-12: the old tip 401d882f failed the P6
#           normal md5 (B BI cost read list 1 at list 0's stride, band vs window); e8bb50a5 fixes it.
#   swap    base = e40733b2 built with -DHPELFLY_SWAP=0 (fused search off the band: C search on a fly ref),
#           arm = e40733b2 (the band-pointer swap of 33d409a1 on)
# Bit-exact by design (the same 6-tap); recon md5 across all arms, bitstreams within one sha.
# No zero-call cell: every P/B search reads subpel samples. The sgfades cells are dropped (no sgfades here);
# fades-p / fades-i 60 frames are md5 cells.
set -u
JOB=hpelfly; AB=${AB:-series}; BRANCHES=wip/x264-nw-hpelfly
BASE_CFLAGS=""
case $AB in
series) BASE=e8bb50a5; ARM=e40733b2 ;;
swap)   BASE=e40733b2; ARM=e40733b2; BASE_CFLAGS="-DHPELFLY_SWAP=0" ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
CELLS="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal"
MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-p:normal:60 fades-i:normal:60 fades-p:lowlat:60 fades-i:lowlat:60
          tile-chaos-p:normal_t4 field-frame-mix-i:normal_t4 tile-chaos-p:lowlat_t4 field-frame-mix-i:lowlat_t4
          tile-chaos-p:sub1 field-frame-mix-i:sub1 tile-chaos-p:slow field-frame-mix-i:slow tile-chaos-p:chme field-frame-mix-i:chme
          tile-chaos-p:plac:10 field-frame-mix-i:plac:10
          fades-p:normal_wp2:60 fades-i:normal_wp2:60 fades-p:medium_wp2r3:60 tile-chaos-p:medium_wp2r3:30
          fades-i:medium_wp2r3:60 field-frame-mix-i:medium_wp2r3:30 ffm422-i:medium_wp2r3:30"
LIVE_RE='me_search_fpel|satd_subpel_search|qpel_search|me_search_ref|refine_subpel|hpel_filter|fly|get_ref'
COUNT_TREES="basecnt armcnt"; COUNT_RE=hpelfly
. "$(dirname "$0")/../lib.sh"
# threads 4 without VBV (crf; nal-hrd drops with a warning): threaded VBV is not deterministic run to run
VBV_N="--bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 20000 --nal-hrd fakevbr"; VBV_L="--bitrate 20000 --vbv-maxrate 20000 --vbv-bufsize 667 --nal-hrd fakevbr"
MODE_normal_t4=${NORMAL/--threads 1/--threads 4}; MODE_normal_t4=${MODE_normal_t4/$VBV_N/--crf 23}
MODE_lowlat_t4=${LOWLAT/--threads 1/--threads 4}; MODE_lowlat_t4=${MODE_lowlat_t4/$VBV_L/--crf 23}
MODE_sub1="--preset superfast --subme 1 --bframes 2 --threads 1"
MODE_slow="--preset slower --bframes 3 --b-adapt 1 --threads 1"
# chroma ME is the default (x264-obe has no --chroma-me): the normal line without --no-chroma-me, subme 7
MODE_chme="${NORMAL/ --no-chroma-me/} --subme 7"
# weighted refs: weightp 2 (smart: the unweighted and offset - 1 duplicates of ref 0), 3 refs, B frames
MODE_normal_wp2="$NORMAL --weightp 2"
MODE_medium_wp2r3="--preset medium --ref 3 --weightp 2 --bframes 3 --rc-lookahead 24 ${NORMAL#*--bframes 3 --rc-lookahead 24 }"
MODE_plac="--preset slower --subme 11 --me esa --merange 16 --partitions all --ref 3 --bframes 3 --b-adapt 1 --threads 1"
xe_cflags() { # tree flavour
    case $1 in base*) echo -n "$BASE_CFLAGS " ;; esac
    case $1 in *cnt) echo -n "-DHPELFLY_STATS=1" ;; esac
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
