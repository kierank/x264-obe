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
typedef struct x264_lowres_p x264_lowres_p_t;
typedef struct x264_analyse_p x264_analyse_p_t;

typedef int  (*x264_pixel_cmp_t) ( pixel *, intptr_t, pixel *, intptr_t );
typedef void (*x264_pixel_cmp_x3_t) ( pixel *, pixel *, pixel *, pixel *, intptr_t, int[3] );
typedef void (*x264_pixel_cmp_x4_t) ( pixel *, pixel *, pixel *, pixel *, pixel *, intptr_t, int[4] );
/* min( best, (cmp( fenc, pix_i ) << 6) + bias_i ), compared as int; bias01 = bias_0 | bias_1 << 32,
 * x3: bias2_best = bias_2 | best << 32, x4: bias23 = bias_2 | bias_3 << 32 and best */
typedef int  (*x264_pixel_cmp_x3_min_t) ( pixel *, pixel *, pixel *, pixel *, intptr_t, uint64_t bias01, uint64_t bias2_best );
typedef int  (*x264_pixel_cmp_x4_min_t) ( pixel *, pixel *, pixel *, pixel *, pixel *, intptr_t, uint64_t bias01, uint64_t bias23, int best );
/* the same over the 12 candidates pix + dx + dy*stride, dx -1..2, bias[] by dy -1, 1, 0 */
typedef int  (*x264_pixel_cmp_sq_min_t) ( pixel *fenc, pixel *pix, intptr_t, const int32_t bias[12], int best );
/* min( best, (sad_i << s) + bias[i] ) over the candidates pix + dx_i + dy_i*stride:
 * dia: (0,-1) (0,1) (-1,0) (1,0), s = 4; hex: hex2[1..6] of me.c, s = 6 */
typedef int  (*x264_pixel_cmp_pt_min_t) ( pixel *fenc, pixel *pix, intptr_t, const int32_t *bias, int best );
/* x4_min over the halfpel diamond: pixv, pixv + stride, pixh, pixh + 1 */
typedef int  (*x264_pixel_cmp_hpel_min_t) ( pixel *fenc, pixel *pixv, pixel *pixh, intptr_t, uint64_t bias01, uint64_t bias23, int best );
/* 1 if the block at fenc (FENC_STRIDE) equals that at fdec (FDEC_STRIDE), else 0 */
typedef int  (*x264_pixel_fenc_eq_t) ( pixel *fenc, pixel *fdec );
/* r = fenc (FENC_STRIDE) - fdec (FDEC_STRIDE) over 16x16: bit 4*i8x8+i4x4 set if every coefficient of that
 * 4x4 quantises to 0 by 16*sum(r^2) - sum(r)^2 <= thr[0] and |sum(r)| < thr[1]; e8: sum(r^2) of each 8x8 */
typedef int  (*x264_pixel_zscreen_t) ( pixel *fenc, pixel *fdec, const int32_t thr[2], int32_t e8[4] );
/* me.c's whole dia search (hex: hexagon, half hexagons, square refine) from bmv = pack16to32_mask( bmx, bmy )
 * at bcost; ref at mv 0, costs cost_mvx[mx<<2] + cost_mvy[my<<2], iters i_me_range, range me.c's
 * mv_min | mv_max << 32. Returns bcost | pack16to32_mask( bmx, bmy ) << 32 */
typedef uint64_t (*x264_pixel_fpel_search_t) ( pixel *fenc, pixel *ref, intptr_t, const uint16_t *cost_mvx,
                                               const uint16_t *cost_mvy, uint32_t bmv, int bcost, int iters, uint64_t range );
/* x264_predictor_clip/roundclip that also drop the candidates whose clipped mv equals pmv or
 * that of an earlier one kept; i_mvc <= 15, writes 16 */
typedef int  (*x264_predictor_clip_t) ( int16_t (*dst)[2], int16_t (*mvc)[2], int i_mvc, int16_t mv_limit[2][2], uint32_t pmv );
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
/* refine_subpel's luma qpel diamond, satd + cost_mvx[mx] + cost_mvy[my], from bmv =
 * pack16to32_mask( bmx, bmy ) at bcost over the unweighted hpel planes fref[0..3]:
 * iters >> 8 steps over (0,-1) (0,1) (-1,0) (1,0), the incumbent winning ties, then the
 * lower dir; a step skips the way back unless iters & 16; stops at an mv on or past
 * range = mv_min_spel | mv_max_spel << 32 (x | y << 16 each). fenc as satd_bi's.
 * Returns bcost | pack16to32_mask( bmx, bmy ) << 32 */
