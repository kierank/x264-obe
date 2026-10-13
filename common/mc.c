/*****************************************************************************
 * mc.c: motion compensation
 *****************************************************************************
 * Copyright (C) 2003-2014 x264 project
 *
 * Authors: Laurent Aimar <fenrir@via.ecp.fr>
 *          Loren Merritt <lorenm@u.washington.edu>
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

#include "common.h"

#if HAVE_MMX
#include "x86/mc.h"
#endif
#if ARCH_PPC
#include "ppc/mc.h"
#endif
#if ARCH_ARM
#include "arm/mc.h"
#endif


static inline void pixel_avg( pixel *dst,  intptr_t i_dst_stride,
                              pixel *src1, intptr_t i_src1_stride,
                              pixel *src2, intptr_t i_src2_stride, int i_width, int i_height )
{
    for( int y = 0; y < i_height; y++ )
    {
        for( int x = 0; x < i_width; x++ )
            dst[x] = ( src1[x] + src2[x] + 1 ) >> 1;
        dst  += i_dst_stride;
        src1 += i_src1_stride;
        src2 += i_src2_stride;
    }
}

static inline void pixel_avg_wxh( pixel *dst,  intptr_t i_dst,
                                  pixel *src1, intptr_t i_src1,
                                  pixel *src2, intptr_t i_src2, int width, int height )
{
    for( int y = 0; y < height; y++ )
    {
        for( int x = 0; x < width; x++ )
            dst[x] = ( src1[x] + src2[x] + 1 ) >> 1;
        src1 += i_src1;
        src2 += i_src2;
        dst += i_dst;
    }
}

/* Implicit weighted bipred only:
 * assumes log2_denom = 5, offset = 0, weight1 + weight2 = 64 */
static inline void pixel_avg_weight_wxh( pixel *dst,  intptr_t i_dst,
                                         pixel *src1, intptr_t i_src1,
                                         pixel *src2, intptr_t i_src2, int width, int height, int i_weight1 )
{
    int i_weight2 = 64 - i_weight1;
    for( int y = 0; y<height; y++, dst += i_dst, src1 += i_src1, src2 += i_src2 )
        for( int x = 0; x<width; x++ )
            dst[x] = x264_clip_pixel( (src1[x]*i_weight1 + src2[x]*i_weight2 + (1<<5)) >> 6 );
}
#undef op_scale2

#define PIXEL_AVG_C( name, width, height ) \
static void name( pixel *pix1, intptr_t i_stride_pix1, \
                  pixel *pix2, intptr_t i_stride_pix2, \
                  pixel *pix3, intptr_t i_stride_pix3, int weight ) \
{ \
    if( weight == 32 ) \
        pixel_avg_wxh( pix1, i_stride_pix1, pix2, i_stride_pix2, pix3, i_stride_pix3, width, height ); \
    else \
        pixel_avg_weight_wxh( pix1, i_stride_pix1, pix2, i_stride_pix2, pix3, i_stride_pix3, width, height, weight ); \
}
PIXEL_AVG_C( pixel_avg_16x16, 16, 16 )
PIXEL_AVG_C( pixel_avg_16x8,  16, 8 )
PIXEL_AVG_C( pixel_avg_8x16,  8, 16 )
PIXEL_AVG_C( pixel_avg_8x8,   8, 8 )
PIXEL_AVG_C( pixel_avg_8x4,   8, 4 )
PIXEL_AVG_C( pixel_avg_4x16,  4, 16 )
PIXEL_AVG_C( pixel_avg_4x8,   4, 8 )
PIXEL_AVG_C( pixel_avg_4x4,   4, 4 )
PIXEL_AVG_C( pixel_avg_4x2,   4, 2 )
PIXEL_AVG_C( pixel_avg_2x8,   2, 8 )
PIXEL_AVG_C( pixel_avg_2x4,   2, 4 )
PIXEL_AVG_C( pixel_avg_2x2,   2, 2 )

static void x264_weight_cache( x264_t *h, x264_weight_t *w )
{
    w->weightfn = h->mc.weight;
}
#define opscale(x) dst[x] = x264_clip_pixel( ((src[x] * scale + (1<<(denom - 1))) >> denom) + offset )
#define opscale_noden(x) dst[x] = x264_clip_pixel( src[x] * scale + offset )
static void mc_weight( pixel *dst, intptr_t i_dst_stride, pixel *src, intptr_t i_src_stride,
                       const x264_weight_t *weight, int i_width, int i_height )
{
    int offset = weight->i_offset << (BIT_DEPTH-8);
    int scale = weight->i_scale;
    int denom = weight->i_denom;
    if( denom >= 1 )
    {
        for( int y = 0; y < i_height; y++, dst += i_dst_stride, src += i_src_stride )
            for( int x = 0; x < i_width; x++ )
                opscale( x );
    }
    else
    {
        for( int y = 0; y < i_height; y++, dst += i_dst_stride, src += i_src_stride )
            for( int x = 0; x < i_width; x++ )
                opscale_noden( x );
    }
}

#define MC_WEIGHT_C( name, width ) \
    static void name( pixel *dst, intptr_t i_dst_stride, pixel *src, intptr_t i_src_stride, const x264_weight_t *weight, int height ) \
{ \
    mc_weight( dst, i_dst_stride, src, i_src_stride, weight, width, height );\
}

MC_WEIGHT_C( mc_weight_w20, 20 )
MC_WEIGHT_C( mc_weight_w16, 16 )
MC_WEIGHT_C( mc_weight_w12, 12 )
MC_WEIGHT_C( mc_weight_w8,   8 )
MC_WEIGHT_C( mc_weight_w4,   4 )
MC_WEIGHT_C( mc_weight_w2,   2 )

