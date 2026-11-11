#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job J: wip/x264-gap-a512only (tip 86666108): avx2 kernels for slots
# where Intel AVX2 ran sse/mmx/C because only an AVX-512 kernel existed. One dispatch commit per KIND, base = its
# parent. From core3-jobs/a512only/a512only-ab.sh: same kinds and AB_CNT counter; the production cells (the Core 3
# script had its own 15 Mbps / keyint 24 cells), perf record pinned with x264. lb.c (the rack01 loop-of-N) is not
# part of this pack.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   KIND=oc bash a512only-ab.sh build | live | md5 | time 9 | report; then KIND=il, cl8, pcd
# KIND (ranked; default oc):
#   oc   optimize_chroma_2x4_dc avx2 (Intel ran C):   base = c31b9ffc, arm = ed88c7ab   4:2:2 only
#   il   cabac residual writer with inline last:       base = 42d3c9c2, arm = 752febdb
#   cl8  coeff_last8 avx2_lzcnt (4:2:2 chroma dc):      base = 2347fb9a, arm = c31b9ffc   4:2:2 only
#   pcd  plane_copy_deinterleave avx2:                  base = e3df3ae3, arm = 42d3c9c2   weightp chroma analysis, --dump-yuv
#   (D5 intra_sad_x3_8x16c, 86666108, is called only at subme <= 1: no in-situ arm; 'build' prints its checkasm bench.
#    KIND=zmm is AVX-512: rack01 only.)
# Cells: oc / cl8 time the 8-bit 4:2:2 clips ffm422-i (--tff) and tc422-p; their 4:2:0 cells are the zero-call null
#   cells. il / pcd time the 4:2:0 cells (pcd adds fades-p / fades-i 60 frames, where weightp chroma analysis runs)
#   with ffm422-i as md5 cells.
set -u
JOB=a512only; KIND=${KIND:-oc}; AB=$KIND; BRANCHES=wip/x264-gap-a512only
P420="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal"
P422="ffm422-i:lowlat ffm422-i:normal tc422-p:lowlat tc422-p:normal"
NULLCELLS=""; MD5CELLS=""
case $KIND in
oc)  BASE=c31b9ffc; ARM=ed88c7ab; CELLS="$P422 $P420"; NULLCELLS="tile-chaos-p_lowlat tile-chaos-p_normal field-frame-mix-i_lowlat field-frame-mix-i_normal"
     LIVE_RE='optimize_chroma' ;;
cl8) BASE=2347fb9a; ARM=c31b9ffc; CELLS="$P422 $P420"; NULLCELLS="tile-chaos-p_lowlat tile-chaos-p_normal field-frame-mix-i_lowlat field-frame-mix-i_normal"
     LIVE_RE='coeff_last' ;;
il)  BASE=42d3c9c2; ARM=752febdb; CELLS="$P420"; MD5CELLS="ffm422-i:lowlat ffm422-i:normal"
     LIVE_RE='cabac_block_residual|cabac_encode' ;;
pcd) BASE=e3df3ae3; ARM=42d3c9c2; CELLS="$P420 fades-p:normal:60 fades-i:normal:60"; MD5CELLS="ffm422-i:lowlat ffm422-i:normal"
     LIVE_RE='plane_copy_deinterleave|weights_analyse|weight_cost' ;;
*) echo "unknown KIND $KIND"; exit 1 ;;
esac
COUNT_TREES=armcnt; COUNT_RE=AB_CNT
. "$(dirname "$0")/../lib.sh"
cntpatch() { # liveness: calls through the pointer under test (> 0 = live)
    local F INIT FIELD K RET ARGS CALL
    case $KIND in
    pcd) F=common/x86/mc-c.c; INIT=x264_mc_init_mmx; FIELD=plane_copy_deinterleave; RET=void
         ARGS="pixel *a, intptr_t b, pixel *c, intptr_t d, pixel *e, intptr_t f, int g, int h"; CALL="a, b, c, d, e, f, g, h"
         K=x264_plane_copy_deinterleave_avx2 ;;
    il)  F=common/bitstream.c; INIT=x264_bitstream_init; FIELD=cabac_block_residual_internal; RET=void
         ARGS="dctcoef *l, int i, intptr_t c, x264_cabac_t *cb"; CALL="l, i, c, cb"
         K=x264_cabac_block_residual_internal_il_avx2_bmi2 ;;
    oc)  F=common/quant.c; INIT=x264_quant_init; FIELD=optimize_chroma_2x4_dc; RET=int
         ARGS="dctcoef *d, int m"; CALL="d, m"; K=x264_optimize_chroma_2x4_dc_avx2 ;;
    cl8) F=common/quant.c; INIT=x264_quant_init; FIELD=coeff_last8; RET=int
         ARGS="dctcoef *d"; CALL="d"; K=x264_coeff_last8_avx2_lzcnt ;;
    esac
    INIT="$INIT" FIELD="$FIELD" K="$K" RET="$RET" ARGS="$ARGS" CALL="$CALL" perl -0pi -e '
        my $w = "static uint64_t ab_cnt;\n"
              . "static void __attribute__((destructor)) ab_cnt_print( void ) { fprintf( stderr, \"AB_CNT $ENV{K} %llu\\n\", (unsigned long long)ab_cnt ); }\n"
              . "static $ENV{RET} ab_wrap( $ENV{ARGS} ) { __atomic_fetch_add( &ab_cnt, 1, __ATOMIC_RELAXED ); "
              . ($ENV{RET} eq "void" ? "" : "return ") . "$ENV{K}( $ENV{CALL} ); }\n";
        s/^(void \Q$ENV{INIT}\E\()/$w$1/m or die "cntpatch: no $ENV{INIT}\n";
        s/(pf->\Q$ENV{FIELD}\E = )\Q$ENV{K}\E;/${1}ab_wrap;/g or die "cntpatch: no $ENV{FIELD} = $ENV{K}\n";' $F
}
xe_patch() { case $1 in *cnt) cntpatch || return 1 ;; esac; }
xe_bench() {
    (cd $(xe_dir arm t) && for p in optimize_chroma_2x4 coeff_last8 intra_sad_x3_8x16c; do taskset -c $CORE ./checkasm8 --bench=$p 1001 | grep -E "$p|nop"; done)
}
[ -n "${XE_TEST:-}" ] || xe_main "$@"
