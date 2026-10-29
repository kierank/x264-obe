/*****************************************************************************
 * quant.c: quantization and level-run
 *****************************************************************************
 * Copyright (C) 2005-2014 x264 project
 *
 * Authors: Loren Merritt <lorenm@u.washington.edu>
 *          Jason Garrett-Glaser <darkshikari@gmail.com>
 *          Christian Heine <sennindemokrit@gmx.net>
 *          Henrik Gramner <henrik@gramner.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02111, USA.
 *
 * This program is also available under a commercial proprietary license.
 * For more information, contact us at licensing@x264.com.
 *****************************************************************************/

#include "common.h"

#if HAVE_MMX
#include "x86/quant.h"
#endif
#if ARCH_PPC
#   include "ppc/quant.h"
#endif
#if ARCH_ARM
#   include "arm/quant.h"
#endif

#define QUANT_ONE( coef, mf, f ) \
{ \
    if( (coef) > 0 ) \
        (coef) = (f + (coef)) * (mf) >> 16; \
    else \
        (coef) = - ((f - (coef)) * (mf) >> 16); \
    nz |= (coef); \
}

static int quant_8x8( dctcoef dct[64], udctcoef mf[64], udctcoef bias[64] )
{
    int nz = 0;
    for( int i = 0; i < 64; i++ )
        QUANT_ONE( dct[i], mf[i], bias[i] );
    return !!nz;
}

static int quant_4x4( dctcoef dct[16], udctcoef mf[16], udctcoef bias[16] )
{
    int nz = 0;
    for( int i = 0; i < 16; i++ )
        QUANT_ONE( dct[i], mf[i], bias[i] );
    return !!nz;
}

static int quant_4x4x4( dctcoef dct[4][16], udctcoef mf[16], udctcoef bias[16] )
{
    int nza = 0;
    for( int j = 0; j < 4; j++ )
    {
        int nz = 0;
        for( int i = 0; i < 16; i++ )
            QUANT_ONE( dct[j][i], mf[i], bias[i] );
        nza |= (!!nz)<<j;
    }
    return nza;
}

static int quant_4x4_dc( dctcoef dct[16], int mf, int bias )
{
    int nz = 0;
    for( int i = 0; i < 16; i++ )
        QUANT_ONE( dct[i], mf, bias );
    return !!nz;
}

static int quant_2x2_dc( dctcoef dct[4], int mf, int bias )
{
    int nz = 0;
    QUANT_ONE( dct[0], mf, bias );
    QUANT_ONE( dct[1], mf, bias );
    QUANT_ONE( dct[2], mf, bias );
    QUANT_ONE( dct[3], mf, bias );
    return !!nz;
}

#define DEQUANT_SHL( x ) \
    dct[x] = ( dct[x] * dequant_mf[i_mf][x] ) << i_qbits

#define DEQUANT_SHR( x ) \
    dct[x] = ( dct[x] * dequant_mf[i_mf][x] + f ) >> (-i_qbits)

static void dequant_4x4( dctcoef dct[16], int dequant_mf[6][16], int i_qp )
{
    const int i_mf = i_qp%6;
    const int i_qbits = i_qp/6 - 4;

    if( i_qbits >= 0 )
    {
        for( int i = 0; i < 16; i++ )
            DEQUANT_SHL( i );
    }
    else
    {
        const int f = 1 << (-i_qbits-1);
        for( int i = 0; i < 16; i++ )
            DEQUANT_SHR( i );
    }
}

static void dequant_8x8( dctcoef dct[64], int dequant_mf[6][64], int i_qp )
{
    const int i_mf = i_qp%6;
    const int i_qbits = i_qp/6 - 6;

    if( i_qbits >= 0 )
    {
        for( int i = 0; i < 64; i++ )
            DEQUANT_SHL( i );
    }
    else
    {
        const int f = 1 << (-i_qbits-1);
        for( int i = 0; i < 64; i++ )
            DEQUANT_SHR( i );
    }
}

static void dequant_4x4_dc( dctcoef dct[16], int dequant_mf[6][16], int i_qp )
{
    const int i_qbits = i_qp/6 - 6;

    if( i_qbits >= 0 )
    {
        const int i_dmf = dequant_mf[i_qp%6][0] << i_qbits;
        for( int i = 0; i < 16; i++ )
            dct[i] *= i_dmf;
    }
    else
    {
        const int i_dmf = dequant_mf[i_qp%6][0];
        const int f = 1 << (-i_qbits-1);
        for( int i = 0; i < 16; i++ )
            dct[i] = ( dct[i] * i_dmf + f ) >> (-i_qbits);
    }
}

#define IDCT_DEQUANT_2X4_START \
    int a0 = dct[0] + dct[1]; \
    int a1 = dct[2] + dct[3]; \
    int a2 = dct[4] + dct[5]; \
    int a3 = dct[6] + dct[7]; \
    int a4 = dct[0] - dct[1]; \
    int a5 = dct[2] - dct[3]; \
    int a6 = dct[4] - dct[5]; \
    int a7 = dct[6] - dct[7]; \
    int b0 = a0 + a1; \
    int b1 = a2 + a3; \
    int b2 = a4 + a5; \
    int b3 = a6 + a7; \
    int b4 = a0 - a1; \
    int b5 = a2 - a3; \
    int b6 = a4 - a5; \
    int b7 = a6 - a7;

static void idct_dequant_2x4_dc( dctcoef dct[8], dctcoef dct4x4[8][16], int dequant_mf[6][16], int i_qp )
{
    IDCT_DEQUANT_2X4_START
    int dmf = dequant_mf[i_qp%6][0] << i_qp/6;
    dct4x4[0][0] = ((b0 + b1) * dmf + 32) >> 6;
    dct4x4[1][0] = ((b2 + b3) * dmf + 32) >> 6;
    dct4x4[2][0] = ((b0 - b1) * dmf + 32) >> 6;
    dct4x4[3][0] = ((b2 - b3) * dmf + 32) >> 6;
    dct4x4[4][0] = ((b4 - b5) * dmf + 32) >> 6;
    dct4x4[5][0] = ((b6 - b7) * dmf + 32) >> 6;
    dct4x4[6][0] = ((b4 + b5) * dmf + 32) >> 6;
    dct4x4[7][0] = ((b6 + b7) * dmf + 32) >> 6;
}