static weight_fn_t x264_mc_weight_wtab[6] =
{
    mc_weight_w2,
    mc_weight_w4,
    mc_weight_w8,
    mc_weight_w12,
    mc_weight_w16,
    mc_weight_w20,
};
const x264_weight_t x264_weight_none[3] = { {{0}} };
static void mc_copy( pixel *src, intptr_t i_src_stride, pixel *dst, intptr_t i_dst_stride, int i_width, int i_height )
{
    for( int y = 0; y < i_height; y++ )
    {
        memcpy( dst, src, i_width * sizeof(pixel) );

        src += i_src_stride;
        dst += i_dst_stride;
    }
}

#define TAPFILTER(pix, d) ((pix)[x-2*d] + (pix)[x+3*d] - 5*((pix)[x-d] + (pix)[x+2*d]) + 20*((pix)[x] + (pix)[x+d]))
static void hpel_filter( pixel *dsth, pixel *dstv, pixel *dstc, pixel *src,
                         intptr_t stride, int width, int height, int16_t *buf )
{
    const int pad = (BIT_DEPTH > 9) ? (-10 * PIXEL_MAX) : 0;
    for( int y = 0; y < height; y++ )
    {
        for( int x = -2; x < width+3; x++ )
        {
            int v = TAPFILTER(src,stride);
            dstv[x] = x264_clip_pixel( (v + 16) >> 5 );
            /* transform v for storage in a 16-bit integer */
            buf[x+2] = v + pad;
        }
        for( int x = 0; x < width; x++ )
            dstc[x] = x264_clip_pixel( (TAPFILTER(buf+2,1) - 32*pad + 512) >> 10 );
        for( int x = 0; x < width; x++ )
            dsth[x] = x264_clip_pixel( (TAPFILTER(src,1) + 16) >> 5 );
        dsth += stride;
        dstv += stride;
        dstc += stride;
        src += stride;
    }
}

static const uint8_t hpel_ref0[16] = {0,1,1,1,0,1,1,1,2,3,3,3,0,1,1,1};
static const uint8_t hpel_ref1[16] = {0,0,0,0,2,2,3,2,2,2,3,2,2,2,3,2};

static void mc_luma( pixel *dst,    intptr_t i_dst_stride,
                     pixel *src[4], intptr_t i_src_stride,
                     int mvx, int mvy,
                     int i_width, int i_height, const x264_weight_t *weight )
{
    int qpel_idx = ((mvy&3)<<2) + (mvx&3);
    int offset = (mvy>>2)*i_src_stride + (mvx>>2);
    pixel *src1 = src[hpel_ref0[qpel_idx]] + offset + ((mvy&3) == 3) * i_src_stride;

    if( qpel_idx & 5 ) /* qpel interpolation needed */
    {
        pixel *src2 = src[hpel_ref1[qpel_idx]] + offset + ((mvx&3) == 3);
        pixel_avg( dst, i_dst_stride, src1, i_src_stride,
                   src2, i_src_stride, i_width, i_height );
        if( weight->weightfn )
            mc_weight( dst, i_dst_stride, dst, i_dst_stride, weight, i_width, i_height );
    }
    else if( weight->weightfn )
        mc_weight( dst, i_dst_stride, src1, i_src_stride, weight, i_width, i_height );
    else
        mc_copy( src1, i_src_stride, dst, i_dst_stride, i_width, i_height );
}

static pixel *get_ref( pixel *dst,   intptr_t *i_dst_stride,
                       pixel *src[4], intptr_t i_src_stride,
                       int mvx, int mvy,
                       int i_width, int i_height, const x264_weight_t *weight )
{
    int qpel_idx = ((mvy&3)<<2) + (mvx&3);
    int offset = (mvy>>2)*i_src_stride + (mvx>>2);
    pixel *src1 = src[hpel_ref0[qpel_idx]] + offset + ((mvy&3) == 3) * i_src_stride;

    if( qpel_idx & 5 ) /* qpel interpolation needed */
    {
        pixel *src2 = src[hpel_ref1[qpel_idx]] + offset + ((mvx&3) == 3);
        pixel_avg( dst, *i_dst_stride, src1, i_src_stride,
                   src2, i_src_stride, i_width, i_height );
        if( weight->weightfn )
            mc_weight( dst, *i_dst_stride, dst, *i_dst_stride, weight, i_width, i_height );
        return dst;
    }
    else if( weight->weightfn )
    {
        mc_weight( dst, *i_dst_stride, src1, i_src_stride, weight, i_width, i_height );
        return dst;
    }
    else
    {
        *i_dst_stride = i_src_stride;
        return src1;
    }
}

/* full chroma mc (ie until 1/8 pixel)*/
static void mc_chroma( pixel *dstu, pixel *dstv, intptr_t i_dst_stride,
                       pixel *src, intptr_t i_src_stride,
                       int mvx, int mvy,
                       int i_width, int i_height )
{
    pixel *srcp;

    int d8x = mvx&0x07;
    int d8y = mvy&0x07;
    int cA = (8-d8x)*(8-d8y);
    int cB = d8x    *(8-d8y);
    int cC = (8-d8x)*d8y;
    int cD = d8x    *d8y;

    src += (mvy >> 3) * i_src_stride + (mvx >> 3)*2;
    srcp = &src[i_src_stride];

    for( int y = 0; y < i_height; y++ )
    {
        for( int x = 0; x < i_width; x++ )
        {
            dstu[x] = ( cA*src[2*x]  + cB*src[2*x+2] +
                        cC*srcp[2*x] + cD*srcp[2*x+2] + 32 ) >> 6;
            dstv[x] = ( cA*src[2*x+1]  + cB*src[2*x+3] +
                        cC*srcp[2*x+1] + cD*srcp[2*x+3] + 32 ) >> 6;
        }
        dstu += i_dst_stride;
        dstv += i_dst_stride;
        src   = srcp;
        srcp += i_src_stride;
    }
}

#define MC_COPY(W) \
static void mc_copy_w##W( pixel *dst, intptr_t i_dst, pixel *src, intptr_t i_src, int i_height ) \
{ \
    mc_copy( src, i_src, dst, i_dst, W, i_height ); \
}
MC_COPY( 16 )
MC_COPY( 8 )
MC_COPY( 4 )

