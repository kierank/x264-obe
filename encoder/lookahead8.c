/*****************************************************************************
 * lookahead8.c: 8-bit lowres analysis for high bit depth encodes
 *****************************************************************************
 * Copyright (C) 2026 x264 project
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

/* Compiled into the 8-bit pass only (SRCS_8). Each context is an 8-bit x264_t
 * that only carries what the lowres analysis and x264_me_search need: the 8-bit
 * function tables, the lookahead mb state and the lookahead MV costs. */

#include "common/common.h"
#include "me.h"
#include "analyse.h"
#include "lookahead8.h"

#if BIT_DEPTH == 8

typedef struct
{
    x264_t h;
    int lambda;
    uint16_t *p_cost_mv;
    pixel *weight_buf;
} lowres8_t;

void *x264_lowres8_init( const x264_param_t *param, int mb_width, int mb_height, int stride, int lines )
{
    lowres8_t *c = x264_malloc( sizeof(lowres8_t) );
    if( !c )
        return NULL;
    memset( c, 0, sizeof(lowres8_t) );
    x264_t *h = &c->h;
    h->param = *param;
    h->mb.i_mb_width = mb_width;
    h->mb.i_mb_height = mb_height;

    x264_pixel_init( param->cpu, &h->pixf );
    x264_mc_init( param->cpu, &h->mc, param->b_cpu_independent );
    x264_predict_8x8c_init( param->cpu, h->predict_8x8c );
    x264_predict_8x8_init( param->cpu, h->predict_8x8, &h->predict_8x8_filter );

    /* mbcmp_init() as the lowres analysis uses it (never lossless here) */
    int satd = param->analyse.i_subpel_refine > 1;
    memcpy( h->pixf.mbcmp, satd ? h->pixf.satd : h->pixf.sad_aligned, sizeof(h->pixf.mbcmp) );
    memcpy( h->pixf.mbcmp_unaligned, satd ? h->pixf.satd : h->pixf.sad, sizeof(h->pixf.mbcmp_unaligned) );
    h->pixf.intra_mbcmp_x3_8x8c = satd ? h->pixf.intra_satd_x3_8x8c : h->pixf.intra_sad_x3_8x8c;
    if( satd )
        memcpy( h->pixf.mbcmp_avg2, h->pixf.satd_avg2, sizeof(h->pixf.mbcmp_avg2) );
    else
        memset( h->pixf.mbcmp_avg2, 0, sizeof(h->pixf.mbcmp_avg2) );
    if( satd && param->analyse.i_subpel_refine >= 3 )
    {
        memcpy( h->pixf.mbcmp_pre, h->pixf.satd_pre, sizeof(h->pixf.mbcmp_pre) );
        memcpy( h->pixf.mbcmp_avg2_pre, h->pixf.satd_avg2_pre, sizeof(h->pixf.mbcmp_avg2_pre) );
    }
    else
    {
        memset( h->pixf.mbcmp_pre, 0, sizeof(h->pixf.mbcmp_pre) );
        memset( h->pixf.mbcmp_avg2_pre, 0, sizeof(h->pixf.mbcmp_avg2_pre) );
    }
    satd &= param->analyse.i_me_method == X264_ME_TESA;
    memcpy( h->pixf.fpelcmp, satd ? h->pixf.satd : h->pixf.sad, sizeof(h->pixf.fpelcmp) );
    memcpy( h->pixf.fpelcmp_x3, satd ? h->pixf.satd_x3 : h->pixf.sad_x3, sizeof(h->pixf.fpelcmp_x3) );
    memcpy( h->pixf.fpelcmp_x4, satd ? h->pixf.satd_x4 : h->pixf.sad_x4, sizeof(h->pixf.fpelcmp_x4) );
    memcpy( h->pixf.fpelcmp_avg2, satd ? h->pixf.satd_avg2 : h->pixf.sad_avg2, sizeof(h->pixf.fpelcmp_avg2) );

    /* x264_lowres_context_init() */
    if( param->analyse.i_subpel_refine > 1 )
    {
        h->mb.i_me_method = X264_MIN( X264_ME_HEX, param->analyse.i_me_method );
        h->mb.i_subpel_refine = 4;
    }
    else
    {
        h->mb.i_me_method = X264_ME_DIA;
        h->mb.i_subpel_refine = 2;
    }
    h->mb.b_chroma_me = 0;

    float *logs = x264_analyse_prepare_costs( h );
    if( !logs )
        goto fail;
    int ret = x264_analyse_init_costs( h, logs, X264_LOOKAHEAD_QP );
    x264_free( logs );
    if( ret )
        goto fail;
    c->lambda = x264_lambda_tab[X264_LOOKAHEAD_QP];
    c->p_cost_mv = h->cost_mv[X264_LOOKAHEAD_QP];

    /* weight_scale_plane writes up to 15 pixels past the plane width */
    c->weight_buf = x264_malloc( stride * (lines + 2*PADV) + 64 );
    if( !c->weight_buf )
        goto fail;
    return c;
fail:
    x264_lowres8_free( c );
    return NULL;
}

