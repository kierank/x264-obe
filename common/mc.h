/*****************************************************************************
 * mc.h: motion compensation
 *****************************************************************************
 * Copyright (C) 2004-2014 x264 project
 *
 * Authors: Loren Merritt <lorenm@u.washington.edu>
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

#ifndef X264_MC_H
#define X264_MC_H

/* Defined for functions shared between mc.c and x86/mc-c.c that have no
 * extern prototype in this fork (unlike upstream 2017+); without this they'd
 * collide as duplicate external symbols across the two BIT_DEPTH object sets. */
#define x264_plane_copy_c x264_template(plane_copy_c)
#define x264_plane_copy_interleave_c x264_template(plane_copy_interleave_c)
#define x264_plane_copy_deinterleave_v210_c x264_template(plane_copy_deinterleave_v210_c)

struct x264_weight_t;
typedef void (* weight_fn_t)( pixel *, intptr_t, pixel *,intptr_t, const struct x264_weight_t *, int );
typedef struct x264_weight_t
{
    /* aligning the first member is a gcc hack to force the struct to be
     * 16 byte aligned, as well as force sizeof(struct) to be a multiple of 16 */
    ALIGNED_16( int16_t cachea[8] );
    int16_t cacheb[8];
    int32_t i_denom;
    int32_t i_scale;
    int32_t i_offset;
    weight_fn_t *weightfn;
} ALIGNED_16( x264_weight_t );

#define x264_weight_none x264_template(weight_none)
extern const x264_weight_t x264_weight_none[3];

#define SET_WEIGHT( w, b, s, d, o )\
{\
    (w).i_scale = (s);\
    (w).i_denom = (d);\
    (w).i_offset = (o);\
    if( b )\
        h->mc.weight_cache( h, &w );\
    else\
        w.weightfn = NULL;\
}

/* Do the MC
 * XXX: Only width = 4, 8 or 16 are valid
 * width == 4 -> height == 4 or 8
 * width == 8 -> height == 4 or 8 or 16
 * width == 16-> height == 8 or 16
 * */

