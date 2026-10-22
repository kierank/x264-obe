/*****************************************************************************
 * cabac_wf.c: cabac binarisation for --wavefront
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

/* encoder/cabac.c with each bin appended to h->cabac.p_tape as ctxIdx and bin.
 * No context state is read: the MB rows are binarised out of raster order and
 * the coder (encoder/wavefront.c) applies the states in raster order. */

#include "common/common.h"
#include "macroblock.h"

static ALWAYS_INLINE void x264_cabac_wf_decision( x264_cabac_t *cb, long i_ctx, long b )
{
    *cb->p_tape++ = i_ctx | (b << 10);
}

/* n <= X264_WF_BYPASS_MAX bypass bins x, msb first: on the last entry if they fit */
static ALWAYS_INLINE void x264_cabac_wf_bins( x264_cabac_t *cb, uint32_t x, int n )
{
    uint32_t e = cb->p_tape[-1];
    int m = (e >> 12) & 15;
    if( m + n <= X264_WF_BYPASS_MAX )
        cb->p_tape[-1] = (e & 0xfff) | ((m+n) << 12) | ((e >> 16 << n | x) << 16);
    else
        *cb->p_tape++ = (2 << 10) | (n << 12) | (x << 16);
}

/* b is negated, as in x264_cabac_encode_bypass */
static ALWAYS_INLINE void x264_cabac_wf_bypass( x264_cabac_t *cb, int b )
{
    x264_cabac_wf_bins( cb, b & 1, 1 );
}

static const int bypass_lut[16] =
{
    -1,      0x2,     0x14,     0x68,     0x1d0,     0x7a0,     0x1f40,     0x7e80,
    0x1fd00, 0x7fa00, 0x1ff400, 0x7fe800, 0x1ffd000, 0x7ffa000, 0x1fff4000, 0x7ffe8000
};

static void x264_cabac_wf_ue_bypass( x264_cabac_t *cb, int exp_bits, int val )
{
    uint32_t v = val + (1<<exp_bits);
    int k = 31 - x264_clz( v );
    uint32_t x = (bypass_lut[k-exp_bits]<<exp_bits) + v;
    k = 2*k+1-exp_bits;
    int i = (k-1)%X264_WF_BYPASS_MAX+1;
    do {
        k -= i;
        x264_cabac_wf_bins( cb, (x>>k) & ((1<<i)-1), i );
        i = X264_WF_BYPASS_MAX;
    } while( k > 0 );
}

#define CABAC_TAPE 2
#undef  x264_cabac_encode_decision
#undef  x264_cabac_encode_decision_noup
#undef  x264_cabac_encode_bypass
#undef  x264_cabac_encode_ue_bypass
#undef  x264_cabac_encode_terminal
#define x264_cabac_encode_decision      x264_cabac_wf_decision
#define x264_cabac_encode_decision_noup x264_cabac_wf_decision
#define x264_cabac_encode_bypass        x264_cabac_wf_bypass
#define x264_cabac_encode_ue_bypass     x264_cabac_wf_ue_bypass
#define x264_cabac_encode_terminal(cb)  x264_cabac_wf_special( cb, X264_WF_TERM, 0 )
#undef  x264_macroblock_write_cabac
#define x264_macroblock_write_cabac     x264_macroblock_write_cabac_wf
#undef  x264_cabac_mb_skip
#define x264_cabac_mb_skip              x264_cabac_mb_skip_wf
#include "cabac.c"
