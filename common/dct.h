/*****************************************************************************
 * dct.h: transform and zigzag
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

#ifndef X264_DCT_H
#define X264_DCT_H

typedef struct
{
    // pix1  stride = FENC_STRIDE
    // pix2  stride = FDEC_STRIDE
    // p_dst stride = FDEC_STRIDE
    void (*sub4x4_dct)   ( dctcoef dct[16], pixel *pix1, pixel *pix2 );
    void (*add4x4_idct)  ( pixel *p_dst, dctcoef dct[16] );

    void (*sub8x8_dct)   ( dctcoef dct[4][16], pixel *pix1, pixel *pix2 );
    void (*sub8x8_dct_dc)( dctcoef dct[4], pixel *pix1, pixel *pix2 );
    void (*add8x8_idct)  ( pixel *p_dst, dctcoef dct[4][16] );
    void (*add8x8_idct_dc) ( pixel *p_dst, dctcoef dct[4] );

    void (*sub8x16_dct_dc)( dctcoef dct[8], pixel *pix1, pixel *pix2 );

    void (*sub16x16_dct) ( dctcoef dct[16][16], pixel *pix1, pixel *pix2 );
    void (*add16x16_idct)( pixel *p_dst, dctcoef dct[16][16] );
    void (*add16x16_idct_dc) ( pixel *p_dst, dctcoef dct[16] );

    void (*sub8x8_dct8)  ( dctcoef dct[64], pixel *pix1, pixel *pix2 );
    void (*add8x8_idct8) ( pixel *p_dst, dctcoef dct[64] );

    void (*sub16x16_dct8) ( dctcoef dct[4][64], pixel *pix1, pixel *pix2 );
    void (*add16x16_idct8)( pixel *p_dst, dctcoef dct[4][64] );

    void (*dct4x4dc) ( dctcoef d[16] );
    void (*idct4x4dc)( dctcoef d[16] );

    void (*dct2x4dc)( dctcoef dct[8], dctcoef dct4x4[8][16] );

} x264_dct_function_t;

/* quant_4x4 and dequant_4x4 of one list at one qp, for intra_satd_x9_4x4_recon.
 * dequant: (dct * dq) << 0, or (dct * dq + dq_round) >> dq_shift if dq_shift */
typedef struct
{
    ALIGNED_64( udctcoef mf[16] );
    udctcoef bias[16];
    dctcoef  dq[16];
    int      dq_shift;
    int      dq_round;
} x264_quant4_recon_t;

typedef struct
{
    void (*scan_8x8)( dctcoef level[64], dctcoef dct[64] );
    void (*scan_4x4)( dctcoef level[16], dctcoef dct[16] );
    int  (*sub_8x8)  ( dctcoef level[64], const pixel *p_src, pixel *p_dst );
    int  (*sub_4x4)  ( dctcoef level[16], const pixel *p_src, pixel *p_dst );
    int  (*sub_4x4ac)( dctcoef level[16], const pixel *p_src, pixel *p_dst, dctcoef *dc );
    void (*interleave_8x8_cavlc)( dctcoef *dst, dctcoef *src, uint8_t *nnz );
    /* quant_4x4x4, then scan_4x4, dequant_4x4 (skipped if dequant_mf is NULL) and decimate_score16
     * (15 for _ac) of the nonzero blocks. Returns nz | min(summed score, 9) << 4. */
    int  (*quant_4x4x4_scan)   ( dctcoef dct[4][16], dctcoef level[4][16], udctcoef mf[16], udctcoef bias[16],
                                 int dequant_mf[6][16], int i_qp );
    int  (*quant_4x4x4_scan_ac)( dctcoef dct[4][16], dctcoef level[4][16], udctcoef mf[16], udctcoef bias[16],
                                 int dequant_mf[6][16], int i_qp );
    /* quant_8x8, then if nonzero scan_8x8, decimate_score64 and dequant_8x8 (skipped if dequant_mf is NULL).
     * Returns 0, or 1 | min(score, 9) << 4. */
    int  (*quant_8x8_scan)( dctcoef dct[64], dctcoef level[64], udctcoef mf[64], udctcoef bias[64],
                            int dequant_mf[6][64], int i_qp );
    /* intra_satd_x9_4x4; if the cost is <= limit, the chosen mode is then coded: sub4x4_dct, quant_4x4,
     * and if nonzero scan_4x4 into level, dequant_4x4 and add4x4_idct. Returns cost | mode << 16 | nz << 24. */
    int  (*intra_satd_x9_4x4_recon)( pixel *fenc, pixel *fdec, uint16_t *bitcosts, dctcoef level[16],
                                     x264_quant4_recon_t *q, int limit );
    /* probe_skip, asm only (NULL otherwise). Luma, references x264_probe_skip_luma_c: 2 if fenc == fdec over
     * 16x16, else 0 if sub8x8_dct + quant_4x4x4_scan over the four 8x8s sum to a score >= 6, else 1.
     * thr: zscreen_thr of mf/bias. */
    int  (*probe_skip_luma)( pixel *fenc, pixel *fdec, udctcoef mf[16], udctcoef bias[16], const int32_t thr[4] );
    /* chroma plane, 8x8 [0] or 8x16 [1], references x264_probe_skip_chroma_c: 1 if ssd < thresh, 0 if
     * quant_2x2_dc( dc_mf, dc_bias ) of the DC transform is nonzero, 1 if ssd < 4*thresh, else 0 if
     * quant_4x4x4_scan_ac over the 8x8s (DCs zeroed) sums to a score >= 7, else 1. thr: zscreen_thr of mf/bias. */
    int  (*probe_skip_chroma[2])( pixel *fenc, pixel *fdec, udctcoef mf[16], udctcoef bias[16], int thresh,
                                  int dc_mf, int dc_bias, const int32_t thr[4] );

} x264_zigzag_function_t;

#define x264_dct_init x264_template(dct_init)
void x264_dct_init( int cpu, x264_dct_function_t *dctf );
void x264_dct_init_weights( void );
#define x264_zigzag_init x264_template(zigzag_init)
void x264_zigzag_init( int cpu, x264_zigzag_function_t *pf_progressive, x264_zigzag_function_t *pf_interlaced );
#define x264_probe_skip_luma_c x264_template(probe_skip_luma_c)
int x264_probe_skip_luma_c( pixel *fenc, pixel *fdec, udctcoef mf[16], udctcoef bias[16], int b_field );
#define x264_probe_skip_chroma_c x264_template(probe_skip_chroma_c)
int x264_probe_skip_chroma_c( pixel *fenc, pixel *fdec, udctcoef mf[16], udctcoef bias[16], int thresh,
                              int dc_mf, int dc_bias, int chroma422, int b_field );

#endif