void x264_lowres8_free( void *ctx )
{
    lowres8_t *c = ctx;
    if( !c )
        return;
    x264_analyse_free_costs( &c->h );
    x264_free( c->weight_buf );
    x264_free( c );
}

void x264_lowres8_weight_plane( void *ctx, void *fenc_, void *ref_, const void *weight )
{
    lowres8_t *c = ctx;
    x264_t *h = &c->h;
    x264_frame_t *fenc = fenc_;
    x264_frame_t *ref = ref_;
    x264_weight_t w;
    memcpy( &w, weight, sizeof(w) );
    h->mc.weight_cache( h, &w );
    int width = ref->i_width_lowres + PADH*2;
    int height = ref->i_lines_lowres + PADV*2;
    x264_weight_scale_plane( h, c->weight_buf, ref->i_stride_lowres, ref->buffer_lowres8, ref->i_stride_lowres,
                             width, height, &w );
    fenc->weighted8 = c->weight_buf + PADH + ref->i_stride_lowres * PADV;
}

/* As in slicetype.c */
#define NUM_INTS 4
#define COST_EST 0
#define COST_EST_AQ 1
#define INTRA_MBS 2
#define ROW_SATD (NUM_INTS + (h->mb.i_mb_y - h->i_threadslice_start))

/* slicetype_mb_cost() at 8-bit. All costs, stored and accumulated, are at 8-bit
 * scale like those of the high bit depth slicetype_mb_cost(). */
