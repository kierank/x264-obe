/*****************************************************************************
 * lowres.h: fused lowres analysis loops
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

#ifndef X264_ENCODER_LOWRES_H
#define X264_ENCODER_LOWRES_H

/* pixf.lowres_i_mbs: slicetype_mb_cost of an intra frame cost (p0 == p1 == b) over the
 * MBs of a slice, with satd mbcmp on fenc_pre and intra_mbcmp_lowres: the intra cost
 * when output_intra is set, then the lowres cost and INTRA_MBS. The asm takes fenc from
 * the plane and does the fenc_pre and intra stages itself; fenc_pre / intra are the C
 * reference's kernels only. 8-bit pixels; common/x86/lowres-a.asm follows this layout. */
struct x264_lowres_i
{
    void (*fenc_pre)( int16_t *fenc_pre, pixel *fenc );            /* satd_fenc_pre[1] */
    int (*intra)( void *fenc_pre, pixel *src, intptr_t i_stride ); /* intra_mbcmp_lowres */
    pixel *fenc;                /* lowres[0] of fenc */
    uint16_t *intra_cost;
    uint16_t *costs;            /* lowres_costs[0][0], the same array as intra_cost in x264_frame_t */
    uint16_t *inv_qscale;       /* NULL without aq */
    int *output_inter;
    int *output_intra;          /* NULL once b_intra_calculated */
    const uint8_t *corr_intra;  /* the 8-bit lookahead's correction (lookahead8.c), NULL for none */
    intptr_t stride;
    int penalty;                /* 5 * lambda + 4, also the correction's floor */
    int corr_intra_max;
    int mb_width;
    int mb_height;
    int slice_start;            /* the row of output_*[NUM_INTS] */
    int start_x, end_x, start_y, end_y; /* the MBs, as slicetype_slice_cost */
};

#if !HIGH_BIT_DEPTH
#define x264_lowres_i_mbs_c x264_template(lowres_i_mbs_c)
void x264_lowres_i_mbs_c( x264_lowres_i_t *c );

/* the struct for h's intra lowres analysis, the frame and slice fields excepted; 0 if
 * pixf.lowres_i_mbs can't do it (x264_me_fenc_pre NULL or no intra_mbcmp_lowres) */
static inline int x264_lowres_i_init( x264_t *h, x264_lowres_i_t *c, int lambda )
{
    x264_pixel_function_t *pf = &h->pixf;
    if( !pf->lowres_i_mbs || !pf->mbcmp_pre[0] || !pf->intra_mbcmp_lowres || !pf->satd_fenc_pre[1] )
        return 0;
    c->fenc_pre = pf->satd_fenc_pre[1];
    c->intra = pf->intra_mbcmp_lowres;
    c->penalty = 5 * lambda + 4;
    c->corr_intra = NULL;
    c->corr_intra_max = 0;
    c->mb_width = h->mb.i_mb_width;
    c->mb_height = h->mb.i_mb_height;
    return 1;
}

/* pixf.lowres_i_mbs, leaving h's mb position as the MB loop would */
static inline void x264_lowres_i_run( x264_t *h, x264_lowres_i_t *c )
{
    h->pixf.lowres_i_mbs( c );
    if( c->start_y < c->end_y )
    {
        h->mb.i_mb_y = c->start_y;
        return;
    }
    h->mb.i_mb_x = c->start_x < c->end_x ? c->start_x : c->end_x - 1;
    h->mb.i_mb_y = c->end_y - 1;
}
#endif

#endif
