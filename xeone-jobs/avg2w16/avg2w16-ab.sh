#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B, job L: wip/x264-gap-avg2w16 (tip 6454133a), the Intel AVX2 get_ref /
# mc_luma: VEX avg2 w8/w12/w16 table and get_ref (unweighted) in asm, dispatched on AVX2 without AVX-512.
# From core3-jobs/avg2w16/avg2w16-ab.sh: same arms, NOMCL variant and AVG2_CNT counters; the production cells
# (the Core 3 script had its own 15 Mbps / keyint 24 cells), perf pinned with x264, no /usr/bin/time.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=tip bash avg2w16-ab.sh build | live | md5 | time 9 | report; then AB=nomcl
# AB (default tip):
#   tip    base = d7fe25e4 (tip~1), arm = 6454133a (Intel dispatch: get_ref_avx2_asm + mc_luma_avx2_intel)
#   nomcl  base = d7fe25e4, arm = 6454133a without the mc_luma switch (get_ref only): the laptop had mc_luma on the
#          Intel table slower than the sse2 table (16x16 17.2 vs 16.0, 8x8 11.0 vs 9.7)
#   (core3's BOX=rack01 arm is Zen 4: rack01 only.)
# No zero-call cell: get_ref / mc_luma run in every mode.
set -u
JOB=avg2w16; AB=${AB:-tip}; BRANCHES=wip/x264-gap-avg2w16
case $AB in
tip|nomcl) BASE=d7fe25e4; ARM=6454133a ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
CELLS="tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal"
MD5CELLS="ffm422-i:lowlat ffm422-i:normal fades-i:lowlat:60 fades-i:normal:60"
LIVE_RE='avg2_w|get_ref|mc_luma|pixel_avg'
COUNT_TREES=armcnt; COUNT_RE=AVG2_CNT
. "$(dirname "$0")/../lib.sh"
cntpatch() { # liveness counters: calls through the arm's get_ref / mc_luma pointers
    awk '/^void x264_mc_init_mmx\( int cpu, x264_mc_functions_t \*pf \)$/ {
      print "static uint64_t avg2_cnt[3];"
      print "static void __attribute__((destructor)) avg2_cnt_print( void )"
      print "{ fprintf( stderr, \"AVG2_CNT get_ref_avx2_asm unweighted %llu weighted %llu mc_luma_avx2_intel %llu\\n\","
      print "           (unsigned long long)avg2_cnt[0], (unsigned long long)avg2_cnt[1], (unsigned long long)avg2_cnt[2] ); }"
      print "static pixel *get_ref_cnt( pixel *d, intptr_t *ds, pixel *s[4], intptr_t ss, int mx, int my, int w, int h, const x264_weight_t *wt )"
      print "{ __atomic_fetch_add( &avg2_cnt[!!wt->weightfn], 1, __ATOMIC_RELAXED ); return get_ref_avx2_asm( d, ds, s, ss, mx, my, w, h, wt ); }"
      print "static void mc_luma_cnt( pixel *d, intptr_t ds, pixel *s[4], intptr_t ss, int mx, int my, int w, int h, const x264_weight_t *wt )"
      print "{ __atomic_fetch_add( &avg2_cnt[2], 1, __ATOMIC_RELAXED ); mc_luma_avx2_intel( d, ds, s, ss, mx, my, w, h, wt ); }"
    } { print }' common/x86/mc-c.c > mcc.new && mv mcc.new common/x86/mc-c.c
    sed -i 's/^            pf->get_ref = get_ref_avx2_asm;$/            pf->get_ref = get_ref_cnt;/; s/^        pf->mc_luma = mc_luma_avx2_intel;$/        pf->mc_luma = mc_luma_cnt;/' common/x86/mc-c.c
    [ "$(grep -c 'get_ref_cnt;' common/x86/mc-c.c)" = 1 ] || { echo "cntpatch did not apply"; return 1; }
}
nomcl() { # arms without the mc_luma switch (get_ref only)
    sed -i '/^        pf->mc_luma = mc_luma_avx2_intel;$/d' common/x86/mc-c.c
    ! grep -q 'pf->mc_luma = mc_luma_avx2_intel;' common/x86/mc-c.c
}
xe_patch() { # tree flavour (in the tree)
    case $1 in arm*) [ $AB = nomcl ] && { nomcl || { echo "nomcl did not apply"; return 1; }; } ;; esac
    case $1 in *cnt) cntpatch || return 1 ;; esac
    return 0
}
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=avg2 1001 | grep -E 'avg2|nop'); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
