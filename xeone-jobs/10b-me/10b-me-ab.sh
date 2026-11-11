#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B: wip/x264-10b-me (tip 41f6b02e): 10-bit AVX2 + BMI2 runs the fused
# me_search_fpel_avx2 (inline search on uint16 pixels, subpel through fn->subpel) instead of C me_search_ref +
# refine_subpel. Adapted from wip/x264-10b-me-tools a2f9181f wip-10b-me/dot44.sh (.44 = Cascade Lake under an
# AVX2 --asm cap). This cpu is natively AVX2-only, so no cap: production pointers as detected.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   bash 10b-me-ab.sh build | live | md5 | time 9 | report
# base = dfd3f236 (tip~1: avx2 + inline avx512 entries assembled, 10-bit AVX2 undispatched), arm = 41f6b02e (dispatch).
# Cells, all 10-bit (--bit-depth=10 builds): the 10-bit 4:2:2 clips ffm422p10-i (--tff) / tc422p10-p with
#   LOWLAT and NORMAL (--output-csp i422 --profile high422), the 8-bit 4:2:0 clips encoded at 10-bit
#   (--profile high10), and the null control ffm422p10-i lowdia (LOWLAT --me dia: the fused search makes zero calls).
# CAP=1 adds dot44.sh's --asm list. It is NOT a no-op here: it drops Cache64 (10-bit predict_8x8 ddl/ddr go from
#   ssse3_cache64 to ssse3) and AVXVNNI (no 10-bit reader). Leave it off; it exists only to mirror .44.
set -u
JOB=10b-me; AB=${AB:-avx2}; BRANCHES=wip/x264-10b-me
case $AB in
avx2) BASE=dfd3f236; ARM=41f6b02e ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
BITDEPTH=10
CELLS="ffm422p10-i:lowlat ffm422p10-i:normal tc422p10-p:lowlat tc422p10-p:normal ffm422p10-i:lowdia
       tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal"
NULLCELLS="ffm422p10-i_lowdia"
[ "${CAP:-0}" = 1 ] && AB=${AB}-cap   # own work dir and times.txt
LIVE_RE='me_search|refine_subpel|sad_x[34]|satd_subpel|qpel_search|predictor_clip'
. "$(dirname "$0")/../lib.sh"
CAPS=""; [ "${CAP:-0}" = 1 ] && CAPS="--asm MMX2,SSE,SSE2,SSE3,SSSE3,SSE4.1,SSE4.2,AVX,FMA3,BMI1,BMI2,LZCNT,AVX2"
MODE_lowlat="$LOWLAT $CAPS"; MODE_normal="$NORMAL $CAPS"; MODE_lowdia="$LOWLAT $CAPS --me dia"
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm10 --bench=me_search_fpel 1001 | grep -E 'me_search_fpel|nop'); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