void x264_plane_copy_c( pixel *dst, intptr_t i_dst,
                        pixel *src, intptr_t i_src, int w, int h )
{
    while( h-- )
    {
        memcpy( dst, src, w * sizeof(pixel) );
        dst += i_dst;
        src += i_src;
    }
}

void x264_plane_copy_interleave_c( pixel *dst,  intptr_t i_dst,
                                   pixel *srcu, intptr_t i_srcu,
                                   pixel *srcv, intptr_t i_srcv, int w, int h )
{
    for( int y=0; y<h; y++, dst+=i_dst, srcu+=i_srcu, srcv+=i_srcv )
        for( int x=0; x<w; x++ )
        {
            dst[2*x]   = srcu[x];
            dst[2*x+1] = srcv[x];
        }
}

static void x264_plane_copy_deinterleave_c( pixel *dstu, intptr_t i_dstu,
                                            pixel *dstv, intptr_t i_dstv,
                                            pixel *src,  intptr_t i_src, int w, int h )
{
    for( int y=0; y<h; y++, dstu+=i_dstu, dstv+=i_dstv, src+=i_src )
        for( int x=0; x<w; x++ )
        {
            dstu[x] = src[2*x];
            dstv[x] = src[2*x+1];
        }
}

static void x264_plane_copy_deinterleave_rgb_c( pixel *dsta, intptr_t i_dsta,
                                                pixel *dstb, intptr_t i_dstb,
                                                pixel *dstc, intptr_t i_dstc,
                                                pixel *src,  intptr_t i_src, int pw, int w, int h )
{
    for( int y=0; y<h; y++, dsta+=i_dsta, dstb+=i_dstb, dstc+=i_dstc, src+=i_src )
    {
        for( int x=0; x<w; x++ )
        {
            dsta[x] = src[x*pw];
            dstb[x] = src[x*pw+1];
            dstc[x] = src[x*pw+2];
        }
    }
}

void x264_plane_copy_deinterleave_v210_c( pixel *dsty, intptr_t i_dsty,
                                          pixel *dstc, intptr_t i_dstc,
                                          uint32_t *src, intptr_t i_src, int w, int h )
{
    for( int l = 0; l < h; l++ )
    {
        pixel *dsty0 = dsty;
        pixel *dstc0 = dstc;
        uint32_t *src0 = src;

        for( int n = 0; n < w; n += 3 )
        {
            *(dstc0++) = *src0 & 0x03FF;
            *(dsty0++) = ( *src0 >> 10 ) & 0x03FF;
            *(dstc0++) = ( *src0 >> 20 ) & 0x03FF;
            src0++;
            *(dsty0++) = *src0 & 0x03FF;
            *(dstc0++) = ( *src0 >> 10 ) & 0x03FF;
            *(dsty0++) = ( *src0 >> 20 ) & 0x03FF;
            src0++;
        }

        dsty += i_dsty;
        dstc += i_dstc;
        src  += i_src;
    }
}

static void store_interleave_chroma( pixel *dst, intptr_t i_dst, pixel *srcu, pixel *srcv, int height )
{
    for( int y=0; y<height; y++, dst+=i_dst, srcu+=FDEC_STRIDE, srcv+=FDEC_STRIDE )
        for( int x=0; x<8; x++ )
        {
            dst[2*x]   = srcu[x];
            dst[2*x+1] = srcv[x];
        }
}

static void load_deinterleave_chroma_fenc( pixel *dst, pixel *src, intptr_t i_src, int height )
{
    x264_plane_copy_deinterleave_c( dst, FENC_STRIDE, dst+FENC_STRIDE/2, FENC_STRIDE, src, i_src, 8, height );
}

static void load_deinterleave_chroma_fdec( pixel *dst, pixel *src, intptr_t i_src, int height )
{
    x264_plane_copy_deinterleave_c( dst, FDEC_STRIDE, dst+FDEC_STRIDE/2, FDEC_STRIDE, src, i_src, 8, height );
}

static void prefetch_fenc_null( pixel *pix_y,  intptr_t stride_y,
                                pixel *pix_uv, intptr_t stride_uv, int mb_x )
{}

static void prefetch_ref_null( pixel *pix, intptr_t stride, int parity )
{}

static void memzero_aligned( void * dst, size_t n )
{
    memset( dst, 0, n );
}

static void integral_init4h( uint16_t *sum, pixel *pix, intptr_t stride )
{
    int v = pix[0]+pix[1]+pix[2]+pix[3];
    for( int x = 0; x < stride-4; x++ )
    {
        sum[x] = v + sum[x-stride];
        v += pix[x+4] - pix[x];
    }
}

static void integral_init8h( uint16_t *sum, pixel *pix, intptr_t stride )
{
    int v = pix[0]+pix[1]+pix[2]+pix[3]+pix[4]+pix[5]+pix[6]+pix[7];
    for( int x = 0; x < stride-8; x++ )
    {
        sum[x] = v + sum[x-stride];
        v += pix[x+8] - pix[x];
    }
}

static void integral_init4v( uint16_t *sum8, uint16_t *sum4, intptr_t stride )
{
    for( int x = 0; x < stride-8; x++ )
        sum4[x] = sum8[x+4*stride] - sum8[x];
    for( int x = 0; x < stride-8; x++ )
        sum8[x] = sum8[x+8*stride] + sum8[x+8*stride+4] - sum8[x] - sum8[x+4];
}

static void integral_init8v( uint16_t *sum8, intptr_t stride )
{
    for( int x = 0; x < stride-8; x++ )
        sum8[x] = sum8[x+8*stride] - sum8[x];
}