static void idct_dequant_2x4_dconly( dctcoef dct[8], int dequant_mf[6][16], int i_qp )
{
    IDCT_DEQUANT_2X4_START
    int dmf = dequant_mf[i_qp%6][0] << i_qp/6;
    dct[0] = ((b0 + b1) * dmf + 32) >> 6;
    dct[1] = ((b2 + b3) * dmf + 32) >> 6;
    dct[2] = ((b0 - b1) * dmf + 32) >> 6;
    dct[3] = ((b2 - b3) * dmf + 32) >> 6;
    dct[4] = ((b4 - b5) * dmf + 32) >> 6;
    dct[5] = ((b6 - b7) * dmf + 32) >> 6;
    dct[6] = ((b4 + b5) * dmf + 32) >> 6;
    dct[7] = ((b6 + b7) * dmf + 32) >> 6;
}

static ALWAYS_INLINE void optimize_chroma_idct_dequant_2x4( dctcoef out[8], dctcoef dct[8], int dmf )
{
    IDCT_DEQUANT_2X4_START
    out[0] = ((b0 + b1) * dmf + 2080) >> 6; /* 2080 = 32 + (32<<6) */
    out[1] = ((b2 + b3) * dmf + 2080) >> 6;
    out[2] = ((b0 - b1) * dmf + 2080) >> 6;
    out[3] = ((b2 - b3) * dmf + 2080) >> 6;
    out[4] = ((b4 - b5) * dmf + 2080) >> 6;
    out[5] = ((b6 - b7) * dmf + 2080) >> 6;
    out[6] = ((b4 + b5) * dmf + 2080) >> 6;
    out[7] = ((b6 + b7) * dmf + 2080) >> 6;
}
#undef IDCT_DEQUANT_2X4_START

static ALWAYS_INLINE void optimize_chroma_idct_dequant_2x2( dctcoef out[4], dctcoef dct[4], int dmf )
{
    int d0 = dct[0] + dct[1];
    int d1 = dct[2] + dct[3];
    int d2 = dct[0] - dct[1];
    int d3 = dct[2] - dct[3];
    out[0] = ((d0 + d1) * dmf >> 5) + 32;
    out[1] = ((d0 - d1) * dmf >> 5) + 32;
    out[2] = ((d2 + d3) * dmf >> 5) + 32;
    out[3] = ((d2 - d3) * dmf >> 5) + 32;
}

static ALWAYS_INLINE int optimize_chroma_round( dctcoef *ref, dctcoef *dct, int dequant_mf, int chroma422 )
{
    dctcoef out[8];

    if( chroma422 )
        optimize_chroma_idct_dequant_2x4( out, dct, dequant_mf );
    else
        optimize_chroma_idct_dequant_2x2( out, dct, dequant_mf );

    int sum = 0;
    for( int i = 0; i < (chroma422?8:4); i++ )
        sum |= ref[i] ^ out[i];
    return sum >> 6;
}

static ALWAYS_INLINE int optimize_chroma_dc_internal( dctcoef *dct, int dequant_mf, int chroma422 )
{
    /* dequant_mf = h->dequant4_mf[CQM_4IC + b_inter][i_qp%6][0] << i_qp/6, max 32*64 */
    dctcoef dct_orig[8];
    int coeff, nz;

    if( chroma422 )
        optimize_chroma_idct_dequant_2x4( dct_orig, dct, dequant_mf );
    else
        optimize_chroma_idct_dequant_2x2( dct_orig, dct, dequant_mf );

    /* If the DC coefficients already round to zero, terminate early. */
    int sum = 0;
    for( int i = 0; i < (chroma422?8:4); i++ )
        sum |= dct_orig[i];
    if( !(sum >> 6) )
        return 0;

    /* Start with the highest frequency coefficient... is this the best option? */
    for( nz = 0, coeff = (chroma422?7:3); coeff >= 0; coeff-- )
    {
        int level = dct[coeff];
        int sign = level>>31 | 1; /* dct[coeff] < 0 ? -1 : 1 */

        while( level )
        {
            dct[coeff] = level - sign;
            if( optimize_chroma_round( dct_orig, dct, dequant_mf, chroma422 ) )
            {
                nz = 1;
                dct[coeff] = level;
                break;
            }
            level -= sign;
        }
    }

    return nz;
}

static int optimize_chroma_2x2_dc( dctcoef dct[4], int dequant_mf )
{
    return optimize_chroma_dc_internal( dct, dequant_mf, 0 );
}

static int optimize_chroma_2x4_dc( dctcoef dct[8], int dequant_mf )
{
    return optimize_chroma_dc_internal( dct, dequant_mf, 1 );
}

static void x264_denoise_dct( dctcoef *dct, uint32_t *sum, udctcoef *offset, int size )
{
    for( int i = 0; i < size; i++ )
    {
        int level = dct[i];
        int sign = level>>31;
        level = (level+sign)^sign;
        sum[i] += level;
        level -= offset[i];
        dct[i] = level<0 ? 0 : (level^sign)-sign;
    }
}

/* (ref: JVT-B118)
 * x264_mb_decimate_score: given dct coeffs it returns a score to see if we could empty this dct coeffs
 * to 0 (low score means set it to null)
 * Used in inter macroblock (luma and chroma)
 *  luma: for a 8x8 block: if score < 4 -> null
 *        for the complete mb: if score < 6 -> null
 *  chroma: for the complete mb: if score < 7 -> null
 */

static int ALWAYS_INLINE x264_decimate_score_internal( dctcoef *dct, int i_max )
{
    const uint8_t *ds_table = (i_max == 64) ? x264_decimate_table8 : x264_decimate_table4;
    int i_score = 0;
    int idx = i_max - 1;

    while( idx >= 0 && dct[idx] == 0 )
        idx--;
    while( idx >= 0 )
    {
        int i_run;

        if( (unsigned)(dct[idx--] + 1) > 2 )
            return 9;

        i_run = 0;
        while( idx >= 0 && dct[idx] == 0 )
        {
            idx--;
            i_run++;
        }
        i_score += ds_table[i_run];
    }

    return i_score;
}