typedef struct
{
    void (*mc_luma)( pixel *dst, intptr_t i_dst, pixel **src, intptr_t i_src,
                     int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight );

    /* may round up the dimensions if they're not a power of 2 */
    pixel* (*get_ref)( pixel *dst, intptr_t *i_dst, pixel **src, intptr_t i_src,
                       int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight );

    /* mc_chroma may write up to 2 bytes of garbage to the right of dst,
     * so it must be run from left to right. */
    void (*mc_chroma)( pixel *dstu, pixel *dstv, intptr_t i_dst, pixel *src, intptr_t i_src,
                       int mvx, int mvy, int i_width, int i_height );

    void (*avg[12])( pixel *dst,  intptr_t dst_stride, pixel *src1, intptr_t src1_stride,
                     pixel *src2, intptr_t src2_stride, int i_weight );

    /* only 16x16, 8x8, and 4x4 defined */
    void (*copy[7])( pixel *dst, intptr_t dst_stride, pixel *src, intptr_t src_stride, int i_height );
    void (*copy_16x16_unaligned)( pixel *dst, intptr_t dst_stride, pixel *src, intptr_t src_stride, int i_height );

    void (*store_interleave_chroma)( pixel *dst, intptr_t i_dst, pixel *srcu, pixel *srcv, int height );
    void (*load_deinterleave_chroma_fenc)( pixel *dst, pixel *src, intptr_t i_src, int height );
    void (*load_deinterleave_chroma_fdec)( pixel *dst, pixel *src, intptr_t i_src, int height );

    void (*plane_copy)( pixel *dst, intptr_t i_dst, pixel *src, intptr_t i_src, int w, int h );
    void (*plane_copy_interleave)( pixel *dst,  intptr_t i_dst, pixel *srcu, intptr_t i_srcu,
                                   pixel *srcv, intptr_t i_srcv, int w, int h );
    /* may write up to 15 pixels off the end of each plane */
    void (*plane_copy_deinterleave)( pixel *dstu, intptr_t i_dstu, pixel *dstv, intptr_t i_dstv,
                                     pixel *src,  intptr_t i_src, int w, int h );
    void (*plane_copy_deinterleave_rgb)( pixel *dsta, intptr_t i_dsta, pixel *dstb, intptr_t i_dstb,
                                         pixel *dstc, intptr_t i_dstc, pixel *src,  intptr_t i_src, int pw, int w, int h );
    void (*plane_copy_deinterleave_v210)( pixel *dsty, intptr_t i_dsty,
                                          pixel *dstc, intptr_t i_dstc,
                                          uint32_t *src, intptr_t i_src, int w, int h );
    void (*hpel_filter)( pixel *dsth, pixel *dstv, pixel *dstc, pixel *src,
                         intptr_t i_stride, int i_width, int i_height, int16_t *buf );
    /* hpel_filter that also copies src to dst (same stride): every output
     * column, and anything else it writes is src at the same offset. NULL if
     * there is no asm. */
    void (*hpel_filter_copy)( pixel *dsth, pixel *dstv, pixel *dstc, pixel *src,
                              intptr_t i_stride, int i_width, int i_height, int16_t *buf, pixel *dst );
    /* analyse.i_me_8bit 2, high bit depth: hpel_filter that also writes the
     * plane_split8 of the pixels it writes; msb and lsb are those of dsth's
     * first pixel (a multiple of 4 pixels from a 32 byte boundary in src),
     * dstv's and dstc's plane8 and 2*plane8 bytes after them. NULL if there
     * is no asm. */
    void (*hpel_filter8)( pixel *dsth, pixel *dstv, pixel *dstc, pixel *src,
                          intptr_t i_stride, int i_width, int i_height, int16_t *buf,
                          uint8_t *msb, uint8_t *lsb, intptr_t plane8 );

    /* prefetch the next few macroblocks of fenc or fdec */
    void (*prefetch_fenc)    ( pixel *pix_y, intptr_t stride_y, pixel *pix_uv, intptr_t stride_uv, int mb_x );
    void (*prefetch_fenc_420)( pixel *pix_y, intptr_t stride_y, pixel *pix_uv, intptr_t stride_uv, int mb_x );
    void (*prefetch_fenc_422)( pixel *pix_y, intptr_t stride_y, pixel *pix_uv, intptr_t stride_uv, int mb_x );
    /* prefetch the next few macroblocks of a hpel reference frame */
    void (*prefetch_ref)( pixel *pix, intptr_t stride, int parity );

    void *(*memcpy_aligned)( void *dst, const void *src, size_t n );
    void (*memzero_aligned)( void *dst, size_t n );

    /* successive elimination prefilter */
    void (*integral_init4h)( uint16_t *sum, pixel *pix, intptr_t stride );
    void (*integral_init8h)( uint16_t *sum, pixel *pix, intptr_t stride );
    void (*integral_init4v)( uint16_t *sum8, uint16_t *sum4, intptr_t stride );
    void (*integral_init8v)( uint16_t *sum8, intptr_t stride );

    void (*frame_init_lowres_core)( pixel *src0, pixel *dst0, pixel *dsth, pixel *dstv, pixel *dstc,
                                    intptr_t src_stride, intptr_t dst_stride, int width, int height );
    /* rc.b_lookahead_8bit: dst[i] = min( (src[i] + 2) >> 2, 255 ), high bit depth only */
    void (*lowres8_convert)( uint8_t *dst, pixel *src, intptr_t n );
    /* analyse.i_me_8bit, high bit depth only: msb[x] = src[x] >> 2, and lsb[x>>2]
     * the src[x] & 3 of pixels x&~3 to x|3, pixel x in bits 2*(x&3). h rows of w
     * pixels (a multiple of 16), rows i_stride pixels (src), bytes (msb) and
     * i_stride/4 bytes (lsb) apart. */
    void (*plane_split8)( uint8_t *msb, uint8_t *lsb, pixel *src, intptr_t i_stride, int w, int h );
    weight_fn_t *weight;
    weight_fn_t *offsetadd;
    weight_fn_t *offsetsub;
    void (*weight_cache)( x264_t *, x264_weight_t * );

    void (*mbtree_propagate_cost)( int16_t *dst, uint16_t *propagate_in, uint16_t *intra_costs,
                                   uint16_t *inter_costs, uint16_t *inv_qscales, float *fps_factor, int len );

    void (*mbtree_propagate_list)( x264_t *h, uint16_t *ref_costs, int16_t (*mvs)[2],
                                   int16_t *propagate_amount, uint16_t *lowres_costs,
                                   int bipred_weight, int mb_y, int len, int list );
} x264_mc_functions_t;

#define x264_mc_init x264_template(mc_init)
void x264_mc_init( int cpu, x264_mc_functions_t *pf, int cpu_independent );

/* the two hpel planes' sources whose pavg is get_ref's unweighted luma prediction
 * at mv (the same one twice where it needs no average) */
static ALWAYS_INLINE void x264_mc_hpel_pair( pixel *dst[2], pixel **src, intptr_t i_stride, int mvx, int mvy )
{
    int qpel_idx = ((mvy&3)<<2) + (mvx&3);
    intptr_t offset = (mvy>>2)*i_stride + (mvx>>2);
    dst[0] = src[x264_hpel_ref0[qpel_idx]] + offset + ((mvy&3) == 3) * i_stride;
    dst[1] = qpel_idx & 5 ? src[x264_hpel_ref1[qpel_idx]] + offset + ((mvx&3) == 3) : dst[0];
}

#endif