void x264_frame_init_lowres( x264_t *h, x264_frame_t *frame )
{
    pixel *src = frame->plane[0];
    int i_stride = frame->i_stride[0];
    int i_height = frame->i_lines[0];
    int i_width  = frame->i_width[0];

    // duplicate last row and column so that their interpolation doesn't have to be special-cased
    for( int y = 0; y < i_height; y++ )
        src[i_width+y*i_stride] = src[i_width-1+y*i_stride];
    memcpy( src+i_stride*i_height, src+i_stride*(i_height-1), (i_width+1) * sizeof(pixel) );
    h->mc.frame_init_lowres_core( src, frame->lowres[0], frame->lowres[1], frame->lowres[2], frame->lowres[3],
                                  i_stride, frame->i_stride_lowres, frame->i_width_lowres, frame->i_lines_lowres );
    x264_frame_expand_border_lowres( frame );
#if HIGH_BIT_DEPTH
    /* rc.b_lookahead_8bit: the 8-bit buffer has the same layout, so convert all
     * four planes, padding included, in one go. The plane size is a multiple of
     * 16 pixels, so the total is a multiple of 64. */
    if( frame->buffer_lowres8 )
        h->mc.lowres8_convert( frame->buffer_lowres8, frame->buffer_lowres[0],
                               4 * (frame->lowres[1] - frame->lowres[0]) );
#endif

    x264_frame_init_lowres_finish( h, frame );
}

/* x264_frame_init_lowres in bands, for sliced threads: _edge on luma rows
 * [y0,y1) of every band, then after all of them _rows on MB rows
 * [mb_y0,mb_y1) of every band, then _finish. */
void x264_frame_init_lowres_edge( x264_frame_t *frame, int y0, int y1 )
{
    pixel *src = frame->plane[0];
    int i_stride = frame->i_stride[0];
    int i_height = frame->i_lines[0];
    int i_width  = frame->i_width[0];

    for( int y = y0; y < y1; y++ )
        src[i_width+y*i_stride] = src[i_width-1+y*i_stride];
    if( y1 == i_height )
        memcpy( src+i_stride*i_height, src+i_stride*(i_height-1), (i_width+1) * sizeof(pixel) );
}

void x264_frame_init_lowres_rows( x264_t *h, x264_frame_t *frame, int mb_y0, int mb_y1 )
{
    int i_stride = frame->i_stride[0];
    int i_stride_lowres = frame->i_stride_lowres;
    int y0 = 8 * mb_y0;
    int y1 = 8 * mb_y1;
    int offset = y0 * i_stride_lowres;

    /* reads source rows 2*y0 to 2*y1 inclusive, so one row of the next band */
    h->mc.frame_init_lowres_core( frame->plane[0] + 2*y0*i_stride,
                                  frame->lowres[0] + offset, frame->lowres[1] + offset,
                                  frame->lowres[2] + offset, frame->lowres[3] + offset,
                                  i_stride, i_stride_lowres, frame->i_width_lowres, y1 - y0 );
    x264_frame_expand_border_lowres_rows( frame, y0, y1 );
#if HIGH_BIT_DEPTH
    /* This band's rows of the four planes with their side padding, plus the
     * padding above the first row or below the last one; offsets are whole
     * rows, so every piece is a multiple of the stride alignment. */
    if( frame->buffer_lowres8 )
    {
        intptr_t plane_size = frame->lowres[1] - frame->lowres[0];
        intptr_t start = y0 ? (intptr_t)(PADV + y0) * i_stride_lowres : 0;
        intptr_t end   = y1 < frame->i_lines_lowres ? (intptr_t)(PADV + y1) * i_stride_lowres : plane_size;
        for( int i = 0; i < 4; i++ )
            h->mc.lowres8_convert( frame->buffer_lowres8 + i*plane_size + start,
                                   frame->buffer_lowres[0] + i*plane_size + start, end - start );
    }
#endif
}

void x264_frame_init_lowres_finish( x264_t *h, x264_frame_t *frame )
{
    memset( frame->i_cost_est, -1, sizeof(frame->i_cost_est) );

    for( int y = 0; y < h->param.i_bframe + 2; y++ )
        for( int x = 0; x < h->param.i_bframe + 2; x++ )
            frame->i_row_satds[y][x][0] = -1;

    for( int y = 0; y <= !!h->param.i_bframe; y++ )
        for( int x = 0; x <= h->param.i_bframe; x++ )
            frame->lowres_mvs[y][x][0][0] = 0x7FFF;
}

#if HIGH_BIT_DEPTH
static void lowres8_convert( uint8_t *dst, pixel *src, intptr_t n )
{
    for( intptr_t i = 0; i < n; i++ )
        dst[i] = X264_MIN( (src[i] + (1 << (BIT_DEPTH-9))) >> (BIT_DEPTH-8), 255 );
}

static void plane_split8( uint8_t *msb, uint8_t *lsb, pixel *src, intptr_t i_stride, int w, int h )
{
    for( int y = 0; y < h; y++ )
    {
        for( int x = 0; x < w; x += 4 )
        {
            int l = 0;
            for( int k = 0; k < 4; k++ )
            {
                msb[x+k] = src[x+k] >> (BIT_DEPTH-8);
                l |= (src[x+k] & ((1 << (BIT_DEPTH-8)) - 1)) << (2*k);
            }
            lsb[x>>2] = l;
        }
        msb += i_stride;
        lsb += i_stride >> 2;
        src += i_stride;
    }
}

static void plane_unpack8( pixel *dst, intptr_t i_dst, uint8_t *msb, uint8_t *lsb, intptr_t i_src, int w, int h )
{
    for( int y = 0; y < h; y++ )
    {
        for( int x = 0; x < w; x++ )
            dst[x] = msb[x] << (BIT_DEPTH-8) | ((lsb[x>>2] >> (2*(x&3))) & ((1 << (BIT_DEPTH-8)) - 1));
        dst += i_dst;
        msb += i_src;
        lsb += i_src >> 2;
    }
}
#endif

