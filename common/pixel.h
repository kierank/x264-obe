/*****************************************************************************
 * pixel.c: pixel metrics
 *****************************************************************************
 * Copyright (C) 2004-2014 x264 project
 *
 * Authors: Loren Merritt <lorenm@u.washington.edu>
 *          Jason Garrett-Glaser <darkshikari@gmail.com>
            Henrik Gramner <henrik@gramner.com>
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

#ifndef X264_PIXEL_H
#define X264_PIXEL_H

// SSD assumes all args aligned
// other cmp functions assume first arg aligned
typedef int  (*x264_pixel_cmp_t) ( pixel *, intptr_t, pixel *, intptr_t );
typedef void (*x264_pixel_cmp_x3_t) ( pixel *, pixel *, pixel *, pixel *, intptr_t, int[3] );
typedef void (*x264_pixel_cmp_x4_t) ( pixel *, pixel *, pixel *, pixel *, pixel *, intptr_t, int[4] );
/* min( best, (cmp( fenc, pix_i ) << 6) + bias_i ), compared as int; bias01 = bias_0 | bias_1 << 32,
 * x3: bias2_best = bias_2 | best << 32, x4: bias23 = bias_2 | bias_3 << 32 and best */
typedef int  (*x264_pixel_cmp_x3_min_t) ( pixel *, pixel *, pixel *, pixel *, intptr_t, uint64_t bias01, uint64_t bias2_best );
typedef int  (*x264_pixel_cmp_x4_min_t) ( pixel *, pixel *, pixel *, pixel *, pixel *, intptr_t, uint64_t bias01, uint64_t bias23, int best );
/* the same over the 12 candidates pix + dx + dy*stride, dx -1..2, bias[] by dy -1, 1, 0 */
typedef int  (*x264_pixel_cmp_sq_min_t) ( pixel *fenc, pixel *pix, intptr_t, const int32_t bias[12], int best );
/* cmp( fenc (FENC_STRIDE), avg( src1, src2 ) (stride) ) without storing the average */
typedef int  (*x264_pixel_cmp_avg2_t) ( pixel *, pixel *, pixel *, intptr_t );
/* chroma ME: satd of the u and v mc_chroma( src, stride, dx, dy, width, height )
 * predictions against fenc's u (res[0]) and v (res[1]), without storing them;
 * high bit depth: fenc is interleaved uv like src, with the same stride;
 * 8-bit: fenc is the partition's part of satd_mcc_fenc_pre's output */
#if HIGH_BIT_DEPTH
typedef pixel x264_mcc_fenc_t;
#else
typedef int16_t x264_mcc_fenc_t;
#endif
typedef void (*x264_pixel_satd_mcc_t) ( x264_mcc_fenc_t *fenc, int res[2], pixel *src, intptr_t i_stride,
                                        int dx, int dy, int i_width, int i_height );
/* satd against fenc_pre, fenc's first transform stage from satd_fenc_pre */
typedef int  (*x264_pixel_cmp_pre_t) ( int16_t *fenc_pre, pixel *, intptr_t );
typedef int  (*x264_pixel_cmp_avg2_pre_t) ( int16_t *fenc_pre, pixel *, pixel *, intptr_t );
/* bipred cost: satd of mc.avg( src0, src1, weight ) without storing it, against the
 * partition's fenc_pre (8-bit) or fenc (high bit depth, FENC_STRIDE); bi4 averages
 * src0 = pavg( src0a, src0b ) and src1 = pavg( src1a, src1b ), get_ref's unweighted
 * predictions from the hpel planes (see x264_mc_hpel_pair) */
#if HIGH_BIT_DEPTH
typedef pixel x264_bi_fenc_t;
#else
typedef int16_t x264_bi_fenc_t;
#endif
typedef int  (*x264_pixel_satd_bi_t) ( x264_bi_fenc_t *fenc, pixel *src0, intptr_t stride0,
                                       pixel *src1, intptr_t stride1, int weight );
