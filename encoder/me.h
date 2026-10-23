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
    /* lazy hpel (x264_me_hpel_ensure): the ref, NULL if its hpel is built, the
     * row of p_fref[0] in its planes, and rows [hpel_ok[0], hpel_ok[1]] known built */
    x264_frame_t *hpel_ref;
    int      hpel_y;
    int      hpel_ok[2];

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

/* lazy hpel of m's ref, for the mb's block at row yoff */
static ALWAYS_INLINE void x264_me_hpel_init( x264_t *h, x264_me_t *m, int list, int i_ref, int yoff )
{
    x264_frame_t *frame = h->fref[list][i_ref >> MB_INTERLACED]->orig;
    m->hpel_ref = frame->b_hpel_lazy ? frame : NULL;
    m->hpel_y = 16*(h->mb.i_mb_y >> MB_INTERLACED) + yoff;
    m->hpel_ok[0] = 1;
    m->hpel_ok[1] = 0;
}

#define x264_me_hpel_build x264_template(me_hpel_build)
void x264_me_hpel_build( x264_t *h, x264_me_t *m, int y0, int y1 );

/* lazy hpel: the hpel rows of m's ref that mc_luma/get_ref read for m's block
 * at qpel mvy, plus height rows (the block's, and any more candidates') */
static ALWAYS_INLINE void x264_me_hpel_ensure_rows( x264_t *h, x264_me_t *m, int mvy, int height )
{
    if( m->hpel_ref )
    {
        int y = m->hpel_y + (mvy >> 2);
        if( y < m->hpel_ok[0] || y + height > m->hpel_ok[1] )
            x264_me_hpel_build( h, m, y, y + height );
    }
}

/* the same for one block at a qpel mv; a fullpel mv reads no hpel */
static ALWAYS_INLINE void x264_me_hpel_ensure( x264_t *h, x264_me_t *m, int mvx, int mvy, int height )
{
    if( (mvx|mvy)&3 )
        x264_me_hpel_ensure_rows( h, m, mvy, height );
}

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
