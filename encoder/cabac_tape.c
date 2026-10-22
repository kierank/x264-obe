/*****************************************************************************
 * cabac_tape.c: cabac bitstream writing through a bin tape
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

/* encoder/cabac.c with each bin appended to h->cabac.p_tape instead of coded.
 * The contexts are updated here, so the next MB's rd and trellis see them as
 * after coding; the tape holds state^bin, which is all the coder needs, and is
 * coded by x264_cabac_tape_drain under the next MB's analysis. */

#include "common/common.h"
#include "macroblock.h"
#include "ratecontrol.h"

static ALWAYS_INLINE void x264_cabac_tape_decision( x264_cabac_t *cb, long i_ctx, long b )
{
    int i_state = cb->state[i_ctx];
    *cb->p_tape++ = i_state ^ b;
    cb->state[i_ctx] = x264_cabac_transition[i_state][b];
}

/* n <= X264_CABAC_TAPE_BYPASS_MAX bypass bins x, msb first: on the last entry if they fit */
static ALWAYS_INLINE void x264_cabac_tape_bins( x264_cabac_t *cb, uint32_t x, int n )
{
    uint32_t e = cb->p_tape[-1];
    int m = (e >> 8) & 31;
    if( m + n <= X264_CABAC_TAPE_BYPASS_MAX )
        cb->p_tape[-1] = (e & 0xff) | ((m+n) << 8) | ((e >> 16 << n | x) << 16);
    else
        *cb->p_tape++ = 0x80 | (n << 8) | (x << 16);
}

/* b is negated, as in x264_cabac_encode_bypass */
static ALWAYS_INLINE void x264_cabac_tape_bypass( x264_cabac_t *cb, int b )
{
    x264_cabac_tape_bins( cb, b & 1, 1 );
}

static const int bypass_lut[16] =
{
    -1,      0x2,     0x14,     0x68,     0x1d0,     0x7a0,     0x1f40,     0x7e80,
    0x1fd00, 0x7fa00, 0x1ff400, 0x7fe800, 0x1ffd000, 0x7ffa000, 0x1fff4000, 0x7ffe8000
};

static void x264_cabac_tape_ue_bypass( x264_cabac_t *cb, int exp_bits, int val )
{
    uint32_t v = val + (1<<exp_bits);
    int k = 31 - x264_clz( v );
    uint32_t x = (bypass_lut[k-exp_bits]<<exp_bits) + v;
    k = 2*k+1-exp_bits;
    int i = ((k-1)&15)+1;
    do {
        k -= i;
        x264_cabac_tape_bins( cb, (x>>k) & ((1<<i)-1), i );
        i = 16;
    } while( k > 0 );
}

#define CABAC_TAPE 1
#undef  x264_cabac_encode_decision
#undef  x264_cabac_encode_decision_noup
#undef  x264_cabac_encode_bypass
#undef  x264_cabac_encode_ue_bypass
#undef  x264_cabac_encode_terminal
#define x264_cabac_encode_decision      x264_cabac_tape_decision
#define x264_cabac_encode_decision_noup x264_cabac_tape_decision
#define x264_cabac_encode_bypass        x264_cabac_tape_bypass
#define x264_cabac_encode_ue_bypass     x264_cabac_tape_ue_bypass
/* the terminal bin 0 is a decision on state 0, whose range_lps is 2 */
#define x264_cabac_encode_terminal(cb)  (*(cb)->p_tape++ = 0)
#undef  x264_macroblock_write_cabac
#define x264_macroblock_write_cabac     x264_macroblock_write_cabac_tape
#undef  x264_cabac_mb_skip
#define x264_cabac_mb_skip              x264_cabac_mb_skip_tape
#include "cabac.c"

/* entries coded per x264_cabac_tape_step */
#define X264_CABAC_TAPE_CHUNK 24

/* codes up to end, taking x264_cabac_pos at the marks it passes */
static void x264_cabac_tape_drain( x264_t *h, uint32_t *end )
{
    while( h->tape.i_mark < 2 && h->tape.mark[h->tape.i_mark] <= end )
    {
        uint32_t *mark = h->tape.mark[h->tape.i_mark];
        h->bsf.cabac_tape_drain( &h->cabac, h->tape.rd, mark );
        h->tape.rd = mark;
        h->tape.pos[++h->tape.i_mark] = x264_cabac_pos( &h->cabac );
    }
    h->bsf.cabac_tape_drain( &h->cabac, h->tape.rd, end );
    h->tape.rd = end;
}

void x264_cabac_tape_start( x264_t *h, int b_terminal )
{
    h->tape.pos[0] = x264_cabac_pos( &h->cabac );
    h->tape.rd = h->cabac.p_tape = h->tape.buf;
    h->tape.mark[0] = NULL;
    h->tape.i_mark = 2;
    if( b_terminal )
        x264_cabac_encode_terminal( &h->cabac );
}

void x264_cabac_tape_chunk( x264_t *h )
{
    x264_cabac_tape_drain( h, X264_MIN( h->tape.rd + X264_CABAC_TAPE_CHUNK, h->cabac.p_tape ) );
}

/* Codes the rest of the tape and returns the MB's bits; b_rc: hands them to
 * ratecontrol, whose x264_ratecontrol_mb for the MB was given 0. */
int x264_cabac_tape_finish( x264_t *h, int b_rc )
{
    x264_cabac_tape_drain( h, h->cabac.p_tape );
    int pos = x264_cabac_pos( &h->cabac );
    if( h->tape.mark[0] )
    {
        h->stat.frame.i_mv_bits += h->tape.pos[2] - h->tape.pos[1];
        h->stat.frame.i_tex_bits += pos - h->tape.pos[2];
    }
    int bits = pos - h->tape.pos[0];
    if( b_rc )
        x264_ratecontrol_mb_bits( h, h->tape.i_mb_y, bits );
    h->tape.b_pending = 0;
    return bits;
}
