#!/bin/bash
# Xeon E (E-2478, Intel AVX2) / rack01 (EPYC 8324P, Zen 4) in-situ A/B, job dbkgap: wip/x264-deblock-gaps,
# the MBAFF / intra deblock pointers production interlaced content still reached below AVX2:
#   10-bit: deblock_luma_intra[0/1] avx -> avx2 (16 pixel edge per ymm), deblock_luma(_intra)_mbaff avx -> avx2
#           ([p|q] qword halves, rows 0-3 | 4-7 per lane);
#   8-bit:  deblock_chroma_420_intra_mbaff mmx2 -> avx, deblock_chroma_420_mbaff sse2 -> avx (4:2:0 MBAFF mixed edges).
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
# Install as xeone-jobs/dbkgap/dbkgap-ab.sh next to lib.sh (wip/x264-core3-jobs), then per AB:
#   AB=tip bash dbkgap-ab.sh build | live | md5 | time 9 | report
# AB (default tip):
#   tip  base = DBK_BASE (tip~1: every kernel assembled, nothing new dispatched), arm = DBK_TIP (the dispatch commit).
#        Xeon E: the Intel AVX2 verdict. rack01: the Zen 4 verdict for the same pointers. AVX-512 machines change
#        too: they take the 8-bit avx chroma MBAFF pair and the 10-bit avx2 luma MBAFF pair (they keep the icl luma intra).
#   icl  rack01 only: base = DBK_TIP, arm = DBK_TIP with the undispatched 10-bit x264_deblock_h_luma(_intra)_mbaff_avx512icl
#        dispatched at AVX512ICL (sed, xe_patch).
# Null cells (zero calls of every changed pointer, the counter trees show it): tile-chaos-p lowlat (progressive,
# no MBAFF edge, 8-bit) and ffm422-i ll50 (8-bit 4:2:2 MBAFF: its mixed edges go through deblock_chroma_422_mbaff
# = h_chroma_420, and the 8-bit luma pointers are unchanged). For AB=icl the 8-bit cells are all null.
# Clips are 30 frames; the 4:2:2 cells use the 10b-brief 50 Mbps lines.
set -u
JOB=dbkgap; AB=${AB:-tip}; BRANCHES=wip/x264-deblock-gaps
DBK_BASE=9ef632af; DBK_TIP=42c8bdbd
case $AB in
tip) BASE=$DBK_BASE; ARM=$DBK_TIP ;;
icl) BASE=$DBK_TIP; ARM=$DBK_TIP ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
BITDEPTH=all
CELLS="ffm422p10-i:ll50@10 ffm422p10-i:nm50@10 field-frame-mix-i:lowlat field-frame-mix-i:normal ffm422-i:ll50 tile-chaos-p:lowlat"
NULLCELLS="ffm422-i_ll50 tile-chaos-p_lowlat"
MD5CELLS="tc422p10-p:ll50@10 tc422p10-p:nm50@10 ffm422-i:nm50 field-frame-mix-i:lowlat@10 tile-chaos-p:normal"
LIVE_RE='deblock_h_luma(_intra)?_mbaff|deblock_[vh]_luma_intra|deblock_h_chroma(_intra)?_mbaff'
COUNT_TREES="basecnt armcnt"; COUNT_RE=DBKGAP_CNT
. "$(dirname "$0")/../lib.sh"
MODE_ll50="--preset veryfast --tune zerolatency --intra-refresh --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 1667 --nal-hrd fakevbr --threads 1"
MODE_nm50="--subme 6 --me hex --ref 2 --no-mixed-refs --no-chroma-me --trellis 1 --partitions i8x8,i4x4 --psy-rd 1.0:0 --bframes 3 --rc-lookahead 24 --keyint 30 --bitrate 50000 --vbv-maxrate 50000 --vbv-bufsize 50000 --nal-hrd fakevbr --threads 1"
cntpatch() { # liveness: call counts through the six changed slots and the names of their pointers, per bit depth
    sed -i 's/^void x264_deblock_init( int cpu, x264_deblock_function_t \*pf, int b_mbaff )$/static void deblock_init_real( int cpu, x264_deblock_function_t *pf, int b_mbaff )/' common/deblock.c
    grep -q '^static void deblock_init_real' common/deblock.c || return 1
    cat >> common/deblock.c <<'EOF'
#define CNT_N(f, isa) if( p == (void*)x264_deblock_##f##_##isa ) return #isa;
static const char *cnt_name( int i, void *p )
{
#if HAVE_MMX && ARCH_X86_64
    switch( i )
    {
        case 0: CNT_N(v_luma_intra, sse2) CNT_N(v_luma_intra, avx) CNT_N(v_luma_intra, avx2) CNT_N(v_luma_intra, avx512icl) break;
        case 1: CNT_N(h_luma_intra, sse2) CNT_N(h_luma_intra, avx) CNT_N(h_luma_intra, avx2) CNT_N(h_luma_intra, avx512icl) break;
#if HIGH_BIT_DEPTH
        case 2: CNT_N(h_luma_mbaff, sse2) CNT_N(h_luma_mbaff, avx) CNT_N(h_luma_mbaff, avx2) CNT_N(h_luma_mbaff, avx512icl) break;
#else
        case 2: CNT_N(h_luma_mbaff, sse2) CNT_N(h_luma_mbaff, avx) CNT_N(h_luma_mbaff, avx512icl) break;
#endif
        case 3: CNT_N(h_luma_intra_mbaff, sse2) CNT_N(h_luma_intra_mbaff, avx) CNT_N(h_luma_intra_mbaff, avx2) CNT_N(h_luma_intra_mbaff, avx512icl) break;
        case 4: CNT_N(h_chroma_mbaff, sse2) CNT_N(h_chroma_mbaff, avx) break;
#if HIGH_BIT_DEPTH
        case 5: CNT_N(h_chroma_intra_mbaff, sse2) CNT_N(h_chroma_intra_mbaff, avx) break;
#else
        case 5: CNT_N(h_chroma_intra_mbaff, mmx2) CNT_N(h_chroma_intra_mbaff, sse2) CNT_N(h_chroma_intra_mbaff, avx) break;
#endif
    }
#endif
    return "C/other";
}
static const char *cnt_slot[6] = { "luma_intra[1]", "luma_intra[0]", "luma_mbaff", "luma_intra_mbaff", "chroma_420_mbaff", "chroma_420_intra_mbaff" };
static void *cnt_real[6];
static uint64_t cnt_calls[6];
#define CNT_INTER(i) static void cnt_f##i( pixel *pix, intptr_t stride, int alpha, int beta, int8_t *tc0 )\
{ __atomic_fetch_add( &cnt_calls[i], 1, __ATOMIC_RELAXED ); ((x264_deblock_inter_t)cnt_real[i])( pix, stride, alpha, beta, tc0 ); }
#define CNT_INTRA(i) static void cnt_f##i( pixel *pix, intptr_t stride, int alpha, int beta )\
{ __atomic_fetch_add( &cnt_calls[i], 1, __ATOMIC_RELAXED ); ((x264_deblock_intra_t)cnt_real[i])( pix, stride, alpha, beta ); }
CNT_INTRA(0) CNT_INTRA(1) CNT_INTER(2) CNT_INTRA(3) CNT_INTER(4) CNT_INTRA(5)
static void cnt_report( void )
{
    fprintf( stderr, "DBKGAP_CNT %d-bit calls", BIT_DEPTH );
    for( int i = 0; i < 6; i++ )
        fprintf( stderr, " %s %llu", cnt_slot[i], (unsigned long long)cnt_calls[i] );
    fprintf( stderr, "\n" );
}
void x264_deblock_init( int cpu, x264_deblock_function_t *pf, int b_mbaff )
{
    deblock_init_real( cpu, pf, b_mbaff );
    if( !cnt_real[0] )
    {
        cnt_real[0] = (void*)pf->deblock_luma_intra[1];
        cnt_real[1] = (void*)pf->deblock_luma_intra[0];
        cnt_real[2] = (void*)pf->deblock_luma_mbaff;
        cnt_real[3] = (void*)pf->deblock_luma_intra_mbaff;
        cnt_real[4] = (void*)pf->deblock_chroma_420_mbaff;
        cnt_real[5] = (void*)pf->deblock_chroma_420_intra_mbaff;
        fprintf( stderr, "DBKGAP_CNT %d-bit pointers", BIT_DEPTH );
        for( int i = 0; i < 6; i++ )
            fprintf( stderr, " %s %s", cnt_slot[i], cnt_name( i, cnt_real[i] ) );
        fprintf( stderr, "\n" );
        atexit( cnt_report );
    }
    pf->deblock_luma_intra[1] = cnt_f0;
    pf->deblock_luma_intra[0] = cnt_f1;
    pf->deblock_luma_mbaff = cnt_f2;
    pf->deblock_luma_intra_mbaff = cnt_f3;
    pf->deblock_chroma_420_mbaff = cnt_f4;
    pf->deblock_chroma_420_intra_mbaff = cnt_f5;
}
EOF
}
iclpatch() { # dispatch the 10-bit avx512icl MBAFF pair at AVX512ICL
    sed -i 's|^            /\* undispatched (checkasm tests them at this level): x264_deblock_h_luma_mbaff_avx512icl,$|            pf->deblock_luma_mbaff = x264_deblock_h_luma_mbaff_avx512icl;\n            pf->deblock_luma_intra_mbaff = x264_deblock_h_luma_intra_mbaff_avx512icl;\n&|' common/deblock.c
    [ "$(grep -c 'pf->deblock_luma_mbaff = x264_deblock_h_luma_mbaff_avx512icl;' common/deblock.c)" = 1 ]
}
xe_patch() { # tree flavour (in the tree)
    case $1 in arm*) [ $AB = icl ] && { iclpatch || { echo "iclpatch did not apply"; return 1; }; } ;; esac
    case $1 in *cnt) cntpatch || { echo "cntpatch did not apply"; return 1; } ;; esac
    return 0
}
xe_bench() { (cd $(xe_dir arm t) && for d in 8 10; do taskset -c $CORE ./checkasm$d --bench=deblock 1001 | grep -E 'nop|deblock_(luma_intra|luma_mbaff|luma_intra_mbaff|chroma_420_mbaff|chroma_420_intra_mbaff)'; done); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