typedef uint64_t (*x264_pixel_qpel_search_t) ( x264_bi_fenc_t *fenc, pixel **fref, intptr_t stride,
                                               const uint16_t *cost_mvx, const uint16_t *cost_mvy,
                                               uint32_t bmv, int bcost, int iters, uint64_t range );
/* refine_subpel up to its qpel stage for a luma-only unweighted search with satd mbcmp
 * and sad fpelcmp, from bmv at bcost: with iters & 32, the mvp clipped to range shrunk
 * by 2 is tried, sad + mv cost, if it moves; (iters >> 16) & 255 hpel diamond steps of
 * sad + mv cost over (0,-2) (0,2) (-2,0) (2,0), the incumbent winning ties, then the
 * lower dir; bcost is then the satd + mv cost at the mv, unless iters & 16 (b_refine_qpel:
 * no re-cost, and qpel skips no way back). With halfpel_thresh: if
 * (bcost*7)>>3 > *halfpel_thresh, returns bcost | 1 << 31 (the multi-ref stop), else
 * lowers *halfpel_thresh to bcost. Then, if iters & 0xff00, returns
 * qpel( qfenc, fref, stride, cost_mvx, cost_mvy, bmv, bcost, iters, range ). fenc for
 * sad at FENC_STRIDE, qfenc as satd_qpel_search's. Returns as x264_pixel_qpel_search_t */
typedef uint64_t (*x264_pixel_subpel_search_t) ( pixel *fenc, pixel **fref, intptr_t stride,
                                                 const uint16_t *cost_mvx, const uint16_t *cost_mvy,
                                                 uint32_t bmv, int bcost, int iters, uint64_t range,
                                                 x264_bi_fenc_t *qfenc, x264_pixel_qpel_search_t qpel,
                                                 int *halfpel_thresh, uint32_t mvp );
/* the same with the luma weight w (weightfn set): each candidate's prediction is
 * get_ref's with w, mc_weight of the average; qpel gets w */
struct x264_weight_t;
typedef uint64_t (*x264_pixel_qpel_search_weight_t) ( x264_bi_fenc_t *fenc, pixel **fref, intptr_t stride,
                                                      const uint16_t *cost_mvx, const uint16_t *cost_mvy,
                                                      uint32_t bmv, int bcost, int iters, uint64_t range,
                                                      const struct x264_weight_t *w );
