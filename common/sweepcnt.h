/*****************************************************************************
 * sweepcnt.h: test-only encoder event counters (bit depth independent)
 *****************************************************************************
 * Copyright (C) 2026 Open Broadcast Systems Ltd
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
 *****************************************************************************/

#ifndef X264_SWEEPCNT_H
#define X264_SWEEPCNT_H

#include <stdint.h>

/* One set per x264_t (so per thread), summed and printed to stderr by
 * x264_encoder_close. Plain increments only; they never change the output. */

/* A1: x264_me_search_ref predictor lists, [la][i_pixel] */
enum
{
    SW_A1_CALLS,
    SW_A1_MVC,          /* sum of i_mvc */
    SW_A1_VALID,        /* left after x264_predictor_(round)clip */
    SW_A1_EQ_PMV,       /* valid entries equal to pmv after clipping */
    SW_A1_EQ_ZERO,      /* valid entries equal to zero after clipping */
    SW_A1_DUP,          /* valid entries equal to an earlier valid entry */
    SW_A1_RED_CALLS,    /* calls with any of the three */
    SW_A1_WEIGHTED,     /* calls with m->weight[0].weightfn */
    SW_A1_N
};

/* A3: fullpel multi-candidate SAD steps, [la][step][i_pixel] */
enum
{
    SW_STEP_DIA,
    SW_STEP_HEX,        /* the two initial hexagon x3 calls */
    SW_STEP_HEXHALF,
    SW_STEP_SQ_CROSS,
    SW_STEP_SQ_DIAG,
    SW_STEP_X4,         /* COST_MV_X4: umh, cross */
    SW_STEP_X3_ABS,     /* COST_MV_X3_ABS: esa */
    SW_STEP_N
};
enum
{
    SW_A3_CALLS,
    SW_A3_LANES,
    SW_A3_LANES_DEAD,   /* key over the first bh/2 rows already >= best */
    SW_A3_ALL_DEAD,     /* every lane dead */
    SW_A3_NO_IMPROVE,   /* best unchanged by the step */
    SW_A3_N
};

/* A6: P-skip probe */
enum
{
    SW_A6_PROBES,
    SW_A6_SKIP,         /* probe returned 1 */
    SW_A6_LUMA_EQ,      /* luma prediction == fenc */
    SW_A6_LUMA_EQ_SKIP,
    SW_A6_ALL_EQ,       /* every plane's prediction == fenc */
    SW_A6_N
};

/* A10: final coded luma blocks, [inter][0: 8x8, 1: 4x4][0: coded, 1: dc only] */

/* weightp: x264_weights_analyse, [b_lookahead] */
#define SW_WP_HIST 7    /* us < 100, 250, 500, 1000, 2000, 4000, >= 4000 */
enum
{
    SW_WP_CALLS,
    SW_WP_LUMA,         /* luma weight chosen */
    SW_WP_CHROMA,       /* a chroma weight chosen */
    SW_WP_US,
    SW_WP_HIST0,
    SW_WP_N = SW_WP_HIST0 + SW_WP_HIST
};
/* weightp: final MBs of P slices */
enum
{
    SW_WPMB_P,
    SW_WPMB_INTER,
    SW_WPMB_WREF_LUMA,  /* a partition refs a frame with a luma weight */
    SW_WPMB_WREF_ANY,
    SW_WPMB_SUBPEL_W0,  /* weighted luma get_ref in subpel cmp, main */
    SW_WPMB_SUBPEL_W1,  /* the same, lookahead */
    SW_WPMB_N
};

/* C3/A7 */
enum
{
    SW_C3_CL_INTERLACED,
    SW_C3_CL_PROGRESSIVE,
    SW_C3_FIELD_MBS,
    SW_C3_F2F,          /* MAP_F2F remaps of a neighbour ref/mv */
    SW_C3_STRENGTH_MBAFF,
    SW_C3_N
};

typedef struct
{
    uint64_t a1[2][7][SW_A1_N];
    uint64_t a3[2][SW_STEP_N][7][SW_A3_N];
    uint64_t a6[SW_A6_N];
    uint64_t a10[2][2][2];
    uint64_t wp[2][SW_WP_N];
    uint64_t wpmb[SW_WPMB_N];
    uint64_t c3[SW_C3_N];
} x264_sweep_cnt_t;

typedef struct
{
    x264_sweep_cnt_t c;
    uint64_t wp_us_max[2];
    int la; /* 1 while this context runs the lowres analysis */
} x264_sweep_t;

static inline void x264_sweep_add( x264_sweep_t *dst, const x264_sweep_t *src )
{
    uint64_t *d = (uint64_t*)&dst->c;
    const uint64_t *s = (const uint64_t*)&src->c;
    for( size_t i = 0; i < sizeof(x264_sweep_cnt_t) / sizeof(uint64_t); i++ )
        d[i] += s[i];
    for( int i = 0; i < 2; i++ )
        if( src->wp_us_max[i] > dst->wp_us_max[i] )
            dst->wp_us_max[i] = src->wp_us_max[i];
}

#endif