static void frame_init_lowres_core( pixel *src0, pixel *dst0, pixel *dsth, pixel *dstv, pixel *dstc,
                                    intptr_t src_stride, intptr_t dst_stride, int width, int height )
{
    for( int y = 0; y < height; y++ )
    {
        pixel *src1 = src0+src_stride;
        pixel *src2 = src1+src_stride;
        for( int x = 0; x<width; x++ )
        {
            // slower than naive bilinear, but matches asm
#define FILTER(a,b,c,d) ((((a+b+1)>>1)+((c+d+1)>>1)+1)>>1)
            dst0[x] = FILTER(src0[2*x  ], src1[2*x  ], src0[2*x+1], src1[2*x+1]);
            dsth[x] = FILTER(src0[2*x+1], src1[2*x+1], src0[2*x+2], src1[2*x+2]);
            dstv[x] = FILTER(src1[2*x  ], src2[2*x  ], src1[2*x+1], src2[2*x+1]);
            dstc[x] = FILTER(src1[2*x+1], src2[2*x+1], src1[2*x+2], src2[2*x+2]);
#undef FILTER
        }
        src0 += src_stride*2;
        dst0 += dst_stride;
        dsth += dst_stride;
        dstv += dst_stride;
        dstc += dst_stride;
    }
}

/* Estimate the total amount of influence on future quality that could be had if we
 * were to improve the reference samples used to inter predict any given macroblock. */
static void mbtree_propagate_cost( int16_t *dst, uint16_t *propagate_in, uint16_t *intra_costs,
                                   uint16_t *inter_costs, uint16_t *inv_qscales, float *fps_factor, int len )
{
    float fps = *fps_factor;
    for( int i = 0; i < len; i++ )
    {
        int intra_cost = intra_costs[i];
        int inter_cost = X264_MIN(intra_costs[i], inter_costs[i] & LOWRES_COST_MASK);
        float propagate_intra  = intra_cost * inv_qscales[i];
        float propagate_amount = propagate_in[i] + propagate_intra*fps;
        float propagate_num    = intra_cost - inter_cost;
        float propagate_denom  = intra_cost;
        dst[i] = X264_MIN((int)(propagate_amount * propagate_num / propagate_denom + 0.5f), 32767);
    }
}

static void mbtree_propagate_list( x264_t *h, uint16_t *ref_costs, int16_t (*mvs)[2],
                                   int16_t *propagate_amount, uint16_t *lowres_costs,
                                   int bipred_weight, int mb_y, int len, int list )
{
    unsigned stride = h->mb.i_mb_stride;
    unsigned width = h->mb.i_mb_width;
    unsigned height = h->mb.i_mb_height;

    for( unsigned i = 0; i < len; i++ )
    {
#define CLIP_ADD(s,x) (s) = X264_MIN((s)+(x),(1<<15)-1)
        int lists_used = lowres_costs[i]>>LOWRES_COST_SHIFT;

        if( !(lists_used & (1 << list)) )
            continue;

        int listamount = propagate_amount[i];
        /* Apply bipred weighting. */
        if( lists_used == 3 )
            listamount = (listamount * bipred_weight + 32) >> 6;

        /* Early termination for simple case of mv0. */
        if( !M32( mvs[i] ) )
        {
            CLIP_ADD( ref_costs[mb_y*stride + i], listamount );
            continue;
        }

        int x = mvs[i][0];
        int y = mvs[i][1];
        unsigned mbx = (x>>5)+i;
        unsigned mby = (y>>5)+mb_y;
        unsigned idx0 = mbx + mby * stride;
        unsigned idx2 = idx0 + stride;
        x &= 31;
        y &= 31;
        int idx0weight = (32-y)*(32-x);
        int idx1weight = (32-y)*x;
        int idx2weight = y*(32-x);
        int idx3weight = y*x;
        idx0weight = (idx0weight * listamount + 512) >> 10;
        idx1weight = (idx1weight * listamount + 512) >> 10;
        idx2weight = (idx2weight * listamount + 512) >> 10;
        idx3weight = (idx3weight * listamount + 512) >> 10;

        if( mbx < width-1 && mby < height-1 )
        {
            CLIP_ADD( ref_costs[idx0+0], idx0weight );
            CLIP_ADD( ref_costs[idx0+1], idx1weight );
            CLIP_ADD( ref_costs[idx2+0], idx2weight );
            CLIP_ADD( ref_costs[idx2+1], idx3weight );
        }
        else
        {
            /* Note: this takes advantage of unsigned representation to
             * catch negative mbx/mby. */
            if( mby < height )
            {
                if( mbx < width )
                    CLIP_ADD( ref_costs[idx0+0], idx0weight );
                if( mbx+1 < width )
                    CLIP_ADD( ref_costs[idx0+1], idx1weight );
            }
            if( mby+1 < height )
            {
                if( mbx < width )
                    CLIP_ADD( ref_costs[idx2+0], idx2weight );
                if( mbx+1 < width )
                    CLIP_ADD( ref_costs[idx2+1], idx3weight );
            }
        }
    }
#undef CLIP_ADD
}

