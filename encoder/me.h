/*****************************************************************************
 * me.h: motion estimation
 *****************************************************************************
 * Copyright (C) 2003-2014 x264 project
 *
 * Authors: Loren Merritt <lorenm@u.washington.edu>
 *          Laurent Aimar <fenrir@via.ecp.fr>
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

#ifndef X264_ME_H
#define X264_ME_H

#define COST_MAX (1<<28)
#define COST_MAX64 (1ULL<<60)

typedef struct
{
    /* aligning the first member is a gcc hack to force the struct to be aligned,
     * as well as force sizeof(struct) to be a multiple of the alignment. */
    /* input */
    ALIGNED_64( int i_pixel );   /* PIXEL_WxH */
    uint16_t *p_cost_mv; /* lambda * nbits for each possible mv */
    int      i_ref_cost;
    int      i_ref;
    const x264_weight_t *weight;

    pixel *p_fref[12];
    pixel *p_fref_w;
    pixel *p_fenc[3];
    uint16_t *integral;
    int      i_stride[3];
    int      i_fld_uv_y; /* NV12: field row of p_fref[4], see x264_mb_fref_uv */

    ALIGNED_4( int16_t mvp[2] );

    /* output */
    int cost_mv;        /* lambda * nbits for the chosen mv */
    int cost;           /* satd + lambda * nbits */
    ALIGNED_4( int16_t mv[2] );
} ALIGNED_64( x264_me_t );

typedef struct
{
    int sad;
    int16_t mv[2];
} mvsad_t;

#define x264_me_search_ref x264_template(me_search_ref)
void x264_me_search_ref( x264_t *h, x264_me_t *m, int16_t (*mvc)[2], int i_mvc, int *p_fullpel_thresh );
#define x264_me_search( h, m, mvc, i_mvc )\
    x264_me_search_ref( h, m, mvc, i_mvc, NULL )

/* pixf.predictor_clip from this many mvc, in the subme >= 3 search; shorter lists rarely
 * hold a duplicate and take the inline x264_predictor_clip. The subme < 3 and fpel pred
 * searches keep the inline x264_predictor_roundclip: their lists are short (8x8
 * partitions, lowres), so the call costs more than the duplicates it drops. */
#define PREDICTOR_DEDUPE_MIN 5

#define x264_me_refine_qpel x264_template(me_refine_qpel)
void x264_me_refine_qpel( x264_t *h, x264_me_t *m );
#define x264_me_refine_qpel_refdupe x264_template(me_refine_qpel_refdupe)
void x264_me_refine_qpel_refdupe( x264_t *h, x264_me_t *m, int *p_halfpel_thresh );
#define x264_me_refine_qpel_rd x264_template(me_refine_qpel_rd)
void x264_me_refine_qpel_rd( x264_t *h, x264_me_t *m, int i_lambda2, int i4, int i_list );
#define x264_me_refine_bidir_rd x264_template(me_refine_bidir_rd)
void x264_me_refine_bidir_rd( x264_t *h, x264_me_t *m0, x264_me_t *m1, int i_weight, int i8, int i_lambda2 );
#define x264_me_refine_bidir_satd x264_template(me_refine_bidir_satd)
void x264_me_refine_bidir_satd( x264_t *h, x264_me_t *m0, x264_me_t *m1, int i_weight );
#define x264_rd_cost_part x264_template(rd_cost_part)
uint64_t x264_rd_cost_part( x264_t *h, int i_lambda2, int i8, int i_pixel );

extern uint16_t *x264_cost_mv_fpel[QP_MAX+1][4];

/* fenc_pre of the luma partition i_pixel at p_fenc (in h->mb.pic.p_fenc[0]) for
 * mbcmp_pre and mbcmp_avg2_pre, filled on first use in the mb; NULL without them */