typedef int  (*x264_pixel_satd_bi4_t) ( x264_bi_fenc_t *fenc, pixel *src0a, pixel *src0b,
                                        pixel *src1a, pixel *src1b, intptr_t stride, int weight );

enum
{
    PIXEL_16x16 = 0,
    PIXEL_16x8  = 1,
    PIXEL_8x16  = 2,
    PIXEL_8x8   = 3,
    PIXEL_8x4   = 4,
    PIXEL_4x8   = 5,
    PIXEL_4x4   = 6,

    /* Subsampled chroma only */
    PIXEL_4x16  = 7,  /* 4:2:2 */
    PIXEL_4x2   = 8,
    PIXEL_2x8   = 9,  /* 4:2:2 */
    PIXEL_2x4   = 10,
    PIXEL_2x2   = 11,
};

static const struct { uint8_t w, h; } x264_pixel_size[12] =
{
    { 16, 16 }, { 16, 8 }, { 8, 16 }, { 8, 8 }, { 8, 4 }, { 4, 8 }, { 4, 4 },
    {  4, 16 }, {  4, 2 }, { 2,  8 }, { 2, 4 }, { 2, 2 },
};

static const uint8_t x264_size2pixel[5][5] =
{
    { 0, },
    { 0, PIXEL_4x4, PIXEL_8x4, 0, 0 },
    { 0, PIXEL_4x8, PIXEL_8x8, 0, PIXEL_16x8 },
    { 0, },
    { 0, 0,        PIXEL_8x16, 0, PIXEL_16x16 }
};

static const uint8_t x264_luma2chroma_pixel[4][7] =
{
    { 0 },
    { PIXEL_8x8,   PIXEL_8x4,  PIXEL_4x8,  PIXEL_4x4, PIXEL_4x2, PIXEL_2x4, PIXEL_2x2 }, /* 4:2:0 */
    { PIXEL_8x16,  PIXEL_8x8,  PIXEL_4x16, PIXEL_4x8, PIXEL_4x4, PIXEL_2x8, PIXEL_2x4 }, /* 4:2:2 */
    { PIXEL_16x16, PIXEL_16x8, PIXEL_8x16, PIXEL_8x8, PIXEL_8x4, PIXEL_4x8, PIXEL_4x4 }, /* 4:4:4 */
};