void x264_mc_init( int cpu, x264_mc_functions_t *pf, int cpu_independent )
{
    pf->mc_luma   = mc_luma;
    pf->get_ref   = get_ref;

    pf->mc_chroma = mc_chroma;

    pf->avg[PIXEL_16x16]= pixel_avg_16x16;
    pf->avg[PIXEL_16x8] = pixel_avg_16x8;
    pf->avg[PIXEL_8x16] = pixel_avg_8x16;
    pf->avg[PIXEL_8x8]  = pixel_avg_8x8;
    pf->avg[PIXEL_8x4]  = pixel_avg_8x4;
    pf->avg[PIXEL_4x16] = pixel_avg_4x16;
    pf->avg[PIXEL_4x8]  = pixel_avg_4x8;
    pf->avg[PIXEL_4x4]  = pixel_avg_4x4;
    pf->avg[PIXEL_4x2]  = pixel_avg_4x2;
    pf->avg[PIXEL_2x8]  = pixel_avg_2x8;
    pf->avg[PIXEL_2x4]  = pixel_avg_2x4;
    pf->avg[PIXEL_2x2]  = pixel_avg_2x2;

    pf->weight    = x264_mc_weight_wtab;
    pf->offsetadd = x264_mc_weight_wtab;
    pf->offsetsub = x264_mc_weight_wtab;
    pf->weight_cache = x264_weight_cache;

    pf->copy_16x16_unaligned = mc_copy_w16;
    pf->copy[PIXEL_16x16] = mc_copy_w16;
    pf->copy[PIXEL_8x8]   = mc_copy_w8;
    pf->copy[PIXEL_4x4]   = mc_copy_w4;

    pf->store_interleave_chroma       = store_interleave_chroma;
    pf->load_deinterleave_chroma_fenc = load_deinterleave_chroma_fenc;
    pf->load_deinterleave_chroma_fdec = load_deinterleave_chroma_fdec;

    pf->plane_copy = x264_plane_copy_c;
    pf->plane_copy_interleave = x264_plane_copy_interleave_c;
    pf->plane_copy_deinterleave = x264_plane_copy_deinterleave_c;
    pf->plane_copy_deinterleave_rgb = x264_plane_copy_deinterleave_rgb_c;
    pf->plane_copy_deinterleave_v210 = x264_plane_copy_deinterleave_v210_c;

    pf->hpel_filter = hpel_filter;
    pf->hpel_filter_copy = NULL;
    pf->hpel_filter8 = NULL;

    pf->prefetch_fenc_420 = prefetch_fenc_null;
    pf->prefetch_fenc_422 = prefetch_fenc_null;
    pf->prefetch_ref  = prefetch_ref_null;
    pf->memcpy_aligned = memcpy;
    pf->memzero_aligned = memzero_aligned;
    pf->frame_init_lowres_core = frame_init_lowres_core;
#if HIGH_BIT_DEPTH
    pf->lowres8_convert = lowres8_convert;
    pf->plane_split8 = plane_split8;
    pf->plane_unpack8 = plane_unpack8;
#endif
    memset( pf->copy_pk, 0, sizeof(pf->copy_pk) );
    memset( pf->avg2_pk, 0, sizeof(pf->avg2_pk) );

    pf->integral_init4h = integral_init4h;
    pf->integral_init8h = integral_init8h;
    pf->integral_init4v = integral_init4v;
    pf->integral_init8v = integral_init8v;

    pf->mbtree_propagate_cost = mbtree_propagate_cost;
    pf->mbtree_propagate_list = mbtree_propagate_list;

#if HAVE_MMX
    x264_mc_init_mmx( cpu, pf );
#endif
#if HAVE_ALTIVEC
    if( cpu&X264_CPU_ALTIVEC )
        x264_mc_altivec_init( pf );
#endif
#if HAVE_ARMV6
    x264_mc_init_arm( cpu, pf );
#endif

    if( cpu_independent )
    {
        pf->mbtree_propagate_cost = mbtree_propagate_cost;
        pf->mbtree_propagate_list = mbtree_propagate_list;
    }
}

#if HIGH_BIT_DEPTH
/* X264_ME8_HPEL8: hpel of rows [0, height) of src writing only the
 * msb8/lsb8 split of h, v and c (msb8[1..3] + offs, lsb8[1..3] + lsb_offs).
 * With dstf, hpel_filter_copy's copy of src to dstf. Without the asm, or with
 * the copy, row by row through scratch rows of 16-bit h, v and c. */
static void hpel_filter_split8( x264_t *h, uint8_t **msb8, uint8_t **lsb8, pixel *src, intptr_t stride,
                                int offs, int lsb_offs, int width, int height, pixel *dstf )
{
    uint8_t *msb = msb8[1] + offs;
    uint8_t *lsb = lsb8[1] + lsb_offs;
    intptr_t plane8 = msb8[2] - msb8[1];
    if( !dstf && h->mc.hpel_filter8 )
        h->mc.hpel_filter8( msb, lsb, plane8, src, stride, width, height, h->scratch_buffer );
    else
    {
        /* in phase with src mod 64 bytes: the kernels realign src and store aligned */
        intptr_t rs = X264_SPLIT8_ROW_STRIDE( width );
        pixel *rh = (pixel*)((uint8_t*)h->scratch_buffer + X264_SPLIT8_ROWS_OFFSET( width ) + ((intptr_t)src & 63));
        pixel *rv = rh + rs;
        pixel *rc = rh + 2*rs;
        for( int y = 0; y < height; y++ )
        {
            if( !dstf )
                h->mc.hpel_filter( rh, rv, rc, src, stride, width, 1, h->scratch_buffer );
            else if( h->mc.hpel_filter_copy )
                h->mc.hpel_filter_copy( rh, rv, rc, src, stride, width, 1, h->scratch_buffer, dstf );
            else
            {
                h->mc.hpel_filter( rh, rv, rc, src, stride, width, 1, h->scratch_buffer );
                memcpy( dstf, src, width * sizeof(pixel) );
            }
            h->mc.plane_split8( msb, lsb, rh, 0, width, 1 );
            h->mc.plane_split8( msb + plane8, lsb + plane8, rv, 0, width, 1 );
            h->mc.plane_split8( msb + 2*plane8, lsb + 2*plane8, rc, 0, width, 1 );
            src += stride;
            msb += stride;
            lsb += stride >> 2;
            if( dstf )
                dstf += stride;
        }
    }
#ifdef X264_ME8_VERIFY_CONTROL
    /* positive control of the verifier and the md5 identity: h's pixel 16
     * (lsb byte 6 after x = -8) gets lsb 3 in every row */
    for( int y = 0; y < height; y++ )
        lsb8[1][lsb_offs + y*(stride>>2) + 6] |= 3;
#endif
}

/* rows of a temp plane window: 19 for get_ref's 17 rows read 2 at a time from row 1 */
#define SPLIT8_ROWS 20

/* plane k's i_width x i_height window at pixel offset o from src8's block,
 * unpacked into buf; columns from o&~3, rounded up to 16 */
