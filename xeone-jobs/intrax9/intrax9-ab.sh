#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job AD: wip/x264-nw-intrax9 (tip 76142791, the _notr chain on 42c3f783).
# From core3-jobs/intrax9/intrax9-ab.sh (500b854d): same arms, patches and X9_CNT counters; per-sha trees,
# timing builds without the md5 cflags, cycles:u + instructions:u timing, perf record pinned with x264.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=tip bash intrax9-ab.sh build | live | md5 | time 9 | report
# AB (default tip):
#   tip  items 2 + 4 dispatched (8x8 fdec edge filter in the kernel, i4x4 MB driver): base = 5cdbdd1c (tip~1), arm = 76142791
#   i1   item 1, x9 v/h/dc in the hadamard domain: base = speed-next 42c3f783, arm = ad2e4638
#   i3   item 3, topright emulation in the kernel: base = f6e9a53f, arm = 219b043c
#   i2   item 2 alone: base = tip~1, arm = tip without the MB driver pointer (sed of dct.c)
#   i4   item 4 alone: base = tip~1, arm = tip without the 8x8 fdec pointer (sed of pixel.c)
#   (core3's AB=icl is AVX-512: rack01 only, dropped here.)
# Counters (live, never timed): X9_CNT mb / fdec8x8 / recon4x4 calls in x264_mb_analyse_intra, base and arm.
# No zero-call cell: both lowlat (subme 2) and normal reach the x9 4x4 / 8x8 analysis.
set -u
JOB=intrax9; AB=${AB:-tip}; BRANCHES=wip/x264-nw-intrax9
TIP=76142791; TIP1=5cdbdd1c
PFILE=""; PATCH=""
case $AB in
tip) BASE=$TIP1;   ARM=$TIP ;;
i1)  BASE=42c3f783; ARM=ad2e4638 ;;
i3)  BASE=f6e9a53f; ARM=219b043c ;;
i2)  BASE=$TIP1;   ARM=$TIP; PFILE=common/dct.c;   PATCH="/intra_satd_x9_4x4_mb *= x264_intra_satd_x9_4x4_mb_f[a-z]*_avx2;/d" ;;
i4)  BASE=$TIP1;   ARM=$TIP; PFILE=common/pixel.c; PATCH="/pixf->intra_sa8d_x9_8x8_fdec = x264_intra_sa8d_x9_8x8_fdec_avx2;/d" ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
CELLS="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal"
MD5CELLS="ffm422-i:lowlat ffm422-i:normal"
LIVE_RE='x9_4x4|x9_8x8|analyse_intra'
COUNT_TREES="basecnt armcnt"; COUNT_RE=X9_CNT
. "$(dirname "$0")/../lib.sh"

cnt_patch() { # counters in x264_mb_analyse_intra, printed at exit as X9_CNT
    perl -0pi -e 's|(static void x264_mb_analyse_intra\( x264_t \*h)|#include <stdio.h>\nstatic unsigned long long x9cnt[3];\n__attribute__((destructor)) static void x9cnt_print( void ) { fprintf( stderr, "X9_CNT mb %llu fdec8x8 %llu recon4x4 %llu\\n", x9cnt[0], x9cnt[1], x9cnt[2] ); }\n$1|' encoder/analyse.c
    perl -pi -e 's/^(\s+)(idx = h->zigzagf\.intra_satd_x9_4x4_mb\()/$1x9cnt[0]++, $2/; s/^(\s+)(i_best = x9_fdec\()/$1x9cnt[1]++, $2/; s/^(\s+)(i_best = (x9_recon|\(b_notr && x9_recon_notr \? x9_recon_notr : x9_recon\))\()/$1x9cnt[2]++, $2/' encoder/analyse.c
    [ $(grep -c 'x9cnt\[[012]\]++' encoder/analyse.c) -ge 1 ] || { echo "CNT SITES NOT FOUND"; return 1; }
    grep -q 'X9_CNT' encoder/analyse.c || { echo "CNT PATCH DID NOT APPLY"; return 1; }
}
xe_patch() { # tree flavour (in the tree)
    case $1 in arm*) if [ -n "$PATCH" ]; then
        sed -i "$PATCH" $PFILE
        git diff --stat | grep -qE "$PFILE \| +[12] " || { echo "ARM PATCH DID NOT APPLY ($1)"; git diff --stat; return 1; }
        git diff | grep '^[-+] '
    fi ;; esac
    case $1 in *cnt) cnt_patch || return 1 ;; esac
}
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=intra_s 1001 | grep -E "x9|nop"); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
