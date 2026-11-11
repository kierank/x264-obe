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

#include "me.h"

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

/* pixf.lowres_b_mbs: slicetype_mb_cost of a B frame (p0 < b < p1) over the MBs of a
 * slice once both lists' mvs and mv costs are stored (do_search 0, see
 * x264_lowres_b_search): the bidir costs at the scaled mvs of fref1, mv 0 and the list
 * mvs, the list costs, the intra cost when output_intra is set, the lowres cost. Satd
 * mbcmp on fenc_pre and the unweighted refs of a B frame; bi, bi4 are satd_bi[PIXEL_8x8]
 * and satd_bi4[PIXEL_8x8] (the asm calls them on its fenc_pre), fenc_pre and intra the C
 * reference's kernels only. 8-bit pixels; common/x86/lowres-a.asm follows this layout. */
struct x264_lowres_b
{
    void (*fenc_pre)( int16_t *fenc_pre, pixel *fenc );            /* satd_fenc_pre[1] */
    int (*intra)( void *fenc_pre, pixel *src, intptr_t i_stride ); /* intra_mbcmp_lowres */
    x264_pixel_satd_bi_t bi;
    x264_pixel_satd_bi4_t bi4;
    pixel *fenc;                /* lowres[0] of fenc */
    pixel *ref0[4];             /* lowres[] of frames[p0] */
    pixel *ref1[4];             /* lowres[] of frames[p1] */
    int16_t (*mvs[2])[2];       /* lowres_mvs[0][b-p0-1], lowres_mvs[1][p1-b-1] */
    int *mv_costs[2];
    int16_t (*mvr)[2];          /* frames[p1]->lowres_mvs[0][p1-p0-1], NULL where not searched */
    uint16_t *costs;            /* lowres_costs[b-p0][p1-b] */
    uint16_t *intra_cost;
    uint16_t *inv_qscale;       /* NULL without aq */
    int *output_inter;
    int *output_intra;          /* NULL once b_intra_calculated */
    const uint8_t *corr_intra;  /* the 8-bit lookahead's corrections, NULL for none */
    const uint8_t *corr_inter;
    intptr_t stride;
    int lambda;
    int dist_scale_factor;
    int bipred_weight;
    int mv_range;               /* 2 * i_mv_range */
    int mb_width;
    int mb_height;
    int slice_start;
    int start_x, end_x, start_y, end_y;
    int corr_intra_max;
    int corr_inter_max;
};

#if !HIGH_BIT_DEPTH
#define x264_lowres_i_mbs_c x264_template(lowres_i_mbs_c)
void x264_lowres_i_mbs_c( x264_lowres_i_t *c );

#define x264_lowres_b_mbs_c x264_template(lowres_b_mbs_c)
void x264_lowres_b_mbs_c( x264_lowres_b_t *c );

/* the struct for h's B lowres analysis, the frame and slice fields excepted; 0 if
 * pixf.lowres_b_mbs can't do it. bi: satd_bi / satd_bi4 equal mc.avg of get_ref's
 * unweighted predictions then satd (checkasm), so this serves the paths with and
 * without mbcmp_bi alike */
static inline int x264_lowres_b_init( x264_t *h, x264_lowres_b_t *c, int lambda )
{
    x264_pixel_function_t *pf = &h->pixf;
    if( !pf->lowres_b_mbs || !pf->mbcmp_pre[0] || !pf->intra_mbcmp_lowres || !pf->satd_fenc_pre[1] ||
        !pf->satd_bi[PIXEL_8x8] || !pf->satd_bi4[PIXEL_8x8] || h->param.analyse.i_subpel_refine <= 1 )
        return 0;
    c->fenc_pre = pf->satd_fenc_pre[1];
    c->intra = pf->intra_mbcmp_lowres;
    c->bi = pf->satd_bi[PIXEL_8x8];
    c->bi4 = pf->satd_bi4[PIXEL_8x8];
    c->lambda = lambda;
    c->mv_range = 2 * h->param.analyse.i_mv_range;
    c->bipred_weight = 32;
    c->corr_intra = c->corr_inter = NULL;
    c->corr_intra_max = c->corr_inter_max = 0;
    c->mb_width = h->mb.i_mb_width;
    c->mb_height = h->mb.i_mb_height;
    return 1;
}

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

/* slice rows the B path takes (its search outputs are on the stack) */
#define LOWRES_B_ROWS 256

/* list l's search of a B frame's slicetype_mb_cost by pixf.lowres_p_mbs: x264_me_search
 * of an unweighted ref, as for a P frame. The mvs and mv costs it stores are those
 * slicetype_mb_cost's search stores, which depend on the list's own mvs only; its lowres
 * costs go to costs, which lowres_b_mbs then rewrites, and its outputs to out. p is from
 * x264_lowres_p_init with fenc, cost_mv, intra_cost, stride, lambda, skip_thresh and the
 * slice fields set */
static inline void x264_lowres_b_search( x264_t *h, x264_lowres_p_t *p, pixel **ref, int16_t (*mvs)[2],
                                         int *mv_costs, uint16_t *costs, int *out )
{
    for( int i = 0; i < 4; i++ )
        p->ref[i] = ref[i];
    p->ref_w = ref[0];
    p->weighted = 0;
    p->weight = x264_weight_none;
    p->mvs = mvs;
    p->mv_costs = mv_costs;
    p->costs = costs;
    p->inv_qscale = NULL;
    p->output_inter = out;
    p->output_intra = NULL;
    p->do_search = 1;
    p->corr_intra = p->corr_inter = NULL;
    h->pixf.lowres_p_mbs( p );
}

/* pixf.lowres_b_mbs, leaving h's mb position and mv limits as the MB loop would */
static inline void x264_lowres_b_run( x264_t *h, x264_lowres_b_t *c )
{
    h->pixf.lowres_b_mbs( c );
    if( c->start_y < c->end_y || c->start_x < c->end_x )
        return;
    int mb_x = c->end_x, mb_y = c->end_y;
    h->mb.mv_min_spel[0] = X264_MAX( 4*(-8*mb_x - 12), -c->mv_range );
    h->mb.mv_max_spel[0] = X264_MIN( 4*(8*(c->mb_width - mb_x - 1) + 12), c->mv_range-1 );
    h->mb.mv_min_spel[1] = X264_MAX( 4*(-8*mb_y - 12), -c->mv_range );
    h->mb.mv_max_spel[1] = X264_MIN( 4*(8*(c->mb_height - mb_y - 1) + 12), c->mv_range-1 );
    for( int i = 0; i < 2; i++ )
    {
        h->mb.mv_limit_fpel[0][i] = h->mb.mv_min_spel[i] >> 2;
        h->mb.mv_limit_fpel[1][i] = h->mb.mv_max_spel[i] >> 2;
    }
    h->mb.i_mb_x = mb_x - 1;
    h->mb.i_mb_y = mb_y - 1;
}
#endif

#endif