typedef struct
{
    x264_pixel_cmp_t  sad[8];
    x264_pixel_cmp_t  ssd[8];
    x264_pixel_cmp_t satd[8];
    x264_pixel_cmp_avg2_t satd_avg2[7]; /* asm only, NULL otherwise */
    x264_pixel_cmp_avg2_t sad_avg2[7];  /* asm only, NULL otherwise */
    x264_pixel_satd_mcc_t satd_mcc;     /* asm only, NULL otherwise; widths 8 and 4, heights 4-16 */
    /* asm only, 8-bit only, NULL otherwise: satd_mcc's fenc, 64*fenc - 32 uv interleaved,
     * from the chroma fenc (FENC_STRIDE, u then v, height 8 or 16) into 512 words. Width 8:
     * row y at 16*y; width 4: chroma x 0 or 4, y 0 or 8 at 256 + 32*x + 8*y, rows y+k | y+k+4
     * 16 words apart; 4x4, height 8 only: x, y 0 or 4 at 128 + 8*x + 16*y, rows y | y+2
     * then y+1 | y+3. */
    void (*satd_mcc_fenc_pre)( int16_t *fenc_pre, pixel *fenc, int i_height );
    /* asm only, NULL otherwise. satd_fenc_pre[0] fills 256 words from a 16x16 fenc
     * (FENC_STRIDE) for the 16 wide sizes, 16 words a row; [1] 64 from an 8x8 for the
     * 8 wide ones, an 8x16 reading those of its two 8x8 consecutively. */
    void (*satd_fenc_pre[2])( int16_t *fenc_pre, pixel *fenc );
    x264_pixel_cmp_pre_t satd_pre[4];
    x264_pixel_cmp_avg2_pre_t satd_avg2_pre[4];
    x264_pixel_satd_bi_t  satd_bi[4];  /* asm only, NULL otherwise */
    x264_pixel_satd_bi4_t satd_bi4[4];
    x264_pixel_cmp_t ssim[7];
    x264_pixel_cmp_t sa8d[4];
    x264_pixel_cmp_t mbcmp[8]; /* either satd or sad for subpel refine and mode decision */
    x264_pixel_cmp_t mbcmp_unaligned[8]; /* unaligned mbcmp for subpel */
    x264_pixel_cmp_avg2_t mbcmp_avg2[7]; /* mbcmp of a qpel average, NULL where get_ref + mbcmp is used */
    x264_pixel_satd_mcc_t mbcmp_mcc;     /* satd_mcc where mbcmp is satd, else NULL */
    x264_pixel_cmp_pre_t mbcmp_pre[4];   /* satd_pre where mbcmp is satd, else NULL */
    x264_pixel_cmp_avg2_pre_t mbcmp_avg2_pre[4];
    x264_pixel_satd_bi_t  mbcmp_bi[4];  /* satd_bi where mbcmp is satd, else NULL */
    x264_pixel_satd_bi4_t mbcmp_bi4[4];
    x264_pixel_cmp_t fpelcmp[8]; /* either satd or sad for fullpel motion search */
    x264_pixel_cmp_avg2_t fpelcmp_avg2[7]; /* fpelcmp of a qpel average, NULL where get_ref + fpelcmp is used */
    x264_pixel_cmp_x3_t fpelcmp_x3[7];
    x264_pixel_cmp_x4_t fpelcmp_x4[7];
    x264_pixel_cmp_x3_min_t sad_x3_min[7]; /* asm only, NULL otherwise */
    x264_pixel_cmp_x4_min_t sad_x4_min[7];
    x264_pixel_cmp_x3_min_t fpelcmp_x3_min[7]; /* sad_x3_min where fpelcmp is sad, else NULL */
    x264_pixel_cmp_x4_min_t fpelcmp_x4_min[7];
    x264_pixel_cmp_sq_min_t sad_sq_min[7]; /* asm only, NULL otherwise; reference x264_pixel_sad_sq_min_c */
    x264_pixel_cmp_sq_min_t fpelcmp_sq_min[7]; /* sad_sq_min where fpelcmp is sad, else NULL */
    x264_pixel_cmp_t sad_aligned[8]; /* Aligned SAD for mbcmp */
    int (*vsad)( pixel *, intptr_t, int );
    int (*asd8)( pixel *pix1, intptr_t stride1, pixel *pix2, intptr_t stride2, int height );
    /* x264_weights_analyse chroma, per 8 x height block of a row of n: the sum and
     * min | max << 16; the sum of ( x * scale + ((1 << denom) >> 1) ) >> denom; the
     * sums of the u and v of an interleaved row; that of x264_clip_pixel( ( x * scale +
     * ((1 << denom) >> 1) ) >> denom + offset ), as mc weight. asm may do n rounded up
     * to 16. */
    void (*weightp_stats8)( int32_t *sum, uint32_t *minmax, pixel *src, intptr_t i_src, int n, int height );
    void (*weightp_sum8)( int32_t *sum, pixel *src, intptr_t i_src, int n, int height, int scale, int denom );
    void (*weightp_sum8_clip)( int32_t *sum, pixel *src, intptr_t i_src, int n, int height, int scale, int denom,
                               int offset );
    void (*weightp_sum8_nv)( int32_t *sumu, int32_t *sumv, pixel *src, intptr_t i_src, int n, int height );
    /* x264_weights_analyse luma: the sums of pix1 - pix2 over the 4x4 blocks of an 8x8,
     * in raster order */
    void (*weightp_dc8x8)( int32_t dc[4], pixel *pix1, intptr_t i_pix1, pixel *pix2, intptr_t i_pix2 );
    /* x264_weights_analyse luma search, a row of n 8x8 blocks of r and f: for k < nk <= 10,
     * wp[k] = { scale, denom, offset << (BIT_DEPTH-8), offsets (1 to 4) }, and j < offsets,
     * cost[k][j] += min( satd_8x8( w - f ), icost[i] << (BIT_DEPTH-8) ), w = x264_clip_pixel(
     * ((r * scale + ((1 << denom) >> 1)) >> denom) + offset + (j << (BIT_DEPTH-8)) ); the other
     * cost[k][j] are undefined. asm may read 24 pixels past the row. */
    void (*weightp_satd8_search)( uint32_t (*cost)[4], pixel *r, pixel *f, intptr_t i_stride, int n,
                                  uint16_t *icost, const int16_t (*wp)[4], int nk );
    /* x264_weights_analyse chroma 4:2:0/4:2:2, a row of n blocks of 8 x height (8 or 16) of the
     * interleaved ref: block i motion compensated as mc_chroma by mvs[i] (mvy as 2*mvy >> v_shift;
     * mvs NULL: none) into dst[0] (u) and dst[1] (v) + 8*i, with sum[p][i] and minmax[p][i] as
     * weightp_stats8 and, for slots q < 6 with ws[q][0] >= 0, of plane q/3, wsum[q][i] as
     * weightp_sum8 at scale ws[q][0], denom ws[q][1]. asm may read 64 bytes a row from each
     * block's position and the row below. */
    void (*weightp_chroma_ref_row)( pixel *dst[2], intptr_t i_stride, pixel *ref, int16_t (*mvs)[2], int n,
                                    int height, int32_t *sum[2], uint32_t *minmax[2], const int16_t (*ws)[2],
                                    int32_t *wsum[6] );
    uint64_t (*sa8d_satd[1])( pixel *pix1, intptr_t stride1, pixel *pix2, intptr_t stride2 );

    uint64_t (*var[4])( pixel *pix, intptr_t stride );
    int (*var2[4])( pixel *pix1, intptr_t stride1,
                    pixel *pix2, intptr_t stride2, int *ssd );
    uint64_t (*hadamard_ac[4])( pixel *pix, intptr_t stride );

    void (*ssd_nv12_core)( pixel *pixuv1, intptr_t stride1,
                           pixel *pixuv2, intptr_t stride2, int width, int height,
                           uint64_t *ssd_u, uint64_t *ssd_v );
    void (*ssim_4x4x2_core)( const pixel *pix1, intptr_t stride1,
                             const pixel *pix2, intptr_t stride2, int sums[2][4] );
    float (*ssim_end4)( int sum0[5][4], int sum1[5][4], int width );

    /* multiple parallel calls to cmp. */
    x264_pixel_cmp_x3_t sad_x3[7];
    x264_pixel_cmp_x4_t sad_x4[7];
    x264_pixel_cmp_x3_t satd_x3[7];
    x264_pixel_cmp_x4_t satd_x4[7];

    /* abs-diff-sum for successive elimination.
     * may round width up to a multiple of 16. */
    int (*ads[7])( int enc_dc[4], uint16_t *sums, int delta,
                   uint16_t *cost_mvx, int16_t *mvs, int width, int thresh );

    /* calculate satd or sad of V, H, and DC modes. */
    void (*intra_mbcmp_x3_16x16)( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_satd_x3_16x16) ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_sad_x3_16x16)  ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_mbcmp_x3_4x4)  ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_satd_x3_4x4)   ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_sad_x3_4x4)    ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_mbcmp_x3_chroma)( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_satd_x3_chroma) ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_sad_x3_chroma)  ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_mbcmp_x3_8x16c) ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_satd_x3_8x16c)  ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_sad_x3_8x16c)   ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_mbcmp_x3_8x8c)  ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_satd_x3_8x8c)   ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_sad_x3_8x8c)    ( pixel *fenc, pixel *fdec, int res[3] );
    void (*intra_mbcmp_x3_8x8)  ( pixel *fenc, pixel edge[36], int res[3] );
    void (*intra_sa8d_x3_8x8)   ( pixel *fenc, pixel edge[36], int res[3] );
    void (*intra_sad_x3_8x8)    ( pixel *fenc, pixel edge[36], int res[3] );
    /* find minimum satd or sad of all modes, and set fdec.
     * may be NULL, in which case just use pred+satd instead. */
    int (*intra_mbcmp_x9_4x4)( pixel *fenc, pixel *fdec, uint16_t *bitcosts );
    int (*intra_satd_x9_4x4) ( pixel *fenc, pixel *fdec, uint16_t *bitcosts );
    int (*intra_sad_x9_4x4)  ( pixel *fenc, pixel *fdec, uint16_t *bitcosts );
    int (*intra_mbcmp_x9_8x8)( pixel *fenc, pixel *fdec, pixel edge[36], uint16_t *bitcosts, uint16_t *satds );
    int (*intra_sa8d_x9_8x8) ( pixel *fenc, pixel *fdec, pixel edge[36], uint16_t *bitcosts, uint16_t *satds );
    int (*intra_sad_x9_8x8)  ( pixel *fenc, pixel *fdec, pixel edge[36], uint16_t *bitcosts, uint16_t *satds );
    /* asm only, NULL otherwise: slicetype's lowres intra cost of the 8x8 at src, all
     * its neighbours in the plane: the minimum satd of the 8x8c DC, H, V and P and the
     * 8x8 DDL..HU predictions (predict_8x8_filter edge). fenc: satd_fenc_pre[1]'s
     * (8-bit) or the fenc at FENC_STRIDE (high bit depth). */
    int (*intra_satd_lowres) ( void *fenc, pixel *src, intptr_t i_stride );
    int (*intra_mbcmp_lowres)( void *fenc, pixel *src, intptr_t i_stride ); /* intra_satd_lowres where mbcmp is satd, else NULL */
} x264_pixel_function_t;