static inline int16_t *x264_me_fenc_pre( x264_t *h, int i_pixel, pixel *p_fenc )
{
    if( i_pixel > PIXEL_8x8 || !h->pixf.mbcmp_pre[0] )
        return NULL;
    int off = p_fenc - h->mb.pic.p_fenc[0];
    if( i_pixel <= PIXEL_16x8 )
    {
        if( !(h->mb.pic.i_fenc_pre & 16) )
        {
            h->pixf.satd_fenc_pre[0]( h->mb.pic.fenc_pre, h->mb.pic.p_fenc[0] );
            h->mb.pic.i_fenc_pre |= 16;
        }
        return h->mb.pic.fenc_pre + off;
    }
    /* 8x8 b = 2*(x/8) + y/8, an 8x16 the two of its column */
    int b = ((off&8) >> 2) + (off >> 7);
    for( int i = b; i <= b + (i_pixel == PIXEL_8x16); i++ )
        if( !(h->mb.pic.i_fenc_pre & (1 << i)) )
        {
            h->pixf.satd_fenc_pre[1]( h->mb.pic.fenc_pre + 256 + 64*i,
                                      h->mb.pic.p_fenc[0] + 8*(i>>1) + 8*FENC_STRIDE*(i&1) );
            h->mb.pic.i_fenc_pre |= 1 << i;
        }
    return h->mb.pic.fenc_pre + 256 + 64*b;
}

/* fenc of mbcmp_bi and mbcmp_bi4 for the luma partition i_pixel at p_fenc, NULL without them */
static inline x264_bi_fenc_t *x264_me_bi_fenc( x264_t *h, int i_pixel, pixel *p_fenc )
{
    if( i_pixel > PIXEL_8x8 || !h->pixf.mbcmp_bi[0] )
        return NULL;
#if HIGH_BIT_DEPTH
    return p_fenc;
#else
    return x264_me_fenc_pre( h, i_pixel, p_fenc );
#endif
}

#if !HIGH_BIT_DEPTH
/* mbcmp_mcc's fenc for the chroma partition at p_fenc (in h->mb.pic.p_fenc[1]) of a
 * luma partition bw wide and chroma ch high, in mcc_fenc_pre, filled on first
 * use in the mb */
static inline int16_t *x264_me_mcc_fenc_pre( x264_t *h, pixel *p_fenc, int bw, int ch )
{
    if( !(h->mb.pic.i_fenc_pre & 32) )
    {
        h->pixf.satd_mcc_fenc_pre( h->mb.pic.mcc_fenc_pre, h->mb.pic.p_fenc[1], 16 >> CHROMA_V_SHIFT );
        h->mb.pic.i_fenc_pre |= 32;
    }
    int off = p_fenc - h->mb.pic.p_fenc[1];
    int x = off % FENC_STRIDE, y = off / FENC_STRIDE;
    return h->mb.pic.mcc_fenc_pre + (bw == 16 ? 16*y : ch == 4 ? 128 + 8*x + 16*y : 256 + 32*x + 8*y);
}
#endif

/* pixf.lowres_p_mbs: slicetype_mb_cost of a P frame (b == p1, p0 < b) over the MBs
 * of a slice, with the lowres x264_me_search of HEX and subme 4, satd mbcmp on
 * fenc_pre and sad fpelcmp. 8-bit pixels only; the asm offsets follow this layout. */
struct x264_lowres_p
{
    void (*fenc_pre)( int16_t *fenc_pre, pixel *fenc );   /* satd_fenc_pre[1] */
    x264_pixel_cmp_pre_t satd;                            /* mbcmp_pre[PIXEL_8x8] */
    x264_pixel_cmp_avg2_pre_t satd_avg2;                  /* mbcmp_avg2_pre[PIXEL_8x8] */
    x264_pixel_cmp_t sad;                                 /* fpelcmp[PIXEL_8x8] */
    x264_pixel_cmp_avg2_t sad_avg2;                       /* fpelcmp_avg2[PIXEL_8x8] */
    x264_pixel_fpel_search_t hex_search;                  /* fpelcmp_hex_search[PIXEL_8x8] or x264_lowres_hex_search_c */
    x264_pixel_cmp_hpel_min_t hpel_min;                   /* fpelcmp_hpel_min[PIXEL_8x8] */
    int (*intra)( void *fenc_pre, pixel *src, intptr_t i_stride ); /* intra_mbcmp_lowres */
    pixel *(*get_ref)( pixel *dst, intptr_t *i_dst, pixel **src, intptr_t i_src,
                       int mvx, int mvy, int bw, int bh, const x264_weight_t *weight );
    pixel *fenc;                /* lowres[0] of fenc */
    pixel *ref[4];              /* lowres[] of the ref */
    pixel *ref_w;               /* the fullpel search plane: ref[0] or the weighted one */
    const x264_weight_t *weight;
    const uint16_t *cost_mv;
    int16_t (*mvs)[2];          /* lowres_mvs[0][b-p0-1] */
    int *mv_costs;              /* lowres_mv_costs[0][b-p0-1] */
    uint16_t *costs;            /* lowres_costs[b-p0][0] */
    uint16_t *intra_cost;
    uint16_t *inv_qscale;       /* NULL without aq */
    int *output_inter;
    int *output_intra;          /* NULL once b_intra_calculated */
    intptr_t stride;
    int lambda;
    int skip_thresh;            /* the mv 0 skip: satd < skip_thresh */
    int mv_range;               /* 2 * i_mv_range */
    int me_range;
    int mb_width;
    int mb_height;
    int slice_start;            /* the row of output_*[NUM_INTS] */
    int slice_end;
    int start_x, end_x, start_y, end_y; /* the MBs, as slicetype_slice_cost */
    int do_search;
    int weighted;               /* weight[0].weightfn */
};

