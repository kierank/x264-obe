#!/bin/bash
# Xeon E (E-2478, Intel AVX2) in-situ A/B: wip/x264-10b-cabac (tip 75947ac3), the 10-bit avx2_bmi2 CABAC rd 4x4,
# 8x8 rd and 4:2:2 chroma dc writer. From tools/notes-10b-cabac/ab-10b-cabac.sh MODE=avx2 (.44 under an AVX2
# --asm cap): same arms, the RD4_AVX2_LEVELS_MIN port variant and the CABLIVE counters.
# Copyright (C) 2026 Open Broadcast Systems Ltd
#
#   AB=avx2 bash 10b-cabac-ab.sh build | live | md5 | time 9 | report
# AB (default avx2):
#   avx2  base = 1c4583b1 (tip~3: kernels assembled, 10-bit undispatched: ssse3_lzcnt rd, C 4:2:2 dc writer),
#         arm = 093a2715 (tip~2: avx2_bmi2 for all three at 10-bit)
#   port  base = 093a2715, arm = 093a2715 with RD4_AVX2_LEVELS_MIN 17 (the 4x4 port without the level pass):
#         arm faster = the level pass loses on Intel
#   tip~1 (c1fa65f4, AVX-512 without ICL) and tip (75947ac3, Zen 4/5 rd2) change only AVX-512 pointers: on this
#   cpu they run what 093a2715 runs, so they are not arms here.
# The --asm cap of the .44 script (CAP=1 here) is not a no-op on this cpu: x264_cpu_detect also sets Cache64 and
#   AVXVNNI, which the list lacks. At 10-bit AVXVNNI has no reader, but Cache64 selects predict_8x8_ddl/ddr
#   ssse3_cache64 (common/x86/predict-c.c, HIGH_BIT_DEPTH block), so the cap swaps two intra kernels. Default off.
# Cells (10-bit builds): ffm422p10-i (--tff) / tc422p10-p (4:2:2: the dc writer runs in every mode), 8-bit 4:2:0
#   clips at 10-bit. Null cell: tile-chaos-p lowlat (trellis 0, no RD, 4:2:0: none of the three slots is called).
set -u
JOB=10b-cabac; AB=${AB:-avx2}; BRANCHES=wip/x264-10b-cabac
case $AB in
avx2) BASE=1c4583b1; ARM=093a2715 ;;
port) BASE=093a2715; ARM=093a2715 ;;
*) echo "unknown AB $AB"; exit 1 ;;
esac
[ "${CAP:-0}" = 1 ] && AB=${AB}-cap
BITDEPTH=10
CELLS="ffm422p10-i:lowlat ffm422p10-i:normal tc422p10-p:lowlat tc422p10-p:normal
       tile-chaos-p:lowlat tile-chaos-p:normal field-frame-mix-i:lowlat field-frame-mix-i:normal"
NULLCELLS="tile-chaos-p_lowlat"
LIVE_RE='cabac_block_residual|cabac_encode|rd_cost'
COUNT_TREES="basecnt armcnt"; COUNT_RE=CABLIVE
. "$(dirname "$0")/../lib.sh"
CAPS=""; [ "${CAP:-0}" = 1 ] && CAPS="--asm MMX2,SSE,SSE2,SSE3,SSSE3,SSE4.1,SSE4.2,AVX,FMA3,BMI1,BMI2,LZCNT,AVX2"
MODE_lowlat="$LOWLAT $CAPS"; MODE_normal="$NORMAL $CAPS"

livepatch() { # call counters on the three slots, and the pointer names (CABLIVE lines)
    sed -i 's/^void x264_bitstream_init( int cpu, x264_bitstream_function_t \*pf )$/static void bitstream_init_real( int cpu, x264_bitstream_function_t *pf )/' common/bitstream.c
    grep -q '^static void bitstream_init_real' common/bitstream.c || return 1
    cat >> common/bitstream.c <<'EOF'
typedef void (*cabres_fn)( dctcoef *, int, intptr_t, x264_cabac_t * );
static cabres_fn live_real[3];
static long live_calls[3];
static void live0( dctcoef *l, int i, intptr_t c, x264_cabac_t *cb ) { live_calls[0]++; live_real[0]( l, i, c, cb ); }
static void live1( dctcoef *l, int i, intptr_t c, x264_cabac_t *cb ) { live_calls[1]++; live_real[1]( l, i, c, cb ); }
static void live2( dctcoef *l, int i, intptr_t c, x264_cabac_t *cb ) { live_calls[2]++; if( live_real[2] ) live_real[2]( l, i, c, cb ); }
static void live_report( void ) { fprintf( stderr, "CABLIVE calls rd4 %ld rd8 %ld 422dc_writer %ld\n", live_calls[0], live_calls[1], live_calls[2] ); }
static const char *live_name( cabres_fn f )
{
#if HAVE_MMX && ARCH_X86_64
    if( f == x264_cabac_block_residual_rd_internal_ssse3_lzcnt || f == x264_cabac_block_residual_8x8_rd_internal_ssse3_lzcnt ) return "ssse3_lzcnt";
    if( f == x264_cabac_block_residual_rd_internal_avx2_bmi2 || f == x264_cabac_block_residual_8x8_rd_internal_avx2_bmi2 ||
        f == x264_cabac_block_residual_422_dc_internal_avx2_bmi2 ) return "avx2_bmi2";
    if( f == x264_cabac_block_residual_8x8_rd_internal_avx512 ) return "avx512";
    if( f == x264_cabac_block_residual_rd_internal_avx512icl || f == x264_cabac_block_residual_8x8_rd_internal_avx512icl ||
        f == x264_cabac_block_residual_422_dc_internal_avx512icl ) return "avx512icl";
    if( f == x264_cabac_block_residual_rd2_internal_avx512icl || f == x264_cabac_block_residual_8x8_rd2_internal_avx512icl ) return "rd2_avx512icl";
#endif
    return f ? "other" : "C";
}
void x264_bitstream_init( int cpu, x264_bitstream_function_t *pf )
{
    bitstream_init_real( cpu, pf );
    if( !live_real[0] )
    {
        live_real[0] = pf->cabac_block_residual_rd_internal;
        live_real[1] = pf->cabac_block_residual_8x8_rd_internal;
        live_real[2] = pf->cabac_block_residual_422_dc_internal;
        fprintf( stderr, "CABLIVE rd4 %s rd8 %s 422dc_writer %s\n", live_name( live_real[0] ), live_name( live_real[1] ), live_name( live_real[2] ) );
        atexit( live_report );
    }
    pf->cabac_block_residual_rd_internal = live0;
    pf->cabac_block_residual_8x8_rd_internal = live1;
    if( live_real[2] ) pf->cabac_block_residual_422_dc_internal = live2; /* NULL = the C writer, not counted */
}
EOF
}
xe_patch() { # tree flavour (in the tree)
    case $AB in port*) case $1 in arm*)
        sed -i 's/^    %define RD4_AVX2_LEVELS_MIN 2$/    %define RD4_AVX2_LEVELS_MIN 17/' common/x86/cabac-a.asm
        grep -q 'RD4_AVX2_LEVELS_MIN 17' common/x86/cabac-a.asm || { echo "port patch did not apply"; return 1; } ;;
    esac ;; esac
    case $1 in *cnt) livepatch || { echo "livepatch did not apply"; return 1; } ;; esac
}
xe_bench() { (cd $(xe_dir arm t) && taskset -c $CORE ./checkasm10 --bench=cabac 1001 | grep -E 'residual|nop'); }
[ -n "${XE_TEST:-}" ] || xe_main "$@"
