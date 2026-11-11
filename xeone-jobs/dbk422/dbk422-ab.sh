#!/bin/bash
# Xeon E (E-2478, Intel AVX2) / rack01 (EPYC 8324P, Zen 4) in-situ A/B, job dbk422: wip/x264-422-deblock,
# 8-bit deblock_h_chroma_422(_intra) avx2 (all 16 rows of a 4:2:2 MB edge in one ymm pass), dispatched at AVX2.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
# Install as xeone-jobs/dbk422/dbk422-ab.sh next to lib.sh (wip/x264-core3-jobs), then per AB:
#   AB=tip bash dbk422-ab.sh build | live | md5 | time 9 | report
# AB (default tip):
#   tip  base = baf5b648 (tip~1: kernels in, avx dispatched), arm = beec0fb5 (tip: avx2 dispatched).
#        Xeon E: the Intel AVX2 verdict. rack01: the Zen 4 verdict for the same pointer (AVX-512 machines inherit
#        the AVX2 dispatch; before it they ran deblock_h_chroma_422_avx, the 8-bit icl having been pruned).
#   icl  rack01 only: base = beec0fb5 (tip), arm = tip with the undispatched x264_deblock_h_chroma_422(_intra)_avx512icl
#        dispatched at AVX512ICL (sed, xe_patch).
# 10-bit: the series changes no 10-bit library object (all of it is !HIGH_BIT_DEPTH), so the @10 cells are null
# cells by construction, timed as the lead asked; tile-chaos-p (8-bit 4:2:0 progressive) is the zero-call null cell.
# Clips are 30 frames; the 4:2:2 cells use the 10b-brief 50 Mbps lines.
set -u
JOB=dbk422; AB=${AB:-tip}; BRANCHES=wip/x264-422-deblock
case $AB in
tip) BASE=baf5b648; ARM=beec0fb5 ;;
icl) BASE=beec0fb5; ARM=beec0fb5 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
BITDEPTH=all
CELLS="ffm422-i:ll50 ffm422-i:nm50 ffm422p10-i:ll50@10 ffm422p10-i:nm50@10 tile-chaos-p:lowlat"
NULLCELLS="ffm422p10-i_ll50-10 ffm422p10-i_nm50-10 tile-chaos-p_lowlat"
MD5CELLS="tc422-p:ll50 tc422-p:nm50 tc422p10-p:ll50@10 tc422p10-p:nm50@10 field-frame-mix-i:lowlat field-frame-mix-i:normal"
LIVE_RE='x264_8_deblock_h_chroma_422'
COUNT_TREES=armcnt; COUNT_RE=DB422_CNT
. "$(dirname "$0")/../lib.sh"
MODE_ll50="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 1667 --nal-hrd fakevbr --threads 1"
MODE_nm50="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 50000 --nal-hrd fakevbr --threads 1"
cntpatch() { # liveness: call counts through the 4:2:2 h chroma slots and the pointer names
    sed -i 's/^void x264_deblock_init( int cpu, x264_deblock_function_t \*pf, int b_mbaff )$/static void deblock_init_real( int cpu, x264_deblock_function_t *pf, int b_mbaff )/' common/deblock.c
    grep -q '^static void deblock_init_real' common/deblock.c || return 1
    cat >> common/deblock.c <<'EOF'
static x264_deblock_inter_t cnt_inter_real;
static x264_deblock_intra_t cnt_intra_real;
static uint64_t cnt_calls[2];
static void cnt_inter( pixel *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )
{ __atomic_fetch_add( &cnt_calls[0], 1, __ATOMIC_RELAXED ); cnt_inter_real( pix, stride, alpha, beta, tc0 ); }
static void cnt_intra( pixel *pix, intptr_t stride, int alpha, int beta )
{ __atomic_fetch_add( &cnt_calls[1], 1, __ATOMIC_RELAXED ); cnt_intra_real( pix, stride, alpha, beta ); }
static void cnt_report( void )
{ fprintf( stderr, "DB422_CNT %d-bit calls h_chroma_422 %llu h_chroma_422_intra %llu\n", BIT_DEPTH,
           (unsigned long long)cnt_calls[0], (unsigned long long)cnt_calls[1] ); }
static const char *cnt_name( void *f )
{
#if HAVE_MMX && ARCH_X86_64
    if( f == (void*)x264_deblock_h_chroma_422_avx || f == (void*)x264_deblock_h_chroma_422_intra_avx ) return "avx";
    if( f == (void*)x264_deblock_h_chroma_422_avx2 || f == (void*)x264_deblock_h_chroma_422_intra_avx2 ) return "avx2";
    if( f == (void*)x264_deblock_h_chroma_422_avx512icl || f == (void*)x264_deblock_h_chroma_422_intra_avx512icl ) return "avx512icl";
#endif
    return "other";
}
void x264_deblock_init( int cpu, x264_deblock_function_t *pf, int b_mbaff )
{
    deblock_init_real( cpu, pf, b_mbaff );
    if( !cnt_inter_real )
    {
        cnt_inter_real = pf->deblock_h_chroma_422;
        cnt_intra_real = pf->deblock_h_chroma_422_intra;
        fprintf( stderr, "DB422_CNT %d-bit pointers h_chroma_422 %s h_chroma_422_intra %s\n", BIT_DEPTH,
                 cnt_name( (void*)cnt_inter_real ), cnt_name( (void*)cnt_intra_real ) );
        atexit( cnt_report );
    }
    pf->deblock_h_chroma_422 = cnt_inter;
    pf->deblock_h_chroma_422_intra = cnt_intra;
}
EOF
}
iclpatch() { # dispatch the 8-bit avx512icl pair at AVX512ICL
    sed -i 's|^            /\* undispatched (checkasm tests them at this level): x264_deblock_h_chroma_422_avx512icl,$|            pf->deblock_h_chroma_422 = x264_deblock_h_chroma_422_avx512icl;\n            pf->deblock_h_chroma_422_intra = x264_deblock_h_chroma_422_intra_avx512icl;\n&|' common/deblock.c
    [ "$(grep -c 'pf->deblock_h_chroma_422 = x264_deblock_h_chroma_422_avx512icl;' common/deblock.c)" = 1 ]
}
xe_patch() { # tree flavour (in the tree)
    case $1 in arm*) [ $AB = icl ] && { iclpatch || { echo "iclpatch did not apply"; return 1; }; } ;; esac
    case $1 in *cnt) cntpatch || { echo "cntpatch did not apply"; return 1; } ;; esac
    return 0
}
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm8 --bench=deblock_h_chroma_422 1001 | grep -E 'deblock_h_chroma_422|nop'); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