typedef uint64_t (*x264_pixel_subpel_search_weight_t) ( pixel *fenc, pixel **fref, intptr_t stride,
                                                        const uint16_t *cost_mvx, const uint16_t *cost_mvy,
                                                        uint32_t bmv, int bcost, int iters, uint64_t range,
                                                        x264_bi_fenc_t *qfenc, x264_pixel_qpel_search_weight_t qpel,
                                                        int *halfpel_thresh, uint32_t mvp, const struct x264_weight_t *w );

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
    x264_pixel_qpel_search_t satd_qpel_search[4]; /* asm only, NULL otherwise; reference x264_pixel_satd_qpel_search_c */
    x264_pixel_subpel_search_t satd_subpel_search[4]; /* asm only, NULL otherwise; reference x264_pixel_satd_subpel_search_c */
    x264_pixel_qpel_search_weight_t satd_qpel_search_weight[4]; /* asm only, NULL otherwise; reference x264_pixel_satd_qpel_search_weight_c */
    x264_pixel_subpel_search_weight_t satd_subpel_search_weight[4]; /* asm only, NULL otherwise; reference x264_pixel_satd_subpel_search_weight_c */
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
    x264_pixel_qpel_search_t mbcmp_qpel_search[4]; /* satd_qpel_search where mbcmp is satd, else NULL */
    x264_pixel_subpel_search_t mbcmp_subpel_search[4]; /* satd_subpel_search where mbcmp is satd and fpelcmp sad, else NULL */
    x264_pixel_subpel_search_weight_t mbcmp_subpel_search_weight[4]; /* satd_subpel_search_weight where mbcmp_subpel_search is set, else NULL */
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
    /* asm only, NULL otherwise; references x264_pixel_sad_{dia,hex,oct,ring}_min_c. umh, s = 4:
     * oct (0,-2) (-1,-1) (1,-1) (-2,0) (2,0) (-1,1) (1,1) (0,2), ring (-1,-2) (1,-2) (-2,-1) (2,-1)
     * (-2,1) (2,1) (-1,2) (1,2) */
    x264_pixel_cmp_pt_min_t sad_dia_min[7];
    x264_pixel_cmp_pt_min_t sad_hex_min[7];
    x264_pixel_cmp_pt_min_t sad_oct_min[7];
    x264_pixel_cmp_pt_min_t sad_ring_min[7];
    x264_pixel_cmp_pt_min_t fpelcmp_dia_min[7]; /* sad_*_min where fpelcmp is sad, else NULL */
    x264_pixel_cmp_pt_min_t fpelcmp_hex_min[7];
    x264_pixel_cmp_pt_min_t fpelcmp_oct_min[7];
    x264_pixel_cmp_pt_min_t fpelcmp_ring_min[7];
    x264_pixel_cmp_hpel_min_t sad_hpel_min[7]; /* asm only, NULL otherwise; reference x264_pixel_sad_hpel_min_c */
    x264_pixel_cmp_hpel_min_t fpelcmp_hpel_min[7]; /* sad_hpel_min where fpelcmp is sad, else NULL */
    x264_pixel_fenc_eq_t fenc_eq[7]; /* 16x16, 8x16, 8x8; asm only, NULL otherwise; reference x264_pixel_fenc_eq_c */
    x264_pixel_zscreen_t zscreen_16x16; /* asm only, NULL otherwise; reference x264_pixel_zscreen_c */
    /* asm only, NULL otherwise; references x264_pixel_sad_{dia,hex}_search_c */
    x264_pixel_fpel_search_t sad_dia_search[7];
    x264_pixel_fpel_search_t sad_hex_search[7];
    x264_pixel_fpel_search_t fpelcmp_dia_search[7]; /* sad_*_search where fpelcmp is sad, else NULL */
    x264_pixel_fpel_search_t fpelcmp_hex_search[7];
    /* asm only, NULL otherwise; references x264_predictor_{clip,roundclip}_c */
    x264_predictor_clip_t predictor_clip;
    x264_predictor_clip_t predictor_roundclip;
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
     * cost[k][j] are undefined. Reads up to 24 pixels past the row. asm only, NULL otherwise
     * (x264_weight_luma_search_rows). */
    void (*weightp_satd8_search)( uint32_t (*cost)[4], pixel *r, pixel *f, intptr_t i_stride, int n,
                                  uint16_t *icost, const int16_t (*wp)[4], int nk );
    uint64_t (*sa8d_satd[1])( pixel *pix1, intptr_t stride1, pixel *pix2, intptr_t stride2 );

    uint64_t (*var[4])( pixel *pix, intptr_t stride );
    int (*var2[4])( pixel *pix1, intptr_t stride1,
                    pixel *pix2, intptr_t stride2, int *ssd );
    uint64_t (*hadamard_ac[4])( pixel *pix, intptr_t stride );
    /* asm only, NULL otherwise. rd ssd_mb with psy, MB cache layout: res = { ssd 16x16,
     * ssd u + ssd v, hadamard_ac[PIXEL_16x16]( fdec ) low, high }. u is 8 wide at fenc_uv /
     * fdec_uv, v at +8 / +16; [0] 4:2:0 (8 rows), [1] 4:2:2 (16 rows) */
    void (*ssd_psy_mb[2])( int res[4], pixel *fenc, pixel *fdec, pixel *fenc_uv, pixel *fdec_uv );

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
    /* asm only, 8-bit only, NULL otherwise; reference x264_lowres_p_mbs_c (encoder/me.h) */
    void (*lowres_p_mbs)( x264_lowres_p_t *c );
    /* asm only, NULL otherwise; encoder/analyse.c's P partition analysis, see x264_analyse_p_t */
    int  (*analyse_p16x16)( x264_analyse_p_t *c );
    void (*analyse_p_sub16x16)( x264_analyse_p_t *c );
    int  (*analyse_p16x16_ll)( x264_analyse_p_t *c ); /* analyse_p16x16 where subme < 3, not 4:4:4, else NULL */
} x264_pixel_function_t;

