/*****************************************************************************
 * lookahead8.h: 8-bit lowres analysis for high bit depth encodes
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

#ifndef X264_ENCODER_LOOKAHEAD8_H
#define X264_ENCODER_LOOKAHEAD8_H

/* With rc.b_lookahead_8bit, a high bit depth encoder keeps 8-bit copies of the
 * lowres planes (x264_frame_t.lowres8) and runs the per-MB lowres analysis with
 * the 8-bit pixel functions. These functions are only compiled into the 8-bit
 * pass, so they are not templated and use no depth dependent types: frames are
 * x264_frame_t pointers, whose layout is the same at every depth.
 *
 * Costs are computed and stored at 8-bit scale, which is what slicetype_mb_cost()
 * at high bit depth stores too (its costs are shifted down by BIT_DEPTH-8, as
 * upstream "Fix high bit depth lookahead cost compensation algorithm").
 * LOWRES8_COST_SHIFT maps high bit depth thresholds to 8-bit. */
#define LOWRES8_COST_SHIFT 2

/* One per x264_t that runs lowres analysis. stride/lines are the lowres plane
 * geometry (i_stride_lowres, i_lines_lowres), for the weighted plane buffer. */
void *x264_lowres8_init( const x264_param_t *param, int mb_width, int mb_height, int stride, int lines );
void  x264_lowres8_free( void *ctx );

/* The MB loop of slicetype_slice_cost over rows [slice_start, slice_end). weights
 * is the high bit depth x264_weight_t[3] of frames[b] (or x264_weight_none);
 * it is re-cached for the 8-bit weight functions. */
void  x264_lowres8_slice_cost( void *ctx, void **frames, int p0, int p1, int b,
                               int dist_scale_factor, int do_search[2], const void *weights,
                               int *output_inter, int *output_intra,
                               int slice_start, int slice_end );

/* Weight ref's 8-bit lowres plane (padding included) into the context's buffer
 * and point fenc->weighted8 at it, like the high bit depth weighted[0]. */
void  x264_lowres8_weight_plane( void *ctx, void *fenc, void *ref, const void *weight );

/* rc.b_weightp_8bit: the x264_weights_analyse cost functions at 8-bit, slice
 * header cost excluded. weight is a high bit depth x264_weight_t, NULL for none.
 * Luma: lowres8[], ref motion compensated into dst with the lowres MVs if any.
 * Chroma (4:2:0/4:2:2): ref8 is the 8-bit copy of ref's interleaved chroma plane
 * with its padding, motion compensated with the lowres MVs into dstu/dstv, the
 * planar layout of the high bit depth cost with fenc at +stride/2. */
uint8_t *x264_lowres8_weight_luma_mc( void *ctx, void *fenc, void *ref, uint8_t *dst );
unsigned x264_lowres8_weight_luma_cost( void *ctx, void *fenc, uint8_t *src, const void *weight );
void     x264_lowres8_weight_chroma_mc( void *ctx, void *fenc, void *ref, uint8_t *ref8,
                                        uint8_t *dstu, uint8_t *dstv, int v_shift );
unsigned x264_lowres8_weight_chroma_cost( void *ctx, void *fenc, uint8_t *src, const void *weight, int v_shift );

#endif