/* counters: test/x264-slicetype-asm-cnt, printed at encoder close (api.c) */
extern int64_t x264_sltasm_cnt[16];
#define x264_lowres_p_mbs_c x264_template(lowres_p_mbs_c)
void x264_lowres_p_mbs_c( x264_lowres_p_t *c );
#define x264_lowres_hex_search_c x264_template(lowres_hex_search_c)
uint64_t x264_lowres_hex_search_c( pixel *fenc, pixel *ref, intptr_t i_stride, const uint16_t *cost_mvx,
                                   const uint16_t *cost_mvy, uint32_t bmv, int bcost, int iters, uint64_t range );
/* the struct for h's lowres analysis, the frame and slice fields excepted; 0 if
 * pixf.lowres_p_mbs can't do it */
static inline int x264_lowres_p_init( x264_t *h, x264_lowres_p_t *c )
{
    x264_pixel_function_t *pf = &h->pixf;
    if( !pf->lowres_p_mbs || h->mb.i_me_method != X264_ME_HEX || h->mb.i_subpel_refine != 4 || h->mb.b_chroma_me ||
        !pf->satd_fenc_pre[1] || !pf->mbcmp_pre[PIXEL_8x8] || !pf->mbcmp_avg2_pre[PIXEL_8x8] ||
        !pf->fpelcmp_hpel_min[PIXEL_8x8] || !pf->fpelcmp_avg2[PIXEL_8x8] || !pf->intra_mbcmp_lowres ||
        pf->mbcmp_unaligned[0] == pf->fpelcmp[0] )
        return 0;
    c->fenc_pre = pf->satd_fenc_pre[1];
    c->satd = pf->mbcmp_pre[PIXEL_8x8];
    c->satd_avg2 = pf->mbcmp_avg2_pre[PIXEL_8x8];
    c->sad = pf->fpelcmp[PIXEL_8x8];
    c->sad_avg2 = pf->fpelcmp_avg2[PIXEL_8x8];
    c->hex_search = pf->fpelcmp_hex_search[PIXEL_8x8] ? pf->fpelcmp_hex_search[PIXEL_8x8] : x264_lowres_hex_search_c;
    c->hpel_min = pf->fpelcmp_hpel_min[PIXEL_8x8];
    c->intra = pf->intra_mbcmp_lowres;
    c->get_ref = h->mc.get_ref;
    c->mv_range = 2 * h->param.analyse.i_mv_range;
    c->me_range = h->param.analyse.i_me_range;
    c->mb_width = h->mb.i_mb_width;
    c->mb_height = h->mb.i_mb_height;
    return 1;
}

/* pixf.lowres_p_mbs, leaving h's mb position and mv limits as the MB loop would */
static inline void x264_lowres_p_run( x264_t *h, x264_lowres_p_t *c )
{
    x264_lowres_p_mbs_c( c );
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

#define COPY1_IF_LT(x,y)\
if((y)<(x))\
    (x)=(y);

#define COPY2_IF_LT(x,y,a,b)\
if((y)<(x))\
{\
    (x)=(y);\
    (a)=(b);\
}

#define COPY3_IF_LT(x,y,a,b,c,d)\
if((y)<(x))\
{\
    (x)=(y);\
    (a)=(b);\
    (c)=(d);\
}

#define COPY4_IF_LT(x,y,a,b,c,d,e,f)\
if((y)<(x))\
{\
    (x)=(y);\
    (a)=(b);\
    (c)=(d);\
    (e)=(f);\
}

#define COPY2_IF_GT(x,y,a,b)\
if((y)>(x))\
{\
    (x)=(y);\
    (a)=(b);\
}

#endif