#define x264_pixel_init x264_template(pixel_init)
void x264_pixel_init( int cpu, x264_pixel_function_t *pixf );
#define x264_pixel_sad_sq_min_c x264_template(pixel_sad_sq_min_c)
int x264_pixel_sad_sq_min_c( int i_pixel, pixel *fenc, pixel *pix, intptr_t i_stride, const int32_t bias[12], int best );
#define x264_pixel_sad_dia_min_c x264_template(pixel_sad_dia_min_c)
int x264_pixel_sad_dia_min_c( int i_pixel, pixel *fenc, pixel *pix, intptr_t i_stride, const int32_t bias[4], int best );
#define x264_pixel_sad_hex_min_c x264_template(pixel_sad_hex_min_c)
int x264_pixel_sad_hex_min_c( int i_pixel, pixel *fenc, pixel *pix, intptr_t i_stride, const int32_t bias[6], int best );
#define x264_pixel_sad_oct_min_c x264_template(pixel_sad_oct_min_c)
int x264_pixel_sad_oct_min_c( int i_pixel, pixel *fenc, pixel *pix, intptr_t i_stride, const int32_t bias[8], int best );
#define x264_pixel_sad_ring_min_c x264_template(pixel_sad_ring_min_c)
int x264_pixel_sad_ring_min_c( int i_pixel, pixel *fenc, pixel *pix, intptr_t i_stride, const int32_t bias[8], int best );
#define x264_pixel_sad_hpel_min_c x264_template(pixel_sad_hpel_min_c)
int x264_pixel_sad_hpel_min_c( int i_pixel, pixel *fenc, pixel *pixv, pixel *pixh, intptr_t i_stride,
                               uint64_t bias01, uint64_t bias23, int best );
#define x264_pixel_fenc_eq_c x264_template(pixel_fenc_eq_c)
int x264_pixel_fenc_eq_c( int i_pixel, pixel *fenc, pixel *fdec );
#define x264_pixel_zscreen_c x264_template(pixel_zscreen_c)
int x264_pixel_zscreen_c( pixel *fenc, pixel *fdec, const int32_t thr[2], int32_t e8[4] );
#define x264_pixel_sad_dia_search_c x264_template(pixel_sad_dia_search_c)
uint64_t x264_pixel_sad_dia_search_c( int i_pixel, pixel *fenc, pixel *ref, intptr_t i_stride, const uint16_t *cost_mvx,
                                      const uint16_t *cost_mvy, uint32_t bmv, int bcost, int iters, uint64_t range );
#define x264_pixel_sad_hex_search_c x264_template(pixel_sad_hex_search_c)
uint64_t x264_pixel_sad_hex_search_c( int i_pixel, pixel *fenc, pixel *ref, intptr_t i_stride, const uint16_t *cost_mvx,
                                      const uint16_t *cost_mvy, uint32_t bmv, int bcost, int iters, uint64_t range );
#define x264_pixel_satd_qpel_search_c x264_template(pixel_satd_qpel_search_c)
uint64_t x264_pixel_satd_qpel_search_c( int i_pixel, pixel *fenc, pixel **fref, intptr_t stride, const uint16_t *cost_mvx,
                                        const uint16_t *cost_mvy, uint32_t bmv, int bcost, int iters, uint64_t range );
#define x264_pixel_satd_subpel_search_c x264_template(pixel_satd_subpel_search_c)
uint64_t x264_pixel_satd_subpel_search_c( int i_pixel, pixel *fenc, pixel **fref, intptr_t stride, const uint16_t *cost_mvx,
                                          const uint16_t *cost_mvy, uint32_t bmv, int bcost, int iters, uint64_t range,
                                          int *halfpel_thresh, uint32_t mvp );
#define x264_pixel_satd_qpel_search_weight_c x264_template(pixel_satd_qpel_search_weight_c)
uint64_t x264_pixel_satd_qpel_search_weight_c( int i_pixel, pixel *fenc, pixel **fref, intptr_t stride, const uint16_t *cost_mvx,
                                               const uint16_t *cost_mvy, uint32_t bmv, int bcost, int iters, uint64_t range,
                                               const struct x264_weight_t *w );
#define x264_pixel_satd_subpel_search_weight_c x264_template(pixel_satd_subpel_search_weight_c)
uint64_t x264_pixel_satd_subpel_search_weight_c( int i_pixel, pixel *fenc, pixel **fref, intptr_t stride, const uint16_t *cost_mvx,
                                                 const uint16_t *cost_mvy, uint32_t bmv, int bcost, int iters, uint64_t range,
                                                 int *halfpel_thresh, uint32_t mvp, const struct x264_weight_t *w );
#define x264_predictor_clip_c x264_template(predictor_clip_c)
int x264_predictor_clip_c( int16_t (*dst)[2], int16_t (*mvc)[2], int i_mvc, int16_t mv_limit[2][2], uint32_t pmv );
#define x264_predictor_roundclip_c x264_template(predictor_roundclip_c)
int x264_predictor_roundclip_c( int16_t (*dst)[2], int16_t (*mvc)[2], int i_mvc, int16_t mv_limit[2][2], uint32_t pmv );
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
