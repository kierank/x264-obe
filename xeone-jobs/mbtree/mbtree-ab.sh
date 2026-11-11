#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job Z: wip/x264-nw-mbtree (tip 0b09bab8), mbtree_propagate_list into an
# int32 row strip, both lists of a B row in one pass, strip kernels in asm. From core3-jobs/mbtree/nwmbtree-ab.sh:
# same arms and NWCNT counters (nwmbcnt.sh beside this script); perf pinned with x264, no /usr/bin/time.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=avx2 bash mbtree-ab.sh build | live | md5 | time 9 | report
# AB (default avx2):
#   avx2    base = 8f852830 (all strip kernels assembled, undispatched), arm = f017bec6 (AVX2 dispatch:
#           mbtree_propagate_list / list2 = strip_asm_avx2). On AVX2-only cpus 0b09bab8 = f017bec6.
#   cstrip  optional: base = 8f852830, arm = 8f852830 with the C strip (commits 1-3) dispatched by a sed of mc-c.c.
# NORMAL is the live cell (mbtree in the lookahead). LOWLAT (zerolatency: no mbtree) is the zero-call null cell.
# The sgfades cells of the Core 3 script are dropped (no sgfades clips here); fades-p / fades-i at 60 frames are
# md5 cells instead (weightp + mbtree on fades).
set -u
JOB=mbtree; AB=${AB:-avx2}; BRANCHES=wip/x264-nw-mbtree
case $AB in
avx2)   BASE=8f852830; ARM=f017bec6 ;;
cstrip) BASE=8f852830; ARM=8f852830 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
CELLS="tile-chaos-p:normal field-frame-mix-i:normal tile-chaos-p:lowlat field-frame-mix-i:lowlat"
NULLCELLS="tile-chaos-p_lowlat field-frame-mix-i_lowlat"
MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-p:normal:60 fades-i:normal:60"
LIVE_RE='mbtree'
COUNT_TREES=armcnt; COUNT_RE=NWCNT; COUNTCELLS="tile-chaos-p:normal field-frame-mix-i:normal fades-p:normal:60 fades-i:normal:60"
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib.sh"
xe_patch() { # tree flavour (in the tree)
    if [ $AB = cstrip ]; then case $1 in arm*)
        # dispatch the C strip at the AVX2 level
        grep -q '^    pf->mbtree_propagate_list = x264_mbtree_propagate_list_avx2;$' common/x86/mc-c.c || { echo "cstrip: no avx2 line"; return 1; }
        sed -i 's/^    pf->mbtree_propagate_list = x264_mbtree_propagate_list_avx2;$/    pf->mbtree_propagate_list = x264_mbtree_propagate_list_strip_avx2;\n    pf->mbtree_propagate_list2 = x264_mbtree_propagate_list2_strip_avx2;/' common/x86/mc-c.c
        git diff --stat ;;
    esac; fi
    case $1 in *cnt) sh $HERE/nwmbcnt.sh $PWD || return 1 ;; esac
}
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=mbtree_propagate_list 1001 | grep -E "^mbtree_propagate_list|nop"); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