static int x264_decimate_score15( dctcoef *dct )
{
    return x264_decimate_score_internal( dct+1, 15 );
}
static int x264_decimate_score16( dctcoef *dct )
{
    return x264_decimate_score_internal( dct, 16 );
}
static int x264_decimate_score64( dctcoef *dct )
{
    return x264_decimate_score_internal( dct, 64 );
}

/* quant_4x4x4, then for each nonzero block: zigzag into level, decimate score, dequant in place
 * (unless dequant_mf is NULL). Returns the nonzero mask | min(summed score, 9) << 4. */
static ALWAYS_INLINE int quant_4x4x4_scan( dctcoef dct[4][16], dctcoef level[4][16], udctcoef mf[16], udctcoef bias[16],
                                           int dequant_mf[6][16], int i_qp, int b_field, int b_ac )
{
    int nza = 0, score = 0;
    for( int j = 0; j < 4; j++ )
    {
        int nz = 0;
        for( int i = 0; i < 16; i++ )
            QUANT_ONE( dct[j][i], mf[i], bias[i] );
        if( !nz )
            continue;
        nza |= 1 << j;
        for( int i = 0; i < 16; i++ )
            level[j][i] = dct[j][x264_zigzag_scan4[b_field][i]];
        score += x264_decimate_score_internal( level[j]+b_ac, 16-b_ac );
        if( dequant_mf )
            dequant_4x4( dct[j], dequant_mf, i_qp );
    }
    return nza | X264_MIN( score, 9 ) << 4;
}

int x264_quant_4x4x4_scan_frame( dctcoef dct[4][16], dctcoef level[4][16], udctcoef mf[16], udctcoef bias[16], int dequant_mf[6][16], int i_qp )
{
    return quant_4x4x4_scan( dct, level, mf, bias, dequant_mf, i_qp, 0, 0 );
}
int x264_quant_4x4x4_scan_field( dctcoef dct[4][16], dctcoef level[4][16], udctcoef mf[16], udctcoef bias[16], int dequant_mf[6][16], int i_qp )
{
    return quant_4x4x4_scan( dct, level, mf, bias, dequant_mf, i_qp, 1, 0 );
}
int x264_quant_4x4x4_scan_frame_ac( dctcoef dct[4][16], dctcoef level[4][16], udctcoef mf[16], udctcoef bias[16], int dequant_mf[6][16], int i_qp )
{
    return quant_4x4x4_scan( dct, level, mf, bias, dequant_mf, i_qp, 0, 1 );
}
int x264_quant_4x4x4_scan_field_ac( dctcoef dct[4][16], dctcoef level[4][16], udctcoef mf[16], udctcoef bias[16], int dequant_mf[6][16], int i_qp )
{
    return quant_4x4x4_scan( dct, level, mf, bias, dequant_mf, i_qp, 1, 1 );
}

/* quant_8x8, then if nonzero: zigzag into level, decimate score, dequant in place
 * (unless dequant_mf is NULL). Returns 0, or 1 | min(score, 9) << 4. */
static ALWAYS_INLINE int quant_8x8_scan( dctcoef dct[64], dctcoef level[64], udctcoef mf[64], udctcoef bias[64],
                                         int dequant_mf[6][64], int i_qp, int b_field )
{
    int nz = 0;
    for( int i = 0; i < 64; i++ )
        QUANT_ONE( dct[i], mf[i], bias[i] );
    if( !nz )
        return 0;
    for( int i = 0; i < 64; i++ )
        level[i] = dct[x264_zigzag_scan8[b_field][i]];
    int score = x264_decimate_score_internal( level, 64 );
    if( dequant_mf )
        dequant_8x8( dct, dequant_mf, i_qp );
    return 1 | X264_MIN( score, 9 ) << 4;
}

int x264_quant_8x8_scan_frame( dctcoef dct[64], dctcoef level[64], udctcoef mf[64], udctcoef bias[64], int dequant_mf[6][64], int i_qp )
{
    return quant_8x8_scan( dct, level, mf, bias, dequant_mf, i_qp, 0 );
}
int x264_quant_8x8_scan_field( dctcoef dct[64], dctcoef level[64], udctcoef mf[64], udctcoef bias[64], int dequant_mf[6][64], int i_qp )
{
    return quant_8x8_scan( dct, level, mf, bias, dequant_mf, i_qp, 1 );
}

#define last(num)\
static int x264_coeff_last##num( dctcoef *l )\
{\
    int i_last = num-1;\
    while( i_last >= 0 && l[i_last] == 0 )\
        i_last--;\
    return i_last;\
}

last(4)
last(8)
last(15)
last(16)
last(64)

#define level_run(num)\
static int x264_coeff_level_run##num( dctcoef *dct, x264_run_level_t *runlevel )\
{\
    int i_last = runlevel->last = x264_coeff_last##num(dct);\
    int i_total = 0;\
    int mask = 0;\
    do\
    {\
        runlevel->level[i_total++] = dct[i_last];\
        mask |= 1 << (i_last);\
        while( --i_last >= 0 && dct[i_last] == 0 );\
    } while( i_last >= 0 );\
    runlevel->mask = mask;\
    return i_total;\
}

level_run(4)
level_run(8)
level_run(15)
level_run(16)

#if ARCH_X86_64
#define INIT_TRELLIS(cpu) do {\
    pf->trellis_cabac_4x4 = x264_trellis_cabac_4x4_##cpu;\
    pf->trellis_cabac_8x8 = x264_trellis_cabac_8x8_##cpu;\
    pf->trellis_cabac_4x4_psy = x264_trellis_cabac_4x4_psy_##cpu;\
    pf->trellis_cabac_8x8_psy = x264_trellis_cabac_8x8_psy_##cpu;\
    pf->trellis_cabac_dc = x264_trellis_cabac_dc_##cpu;\
    pf->trellis_cabac_chroma_422_dc = x264_trellis_cabac_chroma_422_dc_##cpu;\
} while( 0 )
#else
#define INIT_TRELLIS(...)
#endif
#if ARCH_X86_64 && !defined(_WIN32)
/* the asm reads x264_trellis_wrap_t at fixed offsets */
typedef char x264_trellis_wrap_layout[offsetof( x264_trellis_wrap_t, scan ) == 56 && offsetof( x264_trellis_wrap_t, lambda2 ) == 64 &&
                                      offsetof( x264_trellis_wrap_t, b_interlaced ) == 76 ? 1 : -1];