static ALWAYS_INLINE pixel *split8_window( x264_t *h, pixel *buf, uint8_t **src8, int k, intptr_t i_src,
                                           intptr_t o, int i_width, int i_height )
{
    int ph = o & 3;
    h->mc.plane_unpack8( buf, X264_SPLIT8_STRIDE, src8[k] + o - ph, src8[4+k] + (o >> 2), i_src,
                         ALIGN( ph + i_width, 16 ), i_height );
    return buf + ph;
}

/* mc_luma/get_ref's planes at mv as seen from (mvx&3, mvy&3) with stride
 * X264_SPLIT8_STRIDE: each plane they read, over what their kernels can reach
 * (pixel_avg2_w16 for width 12, w18 or mc_weight_w20 for 20, plus the column
 * and row of the second source, rows read two at a time) */
static void split8_view( x264_t *h, pixel *view[4], pixel *buf, uint8_t **src8, intptr_t i_src,
                         int mvx, int mvy, int i_width, int i_height )
{
    int qpel_idx = ((mvy&3)<<2) + (mvx&3);
    intptr_t o = (mvy>>2)*i_src + (mvx>>2);
    int w = (i_width == 12 ? 16 : i_width) + 1;
    int rows = i_height + 1 + (i_height&1);
    int k0 = x264_hpel_ref0[qpel_idx];
    view[k0] = split8_window( h, buf, src8, k0, i_src, o, w, rows );
    if( qpel_idx & 5 )
    {
        int k1 = x264_hpel_ref1[qpel_idx];
        view[k1] = split8_window( h, buf + X264_SPLIT8_STRIDE*SPLIT8_ROWS, src8, k1, i_src, o, w, rows );
    }
}

/* mc_luma's unweighted prediction at a subpel mv, read in place (copy_pk/avg2_pk) */
static ALWAYS_INLINE void mc_pred_pk( x264_t *h, pixel *dst, intptr_t i_dst, uint8_t **src8, intptr_t i_src,
                                      int mvx, int mvy, int i_width, int i_height )
{
    uint8_t *pk[4];
    if( x264_pk_hpel_pair( pk, src8, i_src, mvx, mvy ) )
        h->mc.avg2_pk[i_width>>2]( dst, i_dst, pk[0], pk[1], pk[2], pk[3], i_src, i_height );
    else
        h->mc.copy_pk[i_width>>2]( dst, i_dst, pk[0], pk[1], i_src, i_height );
}

void x264_mc_luma_split8( x264_t *h, pixel *dst, intptr_t i_dst, pixel **src, uint8_t **src8, intptr_t i_src,
                          int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight )
{
    if( !((mvx|mvy)&3) )
    {
        h->mc.mc_luma( dst, i_dst, src, i_src, mvx, mvy, i_width, i_height, weight );
        return;
    }
    if( h->mc.copy_pk[1] )
    {
        /* weighted: in place, as mc_luma weights its qpel average */
        mc_pred_pk( h, dst, i_dst, src8, i_src, mvx, mvy, i_width, i_height );
        if( weight->weightfn )
            weight->weightfn[i_width>>2]( dst, i_dst, dst, i_dst, weight, i_height );
        return;
    }
    ALIGNED_ARRAY_64( pixel, buf,[2*X264_SPLIT8_STRIDE*SPLIT8_ROWS] );
    pixel *view[4];
    split8_view( h, view, buf, src8, i_src, mvx, mvy, i_width, i_height );
    h->mc.mc_luma( dst, i_dst, view, X264_SPLIT8_STRIDE, mvx&3, mvy&3, i_width, i_height, weight );
}

pixel *x264_get_ref_split8( x264_t *h, pixel *dst, intptr_t *i_dst, pixel **src, uint8_t **src8, intptr_t i_src,
                            int mvx, int mvy, int i_width, int i_height, const x264_weight_t *weight )
{
    if( !((mvx|mvy)&3) )
        return h->mc.get_ref( dst, i_dst, src, i_src, mvx, mvy, i_width, i_height, weight );
    if( h->mc.copy_pk[1] )
    {
        /* dst also where get_ref would return an hpel plane */
        mc_pred_pk( h, dst, *i_dst, src8, i_src, mvx, mvy, i_width, i_height );
        if( weight->weightfn )
            weight->weightfn[i_width>>2]( dst, *i_dst, dst, *i_dst, weight, i_height );
        return dst;
    }
    ALIGNED_ARRAY_64( pixel, buf,[2*X264_SPLIT8_STRIDE*SPLIT8_ROWS] );
    pixel *view[4];
    intptr_t stride = *i_dst;
    split8_view( h, view, buf, src8, i_src, mvx, mvy, i_width, i_height );
    pixel *ret = h->mc.get_ref( dst, i_dst, view, X264_SPLIT8_STRIDE, mvx&3, mvy&3, i_width, i_height, weight );
    if( ret != dst )
    {
        /* an unweighted hpel plane, in buf */
        for( int y = 0; y < i_height; y++ )
            memcpy( dst + y*stride, ret + y*X264_SPLIT8_STRIDE, i_width * sizeof(pixel) );
        *i_dst = stride;
    }
    return dst;
}

void x264_mc_hpel_pair_split8( x264_t *h, pixel *dst[2], pixel *buf, uint8_t **src8, intptr_t i_src,
                               int mvx, int mvy, int i_width, int i_height )
{
    int qpel_idx = ((mvy&3)<<2) + (mvx&3);
    intptr_t o = (mvy>>2)*i_src + (mvx>>2);
    dst[0] = split8_window( h, buf, src8, x264_hpel_ref0[qpel_idx], i_src, o + ((mvy&3) == 3) * i_src,
                            i_width, i_height );
    dst[1] = qpel_idx & 5 ? split8_window( h, buf + X264_SPLIT8_STRIDE*i_height, src8, x264_hpel_ref1[qpel_idx],
                                           i_src, o + ((mvx&3) == 3), i_width, i_height )
                          : dst[0];
}
#endif