#define x264_pixel_init x264_template(pixel_init)
void x264_pixel_init( int cpu, x264_pixel_function_t *pixf );
#define x264_pixel_sad_sq_min_c x264_template(pixel_sad_sq_min_c)
int x264_pixel_sad_sq_min_c( int i_pixel, pixel *fenc, pixel *pix, intptr_t i_stride, const int32_t bias[12], int best );
#define x264_pixel_ssd_nv12 x264_template(pixel_ssd_nv12)
void x264_pixel_ssd_nv12   ( x264_pixel_function_t *pf, pixel *pix1, intptr_t i_pix1, pixel *pix2, intptr_t i_pix2,
                             int i_width, int i_height, uint64_t *ssd_u, uint64_t *ssd_v );
#define x264_pixel_ssd_wxh x264_template(pixel_ssd_wxh)
uint64_t x264_pixel_ssd_wxh( x264_pixel_function_t *pf, pixel *pix1, intptr_t i_pix1, pixel *pix2, intptr_t i_pix2,
                             int i_width, int i_height );
#define x264_pixel_ssim_wxh x264_template(pixel_ssim_wxh)
float x264_pixel_ssim_wxh  ( x264_pixel_function_t *pf, pixel *pix1, intptr_t i_pix1, pixel *pix2, intptr_t i_pix2,
                             int i_width, int i_height, void *buf, int *cnt );
#define x264_field_vsad x264_template(field_vsad)
int x264_field_vsad( x264_t *h, int mb_x, int mb_y );

#endif
