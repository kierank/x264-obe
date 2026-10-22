/*****************************************************************************
 * trdcnt.h: test-only transform_rd pre-screen counters
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

#ifndef X264_TRDCNT_H
#define X264_TRDCNT_H

#include <stdint.h>

/* One set per x264_t, summed and printed to stderr by x264_encoder_close.
 * Plain increments only; they never change the output. [s] is 0 P, 1 B. */

#define TRD_NZ    17    /* coded luma 4x4 blocks of the 4x4 RD, 0..16 */
#define TRD_CLASS 3     /* 16x16 (and direct), 16x8/8x16, 8x8 */
#define TRD_QP    4     /* 8-bit scale qp < 20, < 26, < 32, >= 32 */
#define TRD_GAP   6     /* |sa8d - satd| / min < 5, 10, 20, 40, 80, >= 80 % */
#define TRD_ARMS  3

/* outcome of a transform_rd that ran its 8x8 RD */
enum
{
    TRD_CALLS,
    TRD_WIN8,           /* rd8 < rd4 */
    TRD_TIE,            /* rd8 == rd4: base takes 8x8 */
    TRD_WIN4,           /* rd8 > rd4 */
    TRD_RDBEST,         /* sum of min( rd4, rd8 ) */
    TRD_LOSS4,          /* sum of rd4 - rd8 where rd8 < rd4: cost of always keeping 4x4 */
    TRD_LOSS8,          /* sum of rd8 - rd4 where rd8 > rd4: cost of always taking 8x8 */
    TRD_N
};

/* per arm, of the runs it applies to */
enum
{
    TRD_ARM_SKIP,       /* would skip the 8x8 RD */
    TRD_ARM_KEEP,       /* of which keep 4x4 */
    TRD_ARM_FLIP,       /* the skip takes the strictly worse size */
    TRD_ARM_TIEFLIP,    /* keeps 4x4 where base takes 8x8 at equal cost */
    TRD_ARM_LOSS,       /* sum of the RD cost the flips lose */
    TRD_ARM_N
};

typedef struct
{
    uint64_t rd_mb[2];          /* every x264_rd_cost_mb in P/B slices */
    uint64_t entry[2];          /* transform_rd called with 8x8dct on */
    uint64_t allowed[2];        /* of which the type allows 8x8 */
    uint64_t subpart[2];        /* P_8x8 with sub-8x8 partitions: different prediction */
    uint64_t miss[2];           /* no log entry for the picked candidate */
    uint64_t cur8[2];           /* current or logged size already 8x8 */
    uint64_t rdbest[2];         /* sum of min( rd4, rd8 ) of the eligible runs */
    uint64_t nz[2][TRD_CLASS][TRD_QP][TRD_NZ][TRD_N];
    uint64_t gap[2][2][TRD_GAP][TRD_N];     /* [s][sa8d < satd][margin] */
    uint64_t arm[TRD_ARMS][2][TRD_ARM_N];
} x264_trdcnt_t;

static inline void x264_trdcnt_add( x264_trdcnt_t *dst, const x264_trdcnt_t *src )
{
    uint64_t *d = (uint64_t*)dst;
    const uint64_t *s = (const uint64_t*)src;
    for( size_t i = 0; i < sizeof(x264_trdcnt_t) / sizeof(uint64_t); i++ )
        d[i] += s[i];
}

#endif
