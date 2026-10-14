/*****************************************************************************
 * weightp.h: weighted prediction analysis passes
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

#ifndef X264_ENCODER_WEIGHTP_H
#define X264_ENCODER_WEIGHTP_H

/* The x264_weights_analyse passes, on MB rows [mb_y0,mb_y1) of explicit planes, so
 * that they run in bands and, with rc.b_weightp_8bit, on the 8-bit copies of a high
 * bit depth encode (encoder/lookahead8.c). No depth dependent types: the planes are
 * of the pixels of the depth of the functions called. */
/* chroma weighted sums kept per plane, one per scale tried */
#define X264_WEIGHT_WSLOTS 3

typedef struct
{
    int mb_width;
    int mb_height;
    int16_t (*mvs)[2];      /* lowres MVs of fenc to ref, NULL: none searched */
    /* luma, lowres */
    void *fenc_luma;
    void *ref_luma[4];      /* with the hpel planes */
    void *mc_luma;          /* ref motion compensated, if mvs */
    intptr_t stride_luma;
    uint16_t *intra_cost;
    int intra_cost_shift;   /* scale of intra_cost to the depth of the passes */
    int32_t *lsum;          /* per MB of the ref luma, sum and min | max << 16, or NULL */
    uint32_t *lminmax;
    /* chroma 4:2:0/4:2:2 */
    void *fenc_chroma;      /* interleaved */
    void *ref_chroma;       /* interleaved, padded if mvs */
    void *dst[2];           /* ref motion compensated, u and v */
    intptr_t stride_chroma;
    int v_shift;
    /* per MB, rows of n16 = (mb_width + 15) & ~15 (X264_WEIGHT_SUMS of them) */
    int n16;
    int32_t *fsum[2];       /* fenc */
    int32_t *rsum[2];       /* ref */
    uint32_t *minmax[2];    /* ref, min | max << 16 */
    /* slot q of plane q / X264_WEIGHT_WSLOTS: the ref weighted at wscale[q], wdenom[q] (-1:
     * none), unclipped, - fsum[]; per MB row the offsets (<< BIT_DEPTH-8) no block clips
     * at, min and max */
    int32_t *wsum[2*X264_WEIGHT_WSLOTS];
    int32_t *orange[2*X264_WEIGHT_WSLOTS];
    int wscale[2*X264_WEIGHT_WSLOTS];
    int wdenom[2*X264_WEIGHT_WSLOTS];
    int wnext[2];           /* slot to replace */
} x264_weight_src_t;

/* The luma weights of a search: per scale its offsets, ascending and contiguous, cached
 * for the depth of the passes. Costs: [0] unweighted, [1 + k*X264_WEIGHT_OFFSETS_MAX + j]
 * of w[k][j], without the slice header cost. */
#define X264_WEIGHT_SCALES_MAX 9
#define X264_WEIGHT_OFFSETS_MAX 5
#define X264_WEIGHT_COSTS (1 + X264_WEIGHT_SCALES_MAX*X264_WEIGHT_OFFSETS_MAX)
typedef struct
{
    int i_scales;
    int i_offsets[X264_WEIGHT_SCALES_MAX];
    x264_weight_t w[X264_WEIGHT_SCALES_MAX][X264_WEIGHT_OFFSETS_MAX];
} x264_weight_trials_t;

/* Chroma 4:2:0/4:2:2, per plane: the trials and the slot of the scale of each, -1 for
 * none (costed when tried). Costs as above, [0] that of the ref. */
typedef struct
{
    x264_weight_trials_t t[2];
    int slot[2][X264_WEIGHT_SCALES_MAX];
} x264_weight_chroma_trials_t;

#define x264_weight_luma_mc_rows x264_template(weight_luma_mc_rows)
void x264_weight_luma_mc_rows( x264_t *h, x264_weight_src_t *s, int mb_y0, int mb_y1 );
/* src: ref_luma[0] or mc_luma, w: NULL or cached for this depth; no slice header cost */
#define x264_weight_luma_cost_rows x264_template(weight_luma_cost_rows)
unsigned int x264_weight_luma_cost_rows( x264_t *h, x264_weight_src_t *s, void *src, const x264_weight_t *w,
                                         int mb_y0, int mb_y1 );
/* Motion compensates into mc_luma if mvs (src is then mc_luma), and adds the costs of t
 * to cost[X264_WEIGHT_COSTS] */
#define x264_weight_luma_search_rows x264_template(weight_luma_search_rows)
void x264_weight_luma_search_rows( x264_t *h, x264_weight_src_t *s, void *src, const x264_weight_trials_t *t,
                                   unsigned int *cost, int mb_y0, int mb_y1 );
/* fsum[] */
#define x264_weight_chroma_fenc_rows x264_template(weight_chroma_fenc_rows)
void x264_weight_chroma_fenc_rows( x264_t *h, x264_weight_src_t *s, int mb_y0, int mb_y1 );
/* dst[], rsum[], minmax[] */
#define x264_weight_chroma_ref_rows x264_template(weight_chroma_ref_rows)
void x264_weight_chroma_ref_rows( x264_t *h, x264_weight_src_t *s, int mb_y0, int mb_y1 );
/* wsum[q] and orange[q] at wscale[q], wdenom[q] */
#define x264_weight_chroma_wsum_rows x264_template(weight_chroma_wsum_rows)
void x264_weight_chroma_wsum_rows( x264_t *h, x264_weight_src_t *s, int q, int mb_y0, int mb_y1 );
/* The whole plane of slot q; w: NULL or cached for this depth, at the scale and denom of
 * slot q; no slice header cost */
#define x264_weight_chroma_cost x264_template(weight_chroma_cost)
unsigned int x264_weight_chroma_cost( x264_t *h, x264_weight_src_t *s, int q, const x264_weight_t *w );
/* Adds the costs of ct with a slot, and those of the refs, to cost[plane][X264_WEIGHT_COSTS],
 * after the wsum of the slots; weights cached for this depth; no slice header cost */
#define x264_weight_chroma_search_rows x264_template(weight_chroma_search_rows)
void x264_weight_chroma_search_rows( x264_t *h, x264_weight_src_t *s, const x264_weight_chroma_trials_t *ct,
                                     unsigned int (*cost)[X264_WEIGHT_COSTS], int mb_y0, int mb_y1 );

#endif