#define INIT_TRELLIS_WRAP(cpu) do {\
    pf->trellis_wrap_4x4x4 = x264_trellis_wrap_4x4x4_##cpu;\
    pf->trellis_wrap_4x4 = x264_trellis_wrap_4x4_##cpu;\
    pf->trellis_wrap_8x8 = x264_trellis_wrap_8x8_##cpu;\
    pf->trellis_wrap_dc[0] = x264_trellis_wrap_dc4_##cpu;\
    pf->trellis_wrap_dc[1] = x264_trellis_wrap_dc8_##cpu;\
    pf->trellis_wrap_dc[2] = x264_trellis_wrap_dc16_##cpu;\
} while( 0 )
#else
#define INIT_TRELLIS_WRAP(...)
#endif

#if HAVE_MMX && ARCH_X86_64 && !defined(_WIN32)
/* the avx512 trellis_wrap in ymm, but the 10-bit 8x8 */
void x264_trellis_wrap_ymm_init( x264_quant_function_t *pf )
{
    INIT_TRELLIS_WRAP( avx512 );
    pf->trellis_wrap_4x4x4 = x264_trellis_wrap_4x4x4_ymm_avx512;
#if HIGH_BIT_DEPTH
    pf->trellis_wrap_4x4 = x264_trellis_wrap_4x4_ymm_avx512;
    pf->trellis_wrap_dc[2] = x264_trellis_wrap_dc16_ymm_avx512;
#else
    pf->trellis_wrap_8x8 = x264_trellis_wrap_8x8_ymm_avx512;
#endif
}
#endif

#if HAVE_MMX && ARCH_X86_64 && !defined(_WIN32)
/* trellis_wrap avx512 layout triple: TRW512_ARM 0 the zmm arm, 1 the ymm arm, 2 the twin (the
 * avx2 wrapper of 4ea8b2f3). The gates are the addresses of x264_trw512_on (api.c) and of the
 * never defined x264_trw512_off0/1, which link as 0. The code is the same in all three. */
#define TRW512_ARM 2
extern const char x264_trw512_on __attribute__((weak, visibility("hidden")));
extern const char x264_trw512_off0 __attribute__((weak, visibility("hidden")));
extern const char x264_trw512_off1 __attribute__((weak, visibility("hidden")));
#define TRW512_INIT do {\
    if( (TRW512_ARM == 0 ? &x264_trw512_on : &x264_trw512_off0) != NULL )\
        INIT_TRELLIS_WRAP( avx512 );\
    else if( (TRW512_ARM == 1 ? &x264_trw512_on : &x264_trw512_off1) != NULL )\
        x264_trellis_wrap_ymm_init( pf );\
} while( 0 )
#endif