/* Field hpel of field rows [y0, y1) of parity i. With b_copy, read the frame
 * plane and copy it to plane_fld as we go. */
static void frame_filter_fld( x264_t *h, x264_frame_t *frame, int p, int i, int y0, int y1, int b_copy )
{
    intptr_t stride = frame->i_stride[p] << 1;
    int width = frame->i_width[p] + 16;
    int offs = y0*stride + i*frame->i_stride[p] - 8;
    if( y1 <= y0 )
        return;
    /* the 16-bit h, v and c, but for X264_ME8_HPEL8's luma (X264_ME8_VERIFY's shadow) */
    if( frame->filtered_fld[p][1] )
    {
        pixel *dsth = frame->filtered_fld[p][1] + offs;
        pixel *dstv = frame->filtered_fld[p][2] + offs;
        pixel *dstc = frame->filtered_fld[p][3] + offs;
        if( !b_copy )
            h->mc.hpel_filter( dsth, dstv, dstc, frame->plane_fld[p] + offs, stride, width, y1 - y0, h->scratch_buffer );
        else if( h->mc.hpel_filter_copy )
            h->mc.hpel_filter_copy( dsth, dstv, dstc, frame->plane[p] + offs, stride, width, y1 - y0, h->scratch_buffer,
                                    frame->plane_fld[p] + offs );
        else
        {
            h->mc.hpel_filter( dsth, dstv, dstc, frame->plane[p] + offs, stride, width, y1 - y0, h->scratch_buffer );
            for( int y = 0; y < y1 - y0; y++ )
                memcpy( frame->plane_fld[p] + offs + y*stride, frame->plane[p] + offs + y*stride, width * sizeof(pixel) );
        }
    }
#if HIGH_BIT_DEPTH
    if( !p && frame->msb8_fld[1] )
        hpel_filter_split8( h, frame->msb8_fld, frame->lsb8_fld, (b_copy ? frame->plane[0] : frame->plane_fld[0]) + offs,
                            stride, offs, y0*(stride>>2) + i*(frame->i_stride[0]>>2) - 2, width, y1 - y0,
                            b_copy ? frame->plane_fld[0] + offs : NULL );
#endif
}

void x264_frame_filter( x264_t *h, x264_frame_t *frame, int mb_y, int b_end )
{
    const int b_interlaced = PARAM_INTERLACED;
    int start = mb_y*16 - 8; // buffer = 4 for deblock + 3 for 6tap, rounded to 8
    int height = (b_end ? frame->i_lines[0] + 16*PARAM_INTERLACED : (mb_y+b_interlaced)*16) + 8;

    if( mb_y & b_interlaced )
        return;

    for( int p = 0; p < (CHROMA444 ? 3 : 1); p++ )
    {
        int stride = frame->i_stride[p];
        const int width = frame->i_width[p];
        int offs = start*stride - 8; // buffer = 3 for 6tap, aligned to 8 for simd

        if( !b_interlaced || h->mb.b_adaptive_mbaff )
        {
            if( frame->filtered[p][1] )
                h->mc.hpel_filter(
                    frame->filtered[p][1] + offs,
                    frame->filtered[p][2] + offs,
                    frame->filtered[p][3] + offs,
                    frame->plane[p] + offs,
                    stride, width + 16, height - start,
                    h->scratch_buffer );
#if HIGH_BIT_DEPTH
            if( !p && frame->msb8[1] )
                hpel_filter_split8( h, frame->msb8, frame->lsb8, frame->plane[0] + offs, stride,
                                    offs, start*(stride>>2) - 2, width + 16, height - start, NULL );
#endif
        }

        if( b_interlaced )
        {
            /* MC must happen between pixels in the same field. */
            start = (mb_y*16 >> 1) - 8;
            int height_fld = ((b_end ? frame->i_lines[p] : mb_y*16) >> 1) + 8;
            /* Rows whose 6-tap window (rows -2..3) is inside the picture see
             * the same pixels in the frame plane, and copy them to plane_fld.
             * The others read plane_fld's field borders, and the fullpel rows
             * near them, which the encoder copies (top and bottom 16 rows). */
            int y0 = x264_clip3( 2, start, height_fld );
            int y1 = x264_clip3( (frame->i_lines[p] >> 1) - 3, y0, height_fld );
            for( int i = 0; i < 2; i++ )
            {
                frame_filter_fld( h, frame, p, i, start, y0, 0 );
                frame_filter_fld( h, frame, p, i, y0, y1, 1 );
                frame_filter_fld( h, frame, p, i, y1, height_fld, 0 );
            }
        }
    }

    /* generate integral image:
     * frame->integral contains 2 planes. in the upper plane, each element is
     * the sum of an 8x8 pixel region with top-left corner on that point.
     * in the lower plane, 4x4 sums (needed only with --partitions p4x4). */

    if( frame->integral )
    {
        int stride = frame->i_stride[0];
        if( start < 0 )
        {
            memset( frame->integral - PADV * stride - PADH, 0, stride * sizeof(uint16_t) );
            start = -PADV;
        }
        if( b_end )
            height += PADV-9;
        for( int y = start; y < height; y++ )
        {
            pixel    *pix  = frame->plane[0] + y * stride - PADH;
            uint16_t *sum8 = frame->integral + (y+1) * stride - PADH;
            uint16_t *sum4;
            if( h->frames.b_have_sub8x8_esa )
            {
                h->mc.integral_init4h( sum8, pix, stride );
                sum8 -= 8*stride;
                sum4 = sum8 + stride * (frame->i_lines[0] + PADV*2);
                if( y >= 8-PADV )
                    h->mc.integral_init4v( sum8, sum4, stride );
            }
            else
            {
                h->mc.integral_init8h( sum8, pix, stride );
                if( y >= 8-PADV )
                    h->mc.integral_init8v( sum8-8*stride, stride );
            }
        }
    }
}