static void lowres8_mb_cost( lowres8_t *c, x264_frame_t **frames, int p0, int p1, int b,
                             int dist_scale_factor, int do_search[2], const x264_weight_t *w,
                             int *output_inter, int *output_intra )
{
    x264_t *h = &c->h;
    x264_frame_t *fref0 = frames[p0];
    x264_frame_t *fref1 = frames[p1];
    x264_frame_t *fenc  = frames[b];
    const int b_bidir = (b < p1);
    const int i_mb_x = h->mb.i_mb_x;
    const int i_mb_y = h->mb.i_mb_y;
    const int i_mb_stride = h->mb.i_mb_width;
    const int i_mb_xy = i_mb_x + i_mb_y * i_mb_stride;
    const int i_stride = fenc->i_stride_lowres;
    const int i_pel_offset = 8 * (i_mb_x + i_mb_y * i_stride);
    const int i_bipred_weight = h->param.analyse.b_weighted_bipred ? 64 - (dist_scale_factor>>2) : 32;
    int16_t (*fenc_mvs[2])[2] = { &fenc->lowres_mvs[0][b-p0-1][i_mb_xy], &fenc->lowres_mvs[1][p1-b-1][i_mb_xy] };
    int (*fenc_costs[2]) = { &fenc->lowres_mv_costs[0][b-p0-1][i_mb_xy], &fenc->lowres_mv_costs[1][p1-b-1][i_mb_xy] };
    int b_frame_score_mb = (i_mb_x > 0 && i_mb_x < h->mb.i_mb_width - 1 &&
                            i_mb_y > 0 && i_mb_y < h->mb.i_mb_height - 1) ||
                            h->mb.i_mb_width <= 2 || h->mb.i_mb_height <= 2;

    ALIGNED_ARRAY_16( pixel, pix1,[9*FDEC_STRIDE] );
    pixel *pix2 = pix1+8;
    x264_me_t m[2];
    int i_bcost = COST_MAX;
    int list_used = 0;
    /* A small, arbitrary bias to avoid VBV problems caused by zero-residual lookahead blocks. */
    int lowres_penalty = 4;

    h->mb.pic.p_fenc[0] = h->mb.pic.fenc_buf;
    h->mc.copy[PIXEL_8x8]( h->mb.pic.p_fenc[0], FENC_STRIDE, &fenc->lowres8[0][i_pel_offset], i_stride, 8 );
    h->mb.pic.i_fenc_pre = 0;
    int16_t *fenc_pre = x264_me_fenc_pre( h, PIXEL_8x8, h->mb.pic.p_fenc[0] );
/* mbcmp of the lowres fenc against pix */
#define LOWRES_MBCMP( pix, stride ) \
    (fenc_pre ? h->pixf.mbcmp_pre[PIXEL_8x8]( fenc_pre, pix, stride ) \
              : h->pixf.mbcmp[PIXEL_8x8]( h->mb.pic.p_fenc[0], FENC_STRIDE, pix, stride ))

    if( p0 == p1 )
        goto lowres_intra_mb;

    int mv_range = 2 * h->param.analyse.i_mv_range;
    // no need for h->mb.mv_min[]
    h->mb.mv_min_spel[0] = X264_MAX( 4*(-8*h->mb.i_mb_x - 12), -mv_range );
    h->mb.mv_max_spel[0] = X264_MIN( 4*(8*(h->mb.i_mb_width - h->mb.i_mb_x - 1) + 12), mv_range-1 );
    h->mb.mv_limit_fpel[0][0] = h->mb.mv_min_spel[0] >> 2;
    h->mb.mv_limit_fpel[1][0] = h->mb.mv_max_spel[0] >> 2;
    if( h->mb.i_mb_x >= h->mb.i_mb_width - 2 )
    {
        h->mb.mv_min_spel[1] = X264_MAX( 4*(-8*h->mb.i_mb_y - 12), -mv_range );
        h->mb.mv_max_spel[1] = X264_MIN( 4*(8*( h->mb.i_mb_height - h->mb.i_mb_y - 1) + 12), mv_range-1 );
        h->mb.mv_limit_fpel[0][1] = h->mb.mv_min_spel[1] >> 2;
        h->mb.mv_limit_fpel[1][1] = h->mb.mv_max_spel[1] >> 2;
    }

#define LOAD_HPELS_LUMA(dst, src) \
    { \
        (dst)[0] = &(src)[0][i_pel_offset]; \
        (dst)[1] = &(src)[1][i_pel_offset]; \
        (dst)[2] = &(src)[2][i_pel_offset]; \
        (dst)[3] = &(src)[3][i_pel_offset]; \
    }
#define LOAD_WPELS_LUMA(dst,src) \
    (dst) = &(src)[i_pel_offset];

#define CLIP_MV( mv ) \
    { \
        mv[0] = x264_clip3( mv[0], h->mb.mv_min_spel[0], h->mb.mv_max_spel[0] ); \
        mv[1] = x264_clip3( mv[1], h->mb.mv_min_spel[1], h->mb.mv_max_spel[1] ); \
    }
#define TRY_BIDIR( mv0, mv1, penalty ) \
    { \
        int i_cost; \
        if( h->param.analyse.i_subpel_refine <= 1 ) \
        { \
            int hpel_idx1 = (((mv0)[0]&2)>>1) + ((mv0)[1]&2); \
            int hpel_idx2 = (((mv1)[0]&2)>>1) + ((mv1)[1]&2); \
            pixel *src1 = m[0].p_fref[hpel_idx1] + ((mv0)[0]>>2) + ((mv0)[1]>>2) * m[0].i_stride[0]; \
            pixel *src2 = m[1].p_fref[hpel_idx2] + ((mv1)[0]>>2) + ((mv1)[1]>>2) * m[1].i_stride[0]; \
            h->mc.avg[PIXEL_8x8]( pix1, 16, src1, m[0].i_stride[0], src2, m[1].i_stride[0], i_bipred_weight ); \
        } \
        else \
        { \
            intptr_t stride1 = 16, stride2 = 16; \
            pixel *src1, *src2; \
            src1 = h->mc.get_ref( pix1, &stride1, m[0].p_fref, m[0].i_stride[0], \
                                  (mv0)[0], (mv0)[1], 8, 8, w ); \
            src2 = h->mc.get_ref( pix2, &stride2, m[1].p_fref, m[1].i_stride[0], \
                                  (mv1)[0], (mv1)[1], 8, 8, w ); \
            h->mc.avg[PIXEL_8x8]( pix1, 16, src1, stride1, src2, stride2, i_bipred_weight ); \
        } \
        i_cost = penalty * c->lambda + LOWRES_MBCMP( pix1, 16 ); \
        COPY2_IF_LT( i_bcost, i_cost, list_used, 3 ); \
    }

    m[0].i_pixel = PIXEL_8x8;
    m[0].p_cost_mv = c->p_cost_mv;
    m[0].i_stride[0] = i_stride;
    m[0].p_fenc[0] = h->mb.pic.p_fenc[0];
    m[0].weight = w;
    m[0].i_ref = 0;
    LOAD_HPELS_LUMA( m[0].p_fref, fref0->lowres8 );
    m[0].p_fref_w = m[0].p_fref[0];
    if( w[0].weightfn )
        LOAD_WPELS_LUMA( m[0].p_fref_w, fenc->weighted8 );

    if( b_bidir )
    {
        ALIGNED_ARRAY_8( int16_t, dmv,[2],[2] );

        m[1].i_pixel = PIXEL_8x8;
        m[1].p_cost_mv = c->p_cost_mv;
        m[1].i_stride[0] = i_stride;
        m[1].p_fenc[0] = h->mb.pic.p_fenc[0];
        m[1].i_ref = 0;
        m[1].weight = x264_weight_none;
        LOAD_HPELS_LUMA( m[1].p_fref, fref1->lowres8 );
        m[1].p_fref_w = m[1].p_fref[0];

        if( fref1->lowres_mvs[0][p1-p0-1][0][0] != 0x7FFF )
        {
            int16_t *mvr = fref1->lowres_mvs[0][p1-p0-1][i_mb_xy];
            dmv[0][0] = ( mvr[0] * dist_scale_factor + 128 ) >> 8;
            dmv[0][1] = ( mvr[1] * dist_scale_factor + 128 ) >> 8;
            dmv[1][0] = dmv[0][0] - mvr[0];
            dmv[1][1] = dmv[0][1] - mvr[1];
            CLIP_MV( dmv[0] );
            CLIP_MV( dmv[1] );
            if( h->param.analyse.i_subpel_refine <= 1 )
                M64( dmv ) &= ~0x0001000100010001ULL; /* mv & ~1 */
        }
        else
            M64( dmv ) = 0;

        TRY_BIDIR( dmv[0], dmv[1], 0 );
        if( M64( dmv ) )
        {
            int i_cost;
            h->mc.avg[PIXEL_8x8]( pix1, 16, m[0].p_fref[0], m[0].i_stride[0], m[1].p_fref[0], m[1].i_stride[0], i_bipred_weight );
            i_cost = LOWRES_MBCMP( pix1, 16 );
            COPY2_IF_LT( i_bcost, i_cost, list_used, 3 );
        }
    }

    for( int l = 0; l < 1 + b_bidir; l++ )
    {
        if( do_search[l] )
        {
            int i_mvc = 0;
            int16_t (*fenc_mv)[2] = fenc_mvs[l];
            ALIGNED_4( int16_t mvc[4][2] );

            /* Reverse-order MV prediction. */
            M32( mvc[0] ) = 0;
            M32( mvc[2] ) = 0;
#define MVC(mv) { CP32( mvc[i_mvc], mv ); i_mvc++; }
            if( i_mb_x < h->mb.i_mb_width - 1 )
                MVC( fenc_mv[1] );
            if( i_mb_y < h->i_threadslice_end - 1 )
            {
                MVC( fenc_mv[i_mb_stride] );
                if( i_mb_x > 0 )
                    MVC( fenc_mv[i_mb_stride-1] );
                if( i_mb_x < h->mb.i_mb_width - 1 )
                    MVC( fenc_mv[i_mb_stride+1] );
            }
#undef MVC
            if( i_mvc <= 1 )
                CP32( m[l].mvp, mvc[0] );
            else
                x264_median_mv( m[l].mvp, mvc[0], mvc[1], mvc[2] );

            /* Fast skip for cases of near-zero residual.  Shortcut: don't bother except in the mv0 case,
             * since anything else is likely to have enough residual to not trigger the skip.
             * The threshold is the high bit depth one at 8-bit scale. */
            if( !M32( m[l].mvp ) )
            {
                m[l].cost = LOWRES_MBCMP( m[l].p_fref[0], m[l].i_stride[0] );
                if( m[l].cost < (64 >> LOWRES8_COST_SHIFT) )
                {
                    M32( m[l].mv ) = 0;
                    goto skip_motionest;
                }
            }

            x264_me_search( h, &m[l], mvc, i_mvc );
            m[l].cost -= c->p_cost_mv[0]; // remove mvcost from skip mbs
            if( M32( m[l].mv ) )
                m[l].cost += 5 * c->lambda;

skip_motionest:
            CP32( fenc_mvs[l], m[l].mv );
            *fenc_costs[l] = m[l].cost;
        }
        else
        {
            CP32( m[l].mv, fenc_mvs[l] );
            m[l].cost = *fenc_costs[l];
        }
        COPY2_IF_LT( i_bcost, m[l].cost, list_used, l+1 );
    }

    if( b_bidir && ( M32( m[0].mv ) || M32( m[1].mv ) ) )
        TRY_BIDIR( m[0].mv, m[1].mv, 5 );

lowres_intra_mb:
    if( !fenc->b_intra_calculated )
    {
        ALIGNED_ARRAY_16( pixel, edge,[36] );
        pixel *pix = &pix1[8+FDEC_STRIDE];
        pixel *src = &fenc->lowres8[0][i_pel_offset];
        const int intra_penalty = 5 * c->lambda;
        int satds[3];
        int pixoff = 4 / sizeof(pixel);

        /* Avoid store forwarding stalls by writing larger chunks */
        memcpy( pix-FDEC_STRIDE, src-i_stride, 16 * sizeof(pixel) );
        for( int i = -1; i < 8; i++ )
            M32( &pix[i*FDEC_STRIDE-pixoff] ) = M32( &src[i*i_stride-pixoff] );

        h->pixf.intra_mbcmp_x3_8x8c( h->mb.pic.p_fenc[0], pix, satds );
        int i_icost = X264_MIN3( satds[0], satds[1], satds[2] );

        if( h->param.analyse.i_subpel_refine > 1 )
        {
            h->predict_8x8c[I_PRED_CHROMA_P]( pix );
            int satd = fenc_pre ? h->pixf.mbcmp_pre[PIXEL_8x8]( fenc_pre, pix, FDEC_STRIDE )
                                : h->pixf.mbcmp[PIXEL_8x8]( pix, FDEC_STRIDE, h->mb.pic.p_fenc[0], FENC_STRIDE );
            i_icost = X264_MIN( i_icost, satd );
            h->predict_8x8_filter( pix, edge, ALL_NEIGHBORS, ALL_NEIGHBORS );
            for( int i = 3; i < 9; i++ )
            {
                h->predict_8x8[i]( pix, edge );
                satd = fenc_pre ? h->pixf.mbcmp_pre[PIXEL_8x8]( fenc_pre, pix, FDEC_STRIDE )
                                : h->pixf.mbcmp[PIXEL_8x8]( pix, FDEC_STRIDE, h->mb.pic.p_fenc[0], FENC_STRIDE );
                i_icost = X264_MIN( i_icost, satd );
            }
        }

        i_icost += intra_penalty + lowres_penalty;
        fenc->i_intra_cost[i_mb_xy] = i_icost;
        int i_icost_aq = i_icost;
        if( h->param.rc.i_aq_mode )
            i_icost_aq = (i_icost_aq * fenc->i_inv_qscale_factor[i_mb_xy] + 128) >> 8;
        output_intra[ROW_SATD] += i_icost_aq;
        if( b_frame_score_mb )
        {
            output_intra[COST_EST] += i_icost;
            output_intra[COST_EST_AQ] += i_icost_aq;
        }
    }
    i_bcost += lowres_penalty;

    /* forbid intra-mbs in B-frames, because it's rare and not worth checking */
    /* FIXME: Should we still forbid them now that we cache intra scores? */
    if( !b_bidir )
    {
        int i_icost = fenc->i_intra_cost[i_mb_xy];
        int b_intra = i_icost < i_bcost;
        if( b_intra )
        {
            i_bcost = i_icost;
            list_used = 0;
        }
        if( b_frame_score_mb )
            output_inter[INTRA_MBS] += b_intra;
    }

    /* In an I-frame, we've already added the results above in the intra section. */
    if( p0 != p1 )
    {
        int i_bcost_aq = i_bcost;
        if( h->param.rc.i_aq_mode )
            i_bcost_aq = (i_bcost_aq * fenc->i_inv_qscale_factor[i_mb_xy] + 128) >> 8;
        output_inter[ROW_SATD] += i_bcost_aq;
        if( b_frame_score_mb )
        {
            /* Don't use AQ-weighted costs for slicetype decision, only for ratecontrol. */
            output_inter[COST_EST] += i_bcost;
            output_inter[COST_EST_AQ] += i_bcost_aq;
        }
    }

    fenc->lowres_costs[b-p0][p1-b][i_mb_xy] = X264_MIN( i_bcost, LOWRES_COST_MASK ) + (list_used << LOWRES_COST_SHIFT);
}
#undef TRY_BIDIR
#undef LOWRES_MBCMP