void x264_quant_init( x264_t *h, int cpu, x264_quant_function_t *pf )
{
    pf->trellis_wrap_4x4x4 = NULL;
    pf->trellis_wrap_4x4 = NULL;
    pf->trellis_wrap_8x8 = NULL;
    for( int i = 0; i < 3; i++ )
        pf->trellis_wrap_dc[i] = NULL;
    pf->quant_8x8 = quant_8x8;
    pf->quant_4x4 = quant_4x4;
    pf->quant_4x4x4 = quant_4x4x4;
    pf->quant_4x4_dc = quant_4x4_dc;
    pf->quant_2x2_dc = quant_2x2_dc;

    pf->dequant_4x4 = dequant_4x4;
    pf->dequant_4x4_dc = dequant_4x4_dc;
    pf->dequant_8x8 = dequant_8x8;

    pf->idct_dequant_2x4_dc = idct_dequant_2x4_dc;
    pf->idct_dequant_2x4_dconly = idct_dequant_2x4_dconly;

    pf->optimize_chroma_2x2_dc = optimize_chroma_2x2_dc;
    pf->optimize_chroma_2x4_dc = optimize_chroma_2x4_dc;

    pf->denoise_dct = x264_denoise_dct;
    pf->decimate_score15 = x264_decimate_score15;
    pf->decimate_score16 = x264_decimate_score16;
    pf->decimate_score64 = x264_decimate_score64;

    pf->coeff_last4 = x264_coeff_last4;
    pf->coeff_last8 = x264_coeff_last8;
    pf->coeff_last[  DCT_LUMA_AC] = x264_coeff_last15;
    pf->coeff_last[ DCT_LUMA_4x4] = x264_coeff_last16;
    pf->coeff_last[ DCT_LUMA_8x8] = x264_coeff_last64;
    pf->coeff_level_run4 = x264_coeff_level_run4;
    pf->coeff_level_run8 = x264_coeff_level_run8;
    pf->coeff_level_run[  DCT_LUMA_AC] = x264_coeff_level_run15;
    pf->coeff_level_run[ DCT_LUMA_4x4] = x264_coeff_level_run16;

#if HIGH_BIT_DEPTH
#if HAVE_MMX
    INIT_TRELLIS( sse2 );
    if( cpu&X264_CPU_MMX2 )
    {
#if ARCH_X86
        pf->denoise_dct = x264_denoise_dct_mmx;
        pf->decimate_score15 = x264_decimate_score15_mmx2;
        pf->decimate_score16 = x264_decimate_score16_mmx2;
        pf->decimate_score64 = x264_decimate_score64_mmx2;
        pf->coeff_last8 = x264_coeff_last8_mmx2;
        pf->coeff_last[  DCT_LUMA_AC] = x264_coeff_last15_mmx2;
        pf->coeff_last[ DCT_LUMA_4x4] = x264_coeff_last16_mmx2;
        pf->coeff_last[ DCT_LUMA_8x8] = x264_coeff_last64_mmx2;
        pf->coeff_level_run8 = x264_coeff_level_run8_mmx2;
        pf->coeff_level_run[  DCT_LUMA_AC] = x264_coeff_level_run15_mmx2;
        pf->coeff_level_run[ DCT_LUMA_4x4] = x264_coeff_level_run16_mmx2;
#endif
        pf->coeff_last4 = x264_coeff_last4_mmx2;
        pf->coeff_level_run4 = x264_coeff_level_run4_mmx2;
        if( cpu&X264_CPU_LZCNT )
            pf->coeff_level_run4 = x264_coeff_level_run4_mmx2_lzcnt;
    }
    if( cpu&X264_CPU_SSE2 )
    {
        pf->quant_4x4 = x264_quant_4x4_sse2;
        pf->quant_4x4x4 = x264_quant_4x4x4_sse2;
        pf->quant_8x8 = x264_quant_8x8_sse2;
        pf->quant_2x2_dc = x264_quant_2x2_dc_sse2;
        pf->quant_4x4_dc = x264_quant_4x4_dc_sse2;
        pf->dequant_4x4 = x264_dequant_4x4_sse2;
        pf->dequant_8x8 = x264_dequant_8x8_sse2;
        pf->dequant_4x4_dc = x264_dequant_4x4dc_sse2;
        pf->idct_dequant_2x4_dc = x264_idct_dequant_2x4_dc_sse2;
        pf->idct_dequant_2x4_dconly = x264_idct_dequant_2x4_dconly_sse2;
        pf->denoise_dct = x264_denoise_dct_sse2;
        pf->decimate_score15 = x264_decimate_score15_sse2;
        pf->decimate_score16 = x264_decimate_score16_sse2;
        pf->decimate_score64 = x264_decimate_score64_sse2;
        pf->coeff_last8 = x264_coeff_last8_sse2;
        pf->coeff_last[ DCT_LUMA_AC] = x264_coeff_last15_sse2;
        pf->coeff_last[DCT_LUMA_4x4] = x264_coeff_last16_sse2;
        pf->coeff_last[DCT_LUMA_8x8] = x264_coeff_last64_sse2;
        pf->coeff_level_run8 = x264_coeff_level_run8_sse2;
        pf->coeff_level_run[ DCT_LUMA_AC] = x264_coeff_level_run15_sse2;
        pf->coeff_level_run[DCT_LUMA_4x4] = x264_coeff_level_run16_sse2;
        if( cpu&X264_CPU_LZCNT )
        {
            pf->coeff_last4 = x264_coeff_last4_mmx2_lzcnt;
            pf->coeff_last8 = x264_coeff_last8_sse2_lzcnt;
            pf->coeff_last[ DCT_LUMA_AC] = x264_coeff_last15_sse2_lzcnt;
            pf->coeff_last[DCT_LUMA_4x4] = x264_coeff_last16_sse2_lzcnt;
            pf->coeff_last[DCT_LUMA_8x8] = x264_coeff_last64_sse2_lzcnt;
            pf->coeff_level_run8 = x264_coeff_level_run8_sse2_lzcnt;
            pf->coeff_level_run[ DCT_LUMA_AC] = x264_coeff_level_run15_sse2_lzcnt;
            pf->coeff_level_run[DCT_LUMA_4x4] = x264_coeff_level_run16_sse2_lzcnt;
        }
    }
    if( cpu&X264_CPU_SSSE3 )
    {
        pf->quant_4x4 = x264_quant_4x4_ssse3;
        pf->quant_4x4x4 = x264_quant_4x4x4_ssse3;
        pf->quant_8x8 = x264_quant_8x8_ssse3;
        pf->quant_2x2_dc = x264_quant_2x2_dc_ssse3;
        pf->quant_4x4_dc = x264_quant_4x4_dc_ssse3;
        pf->denoise_dct = x264_denoise_dct_ssse3;
        pf->decimate_score15 = x264_decimate_score15_ssse3;
        pf->decimate_score16 = x264_decimate_score16_ssse3;
        pf->decimate_score64 = x264_decimate_score64_ssse3;
        INIT_TRELLIS( ssse3 );
    }
    if( cpu&X264_CPU_SSE4 )
    {
        pf->quant_2x2_dc = x264_quant_2x2_dc_sse4;
        pf->quant_4x4_dc = x264_quant_4x4_dc_sse4;
        pf->quant_4x4 = x264_quant_4x4_sse4;
        pf->quant_4x4x4 = x264_quant_4x4x4_sse4;
        pf->quant_8x8 = x264_quant_8x8_sse4;
    }
    if( cpu&X264_CPU_AVX )
    {
        pf->idct_dequant_2x4_dc = x264_idct_dequant_2x4_dc_avx;
        pf->idct_dequant_2x4_dconly = x264_idct_dequant_2x4_dconly_avx;
        pf->denoise_dct = x264_denoise_dct_avx;
    }
    if( cpu&X264_CPU_XOP )
    {
        pf->dequant_4x4_dc = x264_dequant_4x4dc_xop;
        if( h->param.i_cqm_preset != X264_CQM_FLAT )
        {
            pf->dequant_4x4 = x264_dequant_4x4_xop;
            pf->dequant_8x8 = x264_dequant_8x8_xop;
        }
    }
    if( cpu&X264_CPU_AVX2 )
    {
        pf->quant_4x4 = x264_quant_4x4_avx2;
        INIT_TRELLIS( avx2 );
        INIT_TRELLIS_WRAP( avx2 );
        pf->quant_4x4_dc = x264_quant_4x4_dc_avx2;
        pf->quant_8x8 = x264_quant_8x8_avx2;
        pf->quant_4x4x4 = x264_quant_4x4x4_avx2;
        pf->dequant_4x4 = x264_dequant_4x4_avx2;
        pf->dequant_8x8 = x264_dequant_8x8_avx2;
        pf->dequant_4x4_dc = x264_dequant_4x4dc_avx2;
        pf->denoise_dct = x264_denoise_dct_avx2;
        if( cpu&X264_CPU_LZCNT )
        {
            pf->coeff_last[DCT_LUMA_8x8] = x264_coeff_last64_avx2_lzcnt;
        }
    }
    if( cpu&X264_CPU_AVX512 )
    {
        TRW512_INIT;
        pf->dequant_4x4 = x264_dequant_4x4_avx512;
        pf->dequant_8x8 = x264_dequant_8x8_avx512;
        pf->decimate_score15 = x264_decimate_score15_avx512;
        pf->decimate_score16 = x264_decimate_score16_avx512;
        pf->decimate_score64 = x264_decimate_score64_avx512;
        pf->coeff_last4 = x264_coeff_last4_avx512;
        pf->coeff_last8 = x264_coeff_last8_avx512;
        pf->coeff_last[ DCT_LUMA_AC] = x264_coeff_last15_avx512;
        pf->coeff_last[DCT_LUMA_4x4] = x264_coeff_last16_avx512;
        /* coeff_last64 avx512 1.90x avx2_lzcnt on rack01 Zen 4 */
        if( !(cpu&X264_CPU_LZCNT) )
        {
            pf->coeff_last[DCT_LUMA_8x8] = x264_coeff_last64_avx512;
        }
    }
    if( cpu&X264_CPU_AVX512ICL )
    {
        pf->dequant_4x4 = x264_dequant_4x4_avx512icl;
        pf->dequant_4x4_dc = x264_dequant_4x4dc_avx512icl;
        pf->optimize_chroma_2x2_dc = x264_optimize_chroma_2x2_dc_avx512icl;
        pf->denoise_dct = x264_denoise_dct_avx512icl;
        pf->quant_2x2_dc = x264_quant_2x2_dc_avx512icl;
        pf->optimize_chroma_2x4_dc = x264_optimize_chroma_2x4_dc_avx512icl;
#if ARCH_X86_64
        /* zen4 prune: slower than the previous level on rack01 Zen 4 (checkasm --bench, same test program); kept assembled */
        /* decimate_score15/16/64 1.5-3.5x, quant_4x4 2.21x, quant_4x4_dc 1.13x, quant_4x4x4 1.056x;
         * trellis_cabac 4x4 1.48-1.52x, 4x4_psy 1.16-1.20x, dc 1.26-1.52x, chroma_422_dc 1.31-1.34x */
        pf->trellis_cabac_8x8 = x264_trellis_cabac_8x8_avx512icl;
        pf->trellis_cabac_8x8_psy = x264_trellis_cabac_8x8_psy_avx512icl;
        pf->quant_8x8 = x264_quant_8x8_avx512icl;
        pf->coeff_level_run4 = x264_coeff_level_run4_avx512icl;
        pf->coeff_level_run8 = x264_coeff_level_run8_avx512icl;
        pf->coeff_level_run[ DCT_LUMA_AC] = x264_coeff_level_run15_avx512icl;
        pf->coeff_level_run[DCT_LUMA_4x4] = x264_coeff_level_run16_avx512icl;
#endif
    }
#endif // HAVE_MMX
#else // !HIGH_BIT_DEPTH
#if HAVE_MMX
    INIT_TRELLIS( sse2 );
    if( cpu&X264_CPU_MMX )
    {
#if ARCH_X86
        pf->quant_4x4 = x264_quant_4x4_mmx;
        pf->quant_4x4x4 = x264_quant_4x4x4_mmx;
        pf->quant_8x8 = x264_quant_8x8_mmx;
        pf->dequant_4x4 = x264_dequant_4x4_mmx;
        pf->dequant_4x4_dc = x264_dequant_4x4dc_mmx2;
        pf->dequant_8x8 = x264_dequant_8x8_mmx;
        if( h->param.i_cqm_preset == X264_CQM_FLAT )
        {
            pf->dequant_4x4 = x264_dequant_4x4_flat16_mmx;
            pf->dequant_8x8 = x264_dequant_8x8_flat16_mmx;
        }
        pf->denoise_dct = x264_denoise_dct_mmx;
#endif
    }

    if( cpu&X264_CPU_MMX2 )
    {
        pf->quant_2x2_dc = x264_quant_2x2_dc_mmx2;
#if ARCH_X86
        pf->quant_4x4_dc = x264_quant_4x4_dc_mmx2;
        pf->decimate_score15 = x264_decimate_score15_mmx2;
        pf->decimate_score16 = x264_decimate_score16_mmx2;
        pf->decimate_score64 = x264_decimate_score64_mmx2;
        pf->coeff_last[  DCT_LUMA_AC] = x264_coeff_last15_mmx2;
        pf->coeff_last[ DCT_LUMA_4x4] = x264_coeff_last16_mmx2;
        pf->coeff_last[ DCT_LUMA_8x8] = x264_coeff_last64_mmx2;
        pf->coeff_level_run[  DCT_LUMA_AC] = x264_coeff_level_run15_mmx2;
        pf->coeff_level_run[ DCT_LUMA_4x4] = x264_coeff_level_run16_mmx2;
#endif
        pf->coeff_last4 = x264_coeff_last4_mmx2;
        pf->coeff_last8 = x264_coeff_last8_mmx2;
        pf->coeff_level_run4 = x264_coeff_level_run4_mmx2;
        pf->coeff_level_run8 = x264_coeff_level_run8_mmx2;
        if( cpu&X264_CPU_LZCNT )
        {
            pf->coeff_last4 = x264_coeff_last4_mmx2_lzcnt;
            pf->coeff_last8 = x264_coeff_last8_mmx2_lzcnt;
            pf->coeff_level_run4 = x264_coeff_level_run4_mmx2_lzcnt;
            pf->coeff_level_run8 = x264_coeff_level_run8_mmx2_lzcnt;
        }
    }

    if( cpu&X264_CPU_SSE2 )
    {
        pf->quant_4x4_dc = x264_quant_4x4_dc_sse2;
        pf->quant_4x4 = x264_quant_4x4_sse2;
        pf->quant_4x4x4 = x264_quant_4x4x4_sse2;
        pf->quant_8x8 = x264_quant_8x8_sse2;
        pf->dequant_4x4 = x264_dequant_4x4_sse2;
        pf->dequant_4x4_dc = x264_dequant_4x4dc_sse2;
        pf->dequant_8x8 = x264_dequant_8x8_sse2;
        if( h->param.i_cqm_preset == X264_CQM_FLAT )
        {
            pf->dequant_4x4 = x264_dequant_4x4_flat16_sse2;
            pf->dequant_8x8 = x264_dequant_8x8_flat16_sse2;
        }
        pf->idct_dequant_2x4_dc = x264_idct_dequant_2x4_dc_sse2;
        pf->idct_dequant_2x4_dconly = x264_idct_dequant_2x4_dconly_sse2;
        pf->optimize_chroma_2x2_dc = x264_optimize_chroma_2x2_dc_sse2;
        pf->denoise_dct = x264_denoise_dct_sse2;
        pf->decimate_score15 = x264_decimate_score15_sse2;
        pf->decimate_score16 = x264_decimate_score16_sse2;
        pf->decimate_score64 = x264_decimate_score64_sse2;
        pf->coeff_last[ DCT_LUMA_AC] = x264_coeff_last15_sse2;
        pf->coeff_last[DCT_LUMA_4x4] = x264_coeff_last16_sse2;
        pf->coeff_last[DCT_LUMA_8x8] = x264_coeff_last64_sse2;
        pf->coeff_level_run[ DCT_LUMA_AC] = x264_coeff_level_run15_sse2;
        pf->coeff_level_run[DCT_LUMA_4x4] = x264_coeff_level_run16_sse2;
        if( cpu&X264_CPU_LZCNT )
        {
            pf->coeff_last[ DCT_LUMA_AC] = x264_coeff_last15_sse2_lzcnt;
            pf->coeff_last[DCT_LUMA_4x4] = x264_coeff_last16_sse2_lzcnt;
            pf->coeff_last[DCT_LUMA_8x8] = x264_coeff_last64_sse2_lzcnt;
            pf->coeff_level_run[ DCT_LUMA_AC] = x264_coeff_level_run15_sse2_lzcnt;
            pf->coeff_level_run[DCT_LUMA_4x4] = x264_coeff_level_run16_sse2_lzcnt;
        }
    }

    if( cpu&X264_CPU_SSSE3 )
    {
        pf->quant_2x2_dc = x264_quant_2x2_dc_ssse3;
        pf->quant_4x4_dc = x264_quant_4x4_dc_ssse3;
        pf->quant_4x4 = x264_quant_4x4_ssse3;
        pf->quant_4x4x4 = x264_quant_4x4x4_ssse3;
        pf->quant_8x8 = x264_quant_8x8_ssse3;
        pf->optimize_chroma_2x2_dc = x264_optimize_chroma_2x2_dc_ssse3;
        pf->denoise_dct = x264_denoise_dct_ssse3;
        pf->decimate_score15 = x264_decimate_score15_ssse3;
        pf->decimate_score16 = x264_decimate_score16_ssse3;
        pf->decimate_score64 = x264_decimate_score64_ssse3;
        INIT_TRELLIS( ssse3 );
        pf->coeff_level_run4 = x264_coeff_level_run4_ssse3;
        pf->coeff_level_run8 = x264_coeff_level_run8_ssse3;
        pf->coeff_level_run[ DCT_LUMA_AC] = x264_coeff_level_run15_ssse3;
        pf->coeff_level_run[DCT_LUMA_4x4] = x264_coeff_level_run16_ssse3;
        if( cpu&X264_CPU_LZCNT )
        {
            pf->coeff_level_run4 = x264_coeff_level_run4_ssse3;
            pf->coeff_level_run8 = x264_coeff_level_run8_ssse3;
            pf->coeff_level_run[ DCT_LUMA_AC] = x264_coeff_level_run15_ssse3_lzcnt;
            pf->coeff_level_run[DCT_LUMA_4x4] = x264_coeff_level_run16_ssse3_lzcnt;
        }
    }

    if( cpu&X264_CPU_SSE4 )
    {
        pf->quant_4x4_dc = x264_quant_4x4_dc_sse4;
        pf->quant_4x4 = x264_quant_4x4_sse4;
        pf->quant_8x8 = x264_quant_8x8_sse4;
        pf->optimize_chroma_2x2_dc = x264_optimize_chroma_2x2_dc_sse4;
    }

    if( cpu&X264_CPU_AVX )
    {
        pf->dequant_4x4_dc = x264_dequant_4x4dc_avx;
        if( h->param.i_cqm_preset != X264_CQM_FLAT )
        {
            pf->dequant_4x4 = x264_dequant_4x4_avx;
            pf->dequant_8x8 = x264_dequant_8x8_avx;
        }
        pf->idct_dequant_2x4_dc = x264_idct_dequant_2x4_dc_avx;
        pf->idct_dequant_2x4_dconly = x264_idct_dequant_2x4_dconly_avx;
        pf->optimize_chroma_2x2_dc = x264_optimize_chroma_2x2_dc_avx;
        pf->denoise_dct = x264_denoise_dct_avx;
    }

    if( cpu&X264_CPU_XOP )
    {
        if( h->param.i_cqm_preset != X264_CQM_FLAT )
        {
            pf->dequant_4x4 = x264_dequant_4x4_xop;
            pf->dequant_8x8 = x264_dequant_8x8_xop;
        }
    }

    if( cpu&X264_CPU_AVX2 )
    {
        pf->quant_4x4 = x264_quant_4x4_avx2;
        INIT_TRELLIS( avx2 );
        INIT_TRELLIS_WRAP( avx2 );
        pf->quant_4x4_dc = x264_quant_4x4_dc_avx2;
        pf->quant_8x8 = x264_quant_8x8_avx2;
        pf->quant_4x4x4 = x264_quant_4x4x4_avx2;
        pf->dequant_4x4 = x264_dequant_4x4_avx2;
        pf->dequant_8x8 = x264_dequant_8x8_avx2;
        pf->dequant_4x4_dc = x264_dequant_4x4dc_avx2;
        if( h->param.i_cqm_preset == X264_CQM_FLAT )
        {
            pf->dequant_4x4 = x264_dequant_4x4_flat16_avx2;
            pf->dequant_8x8 = x264_dequant_8x8_flat16_avx2;
        }
        pf->decimate_score64 = x264_decimate_score64_avx2;
        pf->denoise_dct = x264_denoise_dct_avx2;
        if( cpu&X264_CPU_LZCNT )
        {
            pf->coeff_last[DCT_LUMA_8x8] = x264_coeff_last64_avx2_lzcnt;
            pf->coeff_level_run[ DCT_LUMA_AC] = x264_coeff_level_run15_avx2_lzcnt;
            pf->coeff_level_run[DCT_LUMA_4x4] = x264_coeff_level_run16_avx2_lzcnt;
        }
    }
    if( cpu&X264_CPU_AVX512 )
    {
        TRW512_INIT;
        if( h->param.i_cqm_preset == X264_CQM_FLAT )
            pf->dequant_8x8 = x264_dequant_8x8_flat16_avx512;
        else
        {
            pf->dequant_4x4 = x264_dequant_4x4_avx512;
            pf->dequant_8x8 = x264_dequant_8x8_avx512;
        }
        pf->decimate_score15 = x264_decimate_score15_avx512;
        pf->decimate_score16 = x264_decimate_score16_avx512;
        pf->decimate_score64 = x264_decimate_score64_avx512;
        pf->coeff_last8 = x264_coeff_last8_avx512;
        pf->coeff_last[ DCT_LUMA_AC] = x264_coeff_last15_avx512;
        pf->coeff_last[DCT_LUMA_4x4] = x264_coeff_last16_avx512;
        pf->coeff_last[DCT_LUMA_8x8] = x264_coeff_last64_avx512;
    }
    if( cpu&X264_CPU_AVX512ICL )
    {
        pf->denoise_dct = x264_denoise_dct_avx512icl;
        pf->quant_2x2_dc = x264_quant_2x2_dc_avx512icl;
        pf->optimize_chroma_2x4_dc = x264_optimize_chroma_2x4_dc_avx512icl;
#if ARCH_X86_64
        /* zen4 prune: slower than the previous level on rack01 Zen 4 (checkasm --bench, same test program); kept assembled */
        /* decimate_score15/16/64 1.5-4.1x, quant_8x8 1.08x, quant_4x4x4 1.25x;
         * trellis_cabac 4x4 1.48-1.52x, 4x4_psy 1.16-1.20x, dc 1.26-1.52x, chroma_422_dc 1.31-1.34x */
        pf->trellis_cabac_8x8 = x264_trellis_cabac_8x8_avx512icl;
        pf->trellis_cabac_8x8_psy = x264_trellis_cabac_8x8_psy_avx512icl;
        if( h->param.i_cqm_preset != X264_CQM_FLAT )
        {
            pf->dequant_8x8 = x264_dequant_8x8_avx512icl;
        }
        pf->coeff_level_run4 = x264_coeff_level_run4_avx512icl;
        pf->coeff_level_run8 = x264_coeff_level_run8_avx512icl;
        pf->coeff_level_run[ DCT_LUMA_AC] = x264_coeff_level_run15_avx512icl;
        pf->coeff_level_run[DCT_LUMA_4x4] = x264_coeff_level_run16_avx512icl;
#endif
    }
#endif // HAVE_MMX

#if HAVE_ALTIVEC
    if( cpu&X264_CPU_ALTIVEC ) {
        pf->quant_2x2_dc = x264_quant_2x2_dc_altivec;
        pf->quant_4x4_dc = x264_quant_4x4_dc_altivec;
        pf->quant_4x4 = x264_quant_4x4_altivec;
        pf->quant_8x8 = x264_quant_8x8_altivec;

        pf->dequant_4x4 = x264_dequant_4x4_altivec;
        pf->dequant_8x8 = x264_dequant_8x8_altivec;
    }
#endif

#if HAVE_ARMV6
    if( cpu&X264_CPU_ARMV6 )
        pf->coeff_last4 = x264_coeff_last4_arm;

    if( cpu&X264_CPU_NEON )
    {
        pf->quant_2x2_dc   = x264_quant_2x2_dc_neon;
        pf->quant_4x4      = x264_quant_4x4_neon;
        pf->quant_4x4_dc   = x264_quant_4x4_dc_neon;
        pf->quant_4x4x4    = x264_quant_4x4x4_neon;
        pf->quant_8x8      = x264_quant_8x8_neon;
        pf->dequant_4x4    = x264_dequant_4x4_neon;
        pf->dequant_4x4_dc = x264_dequant_4x4_dc_neon;
        pf->dequant_8x8    = x264_dequant_8x8_neon;
        pf->coeff_last[ DCT_LUMA_AC] = x264_coeff_last15_neon;
        pf->coeff_last[DCT_LUMA_4x4] = x264_coeff_last16_neon;
        pf->coeff_last[DCT_LUMA_8x8] = x264_coeff_last64_neon;
    }
#endif
#endif // HIGH_BIT_DEPTH
    pf->coeff_last[DCT_LUMA_DC]     = pf->coeff_last[DCT_CHROMAU_DC]  = pf->coeff_last[DCT_CHROMAV_DC] =
    pf->coeff_last[DCT_CHROMAU_4x4] = pf->coeff_last[DCT_CHROMAV_4x4] = pf->coeff_last[DCT_LUMA_4x4];
    pf->coeff_last[DCT_CHROMA_AC]   = pf->coeff_last[DCT_CHROMAU_AC]  =
    pf->coeff_last[DCT_CHROMAV_AC]  = pf->coeff_last[DCT_LUMA_AC];
    pf->coeff_last[DCT_CHROMAU_8x8] = pf->coeff_last[DCT_CHROMAV_8x8] = pf->coeff_last[DCT_LUMA_8x8];

    pf->coeff_level_run[DCT_LUMA_DC]     = pf->coeff_level_run[DCT_CHROMAU_DC]  = pf->coeff_level_run[DCT_CHROMAV_DC] =
    pf->coeff_level_run[DCT_CHROMAU_4x4] = pf->coeff_level_run[DCT_CHROMAV_4x4] = pf->coeff_level_run[DCT_LUMA_4x4];
    pf->coeff_level_run[DCT_CHROMA_AC]   = pf->coeff_level_run[DCT_CHROMAU_AC]  =
    pf->coeff_level_run[DCT_CHROMAV_AC]  = pf->coeff_level_run[DCT_LUMA_AC];
}