void x264_lowres8_slice_cost( void *ctx, void **frames, int p0, int p1, int b,
                              int dist_scale_factor, int do_search[2], const void *weights,
                              int *output_inter, int *output_intra,
                              int slice_start, int slice_end )
{
    lowres8_t *c = ctx;
    x264_t *h = &c->h;
    x264_weight_t w[3];
    memcpy( w, weights, sizeof(w) );
    w[1].weightfn = w[2].weightfn = NULL;
    if( w[0].weightfn )
        h->mc.weight_cache( h, &w[0] );
    h->i_threadslice_start = slice_start;
    h->i_threadslice_end = slice_end;

    /* As slicetype_slice_cost() */
    int do_edges = h->param.rc.b_mb_tree || h->param.rc.i_vbv_buffer_size || h->mb.i_mb_width <= 2 || h->mb.i_mb_height <= 2;
    int start_y = X264_MIN( h->i_threadslice_end - 1, h->mb.i_mb_height - 2 + do_edges );
    int end_y = X264_MAX( h->i_threadslice_start, 1 - do_edges );
    int start_x = h->mb.i_mb_width - 2 + do_edges;
    int end_x = 1 - do_edges;

    for( h->mb.i_mb_y = start_y; h->mb.i_mb_y >= end_y; h->mb.i_mb_y-- )
        for( h->mb.i_mb_x = start_x; h->mb.i_mb_x >= end_x; h->mb.i_mb_x-- )
            lowres8_mb_cost( c, (x264_frame_t**)frames, p0, p1, b, dist_scale_factor,
                             do_search, w, output_inter, output_intra );
}

#endif
